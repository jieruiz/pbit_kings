`timescale 1ns/1ps
import pbit_pkg::*;
module tb_run3x3;
    localparam realtime PERIOD = 1s / real'(CLK_FREQ_HZ);
    localparam realtime BIT_TIME = (CLK_FREQ_HZ/BAUD_RATE)*PERIOD;
    logic clk=0, rst_n=0, rx=1;
    wire tx;
    always #(PERIOD/2) clk=~clk;
    pbit_top dut(.clk(clk), .rst_n(rst_n), .uart_rx_i(rx), .uart_tx_o(tx));
    `define BANK dut.u_pbit_array_chimera.GEN_BANK_ROW[0].GEN_BANK_COL[0].u_pbit_bank
    logic [31:0] rng [0:8][0:3];
    logic [71:0] expected_spins;
    logic [319:0] captured;
    int votes [0:8][0:3];
    int cycle=0, launch_cycle, run_cycle, n, m, expected_sweeps;
    int phases, completed, transactions=0, cases=0, csv;
    bit checking=0, active=0, clamp_case=0, color;
    bit running=0;

    function automatic logic [31:0] advance(input logic [31:0] s);
        return {s[30:0],s[31]^s[21]^s[1]^s[0]};
    endfunction
    function automatic logic [15:0] extract16(input logic [31:0] s);
        return {s[4]^s[18],s[20]^s[24],s[0]^s[7],s[12]^s[31],
                s[8]^s[27],s[6]^s[25],s[2]^s[15],s[16]^s[28],
                s[10]^s[24],s[17]^s[26],s[21]^s[29],s[19]^s[30],
                s[11]^s[18],s[5]^s[14],s[9]^s[22],s[23]^s[28]};
    endfunction
    function automatic logic [31:0] seed_for(input int cell_id, input int lane);
        return 32'h136a59c7 ^ (32'h10204081*(cell_id*4+lane+1));
    endfunction
    task automatic send_byte(input logic [7:0] b);
        rx=0; #(BIT_TIME);
        for(int k=0;k<8;k++) begin rx=b[k]; #(BIT_TIME); end
        rx=1; #(BIT_TIME);
    endtask
    task automatic recv_byte(output logic [7:0] b);
        @(negedge tx); #(BIT_TIME/2);
        if(tx!==0) $fatal(1,"UART start");
        for(int k=0;k<8;k++) begin #(BIT_TIME); b[k]=tx; end
        #(BIT_TIME); if(tx!==1) $fatal(1,"UART stop");
    endtask
    task automatic access_reg(input bit write_en, input logic [15:0] addr,
                              input logic [31:0] value, output logic [31:0] result);
        logic [55:0] req, rsp;
        logic [7:0] b;
        int cfg_wait;
        req={write_en ? 8'h01 : 8'h02,addr,value}; rsp=0;
        fork
            begin for(int k=6;k>=0;k--) send_byte(req[k*8+:8]); end
            begin for(int k=6;k>=0;k--) begin recv_byte(b); rsp[k*8+:8]=b; end end
        join
        if(rsp[55:32]!=={8'h00,addr}) $fatal(1,"UART response %h addr=%h",rsp,addr);
        result=rsp[31:0]; transactions++;
        cfg_wait=0;
        while(dut.u_uart_reg_subsystem.u_pbit_reg_block.cfg_busy_q) begin
            @(negedge clk); cfg_wait++;
            if(cfg_wait>1000) $fatal(1,"CFG_BUSY timeout addr=%h",addr);
        end
        #(2*BIT_TIME);
    endtask
    task automatic wr(input logic [15:0] addr,input logic [31:0] value);
        logic [31:0] unused; access_reg(1,addr,value,unused);
    endtask
    task automatic rd_check(input logic [15:0] addr,input logic [31:0] expected);
        logic [31:0] value; access_reg(0,addr,0,value);
        if(value!==expected) $fatal(1,"Read %h got=%h expected=%h",addr,value,expected);
    endtask
    task automatic snapshot;
        logic [31:0] value;
        wr('h10,0); wr(0,1<<SNAPSHOT_LATCH_LSB);
        for(int k=0;k<10;k++) begin
            access_reg(0,16'('ha8+4*k),0,value); captured[k*32+:32]=value;
        end
        if(captured!=={248'b0,expected_spins})
            $fatal(1,"Snapshot got=%h expected=%h",captured,expected_spins);
    endtask

    // Independent edge schedule. Sample pre-edge controls; check post-NBA state.
    always @(posedge clk) begin : monitor
        int age, col, idx, threshold;
        bit commit_now, finish_now;
        cycle++;
        if(checking && rst_n) begin
            commit_now=0; finish_now=0;
            if(dut.run_start_pulse_w && !dut.run_busy_w) begin
                run_cycle=cycle; running=1;
            end
            if(`BANK.phase_accept_w) begin
                if(active) $fatal(1,"Overlapping phase");
                active=1; launch_cycle=cycle; color=dut.phase_w;
                if(color !== (phases%2)) $fatal(1,"Color sequence");
                phases++;
                for(int c=0;c<9;c++) for(int r=0;r<4;r++) votes[c][r]=0;
            end
            if(active) begin
                age=cycle-launch_cycle;
                if(`BANK.contrib_en_w !== (age>=1 && age<=n)) $fatal(1,"Contribution age=%0d",age);
                if(`BANK.mac_en_w !== (age>=2 && age<=n+1)) $fatal(1,"MAC age=%0d",age);
                if(`BANK.spin_sum_en_w !== (age>=3 && age<=n+2)) $fatal(1,"Vote age=%0d",age);
                if(`BANK.majority_en_w !== (age==n+3)) $fatal(1,"Commit age=%0d",age);
                if(`BANK.lfsr_en_w !== (age>=1 && age<=n+3)) $fatal(1,"LFSR enable age=%0d",age);
                if(`BANK.threshold_load_q !== (age==1)) $fatal(1,"Threshold load age=%0d",age);
                for(int c=0;c<9;c++) for(int r=0;r<4;r++) begin
                    // With all edges invalid and bias=0, h=0 and threshold=0x8000.
                    // First sample consumes R2, after the two new pipeline stages.
                    if(age>=3 && age<=n+2)
                        votes[c][r] += (extract16(rng[c][r]) <= 16'h8000);
                    if(age>=1 && age<=n+3) rng[c][r]=advance(rng[c][r]);
                    if(age==n+3 && !clamp_case) begin
                        col=int'(color)^((c/3+c%3)%2);
                        idx=c*8+col*4+r;
                        threshold=(m/2)+1+((m%4)==3);
                        expected_spins[idx]=(votes[c][r]>=threshold);
                    end
                end
                if(age==n+3) begin
                    active=0; completed++; commit_now=1;
                end
            end else if(`BANK.contrib_en_w || `BANK.mac_en_w || `BANK.spin_sum_en_w || `BANK.majority_en_w)
                $fatal(1,"Unexpected idle pipeline enable");
            finish_now=running && (cycle-run_cycle==2*expected_sweeps*(n+5));
            #0.001;
            if(`BANK.phase_done_o !== commit_now) $fatal(1,"Phase done alignment cycle=%0d",cycle);
            if(dut.u_pbit_array_chimera.spin_flat_w[71:0] !== expected_spins)
                $fatal(1,"Per-phase spin mismatch cycle=%0d got=%h expected=%h",cycle,dut.u_pbit_array_chimera.spin_flat_w[71:0],expected_spins);
            if(running && dut.run_done_w !== finish_now) $fatal(1,"Run completion cycle mismatch");
            if(finish_now) begin
                if(dut.run_busy_w || completed!=2*expected_sweeps) $fatal(1,"Run completion count/busy");
                $display("[RUN] N=%0d sweeps=%0d cycles=%0d phases=%0d spins=%h",n,expected_sweeps,cycle-run_cycle,completed,expected_spins);
                $fdisplay(csv,"%0d,%0d,%0d,%0d,%0d,%h",clamp_case,n,expected_sweeps,cycle-run_cycle,completed,expected_spins);
                running=0;
            end
        end
    end

    task automatic run_case(input int samples,input int sweeps,input bit clamp_mode);
        logic [31:0] status;
        checking=0;
        @(negedge clk); rst_n=0; rx=1;
        repeat(8) @(negedge clk);
        rst_n=1; #(2*BIT_TIME);
        n=samples; m=n-1; expected_sweeps=sweeps; clamp_case=clamp_mode;
        active=0; running=0; phases=0; completed=0; expected_spins=0;
        for(int c=0;c<9;c++) begin
            wr('h74,(c/3)|((c%3)<<8));
            for(int node=0;node<8;node++) begin
                expected_spins[c*8+node]=((c+node)%2);
                wr('h78,(node%4)|((node/4)<<8));
                // Bias sign varies, but magnitude zero must be exactly disabled.
                wr('h7c,7 | (int'(expected_spins[c*8+node])<<8) |
                   (int'(clamp_mode)<<9) | (int'(expected_spins[c*8+node])<<10) | ((node%2)<<11));
                wr('h80,3);
                rd_check('h84,int'(expected_spins[c*8+node]) | (int'(clamp_mode)<<1) |
                         (int'(expected_spins[c*8+node])<<2) | ((node%2)<<3));
            end
            for(int r=0;r<4;r++) begin
                rng[c][r]=seed_for(c,r);
                wr('h88,r); wr('h8c,rng[c][r]); wr('h90,3); rd_check('h94,rng[c][r]);
            end
        end
        wr('h04,(m<<24)|(sweeps-1));
        // Vary annealing stages to exercise registered threshold loads; h=0 stays 0x8000.
        wr('h14,32'h071f0300);
        wr(0,1<<CFG_DONE_SET_LSB);
        checking=1;
        wr(0,1<<RUN_START_LSB);
        if(running || completed!=2*sweeps) $fatal(1,"Missing run completion");
        access_reg(0,'h08,0,status);
        if(!status[RUN_DONE_LSB] || status[RUN_BUSY_LSB] || status[ERROR_LSB]) $fatal(1,"Status=%h",status);
        snapshot();
        repeat(50) @(negedge clk);
        snapshot(); // Completed runs hold spins until another command.
        for(int c=0;c<9;c++) begin
            wr('h74,(c/3)|((c%3)<<8));
            for(int r=0;r<4;r++) begin
                wr('h88,r); wr('h90,2); rd_check('h94,rng[c][r]);
            end
        end
        wr(0,1<<RUN_DONE_CLEAR_LSB); rd_check('h0c,0);
        if(dut.run_done_w !== 0 || dut.run_busy_w !== 0) $fatal(1,"Done clear failed");
        checking=0; cases++;
    endtask
    initial begin
        if(ROWS!=3 || COLS!=3 || BANK_TILE_ROWS!=5 || BANK_TILE_COLS!=5)
            $fatal(1,"Expected 3x3 units in a partial 5x5 bank");
        csv=$fopen("run_summary.csv","w");
        if(!csv) $fatal(1,"Cannot open summary");
        $fdisplay(csv,"clamped,N,sweeps,cycles,phases,spins_hex");
        run_case(1,1,1);
        run_case(1,1,0);
        run_case(2,3,0);
        run_case(5,3,0);
        run_case(32,3,0);
        $fclose(csv);
        $display("[TB_RUN3X3] PASS cases=%0d UART_transactions=%0d",cases,transactions);
        $finish;
    end
    initial begin #1s; $fatal(1,"TB_RUN3X3 timeout phases=%0d completed=%0d",phases,completed); end
    `undef BANK
endmodule
