`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// c2_display_path
// -----------------------------------------------------------------------------
// Board-independent display-side assembly:
//
//   prefetch_start/config -> c2_rect_burst_reader -> c2_line_fifo -> video sink
//
// The framebuffer configuration is captured at prefetch_start, one clock after
// the page controller commits during vertical blanking.  The reader launches
// on the following clock, after the synchronous FIFO flush.  At the next
// active_frame_start the scan is armed only if prefetched data is already in
// the FIFO; otherwise that complete frame remains black.  This makes the first
// active frame after reset intentionally safe even though it had no preceding
// vertical blank in which to prefetch.
// -----------------------------------------------------------------------------
module c2_display_path #(
    parameter int ADDR_W          = 32,
    parameter int DATA_W          = 16,
    parameter int MAX_BURST_BEATS = 16,
    parameter int LINE_FIFO_DEPTH = 1024,
    parameter bit LIMIT_4KB        = 1'b1
) (
    input  logic                     clk,
    input  logic                     rst_n,
    input  logic                     prefetch_start,
    input  logic                     active_frame_start,
    input  logic                     timing_de,
    input  logic                     timing_hsync,
    input  logic                     timing_vsync,
    input  logic [ADDR_W-1:0]        base_addr,
    input  logic [ADDR_W-1:0]        stride_bytes,
    input  logic [15:0]              width,
    input  logic [15:0]              height,
    input  logic                     phy_pixel_ready,

    output logic                     mem_req_valid,
    input  logic                     mem_req_ready,
    output logic                     mem_req_write,
    output logic [ADDR_W-1:0]        mem_req_addr,
    output logic [15:0]              mem_req_len,
    output logic [DATA_W-1:0]        mem_req_wdata,
    output logic [(DATA_W/8)-1:0]    mem_req_wstrb,
    input  logic                     mem_rsp_valid,
    output logic                     mem_rsp_ready,
    input  logic [DATA_W-1:0]        mem_rsp_rdata,
    input  logic                     mem_rsp_last,
    input  logic                     mem_rsp_error,

    output logic                     video_valid,
    output logic [DATA_W-1:0]        video_data,
    output logic                     video_de,
    output logic                     video_hsync,
    output logic                     video_vsync,
    output logic                     display_busy,
    output logic                     display_done,
    output logic                     display_error,
    output logic                     display_underflow,
    output logic [31:0]              display_pixel_count,
    output logic [31:0]              display_error_count,
    output logic [((LINE_FIFO_DEPTH <= 1) ? 1 : $clog2(LINE_FIFO_DEPTH+1))-1:0]
                                      fifo_level
);

    localparam int BYTE_LANES = DATA_W / 8;
    localparam int FIFO_CNT_W = (LINE_FIFO_DEPTH <= 1) ? 1 :
                                $clog2(LINE_FIFO_DEPTH + 1);

    logic [ADDR_W-1:0] cfg_base_q;
    logic [ADDR_W-1:0] cfg_stride_q;
    logic [15:0]       cfg_width_q;
    logic [15:0]       cfg_height_q;
    logic              launch_pending_q;
    logic              reader_start;
    logic              reader_start_ready;
    logic              line_flush;

    logic reader_mem_req_valid, reader_mem_req_ready, reader_mem_req_write;
    logic [ADDR_W-1:0] reader_mem_req_addr;
    logic [15:0] reader_mem_req_len;
    logic [DATA_W-1:0] reader_mem_req_wdata;
    logic [(DATA_W/8)-1:0] reader_mem_req_wstrb;
    logic reader_mem_rsp_valid, reader_mem_rsp_ready;
    logic [DATA_W-1:0] reader_mem_rsp_rdata;
    logic reader_mem_rsp_last, reader_mem_rsp_error;
    logic reader_pixel_valid, reader_pixel_ready, reader_pixel_last;
    logic [DATA_W-1:0] reader_pixel_data;
    logic [15:0] reader_pixel_x, reader_pixel_y;
    logic reader_busy, reader_done, reader_error;
    logic [3:0] reader_error_code;
    logic [31:0] reader_request_count, reader_pixel_count, reader_error_count;

    logic line_in_valid, line_in_ready, line_in_last;
    logic [DATA_W-1:0] line_in_data;
    logic line_out_valid, line_out_ready, line_out_last;
    logic [DATA_W-1:0] line_out_data;
    logic line_full, line_empty, line_overflow, line_underflow;
    logic fifo_pixel_fire;
    logic [FIFO_CNT_W-1:0] line_level;
    logic [ADDR_W-1:0] row_bytes;
    logic underflow_q;
    logic frame_armed_q;
    logic frame_consume_enable;
    logic prefetch_seen_q;
    logic active_underflow_event;
    logic phy_not_ready_event;
    logic path_error_event;

    assign row_bytes = ADDR_W'(cfg_width_q) * ADDR_W'(BYTE_LANES);

    // prefetch_start is generated one clock after the vertical-blank page
    // commit.  Capturing here therefore observes the newly committed page.
    // Launch remains delayed by another clock so the FIFO flush completes
    // before the first possible returned sample.
    // Flush again at the actual new-reader launch.  If the previous scan
    // overran into vertical blanking, this discards any late pixels from the
    // old page before the newly captured page starts filling the FIFO.
    assign line_flush = prefetch_start || reader_start;
    assign reader_start = launch_pending_q && reader_start_ready &&
                          !prefetch_start;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cfg_base_q       <= '0;
            cfg_stride_q     <= '0;
            cfg_width_q      <= '0;
            cfg_height_q     <= '0;
            launch_pending_q <= 1'b0;
        end else begin
            if (prefetch_start) begin
                cfg_base_q       <= base_addr;
                cfg_stride_q     <= stride_bytes;
                cfg_width_q      <= width;
                cfg_height_q     <= height;
                launch_pending_q <= 1'b1;
            end else if (reader_start) begin
                launch_pending_q <= 1'b0;
            end
        end
    end

    c2_rect_burst_reader #(
        .ADDR_W(ADDR_W), .DATA_W(DATA_W),
        .MAX_BURST_BEATS(MAX_BURST_BEATS), .LIMIT_4KB(LIMIT_4KB)
    ) u_reader (
        .clk, .rst_n,
        .start(reader_start), .start_ready(reader_start_ready),
        .base_addr(cfg_base_q), .stride_bytes(cfg_stride_q),
        .row_bytes(row_bytes), .rows(cfg_height_q),
        .busy(reader_busy), .done(reader_done), .error(reader_error),
        .error_code(reader_error_code),
        .mem_req_valid(reader_mem_req_valid),
        .mem_req_ready(reader_mem_req_ready),
        .mem_req_write(reader_mem_req_write),
        .mem_req_addr(reader_mem_req_addr), .mem_req_len(reader_mem_req_len),
        .mem_req_wdata(reader_mem_req_wdata),
        .mem_req_wstrb(reader_mem_req_wstrb),
        .mem_rsp_valid(reader_mem_rsp_valid),
        .mem_rsp_ready(reader_mem_rsp_ready),
        .mem_rsp_rdata(reader_mem_rsp_rdata),
        .mem_rsp_last(reader_mem_rsp_last),
        .mem_rsp_error(reader_mem_rsp_error),
        .pixel_valid(reader_pixel_valid), .pixel_ready(reader_pixel_ready),
        .pixel_data(reader_pixel_data), .pixel_x(reader_pixel_x),
        .pixel_y(reader_pixel_y), .pixel_last(reader_pixel_last),
        .frame_last(), .request_count(reader_request_count),
        .pixel_count(reader_pixel_count), .error_count(reader_error_count)
    );

    assign mem_req_valid = reader_mem_req_valid;
    assign reader_mem_req_ready = mem_req_ready;
    assign mem_req_write = reader_mem_req_write;
    assign mem_req_addr  = reader_mem_req_addr;
    assign mem_req_len   = reader_mem_req_len;
    assign mem_req_wdata = reader_mem_req_wdata;
    assign mem_req_wstrb = reader_mem_req_wstrb;
    assign reader_mem_rsp_valid = mem_rsp_valid;
    assign mem_rsp_ready = reader_mem_rsp_ready;
    assign reader_mem_rsp_rdata = mem_rsp_rdata;
    assign reader_mem_rsp_last = mem_rsp_last;
    assign reader_mem_rsp_error = mem_rsp_error;

    assign line_in_valid = reader_pixel_valid;
    assign reader_pixel_ready = line_in_ready;
    assign line_in_data  = reader_pixel_data;
    assign line_in_last  = reader_pixel_last;

    c2_line_fifo #(.DATA_W(DATA_W), .DEPTH(LINE_FIFO_DEPTH)) u_line_fifo (
        .clk, .rst_n, .flush(line_flush),
        .in_valid(line_in_valid), .in_ready(line_in_ready),
        .in_data(line_in_data), .in_last(line_in_last),
        .out_valid(line_out_valid), .out_ready(line_out_ready),
        .out_data(line_out_data), .out_last(line_out_last),
        .level(line_level), .full(line_full), .empty(line_empty),
        .overflow(line_overflow), .underflow(line_underflow)
    );

    // The boundary-cycle term permits the very first prefetched pixel to be
    // consumed on active_frame_start itself.  frame_armed_q then holds the
    // decision for the remainder of the active frame; a late FIFO fill cannot
    // turn on a partially missing picture.
    assign frame_consume_enable = frame_armed_q ||
                                  (active_frame_start && line_out_valid);
    assign fifo_pixel_fire = line_out_valid && line_out_ready;
    assign line_out_ready = timing_de && phy_pixel_ready &&
                            frame_consume_enable;
    assign video_valid = timing_de && line_out_valid && frame_consume_enable;
    assign video_data  = (line_out_valid && frame_consume_enable) ?
                         line_out_data : '0;
    assign video_de    = timing_de;
    assign video_hsync = timing_hsync;
    assign video_vsync = timing_vsync;
    assign display_busy = reader_busy || launch_pending_q;
    assign display_done = reader_done;
    assign display_underflow = underflow_q;
    assign fifo_level = line_level;

    // Once a frame has been armed, exhausting the FIFO is an underflow.  If a
    // completed prefetch interval reaches active_frame_start empty, record the
    // same condition while deliberately keeping the whole frame black.  The
    // reset-time first frame is exempt because it had no prefetch interval.
    assign active_underflow_event =
        (timing_de && frame_consume_enable && phy_pixel_ready &&
         !line_out_valid) ||
        (active_frame_start && prefetch_seen_q && !line_out_valid);
    assign phy_not_ready_event = timing_de && !phy_pixel_ready;
    assign path_error_event = active_underflow_event || phy_not_ready_event ||
                              reader_error || line_overflow;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            underflow_q        <= 1'b0;
            frame_armed_q      <= 1'b0;
            prefetch_seen_q    <= 1'b0;
            display_error      <= 1'b0;
            display_pixel_count <= 32'd0;
            display_error_count <= 32'd0;
        end else begin
            if (prefetch_start) begin
                underflow_q     <= 1'b0;
                frame_armed_q   <= 1'b0;
                prefetch_seen_q <= 1'b1;
                display_error <= 1'b0;
            end

            if (active_frame_start)
                frame_armed_q <= line_out_valid;

            if (active_underflow_event)
                underflow_q <= 1'b1;

            if (path_error_event) begin
                display_error       <= 1'b1;
                display_error_count <= display_error_count + 32'd1;
            end
            if (fifo_pixel_fire)
                display_pixel_count <= display_pixel_count + 32'd1;
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (DATA_W <= 0 || (DATA_W % 8) != 0 || LINE_FIFO_DEPTH <= 0)
            $error("c2_display_path: invalid parameter");
    end
`endif
endmodule
