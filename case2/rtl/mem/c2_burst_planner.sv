`timescale 1ns/1ps

// Splits one linear rectangle row into aligned bursts. This is deliberately
// independent of AXI/DDR pins; an adapter can translate req_beats to AXI LEN.
// req_beats is the number of data beats (not beats-1).
module c2_burst_planner #(
  parameter int ADDR_W         = 32,
  parameter int BEAT_BYTES     = 2,
  parameter int MAX_BURST_BEATS = 16,
  parameter bit LIMIT_4KB      = 1'b1
) (
  input  logic                   clk,
  input  logic                   rst_n,
  input  logic                   start,
  input  logic [ADDR_W-1:0]      base_addr,
  input  logic [ADDR_W-1:0]      stride_bytes,
  input  logic [ADDR_W-1:0]      row_bytes,
  input  logic [15:0]            rows,
  output logic                   busy,
  output logic                   done,
  output logic                   error,
  output logic                   req_valid,
  input  logic                   req_ready,
  output logic [ADDR_W-1:0]      req_addr,
  output logic [15:0]            req_beats,
  output logic                   req_row_last,
  output logic                   req_frame_last
);
  localparam int MAX_BURST_BYTES = BEAT_BYTES * MAX_BURST_BEATS;
  localparam logic [ADDR_W-1:0] BEAT_MASK = BEAT_BYTES - 1;

  logic [ADDR_W-1:0] cur_addr;
  logic [ADDR_W-1:0] row_base;
  logic [ADDR_W-1:0] row_rem;
  logic [ADDR_W-1:0] stride_q;
  logic [ADDR_W-1:0] row_bytes_q;
  logic [15:0]       rows_left;
  logic              active;

  logic [ADDR_W-1:0] boundary_bytes;
  logic [ADDR_W-1:0] burst_bytes;
  logic [ADDR_W-1:0] burst_bytes_aligned;
  logic [15:0]       burst_beats;

  assign busy = active;
  assign req_addr = cur_addr;
  assign req_valid = active && (row_rem != 0) && (burst_beats != 0);
  assign req_beats = burst_beats;
  assign req_row_last = req_valid && (burst_bytes_aligned == row_rem);
  assign req_frame_last = req_row_last && (rows_left == 16'd1);

  always_comb begin
    if (LIMIT_4KB) begin
      if (cur_addr[11:0] == 12'd0)
        boundary_bytes = ADDR_W'(4096);
      else
        boundary_bytes = ADDR_W'(4096 - cur_addr[11:0]);
    end else begin
      boundary_bytes = {ADDR_W{1'b1}};
    end

    burst_bytes = row_rem;
    if (burst_bytes > ADDR_W'(MAX_BURST_BYTES))
      burst_bytes = ADDR_W'(MAX_BURST_BYTES);
    if (burst_bytes > boundary_bytes)
      burst_bytes = boundary_bytes;

    // Inputs are required to be beat aligned. This mask operation avoids a
    // variable divider in the generated RTL.
    burst_bytes_aligned = burst_bytes & ~BEAT_MASK;
    burst_beats = 16'(burst_bytes_aligned / BEAT_BYTES);
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cur_addr   <= '0;
      row_base   <= '0;
      row_rem    <= '0;
      stride_q   <= '0;
      row_bytes_q <= '0;
      rows_left  <= '0;
      active     <= 1'b0;
      done       <= 1'b0;
      error      <= 1'b0;
    end else begin
      done  <= 1'b0;
      error <= 1'b0;

      if (start && !active) begin
        if ((rows == 0) || (row_bytes == 0) ||
            ((base_addr & BEAT_MASK) != 0) ||
            ((stride_bytes & BEAT_MASK) != 0) ||
            ((row_bytes & BEAT_MASK) != 0)) begin
          error <= 1'b1;
          done  <= 1'b1;
        end else begin
          cur_addr    <= base_addr;
          row_base    <= base_addr;
          row_rem     <= row_bytes;
          stride_q    <= stride_bytes;
          row_bytes_q <= row_bytes;
          rows_left   <= rows;
          active      <= 1'b1;
        end
      end

      if (req_valid && req_ready) begin
        if (req_row_last) begin
          if (rows_left == 16'd1) begin
            active    <= 1'b0;
            rows_left <= '0;
            row_rem   <= '0;
            done      <= 1'b1;
          end else begin
            row_base  <= row_base + stride_q;
            cur_addr  <= row_base + stride_q;
            row_rem   <= row_bytes_q;
            rows_left <= rows_left - 1'b1;
          end
        end else begin
          cur_addr <= cur_addr + burst_bytes_aligned;
          row_rem  <= row_rem - burst_bytes_aligned;
        end
      end
    end
  end
endmodule
