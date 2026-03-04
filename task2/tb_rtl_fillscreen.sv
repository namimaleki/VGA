`timescale 1ns/1ps
module tb_rtl_fillscreen();

    // Main things we are going to check:
    // 1) Reset puts us into CLEAR and starts clearing to black
    // 2) CLEAR runs for ~19200 cycles then goes to WAIT
    // 3) start makes it go to PLOT and generate vertical stripes (colour = x mod 8).
    // 4) After finishing the last pixel, it reaches DONE and holds done high until start is released.
    // 5) After releasing start, it returns to WAIT and can start again

    // UUT signals
    logic clk,rst_n,start;
    logic [2:0] colour;
    logic done;
    logic [7:0] vga_x;
    logic [6:0] vga_y;
    logic [2:0] vga_colour;
    logic vga_plot;

    // State signals note that these are internal to the DUT and this is fine for RTL tb
    logic [1:0] state,next_state;

    // Helper counter for timing checks
    integer cycle_count;

    // Instantiate DUT
    fillscreen UUT(
        .clk(clk),
        .rst_n(rst_n),
        .colour(colour),
        .start(start),
        .done(done),
        .vga_x(vga_x),
        .vga_y(vga_y),
        .vga_colour(vga_colour),
        .vga_plot(vga_plot)
    );

    // Peek internal states for rtl debug
    assign state = UUT.state;
    assign next_state = UUT.next_state;

    // 50MHz clock (period = 20ns)
    initial clk = 1'b0;
    always #10 clk = ~clk;

    initial begin
        // Initialize inputs to known values
        rst_n = 1'b1;
        start = 1'b0;
        colour = 3'b000;

        // TEST 1: reset
        // Reset is active-low and synchronous, so we assert rst_n=0 and wait for a posedge.
        rst_n = 1'b0;
        @(posedge clk); #1;

        assert(done == 1'b0) else $error("TEST1 FAIL: done should be 0 on reset, got %0d", done);
        assert(vga_plot == 1'b1) else $error("TEST1 FAIL: vga_plot should be 1 in CLEAR, got %0d", vga_plot);
        assert(vga_colour == 3'b000) else $error("TEST1 FAIL: colour should be black in CLEAR, got %0d", vga_colour);
        assert(state == 2'd0) else $error("TEST1 FAIL: state should be CLEAR, got %0d", state);
        assert(next_state == 2'd0) else $error("TEST1 FAIL: next_state should be CLEAR, got %0d", next_state);

        // Release reset and allow the CLEAR state machine to run
        rst_n = 1'b1;

        // TEST 2: clear -> wait
        // During CLEAR, we expect it to keep plotting black pixels while scanning the whole 160x120 screen.
        @(posedge clk); #1;

        assert(state == 2'd0) else $error("TEST2 FAIL: should be in CLEAR after reset, got %0d", state);
        assert(vga_plot == 1'b1) else $error("TEST2 FAIL: vga_plot should be 1 during CLEAR, got %0d", vga_plot);
        assert(vga_colour == 3'b000) else $error("TEST2 FAIL: colour should be black during CLEAR, got %0d", vga_colour);
        assert(next_state == 2'd0) else $error("TEST2 FAIL: next_state should be CLEAR, got %0d", next_state);

        // Count cycles until we enter WAIT (state 1)
        // Clear should complete in about 19200 cycles (160*120).
        cycle_count = 0;
        while(state !== 2'd1) begin
            @(posedge clk); #1;
            cycle_count = cycle_count + 1;
            if(cycle_count > 19210) begin
                $error("TEST2 FAIL: exceeded 19210 cycles, at cycle count: %0d", cycle_count);
                break;
            end
        end

        assert(cycle_count <= 19200) else $error("TEST2 FAIL: took %0d cycles, max is 19200", cycle_count);
        $display("TEST 2 [CLEAR AFTER RST_N]: completed in %0d cycles", cycle_count);

        assert(state == 2'd1) else $error("TEST2 FAIL: should be in WAIT after clear, got %0d", state);
        assert(next_state == 2'd1) else $error("TEST2 FAIL: next_state should be WAIT, got %0d", next_state);
        assert(vga_plot == 1'b0) else $error("TEST2 FAIL: vga_plot should be 0 in WAIT, got %0d", vga_plot);

        // TEST 3: wait -> plot
        // In WAIT, asserting start should move us into PLOT.
        start = 1'b1;
        @(posedge clk); #1;

        assert(state == 2'd2) else $error("TEST3 FAIL: should be in PLOT after start, got %0d", state);
        assert(next_state == 2'd2) else $error("TEST3 FAIL: next_state should be PLOT, got %0d", next_state);
        assert(vga_plot == 1'b1) else $error("TEST3 FAIL: vga_plot should be 1 in PLOT, got %0d", vga_plot);
        assert(vga_x == 8'd0) else $error("TEST3 FAIL: vga_x should start at 0, got %0d", vga_x);
        assert(vga_y == 7'd0) else $error("TEST3 FAIL: vga_y should start at 0, got %0d", vga_y);

        // TEST 4: correct colour pattern
        // In PLOT, stripes are colour = x mod 8, which is just x_count[2:0].
        assert(vga_colour == 3'd0) else $error("TEST4 FAIL: x=0 colour should be 0, got %0d", vga_colour);

        // Each x column has 120 pixels, so after 8 columns we need 8*120 = 960 cycles.
        repeat(960) @(posedge clk); #1;

        assert(vga_x == 8'd8) else $error("TEST4 FAIL: x should be 8, got %0d", vga_x);
        assert(vga_colour == 3'd0) else $error("TEST4 FAIL: x=8 colour should wrap to 0, got %0d", vga_colour);
        assert(state == 2'd2) else $error("TEST4 FAIL: should still be in PLOT, got %0d", state);
        assert(next_state == 2'd2) else $error("TEST4 FAIL: next_state should still be PLOT, got %0d", next_state);

        // TEST 5: counter behavior inside a column
        // After 119 more cycles (we are already partway through), y should reach 119 then wrap to 0 and x increments.
        repeat(119) @(posedge clk); #1;

        assert(vga_y == 7'd119) else $error("TEST5 FAIL: y should be 119 at end of column, got %0d", vga_y);
        assert(vga_x == 8'd8) else $error("TEST5 FAIL: x should still be 8, got %0d", vga_x);
        assert(state == 2'd2) else $error("TEST5 FAIL: should still be in PLOT, got %0d", state);
        assert(next_state == 2'd2) else $error("TEST5 FAIL: next_state should be PLOT, got %0d", next_state);

        @(posedge clk); #1;

        assert(vga_y == 7'd0) else $error("TEST5 FAIL: y should wrap to 0, got %0d", vga_y);
        assert(vga_x == 8'd9) else $error("TEST5 FAIL: x should increment to 9, got %0d", vga_x);

        // TEST 6: plot -> done
        // Run until we reach the last pixel (159,119). This test assumes 1 pixel per cycle.
        repeat(18119) @(posedge clk); #1;

        assert(vga_x == 8'd159) else $error("TEST6 FAIL: x should be 159, got %0d", vga_x);
        assert(vga_y == 7'd119) else $error("TEST6 FAIL: y should be 119, got %0d", vga_y);
        assert(state == 2'd2) else $error("TEST6 FAIL: should still be in PLOT, got %0d", state);
        assert(next_state == 2'd3) else $error("TEST6 FAIL: next_state should be DONE, got %0d", next_state);

        // TEST 7: done -> wait after start released
        // done should not stay stuck forever; dropping start should return us to WAIT.
        start = 1'b0;
        @(posedge clk); #1;

        assert(next_state == 2'd1) else $error("TEST7 FAIL: next_state should be WAIT after ~start, got %0d", next_state);

        @(posedge clk); #1;

        assert(state == 2'd1) else $error("TEST7 FAIL: should be in WAIT, got %0d", state);
        assert(next_state == 2'd1) else $error("TEST7 FAIL: next_state should stay WAIT, got %0d", next_state);
        assert(done == 1'b0) else $error("TEST7 FAIL: done should be 0, got %0d", done);
        assert(vga_plot == 1'b0) else $error("TEST7 FAIL: vga_plot should be 0, got %0d", vga_plot);

        // TEST 8: WAIT -> PLOT again (restart behavior)
        // This checks the module can run multiple times without re-reset.
        cycle_count = 0;
        start = 1'b1;
        @(posedge clk); #1;

        assert(state == 2'd2) else $error("TEST8 FAIL: should be in PLOT, got %0d", state);

        while(done !== 1'b1) begin
            @(posedge clk); #1;
            cycle_count = cycle_count + 1;
            if(cycle_count > 19210) begin
                $error("TEST8 FAIL: exceeded 19210 cycle, at cycle count: %0d", cycle_count);
                break;
            end
        end

        assert(cycle_count <= 19210) else $error("TEST8 FAIL: took %0d cycles, max is 19210 cycles.", cycle_count);
        $display("TEST 8 [PLOT AFTER WAIT]: completed in %0d cycles", cycle_count);

        assert(state == 2'd3) else $error("TEST8 FAIL: should be in DONE, got %0d", state);
        assert(done == 1'b1) else $error("TEST8 FAIL: done should be 1, got %0d", done);

        // TEST 9: DONE -> PLOT (start held high scenario)
        // If start stays high, some implementations restart immediately. We verify this behavior is consistent.
        cycle_count = 0;
        start = 1'b1;
        @(posedge clk); #1;

        assert(state == 2'd2) else $error("TEST9 FAIL: should be in PLOT after start, got %0d", state);
        assert(next_state == 2'd2) else $error("TEST9 FAIL: next_state should be PLOT, got %0d", next_state);

        while(done !== 1'b1) begin
            @(posedge clk); #1;
            cycle_count = cycle_count + 1;
            if(cycle_count > 19210) begin
                $error("TEST9 FAIL: exceeded 19210 cycle, at cycle count: %0d", cycle_count);
                break;
            end
        end

        assert(cycle_count <= 19210) else $error("TEST9 FAIL: took %0d cycles, max is 19210 cycles.", cycle_count);
        $display("TEST 9 [PLOT AFTER DONE]: completed in %0d cycles", cycle_count);
        assert(done == 1'b1) else $error("TEST9 FAIL: done should be 1, got %0d", done);

        $finish(0);
    end

endmodule: tb_rtl_fillscreen