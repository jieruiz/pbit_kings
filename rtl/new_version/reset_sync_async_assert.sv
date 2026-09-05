`ifndef RESET_SYNC_ASYNC_ASSERT_SV
`define RESET_SYNC_ASYNC_ASSERT_SV

// Active-low reset synchronizer:
//   - reset assertion is asynchronous
//   - reset deassertion is synchronized to clk_i
//
// rst_n_o becomes high after two rising edges of clk_i following the release
// of arst_n_i. Keep both synchronizer flops in the same clock domain and place
// them close together during physical implementation.
module reset_sync_async_assert (
    input  logic clk_i,
    input  logic arst_n_i,
    output logic rst_n_o
);

    (* ASYNC_REG = "TRUE" *) logic [1:0] rst_sync_ff;

    always_ff @(posedge clk_i or negedge arst_n_i) begin
        if (!arst_n_i) begin
            rst_sync_ff <= 2'b00;
        end else begin
            rst_sync_ff <= {rst_sync_ff[0], 1'b1};
        end
    end

    assign rst_n_o = rst_sync_ff[1];

endmodule

`endif
