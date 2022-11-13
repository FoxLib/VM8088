
        org     0
        nop
        mov     cx, [cs:D1]
        mov     cx, dx
        add     word [D1], -1
        mov     ax, $FFFF
        xchg    ax, cx
        dec     bx
        mov     bx, D1
        cmp     ax, $AFFE
        jmp     short $
D1:     dw      $FFFA
