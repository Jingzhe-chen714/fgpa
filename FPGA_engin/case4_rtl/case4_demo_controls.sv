`timescale 1ns/1ps
// V7 two-key controls. All public values and command toggles publish only at
// frame_start. Single-key gestures fire on release. A chord consumes both keys
// until BOTH have been released, including staggered releases and bounce.
// Outside menu the V6 gestures remain: short +/-; K1 >=0.7s edge mode;
// K2 >=0.7s freeze; K1 >=2s cycles LIVE/REPLAY/CONTOUR. History uses prev/next,
// reference and pause exactly as V6. Both >=1s now open/close the menu.
// Menu: short K1 next, short K2 change/execute, long K1 close; long K2 ignored.
// THR advances by16 and wraps1024->16 in menu. Manual +/- always disables AUTO.
// Menu indices: APP, EDGE, AUTO, THR, MEDIAN, NOISE, THICK, LEARN, CLEAR, EVENT.
module case4_demo_controls #(
    parameter integer CLK_HZ=148800000,
    parameter integer DEBOUNCE_CYCLES=CLK_HZ/50,
    parameter integer LONG_CYCLES=(CLK_HZ/10)*7,
    parameter integer VERY_LONG_CYCLES=CLK_HZ*2,
    parameter integer CHORD_CYCLES=CLK_HZ,
    parameter integer INITIAL_THRESHOLD=128
)(
    input wire clk,rst_n,input wire [1:0] key_n,input wire frame_start,
    output reg [10:0] threshold,output reg [1:0] mode,
    output reg median_enable,freeze_request,
    output reg [1:0] history_mode,output reg history_paused,
    output reg step_prev_toggle,step_next_toggle,reference_toggle,
    output reg [1:0] app_mode,output reg auto_enable,
    output reg [1:0] noise_level,output reg thick_enable,
    output reg learn_toggle,clear_toggle,event_recall_toggle,
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
    reg [1:0] mode_pending,history_pending,app_pending,noise_pending;
    reg median_pending,freeze_pending,paused_pending,auto_pending,thick_pending;
    reg prev_pending,next_pending,reference_pending,learn_pending,clear_pending,event_pending;
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
            app_pending<=0;app_mode<=0;auto_pending<=0;auto_enable<=0;
            noise_pending<=0;noise_level<=0;thick_pending<=0;thick_enable<=0;
            learn_pending<=0;learn_toggle<=0;clear_pending<=0;clear_toggle<=0;
            event_pending<=0;event_recall_toggle<=0;menu_pending<=0;menu_open<=0;
            index_pending<=0;menu_index<=0;
        end else begin
            if(frame_start) begin
                threshold<=threshold_pending;mode<=mode_pending;median_enable<=median_pending;
                freeze_request<=freeze_pending;history_mode<=history_pending;history_paused<=paused_pending;
                step_prev_toggle<=prev_pending;step_next_toggle<=next_pending;reference_toggle<=reference_pending;
                app_mode<=app_pending;auto_enable<=auto_pending;noise_level<=noise_pending;thick_enable<=thick_pending;
                learn_toggle<=learn_pending;clear_toggle<=clear_pending;event_recall_toggle<=event_pending;
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
                                else index_pending<=index_pending==9?0:index_pending+1'b1;
                            end else if(held<LONG_LIMIT) begin
                                case(index_pending)
                                    0:app_pending<=app_pending+1'b1;
                                    1:mode_pending<=mode_pending+1'b1;
                                    2:auto_pending<=!auto_pending;
                                    3:begin threshold_pending<=threshold_pending>=1024?11'd16:threshold_pending+11'd16;auto_pending<=0;end
                                    4:median_pending<=!median_pending;
                                    5:noise_pending<=noise_pending==2?0:noise_pending+1'b1;
                                    6:thick_pending<=!thick_pending;
                                    7:learn_pending<=!learn_pending;
                                    8:clear_pending<=!clear_pending;
                                    9:begin event_pending<=!event_pending;history_pending<=1;paused_pending<=1;freeze_pending<=0;end
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
                            if(state==KEY1) mode_pending<=mode_pending+1'b1;else freeze_pending<=!freeze_pending;
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
