`timescale 1ns/1ps
module tb_rtl_task3();

    // Testbench for task3 top-level
    // Checks sequencing: reset->CLEAR0->WAIT, then start->CLEAR1->DRAW->DONE, and handshake on start release.
    // We verify behavior through the exposed VGA input ports (VGA_X/Y/COLOUR/PLOT) and LEDR[0].
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

    // 50MHz clock (period 20ns)
    initial CLOCK_50=1'b0;
    always #10 CLOCK_50=~CLOCK_50;

    // Helpers
    task automatic tick();
        @(posedge CLOCK_50);
        #1;
    endtask

    task automatic do_reset();
        begin
            KEY=4'hF;
            SW=10'd0;

            // active-low reset on KEY[3]
            KEY[3]=1'b0;
            tick();
            KEY[3]=1'b1;
            tick();
        end
    endtask

    task automatic press_start();
        begin
            // KEY[0] active-low start
            KEY[0]=1'b0;
        end
    endtask

    task automatic release_start();
        begin
            KEY[0]=1'b1;
        end
    endtask

    // Wait for the CLEAR phase to finish by watching VGA_PLOT stop being 1.
    // During clear, VGA_PLOT should be 1 and VGA_COLOUR should be black.
    task automatic wait_for_clear_done(input int max_cycles);
        int c;
        begin
            c=0;
            while (VGA_PLOT===1'b1) begin
                tick();
                c=c+1;

                // During clear, only black should be written
                assert(VGA_COLOUR==3'b000) else $error("CLEAR: expected black, got %0d", VGA_COLOUR);

                // Clear should finish in about 19200 cycles (+ small tolerance)
                if (c>max_cycles) begin
                    $error("CLEAR TIMEOUT: VGA_PLOT did not go low within %0d cycles", max_cycles);
                    $finish(1);
                end
            end
        end
    endtask

    // Wait for DONE: LEDR[0] asserted
    task automatic wait_for_done(input int max_cycles);
        int c;
        begin
            c=0;
            while (LEDR[0]!==1'b1) begin
                tick();
                c=c+1;
                if (c>max_cycles) begin
                    $error("DONE TIMEOUT: LEDR[0] not asserted within %0d cycles", max_cycles);
                    $finish(1);
                end
            end
        end
    endtask

    // Confirm that during drawing we are outputting the circle colour sometimes (green) and that plotted pixels are always within bounds.
    task automatic observe_draw_phase(input int cycles_to_watch);
        int i;
        bit saw_green_plot;
        begin
            i=0;
            saw_green_plot=0;

            while (i<cycles_to_watch) begin
                tick();

                // If a pixel is plotted, it must be within screen bounds
                if (VGA_PLOT) begin
                    assert(VGA_X<=8'd159) else $error("DRAW: plotted x out of bounds: %0d", VGA_X);
                    assert(VGA_Y<=7'd119) else $error("DRAW: plotted y out of bounds: %0d", VGA_Y);
                end

                // Circle is configured as pure green (010)
                if (VGA_PLOT&&VGA_COLOUR==3'b010) saw_green_plot=1;

                i=i+1;
            end

            assert(saw_green_plot) else $error("DRAW: did not observe any green plotted pixels in watch window");
        end
    endtask

    initial begin
        // Initialize inputs
        KEY=4'hF;
        SW=10'd0;
        release_start();

        // TEST 1: Reset triggers automatic clear, then goes to WAIT (plot stops)
        do_reset();

        // Right after reset, we should be clearing (plotting black)
        assert(VGA_PLOT==1'b1) else $error("TEST1: expected VGA_PLOT=1 during initial clear");
        assert(VGA_COLOUR==3'b000) else $error("TEST1: expected black during initial clear");
        assert(LEDR[0]==1'b0) else $error("TEST1: done LED should be 0 during clear");

        // Wait for clear to finish (plot goes low)
        wait_for_clear_done(19210);

        // Now we should be in WAIT: not plotting and not done
        tick();
        assert(VGA_PLOT==1'b0) else $error("TEST1: expected VGA_PLOT=0 in WAIT");
        assert(LEDR[0]==1'b0) else $error("TEST1: expected done LED low in WAIT");

        // TEST 2: Press start -> clear again (VGA_PLOT becomes 1 black), then draw circle, then done
        press_start();
        tick();

        // After start, we should enter CLEAR1 and plot black
        assert(VGA_PLOT==1'b1) else $error("TEST2: expected VGA_PLOT=1 during pre-draw clear");
        assert(VGA_COLOUR==3'b000) else $error("TEST2: expected black during pre-draw clear");

        // Wait for second clear to finish
        wait_for_clear_done(19210);

        // After clear finishes, it should start drawing circle (observe for some cycles)
        observe_draw_phase(2000);

        // Wait until DONE asserted (LEDR[0]=1)
        wait_for_done(500000);

        // While in DONE, VGA should not be plotting new pixels
        tick();
        assert(LEDR[0]==1'b1) else $error("TEST2: expected done LED high in DONE");
        assert(VGA_PLOT==1'b0) else $error("TEST2: expected VGA_PLOT=0 in DONE");

        // TEST 3: Release start -> returns to WAIT and done LED drops
        release_start();
        tick();
        tick();
        assert(LEDR[0]==1'b0) else $error("TEST3: expected done LED low after releasing start");
        assert(VGA_PLOT==1'b0) else $error("TEST3: expected VGA_PLOT=0 in WAIT");

        // TEST 4: Run again (press start again)
        press_start();
        tick();
        assert(VGA_PLOT==1'b1) else $error("TEST4: expected VGA_PLOT=1 during clear on second run");
        wait_for_clear_done(19210);
        observe_draw_phase(2000);
        wait_for_done(500000);
        release_start();
        tick();
        tick();
        assert(LEDR[0]==1'b0) else $error("TEST4: expected done LED low after releasing start (second run)");

        $display("tb_rtl_task3: ALL TESTS PASSED");
        $finish(0);
    end

endmodule: tb_rtl_task3