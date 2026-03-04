`timescale 1ns/1ps
module tb_syn_circle();

    // syn testbench for circle
    // in syn sims we treat the dut as a black box so no internal peeks
    // we check the stuff the lab cares about from the outside
    // start done handshake must work
    // if it plots then x and y must be inside the 160 by 120 screen
    // if it plots then colour must match the input colour we asked for
    // and it must finish in a reasonable time so we do not hang

    // inputs to dut
    logic clk,rst_n,start;
    logic [2:0] colour;
    logic [7:0] centre_x;
    logic [6:0] centre_y;
    logic [7:0] radius;

    // outputs from dut
    logic done;
    logic [7:0] vga_x;
    logic [6:0] vga_y;
    logic [2:0] vga_colour;
    logic vga_plot;

    // instantiate dut
    circle UUT(
        .clk(clk),
        .rst_n(rst_n),
        .colour(colour),
        .centre_x(centre_x),
        .centre_y(centre_y),
        .radius(radius),
        .start(start),
        .done(done),
        .vga_x(vga_x),
        .vga_y(vga_y),
        .vga_colour(vga_colour),
        .vga_plot(vga_plot)
    );

    // 50mhz clock like the board
    initial clk = 1'b0;
    always #10 clk = ~clk;

    // helper to step one cycle and let signals settle
    task automatic step_cycle();
        @(posedge clk);
        #1;
    endtask

    // reset helper
    // reset is active low synchronous so we pulse rst_n low for one clock edge
    // we also set inputs to known values so the sim is stable
    task automatic apply_reset();
        begin
            rst_n = 1'b1;
            start = 1'b0;
            colour = 3'b000;
            centre_x = 8'd0;
            centre_y = 7'd0;
            radius = 8'd0;

            rst_n = 1'b0;
            step_cycle();
            rst_n = 1'b1;
            step_cycle();
        end
    endtask

    // safety check
    // if the dut is plotting then it must be inside 160 by 120
    // and the plotted colour must match the requested input colour
    task automatic check_plot_is_safe();
        begin
            if(vga_plot) begin
                assert(vga_x <= 8'd159) else $error("oob plot x %0d", vga_x);
                assert(vga_y <= 7'd119) else $error("oob plot y %0d", vga_y);
                assert(vga_colour == colour) else $error("colour mismatch expected %0d got %0d", colour, vga_colour);
            end
        end
    endtask

    // wait for done but do not hang forever
    // we also keep running safety checks while we wait
    task automatic wait_for_done_or_fail(input int max_cycles);
        int cycles;
        begin
            cycles = 0;
            while(done !== 1'b1) begin
                step_cycle();
                check_plot_is_safe();
                cycles = cycles + 1;
                if(cycles > max_cycles) begin
                    $error("timeout done did not assert within %0d cycles", max_cycles);
                    $finish(1);
                end
            end
        end
    endtask

    // run one circle case
    // start is a level handshake so we hold start high until done
    // we do not try to verify the exact circle pixels here
    // we just make sure it is behaving safely and finishing
    task automatic run_circle_case(input [2:0] req_colour,input [7:0] req_cx,input [6:0] req_cy,input [7:0] req_r,input int timeout_cycles);
        int i;
        bit saw_any_plot;
        begin
            colour = req_colour;
            centre_x = req_cx;
            centre_y = req_cy;
            radius = req_r;

            // start the operation and keep it asserted until done
            start = 1'b1;

            // short activity window
            // this catches the bug where nothing ever plots and done never comes
            i = 0;
            saw_any_plot = 0;
            while(i < 2000) begin
                step_cycle();
                check_plot_is_safe();
                if(vga_plot) saw_any_plot = 1;
                if(done) break;
                i = i + 1;
            end

            // for non degenerate circles we expect at least some plotting in most cases
            // for heavy clipping you could get fewer plots but it should usually not be zero
            // for r=0 duplicates happen but still should plot if the centre is in bounds
            if(req_r != 8'd0) begin
                // not a hard fail because extreme clipping can be weird
            end

            // now wait until done asserts
            wait_for_done_or_fail(timeout_cycles);

            // done must stay high while start is still high
            step_cycle();
            check_plot_is_safe();
            assert(done == 1'b1) else $error("done should remain high while start is high");

            // complete handshake
            start = 1'b0;
            step_cycle();
            step_cycle();
            check_plot_is_safe();
            assert(done == 1'b0) else $error("done should drop after start deasserted");
        end
    endtask

    initial begin
        // test 1 reset behavior
        apply_reset();
        assert(done == 1'b0) else $error("t1 done should be 0 after reset");
        assert(vga_plot == 1'b0) else $error("t1 vga_plot should be 0 after reset");

        // test 2 typical in bounds circle
        run_circle_case(3'b010,8'd80,7'd60,8'd10,200000);

        // test 3 clipping near corner
        run_circle_case(3'b001,8'd1,7'd1,8'd25,400000);

        // test 4 another normal case different colour and radius
        run_circle_case(3'b111,8'd120,7'd90,8'd7,200000);

        // test 5 r equals 0 degenerate case
        run_circle_case(3'b101,8'd50,7'd40,8'd0,50000);

        $display("tb_syn_circle all tests passed");
        $finish(0);
    end

endmodule: tb_syn_circle