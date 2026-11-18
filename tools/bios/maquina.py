"""maquina.py — Modelo del N8 clon en modo BIOS/OS para estudiar el arranque y probar un OS propio.

Componentes (todos propios, GPL-3.0-or-later; ver docs/bios-n8-clon.md):
- CPU 6502 (cpu6502.py), 2 KiB de RAM, PPU mínima (registros $2000/$2001/$2002/$2006/$2007, CHR por la ventana
  del modo OS, nametables y paleta), mando 1 en $4016.
- CPLD: $4400 número de registro, $4401 dato, $4402 modo, $4403 estado / byte de configuración del FPGA.
  reg 0 = dato SPI de la SD; reg 1 = USB (sin datos); reg 2 = control de la SD (bit 1 /CS, bit 2 ráfaga);
  reg 6 = nCONFIG; reg 9 bit 0 = BIOS desconectada ($8000-$FFFF = PRG-RAM). Los demás se guardan y se devuelven.
- FPGA en modo OS (como hdl/rtl/n8_os_iface.v): reg 128 ventana PRG en $4800, reg 129 banco de PRG-RAM en $6000,
  reg 130 CHR. Lo que llega por $4403 se guarda por configuración (cada pulso del reg 6). Mientras se configura
  (del pulso del reg 6 a $4402 = 3) no hay nada en $8000-$FFFF. Con el reg 131 distinto de $FF, modo juego: la
  PRG en $8000-$FFFF con la máscara del reg 132 (modelo NROM, para probar el lanzador del OS).
- SD en modo SPI (SDHC o SDSC) sobre una imagen de disco.

La BIOS NO va en el repositorio: se pasa como archivo (16 KiB, ventana $C000-$FFFF).
Todo lo que el programa hace con el hardware queda en `log` y en `accesos`.
"""
import collections

from cpu6502 import CPU


class SD:
    """Tarjeta SD en modo SPI. sdhc=True: direcciones por bloque; False: por byte (SDSC)."""

    def __init__(self, imagen, sdhc=True, log=None):
        self.img = bytearray(imagen)
        self.sdhc = sdhc
        self.log = log if log is not None else []
        self.cmd = []
        self.salida = collections.deque()
        self.idle = True
        self.acmd = False
        self.app41 = 0
        self.modo = None          # None, 'leer_multi', 'escribir', 'escribir_multi'
        self.bloque = 0
        self.wbuf = None
        self.lecturas = []        # bloques leídos, en orden
        self.escrituras = []

    def _blk(self, arg):
        return arg if self.sdhc else arg // 512

    def _datos(self, b):
        d = bytes(self.img[b * 512:(b + 1) * 512]).ljust(512, b'\0')
        self.lecturas.append(b)
        return [0xFF, 0xFF, 0xFE] + list(d) + [0xAA, 0x55]   # espera, testigo, datos, CRC (no se comprueba)

    def byte(self, v, cs):
        """Un byte de SPI: recibe v y devuelve lo que saca la tarjeta. cs=False: tarjeta sin seleccionar."""
        if not cs:
            return 0xFF
        if self.modo in ('escribir', 'escribir_multi'):
            if self.wbuf is not None:
                self.wbuf.append(v)
                if len(self.wbuf) == 515:                      # testigo + 512 + CRC
                    b = self.bloque
                    self.img[b * 512:(b + 1) * 512] = bytes(self.wbuf[1:513])
                    self.escrituras.append(b)
                    self.log.append(('SD_ESCRIBE', b))
                    self.wbuf = None
                    self.bloque += 1
                    self.salida.extend([0x05, 0x00, 0x00, 0xFF])  # aceptado, ocupada, libre
                    if self.modo == 'escribir':
                        self.modo = None
                return 0xFF
            if v == 0xFE or (v == 0xFC and self.modo == 'escribir_multi'):
                self.wbuf = [v]
                return 0xFF
            if v == 0xFD and self.modo == 'escribir_multi':
                self.modo = None
                self.salida.extend([0xFF, 0x00, 0x00, 0xFF])
                return 0xFF
        r = self.salida.popleft() if self.salida else 0xFF
        if self.modo == 'leer_multi' and not self.salida and not self.cmd and v == 0xFF:
            self.salida.extend(self._datos(self.bloque))
            self.bloque += 1
        if self.cmd or (v & 0xC0) == 0x40:
            self.cmd.append(v)
            if len(self.cmd) == 6:
                self._orden()
                self.cmd = []
        return r

    def _orden(self):
        c = self.cmd[0] & 0x3F
        arg = (self.cmd[1] << 24) | (self.cmd[2] << 16) | (self.cmd[3] << 8) | self.cmd[4]
        self.log.append((('SD_ACMD' if self.acmd else 'SD_CMD') + str(c), arg))
        acmd, self.acmd = self.acmd, False
        r1 = 0x01 if self.idle else 0x00
        out = [0xFF]
        if c == 0:
            self.idle = True; self.modo = None; self.salida.clear(); out += [0x01]
        elif c == 8:
            out += [0x01, 0x00, 0x00, 0x01, self.cmd[4]]
        elif c == 55:
            self.acmd = True; out += [r1]
        elif (c == 41 and acmd) or c == 1:
            self.app41 += 1
            if self.app41 >= 3:
                self.idle = False
            out += [0x01 if self.idle else 0x00]
        elif c == 58:
            out += [r1, 0xC0 if self.sdhc else 0x80, 0xFF, 0x80, 0x00]
        elif c in (16, 59):
            out += [r1]
        elif c in (9, 10):
            out += [0x00, 0xFF, 0xFE, 0x40] + [0] * 15 + [0xAA, 0x55]
        elif c == 17:
            self.salida.clear(); out += [0x00] + self._datos(self._blk(arg))
        elif c == 18:
            self.salida.clear()
            self.bloque = self._blk(arg)
            out += [0x00] + self._datos(self.bloque)
            self.bloque += 1
            self.modo = 'leer_multi'
        elif c == 12:
            self.modo = None; self.salida.clear(); out += [0xFF, 0x00, 0xFF]
        elif c == 24:
            self.bloque = self._blk(arg); self.modo = 'escribir'; out += [0x00]
        elif c == 25:
            self.bloque = self._blk(arg); self.modo = 'escribir_multi'; out += [0x00]
        else:
            out += [0x04 | (1 if self.idle else 0)]                 # orden ilegal
        self.salida.extend(out)


class Maquina:
    ROJO = False                         # pantalla(): leer los tiles rojos del OS propio como texto
    def __init__(self, bios, sd, prgram=None):
        if len(bios) != 0x4000:
            raise ValueError('la BIOS debe medir 16 KiB (ventana $C000-$FFFF)')
        self.bios = bytes(bios)
        self.sd = sd
        self.log = sd.log
        self.ram = bytearray(0x800)
        self.prgram = bytearray(prgram if prgram else bytes(0x20000))
        self.prgrom = bytearray(0x80000)
        self.chr = bytearray(0x80000)
        self.nt = bytearray(0x800)
        self.pal = bytearray(0x20)
        self.cpld = collections.defaultdict(int)
        self.sel = 0
        self.m4402 = None
        self.fpga = {128: 0, 129: 0, 130: 0}
        self.mapper = 0xFF             # reg 131: $FF = modo OS; otro valor = juego (modelo NROM: solo PRG)
        self.configurando = False      # entre el pulso de nCONFIG y el final de la carga: el FPGA no mapea nada
        self.pc_en_config = set()      # instrucciones ejecutadas en $8000-$FFFF mientras se configuraba
        self.fpga_cfgs = []            # bytes recibidos por $4403 en cada configuración (pulso 0->1 del reg 6)
        self.ultimo_spi = 0xFF
        self.ppu_ctrl = self.ppu_mask = self.ppu_addr = self.ppu_latch = self.vbl = 0
        self.escrituras_prgram = collections.Counter()   # por banco de 8 KiB
        self.pad = 0                   # botones del mando 1: bit 7 = A ... bit 0 = Derecha (orden de lectura)
        self.pad_sr = 0
        self.cpu = CPU(self.rd, self.wr)
        self.accesos = []              # (pc, 'R'/'W', puerto 0-3, registro seleccionado, valor)
        self.max_accesos = 200000

    # ---------------------------------------------------------------- mapa de memoria
    def bios_off(self):
        return self.cpld[9] & 1

    def rd(self, a):
        if a < 0x2000:
            return self.ram[a & 0x7FF]
        if a < 0x4000:
            r = a & 7
            if r == 2:                                       # VBlank alterno: los bucles de espera avanzan
                self.vbl ^= 1
                self.ppu_latch = 0
                return 0x80 if self.vbl else 0x00
            if r == 7:
                v = self._ppu_rd(self.ppu_addr)
                self._ppu_inc()
                return v
            return 0
        if a == 0x4016:
            v = (self.pad_sr >> 7) & 1
            self.pad_sr = (self.pad_sr << 1) & 0xFF
            return 0x40 | v
        if a < 0x4020:
            return 0x40
        if 0x4400 <= a <= 0x45FF:
            v = self._io_rd(a)
            if len(self.accesos) < self.max_accesos:
                self.accesos.append((self.cpu.pc, 'R', a & 3, self.sel, v))
            return v
        if 0x4800 <= a < 0x5000:
            return self.prgrom[((self.fpga[128] << 11) | (a & 0x7FF)) & 0x7FFFF]
        if 0x6000 <= a < 0x8000:
            return self.prgram[((self.fpga[129] & 0x0F) << 13) | (a & 0x1FFF)]
        if a >= 0x8000:
            if self.configurando and a == self.cpu.pc:
                self.pc_en_config.add(a)
            if not self.bios_off():
                return self.bios[a & 0x3FFF]
            if self.configurando:
                return 0xFF                                  # FPGA sin configurar: nadie contesta
            if self.mapper != 0xFF:                          # juego: PRG con la máscara del reg 132
                return self.prgrom[(a & 0x7FFF) & (((self.fpga.get(132, 0) & 0x1F) + 1 << 14) - 1)]
            return self.prgram[0x18000 | (a & 0x7FFF)]
        return 0xFF

    def wr(self, a, v):
        if a < 0x2000:
            self.ram[a & 0x7FF] = v
            return
        if a < 0x4000:
            r = a & 7
            if r == 0:
                self.ppu_ctrl = v
            elif r == 1:
                self.ppu_mask = v
            elif r == 6:
                if self.ppu_latch == 0:
                    self.ppu_addr = (self.ppu_addr & 0xFF) | ((v & 0x3F) << 8)
                else:
                    self.ppu_addr = (self.ppu_addr & 0xFF00) | v
                self.ppu_latch ^= 1
            elif r == 7:
                self._ppu_wr(self.ppu_addr, v)
                self._ppu_inc()
            return
        if a == 0x4016:
            if v & 1:
                self.pad_sr = self.pad
            return
        if 0x4400 <= a <= 0x45FF:
            if len(self.accesos) < self.max_accesos:
                self.accesos.append((self.cpu.pc, 'W', a & 3, self.sel, v))
            self._io_wr(a, v)
            return
        if 0x4800 <= a < 0x5000:
            self.prgrom[((self.fpga[128] << 11) | (a & 0x7FF)) & 0x7FFFF] = v
            return
        if 0x6000 <= a < 0x8000:
            b = self.fpga[129] & 0x0F
            self.prgram[(b << 13) | (a & 0x1FFF)] = v
            self.escrituras_prgram[b] += 1
            return
        if a >= 0x8000:
            if self.bios_off() and (self.configurando or self.mapper != 0xFF):
                pass                                         # sin FPGA o en un juego: no es la RAM del OS
            elif self.bios_off():
                self.prgram[0x18000 | (a & 0x7FFF)] = v
            else:
                self.log.append(('ESCRITURA_EN_FLASH', self.cpu.pc, a, v))   # nunca debería pasar

    # ---------------------------------------------------------------- PPU
    def _ppu_inc(self):
        self.ppu_addr = (self.ppu_addr + (32 if self.ppu_ctrl & 4 else 1)) & 0x3FFF

    def _chr_dir(self, a):
        b = self.fpga[130] & 0x7F
        if not (a & 0x1000):
            b = (b - 1) & 0x7F
        return (b << 12) | (a & 0xFFF)

    def _ppu_wr(self, a, v):
        if a < 0x2000:
            self.chr[self._chr_dir(a)] = v
        elif a < 0x3F00:
            self.nt[a & 0x7FF] = v
        else:
            self.pal[a & 0x1F] = v

    def _ppu_rd(self, a):
        if a < 0x2000:
            return self.chr[self._chr_dir(a)]
        if a < 0x3F00:
            return self.nt[a & 0x7FF]
        return self.pal[a & 0x1F]

    # tiles $80-$92 de la fuente del OS propio (os/herramientas/fuente.py)
    EXTRA = {0x80 + i: c for i, c in enumerate('áéíóúñüÁÉÍÓÚÑÜ¿¡ºª\u25b6\u25c0\u2026\u2588')}

    def pantalla(self):
        """Nametable 0 como texto (la BIOS y el v13 usan tiles con código ASCII; el OS propio, además, $80-$92)."""
        filas = []
        for f in range(30):
            t = bytes(self.nt[f * 32:(f + 1) * 32])
            if self.ROJO:                    # OS propio: tiles rojos = código ^ $80 (la BIOS usa $00 de relleno)
                t = bytes(c ^ 0x80 if c < 0x20 or c >= 0xA0 else c for c in t)
            s = ''.join(chr(c) if 32 <= c < 127 else self.EXTRA.get(c, ' ') for c in t).rstrip()
            if s.strip():
                filas.append(f'{f:2d} {s}')
        return '\n'.join(filas)

    def rojas(self):
        """Filas de la nametable 0 con algún tile rojo del OS propio (códigos < $20 o >= $A0, sin contar el espacio rojo)."""
        return {f for f in range(30) if any((c < 0x20 or c >= 0xA0) and c != 0xA0 for c in self.nt[f * 32:(f + 1) * 32])}

    # ---------------------------------------------------------------- CPLD / FPGA
    def _cs(self):
        return not (self.cpld[2] & 2)

    def _spi(self, v):
        self.ultimo_spi = self.sd.byte(v, self._cs())
        return self.ultimo_spi

    def _io_rd(self, a):
        p = a & 3
        if p == 1:
            if self.sel == 0:
                if self.cpld[2] & 4:                 # ráfaga: cada lectura saca un byte nuevo
                    return self._spi(0xFF)
                return self.ultimo_spi
            if self.sel == 1:
                return 0x00                          # USB: nada que leer
            if self.sel < 128:
                return self.cpld[self.sel]
            return 0xFF                              # el FPGA no conduce: bus abierto
        if p == 3:
            return 0x01                              # SPI libre; USB sin datos y sin sitio
        return 0xFF

    def _io_wr(self, a, v):
        p = a & 3
        if p == 0:
            self.sel = v
        elif p == 1:
            if self.sel == 0:
                self._spi(v)
            elif self.sel == 1:
                self.log.append(('USB_TX', v))
            elif self.sel < 128:
                ant = self.cpld[self.sel]
                self.cpld[self.sel] = v
                if self.sel == 6 and ant == 0 and v == 1:
                    self.fpga_cfgs.append(bytearray())
                    self.configurando = True
                self.log.append(('CPLD', self.sel, ant, v, self.cpu.pc))
            elif self.mapper != 0xFF:
                self.log.append(('FPGA_EN_JUEGO', self.sel, v, self.cpu.pc))   # en un juego, el dato no se acepta
            else:
                self.fpga[self.sel] = v
                self.log.append(('FPGA', self.sel, v, self.cpu.pc))
                if self.sel == 131:
                    self.mapper = v
        elif p == 2:
            if v != self.m4402:
                self.log.append(('4402', v, self.cpu.pc))
            if self.configurando and self.m4402 == 5 and v == 3:    # fin de la carga: RBF nuevo, en modo OS
                self.configurando = False
                self.fpga = {128: 0, 129: 0, 130: 0}
                self.mapper = 0xFF
                self.log.append(('FPGA_CONFIG', len(self.fpga_cfgs[-1]), self.cpu.pc))
            self.m4402 = v
        else:
            if self.fpga_cfgs:
                self.fpga_cfgs[-1].append(v)

    # ---------------------------------------------------------------- ejecución
    def correr(self, max_pasos, parar=None, nmi_cada=None):
        """Ejecuta hasta max_pasos instrucciones. nmi_cada: NMI cada N instrucciones si $2000 bit 7 está a 1."""
        cpu = self.cpu
        for n in range(1, max_pasos + 1):
            if not cpu.paso():
                self.log.append(('ILEGAL', cpu.ilegal))
                return 'ilegal'
            if parar is not None and parar(self):
                return 'parada'
            if nmi_cada and n % nmi_cada == 0 and (self.ppu_ctrl & 0x80):
                cpu.nmi()
        return 'limite'

    def reset_consola(self):
        """Reset de la consola: M2 se para, el RBF vuelve al modo OS y la CPU lee su vector de reset."""
        self.mapper = 0xFF
        self.cpu.reset()

    def arrancar_bios(self, max_pasos=4_000_000):
        """Reset y BIOS hasta que salta al OS (bios_off = 1 y PC en $8000-$FBFF)."""
        self.cpu.reset()
        return self.correr(max_pasos, lambda m: m.bios_off() and 0x8000 <= m.cpu.pc < 0xFC00)
