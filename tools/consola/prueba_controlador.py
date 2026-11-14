"""Pruebas del controlador sin USB: percepción, decisiones y vencimiento de botones."""
import pathlib
import sys
import unittest

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from controlador import Latencia, Marcador, MandoVigilado, Movimiento, ROOT, SMB, Vista


class Pruebas(unittest.TestCase):
    def test_no_actua_sin_personaje_o_marcador(self):
        p = SMB()
        self.assertEqual(p.decidir(Vista(None, '1-1'), 0)[0], 0)
        self.assertEqual(p.decidir(Vista((40,192,56,208), None), 0)[0], 0)

    def test_hueco_salta_y_suelta_a(self):
        p = SMB()
        v = Vista((100,192,116,208), '1-1', True, hueco=30)
        self.assertEqual(p.decidir(v, 1)[0], 0x82)  # confirmar apoyo antes de saltar
        self.assertEqual(p.decidir(v, 1.05)[0], 0x83)
        self.assertEqual(p.decidir(v, 1.2)[0], 0x83)
        self.assertEqual(p.decidir(v, 1.51)[0], 0x82)
        self.assertEqual(p.decidir(v, 1.7)[0], 0x83)

    def test_no_salta_en_el_aire(self):
        p = SMB()
        self.assertEqual(p.decidir(Vista((100,120,116,136), '1-1', False, hueco=0), 1)[0], 0x82)

    def test_latencia_adelanta_el_salto(self):
        v = Vista((100,192,116,208), '1-1', True, hueco=48, vx=160)
        normal, calibrado = SMB(), SMB(latencia=Latencia(.09,.09,.01))
        normal.decidir(v, .9); calibrado.decidir(v, .9)
        self.assertEqual(normal.decidir(v, 1)[0], 0x82)
        self.assertEqual(calibrado.decidir(v, 1)[0], 0x83)

    def test_parado_no_anticipa_por_velocidad_inventada(self):
        p = SMB(latencia=Latencia(.1,.1,.01))
        v = Vista((100,192,116,208), '1-1', True, hueco=48, vx=0)
        p.decidir(v, .9)
        self.assertEqual(p.decidir(v, 1)[0], 0x82)

    def test_enemigo_que_se_acerca_usa_velocidad_relativa(self):
        p = SMB(latencia=Latencia(.1,.1,0))
        v = Vista((100,192,116,208), '1-1', True, enemigo=65, vx=40,
                  cierre={'enemigo':180})
        p.decidir(v, .9)
        self.assertEqual(p.decidir(v, 1)[0], 0x83)

    def test_no_repite_salto_antes_de_liberacion_y_apoyo(self):
        p = SMB(latencia=Latencia(.09,.1,.01))
        v = Vista((100,192,116,208), '1-1', True, hueco=20)
        p.decidir(v, 1); p.decidir(v, 1.05)
        aire = Vista((100,120,116,136), '1-1', False, hueco=0, vy=80)
        self.assertEqual(p.decidir(aire,1.55)[0], 0x82)
        self.assertEqual(p.decidir(aire,2)[0], 0x82)
        self.assertEqual(p.decidir(v,2.01)[0], 0x82)
        self.assertEqual(p.decidir(v,2.08)[0], 0x83)

    def test_scroll_mide_avance_aunque_mario_no_cambie_de_columna(self):
        rng = np.random.default_rng(12)
        escena = rng.integers(0,255,(240,256,3),dtype=np.uint8)
        m = Movimiento()
        for i in range(15):
            v = Vista((120,192,136,208), '1-1', True)
            m.actualizar(np.roll(escena,-4*i,axis=1),v,i*.05)
        self.assertGreater(v.vx,65)
        self.assertLess(v.vx,95)
        self.assertAlmostEqual(v.vy,0)

    def test_calibracion_rechaza_nan(self):
        data = {'pulsar':{'mediana_s':float('nan'),'p90_s':.1},
                'soltar':{'mediana_s':.09,'p90_s':.1}}
        with self.assertRaises(ValueError): Latencia.desde_medicion(data)

    def test_marcador_no_inventa_digitos(self):
        p = Marcador.cargar(ROOT/'perfiles/smb-digitos.json')
        self.assertIsNone(p.nivel(np.zeros((240,256,3), np.uint8)))
        a = np.zeros((240,256,3), np.uint8)
        for x, d in [(152,1),(168,3)]:
            a[24:32,x:x+8] = p.templates[d][...,None]*255
        a[27:29,161:167] = 255
        self.assertEqual(p.nivel(a), '1-3')

    def test_mario_y_hueco_sintetico(self):
        a = np.full((240,256,3), (56,110,230), np.uint8)
        a[208:240,:] = (130,50,0)
        a[208:240,140:180] = (56,110,230)
        a[192:195,100:110] = (175,22,0)
        a[195:201,101:110] = (195,115,0)
        a[201:207,101:110] = (175,22,0)
        v = SMB().ver(a)
        self.assertIsNotNone(v.mario)
        self.assertTrue(v.suelo)
        self.assertLessEqual(v.hueco, 38)

    def test_pulsos_limitados_y_no_se_renuevan_sin_vision(self):
        class Mando:
            def __init__(self): self.calls = []
            def orden(self, c): self.calls.append(c)
        m = Mando()
        d = MandoVigilado(m)
        d.enviar(0x82, 1)
        d.enviar(0x82, 1.05)
        d.enviar(0, 1.1)
        d.enviar(0, 2)
        self.assertEqual(m.calls, ['T b+right 250', 'T b+right 1'])


if __name__ == '__main__':
    unittest.main()
