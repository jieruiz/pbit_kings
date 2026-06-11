`timescale 1ns / 1ps

module tanh_lut_comb (
    input  wire [3:0]        i0_level_i,
    input  wire signed [4:0] h_i,
    output reg  [15:0]       p_up_thr_o
);

    reg [3:0]  h_abs;
    reg [15:0] pos_thr;

    function [15:0] tanh_pos_thr;
        input [3:0] level;
        input [3:0] h_abs_in;
        begin
            case (level)

                4'd0: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hBB26;
                        4'd2: tanh_pos_thr = 16'hE17B;
                        4'd3: tanh_pos_thr = 16'hF3DB;
                        4'd4: tanh_pos_thr = 16'hFB64;
                        4'd5: tanh_pos_thr = 16'hFE48;
                        4'd6: tanh_pos_thr = 16'hFF5D;
                        4'd7: tanh_pos_thr = 16'hFFC3;
                        4'd8: tanh_pos_thr = 16'hFFE9;
                        4'd9: tanh_pos_thr = 16'hFFF7;
                        default: tanh_pos_thr = 16'hFFF7;
                    endcase
                end

                4'd1: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hE4E3;
                        4'd2: tanh_pos_thr = 16'hFC74;
                        4'd3: tanh_pos_thr = 16'hFF92;
                        4'd4: tanh_pos_thr = 16'hFFF2;
                        4'd5: tanh_pos_thr = 16'hFFFD;
                        4'd6: tanh_pos_thr = 16'hFFFF;
                        4'd7: tanh_pos_thr = 16'hFFFF;
                        4'd8: tanh_pos_thr = 16'hFFFF;
                        4'd9: tanh_pos_thr = 16'hFFFF;
                        default: tanh_pos_thr = 16'hFFFF;
                    endcase
                end

                4'd2: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hF698;
                        4'd2: tanh_pos_thr = 16'hFFA0;
                        4'd3: tanh_pos_thr = 16'hFFFB;
                        4'd4: tanh_pos_thr = 16'hFFFF;
                        4'd5: tanh_pos_thr = 16'hFFFF;
                        4'd6: tanh_pos_thr = 16'hFFFF;
                        4'd7: tanh_pos_thr = 16'hFFFF;
                        4'd8: tanh_pos_thr = 16'hFFFF;
                        4'd9: tanh_pos_thr = 16'hFFFF;
                        default: tanh_pos_thr = 16'hFFFF;
                    endcase
                end

                4'd3: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hFCE4;
                        4'd2: tanh_pos_thr = 16'hFFF5;
                        4'd3: tanh_pos_thr = 16'hFFFF;
                        4'd4: tanh_pos_thr = 16'hFFFF;
                        4'd5: tanh_pos_thr = 16'hFFFF;
                        4'd6: tanh_pos_thr = 16'hFFFF;
                        4'd7: tanh_pos_thr = 16'hFFFF;
                        4'd8: tanh_pos_thr = 16'hFFFF;
                        4'd9: tanh_pos_thr = 16'hFFFF;
                        default: tanh_pos_thr = 16'hFFFF;
                    endcase
                end

                4'd4: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hFEFD;
                        4'd2: tanh_pos_thr = 16'hFFFE;
                        4'd3: tanh_pos_thr = 16'hFFFF;
                        4'd4: tanh_pos_thr = 16'hFFFF;
                        4'd5: tanh_pos_thr = 16'hFFFF;
                        4'd6: tanh_pos_thr = 16'hFFFF;
                        4'd7: tanh_pos_thr = 16'hFFFF;
                        4'd8: tanh_pos_thr = 16'hFFFF;
                        4'd9: tanh_pos_thr = 16'hFFFF;
                        default: tanh_pos_thr = 16'hFFFF;
                    endcase
                end

                4'd5: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hFFAC;
                        4'd2: tanh_pos_thr = 16'hFFFF;
                        4'd3: tanh_pos_thr = 16'hFFFF;
                        4'd4: tanh_pos_thr = 16'hFFFF;
                        4'd5: tanh_pos_thr = 16'hFFFF;
                        4'd6: tanh_pos_thr = 16'hFFFF;
                        4'd7: tanh_pos_thr = 16'hFFFF;
                        4'd8: tanh_pos_thr = 16'hFFFF;
                        4'd9: tanh_pos_thr = 16'hFFFF;
                        default: tanh_pos_thr = 16'hFFFF;
                    endcase
                end

                4'd6: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hFFE4;
                        4'd2: tanh_pos_thr = 16'hFFFF;
                        4'd3: tanh_pos_thr = 16'hFFFF;
                        4'd4: tanh_pos_thr = 16'hFFFF;
                        4'd5: tanh_pos_thr = 16'hFFFF;
                        4'd6: tanh_pos_thr = 16'hFFFF;
                        4'd7: tanh_pos_thr = 16'hFFFF;
                        4'd8: tanh_pos_thr = 16'hFFFF;
                        4'd9: tanh_pos_thr = 16'hFFFF;
                        default: tanh_pos_thr = 16'hFFFF;
                    endcase
                end

                4'd7: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hFFF6;
                        4'd2: tanh_pos_thr = 16'hFFFF;
                        4'd3: tanh_pos_thr = 16'hFFFF;
                        4'd4: tanh_pos_thr = 16'hFFFF;
                        4'd5: tanh_pos_thr = 16'hFFFF;
                        4'd6: tanh_pos_thr = 16'hFFFF;
                        4'd7: tanh_pos_thr = 16'hFFFF;
                        4'd8: tanh_pos_thr = 16'hFFFF;
                        4'd9: tanh_pos_thr = 16'hFFFF;
                        default: tanh_pos_thr = 16'hFFFF;
                    endcase
                end

                4'd8: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hFFFC;
                        4'd2: tanh_pos_thr = 16'hFFFF;
                        4'd3: tanh_pos_thr = 16'hFFFF;
                        4'd4: tanh_pos_thr = 16'hFFFF;
                        4'd5: tanh_pos_thr = 16'hFFFF;
                        4'd6: tanh_pos_thr = 16'hFFFF;
                        4'd7: tanh_pos_thr = 16'hFFFF;
                        4'd8: tanh_pos_thr = 16'hFFFF;
                        4'd9: tanh_pos_thr = 16'hFFFF;
                        default: tanh_pos_thr = 16'hFFFF;
                    endcase
                end

                4'd9: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hFFFE;
                        4'd2: tanh_pos_thr = 16'hFFFF;
                        4'd3: tanh_pos_thr = 16'hFFFF;
                        4'd4: tanh_pos_thr = 16'hFFFF;
                        4'd5: tanh_pos_thr = 16'hFFFF;
                        4'd6: tanh_pos_thr = 16'hFFFF;
                        4'd7: tanh_pos_thr = 16'hFFFF;
                        4'd8: tanh_pos_thr = 16'hFFFF;
                        4'd9: tanh_pos_thr = 16'hFFFF;
                        default: tanh_pos_thr = 16'hFFFF;
                    endcase
                end

                default: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        default: tanh_pos_thr = 16'hFFFF;
                    endcase
                end

            endcase
        end
    endfunction

    always @(*) begin
        // Saturate h_i to [-9, +9].
        if (h_i <= (-5'sd9)) begin
            h_abs = 4'd9;
        end else if (h_i < 5'sd0) begin
            h_abs = -h_i;
        end else if (h_i >= 5'sd9) begin
            h_abs = 4'd9;
        end else begin
            h_abs = h_i[3:0];
        end

        pos_thr = tanh_pos_thr(i0_level_i, h_abs);

        // tanh symmetry:
        // p(-h) = 1 - p(h)
        // Quantized version: thr(-h) = 16'hFFFF - thr(+h)
        if (h_i < 5'sd0) begin
            p_up_thr_o = 16'hFFFF - pos_thr;
        end else begin
            p_up_thr_o = pos_thr;
        end
    end

endmodule
