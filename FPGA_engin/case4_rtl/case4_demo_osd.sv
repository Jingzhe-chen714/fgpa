`timescale 1ns/1ps
// V7 frame-coherent demo UI. Four register stages: character selection, font,
// glyph dot, RGB composite. Input sampled at N appears after N+3. Sync and RGB
// have exactly the same delay. x/y are 11 bits, including 1080p bottom lines.
// frame_start must be a pulse during INPUT vertical blanking. The eleven decimal
// fields convert sequentially in 176 following clocks, well before active video.
// No division or decimal arithmetic appears on the pixel-to-RGB path.
// APP: LIVE/TRACK/INSPECT/FACE. Shape3 means FACE CANDIDATE, not identity.
// INSPECT: 0 NO REF,1 LEARN,2 WAIT,3 PASS,4 FAIL. MISS/EXTRA count 4x4 cells.
// Event: 0 NONE,1 READY,2 RECALL,3 EXPIRED. All measured rates/times come from
// parent counters; this module does not invent a nominal camera/algorithm FPS.
module case4_demo_osd (
    input wire clk,rst,frame_start,in_hs,in_vs,in_de,
    input wire [10:0] x,y,input wire [23:0] in_rgb,
    input wire [1:0] app_mode,history_mode,mode,
    input wire [10:0] threshold,
    input wire median_enable,frozen,processing,auto_enable,
    input wire [1:0] noise_level,input wire thick_enable,
    input wire [1:0] shape,input wire [2:0] inspect_status,
    input wire [15:0] count_in,count_out,
    input wire [7:0] capture_fps,processing_fps,
    input wire [15:0] processing_ms,inspect_missing,inspect_extra,
    input wire [1:0] event_status,
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
                default: font=0;
            endcase
        end
    endfunction


    function automatic [7:0] app_text(input [2:0] code,input [6:0] col);
        begin
            app_text=" ";
            case({code,col})
                10'd0: app_text="L";
                10'd1: app_text="I";
                10'd2: app_text="V";
                10'd3: app_text="E";
                10'd128: app_text="T";
                10'd129: app_text="R";
                10'd130: app_text="A";
                10'd131: app_text="C";
                10'd132: app_text="K";
                10'd256: app_text="I";
                10'd257: app_text="N";
                10'd258: app_text="S";
                10'd259: app_text="P";
                10'd260: app_text="E";
                10'd261: app_text="C";
                10'd262: app_text="T";
                10'd384: app_text="F";
                10'd385: app_text="A";
                10'd386: app_text="C";
                10'd387: app_text="E";
                default: ;
            endcase
        end
    endfunction
    function automatic [7:0] shape_text(input [2:0] code,input [6:0] col);
        begin
            shape_text=" ";
            case({code,col})
                10'd0: shape_text="N";
                10'd1: shape_text="O";
                10'd2: shape_text="N";
                10'd3: shape_text="E";
                10'd128: shape_text="C";
                10'd129: shape_text="I";
                10'd130: shape_text="R";
                10'd131: shape_text="C";
                10'd132: shape_text="L";
                10'd133: shape_text="E";
                10'd256: shape_text="R";
                10'd257: shape_text="E";
                10'd258: shape_text="C";
                10'd259: shape_text="T";
                10'd260: shape_text="A";
                10'd261: shape_text="N";
                10'd262: shape_text="G";
                10'd263: shape_text="L";
                10'd264: shape_text="E";
                10'd384: shape_text="F";
                10'd385: shape_text="A";
                10'd386: shape_text="C";
                10'd387: shape_text="E";
                default: ;
            endcase
        end
    endfunction
    function automatic [7:0] inspect_text(input [2:0] code,input [6:0] col);
        begin
            inspect_text=" ";
            case({code,col})
                10'd0: inspect_text="N";
                10'd1: inspect_text="O";
                10'd3: inspect_text="R";
                10'd4: inspect_text="E";
                10'd5: inspect_text="F";
                10'd128: inspect_text="L";
                10'd129: inspect_text="E";
                10'd130: inspect_text="A";
                10'd131: inspect_text="R";
                10'd132: inspect_text="N";
                10'd256: inspect_text="W";
                10'd257: inspect_text="A";
                10'd258: inspect_text="I";
                10'd259: inspect_text="T";
                10'd384: inspect_text="P";
                10'd385: inspect_text="A";
                10'd386: inspect_text="S";
                10'd387: inspect_text="S";
                10'd512: inspect_text="F";
                10'd513: inspect_text="A";
                10'd514: inspect_text="I";
                10'd515: inspect_text="L";
                default: ;
            endcase
        end
    endfunction
    function automatic [7:0] event_text(input [2:0] code,input [6:0] col);
        begin
            event_text=" ";
            case({code,col})
                10'd0: event_text="N";
                10'd1: event_text="O";
                10'd2: event_text="N";
                10'd3: event_text="E";
                10'd128: event_text="R";
                10'd129: event_text="E";
                10'd130: event_text="A";
                10'd131: event_text="D";
                10'd132: event_text="Y";
                10'd256: event_text="R";
                10'd257: event_text="E";
                10'd258: event_text="C";
                10'd259: event_text="A";
                10'd260: event_text="L";
                10'd261: event_text="L";
                10'd384: event_text="E";
                10'd385: event_text="X";
                10'd386: event_text="P";
                10'd387: event_text="I";
                10'd388: event_text="R";
                10'd389: event_text="E";
                10'd390: event_text="D";
                default: ;
            endcase
        end
    endfunction
    function automatic [7:0] history_text(input [2:0] code,input [6:0] col);
        begin
            history_text=" ";
            case({code,col})
                10'd0: history_text="L";
                10'd1: history_text="I";
                10'd2: history_text="V";
                10'd3: history_text="E";
                10'd128: history_text="R";
                10'd129: history_text="E";
                10'd130: history_text="P";
                10'd131: history_text="L";
                10'd132: history_text="A";
                10'd133: history_text="Y";
                10'd256: history_text="C";
                10'd257: history_text="O";
                10'd258: history_text="N";
                10'd259: history_text="T";
                10'd260: history_text="O";
                10'd261: history_text="U";
                10'd262: history_text="R";
                default: ;
            endcase
        end
    endfunction
    function automatic [7:0] noise_text(input [2:0] code,input [6:0] col);
        begin
            noise_text=" ";
            case({code,col})
                10'd0: noise_text="O";
                10'd1: noise_text="F";
                10'd2: noise_text="F";
                10'd128: noise_text="L";
                10'd129: noise_text="O";
                10'd130: noise_text="W";
                10'd256: noise_text="H";
                10'd257: noise_text="I";
                10'd258: noise_text="G";
                10'd259: noise_text="H";
                default: ;
            endcase
        end
    endfunction
    function automatic [7:0] algo_text(input [2:0] code,input [6:0] col);
        begin
            algo_text=" ";
            case({code,col})
                10'd0: algo_text="S";
                10'd1: algo_text="O";
                10'd2: algo_text="B";
                10'd3: algo_text="E";
                10'd4: algo_text="L";
                10'd128: algo_text="C";
                10'd129: algo_text="A";
                10'd130: algo_text="N";
                10'd131: algo_text="N";
                10'd132: algo_text="Y";
                default: ;
            endcase
        end
    endfunction
    function automatic [7:0] edge_text(input [2:0] code,input [6:0] col);
        begin
            edge_text=" ";
            case({code,col})
                10'd0: edge_text="R";
                10'd1: edge_text="E";
                10'd2: edge_text="D";
                10'd128: edge_text="B";
                10'd129: edge_text="I";
                10'd130: edge_text="N";
                10'd131: edge_text="A";
                10'd132: edge_text="R";
                10'd133: edge_text="Y";
                default: ;
            endcase
        end
    endfunction
    function automatic [7:0] run_text(input [2:0] code,input [6:0] col);
        begin
            run_text=" ";
            case({code,col})
                10'd0: run_text="P";
                10'd1: run_text="L";
                10'd2: run_text="A";
                10'd3: run_text="Y";
                10'd128: run_text="P";
                10'd129: run_text="A";
                10'd130: run_text="U";
                10'd131: run_text="S";
                10'd132: run_text="E";
                default: ;
            endcase
        end
    endfunction
    function automatic [7:0] on_text(input [2:0] code,input [6:0] col);
        begin
            on_text=" ";
            case({code,col})
                10'd0: on_text="O";
                10'd1: on_text="F";
                10'd2: on_text="F";
                10'd128: on_text="O";
                10'd129: on_text="N";
                default: ;
            endcase
        end
    endfunction
    function automatic [7:0] freeze_text(input [2:0] code,input [6:0] col);
        begin
            freeze_text=" ";
            case({code,col})
                10'd0: freeze_text="L";
                10'd1: freeze_text="I";
                10'd2: freeze_text="V";
                10'd3: freeze_text="E";
                10'd128: freeze_text="H";
                10'd129: freeze_text="O";
                10'd130: freeze_text="L";
                10'd131: freeze_text="D";
                default: ;
            endcase
        end
    endfunction
    function automatic [7:0] busy_text(input [2:0] code,input [6:0] col);
        begin
            busy_text=" ";
            case({code,col})
                10'd0: busy_text="R";
                10'd1: busy_text="E";
                10'd2: busy_text="A";
                10'd3: busy_text="D";
                10'd4: busy_text="Y";
                10'd128: busy_text="B";
                10'd129: busy_text="U";
                10'd130: busy_text="S";
                10'd131: busy_text="Y";
                default: ;
            endcase
        end
    endfunction
    function automatic [7:0] auto_text(input [2:0] code,input [6:0] col);
        begin
            auto_text=" ";
            case({code,col})
                10'd0: auto_text="M";
                10'd1: auto_text="A";
                10'd2: auto_text="N";
                10'd128: auto_text="A";
                10'd129: auto_text="U";
                10'd130: auto_text="T";
                10'd131: auto_text="O";
                default: ;
            endcase
        end
    endfunction
    function automatic [7:0] face_text(input [2:0] code,input [6:0] col);
        begin
            face_text=" ";
            case({code,col})
                10'd0: face_text="S";
                10'd1: face_text="E";
                10'd2: face_text="A";
                10'd3: face_text="R";
                10'd4: face_text="C";
                10'd5: face_text="H";
                10'd128: face_text="C";
                10'd129: face_text="A";
                10'd130: face_text="N";
                10'd131: face_text="D";
                10'd132: face_text="I";
                10'd133: face_text="D";
                10'd134: face_text="A";
                10'd135: face_text="T";
                10'd136: face_text="E";
                default: ;
            endcase
        end
    endfunction
    function automatic [7:0] hint_text(input [2:0] code,input [6:0] col);
        begin
            hint_text=" ";
            case({code,col})
                10'd0: hint_text="K";
                10'd1: hint_text="1";
                10'd2: hint_text="/";
                10'd3: hint_text="K";
                10'd4: hint_text="2";
                10'd6: hint_text="T";
                10'd7: hint_text="H";
                10'd8: hint_text="R";
                10'd10: hint_text="+";
                10'd11: hint_text="/";
                10'd12: hint_text="-";
                10'd15: hint_text="H";
                10'd16: hint_text="O";
                10'd17: hint_text="L";
                10'd18: hint_text="D";
                10'd20: hint_text="K";
                10'd21: hint_text="1";
                10'd23: hint_text="E";
                10'd24: hint_text="D";
                10'd25: hint_text="G";
                10'd26: hint_text="E";
                10'd28: hint_text="K";
                10'd29: hint_text="2";
                10'd31: hint_text="F";
                10'd32: hint_text="R";
                10'd33: hint_text="E";
                10'd34: hint_text="E";
                10'd35: hint_text="Z";
                10'd36: hint_text="E";
                10'd39: hint_text="B";
                10'd40: hint_text="O";
                10'd41: hint_text="T";
                10'd42: hint_text="H";
                10'd44: hint_text="M";
                10'd45: hint_text="E";
                10'd46: hint_text="N";
                10'd47: hint_text="U";
                10'd128: hint_text="K";
                10'd129: hint_text="1";
                10'd131: hint_text="O";
                10'd132: hint_text="L";
                10'd133: hint_text="D";
                10'd134: hint_text="E";
                10'd135: hint_text="R";
                10'd137: hint_text="K";
                10'd138: hint_text="2";
                10'd140: hint_text="N";
                10'd141: hint_text="E";
                10'd142: hint_text="W";
                10'd143: hint_text="E";
                10'd144: hint_text="R";
                10'd147: hint_text="H";
                10'd148: hint_text="O";
                10'd149: hint_text="L";
                10'd150: hint_text="D";
                10'd152: hint_text="K";
                10'd153: hint_text="1";
                10'd155: hint_text="R";
                10'd156: hint_text="E";
                10'd157: hint_text="F";
                10'd159: hint_text="K";
                10'd160: hint_text="2";
                10'd162: hint_text="P";
                10'd163: hint_text="L";
                10'd164: hint_text="A";
                10'd165: hint_text="Y";
                10'd168: hint_text="B";
                10'd169: hint_text="O";
                10'd170: hint_text="T";
                10'd171: hint_text="H";
                10'd173: hint_text="M";
                10'd174: hint_text="E";
                10'd175: hint_text="N";
                10'd176: hint_text="U";
                10'd256: hint_text="K";
                10'd257: hint_text="1";
                10'd259: hint_text="N";
                10'd260: hint_text="E";
                10'd261: hint_text="X";
                10'd262: hint_text="T";
                10'd265: hint_text="K";
                10'd266: hint_text="2";
                10'd268: hint_text="S";
                10'd269: hint_text="E";
                10'd270: hint_text="T";
                10'd273: hint_text="H";
                10'd274: hint_text="O";
                10'd275: hint_text="L";
                10'd276: hint_text="D";
                10'd278: hint_text="K";
                10'd279: hint_text="1";
                10'd281: hint_text="C";
                10'd282: hint_text="L";
                10'd283: hint_text="O";
                10'd284: hint_text="S";
                10'd285: hint_text="E";
                10'd288: hint_text="B";
                10'd289: hint_text="O";
                10'd290: hint_text="T";
                10'd291: hint_text="H";
                10'd293: hint_text="M";
                10'd294: hint_text="E";
                10'd295: hint_text="N";
                10'd296: hint_text="U";
                default: ;
            endcase
        end
    endfunction
    function automatic [7:0] crossing_text(input dir,input [6:0] col);
        begin
            crossing_text=" ";
            case({dir,col})
                8'd0: crossing_text="I";
                8'd1: crossing_text="N";
                8'd3: crossing_text="+";
                8'd4: crossing_text="1";
                8'd128: crossing_text="O";
                8'd129: crossing_text="U";
                8'd130: crossing_text="T";
                8'd132: crossing_text="+";
                8'd133: crossing_text="1";
                default: ;
            endcase
        end
    endfunction
    function automatic [7:0] fixed_text(input [4:0] line,input [6:0] col);
        begin
            fixed_text=" ";
            case({line,col})
                12'd0: fixed_text="A";
                12'd1: fixed_text="P";
                12'd2: fixed_text="P";
                12'd12: fixed_text="T";
                12'd13: fixed_text="A";
                12'd14: fixed_text="R";
                12'd15: fixed_text="G";
                12'd16: fixed_text="E";
                12'd17: fixed_text="T";
                12'd128: fixed_text="M";
                12'd129: fixed_text="O";
                12'd130: fixed_text="D";
                12'd131: fixed_text="E";
                12'd148: fixed_text="T";
                12'd149: fixed_text="H";
                12'd150: fixed_text="R";
                12'd256: fixed_text="M";
                12'd257: fixed_text="E";
                12'd258: fixed_text="D";
                12'd264: fixed_text="N";
                12'd265: fixed_text="O";
                12'd266: fixed_text="I";
                12'd267: fixed_text="S";
                12'd268: fixed_text="E";
                12'd275: fixed_text="T";
                12'd276: fixed_text="H";
                12'd277: fixed_text="I";
                12'd278: fixed_text="C";
                12'd279: fixed_text="K";
                12'd283: fixed_text="U";
                12'd284: fixed_text="S";
                12'd285: fixed_text="E";
                12'd286: fixed_text="R";
                12'd512: fixed_text="M";
                12'd513: fixed_text="I";
                12'd514: fixed_text="S";
                12'd515: fixed_text="S";
                12'd523: fixed_text="E";
                12'd524: fixed_text="X";
                12'd525: fixed_text="T";
                12'd526: fixed_text="R";
                12'd527: fixed_text="A";
                12'd640: fixed_text="C";
                12'd641: fixed_text="A";
                12'd642: fixed_text="P";
                12'd648: fixed_text="F";
                12'd649: fixed_text="P";
                12'd650: fixed_text="S";
                12'd652: fixed_text="A";
                12'd653: fixed_text="L";
                12'd654: fixed_text="G";
                12'd660: fixed_text="F";
                12'd661: fixed_text="P";
                12'd662: fixed_text="S";
                12'd664: fixed_text="T";
                12'd665: fixed_text="I";
                12'd666: fixed_text="M";
                12'd667: fixed_text="E";
                12'd675: fixed_text="M";
                12'd676: fixed_text="S";
                12'd768: fixed_text="E";
                12'd769: fixed_text="V";
                12'd770: fixed_text="E";
                12'd771: fixed_text="N";
                12'd772: fixed_text="T";
                12'd782: fixed_text="V";
                12'd783: fixed_text="I";
                12'd784: fixed_text="E";
                12'd785: fixed_text="W";
                12'd1024: fixed_text="T";
                12'd1025: fixed_text="E";
                12'd1026: fixed_text="S";
                12'd1027: fixed_text="T";
                12'd1029: fixed_text="N";
                12'd1030: fixed_text="O";
                12'd1031: fixed_text="I";
                12'd1032: fixed_text="S";
                12'd1033: fixed_text="E";
                12'd1152: fixed_text="M";
                12'd1153: fixed_text="E";
                12'd1154: fixed_text="N";
                12'd1155: fixed_text="U";
                12'd1157: fixed_text="K";
                12'd1158: fixed_text="1";
                12'd1160: fixed_text="N";
                12'd1161: fixed_text="E";
                12'd1162: fixed_text="X";
                12'd1163: fixed_text="T";
                12'd1165: fixed_text="K";
                12'd1166: fixed_text="2";
                12'd1168: fixed_text="S";
                12'd1169: fixed_text="E";
                12'd1170: fixed_text="T";
                12'd1282: fixed_text="A";
                12'd1283: fixed_text="P";
                12'd1284: fixed_text="P";
                12'd1410: fixed_text="E";
                12'd1411: fixed_text="D";
                12'd1412: fixed_text="G";
                12'd1413: fixed_text="E";
                12'd1538: fixed_text="A";
                12'd1539: fixed_text="U";
                12'd1540: fixed_text="T";
                12'd1541: fixed_text="O";
                12'd1666: fixed_text="T";
                12'd1667: fixed_text="H";
                12'd1668: fixed_text="R";
                12'd1794: fixed_text="M";
                12'd1795: fixed_text="E";
                12'd1796: fixed_text="D";
                12'd1797: fixed_text="I";
                12'd1798: fixed_text="A";
                12'd1799: fixed_text="N";
                12'd1922: fixed_text="N";
                12'd1923: fixed_text="O";
                12'd1924: fixed_text="I";
                12'd1925: fixed_text="S";
                12'd1926: fixed_text="E";
                12'd2050: fixed_text="T";
                12'd2051: fixed_text="H";
                12'd2052: fixed_text="I";
                12'd2053: fixed_text="C";
                12'd2054: fixed_text="K";
                12'd2178: fixed_text="L";
                12'd2179: fixed_text="E";
                12'd2180: fixed_text="A";
                12'd2181: fixed_text="R";
                12'd2182: fixed_text="N";
                12'd2186: fixed_text="K";
                12'd2187: fixed_text="2";
                12'd2189: fixed_text="C";
                12'd2190: fixed_text="A";
                12'd2191: fixed_text="P";
                12'd2192: fixed_text="T";
                12'd2193: fixed_text="U";
                12'd2194: fixed_text="R";
                12'd2195: fixed_text="E";
                12'd2197: fixed_text="R";
                12'd2198: fixed_text="E";
                12'd2199: fixed_text="F";
                12'd2200: fixed_text="E";
                12'd2201: fixed_text="R";
                12'd2202: fixed_text="E";
                12'd2203: fixed_text="N";
                12'd2204: fixed_text="C";
                12'd2205: fixed_text="E";
                12'd2306: fixed_text="C";
                12'd2307: fixed_text="L";
                12'd2308: fixed_text="E";
                12'd2309: fixed_text="A";
                12'd2310: fixed_text="R";
                12'd2314: fixed_text="K";
                12'd2315: fixed_text="2";
                12'd2317: fixed_text="R";
                12'd2318: fixed_text="E";
                12'd2319: fixed_text="S";
                12'd2320: fixed_text="E";
                12'd2321: fixed_text="T";
                12'd2323: fixed_text="C";
                12'd2324: fixed_text="O";
                12'd2325: fixed_text="U";
                12'd2326: fixed_text="N";
                12'd2327: fixed_text="T";
                12'd2328: fixed_text="S";
                12'd2434: fixed_text="E";
                12'd2435: fixed_text="V";
                12'd2436: fixed_text="E";
                12'd2437: fixed_text="N";
                12'd2438: fixed_text="T";
                12'd2442: fixed_text="K";
                12'd2443: fixed_text="2";
                12'd2445: fixed_text="R";
                12'd2446: fixed_text="E";
                12'd2447: fixed_text="C";
                12'd2448: fixed_text="A";
                12'd2449: fixed_text="L";
                12'd2450: fixed_text="L";
                12'd2452: fixed_text="E";
                12'd2453: fixed_text="V";
                12'd2454: fixed_text="E";
                12'd2455: fixed_text="N";
                12'd2456: fixed_text="T";
                12'd2560: fixed_text="H";
                12'd2561: fixed_text="O";
                12'd2562: fixed_text="L";
                12'd2563: fixed_text="D";
                12'd2565: fixed_text="K";
                12'd2566: fixed_text="1";
                12'd2568: fixed_text="C";
                12'd2569: fixed_text="L";
                12'd2570: fixed_text="O";
                12'd2571: fixed_text="S";
                12'd2572: fixed_text="E";
                12'd2575: fixed_text="B";
                12'd2576: fixed_text="O";
                12'd2577: fixed_text="T";
                12'd2578: fixed_text="H";
                12'd2580: fixed_text="1";
                12'd2581: fixed_text="S";
                12'd2583: fixed_text="M";
                12'd2584: fixed_text="E";
                12'd2585: fixed_text="N";
                12'd2586: fixed_text="U";
                12'd2688: fixed_text="F";
                12'd2689: fixed_text="R";
                12'd2690: fixed_text="A";
                12'd2691: fixed_text="M";
                12'd2692: fixed_text="E";
                12'd2698: fixed_text="R";
                12'd2699: fixed_text="E";
                12'd2700: fixed_text="F";
                12'd2706: fixed_text="C";
                12'd2707: fixed_text="O";
                12'd2708: fixed_text="U";
                12'd2709: fixed_text="N";
                12'd2710: fixed_text="T";
                default: ;
            endcase
        end
    endfunction
    reg [1:0] app_cfg,history_cfg,mode_cfg,noise_cfg,shape_cfg,event_cfg;
    reg [2:0] inspect_cfg;
    reg median_cfg,frozen_cfg,processing_cfg,auto_cfg,thick_cfg,menu_cfg,paused_cfg;
    reg [3:0] menu_index_cfg;
    reg [5:0] crossing_left;reg crossing_out;
    reg [15:0] numbers[0:10];
    reg [19:0] decimal[0:10];
    reg [35:0] convert_work;
    reg [3:0] convert_field;
    reg [3:0] convert_step;
    reg convert_busy;
    function automatic [35:0] bcd_step(input [35:0] work);
        reg [35:0] adjusted;integer digit;
        begin
            adjusted=work;
            for(digit=0;digit<5;digit=digit+1)
                if(adjusted[16+4*digit+:4]>=5)
                    adjusted[16+4*digit+:4]=adjusted[16+4*digit+:4]+4'd3;
            bcd_step={adjusted[34:0],1'b0};
        end
    endfunction
    wire [35:0] convert_next=bcd_step(convert_work);
    integer n;
    always @(posedge clk) begin
        if(rst) begin
            app_cfg<=0;history_cfg<=0;mode_cfg<=0;noise_cfg<=0;shape_cfg<=0;event_cfg<=0;
            inspect_cfg<=0;median_cfg<=1;frozen_cfg<=0;processing_cfg<=0;auto_cfg<=0;
            thick_cfg<=0;menu_cfg<=0;paused_cfg<=0;menu_index_cfg<=0;crossing_left<=0;crossing_out<=0;
            convert_work<=0;convert_field<=0;convert_step<=0;convert_busy<=0;
            for(n=0;n<11;n=n+1) begin numbers[n]<=0;decimal[n]<=0;end
        end else if(frame_start) begin
            // One brief event banner per real increment, measured in HDMI frames.
            // Clear/decrement, app exit and history entry cancel a stale banner.
            if((app_mode!=1 && app_mode!=3)||history_mode!=0||count_in<numbers[1]||count_out<numbers[2])
                crossing_left<=0;
            else if(count_in>numbers[1]||count_out>numbers[2]) begin
                crossing_left<=30;crossing_out<=count_in<=numbers[1];
            end else if(crossing_left!=0) crossing_left<=crossing_left-1'b1;
            app_cfg<=app_mode;history_cfg<=history_mode;mode_cfg<=mode;noise_cfg<=noise_level;
            shape_cfg<=shape;event_cfg<=event_status;inspect_cfg<=inspect_status;
            median_cfg<=median_enable;frozen_cfg<=frozen;processing_cfg<=processing;
            auto_cfg<=auto_enable;thick_cfg<=thick_enable;menu_cfg<=menu_open;
            paused_cfg<=history_paused;menu_index_cfg<=menu_index;
            numbers[0]<={5'd0,threshold};numbers[1]<=count_in;numbers[2]<=count_out;
            numbers[3]<={8'd0,capture_fps};numbers[4]<={8'd0,processing_fps};
            numbers[5]<=processing_ms;numbers[6]<=inspect_missing;numbers[7]<=inspect_extra;
            numbers[8]<={10'd0,selected_index};numbers[9]<={10'd0,reference_index};numbers[10]<={9'd0,history_count};
            convert_work<={20'd0,5'd0,threshold};convert_field<=0;convert_step<=0;convert_busy<=1;
        end else if(convert_busy) begin
            if(convert_step==15) begin
                decimal[convert_field]<=convert_next[35:16];convert_step<=0;
                if(convert_field==10) convert_busy<=0;
                else begin convert_field<=convert_field+1'b1;convert_work<={20'd0,numbers[convert_field+1'b1]};end
            end else begin convert_work<=convert_next;convert_step<=convert_step+1'b1;end
        end
    end
    function automatic [7:0] digit_text(input [19:0] bcd,input [2:0] col);
        begin
            case(col)
                0:digit_text="0"+bcd[19:16];1:digit_text="0"+bcd[15:12];
                2:digit_text="0"+bcd[11:8];3:digit_text="0"+bcd[7:4];
                4:digit_text="0"+bcd[3:0];default:digit_text=" ";
            endcase
        end
    endfunction
    wire [10:0] lx=x-11'd8;
    reg [10:0] ly;
    reg [4:0] line;
    reg text_large,overlay;
    reg [6:0] character;
    reg [2:0] column,row;
    reg [7:0] ascii;
    reg [23:0] ink,background;
    always @* begin
        line=31;ly=0;text_large=0;
        if(y>=8 && y<40) begin line=0;ly=y-11'd8;text_large=1;end
        else if(y>=48 && y<64) begin line=1;ly=y-11'd48;end
        else if(y>=64 && y<80) begin line=2;ly=y-11'd64;end
        else if(y>=88 && y<120) begin line=3;ly=y-11'd88;text_large=1;end
        else if(y>=120 && y<136 && app_cfg==2) begin line=4;ly=y-11'd120;end
        else if(y>=144 && y<160) begin line=5;ly=y-11'd144;end
        else if(y>=160 && y<176) begin line=6;ly=y-11'd160;end
        else if(y>=184 && y<200) begin line=7;ly=y-11'd184;end
        else if(y>=200 && y<216 && history_cfg!=0) begin line=21;ly=y-11'd200;end
        else if(y>=216 && y<248 && noise_cfg!=0) begin line=8;ly=y-11'd216;text_large=1;end
        else if(!menu_cfg && crossing_left!=0 && (app_cfg==1||app_cfg==3) && history_cfg==0 && y>=248 && y<280) begin line=22;ly=y-11'd248;text_large=1;end
        else if(menu_cfg && y>=272 && y<304) begin line=9;ly=y-11'd272;text_large=1;end
        else if(menu_cfg && y>=320 && y<640) begin
            line=10+((y-11'd320)>>5);ly=(y-11'd320)&11'd31;
            if(ly>=16) line=31;
        end else if(menu_cfg && y>=656 && y<672) begin line=20;ly=y-11'd656;end
        character=text_large?{1'b0,lx[10:5]}:lx[10:4];
        column=text_large?lx[4:2]:lx[3:1];row=text_large?ly[4:2]:ly[3:1];
        overlay=in_de && x>=8 && x<936 && line!=31;
        ascii=fixed_text(line,character);ink=24'hffffff;background=24'h101820;
        case(line)
            0:begin
                if(character>=4 && character<11) ascii=app_text({1'b0,app_cfg},character-7'd4);
                if(character>=19 && character<28) ascii=shape_text({1'b0,shape_cfg},character-7'd19);
                ink=shape_cfg==0?24'hb0beca:24'hffe000;
            end
            1:begin
                if(character==5) ascii="0"+mode_cfg;
                if(character>=7 && character<12) ascii=algo_text({2'd0,mode_cfg[0]},character-7'd7);
                if(character>=13 && character<19) ascii=edge_text({2'd0,mode_cfg[1]},character-7'd13);
                if(character>=24 && character<28) ascii=digit_text(decimal[0],character-7'd23);
                if(character>=29 && character<33) ascii=auto_text({2'd0,auto_cfg},character-7'd29);
            end
            2:begin
                if(character>=4 && character<7) ascii=on_text({2'd0,median_cfg},character-7'd4);
                if(character>=14 && character<18) ascii=noise_text({1'b0,noise_cfg},character-7'd14);
                if(character==25) ascii=thick_cfg?"3":"1";
                if(character>=32 && character<36) ascii=freeze_text({2'd0,frozen_cfg},character-7'd32);
                if(character>=37 && character<42) ascii=busy_text({2'd0,processing_cfg},character-7'd37);
            end
            3:begin
                case(app_cfg)
                    0:case(character)
                        0:ascii="L";1:ascii="I";2:ascii="V";3:ascii="E";
                        5:ascii="E";6:ascii="D";7:ascii="G";8:ascii="E";
                        10:ascii="M";11:ascii="O";12:ascii="N";13:ascii="I";14:ascii="T";15:ascii="O";16:ascii="R";
                        default:ascii=" ";endcase
                    1:begin
                        if(character==0)ascii="I";else if(character==1)ascii="N";
                        else if(character>=3 && character<8)ascii=digit_text(decimal[1],character-7'd3);
                        else if(character==9)ascii="O";else if(character==10)ascii="U";else if(character==11)ascii="T";
                        else if(character>=13 && character<18)ascii=digit_text(decimal[2],character-7'd13);
                    end
                    2:begin
                        if(character<7) ascii=app_text(3'd2,character);
                        if(character>=8 && character<14) ascii=inspect_text(inspect_cfg,character-7'd8);
                        ink=inspect_cfg==3?24'h80ff80:inspect_cfg==4?24'hff6040:24'hffcf60;
                    end
                    3:begin
                        if(character<4)ascii=app_text(3'd3,character);
                        if(character>=5 && character<14)ascii=face_text({2'd0,shape_cfg==3},character-7'd5);
                        ink=shape_cfg==3?24'hffe000:24'hb0beca;
                    end
                endcase
            end
            4:begin
                if(character>=5 && character<10)ascii=digit_text(decimal[6],character-7'd5);
                if(character>=17 && character<22)ascii=digit_text(decimal[7],character-7'd17);
            end
            5:begin
                if(character>=4 && character<7)ascii=digit_text(decimal[3],character-7'd2);
                if(character>=16 && character<19)ascii=digit_text(decimal[4],character-7'd14);
                if(character>=29 && character<34)ascii=digit_text(decimal[5],character-7'd29);
                ink=24'h80d8ff;
            end
            6:begin
                if(character>=6 && character<13)ascii=event_text({1'b0,event_cfg},character-7'd6);
                if(character>=19 && character<26)ascii=history_text({1'b0,history_cfg},character-7'd19);
                if(character>=27 && character<32)ascii=run_text({2'd0,paused_cfg},character-7'd27);
                ink=event_cfg==3?24'hffb040:24'hb0beca;
            end
            7:begin ascii=hint_text(menu_cfg?3'd2:history_cfg!=0?3'd1:3'd0,character);ink=24'h80ff80;end
            8:begin
                if(character>=11 && character<15)ascii=noise_text({1'b0,noise_cfg},character-7'd11);
                ink=24'hffb040;
            end
            9:ink=24'h80d8ff;
            10,11,12,13,14,15,16,17,18,19:begin
                if(line-10==menu_index_cfg) begin background=24'h174e70;ink=24'hffff80;if(character==0)ascii=">";end
                if(line==10 && character>=10 && character<17)ascii=app_text({1'b0,app_cfg},character-7'd10);
                if(line==11)begin
                    if(character==10)ascii="0"+mode_cfg;
                    if(character>=12 && character<17)ascii=algo_text({2'd0,mode_cfg[0]},character-7'd12);
                    if(character>=18 && character<24)ascii=edge_text({2'd0,mode_cfg[1]},character-7'd18);
                end
                if(line==12 && character>=10 && character<13)ascii=on_text({2'd0,auto_cfg},character-7'd10);
                if(line==13 && character>=10 && character<14)ascii=digit_text(decimal[0],character-7'd9);
                if(line==14 && character>=10 && character<13)ascii=on_text({2'd0,median_cfg},character-7'd10);
                if(line==15 && character>=10 && character<14)ascii=noise_text({1'b0,noise_cfg},character-7'd10);
                if(line==16 && character==10)ascii=thick_cfg?"3":"1";
            end
            22:begin ascii=crossing_text(crossing_out,character);ink=24'h101820;background=24'hffe000;end
            20:ink=24'h80ff80;
            21:begin
                if(character>=6 && character<9)ascii=digit_text(decimal[8],character-7'd4);
                if(character>=14 && character<17)ascii=digit_text(decimal[9],character-7'd12);
                if(character>=24 && character<27)ascii=digit_text(decimal[10],character-7'd22);
                ink=24'h80d8ff;
            end
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

