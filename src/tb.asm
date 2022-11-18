
;       СТАРТ $FF00:$0000

        org     0

        mov     ax, [cs:D1]
        mov     ds, ax
        mov     ax, $2741
        mov     [$0000], ax
        jmp     short $
D1:     dw      $B800
