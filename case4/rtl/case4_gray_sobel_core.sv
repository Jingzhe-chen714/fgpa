`timescale 1ns/1ps

// Algorithm-only packed-pixel core:
//   RGB565/RGB888 -> fixed gray -> 3x3 window -> Sobel -> threshold.
//
// This is intentionally not a camera/HDMI top level.  It accepts a clean
// raster pixel stream and exposes the algorithm result with its centre
// coordinate.  The RGB path is not retained here; an eventual display mapper
// should delay the original RGB stream (or use a parallel RGB line buffer) and
// join it by (frame,x,y) before applying the overlay module.
//
// Reset convention at this boundary is rst high, synchronous.  The Sobel and
// threshold primitives use rst_n low, asynchronous reset internally, so the
// inversion is explicit at their instances.
//
// WINDOW_BACKEND selects the line-buffer implementation:
//   0 = portable simulation/reference array window3x3_gray
//   1 = Xilinx XPM BRAM window3x3_gray_xilinx_bram
// The Xilinx branch is intentionally explicit.  A later Efinix/other-FPGA
// port should replace the vendor memory wrapper, not silently mix RAM
// semantics into the arithmetic core.
module case4_gray_sobel_core #(
    parameter integer PIXEL_FORMAT = 0, // 0: RGB565, 1: RGB888
    parameter integer IMG_WIDTH    = 640,
    parameter integer IMG_HEIGHT   = 480,
    parameter integer X_BITS       = (IMG_WIDTH  <= 1) ? 1 : $clog2(IMG_WIDTH),
    parameter integer Y_BITS       = (IMG_HEIGHT <= 1) ? 1 : $clog2(IMG_HEIGHT),
    parameter integer MAG_W        = 11,
    parameter integer WINDOW_BACKEND = 0 // 0: array, 1: Xilinx BRAM/XPM
) (
    input  logic                   clk,
    input  logic                   rst,
    input  logic                   in_valid,
    input  logic                   in_sof,
    input  logic                   in_eol,
    input  logic                   in_eof,
    input  logic [X_BITS-1:0]      in_x,
    input  logic [Y_BITS-1:0]      in_y,
    input  logic [23:0]            in_pixel,
    input  logic [MAG_W-1:0]       threshold,

    output logic                   out_valid,
    output logic                   out_win_valid,
    output logic                   out_sof,
    output logic                   out_eol,
    output logic                   out_eof,
    output logic [X_BITS-1:0]      out_x,
    output logic [Y_BITS-1:0]      out_y,
    output logic signed [11:0]     out_gx,
    output logic signed [11:0]     out_gy,
    output logic [MAG_W-1:0]       out_magnitude,
    output logic                   out_edge
);
    logic gray_valid, gray_sof, gray_eol, gray_eof;
    logic [X_BITS-1:0] gray_x;
    logic [Y_BITS-1:0] gray_y;
    logic [7:0] gray_pixel;

    gray_rgb_stream_out #(
        .PIXEL_FORMAT(PIXEL_FORMAT), .X_BITS(X_BITS), .Y_BITS(Y_BITS)
    ) u_gray (
        .clk(clk), .rst(rst),
        .in_valid(in_valid), .in_sof(in_sof), .in_eol(in_eol), .in_eof(in_eof),
        .in_x(in_x), .in_y(in_y), .in_pixel(in_pixel),
        .out_valid(gray_valid), .out_sof(gray_sof), .out_eol(gray_eol),
        .out_eof(gray_eof), .out_x(gray_x), .out_y(gray_y),
        .out_gray(gray_pixel), .out_acc()
    );

    logic win_valid, win_sof, win_eol, win_eof;
    logic [X_BITS-1:0] win_x;
    logic [Y_BITS-1:0] win_y;
    logic [7:0] p00, p01, p02, p10, p11, p12, p20, p21, p22;

    generate
        if (WINDOW_BACKEND == 0) begin : g_array_window
            window3x3_gray #(
                .IMG_WIDTH(IMG_WIDTH), .IMG_HEIGHT(IMG_HEIGHT), .PIXEL_BITS(8),
                .X_BITS(X_BITS), .Y_BITS(Y_BITS)
            ) u_window (
                .clk(clk), .rst(rst),
                .in_valid(gray_valid), .in_sof(gray_sof), .in_eol(gray_eol),
                .in_eof(gray_eof), .in_x(gray_x), .in_y(gray_y),
                .in_pixel(gray_pixel),
                .out_valid(win_valid), .out_sof(win_sof), .out_eol(win_eol),
                .out_eof(win_eof), .out_x(win_x), .out_y(win_y),
                .out_p00(p00), .out_p01(p01), .out_p02(p02),
                .out_p10(p10), .out_p11(p11), .out_p12(p12),
                .out_p20(p20), .out_p21(p21), .out_p22(p22)
            );
        end else if (WINDOW_BACKEND == 1) begin : g_xilinx_bram_window
            window3x3_gray_xilinx_bram #(
                .IMG_WIDTH(IMG_WIDTH), .IMG_HEIGHT(IMG_HEIGHT), .PIXEL_BITS(8),
                .X_BITS(X_BITS), .Y_BITS(Y_BITS)
            ) u_window (
                .clk(clk), .rst(rst),
                .in_valid(gray_valid), .in_sof(gray_sof), .in_eol(gray_eol),
                .in_eof(gray_eof), .in_x(gray_x), .in_y(gray_y),
                .in_pixel(gray_pixel),
                .out_valid(win_valid), .out_sof(win_sof), .out_eol(win_eol),
                .out_eof(win_eof), .out_x(win_x), .out_y(win_y),
                .out_p00(p00), .out_p01(p01), .out_p02(p02),
                .out_p10(p10), .out_p11(p11), .out_p12(p12),
                .out_p20(p20), .out_p21(p21), .out_p22(p22)
            );
        end else begin : g_bad_window_backend
            initial $error("Unsupported WINDOW_BACKEND=%0d", WINDOW_BACKEND);
        end
    endgenerate

    logic sobel_valid, sobel_win_valid, sobel_sof, sobel_eol, sobel_eof;
    logic [X_BITS-1:0] sobel_x;
    logic [Y_BITS-1:0] sobel_y;
    logic signed [11:0] sobel_gx, sobel_gy;
    logic [MAG_W-1:0] sobel_mag;

    case4_sobel3x3 #(
        .PIX_W(8), .RGB_W(24), .X_W(X_BITS), .Y_W(Y_BITS),
        .PART_W(11), .GRAD_W(12), .MAG_W(MAG_W)
    ) u_sobel (
        .clk(clk), .rst_n(~rst),
        .in_valid(win_valid), .in_win_valid(win_valid),
        .in_sof(win_sof), .in_eol(win_eol), .in_eof(win_eof),
        .in_x(win_x), .in_y(win_y), .in_rgb(24'd0),
        .p00(p00), .p01(p01), .p02(p02),
        .p10(p10), .p11(p11), .p12(p12),
        .p20(p20), .p21(p21), .p22(p22),
        .out_valid(sobel_valid), .out_win_valid(sobel_win_valid),
        .out_sof(sobel_sof), .out_eol(sobel_eol), .out_eof(sobel_eof),
        .out_x(sobel_x), .out_y(sobel_y), .out_rgb(),
        .out_gx(sobel_gx), .out_gy(sobel_gy), .out_magnitude(sobel_mag)
    );

    logic [23:0] unused_rgb;
    case4_edge_threshold #(
        .MAG_W(MAG_W), .RGB_W(24), .X_W(X_BITS), .Y_W(Y_BITS)
    ) u_threshold (
        .clk(clk), .rst_n(~rst),
        .in_valid(sobel_valid), .in_win_valid(sobel_win_valid),
        .in_sof(sobel_sof), .in_eol(sobel_eol), .in_eof(sobel_eof),
        .in_x(sobel_x), .in_y(sobel_y), .in_rgb(24'd0),
        .in_magnitude(sobel_mag), .threshold(threshold),
        .out_valid(out_valid), .out_win_valid(out_win_valid),
        .out_sof(out_sof), .out_eol(out_eol), .out_eof(out_eof),
        .out_x(out_x), .out_y(out_y), .out_rgb(unused_rgb),
        .out_magnitude(out_magnitude), .out_edge(out_edge)
    );

    // The threshold primitive samples the Sobel result and registers the
    // final sideband/magnitude at the same edge.  Sampling the Sobel gradients
    // directly here therefore aligns them with threshold's output (an extra
    // delay would shift Gx/Gy by one pixel transaction).
    always_ff @(posedge clk) begin
        if (rst) begin
            out_gx   <= '0;
            out_gy   <= '0;
        end else begin
            out_gx   <= sobel_valid && sobel_win_valid ? sobel_gx : '0;
            out_gy   <= sobel_valid && sobel_win_valid ? sobel_gy : '0;
        end
    end
endmodule
