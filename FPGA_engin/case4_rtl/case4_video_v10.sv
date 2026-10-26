`timescale 1ns/1ps
// Native-coordinate comparison. Left is original gray; right is either
// original RGB with red edges or binary edges. No scaling and no duplication.
// V6: continuous foreground display; exact Canny runs on another pinned RGB
// frame. Publish matched RGB plus a completed DDR edge slot at vertical blank.
// Never alternate strong-edge previews with completed hysteresis results.
module case4_video_v10 #(
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
    input wire uart_rx_i,output wire uart_tx_o,
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
    wire [2:0] mode;wire [1:0] median_mode,app_mode,view_mode,accessory;
    wire effect_motion,gamma_enable,user_freeze,ui_paused,temporal_enable;
    wire geometry_enable,bilateral_enable,bridge_enable,menu_open,capture_mask;
    wire [4:0] menu_index;wire [10:0] roi_x0,roi_y0,roi_x1,roi_y1;
    wire [7:0] event_code;wire [31:0] event_seq,config_revision;
    wire [3:0] geometry_valid;wire [7:0] circle_score,rect_score,triangle_score,ellipse_score;
    wire circle_outline,rect_outline,triangle_outline,ellipse_outline;
    wire geometry_busy,geometry_overflow;
    wire [2:0] geometry_reject;wire [7:0] geometry_candidates;
    wire [15:0] geometry_observations,geometry_analyses,geometry_timeouts,geometry_dropped;
    wire [10:0] cx0,cx1,cy0,cy1,rx0,rx1,ry0,ry1,tx0,tx1,ty0,ty1,ex0,ex1,ey0,ey1;
    wire [10:0] model_origin_x,model_origin_y;wire [2:0] model_ds;
    wire [4:0] rect_fit_angle,ellipse_fit_angle;wire [41:0] triangle_vertices;wire [3:0] triangle_tolerance;
    wire signed [18:0] rect_fit_umin,rect_fit_umax,rect_fit_vmin,rect_fit_vmax,
      ellipse_fit_umin,ellipse_fit_umax,ellipse_fit_vmin,ellipse_fit_vmax;
    wire raw_source=bridge_enable&&(mode>=4||app_mode==3);
    wire [7:0] source_kind,output_mode;wire capture_mask_active;
    wire link_lost,event_overflow;wire [511:0] status_data;
    wire cmd_valid,cmd_accept,heartbeat,uart_busy;wire [7:0] cmd_id,cmd_result;
    wire [15:0] arg0,arg1,arg2,arg3;
    wire median_enable=median_mode!=0;
    wire auto_enable=1'b0,strobe_capture_toggle=1'b0;
    wire [2:0] strobe_interval=0;
    wire [1:0] algorithm=(mode==1||mode==3)?1:0;
    assign history_mode=view_mode==0?0:1;assign history_paused=ui_paused;assign reference_toggle=0;
    assign event_mark_toggle=0;assign event_mark_frame_id=0;assign event_mark_bank=0;assign event_recall_toggle=0;
    case4_v10_controls #(.CLK_HZ(CLK_HZ),.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES),
      .LONG_CYCLES(LONG_CYCLES),.CHORD_CYCLES(CHORD_CYCLES)) controls(
      .clk(clk),.rst_n(!rst),.frame_start(raw_frame_start),.key_n(key_n),.heartbeat(heartbeat),
      .cmd_valid(cmd_valid),.cmd_id(cmd_id),.cmd_arg0(arg0),.cmd_arg1(arg1),.cmd_arg2(arg2),.cmd_arg3(arg3),
      .cmd_accept(cmd_accept),.cmd_result(cmd_result),.threshold(manual_threshold),.mode(mode),
      .median_mode(median_mode),.app_mode(app_mode),.view_mode(view_mode),.accessory(accessory),
      .effect_motion(effect_motion),.gamma_enable(gamma_enable),.freeze_request(user_freeze),
      .history_paused(ui_paused),.temporal_enable(temporal_enable),.geometry_enable(geometry_enable),
      .bilateral_enable(bilateral_enable),.bridge_enable(bridge_enable),.menu_open(menu_open),.menu_index(menu_index),
      .roi_x0(roi_x0),.roi_y0(roi_y0),.roi_x1(roi_x1),.roi_y1(roi_y1),
      .event_code(event_code),.event_seq(event_seq),.config_revision(config_revision),
      .link_lost(link_lost),.event_overflow(event_overflow),.status_data(status_data),.board_fault(ddr_error||processing_fault),
      .step_prev_toggle(step_prev_toggle),.step_next_toggle(step_next_toggle),.capture_mask(capture_mask),
      .source_kind(source_kind),.output_mode(output_mode),.capture_mask_active(capture_mask_active),
      .display_source_id(video_id),.selected_index(selected_index),.history_count(history_count),
      .geometry_valid(geometry_valid),.circle_score(circle_score),.rectangle_score(rect_score),.triangle_score(triangle_score),.ellipse_score(ellipse_score),
      .geometry_busy(geometry_busy),.geometry_overflow(geometry_overflow),.geometry_reject(geometry_reject),.geometry_candidates(geometry_candidates),
      .geometry_observed(geometry_observations),.geometry_analyses(geometry_analyses),.geometry_timeouts(geometry_timeouts),.geometry_dropped(geometry_dropped));
    case4_v10_uart #(.CLK_HZ(CLK_HZ)) uart(.clk(clk),.rst_n(!rst),.rx_i(uart_rx_i),.tx_o(uart_tx_o),
      .cmd_valid(cmd_valid),.cmd_id(cmd_id),.cmd_arg0(arg0),.cmd_arg1(arg1),.cmd_arg2(arg2),.cmd_arg3(arg3),
      .cmd_accept(cmd_accept),.cmd_result(cmd_result),.status_data(status_data),.heartbeat(heartbeat),.busy(uart_busy));
    wire ph,pv,pd,psobel;wire [7:0] pedges;wire [10:0] pmagnitude;
    // Per-coordinate temporal Schmitt threshold: new edges need T, previously
    // published edges remain only while this new frame still has >=T/2 gradient.
    wire stable_sobel=psobel;
    wire [23:0] background_rgb;
    wire [31:0] pmeta;
    wire [2:0] adaptive_gamma_level;reg [2:0] job_gamma_level;
    reg job_gamma_enable;reg [2:0] slot_gamma_level[0:1];reg slot_gamma_enable[0:1];
    reg frame_had_pixels;wire stats_start=in_de&&in_vs&&!frame_had_pixels;
    always @(posedge clk)begin
      if(rst)frame_had_pixels<=0;
      else if(raw_frame_start)frame_had_pixels<=0;
      else if(in_de&&in_vs)frame_had_pixels<=1;
    end
    case4_v10_gamma gamma_stats(.clk(clk),.rst(rst),.enable(gamma_enable),
      .frame_start(stats_start),.source_fresh(ddr_frame_ready),.source_id(id_sync),
      .in_hs(in_hs),.in_vs(in_vs),.in_de(in_de),.in_rgb(in_rgb),
      .gamma_level(adaptive_gamma_level));
    wire gh,gv,gd;wire [23:0] corrected_display,corrected_background;
    wire [7:0] corrected_edges;wire gamma_edges_ready;
    case4_v10_gamma_curve display_gamma(.clk(clk),.rst(rst),
      .enable(!raw_source&&canny_display_valid&&slot_gamma_enable[slot_sync[1]]),
      .level(slot_gamma_level[slot_sync[1]]),.in_hs(in_hs),.in_vs(in_vs),.in_de(in_de),.in_rgb(in_rgb),
      .out_hs(gh),.out_vs(gv),.out_de(gd),.out_rgb(corrected_display));
    case4_v10_gamma_curve background_gamma(.clk(clk),.rst(rst),.enable(job_gamma_enable),
      .level(job_gamma_level),.in_hs(in_hs),.in_vs(in_vs),.in_de(in_de),.in_rgb(background_rgb),
      .out_rgb(corrected_background));
    case4_raster_delay #(.WIDTH(8),.STAGES(3)) gamma_edge_delay(clk,rst,in_edges,corrected_edges,gamma_edges_ready);
    always @(posedge clk)begin
      if(rst)begin job_gamma_level<=2;job_gamma_enable<=0;
        slot_gamma_level[0]<=2;slot_gamma_level[1]<=2;slot_gamma_enable[0]<=0;slot_gamma_enable[1]<=0;end
      else begin
        if(state==IDLE)begin job_gamma_level<=adaptive_gamma_level;job_gamma_enable<=gamma_enable;end
        if(complete_task)begin slot_gamma_level[publish_slot]<=job_gamma_level;slot_gamma_enable[publish_slot]<=job_gamma_enable;end
      end
    end

    wire [1:0] pclass;
    case4_v10_pipeline #(.W(IMG_WIDTH),.H(IMG_HEIGHT),.HT(H_TOTAL)) pipeline(
        .clk(clk),.rst(rst),.in_hs(gh),.in_vs(gv),.in_de(gd),.in_rgb(corrected_display),
        .scharr(1'b0),.median_mode(median_mode),.canny_enable(algorithm==1 && history_mode==0 && history_active_mode==0),.threshold(threshold),
        .process_rgb(corrected_background),.in_edges(corrected_edges),.out_edges(pedges),
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
    assign canny_enable=!raw_source;
    assign freeze_request=history_mode==0 && user_freeze;
    localparam [3:0] IDLE=0,REQUEST=1,WAIT_RAW=2,WAIT_PIPE=3,LOAD=4,
        COMPUTE=5,PUBLISH=6,CANCEL=7,WAIT_FREE=8,POST=9;
    reg [3:0] state;
    reg [10:0] threshold_seen;
    reg [1:0] median_seen;reg canny_seen,auto_seen,gamma_seen,temporal_seen;reg [1:0] algorithm_seen,history_seen;reg [5:0] selected_seen,completed_selection;
    wire [10:0] auto_threshold=manual_threshold;reg [7:0] mean_luma;wire auto_ready=1'b1;
    wire config_changed=manual_threshold!=threshold_seen || median_mode!=median_seen || algorithm!=algorithm_seen || auto_enable!=auto_seen || gamma_enable!=gamma_seen || temporal_enable!=temporal_seen || history_mode!=history_seen || (history_mode!=0&&selected_index!=selected_seen);
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
    wire roi_valid=pd && pv;
    wire roi_last=px==IMG_WIDTH-1 && py==IMG_HEIGHT-1;
    wire [9:0] task_luma_sum={2'b0,background_rgb[23:16]}+{1'b0,background_rgb[15:8],1'b0}+{2'b0,background_rgb[7:0]};
    // Small sampled mean for exposure compensation. No automatic edge threshold.
    reg [31:0] mean_sum;reg [21:0] mean_count;
    reg [31:0] mean_dividend,mean_divisor,mean_quotient,mean_remainder;
    reg [5:0] mean_left;reg mean_busy;
    wire [32:0] mean_next={mean_remainder,mean_dividend[31]};
    wire mean_subtract=mean_next>={1'b0,mean_divisor};
    wire [31:0] mean_qnext={mean_quotient[30:0],mean_subtract};
    always @(posedge clk)begin
      if(rst)begin mean_sum<=0;mean_count<=0;mean_luma<=128;mean_dividend<=0;mean_divisor<=1;
       mean_quotient<=0;mean_remainder<=0;mean_left<=0;mean_busy<=0;end
      else begin
       if(map_start)begin mean_sum<=0;mean_count<=0;end
       else if(state==LOAD&&in_de&&in_vs)begin mean_sum<=mean_sum+task_luma_sum[9:2];mean_count<=mean_count+1'b1;end
       if(state==LOAD&&roi_valid&&roi_last&&mean_count!=0)begin
        mean_dividend<=mean_sum;mean_divisor<=mean_count;mean_quotient<=0;mean_remainder<=0;mean_left<=32;mean_busy<=1;end
       else if(mean_busy)begin
        mean_dividend<={mean_dividend[30:0],1'b0};mean_quotient<=mean_qnext;
        mean_remainder<=mean_subtract?mean_next-{1'b0,mean_divisor}:mean_next;
        mean_left<=mean_left-1'b1;if(mean_left==1)begin mean_busy<=0;mean_luma<=mean_qnext[7:0];end
       end
      end
    end
    reg foreground_valid;
    wire show_map=foreground_valid;
    localparam integer ROI_WIDTH=IMG_WIDTH;
    localparam integer MAP_ADDR_BITS=$clog2(ROI_WIDTH*IMG_HEIGHT);
    always @(posedge clk) begin
        if(rst) begin
            proc_ack_sync<=0;pub_ack_sync<=0;proc_meta<=0;proc_sync<=0;slot_sync<=0;
            state<=IDLE;threshold<=128;threshold_seen<=128;median_seen<=1;canny_seen<=0;algorithm_seen<=0;auto_seen<=0;gamma_seen<=1;temporal_seen<=1;history_seen<=0;selected_seen<=0;completed_selection<=0;
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
            threshold_seen<=manual_threshold;median_seen<=median_mode;history_seen<=history_mode;selected_seen<=selected_index;canny_seen<=canny_enable;algorithm_seen<=algorithm;auto_seen<=auto_enable;gamma_seen<=gamma_enable;temporal_seen<=temporal_enable;
            reader_start<=0;
            if(pipe_frame_start) foreground_valid<=canny_enable&&canny_display_valid;
            if((!canny_enable || ddr_error || config_changed || (user_freeze&&!user_freeze_q&&history_mode==0)) && state!=IDLE && state!=CANCEL && state!=WAIT_FREE) state<=CANCEL;
            else case(state)
                IDLE: if(canny_enable&&(!user_freeze||history_mode!=0||history_reset_pending)&&!ddr_error&&ddr_frame_ready&&reader_idle&&(history_mode==0||!processed_valid||completed_selection!=selected_index||history_reset_pending)) begin
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
                    else if(map_published&&map_ready&&!mean_busy) begin
                    temporal_payload_latched<={held_id,held_bank,publish_slot,mean_luma,temporal_enable,strobe_capture_toggle,strobe_interval,job_history_reset,32'd0};
                    temporal_request<=!temporal_request;state<=POST;end
                POST: if(temporal_ack_sync[2]==temporal_request)begin
                    if(temporal_fault_sync[1]||temporal_duplicate_sync[1])state<=CANCEL;
                    else begin
                      last_processed_id<=held_id;processed_valid<=1;history_reset_pending<=0;completed_selection<=selected_index;
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
        .load_start(map_start),.load_valid(state==LOAD && roi_valid),.load_last(roi_last),.load_state(algorithm==1?pclass:{2{stable_sobel}}),.bypass_hysteresis(algorithm!=1),
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
    case4_v9_temporal_ddr #(.WIDTH(ROI_WIDTH),.HEIGHT(IMG_HEIGHT),.RGB_WIDTH(IMG_WIDTH),.STATE_BASE0(32'h01800000),.STATE_BASE1(32'h01c00000)) temporal(
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
    wire complete_task=!config_changed&&canny_enable&&state==POST&&temporal_ack_sync[2]==temporal_request&&!temporal_fault_sync[1]&&!temporal_duplicate_sync[1];
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
    // Identical latency for raw bridge and board rendering: pmeta always carries
    // the original RGB, independently of the background algorithm input.
    reg bridge_frame,raw_frame,mask_frame;reg [2:0] display_mode;
    reg [1:0] slot_algorithm[0:1],slot_median[0:1];reg [10:0] slot_threshold[0:1];reg slot_temporal[0:1];
    always @(posedge clk)begin
     if(rst)begin bridge_frame<=0;raw_frame<=0;mask_frame<=0;display_mode<=0;slot_algorithm[0]<=0;slot_algorithm[1]<=0;slot_median[0]<=0;slot_median[1]<=0;slot_threshold[0]<=0;slot_threshold[1]<=0;slot_temporal[0]<=0;slot_temporal[1]<=0;end
     else begin
      if(complete_task)begin slot_algorithm[publish_slot]<=algorithm;slot_median[publish_slot]<=median_mode;
       slot_threshold[publish_slot]<=manual_threshold;slot_temporal[publish_slot]<=temporal_enable;end
      if(pipe_frame_start)begin bridge_frame<=bridge_enable;raw_frame<=raw_source;
       mask_frame<=capture_mask&&mode<4&&app_mode==0;display_mode<=mode;end
     end
    end
    assign source_kind=raw_frame?8'd1:8'd0;
    assign output_mode=raw_frame?{5'd0,display_mode}:
      (foreground_valid&&slot_threshold[slot_sync[1]]==manual_threshold&&slot_median[slot_sync[1]]==median_mode&&
       slot_temporal[slot_sync[1]]==temporal_enable&&slot_gamma_enable[slot_sync[1]]==gamma_enable&&slot_algorithm[slot_sync[1]]==((display_mode==1||display_mode==3)?1:0)?{5'd0,display_mode}:8'hff);
    assign capture_mask_active=mask_frame&&!raw_frame;
    reg [43:0] geometry_roi_seen;reg [31:0] geometry_source_seen;reg geometry_observed;
    wire geometry_roi_changed=geometry_roi_seen!={roi_x0,roi_y0,roi_x1,roi_y1};
    wire geometry_active=geometry_enable&&mode<4&&app_mode==0&&!raw_source&&output_mode!=8'hff;
    wire geometry_clear=config_changed||geometry_roi_changed;wire geometry_sample_accept;
    wire geometry_sample=geometry_active&&!geometry_busy&&!geometry_roi_changed&&
       (!geometry_observed||id_sync!=geometry_source_seen);
    always @(posedge clk)begin
     if(rst)begin geometry_roi_seen<=0;geometry_source_seen<=0;geometry_observed<=0;end
     else begin
      if(!geometry_active||geometry_clear)geometry_observed<=0;
      if(pipe_frame_start)begin geometry_roi_seen<={roi_x0,roi_y0,roi_x1,roi_y1};
       if(geometry_sample_accept)begin geometry_source_seen<=id_sync;geometry_observed<=1;end
      end
     end
    end
    // One high-quality model fit is sufficient, including on a frozen source;
    // loss hysteresis still needs three newly observed failures before clearing.
    case4_v10_shape #(.IMG_WIDTH(IMG_WIDTH),.IMG_HEIGHT(IMG_HEIGHT),.CONFIRM_FRAMES(1)) geometry(
      .clk(clk),.rst_n(!rst),.clear(geometry_clear),.enable(geometry_active),
      .frame_start(pipe_frame_start),.sample_tick(geometry_sample),.sample_accept(geometry_sample_accept),.pixel_valid(pd&&pv),
      .x(11'(px)),.y(11'(py)),.edge_bit(show_map&&pedges[1]),
      .roi_x0(roi_x0),.roi_y0(roi_y0),.roi_x1(roi_x1),.roi_y1(roi_y1),
      .circle_valid(geometry_valid[0]),.rect_valid(geometry_valid[1]),
      .triangle_valid(geometry_valid[2]),.ellipse_valid(geometry_valid[3]),
      .circle_x0(cx0),.circle_x1(cx1),.circle_y0(cy0),.circle_y1(cy1),
      .rect_x0(rx0),.rect_x1(rx1),.rect_y0(ry0),.rect_y1(ry1),
      .triangle_x0(tx0),.triangle_x1(tx1),.triangle_y0(ty0),.triangle_y1(ty1),
      .ellipse_x0(ex0),.ellipse_x1(ex1),.ellipse_y0(ey0),.ellipse_y1(ey1),
      .model_origin_x(model_origin_x),.model_origin_y(model_origin_y),.model_ds(model_ds),
      .rect_fit_angle(rect_fit_angle),.rect_fit_umin(rect_fit_umin),.rect_fit_umax(rect_fit_umax),.rect_fit_vmin(rect_fit_vmin),.rect_fit_vmax(rect_fit_vmax),
      .ellipse_fit_angle(ellipse_fit_angle),.ellipse_fit_umin(ellipse_fit_umin),.ellipse_fit_umax(ellipse_fit_umax),.ellipse_fit_vmin(ellipse_fit_vmin),.ellipse_fit_vmax(ellipse_fit_vmax),
      .triangle_vertices(triangle_vertices),.triangle_tolerance(triangle_tolerance),
      .circle_score(circle_score),.rect_score(rect_score),.triangle_score(triangle_score),.ellipse_score(ellipse_score),
      .busy(geometry_busy),.overflow(geometry_overflow),.reject_reason(geometry_reject),.candidate_count(geometry_candidates),
      .observed_count(geometry_observations),.analysis_count(geometry_analyses),.timeout_count(geometry_timeouts),.dropped_count(geometry_dropped));
    wire [3:0] geometry_outline;
    case4_v10_overlay overlay(.clk(clk),.rst(rst),.pixel_valid(pd&&pv),.edge_bit(show_map&&pedges[1]),
      .x(11'(px)),.y(11'(py)),.valid(geometry_valid),
      .circle_x0(cx0),.circle_x1(cx1),.circle_y0(cy0),.circle_y1(cy1),
      .rect_x0(rx0),.rect_x1(rx1),.rect_y0(ry0),.rect_y1(ry1),
      .triangle_x0(tx0),.triangle_x1(tx1),.triangle_y0(ty0),.triangle_y1(ty1),
      .ellipse_x0(ex0),.ellipse_x1(ex1),.ellipse_y0(ey0),.ellipse_y1(ey1),
      .model_origin_x(model_origin_x),.model_origin_y(model_origin_y),.model_ds(model_ds),
      .rect_fit_angle(rect_fit_angle),.rect_fit_umin(rect_fit_umin),.rect_fit_umax(rect_fit_umax),.rect_fit_vmin(rect_fit_vmin),.rect_fit_vmax(rect_fit_vmax),
      .ellipse_fit_angle(ellipse_fit_angle),.ellipse_fit_umin(ellipse_fit_umin),.ellipse_fit_umax(ellipse_fit_umax),.ellipse_fit_vmin(ellipse_fit_vmin),.ellipse_fit_vmax(ellipse_fit_vmax),
      .triangle_vertices(triangle_vertices),.triangle_tolerance(triangle_tolerance),.outline(geometry_outline));
    assign {ellipse_outline,triangle_outline,rect_outline,circle_outline}=geometry_outline;
    wire [64:0] render_bus;wire render_ready;
    wire rh,rv,rd;wire [31:0] render_meta;wire [7:0] render_edges;wire [10:0] render_x,render_y;
    case4_raster_delay #(.WIDTH(65),.STAGES(8)) render_delay(clk,rst,{ph,pv,pd,pmeta,pedges,11'(px),11'(py)},render_bus,render_ready);
    assign {rh,rv,rd,render_meta,render_edges,render_x,render_y}=render_bus;
    reg app_h,app_v,app_d,app_bridge;reg [10:0] app_x,app_y;reg [23:0] app_rgb;
    wire unsupported=!bridge_enable&&(mode>=4||app_mode==3);
    always @(posedge clk)begin
     if(rst)begin app_h<=1;app_v<=1;app_d<=0;app_rgb<=0;app_x<=0;app_y<=0;app_bridge<=0;end
     else begin
      app_h<=rh;app_v<=rv;app_d<=rd;app_x<=render_x;app_y<=render_y;app_bridge<=bridge_frame;
      if(!rd)app_rgb<=0;
      else if(raw_frame)app_rgb<=render_meta[31:8];
      else if(mask_frame)app_rgb<=show_map&&render_edges[1]?24'hffffff:24'h000000;
      else if(unsupported)app_rgb<=render_meta[31:8];
      else if((geometry_enable||(menu_open&&menu_index>=15&&menu_index<=19))&&
       render_x>=roi_x0&&render_x<=roi_x1&&render_y>=roi_y0&&render_y<=roi_y1&&
       (render_x==roi_x0||render_x==roi_x1||render_y==roi_y0||render_y==roi_y1)&&(render_x[3]^render_y[3]))app_rgb<=24'h00ffff;
      else if(geometry_active&&circle_outline)app_rgb<=24'hffff00;
      else if(geometry_active&&rect_outline)app_rgb<=24'h0000ff;
      else if(geometry_active&&triangle_outline)app_rgb<=24'h00ff00;
      else if(geometry_active&&ellipse_outline)app_rgb<=24'hff00ff;
      else if(effect_motion)app_rgb<=show_map&&render_edges[1]?(render_edges[4]?24'hff0000:24'hffff00):24'h000000;
      else if(mode==2||mode==3)app_rgb<=show_map&&render_edges[1]?24'hffffff:24'h000000;
      else app_rgb<=show_map&&render_edges[1]?24'hff0000:render_meta[31:8];
     end
    end
    case4_v10_osd osd(.clk(clk),.rst(rst),.enable(!app_bridge),
      .in_hs(app_h),.in_vs(app_v),.in_de(app_d),.x(app_x),.y(app_y),.in_rgb(app_rgb),
      .status(status_data),.mode(mode),.threshold(manual_threshold),.menu_open(menu_open),.menu_index(menu_index),
      .link_lost(link_lost),.unsupported(unsupported),.fault(ddr_error||processing_fault),
      .out_hs(out_hs),.out_vs(out_vs),.out_de(out_de),.out_rgb(out_rgb));
endmodule
