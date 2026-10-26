`timescale 1ns/1ps
// Sparse PC drawing instructions -> complete, acknowledged DDR palette frame.
// The display owns one 2 MiB slot. This engine clears/draws only the other slot,
// and cannot reuse the old front until the store acknowledges the publication.
// Command RAM is intentionally single buffered: UART must obey load_ready and
// keep submit_count stable until submit_ack. CRC is checked before submission.
module case4_v11_face_renderer #(
 parameter integer W=1920,H=1080,
 parameter [31:0] BASE0=32'h00400000,BASE1=32'h00600000
)(
 input wire cmd_clk,cmd_rst_n,cmd_wr_en,
 input wire [9:0] cmd_wr_addr,input wire [31:0] cmd_wr_data,
 input wire submit_toggle,input wire [10:0] submit_count,
 output wire load_ready,output wire submit_ack,
 input wire clk,rst,
 output reg busy,output reg [7:0] fault_code,
 output reg publish_toggle,publish_slot,input wire publish_ack,
 output wire [31:0] m_awaddr,output wire [7:0] m_awlen,
 output wire m_awvalid,input wire m_awready,
 output wire [127:0] m_wdata,output wire [15:0] m_wstrb,
 output wire m_wlast,m_wvalid,input wire m_wready,
 input wire [1:0] m_bresp,input wire m_bvalid,output wire m_bready
);
 (* ram_style="block" *) reg [31:0] commands[0:1023];
 reg finished_submit;
 (* async_reg="true" *) reg [2:0] submit_sync,finished_sync;
 (* async_reg="true" *) reg [1:0] busy_sync;
 reg seen_submit;
 assign submit_ack=finished_sync[2];
 assign load_ready=cmd_rst_n&&!busy_sync[1]&&(submit_toggle==finished_sync[2]);
 always @(posedge cmd_clk)begin
  if(cmd_wr_en&&load_ready)commands[cmd_wr_addr]<=cmd_wr_data;
  if(!cmd_rst_n)begin finished_sync<=0;busy_sync<=0;end
  else begin finished_sync<={finished_sync[1:0],finished_submit};busy_sync<={busy_sync[0],busy};end
 end
 always @(posedge clk)begin
  if(rst)submit_sync<=0;else submit_sync<={submit_sync[1:0],submit_toggle};
 end
 reg [10:0] pc,count;
 reg [31:0] instruction;
 always @(posedge clk)instruction<=commands[pc[9:0]];
 localparam IDLE=0,CLEAR_REQ=1,CLEAR_WAIT=2,FETCH=3,DECODE=4,
  LINE_SETUP=5,LINE_PIXEL=6,LINE_ROW_NEXT=7,SPAN_REQ=8,SPAN_WAIT=9,
  LINE_STEP=10,CIRCLE_READ=11,CIRCLE_DECODE=12,CIRCLE_SPAN=13,CIRCLE_NEXT=14,
  TRAP_READ0=15,TRAP_LOAD0=16,TRAP_READ1=17,TRAP_LOAD1=18,
  TRAP_READ2=19,TRAP_LOAD2=20,TRAP_READ3=21,TRAP_LOAD3=22,
  TRAP_ROW=23,TRAP_NEXT=24,SPAN_ADDRESS=25,FINISH=26,WAIT_PUBLISH=27,FAULT=28;
 reg [4:0] state,span_return;
 reg front_slot,target_slot;
 wire [31:0] target_base=target_slot?BASE1:BASE0;
 reg [3:0] color;
 reg [2:0] stroke,stroke_row;
 // All MOVE/LINE/CIRCLE coordinates are checked against W/H before use.
 // Keep a sign bit because clipped strokes and circles can extend negative.
 localparam integer MAX_SIZE=W>H?W:H,MIN_SIZE=W<H?W:H;
 localparam integer COORD_BITS=$clog2(MAX_SIZE+1)+1;
 localparam integer LINE_ERROR_BITS=COORD_BITS+1;
 // A circle span can reach center+radius+1, not merely the active width.
 localparam integer SPAN_BITS=$clog2(MAX_SIZE+MIN_SIZE+2)+1;
 localparam integer CIRCLE_BITS=$clog2(MIN_SIZE+1)+1;
 localparam integer CIRCLE_ERROR_BITS=$clog2(4*MIN_SIZE+4)+1;
 localparam integer TRAP_STEP_BITS=$clog2((W<<8)+1)+1;
 wire signed [2:0] half_stroke=(stroke-1'b1)>>1;
 reg point_valid;
 reg signed [COORD_BITS-1:0] previous_x,previous_y,line_x,line_y,end_x,end_y;
 reg signed [COORD_BITS-1:0] line_dx,line_dy;
 // Integer Bresenham error stays within twice the longest coordinate delta.
 reg signed [LINE_ERROR_BITS-1:0] line_error;
 reg signed [1:0] line_sx,line_sy;
 wire signed [LINE_ERROR_BITS:0] twice_error=$signed(line_error)*2;
 wire move_x=twice_error>=$signed(line_dy),move_y=twice_error<=$signed(line_dx);
 wire signed [COORD_BITS:0] error_adjust=(move_x?$signed(line_dy):$signed({COORD_BITS{1'b0}}))+(move_y?$signed(line_dx):$signed({COORD_BITS{1'b0}}));
 reg signed [COORD_BITS-1:0] center_x,center_y;
 reg signed [CIRCLE_BITS-1:0] circle_x,circle_y;
 reg signed [CIRCLE_ERROR_BITS-1:0] circle_error;
 reg [1:0] circle_span;
 reg [11:0] trap_y,trap_end;
 reg signed [31:0] trap_left,trap_right;
 reg signed [TRAP_STEP_BITS-1:0] trap_dl,trap_dr;
 reg signed [SPAN_BITS-1:0] span_left,span_right,span_y;
 wire signed [SPAN_BITS-1:0] clipped_left=span_left<0?0:span_left;
 wire signed [SPAN_BITS-1:0] clipped_right=span_right>W?W:span_right;
 wire signed [31:0] trap_pixel_left=(trap_left+255)>>>8;
 wire signed [31:0] trap_pixel_right=(trap_right+255)>>>8;
 reg request;
 reg [31:0] write_address;
 reg [21:0] write_count;
 reg [7:0] write_color;
 wire writer_ready,writer_done,writer_failed;
 case4_v11_palette_writer writer(
  .clk(clk),.rst(rst),.request(request),.byte_address(write_address),
  .byte_count(write_count),.palette(write_color),.ready(writer_ready),
  .done(writer_done),.failed(writer_failed),
  .m_awaddr(m_awaddr),.m_awlen(m_awlen),.m_awvalid(m_awvalid),.m_awready(m_awready),
  .m_wdata(m_wdata),.m_wstrb(m_wstrb),.m_wlast(m_wlast),.m_wvalid(m_wvalid),.m_wready(m_wready),
  .m_bresp(m_bresp),.m_bvalid(m_bvalid),.m_bready(m_bready));
 wire [3:0] opcode=instruction[31:28],new_color=instruction[27:24];
 wire [11:0] ix=instruction[23:12],iy=instruction[11:0];
 wire signed [31:0] fixed_value={{8{instruction[23]}},instruction[23:0]};
 always @(posedge clk)begin
  if(rst)begin
   state<=IDLE;span_return<=IDLE;busy<=0;fault_code<=0;finished_submit<=0;seen_submit<=0;
   publish_toggle<=0;publish_slot<=0;front_slot<=0;target_slot<=1;pc<=0;count<=0;
   request<=0;write_address<=0;write_count<=0;write_color<=0;color<=0;stroke<=1;stroke_row<=0;
   point_valid<=0;previous_x<=0;previous_y<=0;line_x<=0;line_y<=0;end_x<=0;end_y<=0;
   line_dx<=0;line_dy<=0;line_error<=0;line_sx<=0;line_sy<=0;
   center_x<=0;center_y<=0;circle_x<=0;circle_y<=0;circle_error<=0;circle_span<=0;
   trap_y<=0;trap_end<=0;trap_left<=0;trap_right<=0;trap_dl<=0;trap_dr<=0;
   span_left<=0;span_right<=0;span_y<=0;
  end else begin
   request<=0;
   case(state)
    IDLE:if(submit_sync[2]!=seen_submit)begin
     seen_submit<=submit_sync[2];busy<=1;fault_code<=0;count<=submit_count;pc<=0;
     target_slot<=!front_slot;point_valid<=0;stroke<=1;
     if(submit_count>1024)begin fault_code<=1;state<=FAULT;end else state<=CLEAR_REQ;
    end
    CLEAR_REQ:if(writer_ready)begin
     write_address<=target_base;write_count<=W*H;write_color<=0;request<=1;state<=CLEAR_WAIT;
    end
    CLEAR_WAIT:if(writer_done)begin
     if(writer_failed)begin fault_code<=2;state<=FAULT;end else state<=FETCH;
    end
    FETCH:begin if(pc>=count)state<=FINISH;else state<=DECODE;end
    DECODE:begin
     pc<=pc+1'b1;
     case(opcode)
      0:if(instruction==0)state<=FETCH;else begin fault_code<=3;state<=FAULT;end
      1:if(ix<W&&iy<H&&new_color==0)begin previous_x<=ix;previous_y<=iy;point_valid<=1;state<=FETCH;end
        else begin fault_code<=3;state<=FAULT;end
      2:if(point_valid&&ix<W&&iy<H&&new_color>=1&&new_color<=9)begin
        line_x<=previous_x;line_y<=previous_y;end_x<=ix;end_y<=iy;
        previous_x<=ix;previous_y<=iy;color<=new_color;state<=LINE_SETUP;
       end else begin fault_code<=3;state<=FAULT;end
      3:if(instruction[27:8]==0&&instruction[7:0]>=1&&instruction[7:0]<=3)begin
        stroke<=instruction[2:0];state<=FETCH;
       end else begin fault_code<=3;state<=FAULT;end
      4:if(ix<iy&&iy<=H&&pc+5<=count&&new_color>=1&&new_color<=9)begin
        trap_y<=ix;trap_end<=iy;color<=new_color;state<=TRAP_READ0;
       end else begin fault_code<=3;state<=FAULT;end
      5:if(ix<W&&iy<H&&pc+2<=count&&new_color>=1&&new_color<=9)begin
        center_x<=ix;center_y<=iy;color<=new_color;state<=CIRCLE_READ;
       end else begin fault_code<=3;state<=FAULT;end
      default:begin fault_code<=4;state<=FAULT;end
     endcase
    end
    LINE_SETUP:begin
     line_dx<=end_x>=line_x?end_x-line_x:line_x-end_x;
     line_dy<=end_y>=line_y?line_y-end_y:end_y-line_y;
     line_error<=(end_x>=line_x?end_x-line_x:line_x-end_x)-(end_y>=line_y?end_y-line_y:line_y-end_y);
     line_sx<=end_x>=line_x?2'sd1:-2'sd1;line_sy<=end_y>=line_y?2'sd1:-2'sd1;
     stroke_row<=0;state<=LINE_PIXEL;
    end
    LINE_PIXEL:begin
     span_left<=$signed(line_x)-half_stroke;
     span_right<=$signed(line_x)-half_stroke+stroke;
     span_y<=$signed(line_y)-half_stroke+stroke_row;
     span_return<=LINE_ROW_NEXT;state<=SPAN_ADDRESS;
    end
    LINE_ROW_NEXT:if(stroke_row+1>=stroke)begin stroke_row<=0;state<=LINE_STEP;end
      else begin stroke_row<=stroke_row+1'b1;state<=LINE_PIXEL;end
    LINE_STEP:if(line_x==end_x&&line_y==end_y)state<=FETCH;
      else begin
       if(move_x)line_x<=line_x+line_sx;if(move_y)line_y<=line_y+line_sy;
       line_error<=line_error+error_adjust;state<=LINE_PIXEL;
      end
    CIRCLE_READ:state<=CIRCLE_DECODE;
    CIRCLE_DECODE:if(instruction[31:12]==0&&instruction[11:0]<=MIN_SIZE)begin
      circle_x<=instruction[11:0];circle_y<=0;circle_error<=16'sd1-$signed({4'b0,instruction[11:0]});
      circle_span<=0;pc<=pc+1'b1;state<=CIRCLE_SPAN;
     end else begin fault_code<=3;state<=FAULT;end
    CIRCLE_SPAN:begin
     if(circle_span<2)begin
      span_left<=$signed(center_x)-$signed(circle_x);span_right<=$signed(center_x)+$signed(circle_x)+1;
      span_y<=circle_span==0?$signed(center_y)+$signed(circle_y):$signed(center_y)-$signed(circle_y);
     end else begin
      span_left<=$signed(center_x)-$signed(circle_y);span_right<=$signed(center_x)+$signed(circle_y)+1;
      span_y<=circle_span==2?$signed(center_y)+$signed(circle_x):$signed(center_y)-$signed(circle_x);
     end
     span_return<=CIRCLE_NEXT;state<=SPAN_ADDRESS;
    end
    CIRCLE_NEXT:if(circle_span!=3)begin circle_span<=circle_span+1'b1;state<=CIRCLE_SPAN;end
     else if((circle_error<0?circle_x:circle_x-1)<circle_y+1)state<=FETCH;
     else begin
      circle_span<=0;circle_y<=circle_y+1;
      if(circle_error<0)circle_error<=circle_error+2*circle_y+3;
      else begin circle_error<=circle_error+2*(circle_y-circle_x)+5;circle_x<=circle_x-1;end
      state<=CIRCLE_SPAN;
     end
    TRAP_READ0:state<=TRAP_LOAD0;
    TRAP_LOAD0:if(instruction[31:24]!=0)begin fault_code<=3;state<=FAULT;end
     else begin trap_left<=fixed_value;pc<=pc+1'b1;state<=TRAP_READ1;end
    TRAP_READ1:state<=TRAP_LOAD1;
    TRAP_LOAD1:if(instruction[31:24]!=0)begin fault_code<=3;state<=FAULT;end
     else begin trap_right<=fixed_value;pc<=pc+1'b1;state<=TRAP_READ2;end
    TRAP_READ2:state<=TRAP_LOAD2;
    TRAP_LOAD2:if(instruction[31:24]!=0||fixed_value<-(W<<8)||fixed_value>(W<<8))begin fault_code<=3;state<=FAULT;end
     else begin trap_dl<=fixed_value;pc<=pc+1'b1;state<=TRAP_READ3;end
    TRAP_READ3:state<=TRAP_LOAD3;
    TRAP_LOAD3:if(instruction[31:24]!=0||fixed_value<-(W<<8)||fixed_value>(W<<8))begin fault_code<=3;state<=FAULT;end
     else begin trap_dr<=fixed_value;pc<=pc+1'b1;state<=TRAP_ROW;end
    TRAP_ROW:if(trap_right<trap_left)begin fault_code<=3;state<=FAULT;end
     else begin
      span_left<=trap_pixel_left<0?0:trap_pixel_left>W?W:trap_pixel_left[15:0];
      span_right<=trap_pixel_right<0?0:trap_pixel_right>W?W:trap_pixel_right[15:0];span_y<={4'b0,trap_y};
      span_return<=TRAP_NEXT;state<=SPAN_ADDRESS;
     end
    TRAP_NEXT:if(trap_y+1>=trap_end)state<=FETCH;
     else begin trap_y<=trap_y+1'b1;trap_left<=trap_left+trap_dl;trap_right<=trap_right+trap_dr;state<=TRAP_ROW;end
    SPAN_ADDRESS:if(span_y<0||span_y>=H||clipped_right<=clipped_left||clipped_right<=0||clipped_left>=W)state<=span_return;
     else begin
      write_address<=target_base+span_y*W+clipped_left;
      write_count<=clipped_right-clipped_left;write_color<={4'b0,color};state<=SPAN_REQ;
     end
    SPAN_REQ:if(writer_ready)begin request<=1;state<=SPAN_WAIT;end
    SPAN_WAIT:if(writer_done)begin
     if(writer_failed)begin fault_code<=2;state<=FAULT;end else state<=span_return;
    end
    FINISH:begin publish_slot<=target_slot;publish_toggle<=!publish_toggle;state<=WAIT_PUBLISH;end
    WAIT_PUBLISH:if(publish_ack==publish_toggle)begin
     front_slot<=target_slot;finished_submit<=seen_submit;busy<=0;state<=IDLE;
    end
    FAULT:begin finished_submit<=seen_submit;busy<=0;state<=IDLE;end
    default:begin fault_code<=5;state<=FAULT;end
   endcase
  end
 end
endmodule
