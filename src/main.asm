org 0x7C00
bits 16

%define nwL 0x0d, 0x0a  ;macro for new line and carriage

start:
    jmp main

; prints a string to the screen
; params:
;   ds:si points to string

puts:
    ;save registers we modify
    push si
    push ax

.loop:
    lodsb       ;loads next character in al
    or al, al   ;verify if next character is null
    jz .done
    
    mov ah, 0x0e ;calling bios interupt for video TTY
    mov bh, 0   ;setting page to 0
    int 0x10
    jmp .loop

.done:
    pop ax
    pop si
    ret
main:
    ; setup data segments 
    mov ax, 0       ; can't write to ds/es directly
    mov ds, ax
    mov es, ax

    ; setup stack
    mov ss, ax
    mov sp, 0x7C00 ;stack grows downward from where are loaded in from memory
    
    ;set message in SI and call print function
    mov si, msg_hello
    call puts

    hlt
.halt:
    jmp .halt

msg_hello: db 'Hello World!', nwL, 0

times 510-($-$$) db 0
dw 0AA55h
