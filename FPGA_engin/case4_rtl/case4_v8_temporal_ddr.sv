`timescale 1ns/1ps
// V8 completed-frame temporal processing. This module runs wholly on AXI clk.
// The caller pins rgb_base and raw_base from start through done, and must not
// publish output_base until done && !fault && !duplicate. Output is byte/pixel:
// bit0 raw, bit1 stabilized, bit2 previous raw, bit3 older raw, bit4 moving edge,
// bits5/6/7 interval-captured edges (oldest first). Metadata rows are padded to
// 128 pixels. Private DDR state is ping-ponged and committed only after every
// output and state BRESP. Reset never assumes uninitialized DDR contains zero.
// Abort drains any offered AXI transaction; a permanently hung bus needs reset.
module case4_v8_temporal_ddr #(
 parameter integer WIDTH=960, HEIGHT=1080, RGB_WIDTH=1920,
 parameter [31:0] STATE_BASE0=32'h01c00000,STATE_BASE1=32'h01e00000,
 parameter integer AXI_TIMEOUT_CYCLES=9600000
)(
 input wire clk,rst,start,abort,clear_history,
 input wire [31:0] source_id,raw_base,rgb_base,output_base,
 input wire [7:0] source_mean,motion_threshold,
 input wire temporal_enable,strobe_toggle,
 input wire [2:0] strobe_interval,
 output reg busy,done,fault,duplicate,
 output reg [1:0] strobe_count,history_depth,
 output reg strobe_active,
 output reg [31:0] completed_source_id,
 output wire [31:0] m_awaddr,output wire [7:0] m_awlen,
 output wire m_awvalid,input wire m_awready,
 output wire [127:0] m_wdata,output wire [15:0] m_wstrb,
 output wire m_wlast,m_wvalid,input wire m_wready,
 input wire [1:0] m_bresp,input wire m_bvalid,output wire m_bready,
 output wire [31:0] m_araddr,output wire [7:0] m_arlen,
 output wire m_arvalid,input wire m_arready,
 input wire [127:0] m_rdata,input wire [1:0] m_rresp,
 input wire m_rlast,m_rvalid,output wire m_rready
);
 localparam integer MAP_BEATS=(WIDTH+127)/128,MAP_BYTES=MAP_BEATS*16,
  PAD_WIDTH=MAP_BEATS*128,META_BEATS=PAD_WIDTH/16,META_BYTES=PAD_WIDTH,
  STATE_BEATS=WIDTH/8,STATE_BYTES=WIDTH*2,
  STATE_A=STATE_BEATS>1?$clog2(STATE_BEATS):1,
  META_A=META_BEATS>1?$clog2(META_BEATS):1;
 localparam [4:0] IDLE=0,ROW_INIT=1,R_PREP=2,R_ADDR=3,R_DATA=4,R_FINISH=5,
  PIX_FETCH=6,PIX_LATCH=7,PIX_RUN=8,META_PAD=9,W_PREP=10,W_FETCH=11,
  W_LATCH=12,W_ADDR=13,W_DATA=14,W_RESP=15,ROW_DONE=16,COMPLETE=17,FAILED=18;
 reg [4:0] state;
 reg [127:0] rgb_row[0:STATE_BEATS-1],old_row[0:STATE_BEATS-1];
 reg [127:0] meta_row[0:META_BEATS-1];
 reg [PAD_WIDTH-1:0] up_bits,cur_bits,dn_bits;
 reg up_left,cur_left,dn_left;
 reg [127:0] rgb_q,state_q,rgb_shift,old_shift,state_pack,meta_pack;
 reg [127:0] meta_q,write_word;
 reg [15:0] row,x;
 reg [8:0] pixel_word,transfer_offset,transfer_index,transfer_total;
 reg [8:0] burst_beats;
 reg [7:0] burst_index;
 reg [3:0] pixel_lane;
 reg [8:0] pad_index;
 reg [2:0] read_kind;
 reg write_kind;
 reg [31:0] transfer_base,dma_addr;
 reg [31:0] job_source,job_raw,job_rgb,job_output;
 reg [31:0] state_read_base,state_write_base;
 reg [7:0] job_mean,previous_mean,job_motion_threshold;
 reg job_temporal,job_history,history_valid,state_front;
 reg [1:0] job_depth;
 reg cancel_pending,job_error;
 reg [31:0] timeout_count;
 reg strobe_seen,job_strobe_toggle,job_strobe_reset,job_strobe_capture;
 reg [1:0] job_strobe_index,next_strobe_count;
 reg next_strobe_active;
 reg [4:0] strobe_wait,next_strobe_wait,job_strobe_gap;
 reg [2:0] interval_latched;
 wire bus_progress=(m_awvalid&&m_awready)||(m_wvalid&&m_wready)||
  (m_bvalid&&m_bready)||(m_arvalid&&m_arready)||(m_rvalid&&m_rready);
 wire stopping=abort||cancel_pending||job_error;
 wire [8:0] remaining=transfer_total-transfer_offset;
 wire [31:0] next_dma_addr=transfer_base+{19'd0,transfer_offset,4'b0};
 wire [8:0] page_beats=9'd256-{1'b0,next_dma_addr[11:4]};
 wire [8:0] next_burst=remaining<page_beats?remaining:page_beats;
 // Camera W0_FIFO_8 packs the first RGB565 pixel into AXI bits127:112.
 // Private state and edge metadata deliberately use coordinate0 at the LSB.
 wire [15:0] pixel=rgb_shift[127:112],old_pixel=old_shift[15:0];
 wire [7:0] red={pixel[15:11],pixel[15:13]},green={pixel[10:5],pixel[10:9]},blue={pixel[4:0],pixel[4:2]};
 // Same rounded BT.601 integer weights as the image-processing gray stream.
 wire [15:0] gray_sum=red*16'd77+green*16'd150+blue*16'd29+16'd128;
 wire [7:0] gray=gray_sum[15:8];
 wire signed [9:0] raw_difference=$signed({2'b00,gray})-$signed({2'b00,old_pixel[7:0]});
 wire signed [9:0] exposure_difference=$signed({2'b00,job_mean})-$signed({2'b00,previous_mean});
 wire signed [10:0] corrected_difference=$signed({raw_difference[9],raw_difference})-
  $signed({exposure_difference[9],exposure_difference});
 wire [10:0] absolute_difference=corrected_difference[10]?-corrected_difference:corrected_difference;
 wire motion=job_history&&absolute_difference>={3'b000,job_motion_threshold};
 wire left_ok=x!=0,right_ok=x!=WIDTH-1;
 wire [3:0] neighbors={3'b000,(left_ok&&up_left)}+{3'b000,up_bits[0]}+
  {3'b000,(right_ok&&up_bits[1])}+{3'b000,(left_ok&&cur_left)}+
  {3'b000,(right_ok&&cur_bits[1])}+{3'b000,(left_ok&&dn_left)}+
  {3'b000,dn_bits[0]}+{3'b000,(right_ok&&dn_bits[1])};
 wire supported=cur_bits[0]&&neighbors!=0;
 wire previous_raw=job_history&&old_pixel[8],older_raw=job_history&&old_pixel[9];
 wire previous_stable=job_history&&old_pixel[10];
 // A current moving contour is never required to occur at one coordinate for
// three frames. Static contours use 2-of-3 evidence; one isolated dropout is
// held for one observation only. Spatially isolated input pixels are removed.
 wire stabilized=(!job_temporal||!job_history)?supported:
  (motion?supported:((supported&&(previous_raw||older_raw))||
                    (!supported&&previous_stable&&previous_raw&&older_raw)));
 wire moving_edge=supported&&motion;
 reg [2:0] captured;
 always @* begin
  captured=(job_history&&!job_strobe_reset)?old_pixel[13:11]:3'b000;
  if(job_strobe_capture) captured[job_strobe_index]=stabilized;
 end
 wire [7:0] metadata={captured,moving_edge,older_raw,previous_raw,stabilized,cur_bits[0]};
 wire [15:0] new_pixel={2'b00,captured,stabilized,previous_raw,supported,gray};
 wire [127:0] next_state_pack={new_pixel,state_pack[127:16]};
 wire [127:0] next_meta_pack={metadata,meta_pack[127:8]};
 wire row_complete=x==WIDTH-1;
 wire word_complete=pixel_lane[2:0]==7;
 wire meta_complete=pixel_lane==15;

 assign m_awaddr=dma_addr;assign m_awlen=burst_beats-1'b1;assign m_awvalid=state==W_ADDR;
 assign m_wdata=write_word;assign m_wstrb=16'hffff;
 assign m_wlast=burst_index==burst_beats-1'b1;assign m_wvalid=state==W_DATA;
 assign m_bready=state==W_RESP;
 assign m_araddr=dma_addr;assign m_arlen=burst_beats-1'b1;assign m_arvalid=state==R_ADDR;
 assign m_rready=state==R_DATA;

 // Explicit single write port and identically sized read/write addresses are
 // required for Efinity block-RAM inference. In particular, padding is muxed
 // BEFORE the metadata write port rather than described as a second writer.
 wire [STATE_A-1:0] state_read_address=transfer_index[STATE_A-1:0];
 wire [STATE_A-1:0] state_write_address=pixel_word[STATE_A-1:0];
 // The old state word is safely in old_shift before any of its eight pixels
 // is processed. Replace that consumed row word in place with the new state;
 // after the row is complete, this same RAM is the output DMA source.
 wire state_input_write=state==R_DATA&&m_rvalid&&transfer_index<transfer_total&&read_kind==4;
 wire state_result_write=state==PIX_RUN&&word_complete;
 wire [STATE_A-1:0] work_write_address=state_input_write?state_read_address:state_write_address;
 wire [127:0] work_write_data=state_input_write?m_rdata:next_state_pack;
 wire [STATE_A-1:0] work_read_address=state==PIX_FETCH?state_write_address:state_read_address;
 wire [META_A-1:0] meta_read_address=transfer_index[META_A-1:0];
 wire [META_A-1:0] meta_write_address=state==META_PAD?pad_index[META_A-1:0]:x[4+:META_A];
 wire meta_write_enable=(state==PIX_RUN&&meta_complete)||(state==META_PAD&&pad_index<META_BEATS);
 wire [127:0] meta_write_data=state==META_PAD?128'd0:next_meta_pack;
 // One synchronous read port per row RAM; no asynchronous array read or reset.
 always @(posedge clk) begin
  if(state==PIX_FETCH) rgb_q<=rgb_row[state_write_address];
  if(state==R_DATA&&m_rvalid&&transfer_index<transfer_total) begin
   if(read_kind==3) rgb_row[state_read_address]<=m_rdata;
  end
 end
 always @(posedge clk) begin
  if(state==PIX_FETCH||state==W_FETCH) state_q<=old_row[work_read_address];
  if(state_input_write||state_result_write) old_row[work_write_address]<=work_write_data;
 end
 always @(posedge clk) begin
  if(state==W_FETCH) meta_q<=meta_row[meta_read_address];
  if(meta_write_enable) meta_row[meta_write_address]<=meta_write_data;
 end

 always @(posedge clk) begin
  if(rst) begin
   state<=IDLE;busy<=0;done<=0;fault<=0;duplicate<=0;
   history_valid<=0;state_front<=0;history_depth<=0;completed_source_id<=0;previous_mean<=0;
   strobe_seen<=0;strobe_count<=0;strobe_active<=0;strobe_wait<=0;interval_latched<=0;
   row<=0;x<=0;pixel_word<=0;pixel_lane<=0;pad_index<=0;
   transfer_offset<=0;transfer_index<=0;transfer_total<=0;burst_beats<=1;burst_index<=0;
   transfer_base<=0;dma_addr<=0;read_kind<=0;write_kind<=0;
   job_source<=0;job_raw<=0;job_rgb<=0;job_output<=0;state_read_base<=STATE_BASE0;state_write_base<=STATE_BASE1;
   job_mean<=0;job_motion_threshold<=16;job_temporal<=1;job_history<=0;job_depth<=0;
   cancel_pending<=0;job_error<=0;timeout_count<=0;
   job_strobe_toggle<=0;job_strobe_reset<=0;job_strobe_capture<=0;job_strobe_index<=0;
   next_strobe_count<=0;next_strobe_active<=0;next_strobe_wait<=0;job_strobe_gap<=1;
   up_bits<=0;cur_bits<=0;dn_bits<=0;up_left<=0;cur_left<=0;dn_left<=0;
   rgb_shift<=0;old_shift<=0;state_pack<=0;meta_pack<=0;write_word<=0;
  end else begin
   done<=0;
   if(busy&&abort) cancel_pending<=1;
   if(!busy||bus_progress||state==PIX_RUN||state==ROW_INIT) timeout_count<=0;
   else if(timeout_count<AXI_TIMEOUT_CYCLES) timeout_count<=timeout_count+1'b1;
   else begin job_error<=1;fault<=1;end
   case(state)
    IDLE: if(start) begin
     fault<=0;duplicate<=0;cancel_pending<=0;job_error<=0;timeout_count<=0;
     if(history_valid&&!clear_history&&source_id==completed_source_id) begin
      done<=1;duplicate<=1;
     end else begin
      busy<=1;state<=ROW_INIT;row<=0;job_source<=source_id;
      job_raw<=raw_base;job_rgb<=rgb_base;job_output<=output_base;
      job_mean<=source_mean;job_motion_threshold<=motion_threshold==0?8'd16:motion_threshold;
      job_temporal<=temporal_enable;job_history<=history_valid&&!clear_history;
      job_depth<=clear_history?0:history_depth;
      state_read_base<=state_front?STATE_BASE1:STATE_BASE0;
      state_write_base<=state_front?STATE_BASE0:STATE_BASE1;
      job_strobe_toggle<=strobe_toggle;job_strobe_reset<=clear_history||!history_valid||(strobe_toggle!=strobe_seen);
      job_strobe_capture<=0;job_strobe_index<=0;
      next_strobe_count<=clear_history?0:strobe_count;
      next_strobe_active<=clear_history?0:strobe_active;
      next_strobe_wait<=clear_history?0:strobe_wait;
      job_strobe_gap<=5'd1<<(strobe_interval>4?3'd4:strobe_interval);
      if(strobe_toggle!=strobe_seen) begin
       job_strobe_capture<=1;job_strobe_index<=0;next_strobe_count<=1;next_strobe_active<=1;
       next_strobe_wait<=(5'd1<<(strobe_interval>4?3'd4:strobe_interval))-1'b1;
       interval_latched<=strobe_interval>4?3'd4:strobe_interval;
      end else if(strobe_active&&!clear_history&&history_valid) begin
       if(strobe_wait==0) begin
        job_strobe_capture<=1;job_strobe_index<=strobe_count;
        next_strobe_count<=strobe_count+1'b1;next_strobe_active<=strobe_count!=2;
        next_strobe_wait<=(5'd1<<interval_latched)-1'b1;
       end else next_strobe_wait<=strobe_wait-1'b1;
      end
      if(clear_history) begin history_valid<=0;history_depth<=0;end
     end
    end
    ROW_INIT: if(stopping) state<=FAILED;else begin
     up_bits<=0;cur_bits<=0;dn_bits<=0;up_left<=0;cur_left<=0;dn_left<=0;
     x<=0;pixel_word<=0;pixel_lane<=0;state_pack<=0;meta_pack<=0;
     read_kind<=row==0?1:0;transfer_offset<=0;transfer_total<=MAP_BEATS;
     transfer_base<=job_raw+(row==0?0:(row-1'b1)*MAP_BYTES);state<=R_PREP;
    end
    R_PREP: if(stopping) state<=FAILED;else begin
     dma_addr<=next_dma_addr;burst_beats<=next_burst;burst_index<=0;
     transfer_index<=transfer_offset;state<=R_ADDR;
    end
    R_ADDR: if(m_arready) state<=R_DATA;
    R_DATA: if(m_rvalid) begin
     if(m_rresp!=0||m_rlast!=(burst_index==burst_beats-1'b1)) job_error<=1;
     if(transfer_index<transfer_total) begin
      if(read_kind==0) up_bits<=(up_bits>>128)|({{(PAD_WIDTH-128){1'b0}},m_rdata}<<(PAD_WIDTH-128));
      if(read_kind==1) cur_bits<=(cur_bits>>128)|({{(PAD_WIDTH-128){1'b0}},m_rdata}<<(PAD_WIDTH-128));
      if(read_kind==2) dn_bits<=(dn_bits>>128)|({{(PAD_WIDTH-128){1'b0}},m_rdata}<<(PAD_WIDTH-128));
     end
     if(m_rlast) begin transfer_offset<=transfer_offset+burst_beats;state<=R_FINISH;end
     else begin
      if(burst_index<255) burst_index<=burst_index+1'b1;
      if(transfer_index<transfer_total) transfer_index<=transfer_index+1'b1;
     end
    end
    R_FINISH: if(stopping) state<=FAILED;
     else if(transfer_offset<transfer_total) state<=R_PREP;
     else begin
      transfer_offset<=0;
      case(read_kind)
       0: begin read_kind<=1;transfer_base<=job_raw+row*MAP_BYTES;state<=R_PREP;end
       1: if(row<HEIGHT-1) begin read_kind<=2;transfer_base<=job_raw+(row+1'b1)*MAP_BYTES;state<=R_PREP;end
          else begin read_kind<=3;transfer_base<=job_rgb+(row*RGB_WIDTH+RGB_WIDTH-WIDTH)*2;transfer_total<=STATE_BEATS;state<=R_PREP;end
       2: begin read_kind<=3;transfer_base<=job_rgb+(row*RGB_WIDTH+RGB_WIDTH-WIDTH)*2;transfer_total<=STATE_BEATS;state<=R_PREP;end
       3: if(job_history) begin read_kind<=4;transfer_base<=state_read_base+row*STATE_BYTES;transfer_total<=STATE_BEATS;state<=R_PREP;end
          else state<=PIX_FETCH;
       default: state<=PIX_FETCH;
      endcase
     end
    PIX_FETCH: if(stopping) state<=FAILED;else state<=PIX_LATCH;
    PIX_LATCH: begin rgb_shift<=rgb_q;old_shift<=job_history?state_q:128'd0;state<=PIX_RUN;end
    PIX_RUN: if(stopping) state<=FAILED;else begin
     up_left<=up_bits[0];cur_left<=cur_bits[0];dn_left<=dn_bits[0];
     up_bits<=up_bits>>1;cur_bits<=cur_bits>>1;dn_bits<=dn_bits>>1;
     rgb_shift<=rgb_shift<<16;old_shift<=old_shift>>16;
     state_pack<=word_complete?128'd0:next_state_pack;
     meta_pack<=meta_complete?128'd0:next_meta_pack;
     pixel_lane<=pixel_lane+1'b1;x<=x+1'b1;
     if(row_complete) begin pad_index<=WIDTH/16;state<=META_PAD;end
     else if(word_complete) begin pixel_word<=pixel_word+1'b1;state<=PIX_FETCH;end
    end
    META_PAD: if(stopping) state<=FAILED;else if(pad_index<META_BEATS) pad_index<=pad_index+1'b1;
     else begin
      write_kind<=0;transfer_base<=state_write_base+row*STATE_BYTES;
      transfer_offset<=0;transfer_total<=STATE_BEATS;state<=W_PREP;
     end
    W_PREP: if(stopping) state<=FAILED;else begin
     dma_addr<=next_dma_addr;burst_beats<=next_burst;burst_index<=0;
     transfer_index<=transfer_offset;state<=W_FETCH;
    end
    W_FETCH: state<=W_LATCH;
    W_LATCH: begin write_word<=write_kind?meta_q:state_q;state<=burst_index==0?W_ADDR:W_DATA;end
    W_ADDR: if(m_awready) state<=W_DATA;
    W_DATA: if(m_wready) begin
     if(m_wlast) state<=W_RESP;
     else begin burst_index<=burst_index+1'b1;transfer_index<=transfer_index+1'b1;state<=W_FETCH;end
    end
    W_RESP: if(m_bvalid) begin
     if(m_bresp!=0) begin job_error<=1;state<=FAILED;end
     else if(stopping) state<=FAILED;
     else if(transfer_offset+burst_beats<transfer_total) begin transfer_offset<=transfer_offset+burst_beats;state<=W_PREP;end
     else if(!write_kind) begin
      write_kind<=1;transfer_base<=job_output+row*META_BYTES;transfer_offset<=0;transfer_total<=META_BEATS;state<=W_PREP;
     end else state<=ROW_DONE;
    end
    ROW_DONE: if(stopping) state<=FAILED;
     else if(row==HEIGHT-1) state<=COMPLETE;
     else begin row<=row+1'b1;state<=ROW_INIT;end
    COMPLETE: if(stopping) state<=FAILED;else begin
     busy<=0;done<=1;fault<=0;duplicate<=0;state<=IDLE;
     history_valid<=1;state_front<=!state_front;completed_source_id<=job_source;previous_mean<=job_mean;
     history_depth<=job_depth==3?2'd3:job_depth+1'b1;
     strobe_seen<=job_strobe_toggle;strobe_count<=next_strobe_count;
     strobe_active<=next_strobe_active;strobe_wait<=next_strobe_wait;
    end
    FAILED: begin busy<=0;done<=1;fault<=1;duplicate<=0;state<=IDLE;end
    default: begin job_error<=1;state<=FAILED;end
   endcase
  end
 end
endmodule
