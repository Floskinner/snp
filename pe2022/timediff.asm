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

%define BUFFER_SIZE      180001 ; 16 numbers + 1 dot + line feed(\n) = 18 chars
                                ; 1 char = 1 Byte
                                ; 18 chars = 18 Byte
                                ; max 10.000 elements -> 180.000 Bytes
                                ; 180.000 Bytes + 1 \0 = 180.001 Bytes
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
timediff:       times 28 db 0
                db CHR_LF
out_str_len equ $-out_str

not_number_error_str:
        db "Die Eingabe der Timestamps enthält einen Fehler!", CHR_LF
not_number_error_str_len equ $-not_number_error_str

not_sorted_error_str:
        db "Die Timestamps sind nicht aufsteigend sortiert!", CHR_LF
not_sorted_error_str_len equ $-not_sorted_error_str

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
        push    r14             ; save r14
        push    r15             ; save r15

        call    list_init       ; init list for the timeval

;-----------------------------------------------------------------------------
; Start: Read input to buffer
;-----------------------------------------------------------------------------

next_string:
        ;-----------------------------------------------------------
        ; read string from standard input (usually keyboard)
        ;-----------------------------------------------------------
        SYSCALL_4 SYS_READ, FD_STDIN, input_buffer, BUFFER_SIZE
        test    rax, rax                ; check system call return value
        jz      exit.exit_failure       ; exit with error status code if string is empty

        ; rsi: pointer to current character in input_buffer
        lea     rsi, [input_buffer]     ; load pointer to character buffer
        mov     byte [rsi+rax], 0        ; zero terminate string

        xor     rcx, rcx                ; clear rcx
        xor     r13, r13                ; clear r13

next_sec_char:
        movzx   edx, byte [rsi]                 ; load next character from buffer to edx
        xor     r8, r8                          ; clear r8
        lea     r8d, [rdx-'.']                  ; number = rdx (ASCII) - '.' (ASCII) saved in r8d
        cmp     r8b, 0                          ; check whether character is '.'
        je      convert_sec_to_complete_number  ; yes, then convert seconds to complete number

;       char to number
        lea     r8d, [rdx-'0']  ; number = rdx (ASXII) - '0' (ASCII) saved in r8d
        cmp     r8b, ('9'-'0')  ; check whether character is a number
        ja      not_number      ; no, then end programm

;       save number to r13b
        shl     r13, 4          ; shift left to create space for the next number
        xor     r13b, r8b       ; write the number to the lower 8 Bit of r13
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
        add     qword [r11], rdx        ; add number * factor to sec_buffer

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
        test    rcx, rcx        ; if counter == 0 end loop
        jnz     convert_next_sec_number
        ; if finished continue with read_usec

read_usec:
        xor     rcx, rcx        ; reset counter

next_usec_char:
        movzx   edx, byte [rsi]  ; load next character from buffer

        xor     r8, r8                          ; clear r8
        lea     r8d, [rdx-CHR_LF]               ; save 0 to r8 if char is line feed
        cmp     r8b, 0                          ; check whether character is line feed
        je      convert_usec_to_complete_number ; yes, then convert to complete number

        cmp     rdx, 0                          ; check ASCII NUL - End of stream
        je      convert_usec_to_complete_number ; yes, then convert to complete number

        cmp     rcx, 0x6                        ; check whether 6 digits are read
        jge     max_usec_length_reached         ; yes, then loop until line feed or end of stream

;       char to number
        lea     r8d, [rdx-'0']          ; number saved in r8d
        cmp     r8b, ('9'-'0')          ; check whether character is a number
        ja      not_number              ; no, then end programm

;       save number in r13b
        shl     r13, 4          ; shift left to create space for the next number
        xor     r13b, r8b       ; write the number to the lower 8 Bit of r13
        inc     rcx             ; increment counter

max_usec_length_reached:
        inc     rsi             ; increment pointer to next char in string
        jmp     next_usec_char  ; jump back to read next char

convert_usec_to_complete_number:
        cmp     rcx, 0x6                        ; check whether 6 digits are read
        jge     six_digits_read                 ; yes, then continue with converting
        shl     r13, 4                          ; else, add a 0 digit
        inc     rcx                             ; ...and increment counter rcx
        jmp     convert_usec_to_complete_number ; loop and check if reading is finished

six_digits_read:
        inc     rsi                     ; increment pointer to next char in string
        mov     qword [usec_buffer], 0  ; clear usec_buffer
        xor     r10, r10                ; clear r10
        inc     r10                     ; use r10 as factor with start value 1
convert_next_usec_number:
        xor     rdx, rdx        ; clear rdx
        mov     dl, 0xF         ; setup rdx for the AND
        AND     rdx, r13        ; get lowest 4 Bit from rdx
        shr     r13, 4          ; shift right to access the next number
        
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
        call    list_add                        ; add timeval to the list

        cmp     byte [rsi], 0                   ; check if end of stream is reached
        jne     next_sec_char
        ; if finished continue with list_add(&timeval_buffer) and next_string

;-----------------------------------------------------------------------------
; End: Read input to buffer
;-----------------------------------------------------------------------------
read_finished:
        xor     r13, r13                ; clear counter

;-----------------------------------------------------------------------------
; Start: Convert first timestamp to ASCII and print to the console
;-----------------------------------------------------------------------------

; r12 = index: index of the current timestamp
; r13 = max loop interation: size of the list - 1
        call    list_size
        mov     r13, rax                ; get size of list
        mov     r12, 0                  ; index of the current timestamp
        cmp     r13, 1                  ; check if list size <= 1
        jle     exit.exit_failure       ; yes -> exit with error status code

        dec     r13                     ; dec list_size to exit the loop

        call    list_is_sorted          ; check if list is sorted
        test    rax, rax
        jz      not_sorted              ; print error and exit if not

;       print first Timestamp
;       get list[0] timeval
        mov     rdi, timeval_buffer
        mov     rsi, 0
        call    list_get

        test    rax, rax                ; test if get was successfull
        jz      exit.exit_failure
        
        xor     rcx, rcx          ; clear counter
        xor     rax, rax          ; clear for div
        mov     rcx, 10           ; counter = 10 -> last position for sec

setup_first_timveal_sec:
        ; convert sec to ASCII
        mov     edx, dword [timeval_buffer+4]   ; setup div
        mov     eax, dword [timeval_buffer]
        mov     r11, 10
        div     r11d                            ; seconds (edx & eax) / 10 (r11d) = seconds (eax) and remainder (edx) 
        add     rdx, '0'                        ; convert remainder to ASCII
        lea     r11, [out_timestr+rcx-1]        ; write ASCII chars from end to start
        mov     byte [r11], dl                  ; write char to output string

        mov     qword [timeval_buffer], rax     ; set the new seconds for next interation
        
        dec     cl                              ; dec counter
        cmp     cl, 0                           ; check if counter > 0
        jg      setup_first_timveal_sec         ; yes -> still seconds to convert left

        ; get list[0] for usec
        mov     rdi, timeval_buffer
        mov     rsi, 0
        call    list_get

        xor     rcx, rcx          ; clear counter
        xor     rax, rax          ; clear for div
        mov     rcx, 17           ; counter = 17 -> last position for sec
        
setup_first_timveal_usec:
        mov     edx, dword [timeval_buffer+12]  ; setup div
        mov     eax, dword [timeval_buffer+8]
        mov     r11, 10
        div     r11d                            ; useconds (edx & eax) / 10 (r11d) = useconds (eax) and remainder (edx)
        add     rdx, '0'                        ; convert remainder to ASCII
        lea     r11, [out_timestr+rcx-1]        ; write ASCII chars from end to start
        mov     byte [r11], dl                  ; write char to output string

        mov     qword [timeval_buffer+8], rax   ; set the new useconds for next interation
        
        dec     cl
        cmp     cl, 11                          ; stop when the dot (position 11) is reached in the string
        jg      setup_first_timveal_usec

        ; print the first timestamp
        SYSCALL_4 SYS_WRITE, FD_STDOUT, out_timestr, out_timestr_len
;-----------------------------------------------------------------------------
; End: Convert first timestamp to ASCII and print to the console
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; Start: calculate all the timediffs for the next timestamp and print the results
;-----------------------------------------------------------------------------
calc_and_print_next:
;-----------------------------
; Start: calculation
;-----------------------------
;       get list[i] timeval
        mov     rdi, timeval_buffer
        mov     rsi, r12        ; r12 = index
        call    list_get

        test    rax, rax        ; test if get was successfull
        jz      exit.exit_failure

;       get list[i+1] timeval
        mov     rdi, calc_buffer_timeval
        mov     rsi, r12        ; r12 = index
        add     rsi, 1          ; r12 + 1 = index + 1
        call    list_get

        test    rax, rax        ; test if get was successfull
        jz      exit.exit_failure

        ; calculate usec diff
        mov     r10, qword [calc_buffer_timeval+8]
        sub     r10, qword [timeval_buffer+8]           ; list[i+1] - list[i]
        mov     qword [calc_buffer_useconds], r10       ; save usec in DRAM buffer

        ; calculate sec diff
        mov     r10, qword [calc_buffer_timeval]
        sbb     r10, qword [timeval_buffer]             ; list[i+1] - list[i]

        ; convert negative usecs to correct value
        xor     rsi, rsi
        mov     rsi, qword [calc_buffer_useconds]
        cmp     rsi, 0
        jge     usec_not_negative
        xor     rsi, 0xffffffffffffffff
        inc     rsi
        mov     r11, 0xF4240
        sub     r11, rsi
        mov     qword [calc_buffer_useconds], r11
        ; [calc_buffer_useconds] = 1 000 000 - Zweierkomplement von rsi

usec_not_negative:
        ; calculate min from sec
        mov     eax, r10d
        shr     r10, 32
        mov     edx, r10d
        mov     r11, 60
        div     r11d                                    ; EDX & EAX / r11 = EAX and EDX
        mov     byte [calc_buffer_seconds], dl          ; save seconds in DRAM buffer
        mov     r10, rax                                ; quotient - left min

        ; calculate hr from min
        mov     eax, r10d
        shr     r10, 32
        mov     edx, r10d
        mov     r11, 60
        div     r11d                                    ; EDX & EAX / r11 = EAX and EDX
        mov     byte [calc_buffer_minutes], dl          ; save minutes in DRAM buffer
        mov     r10, rax                                ; quotient - left min

        ; calculate d from hr
        mov     eax, r10d
        shr     r10, 32
        mov     edx, r10d
        mov     r11, 24
        div     r11d                                    ; EDX & EAX / r11 = EAX and EDX
        mov     byte [calc_buffer_hours], dl            ; save hours in DRAM buffer
        mov     dword [calc_buffer_days], eax           ; save days in DRAM buffer

;-----------------------------
; End: calculation
;-----------------------------

;----------------------------------
; Start: convert timestamp to ASCII
;----------------------------------
        ; setup / clear for sec to ASCII
        xor     rcx, rcx          ; clear counter
        xor     rax, rax          ; clear for div
        mov     rcx, 18           ; counter = 18 -> last position for sec

setup_timveal_sec:
        ; start: convert sec to ASCII
        mov     edx, dword [calc_buffer_timeval+4]
        mov     eax, dword [calc_buffer_timeval]
        mov     r11, 10
        div     r11d                            ; seconds (edx & eax) / 10 (r11d) = seconds (eax) and remainder (edx)
        add     rdx, '0'                        ; convert remainder to ASCII
        lea     r11, [out_str+rcx-1]            ; write ASCII chars from end to start
        mov     byte [r11], dl                  ; write char to output string

        mov     qword [calc_buffer_timeval], rax ; set the new seconds for next interation
        
        dec     cl
        cmp     cl, 8                           ; stop when the start of sec is reached in the string
        jg      setup_timveal_sec

        ; start: convert usec to ASCII
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
        div     r11d                    ; useconds (edx & eax) / 10 (r11d) = useconds (eax) and remainder (edx)
        add     rdx, '0'                ; convert remainder to ASCII
        lea     r11, [out_str+rcx-1]    ; write ASCII chars from end to start
        mov     byte [r11], dl          ; write char to output string

        mov     qword [calc_buffer_timeval+8], rax      ; set the new useconds for next interation
        
        dec     cl
        cmp     cl, 19                  ; stop when the dot is reached in the string
        jg      setup_timveal_usec

;----------------------------------
; End: convert timestamp to ASCII
;----------------------------------

;----------------------------------
; Start: convert the calcualted timediff values to ASCII
;----------------------------------
        ; r14 = 0: string_index
        xor     r14, r14        ; r14 = string_index = 0

        ; no output of days if calc_buffer_days == 0
        cmp     dword [calc_buffer_days], 0
        je      skip_days

        ; convert calc_buffer_days in string
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
        div     r11d                            ; days (edx & eax) / 10 (r11d) = days (eax) and remainder (edx)
        add     rdx, '0'                        ; convert remainder to ASCII
        lea     r11, [days_str_buffer+rcx-1]    ; write ASCII chars from end to start
        mov     byte [r11], dl                  ; write char to output string buffer

        mov     edi, eax                        ; set new value for next iteration
        inc     r14                             ; string_index++

        cmp     dl, '0'                         ; check if char == '0'
        jg      not_zero_char                   ; if not reset offset
        inc     r15                             ; else offset++
        jmp     zero_char

not_zero_char:
        xor     r15, r15                        ; reset the offset
        
zero_char:
        dec     cl
        cmp     cl, 0                           ; stop when the border for the days are reached
        jg      setup_days

        ; write number to string
        mov     r11, [days_str_buffer+r15]      ; write char numbers with offset to r11 (003452 -> 3452)
        mov     qword [timediff], r11           ; char numbers to timediff
        sub     r14, r15                        ; string_index = string_index - offset

        cmp     dword [calc_buffer_days], 1     ; check for multiple days or single day
        jg      days_output

        ; add " day, "
        lea     r11, [timediff+r14]
        mov     rdx, qword [day]                ; save string " day, " to rdx
        mov     qword [r11], rdx                ; save string " day, " to timediff
        add     r14, 6                          ; string_index += 6
        jmp     skip_days

        ; add " days "
days_output:
        lea     r11, [timediff+r14]
        mov     rdx, qword [days]               ; save string " days, " to rdx
        mov     qword [r11], rdx                ; save string " days, " to timediff
        add     r14, 7                          ; string_index += 7

skip_days:
        ; setup hours
        xor     rcx, rcx          ; clear counter
        xor     rax, rax          ; clear for div
        mov     rcx, r14          ; counter = string_index
        add     rcx, 2
        
setup_hours:
        mov     al, byte [calc_buffer_hours]
        mov     r11, 10
        div     r11b                            ; hours (al) / 10 (r11b) = hours (al) and remainder (ah)
        add     ah, '0'                         ; convert remainder to ASCII
        lea     r11, [timediff+rcx-1]           ; write ASCII chars from end to start

        mov     byte [calc_buffer_hours], al    ; write quotient to al

        shr     ax, 8
        mov     byte [r11], al                  ; write char to output string

        dec     cl
        cmp     rcx, r14                        ; stop after the 2 hour digits
        jg      setup_hours
        add     r14, 2                          ; inc string_index for the 2 houres ASCII

        mov     byte [timediff+r14], ':'        ; add hh:mm seperator
        inc     r14                             ; inc string_index beacuse of the ":"

        ; setup minutes
        xor     rcx, rcx          ; clear counter
        xor     rax, rax          ; clear for div
        mov     rcx, r14          ; counter = 2
        add     rcx, 2
        
setup_minutes:
        mov     al, byte [calc_buffer_minutes]
        mov     r11, 10
        div     r11b                            ; minutes (al) / 10 (r11b) = minutes (al) and remainder (ah)
        add     ah, '0'                         ; convert remainder to ASCII
        lea     r11, [timediff+rcx-1]           ; write ASCII chars from end to start

        mov     byte [calc_buffer_minutes], al  ; write quotient to al

        shr     ax, 8
        mov     byte [r11], al                  ; write char to output string

        dec     cl
        cmp     rcx, r14                        ; stop after the 2 min digits
        jg      setup_minutes
        add     r14, 2                          ; inc string_index for the 2 min ASCII

        mov     byte [timediff+r14], ':'        ; add mm:ss seperator
        inc     r14                             ; inc string_index beacuse of the ":"

        ; setup seconds
        xor     rcx, rcx          ; clear counter
        xor     rax, rax          ; clear for div
        mov     rcx, r14          ; counter = 2
        add     rcx, 2
        
setup_seconds:
        mov     al, byte [calc_buffer_seconds]
        mov     r11, 10
        div     r11b                            ; seconds (al) / 10 (r11b) = seconds (al) and remainder (ah)
        add     ah, '0'                         ; convert remainder to ASCII
        lea     r11, [timediff+rcx-1]           ; write ASCII chars from end to start

        mov     byte [calc_buffer_seconds], al  ; write quotient to al

        shr     ax, 8
        mov     byte [r11], al                  ; write char to output string

        dec     cl
        cmp     rcx, r14                        ; stop after the 2 sec digits
        jg      setup_seconds
        add     r14, 2                          ; inc string_index for the 2 sec ASCII

        mov     byte [timediff+r14], '.'        ; add ss:us seperator
        inc     r14                             ; inc string_index beacuse of the ":"
        ; setup useconds
        xor     rcx, rcx          ; clear counter
        xor     rax, rax          ; clear for div
        mov     rcx, r14          ; counter = 2
        add     rcx, 6
        
setup_useconds:
        xor     edx, edx
        mov     eax, [calc_buffer_useconds]
        mov     r11, 10
        div     r11d                                    ; useconds (edx) / 10 (eax) = useconds (eax) and remainder (rdx)
        add     rdx, '0'                                ; convert remainder to ASCII
        lea     r11, [timediff+rcx-1]                   ; write ASCII chars from end to start
        mov     byte [r11], dl                          ; write char to output string buffer

        mov     dword [calc_buffer_useconds], eax       ; set new value for next iteration

        dec     cl
        cmp     rcx, r14                                ; stop after the 6 usec digits
        jg      setup_useconds

        ; print the timestamp and timediff
        SYSCALL_4 SYS_WRITE, FD_STDOUT, out_str, out_str_len

        ; clear timediff buffer string
        xor     rcx, rcx
        mov     rcx, 27
start_clear:
        mov     byte [timediff+rcx], 0        ; clear timediff for next calculation
        dec     rcx
        cmp     rcx, 0
        jg      start_clear

        inc     r12              ; index++
        cmp     r12, r13         ; check if index < (list_size-1)
        jl      calc_and_print_next

;----------------------------------
; End: convert the calcualted timediff values to ASCII
;----------------------------------
        jmp     exit            ; exit with success

not_number:
        ; print not_number_error_str
        SYSCALL_4 SYS_WRITE, FD_STDOUT, not_number_error_str, not_number_error_str_len
        jmp     exit.exit_failure       ; exit with error status code

not_sorted:
        ; print not_sorted_error_str
        SYSCALL_4 SYS_WRITE, FD_STDOUT, not_sorted_error_str, not_sorted_error_str_len
        jmp     exit.exit_failure       ; exit with error status code

; Need to restore regestries
pop     r15             ; restore r15
pop     r14             ; restore r14
pop     r13             ; restore r13
pop     r12             ; restore r12

        ;-----------------------------------------------------------
        ; call system exit and return to operating system / shell
        ;-----------------------------------------------------------
exit:
.exit:  SYSCALL_2 SYS_EXIT, 0
.exit_failure: SYSCALL_2 SYS_EXIT, -1
        ;-----------------------------------------------------------
        ; END OF PROGRAM
        ;-----------------------------------------------------------
