`ifndef DFF_SETS
`define DFF_SETS
module dffr #(
    parameter integer WIDTH = 1,
    parameter [WIDTH-1:0] RESET_VALUE = {WIDTH{1'b0}}
)(
    input  logic                   clk,
    input  logic                   rst_n,
    input  logic [WIDTH-1:0]       d_i,
    output logic [WIDTH-1:0]       q_o
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            q_o <= RESET_VALUE;
        end else begin
            q_o <= d_i;
        end
    end
endmodule

module dffre #(
    parameter integer WIDTH = 1,
    parameter [WIDTH-1:0] RESET_VALUE = {WIDTH{1'b0}}
)(
    input  logic                   clk,
    input  logic                   rst_n,
    input  logic                   en_i,
    input  logic [WIDTH-1:0]       d_i,
    output logic [WIDTH-1:0]       q_o
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            q_o <= RESET_VALUE;
        end else if (en_i) begin
            q_o <= d_i;
        end
    end
endmodule

module dff #(
    parameter integer WIDTH = 1
)(
    input  logic                   clk,
    input  logic [WIDTH-1:0]       d_i,
    output logic [WIDTH-1:0]       q_o
);

    always @(posedge clk) begin
        q_o <= d_i;
    end
endmodule

module dffe #(
    parameter integer WIDTH = 1
)(
    input  logic                   clk,
    input  logic                   en_i,
    input  logic [WIDTH-1:0]       d_i,
    output logic [WIDTH-1:0]       q_o
);

    always @(posedge clk) begin
        if (en_i) begin
            q_o <= d_i;
        end
    end
endmodule

module dffsr #(
    parameter integer WIDTH = 1,
    parameter [WIDTH-1:0] RESET_VALUE = {WIDTH{1'b0}}
)(
    input  logic                   clk,
    input  logic                   rst_n,
    input  logic                   soft_rstn_i,
    input  logic [WIDTH-1:0]       d_i,
    output logic [WIDTH-1:0]       q_o
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            q_o <= RESET_VALUE;
        end else if (!soft_rstn_i) begin
            q_o <= RESET_VALUE;
        end else begin
            q_o <= d_i;
        end
    end
endmodule

module dffsre #(
    parameter integer WIDTH = 1,
    parameter [WIDTH-1:0] RESET_VALUE = {WIDTH{1'b0}}
)(
    input  logic                   clk,
    input  logic                   rst_n,
    input  logic                   soft_rstn_i,
    input  logic                   en_i,
    input  logic [WIDTH-1:0]       d_i,
    output logic [WIDTH-1:0]       q_o
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            q_o <= RESET_VALUE;
        end else if (!soft_rstn_i) begin
            q_o <= RESET_VALUE;
        end else if (en_i) begin
            q_o <= d_i;
        end
    end
endmodule
`endif