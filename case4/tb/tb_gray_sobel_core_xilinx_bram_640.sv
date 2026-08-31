`timescale 1ns/1ps

// Reuse the full-frame stream/count scoreboard with the Xilinx BRAM backend.
// Keeping this as a separate top-level avoids simulator-specific parameter
// override syntax in batch scripts while retaining one source of truth for
// the 640x480 checks.
module tb_gray_sobel_core_xilinx_bram_640;
    tb_gray_sobel_core_640 #(
        .WINDOW_BACKEND(1)
    ) u_scoreboard ();
endmodule
