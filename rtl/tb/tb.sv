`ifndef TB
`define TB
`timescale 1ns / 1ps
import pbit_pkg::*;
module tb;
    localparam realtime CLK_PERIOD = 1s / CLK_FREQ_HZ;
    localparam realtime IDEAL_UART_BIT_TIME = 1s / BAUD_RATE;
    localparam int unsigned UART_CLKS_PER_BIT = $rtoi(IDEAL_UART_BIT_TIME / CLK_PERIOD);
    localparam time UART_BIT_TIME = UART_CLKS_PER_BIT * CLK_PERIOD;
    localparam [7:0] OP_WRITE = 8'h01;
    localparam [7:0] OP_READ  = 8'h02;
    typedef enum logic [7:0] {
        ST_OK       = 8'h00,
        ST_BAD      = 8'h01,
        ST_REG_ERR  = 8'h02,
        ST_BUSY     = 8'h03
    } ST_e;

    logic clk;
    logic rst_n;
    logic uart_rx_i, uart_tx_o;
    logic [7:0] op;
    logic [15:0] waddr, raddr;
    logic [31:0] wdata, rdata;
    ST_e status;
    pbit_top u_pbit_top(
        .clk(clk),
        .rst_n(rst_n),
        .uart_rx_i(uart_rx_i),
        .uart_tx_o(uart_tx_o)
    );

    initial begin
        clk = 1'b1;
        forever begin
            #(CLK_PERIOD/2) clk = ~clk;
        end
    end

    task automatic uart_send_byte(
        input logic [7:0] tx_data
    );
        int idx;
        uart_rx_i = 1'b0;
        #(UART_BIT_TIME);

        for(idx = 0; idx < 8; idx++) begin
            uart_rx_i = tx_data[idx];
            #(UART_BIT_TIME);
        end

        uart_rx_i = 1'b1;
        #(UART_BIT_TIME);

    endtask

    task automatic uart_receive_byte(
        output logic [7:0] rx_data
    );
        int idx;
        @(negedge uart_tx_o);
        #(UART_BIT_TIME / 2.0);
        if(uart_tx_o != 1'b0) begin
            $error("[UART TX] invalid start bit at time %0t", $time);
        end

        for(idx = 0; idx < 8; idx++) begin
            #(UART_BIT_TIME);
            rx_data[idx] = uart_tx_o;
        end

        #(UART_BIT_TIME);
        if(uart_tx_o != 1'b1)begin
             $error("[UART TX] invalid end bit at time %0t", $time);
        end
    endtask  

    task automatic req_send(
        input logic [7:0] op,
        input logic [15:0] waddr,
        input logic [31:0] wdata,
        output ST_e status,
        output logic [15:0] raddr,
        output logic [31:0] rdata
    );
    logic [7:0] rx_data;
    uart_send_byte(op);
    for(int i = 0; i < 2; i++)begin
        uart_send_byte(waddr[(1-i)*8+:8]);
    end
    for(int i = 0; i < 4; i++)begin
        uart_send_byte(wdata[(3-i)*8+:8]);
    end
    for(int i = 0; i < 7; i++)begin
        uart_receive_byte(rx_data);
        case(i)
            0: begin
                if(!$cast(status, rx_data)) begin
                    $error("Illegal status value: %b", rx_data);
                end
            end
            1: raddr[15:8] = rx_data;
            2: raddr[7:0]  = rx_data;
            3: rdata[31:24] = rx_data;
            4: rdata[23:16] = rx_data;
            5: rdata[15:8]  = rx_data;
            6: rdata[7:0]   = rx_data;
        endcase
    end
    $display("status: %s\nraddr: %0h\nrdata: %0b", status.name(), raddr, rdata);
    endtask

    task automatic req_global_ctrl(bit error_clear = 1'b0, bit run_done_clear = 1'b0, bit snapshot_latch = 1'b0, 
                         bit run_start = 1'b0, bit cfg_done_clear = 1'b0, bit cfg_done_set = 1'b0, bit soft_reset = 1'b0);
        op = OP_WRITE;
        waddr = A_GLOBAL_CTRL;
        wdata = {{(32-ERROR_CLEAR_MSB-1){1'b0}}, error_clear, run_done_clear, snapshot_latch,
                 run_start, cfg_done_clear, cfg_done_set, soft_reset};
        $display("req_global_ctrl send");
        req_send(op, waddr, wdata, status, raddr, rdata);
    endtask

    task automatic req_global_cfg(bit[7:0] op_e = OP_READ, bit[NUM_MAJORITY_WIDTH-1:0] num_majority = 'b0, bit[NUM_SWEEP_WIDTH-1:0] num_sweep = 'b0);
        op = op_e;
        waddr = A_GLOBAL_CFG;
        wdata = {{(32-NUM_MAJORITY_MSB-1){1'b0}}, num_majority, {(NUM_MAJORITY_LSB-NUM_SWEEP_MSB-1){1'b0}}, num_sweep};
        $display("req_global_cfg send");
        req_send(op, waddr, wdata, status, raddr, rdata);
    endtask

    task automatic req_global_status();
        op = OP_READ;
        waddr = A_GLOBAL_STATUS;
        wdata = 'd0;
        $display("req_global_status send");
        req_send(op, waddr, wdata, status, raddr, rdata);
    endtask

    task automatic req_array_param();
        op = OP_READ;
        waddr = A_ARRAY_PARAM;
        wdata = 'd0;
        $display("req_array_param send");
        req_send(op, waddr, wdata, status, raddr, rdata);
    endtask

    task automatic req_error_status(bit[7:0] op_e = OP_READ,
                                    bit snap_addr_oor = 1'b0, bit uart_overflow = 1'b0, bit uart_frame_err = 1'b0, bit edge_type_err = 1'b0,
                                    bit edge_col_oor = 1'b0, bit edge_row_oor = 1'b0, bit node_col_oor = 1'b0, bit node_row_orr = 1'b0,
                                    bit node_target_mode_err = 1'b0, bit run_when_busy = 1'b0, bit run_without_cfg_done = 1'b0, bit edge_cfg_while_run = 1'b0,
                                    bit node_cfg_while_run = 1'b0, bit rd_to_wo = 1'b0, bit wr_to_ro = 1'b0, bit addr_err = 1'b0);
        op = op_e;
        waddr = A_ERROR_STATUS;
        wdata = {{(32-SNAP_ADDR_OOR_MSB-1){1'b0}}, {snap_addr_oor, uart_overflow, uart_frame_err, edge_type_err,
                                                    edge_col_oor, edge_row_oor, node_col_oor, node_row_orr,
                                                    node_target_mode_err, run_when_busy, run_without_cfg_done, edge_cfg_while_run,
                                                    node_cfg_while_run, rd_to_wo, wr_to_ro, addr_err}};
        $display("req_error_status send");
        req_send(op, waddr, wdata, status, raddr, rdata);
    endtask

    task automatic req_snapshot_addr(bit[7:0] op_e = OP_READ, bit[2:0] snapshot_addr = 1'b0);
        op = op_e;
        waddr = A_SNAPSHOT_ADDR;
        wdata = {{(32-SNAPSHOT_ADDR_MSB-1){1'b0}}, snapshot_addr};
        $display("req_snapshot_addr send");
        req_send(op, waddr, wdata, status, raddr, rdata);
    endtask

    task automatic req_i0_level(bit[3:0] idx = 'd0, bit[7:0] op_e = OP_READ, bit[I0_LEVEL3_WIDTH-1:0] i0_level_3 = 'd0, bit[I0_LEVEL2_WIDTH-1:0] i0_level_2 = 'd0, bit[I0_LEVEL1_WIDTH-1:0] i0_level_1 = 'd0, bit[I0_LEVEL0_WIDTH-1:0] i0_level_0 = 'd0);
        op = op_e;
        case(idx)
            0: waddr = A_I0_LEVEL0;
            1: waddr = A_I0_LEVEL1;
            2: waddr = A_I0_LEVEL2;
            3: waddr = A_I0_LEVEL3;
            4: waddr = A_I0_LEVEL4;
            5: waddr = A_I0_LEVEL5;
            6: waddr = A_I0_LEVEL6;
            7: waddr = A_I0_LEVEL7;
            8: waddr = A_I0_LEVEL8;
            9: waddr = A_I0_LEVEL9;
            10: waddr = A_I0_LEVEL10;
            11: waddr = A_I0_LEVEL11;
            12: waddr = A_I0_LEVEL12;
            13: waddr = A_I0_LEVEL13;
            14: waddr = A_I0_LEVEL14;
            15: waddr = A_I0_LEVEL15;
        endcase
        wdata = {{(32-I0_LEVEL3_MSB-1){1'b0}}, i0_level_3, {(I0_LEVEL3_LSB-I0_LEVEL2_MSB-1){1'b0}}, i0_level_2, {(I0_LEVEL2_LSB-I0_LEVEL1_MSB-1){1'b0}}, i0_level_1, {(I0_LEVEL1_LSB-I0_LEVEL0_MSB-1){1'b0}}, i0_level_0};
        $display("req_i0_level%0d send", idx);
        req_send(op, waddr, wdata, status, raddr, rdata);
    endtask

    task automatic req_sweep_interval(bit[4:0] idx = 'd0, bit[7:0] op_e = OP_READ, bit[SWEEP_INTERVAL1_WIDTH-1:0] sweep_interval1 = 'd0, bit[SWEEP_INTERVAL0_WIDTH-1:0] sweep_interval0 = 'd0);
        op = op_e;
        case(idx)
            0: waddr = A_SWEEP_INTERVAL0;
            1: waddr = A_SWEEP_INTERVAL1;
            2: waddr = A_SWEEP_INTERVAL2;
            3: waddr = A_SWEEP_INTERVAL3;
            4: waddr = A_SWEEP_INTERVAL4;
            5: waddr = A_SWEEP_INTERVAL5;
            6: waddr = A_SWEEP_INTERVAL6;
            7: waddr = A_SWEEP_INTERVAL7;
            8: waddr = A_SWEEP_INTERVAL8;
            9: waddr = A_SWEEP_INTERVAL9;
            10: waddr = A_SWEEP_INTERVAL10;
            11: waddr = A_SWEEP_INTERVAL11;
            12: waddr = A_SWEEP_INTERVAL12;
            13: waddr = A_SWEEP_INTERVAL13;
            14: waddr = A_SWEEP_INTERVAL14;
            15: waddr = A_SWEEP_INTERVAL15;
            16: waddr = A_SWEEP_INTERVAL16;
            17: waddr = A_SWEEP_INTERVAL17;
            18: waddr = A_SWEEP_INTERVAL18;
            19: waddr = A_SWEEP_INTERVAL19;
            20: waddr = A_SWEEP_INTERVAL20;
            21: waddr = A_SWEEP_INTERVAL21;
            22: waddr = A_SWEEP_INTERVAL22;
            23: waddr = A_SWEEP_INTERVAL23;
            24: waddr = A_SWEEP_INTERVAL24;
            25: waddr = A_SWEEP_INTERVAL25;
            26: waddr = A_SWEEP_INTERVAL26;
            27: waddr = A_SWEEP_INTERVAL27;
            28: waddr = A_SWEEP_INTERVAL28;
            29: waddr = A_SWEEP_INTERVAL29;
            30: waddr = A_SWEEP_INTERVAL30;
            31: waddr = A_SWEEP_INTERVAL31;
        endcase
        wdata = {{(32-SWEEP_INTERVAL1_MSB-1){1'b0}}, sweep_interval1, {(SWEEP_INTERVAL1_LSB-SWEEP_INTERVAL0_MSB-1){1'b0}}, sweep_interval0};
        $display("req_sweep_interval%0d send", idx);
        req_send(op, waddr, wdata, status, raddr, rdata);
    endtask

    task automatic req_node_target(bit[7:0] op_e = OP_READ, bit[NODE_TARGET_COL_WIDTH-1:0] col = 'd0, bit[NODE_TARGET_ROW_WIDTH-1:0] row = 'd0, bit[TARGET_MODE_WIDTH-1:0] target_mode = 'd0);
        op = op_e;
        waddr = A_NODE_TARGET;
        wdata = {{(32-NODE_TARGET_COL_MSB-1){1'b0}}, col, {(NODE_TARGET_COL_LSB-NODE_TARGET_ROW_MSB-1){1'b0}}, row, {(NODE_TARGET_ROW_LSB-TARGET_MODE_MSB-1){1'b0}}, target_mode};
        $display("req_node_target send");
        req_send(op, waddr, wdata, status, raddr, rdata);
    endtask

    task automatic req_node_cfg(bit[7:0] op_e = OP_READ, bit[NODE_CFG_BIAS_PROB_WIDTH-1:0] bias_prob = 'd0, bit bias_sign = 'd0, bit clamp_spin = 'd0, bit clamp_en = 'd0, bit init_spin = 'd0,
                                bit bias_valid = 'd0, bit clamp_valid = 'd0, bit seed_valid = 'd0, bit init_valid = 'd0);
        op = op_e;
        waddr = A_NODE_CFG;
        wdata = {{(32-NODE_CFG_BIAS_PROB_MSB-1){1'b0}}, bias_prob, bias_sign, clamp_spin, clamp_en, init_spin, {(NODE_CFG_INIT_SPIN_LSB-BIAS_VALID_MSB-1){1'b0}},
                 bias_valid, clamp_valid, seed_valid, init_valid};
        $display("req_node_cfg send");
        req_send(op, waddr, wdata, status, raddr, rdata);
    endtask

    task automatic req_node_seed(bit[7:0] op_e = OP_READ, bit[NODE_SEED_WIDTH-1:0] node_seed = 'd0);
        op = op_e;
        waddr = A_NODE_SEED;
        wdata = node_seed;
        $display("req_node_seed send");
        req_send(op, waddr, wdata, status, raddr, rdata);
    endtask

    task automatic req_node_cmd(bit readback_node = 'd0, bit clear_local_all = 'd0, bit clear_scope_en = 'd0, bit load_cfg = 'd0, bit apply_cfg = 'd0);
        op = OP_WRITE;
        waddr = A_NODE_CMD;
        wdata = {{(32-READBACK_NODE_MSB-1){1'b0}}, readback_node, clear_local_all, clear_scope_en, load_cfg, apply_cfg};
        $display("req_node_cmd send");
        req_send(op, waddr, wdata, status, raddr, rdata);
    endtask

    task automatic req_node_rdata_cfg();
        op = OP_READ;
        waddr = A_NODE_RDATA_CFG;
        wdata = 'd0;
        $display("req_node_rdata_cfg send");
        req_send(op, waddr, wdata, status, raddr, rdata);
    endtask

    task automatic req_node_rdata_seed();
        op = OP_READ;
        waddr = A_NODE_RDATA_SEED;
        wdata = 'd0;
        $display("req_node_rdata_seed send");
        req_send(op, waddr, wdata, status, raddr, rdata);
    endtask

    task automatic req_edge_target(bit[7:0] op_e = OP_READ, bit[EDGE_TARGET_COL_WIDTH-1:0] edge_taget_col = 'd0, bit[EDGE_TARGET_ROW_WIDTH-1:0] edge_target_row = 'd0,
                                   bit[EDGE_TYPE_WIDTH-1:0] edge_type = 'd0);
        op = op_e;
        waddr = A_EDGE_TARGET;
        wdata = {{(32-EDGE_TARGET_COL_MSB-1){1'b0}}, edge_target_col, {(EDGE_TARGET_COL_LSB-EDGE_TARGET_ROW_MSB-1){1'b0}}, edge_target_row,
                 {(EDGE_TARGET_ROW_LSB-EDGE_TYPE_MSB-1){1'b0}}, edge_type};
        $display("req_edge_target send");
        req_send(op, waddr, wdata, status, raddr, rdata);
    endtask

    task automatic req_edge_cfg(bit[7:0] op_e = OP_READ, bit[EDGE_CFG_EDGE_PROB_WIDTH-1:0] edge_prob = 'd0, bit edge_sign = 'd0, bit edge_valid = 'd0);
        op = op_e;
        waddr = A_EDGE_CFG;
        wdata = {{(32-EDGE_CFG_EDGE_PROB_MSB-1){1'b0}}, edge_prob, edge_sign, edge_valid};
        $display("req_edge_cfg send");
        req_send(op, waddr, wdata, status, raddr, rdata);
    endtask

    task automatic req_edge_cmd(bit readback_edge = 'd0, bit clear_edge = 'd0, bit apply_edge = 'd0);
        op = OP_WRITE;
        waddr = A_EDGE_CMD;
        wdata = {{(32-READBACK_EDGE_MSB-1){1'b0}}, readback_edge, clear_edge, apply_edge};
        $display("req_edge_cmd send");
        req_send(op, waddr, wdata, status, raddr, rdata);
    endtask

    task automatic req_edge_rdata();
        op = OP_READ;
        waddr = A_EDGE_RDATA;
        wdata = 'd0;
        $display("req_edge_rdata send");
        req_send(op, waddr, wdata, status, raddr, rdata);
    endtask

    task automatic req_spin_data(bit[$clog2(SPIN_RDATA_REG_NUM)-1:0] idx = 'd0);
        op = OP_READ;
        case(idx)
            0: waddr = A_SPIN_RDATA0;
            1: waddr = A_SPIN_RDATA1;
            2: waddr = A_SPIN_RDATA2;
            3: waddr = A_SPIN_RDATA3;
            4: waddr = A_SPIN_RDATA4;
            5: waddr = A_SPIN_RDATA5;
            6: waddr = A_SPIN_RDATA6;
            7: waddr = A_SPIN_RDATA7;
            8: waddr = A_SPIN_RDATA8;
            9: waddr = A_SPIN_RDATA9;
        endcase
        wdata = 'd0;
        $display("req_spin_data%0d send", idx);
        req_send(op, waddr, wdata, status, raddr, rdata);
    endtask
    
    initial begin
        uart_rx_i = 1'b1;
        rst_n = 1'b0;
        repeat(10) @(posedge clk);
        rst_n = 1'b1;
        repeat(10) @(posedge clk);
        op = OP_WRITE;
        waddr = A_GLOBAL_CFG;
        wdata = {{(32-NUM_MAJORITY_MSB-1){1'b0}}, NUM_MAJORITY_WIDTH'(10), {(NUM_MAJORITY_LSB-NUM_SWEEP_MSB-1){1'b0}}, NUM_SWEEP_WIDTH'(64)};
        req_send(op, waddr, wdata, status, raddr, rdata);
    end
endmodule
`endif