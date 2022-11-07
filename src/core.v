/* >> HELLO WORLD << */

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
reg [15:0]  ax = 16'h0000;
reg [15:0]  cx = 16'h0000;
reg [15:0]  dx = 16'h0000;
reg [15:0]  bx = 16'h0000;
reg [15:0]  sp = 16'h0000;
reg [15:0]  bp = 16'h0000;
reg [15:0]  si = 16'h0000;
reg [15:0]  di = 16'h0000;
// ---------------------------------------------------------------------
reg [15:0]  es = 16'h0000;
reg [15:0]  cs = 16'h0000;
reg [15:0]  ss = 16'h0000;
reg [15:0]  ds = 16'h0000;
// ---------------------------------------------------------------------
reg         bus     = 1'b0;
reg [15:0]  seg     = 16'h0000;          // Текущий выбранный сегмент
reg [15:0]  ea      = 16'h0000;          // Эффективный адрес
reg [ 5:0]  phi     = 1'b0;              // Фаза выполнения
reg [ 2:0]  alu     = 3'h0;
reg [15:0]  op1     = 16'h0000;
reg [15:0]  op2     = 16'h0000;
reg [ 7:0]  opcode  = 8'h00;             // Сохраненный опкод
reg [ 7:0]  modrm   = 8'h00;
reg         size    = 1'b0;
reg         dir     = 1'b0;
// ---------------------------------------------------------------------
reg [15:0]  ip      = 16'h0000;
reg [11:0]  flags   = 12'b0000_0000_0000;
// ---------------------------------------------------------------------
reg         o_seg   = 1'b0;
reg         o_seg_  = 1'b0;
reg [1:0]   o_rep   = 2'h0;
reg [1:0]   o_rep_  = 2'h0;
// ---------------------------------------------------------------------
reg [1:0]   src1    = 2'b00;
reg [1:0]   src2    = 2'b00;
reg [2:0]   regn    = 3'b000; // Данные из номера регистра
// ---------------------------------------------------------------------

localparam

    PREPARE         = 0,
    MODRM           = 1;

localparam

    SRC_I20     = 2'b00,
    SRC_I53     = 2'b01,
    SRC_REG     = 2'b10;

// Выбор источника регистров
// ---------------------------------------------------------------------
wire [ 2:0] r1n =   src1 == SRC_I20 ? in[2:0] :
                    src1 == SRC_I53 ? in[5:3] :
                                        regn;
wire [ 2:0] r2n =   src2 == SRC_I20 ? in[2:0] :
                    src2 == SRC_I53 ? in[5:3] :
                                        regn;

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

always @(posedge clock)
// Сброс процессора
if (reset_n == 1'b0) begin

    ip      <= 16'hFFF0;
    cs      <= 16'hF000;
    phi     <= 1'b0;
    o_seg_  <= 1'b0;
    o_rep_  <= 2'h0;

end
// Операции процессора разрешены
else if (locked) case (phi)

// ~=~=~= Считывание префиксов и опкода ~=~=~=
PREPARE: begin

    we      <= 1'b0;
    ip      <= ip + 1'b1;
    src1    <= SRC_I20; // Источник op1 modrm
    src2    <= SRC_I53; // Источник op2 modrm
    size    <= in[0];
    dir     <= in[1];
    regn    <= in[2:0];
    alu     <= in[5:3];

    case (in)

    // Префиксы
    8'h26: begin o_seg_ <= 1'b1; seg <= es; end
    8'h2E: begin o_seg_ <= 1'b1; seg <= cs; end
    8'h36: begin o_seg_ <= 1'b1; seg <= ss; end
    8'h3E: begin o_seg_ <= 1'b1; seg <= ds; end
    8'hF2: begin o_rep_ <= {1'b1, in[0]}; end

    // Не реализованные префиксы, не нужные никому
    8'hF0, 8'h64, 8'h65, 8'h66, 8'h67: begin end

    // Опкоды, первый такт
    default: begin

        // Защелкивание префиксов и опкода на будущее
        opcode <= in;
        o_seg  <= o_seg_; o_seg_ <= 1'h0;
        o_rep  <= o_rep_; o_rep_ <= 2'h0;

        if (!o_seg_) seg <= ds;

        casex (in)

        // Базовый АЛУ
        8'b00xx_x0xx: begin phi <= MODRM; end

        endcase

    end
    endcase

end

// ~=~=~= Раскодирование байта ModRM ~=~=~=
MODRM: begin

    ip      <= ip + 1;
    modrm   <= in;
    op1     <= dir ? r2 : r1;
    op2     <= dir ? r1 : r2;

end

endcase



endmodule
