`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// render_mem_model
// -----------------------------------------------------------------------------
// A tiny simulation memory for the abstract transaction interface.  It is
// intentionally independent of Xilinx/Efinix primitives and is useful in
// module-level testbenches as a drop-in stand-in for DDR/HyperRAM adapters.
//
// The model accepts one request at a time.  Writes update byte lanes selected
// by `req_wstrb`; reads return one response beat after READ_LATENCY cycles and
// assert `rsp_last`.  `req_len` is checked for documentation only: this first
// version services the first beat and leaves burst coalescing to a later
// adapter.  Out-of-range reads return zero with `rsp_error=1`; out-of-range
// writes are ignored and increment `error_count`.
// -----------------------------------------------------------------------------
module render_mem_model #(
    parameter int ADDR_W = 32,
    parameter int DATA_W = 16,
    parameter int MEM_BYTES = 65536,
    parameter int READ_LATENCY = 1,
    parameter int LAT_W = (READ_LATENCY <= 1) ? 1 : $clog2(READ_LATENCY + 1)
) (
    input  logic                  clk,
    input  logic                  rst_n,

    input  logic                  req_valid,
    output logic                  req_ready,
    input  logic                  req_write,
    input  logic [ADDR_W-1:0]     req_addr,
    input  logic [15:0]           req_len,
    input  logic [DATA_W-1:0]     req_wdata,
    input  logic [(DATA_W/8)-1:0] req_wstrb,

    output logic                  rsp_valid,
    input  logic                  rsp_ready,
    output logic [DATA_W-1:0]     rsp_rdata,
    output logic                  rsp_last,
    output logic                  rsp_error,

    output logic [31:0]           read_count,
    output logic [31:0]           write_count,
    output logic [31:0]           error_count
);

    localparam int BYTE_LANES = DATA_W / 8;
    localparam int MEM_WORDS  = (MEM_BYTES + BYTE_LANES - 1) / BYTE_LANES;

    // Kept public (rather than hidden behind a task) so a testbench can load
    // a known framebuffer with hierarchical assignments if desired.
    logic [DATA_W-1:0] mem [0:MEM_WORDS-1];

    logic [DATA_W-1:0] rsp_data_reg;
    logic              rsp_error_reg;
    logic              rd_pending;
    logic [LAT_W-1:0]  latency_count;
    integer             req_word_index;
    integer             read_word_index;
    integer             lane;
    logic               req_fire;
    logic               rsp_fire;
    logic               read_oob;
    logic               write_oob;

    always_comb begin
        req_word_index = req_addr / BYTE_LANES;
        read_oob       = (req_word_index < 0) || (req_word_index >= MEM_WORDS);
        req_ready      = !rd_pending;
        req_fire       = req_valid && req_ready;

        rsp_valid      = rd_pending && (latency_count == 0);
        rsp_rdata      = rsp_data_reg;
        rsp_last       = rsp_valid;
        rsp_error      = rsp_error_reg;
        rsp_fire       = rsp_valid && rsp_ready;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_pending   <= 1'b0;
            latency_count <= '0;
            rsp_data_reg <= '0;
            rsp_error_reg <= 1'b0;
            read_count   <= 32'd0;
            write_count  <= 32'd0;
            error_count  <= 32'd0;
        end else begin
            if (rsp_fire)
                rd_pending <= 1'b0;

            if (rd_pending && (latency_count != 0))
                latency_count <= latency_count - 1'b1;

            if (req_fire) begin
                if (req_write) begin
                    write_count <= write_count + 32'd1;
                    write_oob = (req_word_index < 0) ||
                                (req_word_index >= MEM_WORDS);
                    if (write_oob) begin
                        error_count <= error_count + 32'd1;
                    end else begin
                        for (lane = 0; lane < BYTE_LANES; lane = lane + 1) begin
                            if (req_wstrb[lane])
                                mem[req_word_index][lane*8 +: 8] <=
                                    req_wdata[lane*8 +: 8];
                        end
                    end
                end else begin
                    read_count      <= read_count + 32'd1;
                    rd_pending      <= 1'b1;
                    latency_count   <= READ_LATENCY[LAT_W-1:0];
                    if (read_oob) begin
                        rsp_data_reg  <= '0;
                        rsp_error_reg <= 1'b1;
                        error_count   <= error_count + 32'd1;
                    end else begin
                        rsp_data_reg  <= mem[req_word_index];
                        rsp_error_reg <= 1'b0;
                    end
                end
            end
        end
    end

endmodule

