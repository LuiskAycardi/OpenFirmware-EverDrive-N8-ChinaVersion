// fmref.cpp — reference output of the VRC7 FM synth for the equivalence test of hdl/rtl/vrc7_fm.v.
// Uses emu2413 (MIT, from tools/mesen2) configured exactly as Mesen2's Vrc7Audio: VRC7 chip type and
// patch set, native rate 49716 Hz (one OPLL_calc per sample, no rate conversion). This file is test
// tooling only; nothing of emu2413 goes into the FPGA design.
//
// Input (stdin): lines "S" = number of samples, then "sample reg data" (decimal or 0x..) sorted by
// sample: the write is applied before computing that sample. Output (stdout): one signed sample per line.
#include <cstdio>
#include <cstdlib>
#include <vector>
#include "emu2413.h"

int main() {
    long total = 0;
    if (scanf("%li", &total) != 1) return 1;
    struct W { long s; unsigned r, d; };
    std::vector<W> w;
    long s; unsigned r, d;
    while (scanf("%li %i %i", &s, &r, &d) == 3) w.push_back({s, r, d});

    const int rate = 49716;
    OPLL *o = OPLL_new(rate * 72, rate);
    OPLL_setChipType(o, 1);
    OPLL_resetPatch(o, 1);

    size_t k = 0;
    for (long i = 0; i < total; i++) {
        while (k < w.size() && w[k].s <= i) { OPLL_writeReg(o, w[k].r, w[k].d); k++; }
        printf("%d\n", OPLL_calc(o));
    }
    OPLL_delete(o);
    return 0;
}
