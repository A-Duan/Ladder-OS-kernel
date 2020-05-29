;This process is bootsect process, which is loading in the first sector(0, 0, 1)
;--------------------------------------------------------------------------------
core_begin_address equ 0x00040000	;内核起始地址
core_start_sector equ 0x00000001	;内核起始扇号
gdt_begin_address equ 0x00007e00	;gdt起始地址
boot_begin_address equ 0x00007c00	;主引导程序起始地址
stack_end_address equ 0x00006c00	;核心栈结束位置
process_start_address equ 0x0010000 ;程序和数据的起始区域
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
	mov dword [ebx + 0x04],0x00000000	;0号描述符
	
	;0~4GB地址
	mov dword [ebx + 0x08],0x0000ffff	
	mov dword [ebx + 0x0c],0x00cf9200	;粒度为4KB，存储器段描述符 
	
	;代码段
	mov dword [ebx + 0x10],0x7c0001ff	
	mov dword [ebx + 0x14],0x00409800	;粒度为1Byte，代码段描述符

	;堆栈段    
    mov dword [ebx + 0x18],0x7c00fffe    
    mov dword [ebx + 0x1c],0x00cf9600		;粒度为4KB, 
         
    ;显示缓冲区描述符   
    mov dword [ebx + 0x20],0x80007fff    
    mov dword [ebx + 0x24],0x0040920b    ;粒度为1Byte
	
	;初始化描述符表寄存器GDTR
    mov word [cs:gdt + boot_begin_address],39      ;描述符表的界限

	lgdt [cs:gdt + boot_begin_address]				;加载GDTR
	
	in al,0x92
	or al,0000_0010B
	out 0x92,al							;打开A20
	
	cli
	
	mov eax,cr0							;设置cr0的PE位
	or eax,1
	mov cr0,eax
	
	jmp dword 0x0010:protect			;清空流水线并串行化处理器
	
	[bits 32]
;进入保护模式
protect:
	mov eax,0x0008					;加载0~4GB数据段选择子
	mov ds,eax
	
	mov eax,0x0018					;加载栈段选择子
	mov ss,eax
	xor esp,esp
		
    ;加载内核
	mov edi,core_begin_address
	mov eax,core_start_sector
	mov ebx,edi
	call read_hard_disk				;读取起始部分
	
	;判断程序的大小
	mov eax,[edi]					
	xor edx,edx
	mov ecx,512
	div ecx
	
	or edx,edx
	jnz .left						;未除尽
	dec eax							;除尽

.left:
	or eax,eax
	jz setup						;如果内核大小不到一个扇区，就直接转到setup执行
	
	;读取剩余的扇区
	mov ecx,eax
	mov eax,core_start_sector
	inc eax

.keep_reading:
	call read_hard_disk
	inc eax
	loop .keep_reading
	
	
;安装内核的段描述符	
setup:
	mov esi,[boot_begin_address + gdt + 0x02]
	
	;建立公用例程段描述符
	mov eax,[edi + 0x04]
	mov ebx,[edi + 0x08]
	sub ebx,eax
	dec ebx
	add eax,edi
	mov ecx,0x00409800
	call make_gdt_descriptor
	mov [esi + 0x28],eax
	mov [esi + 0x2c],edx
	
	;建立核心数据段描述符
	mov eax,[edi + 0x08]
	mov ebx,[edi + 0x0c]
	sub ebx,eax
	dec ebx
	add eax,edi
	mov ecx,0x00409200
	call make_gdt_descriptor
	mov [esi + 0x30],eax
	mov [esi + 0x34],edx
	
	;建立核心代码段描述符
    mov eax,[edi+0x0c]                 ;核心代码段起始汇编地址
    mov ebx,[edi+0x00]                 ;程序总长度
    sub ebx,eax
    dec ebx                            ;核心代码段界限
    add eax,edi                        ;核心代码段基地址
    mov ecx,0x00409800                 ;字节粒度的代码段描述符
    call make_gdt_descriptor
    mov [esi+0x38],eax
    mov [esi+0x3c],edx
	
	mov word [boot_begin_address + gdt],63
	
	lgdt [boot_begin_address + gdt]
	
	jmp far [edi + 0x10]
	
;----------------------------------------------------------------------------	
;读取硬盘
read_hard_disk:	
	
	push eax
	push ecx
	push edx
	
	push eax
	
	;使用LBA28的方式来访问磁盘
	;设置要读取扇区的数量
	mov dx,0x1f2	
	mov al,1
	out dx,al
	
	
	;设置起始扇区号
	inc dx
	pop eax
	out dx,al		;LBA地址7~0
	
	inc dx
	mov cl,8
	shr eax,cl
	out dx,al		;LBA地址15~8
	
	inc dx
	shr eax,cl		
	out dx,al 		;LBA地址23~16
	
	inc dx
	shr eax,cl
	or al,0xe0
	out dx,al		;LBA模式，主硬盘，地址27~24
	
	;向端口0x1f7写入0x20,请求硬盘读
	inc dx
	mov al,0x20
	out dx,al
	
.check:
	in al,dx
	and al,0x88		;保留AL中的第七位和第三位
	cmp al,0x08
	jnz .check		;如果AL的第七位是0则退出等待
	
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
;构造描述符
make_gdt_descriptor:	


	mov edx,eax
    shl eax,16                     
    or ax,bx                        ;描述符前32位(EAX)构造完毕
      
    and edx,0xffff0000              ;清除基地址中无关的位
    rol edx,8
    bswap edx                       ;装配基址的31~24和23~16  (80486+)
      
    xor bx,bx
    or edx,ebx                      ;装配段界限的高4位
      
    or edx,ecx                      ;装配属性 
      
    ret
	

;---------------------------------------------------------------------------------------
gdt	dw 0
	dd 0x00007e00
				
;---------------------------------------------------------------------------------------                             
    times 510-($-$$) db 0
					 db 0x55,0xaa