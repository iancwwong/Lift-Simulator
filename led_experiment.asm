; This program tests the strobe LED lights

.include "m2560def.inc"

.def LED_ouput= r16
.def temp = r17

.cseg

rjmp RESET

RESET:
	; set port K to be output
	ser temp
	out DDRB, temp

	; set PORT C to be LED output
	out DDRC, temp
	rjmp MAIN

MAIN:
	ldi temp, 0b00001100
	out PORTB, temp
