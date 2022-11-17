// 00-3F АЛУ modrm
8'b00xx_x0xx: begin

    phi   <= (alu == ALU_CMP ? PREPARE : MODRM_WB);
    bus   <= (alu == ALU_CMP ? 1'b0 : bus);
    wb    <= ar;
    flags <= af;

end

// 00-3F АЛУ аккумулятор
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

// 07,0F,16,1F POP seg
8'b000x_x111: begin

    phi <= PREPARE;

    case (opcode[4:3])
    2'b00: es <= wb;
    2'b01: cs <= wb;
    2'b10: ss <= wb;
    2'b11: ds <= wb;
    endcase

end

// 40-4F INC/DEC
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

// 50-57 PUSH r
8'b0101_0xxx: begin wb <= r1; phi <= PUSH; end

// 58-5F POP r
8'b0101_1xxx: begin

    phi         <= MODRM_WB;
    phi_next    <= PREPARE;
    dir         <= 1'b1;
    size        <= 1'b1;
    modrm[5:3]  <= opcode[2:0];

end

// 68,6A PUSH i16, i8
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

// 80-83 ALU modrm
8'b1000_00xx: case (fn)

    // Обнуление BUS
    // Читать младший байт
    0: begin

        if (bus == 1'b0) begin

            fn  <= 1;
            bus <= 1'b0;
            op2 <= opcode[1:0] == 2'b11 ? {{8{in[7]}}, in} : in;
            fn  <= opcode[1:0] == 2'b01 ? 1 : 2;
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

// 84-85 TEST mrm
8'b1000_010x: begin phi <= PREPARE; flags <= af; bus <= 1'b0; end

// 86-87 XCHG mrm
8'b1000_011x: case (fn)

    0: begin wb <= op2; phi <= MODRM_WB; phi_next <= EXEC;    fn  <= 1; end
    1: begin wb <= op1; phi <= MODRM_WB; phi_next <= PREPARE; dir <= 0; end

endcase

// 88-8B MOV mrm
// 8D LEA
8'b1000_10xx,
8'b1000_1101: begin phi <= MODRM_WB; wb <= opcode[2] ? ea : op2; end

// 8F POP rm
8'b1000_1111: case (fn)

    0: begin fn  <= 1; phi <= MODRM; dir <= 1'b0; ignoreo <= 1'b1; end
    1: begin phi <= MODRM_WB; phi_next <= PREPARE; end

endcase

// 90-97 XCHG a, r
8'b1001_0xxx: begin

    phi <= MODRM_WB;
    ax  <= r1;
    dir <= 1'b1;
    wb  <= ax;
    modrm[5:3] <= regn;

end

// 9D POPF
8'b1001_1101: begin flags <= wb | 2'b10; phi <= PREPARE; end

// A0, A1 MOV a, [m16]
8'b1010_00xx: case (fn)

    // Считать адрес 16 бит
    0: begin ea[ 7:0] <= in; ip <= ip + 1; fn <= 1; end
    1: begin

        fn      <= 2;
        bus     <= 1;
        ip      <= ip + 1;

        wb      <= ax;
        dir     <= 0;
        modrm   <= 0;
        ea[15:8] <= in;

        if (opcode[1]) phi <= MODRM_WB;

    end

    // Запись в AL/AX
    2: begin

        fn  <= 3;
        ax  <= in;
        ea  <= ea + 1;

        if (size == 1'b0) begin phi <= PREPARE; bus <= 0; end

    end

    3: begin ax[15:8] <= in; phi <= PREPARE; bus <= 0; end

endcase

// A8-A9 TEST al, imm
8'b1010_100x: case (fn)

    0: begin

        fn  <= size ? 1 : 2;
        alu <= ALU_AND;
        op1 <= ax;
        op2 <= in;
        ip  <= ip + 1;

    end

    1: begin fn <= 2; op2[15:8] <= in; ip <= ip + 1; end
    2: begin

        phi   <= PREPARE;
        flags <= af;

    end

endcase

// B0-BF MOV r, imm
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

// C0,C1 SHIFT imm8
8'b1100_000x: case (fn)

    0: begin bus <= 1'b0; fn  <= 1; end
    1: begin bus <= 1'b1; op2 <= in[4:0]; alu <= modrm[5:3]; phi <= SHIFT; end

endcase

// C6,C7 MOV mrm, i
8'b1100_011x: case (fn)

    // BYTE
    0: begin

        if (bus == 1'b0) begin

            fn <= 1;
            wb <= in;
            ip <= ip + 1;

            if (size == 1'b0) begin

                phi <= MODRM_WB;
                bus <= 1'b1;

            end

        end

        bus <= 1'b0;

    end

    // WORD
    1: begin

        wb[15:8] <= in;
        ip  <= ip + 1;
        phi <= MODRM_WB;
        bus <= 1'b1;

    end

endcase

// D0-D4 *SHIFT* rm, (1|cl)
8'b1101_00xx: begin op2 <= opcode[1] ? cx[4:0] : 1; alu <= modrm[5:3]; phi <= SHIFT; end

// 70-7F Jccc
// E0-E3 LOOP(Z,NZ) JCXZ
// EB    JMP short
8'b0111_xxxx,
8'b1110_00xx,
8'b1110_1011: begin

    phi <= PREPARE;
    ip  <= ip + {{8{in[7]}}, in} + 1'b1;

end
