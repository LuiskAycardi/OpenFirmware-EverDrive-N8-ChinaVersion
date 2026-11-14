#!/usr/bin/env python3
"""Consolida mediciones NTSC terminadas con la tanda anterior y documenta memoria."""
import collections
import json
import pathlib
import shutil
import subprocess
import sys
import time

import cobertura
import memoria_n8


def main():
    raiz = cobertura.HERE / 'cobertura/completa'
    nueva = raiz / 'medicion_pendientes_ntsc'
    auditoria = json.loads((nueva / 'auditoria_memoria.json').read_text())
    plan = json.loads((nueva / 'plan.json').read_text())
    nuevas = (json.loads((nueva / 'partidas_todas.json').read_text())
              if (nueva / 'partidas_todas.json').exists() else [])
    finalizada = len(nuevas) == len(plan['roms'])
    buenas = [r for r in nuevas if not r.get('error') and r.get('cov')
              and r.get('fotogramas') == plan['frames']]
    anteriores = json.loads((raiz / 'ntsc/partidas.json').read_text())
    validas = [r for r in anteriores if memoria_n8.revisar(r['rom'])['admitida']]
    por_rom = {r['rom']:r for r in validas + buenas}
    salida = raiz / 'ntsc_revisada'
    salida.mkdir(exist_ok=True)
    (salida / 'partidas.json').write_text(json.dumps(list(por_rom.values()),ensure_ascii=False,indent=1))
    cobertura.informe(salida)
    subprocess.run([sys.executable,str(cobertura.HERE/'resumir_cobertura.py'),str(salida),'--ntsc'],check=True)
    cont = collections.Counter((r['ntsc'],r['admitida']) for r in auditoria)
    estado = 'TERMINADA' if finalizada else 'EN CURSO'
    fallos = [r for r in nuevas if r.get('error')]
    md = ['# Revisión de memoria y medición NTSC', '', f'Estado: **{estado}**.', '',
          f'- {len(auditoria)} ROMs revisadas para los mappers pendientes.',
          f'- {cont[True,True]} ROMs NTSC/multirregión admitidas por la revisión de memoria.',
          f'- {cont[True,False]} ROMs NTSC/multirregión rechazadas por memoria/carga.',
          f'- {cont[False,True]+cont[False,False]} ROMs PAL/Dendy excluidas por temporización.',
          f'- {len(buenas)} nuevas partidas completas; {len(fallos)} fallidas; '
          f'{len(plan["roms"])-len(nuevas)} pendientes.',
          f'- {len(validas)} mediciones anteriores conservadas tras revisar su memoria.', '',
          '## Límites y alcance', '',
          'PRG-ROM y SRAM CHR: 512 KiB cada una, independientes. PRG-RAM: 128 KiB físicos, '
          'de los que se consideran 64 KiB disponibles para juegos porque la mitad superior pertenece al OS. '
          'Se suman RAM y NVRAM declaradas, se comprueban tamaño de archivo, trainer y codificación NES 2.0. '
          'La codificación extendida de tamaño no se acepta para el OS v13/puente actual aunque se decodifica '
          'correctamente en el validador.', '',
          'Para las familias pendientes se añaden límites de banca RAM del RTL y regiones CHR mixtas. '
          'En FK23C se limita la CHR-ROM a 256 KiB para evitar la mitad de SRAM usada como CHR-RAM. '
          'No se certifica compatibilidad de placa por cabecera: los submappers no se transmiten al RTL '
          'y los solapes de nametables se señalan para revisión. No se ha operado la NES ni escrito su SD.', '',
          'Las partidas usan 1.200 fotogramas de entrada sintética y miden líneas/conmutación del RTL. '
          'No son una comparación de corrección con el mapper nativo de Mesen2 ni una comprobación de '
          'arranque o guardado en consola. El criterio de partida completa exige todos los fotogramas '
          'y archivo de cobertura.', '',
          'Referencias locales: `difftest.py` (cabeceras), `memoria_n8.py` (reglas), '
          '`N8FpgaMapper.cpp` (memorias y registros cargados como OS v13), '
          '`docs/hardware-fpga.md` y módulos RTL indicados por las reglas. '
          'La fórmula NES 2.0 se contrastó con el lector local de Mesen2; implementación Python propia.', '',
          '## ROMs NTSC/multirregión excluidas por memoria o carga', '',
          '| Mapper | ROM | Motivo |', '| --- | --- | --- |']
    for r in auditoria:
        if r['ntsc'] and not r['admitida']:
            md.append(f"| {r['mapper']} | {pathlib.Path(r['rom']).name} | {'; '.join(r['errores'])} |")
    md += ['', '## Variantes admitidas con submapper distinto de cero', '',
           '| Mapper | ROM | Submapper |', '| --- | --- | --- |']
    for r in auditoria:
        if r['ntsc'] and r['admitida'] and r['cabecera']['submapper']:
            md.append(f"| {r['mapper']} | {pathlib.Path(r['rom']).name} | {r['cabecera']['submapper']} |")
    md += ['', '## Fallos de ejecución', '']
    md += [f"- {pathlib.Path(r['rom']).name}: {r['error']}" for r in fallos] or ['Ninguno registrado.']
    (raiz/'revision_memoria_ntsc.md').write_text('\n'.join(md)+'\n')
    resumen = json.loads((salida/'ntsc/seleccion_juegos.json').read_text())
    resumen.update(estado=estado, nuevas_partidas_completas=len(buenas), nuevas_partidas_fallidas=len(fallos),
                   nuevas_partidas_pendientes=len(plan['roms'])-len(nuevas))
    (salida/'ntsc/seleccion_juegos.json').write_text(json.dumps(resumen,ensure_ascii=False,indent=2)+'\n')
    if finalizada:
        for ext in ('md','json'):
            destino = raiz/f'seleccion_juegos.{ext}'
            copia = raiz/f'seleccion_juegos_antes_revision_memoria.{ext}'
            if not copia.exists():
                shutil.copyfile(destino,copia)
            shutil.copyfile(salida/'ntsc'/destino.name,destino)
        with (raiz/'seleccion_juegos.md').open('a') as f:
            f.write('\n## Revisión de memoria\n\n[Detalle de restricciones, variantes y partidas](revision_memoria_ntsc.md).\n')
    print(f'{estado}: {len(buenas)} nuevas completas, {len(fallos)} fallidas; '
          f'{resumen["mappers"]} mappers, {resumen["juegos"]} juegos seleccionados.')


if __name__ == '__main__':
    if '--esperar' in sys.argv:
        nueva = cobertura.HERE / 'cobertura/completa/medicion_pendientes_ntsc'
        anterior = -1
        while True:
            plan = json.loads((nueva/'plan.json').read_text())
            ruta = nueva/'partidas_todas.json'
            filas = json.loads(ruta.read_text()) if ruta.exists() else []
            n = len(filas)
            if n == len(plan['roms']) or n // 10 > anterior:
                main()
                anterior = n // 10
            if n == len(plan['roms']):
                break
            time.sleep(30)
    else:
        main()
