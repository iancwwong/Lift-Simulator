; This file examines the floor_array component of the assignment
; - Constantly checks the floor_array and refreshses LCD accordingly
; - Records key presses, and checks the corr floor number in floor_array

.include "m2560def.inc"

; DEFINES #########################################################

.def row = r20					; current row number
.def col = r21					; current column number
.def rowmask = r22				; mask for current row during scan
.def colmask = r23				; mask for current column during scan
.def temp1 = r24
.def temp2 = r25

; CONSTANTS #######################################################

; Used for the keypad
.equ PORTLDIR = 0xF0			; PD7-4: output, PD3-0: input
.equ INITCOLMASK = 0xEF			; Scan from leftmost column
.equ INITROWMASK = 0x01			; Scan from topmost row
.equ OUTPUTMASK = 0x0F		

; MACROS ##########################################################

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

	; Used for recording keypad presses reliably
	oldCol: .byte 1
	oldRow: .byte 1

; CODE SEGMENT ####################################################
.cseg

.org 0
	rjmp RESET

RESET:

	; Initialise stack
	ldi temp1, high(RAMEND)
	out SPH, temp1
	ldi temp1, low(RAMEND)
	out SPL, temp1

	; Prepare the keypad ports
	; - Prepare Port L - output through PD7-4, read through PD3-0
	ldi temp1, PORTLDIR
	sts DDRL, temp1

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

	; Display the floor numbers
	do_lcd_data 0, '0'
	do_lcd_data 0, '1'
	do_lcd_data 0, '2'
	do_lcd_data 0, '3'
	do_lcd_data 0, '4'
	do_lcd_data 0, '5'
	do_lcd_data 0, '6'
	do_lcd_data 0, '7'
	do_lcd_data 0, '8'
	do_lcd_data 0, '9'


	; Clear all variables
	clr col
	clr row

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

	sei
	rjmp MAIN

MAIN:
	; If refresh 
	; Loop through the floor_array, inspecting for which ones are set
	; Initiate X pointer
	ldi XH, high(floor_array)
	ldi XL, low(floor_array)

	; Initiate loop counter
	ldi temp2, 0

	; Prepare cursor position
	do_lcd_command 0, 0b10101000 	; set cursor to 1st position on bottom line

	INSPECT_FLOOR_ARRAY_LOOP:
		cpi temp2, 10
		breq END_INSPECT_FLOOR_ARRAY_LOOP

		; Check whether current floor in array is set
		ld temp1, X+
		cpi temp1, 0
			; If set
			brne CASE_FLOOR_IS_SET
			
			; Not set: print an '0' at the current cursor
			do_lcd_data 0, '0'
			rjmp REPEAT_INSPECT_FLOOR_ARRAY_LOOP

		CASE_FLOOR_IS_SET:
			; Print an 'X' at the current cursor
			do_lcd_data 0, 'X'

		REPEAT_INSPECT_FLOOR_ARRAY_LOOP:
		inc temp2
		rjmp INSPECT_FLOOR_ARRAY_LOOP

	END_INSPECT_FLOOR_ARRAY_LOOP:

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
	
HALT: rjmp halt

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
				ldi temp1, 1
				st X, temp1
				rjmp CONVERT_END
			CLEAR_FLOORN_IN_ARRAY:
				ldi temp1, 0
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
