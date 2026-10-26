`timescale 1ns/1ps
// Byte-palette span writer. One acknowledged AXI burst at a time; bursts never
// cross 4 KiB. Partial first/last beats use byte strobes, not read/modify/write.
module case4_v11_palette_writer #(
 parameter integer MAX_BEATS=128
)(
 input wire clk,rst,
 input wire request,input wire [31:0] byte_address,
 input wire [21:0] byte_count,input wire [7:0] palette,
 output wire ready,output reg done,output reg failed,
 output reg [31:0] m_awaddr,output reg [7:0] m_awlen,
 output wire m_awvalid,input wire m_awready,
 output wire [127:0] m_wdata,output reg [15:0] m_wstrb,
 output wire m_wlast,m_wvalid,input wire m_wready,
 input wire [1:0] m_bresp,input wire m_bvalid,output wire m_bready
);
 localparam IDLE=0,PREP=1,ADDR=2,DATA=3,RESP=4;
 reg [2:0] state;
 reg [31:0] address;
 reg [21:0] remaining;
 reg [3:0] skip;
 reg [7:0] value,beat;
 reg [8:0] burst_beats;
 wire [22:0] covered={1'b0,remaining}+skip;
 wire [18:0] needed=(covered+15)>>4;
 wire [8:0] until_page=9'd256-{1'b0,address[11:4]};
 wire [8:0] page_limit=until_page<MAX_BEATS?until_page:MAX_BEATS;
 wire [8:0] next_beats=needed<page_limit?needed[8:0]:page_limit;
 wire [4:0] available=5'd16-{1'b0,skip};
 // A successful data beat consumes at most sixteen bytes. Keeping this mux
 // narrow preserves the full 22-bit remaining counter without a wide mux.
 wire [4:0] consumed=remaining<available?remaining[4:0]:available;
 wire [4:0] byte_limit={1'b0,skip}+consumed[4:0];
 assign ready=state==IDLE;
 assign m_awvalid=state==ADDR;
 assign m_wvalid=state==DATA;
 assign m_wlast={1'b0,beat}==burst_beats-1;
 assign m_wdata={16{value}};
 assign m_bready=state==RESP;
 integer j;
 always @* begin
  m_wstrb=0;
  for(j=0;j<16;j=j+1)
   if(j>=skip&&j<byte_limit)m_wstrb[j]=1'b1;
 end
 always @(posedge clk) begin
  if(rst)begin
   state<=IDLE;address<=0;remaining<=0;skip<=0;value<=0;beat<=0;
   burst_beats<=0;m_awaddr<=0;m_awlen<=0;done<=0;failed<=0;
  end else begin
   done<=0;
   case(state)
    IDLE:if(request)begin
     failed<=0;address<={byte_address[31:4],4'b0};skip<=byte_address[3:0];
     remaining<=byte_count;value<=palette;
     if(byte_count==0)done<=1;else state<=PREP;
    end
    PREP:begin
     burst_beats<=next_beats;m_awaddr<=address;m_awlen<=next_beats-1'b1;
     beat<=0;state<=ADDR;
    end
    ADDR:if(m_awready)state<=DATA;
    DATA:if(m_wready)begin
     remaining<=remaining-consumed;address<=address+16;skip<=0;
     if(m_wlast)state<=RESP;else beat<=beat+1'b1;
    end
    RESP:if(m_bvalid)begin
     if(m_bresp!=0)begin failed<=1;done<=1;state<=IDLE;end
     else if(remaining==0)begin done<=1;state<=IDLE;end
     else state<=PREP;
    end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
