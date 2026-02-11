org 0x0
bits 16

%define nwL 0x0d, 0x0a  ;macro for new line and carriage

start:

    mov si, msg_hello
    call puts

.halt:
	cli
	hlt

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

msg_hello: db 'Hello World from KERNEL!', nwL, 0

