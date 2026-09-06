`timescale 1ns/1ps
module uart_byte_timeout_case #(
    parameter int ACTUAL_CLK_HZ = pbit_pkg::CLK_FREQ_HZ
)(output logic done=0);
    localparam int TIMEOUT_CYCLES = int'((64'(pbit_pkg::REF_CLK_FREQ_HZ) * pbit_pkg::PLL_CFG_BYTE_TIMEOUT_MS) / 1000);
    localparam int BIT_CYCLES = pbit_pkg::CLK_FREQ_HZ / pbit_pkg::BAUD_RATE;
    localparam int RX_CAPTURE_CYCLES = BIT_CYCLES/2 + 9*BIT_CYCLES + 3;
    localparam realtime CLK_NS = 1.0e9 / ACTUAL_CLK_HZ;
    localparam realtime BIT_NS = CLK_NS * BIT_CYCLES;
    logic clk=0,rst_n=0,rx=1;
    wire tx,wr,rd,frame_err,overflow,rx_busy,tx_busy;
    wire [15:0] addr;
    wire [31:0] wdata;
    int accesses=0,errors=0;
    bit deadline_seen=0;
    pbit_uart_reg_master dut(.clk(clk),.rst_n(rst_n),.uart_rx_i(rx),.uart_tx_o(tx),
        .reg_wr_en_o(wr),.reg_rd_en_o(rd),.reg_addr_o(addr),.reg_wdata_o(wdata),
        .reg_rdata_i(32'h12345678),.reg_access_error_i(1'b0),
        .uart_frame_err_pulse_o(frame_err),.uart_overflow_pulse_o(overflow),
        .uart_rx_busy_o(rx_busy),.uart_tx_busy_o(tx_busy));
    initial while(!done) begin #(CLK_NS/2.0);clk=~clk;end
    always @(negedge clk) if(rst_n) begin
        if(wr || rd) accesses++;
        if(frame_err) errors++;
        if(dut.rx_valid_w && dut.rx_timeout_cnt_q==TIMEOUT_CYCLES-1) deadline_seen=1;
    end
    task automatic send_byte(input logic [7:0] value);
        rx=0;#(BIT_NS);
        for(int b=0;b<8;b++) begin rx=value[b];#(BIT_NS);end
        rx=1;#(BIT_NS);
    endtask
    task automatic receive_reply;
        logic [55:0] reply;
        for(int byte_idx=6;byte_idx>=0;byte_idx--) begin
            @(negedge tx);#(BIT_NS*1.5);
            for(int b=0;b<8;b++) begin reply[byte_idx*8+b]=tx;#(BIT_NS);end
            if(tx!==1) $fatal(1,"Bad response stop");
        end
        if(reply!==56'h00001012345678) $fatal(1,"Bad response %h",reply);
    endtask
    task automatic read_request;
        logic [55:0] request;
        request=56'h02001000000000;
        fork
            begin for(int b=6;b>=0;b--) send_byte(request[b*8+:8]);end
            receive_reply();
        join
        #(BIT_NS*2);
    endtask
    task automatic wait_timeout;
        // Already past byte completion; observe the exact counter boundary.
        while(dut.rx_timeout_cnt_q!=TIMEOUT_CYCLES-1) @(negedge clk);
        if(!rx_busy) $fatal(1,"Timeout cleared early");
        @(negedge clk);#0.001;
        if(rx_busy || dut.rx_shift_q!==0 || dut.rx_timeout_cnt_q!==0 || !frame_err)
            $fatal(1,"Timeout failed to clear partial frame");
        @(negedge clk);#0.001;
        if(frame_err) $fatal(1,"Timeout error is not a single-cycle pulse");
    endtask
    task automatic send_prefix;
        send_byte(2);send_byte(0);send_byte(8'h10);repeat(3) send_byte(0);
    endtask
    initial begin
        int old_accesses,old_errors;
        # (CLK_NS*3.3);rst_n=1;#(BIT_NS);
        if(dut.BYTE_TIMEOUT!=TIMEOUT_CYCLES) $fatal(1,"Cycle count differs from reference domain");
        read_request();
        for(int n=1;n<=6;n++) begin
            old_accesses=accesses;old_errors=errors;
            // Valid opcode at the front ensures a stale prefix could cause a write.
            send_byte(1);repeat(n-1) send_byte(0);
            wait_timeout();
            if(accesses!=old_accesses || errors!=old_errors+1) $fatal(1,"Partial request escaped or timeout error missing n=%0d",n);
            read_request();
            if(accesses!=old_accesses+1) $fatal(1,"Recovery read failed n=%0d",n);
        end
        // Every valid byte restarts the timer, even if the complete frame spans it.
        old_errors=errors;old_accesses=accesses;
        fork
            begin
                logic [55:0] request;
                request=56'h02001000000000;
                for(int b=6;b>=0;b--) begin
                    send_byte(request[b*8+:8]);
                    if(b!=0) #(CLK_NS*(TIMEOUT_CYCLES/2));
                end
            end
            receive_reply();
        join
        #(BIT_NS*2);
        if(errors!=old_errors || accesses!=old_accesses+1) $fatal(1,"Valid byte did not restart timer");
        // Seventh byte valid precisely on the deadline must complete the request.
        old_errors=errors;old_accesses=accesses;deadline_seen=0;
        send_prefix();
        while(dut.rx_timeout_cnt_q!=TIMEOUT_CYCLES-1-RX_CAPTURE_CYCLES) @(negedge clk);
        fork send_byte(0);receive_reply();join
        #(BIT_NS*2);
        if(!deadline_seen || errors!=old_errors || accesses!=old_accesses+1)
            $fatal(1,"Deadline byte priority failed seen=%b errors=%0d",deadline_seen,errors-old_errors);
        // One cycle later: discard the old prefix; late byte starts a new partial frame.
        old_accesses=accesses;old_errors=errors;
        send_prefix();
        while(dut.rx_timeout_cnt_q!=TIMEOUT_CYCLES-RX_CAPTURE_CYCLES) @(negedge clk);
        send_byte(0);#(CLK_NS*2);
        if(accesses!=old_accesses || errors!=old_errors+1 || dut.rx_byte_cnt_q!=1)
            $fatal(1,"Late byte reused old prefix");
        wait_timeout();read_request();
        // Hardware reset during a partial request also clears the timer.
        send_byte(1);rst_n=0;#(CLK_NS*3);rst_n=1;#(BIT_NS);
        if(rx_busy || dut.rx_timeout_cnt_q!==0) $fatal(1,"Reset failed to clear timer");
        read_request();
        $display("[UART_BYTE_TIMEOUT] PASS actual_clk=%0d cycles=%0d timeout_ns=%0.0f partial_lengths=1..6 deadline late_byte reset recovery",ACTUAL_CLK_HZ,TIMEOUT_CYCLES,TIMEOUT_CYCLES*CLK_NS);
        done=1;
    end
endmodule

module tb_uart_byte_timeout;
    wire core_done,bypass_done;
    uart_byte_timeout_case core_case(.done(core_done));
    uart_byte_timeout_case #(.ACTUAL_CLK_HZ(pbit_pkg::REF_CLK_FREQ_HZ)) bypass_case(.done(bypass_done));
    initial begin wait(core_done && bypass_done);$display("[TB_UART_BYTE_TIMEOUT] PASS");$finish;end
    initial begin #500_000_000;$fatal(1,"Byte timeout watchdog");end
endmodule
