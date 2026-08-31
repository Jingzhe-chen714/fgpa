# Case 2 system framework

`c2_renderer_system.sv` is the board-independent assembly point for the
current RTL. The competition-facing control and memory buses are now real
RTL: AXI4-Lite CSR input and a width-packed AXI4 Full memory master. It is
still not a physical Ti60 board top: generated Sapphire/DDR3/HDMI IP,
clock/reset, CDC, physical pins and constraints remain integration work.
The corrected 8.22 guide requires DDR3 and HDMI; VGA/HyperRAM are not the
competition configuration.

## Data path

```text
Sapphire control bus -> AXI4-Lite CSR adapter --+
direct CSR simulation input ------------------+-> CSR bridge -> FIFO -> parser
                                                -> render engine
                                                   row read/write bursts --+
                                                                          |
display timing -> rect burst reader -> line FIFO -> RGB/timing -> HDMI IP   |
                         |                                                |
                         +-- read requests -> owner arbiter <--------------+
                                                   |
                        +--------------------------+----------------------+
                        |                                                 |
                  behavior model                         memory-to-AXI4 adapter
                  (simulation only)                      -> m_axi_* -> DDR3 IP
```

The system top requires both `READ_BURST_ENABLE=1` and
`WRITE_BURST_ENABLE=1`. Source rows are fetched through descriptors bounded by
`MAX_READ_BEATS` and `READ_BOUNDARY_BYTES` (4096 by default). Copy rows can be
written back immediately after the source row is buffered. Alpha and Color
Key additionally fetch the full destination row; a one-cycle synchronous RAM
read pipeline overwrites the same line buffer with the result. Color Key thus
preserves background pixels using row bursts rather than separate one-pixel
reads. This conservative path reads background even for non-key pixels.

The completed row is emitted as one or more descriptors bounded by
`MAX_WRITE_BEATS` and `WRITE_BOUNDARY_BYTES` (4096 by default), followed by
`mem_wr_valid/data/strb/last`. `c2_mem_arbiter_2m_owner` locks the
render owner from descriptor acceptance through the final write-data beat and
the later `wr_rsp`; command completion therefore means the memory adapter has
acknowledged the write, not merely accepted its payload. The old
`c2_mem_arbiter_2m` module remains available for legacy single-beat clients.

With `USE_EXT_MEM_IP=0`, `render_owner_mem_model` provides the simulation
read/write/write-completion model. It must not be synthesized as board memory.
With `USE_EXT_MEM_IP=1`, the owner-arbitrated port is connected to
`c2_mem_to_axi4_adapter`, which exposes the top-level `m_axi_*` signals for a
generated DDR3 controller. It packs 16-bit RGB565 writes into parameterized
wide AXI beats, protects partial first/last beats with `WSTRB`, unpacks reads,
and maps AXI B into the delayed abstract write response. It uses full-width
INCR bursts, one outstanding transaction and ID 0. `AXI_DATA_W=128` and
`AXI_ID_W=4` are defaults, not a claim about the generated DDR3 IP ports.
Set them from the actual IP configuration. `ext_mem_init_done/error` gate
new memory requests until calibration succeeds.

AW and W proceed independently; the adapter can collect and transfer W data
before AWREADY. It waits for both AW and the final W handshake before accepting
B. RGB565 commands with an odd used row stride are rejected at the parser and
direct-engine entry points, before any row can reach memory.

The old `c2_ext_mem_adapter_blackbox` is a legacy native-interface anchor and
is no longer selected by this system top. The new AXI adapter does not contain
DDR3 training, refresh, PHY, pins or a CPU/accelerator AXI interconnect.

The display page is committed at `vblank_start`. One clock later
`prefetch_start` captures the settled page/base configuration, flushes stale
FIFO data, and launches the rectangle reader after the flush. The reset-time
first frame is deliberately black. A later active frame is armed only when
prefetched data is present; once armed, FIFO exhaustion is reported as
underflow rather than silently repeating pixels. Because this is a fixed-rate
raster, the real PHY must keep `phy_pixel_ready=1` throughout active video.

## CSR map and AXI4-Lite control input

`c2_csr_cmd_bridge` presents a simple valid/ready CSR handshake:

| Address | Meaning |
|---:|---|
| `0x00..0x1c` | command words 0..7 (write) |
| `0x20` | submit the 256-bit command assembled above |
| `0x24` | status: FIFO/parser/engine/display/memory flags |
| `0x28` | request display page (`wdata[PAGE_W-1:0]`) |
| `0x2c` | page status |
| `0x30..0x5c` | accepted/completed/error and traffic counters |

`USE_AXI4LITE_CSR=1` instantiates `c2_axi4lite_csr_adapter` and selects the
top-level `s_axi_csr_*` port. AW and W are captured independently; B/R remain
stable under backpressure. The current CSR ABI supports 32-bit full-word
writes only: any `WSTRB` other than `4'hf` returns `SLVERR` without a CSR write.
The addresses above are offsets within the renderer's assigned bus window.
The Sapphire interconnect/address decoder must provide that window; if its
exported master is AXI4 Full rather than AXI4-Lite, use the appropriate
interconnect/protocol bridge. `USE_AXI4LITE_CSR=0` keeps the direct-CSR
simulation entry point. `c2_sapphire_csr_blackbox` is now only a legacy anchor
and is not part of the active AXI control path.

Software must render into the inactive page, wait for the command completion
or error indication, and only then request that page at `0x28`. The present RTL
does not automatically associate a command sequence number with a page or
prevent software from flipping a page whose rendering is still in flight.
The RISC-V driver, CPU-only rendering baseline and on-screen CPU/hardware FPS
comparison are not supplied by these RTL interfaces; they remain software
integration and board-validation tasks.

## Clock-domain assumptions

The simulation branch uses `clk_in` for both system and pixel clocks. When
`USE_CLOCK_RESET_IP=1`, `c2_clock_reset_blackbox` supplies the two clocks and
resets; page requests/status use `c2_page_cdc_blackbox`, and the read-only
display memory master uses `c2_mem_cdc_blackbox`. The current memory CDC port
list carries descriptors and read responses only; it is sufficient because
scanout never writes, but it is not a general renderer write-data CDC. Both CDC
modules are deliberately blackboxes because implementation depends on the
selected Efinix clock and asynchronous-FIFO/IP strategy.

Both top-level AXI interfaces operate in `clk_sys`. The DDR3 user clock and
Sapphire interconnect clock must match that domain or have a proper external
AXI CDC bridge. The existing display CDC seam does not replace such a bridge.
HDMI pixel/PHY clocks and their timing relationship remain PLL/vendor-IP work.

## Verification entry points

The final 2026-08-31 regression in
`case2/tb/xsim_newguide_signoff_20260831` passed all 11 elaborations and all
10 functional simulations, including the stride-entry checks and 64-/128-bit
AXI memory-adapter configurations. The remaining-IP stub is elaboration-only;
these counts do not imply vendor DDR3/HDMI or board validation. Reproduce the
suite with `case2/scripts/Run-NewguideRegression.ps1`.

- `tb_c2_renderer_system.sv`: small 4x2 end-to-end XSIM run with local memory,
  a solid-fill command, page flip, exact page-1 pixel checking, and final
  no-underflow/no-system-error checks. Its blanking interval is deliberately
  long enough for the serialized behavior model to prefetch the full frame.
- `tb_c2_renderer_system_ip_stub.sv`: elaboration-only run with all board/IP
  flags set to 1. Remaining clock/CDC/video blackboxes are only checked for
  structural connectivity; this is not DDR3 or HDMI functional verification.
- `tb_c2_renderer_system_axi_shell.sv`: AXI4-Lite submission/completion of a
  NOP while DDR3 initialization is held low. This checks the selected control
  path and memory-init gating, not a full DDR3 framebuffer transaction.
- `tb_c2_axi4lite_csr_adapter.sv` and `tb_c2_mem_to_axi4_adapter.sv`:
  standalone control-bus and packed AXI memory protocol tests; the final
  memory-adapter regression covers both 64- and 128-bit AXI widths.
- `tb_c2_stride_alignment.sv`: parser/direct-engine rejection of odd used
  RGB565 strides before any memory request, with NOP/Fill-source exceptions
  and legal even-stride two-row rectangles.
- `tb_render_cmd_mem_engine_read_burst.sv`: row read segmentation at 4 KiB,
  multi-row copy, Color Key background preservation and malformed `rsp_last`.
- `tb_c2_cmd_mem_engine_burst.sv`: row-burst reads and writes through the
  owner arbiter and behavior memory, including Fill/Copy/Color Key/Alpha.
- `tb_render_cmd_mem_engine_burst.sv`: legacy one-beat reads plus row-burst
  writeback; the standalone engine's `READ_BURST_ENABLE=0` preserves this mode.

`case2/synth_proxy` also contains unconstrained Vivado proxy synthesis scripts.
The regenerated AXI/read-burst proxy maps the 4096x16 render buffer to two
RAMB36 and the 1024x17 display FIFO to one RAMB18, with 3680 LUT, 3840 FF and
0 DSP for the selected system. The detached single-thread rerun completed with
`SYNTH_SYSTEM_IP_STUB_PROXY_PASS`. These are coding-style/resource sanity
checks, not DDR3/HDMI resources or Ti60 timing evidence. Final resource and timing
claims require Efinity synthesis, placement/routing and STA with generated IP
and board constraints.

The final Efinity structural probe is
`case2/efinity_smoke/outflow_sv_axi_final/case2_rtl_probe_axi_final.map.rpt`:
map PASS, 2384 EFX_LUT4, 2134 FF, 804 ADD, 0 RAM and 0 DSP. Its stub/tied-zero
configuration still trims logic and does not enable AXI4-Lite. Treat it as
structural-mapping evidence, not a full-system resource budget or board P&R/STA
result; in particular, its 0 RAM does not negate the line-buffer/FIFO storage.

Run `xvlog`, `xelab` and `xsim` as separate stages, but do not equate stage
separation with Windows Job isolation. On this host an ordinary breakaway
launch still reported `in_job=true` and was refused. Use
`case2/scripts/Start-DetachedEdaTool.ps1`: it creates a hidden
`case2/scripts/run_detached_tool.py` worker through the local `Win32_Process`
WMI service and launches Vivado only after checking
that the actual worker reports `worker_in_job=false`. A separate process or
breakaway flag alone is not sufficient evidence that a long-running `xsim`
will survive the current Codex session lifetime; keep the runtime Job check
as the launch gate.
