`timescale 1ns/1ps

module tb_c2_burst_write_stream;
  localparam int DATA_W = 16;

  logic clk = 1'b0;
  always #5 clk = ~clk;
  logic rst_n = 1'b0;
  logic start;
  logic [31:0] start_addr;
  logic [15:0] start_beats;
  logic busy, done, error;

  logic req_valid, req_ready, req_write;
  logic [31:0] req_addr;
  logic [15:0] req_len, req_wdata;
  logic [1:0] req_wstrb;
  logic in_valid, in_ready, in_last;
  logic [15:0] in_data;
  logic [1:0] in_strb;
  logic wr_valid, wr_ready, wr_last;
  logic [15:0] wr_data;
  logic [1:0] wr_strb;
  logic [31:0] request_count, beat_count, error_count;
  logic req_gate, wr_gate;
  logic model_req_valid, model_req_ready, model_wr_valid, model_wr_ready;
  integer cycle_count;

  c2_burst_write_stream #(.ADDR_W(32), .DATA_W(DATA_W), .LEN_W(16)) u_writer (
    .clk, .rst_n, .start, .start_addr, .start_beats, .busy, .done, .error,
    .req_valid, .req_ready, .req_write, .req_addr, .req_len, .req_wdata,
    .req_wstrb, .in_valid, .in_ready, .in_data, .in_strb, .in_last,
    .wr_valid, .wr_ready, .wr_data, .wr_strb, .wr_last,
    .request_count, .beat_count, .error_count
  );

  assign model_req_valid = req_valid && req_gate;
  assign req_ready       = model_req_ready && req_gate;
  assign model_wr_valid  = wr_valid && wr_gate;
  assign wr_ready        = model_wr_ready && wr_gate;

  render_write_burst_mem_model #(
    .ADDR_W(32), .DATA_W(DATA_W), .LEN_W(16), .MEM_BYTES(4096)
  ) u_mem (
    .clk, .rst_n,
    .req_valid(model_req_valid), .req_ready(model_req_ready),
    .req_write(req_write), .req_addr(req_addr), .req_len(req_len),
    .req_wdata(req_wdata), .req_wstrb(req_wstrb),
    .wr_valid(model_wr_valid), .wr_ready(model_wr_ready), .wr_data(wr_data),
    .wr_strb(wr_strb), .wr_last(wr_last),
    .descriptor_count(), .write_count(), .error_count()
  );

  always @(posedge clk) begin
    if (!rst_n) begin
      cycle_count <= 0;
      req_gate <= 1'b1;
      wr_gate <= 1'b1;
    end else begin
      cycle_count <= cycle_count + 1;
      req_gate <= ((cycle_count % 4) != 1);
      wr_gate <= ((cycle_count % 3) != 2);
    end
  end

  task automatic launch(input logic [31:0] addr, input logic [15:0] beats);
    begin
      @(negedge clk);
      start_addr = addr;
      start_beats = beats;
      start = 1'b1;
      @(negedge clk);
      start = 1'b0;
    end
  endtask

  task automatic send_word(input logic [15:0] data, input logic last);
    begin
      @(negedge clk);
      in_data = data;
      in_strb = 2'b11;
      in_last = last;
      in_valid = 1'b1;
      while (!in_ready)
        @(negedge clk);
      @(negedge clk);
      in_valid = 1'b0;
    end
  endtask

  task automatic wait_done(input logic expect_error);
    integer guard;
    begin
      guard = 0;
      while (!done && guard < 1000) begin
        @(negedge clk);
        guard = guard + 1;
      end
      if (guard >= 1000)
        $fatal(1, "burst writer timeout busy=%b", busy);
      if (error !== expect_error)
        $fatal(1, "burst writer error=%b expected=%b", error, expect_error);
    end
  endtask

  initial begin
    start = 1'b0;
    start_addr = '0;
    start_beats = '0;
    in_valid = 1'b0;
    in_data = '0;
    in_strb = 2'b11;
    in_last = 1'b0;

    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    launch(32'h0100, 16'd5);
    send_word(16'hCA00, 1'b0);
    send_word(16'hCA01, 1'b0);
    send_word(16'hCA02, 1'b0);
    send_word(16'hCA03, 1'b0);
    send_word(16'hCA04, 1'b1);
    wait_done(1'b0);
    for (integer k = 0; k < 5; k = k + 1)
      if (u_mem.mem[(32'h0100 / 2) + k] !== (16'hCA00 + k))
        $fatal(1, "write memory mismatch k=%0d data=%h",
               k, u_mem.mem[(32'h0100 / 2) + k]);
    if (request_count != 1 || beat_count != 5 || error_count != 0 || busy)
      $fatal(1, "writer counters req=%0d beats=%0d err=%0d busy=%b",
             request_count, beat_count, error_count, busy);

    // An early line marker is reported and terminates the descriptor.
    launch(32'h0120, 16'd3);
    send_word(16'hD000, 1'b1);
    wait_done(1'b1);
    if (request_count != 2 || beat_count != 6)
      $fatal(1, "early-last accounting mismatch req=%0d beats=%0d",
             request_count, beat_count);

    launch(32'h0100, 16'd0);
    wait_done(1'b1);
    if (request_count != 2)
      $fatal(1, "zero-length writer emitted a request");

    $display("TB_C2_BURST_WRITE_STREAM_PASS req=%0d beats=%0d", request_count,
             beat_count);
    $finish;
  end
endmodule
