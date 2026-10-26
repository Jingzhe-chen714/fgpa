`timescale 1ns/1ps
// Native-coordinate comparison. Left is original gray; right is either
// original RGB with red edges or binary edges. No scaling and no duplication.
// V6: continuous foreground display; exact Canny runs on another pinned RGB
// frame. Publish matched RGB plus a completed DDR edge slot at vertical blank.
// Never alternate strong-edge previews with completed hysteresis results.
module case4_video_demo #(
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
    input wire in_edge,canny_display_valid,canny_display_slot,
    input wire [31:0] display_frame_id,capture_count,input wire [5:0] display_bank,
    input wire display_frame_toggle,input wire [2:0] event_status,
    output reg event_mark_toggle,output reg [31:0] event_mark_frame_id,
    output reg [5:0] event_mark_bank,output wire event_recall_toggle,
    output wire canny_enable,
    output reg process_request_toggle,process_release_toggle,publish_toggle,publish_slot,
    input wire process_ack_toggle,process_valid,input wire [5:0] process_bank,
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
    wire [1:0] app_mode,noise_level;wire auto_enable,thick_enable,learn_toggle,clear_toggle,menu_open;
    wire [3:0] menu_index;
    wire [1:0] mode;
    wire median_enable,user_freeze;
    case4_demo_controls #(.CLK_HZ(CLK_HZ),.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES),
        .LONG_CYCLES(LONG_CYCLES),.CHORD_CYCLES(CHORD_CYCLES)) controls(
        .clk(clk),.rst_n(!rst),.key_n(key_n),.frame_start(raw_frame_start),
        .threshold(manual_threshold),.mode(mode),.median_enable(median_enable),.freeze_request(user_freeze),
        .history_mode(history_mode),.history_paused(history_paused),
        .step_prev_toggle(step_prev_toggle),.step_next_toggle(step_next_toggle),.reference_toggle(reference_toggle),
        .app_mode(app_mode),.auto_enable(auto_enable),.noise_level(noise_level),.thick_enable(thick_enable),
        .learn_toggle(learn_toggle),.clear_toggle(clear_toggle),.event_recall_toggle(event_recall_toggle),
        .menu_open(menu_open),.menu_index(menu_index));
    wire ph,pv,pd,psobel,pedge;wire [10:0] pmagnitude;
    // Per-coordinate temporal Schmitt threshold: new edges need T, previously
    // published edges remain only while this new frame still has >=T/2 gradient.
    wire stable_sobel=pmagnitude!=0 && ((pmagnitude>=threshold) || (pedge && pmagnitude>=(threshold>>1)));
    wire [23:0] background_rgb;
    wire [31:0] pmeta;
    wire [1:0] pclass;
    case4_demo_pipeline #(.W(IMG_WIDTH),.H(IMG_HEIGHT),.HT(H_TOTAL)) pipeline(
        .clk(clk),.rst(rst),.in_hs(in_hs),.in_vs(in_vs),.in_de(in_de),.in_rgb(in_rgb),
        .noise_level(noise_level),.median_enable(median_enable),.canny_enable(mode[0] && history_mode==0 && history_active_mode==0),.threshold(threshold),
        .process_rgb(background_rgb),.in_edge(in_edge),.out_edge(pedge),
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
        COMPUTE=5,PUBLISH=6,CANCEL=7,WAIT_FREE=8;
    reg [3:0] state;
    reg [10:0] threshold_seen;
    reg median_seen,canny_seen,algorithm_seen,auto_seen;reg [1:0] noise_seen;
    wire [10:0] auto_threshold;wire auto_ready;
    wire config_changed=manual_threshold!=threshold_seen || median_enable!=median_seen || mode[0]!=algorithm_seen || auto_enable!=auto_seen || noise_level!=noise_seen;
    (* async_reg="true" *) reg [2:0] proc_ack_sync,pub_ack_sync;
    (* async_reg="true" *) reg [6:0] proc_meta,proc_sync;
    (* async_reg="true" *) reg [1:0] slot_sync;
    reg [5:0] held_bank;
    reg reader_start;reg [4:0] release_wait;
    wire reader_active,reader_idle,reader_fault;
    wire map_busy,map_ready,map_fault,map_edge,map_published;
    wire [15:0] sweeps;
    wire reader_abort=rst || state==IDLE || state==CANCEL || state==WAIT_FREE || !canny_enable;
    wire map_abort=rst || state==IDLE || state==REQUEST || state==WAIT_RAW || state==CANCEL || state==WAIT_FREE || !canny_enable;
    wire map_start=state==WAIT_PIPE && pipe_frame_start && reader_active && !reader_fault;
    wire roi_valid=pd && pv && px>=IMG_WIDTH/2;
    wire roi_last=px==IMG_WIDTH-1 && py==IMG_HEIGHT-1;
    case4_auto_threshold automatic_threshold(.clk(clk),.rst(rst),.start(map_start),
      .valid(state==LOAD&&roi_valid),.finish(state==LOAD&&roi_valid&&roi_last),
      .magnitude(pmagnitude),.next_threshold(auto_threshold),.ready(auto_ready));
    reg foreground_valid;
    wire show_map=foreground_valid;
    localparam integer ROI_WIDTH=IMG_WIDTH/2;
    localparam integer MAP_ADDR_BITS=$clog2(ROI_WIDTH*IMG_HEIGHT);
    always @(posedge clk) begin
        if(rst) begin
            proc_ack_sync<=0;pub_ack_sync<=0;proc_meta<=0;proc_sync<=0;slot_sync<=0;
            state<=IDLE;threshold<=128;threshold_seen<=128;median_seen<=1;canny_seen<=0;algorithm_seen<=0;auto_seen<=0;noise_seen<=0;
            process_request_toggle<=0;process_release_toggle<=0;publish_toggle<=0;publish_slot<=1;
            held_bank<=0;reader_start<=0;foreground_valid<=0;release_wait<=0;
        end else begin
            proc_ack_sync<={proc_ack_sync[1:0],process_ack_toggle};
            pub_ack_sync<={pub_ack_sync[1:0],publish_ack_toggle};
            proc_meta<={process_valid,process_bank};proc_sync<=proc_meta;
            slot_sync<={slot_sync[0],canny_display_slot};
            threshold_seen<=manual_threshold;median_seen<=median_enable;canny_seen<=canny_enable;algorithm_seen<=mode[0];auto_seen<=auto_enable;noise_seen<=noise_level;
            reader_start<=0;
            if(pipe_frame_start) foreground_valid<=canny_enable&&canny_display_valid;
            if((!canny_enable || ddr_error || config_changed || user_freeze) && state!=IDLE && state!=CANCEL && state!=WAIT_FREE) state<=CANCEL;
            else case(state)
                IDLE: if(canny_enable&&!user_freeze&&!ddr_error&&ddr_frame_ready&&reader_idle) begin
                    process_request_toggle<=!process_request_toggle;state<=REQUEST;
                end
                REQUEST: if(proc_ack_sync[2]==process_request_toggle) begin
                    if(proc_sync[6]) begin held_bank<=proc_sync[5:0];publish_slot<=!slot_sync[1];threshold<=auto_enable?auto_threshold:manual_threshold;state<=WAIT_RAW;end
                    else state<=IDLE;
                end
                WAIT_RAW: if(raw_frame_start&&reader_idle) begin reader_start<=1;state<=WAIT_PIPE;end
                WAIT_PIPE: if(reader_fault) state<=CANCEL;
                    else if(map_start) state<=LOAD;
                LOAD: if(reader_fault||map_fault) state<=CANCEL;
                    else if(roi_valid&&roi_last) state<=COMPUTE;
                COMPUTE: if(reader_fault||map_fault) state<=CANCEL;
                    else if(map_published&&map_ready) begin publish_toggle<=!publish_toggle;state<=PUBLISH;end
                PUBLISH: if(pub_ack_sync[2]==publish_toggle) state<=CANCEL;
                CANCEL: if(reader_idle && proc_ack_sync[2]==process_request_toggle && pub_ack_sync[2]==publish_toggle) begin
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
        .load_start(map_start),.load_valid(state==LOAD && roi_valid),.load_last(roi_last),.load_state(mode[0]?pclass:{2{stable_sobel}}),.bypass_hysteresis(!mode[0]),
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

    // The DDR edge bit and visible-frame metadata take the same fixed raster
    // delay. No partially computed work map is ever used for display.
    reg rh,rv,rd,rsobel,rstrong,rshow;
    reg [31:0] rmeta;
    reg [10:0] rx;
    reg [10:0] ry;
    reg [1:0] rmode;
    reg [1:0] history_frame_mode,history_frame_ui,rhistory,ohistory,rhistory_ui,ohistory_ui;
    always @(posedge clk) begin
        if(rst) begin history_frame_mode<=0;history_frame_ui<=0;end
        else if(pipe_frame_start) begin
            // The FIFO reader confirms its selected frame in vertical blank.
            // A requested mode can precede that confirmation by an entire
            // frame; never interpret comparison pixels as a live RGB frame.
            history_frame_mode<=history_active_mode;
            history_frame_ui<=history_active_mode!=0?history_active_mode:history_mode;
        end
    end
    wire displayed_edge=rshow && rstrong;
    reg rv_q;
    wire [1:0] detected_shape;wire shape_result_tick,shape_observation;
    wire [10:0] box_x0,box_x1;
    wire [10:0] box_y0,box_y1;
    wire geometric_target_pixel=(detected_shape==1 || detected_shape==2) &&
        rx>=box_x0 && rx<=box_x1 && ry>=box_y0 && ry<=box_y1;
    case4_demo_shape_candidates #(.IMG_WIDTH(IMG_WIDTH),.IMG_HEIGHT(IMG_HEIGHT)) detector(
        .clk(clk),.rst_n(!rst),.frame_start(rv_q&&!rv),.pixel_valid(rd&&rv),
        .x(rx),.y(ry),.edge_bit(displayed_edge),.shape(detected_shape),
        .bbox_x0(box_x0),.bbox_x1(box_x1),.bbox_y0(box_y0),.bbox_y1(box_y1),.result_tick(shape_result_tick),.observation_valid(shape_observation));
    reg oh,ov,od;
    reg [23:0] composed;
    reg [10:0] ox;
    reg [10:0] oy;
    reg [1:0] omode;
    reg oshow;
    always @(posedge clk) begin
        if(rst) begin
            rh<=1;rv<=1;rd<=0;rsobel<=0;rstrong<=0;rshow<=0;rmeta<=0;rx<=0;ry<=0;rmode<=0;rv_q<=1;
            rhistory<=0;ohistory<=0;rhistory_ui<=0;ohistory_ui<=0;oh<=1;ov<=1;od<=0;composed<=0;ox<=0;oy<=0;omode<=0;oshow<=0;
        end else begin
            rh<=ph;rv<=pv;rd<=pd;rsobel<=psobel;rstrong<=pedge;rshow<=show_map;rmeta<=pmeta;rx<=px;ry<=py;rmode<=mode;
            rv_q<=rv;rhistory<=history_frame_mode;ohistory<=rhistory;
            rhistory_ui<=history_frame_ui;ohistory_ui<=rhistory_ui;
            oh<=rh;ov<=rv;od<=rd;ox<=rx;oy<=ry;omode<=rmode;oshow<=rshow;
            if(!rd) composed<=0;
            // History preserves the native RGB supplied by the contour raster stage.
            // Only cleaned temporal-change boundaries have already turned red.
            else if(rhistory!=0) composed<=rmeta[31:8];
            else if(rx<IMG_WIDTH/2) composed<={3{rmeta[7:0]}};
            else if(displayed_edge && geometric_target_pixel) composed<=24'hffff00;
            else if(rmode[1]) composed<=displayed_edge?24'hffffff:24'h000000;
            else composed<=displayed_edge?24'hff0000:rmeta[31:8];
        end
    end
    // Coherent source identity. UI-domain payloads are stable for a display
    // frame; delayed video VS is after the store's blanking metadata update.
    (* async_reg="true" *) reg [31:0] id_meta,id_sync,cap_meta,cap_sync;
    (* async_reg="true" *) reg [5:0] bank_meta,bank_sync;
    (* async_reg="true" *) reg [2:0] event_meta,event_sync;
    reg [31:0] video_source_id,last_source_id,capture_packet;reg [5:0] video_source_bank;
    reg [31:0] completed_source_id;reg [5:0] completed_source_bank;
    reg completed_fresh;reg [1:0] video_app_mode,completed_app_mode;
    reg fresh_video,clear_seen;wire clear_pulse=clear_toggle!=clear_seen;
    reg [7:0] capture_fps,processing_fps;reg [31:0] second_count,last_capture_count;
    reg [15:0] completed_this_second,processing_ms,elapsed_ms;
    reg [31:0] millisecond_count;reg measuring;
    wire [31:0] capture_delta=capture_packet-last_capture_count;
    wire complete_task=state==COMPUTE&&map_published&&map_ready;
    always @(posedge clk)begin
      if(rst)begin
       id_meta<=0;id_sync<=0;cap_meta<=0;cap_sync<=0;bank_meta<=0;bank_sync<=0;event_meta<=0;event_sync<=0;
       video_source_id<=0;last_source_id<=0;capture_packet<=0;video_source_bank<=0;fresh_video<=0;clear_seen<=0;
       completed_source_id<=0;completed_source_bank<=0;completed_fresh<=0;video_app_mode<=0;completed_app_mode<=0;
       second_count<=0;last_capture_count<=0;capture_fps<=0;processing_fps<=0;completed_this_second<=0;
       processing_ms<=0;elapsed_ms<=0;millisecond_count<=0;measuring<=0;
      end else begin
       id_meta<=display_frame_id;id_sync<=id_meta;bank_meta<=display_bank;bank_sync<=bank_meta;
       cap_meta<=capture_count;cap_sync<=cap_meta;event_meta<=event_status;event_sync<=event_meta;
       clear_seen<=clear_toggle;
       if(pipe_frame_start)begin
        completed_source_id<=video_source_id;completed_source_bank<=video_source_bank;
        completed_fresh<=fresh_video;completed_app_mode<=video_app_mode;video_app_mode<=app_mode;
        video_source_id<=id_sync;video_source_bank<=bank_sync;capture_packet<=cap_sync;
        fresh_video<=id_sync!=last_source_id&&canny_display_valid&&history_active_mode==0;
        last_source_id<=id_sync;
       end
       if(second_count==CLK_HZ-1)begin
        second_count<=0;last_capture_count<=capture_packet;capture_fps<=capture_delta>255?8'd255:capture_delta[7:0];
        processing_fps<=completed_this_second>255?8'd255:completed_this_second[7:0];
        completed_this_second<=complete_task?1:0;
       end else begin second_count<=second_count+1'b1;if(complete_task)completed_this_second<=completed_this_second+1'b1;end
       if(map_start)begin measuring<=1;elapsed_ms<=0;millisecond_count<=0;end
       else if(measuring)begin
        if(millisecond_count>=CLK_HZ/1000-1)begin millisecond_count<=0;if(elapsed_ms!=16'hffff)elapsed_ms<=elapsed_ms+1'b1;end
        else millisecond_count<=millisecond_count+1'b1;
        if(complete_task)begin measuring<=0;processing_ms<=elapsed_ms;end
        else if(state==CANCEL||state==IDLE)measuring<=0;
       end
      end
    end
    wire face_valid,face_edge,face_result_tick,face_observation;wire [7:0] face_score;
    wire [10:0] face_x0,face_x1,face_y0,face_y1;
    wire app_frame_start=rv_q&&!rv;
    case4_face_outline #(.IMG_WIDTH(IMG_WIDTH),.IMG_HEIGHT(IMG_HEIGHT),
      .MIN_FACE_WIDTH(IMG_WIDTH>=640?48:16),.MIN_FACE_HEIGHT(IMG_HEIGHT>=480?56:20)) face_detector(
      .clk(clk),.rst_n(!rst),.clear(app_mode!=3||rhistory!=0||clear_pulse),.frame_start(app_frame_start),
      .sample_tick(app_frame_start&&fresh_video&&rshow),.pixel_valid(rd&&rv),.x(rx),.y(ry),
      .rgb(rmeta[31:8]),.edge_bit(displayed_edge),.face_valid(face_valid),
      .bbox_x0(face_x0),.bbox_x1(face_x1),.bbox_y0(face_y0),.bbox_y1(face_y1),.face_outline(face_edge),.score(face_score),
      .result_tick(face_result_tick),.observation_valid(face_observation));
    wire [10:0] target_x0=app_mode==3?face_x0:box_x0,target_x1=app_mode==3?face_x1:box_x1;
    wire [10:0] target_y0=app_mode==3?face_y0:box_y0,target_y1=app_mode==3?face_y1:box_y1;
    wire target_valid=app_mode==3?face_valid:detected_shape!=0;
    wire track_valid,trail_hit;wire [4:0] trail_age;wire [1:0] direction;
    wire [10:0] center_x,center_y;wire [15:0] count_in,count_out;
    localparam [10:0] COUNT_LINE=IMG_WIDTH*3/4;
    reg [1:0] track_app_seen,track_history_seen;
    reg [31:0] track_sample_id;reg [5:0] track_sample_bank;
    wire track_invalidate=app_mode!=track_app_seen||rhistory!=track_history_seen;
    wire track_sample=(app_mode==3?face_result_tick:shape_result_tick)&&completed_fresh&&
                      completed_app_mode==app_mode&&(app_mode==1||app_mode==3)&&rhistory==0;
    always @(posedge clk)begin
     if(rst)begin track_app_seen<=0;track_history_seen<=0;track_sample_id<=0;track_sample_bank<=0;end
     else begin
      track_app_seen<=app_mode;track_history_seen<=rhistory;
      if(track_sample)begin track_sample_id<=completed_source_id;track_sample_bank<=completed_source_bank;end
     end
    end
    case4_target_tracker #(.HYSTERESIS_PX(IMG_WIDTH>=640?12:3),.MAX_JUMP_PX(IMG_WIDTH/6)) tracker(
      .clk(clk),.rst_n(!rst),.clear(clear_pulse),.invalidate(track_invalidate),
      .sample_tick(track_sample),
      .target_valid(app_mode==3?face_observation:shape_observation),.bbox_x0(target_x0),.bbox_x1(target_x1),.bbox_y0(target_y0),.bbox_y1(target_y1),.line_x(COUNT_LINE),
      .draw_valid(od),.draw_x(ox),.draw_y(oy),.track_valid(track_valid),.center_x(center_x),.center_y(center_y),
      .direction(direction),.count_in(count_in),.count_out(count_out),.trail_hit(trail_hit),.trail_age(trail_age));
    wire [2:0] inspect_status;wire [15:0] inspect_missing,inspect_extra;
    wire inspect_event;wire [31:0] inspect_id;wire [5:0] inspect_bank;wire [1:0] inspection_overlay;
    case4_reference_inspect #(.IMG_WIDTH(IMG_WIDTH),.IMG_HEIGHT(IMG_HEIGHT)) inspector(
      .clk(clk),.rst(rst),.enable(app_mode==2&&rhistory==0),.frame_start(app_frame_start),
      .pixel_valid(rd&&rv),.edge_bit(displayed_edge),.source_valid(rshow),.x(rx),.y(ry),
      .source_id(video_source_id),.source_bank(video_source_bank),.learn_toggle(learn_toggle),
      .status(inspect_status),.missing_cells(inspect_missing),.extra_cells(inspect_extra),
      .event_pulse(inspect_event),.result_frame_id(inspect_id),.result_bank(inspect_bank),.overlay_code(inspection_overlay));
    reg [15:0] previous_in,previous_out;reg [31:0] event_flash;
    always @(posedge clk)begin
     if(rst)begin event_mark_toggle<=0;event_mark_frame_id<=0;event_mark_bank<=0;previous_in<=0;previous_out<=0;event_flash<=0;end
     else begin
      previous_in<=count_in;previous_out<=count_out;
      if(event_flash!=0)event_flash<=event_flash-1'b1;
      if(inspect_event)begin
       event_mark_toggle<=!event_mark_toggle;event_mark_frame_id<=inspect_id;event_mark_bank<=inspect_bank;event_flash<=CLK_HZ/2;
      end else if((count_in>previous_in||count_out>previous_out)&&!clear_pulse)begin
       event_mark_toggle<=!event_mark_toggle;event_mark_frame_id<=track_sample_id;event_mark_bank<=track_sample_bank;event_flash<=CLK_HZ/2;
      end
     end
    end
    // Display-only 3x3 causal stroke: the algorithm and geometry evidence use
    // the original 1-bit map. Expanding a display stroke never changes counts.
    wire dilate_valid;wire [$clog2(IMG_WIDTH)-1:0] unused_dx;wire [$clog2(IMG_HEIGHT)-1:0] unused_dy;
    wire dp00,dp01,dp02,dp10,dp11,dp12,dp20,dp21,dp22;
    case4_window3x3 #(.DATA_BITS(1),.IMG_WIDTH(IMG_WIDTH),.IMG_HEIGHT(IMG_HEIGHT)) stroke_window(
      .clk(clk),.rst(rst),.in_valid(rd&&rv),.in_x(rx[$clog2(IMG_WIDTH)-1:0]),.in_y(ry[$clog2(IMG_HEIGHT)-1:0]),.in_pixel(displayed_edge),
      .out_valid(dilate_valid),.out_x(unused_dx),.out_y(unused_dy),
      .p00(dp00),.p01(dp01),.p02(dp02),.p10(dp10),.p11(dp11),.p12(dp12),.p20(dp20),.p21(dp21),.p22(dp22));
    wire thick_bit=dilate_valid&&(dp00|dp01|dp02|dp10|dp11|dp12|dp20|dp21|dp22);
    reg o_edge;reg [23:0] o_raw;reg [7:0] o_gray;
    reg bh,bv,bd,b_edge,b_trail,b_target,app_h,app_v,app_d,app_vq;
    reg [23:0] b_rgb,b_raw,app_rgb;reg [7:0] b_gray;
    reg [10:0] bx,by,app_x,app_y;reg [1:0] b_mode,b_history;reg [4:0] b_age;
    wire render_edge=b_edge||(thick_enable&&thick_bit);
    wire track_screen=app_mode==1||app_mode==3;
    wire target_outline=target_valid&&((bx==target_x0||bx==target_x1)&&(by>=target_y0&&by<=target_y1)||
                                 (by==target_y0||by==target_y1)&&(bx>=target_x0&&bx<=target_x1));
    wire crosshair=track_valid&&((bx==center_x&&by+5>=center_y&&by<=center_y+5)||
                                 (by==center_y&&bx+5>=center_x&&bx<=center_x+5));
    wire count_line_pixel=app_mode==1&&(bx==COUNT_LINE||bx==COUNT_LINE+1)&&by[4];
    localparam integer GUIDE_MARGIN=IMG_WIDTH>=640?32:4;
    wire inspection_guide=((bx==IMG_WIDTH/2+GUIDE_MARGIN||bx==IMG_WIDTH-1-GUIDE_MARGIN)&&
                          by>=GUIDE_MARGIN&&by<IMG_HEIGHT-GUIDE_MARGIN&&by[3])||
                         ((by==GUIDE_MARGIN||by==IMG_HEIGHT-1-GUIDE_MARGIN)&&
                          bx>=IMG_WIDTH/2+GUIDE_MARGIN&&bx<IMG_WIDTH-GUIDE_MARGIN&&bx[3]);
    wire [7:0] trail_green=8'd240-{b_age,3'b000};
    always @(posedge clk)begin
      if(rst)begin
       o_edge<=0;o_raw<=0;o_gray<=0;bh<=1;bv<=1;bd<=0;b_edge<=0;b_trail<=0;b_target<=0;b_rgb<=0;b_raw<=0;b_gray<=0;
       bx<=0;by<=0;b_mode<=0;b_history<=0;b_age<=0;app_h<=1;app_v<=1;app_d<=0;app_rgb<=0;app_x<=0;app_y<=0;app_vq<=1;
      end else begin
       o_edge<=displayed_edge;o_raw<=rmeta[31:8];o_gray<=rmeta[7:0];
       bh<=oh;bv<=ov;bd<=od;b_rgb<=composed;b_raw<=o_raw;b_gray<=o_gray;bx<=ox;by<=oy;
       b_mode<=omode;b_history<=ohistory_ui;b_edge<=o_edge;b_trail<=trail_hit;b_age<=trail_age;
       b_target<=target_valid&&ox>=target_x0&&ox<=target_x1&&oy>=target_y0&&oy<=target_y1;
       app_h<=bh;app_v<=bv;app_d<=bd;app_x<=bx;app_y<=by;app_vq<=app_v;
       if(!bd)app_rgb<=0;
       else if(b_history!=0)app_rgb<=b_rgb;
       else if(bx<IMG_WIDTH/2)app_rgb<={3{b_gray}};
       else if(app_mode==2)begin
         if(inspection_overlay[1])app_rgb<=24'hff20b0;
         else if(inspection_overlay[0])app_rgb<=24'h00e8ff;
         else if(inspection_guide)app_rgb<=24'h0088ff;
         else app_rgb<=b_raw;
       end else if(track_screen&&(target_outline||crosshair))app_rgb<=24'hffff00;
       else if(track_screen&&b_trail)app_rgb<={8'd0,trail_green,8'hff};
       else if(count_line_pixel)app_rgb<=event_flash!=0?24'hffffff:24'h0088ff;
       else if(render_edge&&b_target)app_rgb<=24'hffff00;
       else if(b_mode[1])app_rgb<=render_edge?24'hffffff:0;
       else app_rgb<=render_edge?24'hff0000:b_raw;
      end
    end
    // CANCELLED keeps a still-valid mark; INVALID_SOURCE has no saved event.
    // Only an overwritten generation is reported as EXPIRED.
    wire [1:0] ui_event=event_sync==1||event_sync==5?1:event_sync==2||event_sync==3?2:event_sync==4?3:0;
    case4_demo_osd demo_osd(.clk(clk),.rst(rst),.frame_start(app_vq&&!app_v),
     .in_hs(app_h),.in_vs(app_v),.in_de(app_d),.x(app_x),.y(app_y),.in_rgb(app_rgb),
     .app_mode(app_mode),.history_mode(history_frame_ui),.history_paused(active_paused),
     .history_count(history_count),.selected_index(selected_index),.reference_index(reference_index),
     .mode(mode),.threshold(threshold),.median_enable(median_enable),.frozen(user_freeze),
     .processing(ddr_error||!foreground_valid),.auto_enable(auto_enable),.noise_level(noise_level),.thick_enable(thick_enable),
     .shape(app_mode==3?(face_valid?2'd3:2'd0):detected_shape),.inspect_status(inspect_status),
     .inspect_missing(inspect_missing),.inspect_extra(inspect_extra),.count_in(count_in),.count_out(count_out),
     .capture_fps(capture_fps),.processing_fps(processing_fps),.processing_ms(processing_ms),
     .event_status(ui_event),.menu_open(menu_open),.menu_index(menu_index),
     .out_hs(out_hs),.out_vs(out_vs),.out_de(out_de),.out_rgb(out_rgb));

endmodule
