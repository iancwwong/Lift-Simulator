; This experiments turning on the backlight of the LCD
; through the pin PE5 on Port E

.include "m2560def.inc"

.def temp = r16

.cseg

RESET:
	;Set PORTE as output
	ser temp
	out DDRE, temp
	

MAIN:
	;Turn on backlight
	ldi temp, 0b00001000
	out PORTE, temp

HALT: rjmp HALT
