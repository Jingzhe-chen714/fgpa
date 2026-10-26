`timescale 1ns/1ps
// Canonical V12 control state. PC and physical keys use the same command path.
// Action FIFO entries remain visible until explicit host acknowledgement.
module case4_v11_controls #(
 parameter integer CLK_HZ=148800000,DEBOUNCE_CYCLES=CLK_HZ/50,
 LONG_CYCLES=(CLK_HZ/10)*7,VERY_LONG_CYCLES=CLK_HZ*2,CHORD_CYCLES=CLK_HZ,
 WATCHDOG_CYCLES=CLK_HZ*3,INITIAL_THRESHOLD=192,EVENT_DEPTH=16
)(
 input wire clk,rst_n,frame_start,input wire [1:0] key_n,
 input wire heartbeat,input wire cmd_valid,input wire [7:0] cmd_id,
 input wire [15:0] cmd_arg0,cmd_arg1,cmd_arg2,cmd_arg3,
 output wire cmd_accept,output wire [7:0] cmd_result,
 output reg [10:0] threshold,output reg [2:0] mode,
 output reg [1:0] median_mode,app_mode,view_mode,accessory,
 output reg [1:0] effect_mode,
 output reg gamma_enable,freeze_request,history_paused,temporal_enable,
 output reg geometry_enable,bilateral_enable,bridge_enable,split_enable,hud_enable,
 output reg menu_open,output reg [4:0] menu_index,
 output reg [10:0] roi_x0,roi_y0,roi_x1,roi_y1,
 output wire [7:0] event_code,output wire [31:0] event_seq,
 output reg [31:0] config_revision,output reg link_lost,event_overflow,
 output reg step_prev_toggle,step_next_toggle,capture_mask,reference_toggle,
 output reg capture_a_toggle,capture_b_toggle,clear_pair_toggle,
 input wire [7:0] source_kind,output_mode,input wire capture_mask_active,
 input wire [31:0] display_source_id,input wire [5:0] selected_index,input wire [6:0] history_count,
 input wire [4:0] geometry_valid,input wire [7:0] circle_score,rectangle_score,triangle_score,ellipse_score,
 input wire [7:0] parallel_score,
 input wire geometry_busy,geometry_overflow,input wire [2:0] geometry_reject,input wire [7:0] geometry_candidates,
 input wire [15:0] geometry_observed,geometry_analyses,geometry_timeouts,geometry_dropped,
 input wire [7:0] face_count,face_flags,face_fault,pair_flags,
 input wire [31:0] face_batch_id,face_source_id,face_revision,pair_a_source_id,pair_b_source_id,pair_a_signature,pair_b_signature,
 input wire [5:0] reference_index,
 output wire [767:0] status_data,input wire board_fault
);
 localparam integer DB_LIMIT=DEBOUNCE_CYCLES>0?DEBOUNCE_CYCLES:1;
 localparam integer LONG_LIMIT=LONG_CYCLES>0?LONG_CYCLES:1;
 localparam integer VERY_LIMIT=VERY_LONG_CYCLES>LONG_LIMIT?VERY_LONG_CYCLES:LONG_LIMIT+1;
 localparam integer CHORD_LIMIT=CHORD_CYCLES>0?CHORD_CYCLES:1;
 localparam integer DB_W=DB_LIMIT>1?$clog2(DB_LIMIT):1;
 localparam integer HOLD_MAX=CHORD_LIMIT>VERY_LIMIT?CHORD_LIMIT:VERY_LIMIT;
 localparam integer HOLD_W=$clog2(HOLD_MAX+1),WD_W=$clog2(WATCHDOG_CYCLES+1);
 localparam integer EC=$clog2(EVENT_DEPTH+1);
 (* async_reg="true" *) reg [1:0] key_meta,key_sync;
 reg [1:0] key_stable;
 reg [DB_W-1:0] debounce_count[0:1];
 integer k;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin key_meta<=3;key_sync<=3;key_stable<=3;debounce_count[0]<=0;debounce_count[1]<=0;end
  else begin
   key_meta<=key_n;key_sync<=key_meta;
   for(k=0;k<2;k=k+1)begin
    if(key_sync[k]==key_stable[k])debounce_count[k]<=0;
    else if(debounce_count[k]>=DB_LIMIT-1)begin key_stable[k]<=key_sync[k];debounce_count[k]<=0;end
    else debounce_count[k]<=debounce_count[k]+1'b1;
   end
  end
 end
 localparam IDLE=0,KEY1=1,KEY2=2,CHORD=3,CONSUMED=4;
 reg [2:0] key_state;reg [HOLD_W-1:0] held;wire [1:0] pressed=~key_stable;
 reg key_pending;reg [7:0] key_id;reg [15:0] key_a,key_b,key_c,key_d;
 reg [WD_W-1:0] watchdog;
 // Only screenshot requests enter this queue. Their codes are identical and
 // their allocated sequence numbers are consecutive (FFFFFFFF wraps to 1).
 // Store the head sequence and occupancy, instead of duplicating 16 sequence
 // registers plus an asynchronous read mux. Capacity and ACK semantics match
 // the original FIFO, including retained requests while the PC is absent.
 reg [31:0] head_sequence;reg [EC-1:0] count;
 reg [31:0] next_sequence,last_acked;reg acked_valid;
 assign event_code=count!=0?8'h28:8'd0;
 assign event_seq=count!=0?head_sequence:32'd0;
 wire uart_apply=cmd_valid&&(frame_start||cmd_id==8'h30||cmd_id==8'h20);
 wire key_apply=key_pending&&frame_start&&!uart_apply;
 wire apply_command=uart_apply||key_apply;
 wire [7:0] cid=uart_apply?cmd_id:key_id;
 wire [15:0] a=uart_apply?cmd_arg0:key_a,b=uart_apply?cmd_arg1:key_b,
 c=uart_apply?cmd_arg2:key_c,d=uart_apply?cmd_arg3:key_d;
 // Board actions never depend on a host event ACK: offline buttons stay usable.
 wire action=cid==8'h28;
 wire ack_current=count!=0&&{b,a}==event_seq;
 wire ack_duplicate=acked_valid&&{b,a}==last_acked;
 reg legal;
 always @*begin
  legal=0;
  case(cid)
   8'h01:legal=a<=4;
   8'h02,8'h08,8'h0b,8'h16,8'h18,8'h20,8'h21,8'h22,8'h32:legal=a<=1;
   8'h03:legal=a>=16&&a<=1024;
   8'h04,8'h06,8'h23:legal=a<=2;
   8'h07:legal=a<=3;
   8'h05:legal=a==0||a==3;
   8'h10:legal=a<c&&b<d&&c<1920&&d<1080;
   8'h09,8'h0a,8'h17,8'h26,8'h28:legal=1;
   8'h24,8'h25:legal=app_mode==0&&view_mode<2;
   8'h33:legal=view_mode==1||view_mode==3;
   8'h30:legal=ack_current||ack_duplicate;
   8'h31:legal=a<=1&&(a==0||(mode<=4&&app_mode==0&&view_mode<2));
   default:legal=0;
  endcase
 end
 wire full=action&&count==EVENT_DEPTH;
 assign cmd_accept=uart_apply;
 wire pair_locked=pair_flags[2]&&cid!=8'hf1&&cid!=8'h30&&cid!=8'h28;
 assign cmd_result=!legal?8'd1:pair_locked?8'd3:full?8'd2:8'd0;
 wire accepted=apply_command&&legal&&!full&&!pair_locked;
 wire [7:0] flags={bilateral_enable,geometry_enable,bridge_enable,menu_open,temporal_enable,history_paused,freeze_request,gamma_enable};
 wire [7:0] faults={5'b0,event_overflow,link_lost,board_fault};
 assign status_data={56'd0,face_fault,pair_b_signature,pair_a_signature,face_revision,face_source_id,
  pair_b_source_id,pair_a_source_id,2'd0,reference_index,pair_flags,face_batch_id,face_flags,face_count,parallel_score,6'd0,hud_enable,split_enable,geometry_dropped,geometry_timeouts,geometry_analyses,geometry_observed,geometry_candidates,5'd0,geometry_reject,6'd0,geometry_overflow,geometry_busy,8'd0,triangle_score,rectangle_score,(circle_score>ellipse_score?circle_score:ellipse_score),3'd0,geometry_valid[4],1'b0,geometry_valid[2:1],(geometry_valid[0]|geometry_valid[3]),1'b0,history_count,2'd0,selected_index,display_source_id,
  config_revision,7'd0,capture_mask_active,output_mode,source_kind,faults,event_seq,event_code,{3'd0,menu_index},
  5'd0,roi_y1,5'd0,roi_x1,5'd0,roi_y0,5'd0,roi_x0,5'd0,threshold,
  6'd0,view_mode,6'd0,accessory,6'd0,median_mode,flags,6'd0,effect_mode,6'd0,app_mode,5'd0,mode,8'd12};
 task keycmd(input [7:0] id,input [15:0] value);
 begin key_pending<=1;key_id<=id;key_a<=value;key_b<=0;key_c<=0;key_d<=0;end endtask
 task keyroi(input [15:0] x0,input [15:0] y0,input [15:0] x1,input [15:0] y1);
 begin key_pending<=1;key_id<=8'h10;key_a<=x0;key_b<=y0;key_c<=x1;key_d<=y1;end endtask
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   threshold<=INITIAL_THRESHOLD;mode<=0;median_mode<=2;app_mode<=0;view_mode<=0;accessory<=1;
   effect_mode<=0;gamma_enable<=1;freeze_request<=0;history_paused<=0;temporal_enable<=1;
   geometry_enable<=0;bilateral_enable<=0;bridge_enable<=0;split_enable<=0;hud_enable<=1;menu_open<=0;menu_index<=0;
   roi_x0<=320;roi_y0<=180;roi_x1<=1599;roi_y1<=899;
   key_state<=IDLE;held<=0;key_pending<=0;key_id<=0;key_a<=0;key_b<=0;key_c<=0;key_d<=0;
   head_sequence<=1;count<=0;next_sequence<=1;last_acked<=0;acked_valid<=0;
   watchdog<=0;link_lost<=0;event_overflow<=0;config_revision<=0;step_prev_toggle<=0;step_next_toggle<=0;capture_mask<=0;reference_toggle<=0;capture_a_toggle<=0;capture_b_toggle<=0;clear_pair_toggle<=0;
  end else begin
   if(heartbeat)watchdog<=0;
   else if(bridge_enable)begin
    if(watchdog>=WATCHDOG_CYCLES-1)begin bridge_enable<=0;capture_mask<=0;link_lost<=1;watchdog<=0;config_revision<=config_revision+1'b1;end
    else watchdog<=watchdog+1'b1;
   end else watchdog<=0;
   if(key_apply&&!full)key_pending<=0;
   if(key_apply&&full)event_overflow<=1;
   // Pending commands survive UART arbitration and a full action queue.
   if(!key_pending)case(key_state)
    IDLE:begin held<=0;case(pressed)1:key_state<=KEY1;2:key_state<=KEY2;3:key_state<=CHORD;default:;endcase end
    KEY1,KEY2:begin
     if(pressed==3||(key_state==KEY1&&pressed==2)||(key_state==KEY2&&pressed==1))begin key_state<=pressed==3?CHORD:CONSUMED;held<=0;end
     else if(pressed==0)begin
      if(menu_open)begin
       if(key_state==KEY1)begin
        if(held>=LONG_LIMIT)menu_open<=0;else menu_index<=menu_index==23?0:menu_index+1'b1;
        config_revision<=config_revision+1'b1;
       end else if(held<LONG_LIMIT)case(menu_index)
        0:keycmd(8'h05,app_mode==0?3:0);
        1:keycmd(8'h01,mode==4?0:mode+1);
        2:keycmd(8'h03,threshold>=1024?16:threshold+16);
        3:keycmd(8'h04,median_mode==2?0:median_mode+1);
        4:keycmd(8'h02,!gamma_enable);
        5:keycmd(8'h16,!temporal_enable);
        6:keycmd(8'h06,effect_mode==2?0:effect_mode+1);
        7:keycmd(8'h21,!geometry_enable);
        8:keycmd(8'h22,!bilateral_enable);
        9:keycmd(8'h23,accessory==2?0:accessory+1);
        10:keycmd(8'h07,view_mode==3?0:view_mode+1);
        11:keycmd(8'h08,!freeze_request);
        12:keycmd(8'h0b,!history_paused);
        13:keycmd(8'h09,0);14:keycmd(8'h0a,0);
        15:keycmd(8'h17,0);
        16:keycmd(8'h24,0);17:keycmd(8'h25,0);18:keycmd(8'h26,0);
        19:keycmd(8'h28,0);20:keycmd(8'h20,!bridge_enable);
        21:keycmd(8'h32,!split_enable);22:keycmd(8'h33,0);
        23:keycmd(8'h18,!hud_enable);
        default:;
       endcase
      end else if(key_state==KEY1&&held>=VERY_LIMIT)keycmd(8'h07,view_mode==3?0:view_mode+1);
      else if(view_mode!=0)begin
       if(held>=LONG_LIMIT)begin if(key_state==KEY2)keycmd(8'h0b,!history_paused);else if(view_mode==1||view_mode==3)keycmd(8'h33,0);end
       else keycmd(key_state==KEY1?8'h09:8'h0a,0);
      end else if(held>=LONG_LIMIT)keycmd(key_state==KEY1?8'h01:8'h08,key_state==KEY1?(mode==4?0:mode+1):!freeze_request);
      else keycmd(8'h03,key_state==KEY1?(threshold>=1008?1024:threshold+16):(threshold<=32?16:threshold-16));
      key_state<=IDLE;held<=0;
     end else if(held<HOLD_MAX)held<=held+1'b1;
    end
    CHORD:if(pressed!=3)begin key_state<=pressed==0?IDLE:CONSUMED;held<=0;end
     else if(held>=CHORD_LIMIT-1)begin menu_open<=!menu_open;config_revision<=config_revision+1'b1;key_state<=CONSUMED;held<=0;end
     else held<=held+1'b1;
    CONSUMED:if(pressed==0)key_state<=IDLE;
    default:key_state<=IDLE;
   endcase
   if(accepted)begin
    if(cid!=8'h30)config_revision<=config_revision+1'b1;
    if(action)begin
     if(count==0)head_sequence<=next_sequence;
     count<=count+1'b1;next_sequence<=next_sequence == 32'hffffffff ? 32'd1 : next_sequence+1'b1;
    end
    case(cid)
     8'h01:mode<=a[2:0];8'h02:gamma_enable<=a[0];8'h03:threshold<=a[10:0];
     8'h04:median_mode<=a[1:0];8'h05:app_mode<=a[1:0];8'h06:effect_mode<=a[1:0];
     8'h07:begin view_mode<=a[1:0];history_paused<=a>=2;freeze_request<=0;capture_mask<=0;end
     8'h08:begin freeze_request<=a[0];if(view_mode!=0)history_paused<=a[0];end
     8'h09:begin history_paused<=1;step_prev_toggle<=!step_prev_toggle;end
     8'h0a:begin history_paused<=1;step_next_toggle<=!step_next_toggle;end
     8'h0b:history_paused<=a[0];
     8'h10:begin roi_x0<=a[10:0];roi_y0<=b[10:0];roi_x1<=c[10:0];roi_y1<=d[10:0];end
     8'h16:temporal_enable<=a[0];
     8'h18:begin hud_enable<=a[0];if(!a[0])menu_open<=0;end
     8'h17:begin roi_x0<=320;roi_y0<=180;roi_x1<=1599;roi_y1<=899;end
     8'h20:begin bridge_enable<=a[0];watchdog<=0;link_lost<=0;if(!a[0])capture_mask<=0;end
     8'h21:geometry_enable<=a[0];8'h22:bilateral_enable<=a[0];8'h23:accessory<=a[1:0];
     8'h30:if(ack_current)begin head_sequence<=head_sequence==32'hffffffff ? 32'd1 : head_sequence+1'b1;count<=count-1'b1;last_acked<={b,a};acked_valid<=1;end
     8'h31:capture_mask<=a[0];
     8'h32:split_enable<=a[0];
     8'h33:begin reference_toggle<=!reference_toggle;history_paused<=1;end
     8'h24:capture_a_toggle<=!capture_a_toggle;
     8'h25:capture_b_toggle<=!capture_b_toggle;
     8'h26:clear_pair_toggle<=!clear_pair_toggle;
     default:;
    endcase
   end
  end
 end
endmodule

