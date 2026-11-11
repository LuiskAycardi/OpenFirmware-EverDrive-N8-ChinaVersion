#!/usr/bin/env python3
"""romgen.py — ROM sintética para comparar un mapper con Mesen2 sin necesidad de juegos.

La ROM (iNES 1.0, como la ve el OS v13):
  - PRG de 512 KB: cada KB lleva su número en los bytes 0-1 (bajo, alto).
  - CHR de 512 KB (o CHR-RAM): cada KB lleva su número en los bytes 0-1 (bajo, alto | $80).
  - En TODOS los bancos de 8 KB, a partir de $1C10, el programa de prueba, y en $1F00 el arranque, con los
    vectores apuntando a él: arranque igual sea cual sea el banco que el mapper ponga en $E000 al encender.
El arranque copia el programa a la RAM ($0200) y salta allí, así el mapper puede cambiar los bancos de PRG
sin cortar el programa. El programa, con la PPU apagada y la IRQ del contador de tramas de la APU inhibida:
  1. elige una escritura pseudoaleatoria (LFSR de 16 bits, semilla fija) en $4100-$FFFF, con preferencia por
     las direcciones típicas de registros (bytes bajos $00-$03 y $F0-$FF), y la hace;
  2. lee el KB de PRG visible en $6000-$FC00 (40 ventanas de 1 KB), el de CHR en las 8 ventanas de $0000-$1FFF
     (por $2006/$2007) y el mirroring (escribe 4 valores en $2000/$2400/$2800/$2C00 y los vuelve a leer);
  3. lo deja en $0600-$0663 (y la escritura en $0670-$0672) y escribe en $07FF: el Lua del banco lo registra.
Las interrupciones se activan (CLI) al empezar cada paso y se desactivan antes de la marca. Si el mapper pide una
IRQ, el manejador (en el arranque de cada banco) anota en $0664-$0668 que la hubo, la dirección de la instrucción
interrumpida y X e Y (posición en los bucles de muestra), y vuelve con el bit I puesto: una por paso como mucho.
Así la ROM compara también cuándo dispara la IRQ (Mesen2 no da la línea de IRQ al Lua).
Uso: romgen.py MAPPER SALIDA.nes [--pasos N] [--chr-ram] [--mirroring h|v] [--semilla S] [--prg-kb N] [--chr-kb N]
"""
import argparse
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from asm6502 import Asm  # noqa: E402

CODE_RAM = 0x0200          # programa copiado en la RAM
PAYLOAD_OFF = 0x1C10       # dentro de cada banco de 8 KB
STUB_OFF = 0x1F00
SAMPLE = 0x0600            # 100 bytes de muestra por paso
LASTW = 0x0670             # dirección baja, alta y dato de la última escritura
STEP_MARK = 0x07FF         # escribir aquí = "paso listo" (lo vigila el Lua)
STEP_LO, STEP_HI = 0x07FB, 0x07FC
DONE = 0x07FD
IRQREC = SAMPLE + 100      # 5 bytes: IRQ sí/no, PC bajo, PC alto, X, Y de la primera IRQ del paso
# página cero
LFSR = 0x00                # 0x00-0x01
PTR = 0x08                 # 0x08-0x09
CNT = 0x06                 # 0x06-0x07 pasos hechos
DATA = 0x05


def program(steps, chr_ram, mmc5_registers=False, vs99=False, nwc105=False, wr_only=None):
    a = Asm(CODE_RAM)
    a.label("main")
    a.lda_imm(0x5A); a.sta_zp(LFSR)          # semilla (se puede cambiar en la ROM: offset fijo)
    a.lda_imm(0xC3); a.sta_zp(LFSR + 1)
    a.lda_imm(0); a.sta_zp(CNT); a.sta_zp(CNT + 1)
    if nwc105:
        # Complete the mapper105 I=0 -> I=1 startup handshake before sampling.
        a.lda_imm(0x80); a.sta_abs(0x8000)
        for value in (0,16):
            for bit in range(5):
                a.lda_imm((value >> bit) & 1); a.sta_abs(0xA000)
    if chr_ram:
        # marcar la CHR-RAM visible al principio: ventana i -> bytes 0-1 = i, $C0 | i
        a.ldy_imm(0)
        a.label("cr1")
        a.lda_abs(0x2002)
        a.tya(); a.asl_a(); a.asl_a(); a.sta_abs(0x2006); a.lda_imm(0); a.sta_abs(0x2006)
        a.tya(); a.sta_abs(0x2007); a.tya(); a.ora_imm(0xC0); a.sta_abs(0x2007)
        a.iny(); a.cpy_imm(8); a.bne("cr1")
    a.jsr("clrirq")
    a.jsr("sample")                          # muestra inicial (paso 0, sin escritura)
    a.lda_imm(0); a.sta_abs(LASTW); a.sta_abs(LASTW + 1); a.sta_abs(LASTW + 2)
    a.jsr("mark")

    a.label("loop")
    a.jsr("clrirq")
    a.cli()
    if nwc105:
        # Whole MMC1 serial transactions, not isolated random serial bits.
        a.lda_imm(0); a.sta_abs(LASTW); a.sta_abs("wr_lo")
        a.jsr("rand"); a.and_imm(3)
        for _ in range(5): a.asl_a()
        a.ora_imm(0x80); a.sta_abs("wr_hi"); a.sta_abs(LASTW + 1)
        a.jsr("rand"); a.and_imm(31); a.sta_zp(DATA); a.sta_abs(LASTW + 2)
        a.ldx_imm(5)
        a.label("nwc_serial")
        a.lda_zp(DATA); a.and_imm(1)
        a.byte(0x8D)
        a.label("wr_lo"); a.byte(0)
        a.label("wr_hi"); a.byte(0x80)
        a.lda_zp(DATA); a.lsr_a(); a.sta_zp(DATA)
        a.dex(); a.bne("nwc_serial")
    elif vs99:
        # Exercise the physical $4016 mapper99 bank bit, not only cartridge writes.
        a.lda_imm(0x16); a.sta_abs(LASTW)
        a.lda_imm(0x40); a.sta_abs(LASTW + 1)
        a.jsr("rand"); a.sta_abs(LASTW + 2); a.sta_abs(0x4016)
    elif mmc5_registers:
        # Deterministic register coverage, randomized bank data.
        a.lda_zp(CNT); a.and_imm(31); a.byte(0xAA)
        a.lda_absx("mmc5_regs"); a.sta_abs("wr_lo"); a.sta_abs(LASTW)
        a.lda_imm(0x51); a.sta_abs("wr_hi"); a.sta_abs(LASTW + 1)
        a.jsr("rand"); a.ora_imm(0x80)
        a.sta_abs(LASTW + 2)
        a.byte(0x8D)
        a.label("wr_lo"); a.byte(0)
        a.label("wr_hi"); a.byte(0x51)
    else:
        # ---- dirección alta. wr_only: "hi" = siempre $8000-$FFFF, "lo" = siempre $6000-$7FFF
        # (placas que solo decodifican un rango, p. ej. Bandai LZ93D50 / FCG-1/2)
        if wr_only == "lo":
            a.jsr("rand"); a.and_imm(0x1F); a.ora_imm(0x60); a.jmp("hiok")
        if wr_only is None:
            a.jsr("rand"); a.cmp_imm(0xB0); a.bcs("not8")
        a.jsr("rand"); a.ora_imm(0x80)                            # $8000-$FFFF (69 %)
        # sin escribir encima del programa ($1C00-$1FFF de cada banco de 8 KB): con conflictos de bus el dato
        # se mezclaría con el código (Mesen2 los emula; el N8 no los tiene). Esas direcciones pasan a $18xx-$1Bxx.
        a.pha(); a.and_imm(0x1C); a.cmp_imm(0x1C); a.bne("hi8ok")
        a.pla(); a.eor_imm(0x04); a.jmp("hiok")
        a.label("hi8ok"); a.pla(); a.jmp("hiok")
        if wr_only is None:
            a.label("not8")
            a.cmp_imm(0xD8); a.bcs("not6")
            a.jsr("rand"); a.and_imm(0x1F); a.ora_imm(0x60); a.jmp("hiok")   # $6000-$7FFF (16 %)
            a.label("not6")
            a.jsr("rand"); a.and_imm(0x1F); a.ora_imm(0x40)          # $4100-$5FFF (15 %)
            a.cmp_imm(0x40); a.bne("hiok"); a.lda_imm(0x41)
        a.label("hiok")
        a.sta_abs("wr_hi"); a.sta_abs(LASTW + 1)
        # ---- dirección baja
        a.jsr("rand"); a.cmp_imm(0x80); a.bcs("lo2")
        a.jsr("rand"); a.jmp("look")                              # cualquiera (50 %)
        a.label("lo2")
        a.cmp_imm(0xC0); a.bcs("lo3")
        a.jsr("rand"); a.and_imm(0x03); a.jmp("look")             # $x00-$x03 (25 %)
        a.label("lo3")
        a.jsr("rand"); a.ora_imm(0xF0)                            # $xF0-$xFF (25 %)
        a.label("look")
        a.sta_abs("wr_lo"); a.sta_abs(LASTW)
        # ---- dato y escritura (código automodificado: STA absoluto, sin lectura previa)
        a.jsr("rand"); a.sta_abs(LASTW + 2)
        a.byte(0x8D)                                              # sta $xxxx
        a.label("wr_lo"); a.byte(0x00)
        a.label("wr_hi"); a.byte(0x80)
    a.jsr("sample")
    a.sei()
    a.jsr("mark")
    # ---- ¿terminado?
    a.lda_zp(CNT); a.cmp_imm(steps & 0xFF); a.bne("again")
    a.lda_zp(CNT + 1); a.cmp_imm((steps >> 8) & 0xFF); a.beq("fin")
    a.label("again"); a.jmp("loop")
    a.label("fin")
    a.lda_imm(0xAA); a.sta_abs(DONE)
    a.label("halt"); a.jmp("halt")

    # ---- registro de IRQ a cero
    a.label("clrirq")
    a.lda_imm(0)
    for k in range(5):
        a.sta_abs(IRQREC + k)
    a.rts()

    # ---- paso listo: contador y marca para el Lua
    a.label("mark")
    a.inc_zp(CNT); a.bne("mk1"); a.inc_zp(CNT + 1)
    a.label("mk1")
    a.lda_zp(CNT); a.sta_abs(STEP_LO); a.lda_zp(CNT + 1); a.sta_abs(STEP_HI)
    a.sta_abs(STEP_MARK)
    a.rts()

    # ---- número pseudoaleatorio: 8 pasos de un LFSR de Galois de 16 bits (polinomio $B400)
    a.label("rand")
    a.ldx_imm(8)
    a.label("r1")
    a.lsr_zp(LFSR + 1); a.ror_zp(LFSR); a.bcc("r2")
    a.lda_zp(LFSR + 1); a.eor_imm(0xB4); a.sta_zp(LFSR + 1)
    a.label("r2")
    a.dex(); a.bne("r1")
    a.lda_zp(LFSR)
    a.rts()

    # ---- muestra: PRG, CHR y mirroring
    a.label("sample")
    a.lda_imm(0x00); a.sta_zp(PTR); a.lda_imm(0x60); a.sta_zp(PTR + 1)
    a.ldx_imm(0)
    a.label("s1")
    a.ldy_imm(0); a.lda_indy(PTR); a.sta_absx(SAMPLE); a.inx()
    a.iny(); a.lda_indy(PTR); a.sta_absx(SAMPLE); a.inx()
    a.lda_zp(PTR + 1); a.clc(); a.adc_imm(0x04); a.sta_zp(PTR + 1); a.bne("s1")
    a.lda_abs(0x2002)                                         # reinicia el conmutador de $2006
    a.ldy_imm(0)
    a.label("c1")
    a.tya(); a.asl_a(); a.asl_a(); a.sta_abs(0x2006); a.lda_imm(0); a.sta_abs(0x2006)
    a.lda_abs(0x2007)                                         # lectura con retardo (búfer)
    a.lda_abs(0x2007); a.sta_absx(SAMPLE); a.inx()
    a.lda_abs(0x2007); a.sta_absx(SAMPLE); a.inx()
    a.iny(); a.cpy_imm(8); a.bne("c1")
    a.ldy_imm(0)
    a.label("n1")
    a.tya(); a.asl_a(); a.asl_a(); a.ora_imm(0x20); a.sta_abs(0x2006); a.lda_imm(0); a.sta_abs(0x2006)
    a.tya(); a.ora_imm(0x10); a.sta_abs(0x2007)
    a.iny(); a.cpy_imm(4); a.bne("n1")
    a.ldy_imm(0)
    a.label("n2")
    a.tya(); a.asl_a(); a.asl_a(); a.ora_imm(0x20); a.sta_abs(0x2006); a.lda_imm(0); a.sta_abs(0x2006)
    a.lda_abs(0x2007); a.lda_abs(0x2007); a.sta_absx(SAMPLE); a.inx()
    a.iny(); a.cpy_imm(4); a.bne("n2")
    a.rts()
    if mmc5_registers:
        a.label("mmc5_regs")
        a.byte(0x14,0x15,0x16,0x17,0x00,0x01,0x20,0x21,
               0x22,0x23,0x24,0x25,0x26,0x27,0x30,0x13,
               0x00,0x01,0x14,0x15,0x16,0x17,0x20,0x21,
               0x04,0x05,0x06,0x07,0x28,0x29,0x2a,0x2b)
    return a.assemble()


def stub(payload_len):
    """Arranque en $FF00 (offset $1F00 de cada banco de 8 KB)."""
    a = Asm(0xFF00)
    a.label("reset")
    a.sei(); a.cld(); a.ldx_imm(0xFF); a.txs()
    a.lda_imm(0); a.sta_abs(0x2000); a.sta_abs(0x2001); a.sta_abs(0x4010)
    a.lda_imm(0x40); a.sta_abs(0x4017); a.lda_abs(0x4015)    # sin IRQ de la APU (tramas ni DMC)
    a.label("w1"); a.bit_abs(0x2002); a.bpl("w1")              # dos vblank: la PPU ya acepta $2006
    a.label("w2"); a.bit_abs(0x2002); a.bpl("w2")
    # copiar el programa ($FC10.. -> $0200..), hasta 3 páginas
    src = 0xE000 + PAYLOAD_OFF
    a.ldx_imm(0)
    a.label("cp")
    for page in range(3):
        a.lda_absx(src + page * 0x100); a.sta_absx(CODE_RAM + page * 0x100)
    a.inx(); a.bne("cp")
    a.jmp(CODE_RAM)
    a.label("nmi"); a.rti()
    # IRQ: anota la primera del paso y vuelve con I = 1 (la línea puede seguir activa hasta que el mapper la
    # reconozca). Pila tras guardar A, X, Y: $0101+S = Y, +2 = X, +3 = A, +4 = P, +5/+6 = PC.
    a.label("irq")
    a.pha(); a.txa(); a.pha(); a.tya(); a.pha()
    a.tsx()
    a.lda_absx(0x0104); a.ora_imm(0x04); a.sta_absx(0x0104)
    a.lda_abs(IRQREC); a.bne("irq2")
    a.lda_imm(1); a.sta_abs(IRQREC)
    a.lda_absx(0x0105); a.sta_abs(IRQREC + 1)
    a.lda_absx(0x0106); a.sta_abs(IRQREC + 2)
    a.lda_absx(0x0102); a.sta_abs(IRQREC + 3)
    a.lda_absx(0x0101); a.sta_abs(IRQREC + 4)
    a.label("irq2")
    a.pla(); a.tay(); a.pla(); a.tax(); a.pla()
    a.rti()
    code = a.assemble()
    return code, a.labels["nmi"], a.labels["irq"]


def build(mapper, steps=600, chr_ram=False, vertical=True, battery=True, seed=None, prg_kb=512, chr_kb=512,
          chr_ram_kb=None, prg_ram_kb=None, submapper=None, nvram_bytes=None, wr_only=None):
    """chr_ram_kb / prg_ram_kb: cabecera NES 2.0 con esos tamaños de CHR-RAM y PRG-RAM (Mesen2 da 8 KB de cada
    con una iNES 1). submapper / nvram_bytes: cabecera NES 2.0 con ese submapper y PRG-NVRAM en bytes (p. ej. la
    EEPROM de 256 bytes del Bandai LZ93D50). wr_only: "hi" o "lo" limita las escrituras a $8000+ o $6000-$7FFF."""
    prog = program(steps, chr_ram, mmc5_registers=(mapper == 5), vs99=(mapper == 99), nwc105=(mapper == 105),
                   wr_only=wr_only)
    if len(prog) > 0x2F0:
        sys.exit(f"programa demasiado grande: {len(prog)} bytes")
    if seed is not None:
        prog = bytearray(prog)
        prog[1] = seed & 0xFF                                  # lda #semilla_baja (primera instrucción)
        prog[5] = ((seed >> 8) & 0xFF) or 0x01
        prog = bytes(prog)
    stub_code, nmi, irq = stub(len(prog))
    prg = bytearray(b"\xFF" * (prg_kb * 1024))          # relleno $FF: neutro ante conflictos de bus (AND)
    for k in range(prg_kb):
        prg[k * 1024] = k & 0xFF
        prg[k * 1024 + 1] = k >> 8
    for b in range(prg_kb // 8):
        base = b * 0x2000
        prg[base + PAYLOAD_OFF: base + PAYLOAD_OFF + len(prog)] = prog
        prg[base + STUB_OFF: base + STUB_OFF + len(stub_code)] = stub_code
        for vec, addr in ((0x1FFA, nmi), (0x1FFC, 0xFF00), (0x1FFE, irq)):
            prg[base + vec] = addr & 0xFF
            prg[base + vec + 1] = addr >> 8
    chr_ = bytearray()
    if not chr_ram:
        chr_ = bytearray(chr_kb * 1024)
        for k in range(chr_kb):
            chr_[k * 1024] = k & 0xFF
            chr_[k * 1024 + 1] = (k >> 8) | 0x80
    h = bytearray(16)
    h[0:4] = b"NES\x1a"
    h[4] = (prg_kb // 16) & 0xFF
    h[5] = 0 if chr_ram else (chr_kb // 8) & 0xFF
    h[6] = ((mapper & 0x0F) << 4) | (1 if vertical else 0) | (2 if battery else 0)
    if mapper == 99: h[6] |= 8  # VS boards have four physical nametables.
    h[7] = mapper & 0xF0
    if (chr_ram and chr_ram_kb) or prg_ram_kb:
        def shift(kb):                                     # tamaño = 64 << n
            return (kb * 1024 // 64).bit_length() - 1
        h[7] |= 0x08                                       # NES 2.0
        n = shift(prg_ram_kb or 8)
        h[10] = (n << 4) if battery else n                 # PRG-NVRAM (con pila) o PRG-RAM
        h[11] = shift(chr_ram_kb or 8) if chr_ram else 0
    if submapper is not None:
        h[7] |= 0x08                                       # NES 2.0
        h[8] = ((submapper & 0x0F) << 4) | ((mapper >> 8) & 0x0F)
        if nvram_bytes:
            n = (nvram_bytes // 64).bit_length() - 1       # tamaño = 64 << n
            h[10] = (h[10] & 0x0F) | (n << 4)
    return bytes(h) + bytes(prg) + bytes(chr_)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("mapper", type=int)
    ap.add_argument("out")
    ap.add_argument("--pasos", type=int, default=600)
    ap.add_argument("--chr-ram", action="store_true")
    ap.add_argument("--mirroring", choices=("h", "v"), default="v")
    ap.add_argument("--sin-pila", action="store_true")
    ap.add_argument("--semilla", type=lambda x: int(x, 0))
    ap.add_argument("--prg-kb", type=int, default=512)
    ap.add_argument("--chr-kb", type=int, default=512)
    a = ap.parse_args()
    data = build(a.mapper, a.pasos, a.chr_ram, a.mirroring == "v", not a.sin_pila, a.semilla, a.prg_kb, a.chr_kb)
    pathlib.Path(a.out).write_bytes(data)
    print(f"{a.out}: mapper {a.mapper}, {len(data)} bytes")
