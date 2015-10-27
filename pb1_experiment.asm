; Experiment with pb1 button

.include "m2560def.inc"

.def temp1 = r24
.def temp2 = r25

.equ true = 1
.equ false = 0

.equ door_close_request = 1
.equ door_open_request = 2

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

.dseg
	pb0_button_pushed: .byte 1
	pb1_button_pushed: .byte 1
	door_state_change_request: .byte 1

	dummy_value: .byte 1

.cseg

.org 0
	rjmp RESET

; 	Interrupt procedure when PB0 button was pushed
.org INT1addr
	jmp EXT_INT1


RESET:

	;Prepare port c
	ser temp1
	out DDRC, temp1

	; Set control registers for the external outputs (buttons)
	;ldi temp1, (0 << ISC10)				; low level throws interrupt
	;sts EICRA, temp1

	;Enable the push button interrupts
	;in temp1, EIMSK
	;ori temp1, (1 << INT1)
	;out EIMSK, temp1

	clr temp1
	sts door_state_change_request, temp1
	sts dummy_value, temp1

	sei
	rjmp MAIN

; PB1 button was pressed - request to open door
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

	ldi temp1, 0
	sts dummy_value, temp1

	; restore all the registers
	EXT_INT1_END:
	pop temp1
	out SREG, temp1
	pop temp1
	pop temp2
	pop r26

	reti


MAIN:

	lds temp1, dummy_value
	inc temp1
	sts dummy_value, temp1
	out PORTC, temp1
	rjmp MAIN

HALT: 

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
