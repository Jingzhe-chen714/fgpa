`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// render_burst_mem_model
// -----------------------------------------------------------------------------
// Simulation-only memory for the board-independent transaction contract with
// multi-beat read responses.  req_len is beats-minus-one.  A read request is
// accepted once, then produces one response beat per handshake; rsp_last is
// asserted on the final beat and remains stable while the response is stalled.
//
// The write side intentionally remains a single-beat compatibility path.  The
// production DDR/HyperRAM adapter will eventually add a write-data stream (or
// an AXI W channel); keeping that distinction explicit prevents a packed
// req_wdata field from being mistaken for a complete burst payload.
// -----------------------------------------------------------------------------
module render_burst_mem_model #(
    parameter int ADDR_W       = 32,
    parameter int DATA_W       = 16,
    parameter int LEN_W        = 16,
    parameter int MEM_BYTES    = 65536,
    parameter int READ_LATENCY = 1,
    parameter int LAT_W        = (READ_LATENCY <= 1) ? 1 : $clog2(READ_LATENCY + 1)
) (
    input  logic                     clk,
    input  logic                     rst_n,

    input  logic                     req_valid,
    output logic                     req_ready,
    input  logic                     req_write,
    input  logic [ADDR_W-1:0]        req_addr,
    input  logic [LEN_W-1:0]         req_len,
    input  logic [DATA_W-1:0]        req_wdata,
    input  logic [(DATA_W/8)-1:0]    req_wstrb,

    output logic                     rsp_valid,
    input  logic                     rsp_ready,
    output logic [DATA_W-1:0]        rsp_rdata,
    output logic                     rsp_last,
    output logic                     rsp_error,

    output logic [31:0]              read_count,
    output logic [31:0]              write_count,
    output logic [31:0]              error_count
);

    localparam int BYTE_LANES = DATA_W / 8;
    localparam int MEM_WORDS  = (MEM_BYTES + BYTE_LANES - 1) / BYTE_LANES;

    // Public storage lets a testbench preload a framebuffer or inspect writes.
    logic [DATA_W-1:0] mem [0:MEM_WORDS-1];

    logic                    rd_pending;
    logic [LAT_W-1:0]        latency_count;
    logic [ADDR_W-1:0]       read_addr_q;
    logic [LEN_W:0]          beats_left_q;
    logic [DATA_W-1:0]       rsp_data_reg;
    logic                    rsp_error_reg;

    integer req_word_index;
    integer read_word_index;
    integer next_word_index;
    integer lane;
    logic   req_oob;
    logic   next_oob;
    logic   req_fire;
    logic   rsp_fire;

    always_comb begin
        req_word_index = req_addr / BYTE_LANES;
        read_word_index = read_addr_q / BYTE_LANES;
        next_word_index = (read_addr_q + ADDR_W'(BYTE_LANES)) / BYTE_LANES;

        req_oob  = (req_word_index < 0) || (req_word_index >= MEM_WORDS);
        next_oob = (next_word_index < 0) || (next_word_index >= MEM_WORDS);

        req_ready = !rd_pending;
        req_fire  = req_valid && req_ready;

        rsp_valid = rd_pending && (latency_count == 0);
        rsp_rdata = rsp_data_reg;
        rsp_last  = rsp_valid && (beats_left_q == {{LEN_W{1'b0}}, 1'b1});
        rsp_error = rsp_error_reg;
        rsp_fire  = rsp_valid && rsp_ready;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_pending    <= 1'b0;
            latency_count <= '0;
            read_addr_q   <= '0;
            beats_left_q  <= '0;
            rsp_data_reg  <= '0;
            rsp_error_reg <= 1'b0;
            read_count    <= 32'd0;
            write_count   <= 32'd0;
            error_count   <= 32'd0;
        end else begin
            if (rd_pending && (latency_count != 0))
                latency_count <= latency_count - 1'b1;

            if (req_fire) begin
                if (req_write) begin
                    write_count <= write_count + 32'd1;

                    // This model has no write-data channel, so only len=0 is
                    // meaningful.  Perform the first write for observability,
                    // but flag a longer write as an unsupported contract use.
                    if ((req_len != '0) || req_oob)
                        error_count <= error_count + 32'd1;

                    if (!req_oob) begin
                        for (lane = 0; lane < BYTE_LANES; lane = lane + 1) begin
                            if (req_wstrb[lane])
                                mem[req_word_index][lane*8 +: 8] <=
                                    req_wdata[lane*8 +: 8];
                        end
                    end
                end else begin
                    read_count    <= read_count + 32'd1;
                    rd_pending    <= 1'b1;
                    read_addr_q   <= req_addr;
                    beats_left_q  <= {1'b0, req_len} + 1'b1;
                    latency_count <= READ_LATENCY[LAT_W-1:0];

                    if (req_oob) begin
                        rsp_data_reg  <= '0;
                        rsp_error_reg <= 1'b1;
                        error_count   <= error_count + 32'd1;
                    end else begin
                        rsp_data_reg  <= mem[req_word_index];
                        rsp_error_reg <= 1'b0;
                    end
                end
            end else if (rsp_fire) begin
                if (beats_left_q == {{LEN_W{1'b0}}, 1'b1}) begin
                    rd_pending <= 1'b0;
                    beats_left_q <= '0;
                end else begin
                    read_addr_q  <= read_addr_q + ADDR_W'(BYTE_LANES);
                    beats_left_q <= beats_left_q - 1'b1;
                    if (next_oob) begin
                        rsp_data_reg  <= '0;
                        rsp_error_reg <= 1'b1;
                        error_count   <= error_count + 32'd1;
                    end else begin
                        rsp_data_reg  <= mem[next_word_index];
                        rsp_error_reg <= 1'b0;
                    end
                end
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (ADDR_W <= 0 || DATA_W <= 0 || (DATA_W % 8) != 0 ||
            LEN_W <= 0 || MEM_BYTES <= 0 || READ_LATENCY < 0)
            $error("render_burst_mem_model: invalid parameter");
    end
`endif

endmodule
