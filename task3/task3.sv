module task3(input logic CLOCK_50,input logic [3:0] KEY,
             input logic [9:0] SW,output logic [9:0] LEDR,
             output logic [6:0] HEX0,output logic [6:0] HEX1,output logic [6:0] HEX2,
             output logic [6:0] HEX3,output logic [6:0] HEX4,output logic [6:0] HEX5,
             output logic [7:0] VGA_R,output logic [7:0] VGA_G,output logic [7:0] VGA_B,
             output logic VGA_HS,output logic VGA_VS,output logic VGA_CLK,
             output logic [7:0] VGA_X,output logic [6:0] VGA_Y,
             output logic [2:0] VGA_COLOUR,output logic VGA_PLOT);

    // In task3 we have to do the following:
    // First, we clear the screen 
    // Then, draw the circle (centre=(80,60), radius=40, colour=green)
    // Since the VGA adapter only lets us write ONE pixel per clock cycle, both clearing and drawing
    // are naturally multi-cycle operations. That’s why we have a small top-level FSM

    // KEY[3] is active-low reset for both VGA core and our logic
    logic rst_n;
    assign rst_n = KEY[3];

    // KEY[0] is the start button and it’s active-low on the board
    logic start_btn;
    assign start_btn = ~KEY[0];

    // VGA adapter core
    // Note we set res to 160x120 because our design outputs 0..159 and 0..119
    // also note that the adapter outputs 10 bit rgb but the board uses 8 bit so we slice [9:2] after instantiation 
    logic [9:0] vga_r10;
    logic [9:0] vga_g10;
    logic [9:0] vga_b10;
    logic vga_blank;
    logic vga_sync;

    // Instantiate w correct parameters 
    vga_adapter #(
        .RESOLUTION("160x120"),
        .MONOCHROME("FALSE"),
        .BITS_PER_COLOUR_CHANNEL(1),
        .BACKGROUND_IMAGE("background.mif"),
        .USING_DE1("FALSE")
    ) VGA (
        .resetn(rst_n),
        .clock(CLOCK_50),
        .colour(VGA_COLOUR),
        .x(VGA_X),
        .y(VGA_Y),
        .plot(VGA_PLOT),
        .VGA_R(vga_r10),
        .VGA_G(vga_g10),
        .VGA_B(vga_b10),
        .VGA_HS(VGA_HS),
        .VGA_VS(VGA_VS),
        .VGA_BLANK(vga_blank),
        .VGA_SYNC(vga_sync),
        .VGA_CLK(VGA_CLK)
    );

    assign VGA_R = vga_r10[9:2];
    assign VGA_G = vga_g10[9:2];
    assign VGA_B = vga_b10[9:2];

    // Top-level states
    // - BOOT_CLEAR: happens right after reset, we clear the whole framebuffer to black
    // - WAIT_START: idle state, we wait for the user to press start
    // - PRE_CLEAR: clear again right before drawing since we're told to clear again even if the screen looks black 
    // - DRAW_CIRCLE: run the circle module until it says done
    // - HOLD_DONE: keep done asserted until the user releases start
    typedef enum logic [2:0] {
        BOOT_CLEAR = 3'd0,
        WAIT_START = 3'd1,
        PRE_CLEAR = 3'd2,
        DRAW_CIRCLE = 3'd3,
        HOLD_DONE = 3'd4
    } top_state_t;

    top_state_t top_state,top_next_state;

    // Clear-screen counters we're gonna use these to figure out when we're done clearing the screen
    // We write one black pixel per clock, scanning y from 0..119, then increment x.
    logic [7:0] clr_x;
    logic [6:0] clr_y;

    // When we reach the last pixel (159,119), the clear pass is complete
    logic all_clear;
    assign all_clear = (clr_x == 8'd159) && (clr_y == 7'd119);

    // Circle module wires note that the circle module produces its own VGA write signals
    logic circle_done;
    // go flag for the circle this will be asserted if we're in the DRAW_CIRCLE state and it will signal the start of the circle module 
    logic circle_go;

    logic [7:0] circle_vga_x;
    logic [6:0] circle_vga_y;
    logic [2:0] circle_vga_colour;
    logic circle_vga_plot;

    // Circle module instantiation
    // Fixed parameters required by the lab for the top-level demo:
    // - green circle (010)
    // - centre at (80,60)
    // - radius 40
    circle CIRCLE(
        .clk(CLOCK_50),
        .rst_n(rst_n),
        .colour(3'b010),
        .centre_x(8'd80),
        .centre_y(7'd60),
        .radius(8'd40),
        .start(circle_go),
        .done(circle_done),
        .vga_x(circle_vga_x),
        .vga_y(circle_vga_y),
        .vga_colour(circle_vga_colour),
        .vga_plot(circle_vga_plot)
    );

    // The circle module uses a start/done handshake where start must be held high while drawing, and it will raise done when finished.
    assign circle_go = (top_state == DRAW_CIRCLE);

    // Next-state logic for the top-level FSM
    always_comb begin
        top_next_state = top_state;

        case(top_state)
            BOOT_CLEAR: begin
                // We stay here until the clear counters reach the last pixel and everything is cleared 
                if(all_clear) top_next_state = WAIT_START;
            end

            WAIT_START: begin
                // Idle state: do nothing until user presses start.
                if(start_btn) top_next_state = PRE_CLEAR;
            end

            PRE_CLEAR: begin
                // Clear again before drawing. This matches the handout requirement.
                if(all_clear) top_next_state = DRAW_CIRCLE;
            end

            DRAW_CIRCLE: begin
                // Circle module will then run in parallel and we will just wait until it asserts done 
                if(circle_done) top_next_state = HOLD_DONE;
            end

            HOLD_DONE: begin
                // Keep done high until user releases start, then allow a new run.
                if(!start_btn) top_next_state = WAIT_START;
            end

            default: top_next_state = BOOT_CLEAR;
        endcase
    end

    // Sequential state register  and clear counter updates
    always_ff @(posedge CLOCK_50) begin
        if(!rst_n) begin
            // On reset we always start clearing from (0,0)
            top_state <= BOOT_CLEAR;
            clr_x <= 8'd0;
            clr_y <= 7'd0;
        end else begin
            top_state <= top_next_state;

            // Only advance the clear counters while we are in a clear state
            if(top_state == BOOT_CLEAR || top_state == PRE_CLEAR) begin
                if(all_clear) begin
                    clr_x <= 8'd0;
                    clr_y <= 7'd0;
                end else if(clr_y == 7'd119) begin
                    clr_y <= 7'd0;
                    clr_x <= clr_x + 8'd1;
                end else begin
                    clr_y <= clr_y + 7'd1;
                end
            end else begin
                // if we're not in a clear state then the counters should be at 0 so when we start clearing we start from top left 
                clr_x <= 8'd0;
                clr_y <= 7'd0;
            end
        end
    end

    // VGA drive mux
    // we need a drive mux in place as only one thing can drive the vga ports to framebuffer. So here's how we will figure out wether task3 will drive those inputs or circle:
    // - During clearing states: we drive the VGA core directly with (clr_x, clr_y) and black
    // - During drawing state: we forward the circle module’s VGA outputs
    // - Otherwise: VGA_PLOT stays 0 so we don’t accidentally overwrite pixels
    always_comb begin
        // defaults
        VGA_X = 8'd0;
        VGA_Y = 7'd0;
        VGA_COLOUR = 3'd0;
        VGA_PLOT = 1'b0;

        // if in clear states we send clr x and clr y and black 
        if(top_state == BOOT_CLEAR || top_state == PRE_CLEAR) begin
            VGA_X = clr_x;
            VGA_Y = clr_y;
            VGA_COLOUR = 3'b000;
            VGA_PLOT = 1'b1;
        end else if(top_state == DRAW_CIRCLE) begin
            // circle signals 
            VGA_X = circle_vga_x;
            VGA_Y = circle_vga_y;
            VGA_COLOUR = circle_vga_colour;
            VGA_PLOT = circle_vga_plot;
        end
    end

    // We use LEDR[0] as our done indicator for demos and testbenches
    always_comb begin
        LEDR = 10'd0;
        LEDR[0] = (top_state == HOLD_DONE);
    end

endmodule: task3