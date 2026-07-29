`ifndef LFSR32_RNG32
`define LFSR32_RNG32
import pbit_pkg::*;
module lfsr32_rng32 (
    input  logic                             clk,
    input  logic                             rst_n,
    input  logic                             soft_rstn_i,

    input  logic                             local_seed_we_i,
    input  logic                             cfg_node_load_i,
    input  logic [NODE_SEED_WIDTH-1:0]       global_cfg_seed_i,
    input  logic                             global_cfg_vld_i,                      
    input  logic [NODE_SEED_WIDTH-1:0]       row_cfg_seed_i,
    input  logic                             row_cfg_vld_i,
    input  logic [NODE_CFG_PACKED_WIDTH-1:0] local_node_cfg_i,
    input  logic [NODE_SEED_WIDTH-1:0]       local_cfg_seed_i,
    input  logic                             local_cfg_vld_i,
    input  logic                             en_i,
    output logic [NODE_SEED_WIDTH-1:0]       rnd32_o,
    output logic                             rnd_valid_o
);

    logic [NODE_SEED_WIDTH-1:0] global_cfg_seed_safe;
    logic [NODE_SEED_WIDTH-1:0] row_cfg_seed_safe;
    logic [NODE_SEED_WIDTH-1:0] local_cfg_seed_safe;
    logic [NODE_SEED_WIDTH-1:0] state_q, state_d;
    logic                       state_en;
    logic                       feedback;
    logic                       rnd_valid_q, rnd_valid_d;

    // Prevent each LFSR seed source from loading the all-zero lock-up state.
    assign global_cfg_seed_safe = (global_cfg_seed_i == 32'h0000_0000) ? 32'h0000_0001 : global_cfg_seed_i;
    assign row_cfg_seed_safe = (row_cfg_seed_i == 32'h0000_0000) ? 32'h0000_0001 : row_cfg_seed_i;
    assign local_cfg_seed_safe = (local_cfg_seed_i == 32'h0000_0000) ? 32'h0000_0001 : local_cfg_seed_i;
    assign feedback   = state_q[31] ^ state_q[21] ^ state_q[1] ^ state_q[0];
    assign state_d = local_seed_we_i? local_node_cfg_i[SEED_VALID_PACKED_MSB:SEED_VALID_PACKED_LSB]? local_cfg_seed_safe: state_q:
                     cfg_node_load_i? local_cfg_vld_i? state_q:
                                      row_cfg_vld_i? row_cfg_seed_safe:
                                      global_cfg_vld_i? global_cfg_seed_safe:
                                      state_q:
                     en_i?            {state_q[30:0], feedback}:
                                      state_q;
    assign state_en = local_seed_we_i | cfg_node_load_i | en_i;
    assign rnd32_o = state_q;
    assign rnd_valid_d = en_i;
    assign rnd_valid_o = rnd_valid_q;

    dffsre #(.WIDTH(NODE_SEED_WIDTH),
             .RESET_VALUE({{(NODE_SEED_WIDTH-1){1'b0}}, 1'b1})
    ) state_ff (
        .clk(clk),
        .rst_n(rst_n),
        .soft_rstn_i(soft_rstn_i),
        .en_i(state_en),
        .d_i(state_d),
        .q_o(state_q)
    );

    dffsr #(.WIDTH(1)
    ) rnd_valid_ff (
        .clk(clk),
        .rst_n(rst_n),
        .soft_rstn_i(soft_rstn_i),
        .d_i(rnd_valid_d),
        .q_o(rnd_valid_q)
    );
endmodule
`endif
