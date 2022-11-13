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

// JCXZ
8'b1110_0011: if (cx) begin phi <= PREPARE; ip <= ip + 2; end

// LOOP, LOOPNZ, LOOPZ
8'b1110_000x,
8'b1110_0010: begin

    phi <= PREPARE;
    cx  <= cx - 1;

    // ZF=0/1 и CX != 0 (после декремента)
    if (((flags[ZF] == in[0]) || in[1]) && (cx != 1))
        phi <= EXEC;
    else
        ip <= ip + 2;

end
