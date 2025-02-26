//***************************************************************
//Universidad del Valle de Guatemala 
//IE2023: Programación de Microcontroladores
//Autor: Héctor Alejandro Martínez Guerra
//Hardware: ATMEGA328P
//POST_LAB3
//***************************************************************

//***************************************************************
//ENCABEZADO
//***************************************************************
.include "M328PDEF.inc"
;Variables a usar
.def SEC_COUNTER = R17					;Contador de segundos
.def MIN_UNI_COUNTER = R18				;Unidades de minutos (0-9)
.def MIN_DEC_COUNTER = R19				;Decenas de minutos (0-5)
.def MULTIPLEX_STATE = R20				;Multiplexación de unidades y decenas de minutos

/*Valor tiempo real == 975 | Valor simulado rápido == 97 (10 minutos reales serán 1 minuto) | Valor muy rápido == 1*/
.equ OCR1A_VALUE = 976
;Tabla de Vectores
.org 0x0000
    RJMP SET_UP							;Vector de Reset
;Vector de interrupción para Timer1 Compare Match A
.org 0x0016
    RJMP TIMER1_COMPA_ISR
;Vector de interrupción para Timer0 Compare Match A
.org 0x001C
	RJMP TIMER0_COMPA_ISR

;Configuración de la pila
    LDI     R16, LOW(RAMEND)
    OUT     SPL, R16
    LDI     R16, HIGH(RAMEND)
    OUT     SPH, R16

;TABLA 7 SEG (Catodo comun)
SEG_TABLE:.db 0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F,	0x6F ;(0-9)

SET_UP:
    ;Configurar Prescaler: F_CPU = 1 MHz
    LDI     R16, (1<<CLKPCE)
    STS     CLKPR, R16					;Habilitar cambio de prescaler
    LDI     R16, 0b00000100				;Configurar Prescaler a 16 F_cpu = 1MHz 
    STS     CLKPR, R16

	;Configuración de E/S para contador 
    LDI     R16, 0b00000011				;Configuración de PORTB:PB1 (Decenas) y PB0 (segundos) para multiplexar
    OUT     DDRB, R16

	;Configuración de E/S para contador hexadecimal (display)
	LDI		R16, 0xFF					;Configura PORTD como salida
	OUT		DDRD, R16

    ;Deshabilitar el módulo serial (apaga otros LEDs del Arduino)
    LDI     R16, 0x00
    STS     UCSR0A, R16
    STS     UCSR0B, R16
    STS     UCSR0C, R16

	;Inicializar contadores en 0 
	LDI		SEC_COUNTER, 0
	LDI		MIN_UNI_COUNTER, 0
	LDI		MIN_DEC_COUNTER, 0
	LDI		MULTIPLEX_STATE, 0

	;Configurar el timer1 en modo CTC para generar una interrupción cada 1s
	LDI		R16, (1<<WGM12) | (1<<CS12) | (1<<CS10)	;Configurar modo CTC (WGM12 se encuentra en TCCR1B) y Prescaler 1024
    STS     TCCR1B, R16
	;Cargar el valor de 975 (3D0) en OCR1A (registro de 16 bits: OCR1AH y OCR1AL)
	/*Para que un minuto real se vea cada 6 segundos (10 minutos = 1 minuto) OCR1A = 97 = 0x0061
	LDI		R16, 0x00					;Parte alta
	STS		OCR1AH, R16
	LDI		R16, 0x61
	STS		OCR1AL, R16
	*/
	/* Parte de minutos reales */
	LDI		R16, HIGH(OCR1A_VALUE)		;Parte alta
	STS		OCR1AH, R16
	LDI		R16, LOW(OCR1A_VALUE)					;Parte baja
	STS		OCR1AL, R16
	LDI		R16, (1<<OCIE1A)			;Habilitar interrupción Compare Match A de timer1
	STS		TIMSK1, R16

	;Configurar el timer0 en modo CTC para generar una interrupción cada 10ms (Multiplexación de displays)
	LDI		R16, (1<<WGM01)				;Configurar modo CTC
	OUT		TCCR0A, R16
	LDI		R16, (1<<CS00) | (1<<CS01)	;Prescaler 64
	OUT     TCCR0B, R16
	LDI		R16, 155					;OCR0A = 155
	OUT		OCR0A, R16

	LDI		R16, (1<<OCIE0A)			;Habilitar interrupción Compare Match A de timer0
	STS		TIMSK0, R16

    SEI									;Habilitar interrupciones globales

MAIN_LOOP:
    RJMP MAIN_LOOP						;Bucle Principal


TIMER1_COMPA_ISR:
    INC		SEC_COUNTER					;Increemntar segundos
	CPI		SEC_COUNTER, 60				;comparar. Han pasado 60 segundos?
    BRNE END_ISR						;Si no ha llegado a 60, salta a END_ISR
	;Si SEC_COUNTER = 60, ha pasado un minuto
	LDI		SEC_COUNTER, 0				;Se completo un minuto, reiniciar el contador de segundos
	;Incrementar unidades de minutos
	INC		MIN_UNI_COUNTER				;Incremntar unidades de minutos
	CPI		MIN_UNI_COUNTER, 10			;comparar si las unidades han llegado a 10
	BRLO	END_ISR						;Si no es así, continúa 

	;Si MIN_UNI_COUNTER es 10, se debe reiniciar y aumentar la decena
	LDI		MIN_UNI_COUNTER, 0			;Reiniciar unidades de minutos
	INC		MIN_DEC_COUNTER				;Incrementar decenas de minutos
	CPI		MIN_DEC_COUNTER, 6			;Comparar si las decenas han llegado a 6 (60 min)
	BRLO	END_ISR						;Si no es así, continúa 

	;Si las decenas alcanzaron 6, se reinician ambos contadores
	LDI		MIN_DEC_COUNTER, 0
	LDI		MIN_UNI_COUNTER, 0
END_ISR:
    RETI

TIMER0_COMPA_ISR:
	;Guardar registros, para manipularlos sin perder su valor actual
	PUSH	R17
	PUSH	R18

	CPI		MULTIPLEX_STATE, 0			;Comparar. Es 0?
	BRNE	SHOW_MIN_DEC				;Si no es 0 (es 1), salta a mostrar decenas
	;Si MULTIPLEX_STATE = 0
SHOW_MIN_UNI:
	;Cargar la dirección base de SEG_TABLE en el puntero Z
	LDI		ZH, HIGH(SEG_TABLE<<1)
    LDI		ZL, LOW(SEG_TABLE<<1)
    ;Sumar el valor de MIN_UNI_COUNTER para obtener el desplazamiento del dígito o valor
    ADD		ZL, MIN_UNI_COUNTER		;Desplazar segun el estado de SEC_COUNTER (0-9)
    LPM		R16, Z					;Carga el valor en R16
    OUT		PORTD, R16				;Mostrar valor en puerto D

	;Activar PB0 (unidades de minutos) y desactivar PB1 (decenas de minutos)
	IN		R17, PORTB				;Leer el estado del puerto
	LDI		R18, 0xFC				;0xFC = 1111 1100, para limpiar PB0 y PB1
	AND		R17, R18
	LDI		R18, 0x01				;0x01 = 0000 0001, para activar PB0
	OR		R17, R18
	OUT		PORTB, R17
	RJMP	TOGGLE_MUXTLIPLEX_MIN

SHOW_MIN_DEC:
	;Cargar la dirección base de SEG_TABLE en el puntero Z
	LDI		ZH, HIGH(SEG_TABLE<<1)
    LDI		ZL, LOW(SEG_TABLE<<1)
    ;Sumar el valor de MIN_UNI_COUNTER para obtener el desplazamiento del dígito o valor
    ADD		ZL, MIN_DEC_COUNTER		;Desplazar segun el estado de SEC_COUNTER (0-9)
    LPM		R16, Z					;Carga el valor en R16
    OUT		PORTD, R16				;Mostrar valor en puerto D

	;Desactivar PB0 (unidades de minutos) y activar PB1 (decenas de minutos)
	IN		R17, PORTB				;Leer el estado del puerto
	LDI		R18, 0xFC				;0xFC = 1111 1100, para limpiar PB0 y PB1
	AND		R17, R18
	LDI		R18, 0x02				;0x01 = 0000 0001, para activar PB0
	OR		R17, R18
	OUT		PORTB, R17

TOGGLE_MUXTLIPLEX_MIN:
	LDI		R16, 0x01				;Carga valor 0000 0001 en R16
	EOR		MULTIPLEX_STATE, R16	;Alterna el estado de MULTIPLEX_STATE

	;Después de usar los registros, recuperar el valor de los registros
	POP		R18
	POP		R17
	RETI


