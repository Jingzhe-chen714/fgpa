`timescale 1ns/1ps
// V8 frame-coherent two-key menu. All public controls publish at frame_start.
// Active-low keys use independent synchronizers/debounce. Chords consume BOTH
// keys until fully released. Single-key commands are evaluated on release.
// Menu12: APP EDGE AUTO THR MEDIAN THICK EFFECT STABLE INTERVAL CAPTURE VIEW PAUSE.
// APP0 LIVE /3 FACE. Modes0..5. Effect0 NORMAL1 TRAIL2 STABLE_COMPARE3 MOTION4 STROBE.
// INTERVAL0..4 maps to1,2,4,8,16 completed fresh source frames, not HDMI refreshes.
// Capture is accepted only in LIVE+STROBE; releases freeze and closes menu.
module case4_v8_controls #(
    parameter integer CLK_HZ=148800000,
    parameter integer DEBOUNCE_CYCLES=CLK_HZ/50,
    parameter integer LONG_CYCLES=(CLK_HZ/10)*7,
    parameter integer VERY_LONG_CYCLES=CLK_HZ*2,
    parameter integer CHORD_CYCLES=CLK_HZ,
    parameter integer INITIAL_THRESHOLD=128
)(
    input wire clk,rst_n,input wire [1:0] key_n,input wire frame_start,
    output reg [10:0] threshold,output reg [2:0] mode,
    output reg median_enable,freeze_request,
    output reg [1:0] history_mode,output reg history_paused,
    output reg step_prev_toggle,step_next_toggle,reference_toggle,
    output reg [1:0] app_mode,output reg auto_enable,
    output reg thick_enable,temporal_enable,
    output reg [2:0] effect_mode,strobe_interval,
    output reg strobe_capture_toggle,
    output reg menu_open,output reg [3:0] menu_index
);
    localparam integer DB_LIMIT=DEBOUNCE_CYCLES>0?DEBOUNCE_CYCLES:1;
    localparam integer LONG_LIMIT=LONG_CYCLES>0?LONG_CYCLES:1;
    localparam integer VERY_LIMIT=VERY_LONG_CYCLES>LONG_LIMIT?VERY_LONG_CYCLES:LONG_LIMIT+1;
    localparam integer CHORD_LIMIT=CHORD_CYCLES>0?CHORD_CYCLES:1;
    localparam integer DB_W=DB_LIMIT>1?$clog2(DB_LIMIT):1;
    localparam integer HOLD_MAX=CHORD_LIMIT>VERY_LIMIT?CHORD_LIMIT:VERY_LIMIT;
    localparam integer HOLD_W=$clog2(HOLD_MAX+1);
    (* async_reg="true" *) reg [1:0] key_meta,key_sync;
    reg [1:0] key_stable;
    reg [DB_W-1:0] debounce_count[0:1];
    integer k;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            key_meta<=3;key_sync<=3;key_stable<=3;
            debounce_count[0]<=0;debounce_count[1]<=0;
        end else begin
            key_meta<=key_n;key_sync<=key_meta;
            for(k=0;k<2;k=k+1) begin
                if(key_sync[k]==key_stable[k]) debounce_count[k]<=0;
                else if(debounce_count[k]>=DB_LIMIT-1) begin
                    key_stable[k]<=key_sync[k];debounce_count[k]<=0;
                end else debounce_count[k]<=debounce_count[k]+1'b1;
            end
        end
    end
    localparam [2:0] IDLE=0,KEY1=1,KEY2=2,CHORD=3,CONSUMED=4;
    reg [2:0] state;
    reg [HOLD_W-1:0] held;
    reg [10:0] threshold_pending;
    reg [1:0] history_pending,app_pending;
    reg [2:0] mode_pending,effect_pending,interval_pending;
    reg median_pending,freeze_pending,paused_pending,auto_pending,thick_pending;
    reg prev_pending,next_pending,reference_pending,capture_pending,temporal_pending;
    reg menu_pending;
    reg [3:0] index_pending;
    wire [1:0] pressed=~key_stable;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE;held<=0;
            threshold_pending<=INITIAL_THRESHOLD;threshold<=INITIAL_THRESHOLD;
            mode_pending<=0;mode<=0;median_pending<=1;median_enable<=1;
            freeze_pending<=0;freeze_request<=0;history_pending<=0;history_mode<=0;
            paused_pending<=0;history_paused<=0;prev_pending<=0;step_prev_toggle<=0;
            next_pending<=0;step_next_toggle<=0;reference_pending<=0;reference_toggle<=0;
            app_pending<=0;app_mode<=0;auto_pending<=1;auto_enable<=1;
            effect_pending<=0;effect_mode<=0;thick_pending<=0;thick_enable<=0;
            interval_pending<=1;strobe_interval<=1;capture_pending<=0;strobe_capture_toggle<=0;
            temporal_pending<=1;temporal_enable<=1;menu_pending<=0;menu_open<=0;
            index_pending<=0;menu_index<=0;
        end else begin
            if(frame_start) begin
                threshold<=threshold_pending;mode<=mode_pending;median_enable<=median_pending;
                freeze_request<=freeze_pending;history_mode<=history_pending;history_paused<=paused_pending;
                step_prev_toggle<=prev_pending;step_next_toggle<=next_pending;reference_toggle<=reference_pending;
                app_mode<=app_pending;auto_enable<=auto_pending;thick_enable<=thick_pending;
                effect_mode<=effect_pending;strobe_interval<=interval_pending;
                strobe_capture_toggle<=capture_pending;temporal_enable<=temporal_pending;
                menu_open<=menu_pending;menu_index<=index_pending;
            end
            case(state)
                IDLE: begin
                    held<=0;
                    case(pressed)
                        1:state<=KEY1;2:state<=KEY2;3:state<=CHORD;default:state<=IDLE;
                    endcase
                end
                KEY1,KEY2: begin
                    if(pressed==3 || (state==KEY1&&pressed==2) || (state==KEY2&&pressed==1)) begin
                        state<=pressed==3?CHORD:CONSUMED;held<=0;
                    end else if(pressed==0) begin
                        if(menu_pending) begin
                            if(state==KEY1) begin
                                if(held>=LONG_LIMIT) menu_pending<=0;
                                else index_pending<=index_pending==11?0:index_pending+1'b1;
                            end else if(held<LONG_LIMIT) begin
                                case(index_pending)
                                    0:app_pending<=app_pending==0?2'd3:2'd0;
                                    1:mode_pending<=mode_pending==5?3'd0:mode_pending+1'b1;
                                    2:auto_pending<=!auto_pending;
                                    3:begin threshold_pending<=threshold_pending>=1024?11'd16:threshold_pending+11'd16;auto_pending<=0;end
                                    4:median_pending<=!median_pending;
                                    5:thick_pending<=!thick_pending;
                                    6:effect_pending<=effect_pending==4?3'd0:effect_pending+1'b1;
                                    7:temporal_pending<=!temporal_pending;
                                    8:interval_pending<=interval_pending==4?3'd0:interval_pending+1'b1;
                                    9:if(history_pending==0 && app_pending==0 && effect_pending==4) begin
                                        capture_pending<=!capture_pending;freeze_pending<=0;menu_pending<=0;
                                      end
                                    10:begin
                                        if(history_pending==2) begin history_pending<=0;paused_pending<=0;end
                                        else begin history_pending<=history_pending+1'b1;paused_pending<=history_pending==1;end
                                        freeze_pending<=0;
                                    end
                                    11:if(history_pending!=0)paused_pending<=!paused_pending;
                                       else freeze_pending<=!freeze_pending;
                                    default:index_pending<=0;
                                endcase
                            end
                        end else if(state==KEY1&&held>=VERY_LIMIT) begin
                            if(history_pending==2) begin history_pending<=0;paused_pending<=0;end
                            else begin history_pending<=history_pending+1'b1;paused_pending<=history_pending==1;end
                            freeze_pending<=0;
                        end else if(history_pending!=0) begin
                            if(held>=LONG_LIMIT) begin
                                if(state==KEY1) reference_pending<=!reference_pending;
                                else paused_pending<=!paused_pending;
                            end else begin
                                paused_pending<=1;
                                if(state==KEY1) prev_pending<=!prev_pending;else next_pending<=!next_pending;
                            end
                        end else if(held>=LONG_LIMIT) begin
                            if(state==KEY1) mode_pending<=mode_pending==5?3'd0:mode_pending+1'b1;else freeze_pending<=!freeze_pending;
                        end else begin
                            auto_pending<=0;
                            if(state==KEY1) threshold_pending<=threshold_pending>=1008?11'd1024:threshold_pending+11'd16;
                            else threshold_pending<=threshold_pending<=32?11'd16:threshold_pending-11'd16;
                        end
                        state<=IDLE;held<=0;
                    end else if(held<VERY_LIMIT) held<=held+1'b1;
                end
                CHORD: begin
                    if(pressed!=3) begin state<=pressed==0?IDLE:CONSUMED;held<=0;end
                    else if(held>=CHORD_LIMIT-1) begin menu_pending<=!menu_pending;state<=CONSUMED;held<=0;end
                    else held<=held+1'b1;
                end
                CONSUMED: begin held<=0;if(pressed==0) state<=IDLE;end
                default:begin state<=IDLE;held<=0;end
            endcase
        end
    end
endmodule
