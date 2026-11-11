# OpenFirmware-EverDrive-N8-ChinaVersion

Mappers propios (Verilog) para el **EverDrive N8 China Version** (el clon chino del EverDrive N8, con FPGA
**Altera Cyclone II EP2C5**), en sus dos versiones: **Famicom y NES**. Implementación clean room, validada
contra el emulador Mesen2 con fuzz de ROMs sintéticas, bancos de simulación y juegos reales.

*Own Verilog mapper implementations for the EverDrive N8 China Version (the Chinese EP2C5 clone of the
EverDrive N8), for both the Famicom and the NES cartridges. Clean-room, validated against Mesen2.
Documentation is in Spanish.*

> Proyecto independiente: no está afiliado a Krikzz ni a EverDrive, ni respaldado por ellos.
> «EverDrive» es una marca de su autor.

## Estado

- **194 mappers**: los 177 del firmware oficial 1.26 (todos salvo el FDS) y 17 más (46, 59, 83, 114,
  116, 121, 153, 155, 157, 159, 192, 194, 195, 209, 210, 215, 253).
- Siete RBF (`100.RBF`–`106.RBF`) que el OS carga según `MAPROUT.BIN`; cada uno cabe con holgura en
  el EP2C5 y cumple tiempos a 50 MHz.
- Sonido de expansión: VRC6, Sunsoft 5B, Namco 163, MMC5 y **VRC7 (FM)**, un sintetizador propio que
  da exactamente las mismas muestras que emu2413.
- Validación: todos contra Mesen2 con el fuzz de ROMs sintéticas, bancos directos con pruebas de
  mutación y cientos de juegos reales (fotogramas comparados uno a uno). Las diferencias conocidas
  están en `docs/fase4-mappers.md`. **Aún sin validar en la consola real.**

## Probar en tu cartucho

En [Releases](https://github.com/LuiskAycardi/OpenFirmware-EverDrive-N8-ChinaVersion/releases) hay un
paquete listo para la microSD (los RBF y un `MAPROUT.BIN`, con instrucciones en `LEEME.md`). Los
resultados, buenos o malos, se agradecen como *issues*. El paquete se genera con
`make -C hdl build` y `python3 -I release/make_release.py vX.Y.Z`.

## Cómo se ha hecho (clean room)

- Los registros y el comportamiento de cada mapper salen de la descripción pública (NESdev Wiki) y se
  contrastan con Mesen2, que hace de oráculo del banco de pruebas. Las fuentes de Mesen2 se leen para
  conocer hechos (direcciones, bits, orden de eventos), nunca se traducen línea a línea.
- El hardware del N8 (pines de la FPGA, protocolo de configuración del OS, formato de la SD) se ha
  obtenido por ingeniería inversa; está documentado en `docs/hardware-fpga.md`, `docs/sd-analisis.md`
  y `docs/mappers-n8-oficial.md`.
- La referencia pública con licencia MIT del N8 PRO de Krikzz se ha consultado para entender algunas
  placas; no se ha copiado código.

**Este repositorio no contiene** ningún firmware, OS, RBF ni código de Krikzz, ni ROMs. Para usar los
RBF hace falta un N8 con su propio OS y tarjeta SD.

## Estructura

| Carpeta | Contenido |
|---|---|
| `hdl/rtl/` | Diseño: `n8_top.v` (selección de mapper por RBF), mappers, chips de sonido, filtro de A12, DAC |
| `hdl/sim/` | Bancos de simulación con iverilog (`make sim`) |
| `hdl/tools/` | Generador de proyectos Quartus, `MAPROUT.BIN`, inventarios, pruebas de mutación |
| `hdl/quartus/` | Plantilla del proyecto Quartus II 13.0sp1 (pines y tiempos) |
| `tools/n8sim/` | Banco Mesen2 + Verilator: el RTL corre dentro de Mesen2 y se compara con su mapper (`difftest.py`, `fuzz/`) |
| `tools/fm/` | Oráculo y prueba muestra a muestra del FM del VRC7 |
| `tools/consola/` | Pruebas automáticas en la consola real: mando emulado con Arduino, captura de vídeo y comparación |
| `tools/pruebas-n8/`, `tools/pagina-pruebas/` | Plan de pruebas en consola y su página de resultados |
| `docs/` | Documentación del hardware, del banco y de cada fase |

## Uso

Requisitos: Icarus Verilog, Python 3, Quartus II 13.0sp1 (para los RBF), Verilator y .NET (para el
banco Mesen2).

```sh
make -C hdl sim                  # todos los bancos de simulación
make -C hdl build                # hdl/out/100.RBF ... 106.RBF (Quartus II 13.0sp1)

tools/mesen2-setup.sh            # clona Mesen2 en la versión fijada y aplica tools/mesen2-n8.patch
make -C tools/n8sim mesen        # Mesen2 con el mapper puente
python3 -I tools/n8sim/difftest.py --instancias --clk-auto JUEGO.nes   # juego real: N8 frente a Mesen2
python3 -I tools/n8sim/fuzz/fuzz.py 4 85 --semilla 1                   # fuzz de los mappers 4 y 85
```

Para usar los RBF en el N8: copiar `hdl/out/1xx.RBF` a `EDFC/MAPS/` de la SD y dirigir cada mapper a
su RBF con `hdl/tools/maprout.py`.

## Licencia

Copyright © 2026 Luis Carlos Aycardi Salgado.

Este proyecto es software libre: puedes redistribuirlo y/o modificarlo bajo los términos de la
**GNU General Public License** publicada por la Free Software Foundation, ya sea la **versión 3** de la
licencia o (a tu elección) **cualquier versión posterior** (`SPDX-License-Identifier: GPL-3.0-or-later`).
Se distribuye con la esperanza de que sea útil, pero **sin ninguna garantía**; ni siquiera la garantía
implícita de comerciabilidad o idoneidad para un fin determinado. El texto completo está en `LICENSE`.

Terceros:
- `tools/mesen2-n8.patch` modifica [Mesen2](https://github.com/SourMesen/Mesen2) (GPL-3.0); Mesen2 no
  se incluye, `tools/mesen2-setup.sh` lo descarga.
- `tools/fm/fmref.cpp` enlaza en tiempo de compilación con emu2413 (MIT, Mitsutaka Okazaki), tomado
  del árbol de Mesen2; solo es una herramienta de prueba y no forma parte del diseño.
- `hdl/rtl/vrc7_tables.v` se genera con `tools/fm/gen_vrc7_tables.py` a partir de las fórmulas
  públicas del YM2413 y del juego de instrumentos del VRC7 medido por Nuke.YKT.
