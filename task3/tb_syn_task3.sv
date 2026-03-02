`timescale 1ns/1ps
module tb_syn_task3();

    // Post-synthesis testbench for task3 top-level
    // We verify using only the public I/O ports:
    // - After reset: the design clears the screen (VGA_PLOT=1, VGA_COLOUR=black) then stops plotting (WAIT)
    // - On start button press (KEY[0] active-low): clears again, then draws circle (green pixels plotted), then DONE (LEDR[0]=1)
    // - DONE stays high until start is released, then returns to WAIT
    logic CLOCK_50;
    logic [3:0] KEY;
    logic [9:0] SW;
    logic [9:0] LEDR;
    logic [6:0] HEX0,HEX1,HEX2,HEX3,HEX4,HEX5;
    logic [7:0] VGA_R,VGA_G,VGA_B;
    logic VGA_HS,VGA_VS,VGA_CLK;
    logic [7:0] VGA_X;
    logic [6:0] VGA_Y;
    logic [2:0] VGA_COLOUR;
    logic VGA_PLOT;

    task3 UUT(
        .CLOCK_50(CLOCK_50),
        .KEY(KEY),
        .SW(SW),
        .LEDR(LEDR),
        .HEX0(HEX0),.HEX1(HEX1),.HEX2(HEX2),.HEX3(HEX3),.HEX4(HEX4),.HEX5(HEX5),
        .VGA_R(VGA_R),.VGA_G(VGA_G),.VGA_B(VGA_B),
        .VGA_HS(VGA_HS),.VGA_VS(VGA_VS),.VGA_CLK(VGA_CLK),
        .VGA_X(VGA_X),.VGA_Y(VGA_Y),
        .VGA_COLOUR(VGA_COLOUR),.VGA_PLOT(VGA_PLOT)
    );

    // 50MHz clock
    initial CLOCK_50=1'b0;
    always #10 CLOCK_50=~CLOCK_50;

    task automatic tick();
        @(posedge CLOCK_50);
        #1;
    endtask

    task automatic do_reset();
        begin
            KEY=4'hF;
            SW=10'd0;
            KEY[0]=1'b1; // start released
            KEY[3]=1'b0; // assert reset (active-low)
            tick();
            KEY[3]=1'b1; // deassert reset
            tick();
        end
    endtask

    task automatic press_start();
        begin
            KEY[0]=1'b0;
        end
    endtask

    task automatic release_start();
        begin
            KEY[0]=1'b1;
        end
    endtask

    // Wait for a clear phase to end by detecting VGA_PLOT going low.
    // While clearing: VGA_PLOT=1 and VGA_COLOUR must be black.
    task automatic wait_for_clear_end(input int max_cycles);
        int c;
        begin
            c=0;
            while (VGA_PLOT===1'b1) begin
                tick();
                c=c+1;

                assert(VGA_COLOUR==3'b000) else $error("CLEAR: expected black, got %0d", VGA_COLOUR);

                if (c>max_cycles) begin
                    $error("CLEAR TIMEOUT: VGA_PLOT stayed high > %0d cycles", max_cycles);
                    $finish(1);
                end
            end
        end
    endtask

    // Observe the draw phase for some cycles:
    // - any plotted pixel must be in bounds
    // - we should see at least one plotted green pixel
    task automatic observe_draw(input int cycles_to_watch);
        int i;
        bit saw_green;
        begin
            i=0;
            saw_green=0;

            while (i<cycles_to_watch) begin
                tick();

                if (VGA_PLOT) begin
                    assert(VGA_X<=8'd159) else $error("DRAW: plotted x out of bounds: %0d", VGA_X);
                    assert(VGA_Y<=7'd119) else $error("DRAW: plotted y out of bounds: %0d", VGA_Y);
                    if (VGA_COLOUR==3'b010) saw_green=1;
                end

                if (LEDR[0]===1'b1) break; // if it finishes early, stop watching
                i=i+1;
            end

            assert(saw_green) else $error("DRAW: did not observe any plotted green pixels");
        end
    endtask

    task automatic wait_for_done(input int max_cycles);
        int c;
        begin
            c=0;
            while (LEDR[0]!==1'b1) begin
                tick();
                c=c+1;

                // Safety: any plotted pixel must be in bounds
                if (VGA_PLOT) begin
                    assert(VGA_X<=8'd159) else $error("RUN: plotted x out of bounds: %0d", VGA_X);
                    assert(VGA_Y<=7'd119) else $error("RUN: plotted y out of bounds: %0d", VGA_Y);
                end

                if (c>max_cycles) begin
                    $error("DONE TIMEOUT: LEDR[0] not asserted within %0d cycles", max_cycles);
                    $finish(1);
                end
            end
        end
    endtask

    initial begin
        // TEST 1: reset triggers automatic clear then WAIT
        do_reset();

        // Should begin clearing immediately after reset
        assert(VGA_PLOT==1'b1) else $error("TEST1: expected VGA_PLOT=1 during initial clear");
        assert(VGA_COLOUR==3'b000) else $error("TEST1: expected black during initial clear");
        assert(LEDR[0]==1'b0) else $error("TEST1: done LED should be low during initial clear");

        // Initial clear should finish in ~19200 cycles (+ tolerance)
        wait_for_clear_end(19210);

        // Now should be WAIT (not plotting, not done)
        tick();
        assert(VGA_PLOT==1'b0) else $error("TEST1: expected VGA_PLOT=0 after clear");
        assert(LEDR[0]==1'b0) else $error("TEST1: expected done LED low in WAIT");

        // TEST 2: press start -> clear again -> draw -> done
        press_start();
        tick();

        // Should go into clear before draw
        assert(VGA_PLOT==1'b1) else $error("TEST2: expected VGA_PLOT=1 during pre-draw clear");
        assert(VGA_COLOUR==3'b000) else $error("TEST2: expected black during pre-draw clear");

        wait_for_clear_end(19210);

        // After clear ends, should be drawing; observe some green plotted pixels
        observe_draw(4000);

        // Wait for done to assert (overall must be < 1,000,000 ticks)
        wait_for_done(900000);

        // In DONE, it should not be plotting new pixels
        tick();
        assert(LEDR[0]==1'b1) else $error("TEST2: expected done LED high");
        assert(VGA_PLOT==1'b0) else $error("TEST2: expected VGA_PLOT=0 in DONE");

        // TEST 3: release start -> return to WAIT and done LED drops
        release_start();
        tick();
        tick();
        assert(LEDR[0]==1'b0) else $error("TEST3: expected done LED low after start released");
        assert(VGA_PLOT==1'b0) else $error("TEST3: expected VGA_PLOT=0 in WAIT");

        // TEST 4: run again to ensure restart works
        press_start();
        tick();
        wait_for_clear_end(19210);
        observe_draw(4000);
        wait_for_done(900000);
        release_start();
        tick();
        tick();
        assert(LEDR[0]==1'b0) else $error("TEST4: expected done LED low after second run");

        $display("tb_syn_task3: ALL TESTS PASSED");
        $finish(0);
    end

endmodule: tb_syn_task3