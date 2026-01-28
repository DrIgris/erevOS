org 0x7C00
bits 16

%define nwL 0x0d, 0x0a  ;macro for new line and carriage

; FAT12 header
jmp short start
nop

bdb_oem: db 'MSWIN4.1'
bdb_bytes_per_sector: dw 512
bdb_sectors_per_cluster: db 1
bdb_reserved_sectors: dw 1
bdb_fat_count: db 2
bdb_dir_entries_count: dw 0E0h
bdb_total_sectors: dw 2880
bdb_media_descriptor_type: db 0F0h
bdb_sectors_per_fat: dw 9
bdb_sectors_per_track: dw 18
bdb_heads: dw 2
bdb_hidden_sectors: dd 0
bdb_large_sector_count: dd 0

;extended boot record
ebr_drive_number: db 0
ebr_reserved: db 0
ebr_signature: db 29h
ebr_volume_id: db 12h, 34h, 56h, 78h
ebr_volume_label: db 'ErevOS     ' ;11bytes, pad with 5 spaces at end
ebr_system_id: db 'FAT12   ' 

; end of headers

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

;error handling

floppy_error:
	mov si, msg_read_failed
	call puts
	jmp wait_key_and_reboot

wait_key_and_reboot:
	mov ah, 0
	int 16h	;wait for keypress
	jmp 0FFFFh:0	;jump to bios start to reboot
	

.halt:
	cli	;disable interrupt
    jmp .halt

;Disk Routine

;LBA -> CHS conversion
;params:
;	-ax: LBA Address
;returns:
;	-cd [bits 0-5]: sector number
;	-cd [bits 6-15]: cylinder
;	-dh: head num

lba_to_chs:
	push ax	;saving registers
	push dx

	xor dx,dx	;clearing dx
	div word [bdb_sectors_per_track]	;ax=LBA/sectorsPerTrack ;dx=LBA%sectorsPerTrack
	inc dx
	mov cx, dx	;cx->sector

	xor dx,dx	;clear dx again
	div word [bdb_heads]	;ax=LBA/sectorsPerTrack/heads -> cylinder ;dx=LBA/sectorsPerTrack%heads -> head

	mov dh, dl	;dl is lower 8 bits of dx so dh=head
	mov ch, al	;ch=lower 8 bits of cylinder
	shl ah, 6	;2 bits of cylinder left in ax, ah is upper 8 bits. We shift left by 6 to get them in proper pos
	or cl, ah	
	;or with lower bits of cd(cl) to OR the sector number of 6 bits with the 
	; 2 bits of cylinder and 6 empty bits from the shift left. 
	;This creates cd register to hold sector number and cylinder
	
	pop ax ;pop dx into ax
	mov dl, al ;only perserve dl since dh is in our return
	pop ax	;pop ax into ax
	ret

;Read from disk
;params:
;	-ax: LBA
;	-cl: num of sectors to read (max 128)
;	-dl: drive number
;	-es:bx: mem address to store data
disk_read:
	push cx ;save cx since call overwrites
	call lba_to_chs ; convert into chs
	pop ax	;move sectors to read -> al (Since only the lower bits of cx were set)
	mov ah, 02h
	mov di, 3	;counter for retry write loop
.retry:
	pusha	;save all registers from interrupt
	stc	;set carry flag
	int 13h	;carry flag cleared -> success
	jnc	.done
	
	;failed
	popa
	call desk_reset

	dec di
	test di, di
	jnz .retry

.fail:
	;write attempts exhausted
	jmp floppy_error

msg_hello: db 'Hello World!', nwL, 0
msg_read_failed: db 'Read from disk failed', nwL, 0

times 510-($-$$) db 0
dw 0AA55h
