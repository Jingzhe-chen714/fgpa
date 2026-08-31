// Streaming 3x3 window generator for an 8-bit (or parameterised width) gray image.
//
// Input contract
//   * Pixels are presented in raster order, one pixel per cycle when in_valid=1.
//   * in_x/in_y are zero-based active-image coordinates and are held with the
//     pixel.  in_sof is asserted with (0,0), in_eol with the last pixel of a
//     line, and in_eof with the last pixel of a frame.  The marker inputs are
//     optional; the coordinate comparisons below provide a useful fallback.
//
// Output contract (VALID_ONLY border policy)
//   * A window is emitted one clock after the input pixel which completes it.
//   * out_x/out_y identify the centre pixel, i.e. (in_x-1,in_y-1).
//   * out_valid is asserted only for centres x>=1,y>=1.  Thus the first
//     output of a frame is centre (1,1), and the output image has no artificial
//     zero/replicate border.  out_sof is pulsed with that first valid window.
//   * out_eol/out_eof are aligned to the centre coordinate (the final input
//     sample of a line/frame generates the marker).
//   * p00..p22 are packed as the usual top-left to bottom-right 3x3 window.
//
// The three row memories are selected by a rotating bank pointer.  The current
// row is written on the input clock edge; the two previous rows are read
// combinationally before that edge.  Consequently, the module is suitable for
// XSIM and is straightforward to replace with synchronous BRAM wrappers later.

`timescale 1ns/1ps

module window3x3_gray #(
    parameter integer IMG_WIDTH  = 640,
    parameter integer IMG_HEIGHT = 480,
    parameter integer PIXEL_BITS = 8,
    parameter integer X_BITS = (IMG_WIDTH  <= 1) ? 1 : $clog2(IMG_WIDTH),
    parameter integer Y_BITS = (IMG_HEIGHT <= 1) ? 1 : $clog2(IMG_HEIGHT)
) (
    input  logic                   clk,
    input  logic                   rst,

    input  logic                   in_valid,
    input  logic                   in_sof,
    input  logic                   in_eol,
    input  logic                   in_eof,
    input  logic [X_BITS-1:0]      in_x,
    input  logic [Y_BITS-1:0]      in_y,
    input  logic [PIXEL_BITS-1:0]  in_pixel,

    output logic                   out_valid,
    output logic                   out_sof,
    output logic                   out_eol,
    output logic                   out_eof,
    output logic [X_BITS-1:0]      out_x,
    output logic [Y_BITS-1:0]      out_y,
    output logic [PIXEL_BITS-1:0]  out_p00,
    output logic [PIXEL_BITS-1:0]  out_p01,
    output logic [PIXEL_BITS-1:0]  out_p02,
    output logic [PIXEL_BITS-1:0]  out_p10,
    output logic [PIXEL_BITS-1:0]  out_p11,
    output logic [PIXEL_BITS-1:0]  out_p12,
    output logic [PIXEL_BITS-1:0]  out_p20,
    output logic [PIXEL_BITS-1:0]  out_p21,
    output logic [PIXEL_BITS-1:0]  out_p22
);

    // Three rows are sufficient for a 3x3 stencil.  A packed logic array is
    // intentionally used here: Vivado can infer RAMs for larger widths, while
    // small XSIM regressions remain simple and deterministic.
    logic [PIXEL_BITS-1:0] row0 [0:IMG_WIDTH-1];
    logic [PIXEL_BITS-1:0] row1 [0:IMG_WIDTH-1];
    logic [PIXEL_BITS-1:0] row2 [0:IMG_WIDTH-1];

    logic [1:0] cur_bank;
    logic [1:0] effective_bank;

    logic [PIXEL_BITS-1:0] top_at_x;
    logic [PIXEL_BITS-1:0] mid_at_x;

    // Two historical columns for each of the three rows.  At x=0 a line is
    // explicitly restarted; this prevents the tail of the previous line from
    // leaking into the first two windows of the new line.
    logic [PIXEL_BITS-1:0] top_d1, top_d0;
    logic [PIXEL_BITS-1:0] mid_d1, mid_d0;
    logic [PIXEL_BITS-1:0] bot_d1, bot_d0;

    logic line_end;
    logic interior;

    // A frame may be restarted without an intervening reset.  in_sof forces
    // the first row to bank zero; after each eol the pointer advances 0->1->2.
    always_comb begin
        effective_bank = in_sof ? 2'd0 : cur_bank;

        // Avoid an out-of-range memory index while the source is idle or a
        // malformed coordinate is being driven.  Such cycles are never valid.
        top_at_x = '0;
        mid_at_x = '0;
        if (in_x < IMG_WIDTH) begin
            case (effective_bank)
                2'd0: begin
                    // Current row row0; previous rows are row2 (y-1) and
                    // row1 (y-2) under the rotating-bank convention.
                    mid_at_x = row2[in_x];
                    top_at_x = row1[in_x];
                end
                2'd1: begin
                    mid_at_x = row0[in_x];
                    top_at_x = row2[in_x];
                end
                default: begin
                    mid_at_x = row1[in_x];
                    top_at_x = row0[in_x];
                end
            endcase
        end
    end

    always_comb begin
        line_end = in_eol || (in_x == IMG_WIDTH-1);
        interior = in_valid && (in_x >= 2) && (in_y >= 2) &&
                   (in_x < IMG_WIDTH) && (in_y < IMG_HEIGHT);
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            cur_bank  <= 2'd0;

            top_d1 <= '0;
            top_d0 <= '0;
            mid_d1 <= '0;
            mid_d0 <= '0;
            bot_d1 <= '0;
            bot_d0 <= '0;

            out_valid <= 1'b0;
            out_sof   <= 1'b0;
            out_eol   <= 1'b0;
            out_eof   <= 1'b0;
            out_x     <= '0;
            out_y     <= '0;
            out_p00   <= '0;
            out_p01   <= '0;
            out_p02   <= '0;
            out_p10   <= '0;
            out_p11   <= '0;
            out_p12   <= '0;
            out_p20   <= '0;
            out_p21   <= '0;
            out_p22   <= '0;
        end else begin
            // Outputs are registered and deasserted during bubbles.  Window
            // data is held when out_valid=0 and must be ignored by consumers;
            // holding it avoids adding nine unnecessary bubble multiplexers.
            out_valid <= 1'b0;
            out_sof   <= 1'b0;
            out_eol   <= 1'b0;
            out_eof   <= 1'b0;

            if (in_valid) begin
                // The values in the shift registers are x-2 and x-1; the
                // combinational memory reads are the current x column.
                if (interior) begin
                    out_valid <= 1'b1;
                    out_sof   <= (in_x == 2) && (in_y == 2);
                    out_eol   <= line_end;
                    out_eof   <= line_end && (in_eof ||
                                  ((in_y == IMG_HEIGHT-1) &&
                                   (in_x == IMG_WIDTH-1)));
                    out_x     <= in_x - 1'b1;
                    out_y     <= in_y - 1'b1;

                    out_p00 <= top_d1;
                    out_p01 <= top_d0;
                    out_p02 <= top_at_x;
                    out_p10 <= mid_d1;
                    out_p11 <= mid_d0;
                    out_p12 <= mid_at_x; // previous row, current column
                    out_p20 <= bot_d1;
                    out_p21 <= bot_d0;
                    out_p22 <= in_pixel;
                end

                // Restart the horizontal shift registers at every line.  For
                // x=0, d1 is a harmless zero and d0 is the first sample; by
                // x=2 the window is exactly columns 0,1,2.
                if (in_x == 0) begin
                    top_d1 <= '0;
                    top_d0 <= top_at_x;
                    mid_d1 <= '0;
                    mid_d0 <= mid_at_x;
                    bot_d1 <= '0;
                    bot_d0 <= in_pixel;
                end else begin
                    top_d1 <= top_d0;
                    top_d0 <= top_at_x;
                    mid_d1 <= mid_d0;
                    mid_d0 <= mid_at_x;
                    bot_d1 <= bot_d0;
                    bot_d0 <= in_pixel;
                end

                // Write the current sample into the selected row bank.  The
                // read values above were evaluated before this edge, so a
                // bank never aliases either historical row for this pixel.
                if (in_x < IMG_WIDTH) begin
                    case (effective_bank)
                        2'd0: row0[in_x] <= in_pixel;
                        2'd1: row1[in_x] <= in_pixel;
                        default: row2[in_x] <= in_pixel;
                    endcase
                end

                // Advance at end-of-line.  SOF has priority so a new frame
                // always starts with bank zero, even if the previous frame
                // ended on an unexpected line.
                if (in_sof) begin
                    cur_bank <= line_end ? 2'd1 : 2'd0;
                end else if (line_end) begin
                    case (cur_bank)
                        2'd0: cur_bank <= 2'd1;
                        2'd1: cur_bank <= 2'd2;
                        default: cur_bank <= 2'd0;
                    endcase
                end
            end
        end
    end

endmodule
