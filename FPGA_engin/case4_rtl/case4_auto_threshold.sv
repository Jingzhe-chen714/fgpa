`timescale 1ns/1ps
// Gradient histogram, 64 bins. A completed background task determines the
// next task's threshold. Zero gradients are excluded; no task is cancelled
// by this module. Two-stage same-bin forwarding supports II=1 histogramming.
module case4_auto_threshold(
 input wire clk,rst,start,valid,finish,input wire [10:0] magnitude,
 output reg [10:0] next_threshold,output reg ready
);
 reg [21:0] hist[0:63];
 reg [2:0] state;localparam CLEAR=0,COLLECT=1,DRAIN=2,SCAN=3,DONE=4;
 reg [5:0] clear_addr,read_bin,scan_addr,bin_d;
 reg [21:0] hist_q,total,cumulative,target;
 reg pending,forward_valid,finish_seen;reg [5:0] forward_bin;reg [21:0] forward_value;
 reg [2:0] drain_count;reg scan_wait,found;reg [10:0] candidate;
 wire take=state==COLLECT&&valid&&magnitude!=0;
 wire [5:0] bucket=magnitude[10:5];
 wire [21:0] old_count=forward_valid&&forward_bin==bin_d?forward_value:hist_q;
 wire [21:0] increment=old_count+1'b1;
 always @(posedge clk)begin
  if(state==CLEAR)hist[clear_addr]<=0;
  else if(pending)hist[bin_d]<=increment;
  if(take)hist_q<=hist[bucket];
  else if(state==SCAN&&!scan_wait)hist_q<=hist[scan_addr];
 end
 always @(posedge clk)begin
  if(rst)begin
   state<=CLEAR;clear_addr<=0;next_threshold<=128;ready<=0;total<=0;pending<=0;
   forward_valid<=0;forward_bin<=0;forward_value<=0;bin_d<=0;finish_seen<=0;
   drain_count<=0;scan_addr<=0;scan_wait<=0;found<=0;candidate<=128;cumulative<=0;target<=0;
  end else if(start)begin
   state<=CLEAR;clear_addr<=0;total<=0;pending<=0;forward_valid<=0;ready<=0;finish_seen<=0;
  end else begin
   pending<=take;
   if(take)begin bin_d<=bucket;total<=total+1'b1;end
   forward_valid<=pending;
   if(pending)begin forward_bin<=bin_d;forward_value<=increment;end
   case(state)
    CLEAR:if(clear_addr==63)begin state<=COLLECT;clear_addr<=0;end else clear_addr<=clear_addr+1'b1;
    COLLECT:if(finish)begin state<=DRAIN;drain_count<=0;end
    DRAIN:if(drain_count==3)begin
     // ~87.5th percentile among nonzero gradients, avoiding full divider.
     target<=total-(total>>3);cumulative<=0;scan_addr<=0;scan_wait<=0;found<=0;candidate<=128;state<=SCAN;
    end else drain_count<=drain_count+1'b1;
    SCAN:if(!scan_wait)scan_wait<=1;else begin
      scan_wait<=0;cumulative<=cumulative+hist_q;
      if(!found&&cumulative+hist_q>=target&&total>=64)begin
        candidate<=scan_addr<2?11'd64:scan_addr>15?11'd512:{scan_addr,5'b10000};found<=1;
      end
      if(scan_addr==63)state<=DONE;else scan_addr<=scan_addr+1'b1;
    end
    DONE:begin
      // Deadband + EMA limit visual threshold pumping; start latches next task.
      if(found)begin
       if(candidate>next_threshold+16 || candidate+16<next_threshold)
        next_threshold<=({2'b0,next_threshold}*3+candidate+2)>>2;
      end
      ready<=1;state<=3'd5;
    end
    default:begin end
   endcase
  end
 end
endmodule
