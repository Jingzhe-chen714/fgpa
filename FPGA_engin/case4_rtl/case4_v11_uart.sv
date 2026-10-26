`timescale 1ns/1ps
// 55 AA,type,seq,lenLE16,payload,CRC16-CCITT. Type1 controls retain 9 bytes.
// Type2 = version,facecount,wordcountLE16,batchID,sourceID,revision,wordsLE32.
// All face words remain private until CRC/revision validation and submit toggle.
module case4_v11_uart #(
 parameter integer CLK_HZ=148800000,BAUD=460800
)(
 input wire clk,rst_n,rx_i,output wire tx_o,
 output reg cmd_valid,output reg [7:0] cmd_id,
 output reg [15:0] cmd_arg0,cmd_arg1,cmd_arg2,cmd_arg3,
 input wire cmd_accept,input wire [7:0] cmd_result,input wire [767:0] status_data,
 output reg heartbeat,output wire busy,
 input wire face_load_ready,face_submit_ack,input wire [7:0] face_result,
 output reg face_wr_en,output reg [9:0] face_wr_addr,output reg [31:0] face_wr_data,
 output reg face_submit_toggle,output reg [10:0] face_word_count,
 output reg [7:0] face_count,
 output reg [31:0] face_batch_id,face_source_id,face_revision
);
 localparam integer DIV=(CLK_HZ+BAUD/2)/BAUD;
 localparam integer BIT_W=DIV>1?$clog2(DIV):1;
 localparam integer TIMEOUT_W=$clog2(CLK_HZ/20+1);
 function automatic [15:0] crc_byte(input [15:0] c,input [7:0] b);
  integer k;reg [15:0] q;begin q=c^{b,8'b0};for(k=0;k<8;k=k+1)q=q[15]?(q<<1)^16'h1021:q<<1;crc_byte=q;end
 endfunction
 (* async_reg="true" *) reg rx_meta,rx_sync;
 reg [2:0] rx_state;reg [BIT_W-1:0] rx_count;reg [2:0] rx_bit;
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

 reg [3:0] ps;reg [7:0] ptype,pseq,crc_lo;
 reg [15:0] plen,pindex,pcrc;
 // Control payloads (9 bytes) and face headers (16 bytes) are mutually
 // exclusive. Freeze this shared packet buffer for frames that began busy;
 // they are still consumed/CRC checked but cannot overwrite an active packet.
 reg [127:0] packet_fields;reg [31:0] pword;
 reg receiving_free,face_allowed;
 reg packet_ready;reg [7:0] packet_seq,packet_type;
 reg [15:0] packet_length,packet_crc;wire [71:0] packet_data=packet_fields[71:0];
 wire [127:0] packet_header=packet_fields;reg packet_writable;
 reg [TIMEOUT_W-1:0] timeout_count;
 always @(posedge clk)begin
  if(!rst_n)begin
   ps<=0;ptype<=0;pseq<=0;plen<=0;pindex<=0;pcrc<=16'hffff;
   crc_lo<=0;packet_ready<=0;packet_seq<=0;timeout_count<=0;
   packet_fields<=0;pword<=0;receiving_free<=0;face_allowed<=0;packet_type<=0;
   packet_length<=0;packet_crc<=0;packet_writable<=0;
   face_wr_en<=0;face_wr_addr<=0;face_wr_data<=0;
  end else begin
   packet_ready<=0;face_wr_en<=0;
   if(ps!=0)begin if(timeout_count>=CLK_HZ/20)begin ps<=0;timeout_count<=0;end else timeout_count<=timeout_count+1;end
   if(rx_strobe)begin
    timeout_count<=0;
    case(ps)
     0:if(rx_byte==8'h55)ps<=1;
     1:if(rx_byte==8'haa)begin ps<=2;pcrc<=16'hffff;receiving_free<=!busy;end else if(rx_byte!=8'h55)ps<=0;
     2:begin ptype<=rx_byte;pcrc<=crc_byte(pcrc,rx_byte);ps<=3;end
     3:begin pseq<=rx_byte;pcrc<=crc_byte(pcrc,rx_byte);ps<=4;end
     4:begin plen[7:0]<=rx_byte;pcrc<=crc_byte(pcrc,rx_byte);ps<=5;end
     5:begin
      plen[15:8]<=rx_byte;pcrc<=crc_byte(pcrc,rx_byte);pindex<=0;pword<=0;
      if(receiving_free)packet_fields<=0;
      face_allowed<=receiving_free&&face_load_ready;
      if((ptype==1&&{rx_byte,plen[7:0]}==9)||
         (ptype==2&&{rx_byte,plen[7:0]}>=16&&{rx_byte,plen[7:0]}<=4112&&plen[1:0]==0))ps<=6;
      else ps<=0;
     end
     6:begin
      pcrc<=crc_byte(pcrc,rx_byte);
      if(ptype==1||pindex<16)begin
       if(receiving_free)packet_fields[pindex[3:0]*8+:8]<=rx_byte;
      end
      else begin
       pword[pindex[1:0]*8+:8]<=rx_byte;
       if(pindex[1:0]==3&&face_allowed)begin
        face_wr_en<=1;face_wr_addr<=(pindex-16)>>2;face_wr_data<={rx_byte,pword[23:0]};
       end
      end
      if(pindex==plen-1)ps<=7;else pindex<=pindex+1'b1;
     end
     7:begin crc_lo<=rx_byte;ps<=8;end
     8:begin
      ps<=0;
      if({rx_byte,crc_lo}==pcrc&&receiving_free)begin
       packet_ready<=1;packet_seq<=pseq;packet_type<=ptype;packet_length<=plen;
       packet_crc<=pcrc;packet_writable<=face_allowed;
      end
     end
     default:ps<=0;
    endcase
   end
  end
 end
 reg [9:0] tx_shift;reg [BIT_W-1:0] tx_count;reg [3:0] tx_bits;wire byte_busy=tx_bits!=0;
 reg byte_start;reg [7:0] byte_data;assign tx_o=tx_shift[0];
 always @(posedge clk)begin
  if(!rst_n)begin tx_shift<=10'h3ff;tx_count<=0;tx_bits<=0;end
  else if(byte_start&&!byte_busy)begin tx_shift<={1'b1,byte_data,1'b0};tx_bits<=10;tx_count<=DIV-1;end
  else if(byte_busy)begin if(tx_count!=0)tx_count<=tx_count-1;else begin tx_shift<={1'b1,tx_shift[9:1]};tx_bits<=tx_bits-1'b1;tx_count<=DIV-1;end end
 end

 reg tx_active;reg [6:0] tx_index;reg [15:0] tx_crc;
 reg [7:0] active_seq,active_id,active_result,active_type;reg [767:0] ack_status;
 reg [7:0] tx_value;reg tx_launched,last_valid,ack_pending,face_pending;
 reg [7:0] last_seq,last_result;reg [71:0] last_data;
 reg last_face_valid;reg [7:0] last_face_seq,last_face_result;
 reg [31:0] last_face_batch;reg [15:0] last_face_crc,pending_face_crc;
 wire face_header_legal=packet_header[7:0]==12&&packet_header[15:8]<=4&&
  packet_header[31:16]<=1024&&packet_length==16+({1'b0,packet_header[31:16]}<<2);
 wire face_context_legal=status_data[23:16]==3&&status_data[37]&&packet_header[127:96]==status_data[255:224];
 wire face_retry=last_face_valid&&last_face_seq==packet_seq&&last_face_batch==packet_header[63:32]&&last_face_crc==packet_crc;
 assign busy=tx_active||cmd_valid||ack_pending||face_pending;
 always @*begin
  case(tx_index)
   0:tx_value=8'h55;1:tx_value=8'haa;2:tx_value=active_type;3:tx_value=active_seq;
   4:tx_value=8'd98;5:tx_value=0;6:tx_value=active_id;7:tx_value=active_result;
   104:tx_value=tx_crc[7:0];105:tx_value=tx_crc[15:8];
   default:tx_value=tx_index>=8&&tx_index<104?ack_status[(tx_index-8)*8+:8]:0;
  endcase
 end
 always @(posedge clk)begin
  if(!rst_n)begin
   cmd_valid<=0;cmd_id<=0;cmd_arg0<=0;cmd_arg1<=0;cmd_arg2<=0;cmd_arg3<=0;heartbeat<=0;
   tx_active<=0;tx_index<=0;tx_crc<=16'hffff;active_seq<=0;active_id<=0;active_result<=0;active_type<=8'h80;ack_status<=0;
   byte_start<=0;byte_data<=0;tx_launched<=0;last_valid<=0;last_seq<=0;last_data<=0;last_result<=0;ack_pending<=0;
   face_pending<=0;face_submit_toggle<=0;face_word_count<=0;face_count<=0;face_batch_id<=0;face_source_id<=0;face_revision<=0;
   last_face_valid<=0;last_face_seq<=0;last_face_result<=0;last_face_batch<=0;last_face_crc<=0;pending_face_crc<=0;
  end else begin
   byte_start<=0;heartbeat<=0;
   if(packet_ready&&!busy)begin
    active_seq<=packet_seq;active_type<=packet_type==2?8'h81:8'h80;
    if(packet_type==2)begin
     active_id<=8'h40;
     if(face_retry)begin active_result<=last_face_result;ack_pending<=1;heartbeat<=1;end
     else if(!face_header_legal)begin active_result<=1;ack_pending<=1;end
     else if(!face_context_legal)begin active_result<=4;ack_pending<=1;end
     else if(!packet_writable||!face_load_ready)begin active_result<=3;ack_pending<=1;end
     else begin
      face_word_count<=packet_header[26:16];face_count<=packet_header[15:8];
      face_batch_id<=packet_header[63:32];face_source_id<=packet_header[95:64];face_revision<=packet_header[127:96];
      face_submit_toggle<=!face_submit_toggle;face_pending<=1;pending_face_crc<=packet_crc;heartbeat<=1;
     end
    end else begin
     active_id<=packet_data[7:0];
     if(packet_data[7:0]==8'hf1)heartbeat<=1;
     if(last_valid&&last_seq==packet_seq&&last_data==packet_data)begin
      active_result<=last_result;ack_pending<=1;
     end else begin
      last_seq<=packet_seq;last_data<=packet_data;last_valid<=0;
      if(packet_data[7:0]==8'hf1)begin active_result<=0;last_result<=0;last_valid<=1;ack_pending<=1;end
      else begin cmd_id<=packet_data[7:0];cmd_arg0<=packet_data[23:8];cmd_arg1<=packet_data[39:24];cmd_arg2<=packet_data[55:40];cmd_arg3<=packet_data[71:56];cmd_valid<=1;end
     end
    end
   end
   if(face_pending&&face_submit_ack==face_submit_toggle)begin
    face_pending<=0;active_result<=face_result;ack_pending<=1;heartbeat<=1;
    last_face_valid<=1;last_face_seq<=active_seq;last_face_result<=face_result;
    last_face_batch<=face_batch_id;last_face_crc<=pending_face_crc;
   end
   if(cmd_valid&&cmd_accept)begin cmd_valid<=0;active_result<=cmd_result;last_result<=cmd_result;last_valid<=1;ack_pending<=1;end
   if(ack_pending)begin ack_pending<=0;ack_status<=status_data;tx_active<=1;tx_index<=0;tx_crc<=16'hffff;end
   if(tx_active&&tx_index<106&&!byte_busy&&!byte_start&&!tx_launched)begin
    byte_data<=tx_value;byte_start<=1;tx_launched<=1;
    if(tx_index>=2&&tx_index<104)tx_crc<=crc_byte(tx_crc,tx_value);
   end
   if(tx_launched&&byte_busy)begin tx_launched<=0;tx_index<=tx_index+1'b1;end
   if(tx_active&&tx_index==106&&!byte_busy&&!byte_start&&!tx_launched)begin tx_active<=0;tx_index<=0;end
  end
 end
endmodule
