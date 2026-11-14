#!/usr/bin/env python3
"""Control visual local de la NES. Perfil inicial: SMB, experimental.

No lee RAM ni modifica la ROM. Decisiones con vídeo 256x240; Nano por serie.
  python3 -I tools/consola/controlador.py --segundos 180
  python3 -I tools/consola/controlador.py --imagen foto.png
"""
import argparse
import dataclasses
import datetime
import json
import math
import pathlib
import sys
import time

import numpy as np
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))


def grupos(mask):
    """Componentes de cuatro vecinos; máscaras pequeñas, sin dependencias extra."""
    todo = set(map(tuple, np.argwhere(mask)))
    out = []
    while todo:
        seed = todo.pop()
        stack, pts = [seed], [seed]
        while stack:
            y, x = stack.pop()
            for q in ((y-1, x), (y+1, x), (y, x-1), (y, x+1)):
                if q in todo:
                    todo.remove(q)
                    stack.append(q)
                    pts.append(q)
        ys, xs = zip(*pts)
        out.append(tuple(map(int, (min(xs), min(ys), max(xs)+1, max(ys)+1, len(pts)))))
    return out


def bits(img):
    return np.asarray(img).astype(float).mean(2) > 150


class Marcador:
    def __init__(self, templates=None):
        self.templates = templates or {}

    def digito(self, patch):
        if not self.templates:
            return None
        p = bits(patch)
        scores = sorted((int(np.count_nonzero(p != t)), k) for k, t in self.templates.items())
        if scores[0][0] > 7 or (len(scores) > 1 and scores[1][0] - scores[0][0] < 3):
            return None
        return scores[0][1]

    def nivel(self, img):
        w = self.digito(img[24:32, 152:160])
        a = self.digito(img[24:32, 168:176])
        # El guion central evita interpretar otro texto como un nivel.
        dash = bits(img[24:32, 160:168])
        if w is None or a is None or not 1 <= w <= 8 or not 1 <= a <= 4:
            return None
        if dash.sum() < 5 or dash.sum() > 20:
            return None
        return f'{w}-{a}'

    @classmethod
    def cargar(cls, path):
        data = json.loads(pathlib.Path(path).read_text())
        return cls({int(k): np.array(v, bool) for k, v in data.items()})


@dataclasses.dataclass
class Vista:
    mario: tuple | None
    nivel: str | None
    suelo: bool = False
    hueco: int | None = None
    pared: int | None = None
    enemigo: int | None = None
    tiempo: float | None = None
    vx: float = 0.
    vy: float = 0.
    cierre: dict = dataclasses.field(default_factory=dict)


class Movimiento:
    """Velocidad observada, sumando desplazamiento del sprite y scroll del escenario."""
    def __init__(self):
        self.base = None
        self.vx = self.vy = 0.
        self.cierre = {}

    @staticmethod
    def scroll(antes, ahora, dt):
        # Perfil vertical del escenario, sin HUD y sin el centro ocupado por Mario.
        a = antes[48:232].astype(float).mean((0,2))
        b = ahora[48:232].astype(float).mean((0,2))
        limite = min(14, max(1, int(260*dt)))
        # El escenario solo desplaza a la izquierda en SMB. Bordes y sprite fuera del ajuste.
        xs = np.r_[np.arange(16,90), np.arange(150,238-limite)]
        if np.std(a[xs]) < 3:
            return 0.
        errores = [float(np.mean(np.abs(a[xs+d]-b[xs]))) for d in range(limite+1)]
        d = int(np.argmin(errores))
        if d == 0 or errores[d] > errores[0]*.85:
            return 0.
        # Afinar a fracción de píxel sin forzar una precisión de un píxel por muestra.
        sub = 0.
        if 0 < d < limite:
            den = errores[d-1]-2*errores[d]+errores[d+1]
            if den > .01:
                sub = float(np.clip(.5*(errores[d-1]-errores[d+1])/den, -.5, .5))
        return d+sub

    def actualizar(self, img, v, t):
        if v.mario is None or v.nivel is None:
            self.base = None
            self.vx = self.vy = 0.
            self.cierre = {}
            return
        v.tiempo = t
        if self.base is not None:
            previo, old, t0 = self.base
            dt = t-t0
            if dt < .045:
                v.vx, v.vy, v.cierre = self.vx, self.vy, dict(self.cierre)
                return
            if dt <= .25 and old.nivel == v.nivel:
                dx = (v.mario[0]-old.mario[0]) + self.scroll(previo, img, dt)
                vx = float(np.clip(dx/dt, -220, 260))
                vy = float(np.clip((v.mario[3]-old.mario[3])/dt, -450, 450))
                alpha = 1-math.exp(-dt/.1)
                self.vx += alpha*(vx-self.vx)
                self.vy += alpha*(vy-self.vy)
                for k in ('hueco','pared','enemigo'):
                    antes, despues = getattr(old,k), getattr(v,k)
                    if antes is not None and despues is not None and abs(antes-despues) < 320*dt+4:
                        rate = float(np.clip((antes-despues)/dt, -300, 320))
                        self.cierre[k] = self.cierre.get(k, rate)*(1-alpha)+rate*alpha
                    else:
                        self.cierre.pop(k,None)
            else:
                self.vx = self.vy = 0.
                self.cierre = {}
        v.vx, v.vy, v.cierre = self.vx, self.vy, dict(self.cierre)
        self.base = (img.copy(), dataclasses.replace(v), t)


@dataclasses.dataclass(frozen=True)
class Latencia:
    pulsar: float = 0.
    soltar: float = 0.
    jitter: float = 0.

    @classmethod
    def desde_medicion(cls, data):
        on, off = data['pulsar'], data['soltar']
        values = [on['mediana_s'],off['mediana_s'],on['p90_s'],off['p90_s']]
        if not all(isinstance(v,(float,int)) and math.isfinite(v) and 0 <= v <= .5 for v in values):
            raise ValueError('latencia fuera de rango; repetir latencia.py')
        if on['p90_s'] < on['mediana_s'] or off['p90_s'] < off['mediana_s']:
            raise ValueError('percentiles de latencia incoherentes')
        return cls(on['mediana_s'],off['mediana_s'],
                   max(on['p90_s']-on['mediana_s'], off['p90_s']-off['mediana_s']))


class SMB:
    def __init__(self, marcador=None, latencia=None):
        self.marcador = marcador or Marcador()
        self.ultimo = None
        self.sin_mario = 0
        self.latencia = latencia or Latencia()
        self.movimiento = Movimiento()
        self.fase = 'suelo'
        self.orden_salto = None
        self.a_soltada = None
        self.vio_aire = False
        self.apoyo_desde = None
        self.prediccion = {}

    def ver(self, img, tiempo=None):
        v = self._ver(img)
        if tiempo is not None:
            self.movimiento.actualizar(img, v, tiempo)
        return v

    def _ver(self, img):
        a = np.asarray(img, np.int16)
        r, g, b = a.transpose(2, 0, 1)
        logo = (r[40:112,40:218] > 100) & (g[40:112,40:218] < 100) & (b[40:112,40:218] < 80)
        if logo.mean() > .35:
            return Vista(None, None)  # Título, no confundir su Mario decorativo con juego.
        rojo = (r > 145) & (g < 65) & (b < 70)
        rojo[:40] = False
        rojo[208:] = False
        candidatos = [p for p in grupos(rojo) if 3 <= p[4] <= 180
                      and p[2]-p[0] <= 18 and p[3]-p[1] <= 24]
        if candidatos:
            # Ropa roja, con piel naranja cerca: distingue a Mario de restos sueltos.
            rank = []
            for x0, y0, x1, y1, n in candidatos:
                x = (x0+x1)//2
                lo, hi = max(40, y0-4), min(208, y1+9)
                warm = ((r[lo:hi, max(0,x-9):x+10] > 150)
                        & (g[lo:hi, max(0,x-9):x+10] > 70)
                        & (g[lo:hi, max(0,x-9):x+10] < 170)
                        & (b[lo:hi, max(0,x-9):x+10] < 80))
                if warm.sum() < 3:
                    continue
                continuity = abs(x-self.ultimo[0]) if self.ultimo else abs(x-120)
                rank.append((continuity, -n, (x, y0, y1)))
            if rank:
                x, top, bottom = min(rank)[2]
                # La gorra y la camisa pueden ser componentes separados.
                base = max(40,top-20)
                near = rojo[base:min(208,bottom+12), max(0,x-7):min(256,x+8)]
                rows = np.where(near.any(1))[0]
                top = base + int(rows[0])
                red_bottom = base + int(rows[-1])
                bottom = top + (32 if red_bottom-top > 17 else 16)
                self.ultimo = (x, bottom)
                mario = (x-7, top, x+8, bottom)
            else:
                mario = None
        else:
            mario = None
        nivel = self.marcador.nivel(img)
        if mario is None:
            return Vista(None, nivel)
        x0, y0, x1, foot = mario
        x = (x0+x1)//2
        oscuro = np.median(a[40:60, :40]) < 40
        if oscuro:
            solid = (a.max(2) > 90) & ((b > r+30) | ((r > 65) & (g > 35)))
        else:
            solid = ((r > 70) & (g > 15) & (g < 170) & (b < 105)) | ((g > r+20) & (g > b+20))
        # No usar los píxeles del propio Mario como apoyo.
        solid[max(0,y0):min(240,foot), max(0,x0):min(256,x1)] = False
        below = solid[min(239,foot):min(240,foot+5), max(0,x-5):min(256,x+6)]
        suelo = bool(below.size > 0 and below.mean() > .3)
        # Suelo bajo, para saltar huecos; plataformas altas se tratan como paredes.
        floor = solid[210:230].mean(0) > .25
        hueco = next((d for d in range(0,100) if x+d+5 < 256
                     and not floor[x+d:x+d+5].any()), None)
        pared = next((d for d in range(8,70) if x+d+3 < 256
                      and solid[max(40,foot-12):max(41,foot-4), x+d:x+d+3].mean() > .6), None)
        # Enemigos marrones sobre la línea del suelo. Filtrar bloques/colinas grandes.
        brown = (r > 80) & (r < 150) & (g > 15) & (g < 105) & (b < 85)
        enemy_mask = np.zeros((240,256), bool)
        enemy_mask[max(40,foot-24):208, min(255,x+12):min(256,x+85)] = True
        enemy_mask &= brown
        enemies = [p[0]-x for p in grupos(enemy_mask) if 5 <= p[2]-p[0] <= 23
                   and 5 <= p[3]-p[1] <= 22 and p[4] >= 12]
        return Vista(mario, nivel, suelo, hueco, pared, min(enemies) if enemies else None)

    def decidir(self, v, now):
        if v.mario is None or v.nivel is None:
            self.sin_mario += 1
            self.prediccion = {'valida':False, 'motivo':'sin_personaje_o_marcador'}
            return 0, 'sin_personaje_o_marcador'
        self.sin_mario = 0
        edad = max(0., now-v.tiempo) if v.tiempo is not None else 0.
        horizonte = self.latencia.pulsar + edad
        estimadas, margenes = {}, {}
        for k in ('hueco','pared','enemigo'):
            d = getattr(v,k)
            rate = max(0.,v.cierre.get(k, v.vx))
            estimadas[k] = None if d is None else d-rate*horizonte
            margenes[k] = rate*self.latencia.jitter
        self.prediccion = {'horizonte_s':horizonte, 'jitter_s':self.latencia.jitter,
                           'distancias':estimadas, 'margenes_px':margenes, 'fase':self.fase}
        jump = any(estimadas[k] is not None and estimadas[k] <= lead+margenes[k]
                   for k,lead in [('hueco',38),('pared',35),('enemigo',48)])
        apoyo = v.suelo and abs(v.vy) < 45
        self.apoyo_desde = (self.apoyo_desde if self.apoyo_desde is not None else now) if apoyo else None
        estable = self.apoyo_desde is not None and now-self.apoyo_desde >= .04
        if self.orden_salto is not None:
            transcurrido = now-self.orden_salto
            if not v.suelo or v.vy < -45:
                self.vio_aire = True
                self.fase = 'aire'
            # Soltar A en tiempo de mando, sin esperar a verla soltada en vídeo.
            if transcurrido < .45:
                return 0x83, 'salto_pendiente' if not self.vio_aire else 'salto'
            if self.a_soltada is None:
                self.a_soltada = now
            if estable and now-self.a_soltada >= self.latencia.soltar+self.latencia.jitter+.04:
                # Aterrizaje confirmado, o salto bloqueado: siempre esperar la
                # liberación efectiva de A antes de volver a pulsarla.
                self.orden_salto = None
                self.fase = 'suelo'
            else:
                return 0x82, 'esperar_aterrizaje'
        if estable and jump:
            self.orden_salto = now
            self.a_soltada = None
            self.vio_aire = False
            self.fase = 'pendiente'
            return 0x83, 'iniciar_salto'
        return 0x82, 'avanzar'  # derecha + B


class MandoVigilado:
    """Pulso con vencimiento en el firmware: el host no puede dejar una dirección pegada."""
    def __init__(self, mando, lease_ms=250):
        self.mando = mando
        self.lease = lease_ms
        self.mask = None
        self.enviado = 0.

    def enviar(self, mask, now):
        from mando import nombres
        if mask == 0:
            if self.mask:
                # Misma liberación que se midió en latencia.py: sustituir el
                # pulso por 1 ms del mismo botón, sin esperar otros 250 ms.
                self.mando.orden(f'T {nombres(self.mask)} 1')
            self.mask = 0
            return
        if mask != self.mask or now-self.enviado > self.lease/2000:
            self.mando.orden(f'T {nombres(mask)} {self.lease}')
            self.enviado = now
            self.mask = mask

    def cerrar(self):
        try:
            self.enviar(0, time.monotonic())
        finally:
            # Si falló el puerto, el vencimiento sigue siendo la salvaguarda.
            time.sleep(self.lease/1000 + .02)
            self.mando.fijar(0)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--segundos', type=float, default=180)
    ap.add_argument('--rom', default='PRUEBAS/Super Mario Bros. (World) (HVC-SM).nes')
    ap.add_argument('--en-juego', action='store_true', help='no navegar ni pulsar Start')
    ap.add_argument('--imagen', type=pathlib.Path, help='analizar un PNG sin conectar hardware')
    ap.add_argument('--salida', type=pathlib.Path)
    a = ap.parse_args()
    lat_file = ROOT/'datos/latencia_input.json'
    lat = json.loads(lat_file.read_text()) if lat_file.exists() else None
    try:
        tiempos = Latencia.desde_medicion(lat) if lat else Latencia()
    except (KeyError, ValueError, TypeError) as e:
        ap.error(f'calibración inválida: {e}')
    perfil = SMB(Marcador.cargar(ROOT/'perfiles/smb-digitos.json'), tiempos)
    if a.imagen:
        print(json.dumps(dataclasses.asdict(perfil.ver(np.array(Image.open(a.imagen).convert('RGB'))))))
        return
    if not 0 < a.segundos <= 3600:
        ap.error('--segundos debe estar entre 0 y 3600')
    import prueba
    out = a.salida or ROOT/'informes'/('control-smb-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S'))
    out.mkdir(parents=True, exist_ok=True)
    if lat:
        (out/'latencia_usada.json').write_text(json.dumps(lat, indent=2))
    print(f'Predicción: pulsar {tiempos.pulsar*1000:.1f} ms, soltar {tiempos.soltar*1000:.1f} ms, '
          f'variación {tiempos.jitter*1000:.1f} ms; velocidad visual' if lat
          else 'Sin calibración de input lag: anticipación adicional desactivada', flush=True)
    b = prueba.Banco(prueba.cargar_config(None), salida=out)
    driver = MandoVigilado(b.mando)
    transitions, stable, count, previous = [], None, 0, None
    completed = []
    reason = 'limite_tiempo'
    try:
        b.cap.iniciar(b.cal)
        b.mando.desarmar()
        b.mando.guion('')
        if not a.en_juego:
            prueba.lanzar(b, a.rom, 0, '')
            time.sleep(6)
            b.mando.desarmar()
            b.mando.tocar('start', 150)
            time.sleep(2)
        b.cap.grabar_clip(out/'video.mp4')
        t0, last_log = time.monotonic(), 0.
        last_seen = t0
        with (out/'decisiones.jsonl').open('w', buffering=1) as log:
            while time.monotonic()-t0 < a.segundos:
                frame = b.cap.esperar_nuevo(.2)
                now = time.monotonic()
                if frame is None or now-frame[0] > .25:
                    reason = 'video_interrumpido'
                    break
                v = perfil.ver(frame[1], frame[0])
                now = time.monotonic()  # incluir el tiempo real del análisis de la imagen
                mask, why = perfil.decidir(v, now)
                driver.enviar(mask, now)
                if v.mario is not None:
                    last_seen = now
                if now-last_seen > 15:
                    reason = 'personaje_no_detectado_15s'
                    break
                if v.nivel == previous and v.nivel is not None:
                    count += 1
                else:
                    previous, count = v.nivel, 1
                if count >= 15 and stable != v.nivel:
                    old, stable = stable, v.nivel
                    transitions.append(stable)
                    if old and old.split('-')[0] == stable.split('-')[0] and int(stable[-1]) == int(old[-1])+1:
                        if old not in completed:
                            completed.append(old)
                    Image.fromarray(frame[1]).save(out/f'nivel-{stable}.png')
                    print('NIVEL', stable, 'completados', completed, flush=True)
                if len(completed) >= 3:
                    reason = 'tres_niveles_completos'
                    break
                if now-last_log > .2 or why == 'iniciar_salto':
                    log.write(json.dumps({'s':round(now-t0,3), 'vista':dataclasses.asdict(v),
                                          'botones':mask, 'decision':why,
                                          'prediccion':perfil.prediccion, 'fase':perfil.fase})+'\n')
                    last_log = now
                if int((now-t0)*2) != int((now-t0-.04)*2):
                    Image.fromarray(frame[1]).save(out/'actual.png')
                time.sleep(.025)
        frame = b.cap.ultimo()
        if frame[1] is not None:
            Image.fromarray(frame[1]).save(out/'final.png')
    except KeyboardInterrupt:
        reason = 'interrumpido'
    finally:
        driver.cerrar()
        b.cap.parar_clip()
        (out/'resultado.json').write_text(json.dumps({'motivo':reason, 'niveles_vistos':transitions,
            'niveles_completos':completed, 'perfil':'smb-experimental', 'rom':a.rom,
            'latencia':dataclasses.asdict(tiempos), 'control':'predictivo-v2'}, indent=2))
        b.cerrar()
    print(out, reason, completed, flush=True)


if __name__ == '__main__':
    main()
