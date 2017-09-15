
# mp1.S - missile-command version
# Good luck, and have fun!

.data
	
    # Constants for accessing the fields of a struct missile, 
    # struct missile is defined in rtc.h and mp1.h

	NEXT 	  = 0
	X	  = 4
	Y	  = 8
	VX	  = 12
	VY	  = 16
	DEST_X	  = 20
	DEST_Y	  = 24
	EXPLODED  = 28
	C	  = 32

    # Character to draw for an explosion - '@'

	EXPLOSION = 64


# Data shared between this file and rtc.c helper functions

# This '.globl' directive makes these symbols visible externally
.globl mp1_missile_list, base_alive, mp1_score

mp1_missile_list:	.long 0x0	# Head of list pointer
base_alive:		.long 0x0	# Array of 3 bytes, plus a padding byte
mp1_score:		.long 0x0	# Player's current score


# Data private to this  file

base_pic:     	    .string "/^^^\\"	# Picture of a live base
dead_base_pic: 	    .string "xxxxx"	# Picture of a dead base
crosshairs_x:		.long 0x0	# X-position of the crosshairs
crosshairs_y:		.long 0x0	# Y-position of the crosshairs
XHAIR: 				.long 88	#Character for crosshair - 'X'
row_offset:         .long 160   #Row multiple for writing to screen (80 bytes per row * 2 bytes per character)
column_offset:      .long 2     #Column multiple for writing to screen (2 bytes per character)
mp1_status:			.long 0x0   #Status variable with information of the score and base alive/dead

jump_table:
.long mp1_ioctl_startgame, mp1_ioctl_addmissile, mp1_ioctl_movexhairs, mp1_ioctl_getstatus, mp1_ioctl_endgame

.text

# void mp1_poke(void);
# You can use this function to write to video memory.
#
# Interface: Register-based arguments (not C-style)
#    Inputs: %cl  - The byte you wish to write
#            %eax - Offset from the start of video memory that you wish
#                   to write to
#   Outputs: Text-mode video screen is written to at location %eax with
#            the byte in %cl
# Registers: Clobbers EDX

mp1_poke:
		movl    vmem_base_addr(,1),%edx
		movb    %cl,(%edx,%eax,1)
		ret

#   ----------------- Exported functions ---------------------

# void mp1_rtc_tasklet(unsigned long garbage);
# Performs three tasks:
#	(1) updates the list of missiles (implement this in update_missiles,
#           below, and call it from here).
#	(2) Redraw the bases - they may have been overwritten with missiles
#	(3) Redraw the crosshairs - it may have been overwritten with missiles
# Inputs   : none
# Outputs  : none
# Registers: Standard C calling convention

.globl mp1_rtc_tasklet
mp1_rtc_tasklet:
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi
		#Callee saves?
		call update_missiles
		call redraw_cities
		call redraw_xhairs	
		popl %edi
		popl %esi
		popl %ebx
		leave
		ret


# int mp1_ioctl(unsigned long arg, unsigned int cmd)
# The dispatch function for the MP1 ioctls - should use the cmd argument
# and a jumptable to execute one of the specific ioctls implemented below.
# Inputs   : unsigned long arg - parameter to the mp1_ioctl_....
#          : unsigned int cmd  - specifies which mp1_ioctl_... function 
#          :                     to execute
# Outputs  : Returns an integer - depends on which ioctl() function is called
# Registers: Standard C calling convention

.globl mp1_ioctl
mp1_ioctl:
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi
		#move arguments into registers
		movl 8(%ebp), %esi #arg
		movl 12(%ebp), %ebx #cmd
		cmpl $0, %ebx
		jl invalid_ioctl
		cmpl $4, %ebx
		jg invalid_ioctl
		jmp *jump_table(, %ebx,4)
		#return appropriate integer

		jmp ioctl_return

invalid_ioctl:
		movl $-1, %eax

ioctl_return:
		popl %edi
		popl %esi
		popl %ebx
		leave
		ret


# ----------------- Functions private to this file -------------------

update_missiles:
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi

		#Traverse the missile linked list
		movl mp1_missile_list, %ebx

traverse_list:
		cmpl $0, (%ebx) #Access M[mp1_missile_list] and check if it's null
		je end_missiles






end_missiles:
		popl %edi
		popl %esi
		popl %ebx
		leave
		ret

redraw_cities: #FIX BITMASKS (Nonzero for alive and zero for dead)
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi
		pushl %edx #mp1_poke clobbers edx
		movl $3840, %ebx #bottom most row has offset 3840 bytes
		movl $36, %esi #first character in column 18 (18*2 bytes offset)
		xorl %ecx, %ecx
		movl base_alive, %edi
		andl $0x00000001, %edi #bitmask for first city byte
		cmpl $0, %edi
		je first_base_dead
		#draw city 1 alive and then city 1 dead

first_base_alive:		
		movl %ebx, %eax
		addl %esi, %eax  
		movb base_pic(,%ecx,1), %cl #move character into cl (MIGHT NEED TO SOMEHOW CHANGE THIS)
		call mp1_poke
		addl $2, %esi #move to next offset location for column, bottom row so doesn't change
		incl %ecx
		cmpl $5, %ecx
		jl first_base_alive #if count<5, keep drawing, else go on to second base
		jmp second_base

first_base_dead:
		movl %ebx, %eax
		addl %esi, %eax  
		movb dead_base_pic(,%ecx,1), %cl #move character into cl (MIGHT NEED TO SOMEHOW CHANGE THIS)
		call mp1_poke
		addl $2, %esi #move to next offset location for column, bottom row so doesn't change
		incl %ecx
		cmpl $5, %ecx
		jl first_base_dead #if count<5, keep drawing, else go on to second base

second_base:
		movl $3840, %ebx
		movl $76, %esi #first character in column 38 (38*2 bytes offset)
		xorl %ecx, %ecx
		movl base_alive, %edi
		andl $0x00000100, %edi #bitmask for second city byte
		cmpl $0, %edi
		je second_base_dead
		#draw city 2 alive and then city 2 dead
second_base_alive:
		movl %ebx, %eax
		addl %esi, %eax
		movb base_pic(,%ecx,1), %cl
		call mp1_poke
		addl $2, %esi
		incl %ecx
		cmpl $5, %ecx
		jl second_base_alive
		jmp third_base

second_base_dead:
		movl %ebx, %eax
		addl %esi, %eax  
		movb dead_base_pic(,%ecx,1), %cl #move character into cl (MIGHT NEED TO SOMEHOW CHANGE THIS)
		call mp1_poke
		addl $2, %esi #move to next offset location for column, bottom row so doesn't change
		incl %ecx
		cmpl $5, %ecx
		jl second_base_dead #if count<5, keep drawing, else go on to third base

third_base:
		movl $3840, %ebx
		movl $116, %esi #first character in column 58 (58*2 bytes offset)
		xorl %ecx, %ecx
		movl base_alive, %edi
		andl $0x00010000, %edi #bitmask for third city byte
		cmpl $0, %edi
		je third_base_dead
		#draw city 3 alive and then city 3 dead
third_base_alive:
		movl %ebx, %eax
		addl %esi, %eax
		movb base_pic(,%ecx,1), %cl # (MIGHT NEED TO CHANGE THIS, want to move only 1 byte into cl so movl might be wrong)
		call mp1_poke
		addl $2, %esi
		incl %ecx
		cmpl $5, %ecx
		jl third_base_alive #if count<5 keep drawing, otherwise wrap up and return
		jmp city_draw_return
third_base_dead:
		movl %ebx, %eax
		addl %esi, %eax  
		movb dead_base_pic(,%ecx,1), %cl #move character into cl (MIGHT NEED TO SOMEHOW CHANGE THIS)
		call mp1_poke
		addl $2, %esi #move to next offset location for column, bottom row so doesn't change
		incl %ecx
		cmpl $5, %ecx
		jl third_base_dead #if count<5, keep drawing,else wrap up and return

city_draw_return:
		popl %edx
		popl %edi
		popl %esi
		popl %ebx
		leave
		ret



redraw_xhairs:
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi
		pushl %edx #mp1_poke clobbers edx
		movl row_offset, %ebx
		imull crosshairs_x, %ebx, %edi #row offset in edi
		movl column_offset, %ebx
		imull crosshairs_y, %ebx, %esi #column offset in esi
		addl %edi, %esi 
		movl %esi, %eax #move video offset into eax for mp1_poke 
		movl XHAIR, %cl #move crosshair character into cl
		#Do we need caller convention here?
		call mp1_poke
		popl %edx
		popl %edi
		popl %esi
		popl %ebx
		leave
		ret


mp1_missile_remove: 
		ret

mp1_ioctl_startgame: #FIX setting base_alive
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi
		#Set all the bases as alive
		movl $0x00010101, base_alive(,1) 
		#Set the crosshairs to (40,12)
		movl $40, crosshairs_x(,1)
		movl $12, crosshairs_y(,1)
		#Do we have to draw crosshairs? Should tasklet/redraw_xhairs figure that out?

		popl %edi
		popl %esi
		popl %ebx
		leave
		ret

mp1_ioctl_addmissile:
		ret

mp1_ioctl_movexhairs:
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi


		popl %edi
		popl %esi
		popl %ebx
		xorl %eax, %eax #return 0
		leave
		ret

mp1_ioctl_getstatus:
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi
		movl -8(%ebp), %ebx #Move user-level integer pointer to ebx
		#Copy digits into a number
		xorl %edx, %edx
		movw mp1_score, %dx #Move score into lower 16 bits

		movl base_alive, %edi
		movl $0x00000001, %esi
		andl %edi, %esi
		cmpl $0, %esi
		je base_2_status #skip bit 16, which is already cleared because base1 is dead
		orl $0x00010000, %edx #set bit 16 to 1 and keep the rest unchanged
base_2_status:
		movl base_alive, %edi
		movl $0x00000100, %esi
		andl %edi, %esi
		cmpl $0, %esi
		je base_3_status #skip bit 17, which is already cleared because base2 is dead
		orl $0x00020000, %edx #set bit 17 to 1 and keep the rest unchanged
base_3_status:
		movl base_alive, %edi
		movl $0x0100, %esi
		andl %edi, %esi
		cmpl $0, %esi
		je copy_to_user #skip bit 18, which is already cleared because base3 is dead
		orl $0x00040000, %edx #set bit 18 to 1 and keep the rest unchanged
copy_to_user:
		#Caller convention?
		#Do we have to copy_from_user or not?
		movl %edx, mp1_status(,1) #store calculated long in a location
		pushl $4   #push last argument (n), 4 bytes must be copied
		pushl $mp1_status #pass pointer to "from" variable
		push  %ebx  #pass pointer to "to" variable
		call mp1_copy_to_user
		addl $12, %esp
		cmpl $0, %eax #if eax> 0, the copy failed so we should return -1
		jg copy_failed
		xorl %eax, %eax
		jmp getstatus_return
copy_failed:
		movl $-1, %eax
getstatus_return:		
		popl %edi
		popl %esi
		popl %ebx
		leave
		ret

mp1_ioctl_endgame:
		ret
