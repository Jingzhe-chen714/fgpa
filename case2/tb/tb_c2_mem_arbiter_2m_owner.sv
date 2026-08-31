`timescale 1ns/1ps

// Minimal owner-arbiter regression.
//
// Phase 0 checks two competing burst writes.  The second descriptor is kept
// pending while the first owner sends three data beats; after the first
// wr_last, ownership changes and the second stream sends two beats.
// Phase 1 checks that a three-beat response (and its last marker) remains
// routed to master 0 while master 1 waits, then master 1 receives its own
// one-beat response.
module tb_c2_mem_arbiter_2m_owner;
    logic clk = 1'b0;
    always #5 clk = ~clk;
    logic rst_n = 1'b0;
    logic display_priority = 1'b0;

    logic m0_req_valid, m0_req_ready, m0_req_write;
    logic [31:0] m0_req_addr;
    logic [15:0] m0_req_len, m0_req_wdata;
    logic [1:0] m0_req_wstrb;
    logic m0_wr_valid, m0_wr_ready, m0_wr_last;
    logic [15:0] m0_wr_data;
    logic [1:0] m0_wr_strb;
    logic m0_wr_error;
    logic m0_wr_rsp_valid, m0_wr_rsp_ready, m0_wr_rsp_error;
    logic m0_rsp_valid, m0_rsp_ready;
    logic [15:0] m0_rsp_rdata;
    logic m0_rsp_last, m0_rsp_error;

    logic m1_req_valid, m1_req_ready, m1_req_write;
    logic [31:0] m1_req_addr;
    logic [15:0] m1_req_len, m1_req_wdata;
    logic [1:0] m1_req_wstrb;
    logic m1_wr_valid, m1_wr_ready, m1_wr_last;
    logic [15:0] m1_wr_data;
    logic [1:0] m1_wr_strb;
    logic m1_wr_error;
    logic m1_wr_rsp_valid, m1_wr_rsp_ready, m1_wr_rsp_error;
    logic m1_rsp_valid, m1_rsp_ready;
    logic [15:0] m1_rsp_rdata;
    logic m1_rsp_last, m1_rsp_error;

    logic s_req_valid, s_req_ready, s_req_write;
    logic [31:0] s_req_addr;
    logic [15:0] s_req_len, s_req_wdata;
    logic [1:0] s_req_wstrb;
    logic s_wr_valid, s_wr_ready, s_wr_last;
    logic [15:0] s_wr_data;
    logic [1:0] s_wr_strb;
    logic s_wr_error;
    logic s_wr_rsp_valid, s_wr_rsp_ready, s_wr_rsp_error;
    logic s_rsp_valid, s_rsp_ready, s_rsp_last, s_rsp_error;
    logic [15:0] s_rsp_rdata;

    logic rsp_valid_q;
    logic [15:0] rsp_data_q;
    logic rsp_last_q;

    logic busy, owner_valid, owner_m1, owner_write;
    logic write_protocol_error;
    logic [31:0] write_protocol_error_count;
    logic [31:0] grant_count, read_count, write_count, write_beat_count;
    logic [31:0] write_response_count, write_response_error_count;
    logic [31:0] response_count, response_protocol_error_count;
    logic [31:0] orphan_response_count;
    logic [31:0] orphan_write_response_count;
    logic wr_rsp_pending_q;

    c2_mem_arbiter_2m_owner u_dut (
        .clk, .rst_n, .display_priority,
        .m0_req_valid, .m0_req_ready, .m0_req_write, .m0_req_addr,
        .m0_req_len, .m0_req_wdata, .m0_req_wstrb,
        .m0_wr_valid, .m0_wr_ready, .m0_wr_data, .m0_wr_strb, .m0_wr_last,
        .m0_wr_error,
        .m0_wr_rsp_valid, .m0_wr_rsp_ready, .m0_wr_rsp_error,
        .m0_rsp_valid, .m0_rsp_ready, .m0_rsp_rdata, .m0_rsp_last,
        .m0_rsp_error,
        .m1_req_valid, .m1_req_ready, .m1_req_write, .m1_req_addr,
        .m1_req_len, .m1_req_wdata, .m1_req_wstrb,
        .m1_wr_valid, .m1_wr_ready, .m1_wr_data, .m1_wr_strb, .m1_wr_last,
        .m1_wr_error,
        .m1_wr_rsp_valid, .m1_wr_rsp_ready, .m1_wr_rsp_error,
        .m1_rsp_valid, .m1_rsp_ready, .m1_rsp_rdata, .m1_rsp_last,
        .m1_rsp_error,
        .s_req_valid, .s_req_ready, .s_req_write, .s_req_addr, .s_req_len,
        .s_req_wdata, .s_req_wstrb,
        .s_wr_valid, .s_wr_ready, .s_wr_data, .s_wr_strb, .s_wr_last,
        .s_wr_error,
        .s_wr_rsp_valid, .s_wr_rsp_ready, .s_wr_rsp_error,
        .s_rsp_valid, .s_rsp_ready, .s_rsp_rdata, .s_rsp_last, .s_rsp_error,
        .busy, .owner_valid, .owner_m1, .owner_write,
        .write_protocol_error, .write_protocol_error_count,
        .grant_count, .read_count, .write_count,
        .write_beat_count, .write_response_count, .write_response_error_count,
        .response_count, .response_protocol_error_count,
        .orphan_response_count, .orphan_write_response_count
    );

    assign s_req_ready = 1'b1;
    assign s_wr_ready  = 1'b1;
    assign s_wr_error  = 1'b0;
    assign s_wr_rsp_valid = wr_rsp_pending_q;
    assign s_wr_rsp_error = 1'b0;
    assign m0_wr_rsp_ready = 1'b1;
    assign m1_wr_rsp_ready = 1'b1;
    assign m0_rsp_ready = 1'b1;
    assign m1_rsp_ready = 1'b1;
    assign s_rsp_valid = rsp_valid_q;
    assign s_rsp_rdata = rsp_data_q;
    assign s_rsp_last  = rsp_last_q;
    assign s_rsp_error = 1'b0;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            wr_rsp_pending_q <= 1'b0;
        else begin
            if (wr_rsp_pending_q && s_wr_rsp_ready)
                wr_rsp_pending_q <= 1'b0;
            if (s_wr_valid && s_wr_ready && s_wr_last)
                wr_rsp_pending_q <= 1'b1;
        end
    end

    integer phase;
    integer write_seen;
    integer response_seen_m0;
    integer response_seen_m1;
    integer descriptor_seen;

    // Downstream-side checks.  Since s_req_ready/s_wr_ready are tied high,
    // every asserted valid is an accepted beat at the following edge.
    always @(posedge clk) begin
        if (rst_n) begin
            if (s_req_valid && s_req_ready) begin
                descriptor_seen = descriptor_seen + 1;
                if (phase == 0) begin
                    if (!s_req_write)
                        $fatal(1, "write phase emitted a read descriptor");
                    if (descriptor_seen == 1 && s_req_len != 16'd2)
                        $fatal(1, "m0 descriptor length mismatch");
                    if (descriptor_seen == 2 && s_req_len != 16'd1)
                        $fatal(1, "m1 descriptor length mismatch");
                end
            end
            if (s_wr_valid && s_wr_ready && phase == 0) begin
                case (write_seen)
                    0: if (s_wr_data !== 16'h1000 || s_wr_last)
                           $fatal(1, "m0 write beat0 mismatch");
                    1: if (s_wr_data !== 16'h1001 || s_wr_last)
                           $fatal(1, "m0 write beat1 mismatch");
                    2: if (s_wr_data !== 16'h1002 || !s_wr_last)
                           $fatal(1, "m0 write beat2 mismatch");
                    3: if (s_wr_data !== 16'h2000 || s_wr_last)
                           $fatal(1, "m1 write beat0 mismatch");
                    4: if (s_wr_data !== 16'h2001 || !s_wr_last)
                           $fatal(1, "m1 write beat1 mismatch");
                    default: $fatal(1, "extra write beat");
                endcase
                write_seen = write_seen + 1;
            end
            if (m0_rsp_valid && m0_rsp_ready && phase == 1) begin
                case (response_seen_m0)
                    0: if (m0_rsp_rdata !== 16'hA000 || m0_rsp_last)
                           $fatal(1, "m0 response beat0 mismatch");
                    1: if (m0_rsp_rdata !== 16'hA001 || m0_rsp_last)
                           $fatal(1, "m0 response beat1 mismatch");
                    2: if (m0_rsp_rdata !== 16'hA002 || !m0_rsp_last)
                           $fatal(1, "m0 response beat2 mismatch");
                    default: $fatal(1, "extra m0 response");
                endcase
                response_seen_m0 = response_seen_m0 + 1;
            end
            if (m1_rsp_valid && m1_rsp_ready && phase == 1) begin
                if (response_seen_m1 != 0 || m1_rsp_rdata !== 16'hB000 ||
                    !m1_rsp_last)
                    $fatal(1, "m1 response mismatch");
                response_seen_m1 = response_seen_m1 + 1;
            end
        end
    end

    task automatic send_m0_write;
        integer i;
        begin
            @(negedge clk);
            m0_req_valid = 1'b1;
            while (1) begin
                @(posedge clk);
                if (m0_req_ready) begin
                    @(negedge clk);
                    m0_req_valid = 1'b0;
                    break;
                end
            end
            for (i = 0; i < 3; i = i + 1) begin
                if (i == 0)
                    @(negedge clk);
                m0_wr_valid = 1'b1;
                m0_wr_data = 16'h1000 + i;
                m0_wr_last = (i == 2);
                while (1) begin
                    @(posedge clk);
                    if (m0_wr_ready) begin
                        if (i != 2)
                            @(negedge clk);
                        break;
                    end
                end
            end
            m0_wr_valid = 1'b0;
            m0_wr_last = 1'b0;
        end
    endtask

    task automatic send_m1_write;
        integer i;
        begin
            @(negedge clk);
            m1_req_valid = 1'b1;
            while (1) begin
                @(posedge clk);
                if (m1_req_ready) begin
                    @(negedge clk);
                    m1_req_valid = 1'b0;
                    break;
                end
            end
            for (i = 0; i < 2; i = i + 1) begin
                if (i == 0)
                    @(negedge clk);
                m1_wr_valid = 1'b1;
                m1_wr_data = 16'h2000 + i;
                m1_wr_last = (i == 1);
                while (1) begin
                    @(posedge clk);
                    if (m1_wr_ready) begin
                        if (i != 1)
                            @(negedge clk);
                        break;
                    end
                end
            end
            m1_wr_valid = 1'b0;
            m1_wr_last = 1'b0;
        end
    endtask

    task automatic send_m0_read_descriptor;
        begin
            @(negedge clk);
            m0_req_valid = 1'b1;
            while (1) begin
                @(posedge clk);
                if (m0_req_ready) begin
                    @(negedge clk);
                    m0_req_valid = 1'b0;
                    break;
                end
            end
        end
    endtask

    task automatic send_m1_read_descriptor;
        begin
            @(negedge clk);
            m1_req_valid = 1'b1;
            while (1) begin
                @(posedge clk);
                if (m1_req_ready) begin
                    @(negedge clk);
                    m1_req_valid = 1'b0;
                    break;
                end
            end
        end
    endtask

    task automatic send_response;
        input integer beats;
        input [15:0] base;
        integer i;
        begin
            for (i = 0; i < beats; i = i + 1) begin
                if (i == 0)
                    @(negedge clk);
                rsp_valid_q = 1'b1;
                rsp_data_q  = base + i;
                rsp_last_q  = (i == beats - 1);
                while (1) begin
                    @(posedge clk);
                    if (s_rsp_ready) begin
                        if (i != beats - 1)
                            @(negedge clk);
                        rsp_valid_q = 1'b0;
                        break;
                    end
                end
            end
            rsp_last_q = 1'b0;
        end
    endtask

    initial begin
        m0_req_valid = 1'b0; m0_req_write = 1'b1; m0_req_addr = 0;
        m0_req_len = 16'd2; m0_req_wdata = 0; m0_req_wstrb = 2'b11;
        m0_wr_valid = 1'b0; m0_wr_data = 0; m0_wr_strb = 2'b11;
        m0_wr_last = 1'b0;
        m1_req_valid = 1'b0; m1_req_write = 1'b1; m1_req_addr = 32'd32;
        m1_req_len = 16'd1; m1_req_wdata = 0; m1_req_wstrb = 2'b11;
        m1_wr_valid = 1'b0; m1_wr_data = 0; m1_wr_strb = 2'b11;
        m1_wr_last = 1'b0;
        rsp_valid_q = 1'b0; rsp_data_q = 0; rsp_last_q = 1'b0;
        phase = 0; write_seen = 0; descriptor_seen = 0;
        response_seen_m0 = 0; response_seen_m1 = 0;

        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        fork
            send_m0_write();
            send_m1_write();
        join
        repeat (3) @(posedge clk);
        if (write_seen != 5 || descriptor_seen != 2 || grant_count != 2 ||
            write_count != 2 || write_beat_count != 5 || busy ||
            write_protocol_error)
            $fatal(1, "owner write mismatch seen=%0d desc=%0d grants=%0d writes=%0d beats=%0d busy=%b err=%b",
                   write_seen, descriptor_seen, grant_count, write_count,
                   write_beat_count, busy, write_protocol_error);

        // Start the response-owner phase from a clean state.  The counters are
        // intentionally reset so the expected values remain easy to inspect.
        rst_n = 1'b0;
        repeat (2) @(posedge clk);
        phase = 1;
        descriptor_seen = 0;
        response_seen_m0 = 0;
        response_seen_m1 = 0;
        m0_req_write = 1'b0; m0_req_len = 16'd2; m0_req_addr = 0;
        m1_req_write = 1'b0; m1_req_len = 16'd0; m1_req_addr = 32'd32;
        rst_n = 1'b1;

        fork
            send_m0_read_descriptor();
            send_m1_read_descriptor();
        join_none
        // m0 is selected first (round-robin pointer reset to m0).  Inject its
        // three responses while m1 remains blocked behind the owner.
        wait (m0_req_valid == 1'b0);
        send_response(3, 16'hA000);
        // m1 descriptor is accepted after m0's final response.  Its response
        // follows once the owner changes.
        wait (m1_req_valid == 1'b0);
        send_response(1, 16'hB000);
        repeat (4) @(posedge clk);

        if (response_seen_m0 != 3 || response_seen_m1 != 1 ||
            response_count != 4 || read_count != 2 || busy ||
            response_protocol_error_count != 0)
            $fatal(1, "owner response mismatch m0=%0d m1=%0d rsp=%0d reads=%0d busy=%b err=%0d",
                   response_seen_m0, response_seen_m1, response_count,
                   read_count, busy, response_protocol_error_count);

        $display("TB_C2_MEM_ARBITER_OWNER_PASS writes=%0d responses=%0d",
                 write_seen, response_count);
        $finish;
    end
endmodule
