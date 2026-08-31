`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// c2_mem_arbiter_2m
// -----------------------------------------------------------------------------
// Two-client arbiter for the board-independent memory transaction contract.
// Client 0 is normally the render command engine (read/write traffic); client
// 1 is normally the display/framebuffer reader (read-only traffic).  There is
// no transaction ID in the baseline interface, so the arbiter allows one
// outstanding read and remembers its owner until the complete response burst
// is consumed.
// Writes complete when the downstream request is accepted and do not expect a
// response beat.  For a read burst, the owner is held until s_rsp_last is
// accepted; response_count therefore counts beats rather than transactions.
//
// When both clients request simultaneously, `display_priority=1` selects
// client 1.  Otherwise a one-bit round-robin pointer prevents starvation.  A
// future AXI/DDR adapter can sit behind this module without exposing its
// arbitration or ID details to either functional block.
// -----------------------------------------------------------------------------
module c2_mem_arbiter_2m #(
    parameter int ADDR_W = 32,
    parameter int DATA_W = 16,
    parameter int LEN_W  = 16
) (
    input  logic                     clk,
    input  logic                     rst_n,
    input  logic                     display_priority,

    input  logic                     m0_req_valid,
    output logic                     m0_req_ready,
    input  logic                     m0_req_write,
    input  logic [ADDR_W-1:0]        m0_req_addr,
    input  logic [LEN_W-1:0]         m0_req_len,
    input  logic [DATA_W-1:0]        m0_req_wdata,
    input  logic [(DATA_W/8)-1:0]    m0_req_wstrb,
    output logic                     m0_rsp_valid,
    input  logic                     m0_rsp_ready,
    output logic [DATA_W-1:0]        m0_rsp_rdata,
    output logic                     m0_rsp_last,
    output logic                     m0_rsp_error,

    input  logic                     m1_req_valid,
    output logic                     m1_req_ready,
    input  logic                     m1_req_write,
    input  logic [ADDR_W-1:0]        m1_req_addr,
    input  logic [LEN_W-1:0]         m1_req_len,
    input  logic [DATA_W-1:0]        m1_req_wdata,
    input  logic [(DATA_W/8)-1:0]    m1_req_wstrb,
    output logic                     m1_rsp_valid,
    input  logic                     m1_rsp_ready,
    output logic [DATA_W-1:0]        m1_rsp_rdata,
    output logic                     m1_rsp_last,
    output logic                     m1_rsp_error,

    output logic                     s_req_valid,
    input  logic                     s_req_ready,
    output logic                     s_req_write,
    output logic [ADDR_W-1:0]        s_req_addr,
    output logic [LEN_W-1:0]         s_req_len,
    output logic [DATA_W-1:0]        s_req_wdata,
    output logic [(DATA_W/8)-1:0]    s_req_wstrb,
    input  logic                     s_rsp_valid,
    output logic                     s_rsp_ready,
    input  logic [DATA_W-1:0]        s_rsp_rdata,
    input  logic                     s_rsp_last,
    input  logic                     s_rsp_error,

    output logic                     busy,
    output logic                     owner_m1,
    output logic [31:0]              grant_count,
    output logic [31:0]              read_count,
    output logic [31:0]              write_count,
    output logic [31:0]              response_count,
    output logic [31:0]              orphan_response_count
);

    typedef enum logic [1:0] {
        ST_IDLE,
        ST_WAIT_M0,
        ST_WAIT_M1
    } state_e;

    state_e state;
    logic rr_m1_q;
    logic grant_m1;
    logic grant_valid;
    logic req_fire;
    logic rsp_fire;

    always_comb begin
        grant_m1 = 1'b0;
        grant_valid = 1'b0;
        if (state == ST_IDLE) begin
            if (m0_req_valid && m1_req_valid) begin
                grant_m1 = display_priority ? 1'b1 : rr_m1_q;
                grant_valid = 1'b1;
            end else if (m1_req_valid) begin
                grant_m1 = 1'b1;
                grant_valid = 1'b1;
            end else if (m0_req_valid) begin
                grant_m1 = 1'b0;
                grant_valid = 1'b1;
            end
        end

        m0_req_ready = 1'b0;
        m1_req_ready = 1'b0;
        s_req_valid  = 1'b0;
        s_req_write  = 1'b0;
        s_req_addr   = '0;
        s_req_len    = '0;
        s_req_wdata  = '0;
        s_req_wstrb  = '0;

        if (grant_valid) begin
            s_req_valid = 1'b1;
            if (grant_m1) begin
                s_req_write = m1_req_write;
                s_req_addr  = m1_req_addr;
                s_req_len   = m1_req_len;
                s_req_wdata = m1_req_wdata;
                s_req_wstrb = m1_req_wstrb;
                m1_req_ready = s_req_ready;
            end else begin
                s_req_write = m0_req_write;
                s_req_addr  = m0_req_addr;
                s_req_len   = m0_req_len;
                s_req_wdata = m0_req_wdata;
                s_req_wstrb = m0_req_wstrb;
                m0_req_ready = s_req_ready;
            end
        end
        req_fire = s_req_valid && s_req_ready;

        m0_rsp_valid = (state == ST_WAIT_M0) && s_rsp_valid;
        m1_rsp_valid = (state == ST_WAIT_M1) && s_rsp_valid;
        m0_rsp_rdata = s_rsp_rdata;
        m1_rsp_rdata = s_rsp_rdata;
        m0_rsp_last  = s_rsp_last;
        m1_rsp_last  = s_rsp_last;
        m0_rsp_error = s_rsp_error;
        m1_rsp_error = s_rsp_error;

        s_rsp_ready = 1'b0;
        if (state == ST_WAIT_M0)
            s_rsp_ready = m0_rsp_ready;
        else if (state == ST_WAIT_M1)
            s_rsp_ready = m1_rsp_ready;
        rsp_fire = s_rsp_valid && s_rsp_ready;

        busy = (state != ST_IDLE);
        owner_m1 = (state == ST_WAIT_M1);
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state                  <= ST_IDLE;
            rr_m1_q                <= 1'b0;
            grant_count            <= 32'd0;
            read_count             <= 32'd0;
            write_count            <= 32'd0;
            response_count         <= 32'd0;
            orphan_response_count  <= 32'd0;
        end else begin
            if (s_rsp_valid && (state == ST_IDLE))
                orphan_response_count <= orphan_response_count + 32'd1;

            if (req_fire) begin
                grant_count <= grant_count + 32'd1;
                rr_m1_q <= ~grant_m1;
                if (grant_m1 ? m1_req_write : m0_req_write) begin
                    write_count <= write_count + 32'd1;
                    state <= ST_IDLE;
                end else begin
                    read_count <= read_count + 32'd1;
                    state <= grant_m1 ? ST_WAIT_M1 : ST_WAIT_M0;
                end
            end else if (rsp_fire) begin
                response_count <= response_count + 32'd1;
                // A burst response can contain several beats.  Keep routing
                // every beat to the same master until the downstream adapter
                // marks the final one.  The baseline single-beat contract has
                // rsp_last=1, so this preserves its behavior unchanged.
                if (s_rsp_last) begin
                    rr_m1_q <= (state == ST_WAIT_M0);
                    state <= ST_IDLE;
                end
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (ADDR_W <= 0 || DATA_W <= 0 || (DATA_W % 8) != 0 || LEN_W <= 0)
            $error("c2_mem_arbiter_2m: invalid interface width");
    end
`endif

endmodule
