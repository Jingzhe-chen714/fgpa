# Video timing and framebuffer page selection

This directory contains the board-independent timing and page-selection
blocks. It does not instantiate a PLL, HDMI PHY or DDR3 controller. The
corrected 8.22 Case 2 requires HDMI 640x480@60 output from a DDR3 framebuffer;
the generic counters are not a substitute for the required HDMI transmitter.
The active assembly is `c2_display_path` in `rtl/system`, using
`c2_rect_burst_reader` and `c2_line_fifo` rather than the legacy one-beat reader
in this directory.

## `c2_video_timing_gen`

`c2_video_timing_gen` is a parameterized raster counter.  The default values
are the conventional 640x480 raster timings (640 active pixels,
16/96/48 horizontal front/sync/back porch,
and 480 active lines, 10/2/33 vertical front/sync/back porch).  Sync polarity
is independently selected with `H_SYNC_POL` and `V_SYNC_POL` (both are active
low by default). These raster timings can feed an HDMI TX/PHY; they do not
mean the competition output is VGA. A different resolution is an optional
extension, not a replacement for validating the required 640x480@60 mode.
The actual frame rate also depends on the PLL-generated pixel clock, which
is still board/IP integration work.

Important outputs:

* `h_count`/`v_count` cover the complete raster, including blanking.
* `de` (`active_video`) is high only for active picture pixels.
* `pixel_x`/`pixel_y` are zero-based coordinates and are valid when `de` is
  high; they are forced to zero during blanking.
* `hsync` and `vsync` have the requested active polarity.
* `frame_start` is a one-clock pulse at `(h_count,v_count)==(0,0)`, the first
  active pixel period. The system uses it to arm a prefetched active frame,
  not to commit a new page at the last possible moment.
* `vblank_start` is the first pixel clock of vertical blanking and is the
  system's page-flip commit point. `prefetch_start` follows it by exactly one
  clock so the registered new page/base is settled before prefetch captures
  the configuration.
* `frame_end` marks the final period of the raster;
  `line_start`/`line_end` mark line boundaries. `vsync_start` and
  `vsync_end` mark the first line in and first line after the vertical sync
  interval.

The reset is active-low and asynchronous, matching the other case2 building
blocks.  During reset `de` and boundary strobes are low and sync outputs are
held inactive (the inverse of their configured polarity).

## `c2_page_flip_ctrl`

The page controller is intentionally same-clock. Its input is named
`frame_start` for historical reasons, but it accepts the selected safe commit
strobe. The active system connects it to `vblank_start`, leaving blanking time
to prefetch the newly selected page:

```systemverilog
c2_page_flip_ctrl #(.PAGE_W(1), .PAGE_COUNT(2)) u_flip (
  .clk, .rst_n,
  .frame_start(timing_vblank_start),
  .request_valid(cpu_page_valid),
  .request_ready(cpu_page_ready),
  .request_page(cpu_page),
  .active_page(display_page),
  .pending_page(),
  .flip_pending(),
  .flip_ack(cpu_flip_ack),
  .request_error(cpu_page_error)
);
```

`request_valid && request_ready` is the only request-accept condition.  One
pending request is retained until the next commit strobe, where
`active_page` changes atomically and `flip_ack` pulses for one clock.  A
request presented exactly on a commit boundary is applied on that boundary when
the pending slot is empty.  If an older request is being committed, the new
request is retained for the following commit boundary. Requests outside
`0 .. PAGE_COUNT-1` are rejected and pulse `request_error`; no page state is
modified.

Because the commit point is explicit, the module does not hide a clock-domain
crossing assumption. If software and the pixel generator use different
clocks, implement the system's `c2_page_cdc_blackbox` seam with a proper
request/status handshake or asynchronous FIFO. Its empty body is not CDC
verification.

## Active burst/FIFO scanout path

`c2_renderer_system` connects the page/timing blocks to:

```text
vblank_start -> page commit
next clock  -> prefetch_start -> capture page/base and flush stale pixels
later clock -> c2_rect_burst_reader -> c2_line_fifo -> RGB565 + DE/HS/VS
                                                    -> required HDMI TX/PHY
```

The rectangle reader segments rows by the maximum burst length and 4 KiB
boundary. Its memory requests share `c2_mem_arbiter_2m_owner` with the renderer;
the external-memory branch now uses `c2_mem_to_axi4_adapter` and top-level
AXI4 Full pins toward DDR3. The renderer also has row-level source/background
read bursts, so neither active path depends on per-pixel read descriptors.

The first reset-time frame is intentionally black. A later frame is armed
only if prefetch has supplied data by `frame_start`; an empty prefetch or FIFO
exhaustion is reported as underflow. The fixed-rate raster cannot pause:
`phy_pixel_ready` must remain high during active video. The HDMI wrapper must
adapt RGB565 to its required input format, preserve data/sync latency, and
supply the correct PLL/PHY clocks and pin constraints.

When `clk_pix` differs from `clk_sys`, the read-only display-memory CDC seam
must preserve descriptors, data and terminal `last` under backpressure. The
current seam is not a general write-capable AXI CDC bridge. DDR3/HDMI IP
simulation, CDC checks, Efinity placement/routing and real-board underflow/FPS
tests remain necessary before claiming 640x480@60 operation.

## `c2_framebuffer_reader`

`c2_framebuffer_reader` is the retained correctness-first, one-beat scanout
primitive. It is not instantiated by the active system display path. A `start`
command describes one linear rectangle (`base_addr`, byte stride, width and
height). The reader issues one read at a time through the abstract memory
interface, holds each response under downstream back-pressure, and emits
`pixel_data` together with zero-based `pixel_x`/`pixel_y` and `pixel_last`.
`done` is generated only after the final pixel is consumed.

This version remains useful for isolated request/response checks; the
burst/FIFO replacement described above is already implemented. It should not
be cited as the current system's throughput limitation. The accompanying
`tb_c2_framebuffer_reader.sv` exercises request/response stalls and invalid
geometry.
