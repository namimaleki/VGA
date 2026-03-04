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
    logic signed [8:0] c1y,c2y,c3y;

    // we draw 3 circles total
    // circle_idx tells us which corner circle we are currently doing
    logic [1:0] circle_idx;

    // ccx ccy is the current circle center chosen from the three corners
    // this makes the bresenham logic reusable for all 3 circles
    logic signed [9:0] ccx;
    logic signed [8:0] ccy;

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

    // bresenham registers for drawing one circle boundary
    // we reuse the exact same idea as task3 circle
    logic signed [8:0] offset_x;
    logic signed [8:0] offset_y;
    logic signed [11:0] crit;

    // octant_idx selects which of the 8 symmetric points we output this cycle
    // 8 cycles of plot then 1 cycle of update then repeat
    logic [2:0] octant_idx;

    // precompute update results
    // this keeps the update state clean and also makes the loop decision consistent
    logic signed [8:0] offset_x_new;
    logic signed [8:0] offset_y_new;
    logic signed [11:0] crit_new;
    logic loop_continue_new;

    // same idea as task 3 code we compue the offsets and crit value based on the new computed values
    always_comb begin
        offset_y_new = offset_y + 9'sd1;
        offset_x_new = offset_x;
        crit_new = crit;

        if(crit <= 12'sd0) begin
            crit_new = crit + (12'sd2 * $signed(offset_y_new)) + 12'sd1;
        end else begin
            offset_x_new = offset_x - 9'sd1;
            crit_new = crit + (12'sd2 * $signed(offset_y_new - offset_x_new)) + 12'sd1;
        end

        loop_continue_new = (offset_y_new <= offset_x_new);
    end

    // tmp_x tmp_y is the candidate boundary pixel for this cycle
    // this is just the octant mapping around the current center ccx ccy
    logic signed [9:0] tmp_x;
    logic signed [8:0] tmp_y;

    always_comb begin
        tmp_x = 10'sd0;
        tmp_y = 9'sd0;
        case(octant_idx)
            3'd0: begin tmp_x = ccx + offset_x; tmp_y = ccy + offset_y; end
            3'd1: begin tmp_x = ccx + offset_y; tmp_y = ccy + offset_x; end
            3'd2: begin tmp_x = ccx - offset_x; tmp_y = ccy + offset_y; end
            3'd3: begin tmp_x = ccx - offset_y; tmp_y = ccy + offset_x; end
            3'd4: begin tmp_x = ccx - offset_x; tmp_y = ccy - offset_y; end
            3'd5: begin tmp_x = ccx - offset_y; tmp_y = ccy - offset_x; end
            3'd6: begin tmp_x = ccx + offset_x; tmp_y = ccy - offset_y; end
            3'd7: begin tmp_x = ccx + offset_y; tmp_y = ccy - offset_x; end
            default: begin tmp_x = 10'sd0; tmp_y = 9'sd0; end
        endcase
    end

    // first level clipping is screen bounds
    // we still spend the cycle but we keep vga_plot low so the vga core does not write
    logic in_bounds;
    always_comb begin
        in_bounds = 1'b0;
        if((tmp_x >= 0) && (tmp_x <= 10'sd159) && (tmp_y >= 0) && (tmp_y <= 9'sd119)) in_bounds = 1'b1;
    end

    // second level clipping is the reuleaux rule
    // the pixel must be inside the other two circles
    // we do distance squared compare so we do not need sqrt in hardware
    // d2 is diameter squared because radius for these circles is diameter
    logic [21:0] d2;
    assign d2 = $unsigned(d_reg) * $unsigned(d_reg);

    // Helper task to compute distance squared
    // dx and dy are signed
    // we cast to unsigned for the squared sum because result is non negative
    task automatic dist2_to_task(input logic signed [9:0] px,input logic signed [8:0] py,input logic signed [9:0] cx,input logic signed [8:0] cy,output logic [21:0] d2_out);
        logic signed [10:0] dx;
        logic signed [9:0] dy;
        begin
            dx = px - cx;
            dy = py - cy;
            d2_out = $unsigned(dx * dx) + $unsigned(dy * dy);
        end
    endtask

    // for the reuleaux triangle we only want the arc that is inside the other two circles
    // so for each candidate boundary pixel we check it against the other two circle centers
    // inside_other1 means the pixel is inside the first other circle
    // inside_other2 means the pixel is inside the second other circle
    logic inside_other1;
    logic inside_other2;
    logic [21:0] d2_other1;
    logic [21:0] d2_other2;

    // combinational logic that decides which two circles are the other circles
    // circle_idx tells us which circle we are currently generating boundary points for
    // if we are drawing circle 0 we must check inside circle 1 and circle 2 and same logic for others
    // then we compare the computed distance squared to d2 which is diameter squared
    // if d2_other <= d2 then the pixel is inside or on that circle
    always_comb begin
        inside_other1 = 1'b0;
        inside_other2 = 1'b0;
        d2_other1 = 22'd0;
        d2_other2 = 22'd0;

        if(circle_idx == 2'd0) begin
            dist2_to_task(tmp_x,tmp_y,c2x,c2y,d2_other1);
            dist2_to_task(tmp_x,tmp_y,c3x,c3y,d2_other2);
        end else if(circle_idx == 2'd1) begin
            dist2_to_task(tmp_x,tmp_y,c1x,c1y,d2_other1);
            dist2_to_task(tmp_x,tmp_y,c3x,c3y,d2_other2);
        end else begin
            dist2_to_task(tmp_x,tmp_y,c1x,c1y,d2_other1);
            dist2_to_task(tmp_x,tmp_y,c2x,c2y,d2_other2);
        end

        inside_other1 = (d2_other1 <= d2);
        inside_other2 = (d2_other2 <= d2);
    end

    // plot_ok is the final permission for writing a pixel
    // it must be on screen and inside both other circles
    logic plot_ok;
    assign plot_ok = in_bounds && inside_other1 && inside_other2;

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

            done <= 1'b0;
            vga_x <= 8'd0;
            vga_y <= 7'd0;
            vga_colour <= 3'd0;
            vga_plot <= 1'b0;

            colour_reg <= 3'd0;
            cx_reg <= 8'd0;
            cy_reg <= 7'd0;
            d_reg <= 8'd0;

            c1x <= 10'sd0;
            c1y <= 9'sd0;
            c2x <= 10'sd0;
            c2y <= 9'sd0;
            c3x <= 10'sd0;
            c3y <= 9'sd0;
            circle_idx <= 2'd0;

            offset_x <= 9'sd0;
            offset_y <= 9'sd0;
            crit <= 12'sd0;
            octant_idx <= 3'd0;

        end else begin
            state <= next_state;

            // defaults each cycle
            // vga_plot is only high when we truly want to write a pixel
            // done is only high in the done state
            done <= 1'b0;
            vga_plot <= 1'b0;

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
                    // c1 and c2 are down left and down right
                    // c3 is the top point
                    c1x <= $signed({1'b0,centre_x}) + $signed({1'b0,(diameter / 2)});
                    c2x <= $signed({1'b0,centre_x}) - $signed({1'b0,(diameter / 2)});
                    c3x <= $signed({1'b0,centre_x});

                    c1y <= $signed({1'b0,centre_y}) + $signed(yoff1_q[8:0]);
                    c2y <= $signed({1'b0,centre_y}) + $signed(yoff1_q[8:0]);
                    c3y <= $signed({1'b0,centre_y}) - $signed(yoff3_q[8:0]);

                    circle_idx <= 2'd0;
                end

                CINIT: begin
                    // init bresenham for the current circle
                    // radius equals diameter for the reuleaux construction
                    offset_y <= 9'sd0;
                    offset_x <= $signed({1'b0,d_reg});
                    crit <= 12'sd1 - $signed({1'b0,d_reg});
                    octant_idx <= 3'd0;
                end

                PLOT: begin
                    // one pixel per cycle
                    // plot_ok already includes screen bounds and the inside other circles checks
                    vga_colour <= colour_reg;
                   
                    // pixel is only written when plot_ok is true
                    if(plot_ok) begin
                        vga_x <= tmp_x[7:0];
                        vga_y <= tmp_y[6:0];
                        vga_plot <= 1'b1;
                    end else begin
                        vga_plot <= 1'b0;
                    end

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
                    // handshake behavior
                    // done stays high until start goes low
                    done <= 1'b1;
                end

                default: begin end
            endcase
        end
    end

endmodule