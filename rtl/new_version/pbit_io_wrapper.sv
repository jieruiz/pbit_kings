`ifndef PBIT_IO_WRAPPER_SV
`define PBIT_IO_WRAPPER_SV

module pbit_io_wrapper (
    input  wire pad_clk_i,
    input  wire pad_rst_n_i,
    input  wire pad_uart_rx_i,
    inout  wire pad_uart_tx_o
);

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

    // External CMOS clock input. Schmitt trigger and internal pulls are off.
    PDISDU u_pad_clk (
        .PAD (pad_clk_i),
        .PU  (tie_lo),
        .PD  (tie_lo),
        .C   (core_clk),
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

    reset_sync_async_assert u_reset_sync (
        .clk_i    (core_clk),
        .arst_n_i (core_arst_n),
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
