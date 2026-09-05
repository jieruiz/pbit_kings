`ifndef PBIT_IO_WRAPPER_SV
`define PBIT_IO_WRAPPER_SV

module pbit_io_wrapper (
    input  wire pad_clk_i,
    input  wire pad_rst_n_i,
    input  wire pad_uart_rx_i,
    inout  wire pad_uart_tx_o,
    // PLL power nets: all VDD rails are 1.2 V, all VSS rails are ground.
    // Connect real PG networks in the physical flow, never tie-cell outputs.
    inout  wire pll_avdd,
    inout  wire pll_avss,
    inout  wire pll_dvdd,
    inout  wire pll_dvss,
    inout  wire pll_dvdd_drv,
    inout  wire pll_dvss_drv
);

    // Fixed configuration: 25 MHz reference * 32 / 2 = 400 MHz core clock.
    // Hold pad_rst_n_i low until all PLL supplies and REFCLK are stable.
    localparam int unsigned PLL_WAIT_CYCLES = 375; // 15 us at 25 MHz
    localparam int unsigned PLL_WAIT_WIDTH = $clog2(PLL_WAIT_CYCLES);

    logic ref_clk;
    logic ref_rst_n;
    logic pll_ready;
    logic pll_core_arst_n;
    logic [PLL_WAIT_WIDTH-1:0] pll_wait_count;
    logic core_clk;
    logic core_arst_n;
    logic core_rst_n;
    logic core_uart_rx;
    logic core_uart_tx;

    wire tie_hi;
    wire tie_lo;

    // Base tie cells from ICsprout55_SC9T_BASIC_SVT. These cells belong to
    // the 1.2 V core VDD/VSS domain and match the SC9T_site placement rows.
    // Do not replace them with the GTIE* ECO variants.
    //
    // The functional Verilog view exposes only Y. The power-aware view also
    // exposes VDD, VSS, VNW and VPW; connect those through the UPF/PG flow.
    TIEHIX1_9TSVT u_tie_hi (
        .Y (tie_hi)
    );

    TIELOX1_9TSVT u_tie_lo (
        .Y (tie_lo)
    );

    // External 25 MHz CMOS reference. Schmitt trigger and pulls are off.
    PDISDU u_pad_clk (
        .PAD (pad_clk_i),
        .PU  (tie_lo),
        .PD  (tie_lo),
        .C   (ref_clk),
        .IE  (tie_hi),
        .ST  (tie_lo)
    );

    // Active-low reset input. Schmitt trigger and weak pull-up are enabled.
    // Set PU to tie_lo if a reliable board-level pull-up is already present.
    PDISDU u_pad_rst_n (
        .PAD (pad_rst_n_i),
        .PU  (tie_hi),
        .PD  (tie_lo),
        .C   (core_arst_n),
        .IE  (tie_hi),
        .ST  (tie_hi)
    );

    // UART RX idles high, so the weak pull-up is enabled. Set PU to tie_lo
    // when the board-level UART source guarantees a driven idle level.
    PDISDU u_pad_uart_rx (
        .PAD (pad_uart_rx_i),
        .PU  (tie_hi),
        .PD  (tie_lo),
        .C   (core_uart_rx),
        .IE  (tie_hi),
        .ST  (tie_hi)
    );

    // UART TX is configured as a permanently enabled output at the lowest
    // drive-strength setting (S2:S1:S0 = 3'b000). Raise the drive setting only
    // after checking package/board load and signal integrity.
    PDBSDU u_pad_uart_tx (
        .PAD (pad_uart_tx_o),
        .OE  (tie_hi),
        .PU  (tie_lo),
        .PD  (tie_lo),
        .A   (core_uart_tx),
        .S0  (tie_lo),
        .S1  (tie_lo),
        .S2  (tie_lo),
        .C   (),
        .IE  (tie_lo),
        .ST  (tie_lo)
    );

    // EN is released on a reference-clock edge, after two reset-sync stages.
    // Asserting external reset disables the PLL and restarts the full wait.
    reset_sync_async_assert u_ref_reset_sync (
        .clk_i    (ref_clk),
        .arst_n_i (core_arst_n),
        .rst_n_o  (ref_rst_n)
    );

    PLL_TOP u_pll (
        .AVDD     (pll_avdd),
        .AVSS     (pll_avss),
        .DVDD     (pll_dvdd),
        .DVSS     (pll_dvss),
        .DVDD_DRV (pll_dvdd_drv),
        .DVSS_DRV (pll_dvss_drv),
        .REFCLK   (ref_clk),
        .EN       (ref_rst_n),
        .BP       (tie_lo),
        .N        ({tie_lo, tie_lo, tie_hi, {5{tie_lo}}}), // 8'h20
        .SELECT   (tie_lo),
        .OD       ({tie_lo, tie_hi}),                     // divide by 2
        .CKOUT1   (core_clk),
        .CKOUT2   (),
        .CKTST    ()
    );

    // PLL has no LOCK pin. Count 375 complete reference periods after EN.
    // The first increment occurs one full period after ref_rst_n rises.
    // This timer assumes a continuous, stable 25 MHz reference; it is not
    // a lock detector and cannot detect a missing reference or supply fault.
    always_ff @(posedge ref_clk or negedge ref_rst_n) begin
        if (!ref_rst_n) begin
            pll_wait_count <= '0;
            pll_ready      <= 1'b0;
        end else if (!pll_ready) begin
            if (pll_wait_count == PLL_WAIT_WIDTH'(PLL_WAIT_CYCLES - 1)) begin
                pll_ready <= 1'b1;
            end else begin
                pll_wait_count <= pll_wait_count + 1'b1;
            end
        end
    end

    // Hold the core in reset throughout PLL startup. Release only after
    // the wait and two CKOUT1 rising edges; assertion stays asynchronous.
    assign pll_core_arst_n = core_arst_n & pll_ready;

    reset_sync_async_assert u_reset_sync (
        .clk_i    (core_clk),
        .arst_n_i (pll_core_arst_n),
        .rst_n_o  (core_rst_n)
    );

    pbit_top u_pbit_top (
        .clk       (core_clk),
        .rst_n     (core_rst_n),
        .uart_rx_i (core_uart_rx),
        .uart_tx_o (core_uart_tx)
    );

endmodule

`endif
