// Default-size mapping wrapper.  External memory and video PHY stay as
// blackboxes, so the report reflects the real renderer/control datapath and
// inferred line buffers without allocating a simulation memory model.
module case2_rtl_probe_top_full (
    input  logic clk_in,
    input  logic rst_n_in,
    input  logic csr_valid,
    input  logic csr_write,
    input  logic [11:0] csr_addr,
    input  logic [31:0] csr_wdata,
    output logic [31:0] csr_rdata,
    output logic csr_ready,
    output logic video_clk,
    output logic video_valid,
    output logic [15:0] video_data,
    output logic video_de,
    output logic video_hsync,
    output logic video_vsync,
    output logic video_init_done,
    output logic video_init_error
);
    logic unused_clock_locked;
    logic unused_mem_init_done;
    logic unused_mem_init_error;
    logic unused_system_busy;
    logic unused_system_error;
    logic unused_active_page;
    logic unused_pending_page;
    logic unused_page_flip_pending;
    logic unused_display_underflow;
    logic [31:0] unused_submit_count;
    logic [31:0] unused_completed_count;

    c2_renderer_system #(
        .USE_EXT_MEM_IP(1'b1),
        .USE_VIDEO_PHY_IP(1'b1),
        .USE_CLOCK_RESET_IP(1'b0)
    ) u_system (
        .clk_in,
        .rst_n_in,
        .csr_valid,
        .csr_write,
        .csr_addr,
        .csr_wdata,
        .csr_rdata,
        .csr_ready,
        .ext_mem_init_done(1'b1),
        .ext_mem_init_error(1'b0),
        .m_axi_awready(1'b0),
        .m_axi_wready(1'b0),
        .m_axi_bid(4'd0),
        .m_axi_bresp(2'b00),
        .m_axi_bvalid(1'b0),
        .m_axi_arready(1'b0),
        .m_axi_rid(4'd0),
        .m_axi_rdata(128'd0),
        .m_axi_rresp(2'b00),
        .m_axi_rlast(1'b0),
        .m_axi_rvalid(1'b0),
        .video_clk,
        .video_valid,
        .video_data,
        .video_de,
        .video_hsync,
        .video_vsync,
        .video_init_done,
        .video_init_error,
        .clock_locked(unused_clock_locked),
        .mem_init_done(unused_mem_init_done),
        .mem_init_error(unused_mem_init_error),
        .system_busy(unused_system_busy),
        .system_error(unused_system_error),
        .active_page(unused_active_page),
        .pending_page(unused_pending_page),
        .page_flip_pending(unused_page_flip_pending),
        .display_underflow(unused_display_underflow),
        .command_submit_count(unused_submit_count),
        .command_completed_count(unused_completed_count)
    );
endmodule
