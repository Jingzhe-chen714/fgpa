`timescale 1ns/1ps
// Read-only diagnostics. Sensor observation deliberately survives DDR reset.
// Source payloads are held until a round-trip request/ack completes; a stopped
// camera clock cannot block the independent system-clock diagnostic channel.
module case4_v12_diag_snapshot #(parameter WIDTH=32)(
 input wire src_clk,src_rst,input wire [WIDTH-1:0] src_data,
 input wire dst_clk,dst_rst,trigger,
 output reg [WIDTH-1:0] dst_data,output wire alive
);
 reg request,ack,pending,observed;
 (* async_reg="true" *) reg [1:0] request_sync;
 (* async_reg="true" *) reg [2:0] ack_sync;
 reg [WIDTH-1:0] held,data_meta,data_sync;
 reg [2:0] age;
 always @(posedge src_clk or posedge src_rst) begin
  if(src_rst)begin request_sync<=0;ack<=0;held<=0;end
  else begin
   request_sync<={request_sync[0],request};
   if(request_sync[1]!=ack)begin held<=src_data;ack<=request_sync[1];end
  end
 end
 always @(posedge dst_clk or posedge dst_rst) begin
  if(dst_rst)begin request<=0;pending<=0;observed<=0;age<=7;
   ack_sync<=0;data_meta<=0;data_sync<=0;dst_data<=0;end
  else begin
   ack_sync<={ack_sync[1:0],ack};data_meta<=held;data_sync<=data_meta;
   if(trigger)begin
    if(age!=7)age<=age+1'b1;
    if(!pending)begin request<=!request;pending<=1;end
   end
   if(pending&&ack_sync[2]==request)begin
    dst_data<=data_sync;pending<=0;observed<=1;age<=0;
   end
  end
 end
 assign alive=observed&&age<4;
endmodule

module case4_v12_capture_diag(
 input wire sys_clk,sys_rst,pixel_clk,pixel_rst,pixel_vs,
 input wire camera_clk,camera_vs,camera_de,input wire [7:0] camera_data,
 input wire cal_done,cal_pass,i2c_done,i2c_nack_seen,
 input wire [7:0] store_camera_flags,store_axi_flags,
 input wire [31:0] store_write_state,store_commits,
 output wire [31:0] diag0,diag1,diag2,diag3
);
 reg camera_vs_q,vs_seen,de_seen,data_seen,overflow_seen;
 reg [23:0] frame_bytes,last_frame_bytes;
 reg [7:0] camera_frames;
 always @(posedge camera_clk or posedge sys_rst)begin
  if(sys_rst)begin camera_vs_q<=0;vs_seen<=0;de_seen<=0;data_seen<=0;
   overflow_seen<=0;frame_bytes<=0;last_frame_bytes<=0;camera_frames<=0;end
  else begin
   camera_vs_q<=camera_vs;
   if(camera_vs!=camera_vs_q)vs_seen<=1;
   if(camera_de)begin
    de_seen<=1;if(camera_data!=0)data_seen<=1;
   end
   if(camera_vs_q&&!camera_vs)begin
    last_frame_bytes<=frame_bytes;frame_bytes<=0;camera_frames<=camera_frames+1'b1;
   end else if(camera_de)begin
    if(frame_bytes!=24'hffffff)frame_bytes<=frame_bytes+1'b1;
    else overflow_seen<=1;
   end
  end
 end
 reg pixel_vs_q;
 always @(posedge pixel_clk or posedge pixel_rst)
  if(pixel_rst)pixel_vs_q<=1;else pixel_vs_q<=pixel_vs;
 wire trigger=pixel_vs_q&&!pixel_vs;
 wire [47:0] camera_snapshot;
 wire [79:0] system_snapshot;
 wire camera_alive,system_alive;
 case4_v12_diag_snapshot #(.WIDTH(48)) cam_snapshot(
  .src_clk(camera_clk),.src_rst(sys_rst),
  .src_data({store_camera_flags,4'b0,vs_seen,de_seen,data_seen,overflow_seen,camera_frames,last_frame_bytes}),
  .dst_clk(pixel_clk),.dst_rst(pixel_rst),.trigger(trigger),.dst_data(camera_snapshot),.alive(camera_alive));
 case4_v12_diag_snapshot #(.WIDTH(80)) sys_snapshot(
  .src_clk(sys_clk),.src_rst(sys_rst),
  .src_data({4'b0,i2c_nack_seen,i2c_done,cal_done,cal_pass,store_axi_flags,store_write_state,store_commits}),
  .dst_clk(pixel_clk),.dst_rst(pixel_rst),.trigger(trigger),.dst_data(system_snapshot),.alive(system_alive));
 // 0: D1 | camera flags | store flags | PCLK,VS,DE,DATA,NACK,I2C,DONE,PASS
 assign diag0={8'hd1,camera_snapshot[47:40],system_snapshot[71:64],
  camera_alive,camera_snapshot[35:33],system_snapshot[75:72]};
 // 1: camera EOF count modulo256 | last complete sensor-frame byte count
 assign diag1=camera_snapshot[31:0];
 // 2: writer3,reader3,end_pending,end_good,write_failed,bus_error,offset22
 assign diag2=system_snapshot[63:32];
 // 3: number of original frames actually committed to DDR
 assign diag3=system_snapshot[31:0];
endmodule
