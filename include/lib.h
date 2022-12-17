// Перевод числа в ASCIIZ-строку
void int2asc(char* t, int v) {

    byte k;
    char tmp[12];
    int  cnt = 0;

    while (v) {

        k  = v % 10;
        v /= 10;
        tmp[cnt++] = k + '0';
    }

    // Вывод в буфер
    for (int i = 0; i < cnt; i++) { t[cnt-i-1] = tmp[i]; } t[cnt] = 0;
}
