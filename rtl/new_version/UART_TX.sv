`ifndef UART_TX_8N1
`define UART_TX_8N1
import pbit_pkg::*;
module uart_tx_8n1 (
    input  logic       clk,
    input  logic       rst_n,

    input  logic [7:0] tx_data_i,
    input  logic       tx_valid_i,

    output logic       tx_o,
    output logic       tx_busy_o
);

    localparam logic [31:0] CLKS_PER_BIT = CLK_FREQ_HZ / BAUD_RATE;

    typedef enum logic [2:0] {
        S_IDLE  = 3'd0,
        S_START = 3'd1,
        S_DATA  = 3'd2,
        S_STOP  = 3'd3
    } state_e;

    state_e      state_q, state_d;

    logic [31:0] clk_cnt_q, clk_cnt_d;
    logic        clk_cnt_en;

    logic [2:0]  bit_cnt_q, bit_cnt_d; 

    logic [7:0]  tx_shift_q, tx_shift_d;
    logic        tx_shift_en;

    logic        tx_q, tx_d;

    logic        tx_busy_w;

    always @(*) begin
        case(state_q)
            S_IDLE: begin
                if(tx_valid_i) state_d = S_START;
                else state_d = state_q;
            end

            S_START: begin
                if(clk_cnt_q == CLKS_PER_BIT - 1) state_d = S_DATA;
                else state_d = state_q;
            end

            S_DATA: begin
                if((clk_cnt_q == CLKS_PER_BIT - 1) && (bit_cnt_q == 3'd7)) state_d = S_STOP;
                else state_d = state_q;
            end

            S_STOP: begin
                if(clk_cnt_q == CLKS_PER_BIT - 1) state_d = S_IDLE;
                else state_d = state_q;
            end

            default: state_d = S_IDLE;
        endcase
    end

    assign clk_cnt_d = ((state_q == S_START) && (clk_cnt_q == (CLKS_PER_BIT - 1)))? 32'd0 :
                       ((state_q == S_DATA) && (clk_cnt_q == (CLKS_PER_BIT - 1)))? 32'd0 :
                       ((state_q == S_STOP) && (clk_cnt_q == (CLKS_PER_BIT - 1)))? 32'd0 :
                        clk_cnt_q + 32'd1;
    assign clk_cnt_en = (state_q != S_IDLE);

    assign bit_cnt_d = (state_d == S_IDLE)? 3'd0 :
                       ((state_q == S_DATA) && (clk_cnt_q == (CLKS_PER_BIT - 1)))? bit_cnt_q + 3'd1 : // 3'd7 + 1 = 0
                        bit_cnt_q;

    assign tx_shift_d =  tx_data_i;
    assign tx_shift_en = (state_q == S_IDLE) && tx_valid_i;

    assign tx_d = (state_d == S_IDLE)? 1'b1 :
                  (state_d == S_START)? 1'b0 :
                  (state_d == S_DATA)? tx_shift_q[bit_cnt_q] :
                  (state_d == S_STOP)? 1'b1 : tx_q;
    assign tx_o = tx_q;

    assign tx_busy_w = (state_q == S_IDLE)? 1'b0 : 1'b1;
    assign tx_busy_o = tx_busy_w;

    always_ff @(posedge clk or negedge rst_n) begin : state_ff
        if(~rst_n)begin
            state_q <= S_IDLE;
        end else begin
            state_q <= state_d;
        end
    end

    dffre #(.WIDTH(32),
            .RESET_VALUE(32'd0)
    ) clk_cnt_ff (
        .clk(clk),
        .rst_n(rst_n),
        .en_i(clk_cnt_en),
        .d_i(clk_cnt_d),
        .q_o(clk_cnt_q)
    );

    dffr #(.WIDTH(3),
            .RESET_VALUE(3'd0)
    ) bit_cnt_ff (
        .clk(clk),
        .rst_n(rst_n),
        .d_i(bit_cnt_d),
        .q_o(bit_cnt_q)
    );

    dffe #(.WIDTH(8)
    ) tx_shift_ff (
        .clk(clk),
        .en_i(tx_shift_en),
        .d_i(tx_shift_d),
        .q_o(tx_shift_q)
    );

    dffr #(.WIDTH(1),
            .RESET_VALUE(1'b1)
    ) tx_ff (
        .clk(clk),
        .rst_n(rst_n),
        .d_i(tx_d),
        .q_o(tx_q)
    );
endmodule
`endif