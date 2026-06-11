`timescale 1ns / 1ps

module edge_reg_coupler (
    input  wire       clk,
    input  wire       rst_n,

    // ------------------------------------------------------------
    // Configuration / initialization interface
    // Only used during CONFIG phase.
    // ------------------------------------------------------------
    input  wire       cfg_we_i,
    input  wire [3:0] cfg_prob4_i,
    input  wire       cfg_edge_sign_i,   // 1: J=+1, 0: J=-1
    input  wire       cfg_valid_i,

    // ------------------------------------------------------------
    // Runtime p-bit spin inputs from two endpoints
    // ------------------------------------------------------------
    input  wire       pbit_a_spin_i,     // 1: +1, 0: -1
    input  wire       pbit_b_spin_i,     // 1: +1, 0: -1

    // ------------------------------------------------------------
    // Output to p-bit A
    // A sees B as its neighbor.
    // ------------------------------------------------------------
    output wire [3:0] prob4_to_a_o,
    output wire       edge_sign_to_a_o,
    output wire       valid_to_a_o,
    output wire       neighbor_spin_to_a_o,

    // ------------------------------------------------------------
    // Output to p-bit B
    // B sees A as its neighbor.
    // ------------------------------------------------------------
    output wire [3:0] prob4_to_b_o,
    output wire       edge_sign_to_b_o,
    output wire       valid_to_b_o,
    output wire       neighbor_spin_to_b_o

    // ------------------------------------------------------------
    // Optional debug / readback
    // ------------------------------------------------------------

);

    reg [3:0] prob4_q;
    reg       edge_sign_q;
    reg       valid_q;

    // ------------------------------------------------------------
    // Edge configuration registers
    // ------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prob4_q     <= 4'd0;
            edge_sign_q <= 1'b1;
            valid_q     <= 1'b0;
        end else if (cfg_we_i) begin
            prob4_q     <= cfg_prob4_i;
            edge_sign_q <= cfg_edge_sign_i;
            valid_q     <= cfg_valid_i;
        end
    end

    // ------------------------------------------------------------
    // Same edge parameters are seen by both endpoints.
    // This is an undirected symmetric coupler.
    // ------------------------------------------------------------
    assign prob4_to_a_o     = prob4_q;
    assign edge_sign_to_a_o = edge_sign_q;
    assign valid_to_a_o     = valid_q;

    assign prob4_to_b_o     = prob4_q;
    assign edge_sign_to_b_o = edge_sign_q;
    assign valid_to_b_o     = valid_q;

    // ------------------------------------------------------------
    // Neighbor spin routing
    // ------------------------------------------------------------
    assign neighbor_spin_to_a_o = pbit_b_spin_i;
    assign neighbor_spin_to_b_o = pbit_a_spin_i;

    // ------------------------------------------------------------
    // Debug / readback
    // ------------------------------------------------------------
  
endmodule