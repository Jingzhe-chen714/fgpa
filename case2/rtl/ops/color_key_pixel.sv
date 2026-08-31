`timescale 1ns/1ps

// One-pixel color-key operation.
//
// A source pixel equal to key_pixel is transparent: the destination/background
// pixel is retained.  A non-matching source pixel is copied unchanged.  The
// comparison is made on RGB channel fields (rather than byte lanes), which
// makes the intended RGB565 byte order explicit and avoids false matches at a
// byte-swapped framebuffer boundary.
module color_key_pixel #(
    parameter integer PIXEL_FORMAT = 0,
    parameter integer PIXEL_W = (PIXEL_FORMAT == 0) ? 16 : 24
) (
    input  logic [PIXEL_W-1:0] src_pixel,
    input  logic [PIXEL_W-1:0] background_pixel,
    input  logic [PIXEL_W-1:0] key_pixel,
    output logic [PIXEL_W-1:0] out_pixel,
    output logic               key_hit
);
    always_comb begin
        if (PIXEL_FORMAT == 0) begin
            key_hit = (src_pixel[15:11] == key_pixel[15:11])
                    && (src_pixel[10:5]  == key_pixel[10:5])
                    && (src_pixel[4:0]   == key_pixel[4:0]);
        end else if (PIXEL_FORMAT == 1) begin
            key_hit = (src_pixel[23:16] == key_pixel[23:16])
                    && (src_pixel[15:8]  == key_pixel[15:8])
                    && (src_pixel[7:0]   == key_pixel[7:0]);
        end else begin
            key_hit = (src_pixel == key_pixel);
        end

        out_pixel = key_hit ? background_pixel : src_pixel;
    end
endmodule


module color_key_rgb565 (
    input  logic [15:0] src_pixel,
    input  logic [15:0] background_pixel,
    input  logic [15:0] key_pixel,
    output logic [15:0] out_pixel,
    output logic        key_hit
);
    color_key_pixel #(.PIXEL_FORMAT(0), .PIXEL_W(16)) u_impl (
        .src_pixel(src_pixel), .background_pixel(background_pixel),
        .key_pixel(key_pixel), .out_pixel(out_pixel), .key_hit(key_hit)
    );
endmodule

