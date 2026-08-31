`timescale 1ns/1ps

// Original/styled XRGB8888 display prefetch pair.
//
// Two cancel-safe frame readers fetch the complete 640x480 images in the core
// clock domain.  Each reader is backpressured by a two-line, dual-clock store,
// so only the next even/odd lines are resident and the unstalled pixel raster
// receives a deterministic one-cycle RGB response.  The two AXI read masters
// remain separate for a system-level arbiter.
module c1_display_prefetch_pair #(
    parameter integer MAX_WIDTH = 640,
    parameter integer X_BITS = (MAX_WIDTH <= 1) ? 1 : $clog2(MAX_WIDTH),
    parameter integer Y_BITS = 16,
    // A one-burst pixel response FIFO lets a reader drain an already
    // accepted AXI burst even when its line store is temporarily held by
    // the pixel/control domain.  Keep the historical direct path as the
    // default; the FIFO is enabled explicitly for QoS experiments.
    parameter integer ENABLE_RESPONSE_FIFO = 0,
    parameter integer RESPONSE_FIFO_DEPTH = 64
) (
    input  logic                  core_clk,
    input  logic                  core_rst,
    input  logic                  start_valid,
    output logic                  start_ready,
    input  logic                  abort,
    input  logic                  hold_requests,
    input  logic [31:0]           original_base,
    input  logic [31:0]           original_stride,
    input  logic [31:0]           styled_base,
    input  logic [31:0]           styled_stride,
    input  logic [15:0]           width_pixels,
    input  logic [15:0]           height_lines,
    output logic                  busy,
    output logic                  done,
    output logic                  aborted,
    output logic                  error,
    output logic                  primed,

    input  logic                  pixel_clk,
    input  logic                  pixel_rst,
    input  logic                  original_request,
    input  logic [X_BITS-1:0]     original_request_x,
    input  logic [Y_BITS-1:0]     original_request_y,
    output logic                  original_response_valid,
    output logic [23:0]           original_rgb,
    output logic                  original_underflow,
    input  logic                  styled_request,
    input  logic [X_BITS-1:0]     styled_request_x,
    input  logic [Y_BITS-1:0]     styled_request_y,
    output logic                  styled_response_valid,
    output logic [23:0]           styled_rgb,
    output logic                  styled_underflow,

    output logic [31:0]           original_axi_araddr,
    output logic [7:0]            original_axi_arlen,
    output logic [2:0]            original_axi_arsize,
    output logic [1:0]            original_axi_arburst,
    output logic                  original_axi_arvalid,
    input  logic                  original_axi_arready,
    input  logic [127:0]          original_axi_rdata,
    input  logic [1:0]            original_axi_rresp,
    input  logic                  original_axi_rlast,
    input  logic                  original_axi_rvalid,
    output logic                  original_axi_rready,

    output logic [31:0]           styled_axi_araddr,
    output logic [7:0]            styled_axi_arlen,
    output logic [2:0]            styled_axi_arsize,
    output logic [1:0]            styled_axi_arburst,
    output logic                  styled_axi_arvalid,
    input  logic                  styled_axi_arready,
    input  logic [127:0]          styled_axi_rdata,
    input  logic [1:0]            styled_axi_rresp,
    input  logic                  styled_axi_rlast,
    input  logic                  styled_axi_rvalid,
    output logic                  styled_axi_rready
);

    logic active;
    logic aborting;
    logic [1:0] done_seen;
    logic start_fire;
    logic original_reader_busy;
    logic original_reader_done;
    logic original_reader_error;
    logic styled_reader_busy;
    logic styled_reader_done;
    logic styled_reader_error;

    localparam integer RESPONSE_FIFO_WIDTH = 59;
    localparam integer RESPONSE_FIFO_LEVEL_WIDTH =
        (RESPONSE_FIFO_DEPTH < 2) ? 1 : $clog2(RESPONSE_FIFO_DEPTH + 1);
    localparam integer RESPONSE_FIFO_ADMISSION_LEVEL =
        (RESPONSE_FIFO_DEPTH >= 64) ? (RESPONSE_FIFO_DEPTH - 64) : 0;
    logic original_reader_stream_valid;
    logic original_reader_stream_ready;
    logic [23:0] original_reader_stream_rgb;
    logic original_reader_stream_sof;
    logic original_reader_stream_eol;
    logic original_reader_stream_eof;
    logic [15:0] original_reader_stream_x;
    logic [15:0] original_reader_stream_y;
    logic original_reader_axi_arvalid;
    logic original_reader_ar_allow;
    logic original_stream_valid;
    logic original_stream_ready;
    logic [23:0] original_stream_rgb;
    logic original_stream_sof;
    logic original_stream_eol;
    logic original_stream_eof;
    logic [15:0] original_stream_x;
    logic [15:0] original_stream_y;
    logic styled_reader_stream_valid;
    logic styled_reader_stream_ready;
    logic [23:0] styled_reader_stream_rgb;
    logic styled_reader_stream_sof;
    logic styled_reader_stream_eol;
    logic styled_reader_stream_eof;
    logic [15:0] styled_reader_stream_x;
    logic [15:0] styled_reader_stream_y;
    logic styled_reader_axi_arvalid;
    logic styled_reader_ar_allow;
    logic styled_stream_valid;
    logic styled_stream_ready;
    logic [23:0] styled_stream_rgb;
    logic styled_stream_sof;
    logic styled_stream_eol;
    logic styled_stream_eof;
    logic [15:0] styled_stream_x;
    logic [15:0] styled_stream_y;
    logic [RESPONSE_FIFO_WIDTH-1:0] original_fifo_in_data;
    logic [RESPONSE_FIFO_WIDTH-1:0] original_fifo_out_data;
    logic original_fifo_in_valid, original_fifo_in_ready;
    logic original_fifo_out_valid, original_fifo_out_ready;
    logic [RESPONSE_FIFO_LEVEL_WIDTH-1:0] original_fifo_level;
    logic [RESPONSE_FIFO_WIDTH-1:0] styled_fifo_in_data;
    logic [RESPONSE_FIFO_WIDTH-1:0] styled_fifo_out_data;
    logic styled_fifo_in_valid, styled_fifo_in_ready;
    logic styled_fifo_out_valid, styled_fifo_out_ready;
    logic [RESPONSE_FIFO_LEVEL_WIDTH-1:0] styled_fifo_level;
    logic response_fifo_drained;

    logic original_primed;
    logic original_empty;
    logic styled_primed;
    logic styled_empty;
    logic [15:0] width_core;
    logic [15:0] width_sync1_pixel;
    logic [15:0] width_sync2_pixel;
    logic original_request_last;
    logic styled_request_last;
    logic [1:0] completion_next;

    always_comb begin
        start_ready = !core_rst && !active && !original_reader_busy &&
                      !styled_reader_busy && original_empty && styled_empty &&
                      response_fifo_drained;
        start_fire = start_valid && start_ready;
        busy = active || original_reader_busy || styled_reader_busy;
        primed = original_primed && styled_primed;
        completion_next = done_seen |
                          {styled_reader_done, original_reader_done};
        original_request_last = original_request &&
            (width_sync2_pixel != 0) &&
            (original_request_x == width_sync2_pixel[X_BITS-1:0] - 1'b1);
        styled_request_last = styled_request &&
            (width_sync2_pixel != 0) &&
            (styled_request_x == width_sync2_pixel[X_BITS-1:0] - 1'b1);
    end

    always_ff @(posedge core_clk) begin
        if (core_rst) begin
            active <= 1'b0;
            aborting <= 1'b0;
            done_seen <= 2'b00;
            done <= 1'b0;
            aborted <= 1'b0;
            error <= 1'b0;
            width_core <= 16'd0;
        end else begin
            done <= 1'b0;
            aborted <= 1'b0;

            if (start_fire) begin
                active <= 1'b1;
                aborting <= 1'b0;
                done_seen <= 2'b00;
                error <= 1'b0;
                width_core <= width_pixels;
            end else if (active) begin
                done_seen <= completion_next;
                if (abort)
                    aborting <= 1'b1;
                if (original_reader_error || styled_reader_error)
                    error <= 1'b1;

                // A frame reader pulses done when its final stream token has
                // entered the optional response FIFO.  Keep the pair active
                // until both FIFOs and both line stores have drained, so a
                // subsequent frame cannot interleave with residual tokens.
                if ((completion_next == 2'b11) && response_fifo_drained &&
                    original_empty && styled_empty) begin
                    active <= 1'b0;
                    done <= 1'b1;
                    aborted <= aborting || abort;
                end
            end
        end
    end

    always_ff @(posedge pixel_clk) begin
        if (pixel_rst) begin
            width_sync1_pixel <= 16'd0;
            width_sync2_pixel <= 16'd0;
        end else begin
            width_sync1_pixel <= width_core;
            width_sync2_pixel <= width_sync1_pixel;
        end
    end

    c1_axi_xrgb_frame_reader u_original_reader (
        .clk(core_clk), .rst(core_rst), .start(start_fire),
        .cancel(abort || aborting), .cfg_base_addr(original_base),
        .cfg_width_pixels(width_pixels), .cfg_height_lines(height_lines),
        .cfg_stride_bytes(original_stride), .busy(original_reader_busy),
        .done(original_reader_done), .error(original_reader_error),
        .m_valid(original_reader_stream_valid),
        .m_ready(original_reader_stream_ready),
        .m_rgb(original_reader_stream_rgb), .m_sof(original_reader_stream_sof),
        .m_eol(original_reader_stream_eol), .m_eof(original_reader_stream_eof),
        .m_x(original_reader_stream_x), .m_y(original_reader_stream_y),
        .m_axi_araddr(original_axi_araddr),
        .m_axi_arlen(original_axi_arlen),
         .m_axi_arsize(original_axi_arsize),
         .m_axi_arburst(original_axi_arburst),
         .m_axi_arvalid(original_reader_axi_arvalid),
         .m_axi_arready(original_axi_arready),
         .m_axi_ar_allow(original_reader_ar_allow),
         .m_axi_rdata(original_axi_rdata), .m_axi_rresp(original_axi_rresp),
        .m_axi_rlast(original_axi_rlast), .m_axi_rvalid(original_axi_rvalid),
        .m_axi_rready(original_axi_rready)
    );

    c1_axi_xrgb_frame_reader u_styled_reader (
        .clk(core_clk), .rst(core_rst), .start(start_fire),
        .cancel(abort || aborting), .cfg_base_addr(styled_base),
        .cfg_width_pixels(width_pixels), .cfg_height_lines(height_lines),
        .cfg_stride_bytes(styled_stride), .busy(styled_reader_busy),
        .done(styled_reader_done), .error(styled_reader_error),
        .m_valid(styled_reader_stream_valid),
        .m_ready(styled_reader_stream_ready),
        .m_rgb(styled_reader_stream_rgb), .m_sof(styled_reader_stream_sof),
        .m_eol(styled_reader_stream_eol), .m_eof(styled_reader_stream_eof),
        .m_x(styled_reader_stream_x), .m_y(styled_reader_stream_y),
        .m_axi_araddr(styled_axi_araddr), .m_axi_arlen(styled_axi_arlen),
         .m_axi_arsize(styled_axi_arsize),
         .m_axi_arburst(styled_axi_arburst),
         .m_axi_arvalid(styled_reader_axi_arvalid),
         .m_axi_arready(styled_axi_arready),
         .m_axi_ar_allow(styled_reader_ar_allow),
         .m_axi_rdata(styled_axi_rdata), .m_axi_rresp(styled_axi_rresp),
        .m_axi_rlast(styled_axi_rlast), .m_axi_rvalid(styled_axi_rvalid),
        .m_axi_rready(styled_axi_rready)
    );

    // The optional FIFO stores one complete maximum-length AXI burst as
    // pixel/coordinate/marker tokens.  Thus a held line store cannot leave
    // the shared ID-less read arbiter locked on an in-flight display burst.
    // The default generate branch is a wire-level bypass, preserving the
    // original correctness-first path and its resource baseline.
    generate
        if (ENABLE_RESPONSE_FIFO != 0) begin : GEN_RESPONSE_FIFOS
            assign original_fifo_in_valid = original_reader_stream_valid;
            assign original_fifo_in_data = {
                original_reader_stream_eof, original_reader_stream_eol,
                original_reader_stream_sof, original_reader_stream_y,
                original_reader_stream_x, original_reader_stream_rgb};
            assign original_reader_stream_ready = original_fifo_in_ready;
            c1_stream_fifo #(
                .DATA_WIDTH(RESPONSE_FIFO_WIDTH),
                .DEPTH(RESPONSE_FIFO_DEPTH)
            ) u_original_response_fifo (
                .clk(core_clk), .rst(core_rst),
                .in_valid(original_fifo_in_valid),
                .in_ready(original_fifo_in_ready),
                .in_data(original_fifo_in_data),
                .out_valid(original_fifo_out_valid),
                .out_ready(original_fifo_out_ready),
                .out_data(original_fifo_out_data),
                .full(), .empty(), .level(original_fifo_level)
            );
            assign original_stream_valid = original_fifo_out_valid;
            assign original_fifo_out_ready = original_stream_ready;
            assign original_stream_rgb = original_fifo_out_data[23:0];
            assign original_stream_x = original_fifo_out_data[39:24];
            assign original_stream_y = original_fifo_out_data[55:40];
            assign original_stream_sof = original_fifo_out_data[56];
            assign original_stream_eol = original_fifo_out_data[57];
            assign original_stream_eof = original_fifo_out_data[58];
            // Reserve space for a complete maximum-length burst before the
            // reader enters ST_AR.  The reader itself owns ARVALID and keeps
            // it stable until handshake; an already accepted burst is still
            // drained through the FIFO while hold_requests is asserted.
            // hold_requests freezes pixel-domain requests while a new pair
            // is being committed; it must not stop core-domain prefetch.  A
            // credit-only gate lets the reader continue filling the FIFO and
            // prevents the second-pair PREPARE state from deadlocking.
            assign original_reader_ar_allow =
                (original_fifo_level <= RESPONSE_FIFO_ADMISSION_LEVEL);
            assign original_axi_arvalid = original_reader_axi_arvalid;

            assign styled_fifo_in_valid = styled_reader_stream_valid;
            assign styled_fifo_in_data = {
                styled_reader_stream_eof, styled_reader_stream_eol,
                styled_reader_stream_sof, styled_reader_stream_y,
                styled_reader_stream_x, styled_reader_stream_rgb};
            assign styled_reader_stream_ready = styled_fifo_in_ready;
            c1_stream_fifo #(
                .DATA_WIDTH(RESPONSE_FIFO_WIDTH),
                .DEPTH(RESPONSE_FIFO_DEPTH)
            ) u_styled_response_fifo (
                .clk(core_clk), .rst(core_rst),
                .in_valid(styled_fifo_in_valid),
                .in_ready(styled_fifo_in_ready),
                .in_data(styled_fifo_in_data),
                .out_valid(styled_fifo_out_valid),
                .out_ready(styled_fifo_out_ready),
                .out_data(styled_fifo_out_data),
                .full(), .empty(), .level(styled_fifo_level)
            );
            assign styled_stream_valid = styled_fifo_out_valid;
            assign styled_fifo_out_ready = styled_stream_ready;
            assign styled_stream_rgb = styled_fifo_out_data[23:0];
            assign styled_stream_x = styled_fifo_out_data[39:24];
            assign styled_stream_y = styled_fifo_out_data[55:40];
            assign styled_stream_sof = styled_fifo_out_data[56];
            assign styled_stream_eol = styled_fifo_out_data[57];
            assign styled_stream_eof = styled_fifo_out_data[58];
            assign styled_reader_ar_allow =
                (styled_fifo_level <= RESPONSE_FIFO_ADMISSION_LEVEL);
            assign styled_axi_arvalid = styled_reader_axi_arvalid;
            assign response_fifo_drained =
                (original_fifo_level == 0) && (styled_fifo_level == 0);
        end else begin : GEN_RESPONSE_BYPASS
            assign original_reader_stream_ready = original_stream_ready;
            assign original_stream_valid = original_reader_stream_valid;
            assign original_stream_rgb = original_reader_stream_rgb;
            assign original_stream_sof = original_reader_stream_sof;
            assign original_stream_eol = original_reader_stream_eol;
            assign original_stream_eof = original_reader_stream_eof;
            assign original_stream_x = original_reader_stream_x;
            assign original_stream_y = original_reader_stream_y;
            assign original_reader_ar_allow = 1'b1;
            assign original_axi_arvalid = original_reader_axi_arvalid;
            assign styled_reader_stream_ready = styled_stream_ready;
            assign styled_stream_valid = styled_reader_stream_valid;
            assign styled_stream_rgb = styled_reader_stream_rgb;
            assign styled_stream_sof = styled_reader_stream_sof;
            assign styled_stream_eol = styled_reader_stream_eol;
            assign styled_stream_eof = styled_reader_stream_eof;
            assign styled_stream_x = styled_reader_stream_x;
            assign styled_stream_y = styled_reader_stream_y;
            assign styled_reader_ar_allow = 1'b1;
            assign styled_axi_arvalid = styled_reader_axi_arvalid;
            assign response_fifo_drained = 1'b1;
        end
    endgenerate

    c1_display_line_store_cdc #(
        .MAX_WIDTH(MAX_WIDTH), .X_BITS(X_BITS), .Y_BITS(Y_BITS)
    ) u_original_store (
        .core_clk(core_clk), .core_rst(core_rst),
        .s_valid(original_stream_valid), .s_ready(original_stream_ready),
        .s_rgb(original_stream_rgb),
        .s_x(original_stream_x[X_BITS-1:0]),
        .s_y(original_stream_y[Y_BITS-1:0]), .s_eol(original_stream_eol),
        .primed(original_primed), .empty(original_empty),
        .pixel_clk(pixel_clk), .pixel_rst(pixel_rst),
        .request(original_request), .request_x(original_request_x),
        .request_y(original_request_y), .request_last(original_request_last),
        .response_valid(original_response_valid),
        .response_rgb(original_rgb), .underflow_pulse(original_underflow)
    );

    c1_display_line_store_cdc #(
        .MAX_WIDTH(MAX_WIDTH), .X_BITS(X_BITS), .Y_BITS(Y_BITS)
    ) u_styled_store (
        .core_clk(core_clk), .core_rst(core_rst),
        .s_valid(styled_stream_valid), .s_ready(styled_stream_ready),
        .s_rgb(styled_stream_rgb),
        .s_x(styled_stream_x[X_BITS-1:0]),
        .s_y(styled_stream_y[Y_BITS-1:0]), .s_eol(styled_stream_eol),
        .primed(styled_primed), .empty(styled_empty),
        .pixel_clk(pixel_clk), .pixel_rst(pixel_rst),
        .request(styled_request), .request_x(styled_request_x),
        .request_y(styled_request_y), .request_last(styled_request_last),
        .response_valid(styled_response_valid), .response_rgb(styled_rgb),
        .underflow_pulse(styled_underflow)
    );

`ifndef SYNTHESIS
    // AXI VALID/payload stability guard.  This catches accidental external
    // gating of a reader request after it has been presented but before the
    // arbiter accepts it.  The FIFO credit gate is deliberately implemented
    // before ST_AR, so this assertion should remain silent in both branches.
    logic        original_ar_hold_q, styled_ar_hold_q;
    logic [44:0] original_ar_payload_q, styled_ar_payload_q;
    always_ff @(posedge core_clk) begin
        if (core_rst) begin
            original_ar_hold_q <= 1'b0;
            styled_ar_hold_q <= 1'b0;
            original_ar_payload_q <= '0;
            styled_ar_payload_q <= '0;
        end else begin
            if (original_ar_hold_q) begin
                if (!original_axi_arvalid ||
                    ({original_axi_araddr, original_axi_arlen,
                      original_axi_arsize, original_axi_arburst} !==
                     original_ar_payload_q))
                    $fatal(1, "display original ARVALID/payload changed while stalled");
            end
            if (styled_ar_hold_q) begin
                if (!styled_axi_arvalid ||
                    ({styled_axi_araddr, styled_axi_arlen,
                      styled_axi_arsize, styled_axi_arburst} !==
                     styled_ar_payload_q))
                    $fatal(1, "display styled ARVALID/payload changed while stalled");
            end

            if (original_axi_arvalid && !original_axi_arready) begin
                if (!original_ar_hold_q)
                    original_ar_payload_q <=
                        {original_axi_araddr, original_axi_arlen,
                         original_axi_arsize, original_axi_arburst};
                original_ar_hold_q <= 1'b1;
            end else begin
                original_ar_hold_q <= 1'b0;
            end
            if (styled_axi_arvalid && !styled_axi_arready) begin
                if (!styled_ar_hold_q)
                    styled_ar_payload_q <=
                        {styled_axi_araddr, styled_axi_arlen,
                         styled_axi_arsize, styled_axi_arburst};
                styled_ar_hold_q <= 1'b1;
            end else begin
                styled_ar_hold_q <= 1'b0;
            end
        end
    end

    initial begin
        if (ENABLE_RESPONSE_FIFO != 0 && RESPONSE_FIFO_DEPTH < 64)
            $fatal(1, "display response FIFO must hold one 16-beat burst");
    end

    always_ff @(posedge core_clk) begin
        if (!core_rst && start_fire &&
            ((width_pixels == 0) || (width_pixels > MAX_WIDTH)))
            $fatal(1, "display prefetch width outside line-store capacity");
    end
`endif

endmodule
