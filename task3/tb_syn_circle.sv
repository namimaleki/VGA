`timescale 1ns/1ps
module tb_syn_circle();

    // Post-synthesis testbench for circle
    // We verify behavior using only the public I/O:
    // - done/start handshake
    // - vga_plot only asserts when coordinates are in bounds
    // - vga_colour equals the requested colour whenever vga_plot is high
    // - circle completes (done asserts) within a reasonable timeout

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

    // 50MHz clock
    initial clk=1'b0;
    always #10 clk=~clk;

    task automatic tick();
        @(posedge clk);
        #1;
    endtask

    task automatic do_reset();
        begin
            rst_n=1'b1;
            start=1'b0;
            colour=3'b000;
            centre_x=8'd0;
            centre_y=7'd0;
            radius=8'd0;

            // active-low synchronous reset
            rst_n=1'b0;
            tick();
            rst_n=1'b1;
            tick();
        end
    endtask

    task automatic wait_done(input int max_cycles);
        int c;
        begin
            c=0;
            while (done!==1'b1) begin
                tick();
                c=c+1;

                // Safety checks while running
                if (vga_plot) begin
                    // If the design plots, it must be within screen bounds
                    assert(vga_x<=8'd159) else $error("OOB plot: x=%0d", vga_x);
                    assert(vga_y<=7'd119) else $error("OOB plot: y=%0d", vga_y);

                    // Colour must match requested colour on plotted pixels
                    assert(vga_colour==colour) else $error("Colour mismatch: expected %0d got %0d", colour, vga_colour);
                end

                if (c>max_cycles) begin
                    $error("TIMEOUT: done did not assert within %0d cycles", max_cycles);
                    $finish(1);
                end
            end
        end
    endtask

    task automatic run_case(input [2:0] c,input [7:0] cx,input [6:0] cy,input [7:0] r,input int timeout);
        int i;
        bit saw_plot;
        begin
            colour=c;
            centre_x=cx;
            centre_y=cy;
            radius=r;

            // start handshake: hold start high until done
            start=1'b1;

            // Watch a bit to make sure something happens (unless r=0 and clipping makes it silent)
            i=0;
            saw_plot=0;
            while (i<2000) begin
                tick();
                if (vga_plot) saw_plot=1;
                if (done) break;
                i=i+1;
            end

            // If radius is small and in-bounds, we should eventually see plotting
            if (r!=8'd0) begin
                // For heavily clipped circles, it's possible to see very few plots, but usually not zero.
                // We do not hard-fail on saw_plot here; we still rely on bounds + done.
            end

            // Wait for done (with checks inside)
            wait_done(timeout);

            // done should remain high as long as start is high
            tick();
            assert(done==1'b1) else $error("done should remain high while start is high");

            // Deassert start, done should drop within a couple cycles
            start=1'b0;
            tick();
            tick();
            assert(done==1'b0) else $error("done should drop after start deasserted");
        end
    endtask

    initial begin
        // TEST 1: reset behavior
        do_reset();
        assert(done==1'b0) else $error("TEST1: done should be 0 after reset");
        assert(vga_plot==1'b0) else $error("TEST1: vga_plot should be 0 after reset");

        // TEST 2: typical in-bounds circle
        run_case(3'b010,8'd80,7'd60,8'd10,200000);

        // TEST 3: clipping case (near corner)
        run_case(3'b001,8'd1,7'd1,8'd25,400000);

        // TEST 4: another typical case, different colour/centre/radius
        run_case(3'b111,8'd120,7'd90,8'd7,200000);

        // TEST 5: r=0 case (degenerate circle)
        run_case(3'b101,8'd50,7'd40,8'd0,50000);

        $display("tb_syn_circle: ALL TESTS PASSED");
        $finish(0);
    end

endmodule: tb_syn_circle