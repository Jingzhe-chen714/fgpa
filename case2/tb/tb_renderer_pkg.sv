`timescale 1ns/1ps
module tb_renderer_pkg;
  import renderer_pkg::*;

  render_cmd_t cmd;
  logic [CMD_W-1:0] raw;
  render_cmd_t roundtrip;

  initial begin
    cmd = '0;
    cmd.op = OP_ALPHA_BLEND;
    cmd.flags = 8'b0000_0011;
    cmd.pixel_fmt = PIXEL_FMT_RGB565;
    cmd.src_addr = 32'h0010_0000;
    cmd.dst_addr = 32'h0020_0000;
    cmd.width = 16'd640;
    cmd.height = 16'd480;
    cmd.src_stride_bytes = 16'd1280;
    cmd.dst_stride_bytes = 16'd1280;
    cmd.color = 32'h0000_f800;
    cmd.alpha = 8'd128;
    cmd.color_key = 16'h07e0;
    raw = pack_cmd(cmd);
    roundtrip = unpack_cmd(raw);

    assert (roundtrip.op == cmd.op)
      else $fatal(1, "op mismatch");
    assert (roundtrip.src_addr == cmd.src_addr && roundtrip.dst_addr == cmd.dst_addr)
      else $fatal(1, "address mismatch");
    assert (roundtrip.width == 16'd640 && roundtrip.height == 16'd480)
      else $fatal(1, "size mismatch");
    assert (roundtrip.alpha == 8'd128 && roundtrip.color_key == 16'h07e0)
      else $fatal(1, "pixel fields mismatch");
    $display("TB_RENDERER_PKG_PASS");
    $finish;
  end
endmodule

