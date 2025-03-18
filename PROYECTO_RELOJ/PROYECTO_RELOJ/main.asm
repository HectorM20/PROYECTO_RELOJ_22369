//***************************************************************
//Universidad del Valle de Guatemala 
//IE2023: Programación de Microcontroladores
//Autor: Héctor Alejandro Martínez Guerra
//Hardware: ATMEGA328P
//Minutos y Horas + led intermedio (Uso de RAM) + modo 0 y 1 (hora) + modo 2 y 3 (fecha) + modo alarma
//***************************************************************

//***************************************************************
//ENCABEZADO
//***************************************************************
.dseg
;0x0100 (la RAM de datos empieza en esa dirección)
.org 0x0100
SEC_COUNTER:		.byte 1		;Contador de segundos
MIN_UNI_COUNTER:	.byte 1		;Unidades de minutos (0-9)
MIN_DEC_COUNTER:	.byte 1		;Decenas de minutos (0-5)
MULTIPLEX_STATE:	.byte 1		;Estado de multiplexación (0 a 3)
HOUR_UNI_COUNTER:	.byte 1		;Unidades de horas (0-9)
HOUR_DEC_COUNTER:	.byte 1		;Decenas de horas (0-2)
LED_BLINK_COUNTER:	.byte 1		;Contador para el parpadeo del LED intermedio
OLD_PINC:			.byte 1		;Para guardar el estado anterior de PINC
CURRENT_MODE:		.byte 1		;0: MODO_HORA, 1: MODO_CONF_HORA, 2: MODO_FECHA, 3: MODO_CONF_FECHA, 4: MODO_ALARMA
BLINK_FLAG:			.byte 1		;Parpadeos de displays. 0: dígitos apagados, 1: dígitos visibles
DAY_UNI_COUNTER:	.byte 1		;Unidades del día (0-9)
DAY_DEC_COUNTER:	.byte 1		;Decenas del día (0-3)
MONTH_UNI_COUNTER:	.byte 1		;Unidades del mes (0-9), pero solo se usa 1-9
MONTH_DEC_COUNTER:	.byte 1		;Decenas de mes (0-1), para meses 10, 11 y 12
ALARM_HOUR_DEC:		.byte 1		;Decenas de hora de la alarma (0-2)
ALARM_HOUR_UNI:		.byte 1		;Unidades de hora de la alarma (0-9)
ALARM_MIN_DEC:		.byte 1		;Decenas de minuto de la alarma (0-5)
ALARM_MIN_UNI:		.byte 1		;Unidades de minuto de la alarma (0-9)

ALARM_TRIGGERED:	.byte 1		;0 = no sonando, 1 = sonando

OLD_PINC_DEBOUNCE:	.byte 1		;Anti rebote
DEBOUNCE_COUNTER:	.byte 1
;***************************************************************
; Sección de código
;***************************************************************
.cseg
.include "M328PDEF.inc"

;Valor tiempo real == 976 | Valor simulado rápido == 97 (10 minutos reales serán 1 minuto) | Valor muy rápido == 1
.equ OCR1A_VALUE = 1

;***************************************************************
;Tabla de Vectores
;***************************************************************
;Vector de Reset
.org 0x0000
    RJMP SET_UP							
;Vector de interrupción para Timer1 Compare Match A
.org 0x0016
    RJMP TIMER1_COMPA_ISR
;Vector de interrupción para Timer0 Compare Match A
.org 0x001C
	RJMP TIMER0_COMPA_ISR
;Vector de interrupción para Timer2 Compare Match A
.org 0x000E
	RJMP TIMER2_COMPA_ISR
;Vector de interrupción para PCINT1 (PORTC: pines PCINT8 a PCINT14)
.org 0x0008
    RJMP PCINT1_ISR

;***************************************************************
;TABLA 7 SEG (Catodo comun)
;***************************************************************
.org 0x0020								
;Dirección en la que estan guardados los valores, esto evita que se sobrescriba en alguna otra dirección
SEG_TABLE:.db 0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F,	0x6F ;(0-9)
;***************************************************************
;MAX_DAY_TABLE: días máximos para cada mes 
;(ene:31, feb:28, mar:31, abr:30, may:31, jun:30, jul:31, ago:31, sept:30, oct:31, nov:30, dic:31)
;***************************************************************
.org 0x0030
MAX_DAY_TABLE: .db 32, 28, 32, 31, 32, 31, 32, 32, 31, 32, 31, 32

;Configuración de la pila
    LDI     R16, LOW(RAMEND)
    OUT     SPL, R16
    LDI     R16, HIGH(RAMEND)
    OUT     SPH, R16

SET_UP:
;Configurar Prescaler: F_CPU = 1 MHz
    LDI     R16, (1<<CLKPCE)
    STS     CLKPR, R16					;Habilitar cambio de prescaler
    LDI     R16, 0b00000100				;Configurar Prescaler a 16 F_cpu = 1MHz 
    STS     CLKPR, R16
;Configuración de E/S  
;Configuración de PORTB: PB0 (unidades min), PB1 (decenas min), PB2 (unidades hora), PB3 (decenas hora), PB4 LED INTERMEDIO, PB5 Alarma
    LDI     R16, 0b00111111				
    OUT     DDRB, R16
;Configuración de PORTD: (display) PD0-PD6 (A-G) 
	LDI		R16, 0xFF					;Configura PORTD como salida
	OUT		DDRD, R16
;Configuración de PORTC: entradas: PC0 (modo), PC1 (Decremento2), PC2 (Incremento2), PC3 (Decremento1), PC4 (Incremento1). salida: PC5 (Led Indicador)
	LDI		R16, 0b00100000
	OUT		DDRC, R16
;Activar pull-ups internos en PC0-PC4
    LDI     R16, 0b00011111					
    OUT     PORTC, R16
;Deshabilitar el módulo serial (apaga otros LEDs del Arduino)
    LDI     R16, 0x00
    STS     UCSR0A, R16
    STS     UCSR0B, R16
    STS     UCSR0C, R16

;Inicializar variables en la RAM
    LDI     R16, 0
    STS     SEC_COUNTER, R16
    STS     MIN_UNI_COUNTER, R16
    STS     MIN_DEC_COUNTER, R16
    STS     MULTIPLEX_STATE, R16
    STS     HOUR_UNI_COUNTER, R16
    STS     HOUR_DEC_COUNTER, R16
    STS     LED_BLINK_COUNTER, R16
	STS		BLINK_FLAG, R16
	STS		CURRENT_MODE, R16
    STS		ALARM_HOUR_DEC, R16
    STS		ALARM_HOUR_UNI, R16
    STS		ALARM_MIN_DEC, R16
    STS		ALARM_MIN_UNI, R16
    STS		ALARM_TRIGGERED, R16
;Inicializar Fecha en 01/01
	LDI		R16, 1
	STS		DAY_UNI_COUNTER, R16		;Día = 1
	LDI     R16, 0
	STS		DAY_DEC_COUNTER, R16		;decenas = 0
	LDI		R16, 1					
	STS		MONTH_UNI_COUNTER, R16		;Mes = 1
	LDI     R16, 0
	STS		MONTH_DEC_COUNTER, R16

;Inicializar OLD_PINC con el estado actual de PINC (esperamos 0x1F)
    IN		R16, PINC
    STS		OLD_PINC, R16

;***************************************************************
;Configuración de Timers
;***************************************************************
;Configurar el timer1 en modo CTC para generar una interrupción cada 1s
	LDI		R16, (1<<WGM12) | (1<<CS12) | (1<<CS10)	;Configurar modo CTC (WGM12 se encuentra en TCCR1B) y Prescaler 1024
    STS     TCCR1B, R16
;Cargar el valor de 976 en OCR1A (registro de 16 bits: OCR1AH y OCR1AL)
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
	LDI		R16, 4						;OCR0A = 4
	OUT		OCR0A, R16

	LDI		R16, (1<<OCIE0A)			;Habilitar interrupción Compare Match A de timer0
	STS		TIMSK0, R16

;Configurar el timer2 en modo CTC para generar una interrupción cada 10ms
	LDI		R16, (1<<WGM21)				;Modo CTC
	STS		TCCR2A, R16
	LDI		R16, (1<<CS22)				;Prescaler 64
	STS		TCCR2B, R16
	LDI		R16, 156					;OCR2A = 156
	STS		OCR2A, R16
	LDI		R16, (1<<OCIE2A)			;Habilitar interrupción Compare Match A de timer2
	STS		TIMSK2, R16

;***************************************************************
;Configurar interrupciones por cambio (Pin Change Interrupt) para PORTC:
;***************************************************************
;Habilitar el grupo de interrupciones PCINT1 (PCINT8 a PCINT14)
    LDI     R16, (1<<PCIE1)
    STS     PCICR, R16
;Habilitar la interrupción PC0_PC4, 0: PCINT8, 1: PCINT9, 2: PCINT10, 3: PCINT11, 4: PCINT12
	LDI		R16, (1<<PCINT8) | (1<<PCINT9) | (1<<PCINT10) | (1<<PCINT11) | (1<<PCINT12)
	STS		PCMSK1, R16

    SEI									;Habilitar interrupciones globales
	
MAIN_LOOP:	
;0 = MODO_HORA
;1 = MODO_CONF_HORA
;2 = MODO_FECHA
;3 = MODO_CONF_FECHA
;4 = MODO_ALARMA
;Leerá constantemente el estado (modo) 
	LDS		R16, CURRENT_MODE			;Cargar CURRENT_MODE desde la RAM
	CPI		R16, 0						;Compara si CURRENT_MODE es 0
	BREQ	MODE_HORA					;Si CURRENT_MODE = 0, salta a MODE_HORA
	CPI		R16, 1						;Compara si CURRENT_MODE es 1
	BREQ	MODE_CONF_HORA				;Si CURRENT_MODE = 1, salta a MODE_CONF_HORA
	CPI		R16, 2						;Compara si CURRENT_MODE es 2
	BREQ	MODE_FECHA					;Si CURRENT_MODE = 2, salta a MODE_FECHA
	CPI		R16, 3						;Compara si CURRENT_MODE es 3
	BREQ	MODE_CONF_FECHA				;Si CURRENT_MODE = 3, salta a MODE_CONF_FECHA
	CPI		R16, 4						;Compara si CURRENT_MODE es 4
	BREQ	MODE_ALARMA					;Si CURRENT_MODE = 4, salta a MODE_ALARMA
    RJMP	MAIN_LOOP					;Bucle Principal

;***************************************************************
;MODO_HORA: El reloj avanza normalmente (con Timer1)
;***************************************************************
;Verifica si se encuentra en este modo, Si CURRENT_MODE es 0 se matiene en este modo. 
MODE_HORA: 
MODE_HORA_LOOP: 
	LDS		R16, CURRENT_MODE
	CPI		R16, 0 
	BRNE	EXIT_MODE_HORA
	RJMP	MODE_HORA_LOOP
;Si CURRENT_MODE no es 0, hubo un cambio de modo y regresa al MAIN_LOOP para verificar el modo
EXIT_MODE_HORA:
	RJMP	MAIN_LOOP

;***************************************************************
;MODO_CONF_HORA: La cuenta se congela; los dígitos parpadean (por Timer2)
;***************************************************************
;Verifica si se encuentra en este modo, Si CURRENT_MODE es 1 se matiene en este modo. 
MODE_CONF_HORA:
MODE_CONF_HORA_LOOP:
	LDS		R16, CURRENT_MODE
	CPI		R16, 1
	BRNE	EXIT_MODE_CONF_HORA
	RJMP	MODE_CONF_HORA_LOOP
;Si CURRENT_MODE no es 1, hubo un cambio de modo y regresa al MAIN_LOOP para verificar el modo
EXIT_MODE_CONF_HORA:
	RJMP	MAIN_LOOP 

;***************************************************************
;MODO_FECHA: Muestra fecha en formato dd/mm (fecha continúa)
;***************************************************************
MODE_FECHA:
MODE_FECHA_LOOP:
	LDS		R16, CURRENT_MODE
	CPI		R16, 2
	BRNE	EXIT_MODE_FECHA
	RJMP	MODE_FECHA_LOOP
EXIT_MODE_FECHA:
	RJMP	MAIN_LOOP

;***************************************************************
;MODO_CONF_FECHA: Configuración de fecha (fecha congelada)
;***************************************************************
MODE_CONF_FECHA:
	LDS		R16, CURRENT_MODE
	CPI		R16, 3
	BRNE	EXIT_MODE_CONF_FECHA
	RJMP	MODE_CONF_FECHA
EXIT_MODE_CONF_FECHA:
	RJMP	MAIN_LOOP
;***************************************************************
;MODO_ALARMA
;***************************************************************
MODE_ALARMA:
MODE_ALARMA_LOOP:
    LDS  R16, CURRENT_MODE
    CPI  R16, 4
    BRNE EXIT_MODE_ALARMA
    RJMP MODE_ALARMA_LOOP
EXIT_MODE_ALARMA:
    RJMP MAIN_LOOP

;TIMER1
;Modos 1 y 3, el reloj se congela. 
;Modos 0 y 2, el reloj continua normalmente
TIMER1_COMPA_ISR:
    LDS  R17, CURRENT_MODE
    CPI  R17, 0
    BREQ CONTINUE_TIME_UPDATE
    CPI  R17, 1
    BREQ TIMER1_EXIT
    CPI  R17, 2
    BREQ CONTINUE_TIME_UPDATE
    CPI  R17, 3
    BREQ TIMER1_EXIT
    RJMP TIMER1_EXIT
CONTINUE_TIME_UPDATE:
	LDS		R16, SEC_COUNTER			;Cargar SEC_COUNTER desde la RAM
    INC		R16							;Incremntar segundos
	CPI		R16, 60						;comparar. Han pasado 60 segundos?
    BRNE	UPDATE_TIME_SKIP			;Si no ha llegado a 60, salta a UPDATE_TIME_SKIP (continua contando y guarda valor)
;Si SEC_COUNTER = 60, ha pasado un minuto
	LDI		R16, 0						;Se completo un minuto, reiniciar el contador de segundos
    STS		SEC_COUNTER, R16			;Guarda 0 en SEC_COUNTER, cuando se reinicia
	RCALL	UPDATE_TIME					;Actualiza minutos y horas
UPDATE_TIME_SKIP:
	STS		SEC_COUNTER, R16			;Guarda el valor de SEC_COUNTER si no llega a 60
	RETI
CHECK_ALARM:
;Primero, si ya está sonando (ALARM_TRIGGERED=1), no hagas nada:
    LDS		R20, ALARM_TRIGGERED
    CPI		R20, 1
    BREQ	CHECK_ALARM_EXIT

;Leer la hora actual (HOUR_DEC_COUNTER/HOUR_UNI_COUNTER)
    LDS		R16, HOUR_DEC_COUNTER
    LDS		R17, HOUR_UNI_COUNTER
;Leer la hora de la alarma
    LDS		R18, ALARM_HOUR_DEC
    LDS		R19, ALARM_HOUR_UNI
    CP		R16, R18
    BRNE	CHECK_ALARM_EXIT
    CP		R17, R19
    BRNE	CHECK_ALARM_EXIT

;Comparar los minutos
    LDS		R16, MIN_DEC_COUNTER
    LDS		R17, MIN_UNI_COUNTER
    LDS		R18, ALARM_MIN_DEC
    LDS		R19, ALARM_MIN_UNI
    CP		R16, R18
    BRNE	CHECK_ALARM_EXIT
    CP		R17, R19
    BRNE	CHECK_ALARM_EXIT

;Si hora y minutos coinciden, verificar que alarma != 00:00
;(Si ALARM_HOUR_DEC:UNI y ALARM_MIN_DEC:UNI == 0 => no sonar)
    LDS		R16, ALARM_HOUR_DEC
    LDS		R17, ALARM_HOUR_UNI
    OR		R16, R17
    BRNE	CHECK_MIN
;Si hour = 0, checa minutos:
    LDS		R16, ALARM_MIN_DEC
    LDS		R17, ALARM_MIN_UNI
    OR		R16, R17
    BREQ	CHECK_ALARM_EXIT				;=> 00:00 => No suena
CHECK_MIN:
;Activar buzzer
    LDI		R20, 1
    STS		ALARM_TRIGGERED, R20
    SBI		PORTB, 5						;PB5=1 => suena

CHECK_ALARM_EXIT:
    RET
TIMER1_EXIT: 
	RETI


;UPDATE_TIME: Subrutina para la actualización de horas y minutos
UPDATE_TIME:
;Incrementar unidades de minutos
    LDS     R16, MIN_UNI_COUNTER			;Cargar MIN_UNI_COUNTER desde la RAM
    INC     R16								;Incrementar unidades de minutos
    STS     MIN_UNI_COUNTER, R16			;Guardar el nuevo valor en la RAM
    CPI     R16, 10
    BRLO    CHECK_ALARM_AND_EXIT			;Si MIN_UNI_COUNTER < 10, no hay carry, saltar a comprobar alarma

;Si MIN_UNI_COUNTER llegó a 10, se reinicia y se incrementa el contador de decenas
    LDI     R16, 0
    STS     MIN_UNI_COUNTER, R16
    LDS     R16, MIN_DEC_COUNTER			;Cargar MIN_DEC_COUNTER desde la RAM
    INC     R16								;Incrementar decenas de minutos
    STS     MIN_DEC_COUNTER, R16			;Guardar el nuevo valor en la RAM
    CPI     R16, 6
    BRLO    CHECK_ALARM_AND_EXIT			;Si las decenas son menores que 6, saltar a comprobar alarma
;Si las decenas alcanzan 6, se reinician ambos contadores (60 minutos)
    LDI     R16, 0
    STS     MIN_DEC_COUNTER, R16

;Actualizar horas (este bloque se ejecuta al producirse el carry de minutos)
    LDS     R16, HOUR_UNI_COUNTER			;Cargar HOUR_UNI_COUNTER desde la RAM
    INC     R16								;Incrementar contador de unidades de horas
    STS     HOUR_UNI_COUNTER, R16			;Guardar el nuevo valor en la RAM
    LDS     R17, HOUR_DEC_COUNTER			;Cargar HOUR_DEC_COUNTER desde la RAM
    CPI     R17, 2
    BRNE    NORMAL_HOUR_UPDATE				;Si HOUR_DEC_COUNTER != 2, saltar a actualizar horas sin rollover
    CPI     R16, 4
    BRLO    CHECK_ALARM_AND_EXIT			;Si la hora aún es válida, saltar a comprobar alarma
;Si se llega a las 24 horas, reiniciar horas
    LDI     R16, 0
    STS     HOUR_UNI_COUNTER, R16
    LDI     R17, 0
    STS     HOUR_DEC_COUNTER, R17
    LDS     R18, CURRENT_MODE
    CPI     R18, 2
    BRNE    CHECK_ALARM_AND_EXIT			;Solo en modo fecha se actualiza la fecha automáticamente
    RCALL   UPDATE_DATE
    RJMP    CHECK_ALARM_AND_EXIT

NORMAL_HOUR_UPDATE:
    CPI     R16, 10
    BRLO    CHECK_ALARM_AND_EXIT			;Si HOUR_UNI_COUNTER < 10, no hay carry en hora
    LDI     R16, 0
    STS     HOUR_UNI_COUNTER, R16
    INC     R17								;Incrementar decenas de horas
    STS     HOUR_DEC_COUNTER, R17
    CPI     R17, 3
    BRLO    CHECK_ALARM_AND_EXIT
    LDI     R17, 0
    STS     HOUR_DEC_COUNTER, R17

CHECK_ALARM_AND_EXIT:
    RCALL   CHECK_ALARM						;Comprobar si la hora actual coincide con la alarma
    RET

;UPDATE_DATE
UPDATE_DATE:
    LDS		R20, DAY_DEC_COUNTER
    LDS		R21, DAY_UNI_COUNTER
    RCALL	INCR_DAY
    LDS		R16, DAY_DEC_COUNTER
    LDS		R17, DAY_UNI_COUNTER
    CPI		R16, 0							;Comparar decenas del nuevo día con 0
    BRNE	UPDATE_DATE_EXIT				;Si no es 0, el día no se ha reiniciado; salir.
    CPI		R17, 1							;Comparar unidades del nuevo día con 1
    BRNE	UPDATE_DATE_EXIT				;Si no es 1, el día no es 01; salir.
    CPI		R20, 0							;Comparar antiguas decenas del día con 0
    BRNE	ROLLOVER_MONTH					;Si R20 no es 0, el día anterior no era 01; incrementar mes
    CPI		R21, 1							;Comparar antiguas unidades del día con 1
    BRNE	ROLLOVER_MONTH					;Si R21 no es 1, el día anterior no era 01; incrementar mes
    RJMP	UPDATE_DATE_EXIT
ROLLOVER_MONTH:
    RCALL	INCR_MONTH
UPDATE_DATE_EXIT:
    RET

;TIMER0_COMPA_ISR: Multiplexa los 4 dígitos (cada ~5ms)
;Si en modo configuración (CURRENT_MODE=1) y BLINK_FLAG=0, no muestra dígitos.
TIMER0_COMPA_ISR:
;Cargar CURRENT_MODE en R18
    LDS     R18, CURRENT_MODE
	CPI     R18, 2
	BRLO    SHORT_HOUR_MODES
	RJMP    CONTINUE_CODE
SHORT_HOUR_MODES:
	RJMP HOUR_MODES
CONTINUE_CODE:
    CPI     R18, 4
    BREQ    ALARM_MULTIPLEX					;Modo alarma
    CPI     R18, 3
    BREQ    DATE_CONFIG_CHECK				;Modo configuración de fecha: verificar parpadeo
;Si CURRENT_MODE no es 3, debe ser 2 (modo fecha normal)
    RJMP    DATE_NORMAL_DISPLAY

DATE_CONFIG_CHECK:
    LDS     R19, BLINK_FLAG					;Cargar BLINK_FLAG
    CPI     R19, 0
    BRNE    DATE_NORMAL_DISPLAY				;Si BLINK_FLAG != 0, mostrar el dígito normalmente
;Si BLINK_FLAG == 0, se quiere apagar el dígito (parpadeo)
    LDI     R16, 0x00
    OUT     PORTD, R16						;Apagar los segmentos (envía 0 a PORTD)
;Ahora, desactivar el dígito en PORTB:
    IN      R17, PORTB						;Leer PORTB
    LDI     R18, 0xF0						;Dejar intactos los bits superiores
    AND     R17, R18						;Esto limpia el nibble inferior (los bits de selección)
    OUT     PORTB, R17						;Apagar el dígito
;Actualizar MULTIPLEX_STATE para pasar al siguiente dígito
    LDS     R16, MULTIPLEX_STATE
    INC     R16
    CPI     R16, 4
    BRLO    DATE_SKIP_RESET1
    LDI     R16, 0
DATE_SKIP_RESET1:
    STS     MULTIPLEX_STATE, R16
    RETI


; ALARM_MULTIPLEX: Multiplexado de displays para el modo alarma
;Estado 0: Unidades de minuto de la alarma (display en PB0)
;Estado 1: Decenas de minuto de la alarma (display en PB1)
;Estado 2: Unidades de hora de la alarma (display en PB2)
;Estado 3: Decenas de hora de la alarma (display en PB3)
ALARM_MULTIPLEX:
    LDS     R16, MULTIPLEX_STATE			;Cargar el estado actual de multiplexado
    CPI     R16, 0
    BREQ    ALARM_MIN_UNI_DISPLAY
    CPI     R16, 1
    BREQ    ALARM_MIN_DEC_DISPLAY
    CPI     R16, 2
    BREQ    ALARM_HOUR_UNI_DISPLAY
    RJMP    ALARM_HOUR_DEC_DISPLAY

ALARM_MIN_UNI_DISPLAY:
    RCALL   ALARM_DISPLAY_MIN_UNI			;Rutina que muestra ALARM_MIN_UNI en display correspondiente
    RJMP    ALARM_UPDATE_MULTIPLEX

ALARM_MIN_DEC_DISPLAY:
    RCALL   ALARM_DISPLAY_MIN_DEC
    RJMP    ALARM_UPDATE_MULTIPLEX

ALARM_HOUR_UNI_DISPLAY:
    RCALL   ALARM_DISPLAY_HOUR_UNI
    RJMP    ALARM_UPDATE_MULTIPLEX

ALARM_HOUR_DEC_DISPLAY:
    RCALL   ALARM_DISPLAY_HOUR_DEC

ALARM_UPDATE_MULTIPLEX:
    LDS     R16, MULTIPLEX_STATE
    INC     R16								;Incrementar estado para el siguiente dígito
    CPI     R16, 4
    BRLO    ALARM_MULTIPLEX_SKIP_RESET
    LDI     R16, 0							;Si llegó a 4, reiniciar a 0
ALARM_MULTIPLEX_SKIP_RESET:
    STS     MULTIPLEX_STATE, R16
    RETI


;TIMER0_COMPA_ISR (multiplexado de fecha)
DATE_NORMAL_DISPLAY:
    ; Modo fecha (CURRENT_MODE==2) o modo configuración de fecha (CURRENT_MODE==3)
    LDS     R16, MULTIPLEX_STATE
    CPI     R16, 0
    BREQ    CASE0_DATE_DISPLAY				;Posición 0: Unidad del mes
    CPI     R16, 1
    BREQ    CASE1_DATE_DISPLAY				;Posición 1: Decena del mes
    CPI     R16, 2
    BREQ    CASE2_DATE_DISPLAY				;Posición 2: Unidad del día
    RJMP    CASE3_DATE_DISPLAY				;Posición 3: Decena del día

CASE0_DATE_DISPLAY:
    RCALL   DISPLAY_MONTH_UNI
    RJMP    DATE_UPDATE_MULTIPLEX
CASE1_DATE_DISPLAY:
    RCALL   DISPLAY_MONTH_DEC
    RJMP    DATE_UPDATE_MULTIPLEX
CASE2_DATE_DISPLAY:
    RCALL   DISPLAY_DAY_UNI
    RJMP    DATE_UPDATE_MULTIPLEX
CASE3_DATE_DISPLAY:
    RCALL   DISPLAY_DAY_DEC

DATE_UPDATE_MULTIPLEX:
    LDS     R16, MULTIPLEX_STATE
    INC     R16
    CPI     R16, 4
    BRLO    DATE_SKIP_RESET2
    LDI     R16, 0
DATE_SKIP_RESET2:
    STS     MULTIPLEX_STATE, R16
    RETI

;TIMER0_COMPA_ISR (multiplexado de hora)
HOUR_MODES:
    LDS     R18, CURRENT_MODE
    CPI     R18, 1
    BREQ    HOUR_CONFIG_PROCESS
    RJMP    NORMAL_MULTIPLEX

HOUR_CONFIG_PROCESS:
    LDS     R19, BLINK_FLAG
    CPI     R19, 0
    BRNE    NORMAL_MULTIPLEX
    LDI     R16, 0x00
    OUT     PORTD, R16
    LDS     R16, MULTIPLEX_STATE
    INC     R16
    CPI     R16, 4
    BRLO    SKIP_RESET_HOUR
    LDI     R16, 0
SKIP_RESET_HOUR:
    STS     MULTIPLEX_STATE, R16
    RETI

NORMAL_MULTIPLEX:
    LDS     R16, MULTIPLEX_STATE
    CPI     R16, 0
    BREQ    CASE0_DISPLAY					;Unidades de minutos (PB0)
    CPI     R16, 1
    BREQ    CASE1_DISPLAY					;Decenas de minutos (PB1)
    CPI     R16, 2
    BREQ    CASE2_DISPLAY					;Unidades de horas (PB2)
    RJMP    CASE3_DISPLAY					;Decenas de horas (PB3)

CASE0_DISPLAY:
    RCALL   DISPLAY_MIN_UNI
    RJMP    UPDATE_MULTIPLEX
CASE1_DISPLAY:
    RCALL   DISPLAY_MIN_DEC
    RJMP    UPDATE_MULTIPLEX
CASE2_DISPLAY:
    RCALL   DISPLAY_HOUR_UNI
    RJMP    UPDATE_MULTIPLEX
CASE3_DISPLAY:
    RCALL   DISPLAY_HOUR_DEC

UPDATE_MULTIPLEX:
    LDS     R16, MULTIPLEX_STATE
    INC     R16
    CPI     R16, 4
    BRLO    SKIP_RESET2
    LDI     R16, 0
SKIP_RESET2:
    STS     MULTIPLEX_STATE, R16
    RETI

;***************************************************************
; SUBRUTINAS DE DISPLAY: Muestran un dígito usando SEG_TABLE para hora Y MAX_TABLE_DAY para fecha
;***************************************************************
;Caso0 HORA
DISPLAY_MIN_UNI:
    LDS		R16, MIN_UNI_COUNTER		;Carga MIN_UNI_COUNTER desde la RAM
	;Cargar la dirección base de SEG_TABLE en el puntero Z
	LDI		ZH, HIGH(SEG_TABLE<<1)
    LDI		ZL, LOW(SEG_TABLE<<1)
    ;Sumar el valor de MIN_UNI_COUNTER para obtener el desplazamiento del dígito o valor
    ADD		ZL, R16			;Desplazar segun el estado
    LPM		R16, Z						;Carga el valor en R16
    OUT		PORTD, R16					;Mostrar valor en puerto D
	;limpiar bits inferiores (PB0 a PB3) y encender PB0 (0x01), unidades de minutos
	IN		R17, PORTB					;Leer el estado del puerto
	LDI		R18, 0xF0					;0xF0 = 1111 0000, deja intactos los bits superiores
	AND		R17, R18
	LDI		R18, 0x01					;0x01 = 0000 0001, para activar PB0
	OR		R17, R18
	OUT		PORTB, R17
	RET

;Caso1 HORA
DISPLAY_MIN_DEC:
    LDS		R16, MIN_DEC_COUNTER		;Carga MIN_DEC_COUNTER desde la RAM
	;Cargar la dirección base de SEG_TABLE en el puntero Z
	LDI		ZH, HIGH(SEG_TABLE<<1)
    LDI		ZL, LOW(SEG_TABLE<<1)
    ;Sumar el valor de MIN_UNI_COUNTER para obtener el desplazamiento del dígito o valor
    ADD		ZL, R16			;Desplazar segun el estado
    LPM		R16, Z						;Carga el valor en R16
    OUT		PORTD, R16					;Mostrar valor en puerto D
	;limpiar bits inferiores (PB0 a PB3) y encender PB1 (0x02), decenas de minutos
	IN		R17, PORTB					;Leer el estado del puerto
	LDI		R18, 0xF0					;0xF0 = 1111 0000, deja intactos los bits superiores
	AND		R17, R18
	LDI		R18, 0x02					;0x02 = 0000 0010, para activar PB1
	OR		R17, R18
	OUT		PORTB, R17
	RET

;Caso2 HORA
DISPLAY_HOUR_UNI:
    LDS		R16, HOUR_UNI_COUNTER		;Carga HOUR_UNI_COUNTER desde la RAM
	;Cargar la dirección base de SEG_TABLE en el puntero Z
	LDI		ZH, HIGH(SEG_TABLE<<1)
    LDI		ZL, LOW(SEG_TABLE<<1)
    ;Sumar el valor de HOUR_UNI_COUNTER para obtener el desplazamiento del dígito o valor
    ADD		ZL, R16						;Desplazar segun el estado
    LPM		R16, Z						;Carga el valor en R16
    OUT		PORTD, R16					;Mostrar valor en puerto D
	;limpiar bits inferiores (PB0 a PB3) y encender PB2 (0x04), unidades de horas
	IN		R17, PORTB					;Leer el estado del puerto
	LDI		R18, 0xF0					;0xF0 = 1111 0000, deja intactos los bits superiores
	AND		R17, R18
	LDI		R18, 0x04					;0x04 para activar PB2
	OR		R17, R18
	OUT		PORTB, R17
	RET

;Caso3 HORA
DISPLAY_HOUR_DEC:
    LDS		R16, HOUR_DEC_COUNTER		;Carga HOUR_DEC_COUNTER desde la RAM
	;Cargar la dirección base de SEG_TABLE en el puntero Z
	LDI		ZH, HIGH(SEG_TABLE<<1)
    LDI		ZL, LOW(SEG_TABLE<<1)
    ;Sumar el valor de HOUR_DEC_COUNTER para obtener el desplazamiento del dígito o valor
    ADD		ZL, R16						;Desplazar segun el estado
    LPM		R16, Z						;Carga el valor en R16
    OUT		PORTD, R16					;Mostrar valor en puerto D
	;limpiar bits inferiores (PB0 a PB3) y encender PB3 (0x08), decenas de horas
	IN		R17, PORTB					;Leer el estado del puerto
	LDI		R18, 0xF0					;0xF0 = 1111 0000, deja intactos los bits superiores
	AND		R17, R18
	LDI		R18, 0x08					;0x08 para activar PB3
	OR		R17, R18
	OUT		PORTB, R17
	RET
;FECHA
DISPLAY_DAY_UNI:
    LDS		R16, DAY_UNI_COUNTER		;Carga MIN_UNI_COUNTER desde la RAM
	;Cargar la dirección base de SEG_TABLE en el puntero Z
	LDI		ZH, HIGH(SEG_TABLE<<1)
    LDI		ZL, LOW(SEG_TABLE<<1)
    ;Sumar el valor de MIN_UNI_COUNTER para obtener el desplazamiento del dígito o valor
    ADD		ZL, R16			;Desplazar segun el estado
    LPM		R16, Z						;Carga el valor en R16
    OUT		PORTD, R16					;Mostrar valor en puerto D
	;limpiar bits inferiores (PB0 a PB3) y encender PB0 (0x01), unidades de minutos
	IN		R17, PORTB					;Leer el estado del puerto
	LDI		R18, 0xF0					;0xF0 = 1111 0000, deja intactos los bits superiores
	AND		R17, R18
	;LDI		R18, 0x01				;0x01 = 0000 0001, para activar PB0
	LDI		R18, 0x04					;0x04 para activar PB2
	OR		R17, R18
	OUT		PORTB, R17
	RET
DISPLAY_DAY_DEC:
    LDS		R16, DAY_DEC_COUNTER		;Carga MIN_DEC_COUNTER desde la RAM
	;Cargar la dirección base de SEG_TABLE en el puntero Z
	LDI		ZH, HIGH(SEG_TABLE<<1)
    LDI		ZL, LOW(SEG_TABLE<<1)
    ;Sumar el valor de MIN_UNI_COUNTER para obtener el desplazamiento del dígito o valor
    ADD		ZL, R16						;Desplazar segun el estado
    LPM		R16, Z						;Carga el valor en R16
    OUT		PORTD, R16					;Mostrar valor en puerto D
	;limpiar bits inferiores (PB0 a PB3) y encender PB1 (0x02), decenas de minutos
	IN		R17, PORTB					;Leer el estado del puerto
	LDI		R18, 0xF0					;0xF0 = 1111 0000, deja intactos los bits superiores
	AND		R17, R18
	;LDI		R18, 0x02				;0x02 = 0000 0010, para activar PB1
	LDI		R18, 0x08					;0x08 para activar PB3
	OR		R17, R18
	OUT		PORTB, R17
	RET
DISPLAY_MONTH_UNI:
    LDS		R16, MONTH_UNI_COUNTER		;Carga HOUR_UNI_COUNTER desde la RAM
	;Cargar la dirección base de SEG_TABLE en el puntero Z
	LDI		ZH, HIGH(SEG_TABLE<<1)
    LDI		ZL, LOW(SEG_TABLE<<1)
    ;Sumar el valor de HOUR_UNI_COUNTER para obtener el desplazamiento del dígito o valor
    ADD		ZL, R16						;Desplazar segun el estado
    LPM		R16, Z						;Carga el valor en R16
    OUT		PORTD, R16					;Mostrar valor en puerto D
	;limpiar bits inferiores (PB0 a PB3) y encender PB2 (0x04), unidades de horas
	IN		R17, PORTB					;Leer el estado del puerto
	LDI		R18, 0xF0					;0xF0 = 1111 0000, deja intactos los bits superiores
	AND		R17, R18
	;LDI		R18, 0x04				;0x04 para activar PB2
	LDI		R18, 0x01					;0x01 = 0000 0001, para activar PB0
	OR		R17, R18
	OUT		PORTB, R17
	RET
DISPLAY_MONTH_DEC:
    LDS		R16, MONTH_DEC_COUNTER		;Carga HOUR_DEC_COUNTER desde la RAM
	;Cargar la dirección base de SEG_TABLE en el puntero Z
	LDI		ZH, HIGH(SEG_TABLE<<1)
    LDI		ZL, LOW(SEG_TABLE<<1)
    ;Sumar el valor de HOUR_DEC_COUNTER para obtener el desplazamiento del dígito o valor
    ADD		ZL, R16						;Desplazar segun el estado
    LPM		R16, Z						;Carga el valor en R16
    OUT		PORTD, R16					;Mostrar valor en puerto D
	;limpiar bits inferiores (PB0 a PB3) y encender PB3 (0x08), decenas de horas
	IN		R17, PORTB					;Leer el estado del puerto
	LDI		R18, 0xF0					;0xF0 = 1111 0000, deja intactos los bits superiores
	AND		R17, R18
	;LDI		R18, 0x08				;0x08 para activar PB3
	LDI		R18, 0x02					;0x02 = 0000 0010, para activar PB1
	OR		R17, R18
	OUT		PORTB, R17
	RET
;ALARMA
ALARM_DISPLAY_HOUR_DEC:
    LDS     R16, ALARM_HOUR_DEC
    LDI     ZH, HIGH(SEG_TABLE<<1)
    LDI     ZL, LOW(SEG_TABLE<<1)
    ADD     ZL, R16
    LPM     R16, Z
    OUT     PORTD, R16
    IN      R17, PORTB					;Mismo display que HOUR_DEC (PB3)
    LDI     R18, 0xF0
    AND     R17, R18
    LDI     R18, 0x08
    OR      R17, R18
    OUT     PORTB, R17
    RET

ALARM_DISPLAY_HOUR_UNI:
    LDS     R16, ALARM_HOUR_UNI
    LDI     ZH, HIGH(SEG_TABLE<<1)
    LDI     ZL, LOW(SEG_TABLE<<1)
    ADD     ZL, R16
    LPM     R16, Z
    OUT     PORTD, R16
    IN      R17, PORTB					;Mismo display que HOUR_UNI (PB2)
    LDI     R18, 0xF0
    AND     R17, R18
    LDI     R18, 0x04
    OR      R17, R18
    OUT     PORTB, R17
    RET

ALARM_DISPLAY_MIN_DEC:
    LDS     R16, ALARM_MIN_DEC
    LDI     ZH, HIGH(SEG_TABLE<<1)
    LDI     ZL, LOW(SEG_TABLE<<1)
    ADD     ZL, R16
    LPM     R16, Z
    OUT     PORTD, R16
    IN      R17, PORTB					;Mismo display que MIN_DEC (PB1)
    LDI     R18, 0xF0
    AND     R17, R18
    LDI     R18, 0x02
    OR      R17, R18
    OUT     PORTB, R17
    RET

ALARM_DISPLAY_MIN_UNI:
    LDS     R16, ALARM_MIN_UNI
    LDI     ZH, HIGH(SEG_TABLE<<1)
    LDI     ZL, LOW(SEG_TABLE<<1)
    ADD     ZL, R16
    LPM     R16, Z
    OUT     PORTD, R16
    IN      R17, PORTB					;Mismo display que MIN_UNI (PB0)
    LDI     R18, 0xF0
    AND     R17, R18
    LDI     R18, 0x01
    OR      R17, R18
    OUT		PORTB, R17
    RET
;***************************************************************
;TIMER2_COMPA_ISR: Cada 10ms; cada 50 interrupciones (500ms) togglea BLINK_FLAG.
;***************************************************************
TIMER2_COMPA_ISR:
    IN		R20, PINC					;Leer estado actual de PORTC
    LDS		R21, OLD_PINC_DEBOUNCE		;Estado de debouncing almacenado
    CP		R20, R21					;Comparar
    BRNE	DEBOUNCE_RESET              ;Si no coinciden, reinicia contador
;Si coinciden:
    LDS		R22, DEBOUNCE_COUNTER       ;Cargar contador
    INC		R22                         ;Incrementar contador
    CPI		R22, 70						;7 veces (70ms)
    BRLO	DEBOUNCE_EXIT               ;Si no alcanza, salir
;Si alcanza el umbral, actualizar el estado estable
    STS		OLD_PINC, R20               ;Actualiza el estado final
    STS		DEBOUNCE_COUNTER, R22       ;Guarda el contador (o lo reseteas)
    RJMP	DEBOUNCE_EXIT

DEBOUNCE_RESET:
    LDI		R22, 0                      ;Reinicia el contador
    STS		DEBOUNCE_COUNTER, R22

DEBOUNCE_EXIT:
	LDS		R16, LED_BLINK_COUNTER		;Carga LED_BLINK_COUNTER desde la RAM
	INC		R16							;Incrementar el contador cada 10ms
	STS		LED_BLINK_COUNTER, R16		;Guarda el nuevo valor en la RAM
	CPI		R16, 50						;Comparar, si se han acumulado 50 interrupciones (10*50 = 500ms)
	BRLO	TIMER2_EXIT					;Si no, salta al final de la ISR
	LDI		R16, 0						;Reiniciar el contador
	STS		LED_BLINK_COUNTER, R16		;Guarda 0 en LED_BLINK_COUNTER
;Si han pasado 50 intrrupciones (500ms), se hace toggle en PB4 LED INTERMEDIO
	IN		R16, PORTB					;Se lee el estado del puerto
	LDI		R17, 0x10					;0x10 = 0001 0000, máscara para PB4
	EOR		R16, R17					;Toggle del bit PB4
	OUT		PORTB, R16					;Escribir de nuevo el estado 
	
;Toggle BLINK_FLAG parpadeo de displays
	LDS		R18, BLINK_FLAG				;Cargar el valor actual de BLINK_FLAG en R18
	CPI		R18, 0						;Comparar R18 con 0 (verificar si BLINK_FLAG es 0)
	BREQ	SET_BLINK_ONE				;Si BLINK_FLAG es 0, saltar a la etiqueta SET_BLINK_ONE
;Si BLINK_FLAG no es 0, se procede a ponerlo en 0:
	LDI		R18, 0
	STS		BLINK_FLAG, R18				;Almacenar 0 en BLINK_FLAG (apagando el flag)
	RJMP	TIMER2_EXIT					;Saltar a la salida de la ISR
SET_BLINK_ONE:
	LDI		R18, 1						;Cargar el valor 1 en R18
	STS		BLINK_FLAG, R18				;Almacenar 1 en BLINK_FLAG (encendiendo el flag)
PC5_TOGGLE_CHECK:
;Si el modo actual es 4 (modo alarma), togglear el LED indicador en PC5.
    LDS     R16, CURRENT_MODE
    CPI     R16, 4
    BRNE    TIMER2_EXIT
    IN      R16, PORTC                  ;Leer el valor actual de PORTC
    LDI     R17, 0x20                   ;Máscara para PC5 (bit5)
    EOR     R16, R17                    ;Toggle del bit 5
    OUT     PORTC, R16                  ;Escribir el nuevo valor en PORTC

TIMER2_EXIT:
	RETI

;PCINT1_ISR: Detección de flanco de bajada en PC0 para cambiar modo.
PCINT1_ISR:
;Guardar registros, para manipularlos sin perder su valor actual
	PUSH	R16
	PUSH	R17
	PUSH	R18
	PUSH	R20
	PUSH	R21

    IN		R20, PINC						;Leer el estado actual de PORTC en R20
    LDS		R21, OLD_PINC					;Leer el estado anterior (OLD_PINC) en R21

;Procesar PC0 (botón de modo)
;Verificar el flanco de bajada en PC0
    MOV		R16, R21						;OLD_PINC
    ANDI	R16, 0x01						;Extraer bit0 (PC0)
    CPI		R16, 0x01						;¿Estaba en 1? (no presionado)
    BRNE	PC0_SKIP						;Si no, salta
    MOV		R16, R20						;Estado actual de PINC
    ANDI	R16, 0x01						;Extraer bit0 (PC0)
    CPI		R16, 0x00						;¿Es 0? (botón presionado)
    BRNE	PC0_SKIP						;Si no es 0, no hay flanco de bajada

;Ahora, antes de cambiar el modo, se verifica si la alarma está sonando.
    LDS		R22, ALARM_TRIGGERED			;Cargar flag de alarma
    CPI		R22, 1                
    BREQ	ALARM_ACTIVE					;Si ALARM_TRIGGERED == 1, saltar a apagar la alarma

;Si la alarma NO está activa, se incrementa el modo:
NO_ALARM_ACTIVE:
    LDS		R16, CURRENT_MODE
    INC		R16								;Incrementar modo
    CPI		R16, 5							;Tenemos modos 0,1,2,3,4 => si llega a 5, se reinicia a 0
    BRLO	PC0_TOGGLE_OK
    LDI		R16, 0
PC0_TOGGLE_OK:
    STS		CURRENT_MODE, R16
;Actualizar LED indicador en PC5: 
    IN		R17, PORTC						;Leer PORTC
    LDS		R16, CURRENT_MODE
    CPI		R16, 2							;Si modo < 2, apagamos el LED (PC5)
    BRLO	LED_OFF
    LDI		R18, 0x20						;Bit5 en alto
    OR		R17, R18
    OUT		PORTC, R17
    RJMP	PC0_SKIP

ALARM_ACTIVE:
;La alarma está activa: se apaga sin cambiar de modo
    CBI		PORTB, 5						;Apaga el buzzer (PB5 = 0)
    LDI		R22, 0
    STS		ALARM_TRIGGERED, R22
    RJMP	PC0_SKIP
LED_OFF:
    LDI     R18, 0xDF						;0xDF = máscara para limpiar bit5
    AND     R17, R18
    OUT     PORTC, R17

PC0_SKIP:
    ;Procesar PC1 - PC4 solo en modo configuración
    LDS		R16, CURRENT_MODE
    CPI		R16, 1							;Comparar CURRENT_MODE con 1
    BREQ	PROCESS_HOUR_BUTTONS
    CPI		R16, 3
    BREQ	PROCESS_DATE_BUTTONS
	CPI		R16, 4
	BREQ	PROCESS_ALARM_BUTTONS_JUMP
    RJMP	UPDATE_OLD
PROCESS_ALARM_BUTTONS_JUMP:
	RJMP	PROCESS_ALARM_BUTTONS
	RJMP	UPDATE_OLD
PROCESS_HOUR_BUTTONS:
;Botón PC1 (bit1): Decrementar hora
    MOV		R16, R21
    ANDI	R16, 0x02						;Extraer el bit1 (PC1) de OLD_PINC
    CPI		R16, 0x02						;Comprobar que estaba en 1 (no presionado)
    BRNE	PC1_SKIP						;Si no, no se detecta transición en PC1
    MOV		R16, R20
    ANDI	R16, 0x02						;Extraer el bit1 (PC1)
    CPI		R16, 0x00						;Comprobar que es 0 (botón presionado)
    BRNE	PC1_SKIP						;Si no es 0, no hay flanco
    RCALL	DECR_HOUR						;Llamar a la subrutina para decrementar la hora
PC1_SKIP:
;Botón PC2 (bit2): Incrementar hora
    MOV		R16, R21
    ANDI	R16, 0x04						;Extraer el bit2 (PC2)
    CPI		R16, 0x04						;Comprobar que estaba en 1 (no presionado)
    BRNE	PC2_SKIP						;Si no, no se detecta transición en PC2
    MOV		R16, R20	
    ANDI	R16, 0x04						;Extraer el bit2 (PC2)
    CPI		R16, 0x00						;Comprobar que es 0 (presionado)
    BRNE	PC2_SKIP						;Si no, no hay flanco
    RCALL	INCR_HOUR						;Llamar a la subrutina para incrementar la hora
PC2_SKIP:
;Botón PC3 (bit3): Decrementar minutos
    MOV		R16, R21
    ANDI	R16, 0x08						;Extraer bit3 (PC3)
    CPI		R16, 0x08						;Comprobar que estaba en 1 (no presionado)
    BRNE	PC3_SKIP						;Si no, no se detecta transición en PC3
    MOV		R16, R20
    ANDI	R16, 0x08						;Extraer el bit3 (PC3)
    CPI		R16, 0x00						;Comprobar que es 0 (presionado)
    BRNE	PC3_SKIP						;Si no, no hay flanco
    RCALL	DECR_MIN						;Llamar a la subrutina para decrementar minutos
PC3_SKIP:
    ;Botón PC4 (bit4): Incrementar minutos
    MOV		R16, R21
    ANDI	R16, 0x10						;Extraer bit4 (PC4)
    CPI		R16, 0x10						;Comprobar que estaba en 1 (no presionado)
    BRNE	PC4_SKIP						;Si no, no se detecta transición en PC4
    MOV		R16, R20
    ANDI	R16, 0x10						;Extraer el bit4 (PC4)
    CPI		R16, 0x00						;Comprobar que es 0 (presionado)
    BRNE	PC4_SKIP						;Si no, no hay flanco
    RCALL	INCR_MIN						;Llamar a la subrutina para incrementar minutos
PC4_SKIP:
	RJMP  UPDATE_OLD

PROCESS_DATE_BUTTONS:
;Botón PC1 (bit1): Decrementar día
    MOV		R16, R21
    ANDI	R16, 0x02
    CPI		R16, 0x02
    BRNE	PC1_SKIP_DATE
    MOV		R16, R20
    ANDI	R16, 0x02
    CPI		R16, 0x00
    BRNE	PC1_SKIP_DATE
	RCALL	DECR_DAY
;Botón PC2 (bit2): Incrementar día
PC1_SKIP_DATE:
    MOV		R16, R21
    ANDI	R16, 0x04
    CPI		R16, 0x04
    BRNE	PC2_SKIP_DATE
    MOV		R16, R20
    ANDI	R16, 0x04
    CPI		R16, 0x00
    BRNE	PC2_SKIP_DATE
	RCALL	INCR_DAY
PC2_SKIP_DATE:
;Botón PC3 (bit3): Decrementar mes
    MOV		R16, R21
    ANDI	R16, 0x08
    CPI		R16, 0x08
    BRNE	PC3_SKIP_DATE
    MOV		R16, R20
    ANDI	R16, 0x08
    CPI		R16, 0x00
    BRNE	PC3_SKIP_DATE
	RCALL	DECR_MONTH
PC3_SKIP_DATE:
;Botón PC4 (bit4): Incrementar mes
    MOV		R16, R21
    ANDI	R16, 0x10
    CPI		R16, 0x10
    BRNE	PC4_SKIP_DATE
    MOV		R16, R20
    ANDI	R16, 0x10
    CPI		R16, 0x00
    BRNE	PC4_SKIP_DATE
	RCALL	INCR_MONTH
PC4_SKIP_DATE:
    RJMP	UPDATE_OLD

PROCESS_ALARM_BUTTONS:
;Botón PC1 (bit1): Decrementar HORA de la alarma
    MOV		R16, R21
    ANDI	R16, 0x02
    CPI		R16, 0x02
    BRNE	PC1_SKIP_ALARM
    MOV		R16, R20
    ANDI	R16, 0x02
    CPI		R16, 0x00
    BRNE	PC1_SKIP_ALARM
    RCALL	DECR_ALARM_HOUR
PC1_SKIP_ALARM:
;Botón PC2 (bit2): Incrementar HORA de la alarma
    MOV		R16, R21
    ANDI	R16, 0x04
    CPI		R16, 0x04
    BRNE	PC2_SKIP_ALARM
    MOV		R16, R20
    ANDI	R16, 0x04
    CPI		R16, 0x00
    BRNE	PC2_SKIP_ALARM
    RCALL	INCR_ALARM_HOUR
PC2_SKIP_ALARM:
;Botón PC3 (bit3): Decrementar MIN de la alarma
    MOV		R16, R21
    ANDI	R16, 0x08
    CPI		R16, 0x08
    BRNE	PC3_SKIP_ALARM
    MOV		R16, R20
    ANDI	R16, 0x08
    CPI		R16, 0x00
    BRNE	PC3_SKIP_ALARM
    RCALL	DECR_ALARM_MIN
PC3_SKIP_ALARM:
;Botón PC4 (bit4): Incrementar MIN de la alarma
    MOV		R16, R21
    ANDI	R16, 0x10
    CPI		R16, 0x10
    BRNE	PC4_SKIP_ALARM
    MOV		R16, R20
    ANDI	R16, 0x10
    CPI		R16, 0x00
    BRNE	PC4_SKIP_ALARM
    RCALL	INCR_ALARM_MIN
PC4_SKIP_ALARM:
    RJMP	UPDATE_OLD

UPDATE_OLD:
;Actualizar OLD_PINC con el estado actual
    MOV		R16, R20
    STS		OLD_PINC, R16
;Recuperar registros y retornar de la ISR
    POP		R21
    POP		R20
    POP		R18
    POP		R17
    POP		R16
    RETI
;***************************************************************
; SUBRUTINAS DE INCREMENTO/DECREMENTO 
;***************************************************************
;INCR_HOUR (Incrementar la hora en formato 24h: de 23 a 00)
INCR_HOUR:
    LDS     R16, HOUR_UNI_COUNTER
    INC     R16								;Se incrementa el dígito de las unidades
    STS     HOUR_UNI_COUNTER, R16
;Se compara el valor de las unidades con 10, ya que si llega a 10 se debe reiniciar a 0 y aumentar el dígito de las decenas.
    CPI     R16, 10
    BRLO    CHECK_HOUR_24					;Si es menor a 10, continuar la verificación
;Si se llegó a 10, se reinicia la parte de unidades
    LDI     R16, 0
    STS     HOUR_UNI_COUNTER, R16
    LDS     R16, HOUR_DEC_COUNTER
    INC     R16								;Se incrementa el dígito de las decenas
    STS     HOUR_DEC_COUNTER, R16			;Se almacena el nuevo valor en HOUR_DEC_COUNTER

;CHECK_HOUR_24: Verifica que la hora resultante esté en el rango válido.
CHECK_HOUR_24:
    LDS     R16, HOUR_UNI_COUNTER
    LDS     R17, HOUR_DEC_COUNTER
;Se compara R17 con 2, ya que en formato 24h la hora máxima es 23, si las decenas son 2, la unidad solo puede llegar a 3.
    CPI     R17, 2
    BRNE    NORMAL_INC_HOUR					;Si decenas ? 2, la hora es válida
;Si decenas = 2, se compara la unidad con 4
    CPI     R16, 4							;Para horas 20-23, la unidad máxima es 3
    BRLO    NORMAL_INC_HOUR					;Si la unidad es menor a 4, la hora es válida
;Si se supera, wrap en 00
    LDI     R16, 0
    STS     HOUR_UNI_COUNTER, R16
    LDI     R17, 0
    STS     HOUR_DEC_COUNTER, R17
    RET

;NORMAL_INC_HOUR: Si la hora es válida
NORMAL_INC_HOUR:
    CPI     R17, 3							;Si las decenas son 3, la hora debe ser menor que 24
    BRLO    DONE_INC_HOUR					;Si decenas es menor que 3, la hora sigue siendo válida
;Si se llegó a un valor no permitido, reinicia
    LDI     R16, 0
    STS     HOUR_UNI_COUNTER, R16
    LDI     R17, 0
    STS     HOUR_DEC_COUNTER, R17
DONE_INC_HOUR:
    RET										;Retornar de la subrutina de incremento de hora


;DECR_HOUR (Decrementar la hora en formato 24h: de 00 a 23)
DECR_HOUR:
    LDS     R16, HOUR_UNI_COUNTER
;Si las unidades son distintas de 0, se puede decrementar 
    CPI     R16, 0
    BRNE    DECR_HOUR_UNI					;Si R16 ? 0, decrementar unidades
;Si las unidades son 0, se necesita bajar el dígito de las decenas
    LDS     R17, HOUR_DEC_COUNTER
    CPI     R17, 0
    BRNE    DECR_HOUR_DEC					;Si decenas ? 0, bajar la decena
;Si tanto decenas como unidades son 0 (hora 00), se hace wrap a 23
    LDI     R17, 2							;23 tiene 2 en decenas...
    STS     HOUR_DEC_COUNTER, R17
    LDI     R16, 3							;3 en unidades.
    STS     HOUR_UNI_COUNTER, R16
    RET

DECR_HOUR_DEC:
;Si se requiere bajar la decena:
    DEC     R17								;Decrementa la decena
    STS     HOUR_DEC_COUNTER, R17
;Al bajar la decena, se fija la parte de unidades en 9
    LDI     R16, 9
    STS     HOUR_UNI_COUNTER, R16
    RET

DECR_HOUR_UNI:
;Si las unidades son mayores que 0, simplemente se decrementan
    DEC     R16
    STS     HOUR_UNI_COUNTER, R16
    RET


;INCR_MIN (Incrementar minutos en formato 60: de 59 a 00)
INCR_MIN:
    LDS     R16, MIN_UNI_COUNTER
    INC     R16								;Incrementar el dígito de las unidades
    STS     MIN_UNI_COUNTER, R16			;Si el dígito de las unidades es menor a 10, no hay overflow
    CPI     R16, 10
    BRLO    DONE_INC_MIN					;Si R16 < 10, terminar
;Si se llegó a 10, se reinicia el dígito de las unidades a 0
    LDI     R16, 0
    STS     MIN_UNI_COUNTER, R16 
    LDS     R16, MIN_DEC_COUNTER			;Cargar el dígito de las decenas de minuto
    INC     R16								;Incrementar las decenas de minuto
    STS     MIN_DEC_COUNTER, R16
;Comparar con 6, ya que en minutos el máximo es 59 (6*10 = 60 no es válido)
    CPI     R16, 6
    BRLO    DONE_INC_MIN					;Si decenas < 6, minutos son válidos
;Si decenas llegó a 6, se hace wrap a 00
    LDI     R16, 0
    STS     MIN_DEC_COUNTER, R16
DONE_INC_MIN:
    RET


;DECR_MIN (Decrementar minutos en formato 60: de 00 a 59)
DECR_MIN:
    LDS     R16, MIN_UNI_COUNTER
;Si las unidades son mayores que 0, se pueden decrementar directamente
    CPI     R16, 0
    BRNE    DECR_MIN_UNI					;Si R16 ? 0, decrementar unidades
;Si las unidades son 0, se necesita bajar el dígito de las decenas
    LDS     R17, MIN_DEC_COUNTER
    CPI     R17, 0
    BRNE    DECR_MIN_DEC					;Si decenas ? 0, bajar la decena
 ;Si tanto decenas como unidades son 0 (minuto 00), se hace wrap a 59
    LDI     R17, 5							;59 tiene 5 en decenas
    STS     MIN_DEC_COUNTER, R17
    LDI     R16, 9							;y 9 en unidades.
    STS     MIN_UNI_COUNTER, R16
    RET

DECR_MIN_DEC:
;Si se necesita decrementar la decena:
    DEC     R17								;Decrementa la decena
    STS     MIN_DEC_COUNTER, R17
;Se fija la parte de las unidades en 9 (máximo)
    LDI     R16, 9
    STS     MIN_UNI_COUNTER, R16
    RET

DECR_MIN_UNI:
;Si las unidades son mayores que 0, simplemente se decrementan
    DEC     R16
    STS     MIN_UNI_COUNTER, R16
    RET
;FECHA
;INCR_DAY: Incrementa el día y, si supera el máximo permitido para el mes actual pasa a 1
INCR_DAY:
    LDS     R16, DAY_UNI_COUNTER
    INC     R16
    STS     DAY_UNI_COUNTER, R16
    CPI     R16, 10
    BRLO    CHECK_DAY_LIMIT					;Si la unidad es menor a 10, continúa
;Si llega a 10, reiniciar la unidad y aumentar la decena
    LDI     R16, 0
    STS     DAY_UNI_COUNTER, R16
    LDS     R16, DAY_DEC_COUNTER
    INC     R16
    STS     DAY_DEC_COUNTER, R16

CHECK_DAY_LIMIT:
    LDS     R17, DAY_DEC_COUNTER
    CPI     R17, 2
    BRLO    DONE_INC_DAY					;Si decenas es 0 o 1, el día es válido (1–19)
    CPI     R17, 2
    BREQ    CHECK_DAY_TENS2					;Si decenas es 2, evaluar días 20–29
    CPI     R17, 3
    BREQ    CHECK_DAY_TENS3					;Si decenas es 3, evaluar días 30–31
    RJMP    DONE_INC_DAY

CHECK_DAY_TENS2:
    RCALL   GET_MAX_DAY						;Máx día en R20 para el mes actual
    LDS     R16, DAY_UNI_COUNTER
    LDI     R19, 20							;Base para días 20-29
    ADD     R16, R19						;Día_actual = 20 + DAY_UNI_COUNTER
    CP      R16, R20						;Comparar día_actual con máximo permitido
    BRLO    DONE_INC_DAY					;Si día_actual < máximo, es válido
    BREQ    DONE_INC_DAY					;Si día_actual == máximo, es válido
    BRSH    WRAP_DAY						;Si día_actual >= máximo, se "reinicia"
    RET

CHECK_DAY_TENS3:
    RCALL   GET_MAX_DAY						;Máx día en R20 para el mes actual
    LDS     R16, DAY_UNI_COUNTER
    LDI     R19, 30							;Base para días 30-31
    ADD     R16, R19						;Día_actual = 30 + DAY_UNI_COUNTER
    CP      R16, R20						;Comparar día_actual con máximo permitido
    BRSH    WRAP_DAY						;Si día_actual >= máximo, se "reinicia"
    RET

WRAP_DAY:
    LDI     R16, 1
    STS     DAY_UNI_COUNTER, R16
    LDI     R16, 0
    STS     DAY_DEC_COUNTER, R16
    RET

DONE_INC_DAY:
    RET

;DECR_DAY: Decrementa el día (formato dd)
DECR_DAY:
    LDS     R16, DAY_DEC_COUNTER
    LDS     R17, DAY_UNI_COUNTER
    CPI     R16, 0
    BRNE    CONTINUE_DECR_DAY
    CPI     R17, 1
    BRNE    CONTINUE_DECR_DAY
    RCALL   GET_MAX_DAY      ; Máx día en R20
;Convertir R20 al formato dd:
    CPI     R20, 10
    BRLO    SET_DAY_SINGLE
    CPI     R20, 30
    BRLO    SET_DAY_TWENTY
    CPI     R20, 31
    BREQ    SET_DAY_31
	CPI		R20, 32
	BREQ	SET_DAY_32
;Si máximo es 30:
    LDI     R16, 1
    STS     DAY_UNI_COUNTER, R16
	LDI		R16, 0
	STS		DAY_DEC_COUNTER, R16
    RJMP    DONE_DECR_DAY

CONTINUE_DECR_DAY:
    LDS     R16, DAY_UNI_COUNTER
    CPI     R16, 0
    BRNE    DECR_DAY_UNI
    RCALL   DECR_DAY_DEC
    RET

DECR_DAY_UNI:
    DEC     R16
    STS     DAY_UNI_COUNTER, R16
    RET

DECR_DAY_DEC:
    LDS     R16, DAY_DEC_COUNTER
    DEC     R16
    STS     DAY_DEC_COUNTER, R16
    LDI     R16, 9
    STS     DAY_UNI_COUNTER, R16
    RET

;Subrutinas para establecer el día al máximo (cuando se hace wrap o en decremento desde 01)
SET_DAY_SINGLE:
    LDI     R16, 0
    STS     DAY_DEC_COUNTER, R16
    MOV     R16, R20						;R20 = máximo día (si es menor a 10)
    STS     DAY_UNI_COUNTER, R16
    RET

SET_DAY_TWENTY:
    LDI     R16, 2
    STS     DAY_DEC_COUNTER, R16
    CPI     R20, 29
    BREQ    SET_DAY_29
    LDI     R16, 8
    STS     DAY_UNI_COUNTER, R16
    RET

SET_DAY_29:
    LDI     R16, 9
    STS     DAY_UNI_COUNTER, R16
    RET
SET_DAY_30:
    LDI     R16, 3							;Establece decenas en 3 (para "30")
    STS     DAY_DEC_COUNTER, R16
    LDI     R16, 0							;Establece unidades en 0 (30)
    STS     DAY_UNI_COUNTER, R16
    RET
SET_DAY_31:
    LDI     R16, 3							;Decenas = 3 (para 30)
    STS     DAY_DEC_COUNTER, R16
    LDI     R16, 0							;Unidades = 0 (30)
    STS     DAY_UNI_COUNTER, R16
    RET
SET_DAY_32:
;Para R20 = 32, el día máximo real es 31.
    LDI     R16, 3							;Establecer decenas en 3
    STS     DAY_DEC_COUNTER, R16
    LDI     R16, 0							;Establecer unidades en (31)
    STS     DAY_UNI_COUNTER, R16
    RET


DONE_DECR_DAY:
    RET

; INCR_MONTH: Incrementa el mes (formato mm) y reinicia a 01 al pasar de 12.
INCR_MONTH:
    LDS     R16, MONTH_DEC_COUNTER
    CPI     R16, 0
    BREQ    INCR_MONTH_SINGLE				;Si DEC=0: mes 1..9
;Si DEC != 0, el mes es 10, 11 o 12
    LDS     R16, MONTH_UNI_COUNTER
    CPI     R16, 2							;Si unidad es 2 (mes = 12)
    BRLO    INCR_MONTH_INCREMENT			;Si <2, se puede incrementar la unidad
;Si se llega a 12, se reinicia a 01
    LDI     R16, 1
    STS     MONTH_UNI_COUNTER, R16
    LDI     R16, 0
    STS     MONTH_DEC_COUNTER, R16
    RJMP    INCR_MONTH_DONE

INCR_MONTH_INCREMENT:
    LDS     R16, MONTH_UNI_COUNTER
    INC     R16
    STS     MONTH_UNI_COUNTER, R16
    RJMP    INCR_MONTH_DONE

INCR_MONTH_SINGLE:
    LDS     R16, MONTH_UNI_COUNTER
    CPI     R16, 9							;Si es 9, al incrementar se debe pasar a 10
    BREQ    SET_TO_TEN
    INC     R16
    STS     MONTH_UNI_COUNTER, R16
    RJMP    INCR_MONTH_DONE

SET_TO_TEN:
    LDI     R16, 0							;Reiniciar unidad a 0
    STS     MONTH_UNI_COUNTER, R16
    LDI     R16, 1							;Poner DEC en 1 para representar mes 10
    STS     MONTH_DEC_COUNTER, R16

INCR_MONTH_DONE:
    RET



;DECR_MONTH: Decrementa el mes (formato mm)
;Si se intenta decrementar 01, envuelve a 12.
DECR_MONTH:
    LDS     R16, MONTH_DEC_COUNTER			;Cargar dígito de decenas
    LDS     R17, MONTH_UNI_COUNTER			;Cargar dígito de unidades
;Si el mes es 01 (DEC = 0 y UNI = 1), pasa a 12 (DEC = 1, UNI = 2)
    CPI     R16, 0
    BRNE    CONTINUE_DECR_MONTH
    CPI     R17, 1
    BRNE    CONTINUE_DECR_MONTH
    LDI     R16, 1							;Establecer decenas en 1
    STS     MONTH_DEC_COUNTER, R16
    LDI     R16, 2							;Establecer unidades en 2 (mes 12)
    STS     MONTH_UNI_COUNTER, R16
    RJMP    DONE_DECR_MONTH

CONTINUE_DECR_MONTH:
;Para meses >= 10: si el dígito de unidades es 0, se decrementa la decena
    LDS     R16, MONTH_UNI_COUNTER
    CPI     R16, 0
    BREQ    DECR_MONTH_DEC
    ; Si el dígito de unidades es distinto de 0, se decrementa sólo ese dígito
    RCALL   DECR_MONTH_UNI
    RJMP    DONE_DECR_MONTH

DECR_MONTH_DEC:
    LDS     R16, MONTH_DEC_COUNTER
    DEC     R16								;Decrementar el dígito de decenas
    STS     MONTH_DEC_COUNTER, R16
    LDI     R16, 9							;Fijar el dígito de unidades en 9
    STS     MONTH_UNI_COUNTER, R16
    RET

DECR_MONTH_UNI:
    LDS     R16, MONTH_UNI_COUNTER
    DEC     R16								;Decrementar el dígito de unidades
    STS     MONTH_UNI_COUNTER, R16
    RET

DONE_DECR_MONTH:
    RET



;GET_MAX_DAY: Obtiene el máximo día para el mes actual usando MAX_DAY_TABLE.
GET_MAX_DAY:
    LDS     R16, MONTH_DEC_COUNTER
    CPI     R16, 0
    BREQ    GET_MONTH_SINGLE				;Si DEC=0, mes de 1 a 9
;Si DEC != 0, calcular mes = 10 + MONTH_UNI_COUNTER
    LDI     R16, 10
    LDS     R17, MONTH_UNI_COUNTER
    ADD     R16, R17						;R16 = 10 + unidad (mes 10, 11 o 12)
    RJMP    GET_MONTH_DONE
GET_MONTH_SINGLE:
    LDS     R16, MONTH_UNI_COUNTER			;Mes 1..9
GET_MONTH_DONE:
    SUBI    R16, 1							;Índice = mes - 1 (0..11)
    LDI     ZH, HIGH(MAX_DAY_TABLE<<1)
    LDI     ZL, LOW(MAX_DAY_TABLE<<1)
    ADD     ZL, R16							;Ajusta la dirección al índice correspondiente
    LPM     R20, Z							;R20 = máximo día para ese mes
    RET


;INCR_ALARM_HOUR: Incrementa la hora de la alarma (0-23)
INCR_ALARM_HOUR:
    LDS		R16, ALARM_HOUR_UNI
    INC		R16
    STS		ALARM_HOUR_UNI, R16
    CPI		R16, 10
    BRLO	CHECK_ALARM_HOUR_24
;Si llegó a 10, reiniciar unidades y subir decenas
    LDI		R16, 0
    STS		ALARM_HOUR_UNI, R16
    LDS		R16, ALARM_HOUR_DEC
    INC		R16
    STS		ALARM_HOUR_DEC, R16

CHECK_ALARM_HOUR_24:
    LDS		R16, ALARM_HOUR_UNI
    LDS		R17, ALARM_HOUR_DEC
;Si decenas = 2 y unidades >= 4 => wrap a 00
    CPI		R17, 2
    BRNE	NORMAL_INC_ALARM_HOUR
    CPI		R16, 4
    BRLO	NORMAL_INC_ALARM_HOUR
;Wrap a 00
    LDI		R16, 0
    STS		ALARM_HOUR_UNI, R16
    LDI		R17, 0
    STS		ALARM_HOUR_DEC, R17
    RET

NORMAL_INC_ALARM_HOUR:
;Si decenas >= 3 => wrap a 00
    CPI		R17, 3
    BRLO	DONE_INC_ALARM_HOUR
    LDI		R16, 0
    STS		ALARM_HOUR_UNI, R16
    LDI		R17, 0
    STS		ALARM_HOUR_DEC, R17
DONE_INC_ALARM_HOUR:
    RET

; DECR_ALARM_HOUR: Decrementa la hora de la alarma (0-23)
DECR_ALARM_HOUR:
    LDS		R16, ALARM_HOUR_UNI
    CPI		R16, 0
    BRNE	DECR_ALARM_HOUR_UNI
;Si ALARM_HOUR_UNI = 0, bajamos decena o wrap 00->23
    LDS		R17, ALARM_HOUR_DEC
    CPI		R17, 0
    BRNE	DECR_ALARM_HOUR_DEC
;Si está en 00, wrap a 23
    LDI		R17, 2
    STS		ALARM_HOUR_DEC, R17
    LDI		R16, 3
    STS		ALARM_HOUR_UNI, R16
    RET

DECR_ALARM_HOUR_DEC:
    DEC		R17
    STS		ALARM_HOUR_DEC, R17
    LDI		R16, 9
    STS		ALARM_HOUR_UNI, R16
    RET

DECR_ALARM_HOUR_UNI:
    DEC		R16
    STS		ALARM_HOUR_UNI, R16
    RET

;INCR_ALARM_MIN: Incrementa los minutos de la alarma (0-59)
INCR_ALARM_MIN:
    LDS		R16, ALARM_MIN_UNI
    INC		R16
    STS		ALARM_MIN_UNI, R16
    CPI		R16, 10
    BRLO CHECK_ALARM_MIN_60
;Llegó a 10 => reiniciar unidad y subir decena
    LDI		R16, 0
    STS		ALARM_MIN_UNI, R16
    LDS		R16, ALARM_MIN_DEC
    INC		R16
    STS		ALARM_MIN_DEC, R16

CHECK_ALARM_MIN_60:
    LDS		R16, ALARM_MIN_UNI
    LDS		R17, ALARM_MIN_DEC
    CPI		R17, 6
    BRLO	DONE_INC_ALARM_MIN
;Si decenas >= 6 => wrap a 00
    LDI		R16, 0
    STS		ALARM_MIN_UNI, R16
    LDI		R17, 0
    STS		ALARM_MIN_DEC, R17
DONE_INC_ALARM_MIN:
    RET

;DECR_ALARM_MIN: Decrementa los minutos de la alarma (0-59)
DECR_ALARM_MIN:
    LDS		R16, ALARM_MIN_UNI
    CPI		R16, 0
    BRNE	DECR_ALARM_MIN_UNI
;Si ALARM_MIN_UNI = 0 => bajar decena o wrap 00->59
    LDS		R17, ALARM_MIN_DEC
    CPI		R17, 0
    BRNE	DECR_ALARM_MIN_DEC
;Si estaba en 00 => wrap a 59
    LDI		R17, 5
    STS		ALARM_MIN_DEC, R17
    LDI		R16, 9
    STS		ALARM_MIN_UNI, R16
    RET

DECR_ALARM_MIN_DEC:
    DEC		R17
    STS		ALARM_MIN_DEC, R17
    LDI		R16, 9
    STS		ALARM_MIN_UNI, R16
    RET

DECR_ALARM_MIN_UNI:
    DEC		R16
    STS		ALARM_MIN_UNI, R16
    RET



