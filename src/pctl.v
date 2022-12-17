// verilator lint_off WIDTH
// verilator lint_off CASEINCOMPLETE

/**
 * Модуль необходим для управления портами ввода-вывода
 */

module pctl
(
    input   wire        reset_n,
    input   wire        clock,      // CPU HOST Clock

    // Управление
    input   wire        port_clk,
    input   wire [15:0] port,
    output  reg  [ 7:0] port_i,     // К процессору
    input   wire [ 7:0] port_o,     // От процессора
    input   wire        port_w,

    // Видеоадаптер
    output  reg  [ 1:0] videomode,
    output  reg  [10:0] cursor,
    output  reg  [31:0] dac_out,
    output  reg  [ 7:0] dac_address,
    output  reg         dac_we,
    output  reg  [ 4:0] cursor_l,
    output  reg  [ 4:0] cursor_h,

    // Клавиатура
    input   wire [ 7:0] ps2_data,
    input   wire        ps2_hit,

    // SD-карта
    output  reg         sd_signal,  // 0->1 Команда на позитивном фронте
    output  reg  [ 1:0] sd_cmd,     // ID команды
    input   wire [ 7:0] sd_din,     // Исходящие данные в процессор
    output  reg  [ 7:0] sd_out,     // Входящие данные из процессора
    input   wire        sd_busy,    // =1 Устройство занято
    input   wire        sd_timeout, // =1 Вышел таймаут

    // Прерывания
    output reg          intr,
    output reg   [ 7:0] irq,
    input  wire         intl
);

initial begin

    cursor  = 0;
    port_i      = 0;
    intr        = 0;
    irq         = 0;
    sd_signal   = 0;
    sd_cmd      = 0;
    sd_out      = 0;
    dac_we      = 0;
    dac_address = 0;
    dac_reg     = 0;
    dac_cursor  = 0;
    dac_out     = 0;

end

// Обработка прерываний
reg [15:0]  irq_mask            = 16'b0000_0000_0000_0000; // Маски
reg [15:0]  irq_pend            = 16'b0000_0000_0000_0000; // Запросы
reg [ 7:0]  vect_master         = 8'h08;
reg         eoi_master          = 1'b0;     // Ожидание обработки прерывания

reg [ 7:0]  dac_reg             = 1'b0;
reg [ 1:0]  dac_cursor          = 1'b0;
reg [ 7:0]  cga_reg             = 1'b0;

// Таймер
// https://wiki.osdev.org/Programmable_Interval_Timer#Read_Back_Command
reg [15:0]  pit_channel0        = 1'b0;
reg [15:0]  pit_cnt             = 1'b0;
reg         pit0_ff             = 1'b0;   // flip-flop регистр
reg [ 7:0]  pit_mode            = 1'b0;
reg [ 4:0]  pit_119mhz          = 1'b0;

// Клавиатура
reg [ 7:0]  keyb_data           = 8'h0;      // Выходные данные для порта
reg [ 7:0]  keyb_xt             = 8'h0;      // Сконвертированное AT -> XT
reg         keyb_counter        = 1'b0;
reg         keyb_counter_latch  = 1'b0;
reg         keyb_unpressed      = 1'b0;    // Признак "отжатой" клаваши
reg         keyb_intr           = 1'b0;
reg         keyb_intr_latch     = 1'b0;

/*
 * Обработка ввода-вывода
 * 60h,64h Клавиатура
 * 3D5h https://wiki.osdev.org/Text_Mode_Cursor
 */

always @(posedge clock) begin

    // По умолчанию ничего не писать
    dac_we      <= 1'b0;

    // Сигнал активируется только при записи в порт FEh
    sd_signal   <= 1'b0;

    // Приведение к начальным значениям
    if (reset_n == 0) begin

        videomode       <= 0; // 0-Тестовый, 2-Screen13
        vect_master     <= 8;
        pit0_ff         <= 0;
        dac_cursor      <= 0;
        irq_mask        <= 0;
        pit_channel0    <= 0;
        pit_mode        <= 4'b0110;
        cursor_l        <= 14;
        cursor_h        <= 15;

    end

    // Появился вызов прерывания с клавиатуры
    // -----------------------------------------------------------------

    if (keyb_intr_latch ^ keyb_intr) begin

        keyb_intr_latch <= keyb_intr;
        if (irq_mask[1] == 0) irq_pend[1] <= 1;

    end

    // Отсчет таймера 25mhz/21 ~ 1.190476 (оригинал 1.193182)
    // -----------------------------------------------------------------

    if (pit_119mhz == 20) begin
        pit_119mhz <= 0;

        // Проверить достижение триггера
        if (pit_cnt == pit_channel0) begin
            pit_cnt <= 1;
            if (irq_mask[0] == 0) irq_pend[0] <= 1;
        end else
            pit_cnt <= pit_cnt + 1;

    end
    else pit_119mhz <= pit_119mhz + 1;

    // При наличии PEND прерывания, выставить его к процессору и ожидать EOI
    // -----------------------------------------------------------------

    if (eoi_master == 0) begin

        // Убираем REQUEST
        if      (irq_pend[0]) begin irq_pend[0] <= 0; irq <= 0 + vect_master; end
        else if (irq_pend[1]) begin irq_pend[1] <= 0; irq <= 1 + vect_master; end

        // Наличие любого запроса прерывания
        if (|irq_pend[7:0]) begin eoi_master <= 1; intr <= ~intl; end

    end

    // Обработка портов
    // -----------------------------------------------------------------

    if (port_clk) begin

        if (port_w)
        case (port)

            // Сброс готовности Master-контроллера
            16'h20: if (port_o[5]) eoi_master <= 0;

            // Программирование PIT
            16'h40: if (pit_mode[2:1])
            begin

                pit_channel0 <= {port_o[7:0], pit_channel0[15:8]};
                pit0_ff      <= ~pit0_ff;

            end

            // Выбор режима работы PIT
            16'h43: pit_mode <= port_o;

            // Speaker
            16'h61: pit0_ff <= 0;

            // SD
            16'hFE: {sd_signal, sd_cmd} <= {1'b1, port_o[1:0]};
            16'hFF: sd_out <= port_o;

            // Программирование палитры
            16'h3C8: begin dac_reg <= port_o; dac_cursor <= 0; end

            // Запись данных по тетрадам RGB
            16'h3C9: begin

                case (dac_cursor)

                    0: begin dac_cursor <= 1; dac_out[23:16] <= {port_o[6:0], 2'b00}; dac_address <= dac_reg; end
                    1: begin dac_cursor <= 2; dac_out[ 15:8] <= {port_o[6:0], 2'b00}; dac_reg <= dac_reg + 1; end
                    2: begin dac_cursor <= 0; dac_out[  7:0] <= {port_o[6:0], 2'b00}; dac_we <= 1; end

                endcase

            end

            // Выбор регистра CGA/EGA
            16'h3D4: cga_reg <= port_o;

            // Запись в регистр
            16'h3D5: case (cga_reg)

                // Положение курсора на экране
                8'h0A: cursor_l[4:0]    <= port_o[4:0]; // START
                8'h0B: cursor_h[4:0]    <= port_o[4:0]; // END
                8'h0E: cursor[10:8]     <= port_o[2:0];
                8'h0F: cursor[ 7:0]     <= port_o;

            endcase

            // D0-режим символов(1=80 или 0=40)
            // D1-графический 320
            // D4-графический 640
            16'h3D8: case (port_o[1:0])

                2'b00,
                2'b01: videomode <= 0; // Text 80|40
                2'b10: videomode <= 1; // CGA
                2'b11: videomode <= 2; // VGA

            endcase

        endcase
        else
        case (port)

            16'h40: port_i <= pit_cnt[7:0];
            16'h60: port_i <= keyb_data;

            // Статус клавиатуры
            // Бит 0 - признак новых принятых данных с клавиатуры
            16'h64: begin

                port_i <= {7'h0, keyb_counter_latch ^ keyb_counter};
                keyb_counter_latch <= keyb_counter;

            end

            // SD
            16'hFE: port_i <= {sd_busy, sd_timeout, 6'h0};
            16'hFF: port_i <= sd_din;

            // https://frolov-lib.ru/books/bsp.old/v03/ch6.htm
            16'h3D4: port_i <= cga_reg;
            16'h3D5: case (cga_reg)

                8'h0A: port_i <= cursor_l;
                8'h0B: port_i <= cursor_h;
                8'h0E: port_i <= cursor[10:8];
                8'h0F: port_i <= cursor[ 7:0];

            endcase

        endcase

    end

end

// Трансляция скан-кода
always @(*) begin

    case (ps2_data)

        /* A   */ 8'h1C: keyb_xt = 8'h1E;
        /* B   */ 8'h32: keyb_xt = 8'h30;
        /* C   */ 8'h21: keyb_xt = 8'h2E;
        /* D   */ 8'h23: keyb_xt = 8'h20;
        /* E   */ 8'h24: keyb_xt = 8'h12;
        /* F   */ 8'h2B: keyb_xt = 8'h21;
        /* G   */ 8'h34: keyb_xt = 8'h22;
        /* H   */ 8'h33: keyb_xt = 8'h23;
        /* I   */ 8'h43: keyb_xt = 8'h17;
        /* J   */ 8'h3B: keyb_xt = 8'h24;
        /* K   */ 8'h42: keyb_xt = 8'h25;
        /* L   */ 8'h4B: keyb_xt = 8'h26;
        /* M   */ 8'h3A: keyb_xt = 8'h32;
        /* N   */ 8'h31: keyb_xt = 8'h31;
        /* O   */ 8'h44: keyb_xt = 8'h18;
        /* P   */ 8'h4D: keyb_xt = 8'h19;
        /* Q   */ 8'h15: keyb_xt = 8'h10;
        /* R   */ 8'h2D: keyb_xt = 8'h13;
        /* S   */ 8'h1B: keyb_xt = 8'h1F;
        /* T   */ 8'h2C: keyb_xt = 8'h14;
        /* U   */ 8'h3C: keyb_xt = 8'h16;
        /* V   */ 8'h2A: keyb_xt = 8'h2F;
        /* W   */ 8'h1D: keyb_xt = 8'h11;
        /* X   */ 8'h22: keyb_xt = 8'h2D;
        /* Y   */ 8'h35: keyb_xt = 8'h15;
        /* Z   */ 8'h1A: keyb_xt = 8'h2C;
        /* 0   */ 8'h45: keyb_xt = 8'h0B;
        /* 1   */ 8'h16: keyb_xt = 8'h02;
        /* 2   */ 8'h1E: keyb_xt = 8'h03;
        /* 3   */ 8'h26: keyb_xt = 8'h04;
        /* 4   */ 8'h25: keyb_xt = 8'h05;
        /* 5   */ 8'h2E: keyb_xt = 8'h06;
        /* 6   */ 8'h36: keyb_xt = 8'h07;
        /* 7   */ 8'h3D: keyb_xt = 8'h08;
        /* 8   */ 8'h3E: keyb_xt = 8'h09;
        /* 9   */ 8'h46: keyb_xt = 8'h0A;
        /* ~   */ 8'h0E: keyb_xt = 8'h29;
        /* -   */ 8'h4E: keyb_xt = 8'h0C;
        /* =   */ 8'h55: keyb_xt = 8'h0D;
        /* \   */ 8'h5D: keyb_xt = 8'h2B;
        /* [   */ 8'h54: keyb_xt = 8'h1A;
        /* ]   */ 8'h5B: keyb_xt = 8'h1B;
        /* ;   */ 8'h4C: keyb_xt = 8'h27;
        /* '   */ 8'h52: keyb_xt = 8'h28;
        /* ,   */ 8'h41: keyb_xt = 8'h33;
        /* .   */ 8'h49: keyb_xt = 8'h34;
        /* /   */ 8'h4A: keyb_xt = 8'h35;
        /* BS  */ 8'h66: keyb_xt = 8'h0E;
        /* SPC */ 8'h29: keyb_xt = 8'h39;
        /* TAB */ 8'h0D: keyb_xt = 8'h0F;

        /* Кнопки модификации */
        /* CAP */ 8'h58: keyb_xt = 8'h3A; /* CAPS LOCK */
        /* LSH */ 8'h12: keyb_xt = 8'h2A; /* LEFT SHIFT */
        /* LCT */ 8'h14: keyb_xt = 8'h1D; /* LEFT CTRL */
        /* LAT */ 8'h11: keyb_xt = 8'h38; /* LEFT ALT */
        /* LWI */ 8'h1F: keyb_xt = 8'h5B; /* LEFT WIN */
        /* RSH */ 8'h59: keyb_xt = 8'h36; /* RIGHT SHIFT */
        /* RWI */ 8'h27: keyb_xt = 8'h5C; /* RIGHT WIN */
        /* MNU */ 8'h2F: keyb_xt = 8'h5D; /* MENU */
        /* ENT */ 8'h5A: keyb_xt = 8'h1C; /* ENTER */

        /* Функциональная панель */
        /* ESC */ 8'h76: keyb_xt = 8'h01;
        /* F1  */ 8'h05: keyb_xt = 8'h3B;
        /* F2  */ 8'h06: keyb_xt = 8'h3C;
        /* F3  */ 8'h04: keyb_xt = 8'h3D;
        /* F4  */ 8'h0C: keyb_xt = 8'h3E;
        /* F5  */ 8'h03: keyb_xt = 8'h3F;
        /* F6  */ 8'h0B: keyb_xt = 8'h40;
        /* F7  */ 8'h83: keyb_xt = 8'h41;
        /* F8  */ 8'h0A: keyb_xt = 8'h42;
        /* F9  */ 8'h01: keyb_xt = 8'h43;
        /* F10 */ 8'h09: keyb_xt = 8'h44;
        /* F11 */ 8'h78: keyb_xt = 8'h57;
        /* F12 */ 8'h07: keyb_xt = 8'h58;
        /* SCL */ 8'h7E: keyb_xt = 8'h46;

        /* Цифровая клавиатура */
        /* NUM */ 8'h77: keyb_xt = 8'h45;
        /* *   */ 8'h7C: keyb_xt = 8'h37;
        /* -   */ 8'h7B: keyb_xt = 8'h4A;
        /* +   */ 8'h79: keyb_xt = 8'h4E;
        /* .   */ 8'h71: keyb_xt = 8'h53;
        /* 0   */ 8'h70: keyb_xt = 8'h52;
        /* 1   */ 8'h69: keyb_xt = 8'h4F;
        /* 2   */ 8'h72: keyb_xt = 8'h50;
        /* 3   */ 8'h7A: keyb_xt = 8'h51;
        /* 4   */ 8'h6B: keyb_xt = 8'h4B;
        /* 5   */ 8'h73: keyb_xt = 8'h4C;
        /* 6   */ 8'h74: keyb_xt = 8'h4D;
        /* 7   */ 8'h6C: keyb_xt = 8'h47;
        /* 8   */ 8'h75: keyb_xt = 8'h48;
        /* 9   */ 8'h7D: keyb_xt = 8'h49;

        /* E0, E1, ... */
        default: keyb_xt = ps2_data;

    endcase

end

// Принятие данных из PS/2
always @(posedge clock) begin

    // Новые данные присутствуют. Асинхронный прием.
    if (ps2_hit) begin

        // Признак "отжатая клавиша"
        if (ps2_data == 8'hF0) begin
            keyb_unpressed  <= 1'b1;
        end
        // Если предыдущий скан-код - это признак "отжатия" клавиши, то записать 1 в 7-й бит */
        else begin

            keyb_unpressed  <= 1'b0;
            keyb_data       <= keyb_unpressed ? {1'b1, keyb_xt[6:0]} : keyb_xt;
            keyb_counter    <= ~keyb_counter_latch;
            keyb_intr       <= ~keyb_intr_latch;

        end

    end

end

endmodule
