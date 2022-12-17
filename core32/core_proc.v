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

