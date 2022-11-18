/* verilator lint_off WIDTH */
/* verilator lint_off CASEINCOMPLETE */

module vcard
(
    input               clock,
    output  reg [ 3:0]  r,
    output  reg [ 3:0]  g,
    output  reg [ 3:0]  b,
    output              hs,
    output              vs,
    input               cga,            // Режим CGA
    input       [10:0]  cursor,
    output  reg [13:0]  cga_address,
    input       [ 7:0]  cga_data,
    output  reg [12:0]  txt_address,
    inout       [ 7:0]  txt_data
);

// ---------------------------------------------------------------------
// Тайминги для горизонтальной|вертикальной развертки (640x400)
// ---------------------------------------------------------------------
parameter
    hz_visible = 640, vt_visible = 400,
    hz_front   = 16,  vt_front   = 12,
    hz_sync    = 96,  vt_sync    = 2,
    hz_back    = 48,  vt_back    = 35,
    hz_whole   = 800, vt_whole   = 449;
// ---------------------------------------------------------------------
assign hs = x  < (hz_back + hz_visible + hz_front); // NEG.
assign vs = y >= (vt_back + vt_visible + vt_front); // POS.
// ---------------------------------------------------------------------
wire   xmax  = (x == hz_whole - 1);
wire   ymax  = (y == vt_whole - 1);
wire   shown =  x >= hz_back && x < hz_visible + hz_back &&
                y >= vt_back && y < vt_visible + vt_back;
// ---------------------------------------------------------------------
reg  [ 9:0] x;
reg  [ 8:0] y;
wire [ 9:0] X = (x - hz_back + 8);
wire [ 8:0] Y = (y - vt_back);
// ---------------------------------------------------------------------
reg  [11:0] color;
reg  [ 7:0] tdata;
reg  [ 7:0] rattr;
reg  [ 7:0] rmask;
reg  [23:0] timer;
reg         flash;

// Текущее положение курсора
wire [10:0] cid = X[9:3] + 80*Y[8:4];

// Курсор всегда одного вида
wire        cursor_shape = Y[3:1] == 3'b111;
wire        cursor_hit   = cid == (cursor + 1'b1);

wire [ 3:0] pix = rmask[ ~X[2:0] ] || (cursor_shape && cursor_hit && !flash) ? rattr[3:0] : rattr[7:4];
wire [11:0] txt_color =

    pix == 4'h0 ? 12'h111 : // 0 Черный (почти)
    pix == 4'h1 ? 12'h008 : // 1 Синий (темный)
    pix == 4'h2 ? 12'h080 : // 2 Зеленый (темный)
    pix == 4'h3 ? 12'h088 : // 3 Бирюзовый (темный)
    pix == 4'h4 ? 12'h800 : // 4 Красный (темный)
    pix == 4'h5 ? 12'h808 : // 5 Фиолетовый (темный)
    pix == 4'h6 ? 12'h880 : // 6 Коричневый
    pix == 4'h7 ? 12'hCCC : // 7 Серый -- тут что-то не то
    pix == 4'h8 ? 12'h888 : // 8 Темно-серый
    pix == 4'h9 ? 12'h00F : // 9 Синий (темный)
    pix == 4'hA ? 12'h0F0 : // 10 Зеленый
    pix == 4'hB ? 12'h0FF : // 11 Бирюзовый
    pix == 4'hC ? 12'hF00 : // 12 Красный
    pix == 4'hD ? 12'hF0F : // 13 Фиолетовый
    pix == 4'hE ? 12'hFF0 : // 14 Желтый
                  12'hFFF;  // 15 Белый

// Один из цветов в байте
wire [1:0] id = {cga_data[{X[2:1], 1'b1}], cga_data[{X[2:1], 1'b0}]};

// Конвертирование цвета
wire [11:0] cl =
    id == 2'b00 ? 12'h111 :
    id == 2'b01 ? 12'hC0C :
    id == 2'b10 ? 12'h0CC :
                  12'hCCC;

always @(posedge clock) begin

    {r, g, b} <= 12'h000;

    // Кадровая развертка
    x <= xmax ?         0 : x + 1;
    y <= xmax ? (ymax ? 0 : y + 1) : y;

    if (cga) begin

        case (X[0])

        1'b0: cga_address <= Y[8:1] + X[8:3];
        1'b1: color <= cl;

        endcase

        if (shown) {r, g, b} <= color;

    end else begin

        case (X[2:0])

        3'h0: begin txt_address     <= {cid, 1'b0}; end
        3'h1: begin txt_address[0]  <=  1'b1; tdata <= txt_data; end
        3'h2: begin txt_address     <= {1'b1, tdata, Y[3:0]}; tdata <= txt_data; end
        3'h7: begin rmask <= txt_data; rattr <= tdata; end

        endcase

        if (shown) {r, g, b} <= txt_color;

    end

end

// Каждые 0,5 секунды перебрасывается регистр flash
always @(posedge clock) begin

    if (timer == 12500000) begin
        flash <= ~flash;
        timer <= 0;
    end else
        timer <= timer + 1;
end

endmodule
