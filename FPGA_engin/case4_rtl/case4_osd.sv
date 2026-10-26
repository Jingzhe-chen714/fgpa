`timescale 1ns/1ps
// Zero-latency status overlay; x/y and RGB must describe the same sample.
// The parent must pass frame-stable configuration and detection results.
// Status uses doubled 5x7 glyphs (16x16 cells). The separate target banner
// uses fourfold glyphs (32x32 cells), with full CIRCLE / RECTANGLE names.
// frozen means the USER freeze request, not the Canny engine's internal lock.
// shape: 0 NONE, 1 CIRCLE, 2 RECTANGLE; other values show UNKNOWN.
module case4_osd (
    input wire [10:0] x,
    input wire [10:0] y,
    input wire [23:0] in_rgb,
    input wire in_de,
    input wire [10:0] threshold,
    input wire [1:0] mode,
    input wire median_enable,
    input wire frozen,
    input wire processing,
    input wire [1:0] shape,
    output reg [23:0] out_rgb
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
                default: font=0;
            endcase
        end
    endfunction

    // Binary-to-BCD shift/add network: no division or multipliers.
    reg [15:0] bcd;
    integer i,j;
    always_comb begin
        bcd=0;
        for (i=10;i>=0;i=i-1) begin
            for (j=0;j<4;j=j+1)
                if (bcd[j*4 +: 4]>=5) bcd[j*4 +: 4]=bcd[j*4 +: 4]+4'd3;
            bcd={bcd[14:0],threshold[i]};
        end
    end
    wire [10:0] local_x=x-11'd8;
    wire [10:0] local_y=y-11'd8;
    wire [10:0] banner_y=y-11'd48;
    wire banner=y>=48 && y<80;
    wire [6:0] character=banner?{1'b0,local_x[10:5]}:local_x[10:4];
    wire [2:0] column=banner?local_x[4:2]:local_x[3:1];
    wire [2:0] row=banner?banner_y[4:2]:local_y[3:1];
    reg [7:0] ascii;
    reg [34:0] glyph;
    reg [23:0] ink;
    always @* begin
        ascii=" ";
        ink=24'hffffff;
        if (banner) begin
            ink=shape==1 || shape==2 ? 24'hffe000 : 24'hb0beca;
            case(character)
                0: ascii="T"; 1: ascii="A"; 2: ascii="R";
                3: ascii="G"; 4: ascii="E"; 5: ascii="T";
                7: ascii=shape==1?"C":shape==2?"R":shape==0?"N":"U";
                8: ascii=shape==1?"I":shape==2?"E":shape==0?"O":"N";
                9: ascii=shape==1?"R":shape==2?"C":shape==0?"N":"K";
                10: ascii=shape==1?"C":shape==2?"T":shape==0?"E":"N";
                11: ascii=shape==1?"L":shape==2?"A":shape==3?"O":" ";
                12: ascii=shape==1?"E":shape==2?"N":shape==3?"W":" ";
                13: ascii=shape==2?"G":shape==3?"N":" ";
                14: ascii=shape==2?"L":" ";
                15: ascii=shape==2?"E":" ";
                default: ascii=" ";
            endcase
        end else if (!local_y[4]) begin
            if(character==5) ink=24'h80d8ff;
            if(character>=20&&character<=22) ink=median_enable?24'h80ff80:24'hffb040;
            case (character)
                0: ascii="M"; 1: ascii="O"; 2: ascii="D"; 3: ascii="E";
                5: ascii="0"+{6'b0,mode};
                7: ascii="T"; 8: ascii="H"; 9: ascii="R";
                11: ascii="0"+bcd[15:12]; 12: ascii="0"+bcd[11:8];
                13: ascii="0"+bcd[7:4]; 14: ascii="0"+bcd[3:0];
                16: ascii="M"; 17: ascii="E"; 18: ascii="D";
                20: ascii="O"; 21: ascii=median_enable?"N":"F";
                22: ascii=median_enable?" ":"F";
                default: ascii=" ";
            endcase
        end else begin
            if(character>=18&&character<=21) ink=frozen?24'hffb040:24'h80ff80;
            case (character)
                0: ascii=mode[0]?"C":"S"; 1: ascii=mode[0]?"A":"O";
                2: ascii=mode[0]?"N":"B"; 3: ascii=mode[0]?"N":"E";
                4: ascii=mode[0]?"Y":"L";
                6: ascii=mode[1]?"B":"R"; 7: ascii=mode[1]?"I":"E";
                8: ascii=mode[1]?"N":"D"; 9: ascii=mode[1]?"A":" ";
                10: ascii=mode[1]?"R":" "; 11: ascii=mode[1]?"Y":" ";
                13: ascii="U";14: ascii="S";15: ascii="E";16: ascii="R";
                18: ascii=frozen?"H":"L";19: ascii=frozen?"O":"I";
                20: ascii=frozen?"L":"V";21: ascii=frozen?"D":"E";
                23: ascii=processing?"B":"R";24: ascii=processing?"U":"E";
                25: ascii=processing?"S":"A";26: ascii=processing?"Y":"D";
                27: ascii=processing?" ":"Y";
                default: ascii=" ";
            endcase
        end
        glyph=font(ascii);
        out_rgb=in_rgb;
        if (in_de && x>=8 && x<592 && ((y>=8 && y<40)||banner)) begin
            out_rgb=24'h101820;
            if (column<5 && row<7 && glyph[34-row*5-column])
                out_rgb=ink;
        end
    end
endmodule
