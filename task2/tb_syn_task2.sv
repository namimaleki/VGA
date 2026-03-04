`timescale 1ns/1ps
module tb_syn_task2();

    // 1) Reset triggers an automatic clear to black (VGA_PLOT=1, VGA_COLOUR=000).
    // 2) After ~19200 cycles, the clear is finished and the design waits for start
    // 3) Pressing start begins plotting stripes (VGA_PLOT should go high again).
    // 4) When plotting completes, done asserts

    logic CLOCK_50;
    logic [3:0] KEY;
    logic [9:0] SW;
    logic [9:0] LEDR;
    logic [7:0] VGA_R,VGA_G,VGA_B;
    logic VGA_HS,VGA_VS,VGA_CLK;
    logic [7:0] VGA_X;
    logic [6:0] VGA_Y;
    logic [2:0] VGA_COLOUR;
    logic VGA_PLOT;

    task2 UUT(
        .CLOCK_50(CLOCK_50),
        .KEY(KEY),
        .SW(SW),
        .LEDR(LEDR),
        .HEX0(),.HEX1(),.HEX2(),.HEX3(),.HEX4(),.HEX5(),
        .VGA_R(VGA_R),.VGA_G(VGA_G),.VGA_B(VGA_B),
        .VGA_HS(VGA_HS),.VGA_VS(VGA_VS),.VGA_CLK(VGA_CLK),
        .VGA_X(VGA_X),.VGA_Y(VGA_Y),
        .VGA_COLOUR(VGA_COLOUR),.VGA_PLOT(VGA_PLOT)
    );

    // 50MHz clock (period = 20ns)
    initial CLOCK_50 = 1'b0;
    always #10 CLOCK_50 = ~CLOCK_50;

    // HELPERS similar to fillscreen 
    task automatic step_cycle();
        @(posedge CLOCK_50);
        #1;
    endtask

    task automatic assert_in_bounds();
        begin
            if(VGA_PLOT) begin
                assert(VGA_X <= 8'd159) else $error("OOB x: %0d", VGA_X);
                assert(VGA_Y <= 7'd119) else $error("OOB y: %0d", VGA_Y);
            end
        end
    endtask

    initial begin
        // Initialize switches and buttons
        // KEY bits default high (not pressed). KEY[3]=reset, KEY[0]=start.
        KEY = 4'hF;
        SW = 10'd0;

        // TEST 1: reset triggers clear
        // KEY[3] is active-low reset. While clearing, we expect black pixels to be written.
        KEY[3] = 1'b0;
        step_cycle();

        assert(LEDR[0] == 1'b0) else $error("TEST1 FAIL: done should be 0 on reset");
        assert(VGA_PLOT == 1'b1) else $error("TEST1 FAIL: VGA_PLOT should be 1 in CLEAR");
        assert(VGA_COLOUR == 3'b000) else $error("TEST1 FAIL: VGA_COLOUR should be black in CLEAR");

        // Release reset
        KEY[3] = 1'b1;

        // Let the clear finish.
        // Clear is 160*120 = 19200 pixels, one write per cycle.
        repeat(19200) begin
            step_cycle();
            assert_in_bounds();
            // During clear, colour should be black whenever plotting
            if(VGA_PLOT) begin
                assert(VGA_COLOUR == 3'b000) else $error("CLEAR colour not black: %0d at (%0d,%0d)", VGA_COLOUR, VGA_X, VGA_Y);
            end
        end

        // TEST 2: press start and confirm plotting begins
        SW[2:0] = 3'b101; 
        KEY[0] = 1'b0;

        // Give it a couple cycles to leave WAIT and enter PLOT
        repeat(2) begin
            step_cycle();
            assert_in_bounds();
        end

        assert(VGA_PLOT == 1'b1) else $error("TEST2 FAIL: VGA_PLOT should be 1 during PLOT");

        // Wait for the plot pass to finish.
        // For stripes, it should still be 19200 pixel writes total.
        repeat(19198) begin
            step_cycle();
            assert_in_bounds();
        end

        // Release start
        KEY[0] = 1'b1;

        // TEST 3: done should assert at the end
        step_cycle();
        assert(LEDR[0] == 1'b1) else $error("TEST3 FAIL: LEDR[0] should be 1 when done");

        $display("tb_syn_task2: ALL TESTS PASSED");
        $finish(0);
    end

endmodule: tb_syn_task2