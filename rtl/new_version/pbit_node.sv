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
    input  logic [NODE_CFG_INIT_SPIN_WIDTH-1:0]  global_cfg_init_spin_i, 
    input  logic [NODE_CFG_CLAMP_EN_WIDTH-1:0]   global_cfg_clamp_en_i,  
    input  logic [NODE_CFG_CLAMP_SPIN_WIDTH-1:0] global_cfg_clamp_spin_i,
    input  logic [NODE_CFG_BIAS_SIGN_WIDTH-1:0]  global_cfg_bias_sign_i, 
    input  logic [NODE_CFG_BIAS_PROB_WIDTH-1:0]  global_cfg_bias_prob_i,
    input  logic                                 global_cfg_vld_i,
      
    input  logic [NODE_CFG_INIT_SPIN_WIDTH-1:0]  row_cfg_init_spin_i, 
    input  logic [NODE_CFG_CLAMP_EN_WIDTH-1:0]   row_cfg_clamp_en_i,  
    input  logic [NODE_CFG_CLAMP_SPIN_WIDTH-1:0] row_cfg_clamp_spin_i,
    input  logic [NODE_CFG_BIAS_SIGN_WIDTH-1:0]  row_cfg_bias_sign_i, 
    input  logic [NODE_CFG_BIAS_PROB_WIDTH-1:0]  row_cfg_bias_prob_i,
    input  logic                                 row_cfg_vld_i,
                                 
    input  logic                                 local_cfg_node_we_i       ,
    input  logic                                 local_cfg_clr_pulse_i     ,
    input  logic                                 local_cfg_clr_all_pulse_i ,
    input  logic [NODE_CFG_PACKED_WIDTH-1:0]     local_node_cfg_i          ,

    output logic [NODE_CFG_W-1:0]                local_node_rcfg_o,

    input  logic                                 cfg_node_load_i,

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
    logic [NODE_CFG_CLAMP_EN_WIDTH-1:0]   clamp_en_q, clamp_en_d;
    logic [NODE_CFG_CLAMP_SPIN_WIDTH-1:0] clamp_spin_q, clamp_spin_d;
    logic [NODE_CFG_BIAS_SIGN_WIDTH-1:0]  bias_sign_q, bias_sign_d;
    logic [NODE_CFG_BIAS_PROB_WIDTH-1:0]  bias_prob_q, bias_prob_d;
    logic                                 bias_prob_en;
    logic                                 local_cfg_vld_q, local_cfg_vld_d;

    // ------------------------------------------------------------
    // majority vote
    // ------------------------------------------------------------
    logic [NUM_MAJORITY_WIDTH:0] spin_sum_w;
    logic [NUM_MAJORITY_WIDTH:0] num_majority_act_w;
    logic                        majority_en_w;
    logic                        majority_spin_w;

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
    assign clamp_en_d   = local_cfg_node_we_i? local_node_cfg_i[CLAMP_VALID_PACKED_MSB:CLAMP_VALID_PACKED_LSB]? local_cfg_clamp_en_w: clamp_en_q: 
                          cfg_node_load_i? local_cfg_vld_q? clamp_en_q:
                                           row_cfg_vld_i? row_cfg_clamp_en_i:
                                           global_cfg_vld_i? global_cfg_clamp_en_i: 
                                           clamp_en_q:
                          clamp_en_q;
    assign clamp_spin_d = local_cfg_node_we_i? local_node_cfg_i[CLAMP_VALID_PACKED_MSB:CLAMP_VALID_PACKED_LSB]? local_cfg_clamp_spin_w: clamp_spin_q:
                          cfg_node_load_i? local_cfg_vld_q? clamp_spin_q:
                                           row_cfg_vld_i? row_cfg_clamp_spin_i:
                                           global_cfg_vld_i? global_cfg_clamp_spin_i: 
                                           clamp_spin_q:
                          clamp_spin_q;
    assign bias_sign_d  = local_cfg_node_we_i? local_node_cfg_i[BIAS_VALID_PACKED_MSB:BIAS_VALID_PACKED_LSB]? local_cfg_bias_sign_w: bias_sign_q: 
                          cfg_node_load_i? local_cfg_vld_q? bias_sign_q:
                                           row_cfg_vld_i? row_cfg_bias_sign_i:
                                           global_cfg_vld_i? global_cfg_bias_sign_i: 
                                           bias_sign_q:
                          bias_sign_q;
    assign bias_prob_d  = local_cfg_node_we_i? local_node_cfg_i[BIAS_VALID_PACKED_MSB:BIAS_VALID_PACKED_LSB]? local_cfg_bias_prob_w: bias_prob_q: 
                           cfg_node_load_i? local_cfg_vld_q? bias_prob_q:
                                            row_cfg_vld_i? row_cfg_bias_prob_i:
                                            global_cfg_vld_i? global_cfg_bias_prob_i: 
                                            bias_prob_q:
                           bias_prob_q;
    assign bias_prob_en = local_cfg_node_we_i | cfg_node_load_i;
    assign local_cfg_vld_d   = local_cfg_node_we_i? 1'b1:
                               local_cfg_clr_pulse_i | local_cfg_clr_all_pulse_i? 1'b0:
                               local_cfg_vld_q;
    assign spin_d = clamp_en_q? clamp_spin_q:
                    majority_en_i? majority_spin_i:
                    local_cfg_node_we_i? local_node_cfg_i[INIT_VALID_PACKED_MSB:INIT_VALID_PACKED_LSB]? local_cfg_init_spin_w: spin_q:
                    cfg_node_load_i? local_cfg_vld_q? spin_q: 
                                     row_cfg_vld_i? row_cfg_init_spin_i:
                                     global_cfg_vld_i? global_cfg_init_spin_i:
                                     spin_q:
                    spin_q;
    assign spin_o = spin_q;
    assign local_node_rcfg_o = {bias_prob_q, bias_sign_q, clamp_spin_q, clamp_en_q, spin_q};
    assign bias_sign_o = bias_sign_q;
    assign bias_prob_o = bias_prob_q;

    dffr #(.WIDTH(NODE_CFG_CLAMP_EN_WIDTH)
    ) clamp_en_ff (
        .clk(clk),
        .rst_n(rst_n),
        .d_i(clamp_en_d),
        .q_o(clamp_en_q)
    );

    dff #(.WIDTH(NODE_CFG_CLAMP_SPIN_WIDTH)
    ) clamp_spin_ff (
        .clk(clk),
        .d_i(clamp_spin_d),
        .q_o(clamp_spin_q)
    );

    dffr #(.WIDTH(NODE_CFG_BIAS_SIGN_WIDTH)
    ) bias_sign_ff (
        .clk(clk),
        .rst_n(rst_n),
        .d_i(bias_sign_d),
        .q_o(bias_sign_q)
    );

    dffre #(.WIDTH(NODE_CFG_BIAS_PROB_WIDTH)
    ) bias_prob_ff (
        .clk(clk),
        .rst_n(rst_n),
        .en_i(bias_prob_en),
        .d_i(bias_prob_d),
        .q_o(bias_prob_q)
    );

    dffr #(.WIDTH(1)
    ) local_cfg_vld_ff (
        .clk(clk),
        .rst_n(rst_n),
        .d_i(local_cfg_vld_d),
        .q_o(local_cfg_vld_q)
    );

    dff #(.WIDTH(1)
    ) spin_ff (
        .clk(clk),
        .d_i(spin_d),
        .q_o(spin_q)
    );
endmodule
`endif