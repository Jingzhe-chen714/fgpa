`timescale 1ns/1ps
// Native-coordinate comparison. Left is original gray; right is either
// original RGB with red edges or binary edges. No scaling and no duplication.
// V6: continuous foreground display; exact Canny runs on another pinned RGB
// frame. Publish matched RGB plus a completed DDR edge slot at vertical blank.
// Never alternate strong-edge previews with completed hysteresis results.
module case4_video_stable #(
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
    wire [10:0] threshold;
    wire [1:0] mode;
    wire median_enable,user_freeze;
    case4_history_controls #(.CLK_HZ(CLK_HZ),.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES),
        .LONG_CYCLES(LONG_CYCLES),.CHORD_CYCLES(CHORD_CYCLES)) controls(
        .clk(clk),.rst_n(!rst),.key_n(key_n),.frame_start(raw_frame_start),
        .threshold(threshold),.mode(mode),.median_enable(median_enable),.freeze_request(user_freeze),
        .history_mode(history_mode),.history_paused(history_paused),
        .step_prev_toggle(step_prev_toggle),.step_next_toggle(step_next_toggle),.reference_toggle(reference_toggle));
    wire ph,pv,pd,psobel,pedge;wire [10:0] pmagnitude;
    // Per-coordinate temporal Schmitt threshold: new edges need T, previously
    // published edges remain only while this new frame still has >=T/2 gradient.
    wire stable_sobel=pmagnitude!=0 && ((pmagnitude>=threshold) || (pedge && pmagnitude>=(threshold>>1)));
    wire [23:0] background_rgb;
    wire [31:0] pmeta;
    wire [1:0] pclass;
    case4_stable_pipeline #(.W(IMG_WIDTH),.H(IMG_HEIGHT),.HT(H_TOTAL)) pipeline(
        .clk(clk),.rst(rst),.in_hs(in_hs),.in_vs(in_vs),.in_de(in_de),.in_rgb(in_rgb),
        .median_enable(median_enable),.canny_enable(mode[0] && history_mode==0 && history_active_mode==0),.threshold(threshold),
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
    reg median_seen,canny_seen,algorithm_seen;
    wire config_changed=threshold!=threshold_seen || median_enable!=median_seen || mode[0]!=algorithm_seen;
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
    reg foreground_valid;
    wire show_map=foreground_valid;
    localparam integer ROI_WIDTH=IMG_WIDTH/2;
    localparam integer MAP_ADDR_BITS=$clog2(ROI_WIDTH*IMG_HEIGHT);
    always @(posedge clk) begin
        if(rst) begin
            proc_ack_sync<=0;pub_ack_sync<=0;proc_meta<=0;proc_sync<=0;slot_sync<=0;
            state<=IDLE;threshold_seen<=128;median_seen<=1;canny_seen<=0;algorithm_seen<=0;
            process_request_toggle<=0;process_release_toggle<=0;publish_toggle<=0;publish_slot<=1;
            held_bank<=0;reader_start<=0;foreground_valid<=0;release_wait<=0;
        end else begin
            proc_ack_sync<={proc_ack_sync[1:0],process_ack_toggle};
            pub_ack_sync<={pub_ack_sync[1:0],publish_ack_toggle};
            proc_meta<={process_valid,process_bank};proc_sync<=proc_meta;
            slot_sync<={slot_sync[0],canny_display_slot};
            threshold_seen<=threshold;median_seen<=median_enable;canny_seen<=canny_enable;algorithm_seen<=mode[0];
            reader_start<=0;
            if(pipe_frame_start) foreground_valid<=canny_enable&&canny_display_valid;
            if((!canny_enable || ddr_error || config_changed || user_freeze) && state!=IDLE && state!=CANCEL && state!=WAIT_FREE) state<=CANCEL;
            else case(state)
                IDLE: if(canny_enable&&!user_freeze&&!ddr_error&&ddr_frame_ready&&reader_idle) begin
                    process_request_toggle<=!process_request_toggle;state<=REQUEST;
                end
                REQUEST: if(proc_ack_sync[2]==process_request_toggle) begin
                    if(proc_sync[6]) begin held_bank<=proc_sync[5:0];publish_slot<=!slot_sync[1];state<=WAIT_RAW;end
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
    wire [1:0] detected_shape;
    wire [10:0] box_x0,box_x1;
    wire [10:0] box_y0,box_y1;
    wire target_pixel=(detected_shape==1 || detected_shape==2) &&
        rx>=box_x0 && rx<=box_x1 && ry>=box_y0 && ry<=box_y1;
    case4_shape_candidates #(.IMG_WIDTH(IMG_WIDTH),.IMG_HEIGHT(IMG_HEIGHT)) detector(
        .clk(clk),.rst_n(!rst),.frame_start(rv_q&&!rv),.pixel_valid(rd&&rv),
        .x(rx),.y(ry),.edge_bit(displayed_edge),.shape(detected_shape),
        .bbox_x0(box_x0),.bbox_x1(box_x1),.bbox_y0(box_y0),.bbox_y1(box_y1));
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
            else if(displayed_edge && target_pixel) composed<=24'hffff00;
            else if(rmode[1]) composed<=displayed_edge?24'hffffff:24'h000000;
            else composed<=displayed_edge?24'hff0000:rmeta[31:8];
        end
    end
    wire core_hs,core_vs,core_de;
    wire [23:0] core_rgb;
    wire [10:0] osd_x=ohistory_ui==0?ox:11'd0;
    generate if(PIPE_OSD) begin:g_pipelined_osd
    case4_osd_pipeline osd(.clk(clk),.rst(rst),.in_hs(oh),.in_vs(ov),
        .out_hs(core_hs),.out_vs(core_vs),.out_de(core_de),.x(osd_x),.y(oy),.in_rgb(composed),.in_de(od),.threshold(threshold),
        .mode(omode),.median_enable(median_enable),.frozen(user_freeze),
        .processing(ddr_error||(omode[0]&&!oshow)),
        .shape(ddr_error?2'd0:detected_shape),.out_rgb(core_rgb));
    end else begin:g_combinational_osd
    assign core_hs=oh;assign core_vs=ov;assign core_de=od;
    case4_osd osd(.x(osd_x),.y(oy),.in_rgb(composed),.in_de(od),.threshold(threshold),
        .mode(omode),.median_enable(median_enable),.frozen(user_freeze),
        .processing(ddr_error||(omode[0]&&!oshow)),
        .shape(ddr_error?2'd0:detected_shape),.out_rgb(core_rgb));
    end endgenerate
    wire [X_BITS-1:0] hx;
    wire [Y_BITS-1:0] hy;
    case4_raster_xy #(.W(IMG_WIDTH),.H(IMG_HEIGHT)) history_coordinates(clk,rst,core_vs,core_de,hx,hy);
    reg [1:0] history_delay[0:6];
    integer hd;
    always @(posedge clk) begin
        if(rst) for(hd=0;hd<7;hd=hd+1) history_delay[hd]<=0;
        else begin history_delay[0]<=ohistory_ui;for(hd=1;hd<7;hd=hd+1) history_delay[hd]<=history_delay[hd-1];end
    end
    case4_contour_osd history_osd(.clk(clk),.rst(rst),.in_hs(core_hs),.in_vs(core_vs),.in_de(core_de),
        .x(hx),.y(hy),.in_rgb(core_rgb),.history_mode(PIPE_OSD?history_delay[6]:ohistory_ui),
        .ready(history_ready),.paused(active_paused),.count(history_count),
        .selected(selected_index),.reference(reference_index),.threshold(8'd32),
        .out_hs(out_hs),.out_vs(out_vs),.out_de(out_de),.out_rgb(out_rgb));
endmodule
