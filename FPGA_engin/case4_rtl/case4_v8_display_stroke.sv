`timescale 1ns/1ps
// Centered display-only3x3 dilation. Keep the exact source RGB at genuine
// edge pixels (including yellow/blue geometry); only newly covered neighbours
// receive red/white. The enable flag is per-pixel, already gated by VIEW/APP/ROI.
// Metadata and sync take exactly HT+7 registers: sampleN -> outputN+HT+6.
// Two historical1bit rows plus a30bit raster delay; no full frame storage.
// Reconstruct XY from delayed VS/DE instead of storing22 redundant coordinate
// bits per clock. Input raster must contain W contiguous pixels per line and
// H lines per frame. Output XY is native during DE and zero during blanking.
module case4_v8_display_stroke #(
 parameter integer W=1920,H=1080,HT=2200,XB=$clog2(W),YB=$clog2(H)
)(
 input wire clk,rst,in_hs,in_vs,in_de,
 input wire [10:0] in_x,in_y,input wire [23:0] in_rgb,
 input wire in_edge,enable,stroke_white,
 output reg out_hs,out_vs,out_de,
 output reg [10:0] out_x,out_y,output reg [23:0] out_rgb
);
 wire wv,p00,p01,p02,p10,p11,p12,p20,p21,p22;
 wire [XB-1:0] wx;wire [YB-1:0] wy;
 case4_window3x3 #(.DATA_BITS(1),.IMG_WIDTH(W),.IMG_HEIGHT(H)) window(
  .clk(clk),.rst(rst),.in_valid(in_de&&in_vs),.in_x(in_x[XB-1:0]),.in_y(in_y[YB-1:0]),.in_pixel(in_edge),
  .out_valid(wv),.out_x(wx),.out_y(wy),.p00(p00),.p01(p01),.p02(p02),
  .p10(p10),.p11(p11),.p12(p12),.p20(p20),.p21(p21),.p22(p22));
 reg row0,row1,row2,joined,dilated;reg [2:0] valid;
 always @(posedge clk)begin
  if(rst)begin row0<=0;row1<=0;row2<=0;joined<=0;dilated<=0;valid<=0;end
  else begin
   row0<=p00|p01|p02;row1<=p10|p11|p12;row2<=p20|p21|p22;
   joined<=row0|row1|row2;dilated<=joined;valid<={valid[1:0],wv};
  end
 end
 wire [29:0] delayed;wire ready;
 case4_raster_delay #(.WIDTH(30),.STAGES(HT+6)) metadata(
  clk,rst,{in_hs,in_vs,in_de,in_rgb,in_edge,enable,stroke_white},delayed,ready);
 wire [XB-1:0] delayed_x;wire [YB-1:0] delayed_y;
 case4_raster_xy #(.W(W),.H(H)) coordinates(
  clk,rst||!ready,delayed[28],delayed[27],delayed_x,delayed_y);
 always @(posedge clk)begin
  if(rst||!ready)begin out_hs<=1;out_vs<=1;out_de<=0;out_x<=0;out_y<=0;out_rgb<=0;end
  else begin
   {out_hs,out_vs,out_de}<=delayed[29:27];
   out_x<=delayed[27]?delayed_x:0;out_y<=delayed[27]?delayed_y:0;
   out_rgb<=delayed[27]&&delayed[28]&&delayed[1]&&!delayed[2]&&valid[2]&&dilated?
     (delayed[0]?24'hffffff:24'hff0000):delayed[26:3];
  end
 end
endmodule
