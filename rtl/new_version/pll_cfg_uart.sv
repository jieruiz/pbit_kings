`ifndef PLL_CFG_UART_SV
`define PLL_CFG_UART_SV
// Four raw bytes: OP, byte address, DATA[15:8], DATA[7:0].
// Reply: STATUS, echoed address, DATA[15:8], DATA[7:0].
// Stop-and-wait protocol: host must receive a complete reply before next request.
import pbit_pkg::*;
module pll_cfg_uart #(
    parameter int REF_HZ = pbit_pkg::REF_CLK_FREQ_HZ,
    parameter int BAUD = pbit_pkg::BAUD_RATE,
    parameter int BYTE_TIMEOUT = REF_HZ / 50
) (
    input logic clk, rst_n, rx_i,
    output wire tx_o,
    output logic req_valid, req_write,
    output logic [7:0] req_addr,
    output logic [15:0] req_data,
    input logic resp_valid,
    input logic [7:0] resp_status,
    input logic [15:0] resp_data
);
    wire [7:0] rx_byte;
    wire rx_valid, tx_busy;
    localparam int TW = $clog2(BYTE_TIMEOUT+1);
    typedef enum logic [2:0] {RX, REG_WAIT, SEND, TX_HIGH, TX_LOW} state_t;
    logic [2:0] state_q;
    logic [2:0] state_d;
    logic [23:0] rx_shift_q;
    logic [23:0] rx_shift_d;
    logic [1:0] rx_count_q;
    logic [1:0] rx_count_d;
    logic [TW-1:0] timeout_count_q;
    logic [TW-1:0] timeout_count_d;
    logic [31:0] reply_q;
    logic [31:0] reply_d;
    logic [1:0] tx_index_q;
    logic [1:0] tx_index_d;
    logic [7:0] tx_byte_q;
    logic [7:0] tx_byte_d;
    logic tx_start_q;
    logic tx_start_d;
    logic req_valid_q;
    logic req_valid_d;
    logic req_write_q;
    logic req_write_d;
    logic [7:0] req_addr_q;
    logic [7:0] req_addr_d;
    logic [15:0] req_data_q;
    logic [15:0] req_data_d;

    uart_rx_8n1 #(.CLK_FREQ_HZ(REF_HZ), .BAUD_RATE(BAUD)) u_rx (
        .clk(clk), .rst_n(rst_n), .rx_i(rx_i),
        .rx_data_o(rx_byte), .rx_valid_o(rx_valid));
    uart_tx_8n1 #(.CLK_FREQ_HZ(REF_HZ), .BAUD_RATE(BAUD)) u_tx (
        .clk(clk), .rst_n(rst_n), .tx_data_i(tx_byte_q),
        .tx_valid_i(tx_start_q), .tx_o(tx_o), .tx_busy_o(tx_busy));


    logic rx_accept_w, frame_done_w, opcode_valid_w, byte_timeout_w;
    logic response_w, shift_reply_w;
    logic state_en, rx_shift_en, timeout_count_en, reply_en;
    logic tx_byte_en, req_addr_en, req_data_en;

    assign rx_accept_w = state_q == RX && rx_valid;
    assign frame_done_w = rx_accept_w && rx_count_q == 3;
    assign opcode_valid_w = rx_shift_q[23:16] == 1 || rx_shift_q[23:16] == 2;
    assign byte_timeout_w = state_q == RX && !rx_valid && rx_count_q != 0 &&
                            timeout_count_q == BYTE_TIMEOUT-1;
    assign response_w = state_q == REG_WAIT && resp_valid;
    assign shift_reply_w = state_q == TX_LOW && !tx_busy && tx_index_q != 3;

    // State transition logic only.
    always @(*) begin
        state_d = state_q;
        case (state_q)
            RX: if (frame_done_w) state_d = opcode_valid_w ? REG_WAIT : SEND;
            REG_WAIT: if (resp_valid) state_d = SEND;
            SEND: state_d = TX_HIGH;
            TX_HIGH: if (tx_busy) state_d = TX_LOW;
            TX_LOW: if (!tx_busy) state_d = tx_index_q == 3 ? RX : SEND;
            default: state_d = RX;
        endcase
    end
    assign state_en = state_d != state_q;

    // Receiver shift register and frame/timeout counters.
    assign rx_shift_en = rx_accept_w;
    assign rx_shift_d = {rx_shift_q[15:0], rx_byte};
    assign rx_count_d = (frame_done_w || byte_timeout_w) ? 2'd0 :
                        rx_accept_w ? rx_count_q + 1'b1 : rx_count_q;
    assign timeout_count_en = state_q == RX && (rx_valid || rx_count_q != 0);
    assign timeout_count_d = (rx_valid || byte_timeout_w) ?
                             '0 : timeout_count_q + 1'b1;

    // Register bus request fields; accepted once per complete frame.
    assign req_valid_d = frame_done_w && opcode_valid_w;
    assign req_write_d = (frame_done_w && opcode_valid_w) ?
                         (rx_shift_q[23:16] == 1) : req_write_q;
    assign req_addr_en = frame_done_w;
    assign req_addr_d = rx_shift_q[15:8];
    assign req_data_en = frame_done_w;
    assign req_data_d = {rx_shift_q[7:0], rx_byte};

    // Reply payload assembly/shift logic only.
    assign reply_en = (frame_done_w && !opcode_valid_w) || response_w || shift_reply_w;
    always @(*) begin
        case (state_q)
            RX: reply_d = {8'h01, rx_shift_q[15:8], 16'h0000};
            REG_WAIT: reply_d = {resp_status, req_addr_q, resp_data};
            default: reply_d = {reply_q[23:0], 8'h00};
        endcase
    end

    // Transmit byte control.
    assign tx_index_d = frame_done_w ? 2'd0 :
                        shift_reply_w ? tx_index_q + 1'b1 : tx_index_q;
    assign tx_byte_en = state_q == SEND;
    assign tx_byte_d = reply_q[31:24];
    assign tx_start_d = state_q == SEND;

    assign req_valid = req_valid_q;
    assign req_write = req_write_q;
    assign req_addr = req_addr_q;
    assign req_data = req_data_q;

    // Reset assertion/release is supplied by reset_sync_async_assert in wrapper.
    dffre #(.WIDTH(3), .RESET_VALUE(RX)) u_state_ff (
        .clk   (clk),
        .rst_n (rst_n),
        .en_i  (state_en),
        .d_i   (state_d),
        .q_o   (state_q)
    );

    dffre #(.WIDTH(24), .RESET_VALUE(24'd0)) u_rx_shift_ff (
        .clk   (clk),
        .rst_n (rst_n),
        .en_i  (rx_shift_en),
        .d_i   (rx_shift_d),
        .q_o   (rx_shift_q)
    );

    dffr #(.WIDTH(2), .RESET_VALUE(2'd0)) u_rx_count_ff (
        .clk   (clk),
        .rst_n (rst_n),
        .d_i   (rx_count_d),
        .q_o   (rx_count_q)
    );

    dffre #(.WIDTH(TW), .RESET_VALUE('0)) u_timeout_count_ff (
        .clk   (clk),
        .rst_n (rst_n),
        .en_i  (timeout_count_en),
        .d_i   (timeout_count_d),
        .q_o   (timeout_count_q)
    );

    dffre #(.WIDTH(32), .RESET_VALUE(32'd0)) u_reply_ff (
        .clk   (clk),
        .rst_n (rst_n),
        .en_i  (reply_en),
        .d_i   (reply_d),
        .q_o   (reply_q)
    );

    dffr #(.WIDTH(2), .RESET_VALUE(2'd0)) u_tx_index_ff (
        .clk   (clk),
        .rst_n (rst_n),
        .d_i   (tx_index_d),
        .q_o   (tx_index_q)
    );

    dffre #(.WIDTH(8), .RESET_VALUE(8'd0)) u_tx_byte_ff (
        .clk   (clk),
        .rst_n (rst_n),
        .en_i  (tx_byte_en),
        .d_i   (tx_byte_d),
        .q_o   (tx_byte_q)
    );

    dffr #(.WIDTH(1), .RESET_VALUE(1'b0)) u_tx_start_ff (
        .clk   (clk),
        .rst_n (rst_n),
        .d_i   (tx_start_d),
        .q_o   (tx_start_q)
    );

    dffr #(.WIDTH(1), .RESET_VALUE(1'b0)) u_req_valid_ff (
        .clk   (clk),
        .rst_n (rst_n),
        .d_i   (req_valid_d),
        .q_o   (req_valid_q)
    );

    dffr #(.WIDTH(1), .RESET_VALUE(1'b0)) u_req_write_ff (
        .clk   (clk),
        .rst_n (rst_n),
        .d_i   (req_write_d),
        .q_o   (req_write_q)
    );

    dffre #(.WIDTH(8), .RESET_VALUE(8'd0)) u_req_addr_ff (
        .clk   (clk),
        .rst_n (rst_n),
        .en_i  (req_addr_en),
        .d_i   (req_addr_d),
        .q_o   (req_addr_q)
    );

    dffre #(.WIDTH(16), .RESET_VALUE(16'd0)) u_req_data_ff (
        .clk   (clk),
        .rst_n (rst_n),
        .en_i  (req_data_en),
        .d_i   (req_data_d),
        .q_o   (req_data_q)
    );
endmodule
`endif
