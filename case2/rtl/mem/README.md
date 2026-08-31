# Memory-side bottom modules

`c2_burst_planner` turns a rectangle row into aligned burst descriptors. It:

- limits each burst to `MAX_BURST_BEATS`;
- optionally prevents crossing a 4 KiB boundary;
- preserves row stride and reports row/frame last;
- exposes only `req_valid/req_ready`, so it can feed the AXI4 DDR3 adapter or
  a simulation memory model.

Inputs must be aligned to `BEAT_BYTES`; zero dimensions and unaligned requests raise
the one-cycle `error`/`done` indication without emitting a request.

`render_cmd_mem_engine` is the first correctness baseline for Fill, Block
Copy, Alpha Blend and Color Key. It deliberately allows one memory
transaction at a time so a behavioral RAM can inject arbitrary request and
response stalls. `render_mem_model` is the matching XSIM model; its public
word array makes framebuffer scoreboards straightforward.

`render_burst_mem_model` is a separate XSIM model for the multi-beat read
contract. `req_len` is beats-minus-one; it returns consecutive response beats
and holds `rsp_last` stable while stalled. `render_owner_mem_model` extends the
same model with a separate write-data stream plus one delayed `wr_rsp` per
accepted write descriptor and is used by the integrated system regression.
Both read and write errors terminate the current behavioral-model transaction;
this finite-error rule is part of the real adapter contract as well.

`c2_burst_read_stream` converts one burst descriptor into a downstream
ready/valid data stream and checks early/missing `rsp_last` conditions. It has a
one-beat holding register, so an output line FIFO may apply arbitrary
backpressure.

`c2_rect_burst_reader` combines the planner and burst stream. It emits pixel
coordinates plus row/frame markers, but deliberately does not choose a line
buffer depth or a display clock domain.

`c2_burst_write_stream` is the write-side counterpart: it accepts one write
descriptor and forwards a separate `wr_valid/ready/data/strb/last` stream.
`render_write_burst_mem_model` consumes that channel in XSIM.  The
`c2_mem_arbiter_2m_owner` extension wires this data stream through a per-owner
channel. After a descriptor handshake, the selected master keeps the shared
write port through all write beats and the later write-completion response.
`wr_last` (or the advertised beat boundary) moves the owner into the response
phase; only `wr_rsp_valid && wr_rsp_ready` releases it. Early or missing
`wr_last` pulses `write_protocol_error`, and the adapter must then abort/finish
the native operation and emit exactly one error response. The response maps to
AXI `B` or an equivalent native-memory commit indication. The original
`c2_mem_arbiter_2m` remains unchanged for legacy single-beat users.

When `render_cmd_mem_engine.WRITE_BURST_ENABLE=1`, the engine collects a
rectangle row in its line buffer and emits bounded descriptor/data bursts. A
row wider than `MAX_WRITE_BEATS` is split into adjacent bursts, and each segment
is capped again at `WRITE_BOUNDARY_BYTES` (4096 by default), so no descriptor
crosses a 4 KiB boundary. The engine waits for each delayed `wr_rsp` before
advancing to the next segment or completing the command. Color Key reads the
destination on key hits before writing the complete row, preserving the legacy
“key leaves background unchanged” behavior. The system top enables this mode
by default; `WRITE_BURST_ENABLE=0` remains available only for the original
single-beat unit test.

When `READ_BURST_ENABLE=1`（系统默认），Block Copy 以分段源行 burst 填充同一个
line RAM；Alpha/Color Key 随后按相同规则读取完整目的行。目的响应与 line RAM 的
同步源像素读形成一拍流水，并把结果原位写回该 RAM，因此没有增加第二个 4096×16
缓存。读 descriptor 同样受 `MAX_READ_BEATS` 和默认 4 KiB 边界限制，并逐 beat
检查 `rsp_last`。Color Key 当前选择完整背景行读取/完整结果行写回，优先保证连续
burst；透明区段写掩码属于后续带宽优化。

`render_cmd_mem_engine` uses a synchronous-read line buffer with a registered
prefetch word. `c2_line_fifo` likewise has a registered first-word output,
synchronous memory read, end-of-line bit and synchronous flush. These coding
styles infer block RAM in the current Vivado proxy. An empty line FIFO takes
one clock to prefetch its first RAM word before asserting `out_valid`; this is
inside the ready/valid contract. The actual Efinix embedded-RAM mapping remains
an Efinity synthesis check.

`c2_mem_arbiter_2m_owner` is the system shared-memory boundary: client 0 is the
render engine and client 1 is the read-only scanout reader. It locks a pending
grant while the downstream descriptor port is stalled, uses the configured
priority for the first tie and round-robin tie breaking thereafter, and does
not assume AXI IDs. Reads are held through the terminal `rsp_last`; row writes
are held through their terminal `wr_rsp`. `c2_mem_arbiter_2m` is retained only
for legacy single-beat users.

The current independent regressions are:

- `tb_c2_burst_read_stream`: one 8-beat read, response/output stalls and zero
  length rejection;
- `tb_c2_line_fifo`: marker ordering, full/overflow, backpressure and flush;
- `tb_c2_mem_arbiter_burst`: a 3-beat response remains owned by client 0 while
  client 1 waits;
- `tb_c2_rect_burst_reader`: two strided rows split into four bursts with pixel
  coordinates and row/frame last markers.
- `tb_c2_burst_write_stream`: five-beat write data channel, stalls, byte strobes,
  early `last` error and zero-length rejection.
- `tb_c2_mem_arbiter_owner`: normal owner retention, delayed write completion,
  waiting display read, mid-burst out-of-range error, and post-error recovery.
- `tb_render_cmd_mem_engine_burst`: row segmentation, explicit 4 KiB split and
  late write-response error propagation.
- `tb/mem/tb_render_cmd_mem_engine_read_burst`: source/background row bursts,
  4 KiB split, response backpressure and early-`rsp_last` rejection.
- `tb_c2_cmd_mem_engine_burst`: engine + owner arbiter + behavior-model check,
  including read and write row bursts plus one completion response for every
  write descriptor.
