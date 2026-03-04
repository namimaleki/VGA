`timescale 1ns/1ps
module tb_syn_fillscreen();

    // do not peek internal signals no UUT.state / UUT.next_state.
    // We verify behavior only through the external I/O:
    // - During CLEAR we should see vga_plot=1 and vga_colour=000 sweeping the screen.
    // - Then vga_plot goes low (WAIT).
    // - When start=1, we should see vga_plot=1 again and stripes: vga_colour = vga_x[2:0].
    // - done should go high after the full screen is written, and stay high until start is dropped.

    logic clk,rst_n,start;
    logic [2:0] colour;
    logic done;
    logic [7:0] vga_x;
    logic [6:0] vga_y;
    logic [2:0] vga_colour;
    logic vga_plot;

    integer cycle_count;

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

    // 50MHz clock (period = 20ns)
    initial clk = 1'b0;
    always #10 clk = ~clk;

    // HLPERS
    // Small helper: wait one cycle and allow comb logic to settle
    task automatic step_cycle();
        @(posedge clk);
        #1;
    endtask

    // Check that any time we plot, coordinates are within bounds
    task automatic assert_in_bounds();
        begin
            if(vga_plot) begin
                assert(vga_x <= 8'd159) else $error("OOB x: %0d", vga_x);
                assert(vga_y <= 7'd119) else $error("OOB y: %0d", vga_y);
            end
        end
    endtask

    // Wait until vga_plot becomes 0, which means that we've left clear and have entered wait
    // We also enforce that during this phase we are writing black.
    task automatic wait_until_clear_finishes(input int max_cycles);
        int c;
        begin
            c = 0;
            while(vga_plot !== 1'b0) begin
                // tick to draw a pixel
                step_cycle();
                assert_in_bounds();

                // During clear we should be writing black pixels when plotting
                if(vga_plot) begin
                    assert(vga_colour == 3'b000) else $error("CLEAR colour not black: %0d at (%0d,%0d)", vga_colour, vga_x, vga_y);
                end

                // Check to make sure still withint our time budget 
                c = c + 1;
                if(c > max_cycles) begin
                    $error("CLEAR TIMEOUT: vga_plot never went low within %0d cycles", max_cycles);
                    $finish(1);
                end
            end
        end
    endtask

    // Run one full plot pass and ensure it finishes in budget and produces stripe colours.
    task automatic run_until_done_and_check_stripes(input int max_cycles);
        int c;

        // boolean which will indicate whether we went to plot or not 
        bit saw_plot;
        begin
            // init variables 
            c = 0;
            saw_plot = 0;
            
            while(done !== 1'b1) begin
                step_cycle();
                assert_in_bounds();

                // In plot mode, when vga_plot is high, colour should match x[2:0]
                if(vga_plot) begin
                    saw_plot = 1;
                    assert(vga_colour == vga_x[2:0]) else $error("Stripe colour mismatch: x=%0d expected %0d got %0d", vga_x, vga_x[2:0], vga_colour);
                end

                c = c + 1;
                if(c > max_cycles) begin
                    $error("PLOT TIMEOUT: done never asserted within %0d cycles", max_cycles);
                    $finish(1);
                end
            end

            assert(saw_plot) else $error("PLOT FAIL: never observed vga_plot asserted during plot pass");
        end
    endtask

    initial begin
        // Init inputs
        rst_n = 1'b1;
        start = 1'b0;
        colour = 3'b000;

        // T1 check reset behavior
        rst_n = 1'b0;
        step_cycle();

        assert(done == 1'b0) else $error("TEST1 FAIL: done should be 0 on reset");
        assert(vga_plot == 1'b1) else $error("TEST1 FAIL: vga_plot should be 1 during initial clear on reset");
        assert(vga_colour == 3'b000) else $error("TEST1 FAIL: vga_colour should be black during clear on reset");

        rst_n = 1'b1;
        step_cycle();

        // T2 check to see if clear completes and enters WAIT
        // Clear should complete in ~19200 cycles, allow small headroom.
        wait_until_clear_finishes(19215);

        // In WAIT, we should not be plotting and done should be low
        step_cycle();
        assert(vga_plot == 1'b0) else $error("TEST2 FAIL: expected vga_plot=0 in WAIT");
        assert(done == 1'b0) else $error("TEST2 FAIL: expected done=0 in WAIT");

        // T3 check if start triggers plot pass
        start = 1'b1;
        step_cycle();

        // We should start plotting soon
        cycle_count = 0;
        while(vga_plot !== 1'b1) begin
            step_cycle();
            cycle_count = cycle_count + 1;
            if(cycle_count > 35) begin
                $error("TEST3 FAIL: vga_plot did not assert soon after start");
                $finish(1);
            end
        end

        // Plot should finish in 19210 cycles budget 
        run_until_done_and_check_stripes(19210);

        // T4 done stays high while start remains high
        step_cycle();
        assert(done == 1'b1) else $error("TEST4 FAIL: done should remain high while start is high");

        // T5 drop start, done must drop and we should be ready to start again
        start = 1'b0;
        step_cycle();
        step_cycle();
        assert(done == 1'b0) else $error("TEST5 FAIL: done should drop after start deasserted");
        assert(vga_plot == 1'b0) else $error("TEST5 FAIL: expected vga_plot=0 after returning to WAIT");

        // T6: restart plot pass again
        start = 1'b1;
        step_cycle();
        run_until_done_and_check_stripes(19210);

        $display("tb_syn_fillscreen: ALL TESTS PASSED");
        $finish(0);
    end

endmodule: tb_syn_fillscreen