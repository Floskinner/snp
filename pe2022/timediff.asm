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
        push    r12             ; save r12
        push    r13             ; save r13

next_string:
        ;-----------------------------------------------------------
        ; read string from standard input (usually keyboard)
        ;-----------------------------------------------------------
        SYSCALL_4 SYS_READ, FD_STDIN, input_buffer, BUFFER_SIZE
        test    rax,rax         ; check system call return value
        jz      finished        ; jump to loop exit if end of input is
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
        je      convert_sec_to_complete_number      ; yes, then read usec

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

        cmp     dl,CHR_LF       ; check for end-of-string
        je      next_string     ; no, process next sec char in buffer
        ; check counter < 6 -> ja: next_usec, nein: next_string

not_number:
        nop

finished:
        nop

        pop     r13             ; restore r13
        pop     r12             ; restore r12

; 1. Einlesen Timevals
; <= 10 chars = sec
;     1 char  = dot
; <=  6 chars = usec

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

; read sec here
; rcd = 1 faktor
; counter = 0
; do {
;        read char sec
;        char to number
;        save number in RAM
;        counter++
;
;} while (char != ".")

; rdx = 0
; rdx => zahlenwert sec
; convert from RAM to complete sec value
; do {
;         read number from RAM
;         rdx = rdx + number from RAM * faktor
;         faktor = faktor * 10
;         counter--
; } while (counter != 0)
; 
; save sec number

; read usec here
; rcd = 1 faktor 
; counter = 0
; do {
;        read char usec
;        char to number
;        save number in RAM
;        faktor = faktor * 10
;        counter++
;
; } while (char != CHR_LF && counter < 6)
;
; rdx = zahlenwert usec
; convert from RAM to complete usec value
; do {
;         read number from RAM
;         faktor = faktor / 10
;         rdx = rdx + number from RAM * faktor
; } while (faktor != 1)

; while (counter < 6) {
;         rdx = rdx * 10
; }

; save timeval = [sec][usec] wenns geht
; add timeval to list

        ;-----------------------------------------------------------
        ; call system exit and return to operating system / shell
        ;-----------------------------------------------------------
.exit:  SYSCALL_2 SYS_EXIT, 0
        ;-----------------------------------------------------------
        ; END OF PROGRAM
        ;-----------------------------------------------------------
