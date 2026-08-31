`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// c2_burst_write_stream
// -----------------------------------------------------------------------------
// Issues one write descriptor, then forwards exactly start_beats input samples
// on a separate write-data channel.  This is the minimum contract needed by an
// AXI W channel or another native write adapter; the legacy req_wdata field remains
// zero because it cannot hold a complete burst payload.
// -----------------------------------------------------------------------------
module c2_burst_write_stream #(
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

    input  logic                     in_valid,
    output logic                     in_ready,
    input  logic [DATA_W-1:0]        in_data,
    input  logic [(DATA_W/8)-1:0]    in_strb,
    input  logic                     in_last,

    output logic                     wr_valid,
    input  logic                     wr_ready,
    output logic [DATA_W-1:0]        wr_data,
    output logic [(DATA_W/8)-1:0]    wr_strb,
    output logic                     wr_last,

    output logic [31:0]              request_count,
    output logic [31:0]              beat_count,
    output logic [31:0]              error_count
);

    typedef enum logic [1:0] {ST_IDLE, ST_REQ, ST_DATA} state_e;
    state_e state;

    logic [ADDR_W-1:0] addr_q;
    logic [LEN_W-1:0]  beats_q;
    logic [LEN_W-1:0]  beat_index_q;
    logic              req_fire;
    logic              wr_fire;
    logic              expected_last;
    logic              protocol_error;

    always_comb begin
        busy = (state != ST_IDLE);

        req_valid = (state == ST_REQ);
        req_write = 1'b1;
        req_addr  = addr_q;
        req_len   = beats_q - 1'b1;
        req_wdata = '0;
        req_wstrb = '0;
        req_fire  = req_valid && req_ready;

        in_ready  = (state == ST_DATA) && wr_ready;
        wr_valid  = (state == ST_DATA) && in_valid;
        wr_data   = in_data;
        wr_strb   = in_strb;
        wr_last   = in_last;
        wr_fire   = wr_valid && wr_ready;

        expected_last = (beat_index_q == (beats_q - 1'b1));
        protocol_error = in_last != expected_last;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= ST_IDLE;
            addr_q        <= '0;
            beats_q       <= '0;
            beat_index_q  <= '0;
            done          <= 1'b0;
            error         <= 1'b0;
            request_count <= 32'd0;
            beat_count    <= 32'd0;
            error_count   <= 32'd0;
        end else begin
            done  <= 1'b0;
            error <= 1'b0;

            if (start && (state == ST_IDLE)) begin
                if (start_beats == '0) begin
                    done        <= 1'b1;
                    error       <= 1'b1;
                    error_count <= error_count + 32'd1;
                end else begin
                    addr_q       <= start_addr;
                    beats_q      <= start_beats;
                    beat_index_q <= '0;
                    state         <= ST_REQ;
                end
            end

            if (req_fire) begin
                request_count <= request_count + 32'd1;
                state <= ST_DATA;
            end

            if (wr_fire) begin
                beat_count <= beat_count + 32'd1;
                if (protocol_error) begin
                    error       <= 1'b1;
                    error_count <= error_count + 32'd1;
                end

                // A marker mismatch is terminal for this descriptor.  This
                // avoids waiting forever if an upstream line ends early or
                // forgets to mark the final beat.
                if (in_last || expected_last) begin
                    done  <= 1'b1;
                    state <= ST_IDLE;
                end else begin
                    beat_index_q <= beat_index_q + 1'b1;
                end
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (ADDR_W <= 0 || DATA_W <= 0 || (DATA_W % 8) != 0 || LEN_W <= 0)
            $error("c2_burst_write_stream: invalid interface width");
    end
`endif
endmodule
