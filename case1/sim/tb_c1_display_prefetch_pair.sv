`timescale 1ns/1ps

module tb_c1_display_prefetch_pair;
    localparam integer WIDTH = 4;
    localparam integer HEIGHT = 3;
    localparam logic [15:0] WIDTH_CFG = WIDTH;
    localparam logic [15:0] HEIGHT_CFG = HEIGHT;

    logic core_clk = 1'b0;
    logic pixel_clk = 1'b0;
    logic core_rst = 1'b1;
    logic pixel_rst = 1'b1;
    logic start_valid;
    logic start_ready;
    logic abort;
    logic busy;
    logic done;
    logic aborted;
    logic error;
    logic primed;

    logic original_request;
    logic [1:0] original_request_x;
    logic [7:0] original_request_y;
    logic original_response_valid;
    logic [23:0] original_rgb;
    logic original_underflow;
    logic styled_request;
    logic [1:0] styled_request_x;
    logic [7:0] styled_request_y;
    logic styled_response_valid;
    logic [23:0] styled_rgb;
    logic styled_underflow;

    logic [31:0] o_araddr;
    logic [7:0] o_arlen;
    logic [2:0] o_arsize;
    logic [1:0] o_arburst;
    logic o_arvalid;
    logic o_arready;
    logic [127:0] o_rdata;
    logic [1:0] o_rresp;
    logic o_rlast;
    logic o_rvalid;
    logic o_rready;
    logic [31:0] s_araddr;
    logic [7:0] s_arlen;
    logic [2:0] s_arsize;
    logic [1:0] s_arburst;
    logic s_arvalid;
    logic s_arready;
    logic [127:0] s_rdata;
    logic [1:0] s_rresp;
    logic s_rlast;
    logic s_rvalid;
    logic s_rready;

    logic o_pending;
    logic s_pending;
    logic [31:0] o_addr_q;
    logic [31:0] s_addr_q;
    integer original_ar_count;
    integer styled_ar_count;
    integer pixels_checked;
    integer done_pulses;
    integer aborted_pulses;

    always #5 core_clk = ~core_clk;
    always #7 pixel_clk = ~pixel_clk;

    function automatic [23:0] expected_rgb(
        input logic styled,
        input integer row,
        input integer lane
    );
        begin
            expected_rgb = {(styled ? 8'h20 : 8'h10), row[7:0], lane[7:0]};
        end
    endfunction

    function automatic [127:0] make_beat(
        input logic styled,
        input logic [31:0] address
    );
        integer row;
        integer lane;
        logic [127:0] value;
        logic [23:0] rgb;
        begin
            row = (address - (styled ? 32'h00002000 : 32'h00001000)) >> 4;
            value = 128'd0;
            for (lane = 0; lane < 4; lane = lane + 1) begin
                rgb = expected_rgb(styled, row, lane);
                value[lane*32 +: 32] = {8'h00, rgb};
            end
            make_beat = value;
        end
    endfunction

    assign o_arready = !o_pending && !o_rvalid;
    assign s_arready = !s_pending && !s_rvalid;

    always_ff @(posedge core_clk) begin
        if (core_rst) begin
            o_pending <= 1'b0;
            o_addr_q <= 32'd0;
            o_rdata <= 128'd0;
            o_rresp <= 2'b00;
            o_rlast <= 1'b0;
            o_rvalid <= 1'b0;
            original_ar_count <= 0;
        end else begin
            if (o_arvalid && o_arready) begin
                if ((o_arlen != 0) || (o_arsize != 3'd4) ||
                    (o_arburst != 2'b01))
                    $fatal(1, "original display AXI request shape mismatch");
                o_addr_q <= o_araddr;
                o_pending <= 1'b1;
                original_ar_count <= original_ar_count + 1;
            end
            if (o_pending && !o_rvalid) begin
                o_pending <= 1'b0;
                o_rdata <= make_beat(1'b0, o_addr_q);
                o_rresp <= 2'b00;
                o_rlast <= 1'b1;
                o_rvalid <= 1'b1;
            end
            if (o_rvalid && o_rready) begin
                o_rvalid <= 1'b0;
                o_rlast <= 1'b0;
            end
        end
    end

    always_ff @(posedge core_clk) begin
        if (core_rst) begin
            s_pending <= 1'b0;
            s_addr_q <= 32'd0;
            s_rdata <= 128'd0;
            s_rresp <= 2'b00;
            s_rlast <= 1'b0;
            s_rvalid <= 1'b0;
            styled_ar_count <= 0;
        end else begin
            if (s_arvalid && s_arready) begin
                if ((s_arlen != 0) || (s_arsize != 3'd4) ||
                    (s_arburst != 2'b01))
                    $fatal(1, "styled display AXI request shape mismatch");
                s_addr_q <= s_araddr;
                s_pending <= 1'b1;
                styled_ar_count <= styled_ar_count + 1;
            end
            if (s_pending && !s_rvalid) begin
                s_pending <= 1'b0;
                s_rdata <= make_beat(1'b1, s_addr_q);
                s_rresp <= 2'b00;
                s_rlast <= 1'b1;
                s_rvalid <= 1'b1;
            end
            if (s_rvalid && s_rready) begin
                s_rvalid <= 1'b0;
                s_rlast <= 1'b0;
            end
        end
    end

    c1_display_prefetch_pair #(
        .MAX_WIDTH(WIDTH), .X_BITS(2), .Y_BITS(8)
    ) dut (
        .core_clk(core_clk), .core_rst(core_rst),
         .start_valid(start_valid), .start_ready(start_ready), .abort(abort),
         .hold_requests(1'b0),
        .original_base(32'h00001000), .original_stride(32'd16),
        .styled_base(32'h00002000), .styled_stride(32'd16),
         .width_pixels(WIDTH_CFG), .height_lines(HEIGHT_CFG),
        .busy(busy), .done(done), .aborted(aborted), .error(error),
        .primed(primed),
        .pixel_clk(pixel_clk), .pixel_rst(pixel_rst),
        .original_request(original_request),
        .original_request_x(original_request_x),
        .original_request_y(original_request_y),
        .original_response_valid(original_response_valid),
        .original_rgb(original_rgb),
        .original_underflow(original_underflow),
        .styled_request(styled_request), .styled_request_x(styled_request_x),
        .styled_request_y(styled_request_y),
        .styled_response_valid(styled_response_valid), .styled_rgb(styled_rgb),
        .styled_underflow(styled_underflow),
        .original_axi_araddr(o_araddr), .original_axi_arlen(o_arlen),
        .original_axi_arsize(o_arsize), .original_axi_arburst(o_arburst),
        .original_axi_arvalid(o_arvalid), .original_axi_arready(o_arready),
        .original_axi_rdata(o_rdata), .original_axi_rresp(o_rresp),
        .original_axi_rlast(o_rlast), .original_axi_rvalid(o_rvalid),
        .original_axi_rready(o_rready),
        .styled_axi_araddr(s_araddr), .styled_axi_arlen(s_arlen),
        .styled_axi_arsize(s_arsize), .styled_axi_arburst(s_arburst),
        .styled_axi_arvalid(s_arvalid), .styled_axi_arready(s_arready),
        .styled_axi_rdata(s_rdata), .styled_axi_rresp(s_rresp),
        .styled_axi_rlast(s_rlast), .styled_axi_rvalid(s_rvalid),
        .styled_axi_rready(s_rready)
    );

    always_ff @(posedge core_clk) begin
        if (core_rst) begin
            done_pulses <= 0;
            aborted_pulses <= 0;
        end else if (done) begin
            done_pulses <= done_pulses + 1;
            if (aborted)
                aborted_pulses <= aborted_pulses + 1;
        end
    end

    task automatic start_job;
        begin
            @(negedge core_clk);
            if (!start_ready)
                $fatal(1, "display prefetch start not ready");
            start_valid = 1'b1;
            @(posedge core_clk);
            @(negedge core_clk);
            start_valid = 1'b0;
        end
    endtask

    task automatic request_original_pixel(input integer row,
                                          input integer lane);
        logic [23:0] expected;
        begin
            expected = expected_rgb(1'b0, row, lane);
            @(negedge pixel_clk);
            original_request = 1'b1;
            original_request_x = lane[1:0];
            original_request_y = row[7:0];
            @(posedge pixel_clk);
            #1;
            if (!original_response_valid || original_underflow ||
                (original_rgb !== expected))
                $fatal(1, "original pixel mismatch row=%0d lane=%0d got=%06x",
                       row, lane, original_rgb);
            pixels_checked = pixels_checked + 1;
            @(negedge pixel_clk);
            original_request = 1'b0;
        end
    endtask

    task automatic request_styled_pixel(input integer row,
                                        input integer lane);
        logic [23:0] expected;
        begin
            expected = expected_rgb(1'b1, row, lane);
            @(negedge pixel_clk);
            styled_request = 1'b1;
            styled_request_x = lane[1:0];
            styled_request_y = row[7:0];
            @(posedge pixel_clk);
            #1;
            if (!styled_response_valid || styled_underflow ||
                (styled_rgb !== expected))
                $fatal(1, "styled pixel mismatch row=%0d lane=%0d got=%06x",
                       row, lane, styled_rgb);
            pixels_checked = pixels_checked + 1;
            @(negedge pixel_clk);
            styled_request = 1'b0;
        end
    endtask

    task automatic consume_pair_line(input integer row);
        integer lane;
        begin
            for (lane = 0; lane < WIDTH; lane = lane + 1)
                request_original_pixel(row, lane);
            for (lane = 0; lane < WIDTH; lane = lane + 1)
                request_styled_pixel(row, lane);
        end
    endtask

    initial begin
        start_valid = 1'b0;
        abort = 1'b0;
        original_request = 1'b0;
        original_request_x = '0;
        original_request_y = '0;
        styled_request = 1'b0;
        styled_request_x = '0;
        styled_request_y = '0;
        pixels_checked = 0;

        repeat (6) @(posedge core_clk);
        repeat (5) @(posedge pixel_clk);
        @(negedge core_clk);
        core_rst = 1'b0;
        @(negedge pixel_clk);
        pixel_rst = 1'b0;

        start_job();
        fork
            begin
                repeat (300) @(posedge core_clk);
                if (!primed)
                    $fatal(1, "display pair did not prime both line stores");
            end
            begin
                wait (primed);
            end
        join_any
        disable fork;

        consume_pair_line(0);
        consume_pair_line(1);
        repeat (40) @(posedge core_clk);
        consume_pair_line(2);

        wait (done_pulses >= 1);
        if ((aborted_pulses != 0) || error)
            $fatal(1, "normal display prefetch completed with terminal flag");
        repeat (8) @(posedge core_clk);
        if (!start_ready)
            $fatal(1, "display prefetch did not return ready after consumption");

        // A second job is cancelled after at least one read request.  Both
        // readers must retire protocol-safely and report one aborted terminal.
        start_job();
        wait ((original_ar_count + styled_ar_count) >= 7);
        @(negedge core_clk);
        abort = 1'b1;
        @(posedge core_clk);
        @(negedge core_clk);
        abort = 1'b0;
        wait (done_pulses >= 2);
        if (aborted_pulses != 1)
            $fatal(1, "cancelled display prefetch did not report aborted");

        if ((original_ar_count + styled_ar_count) < 7)
            $fatal(1, "insufficient display AXI activity");
        $display("C1_DISPLAY_PREFETCH_PAIR_PASS jobs=%0d aborts=%0d ar=%0d pixels=%0d",
                 done_pulses-aborted_pulses, aborted_pulses,
                 original_ar_count+styled_ar_count, pixels_checked);
        $finish;
    end

    initial begin
        #500000;
        $fatal(1, "display prefetch pair test timeout");
    end
endmodule
