`timescale 1ns/1ps

module tb_c1_r1_microstyle_tensor_adapter;
`ifdef C1_PIPELINED_DESCRIPTOR_VALIDATION
    localparam integer PIPELINED_DESCRIPTOR_VALIDATION_CFG = 1;
`else
    localparam integer PIPELINED_DESCRIPTOR_VALIDATION_CFG = 0;
`endif
`ifdef C1_NARROW_DESCRIPTOR_SIZE_CHECK
    localparam integer NARROW_DESCRIPTOR_SIZE_CHECK_CFG = 1;
`else
    localparam integer NARROW_DESCRIPTOR_SIZE_CHECK_CFG = 0;
`endif
`ifdef C1_PIPELINED_DESCRIPTOR_SIZE_ARITH
    localparam integer PIPELINED_DESCRIPTOR_SIZE_ARITH_CFG = 1;
`else
    localparam integer PIPELINED_DESCRIPTOR_SIZE_ARITH_CFG = 0;
`endif
`ifdef C1_FIXED_DESCRIPTOR_SIZE_LIMITS
    localparam integer FIXED_DESCRIPTOR_SIZE_LIMITS_CFG = 1;
`else
    localparam integer FIXED_DESCRIPTOR_SIZE_LIMITS_CFG = 0;
`endif
`ifdef C1_PIPELINED_DESCRIPTOR_PIXEL_COUNT
    localparam integer PIPELINED_DESCRIPTOR_PIXEL_COUNT_CFG = 1;
`else
    localparam integer PIPELINED_DESCRIPTOR_PIXEL_COUNT_CFG = 0;
`endif
`ifdef C1_ITERATIVE_DESCRIPTOR_PIXEL_COUNT
    localparam integer ITERATIVE_DESCRIPTOR_PIXEL_COUNT_CFG = 1;
`else
    localparam integer ITERATIVE_DESCRIPTOR_PIXEL_COUNT_CFG = 0;
`endif
`ifdef C1_PIPELINED_TENSOR_ADDRESS
    localparam integer PIPELINED_TENSOR_ADDRESS_CFG = 1;
`else
    localparam integer PIPELINED_TENSOR_ADDRESS_CFG = 0;
`endif
`ifdef C1_PIPELINED_TENSOR_PIXEL_INDEX
    localparam integer PIPELINED_TENSOR_PIXEL_INDEX_CFG = 1;
`else
    localparam integer PIPELINED_TENSOR_PIXEL_INDEX_CFG = 0;
`endif
    localparam integer STAGES = 22;
    localparam integer FRAME_W = 8;
    localparam integer FRAME_H = 4;
    localparam integer BANK_BYTES = 1024;
    localparam logic [31:0] BASE_ADDR = 32'h0000_1000;
    localparam integer MEMORY_WORDS = (3 * BANK_BYTES) / 8;

    logic clk = 1'b0;
    logic rst = 1'b1;
    always #5 clk = ~clk;

    logic adapter_start_valid;
    logic adapter_start_ready;
    logic adapter_abort;
    logic adapter_stage_config_valid;
    logic adapter_stage_config_ready;
    logic [15:0] adapter_stage_config_index;
    logic [511:0] adapter_stage_config_descriptor;
    logic [7:0] adapter_stage_config_generation;
    logic adapter_error;
    logic [7:0] adapter_error_code;
    logic adapter_source_valid;
    logic adapter_source_ready;
    logic [63:0] adapter_source_data_s8;
    logic [15:0] adapter_source_x, adapter_source_y;
    logic adapter_source_sof, adapter_source_eol, adapter_source_eof;
    logic adapter_engine_valid;
    logic adapter_engine_ready;
    logic [575:0] adapter_engine_window_s8;
    logic [63:0] adapter_engine_residual_s8;
    logic [2:0] adapter_engine_group_index;
    logic adapter_engine_group_last;
    logic [15:0] adapter_engine_x, adapter_engine_y;
    logic adapter_engine_sof, adapter_engine_eol, adapter_engine_eof;
    logic adapter_result_valid;
    logic adapter_result_ready;
    logic [63:0] adapter_result_data_s8;
    logic [2:0] adapter_result_group_index;
    logic adapter_result_group_last;
    logic [15:0] adapter_result_x, adapter_result_y;
    logic adapter_result_sof, adapter_result_eol, adapter_result_eof;
    logic adapter_final_valid;
    logic adapter_final_ready;
    logic [63:0] adapter_final_data_s8;
    logic [15:0] adapter_final_x, adapter_final_y;
    logic adapter_final_sof, adapter_final_eol, adapter_final_eof;
    logic [31:0] tensor_base_addr;
    logic cache_stage_start_valid, cache_stage_start_ready;
    logic cache_stage_enable;
    logic [31:0] cache_stage_base_addr;
    logic [15:0] cache_stage_width, cache_stage_height;
    logic [3:0] cache_stage_groups;
    logic mem_req_valid, mem_req_ready, mem_req_write;
    logic [31:0] mem_req_addr;
    logic [63:0] mem_req_wdata;
    logic [7:0] mem_req_wstrb;
    logic mem_req_cacheable;
    logic signed [16:0] mem_req_cache_x, mem_req_cache_y;
    logic [2:0] mem_req_cache_group;
    logic mem_rsp_valid, mem_rsp_ready, mem_rsp_error;
    logic [63:0] mem_rsp_rdata;
    logic adapter_busy, adapter_done, adapter_aborted;
    logic adapter_config_complete;
    logic [4:0] active_stage_index;
    logic [7:0] active_stage_opcode;
    logic [1:0] active_input_bank, active_output_bank;
    logic [1:0] active_residual_bank;

    c1_r1_microstyle_tensor_adapter #(
        .REQUIRED_STAGES(STAGES),
        .TENSOR_BANK_BYTES(BANK_BYTES),
        .PIPELINED_DESCRIPTOR_VALIDATION(PIPELINED_DESCRIPTOR_VALIDATION_CFG),
        .NARROW_DESCRIPTOR_SIZE_CHECK(NARROW_DESCRIPTOR_SIZE_CHECK_CFG),
        .PIPELINED_TENSOR_ADDRESS(PIPELINED_TENSOR_ADDRESS_CFG),
        .PIPELINED_TENSOR_PIXEL_INDEX(PIPELINED_TENSOR_PIXEL_INDEX_CFG),
        .PIPELINED_DESCRIPTOR_SIZE_ARITH(PIPELINED_DESCRIPTOR_SIZE_ARITH_CFG),
        .FIXED_DESCRIPTOR_SIZE_LIMITS(FIXED_DESCRIPTOR_SIZE_LIMITS_CFG),
        .PIPELINED_DESCRIPTOR_PIXEL_COUNT(PIPELINED_DESCRIPTOR_PIXEL_COUNT_CFG),
        .ITERATIVE_DESCRIPTOR_PIXEL_COUNT(ITERATIVE_DESCRIPTOR_PIXEL_COUNT_CFG)
    ) dut (
        .clk(clk), .rst(rst),
        .adapter_start_valid(adapter_start_valid),
        .adapter_start_ready(adapter_start_ready),
        .adapter_abort(adapter_abort),
        .adapter_stage_config_valid(adapter_stage_config_valid),
        .adapter_stage_config_ready(adapter_stage_config_ready),
        .adapter_stage_config_index(adapter_stage_config_index),
        .adapter_stage_config_descriptor(adapter_stage_config_descriptor),
        .adapter_stage_config_generation(adapter_stage_config_generation),
        .adapter_error(adapter_error),
        .adapter_error_code(adapter_error_code),
        .adapter_source_valid(adapter_source_valid),
        .adapter_source_ready(adapter_source_ready),
        .adapter_source_data_s8(adapter_source_data_s8),
        .adapter_source_x(adapter_source_x),
        .adapter_source_y(adapter_source_y),
        .adapter_source_sof(adapter_source_sof),
        .adapter_source_eol(adapter_source_eol),
        .adapter_source_eof(adapter_source_eof),
        .adapter_engine_valid(adapter_engine_valid),
        .adapter_engine_ready(adapter_engine_ready),
        .adapter_engine_window_s8(adapter_engine_window_s8),
        .adapter_engine_residual_s8(adapter_engine_residual_s8),
        .adapter_engine_group_index(adapter_engine_group_index),
        .adapter_engine_group_last(adapter_engine_group_last),
        .adapter_engine_x(adapter_engine_x),
        .adapter_engine_y(adapter_engine_y),
        .adapter_engine_sof(adapter_engine_sof),
        .adapter_engine_eol(adapter_engine_eol),
        .adapter_engine_eof(adapter_engine_eof),
        .adapter_result_valid(adapter_result_valid),
        .adapter_result_ready(adapter_result_ready),
        .adapter_result_data_s8(adapter_result_data_s8),
        .adapter_result_group_index(adapter_result_group_index),
        .adapter_result_group_last(adapter_result_group_last),
        .adapter_result_x(adapter_result_x),
        .adapter_result_y(adapter_result_y),
        .adapter_result_sof(adapter_result_sof),
        .adapter_result_eol(adapter_result_eol),
        .adapter_result_eof(adapter_result_eof),
        .adapter_final_valid(adapter_final_valid),
        .adapter_final_ready(adapter_final_ready),
        .adapter_final_data_s8(adapter_final_data_s8),
        .adapter_final_x(adapter_final_x),
        .adapter_final_y(adapter_final_y),
        .adapter_final_sof(adapter_final_sof),
        .adapter_final_eol(adapter_final_eol),
        .adapter_final_eof(adapter_final_eof),
        .tensor_base_addr(tensor_base_addr),
        .cache_stage_start_valid(cache_stage_start_valid),
        .cache_stage_start_ready(cache_stage_start_ready),
        .cache_stage_enable(cache_stage_enable),
        .cache_stage_base_addr(cache_stage_base_addr),
        .cache_stage_width(cache_stage_width),
        .cache_stage_height(cache_stage_height),
        .cache_stage_groups(cache_stage_groups),
        .mem_req_valid(mem_req_valid),
        .mem_req_ready(mem_req_ready),
        .mem_req_write(mem_req_write),
        .mem_req_addr(mem_req_addr),
        .mem_req_wdata(mem_req_wdata),
        .mem_req_wstrb(mem_req_wstrb),
        .mem_req_cacheable(mem_req_cacheable),
        .mem_req_cache_x(mem_req_cache_x),
        .mem_req_cache_y(mem_req_cache_y),
        .mem_req_cache_group(mem_req_cache_group),
        .mem_rsp_valid(mem_rsp_valid),
        .mem_rsp_ready(mem_rsp_ready),
        .mem_rsp_error(mem_rsp_error),
        .mem_rsp_rdata(mem_rsp_rdata),
        .adapter_busy(adapter_busy),
        .adapter_done(adapter_done),
        .adapter_aborted(adapter_aborted),
        .adapter_config_complete(adapter_config_complete),
        .active_stage_index(active_stage_index),
        .active_stage_opcode(active_stage_opcode),
        .active_input_bank(active_input_bank),
        .active_output_bank(active_output_bank),
        .active_residual_bank(active_residual_bank)
    );

    logic [63:0] memory [0:MEMORY_WORDS-1];
    logic [31:0] lfsr_q;
    logic response_pending_q;
    logic [2:0] response_delay_q;
    logic response_error_q;
    logic [63:0] response_data_q;
    logic hold_responses;
    logic force_request_ready;
    logic inject_response_error;

    integer request_count;
    integer read_count;
    integer write_count;
    integer request_stall_count;
    integer response_gap_count;
    integer abort_drain_count;
    integer memory_index;
    integer byte_lane;
    integer adjacent_pairable_count;
    integer adjacent_same_base_count;
    logic have_prev_request;
    logic [31:0] prev_request_addr;
    logic prev_request_write;

    assign mem_req_ready = !response_pending_q &&
                           (force_request_ready || lfsr_q[0]);
    assign mem_rsp_valid = response_pending_q &&
                           (response_delay_q == 0) && !hold_responses;
    assign mem_rsp_error = response_error_q;
    assign mem_rsp_rdata = response_data_q;

    always_ff @(posedge clk) begin
        if (rst) begin
            lfsr_q <= 32'h5a17_03c9;
            response_pending_q <= 1'b0;
            response_delay_q <= 3'd0;
            response_error_q <= 1'b0;
            response_data_q <= 64'd0;
            request_count <= 0;
            read_count <= 0;
            write_count <= 0;
            request_stall_count <= 0;
            response_gap_count <= 0;
            adjacent_pairable_count <= 0;
            adjacent_same_base_count <= 0;
            have_prev_request <= 1'b0;
            prev_request_addr <= 32'd0;
            prev_request_write <= 1'b0;
        end else begin
            lfsr_q <= {lfsr_q[30:0],
                       lfsr_q[31] ^ lfsr_q[21] ^ lfsr_q[1] ^ lfsr_q[0]};
            if (mem_req_valid && !mem_req_ready)
                request_stall_count <= request_stall_count + 1;
            if (response_pending_q && !mem_rsp_valid)
                response_gap_count <= response_gap_count + 1;

            if (response_pending_q && (response_delay_q != 0) &&
                !hold_responses)
                response_delay_q <= response_delay_q - 1'b1;

            if (mem_req_valid && mem_req_ready) begin
                if (response_pending_q)
                    $fatal(1, "memory BFM accepted a second outstanding request");
                if (mem_req_addr[2:0] != 0 || mem_req_addr < BASE_ADDR ||
                    mem_req_addr >= BASE_ADDR + 3 * BANK_BYTES)
                    $fatal(1, "memory address out of tensor arena: %h",
                           mem_req_addr);
                memory_index = (mem_req_addr - BASE_ADDR) >> 3;
                request_count <= request_count + 1;
                // The adapter is intentionally single-outstanding today, so
                // this observes temporal adjacency in its real accepted
                // request stream.  It is not a packing measurement: a future
                // batched emitter must preserve this order while allowing the
                // two entries to coexist in the seam FIFO.
                if (have_prev_request &&
                    (mem_req_addr[31:4] == prev_request_addr[31:4]) &&
                    (mem_req_addr[2:0] == 3'b000) &&
                    (prev_request_addr[2:0] == 3'b000) &&
                    (mem_req_addr[3] != prev_request_addr[3]) &&
                    (mem_req_write == prev_request_write)) begin
                    adjacent_pairable_count <= adjacent_pairable_count + 1;
                end
                if (have_prev_request &&
                    (mem_req_addr[31:4] == prev_request_addr[31:4]))
                    adjacent_same_base_count <= adjacent_same_base_count + 1;
                have_prev_request <= 1'b1;
                prev_request_addr <= mem_req_addr;
                prev_request_write <= mem_req_write;
                response_pending_q <= 1'b1;
                response_delay_q <= {1'b0, lfsr_q[3:2]};
                response_error_q <= inject_response_error;
                if (mem_req_write) begin
                    write_count <= write_count + 1;
                    if (mem_req_wstrb != 8'hff)
                        $fatal(1, "tensor write did not cover one C8 beat");
                    for (byte_lane = 0; byte_lane < 8;
                         byte_lane = byte_lane + 1)
                        if (mem_req_wstrb[byte_lane])
                            memory[memory_index][byte_lane*8 +: 8] <=
                                mem_req_wdata[byte_lane*8 +: 8];
                    response_data_q <= 64'd0;
                end else begin
                    read_count <= read_count + 1;
                    if (mem_req_wstrb != 0)
                        $fatal(1, "tensor read carried nonzero byte strobes");
                    response_data_q <= memory[memory_index];
                end
            end

            if (mem_rsp_valid && mem_rsp_ready) begin
                response_pending_q <= 1'b0;
                response_delay_q <= 3'd0;
                response_error_q <= 1'b0;
            end
        end
    end

    function automatic logic [7:0] stage_opcode_fn(input integer stage);
        begin
            case (stage)
                0, 1, 20: stage_opcode_fn = 8'd1;
                2, 4, 6, 8, 10, 12, 16, 19:
                    stage_opcode_fn = 8'd2;
                3, 7, 11, 15, 18: stage_opcode_fn = 8'd3;
                14, 17: stage_opcode_fn = 8'd4;
                5, 9, 13: stage_opcode_fn = 8'd5;
                21: stage_opcode_fn = 8'd6;
                default: stage_opcode_fn = 8'hff;
            endcase
        end
    endfunction

    function automatic integer stage_cin_fn(input integer stage);
        begin
            case (stage)
                0: stage_cin_fn = 3;
                1: stage_cin_fn = 12;
                2, 5, 6, 9, 10, 13, 14, 15, 16:
                    stage_cin_fn = 24;
                3, 4, 7, 8, 11, 12: stage_cin_fn = 48;
                17, 18, 19: stage_cin_fn = 16;
                20: stage_cin_fn = 8;
                21: stage_cin_fn = 3;
                default: stage_cin_fn = 0;
            endcase
        end
    endfunction

    function automatic integer stage_cout_fn(input integer stage);
        begin
            case (stage)
                0: stage_cout_fn = 12;
                1, 4, 5, 8, 9, 12, 13, 14, 15:
                    stage_cout_fn = 24;
                2, 3, 6, 7, 10, 11: stage_cout_fn = 48;
                16, 17, 18: stage_cout_fn = 16;
                19: stage_cout_fn = 8;
                20, 21: stage_cout_fn = 3;
                default: stage_cout_fn = 0;
            endcase
        end
    endfunction

    function automatic integer stage_iw_fn(input integer stage);
        begin
            if (stage == 0)
                stage_iw_fn = FRAME_W;
            else if (stage == 1)
                stage_iw_fn = FRAME_W / 2;
            else if (stage <= 14)
                stage_iw_fn = FRAME_W / 4;
            else if (stage <= 17)
                stage_iw_fn = FRAME_W / 2;
            else
                stage_iw_fn = FRAME_W;
        end
    endfunction

    function automatic integer stage_ih_fn(input integer stage);
        begin
            if (stage == 0)
                stage_ih_fn = FRAME_H;
            else if (stage == 1)
                stage_ih_fn = FRAME_H / 2;
            else if (stage <= 14)
                stage_ih_fn = FRAME_H / 4;
            else if (stage <= 17)
                stage_ih_fn = FRAME_H / 2;
            else
                stage_ih_fn = FRAME_H;
        end
    endfunction

    function automatic integer stage_ow_fn(input integer stage);
        begin
            if (stage == 0)
                stage_ow_fn = FRAME_W / 2;
            else if (stage <= 13)
                stage_ow_fn = FRAME_W / 4;
            else if (stage <= 16)
                stage_ow_fn = FRAME_W / 2;
            else
                stage_ow_fn = FRAME_W;
        end
    endfunction

    function automatic integer stage_oh_fn(input integer stage);
        begin
            if (stage == 0)
                stage_oh_fn = FRAME_H / 2;
            else if (stage <= 13)
                stage_oh_fn = FRAME_H / 4;
            else if (stage <= 16)
                stage_oh_fn = FRAME_H / 2;
            else
                stage_oh_fn = FRAME_H;
        end
    endfunction

    function automatic integer input_bank_fn(input integer stage);
        begin
            case (stage)
                0: input_bank_fn = 0;
                1: input_bank_fn = 1;
                2: input_bank_fn = 0;
                3: input_bank_fn = 1;
                4: input_bank_fn = 2;
                5: input_bank_fn = 1;
                6: input_bank_fn = 2;
                7: input_bank_fn = 0;
                8: input_bank_fn = 1;
                9: input_bank_fn = 0;
                10: input_bank_fn = 1;
                11: input_bank_fn = 2;
                12: input_bank_fn = 0;
                13: input_bank_fn = 2;
                14: input_bank_fn = 0;
                15: input_bank_fn = 1;
                16: input_bank_fn = 0;
                17: input_bank_fn = 1;
                18: input_bank_fn = 0;
                19: input_bank_fn = 1;
                20: input_bank_fn = 0;
                21: input_bank_fn = 1;
                default: input_bank_fn = 0;
            endcase
        end
    endfunction

    function automatic integer output_bank_fn(input integer stage);
        begin
            case (stage)
                0: output_bank_fn = 1;
                1: output_bank_fn = 0;
                2: output_bank_fn = 1;
                3: output_bank_fn = 2;
                4: output_bank_fn = 1;
                5: output_bank_fn = 2;
                6: output_bank_fn = 0;
                7: output_bank_fn = 1;
                8: output_bank_fn = 0;
                9: output_bank_fn = 1;
                10: output_bank_fn = 2;
                11: output_bank_fn = 0;
                12: output_bank_fn = 2;
                13: output_bank_fn = 0;
                14: output_bank_fn = 1;
                15: output_bank_fn = 0;
                16: output_bank_fn = 1;
                17: output_bank_fn = 0;
                18: output_bank_fn = 1;
                19: output_bank_fn = 0;
                20: output_bank_fn = 1;
                default: output_bank_fn = 3;
            endcase
        end
    endfunction

    function automatic integer residual_bank_fn(input integer stage);
        begin
            case (stage)
                5: residual_bank_fn = 0;
                9: residual_bank_fn = 2;
                13: residual_bank_fn = 1;
                default: residual_bank_fn = 3;
            endcase
        end
    endfunction

    function automatic logic [511:0] descriptor_fn(input integer stage);
        logic [511:0] d;
        integer op, iw, ih, ow, oh, ci, co;
        integer kw, kh, sx, sy, flags, activation;
        begin
            d = 512'd0;
            op = stage_opcode_fn(stage);
            iw = stage_iw_fn(stage);
            ih = stage_ih_fn(stage);
            ow = stage_ow_fn(stage);
            oh = stage_oh_fn(stage);
            ci = stage_cin_fn(stage);
            co = stage_cout_fn(stage);
            kw = ((op == 1) || (op == 3)) ? 3 : 1;
            kh = kw;
            sx = ((stage == 0) || (stage == 1) ||
                  (op == 4)) ? 2 : 1;
            sy = sx;
            flags = (((op == 1) || (op == 3)) ? 1 : 0) |
                    ((op == 5) ? 2 : 0) |
                    ((stage == 0) ? 4 : 0) |
                    ((stage == 21) ? 8 : 0);
            activation = ((stage == 4) || (stage == 8) ||
                          (stage == 12) || (stage == 14) ||
                          (stage == 17) || (stage >= 20)) ? 0 : 1;
            d[7:0] = op[7:0];
            d[9:8] = activation[1:0];
            d[15:10] = flags[5:0];
            d[23:16] = 8'd1;
            d[31:24] = 8'd16;
            d[47:32] = iw[15:0];
            d[63:48] = ih[15:0];
            d[79:64] = ow[15:0];
            d[95:80] = oh[15:0];
            d[111:96] = ci[15:0];
            d[127:112] = co[15:0];
            d[423:416] = kw[7:0];
            d[431:424] = kh[7:0];
            d[439:432] = sx[7:0];
            d[447:440] = sy[7:0];
            d[455:448] = 8'd1;
            d[463:456] = 8'd1;
            d[471:464] = 8'd1;
            d[479:472] = 8'd1;
            d[511:480] = 32'd1000000;
            descriptor_fn = d;
        end
    endfunction

    function automatic logic [63:0] source_data_fn(
        input integer x, input integer y
    );
        logic [63:0] value;
        integer lane;
        begin
            value = 64'd0;
            for (lane = 0; lane < 3; lane = lane + 1)
                value[lane*8 +: 8] = (8'h31 + x*7 + y*11 + lane*17) & 8'hff;
            source_data_fn = value;
        end
    endfunction

    function automatic logic [63:0] result_data_fn(
        input integer stage,
        input integer x,
        input integer y,
        input integer group_index
    );
        logic [63:0] value;
        integer lane;
        integer channel;
        begin
            value = 64'd0;
            for (lane = 0; lane < 8; lane = lane + 1) begin
                channel = group_index * 8 + lane;
                if (channel < stage_cout_fn(stage))
                    value[lane*8 +: 8] =
                        (stage*13 + x*7 + y*5 +
                         group_index*23 + lane*3 + 8'h19) & 8'hff;
            end
            result_data_fn = value;
        end
    endfunction

    function automatic logic [63:0] tensor_word_fn(
        input integer bank,
        input integer width,
        input integer groups,
        input integer x,
        input integer y,
        input integer group_index
    );
        integer index;
        begin
            index = (bank * BANK_BYTES) / 8 +
                    ((y * width + x) * groups) + group_index;
            if (index < 0 || index >= MEMORY_WORDS)
                $fatal(1, "testbench tensor index out of range");
            tensor_word_fn = memory[index];
        end
    endfunction

    integer expected_stage_q;
    integer expected_x_q, expected_y_q, expected_input_group_q;
    logic result_active_q;
    logic result_valid_q;
    integer result_stage_q, result_x_q, result_y_q, result_group_q;
    integer engine_stall_count;
    integer final_stall_count;
    integer engine_operand_count;
    integer final_count;
    integer stage_seen [0:STAGES-1];
    integer op_seen [1:6];
    integer border_window_count;
    integer upsample_operand_count;
    integer residual_operand_count;
    integer residual_bank_seen [0:2];

    assign adapter_engine_ready = !result_active_q && !result_valid_q &&
                                  lfsr_q[5];
    assign adapter_result_valid = result_valid_q;
    assign adapter_result_data_s8 = result_data_fn(
        result_stage_q, result_x_q, result_y_q, result_group_q);
    assign adapter_result_group_index = result_group_q[2:0];
    assign adapter_result_group_last =
        (result_group_q == ((stage_cout_fn(result_stage_q) + 7) / 8) - 1);
    assign adapter_result_x = result_x_q[15:0];
    assign adapter_result_y = result_y_q[15:0];
    assign adapter_result_sof = (result_group_q == 0) &&
                                (result_x_q == 0) && (result_y_q == 0);
    assign adapter_result_eol = adapter_result_group_last &&
                                (result_x_q == stage_ow_fn(result_stage_q)-1);
    assign adapter_result_eof = adapter_result_eol &&
                                (result_y_q == stage_oh_fn(result_stage_q)-1);
    assign adapter_final_ready = lfsr_q[7];

    task automatic check_engine_operand;
        integer stage, x, y, group_index;
        integer iw, ih, groups, op, stride;
        integer tap, sx, sy, dx, dy;
        logic [63:0] expected_word;
        begin
            stage = expected_stage_q;
            x = expected_x_q;
            y = expected_y_q;
            group_index = expected_input_group_q;
            iw = stage_iw_fn(stage);
            ih = stage_ih_fn(stage);
            groups = (stage_cin_fn(stage) + 7) / 8;
            op = stage_opcode_fn(stage);
            stride = ((stage == 0) || (stage == 1)) ? 2 : 1;

            if (active_stage_index !== stage[4:0] ||
                active_stage_opcode !== op[7:0] ||
                adapter_engine_group_index !== group_index[2:0] ||
                adapter_engine_group_last !== (group_index == groups-1) ||
                adapter_engine_x !== x[15:0] ||
                adapter_engine_y !== y[15:0])
                $fatal(1, "engine operand sequence mismatch stage=%0d x=%0d y=%0d g=%0d",
                       stage, x, y, group_index);
            if (adapter_engine_sof !== ((x == 0) && (y == 0)) ||
                adapter_engine_eol !== (x == stage_ow_fn(stage)-1) ||
                adapter_engine_eof !== ((x == stage_ow_fn(stage)-1) &&
                                        (y == stage_oh_fn(stage)-1)))
                $fatal(1, "engine input marker mismatch");
            if (active_input_bank !== input_bank_fn(stage) ||
                active_output_bank !== output_bank_fn(stage) ||
                active_residual_bank !== residual_bank_fn(stage))
                $fatal(1, "published tensor bank map mismatch");

            for (tap = 0; tap < 9; tap = tap + 1) begin
                if ((op == 1) || (op == 3)) begin
                    dx = (tap % 3) - 1;
                    dy = (tap / 3) - 1;
                    sx = x * stride + dx;
                    sy = y * stride + dy;
                    if (sx < 0) sx = 0;
                    if (sy < 0) sy = 0;
                    if (sx >= iw) sx = iw - 1;
                    if (sy >= ih) sy = ih - 1;
                    expected_word = tensor_word_fn(
                        input_bank_fn(stage), iw, groups,
                        sx, sy, group_index);
                end else if (tap == 4) begin
                    if (op == 4) begin
                        sx = x / 2;
                        sy = y / 2;
                    end else begin
                        sx = x;
                        sy = y;
                    end
                    expected_word = tensor_word_fn(
                        input_bank_fn(stage), iw, groups,
                        sx, sy, group_index);
                end else begin
                    expected_word = 64'd0;
                end
                if (adapter_engine_window_s8[tap*64 +: 64] !==
                    expected_word)
                    $fatal(1, "window mismatch stage=%0d x=%0d y=%0d g=%0d tap=%0d got=%h exp=%h",
                           stage, x, y, group_index, tap,
                           adapter_engine_window_s8[tap*64 +: 64],
                           expected_word);
            end

            if (op == 5) begin
                expected_word = tensor_word_fn(
                    residual_bank_fn(stage), iw, groups,
                    x, y, group_index);
                if (adapter_engine_residual_s8 !== expected_word)
                    $fatal(1, "residual operand mismatch stage=%0d", stage);
            end else if (adapter_engine_residual_s8 !== 0) begin
                $fatal(1, "non-residual stage carried residual data");
            end
        end
    endtask

    integer model_i;
    always_ff @(posedge clk) begin
        if (rst) begin
            expected_stage_q <= 0;
            expected_x_q <= 0;
            expected_y_q <= 0;
            expected_input_group_q <= 0;
            result_active_q <= 1'b0;
            result_valid_q <= 1'b0;
            result_stage_q <= 0;
            result_x_q <= 0;
            result_y_q <= 0;
            result_group_q <= 0;
            engine_stall_count <= 0;
            final_stall_count <= 0;
            engine_operand_count <= 0;
            final_count <= 0;
            border_window_count <= 0;
            upsample_operand_count <= 0;
            residual_operand_count <= 0;
            for (model_i = 0; model_i < STAGES; model_i = model_i + 1)
                stage_seen[model_i] <= 0;
            for (model_i = 1; model_i <= 6; model_i = model_i + 1)
                op_seen[model_i] <= 0;
            for (model_i = 0; model_i < 3; model_i = model_i + 1)
                residual_bank_seen[model_i] <= 0;
        end else begin
            if (adapter_engine_valid && !adapter_engine_ready)
                engine_stall_count <= engine_stall_count + 1;
            if (adapter_final_valid && !adapter_final_ready)
                final_stall_count <= final_stall_count + 1;

            if (adapter_engine_valid && adapter_engine_ready) begin
                check_engine_operand();
                engine_operand_count <= engine_operand_count + 1;
                stage_seen[expected_stage_q] <=
                    stage_seen[expected_stage_q] + 1;
                op_seen[stage_opcode_fn(expected_stage_q)] <=
                    op_seen[stage_opcode_fn(expected_stage_q)] + 1;
                if (((stage_opcode_fn(expected_stage_q) == 1) ||
                     (stage_opcode_fn(expected_stage_q) == 3)) &&
                    ((expected_x_q == 0) || (expected_y_q == 0) ||
                     (expected_x_q == stage_ow_fn(expected_stage_q)-1) ||
                     (expected_y_q == stage_oh_fn(expected_stage_q)-1)))
                    border_window_count <= border_window_count + 1;
                if (stage_opcode_fn(expected_stage_q) == 4)
                    upsample_operand_count <= upsample_operand_count + 1;
                if (stage_opcode_fn(expected_stage_q) == 5) begin
                    residual_operand_count <= residual_operand_count + 1;
                    residual_bank_seen[residual_bank_fn(expected_stage_q)] <=
                        residual_bank_seen[residual_bank_fn(expected_stage_q)] + 1;
                end

                if (expected_input_group_q ==
                    ((stage_cin_fn(expected_stage_q) + 7) / 8) - 1) begin
                    result_active_q <= 1'b1;
                    result_stage_q <= expected_stage_q;
                    result_x_q <= expected_x_q;
                    result_y_q <= expected_y_q;
                    result_group_q <= 0;
                end else begin
                    expected_input_group_q <= expected_input_group_q + 1;
                end
            end

            if (result_active_q && !result_valid_q && lfsr_q[9])
                result_valid_q <= 1'b1;

            if (adapter_result_valid && adapter_result_ready) begin
                result_valid_q <= 1'b0;
                if (adapter_result_group_last) begin
                    result_active_q <= 1'b0;
                    expected_input_group_q <= 0;
                    if (adapter_result_eof) begin
                        expected_stage_q <= expected_stage_q + 1;
                        expected_x_q <= 0;
                        expected_y_q <= 0;
                    end else if (expected_x_q ==
                                 stage_ow_fn(expected_stage_q)-1) begin
                        expected_x_q <= 0;
                        expected_y_q <= expected_y_q + 1;
                    end else begin
                        expected_x_q <= expected_x_q + 1;
                    end
                end else begin
                    result_group_q <= result_group_q + 1;
                end
            end

            if (adapter_final_valid && adapter_final_ready) begin
                if (adapter_final_data_s8 !== result_data_fn(
                        21, adapter_final_x, adapter_final_y, 0))
                    $fatal(1, "final C8 data mismatch");
                if (adapter_final_sof !==
                        ((adapter_final_x == 0) && (adapter_final_y == 0)) ||
                    adapter_final_eol !== (adapter_final_x == FRAME_W-1) ||
                    adapter_final_eof !==
                        ((adapter_final_x == FRAME_W-1) &&
                         (adapter_final_y == FRAME_H-1)))
                    $fatal(1, "final marker mismatch");
                final_count <= final_count + 1;
            end
        end
    end

    task automatic reset_engine_model;
        begin
            @(negedge clk);
            expected_stage_q = 0;
            expected_x_q = 0;
            expected_y_q = 0;
            expected_input_group_q = 0;
            result_active_q = 1'b0;
            result_valid_q = 1'b0;
            result_stage_q = 0;
            result_x_q = 0;
            result_y_q = 0;
            result_group_q = 0;
        end
    endtask

    task automatic start_job;
        begin
            @(negedge clk);
            tensor_base_addr = BASE_ADDR;
            adapter_start_valid = 1'b1;
            do @(posedge clk); while (!adapter_start_ready);
            @(negedge clk);
            adapter_start_valid = 1'b0;
        end
    endtask

    task automatic send_all_descriptors(input logic [7:0] generation);
        integer stage;
        begin
            for (stage = 0; stage < STAGES; stage = stage + 1) begin
                repeat (lfsr_q[1:0]) @(posedge clk);
                @(negedge clk);
                adapter_stage_config_index = stage[15:0];
                adapter_stage_config_descriptor = descriptor_fn(stage);
                adapter_stage_config_generation = generation;
                adapter_stage_config_valid = 1'b1;
                do @(posedge clk); while (!adapter_stage_config_ready);
                @(negedge clk);
                adapter_stage_config_valid = 1'b0;
            end
        end
    endtask

    task automatic send_source_beat(input integer x, input integer y);
        begin
            repeat (lfsr_q[3:2]) @(posedge clk);
            @(negedge clk);
            adapter_source_data_s8 = source_data_fn(x, y);
            adapter_source_x = x[15:0];
            adapter_source_y = y[15:0];
            adapter_source_sof = (x == 0) && (y == 0);
            adapter_source_eol = (x == FRAME_W-1);
            adapter_source_eof = (x == FRAME_W-1) && (y == FRAME_H-1);
            adapter_source_valid = 1'b1;
            do @(posedge clk); while (!adapter_source_ready);
            @(negedge clk);
            adapter_source_valid = 1'b0;
        end
    endtask

    task automatic send_source_frame;
        integer x, y;
        begin
            for (y = 0; y < FRAME_H; y = y + 1)
                for (x = 0; x < FRAME_W; x = x + 1)
                    send_source_beat(x, y);
        end
    endtask

    task automatic pulse_abort;
        begin
            @(negedge clk);
            adapter_abort = 1'b1;
            @(negedge clk);
            adapter_abort = 1'b0;
        end
    endtask

    integer timeout;
    integer success_final_start;
    integer success_request_start;
    integer success_write_start;
    integer success_read_start;
    integer engine_before_error;
    integer check_i;
    initial begin
        adapter_start_valid = 1'b0;
        adapter_abort = 1'b0;
        adapter_stage_config_valid = 1'b0;
        adapter_stage_config_index = 16'd0;
        adapter_stage_config_descriptor = 512'd0;
        adapter_stage_config_generation = 8'd0;
        adapter_source_valid = 1'b0;
        adapter_source_data_s8 = 64'd0;
        adapter_source_x = 16'd0;
        adapter_source_y = 16'd0;
        adapter_source_sof = 1'b0;
        adapter_source_eol = 1'b0;
        adapter_source_eof = 1'b0;
        tensor_base_addr = BASE_ADDR;
        cache_stage_start_ready = 1'b0;
        hold_responses = 1'b0;
        force_request_ready = 1'b0;
        inject_response_error = 1'b0;
        abort_drain_count = 0;
        for (check_i = 0; check_i < MEMORY_WORDS; check_i = check_i + 1)
            memory[check_i] = 64'd0;

        repeat (8) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        // Abort with a source write outstanding.  The request must not be
        // withdrawn and the response must be drained before aborted pulses.
        start_job();
        send_all_descriptors(8'h31);
        // Optional pipelined descriptor validation commits a few cycles after
        // the final descriptor handshake.  Wait on the architectural
        // completion flag instead of assuming the legacy same-cycle commit.
        timeout = 0;
        while (!adapter_config_complete && timeout < 256) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (!adapter_config_complete)
            $fatal(1, "descriptor snapshot did not complete");
        hold_responses = 1'b1;
        force_request_ready = 1'b1;
        fork
            send_source_beat(0, 0);
        join
        timeout = 0;
        while (!response_pending_q && timeout < 100) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (!response_pending_q)
            $fatal(1, "abort test never created an outstanding write");
        pulse_abort();
        repeat (5) begin
            @(posedge clk);
            if (!adapter_busy)
                $fatal(1, "adapter retired abort before memory drain");
            abort_drain_count = abort_drain_count + 1;
        end
        hold_responses = 1'b0;
        force_request_ready = 1'b0;
        timeout = 0;
        while (!adapter_aborted && timeout < 100) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (!adapter_aborted || adapter_busy || adapter_error)
            $fatal(1, "protocol-safe abort did not retire cleanly");

        // Full 22-stage restart with randomized memory, engine, result and
        // final-stream stalls.  The engine BFM checks every operand window.
        reset_engine_model();
        success_final_start = final_count;
        success_request_start = request_count;
        success_write_start = write_count;
        success_read_start = read_count;
        start_job();
        send_all_descriptors(8'h32);
        send_source_frame();
        timeout = 0;
        while (!adapter_done && timeout < 300000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (!adapter_done)
            $fatal(1, "full MicroStyle tensor schedule timed out");
        if (adapter_error || adapter_busy)
            $fatal(1, "successful schedule retired with error/busy");
        if (final_count - success_final_start != FRAME_W * FRAME_H)
            $fatal(1, "final frame beat count mismatch");
        if (request_count <= success_request_start ||
            write_count <= success_write_start ||
            read_count <= success_read_start)
            $fatal(1, "full schedule did not exercise read/write traffic");
        for (check_i = 0; check_i < STAGES; check_i = check_i + 1)
            if (stage_seen[check_i] == 0)
                $fatal(1, "stage %0d had no engine operands", check_i);
        for (check_i = 1; check_i <= 6; check_i = check_i + 1)
            if (op_seen[check_i] == 0)
                $fatal(1, "opcode %0d was not covered", check_i);
        for (check_i = 0; check_i < 3; check_i = check_i + 1)
            if (residual_bank_seen[check_i] == 0)
                $fatal(1, "residual bank %0d was not covered", check_i);
        if (border_window_count == 0 || upsample_operand_count == 0 ||
            residual_operand_count == 0 || request_stall_count == 0 ||
            response_gap_count == 0 || engine_stall_count == 0 ||
            final_stall_count == 0)
            $fatal(1, "required scheduler/backpressure coverage missing");

        // A real memory response error is sticky and prevents any compute
        // operand from being launched for that failed job.
        start_job();
        send_all_descriptors(8'h33);
        engine_before_error = engine_operand_count;
        force_request_ready = 1'b1;
        inject_response_error = 1'b1;
        success_request_start = request_count;
        send_source_beat(0, 0);
        timeout = 0;
        while ((request_count == success_request_start) && timeout < 100) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        @(negedge clk);
        inject_response_error = 1'b0;
        force_request_ready = 1'b0;
        timeout = 0;
        while (!adapter_error && timeout < 100) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (!adapter_error || adapter_error_code != 8'h07 ||
            engine_operand_count != engine_before_error)
            $fatal(1, "memory error was not propagated by the adapter");
        pulse_abort();
        @(posedge clk);
        if (adapter_error || adapter_busy)
            $fatal(1, "memory-error abort did not restore idle");

        // A descriptor generation change is rejected and remains sticky until
        // explicit abort.  No source/engine launch is possible in this state.
        start_job();
        @(negedge clk);
        adapter_stage_config_index = 16'd0;
        adapter_stage_config_descriptor = descriptor_fn(0);
        adapter_stage_config_generation = 8'h44;
        adapter_stage_config_valid = 1'b1;
        do @(posedge clk); while (!adapter_stage_config_ready);
        @(negedge clk);
        adapter_stage_config_valid = 1'b0;
        @(negedge clk);
        adapter_stage_config_index = 16'd1;
        adapter_stage_config_descriptor = descriptor_fn(1);
        adapter_stage_config_generation = 8'h45;
        adapter_stage_config_valid = 1'b1;
        do @(posedge clk); while (!adapter_stage_config_ready);
        @(negedge clk);
        adapter_stage_config_valid = 1'b0;
        repeat (3) @(posedge clk);
        if (!adapter_error || adapter_error_code != 8'h03 ||
            adapter_source_ready || adapter_engine_valid)
            $fatal(1, "generation mismatch was not safely quarantined");
        pulse_abort();
        @(posedge clk);
        if (adapter_error || adapter_busy || !adapter_start_ready)
            $fatal(1, "error abort did not restore restart readiness");

        $display("C1_R1_MICROSTYLE_TENSOR_ADAPTER_PASS requests=%0d reads=%0d writes=%0d operands=%0d final=%0d mem_stall=%0d rsp_gap=%0d engine_stall=%0d final_stall=%0d borders=%0d upsample=%0d residual=%0d drains=%0d adjacent_same_base=%0d adjacent_pairable=%0d pipeline=%0d descriptor_pipeline=%0d narrow=%0d size_arith=%0d fixed_limits=%0d pixel_count_pipeline=%0d iterative_descriptor_pixel_count=%0d",
                 request_count, read_count, write_count,
                 engine_operand_count, final_count,
                 request_stall_count, response_gap_count,
                 engine_stall_count, final_stall_count,
                 border_window_count, upsample_operand_count,
                 residual_operand_count, abort_drain_count,
                 adjacent_same_base_count, adjacent_pairable_count,
                 PIPELINED_TENSOR_ADDRESS_CFG,
                 PIPELINED_DESCRIPTOR_VALIDATION_CFG,
                 NARROW_DESCRIPTOR_SIZE_CHECK_CFG,
                 PIPELINED_DESCRIPTOR_SIZE_ARITH_CFG,
                 FIXED_DESCRIPTOR_SIZE_LIMITS_CFG,
                 PIPELINED_DESCRIPTOR_PIXEL_COUNT_CFG,
                 ITERATIVE_DESCRIPTOR_PIXEL_COUNT_CFG);
        $finish;
    end

    initial begin
        #5000000;
        $fatal(1, "global tensor-adapter timeout");
    end

endmodule
