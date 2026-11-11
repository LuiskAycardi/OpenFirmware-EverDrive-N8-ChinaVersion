// N8FpgaMapper.cpp — Mapper puente del banco de pruebas N8 (ver N8FpgaMapper.h).
//
// Modelo de tiempo (en relojes maestros NTSC, 12 por ciclo de CPU):
//   Mesen2 llama a ProcessCpuClock() al empezar cada ciclo (instante T ~ inicio de φ2) y
//   luego, si el acceso cae en $4020-$FFFF, a ReadRegister()/WriteRegister().
//   - M2 sube en T y baja en T+6 (la bajada se aplica en Advance(), en su momento exacto,
//     intercalada con los flancos de clk y con los cambios de dirección de la PPU).
//   - En un acceso al cartucho se adelanta la PPU hasta casi el final de φ2 y se deja correr
//     clk: así la FPGA ve A12 y M2 en el mismo orden que en la consola y los /CE ya están
//     estables (m2_ok necesita 4 muestras de clk con M2 alto) cuando se lee el dato.
//   - Cada cambio de dirección de la PPU llega con su instante (reloj maestro de la PPU +
//     desfase CPU/PPU) y se aplica después de hacer avanzar clk hasta ese instante.
#ifdef N8_FPGA_SIM
#include "pch.h"
#include "N8AudioLog.h"
#include "NES/Mappers/N8/N8FpgaMapper.h"
#include "NES/NesConsole.h"
#include "NES/NesControlManager.h"
#include "NES/NesCpu.h"
#include "NES/BaseNesPpu.h"
#include "NES/NesPpu.h"
#include <functional>
#include "NES/NesMemoryManager.h"
#include "NES/RomData.h"
#include "Shared/MessageManager.h"
#include "Utilities/HexUtilities.h"
#include <dlfcn.h>
#include <cstdlib>
#include <cstring>
#include <algorithm>

// Forward PPU writes unchanged while exposing the physical CPU bus to MMC5.
class N8PpuWriteObserver : public INesMemoryHandler {
    std::function<void(uint16_t,uint8_t)> _write;
public:
    explicit N8PpuWriteObserver(std::function<void(uint16_t,uint8_t)> write) : _write(write) {}
    void GetMemoryRanges(MemoryRanges&) override {}
    uint8_t ReadRam(uint16_t) override { return 0; }
    void WriteRam(uint16_t addr,uint8_t value) override { _write(addr,value); }
};

static constexpr double MasterHz = 21477272.0;
static int g_debug = -1;       // N8_DEBUG=n: traza de las primeras n lecturas/escrituras
static int g_traced = 0;
static bool DebugOn() {
	if(g_debug < 0) { const char* d = getenv("N8_DEBUG"); g_debug = d ? atoi(d) : 0; }
	return g_traced < g_debug;
}
static constexpr double M2HighLen = 6.0;     // relojes maestros con M2 alto

N8FpgaMapper::N8FpgaMapper() {}

BaseMapper* CreateN8FpgaMapper()
{
	return new N8FpgaMapper();
}

N8FpgaMapper::~N8FpgaMapper()
{
	if(_h) {
		_destroy(_h);
	}
	if(_lib) {
		dlclose(_lib);
	}
}

bool N8FpgaMapper::LoadModel()
{
	const char* path = getenv("N8_MODEL");
	if(!path) {
		fprintf(stderr, "[N8] falta N8_MODEL (ruta de libn8model.so)\n");
		return false;
	}
	_lib = dlopen(path, RTLD_NOW | RTLD_LOCAL);
	if(!_lib) {
		fprintf(stderr, "[N8] dlopen %s: %s\n", path, dlerror());
		return false;
	}
	auto ver = (n8_api_version_fn)dlsym(_lib, "n8_api_version");
	auto create = (n8_create_fn)dlsym(_lib, "n8_create");
	_destroy = (n8_destroy_fn)dlsym(_lib, "n8_destroy");
	_eval = (n8_eval_fn)dlsym(_lib, "n8_eval");
	_tick = (n8_tick_fn)dlsym(_lib, "n8_tick");
	if(!ver || !create || !_destroy || !_eval || !_tick || ver() != N8MODEL_API_VERSION) {
		fprintf(stderr, "[N8] %s no es una libn8model compatible\n", path);
		return false;
	}
	_h = create();
	return true;
}

void N8FpgaMapper::InitMapper() {}

void N8FpgaMapper::Eval()
{
	_eval(_h, &_p);
}

void N8FpgaMapper::M2Fall()
{
	// Los registros se capturan en la bajada de M2 con /ROMSEL todavía bajo;
	// /ROMSEL sube después (en la consola, ~15 ns más tarde).
	_p.cpu_m2 = 0;
	Eval();
	_p.cpu_romsel_n = 1;
	_p.cpu_rw = 1;
	Eval();
	_m2High = false;
	_fallPending = false;
}

void N8FpgaMapper::Advance(double t)
{
	// Flancos de clk hasta t, con la bajada de M2 en su instante exacto si cae en medio.
	while(true) {
		double nextFall = (_m2High && _fallPending) ? _fallAt : 1e300;
		double nextRdUp = _rdLow ? _rdUpAt : 1e300;
		double limit = std::min(t, std::min(nextFall, nextRdUp));
		if(_nextClkEdge <= limit) {
			int n = (int)((limit - _nextClkEdge) / _clkPeriod) + 1;
			_tick(_h, &_p, n);
			_nextClkEdge += n * _clkPeriod;
			_now = _nextClkEdge - _clkPeriod;
			continue;
		}
		if(nextRdUp <= t && nextRdUp <= nextFall) {
			_now = std::max(_now, nextRdUp);
			RdUp();
			continue;
		}
		if(nextFall <= t) {
			_now = nextFall;
			M2Fall();
			continue;
		}
		break;
	}
	if(t > _now) {
		_now = t;
	}
}

static int g_traceA12 = -1;
static bool TraceA12() {
	if(g_traceA12 < 0) { const char* e = getenv("N8_TRACE_A12"); g_traceA12 = (e && atoi(e)) ? 1 : 0; }
	return g_traceA12 == 1;
}

void N8FpgaMapper::SyncIrq()
{
	N8AudioLog(_console->GetCpu()->GetCycleCount(), _p.snd_level);
	bool irq = _p.cpu_irq != 0;
	if(irq != _irq && TraceA12()) {
		BaseNesPpu* ppu = _console->GetPpu();
		fprintf(stderr, "[N8] IRQ %d sl=%d pt=%u t=%.1f\n", irq ? 1 : 0, ppu->GetCurrentScanline(), ppu->GetCurrentCycle(), _now);
	}
	if(irq != _irq) {
		_irq = irq;
		if(irq) {
			_console->GetCpu()->SetIrqSource(IRQSource::External);
		} else {
			_console->GetCpu()->ClearIrqSource(IRQSource::External);
		}
	}
}

double N8FpgaMapper::CpuTime()
{
	return (double)_console->GetCpu()->GetMasterClockN8() + _timeOffset;
}

double N8FpgaMapper::PpuTime()
{
	return (double)_console->GetPpu()->GetMasterClockN8() + _console->GetCpu()->GetPpuOffsetN8() + _timeOffset;
}

double N8FpgaMapper::AccessPhaseStart()
{
	// Acceso dentro del ciclo abierto por ProcessCpuClock(): M2 subió en _cycleT.
	// Mesen lee algunos datos (p. ej. el vector de reset al encender) sin pasar por
	// ProcessCpuClock: en ese caso se genera un ciclo de bus completo (fase baja + subida
	// de M2), igual que en la consola, donde toda lectura ocurre en un ciclo con M2.
	if(_m2High && _fallPending) {
		return (double)_cycleT + _timeOffset;
	}
	double rise = _now + (12.0 - M2HighLen);
	Advance(rise);
	_p.cpu_a = 0;
	_p.cpu_rw = 1;
	_p.cpu_romsel_n = 1;
	_p.cpu_m2 = 1;
	Eval();
	_m2High = true;
	_fallPending = true;
	_fallAt = rise + M2HighLen;
	_synthetic = true;
	return rise;
}

void N8FpgaMapper::CatchUpPpu(int endCount)
{
	// Adelanta la PPU dentro de φ2 para que la FPGA vea los cambios de A12 en su momento.
	// NesPpu::Run() es un do/while que SIEMPRE ejecuta al menos un punto, y Mesen2 vuelve a
	// llamarlo al cerrar el ciclo (EndCpuCycle, hasta T+endCount-desfase). Si nosotros dejamos la
	// PPU sin ningún punto pendiente para esa llamada, ejecuta uno de más: la PPU se adelanta a la
	// CPU, la NMI cae en otra instrucción y el juego diverge (Solomon's Key: pila $01FD distinta
	// en el flag N). Por eso solo se adelanta hasta un punto antes de ese final.
	BaseNesPpu* ppu = _console->GetPpu();
	uint64_t div = ppu->GetMasterClockDividerN8();
	uint64_t end = _cycleT + endCount - _console->GetCpu()->GetPpuOffsetN8();
	if(end < div) {
		return;
	}
	uint64_t target = end - div;
	if(ppu->GetMasterClockN8() + div <= target) {
		ppu->Run(target);
	}
}

void N8FpgaMapper::SetCpuPins(uint16_t addr, bool rw, uint8_t data)
{
	_p.cpu_a = addr & 0x7FFF;
	_p.cpu_rw = rw ? 1 : 0;
	_p.cpu_din = data;
	_p.cpu_romsel_n = (addr & 0x8000) ? 0 : 1;   // M2 ya está alto
	Eval();
}

void N8FpgaMapper::BusCycleInit(uint16_t addr, bool rw, uint8_t data)
{
	// Ciclo de bus aislado (antes de que arranque la CPU de Mesen): fase baja y fase alta.
	Advance(_now + 12.0 - M2HighLen);
	_p.cpu_a = addr & 0x7FFF;
	_p.cpu_rw = rw ? 1 : 0;
	_p.cpu_din = data;
	_p.cpu_romsel_n = 1;
	Eval();
	_p.cpu_m2 = 1;
	_p.cpu_romsel_n = (addr & 0x8000) ? 0 : 1;
	Eval();
	_m2High = true;
	_fallPending = true;
	_fallAt = _now + M2HighLen;
	Advance(_fallAt + 0.01);
}

void N8FpgaMapper::InitMapper(RomData& romData)
{
	const char* mhz = getenv("N8_CLK_MHZ");
	double clkMhz = mhz ? atof(mhz) : 50.0;
	_clkPeriod = MasterHz / (clkMhz * 1e6);

	_prgSram.assign(0x80000, 0xFF);
	_chrSram.assign(0x80000, 0x00);
	// N8_PRGRAM_FILL: contenido inicial de la PRG-RAM (por defecto 0). difftest --prgram-fill lo pone igual
	// que la .sav de la referencia (p. ej. juegos que no arrancan con la SRAM de partidas a cero).
	const char* fill = getenv("N8_PRGRAM_FILL");
	_prgRam.assign(0x20000, fill ? (uint8_t)strtol(fill, nullptr, 0) : 0x00);
	memcpy(_prgSram.data(), _prgRom, std::min<uint32_t>(_prgSize, 0x80000));
	if(_chrRomSize) {
		memcpy(_chrSram.data(), _chrRom, std::min<uint32_t>(_chrRomSize, 0x80000));
	}

	if(!LoadModel()) {
		throw std::runtime_error("N8: no se pudo cargar el modelo");
	}
	_p = {};
	_p.bios_off = 1;
	_p.cpu_m2 = 0;
	_p.cpu_romsel_n = 1;
	_p.cpu_rw = 1;
	_p.cpu_a = 0;
	_p.cpu_din = 0;
	_p.ppu_a = 0;
	_p.ppu_rd_n = 1;
	_p.ppu_wr_n = 1;
	Eval();

	// Configuración como el OS v13 (rutina en $BB7E del OS.BIN): cabecera iNES cruda.
	NesHeader& h = romData.Info.Header;
	uint8_t prg16 = h.PrgCount ? h.PrgCount : 1;
	uint8_t chr8 = h.ChrCount;
	uint8_t mapper = (uint8_t)((h.Byte6 >> 4) | (h.Byte7 & 0xF0));
	_mmc5=(mapper==5);
	_ppuRam=_mmc5 || mapper==253;
	_ppuRamFree=(mapper==253);
	_vs99=(mapper==99);
	struct { uint8_t reg, val; } cfg[] = {
		{ 132, (uint8_t)(prg16 - 1) },
		{ 133, (uint8_t)(chr8 ? chr8 - 1 : 0xFF) },
		{ 134, (uint8_t)(h.Byte6 & 0x1B) },
		{ 136, 0 },
		{ 131, mapper },
	};
	// Solo el MMC2/MMC4 (9, 10) usa /RD en el RTL (latches con clk). Las reglas de tiempo de /RD del puente
	// (fase baja completa y fase alta mínima, ver FinishRead y MapperReadVram) se aplican solo ahí, para no
	// mover el tiempo ya validado de los demás mappers (p. ej. la IRQ del MMC3).
	_rdTiming = (mapper == 9 || mapper == 10);
	{
		// N8_RD_RULES = máscara de reglas de /RD para el MMC2/MMC4: 1 sin adelanto ALE, 2 completar la fase baja,
		// 4 fase alta mínima. Por defecto 4. Con 7 los dos Fire Emblem (MMC4) salen idénticos a Mesen2 y Punch-Out
		// (MMC2) no; con 4, al revés (Fire Emblem: diferencias pequeñas en 30-100 de 1500 fotogramas). El latch
		// antiguo, que no depende de la duración de /RD, sale idéntico siempre: lo que queda es cómo comprime
		// el banco /RD en las ráfagas de la PPU de Mesen2 (2026-11-06; ver docs/banco-pruebas.md).
		const char* e = getenv("N8_RD_RULES");
		_rdRules = e ? atoi(e) : 4;
	}

	_now = -1e6;
	_nextClkEdge = _now;
	for(int i = 0; i < 4; i++) {
		BusCycleInit(0x0000, true, 0);
	}
	for(auto& c : cfg) {
		BusCycleInit(0x4400, false, c.reg);
		BusCycleInit(0x4401, false, c.val);
	}
	for(int i = 0; i < 4; i++) {
		BusCycleInit(0x0000, true, 0);
	}
	if(_p.os_mode) {
		MessageManager::Log("[N8] la FPGA sigue en modo OS tras la configuración");
	}

	// El emulador empieza en el reloj maestro 0: el modelo continúa desde ahí.
	_now = 0;
	_nextClkEdge = 0;
	_m2High = false;
	_fallPending = false;
	_ready = true;

	MessageManager::Log("[N8] mapper " + std::to_string(mapper) + ", PRG " + std::to_string(prg16 * 16) +
		" KB, CHR " + (chr8 ? std::to_string(chr8 * 8) + " KB" : string("RAM")) +
		", MAP_CFG $" + HexUtilities::ToHex((uint8_t)(h.Byte6 & 0x1B)) + ", clk " + std::to_string(clkMhz) + " MHz");
}

void N8FpgaMapper::OnAfterResetPowerOn()
{
    // Mapper99 sees controller strobes physically. Preserve Mesen's controller
    // handler as well; an observer installed before power-on is overwritten.
    if(_vs99) {
        _controllerWriteObserver.reset(new N8PpuWriteObserver([this](uint16_t addr,uint8_t value) {
            WriteRegister(addr,value);
            static_cast<NesControlManager*>(_console->GetControlManager())->WriteRam(addr,value);
        }));
        _console->GetMemoryManager()->RegisterWriteHandler(_controllerWriteObserver.get(),0x4016,0x4016);
    }

    if(_mmc5) {
        _ppuWriteObserver.reset(new N8PpuWriteObserver([this](uint16_t addr,uint8_t value) {
            WriteRegister(addr,value);
            _console->GetPpu()->WriteRam(addr,value);
        }));
        _console->GetMemoryManager()->RegisterWriteHandler(_ppuWriteObserver.get(),0x2000,0x3fff);
    }
}

void N8FpgaMapper::ProcessCpuClock()
{
	if(!_ready) {
		return;
	}
	_cycleT = _console->GetCpu()->GetMasterClockN8();
	double t = (double)_cycleT + _timeOffset;
	Advance(t);   // bajada de M2 del ciclo anterior + fase baja

	_p.cpu_a = 0;
	_p.cpu_rw = 1;
	_p.cpu_romsel_n = 1;
	_p.cpu_m2 = 1;
	Eval();
	_m2High = true;
	_fallPending = true;
	_fallAt = t + M2HighLen;
	SyncIrq();
}

uint8_t N8FpgaMapper::ReadRegister(uint16_t addr)
{
	if(!_ready) {
		return 0;
	}
	double base = AccessPhaseStart();
	SetCpuPins(addr, true, 0);
	if(!_synthetic) {
		CatchUpPpu(7);   // lectura: Mesen cierra el ciclo en T+7
	}
	Advance(base + M2HighLen - 0.5);

	uint32_t low = addr & 0x3FF;
	uint8_t value;
	if(!_p.prg_ce_n) {
		value = _prgSram[((uint32_t)(_p.prg_map & 0x1FF) << 10) | low];
	} else if(_p.ram_ce) {
		value = _prgRam[((uint32_t)(_p.prg_map & 0x7F) << 10) | low];
	} else {
		value = _console->GetMemoryManager()->GetOpenBus();
	}
	if(_p.cpu_doe) {
		// la FPGA conduce algunos bits (lectura de registro, fase 3d); el resto queda en bus abierto
		value = (value & ~_p.cpu_doe) | (_p.cpu_dout & _p.cpu_doe);
	}
	if(DebugOn()) {
		g_traced++;
		fprintf(stderr, "[N8] t=%.1f R %04X map=%03X prg_ce_n=%d ram_ce=%d os=%d m2=%d -> %02X\n", _now, addr,
			_p.prg_map, _p.prg_ce_n, _p.ram_ce, _p.os_mode, _p.cpu_m2, value);
	}
	_p.cpu_din=value; Eval(); // physical read bus, including MMC5 PCM
	FinishSynthetic();
	SyncIrq();
	return value;
}

void N8FpgaMapper::WriteRegister(uint16_t addr, uint8_t value)
{
	if(!_ready) {
		return;
	}
	double base = AccessPhaseStart();
	SetCpuPins(addr, false, value);
	// Experimento N8_EARLY_WRITE=1: imitar a Mesen2, que aplica las escrituras a registros en el
	// instante de la escritura. Se baja M2 enseguida (sin dejar que la PPU avance), así los
	// registros cambian antes de que la PPU dibuje el resto del ciclo. Solo para registros
	// ($8000+ y $4020-$5FFF); la PRG-RAM necesita M2 alto (m2_ok) y sigue igual.
	static int early = -1;
	if(early < 0) { const char* e = getenv("N8_EARLY_WRITE"); early = (e && atoi(e)) ? 1 : 0; }
	if(early && !_synthetic && (addr >= 0x8000 || addr < 0x6000)) {
		_fallAt = std::max(_now, base) + 0.01;
		Advance(_fallAt + 0.001);
		SyncIrq();
		return;
	}
	if(!_synthetic) {
		CatchUpPpu(5);   // escritura: Mesen cierra el ciclo en T+5
	}
	Advance(base + M2HighLen - 0.5);

	uint32_t low = addr & 0x3FF;
	if(_p.ram_ce && !_p.ram_we_n) {
		_prgRam[((uint32_t)(_p.prg_map & 0x7F) << 10) | low] = value;
	}
	if(!_p.prg_ce_n && !_p.prg_we_n) {
		_prgSram[((uint32_t)(_p.prg_map & 0x1FF) << 10) | low] = value;
	}
	FinishSynthetic();
	SyncIrq();
}

void N8FpgaMapper::FinishSynthetic()
{
	if(_synthetic) {
		Advance(_fallAt + 0.01);
		_synthetic = false;
	}
}

static int g_traceRd = -1;
static bool TraceRd() {
	if(g_traceRd < 0) { const char* e = getenv("N8_TRACE_RD"); g_traceRd = (e && atoi(e)) ? 1 : 0; }
	return g_traceRd == 1;
}
static bool IsLatchTrigger(uint16_t a) {
	uint16_t m = a & 0x0FF8;
	return m == 0x0FD8 || m == 0x0FE8;
}

void N8FpgaMapper::RdUp()
{
	if(_trTrig == 1) {
		_trLowTicks = (int)((_nextClkEdge - _trLowStart) / _clkPeriod + 0.5);
		_trHighStart = _nextClkEdge;
		_trTrig = 2;
	}
	_rdLow = false;
	_lastRdUp = _now;
	_p.ppu_rd_n = 1;
	Eval();
}

double N8FpgaMapper::RdLimit()
{
	// Hasta dónde pueden adelantar clk las reglas de /RD: antes de la subida de M2 del ciclo siguiente
	// (cycleT + 12) y, si hay un acceso de la CPU en curso (M2 alto), antes de su bajada de M2. Pasarla aquí
	// soltaba /ROMSEL antes de que el puente leyera la PRG y la CPU recibía bus abierto (Punch-Out, 2026-11-06).
	double limit = (double)_cycleT + _timeOffset + 11.5;
	if(_m2High && _fallPending) {
		limit = std::min(limit, _fallAt - 0.6);
	}
	return limit;
}

void N8FpgaMapper::FinishRead()
{
	if(!_rdLow) {
		return;
	}
	// Mesen2 a veces entrega lecturas de la PPU con su tiempo por detrás del tiempo del modelo (que ya avanzó
	// con la CPU). Sin esto, la lectura anterior se cortaba en el acto (/RD bajo 0-2 ciclos de clk) y el latch
	// del MMC2/MMC4, que exige 5, perdía disparos en el banco (Fire Emblem Gaiden, 2026-11-06). En la consola
	// /RD dura siempre ~186 ns. Se completa la fase baja sin pasar de cycleT + 11,5 (antes de la subida de M2).
	if(_rdTiming && (_rdRules & 2)) {
		double limit = RdLimit();
		if(_now < _rdUpAt && _now < limit) {
			Advance(std::min(_rdUpAt, limit));
		}
	}
	if(_rdLow) {
		RdUp();
	}
}

void N8FpgaMapper::NotifyVramAddressChange(uint16_t addr)
{
	if(!_ready) {
		return;
	}
	Advance(PpuTime());
	FinishRead();   // acceso nuevo antes de tiempo (p. ej. $2006): la lectura anterior termina aquí
	if(TraceA12() && ((addr ^ _p.ppu_a) & 0x1000)) {
		BaseNesPpu* ppu = _console->GetPpu();
		fprintf(stderr, "[N8] A12 %d sl=%d pt=%u t=%.1f addr=%04X\n", (addr >> 12) & 1, ppu->GetCurrentScanline(), ppu->GetCurrentCycle(), _now, addr);
	}
	_p.ppu_a = addr & 0x3FFF;
	Eval();
	// En la consola clk corre siempre. Aquí solo avanza con los eventos: sin este adelanto, la IRQ
	// que provoca un cambio de A12 no se vería hasta el evento siguiente, y Mesen2 muestrea la IRQ
	// al cerrar el ciclo, antes de ese evento (la IRQ llegaba un ciclo tarde: prueba 4 de blargg).
	// La dirección de la PPU dura al menos un punto (4 relojes maestros): se adelanta hasta 3, sin
	// pasar del cierre del ciclo de CPU actual (+9.5), para no tocar la subida de M2 del siguiente.
	// Con el MMC2/MMC4 no: no tiene IRQ, y este adelanto ponía el tiempo del modelo por delante del de la PPU,
	// así que las lecturas siguientes llegaban "en el pasado" y /RD se comprimía (Punch-Out, Fire Emblem).
	if(!_rdTiming || !(_rdRules & 1)) {
		Advance(std::min(PpuTime() + 3.0, (double)_cycleT + _timeOffset + 9.5));
	}
	SyncIrq();
}

uint8_t N8FpgaMapper::MapperReadVram(uint16_t addr, MemoryOperationType operationType)
{
	if(!_ready) {
		return 0;
	}
	addr &= 0x3FFF;
	FinishRead();
	// /RD alto al menos 2,4 relojes maestros entre dos lecturas (en la consola, ~4: un punto de PPU). Sin
	// esto, cuando el adelanto de NotifyVramAddressChange se recorta al final del ciclo de CPU, la lectura
	// siguiente bajaba /RD ~1 reloj maestro después de subir y el latch del MMC2/MMC4 (que necesita 5 ciclos
	// de clk con /RD alto) perdía el cambio (Fire Emblem, 2026-11-06). Nunca pasa de cycleT + 11,5: la
	// subida de M2 del ciclo siguiente es en cycleT + 12.
	{
		double minFall = _lastRdUp + 2.4;
		double limit = RdLimit();
		if(_rdTiming && (_rdRules & 4) && _now < minFall && _now < limit) {
			Advance(std::min(minFall, limit));
		}
	}
	if(TraceRd() && _trTrig == 2) {
		int high = (int)((_nextClkEdge - _trHighStart) / _clkPeriod + 0.5);
		BaseNesPpu* ppu = _console->GetPpu();
		fprintf(stderr, "[RD] %04X bajo=%d alto=%d sl=%d pt=%u siguiente=%04X\n", _trAddr, _trLowTicks, high,
			ppu->GetCurrentScanline(), ppu->GetCurrentCycle(), addr);
		_trTrig = 0;
	}
	_p.ppu_a = addr;
	_p.ppu_rd_n = 0;
	Eval();
	if(TraceRd() && IsLatchTrigger(addr)) {
		_trTrig = 1; _trLowStart = _nextClkEdge; _trAddr = addr;
	}
	// RAM interna síncrona (clk): dejar pasar ~2 relojes de clk con la dirección puesta antes de tomar el dato
	if(_ppuRam) Advance(std::min(_now+2.4, RdLimit()));
	// 253: la CHR-RAM interna (M4K) necesita un flanco de clk con la dirección puesta. En la consola clk
	// corre siempre (~9 flancos por punto de PPU); aquí Advance() puede quedar recortado por RdLimit() y la
	// RAM daría el dato de la dirección anterior. El 253 no tiene otra lógica en el dominio de clk, así que
	// se le dan 3 flancos sin mover el tiempo del banco.
	if(_ppuRamFree) { _tick(_h, &_p, 3); }
	uint8_t value;
	if(!_p.chr_ce_n) {
		value = _chrSram[((uint32_t)(_p.chr_map & 0x1FF) << 10) | (addr & 0x3FF)];
	} else if(!_p.ciram_ce_n) {
		value = _ciram[((_p.ciram_a10 & 1) << 10) | (addr & 0x3FF)];
	} else {
		value = 0xFF;   // nadie conduce el bus: pull-up débil en ppu_d (QSF) -> $FF (mappers 93 y 185)
	}
	value=(value & ~_p.ppu_doe) | (_p.ppu_dout & _p.ppu_doe);
	// En la consola /RD queda bajo ~1 punto de PPU (4 relojes maestros) y la lógica que lo filtra con
	// clk (latches del MMC2/MMC4) necesita verlo así. Advance() lo sube en su instante.
	// Se cuenta desde ahora (_now), no desde PpuTime(): NotifyVramAddressChange ya adelantó clk hasta 3
	// relojes maestros con la dirección puesta (fase ALE), y contando desde PpuTime() /RD quedaba bajo
	// solo ~1 reloj maestro (2-3 ciclos de clk a 50 MHz): el latch nuevo del MMC2/MMC4 a veces no llegaba a
	// capturar la lectura y el banco divergía de Mesen2 (corregido el 2026-11-06).
	_rdLow = true;
	_rdUpAt = std::max(PpuTime(), _now) + 4.0;
	return value;
}

void N8FpgaMapper::MapperWriteVram(uint16_t addr, uint8_t value)
{
	if(!_ready) {
		return;
	}
	addr &= 0x3FFF;
	FinishRead();
	_p.ppu_a = addr;
	_p.ppu_din=value;
	_p.ppu_wr_n = 0;
	Eval();
	if(_ppuRam) Advance(std::min(_now+2.4,(double)_cycleT+_timeOffset+11.5));
	if(_ppuRamFree) { _tick(_h, &_p, 3); }
	if(!_p.chr_ce_n) {
		if(!_p.chr_we_n) {
			_chrSram[((uint32_t)(_p.chr_map & 0x1FF) << 10) | (addr & 0x3FF)] = value;
		}
	} else if(!_p.ciram_ce_n) {
		_ciram[((_p.ciram_a10 & 1) << 10) | (addr & 0x3FF)] = value;
	}
	_p.ppu_wr_n = 1;
	Eval();
}
#endif
