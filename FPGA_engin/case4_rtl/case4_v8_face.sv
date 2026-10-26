`timescale 1ns/1ps
// V8: isolated warm-color components, TWO local facial-structure candidates,
// illumination-relative dark features and fresh-source-frame hysteresis.
// This is a bounded frontal-face feature detector, NOT identity recognition or
// a trained detector. Skin/background contact and severe pose remain limits.
// Requires case4_v8_components (defined in case4_v8_shape.sv).
module case4_v8_face #(
 parameter integer IMG_WIDTH=1920,IMG_HEIGHT=1080,
 parameter integer MIN_FACE_WIDTH=48,MIN_FACE_HEIGHT=56,
 parameter integer DS_LOG2=3,CONFIRM_FRAMES=2,LOSS_FRAMES=5
)(
 input wire clk,rst_n,clear,frame_start,sample_tick,pixel_valid,
 input wire [10:0] x,y,input wire [23:0] rgb,input wire edge_bit,
 output reg face_valid,output reg [10:0] bbox_x0,bbox_x1,bbox_y0,bbox_y1,
 output wire face_outline,output reg [7:0] score,
 output reg observation_valid,result_tick,
 output wire busy,overflow
);
 localparam integer DS=1<<DS_LOG2,GW=(IMG_WIDTH/2+DS-1)>>DS_LOG2,GH=(IMG_HEIGHT+DS-1)>>DS_LOG2;
 wire [7:0] r=rgb[23:16],g=rgb[15:8],b=rgb[7:0];
 wire [9:0] lsum={2'b0,r}+{1'b0,g,1'b0}+{2'b0,b};
 wire [7:0] luma=lsum[9:2];
 wire skin=({1'b0,r}+10>={1'b0,g})&&({1'b0,r}+6>={1'b0,b})&&
   ({1'b0,g}+18>={1'b0,b})&&({1'b0,r}<={1'b0,g}+105)&&
   ({1'b0,g}<={1'b0,b}+95)&&({1'b0,r}>={1'b0,b}+3)&&luma>=10&&luma<=250;
 wire ready,done,oversize;reg accept;
 wire [10:0] cx0,cx1,cy0,cy1;wire [12:0] points;
 wire [$clog2(GW)-1:0] unused_x;wire [$clog2(GH)-1:0] unused_y;
 case4_v8_components #(.IMG_WIDTH(IMG_WIDTH),.IMG_HEIGHT(IMG_HEIGHT),.DS_LOG2(DS_LOG2),
   .MAX_POINTS(4096),.GAP_CELLS(0),.STORE_POINTS(0)) components(
  .clk(clk),.rst_n(rst_n),.clear(clear),.frame_start(frame_start),.sample_tick(sample_tick),.pixel_valid(pixel_valid),
  .x(x),.y(y),.mask_bit(skin),.busy(busy),.overflow(overflow),.frame_done(done),.component_ready(ready),.component_accept(accept),
  .bx0(cx0),.bx1(cx1),.by0(cy0),.by1(cy1),.point_count(points),.component_too_large(oversize),
  .point_index(12'd0),.point_x(unused_x),.point_y(unused_y));
 wire [11:0] cw=cx1-cx0+12'd1,ch=cy1-cy0+12'd1;
 reg [23:0] carea;
 always @(posedge clk)carea<=cw*ch;
 wire [23:0] occupied=points<<(2*DS_LOG2);
 // Reject thin arms and extreme aspect ratios before local facial validation.
 // Occupancy is block OR, so its upper density is NOT a skin-pixel density:
 // photographs can legitimately fill almost every coarse cell. Actual local
 // pixel density and facial features reject plain warm rectangles below.
 wire plausible=!oversize&&cw>=MIN_FACE_WIDTH&&ch>=MIN_FACE_HEIGHT&&
   2*cw>=ch&&4*cw<=5*ch&&occupied>=(carea>>2)&&
   cx0>IMG_WIDTH/2&&cx1<IMG_WIDTH-1&&cy0>0&&cy1<IMG_HEIGHT-1;
 reg [1:0] work_valid,candidate_valid,active;
 reg [12:0] work_count[0:1];
 reg [10:0] wx0[0:1],wx1[0:1],wy0[0:1],wy1[0:1];
 reg [10:0] qx0[0:1],qx1[0:1],qy0[0:1],qy1[0:1];
 reg [10:0] ax0[0:1],ax1[0:1],ay0[0:1],ay1[0:1];
 reg capture_active;
 wire [1:0] measured;
 wire [7:0] evidence[0:1];
 integer k;
 always @(posedge clk)begin
  if(!rst_n||clear)begin
   accept<=0;work_valid<=0;candidate_valid<=0;active<=0;capture_active<=0;
   for(k=0;k<2;k=k+1)begin work_count[k]<=0;wx0[k]<=0;wx1[k]<=0;wy0[k]<=0;wy1[k]<=0;
     qx0[k]<=0;qx1[k]<=0;qy0[k]<=0;qy1[k]<=0;ax0[k]<=0;ax1[k]<=0;ay0[k]<=0;ay1[k]<=0;end
  end else begin
   accept<=0;
   if(ready&&!accept)begin
    accept<=1;
    if(plausible)begin
      if(!work_valid[0]||points>work_count[0])begin
       work_valid<={work_valid[0],1'b1};work_count[0]<=points;
       work_count[1]<=work_count[0];wx0[1]<=wx0[0];wx1[1]<=wx1[0];wy0[1]<=wy0[0];wy1[1]<=wy1[0];
       wx0[0]<=cx0;wx1[0]<=cx1;wy0[0]<=cy0;wy1[0]<=cy1;
      end else if(!work_valid[1]||points>work_count[1])begin
       work_valid[1]<=1;work_count[1]<=points;wx0[1]<=cx0;wx1[1]<=cx1;wy0[1]<=cy0;wy1[1]<=cy1;
      end
    end
   end
   if(done)begin
    candidate_valid<=overflow?0:work_valid;work_valid<=0;
    for(k=0;k<2;k=k+1)begin qx0[k]<=wx0[k];qx1[k]<=wx1[k];qy0[k]<=wy0[k];qy1[k]<=wy1[k];work_count[k]<=0;end
   end
   if(frame_start)begin
    capture_active<=sample_tick;
    if(sample_tick)begin active<=candidate_valid;for(k=0;k<2;k=k+1)begin ax0[k]<=qx0[k];ax1[k]<=qx1[k];ay0[k]<=qy0[k];ay1[k]<=qy1[k];end end
   end
  end
 end
 genvar gi;
 generate for(gi=0;gi<2;gi=gi+1)begin:feature
  wire [11:0] w=ax1[gi]-ax0[gi]+12'd1,h=ay1[gi]-ay0[gi]+12'd1;
  reg [23:0] area;
  always @(posedge clk)area<=w*h;
  wire in_box=capture_active&&active[gi]&&pixel_valid&&x>=ax0[gi]&&x<=ax1[gi]&&y>=ay0[gi]&&y<=ay1[gi];
  wire eyes_y=y>=ay0[gi]+((h*4)>>4)&&y<=ay0[gi]+((h*9)>>4);
  wire left_eye=in_box&&eyes_y&&x>=ax0[gi]+((w*3)>>4)&&x<=ax0[gi]+((w*7)>>4);
  wire right_eye=in_box&&eyes_y&&x>=ax0[gi]+((w*9)>>4)&&x<=ax0[gi]+((w*13)>>4);
  wire mouth=in_box&&x>=ax0[gi]+((w*5)>>4)&&x<=ax0[gi]+((w*11)>>4)&&y>=ay0[gi]+((h*10)>>4)&&y<=ay0[gi]+((h*14)>>4);
  reg [7:0] local_mean;
  wire dark=luma<local_mean-(local_mean>>2);
  reg [20:0] dark_l,dark_r,dark_m,edge_l,edge_r,edge_m,skin_count;
  reg [31:0] skin_sum;
  reg [15:0] border_l,border_r,border_t,border_b;
  wire [23:0] min_dark=(area>>10)<3?24'd3:(area>>10);
  wire [23:0] min_edge=(area>>12)<2?24'd2:(area>>12);
  wire good_l=dark_l>=min_dark&&dark_l<(area>>3)&&edge_l>=min_edge;
  wire good_r=dark_r>=min_dark&&dark_r<(area>>3)&&edge_r>=min_edge;
  wire good_m=dark_m>=min_dark&&dark_m<(area>>3)&&edge_m>=min_edge;
  wire eyes_balanced=dark_l<=4*dark_r&&dark_r<=4*dark_l;
  wire [2:0] borders={2'b0,border_l>=min_edge}+{2'b0,border_r>=min_edge}+{2'b0,border_t>=min_edge}+{2'b0,border_b>=min_edge};
  wire density=skin_count>=(area>>2)&&skin_count<area-(area>>6);
  assign measured[gi]=active[gi]&&good_l&&good_r&&good_m&&eyes_balanced&&density&&borders>=3;
  assign evidence[gi]=({7'b0,good_l}+{7'b0,good_r}+{7'b0,good_m}+{7'b0,eyes_balanced}+{7'b0,density}+{7'b0,borders>=3})*8'd32;
  // Local mean only: unrelated warm background cannot change dark thresholds.
  reg div_busy;reg [5:0] div_left;reg [31:0] dividend,divisor,quotient,remainder;
  wire [32:0] rem_next={remainder,dividend[31]};
  wire subtract_ok=rem_next>={1'b0,divisor};
  wire [31:0] quot_next={quotient[30:0],subtract_ok};
  always @(posedge clk)begin
   if(!rst_n||clear)begin
    local_mean<=128;dark_l<=0;dark_r<=0;dark_m<=0;edge_l<=0;edge_r<=0;edge_m<=0;skin_count<=0;skin_sum<=0;
    border_l<=0;border_r<=0;border_t<=0;border_b<=0;div_busy<=0;div_left<=0;dividend<=0;divisor<=1;quotient<=0;remainder<=0;
   end else begin
    if(div_busy)begin
      dividend<={dividend[30:0],1'b0};quotient<=quot_next;remainder<=subtract_ok?rem_next-{1'b0,divisor}:rem_next;
      div_left<=div_left-1'b1;if(div_left==1)begin local_mean<=quot_next[7:0];div_busy<=0;end
    end
    if(frame_start)begin
      if(capture_active&&skin_count!=0)begin div_busy<=1;div_left<=32;dividend<=skin_sum;divisor<=skin_count;quotient<=0;remainder<=0;end
      dark_l<=0;dark_r<=0;dark_m<=0;edge_l<=0;edge_r<=0;edge_m<=0;skin_count<=0;skin_sum<=0;
      border_l<=0;border_r<=0;border_t<=0;border_b<=0;
    end else if(in_box)begin
      if(skin)begin skin_count<=skin_count+1'b1;skin_sum<=skin_sum+luma;end
      if(left_eye)begin if(dark)dark_l<=dark_l+1'b1;if(edge_bit)edge_l<=edge_l+1'b1;end
      if(right_eye)begin if(dark)dark_r<=dark_r+1'b1;if(edge_bit)edge_r<=edge_r+1'b1;end
      if(mouth)begin if(dark)dark_m<=dark_m+1'b1;if(edge_bit)edge_m<=edge_m+1'b1;end
      if(edge_bit)begin
       if(x<=ax0[gi]+(w>>2)&&y>=ay0[gi]+(h>>2)&&y<=ay0[gi]+((h*3)>>2))border_l<=border_l+1'b1;
       if(x>=ax1[gi]-(w>>2)&&y>=ay0[gi]+(h>>2)&&y<=ay0[gi]+((h*3)>>2))border_r<=border_r+1'b1;
       if(y<=ay0[gi]+(h>>2)&&x>=ax0[gi]+(w>>2)&&x<=ax0[gi]+((w*3)>>2))border_t<=border_t+1'b1;
       if(y>=ay1[gi]-(h>>2)&&x>=ax0[gi]+(w>>2)&&x<=ax0[gi]+((w*3)>>2))border_b<=border_b+1'b1;
      end
    end
   end
  end
 end endgenerate
 wire chosen=measured[0]?1'b0:1'b1;
 reg [7:0] hits,misses;
 wire [12:0] oldcx={2'b0,bbox_x0}+{2'b0,bbox_x1},newcx={2'b0,ax0[chosen]}+{2'b0,ax1[chosen]};
 wire [12:0] oldcy={2'b0,bbox_y0}+{2'b0,bbox_y1},newcy={2'b0,ay0[chosen]}+{2'b0,ay1[chosen]};
 wire [12:0] delta_x=oldcx>newcx?oldcx-newcx:newcx-oldcx,delta_y=oldcy>newcy?oldcy-newcy:newcy-oldcy;
 wire near_previous=delta_x<=(bbox_x1-bbox_x0+32)&&delta_y<=(bbox_y1-bbox_y0+32);
 assign face_outline=face_valid&&pixel_valid&&edge_bit&&x>=bbox_x0&&x<=bbox_x1&&y>=bbox_y0&&y<=bbox_y1;
 always @(posedge clk)begin
  if(!rst_n||clear)begin
   hits<=0;misses<=0;face_valid<=0;bbox_x0<=0;bbox_x1<=0;bbox_y0<=0;bbox_y1<=0;score<=0;observation_valid<=0;result_tick<=0;
  end else begin
   result_tick<=0;
   if(frame_start&&capture_active)begin
    result_tick<=1;observation_valid<=0;
    if(|measured)begin
     misses<=0;
     if(hits<CONFIRM_FRAMES)hits<=hits+1'b1;
     if(hits>=CONFIRM_FRAMES-1)begin
      face_valid<=1;observation_valid<=1;score<=evidence[chosen];
      bbox_x0<=ax0[chosen];bbox_x1<=ax1[chosen];bbox_y0<=ay0[chosen];bbox_y1<=ay1[chosen];
     end
    end else begin
     // One failed observation does not reset accumulated confirmations; two
     // failures do. A displayed hold never counts as positive evidence.
     if(misses>=1)hits<=0;
     if(misses<LOSS_FRAMES)misses<=misses+1'b1;
     if(misses>=LOSS_FRAMES-1)begin face_valid<=0;score<=0;end
    end
   end
  end
 end
endmodule

