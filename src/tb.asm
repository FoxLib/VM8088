
        org     0
        push    bx
        pop     di

        mov     ax, $FFFF
        inc     ax
        mov     bx, D1
        cmp     ax, $AFFE
        jmp     short $
D1:     dw      $FFFA
