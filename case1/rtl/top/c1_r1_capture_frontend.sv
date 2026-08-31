`timescale 1ns/1ps

// Portable camera-clock to core-clock RAW10 capture frontend.
//
// The module deliberately stops at a backpressured RGB888 stream suitable for
// c1_axi_xrgb_frame_writer.  Frame-buffer ownership and address resolution are
// system-level responsibilities.  The async FIFO is bounded ingress elasticity,
// not a frame store: the default 2048 entries hold only about 3.2 lines of a
// 642-pixel sensor frame.  The source must honor camera_ready, or allocation and
// table lookup must complete within that bounded backlog.  Once begin_frame is
// accepted, the R1 ISP consumes the frame and an elastic output FIFO absorbs
// bounded DDR stalls.  If that FIFO cannot preserve the no-backpressure ISP
// contract, the frame is rejected with an explicit error.
module c1_r1_capture_frontend #(
    parameter integer SENSOR_WIDTH = 642,
    parameter integer SENSOR_HEIGHT = 482,
    parameter integer CAMERA_FIFO_DEPTH = 2048,
    parameter integer OUTPUT_FIFO_DEPTH = 128,
    parameter integer PIPELINE_HEADROOM = 32,
    parameter integer X_BITS = (SENSOR_WIDTH <= 1) ? 1 : $clog2(SENSOR_WIDTH),
    parameter integer Y_BITS = (SENSOR_HEIGHT <= 1) ? 1 : $clog2(SENSOR_HEIGHT)
) (
    input  logic                    camera_clk,
    input  logic                    camera_rst,
    input  logic                    camera_valid,
    output logic                    camera_ready,
    input  logic [9:0]              camera_raw10,
    input  logic [X_BITS-1:0]       camera_x,
    input  logic [Y_BITS-1:0]       camera_y,
    input  logic                    camera_sof,
    input  logic                    camera_eol,
    input  logic                    camera_eof,
    input  logic                    camera_clear_error,
    output logic                    camera_overflow,

    input  logic                    core_clk,
    input  logic                    core_rst,
    output logic                    frame_waiting,
    input  logic                    begin_frame,
    output logic                    begin_ready,
    input  logic                    drop_frame,
    // Maintenance mode used while capture admission is closed.  Any queued
    // data is discarded silently through EOF, including a mid-frame head left
    // by reset/disable.  Deassertion never truncates an in-progress cleanup.
    input  logic                    discard_idle,
    input  logic                    abort_frame,
    input  logic                    clear_error,
    output logic                    cleanup_busy,
    output logic                    frame_ingress_done,
    output logic                    frame_dropped,
    output logic                    frame_aborted,
    output logic                    capture_error,
    output logic [7:0]              capture_error_code,

    input  logic                    cfg_commit,
    output logic                    cfg_ready,
    input  logic [1:0]              cfg_bayer_pattern,
    input  logic                    cfg_roi_x_parity,
    input  logic                    cfg_roi_y_parity,
    input  logic [9:0]              cfg_black_r,
    input  logic [9:0]              cfg_black_gr,
    input  logic [9:0]              cfg_black_gb,
    input  logic [9:0]              cfg_black_b,
    input  logic [15:0]             cfg_awb_gain_r,
    input  logic [15:0]             cfg_awb_gain_g,
    input  logic [15:0]             cfg_awb_gain_b,
    input  logic signed [15:0]      cfg_ccm_rr,
    input  logic signed [15:0]      cfg_ccm_rg,
    input  logic signed [15:0]      cfg_ccm_rb,
    input  logic signed [15:0]      cfg_ccm_gr,
    input  logic signed [15:0]      cfg_ccm_gg,
    input  logic signed [15:0]      cfg_ccm_gb,
    input  logic signed [15:0]      cfg_ccm_br,
    input  logic signed [15:0]      cfg_ccm_bg,
    input  logic signed [15:0]      cfg_ccm_bb,
    input  logic signed [31:0]      cfg_ccm_offset_r,
    input  logic signed [31:0]      cfg_ccm_offset_g,
    input  logic signed [31:0]      cfg_ccm_offset_b,
    input  logic                    gamma_cfg_we,
    input  logic [9:0]              gamma_cfg_addr,
    input  logic [7:0]              gamma_cfg_data,
    output logic                    gamma_cfg_ready,

    output logic                    m_valid,
    input  logic                    m_ready,
    output logic [23:0]             m_rgb,
    output logic                    m_sof,
    output logic                    m_eol,
    output logic                    m_eof
);

    localparam integer CAMERA_DATA_W = 3 + X_BITS + Y_BITS + 10;
    localparam integer OUTPUT_DATA_W = 27;
    localparam integer OUTPUT_LEVEL_W = $clog2(OUTPUT_FIFO_DEPTH + 1);
    localparam integer STOP_LEVEL = OUTPUT_FIFO_DEPTH - PIPELINE_HEADROOM;
    localparam logic [OUTPUT_LEVEL_W-1:0] STOP_LEVEL_VALUE = STOP_LEVEL;

    typedef enum logic [2:0] {
        ST_IDLE,
        ST_STREAM,
        ST_WAIT_PIPE,
        ST_DRAIN_RAW,
        ST_RECOVER
    } state_t;

    state_t state;
    logic [CAMERA_DATA_W-1:0] camera_fifo_in_data;
    logic camera_fifo_valid;
    logic camera_fifo_ready;
    logic [CAMERA_DATA_W-1:0] camera_fifo_out_data;
    logic camera_fifo_out_valid;
    logic camera_fifo_out_ready;
    logic camera_fifo_full;
    logic camera_fifo_empty;

    logic fifo_sof;
    logic fifo_eol;
    logic fifo_eof;
    logic [X_BITS-1:0] fifo_x;
    logic [Y_BITS-1:0] fifo_y;
    logic [9:0] fifo_raw10;
    logic raw_fire;
    logic isp_in_valid;
    logic isp_out_valid;
    logic isp_out_sof;
    logic isp_out_eol;
    logic isp_out_eof;
    logic [X_BITS-1:0] isp_out_x;
    logic [Y_BITS-1:0] isp_out_y;
    logic [23:0] isp_out_rgb;

    logic output_fifo_in_valid;
    logic output_fifo_in_ready;
    logic [OUTPUT_DATA_W-1:0] output_fifo_in_data;
    logic output_fifo_full;
    logic output_fifo_empty;
    logic [OUTPUT_LEVEL_W-1:0] output_fifo_level;
    logic [OUTPUT_DATA_W-1:0] output_fifo_out_data;
    logic output_fifo_clear;
    logic input_has_headroom;

    logic camera_overflow_sync1;
    logic camera_overflow_sync2;
    logic camera_overflow_seen;
    logic drain_through_isp;

    always_comb begin
        camera_fifo_in_data = {camera_sof, camera_eol, camera_eof,
                               camera_x, camera_y, camera_raw10};
        camera_fifo_valid = camera_valid;
        camera_ready = camera_fifo_ready;

        {fifo_sof, fifo_eol, fifo_eof, fifo_x, fifo_y, fifo_raw10} =
            camera_fifo_out_data;
        frame_waiting = (state == ST_IDLE) && !discard_idle && !abort_frame &&
                        camera_fifo_out_valid &&
                        fifo_sof && cfg_ready && !cfg_commit &&
                        !gamma_cfg_we && !capture_error;
        begin_ready = frame_waiting;
        cleanup_busy = (state == ST_DRAIN_RAW) || (state == ST_RECOVER);
        input_has_headroom = (output_fifo_level <= STOP_LEVEL_VALUE);

        camera_fifo_out_ready = 1'b0;
        isp_in_valid = 1'b0;
        if (state == ST_STREAM) begin
            camera_fifo_out_ready = input_has_headroom;
            isp_in_valid = camera_fifo_out_valid && input_has_headroom;
        end else if (state == ST_DRAIN_RAW) begin
            camera_fifo_out_ready = 1'b1;
            // If this frame had already entered the no-backpressure ISP, feed
            // its remaining RAW pixels and EOF while suppressing RGB output.
            // Otherwise the Debayer frame state would never retire.
            isp_in_valid = camera_fifo_out_valid && drain_through_isp;
        end
        raw_fire = camera_fifo_out_valid && camera_fifo_out_ready;

        output_fifo_in_valid = isp_out_valid &&
            ((state == ST_STREAM) || (state == ST_WAIT_PIPE));
        output_fifo_in_data = {isp_out_sof, isp_out_eol, isp_out_eof,
                               isp_out_rgb};
        {m_sof, m_eol, m_eof, m_rgb} = output_fifo_out_data;
    end

    always_ff @(posedge camera_clk) begin
        if (camera_rst || camera_clear_error) begin
            camera_overflow <= 1'b0;
        end else if (camera_valid && !camera_fifo_ready) begin
            camera_overflow <= 1'b1;
        end
    end

    always_ff @(posedge core_clk) begin
        if (core_rst) begin
            camera_overflow_sync1 <= 1'b0;
            camera_overflow_sync2 <= 1'b0;
        end else begin
            camera_overflow_sync1 <= camera_overflow;
            camera_overflow_sync2 <= camera_overflow_sync1;
        end
    end

    always_ff @(posedge core_clk) begin
        if (core_rst) begin
            state <= ST_IDLE;
            frame_ingress_done <= 1'b0;
            frame_dropped <= 1'b0;
            frame_aborted <= 1'b0;
            capture_error <= 1'b0;
            capture_error_code <= 8'd0;
            output_fifo_clear <= 1'b0;
            camera_overflow_seen <= 1'b0;
            drain_through_isp <= 1'b0;
        end else begin
            frame_ingress_done <= 1'b0;
            frame_dropped <= 1'b0;
            frame_aborted <= 1'b0;
            output_fifo_clear <= 1'b0;

            if (clear_error) begin
                capture_error <= 1'b0;
                capture_error_code <= 8'd0;
                // The camera-domain clear reaches this synchronizer several
                // cycles later.  Mark the currently asserted level as seen so
                // it is not immediately re-reported, then re-arm only after
                // the synchronized sticky level has actually returned low.
                camera_overflow_seen <= camera_overflow_sync2;
            end else begin
                if (!camera_overflow_sync2)
                    camera_overflow_seen <= 1'b0;
                else if (!camera_overflow_seen) begin
                    camera_overflow_seen <= 1'b1;
                    capture_error <= 1'b1;
                    capture_error_code <= 8'h01;
                end
            end

            if (output_fifo_in_valid && !output_fifo_in_ready) begin
                capture_error <= 1'b1;
                capture_error_code <= 8'h03;
                output_fifo_clear <= 1'b1;
                if (state == ST_STREAM) begin
                    drain_through_isp <= 1'b1;
                    state <= ST_DRAIN_RAW;
                end else begin
                    drain_through_isp <= 1'b0;
                    state <= ST_RECOVER;
                end
            end else if (abort_frame && (state != ST_IDLE)) begin
                // Abort may be a level while AXI/control cleanup completes.
                // Transition and report it once; repeated cycles must not cut
                // short a raw-to-EOF drain or repeatedly pulse frame_aborted.
                output_fifo_clear <= 1'b1;
                if (state == ST_STREAM) begin
                    frame_aborted <= 1'b1;
                    drain_through_isp <= 1'b1;
                    state <= ST_DRAIN_RAW;
                end else if (state == ST_WAIT_PIPE) begin
                    frame_aborted <= 1'b1;
                    drain_through_isp <= 1'b0;
                    state <= ST_RECOVER;
                end else if ((state == ST_DRAIN_RAW) && raw_fire &&
                             fifo_eof) begin
                    // The FIFO continues popping while abort is held.  Do not
                    // miss the terminal marker merely because the request is
                    // a multi-cycle level.
                    state <= ST_RECOVER;
                end
            end else begin
                case (state)
                    ST_IDLE: begin
                        if ((discard_idle || abort_frame) &&
                            camera_fifo_out_valid) begin
                            // Maintenance discard is intentionally silent.  It
                            // accepts either SOF or a mid-frame FIFO head and
                            // restores the next admissible boundary at EOF.
                            output_fifo_clear <= 1'b1;
                            drain_through_isp <= 1'b0;
                            state <= ST_DRAIN_RAW;
                        end else if (drop_frame && camera_fifo_out_valid &&
                                     fifo_sof) begin
                            output_fifo_clear <= 1'b1;
                            frame_dropped <= 1'b1;
                            drain_through_isp <= 1'b0;
                            state <= ST_DRAIN_RAW;
                        end else if (begin_frame && begin_ready) begin
                            output_fifo_clear <= 1'b1;
                            drain_through_isp <= 1'b0;
                            state <= ST_STREAM;
                        end else if (camera_fifo_out_valid && !fifo_sof) begin
                            capture_error <= 1'b1;
                            capture_error_code <= 8'h02;
                            output_fifo_clear <= 1'b1;
                            frame_dropped <= 1'b1;
                            drain_through_isp <= 1'b0;
                            state <= ST_DRAIN_RAW;
                        end else if (begin_frame && !begin_ready) begin
                            capture_error <= 1'b1;
                            capture_error_code <= 8'h04;
                        end
                    end

                    ST_STREAM: begin
                        if (raw_fire && fifo_eof)
                            state <= ST_WAIT_PIPE;
                    end

                    ST_WAIT_PIPE: begin
                        if (isp_out_valid && isp_out_eof &&
                            output_fifo_in_ready) begin
                            frame_ingress_done <= 1'b1;
                            state <= ST_IDLE;
                        end
                    end

                    ST_DRAIN_RAW: begin
                        if (raw_fire && fifo_eof)
                            state <= ST_RECOVER;
                    end

                    ST_RECOVER: begin
                        if (cfg_ready) begin
                            drain_through_isp <= 1'b0;
                            state <= ST_IDLE;
                        end
                    end

                    default: state <= ST_IDLE;
                endcase
            end
        end
    end

    c1_async_stream_fifo #(
        .DATA_WIDTH(CAMERA_DATA_W), .DEPTH(CAMERA_FIFO_DEPTH)
    ) u_camera_fifo (
        .wr_clk(camera_clk), .wr_rst(camera_rst),
        .in_valid(camera_fifo_valid), .in_ready(camera_fifo_ready),
        .in_data(camera_fifo_in_data), .wr_full(camera_fifo_full),
        .rd_clk(core_clk), .rd_rst(core_rst),
        .out_valid(camera_fifo_out_valid), .out_ready(camera_fifo_out_ready),
        .out_data(camera_fifo_out_data), .rd_empty(camera_fifo_empty)
    );

    c1_r1_isp_pipeline #(
        .FRAME_WIDTH(SENSOR_WIDTH), .FRAME_HEIGHT(SENSOR_HEIGHT),
        .X_BITS(X_BITS), .Y_BITS(Y_BITS)
    ) u_isp (
        .clk(core_clk), .rst(core_rst),
        .in_valid(isp_in_valid), .in_sof(fifo_sof), .in_eol(fifo_eol),
        .in_eof(fifo_eof), .in_x(fifo_x), .in_y(fifo_y),
        .in_raw10(fifo_raw10),
        .cfg_commit(cfg_commit), .cfg_ready(cfg_ready),
        .cfg_bayer_pattern(cfg_bayer_pattern),
        .cfg_roi_x_parity(cfg_roi_x_parity),
        .cfg_roi_y_parity(cfg_roi_y_parity),
        .cfg_black_r(cfg_black_r), .cfg_black_gr(cfg_black_gr),
        .cfg_black_gb(cfg_black_gb), .cfg_black_b(cfg_black_b),
        .cfg_awb_gain_r(cfg_awb_gain_r), .cfg_awb_gain_g(cfg_awb_gain_g),
        .cfg_awb_gain_b(cfg_awb_gain_b),
        .cfg_ccm_rr(cfg_ccm_rr), .cfg_ccm_rg(cfg_ccm_rg),
        .cfg_ccm_rb(cfg_ccm_rb), .cfg_ccm_gr(cfg_ccm_gr),
        .cfg_ccm_gg(cfg_ccm_gg), .cfg_ccm_gb(cfg_ccm_gb),
        .cfg_ccm_br(cfg_ccm_br), .cfg_ccm_bg(cfg_ccm_bg),
        .cfg_ccm_bb(cfg_ccm_bb),
        .cfg_ccm_offset_r(cfg_ccm_offset_r),
        .cfg_ccm_offset_g(cfg_ccm_offset_g),
        .cfg_ccm_offset_b(cfg_ccm_offset_b),
        .gamma_cfg_we(gamma_cfg_we), .gamma_cfg_addr(gamma_cfg_addr),
        .gamma_cfg_data(gamma_cfg_data),
        .gamma_cfg_ready(gamma_cfg_ready),
        .out_valid(isp_out_valid), .out_sof(isp_out_sof),
        .out_eol(isp_out_eol), .out_eof(isp_out_eof),
        .out_x(isp_out_x), .out_y(isp_out_y), .out_rgb888(isp_out_rgb)
    );

    c1_stream_fifo #(
        .DATA_WIDTH(OUTPUT_DATA_W), .DEPTH(OUTPUT_FIFO_DEPTH),
        .LEVEL_WIDTH(OUTPUT_LEVEL_W)
    ) u_output_fifo (
        .clk(core_clk), .rst(core_rst || output_fifo_clear),
        .in_valid(output_fifo_in_valid), .in_ready(output_fifo_in_ready),
        .in_data(output_fifo_in_data), .out_valid(m_valid),
        .out_ready(m_ready), .out_data(output_fifo_out_data),
        .full(output_fifo_full), .empty(output_fifo_empty),
        .level(output_fifo_level)
    );

`ifndef SYNTHESIS
    initial begin
        if (CAMERA_FIFO_DEPTH < 16)
            $fatal(1, "capture camera FIFO too small");
        if ((OUTPUT_FIFO_DEPTH < 16) ||
            (PIPELINE_HEADROOM < 8) ||
            (PIPELINE_HEADROOM >= OUTPUT_FIFO_DEPTH))
            $fatal(1, "capture output FIFO/headroom parameters invalid");
    end
`endif

endmodule
