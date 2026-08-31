module tb_c1_r1_soc_control;
    logic clk = 1'b0;
    logic rst = 1'b1;
    always #5 clk = ~clk;

    logic system_enable, continuous_mode, drop_oldest_mode;
    logic start_pulse, abort_pulse;
    logic [15:0] frame_width, frame_height;
    logic [3:0] input_pixel_format, output_pixel_format;
    logic [63:0] input_table_base, output_table_base;
    logic [63:0] descriptor_base, weight_base;
    logic [31:0] tensor_base_addr;
    logic [15:0] descriptor_count;
    logic status_busy, done_event, error_event;
    logic [7:0] error_code;
    logic [31:0] error_address;
    logic capture_drop_event, display_swap_event;
    logic [2:0] input_ready_count;
    logic [1:0] output_ready_count;
    logic [31:0] display_frame_id;
    logic display_feed_active, display_hold_requests;
    logic parameter_start_valid, parameter_start_ready;
    logic [31:0] parameter_base_addr;
    logic parameter_abort_request, parameter_abort_pending;
    logic parameter_busy, parameter_done;
    logic parameter_error, parameter_aborted;
    logic [3:0] parameter_error_code;
    logic [31:0] parameter_error_address;
    logic parameter_active_valid;
    logic [31:0] parameter_generation;
    logic [31:0] active_parameter_generation;
    logic capture_frame_waiting, capture_begin_ready;
    logic capture_begin_frame, capture_drop_frame, capture_abort_frame;
    logic capture_clear_error, capture_discard_idle, capture_cleanup_busy;
    logic capture_ingress_done;
    logic capture_frame_dropped, capture_frame_aborted, capture_error;
    logic [7:0] capture_error_code;
    logic capture_table_request_valid, capture_table_request_ready;
    logic [63:0] capture_table_request_base;
    logic [1:0] capture_table_request_index;
    logic capture_table_response_valid, capture_table_response_ready;
    logic capture_table_response_error;
    logic [63:0] capture_table_response_base;
    logic [31:0] capture_table_response_stride;
    logic [15:0] capture_table_response_width;
    logic [15:0] capture_table_response_height;
    logic capture_table_abort_request, capture_table_abort_pending;
    logic capture_writer_start, capture_writer_cancel;
    logic [31:0] capture_writer_base, capture_writer_stride;
    logic [15:0] capture_writer_width, capture_writer_height;
    logic capture_writer_busy, capture_writer_done, capture_writer_error;
    logic boardless_start_valid, boardless_start_ready, boardless_abort;
    logic [1:0] boardless_input_index, boardless_output_index;
    logic [63:0] boardless_input_table_base;
    logic [63:0] boardless_output_table_base;
    logic [15:0] boardless_frame_width, boardless_frame_height;
    logic [31:0] boardless_descriptor_base;
    logic [15:0] boardless_descriptor_count;
    logic [31:0] boardless_cycle_budget;
    logic [31:0] boardless_tensor_base_addr;
    logic boardless_busy, boardless_done, boardless_error;
    logic boardless_aborted;
    logic [7:0] boardless_error_code;
    logic [31:0] boardless_error_address;
    logic [31:0] boardless_resolved_input_base;
    logic [31:0] boardless_resolved_input_stride;
    logic [15:0] boardless_resolved_input_width;
    logic [15:0] boardless_resolved_input_height;
    logic [31:0] boardless_resolved_output_base;
    logic [31:0] boardless_resolved_output_stride;
    logic [15:0] boardless_resolved_output_width;
    logic [15:0] boardless_resolved_output_height;
    logic display_frame_start_event;
    logic display_prefetch_start_valid, display_prefetch_start_ready;
    logic display_prefetch_abort, display_flush_request, display_flush_busy;
    logic [31:0] display_original_base, display_original_stride;
    logic [31:0] display_styled_base, display_styled_stride;
    logic [15:0] display_width, display_height;
    logic display_prefetch_busy, display_prefetch_done;
    logic display_prefetch_aborted, display_prefetch_error;
    logic display_prefetch_primed;

    integer capture_requests = 0;
    integer nn_launches = 0;
    integer prefetch_launches = 0;
    integer swaps = 0;
    integer repeats = 0;
    integer errors = 0;

`ifdef C1_REPLICATE_ABORT_CONTROL
    localparam integer REPLICATE_ABORT_CONTROL_CFG = 1;
`else
    localparam integer REPLICATE_ABORT_CONTROL_CFG = 0;
`endif
`ifdef C1_REGISTER_FATAL_TICKET
    localparam integer REGISTER_FATAL_TICKET_CFG = 1;
`else
    localparam integer REGISTER_FATAL_TICKET_CFG = 0;
`endif

    c1_r1_soc_control #(
        .REPLICATE_ABORT_CONTROL(REPLICATE_ABORT_CONTROL_CFG),
        .REGISTER_FATAL_TICKET(REGISTER_FATAL_TICKET_CFG)
    ) dut (.*);

    task automatic tick(input integer count);
        repeat (count) @(posedge clk);
    endtask

    task automatic pulse_start;
        begin
            @(negedge clk);
            start_pulse = 1'b1;
            @(negedge clk);
            start_pulse = 1'b0;
        end
    endtask

    always @(posedge clk) begin
        if (capture_table_request_valid && capture_table_request_ready)
            capture_requests <= capture_requests + 1;
        if (boardless_start_valid && boardless_start_ready)
            nn_launches <= nn_launches + 1;
        if (display_prefetch_start_valid &&
            display_prefetch_start_ready) begin
            prefetch_launches <= prefetch_launches + 1;
            if (display_feed_active)
                repeats <= repeats + 1;
        end
        if (display_swap_event)
            swaps <= swaps + 1;
        if (error_event)
            errors <= errors + 1;
    end

    initial begin
        system_enable = 1'b0;
        continuous_mode = 1'b1;
        drop_oldest_mode = 1'b1;
        start_pulse = 1'b0;
        abort_pulse = 1'b0;
        frame_width = 16'd640;
        frame_height = 16'd480;
        input_pixel_format = 4'd2;
        output_pixel_format = 4'd2;
        input_table_base = 64'h0000_0000_0001_0000;
        output_table_base = 64'h0000_0000_0002_0000;
        descriptor_base = 64'h0000_0000_0003_0000;
        descriptor_count = 16'd22;
        weight_base = 64'h0000_0000_0004_0000;
        tensor_base_addr = 32'h0200_0000;
        parameter_start_ready = 1'b1;
        parameter_busy = 1'b0;
        parameter_abort_pending = 1'b0;
        parameter_done = 1'b0;
        parameter_error = 1'b0;
        parameter_aborted = 1'b0;
        parameter_error_code = 4'd0;
        parameter_error_address = 32'd0;
        parameter_active_valid = 1'b0;
        parameter_generation = 32'd0;
        capture_frame_waiting = 1'b0;
        capture_begin_ready = 1'b1;
        capture_ingress_done = 1'b0;
        capture_frame_dropped = 1'b0;
        capture_frame_aborted = 1'b0;
        capture_error = 1'b0;
        capture_error_code = 8'd0;
        capture_cleanup_busy = 1'b0;
        capture_table_request_ready = 1'b1;
        capture_table_abort_pending = 1'b0;
        capture_table_response_valid = 1'b0;
        capture_table_response_error = 1'b0;
        capture_table_response_base = 64'h0000_0000_0010_0000;
        capture_table_response_stride = 32'd2560;
        capture_table_response_width = 16'd640;
        capture_table_response_height = 16'd480;
        capture_writer_busy = 1'b0;
        capture_writer_done = 1'b0;
        capture_writer_error = 1'b0;
        boardless_start_ready = 1'b1;
        boardless_busy = 1'b0;
        boardless_done = 1'b0;
        boardless_error = 1'b0;
        boardless_aborted = 1'b0;
        boardless_error_code = 8'd0;
        boardless_error_address = 32'd0;
        boardless_resolved_input_base = 32'h0010_0000;
        boardless_resolved_input_stride = 32'd2560;
        boardless_resolved_input_width = 16'd640;
        boardless_resolved_input_height = 16'd480;
        boardless_resolved_output_base = 32'h0020_0000;
        boardless_resolved_output_stride = 32'd2560;
        boardless_resolved_output_width = 16'd640;
        boardless_resolved_output_height = 16'd480;
        display_frame_start_event = 1'b0;
        display_prefetch_start_ready = 1'b1;
        display_prefetch_busy = 1'b0;
        display_prefetch_done = 1'b0;
        display_prefetch_aborted = 1'b0;
        display_prefetch_error = 1'b0;
        display_prefetch_primed = 1'b0;
        display_flush_busy = 1'b0;

        tick(5);
        rst = 1'b0;
        tick(3);
        capture_cleanup_busy = 1'b1;
        tick(1);
        if (status_busy)
            $fatal(1, "background camera discard incorrectly asserted BUSY");
        capture_cleanup_busy = 1'b0;
        system_enable = 1'b1;
        pulse_start();

        wait (parameter_start_valid);
        $display("SOC_STEP parameter_start t=%0t", $time);
        if (parameter_base_addr != 32'h0004_0000)
            $fatal(1, "parameter snapshot mismatch");
        @(negedge clk);
        parameter_busy = 1'b1;
        tick(3);
        @(negedge clk);
        parameter_busy = 1'b0;
        parameter_active_valid = 1'b1;
        parameter_generation = 32'd1;
        parameter_done = 1'b1;
        @(negedge clk);
        parameter_done = 1'b0;

        capture_frame_waiting = 1'b1;
        wait (capture_table_request_valid);
        $display("SOC_STEP capture_table_request t=%0t", $time);
        @(negedge clk);
        capture_table_response_valid = 1'b1;
        @(posedge clk);
        while (!capture_table_response_ready)
            @(posedge clk);
        $display("SOC_STEP capture_table_response t=%0t", $time);
        @(negedge clk);
        capture_table_response_valid = 1'b0;
        wait (capture_begin_frame);
        $display("SOC_STEP capture_begin t=%0t", $time);
        if (!capture_writer_start ||
            capture_writer_base != 32'h0010_0000)
            $fatal(1, "capture writer did not start atomically");
        capture_frame_waiting = 1'b0;
        capture_writer_busy = 1'b1;
        tick(3);
        @(negedge clk);
        capture_ingress_done = 1'b1;
        @(negedge clk);
        capture_ingress_done = 1'b0;
        tick(2);
        @(negedge clk);
        capture_writer_busy = 1'b0;
        capture_writer_done = 1'b1;
        @(negedge clk);
        capture_writer_done = 1'b0;

        wait (boardless_start_valid);
        $display("SOC_STEP boardless_start t=%0t", $time);
        tensor_base_addr = 32'h0400_0000;
        if (boardless_input_table_base != input_table_base ||
            boardless_output_table_base != output_table_base ||
            boardless_descriptor_count != 22 ||
            boardless_tensor_base_addr != 32'h0200_0000)
            $fatal(1, "boardless command snapshot mismatch");
        @(negedge clk);
        boardless_busy = 1'b1;
        tick(5);
        @(negedge clk);
        boardless_busy = 1'b0;
        boardless_done = 1'b1;
        @(negedge clk);
        boardless_done = 1'b0;

        wait (display_prefetch_start_valid);
        $display("SOC_STEP display_prefetch_new t=%0t", $time);
        if (display_original_base != 32'h0010_0000 ||
            display_styled_base != 32'h0020_0000)
            $fatal(1, "display did not use boardless resolved snapshot");
        @(negedge clk);
        display_prefetch_busy = 1'b1;
        display_prefetch_primed = 1'b1;
        tick(3);
        @(negedge clk);
        display_frame_start_event = 1'b1;
        @(negedge clk);
        display_frame_start_event = 1'b0;
        wait (display_swap_event);
        $display("SOC_STEP display_swap t=%0t", $time);
        if (!display_feed_active)
            $fatal(1, "display feed did not become active");

        @(negedge clk);
        display_prefetch_primed = 1'b0;
        display_prefetch_busy = 1'b0;
        display_prefetch_done = 1'b1;
        @(negedge clk);
        display_prefetch_done = 1'b0;
        @(negedge clk);
        display_flush_busy = 1'b1;
        abort_pulse = 1'b1;
        @(posedge clk);
        if (!display_flush_request || !display_prefetch_abort)
            $fatal(1, "abort did not fence display");
        @(negedge clk);
        abort_pulse = 1'b0;

        tick(2);
        if (!status_busy)
            $fatal(1, "abort cleanup was not reflected in BUSY");
        @(negedge clk);
        display_flush_busy = 1'b0;

        tick(5);
        begin : wait_repeat_prefetch
            integer repeat_wait;
            repeat_wait = 0;
            while ((prefetch_launches < 2) && (repeat_wait < 20)) begin
                tick(1);
                repeat_wait = repeat_wait + 1;
            end
            if (prefetch_launches < 2)
                $fatal(1, "background display repeat did not recover after abort");
        end
        $display("SOC_STEP display_repeat t=%0t", $time);
        if (display_original_base != 32'h0010_0000 ||
            display_styled_base != 32'h0020_0000)
            $fatal(1, "repeat pair address mismatch");

        if (capture_requests != 1 || nn_launches != 1 ||
            prefetch_launches < 2 || swaps != 1 || errors != 0)
            $fatal(1, "unexpected lifecycle counts");

        // Directed capture fault.  The legacy path broadcasts immediately;
        // the registered build must capture an atomic code/address ticket,
        // present abort for the following complete cycle, and report exactly
        // once.  The earlier manual-abort check remains common to both modes
        // and proves software cancellation was not delayed.
        wait (!status_busy);
        pulse_start();
        @(negedge clk);
        capture_error_code = 8'h05;
        capture_error = 1'b1;
        #1;
        if (REGISTER_FATAL_TICKET_CFG != 0) begin
            if (capture_abort_frame || boardless_abort || error_event)
                $fatal(1, "registered fatal ticket leaked combinational abort");
        end else if (!capture_abort_frame || !boardless_abort) begin
            $fatal(1, "legacy fatal path did not broadcast immediately");
        end

        @(posedge clk); #1;
        if (REGISTER_FATAL_TICKET_CFG != 0) begin
            if (error_event)
                $fatal(1, "registered fatal ticket reported too early");
        end else if (!error_event || error_code != 8'h45 ||
                     error_address != 32'd0) begin
            $fatal(1, "legacy fatal report payload mismatch");
        end

        @(negedge clk); #1;
        if (REGISTER_FATAL_TICKET_CFG != 0 &&
            (!capture_abort_frame || !boardless_abort ||
             !display_prefetch_abort))
            $fatal(1, "registered fatal ticket did not broadcast for a full cycle");

        @(posedge clk); #1;
        if (REGISTER_FATAL_TICKET_CFG != 0 &&
            (!error_event || error_code != 8'h45 ||
             error_address != 32'd0))
            $fatal(1, "registered fatal report payload mismatch");

        @(negedge clk);
        capture_error = 1'b0;
        capture_error_code = 8'd0;
        tick(3);
        if (errors != 1)
            $fatal(1, "fatal ticket did not report exactly once");

        // A disabled armed transaction must still broadcast cancellation in
        // the same cycle.  This protects the immediate system-disable
        // contract while allowing RTL to qualify it with registered
        // ownership instead of feeding child busy back into the abort tree.
        wait (!status_busy);
        pulse_start();
        #1;
        if (!status_busy)
            $fatal(1, "disable-abort setup did not arm a transaction");
        boardless_busy = 1'b1;
        system_enable = 1'b0;
        #1;
        if (!parameter_abort_request || !capture_abort_frame ||
            !boardless_abort || !display_prefetch_abort)
            $fatal(1, "system disable did not broadcast immediate abort");
        @(posedge clk);
        @(negedge clk);
        boardless_busy = 1'b0;
        system_enable = 1'b1;
        tick(2);

        $display("C1_R1_SOC_CONTROL_PASS capture=%0d nn=%0d prefetch=%0d swaps=%0d repeats=%0d errors=%0d fatal_ticket=%0d disable_abort=1",
                 capture_requests, nn_launches, prefetch_launches,
                 swaps, repeats, errors, REGISTER_FATAL_TICKET_CFG);
        $finish;
    end

    initial begin
        #200000;
        $fatal(1, "soc control timeout");
    end
endmodule
