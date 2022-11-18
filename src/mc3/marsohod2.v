module marsohod2
(
    input   wire        clk,
    output  wire [3:0]  led,
    input   wire [1:0]  keys,
    output  wire        adc_clock_20mhz,
    input   wire [7:0]  adc_input,
    output  wire        sdram_clock,
    output  wire [11:0] sdram_addr,
    output  wire [1:0]  sdram_bank,
    inout   wire [15:0] sdram_dq,
    output  wire        sdram_ldqm,
    output  wire        sdram_udqm,
    output  wire        sdram_ras,
    output  wire        sdram_cas,
    output  wire        sdram_we,
    output  wire [4:0]  vga_r,
    output  wire [5:0]  vga_g,
    output  wire [4:0]  vga_b,
    output  wire        vga_hs,
    output  wire        vga_vs,
    input   wire        ftdi_rx,
    output  wire        ftdi_tx,
    inout   wire [1:0]  usb0,
    inout   wire [1:0]  usb1,
    output  wire        sound_left,
    output  wire        sound_right,
    inout   wire        ps2_keyb_clk,
    inout   wire        ps2_keyb_dat,
    inout   wire        ps2_mouse_clk,
    inout   wire        ps2_mouse_dat
);

// Генерация частот
// ---------------------------------------------------------------------

wire locked;
wire clock_25;
wire clock_100;

pll unit_pll
(
    .clk       (clk),
    .m25       (clock_25),
    .m100      (clock_100),
    .locked    (locked)
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

wire [13:0] vcard_address; wire [ 7:0] vcard_data;
wire [12:0] vtext_address; wire [ 7:0] vtext_data;

vcard U1
(
    .clock          (clock_25),
    .r              (vga_r[4:1]),
    .g              (vga_g[5:2]),
    .b              (vga_b[4:1]),
    .hs             (vga_hs),
    .vs             (vga_vs),
    .cga            (1'b0),
    .txt_address    (vtext_address),
    .txt_data       (vtext_data),
);

// БЛОКИ ПАМЯТИ 32(RAM)+ 8(VCARD) + 4(BIOS) = 44K
// ---------------------------------------------------------------------

m32k M1
(
    .clock      (clock_100),
    .address_a  (address[14:0]),
    .q_a        (m32k_in),
    .data_a     (out),
    .wren_a     (m32k_we)
);

m8k M2
(
    .clock      (clock_100),
    .address_a  (address[12:0]),
    .q_a        (m8k_in),
    .data_a     (out),
    .wren_a     (m8k_we),
    .address_b  (vtext_address),
    .q_b        (vtext_data)
);

m4k M3
(
    .clock      (clock_100),
    .address_a  (address[11:0]),
    .q_a        (m4k_in),
    .data_a     (out),
    .wren_a     (m4k_we)
);

// РОУТЕР ПАМЯТИ
// ---------------------------------------------------------------------

wire [7:0] m32k_in; reg m16k_we;
wire [7:0] m8k_in;  reg m8k_we;
wire [7:0] m4k_in;  reg m4k_we;

always @(*) begin

    m32k_we = 1'b0;
    m8k_we  = 1'b0;
    m8k_we  = 1'b0;

    casex (address)

        20'b0000_0xxxxxxx_xxxxxxxx: begin in = m32k_in; m32k_we = we; end // 00000 DATA 32K
        20'b1011_10xxxxxx_xxxxxxxx: begin in = m8k_in;  m8k_we  = we; end // B8000 TEXT 8k
        20'b1111_1111xxxx_xxxxxxxx: begin in = m4k_in;  m4k_we  = we; end // FF000 BIOS 4k
        default: in = 8'hFF;

    endcase

end

endmodule

`include "../vcard.v"
`include "../core.v"
