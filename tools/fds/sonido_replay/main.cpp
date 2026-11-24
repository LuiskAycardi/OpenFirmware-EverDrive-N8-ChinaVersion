// main.cpp — mete en hdl/rtl/snd_fds.v (Verilator) las escrituras de sonido que hizo el FDS de Mesen2 y apunta su
// salida. GPL-3.0-or-later, código propio.
//   replay fdsreg.txt salida.txt ULTIMO_CICLO
// fdsreg.txt: "ciclo registro valor" (N8FdsRegLog, tools/n8sim/N8AudioLog.h). En Mesen2, en el ciclo N el sonido
// avanza antes de la escritura del ciclo; en snd_fds.v, cada bajada de M2 aplica la escritura y después avanza. Así
// que la escritura apuntada en el ciclo N va en la bajada del ciclo N + 1. Salida: "ciclo nivel" en cada cambio
// (nivel 0-63 x 16, la escala de audio.txt).
#include "Vsnd_fds.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <vector>

struct Esc { unsigned long long c; unsigned a, v; };

int main(int argc, char** argv)
{
	if(argc < 4) {
		fprintf(stderr, "uso: replay fdsreg.txt salida.txt ULTIMO_CICLO\n");
		return 1;
	}
	std::vector<Esc> w;
	FILE* f = fopen(argv[1], "r");
	if(!f) { perror(argv[1]); return 1; }
	Esc e;
	while(fscanf(f, "%llu %x %x", &e.c, &e.a, &e.v) == 3) w.push_back(e);
	fclose(f);
	FILE* o = fopen(argv[2], "w");
	unsigned long long fin = strtoull(argv[3], nullptr, 10);
	Verilated::commandArgs(argc, argv);
	Vsnd_fds m;
	m.rst = 0; m.wr = 0; m.a = 0; m.d = 0; m.m2 = 1; m.eval();
	size_t i = 0;
	int ultimo = -1;
	for(unsigned long long k = 1; k <= fin; k++) {
		if(i < w.size() && w[i].c + 1 == k) {
			m.wr = 1; m.a = w[i].a & 0xFF; m.d = w[i].v; i++;
		} else {
			m.wr = 0;
		}
		while(i < w.size() && w[i].c + 1 < k) i++;     // (no debería pasar: una escritura por ciclo)
		m.m2 = 1; m.eval();
		m.m2 = 0; m.eval();
		int nivel = m.out * 16;
		if(nivel != ultimo) {
			fprintf(o, "%llu %d\n", k, nivel);
			ultimo = nivel;
		}
	}
	fclose(o);
	fprintf(stderr, "%zu escrituras, %llu ciclos\n", w.size(), fin);
	return 0;
}
