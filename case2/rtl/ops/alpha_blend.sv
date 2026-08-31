`timescale 1ns/1ps

// One-entry elastic/ready-valid wrapper around alpha_blend_pixel.
// Input data is accepted on clk when in_valid && in_ready.  Output data is
// held until out_valid && out_ready.  A consumed output can be replaced by a
// new input in the same cycle (one pixel/cycle after the initial fill).
// rst_n is an active-low asynchronous reset.
module alpha_blend #(
    parameter integer PIXEL_FORMAT = 0,
    parameter integer PIXEL_W = (PIXEL_FORMAT == 0) ? 16 : 24
) (
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic                 in_valid,
    output logic                 in_ready,
    input  logic [PIXEL_W-1:0]   fg_pixel,
    input  logic [PIXEL_W-1:0]   bg_pixel,
    input  logic [7:0]           alpha,
    output logic                 out_valid,
    input  logic                 out_ready,
    output logic [PIXEL_W-1:0]   out_pixel
);
    logic                       out_valid_q;
    logic [PIXEL_W-1:0]         out_pixel_q;
    logic [PIXEL_W-1:0]         blend_value;

    alpha_blend_pixel #(
        .PIXEL_FORMAT(PIXEL_FORMAT), .PIXEL_W(PIXEL_W)
    ) u_blend_pixel (
        .fg_pixel(fg_pixel), .bg_pixel(bg_pixel), .alpha(alpha), .out_pixel(blend_value)
    );

    always_comb begin
        out_valid = out_valid_q;
        out_pixel = out_pixel_q;
        in_ready  = (~out_valid_q) | out_ready;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid_q <= 1'b0;
            out_pixel_q <= '0;
        end else if (in_ready) begin
            if (in_valid) begin
                out_valid_q <= 1'b1;
                out_pixel_q <= blend_value;
            end else if (out_ready) begin
                out_valid_q <= 1'b0;
            end
        end
    end
endmodule


// Descriptive alias for users who prefer the stream suffix.
module alpha_blend_stream #(
    parameter integer PIXEL_FORMAT = 0,
    parameter integer PIXEL_W = (PIXEL_FORMAT == 0) ? 16 : 24
) (
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic                 in_valid,
    output logic                 in_ready,
    input  logic [PIXEL_W-1:0]   fg_pixel,
    input  logic [PIXEL_W-1:0]   bg_pixel,
    input  logic [7:0]           alpha,
    output logic                 out_valid,
    input  logic                 out_ready,
    output logic [PIXEL_W-1:0]   out_pixel
);
    alpha_blend #(.PIXEL_FORMAT(PIXEL_FORMAT), .PIXEL_W(PIXEL_W)) u_impl (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid), .in_ready(in_ready),
        .fg_pixel(fg_pixel), .bg_pixel(bg_pixel), .alpha(alpha),
        .out_valid(out_valid), .out_ready(out_ready), .out_pixel(out_pixel)
    );
endmodule

