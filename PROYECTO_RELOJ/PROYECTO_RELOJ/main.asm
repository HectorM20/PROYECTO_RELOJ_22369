//***************************************************************
//Universidad del Valle de Guatemala 
//IE2023: Programación de Microcontroladores
//Autor: Héctor Alejandro Martínez Guerra
//Hardware: ATMEGA328P
//Minutos (Unidades y Decenas)
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
.def HOUR_UNI_COUNTER = R21				;Unidades de horas (0-9)
.def HOUR_DEC_COUNTER = R22				;Decenas de horas (0-2) Formato 24 horas
/*Valor tiempo real == 975 | Valor simulado rápido == 97 (10 minutos reales serán 1 minuto) | Valor muy rápido == 1*/
.equ OCR1A_VALUE = 1
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
    LDI     R16, 0b00001111				;Configuración de PORTB:PB1 (Decenas) y PB0 (segundos) para multiplexar
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
	LDI		HOUR_UNI_COUNTER, 0
	LDI		HOUR_DEC_COUNTER, 0

	;Configurar el timer1 en modo CTC para generar una interrupción cada 1s
	LDI		R16, (1<<WGM12) | (1<<CS12) | (1<<CS10)	;Configurar modo CTC (WGM12 se encuentra en TCCR1B) y Prescaler 1024
    STS     TCCR1B, R16
	;Cargar el valor de 975 (3D0) en OCR1A (registro de 16 bits: OCR1AH y OCR1AL)
	LDI		R16, HIGH(OCR1A_VALUE)		;Parte alta
	STS		OCR1AH, R16
	LDI		R16, LOW(OCR1A_VALUE)		;Parte baja
	STS		OCR1AL, R16
	LDI		R16, (1<<OCIE1A)			;Habilitar interrupción Compare Match A de timer1
	STS		TIMSK1, R16

	;Configurar el timer0 en modo CTC para generar una interrupción cada 5ms (Multiplexación de displays)
	LDI		R16, (1<<WGM01)				;Configurar modo CTC
	OUT		TCCR0A, R16
	LDI		R16, (1<<CS02) | (1<<CS00)	;Prescaler 1024
	OUT     TCCR0B, R16
	LDI		R16, 4						;OCR0A = 9
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

	;Si MIN_UNI_COUNTER es 10, se debe reiniciar y aumentar la decena de minutos
	LDI		MIN_UNI_COUNTER, 0			;Reiniciar unidades de minutos
	INC		MIN_DEC_COUNTER				;Incrementar decenas de minutos
	CPI		MIN_DEC_COUNTER, 6			;Comparar si las decenas han llegado a 6 (60 min)
	BRLO	END_ISR						;Si no es así, continúa 

	;Si las decenas alcanzaron 6, se reinician ambos contadores
	LDI		MIN_DEC_COUNTER, 0
	;LDI	MIN_UNI_COUNTER, 0

	;Horas
	INC		HOUR_UNI_COUNTER			;Incrementar contador de unidades de horas
	CPI		HOUR_DEC_COUNTER, 2			;Comparar si las decenas son 2 (20, 21, 22 o 23)
	BRNE	NORMAL_HOUR					;Si no es 2, esta entre 0 y 1, salta salta a la rutina para conteo normal
	CPI		HOUR_UNI_COUNTER, 4			;Comparar si las unidades de horas ha llegado a 4 (24 horas)
	BRLO	END_ISR						;Si es menor a 4, continua el conteo 	
	;Si llega a 4 (24 horas), los contadores de horas se reinician
	LDI		HOUR_UNI_COUNTER, 0
	LDI		HOUR_DEC_COUNTER, 0
	RJMP	END_ISR

NORMAL_HOUR:
	CPI		HOUR_UNI_COUNTER, 10		;Comparar si las unidades de horas han llegado a 10
	BRLO	END_ISR						;Si es menor, continua el conteo
	;Si llega a 10, reiniciar el contador e incrementar el contador de decenas
	LDI		HOUR_UNI_COUNTER, 0			;Reiniciar contador
	INC		HOUR_DEC_COUNTER			;Incrementar contador de decenas de horas
	;(Comprobación para no sobrepasar las 23 horas)
	CPI		HOUR_DEC_COUNTER, 3
	BRLO	END_ISR						;si las decenas de horas es menor a 3, el conteo continúa
	;Si se llega a las 23 horas, se reinician contadores
	LDI		HOUR_DEC_COUNTER, 0
	LDI		HOUR_UNI_COUNTER, 0

END_ISR:
    RETI

TIMER0_COMPA_ISR:
	;Guardar registros, para manipularlos sin perder su valor actual
	PUSH	R16
	PUSH	R17
	PUSH	R18

	;La variable MULTIPLEX_STATE ciclará entre 0 y 3, dependiendo del valor, encenderá el display indicado
	;Caso0: Unidades de minutos (display activado en PB0)
	;Caso1: Decenas de minutos (display activado en PB1)
	;Caso2: Unidades de horas (display activado en PB2)
	;Caso3: Decenas de horas (display activado en PB3)
	CPI		MULTIPLEX_STATE, 0
	BRNE	NOT_CASE0						;Si MULTIPLEX_STATE no es 0 salta al siguiente caso

	;Si MULTIPLEX_STATE = 0 (Caso 0), Mostrar unidades de minutos PB0
CASE0:
	;Cargar la dirección base de SEG_TABLE en el puntero Z
	LDI		ZH, HIGH(SEG_TABLE<<1)
    LDI		ZL, LOW(SEG_TABLE<<1)
    ;Sumar el valor de MIN_UNI_COUNTER para obtener el desplazamiento del dígito o valor
    ADD		ZL, MIN_UNI_COUNTER		;Desplazar segun el estado
    LPM		R16, Z					;Carga el valor en R16
    OUT		PORTD, R16				;Mostrar valor en puerto D
	;limpiar bits inferiores (PB0 a PB3) y encender PB0 (0x01), unidades de minutos
	IN		R17, PORTB				;Leer el estado del puerto
	LDI		R18, 0xF0				;0xF0 = 1111 0000, deja intactos los bits superiores
	AND		R17, R18
	LDI		R18, 0x01				;0x01 = 0000 0001, para activar PB0
	OR		R17, R18
	OUT		PORTB, R17
	RJMP	UPDATE_STATE

NOT_CASE0:
	CPI		MULTIPLEX_STATE, 1			;Compara el si MULTIPLEX_STATE es 1
	BRNE	NOT_CASE1					;Si MULTIPLEX_STATE no es uno, salta al siguiente caso
	;Si MULTIPLEX_STATE = 1 (Caso 1), mostrar decenas de minutos PB1
CASE1:
	;Cargar la dirección base de SEG_TABLE en el puntero Z
	LDI		ZH, HIGH(SEG_TABLE<<1)
    LDI		ZL, LOW(SEG_TABLE<<1)
    ;Sumar el valor de MIN_UNI_COUNTER para obtener el desplazamiento del dígito o valor
    ADD		ZL, MIN_DEC_COUNTER		;Desplazar segun el estado
    LPM		R16, Z					;Carga el valor en R16
    OUT		PORTD, R16				;Mostrar valor en puerto D
	;limpiar bits inferiores (PB0 a PB3) y encender PB1 (0x02), decenas de minutos
	IN		R17, PORTB				;Leer el estado del puerto
	LDI		R18, 0xF0				;0xF0 = 1111 0000, deja intactos los bits superiores
	AND		R17, R18
	LDI		R18, 0x02				;0x02 = 0000 0010, para activar PB1
	OR		R17, R18
	OUT		PORTB, R17
	RJMP	UPDATE_STATE

NOT_CASE1:
	CPI		MULTIPLEX_STATE, 2		;Comparar si MULTIPLEX_STATE es 2
	BRNE	NOT_CASE2				;Si MULTIPLEX_STATE no es 2, salta al siguiente caso
	;Si MULTIPLEX_STATE = 2 (Caso 2), mostrar unidades de horas PB2
CASE2:
	;Cargar la dirección base de SEG_TABLE en el puntero Z
	LDI		ZH, HIGH(SEG_TABLE<<1)
    LDI		ZL, LOW(SEG_TABLE<<1)
    ;Sumar el valor de HOUR_UNI_COUNTER para obtener el desplazamiento del dígito o valor
    ADD		ZL, HOUR_UNI_COUNTER	;Desplazar segun el estado
    LPM		R16, Z					;Carga el valor en R16
    OUT		PORTD, R16				;Mostrar valor en puerto D
	;limpiar bits inferiores (PB0 a PB3) y encender PB2 (0x04), unidades de horas
	IN		R17, PORTB				;Leer el estado del puerto
	LDI		R18, 0xF0				;0xF0 = 1111 0000, deja intactos los bits superiores
	AND		R17, R18
	LDI		R18, 0x04				;0x04 para activar PB2
	OR		R17, R18
	OUT		PORTB, R17
	RJMP	UPDATE_STATE

NOT_CASE2: 
	;No es necesario comparar
	;MULTIPLEX_STATE = 3 (Caso 3), mostrar decenas de horas PB3
CASE3:
	;Cargar la dirección base de SEG_TABLE en el puntero Z
	LDI		ZH, HIGH(SEG_TABLE<<1)
    LDI		ZL, LOW(SEG_TABLE<<1)
    ;Sumar el valor de HOUR_DEC_COUNTER para obtener el desplazamiento del dígito o valor
    ADD		ZL, HOUR_DEC_COUNTER	;Desplazar segun el estado
    LPM		R16, Z					;Carga el valor en R16
    OUT		PORTD, R16				;Mostrar valor en puerto D
	;limpiar bits inferiores (PB0 a PB3) y encender PB3 (0x08), decenas de horas
	IN		R17, PORTB				;Leer el estado del puerto
	LDI		R18, 0xF0				;0xF0 = 1111 0000, deja intactos los bits superiores
	AND		R17, R18
	LDI		R18, 0x08				;0x08 para activar PB3
	OR		R17, R18
	OUT		PORTB, R17

UPDATE_STATE:
	INC		MULTIPLEX_STATE			;Incrementa MULTIPLEX_STATE para determinar el caso y encender el display correspondiente
	CPI		MULTIPLEX_STATE, 4		;Comparar con 4, esto hace que el la variable se mantenga en 0-3
	BRLO	SKIP_RESET				;Si es menor, salta a SKIP_RESET, significa que no han pasado todos los casos
	LDI		MULTIPLEX_STATE, 0		;Pero si MULTIPLEX_STATE llega a 4, este se reinicia para que el ciclo de multiplexación se repita

SKIP_RESET:
	;Después de usar los registros, recuperar el valor de los registros
	POP		R18
	POP		R17
	POP		R16
    RETI							;Retorna de la interrupción.



