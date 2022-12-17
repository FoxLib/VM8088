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

