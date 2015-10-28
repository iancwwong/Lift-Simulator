; This is the final project file containing everything
.include "m2560def.inc"

; DEFINES #########################################################

; For function calls
.def return_register = r0
.def parameter_register = r8

; Registers containing important variables
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

; Starting floor number
.equ starting_floor = 0

; Emergency floor number
.equ emergency_floor = 0

; No final destination is set
.equ no_final_dest = -1
.equ undefined_floor = -1		;for undefined contexts

; Maximum number of floors that can be queued up
.equ queue_size = 10

; Describe lift direction
.equ dir_up = 1
.equ dir_stop = 0
.equ dir_down = -1

; Describe door state
.equ door_closed = 0
.equ door_opening = 1
.equ door_opened = 2
.equ door_closing = 3

; Describe the door request
.equ door_no_request = 0
.equ door_close_request = 1
.equ door_open_request = 2

; LED patterns
.equ LED_pattern_off = 0
.equ LED_door_closed_pattern = 0b00001000
.equ LED_door_opening_pattern = 0b00000100
.equ LED_door_opened_pattern = 0b00000100
.equ LED_door_closing_pattern = 0b00001000
.equ LED_emergency_alarm_pattern = 0b00001100

; Durations (in seconds) used for the "stop at floor" procedure
.equ stop_at_floor_progress_start = 0
.equ stop_at_floor_opening_duration = 1
.equ stop_at_floor_closing_duration = 1
.equ stop_at_floor_opened_duration = 3
.equ stop_at_floor_total_duration = 5			; opening_duration + opened_duration + closing_duration
.equ door_min_opened_duration = 2				; NOTE: Must be less than opened_duration

; Time keeping values represented by number of overflows
; at a timer prescaling of CLK/8
.equ eighth_second_overflows = 976
.equ two_second_overflows = 15624
.equ one_second_overflows_16bit = 30			; NOTE: SPECIFICALLY for a 16-bit timer
.equ tenth_second_overflows_16bit = 3			

; Used for controlling the motor speed
.equ motor_speed_low = OCR3BL	;using Timer 3, fast PWM mode
.equ motor_speed_high = OCR3BH
.equ full_motor_speed = 0xFF
.equ no_motor_speed = 0

; Describe the location of the emergency key on the keypad
; ie the '*' symbol
.equ emergency_key_col = 0
.equ emergency_key_row = 3

; Used for scanning the keypad
.equ PORTLDIR = 0xF0			; PD7-4: output, PD3-0: input
.equ INITCOLMASK = 0xEF			; Scan from leftmost column
.equ INITROWMASK = 0x01			; Scan from topmost row
.equ OUTPUTMASK = 0x0F

; Special keypad mask initialisation for emergency key
.equ EMERGCOLMASK = 0xEF		; leftmost column
.equ EMERGROWMASK = 0x08		; lowest row			

; Boolean values
.equ true = 1
.equ false = 0		

; MACROS ##########################################################

; Clears the LCD
.macro reset_lcd_display
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
.endmacro

; Displays the current floor on the LCD using the format:
; CURRENT FLOOR:
; [current_floor]
.macro lcd_display_current_floor

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
	do_lcd_command 0, 0b10101000 	; set cursor to 1st position on bottom line

	; Display the current floor number in ascii
	mov temp1, current_floor
	subi temp1, -'0'
	do_lcd_data 1, 'r'
.endmacro

; Displays the emergency message through the LCD in the format:
; 	Emergency
; 	Call 000
.macro lcd_display_emergency_message

	; Display initial message
	do_lcd_command 0, 0b10000100	; set cursor to 4th position on top line
	do_lcd_data 0, 'E'
	do_lcd_data 0, 'm'
	do_lcd_data 0, 'e'
	do_lcd_data 0, 'r'
	do_lcd_data 0, 'g'
	do_lcd_data 0, 'e'
	do_lcd_data 0, 'n'
	do_lcd_data 0, 'c'
	do_lcd_data 0, 'y'

	do_lcd_command 0, 0b10101100	; set cursor to 5th position on bottom line
	do_lcd_data 0, 'C'
	do_lcd_data 0, 'a'
	do_lcd_data 0, 'l'
	do_lcd_data 0, 'l'
	do_lcd_data 0, ' '
	do_lcd_data 0, '0'
	do_lcd_data 0, '0'
	do_lcd_data 0, '0'
.endmacro

; Disable all interrupts by clearing the i bit in SREG
; - essentially the opposite of sei
.macro disable_all_interrupts
	push temp1
	in temp1, SREG
	andi temp1, 0b01111111
	out SREG, temp1
	pop temp1
.endmacro

; Procedure to reset 2-byte values in program memory
; Parameter @0 is the memory address
.macro clear
	push temp1
	push YL
	push YH

	ldi YL, low(@0)
	ldi YH, high(@0)
	clr temp1
	st Y+, temp1
	st Y, temp1

	pop YH
	pop YL
	pop temp1
.endmacro

; delay the program by counting DOWN a provided value until 0 MULTIPLE TIMES
; NOTE: The provided value uses 2 bytes (so contains a high and low value)
; @0: low value for the desired delay time
; @1: high value for the desired delay time
; @2: number of times to decrement the value
.macro debounce_delay
	push temp1
	push temp2
	;delay by decrementing the specified values to 0
	DEBOUNCE_DELAY_LOOP:
		rcall delay
		ldi temp2, @1
		ldi temp1, @0

	;decrement the overall number of times the number has reached 0
	dec @2
	cpi @2, 0
	brne DEBOUNCE_DELAY_LOOP
	pop temp2
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

	; Array of flags used to keep track of whih floors are requested to be visited	
	floor_array: .byte 10	

	; Floor queue
	floor_queue: .byte queue_size	; Will be a wrap-around type of queue
	queue_start: .byte 1			; Where the queue begins
	queue_end: .byte 1				; Where the queue ends

	; Flag used to indicate the floor level has changed
	floor_changed: .byte 1					

	; Used for a "Stop at floor" request
	stop_at_floor: .byte 1			; flag used to indicate a "stop at current floor" request
	stop_at_floor_progress: .byte 1	; Progress value of "stop at floor" procedure.

	; Used to indicate whether door quick-close or quick-open was requested
	; 0: no request made
	; 1: close request made
	; 2: open request made
	door_state_change_request: .byte 1	

	; Emergency mode variables
	emergency_flag: .byte 1					; Indicate whether emergency mode was requested
	emergency_alarm: .byte 1				; Inidicate whether emergency alarm is triggered
	final_dest_saved: .byte 1				; Indicate whether a destination floor was preserved prior to going to emergency floor

	; LED patterns that are outputted
	LED_lift_direction_output: .byte 1		; lift direction component
	LED_door_state_output: .byte 1			; door state component
	LED_emergency_alarm_output: .byte 1		; emergency alarm display
	
	; Used to count the number of timer overflows
	timer0_TimeCounter: .byte 2		
	timer1_TimeCounter: .byte 1
	timer2_TimeCounter: .byte 2		
	timer4_TimeCounter: .byte 1
	
	; Flags used as a software approach to reading in button presses reliably
	pb0_button_pushed: .byte 1	
	pb1_button_pushed: .byte 1

	; Used for recording keypad presses reliably
	oldCol: .byte 1
	oldRow: .byte 1	

; CODE SEGMENT ####################################################
.cseg

.org 0
	rjmp RESET

; Interrupt procedure when PB0 button was pushed
.org INT0addr
	rjmp EXT_INT0

.org INT1addr
	rjmp EXT_INT1

; Timer0 overflow interrupt procedure
.org OVF0addr
	rjmp TIMER0_OVERFLOW

; Timer1 overflow interrupt procedure
.org OVF1addr
	rjmp TIMER1_OVERFLOW

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

	; Prepare push buttons as interrupts
	ldi temp1, (2 << ISC00)			; falling edge as interrupt for PB0	
	ori temp1, (2 << ISC10)			; falling edge as interrupt for PB1
	sts EICRA, temp1
	in temp1, EIMSK					; Enable the push button interrupts
	ori temp1, (1 << INT0)
	ori temp1, (1 << INT1)
	out EIMSK, temp1

	; Prepare timer 0
	ldi temp1, 0b00000000			; Operation mode: normal
	out TCCR0A, temp1
	ldi temp1, 0b00000010			; Prescaling: CLK/8
	out TCCR0B, temp1
	ldi temp1, 1<<TOIE0				; Timer mask for overflow interrupt
	sts TIMSK0, temp1

	; Prepare timer 1
	ldi temp1, 0b00000000			; Operation mode: normal
	sts TCCR1A, temp1
	ldi temp1, (1 << CS11)			; Prescaling: CLK/8
	sts TCCR1B, temp1
	ldi temp1, 1<<TOIE1				; Timer mask for overflow interrupt
	sts TIMSK1, temp1

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
	reset_lcd_display

	; Clear all variables
	clr lift_direction
	clr door_state
	clr col
	clr row

	; Clear all data in dseg
	clear timer2_TimeCounter
	clear timer0_TimeCounter
	clr temp1
	sts LED_lift_direction_output, temp1
	sts LED_door_state_output, temp1
	sts floor_changed, temp1
	sts stop_at_floor, temp1
	sts stop_at_floor_progress, temp1
	sts pb0_button_pushed, temp1
	sts door_state_change_request, temp1
	sts timer1_TimeCounter, temp1	
	sts LED_emergency_alarm_output, temp1

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

	; Initialise both oldCol and oldRow to be some number greater than 3
	ldi temp1, 9
	sts oldCol, temp1
	sts oldRow, temp1

	; Initialisation of variables
	ldi door_state, door_closed				; door closed
	ldi current_floor, starting_floor		; start on floor 0
	ldi final_dest, no_final_dest			; no final destination set
	ldi lift_direction, dir_stop			; lift is not moving
	
	ldi temp1, false
	sts floor_changed, temp1				; No floor change
	sts stop_at_floor, temp1				; No stop_at_floor
	sts emergency_flag, temp1				; No emergency_mode
	sts emergency_alarm, temp1				; No emergency_alarm
	sts final_dest_saved, temp1				; No final_dest was preserved

	; DEBUGGING
	; Request to be visited
	;ldi temp1, true
	;sts floor_array+5, temp1

	; add floor 5 to queue
	;ldi temp1, 5
	;mov parameter_register, temp1
	;rcall add_to_queue

	sei
	rjmp MAIN

; PB0 button was pressed - request door to quick-close
; during the "stop at floor" procedure
; NOTE: Relies on the fact that the door is ONLY opened during the "stop at floor" procedure
EXT_INT0:
	; save all conflict registers
	push r26
	push temp2
	push temp1
	in temp1, SREG
	push temp1

	; check if pb_0 button was pushed
	lds temp1, pb0_button_pushed
	cpi temp1, false

	; if false, then go to PROCEED
	breq PB0_proceed

	; else clear pb0_button_pushed, and exit
	ldi temp1, false
	sts pb0_button_pushed,temp1
	rjmp EXT_INT0_end

	; set pb0 to be pushed
	PB0_proceed:
	ldi temp1, true
	sts pb0_button_pushed, temp1

	; check if button was pressed
	ldi temp2, 0b10000000
	in temp1, PIND7					;read the output from PIND (where the push button sends its data)
	and temp1, temp2
	cpi temp1, 0
	breq EXT_INT0_end				;button was not pressed - a 0 signal was found

	; if button was pressed / 1 signal detected: wait
	ldi r26, 10
	debounce_delay low(60000), high(60000), r26

	; check again if button really was pressed
	ldi temp2, 0b10000000
	in temp1, PIND7
	and temp1, temp2
	cpi temp1, 0
	breq EXT_INT0_END

	; Check whether there is a stop at floor request
	lds temp1, stop_at_floor
	cpi temp1, true

	; If not, ignore request to close door
	brne EXT_INT0_END

	; Button is pressed - request to close doors
	ldi temp1, door_close_request
	sts door_state_change_request, temp1

	; restore all the registers
	EXT_INT0_END:
	pop temp1
	out SREG, temp1
	pop temp1
	pop temp2
	pop r26
	reti

; PB1 button was pressed - request to open door
; during "stop at floor" procedure
EXT_INT1:
	; save all conflict registers
	push r26
	push temp2
	push temp1
	in temp1, SREG
	push temp1

	; check if pb_1 button was pushed
	lds temp1, pb1_button_pushed
	cpi temp1, false

	; if false, then go to PROCEED
	breq PB1_proceed

	; else clear pb0_button_pushed, and exit
	ldi temp1, false
	sts pb1_button_pushed,temp1
	rjmp EXT_INT1_end

	; set pb0 to be pushed
	PB1_proceed:
	ldi temp1, true
	sts pb1_button_pushed, temp1

	; check if button was pressed
	ldi temp2, 0b10000000
	in temp1, PIND7					;read the output from PIND (where the push button sends its data)
	and temp1, temp2
	cpi temp1, 0
	breq EXT_INT1_end				;button was not pressed - a 0 signal was found

	; if button was pressed / 1 signal detected: wait
	ldi r26, 10
	DEBOUNCE_DELAY low(60000), high(60000), r26

	; check again if button really was pressed
	ldi temp2, 0b10000000
	in temp1, PIND7
	and temp1, temp2
	cpi temp1, 0
	breq EXT_INT1_END
	
	; Check whether the lift is in motion
	cpi lift_direction, dir_stop

	; If not in motion, then go to stop_at_floor check
	breq INT1_CHECK_STOP_AT_FLOOR

	; Else ignore the request
	rjmp EXT_INT1_END

	INT1_CHECK_STOP_AT_FLOOR:
		; Check whether there is a "stop at floor" request
		lds temp1, stop_at_floor
		cpi temp1, true

		; if there is, then request door to be opened
		breq INT1_REQUEST_DOOR_OPEN

		; else set a "stop at floor" request, and exit
		ldi temp1, true
		sts stop_at_floor, temp1
		rjmp EXT_INT1_END

		INT1_REQUEST_DOOR_OPEN:

			; Set a request to open doors
			ldi temp1, door_open_request
			sts door_state_change_request, temp1

	; restore all the registers
	EXT_INT1_END:
	pop temp1
	out SREG, temp1
	pop temp1
	pop temp2
	pop r26
	reti

; Control the movement of the lift
TIMER0_OVERFLOW:

	; Prologue - push all registers used to stack
	TIMER0_PROLOGUE: 
	push temp1
	push temp2
	in temp1, SREG
	push temp1
	push YH
	push YL
	push r26

	; Check whether the lift should be moving
	cpi lift_direction, dir_stop
	breq TIMER0_EPILOGUE

	; Check also that a floor_change has NOT been requested
	lds temp1, floor_changed
	cpi temp1, false

	; If floor_change has not been requested,
	; move the lift by keeping track of the time elapsed
	breq TIMER0_SIMULATE_LIFT_MOVEMENT

	; Else end timer 0
	rjmp TIMER0_EPILOGUE

	TIMER0_SIMULATE_LIFT_MOVEMENT:

		; Load TimeCounter, and increment by 1
		lds temp1, timer0_TimeCounter
		lds temp2, timer0_TimeCounter + 1
		adiw temp2:temp1, 1

		;if TimeCounter value is two_second_overflows, then 2 seconds has occurred
		cpi temp1, low(two_second_overflows)
		ldi r26, high(two_second_overflows)
		cpc temp2, r26
		brne TIMER0_TWO_SECOND_NOT_ELAPSED

		; if one second has occurred, the lift has gone up one floor
		TIMER0_TWO_SECOND_ELAPSED:

			; Request an update in floor
			ldi r26, true
			sts floor_changed, r26

			; Reset the time counter
			clear timer0_TimeCounter
			rjmp TIMER0_EPILOGUE

		; else if one second has not elapsed, simply store the incremented
		; counter for the time into TimeCounter, and end interrupt
		TIMER0_TWO_SECOND_NOT_ELAPSED:
			sts timer0_TimeCounter, temp1
			sts timer0_TimeCounter+1, temp2

	; Epilogue - restore all registers, and return to main
	TIMER0_EPILOGUE:
	pop r26
	pop YL
	pop YH
	pop temp1
	out SREG, temp1
	pop temp2
	pop temp1
	reti
	
; Blink the strobe LED's 5 times per second when emergency_alarm flag is set
TIMER1_OVERFLOW:
	; Prologue - save all registers
	TIMER1_PROLOGUE:
	push temp1
	in temp1, SREG
	push temp1

	; Check if emergency_alarm flag is set
	lds temp1, emergency_alarm
	cpi temp1, true

	; If emergency alarm flag is set, begin timing
	breq TIMER1_START_TIMING

	; Else not set, make sure the alarm pattern is off, then exit
	ldi temp1, LED_pattern_off
	sts LED_emergency_alarm_output, temp1
	rjmp TIMER1_EPILOGUE

	; Else start keeping track of time
	TIMER1_START_TIMING:
	; Load TimeCounter, and increment by 1
	lds temp1, timer1_TimeCounter
	inc temp1

	;if TimeCounter value is 3, then one-tenth second has occurred (16-bit timer overflows)
	cpi temp1, tenth_second_overflows_16bit
	breq TIMER1_TENTH_SECOND_ELAPSED

	; Else one-tenth second has not been elapsed
	rjmp TIMER1_TENTH_SECOND_NOT_ELAPSED

	; one-tenth second occurred: alternate the LED pattern (ie off = on, off = on)
	TIMER1_TENTH_SECOND_ELAPSED:
		
		lds temp1, LED_emergency_alarm_output
		cpi temp1, 0
		breq TIMER1_RESET_LED_ALARM_OUTPUT

		; LED was on - switch it off
		ldi temp1, 0
		sts LED_emergency_alarm_output, temp1
		rjmp TIMER1_END_TENTH_SECOND_ELAPSED

		; LED was off - switch it on
		TIMER1_RESET_LED_ALARM_OUTPUT:
			ldi temp1, LED_emergency_alarm_pattern
			sts LED_emergency_alarm_output, temp1

		TIMER1_END_TENTH_SECOND_ELAPSED:
			; Display the pattern
			out PORTB, temp1

			; Reset the timer
			clr temp1
			sts timer1_TimeCounter, temp1

			rjmp TIMER1_EPILOGUE

	; else if one second has not elapsed, simply store the incremented
	; counter for the time into TimeCounter, and end interrupt
	TIMER1_TENTH_SECOND_NOT_ELAPSED:
		sts timer1_TimeCounter, temp1

	TIMER1_EPILOGUE:
	;Restore conflict registers
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
		lds temp1, timer2_TimeCounter
		lds temp2, timer2_TimeCounter + 1
		adiw temp2:temp1, 1

		;if TimeCounter value is 976, then 1/8th a second has occurred
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
			breq LED_DOOR_CLOSED		
			cpi door_state, 1
			breq LED_DOOR_OPENING
			cpi door_state, 2
			breq LED_DOOR_OPENED
			cpi door_state, 3
			breq LED_DOOR_CLOSING

			; Load the appropriate LED pattern for corresponding door state
			LED_DOOR_CLOSED:
				ldi temp2, LED_door_closed_pattern
				rjmp LED_LIFT_DIRECTION
			LED_DOOR_OPENING:
				lds temp2, LED_door_state_output
				cpi temp2, LED_pattern_off
				breq RESET_LED_FOR_DOOR_OPENING
				ldi temp2, LED_pattern_off
				rjmp LED_LIFT_DIRECTION
				RESET_LED_FOR_DOOR_OPENING:	
					ldi temp2, LED_door_opening_pattern
					rjmp LED_LIFT_DIRECTION
			LED_DOOR_OPENED:
				ldi temp2, LED_door_opened_pattern
				rjmp LED_LIFT_DIRECTION
			LED_DOOR_CLOSING:	
				lds temp2, LED_door_state_output
				cpi temp2, LED_pattern_off
				breq RESET_LED_FOR_DOOR_CLOSING
				ldi temp2, LED_pattern_off
				rjmp LED_LIFT_DIRECTION
				RESET_LED_FOR_DOOR_CLOSING:	
					ldi temp2, LED_door_closing_pattern
					rjmp LED_LIFT_DIRECTION				

			;check for lift_direction
			LED_LIFT_DIRECTION:	
			cpi lift_direction, dir_stop
			breq LED_STATIONARY
			cpi lift_direction, dir_down
			breq LED_MOVING_DOWN

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

			; Reload the timeCounter values, and reset time counter
			clear timer2_TimeCounter
			rjmp TIMER2_EPILOGUE

		; else if an eighth second has not elapsed, simply store the incremented
		; counter for the time into TimeCounter, and end interrupt
		TIMER2_8th_SECOND_NOT_ELAPSED:
			sts timer2_TimeCounter, temp1
			sts timer2_TimeCounter+1, temp2

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
	push temp2

	; Interrupt body
	; Check if there is a "stop at floor" request
	lds temp1, stop_at_floor
	cpi temp1, false

	;Flag is set
	brne TIMER4_TRACK_PROGRESS

	;Else exit interrupt procedure
	rjmp TIMER4_EPILOGUE

	; Start tracking the progress and changing the door state.
	TIMER4_TRACK_PROGRESS:

		; control push buttons
		rcall control_push_buttons

		; Check for any door change requests
		; Check for door close request
		lds temp1, door_state_change_request
		cpi temp1, door_close_request

		; If there is a request to close the door, execute the quick-close procedure
		; NOTE: the door will ONLY quick-close if the door is opened
		breq QUICK_CLOSE_DOOR

		; If there is a request to open the door, execute the open-door procedure
		; NOTE: door will only open when lift is stopped, or door is closing
		cpi temp1, door_open_request
		breq QUICK_OPEN_DOOR

		; Else continue with tracking the time 
		rjmp TIMER4_TRACK_TIME

		QUICK_CLOSE_DOOR:
			; Check whether the door is opening
			; ie progress <= start + opening_duration
			lds temp1, stop_at_floor_progress
			cpi temp1, stop_at_floor_progress_start + stop_at_floor_opening_duration

			; If so, continue on with tracking the time/progress
			breq TIMER4_TRACK_TIME
			brlt TIMER4_TRACK_TIME

			; Check whether the door is closing
			; ie prgress  = total_duration - closing duration
			cpi temp1, stop_at_floor_total_duration - stop_at_floor_closing_duration
	
			; If equal, then clear door_request (since door is already closing)
			; and continue on with tracking time/progress
			brge DOOR_ALREADY_CLOSING

			; Else accept the door_close request, reset timeCounter, and
			; set the progress to be at that point where door closes
			; ie progress = total_duration - closing_duration
			QUICK_CLOSE:
				; Clear the door_change request
				ldi temp1, door_no_request
				sts door_state_change_request, temp1

				; Change progress to the point where door should start closing
				ldi temp1, stop_at_floor_total_duration
				sts stop_at_floor_progress, temp1

				; Reset timeCounter
				clr temp1
				sts timer4_TimeCounter, temp1

				; Set the door to be closing
				ldi door_state, door_closing

				; End interrupt
				rjmp TIMER4_EPILOGUE

			DOOR_ALREADY_CLOSING:
				ldi temp1, door_no_request
				sts door_state_change_request, temp1
				rjmp TIMER4_TRACK_TIME

		QUICK_OPEN_DOOR:
			; Check whether the door is opening
			; ie progress <= start + opening_duration
			lds temp1, stop_at_floor_progress
			cpi temp1, stop_at_floor_progress_start + stop_at_floor_opening_duration

			; If so, clear the request (since door is already opening)
			breq DOOR_ALREADY_OPENING
			brlt DOOR_ALREADY_OPENING

			; Check whether door is closing
			; ie progress = total_duration - closing_duration
			cpi temp1, stop_at_floor_total_duration - stop_at_floor_closing_duration
			
			; If door is not closing (ie opened), then extend the opening duration
			breq EXTEND_OPEN_DURATION
			brlt EXTEND_OPEN_DURATION

			; Else accept request and perform quick_open
			rjmp QUICK_OPEN

			; Else door must be kept open
			EXTEND_OPEN_DURATION:
				; Accept the open request ONLY when door is opened already for minimum_opening duration
				cpi temp1, stop_at_floor_progress_start + stop_at_floor_opening_duration + door_min_opened_duration

				; If door has been opened for minimum amount of time, then accept the open request
				brge EXTEND_OPEN_ACCEPT_REQUEST

				; Else clear and ignore it
				ldi temp1, door_no_request
				sts door_state_change_request, temp1
				rjmp TIMER4_TRACK_TIME

				EXTEND_OPEN_ACCEPT_REQUEST:
					; Set the progress back to minimum opened duration
					ldi temp1, stop_at_floor_progress_start + stop_at_floor_opening_duration + door_min_opened_duration
					sts stop_at_floor_progress, temp1
					
					; Clear the request
					ldi temp1, door_no_request
					sts door_state_change_request, temp1
					rjmp TIMER4_TRACK_TIME

			QUICK_OPEN:
				; Determine the amount of time to open the door, depending on how much the door has closed
				lds temp1, timer4_TimeCounter
				ldi temp2, one_second_overflows_16bit
				sub temp2, temp1

				; Store starting time value into TimeCounter
				sts timer4_TimeCounter, temp2
				
				; Set the progress to opening door
				ldi temp1, stop_at_floor_progress_start
				sts stop_at_floor_progress, temp1

				; Clear the request
				ldi temp1, door_no_request
				sts door_state_change_request, temp1
				
				rjmp TIMER4_TRACK_TIME

			DOOR_ALREADY_OPENING:
				; Clear the request
				ldi temp1, door_no_request
				sts door_state_change_request, temp1

		TIMER4_TRACK_TIME:
		; Load TimeCounter, and increment by 1
		lds temp1, timer4_TimeCounter
		inc temp1

		;if TimeCounter value is 30, then one second has occurred (16-bit timer overflows)
		cpi temp1, one_second_overflows_16bit
		breq TIMER4_ONE_SECOND_ELAPSED

		; Else one second has not been elapsed
		rjmp TIMER4_ONE_SECOND_NOT_ELAPSED

		; if one second has occurred
		TIMER4_ONE_SECOND_ELAPSED:
			; Load the progress
			lds temp1, stop_at_floor_progress
			
			; Check the progress, and carry out the appropriate procedure
			cpi temp1, stop_at_floor_progress_start
			breq DOOR_IS_OPENING
			cpi temp1, stop_at_floor_total_duration
			breq DOOR_IS_CLOSED
			cpi temp1, (stop_at_floor_total_duration - stop_at_floor_closing_duration)
			breq DOOR_IS_CLOSING

			; At this point, the door must be opened
			DOOR_IS_OPENED:
				ldi door_state, door_opened
				rjmp TIMER4_END_ONE_SECOND_ELAPSED

			DOOR_IS_OPENING:
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
				lds temp1, stop_at_floor_progress
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
	pop temp2
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
	; Check if push buttons should be enabled, based on whether lift is moving
	rcall control_push_buttons
	
	; Check if emergency flag is set
	lds temp1, emergency_flag
	cpi temp1, true

	; If not set, execute lift in normal mode
	brne NORMAL_MODE

	; Else execute lift in emergency mode
	rjmp EMERGENCY_MODE

NORMAL_MODE:
	; Update curr_floor and display it on LCD
	UPDATE_AND_DISPLAY_CURRENT_FLOOR:
		rcall update_curr_floor
		lcd_display_current_floor

	; Check whether to stop at current floor
	CHECK_TO_STOP_AT_FLOOR:

		; Check whether floor_array[curr_floor] == true
		mov parameter_register, current_floor
		rcall check_floor_array
		mov temp1, return_register
		cpi temp1, true

		; A request was made to stop at current floor
		breq STOP_AT_CURRENT_FLOOR

		; Else proceed
		rjmp CURR_FLOOR_VISITED

		; Carry out the "stop at floor" procedure
		STOP_AT_CURRENT_FLOOR:
			
			disable_all_interrupts
			ldi temp1, true
			sts stop_at_floor, temp1
			ldi lift_direction, dir_stop
			sei
			rcall complete_stop_at_floor
			

	; Set floor_array[current_floor] to be false, indicating we've visited the floor
	CURR_FLOOR_VISITED:
		mov parameter_register, current_floor
		rcall set_floor_false

	; Check whether final destination has been reached
	CHECK_FINAL_DEST_ARRIVED:
		cp current_floor, final_dest

		; If equal, final destination has been reached
		breq FINAL_DEST_REACHED

		; Else check final_destination
		rjmp UPDATE_FINAL_DESTINATION

		; Clear final destination, and stop the lift
		FINAL_DEST_REACHED:
			ldi final_dest, no_final_dest
			ldi lift_direction, dir_stop

	; Check whether final destination needs to be updated
	UPDATE_FINAL_DESTINATION:
		cpi final_dest, no_final_dest

		; If final dest not set, update from queue
		breq UPDATE_FROM_QUEUE
			
		; Else proceed with journey (since final_dest is set and not reached)
		rjmp PROCEED_WITH_JOURNEY

		UPDATE_FROM_QUEUE:
			
			rcall update_queue

			; Check whether final_dest is still not set
			cpi final_dest, no_final_dest

			; If set, then set the direction
			brne SET_NEW_DIRECTION

			; Else proceed
			rjmp START_POLL_KEYPRESSES

			SET_NEW_DIRECTION:
				disable_all_interrupts
				rcall set_lift_direction
				sei
				rjmp START_POLL_KEYPRESSES

		; At this point, final_dest is set but not yet reached
		PROCEED_WITH_JOURNEY:
			disable_all_interrupts
			rcall set_lift_direction
			sei
			
	; Poll Keypresses
	START_POLL_KEYPRESSES:
		; Disable all interrupts
		disable_all_interrupts

		; Poll the keypresses
		rjmp poll_keypresses

	MAIN_END_POLL_KEYPRESSES:
	; Re-enable the interrupts
	sei

	; Start main again
	rjmp MAIN

EMERGENCY_MODE:

	; Complete any stop at floor procedures currently being executed
	COMPLETE_ANY_STOP_AT_FLOOR:
		; Check if any stop_at_floor_requests
		lds temp1, stop_at_floor
		cpi temp1, true

		; if not set, then proceed to going to emergency floor
		brne PRESERVE_DESTINATION_FLOOR

		; else request a door_close, and complete the "stop at floor" procedure
		ldi temp1, door_close_request
		sts door_state_change_request, temp1
		rcall complete_stop_at_floor

	; If final_dest is currently set, preserve in memory
	PRESERVE_DESTINATION_FLOOR:
		cpi final_dest, no_final_dest
	
		; If final_dest is not set, then proceed to set emergency floor
		breq SET_EMERGENCY_FLOOR

		; Else preserve the destination floor
		push final_dest
		
		; Set the flag indicating that a destination floor has been preserved
		ldi temp1, true
		sts final_dest_saved, temp1

	; Prepare emergency_floor as final destination, and wait until emergency_floor is reached
	SET_EMERGENCY_FLOOR:
		; Update the current floor
		rcall update_curr_floor

		; Display current floor on LCD
		lcd_display_current_floor
		
		; Check whether emergency_floor is reached
		cpi current_floor, emergency_floor
		breq EMERGENCY_ARRIVAL

		; Else prepare to move the lift
		disable_all_interrupts
		ldi final_dest, emergency_floor					; Set final destination to be emergency floor
		rcall set_lift_direction						; Set the direction of the lift
		sei												; Re-enable interrupts
		rjmp SET_EMERGENCY_FLOOR						; Loop back
		
	; Carry out "stop at floor" procedure at emergency floor
	EMERGENCY_ARRIVAL:
		; Stop the lift
		ldi lift_direction, dir_stop

		; make a "stop at floor" request
		ldi temp1, true
		sts stop_at_floor, temp1

		; Wait until "stop at floor" procedure is completed
		rcall complete_stop_at_floor

	; Enable the emergency alarm
	TURN_ON_EMERGENCY_ALARM:
		; Disable timer2 so that emergency alarm can be displayed
		ldi temp1, 0
		sts TIMSK2, temp1

		; Turn on emergency_alarm
		ldi temp1, true
		sts emergency_alarm, temp1

	; Display the emergency message
	reset_lcd_display
	lcd_display_emergency_message
	
	; Wait until emergency key is pressed again (ie cancelled)
	RESET_EMERGENCY_FLAG:
		; Start polling for emergency key
		MAIN_START_POLL_EMERGENCY_KEY:
		rjmp POLL_EMERGENCY_KEY
		MAIN_END_POLL_EMERGENCY_KEY:

		; Check if lift is still in emergency mode
		lds temp1, emergency_flag
		cpi temp1, true
	
		; If still set, poll again for emergency flag
		breq MAIN_START_POLL_EMERGENCY_KEY

	; Resume normal operation of the lift
	RESUME_NORMAL_MODE:
		; Check whether a final_dest has been preserved prior to entering emergency mode
		lds temp1, final_dest_saved
		cpi temp1, true

		; If a final dest was preserved, then restore it
		breq RESTORE_FINAL_DEST

		; Else proceed 
		rjmp NORMAL_MODE_PREP

		RESTORE_FINAL_DEST:
			pop final_dest
			
			; Reset the flag
			ldi temp1, false
			sts final_dest_saved, temp1

		NORMAL_MODE_PREP:
		; Turn off emergency_alarm
		ldi temp1, false
		sts emergency_alarm, temp1

		; Re-enable Timer2 interrupt
		ldi temp1, (1 << TOIE2)
		sts TIMSK2, temp1

		; Return to main
		reset_lcd_display
		rjmp MAIN


; DEBUGGING	 - check particular outputs using LED's
HALT: 
	disable_all_interrupts

	out PORTC, final_dest

	rjmp halt 

; GENERAL FUNCTIONS ######################################################

; Determine whether open/close buttons should be enabled or disabled
; and also their mode of interrupt trigger in some situations
control_push_buttons:
	push temp1

	; Enable/disable the push buttons
	CHECK_ENABLE_DISABLE:
	; Load mask register
	in temp1, EIMSK

	; Check the lift motion
	cpi lift_direction, dir_stop

	; If lift is stopped, then enable both buttons
	breq ENABLE_OPEN_CLOSE_BUTTONS

	; Else disable both buttons
	andi temp1, (0 << INT0)
	andi temp1, (0 << INT1)
	rjmp END_CHECK_ENABLE_DISABLE

	ENABLE_OPEN_CLOSE_BUTTONS:
	ori temp1, (1 << INT0)
	ori temp1, (1 << INT1)

	END_CHECK_ENABLE_DISABLE:
	; Store back into interrupt mask register	
	out EIMSK, temp1

	; Change the interrupt trigger mode for the push buttons
	CHECK_MODE:
	; Load control register for external interrupts
	lds temp1, EICRA

	; Check whether doors are opened
	cpi door_state, door_opened

	; If doors are opened, set the interrupt trigger for pb1 as low-level
	breq CAN_HOLD_PB1

	; Else set the mode to falling-edge triggered
	ori temp1, (2 << ISC10)
	rjmp END_CHECK_MODE

	CAN_HOLD_PB1:
	andi temp1, 0b11110011

	END_CHECK_MODE:
	; Store back into control register
	sts EICRA, temp1

	pop temp1
	ret

; Update the current floor
update_curr_floor:
	; Save conflict registers
	push temp1

	; Check if there is a floor changed request
	lds temp1, floor_changed
	cpi temp1, true

	; If there is a floor_change request, update the current floor
	breq FLOOR_HAS_CHANGED
	rjmp END_UPDATE_CURR_FLOOR

	FLOOR_HAS_CHANGED:
		add current_floor, lift_direction

		; Clear the floor changed request flag
		ldi temp1, false
		sts floor_changed, temp1

	; Restore conflict registers and return
	END_UPDATE_CURR_FLOOR:
	pop temp1
	ret

; Determines the lift direction based on the relativity of final floor with current floor
set_lift_direction:
	cp final_dest, current_floor

	; If final dest is lower than current floor, direction is down
	brlo SET_DIR_DOWN

	; If final dest is lower than current floor, direction is down
	breq SET_DIR_STOP

	; Else direction must be up
	ldi lift_direction, dir_up
	rjmp END_SET_LIFT_DIRECTION

	SET_DIR_DOWN:
	ldi lift_direction, dir_down
	rjmp END_SET_LIFT_DIRECTION

	SET_DIR_STOP:
	ldi lift_direction, dir_stop

	END_SET_LIFT_DIRECTION:
	ret

; Wait until the "stop at floor" procedure is completed
complete_stop_at_floor:
	push temp1
	
	STOP_AT_FLOOR_LOOP:
	; Check whether the stop_at_floor is set
	lds temp1, stop_at_floor
	cpi temp1, true
	
	; If set, then loop back
	breq STOP_AT_FLOOR_LOOP
	
	; else end
	pop temp1
	ret	

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

		lds temp1, PINL				; Read PORT L			
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
	; Display the character value of the number on the bottom line of the LCD
	NUMBER_conv:

		;determine the number value
		mov temp1, row
		lsl temp1
		add temp1, row
		add temp1, col
		inc temp1

		cpi final_dest, no_final_dest


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

		; Do nothing
		HASH:
			rjmp CONVERT_END

		; Enable emergency mode
		STAR:
			ldi temp1, true
			sts emergency_flag, temp1
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

; Poll the emergency key, ie the '*' symbol 
; located in column 0, row 3 (bottom left of keypad)
POLL_EMERGENCY_KEY:
	
	; Prepare column start and end points
	ldi colmask, EMERGCOLMASK
	
	; set the location of the emergency key
	ldi col, emergency_key_col

	CHECK_EMERGENCY_COLUMN:
	; else scan the column
	sts PORTL, colmask 
	lds temp1, PINL				; Read PORT A			
	andi temp1, OUTPUTMASK		; Get keypad output value
	cpi temp1, 0xF				; check if any row is high (ie nothing is pressed)

	; if something is pressed, check the row
	brne CHECK_EMERGENCY_ROW

	; Else reset oldCol and oldRow
	ldi temp1, 9
	sts oldCol, temp1
	sts oldRow, temp1
	rjmp END_POLL_EMERGENCY_KEY

	CHECK_EMERGENCY_ROW:
	; Prepare row start and end points
	ldi rowmask, EMERGROWMASK
	ldi row, emergency_key_row

	; Scan the row
	mov temp2, temp1
	and temp2, rowmask		; Check the unmasked bit
	
	; if the bit is clear, something has been pressed.
	; Check if key pressed is the same as previous key (debouncing)
	breq CHECK_EMERGENCY_KEY_PRESSED

	; else exit
	rjmp END_POLL_EMERGENCY_KEY

	CHECK_EMERGENCY_KEY_PRESSED:

	; Check whether the column and rows are the same
	lds temp1, oldCol
	lds temp2, oldRow
	cp temp1, col
	cpc temp2, row

	; if the same, exit
	breq END_POLL_EMERGENCY_KEY

	; else emergency key confirmed to have been pressed - proceed to execute the process
	sts oldCol, col
	sts oldRow, row
	rjmp PROCESS_EMERGENCY_KEY
	
	END_POLL_EMERGENCY_KEY:
	; Return to main when poll keypress procedure completed
	rjmp MAIN_END_POLL_EMERGENCY_KEY

; Sets a request for emergency mode, or cancels it
PROCESS_EMERGENCY_KEY:
	; Check if emergency flag is already set
	lds temp1, emergency_flag
	cpi temp1, true

	; If already set, then clear the request
	breq EXIT_EMERGENCY_MODE

	; Else make a request for emergency mode
	ldi temp1, true
	sts emergency_flag, temp1
	sts emergency_alarm, temp1
	rjmp END_POLL_EMERGENCY_KEY

	EXIT_EMERGENCY_MODE:
	ldi temp1, false
	sts emergency_flag, temp1
	sts emergency_alarm, temp1
	rjmp END_POLL_EMERGENCY_KEY

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

; Refreshes the floor queue by constantly removing the first item and validating it,
; and sets final_dest to the first valid item (or undefined if queue is empty)
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
			rjmp END_UPDATE_QUEUE 
	
	QUEUE_WAS_EMPTY:
	; Set final_dest to be undefined
	ldi final_dest, undefined_floor

	END_UPDATE_QUEUE:
	pop temp2
	pop temp1
	ret

; ARRAY RELATED FUNCTIONS

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

	; Return the value as parameter
	mov return_register, temp1
	
	END_CHECK_FLOOR_ARRAY:
	pop temp1
	pop XH
	pop XL
	ret

; Set the index of the floor value in r8 of the floor array to be false
set_floor_false:
	push XL
	push XH
	push temp1

	; Determine the address of the array element to set false
	mov temp1, parameter_register		
	ldi XL, low(floor_array)
	ldi XH, high(floor_array)
	add XL, temp1
	ldi temp1, 0
	adc XH, temp1					; X now contains the address of the one to set false
	
	; Set false
	ldi temp1, false
	st X, temp1

	END_SET_FLOOR_FALSE:
	pop temp1
	pop XH
	pop XL
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


; FUNCTIONS USED FOR THE LCD	##########################################
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
