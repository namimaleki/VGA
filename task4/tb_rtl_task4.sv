`timescale 1ns/1ps
module tb_rtl_task4();

    // rtl testbench for task4 top level
    // we only use the top level i o like the lab wants
    // we check the sequencing is correct
    // reset should trigger an automatic clear
    // then we wait for start
    // when start is pressed we clear again then draw then done
    // done must hold until start is released
    // also any plotted pixel must be inside the 160 by 120 screen

    // signals that match the top level ports
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

    // instantiate the top level under test
    task4 UUT(
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

    // 50mhz clock
    initial CLOCK_50 = 1'b0;
    always #10 CLOCK_50 = ~CLOCK_50;

    // helper to step one clock and let signals settle
    task automatic step_cycle();
        @(posedge CLOCK_50);
        #1;
    endtask

    // reset helper
    // key3 is active low synchronous reset
    // we also make sure start is released during reset so behavior is clean
    task automatic apply_reset();
        begin
            KEY = 4'hF;
            SW = 10'd0;
            KEY[0] = 1'b1;

            KEY[3] = 1'b0;
            step_cycle();
            KEY[3] = 1'b1;
            step_cycle();
        end
    endtask

    // start button helpers
    // key0 is active low so pressed is 0 and released is 1
    task automatic press_start_button();
        begin
            KEY[0] = 1'b0;
        end
    endtask

    task automatic release_start_button();
        begin
            KEY[0] = 1'b1;
        end
    endtask

    // wait for a clear phase to finish
    // clearing means the top level is writing black pixels every cycle
    // we detect end of clear when vga_plot goes low
    // we also enforce that during clear the colour is always black
    task automatic wait_until_clear_finishes(input int max_cycles);
        int cycles;
        begin
            cycles = 0;
            while(VGA_PLOT === 1'b1) begin
                step_cycle();
                cycles = cycles + 1;

                // clear is supposed to overwrite the framebuffer with black
                // if we see a different colour here it means the mux or state is wrong
                assert(VGA_COLOUR == 3'b000) else $error("clear expected black got %0d", VGA_COLOUR);

                // clear should take about 19200 cycles so this timeout protects us from infinite loops
                if(cycles > max_cycles) begin
                    $error("clear timeout vga_plot stayed high longer than %0d cycles", max_cycles);
                    $finish(1);
                end
            end
        end
    endtask

    // watch draw behavior for a bit
    // during draw the triangle colour is green so we want to see at least one green pixel plotted
    // we also enforce that any time vga_plot is high the pixel is inside the screen
    task automatic watch_draw_activity(input int watch_cycles);
        int i;
        bit saw_green;
        begin
            i = 0;
            saw_green = 0;

            while(i < watch_cycles) begin
                step_cycle();

                // if we are plotting then x and y must be valid
                if(VGA_PLOT) begin
                    assert(VGA_X <= 8'd159) else $error("draw plotted x out of bounds %0d", VGA_X);
                    assert(VGA_Y <= 7'd119) else $error("draw plotted y out of bounds %0d", VGA_Y);

                    // triangle is configured as green so we expect to see this at least once
                    if(VGA_COLOUR == 3'b010) saw_green = 1;
                end

                // if done happens early we can stop watching
                if(LEDR[0] === 1'b1) break;

                i = i + 1;
            end

            assert(saw_green) else $error("draw did not observe any plotted green pixels");
        end
    endtask

    // wait until done led goes high
    // also keep doing bounds checks while we wait
    task automatic wait_until_done_asserts(input int max_cycles);
        int cycles;
        begin
            cycles = 0;
            while(LEDR[0] !== 1'b1) begin
                step_cycle();
                cycles = cycles + 1;

                // even while waiting for done we enforce the no out of bounds plotting rule
                if(VGA_PLOT) begin
                    assert(VGA_X <= 8'd159) else $error("run plotted x out of bounds %0d", VGA_X);
                    assert(VGA_Y <= 7'd119) else $error("run plotted y out of bounds %0d", VGA_Y);
                end
                
                if(cycles > max_cycles) begin
                    $error("done timeout led0 not asserted within %0d cycles", max_cycles);
                    $finish(1);
                end
            end
        end
    endtask

    initial begin
        // init inputs
        KEY = 4'hF;
        SW = 10'd0;
        release_start_button();

        // test 1 reset should trigger the automatic clear
        // during this clear vga_plot should be high and colour should be black
        apply_reset();

        assert(VGA_PLOT == 1'b1) else $error("t1 expected vga_plot high during initial clear");
        assert(VGA_COLOUR == 3'b000) else $error("t1 expected black during initial clear");
        assert(LEDR[0] == 1'b0) else $error("t1 expected done led low during initial clear");

        // wait for the clear to finish and enter wait state
        wait_until_clear_finishes(19210);

        step_cycle();
        assert(VGA_PLOT == 1'b0) else $error("t1 expected vga_plot low after clear");
        assert(LEDR[0] == 1'b0) else $error("t1 expected done led low in wait");

        // test 2 press start then we should clear again then draw then done
        press_start_button();
        step_cycle();

        // right after start we should be in the pre draw clear
        assert(VGA_PLOT == 1'b1) else $error("t2 expected vga_plot high during pre draw clear");
        assert(VGA_COLOUR == 3'b000) else $error("t2 expected black during pre draw clear");

        // wait for second clear to finish
        wait_until_clear_finishes(19210);

        // now we should be drawing and we should see green plotted pixels at some point
        watch_draw_activity(8000);

        // wait for done to be asserted
        wait_until_done_asserts(900000);

        // in done we should stop plotting new pixels
        step_cycle();
        assert(LEDR[0] == 1'b1) else $error("t2 expected done led high");
        assert(VGA_PLOT == 1'b0) else $error("t2 expected vga_plot low in done");

        // test 3 release start then done should drop and we should be back in wait
        release_start_button();
        step_cycle();
        step_cycle();

        assert(LEDR[0] == 1'b0) else $error("t3 expected done led low after releasing start");
        assert(VGA_PLOT == 1'b0) else $error("t3 expected vga_plot low in wait");

        // test 4 run again to make sure it can restart cleanly
        press_start_button();
        step_cycle();
        wait_until_clear_finishes(19210);
        watch_draw_activity(8000);
        wait_until_done_asserts(900000);
        release_start_button();
        step_cycle();
        step_cycle();
        assert(LEDR[0] == 1'b0) else $error("t4 expected done led low after second run");

        $display("tb_rtl_task4 all tests passed");
        $finish(0);
    end

endmodule: tb_rtl_task4