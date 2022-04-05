;-----------------------------------------------------------------------------
;
; DHBW Ravensburg - Campus Friedrichshafen
;
; Vorlesung Systemnahe Programmierung (SNP)
;
;----------------------------------------------------------------------------
;
; Architecture:  x86-64
; Language:      NASM Assembly Language
;
; Authors:       David Felder, Florian Herkommer, Florian Glaser
;
;----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; Section BSS
;-----------------------------------------------------------------------------
SECTION .bss

; tv_sec sind 8 Bytes
; tv_usec sind 8 Bytes
; => 16 Byte pro timeval

; => 16 Byte * 10.000 Stück = 160.000 Byte
; => 8 Byte RESQ * 20.000 = 160.000 Byte
list    resq 20000

; Maximal 10.000 Stück -> 16 Bit (reichen theoretisch 14 Bit - gibts nicht)
counter resw 1

;-----------------------------------------------------------------------------
; SECTION TEXT
;-----------------------------------------------------------------------------
SECTION .text


;-----------------------------------------------------------------------------
; extern void list(void)
;-----------------------------------------------------------------------------
        global list_init:function
list_init:
        push    rbp
        mov     rbp,rsp

        mov     word [counter], 0       ; Inital counter set to 0

        mov     rsp,rbp
        pop     rbp
        ret

;-----------------------------------------------------------------------------
; extern short list_size(void);
;-----------------------------------------------------------------------------
        global list_size:function
list_size:
        push    rbp
        mov     rbp,rsp

        movzx   rax, word [counter]

        mov     rsp,rbp
        pop     rbp
        ret


;-----------------------------------------------------------------------------
; extern bool list_is_sorted(void);
;-----------------------------------------------------------------------------
        global list_is_sorted:function
list_is_sorted:
        push    rbp
        mov     rbp,rsp

        ; your code goes here

        mov     rsp,rbp
        pop     rbp
        ret


;-----------------------------------------------------------------------------
; extern short list_add(struct timeval *tv);
;-----------------------------------------------------------------------------
        global list_add:function
list_add:
        push    rbp
        mov     rbp,rsp

        ; *tv ist in rdi
        ; *tv = tv_sec (lenght 8 Byte)
        ; *tv + 8 Byte = tv_usec (length 8 Byte)

        mov     r10d, [rdi]             ; *rdi = r10d (tv_sec)
        mov     r11d, [rdi+8]           ; *rdi + 8 Byte = r11d (tv_usec)

        movzx   rcx, word [counter]     ; get counter value in cx
        shl     rcx, 4                  ; cx * 16 Bytes == cx << 4

        add     rcx, list               ; addr + offset (counter * 16 Byte)

        mov    [rcx], r10d              ; tv_sec in list[counter*16]
        mov    [rcx + 8], r11d          ; tv_usec in list[counter*16+8]

        movzx   rax, word [counter]     ; Return index of the added timestamp
        add     word [counter], 1       ; Add 1 to the counter of added timestamps

        mov     rsp,rbp
        pop     rbp
        ret


;-----------------------------------------------------------------------------
; extern short list_find(struct timeval *tv);
;-----------------------------------------------------------------------------
        global list_find:function
list_find:
        push    rbp
        mov     rbp,rsp

        ; your code goes here

        mov     rsp,rbp
        pop     rbp
        ret


;-----------------------------------------------------------------------------
; extern bool list_get(struct timeval *tv, short idx);
;-----------------------------------------------------------------------------
        global list_get:function
list_get:
        push    rbp
        mov     rbp,rsp

        ; your code goes here

        mov     rsp,rbp
        pop     rbp
        ret
