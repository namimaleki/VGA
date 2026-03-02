module circle(input logic clk, input logic rst_n, input logic [2:0] colour,
              input logic [7:0] centre_x, input logic [6:0] centre_y, input logic [7:0] radius,
              input logic start, output logic done,
              output logic [7:0] vga_x, output logic [6:0] vga_y,
              output logic [2:0] vga_colour, output logic vga_plot);
     // draw the circle

     // States for state machine 
     typedef enum logic [2:0] {
               IDLE = 3'd0, // waiting for start to be asserted 
               INIT = 3'd1, // initialization state where we reset inputs and init the Bresenham variables 
               PLOT = 3'd2, // Output one of the 8 octant pixels where we will use an octant_idx to select which 
               UPDATE = 3'd3, // update necessary offsets and check on conditions 
               DONE = 3'd4 // done will be asserted until start is deasserted 
     } state_t; 

     state_t state, next_state; 

     // Note that drawing the circle requires many clock cycles so we need registers where we can store center x, y 
     // radius and colour or else if the change middle of drawing that would mess everything up this is known as latching. 

     // Latched inputs: These are the parameters that we need stable while drawing a circle.
     // we wil load them once in INIT state, and then we use these registers for all the math until we reach the done state
     logic [2:0] colour_reg;
     logic [7:0] cx_reg; 
     logic [6:0] cy_reg; 

     // Bresenham variables
     logic signed [8:0] offset_x; // starts at radius, decreases sometimes 
     logic signed [8:0] offset_y; // starts at 0, increases every iteration 
     logic signed [11:0] crit; // starts at 1 - radius, updated 
     
     // which octant pixel are we outputting this cycle 
     logic [2:0] octant_idx; 

     // temp coords for bounds checking
     logic signed [9:0] tmp_x;
     logic signed [8:0] tmp_y;
     
     // in bounds check 
     logic in_bounds;
     
     // Loop condition: we keep going while offsety is less than or equal to offset x 
     logic loop_continue;
     assign loop_continue = (offset_y <= offset_x); 

     // Store new offsets so update works accordingly 
     logic signed [8:0] offset_y_new; 
     logic signed [8:0] offset_x_new; 
     logic signed [11:0] crit_new; 
     logic loop_continue_new;

     // Combinational logic for our update states next values 
     always_comb begin
          // defaults
          offset_y_new = offset_y + 9'sd1; 
          offset_x_new = offset_x; 
          crit_new = crit; 

          // Bresenham update 
          if (crit <= 0) begin 
               crit_new = crit + (12'sd2 * $signed(offset_y_new)) + 12'sd1; 
          end else begin 
               offset_x_new = offset_x - 9'sd1; 
               crit_new = crit + (12'sd2 * $signed(offset_y_new - offset_x_new)) + 12'sd1; 
          end 

          // Decide loop using the updated offsets
          loop_continue_new = (offset_y_new <= offset_x_new);
     end

     // Combinational loop: compute the temp coords
     always_comb begin 
          tmp_x = 0;
          tmp_y = 0; 

          // Convert center coords to signed and zero extend (doing this for the arithmetic)
          logic signed [9:0] cx_s; 
          logic signed [8:0] cy_s; 
          cx_s = {1'b0, cx_reg}; 
          cy_s = {1'b0, cy_reg};

          // Now we use the pseudocode logic in the lab handout to compute the tmp coordinates 
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

     // Now we can perform our bounds check for the VGA screen recall x e [0, 159] and y e [0, 119]
     always_comb begin 
          in_bounds = 0; 
          if ((tmp_x >= 0) && (tmp_x <= 10'd159) && (tmp_y >= 0) && (tmp_y <= 9'd119)) begin 
               in_bounds = 1'b1; 
          end 
     end 


     // Next_state logic 
     always_comb begin 
          next_state = state; 

          case (state)  
               IDLE: begin 
                    // wait for start 
                    if (start) next_state = INIT; 
               end 

               INIT: begin 
                    // next state is plotting first octant pixel 
                    next_state = PLOT; 
               end 

               PLOT: begin 
                    // After octant 7, go update the Bresenham variables else we keep plotting
                    if (octant_idx == 3'd7) next_state = UPDATE; 
                    else next_state = PLOT; 
               end 

               UPDATE: begin 
                    // if loop still continues, go plot next iteration otherwise we're done 
                    if (loop_continue_new) next_state = PLOT; 
                    else next_state = DONE; 
               end 

               DONE: begin 
                    // hold done high until start goes low 
                    if (~start) next_state = IDLE; 
               end 

               default: next_state = IDLE; 
          endcase
     end 

     // Sequential logic 
     always_ff @(posedge clk) begin 
          if (!rst_n) begin 
               state <= IDLE;

               // Output-related regs
               done <= 1'b0;
               vga_x <= 8'd0;
               vga_y <= 7'd0;
               vga_colour <= 3'd0;
               vga_plot <= 1'b0;

               // Latched inputs
               colour_reg <= 3'd0;
               cx_reg <= 8'd0;
               cy_reg <= 7'd0;

               // Bresenham vars
               offset_x <= '0;
               offset_y <= '0;
               crit <= '0;
               octant_idx <= 3'd0;
          end 
          else begin
               state <= next_state; 

               // Defaults 
               done <= 1'b0; 
               vga_plot <= 1'b0; 

               case (state) 
                    IDLE: begin 
                         // do nothing until start and keep outputs as default 
                         octant_idx <= 3'd0; 
                    end 

                    INIT: begin 
                         // Latch inputs moment we start drawing 
                         colour_reg <= colour; 
                         cx_reg <= centre_x; 
                         cy_reg <= centre_y; 

                         // Init bresenham variables 
                         offset_x <= {1'b0, radius}; 
                         offset_y <= 9'd0; 
                         crit <= 12'sd1 - $signed({1'b0, radius}); 
                         octant_idx <= 3'd0;
                    end 

                    PLOT: begin 
                         // output one pixel per cycle 
                         // if out of bounds we simply will not plot this cycle but we keep advancing the octant 
                         vga_colour <= colour_reg; 

                         if (in_bounds) begin 
                              vga_x <= tmp_x[7:0]; 
                              vga_y <= tmp_y[6:0];
                              vga_plot <= 1'b1; 
                         end else begin 
                              vga_plot <= 1'b0; 
                         end 

                         // octant idx logic we advance and if we're at last octant we wrap 
                         if (octant_idx == 3'd7) octant_idx <= 3'd0; 
                         else octant_idx <= octant_idx + 3'd1; 
                    end 

                    UPDATE: begin 
                         // update Bresenham variables once per cycle 
                         // Pseudocode:
                         //   offset_y = offset_y + 1
                         //   if crit <= 0:
                         //       crit = crit + 2*offset_y + 1
                         //   else:
                         //       offset_x = offset_x - 1
                         //       crit = crit + 2*(offset_y - offset_x) + 1

                         offset_y <= offset_y_new; 
                         offset_x <= offset_x_new;
                         crit <= crit_new;

                    end 

                    DONE: begin 
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