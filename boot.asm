;This process is bootsect process, which is loading in the first sector(0, 0, 1)
;--------------------------------------------------------------------------------
core_begin_address equ 0x00040000	;�ں���ʼ��ַ
core_start_sector equ 0x00000001	;�ں���ʼ�Ⱥ�
gdt_begin_address equ 0x00007e00	;gdt��ʼ��ַ
boot_begin_address equ 0x00007c00	;������������ʼ��ַ
stack_end_address equ 0x00006c00	;����ջ����λ��
process_start_address equ 0x0010000 ;��������ݵ���ʼ����
;--------------------------------------------------------------------------------
;start:
	mov ax,cs
	mov ss,ax
	mov sp,boot_begin_address


	
	mov eax,[cs:gdt + boot_begin_address + 0x02]	;32-bit
	xor edx,edx
	mov ebx,16
	div ebx
	
	mov ds,eax
	mov ebx,edx	
	
	mov dword [ebx],0x00000000
	mov dword [ebx + 0x04],0x00000000	;0��������
	
	;0~4GB��ַ
	mov dword [ebx + 0x08],0x0000ffff	
	mov dword [ebx + 0x0c],0x00cf9200	;����Ϊ4KB���洢���������� 
	
	;�����
	mov dword [ebx + 0x10],0x7c0001ff	
	mov dword [ebx + 0x14],0x00409800	;����Ϊ1Byte�������������

	;��ջ��    
    mov dword [ebx + 0x18],0x7c00fffe    
    mov dword [ebx + 0x1c],0x00cf9600		;����Ϊ4KB, 
         
    ;��ʾ������������   
    mov dword [ebx + 0x20],0x80007fff    
    mov dword [ebx + 0x24],0x0040920b    ;����Ϊ1Byte
	
	;��ʼ����������Ĵ���GDTR
    mov word [cs:gdt + boot_begin_address],39      ;��������Ľ���

	lgdt [cs:gdt + boot_begin_address]				;����GDTR
	
	in al,0x92
	or al,0000_0010B
	out 0x92,al							;��A20
	
	cli
	
	mov eax,cr0							;����cr0��PEλ
	or eax,1
	mov cr0,eax
	
	jmp dword 0x0010:protect			;�����ˮ�߲����л�������
	
	[bits 32]
;���뱣��ģʽ
protect:
	mov eax,0x0008					;����0~4GB���ݶ�ѡ����
	mov ds,eax
	
	mov eax,0x0018					;����ջ��ѡ����
	mov ss,eax
	xor esp,esp
		
    ;�����ں�
	mov edi,core_begin_address
	mov eax,core_start_sector
	mov ebx,edi
	call read_hard_disk				;��ȡ��ʼ����
	
	;�жϳ���Ĵ�С
	mov eax,[edi]					
	xor edx,edx
	mov ecx,512
	div ecx
	
	or edx,edx
	jnz .left						;δ����
	dec eax							;����

.left:
	or eax,eax
	jz setup						;����ں˴�С����һ����������ֱ��ת��setupִ��
	
	;��ȡʣ�������
	mov ecx,eax
	mov eax,core_start_sector
	inc eax

.keep_reading:
	call read_hard_disk
	inc eax
	loop .keep_reading
	
	
;��װ�ں˵Ķ�������	
setup:
	mov esi,[boot_begin_address + gdt + 0x02]
	
	;�����������̶�������
	mov eax,[edi + 0x04]
	mov ebx,[edi + 0x08]
	sub ebx,eax
	dec ebx
	add eax,edi
	mov ecx,0x00409800
	call make_gdt_descriptor
	mov [esi + 0x28],eax
	mov [esi + 0x2c],edx
	
	;�����������ݶ�������
	mov eax,[edi + 0x08]
	mov ebx,[edi + 0x0c]
	sub ebx,eax
	dec ebx
	add eax,edi
	mov ecx,0x00409200
	call make_gdt_descriptor
	mov [esi + 0x30],eax
	mov [esi + 0x34],edx
	
	;�������Ĵ����������
    mov eax,[edi+0x0c]                 ;���Ĵ������ʼ����ַ
    mov ebx,[edi+0x00]                 ;�����ܳ���
    sub ebx,eax
    dec ebx                            ;���Ĵ���ν���
    add eax,edi                        ;���Ĵ���λ���ַ
    mov ecx,0x00409800                 ;�ֽ����ȵĴ����������
    call make_gdt_descriptor
    mov [esi+0x38],eax
    mov [esi+0x3c],edx
	
	mov word [boot_begin_address + gdt],63
	
	lgdt [boot_begin_address + gdt]
	
	jmp far [edi + 0x10]
	
;----------------------------------------------------------------------------	
;��ȡӲ��
read_hard_disk:	
	
	push eax
	push ecx
	push edx
	
	push eax
	
	;ʹ��LBA28�ķ�ʽ�����ʴ���
	;����Ҫ��ȡ����������
	mov dx,0x1f2	
	mov al,1
	out dx,al
	
	
	;������ʼ������
	inc dx
	pop eax
	out dx,al		;LBA��ַ7~0
	
	inc dx
	mov cl,8
	shr eax,cl
	out dx,al		;LBA��ַ15~8
	
	inc dx
	shr eax,cl		
	out dx,al 		;LBA��ַ23~16
	
	inc dx
	shr eax,cl
	or al,0xe0
	out dx,al		;LBAģʽ����Ӳ�̣���ַ27~24
	
	;��˿�0x1f7д��0x20,����Ӳ�̶�
	inc dx
	mov al,0x20
	out dx,al
	
.check:
	in al,dx
	and al,0x88		;����AL�еĵ���λ�͵���λ
	cmp al,0x08
	jnz .check		;���AL�ĵ���λ��0���˳��ȴ�
	
	mov ecx,256
	mov dx,0x1f0
	
	
.read:
	in ax,dx
	mov [ebx],ax
	add ebx,2
	loop .read
	
	pop edx
	pop ecx
	pop eax
	
	ret
	
;---------------------------------------------------------------------------------------
;����������
make_gdt_descriptor:	


	mov edx,eax
    shl eax,16                     
    or ax,bx                        ;������ǰ32λ(EAX)�������
      
    and edx,0xffff0000              ;�������ַ���޹ص�λ
    rol edx,8
    bswap edx                       ;װ���ַ��31~24��23~16  (80486+)
      
    xor bx,bx
    or edx,ebx                      ;װ��ν��޵ĸ�4λ
      
    or edx,ecx                      ;װ������ 
      
    ret
	

;---------------------------------------------------------------------------------------
gdt	dw 0
	dd 0x00007e00
				
;---------------------------------------------------------------------------------------                             
    times 510-($-$$) db 0
					 db 0x55,0xaa