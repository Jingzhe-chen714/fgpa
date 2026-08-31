`timescale 1ns/1ps

module tb_c2_rect_burst_reader;
  localparam int DATA_W = 16;

  logic clk = 1'b0;
  always #5 clk = ~clk;
  logic rst_n = 1'b0;
  logic start, start_ready;
  logic [31:0] base_addr, stride_bytes, row_bytes;
  logic [15:0] rows;
  logic busy, done, error;
  logic [3:0] error_code;

  logic mem_req_valid, mem_req_ready, mem_req_write;
  logic [31:0] mem_req_addr;
  logic [15:0] mem_req_len;
  logic [15:0] mem_req_wdata;
  logic [1:0] mem_req_wstrb;
  logic mem_rsp_valid, mem_rsp_ready;
  logic [15:0] mem_rsp_rdata;
  logic mem_rsp_last, mem_rsp_error;

  logic pixel_valid, pixel_ready, pixel_last, frame_last;
  logic [15:0] pixel_data, pixel_x, pixel_y;
  logic [31:0] request_count, pixel_count, error_count;

  logic req_gate, rsp_gate;
  logic model_req_valid, model_req_ready;
  logic model_rsp_valid, model_rsp_ready;
  integer cycle_count;
  integer seen;
  reg [15:0] expected_data [0:9];
  reg [15:0] expected_x [0:9];
  reg [15:0] expected_y [0:9];

  c2_rect_burst_reader #(
    .ADDR_W(32), .DATA_W(DATA_W), .MAX_BURST_BEATS(3), .LIMIT_4KB(1'b1)
  ) u_reader (
    .clk, .rst_n, .start, .start_ready, .base_addr, .stride_bytes, .row_bytes,
    .rows, .busy, .done, .error, .error_code,
    .mem_req_valid, .mem_req_ready, .mem_req_write, .mem_req_addr,
    .mem_req_len, .mem_req_wdata, .mem_req_wstrb,
    .mem_rsp_valid, .mem_rsp_ready, .mem_rsp_rdata, .mem_rsp_last,
    .mem_rsp_error,
    .pixel_valid, .pixel_ready, .pixel_data, .pixel_x, .pixel_y,
    .pixel_last, .frame_last, .request_count, .pixel_count, .error_count
  );

  assign model_req_valid = mem_req_valid && req_gate;
  assign mem_req_ready   = model_req_ready && req_gate;
  assign mem_rsp_valid   = model_rsp_valid && rsp_gate;
  assign model_rsp_ready = mem_rsp_ready && rsp_gate;

  render_burst_mem_model #(
    .ADDR_W(32), .DATA_W(DATA_W), .LEN_W(16), .MEM_BYTES(4096), .READ_LATENCY(2)
  ) u_mem (
    .clk, .rst_n,
    .req_valid(model_req_valid), .req_ready(model_req_ready),
    .req_write(mem_req_write), .req_addr(mem_req_addr), .req_len(mem_req_len),
    .req_wdata(mem_req_wdata), .req_wstrb(mem_req_wstrb),
    .rsp_valid(model_rsp_valid), .rsp_ready(model_rsp_ready),
    .rsp_rdata(mem_rsp_rdata), .rsp_last(mem_rsp_last), .rsp_error(mem_rsp_error),
    .read_count(), .write_count(), .error_count()
  );

  always @(posedge clk) begin
    if (!rst_n) begin
      cycle_count <= 0;
      req_gate <= 1'b1;
      rsp_gate <= 1'b1;
    end else begin
      cycle_count <= cycle_count + 1;
      req_gate <= ((cycle_count % 5) != 1);
      rsp_gate <= ((cycle_count % 4) != 2);
    end
  end

  always_comb begin
    pixel_ready = rst_n && ((cycle_count % 3) != 1);
  end

  always @(posedge clk) begin
    if (rst_n && pixel_valid && pixel_ready) begin
      if (seen >= 10 || pixel_data !== expected_data[seen] ||
          pixel_x !== expected_x[seen] || pixel_y !== expected_y[seen])
        $fatal(1, "rect reader mismatch n=%0d data=%h x=%0d y=%0d last=%b frame=%b",
               seen, pixel_data, pixel_x, pixel_y, pixel_last, frame_last);
      if (pixel_last !== ((seen == 4) || (seen == 9)))
        $fatal(1, "row last mismatch n=%0d last=%b", seen, pixel_last);
      if (frame_last !== (seen == 9))
        $fatal(1, "frame last mismatch n=%0d frame=%b", seen, frame_last);
      seen = seen + 1;
    end
  end

  task automatic launch(input logic [31:0] addr, input logic [31:0] stride,
                        input logic [31:0] bytes, input logic [15:0] nrows);
    begin
      @(negedge clk);
      base_addr = addr;
      stride_bytes = stride;
      row_bytes = bytes;
      rows = nrows;
      start = 1'b1;
      while (!start_ready)
        @(negedge clk);
      @(negedge clk);
      start = 1'b0;
    end
  endtask

  task automatic wait_done(input logic expect_error);
    integer guard;
    begin
      guard = 0;
      while (!done && guard < 2000) begin
        @(negedge clk);
        guard = guard + 1;
      end
      if (guard >= 2000)
        $fatal(1, "rect reader timeout state=%0d busy=%b seen=%0d",
               u_reader.state, busy, seen);
      if (error !== expect_error)
        $fatal(1, "rect reader error=%b expected=%b code=%0d", error,
               expect_error, error_code);
    end
  endtask

  initial begin
    start = 1'b0;
    base_addr = '0; stride_bytes = '0; row_bytes = '0; rows = '0;
    seen = 0;
    for (integer k = 0; k < 5; k = k + 1) begin
      expected_data[k] = 16'h1000 + k;
      expected_x[k] = k;
      expected_y[k] = 0;
      u_mem.mem[(32'h0100 / 2) + k] = 16'h1000 + k;
      expected_data[5+k] = 16'h2000 + k;
      expected_x[5+k] = k;
      expected_y[5+k] = 1;
      u_mem.mem[(32'h0110 / 2) + k] = 16'h2000 + k;
    end

    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    launch(32'h0100, 32'd16, 32'd10, 16'd2);
    wait_done(1'b0);
    if (seen != 10 || request_count != 4 || pixel_count != 10 ||
        error_count != 0 || busy)
      $fatal(1, "rect counters seen=%0d req=%0d pix=%0d err=%0d busy=%b",
             seen, request_count, pixel_count, error_count, busy);

    launch(32'h0100, 32'd16, 32'd0, 16'd1);
    wait_done(1'b1);
    if (request_count != 4 || error_code != 4'd1)
      $fatal(1, "invalid rectangle was not rejected");

    $display("TB_C2_RECT_BURST_READER_PASS seen=%0d req=%0d", seen,
             request_count);
    $finish;
  end
endmodule
