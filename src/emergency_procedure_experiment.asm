; This file contains the code for which the emergency procedure will execute


.include "m2560def.inc"

; DEFINES ########
.def temp1 = r24
.def temp2 = r25

.def row = r20					; current row number
.def col = r21					; current column number
.def rowmask = r22				; mask for current row during scan
.def colmask = r23				; mask for current column during scan

; CONSTANTS ######
.equ tenth_second_overflows_16bit = 3
.equ LED_emergency_alarm_pattern = 0b00001100

; Describe the location of the emergency key on the keypad
; ie the '*' symbol
.equ emergency_key_col = 0
.equ emergency_key_row = 3

; Used for scanning the keypad
.equ PORTLDIR = 0xF0			; PD7-4: output, PD3-0: input
.equ INITCOLMASK = 0xEF			; Scan from leftmost column
.equ INITROWMASK = 0x01			; Scan from topmost row
.equ OUTPUTMASK = 0x0F

.equ EMERGCOLMASK = 0xEF		; Special initialisation for emergency key (leftmost column)
.equ EMERGROWMASK = 0x08		; Special initialisation for emergency key (lowest row)

.equ true = 1
.equ false = 0


; MACROS #######
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
	; Used to count number of timer overflows
	timer1_TimeCounter: .byte 1

	; Used to indicate the emergency mode is requested
	emergency_flag: .byte 1

	; Used to indicate the emergency alarm is triggered
	emergency_alarm: .byte 1

	; Used to store the LED output in case of emergency alarm
	LED_emergency_alarm_output: .byte 1

	; Used for recording keypad presses reliably
	oldCol: .byte 1
	oldRow: .byte 1

.cseg

.org 0
	rjmp RESET

; Timer overflow interrupt procedure
.org OVF1addr
	rjmp TIMER1_OVERFLOW

RESET:
	; Initialise stack
	ldi temp1, high(RAMEND)
	out SPH, temp1
	ldi temp1, low(RAMEND)
	out SPL, temp1

	; Prepare timer 1
	ldi temp1, 0b00000000			; Operation mode: normal
	sts TCCR1A, temp1
	ldi temp1, (1 << CS11)			; Prescaling: CLK/8
	sts TCCR1B, temp1
	ldi temp1, 1<<TOIE1				; Timer mask for overflow interrupt
	sts TIMSK1, temp1

	; set port B (strobe LED's) and port C (8-bit LED) to be output
	ser temp1
	out DDRB, temp1
	out DDRC, temp1

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

	; Clear LCD display
	reset_lcd_display

	; Clear dseg
	clr temp1
	sts timer1_TimeCounter, temp1
	sts LED_emergency_alarm_output, temp1

	; Initialise both oldCol and oldRow to be some number greater than 3
	ldi temp1, 9
	sts oldCol, temp1
	sts oldRow, temp1

	; DEBUGGING - initialise variables
	ldi temp1, true
	sts emergency_alarm, temp1
	sts emergency_mode, temp1

	rjmp MAIN	

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

	; If not set, exit interrupt
	brne TIMER1_EPILOGUE

	; Else start keeping track of time
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

MAIN:
	lcd_display_emergency_message

	lds temp1, emergency_flag
	out PORTC, temp1

	; Start polling for emergency key
	MAIN_START_POLL_EMERGENCY_KEY:

	rjmp POLL_EMERGENCY_KEY

	MAIN_END_POLL_EMERGENCY_KEY:

	rjmp MAIN


EMERGENCY_MODE:
	
; DEBUGGING
HALT:

	disable_all_interrupts
	ser temp1
	out PORTC, temp1

	rjmp HALT

; GENERAL FUNCTIONS ########

; Poll the emergency key, ie the '*' symbol 
; located in column 0, row 3
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
	rjmp END_POLL_EMERGENCY_KEY

	EXIT_EMERGENCY_MODE:
	ldi temp1, false
	sts emergency_flag, temp1
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
