// n8model.cpp — Implementación de la interfaz C sobre el modelo Verilator (Vn8_sim_top).
#include "n8model.h"
#include "verilated.h"
#include "Vn8_sim_top.h"

namespace {
struct Model {
	VerilatedContext ctx;
	Vn8_sim_top top{&ctx, "n8"};
};

inline void PushInputs(Vn8_sim_top& t, const N8Pins* p)
{
	t.bios_off = p->bios_off;
	t.cpu_romsel_n = p->cpu_romsel_n;
	t.cpu_rw = p->cpu_rw;
	t.cpu_m2 = p->cpu_m2;
	t.ppu_rd_n = p->ppu_rd_n;
	t.ppu_wr_n = p->ppu_wr_n;
	t.cpu_a = p->cpu_a & 0x7FFF;
	t.cpu_din = p->cpu_din;
	t.ppu_a = p->ppu_a & 0x3FFF;
	t.ppu_din = p->ppu_din;
}

inline void PullOutputs(const Vn8_sim_top& t, N8Pins* p)
{
	p->ppu_dout=t.ppu_dout; p->ppu_doe=t.ppu_doe;
	p->cpu_irq = t.cpu_irq;
	p->ciram_ce_n = t.ciram_ce_n;
	p->ciram_a10 = t.ciram_a10;
	p->prg_ce_n = t.prg_ce_n;
	p->prg_we_n = t.prg_we_n;
	p->chr_ce_n = t.chr_ce_n;
	p->chr_we_n = t.chr_we_n;
	p->ram_ce = t.ram_ce;
	p->ram_we_n = t.ram_we_n;
	p->os_mode = t.os_mode;
	p->prg_map = t.prg_map;
	p->chr_map = t.chr_map;
	p->snd_level = t.snd_level;
	p->snd_on = t.snd_on;
	p->cpu_dout = t.cpu_dout;
	p->cpu_doe = t.cpu_doe;
}
}

extern "C" {

int n8_api_version(void) { return N8MODEL_API_VERSION; }

void* n8_create(void)
{
	Model* m = new Model();
	m->top.clk = 0;
	m->top.eval();
	return m;
}

void n8_destroy(void* p)
{
	Model* m = (Model*)p;
	m->top.final();
	delete m;
}

void n8_eval(void* p, N8Pins* pins)
{
	Model* m = (Model*)p;
	PushInputs(m->top, pins);
	m->top.eval();
	PullOutputs(m->top, pins);
}

void n8_tick(void* p, N8Pins* pins, int n)
{
	Model* m = (Model*)p;
	PushInputs(m->top, pins);
	for(int i = 0; i < n; i++) {
		m->top.clk = 1;
		m->top.eval();
		m->top.clk = 0;
		m->top.eval();
	}
	PullOutputs(m->top, pins);
}

}
