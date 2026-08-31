`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// c2_burst_read_stream
// -----------------------------------------------------------------------------
// Issues one read burst and converts its multi-beat response into a normal
// ready/valid data stream.  There is one response holding register, so the
// downstream line FIFO may apply arbitrary backpressure without losing a beat.
// The memory contract uses req_len=beats-1 and requires rsp_last on the final
// response beat.  A malformed early/missing last is reported and terminates the
// stream rather than hanging the controller indefinitely.
// -----------------------------------------------------------------------------
module c2_burst_read_stream #(
    parameter int ADDR_W = 32,
    parameter int DATA_W = 16,
    parameter int LEN_W  = 16
) (
    input  logic                     clk,
    input  logic                     rst_n,
    input  logic                     start,
    input  logic [ADDR_W-1:0]        start_addr,
    input  logic [LEN_W-1:0]         start_beats,
    output logic                     busy,
    output logic                     done,
    output logic                     error,

    output logic                     req_valid,
    input  logic                     req_ready,
    output logic                     req_write,
    output logic [ADDR_W-1:0]        req_addr,
    output logic [LEN_W-1:0]         req_len,
    output logic [DATA_W-1:0]        req_wdata,
    output logic [(DATA_W/8)-1:0]    req_wstrb,

    input  logic                     rsp_valid,
    output logic                     rsp_ready,
    input  logic [DATA_W-1:0]        rsp_rdata,
    input  logic                     rsp_last,
    input  logic                     rsp_error,

    output logic                     out_valid,
    input  logic                     out_ready,
    output logic [DATA_W-1:0]        out_data,
    output logic                     out_last,
    output logic [LEN_W-1:0]         out_index,

    output logic [31:0]              request_count,
    output logic [31:0]              response_count,
    output logic [31:0]              error_count
);

    typedef enum logic [1:0] {ST_IDLE, ST_REQ, ST_WAIT_RSP, ST_OUT} state_e;
    state_e state;

    logic [ADDR_W-1:0] start_addr_q;
    logic [LEN_W-1:0]  beats_q;
    logic [LEN_W-1:0]  beat_index_q;
    logic [DATA_W-1:0] out_data_q;
    logic              out_last_q;
    logic              out_error_q;
    logic              req_fire;
    logic              rsp_fire;
    logic              out_fire;
    logic              expected_last;
    logic              protocol_error;

    always_comb begin
        busy = (state != ST_IDLE);

        req_valid = (state == ST_REQ);
        req_write = 1'b0;
        req_addr  = start_addr_q;
        req_len   = beats_q - 1'b1;
        req_wdata = '0;
        req_wstrb = '0;
        req_fire  = req_valid && req_ready;

        rsp_ready = (state == ST_WAIT_RSP);
        rsp_fire  = rsp_valid && rsp_ready;

        out_valid = (state == ST_OUT);
        out_data  = out_data_q;
        out_last  = out_last_q;
        out_index = beat_index_q;
        out_fire  = out_valid && out_ready;

        expected_last = (beat_index_q == (beats_q - 1'b1));
        protocol_error = rsp_error || (rsp_last != expected_last);
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= ST_IDLE;
            start_addr_q   <= '0;
            beats_q        <= '0;
            beat_index_q   <= '0;
            out_data_q     <= '0;
            out_last_q     <= 1'b0;
            out_error_q    <= 1'b0;
            done           <= 1'b0;
            error          <= 1'b0;
            request_count  <= 32'd0;
            response_count <= 32'd0;
            error_count    <= 32'd0;
        end else begin
            done  <= 1'b0;
            error <= 1'b0;

            if (start && (state == ST_IDLE)) begin
                if (start_beats == '0) begin
                    done        <= 1'b1;
                    error       <= 1'b1;
                    error_count <= error_count + 32'd1;
                end else begin
                    start_addr_q <= start_addr;
                    beats_q      <= start_beats;
                    beat_index_q <= '0;
                    state        <= ST_REQ;
                end
            end

            if (req_fire) begin
                request_count <= request_count + 32'd1;
                state <= ST_WAIT_RSP;
            end

            if (rsp_fire) begin
                response_count <= response_count + 32'd1;
                out_data_q  <= rsp_rdata;
                // If the memory terminates early or omits last on the expected
                // final beat, force a finite stream and flag the transaction.
                out_last_q  <= rsp_last || expected_last;
                out_error_q <= protocol_error;
                if (protocol_error) begin
                    error       <= 1'b1;
                    error_count <= error_count + 32'd1;
                end
                state <= ST_OUT;
            end

            if (out_fire) begin
                if (out_error_q)
                    error <= 1'b1;
                if (out_last_q) begin
                    done  <= 1'b1;
                    state <= ST_IDLE;
                end else begin
                    beat_index_q <= beat_index_q + 1'b1;
                    state <= ST_WAIT_RSP;
                end
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (ADDR_W <= 0 || DATA_W <= 0 || (DATA_W % 8) != 0 || LEN_W <= 0)
            $error("c2_burst_read_stream: invalid interface width");
    end
`endif

endmodule
