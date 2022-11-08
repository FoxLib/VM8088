/* >> HELLO WORLD << */

module core
(
    input               clock,
    input               reset_n,
    input               locked,
    output      [19:0]  address,
    input       [ 7:0]  in,
    output reg  [ 7:0]  out,
    output reg          we
);

// ---------------------------------------------------------------------
initial begin we = 1'b0; out = 8'h00; end
assign  address = bus ? {seg, 4'h0} + ea : {cs, 4'h0} + ip;
// ---------------------------------------------------------------------
reg [15:0]  ax          = 16'h12AA;
reg [15:0]  cx          = 16'h0013;
reg [15:0]  dx          = 16'h0014;
reg [15:0]  bx          = 16'h0105;
reg [15:0]  sp          = 16'h0167;
reg [15:0]  bp          = 16'h1008;
reg [15:0]  si          = 16'h2009;
reg [15:0]  di          = 16'h030A;
// ---------------------------------------------------------------------
reg [15:0]  es          = 16'h0000;
reg [15:0]  cs          = 16'h0000;
reg [15:0]  ss          = 16'h0000;
reg [15:0]  ds          = 16'h0000;
// ---------------------------------------------------------------------
reg         bus         = 1'b0;
reg [15:0]  seg         = 16'h0000;         // Текущий выбранный сегмент
reg [15:0]  ea          = 16'h0000;         // Эффективный адрес
reg [ 5:0]  phi         = 1'b0;             // Фаза выполнения
reg [ 5:0]  phi_next    = 1'b0;             // Фаза выполнения
reg [ 3:0]  fn          = 1'b0;             // Субфаза phi
reg [ 2:0]  alu         = 3'h0;
reg [15:0]  op1         = 16'h0000;
reg [15:0]  op2         = 16'h0000;
reg [15:0]  wb          = 16'h0000;
reg [ 7:0]  opcode      = 8'h00;             // Сохраненный опкод
reg [ 7:0]  modrm       = 8'h00;
reg         size        = 1'b0;
reg         dir         = 1'b0;
// ---------------------------------------------------------------------
reg [15:0]  ip          = 16'h0000;
reg [11:0]  flags       = 12'b0000_0000_0010;
//                            ODIT SZ A  P C
// ---------------------------------------------------------------------
reg         o_seg       = 1'b0;
reg         o_seg_      = 1'b0;
reg [1:0]   o_rep       = 2'h0;
reg [1:0]   o_rep_      = 2'h0;
// ---------------------------------------------------------------------
reg [1:0]   src1        = 2'b00;
reg [1:0]   src2        = 2'b00;
reg [2:0]   regn        = 3'b000; // Данные из номера регистра
// ---------------------------------------------------------------------

localparam

    PREPARE         = 0,
    MODRM           = 1,
    MODRM_DISP8     = 2,
    MODRM_DISP16    = 3,
    MODRM_DISP16H   = 4,
    MODRM_READOP    = 5,
    MODRM_READOPH   = 6,
    MODRM_WB        = 7,
    MODRM_WB_MEM    = 8,
    MODRM_WB_END    = 9,
    EXEC            = 10;

localparam

    SRC_I20 = 2'b00, SRC_I53 = 2'b01,
    SRC_REG = 2'b10;

localparam

    ALU_ADD = 3'h0, ALU_OR  = 3'h1,
    ALU_ADC = 3'h2, ALU_SBB = 3'h3,
    ALU_AND = 3'h4, ALU_SUB = 3'h5,
    ALU_XOR = 3'h6, ALU_CMP = 3'h7;

// Выбор источника регистров
// ---------------------------------------------------------------------
wire [ 2:0] r1n = src1 == SRC_I20 ? in[2:0] :
                  src1 == SRC_I53 ? in[5:3] : regn;
wire [ 2:0] r2n = src2 == SRC_I20 ? in[2:0] :
                  src2 == SRC_I53 ? in[5:3] : regn;

wire [15:0] r1 = // Первый регистровый источник
    r1n == 3'h0 ? (size ? ax : ax[ 7:0]) :
    r1n == 3'h1 ? (size ? cx : cx[ 7:0]) :
    r1n == 3'h2 ? (size ? dx : dx[ 7:0]) :
    r1n == 3'h3 ? (size ? bx : bx[ 7:0]) :
    r1n == 3'h4 ? (size ? sp : ax[15:8]) :
    r1n == 3'h5 ? (size ? bp : cx[15:8]) :
    r1n == 3'h6 ? (size ? si : dx[15:8]) :
                  (size ? di : bx[15:8]);

wire [15:0] r2 = // Второй регистровый источник
    r2n == 3'h0 ? (size ? ax : ax[ 7:0]) :
    r2n == 3'h1 ? (size ? cx : cx[ 7:0]) :
    r2n == 3'h2 ? (size ? dx : dx[ 7:0]) :
    r2n == 3'h3 ? (size ? bx : bx[ 7:0]) :
    r2n == 3'h4 ? (size ? sp : ax[15:8]) :
    r2n == 3'h5 ? (size ? bp : cx[15:8]) :
    r2n == 3'h6 ? (size ? si : dx[15:8]) :
                  (size ? di : bx[15:8]);

// Исполнение инструкции
// ---------------------------------------------------------------------

always @(posedge clock)
// Сброс процессора
if (reset_n == 1'b0) begin

    ip      <= 16'hFFF0;
    cs      <= 16'hF000;
    phi     <= 1'b0;
    o_seg_  <= 1'b0;
    o_rep_  <= 2'h0;

end
// Операции процессора разрешены
else if (locked) case (phi)

    // ~=~=~= Считывание префиксов и опкода ~=~=~=
    PREPARE: begin

        // Инициализация регистров управления
        we          <= 1'b0;
        fn          <= 1'b0;
        src1        <= SRC_I20; // Источник op1 modrm
        src2        <= SRC_I53; // Источник op2 modrm
        size        <= in[0];
        dir         <= in[1];
        regn        <= in[2:0];
        alu         <= in[5:3];
        phi_next    <= PREPARE;
        ip          <= ip + 1'b1;

        case (in)

        // Префиксы
        8'h26: begin o_seg_ <= 1'b1; seg <= es; end
        8'h2E: begin o_seg_ <= 1'b1; seg <= cs; end
        8'h36: begin o_seg_ <= 1'b1; seg <= ss; end
        8'h3E: begin o_seg_ <= 1'b1; seg <= ds; end
        8'hF2: begin o_rep_ <= {1'b1, in[0]}; end

        // Не реализованные префиксы, не нужные никому
        8'hF0, 8'h64, 8'h65, 8'h66, 8'h67: begin end

        // Опкоды, первый такт
        default: begin

            // Защелкивание префиксов и опкода на будущее
            opcode <= in;
            o_seg  <= o_seg_; o_seg_ <= 1'h0;
            o_rep  <= o_rep_; o_rep_ <= 2'h0;

            if (!o_seg_) seg <= ds;

            casex (in)

            // Базовый АЛУ
            8'b00xx_x0xx: begin phi <= MODRM; end

            endcase

        end
        endcase

    end

    // ~=~=~= Раскодирование байта ModRM ~=~=~=
    MODRM: begin

        ip      <= ip + 1;
        modrm   <= in;

        // Выбор операндов
        op1     <= dir ? r2 : r1;
        op2     <= dir ? r1 : r2;

        // Эффективный адрес
        case (in[2:0])
        3'b000: ea <= bx + si;
        3'b001: ea <= bx + di;
        3'b010: ea <= bp + si;
        3'b011: ea <= bp + di;
        3'b100: ea <= si;
        3'b101: ea <= di;
        3'b110: ea <= ^in[7:6] ? bp : 1'b0;
        3'b111: ea <= bx;
        endcase

        // Распределение
        case (in[7:6])
        2'b00: begin

          if (in[2:0] == 3'b110) phi <= MODRM_DISP16;
          else begin phi <= MODRM_READOP; bus <= 1'b1; end

        end
        2'b01: phi <= MODRM_DISP8;
        2'b10: phi <= MODRM_DISP16;
        2'b11: phi <= EXEC;
        endcase

        // Сегмент SS: ставится если есть BP
        if (!o_seg && (in[2:1] == 2'b01 || (^in[7:6] && in[2:0] == 3'b110)))
            seg <= ss;

    end

    // Чтение D8
    MODRM_DISP8: begin

        ip  <= ip + 1'b1;
        ea  <= ea + {{8{in[7]}}, in};
        phi <= MODRM_READOP;
        bus <= 1'b1;

    end

    // Чтение D16: LOW
    MODRM_DISP16: begin

        ip  <= ip + 1'b1;
        ea  <= ea + in;
        phi <= MODRM_DISP16H;

    end

    // Чтение D16: HIGH
    MODRM_DISP16H: begin

        ip  <= ip + 1'b1;
        ea  <= ea + {in, 8'h00};
        phi <= MODRM_READOP;
        bus <= 1'b1;

    end

    // Чтение операнда: LOW
    MODRM_READOP: begin

        if (dir) op2 <= in; else op1 <= in;
        if (size) begin ea <= ea + 1'b1; phi <= MODRM_READOPH; end else phi <= EXEC;

    end

    // Чтение операнда: HIGH
    MODRM_READOPH: begin

        if (dir) op2[15:8] <= in; else op1[15:8] <= in;

        ea  <= ea - 1'b1;
        phi <= EXEC;

    end

    // Запись результата в память или регистры
    MODRM_WB: begin

        // Проверка на запись в регистр
        if (dir || modrm[7:6] == 2'b11) begin

            case (dir ? modrm[5:3] : modrm[2:0])
            3'b000: if (size) ax[15:0] <= wb; else ax[ 7:0] <= wb[7:0];
            3'b001: if (size) cx[15:0] <= wb; else cx[ 7:0] <= wb[7:0];
            3'b010: if (size) dx[15:0] <= wb; else dx[ 7:0] <= wb[7:0];
            3'b011: if (size) bx[15:0] <= wb; else bx[ 7:0] <= wb[7:0];
            3'b100: if (size) sp[15:0] <= wb; else ax[15:8] <= wb[7:0];
            3'b101: if (size) bp[15:0] <= wb; else cx[15:8] <= wb[7:0];
            3'b110: if (size) si[15:0] <= wb; else dx[15:8] <= wb[7:0];
            3'b111: if (size) di[15:0] <= wb; else bx[15:8] <= wb[7:0];
            endcase

            phi <= phi_next;
            bus <= 1'b0;

        end
        // LO-BYTE
        else begin

            phi <= size ? MODRM_WB_MEM : MODRM_WB_END;
            out <= wb[7:0];
            we  <= 1'b1;
            bus <= 1'b1;

        end

    end

    // HI-BYTE (Запись старшего байта)
    MODRM_WB_MEM: begin

        phi <= MODRM_WB_END;
        out <= wb[15:8];
        ea  <= ea + 1;

    end

    // Завершение записи в память
    MODRM_WB_END: begin

        phi <= phi_next;
        bus <= 1'b0;
        we  <= 1'b0;

    end

    // ~=~=~= Исполнение инструкции ~=~=~=
    EXEC: casex (opcode)

        // АЛУ в 00-3F
        8'b00xx_x0xx: begin

            phi   <= (alu == ALU_CMP ? PREPARE : MODRM_WB);
            bus   <= (alu == ALU_CMP ? 1'b0 : bus);
            wb    <= ar;
            flags <= af;

        end

    endcase

endcase

// ~=~=~= ЦЕНТРАЛЬНОЕ АРИФМЕТИКО-ЛОГИЧЕСКОЕ УСТРОЙСТВО =~=~=~

wire [3:0] ntop     = size ? 15 : 7;
wire       i_add    =  (alu == ALU_ADD || alu == ALU_ADC);
wire       i_arith  = !(alu == ALU_OR  || alu == ALU_XOR || alu == ALU_AND);

// Все флаги, которые участвуют в вычислениях (OSZAPC)
wire r_over     = (op1[ntop] ^ op2[ntop] ^ i_add) & (op1[ntop] ^ ar[ntop]);
wire r_sign     = ar[ntop];
wire r_zero     = (size ? ar[15:0] : ar[7:0]) == 1'b0;
wire r_aux      = op1[4] ^ op2[4] ^ ar[4];
wire r_parity   = ~^ar[7:0];
wire r_carry    = ar[ntop + 1];

// Вычисление результа
wire [16:0] ar =
    alu == ALU_ADD ? op1 + op2 :
    alu == ALU_OR  ? op1 | op2 :
    alu == ALU_ADC ? op1 + op2 + flags[0] :
    alu == ALU_SBB ? op1 - op2 - flags[0] :
    alu == ALU_AND ? op1 & op2 :
    alu == ALU_XOR ? op1 ^ op2 :
                     op1 - op2; // SUB, CMP

// Вычисление флагов
wire [11:0] af = {
    r_over & i_arith, flags[10:9], r_sign,   r_zero, 1'b0,     // OSZ
    r_aux  & i_arith, 1'b0,        r_parity, 1'b1,   r_carry}; // APC


endmodule
