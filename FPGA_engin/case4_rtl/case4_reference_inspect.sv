`timescale 1ns/1ps
// V7 fixed-camera contour inspection. Each bit is the OR of a 4x4 native
// pixel cell in the right ROI. Reference/current contours are matched in BOTH
// directions within one grid-cell neighbourhood (4px nominal tolerance).
// Missing and extra contours are distinct; no contour completion is performed.
module case4_reference_inspect #(
 parameter integer IMG_WIDTH=1920,IMG_HEIGHT=1080,DS_LOG2=2,
 parameter integer GW=(IMG_WIDTH/2)>>DS_LOG2,GH=IMG_HEIGHT>>DS_LOG2,
 parameter integer GX=$clog2(GW),GY=$clog2(GH),AB=$clog2(GW*GH),MIN_REFERENCE=8
)(
 input wire clk,rst,enable,frame_start,pixel_valid,edge_bit,source_valid,
 input wire [10:0] x,y,input wire [31:0] source_id,input wire [5:0] source_bank,
 input wire learn_toggle,
 output reg [2:0] status,output reg [15:0] missing_cells,extra_cells,
 output reg event_pulse,output reg [31:0] result_frame_id,output reg [5:0] result_bank,
 output reg [1:0] overlay_code
);
 localparam integer ROI=IMG_WIDTH/2,DS=1<<DS_LOG2,N=GW*GH;
 reg reference[0:N-1];reg [1:0] overlay0[0:N-1],overlay1[0:N-1];
 reg [GW-1:0] column_or;
 reg learn_seen,learn_pending,learning,capture,ref_valid;
 reg front_bank,back_bank,pending_result,pending_fail,previous_fail;
 reg [31:0] capture_id,pending_id;reg [5:0] capture_source,pending_source;
 reg [15:0] count_missing,count_extra,reference_count,learn_count,pending_missing,pending_extra;
 wire learn_changed=learn_toggle!=learn_seen;
 wire learn_request=learn_pending||learn_changed;
 wire take=enable&&!frame_start&&!learn_changed&&capture&&pixel_valid&&x>=ROI&&x<IMG_WIDTH&&y<IMG_HEIGHT;
 wire [10:0] lx=x-ROI;
 wire [GX-1:0] bx=lx>>DS_LOG2;wire [GY-1:0] by=y>>DS_LOG2;
 wire cell_end=take&&(lx&(DS-1))==DS-1&&(y&(DS-1))==DS-1;
 wire cell_bit=column_or[bx]|edge_bit;
 wire [AB-1:0] cell_addr=by*GW+bx;
 reg cell_d,cell_value,reference_q;reg [GX-1:0] cell_x;reg [GY-1:0] cell_y;
 always @(posedge clk) begin
   if(cell_end)begin
     reference_q<=reference[cell_addr];
     if(learning)reference[cell_addr]<=cell_bit;
   end
 end
 always @(posedge clk)begin
   if(rst)begin cell_d<=0;cell_value<=0;cell_x<=0;cell_y<=0;end
   else begin cell_d<=cell_end&&!learning&&ref_valid;
     if(cell_end)begin cell_value<=cell_bit;cell_x<=bx;cell_y<=by;end
   end
 end
 wire wv;wire [GX-1:0] wx;wire [GY-1:0] wy;
 wire [1:0] p00,p01,p02,p10,p11,p12,p20,p21,p22;
 case4_window3x3 #(.DATA_BITS(2),.IMG_WIDTH(GW),.IMG_HEIGHT(GH)) window(
  .clk(clk),.rst(rst||!enable||learn_changed||frame_start),.in_valid(cell_d),.in_x(cell_x),.in_y(cell_y),
  .in_pixel({reference_q,cell_value}),.out_valid(wv),.out_x(wx),.out_y(wy),
  .p00(p00),.p01(p01),.p02(p02),.p10(p10),.p11(p11),.p12(p12),.p20(p20),.p21(p21),.p22(p22));
 wire current_near=p00[0]|p01[0]|p02[0]|p10[0]|p11[0]|p12[0]|p20[0]|p21[0]|p22[0];
 wire reference_near=p00[1]|p01[1]|p02[1]|p10[1]|p11[1]|p12[1]|p20[1]|p21[1]|p22[1];
 wire missing=p11[1]&&!current_near,extra=p11[0]&&!reference_near;
 wire [AB-1:0] wa=wy*GW+wx;
 wire [16:0] next_missing={1'b0,count_missing}+missing,next_extra={1'b0,count_extra}+extra;
 wire [15:0] fail_limit=(reference_count>>6)<4?16'd4:(reference_count>>6);
 always @(posedge clk)if(wv&&enable&&!learn_changed&&!frame_start)begin
   if(back_bank)overlay1[wa]<={missing,extra};else overlay0[wa]<={missing,extra};
 end
 reg [1:0] oq0,oq1;reg draw_ok,draw_bank;
 wire draw_inside=pixel_valid&&x>=ROI&&x<IMG_WIDTH&&y<IMG_HEIGHT&&bx>0&&bx<GW-1&&by>0&&by<GH-1;
 always @(posedge clk)begin
   if(draw_inside)begin oq0<=overlay0[cell_addr];oq1<=overlay1[cell_addr];end
   draw_ok<=!rst&&enable&&draw_inside&&ref_valid&&status>=3&&source_id==result_frame_id;
   draw_bank<=front_bank;
   overlay_code<=draw_ok?(draw_bank?oq1:oq0):2'b00;
 end
 always @(posedge clk)begin
  if(rst)begin
   column_or<=0;learn_seen<=0;learn_pending<=0;learning<=0;capture<=0;ref_valid<=0;
   front_bank<=0;back_bank<=1;pending_result<=0;pending_fail<=0;previous_fail<=0;
   capture_id<=0;pending_id<=0;capture_source<=0;pending_source<=0;
   status<=0;missing_cells<=0;extra_cells<=0;result_frame_id<=0;result_bank<=0;event_pulse<=0;
   count_missing<=0;count_extra<=0;reference_count<=0;learn_count<=0;pending_missing<=0;pending_extra<=0;
  end else begin
   event_pulse<=0;
   if(learn_changed)begin learn_seen<=learn_toggle;learn_pending<=1;end
   if(!enable)begin
    capture<=0;learning<=0;pending_result<=0;previous_fail<=0;
    status<=ref_valid?2:0;
   end else if(frame_start)begin
    column_or<=0;count_missing<=0;count_extra<=0;learn_count<=0;
    capture<=enable&&source_valid;capture_id<=source_id;capture_source<=source_bank;
    learning<=source_valid&&learn_request;
    if(pending_result&&!learn_request)begin
     front_bank<=back_bank;back_bank<=front_bank;pending_result<=0;
     missing_cells<=pending_missing;extra_cells<=pending_extra;
     result_frame_id<=pending_id;result_bank<=pending_source;status<=pending_fail?4:3;
     previous_fail<=pending_fail;
     if(pending_fail&&!previous_fail)event_pulse<=1;
    end
    if(source_valid&&learn_request)begin
      learn_pending<=0;status<=1;ref_valid<=0;previous_fail<=0;pending_result<=0;
    end else if(learn_request)begin pending_result<=0;ref_valid<=0;status<=0;end
    else if(!ref_valid)status<=0;
   end else if(learn_changed)begin
    capture<=0;learning<=0;pending_result<=0;ref_valid<=0;previous_fail<=0;status<=0;
   end
   if(take)column_or[bx]<=cell_end?1'b0:column_or[bx]|edge_bit;
   if(cell_end&&learning)begin
     if(cell_bit)learn_count<=learn_count+1'b1;
     if(bx==GW-1&&by==GH-1)begin
       reference_count<=learn_count+cell_bit;
       ref_valid<=learn_count+cell_bit>=MIN_REFERENCE;
       status<=learn_count+cell_bit>=MIN_REFERENCE?2:0;
     end
   end
   if(wv&&enable&&!learn_changed&&!frame_start)begin
    count_missing<=next_missing[16]?16'hffff:next_missing[15:0];
    count_extra<=next_extra[16]?16'hffff:next_extra[15:0];
    if(wx==GW-2&&wy==GH-2)begin
      pending_missing<=next_missing[15:0];pending_extra<=next_extra[15:0];
      pending_fail<=next_missing+next_extra>fail_limit;
      pending_id<=capture_id;pending_source<=capture_source;pending_result<=1;
    end
   end
  end
 end
endmodule
