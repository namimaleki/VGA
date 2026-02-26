module fillscreen(input logic clk, input logic rst_n, input logic [2:0] colour,
                  input logic start, output logic done,
                  output logic [7:0] vga_x, output logic [6:0] vga_y,
                  output logic [2:0] vga_colour, output logic vga_plot);

    //state assignments
    logic [1:0] state, next_state;
    parameter CLEAR = 2'd0, WAIT = 2'd1, PLOT = 2'd2, DONE = 2'd3;
    
    // internal signals
    logic pixel_done;
    logic [7:0] x_count;
    logic [6:0] y_count;
    
    //helper function counter
    task run_counter;
        if (pixel_done) begin
            x_count <= 8'd0;
            y_count <= 7'd0;
        end 
        else if (y_count == 7'd119) begin
            y_count <= 7'd0;
            x_count <= x_count + 1;
        end 
        else begin
            y_count <= y_count + 1;
        end
    endtask

    //CL INPUT BLOCK
    always_comb begin
        //default 
        next_state = CLEAR;
        case(state) 
            CLEAR: begin
                next_state = (pixel_done) ? WAIT : CLEAR;
            end
            WAIT: begin
                next_state =  (start) ? PLOT : WAIT;
            end
            PLOT: begin 
                next_state =  (pixel_done) ? DONE : PLOT;
            end
            DONE: begin
                next_state =  (~start) ? WAIT : DONE;
            end
        endcase
    end

    //SEQUENTIAL STATE TRANSITION BLOCK
    always_ff @(posedge clk) begin
        if (~rst_n) begin
            state   <= CLEAR;
            x_count <= 8'd0;
            y_count <= 7'd0;
        end else begin
            state <= next_state;
            if (state == CLEAR || state == PLOT) begin
                run_counter();
            end else begin
                x_count <= 8'd0;
                y_count <= 7'd0;
            end
        end
    end
    
    always_comb begin
        // defaults
        done       = 1'b0;
        vga_x      = 8'b0;
        vga_y      = 7'b0;
        vga_plot   = 1'b0;
        vga_colour = 3'b0;

        case(state)
            CLEAR: begin
                vga_x      = x_count;
                vga_y      = y_count;
                vga_plot   = 1'b1;
                vga_colour = 3'b000;
            end
            WAIT: begin
            end
            PLOT: begin
                vga_x      = x_count;
                vga_y      = y_count;
                vga_plot   = 1'b1;
                vga_colour = x_count[2:0];
            end
            DONE: begin
                done = 1'b1;
            end
        endcase
    end

    //assign intermediate signals
    assign pixel_done = (x_count == 8'd159) && (y_count == 7'd119);

endmodule