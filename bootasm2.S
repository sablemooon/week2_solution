# When the PC starts, the processor is essentially emulating an 8086 processor, i.e. 
# a 16-bit processor.  So our initial boot loader code is 16-bit code that will 
# eventually switch the processor into 32-bit mode.

# This code is linked to assume a starting address of 0x7C00 which is where the BIOS
# will load a boot segment.

.code16                         # Assemble for 16-bit mode
.globl start

start:
    jmp     real_start

# Write to the console using BIOS.
# 
# Input: SI contains the address of the null-terminated string to be displayed

cons_write:
    movb    $0x0e, %ah           # 0x0e is the INT 10h BIOS call to output the value contained in AL to screen

cons_write_rpt:
    movb    (%si), %al          # Load the byte at the location contained in the SI register into AL   
    inc     %si                 # Add 1 to the value in SI
    cmp     $0, %al             # Compare the value in AL with 0
    jz      cons_write_done     # If it is zero, then we are done
    int     $0x10               # Output the character in AL to the screen
    jmp     cons_write_rpt      # and continue

cons_write_done:                # Something that is called will never return 
    ret                         # until a 'ret' instruction is encountered.  Labels do 
                                # not give a program any structure.  They just give a 
                                # memory location a name that we can use in our code. 

cons_write_crlf:
    movb    $0x0e, %ah          # Output CR
    movb    $0x0d, %al
    int     $0x10
    movb    $0x0a, %al          # Output LF
    int     $0x10
    ret

cons_writeline:
    call    cons_write
    call    cons_write_crlf
    ret    

wait_for_key_press:
    mov $0, %ah       # AH = 0 for BIOS keyboard services
    int $0x16         # Wait for a key press
    ret


read_sector:
    movw $disk_address_packet, %si  # Move address of the disk address packet into SI
    movw $1, 2(%si)                  # Set the number of blocks to read to be 1 (read one sector)
    movw $0xD000, 4(%si)             # Set the address to read into to be 0xD000
    movw $1, 8(%si)                  # Set the first block to read to be block 1
    movb $0x42, %ah                  # 0x42 is the int 13h BIOS function to read the disk using LBA addressing
    movb (boot_device), %dl          # Retrieve the ID of our boot device and put in DL
    int $0x13                         # Read the disk
    jc read_failed                    # The carry flag will be set if an error occurred

    movb    (0xD000), %al             # Check that what we loaded is not empty
    cmpb    $0, %al
    je      read_failed
    ret


read_failed:	                      # Display error messages
	movw 	$read_failed_msg, %si
    call    cons_writeline
	
	movw 	$cannot_continue, %si	
    call    cons_writeline
    

# Output the 16-bit value in BX to the screen as a 4 digit hex value	
#
# Input:  BX = Value to output	

HexChars:    .ascii "0123456789ABCDEF"

cons_write_hex:
    movw    $4, %cx             # Set the loop counter to 4 (number of hexadecimal digits)
    movb    $0x0E, %ah          # BIOS function to output a character

hexloop:
    rol     $4, %bx             # Rotate the bits in BX to the left by 4 positions
    movw    %bx, %si            # Move the rotated value to SI for masking
    and     $0x000F, %si        # Mask the lower 4 bits to get the hexadecimal digit
    movb    HexChars(%si), %al  # Get the corresponding hexadecimal character
    int     $0x10               # Output the character to the console
    loop    hexloop             # Repeat the loop until CX becomes 0
    ret                         # Return from the function

# Output the value in BX as an unsigned integer
#
# Input: BX = Value to output
	
cons_write_int:
    movw    $IntBuffer + 4, %si
    movw    %bx, %ax
	
getdigit:
	xor		%dx, %dx    #Sets dx to 0
	movw	$16, %cx
	div		%cx
	addb	$48, %dl
	movb	%dl, (%si)
	dec		%si
	cmp		$0, %ax
	jne		getdigit
	inc		%si
	call	cons_write
	ret

    IntBuffer:   .string "     "
	
four:
    movw    $zero, %si
    call    cons_write
    loop    four
    ret

disp_loop:
    pushw   %bx      
    pushw   %cx     
    pushw   %si
    movw    $space, %si
    call    cons_write
    popw    %si
  
    movw    (%si), %bx
    call    cons_write_hex
    addw    $0x0010, %si
    popw    %cx
    popw    %bx
    inc     %si
    loop    disp_loop

    call    cons_write_crlf
   
    ret

super_disp_loop:    # loop to print results from reading disk
    pushw    %cx    # put how many times sdl needs to loop on stack
    
    call    cons_write_hex # write the first section should be 0000
    
    movw    $8, %cx
    call    disp_loop
    popw     %cx
    addw    $0x0010, %bx
  
    loop    super_disp_loop
    ret

real_start:
    cli
    movb    %dl, (boot_device) # Boot device number is passed in DL from BIOS. Save it hear since DL might get trashed

    movw    $boot_message, %si  # Display our boot message
    call    cons_writeline
   
    movw    $booted_from_msg, %si
    call    cons_write

    movb    (boot_device), %dl
    cmp     $0x80, %dl
    jge     harddrive
    
    movw    $fd, %si
    jmp     finish

harddrive:
    movw    $hd, %si


finish:
    call    cons_writeline
    call    cons_write_crlf

    xorw    %ax, %ax                 # Set %ax to zero
    movw    %ax, %ds                 # -> Data Segment
    movw    %ax, %es                 # -> Extra Segment
    movw    %ax, %ss                 # -> Stack Segment
    movw    $0, %sp                  # Set the stack to the top of the segment

    # Call read_sector to read a sector
    call read_sector    

    # Print the contents of the sector in hexadecimal
    movw    $0xD000, %si  # Point %si to the beginning of the loaded sector data
    # movw    $0x0000, %si      
    call    cons_write_hex
    movw    (%si), %bx
    movw    $4, %cx
    call    hexloop
    call    cons_write_crlf
    call    cons_write_hex
    call    cons_write_crlf
    addw    $0x0010, %si
    movw    (%si), %bx
    
    call    cons_write_hex
    call    cons_write_crlf

    xor     %bx, %bx            # initiatlise bx to stop weird carry overs
    movw    $0xD000, %si
    movw    $16, %cx
    call    super_disp_loop     # will need to convert to disk reading once i work that out
    xor     %si, %si
    movw    press_key, %si
    call    cons_write
    call    wait_for_key_press # here as a place holder it will need a better place when close to fin
    jmp     finish

endless_loop:                   # Loop forever more
    jmp     endless_loop    

# Program data

boot_device:
    .byte   0

# Format of disk address packet
#
# Offset	Size	Description
#  0          1     size of packet (16 bytes)
#  1          1     always 0
#  2          2     number of sectors to transfer (max 127 on some BIOSes)
#  4          4     transfer buffer (first 2 bytes is 16-bit offset, next 2 bytes is 16 bit segment)
#  8          4     lower 32-bits of 48-bit starting LBA (starting from 0)
#  12         4     upper 16-bits of 48-bit starting LBA (will always be 0 for us)

disk_address_packet:
    .byte   0x10
    .byte   0
    .word   0
    .long   0
    .long   0
    .long   0

boot_message:     
    .string "Boot Loader Stage 2 loaded"             
booted_from_msg:
    .string "Booting from "
fd: .string "floppy disk"
hd: .string "hard drive"
space:  .string " "
zero:   .string "00"
read_failed_msg:
    .string "Unable to read stage 2 of the boot process"
cannot_continue:
    .string "Cannot continue boot process"
press_key:
    .string "Press a key to continue"