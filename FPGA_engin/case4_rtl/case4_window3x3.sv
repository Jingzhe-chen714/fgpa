`timescale 1ns/1ps
// Vendor-neutral 3x3 window with exactly TWO single-row synchronous RAMs.
// Read the current x; one clock later write the preceding accepted x. RAM0
// stores the preceding row and RAM1 the row before that (cascaded old RAM0).
// For a contiguous raster, read x/write x-1; at wrap read 0/write WIDTH-1.
// During a valid gap only the pending write executes. Thus no same-address
// read/write mode is relied on. First-row history is never read, and explicit
// address guards also prevent collisions during a malformed/restarted stream.
// Accepted samples must follow row-major x/y order; gaps may occur anywhere.
// Memories have no reset/init. Reset aborts the pending write. A fresh frame
// overwrites both historical rows before any valid window is exposed.
// Two registered stages, unchanged from the original interface: input sampled
// at clock N produces its centered window at N+1. II=1, including row wrap.
module case4_window3x3 #(
    parameter integer DATA_BITS = 8, IMG_WIDTH = 1280,
    parameter integer IMG_HEIGHT = 720,
    parameter integer X_BITS = $clog2(IMG_WIDTH),
    parameter integer Y_BITS = $clog2(IMG_HEIGHT)
) (
    input wire clk, rst, in_valid,
    input wire [X_BITS-1:0] in_x,
    input wire [Y_BITS-1:0] in_y,
    input wire [DATA_BITS-1:0] in_pixel,
    output reg out_valid,
    output reg [X_BITS-1:0] out_x,
    output reg [Y_BITS-1:0] out_y,
    output reg [DATA_BITS-1:0] p00,p01,p02,p10,p11,p12,p20,p21,p22
);
    reg [DATA_BITS-1:0] row0 [0:IMG_WIDTH-1];
    reg [DATA_BITS-1:0] row1 [0:IMG_WIDTH-1];
    reg [DATA_BITS-1:0] q0,q1;
    reg valid_d;
    reg [X_BITS-1:0] x_d;
    reg [Y_BITS-1:0] y_d;
    reg [DATA_BITS-1:0] pixel_d;
    wire take = in_valid && !rst && in_x < IMG_WIDTH && in_y < IMG_HEIGHT;
    wire write_rows = valid_d && !rst;
    wire different_address = !write_rows || in_x != x_d;
    wire read_row0 = take && in_y != 0 && different_address;
    wire read_row1 = take && in_y >= 2 && different_address;
    // Each RAM has one synchronous read port and one delayed write port.
    // q0 still contains the OLD row0[x_d] on the edge that updates row1[x_d].
    // That value was read on the preceding clock at a different write address.
    // No synchronous read port or RAM contents are reset, preserving BRAM
    // inference independently of the resettable metadata/horizontal registers.
    always @(posedge clk) begin
        if (read_row0) q0 <= row0[in_x];
        if (read_row1) q1 <= row1[in_x];
        if (write_rows) row0[x_d] <= pixel_d;
        if (write_rows && y_d != 0) row1[x_d] <= q0;
    end
    wire [DATA_BITS-1:0] top_px = q1;
    wire [DATA_BITS-1:0] mid_px = q0;
    reg [DATA_BITS-1:0] t0,t1,m0,m1,b0,b1;
    always @(posedge clk) begin
        if (rst) begin
            valid_d<=0; x_d<=0; y_d<=0; pixel_d<=0;
            t0<=0; t1<=0; m0<=0; m1<=0; b0<=0; b1<=0;
            out_valid<=0; out_x<=0; out_y<=0;
            p00<=0; p01<=0; p02<=0; p10<=0; p11<=0; p12<=0;
            p20<=0; p21<=0; p22<=0;
        end else begin
            valid_d <= take;
            if (take) begin
                x_d<=in_x; y_d<=in_y; pixel_d<=in_pixel;
            end
            out_valid <= valid_d && x_d >= 2 && y_d >= 2;
            if (valid_d) begin
                out_x <= x_d == 0 ? 0 : x_d - 1'b1;
                out_y <= y_d == 0 ? 0 : y_d - 1'b1;
                p00<=t1; p01<=t0; p02<=top_px;
                p10<=m1; p11<=m0; p12<=mid_px;
                p20<=b1; p21<=b0; p22<=pixel_d;
                t1 <= x_d == 0 ? {DATA_BITS{1'b0}} : t0; t0<=top_px;
                m1 <= x_d == 0 ? {DATA_BITS{1'b0}} : m0; m0<=mid_px;
                b1 <= x_d == 0 ? {DATA_BITS{1'b0}} : b0; b0<=pixel_d;
            end
        end
    end
endmodule

