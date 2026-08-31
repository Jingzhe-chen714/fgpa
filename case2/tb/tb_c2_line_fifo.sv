`timescale 1ns/1ps

module tb_c2_line_fifo;
  localparam int DATA_W = 16;
  localparam int DEPTH  = 4;

  logic clk = 1'b0;
  always #5 clk = ~clk;
  logic rst_n = 1'b0;
  logic flush;
  logic in_valid, in_ready, in_last;
  logic [DATA_W-1:0] in_data;
  logic out_valid, out_ready, out_last;
  logic [DATA_W-1:0] out_data;
  logic [$clog2(DEPTH+1)-1:0] level;
  logic full, empty, overflow, underflow;
  integer seen;
  reg [DATA_W-1:0] expected_data [0:3];
  reg expected_last [0:3];

  c2_line_fifo #(.DATA_W(DATA_W), .DEPTH(DEPTH)) dut (
    .clk, .rst_n, .flush,
    .in_valid, .in_ready, .in_data, .in_last,
    .out_valid, .out_ready, .out_data, .out_last,
    .level, .full, .empty, .overflow, .underflow
  );

  // Sample the handshake at the active edge, before the FIFO advances its
  // read pointer in the nonblocking assignment region.
  always @(posedge clk) begin
    if (rst_n && out_valid && out_ready) begin
      if (seen >= 4 || out_data !== expected_data[seen] ||
          out_last !== expected_last[seen])
        $fatal(1, "line fifo mismatch n=%0d data=%h last=%b", seen,
               out_data, out_last);
      seen = seen + 1;
    end
  end

  task automatic push_word(input logic [DATA_W-1:0] data,
                           input logic last);
    begin
      @(negedge clk);
      in_data = data;
      in_last = last;
      in_valid = 1'b1;
      while (!in_ready)
        @(negedge clk);
      @(negedge clk);
      in_valid = 1'b0;
    end
  endtask

  initial begin
    in_valid = 1'b0;
    in_data = '0;
    in_last = 1'b0;
    out_ready = 1'b0;
    flush = 1'b0;
    seen = 0;
    expected_data[0] = 16'h1111; expected_last[0] = 1'b0;
    expected_data[1] = 16'h2222; expected_last[1] = 1'b0;
    expected_data[2] = 16'h3333; expected_last[2] = 1'b1;
    expected_data[3] = 16'h4444; expected_last[3] = 1'b1;

    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    push_word(expected_data[0], expected_last[0]);
    push_word(expected_data[1], expected_last[1]);
    push_word(expected_data[2], expected_last[2]);
    push_word(expected_data[3], expected_last[3]);
    if (!full || level != DEPTH)
      $fatal(1, "line fifo did not reach full level=%0d full=%b", level, full);

    // A blocked producer must be reported without corrupting the queue.
    @(negedge clk);
    in_data = 16'hDEAD; in_last = 1'b0; in_valid = 1'b1;
    @(negedge clk);
    if (!overflow || in_ready)
      $fatal(1, "line fifo overflow indication missing");
    in_valid = 1'b0;

    // Drain with periodic backpressure; all four markers must remain ordered.
    for (integer c = 0; c < 20; c = c + 1) begin
      @(negedge clk);
      out_ready = ((c % 3) != 1);
    end
    out_ready = 1'b1;
    repeat (4) @(negedge clk);
    if (seen != 4 || !empty || level != 0)
      $fatal(1, "line fifo drain mismatch seen=%0d empty=%b level=%0d",
             seen, empty, level);

    // Keep the sink stopped while checking synchronous flush; otherwise the
    // newly pushed word could be legitimately consumed before flush executes.
    out_ready = 1'b0;
    push_word(16'hAAAA, 1'b1);
    @(negedge clk);
    flush = 1'b1;
    @(negedge clk);
    flush = 1'b0;
    if (!empty || level != 0)
      $fatal(1, "line fifo flush failed empty=%b level=%0d", empty, level);

    $display("TB_C2_LINE_FIFO_PASS seen=%0d", seen);
    $finish;
  end
endmodule
