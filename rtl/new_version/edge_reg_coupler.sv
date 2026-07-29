`ifndef EDGE_REG_COUPLER
`define EDGE_REG_COUPLER
import pbit_pkg::*;
module edge_reg_coupler (
    input  logic       clk,

    // ------------------------------------------------------------
    // Configuration / initialization interface
    // Only used during CONFIG phase.
    // ------------------------------------------------------------
    input  logic                                 cfg_we_i,
    input  logic                                 cfg_clr_pulse_i,
    input  logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0]  cfg_prob_i,
    input  logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0]  cfg_edge_sign_i,   // 1: J=+1, 0: J=-1
    input  logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] cfg_valid_i,

    // ------------------------------------------------------------
    // Runtime p-bit spin inputs from two endpoints
    // ------------------------------------------------------------
    input  logic                                 pbit_a_spin_i,     // 1: +1, 0: -1
    input  logic                                 pbit_b_spin_i,     // 1: +1, 0: -1

    // ------------------------------------------------------------
    // Output to p-bit A
    // A sees B as its neighbor.
    // ------------------------------------------------------------
    output logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0]  prob_to_a_o,
    output logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0]  edge_sign_to_a_o,
    output logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] valid_to_a_o,
    output logic                                 neighbor_spin_to_a_o,

    // ------------------------------------------------------------
    // Output to p-bit B
    // B sees A as its neighbor.
    // ------------------------------------------------------------
    output logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0]  prob_to_b_o,
    output logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0]  edge_sign_to_b_o,
    output logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] valid_to_b_o,
    output logic                                 neighbor_spin_to_b_o
);

    // ------------------------------------------------------------
    // Edge configuration registers
    // ------------------------------------------------------------
    logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0]  prob_q, prob_d;
    logic                                 prob_en;
    logic [EDGE_CFG_EDGE_SIGN_WIDTH-1:0]  edge_sign_q, edge_sign_d;
    logic [EDGE_CFG_EDGE_VALID_WIDTH-1:0] valid_q, valid_d;

    // ------------------------------------------------------------
    // Edge configuration registers's d assignment
    // ------------------------------------------------------------
    assign prob_d  = cfg_prob_i;
    assign prob_en = cfg_we_i;
    assign edge_sign_d = cfg_we_i? cfg_edge_sign_i: edge_sign_q;
    assign valid_d = cfg_clr_pulse_i? {EDGE_CFG_EDGE_VALID_WIDTH{1'b0}}:
                     cfg_we_i? cfg_valid_i:
                     valid_q;
    
    dffe #(.WIDTH(EDGE_CFG_EDGE_PROB_WIDTH)
    ) prob_ff (
        .clk(clk),
        .en_i(prob_en),
        .d_i(prob_d),
        .q_o(prob_q)
    );

    dff #(.WIDTH(EDGE_CFG_EDGE_SIGN_WIDTH)
    ) edge_sign_ff (
        .clk(clk),
        .d_i(edge_sign_d),
        .q_o(edge_sign_q)
    );

    dff #(.WIDTH(EDGE_CFG_EDGE_VALID_WIDTH)
    ) valid_ff (
        .clk(clk),
        .d_i(valid_d),
        .q_o(valid_q)
    );  
    // ------------------------------------------------------------
    // Same edge parameters are seen by both endpoints.
    // This is an undirected symmetric coupler.
    // ------------------------------------------------------------
    assign prob_to_a_o     = prob_q;
    assign edge_sign_to_a_o = edge_sign_q;
    assign valid_to_a_o     = valid_q;

    assign prob_to_b_o     = prob_q;
    assign edge_sign_to_b_o = edge_sign_q;
    assign valid_to_b_o     = valid_q;

    // ------------------------------------------------------------
    // Neighbor spin routing
    // ------------------------------------------------------------
    assign neighbor_spin_to_a_o = pbit_b_spin_i;
    assign neighbor_spin_to_b_o = pbit_a_spin_i;

endmodule
`endif