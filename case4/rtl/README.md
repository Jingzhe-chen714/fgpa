# Case 4 算子 RTL

`case4_sobel_edge_ops.sv` contains the arithmetic part of the real-time
edge-detection chain.  It deliberately does not contain camera protocol,
line-buffer RAM, HDMI timing, or DDR control.

## Modules

| Module | Register stages | Output visible after accepting edge N |
|---|---:|---|
| `rgb_unpack_stream` | 1 | N |
| `gray_bt601_stream` / `gray_rgb_stream` | 1 | N |
| `window3x3_gray` | 1 | N |
| `xilinx_bram_sdp_row` | 1 | N |
| `window3x3_gray_xilinx_bram` | 2 | N+1 |
| `median3x3_u8` (default) | 3 | N+2 |
| `window3x3_median` (default) | 4 | N+3 |
| `case4_sobel3x3` | 3 | N+2 |
| threshold / overlay / RGB565 overlay / edge expansion | 1 each | N |
| `case4_sobel_edge_pipeline` | 5 | N+4 |
| `case4_gray_sobel_core` (array) | 6 | N+5 |
| `case4_gray_sobel_core_xilinx_bram` | 7 | N+6 |
| `case4_gray_median_sobel_core` (array, default) | 10 | N+9 |
| `case4_gray_median_sobel_core_xilinx_bram` (default) | 12 | N+11 |

N is the edge accepting the input pixel completing the corresponding window
(or final 5×5 support for the cascade), not the frame's first pixel. Outputs
are observed after nonblocking assignments settle. Thus one register stage
produces a result after N, not N+1. A downstream register consumes it at N+1.
There is no full-frame store and II remains one pixel/window per clock.

The median now uses 19 comparison decisions with row sort / cross-row
selection / final median registers. `PIPELINE_STAGES=1` explicitly selects
the legacy one-register latency, and `REGISTER_OUTPUT=0` defaults to the
combinational reference mode. Defaults have changed; metadata and any external
parallel RGB path must account for the additional TWO register stages.
The median cascade adds a second window and the registered 9-point median.  Its
final valid centre region is `(IMG_WIDTH-4)×(IMG_HEIGHT-4)`; the stream adapter
rebases the first median image to `(IMG_WIDTH-2)×(IMG_HEIGHT-2)` before the
second window and restores the original coordinate by `+1` at its output.

## Window and sideband contract

`case4_sobel3x3` receives nine unsigned pixels:

```text
p00 p01 p02
p10 p11 p12       p11 is the centre pixel
p20 p21 p22
```

`in_x/in_y` identify the centre pixel.  `in_valid` denotes a pixel/coordinate
transfer; `in_win_valid` denotes that all nine values are a usable neighbourhood
(normally false on the one-pixel border).  The output signals are:

```text
out_valid       delayed in_valid
out_win_valid   delayed (in_valid && in_win_valid)
out_sof/eol/eof, out_x/out_y, out_rgb  delayed with out_valid
```

Use `out_win_valid` for Sobel/threshold results.  Border transfers retain
`out_rgb` but produce zero `Gx`, `Gy`, magnitude and edge.  Sideband markers
are gated by `in_valid`, so they cannot appear on a bubble.

The current `window3x3_gray.sv` generator emits only valid interior windows
and uses an active-high synchronous `rst`. All arithmetic modules now use
active-low SYNCHRONOUS `rst_n`; inversion changes polarity only:

```text
Sobel.in_valid     = window.out_valid
Sobel.in_win_valid = window.out_valid
Sobel.rst_n        = ~window_rst
```

An external asynchronous reset must be conditioned at the eventual system
boundary; these modules do not implement that clock-domain function. A pulse
entirely between rising edges must not clear any registered algorithm output.
The original RGB path needs matching spatial and temporal alignment, not just
one unconditional delay register. A future window block that emits border bubbles
can instead connect its transfer-valid and neighbourhood-valid separately.

## Xilinx BRAM boundary

`window3x3_gray_xilinx_bram.sv` is the current Vivado implementation of the
line-buffer stage.  It instantiates two `xilinx_bram_sdp_row.sv` wrappers,
which instantiate XPM `xpm_memory_sdpram` with a one-cycle synchronous read and
`READ_FIRST` collision behavior.  This path is intentionally kept out of the
default portable `run_xsim.ps1` regression; run
`case4/scripts/run_xsim_xilinx_bram.ps1` when Vivado's XPM library is available.

This is a vendor boundary, not an algorithm change.  When moving to Efinix or
another FPGA, replace the wrapper/IP and preserve its latency, read-during-write
and reset contract, then rerun the tap and 640×480 scoreboards.  The complete
migration checklist is in `case4/BRAM_PORTABILITY.md`.

`case4_gray_sobel_core.sv` is the algorithm-only packed-pixel wrapper. It is
useful for XSIM and later integration, but deliberately does not produce an
RGB overlay: the original RGB stream must be delayed or buffered in parallel
before it is joined to `case4_edge_overlay`.

`case4_gray_median_sobel_core.sv` is the corresponding optional denoise path.
It deliberately keeps two independent window stages: sharing one line buffer
without a frame store would mix the input and median-image rasters.  Use the
small `tb_gray_median_sobel_core.sv` scoreboard before changing the coordinate
rebasing or enabling the path in a display top level.

## Arithmetic contract (bit exact)

For 8-bit pixels:

```text
gx = (p02-p00) + 2*(p12-p10) + (p22-p20)
gy = (p20-p00) + 2*(p21-p01) + (p22-p02)
mag = abs(gx) + abs(gy)
edge = in_win_valid && (mag >= threshold)
```

The implementation widens every pixel before subtraction.  Default widths are
11-bit signed partials, 12-bit signed gradients (mathematical range
`-1020..+1020`) and 11-bit unsigned magnitude. The joint Sobel L1 maximum is
1530 for 8-bit samples (2040 was a conservative independent-gradient bound).
The threshold accepts the entire unsigned 11-bit domain `0..2047`.
`PART_W >= PIX_W+2`, `GRAD_W >= PIX_W+3`, `MAG_W >= PIX_W+3` are enforced;
wider MAG ports are explicitly zero-extended. The `×2` terms are
arithmetic shifts, so no DSP is required.  Invalid windows are explicitly
zeroed rather than relying on a border padding convention.

## XSIM self-check

From the repository root, with Vivado 2023.1 installed:

```powershell
powershell -ExecutionPolicy Bypass -File case4\scripts\run_xsim.ps1
```

The script runs:

* `tb_gray_rgb.sv`: exhaustive 65,536-word RGB565 plus mapped RGB888 gray test;
* `tb_image_operators.sv`: 8×6 frame, all 3×3 taps, median, signed Sobel,
  threshold, RGB888 overlay and RGB565 overlay.
* `tb_gray_sobel_core.sv`: packed RGB888 → gray → window → Sobel → threshold
  integration check;
* `tb_gray_sobel_core_565.sv`: the same packed-core check with RGB565
  expansion and grayscale reference;
* `tb_gray_median_sobel_core.sv`: portable two-window median→Sobel cascade,
  including coordinate rebasing, final `(W-4)×(H-4)` valid area and numerical
  Gx/Gy/magnitude/threshold checks;
* `tb_hex_core.sv`: `$readmemh` vectors generated by Python Golden, checked
  sample by sample against the packed core.

Successful output contains `TB_GRAY_RGB PASS` and
`TB_IMAGE_OPERATORS PASS`, followed by the packed-core and HEX-scoreboard pass
messages.  The separate boundary-value testbench
`tb_case4_sobel_extremes.sv` also passes the ±1020 gradient cases.

The Xilinx-specific path is intentionally a separate regression because it
requires Vivado's XPM source:

```powershell
powershell -ExecutionPolicy Bypass -File case4\scripts\run_xsim_xilinx_bram.ps1 -Full640
```

It checks the XPM window, packed BRAM core, median→Sobel BRAM cascade and the
640×480 valid counts (`304964` for one window, `302736` after median cascade).
