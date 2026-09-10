`timescale 1ns/1ps
import pbit_pkg::*;
module tb_chimera_problem;
    `include "problem.svh"
    localparam realtime CLK_PERIOD = 1s / real'(CLK_FREQ_HZ);
    localparam realtime BIT_TIME = (CLK_FREQ_HZ / BAUD_RATE) * CLK_PERIOD;
    logic clk=0, rst_n=0, uart_mode=0, rx=1;
    always #(CLK_PERIOD/2) clk=~clk;
    logic wr_en=0, rd_en=0;
    logic [15:0] addr=0;
    logic [31:0] wdata=0;
    wire tx, access_error, cfg_busy, run_busy, run_done;
    wire run_accept, sweep_done, phase_start, phase;
    wire [31:0] rdata;
    wire [I0_LEVEL_WIDTH-1:0] i0;
    wire [N_SPIN-1:0] spins;
    wire [BANK_ROWS*BANK_COLS-1:0] bank_done;
    chimera_problem_harness dut (.*);

    logic [55:0] program_mem [P_COMMANDS];
    logic initial_bits [P_N];
    integer chain_start [P_CHAINS+1], chain_nodes [P_CHAIN_NODES];
    integer graph_a [(P_EDGES>0)?P_EDGES:1], graph_b [(P_EDGES>0)?P_EDGES:1];
    integer graph_w [(P_EDGES>0)?P_EDGES:1];
    integer clause_start [P_CLAUSES+1], literals [(P_LITERALS>0)?P_LITERALS:1];
    integer sweep_i0 [P_SWEEPS];
    logic [P_CHAINS-1:0] decoded, best_decoded;
    logic [P_N-1:0] final_spins, best_spins;
    integer run_index=0, sweeps_seen=0, phases_seen=0, transactions=0;
    integer best_sweep=0, first_success=0, best_broken=0, csv_file, state_file;
    integer min_score=-1, successful_runs=0;
    longint signed best_score=-1, current_score=0, overall_best=-1;
    longint unsigned cycle=0, start_cycle=0, best_cycle=0, first_success_cycle=0;
    longint unsigned final_cycle=0;
    bit running=0;
    string data_dir="tb/chimera_generated";

    function automatic string required_file(input string name);
        string path;
        integer handle;
        path=$sformatf("%s/%s",data_dir,name);
        handle=$fopen(path,"r");
        if(!handle) $fatal(1,"Missing generated input: %s",path);
        $fclose(handle);
        return path;
    endfunction

    task automatic send_byte(input logic [7:0] value);
        rx=0; #(BIT_TIME);
        for(int b=0;b<8;b++) begin rx=value[b]; #(BIT_TIME); end
        rx=1; #(BIT_TIME);
    endtask
    task automatic receive_byte(output logic [7:0] value);
        @(negedge tx); #(BIT_TIME/2);
        if(tx!==0) $fatal(1,"UART start");
        for(int b=0;b<8;b++) begin #(BIT_TIME); value[b]=tx; end
        #(BIT_TIME);
        if(tx!==1) $fatal(1,"UART stop");
    endtask
    task automatic access_reg(input bit write_access, input logic [15:0] address,
                              input logic [31:0] value, output logic [31:0] result);
        logic [55:0] request, response;
        logic [7:0] received;
        integer waited;
        if(uart_mode) begin
            request={write_access ? 8'd1 : 8'd2,address,value}; response=0;
            fork
                begin
                    for(int b=6;b>=0;b--) send_byte(request[b*8+:8]);
                end
                begin
                    for(int b=6;b>=0;b--) begin
                        receive_byte(received); response[b*8+:8]=received;
                    end
                end
            join
            if(response[55:32]!=={8'd0,address})
                $fatal(1,"UART response addr=%h response=%h",address,response);
            result=response[31:0];
            #(2*BIT_TIME);
        end else begin
            @(negedge clk);
            addr=address; wdata=value; wr_en=write_access; rd_en=!write_access;
            // The bus response is registered. It captures pre-clear RC status.
            @(posedge clk); #(CLK_PERIOD/4);
            if(access_error!==0) $fatal(1,"Register access error addr=%h data=%h",address,value);
            result=rdata;
            @(negedge clk); wr_en=0; rd_en=0;
        end
        // Observe handshake completion, not a fixed delay that assumes bank depth.
        waited=0;
        while(cfg_busy) begin
            @(negedge clk); waited++;
            if(waited>1000) $fatal(1,"Configuration timeout addr=%h",address);
        end
        transactions++;
    endtask
    task automatic wr(input logic [15:0] address, input logic [31:0] value);
        logic [31:0] ignored;
        access_reg(1,address,value,ignored);
    endtask
    task automatic check(input logic [15:0] address, input logic [31:0] expected);
        logic [31:0] actual;
        access_reg(0,address,0,actual);
        if(actual!==expected) $fatal(1,"Readback addr=%h got=%h expected=%h transaction=%0d",address,actual,expected,transactions);
    endtask

    task automatic evaluate(input logic [P_N-1:0] state, output longint signed value,
                            output integer broken, output integer ties);
        integer total;
        bit differs, satisfied;
        value=0; broken=0; ties=0;
        if((^state)===1'bx) $fatal(1,"Unknown spin in array");
        for(int v=0;v<P_CHAINS;v++) begin
            total=0; differs=0;
            for(int k=chain_start[v];k<chain_start[v+1];k++) begin
                total += state[chain_nodes[k]] ? 1 : -1;
                if(state[chain_nodes[k]]!=state[chain_nodes[chain_start[v]]]) differs=1;
            end
            decoded[v]=(total>=0); // Match the Python chain tie rule: +1.
            if(total==0) ties++;
            if(differs) broken++;
        end
        if(P_SAT) begin
            for(int c=0;c<P_CLAUSES;c++) begin
                satisfied=0;
                for(int k=clause_start[c];k<clause_start[c+1];k++) begin
                    if(literals[k]>0) satisfied |= decoded[literals[k]-1];
                    else satisfied |= !decoded[-literals[k]-1];
                end
                if(satisfied) value++;
            end
        end else begin
            for(int e=0;e<P_EDGES;e++)
                if(decoded[graph_a[e]]!=decoded[graph_b[e]]) value+=graph_w[e];
        end
    endtask

    // Sample after nodes committed, at the controller's complete-sweep event.
    // No UART latency or configuration clocks enter these cycle measurements.
    always @(posedge clk) begin : MONITOR
        integer broken, ties;
        cycle++;
        if(rst_n && run_accept) begin
            if(running) $fatal(1,"Duplicate RUN acceptance");
            start_cycle=cycle; running=1;
        end
        if(rst_n && running) begin
            if(phase_start) begin
                if(phase!==(phases_seen%2)) $fatal(1,"Incorrect two-color phase order");
                phases_seen++;
            end
            if((|bank_done) && !(&bank_done)) $fatal(1,"BANK completion mismatch");
            if(sweep_done) begin
                if(sweeps_seen>=P_SWEEPS) $fatal(1,"Too many sweeps");
                if(i0!==I0_LEVEL_WIDTH'(sweep_i0[sweeps_seen])) $fatal(1,"Anneal schedule mismatch sweep=%0d i0=%0d expected=%0d",sweeps_seen+1,i0,sweep_i0[sweeps_seen]);
                sweeps_seen++;
                evaluate(spins,current_score,broken,ties);
                final_cycle=cycle-start_cycle;
                if(current_score>best_score) begin
                    best_score=current_score; best_sweep=sweeps_seen;
                    best_cycle=final_cycle; best_broken=broken; best_decoded=decoded; best_spins=spins;
                    $display("[CHIMERA_SWEEP] run=%0d sweep=%0d cycles=%0d score=%0d best=%0d target=%0d broken=%0d ties=%0d i0=%0d",run_index,sweeps_seen,final_cycle,current_score,best_score,P_TARGET,broken,ties,i0);
                end
                if(current_score>=P_TARGET && first_success==0) begin
                    first_success=sweeps_seen; first_success_cycle=final_cycle;
                end
                $fdisplay(csv_file,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",run_index,sweeps_seen,final_cycle,current_score,best_score,P_TARGET,broken,ties,i0);
                if(sweeps_seen==P_SWEEPS) running=0;
            end
        end
    end

    task automatic snapshot_check(input logic [P_N-1:0] expected);
        logic [31:0] actual, want, status;
        integer flat;
        for(int page=0;page<SPIN_ADDR_MAX;page++) begin
            wr('h10,page); wr(0,1<<SNAPSHOT_LATCH_LSB);
            repeat(4) @(negedge clk);
            access_reg(0,8,0,status);
            if(!status[SNAPSHOT_VALID_LSB]) $fatal(1,"Snapshot valid missing page=%0d",page);
            for(int word_idx=0;word_idx<SPIN_RDATA_REG_NUM;word_idx++) begin
                want=0;
                for(int b=0;b<32;b++) begin
                    flat=page*SNAPSHOT_WIDTH+word_idx*32+b;
                    if(flat<P_N) want[b]=expected[flat];
                end
                access_reg(0,16'('ha8+word_idx*4),0,actual);
                if(actual!==want) $fatal(1,"Snapshot page=%0d word=%0d actual=%h expected=%h",page,word_idx,actual,want);
            end
        end
    endtask

    initial begin : TEST
        logic [31:0] status;
        logic [P_N-1:0] expected_initial;
        integer unused;
        unused=$value$plusargs("DATA_DIR=%s",data_dir);
        unused=$value$plusargs("MIN_SCORE=%d",min_score);
        uart_mode=$test$plusargs("UART");
        if(ROWS!=P_ROWS || COLS!=P_COLS || N_SPIN!=P_N || SWEEP_ROUND_NUM!=32 || I0_LEVEL_WIDTH!=5)
            $fatal(1,"Generated data / RTL geometry or LUT mismatch");
        $readmemh(required_file("chain_start.mem"),chain_start);
        $readmemh(required_file("chain_nodes.mem"),chain_nodes);
        $readmemh(required_file("graph_a.mem"),graph_a);
        $readmemh(required_file("graph_b.mem"),graph_b);
        $readmemh(required_file("graph_w.mem"),graph_w);
        $readmemh(required_file("clause_start.mem"),clause_start);
        $readmemh(required_file("literals.mem"),literals);
        $readmemh(required_file("sweep_i0.mem"),sweep_i0);
        for(int v=0;v<P_CHAINS;v++) begin
            if((^chain_start[v])===1'bx || chain_start[v]<0 ||
                !(chain_start[v+1]>chain_start[v] && chain_start[v+1]<=P_CHAIN_NODES))
                $fatal(1,"Invalid chain offsets");
        end
        for(int v=0;v<P_CHAIN_NODES;v++)
            if((^chain_nodes[v])===1'bx || chain_nodes[v]<0 || chain_nodes[v]>=P_N)
                $fatal(1,"Invalid chain node");
        csv_file=$fopen("chimera_sweeps.csv","w");
        state_file=$fopen("chimera_states.txt","w");
        if(!csv_file || !state_file) $fatal(1,"Cannot open score outputs");
        $fdisplay(csv_file,"run,sweep,cycles,score,best,target,broken,ties,i0");
        $display("[CHIMERA] case=%s geometry=%0dx%0d pbits=%0d transport=%s runs=%0d sweeps=%0d majority=%0d",P_CASE,ROWS,COLS,N_SPIN,uart_mode?"UART":"REGISTER_BUS",P_RUNS,P_SWEEPS,P_MAJORITY);
        if($test$plusargs("UART_SMOKE")) begin
            repeat(8) @(negedge clk); rst_n=1;
            uart_mode=1;
            repeat(8) @(negedge clk);
            check(4,0); wr(4,32'h0400001f); check(4,32'h0400001f); check('h0c,0);
            uart_mode=$test$plusargs("UART");
            $display("[CHIMERA_UART_SMOKE] PASS production baud=%0d",BAUD_RATE);
        end
        for(run_index=0;run_index<P_RUNS;run_index++) begin
            @(negedge clk); rst_n=0;
            repeat(8) @(negedge clk); rst_n=1;
            repeat(8) @(negedge clk);
            sweeps_seen=0; phases_seen=0; best_score=-1; best_sweep=0;
            first_success=0; first_success_cycle=0; best_cycle=0;
            $readmemh(required_file($sformatf("config_%0d.mem",run_index)),program_mem);
            $readmemh(required_file($sformatf("initial_%0d.mem",run_index)),initial_bits);
            $display("[CHIMERA_CONFIG] run=%0d master_seed=%0d init_seed=%0d commands=%0d",run_index,P_SEED_MASTER+10*run_index,P_INIT_SEED+7919*run_index,P_COMMANDS);
            for(int k=0;k<P_COMMANDS;k++) begin
                if(program_mem[k][55:48]==1) wr(program_mem[k][47:32],program_mem[k][31:0]);
                else if(program_mem[k][55:48]==2) check(program_mem[k][47:32],program_mem[k][31:0]);
                else $fatal(1,"Invalid/uninitialized configuration instruction %0d",k);
                if((k+1)%10000==0 || ($test$plusargs("TRACE_CONFIG") && (k+1)%100==0))
                    $display("[CHIMERA_CONFIG] run=%0d checked %0d/%0d transactions time=%0t",run_index,k+1,P_COMMANDS,$time);
            end
            for(int v=0;v<P_N;v++) expected_initial[v]=initial_bits[v];
            if(spins!==expected_initial) $fatal(1,"Initial spins mismatch");
            snapshot_check(expected_initial);
            wr(0,1<<CFG_DONE_SET_LSB);
            wr(0,1<<RUN_START_LSB);
            // RUN may finish before its UART acknowledgement; use persistent done.
            begin : WAIT_DONE
                integer waited;
                waited=0;
                while(!run_done) begin
                    @(negedge clk); waited++;
                    if(waited>P_SWEEPS*2*(P_MAJORITY+20)+1000) $fatal(1,"RUN timeout");
                end
            end
            @(negedge clk);
            if(run_busy || sweeps_seen!=P_SWEEPS || phases_seen!=2*P_SWEEPS)
                $fatal(1,"RUN counts sweeps=%0d phases=%0d busy=%0b",sweeps_seen,phases_seen,run_busy);
            final_spins=spins;
            access_reg(0,8,0,status);
            if(!status[RUN_DONE_LSB] || status[RUN_BUSY_LSB] || status[ERROR_LSB]) $fatal(1,"Run status %h",status);
            snapshot_check(final_spins);
            repeat(100) @(negedge clk);
            if(spins!==final_spins || phase_start) $fatal(1,"State changed after RUN_DONE");
            check('h0c,0);
            if(best_score>overall_best) overall_best=best_score;
            if(first_success>0) successful_runs++;
            $fdisplay(state_file,"run=%0d final_score=%0d best_score=%0d final_spins=%h best_spins=%h best_logical=%h",run_index,current_score,best_score,final_spins,best_spins,best_decoded);
            $display("[CHIMERA_RUN] run=%0d final=%0d best=%0d target=%0d best_sweep=%0d best_cycle=%0d first_success=%0d first_success_cycle=%0d best_broken=%0d final_cycle=%0d",run_index,current_score,best_score,P_TARGET,best_sweep,best_cycle,first_success,first_success_cycle,best_broken,final_cycle);
            if(min_score>=0 && best_score<min_score) $fatal(1,"Quality threshold not reached");
        end
        $fclose(csv_file); $fclose(state_file);
        $display("[CHIMERA_SUMMARY] best=%0d target=%0d success_runs=%0d/%0d",overall_best,P_TARGET,successful_runs,P_RUNS);
        $display("[TB_CHIMERA_PROBLEM] PASS functional checks; optimization success reported separately");
        $finish;
    end
    initial begin #120s; $fatal(1,"Global watchdog timeout"); end
endmodule
