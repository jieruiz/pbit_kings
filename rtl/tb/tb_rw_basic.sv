`ifndef TB_RW_BASIC
`define TB_RW_BASIC
import pbit_pkg::*;

module tb_rw_basic;
    localparam int unsigned CLK_PERIOD_NS = 1_000_000_000 / CLK_FREQ_HZ;
    localparam int unsigned UART_BIT_TIME_NS = 1_000_000_000 / BAUD_RATE;

    localparam logic [7:0] OP_WRITE = 8'h01;
    localparam logic [7:0] OP_READ  = 8'h02;

    typedef enum logic [7:0] {
        ST_OK       = 8'h00,
        ST_BAD      = 8'h01,
        ST_REG_ERR  = 8'h02,
        ST_BUSY     = 8'h03
    } status_e;

    logic clk;
    logic rst_n;
    logic uart_rx_i;
    logic uart_tx_o;
    int unsigned error_count;

    pbit_top u_pbit_top (
        .clk       (clk),
        .rst_n     (rst_n),
        .uart_rx_i (uart_rx_i),
        .uart_tx_o (uart_tx_o)
    );

    initial begin
        clk = 1'b1;
        forever #(CLK_PERIOD_NS / 2) clk = ~clk;
    end

    function automatic logic [31:0] pack_node_target(
        input logic [TARGET_MODE_WIDTH-1:0]     mode,
        input logic [NODE_TARGET_ROW_WIDTH-1:0] row,
        input logic [NODE_TARGET_COL_WIDTH-1:0] col
    );
        pack_node_target = '0;
        pack_node_target[TARGET_MODE_MSB:TARGET_MODE_LSB] = mode;
        pack_node_target[NODE_TARGET_ROW_MSB:NODE_TARGET_ROW_LSB] = row;
        pack_node_target[NODE_TARGET_COL_MSB:NODE_TARGET_COL_LSB] = col;
    endfunction

    function automatic logic [31:0] pack_node_cfg(
        input logic init_valid,
        input logic seed_valid,
        input logic clamp_valid,
        input logic bias_valid,
        input logic init_spin,
        input logic clamp_en,
        input logic clamp_spin,
        input logic bias_sign,
        input logic [NODE_CFG_BIAS_PROB_WIDTH-1:0] bias_prob
    );
        pack_node_cfg = '0;
        pack_node_cfg[INIT_VALID_MSB:INIT_VALID_LSB] = init_valid;
        pack_node_cfg[SEED_VALID_MSB:SEED_VALID_LSB] = seed_valid;
        pack_node_cfg[CLAMP_VALID_MSB:CLAMP_VALID_LSB] = clamp_valid;
        pack_node_cfg[BIAS_VALID_MSB:BIAS_VALID_LSB] = bias_valid;
        pack_node_cfg[NODE_CFG_INIT_SPIN_MSB:NODE_CFG_INIT_SPIN_LSB] = init_spin;
        pack_node_cfg[NODE_CFG_CLAMP_EN_MSB:NODE_CFG_CLAMP_EN_LSB] = clamp_en;
        pack_node_cfg[NODE_CFG_CLAMP_SPIN_MSB:NODE_CFG_CLAMP_SPIN_LSB] = clamp_spin;
        pack_node_cfg[NODE_CFG_BIAS_SIGN_MSB:NODE_CFG_BIAS_SIGN_LSB] = bias_sign;
        pack_node_cfg[NODE_CFG_BIAS_PROB_MSB:NODE_CFG_BIAS_PROB_LSB] = bias_prob;
    endfunction

    function automatic logic [NODE_CFG_W-1:0] expected_node_rdata_cfg(
        input logic current_spin,
        input logic clamp_en,
        input logic clamp_spin,
        input logic bias_sign,
        input logic [NODE_CFG_BIAS_PROB_WIDTH-1:0] bias_prob
    );
        expected_node_rdata_cfg = {bias_prob, bias_sign, clamp_spin, clamp_en, current_spin};
    endfunction

    function automatic logic [31:0] pack_node_cmd(
        input logic apply_cfg,
        input logic load_cfg,
        input logic clear_scope_en,
        input logic clear_local_all,
        input logic readback_node
    );
        pack_node_cmd = '0;
        pack_node_cmd[APPLY_CFG_MSB:APPLY_CFG_LSB] = apply_cfg;
        pack_node_cmd[LOAD_CFG_MSB:LOAD_CFG_LSB] = load_cfg;
        pack_node_cmd[CLEAR_SCOPE_EN_MSB:CLEAR_SCOPE_EN_LSB] = clear_scope_en;
        pack_node_cmd[CLEAR_LOCAL_ALL_MSB:CLEAR_LOCAL_ALL_LSB] = clear_local_all;
        pack_node_cmd[READBACK_NODE_MSB:READBACK_NODE_LSB] = readback_node;
    endfunction

    function automatic logic [31:0] pack_edge_target(
        input logic [EDGE_TYPE_WIDTH-1:0]       edge_type,
        input logic [EDGE_TARGET_ROW_WIDTH-1:0] row,
        input logic [EDGE_TARGET_COL_WIDTH-1:0] col
    );
        pack_edge_target = '0;
        pack_edge_target[EDGE_TYPE_MSB:EDGE_TYPE_LSB] = edge_type;
        pack_edge_target[EDGE_TARGET_ROW_MSB:EDGE_TARGET_ROW_LSB] = row;
        pack_edge_target[EDGE_TARGET_COL_MSB:EDGE_TARGET_COL_LSB] = col;
    endfunction

    function automatic logic [31:0] pack_edge_cfg(
        input logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] prob,
        input logic sign,
        input logic valid
    );
        pack_edge_cfg = '0;
        pack_edge_cfg[EDGE_CFG_EDGE_VALID_MSB:EDGE_CFG_EDGE_VALID_LSB] = valid;
        pack_edge_cfg[EDGE_CFG_EDGE_SIGN_MSB:EDGE_CFG_EDGE_SIGN_LSB] = sign;
        pack_edge_cfg[EDGE_CFG_EDGE_PROB_MSB:EDGE_CFG_EDGE_PROB_LSB] = prob;
    endfunction

    function automatic logic [31:0] pack_edge_cmd(
        input logic apply_edge,
        input logic clear_edge,
        input logic readback_edge
    );
        pack_edge_cmd = '0;
        pack_edge_cmd[APPLY_EDGE_MSB:APPLY_EDGE_LSB] = apply_edge;
        pack_edge_cmd[CLEAR_EDGE_MSB:CLEAR_EDGE_LSB] = clear_edge;
        pack_edge_cmd[READBACK_EDGE_MSB:READBACK_EDGE_LSB] = readback_edge;
    endfunction

    task automatic report_mismatch(
        input string tag,
        input logic [31:0] actual,
        input logic [31:0] expected
    );
        if (actual !== expected) begin
            error_count++;
            $error("[%s] actual=0x%08h expected=0x%08h time=%0t", tag, actual, expected, $time);
        end
    endtask

    task automatic expect_status_ok(
        input string tag,
        input status_e status
    );
        if (status !== ST_OK) begin
            error_count++;
            $error("[%s] status=0x%02h expected ST_OK time=%0t", tag, status, $time);
        end
    endtask

    task automatic uart_send_byte(
        input logic [7:0] tx_data
    );
        uart_rx_i = 1'b0;
        #(UART_BIT_TIME_NS);

        for (int idx = 0; idx < 8; idx++) begin
            uart_rx_i = tx_data[idx];
            #(UART_BIT_TIME_NS);
        end

        uart_rx_i = 1'b1;
        #(UART_BIT_TIME_NS);
    endtask

    task automatic uart_receive_byte(
        output logic [7:0] rx_data
    );
        @(negedge uart_tx_o);
        #(UART_BIT_TIME_NS / 2);
        if (uart_tx_o !== 1'b0) begin
            error_count++;
            $error("[UART_TX] invalid start bit at time %0t", $time);
        end

        for (int idx = 0; idx < 8; idx++) begin
            #(UART_BIT_TIME_NS);
            rx_data[idx] = uart_tx_o;
        end

        #(UART_BIT_TIME_NS);
        if (uart_tx_o !== 1'b1) begin
            error_count++;
            $error("[UART_TX] invalid stop bit at time %0t", $time);
        end
    endtask

    task automatic uart_req(
        input  logic [7:0]  op,
        input  logic [15:0] addr,
        input  logic [31:0] wdata,
        output status_e     status,
        output logic [15:0] raddr,
        output logic [31:0] rdata
    );
        logic [7:0] rx_data;

        uart_send_byte(op);
        uart_send_byte(addr[15:8]);
        uart_send_byte(addr[7:0]);
        uart_send_byte(wdata[31:24]);
        uart_send_byte(wdata[23:16]);
        uart_send_byte(wdata[15:8]);
        uart_send_byte(wdata[7:0]);

        for (int idx = 0; idx < 7; idx++) begin
            uart_receive_byte(rx_data);
            case (idx)
                0: status = status_e'(rx_data);
                1: raddr[15:8] = rx_data;
                2: raddr[7:0] = rx_data;
                3: rdata[31:24] = rx_data;
                4: rdata[23:16] = rx_data;
                5: rdata[15:8] = rx_data;
                6: rdata[7:0] = rx_data;
                default: begin end
            endcase
        end

        #(UART_BIT_TIME_NS);
    endtask

    task automatic write_reg(
        input logic [15:0] addr,
        input logic [31:0] data,
        input string tag
    );
        status_e status;
        logic [15:0] raddr;
        logic [31:0] rdata;

        uart_req(OP_WRITE, addr, data, status, raddr, rdata);
        expect_status_ok({tag, " write status"}, status);
        report_mismatch({tag, " write addr"}, {16'd0, raddr}, {16'd0, addr});
        report_mismatch({tag, " write rdata"}, rdata, 32'd0);
    endtask

    task automatic read_reg(
        input  logic [15:0] addr,
        output logic [31:0] data,
        input  string tag
    );
        status_e status;
        logic [15:0] raddr;

        uart_req(OP_READ, addr, 32'd0, status, raddr, data);
        expect_status_ok({tag, " read status"}, status);
        report_mismatch({tag, " read addr"}, {16'd0, raddr}, {16'd0, addr});
    endtask

    task automatic read_expect(
        input logic [15:0] addr,
        input logic [31:0] expected,
        input string tag
    );
        logic [31:0] data;

        read_reg(addr, data, tag);
        report_mismatch(tag, data, expected);
    endtask

    task automatic check_edge_rw(
        input logic [EDGE_TYPE_WIDTH-1:0] edge_type,
        input logic [EDGE_TARGET_ROW_WIDTH-1:0] row,
        input logic [EDGE_TARGET_COL_WIDTH-1:0] col,
        input logic [EDGE_CFG_EDGE_PROB_WIDTH-1:0] prob,
        input logic sign,
        input string tag
    );
        logic [31:0] edge_target_word;
        logic [31:0] edge_cfg_word;

        edge_target_word = pack_edge_target(edge_type, row, col);
        edge_cfg_word = pack_edge_cfg(prob, sign, 1'b1);

        write_reg(A_EDGE_TARGET, edge_target_word, {tag, " edge target"});
        read_expect(A_EDGE_TARGET, edge_target_word, {tag, " edge target staging"});
        write_reg(A_EDGE_CFG, edge_cfg_word, {tag, " edge cfg"});
        read_expect(A_EDGE_CFG, edge_cfg_word, {tag, " edge cfg staging"});

        write_reg(A_EDGE_CMD, pack_edge_cmd(1'b1, 1'b0, 1'b0), {tag, " edge apply"});
        repeat (4) @(posedge clk);
        write_reg(A_EDGE_CMD, pack_edge_cmd(1'b0, 1'b0, 1'b1), {tag, " edge readback trigger"});
        repeat (4) @(posedge clk);
        read_expect(A_EDGE_RDATA, edge_cfg_word, {tag, " edge applied readback"});
    endtask

    initial begin
        logic [31:0] node_target_word;
        logic [31:0] node_cfg_word;
        logic [31:0] node_seed_word;
        logic [31:0] node_rdata_expected;

        error_count = 0;
        uart_rx_i = 1'b1;
        rst_n = 1'b0;

        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        repeat (20) @(posedge clk);

        read_expect(A_ARRAY_PARAM,
                    {N_SPIN_WIDTH'(N_SPIN), COLS_WIDTH'(COLS), ROWS_WIDTH'(ROWS)},
                    "array param");

        node_target_word = pack_node_target(TARGET_MODE_LOCAL, 6'd5, 6'd6);
        node_cfg_word = pack_node_cfg(.init_valid(1'b1),
                                      .seed_valid(1'b1),
                                      .clamp_valid(1'b1),
                                      .bias_valid(1'b1),
                                      .init_spin(1'b1),
                                      .clamp_en(1'b1),
                                      .clamp_spin(1'b0),
                                      .bias_sign(1'b1),
                                      .bias_prob(7'h35));
        node_seed_word = 32'h1234_abcd;
        // NODE_RDATA_CFG bit0 reports current spin_q, not the original INIT_SPIN field.
        // With clamp enabled and clamp_spin=0, the applied node readback spin is 0.
        node_rdata_expected = {{(32-NODE_CFG_W){1'b0}},
                               expected_node_rdata_cfg(.current_spin(1'b0),
                                                       .clamp_en(1'b1),
                                                       .clamp_spin(1'b0),
                                                       .bias_sign(1'b1),
                                                       .bias_prob(7'h35))};

        write_reg(A_NODE_TARGET, node_target_word, "node target");
        read_expect(A_NODE_TARGET, node_target_word, "node target staging");
        write_reg(A_NODE_CFG, node_cfg_word, "node cfg");
        read_expect(A_NODE_CFG, node_cfg_word, "node cfg staging");
        write_reg(A_NODE_SEED, node_seed_word, "node seed");
        read_expect(A_NODE_SEED, node_seed_word, "node seed staging");

        write_reg(A_NODE_CMD, pack_node_cmd(1'b1, 1'b0, 1'b0, 1'b0, 1'b0), "node apply");
        repeat (4) @(posedge clk);
        write_reg(A_NODE_CMD, pack_node_cmd(1'b0, 1'b0, 1'b0, 1'b0, 1'b1), "node readback trigger");
        repeat (4) @(posedge clk);
        read_expect(A_NODE_RDATA_CFG, node_rdata_expected, "node applied cfg readback");
        read_expect(A_NODE_RDATA_SEED, node_seed_word, "node applied seed readback");

        check_edge_rw(EDGE_TYPE_EDGE_H,   6'd3, 6'd4, 7'h21, 1'b1, "H");
        check_edge_rw(EDGE_TYPE_EDGE_V,   6'd4, 6'd5, 7'h22, 1'b0, "V");
        check_edge_rw(EDGE_TYPE_EDGE_DSE, 6'd5, 6'd6, 7'h23, 1'b1, "DSE");
        check_edge_rw(EDGE_TYPE_EDGE_DSW, 6'd6, 6'd7, 7'h24, 1'b0, "DSW");

        if (error_count == 0) begin
            $display("[TB_RW_BASIC] PASS");
        end else begin
            $fatal(1, "[TB_RW_BASIC] FAIL error_count=%0d", error_count);
        end

        $finish;
    end
endmodule
`endif
