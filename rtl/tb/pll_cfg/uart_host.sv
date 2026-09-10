// SIMULATION ONLY. Host for the four-byte PLL configuration UART protocol.
module uart_host #(
    parameter realtime BIT_NS = 1000.0
) (
    input  wire  tx,
    output logic rx
);
    timeunit 1ns;
    timeprecision 1ps;

    initial rx = 1'b1;

    task automatic send_byte(input logic [7:0] value);
        rx = 1'b0;
        #(BIT_NS);
        for (int bit_idx = 0; bit_idx < 8; bit_idx++) begin
            rx = value[bit_idx];
            #(BIT_NS);
        end
        rx = 1'b1;
        #(BIT_NS);
    endtask

    task automatic receive_byte(output logic [7:0] value);
        @(negedge tx);
        #(BIT_NS / 2.0);
        if (tx !== 1'b0)
            $fatal(1, "PLL configuration UART false start");
        for (int bit_idx = 0; bit_idx < 8; bit_idx++) begin
            #(BIT_NS);
            value[bit_idx] = tx;
        end
        #(BIT_NS);
        if (tx !== 1'b1)
            $fatal(1, "PLL configuration UART invalid stop bit");
        #(BIT_NS / 2.0);
    endtask

    task automatic transfer4(
        input  logic [31:0] request,
        output logic [31:0] reply
    );
        reply = '0;
        fork
            begin
                for (int byte_idx = 3; byte_idx >= 0; byte_idx--)
                    send_byte(request[byte_idx*8 +: 8]);
            end
            begin
                for (int byte_idx = 3; byte_idx >= 0; byte_idx--)
                    receive_byte(reply[byte_idx*8 +: 8]);
            end
        join
        #(BIT_NS * 2.0);
    endtask
endmodule
