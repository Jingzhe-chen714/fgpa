`timescale 1ns/1ps

// Pixel format helpers used by the case2 render operators.
//
// PIXEL_FORMAT = 0 is RGB565 (R[15:11], G[10:5], B[4:0]).
// PIXEL_FORMAT = 1 is RGB888 (R[23:16], G[15:8], B[7:0]).
// The byte helpers use little-endian byte addresses: byte0 is the byte at
// the lowest address.  Thus RGB565 {byte1,byte0} and RGB888
// {byte2,byte1,byte0} are the canonical packed pixel values.

module pixel_pack #(
    parameter integer PIXEL_FORMAT = 0,
    parameter integer PIXEL_W = (PIXEL_FORMAT == 0) ? 16 : 24
) (
    input  logic [7:0]             r8,
    input  logic [7:0]             g8,
    input  logic [7:0]             b8,
    output logic [PIXEL_W-1:0]     pixel
);
    generate
        if (PIXEL_FORMAT == 0) begin : g_rgb565
            always_comb begin
                // Quantisation is truncation to the most significant bits.
                pixel = {r8[7:3], g8[7:2], b8[7:3]};
            end
        end else if (PIXEL_FORMAT == 1) begin : g_rgb888
            always_comb begin
                pixel = {r8, g8, b8};
            end
        end else begin : g_unsupported
            always_comb pixel = '0;
        end
    endgenerate
endmodule


module pixel_unpack #(
    parameter integer PIXEL_FORMAT = 0,
    parameter integer PIXEL_W = (PIXEL_FORMAT == 0) ? 16 : 24
) (
    input  logic [PIXEL_W-1:0]     pixel,
    output logic [7:0]             r8,
    output logic [7:0]             g8,
    output logic [7:0]             b8
);
    generate
        if (PIXEL_FORMAT == 0) begin : g_rgb565
            always_comb begin
                // Bit replication gives the usual full-range RGB expansion:
                // 5'bxxxxx -> xxxxxxxx and 6'bxxxxxx -> xxxxxxxx.
                r8 = {pixel[15:11], pixel[15:13]};
                g8 = {pixel[10:5],  pixel[10:9]};
                b8 = {pixel[4:0],   pixel[4:2]};
            end
        end else if (PIXEL_FORMAT == 1) begin : g_rgb888
            always_comb begin
                r8 = pixel[23:16];
                g8 = pixel[15:8];
                b8 = pixel[7:0];
            end
        end else begin : g_unsupported
            always_comb begin
                r8 = '0;
                g8 = '0;
                b8 = '0;
            end
        end
    endgenerate
endmodule


// Pack/unpack already-formed byte lanes.  These modules are useful at the
// framebuffer boundary where the memory bus is byte addressed.
module pixel_pack_bytes #(
    parameter integer PIXEL_FORMAT = 0,
    parameter integer PIXEL_W = (PIXEL_FORMAT == 0) ? 16 : 24
) (
    input  logic [7:0]             byte0,
    input  logic [7:0]             byte1,
    input  logic [7:0]             byte2,
    output logic [PIXEL_W-1:0]     pixel
);
    generate
        if (PIXEL_FORMAT == 0) begin : g_rgb565
            always_comb pixel = {byte1, byte0};
        end else if (PIXEL_FORMAT == 1) begin : g_rgb888
            always_comb pixel = {byte2, byte1, byte0};
        end else begin : g_unsupported
            always_comb pixel = '0;
        end
    endgenerate
endmodule


module pixel_unpack_bytes #(
    parameter integer PIXEL_FORMAT = 0,
    parameter integer PIXEL_W = (PIXEL_FORMAT == 0) ? 16 : 24
) (
    input  logic [PIXEL_W-1:0]     pixel,
    output logic [7:0]             byte0,
    output logic [7:0]             byte1,
    output logic [7:0]             byte2
);
    generate
        if (PIXEL_FORMAT == 0) begin : g_rgb565
            always_comb begin
                byte0 = pixel[7:0];
                byte1 = pixel[15:8];
                byte2 = 8'h00;
            end
        end else if (PIXEL_FORMAT == 1) begin : g_rgb888
            always_comb begin
                byte0 = pixel[7:0];
                byte1 = pixel[15:8];
                byte2 = pixel[23:16];
            end
        end else begin : g_unsupported
            always_comb begin
                byte0 = '0;
                byte1 = '0;
                byte2 = '0;
            end
        end
    endgenerate
endmodule


// Explicit native-width aliases make channel-level use self-documenting and
// avoid any ambiguity about RGB565 quantisation.
module rgb565_pack (
    input  logic [4:0]  r,
    input  logic [5:0]  g,
    input  logic [4:0]  b,
    output logic [15:0] pixel
);
    always_comb pixel = {r, g, b};
endmodule

module rgb565_unpack (
    input  logic [15:0] pixel,
    output logic [4:0]  r,
    output logic [5:0]  g,
    output logic [4:0]  b
);
    always_comb begin
        r = pixel[15:11];
        g = pixel[10:5];
        b = pixel[4:0];
    end
endmodule

module rgb888_pack (
    input  logic [7:0]  r,
    input  logic [7:0]  g,
    input  logic [7:0]  b,
    output logic [23:0] pixel
);
    always_comb pixel = {r, g, b};
endmodule

module rgb888_unpack (
    input  logic [23:0] pixel,
    output logic [7:0]  r,
    output logic [7:0]  g,
    output logic [7:0]  b
);
    always_comb begin
        r = pixel[23:16];
        g = pixel[15:8];
        b = pixel[7:0];
    end
endmodule

