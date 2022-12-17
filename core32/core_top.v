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

    `include "core_proc.v"
    `include "core_exec.v"

endcase
end

`include "core_decl.v"
`include "core_alu.v"

endmodule
