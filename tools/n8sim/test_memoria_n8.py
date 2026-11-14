import pathlib
import tempfile
import unittest

import difftest
import memoria_n8


class MemoriaN8(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.rom = pathlib.Path(self.tmp.name) / 'prueba.nes'

    def escribir(self, mapper=4, prg=32, chr_=64, ram=0, cram=0, extension=0,
                 payload=1048576):
        h = bytearray(b'NES\x1a' + bytes(12))
        h[4:12] = bytes((prg, chr_, (mapper & 15) << 4,
                         (mapper & 240) | 8, (mapper >> 8) & 15, extension, ram, cram))
        with self.rom.open('wb') as f:
            f.write(h)
            f.truncate(16 + payload)

    def test_memorias_prg_chr_independientes(self):
        self.escribir()
        self.assertTrue(memoria_n8.revisar(self.rom)['admitida'])

    def test_tamano_extendido_no_se_trunca(self):
        self.escribir(prg=1,extension=1)
        info = difftest.ines(self.rom)
        self.assertEqual(info['prg_bytes'],257*16384)
        self.assertFalse(memoria_n8.revisar(self.rom)['admitida'])

    def test_exponente_multiplicador(self):
        self.escribir(prg=(16 << 2) | 1,chr_=0,extension=15)
        self.assertEqual(difftest.ines(self.rom)['prg_bytes'],3*(1 << 16))
        self.assertFalse(memoria_n8.revisar(self.rom)['admitida'])

    def test_ram_volatil_y_pila_se_suman(self):
        self.escribir(mapper=5,ram=0x99)
        i=difftest.ines(self.rom)
        self.assertEqual(i['prg_ram_bytes']+i['prg_nvram_bytes'],65536)
        self.assertTrue(memoria_n8.revisar(self.rom)['admitida'])
        self.escribir(mapper=5,ram=0xaa)
        self.assertFalse(memoria_n8.revisar(self.rom)['admitida'])

    def test_chr_ram_no_se_ignora(self):
        self.escribir(mapper=28,chr_=0,cram=10)
        self.assertEqual(difftest.ines(self.rom)['chr_ram_bytes'],65536)
        self.assertFalse(memoria_n8.revisar(self.rom)['admitida'])
        self.escribir(mapper=28,chr_=0,cram=9)
        self.assertTrue(memoria_n8.revisar(self.rom)['admitida'])

    def test_fk23c_evitar_solape(self):
        self.escribir(mapper=176)
        self.assertFalse(memoria_n8.revisar(self.rom)['admitida'])
        self.escribir(mapper=176,chr_=32,cram=12)
        self.assertTrue(memoria_n8.revisar(self.rom)['admitida'])

    def test_truncada(self):
        self.escribir(payload=0)
        self.assertFalse(memoria_n8.revisar(self.rom)['admitida'])
        self.rom.write_bytes(b'NES\x1a')
        self.assertIsNone(difftest.ines(self.rom))


if __name__ == '__main__':
    unittest.main()
