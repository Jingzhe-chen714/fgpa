`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// c2_renderer_system
// -----------------------------------------------------------------------------
// Board-independent system framework for Case 2.  It is intentionally a
// wrapper, not a board top: either direct CSR pins or an AXI4-Lite slave drive
// the command bridge; render/display traffic is arbitrated and converted into
// a width-packed AXI4 Full master; the abstract video stream terminates at an
// optional HDMI/video-PHY blackbox.
//
// USE_EXT_MEM_IP=1 exposes the AXI4 Full master for a generated DDR3 IP.
// USE_AXI4LITE_CSR=1 selects the Sapphire-facing control port.  With all IP
// selects at zero the module remains fully simulatable using the direct CSR
// port, render_owner_mem_model and the supplied clock.
// -----------------------------------------------------------------------------
module c2_renderer_system #(
    parameter int ADDR_W             = 32,
    parameter int DATA_W             = 16,
    parameter int LEN_W              = 16,
    parameter int AXI_DATA_W         = 128,
    parameter int AXI_ID_W           = 4,
    parameter int PAGE_W             = 1,
    parameter int CMD_FIFO_DEPTH     = 8,
    parameter int MAX_BURST_BEATS    = 16,
    parameter bit WRITE_BURST_ENABLE  = 1'b1,
    parameter bit READ_BURST_ENABLE   = 1'b1,
    parameter int MAX_READ_BEATS     = 16,
    parameter int MAX_WRITE_BEATS    = 16,
    parameter int LINE_BUFFER_PIXELS = 4096,
    parameter int READ_BOUNDARY_BYTES = 4096,
    parameter int WRITE_BOUNDARY_BYTES = 4096,
    parameter int LINE_FIFO_DEPTH    = 1024,
    parameter int H_ACTIVE           = 640,
    parameter int H_FRONT            = 16,
    parameter int H_SYNC             = 96,
    parameter int H_BACK             = 48,
    parameter int V_ACTIVE           = 480,
    parameter int V_FRONT            = 10,
    parameter int V_SYNC             = 2,
    parameter int V_BACK             = 33,
    parameter int FB_STRIDE_BYTES    = H_ACTIVE * (DATA_W/8),
    parameter int PAGE_BYTES         = FB_STRIDE_BYTES * V_ACTIVE,
    parameter int PAGE0_BASE         = 0,
    parameter int PAGE1_BASE         = PAGE0_BASE + PAGE_BYTES,
    parameter int MEM_BYTES          = (PAGE_W == 1) ?
                                       (PAGE1_BASE + PAGE_BYTES) :
                                       (PAGE0_BASE +
                                        ((1 << PAGE_W) * PAGE_BYTES)),
    parameter bit USE_AXI4LITE_CSR   = 1'b0,
    parameter bit USE_EXT_MEM_IP     = 1'b0,
    parameter bit USE_VIDEO_PHY_IP   = 1'b0,
    parameter bit USE_CLOCK_RESET_IP = 1'b0
) (
    input  logic                     clk_in,
    input  logic                     rst_n_in,

    // Direct CSR side for compact XSIM.  The competition configuration uses
    // the AXI4-Lite port below instead.
    input  logic                     csr_valid,
    input  logic                     csr_write,
    input  logic [11:0]              csr_addr,
    input  logic [31:0]              csr_wdata,
    output logic [31:0]              csr_rdata,
    output logic                     csr_ready,

    // Optional Sapphire-facing AXI4-Lite slave.  Set USE_AXI4LITE_CSR=1 to
    // select it; the legacy csr_* pins remain available for direct XSIM.
    input  logic [11:0]              s_axi_csr_awaddr,
    input  logic [2:0]               s_axi_csr_awprot,
    input  logic                     s_axi_csr_awvalid,
    output logic                     s_axi_csr_awready,
    input  logic [31:0]              s_axi_csr_wdata,
    input  logic [3:0]               s_axi_csr_wstrb,
    input  logic                     s_axi_csr_wvalid,
    output logic                     s_axi_csr_wready,
    output logic [1:0]               s_axi_csr_bresp,
    output logic                     s_axi_csr_bvalid,
    input  logic                     s_axi_csr_bready,
    input  logic [11:0]              s_axi_csr_araddr,
    input  logic [2:0]               s_axi_csr_arprot,
    input  logic                     s_axi_csr_arvalid,
    output logic                     s_axi_csr_arready,
    output logic [31:0]              s_axi_csr_rdata,
    output logic [1:0]               s_axi_csr_rresp,
    output logic                     s_axi_csr_rvalid,
    input  logic                     s_axi_csr_rready,

    // AXI4 Full master for the generated DDR3 controller.  These pins are
    // active only when USE_EXT_MEM_IP=1; the behavioral-memory branch drives
    // benign constants so the same top remains convenient for XSIM.
    input  logic                     ext_mem_init_done,
    input  logic                     ext_mem_init_error,
    output logic [AXI_ID_W-1:0]      m_axi_awid,
    output logic [ADDR_W-1:0]        m_axi_awaddr,
    output logic [7:0]               m_axi_awlen,
    output logic [2:0]               m_axi_awsize,
    output logic [1:0]               m_axi_awburst,
    output logic                     m_axi_awlock,
    output logic [3:0]               m_axi_awcache,
    output logic [2:0]               m_axi_awprot,
    output logic [3:0]               m_axi_awqos,
    output logic                     m_axi_awvalid,
    input  logic                     m_axi_awready,
    output logic [AXI_DATA_W-1:0]    m_axi_wdata,
    output logic [(AXI_DATA_W/8)-1:0] m_axi_wstrb,
    output logic                     m_axi_wlast,
    output logic                     m_axi_wvalid,
    input  logic                     m_axi_wready,
    input  logic [AXI_ID_W-1:0]      m_axi_bid,
    input  logic [1:0]               m_axi_bresp,
    input  logic                     m_axi_bvalid,
    output logic                     m_axi_bready,
    output logic [AXI_ID_W-1:0]      m_axi_arid,
    output logic [ADDR_W-1:0]        m_axi_araddr,
    output logic [7:0]               m_axi_arlen,
    output logic [2:0]               m_axi_arsize,
    output logic [1:0]               m_axi_arburst,
    output logic                     m_axi_arlock,
    output logic [3:0]               m_axi_arcache,
    output logic [2:0]               m_axi_arprot,
    output logic [3:0]               m_axi_arqos,
    output logic                     m_axi_arvalid,
    input  logic                     m_axi_arready,
    input  logic [AXI_ID_W-1:0]      m_axi_rid,
    input  logic [AXI_DATA_W-1:0]    m_axi_rdata,
    input  logic [1:0]               m_axi_rresp,
    input  logic                     m_axi_rlast,
    input  logic                     m_axi_rvalid,
    output logic                     m_axi_rready,

    // Abstract video output.  When USE_VIDEO_PHY_IP=0 these are directly
    // observable in XSIM; when it is 1 they are driven by the PHY blackbox.
    output logic                     video_clk,
    output logic                     video_valid,
    output logic [DATA_W-1:0]        video_data,
    output logic                     video_de,
    output logic                     video_hsync,
    output logic                     video_vsync,
    output logic                     video_init_done,
    output logic                     video_init_error,

    output logic                     clock_locked,
    output logic                     mem_init_done,
    output logic                     mem_init_error,
    output logic                     system_busy,
    output logic                     system_error,
    output logic [PAGE_W-1:0]        active_page,
    output logic [PAGE_W-1:0]        pending_page,
    output logic                     page_flip_pending,
    output logic                     display_underflow,
    output logic [31:0]              command_submit_count,
    output logic [31:0]              command_completed_count
);

    localparam int FIFO_CNT_W = (CMD_FIFO_DEPTH <= 1) ? 1 :
                                $clog2(CMD_FIFO_DEPTH + 1);
    localparam int TIMING_X_W = (H_ACTIVE <= 1) ? 1 : $clog2(H_ACTIVE);
    localparam int TIMING_Y_W = (V_ACTIVE <= 1) ? 1 : $clog2(V_ACTIVE);
    localparam logic [15:0] H_ACTIVE_C = H_ACTIVE;
    localparam logic [15:0] V_ACTIVE_C = V_ACTIVE;
    localparam logic [ADDR_W-1:0] FB_STRIDE_C = FB_STRIDE_BYTES;

    logic clk_sys, clk_pix, rst_sys_n, rst_pix_n;
    logic clock_ip_locked;

    generate
        if (USE_CLOCK_RESET_IP) begin : g_clock_ip
            c2_clock_reset_blackbox u_clock_reset (
                .clk_in, .rst_n_in, .clk_sys, .clk_pix,
                .rst_sys_n, .rst_pix_n, .locked(clock_ip_locked)
            );
        end else begin : g_clock_sim
            assign clk_sys = clk_in;
            assign clk_pix = clk_in;
            assign rst_sys_n = rst_n_in;
            assign rst_pix_n = rst_n_in;
            assign clock_ip_locked = 1'b1;
        end
    endgenerate
    assign clock_locked = clock_ip_locked;

    // ------------------------------------------------------------------ CSR
    logic csr_cmd_valid, csr_cmd_ready;
    logic [255:0] csr_cmd_data;
    logic csr_page_valid, csr_page_ready;
    logic [PAGE_W-1:0] csr_page;
    logic page_pix_req_valid, page_pix_req_ready;
    logic [PAGE_W-1:0] page_pix_req_page;
    logic [PAGE_W-1:0] active_page_pix, pending_page_pix;
    logic page_flip_pending_pix;
    logic [15:0] csr_fifo_level;
    logic parser_busy, engine_busy, display_busy;
    logic display_error_status;
    logic mem_error_status;
    logic parser_error_valid;
    logic [3:0] parser_error_code;
    logic [31:0] parser_error_seq;
    logic [31:0] parser_accepted_count;
    logic [31:0] parser_completed_count;
    logic [31:0] parser_mem_error_count;
    logic [31:0] parser_dropped_count;
    logic [31:0] fifo_drop_count;
    logic [31:0] engine_request_count, engine_pixel_count;
    logic [31:0] display_pixel_count, display_error_count;
    logic [31:0] mem_read_count, mem_write_count, mem_response_count;
    logic [31:0] csr_submit_count, csr_page_submit_count;

    // ---------------------------------------------------------------- command
    logic fifo_in_valid, fifo_in_ready;
    logic [255:0] fifo_in_data;
    logic fifo_out_valid, fifo_out_ready;
    logic [255:0] fifo_out_data;
    logic [FIFO_CNT_W-1:0] fifo_count;
    logic fifo_full, fifo_empty, fifo_drop_event;
    logic [31:0] fifo_push_count, fifo_pop_count;

    logic parser_desc_valid, parser_desc_ready;
    logic [255:0] parser_desc_raw;
    logic [31:0] parser_desc_seq;
    logic [2:0] parser_desc_op;
    logic [7:0] parser_desc_flags;
    logic [1:0] parser_desc_fmt;
    logic [31:0] parser_desc_src_addr, parser_desc_dst_addr;
    logic [15:0] parser_desc_width, parser_desc_height;
    logic [15:0] parser_desc_src_stride, parser_desc_dst_stride;
    logic [31:0] parser_desc_color;
    logic [7:0] parser_desc_alpha;
    logic [15:0] parser_desc_key;
    logic parser_accept_event;

    logic engine_done_valid, engine_done_error;
    logic [31:0] engine_done_seq;
    logic engine_done_error_status;
    logic [31:0] engine_error_count;

    logic csr_valid_i, csr_write_i;
    logic [11:0] csr_addr_i;
    logic [31:0] csr_wdata_i, csr_rdata_i;
    logic csr_ready_i;

    generate
        if (USE_AXI4LITE_CSR) begin : g_csr_axi4lite
            c2_axi4lite_csr_adapter #(.ADDR_W(12), .DATA_W(32))
            u_axi4lite_csr (
                .clk(clk_sys), .rst_n(rst_sys_n),
                .s_axi_awaddr(s_axi_csr_awaddr),
                .s_axi_awprot(s_axi_csr_awprot),
                .s_axi_awvalid(s_axi_csr_awvalid),
                .s_axi_awready(s_axi_csr_awready),
                .s_axi_wdata(s_axi_csr_wdata),
                .s_axi_wstrb(s_axi_csr_wstrb),
                .s_axi_wvalid(s_axi_csr_wvalid),
                .s_axi_wready(s_axi_csr_wready),
                .s_axi_bresp(s_axi_csr_bresp),
                .s_axi_bvalid(s_axi_csr_bvalid),
                .s_axi_bready(s_axi_csr_bready),
                .s_axi_araddr(s_axi_csr_araddr),
                .s_axi_arprot(s_axi_csr_arprot),
                .s_axi_arvalid(s_axi_csr_arvalid),
                .s_axi_arready(s_axi_csr_arready),
                .s_axi_rdata(s_axi_csr_rdata),
                .s_axi_rresp(s_axi_csr_rresp),
                .s_axi_rvalid(s_axi_csr_rvalid),
                .s_axi_rready(s_axi_csr_rready),
                .csr_valid(csr_valid_i), .csr_write(csr_write_i),
                .csr_addr(csr_addr_i), .csr_wdata(csr_wdata_i),
                .csr_rdata(csr_rdata_i), .csr_ready(csr_ready_i)
            );
        end else begin : g_csr_direct
            assign csr_valid_i = csr_valid;
            assign csr_write_i = csr_write;
            assign csr_addr_i = csr_addr;
            assign csr_wdata_i = csr_wdata;
            assign s_axi_csr_awready = 1'b0;
            assign s_axi_csr_wready = 1'b0;
            assign s_axi_csr_bresp = 2'b00;
            assign s_axi_csr_bvalid = 1'b0;
            assign s_axi_csr_arready = 1'b0;
            assign s_axi_csr_rdata = 32'd0;
            assign s_axi_csr_rresp = 2'b00;
            assign s_axi_csr_rvalid = 1'b0;
        end
    endgenerate
    assign csr_rdata = csr_rdata_i;
    assign csr_ready = csr_ready_i;

    c2_csr_cmd_bridge #(.CMD_W(256), .ADDR_W(12), .PAGE_W(PAGE_W)) u_csr (
        .clk(clk_sys), .rst_n(rst_sys_n),
        .csr_valid(csr_valid_i), .csr_write(csr_write_i),
        .csr_addr(csr_addr_i), .csr_wdata(csr_wdata_i),
        .csr_rdata(csr_rdata_i), .csr_ready(csr_ready_i),
        .cmd_valid(csr_cmd_valid), .cmd_ready(csr_cmd_ready),
        .cmd_data(csr_cmd_data),
        .page_req_valid(csr_page_valid), .page_req_ready(csr_page_ready),
        .page_req_page(csr_page),
        .cmd_fifo_full(fifo_full), .cmd_fifo_level(csr_fifo_level),
        .parser_busy, .engine_busy, .display_busy,
        .display_underflow, .mem_error(mem_error_status),
        .page_flip_pending, .active_page, .pending_page,
        .accepted_count(parser_accepted_count),
        .completed_count(parser_completed_count),
        .parser_memory_error_count(parser_mem_error_count),
        .dropped_count(parser_dropped_count + fifo_drop_count),
        .engine_request_count, .engine_pixel_count,
        .display_pixel_count, .display_error_count,
        .mem_read_count, .mem_write_count, .mem_response_count,
        .parser_error_valid, .parser_error_code, .parser_error_seq,
        .submit_count(csr_submit_count), .page_submit_count(csr_page_submit_count)
    );
    assign command_submit_count = csr_submit_count;
    assign command_completed_count = parser_completed_count;
    assign fifo_in_valid = csr_cmd_valid;
    assign fifo_in_data  = csr_cmd_data;
    assign csr_cmd_ready = fifo_in_ready;

    render_cmd_fifo #(.CMD_W(256), .DEPTH(CMD_FIFO_DEPTH)) u_cmd_fifo (
        .clk(clk_sys), .rst_n(rst_sys_n),
        .in_valid(fifo_in_valid), .in_ready(fifo_in_ready), .in_data(fifo_in_data),
        .out_valid(fifo_out_valid), .out_ready(fifo_out_ready),
        .out_data(fifo_out_data), .fifo_count(fifo_count), .full(fifo_full),
        .empty(fifo_empty), .drop_event(fifo_drop_event),
        .push_count(fifo_push_count), .pop_count(fifo_pop_count),
        .drop_count(fifo_drop_count)
    );
    assign csr_fifo_level = fifo_count;

    render_cmd_parser #(.CMD_W(256), .SEQ_W(32)) u_parser (
        .clk(clk_sys), .rst_n(rst_sys_n),
        .cmd_valid(fifo_out_valid), .cmd_ready(fifo_out_ready),
        .cmd_data(fifo_out_data),
        .desc_valid(parser_desc_valid), .desc_ready(parser_desc_ready),
        .desc_raw(parser_desc_raw), .desc_seq(parser_desc_seq),
        .desc_op(parser_desc_op), .desc_flags(parser_desc_flags),
        .desc_pixel_fmt(parser_desc_fmt), .desc_src_addr(parser_desc_src_addr),
        .desc_dst_addr(parser_desc_dst_addr), .desc_width(parser_desc_width),
        .desc_height(parser_desc_height),
        .desc_src_stride_bytes(parser_desc_src_stride),
        .desc_dst_stride_bytes(parser_desc_dst_stride),
        .desc_color(parser_desc_color), .desc_alpha(parser_desc_alpha),
        .desc_color_key(parser_desc_key), .accept_event(parser_accept_event),
        .error_valid(parser_error_valid), .error_code(parser_error_code),
        .error_seq(parser_error_seq), .done_valid(engine_done_valid),
        .done_error(engine_done_error),
        .accepted_count(parser_accepted_count),
        .completed_count(parser_completed_count),
        .memory_error_count(parser_mem_error_count),
        .dropped_count(parser_dropped_count), .busy(parser_busy)
    );

    // -------------------------------------------------------------- memory m0
    logic m0_req_valid, m0_req_ready, m0_req_write;
    logic [ADDR_W-1:0] m0_req_addr;
    logic [LEN_W-1:0] m0_req_len;
    logic [DATA_W-1:0] m0_req_wdata;
    logic [(DATA_W/8)-1:0] m0_req_wstrb;
    logic m0_rsp_valid, m0_rsp_ready;
    logic [DATA_W-1:0] m0_rsp_rdata;
    logic m0_rsp_last, m0_rsp_error;
    logic m0_wr_valid, m0_wr_ready;
    logic [DATA_W-1:0] m0_wr_data;
    logic [(DATA_W/8)-1:0] m0_wr_strb;
    logic m0_wr_last, m0_wr_error;
    logic m0_wr_rsp_valid, m0_wr_rsp_ready, m0_wr_rsp_error;

    render_cmd_mem_engine #(
        .ADDR_W(ADDR_W), .DATA_W(DATA_W), .LEN_W(LEN_W), .SEQ_W(32),
        .WRITE_BURST_ENABLE(WRITE_BURST_ENABLE),
        .READ_BURST_ENABLE(READ_BURST_ENABLE),
        .MAX_READ_BEATS(MAX_READ_BEATS),
        .MAX_WRITE_BEATS(MAX_WRITE_BEATS),
        .LINE_BUFFER_PIXELS(LINE_BUFFER_PIXELS),
        .READ_BOUNDARY_BYTES(READ_BOUNDARY_BYTES),
        .WRITE_BOUNDARY_BYTES(WRITE_BOUNDARY_BYTES)
    ) u_engine (
        .clk(clk_sys), .rst_n(rst_sys_n),
        .desc_valid(parser_desc_valid), .desc_ready(parser_desc_ready),
        .desc_seq(parser_desc_seq), .desc_op(parser_desc_op),
        .desc_flags(parser_desc_flags), .desc_pixel_fmt(parser_desc_fmt),
        .desc_src_addr(parser_desc_src_addr), .desc_dst_addr(parser_desc_dst_addr),
        .desc_width(parser_desc_width), .desc_height(parser_desc_height),
        .desc_src_stride_bytes(parser_desc_src_stride),
        .desc_dst_stride_bytes(parser_desc_dst_stride),
        .desc_color(parser_desc_color), .desc_alpha(parser_desc_alpha),
        .desc_color_key(parser_desc_key),
        .mem_req_valid(m0_req_valid), .mem_req_ready(m0_req_ready),
        .mem_req_write(m0_req_write), .mem_req_addr(m0_req_addr),
        .mem_req_len(m0_req_len), .mem_req_wdata(m0_req_wdata),
        .mem_req_wstrb(m0_req_wstrb), .mem_rsp_valid(m0_rsp_valid),
        .mem_rsp_ready(m0_rsp_ready), .mem_rsp_rdata(m0_rsp_rdata),
        .mem_rsp_last(m0_rsp_last), .mem_rsp_error(m0_rsp_error),
        .mem_wr_valid(m0_wr_valid), .mem_wr_ready(m0_wr_ready),
        .mem_wr_data(m0_wr_data), .mem_wr_strb(m0_wr_strb),
        .mem_wr_last(m0_wr_last), .mem_wr_error(m0_wr_error),
        .mem_wr_rsp_valid(m0_wr_rsp_valid),
        .mem_wr_rsp_ready(m0_wr_rsp_ready),
        .mem_wr_rsp_error(m0_wr_rsp_error),
        .done_valid(engine_done_valid), .done_error(engine_done_error),
        .done_seq(engine_done_seq), .busy(engine_busy),
        .request_count(engine_request_count), .read_count(), .write_count(),
        .pixel_count(engine_pixel_count), .error_count(engine_error_count)
    );

    // -------------------------------------------------------------- timing/page
    logic [TIMING_X_W-1:0] timing_pixel_x;
    logic [TIMING_Y_W-1:0] timing_pixel_y;
    logic timing_de, timing_active, timing_hsync, timing_vsync;
    logic timing_hblank, timing_vblank, timing_frame_start, timing_frame_end;
    logic timing_vblank_start, timing_prefetch_start;
    logic timing_line_start, timing_line_end, timing_vsync_start, timing_vsync_end;
    logic [((H_ACTIVE + H_FRONT + H_SYNC + H_BACK <= 1) ? 1 :
           $clog2(H_ACTIVE + H_FRONT + H_SYNC + H_BACK))-1:0] timing_h_count;
    logic [((V_ACTIVE + V_FRONT + V_SYNC + V_BACK <= 1) ? 1 :
           $clog2(V_ACTIVE + V_FRONT + V_SYNC + V_BACK))-1:0] timing_v_count;
    logic csr_page_flip_ack, csr_page_error;
    logic [ADDR_W-1:0] display_base_addr;

    c2_video_timing_gen #(
        .H_ACTIVE(H_ACTIVE), .H_FRONT(H_FRONT), .H_SYNC(H_SYNC), .H_BACK(H_BACK),
        .V_ACTIVE(V_ACTIVE), .V_FRONT(V_FRONT), .V_SYNC(V_SYNC), .V_BACK(V_BACK)
    ) u_timing (
        .clk(clk_pix), .rst_n(rst_pix_n), .h_count(timing_h_count),
        .v_count(timing_v_count), .pixel_x(timing_pixel_x),
        .pixel_y(timing_pixel_y), .de(timing_de), .active_video(timing_active),
        .hsync(timing_hsync), .vsync(timing_vsync), .hblank(timing_hblank),
        .vblank(timing_vblank), .frame_start(timing_frame_start),
        .vblank_start(timing_vblank_start),
        .prefetch_start(timing_prefetch_start),
        .frame_end(timing_frame_end), .line_start(timing_line_start),
        .line_end(timing_line_end), .vsync_start(timing_vsync_start),
        .vsync_end(timing_vsync_end)
    );

    c2_page_flip_ctrl #(.PAGE_W(PAGE_W), .PAGE_COUNT(1 << PAGE_W)) u_page_flip (
        // Commit during vertical blank; prefetch_start is delayed one clock
        // so the display path captures the newly registered active page.
        .clk(clk_pix), .rst_n(rst_pix_n), .frame_start(timing_vblank_start),
        .request_valid(page_pix_req_valid), .request_ready(page_pix_req_ready),
        .request_page(page_pix_req_page), .active_page(active_page_pix),
        .pending_page(pending_page_pix), .flip_pending(page_flip_pending_pix),
        .flip_ack(csr_page_flip_ack), .request_error(csr_page_error)
    );

    // Page requests/status cross the CSR and pixel clock domains only through
    // this reserved bridge when the clock IP is enabled.  The default XSIM
    // configuration uses the direct same-clock path.
    generate
        if (USE_CLOCK_RESET_IP) begin : g_page_cdc_ip
            c2_page_cdc_blackbox #(.PAGE_W(PAGE_W)) u_page_cdc (
                .src_clk(clk_sys), .src_rst_n(rst_sys_n),
                .src_req_valid(csr_page_valid), .src_req_ready(csr_page_ready),
                .src_req_page(csr_page), .src_active_page(active_page),
                .src_pending_page(pending_page),
                .src_flip_pending(page_flip_pending),
                .dst_clk(clk_pix), .dst_rst_n(rst_pix_n),
                .dst_req_valid(page_pix_req_valid),
                .dst_req_ready(page_pix_req_ready),
                .dst_req_page(page_pix_req_page),
                .dst_active_page(active_page_pix),
                .dst_pending_page(pending_page_pix),
                .dst_flip_pending(page_flip_pending_pix)
            );
        end else begin : g_page_cdc_sim
            assign page_pix_req_valid = csr_page_valid;
            assign csr_page_ready = page_pix_req_ready;
            assign page_pix_req_page = csr_page;
            assign active_page = active_page_pix;
            assign pending_page = pending_page_pix;
            assign page_flip_pending = page_flip_pending_pix;
        end
    endgenerate

    always_comb begin
        if (active_page_pix == '0)
            display_base_addr = ADDR_W'(PAGE0_BASE);
        else if (PAGE_W == 1)
            // Keep the explicit PAGE1_BASE override usable for boards whose
            // allocator leaves a guard region between framebuffer pages.
            display_base_addr = ADDR_W'(PAGE1_BASE);
        else
            display_base_addr = ADDR_W'(PAGE0_BASE) +
                                (ADDR_W'(active_page_pix) * ADDR_W'(PAGE_BYTES));
    end

    // -------------------------------------------------------------- display m1
    logic m1_req_valid, m1_req_ready, m1_req_write;
    logic [ADDR_W-1:0] m1_req_addr;
    logic [LEN_W-1:0] m1_req_len;
    logic [DATA_W-1:0] m1_req_wdata;
    logic [(DATA_W/8)-1:0] m1_req_wstrb;
    logic m1_rsp_valid, m1_rsp_ready;
    logic [DATA_W-1:0] m1_rsp_rdata;
    logic m1_rsp_last, m1_rsp_error;
    // Display is read-only today; these ports are tied off but remain present
    // so a future write-capable overlay can use the same owner contract.
    logic m1_wr_valid, m1_wr_ready;
    logic [DATA_W-1:0] m1_wr_data;
    logic [(DATA_W/8)-1:0] m1_wr_strb;
    logic m1_wr_last, m1_wr_error;
    logic m1_wr_rsp_valid, m1_wr_rsp_ready, m1_wr_rsp_error;
    logic disp_req_valid, disp_req_ready, disp_req_write;
    logic [ADDR_W-1:0] disp_req_addr;
    logic [LEN_W-1:0] disp_req_len;
    logic [DATA_W-1:0] disp_req_wdata;
    logic [(DATA_W/8)-1:0] disp_req_wstrb;
    logic disp_rsp_valid, disp_rsp_ready;
    logic [DATA_W-1:0] disp_rsp_rdata;
    logic disp_rsp_last, disp_rsp_error;
    logic [((LINE_FIFO_DEPTH <= 1) ? 1 : $clog2(LINE_FIFO_DEPTH+1))-1:0]
      display_fifo_level;
    // Video-path signals are declared before the display instance so older
    // Verilog parsers do not implicitly create one-bit nets at the use site.
    logic path_pixel_ready;
    logic path_video_valid, path_video_de, path_video_hsync, path_video_vsync;
    logic [DATA_W-1:0] path_video_data;

    c2_display_path #(
        .ADDR_W(ADDR_W), .DATA_W(DATA_W), .MAX_BURST_BEATS(MAX_BURST_BEATS),
        .LINE_FIFO_DEPTH(LINE_FIFO_DEPTH)
    ) u_display (
        .clk(clk_pix), .rst_n(rst_pix_n),
        .prefetch_start(timing_prefetch_start),
        .active_frame_start(timing_frame_start),
        .timing_de(timing_de), .timing_hsync(timing_hsync),
        .timing_vsync(timing_vsync), .base_addr(display_base_addr),
        .stride_bytes(FB_STRIDE_C), .width(H_ACTIVE_C), .height(V_ACTIVE_C),
        .phy_pixel_ready(path_pixel_ready),
        .mem_req_valid(disp_req_valid), .mem_req_ready(disp_req_ready),
        .mem_req_write(disp_req_write), .mem_req_addr(disp_req_addr),
        .mem_req_len(disp_req_len), .mem_req_wdata(disp_req_wdata),
        .mem_req_wstrb(disp_req_wstrb), .mem_rsp_valid(disp_rsp_valid),
        .mem_rsp_ready(disp_rsp_ready), .mem_rsp_rdata(disp_rsp_rdata),
        .mem_rsp_last(disp_rsp_last), .mem_rsp_error(disp_rsp_error),
        .video_valid(path_video_valid), .video_data(path_video_data),
        .video_de(path_video_de), .video_hsync(path_video_hsync),
        .video_vsync(path_video_vsync), .display_busy(display_busy),
        .display_done(), .display_error(display_error_status),
        .display_underflow(display_underflow),
        .display_pixel_count(display_pixel_count),
        .display_error_count(display_error_count), .fifo_level(display_fifo_level)
    );

    // The display master is in clk_pix; the arbiter is in clk_sys.  In the
    // default same-clock simulation this is a direct wire path.  Real clock-IP
    // integration must replace the other branch with an async transaction
    // bridge that preserves burst response ordering.
    generate
        if (USE_CLOCK_RESET_IP) begin : g_display_mem_cdc_ip
            c2_mem_cdc_blackbox #(
                .ADDR_W(ADDR_W), .DATA_W(DATA_W), .LEN_W(LEN_W)
            ) u_display_mem_cdc (
                .src_clk(clk_pix), .src_rst_n(rst_pix_n),
                .src_req_valid(disp_req_valid), .src_req_ready(disp_req_ready),
                .src_req_write(disp_req_write), .src_req_addr(disp_req_addr),
                .src_req_len(disp_req_len), .src_req_wdata(disp_req_wdata),
                .src_req_wstrb(disp_req_wstrb), .src_rsp_valid(disp_rsp_valid),
                .src_rsp_ready(disp_rsp_ready), .src_rsp_rdata(disp_rsp_rdata),
                .src_rsp_last(disp_rsp_last), .src_rsp_error(disp_rsp_error),
                .dst_clk(clk_sys), .dst_rst_n(rst_sys_n),
                .dst_req_valid(m1_req_valid), .dst_req_ready(m1_req_ready),
                .dst_req_write(m1_req_write), .dst_req_addr(m1_req_addr),
                .dst_req_len(m1_req_len), .dst_req_wdata(m1_req_wdata),
                .dst_req_wstrb(m1_req_wstrb), .dst_rsp_valid(m1_rsp_valid),
                .dst_rsp_ready(m1_rsp_ready), .dst_rsp_rdata(m1_rsp_rdata),
                .dst_rsp_last(m1_rsp_last), .dst_rsp_error(m1_rsp_error)
            );
        end else begin : g_display_mem_cdc_sim
            assign m1_req_valid = disp_req_valid;
            assign disp_req_ready = m1_req_ready;
            assign m1_req_write = disp_req_write;
            assign m1_req_addr = disp_req_addr;
            assign m1_req_len = disp_req_len;
            assign m1_req_wdata = disp_req_wdata;
            assign m1_req_wstrb = disp_req_wstrb;
            assign disp_rsp_valid = m1_rsp_valid;
            assign m1_rsp_ready = disp_rsp_ready;
            assign disp_rsp_rdata = m1_rsp_rdata;
            assign disp_rsp_last = m1_rsp_last;
            assign disp_rsp_error = m1_rsp_error;
        end
    endgenerate

    // -------------------------------------------------------------- arbitration
    logic s_req_valid, s_req_ready, s_req_write;
    logic [ADDR_W-1:0] s_req_addr;
    logic [LEN_W-1:0] s_req_len;
    logic [DATA_W-1:0] s_req_wdata;
    logic [(DATA_W/8)-1:0] s_req_wstrb;
    logic s_rsp_valid, s_rsp_ready;
    logic [DATA_W-1:0] s_rsp_rdata;
    logic s_rsp_last, s_rsp_error;
    logic s_wr_valid, s_wr_ready, s_wr_last, s_wr_error;
    logic [DATA_W-1:0] s_wr_data;
    logic [(DATA_W/8)-1:0] s_wr_strb;
    logic s_wr_rsp_valid, s_wr_rsp_ready, s_wr_rsp_error;
    logic arb_busy, arb_owner_valid, arb_owner_m1, arb_owner_write;
    logic arb_write_protocol_error;
    logic [31:0] arb_write_protocol_error_count;
    logic [31:0] arb_grant_count, arb_read_count, arb_write_count;
    logic [31:0] arb_write_beat_count, arb_response_count;
    logic [31:0] arb_write_response_count;
    logic [31:0] arb_write_response_error_count;
    logic [31:0] arb_response_protocol_error_count, arb_orphan_count;
    logic [31:0] arb_orphan_write_response_count;

    assign m1_wr_valid = 1'b0;
    assign m1_wr_data  = '0;
    assign m1_wr_strb  = '0;
    assign m1_wr_last  = 1'b0;
    assign m1_wr_rsp_ready = 1'b1;

    c2_mem_arbiter_2m_owner #(
        .ADDR_W(ADDR_W), .DATA_W(DATA_W), .LEN_W(LEN_W)
    ) u_arbiter (
        .clk(clk_sys), .rst_n(rst_sys_n), .display_priority(1'b1),
        .m0_req_valid, .m0_req_ready, .m0_req_write, .m0_req_addr,
        .m0_req_len, .m0_req_wdata, .m0_req_wstrb,
        .m0_wr_valid, .m0_wr_ready, .m0_wr_data, .m0_wr_strb, .m0_wr_last,
        .m0_wr_error,
        .m0_wr_rsp_valid, .m0_wr_rsp_ready, .m0_wr_rsp_error,
        .m0_rsp_valid, .m0_rsp_ready, .m0_rsp_rdata, .m0_rsp_last,
        .m0_rsp_error,
        .m1_req_valid, .m1_req_ready, .m1_req_write, .m1_req_addr,
        .m1_req_len, .m1_req_wdata, .m1_req_wstrb,
        .m1_wr_valid, .m1_wr_ready, .m1_wr_data, .m1_wr_strb, .m1_wr_last,
        .m1_wr_error,
        .m1_wr_rsp_valid, .m1_wr_rsp_ready, .m1_wr_rsp_error,
        .m1_rsp_valid, .m1_rsp_ready, .m1_rsp_rdata, .m1_rsp_last,
        .m1_rsp_error,
        .s_req_valid, .s_req_ready, .s_req_write, .s_req_addr, .s_req_len,
        .s_req_wdata, .s_req_wstrb,
        .s_wr_valid, .s_wr_ready, .s_wr_data, .s_wr_strb, .s_wr_last,
        .s_wr_error,
        .s_wr_rsp_valid, .s_wr_rsp_ready, .s_wr_rsp_error,
        .s_rsp_valid, .s_rsp_ready, .s_rsp_rdata, .s_rsp_last, .s_rsp_error,
        .busy(arb_busy), .owner_valid(arb_owner_valid),
        .owner_m1(arb_owner_m1), .owner_write(arb_owner_write),
        .write_protocol_error(arb_write_protocol_error),
        .write_protocol_error_count(arb_write_protocol_error_count),
        .grant_count(arb_grant_count), .read_count(arb_read_count),
        .write_count(arb_write_count), .write_beat_count(arb_write_beat_count),
        .write_response_count(arb_write_response_count),
        .write_response_error_count(arb_write_response_error_count),
        .response_count(arb_response_count),
        .response_protocol_error_count(arb_response_protocol_error_count),
        .orphan_response_count(arb_orphan_count),
        .orphan_write_response_count(arb_orphan_write_response_count)
    );

    // -------------------------------------------------------------- memory IP
    logic mem_ip_init_done_i, mem_ip_init_error_i;
    logic [31:0] mem_model_error_count;
    logic [31:0] mem_model_descriptor_count, mem_model_write_beat_count;
    logic [31:0] mem_model_response_count;
    logic [31:0] mem_model_write_response_count;
    logic [31:0] mem_axi_protocol_error_count, mem_axi_error_count;
    generate
        if (USE_EXT_MEM_IP) begin : g_mem_ip
            logic adapter_req_ready;
            c2_mem_to_axi4_adapter #(
                .ADDR_W(ADDR_W), .DATA_W(DATA_W), .LEN_W(LEN_W),
                .AXI_DATA_W(AXI_DATA_W), .AXI_ID_W(AXI_ID_W)
            ) u_axi_adapter (
                .clk(clk_sys), .rst_n(rst_sys_n),
                .mem_req_valid(s_req_valid && ext_mem_init_done &&
                               !ext_mem_init_error),
                .mem_req_ready(adapter_req_ready),
                .mem_req_write(s_req_write), .mem_req_addr(s_req_addr),
                .mem_req_len(s_req_len), .mem_req_wdata(s_req_wdata),
                .mem_req_wstrb(s_req_wstrb),
                .mem_wr_valid(s_wr_valid), .mem_wr_ready(s_wr_ready),
                .mem_wr_data(s_wr_data), .mem_wr_strb(s_wr_strb),
                .mem_wr_last(s_wr_last), .mem_wr_error(s_wr_error),
                .mem_wr_rsp_valid(s_wr_rsp_valid),
                .mem_wr_rsp_ready(s_wr_rsp_ready),
                .mem_wr_rsp_error(s_wr_rsp_error),
                .mem_rsp_valid(s_rsp_valid), .mem_rsp_ready(s_rsp_ready),
                .mem_rsp_rdata(s_rsp_rdata), .mem_rsp_last(s_rsp_last),
                .mem_rsp_error(s_rsp_error),
                .m_axi_awid, .m_axi_awaddr, .m_axi_awlen, .m_axi_awsize,
                .m_axi_awburst, .m_axi_awlock, .m_axi_awcache,
                .m_axi_awprot, .m_axi_awqos, .m_axi_awvalid,
                .m_axi_awready, .m_axi_wdata, .m_axi_wstrb, .m_axi_wlast,
                .m_axi_wvalid, .m_axi_wready, .m_axi_bid, .m_axi_bresp,
                .m_axi_bvalid, .m_axi_bready, .m_axi_arid, .m_axi_araddr,
                .m_axi_arlen, .m_axi_arsize, .m_axi_arburst,
                .m_axi_arlock, .m_axi_arcache, .m_axi_arprot,
                .m_axi_arqos, .m_axi_arvalid, .m_axi_arready,
                .m_axi_rid, .m_axi_rdata, .m_axi_rresp, .m_axi_rlast,
                .m_axi_rvalid, .m_axi_rready, .busy(),
                .protocol_error_count(mem_axi_protocol_error_count),
                .axi_error_count(mem_axi_error_count)
            );
            assign s_req_ready = adapter_req_ready && ext_mem_init_done &&
                                 !ext_mem_init_error;
            assign mem_read_count = arb_read_count;
            assign mem_write_count = arb_write_count;
            assign mem_response_count = arb_response_count;
            assign mem_ip_init_done_i = ext_mem_init_done;
            assign mem_ip_init_error_i = ext_mem_init_error;
            assign mem_model_error_count = 32'd0;
            assign mem_model_descriptor_count = 32'd0;
            assign mem_model_write_beat_count = 32'd0;
            assign mem_model_response_count = 32'd0;
            assign mem_model_write_response_count = 32'd0;
        end else begin : g_mem_model
            render_owner_mem_model #(
                .ADDR_W(ADDR_W), .DATA_W(DATA_W), .LEN_W(LEN_W),
                .MEM_BYTES(MEM_BYTES), .READ_LATENCY(1)
            ) u_mem_model (
                .clk(clk_sys), .rst_n(rst_sys_n),
                .req_valid(s_req_valid), .req_ready(s_req_ready),
                .req_write(s_req_write), .req_addr(s_req_addr),
                .req_len(s_req_len), .req_wdata(s_req_wdata),
                .req_wstrb(s_req_wstrb), .rsp_valid(s_rsp_valid),
                .rsp_ready(s_rsp_ready), .rsp_rdata(s_rsp_rdata),
                .rsp_last(s_rsp_last), .rsp_error(s_rsp_error),
                .wr_valid(s_wr_valid), .wr_ready(s_wr_ready),
                .wr_data(s_wr_data), .wr_strb(s_wr_strb), .wr_last(s_wr_last),
                .wr_error(s_wr_error),
                .wr_rsp_valid(s_wr_rsp_valid), .wr_rsp_ready(s_wr_rsp_ready),
                .wr_rsp_error(s_wr_rsp_error),
                .descriptor_count(mem_model_descriptor_count),
                .read_count(mem_read_count), .write_count(mem_write_count),
                .write_beat_count(mem_model_write_beat_count),
                .write_response_count(mem_model_write_response_count),
                .response_count(mem_model_response_count),
                .error_count(mem_model_error_count)
            );
            assign mem_response_count = arb_response_count;
            assign mem_ip_init_done_i = 1'b1;
            assign mem_ip_init_error_i = 1'b0;
            assign mem_axi_protocol_error_count = 32'd0;
            assign mem_axi_error_count = 32'd0;
            assign m_axi_awid = '0;
            assign m_axi_awaddr = '0;
            assign m_axi_awlen = '0;
            assign m_axi_awsize = '0;
            assign m_axi_awburst = '0;
            assign m_axi_awlock = 1'b0;
            assign m_axi_awcache = '0;
            assign m_axi_awprot = '0;
            assign m_axi_awqos = '0;
            assign m_axi_awvalid = 1'b0;
            assign m_axi_wdata = '0;
            assign m_axi_wstrb = '0;
            assign m_axi_wlast = 1'b0;
            assign m_axi_wvalid = 1'b0;
            assign m_axi_bready = 1'b0;
            assign m_axi_arid = '0;
            assign m_axi_araddr = '0;
            assign m_axi_arlen = '0;
            assign m_axi_arsize = '0;
            assign m_axi_arburst = '0;
            assign m_axi_arlock = 1'b0;
            assign m_axi_arcache = '0;
            assign m_axi_arprot = '0;
            assign m_axi_arqos = '0;
            assign m_axi_arvalid = 1'b0;
            assign m_axi_rready = 1'b0;
        end
    endgenerate
    assign mem_init_done = mem_ip_init_done_i;
    assign mem_init_error = mem_ip_init_error_i;

    // -------------------------------------------------------------- video IP
    logic phy_init_done_i, phy_init_error_i;

    generate
        if (USE_VIDEO_PHY_IP) begin : g_video_ip
            c2_video_phy_blackbox #(.DATA_W(DATA_W)) u_video_ip (
                .clk_pix, .rst_n(rst_pix_n), .pixel_valid(path_video_valid),
                .pixel_ready(path_pixel_ready), .pixel_data(path_video_data),
                .pixel_de(path_video_de), .pixel_hsync(path_video_hsync),
                .pixel_vsync(path_video_vsync), .phy_clk(video_clk),
                .phy_data(video_data), .phy_de(video_de),
                .phy_hsync(video_hsync), .phy_vsync(video_vsync),
                .phy_valid(video_valid), .init_done(phy_init_done_i),
                .init_error(phy_init_error_i)
            );
        end else begin : g_video_sim
            assign path_pixel_ready = 1'b1;
            assign video_clk = clk_pix;
            assign video_valid = path_video_valid;
            assign video_data = path_video_data;
            assign video_de = path_video_de;
            assign video_hsync = path_video_hsync;
            assign video_vsync = path_video_vsync;
            assign phy_init_done_i = 1'b1;
            assign phy_init_error_i = 1'b0;
        end
    endgenerate
    assign video_init_done = phy_init_done_i;
    assign video_init_error = phy_init_error_i;

    assign mem_error_status = mem_init_error ||
                              (mem_model_error_count != 0) ||
                              (mem_axi_protocol_error_count != 0) ||
                              (mem_axi_error_count != 0) ||
                              (arb_write_protocol_error_count != 0) ||
                              (arb_write_response_error_count != 0) ||
                              (arb_response_protocol_error_count != 0) ||
                              (engine_error_count != 0);
    assign system_busy = parser_busy || engine_busy || display_busy || arb_busy ||
                         !fifo_empty || fifo_in_valid || csr_page_valid ||
                         page_flip_pending;
    assign system_error = !clock_locked || mem_error_status || phy_init_error_i ||
                           parser_error_valid || display_error_status ||
                           display_underflow;

`ifndef SYNTHESIS
    initial begin
        if (ADDR_W < 12 || DATA_W != 16 || LEN_W != 16 ||
            AXI_DATA_W < DATA_W || (AXI_DATA_W % DATA_W) != 0 ||
            AXI_ID_W <= 0 ||
            PAGE_W <= 0 || CMD_FIFO_DEPTH <= 0 || H_ACTIVE <= 0 || V_ACTIVE <= 0)
            $error("c2_renderer_system: invalid parameter");
        if (!WRITE_BURST_ENABLE)
            $error("c2_renderer_system: owner-aware system requires WRITE_BURST_ENABLE=1");
        if (!READ_BURST_ENABLE)
            $error("c2_renderer_system: competition system requires READ_BURST_ENABLE=1");
        if (FB_STRIDE_BYTES < H_ACTIVE * (DATA_W/8) || PAGE_BYTES <= 0)
            $error("c2_renderer_system: framebuffer stride/page size is too small");
        if ((PAGE_W == 1) && (PAGE1_BASE < (PAGE0_BASE + PAGE_BYTES)))
            $error("c2_renderer_system: PAGE0/PAGE1 overlap");
        if (!USE_EXT_MEM_IP &&
            (MEM_BYTES < ((PAGE_W == 1) ? (PAGE1_BASE + PAGE_BYTES) :
                          (PAGE0_BASE + ((1 << PAGE_W) * PAGE_BYTES)))))
            $error("c2_renderer_system: behavioral memory does not cover all framebuffer pages");
    end
`endif
endmodule
