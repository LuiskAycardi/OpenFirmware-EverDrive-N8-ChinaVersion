/* sim_hw.c — "hardware" del mando para la prueba en seco: nucleo.c compilado para el PC (biblioteca
 * compartida que carga simulador.py con ctypes). sim_latch() hace lo que la interrupción del Nano: devuelve el
 * byte que el juego lee en ese LATCH (el preparado antes) y luego avisa al núcleo. */
#include <stdint.h>
#include <string.h>
#include "nucleo.h"

static uint8_t cargado = 0xFF, miso_on = 0, v5 = 1;
static uint8_t txb[16384];
static uint32_t txn;
static uint16_t perd;

void hw_cargar(uint8_t b) { cargado = b; }
void hw_tx(uint8_t c) { if (txn < sizeof txb) txb[txn++] = c; else perd++; }
void hw_miso(uint8_t on) { miso_on = on; }
uint8_t hw_v5(void) { return v5; }
uint16_t hw_perdidos(void) { return perd; }

uint8_t sim_latch(uint32_t t) {
    uint8_t b = cargado;
    miso_on = 1;
    nucleo_latch(t);
    return b;
}

uint32_t sim_tx(uint8_t *dst, uint32_t max) {
    uint32_t n = txn < max ? txn : max;
    memcpy(dst, txb, n);
    memmove(txb, txb + n, txn - n);
    txn -= n;
    return n;
}

void sim_v5(uint8_t on) { v5 = on; }
uint8_t sim_miso(void) { return miso_on; }
