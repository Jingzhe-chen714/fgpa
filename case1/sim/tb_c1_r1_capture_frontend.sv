`timescale 1ns/1ps

module tb_c1_r1_capture_frontend;
    localparam integer SENSOR_W = 6;
    localparam integer SENSOR_H = 5;
    localparam integer OUT_PIXELS = (SENSOR_W-2)*(SENSOR_H-2);

    logic camera_clk = 1'b0;
    logic core_clk = 1'b0;
    logic camera_rst = 1'b1;
    logic core_rst = 1'b1;
    logic camera_valid;
    logic camera_ready;
    logic [9:0] camera_raw10;
    logic [2:0] camera_x;
    logic [2:0] camera_y;
    logic camera_sof;
    logic camera_eol;
    logic camera_eof;
    logic camera_clear_error;
    logic camera_overflow;

    logic frame_waiting;
    logic begin_frame;
    logic begin_ready;
    logic drop_frame;
    logic discard_idle;
    logic abort_frame;
    logic clear_error;
    logic cleanup_busy;
    logic frame_ingress_done;
    logic frame_dropped;
    logic frame_aborted;
    logic capture_error;
    logic [7:0] capture_error_code;

    logic cfg_commit;
    logic cfg_ready;
    logic gamma_cfg_ready;
    logic m_valid;
    logic m_ready;
    logic [23:0] m_rgb;
    logic m_sof;
    logic m_eol;
    logic m_eof;

    integer output_pixels;
    integer sof_count;
    integer eol_count;
    integer eof_count;
    integer ingress_done_count;
    integer dropped_count;
    integer aborted_count;
    integer frames_sent;
    integer ready_stalls;
    integer cleanup_cycles;
    integer cleanup_entries;
    logic cleanup_busy_q;
    integer core_cycle;

    always #4 camera_clk = ~camera_clk;
    always #5 core_clk = ~core_clk;

    always_ff @(posedge core_clk) begin
        if (core_rst) begin
            core_cycle <= 0;
            m_ready <= 1'b0;
            output_pixels <= 0;
            sof_count <= 0;
            eol_count <= 0;
            eof_count <= 0;
            ingress_done_count <= 0;
            dropped_count <= 0;
            aborted_count <= 0;
            ready_stalls <= 0;
            cleanup_cycles <= 0;
            cleanup_entries <= 0;
            cleanup_busy_q <= 1'b0;
        end else begin
            core_cycle <= core_cycle + 1;
            m_ready <= ((core_cycle % 5) != 2);
            if (m_valid && !m_ready)
                ready_stalls <= ready_stalls + 1;
            if (m_valid && m_ready) begin
                output_pixels <= output_pixels + 1;
                if (m_sof) sof_count <= sof_count + 1;
                if (m_eol) eol_count <= eol_count + 1;
                if (m_eof) eof_count <= eof_count + 1;
            end
            if (frame_ingress_done)
                ingress_done_count <= ingress_done_count + 1;
            if (frame_dropped)
                dropped_count <= dropped_count + 1;
            if (frame_aborted)
                aborted_count <= aborted_count + 1;
            if (cleanup_busy)
                cleanup_cycles <= cleanup_cycles + 1;
            if (cleanup_busy && !cleanup_busy_q)
                cleanup_entries <= cleanup_entries + 1;
            cleanup_busy_q <= cleanup_busy;
        end
    end

    c1_r1_capture_frontend #(
        .SENSOR_WIDTH(SENSOR_W), .SENSOR_HEIGHT(SENSOR_H),
        .CAMERA_FIFO_DEPTH(64), .OUTPUT_FIFO_DEPTH(32),
        .PIPELINE_HEADROOM(12), .X_BITS(3), .Y_BITS(3)
    ) dut (
        .camera_clk(camera_clk), .camera_rst(camera_rst),
        .camera_valid(camera_valid), .camera_ready(camera_ready),
        .camera_raw10(camera_raw10), .camera_x(camera_x), .camera_y(camera_y),
        .camera_sof(camera_sof), .camera_eol(camera_eol),
        .camera_eof(camera_eof), .camera_clear_error(camera_clear_error),
        .camera_overflow(camera_overflow),
        .core_clk(core_clk), .core_rst(core_rst),
        .frame_waiting(frame_waiting), .begin_frame(begin_frame),
        .begin_ready(begin_ready), .drop_frame(drop_frame),
        .discard_idle(discard_idle), .abort_frame(abort_frame),
        .clear_error(clear_error), .cleanup_busy(cleanup_busy),
        .frame_ingress_done(frame_ingress_done),
        .frame_dropped(frame_dropped), .frame_aborted(frame_aborted),
        .capture_error(capture_error),
        .capture_error_code(capture_error_code),
        .cfg_commit(cfg_commit), .cfg_ready(cfg_ready),
        .cfg_bayer_pattern(2'b00), .cfg_roi_x_parity(1'b0),
        .cfg_roi_y_parity(1'b0), .cfg_black_r(10'd0),
        .cfg_black_gr(10'd0), .cfg_black_gb(10'd0), .cfg_black_b(10'd0),
        .cfg_awb_gain_r(16'd16384), .cfg_awb_gain_g(16'd16384),
        .cfg_awb_gain_b(16'd16384),
        .cfg_ccm_rr(16'sd8192), .cfg_ccm_rg(16'sd0),
        .cfg_ccm_rb(16'sd0), .cfg_ccm_gr(16'sd0),
        .cfg_ccm_gg(16'sd8192), .cfg_ccm_gb(16'sd0),
        .cfg_ccm_br(16'sd0), .cfg_ccm_bg(16'sd0),
        .cfg_ccm_bb(16'sd8192), .cfg_ccm_offset_r(32'sd0),
        .cfg_ccm_offset_g(32'sd0), .cfg_ccm_offset_b(32'sd0),
        .gamma_cfg_we(1'b0), .gamma_cfg_addr(10'd0),
        .gamma_cfg_data(8'd0), .gamma_cfg_ready(gamma_cfg_ready),
        .m_valid(m_valid), .m_ready(m_ready), .m_rgb(m_rgb),
        .m_sof(m_sof), .m_eol(m_eol), .m_eof(m_eof)
    );

    task automatic send_raw_frame(input integer seed);
        integer x;
        integer y;
        logic accepted;
        begin
            for (y = 0; y < SENSOR_H; y = y + 1) begin
                for (x = 0; x < SENSOR_W; x = x + 1) begin
                    @(negedge camera_clk);
                    camera_valid = 1'b1;
                    camera_raw10 = (seed + y*37 + x*11) & 10'h3ff;
                    camera_x = x[2:0];
                    camera_y = y[2:0];
                    camera_sof = (x == 0) && (y == 0);
                    camera_eol = (x == SENSOR_W-1);
                    camera_eof = (x == SENSOR_W-1) && (y == SENSOR_H-1);
                    accepted = 1'b0;
                    while (!accepted) begin
                        @(posedge camera_clk);
                        accepted = camera_ready;
                    end
                end
            end
            @(negedge camera_clk);
            camera_valid = 1'b0;
            camera_sof = 1'b0;
            camera_eol = 1'b0;
            camera_eof = 1'b0;
            frames_sent = frames_sent + 1;
        end
    endtask

    // Deliberately begins without SOF to prove maintenance discard can
    // re-synchronize a FIFO whose head is in the middle of a sensor frame.
    task automatic send_raw_tail(input integer seed);
        integer x;
        integer y;
        logic accepted;
        begin
            for (y = 2; y < SENSOR_H; y = y + 1) begin
                for (x = 0; x < SENSOR_W; x = x + 1) begin
                    @(negedge camera_clk);
                    camera_valid = 1'b1;
                    camera_raw10 = (seed + y*37 + x*11) & 10'h3ff;
                    camera_x = x[2:0];
                    camera_y = y[2:0];
                    camera_sof = 1'b0;
                    camera_eol = (x == SENSOR_W-1);
                    camera_eof = (x == SENSOR_W-1) && (y == SENSOR_H-1);
                    accepted = 1'b0;
                    while (!accepted) begin
                        @(posedge camera_clk);
                        accepted = camera_ready;
                    end
                end
            end
            @(negedge camera_clk);
            camera_valid = 1'b0;
            camera_eol = 1'b0;
            camera_eof = 1'b0;
        end
    endtask

    task automatic pulse_begin;
        begin
            wait (begin_ready);
            @(negedge core_clk);
            begin_frame = 1'b1;
            @(posedge core_clk);
            @(negedge core_clk);
            begin_frame = 1'b0;
        end
    endtask

    task automatic pulse_drop;
        begin
            wait (frame_waiting);
            @(negedge core_clk);
            drop_frame = 1'b1;
            @(posedge core_clk);
            @(negedge core_clk);
            drop_frame = 1'b0;
        end
    endtask

    initial begin
        camera_valid = 1'b0;
        camera_raw10 = '0;
        camera_x = '0;
        camera_y = '0;
        camera_sof = 1'b0;
        camera_eol = 1'b0;
        camera_eof = 1'b0;
        camera_clear_error = 1'b0;
        begin_frame = 1'b0;
        drop_frame = 1'b0;
        discard_idle = 1'b0;
        abort_frame = 1'b0;
        clear_error = 1'b0;
        cfg_commit = 1'b0;
        frames_sent = 0;

        repeat (6) @(posedge camera_clk);
        repeat (6) @(posedge core_clk);
        @(negedge camera_clk);
        camera_rst = 1'b0;
        @(negedge core_clk);
        core_rst = 1'b0;

        wait (cfg_ready);
        @(negedge core_clk);
        cfg_commit = 1'b1;
        @(posedge core_clk);
        @(negedge core_clk);
        cfg_commit = 1'b0;

        // Normal frame: allocation may happen after the complete raw frame is
        // already buffered.  The valid-crop ISP emits exactly 4x3 pixels.
        send_raw_frame(7);
        pulse_begin();
        wait (ingress_done_count >= 1);
        wait (eof_count >= 1);
        if ((output_pixels != OUT_PIXELS) || (sof_count != 1) ||
            (eol_count != SENSOR_H-2) || (eof_count != 1))
            $fatal(1, "capture normal-frame geometry mismatch pixels=%0d sof=%0d eol=%0d eof=%0d",
                   output_pixels, sof_count, eol_count, eof_count);

        // Drop a complete queued frame before enabling the ISP.
        send_raw_frame(101);
        pulse_drop();
        wait (dropped_count >= 1);
        repeat (40) @(posedge core_clk);
        if (output_pixels != OUT_PIXELS)
            $fatal(1, "dropped raw frame leaked RGB pixels");

        // Maintenance discard consumes a complete queued frame without an
        // output beat, capture error, or software-visible drop notification.
        begin : silent_discard_checks
            integer output_before;
            integer drops_before;
            integer cleanups_before;
            output_before = output_pixels;
            drops_before = dropped_count;
            cleanups_before = cleanup_entries;
            @(negedge core_clk);
            discard_idle = 1'b1;
            fork
                send_raw_frame(151);
                begin
                    wait (cleanup_busy);
                    wait (!cleanup_busy);
                end
            join
            repeat (4) @(posedge core_clk);
            if ((output_pixels != output_before) ||
                (dropped_count != drops_before) || capture_error ||
                (cleanup_entries != cleanups_before + 1))
                $fatal(1, "silent full-frame discard was not silent/complete");

            // Repeat from a non-SOF FIFO head and clear a pre-existing local
            // command error while cleanup is active.  Cleanup must still run
            // through EOF and leave the frontend restartable.
            @(negedge core_clk);
            discard_idle = 1'b0;
            begin_frame = 1'b1;
            @(posedge core_clk);
            @(negedge core_clk);
            begin_frame = 1'b0;
            wait (capture_error && (capture_error_code == 8'h04));

            discard_idle = 1'b1;
            fork
                send_raw_tail(181);
                begin
                    wait (cleanup_busy);
                    @(negedge core_clk);
                    clear_error = 1'b1;
                    @(posedge core_clk);
                    @(negedge core_clk);
                    clear_error = 1'b0;
                    wait (!cleanup_busy);
                end
            join
            repeat (4) @(posedge core_clk);
            discard_idle = 1'b0;
            if (capture_error || (output_pixels != output_before) ||
                (dropped_count != drops_before) ||
                (cleanup_entries != cleanups_before + 2))
                $fatal(1, "mid-frame discard/clear did not recover silently");
        end

        // Hold abort as a level after streaming starts.  Cleanup must drain to
        // EOF, pulse aborted exactly once, then accept a restart without reset.
        send_raw_frame(203);
        pulse_begin();
        repeat (8) @(posedge core_clk);
        @(negedge core_clk);
        abort_frame = 1'b1;
        repeat (12) @(posedge core_clk);
        @(negedge core_clk);
        abort_frame = 1'b0;
        wait (aborted_count >= 1);
        wait (!cleanup_busy);
        repeat (8) @(posedge core_clk);
        if (aborted_count != 1)
            $fatal(1, "level abort produced %0d aborted pulses", aborted_count);

        send_raw_frame(307);
        pulse_begin();
        wait (ingress_done_count >= 2);
        wait (eof_count >= 2);

        if (camera_overflow || capture_error)
            $fatal(1, "capture frontend ended with error code=%02x", capture_error_code);
        $display("C1_CAPTURE_FRONTEND_PASS frames=%0d ingress=%0d dropped=%0d aborted=%0d output=%0d stalls=%0d cleanup_entries=%0d cleanup_cycles=%0d",
                 frames_sent, ingress_done_count, dropped_count,
                 aborted_count, output_pixels, ready_stalls,
                 cleanup_entries, cleanup_cycles);
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "capture frontend test timeout");
    end
endmodule
