`timescale 1ns/1ps
import pbit_pkg::*;
module tb;
    localparam int CPB = CLK_FREQ_HZ / BAUD_RATE;
    localparam realtime CLK_PERIOD = 1s / real'(CLK_FREQ_HZ);
    localparam realtime BIT_TIME = CPB * CLK_PERIOD;
    logic clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    logic rst_n = 0, rx = 1;
    wire tx;
    int transactions = 0, phase_count = 0, request_count = 0;
    logic [31:0] data;
    bit [51:0] read_seen='0, write_seen='0;
    // Independent register-map masks, not DUT packing helpers.
    function automatic bit is_wo(input int addr);
        return addr==0 || addr=='h80 || addr=='h90 || addr=='ha0;
    endfunction
    function automatic bit is_ro(input int addr);
        return addr==8 || addr=='h84 || addr=='h94 || addr=='ha4 || addr>='ha8;
    endfunction
    function automatic logic [31:0] rw_mask(input int addr);
        case(addr)
            'h04: return 32'h1fffffff;
            'h10: return 32'h0000000f;
            'h74: return 32'h00001f1f;
            'h78: return 32'h00000103;
            'h7c: return 32'h0007ff07;
            'h88: return 32'h00000003;
            'h98: return 32'h00000307;
            'h9c: return 32'h000001ff;
            default: return (addr>='h14 && addr<='h30) ? 32'h1f1f1f1f : 32'hffffffff;
        endcase
    endfunction
    pbit_top dut (.clk(clk), .rst_n(rst_n), .uart_rx_i(rx), .uart_tx_o(tx));
    always @(posedge clk) if (rst_n && dut.phase_start_w) phase_count++;
    always @(posedge clk) if (rst_n && dut.cfg_req_valid_w && dut.cfg_req_ready_w) request_count++;
    task automatic send_byte(input logic [7:0] value);
        rx = 0; #(BIT_TIME);
        for (int b=0;b<8;b++) begin rx=value[b]; #(BIT_TIME); end
        rx=1; #(BIT_TIME);
    endtask
    task automatic receive_byte(output logic [7:0] value);
        @(negedge tx);
        #(BIT_TIME/2);
        if (tx !== 0) $fatal(1,"UART start");
        for (int b=0;b<8;b++) begin #(BIT_TIME); value[b]=tx; end
        #(BIT_TIME);
        if (tx !== 1) $fatal(1,"UART stop");
    endtask
    task automatic access_reg(input logic [7:0] op, input logic [15:0] addr,
                              input logic [31:0] value, output logic [31:0] result, input logic [7:0] expected_status=0);
        logic [55:0] request, response;
        logic [7:0] received;
        request={op,addr,value}; response='0;
        fork
            begin
                for (int b=6;b>=0;b--) send_byte(request[b*8+:8]);
            end
            begin
                for (int b=6;b>=0;b--) begin
                    receive_byte(received); response[b*8+:8]=received;
                end
            end
        join
        if (response[55:32] !== {expected_status,addr}) $fatal(1,"UART response addr=%h response=%h",addr,response);
        result=response[31:0]; transactions++;
        if (addr<='hcc && addr[1:0]==0) begin
            if(op==1) write_seen[addr/4]=1; else read_seen[addr/4]=1;
        end
        #(BIT_TIME*2);
    endtask
    task automatic wr(input logic [15:0] addr,input logic [31:0] value);
        logic [31:0] ignored;
        access_reg(1,addr,value,ignored);
    endtask
    task automatic check_read(input logic [15:0] addr,input logic [31:0] expected);
        logic [31:0] result;
        access_reg(2,addr,0,result);
        if(result !== expected) $fatal(1,"Read %h got %h expected %h",addr,result,expected);
    endtask
    task automatic reset_dut;
        @(negedge clk); rst_n=0; rx=1;
        repeat(8) @(negedge clk); rst_n=1;
        #(BIT_TIME*2);
    endtask
    task automatic clear_errors;
        wr('h0c,'1); check_read('h0c,0);
    endtask
    initial begin
        reset_dut();
        // A snapshot must be captured before reading its non-reset data register.
        wr('h00,1<<SNAPSHOT_LATCH_LSB);
        for(int a=0;a<='hcc;a+=4) begin
            if(is_wo(a)) begin
                access_reg(2,16'(a),0,data,2);
                if(data!==0) $fatal(1,"WO read must return zero");
                check_read('h0c,1<<RD_TO_WO_LSB); clear_errors();
                wr(16'(a),0); wr(16'(a),32'h80000000);
            end else if(a=='h08) check_read(16'(a),1<<SNAPSHOT_VALID_LSB);
            else check_read(16'(a),0);
        end
        // All ordinary RW registers: zero, ones and complementary patterns.
        // Check every peer register after writes to expose address aliasing.
        for(int pass=0;pass<4;pass++) begin
            for(int a=4;a<='hcc;a+=4) if(!is_ro(a) && !is_wo(a) && a!='h0c) begin
                logic [31:0] pattern;
                case(pass)
                    0:pattern='0; 1:pattern='1;
                    2:pattern=32'haaaaaaaa ^ (32'(a)*32'h01010101);
                    3:pattern=32'h55555555 ^ (32'(a)*32'h01010101);
                endcase
                wr(16'(a),pattern);
            end
            for(int a=4;a<='hcc;a+=4) if(!is_ro(a) && !is_wo(a) && a!='h0c) begin
                logic [31:0] pattern;
                case(pass)
                    0:pattern='0; 1:pattern='1;
                    2:pattern=32'haaaaaaaa ^ (32'(a)*32'h01010101);
                    3:pattern=32'h55555555 ^ (32'(a)*32'h01010101);
                endcase
                check_read(16'(a),pattern & rw_mask(a));
            end
        end
        // RO writes reject and preserve existing contents.
        for(int a=4;a<='hcc;a+=4) if(is_ro(a)) begin
            logic [31:0] before_value;
            access_reg(2,16'(a),0,before_value);
            access_reg(1,16'(a),'1,data,2);
            check_read('h0c,1<<WR_TO_RO_LSB);
            clear_errors(); check_read(16'(a),before_value);
        end
        // Misaligned/unmapped accesses, sticky errors and selective W1C.
        access_reg(2,16'h0001,0,data,2);
        access_reg(1,16'h00d0,0,data,2);
        access_reg(2,16'h0080,0,data,2);
        check_read('h0c,(1<<ADDR_ERR_LSB)|(1<<RD_TO_WO_LSB));
        wr('h0c,1<<ADDR_ERR_LSB); check_read('h0c,1<<RD_TO_WO_LSB);
        wr('h0c,0); check_read('h0c,1<<RD_TO_WO_LSB);
        wr(0,1<<ERROR_CLEAR_LSB); check_read('h0c,0);
        reset_dut();
        // Configure a nonzero bit in every snapshot data word of page zero.
        for(int word_idx=0;word_idx<10;word_idx++) begin
            int cell_idx;
            cell_idx=word_idx*4;
            wr('h74,32'((cell_idx/COLS) | ((cell_idx%COLS)<<8)));
            wr('h78,0); wr('h7c,32'h7ff07);
            wr('h80,(1<<APPLY_CFG_LSB)|(1<<READBACK_CFG_LSB));
            check_read('h84,32'h7ff);
        end
        wr('h88,3); wr('h8c,0);
        wr('h90,(1<<APPLY_SEED_LSB)|(1<<READBACK_SEED_LSB));
        check_read('h94,1); check_read('h8c,0);
        wr('h8c,32'h12345678); wr('h90,1<<APPLY_SEED_LSB);
        wr('h90,1<<READBACK_SEED_LSB); check_read('h94,32'h12345678);
        for(int edge_type=0;edge_type<6;edge_type++) begin
            wr('h98,32'(edge_type | (3<<8))); wr('h9c,32'h1ff);
            wr('ha0,(1<<APPLY_EDGE_LSB)|(1<<READBACK_EDGE_LSB));
            check_read('ha4,32'h1ff);
            wr('ha0,(1<<CLEAR_EDGE_LSB)|(1<<READBACK_EDGE_LSB));
            check_read('ha4,32'h1fe);
        end
        access_reg(2,'h08,0,data);
        if((data & 32'h198)!==32'h98) $fatal(1,"DONE/CFG_BUSY %h",data);
        check_read('h08,0);
        for(int page=0;page<SPIN_ADDR_MAX;page++) begin
            wr('h10,32'(page)); wr(0,1<<SNAPSHOT_LATCH_LSB);
            check_read('h08,1<<SNAPSHOT_VALID_LSB);
            check_read('h08,0); // RC does not clear the captured data below.
            for(int word_idx=0;word_idx<10;word_idx++)
                check_read(16'('ha8+4*word_idx),page==0 ? 1 : 0);
        end
        // Invalid commands complete locally and never reach the array.
        begin
            int before_count;
            before_count=request_count;
            wr('h74,31);
            access_reg(1,'h80,1<<READBACK_CFG_LSB,data,2);
            check_read('h84,0); check_read('h0c,1<<UNIT_ROW_OOR_LSB); clear_errors();
            wr('h74,31<<8);
            access_reg(1,'h90,1<<READBACK_SEED_LSB,data,2);
            check_read('h94,0); check_read('h0c,1<<UNIT_COL_OOR_LSB); clear_errors();
            wr('h74,0); wr('h98,6);
            access_reg(1,'ha0,1<<READBACK_EDGE_LSB,data,2);
            check_read('ha4,0); check_read('h0c,1<<EDGE_TYPE_ERR_LSB); clear_errors();
            wr('h74,(COLS-1)<<8); wr('h98,4);
            access_reg(1,'ha0,1<<APPLY_EDGE_LSB,data,2);
            check_read('h0c,1<<EDGE_BOUNDARY_ERR_LSB); clear_errors();
            if(request_count!=before_count) $fatal(1,"Illegal request reached array");
        end
        wr('h10,15); access_reg(1,0,1<<SNAPSHOT_LATCH_LSB,data,2);
        check_read('h0c,1<<SNAP_ADDR_OOR_LSB); clear_errors();
        access_reg(1,0,1<<RUN_START_LSB,data,2);
        check_read('h0c,1<<RUN_WITHOUT_CFG_DONE_LSB); clear_errors();
        // Inject a runtime-status window to exercise the UART error response
        // without a long stochastic run. The normal run below remains end-to-end.
        wr('h04,32'h1f004e20);
        force dut.run_busy_w = 1'b1;
        for(int pattern_idx=0;pattern_idx<3;pattern_idx++) begin
            logic [31:0] attempted;
            // Change only NUM_SWEEP, only NUM_MAJORITY, then write reserved bits.
            case(pattern_idx)
                0: attempted=32'h1f000000;
                1: attempted=32'h00004e20;
                default: attempted=32'h80000000;
            endcase
            if(!dut.run_busy_w) $fatal(1,"Runtime test ended too early");
            access_reg(1,'h04,attempted,data,2);
            check_read('h04,32'h1f004e20);
            check_read('h0c,1<<GLOBAL_CFG_WHILE_RUN_LSB);
            clear_errors();
        end
        // Every runtime CMD write is illegal, including no-op and reserved-only.
        wr('h74,0); wr('h98,0);
        begin
            int before_requests;
            before_requests=request_count;
            for(int target=0;target<3;target++) begin
                int command_addr,error_bit;
                case(target)
                    0:begin command_addr='h80;error_bit=NODE_CFG_WHILE_RUN_LSB;end
                    1:begin command_addr='h90;error_bit=SEED_CFG_WHILE_RUN_LSB;end
                    default:begin command_addr='ha0;error_bit=EDGE_CFG_WHILE_RUN_LSB;end
                endcase
                for(int bits_value=0;bits_value<9;bits_value++) begin
                    access_reg(1,16'(command_addr),bits_value==8 ? 32'h80000000 : 32'(bits_value),data,2);
                    check_read('h0c,32'd1<<error_bit);
                    clear_errors();
                end
            end
            if(request_count!=before_requests) $fatal(1,"Runtime CMD escaped to array");
        end
        release dut.run_busy_w;
        @(negedge clk);
        // New parameters become writable after completion.
        wr('h04,0); wr(0,1<<CFG_DONE_SET_LSB);
        wr(0,1<<RUN_START_LSB);
        access_reg(2,'h08,0,data);
        if(!data[RUN_DONE_LSB] || data[RUN_BUSY_LSB] || data[ERROR_LSB]) $fatal(1,"Run status %h",data);
        if(phase_count!=2) $fatal(1,"Expected two phases");
        wr(0,1<<RUN_DONE_CLEAR_LSB); check_read('h08,1<<CFG_DONE_LSB);
        wr(0,1<<CFG_DONE_CLEAR_LSB); check_read('h08,0);
        check_read('h0c,0);
        if(!(&read_seen) || !(&write_seen)) $fatal(1,"Incomplete address coverage R=%h W=%h",read_seen,write_seen);
        $display("PASS rw_basic: all 52 registers read/write exercised, %0d UART transactions; masks, permissions, W1C/RC, NODE/SEED/EDGE, all snapshot pages and run",transactions);
        $finish;
    end
    initial begin #1s; $fatal(1,"Timeout"); end
endmodule
