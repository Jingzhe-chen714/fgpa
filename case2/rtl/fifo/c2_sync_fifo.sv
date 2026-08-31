`timescale 1ns/1ps

// Vendor-neutral synchronous ready/valid FIFO.
// The FIFO permits a push and pop in the same cycle, including when full.
module c2_sync_fifo #(
  parameter int DATA_W = 32,
  parameter int DEPTH  = 16
) (
  input  logic                   clk,
  input  logic                   rst_n,
  input  logic                   s_valid,
  output logic                   s_ready,
  input  logic [DATA_W-1:0]      s_data,
  output logic                   m_valid,
  input  logic                   m_ready,
  output logic [DATA_W-1:0]      m_data,
  output logic [$clog2(DEPTH+1)-1:0] count,
  output logic                   full,
  output logic                   empty,
  output logic                   overflow,
  output logic                   underflow
);
  localparam int PTR_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH);
  localparam int CNT_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH+1);

  logic [DATA_W-1:0] mem [0:DEPTH-1];
  logic [PTR_W-1:0]  wr_ptr;
  logic [PTR_W-1:0]  rd_ptr;
  logic [CNT_W-1:0]  count_i;
  logic              push;
  logic              pop;

  assign count = count_i;
  assign empty = (count_i == 0);
  assign full  = (count_i == DEPTH);
  // A simultaneous pop frees a slot, so a full FIFO can still accept one word.
  assign s_ready = !full || (m_valid && m_ready);
  assign m_valid = !empty;
  assign m_data  = mem[rd_ptr];
  assign push = s_valid && s_ready;
  assign pop  = m_valid && m_ready;

  function automatic logic [PTR_W-1:0] ptr_inc(input logic [PTR_W-1:0] ptr);
    if (ptr == PTR_W'(DEPTH-1))
      ptr_inc = '0;
    else
      ptr_inc = ptr + 1'b1;
  endfunction

  // Use the same asynchronous active-low reset convention as the command,
  // memory and video blocks.  This keeps the primitive safe to instantiate
  // before a system-level reset synchronizer is chosen.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_ptr    <= '0;
      rd_ptr    <= '0;
      count_i   <= '0;
      overflow  <= 1'b0;
      underflow <= 1'b0;
    end else begin
      overflow  <= s_valid && !s_ready;
      underflow <= m_ready && !m_valid;

      if (push) begin
        mem[wr_ptr] <= s_data;
        wr_ptr <= ptr_inc(wr_ptr);
      end
      if (pop)
        rd_ptr <= ptr_inc(rd_ptr);

      case ({push, pop})
        2'b10: count_i <= count_i + 1'b1;
        2'b01: count_i <= count_i - 1'b1;
        default: count_i <= count_i;
      endcase
    end
  end
endmodule
