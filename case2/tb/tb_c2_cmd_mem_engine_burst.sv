`timescale 1ns/1ps

// End-to-end row-burst test: the command engine fetches source/background
// lines and writes result lines as bounded bursts through the owner-aware
// two-master arbiter into the behavioral memory.
module tb_c2_cmd_mem_engine_burst;
  localparam int DATA_W = 16;

  logic clk = 1'b0;
  always #5 clk = ~clk;
  logic rst_n = 1'b0;

  logic desc_valid, desc_ready;
  logic [31:0] desc_seq;
  logic [2:0] desc_op;
  logic [7:0] desc_flags;
  logic [1:0] desc_pixel_fmt;
  logic [31:0] desc_src_addr, desc_dst_addr;
  logic [15:0] desc_width, desc_height, desc_src_stride, desc_dst_stride;
  logic [31:0] desc_color;
  logic [7:0] desc_alpha;
  logic [15:0] desc_color_key;

  logic m0_req_valid, m0_req_ready, m0_req_write;
  logic [31:0] m0_req_addr;
  logic [15:0] m0_req_len, m0_req_wdata;
  logic [1:0] m0_req_wstrb;
  logic m0_wr_valid, m0_wr_ready;
  logic [15:0] m0_wr_data;
  logic [1:0] m0_wr_strb;
  logic m0_wr_last, m0_wr_error;
  logic m0_wr_rsp_valid, m0_wr_rsp_ready, m0_wr_rsp_error;
  logic m0_rsp_valid, m0_rsp_ready;
  logic [15:0] m0_rsp_rdata;
  logic m0_rsp_last, m0_rsp_error;

  logic m1_req_valid, m1_req_ready, m1_req_write;
  logic [31:0] m1_req_addr;
  logic [15:0] m1_req_len, m1_req_wdata;
  logic [1:0] m1_req_wstrb;
  logic m1_wr_valid, m1_wr_ready;
  logic [15:0] m1_wr_data;
  logic [1:0] m1_wr_strb;
  logic m1_wr_last, m1_wr_error;
  logic m1_wr_rsp_valid, m1_wr_rsp_ready, m1_wr_rsp_error;
  logic m1_rsp_valid, m1_rsp_ready;
  logic [15:0] m1_rsp_rdata;
  logic m1_rsp_last, m1_rsp_error;

  logic s_req_valid, s_req_ready, s_req_write;
  logic [31:0] s_req_addr;
  logic [15:0] s_req_len, s_req_wdata;
  logic [1:0] s_req_wstrb;
  logic s_wr_valid, s_wr_ready;
  logic [15:0] s_wr_data;
  logic [1:0] s_wr_strb;
  logic s_wr_last, s_wr_error;
  logic s_wr_rsp_valid, s_wr_rsp_ready, s_wr_rsp_error;
  logic s_rsp_valid, s_rsp_ready;
  logic [15:0] s_rsp_rdata;
  logic s_rsp_last, s_rsp_error;

  logic arb_busy, owner_valid, owner_m1, owner_write, arb_wr_error;
  logic [31:0] arb_write_protocol_error_count;
  logic [31:0] arb_write_response_count, arb_write_response_error_count;
  logic [31:0] grant_count, read_count, write_count, write_beat_count;
  logic [31:0] response_count, response_protocol_error_count,
               orphan_response_count;
  logic [31:0] orphan_write_response_count;

  logic done_valid, done_error, engine_busy;
  logic [31:0] done_seq, request_count, engine_read_count,
               engine_write_count, pixel_count, engine_error_count;

  render_cmd_mem_engine #(
    .WRITE_BURST_ENABLE(1'b1), .READ_BURST_ENABLE(1'b1),
    .MAX_READ_BEATS(2), .MAX_WRITE_BEATS(2), .LINE_BUFFER_PIXELS(8)
  ) u_engine (
    .clk, .rst_n, .desc_valid, .desc_ready, .desc_seq, .desc_op,
    .desc_flags, .desc_pixel_fmt, .desc_src_addr, .desc_dst_addr,
    .desc_width, .desc_height, .desc_src_stride_bytes(desc_src_stride),
    .desc_dst_stride_bytes(desc_dst_stride), .desc_color, .desc_alpha,
    .desc_color_key,
    .mem_req_valid(m0_req_valid), .mem_req_ready(m0_req_ready),
    .mem_req_write(m0_req_write), .mem_req_addr(m0_req_addr),
    .mem_req_len(m0_req_len), .mem_req_wdata(m0_req_wdata),
    .mem_req_wstrb(m0_req_wstrb), .mem_rsp_valid(m0_rsp_valid),
    .mem_rsp_ready(m0_rsp_ready), .mem_rsp_rdata(m0_rsp_rdata),
    .mem_rsp_last(m0_rsp_last), .mem_rsp_error(m0_rsp_error),
    .mem_wr_valid(m0_wr_valid), .mem_wr_ready(m0_wr_ready),
    .mem_wr_data(m0_wr_data), .mem_wr_strb(m0_wr_strb),
    .mem_wr_last(m0_wr_last), .mem_wr_error(m0_wr_error),
    .mem_wr_rsp_valid(m0_wr_rsp_valid),
    .mem_wr_rsp_ready(m0_wr_rsp_ready),
    .mem_wr_rsp_error(m0_wr_rsp_error),
    .done_valid, .done_error, .done_seq, .busy(engine_busy),
    .request_count, .read_count(engine_read_count),
    .write_count(engine_write_count), .pixel_count, .error_count(engine_error_count)
  );

  c2_mem_arbiter_2m_owner u_arb (
    .clk, .rst_n, .display_priority(1'b1),
    .m0_req_valid, .m0_req_ready, .m0_req_write, .m0_req_addr,
    .m0_req_len, .m0_req_wdata, .m0_req_wstrb,
    .m0_wr_valid, .m0_wr_ready, .m0_wr_data, .m0_wr_strb, .m0_wr_last,
    .m0_wr_error,
    .m0_wr_rsp_valid, .m0_wr_rsp_ready, .m0_wr_rsp_error,
    .m0_rsp_valid, .m0_rsp_ready, .m0_rsp_rdata, .m0_rsp_last, .m0_rsp_error,
    .m1_req_valid, .m1_req_ready, .m1_req_write, .m1_req_addr,
    .m1_req_len, .m1_req_wdata, .m1_req_wstrb,
    .m1_wr_valid, .m1_wr_ready, .m1_wr_data, .m1_wr_strb, .m1_wr_last,
    .m1_wr_error,
    .m1_wr_rsp_valid, .m1_wr_rsp_ready, .m1_wr_rsp_error,
    .m1_rsp_valid, .m1_rsp_ready, .m1_rsp_rdata, .m1_rsp_last, .m1_rsp_error,
    .s_req_valid, .s_req_ready, .s_req_write, .s_req_addr, .s_req_len,
    .s_req_wdata, .s_req_wstrb,
    .s_wr_valid, .s_wr_ready, .s_wr_data, .s_wr_strb, .s_wr_last,
    .s_wr_error,
    .s_wr_rsp_valid, .s_wr_rsp_ready, .s_wr_rsp_error,
    .s_rsp_valid, .s_rsp_ready, .s_rsp_rdata, .s_rsp_last, .s_rsp_error,
    .busy(arb_busy), .owner_valid, .owner_m1, .owner_write,
    .write_protocol_error(arb_wr_error),
    .write_protocol_error_count(arb_write_protocol_error_count),
    .grant_count, .read_count,
    .write_count, .write_beat_count,
    .write_response_count(arb_write_response_count),
    .write_response_error_count(arb_write_response_error_count),
    .response_count, .response_protocol_error_count, .orphan_response_count,
    .orphan_write_response_count
  );

  render_owner_mem_model #(.MEM_BYTES(4096), .READ_LATENCY(2)) u_mem (
    .clk, .rst_n, .req_valid(s_req_valid), .req_ready(s_req_ready),
    .req_write(s_req_write), .req_addr(s_req_addr), .req_len(s_req_len),
    .req_wdata(s_req_wdata), .req_wstrb(s_req_wstrb), .wr_valid(s_wr_valid),
    .wr_ready(s_wr_ready), .wr_data(s_wr_data), .wr_strb(s_wr_strb),
    .wr_last(s_wr_last), .wr_error(s_wr_error), .rsp_valid(s_rsp_valid),
    .wr_rsp_valid(s_wr_rsp_valid), .wr_rsp_ready(s_wr_rsp_ready),
    .wr_rsp_error(s_wr_rsp_error),
    .rsp_ready(s_rsp_ready), .rsp_rdata(s_rsp_rdata), .rsp_last(s_rsp_last),
    .rsp_error(s_rsp_error), .descriptor_count(), .read_count(),
    .write_count(), .write_beat_count(), .write_response_count(),
    .response_count(), .error_count()
  );

  assign m1_req_valid = 1'b0;
  assign m1_req_write = 1'b0;
  assign m1_req_addr = '0;
  assign m1_req_len = '0;
  assign m1_req_wdata = '0;
  assign m1_req_wstrb = '0;
  assign m1_wr_valid = 1'b0;
  assign m1_wr_data = '0;
  assign m1_wr_strb = '0;
  assign m1_wr_last = 1'b0;
  assign m1_wr_rsp_ready = 1'b1;
  assign m1_rsp_ready = 1'b1;

  function automatic [31:0] word(input integer addr);
    word = u_mem.mem[addr/2];
  endfunction

  task automatic send_desc(
    input [2:0] op, input [31:0] src, input [31:0] dst,
    input [15:0] w, input [15:0] h, input [15:0] ss, input [15:0] ds,
    input [31:0] color, input [7:0] alpha, input [15:0] key
  );
    begin
      @(negedge clk);
      desc_seq = desc_seq + 1;
      desc_op = op; desc_src_addr = src; desc_dst_addr = dst;
      desc_width = w; desc_height = h; desc_src_stride = ss;
      desc_dst_stride = ds; desc_color = color; desc_alpha = alpha;
      desc_color_key = key; desc_valid = 1'b1;
      while (!(desc_valid && desc_ready)) @(posedge clk);
      @(negedge clk);
      desc_valid = 1'b0;
    end
  endtask

  task automatic wait_done(input bit expect_error);
    integer guard;
    begin
      guard = 0;
      while (!done_valid && guard < 5000) begin
        @(posedge clk);
        guard = guard + 1;
      end
      if (guard >= 5000) $fatal(1, "burst engine completion timeout");
      if (done_error !== expect_error)
        $fatal(1, "burst engine done_error=%b expected=%b", done_error, expect_error);
      @(posedge clk);
    end
  endtask

  integer i;
  initial begin
    desc_valid = 1'b0; desc_seq = 0; desc_op = 0; desc_flags = 0;
    desc_pixel_fmt = 0; desc_src_addr = 0; desc_dst_addr = 0;
    desc_width = 0; desc_height = 0; desc_src_stride = 0;
    desc_dst_stride = 0; desc_color = 0; desc_alpha = 0; desc_color_key = 0;
    repeat (3) @(posedge clk);
    rst_n = 1'b1;

    // Fill 3x2; MAX_WRITE_BEATS=2 forces 2+1 beats per row.
    send_desc(3'd1, 0, 32'h0100, 3, 2, 0, 8, 32'h0000_F800, 8'hFF, 0);
    wait_done(1'b0);
    if (word(16'h0100) !== 16'hF800 || word(16'h0102) !== 16'hF800 ||
        word(16'h0104) !== 16'hF800 || word(16'h0108) !== 16'hF800 ||
        word(16'h010A) !== 16'hF800 || word(16'h010C) !== 16'hF800)
      $fatal(1, "burst fill mismatch");

    // Block copy.
    u_mem.mem[16'h0200/2] = 16'h001F;
    u_mem.mem[16'h0202/2] = 16'h07E0;
    u_mem.mem[16'h0204/2] = 16'hF800;
    u_mem.mem[16'h0208/2] = 16'hFFFF;
    u_mem.mem[16'h020A/2] = 16'h8410;
    u_mem.mem[16'h020C/2] = 16'h0000;
    send_desc(3'd2, 32'h0200, 32'h0300, 3, 2, 8, 8, 0, 0, 0);
    wait_done(1'b0);
    if (word(16'h0300) !== 16'h001F || word(16'h0302) !== 16'h07E0 ||
        word(16'h0304) !== 16'hF800 || word(16'h0308) !== 16'hFFFF ||
        word(16'h030A) !== 16'h8410 || word(16'h030C) !== 16'h0000)
      $fatal(1, "burst copy mismatch");

    // Color key: key pixel preserves destination through the row buffer.
    u_mem.mem[16'h0700/2] = 16'h1234;
    u_mem.mem[16'h0702/2] = 16'hABCD;
    u_mem.mem[16'h0800/2] = 16'h5555;
    u_mem.mem[16'h0802/2] = 16'h0000;
    send_desc(3'd4, 32'h0700, 32'h0800, 2, 1, 4, 4, 0, 0, 16'h1234);
    wait_done(1'b0);
    if (word(16'h0800) !== 16'h5555 || word(16'h0802) !== 16'hABCD)
      $fatal(1, "burst color-key mismatch");

    // Alpha blend one pixel.
    u_mem.mem[16'h0500/2] = 16'hF800;
    u_mem.mem[16'h0600/2] = 16'h001F;
    send_desc(3'd3, 32'h0500, 32'h0600, 1, 1, 2, 2, 0, 8'h80, 0);
    wait_done(1'b0);
    if (word(16'h0600) !== 16'h800F)
      $fatal(1, "burst alpha mismatch got=%h", word(16'h0600));

    if (arb_wr_error || arb_busy || engine_busy || engine_error_count != 0 ||
        arb_write_response_error_count != 0 ||
        arb_write_response_count != engine_write_count)
      $fatal(1, "burst engine/arbiter status error");
    $display("TB_C2_CMD_MEM_ENGINE_BURST_PASS req=%0d reads=%0d writes=%0d wr_rsp=%0d pixels=%0d",
             request_count, engine_read_count, engine_write_count,
             arb_write_response_count, pixel_count);
    $finish;
  end
endmodule
