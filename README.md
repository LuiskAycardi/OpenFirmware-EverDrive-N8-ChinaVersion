# OpenFirmware-EverDrive-N8-ChinaVersion

**ES** — Mappers propios (Verilog) para el **EverDrive N8 China Version** (el clon chino del EverDrive N8,
con FPGA **Altera Cyclone II EP2C5**), en sus dos versiones: **Famicom y NES**. Implementación clean room,
validada contra el emulador Mesen2 con fuzz de ROMs sintéticas, bancos de simulación y juegos reales.

**EN** — Our own Verilog mappers for the **EverDrive N8 China Version** (the Chinese clone of the EverDrive
N8, built around an **Altera Cyclone II EP2C5** FPGA), for both cartridge versions: **Famicom and NES**.
Clean-room implementation, validated against the Mesen2 emulator with synthetic-ROM fuzzing, simulation
testbenches and real games.

> **ES** — Proyecto independiente: no está afiliado a Krikzz ni a EverDrive, ni respaldado por ellos.
> «EverDrive» es una marca de su autor. Este README está en español e inglés; el resto de la
> documentación (`docs/`) está en español.
>
> **EN** — Independent project: not affiliated with or endorsed by Krikzz or EverDrive. "EverDrive" is
> a trademark of its owner. This README is in Spanish and English; the rest of the documentation
> (`docs/`) is in Spanish.

## Estado / Status

**ES**
- **194 mappers**: los 177 del firmware oficial 1.26 (todos salvo el FDS) y 17 más (46, 59, 83, 114,
  116, 121, 153, 155, 157, 159, 192, 194, 195, 209, 210, 215, 253).
- Siete RBF (`100.RBF`–`106.RBF`) que el OS carga según `MAPROUT.BIN`; cada uno cabe con holgura en
  el EP2C5 y cumple tiempos a 50 MHz.
- Sonido de expansión: VRC6, Sunsoft 5B, Namco 163, MMC5 y **VRC7 (FM)**, un sintetizador propio que
  da exactamente las mismas muestras que emu2413.
- Validación: todos contra Mesen2 con el fuzz de ROMs sintéticas, bancos directos con pruebas de
  mutación y cientos de juegos reales (fotogramas comparados uno a uno). Las diferencias conocidas
  están en `docs/fase4-mappers.md`. **Aún sin validar en la consola real.**

**EN**
- **194 mappers**: the 177 of the official 1.26 firmware (all but the FDS) plus 17 more (46, 59, 83,
  114, 116, 121, 153, 155, 157, 159, 192, 194, 195, 209, 210, 215, 253).
- Seven RBF files (`100.RBF`–`106.RBF`) that the OS loads according to `MAPROUT.BIN`; each one fits in
  the EP2C5 with room to spare and meets timing at 50 MHz.
- Expansion audio: VRC6, Sunsoft 5B, Namco 163, MMC5 and **VRC7 (FM)**, our own synthesizer that
  produces exactly the same samples as emu2413.
- Validation: every mapper against Mesen2 with synthetic-ROM fuzzing, direct testbenches with mutation
  testing and hundreds of real games (frames compared one by one). Known differences are listed in
  `docs/fase4-mappers.md`. **Not yet validated on real hardware.**

## Probar en tu cartucho / Test it on your cartridge

**ES** — En [Releases](https://github.com/LuiskAycardi/OpenFirmware-EverDrive-N8-ChinaVersion/releases)
hay un paquete listo para la microSD (los RBF y un `MAPROUT.BIN`, con instrucciones en `LEEME.md`). Los
resultados, buenos o malos, se agradecen como *issues*. El paquete se genera con `make -C hdl build` y
`python3 -I release/make_release.py vX.Y.Z`.

**EN** — The [Releases](https://github.com/LuiskAycardi/OpenFirmware-EverDrive-N8-ChinaVersion/releases)
page has a package ready for the microSD card (the RBF files and a `MAPROUT.BIN`, with instructions in
`LEEME.md`). Results, good or bad, are very welcome as *issues*. The package is built with
`make -C hdl build` and `python3 -I release/make_release.py vX.Y.Z`.

## Cómo se ha hecho (clean room) / How it was made (clean room)

**ES**
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

**EN**
- The registers and behaviour of each mapper come from the public description (NESdev Wiki) and are
  checked against Mesen2, which acts as the test bench oracle. Mesen2's sources are read to learn
  facts (addresses, bits, order of events), never translated line by line.
- The N8 hardware (FPGA pinout, OS configuration protocol, SD card layout) was obtained by reverse
  engineering; it is documented in `docs/hardware-fpga.md`, `docs/sd-analisis.md` and
  `docs/mappers-n8-oficial.md`.
- Krikzz's public MIT-licensed N8 PRO reference was consulted to understand a few boards; no code was
  copied.

**This repository does not contain** any firmware, OS, RBF or code from Krikzz, nor any ROMs. Using the
RBF files requires an N8 with its own OS and SD card.

## Estructura / Layout

| Carpeta / Folder | Contenido / Contents |
|---|---|
| `hdl/rtl/` | **ES** Diseño: `n8_top.v` (selección de mapper por RBF), mappers, chips de sonido, filtro de A12, DAC. **EN** Design: `n8_top.v` (mapper selection per RBF), mappers, sound chips, A12 filter, DAC. |
| `hdl/sim/` | **ES** Bancos de simulación con iverilog (`make sim`). **EN** iverilog simulation testbenches (`make sim`). |
| `hdl/tools/` | **ES** Generador de proyectos Quartus, `MAPROUT.BIN`, inventarios, pruebas de mutación. **EN** Quartus project generator, `MAPROUT.BIN`, inventories, mutation testing. |
| `hdl/quartus/` | **ES** Plantilla del proyecto Quartus II 13.0sp1 (pines y tiempos). **EN** Quartus II 13.0sp1 project template (pins and timing). |
| `tools/n8sim/` | **ES** Banco Mesen2 + Verilator: el RTL corre dentro de Mesen2 y se compara con su mapper (`difftest.py`, `fuzz/`). **EN** Mesen2 + Verilator bench: the RTL runs inside Mesen2 and is compared with its mapper (`difftest.py`, `fuzz/`). |
| `tools/fm/` | **ES** Oráculo y prueba muestra a muestra del FM del VRC7. **EN** Oracle and sample-exact test of the VRC7 FM. |
| `tools/consola/` | **ES** Pruebas automáticas en la consola real: mando emulado con Arduino, captura de vídeo y comparación. **EN** Automated tests on real hardware: Arduino-emulated controller, video capture and comparison. |
| `tools/pruebas-n8/`, `tools/pagina-pruebas/` | **ES** Plan de pruebas en consola y su página de resultados. **EN** Console test plan and its results page. |
| `release/` | **ES** Empaquetador de los releases e instrucciones para la SD. **EN** Release packager and SD card instructions. |
| `docs/` | **ES** Documentación del hardware, del banco y de cada fase. **EN** Documentation of the hardware, the bench and each phase (in Spanish). |

## Uso / Usage

**ES** — Requisitos: Icarus Verilog, Python 3, Quartus II 13.0sp1 (para los RBF), Verilator y .NET (para
el banco Mesen2).

**EN** — Requirements: Icarus Verilog, Python 3, Quartus II 13.0sp1 (for the RBF files), Verilator and
.NET (for the Mesen2 bench).

```sh
make -C hdl sim                  # ES: todos los bancos de simulación / EN: all simulation testbenches
make -C hdl build                # hdl/out/100.RBF ... 106.RBF (Quartus II 13.0sp1)

tools/mesen2-setup.sh            # ES: clona Mesen2 en la versión fijada y aplica tools/mesen2-n8.patch
                                 # EN: clones Mesen2 at the pinned version and applies tools/mesen2-n8.patch
make -C tools/n8sim mesen        # ES: Mesen2 con el mapper puente / EN: Mesen2 with the bridge mapper
python3 -I tools/n8sim/difftest.py --instancias --clk-auto GAME.nes   # ES: juego real, N8 frente a Mesen2
                                                                      # EN: real game, N8 vs Mesen2
python3 -I tools/n8sim/fuzz/fuzz.py 4 85 --semilla 1                  # ES: fuzz de los mappers 4 y 85
                                                                      # EN: fuzz mappers 4 and 85
```

**ES** — Para usar los RBF en el N8: copiar `hdl/out/1xx.RBF` a `EDFC/MAPS/` de la SD y generar el
`MAPROUT.BIN` con `hdl/tools/gen_maprout.py` (o editar uno existente con `hdl/tools/maprout.py`).

**EN** — To use the RBF files on the N8: copy `hdl/out/1xx.RBF` into the SD card's `EDFC/MAPS/` and
generate `MAPROUT.BIN` with `hdl/tools/gen_maprout.py` (or edit an existing one with
`hdl/tools/maprout.py`).

## Licencia / License

Copyright © 2026 Luis Carlos Aycardi Salgado.

**ES** — Este proyecto es software libre: puedes redistribuirlo y/o modificarlo bajo los términos de la
**GNU General Public License** publicada por la Free Software Foundation, ya sea la **versión 3** de la
licencia o (a tu elección) **cualquier versión posterior** (`SPDX-License-Identifier: GPL-3.0-or-later`).
Se distribuye con la esperanza de que sea útil, pero **sin ninguna garantía**; ni siquiera la garantía
implícita de comerciabilidad o idoneidad para un fin determinado. El texto completo está en `LICENSE`.

**EN** — This project is free software: you can redistribute it and/or modify it under the terms of the
**GNU General Public License** as published by the Free Software Foundation, either **version 3** of
the License, or (at your option) **any later version** (`SPDX-License-Identifier: GPL-3.0-or-later`).
It is distributed in the hope that it will be useful, but **without any warranty**; without even the
implied warranty of merchantability or fitness for a particular purpose. See `LICENSE` for the full
text.

**Terceros / Third parties**

**ES**
- `tools/mesen2-n8.patch` modifica [Mesen2](https://github.com/SourMesen/Mesen2) (GPL-3.0); Mesen2 no
  se incluye, `tools/mesen2-setup.sh` lo descarga.
- `tools/fm/fmref.cpp` enlaza en tiempo de compilación con emu2413 (MIT, Mitsutaka Okazaki), tomado
  del árbol de Mesen2; solo es una herramienta de prueba y no forma parte del diseño.
- `hdl/rtl/vrc7_tables.v` se genera con `tools/fm/gen_vrc7_tables.py` a partir de las fórmulas
  públicas del YM2413 y del juego de instrumentos del VRC7 medido por Nuke.YKT.

**EN**
- `tools/mesen2-n8.patch` modifies [Mesen2](https://github.com/SourMesen/Mesen2) (GPL-3.0); Mesen2 is
  not included, `tools/mesen2-setup.sh` downloads it.
- `tools/fm/fmref.cpp` links at build time against emu2413 (MIT, Mitsutaka Okazaki), taken from the
  Mesen2 tree; it is only a test tool and is not part of the design.
- `hdl/rtl/vrc7_tables.v` is generated by `tools/fm/gen_vrc7_tables.py` from the public YM2413
  formulas and the VRC7 instrument set measured by Nuke.YKT.
