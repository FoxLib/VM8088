`timescale 10ns / 1ns
module tb;

// -----------------------------------------------------------------------------
reg clock;      always #0.5 clock    = ~clock;
reg clock_25;   always #1.0 clock_25 = ~clock_25;
// -----------------------------------------------------------------------------
initial begin clock = 0; clock_25 = 0; #2000 $finish; end
initial begin $dumpfile("tb.vcd"); $dumpvars(0, tb); end
initial begin $readmemh("tb.hex", memory); end
// -----------------------------------------------------------------------------
reg  [ 7:0] memory[1024*1024];
wire [19:0] address;
wire [ 7:0] in = memory[address];
wire [ 7:0] out;
wire        we;

always @(posedge clock) if (we) memory[address] <= out;
// -----------------------------------------------------------------------------

core Processor
(
    .clock      (clock_25),
    .reset_n    (1'b1),
    .locked     (1'b1),
    .address    (address),
    .in         (in),
    .out        (out),
    .we         (we)
);

endmodule
