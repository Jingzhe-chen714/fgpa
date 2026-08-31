`timescale 1ns/1ps

// One-entry elastic/ready-valid wrapper around color_key_pixel.
// rst_n is an active-low asynchronous reset.
module color_key #(
    parameter integer PIXEL_FORMAT = 0,
    parameter integer PIXEL_W = (PIXEL_FORMAT == 0) ? 16 : 24
) (
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic                 in_valid,
    output logic                 in_ready,
    input  logic [PIXEL_W-1:0]   src_pixel,
    input  logic [PIXEL_W-1:0]   background_pixel,
    input  logic [PIXEL_W-1:0]   key_pixel,
    output logic                 out_valid,
    input  logic                 out_ready,
    output logic [PIXEL_W-1:0]   out_pixel,
    output logic                 out_key_hit
);
    logic                       out_valid_q;
    logic [PIXEL_W-1:0]         out_pixel_q;
    logic                       out_key_hit_q;
    logic [PIXEL_W-1:0]         key_value;
    logic                       key_hit_value;

    color_key_pixel #(
        .PIXEL_FORMAT(PIXEL_FORMAT), .PIXEL_W(PIXEL_W)
    ) u_key_pixel (
        .src_pixel(src_pixel), .background_pixel(background_pixel),
        .key_pixel(key_pixel), .out_pixel(key_value), .key_hit(key_hit_value)
    );

    always_comb begin
        out_valid   = out_valid_q;
        out_pixel   = out_pixel_q;
        out_key_hit = out_key_hit_q;
        in_ready    = (~out_valid_q) | out_ready;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid_q   <= 1'b0;
            out_pixel_q   <= '0;
            out_key_hit_q <= 1'b0;
        end else if (in_ready) begin
            if (in_valid) begin
                out_valid_q   <= 1'b1;
                out_pixel_q   <= key_value;
                out_key_hit_q <= key_hit_value;
            end else if (out_ready) begin
                out_valid_q   <= 1'b0;
                out_key_hit_q <= 1'b0;
            end
        end
    end
endmodule


module color_key_stream #(
    parameter integer PIXEL_FORMAT = 0,
    parameter integer PIXEL_W = (PIXEL_FORMAT == 0) ? 16 : 24
) (
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic                 in_valid,
    output logic                 in_ready,
    input  logic [PIXEL_W-1:0]   src_pixel,
    input  logic [PIXEL_W-1:0]   background_pixel,
    input  logic [PIXEL_W-1:0]   key_pixel,
    output logic                 out_valid,
    input  logic                 out_ready,
    output logic [PIXEL_W-1:0]   out_pixel,
    output logic                 out_key_hit
);
    color_key #(.PIXEL_FORMAT(PIXEL_FORMAT), .PIXEL_W(PIXEL_W)) u_impl (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid), .in_ready(in_ready),
        .src_pixel(src_pixel), .background_pixel(background_pixel), .key_pixel(key_pixel),
        .out_valid(out_valid), .out_ready(out_ready),
        .out_pixel(out_pixel), .out_key_hit(out_key_hit)
    );
endmodule

