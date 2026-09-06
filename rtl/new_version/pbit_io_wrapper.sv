`ifndef PBIT_IO_WRAPPER_SV
`define PBIT_IO_WRAPPER_SV
import pbit_pkg::*;
module pbit_io_wrapper (
    input  wire pad_clk_i,
    input  wire pad_rst_n_i,
    input  wire pad_uart_rx_i,
    inout  wire pad_uart_tx_o,
    input  wire pad_pll_cfg_rx_i,
    inout  wire pad_pll_cfg_tx_o,
    // PLL power nets: all VDD rails are 1.2 V, all VSS rails are ground.
    // Connect real PG networks in the physical flow, never tie-cell outputs.
    inout  wire pll_avdd,
    inout  wire pll_avss,
    inout  wire pll_dvdd,
    inout  wire pll_dvss,
    inout  wire pll_dvdd_drv,
    inout  wire pll_dvss_drv
);

    // Config UART: 25 MHz reference, 115200 baud. Default shadow: 400 MHz.
    // PLL stays disabled and core stays reset until a valid APPLY command.
    // Hold pad_rst_n_i low until all PLL supplies and REFCLK are stable.

    logic ref_clk;
    logic ref_rst_n;
    logic core_release;
    logic pll_core_arst_n;
    logic cfg_rx, cfg_tx, req_valid, req_write, resp_valid;
    logic [7:0] req_addr, resp_status, pll_n;
    logic [15:0] req_data, resp_data;
    logic pll_en, pll_bp, pll_select;
    logic [1:0] pll_od;
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

    PDISDU u_pad_pll_cfg_rx (
        .PAD(pad_pll_cfg_rx_i), .PU(tie_hi), .PD(tie_lo),
        .C(cfg_rx), .IE(tie_hi), .ST(tie_hi)
    );
    PDBSDU u_pad_pll_cfg_tx (
        .PAD(pad_pll_cfg_tx_o), .OE(tie_hi), .PU(tie_lo), .PD(tie_lo),
        .A(cfg_tx), .S0(tie_lo), .S1(tie_lo), .S2(tie_lo),
        .C(), .IE(tie_lo), .ST(tie_lo)
    );

    // Configuration domain remains alive while core reset is asserted.
    reset_sync_async_assert u_ref_reset_sync (
        .clk_i    (ref_clk),
        .arst_n_i (core_arst_n),
        .rst_n_o  (ref_rst_n)
    );

    // Explicitly keep configuration at 115200 baud, not the core's 10 Mbps.
    pll_cfg_uart #(.REF_HZ(REF_CLK_FREQ_HZ), .BAUD(PLL_CFG_BAUD_RATE)) u_pll_cfg_uart (
        .clk(ref_clk), .rst_n(ref_rst_n), .rx_i(cfg_rx), .tx_o(cfg_tx),
        .req_valid(req_valid), .req_write(req_write),
        .req_addr(req_addr), .req_data(req_data),
        .resp_valid(resp_valid), .resp_status(resp_status), .resp_data(resp_data)
    );
    pll_cfg_regs #(.REF_HZ(REF_CLK_FREQ_HZ)) u_pll_cfg_regs (
        .clk(ref_clk), .rst_n(ref_rst_n),
        .req_valid(req_valid), .req_write(req_write),
        .req_addr(req_addr), .req_data(req_data),
        .resp_valid(resp_valid), .resp_status(resp_status), .resp_data(resp_data),
        .core_rst_n(core_rst_n), .pll_en(pll_en), .core_release(core_release),
        .pll_n(pll_n), .pll_select(pll_select), .pll_bp(pll_bp), .pll_od(pll_od)
    );

    PLL_TOP u_pll (
        .AVDD     (pll_avdd),
        .AVSS     (pll_avss),
        .DVDD     (pll_dvdd),
        .DVSS     (pll_dvss),
        .DVDD_DRV (pll_dvdd_drv),
        .DVSS_DRV (pll_dvss_drv),
        .REFCLK   (ref_clk),
        .EN       (pll_en),
        .BP       (pll_bp),
        .N        (pll_n),
        .SELECT   (pll_select),
        .OD       (pll_od),
        .CKOUT1   (core_clk),
        .CKOUT2   (),
        .CKTST    ()
    );

    // Hold the core in reset throughout PLL startup. Release only after
    // the wait and two CKOUT1 rising edges; assertion stays asynchronous.
    assign pll_core_arst_n = core_arst_n & core_release;

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
