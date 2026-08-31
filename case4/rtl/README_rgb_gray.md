# RGB unpack and fixed BT.601 gray RTL

This note documents `rgb_unpack_stream.sv`, `gray_bt601_stream.sv`,
`gray_rgb_stream.sv`, and the `out_*` compatibility wrappers in
`case4_rgb_frontend.sv`.  They are independent of the camera, line buffers,
and display timing and accept one pixel transaction per clock.

## Modules and latency

| File | Module | Purpose | Latency |
|---|---|---|---:|
| `rgb_unpack_stream.sv` | `rgb_unpack_stream` | packed RGB565/RGB888 to R8/G8/B8 | 1 clock |
| `gray_bt601_stream.sv` | `gray_bt601_stream` | R8/G8/B8 to fixed BT.601 luma | 1 clock |
| `gray_rgb_stream.sv` | `gray_rgb_stream` | packed RGB directly to gray | 1 clock |
| `case4_rgb_frontend.sv` | `*_stream_out` | same blocks with `out_*` naming | 1 clock |

The combined block is useful when only grayscale is needed.  If the original
RGB is needed for edge overlay, use `rgb_unpack_stream_out` followed by
`gray_bt601_stream_out`; this path has two clocks of latency.

## Pixel format

`PIXEL_FORMAT=0` selects the conventional RGB565 word:

```text
pixel_in[15:11] = R5
pixel_in[10:5]  = G6
pixel_in[4:0]   = B5
```

The channels are expanded by bit replication:

```text
R8 = {R5, R5[4:2]}
G8 = {G6, G6[5:4]}
B8 = {B5, B5[4:2]}
```

`PIXEL_FORMAT=1` selects RGB888 (`[23:16] = R`, `[15:8] = G`, `[7:0] = B`).
For RGB565, the upper eight bits of the common 24-bit input are ignored.

## Stream contract

`rst` is synchronous, active high.  `in_valid` qualifies a transaction;
`in_sof/in_eol/in_eof` and `in_x/in_y` are meaningful only with it.  At each
rising edge, outputs represent the corresponding input from one clock earlier.
Invalid cycles clear valid, sideband, coordinates, and pixel data, which avoids
stale markers at frame and line gaps.  There is no ready/back-pressure port.

## Fixed-point equation and widths

```text
acc = 77*R + 150*G + 29*B
Y   = (acc + 128) >> 8
```

The constants sum to 256.  The implementation uses shift/add terms (no DSP
requirement), exports a 17-bit accumulator, and emits an 8-bit rounded luma.
For legal 8-bit inputs the maximum accumulator is 65,280, so the rounded
output remains in 0..255.

`case4/verify_fixed_gray.py` exhaustively checks all 65,536 RGB565 words and
all 16,777,216 RGB888 colors against real-valued BT.601.  The maximum
continuous error is 0.931 LSB for RGB565 (after expansion) and 0.945 LSB for
RGB888, both strictly below one output-code LSB.  The test separately reports
occasional one-code differences when comparing two independently rounded
integer references.

## Vivado XSIM smoke test

The exhaustive transaction testbench is
`case4/tb/tb_gray_rgb.sv`. It drives all 65,536 RGB565 words and the
corresponding expanded RGB888 colors. A successful run prints
`TB_GRAY_RGB PASS`:

```powershell
powershell -ExecutionPolicy Bypass -File case4/scripts/run_xsim.ps1
```

The same script also runs the window/median/Sobel/threshold/overlay regression.
