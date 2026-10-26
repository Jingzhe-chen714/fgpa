`timescale 1ns/1ps
// Three registered stages, II=1. 0=original, 1=full median, 2=selective.
// A selective replacement requires a large deviation from the median AND no
// adjacent pixel close to the centre. Thus a one-pixel-wide connected stroke,
// including an endpoint with one supporting neighbour, is preserved. A truly
// isolated one-pixel feature is ambiguous and may be removed, like impulse noise.
module case4_v9_selective_median #(
 parameter integer X_BITS=11,Y_BITS=11
)(
 input wire clk,rst,in_valid,input wire [1:0] mode,
 input wire [7:0] p00,p01,p02,p10,p11,p12,p20,p21,p22,
 output wire out_valid,output wire [7:0] out_pixel
);
 function automatic [7:0] distance(input [7:0] a,b);
  begin distance=a>b?a-b:b-a;end
 endfunction
 wire has_support=distance(p11,p00)<=20||distance(p11,p01)<=20||
  distance(p11,p02)<=20||distance(p11,p10)<=20||distance(p11,p12)<=20||
  distance(p11,p20)<=20||distance(p11,p21)<=20||distance(p11,p22)<=20;
 wire [7:0] median;
 reg [7:0] centre0,centre1,centre2;
 reg [2:0] isolated;
 reg [1:0] mode0,mode1,mode2;
 median3x3_u8 #(.X_BITS(X_BITS),.Y_BITS(Y_BITS)) sorter(
  .clk(clk),.rst(rst),.in_valid(in_valid),.in_sof(1'b0),.in_eol(1'b0),.in_eof(1'b0),
  .in_x({X_BITS{1'b0}}),.in_y({Y_BITS{1'b0}}),
  .in_p00(p00),.in_p01(p01),.in_p02(p02),.in_p10(p10),.in_p11(p11),.in_p12(p12),
  .in_p20(p20),.in_p21(p21),.in_p22(p22),.out_valid(out_valid),
  .out_sof(),.out_eol(),.out_eof(),.out_x(),.out_y(),.out_pixel(median));
 always @(posedge clk) begin
  if(rst)begin centre0<=0;centre1<=0;centre2<=0;isolated<=0;mode0<=0;mode1<=0;mode2<=0;end
  else begin centre0<=p11;centre1<=centre0;centre2<=centre1;
   isolated<={isolated[1:0],!has_support};mode0<=mode;mode1<=mode0;mode2<=mode1;end
 end
 assign out_pixel=mode2==1?median:
  (mode2==2&&isolated[2]&&distance(centre2,median)>=24)?median:centre2;
endmodule
