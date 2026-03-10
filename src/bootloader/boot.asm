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
   ; setup data segments 
	;set es:di to 0000:0000 to check for bios bugs
	mov ax, 0       ; can't write to ds/es directly
    mov ds, ax
    mov es, ax

    ; setup stack
    mov ss, ax
    mov sp, 0x7C00 ;stack grows downward from where are loaded in from memory
	
	push es
	push word .after ;making sure code is being read from 0000:7c00 (or in this case starting from the .after label)
	retf
.after: 

	;attempt to read from floppy, dl is what drive num we are reading
	mov [ebr_drive_number], dl
	
	;read drive param
	push es
	mov ah, 0x08 ;read param specification
	int 0x13 ;interrupt 13
	jc floppy_error
	pop es

	and cl, 0x3F ;removes top 2 bits of cl
	xor ch, ch ;clears c high, gets filled with num of cylinders - 1 (this includes top 2 bits of cl, why we clear the top two earlier)
	mov [bdb_sectors_per_track], cx

	inc dh ;dh is filled with last index of heads, i.e. num of heads - 1
	mov [bdb_heads], dh ;head amt

	;calc FAT root dir
	mov ax, [bdb_sectors_per_fat]
    mov bl, [bdb_fat_count]
    xor bh, bh
    mul bx ;move ax<-sectors per fat, mov bl<- fat count, clear bh(fat count is db not dw so we only take lower reg) and mult bx with ax
	add ax, [bdb_reserved_sectors] ;move past reserved to root dir and push val onto stack
    mov [lba_data_region], ax
    push ax
    
	;calc size of root dir
    mov ax, [bdb_dir_entries_count] ;num of entries per directory
    shl ax, 5 ;ax *32 -> 2^5 ;each entry is 32 bits long
    xor dx, dx ;clear dx, this is where any remainder would go when dividing
    div word [bdb_bytes_per_sector] ; checking how many sectors we require for num of bytes

	test dx, dx ; dx = 0
	jz .root_dir_after ;checking if remainder and incr if so
	inc ax

.root_dir_after:
	add [lba_data_region], ax ;calculating the starting lba data region for when we do fat lookups with clusters
	;read root
	mov cl, al ;num  of sectors root dir takes up	
	pop ax	;LBA of rootdir
	mov dl, [ebr_drive_number]
	mov bx, buffer	;es:bx buffer
	call disk_read

	;search for kernel.bin
	xor bx, bx
	mov di, buffer

.search_kernel:
	mov si, file_kernel_bin
	mov cx, 11 ;max num of characters to check

	push di
	repe cmpsb
	pop di
	je .found_kernel ;zf set as every character was found to be equal, i.e. matching string

	add di, 32 ;move to next dir entry
	inc bx ;counter for num of entries searched
	cmp bx, [bdb_dir_entries_count] ;making sure num of entries searches is not more than total in directory
	jl .search_kernel
	jmp kernel_not_found_error
.found_kernel:
	;di has address of dir entry, first cluster is 26 offset
	mov ax, [di + 26]
	mov [kernel_cluster], ax ;cluster number of the first cluster in fat chain

	;load fat
	mov ax, [bdb_reserved_sectors]
	mov bx, buffer
	mov cl, [bdb_sectors_per_fat]
	mov dl, [ebr_drive_number]
	call disk_read

	mov bx, KERNEL_LOAD_SEG
	mov es, bx
	mov bx, KERNEL_LOAD_OFFSET ;preps disk_read to load the kernel bin file into memory
.load_kernel_loop:
	;converting the cluster number into an LBA address for our disk read function
	mov ax, [kernel_cluster]
	sub ax, 2 ;Clusters start at 2 and so cluster 2 should start at the beginning of the LBA data region, this is what we're accounting for
	add ax, [lba_data_region]

	mov cl, [bdb_sectors_per_cluster] ; read 1 cluster at a time
	mov dl, [ebr_drive_number]
	call disk_read ; reading into kernel offset

	add bx, [bdb_bytes_per_sector] ; making sure we dont overwrite the sector we just read

	mov ax, [kernel_cluster]
	mov cx, 3
	mul cx
	mov cx, 2
	div cx ;Each cluster is 12 bits, or 1.5 bytes. This is multiplying the cluster number by 1.5 (3/2=1.5) to find the byte offset from the start of the FAT table

	mov si, buffer
	add si, ax
	mov ax, [ds:si] ; This reads 2 bytes at seg:off -> ds:si (ds is data segment) si is the buffer i.e. where the fat table is located + the calculated byte offset of current cluster
	; The odd or even calculation is because each cluster is 12 bits instead of an even 8 or 16. If our current cluster is an odd cluster it means the 1st byte has half of the previous cluster's info and the current cluster's info. shaped like this -> AAAAAAAA|BBBBAAAA|BBBBBBBB if we are reading the 0 cluster (the A's) we read two bytes starting from the all A byte. this would give us something like BBBBAAAA:AAAAAAAA (the order seems backwards when its read) We do not want the B info as we are calculating the A. 0 is an even cluster so we cut off the top 4 bits using the 0x0FFF mask, which has its first four bits as 0. If we were trying to read the B data, or cluster 1, we would read two bytes starting from the 1 offset which would look like, BBBBBBBB:BBBBAAAA | Now we see we don't want the bottom quarter of the data so we simply shift down(right) 4 bits to cut them off. Whatever result we get (even or odd) will be the value of the next cluster in the chain for us to read
	or dx, dx
	jz .even
.odd:
	shr ax, 4 ;div ax by 16 -> 2^4
	jmp .next_cluster_after
.even:
	and ax, 0x0FFF

.next_cluster_after:
	cmp ax, 0x0FF8 ; an end of a cluster chain is denoted by this value
	jae .read_finish
	
	mov [kernel_cluster], ax
	jmp .load_kernel_loop

.read_finish:
	mov dl, [ebr_drive_number]

	mov ax, KERNEL_LOAD_SEG
	mov ds, ax
	mov es, ax
; this is just simply loading the data segment and offset to where the kernel will begin loading into and then jumping to that address to start running the kernel
	jmp KERNEL_LOAD_SEG:KERNEL_LOAD_OFFSET

	jmp wait_key_and_reboot



	cli
    hlt

;error handling


floppy_error:
	mov si, msg_read_failed
	call puts
	jmp wait_key_and_reboot

kernel_not_found_error:
	mov si, msg_kernel_nf
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
	push ax		;Save registers we modify
	push bx
	push cx
	push dx
	push di


	push cx
	call lba_to_chs ; convert into chs
	pop ax	;move sectors to read -> al (Since only the lower bits of cx were set)
	mov ah, 0x2
	mov di, 3	;counter for retry write loop
.retry:
	pusha	;save all registers from interrupt
	stc	;set carry flag
	int 0x13	;carry flag cleared -> success
	jnc	.done
	
	;failed
	popa
	call disk_reset

	dec di
	test di, di
	jnz .retry

.fail:
	;write attempts exhausted
	jmp floppy_error

.done:
	popa

	pop di		;Restore registers we modified
	pop dx
	pop cx
	pop bx
	pop ax
	ret

;disk reset
;params:
;	-dl: drive number
disk_reset:	
	pusha
	mov ah,0
	stc
	int 0x13
	jc floppy_error
	popa
	ret

;prints a string
;param: ds:si points to string
puts:
	push si
	push ax
	cld
.loop:
	lodsb
	or al, al
	jz .done

	mov ah, 0x0e ;bios int val for video tty
	mov bh, 0 ;page=0
	int 0x10 ;bios int
	jmp .loop

.done:
	pop ax
	pop si
	ret

msg_kernel_nf: db 'KERNEL.BIN file not found', nwL, 0
msg_read_failed: db 'Read from disk failed', nwL, 0
file_kernel_bin: db 'KERNEL  BIN'
kernel_cluster: dw 0
lba_data_region: dw 0

KERNEL_LOAD_SEG	equ 0x2000
KERNEL_LOAD_OFFSET equ 0

times 510-($-$$) db 0
dw 0AA55h

buffer:
