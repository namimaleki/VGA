`timescale 1ns/1ps
module tb_rtl_circle();

    // Declare signals
    logic clk, rst_n, start;
    logic [2:0] colour;
    logic [7:0] centre_x;
    logic [6:0] centre_y;
    logic [7:0] radius;
    logic done;
    logic [7:0] vga_x;
    logic [6:0] vga_y;
    logic [2:0] vga_colour;
    logic vga_plot;

    // Instantiate DUT
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

    // Clock: 50 MHz (period 20ns)
    initial clk = 1'b0;
    always #10 clk = ~clk;

    // Local copies of circle state encodings
    localparam int IDLE_S = 0;
    localparam int INIT_S = 1;
    localparam int PLOT_S = 2;
    localparam int UPDATE_S = 3;
    localparam int DONE_S = 4;

    
    // Helpers
    task automatic tick();
        @(posedge clk);
        #1;
    endtask

    task automatic do_reset();
        begin
            rst_n = 1'b1;
            start = 1'b0;
            colour = 3'b000;
            centre_x = 8'd0;
            centre_y = 7'd0;
            radius = 8'd0;

            // active-low synchronous reset
            rst_n = 1'b0;
            tick();
            rst_n = 1'b1;
            tick();
        end
    endtask

    task automatic wait_done_with_timeout(input int max_cycles);
        int c;
        begin
            c = 0;
            while (done !== 1'b1) begin
                tick();
                c++;
                if (c > max_cycles) begin
                    $error("TIMEOUT: done did not assert within %0d cycles", max_cycles);
                    $finish(1);
                end
            end
        end
    endtask

    // Compute expected octant coordinate for CURRENT internal regs.
    // We use RTL hierarchical access (allowed for tb_rtl_*).
    task automatic expected_octant_xy(
        input  logic [2:0] oct,
        output logic signed [9:0] ex,
        output logic signed [8:0] ey
    );
        logic signed [9:0] cx_s;
        logic signed [8:0] cy_s;
        logic signed [8:0] ox;
        logic signed [8:0] oy;
        begin
            cx_s = {1'b0, UUT.cx_reg};
            cy_s = {1'b0, UUT.cy_reg};
            ox   = UUT.offset_x;
            oy   = UUT.offset_y;

            ex = 10'sd0;
            ey =  9'sd0;

            case (oct)
                3'd0: begin ex = cx_s + ox; ey = cy_s + oy; end
                3'd1: begin ex = cx_s + oy; ey = cy_s + ox; end
                3'd2: begin ex = cx_s - ox; ey = cy_s + oy; end
                3'd3: begin ex = cx_s - oy; ey = cy_s + ox; end
                3'd4: begin ex = cx_s - ox; ey = cy_s - oy; end
                3'd5: begin ex = cx_s - oy; ey = cy_s - ox; end
                3'd6: begin ex = cx_s + ox; ey = cy_s - oy; end
                3'd7: begin ex = cx_s + oy; ey = cy_s - ox; end
                default: begin ex = 10'sd0; ey = 9'sd0; end
            endcase
        end
    endtask

    task automatic check_plot_cycle();
        logic signed [9:0] ex;
        logic signed [8:0] ey;
        logic exp_in_bounds;
        begin
            // We will only check mapping while in the plot state
            if (UUT.state == PLOT_S) begin
                expected_octant_xy(UUT.octant_idx, ex, ey);

                exp_in_bounds = (ex >= 0) && (ex <= 10'sd159) && (ey >= 0) && (ey <= 9'sd119);

                // Colour should always be the latched colour while plotting
                assert(vga_colour == UUT.colour_reg)
                    else $error("PLOT: vga_colour mismatch. expected latched %0d got %0d", UUT.colour_reg, vga_colour);

                // Plot should match bounds check
                assert(vga_plot == exp_in_bounds)
                    else $error("PLOT: vga_plot mismatch. exp_in_bounds=%0d got vga_plot=%0d (ex=%0d ey=%0d)",
                                exp_in_bounds, vga_plot, ex, ey);

                // If in bounds, coordinates must match expected octant mapping
                if (exp_in_bounds) begin
                    assert(vga_x == ex[7:0])
                        else $error("PLOT: vga_x mismatch. expected %0d got %0d (oct=%0d ox=%0d oy=%0d)",
                                    ex, vga_x, UUT.octant_idx, UUT.offset_x, UUT.offset_y);
                    assert(vga_y == ey[6:0])
                        else $error("PLOT: vga_y mismatch. expected %0d got %0d (oct=%0d ox=%0d oy=%0d)",
                                    ey, vga_y, UUT.octant_idx, UUT.offset_x, UUT.offset_y);
                end
            end
        end
    endtask

    // Run for N cycles and check every cycle (no for-loops; use while)
    task automatic run_and_check_cycles(input int ncycles);
        int i;
        begin
            i = 0;
            while (i < ncycles) begin
                tick();
                check_plot_cycle();

                // Safety: if vga_plot is high, output coords must be in bounds
                if (vga_plot) begin
                    assert(vga_x <= 8'd159) else $error("Out of bounds x plotted: %0d", vga_x);
                    assert(vga_y <= 7'd119) else $error("Out of bounds y plotted: %0d", vga_y);
                end

                i++;
            end
        end
    endtask

    // TESTS
    initial begin
        // TEST 1: Reset puts module in IDLE and quiet outputs
        do_reset();

        assert(UUT.state == IDLE_S) else $error("TEST1: expected IDLE after reset, got state=%0d", UUT.state);
        assert(done == 1'b0) else $error("TEST1: done should be 0 after reset");
        assert(vga_plot == 1'b0) else $error("TEST1: vga_plot should be 0 after reset");

        // TEST 2: Small radius (r=0) centered well inside screen
        // Expect: PLOT cycles output the same centre point (duplicates), then done
        colour = 3'b101;
        centre_x = 8'd50;
        centre_y = 7'd40;
        radius = 8'd0;

        start = 1'b1;
        tick(); // move into INIT
        tick(); // enter PLOT

        // Run enough cycles to get through a few plot cycles + update + done
        run_and_check_cycles(40);

        wait_done_with_timeout(2000);

        // done should stay high while start stays high
        tick();
        assert(done == 1'b1) else $error("TEST2: done should remain 1 while start is high");

        // deassert start -> should eventually drop done and return to IDLE
        start = 1'b0;
        tick();
        tick();
        assert(done == 1'b0) else $error("TEST2: done should drop after start deasserted");
        assert(UUT.state == IDLE_S) else $error("TEST2: expected IDLE after start deasserted");


        // TEST 3: Normal circle (r=5) in the middle, verify octant mapping + no OOB
        colour = 3'b010;
        centre_x = 8'd80;
        centre_y = 7'd60;
        radius = 8'd5;

        start = 1'b1;
        tick(); // INIT
        tick(); // PLOT begins

        // Let it run for a while checking mapping each PLOT cycle
        run_and_check_cycles(400);

        wait_done_with_timeout(20000);

        // TEST 4: Clipping test (circle partially off-screen)
        // Centre near top-left with larger radius, expect many octants out-of-bounds, but should never plot out of bounds
        start = 1'b0;
        tick();
        tick();

        colour = 3'b001;
        centre_x = 8'd1;
        centre_y = 7'd1;
        radius = 8'd20;

        start = 1'b1;
        tick(); // INIT
        tick(); // PLOT begins

        // Run and continuously ensure no OOB pixels are plotted.
        run_and_check_cycles(1200);

        wait_done_with_timeout(200000);

        // done handshake again
        start = 1'b1;
        tick();
        assert(done == 1'b1) else $error("TEST4: done should remain high while start high");
        start = 1'b0;
        tick();
        tick();
        assert(done == 1'b0) else $error("TEST4: done should drop after start low");

        // TEST 5: Restart immediately after a completed run
        colour = 3'b110;
        centre_x = 8'd100;
        centre_y = 7'd30;
        radius = 8'd8;

        start = 1'b1;
        tick();
        tick();

        run_and_check_cycles(800);
        wait_done_with_timeout(50000);

        start = 1'b0;
        tick();
        tick();
        assert(UUT.state == IDLE_S) else $error("TEST5: expected IDLE after restart sequence");

        $display("tb_rtl_circle: ALL TESTS PASSED");
        $finish(0);
    end

endmodule: tb_rtl_circle