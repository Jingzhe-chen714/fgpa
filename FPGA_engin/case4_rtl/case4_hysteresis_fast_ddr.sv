`timescale 1ns/1ps
// Exact 8-connected hysteresis with 32-bit masked-prefix scans.
// Both weak and mutable strong maps are in DDR; only row buffers are on chip.
// Full-width 128-bit mailboxes accept consecutive read beats without pausing
// shared RREADY for unpacking. Four 32-bit scan words assemble one write beat.
// Each row is ceil(WIDTH/128)*16 bytes, leftmost pixel at beat bit 0.
// publish_base is an exclusively owned BACK slot, latched on load_start.
// ready/published follow all successful final BRESPs. Abort drains AXI work.
// rd_* are compatibility-only: display must read the published DDR map.
module case4_hysteresis_fast_ddr #(
 parameter integer WIDTH=960,HEIGHT=1080,ADDR_BITS=$clog2(WIDTH*HEIGHT),
 X_BITS=$clog2(WIDTH),Y_BITS=$clog2(HEIGHT),
 parameter [31:0] WEAK_BASE=32'h01000000,
 parameter integer AXI_TIMEOUT_CYCLES=9600000
)(
 input wire clk,rst_n,abort,load_start,load_valid,load_last,
 input wire [1:0] load_state,input wire [31:0] publish_base,
 input wire bypass_hysteresis,
 output reg busy,ready,fault,published,output reg [15:0] changed_sweeps,
 input wire rd_en,input wire [ADDR_BITS-1:0] rd_addr,output wire rd_edge,
 input wire axiclk,axirst,
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
 localparam integer PIXELS=WIDTH*HEIGHT,ROW_BEATS=(WIDTH+127)/128,
 ROW_BYTES=ROW_BEATS*16,PAD_BITS=ROW_BEATS*128,
 WORD_A=ROW_BEATS>1?$clog2(ROW_BEATS):1,CAP_A=$clog2(ROW_BEATS*2),
 STRONG_WORDS=(WIDTH+31)/32,STRIDE=STRONG_WORDS*32,
 WX=STRONG_WORDS>1?$clog2(STRONG_WORDS):1;
 localparam [4:0] P_IDLE=0,P_ARM=1,P_LOAD=2,P_FLUSH=3,P_SCAN_INIT=4,
 P_WAIT_ROW=5,P_WAIT_BANK=6,P_COPY=7,P_COPY_DRAIN=8,P_SEED=9,
 P_PREFIX_A=10,P_PREFIX_B=11,P_WRITE_LO=12,P_WRITE_HI=13,
 P_ROW_END=14,P_SWEEP_FLUSH=15,P_SWEEP_END=16,P_DONE=17;
 reg [4:0] ps;
 reg [127:0] capture_weak[0:ROW_BEATS*2-1],capture_strong[0:ROW_BEATS*2-1];
 reg [127:0] read_weak[0:ROW_BEATS-1],read_strong[0:ROW_BEATS-1];
 reg [1:0] capture_req,capture_update,capture_ack;
 reg [Y_BITS-1:0] capture_row0,capture_row1,read_row;
 reg read_req,read_ack,ui_fault;
 reg [31:0] publish_base_latched,pending_base;
 reg bypass_latched;
 wire ui_idle,ui_cancel;
 (* async_reg="true" *) reg [1:0] cap_ack_meta,cap_ack_sync;
 (* async_reg="true" *) reg [1:0] read_ack_sync,ui_fault_sync,ui_idle_sync,ui_cancel_sync;
 always @(posedge clk) begin
  if(!rst_n) begin
   cap_ack_meta<=0;cap_ack_sync<=0;read_ack_sync<=0;
   ui_fault_sync<=0;ui_idle_sync<=0;ui_cancel_sync<=2'b11;
  end else begin
   cap_ack_meta<=capture_ack;cap_ack_sync<=cap_ack_meta;
   read_ack_sync<={read_ack_sync[0],read_ack};
   ui_fault_sync<={ui_fault_sync[0],ui_fault};
   ui_idle_sync<={ui_idle_sync[0],ui_idle};
   ui_cancel_sync<={ui_cancel_sync[0],ui_cancel};
  end
 end
 wire arm_safe=ui_idle_sync[1]&&!ui_cancel_sync[1]&&!ui_fault_sync[1]&&
 capture_req==cap_ack_sync&&read_req==read_ack_sync[1];
 reg [ADDR_BITS-1:0] load_addr;
 reg [X_BITS-1:0] load_x;
 reg [Y_BITS-1:0] load_y,scan_y;
 reg [WX-1:0] word_x;
 reg capture_bank;
 reg [127:0] capture_shift,strong_shift;
 wire bank_free=capture_req[capture_bank]==cap_ack_sync[capture_bank];
 wire load_take=rst_n&&!abort&&!fault&&ps==P_LOAD&&load_valid&&bank_free;
 wire [127:0] capture_next={(load_state==2'b01),capture_shift[127:1]};
 wire [127:0] strong_next={load_state[1],strong_shift[127:1]};
 wire word_complete=(load_x%128)==127||load_x==WIDTH-1;
 wire [127:0] capture_word=(load_x==WIDTH-1&&WIDTH%128!=0)?
 capture_next>>(128-WIDTH%128):capture_next;
 wire [127:0] strong_load=(load_x==WIDTH-1&&WIDTH%128!=0)?
 strong_next>>(128-WIDTH%128):strong_next;
 function automatic [31:0] reverse_bits(input [31:0] value);
  integer j;begin for(j=0;j<32;j=j+1) reverse_bits[j]=value[31-j];end
 endfunction
 reg reverse_scan,sweep_changed,pair_changed;
 reg [STRIDE:0] history;
 reg [PAD_BITS-1:0] weak_row,strong_row;
 reg [WORD_A-1:0] copy_issue;
 reg copy_valid;
 reg [127:0] copy_weak_q,copy_strong_q;
 reg [31:0] old_word,seed_q,mask_q,prefix_a,prefix_mask_a,result_word;
 wire copy_read=rst_n&&!abort&&!fault&&ps==P_COPY;
 always @(posedge clk) if(copy_read) begin
  copy_weak_q<=read_weak[copy_issue];copy_strong_q<=read_strong[copy_issue];
 end
 wire processing=rst_n&&!abort&&!fault&&ps==P_WRITE_HI;
 wire write_low=1'b0;
 wire write_high=processing&&pack_complete;
 wire [31:0] physical_result=reverse_scan?reverse_bits(result_word):result_word;
 wire [WX-1:0] physical_word=reverse_scan?STRONG_WORDS-1-word_x:word_x;
 reg [127:0] result_pack;
 reg [127:0] merged_result;
 wire [1:0] pack_lane=physical_word%4;
 wire pack_complete=reverse_scan ? pack_lane==0 : (pack_lane==3||word_x==STRONG_WORDS-1);
 always @* begin
  merged_result=result_pack;
  case(pack_lane)
   0: merged_result[31:0]=physical_result;
   1: merged_result[63:32]=physical_result;
   2: merged_result[95:64]=physical_result;
   3: merged_result[127:96]=physical_result;
  endcase
 end
 wire [CAP_A-1:0] capture_write_addr=capture_bank*ROW_BEATS+
 (write_high?(physical_word>>2):(load_x>>7));
 always @(posedge clk)
  if(load_take&&word_complete) capture_weak[capture_write_addr]<=capture_word;
 always @(posedge clk) begin
  if(load_take&&word_complete) capture_strong[capture_write_addr]<=strong_load;
  else if(write_high) capture_strong[capture_write_addr]<=merged_result;
 end
 assign rd_edge=1'b0;
 // Padding to 32 pixels is always background; it cannot connect components.
 // History is in scan order, so identical expressions implement both directions.
 wire [31:0] oriented_strong=reverse_scan?
 reverse_bits(strong_row[STRIDE-1 -:32]):strong_row[31:0];
 wire [31:0] oriented_weak=reverse_scan?
 reverse_bits(weak_row[STRIDE-1 -:32]):weak_row[31:0];
 reg [31:0] vertical;
 integer b;
 always @* begin
  vertical=0;
  for(b=0;b<32;b=b+1) if(scan_y!=0) begin
   vertical[b]=history[STRIDE-1-b];
   if(word_x!=0||b!=0) vertical[b]=vertical[b]|history[STRIDE-b];
   if(b<STRIDE-1)
    if(word_x!=STRONG_WORDS-1||b!=31)
     vertical[b]=vertical[b]|history[STRIDE-2-b];
  end
 end
 wire [31:0] seeds=oriented_strong|(oriented_weak&vertical)|
 (oriented_weak&{31'b0,(word_x!=0&&history[0])});
 // At distance d, mask marks a chain of d consecutive eligible weak pixels.
 wire [31:0] reach1=seed_q|((seed_q<<1)&mask_q),mask1=mask_q&(mask_q<<1);
 wire [31:0] reach2=reach1|((reach1<<2)&mask1),mask2=mask1&(mask1<<2);
 wire [31:0] reach4=prefix_a|((prefix_a<<4)&prefix_mask_a),mask4=prefix_mask_a&(prefix_mask_a<<4);
 wire [31:0] reach8=reach4|((reach4<<8)&mask4),mask8=mask4&(mask4<<8);
 wire [31:0] reach16=reach8|((reach8<<16)&mask8);
 always @(posedge clk) if(processing)
  history<={history[STRIDE-32:0],reverse_bits(result_word)};
 always @(posedge clk) begin
  if(!rst_n) begin
   ps<=P_IDLE;busy<=0;ready<=0;published<=0;fault<=0;changed_sweeps<=0;
   capture_req<=0;capture_update<=0;read_req<=0;capture_row0<=0;capture_row1<=0;read_row<=0;
   publish_base_latched<=0;pending_base<=0;bypass_latched<=0;load_addr<=0;load_x<=0;load_y<=0;
   capture_bank<=0;capture_shift<=0;strong_shift<=0;word_x<=0;scan_y<=0;
   reverse_scan<=0;sweep_changed<=0;pair_changed<=0;copy_issue<=0;copy_valid<=0;
   old_word<=0;seed_q<=0;mask_q<=0;prefix_a<=0;prefix_mask_a<=0;result_word<=0;result_pack<=0;
  end else if(abort) begin
   ps<=P_IDLE;busy<=0;ready<=0;published<=0;fault<=0;copy_valid<=0;
  end else if(ui_fault_sync[1]&&ps!=P_IDLE&&ps!=P_ARM) begin
   ps<=P_IDLE;busy<=0;ready<=0;published<=0;fault<=1;copy_valid<=0;
  end else begin
   copy_valid<=copy_read;
   if(copy_valid) begin
    weak_row<=(weak_row>>128)|({{(PAD_BITS-128){1'b0}},copy_weak_q}<<(PAD_BITS-128));
    strong_row<=(strong_row>>128)|({{(PAD_BITS-128){1'b0}},copy_strong_q}<<(PAD_BITS-128));
   end
   case(ps)
    P_IDLE,P_DONE: if(load_start) begin
     ps<=arm_safe?P_LOAD:P_ARM;pending_base<=publish_base;bypass_latched<=bypass_hysteresis;
     if(arm_safe) publish_base_latched<=publish_base;
     busy<=1;ready<=0;published<=0;fault<=0;changed_sweeps<=0;
     load_addr<=0;load_x<=0;load_y<=0;capture_bank<=0;capture_shift<=0;strong_shift<=0;
    end
    P_ARM: begin
     if(load_valid) begin ps<=P_IDLE;busy<=0;fault<=1;end
     else if(arm_safe) begin publish_base_latched<=pending_base;ps<=P_LOAD;end
    end
    P_LOAD: if(load_valid) begin
     if(!bank_free||load_state==2'b10||load_last!=(load_addr==PIXELS-1)) begin
      ps<=P_IDLE;busy<=0;fault<=1;
     end else begin
      load_addr<=load_addr+1'b1;
      capture_shift<=word_complete?128'd0:capture_next;
      strong_shift<=word_complete?128'd0:strong_next;
      if(load_x==WIDTH-1) begin
       capture_req[capture_bank]<=!capture_req[capture_bank];capture_update[capture_bank]<=0;
       if(capture_bank) capture_row1<=load_y;else capture_row0<=load_y;
       capture_bank<=!capture_bank;load_x<=0;load_y<=load_y+1'b1;
      end else load_x<=load_x+1'b1;
      if(load_last) ps<=P_FLUSH;
     end
    end
    P_FLUSH: if(capture_req==cap_ack_sync&&ui_idle_sync[1]) begin
     if(bypass_latched) begin busy<=0;ready<=1;published<=1;ps<=P_DONE;end
     else begin reverse_scan<=0;pair_changed<=0;ps<=P_SCAN_INIT;end
    end
    P_SCAN_INIT: begin
     word_x<=0;scan_y<=0;sweep_changed<=0;capture_bank<=0;result_pack<=0;
     read_row<=reverse_scan?HEIGHT-1:0;read_req<=!read_req;ps<=P_WAIT_ROW;
    end
    P_WAIT_ROW: if(read_ack_sync[1]==read_req) ps<=P_WAIT_BANK;
    P_WAIT_BANK: if(bank_free) begin copy_issue<=0;copy_valid<=0;ps<=P_COPY;end
    P_COPY: begin
     if(copy_issue==ROW_BEATS-1) ps<=P_COPY_DRAIN;
     else copy_issue<=copy_issue+1'b1;
    end
    P_COPY_DRAIN: begin
     if(scan_y!=HEIGHT-1) begin
      read_row<=reverse_scan?HEIGHT-2-scan_y:scan_y+1'b1;read_req<=!read_req;
     end
     word_x<=0;ps<=P_SEED;
    end
    P_SEED: begin
     old_word<=oriented_strong;seed_q<=seeds;mask_q<=oriented_weak;
     weak_row<=reverse_scan?weak_row<<32:weak_row>>32;
     strong_row<=reverse_scan?strong_row<<32:strong_row>>32;ps<=P_PREFIX_A;
    end
    P_PREFIX_A: begin prefix_a<=reach2;prefix_mask_a<=mask2;ps<=P_PREFIX_B;end
    P_PREFIX_B: begin result_word<=reach16;ps<=P_WRITE_HI;end
    P_WRITE_LO: ps<=P_WRITE_HI;
    P_WRITE_HI: begin
     result_pack<=pack_complete?128'd0:merged_result;
     if(result_word!=old_word) sweep_changed<=1;
     if(word_x==STRONG_WORDS-1) ps<=P_ROW_END;
     else begin word_x<=word_x+1'b1;ps<=P_SEED;end
    end
    P_ROW_END: begin
     capture_update[capture_bank]<=1;capture_req[capture_bank]<=!capture_req[capture_bank];
     if(capture_bank) capture_row1<=reverse_scan?HEIGHT-1-scan_y:scan_y;
     else capture_row0<=reverse_scan?HEIGHT-1-scan_y:scan_y;
     capture_bank<=!capture_bank;
     if(scan_y==HEIGHT-1) ps<=P_SWEEP_FLUSH;
     else begin scan_y<=scan_y+1'b1;ps<=P_WAIT_ROW;end
    end
    // A direction switch is a DDR ordering barrier: the next sweep may
    // not read any row until every preceding row write has completed.
    P_SWEEP_FLUSH: if(capture_req==cap_ack_sync&&ui_idle_sync[1]) ps<=P_SWEEP_END;
    P_SWEEP_END: begin
     if(sweep_changed&&changed_sweeps!=16'hffff) changed_sweeps<=changed_sweeps+1'b1;
     if(!reverse_scan) begin
      pair_changed<=sweep_changed;reverse_scan<=1;ps<=P_SCAN_INIT;
     end else if(pair_changed||sweep_changed) begin
      pair_changed<=0;reverse_scan<=0;ps<=P_SCAN_INIT;
     end else begin busy<=0;ready<=1;published<=1;ps<=P_DONE;end
    end
    default: begin ps<=P_IDLE;busy<=0;ready<=0;published<=0;fault<=1;end
   endcase
  end
 end
 (* async_reg="true" *) reg [1:0] cap_req_meta,cap_req_sync,read_req_sync,cancel_sync;
 wire pixel_cancel=!rst_n||abort||fault;
 always @(posedge axiclk) begin
  if(axirst) begin cap_req_meta<=0;cap_req_sync<=0;read_req_sync<=0;cancel_sync<=2'b11;end
  else begin
   cap_req_meta<=capture_req;cap_req_sync<=cap_req_meta;
   read_req_sync<={read_req_sync[0],read_req};cancel_sync<={cancel_sync[0],pixel_cancel};
  end
 end
 assign ui_cancel=cancel_sync[1];
 localparam [3:0] U_IDLE=0,U_W_PACK=1,U_W_PACK_DRAIN=2,U_W_ADDR=3,
 U_W_SEND=4,U_W_RESP=5,U_R_ADDR=6,U_R_RECV=7,U_R_UNPACK=8,U_R_DRAIN=9,U_R_FINISH=10;
 reg [3:0] us;
 reg active_bank,active_tag,plane;
 reg [31:0] dma_addr,row_offset,active_base;
 reg [7:0] dma_beat;
 // dma_beat indexes the entire row mailbox; AXI bursts stop at a 4 KiB
 // boundary. A 1920-pixel row is 240 bytes, so row 17 already needs two
 // transactions. Keep the row request unacknowledged until both complete.
 reg [8:0] burst_beats;
 reg [7:0] burst_last;
 reg new_write_burst;
 wire [8:0] row_remaining=ROW_BEATS-{1'b0,dma_beat};
 wire [8:0] page_remaining=9'd256-{1'b0,dma_addr[11:4]};
 wire [8:0] next_burst=row_remaining<page_remaining?row_remaining:page_remaining;
 reg [127:0] cap_weak_q,cap_strong_q;
 reg [127:0] write_word;
 reg [31:0] timeout_count;
 wire cap_read=us==U_W_PACK;
 wire [CAP_A-1:0] cap_read_addr=active_bank*ROW_BEATS+dma_beat;
 always @(posedge axiclk) if(cap_read) begin
  cap_weak_q<=capture_weak[cap_read_addr];cap_strong_q<=capture_strong[cap_read_addr];
 end
 wire [WORD_A-1:0] read_write_addr=dma_beat;
 always @(posedge axiclk) if(us==U_R_RECV&&m_rvalid&&!plane) read_weak[read_write_addr]<=m_rdata;
 always @(posedge axiclk) if(us==U_R_RECV&&m_rvalid&&plane) read_strong[read_write_addr]<=m_rdata;
 assign ui_idle=us==U_IDLE;
 assign m_awaddr=dma_addr;assign m_awlen=next_burst-1'b1;assign m_awvalid=us==U_W_ADDR;
 assign m_wdata=write_word;assign m_wstrb=16'hffff;
 assign m_wlast=dma_beat==burst_last;assign m_wvalid=us==U_W_SEND;
 assign m_bready=us==U_W_RESP;
 assign m_araddr=dma_addr;assign m_arlen=next_burst-1'b1;assign m_arvalid=us==U_R_ADDR;
 assign m_rready=us==U_R_RECV||us==U_R_DRAIN;
 wire bus_progress=(m_awvalid&&m_awready)||(m_wvalid&&m_wready)||
 (m_bvalid&&m_bready)||(m_arvalid&&m_arready)||(m_rvalid&&m_rready);
 wire next_bank=(cap_req_sync[0]==capture_ack[0]);
 always @(posedge axiclk) begin
  if(axirst) begin
   us<=U_IDLE;capture_ack<=0;read_ack<=0;ui_fault<=0;
   active_bank<=0;active_tag<=0;plane<=0;dma_addr<=0;row_offset<=0;active_base<=0;dma_beat<=0;
   burst_beats<=0;burst_last<=0;new_write_burst<=0;
   write_word<=0;timeout_count<=0;
  end else begin
   if(us==U_IDLE||bus_progress) timeout_count<=0;
   else if(timeout_count<AXI_TIMEOUT_CYCLES) timeout_count<=timeout_count+1'b1;
   else ui_fault<=1;
   case(us)
    U_IDLE: begin
     if(ui_cancel) begin
      capture_ack<=cap_req_sync;read_ack<=read_req_sync[1];ui_fault<=0;
     end else if(cap_req_sync!=capture_ack) begin
      active_bank<=next_bank;active_tag<=cap_req_sync[next_bank];
      plane<=capture_update[next_bank];active_base<=publish_base_latched;
      row_offset<=(next_bank?capture_row1:capture_row0)*ROW_BYTES;
      dma_addr<=(capture_update[next_bank]?publish_base_latched:WEAK_BASE)+
       (next_bank?capture_row1:capture_row0)*ROW_BYTES;
      dma_beat<=0;new_write_burst<=1;us<=U_W_PACK;
     end else if(read_req_sync[1]!=read_ack) begin
      active_tag<=read_req_sync[1];active_base<=publish_base_latched;
      row_offset<=read_row*ROW_BYTES;dma_addr<=WEAK_BASE+read_row*ROW_BYTES;
      plane<=0;dma_beat<=0;us<=U_R_ADDR;
     end
    end
    U_W_PACK: us<=U_W_PACK_DRAIN;
    U_W_PACK_DRAIN: begin
     write_word<=plane?cap_strong_q:cap_weak_q;us<=new_write_burst?U_W_ADDR:U_W_SEND;
    end
    U_W_ADDR: if(m_awready) begin
     burst_beats<=next_burst;burst_last<=dma_beat+next_burst-1'b1;
     new_write_burst<=0;us<=U_W_SEND;
    end
    U_W_SEND: if(m_wready) begin
     if(dma_beat==burst_last) us<=U_W_RESP;
     else begin dma_beat<=dma_beat+1'b1;us<=U_W_PACK;end
    end
    U_W_RESP: if(m_bvalid) begin
     if(m_bresp!=0) ui_fault<=1;
     if(ui_cancel||ui_fault||m_bresp!=0) begin capture_ack[active_bank]<=active_tag;us<=U_IDLE;end
     else if(dma_beat<ROW_BEATS-1) begin
      dma_addr<=dma_addr+({23'd0,burst_beats}<<4);dma_beat<=dma_beat+1'b1;
      new_write_burst<=1;us<=U_W_PACK;
     end else if(!plane) begin
      plane<=1;dma_addr<=active_base+row_offset;dma_beat<=0;new_write_burst<=1;us<=U_W_PACK;
     end else begin capture_ack[active_bank]<=active_tag;us<=U_IDLE;end
    end
    U_R_ADDR: if(m_arready) begin
     burst_beats<=next_burst;burst_last<=dma_beat+next_burst-1'b1;us<=U_R_RECV;
    end
    U_R_RECV: if(m_rvalid) begin
     if(m_rresp!=0||m_rlast!=(dma_beat==burst_last)) ui_fault<=1;
     if(m_rlast) begin
      if(ui_cancel||ui_fault||m_rresp!=0||dma_beat!=burst_last||dma_beat==ROW_BEATS-1) us<=U_R_FINISH;
      else begin
       dma_addr<=dma_addr+({23'd0,burst_beats}<<4);dma_beat<=dma_beat+1'b1;us<=U_R_ADDR;
      end
     end else if(dma_beat==burst_last) us<=U_R_DRAIN;
     else dma_beat<=dma_beat+1'b1;
    end
    U_R_DRAIN: if(m_rvalid&&m_rlast) us<=U_R_FINISH;
    U_R_FINISH: begin
     if(ui_cancel||ui_fault)begin read_ack<=active_tag;us<=U_IDLE;end
     else if(!plane) begin plane<=1;dma_addr<=active_base+row_offset;dma_beat<=0;us<=U_R_ADDR;end
     else begin read_ack<=active_tag;us<=U_IDLE;end
    end
    default: begin us<=U_IDLE;ui_fault<=1;end
   endcase
  end
 end
endmodule
