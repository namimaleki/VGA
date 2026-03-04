`timescale 1ns/1ps
module tb_rtl_task2();

    // We treat task2 as a black box top-level and only check its external outputs:
    // 1) Reset (KEY[3] active-low) should trigger an automatic clear to black.
    // 2) After clear is done, pressing start (KEY[0] active-low) should begin plotting stripes.
    // 3) After plotting finishes, done should assert (we use LEDR[0] as done in your task2).
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

    initial begin
        // Initialize inputs to safe defaults
        KEY = 4'hF;
        SW = 10'd0;

        // TEST 1: reset behavior
        // KEY[3] is active-low synchronous reset 
        // During reset/clear, the design should be plotting black pixels (VGA_PLOT=1, VGA_COLOUR=000).
        KEY[3] = 1'b0;
        @(posedge CLOCK_50); #1;

        assert(LEDR[0] == 1'b0) else $error("TEST1 FAIL: done should be 0 on reset");
        assert(VGA_PLOT == 1'b1) else $error("TEST1 FAIL: VGA_PLOT should be 1 in CLEAR");
        assert(VGA_COLOUR == 3'b000) else $error("TEST1 FAIL: VGA_COLOUR should be black in CLEAR");

        // Release reset and let the auto-clear finish
        KEY[3] = 1'b1;

        // Wait for CLEAR to finish
        // Clear is 160*120 = 19200 pixels, one pixel per cycle.
        repeat(19200) @(posedge CLOCK_50); #1;

        // TEST 2: start plotting stripes
        // KEY[0] is active-low start button, start = ~KEY[0].
        // SW[2:0] is connected to colour input of fillscreen, but Task 2 ignores it.
        SW[2:0] = 3'b101;
        KEY[0] = 1'b0;

        // Give it a couple cycles to leave WAIT and enter PLOT
        repeat(2) @(posedge CLOCK_50); #1;

        assert(VGA_PLOT == 1'b1) else $error("TEST2 FAIL: VGA_PLOT should be 1 during PLOT");

        // Wait for PLOT to finish
        // We already spent a couple cycles entering PLOT, so we wait slightly less than 19200 here.
        repeat(19198) @(posedge CLOCK_50); #1;

        // Release start
        // The handshake spec says the user may deassert start after done.
        KEY[0] = 1'b1;

        // TEST 3: done should be high after plot finishes
        @(posedge CLOCK_50); #1;
        assert(LEDR[0] == 1'b1) else $error("TEST3 FAIL: LEDR[0] should be 1 when done");

        $finish(0);
    end

endmodule: tb_rtl_task2