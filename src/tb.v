`timescale 10ns / 1ns
module tb;

// -----------------------------------------------------------------------------
reg clock;      always #0.5 clock    = ~clock;
reg clock_25;   always #1.0 clock_25 = ~clock_25;
// -----------------------------------------------------------------------------
initial begin clock = 0; clock_25 = 0; #2000 $finish; end
initial begin $dumpfile("tb.vcd"); $dumpvars(0, tb); end
// -----------------------------------------------------------------------------

endmodule
