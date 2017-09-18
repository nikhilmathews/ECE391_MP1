
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
mp1_status:			.long 0x0   #Status variable with information of the score in lower 16 bits and base alive/dead in bits 16,17,18

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
		cmpl $0, %ebx #make sure cmd is not invalid (must be between 0 and 4)
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

jump_table:
.long mp1_ioctl_startgame, mp1_ioctl_addmissile, mp1_ioctl_movexhairs, mp1_ioctl_getstatus, mp1_ioctl_endgame



# ----------------- Functions private to this file -------------------

# update_missiles
# Performs two tasks:
#	(1) traverses the missile list and updates it as follows:
#         If exploding, don't move and check if anything else is exploding and notify user
#		  If not exploding, check if moved of screen, and delete if so
#		  If on screen and not exploding, keep moving
#	(2) Keep redrawing the missiles, as long as within the bounds of the screen
# Inputs   : none
# Outputs  : none
# Registers: Clobbers ecx

update_missiles:
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi
		#Traverse the missile linked list
		movl mp1_missile_list, %ebx
traverse_list:
		cmpl $0, %ebx #check if missile is null
		je end_missiles
		#Clear missile 
		pushl %eax #Caller save
		pushl %ebx #push function parameter, pointer to missile
		call calculate_missile_offset 
		addl $4, %esp
		movb $32, %cl #move (space) into cl 
		call mp1_poke #offset in eax from calculate_missile_offset returnval and char in cl
		popl %eax
		movl EXPLODED(%ebx), %esi 
		cmpl $0, %esi  #Check if missile is exploding
		jne missile_exploding
		#not exploding, update x and y
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
		cmpl $0, %esi #left side of screen
		jl remove_missile
		cmpl $79, %esi #right side of screen
		jg remove_missile
		movl Y(%ebx), %esi
		shrl $16, %esi
		cmpl $0, %esi #top of screen
		jl remove_missile
		cmpl $24, %esi #bottom of screen 
		jg remove_missile
		#check if missile reached destination
		movl DEST_X(%ebx), %edi
		movl X(%ebx), %esi
		shrl $16, %esi
		cmpl %esi, %edi  
		jne not_reached
		movl DEST_Y(%ebx), %edi
		movl Y(%ebx), %esi
		shrl $16, %esi
		cmpl %esi, %edi
		jne not_reached
		movl $0, VX(%ebx)	#make this missile stop moving because it has reached destination
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
		cmpl $0, %edi #check if explosion is causing other missiles or bases to explode
		jne chain_explosion	 
decrement_exploded:
		decl EXPLODED(%ebx) #decrement explode value
		cmpl $0, EXPLODED(%ebx) #if 0, remove missile if not, jmp to drawing an exploding missile
		je remove_missile
		movb $EXPLOSION, %cl  #Put EXPLOSION character into cl
		jmp redraw_missiles
chain_explosion:
		#Notify the user that there's a chain explosion and then move on to decrementing EXPLODED value
		pushl %eax
		pushl %ecx
		pushl %edx
		call mp1_notify_user
		popl %edx
		popl %ecx
		popl %eax
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
		jmp traverse_list	#Continue moving through list
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
		movl NEXT(%ebx), %ebx #Move to the next missile and keep traversing list 
		jmp traverse_list
end_missiles:
		popl %edi
		popl %esi
		popl %ebx
		leave
		ret

# redraw_cities
#Redraws all three cities based on whether they are dead or alive and makes sure they are always visible
# Inputs   : none
# Outputs  : none
# Registers: Standard C calling convention
redraw_cities: 
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi
		movl $3840, %ebx #bottom most row has offset 3840 bytes
		movl $36, %esi  #first character in column 18 (18*2 bytes offset)
		xorl %edx, %edx
		movl base_alive, %edi
		andl $0x00000001, %edi #bitmask for first city byte
		cmpl $0, %edi
		je first_base_dead #draw city 1 dead if 0
first_base_alive:		
		movl %ebx, %eax
		addl %esi, %eax  
		movb base_pic(,%edx,1), %cl #move character draw into cl (edx shifts the character to draw by one each loop)
		pushl %edx
		call mp1_poke
		popl %edx
		addl $2, %esi #move to next offset location (2 bytes) for column, no change in x because still bottom row
		incl %edx
		cmpl $5, %edx #bases have 5 characters
		jl first_base_alive #if count<5, keep drawing, else go on to second base
		jmp second_base
first_base_dead:
		movl %ebx, %eax
		addl %esi, %eax  
		movb dead_base_pic(,%edx,1), %cl #move character into cl
		pushl %edx
		call mp1_poke
		popl %edx
		addl $2, %esi 
		incl %edx
		cmpl $5, %edx #bases have 5 characters
		jl first_base_dead #if count<5, keep drawing, else go on to second base
second_base:
		movl $3840, %ebx #bottom most row has offset 3840 bytes
		movl $76, %esi #first character in column 38 (38*2 bytes offset)
		xorl %edx, %edx
		movl base_alive, %edi
		andl $0x00000100, %edi #bitmask for second city byte
		cmpl $0, %edi
		je second_base_dead #draw city 2 dead if 0
second_base_alive:
		movl %ebx, %eax
		addl %esi, %eax
		movb base_pic(,%edx,1), %cl
		pushl %edx
		call mp1_poke
		popl %edx
		addl $2, %esi
		incl %edx
		cmpl $5, %edx #bases have 5 characters
		jl second_base_alive #if count<5, keep drawing, else go on to third base
		jmp third_base 
second_base_dead:
		movl %ebx, %eax
		addl %esi, %eax  
		movb dead_base_pic(,%edx,1), %cl 
		pushl %edx
		call mp1_poke
		popl %edx
		addl $2, %esi 
		incl %edx
		cmpl $5, %edx
		jl second_base_dead #if count<5, keep drawing, else go on to third base
third_base:
		movl $3840, %ebx #bottom most row has offset 3840 bytes
		movl $116, %esi #first character in column 58 (58*2 bytes offset)
		xorl %edx, %edx
		movl base_alive, %edi
		andl $0x00010000, %edi #bitmask for third city byte
		cmpl $0, %edi
		je third_base_dead #draw city 3 dead if 0
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
		addl $2, %esi
		incl %edx
		cmpl $5, %edx
		jl third_base_dead #if count<5, keep drawing,else wrap up and return
city_draw_return:
		popl %edi
		popl %esi
		popl %ebx
		leave
		ret


# redraw_xhairs
# Redraws the crosshairs so they are always visible
# Inputs   : none
# Outputs  : none
# Registers: Clobbers ecx
redraw_xhairs:
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi
		pushl %edx #mp1_poke clobbers edx so save it
		movl crosshairs_y, %ebx
		imull $160, %ebx, %edi #row offset in edi (80 * 2 * y) (video_mem y offset is 2 bytes per character and 80 characters per row)
		movl crosshairs_x, %ebx
		imull $2, %ebx, %esi #column offset in esi (2* x) (video_mem x offset is 2 bytes per character)
		addl %edi, %esi 
		movl %esi, %eax #move video offset into eax for mp1_poke 
		movb $88, %cl #move crosshair character into cl
		call mp1_poke
		popl %edx 	#pop back the value of edx saved earlier
		popl %edi
		popl %esi
		popl %ebx
		leave
		ret

# mp1_missile_remove
# Performs two tasks:
#	(1) Remove the input missile from the linked list
#	(2) If required update the head of the linked list
#   (3) Remove the missile from the screen
# 	(4) Free the memory associated with the missile struct
# Inputs   : missile pointer
# Outputs  : none
# Registers: Clobbers ecx and eax
mp1_missile_remove:
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi
		movl 8(%ebp), %esi #Move the pointer to the missile to be removed into esi
		movl mp1_missile_list, %edi #Move the head missile into edi
		cmpl %edi, %esi 
		je remove_head_list #if head, remove it and update the head
find_missile:
		movl %edi, %ebx #store prev missile in ebx
		movl NEXT(%edi), %edi #move to next missile
		cmpl %edi, %esi  #is this the missile to be removed?
		je found_missile
		jmp find_missile  #if not, keep traversing list
found_missile:
		movl NEXT(%edi), %eax
		movl %eax, NEXT(%ebx) #point the prev->next to current->next, thereby removing the missile from the list
		jmp remove_from_screen
remove_head_list:
		movl NEXT(%edi), %ebx
		movl %ebx, mp1_missile_list #Store the new head as the NEXT missile
remove_from_screen:
		#erase the missile by putting (space) char at it's location
		pushl %edi #push the parameter, the missile pointer
		call calculate_missile_offset
		addl $4, %esp
		movb $32, %cl #move (space) into cl, eax already holds the video offset 
		pushl %edx #mp1_poke clobbers edx
		call mp1_poke
		popl %edx
free_missile: 
		pushl %edi #push function parameter, a pointer to the memory to be freed
		call mp1_free
		popl %edi
missile_remove_return:		
		popl %edi
		popl %esi
		popl %ebx
		leave 
		ret

# mp1_ioctl_startgame
# Initializes the crosshairs to (40,12) and sets all bases alive
# Inputs   : none
# Outputs  : none
# Registers: Standard C caller convention
mp1_ioctl_startgame: 
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi
		#Set all the bases as alive
		movl $0x00010101, base_alive(,1) #set all three bases alive
		#Set the crosshairs to (40,12)
		movl $40, crosshairs_x(,1)
		movl $12, crosshairs_y(,1)
		popl %edi
		popl %esi
		popl %ebx
		leave
		ret

# mp1_ioctl_addmissile
# Adds a missile to kernel space buffer. 
# Inputs   : A pointer to the missile in user space
# Outputs  : returns -1 for failure and 0 for success
# Registers: Clobbers ecx
mp1_ioctl_addmissile:
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi
		movl 8(%ebp), %ebx #move user space pointer to missile into ebx
		movl $33, %edi  #each missile is 33 bytes
		pushl %edi #push parameter (33 bytes)for malloc call
		call mp1_malloc
		popl %edi
		cmpl $0, %eax # Check if malloc failed (returns null pointer)
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
		movl $-1, %eax #return -1 to indicate failure
addmissile_return:
		popl %edi
		popl %esi
		popl %ebx
		leave
		ret


# mp1_ioctl_movexhairs
# Moves the crosshairs by:
# 			(1) Updating the X and Y location of the crosshair
#			(2) Removing the old crosshair from the screen
#			(3) Making sure they are within the bounds of the screen
#			(3) redrawing the crosshair
# Inputs   : a 32 bit unsigned integer; high 16 bits is a signed y change and low 16 bits is a signed x change
# Outputs  : returns 0 for success
# Registers: Clobbers edx, eax and ecx
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
		imull $160, %edx, %edi #row offset in edi (80 * 2 * y) (video_mem y offset is 2 bytes per character and 80 characters per row)
		movl crosshairs_x, %edx
		imull $2, %edx, %esi # column offset in esi (2 * x)(video_mem x offset is 2 bytes per character)
		addl %edi, %esi 
		movl %esi, %eax #move video offset into eax for mp1_poke 
		call mp1_poke
		popl %edx 
		#Now update the new crosshair position
		movl 8(%ebp), %ebx #move function parameter (x,y change) into ebx
		movl %ebx, %eax
		shll $16, %eax #remove the high 16 bits and then move the low bits back 
		sarl $16, %eax
		movl %eax, %esi #holds the x change
		sarl $16, %ebx #remove the low 16 bits
		movl %ebx, %edx #shift into edx, holds the y change
		addl crosshairs_x, %esi #get new crosshair_x val and store in esi
		cmpl $0, %esi #left side of screen
		jl x_below_0
		cmpl $79, %esi #right side of screen
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
		cmpl $0, %edx #top of screen
		jl y_below_0
		cmpl $24, %edx #bottom of screen
		jg y_above_24
		movl %edx, crosshairs_y(,1) #save the new VALID value into y
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

# mp1_ioctl_getstatus
# Updates the user status by copying a long from kernel space to user space
# Puts the score in lower 16 bits, and then base status into bits 16,17,18 (1 for alive and 0 for dead)
# Inputs   : a pointer to a 32 bit integer in user space
# Outputs  : returns 0 for success and -1 for failure
# Registers: Clobbers edx, eax
mp1_ioctl_getstatus:
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi
		movl 8(%ebp), %ebx #Move user-level integer pointer to ebx
		#Copy digits into a number
		xorl %edx, %edx
		movw mp1_score, %dx #Move score into lower 16 bits
		movl base_alive, %edi
		movl $0x00000001, %esi #bitmask for base 1
		andl %edi, %esi
		cmpl $0, %esi
		je base_2_status #skip bit 16, which is already cleared because base1 is dead
		orl $0x00010000, %edx #set bit 16 to 1 and keep the rest unchanged
base_2_status:
		movl base_alive, %edi
		movl $0x00000100, %esi #bitmask for base 2
		andl %edi, %esi
		cmpl $0, %esi
		je base_3_status #skip bit 17, which is already cleared because base2 is dead
		orl $0x00020000, %edx #set bit 17 to 1 and keep the rest unchanged
base_3_status:
		movl base_alive, %edi
		movl $0x00010000, %esi #bitmask for base 3
		andl %edi, %esi
		cmpl $0, %esi
		je copy_to_user #skip bit 18, which is already cleared because base3 is dead
		orl $0x00040000, %edx #set bit 18 to 1 and keep the rest unchanged
copy_to_user:
		#Caller convention?
		movl %edx, mp1_status(,1) #store calculated long in a location
		pushl $4   #push last argument (n), 4 bytes must be copied
		pushl $mp1_status #pass pointer to "from" variable (label address)
		push  %ebx  #pass pointer to "to" variable
		call mp1_copy_to_user
		addl $12, %esp
		cmpl $0, %eax #if eax!= 0, the copy failed
		jne copy_failed
		xorl %eax, %eax #otherwise return 0 for success
		jmp getstatus_return
copy_failed:
		movl $-1, %eax #so we should return -1 for failure
getstatus_return:		
		popl %edi
		popl %esi
		popl %ebx
		leave
		ret


# mp1_ioctl_endgame
# Clear the missile list and deallocate the memory of each missile
# Inputs   : none
# Outputs  : 0 for success
# Registers: Standard C caller convention
mp1_ioctl_endgame:
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi
free_missile_list:
		movl mp1_missile_list, %ebx
		cmpl $0, %ebx # check if list is cleared
		je endgame_return
		movl NEXT(%ebx), %edi
		movl %edi, mp1_missile_list #Store the next missile to be checked as the new head of list
		pushl %ebx
		call mp1_free #free the memory of the current missile
		popl %ebx
		jmp free_missile_list
endgame_return:
		popl %edi
		popl %esi
		popl %ebx
		xorl %eax, %eax #return 0 for success
		leave
		ret

# update_missile_position
# Updates the missile position (x,y) based on VX and VY values 
# Inputs   : a pointer to the missile to be updated
# Outputs  : none
# Registers: Standard C caller convention
update_missile_position:
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi
		movl 8(%ebp), %ebx #move the missile pointer into ebx
		#Update both the x and y coordinate, VX/VY shouldn't change
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

# calculate_missile_offset
# Calculate video memory offset for a given missile
# Inputs   : a pointer to the missile to calculate offset for
# Outputs  : video memory offset in eax
# Registers: clobber eax
calculate_missile_offset:
		pushl %ebp
		movl %esp, %ebp
		pushl %ebx
		pushl %esi
		pushl %edi
		movl 8(%ebp), %ebx #move the missile pointer into ebx
		movl X(%ebx), %esi
		shrl $16, %esi #shift the high 16 bits to the bottom 16 bits
		movl Y(%ebx), %edi 
		shrl $16, %edi 
		imull $160, %edi, %edi #row offset in edi (80 * 2 * y) (video_mem y offset is 2 bytes per character and 80 characters per row)
		imull $2, %esi, %esi # column offset in esi (2*x) (video_mem x offset is 2 bytes per character)
		addl %edi, %esi
		movl %esi, %eax
		popl %edi
		popl %esi
		popl %ebx
		leave
		ret
