`timescale 1ns/1ps
// Six fixed Chinese HUD rows. Both bypass and text have THREE pixel clocks.
// A shared 11-step binary-to-BCD engine replaces per-pixel integer dividers.
module case4_v11_osd #(
 parameter FONT_FILE="case4_rtl/v11_font.hex",TEXT_FILE="case4_rtl/v11_text.hex"
)(
 input wire clk,rst,enable,in_hs,in_vs,in_de,input wire [10:0] x,y,input wire [23:0] in_rgb,
 input wire [2:0] mode,input wire [10:0] threshold,input wire menu_open,input wire [4:0] menu_index,
 input wire link_lost,unsupported,fault,input wire [767:0] status,
 input wire [1:0] effect_mode,view_mode,input wire split_enable,input wire [4:0] geometry_valid,
 input wire [7:0] face_flags,pair_flags,
 output reg out_hs,out_vs,out_de,output reg [23:0] out_rgb
);
 localparam MENU_BASE=7,VALUE_BASE=31,DIGITS=1920,YES=1952,NO=1984;
 reg [15:0] font_rom[0:2367];reg [7:0] text_rom[0:2015];
 initial begin $readmemh(FONT_FILE,font_rom);$readmemh(TEXT_FILE,text_rom);end
 wire area=enable&&in_de&&x>=24&&x<1048&&y>=24&&y<264;
 wire [10:0] xx=x-24,yy=y-24;
 reg [2:0] row;reg [5:0] local_y;
 always @*begin
  if(yy<40)begin row=0;local_y=yy;end
  else if(yy<80)begin row=1;local_y=yy-40;end
  else if(yy<120)begin row=2;local_y=yy-80;end
  else if(yy<160)begin row=3;local_y=yy-120;end
  else if(yy<200)begin row=4;local_y=yy-160;end
  else begin row=5;local_y=yy-200;end
 end
 wire [4:0] col=xx[9:5];wire [3:0] gy=local_y[4:1],gx=xx[4:1];
 wire [7:0] median=status[47:40];wire face=status[23:16]==3;
 wire geometry=status[38],gamma=status[32],stable=status[35],frozen=status[33],paused=status[34],bridge=status[37];
 reg menu_numeric;reg [10:0] menu_number;reg [5:0] menu_value;
 function automatic [5:0] view_name(input [1:0] v);
  begin case(v)0:view_name=2;1:view_name=8;2:view_name=9;default:view_name=10;endcase end
 endfunction
 function automatic [5:0] effect_name(input [1:0] e);
  begin effect_name=e==1?13:e==2?14:12;end
 endfunction
 function automatic [5:0] match_name(input bit found);
  begin match_name=!geometry?17:found?15:16;end
 endfunction
 always @*begin
  menu_numeric=0;menu_number=0;menu_value=11;
  case(menu_index)
   0:menu_value=face?3:2;
   1:begin menu_numeric=1;menu_number={8'b0,mode};end
   2:begin menu_numeric=1;menu_number=threshold;end
   3:menu_value=median==0?0:median==1?4:5;
   4:menu_value=gamma?1:0;5:menu_value=stable?1:0;
   6:menu_value=effect_name(effect_mode);7:menu_value=geometry?1:0;
   8:menu_value=status[39]?1:0;
   9:menu_value=status[55:48]==0?0:status[55:48]==1?6:7;
   10:menu_value=view_name(view_mode);
   11:menu_value=frozen?1:0;12:menu_value=paused?1:0;
   20:menu_value=bridge?1:0;21:menu_value=split_enable?1:0;
   23:menu_value=status[433]?1:0;
   default:;
  endcase
 end
 // Four digits each: threshold, menu value, frame, frame count, reference,
 // selected menu number. Source fields settle long before HUD y=24 is scanned.
 reg [15:0] bcd[0:5];reg [15:0] bcd_work;
 reg [10:0] binary_work;reg [3:0] bcd_step;reg [2:0] bcd_slot;
 reg [15:0] bcd_adjust;integer k;
 always @*begin
  bcd_adjust=bcd_work;
  for(k=0;k<4;k=k+1)if(bcd_work[k*4+:4]>=5)bcd_adjust[k*4+:4]=bcd_work[k*4+:4]+3;
 end
 integer n;
 always @(posedge clk)begin
  if(rst)begin
   bcd_work<=0;binary_work<=0;bcd_step<=0;bcd_slot<=0;
   for(n=0;n<6;n=n+1)bcd[n]<=0;
  end else if(bcd_step==0)begin
   bcd_work<=0;bcd_step<=1;
   case(bcd_slot)
    0:binary_work<=threshold;1:binary_work<=menu_number;
    2:binary_work<={5'b0,status[293:288]};3:binary_work<={4'b0,status[302:296]};
    4:binary_work<={5'b0,status[509:504]};default:binary_work<=menu_index+1'b1;
   endcase
  end else begin
   bcd_work<={bcd_adjust[14:0],binary_work[10]};binary_work<={binary_work[9:0],1'b0};
   if(bcd_step==11)begin
    bcd[bcd_slot]<={bcd_adjust[14:0],binary_work[10]};bcd_step<=0;bcd_slot<=bcd_slot==5?0:bcd_slot+1'b1;
   end else bcd_step<=bcd_step+1'b1;
  end
 end
 reg [11:0] address;reg [23:0] ink;reg [5:0] state_name;
 always @*begin
  state_name=fault?18:link_lost?19:unsupported?20:pair_flags[2]?22:face_flags[3]?23:21;
  address={6'b0,row,5'b0}+col;ink=24'hffffff;
  case(row)
   0:begin
    if(col==2)address=DIGITS+mode;
    if(col>=4&&col<12)address=(VALUE_BASE+24+mode)*32+col-4;
    if(col>=14&&col<18)case(col)
     14:address=DIGITS+bcd[0][15:12];15:address=DIGITS+bcd[0][11:8];
     16:address=DIGITS+bcd[0][7:4];17:address=DIGITS+bcd[0][3:0];
    endcase
   end
   1:begin
    if(col>=3&&col<5)address=(VALUE_BASE+(face?3:2))*32+col-3;
    if(col>=9&&col<13)address=(VALUE_BASE+view_name(view_mode))*32+col-9;
    if(col>=17&&col<21)address=(VALUE_BASE+effect_name(effect_mode))*32+col-17;
    if(col>=23&&col<27)address=(VALUE_BASE+state_name)*32+col-23;
   end
   2:begin
    if(col>=3&&col<7)address=(VALUE_BASE+(median==0?0:median==1?4:5))*32+col-3;
    if(col>=11&&col<13)address=(VALUE_BASE+(gamma?1:0))*32+col-11;
    if(col>=18&&col<20)address=(VALUE_BASE+(stable?1:0))*32+col-18;
    if(col>=25&&col<27)address=(VALUE_BASE+(split_enable?1:0))*32+col-25;
   end
   3:begin
    if(col<7)ink=24'hffff00;else if(col>=9&&col<14)ink=24'h4080ff;else if(col>=16&&col<22)ink=24'h00ff00;
    if(col>=5&&col<7)address=(VALUE_BASE+match_name(geometry_valid[0]||geometry_valid[3]))*32+col-5;
    if(col>=12&&col<14)address=(VALUE_BASE+match_name(geometry_valid[1]))*32+col-12;
    if(col>=20&&col<22)address=(VALUE_BASE+match_name(geometry_valid[2]))*32+col-20;
    if(col==25)address=DIGITS+bcd[2][7:4];if(col==26)address=DIGITS+bcd[2][3:0];
    if(col==28)address=DIGITS+bcd[3][7:4];if(col==29)address=DIGITS+bcd[3][3:0];
   end
   4:begin
    if(col>=6&&col<14)ink=24'hff69b4;
    if(col>=3&&col<5)address=(VALUE_BASE+(status[39]?1:0))*32+col-3;
    if(col>=12&&col<14)address=(VALUE_BASE+match_name(geometry_valid[4]))*32+col-12;
    if(col==18)address=DIGITS+bcd[4][7:4];if(col==19)address=DIGITS+bcd[4][3:0];
    if(col==25)address=DIGITS+(status[455:448]<=4?status[455:448]:0);
   end
   5:if(menu_open)begin
    ink=24'h80ffff;
    if(col==2)address=DIGITS+bcd[5][7:4];if(col==3)address=DIGITS+bcd[5][3:0];
    if(col>=12&&col<23)address=(MENU_BASE+menu_index)*32+col-12;
    if(col>=26)begin
     if(menu_numeric)case(col)
      26:address=DIGITS+bcd[1][15:12];27:address=DIGITS+bcd[1][11:8];
      28:address=DIGITS+bcd[1][7:4];29:address=DIGITS+bcd[1][3:0];default:address=DIGITS+10;
     endcase
     else address=(VALUE_BASE+menu_value)*32+col-26;
    end
   end else begin
    address=6*32+col;
    if(col>=3&&col<5)address=(VALUE_BASE+(bridge?1:0))*32+col-3;
    if(col>=10&&col<12)address=(pair_flags[0]?YES:NO)+col-10;
    if(col>=17&&col<19)address=(pair_flags[1]?YES:NO)+col-17;
    if(col>=24&&col<26)address=(VALUE_BASE+(frozen?1:0))*32+col-24;
   end
  endcase
 end
 reg [7:0] glyph;reg [15:0] glyph_bits;
 reg [3:0] gy1,gx1,gx2;
 reg h1,v1,d1,h2,v2,d2,box1,box2;reg [23:0] rgb1,rgb2,ink1,ink2;
 always @(posedge clk)glyph<=text_rom[address];
 always @(posedge clk)begin
  if(rst)begin
   gy1<=0;gx1<=0;gx2<=0;glyph_bits<=0;h1<=1;v1<=1;d1<=0;h2<=1;v2<=1;d2<=0;
   box1<=0;box2<=0;rgb1<=0;rgb2<=0;ink1<=0;ink2<=0;out_hs<=1;out_vs<=1;out_de<=0;out_rgb<=0;
  end else begin
   gy1<=gy;gx1<=gx;h1<=in_hs;v1<=in_vs;d1<=in_de;rgb1<=in_rgb;ink1<=ink;box1<=area&&local_y<32;
   glyph_bits<=font_rom[{glyph,4'b0}+gy1];gx2<=gx1;h2<=h1;v2<=v1;d2<=d1;rgb2<=rgb1;ink2<=ink1;box2<=box1;
   out_hs<=h2;out_vs<=v2;out_de<=d2;
   out_rgb<=!d2?24'd0:box2?(glyph_bits[15-gx2]?ink2:{3'b0,rgb2[23:19],3'b0,rgb2[15:11],3'b0,rgb2[7:3]}):rgb2;
  end
 end
endmodule
