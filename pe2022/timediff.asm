;-----------------------------------------------------------------------------
; timediff.asm - 
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

%include "syscall.inc"  ; OS-specific system call macros
extern list_init
extern list_size
extern list_is_sorted
extern list_add
extern list_find
extern list_get

;-----------------------------------------------------------------------------
; CONSTANTS
;-----------------------------------------------------------------------------

%define BUFFER_SIZE          18 ; 16 numbers + 1 dot + line feed(\n) = 18 chars
                                ; 1 char = 1 Byte
                                ; 18 chars = 18 Byte
%define CHR_LF               10 ; line feed (LF) character
%define CHR_CR               13 ; carriage return (CR) character (only needed for Windows)
%define TIMEVAL_SIZE         16 ; 8 Byte sec + 8 Byte usec
%define SEC_SIZE              8 ; 8 Byte
%define USEC_SIZE             8 ; 8 Byte

;-----------------------------------------------------------------------------
; Section BSS
;-----------------------------------------------------------------------------
SECTION .bss

input_buffer    resb BUFFER_SIZE
timeval_buffer  resb TIMEVAL_SIZE
sec_buffer      resb SEC_SIZE
usec_buffer     resb USEC_SIZE


;-----------------------------------------------------------------------------
; Section DATA
;-----------------------------------------------------------------------------
SECTION .data

error_str:
        db "Dies ist kein gueltiger Timestamp!", CHR_LF

;-----------------------------------------------------------------------------
; SECTION TEXT
;-----------------------------------------------------------------------------
SECTION .text

        ;-----------------------------------------------------------
        ; PROGRAM'S START ENTRY
        ;-----------------------------------------------------------
        global _start:function  ; make label available to linker
_start:
        nop
        push    r12     ; save r12
        push    r13     ; save r13

        call    list_init       ; init list for the timeval

next_string:
        ;-----------------------------------------------------------
        ; read string from standard input (usually keyboard)
        ;-----------------------------------------------------------
        SYSCALL_4 SYS_READ, FD_STDIN, input_buffer, BUFFER_SIZE
        test    rax,rax         ; check system call return value
        jz      read_finished   ; jump to loop exit if end of input is
                                ; reached, i.e. no characters have been
                                ; read (rax == 0)

        ; rsi: pointer to current character in input_buffer
        lea     rsi,[input_buffer]    ; load pointer to character buffer

        xor     rcx, rcx        ; clear rcx
        xor     r13, r13

next_sec_char:
        movzx   edx,byte [rsi]  ; load next character from buffer

        xor     r8, r8                          ; clear r8
        lea     r8d, [rdx-'.']                  ; number saved in r8d
        cmp     r8b, 0                          ; check whether character is '.'
        je      convert_sec_to_complete_number  ; yes, then convert to complete number

;        char to number
        lea     r8d, [rdx-'0']  ; number saved in r8d
        cmp     r8b, ('9'-'0')  ; check whether character is a number
        ja      not_number      ; no, then end programm

;        save number in r13b
        shl     r13, 4
        xor     r13b, r8b
        inc     rcx             ; increment counter

        inc     rsi             ; increment pointer to next char in string
        jmp     next_sec_char   ; jump back to read next char

convert_sec_to_complete_number:
        inc     rsi                     ; increment pointer to next char in string
        mov     qword [sec_buffer], 0   ; clear sec_buffer
        xor     r10, r10                ; clear r10
        inc     r10                     ; use r10 as factor
convert_next_sec_number:
        xor     rdx, rdx        ; clear rdx
        mov     dl, 0xF         ; setup rdx for the AND
        AND     rdx, r13        ; get lowest 4 Bit from rdx
        shr     r13, 4
        
        ; start number (rdx) * factor (r10)
        push    rax             ; save rax for mul
        mov     rax, rdx        ; move rdx to rax for mul
        mul     r10             ; rax * 10 = edx & eax
        shl     rdx, 32         ; to higher 32 Bit of r10
        mov     edx, eax        ; move eax to lower 32 Bit of rdx
        pop     rax             ; restore rax
        ; end number (rdx) * factor (r10)

        mov     r11, sec_buffer
        add     qword [r11], rdx ; add number * factor to sec_buffer

        ; start calculate factor
        push    rax             ; save rax for mul
        mov     rax, r10        ; move r10 to rax for mul
        mov     r12d, 0xA       ; move factor 10 to r12
        mul     r12d            ; rax * 10 = edx & eax
        xor     r10, r10        ; clear r10
        mov     r10d, edx       ; move edx...
        shl     r10, 32         ; to higher 32 Bit of r10
        mov     r10d, eax       ; move eax to lower 32 Bit of r10
        pop     rax             ; restore rax
        ; end calculate factor

        dec     rcx             ; decrement counter
        test    rcx, rcx
        jg      convert_next_sec_number
        ; if finished continue with read_usec

read_usec:
        xor     rcx, rcx        ; reset counter
        cmp     dl,CHR_LF       ; check for end-of-string
        je      next_string     ; no, process next sec char in buffer
        ; check counter < 6 -> ja: next_usec, nein: next_string

        

next_usec_char:
        movzx   edx,byte [rsi]  ; load next character from buffer

        xor     r8, r8                          ; clear r8
        lea     r8d, [rdx-CHR_LF]               ; save 0 to r8 if char is line feed
        cmp     r8b, 0                          ; check whether character is '.'
        je      convert_usec_to_complete_number ; yes, then convert to complete number

        cmp     rcx, 0x6                        ; check whether 6 digits are read
        jge     convert_usec_to_complete_number ; yes, then convert to complete number

;       char to number
        lea     r8d, [rdx-'0']  ; number saved in r8d
        cmp     r8b, ('9'-'0')  ; check whether character is a number
        ja      not_number      ; no, then end programm

;       save number in r13b
        shl     r13, 4
        xor     r13b, r8b
        inc     rcx             ; increment counter

        inc     rsi             ; increment pointer to next char in string
        jmp     next_usec_char  ; jump back to read next char

convert_usec_to_complete_number:
        cmp     rcx, 0x6                ; check whether 6 digits are read
        jge     six_digits_read         ; yes, then continue with converting
        shl     r13, 4                  ; else, add a 0 digit
        inc     rcx                     ; ...and increment counter rcx
        jmp     convert_usec_to_complete_number ; loop the 6 digit checker

six_digits_read:
        inc     rsi                     ; increment pointer to next char in string
        mov     qword [usec_buffer], 0  ; clear usec_buffer
        xor     r10, r10                ; clear r10
        inc     r10                     ; use r10 as factor
convert_next_usec_number:
        xor     rdx, rdx        ; clear rdx
        mov     dl, 0xF         ; setup rdx for the AND
        AND     rdx, r13        ; get lowest 4 Bit from rdx
        shr     r13, 4
        
        ; start number (rdx) * factor (r10)
        push    rax             ; save rax for mul
        mov     rax, rdx        ; move rdx to rax for mul
        mul     r10             ; rax * 10 = edx & eax
        shl     rdx, 32         ; to higher 32 Bit of r10
        mov     edx, eax        ; move eax to lower 32 Bit of rdx
        pop     rax             ; restore rax
        ; end number (rdx) * factor (r10)

        mov     r11, usec_buffer
        add     qword [r11], rdx ; add number * factor to usec_buffer

        ; start calculate factor
        push    rax             ; save rax for mul
        mov     rax, r10        ; move r10 to rax for mul
        mov     r12d, 0xA       ; move factor 10 to r12
        mul     r12d            ; rax * 10 = edx & eax
        xor     r10, r10        ; clear r10
        mov     r10d, edx       ; move edx...
        shl     r10, 32         ; to higher 32 Bit of r10
        mov     r10d, eax       ; move eax to lower 32 Bit of r10
        pop     rax             ; restore rax
        ; end calculate factor

        dec     rcx                             ; decrement counter
        test    rcx, rcx                        ; check if more digits available
        jg      convert_next_usec_number        ; yes, then convert next digit

        mov     r12, qword [sec_buffer]         ; add sec to timeval_buffer
        mov     qword [timeval_buffer], r12
        
        mov     r12, qword [usec_buffer]        ; add usec to timeval_buffer
        mov     qword [timeval_buffer+8], r12

        mov     rdi, timeval_buffer             ; first argument of list_add need pointer to a timeval
        call    list_add
        jmp     next_string
        ; if finished continue with list_add(&timeval_buffer) and next_string

read_finished:
        nop

; 1. Checken ob Liste sortiert ist -> ansonsten fehler
; 2. Berechnen der Timediff und Ausgabe
    ; foreach timeval in list
        ; "=======" ausgeben
        ; Zahl in ascii convertieren (darauf achten zahlen auszufüllen mit 0er)
        ; die convertierten zeichen in buffer schreiben
        ; buffer ausgeben
        ; timediff berechnen 
        ; umwandeln in ascii
        ; ascii in buffer
        ; buffer ausgeben
        ; und von vorne
;
;Beispiel
;sec = d0012345678
;umwandeln in ascii
;
;ganze 10 mal
;
;sec = (EDX & EAX) / 10 = Ganzzahl (EAX) and Rest (EDX)
;neues sec = EAX
;hier umwandlung von EDX in ascii
;in buffer schreiben - Achtung wir lesen von 1er nach 1milliarder 
;
;und von vorne
;

; =======

; 1.5                   = 0000000001.500000
; 1000000000.0
; 1234567890.000000
; 1483225200.000000
; 1491861600.000
; 1500000000.000000
; 1502529000.000001
; 1502529001.000000
; 1502530860.999999
; 1502617201.999998


not_number:
        nop

; Need to restore regestries
pop     r13             ; restore r13
pop     r12             ; restore r12

        ;-----------------------------------------------------------
        ; call system exit and return to operating system / shell
        ;-----------------------------------------------------------
.exit:  SYSCALL_2 SYS_EXIT, 0
        ;-----------------------------------------------------------
        ; END OF PROGRAM
        ;-----------------------------------------------------------
