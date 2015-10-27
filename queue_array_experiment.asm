; This tests the implementation of the floor_array and floor_queue

.include "m2560def.inc"

.def final_dest = r17

; For function calls
.def return_register = r0
.def parameter_register = r8

.def temp1 = r24
.def temp2 = r25

.def row = r20					; current row number
.def col = r21					; current column number
.def rowmask = r22				; mask for current row during scan
.def colmask = r23				; mask for current column during scan

; Used for scanning the keypad
.equ PORTLDIR = 0xF0			; PD7-4: output, PD3-0: input
.equ INITCOLMASK = 0xEF			; Scan from leftmost column
.equ INITROWMASK = 0x01			; Scan from topmost row
.equ OUTPUTMASK = 0x0F

.equ no_final_dest = -1
.equ undefined_floor = -1

.equ queue_size = 10			; Maximum number of floors that can be queued up

.equ true = 1
.equ false = 0

; MACROS #################

; Disable all interrupts by clearing the i bit in SREG
; - essentially the opposite of sei
.macro disable_all_interrupts
	push temp1
	in temp1, SREG
	andi temp1, 0b01111111
	out SREG, temp1
	pop temp1
.endmacro

.dseg

	; Floor array 
	floor_array: .byte 10

	; Floor queue
	floor_queue: .byte queue_size	; Will be a wrap-around type of queue
	queue_start: .byte 1			; Where the queue begins
	queue_end: .byte 1				; Where the queue ends

	; Used for recording keypad presses reliably
	oldCol: .byte 1
	oldRow: .byte 1

.cseg

.org 0	
	rjmp RESET

RESET:
	; Initialise stack
	ldi temp1, high(RAMEND)
	out SPH, temp1
	ldi temp1, low(RAMEND)
	out SPL, temp1

	; Prepare PORTC for LED output
	ser temp1
	out DDRC, temp1

	; Prepare the keypad ports
	; - Prepare Port L - output through PD7-4, read through PD3-0
	ldi temp1, PORTLDIR
	sts DDRL, temp1

	; initialise floor array
	clr temp1
	sts floor_array, temp1
	sts floor_array+1, temp1
	sts floor_array+2, temp1
	sts floor_array+3, temp1
	sts floor_array+4, temp1
	sts floor_array+5, temp1
	sts floor_array+6, temp1
	sts floor_array+7, temp1
	sts floor_array+8, temp1
	sts floor_array+9, temp1

	; initialise floor queue
	ldi temp1, undefined_floor
	sts floor_queue, temp1
	sts floor_queue+1, temp1
	sts floor_queue+2, temp1
	sts floor_queue+3, temp1
	sts floor_queue+4, temp1
	sts floor_queue+5, temp1
	sts floor_queue+6, temp1
	sts floor_queue+7, temp1
	sts floor_queue+8, temp1
	sts floor_queue+9, temp1

	; Initialise start and end points for floor queue
	ldi temp1, 0
	sts queue_start, temp1
	sts queue_end, temp1

	; Initialise final_dest
	ldi final_dest, no_final_dest

	rjmp MAIN

MAIN:
	out PORTC, final_dest

	; Uncheck the array - ie visit it
	cpi final_dest, no_final_dest
	breq START_POLL_KEYPRESSES

	; Prepare pointer to corresponding floor in array
	ldi XH, high(floor_array)
	ldi XL, low(floor_array)
	add XL, final_dest
	ldi temp1, 0
	adc XH, temp1

	; Clear the floor in floor_array
	ldi temp1, false
	st X, temp1

	; Poll Keypresses
	START_POLL_KEYPRESSES:

		; Poll the keypresses
		rjmp POLL_KEYPRESSES

	MAIN_END_POLL_KEYPRESSES:

	; Start main again
	rjmp MAIN

HALT:
	ldi temp1, 0b10101010
	out PORTC, temp1

	rjmp HALT

; FUNCTIONS #################
; Poll the keypad
POLL_KEYPRESSES:
	
	; Prepare column start and end points
	ldi colmask, INITCOLMASK
	clr col

	; Loop through columns
	COLUMN_LOOP:
		cpi col, 4

		; if column < 4, then proceed to SCAN_COLUMN (entire keyboard scanned)
		brlt SCAN_COLUMN

		; else reset oldCol and oldRow, and go back to MAIN
		ldi temp1, 9
		sts oldCol, temp1
		sts oldRow, temp1
		rjmp END_POLL_KEYPRESSES

		SCAN_COLUMN:
		; else scan the column
		sts PORTL, colmask 
				
		; slow down scan operation
		ldi temp1, 0xFF
		ldi temp2, 0
		rcall delay

		lds temp1, PINL				; Read PORT A			
		andi temp1, OUTPUTMASK		; Get keypad output value
		cpi temp1, 0xF				; check if any row is high (ie nothing is pressed)

		; if nothing is pressed, go to next column
		breq NEXT_COLUMN

		; else determine which row is low (ie has something pressed)

		; Prepare row start and end points
		ldi rowmask, INITROWMASK
		clr row

		ROW_LOOP:
			cpi row, 4

			; if current row is 4, then go to next column
			breq NEXT_COLUMN

			; else proceed with scanning each row
			mov temp2, temp1
			and temp2, rowmask		; Check the unmasked bit
			
			; if the bit is clear, something has been pressed.
			; Check if key pressed is the same as previous key
			breq CHECK_COL_PRESSED

			; else move onto next row
			rjmp NEXT_ROW

			CHECK_COL_PRESSED:
			lds temp1, oldCol
			cp temp1, col
				; if the same, check row
				breq CHECK_ROW_PRESSED

				; else key press is different 
				; Record new col and row combination, and proceed to execute process
				sts oldCol, col
				sts oldRow, row
				rjmp CONVERT

				CHECK_ROW_PRESSED:
				lds temp1, oldRow
				cp temp1, row

					;if the same, then same key has been pressed - go back to main
					breq END_POLL_KEYPRESSES

					; else key press is different 
					; Record new col and row combination, and proceed to execute process
					sts oldCol, col
					sts oldRow, row
					rjmp CONVERT		

			NEXT_ROW:
			inc row
			lsl rowmask		
			rjmp ROW_LOOP
		
		; End of column loop
		NEXT_COLUMN:			
			inc col
			lsl colmask				; TO move to next column
			inc colmask				; Ensure pull up resistors are enabled
			rjmp COLUMN_LOOP
	
	END_POLL_KEYPRESSES:
	; Return to main when poll keypress procedure completed
	rjmp MAIN_END_POLL_KEYPRESSES

; Detect what kind of key was pressed
; and carry out appropriate actions
CONVERT:
	cpi col, 3

	; If key was in column 3, then a letter was pressed
	breq LETTER_conv

	; else proceed scanning
	cpi row, 3

	; If key was in row 3, then we have a symbol or 0
	breq SYMBOL_conv

	;else input is a number in [0..9]
	NUMBER_conv:

		;determine the number value
		mov temp1, row
		lsl temp1
		add temp1, row
		add temp1, col
		inc temp1

		; Check whether floor is requested to be visited
		mov parameter_register, temp1
		rcall check_floor_array
		mov temp2, return_register
		cpi temp2, true

		; If not set, then set the floor, and add it to array
		brne QUEUE_REQUESTED_FLOOR

		; Else ignore the request
		rjmp CONVERT_END

		QUEUE_REQUESTED_FLOOR:
			; Add the floor to queue
			mov parameter_register, temp1
			rcall add_to_queue

			; Prepare pointer to corresponding floor in array
			ldi XH, high(floor_array)
			ldi XL, low(floor_array)
			add XL, temp1
			ldi temp1, 0
			adc XH, temp1

			; Set the floor in floor_array
			ldi temp1, true
			st X, temp1
			rjmp CONVERT_END


	LETTER_conv:
		rjmp CONVERT_END


	SYMBOL_conv:
		; Check for '*' symbol (ie column 0)
		cpi col, 0
		breq STAR

		; Check for '0'
		cpi col, 1
		breq ZERO

		rjmp HASH

		; Remove item from queue and set final_dest to be that
		HASH:
			rcall update_queue
			rjmp CONVERT_END

		; Do nothing
		STAR:
			rjmp CONVERT_END

		; Floor pressed is 0 - set in floor_array
		ZERO:
			; Check whether floor is requested to be visited
			lds temp2, floor_array
			cpi temp2, true

			; If not set, then set the floor, and add it to array
			brne QUEUE_REQUESTED_FLOOR0

			; Else ignore the request
			rjmp CONVERT_END

			QUEUE_REQUESTED_FLOOR0:
				; Add floor0 to queue
				ldi temp1, 0
				mov parameter_register, temp1
				rcall add_to_queue

				; Set the floor in floor_array
				ldi temp1, true
				sts floor_array, temp1
				rjmp CONVERT_END			
		
	CONVERT_END:
		rjmp END_POLL_KEYPRESSES

; Refreshes the floor queue and sets final_dest to the first valid item (or undefined if invalid)
update_queue:
	push temp1
	push temp2

	UPDATE_QUEUE_LOOP:
	; Obtain the first item through r0
	rcall remove_queue_head	
	
	; Check if item was valid
	mov temp2, return_register
	cpi temp2, undefined_floor
	
	; If not undefined, then check whether the floor can be a new final dest
	brne CHECK_FOR_NEW_DEST

	; Else queue must have been empty
	rjmp QUEUE_WAS_EMPTY
	
	CHECK_FOR_NEW_DEST:
		; Preserve the floor removed
		push return_register

		; Check whether corersponding floor in floor_array was set to true (ie requested to be visited)
		mov parameter_register, return_register				; Prepare designated registers
		rcall check_floor_array
		mov temp1, return_register					; temp1 contains the boolean value of floor_array[floor_num] == true
		cpi temp1, true

		; If true, a new final destination can be set
		breq SET_NEW_FINAL_DEST

		; Else go back to updating the queue 
		rjmp UPDATE_QUEUE_LOOP

		SET_NEW_FINAL_DEST:
			pop return_register
			mov final_dest, return_register
			;set_lift_direction
			rjmp END_UPDATE_QUEUE 
	
	QUEUE_WAS_EMPTY:
	; Set final_dest to be undefined
	ldi final_dest, undefined_floor

	END_UPDATE_QUEUE:
	pop temp2
	pop temp1
	ret

; Check whether the floor value in r8 is set to true in floor_array
; ie floor_array[r8] == true
; Return the boolean value through r0
check_floor_array:
	push XL
	push XH
	push temp1

	mov temp1, parameter_register
	; Determine the address of the array to check (in cseg) - addres stored into X
	ldi XH, high(floor_array)
	ldi XL, low(floor_array)
	add XL, temp1
	ldi temp1, 0 
	adc XH, temp1
	ld temp1, X
	cpi temp1, false

	; Return the value as parameter
	mov return_register, temp1
	
	END_CHECK_FLOOR_ARRAY:
	pop temp1
	pop XH
	pop XL
	ret

;Delay by subtracting a pair of values until they are 0
; uses the values preloaded in value_low, and value_high
delay:
	DELAY_LOOP:
		;subtract 1 from the pair of values
		subi temp1, low(1)
		sbci temp2, high(1)

	;check whether value is 0
	cpi temp1, 0
	brne DELAY_LOOP
	cpi temp2, 0
	brne DELAY_LOOP
	ret

; QUEUE RELATED FUNCTIONS

; Adds value stored in r8 to the queue
add_to_queue:
	; Save conflict registers
	push XL
	push XH
	push temp1

	; Determine where to add item (ie load the address of queue end point into X)
	ldi XL, low(floor_queue)
	ldi XH, high(floor_queue)
	lds temp1, queue_end
	add XL, temp1
	clr temp1
	adc XH, temp1			; X now contains the address of where to insert element in queue
	
	; Store the floor number
	st X, parameter_register

	; Increment the end_point
	rcall increment_queue_end

	END_ADD_TO_QUEUE:
	pop temp1
	pop XH
	pop XL
	ret

; Remove the first item from floor_queue, and return it through r0
remove_queue_head:
	push XL
	push XH
	push temp1
	push r26

	; Obtain the item at queue_start
	ldi XL, low(floor_queue)
	ldi XH, high(floor_queue)
	lds temp1, queue_start
	add XL, temp1
	clr temp1
	adc XH, temp1			; X now contains the address of where to insert element in queue
	ld temp1, X

	; store item in r0
	mov return_register, temp1

	; Check if loaded item is undefined
	cpi temp1, undefined_floor

	; If item is undefined, queue is empty - exit
	breq END_REMOVE_QUEUE_HEAD

	; Set the data at same address to be undefined
	ldi temp1, undefined_floor
	st X, temp1

	; Increment start point
	rcall increment_queue_start

	END_REMOVE_QUEUE_HEAD:
	pop r26
	pop temp1
	pop XH
	pop XL
	ret

; Increments the end-point of the queue
increment_queue_end:
	push temp1
	
	; Get the new end_point
	lds temp1, queue_end
	inc temp1

	; Check if new end point is equal to queue size
	cpi temp1, queue_size

	; If equal, reset end to 0
	brge RESET_QUEUE_END
	
	; else store end, and end function
	rjmp END_INCREMENT_QUEUE_END

	RESET_QUEUE_END:
	ldi temp1, 0

	END_INCREMENT_QUEUE_END:
	; store the new end point
	sts queue_end, temp1
	pop temp1
	ret

; Increments the start-point of the queue
increment_queue_start:
	push temp1
	
	; Get the new start point
	lds temp1, queue_start
	inc temp1

	; Check if new end point is equal to queue size
	cpi temp1, queue_size

	; If equal, reset end to 0
	brge RESET_QUEUE_START
	
	; else store end, and end function
	rjmp END_INCREMENT_QUEUE_START

	RESET_QUEUE_START:
	ldi temp1, 0

	END_INCREMENT_QUEUE_START:
	; store the new end point
	sts queue_start, temp1
	pop temp1
	ret
