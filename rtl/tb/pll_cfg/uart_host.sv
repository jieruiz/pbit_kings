// Simulation-only UART host. Use a real baud period, not the DUT divider.
module uart_host #(parameter realtime BIT_NS = 1.0e9 / 1_000_000.0) (
    input wire tx, output logic rx
);
    timeunit 1ns;
    timeprecision 1ps;
    initial rx = 1'b1;
    task automatic send_byte(input logic [7:0] value);
        rx = 0; #(BIT_NS);
        for (int b = 0; b < 8; b++) begin
            rx = value[b]; #(BIT_NS);
        end
        rx = 1; #(BIT_NS);
    endtask
    task automatic receive_byte(output logic [7:0] value);
        @(negedge tx);
        #(BIT_NS / 2.0);
        if (tx !== 0) $fatal(1, "UART false start");
        for (int b = 0; b < 8; b++) begin
            #(BIT_NS); value[b] = tx;
        end
        #(BIT_NS);
        if (tx !== 1) $fatal(1, "UART invalid stop bit");
        #(BIT_NS / 2.0);
    endtask
    task automatic transfer4(input logic [31:0] request,
                             output logic [31:0] reply);
        fork
            begin
                for (int b = 3; b >= 0; b--) send_byte(request[b*8 +: 8]);
            end
            begin
                for (int b = 3; b >= 0; b--) receive_byte(reply[b*8 +: 8]);
            end
        join
        #(BIT_NS * 2.0);
    endtask
endmodule
