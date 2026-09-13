`timescale 1ns/1ps
// Check that the legacy test's REFERENCE is itself fully initialized.
module tb_reference_sanity;
    tb_gray_median_sobel_core reference();
    initial begin
        #1;
        $display("REFERENCE_DIAGNOSTIC image11=%h med11=%h simple_median=%h",
                 reference.image[1][1],reference.med_image[1][1],reference.median9(1,2,3,4,5,6,7,8,9));
        for(integer y=1;y<5;y++) for(integer x=1;x<7;x++)
            if($isunknown(reference.med_image[y][x]))
                $fatal(1,"REFERENCE_UNINITIALIZED x=%0d y=%0d",x,y);
        $display("REFERENCE_SANITY_PASS");
    end
endmodule
