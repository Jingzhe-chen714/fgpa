`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// render_cmd_fifo
// -----------------------------------------------------------------------------
// A small, synchronous ready/valid FIFO for the 256-bit render command stream.
// The implementation deliberately uses only synthesizable SystemVerilog; an
// implementation may therefore be mapped to LUT RAM, block RAM, or an ASIC
// SRAM by the integrator without changing the interface.
//
// * `in_valid && in_ready` is the only condition which pushes a command.
// * `out_valid && out_ready` is the only condition which pops a command.
// * A full FIFO may accept a push in the same cycle as a pop (no bubble).
// * `out_data` is held while `out_valid && !out_ready` (rd_ptr does not move).
// * `drop_event` is a one-cycle indication for a producer that attempted to
//   push while the FIFO was full.  `drop_count` is a monotonically wrapping
//   diagnostic counter; no command is overwritten.
//
// Reset is active-low asynchronous, matching the other case2 building blocks.
// -----------------------------------------------------------------------------
module render_cmd_fifo #(
    parameter int CMD_W = 256,
    parameter int DEPTH = 8,
    parameter int PTR_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH),
    parameter int CNT_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH + 1)
) (
    input  logic                 clk,
    input  logic                 rst_n,

    input  logic                 in_valid,
    output logic                 in_ready,
    input  logic [CMD_W-1:0]     in_data,

    output logic                 out_valid,
    input  logic                 out_ready,
    output logic [CMD_W-1:0]     out_data,

    output logic [CNT_W-1:0]     fifo_count,
    output logic                 full,
    output logic                 empty,
    output logic                 drop_event,
    output logic [31:0]          push_count,
    output logic [31:0]          pop_count,
    output logic [31:0]          drop_count
);

    logic [CMD_W-1:0] mem [0:DEPTH-1];
    logic [PTR_W-1:0] wr_ptr;
    logic [PTR_W-1:0] rd_ptr;
    logic [CNT_W-1:0] count;

    logic push;
    logic pop;

    always_comb begin
        empty      = (count == 0);
        full       = (count == DEPTH);
        out_valid  = !empty;
        // A simultaneous pop frees one slot, so a full FIFO can still accept
        // a command without inserting a throughput bubble.
        in_ready   = !full || (out_ready && out_valid);
        out_data   = mem[rd_ptr];
        fifo_count = count;
    end

    always_comb begin
        push = in_valid && in_ready;
        pop  = out_valid && out_ready;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr     <= '0;
            rd_ptr     <= '0;
            count      <= '0;
            drop_event <= 1'b0;
            push_count <= 32'd0;
            pop_count  <= 32'd0;
            drop_count <= 32'd0;
        end else begin
            // Event pulses are cleared every cycle and asserted only for the
            // failed handshake in this cycle.
            drop_event <= in_valid && !in_ready;

            if (in_valid && !in_ready)
                drop_count <= drop_count + 32'd1;
            if (push)
                push_count <= push_count + 32'd1;
            if (pop)
                pop_count <= pop_count + 32'd1;

            if (push) begin
                mem[wr_ptr] <= in_data;
                if (wr_ptr == DEPTH-1)
                    wr_ptr <= '0;
                else
                    wr_ptr <= wr_ptr + 1'b1;
            end

            if (pop) begin
                if (rd_ptr == DEPTH-1)
                    rd_ptr <= '0;
                else
                    rd_ptr <= rd_ptr + 1'b1;
            end

            case ({push, pop})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end

endmodule

