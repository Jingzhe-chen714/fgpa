# Board/IP replacement points

This directory contains the remaining board-dependent seams and two legacy
anchors. The active AXI4-Lite control adapter and AXI4 Full memory adapter are
implemented RTL in `rtl/bus`; they are not blackboxes. The corrected 8.22
Case 2 requires DDR3 framebuffer memory and HDMI output. Generated
DDR3 controller/PHY and HDMI TX/PHY wrappers, PLL/reset logic, CDC and board
constraints still have to be supplied from the actual board/IP configuration.

## Active board-dependent seams

| Blackbox | What the real implementation must provide | First board task |
|---|---|---|
| `c2_clock_reset_blackbox` | system/pixel clocks, synchronized active-low resets, lock flag | PLL/clock tree and reset release timing |
| `c2_mem_cdc_blackbox` | read-only display async bridge preserving descriptor order and read `last`; current port list has no burst write-data or write-response channel | asynchronous descriptor/response FIFOs or vendor CDC primitive |
| `c2_page_cdc_blackbox` | one-entry page request crossing and stable page status | synchronizer/handshake between CSR and pixel clocks |
| `c2_video_phy_blackbox` | timing-qualified RGB565 stream to a generated HDMI TX/PHY wrapper, with ready/init status | required HDMI output, pixel-format adaptation, serialization, clocks and physical pin constraints |

The current video seam still exposes parallel data/timing signals, not a
finished HDMI pin-level top. The generated board wrapper must add/connect the
actual HDMI pins and preserve the data/sync latency. Merely selecting
`USE_VIDEO_PHY_IP=1` does not create a working transmitter.

The active external-memory seam is the system top's `m_axi_*` port. With
`USE_EXT_MEM_IP=1`, `c2_mem_to_axi4_adapter` already converts the owner-arbitrated
16-bit stream into a parameterized AXI4 Full master (default 128-bit data).
Connect that port to the generated DDR3 controller's AXI slave and connect
calibration status to `ext_mem_init_done/error`. Set data/ID widths and clock
domains from the actual generated ports. DDR3 training, refresh and physical
signaling are not implemented by the adapter.

## Legacy anchors, not selected by the active system path

| Legacy module | Current status |
|---|---|
| `c2_ext_mem_adapter_blackbox` | Retained only for a possible future non-AXI native-memory interface. `c2_renderer_system` no longer instantiates it; `USE_EXT_MEM_IP=1` selects the real AXI adapter. |
| `c2_sapphire_csr_blackbox` | Retained as an older non-AXI control anchor. `USE_AXI4LITE_CSR=1` now instantiates `c2_axi4lite_csr_adapter`; this blackbox is not in that path. |

The AXI4-Lite adapter provides the renderer slave interface, not the Sapphire
CPU, its interconnect, address allocation or software driver. A generated
AXI4 Full CPU master may require an AXI4-to-AXI4-Lite bridge for this CSR window.
An APB-only or Custom Instruction path is not the current competition bus
configuration.

## External-memory contract

`req_len` is beats-minus-one and `req_addr` is a byte address. A write request
is accepted first; exactly `req_len+1` beats then arrive on `wr_valid`, with
`wr_last=1` on the final beat. The adapter must hold `wr_ready` low or high
without losing data and may report an immediate beat/protocol error on
`wr_error`. After consuming or aborting the complete native write, it must emit
exactly one stable `wr_rsp_valid/wr_rsp_error` response and hold it until
`wr_rsp_ready`; this is the AXI `B`-channel equivalent. Read responses are
ordered and use a terminal `rsp_last`; the abstract port has no transaction
IDs. An
out-of-range or native error must terminate the current transaction rather than
leave the owner waiting forever.

The generic engine now splits source/background read descriptors at
`MAX_READ_BEATS` and 4 KiB boundaries, as well as write descriptors at
`MAX_WRITE_BEATS` and 4 KiB boundaries. Alpha/Color Key reuse the synchronous
line RAM to hold the source row and then the computed result. The display
rectangle reader also uses bounded bursts and a line FIFO.

`c2_mem_to_axi4_adapter` packs/unpacks wide AXI beats, preserves byte lanes with
write strobes, and returns one abstract write response per accepted descriptor.
It locally rejects descriptors that are pixel-unaligned, cross 4 KiB, or would
need more than 256 wide AXI beats. It converts AXI errors to terminal abstract
errors and drains a malformed read through the native AXI `RLAST` before
accepting another transaction. The generated IP must support the adapter's
full-width INCR transactions; a smaller native limit requires a reviewed
configuration/adapter change rather than silently truncating a burst.

The owner arbiter must sit immediately before this adapter. It holds the render
owner through the complete write-data stream and delayed write response, or the
display owner through the terminal read response. Do not connect the two
masters directly to a DDR3 IP without an equivalent owner/ID mechanism. This
arbiter only covers renderer and scanout. If Sapphire also accesses DDR3 for
asset loading or the required CPU-rendering benchmark, add a system-level AXI
interconnect for the CPU and accelerator memory masters; do not wire them
onto the same DDR3 slave pins directly.

## Integration order

1. Generate and validate `c2_clock_reset_blackbox` replacement; keep the
   simulation branch for XSIM until lock/reset timing is measured.
2. Generate the board-matched DDR3 controller/PHY, connect the existing
   `m_axi_*` adapter output, and run fixed-pattern read/write tests before
   enabling the renderer. Check byte lane order, AXI data/ID width,
   4 KiB/native burst limits, calibration, one-for-one write responses and
   error termination. Confirm its user clock matches `clk_sys` or add AXI CDC.
3. Implement page/display-read CDC if system and pixel clocks differ; verify no
   descriptor/response loss under backpressure. Add a separate write-capable
   CDC only if a future architecture moves the renderer into another domain.
4. Replace the video seam with the required HDMI TX/PHY wrapper and verify
   640x480@60 operation, pixel-clock configuration and `de/hsync/vsync`
   latency using a fixed color-bar command. Its ready path must not
   backpressure an active fixed-rate raster; any such event is an error.
5. Generate/connect Sapphire and its address decoder/interconnect to the
   existing AXI4-Lite slave; implement the RISC-V command/completion/page-flip
   driver and CPU-versus-hardware FPS display. If caches cover the framebuffer,
   define flush/invalidate and ordering before hardware access or page flips.
6. Run real Efinity placement/routing and STA with generated IP and pin/clock
   constraints, then validate reset, DDR3 traffic, HDMI and performance on the
   actual board. A structurally valid empty-IP build is not this sign-off.

The blackboxes are not claims that the board IP is complete. Verification has
separate scopes: behavior-memory system tests, standalone AXI adapter tests,
the AXI4-Lite NOP/init-gating system test, and remaining-IP elaboration checks.
None demonstrates DDR3 calibration, real HDMI output or CPU/accelerator
performance on Ti60. PLL/reset behavior, CDC implementation, generated IP,
RISC-V software, physical pins and board-level timing remain bring-up work.
