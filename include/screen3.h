
void cls(byte attr) {

    word* m = (word *) 0xB8000;
    for (int i = 0; i < 2000; i++) m[i] = attr << 8;
}

void print(const char* t) {

    int i = 0;
    while (t[i]) { write(0xB8000 + 2*i, t[i]); i++; }
}
