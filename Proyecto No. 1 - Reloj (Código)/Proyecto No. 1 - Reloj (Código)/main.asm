;***********************************************
; Universidad del Valle de Guatemala
; IE2023: Programación de Microcontroladores
; Proyecto No.1 - Reloj.asm 
; Descripción: Reloj digital en formato 24 horas y fecha en formato (DD/MM) implementa un sistema 
;				de alarma audible. 
;***********************************************

; Incluye definiciones del microcontrolador ATmega328PB
.include "m328pbdef.inc"    ; Incluye el archivo con las definiciones específicas del ATmega328PB

;***********************************************
; CONSTANTES DEFINIDAS
;***********************************************
.equ VALOR_COMPARACION = 60  ; Valor de comparación para el temporizador (60 para 1 minuto)
.equ MIN_UNIT_DISP = 2       ; PC2: Pin para mostrar unidades de minutos en el display
.equ MIN_DECS_DISP = 3       ; PC3: Pin para mostrar decenas de minutos en el display
.equ HORA_UNIT_DISP = 4      ; PC4: Pin para mostrar unidades de horas en el display
.equ HORA_DECS_DISP = 5      ; PC5: Pin para mostrar decenas de horas en el display
.equ DIA_UNIT_DISP = 4       ; Reutiliza los mismos pines para mostrar la fecha (unidades del día)
.equ DIA_DECS_DISP = 5       ; Reutiliza los mismos pines para mostrar la fecha (decenas del día)
.equ MES_UNIT_DISP = 2       ; Pin para mostrar unidades del mes
.equ MES_DECS_DISP = 3       ; Pin para mostrar decenas del mes
.equ BOTON_FECHA = 3         ; Pin para el botón que cambia a modo de fecha
.equ BOTON_MODO = 3          ; PB3: Botón para cambiar entre modos (hora/fecha/configuración)
.equ BOTON_SELECCION = 2     ; PB2: Botón para seleccionar entre horas y minutos
.equ BOTON_INCREMENTO = 0    ; PB0: Botón para incrementar el valor
.equ BOTON_DECREMENTO = 1    ; PB1: Botón para decrementar el valor
.equ LED_CONFIG_HORA = 4     ; PB4: LED indicador para modo de configuración de hora
.equ LED_CONFIG_FECHA = 5    ; PB5: LED indicador para modo de configuración de fecha
.equ LED_BIT = 7             ; PD7: Bit para controlar los LEDs
.equ LED_CONFIG_ALARMA = 0   ; PC0: LED indicador para modo de configuración de alarma
.equ BUZZER = 1              ; PC1: Pin para el buzzer que emite la alarma

;***********************************************
; DEFINICIÓN DE VARIABLES EN RAM
;***********************************************
.dseg                       ; Segmento de datos (RAM)
.org SRAM_START             ; Inicio de la RAM

timer_count:    .byte 1     ; Contador para el timer (cuenta hasta ~60 para formar 1 segundo)
segundos:       .byte 1     ; Contador de segundos (0-59)
min_unidades:   .byte 1     ; Unidades de minutos (0-9)
min_decenas:    .byte 1     ; Decenas de minutos (0-5)
hora_unidades:  .byte 1     ; Unidades de horas (0-9)
hora_decenas:   .byte 1     ; Decenas de horas (0-2)
dia_unidades:   .byte 1     ; Unidades del día (0-9)
dia_decenas:    .byte 1     ; Decenas del día (0-3)
mes_unidades:   .byte 1     ; Unidades del mes (0-9)
mes_decenas:    .byte 1     ; Decenas del mes (0-1)
mostrar_fecha:  .byte 1     ; Flag para mostrar fecha (0 = hora, 1 = fecha)
fecha_timer:    .byte 1     ; Contador para mostrar fecha temporalmente
display_sel:    .byte 1     ; Selector de display (0-3) para la multiplexación
led_counter:    .byte 1     ; Contador para parpadeo de LEDs (500ms)
led_state:      .byte 1     ; Estado actual de los LEDs (0 = apagado, 1 = encendido)
modo_reloj:     .byte 1     ; 0=hora, 1=fecha, 2=configuración
config_sel:     .byte 1     ; 0=horas, 1=minutos
alarma_hora_unidades: .byte 1  ; Unidades de hora para alarma (0-9)
alarma_hora_decenas:  .byte 1  ; Decenas de hora para alarma (0-2)
alarma_min_unidades:  .byte 1  ; Unidades de minutos para alarma (0-9)
alarma_min_decenas:   .byte 1  ; Decenas de minutos para alarma (0-5)
alarma_activa:        .byte 1  ; Estado de la alarma (0=inactiva, 1=activa)
alarma_sonando:       .byte 1  ; Indica si la alarma está sonando (0=no, 1=sí)
portc_shadow: .byte 1         ; Sombra para PORTC (para control de displays)
buzzer_counter: .byte 1       ; Contador para el patrón de sonido del buzzer

;***********************************************
; SEGMENTO DE CÓDIGO
;***********************************************
.cseg                       ; Segmento de código (Flash)

;***********************************************
; VECTORES DE INTERRUPCIÓN
;***********************************************
.org 0x0000                 ; Vector de reset
    rjmp SETUP              ; Salta a la configuración inicial

.org PCINT0addr             ; Vector de interrupción para cambios en el pin
   rjmp PCINT0_ISR          ; Salta a la rutina de interrupción del botón fecha

.org TIMER0_OVFaddr         ; Vector de interrupción Timer0
    rjmp TMR0_ISR           ; Salta a la rutina del contador de tiempo

;***********************************************
; DEFINICIÓN DE REGISTROS
;***********************************************
; Registros principales
.def temp = r16             ; Registro temporal para operaciones generales
.def temp2 = r17            ; Segundo registro temporal
.def digit = r18            ; Almacena el dígito actual a mostrar en el display
.def mux_mask = r19         ; Máscara para el display activo en multiplexación
.def display_pat = r20      ; Patrón para el display de 7 segmentos

;***********************************************
; TABLA DE VALORES PARA DISPLAY 7 SEGMENTOS
;***********************************************
TABLA7SEG:                  ; Patrones para mostrar números 0-9 en display cátodo común
    .db 0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F

;***********************************************
; RUTINA DE CONFIGURACIÓN INICIAL
;***********************************************
SETUP:
    ; Configuración del Stack Pointer
    ldi temp, high(RAMEND)  ; Carga la parte alta de la dirección de fin de RAM
    out SPH, temp           ; Establece el puntero de pila alto
    ldi temp, low(RAMEND)   ; Carga la parte baja de la dirección de fin de RAM
    out SPL, temp           ; Establece el puntero de pila bajo

    ; Deshabilita UART
    ldi temp, 0x00          ; Carga 0 en el registro temporal
    sts UCSR0B, temp        ; Deshabilita la comunicación UART

    ; Configurar puertos B
	ldi temp, (1<<LED_CONFIG_HORA)|(1<<LED_CONFIG_FECHA)  ; Configura PB4 y PB5 como salidas (LEDs)
	out DDRB, temp           ; Establece la dirección de datos para PORTB
	ldi temp, 0b00001111     ; Activa pull-ups en PB0-PB3 (botones)
	out PORTB, temp          ; Establece el estado de PORTB

	; Configurar interrupciones pin change para todos los botones
	ldi temp, (1<<PCIE0)     ; Habilita interrupciones de cambio de pin para el grupo PORTB
	sts PCICR, temp          ; Establece el registro de control de interrupciones
	ldi temp, (1<<PCINT0)|(1<<PCINT1)|(1<<PCINT2)|(1<<PCINT3) ; Habilita interrupciones para botones
	sts PCMSK0, temp         ; Establece la máscara de interrupciones para PORTB

    ; Configura PORTC para control de displays
    ldi temp, 0x3F          ; Configura PC0-PC5 como salidas para el display
    out DDRC, temp          ; Establece la dirección de datos para PORTC
    ldi temp, 0x00          ; Inicializa PORTC con todos los displays apagados
    out PORTC, temp         ; Establece el estado de PORTC

    ; Configura PORTD para segmentos del display y LEDs
    ldi temp, 0xFF          ; Configura todo PORTD como salidas (incluyendo PD7 para LEDs)
    out DDRD, temp          ; Establece la dirección de datos para PORTD
    ldi temp, 0x00          ; Inicializa PORTD con todos los segmentos y LEDs apagados
    out PORTD, temp         ; Establece el estado de PORTD

    ; Configura Timer0
    ldi temp, 0x00          ; Configura Timer0 en modo normal
    out TCCR0A, temp        ; Establece el registro de control del Timer0
    ldi temp, 0x05          ; Establece el prescaler a 1024
    out TCCR0B, temp        ; Establece el registro de control del Timer0
    ldi temp, 0x01          ; Habilita la interrupción por overflow del Timer0
    sts TIMSK0, temp        ; Habilita interrupción por overflow

  ; Inicializa variables en RAM
    ldi temp, 0                 ; Carga el valor 0 en el registro temporal 'temp'
    sts timer_count, temp       ; Establece el contador del timer en 0
    sts segundos, temp          ; Establece el contador de segundos en 0
    sts min_unidades, temp      ; Establece las unidades de minutos en 0
    sts min_decenas, temp       ; Establece las decenas de minutos en 0
    sts hora_unidades, temp     ; Establece las unidades de horas en 0
    sts hora_decenas, temp      ; Establece las decenas de horas en 0
    sts modo_reloj, temp        ; Establece el modo de reloj en 0 (hora)
    sts config_sel, temp        ; Establece el selector de configuración en 0 (horas)
    sts display_sel, temp       ; Establece el selector de display en 0
    sts led_counter, temp       ; Establece el contador de LEDs en 0
    sts led_state, temp         ; Establece el estado de los LEDs en 0 (apagado)
    sts alarma_hora_unidades, temp  ; Establece las unidades de hora para la alarma en 0
    sts alarma_hora_decenas, temp     ; Establece las decenas de hora para la alarma en 0
    sts alarma_min_unidades, temp      ; Establece las unidades de minutos para la alarma en 0
    sts alarma_min_decenas, temp       ; Establece las decenas de minutos para la alarma en 0
    sts alarma_activa, temp          ; Establece el estado de la alarma en 0 (inactiva)
    sts alarma_sonando, temp         ; Establece el estado de la alarma sonando en 0 (no sonando)
    sts portc_shadow, temp           ; Establece la sombra de PORTC en 0
    sts buzzer_counter, temp         ; Establece el contador del buzzer en 0
    sts mes_decenas, temp            ; Establece las decenas del mes en 0
    sts mostrar_fecha, temp          ; Establece el flag para mostrar fecha en 0 (hora)
    sts fecha_timer, temp            ; Establece el contador de fecha en 0
    sts dia_decenas, temp            ; Establece las decenas del día en 0

    ; Inicializa variables de fecha (establecer la fecha inicial deseada)
    ldi temp, 1                     ; Carga el valor 1 en el registro temporal 'temp'
    sts dia_unidades, temp          ; Establece las unidades del día en 1 (primer día del mes)
    sts mes_unidades, temp          ; Establece las unidades del mes en 1 (enero)

    sei                              ; Habilita interrupciones globales

;***********************************************
; LOOP PRINCIPAL
;***********************************************
MAIN:
    rcall APAGAR_DISPLAYS           ; Llama a la subrutina para apagar todos los displays
    rcall SELECCIONAR_DISPLAY       ; Llama a la subrutina para seleccionar qué display mostrar
    rcall MOSTRAR_DIGITO            ; Llama a la subrutina para mostrar el dígito correspondiente
    rcall DELAY_MUX                 ; Llama a la subrutina para un pequeño delay en la multiplexación
    rjmp MAIN                       ; Repite indefinidamente el loop principal

;***********************************************
; SUBRUTINAS DEL PROGRAMA PRINCIPAL
;***********************************************
;----------------------------------------------
; APAGAR_DISPLAYS: Apaga los displays sin afectar el buzzer y LED
;-----------------------------------------
APAGAR_DISPLAYS:
    in temp, PORTC                 ; Lee el estado actual de PORTC y lo almacena en 'temp'
    andi temp, 0b00000011          ; Mantiene los bits 0-1 (buzzer y LED), apaga displays (PC2-PC5)
    out PORTC, temp                ; Escribe el estado modificado de PORTC (apaga displays)
    ret                             ; Retorna de la subrutina


;----------------------------------------------
; SELECCIONAR_DISPLAY: Determina qué display mostrar
;----------------------------------------------
SELECCIONAR_DISPLAY:
    ; Verifica el modo actual del reloj
    lds temp, modo_reloj							; Carga el valor del modo actual en 'temp'
    cpi temp, 1										; Compara 'temp' con 1 (modo de fecha)
    breq SELECCIONAR_DISPLAY_FECHA_LOCAL			; Si es igual, salta a la selección de fecha
    cpi temp, 2										; Compara 'temp' con 2 (modo de configuración de hora)
    breq SELECCIONAR_DISPLAY_CONFIG_HORA_LOCAL		; Si es igual, salta a la selección de configuración de hora
    cpi temp, 3										; Compara 'temp' con 3 (modo de configuración de fecha)
    breq SELECCIONAR_DISPLAY_CONFIG_FECH_LOCAL		; Si es igual, salta a la selección de configuración de fecha
    cpi temp, 4										; Compara 'temp' con 4 (modo de configuración de alarma)
    breq SELECCIONAR_DISPLAY_CONFIG_ALARMA_LOCAL    ; Si es igual, salta a la selección de configuración de alarma
    rjmp FIN_SELECCION								; Si no coincide con ninguno, salta a la finalización de selección
	 
SELECCIONAR_DISPLAY_FECHA_LOCAL:
    rjmp SELECCIONAR_DISPLAY_FECHA ; Salta a la subrutina para seleccionar el display de fecha
    
SELECCIONAR_DISPLAY_CONFIG_HORA_LOCAL:
    rjmp SELECCIONAR_DISPLAY_CONFIG_HORA ; Salta a la subrutina para seleccionar el display de configuración de hora
    
SELECCIONAR_DISPLAY_CONFIG_FECH_LOCAL:
    rjmp SELECCIONAR_DISPLAY_CONFIG_FECHA ; Salta a la subrutina para seleccionar el display de configuración de fecha
    
SELECCIONAR_DISPLAY_CONFIG_ALARMA_LOCAL:
    rjmp SELECCIONAR_DISPLAY_ALARMA ; Salta a la subrutina para seleccionar el display de configuración de alarma
    
FIN_SELECCION:
    ; Modo 0: Mostrar hora 
    lds temp, display_sel          ; Carga el valor del selector de display en 'temp'
    cpi temp, 0                    ; Compara 'temp' con 0 (unidades de minutos)
    breq SELECT_MIN_UNIDADES       ; Si es igual, salta a la selección de unidades de minutos
    cpi temp, 1                    ; Compara 'temp' con 1 (decenas de minutos)
    breq SELECT_MIN_DECENAS		   ; Si es igual, salta a la selección de decenas de minutos
    cpi temp, 2                    ; Compara 'temp' con 2 (unidades de horas)
    breq SELECT_HORA_UNIDADES      ; Si es igual, salta a la selección de unidades de horas
    cpi temp, 3                    ; Compara 'temp' con 3 (decenas de horas)
    breq SELECT_HORA_DECENAS       ; Si es igual, salta a la selección de decenas de horas
    rjmp SELECT_MIN_UNIDADES       ; Por seguridad, vuelve a unidades de minutos si no coincide

SELECT_MIN_UNIDADES:
    lds digit, min_unidades          ; Carga el valor de las unidades de minutos en 'digit'
    ldi mux_mask, (1<<MIN_UNIT_DISP) ; Establece la máscara para el display de unidades de minutos
    ret                              ; Retorna de la subrutina

SELECT_MIN_DECENAS:
    lds digit, min_decenas           ; Carga el valor de las decenas de minutos en 'digit'
    ldi mux_mask, (1<<MIN_DECS_DISP) ; Establece la máscara para el display de decenas de minutos
    ret                              ; Retorna de la subrutina
    
SELECT_HORA_UNIDADES:
    lds digit, hora_unidades          ; Carga el valor de las unidades de horas en 'digit'
    ldi mux_mask, (1<<HORA_UNIT_DISP) ; Establece la máscara para el display de unidades de horas
    ret                               ; Retorna de la subrutina
    
SELECT_HORA_DECENAS:
    lds digit, hora_decenas           ; Carga el valor de las decenas de horas en 'digit'
    ldi mux_mask, (1<<HORA_DECS_DISP) ; Establece la máscara para el display de decenas de horas
    ret                               ; Retorna de la subrutina

SELECCIONAR_DISPLAY_FECHA:
    ; Mostrar fecha
    lds temp, display_sel          ; Carga el valor del selector de display en 'temp'
    cpi temp, 0                    ; Compara 'temp' con 0 (unidades del día)
    breq SELECT_DIA_UNIDADES       ; Si es igual, salta a la selección de unidades del día
    cpi temp, 1                    ; Compara 'temp' con 1 (decenas del día)
    breq SELECT_DIA_DECENAS        ; Si es igual, salta a la selección de decenas del día
    cpi temp, 2                    ; Compara 'temp' con 2 (unidades del mes)
    breq SELECT_MES_UNIDADES       ; Si es igual, salta a la selección de unidades del mes
    cpi temp, 3                    ; Compara 'temp' con 3 (decenas del mes)
    breq SELECT_MES_DECENAS        ; Si es igual, salta a la selección de decenas del mes
    rjmp SELECT_DIA_UNIDADES       ; Por seguridad, vuelve a unidades de días si no coincide

SELECT_DIA_UNIDADES:
    lds digit, dia_unidades        ; Carga el valor de las unidades del día en 'digit'
    ldi mux_mask, (1<<DIA_UNIT_DISP) ; Establece la máscara para el display de unidades del día
    ret                             ; Retorna de la subrutina

SELECT_DIA_DECENAS:
    lds digit, dia_decenas         ; Carga el valor de las decenas del día en 'digit'
    ldi mux_mask, (1<<DIA_DECS_DISP) ; Establece la máscara para el display de decenas del día
    ret                             ; Retorna de la subrutina

SELECT_MES_UNIDADES:
    lds digit, mes_unidades        ; Carga el valor de las unidades del mes en 'digit'
    ldi mux_mask, (1<<MES_UNIT_DISP) ; Establece la máscara para el display de unidades del mes
    ret                             ; Retorna de la subrutina

SELECT_MES_DECENAS:
    lds digit, mes_decenas         ; Carga el valor de las decenas del mes en 'digit'
    ldi mux_mask, (1<<MES_DECS_DISP) ; Establece la máscara para el display de decenas del mes
    ret                             ; Retorna de la subrutina


SELECCIONAR_DISPLAY_CONFIG_HORA:
    ; Modo 2: Mostrar hora con parpadeo en el valor que se está configurando
    lds temp, display_sel          ; Carga el valor del selector de display en 'temp'
    cpi temp, 0                    ; Compara 'temp' con 0 (unidades de minutos)
    breq SELECT_CONFIG_MIN_UNIDADES ; Si es igual, salta a la selección de unidades de minutos
    cpi temp, 1                    ; Compara 'temp' con 1 (decenas de minutos)
    breq SELECT_CONFIG_MIN_DECENAS  ; Si es igual, salta a la selección de decenas de minutos
    cpi temp, 2                    ; Compara 'temp' con 2 (unidades de horas)
    breq SELECT_CONFIG_HORA_UNIDADES ; Si es igual, salta a la selección de unidades de horas
    cpi temp, 3                    ; Compara 'temp' con 3 (decenas de horas)
    breq SELECT_CONFIG_HORA_DECENAS  ; Si es igual, salta a la selección de decenas de horas
    rjmp SELECT_CONFIG_MIN_UNIDADES ; Por seguridad, vuelve a unidades de minutos

SELECT_CONFIG_MIN_UNIDADES:
    lds digit, min_unidades        ; Carga el valor de las unidades de minutos en 'digit'
    ldi mux_mask, (1<<MIN_UNIT_DISP) ; Establece la máscara para el display de unidades de minutos
    
    ; Si estamos configurando minutos, parpadear unidades
    lds temp, config_sel           ; Carga el valor del selector de configuración en 'temp'
    cpi temp, 1                    ; Compara 'temp' con 1 (modo de configuración de minutos)
    brne DISPLAY_CONFIG_DIGIT      ; Si no es igual, salta a la rutina de configuración de dígitos
    
    ; Parpadeo usando el contador de LEDs
    lds temp, led_state            ; Carga el estado de los LEDs en 'temp'
    cpi temp, 0                    ; Compara 'temp' con 0 (LED apagado)
    brne DISPLAY_CONFIG_DIGIT      ; Si no es igual, salta a la rutina de configuración de dígitos
    
    ; Durante parpadeo, apagar dígito
    ldi mux_mask, 0                ; Establece la máscara a 0 para apagar el dígito
    ret                             ; Retorna de la subrutina
    
SELECT_CONFIG_MIN_DECENAS:
    lds digit, min_decenas         ; Carga el valor de las decenas de minutos en 'digit'
    ldi mux_mask, (1<<MIN_DECS_DISP) ; Establece la máscara para el display de decenas de minutos
    
    ; Si estamos configurando minutos, parpadear decenas
    lds temp, config_sel           ; Carga el valor del selector de configuración en 'temp'
    cpi temp, 1                    ; Compara 'temp' con 1 (modo de configuración de minutos)
    brne DISPLAY_CONFIG_DIGIT      ; Si no es igual, salta a la rutina de configuración de dígitos
    
    ; Parpadeo usando el contador de LEDs
    lds temp, led_state            ; Carga el estado de los LEDs en 'temp'
    cpi temp, 0                    ; Compara 'temp' con 0 (LED apagado)
    brne DISPLAY_CONFIG_DIGIT      ; Si no es igual, salta a la rutina de configuración de dígitos
    
    ; Durante parpadeo, apagar dígito
    ldi mux_mask, 0                ; Establece la máscara a 0 para apagar el dígito
    ret                             ; Retorna de la subrutina
    
SELECT_CONFIG_HORA_UNIDADES:
    lds digit, hora_unidades       ; Carga el valor de las unidades de horas en 'digit'
    ldi mux_mask, (1<<HORA_UNIT_DISP) ; Establece la máscara para el display de unidades de horas
    
    ; Si estamos configurando horas, parpadear unidades
    lds temp, config_sel           ; Carga el valor del selector de configuración en 'temp'
    cpi temp, 0                    ; Compara 'temp' con 0 (modo de configuración de horas)
    brne DISPLAY_CONFIG_DIGIT      ; Si no es igual, salta a la rutina de configuración de dígitos
    
    ; Parpadeo usando el contador de LEDs
    lds temp, led_state            ; Carga el estado de los LEDs en 'temp'
    cpi temp, 0                    ; Compara 'temp' con 0 (LED apagado)
    brne DISPLAY_CONFIG_DIGIT      ; Si no es igual, salta a la rutina de configuración de dígitos
    
    ; Durante parpadeo, apagar dígito
    ldi mux_mask, 0                ; Establece la máscara a 0 para apagar el dígito
    ret                            ; Retorna de la subrutina
    
SELECT_CONFIG_HORA_DECENAS:
    lds digit, hora_decenas        ; Carga el valor de las decenas de horas en 'digit'
    ldi mux_mask, (1<<HORA_DECS_DISP) ; Establece la máscara para el display de decenas de horas
    
    ; Si estamos configurando horas, parpadear decenas
    lds temp, config_sel           ; Carga el valor del selector de configuración en 'temp'
    cpi temp, 0                    ; Compara 'temp' con 0 (modo de configuración de horas)
    brne DISPLAY_CONFIG_DIGIT      ; Si no es igual, salta a la rutina de configuración de dígitos
    
    ; Parpadeo usando el contador de LEDs
    lds temp, led_state            ; Carga el estado de los LEDs en 'temp'
    cpi temp, 0                    ; Compara 'temp' con 0 (LED apagado)
    brne DISPLAY_CONFIG_DIGIT      ; Si no es igual, salta a la rutina de configuración de dígitos
    
    ; Durante parpadeo, apagar dígito
    ldi mux_mask, 0                 ; Establece la máscara a 0 para apagar el dígito
    ret                             ; Retorna de la subrutina
    
DISPLAY_CONFIG_DIGIT:
    ret                             ; Retorna de la subrutina

SELECCIONAR_DISPLAY_CONFIG_FECHA:
    ; Modo 3: Mostrar fecha con parpadeo en el valor que se está configurando
    lds temp, display_sel				; Carga el valor del selector de display en 'temp'
    cpi temp, 0							; Compara 'temp' con 0 (unidades del día)
    breq SELECT_CONFIG_DIA_UNIDADES		; Si es igual, salta a la selección de unidades del día
    cpi temp, 1							; Compara 'temp' con 1 (decenas del día)
    breq SELECT_CONFIG_DIA_DECENAS		; Si es igual, salta a la selección de decenas del día
    cpi temp, 2							; Compara 'temp' con 2 (unidades del mes)
    breq SELECT_CONFIG_MES_UNIDADES		; Si es igual, salta a la selección de unidades del mes
    cpi temp, 3							; Compara 'temp' con 3 (decenas del mes)
    breq SELECT_CONFIG_MES_DECENAS		; Si es igual, salta a la selección de decenas del mes
    rjmp SELECT_CONFIG_DIA_UNIDADES		; Por seguridad, vuelve a unidades de días si no coincide

SELECT_CONFIG_DIA_UNIDADES:
    lds digit, dia_unidades				; Carga el valor de las unidades del día en 'digit'
    ldi mux_mask, (1<<DIA_UNIT_DISP)	; Establece la máscara para el display de unidades del día
    
    ; Si estamos configurando días, parpadear unidades
    lds temp, config_sel				; Carga el valor del selector de configuración en 'temp'
    cpi temp, 0							; Compara 'temp' con 0 (modo de configuración de días)
    brne DISPLAY_CONFIG_FECHA_DIGIT		; Si no es igual, salta a la rutina de configuración de dígitos
    
    ; Parpadeo usando el contador de LEDs
    lds temp, led_state					; Carga el estado de los LEDs en 'temp'
    cpi temp, 0							; Compara 'temp' con 0 (LED apagado)
    brne DISPLAY_CONFIG_FECHA_DIGIT		; Si no es igual, salta a la rutina de configuración de dígitos
    
    ; Durante parpadeo, apagar dígito
    ldi mux_mask, 0                ; Establece la máscara a 0 para apagar el dígito
    ret                             ; Retorna de la subrutina
    
SELECT_CONFIG_DIA_DECENAS:
    lds digit, dia_decenas				; Carga el valor de las decenas del día en 'digit'
    ldi mux_mask, (1<<DIA_DECS_DISP)	; Establece la máscara para el display de decenas del día
    
    ; Si estamos configurando días, parpadear decenas
    lds temp, config_sel				; Carga el valor del selector de configuración en 'temp'
    cpi temp, 0							; Compara 'temp' con 0 (modo de configuración de días)
    brne DISPLAY_CONFIG_FECHA_DIGIT		; Si no es igual, salta a la rutina de configuración de dígitos
    
    ; Parpadeo usando el contador de LEDs
    lds temp, led_state					; Carga el estado de los LEDs en 'temp'
    cpi temp, 0							; Compara 'temp' con 0 (LED apagado)
    brne DISPLAY_CONFIG_FECHA_DIGIT		; Si no es igual, salta a la rutina de configuración de dígitos
    
    ; Durante parpadeo, apagar dígito
    ldi mux_mask, 0                 ; Establece la máscara a 0 para apagar el dígito
    ret                             ; Retorna de la subrutina
    
SELECT_CONFIG_MES_UNIDADES:
    lds digit, mes_unidades			 ; Carga el valor de las unidades del mes en 'digit'
    ldi mux_mask, (1<<MES_UNIT_DISP) ; Establece la máscara para el display de unidades del mes
    
    ; Si estamos configurando meses, parpadear unidades
    lds temp, config_sel			; Carga el valor del selector de configuración en 'temp'
    cpi temp, 1						; Compara 'temp' con 1 (modo de configuración de meses)
    brne DISPLAY_CONFIG_FECHA_DIGIT ; Si no es igual, salta a la rutina de configuración de dígitos
    
    ; Parpadeo usando el contador de LEDs
    lds temp, led_state				; Carga el estado de los LEDs en 'temp'
    cpi temp, 0						; Compara 'temp' con 0 (LED apagado)
    brne DISPLAY_CONFIG_FECHA_DIGIT ; Si no es igual, salta a la rutina de configuración de dígitos
    
    ; Durante parpadeo, apagar dígito
    ldi mux_mask, 0					; Establece la máscara a 0 para apagar el dígito
    ret                             ; Retorna de la subrutina
    
SELECT_CONFIG_MES_DECENAS:
    lds digit, mes_decenas			 ; Carga el valor de las decenas del mes en 'digit'
    ldi mux_mask, (1<<MES_DECS_DISP) ; Establece la máscara para el display de decenas del mes
    
    ; Si estamos configurando meses, parpadear decenas
    lds temp, config_sel			; Carga el valor del selector de configuración en 'temp'
    cpi temp, 1						; Compara 'temp' con 1 (modo de configuración de meses)
    brne DISPLAY_CONFIG_FECHA_DIGIT ; Si no es igual, salta a la rutina de configuración de dígitos
    
    ; Parpadeo usando el contador de LEDs
    lds temp, led_state				; Carga el estado de los LEDs en 'temp'
    cpi temp, 0						; Compara 'temp' con 0 (LED apagado)
    brne DISPLAY_CONFIG_FECHA_DIGIT ; Si no es igual, salta a la rutina de configuración de dígitos
    
    ; Durante parpadeo, apagar dígito
    ldi mux_mask, 0                 ; Establece la máscara a 0 para apagar el dígito
    ret                             ; Retorna de la subrutina
    
DISPLAY_CONFIG_FECHA_DIGIT:
    ret                             ; Retorna de la subrutina

SELECCIONAR_DISPLAY_ALARMA:
    ; Modo 4: Mostrar alarma con parpadeo en el valor que se está configurando
    lds temp, display_sel          ; Carga el valor del selector de display en 'temp'
    cpi temp, 0                    ; Compara 'temp' con 0 (unidades de minutos de la alarma)
    breq SELECT_ALARMA_MIN_UNIDADES ; Si es igual, salta a la selección de unidades de minutos
    cpi temp, 1                    ; Compara 'temp' con 1 (decenas de minutos de la alarma)
    breq SELECT_ALARMA_MIN_DECENAS  ; Si es igual, salta a la selección de decenas de minutos
    cpi temp, 2                    ; Compara 'temp' con 2 (unidades de horas de la alarma)
    breq SELECT_ALARMA_HORA_UNIDADES ; Si es igual, salta a la selección de unidades de horas
    cpi temp, 3                    ; Compara 'temp' con 3 (decenas de horas de la alarma)
    breq SELECT_ALARMA_HORA_DECENAS  ; Si es igual, salta a la selección de decenas de horas
    rjmp SELECT_ALARMA_MIN_UNIDADES ; Por seguridad, vuelve a unidades de minutos si no coincide

SELECT_ALARMA_MIN_UNIDADES:
    lds digit, alarma_min_unidades   ; Carga el valor de las unidades de minutos de la alarma en 'digit'
    ldi mux_mask, (1<<MIN_UNIT_DISP) ; Establece la máscara para el display de unidades de minutos
    
    ; Si estamos configurando minutos, parpadeo en unidades
    lds temp, config_sel            ; Carga el valor del selector de configuración en 'temp'
    cpi temp, 1                     ; Compara 'temp' con 1 (modo de configuración de minutos)
    brne DISPLAY_ALARMA_DIGIT       ; Si no es igual, salta a la rutina de configuración de dígitos
    
    ; Parpadeo usando el contador de LEDs
    lds temp, led_state             ; Carga el estado de los LEDs en 'temp'
    cpi temp, 0                     ; Compara 'temp' con 0 (LED apagado)
    brne DISPLAY_ALARMA_DIGIT       ; Si no es igual, salta a la rutina de configuración de dígitos
    
    ; Durante parpadeo, apagar dígito
    ldi mux_mask, 0                  ; Establece la máscara a 0 para apagar el dígito
    ret                              ; Retorna de la subrutina
    
SELECT_ALARMA_MIN_DECENAS:
    lds digit, alarma_min_decenas     ; Carga el valor de las decenas de minutos de la alarma en 'digit'
    ldi mux_mask, (1<<MIN_DECS_DISP)  ; Establece la máscara para el display de decenas de minutos
    
    ; Si estamos configurando minutos, parpadeo en decenas
    lds temp, config_sel             ; Carga el valor del selector de configuración en 'temp'
    cpi temp, 1                      ; Compara 'temp' con 1 (modo de configuración de minutos)
    brne DISPLAY_ALARMA_DIGIT        ; Si no es igual, salta a la rutina de configuración de dígitos
    
    ; Parpadeo usando el contador de LEDs
    lds temp, led_state              ; Carga el estado de los LEDs en 'temp'
    cpi temp, 0                      ; Compara 'temp' con 0 (LED apagado)
    brne DISPLAY_ALARMA_DIGIT        ; Si no es igual, salta a la rutina de configuración de dígitos
    
    ; Durante parpadeo, apagar dígito
    ldi mux_mask, 0                   ; Establece la máscara a 0 para apagar el dígito
    ret                               ; Retorna de la subrutina
    
SELECT_ALARMA_HORA_UNIDADES:
    lds digit, alarma_hora_unidades		; Carga el valor de las unidades de horas de la alarma en 'digit'
    ldi mux_mask, (1<<HORA_UNIT_DISP)	; Establece la máscara para el display de unidades de horas
    
    ; Si estamos configurando horas, parpadeo en unidades
    lds temp, config_sel             ; Carga el valor del selector de configuración en 'temp'
    cpi temp, 0                      ; Compara 'temp' con 0 (modo de configuración de horas)
    brne DISPLAY_ALARMA_DIGIT        ; Si no es igual, salta a la rutina de configuración de dígitos
    
    ; Parpadeo usando el contador de LEDs
    lds temp, led_state              ; Carga el estado de los LEDs en 'temp'
    cpi temp, 0                      ; Compara 'temp' con 0 (LED apagado)
    brne DISPLAY_ALARMA_DIGIT        ; Si no es igual, salta a la rutina de configuración de dígitos
    
    ; Durante parpadeo, apagar dígito
    ldi mux_mask, 0					  ; Establece la máscara a 0 para apagar el dígito
    ret                               ; Retorna de la subrutina
    
SELECT_ALARMA_HORA_DECENAS:
    lds digit, alarma_hora_decenas		; Carga el valor de las decenas de horas de la alarma en 'digit'
    ldi mux_mask, (1<<HORA_DECS_DISP)   ; Establece la máscara para el display de decenas de horas
    
    ; Si estamos configurando horas, parpadeo en decenas
    lds temp, config_sel             ; Carga el valor del selector de configuración en 'temp'
    cpi temp, 0                      ; Compara 'temp' con 0 (modo de configuración de horas)
    brne DISPLAY_ALARMA_DIGIT        ; Si no es igual, salta a la rutina de configuración de dígitos
    
    ; Parpadeo usando el contador de LEDs
    lds temp, led_state              ; Carga el estado de los LEDs en 'temp'
    cpi temp, 0                      ; Compara 'temp' con 0 (LED apagado)
    brne DISPLAY_ALARMA_DIGIT        ; Si no es igual, salta a la rutina de configuración de dígitos
    
    ; Durante parpadeo, apagar dígito
    ldi mux_mask, 0					  ; Establece la máscara a 0 para apagar el dígito
    ret                               ; Retorna de la subrutina
    
DISPLAY_ALARMA_DIGIT:
    ret                               ; Retorna de la subrutina

;----------------------------------------------
; MOSTRAR_DIGITO: Muestra el dígito en el display seleccionado
;----------------------------------------------
MOSTRAR_DIGITO:
    ; Obtener patrón para el dígito actual
    ldi ZH, high(TABLA7SEG*2)      ; Carga la parte alta de la dirección de la tabla de patrones
    ldi ZL, low(TABLA7SEG*2)       ; Carga la parte baja de la dirección de la tabla de patrones
    
    ; Verificar que el dígito esté en rango (0-9)
    mov temp, digit                 ; Mueve el dígito actual a 'temp'
    cpi temp, 10                    ; Compara 'temp' con 10
    brlo VALID_DIGIT                ; Si está en rango, salta a VALID_DIGIT
    ldi temp, 0                     ; Si no está en rango, establece 'temp' a 0
    mov digit, temp                 ; Actualiza 'digit' a 0
    
VALID_DIGIT:
    add ZL, digit                   ; Suma el dígito al puntero de la tabla
    brcc NO_CARRY_PATTERN           ; Si no hay acarreo, salta a NO_CARRY_PATTERN
    inc ZH                          ; Incrementa la parte alta si hay acarreo

NO_CARRY_PATTERN:
    lpm display_pat, Z              ; Lee el patrón del dígito de la tabla
    
    ; Mantiene el estado de los LEDs en PD7 al actualizar el display
    in temp, PORTD                  ; Lee el estado actual de PORTD
    andi temp, (1<<LED_BIT)         ; Mantiene solo el bit LED_BIT
    or display_pat, temp            ; Combina el patrón del display con el estado de los LEDs
    
    ; Aplica el patrón al display
    out PORTD, display_pat          ; Envía el patrón al puerto D
    
    ; Activa el display correspondiente
    lds temp, portc_shadow          ; Carga el estado actual guardado de PORTC
    andi temp, 0b00000011           ; Mantiene solo los bits 0-1 (buzzer y LED)
    or temp, mux_mask               ; Añade la máscara de multiplexión
    out PORTC, temp                 ; Actualiza el puerto C
	
    ; Incrementa selector para el siguiente ciclo
    lds temp, display_sel           ; Carga el selector de display
    inc temp                        ; Incrementa el selector
    cpi temp, 4                     ; Compara con 4
    brne SAVE_DISPLAY_SEL           ; Si no es igual, salta a SAVE_DISPLAY_SEL
    ldi temp, 0                     ; Reinicia a 0 cuando llega a 4
    
SAVE_DISPLAY_SEL:
    sts display_sel, temp           ; Guarda el nuevo valor del selector
    ret                             ; Retorna de la subrutina

;----------------------------------------------
; DELAY_MUX: Pequeño delay para multiplexación
;----------------------------------------------
DELAY_MUX:
    ldi temp, 50                  ; Carga el valor 50 en el registro 'temp' para contar el delay
DELAY_LOOP:
    dec temp                      ; Decrementa el valor de 'temp' en 1
    brne DELAY_LOOP               ; Si 'temp' no es cero, salta de nuevo a DELAY_LOOP
    ret                           ; Retorna de la subrutina una vez que el delay ha terminado

;***********************************************
; RUTINA DE INTERRUPCIÓN PARA BOTONES
;***********************************************
PCINT0_ISR:
    ; Guarda contexto
    push temp                   ; Guarda el registro 'temp' en la pila
    in temp, SREG               ; Lee el registro de estado (SREG) y lo guarda en 'temp'
    push temp                   ; Guarda el registro de estado en la pila
    push temp2                  ; Guarda el registro 'temp2' en la pila para preservar su valor
    
    ; Verificar si la alarma está sonando
    lds temp, alarma_sonando    ; Carga el estado de la alarma en 'temp'
    cpi temp, 0                  ; Compara 'temp' con 0 (alarma no sonando)
    breq CONTINUE_PCINT0        ; Si la alarma no está sonando, salta a CONTINUE_PCINT0
    
    ; La alarma está sonando, verificar si algún botón fue presionado
    in temp, PINB               ; Lee el estado de los botones en PORTB
    andi temp, 0x0F             ; Verifica solo los botones PB0-PB3
    cpi temp, 0x0F              ; Compara con 0x0F (ningún botón presionado)
    breq CONTINUE_PCINT0        ; Si no se presionó ningún botón, salta a CONTINUE_PCINT0
    
    ; Algún botón fue presionado, apagar la alarma
    ldi temp, 0                  ; Carga 0 en 'temp' para apagar la alarma
    sts alarma_sonando, temp     ; Establece el estado de la alarma como no sonando
    
    ; IMPORTANTE: También desactivar la alarma para que no se vuelva a activar automáticamente
    sts alarma_activa, temp      ; Establece el estado de la alarma como inactiva
    
    ; Usar registro sombra para apagar el buzzer
    lds temp, portc_shadow       ; Carga el estado actual guardado de PORTC
    andi temp, ~(1<<1)           ; Apaga el buzzer en PORTC1 (bit 1)
    sts portc_shadow, temp       ; Actualiza el registro sombra
    out PORTC, temp              ; Actualiza el puerto físico para apagar el buzzer
    
    rjmp PCINT0_EXIT             ; Salta a la salida de la rutina de interrupción

CONTINUE_PCINT0:
    ; Leer estado actual de PINB - Los botones están con pull-up (0 = presionado)
    in temp, PINB                ; Lee el estado de los botones en PORTB
    
    ; Botón MODO (PB3) - Verifica si está presionado (bit = 0)
    sbrc temp, BOTON_MODO        ; Salta si el bit correspondiente a BOTON_MODO está limpio (no presionado)
    rjmp CHECK_BOTONES_CONFIG    ; Si no está presionado, verifica otros botones
    
    ; El botón modo está presionado - cambiar modo
    lds temp, modo_reloj         ; Carga el modo actual en 'temp'
    inc temp                     ; Incrementa el modo
    cpi temp, 5                  ; Compara 'temp' con 5 (máximo modo)
    brne SAVE_MODO               ; Si no ha llegado a 5, guarda el nuevo modo
    ldi temp, 0                  ; Si llegó a 5, reinicia el modo a 0          ; Sí, volver a modo 0
    
SAVE_MODO:
    sts modo_reloj, temp              ; Guarda el nuevo modo en la variable 'modo_reloj'
    
    ; Apagar todos los LEDs de configuración por defecto
    cbi PORTB, LED_CONFIG_HORA       ; Apaga el LED de configuración de hora en PORTB
    cbi PORTB, LED_CONFIG_FECHA      ; Apaga el LED de configuración de fecha en PORTB
    
    ; Para el LED de alarma que está en PORTC, usar el registro sombra
    lds temp, portc_shadow            ; Carga el estado actual guardado de PORTC en 'temp'
    andi temp, ~(1<<LED_CONFIG_ALARMA); Apaga el bit correspondiente al LED de alarma
    sts portc_shadow, temp            ; Actualiza el registro sombra con el nuevo estado
    
    ; Si estamos en modo configuración hora (2), encender LED CONFIG_HORA
    lds temp, modo_reloj              ; Recarga el modo actual después de modificar el registro sombra
    cpi temp, 2                       ; Compara el modo con 2
    brne CHECK_MODO_3                 ; Si no es igual, salta a CHECK_MODO_3
    sbi PORTB, LED_CONFIG_HORA        ; Enciende el LED de configuración de hora
    rjmp CONTINUE_MODO_CHECK          ; Salta a CONTINUE_MODO_CHECK
    
CHECK_MODO_3:
    ; Si estamos en modo configuración fecha (3), encender LED CONFIG_FECHA
    cpi temp, 3                       ; Compara el modo con 3
    brne CHECK_MODO_4                 ; Si no es igual, salta a CHECK_MODO_4
    sbi PORTB, LED_CONFIG_FECHA       ; Enciende el LED de configuración de fecha
    rjmp CONTINUE_MODO_CHECK          ; Salta a CONTINUE_MODO_CHECK
    
CHECK_MODO_4:
    ; Si estamos en modo configuración alarma (4), encender LED CONFIG_ALARMA
    cpi temp, 4                       ; Compara el modo con 4
    brne CONTINUE_MODO_CHECK          ; Si no es igual, salta a CONTINUE_MODO_CHECK
    
    ; Usar registro sombra para encender LED
    lds temp, portc_shadow            ; Carga el estado actual guardado de PORTC en 'temp'
    ori temp, (1<<LED_CONFIG_ALARMA)  ; Enciende el bit correspondiente al LED de alarma
    sts portc_shadow, temp            ; Guarda el nuevo estado en el registro sombra
    
CONTINUE_MODO_CHECK:
    ; Si modo es 0 o 1, actualizar mostrar_fecha
    lds temp, modo_reloj              ; Recarga el modo para comprobar
    cpi temp, 2                       ; Compara el modo con 2
    brsh SALTAR_A_EXIT                ; Si el modo es mayor o igual a 2, salta a SALTAR_A_EXIT
    
    ; Si es 0 o 1, mostrar_fecha = modo_reloj
    sts mostrar_fecha, temp           ; Actualiza 'mostrar_fecha' con el valor de 'modo_reloj'
    rjmp PCINT0_EXIT                  ; Salta a la salida de la rutina de interrupción
    
SALTAR_A_EXIT:
    rjmp PCINT0_EXIT                  ; Salta a la salida de la rutina de interrupción
    
CHECK_BOTONES_CONFIG:
    ; Verificar si estamos en modo configuración (2, 3 o 4)
    lds temp, modo_reloj          ; Carga el modo actual en 'temp'
    cpi temp, 2                   ; Compara 'temp' con 2
    breq MODO_CONFIG_HORA         ; Si es modo 2, salta a MODO_CONFIG_HORA
    cpi temp, 3                   ; Compara 'temp' con 3
    breq MODO_CONFIG_FECHA        ; Si es modo 3, salta a MODO_CONFIG_FECHA
    cpi temp, 4                   ; Compara 'temp' con 4
    breq MODO_CONFIG_ALARMA_CHECK  ; Si es modo 4, salta a MODO_CONFIG_ALARMA_CHECK
    rjmp PCINT0_EXIT              ; Si no es ninguno de los modos de configuración, salir
    
MODO_CONFIG_ALARMA_CHECK:
    ; Estamos en modo 4 (configuración alarma)
    rjmp MODO_CONFIG_ALARMA       ; Salta a la rutina de configuración de alarma

MODO_CONFIG_HORA:
    ; Código original para modo 2 (configuración hora)
    ; Leer estado actual de los botones
    in temp, PINB                 ; Lee el estado de los botones en PORTB
    
    ; Botón SELECCIÓN (PB2)
    sbrc temp, BOTON_SELECCION     ; Salta si el botón SELECCIÓN NO está presionado
    rjmp CHECK_BOTON_INCREMENTO    ; Si está presionado, salta a CHECK_BOTON_INCREMENTO
    
    ; El botón selección está presionado
    lds temp, config_sel           ; Carga el estado de configuración en 'temp'
    ldi temp2, 1                   ; Carga 1 en 'temp2'
    eor temp, temp2                ; Invierte el estado de 'config_sel' (0 a 1 o 1 a 0)
    sts config_sel, temp           ; Guarda el nuevo estado de configuración
    rjmp PCINT0_EXIT               ; Salta a la salida de la rutina de interrupción

CHECK_BOTON_INCREMENTO:
    ; Botón INCREMENTO (PB0)
    in temp, PINB                 ; Lee el estado de los botones en PORTB
    sbrc temp, BOTON_INCREMENTO    ; Salta si el botón INCREMENTO NO está presionado
    rjmp CHECK_BOTON_DECREMENTO    ; Si está presionado, salta a CHECK_BOTON_DECREMENTO
    
    ; El botón incremento está presionado
    lds temp, config_sel           ; Carga el estado de configuración en 'temp'
    cpi temp, 0                    ; Compara 'temp' con 0
    brne INC_MINUTOS_MANUAL       ; Si no es 0, salta a INC_MINUTOS_MANUAL
    
    ; Incrementar horas manualmente
    rcall INCREMENTAR_HORAS_MANUAL ; Llama a la subrutina para incrementar horas manualmente
    rjmp PCINT0_EXIT               ; Salta a la salida de la rutina de interrupción
    
INC_MINUTOS_MANUAL:
    ; Incrementar minutos manualmente
    rcall INCREMENTAR_MINUTOS_MANUAL ; Llama a la subrutina para incrementar minutos manualmente
    rjmp PCINT0_EXIT               ; Salta a la salida de la rutina de interrupción
    
CHECK_BOTON_DECREMENTO:
    ; Botón DECREMENTO (PB1)
    in temp, PINB                 ; Lee el estado de los botones en PORTB
    sbrc temp, BOTON_DECREMENTO    ; Salta si el botón DECREMENTO NO está presionado
    rjmp PCINT0_EXIT               ; Si está presionado, salta a la salida de la rutina de interrupción
    
    ; El botón decremento está presionado
    lds temp, config_sel           ; Carga el estado de configuración en 'temp'
    cpi temp, 0                    ; Compara 'temp' con 0
    brne DEC_MINUTOS_MANUAL       ; Si no es 0, salta a DEC_MINUTOS_MANUAL
    
    ; Decrementar horas manualmente
    rcall DECREMENTAR_HORAS_MANUAL ; Llama a la subrutina para decrementar horas manualmente
    rjmp PCINT0_EXIT               ; Salta a la salida de la rutina de interrupción
    
DEC_MINUTOS_MANUAL:
    ; Decrementar minutos manualmente
    rcall DECREMENTAR_MINUTOS_MANUAL ; Llama a la subrutina para decrementar minutos manualmente

MODO_CONFIG_FECHA:
    ; Estamos en modo 3 (configuración fecha)
    ; Leer estado actual de los botones
    in temp, PINB                 ; Lee el estado de los botones en PORTB
    
    ; Botón SELECCIÓN (PB2)
    sbrc temp, BOTON_SELECCION     ; Salta si el botón SELECCIÓN NO está presionado
    rjmp CHECK_FECHA_INCREMENTO    ; Si está presionado, salta a CHECK_FECHA_INCREMENTO
    
    ; El botón selección está presionado en modo 3
    lds temp, config_sel           ; Carga el estado de configuración en 'temp'
    ldi temp2, 1                   ; Carga 1 en 'temp2'
    eor temp, temp2                ; Invierte el estado de 'config_sel' (0 = días, 1 = meses)
    sts config_sel, temp           ; Guarda el nuevo estado de configuración
    rjmp PCINT0_EXIT               ; Salta a la salida de la rutina de interrupción

CHECK_FECHA_INCREMENTO:
    ; Botón INCREMENTO (PB0)
    in temp, PINB                 ; Lee el estado de los botones en PORTB
    sbrc temp, BOTON_INCREMENTO    ; Salta si el botón INCREMENTO NO está presionado
    rjmp CHECK_FECHA_DECREMENTO    ; Si está presionado, salta a CHECK_FECHA_DECREMENTO
    
    ; El botón incremento está presionado
    lds temp, config_sel           ; Carga el estado de configuración en 'temp'
    cpi temp, 0                    ; Compara 'temp' con 0
    brne INC_MESES_MANUAL         ; Si no es 0, salta a INC_MESES_MANUAL
    
    ; Incrementar días manualmente
    rcall INCREMENTAR_DIAS_MANUAL  ; Llama a la subrutina para incrementar días manualmente
    rjmp PCINT0_EXIT               ; Salta a la salida de la rutina de interrupción
    
INC_MESES_MANUAL:
    ; Incrementar meses manualmente
    rcall INCREMENTAR_MESES_MANUAL  ; Llama a la subrutina para incrementar meses manualmente
    rjmp PCINT0_EXIT               ; Salta a la salida de la rutina de interrupción
    
CHECK_FECHA_DECREMENTO:
    ; Botón DECREMENTO (PB1)
    in temp, PINB                 ; Lee el estado de los botones en PORTB
    sbrc temp, BOTON_DECREMENTO    ; Salta si el botón DECREMENTO NO está presionado
    rjmp PCINT0_EXIT               ; Si está presionado, salta a la salida de la rutina de interrupción
    
    ; El botón decremento está presionado
    lds temp, config_sel           ; Carga el estado de configuración en 'temp'
    cpi temp, 0                    ; Compara 'temp' con 0
    brne DEC_MESES_MANUAL         ; Si no es 0, salta a DEC_MESES_MANUAL
    
    ; Decrementar días manualmente
    rcall DECREMENTAR_DIAS_MANUAL  ; Llama a la subrutina para decrementar días manualmente
    rjmp PCINT0_EXIT               ; Salta a la salida de la rutina de interrupción
    
DEC_MESES_MANUAL:
    ; Decrementar meses manualmente
    rcall DECREMENTAR_MESES_MANUAL  ; Llama a la subrutina para decrementar meses manualmente
    rjmp PCINT0_EXIT               ; Salta a la salida de la rutina de interrupción

MODO_CONFIG_ALARMA:
    ; Estamos en modo 4 (configuración alarma)
    ; Leer estado actual de los botones
    in temp, PINB                 ; Lee el estado de los botones en PORTB
    
    ; Botón SELECCIÓN (PB2)
    sbrc temp, BOTON_SELECCION     ; Salta si el botón SELECCIÓN NO está presionado
    rjmp CHECK_ALARMA_INCREMENTO    ; Si está presionado, salta a CHECK_ALARMA_INCREMENTO
    
    ; El botón selección está presionado en modo 4
    lds temp, config_sel           ; Carga el estado de configuración en 'temp'
    ldi temp2, 1                   ; Carga 1 en 'temp2'
    eor temp, temp2                ; Invierte el estado de 'config_sel' (0 = horas, 1 = minutos)
    sts config_sel, temp           ; Guarda el nuevo estado de configuración
    rjmp PCINT0_EXIT               ; Salta a la salida de la rutina de interrupción

CHECK_ALARMA_INCREMENTO:
    ; Botón INCREMENTO (PB0)
    in temp, PINB                 ; Lee el estado de los botones en PORTB
    sbrc temp, BOTON_INCREMENTO    ; Salta si el botón INCREMENTO NO está presionado
    rjmp CHECK_ALARMA_DECREMENTO    ; Si está presionado, salta a CHECK_ALARMA_DECREMENTO
    
    ; El botón incremento está presionado
    lds temp, config_sel           ; Carga el estado de configuración en 'temp'
    cpi temp, 0                    ; Compara 'temp' con 0
    brne INC_ALARMA_MINUTOS       ; Si no es 0, salta a INC_ALARMA_MINUTOS
    
    ; Incrementar horas de alarma
    rcall INCREMENTAR_HORAS_ALARMA ; Llama a la subrutina para incrementar horas de alarma
    rjmp PCINT0_EXIT               ; Salta a la salida de la rutina de interrupción
    
INC_ALARMA_MINUTOS:
    ; Incrementar minutos de alarma
    rcall INCREMENTAR_MINUTOS_ALARMA ; Llama a la subrutina para incrementar minutos de alarma
    rjmp PCINT0_EXIT               ; Salta a la salida de la rutina de interrupción
    
CHECK_ALARMA_DECREMENTO:
    ; Botón DECREMENTO (PB1)
    in temp, PINB                 ; Lee el estado de los botones en PORTB
    sbrc temp, BOTON_DECREMENTO    ; Salta si el botón DECREMENTO NO está presionado
    rjmp PCINT0_EXIT               ; Si está presionado, salta a la salida de la rutina de interrupción
    
    ; El botón decremento está presionado
    lds temp, config_sel           ; Carga el estado de configuración en 'temp'
    cpi temp, 0                    ; Compara 'temp' con 0
    brne DEC_ALARMA_MINUTOS       ; Si no es 0, salta a DEC_ALARMA_MINUTOS
    
    ; Decrementar horas de alarma
    rcall DECREMENTAR_HORAS_ALARMA ; Llama a la subrutina para decrementar horas de alarma
    rjmp PCINT0_EXIT               ; Salta a la salida de la rutina de interrupción
    
DEC_ALARMA_MINUTOS:
    ; Decrementar minutos de alarma
    rcall DECREMENTAR_MINUTOS_ALARMA ; Llama a la subrutina para decrementar minutos de alarma
    rjmp PCINT0_EXIT               ; Salta a la salida de la rutina de interrupción

PCINT0_EXIT:
    ; Restaura contexto
    pop temp2                      ; Restaura el registro 'temp2' de la pila
    pop temp                       ; Restaura el registro 'temp' de la pila
    out SREG, temp                 ; Restaura el registro de estado (SREG)
    pop temp                       ; Restaura el registro 'temp' de la pila
    reti                           ; Retorna de la interrupción

;***********************************************
; RUTINA DE INTERRUPCIÓN DEL TIMER0
;***********************************************
TMR0_ISR:
    ; Guarda contexto
    push temp                   ; Guarda el registro 'temp' en la pila
    in temp, SREG               ; Lee el registro de estado (SREG) y lo guarda en 'temp'
    push temp                   ; Guarda el registro de estado en la pila
    push temp2                  ; Guarda el registro 'temp2' en la pila
    push ZL                     ; Guarda la parte baja del registro Z en la pila
    push ZH                     ; Guarda la parte alta del registro Z en la pila

    lds temp, alarma_sonando    ; Carga el estado de la alarma en 'temp'
    cpi temp, 1                 ; Compara 'temp' con 1 (alarma sonando)
    brne CONTINUE_TMR0         ; Si no está sonando, salta a CONTINUE_TMR0
    
    ; Toggle el bit del buzzer en portc_shadow
    lds temp, portc_shadow      ; Carga el estado actual guardado de PORTC en 'temp'
    ldi temp2, (1 << BUZZER)    ; Carga el bit correspondiente al buzzer en 'temp2'
    eor temp, temp2             ; Invierte el estado del buzzer (toggle)
    sts portc_shadow, temp      ; Actualiza el registro sombra con el nuevo estado



CONTINUE_TMR0:  
    ; Incrementa contador para parpadeo de LEDs
    lds temp, led_counter        ; Carga el contador de LEDs en 'temp'
    inc temp                     ; Incrementa el contador
    sts led_counter, temp        ; Guarda el nuevo valor del contador
    
    ldi temp2, 30               ; Carga 30 en 'temp2' (aproximadamente 500ms)
    cp temp, temp2              ; Compara el contador de LEDs con 30
    brne SKIP_LED_TOGGLE        ; Si no es igual, salta a SKIP_LED_TOGGLE
    
    ; Reinicia contador de LEDs
    ldi temp, 0                  ; Carga 0 en 'temp'
    sts led_counter, temp        ; Reinicia el contador de LEDs
    
    ; Invierte estado de los LEDs en PD7
    lds temp, led_state          ; Carga el estado actual de los LEDs en 'temp'
    ldi temp2, 1                 ; Carga 1 en 'temp2'
    eor temp, temp2              ; Invierte el bit 0 del estado de los LEDs
    sts led_state, temp          ; Guarda el nuevo estado de los LEDs
    
    ; Aplicar estado a los LEDs
    cpi temp, 0                  ; Compara el estado de los LEDs con 0
    breq LEDS_OFF                ; Si es 0, salta a LEDS_OFF
    
    ; Encender LEDs (PD7)
    in temp, PORTD              ; Lee el estado actual de PORTD
    ori temp, (1<<LED_BIT)      ; Enciende el bit correspondiente a los LEDs
    out PORTD, temp             ; Actualiza el puerto D con el nuevo estado
    rjmp SKIP_LED_TOGGLE        ; Salta a SKIP_LED_TOGGLE
    
LEDS_OFF:
    ; Apagar LEDs (PD7)
    in temp, PORTD              ; Lee el estado actual de PORTD
    andi temp, ~(1<<LED_BIT)    ; Apaga el bit correspondiente a los LEDs
    out PORTD, temp             ; Actualiza el puerto D con el nuevo estado
    
SKIP_LED_TOGGLE:
    ; Verificar si estamos en modo configuración
    lds temp, modo_reloj        ; Carga el modo actual en 'temp'
    cpi temp, 2                 ; Compara 'temp' con 2
    breq TMR0_EXIT              ; Si estamos en modo configuración, salta a TMR0_EXIT
    
    ; Continúa con el contador de tiempo normal solo si NO estamos en configuración
    lds temp, timer_count       ; Carga el contador de tiempo en 'temp'
    inc temp                    ; Incrementa el contador
    sts timer_count, temp       ; Guarda el nuevo valor del contador
    
    ldi temp2, VALOR_COMPARACION ; Carga el valor de comparación (aproximadamente 1 segundo)
    cp temp, temp2             ; Compara el contador de tiempo con el valor de comparación
    brne TMR0_EXIT              ; Si no es igual, salta a TMR0_EXIT
    
    ; Reinicia contador y maneja tiempo
    ldi temp, 0                  ; Carga 0 en 'temp'
    sts timer_count, temp        ; Reinicia el contador de tiempo
    rcall INCREMENTAR_SEGUNDOS   ; Llama a la subrutina para incrementar los segundos

TMR0_EXIT:
    ; Restaura contexto
    pop ZH                       ; Restaura la parte alta del registro Z de la pila
    pop ZL                       ; Restaura la parte baja del registro Z de la pila
    pop temp2                    ; Restaura el registro 'temp2' de la pila
    pop temp                     ; Restaura el registro 'temp' de la pila
    out SREG, temp               ; Restaura el registro de estado (SREG)
    pop temp                     ; Restaura el registro 'temp' de la pila
    reti                         ; Retorna de la interrupción

;***********************************************
; SUBRUTINAS DE MANEJO DE TIEMPO
;***********************************************
;----------------------------------------------
; INCREMENTAR_SEGUNDOS: Incrementa segundos y actualiza tiempo
;----------------------------------------------
INCREMENTAR_SEGUNDOS:
    lds temp, segundos            ; Carga el valor actual de segundos en 'temp'
    inc temp                      ; Incrementa el contador de segundos
    sts segundos, temp            ; Guarda el nuevo valor de segundos
    
    cpi temp, 60                  ; Compara 'temp' con 60
    brne CHECK_ALARMA             ; Si no es 60, salta a CHECK_ALARMA
    
    ; Si pasaron 60 segundos, incrementar minutos
    ldi temp, 0                   ; Carga 0 en 'temp' para reiniciar segundos
    sts segundos, temp            ; Reinicia el contador de segundos
    rcall INCREMENTAR_MINUTOS     ; Llama a la subrutina para incrementar minutos
    rjmp CHECK_ALARMA             ; Salta incondicionalmente a CHECK_ALARMA
    
CHECK_ALARMA:
    ; Verificar si la alarma está activa
    lds temp, alarma_activa       ; Carga el estado de la alarma activa en 'temp'
    cpi temp, 1                   ; Compara 'temp' con 1 (alarma activa)
    brne EXIT_INC_SEGUNDOS        ; Si la alarma no está activa, salir
    
    ; Obtener el estado actual de alarma_sonando
    lds temp, alarma_sonando      ; Carga el estado de la alarma sonando en 'temp'
    cpi temp, 1                   ; Compara 'temp' con 1 (alarma sonando)
    breq EXIT_INC_SEGUNDOS        ; Si ya está sonando, salir
    
    ; Comparar hora y minutos
    lds temp, hora_decenas        ; Carga las decenas de la hora en 'temp'
    lds temp2, alarma_hora_decenas; Carga las decenas de la alarma en 'temp2'
    cp temp, temp2                ; Compara las decenas de la hora con las de la alarma
    brne EXIT_INC_SEGUNDOS        ; Si no son iguales, salir
    
    lds temp, hora_unidades       ; Carga las unidades de la hora en 'temp'
    lds temp2, alarma_hora_unidades; Carga las unidades de la alarma en 'temp2'
    cp temp, temp2                ; Compara las unidades de la hora con las de la alarma
    brne EXIT_INC_SEGUNDOS        ; Si no son iguales, salir
    
    lds temp, min_decenas         ; Carga las decenas de minutos en 'temp'
    lds temp2, alarma_min_decenas ; Carga las decenas de minutos de la alarma en 'temp2'
    cp temp, temp2                ; Compara las decenas de minutos
    brne EXIT_INC_SEGUNDOS        ; Si no son iguales, salir
    
    lds temp, min_unidades        ; Carga las unidades de minutos en 'temp'
    lds temp2, alarma_min_unidades; Carga las unidades de minutos de la alarma en 'temp2'
    cp temp, temp2                ; Compara las unidades de minutos
    brne EXIT_INC_SEGUNDOS        ; Si no son iguales, salir
    
    ; Si todas las condiciones se cumplen, activar la alarma
    ldi temp, 1                   ; Carga 1 en 'temp' para activar la alarma
    sts alarma_sonando, temp      ; Establece el estado de la alarma como sonando
    
EXIT_INC_SEGUNDOS:
    ret                            ; Retorna de la subrutina

;----------------------------------------------
; INCREMENTAR_MINUTOS: Incrementa minutos
;----------------------------------------------
INCREMENTAR_MINUTOS:
    lds temp, min_unidades        ; Carga el valor actual de las unidades de minutos en 'temp'
    inc temp                      ; Incrementa el contador de minutos
    sts min_unidades, temp        ; Guarda el nuevo valor de las unidades de minutos
    
    cpi temp, 10                  ; Compara 'temp' con 10
    brne EXIT_INC_MINUTOS        ; Si no es 10, salir
    
    ; Si las unidades llegaron a 10
    ldi temp, 0                   ; Carga 0 en 'temp' para reiniciar las unidades de minutos
    sts min_unidades, temp        ; Reinicia las unidades de minutos
    rcall INCREMENTAR_MIN_DECENAS ; Llama a la subrutina para incrementar las decenas de minutos
    
EXIT_INC_MINUTOS:
    ret                            ; Retorna de la subrutina

;----------------------------------------------
; INCREMENTAR_MIN_DECENAS: Incrementa decenas de minutos
;----------------------------------------------
INCREMENTAR_MIN_DECENAS:
    lds temp, min_decenas         ; Carga el valor actual de las decenas de minutos en 'temp'
    inc temp                      ; Incrementa el contador de decenas de minutos
    sts min_decenas, temp         ; Guarda el nuevo valor de las decenas de minutos
    
    cpi temp, 6                   ; Compara 'temp' con 6
    brne EXIT_INC_MIN_DECENAS     ; Si no es 6, salta a EXIT_INC_MIN_DECENAS
    
    ; Si las decenas llegaron a 6 (60 minutos)
    ldi temp, 0                   ; Carga 0 en 'temp' para reiniciar las decenas de minutos
    sts min_decenas, temp         ; Reinicia las decenas de minutos
    rcall INCREMENTAR_HORAS       ; Llama a la subrutina para incrementar las horas
    
EXIT_INC_MIN_DECENAS:
    ret                            ; Retorna de la subrutina

;----------------------------------------------
; INCREMENTAR_HORAS: Incrementa horas
;----------------------------------------------
INCREMENTAR_HORAS:
    lds temp, hora_unidades        ; Carga el valor actual de las unidades de horas en 'temp'
    inc temp                       ; Incrementa el contador de horas
    sts hora_unidades, temp        ; Guarda el nuevo valor de las unidades de horas
    
    cpi temp, 10                   ; Compara 'temp' con 10
    brne CHECK_24_HORAS           ; Si no es 10, salta a CHECK_24_HORAS
    
    ; Si las unidades llegaron a 10
    ldi temp, 0                    ; Carga 0 en 'temp' para reiniciar las unidades de horas
    sts hora_unidades, temp        ; Reinicia las unidades de horas
    
    lds temp, hora_decenas         ; Carga el valor actual de las decenas de horas en 'temp'
    inc temp                       ; Incrementa el contador de decenas de horas
    sts hora_decenas, temp         ; Guarda el nuevo valor de las decenas de horas
    ret                             ; Retorna de la subrutina
    
CHECK_24_HORAS:
    ; Verifica si llegamos a 24 horas
    lds temp, hora_decenas         ; Carga el valor actual de las decenas de horas en 'temp'
    cpi temp, 2                    ; Compara 'temp' con 2
    brne EXIT_INC_HORAS            ; Si no es 2, salta a EXIT_INC_HORAS
    
    lds temp, hora_unidades        ; Carga el valor actual de las unidades de horas en 'temp'
    cpi temp, 4                    ; Compara 'temp' con 4 (24 horas)
    brne EXIT_INC_HORAS            ; Si no es 4, salta a EXIT_INC_HORAS
    
    ; Reinicia el reloj a 00:00
    ldi temp, 0                    ; Carga 0 en 'temp' para reiniciar las horas
    sts hora_unidades, temp        ; Reinicia las unidades de horas
    sts hora_decenas, temp         ; Reinicia las decenas de horas
    
    ; Ahora incrementa el día al pasar 24 horas
    rcall INCREMENTAR_DIA          ; Llama a la subrutina para incrementar el día
    
EXIT_INC_HORAS:
    ret                             ; Retorna de la subrutina

;----------------------------------------------
; INCREMENTAR_DIA: Incrementa días y maneja cambios de mes
;----------------------------------------------
INCREMENTAR_DIA:
    ; Incrementa el día
    lds temp, dia_unidades         ; Carga el valor actual de las unidades de día en 'temp'
    inc temp                       ; Incrementa el contador de días
    sts dia_unidades, temp         ; Guarda el nuevo valor de las unidades de día
    
    cpi temp, 10                   ; Compara 'temp' con 10
    brne CHECK_LIMITE_DIA         ; Si no es 10, salta a CHECK_LIMITE_DIA
    
    ; Si las unidades llegaron a 10
    ldi temp, 0                    ; Carga 0 en 'temp' para reiniciar las unidades de día
    sts dia_unidades, temp         ; Reinicia las unidades de día
    
    ; Incrementa decenas de día
    lds temp, dia_decenas          ; Carga el valor actual de las decenas de día en 'temp'
    inc temp                       ; Incrementa el contador de decenas de día
    sts dia_decenas, temp          ; Guarda el nuevo valor de las decenas de día
    
CHECK_LIMITE_DIA:
    ; Verifica qué mes es para saber el límite de días
    lds temp, mes_decenas          ; Carga el valor de las decenas del mes en 'temp'
    cpi temp, 0                    ; Compara 'temp' con 0
    brne CHECK_OCTUBRE_DICIEMBRE   ; Si es 1, salta a CHECK_OCTUBRE_DICIEMBRE
    
    ; Para meses del 1 al 9
    lds temp, mes_unidades         ; Carga el valor de las unidades del mes en 'temp'
    cpi temp, 2                    ; Compara con 2 (Febrero)
    breq FEBRERO                   ; Si es Febrero, salta a la rutina de manejo de Febrero
    
    cpi temp, 4                    ; Compara con 4 (Abril)
    breq MES_30_DIAS               ; Si es Abril, salta a la rutina de 30 días
    
    cpi temp, 6                    ; Compara con 6 (Junio)
    breq MES_30_DIAS               ; Si es Junio, salta a la rutina de 30 días
    
    cpi temp, 9                    ; Compara con 9 (Septiembre)
    breq MES_30_DIAS               ; Si es Septiembre, salta a la rutina de 30 días
    
    ; Meses de 31 días (Enero, Marzo, Mayo, Julio, Agosto)
    rjmp MES_31_DIAS               ; Salta a la rutina de 31 días
    
CHECK_OCTUBRE_DICIEMBRE:
    lds temp, mes_unidades         ; Carga el valor de las unidades del mes en 'temp'
    cpi temp, 1                    ; Compara con 1 (Noviembre)
    breq MES_30_DIAS               ; Si es Noviembre, salta a la rutina de 30 días
    
    ; Meses de 31 días (Octubre y Diciembre)
    rjmp MES_31_DIAS               ; Salta a la rutina de 31 días
    
FEBRERO:
    ; Febrero tiene 28 días (no implementamos años bisiestos)
    lds temp, dia_decenas          ; Carga el valor de las decenas de día en 'temp'
    cpi temp, 2                    ; Compara con 2 (días 20-29)
    brne CHECK_FEBRERO_UNIDADES    ; Si no es 2, salta a CHECK_FEBRERO_UNIDADES
    
    lds temp, dia_unidades         ; Carga el valor de las unidades de día en 'temp'
    cpi temp, 9                    ; Compara con 9 (día 29)
    brne EXIT_INCREMENTAR_DIA      ; Si no es 29, salir
    
    ; Reinicia a día 1 e incrementa mes
    ldi temp, 1                    ; Carga 1 en 'temp' para reiniciar el día
    sts dia_unidades, temp         ; Establece el día a 1
    ldi temp, 0                    ; Carga 0 en 'temp' para reiniciar decenas de día
    sts dia_decenas, temp          ; Establece las decenas de día a 0
    rjmp INCREMENTAR_MES           ; Llama a la subrutina para incrementar el mes
    
CHECK_FEBRERO_UNIDADES:
    cpi temp, 3                    ; Compara con 3 (se pasó de 28)
    brne EXIT_INCREMENTAR_DIA      ; Si no es 3, salir
    
    ; Reinicia a día 1 e incrementa mes
    ldi temp, 1                    ; Carga 1 en 'temp' para reiniciar el día
    sts dia_unidades, temp         ; Establece el día a 1
    ldi temp, 0                    ; Carga 0 en 'temp' para reiniciar decenas de día
    sts dia_decenas, temp          ; Establece las decenas de día a 0
    rjmp INCREMENTAR_MES           ; Llama a la subrutina para incrementar el mes
    
MES_30_DIAS:
    ; Verifica si llegamos a 31 (día 31)
    lds temp, dia_decenas          ; Carga el valor de las decenas de día en 'temp'
    cpi temp, 3                    ; Compara con 3 (días 30-31)
    brne CHECK_30_DIAS_UNIDADES     ; Si no es 3, salta a CHECK_30_DIAS_UNIDADES
    
    lds temp, dia_unidades         ; Carga el valor de las unidades de día en 'temp'
    cpi temp, 1                    ; Compara con 1 (día 31)
    brne EXIT_INCREMENTAR_DIA      ; Si no es 31, salir
    
    ; Reinicia a día 1 e incrementa mes
    ldi temp, 1                    ; Carga 1 en 'temp' para reiniciar el día
    sts dia_unidades, temp         ; Establece el día a 1
    ldi temp, 0                    ; Carga 0 en 'temp' para reiniciar decenas de día
    sts dia_decenas, temp          ; Establece las decenas de día a 0
    rjmp INCREMENTAR_MES           ; Llama a la subrutina para incrementar el mes
    
CHECK_30_DIAS_UNIDADES:
    cpi temp, 4                    ; Compara con 4 (se pasó de 30)
    brne EXIT_INCREMENTAR_DIA      ; Si no es 4, salir
    
    ; Reinicia a día 1 e incrementa mes
    ldi temp, 1                    ; Carga 1 en 'temp' para reiniciar el día
    sts dia_unidades, temp         ; Establece el día a 1
    ldi temp, 0                    ; Carga 0 en 'temp' para reiniciar decenas de día
    sts dia_decenas, temp          ; Establece las decenas de día a 0
    rjmp INCREMENTAR_MES           ; Llama a la subrutina para incrementar el mes
    
MES_31_DIAS:
    ; Verifica si llegamos a 32 (día 32)
    lds temp, dia_decenas          ; Carga el valor de las decenas de día en 'temp'
    cpi temp, 3                    ; Compara con 3 (días 31-32)
    brne EXIT_INCREMENTAR_DIA      ; Si no es 3, salir
    
    lds temp, dia_unidades         ; Carga el valor de las unidades de día en 'temp'
    cpi temp, 2                    ; Compara con 2 (día 32)
    brne EXIT_INCREMENTAR_DIA      ; Si no es 32, salir
    
    ; Reinicia a día 1 e incrementa mes
    ldi temp, 1                    ; Carga 1 en 'temp' para reiniciar el día
    sts dia_unidades, temp         ; Establece el día a 1
    ldi temp, 0                    ; Carga 0 en 'temp' para reiniciar decenas de día
    sts dia_decenas, temp          ; Establece las decenas de día a 0
    rjmp INCREMENTAR_MES           ; Llama a la subrutina para incrementar el mes
    
EXIT_INCREMENTAR_DIA:
    ret                             ; Retorna de la subrutina

;----------------------------------------------
; INCREMENTAR_MES: Incrementa el mes y maneja cambio de año
;----------------------------------------------
INCREMENTAR_MES:
    lds temp, mes_unidades         ; Carga el valor actual de las unidades del mes en 'temp'
    inc temp                       ; Incrementa el contador de unidades del mes
    sts mes_unidades, temp         ; Guarda el nuevo valor de las unidades del mes
    
    cpi temp, 10                   ; Compara 'temp' con 10
    brne CHECK_LIMITE_MES         ; Si no es 10, salta a CHECK_LIMITE_MES
    
    ; Si las unidades llegaron a 10
    ldi temp, 0                    ; Carga 0 en 'temp' para reiniciar las unidades del mes
    sts mes_unidades, temp         ; Reinicia las unidades del mes
    
    ; Incrementa decenas de mes
    lds temp, mes_decenas          ; Carga el valor actual de las decenas del mes en 'temp'
    inc temp                       ; Incrementa el contador de decenas del mes
    sts mes_decenas, temp          ; Guarda el nuevo valor de las decenas del mes
    
CHECK_LIMITE_MES:
    ; Verifica si llegamos a mes 13
    lds temp, mes_decenas          ; Carga el valor actual de las decenas del mes en 'temp'
    cpi temp, 1                    ; Compara 'temp' con 1
    brne EXIT_INCREMENTAR_MES      ; Si no es 1, salta a EXIT_INCREMENTAR_MES
    
    lds temp, mes_unidades         ; Carga el valor actual de las unidades del mes en 'temp'
    cpi temp, 3                    ; Compara 'temp' con 3 (mes 13)
    brne EXIT_INCREMENTAR_MES      ; Si no es 3, salta a EXIT_INCREMENTAR_MES
    
    ; Reinicia a mes 1 (Enero)
    ldi temp, 1                    ; Carga 1 en 'temp' para establecer el mes a Enero
    sts mes_unidades, temp         ; Establece las unidades del mes a 1
    ldi temp, 0                    ; Carga 0 en 'temp' para reiniciar las decenas del mes
    sts mes_decenas, temp          ; Establece las decenas del mes a 0
    
    ; Aquí podría incrementarse el año si se implementara
    
EXIT_INCREMENTAR_MES:
    ret                             ; Retorna de la subrutina

;----------------------------------------------
; INCREMENTAR_MINUTOS_MANUAL: Incrementa minutos manualmente (para configuración)
;----------------------------------------------
INCREMENTAR_MINUTOS_MANUAL:
    lds temp, min_unidades         ; Carga el valor actual de las unidades de minutos en 'temp'
    inc temp                       ; Incrementa el contador de unidades de minutos
    cpi temp, 10                   ; Compara 'temp' con 10
    brne SAVE_MIN_UNIT_INC         ; Si no es 10, salta a SAVE_MIN_UNIT_INC
    
    ; Si llegó a 10, resetear unidades e incrementar decenas
    ldi temp, 0                    ; Carga 0 en 'temp' para reiniciar las unidades de minutos
    sts min_unidades, temp         ; Reinicia las unidades de minutos
    
    lds temp, min_decenas          ; Carga el valor actual de las decenas de minutos en 'temp'
    inc temp                       ; Incrementa el contador de decenas de minutos
    cpi temp, 6                    ; Compara 'temp' con 6
    brne SAVE_MIN_DEC_INC          ; Si no es 6, salta a SAVE_MIN_DEC_INC
    
    ; Si llegó a 6, resetear decenas
    ldi temp, 0                    ; Carga 0 en 'temp' para reiniciar las decenas de minutos
    
SAVE_MIN_DEC_INC:
    sts min_decenas, temp          ; Guarda el nuevo valor de las decenas de minutos
    ret                             ; Retorna de la subrutina
    
SAVE_MIN_UNIT_INC:
    sts min_unidades, temp         ; Guarda el nuevo valor de las unidades de minutos
    ret                             ; Retorna de la subrutina

;----------------------------------------------
; DECREMENTAR_MINUTOS_MANUAL: Decrementa minutos manualmente (para configuración)
;----------------------------------------------
DECREMENTAR_MINUTOS_MANUAL:
    lds temp, min_unidades         ; Carga el valor actual de las unidades de minutos en 'temp'
    cpi temp, 0                    ; Compara 'temp' con 0
    brne DEC_MIN_UNIT              ; Si no es 0, salta a DEC_MIN_UNIT
    
    ; Si era 0, poner a 9 y decrementar decenas
    ldi temp, 9                    ; Carga 9 en 'temp' para establecer las unidades de minutos
    sts min_unidades, temp         ; Establece las unidades de minutos a 9
    
    lds temp, min_decenas          ; Carga el valor actual de las decenas de minutos en 'temp'
    cpi temp, 0                    ; Compara 'temp' con 0
    brne DEC_MIN_DEC               ; Si no es 0, salta a DEC_MIN_DEC
    
    ; Si decenas era 0, poner a 5
    ldi temp, 6                    ; Carga 6 en 'temp' para establecer las decenas de minutos a 6
    
DEC_MIN_DEC:
    dec temp                       ; Decrementa el contador de decenas de minutos
    sts min_decenas, temp          ; Guarda el nuevo valor de las decenas de minutos
    ret                             ; Retorna de la subrutina
    
DEC_MIN_UNIT:
    dec temp                       ; Decrementa el contador de unidades de minutos
    sts min_unidades, temp         ; Guarda el nuevo valor de las unidades de minutos
    ret                             ; Retorna de la subrutina

;----------------------------------------------
; INCREMENTAR_HORAS_MANUAL: Incrementa horas manualmente (para configuración)
;----------------------------------------------
INCREMENTAR_HORAS_MANUAL:
    lds temp, hora_unidades         ; Carga el valor actual de las unidades de horas en 'temp'
    inc temp                        ; Incrementa el contador de unidades de horas
    cpi temp, 10                    ; Compara 'temp' con 10
    brne CHECK_MAX_HORA_INC         ; Si no es 10, salta a CHECK_MAX_HORA_INC
    
    ; Si llegó a 10, resetear unidades e incrementar decenas
    ldi temp, 0                     ; Carga 0 en 'temp' para reiniciar las unidades de horas
    sts hora_unidades, temp         ; Reinicia las unidades de horas
    
    lds temp, hora_decenas          ; Carga el valor actual de las decenas de horas en 'temp'
    inc temp                        ; Incrementa el contador de decenas de horas
    cpi temp, 3                     ; Máximo 2 para formato 24h
    brne SAVE_HORA_DEC_INC          ; Si no es 3, salta a SAVE_HORA_DEC_INC
    
    ; Si llegó a 3, resetear decenas
    ldi temp, 0                     ; Carga 0 en 'temp' para reiniciar las decenas de horas
    
SAVE_HORA_DEC_INC:
    sts hora_decenas, temp          ; Guarda el nuevo valor de las decenas de horas
    ret                              ; Retorna de la subrutina
    
CHECK_MAX_HORA_INC:
    ; Verificar si superamos 23 horas
    lds temp2, hora_decenas         ; Carga el valor actual de las decenas de horas en 'temp2'
    cpi temp2, 2                    ; Compara 'temp2' con 2
    brne SAVE_HORA_UNIT_INC         ; Si no es 2, salta a SAVE_HORA_UNIT_INC
    
    ; Si decenas es 2, unidades no puede ser mayor que 3
    cpi temp, 4                     ; Compara 'temp' con 4
    brlo SAVE_HORA_UNIT_INC         ; Si es menor que 4, salta a SAVE_HORA_UNIT_INC
    
    ; Si llegó a 24, resetear a 00
    ldi temp, 0                     ; Carga 0 en 'temp' para reiniciar las unidades de horas
    sts hora_unidades, temp         ; Establece las unidades de horas a 0
    sts hora_decenas, temp          ; Establece las decenas de horas a 0
    ret                              ; Retorna de la subrutina
    
SAVE_HORA_UNIT_INC:
    sts hora_unidades, temp         ; Guarda el nuevo valor de las unidades de horas
    ret                              ; Retorna de la subrutina

;----------------------------------------------
; DECREMENTAR_HORAS_MANUAL: Decrementa horas manualmente (para configuración)
;----------------------------------------------
DECREMENTAR_HORAS_MANUAL:
    lds temp, hora_unidades         ; Carga el valor actual de las unidades de horas en 'temp'
    cpi temp, 0                     ; Compara 'temp' con 0
    brne DEC_HORA_UNIT              ; Si no es 0, salta a DEC_HORA_UNIT
    
    ; Si unidades era 0
    lds temp2, hora_decenas         ; Carga el valor actual de las decenas de horas en 'temp2'
    cpi temp2, 0                    ; Compara 'temp2' con 0
    brne DEC_DESDE_X0               ; Si no es 0, salta a DEC_DESDE_X0
    
    ; Si estamos en 00, ir a 23
    ldi temp, 3                     ; Carga 3 en 'temp' para establecer las unidades de horas a 3
    sts hora_unidades, temp         ; Establece las unidades de horas a 3
    ldi temp2, 2                    ; Carga 2 en 'temp2' para establecer las decenas de horas a 2
    sts hora_decenas, temp2         ; Establece las decenas de horas a 2
    ret                              ; Retorna de la subrutina
    
DEC_DESDE_X0:
    ; Si unidades = 0 y decenas > 0
    ldi temp, 9                     ; Carga 9 en 'temp' para establecer las unidades de horas a 9
    sts hora_unidades, temp         ; Establece las unidades de horas a 9
    dec temp2                       ; Decrementa el contador de decenas de horas
    sts hora_decenas, temp2         ; Guarda el nuevo valor de las decenas de horas
    ret                              ; Retorna de la subrutina
    
DEC_HORA_UNIT:
    dec temp                        ; Decrementa el contador de unidades de horas
    sts hora_unidades, temp         ; Guarda el nuevo valor de las unidades de horas
    ret                              ; Retorna de la subrutina

;----------------------------------------------
; OBTENER_LIMITE_DIAS: Determina cuántos días tiene el mes actual
;----------------------------------------------
OBTENER_LIMITE_DIAS:
    ; Verifica qué mes es para conocer su límite de días
    ; Resultado en digit
    lds temp, mes_decenas          ; Carga el valor de las decenas del mes en 'temp'
    cpi temp, 0                    ; Compara 'temp' con 0
    brne CHECK_MESES_10_12        ; Si no es 0, salta a CHECK_MESES_10_12 (meses 10-12)
    
    ; Para meses del 1 al 9
    lds temp, mes_unidades         ; Carga el valor de las unidades del mes en 'temp'
    cpi temp, 2                    ; Compara con 2 (Febrero)
    breq ES_FEBRERO                ; Si es Febrero, salta a ES_FEBRERO
    
    cpi temp, 4                    ; Compara con 4 (Abril)
    breq ES_MES_30                 ; Si es Abril, salta a ES_MES_30
    
    cpi temp, 6                    ; Compara con 6 (Junio)
    breq ES_MES_30                 ; Si es Junio, salta a ES_MES_30
    
    cpi temp, 9                    ; Compara con 9 (Septiembre)
    breq ES_MES_30                 ; Si es Septiembre, salta a ES_MES_30
    
    ; Meses de 31 días (Enero, Marzo, Mayo, Julio, Agosto)
    ldi digit, 31                  ; Establece el límite de días a 31
    ret                             ; Retorna de la subrutina
    
CHECK_MESES_10_12:
    lds temp, mes_unidades         ; Carga el valor de las unidades del mes en 'temp'
    cpi temp, 1                    ; Compara con 1 (Noviembre)
    breq ES_MES_30                 ; Si es Noviembre, salta a ES_MES_30
    
    ; Meses de 31 días (Octubre y Diciembre)
    ldi digit, 31                  ; Establece el límite de días a 31
    ret                             ; Retorna de la subrutina
    
ES_FEBRERO:
    ldi digit, 28                  ; Establece el límite de días a 28 (sin años bisiestos)
    ret                             ; Retorna de la subrutina
    
ES_MES_30:
    ldi digit, 30                  ; Establece el límite de días a 30
    ret                             ; Retorna de la subrutina

;----------------------------------------------
; INCREMENTAR_DIAS_MANUAL: Incrementa días manualmente (para configuración)
;----------------------------------------------
INCREMENTAR_DIAS_MANUAL:
    ; Primero obtenemos el límite de días según el mes actual
    rcall OBTENER_LIMITE_DIAS      ; Llama a la subrutina para obtener el límite de días
    ; digit contiene ahora el límite de días (28, 30 o 31)
    
    ; Incrementa unidades de día
    lds temp, dia_unidades          ; Carga el valor actual de las unidades de día en 'temp'
    inc temp                        ; Incrementa el contador de unidades de día
    cpi temp, 10                    ; Compara 'temp' con 10
    brne CHECK_LIMITE_DIA_INC      ; Si no es 10, salta a CHECK_LIMITE_DIA_INC
    
    ; Si llegó a 10, resetear unidades e incrementar decenas
    ldi temp, 0                     ; Carga 0 en 'temp' para reiniciar las unidades de día
    sts dia_unidades, temp          ; Reinicia las unidades de día
    
    lds temp, dia_decenas           ; Carga el valor actual de las decenas de día en 'temp'
    inc temp                        ; Incrementa el contador de decenas de día
    sts dia_decenas, temp           ; Guarda el nuevo valor de las decenas de día
    rjmp CHECK_DIA_TOTAL_INC        ; Salta a CHECK_DIA_TOTAL_INC
    
CHECK_LIMITE_DIA_INC:
    sts dia_unidades, temp          ; Guarda el nuevo valor de las unidades de día
    
CHECK_DIA_TOTAL_INC:
    ; Verificar si superamos el límite del mes actual
    lds temp, dia_decenas           ; Carga el valor de las decenas de día en 'temp'
    ldi ZL, 10                      ; Carga 10 en ZL para la multiplicación
    mul temp, ZL                    ; Multiplica decenas por 10 (almacena en r0)
    lds temp, dia_unidades          ; Carga el valor de las unidades de día en 'temp'
    add r0, temp                    ; Suma r0 (decenas * 10) con las unidades de día
    
    cp r0, digit                    ; Compara con el límite de días
    brlo EXIT_INC_DIAS_MANUAL       ; Si no se ha superado el límite, salir
    
    ; Si llegamos al límite+1, volver al día 1
    ldi temp, 1                     ; Carga 1 en 'temp' para reiniciar el día
    sts dia_unidades, temp          ; Establece las unidades de día a 1
    ldi temp, 0                     ; Carga 0 en 'temp' para reiniciar las decenas de día
    sts dia_decenas, temp           ; Establece las decenas de día a 0
    
EXIT_INC_DIAS_MANUAL:
    ret                              ; Retorna de la subrutina

;----------------------------------------------
; DECREMENTAR_DIAS_MANUAL: Decrementa días manualmente (para configuración)
;----------------------------------------------
DECREMENTAR_DIAS_MANUAL:
    ; Verificar si estamos en día 01
    lds temp, dia_unidades          ; Carga el valor actual de las unidades de día en 'temp'
    cpi temp, 1                     ; Compara 'temp' con 1
    brne DEC_NO_ES_DIA_UNO         ; Si no es 1, salta a DEC_NO_ES_DIA_UNO
    
    lds temp, dia_decenas           ; Carga el valor actual de las decenas de día en 'temp'
    cpi temp, 0                     ; Compara 'temp' con 0
    brne DEC_NO_ES_DIA_UNO         ; Si no es 0, salta a DEC_NO_ES_DIA_UNO
    
    ; Si estamos en día 01, ir al último día del mes
    rcall OBTENER_LIMITE_DIAS      ; Llama a la subrutina para obtener el límite de días
    ; digit contiene ahora el límite de días
    
    cpi digit, 30                   ; Compara el límite de días con 30
    breq SET_DIA_30                 ; Si es 30, salta a SET_DIA_30
    cpi digit, 28                   ; Compara el límite de días con 28
    breq SET_DIA_28                 ; Si es 28, salta a SET_DIA_28
    
    ; Para meses de 31 días
    ldi temp, 1                     ; Carga 1 en 'temp' para establecer el día a 1
    sts dia_unidades, temp          ; Establece las unidades de día a 1
    ldi temp, 3                     ; Carga 3 en 'temp' para establecer las decenas de día a 3
    sts dia_decenas, temp           ; Establece las decenas de día a 3
    ret                              ; Retorna de la subrutina
    
SET_DIA_30:
    ldi temp, 0                     ; Carga 0 en 'temp' para establecer las unidades de día a 0
    sts dia_unidades, temp          ; Establece las unidades de día a 0
    ldi temp, 3                     ; Carga 3 en 'temp' para establecer las decenas de día a 3
    sts dia_decenas, temp           ; Establece las decenas de día a 3
    ret                              ; Retorna de la subrutina
    
SET_DIA_28:
    ldi temp, 8                     ; Carga 8 en 'temp' para establecer las unidades de día a 8
    sts dia_unidades, temp          ; Establece las unidades de día a 8
    ldi temp, 2                     ; Carga 2 en 'temp' para establecer las decenas de día a 2
    sts dia_decenas, temp           ; Establece las decenas de día a 2
    ret                              ; Retorna de la subrutina
    
DEC_NO_ES_DIA_UNO:
    ; Decrementar normal
    lds temp, dia_unidades          ; Carga el valor actual de las unidades de día en 'temp'
    cpi temp, 0                     ; Compara 'temp' con 0
    brne DEC_DIA_UNIT               ; Si no es 0, salta a DEC_DIA_UNIT
    
    ; Si unidades = 0, poner 9 y decrementar decenas
    ldi temp, 9                     ; Carga 9 en 'temp' para establecer las unidades de día a 9
    sts dia_unidades, temp          ; Establece las unidades de día a 9
    
    lds temp, dia_decenas           ; Carga el valor actual de las decenas de día en 'temp'
    dec temp                        ; Decrementa el contador de decenas de día
    sts dia_decenas, temp           ; Guarda el nuevo valor de las decenas de día
    ret                              ; Retorna de la subrutina
    
DEC_DIA_UNIT:
    dec temp                        ; Decrementa el contador de unidades de día
    sts dia_unidades, temp          ; Guarda el nuevo valor de las unidades de día
    ret                              ; Retorna de la subrutina

;----------------------------------------------
; INCREMENTAR_MESES_MANUAL: Incrementa meses manualmente (para configuración)
;----------------------------------------------
INCREMENTAR_MESES_MANUAL:
    lds temp, mes_unidades          ; Carga el valor actual de las unidades del mes en 'temp'
    inc temp                        ; Incrementa el contador de unidades del mes
    cpi temp, 10                    ; Compara 'temp' con 10
    brne CHECK_LIMITE_MES_INC      ; Si no es 10, salta a CHECK_LIMITE_MES_INC
    
    ; Si llegó a 10, resetear unidades e incrementar decenas
    ldi temp, 0                     ; Carga 0 en 'temp' para reiniciar las unidades del mes
    sts mes_unidades, temp          ; Reinicia las unidades del mes
    
    lds temp, mes_decenas           ; Carga el valor actual de las decenas del mes en 'temp'
    inc temp                        ; Incrementa el contador de decenas del mes
    cpi temp, 1                     ; Compara 'temp' con 1 (diciembre)
    brne SAVE_MES_DEC_INC          ; Si no es 1, salta a SAVE_MES_DEC_INC
    
    ; Si es 1, verificar que no pasemos de 12 meses
    lds temp2, mes_unidades         ; Carga el valor de las unidades del mes en 'temp2'
    cpi temp2, 3                    ; Compara con 3
    brlo SAVE_MES_DEC_INC           ; Si es menor que 3, salta a SAVE_MES_DEC_INC
    
    ; Si es mes 13 o más, volver a mes 01
    ldi temp, 0                     ; Carga 0 en 'temp' para reiniciar las decenas del mes
    sts mes_decenas, temp           ; Establece las decenas del mes a 0
    ldi temp, 1                     ; Carga 1 en 'temp' para establecer las unidades del mes a 1
    sts mes_unidades, temp          ; Establece las unidades del mes a 1
    rjmp AJUSTAR_DIA_POR_MES       ; Salta a AJUSTAR_DIA_POR_MES
    
SAVE_MES_DEC_INC:
    sts mes_decenas, temp           ; Guarda el nuevo valor de las decenas del mes
    rjmp AJUSTAR_DIA_POR_MES       ; Salta a AJUSTAR_DIA_POR_MES
    
CHECK_LIMITE_MES_INC:
    sts mes_unidades, temp          ; Guarda el nuevo valor de las unidades del mes
    
    ; Verificar si estamos en mes 13
    lds temp, mes_decenas           ; Carga el valor actual de las decenas del mes en 'temp'
    cpi temp, 1                     ; Compara 'temp' con 1
    brne AJUSTAR_DIA_POR_MES       ; Si no es 1, salta a AJUSTAR_DIA_POR_MES
    
    lds temp, mes_unidades          ; Carga el valor actual de las unidades del mes en 'temp'
    cpi temp, 3                     ; Compara 'temp' con 3
    brlo AJUSTAR_DIA_POR_MES       ; Si es menor que 3, salta a AJUSTAR_DIA_POR_MES
    
    ; Si es mes 13, volver a mes 01
    ldi temp, 1                     ; Carga 1 en 'temp' para establecer las unidades del mes a 1
    sts mes_unidades, temp          ; Establece las unidades del mes a 1
    ldi temp, 0                     ; Carga 0 en 'temp' para reiniciar las decenas del mes
    sts mes_decenas, temp           ; Establece las decenas del mes a 0
    
AJUSTAR_DIA_POR_MES:
    ; Ajustar el día si cambiamos a un mes con menos días
    rcall OBTENER_LIMITE_DIAS      ; Llama a la subrutina para obtener el límite de días
    ; digit ahora tiene el límite del nuevo mes
    
    lds temp, dia_decenas           ; Carga el valor de las decenas de día en 'temp'
    ldi ZL, 10                      ; Carga 10 en ZL para la multiplicación
    mul temp, ZL                    ; Multiplica decenas por 10 (almacena en r0)
    lds temp, dia_unidades          ; Carga el valor de las unidades de día en 'temp'
    add r0, temp                    ; Suma r0 (decenas * 10) con las unidades de día
    
    cp r0, digit                    ; Compara con el límite de días
    brlo EXIT_INC_MES_MANUAL       ; Si el día actual es válido, no hacer nada
    
    ; Si el día actual excede el límite del nuevo mes, ajustar al último día
    cpi digit, 30                   ; Compara con 30
    breq SET_ULTIMO_DIA_30         ; Si es 30, salta a SET_ULTIMO_DIA_30
    cpi digit, 28                   ; Compara con 28
    breq SET_ULTIMO_DIA_28         ; Si es 28, salta a SET_ULTIMO_DIA_28
    
    ; Para meses de 31 días
    ldi temp, 1                     ; Carga 1 en 'temp' para establecer las unidades de día a 1
    sts dia_unidades, temp          ; Establece las unidades de día a 1
    ldi temp, 3                     ; Carga 3 en 'temp
    sts dia_decenas, temp           ; Guarda el nuevo valor de las decenas de día en la variable 'dia_decenas'
    rjmp EXIT_INC_MES_MANUAL		; Salta incondicionalmente a la etiqueta EXIT_INC_MES_MANUAL

SET_ULTIMO_DIA_30:
    ldi temp, 0                    ; Carga 0 en 'temp' para establecer las unidades de día a 0
    sts dia_unidades, temp         ; Establece las unidades de día a 0 (último día del mes de 30 días)
    ldi temp, 3                    ; Carga 3 en 'temp' para establecer las decenas de día a 3
    sts dia_decenas, temp          ; Establece las decenas de día a 3 (30)
    rjmp EXIT_INC_MES_MANUAL       ; Salta incondicionalmente a la etiqueta EXIT_INC_MES_MANUAL

SET_ULTIMO_DIA_28:
    ldi temp, 8                    ; Carga 8 en 'temp' para establecer las unidades de día a 8 (último día de febrero)
    sts dia_unidades, temp         ; Establece las unidades de día a 8
    ldi temp, 2                    ; Carga 2 en 'temp' para establecer las decenas de día a 2
    sts dia_decenas, temp          ; Establece las decenas de día a 2 (28)

EXIT_INC_MES_MANUAL:
    ret                             ; Retorna de la subrutina

;----------------------------------------------
; DECREMENTAR_MESES_MANUAL: Decrementa meses manualmente (para configuración)
;----------------------------------------------
DECREMENTAR_MESES_MANUAL:
    lds temp, mes_unidades          ; Carga el valor actual de las unidades del mes en 'temp'
    cpi temp, 1                     ; Compara 'temp' con 1
    brne DEC_MES_NORMAL             ; Si no es 1, salta a DEC_MES_NORMAL
    
    lds temp, mes_decenas           ; Carga el valor actual de las decenas del mes en 'temp'
    cpi temp, 0                     ; Compara 'temp' con 0
    brne DEC_MES_NORMAL             ; Si no es 0, salta a DEC_MES_NORMAL
    
    ; Si estamos en mes 01, ir a mes 12
    ldi temp, 2                     ; Carga 2 en 'temp' para establecer las unidades del mes a 2 (Febrero)
    sts mes_unidades, temp          ; Establece las unidades del mes a 2
    ldi temp, 1                     ; Carga 1 en 'temp' para establecer las decenas del mes a 1 (Enero)
    sts mes_decenas, temp           ; Establece las decenas del mes a 1
    rjmp AJUSTAR_DIA_POR_MES_DEC    ; Salta a AJUSTAR_DIA_POR_MES_DEC para ajustar el día

DEC_MES_NORMAL:
    ; Decrementar normal
    lds temp, mes_unidades          ; Carga el valor actual de las unidades del mes en 'temp'
    cpi temp, 0                     ; Compara 'temp' con 0
    brne DEC_MES_UNIT               ; Si no es 0, salta a DEC_MES_UNIT
    
    ; Si unidades = 0, poner 9 y decrementar decenas
    ldi temp, 9                     ; Carga 9 en 'temp' para establecer las unidades del mes a 9
    sts mes_unidades, temp          ; Establece las unidades del mes a 9
    
    lds temp, mes_decenas           ; Carga el valor actual de las decenas del mes en 'temp'
    dec temp                        ; Decrementa el contador de decenas del mes
    sts mes_decenas, temp           ; Guarda el nuevo valor de las decenas del mes
    rjmp AJUSTAR_DIA_POR_MES_DEC    ; Salta a AJUSTAR_DIA_POR_MES_DEC para ajustar el día
    
DEC_MES_UNIT:
    dec temp                        ; Decrementa el contador de unidades del mes
    sts mes_unidades, temp          ; Guarda el nuevo valor de las unidades del mes
    
AJUSTAR_DIA_POR_MES_DEC:
    ; Igual que en AJUSTAR_DIA_POR_MES
    rcall OBTENER_LIMITE_DIAS      ; Llama a la subrutina para obtener el límite de días del mes actual
    
    lds temp, dia_decenas           ; Carga el valor de las decenas de día en 'temp'
    ldi ZL, 10                      ; Carga 10 en ZL para la multiplicación
    mul temp, ZL                    ; Multiplica decenas por 10 (almacena en r0)
    lds temp, dia_unidades          ; Carga el valor de las unidades de día en 'temp'
    add r0, temp                    ; Suma r0 (decenas * 10) con las unidades de día
    
    cp r0, digit                    ; Compara con el límite de días
    brlo EXIT_DEC_MES_MANUAL       ; Si el día actual es válido, no hacer nada
    
    ; Si el día actual excede el límite del nuevo mes, ajustar al último día
    mov temp, digit                 ; Carga el límite de días en 'temp'
    cpi temp, 28                    ; Compara con 28
    breq SET_DIA_28_DEC             ; Si es 28, salta a SET_DIA_28_DEC
    cpi temp, 30                    ; Compara con 30
    breq SET_DIA_30_DEC             ; Si es 30, salta a SET_DIA_30_DEC
    
    ; Para meses de 31 días
    ldi temp, 1                     ; Carga 1 en 'temp' para establecer las unidades de día a 1
    sts dia_unidades, temp          ; Establece las unidades de día a 1
    ldi temp, 3                     ; Carga 3 en 'temp' para establecer las decenas de día a 3
    sts dia_decenas, temp           ; Guarda el nuevo valor de las decenas de día en la variable 'dia_decenas'
    rjmp EXIT_DEC_MES_MANUAL        ; Salta incondicionalmente a la etiqueta EXIT_DEC_MES_MANUAL

SET_DIA_30_DEC:
    ldi temp, 0                     ; Carga 0 en 'temp' para establecer las unidades de día a 0
    sts dia_unidades, temp          ; Establece las unidades de día a 0 (último día del mes de 30 días)
    ldi temp, 3                     ; Carga 3 en 'temp' para establecer las decenas de día a 3 (30)
    sts dia_decenas, temp           ; Establece las decenas de día a 3
    rjmp EXIT_DEC_MES_MANUAL        ; Salta incondicionalmente a la etiqueta EXIT_DEC_MES_MANUAL

SET_DIA_28_DEC:
    ldi temp, 8                     ; Carga 8 en 'temp' para establecer las unidades de día a 8 (último día de febrero)
    sts dia_unidades, temp          ; Establece las unidades de día a 8
    ldi temp, 2                     ; Carga 2 en 'temp' para establecer las decenas de día a 2
    sts dia_decenas, temp           ; Establece las decenas de día a 2 (28)

EXIT_DEC_MES_MANUAL:
    ret                              ; Retorna de la subrutina

;----------------------------------------------
; INCREMENTAR_HORAS_ALARMA: Incrementa horas de alarma manualmente
;----------------------------------------------
INCREMENTAR_HORAS_ALARMA:
    ldi temp, 1                    ; Carga 1 en 'temp' para indicar que la alarma está activa
    sts alarma_activa, temp        ; Establece el estado de la alarma como activa
    lds temp, alarma_hora_unidades ; Carga el valor actual de las unidades de la hora de la alarma en 'temp'
    inc temp                       ; Incrementa el contador de unidades de la hora de la alarma
    cpi temp, 10                   ; Compara 'temp' con 10
    brne CHECK_MAX_HORA_ALARM_INC  ; Si no es 10, salta a CHECK_MAX_HORA_ALARM_INC
    
    ; Si llegó a 10, resetear unidades e incrementar decenas
    ldi temp, 0                    ; Carga 0 en 'temp' para reiniciar las unidades de la hora de la alarma
    sts alarma_hora_unidades, temp  ; Establece las unidades de la hora de la alarma a 0
    
    lds temp, alarma_hora_decenas  ; Carga el valor actual de las decenas de la hora de la alarma en 'temp'
    inc temp                       ; Incrementa el contador de decenas de la hora de la alarma
    cpi temp, 3                    ; Máximo 2 para formato 24h
    brne SAVE_HORA_ALARM_DEC_INC   ; Si no es 3, salta a SAVE_HORA_ALARM_DEC_INC
    
    ; Si llegó a 3, resetear decenas
    ldi temp, 0                    ; Carga 0 en 'temp' para reiniciar las decenas de la hora de la alarma
    
SAVE_HORA_ALARM_DEC_INC:
    sts alarma_hora_decenas, temp  ; Guarda el nuevo valor de las decenas de la hora de la alarma
    ret                             ; Retorna de la subrutina
    
CHECK_MAX_HORA_ALARM_INC:
    ; Verificar si superamos 23 horas
    lds temp2, alarma_hora_decenas  ; Carga el valor actual de las decenas de la hora de la alarma en 'temp2'
    cpi temp2, 2                    ; Compara 'temp2' con 2
    brne SAVE_HORA_ALARM_UNIT_INC   ; Si no es 2, salta a SAVE_HORA_ALARM_UNIT_INC
    
    ; Si decenas es 2, unidades no puede ser mayor que 3
    cpi temp, 4                     ; Compara 'temp' con 4
    brlo SAVE_HORA_ALARM_UNIT_INC   ; Si es menor que 4, salta a SAVE_HORA_ALARM_UNIT_INC
    
    ; Si llegó a 24, resetear a 00
    ldi temp, 0                     ; Carga 0 en 'temp' para reiniciar las unidades de la hora de la alarma
    sts alarma_hora_unidades, temp  ; Establece las unidades de la hora de la alarma a 0
    sts alarma_hora_decenas, temp   ; Establece las decenas de la hora de la alarma a 0
    ret                             ; Retorna de la subrutina
    
SAVE_HORA_ALARM_UNIT_INC:
    sts alarma_hora_unidades, temp  ; Guarda el nuevo valor de las unidades de la hora de la alarma
    ret                             ; Retorna de la subrutina

;----------------------------------------------
; DECREMENTAR_HORAS_ALARMA: Decrementa horas de alarma manualmente
;----------------------------------------------
DECREMENTAR_HORAS_ALARMA:
    ldi temp, 1                    ; Carga 1 en 'temp' para indicar que la alarma está activa
    sts alarma_activa, temp        ; Establece el estado de la alarma como activa
    lds temp, alarma_hora_unidades ; Carga el valor actual de las unidades de la hora de la alarma en 'temp'
    cpi temp, 0                    ; Compara 'temp' con 0
    brne DEC_HORA_ALARM_UNIT       ; Si no es 0, salta a DEC_HORA_ALARM_UNIT
    
    ; Si unidades era 0
    lds temp2, alarma_hora_decenas ; Carga el valor actual de las decenas de la hora de la alarma en 'temp2'
    cpi temp2, 0                   ; Compara 'temp2' con 0
    brne DEC_DESDE_X0_ALARM        ; Si no es 0, salta a DEC_DESDE_X0_ALARM
    
    ; Si estamos en 00, ir a 23
    ldi temp, 3                    ; Carga 3 en 'temp' para establecer las unidades de la hora a 3
    sts alarma_hora_unidades, temp  ; Establece las unidades de la hora de la alarma a 3
    ldi temp2, 2                   ; Carga 2 en 'temp2' para establecer las decenas de la hora a 2
    sts alarma_hora_decenas, temp2  ; Establece las decenas de la hora de la alarma a 2
    ret                             ; Retorna de la subrutina
    
DEC_DESDE_X0_ALARM:
    ; Si unidades = 0 y decenas > 0
    ldi temp, 9                     ; Carga 9 en 'temp' para establecer las unidades de la hora a 9
    sts alarma_hora_unidades, temp  ; Guarda el nuevo valor de las unidades de la hora de la alarma en 'alarma_hora_unidades'
    dec temp2                       ; Decrementa el contador de decenas de la hora de la alarma
    sts alarma_hora_decenas, temp2  ; Guarda el nuevo valor de las decenas de la hora de la alarma
    ret                             ; Retorna de la subrutina
    
DEC_HORA_ALARM_UNIT:
    dec temp                        ; Decrementa el contador de unidades de la hora de la alarma
    sts alarma_hora_unidades, temp  ; Guarda el nuevo valor de las unidades de la hora de la alarma
    ret                             ; Retorna de la subrutina

;----------------------------------------------
; INCREMENTAR_MINUTOS_ALARMA: Incrementa minutos de alarma manualmente
;----------------------------------------------
INCREMENTAR_MINUTOS_ALARMA:
    ldi temp, 1                    ; Carga 1 en 'temp' para indicar que la alarma está activa
    sts alarma_activa, temp        ; Establece el estado de la alarma como activa
    lds temp, alarma_min_unidades   ; Carga el valor actual de las unidades de minutos de la alarma en 'temp'
    inc temp                       ; Incrementa el contador de unidades de minutos de la alarma
    cpi temp, 10                    ; Compara 'temp' con 10
    brne SAVE_MIN_ALARM_UNIT_INC    ; Si no es 10, salta a SAVE_MIN_ALARM_UNIT_INC
    
    ; Si llegó a 10, resetear unidades e incrementar decenas
    ldi temp, 0                     ; Carga 0 en 'temp' para reiniciar las unidades de minutos de la alarma
    sts alarma_min_unidades, temp    ; Establece las unidades de minutos de la alarma a 0
    
    lds temp, alarma_min_decenas     ; Carga el valor actual de las decenas de minutos de la alarma en 'temp'
    inc temp                        ; Incrementa el contador de decenas de minutos de la alarma
    cpi temp, 6                     ; Compara 'temp' con 6
    brne SAVE_MIN_ALARM_DEC_INC     ; Si no es 6, salta a SAVE_MIN_ALARM_DEC_INC
    
    ; Si llegó a 6, resetear decenas
    ldi temp, 0                     ; Carga 0 en 'temp' para reiniciar las decenas de minutos de la alarma
    
SAVE_MIN_ALARM_DEC_INC:
    sts alarma_min_decenas, temp    ; Guarda el nuevo valor de las decenas de minutos de la alarma
    ret                             ; Retorna de la subrutina
    
SAVE_MIN_ALARM_UNIT_INC:
    sts alarma_min_unidades, temp    ; Guarda el nuevo valor de las unidades de minutos de la alarma
    ret                             ; Retorna de la subrutina

;----------------------------------------------
; DECREMENTAR_MINUTOS_ALARMA: Decrementa minutos de alarma manualmente
;----------------------------------------------
DECREMENTAR_MINUTOS_ALARMA:
    ldi temp, 1                    ; Carga 1 en 'temp' para indicar que la alarma está activa
    sts alarma_activa, temp        ; Establece el estado de la alarma como activa
    lds temp, alarma_min_unidades   ; Carga el valor actual de las unidades de minutos de la alarma en 'temp'
    cpi temp, 0                    ; Compara 'temp' con 0
    brne DEC_MIN_ALARM_UNIT        ; Si no es 0, salta a DEC_MIN_ALARM_UNIT
    
    ; Si era 0, poner a 9 y decrementar decenas
    ldi temp, 9                    ; Carga 9 en 'temp' para establecer las unidades de minutos de la alarma a 9
    sts alarma_min_unidades, temp   ; Establece las unidades de minutos de la alarma a 9
    
    lds temp, alarma_min_decenas    ; Carga el valor actual de las decenas de minutos de la alarma en 'temp'
    cpi temp, 0                    ; Compara 'temp' con 0
    brne DEC_MIN_ALARM_DEC         ; Si no es 0, salta a DEC_MIN_ALARM_DEC
    
    ; Si decenas era 0, poner a 5
    ldi temp, 6                    ; Carga 6 en 'temp' para establecer las decenas de minutos de la alarma a 6
    
DEC_MIN_ALARM_DEC:
    dec temp                       ; Decrementa el contador de decenas de minutos de la alarma
    sts alarma_min_decenas, temp    ; Guarda el nuevo valor de las decenas de minutos de la alarma
    ret                             ; Retorna de la subrutina
    
DEC_MIN_ALARM_UNIT:
    dec temp                       ; Decrementa el contador de unidades de minutos de la alarma
    sts alarma_min_unidades, temp    ; Guarda el nuevo valor de las unidades de minutos de la alarma
    ret                             ; Retorna de la subrutina


