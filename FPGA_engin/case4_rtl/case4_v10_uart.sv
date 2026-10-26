`timescale 1ns/1ps
// UART transports controls only. HDMI capture carries video; no thumbnail RAM.
// Command 01/seq/9-byte payload -> ACK80/seq/66-byte payload (id,result,status64).
module case4_v10_uart #(
 parameter integer CLK_HZ=148800000,BAUD=460800
)(
 input wire clk,rst_n,rx_i,output wire tx_o,
 output reg cmd_valid,output reg [7:0] cmd_id,
 output reg [15:0] cmd_arg0,cmd_arg1,cmd_arg2,cmd_arg3,
 input wire cmd_accept,input wire [7:0] cmd_result,input wire [511:0] status_data,
 output reg heartbeat,output wire busy
);
 localparam integer DIV=(CLK_HZ+BAUD/2)/BAUD;
 function automatic [15:0] crc_byte(input [15:0] c,input [7:0] b);
  integer k;reg [15:0] q;begin q=c^{b,8'b0};for(k=0;k<8;k=k+1)q=q[15]?(q<<1)^16'h1021:q<<1;crc_byte=q;end
 endfunction
 (* async_reg="true" *) reg rx_meta,rx_sync;
 reg [2:0] rx_state;integer rx_count;reg [2:0] rx_bit;
 reg [7:0] rx_shift,rx_byte;reg rx_strobe;
 always @(posedge clk)begin
  if(!rst_n)begin rx_meta<=1;rx_sync<=1;rx_state<=0;rx_count<=0;rx_bit<=0;rx_shift<=0;rx_byte<=0;rx_strobe<=0;end
  else begin
   rx_meta<=rx_i;rx_sync<=rx_meta;rx_strobe<=0;
   case(rx_state)
    0:if(!rx_sync)begin rx_state<=1;rx_count<=DIV/2;end
    1:if(rx_count!=0)rx_count<=rx_count-1;else if(!rx_sync)begin rx_state<=2;rx_count<=DIV-1;rx_bit<=0;end else rx_state<=0;
    2:if(rx_count!=0)rx_count<=rx_count-1;else begin rx_shift[rx_bit]<=rx_sync;rx_count<=DIV-1;if(rx_bit==7)rx_state<=3;else rx_bit<=rx_bit+1'b1;end
    3:if(rx_count!=0)rx_count<=rx_count-1;else begin if(rx_sync)begin rx_byte<=rx_shift;rx_strobe<=1;end rx_state<=0;end
    default:rx_state<=0;
   endcase
  end
 end
 reg [3:0] ps;reg [7:0] ptype,pseq,crc_lo;reg [15:0] plen,pindex,pcrc;reg [71:0] ppayload;
 reg packet_ready;reg [7:0] packet_seq;reg [71:0] packet_data;integer timeout_count;
 always @(posedge clk)begin
  if(!rst_n)begin ps<=0;ptype<=0;pseq<=0;plen<=0;pindex<=0;pcrc<=16'hffff;ppayload<=0;crc_lo<=0;packet_ready<=0;packet_seq<=0;packet_data<=0;timeout_count<=0;end
  else begin
   packet_ready<=0;
   if(ps!=0)begin if(timeout_count>=CLK_HZ/20)begin ps<=0;timeout_count<=0;end else timeout_count<=timeout_count+1;end
   if(rx_strobe)begin
    timeout_count<=0;
    case(ps)
     0:if(rx_byte==8'h55)ps<=1;
     1:if(rx_byte==8'haa)begin ps<=2;pcrc<=16'hffff;end else if(rx_byte!=8'h55)ps<=0;
     2:begin ptype<=rx_byte;pcrc<=crc_byte(pcrc,rx_byte);ps<=3;end
     3:begin pseq<=rx_byte;pcrc<=crc_byte(pcrc,rx_byte);ps<=4;end
     4:begin plen[7:0]<=rx_byte;pcrc<=crc_byte(pcrc,rx_byte);ps<=5;end
     5:begin plen[15:8]<=rx_byte;pcrc<=crc_byte(pcrc,rx_byte);pindex<=0;ppayload<=0;ps<=(ptype==1&&{rx_byte,plen[7:0]}==9)?6:0;end
     6:begin ppayload[pindex*8+:8]<=rx_byte;pcrc<=crc_byte(pcrc,rx_byte);if(pindex==8)ps<=7;else pindex<=pindex+1'b1;end
     7:begin crc_lo<=rx_byte;ps<=8;end
     8:begin ps<=0;if({rx_byte,crc_lo}==pcrc)begin packet_ready<=1;packet_seq<=pseq;packet_data<=ppayload;end end
     default:ps<=0;
    endcase
   end
  end
 end
 reg [9:0] tx_shift;integer tx_count;reg [3:0] tx_bits;wire byte_busy=tx_bits!=0;
 reg byte_start;reg [7:0] byte_data;assign tx_o=tx_shift[0];
 always @(posedge clk)begin
  if(!rst_n)begin tx_shift<=10'h3ff;tx_count<=0;tx_bits<=0;end
  else if(byte_start&&!byte_busy)begin tx_shift<={1'b1,byte_data,1'b0};tx_bits<=10;tx_count<=DIV-1;end
  else if(byte_busy)begin if(tx_count!=0)tx_count<=tx_count-1;else begin tx_shift<={1'b1,tx_shift[9:1]};tx_bits<=tx_bits-1'b1;tx_count<=DIV-1;end end
 end
 reg tx_active;reg [6:0] tx_index;reg [15:0] tx_crc;
 reg [7:0] active_seq,active_id,active_result;reg [511:0] ack_status;
 reg [7:0] tx_value;reg tx_launched,last_valid,ack_pending;
 reg [7:0] last_seq,last_result;reg [71:0] last_data;
 assign busy=tx_active||cmd_valid||ack_pending;
 always @*begin
  case(tx_index)
   0:tx_value=8'h55;1:tx_value=8'haa;2:tx_value=8'h80;3:tx_value=active_seq;
   4:tx_value=8'd66;5:tx_value=0;6:tx_value=active_id;7:tx_value=active_result;
   72:tx_value=tx_crc[7:0];73:tx_value=tx_crc[15:8];
   default:tx_value=tx_index>=8&&tx_index<72?ack_status[(tx_index-8)*8+:8]:0;
  endcase
 end
 always @(posedge clk)begin
  if(!rst_n)begin
   cmd_valid<=0;cmd_id<=0;cmd_arg0<=0;cmd_arg1<=0;cmd_arg2<=0;cmd_arg3<=0;heartbeat<=0;
   tx_active<=0;tx_index<=0;tx_crc<=16'hffff;active_seq<=0;active_id<=0;active_result<=0;ack_status<=0;
   byte_start<=0;byte_data<=0;tx_launched<=0;last_valid<=0;last_seq<=0;last_data<=0;last_result<=0;ack_pending<=0;
  end else begin
   byte_start<=0;heartbeat<=0;
   if(packet_ready&&!busy)begin
    active_seq<=packet_seq;active_id<=packet_data[7:0];
    if(packet_data[7:0]==8'hf1)heartbeat<=1;
    if(last_valid&&last_seq==packet_seq&&last_data==packet_data)begin
     active_result<=last_result;ack_status<=status_data;tx_active<=1;tx_index<=0;tx_crc<=16'hffff;
    end else begin
     last_seq<=packet_seq;last_data<=packet_data;last_valid<=0;
     if(packet_data[7:0]==8'hf1)begin active_result<=0;last_result<=0;last_valid<=1;ack_status<=status_data;tx_active<=1;tx_index<=0;tx_crc<=16'hffff;end
     else begin cmd_id<=packet_data[7:0];cmd_arg0<=packet_data[23:8];cmd_arg1<=packet_data[39:24];cmd_arg2<=packet_data[55:40];cmd_arg3<=packet_data[71:56];cmd_valid<=1;end
    end
   end
   if(cmd_valid&&cmd_accept)begin cmd_valid<=0;active_result<=cmd_result;last_result<=cmd_result;last_valid<=1;ack_pending<=1;end
   if(ack_pending)begin ack_pending<=0;ack_status<=status_data;tx_active<=1;tx_index<=0;tx_crc<=16'hffff;end
   if(tx_active&&tx_index<74&&!byte_busy&&!byte_start&&!tx_launched)begin
    byte_data<=tx_value;byte_start<=1;tx_launched<=1;
    if(tx_index>=2&&tx_index<72)tx_crc<=crc_byte(tx_crc,tx_value);
   end
   if(tx_launched&&byte_busy)begin tx_launched<=0;tx_index<=tx_index+1'b1;end
   if(tx_active&&tx_index==74&&!byte_busy&&!byte_start&&!tx_launched)begin tx_active<=0;tx_index<=0;end
  end
 end
endmodule
