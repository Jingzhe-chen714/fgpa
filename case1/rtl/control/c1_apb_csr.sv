`timescale 1ns/1ps

// Board-independent APB3 control/status register block for case 1.
//
// This block contains real synthesizable register and interrupt logic.  It
// intentionally does not instantiate Sapphire or any vendor bus primitive.
// Configuration registers are software-visible shadow registers.  The R1
// lifecycle controller snapshots the complete launch contract when it accepts
// start_pulse; writes made while a job runs apply only to a later launch.
module c1_apb_csr #(
    parameter integer APB_ADDR_W = 12
) (
    input  wire                    clk,
    input  wire                    rst_n,

    input  wire                    psel,
    input  wire                    penable,
    input  wire                    pwrite,
    input  wire [APB_ADDR_W-1:0]   paddr,
    input  wire [31:0]             pwdata,
    input  wire [3:0]              pstrb,
    output reg  [31:0]             prdata,
    output wire                    pready,
    output wire                    pslverr,

    input  wire                    busy,
    input  wire                    done_event,
    input  wire                    error_event,
    input  wire [7:0]              error_code_in,
    input  wire [31:0]             error_address_in,
    input  wire                    capture_drop_event,
    input  wire                    display_swap_event,
    input  wire                    display_underflow_event,
    input  wire [2:0]              input_ready_count,
    input  wire [1:0]              output_ready_count,

    // Optional shared-AXI QoS snapshot inputs.  They are read-only and may
    // be tied to zero by legacy/integration-skeleton instantiations.  The
    // monitor itself remains default-off in the portable SoC.
    input  wire                    qos_monitor_enabled,
    input  wire                    qos_frame_active,
    input  wire                    qos_monitor_overflow,
    input  wire [31:0]             qos_frame_count,
    input  wire [31:0]             qos_last_frame_cycles,
    input  wire [31:0]             qos_deadline_miss_count,
    input  wire [31:0]             qos_display_underflow_count,
    input  wire [31:0]             qos_read_busy_cycles,
    input  wire [31:0]             qos_write_busy_cycles,
    input  wire [31:0]             qos_read_owner_hold_max,
    input  wire [31:0]             qos_write_owner_hold_max,
    input  wire [31:0]             qos_protocol_error_count,

    output reg                     system_enable,
    output reg                     continuous_mode,
    output reg                     drop_oldest_mode,
    output reg                     start_pulse,
    output reg                     abort_pulse,
    output reg                     clear_stats_pulse,
    output reg  [15:0]             frame_width,
    output reg  [15:0]             frame_height,
    output reg  [31:0]             input_stride_bytes,
    output reg  [31:0]             output_stride_bytes,
    output reg  [3:0]              input_pixel_format,
    output reg  [3:0]              output_pixel_format,
    output reg  [63:0]             input_buffer_table_base,
    output reg  [63:0]             output_buffer_table_base,
    output reg  [63:0]             descriptor_base,
    output reg  [15:0]             descriptor_count,
    output reg  [7:0]              style_id,
    output reg  [63:0]             weight_base,
    output reg  [31:0]             tensor_base_addr,
    output reg  [7:0]              display_mode,
    output wire                    irq
);

    localparam [APB_ADDR_W-1:0] ADDR_ID             = 12'h000;
    localparam [APB_ADDR_W-1:0] ADDR_VERSION        = 12'h004;
    localparam [APB_ADDR_W-1:0] ADDR_CAPABILITY     = 12'h008;
    localparam [APB_ADDR_W-1:0] ADDR_CONTROL        = 12'h010;
    localparam [APB_ADDR_W-1:0] ADDR_STATUS         = 12'h014;
    localparam [APB_ADDR_W-1:0] ADDR_IRQ_ENABLE     = 12'h018;
    localparam [APB_ADDR_W-1:0] ADDR_IRQ_STATUS     = 12'h01c;
    localparam [APB_ADDR_W-1:0] ADDR_ERROR_CODE     = 12'h020;
    localparam [APB_ADDR_W-1:0] ADDR_ERROR_ADDRESS  = 12'h024;
    localparam [APB_ADDR_W-1:0] ADDR_IN_TABLE_LO    = 12'h040;
    localparam [APB_ADDR_W-1:0] ADDR_IN_TABLE_HI    = 12'h044;
    localparam [APB_ADDR_W-1:0] ADDR_OUT_TABLE_LO   = 12'h048;
    localparam [APB_ADDR_W-1:0] ADDR_OUT_TABLE_HI   = 12'h04c;
    localparam [APB_ADDR_W-1:0] ADDR_FRAME_SIZE     = 12'h050;
    localparam [APB_ADDR_W-1:0] ADDR_IN_STRIDE      = 12'h054;
    localparam [APB_ADDR_W-1:0] ADDR_OUT_STRIDE     = 12'h058;
    localparam [APB_ADDR_W-1:0] ADDR_PIXEL_FORMAT   = 12'h05c;
    localparam [APB_ADDR_W-1:0] ADDR_DESC_BASE_LO   = 12'h080;
    localparam [APB_ADDR_W-1:0] ADDR_DESC_BASE_HI   = 12'h084;
    localparam [APB_ADDR_W-1:0] ADDR_DESC_COUNT     = 12'h088;
    localparam [APB_ADDR_W-1:0] ADDR_STYLE_ID       = 12'h08c;
    localparam [APB_ADDR_W-1:0] ADDR_WEIGHT_BASE_LO = 12'h090;
    localparam [APB_ADDR_W-1:0] ADDR_WEIGHT_BASE_HI = 12'h094;
    localparam [APB_ADDR_W-1:0] ADDR_TENSOR_BASE     = 12'h098;
    localparam [APB_ADDR_W-1:0] ADDR_DISPLAY_MODE   = 12'h0c0;
    localparam [APB_ADDR_W-1:0] ADDR_FRAME_COUNT    = 12'h100;
    localparam [APB_ADDR_W-1:0] ADDR_BUSY_CYCLES    = 12'h104;
    // QoS snapshot window.  These are deliberately read-only; clearing is
    // still performed by CONTROL[5] so software has one synchronized command
    // for the legacy and optional monitor counters.
    localparam [APB_ADDR_W-1:0] ADDR_QOS_STATUS     = 12'h108;
    localparam [APB_ADDR_W-1:0] ADDR_QOS_FRAME_COUNT= 12'h10c;
    localparam [APB_ADDR_W-1:0] ADDR_QOS_LAST_FRAME = 12'h110;
    localparam [APB_ADDR_W-1:0] ADDR_QOS_DEADLINE   = 12'h114;
    localparam [APB_ADDR_W-1:0] ADDR_QOS_UNDERFLOW  = 12'h118;
    localparam [APB_ADDR_W-1:0] ADDR_QOS_READ_BUSY  = 12'h11c;
    localparam [APB_ADDR_W-1:0] ADDR_QOS_WRITE_BUSY = 12'h120;
    localparam [APB_ADDR_W-1:0] ADDR_QOS_R_OWNER_MAX= 12'h124;
    localparam [APB_ADDR_W-1:0] ADDR_QOS_W_OWNER_MAX= 12'h128;
    localparam [APB_ADDR_W-1:0] ADDR_QOS_PROTOCOL   = 12'h12c;

    // IRQ bits: 0 done, 1 error, 2 capture drop, 3 display swap,
    // 4 display underflow.
    reg [4:0] irq_enable_reg;
    reg [4:0] irq_status_reg;
    reg [7:0] error_code_reg;
    reg [31:0] error_address_reg;
    reg [31:0] processed_frame_count;
    reg [31:0] busy_cycle_count;

    wire apb_access = psel && penable;
    wire apb_write  = apb_access && pwrite;
    wire busy_start_write = apb_write && (paddr == ADDR_CONTROL) &&
                            pstrb[0] && pwdata[1] && busy;

    function automatic [31:0] merge_wstrb;
        input [31:0] old_value;
        input [31:0] new_value;
        input [3:0]  byte_strobe;
        integer byte_index;
        begin
            merge_wstrb = old_value;
            for (byte_index = 0; byte_index < 4; byte_index = byte_index + 1) begin
                if (byte_strobe[byte_index])
                    merge_wstrb[byte_index*8 +: 8] = new_value[byte_index*8 +: 8];
            end
        end
    endfunction

    function automatic address_is_valid;
        input [APB_ADDR_W-1:0] address;
        begin
            case (address)
                ADDR_ID,
                ADDR_VERSION,
                ADDR_CAPABILITY,
                ADDR_CONTROL,
                ADDR_STATUS,
                ADDR_IRQ_ENABLE,
                ADDR_IRQ_STATUS,
                ADDR_ERROR_CODE,
                ADDR_ERROR_ADDRESS,
                ADDR_IN_TABLE_LO,
                ADDR_IN_TABLE_HI,
                ADDR_OUT_TABLE_LO,
                ADDR_OUT_TABLE_HI,
                ADDR_FRAME_SIZE,
                ADDR_IN_STRIDE,
                ADDR_OUT_STRIDE,
                ADDR_PIXEL_FORMAT,
                ADDR_DESC_BASE_LO,
                ADDR_DESC_BASE_HI,
                ADDR_DESC_COUNT,
                ADDR_STYLE_ID,
                ADDR_WEIGHT_BASE_LO,
                ADDR_WEIGHT_BASE_HI,
                ADDR_TENSOR_BASE,
                ADDR_DISPLAY_MODE,
                ADDR_FRAME_COUNT,
                ADDR_BUSY_CYCLES,
                ADDR_QOS_STATUS,
                ADDR_QOS_FRAME_COUNT,
                ADDR_QOS_LAST_FRAME,
                ADDR_QOS_DEADLINE,
                ADDR_QOS_UNDERFLOW,
                ADDR_QOS_READ_BUSY,
                ADDR_QOS_WRITE_BUSY,
                ADDR_QOS_R_OWNER_MAX,
                ADDR_QOS_W_OWNER_MAX,
                ADDR_QOS_PROTOCOL: address_is_valid = 1'b1;
                default:          address_is_valid = 1'b0;
            endcase
        end
    endfunction

    assign pready  = 1'b1;
    assign pslverr = (apb_access && !address_is_valid(paddr)) ||
                     busy_start_write;
    assign irq     = |(irq_enable_reg & irq_status_reg);

    always @* begin
        prdata = 32'h0000_0000;
        case (paddr)
            ADDR_ID:             prdata = 32'h4331_5254; // "C1RT"
            ADDR_VERSION:        prdata = 32'h0001_0100;
            ADDR_CAPABILITY:     prdata = 32'h0000_0323; // 3 in, 2 out, APB3
            ADDR_CONTROL:        prdata = {27'd0, drop_oldest_mode,
                                           continuous_mode, 2'b00,
                                           system_enable};
            ADDR_STATUS:         prdata = {21'd0,
                                           output_ready_count,
                                           input_ready_count,
                                           2'd0,
                                           irq_status_reg[1],
                                           irq_status_reg[0],
                                           busy,
                                           !busy};
            ADDR_IRQ_ENABLE:     prdata = {27'd0, irq_enable_reg};
            ADDR_IRQ_STATUS:     prdata = {27'd0, irq_status_reg};
            ADDR_ERROR_CODE:     prdata = {24'd0, error_code_reg};
            ADDR_ERROR_ADDRESS:  prdata = error_address_reg;
            ADDR_IN_TABLE_LO:    prdata = input_buffer_table_base[31:0];
            ADDR_IN_TABLE_HI:    prdata = input_buffer_table_base[63:32];
            ADDR_OUT_TABLE_LO:   prdata = output_buffer_table_base[31:0];
            ADDR_OUT_TABLE_HI:   prdata = output_buffer_table_base[63:32];
            ADDR_FRAME_SIZE:     prdata = {frame_height, frame_width};
            ADDR_IN_STRIDE:      prdata = input_stride_bytes;
            ADDR_OUT_STRIDE:     prdata = output_stride_bytes;
            ADDR_PIXEL_FORMAT:   prdata = {24'd0, output_pixel_format,
                                           input_pixel_format};
            ADDR_DESC_BASE_LO:   prdata = descriptor_base[31:0];
            ADDR_DESC_BASE_HI:   prdata = descriptor_base[63:32];
            ADDR_DESC_COUNT:     prdata = {16'd0, descriptor_count};
            ADDR_STYLE_ID:       prdata = {24'd0, style_id};
            ADDR_WEIGHT_BASE_LO: prdata = weight_base[31:0];
            ADDR_WEIGHT_BASE_HI: prdata = weight_base[63:32];
            ADDR_TENSOR_BASE:    prdata = tensor_base_addr;
            ADDR_DISPLAY_MODE:   prdata = {24'd0, display_mode};
            ADDR_FRAME_COUNT:    prdata = processed_frame_count;
            ADDR_BUSY_CYCLES:    prdata = busy_cycle_count;
            ADDR_QOS_STATUS:     prdata = {26'd0,
                                           (qos_protocol_error_count != 0),
                                           (qos_deadline_miss_count != 0),
                                           (qos_display_underflow_count != 0),
                                           qos_monitor_overflow,
                                           qos_frame_active,
                                           qos_monitor_enabled};
            ADDR_QOS_FRAME_COUNT:prdata = qos_frame_count;
            ADDR_QOS_LAST_FRAME: prdata = qos_last_frame_cycles;
            ADDR_QOS_DEADLINE:   prdata = qos_deadline_miss_count;
            ADDR_QOS_UNDERFLOW:  prdata = qos_display_underflow_count;
            ADDR_QOS_READ_BUSY:  prdata = qos_read_busy_cycles;
            ADDR_QOS_WRITE_BUSY: prdata = qos_write_busy_cycles;
            ADDR_QOS_R_OWNER_MAX:prdata = qos_read_owner_hold_max;
            ADDR_QOS_W_OWNER_MAX:prdata = qos_write_owner_hold_max;
            ADDR_QOS_PROTOCOL:   prdata = qos_protocol_error_count;
            default:             prdata = 32'h0000_0000;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            system_enable           <= 1'b0;
            continuous_mode         <= 1'b0;
            drop_oldest_mode        <= 1'b1;
            start_pulse             <= 1'b0;
            abort_pulse             <= 1'b0;
            clear_stats_pulse       <= 1'b0;
            frame_width             <= 16'd640;
            frame_height            <= 16'd480;
            input_stride_bytes      <= 32'd2560;
            output_stride_bytes     <= 32'd2560;
            input_pixel_format      <= 4'd2; // DDR XRGB8888, 0x00RRGGBB
            output_pixel_format     <= 4'd2;
            input_buffer_table_base <= 64'd0;
            output_buffer_table_base<= 64'd0;
            descriptor_base         <= 64'd0;
            descriptor_count        <= 16'd0;
            style_id                <= 8'd0;
            weight_base             <= 64'd0;
            tensor_base_addr        <= 32'd0;
            display_mode            <= 8'd0;
            irq_enable_reg          <= 5'd0;
            irq_status_reg          <= 5'd0;
            error_code_reg          <= 8'd0;
            error_address_reg       <= 32'd0;
            processed_frame_count   <= 32'd0;
            busy_cycle_count        <= 32'd0;
        end else begin
            start_pulse       <= 1'b0;
            abort_pulse       <= 1'b0;
            clear_stats_pulse <= 1'b0;

            if (busy)
                busy_cycle_count <= busy_cycle_count + 32'd1;

            if (done_event) begin
                irq_status_reg[0]    <= 1'b1;
                processed_frame_count <= processed_frame_count + 32'd1;
            end
            if (error_event) begin
                irq_status_reg[1] <= 1'b1;
                error_code_reg    <= error_code_in;
                error_address_reg <= error_address_in;
            end
            if (capture_drop_event)
                irq_status_reg[2] <= 1'b1;
            if (display_swap_event)
                irq_status_reg[3] <= 1'b1;
            if (display_underflow_event)
                irq_status_reg[4] <= 1'b1;

            if (apb_write) begin
                case (paddr)
                    ADDR_CONTROL: begin
                        // START is a snapshot command, not a level.  Reject
                        // it while the previous foreground job is armed/busy
                        // and suppress every side effect of that failed APB
                        // transfer so live configuration cannot be replaced.
                        if (pstrb[0] && !busy_start_write) begin
                            system_enable    <= pwdata[0];
                            start_pulse      <= pwdata[1];
                            abort_pulse      <= pwdata[2];
                            continuous_mode  <= pwdata[3];
                            drop_oldest_mode <= pwdata[4];
                            clear_stats_pulse<= pwdata[5];
                            if (pwdata[5]) begin
                                processed_frame_count <= 32'd0;
                                busy_cycle_count      <= 32'd0;
                            end
                        end
                    end
                    ADDR_IRQ_ENABLE: begin
                        if (pstrb[0])
                            irq_enable_reg <= pwdata[4:0];
                    end
                    ADDR_IRQ_STATUS: begin
                        if (pstrb[0]) begin
                            if (pwdata[0] && !done_event)
                                irq_status_reg[0] <= 1'b0;
                            if (pwdata[1] && !error_event)
                                irq_status_reg[1] <= 1'b0;
                            if (pwdata[2] && !capture_drop_event)
                                irq_status_reg[2] <= 1'b0;
                            if (pwdata[3] && !display_swap_event)
                                irq_status_reg[3] <= 1'b0;
                            if (pwdata[4] && !display_underflow_event)
                                irq_status_reg[4] <= 1'b0;
                        end
                    end
                    ADDR_IN_TABLE_LO:
                        input_buffer_table_base[31:0] <=
                            merge_wstrb(input_buffer_table_base[31:0], pwdata, pstrb);
                    ADDR_IN_TABLE_HI:
                        input_buffer_table_base[63:32] <=
                            merge_wstrb(input_buffer_table_base[63:32], pwdata, pstrb);
                    ADDR_OUT_TABLE_LO:
                        output_buffer_table_base[31:0] <=
                            merge_wstrb(output_buffer_table_base[31:0], pwdata, pstrb);
                    ADDR_OUT_TABLE_HI:
                        output_buffer_table_base[63:32] <=
                            merge_wstrb(output_buffer_table_base[63:32], pwdata, pstrb);
                    ADDR_FRAME_SIZE: begin
                        if (pstrb[0]) frame_width[7:0]   <= pwdata[7:0];
                        if (pstrb[1]) frame_width[15:8]  <= pwdata[15:8];
                        if (pstrb[2]) frame_height[7:0]  <= pwdata[23:16];
                        if (pstrb[3]) frame_height[15:8] <= pwdata[31:24];
                    end
                    ADDR_IN_STRIDE:
                        input_stride_bytes <= merge_wstrb(input_stride_bytes, pwdata, pstrb);
                    ADDR_OUT_STRIDE:
                        output_stride_bytes <= merge_wstrb(output_stride_bytes, pwdata, pstrb);
                    ADDR_PIXEL_FORMAT: begin
                        if (pstrb[0]) begin
                            input_pixel_format  <= pwdata[3:0];
                            output_pixel_format <= pwdata[7:4];
                        end
                    end
                    ADDR_DESC_BASE_LO:
                        descriptor_base[31:0] <=
                            merge_wstrb(descriptor_base[31:0], pwdata, pstrb);
                    ADDR_DESC_BASE_HI:
                        descriptor_base[63:32] <=
                            merge_wstrb(descriptor_base[63:32], pwdata, pstrb);
                    ADDR_DESC_COUNT: begin
                        if (pstrb[0]) descriptor_count[7:0]  <= pwdata[7:0];
                        if (pstrb[1]) descriptor_count[15:8] <= pwdata[15:8];
                    end
                    ADDR_STYLE_ID: begin
                        if (pstrb[0]) style_id <= pwdata[7:0];
                    end
                    ADDR_WEIGHT_BASE_LO:
                        weight_base[31:0] <=
                            merge_wstrb(weight_base[31:0], pwdata, pstrb);
                    ADDR_WEIGHT_BASE_HI:
                        weight_base[63:32] <=
                            merge_wstrb(weight_base[63:32], pwdata, pstrb);
                    ADDR_TENSOR_BASE:
                        tensor_base_addr <=
                            merge_wstrb(tensor_base_addr, pwdata, pstrb);
                    ADDR_DISPLAY_MODE: begin
                        if (pstrb[0]) display_mode <= pwdata[7:0];
                    end
                    default: begin
                        // Read-only and unmapped writes have no side effects.
                    end
                endcase
            end
        end
    end

endmodule
