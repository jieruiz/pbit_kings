`timescale 1ns/1ps
import pbit_pkg::*;

// White-box routing regression at the 5x5 BANK boundary. Configuration still
// enters through the production register block; hierarchy is used only to
// observe the exact datapath slots on both endpoints.
module tb_topology_routing;
    localparam realtime CLK_PERIOD = 1s / real'(CLK_FREQ_HZ);
    localparam int TEST_NUMBER = 2;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic uart_mode = 1'b0;
    logic rx = 1'b1;
    logic wr_en = 1'b0;
    logic rd_en = 1'b0;
    logic [15:0] addr = '0;
    logic [31:0] wdata = '0;
    wire tx;
    wire [31:0] rdata;
    wire access_error, cfg_busy, run_busy, run_done;
    wire run_accept, sweep_done, phase_start, phase;
    wire [I0_LEVEL_WIDTH-1:0] i0;
    wire [N_SPIN-1:0] spins;
    wire [BANK_ROWS*BANK_COLS-1:0] bank_done;

    always #(CLK_PERIOD/2) clk = ~clk;
    chimera_problem_harness dut (.*);

    task automatic bus_access(
        input bit write_access,
        input logic [15:0] address,
        input logic [31:0] value,
        input bit expected_error,
        output logic [31:0] result
    );
        @(negedge clk);
        addr = address;
        wdata = value;
        wr_en = write_access;
        rd_en = !write_access;
        @(posedge clk);
        #(CLK_PERIOD/4);
        if (access_error !== expected_error)
            $fatal(1, "Bus error address=%h actual=%b expected=%b",
                   address, access_error, expected_error);
        result = rdata;
        @(negedge clk);
        wr_en = 1'b0;
        rd_en = 1'b0;
    endtask

    task automatic wr(input logic [15:0] address, input logic [31:0] value);
        logic [31:0] ignored;
        bus_access(1'b1, address, value, 1'b0, ignored);
    endtask

    task automatic wr_error(input logic [15:0] address, input logic [31:0] value);
        logic [31:0] ignored;
        bus_access(1'b1, address, value, 1'b1, ignored);
    endtask

    task automatic wait_cfg_idle;
        integer waited;
        begin
            waited = 0;
            while (cfg_busy) begin
                @(negedge clk);
                waited++;
                if (waited > 100) $fatal(1, "CFG_BUSY timeout");
            end
        end
    endtask

    task automatic configure_edge(
        input integer unit_row,
        input integer unit_col,
        input integer edge_type,
        input integer edge_number,
        input logic [EDGE_CFG_PACKED_WIDTH-1:0] packed_cfg
    );
        logic [31:0] target;
        logic [31:0] cfg;
        begin
            target = (edge_type << EDGE_TYPE_LSB) |
                     (edge_number << EDGE_TARGET_NUMBER_LSB);
            cfg = '0;
            cfg[EDGE_CFG_EDGE_VALID_LSB] =
                packed_cfg[EDGE_CFG_EDGE_VALID_PACKED_LSB];
            cfg[EDGE_CFG_EDGE_SIGN_LSB] =
                packed_cfg[EDGE_CFG_EDGE_SIGN_PACKED_LSB];
            cfg[EDGE_CFG_EDGE_PROB_MSB:EDGE_CFG_EDGE_PROB_LSB] =
                packed_cfg[EDGE_CFG_EDGE_PROB_PACKED_MSB:EDGE_CFG_EDGE_PROB_PACKED_LSB];
            wr(A_UNIT_TARGET, unit_row | (unit_col << UNIT_TARGET_COL_LSB));
            wr(A_EDGE_TARGET, target);
            wr(A_EDGE_CFG, cfg);
            wr(A_EDGE_CMD, 1 << APPLY_EDGE_LSB);
            wait_cfg_idle();
        end
    endtask

    function automatic logic [EDGE_CFG_PACKED_WIDTH-1:0] edge_value(input integer edge_type);
        logic [EDGE_CFG_PACKED_WIDTH-1:0] value;
        begin
            value = '0;
            value[EDGE_CFG_EDGE_VALID_PACKED_LSB] = 1'b1;
            value[EDGE_CFG_EDGE_SIGN_PACKED_LSB] = edge_type[0];
            value[EDGE_CFG_EDGE_PROB_PACKED_MSB:EDGE_CFG_EDGE_PROB_PACKED_LSB] =
                EDGE_CFG_EDGE_PROB_WIDTH'(20 + edge_type);
            edge_value = value;
        end
    endfunction

    task automatic check_cfg(
        input logic [EDGE_CFG_PACKED_WIDTH-1:0] actual,
        input logic [EDGE_CFG_PACKED_WIDTH-1:0] expected,
        input string label
    );
        if (actual !== expected)
            $fatal(1, "%s actual=%h expected=%h", label, actual, expected);
    endtask

    initial begin : TEST
        logic [EDGE_CFG_PACKED_WIDTH-1:0] expected [0:5];
        logic [31:0] ignored;
        integer edge_type;

        repeat (8) @(negedge clk);
        rst_n = 1'b1;
        repeat (8) @(negedge clk);

        // Cell (4,4) is the bottom-right cell of BANK(0,0). Types 4 and 5
        // therefore cross into BANK(0,1) and BANK(1,0), respectively.
        for (edge_type = 0; edge_type < 6; edge_type++) begin
            expected[edge_type] = edge_value(edge_type);
            configure_edge(4, 4, edge_type, TEST_NUMBER, expected[edge_type]);
        end

        // All six edge types must reside in their owner slot. Keep hierarchy
        // indices constant for compatibility with the T6 VCS release.
        check_cfg(dut.u_array.GEN_BANK_ROW[0].GEN_BANK_COL[0].u_pbit_bank.GEN_ROW[4].GEN_COL[4].GEN_VALID.GEN_ORDINARY.u_cell.owned_edge_cfg_w[0][TEST_NUMBER], expected[0], "owner type=0");
        check_cfg(dut.u_array.GEN_BANK_ROW[0].GEN_BANK_COL[0].u_pbit_bank.GEN_ROW[4].GEN_COL[4].GEN_VALID.GEN_ORDINARY.u_cell.owned_edge_cfg_w[1][TEST_NUMBER], expected[1], "owner type=1");
        check_cfg(dut.u_array.GEN_BANK_ROW[0].GEN_BANK_COL[0].u_pbit_bank.GEN_ROW[4].GEN_COL[4].GEN_VALID.GEN_ORDINARY.u_cell.owned_edge_cfg_w[2][TEST_NUMBER], expected[2], "owner type=2");
        check_cfg(dut.u_array.GEN_BANK_ROW[0].GEN_BANK_COL[0].u_pbit_bank.GEN_ROW[4].GEN_COL[4].GEN_VALID.GEN_ORDINARY.u_cell.owned_edge_cfg_w[3][TEST_NUMBER], expected[3], "owner type=3");
        check_cfg(dut.u_array.GEN_BANK_ROW[0].GEN_BANK_COL[0].u_pbit_bank.GEN_ROW[4].GEN_COL[4].GEN_VALID.GEN_ORDINARY.u_cell.owned_edge_cfg_w[4][TEST_NUMBER], expected[4], "owner type=4");
        check_cfg(dut.u_array.GEN_BANK_ROW[0].GEN_BANK_COL[0].u_pbit_bank.GEN_ROW[4].GEN_COL[4].GEN_VALID.GEN_ORDINARY.u_cell.owned_edge_cfg_w[5][TEST_NUMBER], expected[5], "owner type=5");

        // Phase 0: even cell (4,4) selects its left shore. Internal type t
        // appears at datapath t/lane number; down is outgoing lane 5.
        check_cfg(dut.u_array.GEN_BANK_ROW[0].GEN_BANK_COL[0].u_pbit_bank.GEN_ROW[4].GEN_COL[4].GEN_VALID.GEN_ORDINARY.u_cell.GEN_DATAPATH[0].selected_edge_w[TEST_NUMBER], expected[0], "internal left endpoint type=0");
        check_cfg(dut.u_array.GEN_BANK_ROW[0].GEN_BANK_COL[0].u_pbit_bank.GEN_ROW[4].GEN_COL[4].GEN_VALID.GEN_ORDINARY.u_cell.GEN_DATAPATH[1].selected_edge_w[TEST_NUMBER], expected[1], "internal left endpoint type=1");
        check_cfg(dut.u_array.GEN_BANK_ROW[0].GEN_BANK_COL[0].u_pbit_bank.GEN_ROW[4].GEN_COL[4].GEN_VALID.GEN_ORDINARY.u_cell.GEN_DATAPATH[2].selected_edge_w[TEST_NUMBER], expected[2], "internal left endpoint type=2");
        check_cfg(dut.u_array.GEN_BANK_ROW[0].GEN_BANK_COL[0].u_pbit_bank.GEN_ROW[4].GEN_COL[4].GEN_VALID.GEN_ORDINARY.u_cell.GEN_DATAPATH[3].selected_edge_w[TEST_NUMBER], expected[3], "internal left endpoint type=3");
        check_cfg(
            dut.u_array.GEN_BANK_ROW[0].GEN_BANK_COL[0].u_pbit_bank
               .GEN_ROW[4].GEN_COL[4].GEN_VALID.GEN_ORDINARY.u_cell
               .GEN_DATAPATH[TEST_NUMBER].selected_edge_w[5],
            expected[5], "down owner endpoint");

        // The right edge must traverse the top-level BANK boundary and enter
        // the neighboring cell as incoming lane 4.
        check_cfg(dut.u_array.right_cfg_w[0][0][4][TEST_NUMBER],
                  expected[4], "right exported from BANK(0,0)");
        check_cfg(
            dut.u_array.GEN_BANK_ROW[0].GEN_BANK_COL[1].u_pbit_bank
               .GEN_ROW[4].GEN_COL[0].GEN_VALID.GEN_ORDINARY.u_cell
               .GEN_DATAPATH[TEST_NUMBER].selected_edge_w[4],
            expected[4], "right imported into BANK(0,1)");

        // Switch the two relevant BANKs to phase 1. The owner selects its
        // right shore, while the odd-parity lower neighbor selects its left shore.
        force dut.u_array.GEN_BANK_ROW[0].GEN_BANK_COL[0].u_pbit_bank.phase_q = 1'b1;
        force dut.u_array.GEN_BANK_ROW[1].GEN_BANK_COL[0].u_pbit_bank.phase_q = 1'b1;
        #0.001;
        check_cfg(dut.u_array.GEN_BANK_ROW[0].GEN_BANK_COL[0].u_pbit_bank.GEN_ROW[4].GEN_COL[4].GEN_VALID.GEN_ORDINARY.u_cell.GEN_DATAPATH[TEST_NUMBER].selected_edge_w[0], expected[0], "internal right endpoint type=0");
        check_cfg(dut.u_array.GEN_BANK_ROW[0].GEN_BANK_COL[0].u_pbit_bank.GEN_ROW[4].GEN_COL[4].GEN_VALID.GEN_ORDINARY.u_cell.GEN_DATAPATH[TEST_NUMBER].selected_edge_w[1], expected[1], "internal right endpoint type=1");
        check_cfg(dut.u_array.GEN_BANK_ROW[0].GEN_BANK_COL[0].u_pbit_bank.GEN_ROW[4].GEN_COL[4].GEN_VALID.GEN_ORDINARY.u_cell.GEN_DATAPATH[TEST_NUMBER].selected_edge_w[2], expected[2], "internal right endpoint type=2");
        check_cfg(dut.u_array.GEN_BANK_ROW[0].GEN_BANK_COL[0].u_pbit_bank.GEN_ROW[4].GEN_COL[4].GEN_VALID.GEN_ORDINARY.u_cell.GEN_DATAPATH[TEST_NUMBER].selected_edge_w[3], expected[3], "internal right endpoint type=3");
        check_cfg(
            dut.u_array.GEN_BANK_ROW[0].GEN_BANK_COL[0].u_pbit_bank
               .GEN_ROW[4].GEN_COL[4].GEN_VALID.GEN_ORDINARY.u_cell
               .GEN_DATAPATH[TEST_NUMBER].selected_edge_w[5],
            expected[4], "right owner endpoint");
        check_cfg(dut.u_array.down_cfg_w[0][0][4][TEST_NUMBER],
                  expected[5], "down exported from BANK(0,0)");
        check_cfg(
            dut.u_array.GEN_BANK_ROW[1].GEN_BANK_COL[0].u_pbit_bank
               .GEN_ROW[0].GEN_COL[4].GEN_VALID.GEN_ORDINARY.u_cell
               .GEN_DATAPATH[TEST_NUMBER].selected_edge_w[4],
            expected[5], "down imported into BANK(1,0)");

        // Prove that the incoming neighbor-spin wires, not only configuration,
        // cross the same two BANK boundaries.
        force dut.u_array.GEN_BANK_ROW[0].GEN_BANK_COL[0].u_pbit_bank
                 .GEN_ROW[4].GEN_COL[4].GEN_VALID.GEN_ORDINARY.u_cell.spin_o[6] = 1'b1;
        force dut.u_array.GEN_BANK_ROW[0].GEN_BANK_COL[0].u_pbit_bank
                 .GEN_ROW[4].GEN_COL[4].GEN_VALID.GEN_ORDINARY.u_cell.spin_o[2] = 1'b1;
        force dut.u_array.GEN_BANK_ROW[0].GEN_BANK_COL[1].u_pbit_bank
                 .GEN_ROW[4].GEN_COL[0].GEN_VALID.GEN_ORDINARY.u_cell.spin_o[6] = 1'b0;
        force dut.u_array.GEN_BANK_ROW[1].GEN_BANK_COL[0].u_pbit_bank
                 .GEN_ROW[0].GEN_COL[4].GEN_VALID.GEN_ORDINARY.u_cell.spin_o[2] = 1'b0;
        #0.001;
        if (dut.u_array.GEN_BANK_ROW[0].GEN_BANK_COL[1].u_pbit_bank
               .GEN_ROW[4].GEN_COL[0].GEN_VALID.GEN_ORDINARY.u_cell
               .GEN_DATAPATH[TEST_NUMBER].neighbor_spin_w[4] !== 1'b1)
            $fatal(1, "Right-neighbor incoming spin did not cross BANK boundary");
        if (dut.u_array.GEN_BANK_ROW[1].GEN_BANK_COL[0].u_pbit_bank
               .GEN_ROW[0].GEN_COL[4].GEN_VALID.GEN_ORDINARY.u_cell
               .GEN_DATAPATH[TEST_NUMBER].neighbor_spin_w[4] !== 1'b1)
            $fatal(1, "Down-neighbor incoming spin did not cross BANK boundary");
        if (dut.u_array.GEN_BANK_ROW[0].GEN_BANK_COL[0].u_pbit_bank
               .GEN_ROW[4].GEN_COL[4].GEN_VALID.GEN_ORDINARY.u_cell
               .GEN_DATAPATH[TEST_NUMBER].neighbor_spin_w[5] !== 1'b0)
            $fatal(1, "Owner outgoing neighbor spin did not return from right BANK");

        release dut.u_array.GEN_BANK_ROW[0].GEN_BANK_COL[0].u_pbit_bank.phase_q;
        release dut.u_array.GEN_BANK_ROW[1].GEN_BANK_COL[0].u_pbit_bank.phase_q;
        #0.001;
        if (dut.u_array.GEN_BANK_ROW[0].GEN_BANK_COL[0].u_pbit_bank
               .GEN_ROW[4].GEN_COL[4].GEN_VALID.GEN_ORDINARY.u_cell
               .GEN_DATAPATH[TEST_NUMBER].neighbor_spin_w[5] !== 1'b0)
            $fatal(1, "Owner outgoing neighbor spin did not return from lower BANK");

        // Production register legality checks at the physical array edges.
        wr(A_ERROR_STATUS, 32'hffff_ffff);
        wr(A_UNIT_TARGET, 19 | (19 << UNIT_TARGET_COL_LSB));
        wr(A_EDGE_TARGET, 4 | (TEST_NUMBER << EDGE_TARGET_NUMBER_LSB));
        wr_error(A_EDGE_CMD, 1 << APPLY_EDGE_LSB);
        bus_access(1'b0, A_ERROR_STATUS, 32'd0, 1'b0, ignored);
        if (ignored !== (1 << EDGE_BOUNDARY_ERR_LSB))
            $fatal(1, "Right array-boundary error actual=%h", ignored);
        wr(A_ERROR_STATUS, 32'hffff_ffff);
        wr(A_EDGE_TARGET, 5 | (TEST_NUMBER << EDGE_TARGET_NUMBER_LSB));
        wr_error(A_EDGE_CMD, 1 << APPLY_EDGE_LSB);
        bus_access(1'b0, A_ERROR_STATUS, 32'd0, 1'b0, ignored);
        if (ignored !== (1 << EDGE_BOUNDARY_ERR_LSB))
            $fatal(1, "Down array-boundary error actual=%h", ignored);

        $display("[TB_TOPOLOGY_ROUTING] PASS internal edges and cross-BANK right/down routing");
        $finish;
    end

    initial begin
        #2ms;
        $fatal(1, "TB_TOPOLOGY_ROUTING timeout");
    end
endmodule
