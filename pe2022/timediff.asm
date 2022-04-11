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

%define MAX_DAY_STR_SIZE     11 ; max 999999 -> 6 Byte numbers (ASCII) + max 5 Byte offset

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

days_str_buffer         resb MAX_DAY_STR_SIZE

;-----------------------------------------------------------------------------
; Section DATA
;-----------------------------------------------------------------------------
SECTION .data

day:
                db " day, __"
days:           
                db " days, _"

out_timestr:    db "__________.______"
                db CHR_LF
out_timestr_len equ $-out_timestr

out_str:        db "======="
                db CHR_LF
next_timestamp: db "__________.______"
                db CHR_LF
timediff:       times 28 db "_"
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
        push    r14     ; save r14
        push    r15     ; save r15

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
; r12 = index: index of the current timestamp
; r13 = max loop interation: size of the list - 1
        call    list_size
        mov     r13, rax                ; get size of list
        mov     r12, 0                  ; get size of list to count
        cmp     r13, 1                  ; check if list size <= 1
        jle     exit_failure

        dec     r13                     ; dec list_size to exit the loop

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
        mov     rcx, 10           ; counter = 10 -> last position for sec

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
        mov     rcx, 17           ; counter = 17 -> last position for sec
        
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
        cmp     cl, 11                          ; stop when the dot is reached in the string
        jg      setup_first_timveal_usec

        
        SYSCALL_4 SYS_WRITE, FD_STDOUT, out_timestr, out_timestr_len
        

calc_and_print_next:
;       get list[i] timeval
        mov     rdi, timeval_buffer
        mov     rsi, r12        ; r12 = index
        call    list_get

        test    rax, rax        ; test if get was successfull
        jz      exit_failure

;       get list[i+1] timeval
        mov     rdi, calc_buffer_timeval
        mov     rsi, r12        ; r12 = index
        add     rsi, 1          ; r12 + 1 = index + 1
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

        ; convert negative usecs to correct value
        ; mov     r10, qword [calc_buffer_useconds]
        ; cmp     r10, 0
        ; jge     usec_not_negative
        ; xor     r10, 0xffffffffffffffff
        ; inc     r10
        ; mov     r11, 0xF4240
        ; sub     r11, r10
        ; mov     qword [calc_buffer_useconds], r11
        ; [calc_buffer_useconds] = 1 000 000 - Zweierkomplement von r10

usec_not_negative:
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
        mov     dword [calc_buffer_days], eax     ; quotient - left days

        ; TODO ausgabe hier
        ; timestamp vorbereiten
        
        xor     rcx, rcx          ; clear counter
        xor     rax, rax          ; clear for div
        mov     rcx, 18           ; counter = 18 -> last position for sec

setup_timveal_sec:
        ; convert sec to ASCII
        mov     edx, dword [calc_buffer_timeval+4]
        mov     eax, dword [calc_buffer_timeval]
        mov     r11, 10
        div     r11d                            ; seconds / 10 = seconds and remainder 
        add     rdx, '0'                        ; convert remainder to ASCII
        lea     r11, [out_str+rcx-1]
        mov     byte [r11], dl                  ; write char to output string

        mov     qword [calc_buffer_timeval], rax
        
        dec     cl
        cmp     cl, 8                           ; stop when the start of sec is reached in the string
        jg      setup_timveal_sec

        ; convert usec to ASCII
        ; get list[index + 1] for usec
        mov     rdi, calc_buffer_timeval
        mov     rsi, r12
        inc     rsi
        call    list_get

        xor     rcx, rcx          ; clear counter
        xor     rax, rax          ; clear for div
        mov     rcx, 25           ; counter = 25 -> last position for the usec
        
setup_timveal_usec:
        mov     edx, dword [calc_buffer_timeval+12]
        mov     eax, dword [calc_buffer_timeval+8]
        mov     r11, 10
        div     r11d                            ; seconds / 10 = seconds and remainder 
        add     rdx, '0'                        ; convert remainder to ASCII
        lea     r11, [out_str+rcx-1]
        mov     byte [r11], dl                  ; write char to output string

        mov     qword [calc_buffer_timeval+8], rax
        
        dec     cl
        cmp     cl, 19                          ; stop when the dot is reached in the string
        jg      setup_timveal_usec


        ; r14 = 0: string_index
        xor     r14, r14        ; r14 = string_index = 0
        
        ; calc_buffer_days == 0
        ;       -> skip
        cmp     qword [calc_buffer_days], 0
        je      skip_days
        
        ; calc_buffer_days in string umwandlen
        xor     rcx, rcx                ; clear counter
        xor     rax, rax                ; clear for div
        xor     rdx, rdx                ; clear for div
        xor     r15, r15                ; clear counter for offset
        mov     rcx, 6                  ; counter = 6 -> last position for the days
        mov     edi, [calc_buffer_days] ; save current days value for conversion
setup_days:
        xor     edx, edx
        mov     eax, edi
        mov     r11, 10
        div     r11d                            ; seconds / 10 = seconds and remainder 
        add     rdx, '0'                        ; convert remainder to ASCII
        lea     r11, [days_str_buffer+rcx-1]
        mov     byte [r11], dl                  ; write char to output string buffer

        mov     edi, eax                        ; set new value for next iteration
        inc     r14                             ; string_index++

        cmp     dl, '0'                         ; check if char == '0'
        jg      not_zero_char                   ; if not reset offset
        inc     r15                             ; else offset++
        jmp     zero_char

not_zero_char:
        xor     r15,r15                         ; ...reset the offset
        
zero_char:
        dec     cl
        cmp     cl, 0                           ; stop when the dot is reached in the string
        jg      setup_days

        ; write number to string
        mov     r11, [days_str_buffer+r15]      ; write char numbers with offset to r11 (003452 -> 3452)
        mov     qword [timediff], r11           ; char numbers to timediff
        sub     r14, r15                        ; string_index = string_index - offset

        ; "______ days, "
        cmp     dword [calc_buffer_days], 1     ; check for multiple days or single day
        jg      days_output

        ; add " day, "
        lea     r11, [timediff+r14]
        mov     rdx, qword [day]                ; save string " day, " to rdx
        mov     qword [r11], rdx                ; save string " day, " to timediff
        add     r14, 6                          ; string_index += 6
        jmp     skip_days

days_output:
        lea     r11, [timediff+r14]
        mov     rdx, qword [days]               ; save string " day, " to rdx
        mov     qword [r11], rdx                ; save string " days, " to timediff
        add     r14, 7                          ; string_index += 7

        ; setup day(s)
        ; calc_buffer_days > 1
        ;       -> calc_buffer_days + " days" in out_str speichern
        ;       -> r14 entsprechen hinzugefügten chars hochzählen

        ; calc_buffer_days == 1
        ;       -> calc_buffer_days + " day" in out_str speichern
        ;       -> r14 entsprechen hinzugefügten chars hochzählen

skip_days:
        ; setup hours
        xor     rcx, rcx          ; clear counter
        xor     rax, rax          ; clear for div
        mov     rcx, r14          ; counter = 2
        add     rcx, 1
        
setup_hours:
        mov     al, byte [calc_buffer_hours]
        mov     r11, 10
        div     r11b                            ; seconds / 10 = seconds and remainder 
        add     ah, '0'                         ; convert remainder to ASCII
        lea     r11, [timediff+rcx]

        mov     byte [calc_buffer_hours], al    ; write quotient to AL

        shr     ax, 8
        mov     byte [r11], al                  ; write char to output string

        dec     cl
        cmp     rcx, r14                         ; stop after the 2 hour digits
        jge     setup_hours
        add     r14, 2                          ; inc string_index for the 2 houres ASCII

        mov     byte [timediff+r14], ':'        ; add hh:mm seperator
        inc     r14                             ; inc string_index beacuse of the ":"
        
        ; calc_buffer_hours in string umwandlen
        ; calc_buffer_hours + ":" in out_str speichern
        ; rcx entsprechen hinzugefügten chars hochzählen

        ; setup minutes
        xor     rcx, rcx          ; clear counter
        xor     rax, rax          ; clear for div
        mov     rcx, r14          ; counter = 2
        add     rcx, 1
        
setup_minutes:
        mov     al, byte [calc_buffer_minutes]
        mov     r11, 10
        div     r11b                            ; seconds / 10 = seconds and remainder 
        add     ah, '0'                         ; convert remainder to ASCII
        lea     r11, [timediff+rcx]

        mov     byte [calc_buffer_minutes], al    ; write quotient to AL

        shr     ax, 8
        mov     byte [r11], al                  ; write char to output string

        dec     cl
        cmp     rcx, r14                         ; stop after the 2 hour digits
        jge     setup_minutes
        add     r14, 2                          ; inc string_index for the 2 houres ASCII

        mov     byte [timediff+r14], ':'        ; add mm:ss seperator
        inc     r14                             ; inc string_index beacuse of the ":"
        ; calc_buffer_minutes in string umwandlen
        ; calc_buffer_minutes + ":" in out_str speichern
        ; rcx entsprechen hinzugefügten chars hochzählen

        ; setup seconds
        xor     rcx, rcx          ; clear counter
        xor     rax, rax          ; clear for div
        mov     rcx, r14          ; counter = 2
        add     rcx, 1
        
setup_seconds:
        mov     al, byte [calc_buffer_seconds]
        mov     r11, 10
        div     r11b                            ; seconds / 10 = seconds and remainder 
        add     ah, '0'                         ; convert remainder to ASCII
        lea     r11, [timediff+rcx]

        mov     byte [calc_buffer_seconds], al    ; write quotient to AL

        shr     ax, 8
        mov     byte [r11], al                  ; write char to output string

        dec     cl
        cmp     rcx, r14                         ; stop after the 2 hour digits
        jge     setup_seconds
        add     r14, 2                          ; inc string_index for the 2 houres ASCII

        mov     byte [timediff+r14], '.'        ; add ss:us seperator
        inc     r14                             ; inc string_index beacuse of the ":"
        ; calc_buffer_seconds in string umwandlen
        ; calc_buffer_seconds + ":" in out_str speichern
        ; rcx entsprechen hinzugefügten chars hochzählen

        ; setup useconds
        xor     rcx, rcx          ; clear counter
        xor     rax, rax          ; clear for div
        mov     rcx, r14          ; counter = 2
        add     rcx, 5
        
setup_useconds:
        xor     edx, edx
        mov     eax, [calc_buffer_useconds]
        mov     r11, 10
        div     r11d                                    ; seconds / 10 = seconds and remainder 
        add     rdx, '0'                                ; convert remainder to ASCII
        lea     r11, [timediff+rcx]
        mov     byte [r11], dl                          ; write char to output string buffer

        mov     dword [calc_buffer_useconds], eax       ; set new value for next iteration

        dec     cl
        cmp     rcx, r14                                ; stop after the 2 hour digits
        jge     setup_useconds

        ; calc_buffer_useconds in string umwandlen
        ; calc_buffer_useconds in out_str speichern
        ; rcx entsprechen hinzugefügten chars hochzählen

        SYSCALL_4 SYS_WRITE, FD_STDOUT, out_str, out_str_len

        ; clear timediff
        xor     rcx, rcx
        mov     rcx, 27
start_clear:
        mov     byte [timediff+rcx], '_'        ; clear timediff for next calculation
        dec     rcx
        cmp     rcx, 0
        jg      start_clear

        inc     r12             ; index++
        cmp     r12,r13         ; check if index < (list_size-1)
        jl      calc_and_print_next

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
pop     r15             ; restore r15
pop     r14             ; restore r14
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