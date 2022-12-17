#ifndef __STDDEF
#define __STDDEF

#define brk asm volatile("xchg %bx, %bx")
#define cli asm volatile("cli")
#define sti asm volatile("sti")

// ---------------------------------------------------------------------
// http://ru.cppreference.com/w/cpp/language/types
// ---------------------------------------------------------------------

#define int8_t      signed char
#define uint8_t     unsigned char
#define byte        unsigned char
#define int16_t     signed short
#define uint16_t    unsigned short
#define word        unsigned short
#define uint        unsigned int
#define uint32_t    unsigned int
#define dword       unsigned int
#define size_t      unsigned int
#define int32_t     signed int
#define int64_t     long long
#define uint64_t    unsigned long long

// Переключение режимов работы VGA
#define screen13 IoWrite8(0x3D8, 3)
#define screen3  IoWrite8(0x3D8, 0)

// ---------------------------------------------------------------------
// I/O Macros
// ---------------------------------------------------------------------

static inline void IoWrite8(uint16_t port, uint8_t data) {
    asm volatile("outb %0, %1" :: "a"(data), "Nd"(port));
}

static inline void IoWrite16(uint16_t port, uint16_t data) {
    asm volatile("outw %0, %1" :: "a"(data), "Nd"(port));
}

static inline void IoWrite32(uint16_t port, uint32_t data) {
    asm volatile("outl %0, %1" :: "a"(data), "Nd"(port));
}

static inline uint8_t IoRead8(uint16_t port) {
    uint8_t data;
    asm volatile ("inb %1, %0" : "=a"(data) : "Nd" (port));
    return data;
}

static inline uint16_t IoRead16(uint16_t port) {
    uint16_t data;
    asm volatile ("inw %1, %0" : "=a"(data) : "Nd" (port));
    return data;
}

static inline uint32_t IoRead32(uint16_t port) {
    uint32_t data;
    asm volatile ("inl %1, %0" : "=a"(data) : "Nd" (port));
    return data;
}

static inline uint8_t read(uint32_t addr) {

    volatile uint8_t* vm = (uint8_t*)1;
    return  vm[addr-1];
}


// ---------------------------------------------------------------------
// Функции работы с видео и устройствами
// ---------------------------------------------------------------------

// Установка палитры
void palette(byte id, byte r, byte g, byte b) {

    IoWrite8(968, id);
    IoWrite8(969, r >> 2);
    IoWrite8(969, g >> 2);
    IoWrite8(969, b >> 2);
}

#endif
