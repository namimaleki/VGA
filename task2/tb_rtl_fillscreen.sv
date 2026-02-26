`timescale 1ns/1ps
module tb_rtl_fillscreen();

    // UUT signals
    logic clk, rst_n, start;
    logic [2:0] colour;
    logic done;
    logic [7:0] vga_x;
    logic [6:0] vga_y;
    logic [2:0] vga_colour;
    logic vga_plot;
    
    //state signals
    reg [1:0] state, next_state;

    //intermediate signals
    integer cycle_count;

    // instantiate DUT
    fillscreen UUT(
        .clk(clk),
        .rst_n(rst_n),
        .colour(colour),
        .start(start),
        .done(done),
        .vga_x(vga_x),
        .vga_y(vga_y),
        .vga_colour(vga_colour),
        .vga_plot(vga_plot)
    );

    assign state = UUT.state;
    assign next_state = UUT.next_state;
    
    // clock generation: 50MHz
    initial clk = 0;
    always #10 clk = ~clk;

    // test flow
    initial begin
        // init
        rst_n  = 1;
        start  = 0;
        colour = 3'b0;

        // TEST 1: reset
        rst_n = 0;
        @(posedge clk); #1;
        assert(done == 1'b0)       else $error("TEST1 FAIL: done should be 0 on reset, got %0d", done);
        assert(vga_plot == 1'b1)   else $error("TEST1 FAIL: vga_plot should be 1 in CLEAR, got %0d", vga_plot);
        assert(vga_colour == 3'b0) else $error("TEST1 FAIL: colour should be black in CLEAR, got %0d", vga_colour);
        assert(state == 2'd0)      else $error("TEST1 FAIL: state should be CLEAR, got %0d", state);
        assert(next_state == 2'd0) else $error("TEST1 FAIL: next_state should be CLEAR, got %0d", next_state);
        rst_n = 1;
        @(posedge clk); #1;

        // TEST 2: clear -> wait
        assert(state == 2'd0)      else $error("TEST2 FAIL: should be in CLEAR after reset, got %0d", state);
        assert(vga_plot == 1'b1)   else $error("TEST2 FAIL: vga_plot should be 1 during CLEAR, got %0d", vga_plot);
        assert(vga_colour == 3'b0) else $error("TEST2 FAIL: colour should be black during CLEAR, got %0d", vga_colour);
        assert(next_state == 2'd0) else $error("TEST2 FAIL: next_state should be CLEAR, got %0d", next_state);
        repeat(19200) @(posedge clk); #1;
        assert(state == 2'd1)      else $error("TEST2 FAIL: should be in WAIT after clear, got %0d", state);
        assert(next_state == 2'd1) else $error("TEST2 FAIL: next_state should be WAIT, got %0d", next_state);
        assert(vga_plot == 1'b0)   else $error("TEST2 FAIL: vga_plot should be 0 in WAIT, got %0d", vga_plot);

        // TEST 3: wait -> plot
        start = 1;
        @(posedge clk); #1;
        assert(state == 2'd2)      else $error("TEST3 FAIL: should be in PLOT after start, got %0d", state);
        assert(next_state == 2'd2) else $error("TEST3 FAIL: next_state should be PLOT, got %0d", next_state);
        assert(vga_plot == 1'b1)   else $error("TEST3 FAIL: vga_plot should be 1 in PLOT, got %0d", vga_plot);
        assert(vga_x == 8'd0)      else $error("TEST3 FAIL: vga_x should start at 0, got %0d", vga_x);
        assert(vga_y == 7'd0)      else $error("TEST3 FAIL: vga_y should start at 0, got %0d", vga_y);

        // TEST 4: correct colour
        assert(vga_colour == 3'd0) else $error("TEST4 FAIL: x=0 colour should be 0, got %0d", vga_colour);
        repeat(960) @(posedge clk); #1;
        assert(vga_x == 8'd8)      else $error("TEST4 FAIL: x should be 8, got %0d", vga_x);
        assert(vga_colour == 3'd0) else $error("TEST4 FAIL: x=8 colour should wrap to 0, got %0d", vga_colour);
        assert(state == 2'd2)      else $error("TEST4 FAIL: should still be in PLOT, got %0d", state);
        assert(next_state == 2'd2) else $error("TEST4 FAIL: next_state should still be PLOT, got %0d", next_state);

        // TEST 5: counter 
        repeat(119) @(posedge clk); #1;
        assert(vga_y == 7'd119)    else $error("TEST5 FAIL: y should be 119 at end of column, got %0d", vga_y);
        assert(vga_x == 8'd8)      else $error("TEST5 FAIL: x should still be 8, got %0d", vga_x);
        assert(state == 2'd2)      else $error("TEST5 FAIL: should still be in PLOT, got %0d", state);
        assert(next_state == 2'd2) else $error("TEST5 FAIL: next_state should be PLOT, got %0d", next_state);
        @(posedge clk); #1;
        assert(vga_y == 7'd0)      else $error("TEST5 FAIL: y should wrap to 0, got %0d", vga_y);
        assert(vga_x == 8'd9)      else $error("TEST5 FAIL: x should increment to 9, got %0d", vga_x);

        // TEST 6: plot -> done
        repeat(18119) @(posedge clk); #1;
        assert(vga_x == 8'd159)    else $error("TEST6 FAIL: x should be 159, got %0d", vga_x);
        assert(vga_y == 7'd119)    else $error("TEST6 FAIL: y should be 119, got %0d", vga_y);
        assert(state == 2'd2)      else $error("TEST6 FAIL: should still be in PLOT, got %0d", state);
        assert(next_state == 2'd3) else $error("TEST6 FAIL: next_state should be DONE, got %0d", next_state);
        @(posedge clk); #1;
        assert(state == 2'd3)      else $error("TEST6 FAIL: should be in DONE, got %0d", state);
        assert(next_state == 2'd3) else $error("TEST6 FAIL: next_state should be DONE (start=1), got %0d", next_state);
        assert(done == 1'b1)       else $error("TEST6 FAIL: done should be 1, got %0d", done);
        assert(vga_plot == 1'b0)   else $error("TEST6 FAIL: vga_plot should be 0, got %0d", vga_plot);

        // TEST 7: done -> wait 
        assert(state == 2'd3)      else $error("TEST7 FAIL: should still be in DONE, got %0d", state);
        assert(next_state == 2'd3) else $error("TEST7 FAIL: next_state should be DONE (start=1), got %0d", next_state);
        assert(done == 1'b1)       else $error("TEST7 FAIL: done should still be 1, got %0d", done);
        start = 0;
        @(posedge clk); #1;
        assert(next_state == 2'd1) else $error("TEST7 FAIL: next_state should be WAIT after ~start, got %0d", next_state);
        @(posedge clk); #1;
        assert(state == 2'd1)      else $error("TEST7 FAIL: should be in WAIT, got %0d", state);
        assert(next_state == 2'd1) else $error("TEST7 FAIL: next_state should stay WAIT, got %0d", next_state);
        assert(done == 1'b0)       else $error("TEST7 FAIL: done should be 0, got %0d", done);
        assert(vga_plot == 1'b0)   else $error("TEST7 FAIL: vga_plot should be 0, got %0d", vga_plot);

        // TEST 8: wait -> plot 
        // cycle count <= 19210
        cycle_count = 0;
        start = 1;
        @(posedge clk); #1;
        assert(state == 2'd2) else $error("TEST8 FAIL: should be in PLOT, got %0d", state);
        
        // count cycles until done
        while(done !== 1'b1) begin
            @(posedge clk); #1;
            cycle_count = cycle_count + 1;
            if(cycle_count > 19210) begin
                $error("TEST8 FAIL: exceeded 19210 cycle, at cycle count: %0d", cycle_count);
                break;
            end
        end
        
        assert(cycle_count <= 19210) else $error("TEST8 FAIL: took %0d cycles, max is 19210 cycles.", cycle_count);
        $display("TESTS PASS: completed in %0d cycles", cycle_count);
        $finish(0);
    end

endmodule: tb_rtl_fillscreen