`timescale 1ns/1ps

// Corner regression for the block-RAM front-prefetch implementation. It
// exercises the one-entry pop+push bubble and a full FIFO pop+push without
// assuming first-word fall-through in the cycle immediately after a push.
module tb_c2_line_fifo_corner;
  localparam int DATA_W = 16;
  localparam int DEPTH  = 4;

  logic clk = 1'b0;
  always #5 clk = ~clk;
  logic rst_n = 1'b0;
  logic flush = 1'b0;
  logic in_valid, in_ready, in_last;
  logic [DATA_W-1:0] in_data;
  logic out_valid, out_ready, out_last;
  logic [DATA_W-1:0] out_data;
  logic [$clog2(DEPTH+1)-1:0] level;
  logic full, empty, overflow, underflow;

  logic [DATA_W-1:0] expected_data [0:15];
  logic expected_last [0:15];
  integer expected_head;
  integer expected_tail;
  integer guard;

  c2_line_fifo #(.DATA_W(DATA_W), .DEPTH(DEPTH)) dut (
    .clk, .rst_n, .flush,
    .in_valid, .in_ready, .in_data, .in_last,
    .out_valid, .out_ready, .out_data, .out_last,
    .level, .full, .empty, .overflow, .underflow
  );

  task automatic add_expected(input logic [DATA_W-1:0] data,
                              input logic last);
    begin
      expected_data[expected_tail] = data;
      expected_last[expected_tail] = last;
      expected_tail = expected_tail + 1;
    end
  endtask

  task automatic push_word(input logic [DATA_W-1:0] data,
                           input logic last);
    begin
      add_expected(data, last);
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

  always @(posedge clk) begin
    if (rst_n && out_valid && out_ready) begin
      if (expected_head >= expected_tail ||
          out_data !== expected_data[expected_head] ||
          out_last !== expected_last[expected_head])
        $fatal(1, "corner fifo mismatch n=%0d data=%h last=%b",
               expected_head, out_data, out_last);
      expected_head = expected_head + 1;
    end
  end

  initial begin
    in_valid = 1'b0;
    in_data = '0;
    in_last = 1'b0;
    out_ready = 1'b0;
    expected_head = 0;
    expected_tail = 0;

    repeat (3) @(posedge clk);
    rst_n = 1'b1;

    // Occupancy one: pop A while pushing B. The RAM-prefetch design may insert
    // one valid-low cycle, but B must remain queued and emerge exactly once.
    push_word(16'h00A1, 1'b0);
    guard = 0;
    while (!out_valid && guard < 20) begin
      @(negedge clk);
      guard = guard + 1;
    end
    if (!out_valid || level != 1)
      $fatal(1, "single-word prefetch failed level=%0d", level);

    add_expected(16'h00B2, 1'b1);
    @(negedge clk);
    in_data = 16'h00B2; in_last = 1'b1; in_valid = 1'b1;
    out_ready = 1'b1;
    @(negedge clk);
    in_valid = 1'b0;
    out_ready = 1'b0;
    if (level != 1)
      $fatal(1, "single pop+push changed occupancy level=%0d", level);
    guard = 0;
    while (!out_valid && guard < 20) begin
      @(negedge clk);
      guard = guard + 1;
    end
    out_ready = 1'b1;
    @(negedge clk);
    out_ready = 1'b0;

    // Full FIFO: the simultaneous pop opens exactly one slot for G. Remaining
    // output order must be C,D,E,F,G with no overwrite at wrapped pointers.
    push_word(16'h00C3, 1'b0);
    push_word(16'h00D4, 1'b0);
    push_word(16'h00E5, 1'b0);
    push_word(16'h00F6, 1'b1);
    if (!full || level != DEPTH)
      $fatal(1, "corner fifo did not become full level=%0d", level);

    add_expected(16'h00A7, 1'b1);
    @(negedge clk);
    in_data = 16'h00A7; in_last = 1'b1; in_valid = 1'b1;
    out_ready = 1'b1;
    @(negedge clk);
    in_valid = 1'b0;

    guard = 0;
    while ((expected_head != expected_tail || !empty) && guard < 50) begin
      @(negedge clk);
      guard = guard + 1;
    end
    if (guard >= 50 || expected_head != expected_tail || !empty || level != 0)
      $fatal(1, "corner fifo drain failed head=%0d tail=%0d level=%0d",
             expected_head, expected_tail, level);

    $display("TB_C2_LINE_FIFO_CORNER_PASS words=%0d", expected_head);
    $finish;
  end
endmodule
