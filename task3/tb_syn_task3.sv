`timescale 1ns/1ps
module tb_syn_task3();

    // syn testbench for task3 top level
    // we only use top level i o since syn sims do not let us trust internal names
    // we check the expected board behavior
    // after reset it should clear the screen to black then stop
    // when start is pressed it should clear again then draw the green circle then done
    // done must hold until start is released
    // any time it plots then x and y must be inside the screen

    // top level signals
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

    // instantiate the top level dut
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

    // 50mhz clock like the board
    initial CLOCK_50 = 1'b0;
    always #10 CLOCK_50 = ~CLOCK_50;

    // helper to step one cycle and let signals settle
    task automatic step_cycle();
        @(posedge CLOCK_50);
        #1;
    endtask

    // reset helper
    // key3 is active low synchronous reset
    // we also keep start released during reset so we do not accidentally start a run
    task automatic apply_reset();
        begin
            KEY = 4'hF;
            SW = 10'd0;

            // key0 released
            KEY[0] = 1'b1;

            // assert then deassert reset
            KEY[3] = 1'b0;
            step_cycle();
            KEY[3] = 1'b1;
            step_cycle();
        end
    endtask

    // start button helpers
    // key0 pressed is 0 and released is 1
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

    // safety check
    // if the top level is plotting then it must be inside 160 by 120
    task automatic check_plot_is_safe();
        begin
            if(VGA_PLOT) begin
                assert(VGA_X <= 8'd159) else $error("oob plot x %0d", VGA_X);
                assert(VGA_Y <= 7'd119) else $error("oob plot y %0d", VGA_Y);
            end
        end
    endtask

    // wait until a clear phase finishes
    // clear phase is when vga_plot is high every cycle and colour is black
    // when clear finishes vga_plot goes low and we move to wait or draw
    task automatic wait_until_clear_finishes(input int max_cycles);
        int cycles;
        begin
            cycles = 0;
            while(VGA_PLOT === 1'b1) begin
                step_cycle();
                check_plot_is_safe();

                // during clear it should always be writing black
                assert(VGA_COLOUR == 3'b000) else $error("clear expected black got %0d", VGA_COLOUR);

                cycles = cycles + 1;
                if(cycles > max_cycles) begin
                    $error("clear timeout vga_plot stayed high longer than %0d cycles", max_cycles);
                    $finish(1);
                end
            end
        end
    endtask

    // watch draw activity
    // the circle colour is green 010 so we expect to see at least one green plotted pixel
    // this is a sanity check that draw actually happened
    task automatic watch_draw_activity(input int watch_cycles);
        int i;
        bit saw_green_pixel;
        begin
            i = 0;
            saw_green_pixel = 0;

            while(i < watch_cycles) begin
                step_cycle();
                check_plot_is_safe();

                if(VGA_PLOT && VGA_COLOUR == 3'b010) saw_green_pixel = 1;

                // if done happens early we stop watching
                if(LEDR[0] === 1'b1) break;

                i = i + 1;
            end

            assert(saw_green_pixel) else $error("draw did not observe any plotted green pixels");
        end
    endtask

    // wait for done using led0
    // keep checking bounds while waiting
    task automatic wait_until_done_asserts(input int max_cycles);
        int cycles;
        begin
            cycles = 0;
            while(LEDR[0] !== 1'b1) begin
                step_cycle();
                check_plot_is_safe();
                cycles = cycles + 1;
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

        // test 1 reset behavior
        // after reset it should immediately start clearing
        apply_reset();

        assert(VGA_PLOT == 1'b1) else $error("t1 expected vga_plot high during initial clear");
        assert(VGA_COLOUR == 3'b000) else $error("t1 expected black during initial clear");
        assert(LEDR[0] == 1'b0) else $error("t1 expected done led low during initial clear");

        // clear should take about 19200 cycles so allow some tolerance
        wait_until_clear_finishes(19210);

        // after clear we should be idle
        step_cycle();
        check_plot_is_safe();
        assert(VGA_PLOT == 1'b0) else $error("t1 expected vga_plot low in wait after clear");
        assert(LEDR[0] == 1'b0) else $error("t1 expected done led low in wait");

        // test 2 press start
        // we should clear again then draw then done
        press_start_button();
        step_cycle();

        assert(VGA_PLOT == 1'b1) else $error("t2 expected vga_plot high during pre draw clear");
        assert(VGA_COLOUR == 3'b000) else $error("t2 expected black during pre draw clear");

        wait_until_clear_finishes(19210);

        // after second clear we expect draw activity
        watch_draw_activity(4000);

        // then we wait for done
        wait_until_done_asserts(900000);

        // in done we expect no more plotting
        step_cycle();
        check_plot_is_safe();
        assert(LEDR[0] == 1'b1) else $error("t2 expected done led high in done");
        assert(VGA_PLOT == 1'b0) else $error("t2 expected vga_plot low in done");

        // test 3 release start
        // done should drop and we should be ready again
        release_start_button();
        step_cycle();
        step_cycle();
        assert(LEDR[0] == 1'b0) else $error("t3 expected done led low after start released");
        assert(VGA_PLOT == 1'b0) else $error("t3 expected vga_plot low in wait");

        // test 4 run again to confirm restart works
        press_start_button();
        step_cycle();
        wait_until_clear_finishes(19210);
        watch_draw_activity(4000);
        wait_until_done_asserts(900000);
        release_start_button();
        step_cycle();
        step_cycle();
        assert(LEDR[0] == 1'b0) else $error("t4 expected done led low after second run");

        $display("tb_syn_task3 all tests passed");
        $finish(0);
    end

endmodule: tb_syn_task3