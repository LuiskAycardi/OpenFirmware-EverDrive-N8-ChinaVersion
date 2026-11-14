"""Comprueba búsqueda y exportación del bot sin Mesen, USB ni capturadora."""
import json
import pathlib
import sys
import tempfile
import unittest
from unittest import mock

from PIL import Image

sys.path.insert(0,str(pathlib.Path(__file__).resolve().parent))
import explorador as e
import tas


class Explorador(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.d = pathlib.Path(self.tmp.name)
        self.perfil = dict(arranque_fotogramas=4,arranque=[],acciones={
            'derecha':dict(mantener='right'),'a':dict(pulsar='a'), 'reposo':{}})

    def test_fm2_preserva_cada_boton_y_encendido(self):
        rom = self.d/'prueba.nes'
        rom.write_bytes(b'NES\x1a'+bytes(12)+bytes(range(256)))
        entradas = bytes(range(256))
        ruta = self.d/'pelicula.fm2'
        e.escribir_fm2(ruta,rom,entradas)
        cab,leidas,ordenes = tas.leer_fm2(ruta)
        self.assertEqual(bytes(leidas),b'\0'+entradas)
        self.assertEqual(ordenes,[2]+[0]*256)
        self.assertEqual(cab['romChecksum'],tas.md5_rom(rom))

    def test_pulsos_liberan_y_no_direcciones_opuestas(self):
        self.assertEqual(e.bloque(dict(mantener='right',pulsar='a',duracion_pulso=2),4),bytes([129,129,128,128]))
        self.assertEqual(e.bloque(dict(pulsar='b',periodo=4,duracion_pulso=2),8),bytes([2,2,0,0,2,2,0,0]))
        with self.assertRaises(ValueError):e.mascara('right+left')
        with self.assertRaises(ValueError):e.bloque(dict(mantener='up',pulsar='down'),3)

    def test_busqueda_respeta_presupuesto_y_reproduce_decisiones(self):
        calls=[]
        def evaluar(entrada,n):
            calls.append(entrada)
            return dict(puntuacion=entrada.count(128))
        kwargs=dict(seed=3,evaluaciones=8,profundidad=4,ancho=2,fotogramas_bloque=3)
        a,h=e.buscar(self.perfil,evaluar,**kwargs)
        b,h2=e.buscar(self.perfil,lambda entrada,n:dict(puntuacion=entrada.count(128)),**kwargs)
        self.assertLessEqual(len(calls),8)
        self.assertGreater(len(calls),1)
        self.assertEqual(a.entrada,b.entrada)
        self.assertEqual(a.acciones,b.acciones)
        self.assertGreater(a.entrada.count(128),0)
        self.assertEqual(a.entrada[:4],bytes(4))
        self.assertEqual(h,h2)

    def test_no_exporta_exploracion_fallida(self):
        with self.assertRaises(RuntimeError):
            e.buscar(self.perfil,lambda *_:dict(error='fallo de emulador'))

    def test_puntuacion_no_inventa_nivel_completado(self):
        paths=[]
        for i in range(4):
            p=self.d/f'{i}.png'
            im=Image.new('RGB',(256,240),'black')
            # Escenas con contraste y posiciones diferentes.
            im.paste((255,255,255),(20+40*i,80,50+40*i,180))
            im.save(p);paths.append(p)
        cambiante=e.puntuar(paths)
        quieta=e.puntuar([paths[0]]*4)
        self.assertGreater(cambiante['puntuacion'],quieta['puntuacion'])
        self.assertIsNone(cambiante['nivel_completado'])
        self.assertIsNone(cambiante['juego_completado'])

    def test_repeticion_nueva_no_usa_cache_y_detecta_diferencias(self):
        rom=self.d/'prueba.nes';rom.write_bytes(bytes(32))
        movie=self.d/'recorrido.fm2';e.escribir_fm2(movie,rom,bytes([128]*4))
        assets=[self.d/f'asset{i}' for i in range(3)]
        for p in assets:p.write_bytes(b'original')
        evaluacion=dict(hashes_capturas={'f00004.png':'pixelsha'},polls_sha256='pollsha',p0=1)
        datos=dict(rom=str(rom),rom_sha256=e.sha(rom),pelicula=str(movie),pelicula_sha256=e.sha(movie),
                   mesen_sha256=e.sha(assets[0]),ajustes_sha256=e.sha(assets[1]),lua_sha256=e.sha(assets[2]),
                   explorador_sha256=e.sha(e.__file__),
                   cada=2,evaluacion=evaluacion)
        ruta=self.d/'recorrido.json';ruta.write_text(json.dumps(datos))
        carpetas=[]
        class Falso:
            def __init__(self,rom,out,cada):carpetas.append(out)
            def __call__(self,*_):return dict(evaluacion)
        with mock.patch.multiple(e.referencia,MESEN=assets[0],AJUSTES=assets[1],LUA=assets[2]),mock.patch.object(e,'EvaluadorMesen',Falso):
            e.verificar(type('Args',(),{'recorrido':self.d})())
            e.verificar(type('Args',(),{'recorrido':self.d})())
            self.assertNotEqual(carpetas[0],carpetas[1])
            evaluacion['polls_sha256']='distinto'
            with self.assertRaises(SystemExit):e.verificar(type('Args',(),{'recorrido':self.d})())
        self.assertFalse(json.loads(ruta.read_text())['repeticion_identica'])

    def test_evaluador_entrega_entrada_y_recoge_evidencia_sin_emulador(self):
        def generar(rom,guion,shots,frames,d,entrada,desfase):
            self.assertEqual(pathlib.Path(entrada).read_bytes(),bytes([0,128,129,128,128]))
            self.assertEqual(desfase,1)
            self.assertEqual(frames,4)
            for n in shots:
                im=Image.new('RGB',(256,240),'black')
                im.paste('white',(10+n*10,80,50+n*10,180))
                im.save(d/f'f{n:05d}.png')
            (d/'polls.txt').write_text('1 1\n2 1\n3 1\n')
            return dict(p0=1)
        with mock.patch.object(e.referencia,'generar',generar):
            r=e.EvaluadorMesen(self.d/'rom.nes',self.d/'capturas',2)(bytes([128,129,128,128]),0)
        self.assertNotIn('error',r)
        self.assertEqual(len(r['hashes_capturas']),2)
        self.assertEqual(r['p0'],1)
        self.assertIsNone(r['juego_completado'])

    def test_lote_continua_tras_fallo_y_guarda_sin_hardware(self):
        plan=self.d/'plan.json'
        plan.write_text(json.dumps(dict(tareas=[dict(rom='falla.nes',mapper=1,out='uno',perfil='generico'),
                                               dict(rom='otro.nes',mapper=2,out='dos',perfil='generico')])))
        args=type('Args',(),dict(plan=plan,out=self.d/'lote',limite=2,perfil=None,seed=7,
             perfiles=e.PERFILES,evaluaciones=3,profundidad=2,ancho=1,bloque=4,cada=2,
             reintentar_fallidas=False))()
        llamadas=[]
        def explorar(a):
            llamadas.append(a.rom.name)
            if a.rom.name=='falla.nes':raise RuntimeError('fallo esperado')
        with mock.patch.object(e,'explorar',explorar),mock.patch.object(e,'verificar') as verificar:
            e.lote(args)
            verificar.assert_called_once()
        datos=json.loads((args.out/'lote.json').read_text())
        self.assertEqual(llamadas,['falla.nes','otro.nes'])
        self.assertEqual([x['repeticion_identica'] for x in datos['resultados']],[False,True])


if __name__=='__main__':unittest.main()
