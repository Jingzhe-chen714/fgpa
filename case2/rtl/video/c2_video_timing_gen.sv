`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// c2_video_timing_gen
// -----------------------------------------------------------------------------
// A small, vendor-neutral raster timing generator.  The counters run over the
// complete line/frame (active video plus porches and sync), while `de` marks
// the active picture area.  No clocking primitive or board-specific IO is used
// here; the module can therefore drive either a VGA DAC wrapper or an HDMI
// serializer in a later integration stage.
//
// The default parameters are the conventional 640x480 VGA timing.  A 720p
// HDMI mode, for example, can be selected with
//   H_ACTIVE=1280, H_FRONT=110, H_SYNC=40, H_BACK=220,
//   V_ACTIVE=720,  V_FRONT=5,   V_SYNC=5,  V_BACK=20,
//   H_SYNC_POL=1, V_SYNC_POL=1.
//
// `frame_start` is asserted for the cycle whose counters are (0,0), i.e. the
// first pixel period of a new active frame.  `vblank_start` marks the first
// pixel clock of vertical blanking and is the preferred page-commit point.
// `prefetch_start` follows `vblank_start` by exactly one clock, allowing a page
// controller's registered commit to settle before the display path captures
// the new framebuffer configuration and starts its blanking-time prefetch.
// `frame_end` is the final pixel period of the frame.  `vsync_start` and
// `vsync_end` identify the first line in and first line after the vertical
// sync interval respectively.
// -----------------------------------------------------------------------------
module c2_video_timing_gen #(
  parameter int H_ACTIVE   = 640,
  parameter int H_FRONT    = 16,
  parameter int H_SYNC     = 96,
  parameter int H_BACK     = 48,
  parameter int V_ACTIVE   = 480,
  parameter int V_FRONT    = 10,
  parameter int V_SYNC     = 2,
  parameter int V_BACK     = 33,
  parameter bit H_SYNC_POL = 1'b0,
  parameter bit V_SYNC_POL = 1'b0,
  parameter int H_TOTAL    = H_ACTIVE + H_FRONT + H_SYNC + H_BACK,
  parameter int V_TOTAL    = V_ACTIVE + V_FRONT + V_SYNC + V_BACK,
  parameter int H_COUNT_W  = (H_TOTAL <= 1) ? 1 : $clog2(H_TOTAL),
  parameter int V_COUNT_W  = (V_TOTAL <= 1) ? 1 : $clog2(V_TOTAL),
  parameter int X_W        = (H_ACTIVE <= 1) ? 1 : $clog2(H_ACTIVE),
  parameter int Y_W        = (V_ACTIVE <= 1) ? 1 : $clog2(V_ACTIVE)
) (
  input  logic                 clk,
  input  logic                 rst_n,

  // Complete-raster counters.  They are useful to a display reader which
  // wants to schedule memory requests during blanking as well as active video.
  output logic [H_COUNT_W-1:0] h_count,
  output logic [V_COUNT_W-1:0] v_count,

  // Coordinates are zero based and meaningful when de=1.  During blanking
  // they are held at zero, avoiding accidental use of porch coordinates.
  output logic [X_W-1:0]       pixel_x,
  output logic [Y_W-1:0]       pixel_y,

  output logic                 de,
  output logic                 active_video,
  output logic                 hsync,
  output logic                 vsync,
  output logic                 hblank,
  output logic                 vblank,

  output logic                 frame_start,
  output logic                 vblank_start,
  output logic                 prefetch_start,
  output logic                 frame_end,
  output logic                 line_start,
  output logic                 line_end,
  output logic                 vsync_start,
  output logic                 vsync_end
);

  // Constants are kept in integer form for readable comparisons; assignment
  // sizing handles the selected counter/coordinate widths for custom modes.
  localparam int H_SYNC_BEGIN = H_ACTIVE + H_FRONT;
  localparam int H_SYNC_END   = H_ACTIVE + H_FRONT + H_SYNC;
  localparam int V_SYNC_BEGIN = V_ACTIVE + V_FRONT;
  localparam int V_SYNC_END   = V_ACTIVE + V_FRONT + V_SYNC;

  logic h_sync_region;
  logic v_sync_region;
  logic prefetch_start_q;

  assign prefetch_start = prefetch_start_q;

  // A reset leaves the raster at the first pixel.  Gating the externally
  // visible strobes while reset is asserted keeps downstream logic quiescent
  // even though the counters themselves are already zero.
  always_comb begin
    hblank       = (h_count >= H_ACTIVE);
    vblank       = (v_count >= V_ACTIVE);
    de           = rst_n && !hblank && !vblank;
    active_video = de;

    h_sync_region = (H_SYNC != 0) &&
                    (h_count >= H_SYNC_BEGIN) &&
                    (h_count <  H_SYNC_END);
    v_sync_region = (V_SYNC != 0) &&
                    (v_count >= V_SYNC_BEGIN) &&
                    (v_count <  V_SYNC_END);

    // Outside the pulse interval the signal is the inverse of the selected
    // polarity, as required by both the standard VGA and common HDMI modes.
    if (!rst_n)
      hsync = !H_SYNC_POL;
    else if (h_sync_region)
      hsync = H_SYNC_POL;
    else
      hsync = !H_SYNC_POL;

    if (!rst_n)
      vsync = !V_SYNC_POL;
    else if (v_sync_region)
      vsync = V_SYNC_POL;
    else
      vsync = !V_SYNC_POL;

    if (de) begin
      // Assignment sizing performs the safe zero extension/truncation for
      // custom modes; avoiding a fixed part-select also permits callers to
      // choose a wider coordinate bus than the raster counter.
      pixel_x = X_W'(h_count);
      pixel_y = Y_W'(v_count);
    end else begin
      pixel_x = '0;
      pixel_y = '0;
    end

    frame_start = rst_n && (h_count == 0) && (v_count == 0);
    vblank_start = rst_n && (V_TOTAL > V_ACTIVE) &&
                   (h_count == 0) && (v_count == V_ACTIVE);
    frame_end   = rst_n && (h_count == H_TOTAL-1) &&
                  (v_count == V_TOTAL-1);
    line_start  = rst_n && (h_count == 0);
    line_end    = rst_n && (h_count == H_TOTAL-1);
    vsync_start = rst_n && (h_count == 0) && (v_count == V_SYNC_BEGIN);
    vsync_end   = rst_n && (h_count == 0) && (v_count == V_SYNC_END);
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      h_count <= '0;
      v_count <= '0;
      prefetch_start_q <= 1'b0;
    end else begin
      // Registering this event, rather than deriving it from a particular
      // horizontal count, preserves the one-clock separation even for tiny
      // simulation timings with H_TOTAL=1.
      prefetch_start_q <= vblank_start;

      if (h_count == H_TOTAL-1) begin
        h_count <= '0;
        if (v_count == V_TOTAL-1)
          v_count <= '0;
        else
          v_count <= v_count + 1'b1;
      end else begin
        h_count <= h_count + 1'b1;
      end
    end
  end

`ifndef SYNTHESIS
  // Parameter checks are simulation-only diagnostics.  Keeping them outside
  // the synthesizable path makes the RTL portable to FPGA and ASIC tools.
  initial begin
    if (H_ACTIVE <= 0 || V_ACTIVE <= 0 || H_TOTAL <= 0 || V_TOTAL <= 0)
      $error("c2_video_timing_gen: active dimensions and totals must be > 0");
    if (H_FRONT < 0 || H_SYNC < 0 || H_BACK < 0 ||
        V_FRONT < 0 || V_SYNC < 0 || V_BACK < 0)
      $error("c2_video_timing_gen: porch/sync lengths cannot be negative");
    if (H_TOTAL != H_ACTIVE + H_FRONT + H_SYNC + H_BACK ||
        V_TOTAL != V_ACTIVE + V_FRONT + V_SYNC + V_BACK)
      $error("c2_video_timing_gen: total does not equal active+porches+sync");
  end
`endif

endmodule
