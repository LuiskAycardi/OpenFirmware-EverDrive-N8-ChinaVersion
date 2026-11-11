"""asm6502.py — Miniensamblador 6502 para las ROMs de prueba del banco (sin cc65).

Uso:
    a = Asm(origin=0x0200)
    a.label("bucle"); a.lda_imm(0); a.sta_abs(0x2000); a.bne("bucle")
    data = a.assemble()          # bytes con las etiquetas resueltas

Solo los modos que usan las ROMs de prueba. Las ramas se comprueban (±127).
"""


class Asm:
    def __init__(self, origin):
        self.origin = origin
        self.code = []          # bytes o ("rel", etiqueta, pc) / ("abs", etiqueta, parte)
        self.labels = {}

    # ------------------------------------------------------------ utilidades
    @property
    def pc(self):
        return self.origin + len(self.code)

    def label(self, name):
        if name in self.labels:
            raise ValueError(f"etiqueta repetida: {name}")
        self.labels[name] = self.pc

    def byte(self, *bs):
        for b in bs:
            self.code.append(b & 0xFF)

    def word_ref(self, target):
        """Dirección de 16 bits: número o etiqueta."""
        if isinstance(target, str):
            self.code.append(("lo", target))
            self.code.append(("hi", target))
        else:
            self.code.append(target & 0xFF)
            self.code.append((target >> 8) & 0xFF)

    def _op_abs(self, opcode, target):
        self.code.append(opcode)
        self.word_ref(target)

    def _op_zp(self, opcode, zp):
        assert 0 <= zp <= 0xFF
        self.byte(opcode, zp)

    def _op_imm(self, opcode, value):
        if isinstance(value, tuple):            # ("lo"/"hi", etiqueta)
            self.code.append(opcode)
            self.code.append(value)
        else:
            self.byte(opcode, value)

    def _branch(self, opcode, target):
        self.code.append(opcode)
        self.code.append(("rel", target, self.pc + 1))

    def assemble(self):
        out = bytearray()
        for item in self.code:
            if isinstance(item, int):
                out.append(item)
                continue
            kind = item[0]
            if kind == "rel":
                dest = self.labels[item[1]]
                off = dest - (item[2])
                if not -128 <= off <= 127:
                    raise ValueError(f"rama fuera de alcance hacia {item[1]}: {off}")
                out.append(off & 0xFF)
            elif kind in ("lo", "hi"):
                v = self.labels[item[1]]
                out.append(v & 0xFF if kind == "lo" else (v >> 8) & 0xFF)
            else:
                raise ValueError(item)
        return bytes(out)

    # ------------------------------------------------------------ instrucciones
    def lda_imm(self, v): self._op_imm(0xA9, v)
    def ldx_imm(self, v): self._op_imm(0xA2, v)
    def ldy_imm(self, v): self._op_imm(0xA0, v)
    def cmp_imm(self, v): self._op_imm(0xC9, v)
    def cpx_imm(self, v): self._op_imm(0xE0, v)
    def cpy_imm(self, v): self._op_imm(0xC0, v)
    def and_imm(self, v): self._op_imm(0x29, v)
    def ora_imm(self, v): self._op_imm(0x09, v)
    def eor_imm(self, v): self._op_imm(0x49, v)
    def adc_imm(self, v): self._op_imm(0x69, v)

    def lda_abs(self, a): self._op_abs(0xAD, a)
    def sta_abs(self, a): self._op_abs(0x8D, a)
    def ldx_abs(self, a): self._op_abs(0xAE, a)
    def stx_abs(self, a): self._op_abs(0x8E, a)
    def sty_abs(self, a): self._op_abs(0x8C, a)
    def bit_abs(self, a): self._op_abs(0x2C, a)
    def inc_abs(self, a): self._op_abs(0xEE, a)
    def lda_absx(self, a): self._op_abs(0xBD, a)
    def sta_absx(self, a): self._op_abs(0x9D, a)
    def lda_absy(self, a): self._op_abs(0xB9, a)
    def sta_absy(self, a): self._op_abs(0x99, a)
    def jmp(self, a): self._op_abs(0x4C, a)
    def jsr(self, a): self._op_abs(0x20, a)

    def lda_zp(self, z): self._op_zp(0xA5, z)
    def sta_zp(self, z): self._op_zp(0x85, z)
    def ldx_zp(self, z): self._op_zp(0xA6, z)
    def stx_zp(self, z): self._op_zp(0x86, z)
    def ldy_zp(self, z): self._op_zp(0xA4, z)
    def sty_zp(self, z): self._op_zp(0x84, z)
    def inc_zp(self, z): self._op_zp(0xE6, z)
    def dec_zp(self, z): self._op_zp(0xC6, z)
    def lsr_zp(self, z): self._op_zp(0x46, z)
    def ror_zp(self, z): self._op_zp(0x66, z)
    def eor_zp(self, z): self._op_zp(0x45, z)
    def and_zp(self, z): self._op_zp(0x25, z)
    def ora_zp(self, z): self._op_zp(0x05, z)
    def adc_zp(self, z): self._op_zp(0x65, z)
    def cmp_zp(self, z): self._op_zp(0xC5, z)
    def lda_indy(self, z): self._op_zp(0xB1, z)
    def sta_indy(self, z): self._op_zp(0x91, z)

    def bne(self, t): self._branch(0xD0, t)
    def beq(self, t): self._branch(0xF0, t)
    def bcc(self, t): self._branch(0x90, t)
    def bcs(self, t): self._branch(0xB0, t)
    def bpl(self, t): self._branch(0x10, t)
    def bmi(self, t): self._branch(0x30, t)

    def rts(self): self.byte(0x60)
    def rti(self): self.byte(0x40)
    def sei(self): self.byte(0x78)
    def cli(self): self.byte(0x58)
    def tsx(self): self.byte(0xBA)
    def cld(self): self.byte(0xD8)
    def clc(self): self.byte(0x18)
    def sec(self): self.byte(0x38)
    def inx(self): self.byte(0xE8)
    def iny(self): self.byte(0xC8)
    def dex(self): self.byte(0xCA)
    def dey(self): self.byte(0x88)
    def tax(self): self.byte(0xAA)
    def txa(self): self.byte(0x8A)
    def tay(self): self.byte(0xA8)
    def tya(self): self.byte(0x98)
    def txs(self): self.byte(0x9A)
    def pha(self): self.byte(0x48)
    def pla(self): self.byte(0x68)
    def asl_a(self): self.byte(0x0A)
    def lsr_a(self): self.byte(0x4A)
    def rol_a(self): self.byte(0x2A)
    def nop(self): self.byte(0xEA)
