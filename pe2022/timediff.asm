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

%define MAX_DAY_SIZE          4 ; max 115.740 days -> 17 Bit -> min 3 Byte
%define MAX_HOUR_SIZE         1 ; max 23 -> 5 Bit -> 1 Byte
%define MAX_MINUTE_SIZE       1 ; max 59 -> 6 Bit -> 1 Byte
%define MAX_SECOND_SIZE       1 ; max 59 -> 6 Bit -> 1 Byte
%define MAX_USECOND_SIZE      4 ; max 999999 -> 20 Bit -> min 3 Byte

;-----------------------------------------------------------------------------
; Section BSS
;-----------------------------------------------------------------------------
SECTION .bss

input_buffer            resb BUFFER_SIZE
timeval_buffer          resb TIMEVAL_SIZE
sec_buffer              resb SEC_SIZE
usec_buffer             resb USEC_SIZE

calc_buffer_timeval     resb TIMEVAL_SIZE
calc_buffer_days        resb MAX_DAY_SIZE
calc_buffer_hours       resb MAX_HOUR_SIZE
calc_buffer_minutes     resb MAX_MINUTE_SIZE
calc_buffer_seconds     resb MAX_SECOND_SIZE
calc_buffer_useconds    resb MAX_USECOND_SIZE

;-----------------------------------------------------------------------------
; Section DATA
;-----------------------------------------------------------------------------
SECTION .data

out_timestr:    db "__________.______"
                db CHR_LF
out_timestr_len equ $-out_timestr

out_str:        db "======="
                db CHR_LF
next_timestamp: db "__________.______"
                db CHR_LF
timediff:       times 28 db ""
                db CHR_LF
out_str_len equ $-out_str

not_number_error_str:
        db "Dies ist kein gueltiger Timestamp!", CHR_LF
not_sorted_error_str:
        db "Die Timestamps sind nicht aufsteigend sortiert!", CHR_LF

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

        cmp     byte [rsi], CHR_LF
        je      read_finished

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
        jnz     convert_next_sec_number
        ; if finished continue with read_usec

read_usec:
        xor     rcx, rcx        ; reset counter       

next_usec_char:
        movzx   edx,byte [rsi]  ; load next character from buffer

        xor     r8, r8                          ; clear r8
        lea     r8d, [rdx-CHR_LF]               ; save 0 to r8 if char is line feed
        cmp     r8b, 0                          ; check whether character is '.'
        je      convert_usec_to_complete_number ; yes, then convert to complete number

        cmp     rdx, 0                          ; check ASCII NUL - End of stream
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
        xor     r13, r13                ; clear counter

; 1. Checken ob Liste sortiert ist -> ansonsten fehler
        call    list_size
        mov     r12, rax                ; get size of list
        mov     r13, r12                ; get size of list to count
        cmp     r13, 1                  ; check if list size <= 1
        jle     exit_failure

        call    list_is_sorted          ; check if list is sorted
        test    rax, rax
        jz      not_sorted              ; print error and exit if not

; hier 1. Timestamp ausgeben
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

;       get list[0] timeval
        mov     rdi, timeval_buffer
        mov     rsi, 0
        call    list_get

        test    rax, rax        ; test if get was successfull
        jz      exit_failure
        
        xor     rcx, rcx          ; clear counter
        xor     rax, rax          ; clear for div
        mov     rcx, 10           ; counter = 10

setup_first_timveal_sec:
        ; convert sec to ASCII
        mov     edx, dword [timeval_buffer+4]
        mov     eax, dword [timeval_buffer]
        mov     r11, 10
        div     r11d                            ; seconds / 10 = seconds and remainder 
        add     rdx, '0'                        ; convert remainder to ASCII
        lea     r11, [out_timestr+rcx-1]
        mov     byte [r11], dl                  ; write char to output string

        mov     qword [timeval_buffer], rax
        
        dec     cl
        cmp     cl, 0
        jg      setup_first_timveal_sec

        ; get list[0] for usec
        mov     rdi, timeval_buffer
        mov     rsi, 0
        call    list_get

        xor     rcx, rcx          ; clear counter
        xor     rax, rax          ; clear for div
        mov     rcx, 17           ; counter = 6
        
setup_first_timveal_usec:
        mov     edx, dword [timeval_buffer+12]
        mov     eax, dword [timeval_buffer+8]
        mov     r11, 10
        div     r11d                            ; seconds / 10 = seconds and remainder 
        add     rdx, '0'                        ; convert remainder to ASCII
        lea     r11, [out_timestr+rcx-1]
        mov     byte [r11], dl                  ; write char to output string

        mov     qword [timeval_buffer+8], rax
        
        dec     cl
        cmp     cl, 11
        jg      setup_first_timveal_usec

        
        SYSCALL_4 SYS_WRITE, FD_STDOUT, out_timestr, out_timestr_len
        

calc_and_print_next:
;       get list[i] timeval
        mov     rdi, timeval_buffer
        mov     rsi, r12
        sub     rsi, r13
        call    list_get

        test    rax, rax        ; test if get was successfull
        jz      exit_failure

;       get list[i+1] timeval
        mov     rdi, calc_buffer_timeval
        mov     rsi, r12
        sub     rsi, r13
        add     rsi, 1
        call    list_get

        test    rax, rax        ; test if get was successfull
        jz      exit_failure

        ; calculate usec diff
        mov     r10, qword [calc_buffer_timeval+8]
        sub     r10, qword [timeval_buffer+8]           ; list[i+1] - list[i]
        mov     qword [calc_buffer_useconds], r10
        
        ; calculate sec diff
        mov     r10, qword [calc_buffer_timeval]
        sbb     r10, qword [timeval_buffer]             ; list[i+1] - list[i]

        ; calculate min from sec
        mov     eax, r10d
        shr     r10, 32
        mov     edx, r10d
        mov     r11, 60
        div     r11d            ; EDX & EAX / r11 = EAX and EDX
        mov     byte [calc_buffer_seconds], dl
        mov     r10, rax         ; quotient - left min

        ; calculate hr from min
        mov     eax, r10d
        shr     r10, 32
        mov     edx, r10d
        mov     r11, 60
        div     r11d            ; EDX & EAX / r11 = EAX and EDX
        mov     byte [calc_buffer_minutes], dl
        mov     r10, rax         ; quotient - left min

        ; calculate d from hr
        mov     eax, r10d
        shr     r10, 32
        mov     edx, r10d
        mov     r11, 24
        div     r11d            ; EDX & EAX / r11 = EAX and EDX
        mov     byte [calc_buffer_hours], dl
        mov     dword [calc_buffer_days], eax     ; quotient - left d

        ; TODO ausgabe hier

        dec     r13
        cmp     r13,1
        jg      calc_and_print_next

; 1000000000.000000
; 1234567890.000000
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

not_sorted:
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

exit_failure:
.exit:  SYSCALL_2 SYS_EXIT, -1