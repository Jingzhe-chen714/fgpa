// Compatibility wrappers using the out_* / X_BITS / Y_BITS naming used by
// the case4 line-buffer, median, and display operators.  The underlying
// primitives in this directory retain m_* names so they can also be used in
// generic stream libraries.

`timescale 1ns/1ps

module rgb_unpack_stream_out #(
    parameter integer PIXEL_FORMAT = 0,
    parameter integer X_BITS = 12,
    parameter integer Y_BITS = 12
) (
    input  logic                  clk,
    input  logic                  rst,
    input  logic                  in_valid,
    input  logic                  in_sof,
    input  logic                  in_eol,
    input  logic                  in_eof,
    input  logic [X_BITS-1:0]     in_x,
    input  logic [Y_BITS-1:0]     in_y,
    input  logic [23:0]           in_pixel,
    output logic                  out_valid,
    output logic                  out_sof,
    output logic                  out_eol,
    output logic                  out_eof,
    output logic [X_BITS-1:0]     out_x,
    output logic [Y_BITS-1:0]     out_y,
    output logic [7:0]            out_r,
    output logic [7:0]            out_g,
    output logic [7:0]            out_b
);
    rgb_unpack_stream #(
        .PIXEL_FORMAT(PIXEL_FORMAT), .X_W(X_BITS), .Y_W(Y_BITS)
    ) u_unpack (
        .clk(clk), .rst(rst), .in_valid(in_valid), .in_sof(in_sof),
        .in_eol(in_eol), .in_eof(in_eof), .in_x(in_x), .in_y(in_y),
        .pixel_in(in_pixel), .m_valid(out_valid), .m_sof(out_sof),
        .m_eol(out_eol), .m_eof(out_eof), .m_x(out_x), .m_y(out_y),
        .m_r(out_r), .m_g(out_g), .m_b(out_b)
    );
endmodule


module gray_bt601_stream_out #(
    parameter integer X_BITS = 12,
    parameter integer Y_BITS = 12
) (
    input  logic                  clk,
    input  logic                  rst,
    input  logic                  in_valid,
    input  logic                  in_sof,
    input  logic                  in_eol,
    input  logic                  in_eof,
    input  logic [X_BITS-1:0]     in_x,
    input  logic [Y_BITS-1:0]     in_y,
    input  logic [7:0]            in_r,
    input  logic [7:0]            in_g,
    input  logic [7:0]            in_b,
    output logic                  out_valid,
    output logic                  out_sof,
    output logic                  out_eol,
    output logic                  out_eof,
    output logic [X_BITS-1:0]     out_x,
    output logic [Y_BITS-1:0]     out_y,
    output logic [7:0]            out_gray,
    output logic [16:0]           out_acc
);
    gray_bt601_stream #(.X_W(X_BITS), .Y_W(Y_BITS)) u_gray (
        .clk(clk), .rst(rst), .in_valid(in_valid), .in_sof(in_sof),
        .in_eol(in_eol), .in_eof(in_eof), .in_x(in_x), .in_y(in_y),
        .in_r(in_r), .in_g(in_g), .in_b(in_b), .m_valid(out_valid),
        .m_sof(out_sof), .m_eol(out_eol), .m_eof(out_eof), .m_x(out_x),
        .m_y(out_y), .m_gray(out_gray), .m_acc(out_acc)
    );
endmodule


module gray_rgb_stream_out #(
    parameter integer PIXEL_FORMAT = 0,
    parameter integer X_BITS = 12,
    parameter integer Y_BITS = 12
) (
    input  logic                  clk,
    input  logic                  rst,
    input  logic                  in_valid,
    input  logic                  in_sof,
    input  logic                  in_eol,
    input  logic                  in_eof,
    input  logic [X_BITS-1:0]     in_x,
    input  logic [Y_BITS-1:0]     in_y,
    input  logic [23:0]           in_pixel,
    output logic                  out_valid,
    output logic                  out_sof,
    output logic                  out_eol,
    output logic                  out_eof,
    output logic [X_BITS-1:0]     out_x,
    output logic [Y_BITS-1:0]     out_y,
    output logic [7:0]            out_gray,
    output logic [16:0]           out_acc
);
    gray_rgb_stream #(
        .PIXEL_FORMAT(PIXEL_FORMAT), .X_W(X_BITS), .Y_W(Y_BITS)
    ) u_gray_rgb (
        .clk(clk), .rst(rst), .in_valid(in_valid), .in_sof(in_sof),
        .in_eol(in_eol), .in_eof(in_eof), .in_x(in_x), .in_y(in_y),
        .pixel_in(in_pixel), .m_valid(out_valid), .m_sof(out_sof),
        .m_eol(out_eol), .m_eof(out_eof), .m_x(out_x), .m_y(out_y),
        .m_gray(out_gray), .m_acc(out_acc)
    );
endmodule

