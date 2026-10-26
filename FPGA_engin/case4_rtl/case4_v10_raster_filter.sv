`timescale 1ns/1ps
// Identical HT+7 raster latency for every setting. Full median uses standard
// Gaussian; OFF bypasses blur, SELECTIVE keeps 3/4 centre plus 1/4 Gaussian.
// OP=0 median; OP=1 Gaussian. Original RGB/gray sidebands never filtered.
module case4_v10_raster_filter #(
 parameter W=1920,H=1080,HT=2200,OP=0,XB=$clog2(W),YB=$clog2(H)
)(
 input wire clk,rst,input wire [1:0] mode,input wire in_hs,in_vs,in_de,
 input wire [7:0] in_pixel,input wire [31:0] in_meta,
 output reg out_hs,out_vs,out_de,output reg [7:0] out_pixel,
 output reg [31:0] out_meta
);
 wire [XB-1:0] x,wx;wire [YB-1:0] y,wy;
 case4_raster_xy #(.W(W),.H(H)) xy(clk,rst,in_vs,in_de,x,y);
 wire wv;wire [7:0] p00,p01,p02,p10,p11,p12,p20,p21,p22;
 case4_window3x3 #(.IMG_WIDTH(W),.IMG_HEIGHT(H)) win(
  .clk(clk),.rst(rst),.in_valid(in_de&&in_vs),.in_x(x),.in_y(y),.in_pixel(in_pixel),
  .out_valid(wv),.out_x(wx),.out_y(wy),.p00(p00),.p01(p01),.p02(p02),
  .p10(p10),.p11(p11),.p12(p12),.p20(p20),.p21(p21),.p22(p22));
 wire fv;wire [7:0] filtered;
 generate if(OP==0)begin:g_med
  case4_v9_selective_median #(.X_BITS(XB),.Y_BITS(YB)) med(
   .clk(clk),.rst(rst),.in_valid(wv),.mode(mode),.p00(p00),.p01(p01),.p02(p02),
   .p10(p10),.p11(p11),.p12(p12),.p20(p20),.p21(p21),.p22(p22),.out_valid(fv),.out_pixel(filtered));
 end else begin:g_gauss
  reg [9:0] row0,row1,row2;reg [11:0] sum;
  reg [7:0] centre0,centre1,result;reg [2:0] valid;reg [1:0] full_blur;
  wire [9:0] detail_sum={2'b0,sum[11:4]}+{1'b0,centre1,1'b0}+{2'b0,centre1}+10'd2;
  reg [1:0] mode0,mode1;
  always @(posedge clk)begin
   if(rst)begin row0<=0;row1<=0;row2<=0;sum<=0;centre0<=0;centre1<=0;
    result<=0;valid<=0;full_blur<=0;mode0<=0;mode1<=0;end
   else begin
    row0<={2'b0,p00}+{1'b0,p01,1'b0}+{2'b0,p02};
    row1<={2'b0,p10}+{1'b0,p11,1'b0}+{2'b0,p12};
    row2<={2'b0,p20}+{1'b0,p21,1'b0}+{2'b0,p22};
    sum<={2'b0,row0}+{1'b0,row1,1'b0}+{2'b0,row2}+12'd8;
    centre0<=p11;centre1<=centre0;mode0<=mode;mode1<=mode0;full_blur<={full_blur[0],mode==1};
    result<=mode1==0?centre1:full_blur[1]?sum[11:4]:detail_sum[9:2];valid<={valid[1:0],wv};
   end
  end
  assign fv=valid[2];assign filtered=result;
 end endgenerate
 wire [42:0] delayed;wire ready;
 case4_raster_delay #(.WIDTH(43),.STAGES(HT+6)) delay(
  clk,rst,{in_hs,in_vs,in_de,in_pixel,in_meta},delayed,ready);
 always @(posedge clk)begin
  if(rst||!ready)begin out_hs<=1;out_vs<=1;out_de<=0;out_meta<=0;out_pixel<=0;end
  else begin {out_hs,out_vs,out_de}<=delayed[42:40];out_meta<=delayed[31:0];
   out_pixel<=fv?filtered:delayed[39:32];end
 end
endmodule
