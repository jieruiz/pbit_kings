`ifndef UART_RX_8N1
`define UART_RX_8N1
import pbit_pkg::*;
module uart_rx_8n1 #(
    parameter int CLK_FREQ_HZ = pbit_pkg::CLK_FREQ_HZ,
    parameter int BAUD_RATE = pbit_pkg::BAUD_RATE
) (
    input  logic       clk,
    input  logic       rst_n,

    input  logic       rx_i,

    output logic [7:0] rx_data_o,
    output logic       rx_valid_o
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

    logic [7:0]  rx_shift_q, rx_shift_d;
    logic        rx_shift_en;

    logic [7:0]  rx_data_q, rx_data_d;
    logic        rx_data_en;

    logic        rx_data_valid_q, rx_data_valid_d;
    
    logic        rx_sync_dly1, rx_sync_dly2;

    always @(*) begin
        case(state_q)
            S_IDLE: begin
                if(rx_sync_dly2 == 1'b0) begin
                    state_d = S_START;
                end else begin
                    state_d = S_IDLE;
                end
            end

            S_START: begin
                if(clk_cnt_q == (CLKS_PER_BIT / 2 - 1)) begin
                    if(rx_sync_dly2 == 1'b0) begin
                        state_d = S_DATA;
                    end else begin
                        state_d = S_IDLE;
                    end
                end else begin
                    state_d = S_START;
                end
            end

            S_DATA: begin
                if(clk_cnt_q == CLKS_PER_BIT - 1) begin
                    if(bit_cnt_q == 3'd7) begin
                        state_d = S_STOP;
                    end else begin
                        state_d = S_DATA;
                    end
                end else begin
                    state_d = S_DATA;
                end
            end

            S_STOP: begin
                if(clk_cnt_q == CLKS_PER_BIT - 1) begin
                    state_d = S_IDLE;
                end else begin
                    state_d = S_STOP;
                end
            end

            default: state_d = S_IDLE;
        endcase
    end

    assign clk_cnt_d = ((state_q == S_START) && (clk_cnt_q == (CLKS_PER_BIT / 2 - 1)))? 32'd0 :
                       ((state_q == S_DATA) && (clk_cnt_q == (CLKS_PER_BIT - 1)))? 32'd0 :
                       ((state_q == S_STOP) && (clk_cnt_q == (CLKS_PER_BIT - 1)))? 32'd0 :
                        clk_cnt_q + 32'd1;
    assign clk_cnt_en = (state_q != S_IDLE);

    assign bit_cnt_d = (state_q == S_IDLE)? 3'd0 :
                       ((state_q == S_DATA) && (clk_cnt_q == (CLKS_PER_BIT - 1)))? bit_cnt_q + 3'd1 : // 3'd7 + 1 = 0
                        bit_cnt_q;

    assign rx_shift_d = {rx_sync_dly2, rx_shift_q[7:1]};
    assign rx_shift_en = (state_q == S_DATA) && (clk_cnt_q == (CLKS_PER_BIT - 1));

    assign rx_data_d = rx_shift_q;
    assign rx_data_en = (state_q == S_STOP) && (clk_cnt_q == (CLKS_PER_BIT - 1));
    assign rx_data_o = rx_data_q;

    assign rx_data_valid_d = ((state_q == S_STOP) && (clk_cnt_q == (CLKS_PER_BIT - 1)))? 1'b1 : 1'b0;
    assign rx_valid_o = rx_data_valid_q;
    
    dffr #(.WIDTH(1),
           .RESET_VALUE(1'b1)
    ) rx_sync_dly1_ff (
        .clk(clk),
        .rst_n(rst_n),
        .d_i(rx_i),
        .q_o(rx_sync_dly1)
    );

    dffr #(.WIDTH(1),
           .RESET_VALUE(1'b1)
    ) rx_sync_dly2_ff (
        .clk(clk),
        .rst_n(rst_n),
        .d_i(rx_sync_dly1),
        .q_o(rx_sync_dly2)
    );

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

    dffre #(.WIDTH(8),
            .RESET_VALUE(8'd0)
    ) rx_shift_ff (
        .clk(clk),
        .rst_n(rst_n),
        .en_i(rx_shift_en),
        .d_i(rx_shift_d),
        .q_o(rx_shift_q)
    );

    dffe #(.WIDTH(8)
    ) rx_data_ff (
        .clk(clk),
        .en_i(rx_data_en),
        .d_i(rx_data_d),
        .q_o(rx_data_q)
    );

    dffr #(.WIDTH(1),
           .RESET_VALUE(1'b0)
    ) rx_data_valid_ff (
        .clk(clk),
        .rst_n(rst_n),
        .d_i(rx_data_valid_d),
        .q_o(rx_data_valid_q)
    );
endmodule
`endif
