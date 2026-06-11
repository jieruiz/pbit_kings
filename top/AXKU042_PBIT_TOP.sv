`timescale 1ns / 1ps

module axku042_pbit_top (
    input  wire pl_clk0_p,
    input  wire pl_clk0_n,

    input  wire fpga_rsetn,

    input  wire uart_rxd,
    output wire uart_txd,

    output wire led1,
    output wire led2,
    output wire led3,
    output wire led4
);

    // ------------------------------------------------------------
    // 200 MHz differential clock input
    // ------------------------------------------------------------

    wire clk_200m;

    IBUFDS #(
        .DIFF_TERM    ("FALSE"),
        .IBUF_LOW_PWR ("FALSE")
    ) u_ibufds_clk (
        .I  (pl_clk0_p),
        .IB (pl_clk0_n),
        .O  (clk_200m)
    );

    // ------------------------------------------------------------
    // Reset synchronizer
    // fpga_rsetn is active low from board.
    // Internal rst_n_sync is active low reset, synchronously released.
    // ------------------------------------------------------------

    reg [3:0] rst_sync;

    always @(posedge clk_200m or negedge fpga_rsetn) begin
        if (!fpga_rsetn) begin
            rst_sync <= 4'b0000;
        end else begin
            rst_sync <= {rst_sync[2:0], 1'b1};
        end
    end

    wire rst_n_sync;
    assign rst_n_sync = rst_sync[3];

    // ------------------------------------------------------------
    // Internal status wires
    // ------------------------------------------------------------

    wire cfg_done_w;
    wire run_busy_w;
    wire run_done_w;
    wire [31:0] sweep_cnt_w;
    wire [19*19-1:0] spin_flat_w;

    // ------------------------------------------------------------
    // Core
    //
    // Important:
    // Board clock is 200 MHz, so CLK_FREQ_HZ must be 200_000_000.
    // If you later use a clock wizard to generate 100 MHz,
    // then change this parameter back to 100_000_000.
    // ------------------------------------------------------------

    pbit_fpga_top_uart_run #(
        .CLK_FREQ_HZ (200_000_000),
        .BAUD_RATE   (115200),
        .ROWS        (19),
        .COLS        (19),
        .N_TRIAL     (5),
        .NUM_SWEEPS  (50)
    ) u_pbit_fpga_top_uart_run (
        .clk         (clk_200m),
        .rst_n       (rst_n_sync),

        .uart_rx_i   (uart_rxd),
        .uart_tx_o   (uart_txd),

        .cfg_done_o  (cfg_done_w),
        .run_busy_o  (run_busy_w),
        .run_done_o  (run_done_w),
        .sweep_cnt_o (sweep_cnt_w),

        .spin_flat_o (spin_flat_w)
    );

    // ------------------------------------------------------------
    // LEDs
    // According to manual, LED is on when FPGA IO outputs high.
    // ------------------------------------------------------------

    assign led1 = cfg_done_w;
    assign led2 = run_busy_w;
    assign led3 = run_done_w;
    assign led4 = sweep_cnt_w[0];

endmodule
