// Convenience wrapper: 3x3 line-buffer window followed by a median filter.
// The window generator uses VALID_ONLY borders and contributes one cycle of
// latency; median3x3_u8 contributes one more cycle by default.

`timescale 1ns/1ps

module window3x3_median #(
    parameter integer IMG_WIDTH  = 640,
    parameter integer IMG_HEIGHT = 480,
    parameter integer PIXEL_BITS = 8,
    parameter integer X_BITS = (IMG_WIDTH  <= 1) ? 1 : $clog2(IMG_WIDTH),
    parameter integer Y_BITS = (IMG_HEIGHT <= 1) ? 1 : $clog2(IMG_HEIGHT),
    parameter bit MEDIAN_REGISTER_OUTPUT = 1'b1
) (
    input  logic                   clk,
    input  logic                   rst,

    input  logic                   in_valid,
    input  logic                   in_sof,
    input  logic                   in_eol,
    input  logic                   in_eof,
    input  logic [X_BITS-1:0]      in_x,
    input  logic [Y_BITS-1:0]      in_y,
    input  logic [PIXEL_BITS-1:0] in_pixel,

    output logic                   out_valid,
    output logic                   out_sof,
    output logic                   out_eol,
    output logic                   out_eof,
    output logic [X_BITS-1:0]      out_x,
    output logic [Y_BITS-1:0]      out_y,
    output logic [PIXEL_BITS-1:0] out_pixel,

    // Expose the window for a parallel Sobel branch or waveform inspection.
    output logic                   window_valid,
    output logic                   window_sof,
    output logic                   window_eol,
    output logic                   window_eof,
    output logic [X_BITS-1:0]      window_x,
    output logic [Y_BITS-1:0]      window_y,
    output logic [PIXEL_BITS-1:0] window_p00,
    output logic [PIXEL_BITS-1:0] window_p01,
    output logic [PIXEL_BITS-1:0] window_p02,
    output logic [PIXEL_BITS-1:0] window_p10,
    output logic [PIXEL_BITS-1:0] window_p11,
    output logic [PIXEL_BITS-1:0] window_p12,
    output logic [PIXEL_BITS-1:0] window_p20,
    output logic [PIXEL_BITS-1:0] window_p21,
    output logic [PIXEL_BITS-1:0] window_p22
);

    window3x3_gray #(
        .IMG_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT),
        .PIXEL_BITS(PIXEL_BITS),
        .X_BITS    (X_BITS),
        .Y_BITS    (Y_BITS)
    ) u_window (
        .clk      (clk),
        .rst      (rst),
        .in_valid (in_valid),
        .in_sof   (in_sof),
        .in_eol   (in_eol),
        .in_eof   (in_eof),
        .in_x     (in_x),
        .in_y     (in_y),
        .in_pixel (in_pixel),
        .out_valid(window_valid),
        .out_sof  (window_sof),
        .out_eol  (window_eol),
        .out_eof  (window_eof),
        .out_x    (window_x),
        .out_y    (window_y),
        .out_p00  (window_p00),
        .out_p01  (window_p01),
        .out_p02  (window_p02),
        .out_p10  (window_p10),
        .out_p11  (window_p11),
        .out_p12  (window_p12),
        .out_p20  (window_p20),
        .out_p21  (window_p21),
        .out_p22  (window_p22)
    );

    median3x3_u8 #(
        .PIXEL_BITS     (PIXEL_BITS),
        .X_BITS         (X_BITS),
        .Y_BITS         (Y_BITS),
        .REGISTER_OUTPUT(MEDIAN_REGISTER_OUTPUT)
    ) u_median (
        .clk      (clk),
        .rst      (rst),
        .in_valid (window_valid),
        .in_sof   (window_sof),
        .in_eol   (window_eol),
        .in_eof   (window_eof),
        .in_x     (window_x),
        .in_y     (window_y),
        .in_p00   (window_p00),
        .in_p01   (window_p01),
        .in_p02   (window_p02),
        .in_p10   (window_p10),
        .in_p11   (window_p11),
        .in_p12   (window_p12),
        .in_p20   (window_p20),
        .in_p21   (window_p21),
        .in_p22   (window_p22),
        .out_valid(out_valid),
        .out_sof  (out_sof),
        .out_eol  (out_eol),
        .out_eof  (out_eof),
        .out_x    (out_x),
        .out_y    (out_y),
        .out_pixel(out_pixel)
    );

endmodule

