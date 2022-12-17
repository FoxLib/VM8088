`timescale 10ns / 1ns
module tb;

// ---------------------------------------------------------------------
reg         clock;
reg         clock_25;
reg         reset_n = 1'b0;
reg [7:0]   memory[1024*1024];

always  #0.5  clock    = ~clock;
always  #1.5  clock_25 = ~clock_25;
initial begin clock = 0; clock_25 = 0; #3 reset_n = 1; #20 intr = 1; #2000 $finish; end
initial begin $dumpfile("tb.vcd"); $dumpvars(0, tb); end
initial begin $readmemh("bios.hex", memory, 20'hF8000); end
// ---------------------------------------------------------------------
reg         intr    = 1'b0;
reg  [ 7:0] irq     = 8'h00;
// ---------------------------------------------------------------------
wire [31:0] address;
reg  [ 7:0] in;
wire [ 7:0] out;
wire        we;

// Контроллер блочной памяти
always @(posedge clock) begin in <= memory[address[19:0]]; if (we) memory[address[19:0]] <= out; end
// ---------------------------------------------------------------------

// Объявление процессора
core cpu_inst
(
    .clock      (clock_25),
    .reset_n    (reset_n),
    .locked     (1'b1),
    .address    (address),
    .in         (in),
    .out        (out),
    .we         (we),
    .intr       (intr),
    .irq        (irq)
);

endmodule
