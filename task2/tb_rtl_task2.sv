`timescale 1ns/1ps
module tb_rtl_task2();
    logic CLOCK_50;
    logic [3:0] KEY;
    logic [9:0] SW;
    logic [9:0] LEDR;
    logic [7:0] VGA_R, VGA_G, VGA_B;
    logic VGA_HS, VGA_VS, VGA_CLK;
    logic [7:0] VGA_X;
    logic [6:0] VGA_Y;
    logic [2:0] VGA_COLOUR;
    logic VGA_PLOT;

    task2 UUT(
        .CLOCK_50(CLOCK_50),
        .KEY(KEY),
        .SW(SW),
        .LEDR(LEDR),
        .HEX0(), .HEX1(), .HEX2(), .HEX3(), .HEX4(), .HEX5(),
        .VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B),
        .VGA_HS(VGA_HS), .VGA_VS(VGA_VS), .VGA_CLK(VGA_CLK),
        .VGA_X(VGA_X), .VGA_Y(VGA_Y),
        .VGA_COLOUR(VGA_COLOUR), .VGA_PLOT(VGA_PLOT)
    );

    initial CLOCK_50 = 0;
    always #10 CLOCK_50 = ~CLOCK_50;

    initial begin
    KEY = 4'hF;  
    SW  = 10'b0;

    // TEST 1: reset (KEY[3] active low)
    KEY[3] = 0;
    @(posedge CLOCK_50); #1;
    assert(LEDR[0] == 0)    else $error("TEST1 FAIL: done should be 0 on reset");
    assert(VGA_PLOT == 1)   else $error("TEST1 FAIL: VGA_PLOT should be 1 in CLEAR");
    assert(VGA_COLOUR == 0) else $error("TEST1 FAIL: VGA_COLOUR should be black in CLEAR");
    KEY[3] = 1;

    // wait for CLEAR to finish
    repeat(19200) @(posedge CLOCK_50); #1;


    // TEST 2: assert start via KEY[0] (active low)
    SW[2:0] = 3'b101;
    KEY[0]  = 0; 
    repeat(2) @(posedge CLOCK_50); #1;
    assert(VGA_PLOT == 1) else $error("TEST2 FAIL: VGA_PLOT should be 1 during PLOT");

    // wait for PLOT to finish
    repeat(19198) @(posedge CLOCK_50); #1;

    // release start
    KEY[0] = 1;  

    //assert done is high after plot finishes    
    @(posedge CLOCK_50) #1;
    assert(LEDR[0] == 1) else $error("TEST3 FAIL: LEDR[0] should be 1 when done");
    $finish(0);

end

endmodule: tb_rtl_task2