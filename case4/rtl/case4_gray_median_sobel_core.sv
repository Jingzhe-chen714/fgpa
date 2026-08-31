`timescale 1ns/1ps

// Algorithm-only median -> Sobel packed-pixel core.
//
// The first 3x3 window produces a median image whose samples are defined at
// original coordinates 1..W-2 / 1..H-2.  The stream is re-based to a local
// (W-2)x(H-2) raster before a second 3x3 window.  The second window's centre
// coordinate is then shifted back by +1, so final valid centres are
// (2..W-3, 2..H-3), as required by two cascaded VALID_ONLY operators.
//
// WINDOW_BACKEND:
//   0 = portable array windows (reference/XSIM)
//   1 = Xilinx XPM BRAM windows (current Vivado adapter)
// The arithmetic and coordinate contract are identical for both paths.
module case4_gray_median_sobel_core #(
    parameter integer PIXEL_FORMAT = 0, // 0: RGB565, 1: RGB888
    parameter integer IMG_WIDTH    = 640,
    parameter integer IMG_HEIGHT   = 480,
    parameter integer X_BITS       = (IMG_WIDTH  <= 1) ? 1 : $clog2(IMG_WIDTH),
    parameter integer Y_BITS       = (IMG_HEIGHT <= 1) ? 1 : $clog2(IMG_HEIGHT),
    parameter integer MAG_W        = 11,
    parameter integer WINDOW_BACKEND = 0
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
    localparam integer W2 = (IMG_WIDTH  > 2) ? IMG_WIDTH  - 2 : 1;
    localparam integer H2 = (IMG_HEIGHT > 2) ? IMG_HEIGHT - 2 : 1;
    localparam integer X2_BITS = (W2 <= 1) ? 1 : $clog2(W2);
    localparam integer Y2_BITS = (H2 <= 1) ? 1 : $clog2(H2);

    initial begin
        if (IMG_WIDTH < 5 || IMG_HEIGHT < 5)
            $error("case4_gray_median_sobel_core requires IMG_WIDTH/HEIGHT >= 5");
        if ((WINDOW_BACKEND != 0) && (WINDOW_BACKEND != 1))
            $error("Unsupported WINDOW_BACKEND=%0d", WINDOW_BACKEND);
    end

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

    // First window: full input raster -> median samples at original centres.
    logic fw_valid, fw_sof, fw_eol, fw_eof;
    logic [X_BITS-1:0] fw_x;
    logic [Y_BITS-1:0] fw_y;
    logic [7:0] fw_p00, fw_p01, fw_p02, fw_p10, fw_p11, fw_p12;
    logic [7:0] fw_p20, fw_p21, fw_p22;

    generate
        if (WINDOW_BACKEND == 0) begin : g_first_array
            window3x3_gray #(
                .IMG_WIDTH(IMG_WIDTH), .IMG_HEIGHT(IMG_HEIGHT), .PIXEL_BITS(8),
                .X_BITS(X_BITS), .Y_BITS(Y_BITS)
            ) u_window (
                .clk(clk), .rst(rst), .in_valid(gray_valid),
                .in_sof(gray_sof), .in_eol(gray_eol), .in_eof(gray_eof),
                .in_x(gray_x), .in_y(gray_y), .in_pixel(gray_pixel),
                .out_valid(fw_valid), .out_sof(fw_sof), .out_eol(fw_eol),
                .out_eof(fw_eof), .out_x(fw_x), .out_y(fw_y),
                .out_p00(fw_p00), .out_p01(fw_p01), .out_p02(fw_p02),
                .out_p10(fw_p10), .out_p11(fw_p11), .out_p12(fw_p12),
                .out_p20(fw_p20), .out_p21(fw_p21), .out_p22(fw_p22)
            );
        end else if (WINDOW_BACKEND == 1) begin : g_first_xilinx
            window3x3_gray_xilinx_bram #(
                .IMG_WIDTH(IMG_WIDTH), .IMG_HEIGHT(IMG_HEIGHT), .PIXEL_BITS(8),
                .X_BITS(X_BITS), .Y_BITS(Y_BITS)
            ) u_window (
                .clk(clk), .rst(rst), .in_valid(gray_valid),
                .in_sof(gray_sof), .in_eol(gray_eol), .in_eof(gray_eof),
                .in_x(gray_x), .in_y(gray_y), .in_pixel(gray_pixel),
                .out_valid(fw_valid), .out_sof(fw_sof), .out_eol(fw_eol),
                .out_eof(fw_eof), .out_x(fw_x), .out_y(fw_y),
                .out_p00(fw_p00), .out_p01(fw_p01), .out_p02(fw_p02),
                .out_p10(fw_p10), .out_p11(fw_p11), .out_p12(fw_p12),
                .out_p20(fw_p20), .out_p21(fw_p21), .out_p22(fw_p22)
            );
        end
    endgenerate

    logic med_valid, med_sof, med_eol, med_eof;
    logic [X_BITS-1:0] med_x;
    logic [Y_BITS-1:0] med_y;
    logic [7:0] med_pixel;

    median3x3_u8 #(
        .PIXEL_BITS(8), .X_BITS(X_BITS), .Y_BITS(Y_BITS),
        .REGISTER_OUTPUT(1'b1)
    ) u_median (
        .clk(clk), .rst(rst), .in_valid(fw_valid),
        .in_sof(fw_sof), .in_eol(fw_eol), .in_eof(fw_eof),
        .in_x(fw_x), .in_y(fw_y),
        .in_p00(fw_p00), .in_p01(fw_p01), .in_p02(fw_p02),
        .in_p10(fw_p10), .in_p11(fw_p11), .in_p12(fw_p12),
        .in_p20(fw_p20), .in_p21(fw_p21), .in_p22(fw_p22),
        .out_valid(med_valid), .out_sof(med_sof), .out_eol(med_eol),
        .out_eof(med_eof), .out_x(med_x), .out_y(med_y),
        .out_pixel(med_pixel)
    );

    // Re-base the sparse valid median stream to a dense (W-2)x(H-2) raster.
    // The first median sample is original (1,1), therefore local (0,0).
    logic med2_valid, med2_sof, med2_eol, med2_eof;
    logic [X2_BITS-1:0] med2_x;
    logic [Y2_BITS-1:0] med2_y;
    always_comb begin
        med2_valid = med_valid;
        med2_sof   = med_valid && med_sof;
        med2_eol   = med_valid && med_eol;
        med2_eof   = med_valid && med_eof;
        med2_x     = '0;
        med2_y     = '0;
        if (med_valid) begin
            med2_x = med_x - 1'b1;
            med2_y = med_y - 1'b1;
        end
    end

    // Second window over the median image.  Its local centre is one pixel
    // below the original coordinate offset; add +1 before Sobel/threshold.
    logic sw_valid, sw_sof, sw_eol, sw_eof;
    logic [X2_BITS-1:0] sw_x;
    logic [Y2_BITS-1:0] sw_y;
    logic [7:0] sw_p00, sw_p01, sw_p02, sw_p10, sw_p11, sw_p12;
    logic [7:0] sw_p20, sw_p21, sw_p22;

    generate
        if (WINDOW_BACKEND == 0) begin : g_second_array
            window3x3_gray #(
                .IMG_WIDTH(W2), .IMG_HEIGHT(H2), .PIXEL_BITS(8),
                .X_BITS(X2_BITS), .Y_BITS(Y2_BITS)
            ) u_window (
                .clk(clk), .rst(rst), .in_valid(med2_valid),
                .in_sof(med2_sof), .in_eol(med2_eol), .in_eof(med2_eof),
                .in_x(med2_x), .in_y(med2_y), .in_pixel(med_pixel),
                .out_valid(sw_valid), .out_sof(sw_sof), .out_eol(sw_eol),
                .out_eof(sw_eof), .out_x(sw_x), .out_y(sw_y),
                .out_p00(sw_p00), .out_p01(sw_p01), .out_p02(sw_p02),
                .out_p10(sw_p10), .out_p11(sw_p11), .out_p12(sw_p12),
                .out_p20(sw_p20), .out_p21(sw_p21), .out_p22(sw_p22)
            );
        end else if (WINDOW_BACKEND == 1) begin : g_second_xilinx
            window3x3_gray_xilinx_bram #(
                .IMG_WIDTH(W2), .IMG_HEIGHT(H2), .PIXEL_BITS(8),
                .X_BITS(X2_BITS), .Y_BITS(Y2_BITS)
            ) u_window (
                .clk(clk), .rst(rst), .in_valid(med2_valid),
                .in_sof(med2_sof), .in_eol(med2_eol), .in_eof(med2_eof),
                .in_x(med2_x), .in_y(med2_y), .in_pixel(med_pixel),
                .out_valid(sw_valid), .out_sof(sw_sof), .out_eol(sw_eol),
                .out_eof(sw_eof), .out_x(sw_x), .out_y(sw_y),
                .out_p00(sw_p00), .out_p01(sw_p01), .out_p02(sw_p02),
                .out_p10(sw_p10), .out_p11(sw_p11), .out_p12(sw_p12),
                .out_p20(sw_p20), .out_p21(sw_p21), .out_p22(sw_p22)
            );
        end
    endgenerate

    logic [X_BITS-1:0] sobel_x;
    logic [Y_BITS-1:0] sobel_y;
    always_comb begin
        sobel_x = '0;
        sobel_y = '0;
        if (sw_valid) begin
            sobel_x = sw_x + 1'b1;
            sobel_y = sw_y + 1'b1;
        end
    end

    logic sobel_valid, sobel_win_valid, sobel_sof, sobel_eol, sobel_eof;
    logic [X_BITS-1:0] sobel_x_d;
    logic [Y_BITS-1:0] sobel_y_d;
    logic signed [11:0] sobel_gx, sobel_gy;
    logic [MAG_W-1:0] sobel_mag;

    case4_sobel3x3 #(
        .PIX_W(8), .RGB_W(24), .X_W(X_BITS), .Y_W(Y_BITS),
        .PART_W(11), .GRAD_W(12), .MAG_W(MAG_W)
    ) u_sobel (
        .clk(clk), .rst_n(~rst),
        .in_valid(sw_valid), .in_win_valid(sw_valid),
        .in_sof(sw_sof), .in_eol(sw_eol), .in_eof(sw_eof),
        .in_x(sobel_x), .in_y(sobel_y), .in_rgb(24'd0),
        .p00(sw_p00), .p01(sw_p01), .p02(sw_p02),
        .p10(sw_p10), .p11(sw_p11), .p12(sw_p12),
        .p20(sw_p20), .p21(sw_p21), .p22(sw_p22),
        .out_valid(sobel_valid), .out_win_valid(sobel_win_valid),
        .out_sof(sobel_sof), .out_eol(sobel_eol), .out_eof(sobel_eof),
        .out_x(sobel_x_d), .out_y(sobel_y_d), .out_rgb(),
        .out_gx(sobel_gx), .out_gy(sobel_gy), .out_magnitude(sobel_mag)
    );

    logic [23:0] unused_rgb;
    case4_edge_threshold #(
        .MAG_W(MAG_W), .RGB_W(24), .X_W(X_BITS), .Y_W(Y_BITS)
    ) u_threshold (
        .clk(clk), .rst_n(~rst),
        .in_valid(sobel_valid), .in_win_valid(sobel_win_valid),
        .in_sof(sobel_sof), .in_eol(sobel_eol), .in_eof(sobel_eof),
        .in_x(sobel_x_d), .in_y(sobel_y_d), .in_rgb(24'd0),
        .in_magnitude(sobel_mag), .threshold(threshold),
        .out_valid(out_valid), .out_win_valid(out_win_valid),
        .out_sof(out_sof), .out_eol(out_eol), .out_eof(out_eof),
        .out_x(out_x), .out_y(out_y), .out_rgb(unused_rgb),
        .out_magnitude(out_magnitude), .out_edge(out_edge)
    );

    // Keep gradients aligned with the registered threshold result, matching
    // case4_gray_sobel_core's established scoreboard convention.
    always_ff @(posedge clk) begin
        if (rst) begin
            out_gx <= '0;
            out_gy <= '0;
        end else begin
            out_gx <= sobel_valid && sobel_win_valid ? sobel_gx : '0;
            out_gy <= sobel_valid && sobel_win_valid ? sobel_gy : '0;
        end
    end
endmodule
