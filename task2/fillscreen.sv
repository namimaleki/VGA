module fillscreen(input logic clk,input logic rst_n,input logic [2:0] colour,
                  input logic start,output logic done,
                  output logic [7:0] vga_x,output logic [6:0] vga_y,
                  output logic [2:0] vga_colour,output logic vga_plot);

    // This module has two jobs depending on the state:
    // CLEAR: write black to every pixel (0,0) -> (159,119) one pixel per clock
    // PLOT: write vertical stripes where colour = x mod 8 (so x_count[2:0])
    // Handshake: user holds start high until done goes high, then drops start to re-arm

    logic [1:0] state,next_state;
    parameter CLEAR = 2'd0,WAIT = 2'd1,PLOT = 2'd2,DONE = 2'd3;

    logic pixel_done;
    logic [7:0] x_count;
    logic [6:0] y_count;

    // This advances (x_count,y_count) like:
    // y goes 0->119, then wraps to 0 and x increments
    // once we reach (159,119) we mark pixel_done and wrap back to (0,0)
    task counter;
        if(pixel_done) begin
            x_count <= 8'd0;
            y_count <= 7'd0;
        end else if(y_count == 7'd119) begin
            y_count <= 7'd0;
            x_count <= x_count + 8'd1;
        end else begin
            y_count <= y_count + 7'd1;
        end
    endtask

    // Next state logic (combinational)
    always_comb begin
        next_state = CLEAR;
        case(state)
            CLEAR: begin
                next_state = pixel_done ? WAIT : CLEAR;
            end
            WAIT: begin
                next_state = start ? PLOT : WAIT;
            end
            PLOT: begin
                next_state = (!start && !pixel_done) ? WAIT :
                             (pixel_done) ? DONE : PLOT;
            end
            DONE: begin
                // done stays high until start is released
                next_state = (!start) ? WAIT :
                             (start) ? PLOT : DONE;
            end
        endcase
    end

    // Sequential state register + counters 
    always_ff @(posedge clk) begin
        if(!rst_n) begin
            state <= CLEAR;
            x_count <= 8'd0;
            y_count <= 7'd0;
        end else begin
            state <= next_state;

            // Only advance pixel counters while we are actively writing pixels
            if(state == CLEAR || state == PLOT) begin
                counter();
            end else begin
                // In WAIT/DONE we reset counters so the next run starts at (0,0)
                x_count <= 8'd0;
                y_count <= 7'd0;
            end
        end
    end

    // Output logic (combinational)
    always_comb begin
        done = 1'b0;
        vga_x = 8'd0;
        vga_y = 7'd0;
        vga_plot = 1'b0;
        vga_colour = 3'd0;

        case(state)
            CLEAR: begin
                vga_x = x_count;
                vga_y = y_count;
                vga_plot = 1'b1;
                vga_colour = 3'b000;
            end
            WAIT: begin
            end
            PLOT: begin
                vga_x = x_count;
                vga_y = y_count;
                vga_plot = 1'b1;
                vga_colour = x_count[2:0];
            end
            DONE: begin
                done = 1'b1;
            end
        endcase
    end

    // We are done once we have written the last screen pixel
    assign pixel_done = (x_count == 8'd159) && (y_count == 7'd119);

endmodule