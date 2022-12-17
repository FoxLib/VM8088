[BITS 32]
[EXTERN main]
[GLOBAL _start]

_start:

        mov     esp, 0x00000800
        jmp     main
