module de0(

    // Reset
    input              RESET_N,

    // Clocks
    input              CLOCK_50,
    input              CLOCK2_50,
    input              CLOCK3_50,
    inout              CLOCK4_50,

    // DRAM
    output             DRAM_CKE,
    output             DRAM_CLK,
    output      [1:0]  DRAM_BA,
    output      [12:0] DRAM_ADDR,
    inout       [15:0] DRAM_DQ,
    output             DRAM_CAS_N,
    output             DRAM_RAS_N,
    output             DRAM_WE_N,
    output             DRAM_CS_N,
    output             DRAM_LDQM,
    output             DRAM_UDQM,

    // GPIO
    inout       [35:0] GPIO_0,
    inout       [35:0] GPIO_1,

    // 7-Segment LED
    output      [6:0]  HEX0,
    output      [6:0]  HEX1,
    output      [6:0]  HEX2,
    output      [6:0]  HEX3,
    output      [6:0]  HEX4,
    output      [6:0]  HEX5,

    // Keys
    input       [3:0]  KEY,

    // LED
    output      [9:0]  LEDR,

    // PS/2
    inout              PS2_CLK,
    inout              PS2_DAT,
    inout              PS2_CLK2,
    inout              PS2_DAT2,

    // SD-Card
    output             SD_CLK,
    inout              SD_CMD,
    inout       [3:0]  SD_DATA,

    // Switch
    input       [9:0]  SW,

    // VGA
    output      [3:0]  VGA_R,
    output      [3:0]  VGA_G,
    output      [3:0]  VGA_B,
    output             VGA_HS,
    output             VGA_VS
);

// Z-state
assign DRAM_DQ = 16'hzzzz;
assign GPIO_0  = 36'hzzzzzzzz;
assign GPIO_1  = 36'hzzzzzzzz;

// LED OFF
assign HEX0 = 7'b1111111;
assign HEX1 = 7'b1111111;
assign HEX2 = 7'b1111111;
assign HEX3 = 7'b1111111;
assign HEX4 = 7'b1111111;
assign HEX5 = 7'b1111111;

// Генерация частот
// -----------------------------------------------------------------------------

wire locked;
wire clock_25;
wire clock_100;

de0pll unit_pll
(
    .clkin      (CLOCK_50),
    .m25        (clock_25),
    .m100       (clock_100),
    .locked     (locked)
);


// ПРОЦЕССОР
// ---------------------------------------------------------------------

wire [19:0] address;
reg  [ 7:0] in;
wire [ 7:0] out;
wire        we;

core U2
(
    .clock      (clock_25),
    .reset_n    (1'b1),
    .locked     (locked),
    .address    (address),
    .in         (in),
    .out        (out),
    .we         (we)
);

// ВИДЕОКАРТА
// ---------------------------------------------------------------------

wire [13:0] vcard_address;
wire [ 7:0] vcard_data;

vcard U1
(
    .clock          (clock_25),
    .r              (VGA_R),
    .g              (VGA_G),
    .b              (VGA_B),
    .hs             (VGA_HS),
    .vs             (VGA_VS),
    .cga            (1'b1),
    .cga_address    (vcard_address),
    .cga_data       (vcard_data),
    .txt_address    (txt_address),
    .txt_in         (txt_in)
);

// МОДУЛИ ПАМЯТИ
// ---------------------------------------------------------------------

// Общая память
m256k M0
(
    .clock      (clock_100),
    .a0         (address[17:0]),
    .q0         (m256k_in),
    .d0         (out),
    .w0         (m256k_we),
);

// CGA модуль
m16k M1
(
    .clock      (clock_100),
    .a0         (address[13:0]),
    .q0         (m16k_in),
    .d0         (out),
    .w0         (m16k_we),
    .a1         (vcard_address),
    .q1         (vcard_data)
);

// BIOS
m8k M2
(
    .clock      (clock_100),
    .a0         (address[12:0]),
    .q0         (m8k_in),
    .d0         (out),
    .w0         (m8k_we),
);

// РОУТЕР ПАМЯТИ
// ---------------------------------------------------------------------

wire [7:0] m8k_in;   reg m8k_we;
wire [7:0] m16k_in;  reg m16k_we;
wire [7:0] m256k_in; reg m256k_we;

always @(*) begin

    m16k_we  = 1'b0;
    m256k_we = 1'b0;
    m8k_we   = 1'b0;

    casex (address)

        20'b00xx_xxxxxxxx_xxxxxxxx: begin in = m256k_in; m256k_we = we; end // 00000 256K
        20'b1010_00xxxxxx_xxxxxxxx: begin in = m16k_in;  m16k_we  = we; end // A0000 16K
        20'b1111_111xxxxx_xxxxxxxx: begin in = m8k_in;   m8k_we   = we; end // FE000 8K
        default: in = 8'hFF;

    endcase

end

endmodule

`include "../vcard.v"
`include "../core.v"
