`timescale 1ns/1ps
module tb_rtl_reuleaux();

    // rtl testbench for reuleaux

    // UUT signals 
    logic clk,rst_n,start;
    logic [2:0] colour;
    logic [7:0] centre_x;
    logic [6:0] centre_y;
    logic [7:0] diameter;

    logic done;
    logic [7:0] vga_x;
    logic [6:0] vga_y;
    logic [2:0] vga_colour;
    logic vga_plot;

    // instantiate reauleaux 
    reuleaux UUT(
        .clk(clk),
        .rst_n(rst_n),
        .colour(colour),
        .centre_x(centre_x),
        .centre_y(centre_y),
        .diameter(diameter),
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

    // helper to step one cycle 
    task automatic step_cycle();
        @(posedge clk);
        #1;
    endtask

    // reset helper
    // reset is active low synchronous so we pulse rst_n low for one clock edge
    // we also set inputs to known values so the tb is deterministic
    task automatic apply_reset();
        begin
            rst_n = 1'b1;
            start = 1'b0;
            colour = 3'b000;
            centre_x = 8'd0;
            centre_y = 7'd0;
            diameter = 8'd0;

            // Activate reset by setting it to 0 
            rst_n = 1'b0;
            // step a cycle 
            step_cycle();
            // deassert reset 
            rst_n = 1'b1;
            step_cycle();
        end
    endtask

    // safety check
    // if the module tries to plot then x and y must be inside the screen
    // and colour should match the input colour we asked it to draw with
    task automatic assert_plot_is_safe();
        begin
            if(vga_plot) begin
                assert(vga_x <= 8'd159) else $error("oob plot x %0d", vga_x);
                assert(vga_y <= 7'd119) else $error("oob plot y %0d", vga_y);
                assert(vga_colour == colour) else $error("colour mismatch expected %0d got %0d", colour, vga_colour);
            end
        end
    endtask

    // wait for done but do not hang forever
    // we also run safety checks each cycle while waiting
    task automatic wait_for_done_or_fail(input int max_cycles);
        int cycles;
        begin
            // keep track of cycles 
            cycles = 0;
            while(done !== 1'b1) begin
                step_cycle();
                assert_plot_is_safe();
                cycles = cycles + 1;
                // check to make sure we are within our time budget 
                if(cycles > max_cycles) begin
                    $error("timeout done did not assert within %0d cycles", max_cycles);
                    $finish(1);
                end
            end
        end
    endtask

    // run one full case
    // this sets the inputs then asserts start and watches for some activity then waits for done and checks the handshake behavior
    task automatic run_reuleaux_case(input [2:0] req_colour,input [7:0] req_cx,input [6:0] req_cy,input [7:0] req_d,input int timeout_cycles,input int watch_cycles);
        int i;
        bit saw_any_plot;
        begin
            // set the inputs 
            colour = req_colour;
            centre_x = req_cx;
            centre_y = req_cy;
            diameter = req_d;

            // start is a level handshake so we hold it high until done
            start = 1'b1;

            // quick sanity window
            // for normal in bounds cases we expect to see plotting soon
            // for extreme clipping it might take longer or have fewer pixels so we do not enforce it there
            i = 0; // keep track of # of cycles 
            saw_any_plot = 0;
            while(i < watch_cycles) begin
                step_cycle();
                assert_plot_is_safe();
                if(vga_plot) saw_any_plot = 1;
                if(done) break;
                i = i + 1;
            end

            // only require early plotting for a reasonable centered case
            if((req_cx >= 8'd40) && (req_cx <= 8'd120) && (req_cy >= 7'd30) && (req_cy <= 7'd90) && (req_d >= 8'd20)) begin
                assert(saw_any_plot) else $error("expected to see plotted pixels early for in bounds case but saw none");
            end

            // finish the run and ensure we hit done in time
            wait_for_done_or_fail(timeout_cycles);

            // done must stay high while start is still high
            step_cycle();
            assert(done == 1'b1) else $error("done should remain high while start is high");

            // release start and done should drop after a couple cycles
            start = 1'b0;
            step_cycle();
            step_cycle();
            assert(done == 1'b0) else $error("done should drop after start deasserted");
        end
    endtask

    initial begin
        // test 1 reset behavior
        apply_reset();
        assert(done == 1'b0) else $error("t1 done should be 0 after reset");
        assert(vga_plot == 1'b0) else $error("t1 vga_plot should be 0 after reset");

        // test 2 normal centered triangle even diameter is what the lab will use
        run_reuleaux_case(3'b010,8'd80,7'd60,8'd80,900000,4000);

        // test 3 smaller even diameter and different colour just to make sure colour path is correct
        run_reuleaux_case(3'b101,8'd90,7'd50,8'd40,700000,3000);

        // test 4 clipping case near corner
        // main thing here is safety we must never plot out of bounds
        run_reuleaux_case(3'b001,8'd10,7'd10,8'd80,900000,6000);

        // test 5 restart case to make sure it can run again cleanly
        run_reuleaux_case(3'b111,8'd120,7'd80,8'd60,900000,4000);

        $display("tb_rtl_reuleaux all tests passed");
        $finish(0);
    end

endmodule: tb_rtl_reuleaux