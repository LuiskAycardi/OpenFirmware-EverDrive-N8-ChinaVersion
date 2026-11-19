#!/usr/bin/env python3
"""analizar.py CARPETA [--md SALIDA.md] [--json SALIDA.json] — Análisis de las BIOS FDS y los .fds de una carpeta
(GPL-3.0-or-later, código propio).

Para cada BIOS: CRC32 y si el OS la puede parchear (tabla de fds.py). Para cada .fds: caras, código del juego,
archivos (declarados y ocultos) y, mirando el código de sus archivos PRG, qué necesita del cartucho:
  - cargador propio: lee $4031 o escribe $4024 sin pasar por la BIOS (no funcionaría con la BIOS parcheada);
  - estado del disco: lee $4030/$4032 (el HDL debe contestar como un FDS con el disco dentro y listo);
  - temporizador: escribe $4020-$4022 (IRQ del temporizador del FDS);
  - sonido: escribe $4040-$4097 (solo se oye en la Famicom);
  - escribe en el disco: llama a las rutinas de escritura de la BIOS (WriteFile $E239, AppendFile $E237,
    SetFileCount $E301/$E305, AdjustFileCount $E2BB); el OS tendrá que guardar la imagen en la SD.
Es un análisis estático: no ve código comprimido ni accesos indirectos ((zp),Y). No copia nada de las ROMs: el
informe solo lleva nombres, sumas y recuentos.
"""
import argparse
import json
import os
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fds  # noqa: E402

COPIA_BIOS = {0xE1CE, 0xE1D1, 0xE1E5, 0xE6C0}   # dónde lee $4031 / escribe $4024 la BIOS Rev 1
ESCRITURA_BIOS = {0xE239: 'WriteFile', 0xE237: 'AppendFile', 0xE301: 'SetFileCount1', 0xE305: 'SetFileCount',
                  0xE2BB: 'AdjustFileCount'}


def analizar_fds(ruta):
    datos = open(ruta, 'rb').read()
    r = {'archivo': os.path.basename(ruta), 'crc32': f'{zlib.crc32(datos):08X}', 'problemas': []}
    desp = 16 if datos[:4] == b'FDS\x1a' else 0
    r['crc_ini'] = f'{zlib.crc32(datos[desp:desp + fds.INI]):08X}'     # el que calcula el OS (lista de los «no»)
    try:
        cs, r['fwnes'] = fds.caras(datos)
    except ValueError as e:
        r['estado'] = 'no'
        r['problemas'].append(str(e))
        return r
    r['caras'] = len(cs)
    r.update(propio=[], copia_bios=[], estado_disco=False, temporizador=False, sonido=False, escribe=set(), ocultos=0,
             archivos=0)
    for k, c in enumerate(cs):
        cr = fds.leer_cara(c)
        r['problemas'] += [f'cara {k + 1}: {p}' for p in cr['problemas']]
        if k == 0 and 'codigo' in cr:
            r['codigo'] = cr['codigo']
            r['revision'] = cr['revision']
            r['fabricante'] = f'{cr["fabricante"]:02X}'
        for a in cr['archivos']:
            r['archivos'] += 1
            r['ocultos'] += a['oculto']
            if a['tipo'] != 0:
                continue
            for (op, reg), donde in fds.accesos(a['datos'], a['dir']).items():
                if (reg == fds.REG_DATOS_LEER and op in fds.LEER.values()) or \
                   (reg == fds.REG_DATOS_ESCRIBIR and op in fds.ESCRIBIR.values()):
                    # En las mismas direcciones que la rutina de la BIOS: un archivo que lleva una copia de la BIOS
                    # (no se puede ejecutar ahí, esa zona es la BIOS). En otra dirección: rutina de disco propia.
                    for d in donde:
                        (r['copia_bios'] if d in COPIA_BIOS else r['propio']).append(f'${d:04X} ({a["nombre"]})')
                if reg in fds.REGS_ESTADO and op in fds.LEER.values():
                    r['estado_disco'] = True
                if 0x4020 <= reg <= 0x4022 and op in fds.ESCRIBIR.values():
                    r['temporizador'] = True
                if 0x4040 <= reg <= 0x4097 and op in fds.ESCRIBIR.values():
                    r['sonido'] = True
            d = a['datos']
            for i in range(len(d) - 2):
                if d[i] == 0x20:                      # JSR
                    dst = d[i + 1] | d[i + 2] << 8
                    if dst in ESCRITURA_BIOS:
                        r['escribe'].add(ESCRITURA_BIOS[dst])
    r['escribe'] = sorted(r['escribe'])
    if r['problemas'] and not r['propio'] and not r['copia_bios'] and all('declara' in p for p in r['problemas']):
        r['problemas'][-1] += ' (la BIOS dará error si intenta leer los que faltan)'
    if any('sin bloque' in p for p in r['problemas']):
        r['estado'] = 'no'
    elif r['propio']:
        r['estado'] = 'no'
        r['problemas'].append('rutina de disco propia en ' + ', '.join(sorted(set(r['propio']))[:3]))
    elif r['copia_bios']:
        r['estado'] = 'aviso'
        r['problemas'].append('un archivo lleva una copia de la rutina de disco de la BIOS (no se ejecuta ahí)')
    elif r['problemas']:
        r['estado'] = 'aviso'
    else:
        r['estado'] = 'si'
    return r


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('carpeta')
    ap.add_argument('--md')
    ap.add_argument('--json')
    ap.add_argument('--inc', help='tablas para el OS (os/src/fds_tablas.inc)')
    a = ap.parse_args()
    nombres = sorted(os.listdir(a.carpeta), key=str.lower)
    bios = []
    for n in nombres:
        p = os.path.join(a.carpeta, n)
        if n.lower().endswith(('.bin', '.rom')) and os.path.getsize(p) == 8192:
            crc, nombre, estado, texto = fds.bios_info(open(p, 'rb').read())
            bios.append({'archivo': n, 'crc32': f'{crc:08X}', 'nombre': nombre, 'estado': estado, 'nota': texto})
    juegos = [analizar_fds(os.path.join(a.carpeta, n)) for n in nombres if n.lower().endswith('.fds')]

    cuenta = {e: sum(j['estado'] == e for j in juegos) for e in ('si', 'aviso', 'no')}
    print(f'BIOS: {len(bios)} ({sum(b["estado"] == "si" for b in bios)} se pueden parchear)')
    print(f'.fds: {len(juegos)}  sí {cuenta["si"]}  aviso {cuenta["aviso"]}  no {cuenta["no"]}')
    for k in ('estado_disco', 'temporizador', 'sonido'):
        print(f'  {k}: {sum(bool(j.get(k)) for j in juegos)}')
    print(f'  escriben en el disco: {sum(bool(j.get("escribe")) for j in juegos)}')
    print(f'  con archivos ocultos: {sum(j.get("ocultos", 0) > 0 for j in juegos)}')

    if a.json:
        with open(a.json, 'w') as f:
            json.dump({'bios': bios, 'juegos': juegos}, f, ensure_ascii=False, indent=1)
    if a.inc:
        escribir_inc(a.inc, juegos)
    if a.md:
        escribir_md(a.md, bios, juegos, cuenta)


def escribir_inc(ruta, juegos):
    """Tablas del OS: CRC32 de las BIOS (primero las que se parchean) y de los primeros fds.INI bytes de los discos
    que no valen. Solo sumas: ningún byte de Nintendo."""
    def dw(v):
        return f'        .dword  ${v:08X}'
    si_ = [c for c, b in fds.BIOS.items() if b[1] == 'si']
    no_ = [c for c, b in fds.BIOS.items() if b[1] != 'si']
    malos = sorted({int(j['crc_ini'], 16): j['archivo'] for j in juegos if j['estado'] == 'no'}.items())
    L = ['; fds_tablas.inc — generado por tools/fds/analizar.py --inc (no editar a mano). GPL-3.0-or-later.',
         '; Solo sumas CRC32: ningún byte de las BIOS ni de los juegos.', '',
         f'FDS_INI     = {fds.INI}                ; bytes del principio del disco que entran en la suma de fds_malos',
         f'FDS_BIOS_SI = {len(si_)}                  ; las primeras de fds_bios se pueden parchear',
         f'FDS_BIOS_N  = {len(si_) + len(no_)}', f'FDS_MALOS_N = {len(malos)}', '',
         'fds_bios_crc:']
    L += [dw(c) + f'      ; {fds.BIOS[c][0]}' for c in si_ + no_]
    tabla = []
    for n in range(16):                       # CRC-32 de 4 en 4 bits: tabla[n] = n pasado 4 veces por el polinomio
        c = n
        for _ in range(4):
            c = (c >> 1) ^ (0xEDB88320 if c & 1 else 0)
        tabla.append(c)
    L += ['', '; CRC-32 (polinomio $EDB88320 reflejado) de 4 en 4 bits', 'tabla_crc:']
    L += [dw(c) for c in tabla]
    L += ['', '; discos con rutina de disco propia (no cargan con la BIOS parcheada)', 'fds_malos:']
    L += [dw(c) + f'      ; {n[:-4]}' for c, n in malos]
    with open(ruta, 'w') as f:
        f.write('\n'.join(L) + '\n')


def si(v):
    return 'sí' if v else ''


def escribir_md(ruta, bios, juegos, cuenta):
    L = ['# Compatibilidad FDS: BIOS e imágenes', '',
         'Generado por `tools/fds/analizar.py` sobre la colección del usuario (No-Intro). Solo lleva nombres, sumas '
         'y recuentos: ningún byte de las BIOS ni de los juegos. Análisis estático del código de los archivos PRG; '
         'no ve código comprimido ni accesos indirectos, así que «sí» quiere decir «nada en contra», no «probado».', '',
         '## BIOS', '',
         '| Archivo | CRC32 | Versión | ¿Se parchea? | Nota |', '|---|---|---|---|---|']
    for b in bios:
        L.append(f'| {b["archivo"]} | `{b["crc32"]}` | {b["nombre"] or "?"} | {b["estado"]} | {b["nota"]} |')
    L += ['', '## Resumen de los .fds', '',
          f'- {len(juegos)} imágenes: **{cuenta["si"]} sí**, {cuenta["aviso"]} con aviso, {cuenta["no"]} no.',
          f'- Con 1 cara: {sum(j.get("caras") == 1 for j in juegos)}; con 2: {sum(j.get("caras") == 2 for j in juegos)}.',
          f'- Leen el estado del disco ($4030/$4032): {sum(bool(j.get("estado_disco")) for j in juegos)}.',
          f'- Usan el temporizador IRQ ($4020-$4022): {sum(bool(j.get("temporizador")) for j in juegos)}.',
          f'- Usan el sonido FDS: {sum(bool(j.get("sonido")) for j in juegos)}.',
          f'- Escriben en el disco con la BIOS: {sum(bool(j.get("escribe")) for j in juegos)}.',
          f'- Con archivos ocultos (detrás de los declarados): {sum(j.get("ocultos", 0) > 0 for j in juegos)}.',
          f'- Con rutina de disco propia: {sum(bool(j.get("propio")) for j in juegos)}.', '',
          '## Imágenes', '',
          '| Juego | Estado | Caras | Código | Rev | Archivos (ocultos) | Temporizador | Sonido | Escribe | Notas |',
          '|---|---|---|---|---|---|---|---|---|---|']
    for j in juegos:
        nombre = j['archivo'][:-4].replace('|', '/')
        notas = '; '.join(j['problemas'])
        L.append(f'| {nombre} | {j["estado"]} | {j.get("caras", "")} | {j.get("codigo", "")} | '
                 f'{j.get("revision", "")} | {j.get("archivos", "")} ({j.get("ocultos", 0)}) | '
                 f'{si(j.get("temporizador"))} | {si(j.get("sonido"))} | {", ".join(j.get("escribe", []))} | '
                 f'{notas} |')
    with open(ruta, 'w') as f:
        f.write('\n'.join(L) + '\n')


if __name__ == '__main__':
    main()
