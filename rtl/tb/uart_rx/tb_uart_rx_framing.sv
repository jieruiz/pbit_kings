`timescale 1ns/1ps
module uart_rx_framing_case #(
    parameter int CLK_HZ = pbit_pkg::REF_CLK_FREQ_HZ,
    parameter int BAUD = pbit_pkg::PLL_CFG_BAUD_RATE
)(output logic done = 0);
    localparam realtime CLK_NS = 1.0e9 / CLK_HZ;
    localparam realtime BIT_NS = 1.0e9 / BAUD;
    logic clk=0, rst_n=0, rx=1;
    wire [7:0] data;
    wire valid, frame_err;
    logic [7:0] expected[2048];
    int sent=0, received=0, errors=0;
    logic prev_valid=0, prev_error=0;
    always #(CLK_NS/2.0) clk=~clk;
    uart_rx_8n1 #(.CLK_FREQ_HZ(CLK_HZ),.BAUD_RATE(BAUD)) dut(
        .clk(clk),.rst_n(rst_n),.rx_i(rx),.rx_data_o(data),
        .rx_valid_o(valid),.rx_frame_err_o(frame_err));
    always @(posedge clk) begin
        #0.001;
        if(rst_n) begin
            if(valid && frame_err) $fatal(1,"Valid and error overlap baud=%0d",BAUD);
            if(valid && prev_valid) $fatal(1,"Valid exceeds one cycle");
            if(frame_err && prev_error) $fatal(1,"Error exceeds one cycle");
            if(valid) begin
                if(received>=sent || data!==expected[received])
                    $fatal(1,"RX mismatch baud=%0d index=%0d actual=%h expected=%h",BAUD,received,data,expected[received]);
                received++;
            end
            if(frame_err) errors++;
        end
        prev_valid=valid;prev_error=frame_err;
    end
    task automatic send(input logic [7:0] value, input bit good_stop, input realtime period);
        if(good_stop) begin expected[sent]=value;sent++;end
        rx=0;#(period);
        for(int b=0;b<8;b++) begin rx=value[b];#(period);end
        rx=good_stop;#(period);
    endtask
    task automatic bad_frame(input logic [7:0] value, input int low_bits);
        int old_errors, old_received;
        logic [7:0] old_data;
        old_errors=errors;old_received=received;old_data=data;
        send(value,0,BIT_NS);
        #(low_bits*BIT_NS);
        if(errors!=old_errors+1 || received!=old_received || data!==old_data)
            $fatal(1,"Bad stop/break accepted or repeated baud=%0d errors=%0d",BAUD,errors-old_errors);
        rx=1;#(BIT_NS);
        send(8'h3c,1,BIT_NS);
        #(BIT_NS);
        if(received!=old_received+1) $fatal(1,"Recovery failed baud=%0d",BAUD);
    endtask
    initial begin
        #(CLK_NS*3.3);rst_n=1;#(BIT_NS);
        // Every byte value, minimum one stop bit, four asynchronous start phases.
        for(int phase=0;phase<4;phase++) begin
            #(CLK_NS*(phase+0.25));
            for(int v=0;v<256;v++) send(8'(v),1,BIT_NS);
            #(BIT_NS);
            if(received!=sent || errors!=0) $fatal(1,"Normal burst failed baud=%0d",BAUD);
        end
        bad_frame(8'ha5,0);
        bad_frame(8'h00,40);
        bad_frame(8'hff,20);
        // Short false start must not publish a byte or a frame error.
        begin
            int before_errors;
            before_errors=errors;
            rx=0;#(BIT_NS*0.2);rx=1;#(BIT_NS*12);
            if(received!=sent || errors!=before_errors) $fatal(1,"False start not filtered");
        end
        // Interrupted data frame: reset must suppress both output pulses.
        rx=0;#(BIT_NS*4.2);rst_n=0;#(CLK_NS*3.1);rx=1;
        if(valid || frame_err) $fatal(1,"Reset failed to clear outputs");
        rst_n=1;#(BIT_NS*2);
        send(8'h96,1,BIT_NS);#(BIT_NS);
        // Two baud offsets, with enough idle between frames to isolate phase drift.
        for(int v=0;v<16;v++) begin
            send(8'(v*17),1,BIT_NS*((v%2)?1.02:0.98));#(BIT_NS);
        end
        if(received!=sent || errors!=3) $fatal(1,"Final RX counts baud=%0d sent=%0d got=%0d errors=%0d",BAUD,sent,received,errors);
        $display("[UART_RX_FRAMING] PASS clk=%0d baud=%0d accepted=%0d rejected=%0d",CLK_HZ,BAUD,received,errors);
        done=1;
    end
endmodule

module tb_uart_rx_framing;
    wire cfg_done,core_done;
    uart_rx_framing_case cfg_case(.done(cfg_done));
    uart_rx_framing_case #(.CLK_HZ(pbit_pkg::CLK_FREQ_HZ),.BAUD(pbit_pkg::BAUD_RATE)) core_case(.done(core_done));
    initial begin wait(cfg_done && core_done);$display("[TB_UART_RX_FRAMING] PASS");$finish;end
    initial begin #20_000_000;$fatal(1,"RX regression watchdog");end
endmodule
