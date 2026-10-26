`timescale 1ns/1ps
// Identical HT+7 raster latency for every setting. FULL retains ordinary
// median/Gaussian for comparison; SELECTIVE uses a range-gated 3x3 kernel
// plus directional thin-line preservation. No extra line/frame buffer or DSP.
// Range gating replaces a dissimilar neighbour with the centre, retaining a
// constant denominator of 16. It is not a full exponential bilateral filter.
// V13: selective range gate 30 with an 11-level directional detail guard.
// This reduces screen-grid noise while retaining weak connected strokes.
// OFF/FULL/bilateral modes, all sidebands and raster latency are unchanged.
// OP=0 median; OP=1 Gaussian. Original RGB/gray sidebands never filtered.
module case4_v11_raster_filter #(
 parameter W=1920,H=1080,HT=2200,OP=0,XB=$clog2(W),YB=$clog2(H)
)(
 input wire clk,rst,input wire [1:0] mode,input wire in_hs,in_vs,in_de,
 input wire [7:0] in_pixel,input wire [31:0] in_meta,
 input wire[1:0] in_pair,input wire pair_view_enable,pair_bilateral_enable,
 input wire in_change,contour_view_enable,
 output reg out_hs,out_vs,out_de,output reg [7:0] out_pixel,
 output reg [31:0] out_meta,output reg out_change,output reg[1:0] out_pair
);
 wire [XB-1:0] x,wx;wire [YB-1:0] y,wy;
 case4_raster_xy #(.W(W),.H(H)) xy(clk,rst,in_vs,in_de,x,y);
 wire wv;wire [7:0] p00,p01,p02,p10,p11,p12,p20,p21,p22;
 localparam WIN_BITS=11;
 wire[WIN_BITS-1:0] w00,w01,w02,w10,w11,w12,w20,w21,w22;
 wire[WIN_BITS-1:0] window_pixel={in_pixel,in_pair,in_change};
 case4_window3x3 #(.DATA_BITS(WIN_BITS),.IMG_WIDTH(W),.IMG_HEIGHT(H)) win(
  .clk(clk),.rst(rst),.in_valid(in_de&&in_vs),.in_x(x),.in_y(y),.in_pixel(window_pixel),
  .out_valid(wv),.out_x(wx),.out_y(wy),.p00(w00),.p01(w01),.p02(w02),
  .p10(w10),.p11(w11),.p12(w12),.p20(w20),.p21(w21),.p22(w22));
 assign p00=w00>>3;assign p01=w01>>3;assign p02=w02>>3;
 assign p10=w10>>3;assign p11=w11>>3;assign p12=w12>>3;
 assign p20=w20>>3;assign p21=w21>>3;assign p22=w22>>3;
 wire[23:0] pair_rgb;wire pair_valid;wire[7:0] bilateral_gray;
 generate if(OP==1)begin:g_pair
  case4_v11_pair_bilateral pair_filter(.clk(clk),.rst(rst),.in_valid(wv),.enable(pair_bilateral_enable),.pair_view_enable(pair_view_enable),
   .p00(w00[2:1]),.p01(w01[2:1]),.p02(w02[2:1]),.p10(w10[2:1]),.p11(w11[2:1]),.p12(w12[2:1]),
   .p20(w20[2:1]),.p21(w21[2:1]),.p22(w22[2:1]),
   .g00(p00),.g01(p01),.g02(p02),.g10(p10),.g11(p11),.g12(p12),.g20(p20),.g21(p21),.g22(p22),
   .out_valid(pair_valid),.out_rgb(pair_rgb),.out_gray(bilateral_gray));
 end else begin:g_no_pair assign pair_rgb=0;assign pair_valid=0;assign bilateral_gray=0;end endgenerate
 // Share both spatial windows with the original change contour: 5/9
 // majority followed by an inner boundary, with a two-pixel native margin.
 reg[1:0] change_row0,change_row1,change_row2;
 reg[3:0] change_sum;reg change_centre0,change_centre1,change_result,change_cross0,change_cross1;
 reg[2:0] change_valid;
 wire change_accepted=wv&&((OP==0)||(wx>=2&&wx<W-2&&wy>=2&&wy<H-2));
 always @(posedge clk)begin
  if(rst)begin change_row0<=0;change_row1<=0;change_row2<=0;change_sum<=0;
   change_centre0<=0;change_centre1<=0;change_cross0<=0;change_cross1<=0;change_result<=0;change_valid<=0;end
  else begin
   change_row0<={1'b0,w00[0]}+{1'b0,w01[0]}+{1'b0,w02[0]};
   change_row1<={1'b0,w10[0]}+{1'b0,w11[0]}+{1'b0,w12[0]};
   change_row2<={1'b0,w20[0]}+{1'b0,w21[0]}+{1'b0,w22[0]};
   change_sum<={2'b0,change_row0}+{2'b0,change_row1}+{2'b0,change_row2};
   change_centre0<=w11[0];change_centre1<=change_centre0;
   change_cross0<=w01[0]&&w10[0]&&w12[0]&&w21[0];change_cross1<=change_cross0;
   change_result<=OP==0?change_sum>=5:change_centre1&&change_sum>=4&&!change_cross1;
   change_valid<={change_valid[1:0],change_accepted};
  end
 end
 wire fv;wire [7:0] filtered;
 wire protect_line;wire[7:0] line_value;
 generate if(OP==0)begin:g_med
  assign protect_line=0;assign line_value=0;
  case4_v9_selective_median #(.X_BITS(XB),.Y_BITS(YB)) med(
   .clk(clk),.rst(rst),.in_valid(wv),.mode(mode),.p00(p00),.p01(p01),.p02(p02),
   .p10(p10),.p11(p11),.p12(p12),.p20(p20),.p21(p21),.p22(p22),.out_valid(fv),.out_pixel(filtered));
 end else begin:g_gauss
  function automatic [7:0] difference(input [7:0] a,b);
   begin difference=a>b?a-b:b-a;end
  endfunction
  wire[7:0] d00=difference(p00,p11),d01=difference(p01,p11),d02=difference(p02,p11);
  wire[7:0] d10=difference(p10,p11),d12=difference(p12,p11);
  wire[7:0] d20=difference(p20,p11),d21=difference(p21,p11),d22=difference(p22,p11);
  wire[7:0] m00=mode==1||d00<=30?p00:p11,m01=mode==1||d01<=30?p01:p11,m02=mode==1||d02<=30?p02:p11;
  wire[7:0] m10=mode==1||d10<=30?p10:p11,m12=mode==1||d12<=30?p12:p11;
  wire[7:0] m20=mode==1||d20<=30?p20:p11,m21=mode==1||d21<=30?p21:p11,m22=mode==1||d22<=30?p22:p11;
  wire[7:0] horizontal=d10>d12?d10:d12,vertical=d01>d21?d01:d21;
  wire[7:0] diagonal_a=d00>d22?d00:d22,diagonal_b=d02>d20?d02:d20;
  reg[7:0] best_direction;reg[8:0] pair_sum;
  always @* begin
   best_direction=horizontal;pair_sum={1'b0,p10}+{1'b0,p12};
   if(vertical<best_direction)begin best_direction=vertical;pair_sum={1'b0,p01}+{1'b0,p21};end
   if(diagonal_a<best_direction)begin best_direction=diagonal_a;pair_sum={1'b0,p00}+{1'b0,p22};end
   if(diagonal_b<best_direction)begin best_direction=diagonal_b;pair_sum={1'b0,p02}+{1'b0,p20};end
  end
  wire[9:0] cardinal_sum={2'b0,p01}+{2'b0,p10}+{2'b0,p12}+{2'b0,p21}+10'd2;
  wire[9:0] directional_sum={1'b0,p11,1'b0}+{1'b0,pair_sum}+10'd2;
  wire preserve_line=best_direction<=8&&difference(p11,cardinal_sum[9:2])>=11;
  // Preserve the independently selectable bilateral filter guard unchanged.
  wire preserve_bilateral_line=best_direction<=8&&difference(p11,cardinal_sum[9:2])>=12;
  reg bilateral_protect0,bilateral_protect1;
  reg[7:0] line0,line1;reg protect0,protect1;
  reg [9:0] row0,row1,row2;reg [11:0] sum;
  reg [7:0] centre0,centre1,result;reg [2:0] valid;reg [1:0] full_blur;
  wire [9:0] detail_sum={2'b0,sum[11:4]}+{1'b0,centre1,1'b0}+{2'b0,centre1}+10'd2;
  reg [1:0] mode0,mode1;
  always @(posedge clk)begin
   if(rst)begin row0<=0;row1<=0;row2<=0;sum<=0;centre0<=0;centre1<=0;
    result<=0;valid<=0;full_blur<=0;mode0<=0;mode1<=0;line0<=0;line1<=0;protect0<=0;protect1<=0;bilateral_protect0<=0;bilateral_protect1<=0;end
   else begin
    row0<={2'b0,m00}+{1'b0,m01,1'b0}+{2'b0,m02};
    row1<={2'b0,m10}+{1'b0,p11,1'b0}+{2'b0,m12};
    row2<={2'b0,m20}+{1'b0,m21,1'b0}+{2'b0,m22};
    sum<={2'b0,row0}+{1'b0,row1,1'b0}+{2'b0,row2}+12'd8;
    centre0<=p11;centre1<=centre0;mode0<=mode;mode1<=mode0;full_blur<={full_blur[0],mode==1};
    line0<=directional_sum[9:2];line1<=line0;protect0<=preserve_line;protect1<=protect0;
    bilateral_protect0<=preserve_bilateral_line;bilateral_protect1<=bilateral_protect0;
    result<=mode1==0?centre1:(mode1==2&&protect1)?line1:sum[11:4];valid<={valid[1:0],wv};
   end
  end
  assign fv=valid[2];assign filtered=result;
  reg protect2;reg[7:0] line2;
  always @(posedge clk)if(rst)begin protect2<=0;line2<=0;end else begin protect2<=bilateral_protect1;line2<=line1;end
  assign protect_line=protect2;assign line_value=line2;
 end endgenerate
 wire [46:0] delayed;wire ready;
 case4_raster_delay #(.WIDTH(47),.STAGES(HT+6)) delay(
  clk,rst,{contour_view_enable,pair_view_enable,in_pair,in_hs,in_vs,in_de,in_pixel,in_meta},delayed,ready);
 always @(posedge clk)begin
  if(rst||!ready)begin out_hs<=1;out_vs<=1;out_de<=0;out_meta<=0;out_pixel<=0;out_change<=0;out_pair<=0;end
  else begin {out_hs,out_vs,out_de}<=delayed[42:40];out_change<=delayed[40]&&delayed[41]&&change_valid[2]&&change_result;
   out_pair<=delayed[44:43];
   out_meta<=(OP==1&&delayed[46]&&delayed[40]&&delayed[41]&&change_valid[2]&&change_result)?{24'hff0000,delayed[7:0]}:(OP==1&&delayed[45])?
     {pair_valid?pair_rgb:{{8{delayed[43]}},8'd0,{8{delayed[44]}}},delayed[7:0]}:delayed[31:0];
   out_pixel<=(OP==1&&pair_bilateral_enable&&!pair_view_enable&&pair_valid)?
     (protect_line?line_value:bilateral_gray):fv?filtered:delayed[39:32];end
 end
endmodule
