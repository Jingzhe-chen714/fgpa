`timescale 1ns/1ps
// Preserve an already published edge map, optionally its original RGB565 frame.
// Each destination byte holds one selected edge bit. Captures remain invalid
// until every read and write response succeeds; no host-video colour inference.
module case4_v11_pair_copy #(
 parameter integer W=1920,H=1080,MAX_BEATS=1,
 parameter [31:0] EDGE_A_BASE=32'h00800000,EDGE_B_BASE=32'h00a00000,RGB_B_BASE=32'h00c00000
)(
 input wire clk,rst,start,select_b,stable_bit,
 input wire [31:0] map_base,rgb_base,
 output wire busy,output reg done,failed,
 output reg [31:0] m_awaddr,output reg [7:0] m_awlen,
 output wire m_awvalid,input wire m_awready,
 output wire [127:0] m_wdata,output wire [15:0] m_wstrb,
 output wire m_wlast,m_wvalid,input wire m_wready,
 input wire [1:0] m_bresp,input wire m_bvalid,output wire m_bready,
 output reg [31:0] m_araddr,output reg [7:0] m_arlen,
 output wire m_arvalid,input wire m_arready,
 input wire [127:0] m_rdata,input wire [1:0] m_rresp,
 input wire m_rlast,m_rvalid,output wire m_rready
);
 localparam IDLE=0,PREP=1,READ_ADDR=2,READ_DATA=3,WRITE_ADDR=4,WRITE_DATA=5,WRITE_RESP=6,NEXT=7;
 reg [2:0] state;
 reg phase_rgb,capture_b,edge_select;
 reg [31:0] source_map,source_rgb,offset;
 reg [8:0] beats;
 reg [7:0] rd_beat,wr_beat;
 reg read_failed;
 reg [127:0] scratch[0:MAX_BEATS-1];reg [127:0] write_word;
 wire write_take=m_wvalid&&m_wready;
 wire [7:0] next_write_addr=write_take&&!m_wlast?wr_beat+1'b1:wr_beat;
 always @(posedge clk)write_word<=scratch[next_write_addr];
 wire [31:0] total=phase_rgb?W*H*2:W*H;
 wire [31:0] remain_beats=(total-offset)>>4;
 wire [8:0] page_beats=9'd256-{1'b0,offset[11:4]};
 wire [8:0] limit=page_beats<MAX_BEATS?page_beats:MAX_BEATS;
 wire [8:0] chosen=remain_beats<limit?remain_beats[8:0]:limit;
 wire [31:0] source=phase_rgb?source_rgb:source_map;
 wire [31:0] destination=phase_rgb?RGB_B_BASE:(capture_b?EDGE_B_BASE:EDGE_A_BASE);
 wire [127:0] selected_data;
 genvar k;
 generate for(k=0;k<16;k=k+1)begin:lane
  assign selected_data[k*8+:8]={7'd0,m_rdata[k*8+(edge_select?1:0)]};
 end endgenerate
 assign busy=state!=IDLE;
 assign m_awvalid=state==WRITE_ADDR;
 assign m_wvalid=state==WRITE_DATA;
 assign m_wlast={1'b0,wr_beat}==beats-1;
 assign m_wdata=write_word;assign m_wstrb=16'hffff;
 assign m_bready=state==WRITE_RESP;
 assign m_arvalid=state==READ_ADDR;assign m_rready=state==READ_DATA;
 always @(posedge clk)begin
  if(rst)begin
   state<=IDLE;phase_rgb<=0;capture_b<=0;edge_select<=0;source_map<=0;source_rgb<=0;
   offset<=0;beats<=0;rd_beat<=0;wr_beat<=0;read_failed<=0;done<=0;failed<=0;
   m_awaddr<=0;m_awlen<=0;m_araddr<=0;m_arlen<=0;
  end else begin
   done<=0;
   case(state)
    IDLE:if(start)begin
     capture_b<=select_b;edge_select<=stable_bit;source_map<=map_base;source_rgb<=rgb_base;
     phase_rgb<=0;offset<=0;failed<=0;state<=PREP;
    end
    PREP:begin
     beats<=chosen;m_araddr<=source+offset;m_awaddr<=destination+offset;
     m_arlen<=chosen-1'b1;m_awlen<=chosen-1'b1;rd_beat<=0;wr_beat<=0;read_failed<=0;state<=READ_ADDR;
    end
    READ_ADDR:if(m_arready)state<=READ_DATA;
    READ_DATA:if(m_rvalid)begin
     if(rd_beat<MAX_BEATS)scratch[rd_beat]<=phase_rgb?m_rdata:selected_data;
     if(m_rresp!=0||m_rlast!=({1'b0,rd_beat}==beats-1))read_failed<=1;
     if(m_rlast)begin
      if(read_failed||m_rresp!=0||{1'b0,rd_beat}!=beats-1)begin failed<=1;done<=1;state<=IDLE;end
      else state<=WRITE_ADDR;
     end else if({1'b0,rd_beat}<beats-1)rd_beat<=rd_beat+1'b1;
    end
    WRITE_ADDR:if(m_awready)state<=WRITE_DATA;
    WRITE_DATA:if(m_wready)begin
     if(m_wlast)state<=WRITE_RESP;else wr_beat<=wr_beat+1'b1;
    end
    WRITE_RESP:if(m_bvalid)begin
     if(m_bresp!=0)begin failed<=1;done<=1;state<=IDLE;end
     else state<=NEXT;
    end
    NEXT:begin
     if(offset+({23'd0,beats}<<4)>=total)begin
      if(capture_b&&!phase_rgb)begin phase_rgb<=1;offset<=0;state<=PREP;end
      else begin done<=1;state<=IDLE;end
     end else begin offset<=offset+({23'd0,beats}<<4);state<=PREP;end
    end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
