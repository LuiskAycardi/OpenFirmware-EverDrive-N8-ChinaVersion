#!/usr/bin/env python3
"""prueba.py — pruebas de los mappers en la consola real, de forma automática.

  python3 -I prueba.py dispositivos            # Nano, capturadora y audio que se ven
  python3 -I prueba.py calibrar                # imagen, mando y retraso con la ROM de calibración
  python3 -I prueba.py referencias             # capturas de Mesen2 de la lista (rápido; se guardan)
  python3 -I prueba.py ejecutar                # la lista de la página de pruebas para --consola nes
  python3 -I prueba.py ejecutar --carpeta "PRUEBAS/4 MMC3" --max 3
  python3 -I prueba.py ejecutar --seco         # todo sin hardware (consola, Nano y capturadora simulados)
  python3 -I prueba.py informe CARPETA         # rehace index.html y resultados_pagina.json

Por cada juego:
  1. vuelve al menú si hace falta (Select+B; si el juego no lee el mando, pide apagar y encender);
  2. navega por el menú del OS v13 hasta la ROM, comprobándolo con capturas;
  3. carga el guion en el Nano, lo arma y pulsa A. El primer LATCH del juego es el fotograma p0 del banco;
  4. graba vídeo y audio y, en cada fotograma de captura, compara la escena con la de Mesen2;
  5. marca negra, basura, distinto o cuelgue, y vuelve al menú.
El informe queda en informes/<fecha>/: index.html, results.json y resultados_pagina.json (para la página
"Pruebas N8": ver README).
"""
import argparse
import datetime
import hashlib
import html
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import time
import unicodedata

import numpy as np

AQUI = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(AQUI))
sys.path.insert(0, str(AQUI / "rom"))
import calibrar  # noqa: E402
import comparar  # noqa: E402
import hacer_rom  # noqa: E402
import menu as menu_mod  # noqa: E402
import referencia  # noqa: E402
import sonido  # noqa: E402
from mando import BOTONES, ErrorMando, Mando, leer_guion  # noqa: E402

FPS = 60.0988
PAGINA = AQUI.parent / "pagina-pruebas"
ROM_CAL = AQUI / "rom" / "calibracion.nes"
DEF = {
    "puerto": None, "video": None, "audio": "auto",
    "sd": "~/SD_Pruebas", "consola": "nes",
    "rom_calibracion": "PRUEBAS/0 Calibracion/calibracion.nes",
    "sensor_5v": False,
    "teclas_menu": {},
    "silencio_arranque_ms": 500,  # OS v13: pausas de hasta ~280 ms al lanzar; la carga del RBF calla ~770 ms (2026-11-11)
    "retraso_video_s": 0.08,
    "ventana_s": 0.35,
    "reset_ms": 5000,
    "reset_boton": True,          # botón RESET con el PC817 en D2 (CONEXION.md); False = solo Select+B
    "ventana": True,             # ventana en vivo con lo que captura la consola (ffplay); --sin-ventana la quita
    "reset_boton_ms": 1000,      # pulsos cortos (300 ms) hacen fallar la carga del OS del N8 (aviso del usuario, 2026-11-11)
}


def log(*a):
    print(time.strftime("%H:%M:%S"), *a, flush=True)


def avisar(texto):
    """Aviso que el usuario no se pierda: campana del terminal y notificación del escritorio si hay."""
    log("⚠ " + texto + "\a")
    if shutil.which("notify-send"):
        subprocess.run(["notify-send", "-u", "critical", "Pruebas N8", texto], check=False)


class Abortar(Exception):
    pass


# ---------------------------------------------------------------- configuración y lista
def cargar_config(ruta):
    cfg = dict(DEF)
    if ruta and pathlib.Path(ruta).exists():
        cfg.update(json.loads(pathlib.Path(ruta).read_text()))
    cfg["sd"] = str(pathlib.Path(os.path.expanduser(cfg["sd"])))
    return cfg


def cargar_guiones():
    return json.loads((AQUI / "guiones.json").read_text())


def plan_pagina():
    """El plan de la página "Pruebas N8", generado con su propio script (ids de los documentos)."""
    d = tempfile.mkdtemp(prefix="plan_")
    r = subprocess.run([sys.executable, "-I", "plan_pruebas.py", d, os.path.join(d, "plan.md")], cwd=PAGINA,
                       capture_output=True, text=True)
    if r.returncode:
        raise RuntimeError(f"plan_pruebas.py falló: {r.stderr[-500:]}")
    plan = json.loads(pathlib.Path(d, "plan.json").read_text())
    shutil.rmtree(d, ignore_errors=True)
    return plan


def fichas(s):
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode().lower()
    s = re.sub(r"\(repetir\)", "", s)
    return [t for t in re.findall(r"[a-z0-9]+", s) if t != "the"]


def carpetas_de(texto, sd):
    pr = pathlib.Path(sd) / "PRUEBAS"
    subs = sorted(d.name for d in pr.iterdir() if d.is_dir())
    if "varias" in texto:
        return ["."] + subs
    out = ["."] if "(raíz)" in texto else []
    for s in subs:
        if re.search(r"(^|[/ ,])" + re.escape(s) + r"($|[ ,)])", texto):
            out.append(s)
    return out


ALIAS = {"tmnt": "teenage mutant ninja turtles"}


def buscar_rom(nombre, carpetas, sd, intento=0):
    """La ROM de la SD que mejor encaja con el nombre de la página. Si no sale, se prueba sin lo que va entre
    paréntesis ("Gauntlet (Tengen)") y, al final, en todas las carpetas."""
    pr = pathlib.Path(sd) / "PRUEBAS"
    n = nombre
    for k, v in ALIAS.items():
        n = re.sub(rf"\b{k}\b", v, n, flags=re.I)
    if intento >= 1:
        n = re.sub(r"\([^)]*\)", "", n)
    t = set(fichas(n))
    if not t:
        return None
    mejor = None
    for c in carpetas:
        d = pr / c if c != "." else pr
        for f in sorted(d.iterdir()):
            if not f.is_file() or f.suffix.lower() != ".nes" or f.name.startswith("._"):
                continue
            base = re.sub(r"^\d{3} ", "", f.stem)
            corto = set(fichas(base.split(" (")[0]))
            todas = set(fichas(base))
            p = len(t & todas) / len(t) - 0.01 * len(corto - t)
            if mejor is None or p > mejor[0]:
                mejor = (p, f)
    if mejor and mejor[0] >= 0.74:
        return str(mejor[1].relative_to(pathlib.Path(sd)))
    if intento == 0:
        return buscar_rom(nombre, carpetas, sd, 1)
    if intento == 1:
        return buscar_rom(nombre, carpetas_de("varias", sd), sd, 2)
    return None


def lista_plan(cfg, consola):
    """[{id, n, tipo, rom_rel | None, motivo}] de la página para esa consola."""
    out = []
    for s in plan_pagina():
        if s["consola"] != consola:
            continue
        base = carpetas_de(s["carpeta"], cfg["sd"])
        for j in s["juegos"]:
            e = {"id": j["id"], "n": j["n"], "m": j["m"], "tipo": j["tipo"], "pila": j["pila"], "seccion": s["titulo"]}
            if "fábrica" in j["n"].lower():
                e["rom_rel"], e["motivo"] = None, "con la SD de fábrica: a mano"
                out.append(e)
                continue
            pista = re.search(r"\(([^()]+)\)\s*$", j["m"])
            carpetas = base
            if pista:
                sub = [c for c in carpetas_de("varias", cfg["sd"]) if c.startswith(pista.group(1) + " ")
                       or c == pista.group(1)]
                carpetas = sub or base
            e["rom_rel"] = buscar_rom(j["n"], carpetas, cfg["sd"])
            e["motivo"] = None if e["rom_rel"] else "no encuentro la ROM en la SD"
            out.append(e)
    return out


def lista_carpeta(cfg, carpeta):
    d = pathlib.Path(cfg["sd"]) / carpeta
    return [{"id": None, "n": f.stem, "m": "", "tipo": "n", "pila": False, "seccion": carpeta,
             "rom_rel": str(f.relative_to(cfg["sd"])), "motivo": None}
            for f in sorted(d.iterdir()) if f.suffix.lower() == ".nes" and not f.name.startswith("._")]


def guion_de(j, guiones, fotogramas=None):
    g = dict(guiones["por_defecto"])
    if j["tipo"] == "b":
        g.update(guiones.get("blargg", {}))
    g.update(guiones.get("por_rom", {}).get(os.path.basename(j["rom_rel"] or ""), {}))
    if fotogramas:
        g["fotogramas"] = fotogramas
        g["shots"] = [s for s in g["shots"] if s <= fotogramas] or [fotogramas]
    leer_guion(g["guion"])
    return g


def dir_ref(rom_rel, g):
    clave = [g["guion"], sorted(g["shots"]), g["fotogramas"]]
    if g.get("entrada"):                                   # película TAS: su contenido y desfase forman parte
        clave += [hashlib.md5(pathlib.Path(g["entrada"]).read_bytes()).hexdigest(), g.get("desfase", 0)]
    h = hashlib.md5(json.dumps(clave).encode()).hexdigest()[:8]
    return AQUI / "refs" / f"{referencia.clave(rom_rel)}__{h}"


# ---------------------------------------------------------------- la sesión: hardware real o simulado
class Banco:
    def __init__(self, cfg, seco=False, salida=None, sim_fallos=None, refs=None):
        self.cfg, self.seco, self.sim = cfg, seco, None
        self.datos = (salida / "datos_seco") if seco else (AQUI / "datos")
        self.datos.mkdir(parents=True, exist_ok=True)
        if seco:
            import simulador
            sd = simulador.sd_simulada(salida / "sd_simulada", cfg["sd"], ROM_CAL)
            cfg["sd"] = str(sd)
            self.sim = simulador.ConsolaSimulada(sd, refs=refs or {}, fallos=sim_fallos or {}, log=log)
            self.mando = Mando(self.sim.puerto, log=log, esperar_hola=1.0)
            self.cap = simulador.CapturaSimulada(self.sim, log=log)
        else:
            import captura
            self.mando = Mando(cfg["puerto"], log=log)
            self.cap = captura.Captura(cfg["video"], cfg["audio"], log=log, ventana=cfg["ventana"])
        self.fuente = menu_mod.Fuente(self.datos / "fuente.json")
        cursor = None
        if (self.datos / "cursor.json").exists():
            cursor = json.loads((self.datos / "cursor.json").read_text())
        self.menu = menu_mod.Menu(cfg["sd"], self.fuente, cursor, cfg["teclas_menu"], log=log)
        self.cal = None
        if (self.datos / "calibracion.json").exists():
            self.cal = calibrar.cargar(self.datos / "calibracion.json")
            self.menu.fase = tuple(self.cal.get("fase_menu", (0, 0)))

    def guardar_aprendido(self):
        self.fuente.guardar()
        if self.menu.cursor:
            (self.datos / "cursor.json").write_text(json.dumps(self.menu.cursor))

    def cerrar(self):
        self.guardar_aprendido()
        for f in (self.cap.cerrar, self.mando.cerrar):
            try:
                f()
            except Exception:  # noqa: BLE001
                pass
        if self.sim:
            self.sim.cerrar()

    def retraso(self):
        return (self.cal or {}).get("retraso_s", self.cfg["retraso_video_s"])

    def mascara(self):
        return calibrar.mascara_visible(self.cal, 2) if self.cal else None


# ---------------------------------------------------------------- volver al menú
def en_menu(b, intentos=2):
    """La lectura del menú, o None. Exige 2 entradas reconocidas y la elegida (salvo carpetas de una sola entrada):
    con una sola coincidencia, el título de Punch-Out!! pasaba por el menú (2026-11-11)."""
    lec, _ = b.menu.ver(b.cap, intentos=intentos)
    if lec is None or lec.carpeta is None or lec.seleccion is None:
        return None
    unicas = {r for _, r, _ in b.menu.carpetas()[lec.carpeta] if r != ".."}
    if lec.puntos < 2 and len(unicas) > 1:
        return None
    return lec


def apagar_a_mano(b, motivo):
    avisar(f"APAGA Y ENCIENDE LA CONSOLA ({motivo}). Sigo solo cuando vea el menú.")
    if b.sim:
        b.sim.apagar_encender()
    if b.cfg["sensor_5v"]:
        t0 = time.monotonic()
        while b.mando.estado().get("v5", 1) == 1 and time.monotonic() - t0 < 900:
            time.sleep(0.5)
    t0 = time.monotonic()
    while time.monotonic() - t0 < 1800:
        lec = en_menu(b, 1)
        if lec:
            log("menú de nuevo: sigo")
            return lec
        time.sleep(2)
    raise Abortar("la consola no ha vuelto al menú en 30 minutos")


def reset_boton(b, res=None):
    """Botón RESET por el PC817. Devuelve la lectura del menú si vuelve a él (o None)."""
    if not b.cfg["reset_boton"]:
        return None
    r = b.mando.reset_boton(b.cfg["reset_boton_ms"])
    if res is not None:
        res["reset"] = dict(r, boton=1)
    lec = en_menu(b, 4)
    if not lec and res is not None:
        res.setdefault("notas", []).append("tras el botón RESET no apareció el menú")
    return lec


def asegurar_menu(b):
    lec = en_menu(b)
    if lec:
        return lec
    lec = reset_boton(b)
    if lec:
        log("menú de nuevo tras el botón RESET")
        return lec
    log("no veo el menú: reset con Select+B")
    r = b.mando.reset(b.cfg["reset_ms"])
    if r.get("lat", 0) > 0:
        time.sleep(2.5)
        lec = en_menu(b, 4)
        if lec:
            return lec
    return apagar_a_mano(b, "el juego no lee el mando y el kit no puede resetear" if not r.get("lat")
                         else "el reset no devuelve al menú")


def volver_al_menu(b, res):
    if reset_boton(b, res):
        return
    r = b.mando.reset(b.cfg["reset_ms"])
    res["reset"] = r
    if not r.get("lat"):
        res.setdefault("notas", []).append("el juego no leía el mando al final: reset a mano")
        apagar_a_mano(b, "el juego no lee el mando y el kit no puede resetear")
        return
    time.sleep(2.0)
    if not en_menu(b, 4):
        res.setdefault("notas", []).append("tras Select+B no apareció el menú")
        asegurar_menu(b)


def lanzar(b, rom_rel, p0, guion_txt):
    """Navega hasta la ROM, carga y arma el guion y la lanza (B, B en el OS v13). Devuelve la hora del pulso."""
    asegurar_menu(b)
    carpeta, nombre = os.path.split(rom_rel)
    lec = b.menu.ir_a_carpeta(b.mando, b.cap, carpeta)
    b.menu.elegir(b.mando, b.cap, nombre, lec)
    b.mando.guion(guion_txt)
    b.mando.eventos(True)
    teclas = b.menu.teclas["lanzar"]
    for k in teclas[:-1]:            # B abre el File Menu del N8 (con 400 ms la 2.ª B a veces se perdía: 800); al
        b.mando.tocar(k, b.menu.teclas["pulso_ms"], 800)    # abrirlo el OS calla un momento: se arma después
    b.mando.armar(p0, b.cfg["silencio_arranque_ms"])
    t = time.monotonic()
    b.mando.tocar(teclas[-1], b.menu.teclas["pulso_ms"], 50)
    return t


# ---------------------------------------------------------------- calibración
def leer_botones(img):
    lu = comparar.lum(img)
    blanco = float(np.percentile(lu, 99.5))
    return [int(lu[y0:y1, x0:x1].mean() > 0.55 * blanco) for (y0, y1, x0, x1) in hacer_rom.zonas_botones()]


def leer_contador(img):
    r = np.asarray(img, np.float32)
    c = 0
    for (y0, y1, x0, x1) in hacer_rom.zonas_contador():
        z = r[y0:y1, x0:x1]
        c = c * 2 + int(z[..., 0].mean() > 70 and z[..., 0].mean() > z[..., 1].mean() + 25)
    return c


def calibrar_todo(b, salida):
    """Provisional con el menú (si hace falta) -> ROM de calibración -> calibración fina, mando y retraso."""
    salida.mkdir(parents=True, exist_ok=True)
    if b.cal is None:
        log("sin calibración: provisional con el menú")
        for intento in range(4):
            foto = b.cap.foto_completa()
            prov = calibrar.provisional_menu(foto, log=log)
            b.cap.iniciar(prov)
            b.cal = prov
            if en_menu(b, 2):
                break
            b.cap.parar()
            # quizá estamos en la raíz con dos líneas: entrar en una carpeta con más texto
            for k in (["down", "b"], ["a"], ["b"], ["a", "a"])[intento]:   # OS v13: B entra, A vuelve
                b.mando.tocar(k, 100, 300)
        else:
            raise Abortar("no consigo leer el menú del N8 con la calibración provisional")
        _, img = b.cap.estable(3)
        b.menu.fase = menu_mod.fase_rejilla(img)
    else:
        b.cap.iniciar(b.cal)
    rom_rel = b.cfg["rom_calibracion"]
    if not (pathlib.Path(b.cfg["sd"]) / rom_rel).exists():
        raise Abortar(f"falta {rom_rel} en la SD: copia {ROM_CAL} a esa ruta")
    lanzar(b, rom_rel, 1, "")
    if not b.mando.esperar_aviso("!INICIO", 30):
        raise Abortar("la ROM de calibración no arranca (no lee el mando)")
    time.sleep(1.0)
    b.cap.parar()
    foto = b.cap.foto_completa()
    from PIL import Image
    Image.fromarray(foto).save(salida / "calibracion_720p.png")
    esperado, idx, mascara = hacer_rom.imagen_esperada()
    mascara[hacer_rom.FILA_BOTONES * 8:(hacer_rom.FILA_BOTONES + 2) * 8] = False
    cal = calibrar.estimar(foto, esperado, mascara, log=log)
    if cal["puntuacion"] < 0.8:
        raise Abortar(f"calibración dudosa (correlación {cal['puntuacion']}): mira {salida / 'calibracion_720p.png'}")
    b.cal = cal
    b.menu.fase = (0, 0)                       # la rejilla del menú se vuelve a medir al volver a él
    b.cap.iniciar(cal)
    _, nes = b.cap.estable(5)
    Image.fromarray(nes).save(salida / "calibracion_256x240.png")
    cal["mapa_color"] = calibrar.mapa_color(nes, idx, calibrar.mascara_visible(cal, 2) & mascara)
    # el mando, botón a botón
    pm = {}
    for i, nombre in enumerate(BOTONES):
        b.mando.fijar(1 << i)
        time.sleep(0.25)
        _, img = b.cap.estable(3)
        visto = leer_botones(img)
        pm[nombre] = visto == [int(k == i) for k in range(8)]
        if not pm[nombre]:
            log(f"botón {nombre}: la consola ve {visto}")
    b.mando.fijar(0)
    cal["prueba_mando"] = pm
    # retraso de la cadena de vídeo: contador de la ROM frente al fotograma del Nano
    desfase = 4
    try:
        r = referencia.generar(ROM_CAL, "", [60], 60, AQUI / "refs" / "calibracion", log=log)
        desfase = 60 - leer_contador(np.asarray(Image.open(r["shots"][60]).convert("RGB")))
    except Exception as e:  # noqa: BLE001
        log(f"sin referencia de la ROM de calibración ({e}); desfase del contador = 4")
    medidas = []
    for _ in range(40):
        t, img = b.cap.esperar_nuevo(1.0) or (None, None)
        if img is None:
            continue
        fotos = list(b.mando.fotos)
        if not fotos:
            continue
        fc_t = fotograma_en(fotos, t)
        if fc_t is not None:
            medidas.append(fc_t - (leer_contador(img) + desfase))
    if medidas:
        med = float(np.median(medidas))
        if 0 <= med < 30:
            cal["retraso_s"] = round(med / FPS, 4)
        log(f"retraso de la cadena de vídeo: {med:.1f} fotogramas")
    cal["fase_menu"] = [0, 0]
    volver_al_menu(b, {})
    _, img = b.cap.estable(3)
    cal["fase_menu"] = list(menu_mod.fase_rejilla(img))
    b.menu.fase = tuple(cal["fase_menu"])
    calibrar.guardar(cal, b.datos / "calibracion.json")
    ok = all(pm.values())
    log(f"calibración guardada en {b.datos / 'calibracion.json'}; mando: "
        f"{'todos los botones bien' if ok else 'FALLAN ' + ', '.join(k for k, v in pm.items() if not v)}")
    return cal


def fotograma_en(fotos, t):
    """Fotograma del Nano a la hora t (interpolando los avisos !L)."""
    antes = [x for x in fotos if x[0] <= t]
    despues = [x for x in fotos if x[0] > t]
    if antes and despues:
        (t0, f0), (t1, f1) = antes[-1], despues[0]
        return f0 + (f1 - f0) * (t - t0) / max(1e-6, t1 - t0)
    if antes:
        t0, f0 = antes[-1]
        return f0 + (t - t0) * FPS
    return None


def hora_de(fotos, f, t_ini, p0):
    """Hora en que el Nano llegó (o llegará) al fotograma f."""
    for i, (t, fc) in enumerate(fotos):
        if fc >= f:
            if i == 0:
                return t - (fc - f) / FPS
            t0, f0 = fotos[i - 1]
            return t0 + (t - t0) * (f - f0) / max(1, fc - f0)
    if fotos:
        t, fc = fotos[-1]
        return t + (f - fc) / FPS
    return t_ini + (f - p0) / FPS


# ---------------------------------------------------------------- un juego
def probar(b, j, g, ref, dir_juego):
    from PIL import Image
    dir_juego.mkdir(parents=True, exist_ok=True)
    res = {"id": j["id"], "n": j["n"], "rom": j["rom_rel"], "tipo": j["tipo"], "seccion": j["seccion"],
           "guion": g["guion"], "fotogramas": g["fotogramas"], "p0": ref["p0"], "escenas": [], "notas": []}
    p0 = ref["p0"] if ref["p0"] is not None else 0
    if ref["p0"] is None:
        res["notas"].append("el juego no lee el mando en la referencia: sin guion")
    # Película TAS (g["entrada"], un byte por fotograma): el Nano toma los botones de su cola, que se llena antes de
    # lanzar (desde p0) y se rellena mientras se juega, siempre unos 200 fotogramas por delante.
    datos, q_hasta = None, 0
    if g.get("entrada"):
        datos, desfase = pathlib.Path(g["entrada"]).read_bytes(), g.get("desfase", 0)

        def byte_de(f):
            return datos[f + desfase] if 0 <= f + desfase < len(datos) else 0
        b.mando.orden("X")                        # sin guion activo mientras se navega por el menú
        b.mando.cola_vaciar()
        q_hasta = p0 + 200
        b.mando.cola_escribir(p0, [byte_de(f) for f in range(p0, q_hasta)])
    b.cap.grabar_clip(dir_juego / "clip.mp4")
    audio = b.cap.grabar_audio(dir_juego / "audio.wav")
    rotulo = getattr(b.cap, "rotulo", lambda s: None)
    rotulo(f"{j['n'][:40]}\nnavegando por el menú del N8")
    t_lanzar = lanzar(b, j["rom_rel"], p0, g["guion"])
    ini = b.mando.esperar_aviso("!INICIO", 30, t_lanzar)
    if not ini:
        _, img = b.cap.estable(2)
        Image.fromarray(img).save(dir_juego / "no_arranca.png")
        res["veredicto"] = "no_arranca"
        res["notas"].append("no empezó a leer el mando en 30 s (¿mapper no soportado, pantalla del OS?)")
        b.cap.parar_clip()
        b.cap.parar_audio()
        volver_al_menu(b, res)
        return res
    t_ini = next(t for t, a in reversed(b.mando.avisos) if a.startswith("!INICIO"))
    L, V = b.retraso(), b.cfg["ventana_s"]
    pendientes = sorted(s for s in g["shots"] if s >= p0)
    fin = g["fotogramas"]
    t_limite = t_ini + (fin - p0) / FPS * 1.6 + 20
    mascara = b.mascara()
    cuelgue = None
    polls_ref = sorted(p[0] for p in ref.get("polls", []))
    rearmes = 0
    while True:
        time.sleep(0.05)
        ahora = time.monotonic()
        fotos = [x for x in list(b.mando.fotos) if x[0] >= t_ini]
        fc = fotos[-1][1] if fotos else p0
        t_ult = fotos[-1][0] if fotos else t_ini
        if int(ahora * 4) != int((ahora - 0.05) * 4):          # el rótulo, 4 veces por segundo
            ok_ = sum(1 for e in res["escenas"] if e.get("veredicto") == "ok")
            ult = res["escenas"][-1] if res["escenas"] else None
            rotulo(f"{j['n'][:40]}\nfotograma {fc} / {fin}   escenas iguales {ok_}/{len(res['escenas'])}"
                   + (f"\núltima: {ult['f']} {ult['veredicto']}" if ult else ""))
        # La cola (256 fotogramas) va siempre ~250 por delante; se rellena de una vez lo que falte, en trozos de 48.
        # (Con un umbral de 150 y un trozo por vuelta, en el TAS de SMB llegaron 10 fotogramas sin dato.)
        if datos is not None and q_hasta - fc < 210 and q_hasta <= fin + 300:   # más allá del final: ceros
            n = fc + 250 - q_hasta
            if n > 0:
                b.mando.cola_escribir(q_hasta, [byte_de(f) for f in range(q_hasta, q_hasta + n)])
                q_hasta += n
        # Con ROMs grandes el OS v13 carga por partes y lee el mando entre medias ("loading..." y segundos en negro):
        # el !INICIO puede llegar con una lectura del OS. Si al principio las lecturas se cortan más de 0,5 s donde
        # Mesen2 sigue leyendo, era una pausa del OS: se rearma el Nano y se espera el arranque de verdad.
        sig_ref = next((p for p in polls_ref if p > fc), None)
        if (rearmes < 8 and fc - p0 < 300 and ahora - t_ult > 0.5 and sig_ref is not None and sig_ref <= fc + 30
                and not any(e.get("f", 0) <= fc for e in res["escenas"])):
            b.mando.armar(p0, b.cfg["silencio_arranque_ms"])
            ini = b.mando.esperar_aviso("!INICIO", 30, ahora)
            if not ini:
                res["notas"].append("tras una pausa del arranque no volvió a leer el mando en 30 s")
                break
            t_ini = next(t for t, a in reversed(b.mando.avisos) if a.startswith("!INICIO"))
            t_limite = t_ini + (fin - p0) / FPS * 1.6 + 20
            rearmes += 1
            log(f"  pausa del OS al cargar: nuevo arranque ({rearmes})")
            continue
        for s in list(pendientes):
            ts = hora_de(fotos, s, t_ini, p0) + L
            if ahora > ts + V + 0.15:
                cuadros = b.cap.ventana(ts - V, ts + V)
                refimg = np.asarray(Image.open(ref["shots"][s]).convert("RGB")) if s in ref["shots"] else None
                e = {"f": s}
                if refimg is None:
                    e["veredicto"] = "sin_referencia"
                elif not cuadros:
                    e["veredicto"] = "sin_imagen"
                else:
                    v, p, i, t = comparar.mejor_de_ventana(cuadros, refimg, mascara)
                    e.update({"veredicto": v, **p, "desfase_s": round(t - ts, 3)})
                    Image.fromarray(cuadros[i][1]).save(dir_juego / f"consola_{s:05d}.png")
                    Image.fromarray(refimg).save(dir_juego / f"mesen_{s:05d}.png")
                res["escenas"].append(e)
                pendientes.remove(s)
                log(f"  escena {s}: {e['veredicto']} {e.get('frac', '')}")
        sin_leer = ahora - t_ult
        # Hay juegos que pasan segundos sin leer el mando (la intro de Punch-Out!!, ~6 s en negro): solo es cuelgue si
        # en Mesen2 el juego ya habría vuelto a leerlo. Siguiente lectura de la referencia tras el último fotograma visto:
        sig_ref = next((p for p in polls_ref if p > fc), None)
        espera_ref = sig_ref is None or (fc + sin_leer * FPS) < sig_ref + 3 * FPS
        if sin_leer > 3 and not espera_ref:
            ult = b.cap.ventana(ahora - 3, ahora)
            if comparar.congelada(ult, mascara) or sin_leer > 12:
                cuelgue = {"fc": fc, "segundos_sin_leer": round(sin_leer, 1),
                           "congelada": comparar.congelada(ult, mascara)}
                _, img = b.cap.ultimo()
                if img is not None:
                    Image.fromarray(img).save(dir_juego / "cuelgue.png")
                log(f"  cuelgue en el fotograma {fc} ({sin_leer:.0f} s sin leer el mando)")
                break
        if (fc >= fin and not pendientes) or ahora > t_limite:
            break
    b.cap.parar_clip()
    b.cap.parar_audio()
    if datos is not None:
        res["huecos_cola"] = b.mando.estado().get("qf", 0)    # fotogramas que llegaron sin entrada de la película
        b.mando.cola_quitar()
        if res["huecos_cola"]:
            res["notas"].append(f"{res['huecos_cola']} fotogramas sin entrada de la película (la cola no llegó a tiempo)")
    res["lecturas"] = len([x for x in b.mando.fotos if x[0] >= t_ini])
    res["fc_final"] = fc
    if cuelgue:
        res["cuelgue"] = cuelgue
    if audio and (dir_juego / "audio.wav").exists():
        try:
            res["audio"] = sonido.analizar(dir_juego / "audio.wav", buscar_tono="tono" in j["n"].lower())
        except Exception as e:  # noqa: BLE001
            res["notas"].append(f"audio: {e}")
    res["veredicto"] = comparar.resumen(res["escenas"], cuelgue is not None)
    if j["tipo"] == "s" and "audio" in res:
        a = res["audio"]
        if "tono" in a:
            res["veredicto_audio"] = "ok" if a["tono"] else "falla"
        else:
            res["veredicto_audio"] = "escuchar"
    volver_al_menu(b, res)
    return res


# ---------------------------------------------------------------- informe
COLOR = {"ok": "#167a2c", "parecido": "#b26a00", "distinto": "#b3261e", "negra": "#b3261e", "basura": "#b3261e",
         "cuelgue": "#b3261e", "no_arranca": "#b3261e", "error": "#b3261e"}


def nota_pagina(r):
    v = r.get("veredicto")
    partes = [f"[auto {datetime.date.today().isoformat()}] {v}"]
    malas = [e for e in r.get("escenas", []) if e.get("veredicto") not in ("ok",)]
    if malas:
        partes.append("escenas " + ", ".join(f"{e['f']}:{e['veredicto']}" for e in malas[:6]))
    if r.get("cuelgue"):
        partes.append(f"cuelgue en el fotograma {r['cuelgue']['fc']}")
    if r.get("audio"):
        a = r["audio"]
        partes.append(f"audio {a['rms_db']} dBFS" + (f", tono 1 kHz {'sí' if a.get('tono') else 'no'}" if "tono" in a else ""))
    partes += r.get("notas", [])
    return "; ".join(partes)


def resultados_pagina(resultados, consola):
    """Documentos para la colección `resultados` de la página (mismo formato que guarda la página)."""
    docs = {}
    ahora = datetime.datetime.now(datetime.timezone.utc).isoformat()
    for r in resultados:
        if not r.get("id"):
            continue
        v = r.get("veredicto")
        if r.get("tipo") == "s":
            estado = {"ok": "ok", "falla": "falla"}.get(r.get("veredicto_audio"), "")
        else:
            estado = "ok" if v == "ok" else ("falla" if v in ("distinto", "negra", "basura", "cuelgue", "no_arranca")
                                             else "")
        docs[r["id"]] = {"estado": estado, "nota": nota_pagina(r), "vol": "", "consola": consola, "t": ahora}
    return docs


def informe(salida, resultados, cfg, consola):
    (salida / "results.json").write_text(json.dumps(resultados, indent=1, ensure_ascii=False))
    (salida / "resultados_pagina.json").write_text(json.dumps(resultados_pagina(resultados, consola), indent=1,
                                                              ensure_ascii=False))
    filas = []
    for r in resultados:
        v = r.get("veredicto", "?")
        k = r.get("dir", "")
        esc = []
        for e in r.get("escenas", []):
            f = e["f"]
            c = f"{k}/consola_{f:05d}.png"
            m = f"{k}/mesen_{f:05d}.png"
            info = html.escape(f"{e['veredicto']} {e.get('frac', '')}")
            esc.append(f'<figure><img src="{c}" title="consola"><img src="{m}" title="Mesen2"><figcaption>'
                       f'{f}: <b style="color:{COLOR.get(e["veredicto"], "#555")}">{info}</b></figcaption></figure>')
        extra = []
        if r.get("cuelgue"):
            extra.append(f"cuelgue en el fotograma {r['cuelgue']['fc']} ({r['cuelgue']['segundos_sin_leer']} s sin leer el mando)")
        if r.get("audio"):
            extra.append(f'audio: {html.escape(json.dumps(r["audio"]))} <a href="{k}/audio.wav">wav</a>')
        extra += [html.escape(n) for n in r.get("notas", [])]
        clip = ""
        for ext in ("mp4", "gif"):
            if k and (salida / k / f"clip.{ext}").exists():
                clip = f'<a href="{k}/clip.{ext}">vídeo</a>'
                break
        filas.append(f'<tr><td><b>{html.escape(r["n"])}</b><br><small>{html.escape(r.get("rom") or "")}<br>'
                     f'{html.escape(r.get("id") or "")}</small></td><td><b style="color:{COLOR.get(v, "#555")}">{v}'
                     f'</b><br>{clip}<br><small>p0={r.get("p0")} · {"<br>".join(extra)}</small></td>'
                     f'<td>{"".join(esc)}</td></tr>')
    cuenta = {}
    for r in resultados:
        cuenta[r.get("veredicto", "?")] = cuenta.get(r.get("veredicto", "?"), 0) + 1
    pagina = f"""<!doctype html><html lang="es"><head><meta charset="utf-8"><title>Pruebas en consola</title>
<style>body{{font-family:sans-serif;margin:16px;background:#fafafa;color:#222}} table{{border-collapse:collapse}}
td{{border-bottom:1px solid #ddd;padding:6px;vertical-align:top}} img{{width:160px;image-rendering:pixelated;margin-right:2px}}
figure{{display:inline-block;margin:0 8px 6px 0}} figcaption{{font-size:12px}}</style></head><body>
<h1>Pruebas en consola ({consola}) — {datetime.datetime.now():%Y-%m-%d %H:%M}</h1>
<p>{" · ".join(f"{k}: {v}" for k, v in sorted(cuenta.items()))}. En cada escena: consola a la izquierda, Mesen2 a la derecha;
número = fracción de píxeles que no encajan con su color.</p><table>{''.join(filas)}</table></body></html>"""
    (salida / "index.html").write_text(pagina)


# ---------------------------------------------------------------- órdenes
def preparar_tas(a, cfg, salida):
    """Un juego que reproduce una película TAS .fm2 (tas.py) con capturas cada --cada fotogramas."""
    import tas
    if not a.rom or len(a.rom) != 1:
        raise SystemExit("tas: indica la ROM con --rom (ruta relativa a la raíz de la SD)")
    rom_rel = a.rom[0]
    cab, mandos, _ = tas.leer_fm2(a.pelicula)
    if tas.md5_rom(pathlib.Path(cfg["sd"]) / rom_rel) != cab.get("romChecksum"):
        raise SystemExit(f"tas: la ROM {rom_rel} no es la de la película ({cab.get('romFilename')})")
    entrada = salida / "pelicula.bin"
    entrada.write_bytes(bytes(mandos))
    fin = len(mandos) + a.extra
    g = {"guion": "", "fotogramas": fin, "shots": list(range(a.cada, fin + 1, a.cada)), "entrada": str(entrada),
         "desfase": a.desfase}
    nombre = f"TAS {pathlib.Path(a.pelicula).stem}"
    log(f"{nombre}: {len(mandos)} fotogramas de película, {len(g['shots'])} escenas, ROM {rom_rel}")
    return [{"id": None, "n": nombre, "m": "", "tipo": "t", "pila": False, "seccion": "TAS", "rom_rel": rom_rel,
             "motivo": None, "g": g}]


def preparar_lista(a, cfg, guiones):
    if a.carpeta:
        lista = lista_carpeta(cfg, a.carpeta)
    elif a.rom:
        lista = [{"id": None, "n": pathlib.Path(r).stem, "m": "", "tipo": "n", "pila": False, "seccion": "",
                  "rom_rel": r, "motivo": None} for r in a.rom]
    else:
        lista = lista_plan(cfg, a.consola)
    for j in lista:
        if j["rom_rel"] and j["tipo"] == "s" and a.consola == "nes":
            j["motivo"] = "prueba de sonido: en la Famicom"
    validos = [j for j in lista if j["rom_rel"] and not j["motivo"]]
    for j in lista:
        if j["motivo"]:
            log(f"se salta {j['n']}: {j['motivo']}")
    if a.solo:
        validos = [j for j in validos if re.search(a.solo, j["n"] + " " + (j["rom_rel"] or ""), re.I)]
    if a.max:
        validos = validos[:a.max]
    for j in validos:
        j["g"] = guion_de(j, guiones, a.fotogramas)
    return validos, lista


def generar_refs(validos, cfg):
    refs = {}
    for k, j in enumerate(validos, 1):
        rom = pathlib.Path(cfg["sd"]) / j["rom_rel"]
        d = dir_ref(j["rom_rel"], j["g"])
        try:
            refs[j["rom_rel"]] = referencia.generar(rom, j["g"]["guion"], j["g"]["shots"], j["g"]["fotogramas"], d,
                                                    entrada=j["g"].get("entrada"), desfase=j["g"].get("desfase", 0))
        except Exception as e:  # noqa: BLE001
            log(f"[{k}/{len(validos)}] sin referencia para {j['n']}: {e}")
            continue
        log(f"[{k}/{len(validos)}] referencia {j['n']}: p0={refs[j['rom_rel']]['p0']}")
    return refs


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("accion", choices=["dispositivos", "calibrar", "referencias", "ejecutar", "informe", "tas"])
    ap.add_argument("--pelicula", help="tas: película .fm2 de FCEUX (TASVideos)")
    ap.add_argument("--desfase", type=int, default=1, help="tas: fotograma de la película = fotograma + desfase (FCEUX: 1)")
    ap.add_argument("--cada", type=int, default=600, help="tas: una escena cada tantos fotogramas")
    ap.add_argument("--extra", type=int, default=600, help="tas: fotogramas tras el final de la película")
    ap.add_argument("carpeta_informe", nargs="?")
    ap.add_argument("--config", default=str(AQUI / "config.json"))
    ap.add_argument("--consola", choices=["nes", "famicom"])
    ap.add_argument("--carpeta", help="todas las ROMs de una carpeta de la SD (p. ej. 'PRUEBAS/4 MMC3')")
    ap.add_argument("--rom", action="append", help="ROM concreta (ruta relativa a la raíz de la SD)")
    ap.add_argument("--solo", help="expresión regular sobre el nombre")
    ap.add_argument("--max", type=int)
    ap.add_argument("--fotogramas", type=int, help="acortar el guion (útil para probar)")
    ap.add_argument("--banco", action="store_true", help="además, lanzar difftest.py con el mismo guion (lento)")
    ap.add_argument("--seco", action="store_true", help="sin hardware: consola, Nano y capturadora simulados")
    ap.add_argument("--sim-fallos", default=None,
                    help='en seco: "archivo.nes=negra,otro.nes=cuelgue:300" (por defecto, el 2.º juego negra y el 3.º se cuelga)')
    ap.add_argument("--recalibrar", action="store_true")
    ap.add_argument("--sin-ventana", action="store_true", help="sin la ventana en vivo de la capturadora")
    a = ap.parse_args()
    cfg = cargar_config(a.config)
    if a.sin_ventana:
        cfg["ventana"] = False
    a.consola = a.consola or cfg["consola"]

    if a.accion == "dispositivos":
        import captura
        from serie import buscar_puertos, describir
        print("Puertos serie:", [(p, describir(p)) for p in buscar_puertos()] or "ninguno")
        print("Capturadoras:", [(r, n, captura.admite_720p60(r)) for r, n in captura.listar_video()] or "ninguna")
        print("Audio:", captura.listar_audio(), "-> capturadora:", captura.audio_de_capturadora())
        print("Mesen2 del banco:", "sí" if referencia.disponible() else "no")
        return
    if a.accion == "informe":
        d = pathlib.Path(a.carpeta_informe)
        informe(d, json.loads((d / "results.json").read_text()), cfg, a.consola)
        print(d / "index.html")
        return

    guiones = cargar_guiones()
    salida = AQUI / "informes" / (datetime.datetime.now().strftime("%Y%m%d-%H%M%S") + ("-seco" if a.seco else ""))
    salida.mkdir(parents=True, exist_ok=True)
    if a.accion == "tas":
        validos = lista = preparar_tas(a, cfg, salida)
    else:
        validos, lista = preparar_lista(a, cfg, guiones)
    log(f"{len(validos)} juegos para la {a.consola.upper()} -> {salida}")
    if a.accion in ("referencias", "ejecutar", "tas"):
        refs = generar_refs(validos, cfg)
        if a.banco:
            por_guion = {}
            for j in validos:
                por_guion.setdefault(json.dumps([j["g"]["guion"], j["g"]["shots"], j["g"]["fotogramas"]]), []).append(j)
            for clave, js in por_guion.items():
                gu, sh, fo = json.loads(clave)
                referencia.lanzar_banco([pathlib.Path(cfg["sd"]) / j["rom_rel"] for j in js], gu, sh, fo,
                                        salida / "banco", log=log)
        if a.accion == "referencias":
            return
    else:
        refs = {}

    fallos = {}
    if a.seco:
        if a.sim_fallos is None and len(validos) >= 3:
            fallos = {os.path.basename(validos[1]["rom_rel"]): "negra",
                      os.path.basename(validos[2]["rom_rel"]): "cuelgue:" + str(max(200, validos[2]["g"]["fotogramas"] // 2))}
        elif a.sim_fallos:
            fallos = dict(x.split("=", 1) for x in a.sim_fallos.split(","))
        if fallos:
            log(f"fallos simulados a propósito: {fallos}")
    refs_sim = {j["rom_rel"]: str(refs[j["rom_rel"]]["dir"]) for j in validos if j["rom_rel"] in refs}
    b = Banco(cfg, a.seco, salida, fallos, refs_sim)
    resultados = []
    try:
        if a.accion == "calibrar" or b.cal is None or a.recalibrar:
            calibrar_todo(b, salida)
            b.guardar_aprendido()
            if a.accion == "calibrar":
                return
        else:
            b.cap.iniciar(b.cal)
        for k, j in enumerate(validos, 1):
            if j["rom_rel"] not in refs:
                continue
            log(f"[{k}/{len(validos)}] {j['n']} ({j['rom_rel']})")
            d = salida / referencia.clave(j["rom_rel"])
            try:
                r = probar(b, j, j["g"], refs[j["rom_rel"]], d)
            except (menu_mod.ErrorMenu, ErrorMando) as e:
                r = {"id": j["id"], "n": j["n"], "rom": j["rom_rel"], "tipo": j["tipo"], "veredicto": "error",
                     "notas": [f"{type(e).__name__}: {e}"], "escenas": []}
                log(f"  error: {e}")
                b.cap.parar_clip()
                b.cap.parar_audio()
                try:
                    asegurar_menu(b)
                except Abortar:
                    raise
            r["dir"] = d.name
            resultados.append(r)
            log(f"  -> {r['veredicto']}")
            informe(salida, resultados, cfg, a.consola)
            b.guardar_aprendido()
    except Abortar as e:
        avisar(f"prueba detenida: {e}")
    except KeyboardInterrupt:
        log("interrumpido")
    finally:
        if resultados:
            informe(salida, resultados, cfg, a.consola)
        b.cerrar()
    if resultados:
        cuenta = {}
        for r in resultados:
            cuenta[r["veredicto"]] = cuenta.get(r["veredicto"], 0) + 1
        log(f"terminado: {cuenta}. Informe: {salida / 'index.html'}")


if __name__ == "__main__":
    main()
