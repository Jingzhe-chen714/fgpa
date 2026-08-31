# Command path

`render_cmd_fifo.sv` is the bounded ready/valid command queue. It never
overwrites an accepted command and reports a one-cycle `drop_event` if a
producer violates back-pressure while the queue is full.

`render_cmd_parser.sv` decodes the canonical 256-bit packet from
`rtl/common/renderer_pkg.sv`, assigns a monotonically increasing sequence
number, validates the RGB565 geometry/alignment contract, and presents one
descriptor at a time to the operation engine. Invalid packets are consumed
and counted but are not forwarded; `error_valid/error_code/error_seq` make the
failure visible to a later CSR/status block.

Every used RGB565 row must remain two-byte aligned: used source/destination
strides must be even as well as at least `width*2`. Odd strides are rejected
with `ERR_BAD_STRIDE` before a descriptor is forwarded. NOP does not use a
stride, and Solid Fill does not use the source stride. The engine's direct
descriptor input repeats this guard so bypassing the parser cannot partly
execute an odd-stride rectangle before failing on a later row.

The parser deliberately has no AXI, Sapphire or board-pin dependency. The
implemented `c2_csr_cmd_bridge` translates command-word writes into
`cmd_valid/cmd_data` and exposes counters/completion events. The optional
`c2_axi4lite_csr_adapter` in `rtl/bus` supplies the AXI control boundary.
