`ifndef PLL_CFG_REGS_SV
`define PLL_CFG_REGS_SV
// 25 MHz reference-domain register bank and PLL startup controller.
// No clock mux, no automatic failover and no inferred LOCK indication.
module pll_cfg_regs #(
    parameter int REF_HZ = 25_000_000,
    parameter int MAX_CORE_HZ = 400_000_000,
    parameter int WAIT_CYCLES = (REF_HZ / 1_000_000) * 15,
    // Reference cycles allowed for actual core reset-release acknowledgment,
    // counted AFTER the 15 us startup wait. Not a PLL lock timeout.
    parameter int RELEASE_TIMEOUT = 1024
) (
    input logic clk, rst_n,
    input logic req_valid, req_write,
    input logic [7:0] req_addr,
    input logic [15:0] req_data,
    output logic resp_valid,
    output logic [7:0] resp_status,
    output logic [15:0] resp_data,
    input logic core_rst_n,
    output logic pll_en, core_release,
    output logic [7:0] pll_n,
    output logic pll_select, pll_bp,
    output logic [1:0] pll_od
);
    localparam int CW = $clog2(WAIT_CYCLES + RELEASE_TIMEOUT + 8);
    typedef enum logic [2:0] {IDLE, HOLD_RESET, DISABLE_PLL,
        SET_CONFIG, ENABLE_PLL, WAIT_START, WAIT_RELEASE} state_t;
    logic [2:0] state_q;
    logic [2:0] state_d;
    logic [15:0] shadow_cfg_q;
    logic [15:0] shadow_cfg_d;
    logic [15:0] active_cfg_q;
    logic [15:0] active_cfg_d;
    logic [15:0] pending_cfg_q;
    logic [15:0] pending_cfg_d;
    logic done_q;
    logic done_d;
    logic startup_done_q;
    logic startup_done_d;
    logic [3:0] error_code_q;
    logic [3:0] error_code_d;
    logic [CW-1:0] count_q;
    logic [CW-1:0] count_d;
    (* ASYNC_REG = "TRUE" *) logic [1:0] release_sync_q;
    logic [1:0] release_sync_d;
    logic pll_en_q;
    logic pll_en_d;
    logic core_release_q;
    logic core_release_d;
    logic resp_valid_q;
    logic resp_valid_d;
    logic [7:0] resp_status_q;
    logic [7:0] resp_status_d;
    logic [15:0] resp_data_q;
    logic [15:0] resp_data_d;

    wire busy = state_q != IDLE;
    wire [15:0] status_word = {4'b0, error_code_q, 1'b0,
        release_sync_q[1], startup_done_q, pll_en_q, active_cfg_q[11],
        (error_code_q != 0), done_q, busy};
    assign pll_n = active_cfg_q[7:0];
    assign pll_select = active_cfg_q[8];
    assign pll_od = active_cfg_q[10:9];
    assign pll_bp = active_cfg_q[11];

    function automatic logic [3:0] config_error(input logic [15:0] cfg);
        longint unsigned vco_hz;
        longint unsigned out_hz;
        begin
            vco_hz = 64'(REF_HZ) * cfg[7:0] * (cfg[8] ? 2 : 1);
            out_hz = vco_hz >> cfg[10:9];
            if (cfg[15:12] != 0) config_error = 2;
            else if (cfg[7:0] < 17 || vco_hz < 500_000_000 ||
                     vco_hz > 1_200_000_000) config_error = 3;
            else if (!cfg[11] && out_hz > MAX_CORE_HZ) config_error = 4;
            else config_error = 0;
        end
    endfunction



    // Decode access errors once; accepted APPLY is an atomic snapshot event.
    logic addr_valid_w, apply_w, clear_error_w, hold_done_w;
    logic wait_done_w, release_done_w, release_timeout_w, illegal_state_w;
    logic [3:0] cfg_error_w, access_error_w;
    logic state_en, shadow_cfg_en, active_cfg_en, pending_cfg_en;
    logic error_code_en, count_en, resp_status_en, resp_data_en;

    assign addr_valid_w = req_addr == 0 || req_addr == 2 ||
                          req_addr == 4 || req_addr == 6;
    assign cfg_error_w = config_error(shadow_cfg_q);
    always @(*) begin
        access_error_w = 4'd0;
        if (req_valid) begin
            if (!addr_valid_w) access_error_w = 4'd1;
            else if (req_write) begin
                case (req_addr)
                    0: if (busy) access_error_w = 4'd6;
                    2: begin
                        if (req_data == 2) access_error_w = 4'd0;
                        else if (req_data != 1) access_error_w = 4'd5;
                        else if (busy) access_error_w = 4'd6;
                        else access_error_w = cfg_error_w;
                    end
                    default: access_error_w = 4'd1;
                endcase
            end
        end
    end

    assign apply_w = req_valid && req_write && req_addr == 2 &&
                     req_data == 1 && access_error_w == 0;
    assign clear_error_w = req_valid && req_write && req_addr == 2 && req_data == 2;
    assign hold_done_w = state_q == HOLD_RESET && count_q == 3;
    assign wait_done_w = state_q == WAIT_START && count_q == CW'(WAIT_CYCLES-1);
    assign release_done_w = state_q == WAIT_RELEASE && release_sync_q[1];
    // A release acknowledgment on the last allowed edge wins over timeout.
    assign release_timeout_w = state_q == WAIT_RELEASE && !release_sync_q[1] &&
                               count_q == CW'(RELEASE_TIMEOUT-1);
    assign illegal_state_w = state_q > WAIT_RELEASE;

    // State transition logic only.
    always @(*) begin
        state_d = state_q;
        case (state_q)
            IDLE: if (apply_w) state_d = HOLD_RESET;
            HOLD_RESET: if (hold_done_w) state_d = DISABLE_PLL;
            DISABLE_PLL: state_d = SET_CONFIG;
            SET_CONFIG: state_d = ENABLE_PLL;
            ENABLE_PLL: state_d = WAIT_START;
            WAIT_START: if (wait_done_w) state_d = WAIT_RELEASE;
            WAIT_RELEASE: if (release_done_w || release_timeout_w) state_d = IDLE;
            default: state_d = IDLE;
        endcase
    end
    assign state_en = state_d != state_q;

    // Configuration registers have explicit write/capture enables.
    assign shadow_cfg_en = req_valid && req_write && req_addr == 0 && !busy;
    assign shadow_cfg_d = req_data;
    assign pending_cfg_en = apply_w;
    assign pending_cfg_d = shadow_cfg_q;
    assign active_cfg_en = state_q == SET_CONFIG;
    assign active_cfg_d = pending_cfg_q;

    // Shared phase counter; no updates while idle or after release acknowledgment.
    assign count_en = apply_w || state_q == HOLD_RESET || state_q == ENABLE_PLL ||
                      state_q == WAIT_START ||
                      (state_q == WAIT_RELEASE && !release_done_w && !release_timeout_w);
    assign count_d = (apply_w || hold_done_w || state_q == ENABLE_PLL || wait_done_w) ?
                     '0 : count_q + 1'b1;

    assign pll_en_d = (hold_done_w || illegal_state_w) ? 1'b0 :
                     (state_q == ENABLE_PLL) ? 1'b1 : pll_en_q;
    assign core_release_d = (apply_w || release_timeout_w || illegal_state_w) ? 1'b0 :
                           wait_done_w ? 1'b1 : core_release_q;
    assign startup_done_d = hold_done_w ? 1'b0 :
                           wait_done_w ? 1'b1 : startup_done_q;
    assign done_d = apply_w ? 1'b0 : release_done_w ? 1'b1 : done_q;

    // Sticky latest error. New timeout has priority over a simultaneous clear.
    assign error_code_en = release_timeout_w || access_error_w != 0 || clear_error_w;
    assign error_code_d = release_timeout_w ? 4'd7 :
                          access_error_w != 0 ? access_error_w : 4'd0;

    // Protocol response registers.
    assign resp_valid_d = req_valid;
    assign resp_status_en = req_valid;
    assign resp_status_d = access_error_w == 0 ? 8'd0 :
                           access_error_w == 6 ? 8'd3 : 8'd2;
    assign resp_data_en = req_valid;
    always @(*) begin
        resp_data_d = 16'd0;
        if (!req_write && addr_valid_w) begin
            case (req_addr)
                0: resp_data_d = shadow_cfg_q;
                4: resp_data_d = status_word;
                6: resp_data_d = active_cfg_q;
                default: resp_data_d = 16'd0;
            endcase
        end
    end

    assign pll_en = pll_en_q;
    assign core_release = core_release_q;
    assign resp_valid = resp_valid_q;
    assign resp_status = resp_status_q;
    assign resp_data = resp_data_q;
    // Status feedback is a data CDC synchronizer, not a reset generator.
    assign release_sync_d = {release_sync_q[0], core_rst_n};

    // Reset assertion/release is supplied by reset_sync_async_assert in wrapper.
    dffre #(.WIDTH(3), .RESET_VALUE(IDLE)) u_state_ff (
        .clk   (clk),
        .rst_n (rst_n),
        .en_i  (state_en),
        .d_i   (state_d),
        .q_o   (state_q)
    );

    dffre #(.WIDTH(16), .RESET_VALUE(16'h0220)) u_shadow_cfg_ff (
        .clk   (clk),
        .rst_n (rst_n),
        .en_i  (shadow_cfg_en),
        .d_i   (shadow_cfg_d),
        .q_o   (shadow_cfg_q)
    );

    dffre #(.WIDTH(16), .RESET_VALUE(16'h0220)) u_active_cfg_ff (
        .clk   (clk),
        .rst_n (rst_n),
        .en_i  (active_cfg_en),
        .d_i   (active_cfg_d),
        .q_o   (active_cfg_q)
    );

    dffre #(.WIDTH(16), .RESET_VALUE(16'h0220)) u_pending_cfg_ff (
        .clk   (clk),
        .rst_n (rst_n),
        .en_i  (pending_cfg_en),
        .d_i   (pending_cfg_d),
        .q_o   (pending_cfg_q)
    );

    dffr #(.WIDTH(1), .RESET_VALUE(1'b0)) u_done_ff (
        .clk   (clk),
        .rst_n (rst_n),
        .d_i   (done_d),
        .q_o   (done_q)
    );

    dffr #(.WIDTH(1), .RESET_VALUE(1'b0)) u_startup_done_ff (
        .clk   (clk),
        .rst_n (rst_n),
        .d_i   (startup_done_d),
        .q_o   (startup_done_q)
    );

    dffre #(.WIDTH(4), .RESET_VALUE(4'd0)) u_error_code_ff (
        .clk   (clk),
        .rst_n (rst_n),
        .en_i  (error_code_en),
        .d_i   (error_code_d),
        .q_o   (error_code_q)
    );

    dffre #(.WIDTH(CW), .RESET_VALUE('0)) u_count_ff (
        .clk   (clk),
        .rst_n (rst_n),
        .en_i  (count_en),
        .d_i   (count_d),
        .q_o   (count_q)
    );

    dffr #(.WIDTH(2), .RESET_VALUE(2'b00)) u_release_sync_ff (
        .clk   (clk),
        .rst_n (rst_n),
        .d_i   (release_sync_d),
        .q_o   (release_sync_q)
    );

    dffr #(.WIDTH(1), .RESET_VALUE(1'b0)) u_pll_en_ff (
        .clk   (clk),
        .rst_n (rst_n),
        .d_i   (pll_en_d),
        .q_o   (pll_en_q)
    );

    dffr #(.WIDTH(1), .RESET_VALUE(1'b0)) u_core_release_ff (
        .clk   (clk),
        .rst_n (rst_n),
        .d_i   (core_release_d),
        .q_o   (core_release_q)
    );

    dffr #(.WIDTH(1), .RESET_VALUE(1'b0)) u_resp_valid_ff (
        .clk   (clk),
        .rst_n (rst_n),
        .d_i   (resp_valid_d),
        .q_o   (resp_valid_q)
    );

    dffre #(.WIDTH(8), .RESET_VALUE(8'd0)) u_resp_status_ff (
        .clk   (clk),
        .rst_n (rst_n),
        .en_i  (resp_status_en),
        .d_i   (resp_status_d),
        .q_o   (resp_status_q)
    );

    dffre #(.WIDTH(16), .RESET_VALUE(16'd0)) u_resp_data_ff (
        .clk   (clk),
        .rst_n (rst_n),
        .en_i  (resp_data_en),
        .d_i   (resp_data_d),
        .q_o   (resp_data_q)
    );
endmodule
`endif
