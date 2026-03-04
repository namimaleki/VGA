`timescale 1ns/1ps
module tb_rtl_circle();

    // rtl testbench for circle
    // here we are allowed to peek internal registers because this is tb_rtl
    // that lets us check the octant mapping exactly and not just guess from outputs
    // we still keep it realistic by mainly checking the vga outputs and handshake

    // dut signals
    logic clk,rst_n,start;
    logic [2:0] colour;
    logic [7:0] centre_x;
    logic [6:0] centre_y;
    logic [7:0] radius;
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

    // 50mhz clock
    initial clk = 1'b0;
    always #10 clk = ~clk;

    // local copies of circle state encodings
    // these match the enum values in your circle module
    localparam int IDLE_S = 0;
    localparam int INIT_S = 1;
    localparam int PLOT_S = 2;
    localparam int UPDATE_S = 3;
    localparam int DONE_S = 4;

    // helpers
    // one clean clock step and then a small delay so signals settle
    task automatic step_cycle();
        @(posedge clk);
        #1;
    endtask

    // reset helper
    // reset is active low and synchronous so we hold rst_n low for one clock edge
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

    // wait for done but do not hang forever
    // this keeps the tb from getting stuck if something is broken
    task automatic wait_for_done_or_fail(input int max_cycles);
        int cycles;
        begin
            cycles = 0;
            while(done !== 1'b1) begin
                step_cycle();
                cycles = cycles + 1;
                if(cycles > max_cycles) begin
                    $error("timeout done did not assert within %0d cycles", max_cycles);
                    $finish(1);
                end
            end
        end
    endtask

    // compute the expected pixel for a given octant based on the dut internal regs
    // we do this so we can check your octant mapping is exactly right
    task automatic calc_expected_octant_xy(
        input logic [2:0] oct,
        output logic signed [9:0] exp_x,
        output logic signed [8:0] exp_y
    );
        logic signed [9:0] cx_s;
        logic signed [8:0] cy_s;
        logic signed [8:0] ox;
        logic signed [8:0] oy;
        begin
            cx_s = {1'b0,UUT.cx_reg};
            cy_s = {1'b0,UUT.cy_reg};
            ox = UUT.offset_x;
            oy = UUT.offset_y;

            exp_x = 10'sd0;
            exp_y = 9'sd0;

            case(oct)
                3'd0: begin exp_x = cx_s + ox; exp_y = cy_s + oy; end
                3'd1: begin exp_x = cx_s + oy; exp_y = cy_s + ox; end
                3'd2: begin exp_x = cx_s - ox; exp_y = cy_s + oy; end
                3'd3: begin exp_x = cx_s - oy; exp_y = cy_s + ox; end
                3'd4: begin exp_x = cx_s - ox; exp_y = cy_s - oy; end
                3'd5: begin exp_x = cx_s - oy; exp_y = cy_s - ox; end
                3'd6: begin exp_x = cx_s + ox; exp_y = cy_s - oy; end
                3'd7: begin exp_x = cx_s + oy; exp_y = cy_s - ox; end
                default: begin exp_x = 10'sd0; exp_y = 9'sd0; end
            endcase
        end
    endtask

    // check one cycle worth of behavior when the dut is in plot
    // we verify colour is latched colour
    // we verify vga_plot matches in bounds logic
    // and if we are in bounds we verify vga_x and vga_y match the expected mapping
    task automatic check_plot_cycle_mapping();
        logic signed [9:0] exp_x;
        logic signed [8:0] exp_y;
        logic exp_in_bounds;
        begin
            if(UUT.state == PLOT_S) begin
                calc_expected_octant_xy(UUT.octant_idx,exp_x,exp_y);

                exp_in_bounds = (exp_x >= 0) && (exp_x <= 10'sd159) && (exp_y >= 0) && (exp_y <= 9'sd119);

                assert(vga_colour == UUT.colour_reg)
                    else $error("plot colour mismatch expected %0d got %0d", UUT.colour_reg, vga_colour);

                assert(vga_plot == exp_in_bounds)
                    else $error("plot enable mismatch expected %0d got %0d exp_x %0d exp_y %0d", exp_in_bounds, vga_plot, exp_x, exp_y);

                if(exp_in_bounds) begin
                    assert(vga_x == exp_x[7:0])
                        else $error("x mismatch expected %0d got %0d oct %0d ox %0d oy %0d", exp_x, vga_x, UUT.octant_idx, UUT.offset_x, UUT.offset_y);
                    assert(vga_y == exp_y[6:0])
                        else $error("y mismatch expected %0d got %0d oct %0d ox %0d oy %0d", exp_y, vga_y, UUT.octant_idx, UUT.offset_x, UUT.offset_y);
                end
            end
        end
    endtask

    // run for n cycles and check mapping on every cycle
    // also always enforce safety that we never plot out of bounds
    task automatic run_cycles_with_checks(input int ncycles);
        int i;
        begin
            i = 0;
            while(i < ncycles) begin
                step_cycle();
                check_plot_cycle_mapping();

                if(vga_plot) begin
                    assert(vga_x <= 8'd159) else $error("oob plot x %0d", vga_x);
                    assert(vga_y <= 7'd119) else $error("oob plot y %0d", vga_y);
                end

                i = i + 1;
            end
        end
    endtask

    initial begin
        // test 1 reset should put us in idle and keep outputs quiet
        apply_reset();

        assert(UUT.state == IDLE_S) else $error("t1 expected idle after reset got %0d", UUT.state);
        assert(done == 1'b0) else $error("t1 done should be 0 after reset");
        assert(vga_plot == 1'b0) else $error("t1 vga_plot should be 0 after reset");

        // test 2 radius 0 case
        // this is a corner case because all 8 octants map to the same center point
        // we mainly care that the module runs and reaches done and handshake works
        colour = 3'b101;
        centre_x = 8'd50;
        centre_y = 7'd40;
        radius = 8'd0;

        start = 1'b1;
        step_cycle(); 
        step_cycle(); 

        run_cycles_with_checks(40);
        wait_for_done_or_fail(2000);

        step_cycle();
        assert(done == 1'b1) else $error("t2 done should stay high while start is high");

        start = 1'b0;
        step_cycle();
        step_cycle();
        assert(done == 1'b0) else $error("t2 done should drop after start goes low");
        assert(UUT.state == IDLE_S) else $error("t2 expected idle after start low");

        // test 3 normal circle in the middle
        // here we check mapping a lot to catch any octant mistakes
        colour = 3'b010;
        centre_x = 8'd80;
        centre_y = 7'd60;
        radius = 8'd5;

        start = 1'b1;
        step_cycle();
        step_cycle();

        run_cycles_with_checks(400);
        wait_for_done_or_fail(20000);

        // test 4 clipping case
        // center near top left and radius bigger
        // many candidate pixels are off screen and should not be plotted
        start = 1'b0;
        step_cycle();
        step_cycle();

        colour = 3'b001;
        centre_x = 8'd1;
        centre_y = 7'd1;
        radius = 8'd20;

        start = 1'b1;
        step_cycle();
        step_cycle();

        run_cycles_with_checks(1200);
        wait_for_done_or_fail(200000);

        start = 1'b1;
        step_cycle();
        assert(done == 1'b1) else $error("t4 done should remain high while start high");
        start = 1'b0;
        step_cycle();
        step_cycle();
        assert(done == 1'b0) else $error("t4 done should drop after start low");

        // test 5 restart after a completed run
        // this checks we can go back to idle and start again cleanly
        colour = 3'b110;
        centre_x = 8'd100;
        centre_y = 7'd30;
        radius = 8'd8;

        start = 1'b1;
        step_cycle();
        step_cycle();

        run_cycles_with_checks(800);
        wait_for_done_or_fail(50000);

        start = 1'b0;
        step_cycle();
        step_cycle();
        assert(UUT.state == IDLE_S) else $error("t5 expected idle after restart sequence");

        $display("tb_rtl_circle all tests passed");
        $finish(0);
    end

endmodule: tb_rtl_circle