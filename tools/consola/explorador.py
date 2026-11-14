#!/usr/bin/env python3
"""Bot de exploración visual en Mesen2; exporta entradas FM2 para repetir en la NES.

No controla hardware. `plan` prepara archivos; `explorar` y `verificar` sí ejecutan Mesen2.
La novedad visual no demuestra avanzar de nivel ni terminar un juego.
"""
import argparse
import dataclasses
import hashlib
import json
import pathlib
import random
import sys
import tempfile
import time

from PIL import Image, ImageStat

AQUI = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(AQUI))
sys.path.insert(0, str(AQUI.parent / 'n8sim'))
import memoria_n8
import cobertura
import referencia
import tas
import exploracion_v2 as v2
from explorador_generos import clasificar

BOTONES = {'a':1, 'b':2, 'select':4, 'start':8, 'up':16, 'down':32, 'left':64, 'right':128}
PERFILES = AQUI / 'perfiles/explorador.json'
JUEGOS = AQUI / 'perfiles/juegos_explorador.json'


def sha(ruta):
    return hashlib.sha256(pathlib.Path(ruta).read_bytes()).hexdigest()


def guardar_json(ruta,datos):
    ruta=pathlib.Path(ruta)
    temporal=ruta.with_suffix(ruta.suffix+'.tmp')
    temporal.write_text(json.dumps(datos,ensure_ascii=False,indent=1)+'\n')
    temporal.replace(ruta)


def mascara(texto):
    valor = 0
    for tecla in texto.split('+'):
        if tecla:
            if tecla not in BOTONES:
                raise ValueError(f'Botón desconocido: {tecla}')
            valor |= BOTONES[tecla]
    if valor & 0xc0 == 0xc0 or valor & 0x30 == 0x30:
        raise ValueError('Direcciones opuestas no admitidas')
    return valor


def inicio(perfil):
    datos = bytearray(perfil['arranque_fotogramas'])
    for pulso in perfil['arranque']:
        a, b = pulso['desde'], pulso['hasta']
        if not 0 <= a < b <= len(datos):
            raise ValueError('Pulso de arranque fuera de rango')
        datos[a:b] = bytes([mascara(pulso['botones'])]) * (b-a)
    return bytes(datos)


def bloque(accion, longitud):
    if 'secuencia' in accion:
        patron=bytearray()
        for paso in accion['secuencia']:
            n=paso['fotogramas']
            if not isinstance(n,int) or not 1<=n<=600:
                raise ValueError('Duración de paso fuera de rango')
            patron.extend([mascara(paso.get('botones',''))]*n)
        if not patron:raise ValueError('Secuencia de acción vacía')
        if accion.get('repetir'):
            return bytes((patron*((longitud+len(patron)-1)//len(patron)))[:longitud])
        return bytes((patron+bytes(max(0,longitud-len(patron))))[:longitud])
    base = mascara(accion.get('mantener',''))
    pulso = mascara(accion.get('pulsar',''))
    # Validar también la combinación, no solo sus componentes.
    mascara('+'.join(k for k,v in BOTONES.items() if (base|pulso)&v))
    duracion = min(longitud, accion.get('duracion_pulso',max(1,longitud//3)))
    periodo = accion.get('periodo',0)
    if periodo < 0 or duracion < 0:
        raise ValueError('Duraciones negativas')
    return bytes(base | (pulso if ((f % periodo < duracion) if periodo else f < duracion) else 0)
                 for f in range(longitud))


def cargar_perfil(nombre,archivo,rom=None,juegos=None):
    perfiles=json.loads(pathlib.Path(archivo).read_text())
    if nombre not in perfiles:raise ValueError(f'Perfil desconocido: {nombre}')
    perfil=perfiles[nombre]
    perfil['_directorio']=str(pathlib.Path(archivo).resolve().parent)
    if rom is not None:
        juegos=pathlib.Path(juegos or JUEGOS)
        if not juegos.exists():raise ValueError(f'No existe el archivo de ajustes por ROM: {juegos}')
        if juegos.exists():
            ajustes=json.loads(juegos.read_text()).get('por_sha256',{}).get(sha(rom),{})
            permitidas={'arranque','arranque_fotogramas','variantes_arranque','acciones','vision','objetivos','escalas_duracion'}
            if set(ajustes)-permitidas:raise ValueError('Campo de ajuste por ROM desconocido')
            for clave,valor in ajustes.items():
                if clave in ('acciones','vision'):perfil[clave]=dict(perfil.get(clave,{}),**valor)
                else:perfil[clave]=valor
            if 'objetivos' in ajustes:perfil['_directorio']=str(juegos.resolve().parent)
            perfil['_juegos_archivo']=str(juegos.resolve())
            perfil['_juegos_sha256']=sha(juegos)
    if perfil.get('requiere_periferico'):
        raise ValueError('La ROM declara un periférico que este bot de mando estándar no controla')
    for _,entrada in v2.variantes_inicio(perfil,inicio):
        if not 1<=len(entrada)<=3600:raise ValueError('Arranque fuera de rango')
    for accion in perfil['acciones'].values():
        if accion.get('fase','juego') not in ('menu','juego','recuperacion'):
            raise ValueError('Fase de acción desconocida')
        bloque(accion,90)
    if not perfil['acciones']:raise ValueError('Perfil sin acciones')
    roi=perfil.get('vision',{}).get('roi',[0,40,256,240])
    if len(roi)!=4 or not (0<=roi[0]<roi[2]<=256 and 0<=roi[1]<roi[3]<=240):
        raise ValueError('ROI de visión fuera de la imagen NES')
    if perfil.get('vision',{}).get('ventana_temporal',3) not in (1,3,5):
        raise ValueError('Ventana temporal inválida')
    tolerancia=perfil.get('vision',{}).get('tolerancia_celda',.12)
    if not isinstance(tolerancia,(float,int)) or not 0<=tolerancia<=1:
        raise ValueError('Tolerancia de celdas inválida')
    escalas=perfil.get('escalas_duracion',[.5,1,2])
    if not escalas or any(not isinstance(n,(float,int)) or not 0<n<=4 for n in escalas):
        raise ValueError('Escalas de duración fuera de rango')
    return perfil


def parametros(a):
    valores={k:getattr(a,k) for k in ('evaluaciones','profundidad','ancho','bloque','cada')}
    valores.update(motor=getattr(a,'motor','archivo'),archivo_max=getattr(a,'archivo_max',128),
                   rutas=getattr(a,'rutas',3))
    return valores


def escribir_fm2(ruta, rom, entrada):
    # Índice 0 reservado al encendido; índice f+1 aplicado por mesen_ref.lua al fotograma f.
    lineas = ['version 3', 'emuVersion 0', 'rerecordCount 0', 'palFlag 0',
              f'romFilename {pathlib.Path(rom).stem}', f'romChecksum {tas.md5_rom(rom)}',
              'fourscore 0', 'microphone 0', 'port0 1', 'port1 0', 'port2 0',
              'comment author Explorador local del banco N8; no es un TAS publicado',
              'comment origin Entradas generadas para Mesen2 y exportadas a FM2; no grabadas con FCEUX',
              '|2|........|||']
    for valor in entrada:
        botones = ''.join(c if valor & (1 << tas.BIT[c]) else '.' for c in tas.ORDEN_FM2)
        lineas.append(f'|0|{botones}|||')
    pathlib.Path(ruta).write_text('\n'.join(lineas)+'\n')


def imagen_estado(ruta):
    with Image.open(ruta) as imagen:
        if imagen.size!=(256,240):
            raise ValueError('Se requiere una captura NES de 256x240')
        # Se omite el HUD superior para que el contador/puntuación no domine el premio.
        gris = imagen.convert('L').crop((0,40,256,240))
        pequena = gris.resize((16,12),Image.Resampling.BOX)
        token = bytes(min(7,v//32) for v in pequena.tobytes())
        vacia = ImageStat.Stat(gris).stddev[0] < 2
        return token, vacia


def puntuar(capturas):
    estados = [imagen_estado(p) for p in capturas]
    tokens = [t for t,vacia in estados if not vacia]
    cambios = sum(a != b for a,b in zip(tokens,tokens[1:]))
    quieto = len(tokens)>=3 and len(set(tokens[-3:]))==1
    valor = len(set(tokens)) + .1*cambios - 2*sum(v for _,v in estados) - 2*quieto
    return dict(puntuacion=valor,estados_visuales=len(set(tokens)),cambios=cambios,
                capturas_vacias=sum(v for _,v in estados),estancamiento_visual=quieto,
                nivel_completado=None,juego_completado=None)


@dataclasses.dataclass
class Candidato:
    entrada: bytes
    acciones: tuple
    evaluacion: dict


def buscar(perfil, evaluar, *, seed=7, evaluaciones=24, profundidad=8, ancho=2, fotogramas_bloque=90):
    """Búsqueda por haces, con presupuesto: cada candidato se reproduce desde encendido."""
    rng = random.Random(seed)
    cola = [(inicio(perfil),())]
    vistos = set()
    ganadores = []
    historial = []
    for paso in range(profundidad):
        propuestas = []
        for entrada,acciones in cola:
            nombres = list(perfil['acciones'])
            rng.shuffle(nombres)
            for nombre in nombres:
                siguiente = entrada + bloque(perfil['acciones'][nombre],fotogramas_bloque)
                digest = hashlib.sha256(siguiente).hexdigest()
                if digest not in vistos:
                    propuestas.append((siguiente,acciones+(nombre,)))
                    vistos.add(digest)
        # Repartir el presupuesto entre profundidades y padres, evitando gastar todo en el título.
        cupo = min(len(propuestas),max(1,(evaluaciones-len(historial))//max(1,profundidad-paso)))
        rng.shuffle(propuestas)
        nuevos = []
        for entrada,acciones in propuestas[:cupo]:
            resultado = evaluar(entrada,len(historial))
            historial.append(dict(acciones=list(acciones),fotogramas=len(entrada),**resultado))
            if not resultado.get('error'):
                nuevos.append(Candidato(entrada,acciones,resultado))
        if not nuevos:
            break
        nuevos.sort(key=lambda c:(c.evaluacion['puntuacion'],len(c.entrada)),reverse=True)
        ganadores += nuevos
        cola = [(c.entrada,c.acciones) for c in nuevos[:ancho]]
        if len(historial)>=evaluaciones:
            break
    if not ganadores:
        raise RuntimeError('Ningún recorrido produjo capturas válidas')
    mejor = max(ganadores,key=lambda c:(c.evaluacion['puntuacion'],len(c.entrada)))
    return mejor,historial


class EvaluadorMesen:
    def __init__(self,rom,salida,intervalo,perfil=None):
        self.rom = pathlib.Path(rom).resolve()
        self.salida = pathlib.Path(salida).resolve()
        self.intervalo = intervalo
        self.perfil = perfil
        self.objetivos_sha256=v2.huellas_objetivos(perfil,sha(self.rom)) if perfil else {}

    def __call__(self,entrada,numero):
        d = self.salida/f'intento_{numero:04d}'
        d.mkdir(parents=True,exist_ok=True)
        # Separación del primer byte de encendido igual que en la exportación FM2.
        pelicula = d/'entrada.bin'
        pelicula.write_bytes(b'\0'+entrada)
        shots = sorted(set(range(self.intervalo,len(entrada)+1,self.intervalo)) | {len(entrada)})
        referencia.CASA = self.salida/'casa'
        try:
            ref = referencia.generar(self.rom,'',shots,len(entrada),d,entrada=pelicula,desfase=1)
            capturas = sorted(d.glob('f*.png'))
            if len(capturas)!=len(shots):
                raise RuntimeError(f'Capturas incompletas: {len(capturas)}/{len(shots)}')
            polls = [tuple(map(int,l.split())) for l in (d/'polls.txt').read_text().splitlines()]
            if not polls:
                raise RuntimeError('La ROM no produjo lecturas de mando')
            premio = v2.analizar(capturas,self.perfil) if self.perfil else puntuar(capturas)
            if not premio['estados_visuales']:
                raise RuntimeError('Todas las capturas son visualmente vacías')
            hashes = {}
            for p in capturas:
                with Image.open(p) as imagen:
                    hashes[p.name] = hashlib.sha256(imagen.convert('RGB').tobytes()).hexdigest()
            return dict(**premio,directorio=str(d),p0=ref['p0'],
                        polls_sha256=sha(d/'polls.txt'),hashes_capturas=hashes,
                        capturas=[str(p) for p in capturas])
        except Exception as e:
            return dict(error=str(e),directorio=str(d))


def explorar(a):
    rom = a.rom.resolve()
    revision = memoria_n8.revisar(rom)
    if not revision['admitida'] or not cobertura.compatible_ntsc(rom):
        raise ValueError(f'ROM no admitida: {revision["errores"]}; se requiere NTSC/multirregión')
    clasificacion=clasificar(rom)
    if clasificacion.get('dispositivo'):
        raise ValueError(f"Revisar modo de entrada antes de automatizar: la cabecera declara {clasificacion['dispositivo']}")
    nombre_perfil=clasificacion['perfil'] if a.perfil=='auto' else a.perfil
    perfil = cargar_perfil(nombre_perfil,a.perfiles,rom,getattr(a,'juegos',JUEGOS))
    salida = a.out.resolve()
    if salida.exists() and any(salida.iterdir()):
        raise ValueError('La salida debe estar vacía; usar otra carpeta')
    salida.mkdir(parents=True,exist_ok=True)
    evaluar = EvaluadorMesen(rom,salida,a.cada,perfil)
    def observar(entrada,n):
        r = evaluar(entrada,n)
        print(json.dumps(dict(intento=n+1,fotogramas=len(entrada),**r),ensure_ascii=False),flush=True)
        return r
    archivo={}
    if getattr(a,'motor','archivo')=='archivo':
        def conservar(historial,celdas):
            # Evidencia parcial en disco aunque se interrumpa el juego; no sustituye la verificación.
            guardar_json(salida/'historial.json',historial)
            estado={k:dict(acciones=list(r.acciones),fotogramas=len(r.entrada),visitas=r.visitas,
                fallos=r.fallos,acciones_probadas=sorted(r.probadas),evaluacion=r.evaluacion)
                for k,r in celdas.items()}
            guardar_json(salida/'archivo_estados.json',estado)
        mejor,historial,archivo=v2.buscar_archivo(perfil,observar,inicio,bloque,seed=a.seed,
            evaluaciones=a.evaluaciones,profundidad=a.profundidad,ancho=getattr(a,'archivo_max',128),
            fotogramas_bloque=a.bloque,conservar=conservar)
    else:
        mejor,historial = buscar(perfil,observar,seed=a.seed,evaluaciones=a.evaluaciones,
                                profundidad=a.profundidad,ancho=a.ancho,fotogramas_bloque=a.bloque)
    escribir_fm2(salida/'recorrido.fm2',rom,mejor.entrada)
    guardar_json(salida/'historial.json',historial)
    datos = dict(rom=str(rom),rom_sha256=sha(rom),rom_checksum_fm2=tas.md5_rom(rom),
                 mapper=revision['cabecera']['mapper'],revision_memoria=revision,perfil=nombre_perfil,
                 clasificacion=clasificacion,perfil_configurado=perfil,perfiles_archivo=str(a.perfiles.resolve()),
                 perfil_sha256=sha(a.perfiles),seed=a.seed,fotogramas=len(mejor.entrada),
                 explorador_sha256=sha(__file__),motor_sha256=sha(v2.__file__),
                 objetivos_sha256=evaluar.objetivos_sha256,
                 parametros_busqueda=parametros(a),
                 pelicula=str(salida/'recorrido.fm2'),pelicula_sha256=sha(salida/'recorrido.fm2'),
                 desfase=1,cada=a.cada,acciones=list(mejor.acciones),evaluacion=mejor.evaluacion,
                 mesen_sha256=sha(referencia.MESEN),ajustes_sha256=sha(referencia.AJUSTES),
                 lua_sha256=sha(referencia.LUA),repeticion_identica=None,
                 nivel_completado=mejor.evaluacion.get('nivel_completado'),
                 juego_completado=mejor.evaluacion.get('juego_completado'),
                 solo_arranque=(getattr(a,'motor','archivo')=='archivo' and len(mejor.acciones)==1),
                 estado='Explorado; pendiente de repetir en emulador y comparar en consola')
    # Rutas alternativas a celdas distintas; cada una tiene su propia verificación pendiente.
    candidatas=[mejor]+sorted(archivo.values(),key=lambda r:r.evaluacion['puntuacion'],reverse=True)
    elegidas=[]
    entradas_vistas=set()
    celdas_vistas=set()
    for candidato in candidatas:
        digest=hashlib.sha256(candidato.entrada).hexdigest()
        celda=candidato.evaluacion.get('celda_archivo')
        if digest in entradas_vistas or (celda and celda in celdas_vistas):continue
        entradas_vistas.add(digest)
        if celda:celdas_vistas.add(celda)
        if len(elegidas)>=getattr(a,'rutas',3):break
        d=salida/'rutas'/f'{len(elegidas)+1:02d}'
        d.mkdir(parents=True,exist_ok=True)
        escribir_fm2(d/'recorrido.fm2',rom,candidato.entrada)
        registro=dict(datos,pelicula=str(d/'recorrido.fm2'),pelicula_sha256=sha(d/'recorrido.fm2'),
            fotogramas=len(candidato.entrada),acciones=list(candidato.acciones),evaluacion=candidato.evaluacion,
            nivel_completado=candidato.evaluacion.get('nivel_completado'),
            juego_completado=candidato.evaluacion.get('juego_completado'))
        registro['solo_arranque']=(getattr(a,'motor','archivo')=='archivo' and len(candidato.acciones)==1)
        guardar_json(d/'recorrido.json',registro)
        elegidas.append(dict(directorio=str(d),celda=celda,fotogramas=len(candidato.entrada),repeticion_identica=None))
    datos['rutas_alternativas']=elegidas
    guardar_json(salida/'recorrido.json',datos)
    print(salida/'recorrido.fm2')


def verificar(a):
    salida = a.recorrido.resolve()
    datos = json.loads((salida/'recorrido.json').read_text())
    for ruta,esperado in [(datos['rom'],datos['rom_sha256']),
                          (datos['pelicula'],datos['pelicula_sha256']),
                          (referencia.MESEN,datos['mesen_sha256']),
                          (referencia.AJUSTES,datos['ajustes_sha256']),
                          (referencia.LUA,datos['lua_sha256']),
                          (__file__,datos['explorador_sha256'])]:
        if sha(ruta)!=esperado:
            raise ValueError(f'Cambió un archivo desde la exploración: {ruta}')
    extras=dict(datos.get('objetivos_sha256',{}))
    if datos.get('motor_sha256'):extras[str(pathlib.Path(v2.__file__).resolve())]=datos['motor_sha256']
    if datos.get('perfiles_archivo'):extras[datos['perfiles_archivo']]=datos['perfil_sha256']
    config=datos.get('perfil_configurado',{})
    if config.get('_juegos_archivo'):extras[config['_juegos_archivo']]=config['_juegos_sha256']
    for ruta,esperado in extras.items():
        if sha(ruta)!=esperado:raise ValueError(f'Cambió el motor, perfil u objetivo: {ruta}')
    cab,entrada,ordenes = tas.leer_fm2(datos['pelicula'])
    if not entrada or cab['romChecksum']!=tas.md5_rom(datos['rom']) or entrada[0]!=0 or ordenes[0]!=2 or any(ordenes[1:]):
        raise ValueError('Película incompatible con el recorrido registrado')
    # Una repetición nueva nunca acepta las capturas guardadas de un intento anterior.
    nueva = pathlib.Path(tempfile.mkdtemp(prefix='repeticion_',dir=salida))
    evaluar = (EvaluadorMesen(datos['rom'],nueva,datos['cada'],datos['perfil_configurado'])
               if datos.get('perfil_configurado') else EvaluadorMesen(datos['rom'],nueva,datos['cada']))
    r = evaluar(bytes(entrada[1:]),0)
    iguales = (not r.get('error') and r['hashes_capturas']==datos['evaluacion']['hashes_capturas']
               and r['polls_sha256']==datos['evaluacion']['polls_sha256'] and r['p0']==datos['evaluacion']['p0'])
    datos.update(repeticion_identica=bool(iguales),repeticion=r,
                 estado='Repetición idéntica en emulador; pendiente de consola' if iguales else 'No reproduce las capturas registradas')
    guardar_json(salida/'recorrido.json',datos)
    print(datos['estado'])
    if not iguales:
        raise SystemExit(1)


def plan(a):
    seleccion = json.loads(a.seleccion.read_text())['seleccion']
    partidas = json.loads(a.partidas.read_text())
    rutas = {pathlib.Path(r['rom']).name:r['rom'] for r in partidas}
    tareas = []
    for r in seleccion:
        path = rutas.get(r['juego'])
        if not path:
            raise ValueError(f'No se encuentra la ruta medida de {r["juego"]}')
        genero=clasificar(path)
        tareas.append(dict(mapper=r['mapper'],rom=path,perfil=genero['perfil'],clasificacion=genero,
                           estado=genero['estado'],
                           out=f"{r['mapper']:03d}_{hashlib.sha256(path.encode()).hexdigest()[:10]}"))
    a.out.parent.mkdir(parents=True,exist_ok=True)
    guardar_json(a.out,dict(tareas=tareas,ejecutadas=0))
    resumen={}
    for tarea in tareas:resumen[tarea['perfil']]=resumen.get(tarea['perfil'],0)+1
    md=['# Plan del bot por género', '',
        'Asignación orientativa mediante reglas locales por título. No se infiere el género '
        'a partir del mapper y no se han confirmado controles, niveles ni victorias. '
        'Los periféricos se detectan por la cabecera NES 2.0 y no se ejecutan con este bot de mando estándar.', '',
        '| Perfil | ROMs |','| --- | --- |']
    md += [f'| {n} | {v} |' for n,v in sorted(resumen.items())]
    md += ['', '| Mapper | ROM | Perfil sugerido | Motivo/estado |','| --- | --- | --- | --- |']
    for t in tareas:
        c=t['clasificacion']
        motivo=c['dispositivo'] or c['fuente']
        md.append(f"| {t['mapper']} | {pathlib.Path(t['rom']).name} | {t['perfil']} | {motivo} |")
    a.out.with_suffix('.md').write_text('\n'.join(md)+'\n')
    print(f'{len(tareas)} tareas preparadas; no se ejecutó ningún emulador ni hardware.')


def lote(a):
    tareas = json.loads(a.plan.read_text())['tareas']
    salida = a.out.resolve()
    salida.mkdir(parents=True,exist_ok=True)
    ruta = salida/'lote.json'
    estado = json.loads(ruta.read_text()) if ruta.exists() else dict(plan_sha256=sha(a.plan),resultados=[])
    if estado['plan_sha256']!=sha(a.plan):
        raise ValueError('Cambió el plan; usar otra carpeta para la tanda')
    def guardar():
        temporal = ruta.with_suffix('.tmp')
        temporal.write_text(json.dumps(estado,ensure_ascii=False,indent=1)+'\n')
        temporal.replace(ruta)
    estado['estado'] = 'En curso'
    guardar()
    intentadas = 0
    try:
        for tarea in tareas:
            if intentadas>=a.limite:
                break
            previas = [r for r in estado['resultados'] if r['rom']==tarea['rom']]
            if not a.reintentar_fallidas and previas and not previas[-1].get('repeticion_identica'):
                continue
            perfil = (clasificar(tarea['rom'])['perfil'] if a.perfil=='auto' else a.perfil or tarea['perfil'])
            config = parametros(a)
            terminadas = [r for r in estado['resultados'] if r['rom']==tarea['rom'] and r.get('repeticion_identica')]
            reutilizada = False
            for r in reversed(terminadas):
                try:
                    d = json.loads((pathlib.Path(r['directorio'])/'recorrido.json').read_text())
                    reutilizada = (d['rom_sha256']==sha(tarea['rom']) and d['perfil']==perfil
                        and d['perfil_sha256']==sha(a.perfiles) and d['seed']==a.seed
                        and d['parametros_busqueda']==config
                        and d['mesen_sha256']==sha(referencia.MESEN)
                        and d['ajustes_sha256']==sha(referencia.AJUSTES)
                        and d['lua_sha256']==sha(referencia.LUA)
                        and d['explorador_sha256']==sha(__file__)
                        and d.get('motor_sha256')==sha(v2.__file__)
                        and d.get('perfil_configurado',{}).get('_juegos_sha256')==
                            cargar_perfil(perfil,a.perfiles,tarea['rom'],getattr(a,'juegos',JUEGOS)).get('_juegos_sha256')
                        and d.get('objetivos_sha256',{})==v2.huellas_objetivos(
                            cargar_perfil(perfil,a.perfiles,tarea['rom'],getattr(a,'juegos',JUEGOS)),sha(tarea['rom']))
                        and d['pelicula_sha256']==sha(d['pelicula']))
                    if reutilizada:
                        break
                except (OSError,KeyError,ValueError,TypeError):
                    pass
            if reutilizada:
                continue
            intentadas += 1
            directorio = salida/tarea['out']/f'sesion_{time.time_ns()}'
            opciones = argparse.Namespace(**vars(a))
            opciones.rom = pathlib.Path(tarea['rom'])
            opciones.out = directorio
            opciones.perfil = perfil
            registro = dict(rom=tarea['rom'],mapper=tarea['mapper'],directorio=str(directorio),perfil=perfil)
            try:
                explorar(opciones)
                verificar(argparse.Namespace(recorrido=directorio))
                registro.update(estado='Repetición idéntica; pendiente de consola',repeticion_identica=True)
            except (Exception,SystemExit) as e:
                registro.update(estado='Fallida o no determinista',error=str(e),repeticion_identica=False)
            estado['resultados'].append(registro)
            guardar()
        estado['estado'] = 'Presupuesto de esta tanda terminado'
    except KeyboardInterrupt:
        estado['estado'] = 'Interrumpida; se conservan los resultados terminados'
        raise
    finally:
        guardar()
    print(ruta)


def main():
    ap = argparse.ArgumentParser(description=__doc__,formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest='accion',required=True)
    p = sub.add_parser('plan',help='prepara el listado de las 204 ROMs; no ejecuta Mesen')
    base = AQUI.parent/'n8sim/cobertura/completa'
    p.add_argument('--seleccion',type=pathlib.Path,default=base/'seleccion_juegos.json')
    p.add_argument('--partidas',type=pathlib.Path,default=base/'ntsc_revisada/partidas.json')
    p.add_argument('--out',type=pathlib.Path,default=AQUI/'datos/plan_explorador.json')
    p.set_defaults(func=plan)
    p = sub.add_parser('explorar',help='ejecuta Mesen2 para buscar un recorrido y exportarlo')
    p.add_argument('--rom',type=pathlib.Path,required=True)
    p.add_argument('--out',type=pathlib.Path,required=True)
    p.add_argument('--perfiles',type=pathlib.Path,default=PERFILES)
    p.add_argument('--juegos',type=pathlib.Path,default=JUEGOS)
    p.add_argument('--perfil',default='auto')
    p.add_argument('--seed',type=int,default=7)
    p.add_argument('--evaluaciones',type=int,default=48)
    p.add_argument('--profundidad',type=int,default=16)
    p.add_argument('--ancho',type=int,default=2)
    p.add_argument('--bloque',type=int,default=90)
    p.add_argument('--cada',type=int,default=60)
    p.add_argument('--motor',choices=['archivo','haz'],default='archivo')
    p.add_argument('--archivo-max',type=int,default=128)
    p.add_argument('--rutas',type=int,default=3)
    p.set_defaults(func=explorar)
    p = sub.add_parser('verificar',help='repite el recorrido desde encendido en Mesen2')
    p.add_argument('recorrido',type=pathlib.Path)
    p.set_defaults(func=verificar)
    p = sub.add_parser('lote',help='explora y repite automáticamente los juegos de un plan, sin hardware')
    p.add_argument('--plan',type=pathlib.Path,default=AQUI/'datos/plan_explorador.json')
    p.add_argument('--out',type=pathlib.Path,required=True)
    p.add_argument('--limite',type=int,default=3,help='máximo de juegos nuevos por invocación')
    p.add_argument('--reintentar-fallidas',action='store_true',help='volver a intentar juegos fallidos de esta tanda')
    p.add_argument('--perfiles',type=pathlib.Path,default=PERFILES)
    p.add_argument('--juegos',type=pathlib.Path,default=JUEGOS)
    p.add_argument('--perfil',default=None,help='si se omite usa el perfil de cada tarea')
    p.add_argument('--seed',type=int,default=7)
    p.add_argument('--evaluaciones',type=int,default=48)
    p.add_argument('--profundidad',type=int,default=16)
    p.add_argument('--ancho',type=int,default=2)
    p.add_argument('--bloque',type=int,default=90)
    p.add_argument('--cada',type=int,default=60)
    p.add_argument('--motor',choices=['archivo','haz'],default='archivo')
    p.add_argument('--archivo-max',type=int,default=128)
    p.add_argument('--rutas',type=int,default=3)
    p.set_defaults(func=lote)
    a = ap.parse_args()
    if a.accion in ('explorar','lote') and not (1<=a.evaluaciones<=1000 and 1<=a.profundidad<=100
        and 1<=a.ancho<=16 and 1<=a.bloque<=600 and 1<=a.cada<=600):
        ap.error('Presupuesto o duración fuera de los límites admitidos')
    if a.accion in ('explorar','lote') and not (1<=a.archivo_max<=2048 and 1<=a.rutas<=16):
        ap.error('Límites del archivo o cantidad de rutas fuera de rango')
    if a.accion=='lote' and not 1<=a.limite<=10000:
        ap.error('El límite de juegos debe ser positivo y no mayor que 10000')
    a.func(a)


if __name__=='__main__':
    main()
