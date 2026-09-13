`timescale 1ns/1ps

// Explicit Xilinx entry point for the median -> Sobel cascade.  Both 3x3
// windows use the XPM/BRAM backend; replace the memory wrappers when moving
// to Efinix or another FPGA while keeping this stream/arithmetic interface.
module case4_gray_median_sobel_core_xilinx_bram #(
    parameter integer PIXEL_FORMAT = 0,
    parameter integer IMG_WIDTH    = 640,
    parameter integer IMG_HEIGHT   = 480,
    parameter integer X_BITS       = (IMG_WIDTH  <= 1) ? 1 : $clog2(IMG_WIDTH),
    parameter integer Y_BITS       = (IMG_HEIGHT <= 1) ? 1 : $clog2(IMG_HEIGHT),
    parameter integer MAG_W        = 11,
    parameter integer MEDIAN_PIPELINE_STAGES = 3
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
    case4_gray_median_sobel_core #(
        .PIXEL_FORMAT(PIXEL_FORMAT), .IMG_WIDTH(IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT), .X_BITS(X_BITS), .Y_BITS(Y_BITS),
        .MAG_W(MAG_W), .WINDOW_BACKEND(1), .MEDIAN_PIPELINE_STAGES(MEDIAN_PIPELINE_STAGES)
    ) u_core (
        .clk(clk), .rst(rst), .in_valid(in_valid), .in_sof(in_sof),
        .in_eol(in_eol), .in_eof(in_eof), .in_x(in_x), .in_y(in_y),
        .in_pixel(in_pixel), .threshold(threshold),
        .out_valid(out_valid), .out_win_valid(out_win_valid),
        .out_sof(out_sof), .out_eol(out_eol), .out_eof(out_eof),
        .out_x(out_x), .out_y(out_y), .out_gx(out_gx), .out_gy(out_gy),
        .out_magnitude(out_magnitude), .out_edge(out_edge)
    );
endmodule
