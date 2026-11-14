; arranque.S — vectores, arranque en C y la interrupción de LATCH del mando emulado (ATmega328P).
;
; La interrupción es la única parte con tiempo crítico. En la subida de LATCH (PCINT2 = D10 = SS) copia
; GPIOR1 (el byte que ha preparado nucleo.c) al registro del SPI, que lo saca bit a bit por MISO en cada
; subida de CLK sin ayuda del programa. Desde el flanco hasta la escritura de SPDR pasan ≤ ~20 ciclos
; (1,25 µs a 16 MHz) y el pulso de LATCH más corto dura ~2,2 µs. No toca SREG (sbis/in/out/sbi no cambian las
; banderas). En la bajada de LATCH no hace nada: en ese momento empieza la transferencia y no se puede escribir
; SPDR.

        .equ PINB_IO,   0x03
        .equ DDRB_IO,   0x04
        .equ GPIOR0_IO, 0x1E
        .equ GPIOR1_IO, 0x2A
        .equ SPDR_IO,   0x2E
        .equ SPFR_IO,   0x19    ; solo LGT8F328P: estado y vaciado de las colas (FIFO) del SPI
        .equ SPL_IO,    0x3D
        .equ SPH_IO,    0x3E
        .equ SREG_IO,   0x3F
        .equ RAMEND,    0x08FF

        .section .vectors,"ax",@progbits
        .global __vectors
__vectors:
        jmp __reset             ; 0  RESET
        jmp __malo              ; 1  INT0
        jmp __malo              ; 2  INT1
        jmp isr_latch           ; 3  PCINT0 (puerto B: D10 = LATCH)
        .rept 22                ; 4..25
        jmp __malo
        .endr

        .text
__malo:
        reti

isr_latch:
        sbis PINB_IO, 2         ; LATCH alto: subida
        reti                    ; bajada: nada
        push r24
        ldi  r24, 0x44          ; SPFR del LGT8F: WREMPT | RDEMPT = vaciar las colas del SPI
        sbic GPIOR0_IO, 1       ; solo en el LGT8F (main_avr.c pone el bit 1 de GPIOR0)
        out  SPFR_IO, r24       ; sin esto el byte nuevo queda detrás de los viejos y la consola lee basura
        in   r24, GPIOR1_IO
        out  SPDR_IO, r24       ; el SPI saca este byte cuando LATCH baje
        sbi  DDRB_IO, 4         ; MISO como salida (en reposo queda en alta impedancia)
        sbi  GPIOR0_IO, 0       ; aviso para el bucle principal
        pop  r24
        reti

        .global __reset
__reset:
        clr  r1
        out  SREG_IO, r1
        ldi  r28, lo8(RAMEND)
        ldi  r29, hi8(RAMEND)
        out  SPH_IO, r29
        out  SPL_IO, r28
        ; .data (y las constantes) de la flash a la RAM
        ldi  r26, lo8(__data_start)
        ldi  r27, hi8(__data_start)
        ldi  r30, lo8(__data_load_start)
        ldi  r31, hi8(__data_load_start)
        ldi  r24, lo8(__data_end)
        ldi  r25, hi8(__data_end)
1:      cp   r26, r24
        cpc  r27, r25
        breq 2f
        lpm  r0, Z+
        st   X+, r0
        rjmp 1b
        ; .bss a cero
2:      ldi  r26, lo8(__bss_start)
        ldi  r27, hi8(__bss_start)
        ldi  r24, lo8(__bss_end)
        ldi  r25, hi8(__bss_end)
3:      cp   r26, r24
        cpc  r27, r25
        breq 4f
        st   X+, r1
        rjmp 3b
4:      call main
5:      rjmp 5b
