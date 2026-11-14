/* main_avr.c — el mando de NES emulado en un Arduino Nano/Uno (ATmega328P a 16 MHz, 5 V).
 *
 * Pines (ver ../CONEXION.md): D10 = LATCH (SS), D13 = CLK (SCK), D12 = DATA (MISO, por 1 kΩ),
 * D11 (MOSI) a GND, A0 = sensor opcional del +5V de la consola, D2 = LED del PC817 (por 330 Ω) que pulsa el
 * botón RESET de la consola. D2 queda en bajo desde el arranque; mientras corre el cargador está en entrada
 * (sin corriente por el LED), así que reiniciar el Nano no resetea la consola.
 *
 * El SPI en modo esclavo hace de CD4021: modo 2 (CPOL=1: CLK en reposo alto; CPHA=0: el bit sale al bajar SS
 * y cambia en la subida de CLK), bit 0 primero. Con MOSI a GND, tras 8 lecturas salen ceros en la línea (la CPU
 * lee 1), como en el mando original. La interrupción de LATCH está en arranque.S; aquí no hay ninguna otra: el
 * puerto serie (115200 baudios) y el temporizador se atienden por sondeo para no retrasarla.
 */
#include <stdint.h>
#include "avr328p.h"
#include "nucleo.h"

#define TXN 192
static uint8_t txb[TXN];
static uint8_t txh, txt;
static uint16_t perdidos;
static uint16_t t_alto;

void hw_cargar(uint8_t b) { GPIOR1 = b; }

void hw_tx(uint8_t c) {
    uint8_t n = (uint8_t)(txh + 1);
    if (n == TXN) n = 0;
    if (n == txt) { perdidos++; return; }
    txb[txh] = c;
    txh = n;
}

uint16_t hw_perdidos(void) { return perdidos; }

void hw_miso(uint8_t on) {
    /* sbi/cbi son atómicas: la interrupción también toca DDRB */
    if (on) __asm__ volatile("sbi 0x04, 4");
    else __asm__ volatile("cbi 0x04, 4");
}

uint8_t hw_v5(void) { return PINC & 1; }

void hw_boton_reset(uint8_t on) {
    if (on) __asm__ volatile("sbi 0x0B, 2");   /* PORTD2 */
    else __asm__ volatile("cbi 0x0B, 2");
}

/* Temporizador 1 a 250 kHz (16 MHz / 64) extendido a 32 bits. Hay que llamarlo al menos cada 262 ms. */
static uint32_t ahora(void) {
    uint8_t l = TCNT1L, h = TCNT1H;
    if (TIFR1 & (1 << TOV1)) {          /* desbordamiento pendiente: releer ya pasado */
        l = TCNT1L;
        h = TCNT1H;
        TIFR1 = 1 << TOV1;
        t_alto++;
    }
    return ((uint32_t)t_alto << 16) | ((uint16_t)h << 8) | l;
}

/* Clones del Nano con LGT8F328P (LQFP32, el cargador responde como un ATmega328P, firma 1e950f): corren con su
 * oscilador interno de 32 MHz y arrancan con el preescalador a /8 (4 MHz). Su cargador pone /2 para sí mismo, pero
 * el programa empieza otra vez con /8: sin esto la UART iba a una cuarta parte de 115200 y el PC solo recibía basura
 * (medido el 2026-11-11 con un Nano "BTE21-15A"). Se reconoce por PMCR (0xF2), que en el LGT8F vale 0x13 al
 * arrancar y en el ATmega328P es una dirección reservada que se lee 0. En un ATmega no se toca CLKPR: dividiría el
 * cristal de 16 MHz. */
static void reloj_lgt8f(void) {
    if (R8(0xF2) == 0) return;
    __asm__ volatile(
        "ldi r24, 0x80\n\t"
        "ldi r25, 0x01\n\t"
        "sts 0x61, r24\n\t"              /* CLKPR: CLKPCE y, en menos de 4 ciclos, el divisor /2 -> 16 MHz */
        "sts 0x61, r25\n\t"
        "nop\n\tnop\n\t" ::: "r24", "r25");
}

int main(void) {
    reloj_lgt8f();
    MCUSR = 0;                           /* perro guardián apagado (secuencia temporizada) */
    WDTCSR = (1 << WDCE) | (1 << WDE);
    WDTCSR = 0;

    DDRB = 0;                            /* todo entradas; MISO en alta impedancia hasta el primer LATCH */
    PORTB = 0;
    DDRC = 0;
    PORTC = 0;
    __asm__ volatile("cbi 0x0B, 2");      /* D2 en bajo antes de hacerlo salida: botón RESET suelto */
    __asm__ volatile("sbi 0x0A, 2");      /* DDRD2 */
    /* Bit 1 de GPIOR0 = LGT8F: la interrupción de LATCH vacía antes las colas del SPI (SPFR, E/S 0x19). Su SPI tiene
     * colas de envío y recepción que el ATmega no tiene: sin vaciarlas, cada byte escrito en SPDR quedaba detrás de
     * los anteriores, la cola se llenaba y la consola leía siempre bytes viejos (nada pulsado). */
    GPIOR0 = (R8(0xF2) != 0) ? 2 : 0;
    GPIOR1 = 0xFF;                       /* nada pulsado */

    SPCR = (1 << SPE) | (1 << DORD) | (1 << CPOL);   /* esclavo, modo 2, LSB primero */
    if (GPIOR0 & 2) R8(0x39) = 0x44;     /* SPFR (E/S 0x19 = datos 0x39): colas vacías */
    SPDR = 0xFF;

    TCCR1A = 0;
    TCCR1B = (1 << CS11) | (1 << CS10);

    UBRR0H = 0;
    UBRR0L = 16;                         /* 115200 con U2X (117647, +2,1 %) */
    UCSR0A = 1 << U2X0;
    UCSR0C = (1 << UCSZ01) | (1 << UCSZ00);
    UCSR0B = (1 << RXEN0) | (1 << TXEN0);

    PCIFR = 1 << PCIE0;
    PCMSK0 = 1 << PCINT2;
    PCICR = 1 << PCIE0;
    __asm__ volatile("sei");

    nucleo_inicio(ahora());
    for (;;) {
        uint32_t t = ahora();
        if (GPIOR0 & 1) {
            __asm__ volatile("cbi 0x1E, 0");
            nucleo_latch(t);
        }
        if (UCSR0A & (1 << RXC0)) nucleo_rx(UDR0, t);
        if ((UCSR0A & (1 << UDRE0)) && txt != txh) {
            UDR0 = txb[txt];
            txt = (uint8_t)(txt + 1 == TXN ? 0 : txt + 1);
        }
        nucleo_tick(t);
    }
}
