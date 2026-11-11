// n8model.h — Interfaz C del modelo Verilator de n8_top (libn8model.so).
// El mapper puente de Mesen2 la carga con dlopen: así recompilar el Verilog no obliga
// a reenlazar Mesen2 (variable de entorno N8_MODEL = ruta de la librería).
#pragma once
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct N8Pins {
	// entradas
	uint8_t  bios_off, cpu_romsel_n, cpu_rw, cpu_m2, ppu_rd_n, ppu_wr_n;
	uint16_t cpu_a;
	uint8_t  cpu_din;
	uint16_t ppu_a;
	uint8_t ppu_din, ppu_dout, ppu_doe;
	// salidas
	uint8_t  cpu_irq, ciram_ce_n, ciram_a10, prg_ce_n, prg_we_n, chr_ce_n, chr_we_n,
	         ram_ce, ram_we_n, os_mode;
	uint16_t prg_map, chr_map;
	uint16_t snd_level;   // sonido de expansión (0-1023)
	uint8_t  snd_on;
	uint8_t  cpu_dout, cpu_doe;   // lectura de registro: dato y bits que conduce la FPGA
} N8Pins;

#define N8MODEL_API_VERSION 4

typedef int   (*n8_api_version_fn)(void);
typedef void* (*n8_create_fn)(void);
typedef void  (*n8_destroy_fn)(void*);
typedef void  (*n8_eval_fn)(void*, N8Pins*);        // aplica entradas, evalúa, lee salidas
typedef void  (*n8_tick_fn)(void*, N8Pins*, int);   // n flancos de subida de clk

int   n8_api_version(void);
void* n8_create(void);
void  n8_destroy(void* m);
void  n8_eval(void* m, N8Pins* p);
void  n8_tick(void* m, N8Pins* p, int n);

#ifdef __cplusplus
}
#endif
