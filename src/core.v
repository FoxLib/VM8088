// verilator lint_off WIDTH
// verilator lint_off CASEX
// verilator lint_off CASEOVERLAP
// verilator lint_off CASEINCOMPLETE

module core
(
    // Тактовый генератор
    input               clock,
    input               reset_n,
    input               locked,
    // Магистраль данных 8 битная
    output      [31:0]  address,
    input       [ 7:0]  in,
    output reg  [ 7:0]  out,
    output reg          we,
    // Порты
    output  reg [15:0]  port,
    output  reg         port_clk,
    input       [ 7:0]  port_i,
    output  reg [ 7:0]  port_o,
    output  reg         port_w,
    // Прерывания
    input       [ 7:0]  irq,
    input               intr,
    output  reg         intl,
    // Отладка
    output      [ 3:0]  instr
);

assign instr = t;

always @(posedge clock)
if (locked) begin
if (reset_n == 1'b0) begin

    t           <= fetch;
    cs          <= 16'h000;
    ds          <= 16'h000;
    es          <= 16'h000;
    ss          <= 16'h000;
    eip         <= 20'hF8000;
    eflags      <= 2'h2;
    adsize      <= defsize;
    __adsize    <= defsize;
    __opsize    <= defsize;
    __segment   <= 16'h0000;
    __override  <= 1'b0;
    __rep       <= 1'b0;
    __opext     <= 1'b0;
    src         <= 1'b0;
    prot        <= 1'b0;
    psize       <= 1'b0;
    trace_ff    <= 1'b0;

end
else case (t)

    // Считывание опкода или префикса
    fetch: begin

        eip      <= eip_next;
        opcode   <= in;
        size     <= in[0];
        dir      <= in[1];
        alu      <= in[5:3];
        regn     <= in[2:0];
        fn       <= 1'b0;
        fn2      <= 1'b0;
        ignoreo  <= 1'b0;
        t_next   <= fetch;
        src_next <= 1'b1;

        case (in)

            // Сегментные префиксы
            8'h26: begin psize <= psize + 1'b1; __segment <= es; __override <= 1'b1; end
            8'h2E: begin psize <= psize + 1'b1; __segment <= cs; __override <= 1'b1; end
            8'h36: begin psize <= psize + 1'b1; __segment <= ss; __override <= 1'b1; end
            8'h3E: begin psize <= psize + 1'b1; __segment <= ds; __override <= 1'b1; end
            8'h64: begin psize <= psize + 1'b1; __segment <= fs; __override <= 1'b1; end
            8'h65: begin psize <= psize + 1'b1; __segment <= gs; __override <= 1'b1; end
            // Префиксы расширения адреса
            8'h66: begin psize <= psize + 1'b1; __opsize  <= ~__opsize; end
            8'h67: begin psize <= psize + 1'b1; __adsize  <= ~__adsize; end
            // ...
            8'h0F: begin psize <= psize + 1'b1; __opext   <= 1'b1; end
            // LOCK, REP
            8'hF0: begin psize <= psize + 1'b1; end // LOCK:
            8'hF2, 8'hF3: begin psize <= psize + 1'b1; __rep <= in[1:0]; end
            // Исполнение опкода
            default: begin

                t       <= exec;
                eip_rep <= eip-psize;
                psize   <= 0;

                // Защелкивание префиксов
                rep         <= __rep;       __rep       <= 2'b00;
                override    <= __override;  __override  <= 1'b0;
                opsize      <= __opsize;    __opsize    <= defsize;
                adsize      <= __adsize;    __adsize    <= defsize;
                segment     <= __segment;   __segment   <= ds;
                opcode[8]   <= __opext;     __opext     <= 1'b0;

                // Вызвать прерывание, если разрешено
                if (eflags[IF] && intr ^ intl) begin

                    t       <= interrupt;
                    intl    <= intr;
                    eip     <= eip - psize;
                    wb      <= irq;

                end
                // Trace Flag=1
                else if (eflags[TF] && trace_ff) begin

                    t        <= interrupt;
                    trace_ff <= ~trace_ff;
                    eip      <= eip - psize;
                    wb       <= 1;

                end
                // На первом такте также можно исполнять некоторые опкоды
                else casex ({__opext, in})

                    // FWAIT, NOP
                    8'h9B, 8'h90: begin t <= fetch; end

                    // <ALU> modrm; XCHG modrm; ESC
                    8'b00xx_x0xx,
                    8'b1000_011x,
                    8'b1101_1xxx: begin t <= fetch_modrm; end

                    8'b00xx_x101, // <ALU> a, imm
                    8'b1001_1010, // JMP|CALL far seg:off
                    8'b1110_1010: begin t <= fetch_imm16; end

                    // RET/RETF imm
                    8'b1100_x010: begin t <= fetch_imm16; t_next <= exec; size <= 1'b1; end

                    // POP
                    8'b000x_x111, // POP sreg
                    8'b0101_1xxx, // POP r16
                    8'b1000_1111, // POPF
                    8'b1001_1101, // POP rm
                    8'b1100_1111, // IRET; RET; RETF
                    8'b1100_x011: begin t <= pop; t_next <= exec; op1 <= 0; fn <= 1; end

                    // DAA, DAS
                    8'b0010_x111: begin t <= fetch; eflags <= eflags_d; eax[7:0] <= daa_r[ 7:0]; end

                    // Jccc short|near
                    9'b0_0111_xxxx,
                    9'b1_1000_xxxx: begin

                        // Если условие не сработало, переход к +2
                        if (branches[ in[3:1] ] == in[0]) begin

                            t   <= fetch;
                            eip <= __opext ? (__opsize ? eip_next5 : eip_next3) : eip_next2;

                        end
                        // В near-варианте считывается 16/32 бита
                        else if (__opext) begin size <= 1'b1; t <= fetch_imm16; end

                    end

                    // AAA, AAS
                    8'b0011_x111: begin t <= fetch; eflags <= eflags_d; eax[15:0] <= daa_r[15:0]; end

                    // PUSH sreg
                    8'b000x_x110: begin

                        t       <= push;
                        opsize  <= 1'b0;

                        case (in[4:3])
                        2'b00: wb <= es[15:0];
                        2'b01: wb <= cs[15:0];
                        2'b10: wb <= ss[15:0];
                        2'b11: wb <= ds[15:0];
                        endcase

                    end

                    // PUSH imm16
                    8'b0110_1000: begin t <= fetch_imm16; size <= 1'b1; t_next <= exec; end

                    // INC|DEC r16; PUSH r16; XCHG a,r16
                    8'b0100_xxxx,
                    8'b0101_0xxx,
                    8'b1001_0xxx: begin size <= 1'b1; end

                    // PUSHA
                    8'b0110_0000: begin frametemp <= esp; t_next <= exec; size <= 1'b1; regn <= 0; end

                    // POPA
                    8'b0110_0001: begin t_next <= exec; regn <= 7; t <= pop; end

                    // IMUL r,m,i8
                    8'b0110_10x1: begin t <= fetch_modrm; {size, dir} <= 2'b11; src_next <= 1'b0; end

                    // *SHIFT* C0-C1,D0-D3
                    // *ALU* 80-83
                    8'b1000_00xx,
                    8'b1100_000x,
                    8'b1101_00xx: begin

                        t           <= fetch_modrm;
                        dir         <= 1'b0;
                        src_next    <= 1'b0;

                    end

                    // PUSHF
                    8'b1001_1100: begin

                        t   <= push;
                        wb  <= {eflags[17:6], 1'b0, eflags[4], 1'b0, eflags[2], 1'b1, eflags[0]};

                    end

                    // MOV [m],a; MOV a,[m]
                    8'b1010_00xx: begin

                        t       <= fetch_imm16;
                        size    <= 1'b1;
                        opsize  <= __adsize;
                        adsize  <= __opsize;

                    end

                    // MOVSx | LODSx
                    8'b1010_x10x: if (__rep[1] == 1'b0 || str_zcx) begin

                        t       <= fetch_modrm;
                        t_next  <= exec;
                        fn2     <= 4;
                        src     <= 1'b1;
                        ea      <= defsize ? esi : esi[15:0];

                    end else t <= fetch;

                    // STOSx
                    8'b1010_101x: if (__rep[1] == 1'b0 || str_zcx) begin

                        t       <= modrm_wb;
                        segment <= es;
                        ea      <= defsize ? edi : edi[15:0];
                        wb      <= eax;
                        edi     <= str_edi;
                        dir     <= 1'b0;
                        src     <= 1'b1;
                        modrm   <= 1'b0;

                        // При REP: уменьшать CX и переход к возвратной точке
                        if (__rep[1]) begin ecx <= str_ecx; eip <= eip-psize; end

                    end else t <= fetch;

                    // CMPSx
                    8'b1010_011x: if (__rep[1] == 1'b0 || str_zcx) begin

                        t       <= fetch_modrm;
                        t_next  <= exec;
                        fn2     <= 4;
                        dir     <= 1'b0;
                        src     <= 1'b1;
                        ea      <= defsize ? esi : esi[15:0];
                        op1     <= 0;
                        alu     <= alu_cmp;

                    end else t <= fetch;

                    // SCASx
                    8'b1010_111x: if (__rep[1] == 1'b0 || str_zcx) begin

                        t       <= fetch_modrm;
                        t_next  <= exec;
                        fn2     <= 4;
                        src     <= 1'b1;
                        ea      <= defsize ? edi : edi[15:0];
                        segment <= es;
                        op1     <= eax;
                        alu     <= alu_cmp;

                    end else t <= fetch;

                    // TEST modrm
                    8'b1000_010x: begin t <= fetch_modrm; alu <= alu_and; end

                    // MOV rm, sreg
                    8'b1000_1100: begin t <= fetch_modrm; {size, dir, ignoreo} <= 3'b101; end

                    // LEA r16, [ea]
                    8'b1000_1101: begin t <= fetch_modrm; {size, dir, ignoreo} <= 3'b111; end

                    // LES|LDS r,[m]
                    // MOV sreg, rm
                    8'b1100_010x,
                    8'b1000_1110: begin t <= fetch_modrm; {size, dir} <= 2'b11; end

                    // MOV modrm
                    8'b1000_10xx: begin t <= fetch_modrm; ignoreo <= ~in[1]; end

                    // MOV r,imm
                    8'b1011_1xxx: begin t <= fetch_imm16; end

                    // SAHF
                    8'b1001_1110: begin eflags[7:0] <= eax[15:8];   t <= fetch; end

                    // LAHF
                    8'b1001_1111: begin eax[15:8]   <= eflags[7:0]; t <= fetch; end

                    // CBW, CWDE
                    8'b1001_1000: begin

                        t <= fetch;
                        if (__opsize)
                             eax[31:16] <= {16{eax[15]}};
                        else eax[15:8]  <= { 8{eax[7]}};

                    end

                    // CWD, CDQ
                    8'b1001_1001: begin

                        t <= fetch;
                        if (__opsize)
                             edx[31:0] <= {32{eax[31]}};
                        else edx[15:0] <= {16{eax[15]}};

                    end

                    // TEST a, imm16
                    8'b1010_1001: begin t <= fetch_imm16; end

                    // MOV modrm,imm
                    8'b1100_011x: begin t <= fetch_modrm; {dir, ignoreo} <= 2'b01; end

                    // ENTER i16, i8
                    8'b1100_1000: begin t <= fetch_imm16; t_next <= exec; size <= 1'b1; end

                    // LEAVE
                    8'b1100_1001: begin esp <= ebp; t <= pop; t_next <= exec; end

                    // SALC
                    8'b1101_0110: begin t <= fetch; eax[7:0] <= {8{eflags[CF]}}; end

                    // XLATB
                    8'b1101_0111: begin t <= exec; ea <= ebx[15:0] + eax[7:0]; src <= 1'b1; end

                    // JCXZ
                    8'b1110_0011: begin

                        t <= fetch;
                        if ((__opsize && ecx == 0) || (!__opsize && ecx[15:0] == 0))
                            t <= exec;
                        else
                            eip <= eip_next2;

                    end

                    // LOOP, LOOPNZ, LOOPZ
                    8'b1110_000x,
                    8'b1110_0010: begin

                        t <= fetch;

                        // В зависимости от выбранного режима адресации либо ECX, либо CX
                        if (__adsize) ecx <= ecx - 1'b1; else ecx[15:0] <= ecx[15:0] - 1'b1;

                        // ZF=0/1 и CX != 0 (после декремента)
                        if (((eflags[ZF] == in[0]) || in[1]) && (__adsize ? ecx : ecx[15:0]) != 1'b1)
                            t <= exec;
                        else
                            eip <= eip_next2;

                    end

                    // IN|OUT
                    8'b1110_x1xx: begin

                        fn       <= in[3] ? 1 : 0;
                        op1      <= in[0] ? (__opsize ? 3 : 1) : 0;
                        op2      <= 0;
                        port     <= edx[15:0];
                        port_clk <= 1'b0;

                    end

                    // CALL|JMP near
                    8'b1110_100x: begin t <= fetch_imm16; size <= 1'b1; end

                    // INT 3; INT 1
                    8'b1100_1100: begin t <= interrupt; wb <= 3; end
                    8'b1111_0001: begin t <= interrupt; wb <= 1; end

                    // INTO
                    8'b1100_1110: begin if (eflags[OF]) begin t <= interrupt; wb <= 4; end else t <= fetch; end

                    // HLT
                    8'b1111_0100: begin t <= fetch; eip <= eip; end

                    // CMC; CLC,STC; CLI,STI; CLD,STD
                    8'b1111_0101: begin t <= fetch; eflags[CF] <= ~eflags[CF]; end
                    8'b1111_100x: begin t <= fetch; eflags[CF] <= in[0]; end
                    8'b1111_101x: begin t <= fetch; eflags[IF] <= in[0]; end
                    8'b1111_110x: begin t <= fetch; eflags[DF] <= in[0]; end

                    // Групповые инструкции
                    8'b1111_x11x: begin t <= fetch_modrm; t_next <= exec; dir <= 1'b0; end

                    // CMOV<cc> r,rm
                    9'b1_0100_xxxx: begin t <= fetch_modrm; dir <= 1'b1; end

                    // Все оставшиеся
                    default: t <= exec;

                endcase

            end

        endcase

    end

    // Прочитать байт modrm+sib
    fetch_modrm: case (fn2)
    
        // Считывание регистров
        0: begin
    
            modrm   <= in;
            eip     <= eip_next;
            ea      <= 1'b0;
    
            // Левый операнд
            case (dir ? in[5:3] : in[2:0])
            0: op1 <= size ? (opsize ? eax : eax[15:0]) : eax[ 7:0];
            1: op1 <= size ? (opsize ? ecx : ecx[15:0]) : ecx[ 7:0];
            2: op1 <= size ? (opsize ? edx : edx[15:0]) : edx[ 7:0];
            3: op1 <= size ? (opsize ? ebx : ebx[15:0]) : ebx[ 7:0];
            4: op1 <= size ? (opsize ? esp : esp[15:0]) : eax[15:8];
            5: op1 <= size ? (opsize ? ebp : ebp[15:0]) : ecx[15:8];
            6: op1 <= size ? (opsize ? esi : esi[15:0]) : edx[15:8];
            7: op1 <= size ? (opsize ? edi : edi[15:0]) : ebx[15:8];
            endcase
    
            // Правый операнд
            case (dir ? in[2:0] : in[5:3])
            0: op2 <= size ? (opsize ? eax : eax[15:0]) : eax[ 7:0];
            1: op2 <= size ? (opsize ? ecx : ecx[15:0]) : ecx[ 7:0];
            2: op2 <= size ? (opsize ? edx : edx[15:0]) : edx[ 7:0];
            3: op2 <= size ? (opsize ? ebx : ebx[15:0]) : ebx[ 7:0];
            4: op2 <= size ? (opsize ? esp : esp[15:0]) : eax[15:8];
            5: op2 <= size ? (opsize ? ebp : ebp[15:0]) : ecx[15:8];
            6: op2 <= size ? (opsize ? esi : esi[15:0]) : edx[15:8];
            7: op2 <= size ? (opsize ? edi : edi[15:0]) : ebx[15:8];
            endcase
    
            // 32-bit MODRM
            if (adsize) begin
    
                case (in[2:0])
                3'b000: ea <= eax;
                3'b001: ea <= ecx;
                3'b010: ea <= edx;
                3'b011: ea <= ebx;
                3'b100: ea <= 0;
                3'b101: ea <= ^in[7:6] ? ebp : 0;
                3'b110: ea <= esi;
                3'b111: ea <= edi;
                endcase
    
                // Выбор решения
                case (in[7:6])
                2'b00: begin
    
                    if      (in[2:0] == 3'b101) fn2 <= 1;  // DISP32
                    else if (in[2:0] == 3'b100) fn2 <= 10; // SIB
                    else begin
    
                        fn2 <= 4;
                        src <= 1'b1;
                        if (ignoreo) begin t <= exec; fn2 <= 0; end
    
                    end
    
                end
                2'b01: fn2 <= in[2:0] == 3'b100 ? 10 : 3; // 8     bit | SIB
                2'b10: fn2 <= in[2:0] == 3'b100 ? 10 : 1; // 16/32 bit | SIB
                2'b11: begin fn2 <= 0; t <= exec; end
                endcase
    
                // Выбор сегмента по умолчанию
                if (!override && (^in[7:6] && in[2:0] == 3'b101))
                    segment <= ss;
    
            end
            // 16-bit MODRM
            else begin
    
                case (in[2:0])
                3'b000: ea[15:0] <= ebx + esi;
                3'b001: ea[15:0] <= ebx + edi;
                3'b010: ea[15:0] <= ebp + esi;
                3'b011: ea[15:0] <= ebp + edi;
                3'b100: ea[15:0] <= esi;
                3'b101: ea[15:0] <= edi;
                3'b110: ea[15:0] <= ^in[7:6] ? ebp : 1'b0;
                3'b111: ea[15:0] <= ebx;
                endcase
    
                // Выбор сегмента по умолчанию
                if (!override && (in[2:1] == 2'b01 || (^in[7:6] && in[2:0] == 3'b110)))
                    segment <= ss;
    
                // Выбор решения
                case (in[7:6])
                2'b00: begin
    
                    // Читать +disp16
                    if (in[2:0] == 3'b110) fn2 <= 1;
                    // Сразу читать операнды из памяти
                    else begin
    
                        fn2 <= 4;
                        src <= 1'b1;
    
                        if (ignoreo) begin t <= exec; fn2 <= 0; end
    
                    end
    
                end
                2'b01: fn2 <= 3; // 8 bit
                2'b10: fn2 <= 1; // 16 bit
                2'b11: begin fn2 <= 0; t <= exec; end
                endcase
    
            end
    
        end
    
        // DISP16/32
        1: begin fn2 <= 2; ea <= ea + in; eip <= eip_next; end
        2: begin
    
            fn2      <=  adsize ? 8 : 4;
            src      <= !adsize;
            ea[31:8] <= ea[31:8] + in;
            eip      <= eip_next;
    
            if (ignoreo && !adsize) begin t <= exec; fn2 <= 0; end
    
        end
    
        // DISP8
        3: begin
    
            fn2 <= 4;
            ea  <= ea + {{24{in[7]}}, in};
            src <= 1'b1;
            eip <= eip_next;
    
            if (ignoreo) begin t <= exec; fn2 <= 0; end
    
        end
    
        // OPERAND-7:0
        4: begin
    
            if (dir) op2 <= in; else op1 <= in;
            if (size) begin fn2 <= 5; ea <= ea + 1; end
            else      begin fn2 <= 0; t  <= exec; src <= src_next; end
    
        end
    
        // OPERAND-15:8
        5: begin
    
            if (dir) op2[15:8] <= in; else op1[15:8] <= in;
            if (opsize) begin fn2 <= 6; ea <= ea + 1; end
            else        begin fn2 <= 0; ea <= ea - 1; t <= exec; src <= src_next; end
    
        end
    
        // OPERAND-23:16
        6: begin
    
            fn2 <= 7; ea <= ea + 1;
            if (dir) op2[23:16] <= in; else op1[23:16] <= in;
    
        end
    
        // OPERAND-31:24
        7: begin
    
            t   <= exec;
            fn2 <= 0;
            ea  <= ea - 3;
            src <= src_next;
    
            if (dir) op2[31:24] <= in; else op1[31:24] <= in;
    
        end
    
        // DISP32
        8: begin fn2 <= 9; ea[31:16] <= ea[31:16] + in; eip <= eip_next; end
        9: begin
    
            fn2         <= 4;
            ea[31:24]   <= ea[31:24] + in;
            src         <= 1'b1;
            eip         <= eip_next;
    
            if (ignoreo) begin t <= exec; fn2 <= 0; end
    
        end
    
        // SIB
        10: begin
    
            eip <= eip_next;
    
            // SCALE*INDEX
            case (in[5:3])
            3'b000: ea <= sib_base + (eax << in[7:6]);
            3'b001: ea <= sib_base + (ecx << in[7:6]);
            3'b010: ea <= sib_base + (edx << in[7:6]);
            3'b011: ea <= sib_base + (ebx << in[7:6]);
            3'b100: ea <= sib_base;
            3'b101: ea <= sib_base + (ebp << in[7:6]);
            3'b110: ea <= sib_base + (esi << in[7:6]);
            3'b111: ea <= sib_base + (edi << in[7:6]);
            endcase
    
            // disp32 или чтение операнда
            case (modrm[7:6])
            2'b00: if (in[2:0] == 3'b101)
                   begin fn2 <= 1; end // disp32
            else   begin fn2 <= 4; src <= 1'b1; end // operand
            2'b01: begin fn2 <= 3; end // disp8
            2'b10: begin fn2 <= 1; end // disp32
            2'b11: begin fn2 <= 0; t <= exec; end
            endcase
    
            // Выбор сегмента по умолчанию (ebp)
            if (!override && ((^modrm[7:6] && in[2:0] == 3'b101) || (in[5:3] == 3'b101)))
                segment <= ss;
    
            // Если необходимо игнорировать чтение операнда, то выход сразу к исполнению
            if (ignoreo && modrm[7:6] == 2'b00 && in[2:0] != 3'b101) begin t <= exec; fn2 <= 0; end
    
        end
    
    endcase
    
    // Запись результата в память или регистры
    modrm_wb: case (fn2)
    
        0: begin
    
            // Проверка на запись в регистр
            if (dir || modrm[7:6] == 2'b11) begin
    
                case (dir ? modrm[5:3] : modrm[2:0])
                3'b000: if (size && opsize) eax <= wb; else if (size) eax[15:0] <= wb[15:0]; else eax[ 7:0] <= wb[7:0];
                3'b001: if (size && opsize) ecx <= wb; else if (size) ecx[15:0] <= wb[15:0]; else ecx[ 7:0] <= wb[7:0];
                3'b010: if (size && opsize) edx <= wb; else if (size) edx[15:0] <= wb[15:0]; else edx[ 7:0] <= wb[7:0];
                3'b011: if (size && opsize) ebx <= wb; else if (size) ebx[15:0] <= wb[15:0]; else ebx[ 7:0] <= wb[7:0];
                3'b100: if (size && opsize) esp <= wb; else if (size) esp[15:0] <= wb[15:0]; else eax[15:8] <= wb[7:0];
                3'b101: if (size && opsize) ebp <= wb; else if (size) ebp[15:0] <= wb[15:0]; else ecx[15:8] <= wb[7:0];
                3'b110: if (size && opsize) esi <= wb; else if (size) esi[15:0] <= wb[15:0]; else edx[15:8] <= wb[7:0];
                3'b111: if (size && opsize) edi <= wb; else if (size) edi[15:0] <= wb[15:0]; else ebx[15:8] <= wb[7:0];
                endcase
    
                t   <= t_next;
                src <= 1'b0;
    
            end
            // LO-BYTE
            else begin
    
                out <= wb[7:0];
                we  <= 1'b1;
                src <= 1'b1;
                fn2 <= 1;
    
            end
    
        end
    
        // HI-BYTE
        1: begin
    
            if (size) begin out <= wb[15:8]; ea <= ea + 1; fn2 <= 2; end
            else      begin fn2 <= 0; t <= t_next; {src, we} <= 2'b00;  end
    
        end
    
        // BYTE-3
        2: begin
    
            if (opsize) begin out <= wb[23:16]; ea <= ea + 1; fn2 <= 3; end
            else        begin fn2 <= 0; t <= t_next; {src, we} <= 2'b00; end
    
        end
    
        // BYTE-4
        3: begin out <= wb[31:24]; ea <= ea + 1; fn2 <= 4; end
        4: begin fn2 <= 0; t <= t_next; {src, we} <= 2'b00; end
    
    endcase
    
    // Считать 16 или 32 бита
    fetch_imm16: case (fn2)
    
        0: begin eip <= eip_next; wb        <= in; fn2 <= 1; end
        1: begin eip <= eip_next; wb[15:8]  <= in; fn2 <= opsize ? 2 : 0; if (!opsize) t <= exec; end
        2: begin eip <= eip_next; wb[23:16] <= in; fn2 <= 3; end
        3: begin eip <= eip_next; wb[31:24] <= in; fn2 <= 0; t <= exec; end
    
    endcase
    
    // Загрузка сегмента из wb
    loadseg: case (fn2)
    
        // Пока что загрузка идет только в REALMODE
        0: begin
    
            t   <= t_next;
            src <= 1'b0;
    
            // Обновить сегмент | селектор
            case (regn)
            3'b000: begin es[15:0] <= wb; end
            3'b001: begin cs[15:0] <= wb; end
            3'b010: begin ss[15:0] <= wb; end
            // Заместить "скрытый" сегмент
            3'b011: begin ds[15:0] <= wb; __segment[15:0] <= wb; end
            3'b100: begin fs[15:0] <= wb; end
            3'b101: begin gs[15:0] <= wb; end
            default: t <= exception;
            endcase
    
        end
    
    endcase
    
    // Запись в стек
    push: case (fn2)
    
        // BYTE-1
        0: begin
    
            fn2     <= 1;
            segment <= ss;
            ea      <= esp_dec;
            esp     <= esp_dec;
            src     <= 1'b1;
            we      <= 1'b1;
            out     <= wb[7:0];
    
        end
    
        // Запись байтов 2/3/4/FIN
        1: begin ea <= ea + 1; out <= wb[ 15:8]; fn2 <= stacksize | opsize ? 2 : 4; end
        2: begin ea <= ea + 1; out <= wb[24:16]; fn2 <= 3; end
        3: begin ea <= ea + 1; out <= wb[31:24]; fn2 <= 4; end
        4: begin {we, src} <= 2'b00; fn2 <= 0; t <= t_next; end
    
    endcase
    
    // Извлечь из стека
    pop: case (fn2)
    
        // Установка адреса
        0: begin
    
            fn2     <= 1;
            segment <= ss;
            ea      <= esp;
            esp     <= esp_inc;
            src     <= 1'b1;
    
        end
    
        // 16bit
        1: begin fn2 <= 2; wb <= in; ea <= ea + 1; end
        2: begin
    
            wb[15:8] <= in;
    
            fn2 <= stacksize | opsize ? 3 : 0;
            ea  <= ea + 1;
    
            if (opsize == 0) begin src <= 1'b0; t <= t_next; end
    
        end
    
        // 32bit
        3: begin wb[23:16] <= in; fn2 <= 4; ea <= ea + 1; end
        4: begin wb[31:24] <= in; fn2 <= 0; src <= 1'b0; t <= t_next; end
    
    endcase
    
    // Сдвиги
    // alu
    // size, opsize
    // op1, op2
    shift: case (fn2)
    
        // Вычисление ограничения количества сдвигов
        // Если сдвиг не задан (0), то сдвиг не срабатывает
        0: begin
    
            fn2 <= 1;
    
            // 32 bit
            if (size && opsize) begin
    
                wb  <= 31;
                op2 <= op2[4:0];
                if (op2[4:0] == 0) begin fn2 <= 0; src <= 1'b0; t <= fetch; end
    
            end
            // 16 bit
            else if (size) begin
    
                // DosBox так обрабатывает (4:0)
                wb  <= 15;
                op2 <= op2[4:0];
                if (op2[4:0] == 0) begin fn2 <= 0; src <= 1'b0; t <= fetch; end
    
            end
            // 8 bit
            else begin
    
                wb  <= 7;
                op2 <= op2[2:0];
    
                if (op2[2:0] == 0) begin fn2 <= 0; src <= 1'b0; t <= fetch; end
    
            end
    
        end
    
        // Вычисление
        1: begin
    
            // Сдвиги
            if (op2) begin
    
                op2 <= op2 - 1;
    
                case (alu)
    
                    0: // ROL
                    begin op1 <= size ? (opsize ? {op1[30:0],op1[31]} : {op1[14:0],op1[15]}) : {op1[6:0],op1[7]}; end
    
                    1: // ROR
                    begin op1 <= size ? (opsize ? {op1[0],op1[31:1]} : {op1[0],op1[15:1]}) : {op1[0],op1[7:1]}; end
    
                    2: // RCL
                    begin
    
                        op1 <= size ? (opsize ? {op1[30:0],eflags[CF]} : {op1[14:0],eflags[CF]}) : {op1[6:0],eflags[CF]};
                        eflags[CF] <= op1[wb];
    
                    end
    
                    3: // RCR
                    begin
    
                        op1 <= size ? (opsize ? {eflags[CF],op1[31:1]} : {eflags[CF],op1[15:1]}) : {eflags[CF],op1[7:1]};
                        eflags[CF] <= op1[0];
    
                    end
    
                    4, 6: // SHL
                    begin
    
                        eflags[CF] <= op1[wb-op2+1];
                        op1 <= op1 << op2;
                        op2 <= 0;
    
                    end
    
                    5: // SHR
                    begin
    
                        eflags[CF] <= op1[op2-1];
                        op1 <= op1 >> op2;
                        op2 <= 0;
    
                    end
    
                    7: // SAR
                    begin
    
                        op1 <= size ? (opsize ? {op1[31],op1[31:1]} : {op1[15],op1[15:1]}) : {op1[7],op1[7:1]};
                        eflags[CF] <= op1[0];
    
                    end
    
                endcase
    
            end
            // Расчет флагов
            else begin
    
                fn2 <= 0;
                t   <= modrm_wb;
                wb  <= op1;
    
                case (alu)
    
                    0: begin eflags[CF] <= op1[0];  eflags[OF] <= op1[0]  ^ op1[wb];   end
                    1: begin eflags[CF] <= op1[wb]; eflags[OF] <= op1[wb] ^ op1[wb-1]; end
                    2: begin eflags[OF] <= eflags[CF] ^ op1[wb]; end
                    3: begin eflags[OF] <= op1[wb] ^ op1[wb-1]; end
                    default: begin
    
                        eflags[ZF] <= !op1;
                        eflags[SF] <= op1[wb];
                        eflags[PF] <= ~^op1[7:0];
                        eflags[AF] <= 1'b1;
    
                    end
    
                endcase
    
            end
        end
    
    endcase
    
    // Процедура деления [diva, divb, divcnt]
    divide: begin
    
        if (divcnt) begin
    
            // Следующий остаток
            divrem <= _divr >= divb ? _divr - divb : _divr;
    
            // Вдвиг нового бита результата
            divres <= {divres[62:0], _divr >= divb};
    
            // Сдвиг влево делимого
            diva   <= {diva[62:0], 1'b0};
    
            // Уменьшение счетчика
            divcnt <= divcnt - 1'b1;
    
        end
        else t <= t_next;
    
    end
    
    // portin: begin end
    // portout: begin end
    
    // Вызов прерывания wb
    interrupt: case (fn)
    
        // Запись в стек eflags|cs|ip
        0: begin
    
            fn          <= 1;
            t           <= push;
            t_next      <= interrupt;
            wb          <= eflags;
            eflags[IF]  <= 1'b0;
            eflags[TF]  <= 1'b0;
            op1         <= wb;
    
        end
        1: begin fn <= 2; t <= push; wb <=  cs[15:0]; end
        2: begin fn <= 3; t <= push; wb <= eip[15:0]; end
        // Загрузка данных из IDTR
        3: begin fn <= 4; ea <= {op1[7:0], 2'b00}; src <= 1'b1; segment[15:0] <= 16'h0000; end
        4: begin fn <= 5; eip[ 7:0] <= in; ea <= ea + 1; end
        5: begin fn <= 6; eip[15:8] <= in; ea <= ea + 1; end
        6: begin fn <= 7; wb [ 7:0] <= in; ea <= ea + 1; end
        7: begin
    
            t           <= loadseg;
            t_next      <= fetch;
            fn          <= 0;
            fn2         <= 0;
            wb[15:8]    <= in;
            regn        <= 1;
    
        end
    
    endcase
    
    exec: casex (opcode)
    
        // 00 <ALU> modrm
        8'b00xx_x0xx: begin
    
            t       <= modrm_wb;
            wb      <= alu_r;
            eflags  <= alu_f;
    
            if (alu == alu_cmp) begin t <= fetch; src <= 1'b0; end
    
        end
    
        // 04 <ALU> a, imm
        8'b00xx_x10x: case (fn)
    
            // Выставить операнды на вычисление
            0: begin
    
                fn  <= 1;
                op1 <= size ? (opsize ? eax : eax[15:0]) : eax[7:0];
                op2 <= size ? (opsize ? wb  : wb[15:0]) : in;
    
                if (size == 0) eip <= eip_next;
    
            end
    
            // Записать результаты в AL|AX|EAX
            1: begin
    
                t       <= fetch;
                eflags  <= alu_f;
    
                if (alu != alu_cmp) begin
    
                    if (opsize && size) eax       <= alu_r;
                    else if (size)      eax[15:0] <= alu_r[15:0];
                    else                eax[7:0]  <= alu_r[7:0];
    
                end
    
            end
    
        endcase
    
        // 07 POP sreg
        8'b000x_x111: begin
    
            t       <= loadseg;
            t_next  <= fetch;
            regn    <= opcode[4:3];
    
        end
    
        // 40 INC|DEC r16
        8'b0100_xxxx: case (fn)
    
            // Загрузка
            0: begin
    
                fn  <= 1;
                op1 <= reg32;
                op2 <= 1;
                alu <= opcode[3] ? alu_sub : alu_add;
    
            end
    
            // Вычисление
            1: begin
    
                t           <= modrm_wb;
                wb          <= alu_r;
                eflags      <= {alu_f[17:1], eflags[CF]};
                dir         <= 1'b1;
                modrm[5:3]  <= opcode[2:0];
    
            end
    
        endcase
    
        // 50 PUSH r16
        8'b0101_0xxx: begin
    
            t  <= push;
            wb <= reg32;
    
        end
    
        // 58 POP r16
        8'b0101_1xxx: begin
    
            t           <= modrm_wb;
            t_next      <= fetch;
            size        <= 1'b1;
            dir         <= 1'b1;
            modrm[5:3]  <= opcode[2:0];
    
        end
    
        // 60 PUSHA
        8'b0110_0000: begin
    
            if (regn == 7) t_next <= fetch;
    
            wb   <= regn == 4 ? frametemp : reg32;
            t    <= push;
            regn <= regn + 1;
    
        end
    
        // 60 POPA
        8'b0110_0001: begin
    
            t    <= regn == 0 ? fetch : pop;
            regn <= regn - 1;
    
            case (regn)
    
                0: if (opsize) eax <= wb; else eax[15:0] <= wb[15:0];
                1: if (opsize) ecx <= wb; else ecx[15:0] <= wb[15:0];
                2: if (opsize) edx <= wb; else edx[15:0] <= wb[15:0];
                3: if (opsize) ebx <= wb; else ebx[15:0] <= wb[15:0];
                // esp skip
                5: if (opsize) ebp <= wb; else ebp[15:0] <= wb[15:0];
                6: if (opsize) esi <= wb; else esi[15:0] <= wb[15:0];
                7: if (opsize) edi <= wb; else edi[15:0] <= wb[15:0];
    
            endcase
    
        end
    
        // 68 PUSH i16
        8'b0110_10x0: begin
    
            t       <= push;
            t_next  <= fetch;
    
            if (opcode[1]) begin wb <= {{24{in[7]}}, in}; eip <= eip_next; end
    
        end
    
        // 69 IMUL r16, rm, i16/i8
        8'b0110_10x1: case (fn)
    
            0: begin
    
                fn      <= 1;
                t       <= opcode[1] ? exec : fetch_imm16;
                t_next  <= exec;
                op1     <= op2;
                wb      <= in;
    
                if (opcode[1]) eip <= eip_next;
    
            end
    
            1: begin
    
                fn      <= 2;
                op1     <= opsize ? op2 : {{16{op2[15]}}, op2[15:0]};
                op2     <= opcode[1] ? {{24{wb[7]}}, wb[7:0]} : (opsize ? wb : {{16{wb[15]}}, wb[15:0]});
    
            end
    
            2: begin
    
                if (opsize) begin
    
                    wb <= mult[31:0];
                    eflags[CF] <= mult[63:32] ? 1 : 0;
                    eflags[OF] <= mult[63:32] ? 1 : 0;
    
                end
                else begin
    
                    wb <= mult[15:0];
                    eflags[CF] <= mult[31:16] ? 1 : 0;
                    eflags[OF] <= mult[31:16] ? 1 : 0;
    
                end
    
                t       <= modrm_wb;
                t_next  <= fetch;
    
            end
    
        endcase
    
        // 80 <ALU> rm, i8/16
        8'b1000_00xx: case (fn)
    
            // Считывние 8 бит или дочитывание 16/32
            0: begin
    
                fn  <= 2;
                alu <= modrm[5:3];
    
                case (opcode[1:0])
                /*I8 */ 0, 2: begin eip <= eip_next;    op2 <= in; end
                /*I16*/ 1:    begin t   <= fetch_imm16; fn  <= 1; end
                /*S8 */ 3:    begin eip <= eip_next;    op2 <= opsize ? {{24{in[7]}}, in} : {{8{in[7]}}, in}; end
                endcase
    
            end
    
            // Данные из Imm16/32
            1: begin fn <= 2; op2 <= wb; end
    
            // Запись результата
            2: begin
    
                t       <= modrm_wb;
                wb      <= alu_r;
                eflags  <= alu_f;
                src     <= 1'b1;
    
                if (alu == alu_cmp) begin t <= fetch; src <= 1'b0; end
    
            end
    
        endcase
    
        // 84 TEST modrm
        8'b1000_010x: begin
    
            eflags  <= alu_f;
            fn      <= 1'b0;
            t       <= fetch;
            src     <= 1'b0;
    
        end
    
        // 86 XCHG rm,r
        8'b1000_011x: case (fn)
    
            0: begin t <= modrm_wb; wb <= op2; t_next <= exec;  fn  <= 1; end
            1: begin t <= modrm_wb; wb <= op1; t_next <= fetch; dir <= 0; end
    
        endcase
    
        // 88 MOV modrm
        // 8D LEA
        8'b1000_10xx,
        8'b1000_1101: begin
    
            t   <= modrm_wb;
            wb  <= opcode[2] ? ea : op2;
    
        end
    
        // 8C MOV r, sreg
        8'b1000_110x: begin
    
            t <= modrm_wb;
    
            case (modrm[5:3])
            3'h0: wb <= es[15:0];
            3'h1: wb <= cs[15:0];
            3'h2: wb <= ss[15:0];
            3'h3: wb <= ds[15:0];
            3'h4: wb <= fs[15:0];
            3'h5: wb <= gs[15:0];
            default: t <= exception;
            endcase
    
        end
    
        // 8E MOV sreg, rm
        8'b1000_1110: begin
    
            wb   <= op2;
            t    <= modrm[5:3] == 3'b001 ? exception : loadseg;
            regn <= modrm[5:3];
    
        end
    
        // 8F POP rm
        8'b1000_1111: case (fn)
    
            1: begin t <= fetch_modrm; fn <= 2; {dir, ignoreo} <= 2'b01; end
            2: begin t <= modrm_wb; t_next <= fetch; end
    
        endcase
    
        // 90 XCHG ax, r16
        8'b1001_0xxx: begin
    
            t           <= modrm_wb;
            wb          <= eax;
            dir         <= 1'b1;
            modrm[5:3]  <= regn;
    
            if (opsize) eax <= reg32; else eax[15:0] <= reg32[15:0];
    
        end
    
        // 9A JMP|CALL FAR
        8'b1001_1010,
        8'b1110_1010: case (fn)
    
            0: begin fn <= 1; opsize <= 1'b0; op1 <= wb; t <= fetch_imm16; end
            1: begin
    
                fn      <= 2;
                t       <= loadseg;
                t_next  <= opcode[4] ? exec : fetch; // CALL | JMP
                regn    <= 3'h1; // CS:
    
                if (opsize) eip <= op1; else eip[15:0] <= op1;
    
                // Для CALL
                op1 <= eip;
                op2 <= cs[15:0];
    
            end
    
            2: begin fn <= 3; t <= push; wb <= op2; end
            3: begin fn <= 0; t <= push; wb <= op1; t_next <= fetch; end
    
        endcase
    
        // 9D POPF
        8'b1001_1101: begin
    
            t <= fetch;
    
            if (opsize)
                eflags[17:0] <= {wb[17:6], 1'b0, wb[4], 1'b0, wb[2], 1'b1, wb[0]};
            else
                eflags[15:0] <= {wb[15:6], 1'b0, wb[4], 1'b0, wb[2], 1'b1, wb[0]};
    
        end
    
        // A0 MOV a,[m] || mov [m],a
        8'b1010_00xx: case (fn)
    
            // Либо запись в память, либо чтение
            0: begin
    
                fn      <= 1;
                src     <= 1'b1;
                ea      <= wb;
                adsize  <= opsize;
                opsize  <= adsize;
                size    <= opcode[0];
    
                if (opcode[1]) begin
    
                    t       <= modrm_wb;
                    wb      <= eax;
                    dir     <= 1'b0;
                    modrm   <= 1'b0;
    
                end
    
            end
    
            // AL, [mem]
            1: begin
    
                fn <= 2;
                ea <= ea + 1;
                eax[7:0] <= in;
                if (opcode[0] == 1'b0) begin fn <= 0; src <= 1'b0; t <= fetch; end
    
            end
    
            2: begin
    
                fn <= 3;
                ea <= ea + 1;
                eax[15:8] <= in;
                if (opsize == 1'b0) begin fn <= 0; src <= 1'b0; t <= fetch; end
    
            end
    
            3: begin eax[23:16] <= in; fn <= 4; ea <= ea + 1; end
            4: begin eax[31:24] <= in; t <= fetch; src <= 1'b0; end
    
        endcase
    
        // A4 MOVSx
        8'b1010_010x: begin
    
            t       <= modrm_wb;
            t_next  <= fetch;
            segment <= es;
            ea      <= defsize ? edi : edi[15:0];
            wb      <= op1;
            modrm   <= 1'b0;
            esi     <= str_esi;
            edi     <= str_edi;
    
            if (rep[1]) begin ecx <= str_ecx; eip <= eip_rep; end
    
        end
    
        // A6 CMPSx
        8'b1010_011x: case (fn)
    
            0: begin // Читать ES:eDI
    
                fn      <= 1;
                fn2     <= 4;
                dir     <= 1'b1;
                segment <= es;
                ea      <= defsize ? edi : edi[15:0];
                t       <= fetch_modrm;
    
            end
            1: begin // Инкременты, запись в eflags
    
                t       <= fetch;
                src     <= 1'b0;
                eflags  <= alu_f;
                esi     <= str_esi;
                edi     <= str_edi;
    
                if (rep[1]) ecx <= str_ecx;
                if (rep[1] && rep[0] == alu_f[ZF]) eip <= eip_rep;
    
            end
    
        endcase
    
        // A8 TEST a,imm
        8'b1010_100x: case (fn)
    
            0: begin
    
                fn  <= 1;
                op1 <= eax;
                op2 <= opcode[0] ? wb : in;
                alu <= alu_and;
    
                if (opcode[0] == 1'b0) eip <= eip_next;
    
            end
    
            1: begin eflags <= alu_f; fn <= 1'b0; t <= fetch; end
    
        endcase
    
        // AC LODSx
        8'b1010_110x: begin
    
            t   <= fetch;
            src <= 1'b0;
            esi <= str_esi;
    
            // Загрузка в Acc
            if (size && opsize) eax         <= op1[31:0];
            else if (size)      eax[15:0]   <= op1[15:0];
            else                eax[7:0]    <= op1[ 7:0];
    
            if (rep[1]) begin ecx <= str_ecx; eip <= eip_rep; end
    
        end
    
        // AE SCASx
        8'b1010_111x: begin
    
            src     <= 1'b0;
            t       <= fetch;
            eflags  <= alu_f;
            edi     <= str_edi;
    
            if (rep[1]) ecx <= str_ecx;
            if (rep[1] && rep[0] == alu_f[ZF]) eip <= eip_rep;
    
        end
    
        // B0 MOV r, imm
        8'b1011_xxxx: begin
    
            t           <= modrm_wb;
            dir         <= 1'b1;
            size        <= opcode[3];
            modrm[5:3]  <= opcode[2:0];
    
            // 8 битное значение
            if (!opcode[3]) begin eip <= eip_next; wb <= in; end
    
        end
    
        // C6 MOV modrm, imm
        8'b1100_011x: case (fn)
    
            // Запросить считывание immediate
            0: begin
    
                fn  <= size ? 2 : 1;
                src <= 1'b0;
    
                if (size) t <= fetch_imm16;
    
            end
    
            1: begin fn  <= 2; wb <= in; eip <= eip_next; end
            2: begin src <= 1'b1; t <= modrm_wb; t_next <= fetch; end
    
        endcase
    
        // C0 SHIFT
        8'b1100_000x,
        8'b1101_00xx: begin
    
            t       <= shift;
            t_next  <= fetch;
            alu     <= modrm[5:3];
            src     <= 1'b1;
    
            if (opcode[4])
                op2 <= opcode[1] ? ecx[5:0] : 1'b1;
            else begin
                eip <= eip_next;
                op2 <= in;
            end
    
    
        end
    
        // C4 LES|LDS r,[m]
        8'b1100_010x: case (fn)
    
            0: begin fn <= 1; t <= modrm_wb; t_next <= exec; wb <= op2; end
            1: begin fn <= 2; src <= 1'b1; ea <= ea + (opsize ? 4 : 2); end
            2: begin wb[7:0] <= in; fn <= 3; ea <= ea + 1; end
            3: begin
    
                t           <= loadseg;
                t_next      <= fetch;
                regn        <= opcode[0] ? 3 : 0;
                wb[15:8]    <= in;
    
            end
    
        endcase
    
        // C2 RET; RET imm
        8'b1100_001x: case (fn)
    
            0: begin fn <= 1; t <= pop; op1 <= wb; end
            1: begin
    
                t <= fetch;
    
                if (defsize) eip <= wb; else eip[15:0] <= wb[15:0];
                if (stacksize) esp <= esp + op1; else esp[15:0] <= esp[15:0] + op1[15:0];
    
            end
    
        endcase
    
        // C8 ENTER imm,i8
        8'b1100_1000: case (fn)
    
            0: begin
    
                fn  <= in ? 1 : 2;
                op1 <= wb;
                op2 <= in;
                eip <= eip_next;
                t   <= push;
                wb  <= ebp;
                frametemp <= esp_dec;
    
            end
    
            1: begin
    
                t   <= push;
                wb  <= op2 >  1 ? ebp-2 : frametemp;
                ebp <= op2 >  1 ? ebp-2 : ebp;
                fn  <= op2 == 1 ? 2 : 1;
                op2 <= op2 - 1;
    
            end
    
            2: begin
    
                t       <= fetch;
                ebp     <= frametemp;
                esp     <= ebp - op1;
    
            end
    
        endcase
    
        // LEAVE
        8'b1100_1001: begin ebp <= wb; t <= fetch; end
    
        // CA RETF; RETF imm
        8'b1100_101x: case (fn)
    
            0: begin fn <= 1; t <= pop; op1 <= wb; end
    
            1: begin
    
                fn <= 2;
                t  <= pop;
    
                if (defsize) eip <= wb; else eip[15:0] <= wb[15:0];
    
            end
    
            2: begin
    
                t       <= loadseg;
                t_next  <= fetch;
                regn    <= 3'h1; // CS:
    
                if (stacksize) esp <= esp + op1; else esp[15:0] <= esp[15:0] + op1[15:0];
    
            end
    
        endcase
    
        // CD INT i8
        8'b1100_1101: begin t <= interrupt; eip <= eip_next; wb <= in; end
    
        // CF IRET
        8'b1100_1111: case (fn)
    
            1: begin fn <= 2; t <= pop; op1 <= wb; end
            2: begin fn <= 3; t <= pop; op2 <= wb; end
            3: begin
    
                t       <= loadseg;
                t_next  <= fetch;
                regn    <= 1;
                eflags  <= wb;
                wb      <= op2;
    
                if (defsize) eip <= op1; else eip[15:0] <= op1[15:0];
    
            end
    
        endcase
    
        // E4 IN eAX, dx/i8
        8'b1110_x10x: case (fn)
    
            0: begin
    
                fn       <= 1;
                eip      <= eip_next;
                port     <= in;
                port_clk <= 1'b0;
    
            end
            1: begin fn <= 2; port_clk <= 1; end
            2: begin fn <= 3; port_clk <= 0; end
            3: begin fn <= 1;
    
                case (op2[1:0])
    
                    0: eax[7:0]   <= port_i; // 8  bit
                    1: eax[15:8]  <= port_i; // 16 bit
                    2: eax[23:16] <= port_i;
                    3: eax[31:24] <= port_i; // 32 bit
    
                endcase
    
                port     <= port     + 1'b1;
                op2[1:0] <= op2[1:0] + 1'b1;
    
                if (op1[1:0] == op2[1:0]) t <= fetch;
    
            end
    
        endcase
    
        // E8 CALL a16
        8'b1110_1000: begin
    
            t       <= push;
            t_next  <= fetch;
            wb      <= eip;
    
            if (opsize) eip       <= eip       + wb;
            else        eip[15:0] <= eip[15:0] + wb[15:0];
    
        end
    
        // D4 AAM
        8'b1101_0100: case (fn)
    
            0: begin
    
                fn      <= 1;
                t       <= in ? divide : interrupt;
                t_next  <= exec;
                diva    <= {eax[7:0], 56'b0};
                divb    <= in;
                divcnt  <= 8;
                wb      <= 0;
                eip     <= eip_next;
    
            end
    
            1: begin
    
                src <= 1'b0;
                t   <= fetch;
    
                if (divb) begin
    
                    eax[15:0] <= {divres[7:0], divrem[7:0]};
                    eflags[ZF] <= eax[15:0] == 0;
                    eflags[SF] <= eax[15];
                    eflags[PF] <= ~^eax[15];
    
                end
    
            end
    
        endcase
    
        // D5 AAD
        8'b1101_0101: begin
    
            t           <= fetch;
            eip         <= eip_next;
            eax[15:0]   <= aam;
            eflags[ZF]  <= aam[15:0] == 0;
            eflags[SF]  <= aam[15];
            eflags[PF]  <= ~^aam[15];
    
        end
    
        // D7 XLATB
        8'b1101_0111: begin eax[7:0] <= in; src <= 1'b0; t <= fetch; end
    
        // E0 LOOP | JMP | J<ccc> short b8
        8'b1110_00xx,
        8'b1110_1011,
        8'b0111_xxxx: begin
    
            t   <= fetch;
            eip <= eip + 1'b1 + {{24{in[7]}}, in};
    
        end
    
        // E6 OUT dx/i8, eAX
        8'b1110_x11x: case (fn)
    
            0: begin
    
                fn       <= 1;
                eip      <= eip_next;
                port     <= in;
                port_clk <= 1'b0;
    
            end
    
            1: begin
    
                fn       <= 2;
                port_w   <= 1;
                port_clk <= 1;
    
                case (op2[1:0])
    
                    0: port_o <= eax[  7:0];
                    1: port_o <= eax[ 15:8];
                    2: port_o <= eax[23:16];
                    3: port_o <= eax[31:24];
    
                endcase
    
            end
            2: begin fn <= 3; port_w <= 0; port_clk <= 0; end
            3: begin fn <= 1;
    
                port     <= port     + 1'b1;
                op2[1:0] <= op2[1:0] + 1'b1;
    
                if (op1[1:0] == op2[1:0]) t <= fetch;
    
            end
    
        endcase
    
        // E9 JMP near
        9'b0_1110_1001,
        9'b1_1000_xxxx: begin
    
            t <= fetch;
    
            if (opsize) eip       <= eip       + wb;
            else        eip[15:0] <= eip[15:0] + wb[15:0];
    
        end
    
        // Групповые инструкции F6/F7
        8'b1111_011x: casex (modrm[5:3])
    
            // TEST rm, imm
            3'b00x: case (fn)
    
                // Сброс src, если был для imm8
                0: if (src) src <= 1'b0;
                else begin
    
                    fn  <= opcode[0] ? 1 : 2;
                    t   <= opcode[0] ? fetch_imm16 : exec;
                    op2 <= in;
                    alu <= alu_and;
                    src <= 1'b0;
    
                    if (opcode[0] == 1'b0) eip <= eip_next;
    
                end
    
                1: begin fn <= 2; op2 <= wb; end
                2: begin eflags <= alu_f; t <= fetch; end
    
            endcase
    
            // NOT rm
            3'b010: begin
    
                wb      <= ~op1;
                t       <= modrm_wb;
                t_next  <= fetch;
    
            end
    
            // NEG rm
            3'b011: case (fn)
    
                0: begin fn <= 1; op1 <= 0; op2 <= op1; alu <= alu_sub; end
                1: begin wb <= alu_r; eflags <= alu_f; t <= modrm_wb; t_next <= fetch; end
    
            endcase
    
            // MUL | IMUL
            3'b10x: case (fn)
    
                // Запрос
                0: begin
    
                    fn <= 1;
    
                    if (modrm[3]) begin
                        op1 <= size ? (opsize ? op1 : {{16{op1[15]}}, op1[15:0]}) : {{24{op1[7]}}, op1[7:0]};
                        op2 <= size ? (opsize ? eax : {{16{eax[15]}}, eax[15:0]}) : {{24{eax[7]}}, eax[7:0]};
                    end else begin
                        op2 <= size ? (opsize ? eax : eax[15:0]) : eax[7:0];
                    end
    
                end
    
                // Запись результата
                1: begin
    
                    src <= 1'b0;
                    t   <= fetch;
    
                    // CF,OF устанавливаются при переполнении
                    // ZF при нулевом результате
                    if (opsize && size) begin // 32 bit
    
                        eax         <= mult[31:0];
                        edx         <= mult[63:32];
                        eflags[ZF]  <= mult[63:0] == 64'b0;
                        eflags[CF]  <= edx[31:0]  != 32'b0;
                        eflags[OF]  <= edx[31:0]  != 32'b0;
    
                    end else if (size) begin // 16 bit
    
                        eax[15:0]   <= mult[15:0];
                        edx[15:0]   <= mult[31:16];
                        eflags[ZF]  <= mult[31:0] == 32'b0;
                        eflags[CF]  <= edx[15:0]  != 16'b0;
                        eflags[OF]  <= edx[15:0]  != 16'b0;
    
                    end else begin // 8 bit
    
                        eax[15:0]   <= mult[15:0];
                        eflags[ZF]  <= mult[15:0] == 16'b0;
                        eflags[CF]  <= eax[15:8]  != 8'b0;
                        eflags[OF]  <= eax[15:8]  != 8'b0;
    
                    end
    
                end
    
            endcase
    
            // DIV, IDIV
            3'b11x: case (fn)
    
                // Запрос
                0: begin
    
                    fn      <= 1;
                    t       <= divide;
                    diva    <= _diva;
                    divb    <= _divb;
                    divcnt  <= size ? (opsize ? 64 : 32) : 16;
                    divrem  <= 1'b0;
                    divres  <= 1'b0;
                    signa   <= 1'b0;
                    signb   <= 1'b0;
    
                    // IDIV
                    if (modrm[3]) begin
    
                        // Расстановка знаков
                        signa <= _diva[63];
                        signb <= _divb[alu_top];
    
                        // diva = |diva|
                        if (_diva[63]) begin
    
                            if (size && opsize) diva        <= -_diva;
                            else if (size)      diva[63:32] <= -_diva[63:32];
                            else                diva[63:48] <= -_diva[63:48];
    
                        end
    
                        // divb = |divb|
                        if (size && opsize && _divb[31]) divb[31:0] <= -_divb[31:0];
                        else if (size && _divb[15])      divb[15:0] <= -_divb[15:0];
                        else if (_divb[7])               divb[ 7:0] <= -_divb[ 7:0];
    
                    end
    
                end
    
                // Запись результата
                1: begin
    
                    t    <= fetch;
                    src  <= 1'b0;
                    wb   <= 1'b0;   // INT 0
    
                    if (size && opsize) begin
    
                        eax <= signd ? -divres[31:0] : divres[31:0];
                        edx <= divrem[31:0];
    
                        if (|divres[63:32] || divb[31:0] == 0) t <= interrupt;
    
                    end else if (size) begin
    
                        eax[15:0] <= signd ? -divres[15:0] : divres[15:0];
                        edx[15:0] <= divrem[15:0];
    
                        if (|divres[31:16] || divb[15:0] == 0) t <= interrupt;
    
                    end else begin
    
                        eax[ 7:0] <= signd ? -divres[7:0] : divres[7:0];
                        eax[15:8] <= divrem[7:0];
    
                        if (|divres[15:8] || divb[7:0] == 0) t <= interrupt;
    
                    end
    
                end
    
            endcase
    
        endcase
    
        // Групповые инструкции FE/FF
        8'b1111_111x: case (modrm[5:3])
    
            // INC|DEC rm
            3'b000,
            3'b001: case (fn)
    
                0: begin fn <= 1; op2 <= 1; alu <= modrm[3] ? 5 : 0; end
                1: begin wb <= alu_r; t <= modrm_wb; t_next <= fetch; eflags <= {alu_f[11:1], eflags[CF]}; end
    
            endcase
    
            // CALL | JMP rm
            3'b010,
            3'b100: if (size) begin
    
                t       <= modrm[4] ? push : fetch;
                t_next  <= fetch;
                src     <= modrm[4];
                wb      <= eip;
    
                if (opsize) eip <= op1; else eip[15:0] <= op1[15:0];
    
            end else t <= exception;
    
            // CALL | JMP far
            3'b011,
            3'b101: if (size) case (fn)
    
                0: begin
    
                    // Для PUSH (CALL)
                    op1 <= cs[15:0];
                    op2 <= eip;
    
                    // Переход по заданному адресу
                    if (defsize | opsize) eip <= op1; else eip[15:0] <= op1[15:0];
    
                    fn  <= 1;
                    ea  <= ea + (opsize? 4 : 2);
    
                end
    
                // Загрузка CS:
                1: begin fn <= 2; wb[7:0] <= in; ea <= ea + 1; end
    
                // Загрузка сегмента и либо выход к fetch, либо call far
                2: begin
    
                    t           <= loadseg;
                    t_next      <= modrm[5] ? fetch : exec;
                    fn          <= 3;
                    regn        <= 1;
                    wb[15:8]    <= in;
    
                end
    
                // PUSH для CALL FAR
                3: begin fn <= 4; t <= push; wb <= op1; end
                4: begin fn <= 5; t <= push; wb <= op2; t_next <= fetch; end
    
            endcase else t <= exception;
    
            // PUSH rm
            3'b110: if (size) begin
    
                t       <= push;
                t_next  <= fetch;
                wb      <= op1;
    
            end else t <= exception;
    
            // Undefined instruction
            3'b111: t <= exception;
    
        endcase
    
        // CMOV<cc> r, rm
        9'b1_0100_xxxx: begin
    
            if (branches[ opcode[3:1] ] != opcode[0]) begin
    
                t  <= modrm_wb;
                wb <= op2;
    
            end else begin src <= 0; t <= fetch; end
    
        end
    
        // UNEXPECTED INSTRUCTION
        default: begin end
    
    endcase

endcase
end

// ---------------------------------------------------------------------
// Именованные константы
// ---------------------------------------------------------------------

localparam
    fetch           = 0,
    fetch_modrm     = 1,
    exec            = 2,
    modrm_wb        = 3,
    fetch_imm16     = 4,
    loadseg         = 5,
    exception       = 6,
    push            = 7,
    pop             = 8,
    shift           = 9,
    interrupt       = 10,
    divide          = 11,
    portin          = 12,
    portout         = 13;

localparam
    CF = 0, PF = 2, AF =  4, ZF =  6, SF = 7,
    TF = 8, IF = 9, DF = 10, OF = 11,
    IOPL0   = 12,
    IOPL1   = 13,
    NT      = 14,
    RF      = 16,
    VM      = 17;

localparam
    alu_add = 3'h0, alu_or  = 3'h1,
    alu_adc = 3'h2, alu_sbb = 3'h3,
    alu_and = 3'h4, alu_sub = 3'h5,
    alu_xor = 3'h6, alu_cmp = 3'h7;

// -----------------------------------------------------------------------------
// УПРАВЛЕНИЕ ПАМЯТЬЮ
// -----------------------------------------------------------------------------

// REAL-MODE
assign address =
    src ? {segment, 4'h0} + (adsize ? ea  :  ea[15:0]) :
          {     cs, 4'h0} + (adsize ? eip : eip[15:0]);

initial begin

    we       = 1'b0;
    out      = 1'b0;
    port     = 1'b0;
    port_clk = 1'b0;
    port_o   = 1'b0;
    port_w   = 1'b0;

end

// ---------------------------------------------------------------------
// РЕГИСТРЫ И СЕГМЕНТЫ
// ---------------------------------------------------------------------

// 8 x 32 битных регистров общего назначения
reg [31:0]  eax = 32'hDAEE_707F;
reg [31:0]  ebx = 32'h0177_AABC;
reg [31:0]  ecx = 32'h0000_0002;
reg [31:0]  edx = 32'h0000_0000;
reg [31:0]  esp = 32'h0000_FFFE;
reg [31:0]  ebp = 32'h0000_0000;
reg [31:0]  esi = 32'h0000_0000;
reg [31:0]  edi = 32'h0000_0004;

//                        VR  Nio ODIT SZ A  P1C
reg [17:0]  eflags  = 18'b00_0000_0000_0000_0010;
reg [31:0]  eip     = 32'h0000_0000;
reg [31:0]  eip_rep = 32'h0000_0000;

// Сегменты
reg [15:0]  es  = 80'hF000;
reg [15:0]  cs  = 80'hF000;
reg [15:0]  ss  = 80'h0000;
reg [15:0]  ds  = 80'hF800;
reg [15:0]  fs  = 80'h0000;
reg [15:0]  gs  = 80'h0000;

// -----------------------------------------------------------------------------

reg [3:0]   t               = 1'b0;     // Фаза исполнения
reg [3:0]   t_next          = 1'b0;     // Переход к фазе после исполнения процедуры
reg [4:0]   fn              = 1'b0;     // Фаза exec
reg [3:0]   fn2             = 1'b0;     // Фаза процедур
reg [8:0]   opcode          = 1'b0;     // Сохраненный опкод
reg [2:0]   psize           = 1'b0;     // Количество префиксов от 0 до 7
reg [7:0]   modrm           = 1'b0;     // Сохраненный modrm
reg         src             = 1'b0;     // Источник адреса segment:ea; cs:eip
reg         src_next        = 1'b1;     // src после fetch_modrm
reg         trace_ff        = 1'b0;     // Trace вызывается после инструкции
reg [79:0]  segment         = 1'b0;     // Рабочий сегмент
reg [31:0]  ea              = 1'b0;     // Эффективный адрес
reg         prot            = 1'b0;     // =1 Защищенный режим
reg         adsize          = 1'b0;     // =1 32х битная адресация
reg         opsize          = 1'b0;     // =1 32х битный операнд
reg         override        = 1'b0;     // =1 Сегмент префиксирован
reg         ignoreo         = 1'b0;     // Игнорировать чтение из памяти modrm
reg [1:0]   rep             = 1'b0;     // Режим REPNZ/REPZ
reg [2:0]   alu             = 3'h0;     // Режим АЛУ
reg         size            = 1'b0;     // =1 16/32 битный операнд
reg         dir             = 1'b0;     // =0 rm,r; =1 r,rm modrm
reg [ 2:0]  regn            = 3'b0;     // reg32 = register[regn]
reg [31:0]  op1             = 32'h0;    // Левый операнд
reg [31:0]  op2             = 32'h0;    // Правый операнд
reg [31:0]  wb              = 32'h0;    // Значение для записи
reg [31:0]  frametemp       = 32'h0;    // ENTER

reg         __opext         = 1'b0;
reg         __adsize        = 1'b0;
reg         __opsize        = 1'b0;
reg         __override      = 1'b0;
reg [1:0]   __rep           = 2'b00;
reg [15:0]  __segment       = 16'h0000;

// -----------------------------------------------------------------------------
// Модуль деления op1 / op2 -> divres | divrem
// -----------------------------------------------------------------------------

reg [63:0]  diva    = 1'b0;
reg [63:0]  divb    = 1'b0;
reg [ 6:0]  divcnt  = 1'b0;
reg [63:0]  divrem  = 1'b0;
reg [63:0]  divres  = 1'b0;
reg         signa   = 1'b0;
reg         signb   = 1'b0;

// -----------------------------------------------------------------------------

wire        signd   = signa ^ signb;
wire [63:0] mult    = op1 * op2;
wire [15:0] aam     = eax[15:8]*in + eax[7:0];
wire [63:0] _diva   = size ? (opsize ? {edx, eax} : {edx[15:0], eax[15:0], 32'h0}) : {eax[15:0], 48'h0};
wire [63:0] _divb   = size ? (opsize ? op1 : op1[15:0]) : op1[7:0];
wire [63:0] _divr   = {divrem, diva[63]};

// -----------------------------------------------------------------------------
// Вычисление следующего EIP в зависимости от 54-го бита
// По умолчанию процессор сразу же переходит в 32х битный режим работы
// -----------------------------------------------------------------------------

wire        defsize     = 1'b1;
wire        stacksize   = 1'b1;
wire [15:0] sp_dec      = esp[15:0] - (opsize ? 3'h4 : 2'h2);
wire [15:0] sp_inc      = esp[15:0] + (opsize ? 3'h4 : 2'h2);
wire [15:0] ipnext1     = eip[15:0] + 1'b1;
wire [15:0] ipnext2     = eip[15:0] + 2'h2;
wire [15:0] ipnext3     = eip[15:0] + 2'h3;
wire [15:0] ipnext5     = eip[15:0] + 3'h5;

// eip / esp
wire [31:0] eip_next    = defsize ? eip + 1'b1 : {eip[31:16], ipnext1};
wire [31:0] eip_next2   = defsize ? eip + 2'h2 : {eip[31:16], ipnext2};
wire [31:0] eip_next3   = defsize ? eip + 2'h3 : {eip[31:16], ipnext3};
wire [31:0] eip_next5   = defsize ? eip + 2'h3 : {eip[31:16], ipnext5};
wire [31:0] esp_dec     = defsize ? esp - 4'h4 : {esp[31:16], sp_dec};
wire [31:0] esp_inc     = defsize ? esp + 4'h4 : {esp[31:16], sp_inc};

// ---------------------------------------------------------------------
// Строковые инструкции, инкременты и декременты
// ---------------------------------------------------------------------

// Приращение +/- 1,2,4;
wire [ 2:0] str_inc     = t == fetch ?
    ((    in[0] ? (__opsize ? 3'h4 : 3'h2) : 3'h1)) :
    ((opcode[0] ? (  opsize ? 3'h4 : 3'h2) : 3'h1));

wire [31:0] str_ncx     = ecx - 1'b1;
wire [31:0] str_zcx     = defsize ? ecx : ecx[15:0];
wire [31:0] str_nsi     = eflags[DF] ? esi - str_inc : esi + str_inc;
wire [31:0] str_ndi     = eflags[DF] ? edi - str_inc : edi + str_inc;

// Следующий ESI:EDI:ECX
wire [31:0] str_esi     = defsize ? str_nsi : {esi[31:16], str_nsi[15:0]};
wire [31:0] str_edi     = defsize ? str_ndi : {edi[31:16], str_ndi[15:0]};
wire [31:0] str_ecx     = defsize ? str_ncx : {ecx[31:16], str_ncx[15:0]};

// ---------------------------------------------------------------------
// Получение регистров
// ---------------------------------------------------------------------

// Вычисление базы SIB
wire [31:0] sib_base =
    in[2:0] == 3'b000 ? eax :
    in[2:0] == 3'b001 ? ecx :
    in[2:0] == 3'b010 ? edx :
    in[2:0] == 3'b011 ? ebx :
    in[2:0] == 3'b100 ? esp :
    in[2:0] == 3'b101 ? (^modrm[7:6] ? ebp : 1'b0) :
    in[2:0] == 3'b110 ? esi :
                        edi;

// Извлечение регистра
wire [31:0] reg32 =
    regn == 3'd0 ? (opsize & size ? eax : (size ? eax[15:0] : eax[ 7:0])) :
    regn == 3'd1 ? (opsize & size ? ecx : (size ? ecx[15:0] : ecx[ 7:0])) :
    regn == 3'd2 ? (opsize & size ? edx : (size ? edx[15:0] : edx[ 7:0])) :
    regn == 3'd3 ? (opsize & size ? ebx : (size ? ebx[15:0] : ebx[ 7:0])) :
    regn == 3'd4 ? (opsize & size ? esp : (size ? esp[15:0] : eax[15:8])) :
    regn == 3'd5 ? (opsize & size ? ebp : (size ? ebp[15:0] : ecx[15:8])) :
    regn == 3'd6 ? (opsize & size ? esi : (size ? esi[15:0] : edx[15:8])) :
                   (opsize & size ? edi : (size ? edi[15:0] : ebx[15:8]));

// ---------------------------------------------------------------------
// Условные переходы
// ---------------------------------------------------------------------

wire [7:0] branches = {

    /*7*/ (eflags[SF] ^ eflags[OF]) | eflags[ZF],
    /*6*/ (eflags[SF] ^ eflags[OF]),
    /*5*/  eflags[PF],
    /*4*/  eflags[SF],
    /*3*/  eflags[CF] | eflags[ZF],
    /*2*/  eflags[ZF],
    /*1*/  eflags[CF],
    /*0*/  eflags[OF]
};

// ---------------------------------------------------------------------
// Арифметико-логика, базовая
// ---------------------------------------------------------------------

wire [32:0] alu_r =

    alu == alu_add ? op1 + op2 :
    alu == alu_or  ? op1 | op2 :
    alu == alu_adc ? op1 + op2 + eflags[CF] :
    alu == alu_sbb ? op1 - op2 - eflags[CF] :
    alu == alu_and ? op1 & op2:
    alu == alu_xor ? op1 ^ op2:
                     op1 - op2; // SUB, CMP

wire [ 4:0] alu_top = size ? (opsize ? 31 : 15) : 7;
wire [ 5:0] alu_up  = alu_top + 1'b1;

wire is_add  = alu == alu_add || alu == alu_adc;
wire is_lgc  = alu == alu_xor || alu == alu_and || alu == alu_or;
wire alu_cf  = alu_r[alu_up];
wire alu_af  = op1[4] ^ op2[4] ^ alu_r[4];
wire alu_sf  = alu_r[alu_top];
wire alu_zf  = size ? (opsize ? ~|alu_r[31:0] : ~|alu_r[15:0]) : ~|alu_r[7:0];
wire alu_pf  = ~^alu_r[7:0];
wire alu_of  = (op1[alu_top] ^ op2[alu_top] ^ is_add) & (op1[alu_top] ^ alu_r[alu_top]);

wire [17:0] alu_f = {

    /* ..  */ eflags[17:12],
    /* OF  */ alu_of & ~is_lgc,
    /* DIT */ eflags[10:8],
    /* SF  */ alu_sf,
    /* ZF  */ alu_zf,
    /* 5   */ 1'b0,
    /* AF  */ alu_af & ~is_lgc,
    /* 3   */ 1'b0,
    /* PF  */ alu_pf,
    /* 1   */ 1'b1,
    /* CF  */ alu_cf & ~is_lgc
};

// ---------------------------------------------------------------------
// Десятичная коррекция DAA, DAS, AAA, AAS
// ---------------------------------------------------------------------

reg         daa_a;
reg         daa_c;
reg         daa_x;
reg [8:0]   daa_i;
reg [7:0]   daa_h;
reg [15:0]  daa_r;
reg [11:0]  eflags_o;
reg [11:0]  eflags_d;

always @* begin

    daa_r    = eax[15:0];
    eflags_d = eflags;

    case (in[4:3])

        // DAA, DAS
        0, 1: begin

            daa_c = eflags[CF];
            daa_a = eflags[AF];
            daa_i = eax[7:0];

            // Младший ниббл
            if (eax[3:0] > 4'h9 || eflags[AF]) begin

                daa_i = in[3] ? eax[7:0] - 3'h6 : eax[7:0] + 3'h6;
                daa_c = daa_i[8];
                daa_a = 1'b1;

            end

            daa_r = daa_i[7:0];
            daa_x = daa_c;

            // Старший ниббл
            if (daa_c || daa_i[7:0] > 8'h9F) begin
                daa_r = in[3] ? daa_i[7:0] - 8'h60 : daa_i[7:0] + 8'h60;
                daa_x = 1'b1;
            end

            eflags_d[SF] =   daa_r[7];   // SF
            eflags_d[ZF] = ~|daa_r[7:0]; // ZF
            eflags_d[AF] =   daa_a;      // AF
            eflags_d[PF] = ~^daa_r[7:0]; // PF
            eflags_d[OF] =   daa_x;      // CF

        end

        // AAA, AAS
        2, 3: begin

            daa_i = eax[ 7:0];
            daa_r = eax[15:0];

            if (eflags[4] || eax[3:0] > 4'h9) begin

                daa_i = alu[0] ? eax[ 7:0] - 3'h6 : eax[ 7:0] + 3'h6;
                daa_h = alu[0] ? eax[15:8] - 1'b1 : eax[15:8] + 1'b1;
                daa_r = {daa_h, 4'h0, daa_i[3:0]};

                eflags_d[AF] = 1'b1;
                eflags_d[CF] = 1'b1;

            end
            else begin

                eflags_d[AF] = 1'b0;
                eflags_d[CF] = 1'b0;

            end

        end

    endcase

end

endmodule
