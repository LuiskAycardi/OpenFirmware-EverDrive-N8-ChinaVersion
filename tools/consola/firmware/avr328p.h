/* avr328p.h — los registros del ATmega328P que usa el firmware (direcciones de la hoja de datos, espacio de
 * datos). Propio, para compilar con clang --target=avr sin avr-libc. */
#ifndef AVR328P_H
#define AVR328P_H
#include <stdint.h>

#define R8(a) (*(volatile uint8_t *)(a))

#define PINB   R8(0x23)
#define DDRB   R8(0x24)
#define PORTB  R8(0x25)
#define PINC   R8(0x26)
#define DDRC   R8(0x27)
#define PORTC  R8(0x28)
#define TIFR1  R8(0x36)
#define PCIFR  R8(0x3B)
#define GPIOR0 R8(0x3E)
#define SPCR   R8(0x4C)
#define SPSR   R8(0x4D)
#define SPDR   R8(0x4E)
#define GPIOR1 R8(0x4A)
#define MCUSR  R8(0x54)
#define WDTCSR R8(0x60)
#define PCICR  R8(0x68)
#define PCMSK0 R8(0x6B)
#define TCCR1A R8(0x80)
#define TCCR1B R8(0x81)
#define TCNT1L R8(0x84)
#define TCNT1H R8(0x85)
#define UCSR0A R8(0xC0)
#define UCSR0B R8(0xC1)
#define UCSR0C R8(0xC2)
#define UBRR0L R8(0xC4)
#define UBRR0H R8(0xC5)
#define UDR0   R8(0xC6)

/* bits */
#define SPE   6
#define DORD  5
#define MSTR  4
#define CPOL  3
#define CPHA  2
#define TOV1  0
#define CS11  1
#define CS10  0
#define U2X0  1
#define RXC0  7
#define UDRE0 5
#define RXEN0 4
#define TXEN0 3
#define UCSZ01 2
#define UCSZ00 1
#define WDCE  4
#define WDE   3
#define PCIE0 0
#define PCINT2 2

#endif
