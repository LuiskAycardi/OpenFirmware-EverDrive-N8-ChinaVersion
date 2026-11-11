# OpenFirmware-EverDrive-N8-ChinaVersion — paquete de pruebas / test package {VERSION}

**ES** — Mappers libres (GPL-3.0-or-later) para el **EverDrive N8 China Version** (clon chino con FPGA
EP2C5) de **Famicom y NES**, listos para copiar a la microSD. **Versión de pruebas**: todos los mappers
coinciden con el emulador Mesen2 en el banco de pruebas, pero **casi nada se ha probado aún en la consola
real**. Para eso es este paquete: para que quien tenga uno de estos cartuchos nos ayude a probarlos.

**EN** — Free (GPL-3.0-or-later) mappers for the **EverDrive N8 China Version** (Chinese clone with an
EP2C5 FPGA), **Famicom and NES** cartridges, ready to copy to the microSD card. **Test release**: every
mapper matches the Mesen2 emulator on our test bench, but **almost nothing has been tried on real
hardware yet**. That is what this package is for: so that anyone who owns one of these cartridges can
help us test them.

## Qué contiene / Contents

| Archivo / File | Para qué / Purpose |
|---|---|
| `EDFC/MAPS/100.RBF` … `106.RBF` | **ES** Los mappers (7 archivos; cada uno lleva un grupo de mappers). **EN** The mappers (7 files; each holds a group of mappers). |
| `EDFC/MAPROUT.BIN` | **ES** Tabla que le dice al OS qué RBF usar para cada mapper. **EN** Table telling the OS which RBF to use for each mapper. |
| `MAPPERS.txt` | **ES** Qué mappers hay en cada RBF. **EN** Which mappers each RBF contains. |
| `SHA256SUMS.txt` | **ES** Sumas para comprobar que los archivos llegaron bien. **EN** Checksums to verify the files. |
| `LICENSE` | **ES** Licencia GPL-3.0 (código fuente: commit `{COMMIT}` del repositorio). **EN** GPL-3.0 license (source code: repository commit `{COMMIT}`). |

**ES** — **No contiene** el OS, los RBF de fábrica ni ningún archivo de Krikzz: se usan los que ya tiene
tu SD.

**EN** — It **does not contain** the OS, the factory RBF files or any file from Krikzz: the ones already
on your SD card are used.

## Requisitos / Requirements

**ES**
- **EverDrive N8 China Version** (clon chino con EP2C5, el que se vende con la SD «de fábrica» de un pack
  vietnamita/chino), de Famicom o de NES.
- Su **OS de fábrica**. ⚠️ **No instales los OS oficiales 1.24–1.26 de Krikzz en el clon**: llevan un
  bloqueo contra clones.

**EN**
- **EverDrive N8 China Version** (Chinese EP2C5 clone, the one sold with a "factory" SD card from a
  Vietnamese/Chinese pack), Famicom or NES.
- Its **factory OS**. ⚠️ **Do not install Krikzz's official OS 1.24–1.26 on the clone**: they include a
  lock against clones.

## Instalación / Installation

**ES**
1. **Haz una copia de seguridad de la carpeta `EDFC` de tu microSD** (sobre todo `EDFC/MAPROUT.BIN` y
   `EDFC/SAVE`).
2. Copia `EDFC/MAPS/100.RBF` … `106.RBF` a la carpeta `EDFC/MAPS/` de tu SD. **No borres** los RBF que
   ya están: el OS sigue usando `255.RBF` (el menú) y, para el Famicom Disk System, `254.RBF`.
3. Sustituye `EDFC/MAPROUT.BIN` de tu SD por el de este paquete.
4. Arranca un juego como siempre.

**Para volver atrás**: restaura tu `MAPROUT.BIN` original (los RBF nuevos pueden quedarse, el OS de
fábrica no los usa).

**EN**
1. **Back up the `EDFC` folder of your microSD card** (especially `EDFC/MAPROUT.BIN` and `EDFC/SAVE`).
2. Copy `EDFC/MAPS/100.RBF` … `106.RBF` into your SD card's `EDFC/MAPS/` folder. **Do not delete** the
   RBF files already there: the OS still uses `255.RBF` (the menu) and, for the Famicom Disk System,
   `254.RBF`.
3. Replace your SD card's `EDFC/MAPROUT.BIN` with the one in this package.
4. Start a game as usual.

**To roll back**: restore your original `MAPROUT.BIN` (the new RBF files can stay; the factory OS does
not use them).

## Cosas que conviene saber / Good to know

**ES**
- **Save states**: este paquete no los implementa (la tabla de save states va vacía). Las partidas con
  pila (archivos `.SRM` de `EDFC/SAVE`) sí funcionan como siempre.
- **Sonido de expansión** (VRC6, VRC7, Sunsoft 5B, Namco 163, MMC5): solo se oye en la **Famicom**; la NES
  no mezcla el audio del cartucho.
- **ROMs PAL** (Europe): en una consola NTSC pueden ir rápidas, con basura o colgarse aunque el mapper
  esté bien. Para probar, mejor las versiones USA o Japón.
- **Diferencias conocidas** con el emulador (detalle en `docs/fase4-mappers.md` del repositorio):
  - MMC5 (mapper 5): el modo split vertical tiene limitaciones por el cableado de la SRAM.
  - Mapper 4 (MMC3): ignora la protección de escritura de la PRG-RAM (`$A001`), por compatibilidad con
    el MMC6.
  - Kart Fighter (116): en Mesen2 recibe una IRQ que aquí no llega; puede comportarse distinto.
  - Famicom Jump II (153): se cuelga si su partida empieza a cero (también en el emulador).
  - Varios juegos con efectos de pantalla partida pueden diferir unos pocos píxeles en la línea del corte.
- RBF que **ya se han cargado en la consola real**: 100, 101 y 102 (versiones anteriores). **Nunca
  probados en consola**: 103 (MMC5), 104, 105 y 106 (VRC7 con sonido FM).

**EN**
- **Save states**: not implemented in this package (the save state table is empty). Battery saves
  (`.SRM` files in `EDFC/SAVE`) work as usual.
- **Expansion audio** (VRC6, VRC7, Sunsoft 5B, Namco 163, MMC5): only heard on the **Famicom**; the NES
  does not mix the cartridge audio.
- **PAL ROMs** (Europe): on an NTSC console they may run fast, show garbage or hang even if the mapper is
  fine. For testing, prefer the USA or Japan versions.
- **Known differences** from the emulator (details in the repository's `docs/fase4-mappers.md`):
  - MMC5 (mapper 5): the vertical split mode is limited by the SRAM wiring.
  - Mapper 4 (MMC3): ignores the PRG-RAM write protection (`$A001`), for MMC6 compatibility.
  - Kart Fighter (116): in Mesen2 it receives an IRQ that does not arrive here; it may behave
    differently.
  - Famicom Jump II (153): hangs if its save starts zeroed (also in the emulator).
  - Several games with split-screen effects may differ by a few pixels on the split line.
- RBF files **already loaded on real hardware**: 100, 101 and 102 (earlier versions). **Never tested on
  hardware**: 103 (MMC5), 104, 105 and 106 (VRC7 with FM audio).

## Cómo informar / How to report

**ES** — Abre un *issue* en https://github.com/LuiskAycardi/OpenFirmware-EverDrive-N8-ChinaVersion/issues
con:
- consola (NES / Famicom, NTSC / PAL) y modelo del cartucho;
- juego (nombre exacto de la ROM, mejor de No-Intro) y número de mapper;
- qué pasa: arranca bien, pantalla negra o gris, gráficos rotos, parpadeo, se cuelga, sonido…;
- si con tu SD de fábrica el mismo juego va bien o mal.

Los informes de «funciona bien» también sirven mucho.

**EN** — Open an *issue* at https://github.com/LuiskAycardi/OpenFirmware-EverDrive-N8-ChinaVersion/issues
with:
- console (NES / Famicom, NTSC / PAL) and cartridge model;
- game (exact ROM name, preferably No-Intro) and mapper number;
- what happens: boots fine, black or grey screen, broken graphics, flicker, hang, sound…;
- whether the same game works with your factory SD card.

"Works fine" reports are very useful too.
