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
wire locked;
wire clock_25;
wire clock_100;

de0pll unit_pll
(
    .clkin     (CLOCK_50),
    .m25       (clock_25),
    .m100      (clock_100),
    .locked    (locked)
);

// ---------------------------------------------------------------------
// Маршрутизация памяти
// 256K Базовая
// 32K  BIOS
// 8K   TextMode
// 1K   DAC
// ---------------------------------------------------------------------

wire [31:0] address;
reg  [17:0] mm_address;
reg  [ 7:0] in;
wire [ 7:0] out;
wire        we;
reg         we_vga;
reg         we_membase;
reg         we_bios;
reg   [7:0] in_membase;
reg   [7:0] in_vga;
reg   [7:0] in_bios;

always @* begin

    we_membase  = 1'b0;
    we_vga      = 1'b0;
    we_bios     = 1'b0;
    in          = 8'hFF;
    mm_address  = address;

    casex (address)

        // 0..256K
        20'b00xx_xxxxxxxx_xxxxxxxx: begin we_membase = we; in = in_membase; end

        // VGA B8000-B9FFF 8K
        20'b1011_100xxxxx_xxxxxxxx: begin we_vga = we; in = in_vga; end

        // VGA A0000-AFFFF 64K
        20'b1010_xxxxxxxx_xxxxxxxx: case (videomode)

            2: begin

                in         = in_membase;
                we_membase = we;
                mm_address = {2'b11, address[15:0]};

            end

        endcase

        // BIOS F8000-FFFFF 32K
        20'b1111_1xxxxxxx_xxxxxxxx: begin we_bios = we; in = in_bios; end

    endcase

end

// 256k
membase membase_inst
(
    .clock      (clock_100),
    .address_a  (mm_address),
    .q_a        (in_membase),
    .data_a     (out),
    .wren_a     (we_membase),
    .address_b  (gfx_address),
    .q_b        (gfx_data)
);

// 32k
bios bios_inst
(
    .clock      (clock_100),
    .address_a  (address[14:0]),
    .q_a        (in_bios),
    .data_a     (out),
    .wren_a     (we_bios),
);

// 8k: Видеопамять и знакогенератор
font font_inst
(
    .clock      (clock_100),

    // Видеоадаптер
    .address_a  (vga_address),
    .q_a        (vga_data),

    // Процессор
    .address_b  (address[12:0]),
    .q_b        (in_vga),
    .data_b     (out),
    .wren_b     (we_vga),
);

// 1kb
dac dac_inst
(
    .clock      (clock_100),
    .address_a  (vga_dac_address),
    .q_a        (vga_dac_data),
    .address_b  (dac_address),
    .data_b     (dac_out),
    .wren_b     (dac_we),
);

// ---------------------------------------------------------------------
// Процессор 32х битный
// ---------------------------------------------------------------------

core cpu_inst
(
    // Тактовый генератор
    .clock          (clock_25),
    .reset_n        (locked & RESET_N),
    .locked         (1'b1),
    // Магистраль данных 8 битная
    .address        (address),
    .in             (in),
    .out            (out),
    .we             (we),

    // Порты
    .port_clk       (port_clk),
    .port           (port),
    .port_i         (port_i),
    .port_o         (port_o),
    .port_w         (port_w),

    // Прерывания
    .intr           (intr),
    .irq            (irq),
    .intl           (intl)
);

// ---------------------------------------------------------------------
// Управление портами
// ---------------------------------------------------------------------

wire        port_clk;
wire [15:0] port;
wire [ 7:0] port_i;
wire [ 7:0] port_o;
wire        port_w;
wire        intr;
wire        intl;
wire [ 7:0] irq;

pctl pctl_inst
(
    .reset_n        (locked & RESET_N),
    .clock          (clock_25),

    // Интерфейс
    .port_clk       (port_clk),
    .port           (port),
    .port_i         (port_i),
    .port_o         (port_o),
    .port_w         (port_w),

    // Видео
    .videomode      (videomode),
    .cursor         (cursor),
    .cursor_l       (cursor_l),
    .cursor_h       (cursor_h),
    .dac_out        (dac_out),
    .dac_address    (dac_address),
    .dac_we         (dac_we),

    // Клавиатура
    .ps2_data       (ps2_data),
    .ps2_hit        (ps2_hit),

    // SD-карта
    .sd_signal      (sd_signal),   // In   =1 Сообщение отослано на spi
    .sd_cmd         (sd_cmd),      // In      Команда
    .sd_din         (sd_din),      // Out     Принятое сообщение от карты
    .sd_out         (sd_out),      // In      Сообщение на отправку к карте
    .sd_busy        (sd_busy),     // Out  =1 Занято
    .sd_timeout     (sd_timeout),  // Out  =1 Таймаут

    // Прерывания
    .intr           (intr),
    .irq            (irq),
    .intl           (intl)
);

// ---------------------------------------------------------------------
// Модуль VGA
// ---------------------------------------------------------------------

wire [12:0] vga_address;
wire [ 7:0] vga_data;
wire [ 1:0] videomode;
wire [10:0] cursor;
wire [ 3:0] cursor_l;
wire [ 3:0] cursor_h;

wire [31:0] dac_out;
wire        dac_we;
wire [ 7:0] dac_address;
wire [17:0] gfx_address;
wire [ 7:0] gfx_data;
wire [ 7:0] vga_dac_address;
wire [31:0] vga_dac_data;

vga vga_inst
(
    .clock      (clock_25),
    .r          (VGA_R),
    .g          (VGA_G),
    .b          (VGA_B),
    .hs         (VGA_HS),
    .vs         (VGA_VS),
    .address    (vga_address),
    .data       (vga_data),
    .cursor     (cursor),
    .cursor_sl  (cursor_l),
    .cursor_sh  (cursor_h),
    .videomode  (videomode),

    // Видео
    .vga_address     (gfx_address),
    .vga_data        (gfx_data),
    .vga_dac_address (vga_dac_address),
    .vga_dac_data    (vga_dac_data),
);

// ---------------------------------------------------------------------
// Модуль SD
// ---------------------------------------------------------------------

assign SD_DATA[0] = 1'bZ;

wire [1:0]  sd_cmd;
wire [7:0]  sd_din;
wire [7:0]  sd_out;
wire        sd_signal;
wire        sd_busy;
wire        sd_timeout;

sd UnitSD
(
    // 25 Mhz
    .clock      (clock_25),

    // Физический интерфейс
    .SPI_CS     (SD_DATA[3]),   // Выбор чипа
    .SPI_SCLK   (SD_CLK),       // Тактовая частота
    .SPI_MISO   (SD_DATA[0]),   // Входящие данные
    .SPI_MOSI   (SD_CMD),       // Исходящие

    // Интерфейс
    .sd_signal  (sd_signal),   // In   =1 Сообщение отослано на spi
    .sd_cmd     (sd_cmd),      // In      Команда
    .sd_din     (sd_din),      // Out     Принятое сообщение от карты
    .sd_out     (sd_out),      // In      Сообщение на отправку к карте
    .sd_busy    (sd_busy),     // Out  =1 Занято
    .sd_timeout (sd_timeout)   // Out  =1 Таймаут
);

// ---------------------------------------------------------------------
// Клавиатура
// ---------------------------------------------------------------------

wire [7:0]  ps2_data;
wire        ps2_hit;

ps2 ps2_inst
(
    .clock      (clock_25),
    .ps_clock   (PS2_CLK),
    .ps_data    (PS2_DAT),
    .done       (ps2_hit),
    .data       (ps2_data)
);

endmodule

`include "../core.v"
`include "../vga.v"
`include "../pctl.v"
`include "../ps2.v"
`include "../sd.v"
