
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
base_alive:			.long 0x0	# Array of 3 bytes, plus a padding byte
mp1_score:			.long 0x0	# Player's current score


# Data private to this  file

base_pic:     	    .string "/^^^\\"	# Picture of a live base
dead_base_pic: 	    .string "xxxxx"	# Picture of a dead base
crosshairs_x:		.long 0x0	# X-position of the crosshairs
crosshairs_y:		.long 0x0	# Y-position of the crosshairs
XHAIR: 				.long 88	#Character for crosshair - 'X'
row_offset:         .long 160   #Row multiple for writing to screen (80 bytes per row * 2 bytes per character)
column_offset:      .long 2     #Column multiple for writing to screen (2 bytes per character) MIGHT NEED TO FLIP THESE TWO
mp1_status:			.long 0x0   #Status variable with information of the score and base alive/dead

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
#clobbers eax
.globl mp1_ioctl
mp1_ioctl:
		#move cmd argument into register
		movl 8(%esp), %ebx #cmd
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
		ret

#Is this supposed to be here?
jump_table:
.long mp1_ioctl_startgame, mp1_ioctl_addmissile, mp1_ioctl_movexhairs, mp1_ioctl_getstatus, mp1_ioctl_endgame



# ----------------- Functions private to this file -------------------

#using both ecx and cl (FIX THAT)
update_missiles:
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi
		#Traverse the missile linked list
		movl mp1_missile_list, %ebx
traverse_list:
		cmpl $0, %ebx #check if null
		je end_missiles
		#Clear missile 
		pushl %eax #Caller save
		pushl %ebx #push function parameter, pointer to missile
		call calculate_missile_offset 
		addl $4, %esp
		movb $32, %cl #move (space) into cl 
		call mp1_poke #offset in eax and char in cl
		popl %eax
		movl EXPLODED(%ebx), %esi 
		cmpl $0, %esi  #Check if missile is exploding
		jne missile_exploding
		#update x and y
		pushl %eax
		pushl %ecx
		pushl %edx
		pushl %ebx #push function parameter, pointer to missile
		call update_missile_position
		addl $4, %esp #remove parameter from stack
		popl %edx
		popl %ecx
		popl %eax
		#Check if the missile went off screen
		movl X(%ebx), %esi
		shrl $16, %esi
		cmpl $0, %esi
		jl remove_missile
		cmpl $79, %esi
		jg remove_missile
		movl Y(%ebx), %esi
		shrl $16, %esi
		cmpl $0, %esi
		jl remove_missile
		cmpl $24, %esi
		jg remove_missile
		movl DEST_X(%ebx), %edi
		movl X(%ebx), %esi
		shrl $16, %esi
		cmpl %esi, %edi #has the missile reached its destination?
		jne not_reached
		movl DEST_Y(%ebx), %edi
		movl Y(%ebx), %esi
		shrl $16, %esi
		cmpl %esi, %edi
		jne not_reached
		movl $0, VX(%ebx)	#make this missile stop moving
		movl $0, VY(%ebx)
		jmp missile_exploding #it has reached its destination,so explode
not_reached:
		#put missile symbol in cl
		movb C(%ebx), %cl
		jmp redraw_missiles 
missile_exploding:
		#call missile_explode
		#Caller saves
		pushl %eax 
		pushl %ecx
		pushl %edx 
		pushl %ebx #contains pointer to missile that's exploding, function parameter
		call missile_explode
		addl $4, %esp #remove the argument 
		movl %eax, %edi #put the missile_explode return val into edi
		popl %edx
		popl %ecx
		popl %eax
		cmpl $0, %edi
		jne chain_explosion	 #update other missiles and cities
decrement_exploded:
		decl EXPLODED(%ebx) #decrement explode value
		cmpl $0, EXPLODED(%ebx) #if 0, remove missile if not, jmp to drawing an exploding missile
		je remove_missile
		#put exploding character into cl
		movb $64, %cl  #PUTTING 64 '@' but figure out how to put explosion here
		jmp redraw_missiles
chain_explosion:
		#Update the cities and other missiles here
		jmp decrement_exploded
remove_missile:
		movl NEXT(%ebx), %ecx 	#move the pointer to the next missile to ecx
		pushl %eax 
		pushl %ecx
		pushl %ebx			#push argument, pointer to missile to remove
		call mp1_missile_remove
		addl $4, %esp
		popl %ecx
		popl %eax
		movl %ecx, %ebx     #put the next missile to be checked back into ebx
		jmp traverse_list
redraw_missiles:
		#put the offset in memory into eax, char already in cl
		pushl %eax #Save eax because calculate_mission_position stores return val in eax
		pushl %ebx	#push function parameter, missile pointer
		call calculate_missile_offset #offset in eax now
		addl $4, %esp #remove function parameter from stack
		pushl %edx #mp1_poke clobbers edx so save it
		call mp1_poke
		popl %edx
		popl %eax #recover eax
		movl NEXT(%ebx), %ebx #curr= curr->next
		jmp traverse_list
end_missiles:
		popl %edi
		popl %esi
		popl %ebx
		leave
		ret

#clobbers ecx (cl)
redraw_cities: #make sure rows and columns offsets are right
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi
		movl $3840, %ebx #bottom most row has offset 3840 bytes
		movl $36, %esi #first character in column 18 (18*2 bytes offset)
		xorl %edx, %edx
		movl base_alive, %edi
		andl $0x00000001, %edi #bitmask for first city byte
		cmpl $0, %edi
		je first_base_dead
		#draw city 1 alive and then city 1 dead
first_base_alive:		
		movl %ebx, %eax
		addl %esi, %eax  
		movb base_pic(,%edx,1), %cl #move character into cl (MIGHT NEED TO SOMEHOW CHANGE THIS)
		pushl %edx
		call mp1_poke
		popl %edx
		addl $2, %esi #move to next offset location for column, bottom row so doesn't change
		incl %edx
		cmpl $5, %edx
		jl first_base_alive #if count<5, keep drawing, else go on to second base
		jmp second_base
first_base_dead:
		movl %ebx, %eax
		addl %esi, %eax  
		movb dead_base_pic(,%edx,1), %cl #move character into cl (MIGHT NEED TO SOMEHOW CHANGE THIS)
		pushl %edx
		call mp1_poke
		popl %edx
		addl $2, %esi #move to next offset location for column, bottom row so doesn't change
		incl %edx
		cmpl $5, %edx
		jl first_base_dead #if count<5, keep drawing, else go on to second base
second_base:
		movl $3840, %ebx
		movl $76, %esi #first character in column 38 (38*2 bytes offset)
		xorl %edx, %edx
		movl base_alive, %edi
		andl $0x00000100, %edi #bitmask for second city byte
		cmpl $0, %edi
		je second_base_dead
		#draw city 2 alive and then city 2 dead
second_base_alive:
		movl %ebx, %eax
		addl %esi, %eax
		movb base_pic(,%edx,1), %cl
		pushl %edx
		call mp1_poke
		popl %edx
		addl $2, %esi
		incl %edx
		cmpl $5, %edx
		jl second_base_alive
		jmp third_base
second_base_dead:
		movl %ebx, %eax
		addl %esi, %eax  
		movb dead_base_pic(,%edx,1), %cl #move character into cl (MIGHT NEED TO SOMEHOW CHANGE THIS)
		pushl %edx
		call mp1_poke
		popl %edx
		addl $2, %esi #move to next offset location for column, bottom row so doesn't change
		incl %edx
		cmpl $5, %edx
		jl second_base_dead #if count<5, keep drawing, else go on to third base
third_base:
		movl $3840, %ebx
		movl $116, %esi #first character in column 58 (58*2 bytes offset)
		xorl %edx, %edx
		movl base_alive, %edi
		andl $0x00010000, %edi #bitmask for third city byte
		cmpl $0, %edi
		je third_base_dead
		#draw city 3 alive and then city 3 dead
third_base_alive:
		movl %ebx, %eax
		addl %esi, %eax
		movb base_pic(,%edx,1), %cl
		pushl %edx 
		call mp1_poke
		popl %edx
		addl $2, %esi
		incl %edx
		cmpl $5, %edx
		jl third_base_alive #if count<5 keep drawing, otherwise wrap up and return
		jmp city_draw_return
third_base_dead:
		movl %ebx, %eax
		addl %esi, %eax  
		movb dead_base_pic(,%edx,1), %cl 
		pushl %edx
		call mp1_poke
		popl %edx
		addl $2, %esi #move to next offset location for column, bottom row so doesn't change
		incl %edx
		cmpl $5, %edx
		jl third_base_dead #if count<5, keep drawing,else wrap up and return
city_draw_return:
		popl %edi
		popl %esi
		popl %ebx
		leave
		ret


#clobbers ecx
redraw_xhairs:
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi
		pushl %edx #mp1_poke clobbers edx
		movl crosshairs_y, %ebx
		imull $160, %ebx, %edi #row offset in edi
		movl crosshairs_x, %ebx
		imull $2, %ebx, %esi #column offset in esi
		addl %edi, %esi 
		movl %esi, %eax #move video offset into eax for mp1_poke 
		movb XHAIR, %cl #move crosshair character into cl
		#Do we need caller convention here?
		call mp1_poke
		popl %edx
		popl %edi
		popl %esi
		popl %ebx
		leave
		ret

#clobbers ecx (cl) and eax
mp1_missile_remove:
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi
		movl 8(%ebp), %esi #Move the pointer to the missile to be removed into esi
		movl mp1_missile_list, %edi #Move the head missile into edi
		cmpl %edi, %esi 
		je remove_head_list
find_missile:
		movl %edi, %ebx #store prev in ebx
		movl NEXT(%edi), %edi #move to next missile
		cmpl %edi, %esi  #is this the missile to be removed?
		je found_missile
		jmp find_missile
found_missile:
		movl NEXT(%edi), %eax
		movl %eax, NEXT(%ebx) #point the prev->next to curr->next
		jmp remove_from_screen
remove_head_list:
		movl NEXT(%edi), %ebx
		movl %ebx, mp1_missile_list #Does this work? Store the new head as the NEXT missile
remove_from_screen:
		#erase the missile by putting " " char at it's location
		pushl %edi #push the parameter, the missile pointer
		call calculate_missile_offset
		addl $4, %esp
		movb $32, %cl #move (space) into cl
		pushl %edx #mp1_poke clobbers edx
		call mp1_poke
		popl %edx
free_missile: #Calling convention needed?
		#SHOULD THIS BE ESI?
		pushl %edi #push function parameter, a pointer to the memory to be freed
		call mp1_free
		popl %edi
missile_remove_return:		
		popl %edi
		popl %esi
		popl %ebx
		leave 
		ret

mp1_ioctl_startgame: 
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

#Clobbers eax
mp1_ioctl_addmissile:
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi
		movl 8(%ebp), %ebx #move user space pointer to missile into ebx
		movl $33, %edi  #each missile is 33 bytes
		pushl %edi #push parameter for malloc call
		call mp1_malloc
		popl %edi
		cmpl $0, %eax #should this be M[eax] NULL? CHECK THIS?
		je malloc_failed
		pushl %eax #save the pointer in memory to the allocated memory, we might need to free it
		pushl %edi #parameter 3, number of bytes to copy
		pushl %ebx #parameter 2, pointer to "from" in user space
		pushl %eax #parameter 1, pointer to "to" in kernel space
		call mp1_copy_from_user
		addl $12, %esp #pop parameters from stack
		cmpl $0, %eax #check if copy was successful 
		jne copy_from_user_failed
		popl %eax #pop the pointer we allocated in stack back into eax
		#Fix the new pointer as the head of the list
		movl mp1_missile_list, %esi
		movl %esi, NEXT(%eax)
		movl %eax, mp1_missile_list
		xorl %eax, %eax # zero out eax for return val
		jmp addmissile_return

copy_from_user_failed:
		popl %eax #pop the pointer to allocated memory back into eax
		pushl %eax #re add the pointer to the stack as a parameter for free
		call mp1_free
		popl %eax
malloc_failed:
		movl $-1, %eax
addmissile_return:
		popl %edi
		popl %esi
		popl %ebx
		leave
		ret


#Clobbers edx and eax
mp1_ioctl_movexhairs:
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi
		xorl %edx, %edx
		xorl %esi, %esi
		#First clear the current crosshair
		movb $32, %cl #move (space) ASCII into cl for printing to screen
		pushl %edx #mp1_poke clobbers edx
		movl crosshairs_y, %edx
		imull $160, %edx, %edi #row offset in edi
		movl crosshairs_x, %edx
		imull $2, %edx, %esi #column offset in esi
		addl %edi, %esi 
		movl %esi, %eax #move video offset into eax for mp1_poke 
		#Do we need caller convention here?
		call mp1_poke
		popl %edx
		#Now update the new crosshair position
		movl 8(%ebp), %ebx #move function parameter (x,y change) into ebx
		movl %ebx, %eax
		shll $16, %eax
		sarl $16, %eax
		movl %eax, %esi #move low 16 bits into esi, holds x change.
		sarl $16, %ebx #shift the high 16 bits into the low 16 bits in ebx
		movl %ebx, %edx #shift the low 16 bits into edx, holds the y change
		addl crosshairs_x, %esi #get new crosshair_x val and store in esi
		cmpl $0, %esi 
		jl x_below_0
		cmpl $79, %esi
		jg x_above_79
		movl %esi, crosshairs_x(,1) # save the new VALID value into x 
		jmp update_xhair_y
x_below_0:
		movl $0, crosshairs_x(,1) #reset crosshairs x to 0
		jmp update_xhair_y
x_above_79:
		movl $79, crosshairs_x(,1) #reset crosshairs x to 79
update_xhair_y:
		addl crosshairs_y, %edx
		cmpl $0, %edx
		jl y_below_0
		cmpl $24, %edx
		jg y_above_24
		movl %edx, crosshairs_y(,1) #save the new VALIUD value into y
		jmp draw_new_xhairs
y_below_0:
		movl $0, crosshairs_y(,1) #reset crosshairs y to 0
		jmp draw_new_xhairs
y_above_24:
		movl $24, crosshairs_y(,1) #reset crosshairs y to 24
draw_new_xhairs:
		call redraw_xhairs
		popl %edi
		popl %esi
		popl %ebx
		xorl %eax, %eax #return 0
		leave
		ret

#Clobbers edx and eax
#Do we need to malloc memory for pointer in user space?
mp1_ioctl_getstatus:
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi
		movl 8(%ebp), %ebx #Move user-level integer pointer to ebx
		#Copy digits into a number
		xorl %edx, %edx
		movw mp1_score, %dx #Move score into lower 16 bits (DOES THIS WORK?)
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
		movl $0x00010000, %esi
		andl %edi, %esi
		cmpl $0, %esi
		je copy_to_user #skip bit 18, which is already cleared because base3 is dead
		orl $0x00040000, %edx #set bit 18 to 1 and keep the rest unchanged
copy_to_user:
		#Caller convention?
		movl %edx, mp1_status(,1) #store calculated long in a location
		pushl $4   #push last argument (n), 4 bytes must be copied
		pushl $mp1_status #pass pointer to "from" variable IS THIS RIGHT?
		push  %ebx  #pass pointer to "to" variable
		call mp1_copy_to_user
		addl $12, %esp
		cmpl $0, %eax #if eax!= 0, the copy failed so we should return -1
		jne copy_failed
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
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi
free_missile_list:
		movl mp1_missile_list, %ebx
		cmpl $0, %ebx #compare pointer
		je endgame_return
		movl NEXT(%ebx), %edi
		movl %edi, mp1_missile_list #Does this work? Store the new head as the NEXT missile
		pushl %ebx
		call mp1_free
		popl %ebx
		jmp free_missile_list
endgame_return:
		popl %edi
		popl %esi
		popl %ebx
		xorl %eax, %eax #return 0
		leave
		ret


update_missile_position:
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi
		movl 8(%ebp), %ebx #move the missile pointer into ebx
		#Update both the x and y coordinate, VX/VY shouldn't change afaik
		movl X(%ebx), %esi
		addl VX(%ebx), %esi
		movl %esi, X(%ebx)
		movl Y(%ebx), %esi
		addl VY(%ebx), %esi
		movl %esi, Y(%ebx)
		popl %edi
		popl %esi
		popl %ebx
		leave
		ret

#clobbers eax
calculate_missile_offset:
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi
		movl 8(%ebp), %ebx #move the missile pointer into ebx
		movl X(%ebx), %esi
		shrl $16, %esi #shift the high 16 bits to the bottom 16 bits DO WE WANT SHRL or SARL
		movl Y(%ebx), %edi 
		shrl $16, %edi 
		imull $160, %edi, %edi
		imull $2, %esi, %esi #can we overwrite, does this work?
		addl %edi, %esi
		movl %esi, %eax
		popl %edi
		popl %esi
		popl %ebx
		leave
		ret