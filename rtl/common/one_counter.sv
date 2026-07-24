`ifndef ONE_COUNTER
`define ONE_COUNTER
module one_counter #(
    parameter integer WIDTH = 8,
    parameter integer COUNT_W = $clog2(WIDTH + 1)
) (
    input  logic [WIDTH-1:0]   data_i,
    output logic [COUNT_W-1:0] count_o
);
    // ------------------------------------------------------------
    // 4-bit查找表：输出范围0~4，需要3bit
    // ------------------------------------------------------------
    function automatic logic [2:0] popcount4_lut(
        input logic [3:0] data
    );
        case (data)
            4'b0000: popcount4_lut = 3'd0;

            4'b0001,
            4'b0010,
            4'b0100,
            4'b1000: popcount4_lut = 3'd1;

            4'b0011,
            4'b0101,
            4'b0110,
            4'b1001,
            4'b1010,
            4'b1100: popcount4_lut = 3'd2;

            4'b0111,
            4'b1011,
            4'b1101,
            4'b1110: popcount4_lut = 3'd3;

            4'b1111: popcount4_lut = 3'd4;

            default: popcount4_lut = 3'd0;
        endcase
    endfunction

    generate
        // ========================================================
        // 递归终止条件：WIDTH <= 8
        // ========================================================
        if (WIDTH <= 8) begin : GEN_LUT_BASE

            logic [7:0] data_pad;
            logic [2:0] count_low;
            logic [2:0] count_high;
            logic [3:0] count_sum;

            // 将不足8bit的输入在高位补0
            assign data_pad = {{(8-WIDTH){1'b0}}, data_i};
            assign count_low = popcount4_lut(data_pad[3:0]);
            assign count_high = popcount4_lut(data_pad[7:4]);
            assign count_sum = {1'b0, count_low} + {1'b0, count_high};
            assign count_o = count_sum[COUNT_W-1:0];
        end else begin : GEN_RECURSIVE

            // ====================================================
            // 二分递归
            // ====================================================
            localparam int unsigned LOW_WIDTH  = WIDTH / 2;
            localparam int unsigned HIGH_WIDTH = WIDTH - LOW_WIDTH;

            localparam int unsigned LOW_COUNT_W =
                $clog2(LOW_WIDTH + 1);

            localparam int unsigned HIGH_COUNT_W =
                $clog2(HIGH_WIDTH + 1);

            logic [LOW_COUNT_W-1:0]  low_count;
            logic [HIGH_COUNT_W-1:0] high_count;

            logic [COUNT_W-1:0] low_count_ext;
            logic [COUNT_W-1:0] high_count_ext;

            one_counter #(
                .WIDTH   (LOW_WIDTH),
                .COUNT_W (LOW_COUNT_W)
            ) u_popcount_low (
                .data_i  (data_i[LOW_WIDTH-1:0]),
                .count_o (low_count)
            );

            one_counter #(
                .WIDTH   (HIGH_WIDTH),
                .COUNT_W (HIGH_COUNT_W)
            ) u_popcount_high (
                .data_i  (data_i[WIDTH-1:LOW_WIDTH]),
                .count_o (high_count)
            );

            assign low_count_ext = {
                    {(COUNT_W-LOW_COUNT_W){1'b0}},
                    low_count
                };

            assign high_count_ext = {
                    {(COUNT_W-HIGH_COUNT_W){1'b0}},
                    high_count
                };

            assign count_o = low_count_ext + high_count_ext;
        end
    endgenerate
endmodule
`endif