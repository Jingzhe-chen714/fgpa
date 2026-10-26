`timescale 1ns/1ps
// Per-task statistics. Luminance samples come from the pinned processing RGB
// raster; gradient samples arrive after the image pipeline. finish follows
// the last gradient, so all RGB samples have already been accumulated.
// Never modifies an in-flight threshold. Caller latches next_threshold at start.
module case4_v8_auto_threshold(
 input wire clk,rst,start,valid,finish,input wire [10:0] magnitude,
 input wire luma_valid,input wire [7:0] luma,
 output reg [10:0] next_threshold,output reg ready,
 output reg [7:0] mean_luma,output reg [10:0] target_threshold
);
 localparam CLEAR=0,COLLECT=1,DRAIN=2,SCAN=3,DIVIDE=4,TARGET=5,UPDATE=6,IDLE=7;
 reg [2:0] state;
 reg [21:0] hist[0:127];
 reg [6:0] clear_addr,bin_d,forward_bin,scan_addr;
 reg [21:0] hist_q,total,cumulative,forward_value;
 reg pending,forward_valid,scan_wait,found50,found85;
 reg [2:0] drain_count;
 reg [10:0] p50,p85;
 reg [31:0] light_sum,dividend,quotient,divisor,remainder;
 reg [21:0] light_count;
 reg [5:0] divide_left;
 reg [7:0] old_luma;
 reg [10:0] candidate;
 wire take=state==COLLECT&&valid&&magnitude!=0;
 wire [6:0] bucket=magnitude>=1024?7'd127:magnitude[9:3];
 wire [21:0] old_count=forward_valid&&forward_bin==bin_d?forward_value:hist_q;
 wire [21:0] increment=old_count+1'b1;
 wire [32:0] shifted_remainder={remainder,dividend[31]};
 wire subtract_ok=shifted_remainder>={1'b0,divisor};
 wire [31:0] next_quotient={quotient[30:0],subtract_ok};
 wire [11:0] noise_floor=(p50>>1)+12'd8;
 wire [11:0] contrast_floor={1'b0,p85}-(p85>>2);
 wire [11:0] base=noise_floor>contrast_floor?noise_floor:contrast_floor;
 wire [7:0] dark_penalty=mean_luma<80?(8'd80-mean_luma)>>1:0;
 wire [12:0] proposed={1'b0,base}+dark_penalty;
 wire [7:0] light_delta=mean_luma>old_luma?mean_luma-old_luma:old_luma-mean_luma;
 wire [11:0] filtered=light_delta>=12?({1'b0,next_threshold}+candidate+1)>>1:
                       (({1'b0,next_threshold}<<1)+next_threshold+candidate+2)>>2;
 wire [11:0] max_step=light_delta>=12?12'd48:12'd16;
 wire hist_we=state==CLEAR||pending;
 wire [6:0] hist_wa=state==CLEAR?clear_addr:bin_d;
 wire [21:0] hist_wd=state==CLEAR?22'd0:increment;
 wire hist_re=take||(state==SCAN&&!scan_wait);
 wire [6:0] hist_ra=take?bucket:scan_addr;
 always @(posedge clk)begin
  if(hist_we)hist[hist_wa]<=hist_wd;
  if(hist_re)hist_q<=hist[hist_ra];
 end
 always @(posedge clk)begin
  if(rst)begin
   state<=CLEAR;clear_addr<=0;next_threshold<=128;ready<=0;
   total<=0;cumulative<=0;pending<=0;forward_valid<=0;forward_bin<=0;forward_value<=0;bin_d<=0;
   scan_addr<=0;scan_wait<=0;found50<=0;found85<=0;drain_count<=0;p50<=0;p85<=0;
   light_sum<=0;light_count<=0;dividend<=0;quotient<=0;divisor<=1;remainder<=0;divide_left<=0;
   mean_luma<=128;old_luma<=128;candidate<=128;target_threshold<=128;
  end else if(start)begin
   state<=CLEAR;clear_addr<=0;total<=0;pending<=0;forward_valid<=0;ready<=0;
   light_sum<=0;light_count<=0;
  end else begin
   pending<=take;forward_valid<=pending;
   if(take)begin bin_d<=bucket;total<=total+1'b1;end
   if(pending)begin forward_bin<=bin_d;forward_value<=increment;end
   if((state==CLEAR||state==COLLECT)&&luma_valid)begin
    light_sum<=light_sum+luma;light_count<=light_count+1'b1;
   end
   case(state)
    CLEAR:if(clear_addr==127)begin state<=COLLECT;clear_addr<=0;end else clear_addr<=clear_addr+1'b1;
    COLLECT:if(finish)begin state<=DRAIN;drain_count<=0;end
    DRAIN:if(drain_count==3)begin
     cumulative<=0;scan_addr<=0;scan_wait<=0;found50<=0;found85<=0;p50<=0;p85<=0;state<=SCAN;
    end else drain_count<=drain_count+1'b1;
    SCAN:if(!scan_wait)scan_wait<=1;else begin
     scan_wait<=0;cumulative<=cumulative+hist_q;
     if(total!=0&&!found50&&cumulative+hist_q>=((total+1)>>1))begin p50<={1'b0,scan_addr,3'b100};found50<=1;end
     // 84.375th percentile = 1 - 1/8 - 1/32.
     if(total!=0&&!found85&&cumulative+hist_q>=total-(total>>3)-(total>>5))begin p85<={1'b0,scan_addr,3'b100};found85<=1;end
     if(scan_addr==127)begin
      dividend<=light_sum;divisor<=light_count==0?1:light_count;remainder<=0;quotient<=0;divide_left<=32;state<=DIVIDE;
     end else scan_addr<=scan_addr+1'b1;
    end
    DIVIDE:begin
     dividend<={dividend[30:0],1'b0};quotient<=next_quotient;
     remainder<=subtract_ok?shifted_remainder-{1'b0,divisor}:shifted_remainder;
     divide_left<=divide_left-1'b1;
     if(divide_left==1)begin if(light_count!=0)mean_luma<=next_quotient[7:0];state<=TARGET;end
    end
    TARGET:begin
     candidate<=proposed<16?11'd16:proposed>768?11'd768:proposed[10:0];state<=UPDATE;
    end
    UPDATE:begin
     target_threshold<=candidate;old_luma<=mean_luma;
     if(filtered>next_threshold+2)next_threshold<=filtered>next_threshold+max_step?next_threshold+max_step:filtered[10:0];
     else if(filtered+2<next_threshold)next_threshold<=filtered+max_step<next_threshold?next_threshold-max_step:filtered[10:0];
     ready<=1;state<=IDLE;
    end
    default:begin end
   endcase
  end
 end
endmodule
