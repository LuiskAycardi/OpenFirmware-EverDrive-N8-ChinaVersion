// N8AudioLog.h — Registro del nivel de sonido de expansión para el banco de pruebas N8.
// Lo usan el puente (nuestro modelo) y los chips de sonido de Mesen2 parcheados (referencia), así las
// dos ejecuciones escriben lo mismo y se pueden comparar (tools/n8sim/audiodiff.py).
// Activo con N8_AUDIO=1: escribe "ciclo_de_CPU nivel" en <carpeta de N8_OUT>/audio.txt cada vez que el
// nivel cambia (el búfer se vacía cada 1024 líneas y al salir). Escala común: la de hdl/rtl (VRC6 = suma x 8, 5B = suma de la tabla logarítmica).
#pragma once
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <string>

inline void N8AudioLog(uint64_t cycle, int level)
{
	static FILE* f = nullptr;
	static int state = -1;
	static int last = -1;
	static unsigned lines = 0;
	if(state < 0) {
		const char* e = getenv("N8_AUDIO");
		state = (e && atoi(e)) ? 1 : 0;
		if(state) {
			const char* o = getenv("N8_OUT");
			std::string p = o ? o : "./x";
			size_t k = p.rfind('/');
			p = (k == std::string::npos ? std::string(".") : p.substr(0, k)) + "/audio.txt";
			f = fopen(p.c_str(), "w");
			if(!f) {
				state = 0;
			}
		}
	}
	if(state != 1 || level == last) {
		return;
	}
	last = level;
	fprintf(f, "%llu %d\n", (unsigned long long)cycle, level);
	if(++lines % 1024 == 0) {
		fflush(f);
	}
}

// Escrituras en los registros de sonido del FDS de Mesen2 ("ciclo registro valor" en <carpeta de N8_OUT>/fdsreg.txt,
// con N8_AUDIO=1): tools/fds/sonido_replay las mete tal cual en hdl/rtl/snd_fds.v para comparar su salida con la de
// Mesen2 sin depender de cuándo hace cada cosa el juego.
inline void N8FdsRegLog(uint64_t cycle, uint16_t addr, uint8_t value)
{
	static FILE* f = nullptr;
	static int state = -1;
	static unsigned lines = 0;
	if(state < 0) {
		const char* e = getenv("N8_AUDIO");
		state = (e && atoi(e)) ? 1 : 0;
		if(state) {
			const char* o = getenv("N8_OUT");
			std::string p = o ? o : "./x";
			size_t k = p.rfind('/');
			p = (k == std::string::npos ? std::string(".") : p.substr(0, k)) + "/fdsreg.txt";
			f = fopen(p.c_str(), "w");
			if(!f) {
				state = 0;
			}
		}
	}
	if(state != 1) {
		return;
	}
	fprintf(f, "%llu %04X %02X\n", (unsigned long long)cycle, addr, value);
	if(++lines % 1024 == 0) {
		fflush(f);
	}
}
