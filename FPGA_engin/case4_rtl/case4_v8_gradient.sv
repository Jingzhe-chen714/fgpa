`timescale 1ns/1ps
// Shared Sobel/Scharr arithmetic. Scharr kernels use3/10/3 weights and
// normalize L1 magnitude by4, keeping manual thresholds on the Sobel scale.
// Three arithmetic registers plus output feature register, one pixel/clock.
module case4_v8_gradient #(
 parameter W=1920,H=1080,HT=2200,XB=$clog2(W),YB=$clog2(H)
)(
 input wire clk,rst,in_hs,in_vs,in_de,input wire [7:0] in_pixel,
 input wire [31:0] in_meta,input wire [10:0] threshold,input wire scharr,
 output reg out_hs,out_vs,out_de,output reg [13:0] out_feature,
 output reg [31:0] out_meta
);
 wire [XB-1:0] x,wx;wire [YB-1:0] y,wy;
 case4_raster_xy #(.W(W),.H(H)) xy(clk,rst,in_vs,in_de,x,y);
 wire wv;wire [7:0] p00,p01,p02,p10,p11,p12,p20,p21,p22;
 case4_window3x3 #(.IMG_WIDTH(W),.IMG_HEIGHT(H)) win(
 .clk(clk),.rst(rst),.in_valid(in_de&&in_vs),.in_x(x),.in_y(y),.in_pixel(in_pixel),
 .out_valid(wv),.out_x(wx),.out_y(wy),.p00(p00),.p01(p01),.p02(p02),
 .p10(p10),.p11(p11),.p12(p12),.p20(p20),.p21(p21),.p22(p22));
 function automatic signed [12:0] weighted(input [7:0] a,b,input mid,sc);
 reg signed [12:0] d;
 begin d=$signed({1'b0,a})-$signed({1'b0,b});
  if(sc)weighted=mid?((d<<<3)+(d<<<1)):((d<<<1)+d);
  else weighted=mid?(d<<<1):d;
 end endfunction
 reg signed [12:0] xa,xb_,xc,ya,yb_,yc;
 reg signed [13:0] gx,gy,dx,dy;
 reg [2:0] valid,scpipe;
 reg [10:0] magnitude;
 wire [13:0] ax=gx[13]?$unsigned(-gx):$unsigned(gx);
 wire [13:0] ay=gy[13]?$unsigned(-gy):$unsigned(gy);
 wire [14:0] full_mag={1'b0,ax}+{1'b0,ay};
 always @(posedge clk)begin
  if(rst)begin xa<=0;xb_<=0;xc<=0;ya<=0;yb_<=0;yc<=0;gx<=0;gy<=0;dx<=0;dy<=0;
   valid<=0;scpipe<=0;magnitude<=0;end
  else begin
   xa<=weighted(p02,p00,0,scharr);xb_<=weighted(p12,p10,1,scharr);xc<=weighted(p22,p20,0,scharr);
   ya<=weighted(p20,p00,0,scharr);yb_<=weighted(p21,p01,1,scharr);yc<=weighted(p22,p02,0,scharr);
   gx<=$signed({xa[12],xa})+$signed({xb_[12],xb_})+$signed({xc[12],xc});
   gy<=$signed({ya[12],ya})+$signed({yb_[12],yb_})+$signed({yc[12],yc});
   dx<=gx;dy<=gy;magnitude<=scpipe[1]?((full_mag+2)>>2):full_mag;
   valid<={valid[1:0],wv};scpipe<={scpipe[1:0],scharr};
  end
 end
 wire [13:0] dax=dx[13]?$unsigned(-dx):$unsigned(dx);
 wire [13:0] day=dy[13]?$unsigned(-dy):$unsigned(dy);
 wire [21:0] ax106=({8'b0,dax}<<6)+({8'b0,dax}<<5)+({8'b0,dax}<<3)+({8'b0,dax}<<1);
 wire [21:0] ay106=({8'b0,day}<<6)+({8'b0,day}<<5)+({8'b0,day}<<3)+({8'b0,day}<<1);
 wire [1:0] direction=({day,8'b0}<=ax106)?0:({dax,8'b0}<=ay106)?2:(dx[13]==dy[13]?1:3);
 wire [34:0] delayed;wire ready;
 case4_raster_delay #(.WIDTH(35),.STAGES(HT+6)) delay(clk,rst,{in_hs,in_vs,in_de,in_meta},delayed,ready);
 always @(posedge clk)begin
  if(rst||!ready)begin out_hs<=1;out_vs<=1;out_de<=0;out_meta<=0;out_feature<=0;end
  else begin
   {out_hs,out_vs,out_de}<=delayed[34:32];out_meta<=delayed[31:0];
   out_feature<=valid[2]?{magnitude!=0&&magnitude>=threshold,direction,magnitude}:14'd0;
  end
 end
endmodule
