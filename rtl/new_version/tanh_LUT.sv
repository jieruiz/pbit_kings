`ifndef TANH_LUT_COMB
`define TANH_LUT_COMB
import pbit_pkg::*;

// Generate the seven nonzero-magnitude thresholds for one shared regional bank.
// The h=0 threshold is supplied locally by each selector.
module tanh_threshold_bank (
    input  logic [I0_LEVEL_WIDTH-1:0] i0_level_i,
    output logic [LUT_WIDTH-1:0]      pos_thr_by_abs_o [1:7]
);
    // New I0 IDs 0..31 select these original 64-level LUT IDs in order:
    // 0, 1, 2, 3, 4, 5, 6, 7.
    // 8, 9, 10, 13, 16, 20, 24, 26.
    // 28, 30, 32, 36, 40, 44, 46, 48.
    // 50, 52, 54, 56, 60, 61, 62, 63.
    function automatic logic [LUT_WIDTH-1:0] tanh_pos_thr;
        input logic [I0_LEVEL_WIDTH-1:0] level;
        input logic [MACSUM_WIDTH-2:0] h_abs_in;
        begin
            // h_abs_in is a generate-time constant; merge equal I0 outputs per magnitude.
            case (h_abs_in)
                3'd1: begin
                    case (level)
                        5'd0: tanh_pos_thr = 16'h8CC1;
                        5'd1: tanh_pos_thr = 16'h987B;
                        5'd2: tanh_pos_thr = 16'hA3CB;
                        5'd3: tanh_pos_thr = 16'hAE88;
                        5'd4: tanh_pos_thr = 16'hBB26;
                        5'd5: tanh_pos_thr = 16'hC1CC;
                        5'd6: tanh_pos_thr = 16'hCA31;
                        5'd7: tanh_pos_thr = 16'hD3CA;
                        5'd8: tanh_pos_thr = 16'hD867;
                        5'd9: tanh_pos_thr = 16'hDE46;
                        5'd10: tanh_pos_thr = 16'hE364;
                        5'd11: tanh_pos_thr = 16'hEB9E;
                        5'd12: tanh_pos_thr = 16'hF1A0;
                        5'd13: tanh_pos_thr = 16'hF79A;
                        5'd14: tanh_pos_thr = 16'hFB24;
                        5'd15: tanh_pos_thr = 16'hFCA3;
                        5'd16: tanh_pos_thr = 16'hFD35;
                        5'd17: tanh_pos_thr = 16'hFE12;
                        5'd18: tanh_pos_thr = 16'hFE66;
                        5'd19: tanh_pos_thr = 16'hFF15;
                        5'd20: tanh_pos_thr = 16'hFF79;
                        5'd21: tanh_pos_thr = 16'hFFB3;
                        5'd22: tanh_pos_thr = 16'hFFCB;
                        5'd23: tanh_pos_thr = 16'hFFDB;
                        5'd24: tanh_pos_thr = 16'hFFE4;
                        5'd25: tanh_pos_thr = 16'hFFEA;
                        5'd26: tanh_pos_thr = 16'hFFF1;
                        5'd27: tanh_pos_thr = 16'hFFF5;
                        5'd28: tanh_pos_thr = 16'hFFF9;
                        5'd29: tanh_pos_thr = 16'hFFFC;
                        5'd30: tanh_pos_thr = 16'hFFFE;
                        5'd31: tanh_pos_thr = 16'hFFFF;
                        default: tanh_pos_thr = 16'hFFFF;
                    endcase
                end
                3'd2: begin
                    case (level)
                        5'd0: tanh_pos_thr = 16'h9943;
                        5'd1: tanh_pos_thr = 16'hAF3C;
                        5'd2: tanh_pos_thr = 16'hC265;
                        5'd3: tanh_pos_thr = 16'hD233;
                        5'd4: tanh_pos_thr = 16'hE17B;
                        5'd5: tanh_pos_thr = 16'hE817;
                        5'd6: tanh_pos_thr = 16'hEF11;
                        5'd7: tanh_pos_thr = 16'hF54F;
                        5'd8: tanh_pos_thr = 16'hF7B4;
                        5'd9: tanh_pos_thr = 16'hFA3C;
                        5'd10: tanh_pos_thr = 16'hFC02;
                        5'd11: tanh_pos_thr = 16'hFE18;
                        5'd12: tanh_pos_thr = 16'hFF18;
                        5'd13: tanh_pos_thr = 16'hFFB4;
                        5'd14: tanh_pos_thr = 16'hFFE7;
                        5'd15: tanh_pos_thr = 16'hFFF3;
                        5'd16: tanh_pos_thr = 16'hFFF7;
                        5'd17: tanh_pos_thr = 16'hFFFB;
                        5'd18: tanh_pos_thr = 16'hFFFC;
                        5'd19: tanh_pos_thr = 16'hFFFE;
                        5'd20, 5'd21, 5'd22, 5'd23, 5'd24, 5'd25,
                        5'd26, 5'd27, 5'd28, 5'd29, 5'd30, 5'd31: tanh_pos_thr = 16'hFFFF;
                        default: tanh_pos_thr = 16'hFFFF;
                    endcase
                end
                3'd3: begin
                    case (level)
                        5'd0: tanh_pos_thr = 16'hA549;
                        5'd1: tanh_pos_thr = 16'hC2FD;
                        5'd2: tanh_pos_thr = 16'hD93E;
                        5'd3: tanh_pos_thr = 16'hE85D;
                        5'd4: tanh_pos_thr = 16'hF3DB;
                        5'd5: tanh_pos_thr = 16'hF7CE;
                        5'd6: tanh_pos_thr = 16'hFB43;
                        5'd7: tanh_pos_thr = 16'hFDB0;
                        5'd8: tanh_pos_thr = 16'hFE70;
                        5'd9: tanh_pos_thr = 16'hFF1B;
                        5'd10: tanh_pos_thr = 16'hFF7D;
                        5'd11: tanh_pos_thr = 16'hFFD5;
                        5'd12: tanh_pos_thr = 16'hFFF1;
                        5'd13: tanh_pos_thr = 16'hFFFC;
                        5'd14, 5'd15, 5'd16, 5'd17, 5'd18, 5'd19,
                        5'd20, 5'd21, 5'd22, 5'd23, 5'd24, 5'd25,
                        5'd26, 5'd27, 5'd28, 5'd29, 5'd30, 5'd31: tanh_pos_thr = 16'hFFFF;
                        default: tanh_pos_thr = 16'hFFFF;
                    endcase
                end
                3'd4: begin
                    case (level)
                        5'd0: tanh_pos_thr = 16'hB0A1;
                        5'd1: tanh_pos_thr = 16'hD325;
                        5'd2: tanh_pos_thr = 16'hE8A3;
                        5'd3: tanh_pos_thr = 16'hF465;
                        5'd4: tanh_pos_thr = 16'hFB64;
                        5'd5: tanh_pos_thr = 16'hFD4F;
                        5'd6: tanh_pos_thr = 16'hFEB8;
                        5'd7: tanh_pos_thr = 16'hFF83;
                        5'd8: tanh_pos_thr = 16'hFFB6;
                        5'd9: tanh_pos_thr = 16'hFFDC;
                        5'd10: tanh_pos_thr = 16'hFFEF;
                        5'd11: tanh_pos_thr = 16'hFFFB;
                        5'd12: tanh_pos_thr = 16'hFFFE;
                        5'd13, 5'd14, 5'd15, 5'd16, 5'd17, 5'd18,
                        5'd19, 5'd20, 5'd21, 5'd22, 5'd23, 5'd24,
                        5'd25, 5'd26, 5'd27, 5'd28, 5'd29, 5'd30,
                        5'd31: tanh_pos_thr = 16'hFFFF;
                        default: tanh_pos_thr = 16'hFFFF;
                    endcase
                end
                3'd5: begin
                    case (level)
                        5'd0: tanh_pos_thr = 16'hBB26;
                        5'd1: tanh_pos_thr = 16'hDFBB;
                        5'd2: tanh_pos_thr = 16'hF24D;
                        5'd3: tanh_pos_thr = 16'hFA72;
                        5'd4: tanh_pos_thr = 16'hFE48;
                        5'd5: tanh_pos_thr = 16'hFF21;
                        5'd6: tanh_pos_thr = 16'hFFA8;
                        5'd7: tanh_pos_thr = 16'hFFE5;
                        5'd8: tanh_pos_thr = 16'hFFF2;
                        5'd9: tanh_pos_thr = 16'hFFFA;
                        5'd10: tanh_pos_thr = 16'hFFFD;
                        5'd11, 5'd12, 5'd13, 5'd14, 5'd15, 5'd16,
                        5'd17, 5'd18, 5'd19, 5'd20, 5'd21, 5'd22,
                        5'd23, 5'd24, 5'd25, 5'd26, 5'd27, 5'd28,
                        5'd29, 5'd30, 5'd31: tanh_pos_thr = 16'hFFFF;
                        default: tanh_pos_thr = 16'hFFFF;
                    endcase
                end
                3'd6: begin
                    case (level)
                        5'd0: tanh_pos_thr = 16'hC4BD;
                        5'd1: tanh_pos_thr = 16'hE92B;
                        5'd2: tanh_pos_thr = 16'hF81A;
                        5'd3: tanh_pos_thr = 16'hFD60;
                        5'd4: tanh_pos_thr = 16'hFF5D;
                        5'd5: tanh_pos_thr = 16'hFFB7;
                        5'd6: tanh_pos_thr = 16'hFFE8;
                        5'd7: tanh_pos_thr = 16'hFFFA;
                        5'd8: tanh_pos_thr = 16'hFFFD;
                        5'd9: tanh_pos_thr = 16'hFFFE;
                        5'd10, 5'd11, 5'd12, 5'd13, 5'd14, 5'd15,
                        5'd16, 5'd17, 5'd18, 5'd19, 5'd20, 5'd21,
                        5'd22, 5'd23, 5'd24, 5'd25, 5'd26, 5'd27,
                        5'd28, 5'd29, 5'd30, 5'd31: tanh_pos_thr = 16'hFFFF;
                        default: tanh_pos_thr = 16'hFFFF;
                    endcase
                end
                3'd7: begin
                    case (level)
                        5'd0: tanh_pos_thr = 16'hCD5B;
                        5'd1: tanh_pos_thr = 16'hF00B;
                        5'd2: tanh_pos_thr = 16'hFB7E;
                        5'd3: tanh_pos_thr = 16'hFEC4;
                        5'd4: tanh_pos_thr = 16'hFFC3;
                        5'd5: tanh_pos_thr = 16'hFFE8;
                        5'd6: tanh_pos_thr = 16'hFFF9;
                        5'd7: tanh_pos_thr = 16'hFFFE;
                        5'd8, 5'd9, 5'd10, 5'd11, 5'd12, 5'd13,
                        5'd14, 5'd15, 5'd16, 5'd17, 5'd18, 5'd19,
                        5'd20, 5'd21, 5'd22, 5'd23, 5'd24, 5'd25,
                        5'd26, 5'd27, 5'd28, 5'd29, 5'd30, 5'd31: tanh_pos_thr = 16'hFFFF;
                        default: tanh_pos_thr = 16'hFFFF;
                    endcase
                end
                default: tanh_pos_thr = 16'hFFFF;
            endcase
        end
    endfunction

    genvar h_idx;
    generate
        for (h_idx = 1; h_idx < 8; h_idx = h_idx + 1) begin : GEN_POS_THR_BY_ABS
            assign pos_thr_by_abs_o[h_idx] =
                tanh_pos_thr(i0_level_i, h_idx[MACSUM_WIDTH-2:0]);
        end
    endgenerate

endmodule

// AREA_OPT_TANH_SHARED: Keep only signed-|h| saturation and an 8:1 threshold selector with a local h=0 constant.
module tanh_threshold_select (
    input  logic signed [MACSUM_WIDTH-1:0] h_i,
    input  wire         [LUT_WIDTH-1:0]    pos_thr_by_abs_i [1:7],
    output logic        [LUT_WIDTH-1:0]    p_up_thr_o
);
    logic [MACSUM_WIDTH-1:0] h_mag;
    logic [MACSUM_WIDTH-2:0] h_abs_sat;
    logic [LUT_WIDTH-1:0]    pos_thr;

    // AREA_OPT_TANH_SHARED: Replace the enumerated signed-magnitude case with equivalent abs-and-saturate logic.
    assign h_mag = h_i[MACSUM_WIDTH-1]
                 ? (~h_i + {{(MACSUM_WIDTH-1){1'b0}}, 1'b1})
                 : h_i;

    // The only out-of-range 4-bit input is -8; saturate its magnitude to 7.
    // Use the magnitude MSB instead of a general comparator.
    assign h_abs_sat = h_mag[MACSUM_WIDTH-1] ? '1 : h_mag[MACSUM_WIDTH-2:0];

    // Avoid distributing or registering the constant zero-magnitude threshold.
    assign pos_thr = (h_abs_sat == '0) ? 16'h8000 : pos_thr_by_abs_i[h_abs_sat];

    // AREA_OPT_TANH_SHARED: Preserve the original quantized symmetry exactly for negative h values.
    assign p_up_thr_o = h_i[MACSUM_WIDTH-1] ? ~pos_thr : pos_thr;

endmodule
`endif
