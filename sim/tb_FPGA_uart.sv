`timescale 1ns / 1ps

module tb_pbit_fpga_top_uart_run_3x3;

    localparam integer CLK_FREQ_HZ = 100_000_000;
    localparam integer BAUD_RATE   = 10_000_000;   // fast for simulation
    localparam integer BIT_CYCLES  = CLK_FREQ_HZ / BAUD_RATE;

    localparam integer ROWS   = 3;
    localparam integer COLS   = 3;
    localparam integer N_SPIN = ROWS * COLS;

    localparam integer N_TRIAL    = 5;
    localparam integer NUM_SWEEPS = 1;

    localparam [1:0] CMD_NODE = 2'b00;
    localparam [1:0] CMD_EDGE = 2'b01;
    localparam [1:0] CMD_CTRL = 2'b10;
    localparam [1:0] CMD_END  = 2'b11;

    localparam [5:0] OP_CONFIG_DONE   = 6'd0;
    localparam [5:0] OP_RUN_START     = 6'd1;
    localparam [5:0] OP_SNAPSHOT_READ = 6'd2;

    localparam [1:0] EDGE_H   = 2'd0;
    localparam [1:0] EDGE_V   = 2'd1;
    localparam [1:0] EDGE_DSE = 2'd2;
    localparam [1:0] EDGE_DSW = 2'd3;

    localparam [7:0] ACK_OK   = 8'hA5;
    localparam [7:0] ACK_BAD  = 8'h5A;
    localparam [7:0] SNAP_HDR = 8'h53;

    logic clk;
    logic rst_n;

    logic uart_rx_i;   // PC drives this into FPGA
    wire  uart_tx_o;   // FPGA drives this back to PC

    wire cfg_done_o;
    wire run_busy_o;
    wire run_done_o;
    wire [31:0] sweep_cnt_o;
    wire [N_SPIN-1:0] spin_flat_o;

    integer error_count;
    integer r;
    integer c;

    pbit_fpga_top_uart_run #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE  (BAUD_RATE),
        .ROWS       (ROWS),
        .COLS       (COLS),
        .N_TRIAL    (N_TRIAL),
        .NUM_SWEEPS (NUM_SWEEPS)
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),

        .uart_rx_i   (uart_rx_i),
        .uart_tx_o   (uart_tx_o),

        .cfg_done_o  (cfg_done_o),
        .run_busy_o  (run_busy_o),
        .run_done_o  (run_done_o),
        .sweep_cnt_o (sweep_cnt_o),

        .spin_flat_o (spin_flat_o)
    );

    // ------------------------------------------------------------
    // Clock
    // ------------------------------------------------------------

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;  // 100 MHz
    end

    // ------------------------------------------------------------
    // Utility
    // ------------------------------------------------------------

    function automatic int idx(input int row, input int col);
        begin
            idx = row * COLS + col;
        end
    endfunction

    function automatic [8:0] expected_snapshot;
        input [31:0] scenario;
        begin
            expected_snapshot = {N_SPIN{1'b0}};

            case (scenario)
                0: begin
                    expected_snapshot = 9'b010_110_011;
                end

                1: begin
                    expected_snapshot = 9'b101_101_100;
                end

                default: begin
                    expected_snapshot = {N_SPIN{1'b0}};
                end
            endcase
        end
    endfunction

    function automatic [63:0] make_node_cmd;
        input [4:0]  row;
        input [4:0]  col;
        input [31:0] seed;
        input        init_spin;
        input        clamp_en;
        input        clamp_spin;
        input        bias_sign;
        input [3:0]  bias_prob4;
        reg [63:0] cmd;
        begin
            cmd = 64'd0;
            cmd[63:62] = CMD_NODE;
            cmd[61:57] = row;
            cmd[56:52] = col;
            cmd[51:20] = seed;
            cmd[19]    = init_spin;
            cmd[18]    = clamp_en;
            cmd[17]    = clamp_spin;
            cmd[16]    = bias_sign;
            cmd[15:12] = bias_prob4;
            make_node_cmd = cmd;
        end
    endfunction

    function automatic [63:0] make_edge_cmd;
        input [1:0] edge_type;
        input [4:0] row;
        input [4:0] col;
        input [3:0] prob4;
        input       sign;
        input       valid;
        reg [63:0] cmd;
        begin
            cmd = 64'd0;
            cmd[63:62] = CMD_EDGE;
            cmd[61:60] = edge_type;
            cmd[59:55] = row;
            cmd[54:50] = col;
            cmd[49:46] = prob4;
            cmd[45]    = sign;
            cmd[44]    = valid;
            make_edge_cmd = cmd;
        end
    endfunction

    function automatic [63:0] make_ctrl_cmd;
        input [5:0] opcode;
        reg [63:0] cmd;
        begin
            cmd = 64'd0;
            cmd[63:62] = CMD_CTRL;
            cmd[61:56] = opcode;
            make_ctrl_cmd = cmd;
        end
    endfunction

    task automatic wait_bit_time;
        begin
            repeat (BIT_CYCLES) @(posedge clk);
        end
    endtask

    // ------------------------------------------------------------
    // PC sends one UART byte into FPGA uart_rx_i.
    // UART format: 8N1, LSB first.
    //
    // Important:
    // Do NOT add extra one-bit gap after stop bit.
    // Otherwise the PC-side testbench may miss FPGA ACK start bit.
    // ------------------------------------------------------------
    task automatic pc_uart_send_byte;
        input [7:0] data;
        integer i;
        begin
            // idle
            uart_rx_i = 1'b1;
            @(posedge clk);

            // start bit
            uart_rx_i = 1'b0;
            wait_bit_time();

            // data bits, LSB first
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx_i = data[i];
                wait_bit_time();
            end

            // stop bit
            uart_rx_i = 1'b1;
            wait_bit_time();
        end
    endtask

    // ------------------------------------------------------------
    // PC receives one UART byte from FPGA uart_tx_o.
    //
    // Important:
    // Use negedge to catch the exact start bit.
    // The previous wait(uart_tx_o==0) version may sample one bit late.
    // ------------------------------------------------------------
    task automatic pc_uart_recv_byte;
        output [7:0] data;
        integer i;
        begin
            data = 8'd0;

            // Wait exact falling edge of start bit.
            @(negedge uart_tx_o);

            // Move to middle of start bit.
            repeat (BIT_CYCLES / 2) @(posedge clk);

            if (uart_tx_o !== 1'b0) begin
                $display("ERROR: UART start bit not stable low");
                error_count = error_count + 1;
            end

            // Move to middle of bit0.
            repeat (BIT_CYCLES) @(posedge clk);

            for (i = 0; i < 8; i = i + 1) begin
                data[i] = uart_tx_o;
                repeat (BIT_CYCLES) @(posedge clk);
            end

            // Now at middle of stop bit.
            if (uart_tx_o !== 1'b1) begin
                $display("ERROR: UART stop bit not high, byte=%h", data);
                error_count = error_count + 1;
            end

            // Finish stop bit.
            repeat (BIT_CYCLES / 2) @(posedge clk);
        end
    endtask

    task automatic pc_send_cmd_raw;
        input [63:0] cmd;
        integer i;
        reg [7:0] b;
        begin
            // big-endian: send [63:56] first
            for (i = 7; i >= 0; i = i - 1) begin
                b = cmd[i*8 +: 8];
                pc_uart_send_byte(b);
            end
        end
    endtask

    task automatic pc_send_cmd_expect_ack;
        input [63:0] cmd;
        reg [7:0] ack;
        begin
            pc_send_cmd_raw(cmd);
            pc_uart_recv_byte(ack);

            if (ack !== ACK_OK) begin
                $display("ERROR: expected ACK_OK=A5, got %h", ack);
                error_count = error_count + 1;
            end else begin
                $display("PASS : ACK_OK received");
            end
        end
    endtask

    task automatic pc_read_snapshot;
        output [N_SPIN-1:0] snapshot;
        reg [7:0] ack;
        reg [7:0] hdr;
        reg [7:0] len;
        reg [7:0] data_byte;
        integer i;
        integer bit_idx;
        begin
            snapshot = {N_SPIN{1'b0}};

            pc_send_cmd_raw(make_ctrl_cmd(OP_SNAPSHOT_READ));

            pc_uart_recv_byte(ack);
            if (ack !== ACK_OK) begin
                $display("ERROR: snapshot ACK expected A5, got %h", ack);
                error_count = error_count + 1;
            end else begin
                $display("PASS : snapshot ACK_OK received");
            end

            pc_uart_recv_byte(hdr);
            if (hdr !== SNAP_HDR) begin
                $display("ERROR: snapshot header expected 53, got %h", hdr);
                error_count = error_count + 1;
            end else begin
                $display("PASS : snapshot header received");
            end

            pc_uart_recv_byte(len);
            if (len < ((N_SPIN + 7) / 8)) begin
                $display("ERROR: snapshot length too small: %0d", len);
                error_count = error_count + 1;
            end else begin
                $display("PASS : snapshot length = %0d bytes", len);
            end

            for (i = 0; i < len; i = i + 1) begin
                pc_uart_recv_byte(data_byte);

                for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                    if ((i*8 + bit_idx) < N_SPIN) begin
                        snapshot[i*8 + bit_idx] = data_byte[bit_idx];
                    end
                end
            end
        end
    endtask

    task automatic configure_nodes_by_uart;
        input [31:0] scenario;
        reg init_spin;
        reg clamp_en;
        reg clamp_spin;
        reg bias_sign;
        reg [3:0] bias_prob4;
        reg [31:0] seed;
        reg [63:0] cmd;
        integer cell_idx;
        begin
            for (r = 0; r < ROWS; r = r + 1) begin
                for (c = 0; c < COLS; c = c + 1) begin

                    cell_idx = idx(r, c);

                    clamp_en   = 1'b0;
                    clamp_spin = 1'b0;
                    bias_sign  = 1'b1;
                    bias_prob4 = 4'hF;
                    seed       = 32'h1234_5600 + (scenario * 32) + cell_idx;

                    if (((scenario + cell_idx) % 2) == 0) begin
                        init_spin = 1'b0;
                    end else begin
                        init_spin = 1'b1;
                    end

                    case (scenario)
                        0: begin
                            case (cell_idx)
                                0: begin clamp_en = 1'b1; clamp_spin = 1'b1; bias_prob4 = 4'h0; end
                                1: begin bias_sign = 1'b0; end
                                2: begin bias_sign = 1'b1; end
                                3: begin clamp_en = 1'b1; clamp_spin = 1'b0; bias_prob4 = 4'h0; end
                                4: begin bias_sign = 1'b0; end
                                5: begin clamp_en = 1'b1; clamp_spin = 1'b1; bias_prob4 = 4'h0; end
                                6: begin bias_sign = 1'b1; end
                                7: begin bias_sign = 1'b0; end
                                8: begin clamp_en = 1'b1; clamp_spin = 1'b0; bias_prob4 = 4'h0; end
                                default: begin bias_prob4 = 4'h0; end
                            endcase
                        end

                        1: begin
                            case (cell_idx)
                                0: begin clamp_en = 1'b1; clamp_spin = 1'b0; bias_prob4 = 4'h0; end
                                1: begin bias_sign = 1'b1; end
                                2: begin bias_sign = 1'b0; end
                                3: begin clamp_en = 1'b1; clamp_spin = 1'b1; bias_prob4 = 4'h0; end
                                4: begin bias_sign = 1'b1; end
                                5: begin bias_sign = 1'b0; end
                                6: begin clamp_en = 1'b1; clamp_spin = 1'b1; bias_prob4 = 4'h0; end
                                7: begin clamp_en = 1'b1; clamp_spin = 1'b0; bias_prob4 = 4'h0; end
                                8: begin bias_sign = 1'b0; end
                                default: begin bias_prob4 = 4'h0; end
                            endcase
                        end

                        default: begin
                            bias_prob4 = 4'h0;
                        end
                    endcase

                    cmd = make_node_cmd(
                        r[4:0],
                        c[4:0],
                        seed,
                        init_spin,
                        clamp_en,
                        clamp_spin,
                        bias_sign,
                        bias_prob4
                    );
                    pc_send_cmd_expect_ack(cmd);

                end
            end
        end
    endtask

    task automatic configure_edges_by_uart;
        reg [63:0] cmd;
        begin
            // Bias-only test: all graph edges are written invalid.
            // This verifies that the center p-bit is driven by its node bias,
            // not by any neighbor contribution.

            // H edges
            for (r = 0; r < ROWS; r = r + 1) begin
                for (c = 0; c < COLS-1; c = c + 1) begin
                    cmd = make_edge_cmd(EDGE_H, r[4:0], c[4:0], 4'h0, 1'b1, 1'b0);
                    pc_send_cmd_expect_ack(cmd);
                end
            end

            // V edges
            for (r = 0; r < ROWS-1; r = r + 1) begin
                for (c = 0; c < COLS; c = c + 1) begin
                    cmd = make_edge_cmd(EDGE_V, r[4:0], c[4:0], 4'h0, 1'b1, 1'b0);
                    pc_send_cmd_expect_ack(cmd);
                end
            end

            // DSE edges
            for (r = 0; r < ROWS-1; r = r + 1) begin
                for (c = 0; c < COLS-1; c = c + 1) begin
                    cmd = make_edge_cmd(EDGE_DSE, r[4:0], c[4:0], 4'h0, 1'b1, 1'b0);
                    pc_send_cmd_expect_ack(cmd);
                end
            end

            // DSW edges, c starts at 1
            for (r = 0; r < ROWS-1; r = r + 1) begin
                for (c = 1; c < COLS; c = c + 1) begin
                    cmd = make_edge_cmd(EDGE_DSW, r[4:0], c[4:0], 4'h0, 1'b1, 1'b0);
                    pc_send_cmd_expect_ack(cmd);
                end
            end
        end
    endtask

    task automatic check_snapshot_expected;
        input [N_SPIN-1:0] snapshot;
        input [N_SPIN-1:0] expected;
        input [31:0] scenario;
        integer i;
        begin
            for (i = 0; i < N_SPIN; i = i + 1) begin
                if (snapshot[i] !== expected[i]) begin
                    $display("ERROR: snapshot bit %0d expected %b, got %b",
                             i, expected[i], snapshot[i]);
                    error_count = error_count + 1;
                end
            end

            if (snapshot === expected) begin
                $display("PASS : scenario %0d snapshot matches expected pattern %b",
                         scenario, expected);
            end
        end
    endtask

    task automatic run_and_check_scenario;
        input [31:0] scenario;
        reg [N_SPIN-1:0] expected;
        begin
            expected = expected_snapshot(scenario);

            $display("");
            $display("PC SEND: RUN_START scenario %0d", scenario);
            pc_send_cmd_expect_ack(make_ctrl_cmd(OP_RUN_START));

            $display("WAIT FPGA RUN DONE scenario %0d", scenario);
            wait (run_done_o == 1'b1);
            repeat (20) @(posedge clk);

            if (spin_flat_o !== expected) begin
                $display("ERROR: spin_flat_o scenario %0d expected %b, got %b",
                         scenario, expected, spin_flat_o);
                error_count = error_count + 1;
            end else begin
                $display("PASS : spin_flat_o scenario %0d matches expected %b",
                         scenario, expected);
            end

            $display("");
            $display("PC SEND: SNAPSHOT_READ scenario %0d", scenario);
            pc_read_snapshot(snapshot);

            $display("snapshot scenario %0d = %b", scenario, snapshot);
            check_snapshot_expected(snapshot, expected, scenario);
        end
    endtask

    // ------------------------------------------------------------
    // Main
    // ------------------------------------------------------------

    reg [N_SPIN-1:0] snapshot;

    initial begin
        error_count = 0;

        uart_rx_i = 1'b1;
        rst_n = 1'b0;

        $display("=================================================");
        $display("Start tb_pbit_fpga_top_uart_run_3x3");
        $display("=================================================");

        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        repeat (20) @(posedge clk);

        $display("");
        $display("PC CONFIG: nodes scenario 0");
        configure_nodes_by_uart(0);

        $display("");
        $display("PC CONFIG: edges");
        configure_edges_by_uart();

        $display("");
        $display("PC SEND: CONFIG_DONE");
        pc_send_cmd_expect_ack(make_ctrl_cmd(OP_CONFIG_DONE));

        repeat (20) @(posedge clk);

        if (cfg_done_o !== 1'b1) begin
            $display("ERROR: cfg_done_o should be sticky 1 after CONFIG_DONE");
            error_count = error_count + 1;
        end else begin
            $display("PASS : cfg_done_o sticky high");
        end

        run_and_check_scenario(0);

        $display("");
        $display("PC RECONFIG: nodes scenario 1 after first run");
        configure_nodes_by_uart(1);

        run_and_check_scenario(1);

        $display("");
        $display("=================================================");
        if (error_count == 0) begin
            $display("tb_pbit_fpga_top_uart_run_3x3 PASS");
        end else begin
            $display("tb_pbit_fpga_top_uart_run_3x3 FAIL, error_count=%0d", error_count);
        end
        $display("=================================================");

        $finish;
    end

endmodule
