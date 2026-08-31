`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// c2_rect_burst_reader
// -----------------------------------------------------------------------------
// Rectangle scan reader for the board-independent memory contract.  The
// planner splits each row into bounded bursts; c2_burst_read_stream converts
// each response burst into a pixel stream.  The module deliberately stops at a
// ready/valid pixel boundary so a later line FIFO or display pipeline can
// determine buffering depth independently of the memory adapter.
// -----------------------------------------------------------------------------
module c2_rect_burst_reader #(
    parameter int ADDR_W          = 32,
    parameter int DATA_W          = 16,
    parameter int MAX_BURST_BEATS = 16,
    parameter bit LIMIT_4KB        = 1'b1
) (
    input  logic                     clk,
    input  logic                     rst_n,
    input  logic                     start,
    output logic                     start_ready,
    input  logic [ADDR_W-1:0]        base_addr,
    input  logic [ADDR_W-1:0]        stride_bytes,
    input  logic [ADDR_W-1:0]        row_bytes,
    input  logic [15:0]              rows,
    output logic                     busy,
    output logic                     done,
    output logic                     error,
    output logic [3:0]               error_code,

    output logic                     mem_req_valid,
    input  logic                     mem_req_ready,
    output logic                     mem_req_write,
    output logic [ADDR_W-1:0]        mem_req_addr,
    output logic [15:0]              mem_req_len,
    output logic [DATA_W-1:0]        mem_req_wdata,
    output logic [(DATA_W/8)-1:0]    mem_req_wstrb,
    input  logic                     mem_rsp_valid,
    output logic                     mem_rsp_ready,
    input  logic [DATA_W-1:0]        mem_rsp_rdata,
    input  logic                     mem_rsp_last,
    input  logic                     mem_rsp_error,

    output logic                     pixel_valid,
    input  logic                     pixel_ready,
    output logic [DATA_W-1:0]        pixel_data,
    output logic [15:0]              pixel_x,
    output logic [15:0]              pixel_y,
    output logic                     pixel_last,
    output logic                     frame_last,

    output logic [31:0]              request_count,
    output logic [31:0]              pixel_count,
    output logic [31:0]              error_count
);

    localparam int BYTE_LANES = DATA_W / 8;

    typedef enum logic [1:0] {ST_IDLE, ST_PLAN, ST_BURST} state_e;
    state_e state;

    logic planner_start;
    logic planner_busy, planner_done, planner_error;
    logic planner_req_valid, planner_req_ready;
    logic [ADDR_W-1:0] planner_req_addr;
    logic [15:0] planner_req_beats;
    logic planner_req_row_last, planner_req_frame_last;

    logic stream_start;
    logic stream_busy, stream_done, stream_error;
    logic stream_req_valid, stream_req_ready, stream_req_write;
    logic [ADDR_W-1:0] stream_req_addr;
    logic [15:0] stream_req_len;
    logic [DATA_W-1:0] stream_req_wdata;
    logic [(DATA_W/8)-1:0] stream_req_wstrb;
    logic stream_rsp_valid, stream_rsp_ready;
    logic [DATA_W-1:0] stream_rsp_rdata;
    logic stream_rsp_last, stream_rsp_error;
    logic stream_out_valid, stream_out_ready, stream_out_last;
    logic [DATA_W-1:0] stream_out_data;
    logic [15:0] stream_out_index;
    logic [31:0] stream_request_count, stream_response_count;
    logic [31:0] stream_error_count;

    logic burst_row_last_q;
    logic burst_frame_last_q;
    logic error_seen_q;
    logic [15:0] x_q, y_q;
    logic pixel_fire;

    assign start_ready = (state == ST_IDLE);
    assign busy        = (state != ST_IDLE);
    assign planner_start = start && start_ready;

    c2_burst_planner #(
        .ADDR_W(ADDR_W),
        .BEAT_BYTES(BYTE_LANES),
        .MAX_BURST_BEATS(MAX_BURST_BEATS),
        .LIMIT_4KB(LIMIT_4KB)
    ) u_planner (
        .clk, .rst_n, .start(planner_start), .base_addr, .stride_bytes,
        .row_bytes, .rows, .busy(planner_busy), .done(planner_done),
        .error(planner_error), .req_valid(planner_req_valid),
        .req_ready(planner_req_ready), .req_addr(planner_req_addr),
        .req_beats(planner_req_beats), .req_row_last(planner_req_row_last),
        .req_frame_last(planner_req_frame_last)
    );

    c2_burst_read_stream #(
        .ADDR_W(ADDR_W), .DATA_W(DATA_W), .LEN_W(16)
    ) u_stream (
        .clk, .rst_n, .start(stream_start), .start_addr(planner_req_addr),
        .start_beats(planner_req_beats), .busy(stream_busy),
        .done(stream_done), .error(stream_error),
        .req_valid(stream_req_valid), .req_ready(stream_req_ready),
        .req_write(stream_req_write), .req_addr(stream_req_addr),
        .req_len(stream_req_len), .req_wdata(stream_req_wdata),
        .req_wstrb(stream_req_wstrb), .rsp_valid(stream_rsp_valid),
        .rsp_ready(stream_rsp_ready), .rsp_rdata(stream_rsp_rdata),
        .rsp_last(stream_rsp_last), .rsp_error(stream_rsp_error),
        .out_valid(stream_out_valid), .out_ready(stream_out_ready),
        .out_data(stream_out_data), .out_last(stream_out_last),
        .out_index(stream_out_index), .request_count(stream_request_count),
        .response_count(stream_response_count), .error_count(stream_error_count)
    );

    // A descriptor is accepted only while the stream is idle.  The same
    // handshake launches the stream and advances the planner, so no descriptor
    // queue is needed at this layer.
    assign planner_req_ready = (state == ST_PLAN) && !stream_busy;
    assign stream_start      = planner_req_valid && planner_req_ready;

    assign mem_req_valid = stream_req_valid;
    assign stream_req_ready = mem_req_ready;
    assign mem_req_write = stream_req_write;
    assign mem_req_addr  = stream_req_addr;
    assign mem_req_len   = stream_req_len;
    assign mem_req_wdata = stream_req_wdata;
    assign mem_req_wstrb = stream_req_wstrb;
    assign stream_rsp_valid = mem_rsp_valid;
    assign mem_rsp_ready = stream_rsp_ready;
    assign stream_rsp_rdata = mem_rsp_rdata;
    assign stream_rsp_last = mem_rsp_last;
    assign stream_rsp_error = mem_rsp_error;

    assign pixel_valid = stream_out_valid;
    assign stream_out_ready = pixel_ready;
    assign pixel_data = stream_out_data;
    assign pixel_x = x_q;
    assign pixel_y = y_q;
    assign pixel_last = stream_out_valid && stream_out_last && burst_row_last_q;
    assign frame_last = stream_out_valid && stream_out_last && burst_frame_last_q;
    assign pixel_fire = stream_out_valid && stream_out_ready;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= ST_IDLE;
            burst_row_last_q <= 1'b0;
            burst_frame_last_q <= 1'b0;
            error_seen_q     <= 1'b0;
            x_q              <= '0;
            y_q              <= '0;
            done             <= 1'b0;
            error            <= 1'b0;
            error_code       <= 4'd0;
            request_count    <= 32'd0;
            pixel_count      <= 32'd0;
            error_count      <= 32'd0;
        end else begin
            done  <= 1'b0;
            error <= 1'b0;

            if (planner_start) begin
                x_q          <= '0;
                y_q          <= '0;
                error_seen_q <= 1'b0;
                error_code   <= 4'd0;
            end

            if (state == ST_IDLE && planner_start)
                state <= ST_PLAN;

            if (state == ST_PLAN) begin
                if (planner_error) begin
                    error        <= 1'b1;
                    done         <= 1'b1;
                    error_code   <= 4'd1;
                    error_count  <= error_count + 32'd1;
                    state        <= ST_IDLE;
                end else if (planner_req_valid && planner_req_ready) begin
                    burst_row_last_q   <= planner_req_row_last;
                    burst_frame_last_q <= planner_req_frame_last;
                    state               <= ST_BURST;
                    request_count       <= request_count + 32'd1;
                end
            end

            if (state == ST_BURST) begin
                if (stream_error) begin
                    error_seen_q <= 1'b1;
                    error_code   <= 4'd2;
                    error_count  <= error_count + 32'd1;
                end
                if (pixel_fire) begin
                    pixel_count <= pixel_count + 32'd1;
                    if (pixel_last) begin
                        x_q <= '0;
                        y_q <= y_q + 1'b1;
                    end else begin
                        x_q <= x_q + 1'b1;
                    end
                end
                if (stream_done) begin
                    if (burst_frame_last_q) begin
                        done  <= 1'b1;
                        error <= error_seen_q || stream_error;
                        state <= ST_IDLE;
                    end else begin
                        state <= ST_PLAN;
                    end
                end
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (ADDR_W <= 0 || DATA_W <= 0 || (DATA_W % 8) != 0 ||
            MAX_BURST_BEATS <= 0)
            $error("c2_rect_burst_reader: invalid parameter");
    end
`endif
endmodule
