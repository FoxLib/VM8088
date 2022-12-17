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

int main() {

    cli;

    IoWrite8(0x3D8, 3);

    int n = 0;
    for (;;) {

        for (int y = 0; y < 200; y++) line(0, y, 319, 199, y + n);
        for (int x = 0; x < 319; x++) line(x, 0, 319, 199, x + n);
        n++;
    }


    /*
    for (int y = 0; y < 200; y++)
    for (int x = 0; x < 256; x++) {
        pset(x, y, x + y);
    }
    */

    for(;;);
}
