`timescale 1ns/1ps

// Pixel line FIFO carrying an end-of-line marker alongside each sample.  The
// implementation is vendor-neutral and uses a registered first-word output so
// the storage read is synchronous and can infer FPGA block RAM.  The output
// register is included in `level`; flush is synchronous and discards all data.
module c2_line_fifo #(
  parameter int DATA_W = 16,
  parameter int DEPTH  = 1024
) (
  input  logic                         clk,
  input  logic                         rst_n,
  input  logic                         flush,
  input  logic                         in_valid,
  output logic                         in_ready,
  input  logic [DATA_W-1:0]             in_data,
  input  logic                         in_last,
  output logic                         out_valid,
  input  logic                         out_ready,
  output logic [DATA_W-1:0]             out_data,
  output logic                         out_last,
  output logic [$clog2(DEPTH+1)-1:0]   level,
  output logic                         full,
  output logic                         empty,
  output logic                         overflow,
  output logic                         underflow
);
  localparam int PTR_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH);
  localparam int CNT_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH+1);

  // The attribute is understood by Vivado and harmless to tools that ignore
  // it; the reset-free synchronous access pattern remains the portable part.
  (* ram_style = "block" *) logic [DATA_W:0] mem [0:DEPTH-1];
  logic [PTR_W-1:0] wr_ptr;
  logic [PTR_W-1:0] rd_ptr;
  logic [CNT_W-1:0] count_i;
  logic [DATA_W:0] out_q;
  logic out_valid_q;
  logic push, pop;
  logic front_load;
  logic [CNT_W-1:0] queued_count;

  assign level    = count_i;
  assign empty    = (count_i == 0);
  assign full     = (count_i == DEPTH);
  assign out_valid = out_valid_q;
  assign out_data  = out_q[DATA_W-1:0];
  assign out_last  = out_q[DATA_W];
  assign in_ready  = !full || (out_valid && out_ready);
  assign push      = in_valid && in_ready;
  assign pop       = out_valid && out_ready;
  // count_i includes the registered output word. Everything behind that word
  // is still resident in RAM and can be synchronously prefetched whenever the
  // output is empty or is being consumed on this clock.
  assign queued_count = count_i - CNT_W'(out_valid_q);
  assign front_load = (queued_count != 0) && (!out_valid_q || pop);

  function automatic logic [PTR_W-1:0] ptr_inc(input logic [PTR_W-1:0] ptr);
    if (ptr == PTR_W'(DEPTH-1))
      ptr_inc = '0;
    else
      ptr_inc = ptr + 1'b1;
  endfunction

  // Canonical simple-dual-port synchronous RAM. Every input word is first
  // enqueued in RAM; front_load copies the oldest queued word into out_q. RAM
  // and out_q intentionally have no reset because out_valid_q is the validity
  // guard. This adds one harmless prefetch cycle when an empty FIFO receives
  // its first word, while permitting a block-RAM implementation.
  always_ff @(posedge clk) begin
    if (rst_n && !flush) begin
      if (push)
        mem[wr_ptr] <= {in_last, in_data};
      if (front_load)
        out_q <= mem[rd_ptr];
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_ptr    <= '0;
      rd_ptr    <= '0;
      count_i   <= '0;
      out_valid_q <= 1'b0;
      overflow  <= 1'b0;
      underflow <= 1'b0;
    end else if (flush) begin
      wr_ptr    <= '0;
      rd_ptr    <= '0;
      count_i   <= '0;
      out_valid_q <= 1'b0;
      overflow  <= 1'b0;
      underflow <= 1'b0;
    end else begin
      overflow  <= in_valid && !in_ready;
      underflow <= out_ready && !out_valid;

      if (push)
        wr_ptr <= ptr_inc(wr_ptr);
      if (front_load)
        rd_ptr <= ptr_inc(rd_ptr);

      if (front_load)
        out_valid_q <= 1'b1;
      else if (pop)
        out_valid_q <= 1'b0;

      case ({push, pop})
        2'b10: count_i <= count_i + 1'b1;
        2'b01: count_i <= count_i - 1'b1;
        default: count_i <= count_i;
      endcase
    end
  end

`ifndef SYNTHESIS
  initial begin
    if (DATA_W <= 0 || DEPTH <= 0)
      $error("c2_line_fifo: invalid parameter");
  end
`endif
endmodule
