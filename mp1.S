
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

	SHIFT_BITS = 16
	COLUMN_OFFSET = 160
	ROW_OFFSET = 2
	CROSSHAIR_CHARACTER = 43
	CROSSHAIR_START_X = 12
	CROSSHAIR_START_Y = 40
	SPACE_CHARACTER = 32
	X_POSITION_MIN = 0
	Y_POSITION_MIN = 0
	X_POSITION_MAX = 79
	Y_POSITION_MAX = 24
	BASE_OFFSET = 3840

	FIRST_CITY_START = 18
	FIRST_CITY_END = 23
	SECOND_CITY_START = 38
	SECOND_CITY_END = 43
	THIRD_CITY_START = 58
	THIRD_CITY_END = 63


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
	pushl %ebp	#push base pointer and set stack pointer to the base
	movl %esp, %ebp 
	
	pushl %ebx #save callee registers
	pushl %eax	
	pushl %ecx	
	pushl %edx	
	pushl %esi
	pushl %edi
	call draw_missiles #calls draw_missiles
	popl %edi	
	popl %esi
	popl %edx
	popl %ecx
	popl %eax
	popl %ebx

	pushl %eax	#save callee registers
	pushl %ebx	
	pushl %ecx	
	pushl %edx
	pushl %edi
	pushl %esi	
	call draw_bases	#calls draw_bases
	popl %esi
	popl %edi
	popl %edx
	popl %ecx
	popl %ebx
	popl %eax	#pop callee saved registers
	
	pushl %eax	#save callee registers
	pushl %ebx	
	pushl %ecx	
	pushl %edx	
	pushl %esi
	pushl %edi	
	call draw_crosshairs	#calls draw_crosshairs
	popl %edi 
	popl %esi
	popl %edx
	popl %ecx
	popl %ebx
	popl %eax	#pop callee saved registers
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
	movl 8(%esp), %eax	#eax gets the argument value passed with stack pointer	
	cmpl $0, %eax	#see if the command is less than 0 or greater than 4
	jl skip
	cmpl $4, %eax	
	jg skip
	jmp *jump_table(,%eax,4) 
	jmp end
	skip:
	movl $-1, %eax	#return value of -1 if command is invalid.
	end:
	ret

jump_table:
	.long mp1_ioctl_startgame, mp1_ioctl_addmissile, mp1_ioctl_movexhairs, mp1_ioctl_getstatus, mp1_ioctl_endgame

# ----------------- Functions private to this file -------------------

# void draw_missiles() 
# This is the function that is called from mp1_rtc_tasklet. The function can follow
# either one or two flows. The first flow is it passing through the exploding check,
# where it will go through an updating position flow. The other flow that it will follow
# is the exploding flow, where the missiles will go through an explosion.
# Inputs   : none
# Outputs  : none
# Registers: Standard C calling convention
draw_missiles:
	pushl %ebp #initialize both the base and stack pointer
	movl %esp, %ebp

	movl mp1_missile_list, %ebx #make ebx point to the head of the missile list
	MISSILE_ITERATION:
		cmpl $0, %ebx #if the current point is null, then go to finished iteration
		je FINISHED_ITERATION 
		
		movl X(%ebx), %eax #load the x value into eax, shift it, and multiply the offset by the row * 2
		shrl $SHIFT_BITS, %eax
		imull $2, %eax

		movl Y(%ebx), %ecx #load the y value into ecx, shift it, and multiply the offset by the column * 160
		shrl $SHIFT_BITS, %ecx
		imull $COLUMN_OFFSET, %ecx

		addl %ecx, %eax #add the offset into eax so that it is passed into mp1_poke correctly

		movb $SPACE_CHARACTER, %cl #draw a space in  the place of the current missile's position, and also make sure to save edx
		pushl %edx
		call mp1_poke
		popl %edx
	
		cmpl $0, EXPLODED(%ebx) #check the exploded value, and if it is not zero, then go to explode missile flow
		jne EXPLODE_MISSILE
		
	CHECK_POSITION:
		movl VX(%ebx), %eax #otherwise, I check the updated position's X's boundaries with eax
		addl X(%ebx), %eax
		shrl $SHIFT_BITS, %eax
		cmpl $X_POSITION_MAX, %eax
		jg remove_missile
		cmpl $0, %eax
		jl remove_missile

		movl VY(%ebx), %ecx #I check the updated position's Y's boundaries with ecx
		addl Y(%ebx), %ecx
		shrl $SHIFT_BITS, %ecx
		cmpl $Y_POSITION_MAX, %ecx
		jg remove_missile
		cmpl $0, %ecx
		jl remove_missile
		
	UPDATE_POSITION:
		movl VX(%ebx), %eax #if the checks go through, then I add the velocity values to x and y
		addl %eax, X(%ebx)	
		movl VY(%ebx), %ecx
		addl %ecx, Y(%ebx)

		movl X(%ebx), %eax #check if the update x coordinate is at its destination, and if it's not, then draw regular missile
		shrl $SHIFT_BITS, %eax
		movl DEST_X(%ebx), %ecx
		cmpl %eax, %ecx
		jne DRAW_MISSILE

		movl Y(%ebx), %eax #do the same thing with y
		shrl $SHIFT_BITS, %eax
		movl DEST_Y(%ebx), %ecx 
		cmpl %eax, %ecx
		je EXPLODE_MISSILE #by this check, both x and y are at their respective destinations, so explode the missile
	
	DRAW_MISSILE: 
		movl X(%ebx), %eax #load the x value into eax, shift it, and multiply the offset by the row * 2
		shrl $SHIFT_BITS, %eax
		imull $2, %eax

		movl Y(%ebx), %ecx #load the y value into ecx, shift it, and multiply the offset by the column * 160
		shrl $SHIFT_BITS, %ecx
		imull $COLUMN_OFFSET, %ecx

		addl %ecx, %eax #add the offset into eax so that it is passed into mp1_poke correctly

		pushl %edx #load the missile character into cl so that the right character is drawn
		movb C(%ebx), %cl
		call mp1_poke 
		popl %edx
		jmp CONTINUE_ITERATION

	EXPLODE_MISSILE:
		movl X(%ebx), %eax #load the x value into eax, shift it, and multiply the offset by the row * 2
		shrl $SHIFT_BITS, %eax
		imull $2, %eax

		movl Y(%ebx), %ecx #load the y value into ecx, shift it, and multiply the offset by the column * 160
		shrl $SHIFT_BITS, %ecx
		imull $COLUMN_OFFSET, %ecx

		addl %ecx, %eax #add the offset into eax so that it is passed into mp1_poke correctly

		movb $EXPLOSION, %cl  #load the explosion character into cl so that the right character is drawn
		pushl %edx
		call mp1_poke
		popl %edx

		pushl %ebx
		call missile_explode #call missile_explode to check if any other missiles need to be exploded 
		popl %ebx

		cmpl $0, %eax #if the resulting value from the method is zero, then iterate through the explosion
		je EXPLOSION_ITERATION 
		call mp1_notify_user #otherwise notify the user

	EXPLOSION_ITERATION:
		decl EXPLODED(%ebx) #if the explosion value is greater than zero, continue the list iteration
		cmpl $0, EXPLODED(%ebx)
		je CONTINUE_EXPLOSION #otherwise keep the explosion going by removing the characters
		jmp CONTINUE_ITERATION
		
	CONTINUE_EXPLOSION:
		movl X(%ebx), %eax #load the x value into eax, shift it, and multiply the offset by the row * 2
		shrl $SHIFT_BITS, %eax
		imull $2, %eax

		movl Y(%ebx), %ecx #load the y value into ecx, shift it, and multiply the offset by the column * 160
		shrl $SHIFT_BITS, %ecx
		imull $COLUMN_OFFSET, %ecx

		addl %ecx, %eax #add the offset into eax so that it is passed into mp1_poke correctly
		movb $SPACE_CHARACTER, %cl #load the space character into cl so that the right character is drawn
		
		pushl %edx
		call mp1_poke
		popl %edx
		jmp remove_missile #call remove missile to remove the current missile pointed at
		
	CONTINUE_ITERATION: #go to the next missile in the linked list
		movl NEXT(%ebx), %ebx
		jmp MISSILE_ITERATION

	FINISHED_ITERATION:  
		leave
		ret

# void remove_missile() 
# This is the remove missile function that adjusts the missile list when a missile explodes or reaches its destination
# Inputs   : none (but mp1_missile_list is used)
# Outputs  : none (but mp1_missile_list is modified)
# Registers: Standard C calling convention
remove_missile:	
	cmpl mp1_missile_list, %ebx #compare the pointer with the list, and if they're equal, then I am removing the head
	je REMOVE_HEAD
	movl mp1_missile_list, %ecx #otherwise load the head into another register
	
	ITERATE_THROUGH_LIST:	
		cmpl (%ecx), %ebx #iterate through the list until I hit ebx, or the current pointer we want to remove
		je REMOVE_BODY
		movl NEXT(%ecx), %ecx
		jmp ITERATE_THROUGH_LIST
		
	REMOVE_BODY:
		movl (%ebx), %eax #adjust the next pointers so that they skip the current struct in the list
		movl %eax, (%ecx)
		pushl %ecx
		pushl %ebx
		call mp1_free #call mp1_free
		popl %ebx
		popl %ecx
		movl (%ecx), %ebx #make my current pointer point to the new struct
		jmp MISSILE_ITERATION 


	REMOVE_HEAD:
		movl (%ebx), %ecx #adjust the next pointers so that they skip the current struct in the list
		movl %ecx, mp1_missile_list
		pushl %ebx
		call mp1_free 
		popl %ebx
		movl mp1_missile_list, %ebx #make my current pointer point to the new struct
		jmp MISSILE_ITERATION

# void draw_bases() 
# This is the function that is called from mp1_rtc_tasklet. The function checks each of the three bases
# and decides whether or not to draw an alive or dead base
# Inputs   : none
# Outputs  : none
# Registers: Standard C calling convention
draw_bases:
	pushl %ebp
	movl %esp, %ebp
	movl $base_alive, %eax #eax will point to the base_alive array


	DRAW_FIRST_BASE:
	ALIVE_FIRST_BASE:
		cmpb $0, (%eax) #compare eax with 0, and if it is 0, then go to dead first base and draw that
		je DEAD_FIRST_BASE
		movl $base_pic, %ebx #load the base alive pic into ebx
		movl $FIRST_CITY_START, %edi #start of edi as 18 for my first base
		pushl %eax #push the registers that will be changed in the draw for loop
		pushl %edi 
		drawLoopA:
			movb (%ebx), %cl #move the character to be drawn into cl
			movl %edi, %eax
			imull $ROW_OFFSET, %eax
			addl $BASE_OFFSET, %eax #add the offset of current col * 2 + 3840
			pushl %edx
			call mp1_poke
			popl %edx
			incl %edi #increment both edi and ebx to get the next character and next iteration
			incl %ebx
			cmpl $FIRST_CITY_END, %edi #compare with the end to see if it has finished
			je endDrawLoopA
			jmp drawLoopA
		endDrawLoopA:
			popl %edi #pop both registers for end of foor loop
		popl %eax
		jmp ALIVE_SECOND_BASE
	DEAD_FIRST_BASE:
		movl $dead_base_pic, %ebx #same logic as drawing an alive first base above
		movl $FIRST_CITY_START, %edi
		pushl %eax
		pushl %edi
		drawLoopD:
			movb (%ebx), %cl
			movl %edi, %eax
			imull $ROW_OFFSET, %eax
			addl $BASE_OFFSET, %eax
			pushl %edx
			call mp1_poke
			popl %edx
			incl %edi
			incl %ebx
			cmpl $FIRST_CITY_END, %edi
			je endDrawLoopD
			jmp drawLoopD
		endDrawLoopD:
			popl %edi
		popl %eax


	DRAW_SECOND_BASE:
	ALIVE_SECOND_BASE: #FOLLOWS THE SAME LOGIC AS THE FLOW FOR THE FIRST base
		cmpb $0, 1(%eax)
		je DEAD_SECOND_BASE
		movl $base_pic, %ebx
		movl $SECOND_CITY_START, %edi
		pushl %eax
		pushl %edi
		drawLoop2A:
			movb (%ebx), %cl
			movl %edi, %eax
			imull $ROW_OFFSET, %eax
			addl $BASE_OFFSET, %eax
			pushl %edx
			call mp1_poke
			popl %edx
			incl %edi
			incl %ebx
			cmpl $SECOND_CITY_END, %edi
			je endDrawLoop2A
			jmp drawLoop2A
		endDrawLoop2A:
			popl %edi
		popl %eax
		jmp ALIVE_THIRD_BASE
	DEAD_SECOND_BASE:
		movl $dead_base_pic, %ebx
		movl $SECOND_CITY_START, %edi
		pushl %eax
		pushl %edi
		drawLoop2D:
			movb (%ebx), %cl
			movl %edi, %eax
			imull $ROW_OFFSET, %eax
			addl $BASE_OFFSET, %eax
			pushl %edx
			call mp1_poke
			popl %edx
			incl %edi
			incl %ebx
			cmpl $SECOND_CITY_END, %edi
			je endDrawLoop2D
			jmp drawLoop2D
		endDrawLoop2D:
			popl %edi
		popl %eax


	DRAW_THIRD_BASE:
	ALIVE_THIRD_BASE: #FOLLOWS THE SAME LOGIC AS THE FLOW FOR THE FIRST base
		cmpb $0, 2(%eax)
		je DEAD_THIRD_BASE
		movl $base_pic, %ebx
		movl $THIRD_CITY_START, %edi
		pushl %eax
		pushl %edi
		drawLoop3A:
			movb (%ebx), %cl
			movl %edi, %eax
			imull $ROW_OFFSET, %eax
			addl $BASE_OFFSET, %eax
			pushl %edx
			call mp1_poke
			popl %edx
			incl %edi
			incl %ebx
			cmpl $THIRD_CITY_END, %edi
			je endDrawLoop3A
			jmp drawLoop3A
		endDrawLoop3A:
			popl %edi
		popl %eax
		jmp DONE_DRAWING
	DEAD_THIRD_BASE:
		movl $dead_base_pic, %ebx
		movl $THIRD_CITY_START, %edi
		pushl %eax
		pushl %edi
		drawLoop3D:
			movb (%ebx), %cl
			movl %edi, %eax
			imull $ROW_OFFSET, %eax
			addl $BASE_OFFSET, %eax
			pushl %edx
			call mp1_poke
			popl %edx
			incl %edi
			incl %ebx
			cmpl $THIRD_CITY_END, %edi
			je endDrawLoop3D
			jmp drawLoop3D
		endDrawLoop3D:
			popl %edi
		popl %eax
	DONE_DRAWING: 
		leave
		ret

# void draw_crosshairs() 
# This is the function that is called from mp1_rtc_tasklet. The function checks the crosshairs that are drawn,
# and constantly redraws the crosshair. 
# Inputs   : none
# Outputs  : none
# Registers: Standard C calling convention
draw_crosshairs:
	pushl %ebp	
	movl %esp, %ebp	
	movl crosshairs_x, %eax #load the x coordinate of crosshairs into eax
	movl crosshairs_y, %edx #load the y coordinate of crosshairs into edx

	imull $COLUMN_OFFSET, %edx #load the y value into edx, shift it, and multiply the offset by the column * 160
	imull $ROW_OFFSET, %eax #load the x value into eax, shift it, and multiply the offset by the row * 2
	addl %edx, %eax
	movb $CROSSHAIR_CHARACTER, %cl	#draws a crosshair
	pushl %edx
	call mp1_poke	
	popl %edx

	leave
	ret

# int mp1_ioctl_startgame(unsigned long ignore) 
# This is the function that initializes the crosshair position, missile list, bases, and score 
# Inputs   : ignore (meaningless and should be ignored)
# Outputs  : none
# Registers: Standard C calling convention
mp1_ioctl_startgame:
	movl $CROSSHAIR_START_X, crosshairs_y #initialize the crosshair coordinate to (12, 40) middle of the screen
	movl $CROSSHAIR_START_Y, crosshairs_x	
	movl $0x0, mp1_missile_list #initialize the missile list, bases, and score
	movl $0x00010101, base_alive
	movl $0x0, mp1_score 
	ret

# int  mp1 ioctl addmissile (struct missile* user missile) 
# This is the function that dynamically adds the missile, while also allocating memory
# Inputs   : pointer to a struct missile in user space
# Outputs  : -1 if the add fails, otherwise 0
# Registers: Standard C calling convention
mp1_ioctl_addmissile: 
	pushl %ebp
	movl %esp, %ebp
	pushl %ebx
	movl 8(%ebp), %esi #adjust the stack pointer so that I access the right missile into esi
	
	pushl $33	#size of missile struct
	call mp1_malloc	#malloc(33)
	addl $4, %esp #adjust the stack pointer for the next missile
	movl %eax, %ebx	#put the current pointer to the list (ebx) to eax from mp1_mallocs' value
	cmpl $0, %ebx #if it is zero, then this is a failed copy
	je FAILED_COPY
	
	pushl $33	#size of the missile
	pushl %esi	#*from
	pushl %ebx	#*to
	call mp1_copy_from_user #call copy from user
	addl $12, %esp	#adjust for the three pops in mp1_copy_from_user
	cmpl $0, %eax	#check again if it is null, and go to failed copy if it is
	jne FAILED_COPY	
	
	movl mp1_missile_list ,%eax #update the missile list as such with pointers
	movl %eax, NEXT(%ebx)	
	movl %ebx, mp1_missile_list
	
	movl $0, %eax #return 0 to signify correct insertion
	jmp FINISHED

	FAILED_COPY:	
		pushl %eax	#push callee registers and call mp1_free
		pushl %esi	
		pushl %ecx	
		pushl %edx	
		pushl %edi
		pushl %ebx
		call mp1_free	
		popl %ebx
		popl %edi
		popl %edx
		popl %ecx
		popl %esi
		popl %eax
		movl $-1, %eax #return -1 and adjust the stack pointer
		addl $4, %esp

	FINISHED: #return from function
		popl %ebx
		leave
		ret

# int mp1 ioctl movexhairs (unsigned long xhair delta packed)
# This is the function moves the crosshairs
# Inputs   : a 32-bit integer containing two signed 16-bit integers packed into
# its low and high words
# Outputs  : always 0
# Registers: Standard C calling convention
mp1_ioctl_movexhairs:

	movl crosshairs_x, %eax #load x in eax and y into esi, and adjust the offsets the same as before
	movl crosshairs_y, %esi
	imull $ROW_OFFSET, %eax
	imull $COLUMN_OFFSET, %esi
	addl %esi, %eax	
	movb $SPACE_CHARACTER, %cl	#replace current coordinate with space
	pushl %edx
	call mp1_poke
	popl %edx
	
	movl 4(%esp), %edx	#load the x coordinate of the paramter into edx
	shll $SHIFT_BITS, %edx	# shifting the bits left first
	sarl $SHIFT_BITS, %edx #and then an arithmetic shift to get the low 16 bits
	movl 4(%esp), %edi #load the y coordinate by doing an arithmetic shift right to get the high 16 bits
	sarl $SHIFT_BITS, %edi
	addl %edx, crosshairs_x	#add the respective values to the crosshairs_x and crosshairs_y coordinates
	addl %edi, crosshairs_y
	
	CHECK_CONSTRAINTS_LOOP:	
		cmpl $X_POSITION_MIN, crosshairs_x #check the bounds for each
		jl MINIMUM_X_CHECK
		cmpl $X_POSITION_MAX, crosshairs_x	
		jg MAXIMUM_X_CHECK
		cmpl $Y_POSITION_MIN, crosshairs_y
		jl MINIMUM_Y_CHECK
		cmpl $Y_POSITION_MAX, crosshairs_y
		jg MAXIMUM_Y_CHECK
		jmp DONE_WITH_CHECKS
	
	MINIMUM_X_CHECK:	
	movl $X_POSITION_MIN, crosshairs_x #if a check if hit, then make sure to move the positions of each to their respective min or max bounds
	jmp CHECK_CONSTRAINTS_LOOP
	MINIMUM_Y_CHECK:
	movl $Y_POSITION_MIN, crosshairs_y
	jmp CHECK_CONSTRAINTS_LOOP
	MAXIMUM_X_CHECK:
	movl $X_POSITION_MAX, crosshairs_x
	jmp CHECK_CONSTRAINTS_LOOP
	MAXIMUM_Y_CHECK:
	movl $Y_POSITION_MAX, crosshairs_y
	
	DONE_WITH_CHECKS: #make sure to return 0
	andl $0, %eax
	
	ret

mp1_ioctl_getstatus: /*could not do */
	ret

# int mp1_ioctl_endgame(unsigned long ignore) 
# This is the function that frees all the memory in the game and ends it
# Inputs   : ignore (meaningless and should be ignored)
# Outputs  : none
# Registers: Standard C calling convention
mp1_ioctl_endgame:
	movl mp1_missile_list, %eax	#eax also points to the head currently in missile list
	MISSILE_LIST_ITERATION:
		cmpl $0, %eax	#sees if the list is empty
		je ending
		movl NEXT(%eax), %eax	#goes to the next missilie
		pushl %eax	#save callee registers
		pushl %ebx	
		pushl %ecx	
		pushl %edx	
		pushl %edi
		pushl %esi
		pushl mp1_missile_list
		call mp1_free #free the current node looked at
		popl mp1_missile_list
		popl %esi
		popl %edi
		popl %edx
		popl %ecx
		popl %ebx
		popl %eax
		movl %eax, mp1_missile_list	#move the register eax is pointer at to missile list
		cmpl $0, mp1_missile_list	
		jne MISSILE_LIST_ITERATION #if the new value is not zero, then keep iterating
		
	ending:
	ret
