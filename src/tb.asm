
        org     0
        mov     ax, $1122
        mov     bx, D1
        cmp     ax, $AFFE

        jmp     short $
D1:     dw      $FFFA
