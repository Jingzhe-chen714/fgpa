`timescale 1ns/1ps
// V12 shared-window, three-clock grayscale / comparison bilateral core.
// Labels: bit0=A/red, bit1=B/blue; 00 black, 11 magenta. No input map writeback.
// Space weights [1 2 1]^T[1 2 1]. Colour distance is Hamming(label)*255^2;
// range weights 16/8/4 approximate exp(-distance/(2*217^2)) at these three
// possible squared distances. This is a genuine normalized, colour-aware
// 3x3 integer bilateral filter. LIVE reuses the same reciprocal ROM and DSP
// for normalized grayscale weights 16/8/4/2/0 at distances <=8/16/32/48/>48.
// Then project back onto the ORIGINAL centre support: black stays black,
// A stays red, B stays blue, A&B uses equal red/blue intensity. No new edge
// positions or cross-frame colour contamination are introduced by smoothing.
module case4_v11_pair_bilateral(
 input wire clk,rst,in_valid,enable,pair_view_enable,
 input wire[1:0] p00,p01,p02,p10,p11,p12,p20,p21,p22,
 input wire[7:0] g00,g01,g02,g10,g11,g12,g20,g21,g22,
 output wire out_valid,output reg[23:0] out_rgb,output reg[7:0] out_gray
);
 function automatic[4:0] range_weight(input[1:0] label,centre);
  case(label^centre)2'b00:range_weight=16;2'b11:range_weight=4;default:range_weight=8;endcase
 endfunction
 function automatic[4:0] gray_weight(input[7:0] value,centre);
  reg[7:0] distance;
  begin distance=value>centre?value-centre:centre-value;
   gray_weight=distance<=8?16:distance<=16?8:distance<=32?4:distance<=48?2:0;
  end
 endfunction
 function automatic[11:0] weighted_value(input[7:0] value,input[4:0] weight);
  begin case(weight)
   16:weighted_value={value,4'd0};8:weighted_value={1'd0,value,3'd0};
   4:weighted_value={2'd0,value,2'd0};2:weighted_value={3'd0,value,1'd0};
   default:weighted_value=0;
  endcase end
 endfunction
 function automatic[23:0] palette(input[1:0] label);
  begin palette={{8{label[0]}},8'd0,{8{label[1]}}};end
 endfunction
 wire[4:0] q00=pair_view_enable?range_weight(p00,p11):gray_weight(g00,g11);
 wire[4:0] q01=pair_view_enable?range_weight(p01,p11):gray_weight(g01,g11);
 wire[4:0] q02=pair_view_enable?range_weight(p02,p11):gray_weight(g02,g11);
 wire[4:0] q10=pair_view_enable?range_weight(p10,p11):gray_weight(g10,g11);
 wire[4:0] q12=pair_view_enable?range_weight(p12,p11):gray_weight(g12,g11);
 wire[4:0] q20=pair_view_enable?range_weight(p20,p11):gray_weight(g20,g11);
 wire[4:0] q21=pair_view_enable?range_weight(p21,p11):gray_weight(g21,g11);
 wire[4:0] q22=pair_view_enable?range_weight(p22,p11):gray_weight(g22,g11);
 wire[6:0] w00={2'b0,q00},w01=pair_view_enable?{1'b0,q01,1'b0}:{2'b0,q01},w02={2'b0,q02};
 wire[6:0] w10=pair_view_enable?{1'b0,q10,1'b0}:{2'b0,q10},w11=pair_view_enable?7'd64:7'd16,w12=pair_view_enable?{1'b0,q12,1'b0}:{2'b0,q12};
 wire[6:0] w20={2'b0,q20},w21=pair_view_enable?{1'b0,q21,1'b0}:{2'b0,q21},w22={2'b0,q22};
 wire[11:0] v00=weighted_value(pair_view_enable?{8{p00[0]}}:g00,q00);
 wire[11:0] v01=weighted_value(pair_view_enable?{8{p01[0]}}:g01,q01);
 wire[11:0] v02=weighted_value(pair_view_enable?{8{p02[0]}}:g02,q02);
 wire[11:0] v10=weighted_value(pair_view_enable?{8{p10[0]}}:g10,q10);
 wire[11:0] v12=weighted_value(pair_view_enable?{8{p12[0]}}:g12,q12);
 wire[11:0] v20=weighted_value(pair_view_enable?{8{p20[0]}}:g20,q20);
 wire[11:0] v21=weighted_value(pair_view_enable?{8{p21[0]}}:g21,q21);
 wire[11:0] v22=weighted_value(pair_view_enable?{8{p22[0]}}:g22,q22);
 wire[7:0] centre_value=pair_view_enable?{8{p11[0]}}:g11;
 reg[7:0] weight_row0,weight_row1,weight_row2,blue_row0,blue_row1,blue_row2;
 reg[13:0] red_row0,red_row2;reg[14:0] red_row1;
 wire[8:0] total_weight={1'b0,weight_row0}+{1'b0,weight_row1}+{1'b0,weight_row2};
 wire[15:0] red_weighted_sum={2'b0,red_row0}+{1'b0,red_row1}+{2'b0,red_row2};
 wire[8:0] blue_weight={1'b0,blue_row0}+{1'b0,blue_row1}+{1'b0,blue_row2};
 // Denominator is 16..256; grayscale uses a uniform finite spatial support.
 // A synchronous 512x13 ROM consumes at most one 20K block. ROM contents are
 // compile-time constants; no divider exists in the pixel data path.
 reg[12:0] reciprocal[0:511];integer k;
 initial for(k=0;k<512;k=k+1)reciprocal[k]=k<16?4096:(65536+(k>>1))/k;
 reg[12:0] reciprocal_q;
 reg[15:0] red_numerator,blue_numerator;
 wire[28:0] red_product=red_numerator*reciprocal_q,blue_product=blue_numerator*reciprocal_q;
 wire[29:0] red_rounded={1'b0,red_product}+30'd32768,blue_rounded={1'b0,blue_product}+30'd32768;
 wire[8:0] overlap_sum={1'b0,red_rounded[23:16]}+{1'b0,blue_rounded[23:16]}+9'd1;
 reg[2:0] valid;reg[1:0] enabled,centre0,centre1;reg[7:0] gray_centre0,gray_centre1;
 assign out_valid=valid[2];
 always @(posedge clk)begin
  if(rst)begin
   weight_row0<=0;weight_row1<=0;weight_row2<=0;red_row0<=0;red_row1<=0;red_row2<=0;
   blue_row0<=0;blue_row1<=0;blue_row2<=0;reciprocal_q<=0;red_numerator<=0;blue_numerator<=0;
   valid<=0;enabled<=0;centre0<=0;centre1<=0;gray_centre0<=0;gray_centre1<=0;out_rgb<=0;out_gray<=0;
  end else begin
   weight_row0<={1'b0,w00}+{1'b0,w01}+{1'b0,w02};
   weight_row1<={1'b0,w10}+{1'b0,w11}+{1'b0,w12};
   weight_row2<={1'b0,w20}+{1'b0,w21}+{1'b0,w22};
   red_row0<={2'd0,v00}+(pair_view_enable?{1'd0,v01,1'b0}:{2'd0,v01})+{2'd0,v02};
   red_row1<=(pair_view_enable?{2'd0,v10,1'b0}:{3'd0,v10})+
    (pair_view_enable?{1'd0,centre_value,6'd0}:{3'd0,centre_value,4'd0})+
    (pair_view_enable?{2'd0,v12,1'b0}:{3'd0,v12});
   red_row2<={2'd0,v20}+(pair_view_enable?{1'd0,v21,1'b0}:{2'd0,v21})+{2'd0,v22};
   blue_row0<=(p00[1]?{1'b0,w00}:8'd0)+(p01[1]?{1'b0,w01}:8'd0)+(p02[1]?{1'b0,w02}:8'd0);
   blue_row1<=(p10[1]?{1'b0,w10}:8'd0)+(p11[1]?{1'b0,w11}:8'd0)+(p12[1]?{1'b0,w12}:8'd0);
   blue_row2<=(p20[1]?{1'b0,w20}:8'd0)+(p21[1]?{1'b0,w21}:8'd0)+(p22[1]?{1'b0,w22}:8'd0);
   reciprocal_q<=reciprocal[total_weight];
   red_numerator<=red_weighted_sum;
   blue_numerator<=({blue_weight,8'd0}-{8'd0,blue_weight});
   centre0<=p11;centre1<=centre0;gray_centre0<=g11;gray_centre1<=gray_centre0;
   enabled<={enabled[0],enable};valid<={valid[1:0],in_valid};
   out_gray<=enabled[1]?red_rounded[23:16]:gray_centre1;
   if(!enabled[1])out_rgb<=palette(centre1);
   else case(centre1)
    2'b00:out_rgb<=24'd0;
    2'b01:out_rgb<={red_rounded[23:16],16'd0};
    2'b10:out_rgb<={16'd0,blue_rounded[23:16]};
    2'b11:out_rgb<={overlap_sum[8:1],8'd0,overlap_sum[8:1]};
   endcase
  end
 end
endmodule
