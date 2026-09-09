`ifndef PBIT_NODE
`define PBIT_NODE
import pbit_pkg::*;
module pbit_node (
    input  logic                                 clk,
    input  logic                                 rst_n,

    // ------------------------------------------------------------
    // Node configuration interface.
    // Used during CONFIG phase.
    // ------------------------------------------------------------
    input  logic                                 local_cfg_node_we_i,
    input  logic [NODE_CFG_PACKED_WIDTH-1:0]     local_node_cfg_i          ,

    output logic [NODE_CFG_W-1:0]                local_node_rcfg_o,

    output logic [NODE_CFG_BIAS_SIGN_WIDTH-1:0]  bias_sign_o,
    output logic [NODE_CFG_BIAS_PROB_WIDTH-1:0]  bias_prob_o,

    // ------------------------------------------------------------
    // Runtime
    // ------------------------------------------------------------
    input  logic                                 majority_en_i,
    input  logic                                 majority_spin_i,
    output logic                                 spin_o
);

    // ------------------------------------------------------------
    // Clamp and bias registers.
    // ------------------------------------------------------------
    logic [NODE_CFG_INIT_SPIN_WIDTH-1:0]  local_cfg_init_spin_w ;
    logic [NODE_CFG_CLAMP_EN_WIDTH-1:0]   local_cfg_clamp_en_w  ;
    logic [NODE_CFG_CLAMP_SPIN_WIDTH-1:0] local_cfg_clamp_spin_w;
    logic [NODE_CFG_BIAS_SIGN_WIDTH-1:0]  local_cfg_bias_sign_w ;
    logic [NODE_CFG_BIAS_PROB_WIDTH-1:0]  local_cfg_bias_prob_w;
    logic [NODE_CFG_CLAMP_EN_WIDTH-1:0]   clamp_en_q;
    logic [NODE_CFG_CLAMP_SPIN_WIDTH-1:0] clamp_spin_q;
    logic [NODE_CFG_BIAS_SIGN_WIDTH-1:0]  bias_sign_q;
    logic [NODE_CFG_BIAS_PROB_WIDTH-1:0]  bias_prob_q;
    logic                                 init_we;
    logic                                 clamp_we;
    logic                                 bias_we;

    // ------------------------------------------------------------
    // output
    // ------------------------------------------------------------
    logic                           spin_q, spin_d;

    // ------------------------------------------------------------
    // Clamp and bias registers.
    // ------------------------------------------------------------
    assign local_cfg_init_spin_w  = local_node_cfg_i[NODE_CFG_INIT_SPIN_PACKED_MSB:NODE_CFG_INIT_SPIN_PACKED_LSB];
    assign local_cfg_clamp_en_w   = local_node_cfg_i[NODE_CFG_CLAMP_EN_PACKED_MSB:NODE_CFG_CLAMP_EN_PACKED_LSB];
    assign local_cfg_clamp_spin_w = local_node_cfg_i[NODE_CFG_CLAMP_SPIN_PACKED_MSB:NODE_CFG_CLAMP_SPIN_PACKED_LSB];
    assign local_cfg_bias_sign_w  = local_node_cfg_i[NODE_CFG_BIAS_SIGN_PACKED_MSB:NODE_CFG_BIAS_SIGN_PACKED_LSB];
    assign local_cfg_bias_prob_w  = local_node_cfg_i[NODE_CFG_BIAS_PROB_PACKED_MSB:NODE_CFG_BIAS_PROB_PACKED_LSB];
    // Field-valid bits are write masks, not persistent configuration ownership.
    assign init_we  = local_cfg_node_we_i && local_node_cfg_i[INIT_VALID_PACKED_LSB];
    assign clamp_we = local_cfg_node_we_i && local_node_cfg_i[CLAMP_VALID_PACKED_LSB];
    assign bias_we  = local_cfg_node_we_i && local_node_cfg_i[BIAS_VALID_PACKED_LSB];

    // Preserve the original priority and registered-clamp timing.
    // A newly written clamp takes effect on spin at the following clock edge.
    assign spin_d = clamp_en_q   ? clamp_spin_q :
                    majority_en_i ? majority_spin_i :
                    init_we       ? local_cfg_init_spin_w :
                                    spin_q;
    assign spin_o = spin_q;
    assign local_node_rcfg_o = {bias_prob_q, bias_sign_q, clamp_spin_q, clamp_en_q, spin_q};
    assign bias_sign_o = bias_sign_q;
    assign bias_prob_o = bias_prob_q;

    dffre #(.WIDTH(NODE_CFG_CLAMP_EN_WIDTH)
    ) clamp_en_ff (
        .clk(clk),
        .rst_n(rst_n),
        .en_i(clamp_we),
        .d_i(local_cfg_clamp_en_w),
        .q_o(clamp_en_q)
    );

    dffre #(.WIDTH(NODE_CFG_CLAMP_SPIN_WIDTH)
    ) clamp_spin_ff (
        .clk(clk),
        .rst_n(rst_n),
        .en_i(clamp_we),
        .d_i(local_cfg_clamp_spin_w),
        .q_o(clamp_spin_q)
    );

    dffre #(.WIDTH(NODE_CFG_BIAS_SIGN_WIDTH)
    ) bias_sign_ff (
        .clk(clk),
        .rst_n(rst_n),
        .en_i(bias_we),
        .d_i(local_cfg_bias_sign_w),
        .q_o(bias_sign_q)
    );

    dffre #(.WIDTH(NODE_CFG_BIAS_PROB_WIDTH)
    ) bias_prob_ff (
        .clk(clk),
        .rst_n(rst_n),
        .en_i(bias_we),
        .d_i(local_cfg_bias_prob_w),
        .q_o(bias_prob_q)
    );

    dffr #(.WIDTH(1)
    ) spin_ff (
        .clk(clk),
        .rst_n(rst_n),
        .d_i(spin_d),
        .q_o(spin_q)
    );
endmodule
`endif
