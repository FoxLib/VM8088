#include <io.h>

void pset(int x, int y, char ch) {

    char* m = (char*) 0xA0000;
    m[x + y*320] = ch;
}

void line(int x1, int y1, int x2, int y2, int color) {

    // Инициализация смещений
    int signx  = x1 < x2 ? 1 : -1;
    int signy  = y1 < y2 ? 1 : -1;
    int deltax = x2 > x1 ? x2 - x1 : x1 - x2;
    int deltay = y2 > y1 ? y2 - y1 : y1 - y2;
    int error  = deltax - deltay;
    int error2;

    // Если линия - это точка
    pset(x2, y2, color);

    // Перебирать до конца
    while ((x1 != x2) || (y1 != y2)) {

        pset(x1, y1, color);
        error2 = 2 * error;

        // Коррекция по X
        if (error2 > -deltay) {
            error -= deltay;
            x1 += signx;
        }

        // Коррекция по Y
        if (error2 < deltax) {
            error += deltax;
            y1 += signy;
        }
    }
}

void circle(int xc, int yc, int radius, int color) {

    int x = 0,
        y = radius,
        d = 3 - 2*y;

    while (x <= y) {

        // Верхний и нижний сектор
        pset(xc - x, yc + y, color);
        pset(xc + x, yc + y, color);
        pset(xc - x, yc - y, color);
        pset(xc + x, yc - y, color);

        // Левый и правый сектор
        pset(xc - y, yc + x, color);
        pset(xc + y, yc + x, color);
        pset(xc - y, yc - x, color);
        pset(xc + y, yc - x, color);

        d += (4*x + 6);
        if (d >= 0) {
            d += 4*(1 - y);
            y--;
        }

        x++;
    }
}

void test1() {

    int n = 0;
    for (;;) {

        for (int y = 0; y < 200; y++) line(0, y, 319, 199, y + n);
        for (int x = 0; x < 319; x++) line(x, 0, 319, 199, x + n);
        n++;
    }
}

void test2() {

    int n = 3;
    for (;;) {

        for (int i = 1; i < 100; i++)
            circle(160, 100, 1 + i, i + n);

        n++;
    }
}


int main() {

    cli;

    screen13;
    test2();



    for(;;);
}
