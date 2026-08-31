`timescale 1ns/1ps
//
// Case 4 image-processing operators.
//
// The modules in this file deliberately stop at a pixel-stream boundary.  A
// line-buffer/window block supplies the nine pixels and asserts in_win_valid
// only when the complete 3x3 neighbourhood is usable.  The arithmetic never
// invents a border policy: invalid windows are marked invalid and their data
// outputs are driven to zero.
//
// Sideband convention
// -------------------
// in_valid means that the input pixel/coordinate transfer is present.  The
// window-valid qualifier is separate, because the first/last row and column
// often still need to carry SOF/EOL/EOF timing.  out_valid is the delayed
// transfer-valid and out_win_valid is the delayed algorithm-valid qualifier.
// SOF/EOL/EOF/x/y follow in_valid through exactly the same registers as the
// pixel data.  Downstream arithmetic should use out_win_valid; a display
// mapper may use out_valid to retain frame timing and pass border RGB through.
//
// Reset is active-low and asynchronous.  All state is reset to zero.
//
// Default arithmetic widths are for 8-bit pixels:
//   partials: 11-bit signed, Gx/Gy: 12-bit signed, L1 magnitude: 11-bit.
// The parameters retain enough headroom for other unsigned pixel widths.
//

module case4_sobel3x3 #(
    parameter integer PIX_W  = 8,
    parameter integer RGB_W  = 24,
    parameter integer X_W    = 12,
    parameter integer Y_W    = 12,
    parameter integer PART_W = PIX_W + 3,
    parameter integer GRAD_W = PIX_W + 4,
    parameter integer MAG_W  = PIX_W + 3
) (
    input  logic                   clk,
    input  logic                   rst_n,

    input  logic                   in_valid,
    input  logic                   in_win_valid,
    input  logic                   in_sof,
    input  logic                   in_eol,
    input  logic                   in_eof,
    input  logic [X_W-1:0]         in_x,
    input  logic [Y_W-1:0]         in_y,
    input  logic [RGB_W-1:0]       in_rgb,

    // 3x3 window.  p00 is the upper-left value and p22 the lower-right;
    // the centre pixel is p11.  Coordinates refer to the centre pixel.
    input  logic [PIX_W-1:0]       p00,
    input  logic [PIX_W-1:0]       p01,
    input  logic [PIX_W-1:0]       p02,
    input  logic [PIX_W-1:0]       p10,
    input  logic [PIX_W-1:0]       p11,
    input  logic [PIX_W-1:0]       p12,
    input  logic [PIX_W-1:0]       p20,
    input  logic [PIX_W-1:0]       p21,
    input  logic [PIX_W-1:0]       p22,

    output logic                   out_valid,
    output logic                   out_win_valid,
    output logic                   out_sof,
    output logic                   out_eol,
    output logic                   out_eof,
    output logic [X_W-1:0]         out_x,
    output logic [Y_W-1:0]         out_y,
    output logic [RGB_W-1:0]       out_rgb,
    output logic signed [GRAD_W-1:0] out_gx,
    output logic signed [GRAD_W-1:0] out_gy,
    output logic [MAG_W-1:0]       out_magnitude
);

    // A partial difference is deliberately widened before subtraction and
    // before the *2 shift.  This avoids the common unsigned 8-bit wraparound
    // (for example, 0 - 255 must be -255, not 1).
    logic signed [PART_W-1:0] gx_top_s1;
    logic signed [PART_W-1:0] gx_mid_s1;
    logic signed [PART_W-1:0] gx_bottom_s1;
    logic signed [PART_W-1:0] gy_top_s1;
    logic signed [PART_W-1:0] gy_mid_s1;
    logic signed [PART_W-1:0] gy_bottom_s1;

    logic                     valid_s1;
    logic                     win_valid_s1;
    logic                     sof_s1;
    logic                     eol_s1;
    logic                     eof_s1;
    logic [X_W-1:0]           x_s1;
    logic [Y_W-1:0]           y_s1;
    logic [RGB_W-1:0]         rgb_s1;

    logic signed [GRAD_W-1:0] gx_s2;
    logic signed [GRAD_W-1:0] gy_s2;
    logic                     valid_s2;
    logic                     win_valid_s2;
    logic                     sof_s2;
    logic                     eol_s2;
    logic                     eof_s2;
    logic [X_W-1:0]           x_s2;
    logic [Y_W-1:0]           y_s2;
    logic [RGB_W-1:0]         rgb_s2;

    localparam integer SUM_W = PART_W + 2;
    logic signed [SUM_W-1:0] gx_sum;
    logic signed [SUM_W-1:0] gy_sum;
    logic signed [GRAD_W-1:0] gx_calc;
    logic signed [GRAD_W-1:0] gy_calc;
    logic [GRAD_W-1:0] abs_gx_calc;
    logic [GRAD_W-1:0] abs_gy_calc;
    logic [GRAD_W:0]   magnitude_calc_ext;

    // Sign-extension helper.  SUM_W is larger than PART_W by construction.
    function automatic logic signed [SUM_W-1:0] part_to_sum(
        input logic signed [PART_W-1:0] value
    );
        begin
            part_to_sum = {{(SUM_W-PART_W){value[PART_W-1]}}, value};
        end
    endfunction

    always_comb begin
        gx_sum = part_to_sum(gx_top_s1)
               + part_to_sum(gx_mid_s1)
               + part_to_sum(gx_bottom_s1);
        gy_sum = part_to_sum(gy_top_s1)
               + part_to_sum(gy_mid_s1)
               + part_to_sum(gy_bottom_s1);

        // The mathematical range for 8-bit pixels is -1020..+1020.  The
        // explicit assignment truncates only unused headroom, not data bits.
        gx_calc = gx_sum;
        gy_calc = gy_sum;

        // Magnitude is formed from the registered stage-2 gradients.  Using
        // gx_calc here would make magnitude one pixel ahead of out_gx/out_gy
        // because gx_calc is driven directly by the stage-1 partials.
        if (gx_s2[GRAD_W-1])
            abs_gx_calc = $unsigned(-gx_s2);
        else
            abs_gx_calc = $unsigned(gx_s2);
        if (gy_s2[GRAD_W-1])
            abs_gy_calc = $unsigned(-gy_s2);
        else
            abs_gy_calc = $unsigned(gy_s2);

        magnitude_calc_ext = abs_gx_calc + abs_gy_calc;
    end

    // Three arithmetic stages:
    //   stage 1: six signed partial differences
    //   stage 2: complete Gx/Gy
    //   stage 3: absolute values and L1 magnitude (outputs)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gx_top_s1       <= '0;
            gx_mid_s1       <= '0;
            gx_bottom_s1    <= '0;
            gy_top_s1       <= '0;
            gy_mid_s1       <= '0;
            gy_bottom_s1    <= '0;
            valid_s1        <= 1'b0;
            win_valid_s1    <= 1'b0;
            sof_s1          <= 1'b0;
            eol_s1          <= 1'b0;
            eof_s1          <= 1'b0;
            x_s1            <= '0;
            y_s1            <= '0;
            rgb_s1          <= '0;

            gx_s2           <= '0;
            gy_s2           <= '0;
            valid_s2        <= 1'b0;
            win_valid_s2    <= 1'b0;
            sof_s2          <= 1'b0;
            eol_s2          <= 1'b0;
            eof_s2          <= 1'b0;
            x_s2            <= '0;
            y_s2            <= '0;
            rgb_s2          <= '0;

            out_valid       <= 1'b0;
            out_win_valid   <= 1'b0;
            out_sof         <= 1'b0;
            out_eol         <= 1'b0;
            out_eof         <= 1'b0;
            out_x           <= '0;
            out_y           <= '0;
            out_rgb         <= '0;
            out_gx          <= '0;
            out_gy          <= '0;
            out_magnitude   <= '0;
        end else begin
            // Stage 1: widen before subtracting.  The mid terms are shifted
            // in the widened signed domain, so -255*2 remains -510.
            gx_top_s1       <= $signed({{(PART_W-PIX_W){1'b0}}, p02})
                             - $signed({{(PART_W-PIX_W){1'b0}}, p00});
            gx_mid_s1       <= ($signed({{(PART_W-PIX_W){1'b0}}, p12})
                             -  $signed({{(PART_W-PIX_W){1'b0}}, p10})) <<< 1;
            gx_bottom_s1    <= $signed({{(PART_W-PIX_W){1'b0}}, p22})
                             - $signed({{(PART_W-PIX_W){1'b0}}, p20});
            gy_top_s1       <= $signed({{(PART_W-PIX_W){1'b0}}, p20})
                             - $signed({{(PART_W-PIX_W){1'b0}}, p00});
            gy_mid_s1       <= ($signed({{(PART_W-PIX_W){1'b0}}, p21})
                             -  $signed({{(PART_W-PIX_W){1'b0}}, p01})) <<< 1;
            gy_bottom_s1    <= $signed({{(PART_W-PIX_W){1'b0}}, p22})
                             - $signed({{(PART_W-PIX_W){1'b0}}, p02});

            valid_s1        <= in_valid;
            win_valid_s1    <= in_valid && in_win_valid;
            sof_s1          <= in_valid && in_sof;
            eol_s1          <= in_valid && in_eol;
            eof_s1          <= in_valid && in_eof;
            x_s1            <= in_x;
            y_s1            <= in_y;
            rgb_s1          <= in_rgb;

            // Stage 2: complete signed gradients.  The sideband is delayed
            // even for invalid windows, preserving the video timing stream.
            gx_s2           <= gx_calc;
            gy_s2           <= gy_calc;
            valid_s2        <= valid_s1;
            win_valid_s2    <= win_valid_s1;
            sof_s2          <= sof_s1;
            eol_s2          <= eol_s1;
            eof_s2          <= eof_s1;
            x_s2            <= x_s1;
            y_s2            <= y_s1;
            rgb_s2          <= rgb_s1;

            // Stage 3: output values and sideband.  Invalid windows are
            // zeroed, making border behaviour explicit and deterministic.
            out_valid       <= valid_s2;
            out_win_valid   <= win_valid_s2;
            out_sof         <= sof_s2;
            out_eol         <= eol_s2;
            out_eof         <= eof_s2;
            out_x           <= x_s2;
            out_y           <= y_s2;
            out_rgb         <= rgb_s2;
            if (win_valid_s2) begin
                out_gx        <= gx_s2;
                out_gy        <= gy_s2;
                out_magnitude <= magnitude_calc_ext[MAG_W-1:0];
            end else begin
                out_gx        <= '0;
                out_gy        <= '0;
                out_magnitude <= '0;
            end
        end
    end

endmodule


// Threshold stage.  It has one registered stage and passes the RGB and
// timing sideband alongside the edge decision.  threshold is unsigned and
// may be any value representable by MAG_W; values above the Sobel maximum
// naturally produce no edges.
module case4_edge_threshold #(
    parameter integer MAG_W = 11,
    parameter integer RGB_W = 24,
    parameter integer X_W   = 12,
    parameter integer Y_W   = 12
) (
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic                 in_valid,
    input  logic                 in_win_valid,
    input  logic                 in_sof,
    input  logic                 in_eol,
    input  logic                 in_eof,
    input  logic [X_W-1:0]       in_x,
    input  logic [Y_W-1:0]       in_y,
    input  logic [RGB_W-1:0]     in_rgb,
    input  logic [MAG_W-1:0]     in_magnitude,
    input  logic [MAG_W-1:0]     threshold,

    output logic                 out_valid,
    output logic                 out_win_valid,
    output logic                 out_sof,
    output logic                 out_eol,
    output logic                 out_eof,
    output logic [X_W-1:0]       out_x,
    output logic [Y_W-1:0]       out_y,
    output logic [RGB_W-1:0]     out_rgb,
    output logic [MAG_W-1:0]     out_magnitude,
    output logic                 out_edge
);
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid       <= 1'b0;
            out_win_valid   <= 1'b0;
            out_sof         <= 1'b0;
            out_eol         <= 1'b0;
            out_eof         <= 1'b0;
            out_x           <= '0;
            out_y           <= '0;
            out_rgb         <= '0;
            out_magnitude   <= '0;
            out_edge        <= 1'b0;
        end else begin
            out_valid       <= in_valid;
            out_win_valid   <= in_valid && in_win_valid;
            out_sof         <= in_valid && in_sof;
            out_eol         <= in_valid && in_eol;
            out_eof         <= in_valid && in_eof;
            out_x           <= in_x;
            out_y           <= in_y;
            out_rgb         <= in_rgb;
            out_magnitude   <= in_magnitude;
            out_edge        <= in_valid && in_win_valid
                            && (in_magnitude >= threshold);
        end
    end
endmodule


// RGB888 edge overlay.  Invalid-border pixels retain the original RGB; a
// valid edge pixel is replaced by EDGE_COLOR.  The replacement is performed
// in the same registered stage as the sideband, so no combinational CDC path
// is introduced.
module case4_edge_overlay #(
    parameter integer RGB_W = 24,
    parameter integer X_W   = 12,
    parameter integer Y_W   = 12,
    parameter logic [23:0] EDGE_COLOR = 24'hFF0000
) (
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic                 in_valid,
    input  logic                 in_win_valid,
    input  logic                 in_sof,
    input  logic                 in_eol,
    input  logic                 in_eof,
    input  logic [X_W-1:0]       in_x,
    input  logic [Y_W-1:0]       in_y,
    input  logic [RGB_W-1:0]     in_rgb,
    input  logic                 in_edge,

    output logic                 out_valid,
    output logic                 out_win_valid,
    output logic                 out_sof,
    output logic                 out_eol,
    output logic                 out_eof,
    output logic [X_W-1:0]       out_x,
    output logic [Y_W-1:0]       out_y,
    output logic [RGB_W-1:0]     out_rgb,
    output logic                 out_edge
);
    localparam logic [RGB_W-1:0] EDGE_COLOR_W = EDGE_COLOR[RGB_W-1:0];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid       <= 1'b0;
            out_win_valid   <= 1'b0;
            out_sof         <= 1'b0;
            out_eol         <= 1'b0;
            out_eof         <= 1'b0;
            out_x           <= '0;
            out_y           <= '0;
            out_rgb         <= '0;
            out_edge        <= 1'b0;
        end else begin
            out_valid       <= in_valid;
            out_win_valid   <= in_valid && in_win_valid;
            out_sof         <= in_valid && in_sof;
            out_eol         <= in_valid && in_eol;
            out_eof         <= in_valid && in_eof;
            out_x           <= in_x;
            out_y           <= in_y;
            out_edge        <= in_valid && in_win_valid && in_edge;
            if (in_valid && in_win_valid && in_edge)
                out_rgb      <= EDGE_COLOR_W;
            else
                out_rgb      <= in_rgb;
        end
    end
endmodule


// Optional RGB565 overlay variant for cameras/displays that stay in the
// contest-board's native 16-bit format.  A detected edge is encoded as red
// RGB565 (5'b11111, 6'b000000, 5'b00000); non-edge pixels pass through exactly.
module case4_edge_overlay_rgb565 #(
    parameter integer X_W = 12,
    parameter integer Y_W = 12,
    parameter logic [15:0] EDGE_COLOR = 16'hF800
) (
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic                 in_valid,
    input  logic                 in_win_valid,
    input  logic                 in_sof,
    input  logic                 in_eol,
    input  logic                 in_eof,
    input  logic [X_W-1:0]       in_x,
    input  logic [Y_W-1:0]       in_y,
    input  logic [15:0]          in_rgb565,
    input  logic                 in_edge,

    output logic                 out_valid,
    output logic                 out_win_valid,
    output logic                 out_sof,
    output logic                 out_eol,
    output logic                 out_eof,
    output logic [X_W-1:0]       out_x,
    output logic [Y_W-1:0]       out_y,
    output logic [15:0]          out_rgb565,
    output logic                 out_edge
);
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid       <= 1'b0;
            out_win_valid   <= 1'b0;
            out_sof         <= 1'b0;
            out_eol         <= 1'b0;
            out_eof         <= 1'b0;
            out_x           <= '0;
            out_y           <= '0;
            out_rgb565      <= '0;
            out_edge        <= 1'b0;
        end else begin
            out_valid       <= in_valid;
            out_win_valid   <= in_valid && in_win_valid;
            out_sof         <= in_valid && in_sof;
            out_eol         <= in_valid && in_eol;
            out_eof         <= in_valid && in_eof;
            out_x           <= in_x;
            out_y           <= in_y;
            out_edge        <= in_valid && in_win_valid && in_edge;
            if (in_valid && in_win_valid && in_edge)
                out_rgb565  <= EDGE_COLOR;
            else
                out_rgb565  <= in_rgb565;
        end
    end
endmodule


// Convenience wrapper for the complete algorithmic chain.  It intentionally
// does not include line buffers, camera protocol, or display timing.  The
// wrapper's output latency is four clocks from an input transfer sampled at a
// rising edge: Sobel (three registered arithmetic stages), threshold (one),
// and overlay (one; the first Sobel stage is counted as the sampling edge).
module case4_sobel_edge_pipeline #(
    parameter integer PIX_W  = 8,
    parameter integer RGB_W  = 24,
    parameter integer X_W    = 12,
    parameter integer Y_W    = 12,
    parameter integer PART_W = PIX_W + 3,
    parameter integer GRAD_W = PIX_W + 4,
    parameter integer MAG_W  = PIX_W + 3,
    parameter logic [RGB_W-1:0] EDGE_COLOR = 24'hFF0000
) (
    input  logic                   clk,
    input  logic                   rst_n,
    input  logic                   in_valid,
    input  logic                   in_win_valid,
    input  logic                   in_sof,
    input  logic                   in_eol,
    input  logic                   in_eof,
    input  logic [X_W-1:0]         in_x,
    input  logic [Y_W-1:0]         in_y,
    input  logic [RGB_W-1:0]       in_rgb,
    input  logic [PIX_W-1:0]       p00,
    input  logic [PIX_W-1:0]       p01,
    input  logic [PIX_W-1:0]       p02,
    input  logic [PIX_W-1:0]       p10,
    input  logic [PIX_W-1:0]       p11,
    input  logic [PIX_W-1:0]       p12,
    input  logic [PIX_W-1:0]       p20,
    input  logic [PIX_W-1:0]       p21,
    input  logic [PIX_W-1:0]       p22,
    input  logic [MAG_W-1:0]       threshold,

    output logic                   out_valid,
    output logic                   out_win_valid,
    output logic                   out_sof,
    output logic                   out_eol,
    output logic                   out_eof,
    output logic [X_W-1:0]         out_x,
    output logic [Y_W-1:0]         out_y,
    output logic [RGB_W-1:0]       out_rgb,
    output logic signed [GRAD_W-1:0] out_gx,
    output logic signed [GRAD_W-1:0] out_gy,
    output logic [MAG_W-1:0]       out_magnitude,
    output logic                   out_edge
);
    logic                   sobel_valid;
    logic                   sobel_win_valid;
    logic                   sobel_sof, sobel_eol, sobel_eof;
    logic [X_W-1:0]         sobel_x;
    logic [Y_W-1:0]         sobel_y;
    logic [RGB_W-1:0]       sobel_rgb;
    logic signed [GRAD_W-1:0] sobel_gx, sobel_gy;
    logic [MAG_W-1:0]       sobel_mag;

    logic                   thr_valid;
    logic                   thr_win_valid;
    logic                   thr_sof, thr_eol, thr_eof;
    logic [X_W-1:0]         thr_x;
    logic [Y_W-1:0]         thr_y;
    logic [RGB_W-1:0]       thr_rgb;
    logic [MAG_W-1:0]       thr_mag;
    logic                   thr_edge;

    case4_sobel3x3 #(
        .PIX_W(PIX_W), .RGB_W(RGB_W), .X_W(X_W), .Y_W(Y_W),
        .PART_W(PART_W), .GRAD_W(GRAD_W), .MAG_W(MAG_W)
    ) u_sobel (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid), .in_win_valid(in_win_valid),
        .in_sof(in_sof), .in_eol(in_eol), .in_eof(in_eof),
        .in_x(in_x), .in_y(in_y), .in_rgb(in_rgb),
        .p00(p00), .p01(p01), .p02(p02),
        .p10(p10), .p11(p11), .p12(p12),
        .p20(p20), .p21(p21), .p22(p22),
        .out_valid(sobel_valid), .out_win_valid(sobel_win_valid),
        .out_sof(sobel_sof), .out_eol(sobel_eol), .out_eof(sobel_eof),
        .out_x(sobel_x), .out_y(sobel_y), .out_rgb(sobel_rgb),
        .out_gx(sobel_gx), .out_gy(sobel_gy), .out_magnitude(sobel_mag)
    );

    case4_edge_threshold #(
        .MAG_W(MAG_W), .RGB_W(RGB_W), .X_W(X_W), .Y_W(Y_W)
    ) u_threshold (
        .clk(clk), .rst_n(rst_n),
        .in_valid(sobel_valid), .in_win_valid(sobel_win_valid),
        .in_sof(sobel_sof), .in_eol(sobel_eol), .in_eof(sobel_eof),
        .in_x(sobel_x), .in_y(sobel_y), .in_rgb(sobel_rgb),
        .in_magnitude(sobel_mag), .threshold(threshold),
        .out_valid(thr_valid), .out_win_valid(thr_win_valid),
        .out_sof(thr_sof), .out_eol(thr_eol), .out_eof(thr_eof),
        .out_x(thr_x), .out_y(thr_y), .out_rgb(thr_rgb),
        .out_magnitude(thr_mag), .out_edge(thr_edge)
    );

    case4_edge_overlay #(
        .RGB_W(RGB_W), .X_W(X_W), .Y_W(Y_W), .EDGE_COLOR(EDGE_COLOR)
    ) u_overlay (
        .clk(clk), .rst_n(rst_n),
        .in_valid(thr_valid), .in_win_valid(thr_win_valid),
        .in_sof(thr_sof), .in_eol(thr_eol), .in_eof(thr_eof),
        .in_x(thr_x), .in_y(thr_y), .in_rgb(thr_rgb), .in_edge(thr_edge),
        .out_valid(out_valid), .out_win_valid(out_win_valid),
        .out_sof(out_sof), .out_eol(out_eol), .out_eof(out_eof),
        .out_x(out_x), .out_y(out_y), .out_rgb(out_rgb),
        .out_edge(out_edge)
    );

    // The gradient path is delayed through the threshold and overlay stages
    // so that it remains aligned with the final RGB/edge sideband.  The
    // magnitude can be sampled from the threshold stage one clock before the
    // overlay output and is registered here at the overlay edge.
    logic signed [GRAD_W-1:0] gx_delay;
    logic signed [GRAD_W-1:0] gy_delay;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gx_delay     <= '0;
            gy_delay     <= '0;
            out_gx        <= '0;
            out_gy        <= '0;
            out_magnitude <= '0;
        end else begin
            gx_delay      <= sobel_valid && sobel_win_valid ? sobel_gx : '0;
            gy_delay      <= sobel_valid && sobel_win_valid ? sobel_gy : '0;
            out_gx        <= gx_delay;
            out_gy        <= gy_delay;
            out_magnitude <= thr_valid && thr_win_valid ? thr_mag : '0;
        end
    end
endmodule
