#include "disasm.h"

class Disassemble {

protected:

    int     eip;
    int     reg, mod, rm;
    char    tmps[256];
    char    dis_rg[32];        // Rm-часть Modrm
    char    dis_rm[32];        // Rm-часть Modrm
    char    dis_px[32];        // Префикс
    int     max_memory;
    unsigned char* memory;

public:

    // Непосредственный доступ
    char    dis_row[256];

    Disassemble(unsigned char* _mem) {

        memory = _mem;
        max_memory = 0xfffff;
    }

    int readb(int address) {
        return memory[address & max_memory];
    }

    int fetchb() {

        int a = readb(eip);
        eip = (eip + 1) & 0xfffff;
        return a;
    }

    int fetchw() { int a = fetchb(); int b = fetchb(); return b*256 + a; }
    int fetchd() { int a = fetchw(); int b = fetchw(); return b*65536 + a; }

    // Дизассемблирование modrm
    int disas_modrm(int reg32, int mem32) {

        int n = 0, b, w;

        /* Очистка */
        dis_rg[0] = 0;
        dis_rm[0] = 0;

        b = fetchb(); n++;

        rm  = (b & 0x07);
        reg = (b & 0x38) >> 3;
        mod = (b & 0xc0);

        /* Печать регистра 8/16/32 */
        switch (reg32) {
            case 0x08: sprintf(dis_rg, "%s", regnames[ reg ]); break;
            case 0x10: sprintf(dis_rg, "%s", regnames[ reg + 0x08 ]); break;
            case 0x20: sprintf(dis_rg, "%s", regnames[ reg + 0x10 ]); break;
            default:   sprintf(dis_rg, "<unknown>"); break;
        }

        // 16 бит
        if (mem32 == 0) {

            /* Rm-часть */
            switch (mod) {

                /* Индекс без disp или disp16 */
                case 0x00:

                    if (rm == 6) {
                        w = fetchw(); n += 2;
                        sprintf(dis_rm, "[%s%04x]", dis_px, w);
                    } else {
                        sprintf(dis_rm, "[%s%s]", dis_px, rm16names[ rm ]);
                    }

                    break;

                /* + disp8 */
                case 0x40:

                    b = fetchb(); n++;
                    if (b & 0x80) {
                        sprintf(dis_rm, "[%s%s-%02x]", dis_px, rm16names[ rm ], (0xff ^ b) + 1);
                    } else if (b == 0) {
                        sprintf(dis_rm, "[%s%s]", dis_px, rm16names[ rm ]);
                    } else {
                        sprintf(dis_rm, "[%s%s+%02x]", dis_px, rm16names[ rm ], b);
                    }

                    break;

                /* + disp16 */
                case 0x80:

                    w = fetchw(); n += 2;
                    if (w & 0x8000) {
                        sprintf(dis_rm, "[%s%s-%04x]", dis_px, rm16names[ rm ], (0xFFFF ^ w) + 1);
                    } else if (w == 0) {
                        sprintf(dis_rm, "[%s%s]", dis_px, rm16names[ rm ]);
                    } else {
                        sprintf(dis_rm, "[%s%s+%04x]", dis_px, rm16names[ rm ], w);
                    }

                    break;

                /* Регистровая часть */
                case 0xc0:

                    switch (reg32) {
                        case 0x08: sprintf(dis_rm, "%s", regnames[ rm ]); break;
                        case 0x10: sprintf(dis_rm, "%s", regnames[ rm + 0x08 ]); break;
                        case 0x20: sprintf(dis_rm, "%s", regnames[ rm + 0x10 ]); break;
                    }

                    break;
            }
        }
        // 32 бит
        else {

            int sib = 0, sibhas = 0;

            switch (mod) {

                case 0x00:

                    if (rm == 5) {

                        w = fetchd(); n += 4;
                        sprintf(dis_rm, "[%s%08x]", dis_px, w);

                    } else if (rm == 4) { /* SIB */

                        sib = fetchb(); n++;
                        sibhas = 1;

                    } else {
                        sprintf(dis_rm, "[%s%s]", dis_px, regnames[0x10 + rm]);
                    }

                    break;

                /* + disp8 */
                case 0x40:


                    if (rm == 4) {

                        sib = fetchb(); n++;
                        sibhas = 1;

                    } else {

                        b = fetchb(); n++;

                        if (b & 0x80) {
                            sprintf(dis_rm, "[%s%s-%02x]", dis_px, regnames[ 0x10 + rm ], (0xff ^ b) + 1);
                        } else if (b == 0) {
                            sprintf(dis_rm, "[%s%s]", dis_px, regnames[ 0x10 + rm ]);
                        } else {
                            sprintf(dis_rm, "[%s%s+%02x]", dis_px, regnames[ 0x10 + rm ], b);
                        }
                    }

                    break;

                /* + disp32 */
                case 0x80:


                    if (rm == 4) {

                        sib = fetchb(); n++;
                        sibhas = 1;

                    } else {

                        w = fetchd(); n += 4;

                        if (w & 0x80000000) {
                        sprintf(dis_rm, "[%s%s-%04x]", dis_px, regnames[ 0x10 + rm ], (0xFFFFFFFF ^ w) + 1);
                        } else if (w == 0) {
                            sprintf(dis_rm, "[%s%s]", dis_px, regnames[ 0x10 + rm ]);
                        } else {
                            sprintf(dis_rm, "[%s%s+%04x]", dis_px, regnames[ 0x10 + rm ], w);
                        }
                    }

                    break;

                // Регистровая часть
                case 0xc0:

                    switch (reg32) {
                        case 0x08: sprintf(dis_rm, "%s", regnames[ rm ]); break;
                        case 0x10: sprintf(dis_rm, "%s", regnames[ rm + 0x08 ]); break;
                        case 0x20: sprintf(dis_rm, "%s", regnames[ rm + 0x10 ]); break;
                    }

                    break;
            }

            // Имеется байт SIB
            if (sibhas) {

                char cdisp32[16]; cdisp32[0] = 0;

                int disp = 0;
                int sib_ss = (sib & 0xc0);
                int sib_ix = (sib & 0x38) >> 3;
                int sib_bs = (sib & 0x07);

                /* Декодирование Displacement */
                switch (mod) {

                    case 0x40:

                        disp = fetchb(); n += 1;

                        if (disp & 0x80) {
                            sprintf(cdisp32, "-%02X", (disp ^ 0xff) + 1);
                        } else {
                            sprintf(cdisp32, "+%02X", disp);
                        }

                        break;

                   case 0x80:
                   case 0xc0:

                        disp = fetchd(); n += 4;
                        if (disp & 0x80000000) {
                            sprintf(cdisp32, "-%08X", (disp ^ 0xffffffff) + 1);
                        } else {
                            sprintf(cdisp32, "+%08X", disp);
                        }
                        break;
                }

                /* Декодирование Index */
                if (sib_ix == 4) {

                    sprintf(dis_rm, "[%s%s]", dis_px, regnames[ 0x10 + sib_bs ]);

                } else {

                    switch (sib_ss) {

                        case 0x00:

                            sprintf(dis_rm, "[%s%s+%s]", dis_px, regnames[ 0x10 + sib_bs ], regnames[ 0x10 + sib_ix ]);
                            break;

                        case 0x40:

                            sprintf(dis_rm, "[%s%s+2*%s%s]", dis_px, regnames[ 0x10 + sib_bs ], regnames[ 0x10 + sib_ix ], cdisp32);
                            break;

                        case 0x80:

                            sprintf(dis_rm, "[%s%s+4*%s%s]", dis_px, regnames[ 0x10 + sib_bs ], regnames[ 0x10 + sib_ix ], cdisp32);
                            break;

                        case 0xc0:

                            sprintf(dis_rm, "[%s%s+8*%s%s]", dis_px, regnames[ 0x10 + sib_bs ], regnames[ 0x10 + sib_ix ], cdisp32);
                            break;
                    }
                }
            }
        }

        return n;
    }

    // Дизассемблировать строку
    int disassemble(int address) {

        eip = address & max_memory;

        int  ereg = 1;
        int  emem = 1;
        int  stop = 0;
        char dis_pf[8];
        char dis_cmd [32];
        char dis_cmd2[64];
        char dis_ops[128];
        char dis_dmp[128];
        char dis_sfx[8];

        int n = 0, i, j, d, opcode = 0;
        int elock = 0;

        // Очистить префикс
        dis_px[0]  = 0; // Сегментный префикс
        dis_pf[0]  = 0; // Префикс
        dis_ops[0] = 0; // Операнды
        dis_dmp[0] = 0; // Минидамп
        dis_sfx[0] = 0; // Суффикс

        /* Декодирование префиксов (до 6 штук) */
        for (i = 0; i < 6; i++) {

            d = fetchb();
            n++;

            switch (d) {
                case 0x0F: opcode |= 0x100; break;
                case 0x26: sprintf(dis_px, "%s", "es:"); break;
                case 0x2E: sprintf(dis_px, "%s", "cs:"); break;
                case 0x36: sprintf(dis_px, "%s", "ss:"); break;
                case 0x3E: sprintf(dis_px, "%s", "ss:"); break;
                case 0x64: sprintf(dis_px, "%s", "fs:"); break;
                case 0x65: sprintf(dis_px, "%s", "gs:"); break;
                case 0x66: ereg = ereg ^ 1; break;
                case 0x67: emem = emem ^ 1; break;
                case 0xf0: elock = 1; break;
                case 0xf2: sprintf(dis_pf, "%s", "repnz "); break;
                case 0xf3: sprintf(dis_pf, "%s", "rep "); break;
                default:   opcode |= d; stop = 1; break;
            }

            if (stop) break;
        }

        int opdec    = ops[ opcode & 255 ];
        int hasmodrm = modrm_lookup[ opcode ];

        // Типичная мнемоника
        if (opdec != 0xff) {
            sprintf(dis_cmd, "%s", mnemonics[ opdec ] );
        }

        // Байт имеет modrm
        if (hasmodrm) {

            // Размер по умолчанию 8 бит, если opcode[0] = 1, то либо 16, либо 32
            int regsize = opcode & 1 ? (ereg ? 32 : 16) : 8;
            int swmod   = opcode & 2; // Обмен местами dis_rm и dis_rg

            if (opcode == /* BOUND */ 0x62) regsize = (ereg ? 32 : 16);

            // SWmod
            if (opcode == /* ARPL */ 0x63) swmod = 0;
            if (opcode == /* LEA */ 0x8D || opcode == 0xC4 /* LES */ || opcode == 0xC5) swmod = 1;

            // Regsize
            if (opcode == /* SREG */ 0x8C || opcode == 0x8E ||
                opcode == /* LES */ 0xC4) regsize = (ereg ? 32 : 16);

            // Получить данные из modrm
            n += disas_modrm(regsize, emem ? 0x20 : 0x00);

            // GRP-1 8
            if (opcode == 0x80 || opcode == 0x82) {

                sprintf(dis_cmd, "%s", mnemonics[ reg ]  );
                sprintf(dis_ops, "%s, %02X", dis_rm, fetchb()); n++;
            }

            // GRP-1 16/32
            else if (opcode == 0x81) {

                sprintf(dis_cmd, "%s", mnemonics[ reg ]  );

                if (ereg) {
                    sprintf(dis_ops, "%s, %08X", dis_rm, fetchd()); n += 4;
                } else {
                    sprintf(dis_ops, "%s, %04X", dis_rm, fetchw()); n += 2;
                }
            }

            // GRP-1 16/32: Расширение 8 бит до 16/32
            else if (opcode == 0x83) {

                int b8 = fetchb(); n++;
                sprintf(dis_cmd, "%s", mnemonics[ reg ]  );

                if (ereg) {
                    sprintf(dis_ops, "%s, %08X", dis_rm, b8 | (b8 & 0x80 ? 0xFFFFFF00 : 0));
                } else {
                    sprintf(dis_ops, "%s, %04X", dis_rm, b8 | (b8 & 0x80 ? 0xFF00 : 0));
                }
            }

            // IMUL imm16
            else if (opcode == 0x69) {

                if (ereg) {
                    sprintf(dis_ops, "%s, %s, %08X", dis_rg, dis_rm, fetchd() ); n += 4;
                } else {
                    sprintf(dis_ops, "%s, %s, %04X", dis_rg, dis_rm, fetchw() ); n += 2;
                }
            }
            // Групповые инструкции #2: Byte
            else if (opcode == 0xF6) {

                sprintf(dis_cmd, "%s", grp2[ reg ]  );
                if (reg < 2) { /* TEST */
                    sprintf(dis_ops, "%s, %02X", dis_rm, fetchb() ); n++;
                } else {
                    sprintf(dis_ops, "%s", dis_rm);
                }
            }

            // Групповые инструкции #2: Word/Dword
            else if (opcode == 0xF7) {

                sprintf(dis_cmd, "%s", grp2[ reg ]  );

                if (reg < 2) { /* TEST */
                    if (ereg) {
                        sprintf(dis_ops, "%s, %08X", dis_rm, fetchd() ); n += 4;
                    } else {
                        sprintf(dis_ops, "%s, %04X", dis_rm, fetchw() ); n += 2;
                    }
                } else {
                    sprintf(dis_ops, "%s", dis_rm);
                }
            }

            // Групповые инструкции #3: Byte
            else if (opcode == 0xFE) {

                if (reg < 2) {
                    sprintf(dis_cmd, "%s", grp3[ reg ]  );
                    sprintf(dis_ops, "byte %s", dis_rm );
                } else {
                    sprintf(dis_cmd, "(unk)");
                }
            }
            // Групповые инструкции #3: Word / Dword
            else if (opcode == 0xFF) {

                sprintf(dis_cmd, "%s", grp3[ reg ]  );
                sprintf(dis_ops, "%s %s", ereg ? "dword" : "word", dis_rm );

            }

            // Сегментные и POP r/m
            else if (opcode == 0x8C) { sprintf(dis_ops, "%s, %s", dis_rm, regnames[ 0x18 + reg ] ); }
            else if (opcode == 0x8E) { sprintf(dis_ops, "%s, %s", regnames[ 0x18 + reg ], dis_rm ); }
            else if (opcode == 0x8F) { sprintf(dis_ops, "%s %s", ereg ? "dword" : "word", dis_rm ); }

            // GRP-2: imm
            else if (opcode == 0xC0 || opcode == 0xC1) {
                sprintf(dis_cmd, "%s", mnemonics[ 0x66 + reg ]);
                sprintf(dis_ops, "%s, %02X", dis_rm, fetchb()); n++;
            }
            // 1
            else if (opcode == 0xD0 || opcode == 0xD1) {
                sprintf(dis_cmd, "%s", mnemonics[ 0x66 + reg ]);
                sprintf(dis_ops, "%s, 1", dis_rm);
            }
            // cl
            else if (opcode == 0xD2 || opcode == 0xD3) {
                sprintf(dis_cmd, "%s", mnemonics[ 0x66 + reg ]);
                sprintf(dis_ops, "%s, cl", dis_rm);
            }
            // mov r/m, i8/16/32
            else if (opcode == 0xC6) {
                sprintf(dis_ops, "%s, %02X", dis_rm, fetchb()); n++;
            }
            else if (opcode == 0xC7) {
                if (ereg) {
                    sprintf(dis_ops, "%s, %08X", dis_rm, fetchd()); n += 4;
                } else {
                    sprintf(dis_ops, "%s, %04X", dis_rm, fetchw()); n += 2;
                }
            }
            // Обычные
            else {
                sprintf(dis_ops, "%s, %s", swmod ? dis_rg : dis_rm, swmod ? dis_rm : dis_rg);
            }

        } else {

            // [00xx_x10x] АЛУ AL/AX/EAX, i8/16/32
            if ((opcode & 0b11000110) == 0b00000100) {

                if ((opcode & 1) == 0) { // 8 bit
                    sprintf(dis_ops, "al, %02X", fetchb()); n++;
                } else if (ereg == 0) { // 16 bit
                    sprintf(dis_ops, "ax, %04X", fetchw()); n += 2;
                } else {
                    sprintf(dis_ops, "eax, %08X", fetchd()); n += 4;
                }
            }

            // [000x x11x] PUSH/POP
            else if ((opcode & 0b11100110) == 0b00000110) {
                sprintf(dis_ops, "%s", regnames[0x18 + ((opcode >> 3) & 3)] );
            }

            // [0100_xxxx] INC/DEC/PUSH/POP
            else if ((opcode & 0b11100000) == 0b01000000) {
                sprintf(dis_ops, "%s", regnames[ (ereg ? 0x10 : 0x08) + (opcode & 7)] );
            }
            else if (opcode == 0x60 && ereg) { sprintf(dis_cmd, "pushad"); }
            else if (opcode == 0x61 && ereg) { sprintf(dis_cmd, "popad"); }

            // PUSH imm16/32
            else if (opcode == 0x68) {

                if (ereg) {
                    sprintf(dis_ops, "%08X", fetchd()); n += 4;
                } else {
                    sprintf(dis_ops, "%04X", fetchw()); n += 2;
                }
            }
            // PUSH imm8
            else if (opcode == 0x6A) { int t = fetchb(); sprintf(dis_ops, "%04X", t | ((t & 0x80) ? 0xFF00 : 0)); n++; }
            // Jccc rel8
            else if (((opcode & 0b11110000) == 0b01110000) || (opcode >= 0xE0 && opcode <= 0xE3) || (opcode == 0xEB)) {
                int br = fetchb(); n++;
                sprintf(dis_ops, "%08X", (br & 0x80 ? (eip + br - 256) : eip + br ));
            }
            else if (opcode == 0x6c) sprintf(dis_cmd, "insb");
            else if (opcode == 0x6d) sprintf(dis_cmd, ereg ? "insd" : "insw");
            else if (opcode == 0x6e) sprintf(dis_cmd, "outsb");
            else if (opcode == 0x6f) sprintf(dis_cmd, ereg ? "outsd" : "outsw");
            // XCHG ax, r16/32
            else if (opcode > 0x90 && opcode <= 0x97) {
                if (ereg) {
                    sprintf(dis_ops, "eax, %s", regnames[ 0x10 + (opcode & 7) ] );
                } else {
                    sprintf(dis_ops, "ax, %s", regnames[ 0x8 + (opcode & 7) ] );
                }
            }
            else if (opcode == 0x98 && ereg) sprintf(dis_cmd, "cwde");
            else if (opcode == 0x99 && ereg) sprintf(dis_cmd, "cdq");

            // CALLF/JMPF
            else if (opcode == 0x9A || opcode == 0xEA) {

                int dw = ereg ? fetchd() : fetchw();
                n += (ereg ? 4 : 2);

                int sg = fetchw();
                n += 2;

                if (ereg) sprintf(dis_ops, "%04X:%08X", sg, dw);
                    else  sprintf(dis_ops, "%04X:%04X", sg, dw);
            }
            // MOV
            else if (opcode == 0xA0) { sprintf(dis_ops, "al, [%04X]", fetchw()); n += 2; }
            else if (opcode == 0xA1) { sprintf(dis_ops, "ax, [%04X]", fetchw()); n += 2; }
            else if (opcode == 0xA2) { sprintf(dis_ops, "[%04X], al", fetchw()); n += 2; }
            else if (opcode == 0xA3) { sprintf(dis_ops, "[%04X], ax", fetchw()); n += 2; }
            else if (opcode == 0xA8) { sprintf(dis_ops, "al, %02X", fetchb()); n++; }
            // TEST
            else if (opcode == 0xA9) {
                if (ereg) {
                    sprintf(dis_ops, "eax, %08X", fetchd()); n += 4;
                } else {
                    sprintf(dis_ops, "ax, %04X", fetchw()); n += 2;
                }
            }
            else if ((opcode >= 0xA4 && opcode <= 0xA7) || (opcode >= 0xAA && opcode <= 0xAF)) {
                sprintf(dis_sfx, opcode&1 ? (ereg ? "d" : "w") : "b");
            }
            else if (opcode >= 0xB0 && opcode <= 0xB7) {
                sprintf(dis_ops, "%s, %02x", regnames[ opcode & 7 ], fetchb()); n++;
            }
            else if (opcode >= 0xB8 && opcode <= 0xBF) {
                if (ereg) {
                    sprintf(dis_ops, "%s, %08x", regnames[ 0x10 + (opcode & 7) ], fetchd()); n += 4;
                } else {
                    sprintf(dis_ops, "%s, %04x", regnames[ 0x08 + (opcode & 7) ], fetchw()); n += 2;
                }
            }
            // RET / RETF
            else if (opcode == 0xc2 || opcode == 0xca) {
                sprintf(dis_ops, "%04X", fetchw()); n += 2;
            }
            // ENTER
            else if (opcode == 0xC8) {

                int aa = fetchw();
                int ab = fetchb();
                sprintf(dis_ops, "%04x, %02X", aa, ab); n += 3;
            }
            // INT
            else if (opcode == 0xCD) { sprintf(dis_ops, "%02X", fetchb()); n++; }
            // IO/OUT
            else if (opcode == 0xE4) { sprintf(dis_ops, "al, %02X", fetchb()); n++; }
            else if (opcode == 0xE5) { sprintf(dis_ops, "%s, %02X", ereg ? "eax" : "ax", fetchb()); n++; }
            else if (opcode == 0xE6) { sprintf(dis_ops, "%02X, al", fetchb()); n++; }
            else if (opcode == 0xE7) { sprintf(dis_ops, "%02X, %s", fetchb(), ereg ? "eax" : "ax"); n++; }
            else if (opcode == 0xEC) { sprintf(dis_ops, "al, dx"); }
            else if (opcode == 0xED) { sprintf(dis_ops, "%s, dx", ereg ? "eax" : "ax"); }
            else if (opcode == 0xEE) { sprintf(dis_ops, "dx, al"); }
            else if (opcode == 0xEF) { sprintf(dis_ops, "dx, %s", ereg ? "eax" : "ax"); }
            // CALL / JMP rel16
            else if (opcode == 0xE8 || opcode == 0xE9) {
                if (ereg) {

                    int m = fetchd(); n += 4;
                        m = (m & 0x80000000) ? m - 0x100000000 : m;
                    sprintf(dis_ops, "%08X", m);

                } else {
                    int m = fetchw(); n += 2;
                        m = (m & 0x8000) ? m - 0x10000 : m;
                    sprintf(dis_ops, "%04X", m + (eip & 0xffff));
                }
            }
        }

        // Максимальное кол-во байт должно быть не более 6
        for (i = 0; i < 6; i++) {
            if (i == 5 && n > 5) {
                sprintf(dis_dmp + 2*i, "..");
            } else if (i < n) {
                sprintf(dis_dmp + 2*i, "%02X", readb(address + i));
            } else {
                sprintf(dis_dmp + 2*i, "  ");
            }
        }

        // Суффикс команды
        sprintf(dis_cmd2, "%s%s", dis_cmd, dis_sfx);

        // Дополнить пробелами мнемонику
        for (i = 0; i < 8; i++) {
            if (dis_cmd2[i] == 0) {
                for (j = i; j < 8; j++) {
                    dis_cmd2[j] = ' ';
                }
                dis_cmd2[8 - 1] = 0;
                break;
            }
        }

        // Формирование строки вывода
        // Дамп инструкции, команда, операнды
        sprintf(dis_row, "%s %s%s%s %s", dis_dmp, elock ? "lock " : "", dis_pf, dis_cmd2, dis_ops);
        return n;
    }
};
