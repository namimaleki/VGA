module task3(input logic CLOCK_50, input logic [3:0] KEY,
             input logic [9:0] SW, output logic [9:0] LEDR,
             output logic [6:0] HEX0, output logic [6:0] HEX1, output logic [6:0] HEX2,
             output logic [6:0] HEX3, output logic [6:0] HEX4, output logic [6:0] HEX5,
             output logic [7:0] VGA_R, output logic [7:0] VGA_G, output logic [7:0] VGA_B,
             output logic VGA_HS, output logic VGA_VS, output logic VGA_CLK,
             output logic [7:0] VGA_X, output logic [6:0] VGA_Y,
             output logic [2:0] VGA_COLOUR, output logic VGA_PLOT);


    // KEY[3] is active-low reset for both VGA core and our logic
    logic rst_n;
    assign rst_n = KEY[3];

    // KEY[0] is active-low start button
    logic start_btn;
    assign start_btn = ~KEY[0];

    // VGA adapter core
    vga_adapter VGA(
        .resetn(rst_n),
        .clock(CLOCK_50),
        .colour(VGA_COLOUR),
        .x(VGA_X),
        .y(VGA_Y),
        .plot(VGA_PLOT),
        .VGA_R(VGA_R),
        .VGA_G(VGA_G),
        .VGA_B(VGA_B),
        .VGA_HS(VGA_HS),
        .VGA_VS(VGA_VS),
        .VGA_BLANK(),
        .VGA_SYNC(),
        .VGA_CLK(VGA_CLK)
    );

    // Top-level control:
    // - On reset: clear the screen to black automatically
    // - After that: wait for start
    // - On start: clear screen again, then draw circle, then done
    typedef enum logic [2:0] {
        CLEAR0 = 3'd0, // clear after reset
        WAIT = 3'd1, // wait for start
        CLEAR1 = 3'd2, // clear before drawing circle
        DRAW = 3'd3, // draw circle
        DONE = 3'd4 // done asserted until start deasserted
    } top_state_t;

    top_state_t state, next_state;

    // Clear-screen datapath (one black pixel per cycle)
    logic [7:0] clear_x;
    logic [6:0] clear_y;

    logic clear_last;
    assign clear_last = (clear_x == 8'd159) && (clear_y == 7'd119);

    
    // Circle module wires
    logic circle_done;
    logic circle_start;

    logic [7:0] circle_x;
    logic [6:0] circle_y;
    logic [2:0] circle_colour;
    logic circle_plot;

    // Instantiate circle module 
    circle CIRCLE(
        .clk(CLOCK_50),
        .rst_n(rst_n),
        .colour(3'b010),     
        .centre_x(8'd80),
        .centre_y(7'd60),
        .radius(8'd40),
        .start(circle_start),
        .done(circle_done),
        .vga_x(circle_x),
        .vga_y(circle_y),
        .vga_colour(circle_colour),
        .vga_plot(circle_plot)
    );

    // start circle only while in DRAW
    assign circle_start = (state == DRAW);

    // Next-state logic
    always_comb begin
        next_state = state;

        case (state)
            CLEAR0: begin
                if (clear_last) next_state = WAIT;
            end

            WAIT: begin
                if (start_btn) next_state = CLEAR1;
            end

            CLEAR1: begin
                if (clear_last) next_state = DRAW;
            end

            DRAW: begin
                if (circle_done) next_state = DONE;
            end

            DONE: begin
                if (!start_btn) next_state = WAIT;
            end

            default: next_state = CLEAR0;
        endcase
    end

    // Sequential state + clear counters
    always_ff @(posedge CLOCK_50) begin
        if (!rst_n) begin
            state <= CLEAR0;
            clear_x <= 8'd0;
            clear_y <= 7'd0;
        end else begin
            state <= next_state;

            // Clear counters only advance during CLEAR0 or CLEAR1
            if (state == CLEAR0 || state == CLEAR1) begin
                if (clear_last) begin
                    clear_x <= 8'd0;
                    clear_y <= 7'd0;
                end else if (clear_y == 7'd119) begin
                    clear_y <= 7'd0;
                    clear_x <= clear_x + 8'd1;
                end else begin
                    clear_y <= clear_y + 7'd1;
                end
            end else begin
                // keep them reset when not clearing (so clear always starts at 0,0)
                clear_x <= 8'd0;
                clear_y <= 7'd0;
            end
        end
    end

    // VGA drive mux:
    // - During CLEAR states: write black pixels from clear counters
    // - During DRAW: forward circle module VGA signals
    // - Otherwise: don't plot
    always_comb begin
        VGA_X = 8'd0;
        VGA_Y = 7'd0;
        VGA_COLOUR = 3'd0;
        VGA_PLOT = 1'b0;

        if (state == CLEAR0 || state == CLEAR1) begin
            VGA_X = clear_x;
            VGA_Y = clear_y;
            VGA_COLOUR = 3'b000; // black
            VGA_PLOT = 1'b1;   // write one pixel each cycle
        end else if (state == DRAW) begin
            VGA_X = circle_x;
            VGA_Y = circle_y;
            VGA_COLOUR = circle_colour;
            VGA_PLOT = circle_plot;
        end
    end

    // LEDs: show done
    always_comb begin
        LEDR = 10'd0;
        LEDR[0] = (state == DONE);
    end

endmodule: task3