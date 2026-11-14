"""Exploración por archivo de celdas visuales y objetivos configurados por ROM.

Inspirado en conservar/volver/explorar de Go-Explore; no es su implementación
completa ni un modelo de aprendizaje entrenado. Cada retorno reproduce botones
desde encendido, sin savestates ni acceso a la RAM del juego.
"""
import dataclasses
import hashlib
import pathlib
import random

import numpy as np
from PIL import Image, ImageStat


def descriptores(capturas, perfil):
    vision=perfil.get('vision',{})
    roi=tuple(vision.get('roi',[0,40,256,240]))
    ventana=vision.get('ventana_temporal',3)
    if ventana not in (1,3,5):
        raise ValueError('Ventana temporal admitida: 1, 3 o 5 capturas')
    imagenes=[]
    vacias=[]
    for ruta in capturas:
        with Image.open(ruta) as im:
            if im.size!=(256,240):raise ValueError('Captura NES de tamaño inesperado')
            gris=im.convert('L').crop(roi)
            vacias.append(ImageStat.Stat(gris).stddev[0]<2)
            imagenes.append(np.asarray(gris.resize((16,12),Image.Resampling.BOX),dtype=np.uint8)//32)
    tokens=[]
    for n in range(len(imagenes)):
        # Mediana causal: reduce variaciones de un solo muestreo; no elimina todo el parpadeo NES.
        mediana=np.median(imagenes[max(0,n-ventana+1):n+1],axis=0).astype(np.uint8)
        tokens.append(mediana.tobytes())
    return tokens,vacias


def agrupar(tokens, tolerancia=.12):
    """Agrupa imágenes cercanas por distancia media de sus 192 muestras cuantizadas."""
    centros=[]
    ids=[]
    for token in tokens:
        arr=np.frombuffer(token,dtype=np.uint8).astype(np.int16)
        cerca=next((n for n,c in enumerate(centros) if float(np.mean(np.abs(arr-c)))<=tolerancia),None)
        if cerca is None:
            cerca=len(centros)
            centros.append(arr)
        ids.append(cerca)
    return ids


def huellas_objetivos(perfil,rom_sha256):
    out={}
    nombres=set()
    for objetivo in perfil.get('objetivos',[]):
        if not isinstance(objetivo.get('nombre'),str) or not objetivo['nombre'] or objetivo['nombre'] in nombres:
            raise ValueError('Los objetivos requieren nombres únicos y no vacíos')
        nombres.add(objetivo['nombre'])
        if objetivo.get('rom_sha256')!=rom_sha256:
            raise ValueError('Los objetivos visuales deben declarar el SHA256 exacto de esta ROM')
        if objetivo.get('tipo') not in ('nivel','juego','muerte','menu'):
            raise ValueError('Tipo de objetivo desconocido')
        if not isinstance(objetivo.get('consecutivas',2),int) or not 2<=objetivo.get('consecutivas',2)<=100:
            raise ValueError('Un objetivo requiere al menos dos capturas consecutivas')
        limite=objetivo.get('error_maximo',.01)
        if not 0<=limite<=.1:raise ValueError('Umbral de plantilla fuera de rango')
        roi=objetivo.get('roi')
        if not roi or len(roi)!=4 or not (0<=roi[0]<roi[2]<=256 and 0<=roi[1]<roi[3]<=240):
            raise ValueError('ROI inválida en objetivo')
        ruta=(pathlib.Path(perfil.get('_directorio','.'))/objetivo['plantilla']).resolve()
        with Image.open(ruta) as im:
            if im.size!=(roi[2]-roi[0],roi[3]-roi[1]) or im.width*im.height<256:
                raise ValueError('Plantilla de objetivo incompatible con la ROI o demasiado pequeña')
            if max(ImageStat.Stat(im.convert('RGB')).stddev)<2:
                raise ValueError('Una plantilla uniforme no confirma un objetivo')
        out[str(ruta)]=hashlib.sha256(ruta.read_bytes()).hexdigest()
    return out


def objetivos_visuales(capturas,perfil):
    encontrados=[]
    for objetivo in perfil.get('objetivos',[]):
        ruta=pathlib.Path(perfil.get('_directorio','.'))/objetivo['plantilla']
        with Image.open(ruta) as im:plantilla=np.asarray(im.convert('RGB'),dtype=np.int16)
        seguidas=0
        for captura in capturas:
            with Image.open(captura) as im:region=np.asarray(im.convert('RGB').crop(objetivo['roi']),dtype=np.int16)
            error=float(np.mean(np.abs(region-plantilla)))/255
            seguidas=seguidas+1 if error<=objetivo.get('error_maximo',.01) else 0
            if seguidas>=objetivo.get('consecutivas',2):
                encontrados.append(dict(nombre=objetivo['nombre'],tipo=objetivo['tipo'],
                    captura=str(captura),evidencia='Plantilla visual configurada para la ROM',error=error))
                break
    return encontrados


def analizar(capturas,perfil):
    tokens,vacias=descriptores(capturas,perfil)
    # El análisis se centra en el tramo posterior al arranque, no premia su logo en cada intento.
    arranque=perfil.get('arranque_fotogramas',240)
    indices=[]
    for n,ruta in enumerate(capturas):
        nombre=pathlib.Path(ruta).stem
        frame=int(nombre[1:]) if nombre.startswith('f') and nombre[1:].isdigit() else n
        if frame>=arranque:indices.append(n)
    if not indices:indices=list(range(len(tokens)))
    utiles=[tokens[n] for n in indices if not vacias[n]]
    ids=agrupar(utiles,perfil.get('vision',{}).get('tolerancia_celda',.12))
    secuencia=[]
    for celda in ids:
        if not secuencia or celda!=secuencia[-1]:secuencia.append(celda)
    bucles=sum(secuencia[n] in secuencia[max(0,n-6):n] for n in range(1,len(secuencia)))
    proporcion=bucles/max(1,len(secuencia)-1)
    quieto=len(ids)>=3 and len(set(ids[-3:]))==1
    objetivos=objetivos_visuales(capturas,perfil)
    # Menú/muerte solo se afirman con una plantilla vinculada a esta ROM.
    muertes=sum(o['tipo']=='muerte' for o in objetivos)
    hitos=sum(o['tipo'] in ('nivel','juego') for o in objetivos)
    blancos=sum(vacias[n] for n in indices)
    puntos=len(set(ids))+.1*len(secuencia)-3*proporcion-2*quieto-2*blancos+20*hitos-8*muertes
    ultimo=next((tokens[n] for n in reversed(indices) if not vacias[n]),None)
    return dict(puntuacion=float(puntos),estados_visuales=len(set(ids)),cambios=max(0,len(secuencia)-1),
                capturas_vacias=blancos,estancamiento_visual=quieto,proporcion_bucles=proporcion,
                descriptor_final=ultimo.hex() if ultimo else None,
                celdas_visuales=[hashlib.sha256(t).hexdigest()[:16] for t in utiles],
                objetivos_confirmados=objetivos,
                nivel_completado=True if any(o['tipo']=='nivel' for o in objetivos) else None,
                juego_completado=True if any(o['tipo']=='juego' for o in objetivos) else None)


@dataclasses.dataclass
class Ruta:
    entrada: bytes
    acciones: tuple
    evaluacion: dict
    profundidad: int=0
    visitas: int=0
    probadas: set=dataclasses.field(default_factory=set)
    fallos: int=0


def variantes_inicio(perfil,inicio):
    variantes=[('inicio',inicio(perfil))]
    for v in perfil.get('variantes_arranque',[]):
        alternativa=dict(perfil,arranque=v['arranque'],arranque_fotogramas=v.get('fotogramas',perfil['arranque_fotogramas']))
        variantes.append((v['nombre'],inicio(alternativa)))
    vistos=set()
    unicas=[]
    for nombre,entrada in variantes:
        if entrada not in vistos:
            vistos.add(entrada)
            unicas.append((nombre,entrada))
    return unicas


def buscar_archivo(perfil,evaluar,inicio,bloque,*,seed=7,evaluaciones=48,profundidad=16,
                   ancho=128,fotogramas_bloque=90,conservar=None):
    """Archivo acotado de rutas desde encendido; rescata ramas antiguas al estancarse."""
    rng=random.Random(seed)
    archivo={}
    historial=[]
    mejor=None
    sin_novedad=0
    tolerancia=perfil.get('vision',{}).get('tolerancia_celda',.12)
    maxframes=max(len(b) for _,b in variantes_inicio(perfil,inicio))+profundidad*fotogramas_bloque
    def clave_de(r):
        descriptor=r.get('descriptor_final')
        if descriptor:
            a=np.frombuffer(bytes.fromhex(descriptor),dtype=np.uint8).astype(np.int16)
            for clave,ruta in archivo.items():
                d=ruta.evaluacion.get('descriptor_final')
                if d:
                    b=np.frombuffer(bytes.fromhex(d),dtype=np.uint8).astype(np.int16)
                    if a.shape==b.shape and float(np.mean(np.abs(a-b)))<=tolerancia:return clave
            return hashlib.sha256(bytes.fromhex(descriptor)).hexdigest()[:16]
        return r.get('celda_final') or hashlib.sha256(str(r.get('puntuacion')).encode()).hexdigest()[:16]
    def evaluar_ruta(entrada,acciones,depth,padre=None):
        nonlocal mejor,sin_novedad
        r=dict(evaluar(entrada,len(historial)))
        ruta=Ruta(entrada,acciones,r,depth)
        if padre:padre.visitas+=1
        if not r.get('error'):
            clave=clave_de(r)
            nueva=clave not in archivo
            r['celda_archivo']=clave
            r['celda_nueva']=nueva
            sin_novedad=0 if nueva else sin_novedad+1
            anterior=archivo.get(clave)
            # Conservar el camino corto sin perder los intentos agotados de esa celda.
            if nueva or len(entrada)<len(anterior.entrada):
                if anterior:ruta.probadas=set(anterior.probadas);ruta.visitas=anterior.visitas; ruta.fallos=anterior.fallos
                archivo[clave]=ruta
            if mejor is None or (r['puntuacion'],-len(entrada))>(mejor.evaluacion['puntuacion'],-len(mejor.entrada)):
                mejor=ruta
            if len(archivo)>ancho:
                candidatas=[k for k in archivo if archivo[k] is not mejor]
                victima=min(candidatas,key=lambda k:(archivo[k].evaluacion['puntuacion']-archivo[k].visitas*.1))
                del archivo[victima]
        else:
            sin_novedad+=1
            if padre:padre.fallos+=1
        historial.append(dict(acciones=list(acciones),fotogramas=len(entrada),profundidad=depth,**r))
        if conservar:conservar(historial,archivo)
    # Explorar varios arranques permite encontrar menús que necesitan A además de Start.
    for nombre,entrada in variantes_inicio(perfil,inicio):
        if len(historial)>=evaluaciones:break
        evaluar_ruta(entrada,(nombre,),0)
    while len(historial)<evaluaciones:
        opciones=[]
        for clave,ruta in archivo.items():
            if ruta.profundidad>=profundidad:continue
            estancada=ruta.evaluacion.get('estancamiento_visual') or ruta.evaluacion.get('proporcion_bucles',0)>.5
            for nombre,accion in perfil['acciones'].items():
                fase=accion.get('fase','juego')
                if fase=='menu' and ruta.profundidad>2 and not estancada and sin_novedad<6:continue
                if fase=='recuperacion' and not estancada and sin_novedad<4:continue
                for factor in perfil.get('escalas_duracion',[.5,1,2]):
                    duracion=max(1,round(fotogramas_bloque*factor))
                    intento=(nombre,duracion)
                    if intento not in ruta.probadas and len(ruta.entrada)+duracion<=maxframes:
                        opciones.append((clave,intento))
        if not opciones:break
        # Retorno explícito a una celda, después una acción no probada. Visitas y fallos reducen su peso.
        pesos=[]
        for clave,_ in opciones:
            ruta=archivo[clave]
            hitos=sum(o['tipo'] in ('nivel','juego') for o in ruta.evaluacion.get('objetivos_confirmados',[]))
            pesos.append((1+min(3,ruta.profundidad*.15)+hitos*2)/(1+ruta.visitas+ruta.fallos*2))
        clave,(nombre,duracion)=rng.choices(opciones,weights=pesos,k=1)[0]
        padre=archivo[clave]
        padre.probadas.add((nombre,duracion))
        entrada=padre.entrada+bloque(perfil['acciones'][nombre],duracion)
        evaluar_ruta(entrada,padre.acciones+(f'{nombre}@{duracion}',),padre.profundidad+1,padre)
    if mejor is None:raise RuntimeError('No se obtuvo ninguna ruta visual válida')
    return mejor,historial,archivo
