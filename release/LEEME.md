# OpenFirmware-EverDrive-N8-ChinaVersion — paquete de pruebas / test package {VERSION}

**ES** — Mappers libres (GPL-3.0-or-later) para el **EverDrive N8 China Version** (clon chino con FPGA
EP2C5) de **Famicom y NES**, listos para copiar a la microSD, y **nuestro primer OS propio**, experimental.
**Versión de pruebas**: todos los mappers coinciden con el emulador Mesen2 en el banco de pruebas y una parte
se ha probado en una NES real. Este paquete es para que quien tenga uno de estos cartuchos nos ayude a
probarlos.

**EN** — Free (GPL-3.0-or-later) mappers for the **EverDrive N8 China Version** (Chinese clone with an
EP2C5 FPGA), **Famicom and NES** cartridges, ready to copy to the microSD card, and **our first own OS**,
experimental. **Test release**: every mapper matches the Mesen2 emulator on our test bench and part of them
have been tried on a real NES. This package is for anyone who owns one of these cartridges to help us test
them.

## Qué contiene / Contents

| Archivo / File | Para qué / Purpose |
|---|---|
| `EDFC/MAPS/100.RBF` … `106.RBF` | **ES** Los mappers (7 archivos; cada uno lleva un grupo de mappers). **EN** The mappers (7 files; each holds a group of mappers). |
| `EDFC/MAPROUT.BIN` | **ES** Tabla que le dice al OS qué RBF usar para cada mapper. **EN** Table telling the OS which RBF to use for each mapper. |
| `OS-propio/OS.BIN` | **ES** Nuestro OS propio, experimental y **opcional** (ver más abajo). **EN** Our own OS, experimental and **optional** (see below). |
| `MAPPERS.txt` | **ES** Qué mappers hay en cada RBF. **EN** Which mappers each RBF contains. |
| `SHA256SUMS.txt` | **ES** Sumas para comprobar que los archivos llegaron bien. **EN** Checksums to verify the files. |
| `LICENSE` | **ES** Licencia GPL-3.0 (código fuente: commit `{COMMIT}` del repositorio). **EN** GPL-3.0 license (source code: repository commit `{COMMIT}`). |

**ES** — **No contiene** el OS de fábrica, los RBF de fábrica ni ningún archivo de Krikzz: se usan los que
ya tiene tu SD.

**EN** — It **does not contain** the factory OS, the factory RBF files or any file from Krikzz: the ones
already on your SD card are used.

## Requisitos / Requirements

**ES**
- **EverDrive N8 China Version, versión NO-PRO** (clon chino con FPGA Cyclone II EP2C5, el que se vende
  con la SD «de fábrica» de un pack vietnamita/chino), de Famicom o de NES. **No sirve para el EverDrive
  N8 PRO.** Placas usadas en el desarrollo (etiqueta serigrafiada en el circuito impreso):
  - NES (72 pines): `V2.0 2025-1`, `WB211982`.
  - Famicom (60 pines): `V3.1 2024.07`.
- Su **OS de fábrica**. ⚠️ **No instales los OS oficiales 1.24–1.26 de Krikzz en el clon**: llevan un
  bloqueo contra clones.

**EN**
- **EverDrive N8 China Version, NON-PRO version** (Chinese clone with a Cyclone II EP2C5 FPGA, the one
  sold with a "factory" SD card from a Vietnamese/Chinese pack), Famicom or NES. **It does not work on
  the EverDrive N8 PRO.** Boards used during development (label printed on the circuit board):
  - NES (72 pins): `V2.0 2025-1`, `WB211982`.
  - Famicom (60 pins): `V3.1 2024.07`.
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

## OS propio (opcional, experimental) / Own OS (optional, experimental)

**ES** — `OS-propio/OS.BIN` es nuestro primer OS, escrito desde cero. **No hace falta para usar los RBF**: con
el OS de fábrica funcionan igual (salvo el mapper 219, ver abajo).
- **Qué hace:** arranca desde la BIOS del cartucho, lee la microSD (solo lectura), muestra la raíz y lanza los
  juegos de la raíz con nuestros RBF. El botón RESET vuelve al menú con el cursor sobre el juego.
- **Qué no hace todavía:** carpetas, nombres largos (se ven los cortos, `SUPERM~1.NES`), partidas con pila,
  save states ni FDS. Una ROM de 384 KiB se carga en unos 3,8 s.
- **Probado** en una NES real: Super Mario Bros. y Super Mario Bros. 3.
- **Instalación:**
  1. Haz copia de tu carpeta `EDFC`.
  2. Renombra el `EDFC/OS.BIN` de tu SD a `EDFC/OS_V13.BIN`.
  3. Copia `OS-propio/OS.BIN` como `EDFC/OS.BIN`. El archivo tiene que quedar contiguo en la tarjeta: lo más
     seguro es usar una SD recién formateada. Si al encender la pantalla sale negra, es lo primero que hay
     que mirar.
  4. Necesita el `EDFC/MAPS/255.RBF` de fábrica, que no se toca.
- **Para volver al OS de fábrica:** borra `EDFC/OS.BIN` y renombra `EDFC/OS_V13.BIN` a `EDFC/OS.BIN`.
- **Con este OS no uses juegos con partida guardada que te importe:** todavía no guarda las partidas.

**EN** — `OS-propio/OS.BIN` is our first own OS, written from scratch. **It is not needed to use the RBF
files**: they work the same with the factory OS (except mapper 219, see below).
- **What it does:** it boots from the cartridge BIOS, reads the microSD card (read-only), shows the root
  folder and launches the games in it with our RBF files. The RESET button returns to the menu with the cursor
  on the game.
- **What it does not do yet:** folders, long file names (short names such as `SUPERM~1.NES` are shown),
  battery saves, save states or FDS. A 384 KiB ROM loads in about 3.8 s.
- **Tested** on a real NES: Super Mario Bros. and Super Mario Bros. 3.
- **Installation:**
  1. Back up your `EDFC` folder.
  2. Rename your SD card's `EDFC/OS.BIN` to `EDFC/OS_V13.BIN`.
  3. Copy `OS-propio/OS.BIN` as `EDFC/OS.BIN`. The file must be contiguous on the card: the safest way is a
     freshly formatted SD card. If the screen stays black at power-on, check this first.
  4. It needs the factory `EDFC/MAPS/255.RBF`, which is left untouched.
- **To go back to the factory OS:** delete `EDFC/OS.BIN` and rename `EDFC/OS_V13.BIN` to `EDFC/OS.BIN`.
- **Do not use games with a save you care about with this OS:** it does not save battery games yet.

## Cosas que conviene saber / Good to know

**ES**
- **Mapper 219 (Toy Story) y el OS de fábrica:** los RBF reciben ahora el número de mapper tal cual está en la
  cabecera de la ROM. El OS de fábrica cambia el 219 por 0 antes de pasarlo al FPGA, así que **con el OS de
  fábrica el 219 vuelve a no arrancar** (en v0.1.3 el RBF deshacía ese cambio). Con el OS propio el número
  llega bien, pero aún no se ha probado en la consola. Si necesitas Toy Story con el OS de fábrica, usa el
  `105.RBF` de v0.1.3.
- **Save states**: este paquete no los implementa (la tabla de save states va vacía). Con el OS de fábrica,
  las partidas con pila (archivos `.SRM` de `EDFC/SAVE`) sí funcionan como siempre.
- **Sonido de expansión** (VRC6, VRC7, Sunsoft 5B, Namco 163, MMC5): solo se oye en la **Famicom**; la NES
  no mezcla el audio del cartucho.
- **ROMs PAL** (Europe): en una consola NTSC pueden ir rápidas, con basura o colgarse aunque el mapper
  esté bien. Para probar, mejor las versiones USA o Japón.
- **Diferencias conocidas** con el emulador (detalle en `docs/fase4-mappers.md` del repositorio):
  - MMC5 (mapper 5): el modo split vertical tiene limitaciones por el cableado de la SRAM.
  - Kart Fighter (116): en Mesen2 recibe una IRQ que aquí no llega; puede comportarse distinto.
  - Famicom Jump II (153): se cuelga si su partida empieza a cero (también en el emulador).
  - Varios juegos con efectos de pantalla partida pueden diferir unos pocos píxeles en la línea del corte.
- **Hardware real**: ya hay un banco de pruebas automático con una **NES NTSC real** (mando emulado,
  capturadora y películas TAS de TASVideos comparadas escena a escena con Mesen2). Películas completas
  verificadas, sin perder la sincronización: Super Mario Bros. (0), Nuts & Milk (0), Rainbow Islands (2),
  Fire 'n Ice (4), Wizards & Warriors III (7) y Metal Force (156); además, tramos de Mighty Bomb Jack (3),
  Captain Comic (11), Plummet/Arm Wrestling (30), Solitaire (79) y Goonies (87), y la IRQ del mapper 65
  medida con una ROM de prueba (idéntica a Mesen2). Fire 'n Ice se repitió con el `100.RBF` de la v0.1.2
  (protección de `$A001`): 40 de 40 escenas iguales a Mesen2. **RBF 103 a 106** (2026-11-15/16): 39 juegos
  NTSC elegidos por cobertura, 20 segundos cada uno con botones de guion. Arrancan y coinciden con Mesen2
  los del MMC5 (5), 56, 91, 105, 111, 117, 222, 234, 35, 59, 83, 90, 114, 116, 121, 176, 194, 209, 211,
  215, 219 y el VRC7 (85). En los juegos de lucha la pelea puede seguir otro camino por unos fotogramas de
  diferencia. Los fallos que salieron (35, 176 y 219) se corrigieron en v0.1.3; el arreglo del 219 se ha
  retirado en esta versión (ver arriba).

**EN**
- **Mapper 219 (Toy Story) and the factory OS:** the RBF files now get the mapper number exactly as written
  in the ROM header. The factory OS turns 219 into 0 before passing it to the FPGA, so **with the factory OS,
  mapper 219 no longer boots** (in v0.1.3 the RBF undid that change). With our own OS the number arrives
  correctly, but this has not been tested on the console yet. If you need Toy Story with the factory OS, use
  v0.1.3's `105.RBF`.
- **Save states**: not implemented in this package (the save state table is empty). With the factory OS,
  battery saves (`.SRM` files in `EDFC/SAVE`) work as usual.
- **Expansion audio** (VRC6, VRC7, Sunsoft 5B, Namco 163, MMC5): only heard on the **Famicom**; the NES
  does not mix the cartridge audio.
- **PAL ROMs** (Europe): on an NTSC console they may run fast, show garbage or hang even if the mapper is
  fine. For testing, prefer the USA or Japan versions.
- **Known differences** from the emulator (details in the repository's `docs/fase4-mappers.md`):
  - MMC5 (mapper 5): the vertical split mode is limited by the SRAM wiring.
  - Kart Fighter (116): in Mesen2 it receives an IRQ that does not arrive here; it may behave
    differently.
  - Famicom Jump II (153): hangs if its save starts zeroed (also in the emulator).
  - Several games with split-screen effects may differ by a few pixels on the split line.
- **Real hardware**: there is now an automated test bench with a **real NTSC NES** (emulated
  controller, capture card and TASVideos TAS movies compared scene by scene against Mesen2). Full movies
  verified without losing sync: Super Mario Bros. (0), Nuts & Milk (0), Rainbow Islands (2), Fire 'n Ice
  (4), Wizards & Warriors III (7) and Metal Force (156); plus stretches of Mighty Bomb Jack (3), Captain
  Comic (11), Plummet/Arm Wrestling (30), Solitaire (79) and Goonies (87), and the mapper 65 IRQ measured
  with a test ROM (identical to Mesen2). Fire 'n Ice was rerun with v0.1.2's `100.RBF` (`$A001`
  protection): 40 out of 40 scenes match Mesen2. **RBF 103 to 106** (2026-11-15/16): 39 NTSC games picked
  by coverage, 20 seconds each with scripted buttons. The MMC5 (5), 56, 91, 105, 111, 117, 222, 234, 35, 59,
  83, 90, 114, 116, 121, 176, 194, 209, 211, 215, 219 and VRC7 (85) games boot and match Mesen2. In
  fighting games the fight may take another path because of a few frames of difference. The failures found
  (35, 176 and 219) were fixed in v0.1.3; the 219 fix has been removed in this release (see above).

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
