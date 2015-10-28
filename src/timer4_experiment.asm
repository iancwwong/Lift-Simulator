; This file uses timer4 to control the doors by keeping
; track of the progress (ie number of seconds) that have
; passed when the stop_at_floor flag is set

.include "m2560def.inc"

.def door_state = r17
.def temp1 = r24
.def temp2 = r25

; Describe the door_state
.equ door_closed = 0
.equ door_opening = 1
.equ door_opened = 2
.equ door_closing = 3

; Describe the door request
.equ door_no_request = 0
.equ door_close_request = 1
.equ door_open_request = 2

; Durations (in seconds) used for the "stop at floor" procedure
.equ stop_at_floor_progress_start = 0
.equ stop_at_floor_opening_duration = 1
.equ stop_at_floor_closing_duration = 1
.equ stop_at_floor_opened_duration = 3
.equ stop_at_floor_total_duration = 5			; opening_duration + opened_duration + closing_duration

; Number of overflows that represent one second, with timer prescaling of CLK/8
; NOTE: Specifically for a 16-bit counter 
.equ one_second_overflows_16bit = 30

.equ true = 1
.equ false = 0

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

; delay the program by counting DOWN a provided value until 0 MULTIPLE TIMES
; NOTE: The provided value uses 2 bytes (so contains a high and low value)
; @0: low value for the desired delay time
; @1: high value for the desired delay time
; @2: number of times to decrement the value
.macro DEBOUNCE_DELAY
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
	stop_at_floor: .byte 1			;flag used to indicate a "stop at current floor" request
	stop_at_floor_progress: .byte 1	;Stage number of stopping the door (0,1,2,3,4,5)
					`				; 0: opening
									; 1: opened
									; 2: opened
									; 3: opened
									; 4: closing
									; 5: closed

	timer4_TimeCounter: .byte 2		; Used to count number of timer4 overflows

	; Flags used as a software approach to reading in button presses reliably
	pb0_button_pushed: .byte 1	
	pb1_button_pushed: .byte 1	

	; Used to indicate whether door quick-close or quick-open was requested
	; 0: no request made
	; 1: close request made
	; 2: open request made
	door_state_change_request: .byte 1

.cseg

.org 0
	rjmp RESET

; 	Interrupt procedure when PB0 button was pushed
.org INT0addr
	jmp EXT_INT0

.org OVF4addr
	rjmp TIMER4_OVERFLOW

RESET:
	; Prepare timer4
	ldi temp1, 0b00000000			; Operation mode: normal
	sts TCCR4A, temp1
	ldi temp1, (1 << CS41)			; Prescaling: CLK/8
	sts TCCR4B, temp1
	ldi temp1, 1<<TOIE4				; Timer mask for overflow interrupt
	sts TIMSK4, temp1

	;Prepare port c
	ser temp1
	out DDRC, temp1

	; Set control registers for the external outputs (buttons)
	ldi temp1, (2 << ISC00)
	sts EICRA, temp1

	;Enable the push button interrupts
	in temp1, EIMSK
	ori temp1, (1 << INT0)
	out EIMSK, temp1

	; Clear dseg
	clr temp1
	sts pb0_button_pushed, temp1
	sts door_state_change_request, temp1

	; DEBUGGING - INITIALISE STATE OF LIFT THROUGH SOME VARIABLES
	ldi door_state, door_closed
	ldi temp1, true
	sts stop_at_floor, temp1

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
	DEBOUNCE_DELAY low(60000), high(60000), r26

	; check again if button really was pressed
	ldi temp2, 0b10000000
	in temp1, PIND7
	and temp1, temp2
	cpi temp1, 0
	breq EXT_INT0_END
	
	; Button is pressed - request to close doors
	ldi temp1, door_close_request
	sts door_state_change_request, temp1

	lds temp1, door_state_change_request
	out PORTC, temp1

	; restore all the registers
	EXT_INT0_END:
	pop temp1
	out SREG, temp1
	pop temp1
	pop temp2
	pop r26

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
	TIMER4_TRACK_PROGRESS:

		; Check for any door change requests
		; Check for door close request
		lds temp1, door_state_change_request
		cpi temp1, door_close_request

		; If there is a request to close the door, execute the quick-close procedure
		; NOTE: the door will ONLY quick-close if the door is opened
		breq QUICK_CLOSE_DOOR

		; Else continue with tracking the time 
		rjmp TIMER4_TRACK_TIME

		QUICK_CLOSE_DOOR:
			; Check whether the door is opening
			; ie progress < start + opening_duration
			lds temp1, stop_at_floor_progress
			cpi temp1, stop_at_floor_progress_start + stop_at_floor_opening_duration

			; If so, continue on with tracking the time/progress
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
				ldi temp1, stop_at_floor_total_duration - stop_at_floor_closing_duration
				sts stop_at_floor_progress, temp1

				; Reset timeCounter
				clr temp1
				sts timer4_TimeCounter, temp1

				; End interrupt
				rjmp TIMER4_EPILOGUE

			DOOR_ALREADY_CLOSING:
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
	pop temp1
	out SREG, temp1
	pop temp1
	reti

MAIN:
	out PORTC, door_state
	rjmp MAIN

HALT: 
	disable_all_interrupts

	lds temp1, door_state_change_request
	out PORTC, temp1

	rjmp HALT

; GENERAL FUNCTIONS ###########################
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
