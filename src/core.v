/* verilator lint_off WIDTH */
/* verilator lint_off CASEX */
/* verilator lint_off CASEINCOMPLETE */

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
reg [15:0]  cx          = 16'h0313;
reg [15:0]  dx          = 16'h5014;
reg [15:0]  bx          = 16'h0105;
reg [15:0]  sp          = 16'h0167;
reg [15:0]  bp          = 16'h1008;
reg [15:0]  si          = 16'h2009;
reg [15:0]  di          = 16'h030A;
// ---------------------------------------------------------------------
reg [15:0]  es          = 16'h0402;
reg [15:0]  cs          = 16'h0000;
reg [15:0]  ss          = 16'h0001;
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
reg [ 2:0]  pcnt        = 1'b0;             // Кол-во префиксов
reg [ 7:0]  opcode      = 8'h00;            // Сохраненный опкод
reg [ 7:0]  modrm       = 8'h00;
reg         size        = 1'b0;
reg         dir         = 1'b0;
// ---------------------------------------------------------------------
reg [15:0]  ip          = 16'h0000;
reg [15:0]  ipstart     = 16'h0000;         // Где начало инструкции
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
    EXEC            = 10,
    PUSH            = 11,
    PUSH2           = 12,
    PUSH3           = 13,
    POP             = 14,
    POP2            = 15,
    POP3            = 16;

localparam

    SRC_I20 = 2'b00, SRC_I53 = 2'b01,
    SRC_REG = 2'b10;

localparam

    ALU_ADD = 3'h0, ALU_OR  = 3'h1,
    ALU_ADC = 3'h2, ALU_SBB = 3'h3,
    ALU_AND = 3'h4, ALU_SUB = 3'h5,
    ALU_XOR = 3'h6, ALU_CMP = 3'h7;

localparam

    CF = 0, PF = 2, AF =  4, ZF =  6, SF = 7,
    TF = 8, IF = 9, DF = 10, OF = 11;

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
    pcnt    <= 3'b0;

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
        8'h26: begin o_seg_ <= 1'b1; seg <= es; pcnt <= pcnt + 1; end
        8'h2E: begin o_seg_ <= 1'b1; seg <= cs; pcnt <= pcnt + 1; end
        8'h36: begin o_seg_ <= 1'b1; seg <= ss; pcnt <= pcnt + 1; end
        8'h3E: begin o_seg_ <= 1'b1; seg <= ds; pcnt <= pcnt + 1; end
        8'hF2: begin o_rep_ <= {1'b1, in[0]};   pcnt <= pcnt + 1; end

        // Не реализованные префиксы, не нужные никому
        8'hF0, 8'h64, 8'h65, 8'h66, 8'h67: begin  pcnt <= pcnt + 1; end

        // Опкоды, первый такт
        default: begin

            phi     <= EXEC;
            opcode  <= in;
            ipstart <= ip - pcnt;
            pcnt    <= 0;

            // Защелкивание префиксов и опкода на будущее
            o_seg <= o_seg_; o_seg_ <= 1'h0;
            o_rep <= o_rep_; o_rep_ <= 2'h0;
            if (!o_seg_) seg <= ds;

            casex (in)

                // CLC, STC; CLI, STI; CLD, STD; CMC
                8'b1111_100x: begin flags[CF] <= in[0]; phi <= PREPARE; end
                8'b1111_101x: begin flags[IF] <= in[0]; phi <= PREPARE; end
                8'b1111_110x: begin flags[DF] <= in[0]; phi <= PREPARE; end
                8'b1111_0101: begin flags[CF] <= ~flags[CF]; phi <= PREPARE; end

                // NOP, FWAIT; HLT
                8'b1001_0000,
                8'b1001_1011: begin phi <= PREPARE; end
                8'b1111_0100: begin phi <= PREPARE; ip <= ip; end

                // CBW, CWD, SALC
                8'b1001_1000: begin phi <= PREPARE; ax[15:8] <= {8{ax[7]}}; end
                8'b1001_1001: begin phi <= PREPARE; dx <= {16{ax[15]}}; end
                8'b1101_0110: begin phi <= PREPARE; ax[7:0] <= {8{flags[CF]}}; end

                // <ALU> modrm
                8'b00xx_x0xx: begin phi <= MODRM; end

                // <ALU> mrm, i
                8'b1000_00xx: begin dir <= 1'b0; phi <= MODRM; end

                // PUSH es, cs, ss, cs
                8'b000x_x110: begin

                    phi <= PUSH;

                    case (in[4:3])
                    2'b00: wb <= es; 2'b01: wb <= cs;
                    2'b10: wb <= ss; 2'b11: wb <= ds;
                    endcase

                end

                // POP seg; POP r; POPF
                8'b000x_x111,
                8'b0101_1xxx,
                8'b1001_1101: begin phi <= POP; phi_next <= EXEC; end

                // PUSH r
                8'b0101_0xxx: begin size <= 1'b1; src1 <= SRC_REG; end

                // TEST modrm
                8'b1000_010x: begin phi <= MODRM; alu <= ALU_AND; end

                // PUSHF
                8'b1001_1100: begin wb <= flags | 2'b10; phi <= PUSH; phi_next <= PREPARE; end

                // SAHF
                8'b1001_1110: begin flags[7:0] <= ax[15:8]; phi <= PREPARE; end

                // LAHF
                8'b1001_1111: begin ax[15:8] <= flags[7:0]; phi <= PREPARE; end

                // MOV r, i
                8'b1011_xxxx: begin size <= in[3]; end

                // MOV mrm
                8'b1000_10xx: begin phi <= MODRM; end

                // INC|DEC r16; XCHG a, r
                8'b0100_xxxx,
                8'b1001_0xxx: begin

                    size <= 1'b1;
                    src1 <= SRC_REG;
                    alu  <= in[3] ? ALU_SUB : ALU_ADD;

                end

                // Jccc short
                8'b0111_xxxx: // Пропуск, если условие не сработало
                if (branch[ in[3:1] ] == in[0]) begin

                    phi <= PREPARE;
                    ip  <= ip + 2;

                end

            endcase

        end
        endcase

    end

    // ~=~=~= Исполнение инструкции ~=~=~=
    EXEC: casex (opcode)

        // #00-3F АЛУ modrm
        8'b00xx_x0xx: begin

            phi   <= (alu == ALU_CMP ? PREPARE : MODRM_WB);
            bus   <= (alu == ALU_CMP ? 1'b0 : bus);
            wb    <= ar;
            flags <= af;

        end

        // #00-3F АЛУ аккумулятор
        8'b00xx_x10x: case (fn)

            // 8 BIT
            0: begin

                ip  <= ip + 1;
                fn  <= size ? 1 : 2;
                op1 <= ax;
                op2 <= in;

            end

            // 16 BIT
            1: begin

                ip <= ip + 1;
                fn <= 2;
                op2[15:8] <= in;

            end

            // Запись результата
            2: begin

                phi     <= (alu == ALU_CMP ? PREPARE : MODRM_WB);
                dir     <= 1'b1;
                wb      <= ar;
                flags   <= af;

                modrm[5:3] <= 3'b0;

            end

        endcase

        // #07,#0F,#16,#1F POP seg
        8'b000x_x111: begin

            phi <= PREPARE;

            case (opcode[4:3])
            2'b00: es <= wb;
            2'b01: cs <= wb;
            2'b10: ss <= wb;
            2'b11: ds <= wb;
            endcase

        end

        // #40-4F INC/DEC
        8'b0100_xxxx: case (fn)

            // Установка операндов
            0: begin

                fn  <= 1;
                op1 <= r1;
                op2 <= 1'b1;

            end

            // Запись результата
            1: begin

                phi     <= MODRM_WB;
                dir     <= 1'b1;
                wb      <= ar;
                flags   <= {af[11:1], flags[CF]};

                modrm[5:3] <= regn;

            end

        endcase

        // #50-57 PUSH r
        8'b0101_0xxx: begin wb <= r1; phi <= PUSH; end

        // #58-5F POP r
        8'b0101_1xxx: begin

            phi         <= MODRM_WB;
            phi_next    <= PREPARE;
            dir         <= 1'b1;
            size        <= 1'b1;
            modrm[5:3]  <= opcode[2:0];

        end

        // #68,6A PUSH i16, i8
        8'b0110_10x0: case (fn)

            // PUSH i8
            0: begin

                fn <= 1;
                ip <= ip + 1;
                wb <= opcode[1] ? {{8{in[7]}}, in} : in;

                if (opcode[1]) phi <= PUSH;

            end

            // PUSH i16
            1: begin

                fn <= 2;
                ip <= ip + 1;
                phi <= PUSH;
                wb[15:8] <= in;

            end

        endcase

        // #80-83 ALU modrm
        8'b1000_00xx: case (fn)

            // Обнуление BUS
            // Читать младший байт
            0: begin

                if (bus == 1'b0) begin

                    fn  <= 1;
                    bus <= 1'b0;
                    op2 <= opcode[1:0] == 2'b11 ? {{8{in[7]}}, in} : in;
                    fn  <= size ? 1 : 2;
                    ip  <= ip + 1'b1;

                end

                bus <= 1'b0;
                alu <= modrm[5:3];

            end

            // Читать старший байт
            1: begin fn <= 2; op2[15:8] <= in; ip <= ip + 1'b1; end

            // Вычислить и записать результат
            2: begin

                phi   <= (alu == ALU_CMP ? PREPARE : MODRM_WB);
                bus   <= (alu != ALU_CMP);
                wb    <= ar;
                flags <= af;

            end

        endcase

        // #84-85 TEST rmr
        8'b1000_010x: begin phi <= PREPARE; flags <= af; bus <= 1'b0; end

        // #88-8B MOV mrm
        8'b1000_10xx: begin phi <= MODRM_WB; wb <= op2; end

        // #90-97 XCHG a, r
        8'b1001_0xxx: begin

            phi <= MODRM_WB;
            ax  <= r1;
            dir <= 1'b1;
            wb  <= ax;
            modrm[5:3] <= regn;

        end

        // #9D POPF
        8'b1001_1101: begin flags <= wb | 2'b10; phi <= PREPARE; end

        // #B0-BF MOV r, imm
        8'b1011_xxxx: case (fn)

            // Младший байт
            0: begin

                phi <= size ? EXEC : MODRM_WB;
                fn  <= 1;
                dir <= 1'b1;
                wb  <= in;
                ip  <= ip + 1'b1;

                modrm[5:3] <= opcode[2:0];

            end

            // Старший байт
            1: begin

                phi <= MODRM_WB;
                ip  <= ip + 1'b1;
                wb[15:8] <= in;

            end

        endcase

        // #EB, #70-7F Jccc, JMP short
        8'b1110_1011,
        8'b0111_xxxx: begin phi <= PREPARE; ip <= ip + {{8{in[7]}}, in} + 1'b1; end

    endcase

    // ~=~=~= Раскодирование байта ModRM ~=~=~=
    MODRM: begin

        ip    <= ip + 1;
        modrm <= in;

        // Выбор операндов
        op1   <= dir ? r2 : r1;
        op2   <= dir ? r1 : r2;

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

          if (in[2:0] == 3'b110)
               begin phi <= MODRM_DISP16; end
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

        phi <= size ? MODRM_READOPH : EXEC;

        if (dir) op2 <= in; else op1 <= in;
        if (size) ea <= ea + 1'b1;

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

    // ~=~=~= Процедуры ~=~=~=

    // Запись значения в стек
    PUSH: begin

        phi <= PUSH2;
        seg <= ss;
        ea  <= sp - 1'b1;
        sp  <= sp - 1'b1;
        we  <= 1'b1;
        bus <= 1'b1;
        out <= wb[15:8];

    end

    // Запись младшего байта
    PUSH2: begin

        phi <= PUSH3;
        ea  <= sp - 1'b1;
        sp  <= sp - 1'b1;
        out <= wb[7:0];

    end

    // Завершение записи
    PUSH3: begin phi <= phi_next; we <= 1'b0; bus <= 1'b0; end

    // Извлечение из стека
    POP: begin

        phi <= POP2;
        ea  <= sp;
        sp  <= sp + 1'b1;
        seg <= ss;
        bus <= 1'b1;

    end

    POP2: begin phi <= POP3; wb <= in; ea <= sp; sp <= sp + 1'b1; end
    POP3: begin phi <= phi_next; wb[15:8] <= in; bus <= 1'b0; end

endcase

// ~=~=~= ЦЕНТРАЛЬНОЕ АРИФМЕТИКО-ЛОГИЧЕСКОЕ УСТРОЙСТВО =~=~=~

wire [3:0] ntop     = size ? 15 : 7;
wire       i_add    =  (alu == ALU_ADD || alu == ALU_ADC);
wire       i_arith  = !(alu == ALU_OR  || alu == ALU_XOR || alu == ALU_AND);

// Все флаги, которые участвуют в вычислениях (OSZAPC)
wire r_over     = (op1[ntop] ^ op2[ntop] ^ i_add) & (op1[ntop] ^ ar[ntop]);
wire r_sign     = ar[ntop];
wire r_zero     = (size ? ar[15:0] : ar[7:0]) == 1'b0;
wire r_aux      = op1[AF] ^ op2[AF] ^ ar[AF];
wire r_parity   = ~^ar[7:0];
wire r_carry    = ar[ntop + 1];

// Вычисление результа
wire [16:0] ar =
    alu == ALU_ADD ? op1 + op2 :
    alu == ALU_OR  ? op1 | op2 :
    alu == ALU_ADC ? op1 + op2 + flags[CF] :
    alu == ALU_SBB ? op1 - op2 - flags[CF] :
    alu == ALU_AND ? op1 & op2 :
    alu == ALU_XOR ? op1 ^ op2 :
                     op1 - op2; // SUB, CMP

// Вычисление флагов
wire [11:0] af = {
    r_over & i_arith, flags[10:9], r_sign,   r_zero, 1'b0,     // OSZ
    r_aux  & i_arith, 1'b0,        r_parity, 1'b1,   r_carry}; // APC

// ~=~=~= ВЫЧИСЛЕНИЯ =~=~=~

// Условные переходы
wire [7:0] branch = {

    /*7*/ (flags[SF] ^ flags[OF]) | flags[ZF],
    /*6*/ (flags[SF] ^ flags[OF]),
    /*5*/  flags[PF],
    /*4*/  flags[SF],
    /*3*/  flags[CF] | flags[ZF],
    /*2*/  flags[ZF],
    /*1*/  flags[CF],
    /*0*/  flags[OF]
};

endmodule
