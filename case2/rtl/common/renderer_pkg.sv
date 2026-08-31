`timescale 1ns/1ps

// 公共命令定义。保持为简单 packed 常量，便于 Verilog/SystemVerilog testbench
// 和后续 Efinity/AXI 适配器共同使用。
package renderer_pkg;
  // The command width is fixed by the packed command ABI.  Efinity treats
  // package parameters as localparams, so declare it explicitly to avoid a
  // vendor-specific parameter warning while retaining the same constant.
  localparam int CMD_W = 256;

  typedef enum logic [2:0] {
    OP_NOP          = 3'd0,
    OP_SOLID_FILL   = 3'd1,
    OP_BLOCK_COPY   = 3'd2,
    OP_ALPHA_BLEND  = 3'd3,
    OP_COLOR_KEY    = 3'd4
  } render_op_e;

  localparam logic [1:0] PIXEL_FMT_RGB565 = 2'd0;

  // flags[0]/flags[1] are reserved validity hints for a future CSR ABI.  In
  // the current baseline the operation code itself selects Alpha/Color Key,
  // so the corresponding fields are consumed even when these hints are 0.
  typedef struct packed {
    logic [55:0] reserved_hi;       // [255:200]
    logic [15:0] color_key;         // [199:184]
    logic [7:0]  alpha;             // [183:176]
    logic [31:0] color;             // [175:144]
    logic [15:0] dst_stride_bytes;  // [143:128]
    logic [15:0] src_stride_bytes;  // [127:112]
    logic [15:0] height;             // [111:96]
    logic [15:0] width;              // [95:80]
    logic [31:0] dst_addr;           // [79:48]
    logic [31:0] src_addr;           // [47:16]
    logic [2:0]  reserved_lo;        // [15:13]
    logic [1:0]  pixel_fmt;          // [12:11]
    logic [7:0]  flags;              // [10:3]
    logic [2:0]  op;                 // [2:0]
  } render_cmd_t;

  function automatic render_cmd_t unpack_cmd(input logic [CMD_W-1:0] raw);
    unpack_cmd = render_cmd_t'(raw);
  endfunction

  function automatic logic [CMD_W-1:0] pack_cmd(input render_cmd_t cmd);
    pack_cmd = cmd;
  endfunction
endpackage
