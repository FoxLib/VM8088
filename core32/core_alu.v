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
