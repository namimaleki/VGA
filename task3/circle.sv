module circle(input logic clk,input logic rst_n,input logic [2:0] colour,
              input logic [7:0] centre_x,input logic [6:0] centre_y,input logic [7:0] radius,
              input logic start,output logic done,
              output logic [7:0] vga_x,output logic [6:0] vga_y,
              output logic [2:0] vga_colour,output logic vga_plot);

     // this module draws a circle using bresenham
     // states for the state machine
     // idle means we are waiting for start
     // init means latch inputs and reset bresenham variables
     // plot means output one of the 8 symmetric pixels
     // update means do the bresenham math once per loop iteration
     // done means hold done high until start is dropped
     typedef enum logic [2:0] {
               IDLE = 3'd0, // waiting for start to be asserted
               INIT = 3'd1, // latch inputs and initialize bresenham values
               PLOT = 3'd2, // output pixels one per cycle using octant_idx
               UPDATE = 3'd3, // update offset_x offset_y and crit
               DONE = 3'd4 // done stays high until start goes low
     } state_t;

     state_t state,next_state;

     // latching
     // drawing takes many cycles so inputs can not be used directly
     // if centre or radius changes mid draw it will corrupt the circle
     // so we capture them once in init and then only use the captured values
     logic [2:0] colour_reg;
     logic [7:0] cx_reg;
     logic [6:0] cy_reg;

     // bresenham registers
     // offset_x starts at radius and sometimes decreases
     // offset_y starts at 0 and increases every loop
     // crit is the decision value that decides whether offset_x changes
     logic signed [8:0] offset_x;
     logic signed [8:0] offset_y;
     logic signed [11:0] crit;

     // which symmetric point are we outputting this cycle
     // each loop iteration we output 8 points total
     logic [2:0] octant_idx;

     // tmp_x tmp_y is the candidate pixel we might plot this cycle
     // they are signed because subtraction can make them negative
     logic signed [9:0] tmp_x;
     logic signed [8:0] tmp_y;

     // in bounds check vga screen is x 0 to 159 and y 0 to 119 we must not plot off screen pixels
     logic in_bounds;

     // loop condition from the pseudocode, keep looping while offset_y <= offset_x
     logic loop_continue;
     assign loop_continue = (offset_y <= offset_x);

     // we compute the update results combinationally
     // this way update state can just load the new values and we can also decide next_state using the updated values
     logic signed [8:0] offset_y_new;
     logic signed [8:0] offset_x_new;
     logic signed [11:0] crit_new;
     logic loop_continue_new;

     // combinational math for update state
     // we follow the bresenham pseudocode
     // first offset_y increments
     // then depending on crit we either keep offset_x or decrement it
     // then crit updates accordingly
     always_comb begin
          offset_y_new = offset_y + 9'sd1;
          offset_x_new = offset_x;
          crit_new = crit;

          if(crit <= 0) begin
               crit_new = crit + (12'sd2 * $signed(offset_y_new)) + 12'sd1;
          end else begin
               offset_x_new = offset_x - 9'sd1;
               crit_new = crit + (12'sd2 * $signed(offset_y_new - offset_x_new)) + 12'sd1;
          end

          // decide if the loop will continue using the updated offsets
          loop_continue_new = (offset_y_new <= offset_x_new);
     end

     // compute candidate pixel based on current octant index
     // this is the 8 setPixel calls in the pseudocode
     always_comb begin
          logic signed [9:0] cx_s;
          logic signed [8:0] cy_s;

          tmp_x = 0;
          tmp_y = 0;

          // cast centre coords to signed for arithmetic
          // we are zero extending because centre coords are always non negative
          cx_s = {1'b0,cx_reg};
          cy_s = {1'b0,cy_reg};

          case(octant_idx)
               3'd0: begin tmp_x = cx_s + offset_x; tmp_y = cy_s + offset_y; end
               3'd1: begin tmp_x = cx_s + offset_y; tmp_y = cy_s + offset_x; end
               3'd2: begin tmp_x = cx_s - offset_x; tmp_y = cy_s + offset_y; end
               3'd3: begin tmp_x = cx_s - offset_y; tmp_y = cy_s + offset_x; end
               3'd4: begin tmp_x = cx_s - offset_x; tmp_y = cy_s - offset_y; end
               3'd5: begin tmp_x = cx_s - offset_y; tmp_y = cy_s - offset_x; end
               3'd6: begin tmp_x = cx_s + offset_x; tmp_y = cy_s - offset_y; end
               3'd7: begin tmp_x = cx_s + offset_y; tmp_y = cy_s - offset_x; end
               default: begin tmp_x = 0; tmp_y = 0; end
          endcase
     end

     // clipping
     // we only assert vga_plot when candidate pixel is inside the screen
     // if it is off screen we just skip plotting that pixel but still advance octants
     always_comb begin
          in_bounds = 1'b0;
          if((tmp_x >= 0) && (tmp_x <= 10'd159) && (tmp_y >= 0) && (tmp_y <= 9'd119)) begin
               in_bounds = 1'b1;
          end
     end

     // next state logic
     always_comb begin
          next_state = state;

          case(state)
               IDLE: begin
                    // idle waits for start
                    if(start) next_state = INIT;
               end

               INIT: begin
                    // init always goes to plot   
                    next_state = PLOT;
               end

               PLOT: begin
                    // plot outputs octants 0 to 7 over 8 cycles then goes to update
                    if(octant_idx == 3'd7) next_state = UPDATE;
                    else next_state = PLOT;
               end

               UPDATE: begin
                    // update either goes back to plot for the next iteration or goes to done
                    if(loop_continue_new) next_state = PLOT;
                    else next_state = DONE;
               end

               DONE: begin
                    // done waits for start to drop so we can restart cleanly
                    if(~start) next_state = IDLE;
               end

               default: next_state = IDLE;
          endcase
     end

     // sequential logic
     // all state and datapath registers update on posedge clk
     always_ff @(posedge clk) begin
          if(!rst_n) begin
               state <= IDLE;

               // default outputs on reset
               // vga_plot 0 so we do not accidentally write pixels during reset
               done <= 1'b0;
               vga_x <= 8'd0;
               vga_y <= 7'd0;
               vga_colour <= 3'd0;
               vga_plot <= 1'b0;

               // reset latched inputs
               colour_reg <= 3'd0;
               cx_reg <= 8'd0;
               cy_reg <= 7'd0;

               // reset bresenham registers
               offset_x <= '0;
               offset_y <= '0;
               crit <= '0;
               octant_idx <= 3'd0;
          end else begin
               state <= next_state;

               // defaults every cycle
               // done should only be high in done state
               // vga_plot should only be high in plot state when in bounds
               done <= 1'b0;
               vga_plot <= 1'b0;

               case(state)
                    IDLE: begin
                         // sit here until start
                         // also keep octant index reset so first plot starts at octant 0
                         octant_idx <= 3'd0;
                    end

                    INIT: begin
                         // latch inputs right at the start of drawing
                         // this makes them stable for the whole multi cycle operation
                         colour_reg <= colour;
                         cx_reg <= centre_x;
                         cy_reg <= centre_y;

                         // initialize bresenham
                         // offset_x = radius
                         // offset_y = 0
                         // crit = 1 - radius
                         offset_x <= {1'b0,radius};
                         offset_y <= 9'd0;
                         crit <= 12'sd1 - $signed({1'b0,radius});
                         octant_idx <= 3'd0;
                    end

                    PLOT: begin
                         // output one pixel per cycle
                         // vga core writes on clock edge when vga_plot is high
                         vga_colour <= colour_reg;

                         if(in_bounds) begin
                              vga_x <= tmp_x[7:0];
                              vga_y <= tmp_y[6:0];
                              vga_plot <= 1'b1;
                         end else begin
                              vga_plot <= 1'b0;
                         end

                         // move to next octant
                         // after octant 7 we wrap and next_state will go to update
                         if(octant_idx == 3'd7) octant_idx <= 3'd0;
                         else octant_idx <= octant_idx + 3'd1;
                    end

                    UPDATE: begin
                         // apply the precomputed next values
                         offset_y <= offset_y_new;
                         offset_x <= offset_x_new;
                         crit <= crit_new;
                    end

                    DONE: begin
                         // signal completion to the top level
                         // we keep it high until start goes low
                         done <= 1'b1;
                    end

                    default: begin
                         done <= 1'b0;
                         vga_plot <= 1'b0;
                    end
               endcase
          end
     end

endmodule