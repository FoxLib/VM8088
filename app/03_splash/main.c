#include <io.h>
#include <lib.h>
#include <screen3.h>

int main() {

    char buf[32];

    screen3;
    cls(0x07);

    int2asc(buf, 252); print(buf);

    for(;;);
}
