`timescale 1ns/1ps
// Native-coordinate comparison. Left is original gray; right is either
// original RGB with red edges or binary edges. No scaling and no duplication.
// V6: continuous foreground display; exact Canny runs on another pinned RGB
// frame. Publish matched RGB plus a completed DDR edge slot at vertical blank.
// Never alternate strong-edge previews with completed hysteresis results.
module case4_video_v8 #(
    parameter integer IMG_WIDTH=1280, IMG_HEIGHT=720, H_TOTAL=1650,
    parameter integer CLK_HZ=74399000,
    parameter integer EXTERNAL_WEAK=0, PIPE_OSD=0,
    parameter integer DEBOUNCE_CYCLES=CLK_HZ/50,
    parameter integer LONG_CYCLES=(CLK_HZ/10)*7,
    parameter integer CHORD_CYCLES=CLK_HZ,
    parameter integer X_BITS=$clog2(IMG_WIDTH), Y_BITS=$clog2(IMG_HEIGHT)
) (
    input wire clk,rst,in_hs,in_vs,in_de,
    input wire [23:0] in_rgb,
    input wire [1:0] key_n,
    input wire ddr_frozen,ddr_frame_ready,ddr_error,
    output wire [1:0] history_mode,
    output wire history_paused,step_prev_toggle,step_next_toggle,reference_toggle,
    input wire history_ready,
    input wire [1:0] history_active_mode,
    input wire [6:0] history_count,
    input wire [5:0] selected_index,reference_index,
    input wire active_paused,
    output wire freeze_request,
    output wire out_hs,out_vs,out_de,
    output wire [23:0] out_rgb,
    input wire [7:0] in_edges,input wire canny_display_valid,canny_display_slot,
    input wire [31:0] display_frame_id,capture_count,input wire [5:0] display_bank,
    input wire display_frame_toggle,input wire [2:0] event_status,
    output wire event_mark_toggle,output wire [31:0] event_mark_frame_id,
    output wire [5:0] event_mark_bank,output wire event_recall_toggle,
    output wire canny_enable,
    output reg process_request_toggle,process_release_toggle,publish_toggle,publish_slot,
    input wire process_ack_toggle,process_valid,input wire [5:0] process_bank,input wire [31:0] process_frame_id,
    input wire publish_ack_toggle,
    input wire axiclk, axirst,
    output wire [31:0] m_awaddr,
    output wire [7:0] m_awlen,
    output wire m_awvalid,
    input wire m_awready,
    output wire [127:0] m_wdata,
    output wire [15:0] m_wstrb,
    output wire m_wlast,
    output wire m_wvalid,
    input wire m_wready,
    input wire [1:0] m_bresp,
    input wire m_bvalid,
    output wire m_bready,
    output wire [31:0] m_araddr,
    output wire [7:0] m_arlen,
    output wire m_arvalid,
    input wire m_arready,
    input wire [127:0] m_rdata,
    input wire [1:0] m_rresp,
    input wire m_rlast,
    input wire m_rvalid,
    output wire m_rready
);
    reg raw_vs_q,pipe_vs_q,user_freeze_q;
    wire raw_frame_start=raw_vs_q&&!in_vs;
    wire [10:0] manual_threshold;reg [10:0] threshold;
    wire [1:0] app_mode;wire auto_enable,thick_enable,menu_open,temporal_enable,strobe_capture_toggle;
    wire [2:0] effect_mode,strobe_interval;
    assign event_mark_toggle=0;assign event_mark_frame_id=0;assign event_mark_bank=0;assign event_recall_toggle=0;
    wire [3:0] menu_index;
    wire [2:0] mode;wire [1:0] algorithm=(mode==4||mode==5)?2:(mode==1||mode==3)?1:0;
    wire median_enable,user_freeze;
    case4_v8_controls #(.CLK_HZ(CLK_HZ),.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES),
        .LONG_CYCLES(LONG_CYCLES),.CHORD_CYCLES(CHORD_CYCLES)) controls(
        .clk(clk),.rst_n(!rst),.key_n(key_n),.frame_start(raw_frame_start),
        .threshold(manual_threshold),.mode(mode),.median_enable(median_enable),.freeze_request(user_freeze),
        .history_mode(history_mode),.history_paused(history_paused),
        .step_prev_toggle(step_prev_toggle),.step_next_toggle(step_next_toggle),.reference_toggle(reference_toggle),
        .app_mode(app_mode),.auto_enable(auto_enable),.thick_enable(thick_enable),
        .effect_mode(effect_mode),.temporal_enable(temporal_enable),.strobe_capture_toggle(strobe_capture_toggle),.strobe_interval(strobe_interval),
        .menu_open(menu_open),.menu_index(menu_index));
    wire ph,pv,pd,psobel;wire [7:0] pedges;wire [10:0] pmagnitude;
    // Per-coordinate temporal Schmitt threshold: new edges need T, previously
    // published edges remain only while this new frame still has >=T/2 gradient.
    wire stable_sobel=psobel;
    wire [23:0] background_rgb;
    wire [31:0] pmeta;
    wire [1:0] pclass;
    case4_v8_pipeline #(.W(IMG_WIDTH),.H(IMG_HEIGHT),.HT(H_TOTAL)) pipeline(
        .clk(clk),.rst(rst),.in_hs(in_hs),.in_vs(in_vs),.in_de(in_de),.in_rgb(in_rgb),
        .scharr(algorithm==2),.median_enable(median_enable),.canny_enable(algorithm==1 && history_mode==0 && history_active_mode==0),.threshold(threshold),
        .process_rgb(background_rgb),.in_edges(in_edges),.out_edges(pedges),
        .out_hs(ph),.out_vs(pv),.out_de(pd),.out_meta(pmeta),.out_sobel(psobel),.out_class(pclass),.out_magnitude(pmagnitude));
    wire [X_BITS-1:0] px;
    wire [Y_BITS-1:0] py;
    case4_raster_xy #(.W(IMG_WIDTH),.H(IMG_HEIGHT)) coordinates(clk,rst,pv,pd,px,py);
    wire pipe_frame_start=pipe_vs_q&&!pv;
    always @(posedge clk) begin
        if(rst) begin raw_vs_q<=1;pipe_vs_q<=1;user_freeze_q<=0;end
        else begin raw_vs_q<=in_vs;pipe_vs_q<=pv;user_freeze_q<=user_freeze;end
    end

    // Background ownership is independent of the foreground read bank.
    // A published map and its exact RGB frame switch only in the store's blank.
    assign canny_enable=history_mode==0 && history_active_mode==0;
    assign freeze_request=history_mode==0 && history_active_mode==0 && user_freeze;
    localparam [3:0] IDLE=0,REQUEST=1,WAIT_RAW=2,WAIT_PIPE=3,LOAD=4,
        COMPUTE=5,PUBLISH=6,CANCEL=7,WAIT_FREE=8,POST=9;
    reg [3:0] state;
    reg [10:0] threshold_seen;
    reg median_seen,canny_seen,auto_seen,temporal_seen;reg [1:0] algorithm_seen;
    wire [10:0] auto_threshold,auto_target;wire [7:0] mean_luma;wire auto_ready;
    wire config_changed=manual_threshold!=threshold_seen || median_enable!=median_seen || algorithm!=algorithm_seen || auto_enable!=auto_seen || temporal_enable!=temporal_seen;
    (* async_reg="true" *) reg [2:0] proc_ack_sync,pub_ack_sync;
    (* async_reg="true" *) reg [6:0] proc_meta,proc_sync;
    (* async_reg="true" *) reg [1:0] slot_sync;
    reg [5:0] held_bank;reg [31:0] held_id;
    (* async_reg="true" *) reg [31:0] proc_id_meta,proc_id_sync;
    reg temporal_request,history_reset_pending,job_history_reset;
    reg temporal_abort_request;
    reg [84:0] temporal_payload_latched;
    reg [31:0] last_processed_id;reg processed_valid;
    (* async_reg="true" *) reg [2:0] temporal_ack_sync;
    (* async_reg="true" *) reg [1:0] temporal_fault_sync,temporal_duplicate_sync;
    wire temporal_ack,temporal_fault_result,temporal_duplicate_result;
    reg reader_start;reg [4:0] release_wait;
    wire reader_active,reader_idle,reader_fault;
    wire map_busy,map_ready,map_fault,map_edge,map_published;
    wire [15:0] sweeps;
    wire reader_abort=rst || state==IDLE || state==CANCEL || state==WAIT_FREE || !canny_enable;
    wire map_abort=rst || state==IDLE || state==REQUEST || state==WAIT_RAW || state==CANCEL || state==WAIT_FREE || !canny_enable;
    wire map_start=state==WAIT_PIPE && pipe_frame_start && reader_active && !reader_fault;
    wire roi_valid=pd && pv && px>=IMG_WIDTH/2;
    wire roi_last=px==IMG_WIDTH-1 && py==IMG_HEIGHT-1;
    wire [9:0] task_luma_sum={2'b0,background_rgb[23:16]}+{1'b0,background_rgb[15:8],1'b0}+{2'b0,background_rgb[7:0]};
    case4_v8_auto_threshold automatic_threshold(.clk(clk),.rst(rst),.start(map_start),
      .valid(state==LOAD&&roi_valid),.finish(state==LOAD&&roi_valid&&roi_last),
      .magnitude(pmagnitude),.luma_valid(state==LOAD&&in_de&&in_vs),
      .luma(task_luma_sum[9:2]),
      .next_threshold(auto_threshold),.ready(auto_ready),.mean_luma(mean_luma),.target_threshold(auto_target));
    reg foreground_valid;
    wire show_map=foreground_valid;
    localparam integer ROI_WIDTH=IMG_WIDTH/2;
    localparam integer MAP_ADDR_BITS=$clog2(ROI_WIDTH*IMG_HEIGHT);
    always @(posedge clk) begin
        if(rst) begin
            proc_ack_sync<=0;pub_ack_sync<=0;proc_meta<=0;proc_sync<=0;slot_sync<=0;
            state<=IDLE;threshold<=128;threshold_seen<=128;median_seen<=1;canny_seen<=0;algorithm_seen<=0;auto_seen<=1;temporal_seen<=1;
            process_request_toggle<=0;process_release_toggle<=0;publish_toggle<=0;publish_slot<=1;
            held_bank<=0;held_id<=0;proc_id_meta<=0;proc_id_sync<=0;reader_start<=0;foreground_valid<=0;release_wait<=0;
            temporal_request<=0;temporal_abort_request<=0;temporal_payload_latched<=0;temporal_ack_sync<=0;temporal_fault_sync<=0;temporal_duplicate_sync<=0;
            history_reset_pending<=1;job_history_reset<=1;last_processed_id<=0;processed_valid<=0;
        end else begin
            proc_ack_sync<={proc_ack_sync[1:0],process_ack_toggle};
            pub_ack_sync<={pub_ack_sync[1:0],publish_ack_toggle};
            proc_meta<={process_valid,process_bank};proc_sync<=proc_meta;
            proc_id_meta<=process_frame_id;proc_id_sync<=proc_id_meta;
            temporal_abort_request<=state==CANCEL||!canny_enable;
            temporal_ack_sync<={temporal_ack_sync[1:0],temporal_ack};
            temporal_fault_sync<={temporal_fault_sync[0],temporal_fault_result};
            temporal_duplicate_sync<={temporal_duplicate_sync[0],temporal_duplicate_result};
            if(config_changed||!canny_enable)history_reset_pending<=1;
            slot_sync<={slot_sync[0],canny_display_slot};
            threshold_seen<=manual_threshold;median_seen<=median_enable;canny_seen<=canny_enable;algorithm_seen<=algorithm;auto_seen<=auto_enable;temporal_seen<=temporal_enable;
            reader_start<=0;
            if(pipe_frame_start) foreground_valid<=canny_enable&&canny_display_valid;
            if((!canny_enable || ddr_error || config_changed || user_freeze) && state!=IDLE && state!=CANCEL && state!=WAIT_FREE) state<=CANCEL;
            else case(state)
                IDLE: if(canny_enable&&!user_freeze&&!ddr_error&&ddr_frame_ready&&reader_idle) begin
                    process_request_toggle<=!process_request_toggle;state<=REQUEST;
                end
                REQUEST: if(proc_ack_sync[2]==process_request_toggle) begin
                    if(proc_sync[6]) begin
                      held_bank<=proc_sync[5:0];held_id<=proc_id_sync;publish_slot<=!slot_sync[1];
                      threshold<=auto_enable?auto_threshold:manual_threshold;job_history_reset<=history_reset_pending;
                      if(processed_valid&&proc_id_sync==last_processed_id&&!history_reset_pending)state<=CANCEL;
                      else state<=WAIT_RAW;
                    end
                    else state<=IDLE;
                end
                WAIT_RAW: if(raw_frame_start&&reader_idle) begin reader_start<=1;state<=WAIT_PIPE;end
                WAIT_PIPE: if(reader_fault) state<=CANCEL;
                    else if(map_start) state<=LOAD;
                LOAD: if(reader_fault||map_fault) state<=CANCEL;
                    else if(roi_valid&&roi_last) state<=COMPUTE;
                COMPUTE: if(reader_fault||map_fault) state<=CANCEL;
                    else if(map_published&&map_ready&&auto_ready) begin
                    temporal_payload_latched<={held_id,held_bank,publish_slot,mean_luma,temporal_enable,strobe_capture_toggle,strobe_interval,job_history_reset,32'd0};
                    temporal_request<=!temporal_request;state<=POST;end
                POST: if(temporal_ack_sync[2]==temporal_request)begin
                    if(temporal_fault_sync[1]||temporal_duplicate_sync[1])state<=CANCEL;
                    else begin
                      last_processed_id<=held_id;processed_valid<=1;history_reset_pending<=0;
                      publish_toggle<=!publish_toggle;state<=PUBLISH;
                    end
                end
                PUBLISH: if(pub_ack_sync[2]==publish_toggle) state<=CANCEL;
                CANCEL: if(reader_idle && temporal_ack_sync[2]==temporal_request && proc_ack_sync[2]==process_request_toggle && pub_ack_sync[2]==publish_toggle) begin
                    process_release_toggle<=!process_release_toggle;release_wait<=0;state<=WAIT_FREE;
                end
                WAIT_FREE: if(release_wait==16) state<=IDLE;else release_wait<=release_wait+1'b1;
                default: state<=CANCEL;
            endcase
        end
    end
    wire [31:0] bg_awaddr;
    wire [7:0] bg_awlen;
    wire bg_awvalid;
    wire bg_awready;
    wire [127:0] bg_wdata;
    wire [15:0] bg_wstrb;
    wire bg_wlast;
    wire bg_wvalid;
    wire bg_wready;
    wire [1:0] bg_bresp;
    wire bg_bvalid;
    wire bg_bready;
    wire [31:0] bg_araddr;
    wire [7:0] bg_arlen;
    wire bg_arvalid;
    wire bg_arready;
    wire [127:0] bg_rdata;
    wire [1:0] bg_rresp;
    wire bg_rlast;
    wire bg_rvalid;
    wire bg_rready;
    wire [31:0] hy_awaddr;
    wire [7:0] hy_awlen;
    wire hy_awvalid;
    wire hy_awready;
    wire [127:0] hy_wdata;
    wire [15:0] hy_wstrb;
    wire hy_wlast;
    wire hy_wvalid;
    wire hy_wready;
    wire [1:0] hy_bresp;
    wire hy_bvalid;
    wire hy_bready;
    wire [31:0] hy_araddr;
    wire [7:0] hy_arlen;
    wire hy_arvalid;
    wire hy_arready;
    wire [127:0] hy_rdata;
    wire [1:0] hy_rresp;
    wire hy_rlast;
    wire hy_rvalid;
    wire hy_rready;
    assign bg_awaddr=0;assign bg_awlen=0;assign bg_awvalid=0;
    assign bg_wdata=0;assign bg_wstrb=0;assign bg_wlast=0;assign bg_wvalid=0;assign bg_bready=1;
    case4_background_reader #(.FRAME_BYTES(IMG_WIDTH*IMG_HEIGHT*2)) background_reader(
        .clk(clk),.rst(rst),.start(reader_start),.abort(reader_abort),.bank(held_bank),
        .pixel_de(in_de),.pixel_rgb(background_rgb),.active(reader_active),.idle(reader_idle),.fault(reader_fault),
        .axiclk(axiclk),.axirst(axirst),
        .m_araddr(bg_araddr),
        .m_arlen(bg_arlen),
        .m_arvalid(bg_arvalid),
        .m_arready(bg_arready),
        .m_rdata(bg_rdata),
        .m_rresp(bg_rresp),
        .m_rlast(bg_rlast),
        .m_rvalid(bg_rvalid),
        .m_rready(bg_rready));
    case4_hysteresis_fast_ddr #(.WIDTH(ROI_WIDTH),.HEIGHT(IMG_HEIGHT)) hysteresis(
        .clk(clk),.rst_n(!rst),.abort(map_abort),
        .load_start(map_start),.load_valid(state==LOAD && roi_valid),.load_last(roi_last),.load_state(algorithm==1?pclass:{2{algorithm==2?pclass[1]:stable_sobel}}),.bypass_hysteresis(algorithm!=1),
        .busy(map_busy),.ready(map_ready),.fault(map_fault),.changed_sweeps(sweeps),
        .publish_base(publish_slot?32'h01240000:32'h01200000),.published(map_published),
        .rd_en(1'b0),.rd_addr({MAP_ADDR_BITS{1'b0}}),.rd_edge(map_edge),
        .axiclk(axiclk),.axirst(axirst),
        .m_awaddr(hy_awaddr),
        .m_awlen(hy_awlen),
        .m_awvalid(hy_awvalid),
        .m_awready(hy_awready),
        .m_wdata(hy_wdata),
        .m_wstrb(hy_wstrb),
        .m_wlast(hy_wlast),
        .m_wvalid(hy_wvalid),
        .m_wready(hy_wready),
        .m_bresp(hy_bresp),
        .m_bvalid(hy_bvalid),
        .m_bready(hy_bready),
        .m_araddr(hy_araddr),
        .m_arlen(hy_arlen),
        .m_arvalid(hy_arvalid),
        .m_arready(hy_arready),
        .m_rdata(hy_rdata),
        .m_rresp(hy_rresp),
        .m_rlast(hy_rlast),
        .m_rvalid(hy_rvalid),
        .m_rready(hy_rready));
    wire [31:0] base_awaddr;
    wire [7:0] base_awlen;
    wire base_awvalid;
    wire base_awready;
    wire [127:0] base_wdata;
    wire [15:0] base_wstrb;
    wire base_wlast;
    wire base_wvalid;
    wire base_wready;
    wire [1:0] base_bresp;
    wire base_bvalid;
    wire base_bready;
    wire [31:0] base_araddr;
    wire [7:0] base_arlen;
    wire base_arvalid;
    wire base_arready;
    wire [127:0] base_rdata;
    wire [1:0] base_rresp;
    wire base_rlast;
    wire base_rvalid;
    wire base_rready;
    wire [31:0] tm_awaddr;
    wire [7:0] tm_awlen;
    wire tm_awvalid;
    wire tm_awready;
    wire [127:0] tm_wdata;
    wire [15:0] tm_wstrb;
    wire tm_wlast;
    wire tm_wvalid;
    wire tm_wready;
    wire [1:0] tm_bresp;
    wire tm_bvalid;
    wire tm_bready;
    wire [31:0] tm_araddr;
    wire [7:0] tm_arlen;
    wire tm_arvalid;
    wire tm_arready;
    wire [127:0] tm_rdata;
    wire [1:0] tm_rresp;
    wire tm_rlast;
    wire tm_rvalid;
    wire tm_rready;
    case4_axi_arbiter background_arbiter(.clk(axiclk),.rst(axirst),
        .s0_awaddr(bg_awaddr),
        .s0_awlen(bg_awlen),
        .s0_awvalid(bg_awvalid),
        .s0_awready(bg_awready),
        .s0_wdata(bg_wdata),
        .s0_wstrb(bg_wstrb),
        .s0_wlast(bg_wlast),
        .s0_wvalid(bg_wvalid),
        .s0_wready(bg_wready),
        .s0_bresp(bg_bresp),
        .s0_bvalid(bg_bvalid),
        .s0_bready(bg_bready),
        .s0_araddr(bg_araddr),
        .s0_arlen(bg_arlen),
        .s0_arvalid(bg_arvalid),
        .s0_arready(bg_arready),
        .s0_rdata(bg_rdata),
        .s0_rresp(bg_rresp),
        .s0_rlast(bg_rlast),
        .s0_rvalid(bg_rvalid),
        .s0_rready(bg_rready),
        .s1_awaddr(hy_awaddr),
        .s1_awlen(hy_awlen),
        .s1_awvalid(hy_awvalid),
        .s1_awready(hy_awready),
        .s1_wdata(hy_wdata),
        .s1_wstrb(hy_wstrb),
        .s1_wlast(hy_wlast),
        .s1_wvalid(hy_wvalid),
        .s1_wready(hy_wready),
        .s1_bresp(hy_bresp),
        .s1_bvalid(hy_bvalid),
        .s1_bready(hy_bready),
        .s1_araddr(hy_araddr),
        .s1_arlen(hy_arlen),
        .s1_arvalid(hy_arvalid),
        .s1_arready(hy_arready),
        .s1_rdata(hy_rdata),
        .s1_rresp(hy_rresp),
        .s1_rlast(hy_rlast),
        .s1_rvalid(hy_rvalid),
        .s1_rready(hy_rready),
        .m_awaddr(base_awaddr),
        .m_awlen(base_awlen),
        .m_awvalid(base_awvalid),
        .m_awready(base_awready),
        .m_wdata(base_wdata),
        .m_wstrb(base_wstrb),
        .m_wlast(base_wlast),
        .m_wvalid(base_wvalid),
        .m_wready(base_wready),
        .m_bresp(base_bresp),
        .m_bvalid(base_bvalid),
        .m_bready(base_bready),
        .m_araddr(base_araddr),
        .m_arlen(base_arlen),
        .m_arvalid(base_arvalid),
        .m_arready(base_arready),
        .m_rdata(base_rdata),
        .m_rresp(base_rresp),
        .m_rlast(base_rlast),
        .m_rvalid(base_rvalid),
        .m_rready(base_rready));


    // Bundled payload settles two clocks before request detection. Source pin,
    // raw map slot and configuration remain fixed until completion/abort ACK.
    (* async_reg="true" *) reg [2:0] tm_req_sync;
    (* async_reg="true" *) reg [1:0] tm_abort_sync;
    reg tm_seen,tm_ack,tm_start,tm_fault_latched,tm_duplicate_latched;
    reg [84:0] tm_payload_meta,tm_payload;
    wire tm_busy,tm_done,tm_fault,tm_duplicate,tm_strobe_active;
    wire [1:0] tm_strobe_count,tm_depth;wire [31:0] tm_completed_id;
    assign temporal_ack=tm_ack;assign temporal_fault_result=tm_fault_latched;assign temporal_duplicate_result=tm_duplicate_latched;
    always @(posedge axiclk)begin
      if(axirst)begin tm_req_sync<=0;tm_abort_sync<=0;tm_seen<=0;tm_ack<=0;tm_start<=0;
       tm_payload_meta<=0;tm_payload<=0;tm_fault_latched<=0;tm_duplicate_latched<=0;end
      else begin
       tm_req_sync<={tm_req_sync[1:0],temporal_request};
       tm_abort_sync<={tm_abort_sync[0],temporal_abort_request};
       tm_payload_meta<=temporal_payload_latched;
       tm_payload<=tm_payload_meta;tm_start<=0;
       if(tm_req_sync[2]!=tm_seen&&!tm_busy)begin tm_start<=1;tm_seen<=tm_req_sync[2];end
       if(tm_done)begin tm_fault_latched<=tm_fault;tm_duplicate_latched<=tm_duplicate;tm_ack<=tm_seen;end
      end
    end
    case4_v8_temporal_ddr #(.WIDTH(ROI_WIDTH),.HEIGHT(IMG_HEIGHT),.RGB_WIDTH(IMG_WIDTH)) temporal(
      .clk(axiclk),.rst(axirst),.start(tm_start),.abort(tm_abort_sync[1]),.clear_history(tm_payload[32]),
      .source_id(tm_payload[84:53]),.raw_base(tm_payload[46]?32'h01240000:32'h01200000),
      .rgb_base(32'h02000000+{4'd0,tm_payload[52:47],22'd0}),
      .output_base(tm_payload[46]?32'h01600000:32'h01400000),.source_mean(tm_payload[45:38]),
      .motion_threshold(8'd16),.temporal_enable(tm_payload[37]),.strobe_toggle(tm_payload[36]),.strobe_interval(tm_payload[35:33]),
      .busy(tm_busy),.done(tm_done),.fault(tm_fault),.duplicate(tm_duplicate),.strobe_count(tm_strobe_count),
      .history_depth(tm_depth),.strobe_active(tm_strobe_active),.completed_source_id(tm_completed_id),
      .m_awaddr(tm_awaddr),
      .m_awlen(tm_awlen),
      .m_awvalid(tm_awvalid),
      .m_awready(tm_awready),
      .m_wdata(tm_wdata),
      .m_wstrb(tm_wstrb),
      .m_wlast(tm_wlast),
      .m_wvalid(tm_wvalid),
      .m_wready(tm_wready),
      .m_bresp(tm_bresp),
      .m_bvalid(tm_bvalid),
      .m_bready(tm_bready),
      .m_araddr(tm_araddr),
      .m_arlen(tm_arlen),
      .m_arvalid(tm_arvalid),
      .m_arready(tm_arready),
      .m_rdata(tm_rdata),
      .m_rresp(tm_rresp),
      .m_rlast(tm_rlast),
      .m_rvalid(tm_rvalid),
      .m_rready(tm_rready));
    case4_axi_arbiter temporal_arbiter(.clk(axiclk),.rst(axirst),
      .s0_awaddr(base_awaddr),
      .s0_awlen(base_awlen),
      .s0_awvalid(base_awvalid),
      .s0_awready(base_awready),
      .s0_wdata(base_wdata),
      .s0_wstrb(base_wstrb),
      .s0_wlast(base_wlast),
      .s0_wvalid(base_wvalid),
      .s0_wready(base_wready),
      .s0_bresp(base_bresp),
      .s0_bvalid(base_bvalid),
      .s0_bready(base_bready),
      .s0_araddr(base_araddr),
      .s0_arlen(base_arlen),
      .s0_arvalid(base_arvalid),
      .s0_arready(base_arready),
      .s0_rdata(base_rdata),
      .s0_rresp(base_rresp),
      .s0_rlast(base_rlast),
      .s0_rvalid(base_rvalid),
      .s0_rready(base_rready),
      .s1_awaddr(tm_awaddr),
      .s1_awlen(tm_awlen),
      .s1_awvalid(tm_awvalid),
      .s1_awready(tm_awready),
      .s1_wdata(tm_wdata),
      .s1_wstrb(tm_wstrb),
      .s1_wlast(tm_wlast),
      .s1_wvalid(tm_wvalid),
      .s1_wready(tm_wready),
      .s1_bresp(tm_bresp),
      .s1_bvalid(tm_bvalid),
      .s1_bready(tm_bready),
      .s1_araddr(tm_araddr),
      .s1_arlen(tm_arlen),
      .s1_arvalid(tm_arvalid),
      .s1_arready(tm_arready),
      .s1_rdata(tm_rdata),
      .s1_rresp(tm_rresp),
      .s1_rlast(tm_rlast),
      .s1_rvalid(tm_rvalid),
      .s1_rready(tm_rready),
      .m_awaddr(m_awaddr),
      .m_awlen(m_awlen),
      .m_awvalid(m_awvalid),
      .m_awready(m_awready),
      .m_wdata(m_wdata),
      .m_wstrb(m_wstrb),
      .m_wlast(m_wlast),
      .m_wvalid(m_wvalid),
      .m_wready(m_wready),
      .m_bresp(m_bresp),
      .m_bvalid(m_bvalid),
      .m_bready(m_bready),
      .m_araddr(m_araddr),
      .m_arlen(m_arlen),
      .m_arvalid(m_arvalid),
      .m_arready(m_arready),
      .m_rdata(m_rdata),
      .m_rresp(m_rresp),
      .m_rlast(m_rlast),
      .m_rvalid(m_rvalid),
      .m_rready(m_rready));
    // Display receives source-coherent RGB and eight metadata bits. All
    // application drawing runs on the completed foreground, never work RAM.
    (* async_reg="true" *) reg [31:0] id_meta,id_sync,cap_meta,cap_sync;
    (* async_reg="true" *) reg [2:0] strobe_meta,strobe_sync;
    reg [31:0] video_id,last_id,capture_packet;
    reg fresh_video;
    reg [1:0] history_frame_mode,history_frame_ui;
    reg [7:0] capture_fps,processing_fps;
    reg [31:0] second_count,last_capture_count,millisecond_count;
    reg [15:0] completed_this_second,processing_ms,elapsed_ms;reg measuring,processing_fault;
    wire complete_task=state==POST&&temporal_ack_sync[2]==temporal_request&&!temporal_fault_sync[1]&&!temporal_duplicate_sync[1];
    wire [31:0] capture_delta=capture_packet-last_capture_count;
    always @(posedge clk)begin
      if(rst)begin
       id_meta<=0;id_sync<=0;cap_meta<=0;cap_sync<=0;strobe_meta<=0;strobe_sync<=0;
       video_id<=0;last_id<=0;capture_packet<=0;fresh_video<=0;history_frame_mode<=0;history_frame_ui<=0;
       capture_fps<=0;processing_fps<=0;second_count<=0;last_capture_count<=0;
       completed_this_second<=0;processing_ms<=0;elapsed_ms<=0;millisecond_count<=0;measuring<=0;processing_fault<=0;
      end else begin
       id_meta<=display_frame_id;id_sync<=id_meta;cap_meta<=capture_count;cap_sync<=cap_meta;
       strobe_meta<={tm_strobe_active,tm_strobe_count};strobe_sync<=strobe_meta;
       if(!canny_enable||config_changed||user_freeze||complete_task)processing_fault<=0;
       else if((state==LOAD||state==COMPUTE)&&(reader_fault||map_fault))processing_fault<=1;
       else if(state==POST&&temporal_ack_sync[2]==temporal_request&&temporal_fault_sync[1])processing_fault<=1;
       if(pipe_frame_start)begin
        video_id<=id_sync;last_id<=id_sync;capture_packet<=cap_sync;
        fresh_video<=id_sync!=last_id&&canny_display_valid&&history_active_mode==0;
        history_frame_mode<=history_active_mode;
        history_frame_ui<=history_active_mode!=0?history_active_mode:history_mode;
       end
       if(second_count==CLK_HZ-1)begin
        second_count<=0;last_capture_count<=capture_packet;capture_fps<=capture_delta>255?255:capture_delta[7:0];
        processing_fps<=completed_this_second>255?255:completed_this_second[7:0];completed_this_second<=complete_task?1:0;
       end else begin second_count<=second_count+1'b1;if(complete_task)completed_this_second<=completed_this_second+1'b1;end
       if(map_start)begin measuring<=1;elapsed_ms<=0;millisecond_count<=0;end
       else if(measuring)begin
        if(millisecond_count>=CLK_HZ/1000-1)begin millisecond_count<=0;if(elapsed_ms!=65535)elapsed_ms<=elapsed_ms+1'b1;end
        else millisecond_count<=millisecond_count+1'b1;
        if(complete_task)begin measuring<=0;processing_ms<=elapsed_ms;end
        else if(state==CANCEL||state==IDLE)measuring<=0;
       end
      end
    end
    reg rh,rv,rd,rv_q,rshow;reg [31:0] rmeta;reg [7:0] redges;
    reg [10:0] rx,ry;reg [2:0] rmode,reffect;reg [1:0] rhistory;
    wire app_frame_start=rv_q&&!rv;
    wire displayed_edge=rshow&&redges[1];
    wire geometry_enable=app_mode==0&&history_frame_ui==0&&mode==0&&effect_mode==0;
    wire circle_valid,rect_valid,circle_edge,rect_edge,shape_busy,shape_overflow,shape_tick;
    wire [10:0] cx0,cx1,cy0,cy1,qx0,qx1,qy0,qy1;wire [7:0] circle_score,rect_score;
    case4_v8_shape #(.IMG_WIDTH(IMG_WIDTH),.IMG_HEIGHT(IMG_HEIGHT)) shapes(
      .clk(clk),.rst_n(!rst),.clear(!geometry_enable),.frame_start(app_frame_start),
      .sample_tick(app_frame_start&&fresh_video&&rshow),.pixel_valid(rd&&rv),.x(rx),.y(ry),.edge_bit(displayed_edge),
      .circle_valid(circle_valid),.rect_valid(rect_valid),.circle_x0(cx0),.circle_x1(cx1),.circle_y0(cy0),.circle_y1(cy1),
      .rect_x0(qx0),.rect_x1(qx1),.rect_y0(qy0),.rect_y1(qy1),.circle_outline(circle_edge),.rect_outline(rect_edge),
      .circle_score(circle_score),.rect_score(rect_score),.busy(shape_busy),.overflow(shape_overflow),.result_tick(shape_tick));
    wire face_valid,face_edge,face_tick,face_observation,face_busy,face_overflow;wire [7:0] face_score;
    wire [10:0] fx0,fx1,fy0,fy1;
    case4_v8_face #(.IMG_WIDTH(IMG_WIDTH),.IMG_HEIGHT(IMG_HEIGHT)) faces(
      .clk(clk),.rst_n(!rst),.clear(app_mode!=3||history_frame_ui!=0),.frame_start(app_frame_start),
      .sample_tick(app_frame_start&&fresh_video&&rshow),.pixel_valid(rd&&rv),.x(rx),.y(ry),.rgb(rmeta[31:8]),.edge_bit(displayed_edge),
      .face_valid(face_valid),.bbox_x0(fx0),.bbox_x1(fx1),.bbox_y0(fy0),.bbox_y1(fy1),.face_outline(face_edge),.score(face_score),
      .observation_valid(face_observation),.result_tick(face_tick),.busy(face_busy),.overflow(face_overflow));
    reg oh,ov,od,bh,bv,bd,app_h,app_v,app_d,app_vq;
    reg [31:0] ometa,bmeta;reg [7:0] oedges,bedges;
    reg [10:0] ox,oy,bx,by,app_x,app_y;
    reg [2:0] omode,bmode,oeffect,beffect;reg [1:0] ohistory,bhistory;
    reg ocircle,orect,oface,bcircle,brect,bface,oshow,bshow;
    reg [23:0] app_rgb;reg app_edge,app_stroke_enable,app_white;
    wire render_edge=bshow&&bedges[1];
    wire monochrome_mode=bmode==2||bmode==3||bmode==4;
    wire [23:0] trail_rgb={{8{bedges[0]}},{8{bedges[2]}},{8{bedges[3]}}};
    wire [23:0] strobe_rgb={{8{bedges[7]}},{8{bedges[6]}},{8{bedges[5]}}};
    wire face_box=face_valid&&((bx==fx0||bx==fx1)&&(by>=fy0&&by<=fy1)||
                             (by==fy0||by==fy1)&&(bx>=fx0&&bx<=fx1));
    always @(posedge clk)begin
      if(rst)begin
       rh<=1;rv<=1;rd<=0;rv_q<=1;rshow<=0;rmeta<=0;redges<=0;rx<=0;ry<=0;rmode<=0;reffect<=0;rhistory<=0;
       oh<=1;ov<=1;od<=0;bh<=1;bv<=1;bd<=0;app_h<=1;app_v<=1;app_d<=0;app_vq<=1;
       ometa<=0;bmeta<=0;oedges<=0;bedges<=0;ox<=0;oy<=0;bx<=0;by<=0;app_x<=0;app_y<=0;
       omode<=0;bmode<=0;oeffect<=0;beffect<=0;ohistory<=0;bhistory<=0;
       ocircle<=0;orect<=0;oface<=0;bcircle<=0;brect<=0;bface<=0;oshow<=0;bshow<=0;app_rgb<=0;
       app_edge<=0;app_stroke_enable<=0;app_white<=0;
      end else begin
       rh<=ph;rv<=pv;rd<=pd;rv_q<=rv;rshow<=show_map;rmeta<=pmeta;redges<=pedges;
       rx<=px;ry<=py;rmode<=mode;reffect<=app_mode==3?0:effect_mode;rhistory<=history_frame_mode;
       oh<=rh;ov<=rv;od<=rd;ometa<=rmeta;oedges<=redges;ox<=rx;oy<=ry;omode<=rmode;oeffect<=reffect;ohistory<=rhistory;oshow<=rshow;
       ocircle<=geometry_enable&&circle_edge;orect<=geometry_enable&&rect_edge;oface<=face_edge;
       bh<=oh;bv<=ov;bd<=od;bmeta<=ometa;bedges<=oedges;bx<=ox;by<=oy;bmode<=omode;beffect<=oeffect;bhistory<=ohistory;bshow<=oshow;
       bcircle<=ocircle;brect<=orect;bface<=oface;
       app_h<=bh;app_v<=bv;app_d<=bd;app_vq<=app_v;app_x<=bx;app_y<=by;
       app_edge<=render_edge;app_white<=monochrome_mode;
       app_stroke_enable<=thick_enable&&bhistory==0&&beffect==0&&bx>=IMG_WIDTH/2&&bshow;
       if(!bd)app_rgb<=0;
       else if(bhistory!=0)app_rgb<=bmeta[31:8];
       else if(beffect==2)app_rgb<=bshow&&(bx<IMG_WIDTH/2?bedges[0]:bedges[1])?24'hffffff:0;
       else if(bx<IMG_WIDTH/2)app_rgb<={3{bmeta[7:0]}};
       else if(app_mode==3&&(bface||face_box))app_rgb<=24'h00ffb0;
       else if(beffect==1)app_rgb<=bshow?trail_rgb:0;
       else if(beffect==3)app_rgb<=bshow&&bedges[4]?24'hffffff:0;
       else if(beffect==4)app_rgb<=bshow?(strobe_rgb|(bedges[1]?24'h404040:0)):0;
       else if(bcircle)app_rgb<=24'hffff00;
       else if(brect)app_rgb<=24'h0088ff;
       else if(monochrome_mode)app_rgb<=render_edge?24'hffffff:0;
       else app_rgb<=render_edge?24'hff0000:bmeta[31:8];
      end
    end
    wire stroke_h,stroke_v,stroke_d;wire [10:0] stroke_x,stroke_y;wire [23:0] stroke_rgb;
    reg stroke_vq;
    always @(posedge clk)if(rst)stroke_vq<=1;else stroke_vq<=stroke_v;
    case4_v8_display_stroke #(.W(IMG_WIDTH),.H(IMG_HEIGHT),.HT(H_TOTAL)) stroke(
      .clk(clk),.rst(rst),.in_hs(app_h),.in_vs(app_v),.in_de(app_d),.in_x(app_x),.in_y(app_y),
      .in_rgb(app_rgb),.in_edge(app_edge),.enable(app_stroke_enable),.stroke_white(app_white),
      .out_hs(stroke_h),.out_vs(stroke_v),.out_de(stroke_d),.out_x(stroke_x),.out_y(stroke_y),.out_rgb(stroke_rgb));
    case4_v8_osd osd(.clk(clk),.rst(rst),.frame_start(stroke_vq&&!stroke_v),
     .in_hs(stroke_h),.in_vs(stroke_v),.in_de(stroke_d),.x(stroke_x),.y(stroke_y),.in_rgb(stroke_rgb),
     .app_mode(app_mode),.history_mode(history_frame_ui),.mode(mode),.effect_mode(effect_mode),.strobe_interval(strobe_interval),
     .threshold(threshold),.auto_target(auto_target),.mean_luma(mean_luma),.median_enable(median_enable),.frozen(user_freeze),
     .processing(history_frame_ui!=0?!history_ready:!foreground_valid),.auto_enable(auto_enable),.thick_enable(thick_enable),.temporal_enable(temporal_enable),.fault(ddr_error||processing_fault),
     .circle_found(circle_valid&&geometry_enable),.rectangle_found(rect_valid&&geometry_enable),.face_found(face_valid),
     .strobe_busy(strobe_sync[2]),.strobe_ready(strobe_sync[1:0]==3),
     .capture_fps(capture_fps),.processing_fps(processing_fps),.processing_ms(processing_ms),
     .menu_open(menu_open),.menu_index(menu_index),.history_paused(active_paused),.history_count(history_count),
     .selected_index(selected_index),.reference_index(reference_index),.out_hs(out_hs),.out_vs(out_vs),.out_de(out_de),.out_rgb(out_rgb));

endmodule
