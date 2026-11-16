"""cpu6502.py — CPU 6502 (NMOS, sin modo decimal, como la 2A03 del NES), solo opcodes oficiales.

Sin dependencias. La memoria la dan dos funciones: rd(addr) y wr(addr, val). `paso()` ejecuta una instrucción y
devuelve False ante un opcode no oficial (queda en `ilegal`). No cuenta ciclos reales: `ciclos` es orientativo.

Código propio (GPL-3.0-or-later), parte de tools/bios: banco para estudiar la BIOS del N8 clon y probar un OS.
"""


class CPU:
    def __init__(self, rd, wr):
        self.rd, self.wr = rd, wr
        self.a = self.x = self.y = 0
        self.s = 0xFD
        self.pc = 0
        self.c = self.z = self.i = self.d = self.v = self.n = 0
        self.ciclos = 0
        self.ilegal = None
        self._tabla()

    # ---------------------------------------------------------------- flags
    def p(self, b=0):
        return (self.n << 7) | (self.v << 6) | 0x20 | (b << 4) | (self.d << 3) | (self.i << 2) | (self.z << 1) | self.c

    def setp(self, v):
        self.n, self.v, self.d, self.i, self.z, self.c = (v >> 7) & 1, (v >> 6) & 1, (v >> 3) & 1, (v >> 2) & 1, (v >> 1) & 1, v & 1

    def nz(self, v):
        self.n = (v >> 7) & 1
        self.z = 1 if v == 0 else 0
        return v

    def push(self, v):
        self.wr(0x100 | self.s, v)
        self.s = (self.s - 1) & 0xFF

    def pull(self):
        self.s = (self.s + 1) & 0xFF
        return self.rd(0x100 | self.s)

    def rd16(self, a):
        return self.rd(a) | (self.rd((a + 1) & 0xFFFF) << 8)

    def reset(self):
        self.pc = self.rd16(0xFFFC)
        self.i = 1

    # ---------------------------------------------------------------- modos (devuelven dirección)
    def imm(self):
        a = self.pc; self.pc = (self.pc + 1) & 0xFFFF; return a

    def zp(self):
        a = self.rd(self.pc); self.pc = (self.pc + 1) & 0xFFFF; return a

    def zpx(self):
        a = (self.rd(self.pc) + self.x) & 0xFF; self.pc = (self.pc + 1) & 0xFFFF; return a

    def zpy(self):
        a = (self.rd(self.pc) + self.y) & 0xFF; self.pc = (self.pc + 1) & 0xFFFF; return a

    def ab(self):
        a = self.rd16(self.pc); self.pc = (self.pc + 2) & 0xFFFF; return a

    def abx(self):
        a = (self.rd16(self.pc) + self.x) & 0xFFFF; self.pc = (self.pc + 2) & 0xFFFF; return a

    def aby(self):
        a = (self.rd16(self.pc) + self.y) & 0xFFFF; self.pc = (self.pc + 2) & 0xFFFF; return a

    def izx(self):
        z = (self.rd(self.pc) + self.x) & 0xFF; self.pc = (self.pc + 1) & 0xFFFF
        return self.rd(z) | (self.rd((z + 1) & 0xFF) << 8)

    def izy(self):
        z = self.rd(self.pc); self.pc = (self.pc + 1) & 0xFFFF
        return ((self.rd(z) | (self.rd((z + 1) & 0xFF) << 8)) + self.y) & 0xFFFF

    # ---------------------------------------------------------------- operaciones
    def _adc(self, m):
        r = self.a + m + self.c
        self.v = 1 if (~(self.a ^ m) & (self.a ^ r) & 0x80) else 0
        self.c = 1 if r > 0xFF else 0
        self.a = self.nz(r & 0xFF)

    def _cmp(self, r, m):
        t = (r - m) & 0x1FF
        self.c = 1 if r >= m else 0
        self.nz(t & 0xFF)

    def _tabla(self):
        T = [None] * 256
        modos = {'imm': self.imm, 'zp': self.zp, 'zpx': self.zpx, 'zpy': self.zpy, 'ab': self.ab,
                 'abx': self.abx, 'aby': self.aby, 'izx': self.izx, 'izy': self.izy}

        def lectura(op, f):
            for codigo, m in op:
                mm = modos[m]
                T[codigo] = (lambda mm=mm: f(self.rd(mm())))

        def escritura(op, f):
            for codigo, m in op:
                mm = modos[m]
                T[codigo] = (lambda mm=mm: self.wr(mm(), f()))

        def rmw(op, f, acc=None):
            for codigo, m in op:
                mm = modos[m]

                def g(mm=mm):
                    a = mm(); v = self.rd(a); self.wr(a, v); self.wr(a, f(v))
                T[codigo] = g
            if acc is not None:
                def h():
                    self.a = f(self.a)
                T[acc] = h

        def lda(v): self.a = self.nz(v)
        def ldx(v): self.x = self.nz(v)
        def ldy(v): self.y = self.nz(v)
        def ora(v): self.a = self.nz(self.a | v)
        def and_(v): self.a = self.nz(self.a & v)
        def eor(v): self.a = self.nz(self.a ^ v)
        def adc(v): self._adc(v)
        def sbc(v): self._adc(v ^ 0xFF)
        def cmp_(v): self._cmp(self.a, v)
        def cpx(v): self._cmp(self.x, v)
        def cpy(v): self._cmp(self.y, v)

        def bit(v):
            self.z = 1 if (self.a & v) == 0 else 0
            self.n, self.v = (v >> 7) & 1, (v >> 6) & 1

        std = [('izx', 0x01), ('zp', 0x05), ('imm', 0x09), ('ab', 0x0D), ('izy', 0x11), ('zpx', 0x15), ('aby', 0x19), ('abx', 0x1D)]
        for base, f in ((0x00, ora), (0x20, and_), (0x40, eor), (0x60, adc), (0xC0, cmp_), (0xE0, sbc), (0xA0, lda)):
            lectura([(base | (o & 0x1F), m) for m, o in std], f)
        escritura([(0x81, 'izx'), (0x85, 'zp'), (0x8D, 'ab'), (0x91, 'izy'), (0x95, 'zpx'), (0x99, 'aby'), (0x9D, 'abx')], lambda: self.a)
        lectura([(0xA2, 'imm'), (0xA6, 'zp'), (0xAE, 'ab'), (0xB6, 'zpy'), (0xBE, 'aby')], ldx)
        lectura([(0xA0, 'imm'), (0xA4, 'zp'), (0xAC, 'ab'), (0xB4, 'zpx'), (0xBC, 'abx')], ldy)
        escritura([(0x86, 'zp'), (0x8E, 'ab'), (0x96, 'zpy')], lambda: self.x)
        escritura([(0x84, 'zp'), (0x8C, 'ab'), (0x94, 'zpx')], lambda: self.y)
        lectura([(0xE0, 'imm'), (0xE4, 'zp'), (0xEC, 'ab')], cpx)
        lectura([(0xC0, 'imm'), (0xC4, 'zp'), (0xCC, 'ab')], cpy)
        lectura([(0x24, 'zp'), (0x2C, 'ab')], bit)

        def asl(v): self.c = v >> 7; return self.nz((v << 1) & 0xFF)
        def lsr(v): self.c = v & 1; return self.nz(v >> 1)
        def rol(v): r = ((v << 1) | self.c) & 0xFF; self.c = v >> 7; return self.nz(r)
        def ror(v): r = (v >> 1) | (self.c << 7); self.c = v & 1; return self.nz(r)
        def inc(v): return self.nz((v + 1) & 0xFF)
        def dec(v): return self.nz((v - 1) & 0xFF)
        sh = [('zp', 0x06), ('ab', 0x0E), ('zpx', 0x16), ('abx', 0x1E)]
        for base, f, acc in ((0x00, asl, 0x0A), (0x40, lsr, 0x4A), (0x20, rol, 0x2A), (0x60, ror, 0x6A)):
            rmw([(base | o, m) for m, o in sh], f, acc)
        rmw([(0xE6, 'zp'), (0xEE, 'ab'), (0xF6, 'zpx'), (0xFE, 'abx')], inc)
        rmw([(0xC6, 'zp'), (0xCE, 'ab'), (0xD6, 'zpx'), (0xDE, 'abx')], dec)

        def br(cond):
            def g():
                o = self.rd(self.pc); self.pc = (self.pc + 1) & 0xFFFF
                if cond():
                    self.pc = (self.pc + (o - 256 if o > 127 else o)) & 0xFFFF
            return g
        T[0x10] = br(lambda: not self.n); T[0x30] = br(lambda: self.n)
        T[0x50] = br(lambda: not self.v); T[0x70] = br(lambda: self.v)
        T[0x90] = br(lambda: not self.c); T[0xB0] = br(lambda: self.c)
        T[0xD0] = br(lambda: not self.z); T[0xF0] = br(lambda: self.z)

        def jmp(): self.pc = self.rd16(self.pc)

        def jmpi():
            a = self.rd16(self.pc)
            self.pc = self.rd(a) | (self.rd((a & 0xFF00) | ((a + 1) & 0xFF)) << 8)

        def jsr():
            t = self.rd16(self.pc); r = (self.pc + 1) & 0xFFFF
            self.push(r >> 8); self.push(r & 0xFF); self.pc = t

        def rts():
            lo = self.pull(); hi = self.pull(); self.pc = ((hi << 8) | lo) + 1 & 0xFFFF

        def rti():
            self.setp(self.pull()); lo = self.pull(); hi = self.pull(); self.pc = (hi << 8) | lo

        def brk():
            r = (self.pc + 1) & 0xFFFF
            self.push(r >> 8); self.push(r & 0xFF); self.push(self.p(1)); self.i = 1
            self.pc = self.rd16(0xFFFE)
        T[0x4C] = jmp; T[0x6C] = jmpi; T[0x20] = jsr; T[0x60] = rts; T[0x40] = rti; T[0x00] = brk

        def s(attr, val):
            def g(): setattr(self, attr, val)
            return g
        T[0x18] = s('c', 0); T[0x38] = s('c', 1); T[0x58] = s('i', 0); T[0x78] = s('i', 1)
        T[0xB8] = s('v', 0); T[0xD8] = s('d', 0); T[0xF8] = s('d', 1)

        def t(src, dst, flags=True):
            def g():
                v = getattr(self, src)
                setattr(self, dst, self.nz(v) if flags else v)
            return g
        T[0xAA] = t('a', 'x'); T[0xA8] = t('a', 'y'); T[0x8A] = t('x', 'a'); T[0x98] = t('y', 'a')
        T[0xBA] = t('s', 'x'); T[0x9A] = t('x', 's', False)

        def ix(r, d):
            def g(): setattr(self, r, self.nz((getattr(self, r) + d) & 0xFF))
            return g
        T[0xE8] = ix('x', 1); T[0xCA] = ix('x', -1); T[0xC8] = ix('y', 1); T[0x88] = ix('y', -1)
        T[0x48] = lambda: self.push(self.a)
        T[0x08] = lambda: self.push(self.p(1))

        def pla(): self.a = self.nz(self.pull())
        T[0x68] = pla
        T[0x28] = lambda: self.setp(self.pull())
        T[0xEA] = lambda: None
        self.T = T

    def paso(self):
        op = self.rd(self.pc)
        self.pc = (self.pc + 1) & 0xFFFF
        f = self.T[op]
        if f is None:
            self.ilegal = (self.pc - 1) & 0xFFFF, op
            return False
        f()
        self.ciclos += 3
        return True

    def nmi(self):
        self.push(self.pc >> 8); self.push(self.pc & 0xFF); self.push(self.p(0)); self.i = 1
        self.pc = self.rd16(0xFFFA)
