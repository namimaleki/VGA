module reuleaux(input logic clk,input logic rst_n,input logic [2:0] colour,
                input logic [7:0] centre_x,input logic [6:0] centre_y,input logic [7:0] diameter,
                input logic start,output logic done,
                output logic [7:0] vga_x,output logic [6:0] vga_y,
                output logic [2:0] vga_colour,output logic vga_plot);

    // this module draws the reuleaux triangle boundary pointy end up
    // the easiest way to think about it is 3 circles of the same radius
    // each circle is centered at one corner of an equilateral triangle
    // the reuleaux boundary is the part of each circle that is still inside the other two circles
    // so we generate circle boundary points then we clip hard

    // we need sqrt3 for corner y offsets but note that sqrt is not synthesizable so we approximate sqrt3 using a fixed point constant
    // SQRT3_K is sqrt3 scaled by 2^SQRT3_Q
    // then we do integer division which gives us truncation like the real formula would under sim
    localparam int unsigned SQRT3_Q = 20;
    // this constant must match the usual Q20 sqrt3 value or the corners shift and clipping gets weird
    localparam int unsigned SQRT3_K = 1811939;

    // top level fsm
    // idle waits for start
    // latch captures inputs and computes the 3 corners
    // cinit sets up bresenham for the current circle
    // plot outputs one octant pixel per cycle
    // update does the bresenham math once per loop iteration
    // nextcircle switches which corner circle we are drawing
    // done holds until start goes low
    typedef enum logic [3:0] {
        IDLE = 4'd0,
        LATCH = 4'd1,
        CINIT = 4'd2,
        PLOT = 4'd3,
        UPDATE = 4'd4,
        NEXTCIRCLE = 4'd5,
        DONE = 4'd6
    } state_t;

    state_t state,next_state;

    // latched registers
    logic [2:0] colour_reg;
    logic [7:0] cx_reg;
    logic [6:0] cy_reg;
    logic [7:0] d_reg;

    // these are the triangle corner coordinates
    // signed because corners can end up off screen and also because we do subtractions
    logic signed [9:0] c1x,c2x,c3x;
    // widened y corners from [8:0] to [9:0] to match x width and avoid sign extension mismatches when feeding into distance subtraction later
    logic signed [9:0] c1y,c2y,c3y;

    // we draw 3 circles total
    // circle_idx tells us which corner circle we are currently doing
    logic [1:0] circle_idx;

    // ccx ccy is the current circle center chosen from the three corners this makes the bresenham logic reusable for all 3 circles
    logic signed [9:0] ccx;
    // widened ccy to [9:0] to stay consistent with the wider corner y registers
    logic signed [9:0] ccy;

    // comb logic to select current circle center based on circle_idx
    always_comb begin
        ccx = c1x;
        ccy = c1y;
        case(circle_idx)
            2'd0: begin ccx = c1x; ccy = c1y; end
            2'd1: begin ccx = c2x; ccy = c2y; end
            2'd2: begin ccx = c3x; ccy = c3y; end
            default: begin ccx = c1x; ccy = c1y; end
        endcase
    end

    // we also pick the other two circle centers once this makes clipping simpler and avoids mixing up which circles we are checking
    logic signed [9:0] o1x,o2x;
    logic signed [9:0] o1y,o2y;

    // combination logic that assignes the other circles centers based on the current circle index so for example
    // if curr circle is 0 then the other centers would be centers of circle 1 and 2 center coords
    always_comb begin
        o1x = c2x;
        o1y = c2y;
        o2x = c3x;
        o2y = c3y;

        if(circle_idx == 2'd0) begin
            o1x = c2x; 
            o1y = c2y;
            o2x = c3x; 
            o2y = c3y;
        end else if(circle_idx == 2'd1) begin
            o1x = c1x; 
            o1y = c1y;
            o2x = c3x; 
            o2y = c3y;
        end else begin
            o1x = c1x; 
            o1y = c1y;
            o2x = c2x; 
            o2y = c2y;
        end
    end

    // bresenham registers for drawing one circle boundary
    // we reuse the exact same idea as task3 circle
    logic signed [8:0] offset_x;
    logic signed [8:0] offset_y;
    // note that we have widened crit from [11:0] to [15:0] at radius 80 the accumulator can exceed 2047 which is the signed 12-bit ceiling overflow flips the sign and corrupts which bresenham branch we take which distorts the circle
    logic signed [15:0] crit;

    // octant_idx selects which of the 8 symmetric points we output this cycle
    // 8 cycles of plot then 1 cycle of update then repeat
    logic [2:0] octant_idx;

    // precompute update results
    // this keeps the update state clean and also makes the loop decision consistent
    logic signed [8:0] offset_x_new;
    logic signed [8:0] offset_y_new;
    logic signed [15:0] crit_new;
    logic loop_continue_new;

    // same idea as task 3 code we compute the offsets and crit value based on the new computed values
    always_comb begin
        offset_y_new = offset_y + 9'sd1;
        offset_x_new = offset_x;
        crit_new = crit;

        if(crit <= 16'sd0) begin
            crit_new = crit + (16'sd2 * $signed(offset_y_new)) + 16'sd1;
        end else begin
            offset_x_new = offset_x - 9'sd1;
            crit_new = crit + (16'sd2 * $signed(offset_y_new - offset_x_new)) + 16'sd1;
        end

        loop_continue_new = (offset_y_new <= offset_x_new);
    end

    // tmp_x tmp_y is the candidate boundary pixel for this cycle
    // this is just the octant mapping around the current center ccx ccy
    logic signed [9:0] tmp_x;
    logic signed [9:0] tmp_y;

    // combination logic that computes the candidate boundry pixel based on the octant index
    always_comb begin
        tmp_x = 10'sd0;
        tmp_y = 10'sd0;
        case(octant_idx)
            3'd0: begin tmp_x = ccx + offset_x; tmp_y = ccy + offset_y; end
            3'd1: begin tmp_x = ccx + offset_y; tmp_y = ccy + offset_x; end
            3'd2: begin tmp_x = ccx - offset_x; tmp_y = ccy + offset_y; end
            3'd3: begin tmp_x = ccx - offset_y; tmp_y = ccy + offset_x; end
            3'd4: begin tmp_x = ccx - offset_x; tmp_y = ccy - offset_y; end
            3'd5: begin tmp_x = ccx - offset_y; tmp_y = ccy - offset_x; end
            3'd6: begin tmp_x = ccx + offset_x; tmp_y = ccy - offset_y; end
            3'd7: begin tmp_x = ccx + offset_y; tmp_y = ccy - offset_x; end
            default: begin tmp_x = 10'sd0; tmp_y = 10'sd0; end
        endcase
    end

    // first level clipping is screen bounds
    // we still spend the cycle but we keep vga_plot low so the vga core does not write
    logic in_bounds;
    always_comb begin
        in_bounds = 1'b0;
        if((tmp_x >= 0) && (tmp_x <= 10'sd159) && (tmp_y >= 0) && (tmp_y <= 10'sd119)) in_bounds = 1'b1;
    end

    // second level clipping is the reuleaux rule
    // the pixel must be inside the other two circles
    // we do distance squared compare so we do not need sqrt in hardware
    // IMPORTANT this math must be done in wide enough types or it will overflow and nothing clips
    // this block is basically the same sizing idea as your friends working code

    // turn tmp into slightly wider pixels so subtractions and squares behave
    logic signed [10:0] px;
    logic signed [10:0] py;

    always_comb begin
        px = $signed(tmp_x);
        py = $signed(tmp_y);
    end

    // dx and dy to each other circle center
    logic signed [11:0] dx1;
    logic signed [11:0] dy1s;
    logic signed [11:0] dx2;
    logic signed [11:0] dy2s;

    // squared distances and radius squared
    logic [23:0] dist1;
    logic [23:0] dist2;
    logic [23:0] d2_clip;

    // keep_pixel is the final inside check result
    logic keep_pixel;

    // compute distance math inside comb always block 
    always_comb begin
        // signed deltas from pixel to each other center always computed no gating
        dx1 = px - $signed(o1x);
        dy1s = py - $signed(o1y);

        dx2 = px - $signed(o2x);
        dy2s = py - $signed(o2y);

        // square and add in a width that cannot wrap for our screen sizes
        dist1 = dx1 * dx1 + dy1s * dy1s;
        dist2 = dx2 * dx2 + dy2s * dy2s;

        // radius for each construction circle is diameter
        d2_clip = d_reg * d_reg;

        // inside both other circles AND on screen means we keep this boundary pixel
        // in_bounds is folded in here instead of gating the whole block above
        keep_pixel = in_bounds && (dist1 <= d2_clip) && (dist2 <= d2_clip);
    end

    // plot_ok is the final permission for writing a pixel
    // it must be on screen and inside both other circles
    logic plot_ok;
    assign plot_ok = keep_pixel;

    // drive vga outputs combinationally instead of registering them
    // Note that registering vga_plot and vga_x/y in the same always_ff block creates a one cycle misalignment
    // vga_x/y would hold the previous octant coords while vga_plot reflects the current decision
    // combinational drive means the vga core always sees x y and plot that correspond to the same cycle
    always_comb begin
        vga_colour = colour_reg;
        vga_plot = (state == PLOT) && plot_ok;
        vga_x = plot_ok ? tmp_x[7:0] : 8'd0;
        vga_y = plot_ok ? tmp_y[6:0] : 7'd0;
        // done is set if we're in the DONE state and note that we transition to idle when ever start gets deasserted so this logic checks out 
        done = (state == DONE);
    end

    // corner math
    // corners are based on the handout formulas
    // yoff1 is diameter*sqrt3/6
    // yoff3 is diameter*sqrt3/3
    // we compute these using fixed point sqrt3_k and integer division which gives truncation
    logic [31:0] mult_d_sqrt3;
    logic [31:0] yoff1_q;
    logic [31:0] yoff3_q;

    always_comb begin
        mult_d_sqrt3 = $unsigned(diameter) * SQRT3_K;
        yoff1_q = mult_d_sqrt3 / (6 * (1 << SQRT3_Q));
        yoff3_q = mult_d_sqrt3 / (3 * (1 << SQRT3_Q));
    end

    // next state logic
    always_comb begin
        next_state = state;
        case(state)
            IDLE: begin
                // latch then cinit then plot update loop
                if(start) next_state = LATCH;
            end
            LATCH: begin
                next_state = CINIT;
            end
            CINIT: begin
                next_state = PLOT;
            end
            PLOT: begin
                if(octant_idx == 3'd7) next_state = UPDATE;
                else next_state = PLOT;
            end
            UPDATE: begin
                // when loop ends we go to next circle
                if(loop_continue_new) next_state = PLOT;
                else next_state = NEXTCIRCLE;
            end
            NEXTCIRCLE: begin
                // after third circle we go to done
                if(circle_idx == 2'd2) next_state = DONE;
                else next_state = CINIT;
            end
            DONE: begin
                if(!start) next_state = IDLE;
            end
            default: next_state = IDLE;
        endcase
    end

    // sequential logic
    // everything updates on posedge clk
    // reset is active low synchronous
    always_ff @(posedge clk) begin
        if(!rst_n) begin
            // Reset all variables to default values
            state <= IDLE;

            colour_reg <= 3'd0;
            cx_reg <= 8'd0;
            cy_reg <= 7'd0;
            d_reg <= 8'd0;

            c1x <= 10'sd0;
            c1y <= 10'sd0;
            c2x <= 10'sd0;
            c2y <= 10'sd0;
            c3x <= 10'sd0;
            c3y <= 10'sd0;
            circle_idx <= 2'd0;

            offset_x <= 9'sd0;
            offset_y <= 9'sd0;
            crit <= 16'sd0;
            octant_idx <= 3'd0;

        end else begin
            state <= next_state;

            case(state)
                IDLE: begin
                    // reset indices so the next start begins clean
                    circle_idx <= 2'd0;
                    octant_idx <= 3'd0;
                end

                LATCH: begin
                    // latch inputs for stability
                    colour_reg <= colour;
                    cx_reg <= centre_x;
                    cy_reg <= centre_y;
                    d_reg <= diameter;

                    // compute corners based on centre and diameter
                    // c1 is the bottom right corner
                    // c2 is the bottom left corner
                    // c3 is the top point
                    c1x <= $signed({1'b0,centre_x}) + $signed({1'b0,(diameter / 2)});
                    c2x <= $signed({1'b0,centre_x}) - $signed({1'b0,(diameter / 2)});
                    c3x <= $signed({1'b0,centre_x});

                    c1y <= $signed({1'b0,centre_y}) + $signed({1'b0,yoff1_q[7:0]});
                    c2y <= $signed({1'b0,centre_y}) + $signed({1'b0,yoff1_q[7:0]});
                    c3y <= $signed({1'b0,centre_y}) - $signed({1'b0,yoff3_q[7:0]});

                    circle_idx <= 2'd0;
                end

                CINIT: begin
                    // init bresenham for the current circle
                    // radius equals diameter for the reuleaux construction
                    offset_y <= 9'sd0;
                    offset_x <= $signed({1'b0,d_reg});
                    // FIX init crit at 16-bit width to match the wider register
                    crit <= 16'sd1 - $signed({1'b0,d_reg});
                    octant_idx <= 3'd0;
                end

                PLOT: begin
                    // one pixel per cycle
                    // vga outputs are now driven combinationally so we only advance octant here
                    // advance octant
                    if(octant_idx == 3'd7) octant_idx <= 3'd0;
                    else octant_idx <= octant_idx + 3'd1;
                end

                UPDATE: begin
                    // apply bresenham update once per iteration
                    offset_y <= offset_y_new;
                    offset_x <= offset_x_new;
                    crit <= crit_new;
                end

                NEXTCIRCLE: begin
                    // move to the next circle center
                    // after circle 2 we will go to done
                    if(circle_idx != 2'd2) circle_idx <= circle_idx + 2'd1;
                end

                DONE: begin
                    // done stays high until start goes low done is driven combinationally above so nothing to do here
                end

                default: begin end
            endcase
        end
    end

endmodule