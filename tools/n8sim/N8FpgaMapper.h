#pragma once
// N8FpgaMapper.h — Mapper puente del banco de pruebas N8 (GPL-3, como Mesen2).
// Ejecuta nuestro hdl/rtl/n8_top.v (compilado con Verilator) como si fuera el cartucho:
// mueve M2, /ROMSEL, R/W, el bus de direcciones/datos y PPU A0-A13 ciclo a ciclo, hace
// avanzar el reloj clk de la FPGA entre medias y modela las memorias de la placa del N8
// (SRAM PRG 512 KB, SRAM CHR 512 KB, PRG-RAM 128 KB) y la CIRAM de 2 KB de la consola.
// Antes de arrancar configura la FPGA igual que el OS v13 (registros 132-134, 136, 131).
// Solo se compila con N8_FPGA_SIM (make -C tools/n8sim mesen) y se activa con la variable
// de entorno N8_FPGA=1; el modelo se carga de N8_MODEL (libn8model.so, make -C tools/n8sim model). Fuente: tools/n8sim/N8FpgaMapper.h (se copia a Mesen2).
#ifdef N8_FPGA_SIM
#include "pch.h"
#include "NES/BaseMapper.h"
#include "n8model.h"
#include "NES/INesMemoryHandler.h"

class N8FpgaMapper : public BaseMapper
{
private:
	void* _lib = nullptr;          // libn8model.so (N8_MODEL)
	void* _h = nullptr;            // instancia del modelo
	n8_destroy_fn _destroy = nullptr;
	n8_eval_fn _eval = nullptr;
	n8_tick_fn _tick = nullptr;
	N8Pins _p = {};
	bool _mmc5=false;
	bool _ppuRam=false;   // el mapper conduce el bus de la PPU con una RAM síncrona (MMC5, 253)
	bool _ppuRamFree=false; // 253: flancos de clk extra en cada acceso PPU (sin mover el tiempo del banco)
	bool _vs99=false;
	std::unique_ptr<INesMemoryHandler> _controllerWriteObserver;
	std::unique_ptr<INesMemoryHandler> _ppuWriteObserver;

	vector<uint8_t> _prgSram;     // 512 KB (juego)
	vector<uint8_t> _chrSram;     // 512 KB
	vector<uint8_t> _prgRam;      // 128 KB (pila)
	uint8_t _ciram[0x800] = {};   // nametables de la consola

	double _now = 0;              // tiempo del modelo, en relojes maestros
	double _nextClkEdge = 0;      // próximo flanco de subida de clk
	double _clkPeriod = 0;        // relojes maestros por ciclo de clk
	bool _m2High = false;
	bool _fallPending = false;
	double _fallAt = 0;
	bool _rdLow = false;          // /RD de la PPU bajo (lectura en curso)
	double _rdUpAt = 0;           // instante en que sube /RD
	double _lastRdUp = -1e300;    // instante en que subió /RD por última vez
	int _rdRules = 4;             // N8_RD_RULES (ver InitMapper)
	bool _rdTiming = false;       // reglas de tiempo de /RD (solo MMC2/MMC4, los únicos que lo miran en el RTL)
	void FinishRead();            // termina la lectura en curso antes de otro acceso de la PPU
	double RdLimit();             // límite de tiempo para esas reglas (antes de la bajada y la subida de M2)
	// N8_TRACE_RD=1: ciclos de clk con /RD bajo y alto en las lecturas que disparan los latches del MMC2/MMC4
	int _trTrig = 0;              // 0 = nada; 1 = lectura de disparo con /RD bajo; 2 = /RD alto tras ella
	double _trLowStart = 0, _trHighStart = 0; int _trLowTicks = 0; uint16_t _trAddr = 0;
	void RdUp();
	uint64_t _cycleT = 0;         // reloj maestro de la CPU al empezar el ciclo actual
	double _timeOffset = 0;       // la configuración inicial ocurre en tiempo negativo
	bool _irq = false;
	bool _ready = false;
	bool _synthetic = false;      // acceso fuera de ProcessCpuClock (ciclo de bus generado aquí)

	bool LoadModel();
	void Eval();
	void M2Fall();
	void Advance(double t);
	void SyncIrq();
	void BusCycleInit(uint16_t addr, bool rw, uint8_t data);
	void SetCpuPins(uint16_t addr, bool rw, uint8_t data);
	double AccessPhaseStart();
	void CatchUpPpu(int endCount);
	void FinishSynthetic();
	double CpuTime();
	double PpuTime();

protected:
	uint16_t GetPrgPageSize() override { return 0x2000; }
	uint16_t GetChrPageSize() override { return 0x0400; }
	uint16_t RegisterStartAddress() override { return 0x4020; }
	uint16_t RegisterEndAddress() override { return 0xFFFF; }
	bool AllowRegisterRead() override { return true; }
	bool EnableCpuClockHook() override { return true; }
	bool EnableCustomVramRead() override { return true; }
	bool EnableVramAddressHook() override { return true; }
	uint32_t GetWorkRamSize() override { return 0; }
	uint32_t GetSaveRamSize() override { return 0; }

	void InitMapper() override;
	void InitMapper(RomData& romData) override;

	uint8_t ReadRegister(uint16_t addr) override;
	void WriteRegister(uint16_t addr, uint8_t value) override;
	void ProcessCpuClock() override;
	void OnAfterResetPowerOn() override;
	void NotifyVramAddressChange(uint16_t addr) override;
	uint8_t MapperReadVram(uint16_t addr, MemoryOperationType operationType) override;
	void MapperWriteVram(uint16_t addr, uint8_t value) override;

public:
	N8FpgaMapper();
	~N8FpgaMapper();
};
#endif
