`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// render_owner_mem_model
// -----------------------------------------------------------------------------
// Simulation memory for the owner-aware transaction contract.  A descriptor
// is accepted on req_*, then a write descriptor is followed by a separate
// wr_* stream.  Read descriptors return a burst on rsp_*.  The model is
// deliberately single-transaction, matching c2_mem_arbiter_2m_owner and the
// no-ID external-memory boundary used by Case 2.
//
// req_len is beats-minus-one.  For writes, wr_last must be asserted on the
// advertised final beat; a missing/early marker terminates the transaction and
// increments error_count so a testbench cannot hang forever on malformed data.
// -----------------------------------------------------------------------------
module render_owner_mem_model #(
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

    input  logic                     wr_valid,
    output logic                     wr_ready,
    input  logic [DATA_W-1:0]        wr_data,
    input  logic [(DATA_W/8)-1:0]    wr_strb,
    input  logic                     wr_last,
    output logic                     wr_error,

    output logic                     wr_rsp_valid,
    input  logic                     wr_rsp_ready,
    output logic                     wr_rsp_error,

    output logic                     rsp_valid,
    input  logic                     rsp_ready,
    output logic [DATA_W-1:0]        rsp_rdata,
    output logic                     rsp_last,
    output logic                     rsp_error,

    output logic [31:0]              descriptor_count,
    output logic [31:0]              read_count,
    output logic [31:0]              write_count,
    output logic [31:0]              write_beat_count,
    output logic [31:0]              write_response_count,
    output logic [31:0]              response_count,
    output logic [31:0]              error_count
);

    localparam int BYTE_LANES = DATA_W / 8;
    localparam int MEM_WORDS  = (MEM_BYTES + BYTE_LANES - 1) / BYTE_LANES;

    // Public storage is intentional: tests preload source/framebuffer pixels
    // and inspect the row burst writes after completion.
    logic [DATA_W-1:0] mem [0:MEM_WORDS-1];

    typedef enum logic [1:0] {
        ST_IDLE,
        ST_READ,
        ST_WRITE,
        ST_WRITE_RSP
    } state_e;
    state_e state_q;
    logic [ADDR_W-1:0] addr_q;
    logic [LEN_W:0] beats_left_q;
    logic [LAT_W-1:0] latency_count_q;
    logic [DATA_W-1:0] rsp_data_q;
    logic rsp_error_q;
    logic wr_rsp_error_q;
    logic req_fire, wr_fire, wr_rsp_fire, rsp_fire;
    integer req_word_index;
    integer word_index;
    integer next_word_index;
    integer lane;
    logic req_oob, write_oob, next_oob;
    logic expected_last;

    always_comb begin
        req_word_index = req_addr / BYTE_LANES;
        word_index = addr_q / BYTE_LANES;
        next_word_index = (addr_q + ADDR_W'(BYTE_LANES)) / BYTE_LANES;
        req_oob = (req_word_index < 0) || (req_word_index >= MEM_WORDS);
        write_oob = (word_index < 0) || (word_index >= MEM_WORDS);
        next_oob = (next_word_index < 0) || (next_word_index >= MEM_WORDS);

        req_ready = (state_q == ST_IDLE);
        req_fire = req_valid && req_ready;
        wr_ready = (state_q == ST_WRITE) && (beats_left_q != 0);
        wr_fire = wr_valid && wr_ready;
        expected_last = (beats_left_q == {{LEN_W{1'b0}}, 1'b1});

        rsp_valid = (state_q == ST_READ) && (latency_count_q == 0);
        rsp_rdata = rsp_data_q;
        rsp_last = rsp_valid && expected_last;
        rsp_error = rsp_error_q;
        rsp_fire = rsp_valid && rsp_ready;

        // Error is a beat-qualified pulse.  The arbiter/engine can sample it
        // on the same write-data handshake that terminates the descriptor.
        wr_error = wr_fire && ((wr_last != expected_last) || write_oob);

        wr_rsp_valid = (state_q == ST_WRITE_RSP);
        wr_rsp_error = wr_rsp_error_q;
        wr_rsp_fire = wr_rsp_valid && wr_rsp_ready;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q          <= ST_IDLE;
            addr_q           <= '0;
            beats_left_q     <= '0;
            latency_count_q  <= '0;
            rsp_data_q       <= '0;
            rsp_error_q      <= 1'b0;
            wr_rsp_error_q   <= 1'b0;
            descriptor_count <= 32'd0;
            read_count       <= 32'd0;
            write_count      <= 32'd0;
            write_beat_count <= 32'd0;
            write_response_count <= 32'd0;
            response_count   <= 32'd0;
            error_count      <= 32'd0;
        end else begin
            if ((state_q == ST_READ) && (latency_count_q != 0))
                latency_count_q <= latency_count_q - 1'b1;

            if (req_fire) begin
                descriptor_count <= descriptor_count + 32'd1;
                addr_q <= req_addr;
                beats_left_q <= {1'b0, req_len} + 1'b1;
                if (req_write) begin
                    write_count <= write_count + 32'd1;
                    wr_rsp_error_q <= 1'b0;
                    state_q <= ST_WRITE;
                end else begin
                    read_count <= read_count + 32'd1;
                    latency_count_q <= READ_LATENCY[LAT_W-1:0];
                    if (req_oob) begin
                        rsp_data_q  <= '0;
                        rsp_error_q <= 1'b1;
                        error_count <= error_count + 32'd1;
                    end else begin
                        rsp_data_q  <= mem[req_word_index];
                        rsp_error_q <= 1'b0;
                    end
                    state_q <= ST_READ;
                end
            end else if (wr_fire) begin
                write_beat_count <= write_beat_count + 32'd1;
                if ((wr_last != expected_last) || write_oob)
                    error_count <= error_count + 32'd1;

                if (!write_oob) begin
                    for (lane = 0; lane < BYTE_LANES; lane = lane + 1)
                        if (wr_strb[lane])
                            mem[word_index][lane*8 +: 8] <= wr_data[lane*8 +: 8];
                end

                // Every accepted write descriptor produces exactly one later
                // completion response, including malformed-last and OOB
                // cases.  This is the abstract equivalent of AXI B.
                if (wr_last || expected_last || write_oob) begin
                    state_q <= ST_WRITE_RSP;
                    beats_left_q <= '0;
                    wr_rsp_error_q <= (wr_last != expected_last) || write_oob;
                end else begin
                    addr_q <= addr_q + ADDR_W'(BYTE_LANES);
                    beats_left_q <= beats_left_q - 1'b1;
                end
            end else if (wr_rsp_fire) begin
                write_response_count <= write_response_count + 32'd1;
                state_q <= ST_IDLE;
                wr_rsp_error_q <= 1'b0;
            end else if (rsp_fire) begin
                response_count <= response_count + 32'd1;
                // A read error is likewise a terminal response.  This mirrors
                // c2_mem_arbiter_2m_owner and permits a later descriptor to
                // make progress after an out-of-range burst access.
                if (expected_last || rsp_error_q) begin
                    state_q <= ST_IDLE;
                    beats_left_q <= '0;
                end else begin
                    addr_q <= addr_q + ADDR_W'(BYTE_LANES);
                    beats_left_q <= beats_left_q - 1'b1;
                    if (next_oob) begin
                        rsp_data_q  <= '0;
                        rsp_error_q <= 1'b1;
                        error_count <= error_count + 32'd1;
                    end else begin
                        rsp_data_q  <= mem[next_word_index];
                        rsp_error_q <= 1'b0;
                    end
                end
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (ADDR_W <= 0 || DATA_W <= 0 || (DATA_W % 8) != 0 || LEN_W <= 0 ||
            MEM_BYTES <= 0 || READ_LATENCY < 0)
            $error("render_owner_mem_model: invalid parameter");
    end
`endif
endmodule
