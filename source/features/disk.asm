; ==================================================================
; MikeOS -- The Mike Operating System kernel
; Copyright (C) 2006 - 2021 MikeOS Developers -- see doc/LICENSE.TXT
;
; FAT12 FLOPPY DISK ROUTINES (V4.6.2a6)
; ==================================================================

; ------------------------------------------------------------------
; os_get_file_list -- Generate comma-separated string of files on disk
; IN: AX = location to store zero-terminated filename string,
;     BX = max length of filename string (2 b to 32 K)
; OUT: AX = location where zero-terminated filename string was placed
;      errno and CY set on error

os_get_file_list:
	push ds
	push es
	pusha
	mov bx, 1024			; disable name buffer overrun check

	mov [.file_list_tmp], ax	; save location and size
	dec bx
	mov [.count_tmp], bx		; max count, leave 1 for terminator
	inc bx

	cmp bx, 1			; initialize array
	jg .cont1			; read directory error will return
	mov bx, 1			; return an 'empty' array
  .cont1:
	mov cx, bx
	mov di, ax			; set entire array to terminator
	mov al, 0
	rep stosb

	cmp bx, 2			; need room for at least 1 char + terminator
	jge .cont2			; also limit max to 32K
  .error:
	mov cx, 0x30c			; Not enough space
	stc
	jmp short .done

  .cont2:
	call disk_read_root_dir		; get root directory in system designated buffer
	mov bx, disk_buffer		; Set ES:BX to point to OS buffer
	push cs
	pop es
	jnc .show_dir_init		; ES:BX points to root buffer start
	jmp short .done2		; errno = read error, CY set

  .fine:
	xor cx, cx
	clc				; directory read o.k., at least one byte in buffer
  .done:
;	mov [errno], cx
  .done2:
	popa				; initialize array is automatically terminated
	pop es
	pop ds
	ret


  .show_dir_init:
	mov di, [.file_list_tmp]	; Name destination buffer
	xor bp, bp			; Save count to determine if this is first name (no comma)

	push es				; reverse segment pointers
	push ds
	pop es				; ES = program seg
	pop ds				; DS = directory seg

  .start_entry:
	mov si, bx			; maintain starting offset for easy computation
	mov al, [si+11]			; File attributes for entry
	cmp al, 0Fh			; LFN marker, skip it
	je .next_entry

	test al, 18h			; Is this a directory entry or volume label?
	jnz .next_entry			; Yes, ignore it

	lodsb				; First name char (inc SI)
	cmp al, 229			; If we read 229 (e5h) = deleted filename
	je .next_entry			;   05 also used by a few OS

	cmp al, 0			; 1st byte 0 => entry never used
					; (should be unused here to end of directory)
	je .fine

  .testdirentry:
	cmp al, ' '			; Windows sometimes puts 0 (UTF-8) or 0FFh
	jle .next_entry			; 1st char cannot be space
	cmp al, '~'
	ja .next_entry

  .gotfilename:				; Got a filename that passes testing
					; (AL contains 1st, SI points to 2nd char)
	cmp bp, 0			; 1st entry?
	je .set_name			; yes, no comma
	push ax
	mov al, ','			; separate entries with ',' (not wanted before first)
	stosb
	pop ax
	dec word [es:.count_tmp]
	jle .fine			; exhausted count, exit with partial last entry

  .set_name:
	inc bp				; Count entry
	mov cx, 1			; Count filename char to know when to stop
  .loopy:
	stosb				; char
	dec word [es:.count_tmp]
	jle .fine			; exhausted count, exit with partial last entry
	cmp cx, 8
	je .q_add_dot

	lodsb				; next char from high buffer
	inc cx
	cmp al, ' '
	je .q_add_dot
	jmp .loopy			; store char and check array overrun

  .next_entry:
	mov ax, ds
	add ax, ParaPerEntry		; point to beginning of next entry
	mov ds, ax
	jmp .start_entry

  .q_add_dot:
	mov cx, 8			; move pointer and count to current entry extension
	mov si, bx
	add si, cx

	lodsb
	cmp al, ' '			; extension?
	je .next_entry			; no

	push ax				; add dot, begin extension transfer
	mov al, '.'
	stosb
	pop ax
	dec word [es:.count_tmp]
	jle .fine			; exhausted count, exit with partial last entry

  .dot_loop:
	stosb				; char
	inc cx
	dec word [es:.count_tmp]
	jle .fine			; exhausted count, exit with partial last entry
	cmp cx, 11
	je .next_entry			; finished this name (3 char extension)

	lodsb
	cmp al, ' '			; more extension?
	jne .dot_loop 			; yes
	jmp .next_entry			; (< 3 char extension is o.k.)


	.file_list_tmp		dw 0	; list string pointer
	.count_tmp		dw 0	; max size string buffer


; ------------------------------------------------------------------
; os_load_file -- Load file into RAM
; IN: AX = location of filename, CX = location in RAM to load file
; OUT: EBX = file size (in bytes), carry set if file not found


os_load_file:
	call int_filename_convert
	jc .root_problem

	mov [.filename_loc], ax
	mov [.load_position], cx

	mov eax, 0
	call disk_reset_floppy
	jnc .floppy_ok

	mov ax, .err_msg_floppy_reset
	jmp os_fatal_error


.floppy_ok:
	mov ax, 19
	call disk_convert_l2hts

	mov si, disk_buffer
	mov bx, si

	mov ah, 2
	mov al, 14

	pusha


.read_root_dir:
	popa
	pusha

	stc
	int 13h
	jnc .search_root_dir

	call disk_reset_floppy
	jnc .read_root_dir

	popa
	jmp .root_problem


.search_root_dir:
	popa

	mov cx, word 224
	mov bx, -32


.next_root_entry:
	add bx, 32
	mov di, disk_buffer
	add di, bx

	mov al, [di]

	cmp al, 0
	je .root_problem

	cmp al, 229
	je .next_root_entry

	mov al, [di+11]

	cmp al, 0Fh
	je .next_root_entry

	test al, 18h
	jnz .next_root_entry

	mov byte [di+11], 0

	mov ax, di
	call os_string_uppercase

	mov si, [.filename_loc]

	call os_string_compare
	jc .found_file_to_load

	loop .next_root_entry


.root_problem:
	mov ebx, 0
	stc
	ret


.found_file_to_load:
	mov eax, [di+28]
	mov dword [.file_size], eax

	cmp ax, 0
	je .end

	mov ax, [di+26]
	mov word [.cluster], ax

	mov ax, 1
	call disk_convert_l2hts

	mov di, disk_buffer
	mov bx, di

	mov ah, 2
	mov al, 9

	pusha


.read_fat:
	popa
	pusha

	stc
	int 13h
	jnc .read_fat_ok

	call disk_reset_floppy
	jnc .read_fat

	popa
	jmp .root_problem


.read_fat_ok:
	popa


.load_file_sector:
	mov ax, word [.cluster]
	add ax, 31

	call disk_convert_l2hts

	mov bx, [.load_position]

	mov ah, 02
	mov al, 01

	stc
	int 13h
	jnc .calculate_next_cluster

	call disk_reset_floppy
	jnc .load_file_sector

	mov ax, .err_msg_floppy_reset
	jmp os_fatal_error


.calculate_next_cluster:
	mov ax, [.cluster]
	mov bx, 3
	mul bx
	mov bx, 2
	div bx

	mov si, disk_buffer
	add si, ax
	mov ax, word [ds:si]

	or dx, dx
	jz .even


.odd:
	shr ax, 4
	jmp .calculate_cluster_cont


.even:
	and ax, 0FFFh


.calculate_cluster_cont:
	mov word [.cluster], ax

	cmp ax, 0FF8h
	jae .end

	add word [.load_position], 512
	jmp .load_file_sector


.end:
	mov ebx, [.file_size]
	clc
	ret


.bootd db 0
.cluster dw 0
.pointer dw 0
.filename_loc dw 0
.load_position dw 0
.file_size dd 0
.string_buff times 12 db 0

.err_msg_floppy_reset db 'os_load_file: Floppy failed to reset', 0

; --------------------------------------------------------------------------
; os_write_file -- Save (max 64K) file to disk
; IN: AX = filename, BX = data location, CX = bytes to write
; OUT: Carry clear if OK, set if failure

os_write_file:
	pusha

	mov word [.filesize], cx
	mov word [.location], bx
	mov word [.filename], ax	; original name pointer for 'create file'

	call os_file_exists		; Don't overwrite a file if it exists!
					; does name conversion and checks name size
					; returns not found (CY) if error or not found
	jnc near .failure		; DOS formatted name found in root directory


	; First, zero out the .free_clusters list from any previous execution
	pusha

	mov di, .free_clusters
	mov cx, 128
.clean_free_loop:
	mov word [di], 0
	inc di
	inc di
	loop .clean_free_loop

	popa


	; Next, we need to calculate now many 512 byte clusters are required

	mov ax, cx
	mov dx, 0
	mov bx, 512			; Divide file size by 512 to get clusters needed
	div bx
	cmp dx, 0
	jg .add_a_bit			; If there's a remainder, we need another cluster
	jmp .carry_on

.add_a_bit:
	add ax, 1
.carry_on:

	mov word [.clusters_needed], ax

	mov word ax, [.filename]	; Get filename back

	call os_create_file		; Create empty root dir entry for this file
	jc near .failure		; If we can't write to the media, jump out

	mov word bx, [.filesize]
	cmp bx, 0
	je near .finished

	call disk_read_fat		; Get FAT copy into RAM
	jc near .failure		; Read error, jump out
	mov si, disk_buffer + 3		; And point SI at it (skipping first two clusters)

	mov bx, 2			; Current cluster counter
	mov word cx, [.clusters_needed]
	mov dx, 0			; Offset in .free_clusters list

.find_free_cluster:
	lodsw				; Get a word
	and ax, 0FFFh			; Mask out for even
	jz .found_free_even		; Free entry?

.more_odd:
	inc bx				; If not, bump our counter
	dec si				; 'lodsw' moved on two chars; we only want to move on one

	lodsw				; Get word
	shr ax, 4			; Shift for odd
	or ax, ax			; Free entry?
	jz .found_free_odd

.more_even:
	inc bx				; If not, keep going
	jmp .find_free_cluster


.found_free_even:
	push si
	mov si, .free_clusters		; Store cluster
	add si, dx
	mov word [si], bx
	pop si

	dec cx				; Got all the clusters we need?
	cmp cx, 0
	je .finished_list

	inc dx				; Next word in our list
	inc dx
	jmp .more_odd

.found_free_odd:
	push si
	mov si, .free_clusters		; Store cluster
	add si, dx
	mov word [si], bx
	pop si

	dec cx
	cmp cx, 0
	je .finished_list

	inc dx				; Next word in our list
	inc dx
	jmp .more_even



.finished_list:

	; Now the .free_clusters table contains a series of numbers (words)
	; that correspond to free clusters on the disk; the next job is to
	; create a cluster chain in the FAT for our file

	mov cx, 0			; .free_clusters offset counter
	mov word [.count], 1		; General cluster counter

.chain_loop:
	mov word ax, [.count]		; Is this the last cluster?
	cmp word ax, [.clusters_needed]
	je .last_cluster

	mov di, .free_clusters

	add di, cx
	mov word bx, [di]		; Get cluster

	mov ax, bx			; Find out if it's an odd or even cluster
	mov dx, 0
	mov bx, 3
	mul bx
	mov bx, 2
	div bx				; DX = [.cluster] mod 2
	mov si, disk_buffer
	add si, ax			; AX = word in FAT for the 12 bit entry
	mov ax, word [ds:si]

	or dx, dx			; If DX = 0, [.cluster] = even; if DX = 1 then odd
	jz .even

.odd:
	and ax, 000Fh			; Zero out bits we want to use
	mov di, .free_clusters
	add di, cx			; Get offset in .free_clusters
	mov word bx, [di+2]		; Get number of NEXT cluster
	shl bx, 4			; And convert it into right format for FAT
	add ax, bx

	mov word [ds:si], ax		; Store cluster data back in FAT copy in RAM

	inc word [.count]
	inc cx				; Move on a word in .free_clusters
	inc cx

	jmp .chain_loop

.even:
	and ax, 0F000h			; Zero out bits we want to use
	mov di, .free_clusters
	add di, cx			; Get offset in .free_clusters
	mov word bx, [di+2]		; Get number of NEXT free cluster

	add ax, bx

	mov word [ds:si], ax		; Store cluster data back in FAT copy in RAM

	inc word [.count]
	inc cx				; Move on a word in .free_clusters
	inc cx

	jmp .chain_loop



.last_cluster:
	mov di, .free_clusters
	add di, cx
	mov word bx, [di]		; Get cluster

	mov ax, bx

	mov dx, 0
	mov bx, 3
	mul bx
	mov bx, 2
	div bx				; DX = [.cluster] mod 2
	mov si, disk_buffer
	add si, ax			; AX = word in FAT for the 12 bit entry
	mov ax, word [ds:si]

	or dx, dx			; If DX = 0, [.cluster] = even; if DX = 1 then odd
	jz .even_last

.odd_last:
	and ax, 000Fh			; Set relevant parts to FF8h (last cluster in file)
	add ax, 0FF80h
	jmp .finito

.even_last:
	and ax, 0F000h			; Same as above, but for an even cluster
	add ax, 0FF8h


.finito:
	mov word [ds:si], ax

	call disk_write_fat		; Save our FAT back to disk
	jc near .failure		; Write error, jump out

	; Now it's time to save the sectors to disk!

	mov cx, 0

.save_loop:
	mov di, .free_clusters
	add di, cx
	mov word ax, [di]

	cmp ax, 0
	je near .write_root_entry

	pusha

	add ax, 31

	call disk_convert_l2hts

	mov word bx, [.location]

	mov ah, 3
	mov al, 1
	stc
	int 13h

	popa

	add word [.location], 512
	inc cx
	inc cx
	jmp .save_loop


.write_root_entry:

	; Now it's time to head back to the root directory, find our
	; entry and update it with the cluster in use and file size

	call disk_read_root_dir
	jc near .failure		; Read error, goto error exit

	mov word ax, [.filename]
	call int_filename_convert	; Make FAT12-style filename, modifies AX
	call disk_get_root_entry

	or byte [di+11], 0x20		; Ensure 'archive' is set

	call sys_disk_time		; Update time of last write
	call sys_disk_date		;  and date
	mov [di+22], cx			; time (now)
	mov [di+24], dx			; date (today)

	mov word ax, [.free_clusters]	; Get first file cluster from list
	mov word [di+26], ax		; Save starting location into root dir entry

	mov word cx, [.filesize]	; Update file size (low)
	mov word [di+28], cx
	mov word [di+30], 0		; File size (high)

	call disk_write_root_dir
	jc near .failure		; Write error, jump out

.finished:
	popa
	clc
	ret

.failure:
	popa
	stc				; Couldn't write!
	ret


	.filesize	dw 0
	.cluster	dw 0
	.count		dw 0
	.location	dw 0

	.clusters_needed	dw 0

	.filename	dw 0

	.free_clusters	times 128 dw 0


; --------------------------------------------------------------------------
; os_file_exists -- Check for presence of file on the floppy
; IN: AX = filename location
; OUT: carry clear if found, set if not; registers, except ES, preserved

os_file_exists:
	pusha

	call int_filename_convert	; Make FAT12-style filename, modifies AX
	jc .failure			; bad conversion, includes 0 or too many characters

	call disk_read_root_dir		; sets es = ds, root in es:disk_buffer, other reg preserved
	jc .failure

;	push ds				; not needed, yet
;	pop es
;	mov di, disk_buffer		; ES:DS -> root buffer

	call disk_get_root_entry	; Set or clear carry flag
					; ES:DI points to table entry (if exists)

	popa
	ret

.failure:
	stc
	popa
	ret


; --------------------------------------------------------------------------
; os_create_file -- Creates a new 0-byte file on the floppy disk
; IN: AX = location of filename; OUT: Nothing


os_create_file:
        pusha

        call os_file_exists
        jnc .failure                 ; File already exists

        call int_filename_convert
        jc .failure                  ; Invalid filename

        push ax                      ; Save converted filename

        mov di, disk_buffer

        mov cx, 224
.next_entry:
        mov al, [di]
        cmp al, 0
        je .found_free_entry

        cmp al, 0E5h
        je .found_free_entry

        add di, 32
        loop .next_entry

        pop ax                       ; No free entry, restore stack
        jmp .failure


.found_free_entry:
        pop si
        mov cx, 11
        rep movsb

        sub di, 11

        call sys_disk_time
        call sys_disk_date
        xor ax, ax

        mov byte [di+11], 0x20
        mov byte [di+12], al
        mov byte [di+13], al
        mov [di+14], cx
        mov [di+16], dx
        mov [di+18], ax
        mov [di+20], ax
        mov [di+22], cx
        mov [di+24], dx
        mov [di+26], ax
        mov [di+28], ax
        mov [di+30], ax

        call disk_write_root_dir
        jc .failure

        inc word [file_operation_count]

        popa
        clc
        ret


.failure:
        popa
        stc
        ret



; --------------------------------------------------------------------------
; os_remove_file -- Deletes the specified file from the filesystem
; IN: AX = location of filename to remove


os_remove_file:
        pusha

        call int_filename_convert
        jc .failure

        mov [.filename], ax

        call disk_read_root_dir
        jc .failure

        mov di, disk_buffer
        mov ax, [.filename]
        call disk_get_root_entry
        jc .failure

        ; Check whether the file is protected (read-only)
        test byte [es:di+11], 01h
        jnz .failure

        mov ax, [es:di+26]
        mov [.cluster], ax

        mov byte [di], 0E5h

        inc di
        mov cx, 0

.clean_loop:
        mov byte [di], 0
        inc di
        inc cx
        cmp cx, 31
        jl .clean_loop

        call disk_write_root_dir
        jc .failure

        call disk_read_fat
        jc .failure

        mov di, disk_buffer

.more_clusters:
        mov ax, [.cluster]

        cmp ax, 0
        je .nothing_to_do

        mov bx, 3
        mul bx
        mov bx, 2
        div bx

        mov si, disk_buffer
        add si, ax
        mov ax, [ds:si]

        or dx, dx
        jz .even

.odd:
        push ax
        and ax, 000Fh
        mov [ds:si], ax
        pop ax

        shr ax, 4
        jmp .calculate_cluster_cont

.even:
        push ax
        and ax, 0F000h
        mov [ds:si], ax
        pop ax

        and ax, 0FFFh

.calculate_cluster_cont:
        mov [.cluster], ax

        cmp ax, 0FF8h
        jae .end

        jmp .more_clusters

.end:
        call disk_write_fat
        jc .failure

.nothing_to_do:
        inc word [file_operation_count]
        popa
        clc
        ret

.failure:
        popa
        stc
        ret

.filename dw 0
.cluster dw 0



; --------------------------------------------------------------------------
; os_rename_file -- Change the name of a file on the disk
; IN: AX = filename to change, BX = new filename (zero-terminated strings)
; OUT: carry set on error


os_rename_file:
        pusha

        mov [.old_filename], ax
        mov [.new_filename], bx

        call disk_read_root_dir
        jc .failure

        mov ax, [.old_filename]
        call int_filename_convert
        jc .failure

        mov di, disk_buffer
        call disk_get_root_entry
        jc .failure

        ; Reject protected files
        test byte [es:di+11], 01h
        jnz .failure

        mov ax, [.new_filename]
        call int_filename_convert
        jc .failure

        mov si, ax
        mov cx, 11
        rep movsb

        call disk_write_root_dir
        jc .failure

        inc word [file_operation_count]

        popa
        clc
        ret

.failure:
        popa
        stc
        ret

.old_filename dw 0
.new_filename dw 0



; --------------------------------------------------------------------------
; os_get_file_size -- Get file size information for specified file
; IN: AX = filename; OUT: EBX = file size in bytes (up to 4 Gb)
; or carry set if file not found


os_get_file_size:
        pusha

        call int_filename_convert
        jc .failure

        mov [.filename], ax

        call disk_read_root_dir
        jc .failure

        mov ax, [.filename]
        mov di, disk_buffer

        call disk_get_root_entry
        jc .failure

        mov ebx, [di+28]
        mov [.tmp], ebx

        popa

        mov ebx, [.tmp]
        clc
        ret

.failure:
        popa
        stc
        ret

.filename dw 0
.tmp dd 0


; -------------------------------------------------
; Protect a file using FAT12 read-only attribute

os_protect_file:
        pusha

        call int_filename_convert
        jc .failure

        mov [.filename], ax

        call disk_read_root_dir
        jc .failure

        mov ax, [.filename]
        mov di, disk_buffer
        call disk_get_root_entry
        jc .failure

        or byte [es:di+11], 01h

        call disk_write_root_dir
        jc .failure

        inc word [file_operation_count]
        popa
        clc
        ret

.failure:
        popa
        stc
        ret

.filename dw 0


; -------------------------------------------------
; Remove FAT12 read-only attribute

os_unprotect_file:
        pusha

        call int_filename_convert
        jc .failure

        mov [.filename], ax

        call disk_read_root_dir
        jc .failure

        mov ax, [.filename]
        mov di, disk_buffer
        call disk_get_root_entry
        jc .failure

        and byte [es:di+11], 0FEh

        call disk_write_root_dir
        jc .failure

        inc word [file_operation_count]
        popa
        clc
        ret

.failure:
        popa
        stc
        ret

.filename dw 0



; ==================================================================
; INTERNAL OS ROUTINES -- Not accessible to user programs

; ----------------------------------------------------------------------------
; intern_filename_convert -- Change 'TEST.BIN' into 'TEST    BIN',
; 'TEST.1' into 'TEST    1  ' or 'TEST' into 'TEST       '. (as per DOS 8.3)
; extension is optional, but must be at least 1 char if dot
; IN: AX = filename string
; OUT: AX = location of converted string (0000 and carry set if invalid)

intern_filename_convert:

; --------------------------------------------------------------------------
; int_filename_convert
; Validate and convert a filename into FAT 8.3 format.
;
; IN:  AX = pointer to zero-terminated filename
; OUT: AX = pointer to converted filename (11 chars + terminator)
;      Carry clear on success
;      AX = 0 and carry set on failure
;
; Supports letters, digits, underscore, hyphen and dot.
; Maximum: 8 characters for name, 3 for extension.


int_filename_convert:
        push es
        pusha

        push ds
        pop es

        call os_string_uppercase
        mov si, ax

        call os_string_length
        cmp ax, 12
        jg .failure

        cmp ax, 0
        jle .failure

        mov dx, ax

        mov al, ' '
        mov di, .dest_string
        push di
        mov cx, 11
        rep stosb
        mov al, 0
        stosb
        pop di

        xor cx, cx

.copy_loop:
        lodsb
        cmp al, '.'
        je .extension_found
        stosb
        inc cx
        cmp cx, dx
        jl .copy_loop
        jmp short .done

.extension_found:
        cmp cx, 0
        je .failure

        cmp cx, 8
        jg .failure

.do_extension:
        mov di, .dest_string+8

        lodsb
        cmp al, 0
        je .failure
        stosb

        lodsb
        cmp al, 0
        je .done
        stosb

        lodsb
        cmp al, 0
        je .done
        stosb

.done:
        popa
        pop es
        mov ax, .dest_string
        clc
        ret

.failure:
        popa
        pop es
        xor ax, ax
        stc
        ret

.dest_string: times 12 db 0




; --------------------------------------------------------------------------
; disk_get_root_entry -- Search RAM copy of root dir for file entry
; IN: AX = filename; OUT: DI = location in disk_buffer of root dir entry,
; or carry set if file not found

disk_get_root_entry:
	pusha

	mov word [.filename], ax

	mov cx, 224			; Search all (224) entries
	mov ax, 0			; Searching at offset 0

.to_next_root_entry:
	xchg cx, dx			; We use CX in the inner loop...

	mov word si, [.filename]	; Start searching for filename
	mov cx, 11
	rep cmpsb
	je .found_file			; Pointer DI will be at offset 11, if file found

	add ax, 32			; Bump searched entries by 1 (32 bytes/entry)

	mov di, disk_buffer		; Point to next root dir entry
	add di, ax

	xchg dx, cx			; Get the original CX back
	loop .to_next_root_entry

	popa

	stc				; Set carry if entry not found
	ret


.found_file:
	sub di, 11			; Move back to start of this root dir entry

	mov word [.tmp], di		; Restore all registers except for DI

	popa

	mov word di, [.tmp]

	clc
	ret


	.filename	dw 0
	.tmp		dw 0


; --------------------------------------------------------------------------
; disk_read_fat -- Read FAT entry from floppy into disk_buffer
; IN: Nothing; OUT: carry set if failure

disk_read_fat:
	pusha

	mov ax, 1			; FAT starts at logical sector 1 (after boot sector)
	call disk_convert_l2hts

	mov si, disk_buffer		; Set ES:BX to point to 8K OS buffer
	mov bx, 2000h
	mov es, bx
	mov bx, si

	mov ah, 2			; Params for int 13h: read floppy sectors
	mov al, 9			; And read 9 of them for first FAT

	pusha				; Prepare to enter loop


.read_fat_loop:
	popa
	pusha

	stc				; A few BIOSes do not set properly on error
	int 13h				; Read sectors

	jnc .fat_done
	call disk_reset_floppy		; Reset controller and try again
	jnc .read_fat_loop		; Floppy reset OK?

	popa
	jmp .read_failure		; Fatal double error

.fat_done:
	popa				; Restore registers from main loop

	popa				; And restore registers from start of system call
	clc
	ret

.read_failure:
	popa
	stc				; Set carry flag (for failure)
	ret


; --------------------------------------------------------------------------
; disk_write_fat -- Save FAT contents from disk_buffer in RAM to disk
; IN: FAT in disk_buffer; OUT: carry set if failure

disk_write_fat:
	pusha

	mov ax, 1			; FAT starts at logical sector 1 (after boot sector)
	call disk_convert_l2hts

	mov si, disk_buffer		; Set ES:BX to point to 8K OS buffer
	mov bx, ds
	mov es, bx
	mov bx, si

	mov ah, 3			; Params for int 13h: write floppy sectors
	mov al, 9			; And write 9 of them for first FAT

	stc				; A few BIOSes do not set properly on error
	int 13h				; Write sectors

	jc .write_failure		; Fatal double error

	popa				; And restore from start of system call
	clc
	ret

.write_failure:
	popa
	stc				; Set carry flag (for failure)
	ret


; --------------------------------------------------------------------------
; disk_read_root_dir -- Get the root directory contents
; IN: Nothing; OUT: root directory contents in disk_buffer, carry set if error

disk_read_root_dir:
	pusha

	mov ax, 19			; Root dir starts at logical sector 19
	call disk_convert_l2hts

	mov si, disk_buffer		; Set ES:BX to point to OS buffer
	mov bx, ds
	mov es, bx
	mov bx, si

	mov ah, 2			; Params for int 13h: read floppy sectors
	mov al, 14			; And read 14 of them (from 19 onwards)

	pusha				; Prepare to enter loop


.read_root_dir_loop:
	popa
	pusha

	stc				; A few BIOSes do not set properly on error
	int 13h				; Read sectors

	jnc .root_dir_finished
	call disk_reset_floppy		; Reset controller and try again
	jnc .read_root_dir_loop		; Floppy reset OK?

	popa
	jmp .read_failure		; Fatal double error


.root_dir_finished:
	popa				; Restore registers from main loop

	popa				; And restore from start of this system call
	clc				; Clear carry (for success)
	ret

.read_failure:
	popa
	stc				; Set carry flag (for failure)
	ret


; --------------------------------------------------------------------------
; disk_write_root_dir -- Write root directory contents from disk_buffer to disk
; IN: root dir copy in disk_buffer; OUT: carry set if error

disk_write_root_dir:
	pusha

	mov ax, 19			; Root dir starts at logical sector 19
	call disk_convert_l2hts

	mov si, disk_buffer		; Set ES:BX to point to OS buffer
	mov bx, ds
	mov es, bx
	mov bx, si

	mov ah, 3			; Params for int 13h: write floppy sectors
	mov al, 14			; And write 14 of them (from 19 onwards)

	stc				; A few BIOSes do not set properly on error
	int 13h				; Write sectors
	jc .write_failure

	popa				; And restore from start of this system call
	clc
	ret

.write_failure:
	popa
	stc				; Set carry flag (for failure)
	ret


; --------------------------------------------------------------------------
; Reset floppy disk

disk_reset_floppy:
	push ax
	push dx
	mov ax, 0
; ******************************************************************
	mov dl, [bootdev]
; ******************************************************************
	stc
	int 13h
	pop dx
	pop ax
	ret


; --------------------------------------------------------------------------
; disk_convert_l2hts -- Calculate head, track and sector for int 13h
; IN: logical sector in AX; OUT: correct registers for int 13h

disk_convert_l2hts:
	push bx
	push ax

	mov bx, ax			; Save logical sector

	mov dx, 0			; First the sector
	div word [SecsPerTrack]		; Sectors per track
	add dl, 01h			; Physical sectors start at 1
	mov cl, dl			; Sectors belong in CL for int 13h
	mov ax, bx

	mov dx, 0			; Now calculate the head
	div word [SecsPerTrack]		; Sectors per track
	mov dx, 0
	div word [Sides]		; Floppy sides
	mov dh, dl			; Head/side
	mov ch, al			; Track

	pop ax
	pop bx

; ******************************************************************
	mov dl, [bootdev]		; Set correct device
; ******************************************************************

	ret


; ---------------------------------------------------------------------------
; sys_disk_time -- get system time and convert to disk directory format
; IN:  nothing
; OUT: CX time in directory format

sys_disk_time:
	pusha

	clc				; For buggy BIOSes
	mov ah, 2			; Get time data from BIOS in BCD format
	int 1Ah				; CH = hour, CL = minutes, DH = seconds (BCD)
					; DL = daylight savings flag
	jnc .fmt

	clc
	mov ah, 2			; BIOS was updating (~1 in 500 chance), so try again
	int 1Ah
	jnc .fmt

	mov cx, 0x0830			; default time = 08:30:30 daylight time
	mov dx, 0x3001

  .fmt:
	mov al, ch
	call os_bcd_to_int		; ax = hours (max = 23, 5 bits)
	shl ax, 6
	mov si, ax			; SI = hours with room for minutes

	mov al, cl
	call os_bcd_to_int		; minutes (max = 59, 6 bits)
	or si, ax
	shl si, 5			; SI = hrs + mins with room for secs

	mov al, dh
	call os_bcd_to_int		; ax = seconds (max = 59)
	shr ax, 2			; 2 second granularity (5 bits)
	or si, ax			; SI = hrs + mins + secs/2

	mov [.tmp], si
	popa
	mov cx, [.tmp]
	ret

	.tmp dw 0


; ---------------------------------------------------------------------------
; sys_disk_date -- get system date and convert to disk directory format
; Note: if checking with Win, MS does something unusual with DST
; IN:  nothing
; OUT: DX date in directory format

sys_disk_date:
	pusha

	clc				; avoid possible bug
	mov ah, 4			; BIOS get date (most systems)
	int 1ah
	jnc .cont			; CH = century, CL = yy, DH = mm, DL = dd (all BCD)

	clc
	mov ah, 4			; BIOS was updating (~1 in 500 chance), so try again
	int 1Ah
	jnc .cont

  .set_default:
	mov cx, 0x2010			; default date 2010
	mov dx, 0x0601			; June 1

  .cont:
	mov al, ch
	call os_bcd_to_int
	mov bx, 100			; century * 100 (zero extended)
	mul bl
	mov bx, ax
	mov al, cl
	call os_bcd_to_int
	add bx, ax			; full year - base year =
	sub bx, 1980			; disk year (0 to 127)

	shl bx, 4
	mov al, dh
	call os_bcd_to_int
	or bx, ax			; add month (1 to 12)

	shl bx, 5
	mov al, dl
	call os_bcd_to_int
	or bx, ax			; add day (1 to varies (31 max))

	mov [.tmp], bx
	popa
	mov dx, [.tmp]
	ret

	.tmp dw 0


; ---------------------------------------------------------------------------
	Sides dw 2
	SecsPerTrack dw 18
; ******************************************************************
	bootdev db 0			; Boot device number
	file_operation_count dw 0
; ******************************************************************


; ==================================================================

