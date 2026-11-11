/* rt_avr.c — rutina de multiplicación que clang espera de libgcc. Sin avr-libc/libgcc hay que darla: clang
 * convierte "(x << 3) + (x << 1)" en "x * 10" y lo llama. Misma convención de llamada que libgcc (A en r22-r25,
 * B en r18-r21, resultado en r22-r25), que es la convención normal de C en AVR. Con sumas y desplazamientos
 * para que el compilador no vuelva a llamarse a sí misma. */
#include <stdint.h>

uint32_t __mulsi3(uint32_t a, uint32_t b);
uint32_t __mulsi3(uint32_t a, uint32_t b) {
    uint32_t r = 0;
    while (b) {
        if (b & 1) r += a;
        a <<= 1;
        b >>= 1;
    }
    return r;
}
