"""Pruebas de archivo, géneros y evidencia visual: no ejecuta emuladores."""
import json
import pathlib
import sys
import tempfile
import unittest
import argparse
import contextlib
import io
from unittest import mock

from PIL import Image

sys.path.insert(0,str(pathlib.Path(__file__).resolve().parent))
import explorador as e
import exploracion_v2 as v2
from explorador_generos import clasificar


class ExploradorV2(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.d=pathlib.Path(self.tmp.name)

    def perfil(self):
        return dict(arranque_fotogramas=2,arranque=[],escalas_duracion=[1],
                    acciones={'derecha':{'mantener':'right'},'izquierda':{'mantener':'left'}})

    def imagen(self,n,x=30):
        p=self.d/f'f{n:05d}.png'
        im=Image.new('RGB',(256,240),'black')
        im.paste('white',(x,60,x+30,220));im.save(p)
        return p

    def test_archivo_rescata_ruta_con_recompensa_tardia(self):
        def evaluar(entrada,n):
            estado=0
            for b in entrada[2:]:
                if estado==0:estado=1 if b==128 else 2
                elif estado==2 and b==64:estado=3
            return dict(puntuacion={0:0,1:10,2:1,3:100}[estado],celda_final=f's{estado}')
        a,h,archivo=v2.buscar_archivo(self.perfil(),evaluar,e.inicio,e.bloque,
                                     seed=7,evaluaciones=12,profundidad=3,ancho=16,fotogramas_bloque=1)
        self.assertEqual(a.evaluacion['puntuacion'],100)
        self.assertIn('s1',archivo)  # el callejón sin salida atractivo no borró las otras rutas
        self.assertIn('s2',archivo)
        self.assertLessEqual(len(h),12)

    def test_archivo_y_semilla_reproducen_acciones(self):
        def evaluar(b,n):return dict(puntuacion=sum(b),celda_final=str(sum(b)%7))
        args=dict(seed=5,evaluaciones=10,profundidad=4,ancho=3,fotogramas_bloque=2)
        a,h,arch=v2.buscar_archivo(self.perfil(),evaluar,e.inicio,e.bloque,**args)
        b,h2,arch2=v2.buscar_archivo(self.perfil(),evaluar,e.inicio,e.bloque,**args)
        self.assertEqual(a.entrada,b.entrada)
        self.assertEqual(h,h2)
        self.assertLessEqual(len(arch),3)

    def test_error_no_se_guarda_como_celda_valida(self):
        p=self.perfil()
        p['variantes_arranque']=[dict(nombre='otro',fotogramas=2,
                                      arranque=[dict(desde=0,hasta=1,botones='a')])]
        def evaluar(b,n):return dict(error='fallo') if n==0 else dict(puntuacion=1,celda_final='ok')
        _,h,archivo=v2.buscar_archivo(p,evaluar,e.inicio,e.bloque,evaluaciones=4,
                                    profundidad=2,ancho=2,fotogramas_bloque=1)
        self.assertEqual(h[0]['error'],'fallo')
        self.assertEqual(list(archivo),['ok'])

    def test_macro_compuesto_preserva_orden_y_liberaciones(self):
        accion=dict(secuencia=[dict(botones='down',fotogramas=2),
                              dict(botones='right+a',fotogramas=2),dict(botones='',fotogramas=1)])
        self.assertEqual(e.bloque(accion,7),bytes([32,32,129,129,0,0,0]))
        accion['repetir']=True
        self.assertEqual(e.bloque(accion,7),bytes([32,32,129,129,0,32,32]))

    def test_todos_los_perfiles_generan_acciones_sin_opuestos(self):
        perfiles=json.loads(e.PERFILES.read_text())
        self.assertGreaterEqual(len(perfiles),13)
        for nombre in perfiles:
            if nombre=='periferico':continue
            p=e.cargar_perfil(nombre,e.PERFILES)
            for a in p['acciones'].values():
                for b in e.bloque(a,180):
                    self.assertNotEqual(b&0xc0,0xc0,(nombre,a))
                    self.assertNotEqual(b&0x30,0x30,(nombre,a))

    def test_agrupacion_no_premia_un_pixel_aislado(self):
        a=bytes(192);b=bytes([1])+bytes(191);c=bytes([7]*192)
        self.assertEqual(v2.agrupar([a,b,c]),[0,0,1])

    def test_bucles_visuales_penalizados_sin_inventar_victorias(self):
        a,b,c,d=[self.imagen(n,x) for n,x in enumerate((10,70,130,200))]
        perfil=dict(arranque_fotogramas=0,vision=dict(ventana_temporal=1),objetivos=[])
        bucle=v2.analizar([a,b,a,b,a,b],perfil)
        ruta=v2.analizar([a,b,c,d],perfil)
        self.assertGreater(bucle['proporcion_bucles'],.5)
        self.assertGreater(ruta['puntuacion'],bucle['puntuacion'])
        self.assertIsNone(ruta['juego_completado'])

    def test_hud_no_cambia_la_celda_de_juego(self):
        a=self.imagen(1)
        b=self.d/'f00002.png'
        with Image.open(a) as im:
            im.paste('white',(0,0,256,32));im.save(b)
        tokens,_=v2.descriptores([a,b],dict(vision=dict(ventana_temporal=1)))
        self.assertEqual(tokens[0],tokens[1])

    def objetivo(self):
        patron=Image.new('RGB',(32,32),'black')
        patron.paste('white',(0,0,16,32))
        patron.save(self.d/'meta.png')
        return dict(_directorio=str(self.d),objetivos=[dict(nombre='final_prueba',tipo='juego',
             plantilla='meta.png',rom_sha256='abc',roi=[64,64,96,96],consecutivas=2,error_maximo=.01)])

    def test_objetivo_requiere_rom_exacta_y_dos_observaciones(self):
        perfil=self.objetivo()
        with self.assertRaises(ValueError):v2.huellas_objetivos(perfil,'otra_rom')
        self.assertEqual(len(v2.huellas_objetivos(perfil,'abc')),1)
        paths=[]
        for n in range(2):
            p=self.imagen(n)
            with Image.open(p) as im, Image.open(self.d/'meta.png') as meta:
                im.paste(meta,(64,64));im.save(p)
            paths.append(p)
        self.assertEqual(v2.objetivos_visuales(paths[:1],perfil),[])
        hallados=v2.objetivos_visuales(paths,perfil)
        self.assertEqual(hallados[0]['tipo'],'juego')

    def test_plantilla_uniforme_no_certifica_final(self):
        perfil=self.objetivo()
        Image.new('RGB',(32,32),'black').save(self.d/'meta.png')
        with self.assertRaises(ValueError):v2.huellas_objetivos(perfil,'abc')

    def test_genero_no_se_deduce_del_mapper_y_periferico_se_separa(self):
        p=self.d/'Gimmick! (Japan).nes'
        h=bytearray(b'NES\x1a'+bytes(12));h[7]=8;h[6]=0xf0
        p.write_bytes(h)
        self.assertEqual(clasificar(p)['perfil'],'plataformas')
        h[15]=8;p.write_bytes(h)
        self.assertEqual(clasificar(p)['perfil'],'periferico')
        self.assertEqual(clasificar(p)['dispositivo'],'Zapper')

    def test_recuperacion_se_intenta_al_estancarse(self):
        perfil=self.perfil()
        perfil['acciones']={'rescatar':dict(mantener='a',fase='recuperacion')}
        def evaluar(b,n):return dict(puntuacion=b.count(1),celda_final=str(n),estancamiento_visual=True)
        mejor,h,_=v2.buscar_archivo(perfil,evaluar,e.inicio,e.bloque,evaluaciones=3,
                                  profundidad=2,ancho=8,fotogramas_bloque=1)
        self.assertIn(1,mejor.entrada)

    def test_pipeline_exporta_rutas_y_las_repite_sin_mesen(self):
        rom=self.d/'Gimmick! (Japan).nes'
        header=bytearray(b'NES\x1a'+bytes(12));header[4]=1;header[5]=1;header[7]=8
        rom.write_bytes(header+bytes(16384+8192))
        assets=[self.d/f'asset{n}' for n in range(3)]
        for p in assets:p.write_bytes(b'fixture')
        def generar(rom,guion,shots,frames,d,entrada,desfase):
            botones=pathlib.Path(entrada).read_bytes()
            for frame in shots:
                # Estado causal determinista: no depende de los botones futuros.
                x=sum(botones[1:frame+1])%200
                im=Image.new('RGB',(256,240),'black')
                im.paste('white',(x,60,x+30,220))
                im.save(d/f'f{frame:05d}.png')
            (d/'polls.txt').write_text(''.join(f'{n} 1\n' for n in range(1,frames+1)))
            return dict(p0=1)
        a=argparse.Namespace(rom=rom,out=self.d/'salida',perfiles=e.PERFILES,perfil='auto',seed=7,
             evaluaciones=8,profundidad=3,ancho=2,bloque=30,cada=30,motor='archivo',archivo_max=8,rutas=3)
        with mock.patch.multiple(e.referencia,MESEN=assets[0],AJUSTES=assets[1],LUA=assets[2]), \
             mock.patch.object(e.referencia,'generar',generar),contextlib.redirect_stdout(io.StringIO()):
            e.explorar(a)
            e.verificar(argparse.Namespace(recorrido=a.out))
            datos=json.loads((a.out/'recorrido.json').read_text())
            self.assertTrue(datos['repeticion_identica'])
            self.assertEqual(datos['perfil'],'plataformas')
            self.assertIsNone(datos['juego_completado'])
            self.assertTrue((a.out/'archivo_estados.json').exists())
            self.assertGreaterEqual(len(datos['rutas_alternativas']),1)
            alternativa=pathlib.Path(datos['rutas_alternativas'][0]['directorio'])
            e.verificar(argparse.Namespace(recorrido=alternativa))
            self.assertTrue(json.loads((alternativa/'recorrido.json').read_text())['repeticion_identica'])

    def test_ajustes_por_rom_no_contaminan_otros_juegos_del_genero(self):
        uno=self.d/'uno.nes';uno.write_bytes(b'rom uno')
        dos=self.d/'dos.nes';dos.write_bytes(b'rom dos')
        ajustes=self.d/'juegos.json'
        ajustes.write_text(json.dumps(dict(por_sha256={e.sha(uno):dict(arranque_fotogramas=360,
            arranque=[dict(desde=300,hasta=312,botones='a')],vision=dict(roi=[0,8,256,240]))})))
        a=e.cargar_perfil('plataformas',e.PERFILES,uno,ajustes)
        b=e.cargar_perfil('plataformas',e.PERFILES,dos,ajustes)
        self.assertEqual(a['arranque_fotogramas'],360)
        self.assertEqual(b['arranque_fotogramas'],240)
        self.assertEqual(a['vision']['roi'],[0,8,256,240])
        self.assertEqual(b['vision']['roi'],[0,40,256,240])
        self.assertEqual(a['_juegos_sha256'],e.sha(ajustes))


if __name__=='__main__':unittest.main()
