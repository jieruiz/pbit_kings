`timescale 1ns / 1ps

module pbit_uart_host_if #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer BAUD_RATE   = 115200,
    parameter integer N_SPIN      = 361
)(
    input  wire clk,
    input  wire rst_n,

    input  wire uart_rx_i,
    output wire uart_tx_o,

    input  wire [N_SPIN-1:0] spin_flat_i,

    output reg        cfg_node_we_o,
    output reg [4:0]  cfg_node_row_o,
    output reg [4:0]  cfg_node_col_o,
    output reg [31:0] cfg_node_seed_o,
    output reg        cfg_node_init_spin_o,
    output reg        cfg_node_clamp_en_o,
    output reg        cfg_node_clamp_spin_o,
    output reg        cfg_node_bias_sign_o,
    output reg [3:0]  cfg_node_bias_prob4_o,

    output reg        cfg_edge_we_o,
    output reg [1:0]  cfg_edge_type_o,
    output reg [4:0]  cfg_edge_row_o,
    output reg [4:0]  cfg_edge_col_o,
    output reg [3:0]  cfg_edge_prob4_o,
    output reg        cfg_edge_sign_o,
    output reg        cfg_edge_valid_o,

    // sticky: set by CONFIG_DONE / END, cleared only by reset
    output reg        cfg_done_o,

    // 1-cycle pulse
    output reg        run_start_pulse_o,

    output reg [31:0] cmd_count_o
);

    localparam [1:0] CMD_NODE = 2'b00;
    localparam [1:0] CMD_EDGE = 2'b01;
    localparam [1:0] CMD_CTRL = 2'b10;
    localparam [1:0] CMD_END  = 2'b11;

    localparam [5:0] OP_CONFIG_DONE   = 6'd0;
    localparam [5:0] OP_RUN_START     = 6'd1;
    localparam [5:0] OP_SNAPSHOT_READ = 6'd2;

    localparam [7:0] ACK_OK   = 8'hA5;
    localparam [7:0] ACK_BAD  = 8'h5A;
    localparam [7:0] SNAP_HDR = 8'h53; // ASCII 'S'

    // NODE command low fields:
    //   [19] init_spin, [18] clamp_en, [17] clamp_spin,
    //   [16] bias_sign, [15:12] bias_prob4.

    localparam integer N_BYTES   = (N_SPIN + 7) / 8;
    localparam integer SNAP_BITS = N_BYTES * 8;
    localparam integer SNAP_PAD  = SNAP_BITS - N_SPIN;

    localparam [7:0] N_BYTES_U8 = N_BYTES[7:0];

    localparam [2:0] TX_IDLE      = 3'd0;
    localparam [2:0] TX_SEND      = 3'd1;
    localparam [2:0] TX_WAIT_BUSY = 3'd2;
    localparam [2:0] TX_WAIT_DONE = 3'd3;

    localparam [1:0] PH_ACK  = 2'd0;
    localparam [1:0] PH_HDR  = 2'd1;
    localparam [1:0] PH_LEN  = 2'd2;
    localparam [1:0] PH_DATA = 2'd3;

    wire [7:0] rx_data_w;
    wire       rx_valid_w;

    reg  [7:0] tx_data_q;
    reg        tx_valid_q;
    wire       tx_busy_w;

    reg [63:0] cmd_shift_q;
    reg [2:0]  byte_cnt_q;

    wire [63:0] cmd_word_w;
    assign cmd_word_w = {cmd_shift_q[55:0], rx_data_w};

    reg [2:0] tx_state_q;
    reg [1:0] tx_phase_q;
    reg [7:0] tx_byte_idx_q;

    reg        resp_pending_q;
    reg        resp_snapshot_q;
    reg [7:0]  ack_byte_q;
    reg [SNAP_BITS-1:0] snapshot_q;

    wire host_busy_w;
    assign host_busy_w = resp_pending_q || (tx_state_q != TX_IDLE) || tx_busy_w;

    uart_rx_8n1 #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE  (BAUD_RATE)
    ) u_uart_rx_8n1 (
        .clk        (clk),
        .rst_n      (rst_n),
        .rx_i       (uart_rx_i),
        .rx_data_o  (rx_data_w),
        .rx_valid_o (rx_valid_w)
    );

    uart_tx_8n1 #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE  (BAUD_RATE)
    ) u_uart_tx_8n1 (
        .clk        (clk),
        .rst_n      (rst_n),
        .tx_data_i  (tx_data_q),
        .tx_valid_i (tx_valid_q),
        .tx_o       (uart_tx_o),
        .tx_busy_o  (tx_busy_w)
    );

    // ------------------------------------------------------------
    // Single sequential block:
    // All registers in this module are assigned here.
    // This avoids MDRV multiple-driver errors.
    // ------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cmd_shift_q <= 64'd0;
            byte_cnt_q  <= 3'd0;

            cfg_node_we_o         <= 1'b0;
            cfg_node_row_o        <= 5'd0;
            cfg_node_col_o        <= 5'd0;
            cfg_node_seed_o       <= 32'd0;
            cfg_node_init_spin_o  <= 1'b0;
            cfg_node_clamp_en_o   <= 1'b0;
            cfg_node_clamp_spin_o <= 1'b0;
            cfg_node_bias_sign_o  <= 1'b1;
            cfg_node_bias_prob4_o <= 4'd0;

            cfg_edge_we_o     <= 1'b0;
            cfg_edge_type_o   <= 2'd0;
            cfg_edge_row_o    <= 5'd0;
            cfg_edge_col_o    <= 5'd0;
            cfg_edge_prob4_o  <= 4'd0;
            cfg_edge_sign_o   <= 1'b1;
            cfg_edge_valid_o  <= 1'b0;

            cfg_done_o        <= 1'b0;
            run_start_pulse_o <= 1'b0;
            cmd_count_o       <= 32'd0;

            tx_state_q        <= TX_IDLE;
            tx_phase_q        <= PH_ACK;
            tx_byte_idx_q     <= 8'd0;
            tx_data_q         <= 8'd0;
            tx_valid_q        <= 1'b0;

            resp_pending_q    <= 1'b0;
            resp_snapshot_q   <= 1'b0;
            ack_byte_q        <= ACK_OK;
            snapshot_q        <= {SNAP_BITS{1'b0}};
        end else begin
            // default one-cycle pulses
            cfg_node_we_o      <= 1'b0;
            cfg_edge_we_o      <= 1'b0;
            run_start_pulse_o  <= 1'b0;
            tx_valid_q         <= 1'b0;

            // cfg_done_o is sticky; do not clear it here.

            // ====================================================
            // TX response state machine
            // ====================================================
            case (tx_state_q)

                TX_IDLE: begin
                    if (resp_pending_q && !tx_busy_w) begin
                        case (tx_phase_q)
                            PH_ACK:  tx_data_q <= ack_byte_q;
                            PH_HDR:  tx_data_q <= SNAP_HDR;
                            PH_LEN:  tx_data_q <= N_BYTES_U8;
                            PH_DATA: tx_data_q <= snapshot_q[tx_byte_idx_q * 8 +: 8];
                            default: tx_data_q <= ACK_BAD;
                        endcase

                        tx_valid_q <= 1'b1;
                        tx_state_q <= TX_WAIT_BUSY;
                    end
                end

                // Wait until uart_tx accepts tx_valid and becomes busy.
                TX_WAIT_BUSY: begin
                    if (tx_busy_w) begin
                        tx_state_q <= TX_WAIT_DONE;
                    end
                end

                // Wait until current byte has fully transmitted.
                TX_WAIT_DONE: begin
                    if (!tx_busy_w) begin
                        case (tx_phase_q)

                            PH_ACK: begin
                                if (resp_snapshot_q && (ack_byte_q == ACK_OK)) begin
                                    tx_phase_q <= PH_HDR;
                                end else begin
                                    resp_pending_q  <= 1'b0;
                                    resp_snapshot_q <= 1'b0;
                                    tx_phase_q      <= PH_ACK;
                                end

                                tx_state_q <= TX_IDLE;
                            end

                            PH_HDR: begin
                                tx_phase_q <= PH_LEN;
                                tx_state_q <= TX_IDLE;
                            end

                            PH_LEN: begin
                                tx_byte_idx_q <= 8'd0;
                                tx_phase_q    <= PH_DATA;
                                tx_state_q    <= TX_IDLE;
                            end

                            PH_DATA: begin
                                if (tx_byte_idx_q == N_BYTES_U8 - 1) begin
                                    resp_pending_q  <= 1'b0;
                                    resp_snapshot_q <= 1'b0;
                                    tx_byte_idx_q   <= 8'd0;
                                    tx_phase_q      <= PH_ACK;
                                end else begin
                                    tx_byte_idx_q <= tx_byte_idx_q + 8'd1;
                                end

                                tx_state_q <= TX_IDLE;
                            end

                            default: begin
                                resp_pending_q  <= 1'b0;
                                resp_snapshot_q <= 1'b0;
                                tx_byte_idx_q   <= 8'd0;
                                tx_phase_q      <= PH_ACK;
                                tx_state_q      <= TX_IDLE;
                            end

                        endcase
                    end
                end

                default: begin
                    tx_state_q <= TX_IDLE;
                end

            endcase

            // ====================================================
            // RX command assembly and decode
            // One 64-bit command = 8 bytes, MSB first.
            // PC should wait for ACK or full snapshot before sending next cmd.
            // ====================================================
            if (rx_valid_w) begin
                cmd_shift_q <= {cmd_shift_q[55:0], rx_data_w};

                if (byte_cnt_q == 3'd7) begin
                    byte_cnt_q  <= 3'd0;
                    cmd_count_o <= cmd_count_o + 32'd1;

                    if (host_busy_w) begin
                        // PC protocol violation.
                        // Drop this command. PC should timeout or avoid this.
                        // Do not queue ACK_BAD here, because TX is already busy.
                    end else begin
                        case (cmd_word_w[63:62])

                            CMD_NODE: begin
                                cfg_node_we_o         <= 1'b1;
                                cfg_node_row_o        <= cmd_word_w[61:57];
                                cfg_node_col_o        <= cmd_word_w[56:52];
                                cfg_node_seed_o       <= cmd_word_w[51:20];
                                cfg_node_init_spin_o  <= cmd_word_w[19];
                                cfg_node_clamp_en_o   <= cmd_word_w[18];
                                cfg_node_clamp_spin_o <= cmd_word_w[17];
                                cfg_node_bias_sign_o  <= cmd_word_w[16];
                                cfg_node_bias_prob4_o <= cmd_word_w[15:12];

                                ack_byte_q      <= ACK_OK;
                                resp_snapshot_q <= 1'b0;
                                resp_pending_q  <= 1'b1;
                                tx_phase_q      <= PH_ACK;
                            end

                            CMD_EDGE: begin
                                cfg_edge_we_o     <= 1'b1;
                                cfg_edge_type_o   <= cmd_word_w[61:60];
                                cfg_edge_row_o    <= cmd_word_w[59:55];
                                cfg_edge_col_o    <= cmd_word_w[54:50];
                                cfg_edge_prob4_o  <= cmd_word_w[49:46];
                                cfg_edge_sign_o   <= cmd_word_w[45];
                                cfg_edge_valid_o  <= cmd_word_w[44];

                                ack_byte_q      <= ACK_OK;
                                resp_snapshot_q <= 1'b0;
                                resp_pending_q  <= 1'b1;
                                tx_phase_q      <= PH_ACK;
                            end

                            CMD_CTRL: begin
                                case (cmd_word_w[61:56])

                                    OP_CONFIG_DONE: begin
                                        cfg_done_o <= 1'b1;

                                        ack_byte_q      <= ACK_OK;
                                        resp_snapshot_q <= 1'b0;
                                        resp_pending_q  <= 1'b1;
                                        tx_phase_q      <= PH_ACK;
                                    end

                                    OP_RUN_START: begin
                                        run_start_pulse_o <= 1'b1;

                                        ack_byte_q      <= ACK_OK;
                                        resp_snapshot_q <= 1'b0;
                                        resp_pending_q  <= 1'b1;
                                        tx_phase_q      <= PH_ACK;
                                    end

                                    OP_SNAPSHOT_READ: begin
                                        snapshot_q <= {{SNAP_PAD{1'b0}}, spin_flat_i};

                                        ack_byte_q      <= ACK_OK;
                                        resp_snapshot_q <= 1'b1;
                                        resp_pending_q  <= 1'b1;
                                        tx_phase_q      <= PH_ACK;
                                    end

                                    default: begin
                                        ack_byte_q      <= ACK_BAD;
                                        resp_snapshot_q <= 1'b0;
                                        resp_pending_q  <= 1'b1;
                                        tx_phase_q      <= PH_ACK;
                                    end

                                endcase
                            end

                            CMD_END: begin
                                cfg_done_o <= 1'b1;

                                ack_byte_q      <= ACK_OK;
                                resp_snapshot_q <= 1'b0;
                                resp_pending_q  <= 1'b1;
                                tx_phase_q      <= PH_ACK;
                            end

                            default: begin
                                ack_byte_q      <= ACK_BAD;
                                resp_snapshot_q <= 1'b0;
                                resp_pending_q  <= 1'b1;
                                tx_phase_q      <= PH_ACK;
                            end

                        endcase
                    end
                end else begin
                    byte_cnt_q <= byte_cnt_q + 3'd1;
                end
            end
        end
    end

endmodule
