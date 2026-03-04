`timescale 1ns/1ps
module tb_rtl_task3();

    // rtl testbench for task3 top level
    // goal is to make sure the top level sequencing is right
    // reset should force an automatic clear
    // then we wait for start
    // when start is pressed we clear again then draw the circle then done
    // done should hold until start is released
    // we only look at top level outputs like vga_x vga_y vga_colour vga_plot and led
    // this matches the lab idea where we validate inputs going into the vga core

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

    // 50mhz clock
    initial CLOCK_50 = 1'b0;
    always #10 CLOCK_50 = ~CLOCK_50;

    // Helpers 
    // step one cycle 
    task automatic step_cycle();
        @(posedge CLOCK_50);
        #1;
    endtask

    // reset helper
    task automatic apply_reset();
        begin
            KEY = 4'hF;
            SW = 10'd0;

            KEY[0] = 1'b1;

            // active low reset 
            KEY[3] = 1'b0;
            step_cycle();
            KEY[3] = 1'b1;
            step_cycle();
        end
    endtask

    // start button helpers
    task automatic press_start_button();
        begin
            // active low 
            KEY[0] = 1'b0;
        end
    endtask

    task automatic release_start_button();
        begin
            KEY[0] = 1'b1;
        end
    endtask

    // during clear we expect vga_plot to be 1 and vga_colour to be black clear ends when the design stops plotting which is vga_plot going low
    // we use a timeout so we do not hang if something is broken
    task automatic wait_until_clear_finishes(input int max_cycles);
        int cycles;
        begin
            cycles = 0;
            while(VGA_PLOT === 1'b1) begin
                step_cycle();
                cycles = cycles + 1;

                assert(VGA_COLOUR == 3'b000) else $error("clear expected black got %0d", VGA_COLOUR);

                if(cycles > max_cycles) begin
                    $error("clear timeout vga_plot did not go low within %0d cycles", max_cycles);
                    $finish(1);
                end
            end
        end
    endtask

    // done is exposed as led0 in your top level
    // we wait until it becomes 1 and we also cap the wait time
    task automatic wait_until_done_asserts(input int max_cycles);
        int cycles;
        begin
            cycles = 0;
            while(LEDR[0] !== 1'b1) begin
                step_cycle();
                cycles = cycles + 1;
                if(cycles > max_cycles) begin
                    $error("done timeout led0 did not assert within %0d cycles", max_cycles);
                    $finish(1);
                end
            end
        end
    endtask

    // during draw we want to see some green pixels being plotted we also want to enforce that any plotted pixel stays in bounds
    // this is a good sanity check that circle clipping is working
    task automatic watch_draw_activity(input int watch_cycles);
        int i;
        bit saw_green_plot;
        begin
            i = 0;
            saw_green_plot = 0;

            while(i < watch_cycles) begin
                step_cycle();
                if(VGA_PLOT) begin
                    assert(VGA_X <= 8'd159) else $error("draw plotted x out of bounds %0d", VGA_X);
                    assert(VGA_Y <= 7'd119) else $error("draw plotted y out of bounds %0d", VGA_Y);
                    if(VGA_COLOUR == 3'b010) saw_green_plot = 1;
                end
                i = i + 1;
            end
            assert(saw_green_plot) else $error("draw did not observe any green plotted pixels in watch window");
        end
    endtask

    initial begin
        // init inputs
        KEY = 4'hF;
        SW = 10'd0;
        release_start_button();

        // T1 reset should trigger automatic clear while clearing we should be plotting black pixels
        apply_reset();

        assert(VGA_PLOT == 1'b1) else $error("t1 expected vga_plot high during initial clear");
        assert(VGA_COLOUR == 3'b000) else $error("t1 expected black during initial clear");
        assert(LEDR[0] == 1'b0) else $error("t1 expected done led low during clear");

        // wait for clear to finish
        // clear is 160 by 120 so about 19200 cycles plus a little headroom
        wait_until_clear_finishes(19210);

        // after clear we are in wait
        step_cycle();
        assert(VGA_PLOT == 1'b0) else $error("t1 expected vga_plot low in wait");
        assert(LEDR[0] == 1'b0) else $error("t1 expected done led low in wait");

        // T2 press start should cause clear again then draw then done
        press_start_button();
        step_cycle();

        // right after start we should be clearing again
        // this is the pre draw clear required by the handout
        assert(VGA_PLOT == 1'b1) else $error("t2 expected vga_plot high during pre draw clear");
        assert(VGA_COLOUR == 3'b000) else $error("t2 expected black during pre draw clear");

        // wait for the second clear to finish
        wait_until_clear_finishes(19210);

        // after clear we should start seeing the circle draw activity
        // we watch a bit and make sure green appears at least once
        watch_draw_activity(2000);

        // now wait until done goes high
        wait_until_done_asserts(500000);

        // in done state we expect no more plotting
        step_cycle();
        assert(LEDR[0] == 1'b1) else $error("t2 expected done led high in done");
        assert(VGA_PLOT == 1'b0) else $error("t2 expected vga_plot low in done");

        // T3 releasing start should drop done and return to wait
        release_start_button();
        step_cycle();
        step_cycle();
        assert(LEDR[0] == 1'b0) else $error("t3 expected done led low after releasing start");
        assert(VGA_PLOT == 1'b0) else $error("t3 expected vga_plot low in wait");

        // T4 run again to make sure the top level can restart cleanly
        press_start_button();
        step_cycle();
        assert(VGA_PLOT == 1'b1) else $error("t4 expected vga_plot high during clear on second run");
        wait_until_clear_finishes(19210);
        watch_draw_activity(2000);
        wait_until_done_asserts(500000);
        release_start_button();
        step_cycle();
        step_cycle();
        assert(LEDR[0] == 1'b0) else $error("t4 expected done led low after releasing start second run");

        $display("tb_rtl_task3 all tests passed");
        $finish(0);
    end

endmodule: tb_rtl_task3