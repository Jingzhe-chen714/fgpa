`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// c2_page_flip_ctrl
// -----------------------------------------------------------------------------
// Synchronous, tear-free page selection for a double (or multi-) buffered
// framebuffer.  A software/rendering side presents `request_page` with
// `request_valid`; the request is accepted only when `request_ready` is high
// and is committed at `frame_start`.  Consequently `active_page` never
// changes in the middle of a raster and can safely feed a display reader.
//
// There is one pending request slot.  A request arriving on a frame boundary
// with no older pending request is committed on that same boundary; a request
// arriving while an older request is being committed is retained for the next
// frame.  `flip_ack` is a one-cycle pulse for every request committed,
// including a request for the page that is already active.  Software can use
// the pulse as its completion event without having to special-case that case.
//
// `PAGE_COUNT` is only a range check.  Set it to 2 for a normal ping-pong
// framebuffer, or to a larger value when the page index has more bits.  An
// out-of-range request is not accepted and raises `request_error` for one
// cycle.  The range check is intentionally optional at synthesis time (a
// power-of-two PAGE_COUNT has no comparator cost in most tools).
// -----------------------------------------------------------------------------
module c2_page_flip_ctrl #(
  parameter int PAGE_W     = 1,
  parameter int PAGE_COUNT = (1 << PAGE_W)
) (
  input  logic             clk,
  input  logic             rst_n,

  // `frame_start` is normally wired to c2_video_timing_gen.frame_start.
  input  logic             frame_start,

  input  logic             request_valid,
  output logic             request_ready,
  input  logic [PAGE_W-1:0] request_page,

  output logic [PAGE_W-1:0] active_page,
  output logic [PAGE_W-1:0] pending_page,
  output logic             flip_pending,
  output logic             flip_ack,
  output logic             request_error
);

  logic pending_valid;
  logic req_in_range;
  logic req_fire;

  always_comb begin
    // A pending request is normally held until the next frame.  On the
    // boundary itself the old slot is freed, so a new request can be accepted
    // without imposing a one-cycle software-visible bubble.
    request_ready = !pending_valid || frame_start;
    req_in_range  = (PAGE_COUNT <= 0) || (request_page < PAGE_COUNT);
    req_fire      = request_valid && request_ready && req_in_range;
  end

  assign flip_pending = pending_valid;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      active_page  <= '0;
      pending_page <= '0;
      pending_valid <= 1'b0;
      flip_ack     <= 1'b0;
      request_error <= 1'b0;
    end else begin
      // All event outputs are pulses, not sticky status bits.
      flip_ack      <= 1'b0;
      request_error <= request_valid && request_ready && !req_in_range;

      if (frame_start) begin
        if (pending_valid) begin
          // Commit the request captured in an earlier frame.
          active_page   <= pending_page;
          flip_ack      <= 1'b1;
          pending_valid <= 1'b0;

          // If software presents another request on this same boundary,
          // preserve it for the following frame rather than dropping it.
          if (req_fire) begin
            pending_page  <= request_page;
            pending_valid <= 1'b1;
          end
        end else if (req_fire) begin
          // A request already visible at the boundary is safe to apply now.
          active_page   <= request_page;
          flip_ack      <= 1'b1;
          pending_valid <= 1'b0;
        end
      end else if (req_fire) begin
        pending_page  <= request_page;
        pending_valid <= 1'b1;
      end
    end
  end

`ifndef SYNTHESIS
  initial begin
    if (PAGE_W <= 0)
      $error("c2_page_flip_ctrl: PAGE_W must be positive");
    if (PAGE_COUNT <= 0)
      $error("c2_page_flip_ctrl: PAGE_COUNT must be positive (or use a power of two)");
  end
`endif

endmodule

