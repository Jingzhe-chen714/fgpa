`timescale 1ns/1ps
// VF-Ti60F225: key_n[0]=N2/GPIOL_P_02, key_n[1]=M2/GPIOL_N_02.
// Board keys are active low. All outputs belong to the clk_pixel domain.
// Short K1/K2: threshold +/-16 (16..1024). Long K1/K2 (>=700 ms,
// then release): mode cycle / freeze request. Both held >=1 s: median toggle.
// A chord consumes individual-key tails. After either key is debounced as
// released, pressing both again starts a new chord even if the other key was
// never released. This permits repeated median ON/OFF without a dead session.
// Releasing long keys before acting prevents an overlapping chord from also
// performing an individual action. No auto-repeat is applied.
// Mode 0/1: gray-left + red Sobel/Canny edges over RGB-right.
// Mode 2/3: gray-left + binary Sobel/Canny edges-right. No image scaling.
module case4_controls #(
    parameter integer CLK_HZ = 74399000,
    parameter integer DEBOUNCE_CYCLES = CLK_HZ / 50,
    parameter integer LONG_CYCLES = (CLK_HZ / 10) * 7,
    parameter integer CHORD_CYCLES = CLK_HZ,
    parameter integer INITIAL_THRESHOLD = 128
) (
    input wire clk, rst_n,
    input wire [1:0] key_n,
    input wire frame_start,
    output reg [10:0] threshold,
    output reg [1:0] mode,
    output reg median_enable,
    output reg freeze_request
);
    localparam integer DB_LIMIT = DEBOUNCE_CYCLES > 0 ? DEBOUNCE_CYCLES : 1;
    localparam integer LONG_LIMIT = LONG_CYCLES > 0 ? LONG_CYCLES : 1;
    localparam integer CHORD_LIMIT = CHORD_CYCLES > 0 ? CHORD_CYCLES : 1;
    localparam integer DB_W = DB_LIMIT > 1 ? $clog2(DB_LIMIT) : 1;
    localparam integer HOLD_MAX = CHORD_LIMIT > LONG_LIMIT ? CHORD_LIMIT : LONG_LIMIT;
    localparam integer HOLD_W = HOLD_MAX > 1 ? $clog2(HOLD_MAX+1) : 1;
    (* async_reg = "true" *) reg [1:0] key_meta, key_sync;
    reg [1:0] key_stable;
    reg [DB_W-1:0] debounce_count [0:1];
    integer k;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_meta <= 2'b11;
            key_sync <= 2'b11;
            key_stable <= 2'b11;
            debounce_count[0] <= 0;
            debounce_count[1] <= 0;
        end else begin
            key_meta <= key_n;
            key_sync <= key_meta;
            for (k=0; k<2; k=k+1) begin
                if (key_sync[k] == key_stable[k]) debounce_count[k] <= 0;
                else if (debounce_count[k] >= DB_LIMIT-1) begin
                    key_stable[k] <= key_sync[k];
                    debounce_count[k] <= 0;
                end else debounce_count[k] <= debounce_count[k] + 1'b1;
            end
        end
    end

    localparam [2:0] IDLE=0, KEY1=1, KEY2=2, CHORD=3, CONSUMED=4, CHORD_GAP=5;
    reg [2:0] state;
    reg [HOLD_W-1:0] held;
    reg [10:0] threshold_pending;
    reg [1:0] mode_pending;
    reg median_pending;
    wire [1:0] pressed = ~key_stable;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            held <= 0;
            threshold_pending <= INITIAL_THRESHOLD;
            mode_pending <= 0;
            median_pending <= 1;
            threshold <= INITIAL_THRESHOLD;
            mode <= 0;
            median_enable <= 1;
            freeze_request <= 0;
        end else begin
            // If an action coincides with frame_start, its new value takes
            // effect on the following frame, never halfway through a frame.
            if (frame_start) begin
                threshold <= threshold_pending;
                mode <= mode_pending;
                median_enable <= median_pending;
            end
            case (state)
                IDLE: begin
                    held <= 0;
                    case (pressed)
                        2'b01: state <= KEY1;
                        2'b10: state <= KEY2;
                        2'b11: state <= CHORD;
                        default: state <= IDLE;
                    endcase
                end
                KEY1, KEY2: begin
                    if (pressed == 2'b11 ||
                        (state == KEY1 && pressed == 2'b10) ||
                        (state == KEY2 && pressed == 2'b01)) begin
                        state <= pressed == 2'b11 ? CHORD : CONSUMED;
                        held <= 0;
                    end else if (pressed == 0) begin
                        if (held >= LONG_LIMIT) begin
                            if (state == KEY1) mode_pending <= mode_pending + 1'b1;
                            else freeze_request <= !freeze_request;
                        end else if (state == KEY1) begin
                            threshold_pending <= threshold_pending >= 1008 ? 11'd1024 : threshold_pending + 11'd16;
                        end else begin
                            threshold_pending <= threshold_pending <= 32 ? 11'd16 : threshold_pending - 11'd16;
                        end
                        state <= IDLE;
                        held <= 0;
                    end else if (held < LONG_LIMIT) held <= held + 1'b1;
                end
                CHORD: begin
                    if (pressed != 2'b11) begin
                        state <= pressed==0 ? IDLE : CHORD_GAP;
                        held <= 0;
                    end else if (held >= CHORD_LIMIT-1) begin
                        median_pending <= !median_pending;
                        state <= CONSUMED;
                        held <= 0;
                    end else held <= held + 1'b1;
                end
                CONSUMED: begin
                    held <= 0;
                    if (pressed == 0) state <= IDLE;
                    else if (pressed != 2'b11) state <= CHORD_GAP;
                end
                CHORD_GAP: begin
                    // A release has already passed the debounce interval.
                    // Keep swallowing a single held key; only a new pair
                    // starts another chord. Never synthesize a short/long key
                    // action from the tail of a two-key gesture.
                    held <= 0;
                    if (pressed == 0) state <= IDLE;
                    else if (pressed == 2'b11) state <= CHORD;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
