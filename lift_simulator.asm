; This is the final project file containing everything
.include "m2560def.inc"

; DEFINES #########################################################

.def current_floor = r16
.def final_dest = r17
.def lift_direction = r18
.def door_state = r19
.def row = r20					; current row number
.def col = r21					; current column number
.def rowmask = r22				; mask for current row during scan
.def colmask = r23				; mask for current column during scan
.def temp1 = r24
.def temp2 = r25

; CONSTANTS #######################################################

; Describe lift direction
.equ dir_up = 1
.equ dir_stop = 0
.equ dir_down = -1

; Describe door state
.equ door_closed = 0
.equ door_opening = 1
.equ door_opened = 2
.equ door_closing = 3

; Durations (in seconds) used for the "stop at floor" procedure
.equ stop_at_floor_progress_start = 0
.equ stop_at_floor_opening_duration = 1
.equ stop_at_floor_closing_duration = 1
.equ stop_at_floor_opened_duration = 3
.equ stop_at_floor_total_duration = 5			; opening_duration + opened_duration + closing_duration

; Time keeping values
.equ half_second_overflows = 3906
.equ eighth_second_overflows = 976
.equ one_second_overflows = 30				;NOTE: SPECIFICALLY for a 16-bit timer

; Used for controlling the motor speed
.equ motor_speed_low = OCR3BL	;using Timer 3, fast PWM mode
.equ motor_speed_high = OCR3BH
.equ full_motor_speed = 0xFF
.equ no_motor_speed = 0

; Used for scanning the keypad
.equ PORTLDIR = 0xF0			; PD7-4: output, PD3-0: input
.equ INITCOLMASK = 0xEF			; Scan from leftmost column
.equ INITROWMASK = 0x01			; Scan from topmost row
.equ OUTPUTMASK = 0x0F

; Boolean values
.equ true = 1
.equ false = 0		

; MACROS ##########################################################

.macro change_floor
	add current_floor, lift_direction
.endmacro

.macro lcd_display_current_floor
	do_lcd_command 0, 0b10101000 	; set cursor to 1st position on bottom line
	mov temp1, current_floor
	subi temp1, -'0'
	do_lcd_data 1, 'r'
.endmacro

; Procedure to reset 2-byte values in program memory
; Parameter @0 is the memory address
.macro clear
	push temp1
	ldi YL, low(@0)
	ldi YH, high(@0)
	clr temp1
	st Y+, temp1
	st Y, temp1
	pop temp1
.endmacro

; Conduct the command
; Parameters:
;	@0: if 0, @1 is loaded into temp1 as an immediate value
;		else do the command already in temp1
.macro do_lcd_command
	push temp1
	push temp2
	ldi temp2, @0
	cpi temp2, 0
	brne DO_COMMAND_TEMP1
		ldi temp1, @1

	DO_COMMAND_TEMP1:
		rcall lcd_command
		rcall lcd_wait
	pop temp2
	pop temp1
.endmacro

; Print out character
; Parameters:
; 	@0: if 0, @1 is loaded into temp1 is an immediate value
;		else temp1 already has the value loaded before hand - so just print it
.macro do_lcd_data
	push temp1
	push temp2
	ldi temp2, @0
	cpi temp2, 0
	brne PRINT_TEMP1
		ldi temp1, @1

	PRINT_TEMP1:
		rcall lcd_data
		rcall lcd_wait
	pop temp2
	pop temp1
.endmacro


; DATA SEGMENT ####################################################
.dseg
	
	floor_array: .byte 10					; Array of flags to keep track of which floors are requested to be visited
	floor_changed: .byte 1					; Flag used to indicate the floor level has changed

	LED_lift_direction_output: .byte 1		; LED pattern for the lift direction component
	LED_door_state_output: .byte 1			; LED pattern for the door state component
	
	eighthTimeCounter: .byte 2				; Used to calculate whether 1/8th second has passed
	halfTimeCounter: .byte 2				; Used to calculate whether 1/2 second has passed

	; Used for recording keypad presses reliably
	oldCol: .byte 1
	oldRow: .byte 1

	; Used for a "Stop at floor" request
	stop_at_floor: .byte 1			; flag used to indicate a "stop at current floor" request
	stop_at_floor_progress: .byte 1	; Progress value of "stop at floor" procedure.

	; Used to count number of timer4 overflows
	timer4_TimeCounter: .byte 1	

; CODE SEGMENT ####################################################
.cseg

.org 0
	rjmp RESET

; Timer 0 overflow interrupt procedure
.org OVF0addr
	rjmp TIMER0_OVERFLOW

; Timer 2 overflow interrupt procedure
.org OVF2addr
	rjmp TIMER2_OVERFLOW

; Timer 4 overflow interrupt procedure
.org OVF4addr
	rjmp TIMER4_OVERFLOW

; Timer 5 overflow interrupt procedure
.org OVF5addr
	rjmp TIMER5_OVERFLOW

; Hard reset
RESET:

	; Initialise stack
	ldi temp1, high(RAMEND)
	out SPH, temp1
	ldi temp1, low(RAMEND)
	out SPL, temp1

	; Prepare Timer 0
	ldi temp1, 0b00000000			; Operation mode: normal
	sts TCCR0A, temp1	
	ldi temp1, 0b00000010			; Prescaling: 00000010
	sts TCCR0B, temp1	
	ldi temp1, 1<<TOIE0				; Timer interrupt mask
	sts TIMSK0, temp1
	

	; Prepare Timer 2 and the LED's
	ldi temp1, 0b00000000			; Operation mode: normal
	sts TCCR2A, temp1
	ldi temp1, 0b00000010			; Prescaling: CLK/8
	sts TCCR2B, temp1
	ldi temp1, 1<<TOIE2				; Timer mask
	sts TIMSK2, temp1

	; set port B (strobe LED's) and port C (8-bit LED) to be output
	ser temp1
	out DDRB, temp1
	out DDRC, temp1

	; Prepare Timer 3 and the motor
	ldi temp1, (1 << WGM30) | (1 << WGM31)	; Operation mode: Fast PWM
	ori temp1, (1 << COM3B1)				; 				  cleared on compare match
	sts TCCR3A, temp1
	ldi temp1, (1 << CS30)			; Prescaling: none
	sts TCCR3B, temp1

	; Prepare motor related components
	; Set PE2 to be output (Port E will control the motor)
	ser temp1
	out DDRE, temp1

	; Initialise motor speed (ie Setting the value of PWM for OC3B to 0)
	ldi temp1, no_motor_speed
	sts motor_speed_low, temp1
	sts motor_speed_high, temp1

	; Prepare timer4
	ldi temp1, 0b00000000			; Operation mode: normal
	sts TCCR4A, temp1
	ldi temp1, (1 << CS41)			; Prescaling: CLK/8
	sts TCCR4B, temp1
	ldi temp1, 1<<TOIE4				; Timer mask for overflow interrupt
	sts TIMSK4, temp1

	; Prepare Timer 5
	ldi temp1, 0b00000000			; Operation mode: normal
	sts TCCR5A, temp1
	ldi temp1, 0b00000010			; Prescaling: CLK/8
	sts TCCR5B, temp1
	ldi temp1, 1<<TOIE5				; Timer mask for overflow interrupt
	sts TIMSK5, temp1

	; Prepare the keypad ports
	; - Prepare Port L - output through PD7-4, read through PD3-0
	ldi temp1, PORTLDIR
	sts DDRL, temp1

	; Prepare the LCD
	; Configure ports F and A - F and A ports are for LCD Data and LCD control respectively
	ser temp1
	out DDRF, temp1
	out DDRA, temp1
	clr temp1
	out PORTF, temp1
	out PORTA, temp1	
	ldi temp1, 0b00001000
	out PORTE, temp1 			 ;Turn on backlight (through pin PE5 on Port E)

	; Reset the LCD display
	do_lcd_command 0, 0b00111000 ; 2x5x7
	rcall sleep_5ms
	do_lcd_command 0, 0b00111000 ; 2x5x7
	rcall sleep_1ms
	do_lcd_command 0, 0b00111000 ; 2x5x7
	do_lcd_command 0, 0b00111000 ; 2x5x7
	do_lcd_command 0, 0b00001000 ; display off?
	do_lcd_command 0, 0b00000001 ; clear display
	do_lcd_command 0, 0b00000110 ; increment, no display shift
	do_lcd_command 0, 0b00001100 ; Disply on, Cursor off, blink off
	
	; Display initial message
	do_lcd_command 0, 0b10000000	; set cursor to 1st position on top line
	do_lcd_data 0, 'C'
	do_lcd_data 0, 'U'
	do_lcd_data 0, 'R'
	do_lcd_data 0, 'R'
	do_lcd_data 0, 'E'
	do_lcd_data 0, 'N'
	do_lcd_data 0, 'T'
	do_lcd_data 0, ' '
	do_lcd_data 0, 'F'
	do_lcd_data 0, 'L'
	do_lcd_data 0, 'O'
	do_lcd_data 0, 'O'
	do_lcd_data 0, 'R'
	do_lcd_data 0, ':'

	; Clear all variables
	clr lift_direction
	clr door_state
	clr col
	clr row

	; Clear all data in dseg
	clear eighthTimeCounter
	clear halfTimeCounter
	clr temp1
	sts LED_lift_direction_output, temp1
	sts LED_door_state_output, temp1
	sts floor_changed, temp1
	sts stop_at_floor, temp1
	sts stop_at_floor_progress, temp1

	; Clear the floor_array
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

	; Initialise both oldCol and oldRow to be some number greater than 3
	ldi temp1, 9
	sts oldCol, temp1
	sts oldRow, temp1

	; DEBUGGING - Initilisation of variables to test functionality
	ldi current_floor, 6
	ldi lift_direction, dir_stop
	ldi door_state, door_closed
	ldi temp1, true
	sts stop_at_floor, temp1

	sei
	rjmp MAIN

; Keeping track of the lift movement
TIMER0_OVERFLOW:
	; Prologue - save all registers
	TIMER0_PROLOGUE:
		push temp1
		in temp1, SREG
		push temp1
		push r26

	; Interrupt body
		; Load TimeCounter, and increment by 1
		lds temp1, halfTimeCounter
		lds temp2, halfTimeCounter + 1
		adiw temp2:temp1, 1

		;if TimeCounter value is 3906, then half a second has occurred
		cpi temp1, low(half_second_overflows)
		ldi r26, high(half_second_overflows)
		cpc temp2, r26
		brne TIMER0_HALF_SECOND_NOT_ELAPSED_label
		rjmp TIMER0_HALF_SECOND_ELAPSED

			TIMER0_HALF_SECOND_NOT_ELAPSED_LABEL:
			rjmp TIMER0_HALF_SECOND_NOT_ELAPSED

		; if half second has occurred
		TIMER0_HALF_SECOND_ELAPSED:

			; do something

			TIMER0_END_HALF_SECOND_ELAPSED:
			clear halfTimeCounter
			rjmp TIMER0_EPILOGUE

		; else if one second has not elapsed, simply store the incremented
		; counter for the time into TimeCounter, and end interrupt
		TIMER0_HALF_SECOND_NOT_ELAPSED:
			sts halfTimeCounter, r24
			sts halfTimeCounter+1, r25

	TIMER0_EPILOGUE:
		;Restore conflict registers
		pop r26
		pop temp1
		out SREG, temp1
		pop temp1
		reti		

; Describe the door state and lift direction using the LED's
TIMER2_OVERFLOW:
	; Prologue - save all registers
	TIMER2_PROLOGUE:
		push temp1
		push temp2
		in temp1, SREG
		push temp1
		push r26

	; Function body
		; Load TimeCounter, and increment by 1
		lds temp1, eighthTimeCounter
		lds temp2, eighthTimeCounter + 1
		adiw temp2:temp1, 1

		;if TimeCounter value is 3906, then 1/8th a second has occurred
		cpi temp1, low(eighth_second_overflows)
		ldi r26, high(eighth_second_overflows)
		cpc temp2, r26
		brne TIMER2_8th_SECOND_NOT_ELAPSED_label
		rjmp TIMER2_8th_SECOND_ELAPSED
		TIMER2_8th_SECOND_NOT_ELAPSED_label:
			rjmp TIMER2_8th_SECOND_NOT_ELAPSED

		; if 1/8th second has occurred
		TIMER2_8th_SECOND_ELAPSED:

			; Check for door state
			LED_DOOR_STATE:
			cpi door_state, 0
			breq LED_DOOR_CLOSED			; door is closed
			cpi door_state, 1
			breq LED_DOOR_OPENING
			cpi door_state, 2
			breq LED_DOOR_OPENED
			cpi door_state, 3
			breq LED_DOOR_CLOSING

			LED_DOOR_CLOSED:
				ldi temp2, 0b00001000
				rjmp LED_LIFT_DIRECTION
			LED_DOOR_OPENING:
				lds temp2, LED_door_state_output
				cpi temp2, 0
				breq RESET_LED_FOR_DOOR_OPENING
				ldi temp2, 0
				rjmp LED_LIFT_DIRECTION
				RESET_LED_FOR_DOOR_OPENING:	
					ldi temp2, 0b00000100
					rjmp LED_LIFT_DIRECTION
			LED_DOOR_OPENED:
				ldi temp2, 0b00000100
				rjmp LED_LIFT_DIRECTION
			LED_DOOR_CLOSING:	
				lds temp2, LED_door_state_output
				cpi temp2, 0
				breq RESET_LED_FOR_DOOR_CLOSING
				ldi temp2, 0
				rjmp LED_LIFT_DIRECTION
				RESET_LED_FOR_DOOR_CLOSING:	
					ldi temp2, 0b00001000
					rjmp LED_LIFT_DIRECTION				

			;check for lift_direction
			LED_LIFT_DIRECTION:	
			cpi lift_direction, 0
			breq LED_STATIONARY
			cpi lift_direction, 0
			brlt LED_MOVING_DOWN

			;else lift must be moving up
			lds temp1, LED_lift_direction_output
			cpi temp1, 0
				breq RESET_LED_FOR_UP
				lsl temp1
				rjmp DISPLAY_LED_OUTPUT
				RESET_LED_FOR_UP:
					ldi temp1, 1
					rjmp DISPLAY_LED_OUTPUT

			LED_STATIONARY:
				ldi temp1, 0
				breq DISPLAY_LED_OUTPUT

			LED_MOVING_DOWN:
			lds temp1, LED_lift_direction_output
			cpi temp1, 0
				breq RESET_LED_FOR_DOWN
				lsr temp1
				rjmp DISPLAY_LED_OUTPUT
				RESET_LED_FOR_DOWN:
					ldi temp1, 128
					rjmp DISPLAY_LED_OUTPUT			

			DISPLAY_LED_OUTPUT:

			; Display the direction
			out PORTC, temp1
			sts LED_lift_direction_output, temp1

			; Display the door state
			out PORTB, temp2
			sts LED_door_state_output, temp2

			; Reset time counter
			clear eighthTimeCounter
			rjmp TIMER2_EPILOGUE

		; else if one second has not elapsed, simply store the incremented
		; counter for the time into TimeCounter, and end interrupt
		TIMER2_8th_SECOND_NOT_ELAPSED:
			sts eighthTimeCounter, temp1
			sts eighthTimeCounter+1, temp2

	TIMER2_EPILOGUE:
		;Restore conflict registers
		pop r26
		pop temp1
		out SREG, temp1
		pop temp2
		pop temp1
		reti

; Control the "stop at floor" procedure
TIMER4_OVERFLOW:
	; Prologue - save all registers
	TIMER4_PROLOGUE:
	push temp1
	in temp1, SREG
	push temp1

	; Interrupt body
	; Check if there is a "stop at floor" request
	lds temp1, stop_at_floor
	cpi temp1, false

	;Flag is set
	brne TIMER4_TRACK_PROGRESS

	;Else exit interrupt procedure
	rjmp TIMER4_EPILOGUE

	; Start tracking the progress and changing the door state.
	; NOTE: progress can go from 0-5 (progress essentially represents number of seconds elapsed
	; 		while the stop_at_floor flag is set):
	; for 0-1 seconds, door is opening
	; for 1-4 seconds, door is opened
	; for 4-5 seconds, door is closing
	; for 5 seconds onwards, door is closed
	TIMER4_TRACK_PROGRESS:

		; Load TimeCounter, and increment by 1
		lds temp1, timer4_TimeCounter
		inc temp1

		;if TimeCounter value is 30, then one second has occurred (16-bit timer overflows)
		cpi temp1, one_second_overflows
		breq TIMER4_ONE_SECOND_ELAPSED

		; Else one second has not been elapsed
		rjmp TIMER4_ONE_SECOND_NOT_ELAPSED

		; if one second has occurred
		TIMER4_ONE_SECOND_ELAPSED:
			; Load the progress
			lds temp1, stop_at_floor_progress
			
			; Check the progress, and carry out the appropriate procedure
			cpi temp1, stop_at_floor_progress_start
			breq DOOR_IS_OPENING_lol
			cpi temp1, stop_at_floor_total_duration
			breq DOOR_IS_CLOSED
			cpi temp1, (stop_at_floor_total_duration - stop_at_floor_closing_duration)
			breq DOOR_IS_CLOSING

			; At this point, the door must be opened
			DOOR_IS_OPENED:
				ldi door_state, door_opened
				rjmp TIMER4_END_ONE_SECOND_ELAPSED

			DOOR_IS_OPENING_lol:
				ldi door_state, door_opening
				rjmp TIMER4_END_ONE_SECOND_ELAPSED

			DOOR_IS_CLOSING:
				ldi door_state, door_closing
				rjmp TIMER4_END_ONE_SECOND_ELAPSED

			DOOR_IS_CLOSED:	
				; Set the progress to be -1 (in prep for reset of progress)
				ldi temp1, -1
				sts stop_at_floor_progress, temp1

				;Clear the stop_at_floor flag
				ldi temp1, false
				sts stop_at_floor, temp1

				;Close the door
				ldi door_state, door_closed
				rjmp TIMER4_END_ONE_SECOND_ELAPSED


			TIMER4_END_ONE_SECOND_ELAPSED:
				; Increment the stop_at_floor progress, and store it back
				inc temp1
				sts stop_at_floor_progress, temp1

				; Reset the timer
				clr temp1
				sts timer4_TimeCounter, temp1

				rjmp TIMER4_EPILOGUE

		; else if one second has not elapsed, simply store the incremented
		; counter for the time into TimeCounter, and end interrupt
		TIMER4_ONE_SECOND_NOT_ELAPSED:
			sts timer4_TimeCounter, temp1

	TIMER4_EPILOGUE:
	;Restore conflict registers
	pop temp1
	out SREG, temp1
	pop temp1
	reti


; Turns the motor on/off depending on the door_state variable
TIMER5_OVERFLOW:

	; Prologue - save conflict registers
	TIMER5_PROLOGUE: 
	push temp1
	in temp1, SREG
	push temp1

	; Function body
	; Check whether the lift door is opening or closing
	; If so, set motor to full speed
	cpi door_state, door_closing
	breq SET_MOTOR
	cpi door_state, door_opening
	breq SET_MOTOR

	; else turn off the motor
	ldi temp1, no_motor_speed
	sts motor_speed_low, temp1
	sts motor_speed_high, temp1
	rjmp TIMER5_EPILOGUE

	SET_MOTOR:
		ldi temp1, full_motor_speed
		sts motor_speed_low, temp1
		sts motor_speed_high, temp1

	; Epilogue - restore all registers
	TIMER5_EPILOGUE:
	pop temp1
	out SREG, temp1
	pop temp1
	reti		
	

; Main procedure
MAIN:
	; Display current floor on LCD
	lcd_display_current_floor

	; Poll keypresses
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
		ldi temp1, 0xFF
		
		; slow down scan operation
		DELAY:
			dec temp1
			cpi temp1, 0
			brne DELAY

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
	rjmp MAIN
	
HALT: 
	lds temp1, stop_at_floor
	out PORTC, temp1

	; Disable all interrupts
	in temp1, SREG
	andi temp1, 0b10000000
	out SREG, temp1

	rjmp halt

; CONVERSION METHODS FOR KEYPRESS ####################################

; Detect what kind of key was pressed,
; and store the entered value into temp1
CONVERT:
	cpi col, 3

	; If key was in column 3, then a letter was pressed
	breq LETTER_conv

	; else proceed scanning
	cpi row, 3

	; If key was in row 3, then we have a symbol or 0
	breq SYMBOL_conv

	;else input is a number in [0..9]
	; Display the character value of the number on the bottom line of the LCD
	NUMBER:

		;determine the number value
		mov temp1, row
		lsl temp1
		add temp1, row
		add temp1, col
		inc temp1

		; Check the corresponding floor in the floor_array
		ldi XH, high(floor_array)
		ldi XL, low(floor_array)
		add XL, temp1
		ldi temp1, 0
		adc XH, temp1
		ld temp1, X
		cpi temp1, 0
			brne CLEAR_FLOORN_IN_ARRAY
				ldi temp1, true
				st X, temp1
				rjmp CONVERT_END
			CLEAR_FLOORN_IN_ARRAY:				;Remove this: clears the specified floor when the key is pressed again
				ldi temp1, false
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

		; Result must be a hash at this point
		; read number on the bottom line, and display using LED's
		HASH:
			rjmp CONVERT_END

		; Reset display on LCD
		STAR:
			rjmp CONVERT_END

		; Floor pressed is 0 - set in floor_array
		ZERO:
			lds temp1, floor_array
			cpi temp1, 0
			brne CLEAR_FLOOR0_IN_ARRAY
				ldi temp1, 1
				sts floor_array, temp1
				rjmp CONVERT_END
			CLEAR_FLOOR0_IN_ARRAY:
				ldi temp1, 0
				sts floor_array, temp1			
		
	CONVERT_END:
		rjmp END_POLL_KEYPRESSES

; COMMANDS USED FOR THE LCD	##########################################
; Some constants
.equ LCD_RS = 7
.equ LCD_E = 6
.equ LCD_RW = 5
.equ LCD_BE = 4

.macro lcd_set
	sbi PORTA, @0
.endmacro
.macro lcd_clr
	cbi PORTA, @0
.endmacro
;
; Send a command to the LCD (temp1)
;
lcd_command:
	out PORTF, temp1
	rcall sleep_1ms
	lcd_set LCD_E
	rcall sleep_1ms
	lcd_clr LCD_E
	rcall sleep_1ms
	ret

lcd_data:
	out PORTF, temp1
	lcd_set LCD_RS
	rcall sleep_1ms
	lcd_set LCD_E
	rcall sleep_1ms
	lcd_clr LCD_E
	rcall sleep_1ms
	lcd_clr LCD_RS
	ret

lcd_wait:
	push temp1
	clr temp1
	out DDRF, temp1
	out PORTF, temp1
	lcd_set LCD_RW
lcd_wait_loop:
	rcall sleep_1ms
	lcd_set LCD_E
	rcall sleep_1ms
	in temp1, PINF
	lcd_clr LCD_E
	sbrc temp1, 7
	rjmp lcd_wait_loop
	lcd_clr LCD_RW
	ser temp1
	out DDRF, temp1
	pop temp1
	ret

.equ F_CPU = 16000000
.equ DELAY_1MS = F_CPU / 4 / 1000 - 4
; 4 cycles per iteration - setup/call-return overhead

sleep_1ms:
	push r24
	push r25
	ldi r25, high(DELAY_1MS)
	ldi r24, low(DELAY_1MS)
	delayloop_1ms:
		sbiw r25:r24, 1
		brne delayloop_1ms
		pop r25
		pop r24
		ret

sleep_5ms:
	rcall sleep_1ms
	rcall sleep_1ms
	rcall sleep_1ms
	rcall sleep_1ms
	rcall sleep_1ms
	ret
