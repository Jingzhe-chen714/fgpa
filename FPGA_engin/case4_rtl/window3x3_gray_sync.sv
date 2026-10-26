`timescale 1ns/1ps
// Vendor-neutral synchronous RAM window. Three rotating row banks keep the
// write bank separate from both historical read banks: no read-during-write
// behaviour or Xilinx primitive is assumed. Memories have no reset/init.
module window3x3_gray_sync #(
    parameter integer IMG_WIDTH = 1280,
    parameter integer IMG_HEIGHT = 720,
    parameter integer X_BITS = $clog2(IMG_WIDTH),
    parameter integer Y_BITS = $clog2(IMG_HEIGHT)
) (
    input wire clk, rst, in_valid,
    input wire [X_BITS-1:0] in_x,
    input wire [Y_BITS-1:0] in_y,
    input wire [7:0] in_pixel,
    output reg out_valid,
    output reg [X_BITS-1:0] out_x,
    output reg [Y_BITS-1:0] out_y,
    output reg [7:0] p00,p01,p02,p10,p11,p12,p20,p21,p22
);
    reg [7:0] row0 [0:IMG_WIDTH-1];
    reg [7:0] row1 [0:IMG_WIDTH-1];
    reg [7:0] row2 [0:IMG_WIDTH-1];
    reg [7:0] q0,q1,q2;
    reg [1:0] bank, bank_d;
    wire [1:0] active_bank = (in_x == 0 && in_y == 0) ? 2'd0 : bank;
    wire take = in_valid && !rst && in_x < IMG_WIDTH && in_y < IMG_HEIGHT;
    // Registered reads are intentionally outside the resettable control block.
    always @(posedge clk) begin
        if (take) begin
            if (active_bank == 0) row0[in_x] <= in_pixel;
            else q0 <= row0[in_x];
            if (active_bank == 1) row1[in_x] <= in_pixel;
            else q1 <= row1[in_x];
            if (active_bank == 2) row2[in_x] <= in_pixel;
            else q2 <= row2[in_x];
        end
    end
    reg valid_d;
    reg [X_BITS-1:0] x_d;
    reg [Y_BITS-1:0] y_d;
    reg [7:0] pixel_d;
    wire [7:0] top_px = bank_d == 0 ? q1 : bank_d == 1 ? q2 : q0;
    wire [7:0] mid_px = bank_d == 0 ? q2 : bank_d == 1 ? q0 : q1;
    reg [7:0] t0,t1,m0,m1,b0,b1;
    always @(posedge clk) begin
        if (rst) begin
            bank<=0; bank_d<=0; valid_d<=0; x_d<=0; y_d<=0; pixel_d<=0;
            t0<=0; t1<=0; m0<=0; m1<=0; b0<=0; b1<=0;
            out_valid<=0; out_x<=0; out_y<=0;
            p00<=0; p01<=0; p02<=0; p10<=0; p11<=0; p12<=0;
            p20<=0; p21<=0; p22<=0;
        end else begin
            valid_d <= take;
            if (take) begin
                x_d<=in_x; y_d<=in_y; pixel_d<=in_pixel; bank_d<=active_bank;
                if (in_x == IMG_WIDTH-1)
                    bank <= active_bank == 2 ? 0 : active_bank + 1'b1;
                else bank <= active_bank;
            end
            out_valid <= valid_d && x_d >= 2 && y_d >= 2;
            if (valid_d) begin
                out_x <= x_d == 0 ? 0 : x_d - 1'b1;
                out_y <= y_d == 0 ? 0 : y_d - 1'b1;
                p00<=t1; p01<=t0; p02<=top_px;
                p10<=m1; p11<=m0; p12<=mid_px;
                p20<=b1; p21<=b0; p22<=pixel_d;
                t1 <= x_d == 0 ? 8'd0 : t0; t0<=top_px;
                m1 <= x_d == 0 ? 8'd0 : m0; m0<=mid_px;
                b1 <= x_d == 0 ? 8'd0 : b0; b0<=pixel_d;
            end
        end
    end
endmodule
