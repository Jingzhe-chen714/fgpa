`timescale 1ns/1ps

// One-pixel, combinational alpha blend.
//
// alpha=0 gives the background and alpha=255 gives the foreground.  Each
// native channel is evaluated independently as
//
//   round((fg*alpha + bg*(255-alpha)) / 255)
//
// where round is implemented as integer (numerator + 128) / 255.  The result
// is explicitly clipped to the native channel range (R5/G6/B5 for RGB565 or
// R8/G8/B8 for RGB888).
module alpha_blend_pixel #(
    parameter integer PIXEL_FORMAT = 0,
    parameter integer PIXEL_W = (PIXEL_FORMAT == 0) ? 16 : 24
) (
    input  logic [PIXEL_W-1:0] fg_pixel,
    input  logic [PIXEL_W-1:0] bg_pixel,
    input  logic [7:0]         alpha,
    output logic [PIXEL_W-1:0] out_pixel
);
    function automatic integer blend_channel (
        input integer fg_c,
        input integer bg_c,
        input integer alpha_c,
        input integer max_c
    );
        integer numerator;
        integer value;
        begin
            numerator = fg_c * alpha_c + bg_c * (255 - alpha_c) + 128;
            value = numerator / 255;
            if (value < 0)
                value = 0;
            else if (value > max_c)
                value = max_c;
            blend_channel = value;
        end
    endfunction

    integer r_value;
    integer g_value;
    integer b_value;

    always_comb begin
        out_pixel = '0;
        r_value = 0;
        g_value = 0;
        b_value = 0;

        if (PIXEL_FORMAT == 0) begin
            r_value = blend_channel(fg_pixel[15:11], bg_pixel[15:11], alpha, 31);
            g_value = blend_channel(fg_pixel[10:5],  bg_pixel[10:5],  alpha, 63);
            b_value = blend_channel(fg_pixel[4:0],   bg_pixel[4:0],   alpha, 31);
            out_pixel[15:11] = r_value[4:0];
            out_pixel[10:5]  = g_value[5:0];
            out_pixel[4:0]   = b_value[4:0];
        end else if (PIXEL_FORMAT == 1) begin
            r_value = blend_channel(fg_pixel[23:16], bg_pixel[23:16], alpha, 255);
            g_value = blend_channel(fg_pixel[15:8],  bg_pixel[15:8],  alpha, 255);
            b_value = blend_channel(fg_pixel[7:0],   bg_pixel[7:0],   alpha, 255);
            out_pixel[23:16] = r_value[7:0];
            out_pixel[15:8]  = g_value[7:0];
            out_pixel[7:0]   = b_value[7:0];
        end else begin
            // Unsupported formats are deterministic rather than inferred.
            out_pixel = fg_pixel;
        end
    end
endmodule


// Fixed-format convenience wrapper.
module alpha_blend_rgb565 (
    input  logic        [15:0] fg_pixel,
    input  logic        [15:0] bg_pixel,
    input  logic         [7:0] alpha,
    output logic        [15:0] out_pixel
);
    alpha_blend_pixel #(.PIXEL_FORMAT(0), .PIXEL_W(16)) u_impl (
        .fg_pixel(fg_pixel), .bg_pixel(bg_pixel), .alpha(alpha), .out_pixel(out_pixel)
    );
endmodule


module alpha_blend_rgb888 (
    input  logic        [23:0] fg_pixel,
    input  logic        [23:0] bg_pixel,
    input  logic         [7:0] alpha,
    output logic        [23:0] out_pixel
);
    alpha_blend_pixel #(.PIXEL_FORMAT(1), .PIXEL_W(24)) u_impl (
        .fg_pixel(fg_pixel), .bg_pixel(bg_pixel), .alpha(alpha), .out_pixel(out_pixel)
    );
endmodule

