.include "m2560def.inc"

.def temp = r17
.def door_state = r19

.equ motor_speed_low = OCR3BL
.equ motor_speed_high = OCR3BH
.equ full_motor_speed = 0xFF
.equ no_motor_speed = 0

; Describe door state
.equ door_closed = 0
.equ door_opening = 1
.equ door_opened = 2
.equ door_closing = 3

; Procedure to reset 2-byte values in program memory
; Parameter @0 is the memory address
; ** THIS PROCEDURE IS KINDLY PROVIDED THROUGH LECTURE NOTES WEEK5A SLIDE 25
.macro clear
	ldi YL, low(@0)
	ldi YH, high(@0)
	clr temp
	st Y+, temp
	st Y, temp
.endmacro

.cseg

jmp RESET

; Timer0 overflow interrupt procedure
.org OVF5addr
	jmp TIMER5_OVERFLOW

RESET:

	; Set PE2 to be output
	ser temp
	out DDRE, temp

	;Prepare PWM through timer3
	; Initialise motor speed (ie Setting the value of PWM for OC3B to 0)
	ldi temp, no_motor_speed
	sts motor_speed_low, temp
	sts motor_speed_high, temp

	; Set Fast PWM Mode 
	ldi temp, (1 << WGM30) | (1 << WGM31)

	; Set timer3 to be cleared on compare match
	ori temp, (1 << COM3B1)
	sts TCCR3A, temp

	; No prescaling
	ldi temp, (1 << CS30)
	sts TCCR3B, temp

	; PREPARE TIMER 5

	; Prepare the Timer Counter Control Register (both A and B)
	ldi temp, 0b00000000
	sts TCCR5A, temp

	ldi temp, 0b00000010			; Prescaling: 00000010
	sts TCCR5B, temp

	; Prepare the timer masks for interrupt through Timer0
	ldi temp, 1<<TOIE5
	sts TIMSK5, temp

	sei
	rjmp MAIN

TIMER5_OVERFLOW:

	; Prologue - save conflict registers
	TIMER5_PROLOGUE: 
	push temp
	in temp, SREG
	push temp

	; Function body
	; Check whether the lift door is opening or closing
	; If so, set motor to full speed
	cpi door_state, door_closing
	breq SET_MOTOR
	cpi door_state, door_opening
	breq SET_MOTOR

	; else turn off the motor
	ldi temp, no_motor_speed
	sts motor_speed_low, temp
	sts motor_speed_high, temp
	rjmp TIMER5_EPILOGUE

	SET_MOTOR:
		ldi temp, full_motor_speed
		sts motor_speed_low, temp
		sts motor_speed_high, temp

	; Epilogue - restore all registers
	TIMER5_EPILOGUE:
	pop temp
	out SREG, temp
	pop temp
	reti

MAIN:
	ldi door_state, door_opening

HALT: rjmp HALT
