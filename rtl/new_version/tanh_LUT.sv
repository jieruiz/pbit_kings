`ifndef TANH_LUT_COMB
`define TANH_LUT_COMB
import pbit_pkg::*;

// AREA_OPT_TANH_SHARED: Decode the global I0 level once and broadcast all ten positive-|h| thresholds.
module tanh_threshold_bank (
    input  logic [I0_LEVEL_WIDTH-1:0] i0_level_i,
    output logic [LUT_WIDTH-1:0]      pos_thr_by_abs_o [0:9]
);
    function automatic logic [LUT_WIDTH-1:0] tanh_pos_thr;
        input logic[I0_LEVEL_WIDTH-1:0] level;
        input logic[MACSUM_WIDTH-2:0] h_abs_in;
        begin
        case (level)
                6'd0: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'h8CC1;
                        4'd2: tanh_pos_thr = 16'h9943;
                        4'd3: tanh_pos_thr = 16'hA549;
                        4'd4: tanh_pos_thr = 16'hB0A1;
                        4'd5: tanh_pos_thr = 16'hBB26;
                        4'd6: tanh_pos_thr = 16'hC4BD;
                        4'd7: tanh_pos_thr = 16'hCD5B;
                        4'd8: tanh_pos_thr = 16'hD4FE;
                        4'd9: tanh_pos_thr = 16'hDBAF;
                        default: tanh_pos_thr = 16'hDBAF;
                    endcase
                end
    
                6'd1: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'h987B;
                        4'd2: tanh_pos_thr = 16'hAF3C;
                        4'd3: tanh_pos_thr = 16'hC2FD;
                        4'd4: tanh_pos_thr = 16'hD325;
                        4'd5: tanh_pos_thr = 16'hDFBB;
                        4'd6: tanh_pos_thr = 16'hE92B;
                        4'd7: tanh_pos_thr = 16'hF00B;
                        4'd8: tanh_pos_thr = 16'hF4F2;
                        4'd9: tanh_pos_thr = 16'hF863;
                        default: tanh_pos_thr = 16'hF863;
                    endcase
                end
    
                6'd2: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hA3CB;
                        4'd2: tanh_pos_thr = 16'hC265;
                        4'd3: tanh_pos_thr = 16'hD93E;
                        4'd4: tanh_pos_thr = 16'hE8A3;
                        4'd5: tanh_pos_thr = 16'hF24D;
                        4'd6: tanh_pos_thr = 16'hF81A;
                        4'd7: tanh_pos_thr = 16'hFB7E;
                        4'd8: tanh_pos_thr = 16'hFD71;
                        4'd9: tanh_pos_thr = 16'hFE8D;
                        default: tanh_pos_thr = 16'hFE8D;
                    endcase
                end
    
                6'd3: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hAE88;
                        4'd2: tanh_pos_thr = 16'hD233;
                        4'd3: tanh_pos_thr = 16'hE85D;
                        4'd4: tanh_pos_thr = 16'hF465;
                        4'd5: tanh_pos_thr = 16'hFA72;
                        4'd6: tanh_pos_thr = 16'hFD60;
                        4'd7: tanh_pos_thr = 16'hFEC4;
                        4'd8: tanh_pos_thr = 16'hFF6C;
                        4'd9: tanh_pos_thr = 16'hFFBA;
                        default: tanh_pos_thr = 16'hFFBA;
                    endcase
                end
    
                6'd4: begin
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
    
                6'd5: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hC1CC;
                        4'd2: tanh_pos_thr = 16'hE817;
                        4'd3: tanh_pos_thr = 16'hF7CE;
                        4'd4: tanh_pos_thr = 16'hFD4F;
                        4'd5: tanh_pos_thr = 16'hFF21;
                        4'd6: tanh_pos_thr = 16'hFFB7;
                        4'd7: tanh_pos_thr = 16'hFFE8;
                        4'd8: tanh_pos_thr = 16'hFFF8;
                        4'd9: tanh_pos_thr = 16'hFFFD;
                        default: tanh_pos_thr = 16'hFFFD;
                    endcase
                end
    
                6'd6: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hCA31;
                        4'd2: tanh_pos_thr = 16'hEF11;
                        4'd3: tanh_pos_thr = 16'hFB43;
                        4'd4: tanh_pos_thr = 16'hFEB8;
                        4'd5: tanh_pos_thr = 16'hFFA8;
                        4'd6: tanh_pos_thr = 16'hFFE8;
                        4'd7: tanh_pos_thr = 16'hFFF9;
                        4'd8: tanh_pos_thr = 16'hFFFD;
                        4'd9: tanh_pos_thr = 16'hFFFF;
                        default: tanh_pos_thr = 16'hFFFF;
                    endcase
                end
    
                6'd7: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hD3CA;
                        4'd2: tanh_pos_thr = 16'hF54F;
                        4'd3: tanh_pos_thr = 16'hFDB0;
                        4'd4: tanh_pos_thr = 16'hFF83;
                        4'd5: tanh_pos_thr = 16'hFFE5;
                        4'd6: tanh_pos_thr = 16'hFFFA;
                        4'd7: tanh_pos_thr = 16'hFFFE;
                        4'd8: tanh_pos_thr = 16'hFFFF;
                        4'd9: tanh_pos_thr = 16'hFFFF;
                        default: tanh_pos_thr = 16'hFFFF;
                    endcase
                end
    
                6'd8: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hD867;
                        4'd2: tanh_pos_thr = 16'hF7B4;
                        4'd3: tanh_pos_thr = 16'hFE70;
                        4'd4: tanh_pos_thr = 16'hFFB6;
                        4'd5: tanh_pos_thr = 16'hFFF2;
                        4'd6: tanh_pos_thr = 16'hFFFD;
                        4'd7: tanh_pos_thr = 16'hFFFF;
                        4'd8: tanh_pos_thr = 16'hFFFF;
                        4'd9: tanh_pos_thr = 16'hFFFF;
                        default: tanh_pos_thr = 16'hFFFF;
                    endcase
                end
    
                6'd9: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hDE46;
                        4'd2: tanh_pos_thr = 16'hFA3C;
                        4'd3: tanh_pos_thr = 16'hFF1B;
                        4'd4: tanh_pos_thr = 16'hFFDC;
                        4'd5: tanh_pos_thr = 16'hFFFA;
                        4'd6: tanh_pos_thr = 16'hFFFE;
                        4'd7: tanh_pos_thr = 16'hFFFF;
                        4'd8: tanh_pos_thr = 16'hFFFF;
                        4'd9: tanh_pos_thr = 16'hFFFF;
                        default: tanh_pos_thr = 16'hFFFF;
                    endcase
                end
    
                6'd10: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hE364;
                        4'd2: tanh_pos_thr = 16'hFC02;
                        4'd3: tanh_pos_thr = 16'hFF7D;
                        4'd4: tanh_pos_thr = 16'hFFEF;
                        4'd5: tanh_pos_thr = 16'hFFFD;
                        4'd6: tanh_pos_thr = 16'hFFFF;
                        4'd7: tanh_pos_thr = 16'hFFFF;
                        4'd8: tanh_pos_thr = 16'hFFFF;
                        4'd9: tanh_pos_thr = 16'hFFFF;
                        default: tanh_pos_thr = 16'hFFFF;
                    endcase
                end
    
                6'd11: begin
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
    
                6'd12: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hE7D0;
                        4'd2: tanh_pos_thr = 16'hFD3E;
                        4'd3: tanh_pos_thr = 16'hFFB5;
                        4'd4: tanh_pos_thr = 16'hFFF7;
                        4'd5: tanh_pos_thr = 16'hFFFE;
                        4'd6: tanh_pos_thr = 16'hFFFF;
                        4'd7: tanh_pos_thr = 16'hFFFF;
                        4'd8: tanh_pos_thr = 16'hFFFF;
                        4'd9: tanh_pos_thr = 16'hFFFF;
                        default: tanh_pos_thr = 16'hFFFF;
                    endcase
                end
    
                6'd13: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hEB9E;
                        4'd2: tanh_pos_thr = 16'hFE18;
                        4'd3: tanh_pos_thr = 16'hFFD5;
                        4'd4: tanh_pos_thr = 16'hFFFB;
                        4'd5: tanh_pos_thr = 16'hFFFF;
                        4'd6: tanh_pos_thr = 16'hFFFF;
                        4'd7: tanh_pos_thr = 16'hFFFF;
                        4'd8: tanh_pos_thr = 16'hFFFF;
                        4'd9: tanh_pos_thr = 16'hFFFF;
                        default: tanh_pos_thr = 16'hFFFF;
                    endcase
                end
    
                6'd14: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hEEDD;
                        4'd2: tanh_pos_thr = 16'hFEB0;
                        4'd3: tanh_pos_thr = 16'hFFE7;
                        4'd4: tanh_pos_thr = 16'hFFFD;
                        4'd5: tanh_pos_thr = 16'hFFFF;
                        4'd6: tanh_pos_thr = 16'hFFFF;
                        4'd7: tanh_pos_thr = 16'hFFFF;
                        4'd8: tanh_pos_thr = 16'hFFFF;
                        4'd9: tanh_pos_thr = 16'hFFFF;
                        default: tanh_pos_thr = 16'hFFFF;
                    endcase
                end
    
                6'd15: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hEFE0;
                        4'd2: tanh_pos_thr = 16'hFED8;
                        4'd3: tanh_pos_thr = 16'hFFEB;
                        4'd4: tanh_pos_thr = 16'hFFFE;
                        4'd5: tanh_pos_thr = 16'hFFFF;
                        4'd6: tanh_pos_thr = 16'hFFFF;
                        4'd7: tanh_pos_thr = 16'hFFFF;
                        4'd8: tanh_pos_thr = 16'hFFFF;
                        4'd9: tanh_pos_thr = 16'hFFFF;
                        default: tanh_pos_thr = 16'hFFFF;
                    endcase
                end
    
                6'd16: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hF1A0;
                        4'd2: tanh_pos_thr = 16'hFF18;
                        4'd3: tanh_pos_thr = 16'hFFF1;
                        4'd4: tanh_pos_thr = 16'hFFFE;
                        4'd5: tanh_pos_thr = 16'hFFFF;
                        4'd6: tanh_pos_thr = 16'hFFFF;
                        4'd7: tanh_pos_thr = 16'hFFFF;
                        4'd8: tanh_pos_thr = 16'hFFFF;
                        4'd9: tanh_pos_thr = 16'hFFFF;
                        default: tanh_pos_thr = 16'hFFFF;
                    endcase
                end
    
                6'd17: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hF3F7;
                        4'd2: tanh_pos_thr = 16'hFF60;
                        4'd3: tanh_pos_thr = 16'hFFF7;
                        4'd4: tanh_pos_thr = 16'hFFFF;
                        4'd5: tanh_pos_thr = 16'hFFFF;
                        4'd6: tanh_pos_thr = 16'hFFFF;
                        4'd7: tanh_pos_thr = 16'hFFFF;
                        4'd8: tanh_pos_thr = 16'hFFFF;
                        4'd9: tanh_pos_thr = 16'hFFFF;
                        default: tanh_pos_thr = 16'hFFFF;
                    endcase
                end
    
                6'd18: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hF5F0;
                        4'd2: tanh_pos_thr = 16'hFF92;
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
    
                6'd19: begin
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
    
                6'd20: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hF79A;
                        4'd2: tanh_pos_thr = 16'hFFB4;
                        4'd3: tanh_pos_thr = 16'hFFFC;
                        4'd4: tanh_pos_thr = 16'hFFFF;
                        4'd5: tanh_pos_thr = 16'hFFFF;
                        4'd6: tanh_pos_thr = 16'hFFFF;
                        4'd7: tanh_pos_thr = 16'hFFFF;
                        4'd8: tanh_pos_thr = 16'hFFFF;
                        4'd9: tanh_pos_thr = 16'hFFFF;
                        default: tanh_pos_thr = 16'hFFFF;
                    endcase
                end
    
                6'd21: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hF8FF;
                        4'd2: tanh_pos_thr = 16'hFFCB;
                        4'd3: tanh_pos_thr = 16'hFFFE;
                        4'd4: tanh_pos_thr = 16'hFFFF;
                        4'd5: tanh_pos_thr = 16'hFFFF;
                        4'd6: tanh_pos_thr = 16'hFFFF;
                        4'd7: tanh_pos_thr = 16'hFFFF;
                        4'd8: tanh_pos_thr = 16'hFFFF;
                        4'd9: tanh_pos_thr = 16'hFFFF;
                        default: tanh_pos_thr = 16'hFFFF;
                    endcase
                end
    
                6'd22: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hFA2A;
                        4'd2: tanh_pos_thr = 16'hFFDB;
                        4'd3: tanh_pos_thr = 16'hFFFE;
                        4'd4: tanh_pos_thr = 16'hFFFF;
                        4'd5: tanh_pos_thr = 16'hFFFF;
                        4'd6: tanh_pos_thr = 16'hFFFF;
                        4'd7: tanh_pos_thr = 16'hFFFF;
                        4'd8: tanh_pos_thr = 16'hFFFF;
                        4'd9: tanh_pos_thr = 16'hFFFF;
                        default: tanh_pos_thr = 16'hFFFF;
                    endcase
                end
    
                6'd23: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hFA93;
                        4'd2: tanh_pos_thr = 16'hFFE0;
                        4'd3: tanh_pos_thr = 16'hFFFE;
                        4'd4: tanh_pos_thr = 16'hFFFF;
                        4'd5: tanh_pos_thr = 16'hFFFF;
                        4'd6: tanh_pos_thr = 16'hFFFF;
                        4'd7: tanh_pos_thr = 16'hFFFF;
                        4'd8: tanh_pos_thr = 16'hFFFF;
                        4'd9: tanh_pos_thr = 16'hFFFF;
                        default: tanh_pos_thr = 16'hFFFF;
                    endcase
                end
    
                6'd24: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hFB24;
                        4'd2: tanh_pos_thr = 16'hFFE7;
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
    
                6'd25: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hFBF5;
                        4'd2: tanh_pos_thr = 16'hFFEE;
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
    
                6'd26: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hFCA3;
                        4'd2: tanh_pos_thr = 16'hFFF3;
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
    
                6'd27: begin
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
    
                6'd28: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hFD35;
                        4'd2: tanh_pos_thr = 16'hFFF7;
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
    
                6'd29: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hFDAE;
                        4'd2: tanh_pos_thr = 16'hFFFA;
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
    
                6'd30: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hFE12;
                        4'd2: tanh_pos_thr = 16'hFFFB;
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
    
                6'd31: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hFE3A;
                        4'd2: tanh_pos_thr = 16'hFFFC;
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
    
                6'd32: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hFE66;
                        4'd2: tanh_pos_thr = 16'hFFFC;
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
    
                6'd33: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hFEAB;
                        4'd2: tanh_pos_thr = 16'hFFFD;
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
    
                6'd34: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hFEE5;
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
    
                6'd35: begin
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
    
                6'd36: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hFF15;
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
    
                6'd37: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hFF3D;
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
    
                6'd38: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hFF5E;
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
    
                6'd39: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hFF6D;
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
    
                6'd40: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hFF79;
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
    
                6'd41: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hFF90;
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
    
                6'd42: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hFFA3;
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
    
                6'd43: begin
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
    
                6'd44: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hFFB3;
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
    
                6'd45: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hFFC0;
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
    
                6'd46: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hFFCB;
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
    
                6'd47: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hFFD4;
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
    
                6'd48: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hFFDB;
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
    
                6'd49: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hFFE1;
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
    
                6'd50: begin
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
    
                6'd51: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hFFE6;
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
    
                6'd52: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hFFEA;
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
    
                6'd53: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hFFEE;
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
    
                6'd54: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hFFF1;
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
    
                6'd55: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hFFF3;
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
    
                6'd56: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hFFF5;
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
    
                6'd57: begin
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
    
                6'd58: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hFFF7;
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
    
                6'd59: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hFFF8;
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
    
                6'd60: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hFFF9;
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
    
                6'd61: begin
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
    
                6'd62: begin
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
    
                6'd63: begin
                    case (h_abs_in)
                        4'd0: tanh_pos_thr = 16'h8000;
                        4'd1: tanh_pos_thr = 16'hFFFF;
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

    // AREA_OPT_TANH_SHARED: Materialize only ten level-dependent values instead of one full decoder per tile.
    genvar h_idx;
    generate
        for (h_idx = 0; h_idx < 10; h_idx = h_idx + 1) begin : GEN_POS_THR_BY_ABS
            assign pos_thr_by_abs_o[h_idx] =
                tanh_pos_thr(i0_level_i, h_idx[MACSUM_WIDTH-2:0]);
        end
    endgenerate

endmodule

// AREA_OPT_TANH_SHARED: Keep only signed-|h| saturation and a 10:1 threshold selector in each tile.
module tanh_threshold_select (
    input  logic signed [MACSUM_WIDTH-1:0] h_i,
    input  wire         [LUT_WIDTH-1:0]    pos_thr_by_abs_i [0:9],
    output logic        [LUT_WIDTH-1:0]    p_up_thr_o
);
    logic [MACSUM_WIDTH-1:0] h_mag;
    logic [MACSUM_WIDTH-2:0] h_abs_sat;
    logic [LUT_WIDTH-1:0]    pos_thr;

    // AREA_OPT_TANH_SHARED: Replace the enumerated signed-magnitude case with equivalent abs-and-saturate logic.
    always @(*) begin
        h_mag = h_i[MACSUM_WIDTH-1]
              ? (~h_i + {{(MACSUM_WIDTH-1){1'b0}}, 1'b1})
              : h_i;

        if (h_mag > MACSUM_WIDTH'(9))
            h_abs_sat = (MACSUM_WIDTH-1)'(9);
        else
            h_abs_sat = h_mag[MACSUM_WIDTH-2:0];
    end

    assign pos_thr = pos_thr_by_abs_i[h_abs_sat];

    // AREA_OPT_TANH_SHARED: Preserve the original quantized symmetry exactly for negative h values.
    assign p_up_thr_o = h_i[MACSUM_WIDTH-1] ? 16'hFFFF - pos_thr : pos_thr;

endmodule
`endif
