/* verilator lint_off WIDTH */

module vcard
(
    input               clock,
    output  reg [ 3:0]  r,
    output  reg [ 3:0]  g,
    output  reg [ 3:0]  b,
    output              hs,
    output              vs,
    output  reg [13:0]  address,
    input       [ 7:0]  data
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
wire [ 9:0] X = (x - hz_back);
wire [ 8:0] Y = (y - vt_back);
// ---------------------------------------------------------------------
// Цвет на 2x пикселя
reg  [11:0] color;

// Один из цветов в байте
wire [1:0] id =
    X[2:1] == 2'b11 ? data[7:6] :
    X[2:1] == 2'b10 ? data[5:4] :
    X[2:1] == 2'b01 ? data[3:2] :
                      data[1:0];

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

    case (X[0])
    1'b0: address <= Y[8:1] + X[8:3];
    1'b1: color   <= cl;
    endcase

    if (shown) {r, g, b} <= color;

end
endmodule
