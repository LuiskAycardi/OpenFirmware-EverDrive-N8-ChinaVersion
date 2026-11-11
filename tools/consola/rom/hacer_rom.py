#!/usr/bin/env python3
"""hacer_rom.py — genera rom/calibracion.nes: la ROM de calibración del banco de consola (NROM, mapper 0).

Qué hace la ROM:
  - Dibuja un marco de 1 píxel justo en los bordes de la imagen de 256x240, dos "códigos de barras" (uno
    horizontal y dos verticales) para que la calibración encuentre la escala y el desplazamiento sin ambigüedad,
    y 12 parches de color (4 paletas x 3 colores).
  - Lee el mando 1 una vez por fotograma (en la NMI) y muestra los 8 botones: cuadrado blanco lleno = pulsado,
    solo el contorno = suelto. Orden de izquierda a derecha: A B Select Start Arriba Abajo Izquierda Derecha.
  - Muestra un contador de fotogramas de 12 bits (rojo = 1), el bit más alto a la izquierda.
Con ella prueba.py calibra la imagen, comprueba que el Nano llega a la consola botón a botón y mide el retraso
de la cadena de vídeo (GBS-Control + capturadora).

El código 6502 se ensambla aquí mismo (no hace falta cc65). imagen_esperada() da la imagen que debe verse.
  python3 -I rom/hacer_rom.py            -> rom/calibracion.nes
"""
import pathlib

AQUI = pathlib.Path(__file__).resolve().parent

# Paleta NES de referencia (2C02, la de la wiki de NESdev). Solo se usa para la imagen esperada: la calibración
# compara estructura (luminancia y clases de color), no colores exactos.
PALETA_NES = [
    (84, 84, 84), (0, 30, 116), (8, 16, 144), (48, 0, 136), (68, 0, 100), (92, 0, 48), (84, 4, 0), (60, 24, 0),
    (32, 42, 0), (8, 58, 0), (0, 64, 0), (0, 60, 0), (0, 50, 60), (0, 0, 0), (0, 0, 0), (0, 0, 0),
    (152, 150, 152), (8, 76, 196), (48, 50, 236), (92, 30, 228), (136, 20, 176), (160, 20, 100), (152, 34, 32),
    (120, 60, 0), (84, 90, 0), (40, 114, 0), (8, 124, 0), (0, 118, 40), (0, 102, 120), (0, 0, 0), (0, 0, 0),
    (0, 0, 0),
    (236, 238, 236), (76, 154, 236), (120, 124, 236), (176, 98, 236), (228, 84, 236), (236, 88, 180),
    (236, 106, 100), (212, 136, 32), (160, 170, 0), (116, 196, 0), (76, 208, 32), (56, 204, 108), (56, 180, 204),
    (60, 60, 60), (0, 0, 0), (0, 0, 0),
    (236, 238, 236), (168, 204, 236), (188, 188, 236), (212, 178, 236), (236, 174, 236), (236, 174, 212),
    (236, 180, 176), (228, 196, 144), (204, 210, 120), (180, 222, 120), (168, 226, 144), (152, 226, 180),
    (160, 214, 228), (160, 162, 160), (0, 0, 0), (0, 0, 0),
]

PALETAS_FONDO = [[0x0F, 0x30, 0x16, 0x2A], [0x0F, 0x12, 0x28, 0x10], [0x0F, 0x14, 0x27, 0x3C],
                 [0x0F, 0x00, 0x1A, 0x21]]

# Teselas (patrón 0): 0 vacía, 1-3 llenas de color 1-3, 4-7 bordes (arriba, abajo, izquierda, derecha),
# 8-11 esquinas (sup-izq, sup-der, inf-izq, inf-der), 12 contorno.
T_VACIA, T_LLENA1, T_LLENA2, T_LLENA3 = 0, 1, 2, 3
T_ARR, T_ABA, T_IZQ, T_DER, T_SI, T_SD, T_II, T_ID, T_CONTORNO = 4, 5, 6, 7, 8, 9, 10, 11, 12

FILA_BOTONES, FILA_CONTADOR, COL0 = 12, 17, 4       # filas de teselas; columnas 4..27
BITS_CONTADOR = 12
BARRAS = "1101001110001011011000010111"           # 28 columnas, sin periodo (para la correlación)


def tesela(pixeles):
    """8x8 de colores 0-3 -> 16 bytes (dos planos)."""
    p0 = bytes(sum(((pixeles[y][x] & 1) << (7 - x)) for x in range(8)) for y in range(8))
    p1 = bytes(sum(((pixeles[y][x] >> 1 & 1) << (7 - x)) for x in range(8)) for y in range(8))
    return p0 + p1


def teselas():
    def llena(c):
        return [[c] * 8 for _ in range(8)]

    def con(f):
        return [[1 if f(x, y) else 0 for x in range(8)] for y in range(8)]

    t = [llena(0), llena(1), llena(2), llena(3),
         con(lambda x, y: y == 0), con(lambda x, y: y == 7), con(lambda x, y: x == 0), con(lambda x, y: x == 7),
         con(lambda x, y: y == 0 or x == 0), con(lambda x, y: y == 0 or x == 7),
         con(lambda x, y: y == 7 or x == 0), con(lambda x, y: y == 7 or x == 7),
         con(lambda x, y: x in (0, 7) or y in (0, 7))]
    return t


def nametable():
    """(teselas 32x30, atributos 8x8 -> paleta por bloque de 16x16)"""
    nt = [[T_VACIA] * 32 for _ in range(30)]
    pal = [[0] * 16 for _ in range(15)]                 # paleta de cada bloque de 2x2 teselas
    for x in range(32):
        nt[0][x], nt[29][x] = T_ARR, T_ABA
    for y in range(30):
        nt[y][0], nt[y][31] = T_IZQ, T_DER
    nt[0][0], nt[0][31], nt[29][0], nt[29][31] = T_SI, T_SD, T_II, T_ID
    for i, b in enumerate(BARRAS):                       # código de barras horizontal (filas 3-4)
        if b == "1":
            nt[3][2 + i] = nt[4][2 + i] = T_LLENA1
    for i, b in enumerate(BARRAS[:22]):                  # verticales (columnas 2 y 29, filas 6-27)
        if b == "1":
            nt[6 + i][2] = nt[6 + i][29] = T_LLENA1
    for k in range(12):                                  # parches: paleta k // 3, color k % 3 + 1
        y, x = 24, 4 + 2 * k
        for dy in (0, 1):
            for dx in (0, 1):
                nt[y + dy][x + dx] = T_LLENA1 + k % 3
        pal[y // 2][x // 2] = k // 3
    for i in range(8):                                   # botones sueltos
        for dy in (0, 1):
            nt[FILA_BOTONES + dy][COL0 + 3 * i] = nt[FILA_BOTONES + dy][COL0 + 3 * i + 1] = T_CONTORNO
    for j in range(BITS_CONTADOR):
        for dy in (0, 1):
            nt[FILA_CONTADOR + dy][COL0 + 2 * j] = T_CONTORNO
    return nt, pal


def bytes_nametable():
    nt, pal = nametable()
    out = bytearray(t for fila in nt for t in fila)
    for ay in range(8):
        for ax in range(8):
            v = 0
            for q, (dy, dx) in enumerate(((0, 0), (0, 1), (1, 0), (1, 1))):
                by, bx = ay * 2 + dy, ax * 2 + dx
                p = pal[by][bx] if by < 15 else 0
                v |= p << (2 * q)
            out.append(v)
    return bytes(out)


# ---------------------------------------------------------------- ensamblador mínimo de 6502
OPS = {
    ("sei", None): 0x78, ("cld", None): 0xD8, ("txs", None): 0x9A, ("inx", None): 0xE8, ("iny", None): 0xC8,
    ("dex", None): 0xCA, ("rts", None): 0x60, ("rti", None): 0x40, ("pha", None): 0x48, ("pla", None): 0x68,
    ("txa", None): 0x8A, ("tax", None): 0xAA, ("tya", None): 0x98, ("tay", None): 0xA8, ("lsr", None): 0x4A,
    ("lda", "#"): 0xA9, ("lda", "zp"): 0xA5, ("lda", "abs"): 0xAD, ("lda", "abs,x"): 0xBD,
    ("sta", "zp"): 0x85, ("sta", "abs"): 0x8D, ("sta", "abs,x"): 0x9D,
    ("ldx", "#"): 0xA2, ("ldy", "#"): 0xA0, ("stx", "abs"): 0x8E,
    ("cpx", "#"): 0xE0, ("cpy", "#"): 0xC0, ("and", "#"): 0x29,
    ("bit", "abs"): 0x2C, ("jmp", "abs"): 0x4C, ("jsr", "abs"): 0x20,
    ("lsr", "zp"): 0x46, ("ror", "zp"): 0x66, ("rol", "zp"): 0x26, ("asl", "zp"): 0x06, ("inc", "zp"): 0xE6,
    ("bpl", "rel"): 0x10, ("bne", "rel"): 0xD0, ("beq", "rel"): 0xF0, ("bcc", "rel"): 0x90,
}
TAM = {None: 1, "#": 2, "zp": 2, "abs": 3, "abs,x": 3, "rel": 2}


class Asm:
    def __init__(self, origen):
        self.org, self.b, self.etq, self.arreglos = origen, bytearray(), {}, []

    @property
    def pc(self):
        return self.org + len(self.b)

    def __call__(self, nombre, modo=None, arg=None):
        op = OPS[(nombre, modo)]
        self.b.append(op)
        if modo is None:
            return
        if modo == "rel":
            self.arreglos.append(("rel", len(self.b), arg))
            self.b.append(0)
        elif TAM[modo] == 2:
            self.b.append(arg & 0xFF)
        elif isinstance(arg, str):
            self.arreglos.append(("abs", len(self.b), arg))
            self.b += b"\0\0"
        else:
            self.b += bytes([arg & 0xFF, arg >> 8])

    def et(self, nombre):
        self.etq[nombre] = self.pc

    def datos(self, nombre, d):
        self.et(nombre)
        self.b += d

    def resolver(self):
        for tipo, pos, nombre in self.arreglos:
            destino = self.etq[nombre]
            if tipo == "abs":
                self.b[pos:pos + 2] = bytes([destino & 0xFF, destino >> 8])
            else:
                d = destino - (self.org + pos + 1)
                assert -128 <= d <= 127, f"salto largo a {nombre}"
                self.b[pos] = d & 0xFF
        return bytes(self.b)


ZP_NMI, ZP_BOT, ZP_CNT, ZP_TMP, ZP_TMP2, ZP_LEC = 0x00, 0x01, 0x02, 0x04, 0x05, 0x06
BUF = 0x0300


def programa():
    a = Asm(0xC000)
    # ---------------- RESET
    a.et("reset")
    a("sei"); a("cld")
    a("ldx", "#", 0x40); a("stx", "abs", 0x4017)
    a("ldx", "#", 0xFF); a("txs"); a("inx")
    a("stx", "abs", 0x2000); a("stx", "abs", 0x2001); a("stx", "abs", 0x4010)
    a("bit", "abs", 0x2002)
    a.et("vb1"); a("bit", "abs", 0x2002); a("bpl", "rel", "vb1")
    a("lda", "#", 0)
    a.et("borra")
    for pagina in range(0, 0x800, 0x100):
        a("sta", "abs,x", pagina)
    a("inx"); a("bne", "rel", "borra")
    a.et("vb2"); a("bit", "abs", 0x2002); a("bpl", "rel", "vb2")
    # paleta
    a("lda", "#", 0x3F); a("sta", "abs", 0x2006); a("lda", "#", 0x00); a("sta", "abs", 0x2006)
    a("ldx", "#", 0)
    a.et("pal"); a("lda", "abs,x", "PALETA"); a("sta", "abs", 0x2007); a("inx"); a("cpx", "#", 32)
    a("bne", "rel", "pal")
    # nametable 0 (960 teselas + 64 atributos)
    a("lda", "#", 0x20); a("sta", "abs", 0x2006); a("lda", "#", 0x00); a("sta", "abs", 0x2006)
    a("ldx", "#", 0)
    for k in range(4):
        a.et(f"nt{k}"); a("lda", "abs,x", f"NT{k}"); a("sta", "abs", 0x2007); a("inx"); a("bne", "rel", f"nt{k}")
    a("jsr", "abs", "prepara")
    a("lda", "#", 0); a("sta", "abs", 0x2005); a("sta", "abs", 0x2005)
    a("lda", "#", 0x80); a("sta", "abs", 0x2000)
    a("lda", "#", 0x0A); a("sta", "abs", 0x2001)
    a.et("bucle")
    a("lda", "zp", ZP_NMI); a("beq", "rel", "bucle")
    a("lda", "#", 0); a("sta", "zp", ZP_NMI)
    a("jsr", "abs", "prepara")
    a("jmp", "abs", "bucle")

    # ---------------- prepara el búfer de 4 filas x 24 teselas (botones y contador)
    a.et("prepara")
    a("lda", "zp", ZP_BOT); a("sta", "zp", ZP_TMP)
    a("ldx", "#", 0); a("ldy", "#", 0)
    a.et("pb")
    a("lsr", "zp", ZP_TMP)
    a("lda", "#", T_CONTORNO); a("bcc", "rel", "pb_suelto"); a("lda", "#", T_LLENA1)
    a.et("pb_suelto")
    for off in (0, 1, 24, 25):
        a("sta", "abs,x", BUF + off)
    a("lda", "#", 0); a("sta", "abs,x", BUF + 2); a("sta", "abs,x", BUF + 26)
    a("inx"); a("inx"); a("inx"); a("iny"); a("cpy", "#", 8); a("bne", "rel", "pb")
    # contador de 12 bits: bits 11..8 de ZP_CNT+1 y 7..0 de ZP_CNT; se desplaza para leer el más alto primero
    a("lda", "zp", ZP_CNT + 1); a("and", "#", 0x0F); a("sta", "zp", ZP_TMP)
    a("lda", "zp", ZP_CNT); a("sta", "zp", ZP_TMP2)
    for _ in range(4):
        a("asl", "zp", ZP_TMP2); a("rol", "zp", ZP_TMP)
    a("ldx", "#", 0); a("ldy", "#", 0)
    a.et("pc_")
    a("asl", "zp", ZP_TMP2); a("rol", "zp", ZP_TMP)
    a("lda", "#", T_CONTORNO); a("bcc", "rel", "pc_cero"); a("lda", "#", T_LLENA2)
    a.et("pc_cero")
    a("sta", "abs,x", BUF + 48); a("sta", "abs,x", BUF + 72)
    a("lda", "#", 0); a("sta", "abs,x", BUF + 49); a("sta", "abs,x", BUF + 73)
    a("inx"); a("inx"); a("iny"); a("cpy", "#", BITS_CONTADOR); a("bne", "rel", "pc_")
    a("rts")

    # ---------------- NMI: copia el búfer, lee el mando, cuenta
    a.et("nmi")
    a("pha"); a("txa"); a("pha"); a("tya"); a("pha")
    a("lda", "abs", 0x2002)
    filas = [(FILA_BOTONES, 0), (FILA_BOTONES + 1, 24), (FILA_CONTADOR, 48), (FILA_CONTADOR + 1, 72)]
    a("ldx", "#", 0)
    for k, (fila, ini) in enumerate(filas):
        dirppu = 0x2000 + fila * 32 + COL0
        a("lda", "#", dirppu >> 8); a("sta", "abs", 0x2006); a("lda", "#", dirppu & 0xFF); a("sta", "abs", 0x2006)
        a.et(f"cp{k}"); a("lda", "abs,x", BUF); a("sta", "abs", 0x2007); a("inx"); a("cpx", "#", ini + 24)
        a("bne", "rel", f"cp{k}")
    a("lda", "#", 0); a("sta", "abs", 0x2005); a("sta", "abs", 0x2005)
    a("lda", "#", 0x80); a("sta", "abs", 0x2000)
    a("lda", "#", 1); a("sta", "abs", 0x4016); a("lda", "#", 0); a("sta", "abs", 0x4016)
    a("ldx", "#", 8)
    a.et("lee"); a("lda", "abs", 0x4016); a("lsr"); a("ror", "zp", ZP_LEC); a("dex"); a("bne", "rel", "lee")
    a("lda", "zp", ZP_LEC); a("sta", "zp", ZP_BOT)
    a("inc", "zp", ZP_CNT); a("bne", "rel", "sin_acarreo"); a("inc", "zp", ZP_CNT + 1)
    a.et("sin_acarreo")
    a("lda", "#", 1); a("sta", "zp", ZP_NMI)
    a("pla"); a("tay"); a("pla"); a("tax"); a("pla")
    a("rti")
    a.et("irq"); a("rti")

    # ---------------- datos
    pal = bytes(c for p in PALETAS_FONDO for c in p) + bytes([0x0F] * 16)
    a.datos("PALETA", pal)
    nt = bytes_nametable()
    while a.pc & 0xFF:
        a.b.append(0)
    for k in range(4):
        a.datos(f"NT{k}", nt[k * 256:(k + 1) * 256])
    return a


def rom():
    a = programa()
    codigo = a.resolver()
    prg = bytearray(codigo.ljust(0x4000, b"\xff"))
    for i, nombre in enumerate(("nmi", "reset", "irq")):
        d = a.etq[nombre]
        prg[0x3FFA + 2 * i:0x3FFC + 2 * i] = bytes([d & 0xFF, d >> 8])
    chr_ = b"".join(tesela(t) for t in teselas()).ljust(0x2000, b"\0")
    cabecera = b"NES\x1a" + bytes([1, 1, 0x01, 0]) + bytes(8)
    return cabecera + bytes(prg) + chr_


def imagen_esperada(botones=0, contador=None):
    """(rgb 240x256x3 uint8, índice de color NES 240x256, máscara de zonas fijas 240x256 bool).
    Con contador=None, la zona del contador queda fuera de la máscara (cambia en cada fotograma)."""
    import numpy as np
    nt, pal = nametable()
    ts = teselas()
    for i in range(8):
        t = T_LLENA1 if botones >> i & 1 else T_CONTORNO
        for dy in (0, 1):
            nt[FILA_BOTONES + dy][COL0 + 3 * i] = nt[FILA_BOTONES + dy][COL0 + 3 * i + 1] = t
    if contador is not None:
        for j in range(BITS_CONTADOR):
            t = T_LLENA2 if contador >> (BITS_CONTADOR - 1 - j) & 1 else T_CONTORNO
            for dy in (0, 1):
                nt[FILA_CONTADOR + dy][COL0 + 2 * j] = t
    ts = np.array(ts, np.uint8)                                   # (13, 8, 8) colores 0-3
    pal_t = np.repeat(np.repeat(np.array(pal), 2, 0), 2, 1)[:30, :32]
    idx_t = np.array(PALETAS_FONDO, np.uint8)[pal_t[..., None, None], ts[np.array(nt)]]   # color 0 = $0F
    idx = idx_t.transpose(0, 2, 1, 3).reshape(240, 256)
    rgb = np.array(PALETA_NES, np.uint8)[idx]
    mascara = np.ones((240, 256), bool)
    if contador is None:
        mascara[FILA_CONTADOR * 8:(FILA_CONTADOR + 2) * 8, COL0 * 8:(COL0 + 24) * 8] = False
    return rgb, idx, mascara


def zonas_botones():
    """[(y0, y1, x0, x1)] interior de cada indicador de botón (píxeles NES), A primero."""
    y0 = FILA_BOTONES * 8
    return [(y0 + 3, y0 + 13, (COL0 + 3 * i) * 8 + 3, (COL0 + 3 * i) * 8 + 13) for i in range(8)]


def zonas_contador():
    y0 = FILA_CONTADOR * 8
    return [(y0 + 3, y0 + 13, (COL0 + 2 * j) * 8 + 2, (COL0 + 2 * j) * 8 + 6) for j in range(BITS_CONTADOR)]


if __name__ == "__main__":
    datos = rom()
    destino = AQUI / "calibracion.nes"
    destino.write_bytes(datos)
    print(f"{destino}: {len(datos)} bytes")
