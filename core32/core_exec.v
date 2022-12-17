exec: casex (opcode)

    // E9      JMP near
    // 180-18C J<ccc> near
    9'b0_1110_1001,
    9'b1_1000_xxxx: begin

        t <= fetch;

        if (opsize) eip       <= eip       + wb;
        else        eip[15:0] <= eip[15:0] + wb[15:0];

    end

    // CMOV<cc> r, rm
    9'b1_0100_xxxx: begin

        if (branches[ opcode[3:1] ] != opcode[0]) begin

            t  <= modrm_wb;
            wb <= op2;

        end else begin src <= 0; t <= fetch; end

    end

    // SET<cc> rm8
    9'b1_1001_xxxx: begin

        t  <= modrm_wb;
        wb <= branches[ opcode[3:1] ] != opcode[0] ? 1'b1 : 1'b0;

    end

    // MOV[ZS]X reg, rm
    9'b1_1011_x11x: begin

        t <= modrm_wb;

        if (opcode[2])
             wb <= opcode[0] ? {{16{op2[15]}}, op2[15:0]} : {{24{op2[7]}}, op2[7:0]}; // SX
        else wb <= opcode[0] ?                 op2[15:0]  :                op2[7:0];  // ZX

    end

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

    // UNEXPECTED INSTRUCTION
    default: begin end

endcase
