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

; max 10.000 timevals -> at least 14 Bit -> 16 Bit for registry compatibility
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

        movzx   rax, word [counter]     ; set counter to return value

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

        xor     rax,rax                 ; set return value to false
        xor     rcx, rcx                ; set counter rcx to 0

        cmp     word [counter],0        ; check if list size is 0
        je      return_sorted_false     ; return false

        cmp     word [counter],1        ; check if list size is 1
        je      return_sorted_true      ; return true

        movzx   rdx, word [counter]     ; save list size to rdx
        sub     rdx, 1                  ; rdx = list size - 1
        shl     rdx, 4                  ; list size * 16 -> max physical address

loop_start_sorted:
        xor     r10, r10
        xor     r11, r11

        mov     r10, [list + rcx]               ; get tv_sec at list[rcx]
        mov     r11, [list + rcx + 0x10]        ; get tv_sec at list[rcx+1]

        cmp     r10, r11                ; if links & rechts...
        je      check_usec              ; links == rechts
        jg      return_sorted_false     ; links > rechts => false

callback_from_check_usec:
        add     rcx, 0x10               ; add 16 to the index
        cmp     rcx, rdx                ; if index >= counter * 16
        jge     return_sorted_true      ; list is sorted => return true

        jmp     loop_start_sorted       ; go to loop start

check_usec:
        xor     r10, r10                ; clear r10
        xor     r11, r11                ; celar r11

        mov     r10, [list + rcx + 0x8]         ; get tv_usec at list[rcx]
        mov     r11, [list + rcx + 0x18]        ; get tv_usec at list[rcx+1]

        cmp     r10, r11                        ; if links & rechts...
        jg      return_sorted_false             ; links > rechts => false

        jmp      callback_from_check_usec       ; return to loop


return_sorted_true:
        add     rax, 1                  ; set return value to true

return_sorted_false:
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

        mov     r10, [rdi]              ; r10 = *rdi (tv_sec)
        mov     r11, [rdi+0x8]          ; r11 = *rdi + 8 Byte (tv_usec)

        movzx   rcx, word [counter]     ; get counter value in rcx
        shl     rcx, 4                  ; rcx * 16 Bytes == rcx << 4

        add     rcx, list               ; addr + offset (counter * 16 Byte)

        mov     [rcx], r10              ; tv_sec in list[counter*16]
        mov     [rcx + 0x8], r11        ; tv_usec in list[counter*16+8]

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

        ; binary search to find a timeval in the list
        mov     rax, 0xffffffff         ; return -1 on failure

        cmp     word [counter], 0       ; check if counter == 0
        je      return_find             ; return -1 -> object not found

        xor     r10, r10                ; r10 is the left edge index = 0
        movzx   r11, word [counter]     ; save counter to r11
        sub     r11, 1                  ; r11 is the right edge index = counter -1

loop_start_find:
        mov     rcx, r11                ; rcx = r11
        sub     rcx, r10                ; rcx = r11 - r10
        shr     rcx, 1                  ; rcx = ( r11 - r10 ) / 2
        add     rcx, r10                ; rcx is the middle element index of the search field = ( r11 - r10 ) / 2 + r10
        shl     rcx, 4                  ; set rcx from index to offset ( rcx * 16 Bytes )

        mov     rdx, [list + rcx]       ; find timeval sec at offset rcx in list
        cmp     rdx, [rdi]              ; compare sec of rdx & *tv
        je      equal_seconds           ; rdx == *tv
        jg      binary_search_lower     ; rdx > *tv
        jl      binary_search_greater   ; rdx < *tv

equal_seconds:
        mov     rdx, [list + rcx + 0x8] ; find timeval usec at offset rcx in list
        cmp     rdx, [rdi + 0x8]        ; compare usec of rdx & *tv
        je      return_find_success     ; rdx == *tv
        jg      binary_search_lower     ; rdx > *tv
        jl      binary_search_greater   ; rdx < *tv

binary_search_lower:
        cmp     rcx, 0                  ; check if rcx == 0
        je      return_find             ; return -1 -> object not found

        shr     rcx, 4                  ; set rcx from offset to index ( rcx / 16 Bytes )
        sub     rcx, 1                  ; rcx is the new right edge index
        mov     r11, rcx                ; set r11 the new right edge index

        cmp     r10, r11                ; compare right and left edge index
        jle     loop_start_find         ; loop if checkable timeval is available
        jg      return_find             ; return -1 -> object not found

binary_search_greater:
        shr     rcx, 4                  ; set rcx from offset to index ( rcx / 16 Bytes )
        add     rcx, 1                  ; rcx is the new left edge index
        mov     r10, rcx                ; set r10 the new left edge index

        cmp     r10, r11                ; compare right and left edge index
        jle     loop_start_find         ; loop if checkable timeval is available
        jg      return_find             ; return -1 -> object not found

return_find_success:
        shr     rcx, 4                  ; set rcx from offset to index ( rcx / 16 Bytes )
        mov     rax, rcx                ; return the index value

return_find:
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

        ; *tv is in rdi
        ; idx is in rsi

        xor     rax, rax                ; return false on failure

        cmp     word [counter], 0       ; check if counter == 0
        je      return_get              ; return false

        cmp     si, word [counter]      ; check if index >= counter
        jge     return_get              ; return false
        
        mov     rcx, rsi                ; get counter value in rcx
        shl     rcx, 4                  ; rcx * 16 Bytes == rcx << 4

        add     rcx, list               ; addr + offset (counter * 16 Byte)
        mov     r10, [rcx]              ; r10 = tv_sec
        mov     [rdi], r10              ; rdi = r10 (tv_sec)

        xor     r10, r10                ; clear r10
        mov     r10, [rcx + 0x8]        ; r10 = tv_usec
        mov     [rdi + 0x8], r10        ; rdi+0x8 = r10 (tv_usec)

        add     rax, 1                  ; return true on success

return_get:
        mov     rsp,rbp
        pop     rbp
        ret
