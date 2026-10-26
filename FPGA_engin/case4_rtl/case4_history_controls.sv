`timescale 1ns/1ps
// Active-low keys. Release-triggered gestures never fire while a key is held.
// LIVE: short K1/K2 = threshold +/-16; K1 0.7..2 s = edge mode;
// K2 >=0.7 s = freeze. In every screen, K1 >=2 s cycles LIVE/REPLAY/COMPARE.
// HISTORY: short K1/K2 = older/newer and pause; K1 0.7..2 s = reference;
// K2 >=0.7 s = play/pause. Both >=1 s toggles median in every screen.
// A chord consumes both individual gestures, including staggered release.
// All control values and persistent command toggles publish at frame_start.
module case4_history_controls #(
    parameter integer CLK_HZ = 148800000,
    parameter integer DEBOUNCE_CYCLES = CLK_HZ / 50,
    parameter integer LONG_CYCLES = (CLK_HZ / 10) * 7,
    parameter integer VERY_LONG_CYCLES = CLK_HZ * 2,
    parameter integer CHORD_CYCLES = CLK_HZ,
    parameter integer INITIAL_THRESHOLD = 128
) (
    input wire clk, rst_n,
    input wire [1:0] key_n,
    input wire frame_start,
    output reg [10:0] threshold,
    output reg [1:0] mode,
    output reg median_enable,
    output reg freeze_request,
    output reg [1:0] history_mode,
    output reg history_paused,
    output reg step_prev_toggle,
    output reg step_next_toggle,
    output reg reference_toggle
);
    localparam integer DB_LIMIT = DEBOUNCE_CYCLES > 0 ? DEBOUNCE_CYCLES : 1;
    localparam integer LONG_LIMIT = LONG_CYCLES > 0 ? LONG_CYCLES : 1;
    localparam integer VERY_LIMIT = VERY_LONG_CYCLES > LONG_LIMIT ? VERY_LONG_CYCLES : LONG_LIMIT+1;
    localparam integer CHORD_LIMIT = CHORD_CYCLES > 0 ? CHORD_CYCLES : 1;
    localparam integer DB_W = DB_LIMIT > 1 ? $clog2(DB_LIMIT) : 1;
    localparam integer HOLD_MAX = CHORD_LIMIT > VERY_LIMIT ? CHORD_LIMIT : VERY_LIMIT;
    localparam integer HOLD_W = HOLD_MAX > 1 ? $clog2(HOLD_MAX+1) : 1;
    (* async_reg = "true" *) reg [1:0] key_meta, key_sync;
    reg [1:0] key_stable;
    reg [DB_W-1:0] debounce_count [0:1];
    integer k;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_meta <= 2'b11; key_sync <= 2'b11; key_stable <= 2'b11;
            debounce_count[0] <= 0; debounce_count[1] <= 0;
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
    reg [1:0] mode_pending, history_pending;
    reg median_pending, freeze_pending, paused_pending;
    reg prev_pending, next_pending, reference_pending;
    wire [1:0] pressed = ~key_stable;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE; held <= 0;
            threshold_pending <= INITIAL_THRESHOLD; threshold <= INITIAL_THRESHOLD;
            mode_pending <= 0; mode <= 0;
            median_pending <= 1; median_enable <= 1;
            freeze_pending <= 0; freeze_request <= 0;
            history_pending <= 0; history_mode <= 0;
            paused_pending <= 0; history_paused <= 0;
            prev_pending <= 0; step_prev_toggle <= 0;
            next_pending <= 0; step_next_toggle <= 0;
            reference_pending <= 0; reference_toggle <= 0;
        end else begin
            // A gesture completed on frame_start becomes visible next frame.
            if (frame_start) begin
                threshold <= threshold_pending; mode <= mode_pending;
                median_enable <= median_pending; freeze_request <= freeze_pending;
                history_mode <= history_pending; history_paused <= paused_pending;
                step_prev_toggle <= prev_pending; step_next_toggle <= next_pending;
                reference_toggle <= reference_pending;
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
                        if (state == KEY1 && held >= VERY_LIMIT) begin
                            // The very-long gesture has priority over all others.
                            if (history_pending == 2) begin
                                history_pending <= 0; paused_pending <= 0;
                            end else begin
                                history_pending <= history_pending + 1'b1;
                                paused_pending <= history_pending == 1;
                            end
                            freeze_pending <= 0;
                        end else if (history_pending != 0) begin
                            if (held >= LONG_LIMIT) begin
                                if (state == KEY1) reference_pending <= !reference_pending;
                                else paused_pending <= !paused_pending;
                            end else begin
                                paused_pending <= 1;
                                if (state == KEY1) prev_pending <= !prev_pending;
                                else next_pending <= !next_pending;
                            end
                        end else if (held >= LONG_LIMIT) begin
                            if (state == KEY1) mode_pending <= mode_pending + 1'b1;
                            else freeze_pending <= !freeze_pending;
                        end else if (state == KEY1) begin
                            threshold_pending <= threshold_pending >= 1008 ? 11'd1024 : threshold_pending + 11'd16;
                        end else begin
                            threshold_pending <= threshold_pending <= 32 ? 11'd16 : threshold_pending - 11'd16;
                        end
                        state <= IDLE; held <= 0;
                    end else if (held < VERY_LIMIT) held <= held + 1'b1;
                end
                CHORD: begin
                    if (pressed != 2'b11) begin
                        state <= pressed == 0 ? IDLE : CHORD_GAP; held <= 0;
                    end else if (held >= CHORD_LIMIT-1) begin
                        median_pending <= !median_pending;
                        state <= CONSUMED; held <= 0;
                    end else held <= held + 1'b1;
                end
                CONSUMED: begin
                    held <= 0;
                    if (pressed == 0) state <= IDLE;
                    else if (pressed != 2'b11) state <= CHORD_GAP;
                end
                CHORD_GAP: begin
                    held <= 0;
                    if (pressed == 0) state <= IDLE;
                    else if (pressed == 2'b11) state <= CHORD;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
