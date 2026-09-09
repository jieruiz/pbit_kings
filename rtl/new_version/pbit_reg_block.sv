`ifndef PBIT_REG_BLOCK
`define PBIT_REG_BLOCK
import pbit_pkg::*;
// Register layout follows pbit_register_file.xlsx. Reserved fields read as zero.
// Bus accesses complete in one cycle. Array CMD completion is reported via DONE.
module pbit_reg_block (
    input  logic clk,
    input  logic rst_n,
    input  logic reg_wr_en_i,
    input  logic reg_rd_en_i,
    input  logic [15:0] reg_addr_i,
    input  logic [31:0] reg_wdata_i,
    output logic [31:0] reg_rdata_o,
    output logic reg_access_error_o,
    input  logic run_busy_i,
    input  logic run_done_i,
    input  logic uart_frame_err_pulse_i,
    input  logic uart_overflow_pulse_i,
    input  logic [SNAPSHOT_WIDTH-1:0] snapshot_flat_i,
    input  logic snapshot_vld_i,
    output logic [SNAPSHOT_ADDR_WIDTH-1:0] snapshot_addr_o,
    output logic snapshot_latch_pulse_o,
    output logic snapshot_valid_clr_o,
    output logic [I0_LEVEL_WIDTH-1:0] i0_level_o [SWEEP_ROUND_NUM],
    output logic [SWEEP_INTERVAL_WIDTH-1:0] sweep_interval_o [SWEEP_ROUND_NUM],
    output logic cfg_done_o,
    output logic run_start_pulse_o,
    output logic run_done_clr_pulse_o,
    output logic [NUM_SWEEP_WIDTH-1:0] num_sweeps_o,
    output logic [NUM_MAJORITY_WIDTH-1:0] num_majority_o,
    output logic cfg_req_valid_o,
    input  logic cfg_req_ready_i,
    output cfg_array_req_t cfg_req_o,
    input  logic cfg_rsp_valid_i,
    input  var cfg_rsp_t cfg_rsp_i
);
    // ------------------------------------------------------------
    // Signal declarations
    // ------------------------------------------------------------
    localparam logic [ERROR_STATUS_PACKED_WIDTH-1:0] BUS_ERROR_MASK =
        ~((ERROR_STATUS_PACKED_WIDTH'(1) << UART_FRAME_ERR_LSB) |
          (ERROR_STATUS_PACKED_WIDTH'(1) << UART_OVERFLOW_LSB));
    logic access_w, addr_known_w, readable_w, writable_w, read_w, write_w;
    logic ctrl_w, cmd_w, cmd_apply_w, cmd_clear_w, cmd_readback_w;
    cfg_target_e cmd_target_w;
    cfg_array_req_t req_d;
    logic [31:0] bus_rdata_w;
    logic [GLOBAL_STATUS_PACKED_WIDTH-1:0] status_w;
    logic [ERROR_STATUS_PACKED_WIDTH-1:0] error_q, error_d, error_set_w, error_clear_w, cmd_error_w;
    logic access_error_w, issue_w, local_reject_w, cmd_accept_w, response_w;
    logic cfg_busy_q, cfg_busy_d, req_valid_d;
    logic node_done_q, seed_done_q, edge_done_q, node_done_d, seed_done_d, edge_done_d;
    logic cfg_done_d, run_start_d, run_done_clear_d, snapshot_latch_d;
    logic runtime_w, status_read_w;
    logic [NODE_CFG_W-1:0] node_rdata_q, node_rdata_d;
    logic [SEED_WIDTH-1:0] seed_rdata_q, seed_rdata_d;
    logic [EDGE_RDATA_PACKED_WIDTH-1:0] edge_rdata_q, edge_rdata_d;
    logic node_rdata_en, seed_rdata_en, edge_rdata_en;
    logic [I0_LEVEL_REG_NUM-1:0] i0_hit_w;
    logic [SWEEP_INTERVAL_REG_NUM-1:0] interval_hit_w;
    logic [SPIN_RDATA_REG_NUM-1:0] spin_hit_w;
    logic [UNIT_TARGET_PACKED_WIDTH-1:0] unit_target_q, unit_target_d;
    logic [NODE_TARGET_PACKED_WIDTH-1:0] node_target_q, node_target_d;
    logic [NODE_CFG_PACKED_WIDTH-1:0] node_cfg_q, node_cfg_d;
    logic [SEED_TARGET_PACKED_WIDTH-1:0] seed_target_q, seed_target_d;
    logic [SEED_WIDTH-1:0] seed_q, seed_d;
    logic [EDGE_TARGET_PACKED_WIDTH-1:0] edge_target_q, edge_target_d;
    logic [EDGE_CFG_PACKED_WIDTH-1:0] edge_cfg_q, edge_cfg_d;
    logic [GLOBAL_CFG_PACKED_WIDTH-1:0] global_cfg_q, global_cfg_d;
    logic [SNAPSHOT_ADDR_WIDTH-1:0] snapshot_addr_q, snapshot_addr_d;

    // ------------------------------------------------------------
    // Combinational decode and next-value logic
    // ------------------------------------------------------------
    // Cover the cycle between registered RUN_START and the scheduler's RUN_BUSY.
    assign runtime_w = run_busy_i || run_start_pulse_o;
    assign access_w = reg_wr_en_i || reg_rd_en_i;
    assign read_w = reg_rd_en_i && !reg_wr_en_i && addr_known_w && readable_w;
    assign write_w = reg_wr_en_i && addr_known_w && writable_w;
    assign ctrl_w = write_w && (reg_addr_i == A_GLOBAL_CTRL);
    assign status_read_w = read_w && (reg_addr_i == A_GLOBAL_STATUS);
    // Clear on the same edge that captures the pre-clear status for bus readback.
    assign snapshot_valid_clr_o = status_read_w;
    assign unit_target_d[UNIT_TARGET_ROW_PACKED_MSB:UNIT_TARGET_ROW_PACKED_LSB] = reg_wdata_i[UNIT_TARGET_ROW_MSB:UNIT_TARGET_ROW_LSB];
    assign unit_target_d[UNIT_TARGET_COL_PACKED_MSB:UNIT_TARGET_COL_PACKED_LSB] = reg_wdata_i[UNIT_TARGET_COL_MSB:UNIT_TARGET_COL_LSB];
    assign node_target_d[NODE_TARGET_ROW_PACKED_MSB:NODE_TARGET_ROW_PACKED_LSB] = reg_wdata_i[NODE_TARGET_ROW_MSB:NODE_TARGET_ROW_LSB];
    assign node_target_d[NODE_TARGET_COL_PACKED_MSB:NODE_TARGET_COL_PACKED_LSB] = reg_wdata_i[NODE_TARGET_COL_MSB:NODE_TARGET_COL_LSB];
    assign node_cfg_d[INIT_VALID_PACKED_MSB:INIT_VALID_PACKED_LSB] = reg_wdata_i[INIT_VALID_MSB:INIT_VALID_LSB];
    assign node_cfg_d[CLAMP_VALID_PACKED_MSB:CLAMP_VALID_PACKED_LSB] = reg_wdata_i[CLAMP_VALID_MSB:CLAMP_VALID_LSB];
    assign node_cfg_d[BIAS_VALID_PACKED_MSB:BIAS_VALID_PACKED_LSB] = reg_wdata_i[BIAS_VALID_MSB:BIAS_VALID_LSB];
    assign node_cfg_d[NODE_CFG_INIT_SPIN_PACKED_MSB:NODE_CFG_INIT_SPIN_PACKED_LSB] = reg_wdata_i[NODE_CFG_INIT_SPIN_MSB:NODE_CFG_INIT_SPIN_LSB];
    assign node_cfg_d[NODE_CFG_CLAMP_EN_PACKED_MSB:NODE_CFG_CLAMP_EN_PACKED_LSB] = reg_wdata_i[NODE_CFG_CLAMP_EN_MSB:NODE_CFG_CLAMP_EN_LSB];
    assign node_cfg_d[NODE_CFG_CLAMP_SPIN_PACKED_MSB:NODE_CFG_CLAMP_SPIN_PACKED_LSB] = reg_wdata_i[NODE_CFG_CLAMP_SPIN_MSB:NODE_CFG_CLAMP_SPIN_LSB];
    assign node_cfg_d[NODE_CFG_BIAS_SIGN_PACKED_MSB:NODE_CFG_BIAS_SIGN_PACKED_LSB] = reg_wdata_i[NODE_CFG_BIAS_SIGN_MSB:NODE_CFG_BIAS_SIGN_LSB];
    assign node_cfg_d[NODE_CFG_BIAS_PROB_PACKED_MSB:NODE_CFG_BIAS_PROB_PACKED_LSB] = reg_wdata_i[NODE_CFG_BIAS_PROB_MSB:NODE_CFG_BIAS_PROB_LSB];
    assign seed_target_d[SEED_TARGET_NUMBER_PACKED_MSB:SEED_TARGET_NUMBER_PACKED_LSB] = reg_wdata_i[SEED_TARGET_NUMBER_MSB:SEED_TARGET_NUMBER_LSB];
    assign seed_d[SEED_PACKED_MSB:SEED_PACKED_LSB] = reg_wdata_i[SEED_MSB:SEED_LSB];
    assign edge_target_d[EDGE_TYPE_PACKED_MSB:EDGE_TYPE_PACKED_LSB] = reg_wdata_i[EDGE_TYPE_MSB:EDGE_TYPE_LSB];
    assign edge_target_d[EDGE_TARGET_NUMBER_PACKED_MSB:EDGE_TARGET_NUMBER_PACKED_LSB] = reg_wdata_i[EDGE_TARGET_NUMBER_MSB:EDGE_TARGET_NUMBER_LSB];
    assign edge_cfg_d[EDGE_CFG_EDGE_VALID_PACKED_MSB:EDGE_CFG_EDGE_VALID_PACKED_LSB] = reg_wdata_i[EDGE_CFG_EDGE_VALID_MSB:EDGE_CFG_EDGE_VALID_LSB];
    assign edge_cfg_d[EDGE_CFG_EDGE_SIGN_PACKED_MSB:EDGE_CFG_EDGE_SIGN_PACKED_LSB] = reg_wdata_i[EDGE_CFG_EDGE_SIGN_MSB:EDGE_CFG_EDGE_SIGN_LSB];
    assign edge_cfg_d[EDGE_CFG_EDGE_PROB_PACKED_MSB:EDGE_CFG_EDGE_PROB_PACKED_LSB] = reg_wdata_i[EDGE_CFG_EDGE_PROB_MSB:EDGE_CFG_EDGE_PROB_LSB];
    assign global_cfg_d[NUM_SWEEP_PACKED_MSB:NUM_SWEEP_PACKED_LSB] = reg_wdata_i[NUM_SWEEP_MSB:NUM_SWEEP_LSB];
    assign global_cfg_d[NUM_MAJORITY_PACKED_MSB:NUM_MAJORITY_PACKED_LSB] = reg_wdata_i[NUM_MAJORITY_MSB:NUM_MAJORITY_LSB];
    assign snapshot_addr_d[SNAPSHOT_ADDR_PACKED_MSB:SNAPSHOT_ADDR_PACKED_LSB] = reg_wdata_i[SNAPSHOT_ADDR_MSB:SNAPSHOT_ADDR_LSB];
    assign snapshot_addr_o = snapshot_addr_q;
    assign num_sweeps_o = global_cfg_q[NUM_SWEEP_PACKED_MSB:NUM_SWEEP_PACKED_LSB];
    assign num_majority_o = global_cfg_q[NUM_MAJORITY_PACKED_MSB:NUM_MAJORITY_PACKED_LSB];
    genvar g, f;
    generate
        for (g=0; g<I0_LEVEL_REG_NUM; g=g+1) begin : GEN_I0_HIT
            assign i0_hit_w[g] = (reg_addr_i == A_I0_LEVEL0 + 16'(4*g));
        end
        for (g=0; g<SWEEP_INTERVAL_REG_NUM; g=g+1) begin : GEN_INTERVAL_HIT
            assign interval_hit_w[g] = (reg_addr_i == A_SWEEP_INTERVAL0 + 16'(4*g));
        end
        for (g=0; g<SPIN_RDATA_REG_NUM; g=g+1) begin : GEN_SPIN_HIT
            assign spin_hit_w[g] = (reg_addr_i == A_SPIN_RDATA0 + 16'(4*g));
        end
    endgenerate
    // Explicit address permissions. Each process drives only one signal.
    always @(*) begin
        addr_known_w = 1'b1;
        case (reg_addr_i)
            A_GLOBAL_CTRL, A_NODE_CMD, A_SEED_CMD, A_EDGE_CMD,
            A_GLOBAL_STATUS, A_NODE_RDATA_CFG, A_SEED_RDATA, A_EDGE_RDATA,
            A_GLOBAL_CFG, A_ERROR_STATUS, A_SNAPSHOT_ADDR, A_UNIT_TARGET,
            A_NODE_TARGET, A_NODE_CFG, A_SEED_TARGET, A_SEED, A_EDGE_TARGET, A_EDGE_CFG: begin end
            default: addr_known_w = (|i0_hit_w) || (|interval_hit_w) || (|spin_hit_w);
        endcase
    end
    assign readable_w = !((reg_addr_i == A_GLOBAL_CTRL) || (reg_addr_i == A_NODE_CMD) ||
                          (reg_addr_i == A_SEED_CMD) || (reg_addr_i == A_EDGE_CMD));
    assign writable_w = !((reg_addr_i == A_GLOBAL_STATUS) || (reg_addr_i == A_NODE_RDATA_CFG) ||
                          (reg_addr_i == A_SEED_RDATA) || (reg_addr_i == A_EDGE_RDATA) || (|spin_hit_w));

    // W1P: zero/reserved-only writes are idle no-ops. Any runtime CMD write is illegal.
    always @(*) begin
        cmd_target_w = CFG_TARGET_NODE;
        if (write_w) begin
            case (reg_addr_i)
                A_SEED_CMD: cmd_target_w = CFG_TARGET_SEED;
                A_EDGE_CMD: cmd_target_w = CFG_TARGET_EDGE;
                default: begin end
            endcase
        end
    end
    always @(*) begin
        cmd_apply_w = 1'b0;
        if (write_w) begin
            case (reg_addr_i)
                A_NODE_CMD: cmd_apply_w = reg_wdata_i[APPLY_CFG_LSB];
                A_SEED_CMD: cmd_apply_w = reg_wdata_i[APPLY_SEED_LSB];
                A_EDGE_CMD: cmd_apply_w = reg_wdata_i[APPLY_EDGE_LSB];
                default: begin end
            endcase
        end
    end
    assign cmd_clear_w = write_w && (reg_addr_i == A_EDGE_CMD) && reg_wdata_i[CLEAR_EDGE_LSB];
    always @(*) begin
        cmd_readback_w = 1'b0;
        if (write_w) begin
            case (reg_addr_i)
                A_NODE_CMD: cmd_readback_w = reg_wdata_i[READBACK_CFG_LSB];
                A_SEED_CMD: cmd_readback_w = reg_wdata_i[READBACK_SEED_LSB];
                A_EDGE_CMD: cmd_readback_w = reg_wdata_i[READBACK_EDGE_LSB];
                default: begin end
            endcase
        end
    end
    assign cmd_w = write_w && (cmd_apply_w || cmd_clear_w || cmd_readback_w ||
        (runtime_w && ((reg_addr_i == A_NODE_CMD) || (reg_addr_i == A_SEED_CMD) || (reg_addr_i == A_EDGE_CMD))));
    always @(*) begin
        req_d='0;
        req_d.unit_row=unit_target_q[UNIT_TARGET_ROW_PACKED_MSB:UNIT_TARGET_ROW_PACKED_LSB];
        req_d.unit_col=unit_target_q[UNIT_TARGET_COL_PACKED_MSB:UNIT_TARGET_COL_PACKED_LSB];
        req_d.payload.target=cmd_target_w;
        req_d.payload.apply=cmd_apply_w;
        req_d.payload.clear=cmd_clear_w;
        req_d.payload.readback=cmd_readback_w;
        case(cmd_target_w)
            CFG_TARGET_NODE: begin
                req_d.payload.object_idx=CFG_OBJECT_WIDTH'(node_target_q);
                req_d.payload.wdata=CFG_DATA_WIDTH'(node_cfg_q);
            end
            CFG_TARGET_SEED: begin
                req_d.payload.object_idx=CFG_OBJECT_WIDTH'(seed_target_q);
                req_d.payload.wdata=(seed_q=='0) ? SEED_WIDTH'(1) : seed_q;
            end
            CFG_TARGET_EDGE: begin
                // Transport order differs from the software target register order.
                req_d.payload.object_idx={edge_target_q[EDGE_TYPE_PACKED_MSB:EDGE_TYPE_PACKED_LSB],
                                         edge_target_q[EDGE_TARGET_NUMBER_PACKED_MSB:EDGE_TARGET_NUMBER_PACKED_LSB]};
                req_d.payload.wdata=CFG_DATA_WIDTH'(edge_cfg_q);
            end
            default: begin end
        endcase
    end
    always @(*) begin
        cmd_error_w='0;
        if(cmd_w) begin
            if(cfg_busy_q) cmd_error_w[CFG_CMD_WHILE_BUSY_LSB]=1'b1;
            else begin
                cmd_error_w[UNIT_ROW_OOR_LSB]=(req_d.unit_row >= ROWS);
                cmd_error_w[UNIT_COL_OOR_LSB]=(req_d.unit_col >= COLS);
                if(cmd_target_w==CFG_TARGET_NODE)
                    cmd_error_w[NODE_CFG_WHILE_RUN_LSB]=runtime_w;
                if(cmd_target_w==CFG_TARGET_SEED)
                    cmd_error_w[SEED_CFG_WHILE_RUN_LSB]=runtime_w;
                if(cmd_target_w==CFG_TARGET_EDGE) begin
                    cmd_error_w[EDGE_CFG_WHILE_RUN_LSB]=runtime_w;
                    cmd_error_w[EDGE_TYPE_ERR_LSB]=(edge_target_q[EDGE_TYPE_PACKED_MSB:EDGE_TYPE_PACKED_LSB] >= EDGE_TYPE_WIDTH'(6));
                    cmd_error_w[EDGE_BOUNDARY_ERR_LSB]=
                        ((req_d.unit_col == COLS-1) && (edge_target_q[EDGE_TYPE_PACKED_MSB:EDGE_TYPE_PACKED_LSB] == EDGE_TYPE_WIDTH'(4))) ||
                        ((req_d.unit_row == ROWS-1) && (edge_target_q[EDGE_TYPE_PACKED_MSB:EDGE_TYPE_PACKED_LSB] == EDGE_TYPE_WIDTH'(5)));
                end
            end
        end
    end
    assign cmd_accept_w = cmd_w && !cfg_busy_q;
    assign issue_w = cmd_accept_w && !(|cmd_error_w);
    assign local_reject_w = cmd_accept_w && (|cmd_error_w);
    // A response completes an already accepted request, never one still awaiting ready.
    assign response_w = cfg_busy_q && !cfg_req_valid_o && cfg_rsp_valid_i;
    assign cfg_busy_d = issue_w ? 1'b1 : response_w ? 1'b0 : cfg_busy_q;
    assign req_valid_d = issue_w ? 1'b1 : (cfg_req_valid_o && cfg_req_ready_i) ? 1'b0 : cfg_req_valid_o;
    // Completion wins over RC and command acceptance. A busy rejection leaves
    // DONE/RDATA unchanged unless an independent old response completes that cycle.
    assign node_done_d = (response_w && cfg_req_o.payload.target == CFG_TARGET_NODE) ? 1'b1 :
                         (cmd_accept_w && cmd_target_w == CFG_TARGET_NODE) ? local_reject_w :
                         status_read_w ? 1'b0 : node_done_q;
    assign node_rdata_en = (response_w && cfg_req_o.payload.target == CFG_TARGET_NODE) ? cfg_req_o.payload.readback :
                           (local_reject_w && cmd_target_w == CFG_TARGET_NODE && cmd_readback_w);
    assign node_rdata_d = (response_w && cfg_req_o.payload.target == CFG_TARGET_NODE) ?
                          cfg_rsp_i.rdata[NODE_CFG_W-1:0] : '0;
    assign seed_done_d = (response_w && cfg_req_o.payload.target == CFG_TARGET_SEED) ? 1'b1 :
                         (cmd_accept_w && cmd_target_w == CFG_TARGET_SEED) ? local_reject_w :
                         status_read_w ? 1'b0 : seed_done_q;
    assign seed_rdata_en = (response_w && cfg_req_o.payload.target == CFG_TARGET_SEED) ? cfg_req_o.payload.readback :
                           (local_reject_w && cmd_target_w == CFG_TARGET_SEED && cmd_readback_w);
    assign seed_rdata_d = (response_w && cfg_req_o.payload.target == CFG_TARGET_SEED) ?
                          cfg_rsp_i.rdata[SEED_WIDTH-1:0] : '0;
    assign edge_done_d = (response_w && cfg_req_o.payload.target == CFG_TARGET_EDGE) ? 1'b1 :
                         (cmd_accept_w && cmd_target_w == CFG_TARGET_EDGE) ? local_reject_w :
                         status_read_w ? 1'b0 : edge_done_q;
    assign edge_rdata_en = (response_w && cfg_req_o.payload.target == CFG_TARGET_EDGE) ? cfg_req_o.payload.readback :
                           (local_reject_w && cmd_target_w == CFG_TARGET_EDGE && cmd_readback_w);
    assign edge_rdata_d = (response_w && cfg_req_o.payload.target == CFG_TARGET_EDGE) ?
                          cfg_rsp_i.rdata[EDGE_RDATA_PACKED_WIDTH-1:0] : '0;
    always @(*) begin
        error_set_w=cmd_error_w;
        if(access_w && !addr_known_w) error_set_w[ADDR_ERR_LSB]=1'b1;
        if(reg_wr_en_i && addr_known_w && !writable_w) error_set_w[WR_TO_RO_LSB]=1'b1;
        if(reg_rd_en_i && !reg_wr_en_i && addr_known_w && !readable_w) error_set_w[RD_TO_WO_LSB]=1'b1;
        if(write_w && runtime_w && reg_addr_i==A_GLOBAL_CFG) error_set_w[GLOBAL_CFG_WHILE_RUN_LSB]=1'b1;
        if(write_w && runtime_w && (|i0_hit_w)) error_set_w[I0_CFG_WHILE_RUN_LSB]=1'b1;
        if(write_w && runtime_w && (|interval_hit_w)) error_set_w[SWEEP_CFG_WHILE_RUN_LSB]=1'b1;
        if(ctrl_w && reg_wdata_i[RUN_START_LSB]) begin
            error_set_w[RUN_WITHOUT_CFG_DONE_LSB]=!cfg_done_o;
            error_set_w[RUN_WHEN_BUSY_LSB]=runtime_w;
            error_set_w[RUN_WHILE_CFG_BUSY_LSB]=cfg_busy_q;
        end
        if(ctrl_w && reg_wdata_i[SNAPSHOT_LATCH_LSB] && snapshot_addr_q >= SPIN_ADDR_MAX)
            error_set_w[SNAP_ADDR_OOR_LSB]=1'b1;
        error_set_w[UART_FRAME_ERR_LSB]=uart_frame_err_pulse_i;
        error_set_w[UART_OVERFLOW_LSB]=uart_overflow_pulse_i;
    end
    // UART events set sticky status but do not fail an unrelated bus access.
    assign access_error_w = access_w && (|(error_set_w & BUS_ERROR_MASK));
    always @(*) begin
        error_clear_w='0;
        if(write_w && reg_addr_i==A_ERROR_STATUS) error_clear_w=reg_wdata_i[ERROR_STATUS_PACKED_WIDTH-1:0];
        if(ctrl_w && reg_wdata_i[ERROR_CLEAR_LSB]) error_clear_w='1;
    end
    // Newly arriving errors win over W1C/ERROR_CLEAR in the same cycle.
    assign error_d=(error_q & ~error_clear_w) | error_set_w;
    assign cfg_done_d = (ctrl_w && reg_wdata_i[CFG_DONE_SET_LSB]) ? 1'b1 :
                        (ctrl_w && reg_wdata_i[CFG_DONE_CLEAR_LSB]) ? 1'b0 : cfg_done_o;
    assign run_start_d = ctrl_w && reg_wdata_i[RUN_START_LSB] && cfg_done_o && !runtime_w && !cfg_busy_q;
    assign run_done_clear_d = ctrl_w && reg_wdata_i[RUN_DONE_CLEAR_LSB];
    assign snapshot_latch_d = ctrl_w && reg_wdata_i[SNAPSHOT_LATCH_LSB] && (snapshot_addr_q < SPIN_ADDR_MAX);
    always @(*) begin
        status_w='0;
        status_w[CFG_DONE_LSB]=cfg_done_o;
        status_w[RUN_BUSY_LSB]=run_busy_i;
        status_w[RUN_DONE_LSB]=run_done_i;
        status_w[NODE_CMD_DONE_LSB]=node_done_q;
        status_w[EDGE_CMD_DONE_LSB]=edge_done_q;
        status_w[SNAPSHOT_VALID_LSB]=snapshot_vld_i;
        status_w[ERROR_LSB]=|error_q;
        status_w[SEED_CMD_DONE_LSB]=seed_done_q;
        status_w[CFG_BUSY_LSB]=cfg_busy_q;
    end
    always @(*) begin
        bus_rdata_w='0;
        if(read_w) begin
            case(reg_addr_i)
                A_GLOBAL_STATUS: bus_rdata_w=32'(status_w);
                A_ERROR_STATUS: bus_rdata_w=32'(error_q);
                A_NODE_RDATA_CFG: bus_rdata_w=32'(node_rdata_q);
                A_SEED_RDATA: bus_rdata_w=seed_rdata_q;
                A_EDGE_RDATA: bus_rdata_w=32'(edge_rdata_q);
                A_UNIT_TARGET: begin
                    bus_rdata_w[UNIT_TARGET_ROW_MSB:UNIT_TARGET_ROW_LSB]=unit_target_q[UNIT_TARGET_ROW_PACKED_MSB:UNIT_TARGET_ROW_PACKED_LSB];
                    bus_rdata_w[UNIT_TARGET_COL_MSB:UNIT_TARGET_COL_LSB]=unit_target_q[UNIT_TARGET_COL_PACKED_MSB:UNIT_TARGET_COL_PACKED_LSB];
                end
                A_NODE_TARGET: begin
                    bus_rdata_w[NODE_TARGET_ROW_MSB:NODE_TARGET_ROW_LSB]=node_target_q[NODE_TARGET_ROW_PACKED_MSB:NODE_TARGET_ROW_PACKED_LSB];
                    bus_rdata_w[NODE_TARGET_COL_MSB:NODE_TARGET_COL_LSB]=node_target_q[NODE_TARGET_COL_PACKED_MSB:NODE_TARGET_COL_PACKED_LSB];
                end
                A_NODE_CFG: begin
                    bus_rdata_w[INIT_VALID_MSB:INIT_VALID_LSB]=node_cfg_q[INIT_VALID_PACKED_MSB:INIT_VALID_PACKED_LSB];
                    bus_rdata_w[CLAMP_VALID_MSB:CLAMP_VALID_LSB]=node_cfg_q[CLAMP_VALID_PACKED_MSB:CLAMP_VALID_PACKED_LSB];
                    bus_rdata_w[BIAS_VALID_MSB:BIAS_VALID_LSB]=node_cfg_q[BIAS_VALID_PACKED_MSB:BIAS_VALID_PACKED_LSB];
                    bus_rdata_w[NODE_CFG_INIT_SPIN_MSB:NODE_CFG_INIT_SPIN_LSB]=node_cfg_q[NODE_CFG_INIT_SPIN_PACKED_MSB:NODE_CFG_INIT_SPIN_PACKED_LSB];
                    bus_rdata_w[NODE_CFG_CLAMP_EN_MSB:NODE_CFG_CLAMP_EN_LSB]=node_cfg_q[NODE_CFG_CLAMP_EN_PACKED_MSB:NODE_CFG_CLAMP_EN_PACKED_LSB];
                    bus_rdata_w[NODE_CFG_CLAMP_SPIN_MSB:NODE_CFG_CLAMP_SPIN_LSB]=node_cfg_q[NODE_CFG_CLAMP_SPIN_PACKED_MSB:NODE_CFG_CLAMP_SPIN_PACKED_LSB];
                    bus_rdata_w[NODE_CFG_BIAS_SIGN_MSB:NODE_CFG_BIAS_SIGN_LSB]=node_cfg_q[NODE_CFG_BIAS_SIGN_PACKED_MSB:NODE_CFG_BIAS_SIGN_PACKED_LSB];
                    bus_rdata_w[NODE_CFG_BIAS_PROB_MSB:NODE_CFG_BIAS_PROB_LSB]=node_cfg_q[NODE_CFG_BIAS_PROB_PACKED_MSB:NODE_CFG_BIAS_PROB_PACKED_LSB];
                end
                A_SEED_TARGET: begin
                    bus_rdata_w[SEED_TARGET_NUMBER_MSB:SEED_TARGET_NUMBER_LSB]=seed_target_q[SEED_TARGET_NUMBER_PACKED_MSB:SEED_TARGET_NUMBER_PACKED_LSB];
                end
                A_SEED: begin
                    bus_rdata_w[SEED_MSB:SEED_LSB]=seed_q[SEED_PACKED_MSB:SEED_PACKED_LSB];
                end
                A_EDGE_TARGET: begin
                    bus_rdata_w[EDGE_TYPE_MSB:EDGE_TYPE_LSB]=edge_target_q[EDGE_TYPE_PACKED_MSB:EDGE_TYPE_PACKED_LSB];
                    bus_rdata_w[EDGE_TARGET_NUMBER_MSB:EDGE_TARGET_NUMBER_LSB]=edge_target_q[EDGE_TARGET_NUMBER_PACKED_MSB:EDGE_TARGET_NUMBER_PACKED_LSB];
                end
                A_EDGE_CFG: begin
                    bus_rdata_w[EDGE_CFG_EDGE_VALID_MSB:EDGE_CFG_EDGE_VALID_LSB]=edge_cfg_q[EDGE_CFG_EDGE_VALID_PACKED_MSB:EDGE_CFG_EDGE_VALID_PACKED_LSB];
                    bus_rdata_w[EDGE_CFG_EDGE_SIGN_MSB:EDGE_CFG_EDGE_SIGN_LSB]=edge_cfg_q[EDGE_CFG_EDGE_SIGN_PACKED_MSB:EDGE_CFG_EDGE_SIGN_PACKED_LSB];
                    bus_rdata_w[EDGE_CFG_EDGE_PROB_MSB:EDGE_CFG_EDGE_PROB_LSB]=edge_cfg_q[EDGE_CFG_EDGE_PROB_PACKED_MSB:EDGE_CFG_EDGE_PROB_PACKED_LSB];
                end
                A_GLOBAL_CFG: begin
                    bus_rdata_w[NUM_SWEEP_MSB:NUM_SWEEP_LSB]=global_cfg_q[NUM_SWEEP_PACKED_MSB:NUM_SWEEP_PACKED_LSB];
                    bus_rdata_w[NUM_MAJORITY_MSB:NUM_MAJORITY_LSB]=global_cfg_q[NUM_MAJORITY_PACKED_MSB:NUM_MAJORITY_PACKED_LSB];
                end
                A_SNAPSHOT_ADDR: begin
                    bus_rdata_w[SNAPSHOT_ADDR_MSB:SNAPSHOT_ADDR_LSB]=snapshot_addr_q[SNAPSHOT_ADDR_PACKED_MSB:SNAPSHOT_ADDR_PACKED_LSB];
                end
                default: begin
                    for(int i=0;i<I0_LEVEL_REG_NUM;i=i+1) if(i0_hit_w[i])
                        for(int j=0;j<4;j=j+1) bus_rdata_w[j*8 +: I0_LEVEL_WIDTH]=i0_level_o[i*4+j];
                    for(int i=0;i<SWEEP_INTERVAL_REG_NUM;i=i+1) if(interval_hit_w[i])
                        for(int j=0;j<2;j=j+1) bus_rdata_w[j*SWEEP_INTERVAL_WIDTH +: SWEEP_INTERVAL_WIDTH]=sweep_interval_o[i*2+j];
                    for(int i=0;i<SPIN_RDATA_REG_NUM;i=i+1) if(spin_hit_w[i])
                        bus_rdata_w=snapshot_flat_i[i*32 +: 32];
                end
            endcase
        end
    end
    // ------------------------------------------------------------
    // Register instances
    // ------------------------------------------------------------
    dffre #(.WIDTH(UNIT_TARGET_PACKED_WIDTH)) unit_target_ff (
        .clk(clk), .rst_n(rst_n), .en_i(write_w && reg_addr_i == A_UNIT_TARGET),
        .d_i(unit_target_d), .q_o(unit_target_q)
    );
    dffre #(.WIDTH(NODE_TARGET_PACKED_WIDTH)) node_target_ff (
        .clk(clk), .rst_n(rst_n), .en_i(write_w && reg_addr_i == A_NODE_TARGET),
        .d_i(node_target_d), .q_o(node_target_q)
    );
    dffre #(.WIDTH(NODE_CFG_PACKED_WIDTH)) node_cfg_ff (
        .clk(clk), .rst_n(rst_n), .en_i(write_w && reg_addr_i == A_NODE_CFG),
        .d_i(node_cfg_d), .q_o(node_cfg_q)
    );
    dffre #(.WIDTH(SEED_TARGET_PACKED_WIDTH)) seed_target_ff (
        .clk(clk), .rst_n(rst_n), .en_i(write_w && reg_addr_i == A_SEED_TARGET),
        .d_i(seed_target_d), .q_o(seed_target_q)
    );
    dffre #(.WIDTH(SEED_WIDTH)) seed_ff (
        .clk(clk), .rst_n(rst_n), .en_i(write_w && reg_addr_i == A_SEED),
        .d_i(seed_d), .q_o(seed_q)
    );
    dffre #(.WIDTH(EDGE_TARGET_PACKED_WIDTH)) edge_target_ff (
        .clk(clk), .rst_n(rst_n), .en_i(write_w && reg_addr_i == A_EDGE_TARGET),
        .d_i(edge_target_d), .q_o(edge_target_q)
    );
    dffre #(.WIDTH(EDGE_CFG_PACKED_WIDTH)) edge_cfg_ff (
        .clk(clk), .rst_n(rst_n), .en_i(write_w && reg_addr_i == A_EDGE_CFG),
        .d_i(edge_cfg_d), .q_o(edge_cfg_q)
    );
    dffre #(.WIDTH(GLOBAL_CFG_PACKED_WIDTH)) global_cfg_ff (
        .clk(clk), .rst_n(rst_n), .en_i(write_w && reg_addr_i == A_GLOBAL_CFG && !runtime_w),
        .d_i(global_cfg_d), .q_o(global_cfg_q)
    );
    dffre #(.WIDTH(SNAPSHOT_ADDR_WIDTH)) snapshot_addr_ff (
        .clk(clk), .rst_n(rst_n), .en_i(write_w && reg_addr_i == A_SNAPSHOT_ADDR),
        .d_i(snapshot_addr_d), .q_o(snapshot_addr_q)
    );
    dffr #(.WIDTH(1)) cfg_busy_ff (.clk(clk), .rst_n(rst_n), .d_i(cfg_busy_d), .q_o(cfg_busy_q));
    dffr #(.WIDTH(1)) req_valid_ff (.clk(clk), .rst_n(rst_n), .d_i(req_valid_d), .q_o(cfg_req_valid_o));
    dffe #(.WIDTH(CFG_ARRAY_REQ_WIDTH)) request_ff (
        .clk(clk), .en_i(issue_w), .d_i(req_d), .q_o(cfg_req_o)
    );
    dffr #(.WIDTH(1)) node_done_ff (.clk(clk), .rst_n(rst_n), .d_i(node_done_d), .q_o(node_done_q));
    dffre #(.WIDTH(NODE_CFG_W)) node_rdata_ff (
        .clk(clk), .rst_n(rst_n), .en_i(node_rdata_en), .d_i(node_rdata_d), .q_o(node_rdata_q)
    );
    dffr #(.WIDTH(1)) seed_done_ff (.clk(clk), .rst_n(rst_n), .d_i(seed_done_d), .q_o(seed_done_q));
    dffre #(.WIDTH(SEED_WIDTH)) seed_rdata_ff (
        .clk(clk), .rst_n(rst_n), .en_i(seed_rdata_en), .d_i(seed_rdata_d), .q_o(seed_rdata_q)
    );
    dffr #(.WIDTH(1)) edge_done_ff (.clk(clk), .rst_n(rst_n), .d_i(edge_done_d), .q_o(edge_done_q));
    dffre #(.WIDTH(EDGE_RDATA_PACKED_WIDTH)) edge_rdata_ff (
        .clk(clk), .rst_n(rst_n), .en_i(edge_rdata_en), .d_i(edge_rdata_d), .q_o(edge_rdata_q)
    );
    dffr #(.WIDTH(ERROR_STATUS_PACKED_WIDTH)) error_status_ff (
        .clk(clk), .rst_n(rst_n), .d_i(error_d), .q_o(error_q)
    );
    dffr #(.WIDTH(1)) cfg_done_ff (.clk(clk), .rst_n(rst_n), .d_i(cfg_done_d), .q_o(cfg_done_o));
    dffr #(.WIDTH(1)) run_start_ff (.clk(clk), .rst_n(rst_n), .d_i(run_start_d), .q_o(run_start_pulse_o));
    dffr #(.WIDTH(1)) run_done_clear_ff (.clk(clk), .rst_n(rst_n), .d_i(run_done_clear_d), .q_o(run_done_clr_pulse_o));
    dffr #(.WIDTH(1)) snapshot_latch_ff (.clk(clk), .rst_n(rst_n), .d_i(snapshot_latch_d), .q_o(snapshot_latch_pulse_o));
    dffre #(.WIDTH(32)) bus_rdata_ff (
        .clk(clk), .rst_n(rst_n), .en_i(access_w), .d_i(bus_rdata_w), .q_o(reg_rdata_o)
    );
    dffre #(.WIDTH(1)) bus_error_ff (
        .clk(clk), .rst_n(rst_n), .en_i(access_w), .d_i(access_error_w), .q_o(reg_access_error_o)
    );
    generate
        for (g=0; g<I0_LEVEL_REG_NUM; g=g+1) begin : GEN_I0
            for (f=0; f<4; f=f+1) begin : GEN_FIELD
                dffre #(.WIDTH(I0_LEVEL_WIDTH)) i0_ff (
                    .clk(clk), .rst_n(rst_n), .en_i(write_w && i0_hit_w[g] && !runtime_w),
                    .d_i(reg_wdata_i[f*8 +: I0_LEVEL_WIDTH]), .q_o(i0_level_o[g*4+f])
                );
            end
        end
        for (g=0; g<SWEEP_INTERVAL_REG_NUM; g=g+1) begin : GEN_INTERVAL
            for (f=0; f<2; f=f+1) begin : GEN_FIELD
                dffre #(.WIDTH(SWEEP_INTERVAL_WIDTH)) interval_ff (
                    .clk(clk), .rst_n(rst_n), .en_i(write_w && interval_hit_w[g] && !runtime_w),
                    .d_i(reg_wdata_i[f*SWEEP_INTERVAL_WIDTH +: SWEEP_INTERVAL_WIDTH]),
                    .q_o(sweep_interval_o[g*2+f])
                );
            end
        end
    endgenerate
endmodule
`endif
