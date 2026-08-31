`timescale 1ns/1ps

module tb_c1_r1_microstyle_engine;
`ifdef C1_PIPELINED_DOT_TREE
    localparam integer PIPELINED_DOT_TREE = 1;
`else
    localparam integer PIPELINED_DOT_TREE = 0;
`endif
`ifdef C1_PIPELINED_DOT_TREE_FULL
    localparam integer PIPELINED_DOT_TREE_FULL = 1;
`else
    localparam integer PIPELINED_DOT_TREE_FULL = 0;
`endif
`ifdef C1_CACHE_DW_WEIGHT_TILES
    localparam integer CACHE_DW_WEIGHT_TILES = 1;
`else
    localparam integer CACHE_DW_WEIGHT_TILES = 0;
`endif
`ifdef C1_MAC_PREFETCH_OVERLAP
    localparam integer MAC_PREFETCH_OVERLAP = 1;
`else
    localparam integer MAC_PREFETCH_OVERLAP = 0;
`endif
`ifdef C1_PACKED_AFFINE_CACHE
    localparam integer PACKED_AFFINE_CACHE = 1;
`else
    localparam integer PACKED_AFFINE_CACHE = 0;
`endif
`ifdef C1_PIPELINED_DECODER_VALIDATION
    localparam integer PIPELINED_DECODER_VALIDATION = 1;
`else
    localparam integer PIPELINED_DECODER_VALIDATION = 0;
`endif
`ifdef C1_NONZERO_CYCLE_BUDGET
    localparam logic [31:0] TEST_CYCLE_BUDGET = 32'd10000;
`else
    localparam logic [31:0] TEST_CYCLE_BUDGET = 32'd0;
`endif
    localparam integer PARAM_BYTES = 16896;
    localparam integer PARAM_ADDR_W = 11;
    localparam integer STAGES = 22;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    logic rst, abort;
    logic job_start_valid, job_start_ready;
    logic [15:0] job_stage_count;
    logic [7:0] config_generation;
    logic parameter_active_valid;
    logic [31:0] parameter_generation;
    logic busy, done, aborted, error;
    logic [7:0] error_code;

    logic stage_config_valid, stage_config_ready;
    logic [15:0] stage_config_index;
    logic [511:0] stage_config_descriptor;
    logic [7:0] stage_config_generation;

    logic param_rd_en;
    logic [PARAM_ADDR_W-1:0] param_rd_addr;
    logic param_rd_valid, param_rd_error;
    logic [127:0] param_rd_data;

    logic in_valid, in_ready;
    logic [575:0] in_window_s8;
    logic [63:0] in_residual_s8;
    logic [2:0] in_group_index;
    logic in_group_last;
    logic [15:0] in_x, in_y;
    logic in_sof, in_eol, in_eof;

    logic out_valid, out_ready;
    logic [63:0] out_data_s8;
    logic [2:0] out_group_index;
    logic out_group_last;
    logic [15:0] out_x, out_y;
    logic out_sof, out_eol, out_eof;
    logic [4:0] stage_index;
    logic [7:0] stage_opcode;
    logic stage_active, adapter_required, stage_done, overflow_seen;
    logic config_capture_complete;

    logic [511:0] descriptors [0:STAGES-1];
    logic [7:0] parameter_bytes [0:PARAM_BYTES-1];
    integer stage_ow [0:STAGES-1];
    integer stage_oh [0:STAGES-1];
    integer stage_cin [0:STAGES-1];
    integer stage_cout [0:STAGES-1];
    integer stage_op [0:STAGES-1];
    integer stage_act [0:STAGES-1];
    integer observed_outputs [0:STAGES-1];

    integer parameter_read_count;
    integer output_count;
    integer mac_output_count;
    integer dw_output_count;
    integer bypass_output_count;
    integer stage_done_count;
    integer abort_count;
    integer injected_fault_count;
    integer output_stall_count;
    integer cycle_count;
    integer pending_delay;
    integer pending_addr;
    integer first_run_start_cycle;
    integer first_run_cycles;
    logic parameter_pending;
    logic inject_param_error_once;

    c1_r1_microstyle_cnn_top #(
        .REQUIRED_STAGES(STAGES),
        .PARAM_ADDR_W(PARAM_ADDR_W),
        .PARAM_ARENA_BYTES(PARAM_BYTES),
        .MAX_CHANNELS(48),
        .MAX_WEIGHT_BYTES(2592),
        .PIPELINED_DOT_TREE(PIPELINED_DOT_TREE),
        .PIPELINED_DOT_TREE_FULL(PIPELINED_DOT_TREE_FULL),
        .PIPELINED_DECODER_VALIDATION(PIPELINED_DECODER_VALIDATION),
        .CACHE_DW_WEIGHT_TILES(CACHE_DW_WEIGHT_TILES),
        .MAC_PREFETCH_OVERLAP(MAC_PREFETCH_OVERLAP),
        .PACKED_AFFINE_CACHE(PACKED_AFFINE_CACHE)
    ) dut (
        .clk, .rst, .abort,
        .start_valid(job_start_valid), .start_ready(job_start_ready),
        .stage_count(job_stage_count),
        .config_generation, .parameter_active_valid,
        .parameter_generation, .busy, .done, .aborted, .error,
        .error_code,
        .stage_config_valid, .stage_config_ready,
        .stage_config_index, .stage_config_descriptor,
        .stage_config_generation,
        .param_rd_en, .param_rd_addr, .param_rd_valid,
        .param_rd_error, .param_rd_data,
        .in_valid, .in_ready, .in_window_s8, .in_residual_s8,
        .in_group_index, .in_group_last, .in_x, .in_y,
        .in_sof, .in_eol, .in_eof,
        .out_valid, .out_ready, .out_data_s8, .out_group_index,
        .out_group_last, .out_x, .out_y, .out_sof, .out_eol,
        .out_eof, .stage_index, .stage_opcode, .stage_active,
        .adapter_required, .stage_done, .overflow_seen,
        .config_capture_complete
    );

    function automatic integer align16(input integer value);
        align16 = (value + 15) & ~15;
    endfunction

    function automatic integer align64(input integer value);
        align64 = (value + 63) & ~63;
    endfunction

    function automatic integer layer_weight_bytes(
        input integer op,
        input integer cin,
        input integer cout
    );
        begin
            case (op)
                1: layer_weight_bytes = cin * cout * 9;
                2: layer_weight_bytes = cin * cout;
                3: layer_weight_bytes = cin * 9;
                default: layer_weight_bytes = 0;
            endcase
        end
    endfunction

    function automatic logic signed [7:0] input_value(
        input integer si,
        input integer px,
        input integer py,
        input integer channel
    );
        integer value;
        begin
            value = ((si * 3 + px + py + channel) % 31) - 15;
            input_value = value;
        end
    endfunction

    function automatic logic [7:0] residual_expected(
        input logic signed [7:0] value
    );
        integer sum;
        begin
            sum = value + 1;
            if (sum < 0)
                sum = 0;
            else if (sum > 127)
                sum = 127;
            residual_expected = sum[7:0];
        end
    endfunction

    function automatic logic [7:0] mac_expected(
        input integer si,
        input integer px,
        input integer py,
        input integer channel
    );
        integer value;
        begin
            value = si + channel + 1;
            if (((si == 0) && (channel == 0)) ||
                (si == 18) || (si == 19) || (si == 20))
                value = value + $signed(input_value(si, px, py, channel));
            if (value > 127)
                value = 127;
            else if (value < -128)
                value = -128;
            if ((stage_act[si] == 1) && (value < 0))
                value = 0;
            mac_expected = value[7:0];
        end
    endfunction

    task automatic put_u32(input integer address, input integer value);
        begin
            parameter_bytes[address + 0] = value[7:0];
            parameter_bytes[address + 1] = value[15:8];
            parameter_bytes[address + 2] = value[23:16];
            parameter_bytes[address + 3] = value[31:24];
        end
    endtask

    task automatic set_stage_shape(
        input integer si,
        input integer op,
        input integer iw,
        input integer ih,
        input integer ow,
        input integer oh,
        input integer cin,
        input integer cout,
        input integer act
    );
        begin
            stage_op[si] = op;
            stage_ow[si] = ow;
            stage_oh[si] = oh;
            stage_cin[si] = cin;
            stage_cout[si] = cout;
            stage_act[si] = act;
            descriptors[si] = '0;
            descriptors[si][7:0] = op;
            descriptors[si][9:8] = act;
            descriptors[si][23:16] = 8'd1;
            descriptors[si][31:24] = 8'd16;
            descriptors[si][47:32] = iw;
            descriptors[si][63:48] = ih;
            descriptors[si][79:64] = ow;
            descriptors[si][95:80] = oh;
            descriptors[si][111:96] = cin;
            descriptors[si][127:112] = cout;
            descriptors[si][455:448] = 8'd8;
            descriptors[si][463:456] = 8'd1;
            descriptors[si][471:464] = 8'd1;
            descriptors[si][479:472] = 8'd1;
            if ((op == 1) || (op == 3)) begin
                descriptors[si][423:416] = 8'd3;
                descriptors[si][431:424] = 8'd3;
                descriptors[si][10] = 1'b1;
            end else begin
                descriptors[si][423:416] = 8'd1;
                descriptors[si][431:424] = 8'd1;
            end
            if ((si == 0) || (si == 1)) begin
                descriptors[si][439:432] = 8'd2;
                descriptors[si][447:440] = 8'd2;
            end else if (op == 4) begin
                descriptors[si][439:432] = 8'd2;
                descriptors[si][447:440] = 8'd2;
            end else begin
                descriptors[si][439:432] = 8'd1;
                descriptors[si][447:440] = 8'd1;
            end
            if (op == 5)
                descriptors[si][11] = 1'b1;
            if (si == 0)
                descriptors[si][12] = 1'b1;
            if (si == STAGES-1)
                descriptors[si][13] = 1'b1;
            // Optional margin gate: stage 18 is the largest legal MAC/DW
            // shape in this TB.  A finite budget exercises the engine's
            // cycle-budget comparator without changing the default test.
            if ((TEST_CYCLE_BUDGET != 0) && (si == 18))
                descriptors[si][511:480] = TEST_CYCLE_BUDGET;
        end
    endtask

    task automatic build_layout;
        integer i, j, cursor, weight_count;
        integer weight_offset, bias_offset, mult_offset, shift_offset;
        begin
            for (i = 0; i < PARAM_BYTES; i = i + 1)
                parameter_bytes[i] = 8'd0;
            for (i = 0; i < STAGES; i = i + 1) begin
                descriptors[i] = '0;
                observed_outputs[i] = 0;
            end

            set_stage_shape(0, 1, 8, 8, 4, 4, 3, 12, 1);
            set_stage_shape(1, 1, 4, 4, 2, 2, 12, 24, 1);
            set_stage_shape(2, 2, 2, 2, 2, 2, 24, 48, 1);
            set_stage_shape(3, 3, 2, 2, 2, 2, 48, 48, 1);
            set_stage_shape(4, 2, 2, 2, 2, 2, 48, 24, 0);
            set_stage_shape(5, 5, 2, 2, 2, 2, 24, 24, 1);
            set_stage_shape(6, 2, 2, 2, 2, 2, 24, 48, 1);
            set_stage_shape(7, 3, 2, 2, 2, 2, 48, 48, 1);
            set_stage_shape(8, 2, 2, 2, 2, 2, 48, 24, 0);
            set_stage_shape(9, 5, 2, 2, 2, 2, 24, 24, 1);
            set_stage_shape(10, 2, 2, 2, 2, 2, 24, 48, 1);
            set_stage_shape(11, 3, 2, 2, 2, 2, 48, 48, 1);
            set_stage_shape(12, 2, 2, 2, 2, 2, 48, 24, 0);
            set_stage_shape(13, 5, 2, 2, 2, 2, 24, 24, 1);
            set_stage_shape(14, 4, 2, 2, 4, 4, 24, 24, 0);
            set_stage_shape(15, 3, 4, 4, 4, 4, 24, 24, 1);
            set_stage_shape(16, 2, 4, 4, 4, 4, 24, 16, 1);
            set_stage_shape(17, 4, 4, 4, 8, 8, 16, 16, 0);
            set_stage_shape(18, 3, 8, 8, 8, 8, 16, 16, 1);
            set_stage_shape(19, 2, 8, 8, 8, 8, 16, 8, 1);
            set_stage_shape(20, 1, 8, 8, 8, 8, 8, 3, 0);
            set_stage_shape(21, 6, 8, 8, 8, 8, 3, 3, 0);

            cursor = 0;
            for (i = 0; i < STAGES; i = i + 1) begin
                weight_count = layer_weight_bytes(
                    stage_op[i], stage_cin[i], stage_cout[i]);
                if (weight_count != 0) begin
                    cursor = align64(cursor);
                    weight_offset = cursor;
                    if (i == 0)
                        parameter_bytes[weight_offset + 4] = 8'd1;
                    if (i == 18)
                        for (j = 0; j < stage_cout[i]; j = j + 1)
                            parameter_bytes[weight_offset + j*9 + 4] = 8'd1;
                    if (i == 19)
                        for (j = 0; j < stage_cout[i]; j = j + 1)
                            parameter_bytes[weight_offset + j*stage_cin[i] + j] = 8'd1;
                    if (i == 20)
                        for (j = 0; j < stage_cout[i]; j = j + 1)
                            parameter_bytes[weight_offset +
                                            (j*stage_cin[i] + j)*9 + 4] = 8'd1;
                    cursor = cursor + weight_count;
                    cursor = align16(cursor);
                    bias_offset = cursor;
                    for (j = 0; j < stage_cout[i]; j = j + 1)
                        put_u32(cursor + j*4, i + j + 1);
                    cursor = align16(cursor + stage_cout[i]*4);
                    mult_offset = cursor;
                    for (j = 0; j < stage_cout[i]; j = j + 1)
                        put_u32(cursor + j*4, 1);
                    cursor = align16(cursor + stage_cout[i]*4);
                    shift_offset = cursor;
                    for (j = 0; j < stage_cout[i]; j = j + 1)
                        parameter_bytes[cursor + j] = 8'd0;
                    cursor = align16(cursor + stage_cout[i]);

                    descriptors[i][255:224] = weight_offset;
                    descriptors[i][287:256] = bias_offset;
                    descriptors[i][319:288] = mult_offset;
                    descriptors[i][351:320] = shift_offset;
                end
            end
            if (cursor > PARAM_BYTES)
                $fatal(1, "test parameter layout overflowed arena: %0d", cursor);
        end
    endtask

    task automatic pulse_job_start;
        begin
            @(negedge clk);
            job_start_valid = 1'b1;
            while (!job_start_ready)
                @(negedge clk);
            @(negedge clk);
            job_start_valid = 1'b0;
        end
    endtask

    task automatic send_descriptor(
        input integer index,
        input logic [511:0] value
    );
        begin
            @(negedge clk);
            stage_config_index = index;
            stage_config_descriptor = value;
            stage_config_generation = config_generation;
            stage_config_valid = 1'b1;
            while (!stage_config_ready)
                @(negedge clk);
            @(negedge clk);
            stage_config_valid = 1'b0;
        end
    endtask

    task automatic send_input_group(
        input integer si,
        input integer px,
        input integer py,
        input integer group_index,
        input bit corrupt_group
    );
        logic [575:0] window_value;
        logic [63:0] residual_value;
        logic signed [7:0] lane_value;
        integer tap, lane, global_channel;
        begin
            window_value = '0;
            residual_value = '0;
            for (tap = 0; tap < 9; tap = tap + 1) begin
                for (lane = 0; lane < 8; lane = lane + 1) begin
                    global_channel = group_index * 8 + lane;
                    if (global_channel < stage_cin[si])
                        lane_value = input_value(si, px, py, global_channel);
                    else
                        lane_value = 8'sd0;
                    window_value[(tap*8 + lane)*8 +: 8] = lane_value;
                end
            end
            for (lane = 0; lane < 8; lane = lane + 1)
                residual_value[lane*8 +: 8] = 8'sd1;

            @(negedge clk);
            in_window_s8 = window_value;
            in_residual_s8 = residual_value;
            in_group_index = corrupt_group ? group_index + 1 : group_index;
            in_group_last =
                (group_index == ((stage_cin[si] + 7) / 8) - 1);
            in_x = px;
            in_y = py;
            in_sof = (px == 0) && (py == 0);
            in_eol = (px == stage_ow[si] - 1);
            in_eof = in_eol && (py == stage_oh[si] - 1);
            in_valid = 1'b1;
            while (!in_ready)
                @(negedge clk);
            @(negedge clk);
            in_valid = 1'b0;
        end
    endtask

    task automatic run_stage(input integer si);
        integer px, py, group_index, input_groups;
        begin
            while (!stage_active) begin
                if (error)
                    $fatal(1, "engine rejected legal stage %0d code=%0h",
                           si, error_code);
                @(negedge clk);
            end
            if (!adapter_required)
                $fatal(1, "stage %0d did not advertise tensor adapter contract", si);
            input_groups = (stage_cin[si] + 7) / 8;
            for (py = 0; py < stage_oh[si]; py = py + 1)
                for (px = 0; px < stage_ow[si]; px = px + 1)
                    for (group_index = 0; group_index < input_groups;
                         group_index = group_index + 1)
                        send_input_group(si, px, py, group_index, 1'b0);
            while (!stage_done) begin
                if (error)
                    $fatal(1, "engine faulted in legal stage %0d code=%0h",
                           si, error_code);
                @(negedge clk);
            end
        end
    endtask

    always @(posedge clk) begin
        param_rd_valid <= 1'b0;
        param_rd_error <= 1'b0;
        if (rst || abort) begin
            parameter_pending <= 1'b0;
            pending_delay <= 0;
            pending_addr <= 0;
            param_rd_data <= '0;
        end else begin
            if (param_rd_en) begin
                if (parameter_pending)
                    $fatal(1, "engine issued a second parameter read");
                parameter_pending <= 1'b1;
                pending_addr <= param_rd_addr;
                pending_delay <= (parameter_read_count % 3) + 1;
                parameter_read_count <= parameter_read_count + 1;
            end
            if (parameter_pending) begin
                if (pending_delay == 0) begin
                    if (inject_param_error_once) begin
                        param_rd_error <= 1'b1;
                        inject_param_error_once <= 1'b0;
                    end else begin
                        for (integer byte_lane = 0; byte_lane < 16;
                             byte_lane = byte_lane + 1)
                            param_rd_data[byte_lane*8 +: 8] <=
                                parameter_bytes[pending_addr*16 + byte_lane];
                        param_rd_valid <= 1'b1;
                    end
                    parameter_pending <= 1'b0;
                end else begin
                    pending_delay <= pending_delay - 1;
                end
            end
        end
    end

    always @(posedge clk) begin
        cycle_count <= cycle_count + 1;
        out_ready <= ((cycle_count % 7) != 2) &&
                     ((cycle_count % 11) != 5);
        if (out_valid && !out_ready)
            output_stall_count <= output_stall_count + 1;

        if (out_valid && out_ready) begin
            integer lane;
            integer global_channel;
            logic [7:0] expected_value;
            logic signed [7:0] source_value;
            output_count <= output_count + 1;
            observed_outputs[stage_index] <=
                observed_outputs[stage_index] + 1;
            if ((stage_opcode == 1) || (stage_opcode == 2))
                mac_output_count <= mac_output_count + 1;
            else if (stage_opcode == 3)
                dw_output_count <= dw_output_count + 1;
            else
                bypass_output_count <= bypass_output_count + 1;

            if ((out_x >= stage_ow[stage_index]) ||
                (out_y >= stage_oh[stage_index]))
                $fatal(1, "output coordinate out of range stage=%0d", stage_index);
            if (out_group_last !=
                (out_group_index == ((stage_cout[stage_index] + 7) / 8) - 1))
                $fatal(1, "output group-last mismatch stage=%0d", stage_index);
            if (out_sof != ((out_x == 0) && (out_y == 0) &&
                           (out_group_index == 0)))
                $fatal(1, "output SOF mismatch stage=%0d", stage_index);
            if (out_eol != ((out_x == stage_ow[stage_index]-1) &&
                           out_group_last))
                $fatal(1, "output EOL mismatch stage=%0d", stage_index);
            if (out_eof != ((out_x == stage_ow[stage_index]-1) &&
                           (out_y == stage_oh[stage_index]-1) &&
                           out_group_last))
                $fatal(1, "output EOF mismatch stage=%0d", stage_index);

            for (lane = 0; lane < 8; lane = lane + 1) begin
                global_channel = out_group_index * 8 + lane;
                if (global_channel >= stage_cout[stage_index]) begin
                    expected_value = 8'd0;
                end else if ((stage_opcode == 1) ||
                             (stage_opcode == 2) ||
                             (stage_opcode == 3)) begin
                    expected_value = mac_expected(
                        stage_index, out_x, out_y, global_channel);
                end else begin
                    source_value = input_value(
                        stage_index, out_x, out_y, global_channel);
                    if (stage_opcode == 5)
                        expected_value = residual_expected(source_value);
                    else
                        expected_value = source_value;
                end
                if (out_data_s8[lane*8 +: 8] !== expected_value)
                    $fatal(1,
                           "data mismatch stage=%0d xy=%0d,%0d group=%0d lane=%0d got=%0d expected=%0d",
                           stage_index, out_x, out_y, out_group_index, lane,
                           $signed(out_data_s8[lane*8 +: 8]),
                           $signed(expected_value));
            end
        end
        if (stage_done)
            stage_done_count <= stage_done_count + 1;
        if (overflow_seen)
            $fatal(1, "unexpected accumulator overflow");
    end

    initial begin : main_test
        integer i;
        logic [511:0] bad_descriptor;
        rst = 1'b1;
        abort = 1'b0;
        job_start_valid = 1'b0;
        job_stage_count = STAGES;
        config_generation = 8'd7;
        parameter_active_valid = 1'b1;
        parameter_generation = 32'd9;
        stage_config_valid = 1'b0;
        stage_config_index = 16'd0;
        stage_config_descriptor = '0;
        stage_config_generation = 8'd0;
        in_valid = 1'b0;
        in_window_s8 = '0;
        in_residual_s8 = '0;
        in_group_index = '0;
        in_group_last = 1'b0;
        in_x = '0;
        in_y = '0;
        in_sof = 1'b0;
        in_eol = 1'b0;
        in_eof = 1'b0;
        param_rd_valid = 1'b0;
        param_rd_error = 1'b0;
        param_rd_data = '0;
        parameter_pending = 1'b0;
        inject_param_error_once = 1'b0;
        parameter_read_count = 0;
        output_count = 0;
        mac_output_count = 0;
        dw_output_count = 0;
        bypass_output_count = 0;
        stage_done_count = 0;
        abort_count = 0;
        injected_fault_count = 0;
        output_stall_count = 0;
        cycle_count = 0;
        out_ready = 1'b0;

        build_layout();
        repeat (8) @(negedge clk);
        rst = 1'b0;

        first_run_start_cycle = cycle_count;
        pulse_job_start();
        for (i = 0; i < STAGES; i = i + 1)
            send_descriptor(i, descriptors[i]);
        for (i = 0; i < STAGES; i = i + 1)
            run_stage(i);
        while (!done)
            @(negedge clk);
        first_run_cycles = cycle_count - first_run_start_cycle;
        repeat (2) @(negedge clk);
        if (stage_done_count != STAGES)
            $fatal(1, "stage completion count mismatch got=%0d", stage_done_count);
        for (i = 0; i < STAGES; i = i + 1)
            if (observed_outputs[i] !=
                stage_ow[i] * stage_oh[i] * ((stage_cout[i] + 7) / 8))
                $fatal(1, "stage %0d output count mismatch got=%0d", i,
                       observed_outputs[i]);

        // Abort while the first stage is loading parameters, then restart.
        pulse_job_start();
        for (i = 0; i < STAGES; i = i + 1)
            send_descriptor(i, descriptors[i]);
        repeat (5) @(negedge clk);
        abort = 1'b1;
        @(negedge clk);
        abort = 1'b0;
        abort_count = abort_count + 1;
        @(negedge clk);
        if (!job_start_ready || error)
            $fatal(1, "engine did not recover from parameter-load abort");

        // Abort after the linear ABI weights have entered the sequential
        // lane-bank repack phase.  This specifically covers the new local
        // prefetch/repack machinery rather than only the parameter reader.
        pulse_job_start();
        for (i = 0; i < STAGES; i = i + 1)
            send_descriptor(i, descriptors[i]);
        while (dut.u_engine.repack_linear_index_q < 16)
            @(negedge clk);
        if (!stage_active || in_ready)
            $fatal(1, "unexpected interface state during weight repack");
        abort = 1'b1;
        @(negedge clk);
        abort = 1'b0;
        abort_count = abort_count + 1;
        @(negedge clk);
        if (!job_start_ready || busy || error || out_valid || param_rd_en)
            $fatal(1, "engine did not quiesce after weight-repack abort");

        // Live parameter generation is part of the atomic job snapshot.
        pulse_job_start();
        parameter_generation = 32'd10;
        while (!error)
            @(negedge clk);
        if (error_code != 8'he3)
            $fatal(1, "wrong parameter-generation fault code %0h", error_code);
        injected_fault_count = injected_fault_count + 1;
        abort = 1'b1;
        @(negedge clk);
        abort = 1'b0;
        parameter_generation = 32'd9;
        abort_count = abort_count + 1;

        // A descriptor may be ABI-legal but not the frozen MicroStyle graph.
        pulse_job_start();
        bad_descriptor = descriptors[0];
        bad_descriptor[111:96] = 16'd4;
        send_descriptor(0, bad_descriptor);
        for (i = 1; i < STAGES; i = i + 1)
            send_descriptor(i, descriptors[i]);
        while (!error)
            @(negedge clk);
        if (error_code != 8'h02)
            $fatal(1, "wrong topology fault code %0h", error_code);
        injected_fault_count = injected_fault_count + 1;
        abort = 1'b1;
        @(negedge clk);
        abort = 1'b0;
        abort_count = abort_count + 1;

        // Input C8 groups must be strictly ordered for every output site.
        pulse_job_start();
        for (i = 0; i < STAGES; i = i + 1)
            send_descriptor(i, descriptors[i]);
        while (!stage_active)
            @(negedge clk);
        send_input_group(0, 0, 0, 0, 1'b1);
        while (!error)
            @(negedge clk);
        if (error_code != 8'h07)
            $fatal(1, "wrong input-protocol fault code %0h", error_code);
        injected_fault_count = injected_fault_count + 1;
        abort = 1'b1;
        @(negedge clk);
        abort = 1'b0;
        abort_count = abort_count + 1;

        // Dispatcher-facing capture must be strictly ordered 0..21.
        pulse_job_start();
        send_descriptor(1, descriptors[0]);
        while (!error)
            @(negedge clk);
        if (error_code != 8'he1)
            $fatal(1, "wrong config-order fault code %0h", error_code);
        injected_fault_count = injected_fault_count + 1;
        abort = 1'b1;
        @(negedge clk);
        abort = 1'b0;
        abort_count = abort_count + 1;

        // A parameter-bank read fault tears down the active layer snapshot.
        pulse_job_start();
        for (i = 0; i < STAGES; i = i + 1)
            send_descriptor(i, descriptors[i]);
        inject_param_error_once = 1'b1;
        while (!error)
            @(negedge clk);
        if (error_code != 8'h57)
            $fatal(1, "wrong parameter-read fault code %0h", error_code);
        injected_fault_count = injected_fault_count + 1;
        abort = 1'b1;
        @(negedge clk);
        abort = 1'b0;
        abort_count = abort_count + 1;

        // Exported u6 shifts are checked after the affine cache is filled.
        parameter_bytes[descriptors[0][351:320]] = 8'd48;
        pulse_job_start();
        for (i = 0; i < STAGES; i = i + 1)
            send_descriptor(i, descriptors[i]);
        while (!error)
            @(negedge clk);
        if (error_code != 8'h06)
            $fatal(1, "wrong affine-format fault code %0h", error_code);
        parameter_bytes[descriptors[0][351:320]] = 8'd0;
        injected_fault_count = injected_fault_count + 1;
        abort = 1'b1;
        @(negedge clk);
        abort = 1'b0;
        abort_count = abort_count + 1;

        repeat (5) @(negedge clk);
        $display("C1_R1_MICROSTYLE_ENGINE_PASS stages=%0d outputs=%0d mac=%0d dw=%0d bypass=%0d param_reads=%0d stalls=%0d aborts=%0d faults=%0d cache_dw=%0d mac_overlap=%0d first_run_cycles=%0d",
                 stage_done_count, output_count, mac_output_count,
                 dw_output_count, bypass_output_count,
                 parameter_read_count, output_stall_count,
                 abort_count, injected_fault_count,
                 CACHE_DW_WEIGHT_TILES, MAC_PREFETCH_OVERLAP,
                 first_run_cycles);
        $finish;
    end

    initial begin
        repeat (1500000) @(posedge clk);
        $fatal(1, "MicroStyle engine test timeout");
    end

endmodule
