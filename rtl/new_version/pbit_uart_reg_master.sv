`ifndef PBIT_UART_REG_MASTER
`define PBIT_UART_REG_MASTER
import pbit_pkg::*;
// -----------------------------------------------------------------------------
// UART to simple 46-bit register bus master.
//
// Request frame, 7 bytes, MSB first:
//   byte6 : opcode, 8'h01 = WRITE, 8'h02 = READ
//   byte5 : addr[15:8]
//   byte4 : addr[7:0]
//   byte3 : wdata[31:24]
//   byte2 : wdata[23:16]
//   byte1 : wdata[15:8]
//   byte0 : wdata[7:0]
//
// Response frame, 7 bytes, MSB first:
//   byte6 : status, 8'h00 OK, 8'h01 bad frame/opcode, 8'h02 register error,
//           8'h03 host busy/overflow
//   byte5 : addr[15:8]
//   byte4 : addr[7:0]
//   byte3 : rdata[31:24]
//   byte2 : rdata[23:16]
//   byte1 : rdata[15:8]
//   byte0 : rdata[7:0]
//
// The UART layer does not know p-bit semantics. It only issues register reads
// and writes. pbit_reg_block owns the register map and all control semantics.
// -----------------------------------------------------------------------------
module pbit_uart_reg_master #(
    // Match the configuration UART timeout cycle count, not its elapsed time.
    parameter int BYTE_TIMEOUT = int'((64'(pbit_pkg::REF_CLK_FREQ_HZ) * pbit_pkg::PLL_CFG_BYTE_TIMEOUT_MS) / 1000)
) (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        uart_rx_i,
    output logic        uart_tx_o,

    output logic        reg_wr_en_o,
    output logic        reg_rd_en_o,
    output logic [15:0] reg_addr_o,
    output logic [31:0] reg_wdata_o,
    input  logic [31:0] reg_rdata_i,
    input  logic        reg_access_error_i,

    output logic        uart_frame_err_pulse_o,
    output logic        uart_overflow_pulse_o,

    output logic        uart_rx_busy_o,
    output logic        uart_tx_busy_o
);

    localparam int BYTE_TIMEOUT_WIDTH = (BYTE_TIMEOUT > 1)? $clog2(BYTE_TIMEOUT + 1): 1;

    localparam [7:0] OP_WRITE  = 8'h01;
    localparam [7:0] OP_READ   = 8'h02;

    typedef enum logic [7:0] {
        ST_OK       = 8'h00,
        ST_BAD      = 8'h01,
        ST_REG_ERR  = 8'h02,
        ST_BUSY     = 8'h03
    } ST_e;

    typedef enum logic[1:0] {
        BUS_IDLE    = 2'd0,
        BUS_ISSUE   = 2'd1,
        BUS_CAPTURE = 2'd2
    } BUS_e;

    typedef enum logic[1:0] {
        TX_IDLE     = 2'd0,
        TX_WAIT_HI  = 2'd1,
        TX_WAIT_LO  = 2'd2
    } TX_e;

    logic        uart_busy_w;
    logic        uart_overflow_pulse_q, uart_overflow_pulse_d;
    logic        uart_frame_err_pulse_q, uart_frame_err_pulse_d;

    logic [7:0]  rx_data_w;
    logic        rx_valid_w;
    logic [55:0] rx_shift_q, rx_shift_d;
    logic        rx_shift_en;
    logic [2:0]  rx_byte_cnt_q, rx_byte_cnt_d;
    logic        rx_cmd_valid_w;
    logic        rx_cmd_illegal_w;
    logic        rx_byte_timeout_w;
    logic [BYTE_TIMEOUT_WIDTH-1:0] rx_timeout_cnt_q, rx_timeout_cnt_d;
    logic        rx_timeout_cnt_en;

    logic        req_valid_q, req_valid_d;
    logic        req_wr_en_q, req_wr_en_d;
    logic        req_rd_en_q, req_rd_en_d;
    logic [7:0]  req_op_q, req_op_d;
    logic        req_op_en;
    logic [15:0] req_addr_q, req_addr_d;
    logic        req_addr_en;
    logic [31:0] req_wdata_q, req_wdata_d;
    logic        req_wdata_en;

    BUS_e        bus_state_q, bus_state_d;

    logic        resp_valid_q, resp_valid_d;
    ST_e         resp_status_q, resp_status_d;
    logic [15:0] resp_addr_q, resp_addr_d;
    logic        resp_addr_en;
    logic [31:0] resp_rdata_q, resp_rdata_d;
    logic        resp_rdata_en;
    logic        resp_no_pend_w;

    TX_e         tx_state_q, tx_state_d;
    logic [7:0]  tx_data_q, tx_data_d;
    logic        tx_data_en;
    logic        tx_valid_pulse_q, tx_valid_pulse_d;
    logic        tx_busy_w;
    logic [2:0]  tx_idx_q, tx_idx_d;

    function automatic logic [7:0] resp_byte(
        input logic [2:0] idx, 
        input ST_e status, 
        input logic [15:0] addr, 
        input logic [31:0] rdata
    );
        case (idx)
            3'd0: resp_byte = status;
            3'd1: resp_byte = addr[15:8];
            3'd2: resp_byte = addr[7:0];
            3'd3: resp_byte = rdata[31:24];
            3'd4: resp_byte = rdata[23:16];
            3'd5: resp_byte = rdata[15:8];
            3'd6: resp_byte = rdata[7:0];
            default: resp_byte = 8'h00;
        endcase
    endfunction

    assign uart_rx_busy_o = (rx_byte_cnt_q != 3'd0);
    assign uart_tx_busy_o = tx_busy_w;
    assign uart_busy_w    = req_valid_q || (bus_state_q != BUS_IDLE) || resp_valid_q ||
                         (tx_state_q != TX_IDLE) || tx_busy_w;
    assign uart_overflow_pulse_d = (rx_cmd_valid_w && uart_busy_w)? 1'b1: 1'b0;
    assign uart_overflow_pulse_o = uart_overflow_pulse_q;
    assign uart_frame_err_pulse_d = (rx_byte_timeout_w || (rx_cmd_valid_w && !uart_busy_w && rx_cmd_illegal_w))? 1'b1 : 1'b0;
    assign uart_frame_err_pulse_o = uart_frame_err_pulse_q;

    assign rx_shift_d = rx_byte_timeout_w? 56'd0: {rx_shift_q[47:0], rx_data_w};
    assign rx_shift_en = rx_valid_w || rx_byte_timeout_w;
    assign rx_cmd_valid_w = rx_valid_w && (rx_byte_cnt_q == 3'd6);
    assign rx_byte_cnt_d = rx_byte_timeout_w? 3'd0:
                           rx_valid_w? (rx_byte_cnt_q == 3'd6)? 3'd0: rx_byte_cnt_q + 1:
                           rx_byte_cnt_q;
    assign rx_cmd_illegal_w = !((rx_shift_d[55:48] == OP_WRITE) || (rx_shift_d[55:48] == OP_READ));

    // A valid byte on the last allowed cycle takes priority over timeout.
    assign rx_byte_timeout_w = !rx_valid_w && (rx_byte_cnt_q != 3'd0) &&
                               (rx_timeout_cnt_q == BYTE_TIMEOUT - 1);
    assign rx_timeout_cnt_d = (rx_valid_w || rx_byte_timeout_w)? '0: rx_timeout_cnt_q + 1'b1;
    assign rx_timeout_cnt_en = rx_valid_w || (rx_byte_cnt_q != 3'd0);

    assign resp_no_pend_w = !resp_valid_q && (tx_state_q == TX_IDLE) && !tx_busy_w;
    assign resp_valid_d = (rx_cmd_valid_w && uart_busy_w && resp_no_pend_w)? 1'b1:
                          (rx_cmd_valid_w && !uart_busy_w && rx_cmd_illegal_w)? 1'b1:
                          (bus_state_q == BUS_CAPTURE)? 1'b1:
                          ((tx_state_q == TX_WAIT_LO) && (tx_state_d == TX_IDLE))? 1'b0:
                          resp_valid_q;
    assign resp_status_d = (rx_cmd_valid_w && uart_busy_w && resp_no_pend_w)? ST_BUSY:
                           (rx_cmd_valid_w && !uart_busy_w && rx_cmd_illegal_w)? ST_BAD:
                           (bus_state_q == BUS_CAPTURE)? reg_access_error_i? ST_REG_ERR: ST_OK:
                           resp_status_q;
    assign resp_addr_d = (rx_cmd_valid_w && uart_busy_w && resp_no_pend_w)? rx_shift_d[47:32]:
                         (rx_cmd_valid_w && rx_cmd_illegal_w)? rx_shift_d[47:32]:
                         (bus_state_q == BUS_CAPTURE)? req_addr_q:
                         resp_addr_q;
    assign resp_addr_en = (rx_cmd_valid_w && uart_busy_w && resp_no_pend_w) || (rx_cmd_valid_w && rx_cmd_illegal_w) || (bus_state_q == BUS_CAPTURE);
    assign resp_rdata_d = (rx_cmd_valid_w && uart_busy_w && resp_no_pend_w)? 32'd0:
                         (rx_cmd_valid_w && rx_cmd_illegal_w)? 32'd0:
                         (bus_state_q == BUS_CAPTURE)? (req_op_q == OP_WRITE)? 32'd0: reg_rdata_i:
                         resp_rdata_q;      
    assign resp_rdata_en = (rx_cmd_valid_w && uart_busy_w && resp_no_pend_w) || (rx_cmd_valid_w && rx_cmd_illegal_w) || (bus_state_q == BUS_CAPTURE); 

    always @(*) begin
        case(bus_state_q)
            BUS_IDLE: begin
                if(req_valid_q) bus_state_d = BUS_ISSUE;
                else bus_state_d = bus_state_q;
            end
            BUS_ISSUE: begin
                bus_state_d = BUS_CAPTURE;
            end
            BUS_CAPTURE: begin
                bus_state_d = BUS_IDLE;
            end
            default: begin
                bus_state_d = BUS_IDLE;
            end
        endcase
    end

    assign req_valid_d = (rx_cmd_valid_w && !uart_busy_w && !rx_cmd_illegal_w)? 1'b1:
                         (bus_state_q == BUS_CAPTURE)? 1'b0:
                         req_valid_q;
    assign req_wr_en_d = ((bus_state_q == BUS_IDLE) && (bus_state_d == BUS_ISSUE) && (req_op_q == OP_WRITE))? 1'b1: 1'b0;
    assign reg_wr_en_o = req_wr_en_q;
    assign req_rd_en_d = ((bus_state_q == BUS_IDLE) && (bus_state_d == BUS_ISSUE) && (req_op_q == OP_READ))? 1'b1: 1'b0;  
    assign reg_rd_en_o = req_rd_en_q;
    assign req_op_d =  rx_shift_d[55:48];
    assign req_op_en = (rx_cmd_valid_w && !uart_busy_w && !rx_cmd_illegal_w);
    assign req_addr_d = rx_shift_d[47:32];
    assign req_addr_en = (rx_cmd_valid_w && !uart_busy_w && !rx_cmd_illegal_w);
    assign reg_addr_o = req_addr_q;
    assign req_wdata_d = rx_shift_d[31:0];
    assign req_wdata_en = (rx_cmd_valid_w && !uart_busy_w && !rx_cmd_illegal_w); 
    assign reg_wdata_o = req_wdata_q;

    always @(*) begin
        case(tx_state_q)
            TX_IDLE: begin
                if(resp_valid_q && !tx_busy_w) tx_state_d = TX_WAIT_HI;
                else tx_state_d = tx_state_q;
            end
            TX_WAIT_HI: begin
                if(tx_busy_w) tx_state_d = TX_WAIT_LO;
                else tx_state_d = tx_state_q;
            end
            TX_WAIT_LO: begin
                if(!tx_busy_w)begin
                    if(tx_idx_q == 3'd6) tx_state_d = TX_IDLE;
                    else tx_state_d = TX_WAIT_HI;
                end
                else tx_state_d = tx_state_q;
            end
            default: begin
                tx_state_d = TX_IDLE;
            end
        endcase
    end
    assign tx_idx_d = ((tx_state_q == TX_WAIT_LO) && (tx_state_d == TX_IDLE))? 3'd0:
                      ((tx_state_q == TX_WAIT_LO) && (tx_state_d == TX_WAIT_HI))? tx_idx_q + 1:
                      tx_idx_q;
    assign tx_data_d = ((tx_state_q == TX_IDLE) && (tx_state_d == TX_WAIT_HI))? resp_byte(3'd0, resp_status_q, resp_addr_q, resp_rdata_q):
                       ((tx_state_q == TX_WAIT_LO) && (tx_state_d == TX_WAIT_HI))? resp_byte(tx_idx_d, resp_status_q, resp_addr_q, resp_rdata_q):
                       tx_data_q;
    assign tx_data_en = (tx_state_d == TX_WAIT_HI);
    assign tx_valid_pulse_d = ((tx_state_q == TX_IDLE) && (tx_state_d == TX_WAIT_HI))? 1'b1:
                              ((tx_state_q == TX_WAIT_LO) && (tx_state_d == TX_WAIT_HI))? 1'b1: 1'b0;
                 

    uart_rx_8n1 u_uart_rx_8n1 (
        .clk        (clk),
        .rst_n      (rst_n),
        .rx_i       (uart_rx_i),
        .rx_data_o  (rx_data_w),
        .rx_valid_o (rx_valid_w),
        .rx_frame_err_o ()
    );

    uart_tx_8n1 u_uart_tx_8n1 (
        .clk        (clk),
        .rst_n      (rst_n),
        .tx_data_i  (tx_data_q),
        .tx_valid_i (tx_valid_pulse_q),
        .tx_o       (uart_tx_o),
        .tx_busy_o  (tx_busy_w)
    );

    dffe #(
        .WIDTH(56)
    ) rx_shift_ff (
        .clk(clk),
        .en_i(rx_shift_en),
        .d_i(rx_shift_d),
        .q_o(rx_shift_q)
    );

    dffr #(
        .WIDTH(3)
    ) rx_byte_cnt_ff (
        .clk(clk),
        .rst_n(rst_n),
        .d_i(rx_byte_cnt_d),
        .q_o(rx_byte_cnt_q)
    );

    dffre #(
        .WIDTH(BYTE_TIMEOUT_WIDTH),
        .RESET_VALUE('0)
    ) rx_timeout_cnt_ff (
        .clk(clk),
        .rst_n(rst_n),
        .en_i(rx_timeout_cnt_en),
        .d_i(rx_timeout_cnt_d),
        .q_o(rx_timeout_cnt_q)
    );

    dffr #(
        .WIDTH(1)
    ) req_valid_ff (
        .clk(clk),
        .rst_n(rst_n),
        .d_i(req_valid_d),
        .q_o(req_valid_q)
    );

    dffr #(
        .WIDTH(1)
    ) req_wr_en_ff (
        .clk(clk),
        .rst_n(rst_n),
        .d_i(req_wr_en_d),
        .q_o(req_wr_en_q)
    );

    dffr #(
        .WIDTH(1)
    ) req_rd_en_ff (
        .clk(clk),
        .rst_n(rst_n),
        .d_i(req_rd_en_d),
        .q_o(req_rd_en_q)
    );

    dffe #(
        .WIDTH(8)
    ) req_op_ff (
        .clk(clk),
        .en_i(req_op_en),
        .d_i(req_op_d),
        .q_o(req_op_q)
    );

    dffe #(
        .WIDTH(16)
    ) req_addr_ff (
        .clk(clk),
        .en_i(req_addr_en),
        .d_i(req_addr_d),
        .q_o(req_addr_q)
    );

    dffe #(
        .WIDTH(32)
    ) req_wdata_ff (
        .clk(clk),
        .en_i(req_wdata_en),
        .d_i(req_wdata_d),
        .q_o(req_wdata_q)
    );

    always_ff @(posedge clk or negedge rst_n) begin : bus_state_ff
        if(~rst_n)begin
            bus_state_q <= BUS_IDLE;
        end else begin
            bus_state_q <= bus_state_d;
        end
    end

    dffr #(
        .WIDTH(1)
    ) resp_valid_ff (
        .clk(clk),
        .rst_n(rst_n),
        .d_i(resp_valid_d),
        .q_o(resp_valid_q)
    );

    always_ff @(posedge clk or negedge rst_n) begin : resp_status_ff
        if(~rst_n)begin
            resp_status_q <= ST_OK;
        end else begin
            resp_status_q <= resp_status_d;
        end
    end

    dffe #(
        .WIDTH(16)
    ) resp_addr_ff (
        .clk(clk),
        .en_i(resp_addr_en),
        .d_i(resp_addr_d),
        .q_o(resp_addr_q)
    );

    dffe #(
        .WIDTH(32)
    ) resp_rdata_ff (
        .clk(clk),
        .en_i(resp_rdata_en),
        .d_i(resp_rdata_d),
        .q_o(resp_rdata_q)
    );

    always_ff @(posedge clk or negedge rst_n) begin : tx_state_ff
        if(~rst_n)begin
            tx_state_q <= TX_IDLE;
        end else begin
            tx_state_q <= tx_state_d;
        end
    end

    dffr #(
        .WIDTH(3)
    ) tx_idx_ff (
        .clk(clk),
        .rst_n(rst_n),
        .d_i(tx_idx_d),
        .q_o(tx_idx_q)
    );

    dffe #(
        .WIDTH(8)
    ) tx_data_ff (
        .clk(clk),
        .en_i(tx_data_en),
        .d_i(tx_data_d),
        .q_o(tx_data_q)
    );

    dffr #(
        .WIDTH(1)
    ) tx_valid_ff (
        .clk(clk),
        .rst_n(rst_n),
        .d_i(tx_valid_pulse_d),
        .q_o(tx_valid_pulse_q)
    );

    dffr #(
        .WIDTH(1)
    ) uart_frame_err_ff (
        .clk(clk),
        .rst_n(rst_n),
        .d_i(uart_frame_err_pulse_d),
        .q_o(uart_frame_err_pulse_q)
    );

    dffr #(
        .WIDTH(1)
    ) uart_overflow_ff (
        .clk(clk),
        .rst_n(rst_n),
        .d_i(uart_overflow_pulse_d),
        .q_o(uart_overflow_pulse_q)
    );
endmodule
`endif