`timescale 1ns/1ps
// Exact native-resolution Canny hysteresis with a hybrid bitmap.
// The mutable strong/connected bitmap is 1 bit/pixel in on-chip true dual-port
// RAM. Immutable weak eligibility is in external DDR, one padded row per burst.
// No compression assumption, downsampling, connectivity limit or sweep cap.
//
// Pixel-side loading/read semantics match case4_hysteresis. load_start follows
// cancellation only after outstanding AXI work has drained; if the next video
// frame arrives before this happens, fault is raised instead of dropping pixels.
// Capture has two row mailboxes. They remain immutable until their write B
// response. Read DMA has one row mailbox, copied locally before reuse/prefetch.
// Toggle synchronizers transfer ownership; multibit row metadata is held until
// acknowledgement. AXI abort drains accepted/pending bursts to their responses.
module case4_hysteresis_ddr #(
    parameter integer WIDTH=960, HEIGHT=1080,
    parameter integer ADDR_BITS=$clog2(WIDTH*HEIGHT),
    parameter integer X_BITS=$clog2(WIDTH), Y_BITS=$clog2(HEIGHT),
    parameter [31:0] WEAK_BASE=32'h01000000,
    parameter integer AXI_TIMEOUT_CYCLES=9600000
)(
    input wire clk,rst_n,abort,
    input wire load_start,load_valid,load_last,input wire [1:0] load_state,
    output reg busy,ready,fault,output reg [15:0] changed_sweeps,
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
    localparam integer PIXELS=WIDTH*HEIGHT;
    localparam integer ROW_BEATS=(WIDTH+127)/128,ROW_BYTES=ROW_BEATS*16;
    localparam integer ROW_WORDS=ROW_BEATS*8,PAD_BITS=ROW_BEATS*128;
    localparam integer VALID_WORDS=(WIDTH+15)/16;
    localparam integer WORD_A=$clog2(ROW_WORDS),CAP_A=$clog2(ROW_WORDS*2);
    localparam [3:0] P_IDLE=0,P_ARM=1,P_LOAD=2,P_FLUSH=3,P_SCAN_INIT=4,
        P_WAIT_ROW=5,P_COPY=6,P_COPY_DRAIN=7,P_SCAN=8,P_DRAIN=9,
        P_ROW_END=10,P_SWEEP_END=11,P_DONE=12;
    reg [3:0] ps;
    reg strong_map[0:PIXELS-1];
    reg [15:0] capture_mem[0:ROW_WORDS*2-1];
    reg [15:0] read_mem[0:ROW_WORDS-1];
    reg [1:0] capture_req;
    reg [Y_BITS-1:0] capture_row0,capture_row1;
    reg read_req;
    reg [Y_BITS-1:0] read_row;
    reg [1:0] capture_ack;
    reg read_ack,ui_fault;
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
    wire arm_safe=ui_idle_sync[1] && !ui_cancel_sync[1] && !ui_fault_sync[1] &&
        capture_req==cap_ack_sync && read_req==read_ack_sync[1];
    reg [ADDR_BITS-1:0] load_addr,issue_addr,center_addr;
    reg [X_BITS-1:0] load_x,issue_x,center_x;
    reg [Y_BITS-1:0] load_y,scan_y,center_y;
    reg capture_bank;
    reg [15:0] capture_shift;
    wire bank_free=capture_req[capture_bank]==cap_ack_sync[capture_bank];
    wire load_take=rst_n && !abort && !fault && ps==P_LOAD && load_valid && bank_free;
    wire [15:0] capture_next={(load_state==2'b01),capture_shift[15:1]};
    wire word_complete=(load_x%16)==15 || load_x==WIDTH-1;
    wire [15:0] capture_word=(load_x==WIDTH-1 && WIDTH%16!=0) ?
        capture_next>>(16-WIDTH%16) : capture_next;
    wire [CAP_A-1:0] capture_write_addr=capture_bank*ROW_WORDS+(load_x>>4);
    always @(posedge clk) if(load_take && word_complete)
        capture_mem[capture_write_addr]<=capture_word;

    reg reverse_scan,sweep_changed,pair_changed,center_valid;
    reg center_strong,center_weak,display_q,display_valid;
    reg [WIDTH:0] history;
    reg [PAD_BITS-1:0] weak_row;
    reg [WORD_A-1:0] copy_issue,copy_tag;
    reg copy_valid;
    reg [15:0] copy_q;
    wire copy_read=rst_n && !abort && !fault && ps==P_COPY;
    always @(posedge clk) if(copy_read) copy_q<=read_mem[copy_issue];
    wire issue_read=rst_n && !abort && !fault && ps==P_SCAN;
    wire processing=rst_n && !abort && !fault && center_valid && (ps==P_SCAN || ps==P_DRAIN);
    wire connected=(center_x!=0 && history[0]) ||
        (center_y!=0 && ((center_x!=0 && history[WIDTH]) || history[WIDTH-1] ||
                       (center_x!=WIDTH-1 && history[WIDTH-2])));
    wire promote=processing && !center_strong && center_weak && connected;
    wire final_edge=center_strong || (center_weak && connected);
    wire display_read=rst_n && !abort && ready && rd_en && rd_addr<PIXELS;
    wire [ADDR_BITS-1:0] port_a_addr=load_take ? load_addr : issue_addr;
    wire [ADDR_BITS-1:0] port_b_addr=promote ? center_addr : rd_addr;
    always @(posedge clk) if(load_take || issue_read) begin
        if(load_take) strong_map[port_a_addr]<=load_state[1];
        center_strong<=strong_map[port_a_addr];
    end
    always @(posedge clk) begin
        if(promote || display_read) begin
            if(promote) strong_map[port_b_addr]<=1'b1;
            display_q<=strong_map[port_b_addr];
        end
        display_valid<=display_read;
    end
    always @(posedge clk) if(processing) history<={history[WIDTH-1:0],final_edge};
    assign rd_edge=rst_n && !abort && ready && display_valid && display_q;

    always @(posedge clk) begin
        if(!rst_n) begin
            ps<=P_IDLE;busy<=0;ready<=0;fault<=0;changed_sweeps<=0;
            capture_req<=0;read_req<=0;capture_row0<=0;capture_row1<=0;read_row<=0;
            load_addr<=0;load_x<=0;load_y<=0;capture_bank<=0;capture_shift<=0;
            issue_addr<=0;issue_x<=0;scan_y<=0;center_addr<=0;center_x<=0;center_y<=0;
            center_valid<=0;center_weak<=0;reverse_scan<=0;sweep_changed<=0;pair_changed<=0;
            copy_issue<=0;copy_tag<=0;copy_valid<=0;
        end else if(abort) begin
            // Keep request toggles unchanged until UI acknowledges cancellation.
            ps<=P_IDLE;busy<=0;ready<=0;fault<=0;center_valid<=0;copy_valid<=0;
        end else if(ui_fault_sync[1] && ps!=P_IDLE && ps!=P_ARM) begin
            ps<=P_IDLE;busy<=0;ready<=0;fault<=1;center_valid<=0;copy_valid<=0;
        end else begin
            center_valid<=issue_read;
            copy_valid<=copy_read;
            if(copy_read) copy_tag<=copy_issue;
            if(copy_valid) weak_row<={copy_q,weak_row[PAD_BITS-1:16]};
            if(issue_read) begin
                center_addr<=issue_addr;center_x<=issue_x;center_y<=scan_y;
                center_weak<=reverse_scan ? weak_row[WIDTH-1] : weak_row[0];
                weak_row<=reverse_scan ? weak_row<<1 : weak_row>>1;
            end
            if(promote) sweep_changed<=1;
            case(ps)
                P_IDLE,P_DONE: if(load_start) begin
                    ps<=arm_safe ? P_LOAD : P_ARM;
                    busy<=1;ready<=0;fault<=0;changed_sweeps<=0;
                    load_addr<=0;load_x<=0;load_y<=0;capture_bank<=0;capture_shift<=0;
                end
                P_ARM: begin
                    if(load_valid) begin ps<=P_IDLE;busy<=0;fault<=1;end
                    else if(arm_safe) ps<=P_LOAD;
                end
                P_LOAD: if(load_valid) begin
                    if(!bank_free || load_state==2'b10 || load_last!=(load_addr==PIXELS-1)) begin
                        ps<=P_IDLE;busy<=0;fault<=1;
                    end else begin
                        load_addr<=load_addr+1'b1;
                        capture_shift<=word_complete ? 16'd0 : capture_next;
                        if(load_x==WIDTH-1) begin
                            capture_req[capture_bank]<=!capture_req[capture_bank];
                            if(capture_bank) capture_row1<=load_y;else capture_row0<=load_y;
                            capture_bank<=!capture_bank;load_x<=0;load_y<=load_y+1'b1;
                        end else load_x<=load_x+1'b1;
                        if(load_last) ps<=P_FLUSH;
                    end
                end
                P_FLUSH: if(capture_req==cap_ack_sync && ui_idle_sync[1]) begin
                    reverse_scan<=0;pair_changed<=0;ps<=P_SCAN_INIT;
                end
                P_SCAN_INIT: begin
                    issue_addr<=reverse_scan ? PIXELS-1 : 0;
                    issue_x<=0;scan_y<=0;sweep_changed<=0;center_valid<=0;
                    read_row<=reverse_scan ? HEIGHT-1 : 0;read_req<=!read_req;
                    ps<=P_WAIT_ROW;
                end
                P_WAIT_ROW: if(read_ack_sync[1]==read_req) begin
                    copy_issue<=0;copy_valid<=0;ps<=P_COPY;
                end
                P_COPY: begin
                    if(copy_issue==ROW_WORDS-1) ps<=P_COPY_DRAIN;
                    else copy_issue<=copy_issue+1'b1;
                end
                P_COPY_DRAIN: begin
                    // Last copied word lands on this edge. UI may now overwrite
                    // its mailbox while this row is processed from local bits.
                    if(scan_y!=HEIGHT-1) begin
                        read_row<=reverse_scan ? HEIGHT-2-scan_y : scan_y+1'b1;
                        read_req<=!read_req;
                    end
                    issue_x<=0;ps<=P_SCAN;
                end
                P_SCAN: begin
                    issue_addr<=reverse_scan ? issue_addr-1'b1 : issue_addr+1'b1;
                    if(issue_x==WIDTH-1) ps<=P_DRAIN;
                    else issue_x<=issue_x+1'b1;
                end
                P_DRAIN: ps<=P_ROW_END;
                P_ROW_END: begin
                    if(scan_y==HEIGHT-1) ps<=P_SWEEP_END;
                    else begin scan_y<=scan_y+1'b1;ps<=P_WAIT_ROW;end
                end
                P_SWEEP_END: begin
                    if(sweep_changed && changed_sweeps!=16'hffff) changed_sweeps<=changed_sweeps+1'b1;
                    if(!reverse_scan) begin
                        pair_changed<=sweep_changed;reverse_scan<=1;ps<=P_SCAN_INIT;
                    end else if(pair_changed || sweep_changed) begin
                        pair_changed<=0;reverse_scan<=0;ps<=P_SCAN_INIT;
                    end else begin busy<=0;ready<=1;ps<=P_DONE;end
                end
                default: begin ps<=P_IDLE;busy<=0;ready<=0;fault<=1;end
            endcase
        end
    end

    // AXI-domain row DMA. All command metadata is held by the pixel owner
    // until the corresponding acknowledgement has crossed back.
    (* async_reg="true" *) reg [1:0] cap_req_meta,cap_req_sync;
    (* async_reg="true" *) reg [1:0] read_req_sync,cancel_sync;
    wire pixel_cancel=!rst_n || abort || fault;
    always @(posedge axiclk) begin
        if(axirst) begin cap_req_meta<=0;cap_req_sync<=0;read_req_sync<=0;cancel_sync<=2'b11;end
        else begin
            cap_req_meta<=capture_req;cap_req_sync<=cap_req_meta;
            read_req_sync<={read_req_sync[0],read_req};
            cancel_sync<={cancel_sync[0],pixel_cancel};
        end
    end
    assign ui_cancel=cancel_sync[1];
    localparam [3:0] U_IDLE=0,U_W_PACK=1,U_W_PACK_DRAIN=2,U_W_ADDR=3,
        U_W_SEND=4,U_W_RESP=5,U_R_ADDR=6,U_R_RECV=7,U_R_UNPACK=8,U_R_DRAIN=9,U_R_FINISH=10;
    reg [3:0] us;
    reg active_bank,active_tag;
    reg [31:0] dma_addr;
    reg [7:0] dma_beat;
    reg [2:0] pack_issue,unpack_index;
    reg pack_valid,cap_is_data;
    reg [15:0] cap_q;
    reg [127:0] write_word,read_word;
    reg received_last;
    reg [31:0] timeout_count;
    wire cap_read=us==U_W_PACK;
    wire [CAP_A-1:0] cap_read_addr=active_bank*ROW_WORDS+dma_beat*8+pack_issue;
    always @(posedge axiclk) if(cap_read) cap_q<=capture_mem[cap_read_addr];
    wire [WORD_A-1:0] read_write_addr=dma_beat*8+unpack_index;
    always @(posedge axiclk) if(us==U_R_UNPACK) read_mem[read_write_addr]<=read_word[15:0];
    assign ui_idle=us==U_IDLE;
    assign m_awaddr=dma_addr;
    assign m_awlen=ROW_BEATS-1;
    assign m_awvalid=us==U_W_ADDR;
    assign m_wdata=write_word;
    assign m_wstrb=16'hffff;
    assign m_wlast=dma_beat==ROW_BEATS-1;
    assign m_wvalid=us==U_W_SEND;
    assign m_bready=us==U_W_RESP;
    assign m_araddr=dma_addr;
    assign m_arlen=ROW_BEATS-1;
    assign m_arvalid=us==U_R_ADDR;
    assign m_rready=us==U_R_RECV || us==U_R_DRAIN;
    wire bus_progress=(m_awvalid&&m_awready)||(m_wvalid&&m_wready)||
        (m_bvalid&&m_bready)||(m_arvalid&&m_arready)||(m_rvalid&&m_rready);
    always @(posedge axiclk) begin
        if(axirst) begin
            us<=U_IDLE;capture_ack<=0;read_ack<=0;ui_fault<=0;
            active_bank<=0;active_tag<=0;dma_addr<=0;dma_beat<=0;
            pack_issue<=0;pack_valid<=0;cap_is_data<=0;unpack_index<=0;
            write_word<=0;read_word<=0;received_last<=0;timeout_count<=0;
        end else begin
            pack_valid<=cap_read;
            if(cap_read) cap_is_data<=(dma_beat*8+pack_issue)<VALID_WORDS;
            if(pack_valid) write_word<={cap_is_data?cap_q:16'd0,write_word[127:16]};
            if(us==U_IDLE || bus_progress) timeout_count<=0;
            else if(timeout_count<AXI_TIMEOUT_CYCLES) timeout_count<=timeout_count+1'b1;
            else ui_fault<=1;
            case(us)
                U_IDLE: begin
                    if(ui_cancel) begin
                        capture_ack<=cap_req_sync;read_ack<=read_req_sync[1];ui_fault<=0;
                    end else if(cap_req_sync!=capture_ack) begin
                        active_bank<=(cap_req_sync[0]==capture_ack[0]);
                        active_tag<=(cap_req_sync[0]!=capture_ack[0])?cap_req_sync[0]:cap_req_sync[1];
                        dma_addr<=WEAK_BASE+((cap_req_sync[0]!=capture_ack[0])?capture_row0:capture_row1)*ROW_BYTES;
                        dma_beat<=0;pack_issue<=0;pack_valid<=0;us<=U_W_PACK;
                    end else if(read_req_sync[1]!=read_ack) begin
                        active_tag<=read_req_sync[1];dma_addr<=WEAK_BASE+read_row*ROW_BYTES;
                        dma_beat<=0;us<=U_R_ADDR;
                    end
                end
                U_W_PACK: begin
                    if(pack_issue==7) us<=U_W_PACK_DRAIN;
                    else pack_issue<=pack_issue+1'b1;
                end
                U_W_PACK_DRAIN: us<=dma_beat==0 ? U_W_ADDR : U_W_SEND;
                U_W_ADDR: if(m_awready) us<=U_W_SEND;
                U_W_SEND: if(m_wready) begin
                    if(dma_beat==ROW_BEATS-1) us<=U_W_RESP;
                    else begin dma_beat<=dma_beat+1'b1;pack_issue<=0;pack_valid<=0;us<=U_W_PACK;end
                end
                U_W_RESP: if(m_bvalid) begin
                    if(m_bresp!=0) ui_fault<=1;
                    capture_ack[active_bank]<=active_tag;us<=U_IDLE;
                end
                U_R_ADDR: if(m_arready) us<=U_R_RECV;
                U_R_RECV: if(m_rvalid) begin
                    if(m_rresp!=0 || m_rlast!=(dma_beat==ROW_BEATS-1)) ui_fault<=1;
                    read_word<=m_rdata;received_last<=m_rlast;unpack_index<=0;us<=U_R_UNPACK;
                end
                U_R_UNPACK: begin
                    read_word<=read_word>>16;
                    if(unpack_index==7) begin
                        if(received_last) us<=U_R_FINISH;
                        else if(dma_beat==ROW_BEATS-1) us<=U_R_DRAIN;
                        else begin dma_beat<=dma_beat+1'b1;us<=U_R_RECV;end
                    end else unpack_index<=unpack_index+1'b1;
                end
                U_R_DRAIN: if(m_rvalid&&m_rlast) us<=U_R_FINISH;
                U_R_FINISH: begin read_ack<=active_tag;us<=U_IDLE;end
                default: begin us<=U_IDLE;ui_fault<=1;end
            endcase
        end
    end
endmodule
