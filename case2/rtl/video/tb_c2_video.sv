`timescale 1ns/1ps

// Small self-checking smoke test for the timing generator and page-flip
// controller.  The deliberately tiny raster keeps the run short while still
// exercising active video, both blanking regions, sync polarity, frame wrap,
// and the tear-free page commit rule.
module tb_c2_video;
  localparam int H_ACTIVE = 4;
  localparam int H_FRONT  = 1;
  localparam int H_SYNC   = 2;
  localparam int H_BACK   = 1;
  localparam int V_ACTIVE = 3;
  localparam int V_FRONT  = 1;
  localparam int V_SYNC   = 1;
  localparam int V_BACK   = 1;
  localparam int H_TOTAL  = H_ACTIVE + H_FRONT + H_SYNC + H_BACK;
  localparam int V_TOTAL  = V_ACTIVE + V_FRONT + V_SYNC + V_BACK;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic rst_n = 1'b0;
  logic [((H_TOTAL <= 1) ? 1 : $clog2(H_TOTAL))-1:0] h_count;
  logic [((V_TOTAL <= 1) ? 1 : $clog2(V_TOTAL))-1:0] v_count;
  logic [((H_ACTIVE <= 1) ? 1 : $clog2(H_ACTIVE))-1:0] pixel_x;
  logic [((V_ACTIVE <= 1) ? 1 : $clog2(V_ACTIVE))-1:0] pixel_y;
  logic de, active_video, hsync, vsync, hblank, vblank;
  logic frame_start, frame_end, line_start, line_end;
  logic vsync_start, vsync_end;

  logic request_valid;
  logic request_ready;
  logic request_error;
  logic [0:0] request_page;
  logic [0:0] active_page;
  logic [0:0] pending_page;
  logic flip_pending, flip_ack;

  c2_video_timing_gen #(
    .H_ACTIVE(H_ACTIVE), .H_FRONT(H_FRONT), .H_SYNC(H_SYNC), .H_BACK(H_BACK),
    .V_ACTIVE(V_ACTIVE), .V_FRONT(V_FRONT), .V_SYNC(V_SYNC), .V_BACK(V_BACK),
    .H_SYNC_POL(1'b0), .V_SYNC_POL(1'b0)
  ) u_timing (
    .clk, .rst_n, .h_count, .v_count, .pixel_x, .pixel_y,
    .de, .active_video, .hsync, .vsync, .hblank, .vblank,
    .frame_start, .frame_end, .line_start, .line_end,
    .vsync_start, .vsync_end
  );

  c2_page_flip_ctrl #(.PAGE_W(1), .PAGE_COUNT(2)) u_flip (
    .clk, .rst_n, .frame_start,
    .request_valid, .request_ready, .request_page,
    .active_page, .pending_page, .flip_pending, .flip_ack,
    .request_error
  );

  int cycles;
  int active_pixels;
  logic boundary_seen;
  logic request_sent;
  logic page_one_committed;
  logic page_zero_committed;

  // Check values after each counter transition, at the falling edge.  A
  // frame_start observed on one falling edge commits at the following rising
  // edge; flip_ack is consequently checked on the next falling edge.
  always @(negedge clk) begin
    if (!rst_n) begin
      if (de || frame_start || flip_ack)
        $fatal(1, "outputs asserted during reset");
    end else begin
      cycles = cycles + 1;

      if (frame_start)
        boundary_seen = 1'b1;
      else if (boundary_seen) begin
        boundary_seen = 1'b0;
        if (request_sent && !page_one_committed && active_page != 1'b1)
          $fatal(1, "page did not commit at frame boundary");
        if (flip_ack && active_page == 1'b1)
          page_one_committed = 1'b1;
        if (flip_ack && active_page == 1'b0 && page_one_committed)
          page_zero_committed = 1'b1;
      end

      if (de) begin
        if (pixel_x !== h_count || pixel_y !== v_count)
          $fatal(1, "bad active coordinate x=%0d y=%0d expected x=%0d y=%0d",
                 pixel_x, pixel_y, h_count, v_count);
        active_pixels = active_pixels + 1;
      end

      // Active-low sync: pulse is low, idle is high.
      if (h_count >= H_ACTIVE + H_FRONT &&
          h_count <  H_ACTIVE + H_FRONT + H_SYNC && hsync !== 1'b0)
        $fatal(1, "hsync polarity/interval error");
      if (v_count >= V_ACTIVE + V_FRONT &&
          v_count <  V_ACTIVE + V_FRONT + V_SYNC && vsync !== 1'b0)
        $fatal(1, "vsync polarity/interval error");
    end
  end

  initial begin
    cycles = 0;
    active_pixels = 0;
    boundary_seen = 0;
    request_sent = 0;
    page_one_committed = 0;
    page_zero_committed = 0;
    request_valid = 0;
    request_page = 0;

    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    // Wait into active video, then request the other page.  It must remain
    // pending until the next frame_start and may not tear the current frame.
    repeat (3) @(negedge clk);
    request_page = 1'b1;
    request_valid = 1'b1;
    if (!request_ready)
      $fatal(1, "page request unexpectedly back-pressured");
    @(negedge clk);
    request_valid = 1'b0;
    request_sent = 1'b1;
    if (active_page !== 1'b0 || !flip_pending)
      $fatal(1, "request changed active page before frame boundary");

    // Let two complete frames pass.  A second request back to page zero is
    // sent after page one has committed, exercising another safe transition.
    wait (page_one_committed);
    repeat (5) @(negedge clk);
    request_page = 1'b0;
    request_valid = 1'b1;
    @(negedge clk);
    request_valid = 1'b0;
    wait (page_zero_committed);

    if (active_pixels < 2 * H_ACTIVE * V_ACTIVE)
      $fatal(1, "too few active pixels observed: %0d", active_pixels);
    if (request_error)
      $fatal(1, "unexpected page request error");
    $display("TB_C2_VIDEO_PASS cycles=%0d active_pixels=%0d", cycles, active_pixels);
    $finish;
  end
endmodule
