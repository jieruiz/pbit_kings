`timescale 1ns / 1ps

module lfsr32_rng32 (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        load_seed_i,
    input  wire [31:0] seed_i,

    input  wire        en_i,

    output wire [31:0] rnd32_o,
    output reg         rnd_valid_o
);

    reg [31:0] state_q;

    wire feedback;
    wire [31:0] state_next;
    wire [31:0] seed_safe;

    assign feedback   = state_q[31] ^ state_q[21] ^ state_q[1] ^ state_q[0];
    assign state_next = {state_q[30:0], feedback};

    assign seed_safe = (seed_i == 32'h0000_0000) ? 32'h0000_0001 : seed_i;

    assign rnd32_o = state_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q     <= 32'h0000_0001;
            rnd_valid_o <= 1'b0;
        end else begin
            if (load_seed_i) begin
                state_q     <= seed_safe;
                rnd_valid_o <= 1'b0;
            end else if (en_i) begin
                state_q     <= state_next;
                rnd_valid_o <= 1'b1;
            end else begin
                state_q     <= state_q;
                rnd_valid_o <= 1'b0;
            end
        end
    end

endmodule