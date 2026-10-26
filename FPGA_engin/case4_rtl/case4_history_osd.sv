`timescale 1ns/1ps
// Seven registered stages: decimal conversion (3), character selection,
// font lookup, glyph bit, RGB. Pixel/sync/config take identical paths.
// Sampled at N, output after N+6. With history_mode=0 pixels pass unchanged.
// selected/reference are zero-based slots; the OSD displays decimal 001..064.
module case4_history_osd (
    input wire clk, rst, in_hs, in_vs, in_de,
    input wire [10:0] x, y,
    input wire [23:0] in_rgb,
    input wire [1:0] history_mode,
    input wire ready, paused,
    input wire [6:0] count,
    input wire [5:0] selected, reference,
    input wire [7:0] threshold,
    output reg out_hs, out_vs, out_de,
    output reg [23:0] out_rgb
);
    function automatic [34:0] font(input [7:0] c);
        begin
            case(c)
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
                "C": font={5'b01110,5'b10001,5'b10000,5'b10000,5'b10000,5'b10001,5'b01110};
                "D": font={5'b11110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b11110};
                "E": font={5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b11111};
                "F": font={5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b10000};
                "H": font={5'b10001,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
                "I": font={5'b01110,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110};
                "K": font={5'b10001,5'b10010,5'b10100,5'b11000,5'b10100,5'b10010,5'b10001};
                "L": font={5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b11111};
                "M": font={5'b10001,5'b11011,5'b10101,5'b10101,5'b10001,5'b10001,5'b10001};
                "N": font={5'b10001,5'b11001,5'b10101,5'b10011,5'b10001,5'b10001,5'b10001};
                "O": font={5'b01110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
                "P": font={5'b11110,5'b10001,5'b10001,5'b11110,5'b10000,5'b10000,5'b10000};
                "R": font={5'b11110,5'b10001,5'b10001,5'b11110,5'b10100,5'b10010,5'b10001};
                "S": font={5'b01111,5'b10000,5'b10000,5'b01110,5'b00001,5'b00001,5'b11110};
                "T": font={5'b11111,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100};
                "U": font={5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
                "V": font={5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01010,5'b00100};
                "W": font={5'b10001,5'b10001,5'b10001,5'b10101,5'b10101,5'b11011,5'b10001};
                "X": font={5'b10001,5'b10001,5'b01010,5'b00100,5'b01010,5'b10001,5'b10001};
                "Y": font={5'b10001,5'b10001,5'b01010,5'b00100,5'b00100,5'b00100,5'b00100};
                "/": font={5'b00001,5'b00001,5'b00010,5'b00100,5'b01000,5'b10000,5'b10000};
                default: font=0;
            endcase
        end
    endfunction
    function automatic [19:0] bcd_step(input [19:0] work);
        reg [19:0] adjusted;
        integer digit;
        begin
            adjusted=work;
            for(digit=0;digit<3;digit=digit+1)
                if(adjusted[8+4*digit +: 4]>=5)
                    adjusted[8+4*digit +: 4]=adjusted[8+4*digit +: 4]+4'd3;
            bcd_step={adjusted[18:0],1'b0};
        end
    endfunction
    reg [19:0] decimal0[0:3], decimal1[0:3], decimal2[0:3];
    reg [52:0] meta0,meta1,meta2;
    wire h2,v2,d2,ready2,paused2;
    wire [23:0] rgb2;
    wire [10:0] x2,y2;
    wire [1:0] mode2;
    assign {h2,v2,d2,rgb2,x2,y2,mode2,ready2,paused2}=meta2;
    wire [7:0] number[0:3];
    assign number[0]={1'b0,count};
    assign number[1]=count==0 ? 8'd0 : {2'b0,selected}+8'd1;
    assign number[2]=count==0 ? 8'd0 : {2'b0,reference}+8'd1;
    assign number[3]=threshold;
    integer n;
    always @(posedge clk) begin
        if(rst) begin
            meta0<={3'b110,50'd0};meta1<={3'b110,50'd0};meta2<={3'b110,50'd0};
            for(n=0;n<4;n=n+1) begin decimal0[n]<=0;decimal1[n]<=0;decimal2[n]<=0;end
        end else begin
            meta0<={in_hs,in_vs,in_de,in_rgb,x,y,history_mode,ready,paused};
            meta1<=meta0;meta2<=meta1;
            for(n=0;n<4;n=n+1) begin
                decimal0[n]<=bcd_step(bcd_step(bcd_step({12'd0,number[n]})));
                decimal1[n]<=bcd_step(bcd_step(bcd_step(decimal0[n])));
                decimal2[n]<=bcd_step(bcd_step(decimal1[n]));
            end
        end
    end
    wire [10:0] lx=x2-11'd8, ly=y2-11'd8;
    wire [5:0] character=lx[10:5];
    wire [1:0] line_no=ly[6:5];
    wire [2:0] column=lx[4:2], row=ly[4:2];
    wire panel=mode2!=0 && d2 && x2>=8 && x2<1160 && y2>=8 && y2<136;
    reg [7:0] ascii;
    reg [23:0] ink;
    always @* begin
        ascii=" ";
        ink=line_no==0 ? 24'hffe000 : line_no==1 ? (ready2?24'h80ff80:24'hffb040) : 24'hb0beca;
        case(line_no)
            0: if(mode2==1) begin
                case(character)
                    0:ascii="R";1:ascii="E";2:ascii="P";3:ascii="L";4:ascii="A";5:ascii="Y";
                    7:ascii="P";8:ascii=paused2?"A":"L";9:ascii=paused2?"U":"A";
                    10:ascii=paused2?"S":"Y";11:ascii=paused2?"E":" ";
                    13:ascii="F";14:ascii="R";15:ascii="A";16:ascii="M";17:ascii="E";
                    19:ascii="0"+decimal2[1][19:16];20:ascii="0"+decimal2[1][15:12];21:ascii="0"+decimal2[1][11:8];
                    22:ascii="/";
                    23:ascii="0"+decimal2[0][19:16];24:ascii="0"+decimal2[0][15:12];25:ascii="0"+decimal2[0][11:8];
                    default:ascii=" ";
                endcase
            end else begin
                case(character)
                    0:ascii="C";1:ascii="O";2:ascii="M";3:ascii="P";4:ascii="A";5:ascii="R";6:ascii="E";
                    8:ascii="F";9:ascii="R";10:ascii="A";11:ascii="M";12:ascii="E";
                    14:ascii="0"+decimal2[1][19:16];15:ascii="0"+decimal2[1][15:12];16:ascii="0"+decimal2[1][11:8];
                    18:ascii="R";19:ascii="E";20:ascii="F";
                    22:ascii="0"+decimal2[2][19:16];23:ascii="0"+decimal2[2][15:12];24:ascii="0"+decimal2[2][11:8];
                    default:ascii=" ";
                endcase
            end
            1: begin
                if(character<13) begin
                    if(ready2) begin
                        case(character)
                            0:ascii="R";1:ascii="E";2:ascii="A";3:ascii="D";4:ascii="Y";
                            default:ascii=" ";
                        endcase
                    end else begin
                        case(character)
                            0:ascii="W";1:ascii="A";2:ascii="I";3:ascii="T";
                            5:ascii="S";6:ascii="N";7:ascii="A";8:ascii="P";9:ascii="S";10:ascii="H";11:ascii="O";12:ascii="T";
                            default:ascii=" ";
                        endcase
                    end
                end else if(mode2==2) begin
                    case(character)
                        16:ascii="D";17:ascii="I";18:ascii="F";19:ascii="F";
                        21:ascii="0"+decimal2[3][19:16];22:ascii="0"+decimal2[3][15:12];23:ascii="0"+decimal2[3][11:8];
                        26:ascii="P";27:ascii=paused2?"A":"L";28:ascii=paused2?"U":"A";
                        29:ascii=paused2?"S":"Y";30:ascii=paused2?"E":" ";
                        default:ascii=" ";
                    endcase
                end
            end
            2: case(character)
                0:ascii="S";1:ascii="H";2:ascii="O";3:ascii="R";4:ascii="T";
                6:ascii="K";7:ascii="1";9:ascii="P";10:ascii="R";11:ascii="E";12:ascii="V";
                15:ascii="K";16:ascii="2";18:ascii="N";19:ascii="E";20:ascii="X";21:ascii="T";
                default:ascii=" ";
            endcase
            3: case(character)
                0:ascii="H";1:ascii="O";2:ascii="L";3:ascii="D";
                5:ascii="K";6:ascii="1";8:ascii="R";9:ascii="E";10:ascii="F";
                12:ascii="K";13:ascii="2";15:ascii="P";16:ascii="L";17:ascii="A";18:ascii="Y";
                20:ascii="2";21:ascii="S";23:ascii="K";24:ascii="1";
                26:ascii="S";27:ascii="C";28:ascii="R";29:ascii="E";30:ascii="E";31:ascii="N";
                default:ascii=" ";
            endcase
        endcase
    end
    reg h3,v3,d3,h4,v4,d4,h5,v5,d5;
    reg [23:0] rgb3,rgb4,rgb5,ink3,ink4,ink5;
    reg panel3,panel4,panel5;
    reg [7:0] ascii3;
    reg [2:0] row3,column3,row4,column4;
    reg [34:0] glyph4;
    reg lit5;
    always @(posedge clk) begin
        if(rst) begin
            h3<=1;v3<=1;d3<=0;h4<=1;v4<=1;d4<=0;h5<=1;v5<=1;d5<=0;
            rgb3<=0;rgb4<=0;rgb5<=0;ink3<=0;ink4<=0;ink5<=0;
            panel3<=0;panel4<=0;panel5<=0;ascii3<=0;
            row3<=0;column3<=0;row4<=0;column4<=0;glyph4<=0;lit5<=0;
            out_hs<=1;out_vs<=1;out_de<=0;out_rgb<=0;
        end else begin
            {h3,v3,d3,rgb3}<={h2,v2,d2,rgb2};
            panel3<=panel;ascii3<=ascii;ink3<=ink;row3<=row;column3<=column;
            {h4,v4,d4,rgb4}<={h3,v3,d3,rgb3};
            panel4<=panel3;glyph4<=font(ascii3);ink4<=ink3;row4<=row3;column4<=column3;
            {h5,v5,d5,rgb5}<={h4,v4,d4,rgb4};
            panel5<=panel4;ink5<=ink4;
            lit5<=row4<7 && column4<5 && glyph4[34-row4*5-column4];
            {out_hs,out_vs,out_de}<={h5,v5,d5};
            out_rgb<=panel5 ? (lit5?ink5:24'h101820) : rgb5;
        end
    end
endmodule
