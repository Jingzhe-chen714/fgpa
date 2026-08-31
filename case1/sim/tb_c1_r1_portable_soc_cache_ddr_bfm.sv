`timescale 1ns/1ps

// Small-frame dynamic integration test for the portable SoC.
//
// This test intentionally instantiates the real top (rather than the cache
// seam in isolation) with a selectable small active frame.  The default is
// 8x8; C1_FRAME_16X8, C1_FRAME_64X48 and C1_FRAME_640X480 provide deterministic scale-up
// points for the same complete lifecycle.
// software-visible lifecycle:
//
//   APB tables/descriptor/parameter setup -> ISP commit -> START
//   RAW10 (FRAME_W+2)x(FRAME_H+2) camera frame -> capture table lookup
//   -> XRGB DDR write
//   parameter arena + 22 descriptors -> boardless CNN job
//   tensor adapter/cache (client 6) -> seven-client AXI128 fabric
//   output DDR write -> display prefetch reads
//
// The memory model is deliberately a protocol BFM, not a zero-latency tie-off:
// AW/W/AR are independently backpressured, R/B responses are delayed and held
// until READY, and byte strobes are applied to a small sparse line store.
// Descriptor and table regions are decoded functionally, so the test does not
// allocate a multi-megabyte four-state memory just to represent the 32-bit
// address space.
module tb_c1_r1_portable_soc_cache_ddr_bfm;
`ifdef C1_TRAINED_ARTIFACT
    // Boardless artifact mode is an opt-in 8x8 integration probe.  The
    // default BFM remains the historical zero-parameter lifecycle test so
    // existing traffic/timing baselines are not changed accidentally.
    localparam integer TRAINED_ARTIFACT_CFG = 1;
`else
    localparam integer TRAINED_ARTIFACT_CFG = 0;
`endif
`ifdef C1_FRAME_16X8
    localparam integer FRAME_W = 16;
    localparam integer FRAME_H = 8;
`elsif C1_FRAME_64X48
    localparam integer FRAME_W = 64;
    localparam integer FRAME_H = 48;
`elsif C1_FRAME_640X480
    localparam integer FRAME_W = 640;
    localparam integer FRAME_H = 480;
`else
    localparam integer FRAME_W = 8;
    localparam integer FRAME_H = 8;
`endif
`ifdef C1_DISPLAY_RESPONSE_FIFO
    localparam integer DISPLAY_RESPONSE_FIFO_ENABLE = 1;
    // Leave one complete 16-beat/64-pixel burst of headroom even when a
    // previous burst has not yet drained into the line store.
    localparam integer DISPLAY_RESPONSE_FIFO_DEPTH_CFG = 128;
`else
    localparam integer DISPLAY_RESPONSE_FIFO_ENABLE = 0;
    localparam integer DISPLAY_RESPONSE_FIFO_DEPTH_CFG = 64;
`endif
`ifdef C1_TABLE_RESPONSE_FIFO
    localparam integer ENABLE_TABLE_RESPONSE_FIFO_CFG = 1;
`else
    localparam integer ENABLE_TABLE_RESPONSE_FIFO_CFG = 0;
`endif
`ifdef C1_RELAXED_DESCRIPTOR
    // The relaxed build is an explicitly opted-in performance experiment.
    // The DUT keeps a simulation-time ABI guard so malformed descriptors still
    // fail loudly instead of silently producing an invalid tensor address.
    localparam integer STRICT_DESCRIPTOR_VALIDATION_CFG = 0;
`else
    localparam integer STRICT_DESCRIPTOR_VALIDATION_CFG = 1;
`endif
`ifdef C1_FAST_ADDRESS
    localparam integer FAST_TENSOR_ADDRESS_ARITH_CFG = 1;
`else
    localparam integer FAST_TENSOR_ADDRESS_ARITH_CFG = 0;
`endif
`ifdef C1_PIPELINED_ADDRESS
    localparam integer PIPELINED_TENSOR_ADDRESS_CFG = 1;
`else
    localparam integer PIPELINED_TENSOR_ADDRESS_CFG = 0;
`endif
`ifdef C1_PIPELINED_TENSOR_PIXEL_INDEX
    localparam integer PIPELINED_TENSOR_PIXEL_INDEX_CFG = 1;
`else
    localparam integer PIPELINED_TENSOR_PIXEL_INDEX_CFG = 0;
`endif
`ifdef C1_PIPELINED_DESCRIPTOR_VALIDATION
    // Optional two-boundary strict descriptor checker.  It adds a fixed
    // bubble per stage configuration but should not alter the descriptor
    // stream payload or error priority.
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
`ifdef C1_PRECLAMPED_TAP_COORDS
    // The tensor seam clamps cache sideband coordinates before the payload
    // cache sees them; this opt-in removes the child's duplicate geometry
    // compare for timing A/B only.
    localparam integer PRECLAMPED_TAP_COORDS_CFG = 1;
`else
    localparam integer PRECLAMPED_TAP_COORDS_CFG = 0;
`endif
`ifdef C1_REGISTER_ABORT_RESET
    // Optional one-cycle child-reset hold used only for timing attribution;
    // raw abort handshakes remain fenced immediately by the RTL wrapper.
    localparam integer REGISTER_ABORT_RESET_CFG = 1;
`else
    localparam integer REGISTER_ABORT_RESET_CFG = 0;
`endif
`ifdef C1_PIPELINED_START_CONFIG
    localparam integer PIPELINED_START_CONFIG_CFG = 1;
`else
    localparam integer PIPELINED_START_CONFIG_CFG = 0;
`endif
`ifdef C1_PIPELINED_DOT_TREE
    localparam integer PIPELINED_DOT_TREE_CFG = 1;
`else
    localparam integer PIPELINED_DOT_TREE_CFG = 0;
`endif
`ifdef C1_PIPELINED_DOT_TREE_FULL
    localparam integer PIPELINED_DOT_TREE_FULL_CFG = 1;
`else
    localparam integer PIPELINED_DOT_TREE_FULL_CFG = 0;
`endif
`ifdef C1_PIPELINED_DESCRIPTOR_REPLAY
    localparam integer PIPELINED_DESCRIPTOR_REPLAY_CFG = 1;
`else
    localparam integer PIPELINED_DESCRIPTOR_REPLAY_CFG = 0;
`endif
`ifdef C1_PREVALIDATE_DESCRIPTOR_REPLAY
    localparam integer PREVALIDATE_DESCRIPTOR_REPLAY_CFG = 1;
`else
    localparam integer PREVALIDATE_DESCRIPTOR_REPLAY_CFG = 0;
`endif
`ifdef C1_PIPELINED_DECODER_VALIDATION
    // Optional two-cycle validation schedule in the replay-side command
    // decoder.  It is independent of the tensor-adapter checker above.
    localparam integer PIPELINED_DECODER_VALIDATION_CFG = 1;
`else
    localparam integer PIPELINED_DECODER_VALIDATION_CFG = 0;
`endif
`ifdef C1_REPLICATE_ABORT_CONTROL
    localparam integer REPLICATE_ABORT_CONTROL_CFG = 1;
`else
    localparam integer REPLICATE_ABORT_CONTROL_CFG = 0;
`endif
`ifdef C1_UNIFIED_OUTPUT_FIFO
    localparam integer ENABLE_UNIFIED_OUTPUT_FIFO_CFG = 1;
`else
    localparam integer ENABLE_UNIFIED_OUTPUT_FIFO_CFG = 0;
`endif
`ifdef C1_UNIFIED_OUTPUT_SKID
    localparam integer ENABLE_UNIFIED_OUTPUT_SKID_CFG = 1;
`else
    localparam integer ENABLE_UNIFIED_OUTPUT_SKID_CFG = 0;
`endif
`ifdef C1_FABRIC_READ_RESPONSE_SKID
    localparam integer ENABLE_FABRIC_READ_RESPONSE_SKID_CFG = 1;
`else
    localparam integer ENABLE_FABRIC_READ_RESPONSE_SKID_CFG = 0;
`endif
`ifdef C1_REGISTER_FATAL_TICKET
    localparam integer REGISTER_FATAL_TICKET_CFG = 1;
`else
    localparam integer REGISTER_FATAL_TICKET_CFG = 0;
`endif
`ifdef C1_SHARED_QOS_MONITOR
    localparam integer ENABLE_SHARED_QOS_MONITOR_CFG = 1;
    // The native 8x8 BFM intentionally includes a long ID-less R hold.  A
    // one-million-cycle budget therefore exercises the deadline-miss counter
    // while remaining below the 24-bit monitor range.
    localparam logic [31:0] SHARED_QOS_DEADLINE_CYCLES_CFG = 32'd1_000_000;
    // The display timing domain is a fixed 720p raster, while the active test
    // image may be wider/taller than the 8x8 smoke shape.  A tagged prefetch
    // completion is allowed to wait for the pixel side to acknowledge the last
    // line, so a larger shape can legitimately cross a 50 ms (5 M core-cycle)
    // observation window even after the ownership swap has occurred.  Keep the
    // short guard for the fast smoke case and scale only the larger dynamic
    // shape; this is a testbench bound, not a hardware timeout.
    localparam integer SHARED_QOS_BOUNDARY_WAIT_CYCLES =
        ((FRAME_W * FRAME_H) >= 3072) ? 20_000_000 : 5_000_000;
`else
    localparam integer ENABLE_SHARED_QOS_MONITOR_CFG = 0;
    localparam logic [31:0] SHARED_QOS_DEADLINE_CYCLES_CFG = 32'd0;
`endif
`ifdef C1_TENSOR_BURST_REFILL
    localparam integer ENABLE_TENSOR_BURST_REFILL_CFG = 1;
`else
    localparam integer ENABLE_TENSOR_BURST_REFILL_CFG = 0;
`endif
`ifdef C1_TENSOR_BURST_BEAT_MODE
    // The top-level beat-record option uses the conservative minimum depth
    // for the default 16-beat/4-outstanding reader configuration.  It is only
    // meaningful when the burst client itself is enabled.
    localparam integer TENSOR_BURST_RSP_FIFO_BEAT_MODE_CFG = 1;
    localparam integer TENSOR_BURST_RSP_FIFO_DEPTH_CFG = 64;
`else
    localparam integer TENSOR_BURST_RSP_FIFO_BEAT_MODE_CFG = 0;
    localparam integer TENSOR_BURST_RSP_FIFO_DEPTH_CFG = 128;
`endif
    localparam integer SENSOR_W = FRAME_W + 2;
    localparam integer SENSOR_H = FRAME_H + 2;
    localparam integer CAM_X_W = (SENSOR_W <= 1) ? 1 : $clog2(SENSOR_W);
    localparam integer CAM_Y_W = (SENSOR_H <= 1) ? 1 : $clog2(SENSOR_H);

    localparam logic [31:0] IN_TABLE   = 32'h0000_1000;
    localparam logic [31:0] OUT_TABLE  = 32'h0000_2000;
    localparam logic [31:0] DESC_BASE  = 32'h0000_4000;
    localparam logic [31:0] WEIGHT_BASE= 32'h0001_0000;
    localparam logic [31:0] INPUT_BASE = 32'h0010_0000;
    // The compact smoke-map is sufficient for the small frames, but a native
    // 640x480 slot is 0x12c000 bytes.  Move output far enough past all three
    // input slots before any native runtime test; keep the historical map for
    // the existing small-frame traffic baselines.
    localparam logic [31:0] OUTPUT_BASE = (FRAME_W >= 640) ?
                                          32'h0060_0000 : 32'h0020_0000;
    localparam logic [31:0] TENSOR_BASE= 32'h0200_0000;
    localparam integer XRGB_STRIDE = FRAME_W * 4;
    // Frame-manager table indices must not alias when the parameterized
    // image is larger than the original 8x8 smoke-test frame.  Keep every
    // slot 0x100 aligned so descriptor/table ABI alignment remains intact.
    localparam integer FRAME_BYTES = XRGB_STRIDE * FRAME_H;
    localparam integer FRAME_SLOT_BYTES =
        ((FRAME_BYTES + 16'h00ff) / 16'h0100) * 16'h0100;
    // The bounded hash store is intentionally retained for fast small-frame
    // regressions.  Native geometry switches to an address-keyed associative
    // store below so line collisions cannot masquerade as frame corruption.
    localparam logic USE_ASSOC_MEM = (FRAME_W >= 640);
    localparam integer MEM_SLOTS = 32768;

    // The generated 8x8 artifact is loaded only by the opt-in trained mode.
    // Keeping the arrays at the fixed ABI dimensions also lets the same
    // source elaborate in Icarus and Vivado without allocating a dense DDR
    // image.  The normal mode never reads these arrays.
    logic [511:0] trained_descriptors [0:21];
    logic [127:0] trained_parameter_mem [0:1055];

    logic core_clk = 1'b0;
    logic pixel_clk = 1'b0;
    logic camera_clk = 1'b0;
    logic arst_n = 1'b0;
    always #5 core_clk = ~core_clk;
    always #7 pixel_clk = ~pixel_clk;
    always #6 camera_clk = ~camera_clk;

    logic psel = 1'b0, penable = 1'b0, pwrite = 1'b0;
    logic [11:0] paddr = 12'd0;
    logic [31:0] pwdata = 32'd0, prdata;
    logic [3:0] pstrb = 4'd0;
    logic pready, pslverr, irq;

    logic camera_valid = 1'b0, camera_ready;
    logic [9:0] camera_raw10 = 10'd0;
    logic [CAM_X_W-1:0] camera_x = '0;
    logic [CAM_Y_W-1:0] camera_y = '0;
    logic camera_sof = 1'b0, camera_eol = 1'b0, camera_eof = 1'b0;
    logic camera_overflow;
    logic [23:0] video_rgb;
    logic video_de, video_hsync, video_vsync;
    logic [4:0] engine_stage_index;
    logic [7:0] engine_stage_opcode;
    logic engine_stage_active, engine_overflow_seen, system_busy;

    logic [31:0] awaddr, araddr;
    logic [7:0] awlen, arlen;
    logic [2:0] awsize, arsize;
    logic [1:0] awburst, arburst;
    logic awvalid, awready;
    logic [127:0] wdata;
    logic [15:0] wstrb;
    logic wlast, wvalid, wready;
    logic [1:0] bresp;
    logic bvalid, bready;
    logic arvalid, arready;
    logic [127:0] rdata;
    logic [1:0] rresp;
    logic rlast, rvalid, rready;

    c1_r1_portable_soc #(
        .FRAME_WIDTH(FRAME_W),
        .FRAME_HEIGHT(FRAME_H),
        .SENSOR_WIDTH(SENSOR_W),
        .SENSOR_HEIGHT(SENSOR_H),
        .ENABLE_TENSOR_WINDOW_CACHE(1),
        .ENABLE_TENSOR_BURST_REFILL(ENABLE_TENSOR_BURST_REFILL_CFG),
        .TENSOR_BURST_RSP_FIFO_BEAT_MODE(TENSOR_BURST_RSP_FIFO_BEAT_MODE_CFG),
        .TENSOR_BURST_RSP_FIFO_DEPTH(TENSOR_BURST_RSP_FIFO_DEPTH_CFG),
        .ENABLE_DISPLAY_RESPONSE_FIFO(DISPLAY_RESPONSE_FIFO_ENABLE),
        .DISPLAY_RESPONSE_FIFO_DEPTH(DISPLAY_RESPONSE_FIFO_DEPTH_CFG),
        .ENABLE_FABRIC_READ_RESPONSE_SKID(ENABLE_FABRIC_READ_RESPONSE_SKID_CFG),
        .ENABLE_TABLE_RESPONSE_FIFO(ENABLE_TABLE_RESPONSE_FIFO_CFG),
        .STRICT_DESCRIPTOR_VALIDATION(STRICT_DESCRIPTOR_VALIDATION_CFG),
        .PIPELINED_DESCRIPTOR_VALIDATION(PIPELINED_DESCRIPTOR_VALIDATION_CFG),
        .NARROW_DESCRIPTOR_SIZE_CHECK(NARROW_DESCRIPTOR_SIZE_CHECK_CFG),
        .PIPELINED_DESCRIPTOR_SIZE_ARITH(PIPELINED_DESCRIPTOR_SIZE_ARITH_CFG),
        .FIXED_DESCRIPTOR_SIZE_LIMITS(FIXED_DESCRIPTOR_SIZE_LIMITS_CFG),
        .PIPELINED_DESCRIPTOR_PIXEL_COUNT(PIPELINED_DESCRIPTOR_PIXEL_COUNT_CFG),
        .ITERATIVE_DESCRIPTOR_PIXEL_COUNT(ITERATIVE_DESCRIPTOR_PIXEL_COUNT_CFG),
        .PRECLAMPED_TAP_COORDS(PRECLAMPED_TAP_COORDS_CFG),
        .REGISTER_ABORT_RESET(REGISTER_ABORT_RESET_CFG),
        .FAST_TENSOR_ADDRESS_ARITH(FAST_TENSOR_ADDRESS_ARITH_CFG),
        .PIPELINED_TENSOR_ADDRESS(PIPELINED_TENSOR_ADDRESS_CFG),
        .PIPELINED_TENSOR_PIXEL_INDEX(PIPELINED_TENSOR_PIXEL_INDEX_CFG),
        .PIPELINED_START_CONFIG(PIPELINED_START_CONFIG_CFG),
        .PIPELINED_DOT_TREE(PIPELINED_DOT_TREE_CFG),
        .PIPELINED_DOT_TREE_FULL(PIPELINED_DOT_TREE_FULL_CFG),
        .PIPELINED_DESCRIPTOR_REPLAY(PIPELINED_DESCRIPTOR_REPLAY_CFG),
        .PREVALIDATE_DESCRIPTOR_REPLAY(PREVALIDATE_DESCRIPTOR_REPLAY_CFG),
        .PIPELINED_DECODER_VALIDATION(PIPELINED_DECODER_VALIDATION_CFG),
        .REPLICATE_ABORT_CONTROL(REPLICATE_ABORT_CONTROL_CFG),
        .REGISTER_FATAL_TICKET(REGISTER_FATAL_TICKET_CFG),
        .ENABLE_UNIFIED_OUTPUT_FIFO(ENABLE_UNIFIED_OUTPUT_FIFO_CFG),
        .ENABLE_UNIFIED_OUTPUT_SKID(ENABLE_UNIFIED_OUTPUT_SKID_CFG),
        .ENABLE_SHARED_QOS_MONITOR(ENABLE_SHARED_QOS_MONITOR_CFG),
        .SHARED_QOS_COUNTER_W(24),
        .SHARED_QOS_DEADLINE_CYCLES(SHARED_QOS_DEADLINE_CYCLES_CFG),
        .JOB_CYCLE_BUDGET(32'd1_000_000_000)
    ) dut (
        .core_clk(core_clk), .pixel_clk(pixel_clk), .camera_clk(camera_clk),
        .arst_n(arst_n),
        .psel(psel), .penable(penable), .pwrite(pwrite), .paddr(paddr),
        .pwdata(pwdata), .pstrb(pstrb), .prdata(prdata), .pready(pready),
        .pslverr(pslverr), .irq(irq),
        .camera_valid(camera_valid), .camera_ready(camera_ready),
        .camera_raw10(camera_raw10), .camera_x(camera_x), .camera_y(camera_y),
        .camera_sof(camera_sof), .camera_eol(camera_eol), .camera_eof(camera_eof),
        .camera_overflow(camera_overflow),
        .video_rgb(video_rgb), .video_de(video_de),
        .video_hsync(video_hsync), .video_vsync(video_vsync),
        .engine_stage_index(engine_stage_index),
        .engine_stage_opcode(engine_stage_opcode),
        .engine_stage_active(engine_stage_active),
        .engine_overflow_seen(engine_overflow_seen), .system_busy(system_busy),
        .m_axi_awaddr(awaddr), .m_axi_awlen(awlen), .m_axi_awsize(awsize),
        .m_axi_awburst(awburst), .m_axi_awvalid(awvalid), .m_axi_awready(awready),
        .m_axi_wdata(wdata), .m_axi_wstrb(wstrb), .m_axi_wlast(wlast),
        .m_axi_wvalid(wvalid), .m_axi_wready(wready),
        .m_axi_bresp(bresp), .m_axi_bvalid(bvalid), .m_axi_bready(bready),
        .m_axi_araddr(araddr), .m_axi_arlen(arlen), .m_axi_arsize(arsize),
        .m_axi_arburst(arburst), .m_axi_arvalid(arvalid), .m_axi_arready(arready),
        .m_axi_rdata(rdata), .m_axi_rresp(rresp), .m_axi_rlast(rlast),
        .m_axi_rvalid(rvalid), .m_axi_rready(rready)
    );

    // ------------------------------------------------------------------
    // Descriptor/table/parameter image helpers
    // ------------------------------------------------------------------
    function automatic [7:0] stage_opcode(input integer si);
        begin
            case (si)
                0,1,20: stage_opcode=8'd1;
                2,4,6,8,10,12,16,19: stage_opcode=8'd2;
                3,7,11,15,18: stage_opcode=8'd3;
                14,17: stage_opcode=8'd4;
                5,9,13: stage_opcode=8'd5;
                21: stage_opcode=8'd6;
                default: stage_opcode=8'd0;
            endcase
        end
    endfunction

    function automatic integer stage_cin(input integer si);
        begin
            case (si)
                0: stage_cin=3;
                1: stage_cin=12;
                2,5,6,9,10,13,14,15,16: stage_cin=24;
                3,4,7,8,11,12: stage_cin=48;
                17,18,19: stage_cin=16;
                20: stage_cin=8;
                21: stage_cin=3;
                default: stage_cin=0;
            endcase
        end
    endfunction

    function automatic integer stage_cout(input integer si);
        begin
            case (si)
                0: stage_cout=12;
                1,4,5,8,9,12,13,14,15: stage_cout=24;
                2,3,6,7,10,11: stage_cout=48;
                16,17,18: stage_cout=16;
                19: stage_cout=8;
                20,21: stage_cout=3;
                default: stage_cout=0;
            endcase
        end
    endfunction

    function automatic integer scale_width(input integer base_width);
        scale_width = (base_width * FRAME_W) / 8;
    endfunction

    function automatic integer scale_height(input integer base_height);
        scale_height = (base_height * FRAME_H) / 8;
    endfunction

    function automatic integer stage_iw(input integer si);
        integer base_width;
        begin
            if (si == 0) base_width=8;
            else if (si == 1) base_width=4;
            else if (si <= 14) base_width=2;
            else if (si <= 17) base_width=4;
            else base_width=8;
            stage_iw = scale_width(base_width);
        end
    endfunction

    function automatic integer stage_ih(input integer si);
        integer base_height;
        begin
            if (si == 0) base_height=8;
            else if (si == 1) base_height=4;
            else if (si <= 14) base_height=2;
            else if (si <= 17) base_height=4;
            else base_height=8;
            stage_ih = scale_height(base_height);
        end
    endfunction

    function automatic integer stage_ow(input integer si);
        integer base_width;
        begin
            if (si == 0) base_width=4;
            else if (si <= 13) base_width=2;
            else if (si <= 16) base_width=4;
            else base_width=8;
            stage_ow = scale_width(base_width);
        end
    endfunction

    function automatic integer stage_oh(input integer si);
        integer base_height;
        begin
            if (si == 0) base_height=4;
            else if (si <= 13) base_height=2;
            else if (si <= 16) base_height=4;
            else base_height=8;
            stage_oh = scale_height(base_height);
        end
    endfunction

    function automatic integer stage_act(input integer si);
        begin
            case (si)
                4,8,12,14,17,19,20,21: stage_act=0;
                default: stage_act=1;
            endcase
        end
    endfunction

    function automatic [511:0] make_descriptor(input integer si);
        logic [511:0] d;
        logic [7:0] op;
        integer iw,ih,ow,oh,cin,cout,act;
        begin
            op=stage_opcode(si); iw=stage_iw(si); ih=stage_ih(si);
            ow=stage_ow(si); oh=stage_oh(si); cin=stage_cin(si);
            cout=stage_cout(si); act=stage_act(si);
            d='0;
            d[7:0]=op; d[9:8]=act[1:0];
            d[23:16]=8'd1; d[31:24]=8'd16;
            d[47:32]=iw; d[63:48]=ih; d[79:64]=ow; d[95:80]=oh;
            d[111:96]=cin; d[127:112]=cout;
            d[455:448]=8'd8; d[463:456]=8'd1;
            d[471:464]=8'd1; d[479:472]=8'd1;
            if ((op==8'd1)||(op==8'd3)) begin
                d[423:416]=8'd3; d[431:424]=8'd3; d[10]=1'b1;
            end else begin
                d[423:416]=8'd1; d[431:424]=8'd1;
            end
            if ((si==0)||(si==1)) begin
                d[439:432]=8'd2; d[447:440]=8'd2;
            end else if (op==8'd4) begin
                d[439:432]=8'd2; d[447:440]=8'd2;
            end else begin
                d[439:432]=8'd1; d[447:440]=8'd1;
            end
            if (op==8'd5) d[11]=1'b1;
            if (si==0) d[12]=1'b1;
            if (si==21) d[13]=1'b1;
            d[511:480]=32'd1_000_000;
            make_descriptor=d;
        end
    endfunction

    // Keep each frame-manager buffer index on a distinct frame-sized,
    // 0x100-aligned slot.  This is required for serialized multi-frame runs:
    // a fixed 0x100 stride would overlap 64x48 (12 KiB) image buffers.
    function automatic [127:0] table_entry(input logic [31:0] base,
                                           input integer index);
        logic [127:0] t;
        begin
            t='0;
            t[63:0]=base + (index * FRAME_SLOT_BYTES);
            t[95:64]=XRGB_STRIDE;
            t[111:96]=FRAME_W;
            t[127:112]=FRAME_H;
            table_entry=t;
        end
    endfunction

    // The default parameter image is intentionally all zero.  In the
    // opt-in trained-artifact mode this function instead exposes the exact
    // 16-byte words exported by the QAT arena, while preserving the same DDR
    // address contract used by the parameter loader.
    function automatic [127:0] parameter_word(input logic [31:0] addr);
        integer parameter_index;
        begin
            parameter_word = 128'd0;
            if (TRAINED_ARTIFACT_CFG &&
                (addr >= WEIGHT_BASE) &&
                (addr < (WEIGHT_BASE + 32'd16896)) &&
                (addr[3:0] == 4'd0)) begin
                parameter_index = (addr - WEIGHT_BASE) >> 4;
                if ((parameter_index >= 0) && (parameter_index < 1056))
                    parameter_word = trained_parameter_mem[parameter_index];
            end
        end
    endfunction

    // ------------------------------------------------------------------
    // Sparse 128-bit line store for frame/tensor writes
    // ------------------------------------------------------------------
    logic mem_valid [0:MEM_SLOTS-1];
    logic [31:0] mem_tag [0:MEM_SLOTS-1];
    logic [127:0] mem_line [0:MEM_SLOTS-1];
    // Native mode uses the full AXI line address as the key.  This remains a
    // testbench-only data structure and grows only for lines actually touched
    // by the run; it avoids the 32K modulo-hash collision limit.
    logic [127:0] mem_line_assoc [longint unsigned];

    function automatic integer line_index(input logic [31:0] addr);
        // Mix the high address bits before the bounded sparse-store index.
        // INPUT/OUTPUT/TENSOR bases are intentionally far apart but share
        // low modulo bits; direct mapping would make a two-frame ownership
        // test look like an overwrite even when the AXI address is correct.
        line_index = ((addr[31:4] ^ (addr[31:4] >> 13) ^
                       (addr[31:4] >> 26)) % MEM_SLOTS);
    endfunction

    function automatic [127:0] read_beat(input logic [31:0] addr);
        logic [127:0] value;
        logic [511:0] descriptor_value;
        longint unsigned assoc_key;
        integer di, beat, idx, table_idx;
        begin
            value='0;
            assoc_key = addr[31:4];
            if ((addr >= DESC_BASE) && (addr < DESC_BASE + 32'd1408)) begin
                di=(addr-DESC_BASE)>>6; beat=((addr-DESC_BASE)>>4)&3;
                if (TRAINED_ARTIFACT_CFG && (di >= 0) && (di < 22))
                    descriptor_value=trained_descriptors[di];
                else
                    descriptor_value=make_descriptor(di);
                case (beat)
                    0: value=descriptor_value[127:0];
                    1: value=descriptor_value[255:128];
                    2: value=descriptor_value[383:256];
                    default: value=descriptor_value[511:384];
                endcase
            end else if ((addr >= IN_TABLE) && (addr < IN_TABLE+32'd64)) begin
                table_idx=(addr-IN_TABLE)>>4;
                value=table_entry(INPUT_BASE,table_idx);
            end else if ((addr >= OUT_TABLE) && (addr < OUT_TABLE+32'd64)) begin
                table_idx=(addr-OUT_TABLE)>>4;
                value=table_entry(OUTPUT_BASE,table_idx);
            end else if ((addr >= WEIGHT_BASE) &&
                         (addr < WEIGHT_BASE+32'd16896)) begin
                value=parameter_word(addr);
            end else begin
                if (USE_ASSOC_MEM) begin
                    if (mem_line_assoc.exists(assoc_key))
                        value=mem_line_assoc[assoc_key];
                    else
                        value={32'hc1dd_0000,addr,addr+32'd16,addr+32'd32};
                end else begin
                    idx=line_index(addr);
                    if (mem_valid[idx] && (mem_tag[idx] == addr[31:4]))
                        value=mem_line[idx];
                    else
                        value={32'hc1dd_0000,addr,addr+32'd16,addr+32'd32};
                end
            end
            read_beat=value;
        end
    endfunction

    task automatic store_beat(
        input logic [31:0] addr,
        input logic [127:0] data,
        input logic [15:0] strb
    );
        longint unsigned assoc_key;
        integer idx, lane;
        begin
            assoc_key = addr[31:4];
            if (USE_ASSOC_MEM) begin
                if (!mem_line_assoc.exists(assoc_key))
                    mem_line_assoc[assoc_key]='0;
                for (lane=0; lane<16; lane=lane+1)
                    if (strb[lane])
                        mem_line_assoc[assoc_key][lane*8 +: 8]=
                            data[lane*8 +: 8];
            end else begin
                idx=line_index(addr);
                if (!mem_valid[idx] || (mem_tag[idx] != addr[31:4])) begin
                    mem_valid[idx]=1'b1;
                    mem_tag[idx]=addr[31:4];
                    mem_line[idx]='0;
                end
                for (lane=0; lane<16; lane=lane+1)
                    if (strb[lane]) mem_line[idx][lane*8 +: 8]=data[lane*8 +: 8];
            end
        end
    endtask

    // ------------------------------------------------------------------
    // AXI128 slave BFM: independent channel stalls and held responses
    // ------------------------------------------------------------------
    integer cycle_count=0;
    integer axi_aw_count=0, axi_w_count=0, axi_b_count=0;
    integer axi_ar_count=0, axi_r_count=0;
    integer trained_weight_ar_count=0;
    integer aw_stall_count=0, w_stall_count=0, ar_stall_count=0;
    integer r_stall_count=0, fabric_r_stall_count=0, b_stall_count=0;
    integer r_gap_count=0, b_gap_count=0;
    logic aw_active=1'b0, b_pending=1'b0, bvalid_q=1'b0;
    logic [31:0] aw_base_q=32'd0;
    logic [7:0] aw_len_q=8'd0;
    integer w_index_q=0, b_delay_q=0;
    logic r_active=1'b0, rvalid_q=1'b0;
    logic [31:0] ar_base_q=32'd0;
    logic [7:0] ar_len_q=8'd0;
    integer r_index_q=0, r_delay_q=0;
    logic [127:0] rdata_q=128'd0;
    logic rlast_q=1'b0;
    always_comb begin
        awready = !aw_active && !b_pending && !bvalid_q &&
                  ((cycle_count % 7) != 0);
        wready = aw_active && !b_pending && !bvalid_q &&
                 ((cycle_count % 5) != 0);
        arready = !r_active && !rvalid_q && ((cycle_count % 6) != 0);
        bvalid = bvalid_q;
        bresp = 2'b00;
        rvalid = rvalid_q;
        rdata = rdata_q;
        rresp = 2'b00;
        rlast = rlast_q;
    end

    always @(posedge core_clk) begin : axi_bfm_proc
        integer write_addr;
        if (!arst_n) begin
            cycle_count <= 0;
            aw_active <= 1'b0; b_pending <= 1'b0; bvalid_q <= 1'b0;
            r_active <= 1'b0; rvalid_q <= 1'b0;
            w_index_q <= 0; r_index_q <= 0;
            b_delay_q <= 0; r_delay_q <= 0;
            axi_aw_count <= 0; axi_w_count <= 0; axi_b_count <= 0;
            axi_ar_count <= 0; axi_r_count <= 0;
            trained_weight_ar_count <= 0;
            aw_stall_count <= 0; w_stall_count <= 0; ar_stall_count <= 0;
            r_stall_count <= 0; fabric_r_stall_count <= 0;
            b_stall_count <= 0;
            r_gap_count <= 0; b_gap_count <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
            if (awvalid && !awready) aw_stall_count <= aw_stall_count + 1;
            if (wvalid && !wready) w_stall_count <= w_stall_count + 1;
            if (arvalid && !arready) ar_stall_count <= ar_stall_count + 1;
            if (rvalid_q && !rready) r_stall_count <= r_stall_count + 1;
            // A registered fabric response boundary can absorb all DDR-side
            // R stalls while still exercising backpressure at the selected
            // client.  Count both boundaries so the stress requirement is
            // preserved instead of being weakened for the skid build.
            if (|(dut.axi_s_rvalid & ~dut.axi_s_rready))
                fabric_r_stall_count <= fabric_r_stall_count + 1;
            if (bvalid_q && !bready) b_stall_count <= b_stall_count + 1;

            if (awvalid && awready) begin
                if ((awsize !== 3'd4) || (awburst !== 2'b01))
                    $fatal(1,"portable SoC emitted malformed AW");
                aw_active <= 1'b1;
                aw_base_q <= awaddr;
                aw_len_q <= awlen;
                w_index_q <= 0;
                axi_aw_count <= axi_aw_count + 1;
            end

            if (wvalid && wready) begin
                if (!aw_active) $fatal(1,"W accepted without AW");
                if (wlast !== (w_index_q == aw_len_q))
                    $fatal(1,"W.last mismatch addr=%08x beat=%0d len=%0d",
                           aw_base_q,w_index_q,aw_len_q);
                write_addr = aw_base_q + (w_index_q * 16);
                store_beat(write_addr,wdata,wstrb);
                axi_w_count <= axi_w_count + 1;
                if (wlast) begin
                    aw_active <= 1'b0;
                    b_pending <= 1'b1;
                    b_delay_q <= 2 + (cycle_count % 3);
                end else begin
                    w_index_q <= w_index_q + 1;
                end
            end

            if (b_pending && !bvalid_q) begin
                if (b_delay_q > 0) begin
                    b_delay_q <= b_delay_q - 1;
                    b_gap_count <= b_gap_count + 1;
                end else begin
                    bvalid_q <= 1'b1;
                end
            end
            if (bvalid_q && bready) begin
                bvalid_q <= 1'b0;
                b_pending <= 1'b0;
                axi_b_count <= axi_b_count + 1;
            end

            if (arvalid && arready) begin
                if ((arsize !== 3'd4) || (arburst !== 2'b01))
                    $fatal(1,"portable SoC emitted malformed AR");
                if (TRAINED_ARTIFACT_CFG &&
                    (araddr >= WEIGHT_BASE) &&
                    (araddr < (WEIGHT_BASE + 32'd16896)))
                    trained_weight_ar_count <= trained_weight_ar_count + 1;
                r_active <= 1'b1;
                ar_base_q <= araddr;
                ar_len_q <= arlen;
                r_index_q <= 0;
                r_delay_q <= 1 + (cycle_count % 3);
                axi_ar_count <= axi_ar_count + 1;
            end

            if (r_active && !rvalid_q) begin
                if (r_delay_q > 0) begin
                    r_delay_q <= r_delay_q - 1;
                    r_gap_count <= r_gap_count + 1;
                end else begin
                    rdata_q <= read_beat(ar_base_q + (r_index_q * 16));
                    rlast_q <= (r_index_q == ar_len_q);
                    rvalid_q <= 1'b1;
                end
            end
            if (rvalid_q && rready) begin
                rvalid_q <= 1'b0;
                axi_r_count <= axi_r_count + 1;
                if (rlast_q) begin
                    r_active <= 1'b0;
                end else begin
                    r_index_q <= r_index_q + 1;
                    r_delay_q <= 1 + ((cycle_count + r_index_q) % 2);
                end
            end
        end
    end

    // ------------------------------------------------------------------
    // APB and camera stimulus
    // ------------------------------------------------------------------
    task automatic apb_write(input logic [11:0] address,
                              input logic [31:0] data);
        begin
            @(negedge core_clk);
            psel<=1'b1; penable<=1'b0; pwrite<=1'b1;
            paddr<=address; pwdata<=data; pstrb<=4'hf;
            @(negedge core_clk); penable<=1'b1;
            do @(negedge core_clk); while (!pready);
            if (pslverr) $fatal(1,"APB write error addr=%03x",address);
            psel<=1'b0; penable<=1'b0; pwrite<=1'b0;
            paddr<=12'd0; pwdata<=32'd0; pstrb<=4'd0;
        end
    endtask

    task automatic apb_read(input logic [11:0] address,
                             output logic [31:0] data);
        begin
            @(negedge core_clk);
            psel<=1'b1; penable<=1'b0; pwrite<=1'b0; paddr<=address;
            @(negedge core_clk); penable<=1'b1;
            do @(negedge core_clk); while (!pready);
            data=prdata;
            if (pslverr) $fatal(1,"APB read error addr=%03x",address);
            psel<=1'b0; penable<=1'b0; paddr<=12'd0;
        end
    endtask

    task automatic send_camera_frame(input logic [9:0] tone_offset);
        integer x,y;
        begin
            for (y=0; y<SENSOR_H; y=y+1) begin
                for (x=0; x<SENSOR_W; x=x+1) begin
                    @(negedge camera_clk);
                    camera_valid<=1'b1;
                    camera_x<=x[CAM_X_W-1:0]; camera_y<=y[CAM_Y_W-1:0];
                    camera_raw10<=((x*17)+(y*29)+10'h40+tone_offset) & 10'h3ff;
                    camera_sof<=(x==0)&&(y==0);
                    camera_eol<=(x==SENSOR_W-1);
                    camera_eof<=(x==SENSOR_W-1)&&(y==SENSOR_H-1);
                    do @(posedge camera_clk); while (!camera_ready);
                end
            end
            @(negedge camera_clk);
            camera_valid<=1'b0; camera_sof<=1'b0;
            camera_eol<=1'b0; camera_eof<=1'b0;
        end
    endtask

    integer done_seen=0;
    integer error_seen=0;
    integer descriptor_fire_count=0;
    logic [21:0] descriptor_stage_seen=22'd0;
    logic display_done_seen=1'b0;
    integer display_swap_count=0;
    integer qos_start_count=0;
    integer qos_prefetch_done_count=0;
    integer qos_new_done_count=0;
    integer qos_swap_event_count=0;
    integer capture_drop_count=0;
    always @(posedge core_clk) begin
        if (arst_n) begin
            if (dut.control_done_event) done_seen <= done_seen + 1;
            if (dut.control_error_event) begin
                error_seen <= error_seen + 1;
                $display("portable SoC control error code=%02x addr=%08x",
                         dut.control_error_code,dut.control_error_address);
            end
            if (dut.u_microstyle.u_cnn.u_engine.raw_descriptor_fire) begin
                descriptor_fire_count <= descriptor_fire_count + 1;
                descriptor_stage_seen[dut.u_microstyle.u_cnn.u_engine.stage_index_q] <= 1'b1;
            end
            if (dut.display_prefetch_done)
                begin
                    display_done_seen <= 1'b1;
                    qos_prefetch_done_count <= qos_prefetch_done_count + 1;
                end
            if (dut.display_prefetch_new_done_event)
                qos_new_done_count <= qos_new_done_count + 1;
            if (dut.control_display_swap_event)
                begin
                    display_swap_count <= display_swap_count + 1;
                    qos_swap_event_count <= qos_swap_event_count + 1;
                end
            if (dut.qos_frame_start_event)
                qos_start_count <= qos_start_count + 1;
            if (dut.control_capture_drop_event)
                capture_drop_count <= capture_drop_count + 1;
            if (dut.u_microstyle.cnn_error || dut.u_boardless.compute_error ||
                dut.u_control.fatal_now) begin
                // Keep the failure actionable for scaled-frame bring-up: an
                // engine cycle-budget error usually means that a stage is
                // waiting for a missing/incorrectly shaped input beat, not
                // that the DDR BFM merely ran out of sparse storage.
                $display("diag bases input=%08x output=%08x capture=%08x/%0dx%0d writer_busy=%0b writer_done=%0b writer_err=%0b",
                         dut.u_boardless.resolved_input_base,
                         dut.u_boardless.resolved_output_base,
                         dut.u_control.capture_writer_base,
                         dut.u_control.capture_writer_width,
                         dut.u_control.capture_writer_height,
                         dut.u_capture.u_writer.busy,
                         dut.u_capture.u_writer.done,
                         dut.u_capture.u_writer.error);
                $display("diag input_dma state=%0d busy/done/err=%0b/%0b/%0b row=%0d addr=%08x row_beats=%0d burst=%0d/%0d lane=%0d xy=%0d,%0d shell_ready=%0b stream=%0b/%0b/%0b/%0b/%0b",
                         dut.u_boardless.u_input_dma.state,
                         dut.u_boardless.u_input_dma.busy,
                         dut.u_boardless.u_input_dma.done,
                         dut.u_boardless.u_input_dma.error,
                         dut.u_boardless.u_input_dma.current_row,
                         dut.u_boardless.u_input_dma.current_addr,
                         dut.u_boardless.u_input_dma.row_beats_remaining,
                         dut.u_boardless.u_input_dma.burst_beat_index,
                         dut.u_boardless.u_input_dma.burst_beats_target,
                         dut.u_boardless.u_input_dma.pixel_lane,
                         dut.u_boardless.u_input_dma.output_x,
                         dut.u_boardless.u_input_dma.output_y,
                         dut.u_boardless.shell_dma_ready,
                         dut.u_boardless.input_stream_valid,
                         dut.u_boardless.input_stream_ready,
                         dut.u_boardless.input_stream_sof,
                         dut.u_boardless.input_stream_eol,
                         dut.u_boardless.input_stream_eof);
                $display("diag axi reader ar=%0b/%0b addr=%08x len=%0d active=%0b rvalid=%0b idx=%0d/%0d base=%08x",
                         dut.u_boardless.reader_arvalid,
                         dut.u_boardless.reader_arready,
                         dut.u_boardless.reader_araddr,
                         dut.u_boardless.reader_arlen,
                         r_active,
                         rvalid_q,
                         r_index_q,
                         ar_len_q,
                         ar_base_q);
                $display("diag ingress active=%0b resize_busy=%0b resize_req=%0b/%0b out=%0b/%0b xy=%0d,%0d",
                         dut.u_boardless.u_compute_shell.u_compute_ingress.ingress_active,
                         dut.u_boardless.u_compute_shell.u_compute_ingress.resize_busy,
                         dut.u_boardless.u_compute_shell.u_compute_ingress.u_resize_pipeline.u_resize_system.u_request.busy,
                         dut.u_boardless.u_compute_shell.u_compute_ingress.u_resize_pipeline.u_resize_system.u_request.req_valid,
                         dut.u_boardless.u_compute_shell.u_compute_ingress.u_resize_pipeline.u_resize_system.out_valid,
                         dut.u_boardless.u_compute_shell.u_compute_ingress.u_resize_pipeline.u_resize_system.out_ready,
                         dut.u_boardless.u_compute_shell.u_compute_ingress.u_resize_pipeline.u_resize_system.out_x,
                         dut.u_boardless.u_compute_shell.u_compute_ingress.u_resize_pipeline.u_resize_system.out_y);
                $display("diag sampler src=%0b/%0b expected=%0d,%0d done=%0b rows=%0b/%0b tags=%0d/%0d req=%0b/%0b",
                         dut.u_boardless.u_compute_shell.u_compute_ingress.u_resize_pipeline.u_line_sampler.src_valid,
                         dut.u_boardless.u_compute_shell.u_compute_ingress.u_resize_pipeline.u_line_sampler.src_ready,
                         dut.u_boardless.u_compute_shell.u_compute_ingress.u_resize_pipeline.u_line_sampler.expected_src_x,
                         dut.u_boardless.u_compute_shell.u_compute_ingress.u_resize_pipeline.u_line_sampler.expected_src_y,
                         dut.u_boardless.u_compute_shell.u_compute_ingress.u_resize_pipeline.u_line_sampler.source_done,
                         dut.u_boardless.u_compute_shell.u_compute_ingress.u_resize_pipeline.u_line_sampler.line0_valid,
                         dut.u_boardless.u_compute_shell.u_compute_ingress.u_resize_pipeline.u_line_sampler.line1_valid,
                         dut.u_boardless.u_compute_shell.u_compute_ingress.u_resize_pipeline.u_line_sampler.line0_y,
                         dut.u_boardless.u_compute_shell.u_compute_ingress.u_resize_pipeline.u_line_sampler.line1_y,
                         dut.u_boardless.u_compute_shell.u_compute_ingress.u_resize_pipeline.u_resize_system.sample_req_valid,
                         dut.u_boardless.u_compute_shell.u_compute_ingress.u_resize_pipeline.u_resize_system.sample_req_ready);
                $display("diag adapter state=%0d stage=%0d src=%0d,%0d out=%0d,%0d err=%0b/%02x cfg=%0b mem=%0b/%0b cache=%0b/%0b",
                         dut.u_tensor_adapter.state_q,
                         dut.u_tensor_adapter.stage_index_q,
                         dut.u_tensor_adapter.source_x_q,
                         dut.u_tensor_adapter.source_y_q,
                         dut.u_tensor_adapter.output_x_q,
                         dut.u_tensor_adapter.output_y_q,
                         dut.u_tensor_adapter.error_q,
                         dut.u_tensor_adapter.error_code_q,
                         dut.u_tensor_adapter.config_complete_q,
                         dut.u_tensor_adapter.mem_req_valid,
                         dut.u_tensor_adapter.mem_rsp_valid,
                         dut.tensor_cache_busy,
                         dut.tensor_cache_quiescent);
`ifdef C1_TENSOR_BURST_REFILL
                $display("diag burst_client owner=%0d bridge_inflight=%0b route_burst=%0b route_bridge=%0b stage_en=%0b reject=%0b cfg=%0b burst_busy=%0b burst_q=%0b tap=%0b/%0b bridge_req=%0b/%0b rsp=%0b/%0b",
                         dut.g_tensor_burst_refill.u_tensor_cache_axi_client.owner_q,
                         dut.g_tensor_burst_refill.u_tensor_cache_axi_client.bridge_inflight_q,
                         dut.g_tensor_burst_refill.u_tensor_cache_axi_client.route_burst,
                         dut.g_tensor_burst_refill.u_tensor_cache_axi_client.route_bridge,
                         dut.g_tensor_burst_refill.u_tensor_cache_axi_client.stage_cache_enable_q,
                         dut.g_tensor_burst_refill.u_tensor_cache_axi_client.stage_reject_q,
                         dut.g_tensor_burst_refill.u_tensor_cache_axi_client.burst_config_valid,
                         dut.g_tensor_burst_refill.u_tensor_cache_axi_client.burst_busy,
                         dut.g_tensor_burst_refill.u_tensor_cache_axi_client.burst_quiescent,
                         dut.g_tensor_burst_refill.u_tensor_cache_axi_client.burst_tap_valid,
                         dut.g_tensor_burst_refill.u_tensor_cache_axi_client.burst_tap_ready,
                         dut.g_tensor_burst_refill.u_tensor_cache_axi_client.bridge_req_valid,
                         dut.g_tensor_burst_refill.u_tensor_cache_axi_client.bridge_req_ready,
                         dut.g_tensor_burst_refill.u_tensor_cache_axi_client.s_rsp_valid,
                         dut.g_tensor_burst_refill.u_tensor_cache_axi_client.s_rsp_ready);
                $display("diag burst_shell cache_cfg=%0b cache_busy/q=%0b/%0b exact_busy/q=%0b/%0b cmd_hold=%0b start_gate=%0b cache_tap=%0b/%0b refill=%0b/%0b exact_cmd=%0b/%0b",
                         dut.g_tensor_burst_refill.u_tensor_cache_axi_client.u_burst_cache.cache_config_valid,
                         dut.g_tensor_burst_refill.u_tensor_cache_axi_client.u_burst_cache.cache_busy,
                         dut.g_tensor_burst_refill.u_tensor_cache_axi_client.u_burst_cache.cache_quiescent,
                         dut.g_tensor_burst_refill.u_tensor_cache_axi_client.u_burst_cache.exact_busy,
                         dut.g_tensor_burst_refill.u_tensor_cache_axi_client.u_burst_cache.exact_quiescent,
                         dut.g_tensor_burst_refill.u_tensor_cache_axi_client.u_burst_cache.cmd_hold_valid_q,
                         dut.g_tensor_burst_refill.u_tensor_cache_axi_client.u_burst_cache.start_gate,
                         dut.g_tensor_burst_refill.u_tensor_cache_axi_client.u_burst_cache.cache_tap_ready,
                         dut.g_tensor_burst_refill.u_tensor_cache_axi_client.u_burst_cache.tap_ready,
                         dut.g_tensor_burst_refill.u_tensor_cache_axi_client.u_burst_cache.cache_refill_req_valid,
                         dut.g_tensor_burst_refill.u_tensor_cache_axi_client.u_burst_cache.cache_refill_req_ready,
                         dut.g_tensor_burst_refill.u_tensor_cache_axi_client.u_burst_cache.exact_cmd_valid,
                         dut.g_tensor_burst_refill.u_tensor_cache_axi_client.u_burst_cache.exact_cmd_ready);
                $display("diag burst_deep cache_state=%0d refill_index=%0d addr_pending=%0b read_pending=%0b tap_rsp=%0b exact_core_busy/q=%0b/%0b core_cmd_occ=%0d core_out=%0d comp_active=%0b synth=%0b comp_words=%0d",
                         dut.g_tensor_burst_refill.u_tensor_cache_axi_client.u_burst_cache.u_cache.state_q,
                         dut.g_tensor_burst_refill.u_tensor_cache_axi_client.u_burst_cache.u_cache.refill_word_index_q,
                         dut.g_tensor_burst_refill.u_tensor_cache_axi_client.u_burst_cache.u_cache.address_pending_q,
                         dut.g_tensor_burst_refill.u_tensor_cache_axi_client.u_burst_cache.u_cache.read_pending_q,
                         dut.g_tensor_burst_refill.u_tensor_cache_axi_client.u_burst_cache.u_cache.tap_rsp_valid_q,
                         dut.g_tensor_burst_refill.u_tensor_cache_axi_client.u_burst_cache.u_exact.core_busy,
                         dut.g_tensor_burst_refill.u_tensor_cache_axi_client.u_burst_cache.u_exact.core_quiescent,
                         dut.g_tensor_burst_refill.u_tensor_cache_axi_client.u_burst_cache.u_exact.core_cmd_occupancy,
                         dut.g_tensor_burst_refill.u_tensor_cache_axi_client.u_burst_cache.u_exact.core_outstanding,
                         dut.g_tensor_burst_refill.u_tensor_cache_axi_client.u_burst_cache.u_exact.u_completion.active_q,
                         dut.g_tensor_burst_refill.u_tensor_cache_axi_client.u_burst_cache.u_exact.u_completion.synthetic_q,
                         dut.g_tensor_burst_refill.u_tensor_cache_axi_client.u_burst_cache.u_exact.u_completion.next_index_q);
`endif
                $fatal(1,"portable SoC compute/control error code=%02x/%02x/%02x stage=%0d state=%0d stage_cycle=%0d budget=%0d dims=%0dx%0d->%0dx%0d exp=%0d,%0d grp=%0d in=%0b/%0b xy=%0d,%0d sof/eol/eof=%0b/%0b/%0b resolved=%0dx%0d->%0dx%0d dma=%0dx%0d idx=%0d/%0d cfg_h=%0d",
                       dut.u_microstyle.cnn_error_code,
                       dut.u_boardless.compute_error_code,
                       dut.u_control.fatal_code,
                       dut.u_microstyle.u_cnn.u_engine.stage_index_q,
                       dut.u_microstyle.u_cnn.u_engine.state_q,
                       dut.u_microstyle.u_cnn.u_engine.stage_cycle_q,
                       dut.u_microstyle.u_cnn.u_engine.cycle_budget_q,
                       dut.u_microstyle.u_cnn.u_engine.input_width_q,
                       dut.u_microstyle.u_cnn.u_engine.input_height_q,
                       dut.u_microstyle.u_cnn.u_engine.output_width_q,
                       dut.u_microstyle.u_cnn.u_engine.output_height_q,
                       dut.u_microstyle.u_cnn.u_engine.expected_x_q,
                       dut.u_microstyle.u_cnn.u_engine.expected_y_q,
                       dut.u_microstyle.u_cnn.u_engine.expected_input_group_q,
                       dut.u_microstyle.u_cnn.u_engine.in_valid,
                       dut.u_microstyle.u_cnn.u_engine.in_ready,
                       dut.u_microstyle.u_cnn.u_engine.in_x,
                       dut.u_microstyle.u_cnn.u_engine.in_y,
                       dut.u_microstyle.u_cnn.u_engine.in_sof,
                        dut.u_microstyle.u_cnn.u_engine.in_eol,
                        dut.u_microstyle.u_cnn.u_engine.in_eof,
                        dut.u_boardless.resolved_input_width,
                       dut.u_boardless.resolved_input_height,
                       dut.u_boardless.resolved_output_width,
                       dut.u_boardless.resolved_output_height,
                       dut.u_boardless.u_input_dma.width_reg,
                       dut.u_boardless.u_input_dma.height_reg,
                       dut.u_control.nn_input_index_q,
                        dut.u_control.manager_nn_input_index,
                        dut.u_control.cfg_frame_height_q);
            end
            if (engine_overflow_seen || camera_overflow)
                $fatal(1,"capture/engine overflow asserted");
            if (dut.qos_frame_start_event || dut.display_prefetch_done ||
                dut.display_prefetch_new_done_event ||
                dut.control_display_swap_event) begin
`ifdef C1_SHARED_QOS_MONITOR
                $display("C1_QOS_EVENT t=%0t start=%0b raw_done=%0b new_done=%0b swap=%0b active_tag=%0b loading_new=%0b request_new=%0b prefetch_busy=%0b monitor_active=%0b monitor_frame=%0d",
                         $time,dut.qos_frame_start_event,
                         dut.display_prefetch_done,
                         dut.display_prefetch_new_done_event,
                         dut.control_display_swap_event,
                         dut.u_control.prefetch_active_is_new_q,
                         dut.u_control.prefetch_loading_new_q,
                         dut.u_control.prefetch_request_is_new_q,
                         dut.display_prefetch_busy,
                         dut.g_shared_qos_monitor.u_monitor.frame_active,
                         dut.g_shared_qos_monitor.u_monitor.frame_count);
`else
                // Keep the event trace format stable without referring to the
                // optional monitor hierarchy when it is compiled out.
                $display("C1_QOS_EVENT t=%0t start=%0b raw_done=%0b new_done=%0b swap=%0b active_tag=%0b loading_new=%0b request_new=%0b prefetch_busy=%0b monitor_active=0 monitor_frame=0",
                         $time,dut.qos_frame_start_event,
                         dut.display_prefetch_done,
                         dut.display_prefetch_new_done_event,
                         dut.control_display_swap_event,
                         dut.u_control.prefetch_active_is_new_q,
                         dut.u_control.prefetch_loading_new_q,
                         dut.u_control.prefetch_request_is_new_q,
                         dut.display_prefetch_busy);
`endif
            end
        end
    end

    initial begin : main_test
        logic [31:0] status_word;
        logic [31:0] qos_apb_status;
        logic [31:0] qos_apb_frame_count;
        logic [31:0] qos_apb_last_frame;
        logic [31:0] qos_apb_deadline;
        logic [31:0] qos_apb_underflow;
        logic [31:0] qos_apb_read_busy;
        logic [31:0] qos_apb_write_busy;
        logic [31:0] qos_apb_read_owner_max;
        logic [31:0] qos_apb_write_owner_max;
        logic [31:0] qos_apb_protocol;
        integer wait_cycles;
        integer i;
        integer first_descriptor_count;
        integer first_swap_count;
        if (TRAINED_ARTIFACT_CFG) begin
            // The detached runner copies these compact files into its
            // disposable working directory.  A direct Icarus invocation can
            // do the same before starting vvp.  No large simulator database
            // is needed; the arrays contain only the descriptor/arena ABI.
            $readmemh("trained_descriptors.mem", trained_descriptors);
            $readmemh("trained_parameter_arena.mem", trained_parameter_mem);
        end
        if ((FRAME_W >= 640) &&
            (OUTPUT_BASE <= (INPUT_BASE + (3 * FRAME_SLOT_BYTES))))
            $fatal(1, "native frame table address regions overlap input=%08x output=%08x slot=%0d",
                   INPUT_BASE, OUTPUT_BASE, FRAME_SLOT_BYTES);
        if ((FRAME_W >= 640) &&
            ((OUTPUT_BASE + (2 * FRAME_SLOT_BYTES)) >= TENSOR_BASE))
            $fatal(1, "native output arena overlaps tensor arena output=%08x tensor=%08x",
                   OUTPUT_BASE, TENSOR_BASE);
        if ((FRAME_W >= 640) && !USE_ASSOC_MEM)
            $fatal(1, "native frame requires address-keyed DDR store");
        for (i=0;i<MEM_SLOTS;i=i+1) begin
            mem_valid[i]=1'b0; mem_tag[i]=32'd0; mem_line[i]=128'd0;
        end

        repeat (8) @(posedge core_clk);
        arst_n <= 1'b1;
        repeat (12) @(posedge core_clk);

        // The ISP CSR reset image is already a legal identity configuration.
        // Leave it uncommitted here: cfg_valid=0 makes the capture frontend
        // use that reset image immediately, avoiding a needless APB commit
        // race while the three clock domains are still releasing.
        repeat (20) @(posedge core_clk);

        // Legal parameterized job image.  Descriptor count remains the frozen
        // 22; the descriptor graph itself is intentionally independent of the
        // outer capture/display scale used by this BFM.
        apb_write(12'h040,IN_TABLE);
        apb_write(12'h048,OUT_TABLE);
        apb_write(12'h050,((FRAME_H << 16) | FRAME_W));
        apb_write(12'h054,XRGB_STRIDE);
        apb_write(12'h058,XRGB_STRIDE);
        apb_write(12'h05c,32'h0000_0022);
        apb_write(12'h080,DESC_BASE);
        apb_write(12'h088,32'd22);
        apb_write(12'h090,WEIGHT_BASE);
        apb_write(12'h098,TENSOR_BASE);
        apb_write(12'h0c0,32'd0);

        // Enable and arm one frame.  The camera source starts only after the
        // START edge, so the capture FIFO cannot silently discard its SOF.
        apb_write(12'h010,32'h1);
        apb_read(12'h010,status_word);
        $display("after enable CONTROL=%08x csr_enable=%0b",status_word,dut.csr_system_enable);
        apb_write(12'h010,32'h13);
        $display("after start write csr_enable=%0b start_pulse=%0b run_armed=%0b",
                 dut.csr_system_enable,dut.csr_start_pulse,dut.u_control.run_armed_q);
        // Do not rely on the relative phase of camera/core clocks for SOF
        // admission.  Wait until the one-shot arm is visible in the core
        // domain and idle-frame discard is closed.
        wait_cycles=0;
        while ((!dut.u_control.run_armed_q || dut.capture_discard_idle) &&
               (wait_cycles < 1000)) begin
            @(posedge core_clk);
            wait_cycles=wait_cycles+1;
        end
        if (!dut.u_control.run_armed_q || dut.capture_discard_idle)
            $fatal(1,"camera started before one-shot admission opened");
        send_camera_frame(10'd0);

        wait_cycles=0;
        while ((done_seen==0) && (error_seen==0) && (wait_cycles<20_000_000)) begin
            @(posedge core_clk);
            wait_cycles=wait_cycles+1;
        end
        if (error_seen!=0)
            $fatal(1,"portable SoC reported a control error");
        if (done_seen==0)
            $fatal(1,"portable SoC small-frame job timed out");

        // The display subsystem intentionally uses the real 720p raster
        // timing, even in this small-frame regression.  Its two-line stores
        // cannot release the third line until the pixel domain reaches the
        // corresponding active line, and request enable is committed only at
        // a local frame boundary.  The guard therefore covers one complete
        // 720p frame plus margin rather than a short arbitrary drain.
        wait_cycles = 0;
        while ((system_busy || !display_done_seen) &&
               (wait_cycles < 2_500_000)) begin
            @(posedge core_clk);
            wait_cycles = wait_cycles + 1;
        end
        // The frozen 22-descriptor graph has 21 stage indices: stage 0 is
        // emitted twice while the engine advances from its first descriptor
        // fetch into the first compute stage.  Count both descriptor fires,
        // but require the complete stage-index set 0..20.
        if (descriptor_fire_count < 22 ||
            descriptor_stage_seen !== 22'h1fffff)
            $fatal(1,"not all 22 CNN descriptors/stages were accepted count=%0d mask=%06x",
                   descriptor_fire_count,descriptor_stage_seen);
        if (!display_done_seen) begin
            $display("display timeout system=%0b control=%0b feed=%0b start_v/r=%0b/%0b busy=%0b done=%0b primed=%0b err=%0b pending=%0b current=%0b loading_new=%0b frame_start=%0b",
                     system_busy,dut.control_status_busy,dut.display_feed_active,
                     dut.display_prefetch_start_valid,dut.display_prefetch_start_ready,
                     dut.display_prefetch_busy,dut.display_prefetch_done,
                     dut.display_prefetch_primed,dut.display_prefetch_error,
                     dut.u_control.pending_pair_valid_q,
                     dut.u_control.current_pair_valid_q,
                     dut.u_control.prefetch_loading_new_q,
                     dut.display_frame_start_event);
            $display("  readers orig/styled busy done err state=%0b/%0b/%0b/%0d %0b/%0b/%0b/%0d stores primed=%0b/%0b empty=%0b/%0b",
                     dut.u_display.u_prefetch.original_reader_busy,
                     dut.u_display.u_prefetch.original_reader_done,
                     dut.u_display.u_prefetch.original_reader_error,
                     dut.u_display.u_prefetch.u_original_reader.state,
                     dut.u_display.u_prefetch.styled_reader_busy,
                     dut.u_display.u_prefetch.styled_reader_done,
                     dut.u_display.u_prefetch.styled_reader_error,
                     dut.u_display.u_prefetch.u_styled_reader.state,
                     dut.u_display.u_prefetch.original_primed,
                     dut.u_display.u_prefetch.styled_primed,
                     dut.u_display.u_prefetch.original_empty,
                     dut.u_display.u_prefetch.styled_empty);
            $display("  pixel timing x/y=%0d/%0d req_en=%0b frame_req=%0b line_ready=%0b/%0b toggles=%b/%b ack=%b/%b",
                     dut.u_display.timing_x,dut.u_display.timing_y,
                     dut.u_display.request_enable_core,
                     dut.u_display.request_enable_frame_q,
                     dut.u_display.compositor_original_request,
                     dut.u_display.compositor_styled_request,
                     dut.u_display.u_prefetch.u_original_store.ready_toggle_core,
                     dut.u_display.u_prefetch.u_styled_store.ready_toggle_core,
                     dut.u_display.u_prefetch.u_original_store.ack_toggle_pixel,
                     dut.u_display.u_prefetch.u_styled_store.ack_toggle_pixel);
            $fatal(1,"display prefetch did not report completion");
        end

`ifdef C1_TWO_FRAME
        // Optional serialized two-frame contract test.  STATUS.BUSY is not
        // equivalent to boardless_done: the previous display pair may still
        // be pending a frame-boundary swap.  Wait for the ownership barrier
        // before issuing the second START, then use table entry 1 and a
        // different camera tone so an address/index mix-up is observable.
        first_descriptor_count = descriptor_fire_count;
        first_swap_count = display_swap_count;
        wait_cycles = 0;
        // display_prefetch_busy may remain high while the display service
        // refreshes the currently-owned pair in the background; it is not a
        // foreground ownership fence.  The pending/new-pair bookkeeping is
        // the relevant condition for a serialized one-shot START.  The swap
        // count is sampled only for the final two-frame assertion; comparing
        // it with itself here would be a vacuous wait, while waiting for the
        // next swap would deadlock because the second START creates it.
        while ((system_busy || dut.u_control.pending_pair_valid_q ||
                dut.u_control.prefetch_loading_new_q ||
                dut.u_control.display_swap_requested_q) &&
               (wait_cycles < 3_000_000)) begin
            @(posedge core_clk);
            wait_cycles = wait_cycles + 1;
        end
        if (system_busy || dut.u_control.pending_pair_valid_q ||
            dut.u_control.prefetch_loading_new_q ||
            dut.u_control.display_swap_requested_q)
            $display("two-frame barrier timeout system=%0b control=%0b prefetch_busy=%0b pending=%0b loading_new=%0b swap_req=%0b swap=%0d first_swap=%0d frame_id=%0d done=%0d display_done=%0b primed=%0b feed=%0b",
                     system_busy,dut.control_status_busy,dut.display_prefetch_busy,
                     dut.u_control.pending_pair_valid_q,
                     dut.u_control.prefetch_loading_new_q,
                     dut.u_control.display_swap_requested_q,
                     display_swap_count,
                     first_swap_count,dut.control_display_frame_id,done_seen,
                     display_done_seen,dut.display_prefetch_primed,
                     dut.display_feed_active);
        if (system_busy || dut.u_control.pending_pair_valid_q ||
            dut.u_control.prefetch_loading_new_q ||
            dut.u_control.display_swap_requested_q)
            $fatal(1,"first frame ownership barrier did not close");

        apb_write(12'h010,32'h13);
        wait_cycles = 0;
        while ((!dut.u_control.run_armed_q || dut.capture_discard_idle) &&
               (wait_cycles < 1000)) begin
            @(posedge core_clk);
            wait_cycles = wait_cycles + 1;
        end
        if (!dut.u_control.run_armed_q || dut.capture_discard_idle)
            $fatal(1,"second START did not open camera admission");
        send_camera_frame(10'h155);

        wait_cycles = 0;
`ifdef C1_SHARED_QOS_MONITOR
        // The frame-manager swap is a VSYNC ownership commit and may occur
        // while the tagged prefetch reader is still draining its final R
        // beats.  Keep the native QoS assertion aligned with that terminal
        // drain instead of sampling frame_count immediately after swap.
        while ((done_seen < 2 || display_swap_count < (first_swap_count + 1) ||
                system_busy || (qos_new_done_count < 2)) &&
               (wait_cycles < SHARED_QOS_BOUNDARY_WAIT_CYCLES)) begin
            @(posedge core_clk);
            wait_cycles = wait_cycles + 1;
        end
`else
        while ((done_seen < 2 || display_swap_count < (first_swap_count + 1) ||
                system_busy) && (wait_cycles < 5_000_000)) begin
            @(posedge core_clk);
            wait_cycles = wait_cycles + 1;
        end
`endif
        if (done_seen < 2)
            $fatal(1,"second one-shot job timed out done=%0d",done_seen);
        if (descriptor_fire_count < (first_descriptor_count + 22))
            $fatal(1,"second job accepted fewer than 22 descriptors total=%0d",
                   descriptor_fire_count);
        if (display_swap_count < (first_swap_count + 1))
             $display("second swap timeout done=%0d desc=%0d swaps=%0d drops=%0d system=%0b control=%0b pending=%0b current=%0b loading_new=%0b prefetch busy/done/err/primed=%0b/%0b/%0b/%0b pair orig=%08x/%08x styled=%08x/%08x readers=%0b/%0b states=%0d/%0d timing=%0d/%0d hold=%0b",
                      done_seen,descriptor_fire_count,display_swap_count,
                      capture_drop_count,system_busy,dut.control_status_busy,
                      dut.u_control.pending_pair_valid_q,
                      dut.u_control.current_pair_valid_q,
                      dut.u_control.prefetch_loading_new_q,
                      dut.display_prefetch_busy,dut.display_prefetch_done,
                      dut.display_prefetch_error,dut.display_prefetch_primed,
                      dut.u_control.current_original_base_q,
                      dut.u_control.pending_original_base_q,
                      dut.u_control.current_styled_base_q,
                      dut.u_control.pending_styled_base_q,
                      dut.u_display.u_prefetch.original_reader_busy,
                      dut.u_display.u_prefetch.styled_reader_busy,
                      dut.u_display.u_prefetch.u_original_reader.state,
                      dut.u_display.u_prefetch.u_styled_reader.state,
                      dut.u_display.timing_x,dut.u_display.timing_y,
                      dut.display_hold_requests);
        if (display_swap_count < (first_swap_count + 1))
            $fatal(1,"second display pair did not swap count=%0d",
                   display_swap_count);
        if (capture_drop_count != 0)
            $fatal(1,"two-frame contract dropped capture frames count=%0d",
                   capture_drop_count);
`endif
        apb_read(12'h100,status_word);
`ifdef C1_TWO_FRAME
        if (status_word < 32'd2)
            $fatal(1,"processed frame count did not reach two: %0d",status_word);
`else
        if (status_word == 32'd0)
            $fatal(1,"processed frame count did not advance");
`endif
        if (axi_aw_count==0 || axi_w_count==0 || axi_b_count==0 ||
            axi_ar_count==0 || axi_r_count==0)
            $fatal(1,"small-frame run produced incomplete AXI traffic");
        $display("DDR BFM traffic aw=%0d w=%0d b=%0d ar=%0d r=%0d stalls aw/w/ar/r/fabric_r/b=%0d/%0d/%0d/%0d/%0d/%0d gaps r/b=%0d/%0d",
                 axi_aw_count,axi_w_count,axi_b_count,axi_ar_count,axi_r_count,
                 aw_stall_count,w_stall_count,ar_stall_count,r_stall_count,
                 fabric_r_stall_count,b_stall_count,r_gap_count,b_gap_count);
        if (aw_stall_count==0 || w_stall_count==0 || ar_stall_count==0 ||
            ((r_stall_count==0) && (fabric_r_stall_count==0)) ||
            (r_gap_count==0) || (b_gap_count==0))
            $fatal(1,"DDR BFM did not exercise request/response delay or backpressure");
        if (system_busy) begin
            $display("busy fence: system=%0b control=%0b bridge=%0b adapter=%0b cache=%0b cache_q=%0b display=%0b prefetch=%0b writer=%0b boardless=%0b parameter=%0b",
                     system_busy,dut.control_status_busy,dut.bridge_busy,
                     dut.tensor_adapter_busy,dut.tensor_cache_busy,
                     dut.tensor_cache_quiescent,dut.display_prefetch_busy,
                     dut.display_prefetch_start_valid,dut.capture_writer_busy,
                     dut.boardless_busy,dut.parameter_busy);
            $display("  display readers orig busy/done/err/state=%0b/%0b/%0b/%0d styled=%0b/%0b/%0b/%0d primed=%0b/%0b empty=%0b/%0b",
                     dut.u_display.u_prefetch.original_reader_busy,
                     dut.u_display.u_prefetch.original_reader_done,
                     dut.u_display.u_prefetch.original_reader_error,
                     dut.u_display.u_prefetch.u_original_reader.state,
                     dut.u_display.u_prefetch.styled_reader_busy,
                     dut.u_display.u_prefetch.styled_reader_done,
                     dut.u_display.u_prefetch.styled_reader_error,
                     dut.u_display.u_prefetch.u_styled_reader.state,
                     dut.u_display.u_prefetch.original_primed,
                     dut.u_display.u_prefetch.styled_primed,
                     dut.u_display.u_prefetch.original_empty,
                     dut.u_display.u_prefetch.styled_empty);
            $fatal(1,"portable SoC remained busy after drain");
        end

`ifdef C1_SHARED_QOS_MONITOR
        // The production monitor is observation-only, so native traffic and
        // lifecycle checks above remain the authority.  This gate additionally
        // proves that the real seven-client path produced a coherent job
        // snapshot and did not report an owner-status wiring error.
        $display("C1_QOS_EVENT_COUNTS start=%0d prefetch_done=%0d new_done=%0d swap=%0d monitor_frame=%0d monitor_active=%0b",
                 qos_start_count,qos_prefetch_done_count,qos_new_done_count,
                 qos_swap_event_count,
                 dut.g_shared_qos_monitor.u_monitor.frame_count,
                 dut.g_shared_qos_monitor.u_monitor.frame_active);
`ifdef C1_TWO_FRAME
        if (dut.g_shared_qos_monitor.u_monitor.frame_count < 24'd2) begin
            // This diagnostic is intentionally emitted before the fatal so a
            // shape-scaled run distinguishes a slow pixel-domain drain from a
            // real reader error/deadlock.  The persistent runner keeps only
            // this short line and the log tail; the full xsim tree is removed.
            $display("C1_QOS_BOUNDARY_TIMEOUT wait=%0d limit=%0d starts=%0d raw_done=%0d new_done=%0d swaps=%0d monitor_frame=%0d active=%0b prefetch_busy=%0b prefetch_done=%0b primed=%0b error=%0b readers=%0b/%0b states=%0d/%0d empty=%0b/%0b fifo=%0d/%0d fifo_drained=%0b req_en=%0b/%0b hold=%0b timing=%0d/%0d",
                     wait_cycles,SHARED_QOS_BOUNDARY_WAIT_CYCLES,
                     qos_start_count,qos_prefetch_done_count,qos_new_done_count,
                     qos_swap_event_count,
                     dut.g_shared_qos_monitor.u_monitor.frame_count,
                     dut.g_shared_qos_monitor.u_monitor.frame_active,
                     dut.display_prefetch_busy,dut.display_prefetch_done,
                     dut.display_prefetch_primed,dut.display_prefetch_error,
                     dut.u_display.u_prefetch.original_reader_busy,
                     dut.u_display.u_prefetch.styled_reader_busy,
                     dut.u_display.u_prefetch.u_original_reader.state,
                     dut.u_display.u_prefetch.u_styled_reader.state,
                     dut.u_display.u_prefetch.original_empty,
                     dut.u_display.u_prefetch.styled_empty,
                     dut.u_display.u_prefetch.original_fifo_level,
                     dut.u_display.u_prefetch.styled_fifo_level,
                     dut.u_display.u_prefetch.response_fifo_drained,
                     dut.u_display.request_enable_core,
                     dut.u_display.request_enable_frame_q,
                     dut.display_hold_requests,
                     dut.u_display.timing_x,dut.u_display.timing_y);
            $fatal(1,"QoS monitor missed a native job boundary: frame_count=%0d",
                   dut.g_shared_qos_monitor.u_monitor.frame_count);
        end
`else
        if (dut.g_shared_qos_monitor.u_monitor.frame_count < 24'd1)
            $fatal(1,"QoS monitor missed the native job boundary");
`endif
        if (dut.g_shared_qos_monitor.u_monitor.protocol_error_count != 24'd0)
            $fatal(1,"QoS monitor saw protocol errors: %0d",
                   dut.g_shared_qos_monitor.u_monitor.protocol_error_count);
        // Read back the production APB aggregate window after the native job
        // is idle.  This proves the software-visible path carries the same
        // snapshot as the hierarchical monitor; per-client vectors remain
        // intentionally outside this compact ABI.
        apb_read(12'h108,qos_apb_status);
        apb_read(12'h10c,qos_apb_frame_count);
        apb_read(12'h110,qos_apb_last_frame);
        apb_read(12'h114,qos_apb_deadline);
        apb_read(12'h118,qos_apb_underflow);
        apb_read(12'h11c,qos_apb_read_busy);
        apb_read(12'h120,qos_apb_write_busy);
        apb_read(12'h124,qos_apb_read_owner_max);
        apb_read(12'h128,qos_apb_write_owner_max);
        apb_read(12'h12c,qos_apb_protocol);
        if ((qos_apb_status & 32'h0000_0001) == 0 ||
            (qos_apb_status & 32'h0000_0006) != 0 ||
            (((qos_apb_status & 32'h0000_0008) != 0) != (qos_apb_underflow != 0)) ||
            (((qos_apb_status & 32'h0000_0010) != 0) != (qos_apb_deadline != 0)) ||
            (((qos_apb_status & 32'h0000_0020) != 0) != (qos_apb_protocol != 0)) ||
            qos_apb_frame_count != dut.g_shared_qos_monitor.u_monitor.frame_count ||
            qos_apb_last_frame != dut.g_shared_qos_monitor.u_monitor.last_frame_cycles ||
            qos_apb_deadline != dut.g_shared_qos_monitor.u_monitor.deadline_miss_count ||
            qos_apb_underflow != dut.g_shared_qos_monitor.u_monitor.display_underflow_count ||
            qos_apb_read_busy > dut.g_shared_qos_monitor.u_monitor.read_busy_cycles ||
            qos_apb_write_busy > dut.g_shared_qos_monitor.u_monitor.write_busy_cycles ||
            qos_apb_read_owner_max > dut.g_shared_qos_monitor.u_monitor.read_owner_hold_max ||
            qos_apb_write_owner_max > dut.g_shared_qos_monitor.u_monitor.write_owner_hold_max ||
            qos_apb_protocol != dut.g_shared_qos_monitor.u_monitor.protocol_error_count)
            $fatal(1,"QoS APB aggregate readback mismatch/live-order violation status=%08x frame=%0d last=%0d deadline=%0d underflow=%0d read_busy=%0d write_busy=%0d r_owner=%0d w_owner=%0d protocol=%0d",
                   qos_apb_status,qos_apb_frame_count,qos_apb_last_frame,
                   qos_apb_deadline,qos_apb_underflow,qos_apb_read_busy,
                   qos_apb_write_busy,qos_apb_read_owner_max,
                   qos_apb_write_owner_max,qos_apb_protocol);
        $display("C1_QOS_APB_READBACK pass=1 status=%08x frame=%0d last=%0d deadline=%0d underflow=%0d read_busy=%0d write_busy=%0d r_owner=%0d w_owner=%0d protocol=%0d",
                 qos_apb_status,qos_apb_frame_count,qos_apb_last_frame,
                 qos_apb_deadline,qos_apb_underflow,qos_apb_read_busy,
                 qos_apb_write_busy,qos_apb_read_owner_max,
                 qos_apb_write_owner_max,qos_apb_protocol);
        $display("C1_R1_PORTABLE_SOC_SHARED_QOS_STATS frame_count=%0d last_frame_cycles=%0d deadline_miss=%0d underflow=%0d read_busy=%0d write_busy=%0d r4_stall=%0d r5_stall=%0d ar4_wait=%0d ar5_wait=%0d protocol=%0d overflow=%0b event_start=%0d event_prefetch_done=%0d event_new_done=%0d event_swap=%0d",
                 dut.g_shared_qos_monitor.u_monitor.frame_count,
                 dut.g_shared_qos_monitor.u_monitor.last_frame_cycles,
                 dut.g_shared_qos_monitor.u_monitor.deadline_miss_count,
                 dut.g_shared_qos_monitor.u_monitor.display_underflow_count,
                 dut.g_shared_qos_monitor.u_monitor.read_busy_cycles,
                 dut.g_shared_qos_monitor.u_monitor.write_busy_cycles,
                 dut.g_shared_qos_monitor.u_monitor.r_stall_total[4],
                 dut.g_shared_qos_monitor.u_monitor.r_stall_total[5],
                 dut.g_shared_qos_monitor.u_monitor.ar_wait_total[4],
                 dut.g_shared_qos_monitor.u_monitor.ar_wait_total[5],
                 dut.g_shared_qos_monitor.u_monitor.protocol_error_count,
                  dut.g_shared_qos_monitor.u_monitor.monitor_overflow,
                  qos_start_count,qos_prefetch_done_count,qos_new_done_count,
                  qos_swap_event_count);
        // Keep the per-client vectors out of the software ABI, but emit a
        // bounded seven-line attribution table in the native BFM.  This is
        // the next optimization decision point: it distinguishes tensor
        // client-6 demand from display/parameter/engine arbitration without
        // retaining a large waveform or a full xsim log.
        for (i = 0; i < 7; i = i + 1) begin
            $display("C1_QOS_CLIENT id=%0d aw=%0d w=%0d b=%0d ar=%0d r=%0d aw_wait=%0d w_wait=%0d b_stall=%0d ar_wait=%0d r_stall=%0d aw_max=%0d w_max=%0d b_max=%0d ar_max=%0d r_max=%0d r_owner=%0d w_owner=%0d",
                     i,
                     dut.g_shared_qos_monitor.u_monitor.aw_accept_count[i],
                     dut.g_shared_qos_monitor.u_monitor.w_accept_count[i],
                     dut.g_shared_qos_monitor.u_monitor.b_accept_count[i],
                     dut.g_shared_qos_monitor.u_monitor.ar_accept_count[i],
                     dut.g_shared_qos_monitor.u_monitor.r_accept_count[i],
                     dut.g_shared_qos_monitor.u_monitor.aw_wait_total[i],
                     dut.g_shared_qos_monitor.u_monitor.w_wait_total[i],
                     dut.g_shared_qos_monitor.u_monitor.b_stall_total[i],
                     dut.g_shared_qos_monitor.u_monitor.ar_wait_total[i],
                     dut.g_shared_qos_monitor.u_monitor.r_stall_total[i],
                     dut.g_shared_qos_monitor.u_monitor.aw_wait_max[i],
                     dut.g_shared_qos_monitor.u_monitor.w_wait_max[i],
                     dut.g_shared_qos_monitor.u_monitor.b_stall_max[i],
                     dut.g_shared_qos_monitor.u_monitor.ar_wait_max[i],
                     dut.g_shared_qos_monitor.u_monitor.r_stall_max[i],
                     dut.g_shared_qos_monitor.u_monitor.read_owner_hold_total[i],
                     dut.g_shared_qos_monitor.u_monitor.write_owner_hold_total[i]);
        end
`endif

`ifdef C1_TWO_FRAME
        $display("C1_R1_PORTABLE_SOC_CACHE_DDR_BFM_TWO_FRAME_PASS frame=%0dx%0d done=%0d swaps=%0d drops=%0d descriptors=%0d stage_mask=%06x display_done=%0b drain_cycles=%0d axi_aw=%0d axi_w=%0d axi_b=%0d axi_ar=%0d axi_r=%0d aw_stalls=%0d w_stalls=%0d ar_stalls=%0d r_stalls=%0d fabric_r_stalls=%0d b_stalls=%0d r_gaps=%0d b_gaps=%0d descriptor_size_arith=%0d fixed_descriptor_size_limits=%0d pipelined_descriptor_pixel_count=%0d iterative_descriptor_pixel_count=%0d preclamped_tap_coords=%0d",
`else
        $display("C1_R1_PORTABLE_SOC_CACHE_DDR_BFM_PASS frame=%0dx%0d done=%0d swaps=%0d drops=%0d descriptors=%0d stage_mask=%06x display_done=%0b drain_cycles=%0d axi_aw=%0d axi_w=%0d axi_b=%0d axi_ar=%0d axi_r=%0d aw_stalls=%0d w_stalls=%0d ar_stalls=%0d r_stalls=%0d fabric_r_stalls=%0d b_stalls=%0d r_gaps=%0d b_gaps=%0d descriptor_size_arith=%0d fixed_descriptor_size_limits=%0d pipelined_descriptor_pixel_count=%0d iterative_descriptor_pixel_count=%0d preclamped_tap_coords=%0d",
`endif
                 FRAME_W,FRAME_H,done_seen,display_swap_count,
                 capture_drop_count,descriptor_fire_count,descriptor_stage_seen,
                 display_done_seen,wait_cycles,
                 axi_aw_count,axi_w_count,axi_b_count,axi_ar_count,axi_r_count,
                 aw_stall_count,w_stall_count,
                 ar_stall_count,r_stall_count,fabric_r_stall_count,
                 b_stall_count,r_gap_count,b_gap_count,
                 PIPELINED_DESCRIPTOR_SIZE_ARITH_CFG,
                 FIXED_DESCRIPTOR_SIZE_LIMITS_CFG,
                 PIPELINED_DESCRIPTOR_PIXEL_COUNT_CFG,
                 ITERATIVE_DESCRIPTOR_PIXEL_COUNT_CFG,
                  PRECLAMPED_TAP_COORDS_CFG);
        if (TRAINED_ARTIFACT_CFG) begin
            if (trained_weight_ar_count == 0)
                $fatal(1, "trained artifact mode did not issue a parameter-arena read");
            $display("C1_R1_PORTABLE_SOC_TRAINED_ARTIFACT_8X8_PASS descriptors=%0d weight_ar=%0d axi_r=%0d done=%0d stage_mask=%06x",
                     descriptor_fire_count, trained_weight_ar_count, axi_r_count,
                     done_seen, descriptor_stage_seen);
        end
        $finish;
    end

    initial begin
`ifdef C1_TWO_FRAME
        #600_000_000;
`else
        #300_000_000;
`endif
        $fatal(1,"portable SoC cache DDR BFM timeout");
    end
endmodule
