`timescale 1ns / 1ps

module uart_tx_8n1 #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer BAUD_RATE   = 115200
)(
    input  wire       clk,
    input  wire       rst_n,

    input  wire [7:0] tx_data_i,
    input  wire       tx_valid_i,

    output reg        tx_o,
    output reg        tx_busy_o
);

    localparam integer CLKS_PER_BIT = CLK_FREQ_HZ / BAUD_RATE;

    localparam S_IDLE  = 3'd0;
    localparam S_START = 3'd1;
    localparam S_DATA  = 3'd2;
    localparam S_STOP  = 3'd3;

    reg [2:0] state_q;

    reg [31:0] clk_cnt_q;
    reg [2:0]  bit_idx_q;
    reg [7:0]  tx_shift_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q    <= S_IDLE;
            clk_cnt_q  <= 32'd0;
            bit_idx_q  <= 3'd0;
            tx_shift_q <= 8'd0;

            tx_o       <= 1'b1;
            tx_busy_o  <= 1'b0;
        end else begin
            case (state_q)

                S_IDLE: begin
                    tx_o      <= 1'b1;
                    tx_busy_o <= 1'b0;
                    clk_cnt_q <= 32'd0;
                    bit_idx_q <= 3'd0;

                    if (tx_valid_i) begin
                        tx_shift_q <= tx_data_i;
                        tx_busy_o  <= 1'b1;
                        state_q    <= S_START;
                    end
                end

                S_START: begin
                    tx_o <= 1'b0;

                    if (clk_cnt_q == CLKS_PER_BIT - 1) begin
                        clk_cnt_q <= 32'd0;
                        state_q   <= S_DATA;
                    end else begin
                        clk_cnt_q <= clk_cnt_q + 32'd1;
                    end
                end

                S_DATA: begin
                    tx_o <= tx_shift_q[bit_idx_q];

                    if (clk_cnt_q == CLKS_PER_BIT - 1) begin
                        clk_cnt_q <= 32'd0;

                        if (bit_idx_q == 3'd7) begin
                            bit_idx_q <= 3'd0;
                            state_q   <= S_STOP;
                        end else begin
                            bit_idx_q <= bit_idx_q + 3'd1;
                        end
                    end else begin
                        clk_cnt_q <= clk_cnt_q + 32'd1;
                    end
                end

                S_STOP: begin
                    tx_o <= 1'b1;

                    if (clk_cnt_q == CLKS_PER_BIT - 1) begin
                        clk_cnt_q <= 32'd0;
                        state_q   <= S_IDLE;
                    end else begin
                        clk_cnt_q <= clk_cnt_q + 32'd1;
                    end
                end

                default: begin
                    state_q <= S_IDLE;
                end

            endcase
        end
    end

endmodule