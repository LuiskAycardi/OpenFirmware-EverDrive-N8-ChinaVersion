/* nucleo.h — lógica del mando de NES emulado, independiente del hardware.
 *
 * La misma lógica corre en el Arduino Nano (main_avr.c) y en el PC dentro del simulador de la prueba en
 * seco (sim_hw.c + simulador.py). El hardware solo tiene que:
 *   - en cada subida de LATCH, pasar al registro de desplazamiento el último byte de hw_cargar()
 *     (en el Nano lo hace la interrupción PCINT0 por su cuenta) y avisar con nucleo_latch();
 *   - llamar a nucleo_rx() con cada byte que llega del PC y a nucleo_tick() muy a menudo.
 *
 * Tiempo: "ticks" de 4 µs (temporizador de 250 kHz), contador de 32 bits que da la vuelta a las 4,77 h.
 * Botones (máscara, 1 = pulsado): A=01 B=02 Select=04 Start=08 Arriba=10 Abajo=20 Izquierda=40 Derecha=80.
 * En la línea DATA sale el bit 0 primero (A) y a nivel bajo = pulsado: hw_cargar() recibe ~máscara.
 */
#ifndef NUCLEO_H
#define NUCLEO_H
#include <stdint.h>

#define TICKS_MS 250u

/* Lo pone el hardware */
void hw_cargar(uint8_t linea);   /* byte para la próxima lectura, tal cual sale por DATA (0 = pulsado) */
void hw_tx(uint8_t c);           /* cola de salida hacia el PC (sin bloquear) */
void hw_miso(uint8_t activo);    /* 1 = conducir DATA, 0 = alta impedancia */
uint8_t hw_v5(void);             /* sensor de +5V de la consola (A0): 1 = encendida */
uint16_t hw_perdidos(void);      /* bytes de salida descartados por cola llena */

/* Lo llama el hardware */
void nucleo_inicio(uint32_t t);
void nucleo_latch(uint32_t t);
void nucleo_rx(uint8_t c, uint32_t t);
void nucleo_tick(uint32_t t);

#endif
