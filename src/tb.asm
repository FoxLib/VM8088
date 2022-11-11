
        org     0
        mov     ax, $FFFF
        inc     ax
        mov     bx, D1
        cmp     ax, $AFFE
        jmp     short $
D1:     dw      $FFFA
