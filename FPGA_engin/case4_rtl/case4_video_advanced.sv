`timescale 1ns/1ps
// Native-coordinate comparison. Left is original gray; right is either
// original RGB with red edges or binary edges. No scaling and no duplication.
// Sobel runs continuously. Canny holds the source DDR frame while its complete
// right-hand ROI is captured and hysteresis converges; a map is published only
// at vertical blanking. While busy, display NMS strong-edge previews using the
// requested red/binary style. A user resume always releases the old snapshot.
module case4_video_advanced #(
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
    output wire freeze_request,
    output wire out_hs,out_vs,out_de,
    output wire [23:0] out_rgb,
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
    case4_controls #(.CLK_HZ(CLK_HZ),.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES),
        .LONG_CYCLES(LONG_CYCLES),.CHORD_CYCLES(CHORD_CYCLES)) controls(
        .clk(clk),.rst_n(!rst),.key_n(key_n),.frame_start(raw_frame_start),
        .threshold(threshold),.mode(mode),.median_enable(median_enable),.freeze_request(user_freeze));
    wire ph,pv,pd,psobel;
    wire [31:0] pmeta;
    wire [1:0] pclass;
    case4_advanced_pipeline #(.W(IMG_WIDTH),.H(IMG_HEIGHT),.HT(H_TOTAL)) pipeline(
        .clk(clk),.rst(rst),.in_hs(in_hs),.in_vs(in_vs),.in_de(in_de),.in_rgb(in_rgb),
        .median_enable(median_enable),.canny_enable(mode[0]),.threshold(threshold),
        .out_hs(ph),.out_vs(pv),.out_de(pd),.out_meta(pmeta),.out_sobel(psobel),.out_class(pclass));
    wire [X_BITS-1:0] px;
    wire [Y_BITS-1:0] py;
    case4_raster_xy #(.W(IMG_WIDTH),.H(IMG_HEIGHT)) coordinates(clk,rst,pv,pd,px,py);
    wire pipe_frame_start=pipe_vs_q&&!pv;
    always @(posedge clk) begin
        if(rst) begin raw_vs_q<=1;pipe_vs_q<=1;user_freeze_q<=0;end
        else begin raw_vs_q<=in_vs;pipe_vs_q<=pv;user_freeze_q<=user_freeze;end
    end

    localparam [3:0] IDLE=0,LOCK=1,WAIT_FRAME=2,LOAD=3,COMPUTE=4,
        WAIT_SHOW=5,SHOW=6,RELEASE=7;
    reg [3:0] state;
    reg [1:0] shown_frames,released_frames;
    reg [10:0] threshold_seen;
    reg median_seen;
    reg [1:0] mode_seen;
    wire config_changed=threshold!=threshold_seen || median_enable!=median_seen || mode!=mode_seen;
    wire user_resume=user_freeze_q && !user_freeze;
    wire auto_hold=mode[0] && state!=IDLE && state!=RELEASE && !ddr_error && !user_resume;
    assign freeze_request=user_freeze||auto_hold;
    wire map_busy,map_ready,map_fault,map_edge;
    wire [15:0] sweeps;
    wire map_abort=rst || !mode[0] || ddr_error || config_changed || user_resume ||
                   state==IDLE || state==LOCK || state==RELEASE;
    wire map_start=state==WAIT_FRAME && pipe_frame_start && ddr_frozen && ddr_frame_ready && !map_abort;
    wire roi_valid=pd && pv && px>=IMG_WIDTH/2;
    wire roi_last=px==IMG_WIDTH-1 && py==IMG_HEIGHT-1;
    wire show_map=state==SHOW && map_ready && !map_fault && !map_abort && ddr_frozen && ddr_frame_ready;
    localparam integer ROI_WIDTH=IMG_WIDTH/2;
    localparam integer MAP_ADDR_BITS=$clog2(ROI_WIDTH*IMG_HEIGHT);
    wire [MAP_ADDR_BITS-1:0] map_addr=py*ROI_WIDTH+(px-ROI_WIDTH);
    generate if(EXTERNAL_WEAK) begin:g_external
    case4_hysteresis_ddr #(.WIDTH(ROI_WIDTH),.HEIGHT(IMG_HEIGHT)) hysteresis(
        .clk(clk),.rst_n(!rst),.abort(map_abort),
        .load_start(map_start),.load_valid(state==LOAD && roi_valid),.load_last(roi_last),.load_state(pclass),
        .busy(map_busy),.ready(map_ready),.fault(map_fault),.changed_sweeps(sweeps),
        .rd_en(show_map&&roi_valid),.rd_addr(map_addr),.rd_edge(map_edge),
        .axiclk(axiclk),.axirst(axirst),
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
    end else begin:g_internal
    case4_hysteresis #(.WIDTH(ROI_WIDTH),.HEIGHT(IMG_HEIGHT)) hysteresis(
        .clk(clk),.rst_n(!rst),.abort(map_abort),
        .load_start(map_start),.load_valid(state==LOAD && roi_valid),.load_last(roi_last),.load_state(pclass),
        .busy(map_busy),.ready(map_ready),.fault(map_fault),.changed_sweeps(sweeps),
        .rd_en(show_map&&roi_valid),.rd_addr(map_addr),.rd_edge(map_edge));
        assign m_awaddr=32'd0;
        assign m_awlen=8'd0;
        assign m_awvalid=1'd0;
        assign m_wdata=128'd0;
        assign m_wstrb=16'd0;
        assign m_wlast=1'd0;
        assign m_wvalid=1'd0;
        assign m_bready=1'd0;
        assign m_araddr=32'd0;
        assign m_arlen=8'd0;
        assign m_arvalid=1'd0;
        assign m_rready=1'd0;
    end endgenerate
    always @(posedge clk) begin
        if(rst) begin
            state<=IDLE;shown_frames<=0;released_frames<=0;
            threshold_seen<=128;mode_seen<=0;median_seen<=1;
        end else begin
            threshold_seen<=threshold;mode_seen<=mode;median_seen<=median_enable;
            if(!mode[0] || ddr_error) begin
                state<=IDLE;shown_frames<=0;released_frames<=0;
            end else if(user_resume) begin
                // Manual resume must win over the Canny engine's internal
                // freeze, even in LOAD/COMPUTE or before the map is ready.
                state<=RELEASE;shown_frames<=0;released_frames<=0;
            end else if((config_changed || map_fault) && state!=RELEASE) begin
                state<=LOCK;shown_frames<=0;released_frames<=0;
            end else begin
                case(state)
                    IDLE: state<=LOCK;
                    LOCK: if(ddr_frozen&&ddr_frame_ready) state<=WAIT_FRAME;
                    WAIT_FRAME: begin
                        if(!ddr_frozen || !ddr_frame_ready) state<=LOCK;
                        else if(pipe_frame_start) state<=LOAD;
                    end
                    LOAD: begin
                        if(!ddr_frozen || !ddr_frame_ready) state<=LOCK;
                        else if(roi_valid&&roi_last) state<=COMPUTE;
                    end
                    COMPUTE: begin
                        if(!ddr_frozen || !ddr_frame_ready) state<=LOCK;
                        else if(map_ready) state<=WAIT_SHOW;
                    end
                    WAIT_SHOW: begin
                        if(!ddr_frozen || !ddr_frame_ready) state<=LOCK;
                        else if(pipe_frame_start) begin state<=SHOW;shown_frames<=0;end
                    end
                    SHOW: begin
                        if(!ddr_frozen || !ddr_frame_ready) state<=LOCK;
                        else if(pipe_frame_start) begin
                            // Detector needs two stable edge frames; retain a
                            // third complete frame to make its result visible.
                            if(shown_frames<3) shown_frames<=shown_frames+1'b1;
                            if(shown_frames>=2 && !user_freeze) begin
                                state<=RELEASE;released_frames<=0;
                            end
                        end
                    end
                    RELEASE: begin
                        if(raw_frame_start && released_frames<2) released_frames<=released_frames+1'b1;
                        if(user_freeze || (released_frames>=2 && !ddr_frozen)) state<=LOCK;
                    end
                    default: state<=IDLE;
                endcase
            end
        end
    end

    // The synchronous map read and this metadata register refer to the same
    // source pixel. Both Sobel and Canny then use the same output register.
    reg rh,rv,rd,rsobel,rstrong,rshow;
    reg [31:0] rmeta;
    reg [10:0] rx;
    reg [10:0] ry;
    reg [1:0] rmode;
    wire displayed_edge=rmode[0] ? (rshow ? map_edge : rstrong) : rsobel;
    reg rv_q;
    wire [1:0] detected_shape;
    wire [10:0] box_x0,box_x1;
    wire [10:0] box_y0,box_y1;
    wire target_pixel=(detected_shape==1 || detected_shape==2) &&
        rx>=box_x0 && rx<=box_x1 && ry>=box_y0 && ry<=box_y1;
    case4_shape_detect #(.IMG_WIDTH(IMG_WIDTH),.IMG_HEIGHT(IMG_HEIGHT)) detector(
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
            oh<=1;ov<=1;od<=0;composed<=0;ox<=0;oy<=0;omode<=0;oshow<=0;
        end else begin
            rh<=ph;rv<=pv;rd<=pd;rsobel<=psobel;rstrong<=pclass[1];rshow<=show_map;rmeta<=pmeta;rx<=px;ry<=py;rmode<=mode;
            rv_q<=rv;
            oh<=rh;ov<=rv;od<=rd;ox<=rx;oy<=ry;omode<=rmode;oshow<=rshow;
            if(!rd) composed<=0;
            else if(rx<IMG_WIDTH/2) composed<={3{rmeta[7:0]}};
            else if(displayed_edge && target_pixel) composed<=24'hffff00;
            else if(rmode[1]) composed<=displayed_edge?24'hffffff:24'h000000;
            else composed<=displayed_edge?24'hff0000:rmeta[31:8];
        end
    end
    generate if(PIPE_OSD) begin:g_pipelined_osd
    case4_osd_pipeline osd(.clk(clk),.rst(rst),.in_hs(oh),.in_vs(ov),
        .out_hs(out_hs),.out_vs(out_vs),.out_de(out_de),.x(ox),.y(oy),.in_rgb(composed),.in_de(od),.threshold(threshold),
        .mode(omode),.median_enable(median_enable),.frozen(user_freeze),
        .processing(ddr_error||(omode[0]&&!oshow)),
        .shape(ddr_error?2'd0:detected_shape),.out_rgb(out_rgb));
    end else begin:g_combinational_osd
    assign out_hs=oh;assign out_vs=ov;assign out_de=od;
    case4_osd osd(.x(ox),.y(oy),.in_rgb(composed),.in_de(od),.threshold(threshold),
        .mode(omode),.median_enable(median_enable),.frozen(user_freeze),
        .processing(ddr_error||(omode[0]&&!oshow)),
        .shape(ddr_error?2'd0:detected_shape),.out_rgb(out_rgb));
    end endgenerate
endmodule
