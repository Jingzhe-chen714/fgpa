`timescale 1ns/1ps
// V8 OSD: frame snapshots, sequential double-dabble conversion, four video
// registers (input edge N -> output N+3). Budget160 blanking clocks after frame.
// Measured FPS/time and status inputs are never replaced with nominal numbers.
module case4_v8_osd (
 input wire clk,rst,frame_start,in_hs,in_vs,in_de,
 input wire [10:0] x,y,input wire [23:0] in_rgb,
 input wire [1:0] app_mode,history_mode,input wire [2:0] mode,effect_mode,strobe_interval,
 input wire [10:0] threshold,auto_target,input wire [7:0] mean_luma,
 input wire median_enable,frozen,processing,auto_enable,thick_enable,temporal_enable,fault,
 input wire circle_found,rectangle_found,face_found,strobe_busy,strobe_ready,
 input wire [7:0] capture_fps,processing_fps,input wire [15:0] processing_ms,
 input wire menu_open,input wire [3:0] menu_index,input wire history_paused,
 input wire [6:0] history_count,input wire [5:0] selected_index,reference_index,
 output reg out_hs,out_vs,out_de,output reg [23:0] out_rgb
);
    function automatic [34:0] font(input [7:0] c);
        begin
            case (c)
                "0": font={5'b01110,5'b10001,5'b10011,5'b10101,5'b11001,5'b10001,5'b01110};
                "1": font={5'b00100,5'b01100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110};
                "2": font={5'b01110,5'b10001,5'b00001,5'b00010,5'b00100,5'b01000,5'b11111};
                "3": font={5'b11110,5'b00001,5'b00001,5'b01110,5'b00001,5'b00001,5'b11110};
                "4": font={5'b00010,5'b00110,5'b01010,5'b10010,5'b11111,5'b00010,5'b00010};
                "5": font={5'b11111,5'b10000,5'b10000,5'b11110,5'b00001,5'b00001,5'b11110};
                "6": font={5'b01110,5'b10000,5'b10000,5'b11110,5'b10001,5'b10001,5'b01110};
                "7": font={5'b11111,5'b00001,5'b00010,5'b00100,5'b01000,5'b01000,5'b01000};
                "8": font={5'b01110,5'b10001,5'b10001,5'b01110,5'b10001,5'b10001,5'b01110};
                "9": font={5'b01110,5'b10001,5'b10001,5'b01111,5'b00001,5'b00001,5'b01110};
                "A": font={5'b01110,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
                "B": font={5'b11110,5'b10001,5'b10001,5'b11110,5'b10001,5'b10001,5'b11110};
                "C": font={5'b01110,5'b10001,5'b10000,5'b10000,5'b10000,5'b10001,5'b01110};
                "D": font={5'b11110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b11110};
                "E": font={5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b11111};
                "F": font={5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b10000};
                "G": font={5'b01110,5'b10001,5'b10000,5'b10111,5'b10001,5'b10001,5'b01110};
                "H": font={5'b10001,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
                "I": font={5'b01110,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110};
                "K": font={5'b10001,5'b10010,5'b10100,5'b11000,5'b10100,5'b10010,5'b10001};
                "L": font={5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b11111};
                "M": font={5'b10001,5'b11011,5'b10101,5'b10101,5'b10001,5'b10001,5'b10001};
                "N": font={5'b10001,5'b11001,5'b10101,5'b10011,5'b10001,5'b10001,5'b10001};
                "O": font={5'b01110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
                "R": font={5'b11110,5'b10001,5'b10001,5'b11110,5'b10100,5'b10010,5'b10001};
                "S": font={5'b01111,5'b10000,5'b10000,5'b01110,5'b00001,5'b00001,5'b11110};
                "T": font={5'b11111,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100};
                "U": font={5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
                "V": font={5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01010,5'b00100};
                "W": font={5'b10001,5'b10001,5'b10001,5'b10101,5'b10101,5'b11011,5'b10001};
                "Y": font={5'b10001,5'b10001,5'b01010,5'b00100,5'b00100,5'b00100,5'b00100};
                "Z": font={5'b11111,5'b00001,5'b00010,5'b00100,5'b01000,5'b10000,5'b11111};
                "J": font={5'b00111,5'b00010,5'b00010,5'b00010,5'b00010,5'b10010,5'b01100};
                "P": font={5'b11110,5'b10001,5'b10001,5'b11110,5'b10000,5'b10000,5'b10000};
                "Q": font={5'b01110,5'b10001,5'b10001,5'b10001,5'b10101,5'b10010,5'b01101};
                "X": font={5'b10001,5'b10001,5'b01010,5'b00100,5'b01010,5'b10001,5'b10001};
                "+": font={5'b00000,5'b00100,5'b00100,5'b11111,5'b00100,5'b00100,5'b00000};
                "-": font={5'b00000,5'b00000,5'b00000,5'b11111,5'b00000,5'b00000,5'b00000};
                "/": font={5'b00001,5'b00010,5'b00010,5'b00100,5'b01000,5'b01000,5'b10000};
                ">": font={5'b10000,5'b01000,5'b00100,5'b00010,5'b00100,5'b01000,5'b10000};
                ":": font={5'b00000,5'b00100,5'b00100,5'b00000,5'b00100,5'b00100,5'b00000};
                8'h80: font={5'b01110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
                8'h81: font={5'b11111,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b11111};
                default: font=0;
            endcase
        end
    endfunction


    function automatic [7:0] app_text(input [5:0] code,input [6:0] col);
      begin app_text=" "; case({code,col})
        13'd0: app_text="L";
        13'd1: app_text="I";
        13'd2: app_text="V";
        13'd3: app_text="E";
        13'd384: app_text="F";
        13'd385: app_text="A";
        13'd386: app_text="C";
        13'd387: app_text="E";
        default: ; endcase end endfunction
    function automatic [7:0] history_text(input [5:0] code,input [6:0] col);
      begin history_text=" "; case({code,col})
        13'd0: history_text="L";
        13'd1: history_text="I";
        13'd2: history_text="V";
        13'd3: history_text="E";
        13'd128: history_text="R";
        13'd129: history_text="E";
        13'd130: history_text="P";
        13'd131: history_text="L";
        13'd132: history_text="A";
        13'd133: history_text="Y";
        13'd256: history_text="C";
        13'd257: history_text="O";
        13'd258: history_text="N";
        13'd259: history_text="T";
        13'd260: history_text="O";
        13'd261: history_text="U";
        13'd262: history_text="R";
        default: ; endcase end endfunction
    function automatic [7:0] algo_text(input [5:0] code,input [6:0] col);
      begin algo_text=" "; case({code,col})
        13'd0: algo_text="S";
        13'd1: algo_text="O";
        13'd2: algo_text="B";
        13'd3: algo_text="E";
        13'd4: algo_text="L";
        13'd6: algo_text="C";
        13'd7: algo_text="O";
        13'd8: algo_text="L";
        13'd9: algo_text="O";
        13'd10: algo_text="R";
        13'd128: algo_text="C";
        13'd129: algo_text="A";
        13'd130: algo_text="N";
        13'd131: algo_text="N";
        13'd132: algo_text="Y";
        13'd134: algo_text="C";
        13'd135: algo_text="O";
        13'd136: algo_text="L";
        13'd137: algo_text="O";
        13'd138: algo_text="R";
        13'd256: algo_text="S";
        13'd257: algo_text="O";
        13'd258: algo_text="B";
        13'd259: algo_text="E";
        13'd260: algo_text="L";
        13'd262: algo_text="B";
        13'd263: algo_text="W";
        13'd384: algo_text="C";
        13'd385: algo_text="A";
        13'd386: algo_text="N";
        13'd387: algo_text="N";
        13'd388: algo_text="Y";
        13'd390: algo_text="B";
        13'd391: algo_text="W";
        13'd512: algo_text="S";
        13'd513: algo_text="C";
        13'd514: algo_text="H";
        13'd515: algo_text="A";
        13'd516: algo_text="R";
        13'd517: algo_text="R";
        13'd519: algo_text="B";
        13'd520: algo_text="W";
        13'd640: algo_text="S";
        13'd641: algo_text="C";
        13'd642: algo_text="H";
        13'd643: algo_text="A";
        13'd644: algo_text="R";
        13'd645: algo_text="R";
        13'd647: algo_text="C";
        13'd648: algo_text="O";
        13'd649: algo_text="L";
        13'd650: algo_text="O";
        13'd651: algo_text="R";
        default: ; endcase end endfunction
    function automatic [7:0] effect_text(input [5:0] code,input [6:0] col);
      begin effect_text=" "; case({code,col})
        13'd0: effect_text="N";
        13'd1: effect_text="O";
        13'd2: effect_text="R";
        13'd3: effect_text="M";
        13'd4: effect_text="A";
        13'd5: effect_text="L";
        13'd128: effect_text="T";
        13'd129: effect_text="R";
        13'd130: effect_text="A";
        13'd131: effect_text="I";
        13'd132: effect_text="L";
        13'd256: effect_text="S";
        13'd257: effect_text="T";
        13'd258: effect_text="A";
        13'd259: effect_text="B";
        13'd260: effect_text="L";
        13'd261: effect_text="E";
        13'd263: effect_text="C";
        13'd264: effect_text="O";
        13'd265: effect_text="M";
        13'd266: effect_text="P";
        13'd267: effect_text="A";
        13'd268: effect_text="R";
        13'd269: effect_text="E";
        13'd384: effect_text="M";
        13'd385: effect_text="O";
        13'd386: effect_text="T";
        13'd387: effect_text="I";
        13'd388: effect_text="O";
        13'd389: effect_text="N";
        13'd512: effect_text="S";
        13'd513: effect_text="T";
        13'd514: effect_text="R";
        13'd515: effect_text="O";
        13'd516: effect_text="B";
        13'd517: effect_text="E";
        default: ; endcase end endfunction
    function automatic [7:0] on_text(input [5:0] code,input [6:0] col);
      begin on_text=" "; case({code,col})
        13'd0: on_text="O";
        13'd1: on_text="F";
        13'd2: on_text="F";
        13'd128: on_text="O";
        13'd129: on_text="N";
        default: ; endcase end endfunction
    function automatic [7:0] found_text(input [5:0] code,input [6:0] col);
      begin found_text=" "; case({code,col})
        13'd0: found_text="S";
        13'd1: found_text="E";
        13'd2: found_text="A";
        13'd3: found_text="R";
        13'd4: found_text="C";
        13'd5: found_text="H";
        13'd128: found_text="F";
        13'd129: found_text="O";
        13'd130: found_text="U";
        13'd131: found_text="N";
        13'd132: found_text="D";
        default: ; endcase end endfunction
    function automatic [7:0] run_text(input [5:0] code,input [6:0] col);
      begin run_text=" "; case({code,col})
        13'd0: run_text="P";
        13'd1: run_text="L";
        13'd2: run_text="A";
        13'd3: run_text="Y";
        13'd128: run_text="P";
        13'd129: run_text="A";
        13'd130: run_text="U";
        13'd131: run_text="S";
        13'd132: run_text="E";
        default: ; endcase end endfunction
    function automatic [7:0] freeze_text(input [5:0] code,input [6:0] col);
      begin freeze_text=" "; case({code,col})
        13'd0: freeze_text="L";
        13'd1: freeze_text="I";
        13'd2: freeze_text="V";
        13'd3: freeze_text="E";
        13'd128: freeze_text="H";
        13'd129: freeze_text="O";
        13'd130: freeze_text="L";
        13'd131: freeze_text="D";
        default: ; endcase end endfunction
    function automatic [7:0] ready_text(input [5:0] code,input [6:0] col);
      begin ready_text=" "; case({code,col})
        13'd0: ready_text="R";
        13'd1: ready_text="E";
        13'd2: ready_text="A";
        13'd3: ready_text="D";
        13'd4: ready_text="Y";
        13'd128: ready_text="W";
        13'd129: ready_text="A";
        13'd130: ready_text="I";
        13'd131: ready_text="T";
        default: ; endcase end endfunction
    function automatic [7:0] auto_text(input [5:0] code,input [6:0] col);
      begin auto_text=" "; case({code,col})
        13'd0: auto_text="M";
        13'd1: auto_text="A";
        13'd2: auto_text="N";
        13'd128: auto_text="A";
        13'd129: auto_text="U";
        13'd130: auto_text="T";
        13'd131: auto_text="O";
        default: ; endcase end endfunction
    function automatic [7:0] face_text(input [5:0] code,input [6:0] col);
      begin face_text=" "; case({code,col})
        13'd0: face_text="F";
        13'd1: face_text="A";
        13'd2: face_text="C";
        13'd3: face_text="E";
        13'd5: face_text="S";
        13'd6: face_text="E";
        13'd7: face_text="A";
        13'd8: face_text="R";
        13'd9: face_text="C";
        13'd10: face_text="H";
        13'd128: face_text="F";
        13'd129: face_text="A";
        13'd130: face_text="C";
        13'd131: face_text="E";
        13'd133: face_text="C";
        13'd134: face_text="A";
        13'd135: face_text="N";
        13'd136: face_text="D";
        13'd137: face_text="I";
        13'd138: face_text="D";
        13'd139: face_text="A";
        13'd140: face_text="T";
        13'd141: face_text="E";
        default: ; endcase end endfunction
    function automatic [7:0] strobe_text(input [5:0] code,input [6:0] col);
      begin strobe_text=" "; case({code,col})
        13'd0: strobe_text="E";
        13'd1: strobe_text="M";
        13'd2: strobe_text="P";
        13'd3: strobe_text="T";
        13'd4: strobe_text="Y";
        13'd128: strobe_text="C";
        13'd129: strobe_text="A";
        13'd130: strobe_text="P";
        13'd131: strobe_text="T";
        13'd132: strobe_text="U";
        13'd133: strobe_text="R";
        13'd134: strobe_text="I";
        13'd135: strobe_text="N";
        13'd136: strobe_text="G";
        13'd256: strobe_text="R";
        13'd257: strobe_text="E";
        13'd258: strobe_text="A";
        13'd259: strobe_text="D";
        13'd260: strobe_text="Y";
        default: ; endcase end endfunction
    function automatic [7:0] hint_text(input [5:0] code,input [6:0] col);
      begin hint_text=" "; case({code,col})
        13'd0: hint_text="K";
        13'd1: hint_text="1";
        13'd2: hint_text="/";
        13'd3: hint_text="K";
        13'd4: hint_text="2";
        13'd6: hint_text="T";
        13'd7: hint_text="H";
        13'd8: hint_text="R";
        13'd12: hint_text="K";
        13'd13: hint_text="1";
        13'd15: hint_text="H";
        13'd16: hint_text="O";
        13'd17: hint_text="L";
        13'd18: hint_text="D";
        13'd20: hint_text="M";
        13'd21: hint_text="O";
        13'd22: hint_text="D";
        13'd23: hint_text="E";
        13'd27: hint_text="B";
        13'd28: hint_text="O";
        13'd29: hint_text="T";
        13'd30: hint_text="H";
        13'd32: hint_text="1";
        13'd33: hint_text="S";
        13'd35: hint_text="M";
        13'd36: hint_text="E";
        13'd37: hint_text="N";
        13'd38: hint_text="U";
        13'd128: hint_text="K";
        13'd129: hint_text="1";
        13'd131: hint_text="P";
        13'd132: hint_text="R";
        13'd133: hint_text="E";
        13'd134: hint_text="V";
        13'd136: hint_text="K";
        13'd137: hint_text="2";
        13'd139: hint_text="N";
        13'd140: hint_text="E";
        13'd141: hint_text="X";
        13'd142: hint_text="T";
        13'd145: hint_text="H";
        13'd146: hint_text="O";
        13'd147: hint_text="L";
        13'd148: hint_text="D";
        13'd150: hint_text="K";
        13'd151: hint_text="1";
        13'd153: hint_text="R";
        13'd154: hint_text="E";
        13'd155: hint_text="F";
        13'd157: hint_text="K";
        13'd158: hint_text="2";
        13'd160: hint_text="P";
        13'd161: hint_text="L";
        13'd162: hint_text="A";
        13'd163: hint_text="Y";
        13'd256: hint_text="K";
        13'd257: hint_text="1";
        13'd259: hint_text="N";
        13'd260: hint_text="E";
        13'd261: hint_text="X";
        13'd262: hint_text="T";
        13'd264: hint_text="K";
        13'd265: hint_text="2";
        13'd267: hint_text="S";
        13'd268: hint_text="E";
        13'd269: hint_text="T";
        13'd272: hint_text="H";
        13'd273: hint_text="O";
        13'd274: hint_text="L";
        13'd275: hint_text="D";
        13'd277: hint_text="K";
        13'd278: hint_text="1";
        13'd280: hint_text="C";
        13'd281: hint_text="L";
        13'd282: hint_text="O";
        13'd283: hint_text="S";
        13'd284: hint_text="E";
        default: ; endcase end endfunction
    function automatic [7:0] fixed_text(input [5:0] code,input [6:0] col);
      begin fixed_text=" "; case({code,col})
        13'd0: fixed_text="A";
        13'd1: fixed_text="P";
        13'd2: fixed_text="P";
        13'd11: fixed_text="V";
        13'd12: fixed_text="I";
        13'd13: fixed_text="E";
        13'd14: fixed_text="W";
        13'd130: fixed_text="T";
        13'd131: fixed_text="A";
        13'd132: fixed_text="R";
        13'd133: fixed_text="G";
        13'd134: fixed_text="E";
        13'd135: fixed_text="T";
        13'd137: fixed_text="C";
        13'd138: fixed_text="I";
        13'd139: fixed_text="R";
        13'd140: fixed_text="C";
        13'd141: fixed_text="L";
        13'd142: fixed_text="E";
        13'd258: fixed_text="T";
        13'd259: fixed_text="A";
        13'd260: fixed_text="R";
        13'd261: fixed_text="G";
        13'd262: fixed_text="E";
        13'd263: fixed_text="T";
        13'd265: fixed_text="R";
        13'd266: fixed_text="E";
        13'd267: fixed_text="C";
        13'd268: fixed_text="T";
        13'd269: fixed_text="A";
        13'd270: fixed_text="N";
        13'd271: fixed_text="G";
        13'd272: fixed_text="L";
        13'd273: fixed_text="E";
        13'd384: fixed_text="M";
        13'd385: fixed_text="O";
        13'd386: fixed_text="D";
        13'd387: fixed_text="E";
        13'd410: fixed_text="T";
        13'd411: fixed_text="H";
        13'd412: fixed_text="R";
        13'd512: fixed_text="M";
        13'd513: fixed_text="E";
        13'd514: fixed_text="D";
        13'd520: fixed_text="S";
        13'd521: fixed_text="T";
        13'd522: fixed_text="A";
        13'd523: fixed_text="B";
        13'd524: fixed_text="L";
        13'd525: fixed_text="E";
        13'd531: fixed_text="T";
        13'd532: fixed_text="H";
        13'd533: fixed_text="I";
        13'd534: fixed_text="C";
        13'd535: fixed_text="K";
        13'd540: fixed_text="U";
        13'd541: fixed_text="S";
        13'd542: fixed_text="E";
        13'd543: fixed_text="R";
        13'd640: fixed_text="A";
        13'd641: fixed_text="U";
        13'd642: fixed_text="T";
        13'd643: fixed_text="O";
        13'd650: fixed_text="L";
        13'd651: fixed_text="U";
        13'd652: fixed_text="M";
        13'd653: fixed_text="A";
        13'd659: fixed_text="A";
        13'd660: fixed_text="I";
        13'd661: fixed_text="M";
        13'd768: fixed_text="C";
        13'd769: fixed_text="A";
        13'd770: fixed_text="P";
        13'd776: fixed_text="F";
        13'd777: fixed_text="P";
        13'd778: fixed_text="S";
        13'd780: fixed_text="A";
        13'd781: fixed_text="L";
        13'd782: fixed_text="G";
        13'd788: fixed_text="F";
        13'd789: fixed_text="P";
        13'd790: fixed_text="S";
        13'd792: fixed_text="T";
        13'd793: fixed_text="I";
        13'd794: fixed_text="M";
        13'd795: fixed_text="E";
        13'd803: fixed_text="M";
        13'd804: fixed_text="S";
        13'd896: fixed_text="E";
        13'd897: fixed_text="F";
        13'd898: fixed_text="F";
        13'd899: fixed_text="E";
        13'd900: fixed_text="C";
        13'd901: fixed_text="T";
        13'd1024: fixed_text="F";
        13'd1025: fixed_text="R";
        13'd1026: fixed_text="A";
        13'd1027: fixed_text="M";
        13'd1028: fixed_text="E";
        13'd1034: fixed_text="R";
        13'd1035: fixed_text="E";
        13'd1036: fixed_text="F";
        13'd1042: fixed_text="C";
        13'd1043: fixed_text="O";
        13'd1044: fixed_text="U";
        13'd1045: fixed_text="N";
        13'd1046: fixed_text="T";
        13'd1152: fixed_text="S";
        13'd1153: fixed_text="T";
        13'd1154: fixed_text="R";
        13'd1155: fixed_text="O";
        13'd1156: fixed_text="B";
        13'd1157: fixed_text="E";
        13'd1170: fixed_text="I";
        13'd1171: fixed_text="N";
        13'd1172: fixed_text="T";
        13'd1173: fixed_text="E";
        13'd1174: fixed_text="R";
        13'd1175: fixed_text="V";
        13'd1176: fixed_text="A";
        13'd1177: fixed_text="L";
        13'd1183: fixed_text="F";
        13'd1184: fixed_text="R";
        13'd1185: fixed_text="A";
        13'd1186: fixed_text="M";
        13'd1187: fixed_text="E";
        13'd1188: fixed_text="S";
        13'd1536: fixed_text="M";
        13'd1537: fixed_text="E";
        13'd1538: fixed_text="N";
        13'd1539: fixed_text="U";
        13'd1541: fixed_text="K";
        13'd1542: fixed_text="1";
        13'd1544: fixed_text="N";
        13'd1545: fixed_text="E";
        13'd1546: fixed_text="X";
        13'd1547: fixed_text="T";
        13'd1549: fixed_text="K";
        13'd1550: fixed_text="2";
        13'd1552: fixed_text="S";
        13'd1553: fixed_text="E";
        13'd1554: fixed_text="T";
        13'd1666: fixed_text="A";
        13'd1667: fixed_text="P";
        13'd1668: fixed_text="P";
        13'd1794: fixed_text="E";
        13'd1795: fixed_text="D";
        13'd1796: fixed_text="G";
        13'd1797: fixed_text="E";
        13'd1922: fixed_text="A";
        13'd1923: fixed_text="U";
        13'd1924: fixed_text="T";
        13'd1925: fixed_text="O";
        13'd2050: fixed_text="T";
        13'd2051: fixed_text="H";
        13'd2052: fixed_text="R";
        13'd2178: fixed_text="M";
        13'd2179: fixed_text="E";
        13'd2180: fixed_text="D";
        13'd2181: fixed_text="I";
        13'd2182: fixed_text="A";
        13'd2183: fixed_text="N";
        13'd2306: fixed_text="T";
        13'd2307: fixed_text="H";
        13'd2308: fixed_text="I";
        13'd2309: fixed_text="C";
        13'd2310: fixed_text="K";
        13'd2434: fixed_text="E";
        13'd2435: fixed_text="F";
        13'd2436: fixed_text="F";
        13'd2437: fixed_text="E";
        13'd2438: fixed_text="C";
        13'd2439: fixed_text="T";
        13'd2562: fixed_text="S";
        13'd2563: fixed_text="T";
        13'd2564: fixed_text="A";
        13'd2565: fixed_text="B";
        13'd2566: fixed_text="L";
        13'd2567: fixed_text="E";
        13'd2690: fixed_text="I";
        13'd2691: fixed_text="N";
        13'd2692: fixed_text="T";
        13'd2693: fixed_text="E";
        13'd2694: fixed_text="R";
        13'd2695: fixed_text="V";
        13'd2696: fixed_text="A";
        13'd2697: fixed_text="L";
        13'd2818: fixed_text="C";
        13'd2819: fixed_text="A";
        13'd2820: fixed_text="P";
        13'd2821: fixed_text="T";
        13'd2822: fixed_text="U";
        13'd2823: fixed_text="R";
        13'd2824: fixed_text="E";
        13'd2946: fixed_text="V";
        13'd2947: fixed_text="I";
        13'd2948: fixed_text="E";
        13'd2949: fixed_text="W";
        13'd3074: fixed_text="P";
        13'd3075: fixed_text="A";
        13'd3076: fixed_text="U";
        13'd3077: fixed_text="S";
        13'd3078: fixed_text="E";
        13'd3200: fixed_text="H";
        13'd3201: fixed_text="O";
        13'd3202: fixed_text="L";
        13'd3203: fixed_text="D";
        13'd3205: fixed_text="K";
        13'd3206: fixed_text="1";
        13'd3208: fixed_text="C";
        13'd3209: fixed_text="L";
        13'd3210: fixed_text="O";
        13'd3211: fixed_text="S";
        13'd3212: fixed_text="E";
        13'd3216: fixed_text="B";
        13'd3217: fixed_text="O";
        13'd3218: fixed_text="T";
        13'd3219: fixed_text="H";
        13'd3221: fixed_text="1";
        13'd3222: fixed_text="S";
        13'd3224: fixed_text="M";
        13'd3225: fixed_text="E";
        13'd3226: fixed_text="N";
        13'd3227: fixed_text="U";
        13'd3328: fixed_text="G";
        13'd3329: fixed_text="E";
        13'd3330: fixed_text="O";
        13'd3331: fixed_text="M";
        13'd3332: fixed_text="E";
        13'd3333: fixed_text="T";
        13'd3334: fixed_text="R";
        13'd3335: fixed_text="Y";
        13'd3337: fixed_text="L";
        13'd3338: fixed_text="I";
        13'd3339: fixed_text="V";
        13'd3340: fixed_text="E";
        13'd3342: fixed_text="M";
        13'd3343: fixed_text="O";
        13'd3344: fixed_text="D";
        13'd3345: fixed_text="E";
        13'd3346: fixed_text="0";
        13'd3348: fixed_text="N";
        13'd3349: fixed_text="O";
        13'd3350: fixed_text="R";
        13'd3351: fixed_text="M";
        13'd3352: fixed_text="A";
        13'd3353: fixed_text="L";
        13'd3355: fixed_text="O";
        13'd3356: fixed_text="N";
        13'd3357: fixed_text="L";
        13'd3358: fixed_text="Y";
        13'd3456: fixed_text="E";
        13'd3457: fixed_text="R";
        13'd3458: fixed_text="R";
        13'd3459: fixed_text="O";
        13'd3460: fixed_text="R";
        13'd3462: fixed_text="C";
        13'd3463: fixed_text="H";
        13'd3464: fixed_text="E";
        13'd3465: fixed_text="C";
        13'd3466: fixed_text="K";
        13'd3468: fixed_text="D";
        13'd3469: fixed_text="D";
        13'd3470: fixed_text="R";
        13'd3471: fixed_text="/";
        13'd3472: fixed_text="P";
        13'd3473: fixed_text="I";
        13'd3474: fixed_text="P";
        13'd3475: fixed_text="E";
        13'd3476: fixed_text="L";
        13'd3477: fixed_text="I";
        13'd3478: fixed_text="N";
        13'd3479: fixed_text="E";
        13'd3584: fixed_text="D";
        13'd3585: fixed_text="I";
        13'd3586: fixed_text="S";
        13'd3587: fixed_text="P";
        13'd3588: fixed_text="L";
        13'd3589: fixed_text="A";
        13'd3590: fixed_text="Y";
        13'd3592: fixed_text="C";
        13'd3593: fixed_text="O";
        13'd3594: fixed_text="M";
        13'd3595: fixed_text="P";
        13'd3596: fixed_text="L";
        13'd3597: fixed_text="E";
        13'd3598: fixed_text="T";
        13'd3599: fixed_text="E";
        13'd3601: fixed_text="F";
        13'd3602: fixed_text="R";
        13'd3603: fixed_text="A";
        13'd3604: fixed_text="M";
        13'd3605: fixed_text="E";
        13'd3606: fixed_text="S";
        13'd3712: fixed_text="R";
        13'd3713: fixed_text="A";
        13'd3714: fixed_text="W";
        13'd3716: fixed_text="L";
        13'd3717: fixed_text="E";
        13'd3718: fixed_text="F";
        13'd3719: fixed_text="T";
        13'd3721: fixed_text="/";
        13'd3723: fixed_text="S";
        13'd3724: fixed_text="T";
        13'd3725: fixed_text="A";
        13'd3726: fixed_text="B";
        13'd3727: fixed_text="L";
        13'd3728: fixed_text="E";
        13'd3730: fixed_text="R";
        13'd3731: fixed_text="I";
        13'd3732: fixed_text="G";
        13'd3733: fixed_text="H";
        13'd3734: fixed_text="T";
        13'd3840: fixed_text="K";
        13'd3841: fixed_text="2";
        13'd3843: fixed_text="S";
        13'd3844: fixed_text="T";
        13'd3845: fixed_text="A";
        13'd3846: fixed_text="R";
        13'd3847: fixed_text="T";
        13'd3849: fixed_text="/";
        13'd3851: fixed_text="R";
        13'd3852: fixed_text="E";
        13'd3853: fixed_text="S";
        13'd3854: fixed_text="T";
        13'd3855: fixed_text="A";
        13'd3856: fixed_text="R";
        13'd3857: fixed_text="T";
        13'd3859: fixed_text="S";
        13'd3860: fixed_text="T";
        13'd3861: fixed_text="R";
        13'd3862: fixed_text="O";
        13'd3863: fixed_text="B";
        13'd3864: fixed_text="E";
        13'd128: fixed_text=8'h80;
        13'd256: fixed_text=8'h81;
        default: ; endcase end endfunction

 reg [1:0] app_cfg,history_cfg;
 reg [2:0] mode_cfg,effect_cfg,interval_cfg;
 reg median_cfg,frozen_cfg,processing_cfg,auto_cfg,thick_cfg,temporal_cfg,fault_cfg;
 reg circle_cfg,rectangle_cfg,face_cfg,strobe_busy_cfg,strobe_ready_cfg,menu_cfg,paused_cfg;
 reg [3:0] menu_index_cfg;
 reg [15:0] numbers[0:9];reg [19:0] decimal[0:9];
 reg [35:0] convert_work;reg [3:0] convert_field,convert_step;reg convert_busy;
 function automatic [35:0] bcd_step(input [35:0] work);
   reg [35:0] adjusted;integer digit;
   begin adjusted=work;
     for(digit=0;digit<5;digit=digit+1)
       if(adjusted[16+4*digit+:4]>=5)adjusted[16+4*digit+:4]=adjusted[16+4*digit+:4]+4'd3;
     bcd_step={adjusted[34:0],1'b0};
   end
 endfunction
 wire [35:0] convert_next=bcd_step(convert_work);
 integer n;
 always @(posedge clk)begin
  if(rst)begin
   app_cfg<=0;history_cfg<=0;mode_cfg<=0;effect_cfg<=0;interval_cfg<=1;
   median_cfg<=1;frozen_cfg<=0;processing_cfg<=1;auto_cfg<=1;thick_cfg<=0;temporal_cfg<=1;fault_cfg<=0;
   circle_cfg<=0;rectangle_cfg<=0;face_cfg<=0;strobe_busy_cfg<=0;strobe_ready_cfg<=0;
   menu_cfg<=0;paused_cfg<=0;menu_index_cfg<=0;
   convert_work<=0;convert_field<=0;convert_step<=0;convert_busy<=0;
   for(n=0;n<10;n=n+1)begin numbers[n]<=0;decimal[n]<=0;end
  end else if(frame_start)begin
   app_cfg<=app_mode;history_cfg<=history_mode;mode_cfg<=mode;effect_cfg<=effect_mode;interval_cfg<=strobe_interval;
   median_cfg<=median_enable;frozen_cfg<=frozen;processing_cfg<=processing;auto_cfg<=auto_enable;
   thick_cfg<=thick_enable;temporal_cfg<=temporal_enable;fault_cfg<=fault;
   circle_cfg<=circle_found;rectangle_cfg<=rectangle_found;face_cfg<=face_found;
   strobe_busy_cfg<=strobe_busy;strobe_ready_cfg<=strobe_ready;menu_cfg<=menu_open;
   paused_cfg<=history_paused;menu_index_cfg<=menu_index;
   numbers[0]<={5'd0,threshold};numbers[1]<={5'd0,auto_target};numbers[2]<={8'd0,mean_luma};
   numbers[3]<={8'd0,capture_fps};numbers[4]<={8'd0,processing_fps};numbers[5]<=processing_ms;
   numbers[6]<={10'd0,selected_index};numbers[7]<={10'd0,reference_index};numbers[8]<={9'd0,history_count};
   numbers[9]<=16'd1<<strobe_interval;
   convert_work<={20'd0,5'd0,threshold};convert_field<=0;convert_step<=0;convert_busy<=1;
  end else if(convert_busy)begin
   if(convert_step==15)begin
    decimal[convert_field]<=convert_next[35:16];convert_step<=0;
    if(convert_field==9)convert_busy<=0;
    else begin convert_field<=convert_field+1'b1;convert_work<={20'd0,numbers[convert_field+1'b1]};end
   end else begin convert_work<=convert_next;convert_step<=convert_step+1'b1;end
  end
 end
 function automatic [7:0] digit_text(input [19:0] bcd,input [2:0] col);
   begin case(col)
    0:digit_text="0"+bcd[19:16];1:digit_text="0"+bcd[15:12];2:digit_text="0"+bcd[11:8];
    3:digit_text="0"+bcd[7:4];4:digit_text="0"+bcd[3:0];default:digit_text=" ";
   endcase end
 endfunction
 wire geometry_cfg=app_cfg==0&&history_cfg==0&&mode_cfg==0&&effect_cfg==0;
 wire [10:0] lx=x-11'd8;reg [10:0] ly;reg [5:0] line;reg text_large,overlay;
 reg [6:0] character;reg [2:0] column,row;reg [7:0] ascii;reg [23:0] ink,background;
 always @*begin
  line=63;ly=0;text_large=0;
  if(y>=8&&y<40)begin line=0;ly=y-11'd8;text_large=1;end
  else if(y>=48&&y<80)begin line=1;ly=y-11'd48;text_large=1;end
  else if(y>=80&&y<112)begin line=2;ly=y-11'd80;text_large=1;end
  else if(y>=128&&y<272)begin line=3+((y-11'd128)>>4);ly=(y-11'd128)&11'd15;end
  else if(menu_cfg&&y>=288&&y<320)begin line=12;ly=y-11'd288;text_large=1;end
  else if(menu_cfg&&y>=336&&y<624)begin
   // 24-pixel row pitch gives12 menu entries without obscuring the right half.
   // Constant arithmetic is outside pixel data and synthesized as comparators.
   if(y<360)begin line=13;ly=y-336;end
   else if(y<384)begin line=14;ly=y-360;end
   else if(y<408)begin line=15;ly=y-384;end
   else if(y<432)begin line=16;ly=y-408;end
   else if(y<456)begin line=17;ly=y-432;end
   else if(y<480)begin line=18;ly=y-456;end
   else if(y<504)begin line=19;ly=y-480;end
   else if(y<528)begin line=20;ly=y-504;end
   else if(y<552)begin line=21;ly=y-528;end
   else if(y<576)begin line=22;ly=y-552;end
   else if(y<600)begin line=23;ly=y-576;end
   else begin line=24;ly=y-600;end
   if(ly>=16)line=63;
  end else if(menu_cfg&&y>=640&&y<656)begin line=25;ly=y-640;end
  character=text_large?{1'b0,lx[10:5]}:lx[10:4];column=text_large?lx[4:2]:lx[3:1];row=text_large?ly[4:2]:ly[3:1];
  overlay=in_de&&x>=8&&x<952&&line!=63;
  ascii=fixed_text(line,character);ink=24'hffffff;background=24'h101820;
  case(line)
   0:begin
    if(character>=4&&character<8)ascii=app_text({4'd0,app_cfg},character-7'd4);
    if(character>=16&&character<23)ascii=history_text({4'd0,history_cfg},character-7'd16);
    ink=24'h80d8ff;
   end
   1:begin
    if(geometry_cfg)begin
      if(character>=16&&character<22)ascii=found_text({5'd0,circle_cfg},character-7'd16);
      ink=24'hffe000;
    end else if(app_cfg==3&&history_cfg==0)begin ascii=face_text({5'd0,face_cfg},character);ink=face_cfg?24'h80ff80:24'hb0beca;end
    else begin ascii=effect_text({3'd0,effect_cfg},character);ink=24'h80d8ff;end
   end
   2:begin
    if(geometry_cfg)begin
      if(character>=19&&character<25)ascii=found_text({5'd0,rectangle_cfg},character-7'd19);
      ink=24'h4090ff;
    end else begin ascii=fixed_text(28,character);ink=24'hb0beca;end
   end
   3:begin
    if(character==5)ascii="0"+mode_cfg;
    if(character>=7&&character<19)ascii=algo_text({3'd0,mode_cfg},character-7'd7);
    if(character>=30&&character<34)ascii=digit_text(decimal[0],character-7'd29);
    if(character>=36&&character<40)ascii=auto_text({5'd0,auto_cfg},character-7'd36);
   end
   4:begin
    if(character>=4&&character<7)ascii=on_text({5'd0,median_cfg},character-7'd4);
    if(character>=15&&character<18)ascii=on_text({5'd0,temporal_cfg},character-7'd15);
    if(character==25)ascii=thick_cfg?"3":"1";
    if(character>=33&&character<37)ascii=freeze_text({5'd0,frozen_cfg},character-7'd33);
    if(character>=38&&character<43)ascii=ready_text({5'd0,processing_cfg},character-7'd38);
   end
   5:begin
    if(character>=5&&character<8)ascii=on_text({5'd0,auto_cfg},character-7'd5);
    if(character>=15&&character<18)ascii=digit_text(decimal[2],character-7'd13);
    if(character>=23&&character<27)ascii=digit_text(decimal[1],character-7'd22);
    ink=24'h80ff80;
   end
   6:begin
    if(character>=4&&character<7)ascii=digit_text(decimal[3],character-7'd2);
    if(character>=16&&character<19)ascii=digit_text(decimal[4],character-7'd14);
    if(character>=29&&character<34)ascii=digit_text(decimal[5],character-7'd29);
    ink=24'h80d8ff;
   end
   7:begin
    if(character>=7&&character<21)ascii=effect_text({3'd0,effect_cfg},character-7'd7);
    if(character>=23&&character<28)ascii=run_text({5'd0,paused_cfg},character-7'd23);
   end
   8:begin
    if(character>=6&&character<9)ascii=digit_text(decimal[6],character-7'd4);
    if(character>=14&&character<17)ascii=digit_text(decimal[7],character-7'd12);
    if(character>=24&&character<27)ascii=digit_text(decimal[8],character-7'd22);
    if(history_cfg==0)ascii=" ";
   end
   9:begin
    if(character>=7&&character<16)ascii=strobe_text(strobe_busy_cfg?6'd1:strobe_ready_cfg?6'd2:6'd0,character-7'd7);
    if(character>=27&&character<29)ascii=digit_text(decimal[9],character-7'd24);
    if(effect_cfg!=4)ascii=" ";
   end
   10:begin ascii=hint_text(menu_cfg?6'd2:history_cfg!=0?6'd1:6'd0,character);ink=24'h80ff80;end
   11:begin
    if(fault_cfg)begin ascii=fixed_text(27,character);ink=24'hff6040;end
    else if(effect_cfg==2)begin ascii=fixed_text(29,character);ink=24'h80d8ff;end
    else begin ascii=fixed_text(26,character);ink=24'hb0beca;end
   end
   12:ink=24'h80d8ff;
   13,14,15,16,17,18,19,20,21,22,23,24:begin
    if(line-13==menu_index_cfg)begin background=24'h174e70;ink=24'hffff80;if(character==0)ascii=">";end
    if(line==13&&character>=12&&character<16)ascii=app_text({4'd0,app_cfg},character-7'd12);
    if(line==14)begin
      if(character==12)ascii="0"+mode_cfg;
      if(character>=14&&character<26)ascii=algo_text({3'd0,mode_cfg},character-7'd14);
    end
    if(line==15&&character>=12&&character<15)ascii=on_text({5'd0,auto_cfg},character-7'd12);
    if(line==16&&character>=12&&character<16)ascii=digit_text(decimal[0],character-7'd11);
    if(line==17&&character>=12&&character<15)ascii=on_text({5'd0,median_cfg},character-7'd12);
    if(line==18&&character==12)ascii=thick_cfg?"3":"1";
    if(line==19&&character>=12&&character<26)ascii=effect_text({3'd0,effect_cfg},character-7'd12);
    if(line==20&&character>=12&&character<15)ascii=on_text({5'd0,temporal_cfg},character-7'd12);
    if(line==21&&character>=12&&character<14)ascii=digit_text(decimal[9],character-7'd9);
    if(line==22&&character>=12&&character<37)ascii=fixed_text(30,character-7'd12);
    if(line==23&&character>=12&&character<19)ascii=history_text({4'd0,history_cfg},character-7'd12);
    if(line==24&&character>=12&&character<17)ascii=history_cfg!=0?run_text({5'd0,paused_cfg},character-7'd12):freeze_text({5'd0,frozen_cfg},character-7'd12);
   end
   25:ink=24'h80ff80;
   default:;
  endcase
 end
    reg [7:0] ascii0;reg [2:0] col0,row0,col1,row1;
    reg [34:0] glyph1;
    reg overlay0,overlay1,overlay2,dot2;
    reg [23:0] ink0,ink1,ink2,bg0,bg1,bg2;
    reg [26:0] video0,video1,video2;
    always @(posedge clk) begin
        if(rst) begin
            ascii0<=0;col0<=0;row0<=0;col1<=0;row1<=0;glyph1<=0;
            overlay0<=0;overlay1<=0;overlay2<=0;dot2<=0;
            ink0<=0;ink1<=0;ink2<=0;bg0<=0;bg1<=0;bg2<=0;
            video0<={3'b110,24'd0};video1<={3'b110,24'd0};video2<={3'b110,24'd0};
            out_hs<=1;out_vs<=1;out_de<=0;out_rgb<=0;
        end else begin
            ascii0<=ascii;col0<=column;row0<=row;overlay0<=overlay;
            ink0<=ink;bg0<=background;video0<={in_hs,in_vs,in_de,in_rgb};
            glyph1<=font(ascii0);col1<=col0;row1<=row0;overlay1<=overlay0;
            ink1<=ink0;bg1<=bg0;video1<=video0;
            dot2<=col1<5 && row1<7 && glyph1[34-row1*5-col1];
            overlay2<=overlay1;ink2<=ink1;bg2<=bg1;video2<=video1;
            {out_hs,out_vs,out_de}<=video2[26:24];
            out_rgb<=overlay2?(dot2?ink2:bg2):video2[23:0];
        end
    end
endmodule

