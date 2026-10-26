`timescale 1ns/1ps
// Finite 16x16 Chinese glyphs; raster doubled to 32x32 for 1080p readability.
// Both bypass and OSD paths have the same fixed three-clock latency.
module case4_v10_osd #(
 parameter FONT_FILE="case4_rtl/v10_font.hex",TEXT_FILE="case4_rtl/v10_text.hex"
)(
 input wire clk,rst,enable,in_hs,in_vs,in_de,input wire [10:0] x,y,input wire [23:0] in_rgb,
 input wire [2:0] mode,input wire [10:0] threshold,input wire menu_open,input wire [4:0] menu_index,
 input wire link_lost,unsupported,fault,input wire [511:0] status,
 output reg out_hs,out_vs,out_de,output reg [23:0] out_rgb
);
 reg [15:0] font_rom[0:2112-1];reg [7:0] text_rom[0:1536-1];
 initial begin $readmemh(FONT_FILE,font_rom);$readmemh(TEXT_FILE,text_rom);end
 wire in_area=enable&&in_de&&x>=24&&x<1048&&y>=24&&y<224;
 wire [10:0] yy=y-24,xx=x-24;
 wire [2:0] line=yy/40;wire [4:0] col=xx>>5;wire [3:0] gy=(yy%40)>>1,gx=xx[4:1];
 reg [5:0] textline;reg row_active;reg [3:0] value_kind;reg value_numeric;reg [10:0] value_number;
 always @*begin
  value_kind=12;value_numeric=0;value_number=0;
  case(menu_index)
   0:value_kind=status[23:16]==3?3:2;
   1:begin value_numeric=1;value_number={8'd0,mode};end
   2:begin value_numeric=1;value_number=threshold;end
   3:value_kind=status[47:40]==0?0:status[47:40]==1?4:5;
   4:value_kind=status[32]?1:0;5:value_kind=status[35]?1:0;
   6:value_kind=status[24]?1:0;7:value_kind=status[38]?1:0;8:value_kind=status[39]?1:0;
   9:value_kind=status[55:48]==0?0:status[55:48]==1?6:7;
   10:value_kind=status[63:56]==0?8:status[63:56]==1?9:10;
   11:value_kind=status[33]?1:0;12:value_kind=status[34]?1:0;
   15:begin value_numeric=1;value_number=status[90:80];end
   16:begin value_numeric=1;value_number=status[106:96];end
   17:begin value_numeric=1;value_number=status[122:112]-status[90:80]+1'b1;end
   18:begin value_numeric=1;value_number=status[138:128]-status[106:96]+1'b1;end
   20,21,22,23:value_kind=11;
   24:value_kind=status[37]?1:0;
   default:value_kind=12;
  endcase
 end
 reg [3:0] vthousands,vhundreds,vtens,vones;

 always @*begin
  textline=0;row_active=in_area&&(yy%40)<32;
  case(line)
   0:textline=0;
   1:textline=fault?7:link_lost?1:unsupported?2:3;
   2:textline=4;
   3:begin textline=8+menu_index;row_active=row_active&&menu_open;end
   4:begin textline=6;row_active=row_active&&menu_open;end
   default:row_active=0;
  endcase
 end
 wire value_area=line==3&&col>=18;
 wire [10:0] text_address=value_area?((11'd33+value_kind)*32+col-18):{textline,5'd0}+col;
 reg [10:0] glyph_address;
 reg [7:0] glyph;reg [3:0] gy1,gx1,gx2;reg [15:0] bits;
 reg h1,v1,d1,h2,v2,d2,box1,box2;reg [23:0] rgb1,rgb2;
 reg [3:0] thousands,hundreds,tens,ones;
 always @*begin
  glyph_address=text_address;
  if(value_area&&value_numeric)case(col)
   18:glyph_address=1504+vthousands;19:glyph_address=1504+vhundreds;
   20:glyph_address=1504+vtens;21:glyph_address=1504+vones;
   default:glyph_address=1504+10;
  endcase
  if(line==0)case(col)
   10:glyph_address=1504+mode;
   15:glyph_address=1504+thousands;
   16:glyph_address=1504+hundreds;
   17:glyph_address=1504+tens;
   18:glyph_address=1504+ones;
   default:;
  endcase
 end
 // One unconditionally clocked ROM output permits RAM inference. Dynamic
 // digits select ROM addresses too; pixel/sync latency remains three clocks.
 always @(posedge clk)glyph<=text_rom[glyph_address];
 always @(posedge clk)begin
  if(rst)begin gy1<=0;gx1<=0;gx2<=0;bits<=0;h1<=1;v1<=1;d1<=0;h2<=1;v2<=1;d2<=0;
   box1<=0;box2<=0;rgb1<=0;rgb2<=0;out_hs<=1;out_vs<=1;out_de<=0;out_rgb<=0;
   thousands<=0;hundreds<=0;tens<=0;ones<=0;vthousands<=0;vhundreds<=0;vtens<=0;vones<=0;
  end else begin
   thousands<=threshold/1000;hundreds<=(threshold/100)%10;tens<=(threshold/10)%10;ones<=threshold%10;
   vthousands<=value_number/1000;vhundreds<=(value_number/100)%10;vtens<=(value_number/10)%10;vones<=value_number%10;
   gy1<=gy;gx1<=gx;box1<=row_active;h1<=in_hs;v1<=in_vs;d1<=in_de;rgb1<=in_rgb;
   bits<=font_rom[{glyph,4'd0}+gy1];gx2<=gx1;box2<=box1;h2<=h1;v2<=v1;d2<=d1;rgb2<=rgb1;
   out_hs<=h2;out_vs<=v2;out_de<=d2;
   out_rgb<=!d2?24'd0:box2?(bits[15-gx2]?24'hffffff:{3'b0,rgb2[23:19],3'b0,rgb2[15:11],3'b0,rgb2[7:3]}):rgb2;
  end
 end
endmodule
