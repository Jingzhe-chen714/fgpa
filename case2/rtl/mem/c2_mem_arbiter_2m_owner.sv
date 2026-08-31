`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// c2_mem_arbiter_2m_owner
// -----------------------------------------------------------------------------
// Two-master memory arbiter with an explicit write-data channel.
//
// The original c2_mem_arbiter_2m contract carries one write word in the
// request descriptor.  That is sufficient for a single-beat write, but it
// cannot represent an AXI/DDR burst: the remaining write words have to arrive
// on a separate valid/ready channel.  This module keeps the original abstract
// request/response fields and adds one write-data stream per master and one
// shared write-data stream downstream.
//
// Transaction ownership rules:
//   * A descriptor is arbitrated only in ST_IDLE.
//   * A read descriptor owns the downstream response channel until the
//     accepted response with rsp_last=1.
//   * A write descriptor owns the downstream write-data and write-response
//     channels from descriptor acceptance through the accepted wr_rsp beat.
//     The requested length is tracked as a safety boundary; if the producer
//     omits last on the expected final beat (or asserts it early), the data
//     phase terminates and write_protocol_error pulses, but owner release still
//     waits for the controller's completion response.
//   * No write data is accepted before its descriptor has been accepted.  This
//     deliberate one-cycle separation makes the owner unambiguous and maps
//     cleanly to AXI AW/W or another command/data adapter.
//
// There are no transaction IDs.  A selected read response (including every
// beat and its last marker) is routed only to the selected master.  Requests
// from the other master remain back-pressured while an owner is active.
// -----------------------------------------------------------------------------
module c2_mem_arbiter_2m_owner #(
    parameter int ADDR_W = 32,
    parameter int DATA_W = 16,
    parameter int LEN_W  = 16
) (
    input  logic                     clk,
    input  logic                     rst_n,
    input  logic                     display_priority,

    // Master 0 descriptor channel (normally renderer).
    input  logic                     m0_req_valid,
    output logic                     m0_req_ready,
    input  logic                     m0_req_write,
    input  logic [ADDR_W-1:0]        m0_req_addr,
    input  logic [LEN_W-1:0]         m0_req_len,
    input  logic [DATA_W-1:0]        m0_req_wdata,
    input  logic [(DATA_W/8)-1:0]    m0_req_wstrb,

    // Master 0 write-data channel.  It is meaningful only for a write
    // descriptor accepted on m0_req_*.
    input  logic                     m0_wr_valid,
    output logic                     m0_wr_ready,
    input  logic [DATA_W-1:0]        m0_wr_data,
    input  logic [(DATA_W/8)-1:0]    m0_wr_strb,
    input  logic                     m0_wr_last,
    output logic                     m0_wr_error,

    // Write completion response.  This maps to AXI B or to the commit/error
    // indication of a DDR3 controller.  Ownership is retained until this
    // response is accepted, not merely until the final data beat.
    output logic                     m0_wr_rsp_valid,
    input  logic                     m0_wr_rsp_ready,
    output logic                     m0_wr_rsp_error,

    // Master 0 response channel.
    output logic                     m0_rsp_valid,
    input  logic                     m0_rsp_ready,
    output logic [DATA_W-1:0]        m0_rsp_rdata,
    output logic                     m0_rsp_last,
    output logic                     m0_rsp_error,

    // Master 1 descriptor channel (normally display/scanout).
    input  logic                     m1_req_valid,
    output logic                     m1_req_ready,
    input  logic                     m1_req_write,
    input  logic [ADDR_W-1:0]        m1_req_addr,
    input  logic [LEN_W-1:0]         m1_req_len,
    input  logic [DATA_W-1:0]        m1_req_wdata,
    input  logic [(DATA_W/8)-1:0]    m1_req_wstrb,

    // Master 1 write-data channel.
    input  logic                     m1_wr_valid,
    output logic                     m1_wr_ready,
    input  logic [DATA_W-1:0]        m1_wr_data,
    input  logic [(DATA_W/8)-1:0]    m1_wr_strb,
    input  logic                     m1_wr_last,
    output logic                     m1_wr_error,

    output logic                     m1_wr_rsp_valid,
    input  logic                     m1_wr_rsp_ready,
    output logic                     m1_wr_rsp_error,

    // Master 1 response channel.
    output logic                     m1_rsp_valid,
    input  logic                     m1_rsp_ready,
    output logic [DATA_W-1:0]        m1_rsp_rdata,
    output logic                     m1_rsp_last,
    output logic                     m1_rsp_error,

    // Shared downstream descriptor channel.
    output logic                     s_req_valid,
    input  logic                     s_req_ready,
    output logic                     s_req_write,
    output logic [ADDR_W-1:0]        s_req_addr,
    output logic [LEN_W-1:0]         s_req_len,
    output logic [DATA_W-1:0]        s_req_wdata,
    output logic [(DATA_W/8)-1:0]    s_req_wstrb,

    // Shared downstream write-data channel.
    output logic                     s_wr_valid,
    input  logic                     s_wr_ready,
    output logic [DATA_W-1:0]        s_wr_data,
    output logic [(DATA_W/8)-1:0]    s_wr_strb,
    output logic                     s_wr_last,
    // Optional downstream beat error from a DDR3/AXI adapter.  The
    // abstract simulation model drives this when an address/byte lane is out
    // of range; an omitted port is treated as inactive by case equality.
    input  logic                     s_wr_error,

    // Shared downstream write completion response.
    input  logic                     s_wr_rsp_valid,
    output logic                     s_wr_rsp_ready,
    input  logic                     s_wr_rsp_error,

    // Shared downstream response channel.
    input  logic                     s_rsp_valid,
    output logic                     s_rsp_ready,
    input  logic [DATA_W-1:0]        s_rsp_rdata,
    input  logic                     s_rsp_last,
    input  logic                     s_rsp_error,

    // State/diagnostic outputs.  owner_valid is low in ST_IDLE; owner_m1 is
    // meaningful only while owner_valid is high.
    output logic                     busy,
    output logic                     owner_valid,
    output logic                     owner_m1,
    output logic                     owner_write,
    output logic                     write_protocol_error,
    output logic [31:0]              write_protocol_error_count,
    output logic [31:0]              grant_count,
    output logic [31:0]              read_count,
    output logic [31:0]              write_count,
    output logic [31:0]              write_beat_count,
    output logic [31:0]              write_response_count,
    output logic [31:0]              write_response_error_count,
    output logic [31:0]              response_count,
    output logic [31:0]              response_protocol_error_count,
    output logic [31:0]              orphan_response_count,
    output logic [31:0]              orphan_write_response_count
);

    localparam int BYTE_LANES = DATA_W / 8;

    typedef enum logic [2:0] {
        ST_IDLE,
        ST_READ_M0,
        ST_READ_M1,
        ST_WRITE_M0,
        ST_WRITE_M1,
        ST_WRITE_RSP_M0,
        ST_WRITE_RSP_M1
    } state_e;

    state_e state_q;
    logic   rr_m1_q;
    logic   grant_m1;
    logic   grant_valid;
    logic   req_fire;
    logic   wr_fire;
    logic   wr_rsp_fire;
    logic   rsp_fire;
    logic   selected_req_write;
    logic [LEN_W:0] beats_left_q;
    logic           expected_last;
    logic           write_last_or_boundary;
    logic           read_last_or_boundary;
    logic           write_beat_error;
    logic           write_error_event;
    logic           pending_valid_q;
    logic           pending_m1_q;

    // -------------------------------------------------------------------------
    // Combinational routing.  All payload fields are assigned defaults so the
    // module remains friendly to lint and to Vivado's stricter SV elaborator.
    // -------------------------------------------------------------------------
    always_comb begin
        grant_m1       = 1'b0;
        grant_valid    = 1'b0;
        selected_req_write = 1'b0;

        if (state_q == ST_IDLE) begin
            if (pending_valid_q) begin
                // Once downstream has observed valid under back-pressure,
                // hold the selected source until the descriptor handshake.
                grant_m1    = pending_m1_q;
                grant_valid = 1'b1;
            end else if (m0_req_valid && m1_req_valid) begin
                // Display priority selects the first contested grant; later
                // ties round-robin so continuous scanout cannot starve render.
                grant_m1    = (grant_count == 0) ? display_priority : rr_m1_q;
                grant_valid = 1'b1;
            end else if (m1_req_valid) begin
                grant_m1    = 1'b1;
                grant_valid = 1'b1;
            end else if (m0_req_valid) begin
                grant_m1    = 1'b0;
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
                selected_req_write = m1_req_write;
                s_req_write = m1_req_write;
                s_req_addr  = m1_req_addr;
                s_req_len   = m1_req_len;
                s_req_wdata = m1_req_wdata;
                s_req_wstrb = m1_req_wstrb;
                m1_req_ready = s_req_ready;
            end else begin
                selected_req_write = m0_req_write;
                s_req_write = m0_req_write;
                s_req_addr  = m0_req_addr;
                s_req_len   = m0_req_len;
                s_req_wdata = m0_req_wdata;
                s_req_wstrb = m0_req_wstrb;
                m0_req_ready = s_req_ready;
            end
        end
        req_fire = s_req_valid && s_req_ready;

        // Defaults for independent write stream.
        s_wr_valid = 1'b0;
        s_wr_data  = '0;
        s_wr_strb  = '0;
        s_wr_last  = 1'b0;
        m0_wr_ready = 1'b0;
        m1_wr_ready = 1'b0;
        // Beat errors are generated combinationally below so the selected
        // producer sees them on the same accepted data beat.

        if (state_q == ST_WRITE_M0) begin
            s_wr_valid  = m0_wr_valid;
            s_wr_data   = m0_wr_data;
            s_wr_strb   = m0_wr_strb;
            s_wr_last   = m0_wr_last;
            m0_wr_ready = s_wr_ready;
        end else if (state_q == ST_WRITE_M1) begin
            s_wr_valid  = m1_wr_valid;
            s_wr_data   = m1_wr_data;
            s_wr_strb   = m1_wr_strb;
            s_wr_last   = m1_wr_last;
            m1_wr_ready = s_wr_ready;
        end
        wr_fire = s_wr_valid && s_wr_ready;

        // Write completion routing.  No new descriptor is considered until
        // the selected master accepts this response.
        m0_wr_rsp_valid = (state_q == ST_WRITE_RSP_M0) && s_wr_rsp_valid;
        m1_wr_rsp_valid = (state_q == ST_WRITE_RSP_M1) && s_wr_rsp_valid;
        m0_wr_rsp_error = s_wr_rsp_error;
        m1_wr_rsp_error = s_wr_rsp_error;
        s_wr_rsp_ready = 1'b0;
        if (state_q == ST_WRITE_RSP_M0)
            s_wr_rsp_ready = m0_wr_rsp_ready;
        else if (state_q == ST_WRITE_RSP_M1)
            s_wr_rsp_ready = m1_wr_rsp_ready;
        wr_rsp_fire = s_wr_rsp_valid && s_wr_rsp_ready;

        // Response routing is owner-qualified.  Keeping the data/last/error
        // values identical on both outputs is harmless, but valid is asserted
        // for exactly one selected master.
        m0_rsp_valid = (state_q == ST_READ_M0) && s_rsp_valid;
        m1_rsp_valid = (state_q == ST_READ_M1) && s_rsp_valid;
        m0_rsp_rdata = s_rsp_rdata;
        m1_rsp_rdata = s_rsp_rdata;
        m0_rsp_last   = s_rsp_last;
        m1_rsp_last   = s_rsp_last;
        m0_rsp_error  = s_rsp_error;
        m1_rsp_error  = s_rsp_error;

        s_rsp_ready = 1'b0;
        if (state_q == ST_READ_M0)
            s_rsp_ready = m0_rsp_ready;
        else if (state_q == ST_READ_M1)
            s_rsp_ready = m1_rsp_ready;
        rsp_fire = s_rsp_valid && s_rsp_ready;

        busy       = (state_q != ST_IDLE);
        owner_valid = (state_q != ST_IDLE);
        owner_m1   = (state_q == ST_READ_M1) ||
                     (state_q == ST_WRITE_M1) ||
                     (state_q == ST_WRITE_RSP_M1);
        owner_write = (state_q == ST_WRITE_M0) ||
                      (state_q == ST_WRITE_M1) ||
                      (state_q == ST_WRITE_RSP_M0) ||
                      (state_q == ST_WRITE_RSP_M1);

        expected_last      = (beats_left_q == {{LEN_W{1'b0}}, 1'b1});
        write_last_or_boundary = s_wr_last || expected_last ||
                                 (s_wr_error === 1'b1);
        // A downstream read error is terminal for the no-ID command contract:
        // the renderer will stop accepting the response after reporting the
        // error, so retaining the owner until a later last marker would
        // deadlock the shared port.
        read_last_or_boundary  = s_rsp_last || expected_last ||
                                 (s_rsp_error === 1'b1);
        write_beat_error = (s_wr_last != expected_last) ||
                           (s_wr_error === 1'b1);
        // Error outputs are combinational beat-qualified events.  This lets a
        // producer sample the error on the same clock edge as its terminal
        // write beat; the later wr_rsp reports controller commit status.
        write_error_event = wr_fire && write_beat_error;
        write_protocol_error = write_error_event;
        m0_wr_error = write_error_event && (state_q == ST_WRITE_M0);
        m1_wr_error = write_error_event && (state_q == ST_WRITE_M1);
    end

    // -------------------------------------------------------------------------
    // State and accounting.  The descriptor length is beats-minus-one, so
    // adding one yields a one-based remaining-beat count.  A malformed stream
    // is terminated at the first explicit last or at the advertised boundary;
    // this prevents an omitted last marker from deadlocking the shared port.
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q                    <= ST_IDLE;
            rr_m1_q                    <= 1'b0;
            pending_valid_q            <= 1'b0;
            pending_m1_q               <= 1'b0;
            beats_left_q               <= '0;
            write_protocol_error_count <= 32'd0;
            grant_count                <= 32'd0;
            read_count                 <= 32'd0;
            write_count                <= 32'd0;
            write_beat_count           <= 32'd0;
            write_response_count       <= 32'd0;
            write_response_error_count <= 32'd0;
            response_count             <= 32'd0;
            response_protocol_error_count <= 32'd0;
            orphan_response_count      <= 32'd0;
            orphan_write_response_count <= 32'd0;
        end else begin
            if (s_rsp_valid && (state_q == ST_IDLE))
                orphan_response_count <= orphan_response_count + 32'd1;
            if (s_wr_rsp_valid &&
                (state_q != ST_WRITE_RSP_M0) &&
                (state_q != ST_WRITE_RSP_M1))
                orphan_write_response_count <=
                    orphan_write_response_count + 32'd1;

            if ((state_q == ST_IDLE) && !pending_valid_q && grant_valid &&
                !s_req_ready) begin
                pending_valid_q <= 1'b1;
                pending_m1_q    <= grant_m1;
            end

            if (req_fire) begin
                pending_valid_q <= 1'b0;
                grant_count <= grant_count + 32'd1;
                // Next tie goes to the other master.  This assignment is made
                // at descriptor acceptance, before a potentially long burst.
                rr_m1_q <= ~grant_m1;
                beats_left_q <= {1'b0, (grant_m1 ? m1_req_len : m0_req_len)} +
                                {{LEN_W{1'b0}}, 1'b1};
                if (selected_req_write) begin
                    write_count <= write_count + 32'd1;
                    state_q <= grant_m1 ? ST_WRITE_M1 : ST_WRITE_M0;
                end else begin
                    read_count <= read_count + 32'd1;
                    state_q <= grant_m1 ? ST_READ_M1 : ST_READ_M0;
                end
            end else if (wr_fire) begin
                write_beat_count <= write_beat_count + 32'd1;
                if (write_beat_error) begin
                    write_protocol_error_count <=
                        write_protocol_error_count + 32'd1;
                end

                if (write_last_or_boundary) begin
                    // The data phase is complete, but the owner remains held
                    // until the downstream controller reports commit/error.
                    state_q      <= (state_q == ST_WRITE_M0) ?
                                    ST_WRITE_RSP_M0 : ST_WRITE_RSP_M1;
                    beats_left_q <= '0;
                end else begin
                    beats_left_q <= beats_left_q - {{LEN_W{1'b0}}, 1'b1};
                end
            end else if (wr_rsp_fire) begin
                write_response_count <= write_response_count + 32'd1;
                if (s_wr_rsp_error)
                    write_response_error_count <=
                        write_response_error_count + 32'd1;
                state_q      <= ST_IDLE;
                beats_left_q <= '0;
                rr_m1_q <= (state_q == ST_WRITE_RSP_M0);
            end else if (rsp_fire) begin
                response_count <= response_count + 32'd1;
                if (s_rsp_last != expected_last)
                    response_protocol_error_count <=
                        response_protocol_error_count + 32'd1;

                if (read_last_or_boundary) begin
                    state_q      <= ST_IDLE;
                    beats_left_q <= '0;
                    rr_m1_q <= (state_q == ST_READ_M0);
                end else begin
                    beats_left_q <= beats_left_q - {{LEN_W{1'b0}}, 1'b1};
                end
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (ADDR_W <= 0 || DATA_W <= 0 || (DATA_W % 8) != 0 || LEN_W <= 0)
            $error("c2_mem_arbiter_2m_owner: invalid interface width");
    end
`endif

endmodule
