
        org     0
        mov     es, [D1]
        pop     word [bx]
        mov     cx, [cs:D1]
        mov     cx, dx
        mov     ax, $FFFF
        xchg    ax, cx
        dec     bx
        mov     bx, D1
        cmp     ax, $AFFE
        jmp     short $
D1:     dw      $FFFA
