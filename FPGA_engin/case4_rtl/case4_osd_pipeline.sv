`timescale 1ns/1ps
// Seven registered stages: BCD (4+4+3 shifts), character selection, font ROM,
// glyph bit selection, then RGB composition. All pixel/config/sync data take
// the same path. Input sampled at N appears after N+6 (seven registers);
// connecting after an existing registered stream adds seven clock periods.
// No BCD arithmetic is on the character/font/output RGB combinational path.
// Function/visual content matches case4_osd; x/y both support native 1080p.
module case4_osd_pipeline (
    input wire clk,rst,in_hs,in_vs,in_de,
    input wire [10:0] x,y,
    input wire [23:0] in_rgb,
    input wire [10:0] threshold,
    input wire [1:0] mode,
    input wire median_enable,frozen,processing,
    input wire [1:0] shape,
    output reg out_hs,out_vs,out_de,
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


    function automatic [26:0] bcd_step(input [26:0] work);
        reg [26:0] adjusted;
        integer digit;
        begin
            adjusted=work;
            for(digit=0;digit<4;digit=digit+1)
                if(adjusted[11+4*digit +: 4]>=5)
                    adjusted[11+4*digit +: 4]=adjusted[11+4*digit +: 4]+4'd3;
            bcd_step={adjusted[25:0],1'b0};
        end
    endfunction
    reg [26:0] decimal0,decimal1,decimal2;
    reg [55:0] meta0,meta1,meta2;
    wire [15:0] bcd2=decimal2[26:11];
    wire h2,v2,d2,median2,frozen2,processing2;
    wire [23:0] rgb2;
    wire [10:0] x2,y2;
    wire [1:0] mode2,shape2;
    assign {h2,v2,d2,rgb2,x2,y2,mode2,median2,frozen2,processing2,shape2}=meta2;
    always @(posedge clk) begin
        if(rst) begin
            decimal0<=0;decimal1<=0;decimal2<=0;
            meta0<={3'b110,53'd0};meta1<={3'b110,53'd0};meta2<={3'b110,53'd0};
        end else begin
            decimal0<=bcd_step(bcd_step(bcd_step(bcd_step({16'd0,threshold}))));
            decimal1<=bcd_step(bcd_step(bcd_step(bcd_step(decimal0))));
            decimal2<=bcd_step(bcd_step(bcd_step(decimal1)));
            meta0<={in_hs,in_vs,in_de,in_rgb,x,y,mode,median_enable,frozen,processing,shape};
            meta1<=meta0;meta2<=meta1;
        end
    end
    wire [10:0] local_x=x2-11'd8;
    wire [10:0] local_y=y2-11'd8;
    wire [10:0] banner_y=y2-11'd48;
    wire banner=y2>=48 && y2<80;
    wire [6:0] character=banner?{1'b0,local_x[10:5]}:local_x[10:4];
    wire [2:0] column=banner?local_x[4:2]:local_x[3:1];
    wire [2:0] row=banner?banner_y[4:2]:local_y[3:1];
    reg [7:0] ascii;
    reg [23:0] ink;
    always @* begin
        ascii=" ";
        ink=24'hffffff;
        if (banner) begin
            ink=shape2==1 || shape2==2 ? 24'hffe000 : 24'hb0beca;
            case(character)
                0: ascii="T"; 1: ascii="A"; 2: ascii="R";
                3: ascii="G"; 4: ascii="E"; 5: ascii="T";
                7: ascii=shape2==1?"C":shape2==2?"R":shape2==0?"N":"U";
                8: ascii=shape2==1?"I":shape2==2?"E":shape2==0?"O":"N";
                9: ascii=shape2==1?"R":shape2==2?"C":shape2==0?"N":"K";
                10: ascii=shape2==1?"C":shape2==2?"T":shape2==0?"E":"N";
                11: ascii=shape2==1?"L":shape2==2?"A":shape2==3?"O":" ";
                12: ascii=shape2==1?"E":shape2==2?"N":shape2==3?"W":" ";
                13: ascii=shape2==2?"G":shape2==3?"N":" ";
                14: ascii=shape2==2?"L":" ";
                15: ascii=shape2==2?"E":" ";
                default: ascii=" ";
            endcase
        end else if (!local_y[4]) begin
            if(character==5) ink=24'h80d8ff;
            if(character>=20&&character<=22) ink=median2?24'h80ff80:24'hffb040;
            case (character)
                0: ascii="M"; 1: ascii="O"; 2: ascii="D"; 3: ascii="E";
                5: ascii="0"+{6'b0,mode2};
                7: ascii="T"; 8: ascii="H"; 9: ascii="R";
                11: ascii="0"+bcd2[15:12]; 12: ascii="0"+bcd2[11:8];
                13: ascii="0"+bcd2[7:4]; 14: ascii="0"+bcd2[3:0];
                16: ascii="M"; 17: ascii="E"; 18: ascii="D";
                20: ascii="O"; 21: ascii=median2?"N":"F";
                22: ascii=median2?" ":"F";
                default: ascii=" ";
            endcase
        end else begin
            if(character>=18&&character<=21) ink=frozen2?24'hffb040:24'h80ff80;
            case (character)
                0: ascii=mode2[0]?"C":"S"; 1: ascii=mode2[0]?"A":"O";
                2: ascii=mode2[0]?"N":"B"; 3: ascii=mode2[0]?"N":"E";
                4: ascii=mode2[0]?"Y":"L";
                6: ascii=mode2[1]?"B":"R"; 7: ascii=mode2[1]?"I":"E";
                8: ascii=mode2[1]?"N":"D"; 9: ascii=mode2[1]?"A":" ";
                10: ascii=mode2[1]?"R":" "; 11: ascii=mode2[1]?"Y":" ";
                13: ascii="U";14: ascii="S";15: ascii="E";16: ascii="R";
                18: ascii=frozen2?"H":"L";19: ascii=frozen2?"O":"I";
                20: ascii=frozen2?"L":"V";21: ascii=frozen2?"D":"E";
                23: ascii=processing2?"B":"R";24: ascii=processing2?"U":"E";
                25: ascii=processing2?"S":"A";26: ascii=processing2?"Y":"D";
                27: ascii=processing2?" ":"Y";
                default: ascii=" ";
            endcase
        end
    end

    reg [7:0] ascii3;
    reg [2:0] column3,row3,column4,row4;
    reg [34:0] glyph4;
    reg overlay3,overlay4,overlay5,pixel5;
    reg [23:0] ink3,ink4,ink5;
    reg [26:0] video3,video4,video5;
    always @(posedge clk) begin
        if(rst) begin
            ascii3<=0;column3<=0;row3<=0;column4<=0;row4<=0;glyph4<=0;
            overlay3<=0;overlay4<=0;overlay5<=0;pixel5<=0;
            ink3<=0;ink4<=0;ink5<=0;
            video3<={3'b110,24'd0};video4<={3'b110,24'd0};video5<={3'b110,24'd0};
            out_hs<=1;out_vs<=1;out_de<=0;out_rgb<=0;
        end else begin
            // Stage 4: geometry/status selection, no font/BCD chain.
            ascii3<=ascii;column3<=column;row3<=row;ink3<=ink;
            overlay3<=d2 && x2>=8 && x2<592 && ((y2>=8 && y2<40)||banner);
            video3<={h2,v2,d2,rgb2};
            // Stage 5: a small constant character ROM.
            glyph4<=font(ascii3);column4<=column3;row4<=row3;
            overlay4<=overlay3;ink4<=ink3;video4<=video3;
            // Stage 6: select the rendered dot; RGB still passes untouched.
            pixel5<=column4<5 && row4<7 && glyph4[34-row4*5-column4];
            overlay5<=overlay4;ink5<=ink4;video5<=video4;
            // Stage 7: final 24-bit mux, with identical HS/VS/DE latency.
            {out_hs,out_vs,out_de}<=video5[26:24];
            out_rgb<=overlay5?(pixel5?ink5:24'h101820):video5[23:0];
        end
    end
endmodule
