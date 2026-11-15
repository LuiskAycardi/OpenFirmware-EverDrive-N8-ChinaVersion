#!/usr/bin/env python3
"""hacer_rom_irq65.py — ROM de prueba propia del IRQ del mapper 65 (Irem H3001): rom/irq65.nes.

El H3001 tiene un contador de 16 bits que baja en cada ciclo de CPU (con M2) y da IRQ al llegar a 0. La ROM lo
programa con 4 valores de recarga y, con un bucle de 5 ciclos por vuelta (INX/BNE), cuenta cuántas vueltas da la
CPU hasta que llega el IRQ. Lo repite sin parar y muestra en hexadecimal, una fila por valor:

    recarga   último   mínimo   máximo          (vueltas del bucle; 256 por cada incremento del byte alto)

En un chip que cuenta bien, último = mínimo = máximo y coinciden con Mesen2 y con nuestro Verilog. Si la FPGA cuenta
ciclos de más (rebotes o flancos lentos de M2), las vueltas salen menos y/o el mínimo y el máximo se separan.
Durante cada medida la NMI está desactivada (no roba ciclos); entre tandas se pinta la pantalla y se lee el mando
(así el Nano del banco ve un juego que lee el mando y puede armarse).

  python3 -I rom/hacer_rom_irq65.py      -> rom/irq65.nes
"""
import pathlib
import sys

AQUI = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(AQUI))
import hacer_rom  # noqa: E402
from hacer_rom import Asm, tesela  # noqa: E402

hacer_rom.OPS.update({
    ("cli", None): 0x58, ("dey", None): 0x88, ("sec", None): 0x38, ("clc", None): 0x18, ("asl", None): 0x0A,
    ("lda", "zp,x"): 0xB5, ("sta", "zp,x"): 0x95, ("lda", "abs,y"): 0xB9, ("sta", "abs,y"): 0x99,
    ("stx", "zp"): 0x86, ("sty", "zp"): 0x84, ("ldx", "zp"): 0xA6, ("cmp", "zp,x"): 0xD5, ("sbc", "zp,x"): 0xF5,
    ("cmp", "zp"): 0xC5, ("cmp", "#"): 0xC9, ("sbc", "zp"): 0xE5, ("bcs", "rel"): 0xB0, ("cpx", "zp"): 0xE4,
})
hacer_rom.TAM.update({"zp,x": 2, "abs,y": 3})

RECARGAS = [0x0100, 0x1000, 0x4000, 0xF000]
NMIF, BOT, LEC, T, TX, TY = 0x00, 0x01, 0x02, 0x03, 0x04, 0x05
RLO, RHI, MNLO, MNHI, MXLO, MXHI = 0x10, 0x14, 0x18, 0x1C, 0x20, 0x24
BUF = 0x0300
COLS = 19                           # rrrr ' ' uuuu ' ' mmmm ' ' MMMM
FILA0, COL0 = 8, 6
BLANCO = 0x10

FUENTE = {   # 3x5
    0: "111101101101111", 1: "010110010010111", 2: "111001111100111", 3: "111001111001111",
    4: "101101111001001", 5: "111100111001111", 6: "111100111101111", 7: "111001010010010",
    8: "111101111101111", 9: "111101111001111", 10: "010101111101101", 11: "110101110101110",
    12: "111100100100111", 13: "110101101101110", 14: "111100111100111", 15: "111100111100100",
}


def chr_rom():
    ts = []
    for d in range(16):
        g = FUENTE[d]
        filas = [[0] * 8 for _ in range(8)]
        for y in range(5):
            for x in range(3):
                if g[y * 3 + x] == "1":
                    filas[y + 1][x + 2] = 1
        ts.append(tesela(filas))
    ts.append(tesela([[0] * 8 for _ in range(8)]))          # 0x10 en blanco
    return b"".join(ts).ljust(0x2000, b"\0")


def programa():
    a = Asm(0xE000)
    a.et("reset")
    a("sei"); a("cld")
    a("ldx", "#", 0x40); a("stx", "abs", 0x4017)
    a("ldx", "#", 0xFF); a("txs"); a("inx")
    a("stx", "abs", 0x2000); a("stx", "abs", 0x2001); a("stx", "abs", 0x4010)
    a("bit", "abs", 0x2002)
    a.et("vb1"); a("bit", "abs", 0x2002); a("bpl", "rel", "vb1")
    a("lda", "#", 0)
    a.et("borra"); a("sta", "zp,x", 0); a("sta", "abs,x", 0x0300); a("inx"); a("bne", "rel", "borra")
    a.et("vb2"); a("bit", "abs", 0x2002); a("bpl", "rel", "vb2")
    # mapper: PRG 0, 1, 2 (el código está en el banco fijo $E000); CHR 0-7 en orden; IRQ apagada
    for i, reg in enumerate((0x8000, 0xA000, 0xC000)):
        a("lda", "#", i); a("sta", "abs", reg)
    for i in range(8):
        a("lda", "#", i); a("sta", "abs", 0xB000 + i)
    a("lda", "#", 0); a("sta", "abs", 0x9003)
    # paleta y pantalla en blanco
    a("lda", "#", 0x3F); a("sta", "abs", 0x2006); a("lda", "#", 0); a("sta", "abs", 0x2006)
    a("ldx", "#", 0)
    a.et("pal"); a("lda", "abs,x", "PALETA"); a("sta", "abs", 0x2007); a("inx"); a("cpx", "#", 32)
    a("bne", "rel", "pal")
    a("lda", "#", 0x20); a("sta", "abs", 0x2006); a("lda", "#", 0); a("sta", "abs", 0x2006)
    a("ldy", "#", 4); a("ldx", "#", 0)
    a.et("nt"); a("lda", "#", BLANCO); a("sta", "abs", 0x2007); a("inx"); a("bne", "rel", "nt")
    a("dey"); a("bne", "rel", "nt")
    a("lda", "#", 0x23); a("sta", "abs", 0x2006); a("lda", "#", 0xC0); a("sta", "abs", 0x2006)
    a("lda", "#", 0); a("ldx", "#", 64)
    a.et("atr"); a("sta", "abs", 0x2007); a("dex"); a("bne", "rel", "atr")
    a("lda", "#", 0); a("sta", "abs", 0x2005); a("sta", "abs", 0x2005)
    a("lda", "#", 0xFF); a("ldx", "#", 7)
    a.et("ini_min"); a("sta", "zp,x", MNLO); a("dex"); a("bpl", "rel", "ini_min")
    a("lda", "#", BLANCO); a("ldx", "#", 0)
    a.et("buf_blanco"); a("sta", "abs,x", BUF); a("inx"); a("bne", "rel", "buf_blanco")

    # ---------------- bucle principal: 4 medidas, preparar el texto, esperar una NMI
    a.et("principal")
    a("lda", "#", 0); a("sta", "zp", T)
    a.et("medidas")
    a("ldx", "zp", T)
    a("jsr", "abs", "medir")
    a("ldx", "zp", T)
    a("lda", "zp", TX); a("sta", "zp,x", RLO); a("lda", "zp", TY); a("sta", "zp,x", RHI)
    # mínimo: si R < MN
    a("lda", "zp,x", RLO); a("cmp", "zp,x", MNLO); a("lda", "zp,x", RHI); a("sbc", "zp,x", MNHI)
    a("bcs", "rel", "no_min")
    a("lda", "zp,x", RLO); a("sta", "zp,x", MNLO); a("lda", "zp,x", RHI); a("sta", "zp,x", MNHI)
    a.et("no_min")
    # máximo: si MX < R
    a("lda", "zp,x", MXLO); a("cmp", "zp,x", RLO); a("lda", "zp,x", MXHI); a("sbc", "zp,x", RHI)
    a("bcs", "rel", "no_max")
    a("lda", "zp,x", RLO); a("sta", "zp,x", MXLO); a("lda", "zp,x", RHI); a("sta", "zp,x", MXHI)
    a.et("no_max")
    a("inc", "zp", T); a("lda", "zp", T); a("cmp", "#", len(RECARGAS)); a("bne", "rel", "medidas")
    # texto (desenrollado): por fila, recarga, último, mínimo, máximo
    for t, r in enumerate(RECARGAS):
        base = t * COLS
        for k, (fuente_hi, fuente_lo) in enumerate((("#", "#"), (RHI + t, RLO + t), (MNHI + t, MNLO + t),
                                                    (MXHI + t, MXLO + t))):
            a("ldy", "#", base + k * 5)
            if k == 0:
                a("lda", "#", r >> 8); a("jsr", "abs", "hex"); a("lda", "#", r & 0xFF); a("jsr", "abs", "hex")
            else:
                a("lda", "zp", fuente_hi); a("jsr", "abs", "hex"); a("lda", "zp", fuente_lo); a("jsr", "abs", "hex")
    # esperar una NMI nueva (borrar antes el aviso de vblank para no entrar a mitad de uno)
    a("lda", "#", 0); a("sta", "zp", NMIF)
    a("bit", "abs", 0x2002)
    a("lda", "#", 0x80); a("sta", "abs", 0x2000)
    a.et("espera"); a("lda", "zp", NMIF); a("beq", "rel", "espera")
    a("lda", "#", 0); a("sta", "abs", 0x2000)
    a("jmp", "abs", "principal")

    # ---------------- una medida: X = índice de la recarga. Vuelve (RTS) desde la IRQ con TX/TY = vueltas
    a.et("medir")
    a("lda", "abs,x", "REC_HI"); a("sta", "abs", 0x9005)
    a("lda", "abs,x", "REC_LO"); a("sta", "abs", 0x9006)
    a("lda", "#", 0x80); a("sta", "abs", 0x9003); a("sta", "abs", 0x9004)
    a("ldx", "#", 0); a("ldy", "#", 0)
    a("cli")
    a.et("vuelta"); a("inx"); a("bne", "rel", "vuelta")
    a("iny"); a("jmp", "abs", "vuelta")
    a.et("irq")
    a("stx", "zp", TX); a("sty", "zp", TY)
    a("lda", "#", 0); a("sta", "abs", 0x9003)          # reconoce y apaga
    a("pla"); a("pla"); a("pla")                         # P y dirección de vuelta: se sale de medir con su RTS
    a("rts")

    # ---------------- A -> dos dígitos en BUF+Y, BUF+Y+1
    a.et("hex")
    a("pha"); a("lsr"); a("lsr"); a("lsr"); a("lsr"); a("sta", "abs,y", BUF); a("iny")
    a("pla"); a("and", "#", 0x0F); a("sta", "abs,y", BUF); a("iny")
    a("rts")

    # ---------------- NMI: copia las filas, enciende el fondo, lee el mando
    a.et("nmi")
    a("pha"); a("txa"); a("pha"); a("tya"); a("pha")
    a("lda", "abs", 0x2002)
    a("ldx", "#", 0)
    for t in range(len(RECARGAS)):
        d = 0x2000 + (FILA0 + 2 * t) * 32 + COL0
        a("lda", "#", d >> 8); a("sta", "abs", 0x2006); a("lda", "#", d & 0xFF); a("sta", "abs", 0x2006)
        a.et(f"fila{t}"); a("lda", "abs,x", BUF); a("sta", "abs", 0x2007); a("inx"); a("cpx", "#", (t + 1) * COLS)
        a("bne", "rel", f"fila{t}")
    a("lda", "#", 0); a("sta", "abs", 0x2005); a("sta", "abs", 0x2005)
    a("lda", "#", 0x0A); a("sta", "abs", 0x2001)
    a("lda", "#", 1); a("sta", "abs", 0x4016); a("lda", "#", 0); a("sta", "abs", 0x4016)
    a("ldx", "#", 8)
    a.et("lee"); a("lda", "abs", 0x4016); a("lsr"); a("ror", "zp", LEC); a("dex"); a("bne", "rel", "lee")
    a("lda", "zp", LEC); a("sta", "zp", BOT)
    a("lda", "#", 1); a("sta", "zp", NMIF)
    a("pla"); a("tay"); a("pla"); a("tax"); a("pla")
    a("rti")

    a.datos("PALETA", bytes([0x0F, 0x30, 0x10, 0x00] * 4 + [0x0F] * 16))
    a.datos("REC_HI", bytes(r >> 8 for r in RECARGAS))
    a.datos("REC_LO", bytes(r & 0xFF for r in RECARGAS))
    return a


def rom():
    a = programa()
    codigo = a.resolver()
    assert len(codigo) < 0x1FFA, len(codigo)
    banco = bytearray(codigo.ljust(0x2000, b"\xff"))
    for i, nombre in enumerate(("nmi", "reset", "irq")):
        d = a.etq[nombre]
        banco[0x1FFA + 2 * i:0x1FFC + 2 * i] = bytes([d & 0xFF, d >> 8])
    prg = bytes(0x2000) * 3 + bytes(banco)                  # 32 KB: el código en el último banco de 8 KB
    cabecera = b"NES\x1a" + bytes([2, 1, 0x10, 0x40]) + bytes(8)   # mapper 65
    return cabecera + prg + chr_rom()


if __name__ == "__main__":
    out = AQUI / "irq65.nes"
    out.write_bytes(rom())
    print(f"{out}: {out.stat().st_size} bytes")
