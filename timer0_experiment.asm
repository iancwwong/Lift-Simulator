; This program tests whether Timer0 works when it "simulates" the lift's movement
; The floor is constantly displayed using the LCD
.include "m2560def.inc"

; DEFINES #########################################################

.def current_floor = r16
.def final_dest = r17
.def lift_direction = r18
.def temp1 = r24
.def temp2 = r25

; CONSTANTS #######################################################

; Time keeping values
.equ one_second_overflows = 7812

; Describe lift direction
.equ dir_up = 1
.equ dir_stop = 0
.equ dir_down = -1

; Boolean constants
.equ true = 1
.equ false = 0		

; MACROS ##########################################################

; Display the current floor number using the LCD
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

	timer0_TimeCounter: .byte 2				; Used to count the number of timer0 overflows

; CODE SEGMENT ####################################################
.cseg

.org 0
	rjmp RESET

; Timer0 overflow interrupt procedure
.org OVF0addr
	rjmp TIMER0_OVERFLOW

RESET:

	; Initialise stack
	ldi temp1, high(RAMEND)
	out SPH, temp1
	ldi temp1, low(RAMEND)
	out SPL, temp1

	; Prepare the F and A ports for LCD Data and LCD Control
	ser temp1
	out DDRF, temp1
	out DDRA, temp1
	clr temp1
	out PORTF, temp1
	out PORTA, temp1

	; Prepare the LCD
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
	clr current_floor

	; Clear all data in dseg
	clear timer0_TimeCounter
	clr temp1
	sts floor_changed, temp1

	; Set portc to be output
	ser temp1
	out DDRC, temp1

	; Prepare timer 0
	ldi temp1, 0b00000000			; Operation mode: normal
	out TCCR0A, temp1
	ldi temp1, 0b00000010			; Prescaling: 00000010
	out TCCR0B, temp1
	ldi temp1, 1<<TOIE0				; Timer mask for overflow interrupt
	sts TIMSK0, temp1

	; Debugging - initialise state of lift
	ldi current_floor, 5
	ldi final_dest, 1
	ldi lift_direction, dir_down
	ldi temp1, false
	sts floor_changed, temp1

	sei
	rjmp MAIN

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

		;if TimeCounter value is 7812, then one second has occurred
		cpi temp1, low(one_second_overflows)
		ldi r26, high(one_second_overflows)
		cpc temp2, r26
		brne TIMER0_ONE_SECOND_NOT_ELAPSED

		; if one second has occurred, the lift has gone up one floor
		TIMER0_ONE_SECOND_ELAPSED:

			; Request an update in floor
			ldi r26, true
			sts floor_changed, r26

			; Reset the time counter
			clear timer0_TimeCounter
			rjmp TIMER0_EPILOGUE

		; else if one second has not elapsed, simply store the incremented
		; counter for the time into TimeCounter, and end interrupt
		TIMER0_ONE_SECOND_NOT_ELAPSED:
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

MAIN:
	; Update curr_floor
	rcall update_curr_floor

	; Display the current floor
	lcd_display_current_floor

	; Check if arrived at destination floor
	cp current_floor, final_dest

	; If arrived, stop lift
	breq STOP_LIFT

	; Else proceed
	rjmp MAIN

	STOP_LIFT:
		ldi lift_direction, dir_stop
		rjmp MAIN

HALT:
	rjmp HALT


; FUNCTIONS ############

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
