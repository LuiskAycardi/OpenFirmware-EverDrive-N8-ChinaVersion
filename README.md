# OpenFirmware-EverDrive-N8-ChinaVersion

**ES** — **Firmware libre completo** para el **EverDrive N8 China Version** (el clon chino del EverDrive N8, con
FPGA **Altera Cyclone II EP2C5**), en sus dos versiones: **Famicom y NES**. Todo lo que el cartucho lee de la microSD
sale de aquí: un **OS propio** (menú, partidas con pila, Famicom Disk System), el RBF del menú y **195 mappers** en
Verilog. Implementación clean room, validada contra el emulador Mesen2 con fuzz de ROMs sintéticas, bancos de
simulación y juegos reales en la consola.

**EN** — **Complete free firmware** for the **EverDrive N8 China Version** (the Chinese clone of the EverDrive N8,
built around an **Altera Cyclone II EP2C5** FPGA), for both cartridge versions: **Famicom and NES**. Everything the
cartridge reads from the microSD card comes from here: **our own OS** (menu, battery saves, Famicom Disk System), the
menu RBF and **195 mappers** in Verilog. Clean-room implementation, validated against the Mesen2 emulator with
synthetic-ROM fuzzing, simulation testbenches and real games on the console.

> 💾 **ES — Novedad (25-11-2026): v0.6.3-beta, partidas de los juegos con EEPROM.** Los Bandai que guardan en una
> EEPROM serie (mappers 16, 159 y 157 Datach: Dragon Ball Z, SD Gundam Gaiden…) ya guardan su partida en la microSD,
> en el mismo formato que Mesen2. Probado en una Famicom y en una NES reales. Sal con RESET antes de apagar.
>
> 💾 **EN — News (25 Nov 2026): v0.6.3-beta, saves for games with an EEPROM.** The Bandai games that save to a serial
> EEPROM (mappers 16, 159 and 157 Datach: Dragon Ball Z, SD Gundam Gaiden…) now save to the microSD card, in the same
> format as Mesen2. Tested on a real Famicom and a real NES. Leave with RESET before switching off.
>
> 🎚️ **ES — Novedad (25-11-2026): v0.6.2-beta, volumen calibrado en una Famicom.** Con ROMs de prueba propias y el
> audio grabado de una Famicom AV, cada chip de sonido del cartucho suena frente al de la consola como en Mesen2 (a
> menos de un 2 %). Además, el reset del kit Lava RGB al salir de un disco FDS ya no se repite sin fin.
>
> 🎚️ **EN — News (25 Nov 2026): v0.6.2-beta, volume calibrated on a Famicom.** With our own test ROMs and audio
> recorded from a Famicom AV, each cartridge sound chip now sounds against the console's own sound as in Mesen2
> (within 2 %). Also, the Lava RGB kit reset when leaving an FDS disk no longer repeats endlessly.
>
> 🔊 **ES — Novedad (24-11-2026): v0.6.1-beta, volumen del sonido de expansión.** Select+Start en el menú abre
> «Opciones»: el volumen del sonido del cartucho (FDS, VRC6, VRC7, 5B, N163, MMC5) de −4 a +4, guardado con pila. Los
> mappers se repartieron para que ningún RBF pase del 85 % del FPGA. Probado en una NES real.
>
> 🔊 **EN — News (24 Nov 2026): v0.6.1-beta, expansion audio volume.** Select+Start in the menu opens «Opciones»:
> the cartridge sound volume (FDS, VRC6, VRC7, 5B, N163, MMC5) from −4 to +4, kept in battery-backed memory. Mappers
> were redistributed so that no RBF uses more than 85 % of the FPGA. Tested on a real NES.
>
> 💿 **ES — Novedad (noviembre de 2026): v0.6.0-beta, Famicom Disk System.** El OS lanza imágenes `.fds` con tu
> propia BIOS FDS (`EDFC/DISKSYS.ROM`, no se distribuye): cambia de cara solo, guarda lo que el juego escribe en el
> disco al volver con RESET y, cuando las dos caras tienen el mismo ID, se cambia a mano con B + Select. Con el
> sonido del FDS (en la Famicom). Probado en una NES real con 7 juegos (Zelda, Metroid, Doki Doki Panic…). Descárgala
> en [Releases](https://github.com/LuiskAycardi/OpenFirmware-EverDrive-N8-ChinaVersion/releases).
>
> 💿 **EN — News (November 2026): v0.6.0-beta, Famicom Disk System.** The OS launches `.fds` images with your own
> FDS BIOS (`EDFC/DISKSYS.ROM`, not distributed): it switches sides by itself, saves what the game writes to the
> disk when you go back with RESET and, when both sides have the same ID, you switch by hand with B + Select. With
> the FDS sound (on the Famicom). Tested on a real NES with 7 games (Zelda, Metroid, Doki Doki Panic…). Download it
> from [Releases](https://github.com/LuiskAycardi/OpenFirmware-EverDrive-N8-ChinaVersion/releases).
>
> 🗂️ **ES — Novedad (noviembre de 2026): v0.5.1-beta, menú ordenado y modo banco.** Lista en orden alfabético
> (carpetas primero) con la entrada elegida en rojo, información del juego bajo el cursor, ◀▶ para cambiar de página
> y Select+◀▶ para saltar de letra, y al encender vuelve al último juego. Además, un modo banco para las pruebas
> automáticas en la consola (`tools/consola`). Descárgala en
> [Releases](https://github.com/LuiskAycardi/OpenFirmware-EverDrive-N8-ChinaVersion/releases).
>
> 🗂️ **EN — News (November 2026): v0.5.1-beta, sorted menu and test-bench mode.** Alphabetical list (folders first)
> with the selected entry in red, game information under the cursor, ◀▶ to change page and Select+◀▶ to jump by
> letter, and at power-on it goes back to the last game. Plus a test-bench mode for automated console tests
> (`tools/consola`). Download it from
> [Releases](https://github.com/LuiskAycardi/OpenFirmware-EverDrive-N8-ChinaVersion/releases).
>
> 💾 **ES — Novedad (noviembre de 2026): v0.5.0-beta, partidas con pila.** Nuestro OS guarda las partidas en
> `EDFC/SAVE/<nombre>.srm` (el formato `.sav` de los emuladores) al volver al menú con RESET y también si apagas
> dentro del juego. Probado en una NES real con Zelda. Descárgala en
> [Releases](https://github.com/LuiskAycardi/OpenFirmware-EverDrive-N8-ChinaVersion/releases).
>
> 💾 **EN — News (November 2026): v0.5.0-beta, battery saves.** Our OS saves games to `EDFC/SAVE/<name>.srm`
> (the emulator `.sav` format) when you go back to the menu with RESET and also if you switch off inside the
> game. Tested on a real NES with Zelda. Download it from
> [Releases](https://github.com/LuiskAycardi/OpenFirmware-EverDrive-N8-ChinaVersion/releases).
>
> 🚀 **ES — Novedad (noviembre de 2026): primera compilación completa propia (beta).** Nuestro OS, nuestro
> `255.RBF` y nuestros mappers: en la microSD ya no hace falta **ningún archivo de Krikzz ni de fábrica**; del
> cartucho solo se usa su BIOS, que no se toca. Descárgala en
> [Releases](https://github.com/LuiskAycardi/OpenFirmware-EverDrive-N8-ChinaVersion/releases) y sigue su
> `LEEME.md` (copia de seguridad, formato FAT32 con clúster de 32 KB y copia).
>
> 🚀 **EN — News (November 2026): first complete own build (beta).** Our OS, our `255.RBF` and our mappers:
> the microSD card no longer needs **any file from Krikzz or from the factory**; only the cartridge's BIOS is
> used, and it is left untouched. Download it from
> [Releases](https://github.com/LuiskAycardi/OpenFirmware-EverDrive-N8-ChinaVersion/releases) and follow its
> `LEEME.md` (backup, FAT32 format with 32 KB clusters and copy).
>
> 🎉 **ES — Novedad (noviembre de 2026): ya tenemos nuestro primer `OS.BIN` propio funcional.** Arranca
> desde la BIOS del cartucho, lee la microSD, recorre sus carpetas con nombres largos y **lanza juegos con nuestros RBF**: Super Mario
> Bros. y Super Mario Bros. 3 funcionan en una NES real, y el botón RESET vuelve al menú con el cursor sobre
> el juego. Es una versión temprana y experimental; ver [OS propio](#os-propio--own-os).
>
> 🎉 **EN — News (November 2026): we now have our first working `OS.BIN` of our own.** It boots from the
> cartridge BIOS, reads the microSD card, browses its folders with long file names and **launches games with our RBF files**:
> Super Mario Bros. and Super Mario Bros. 3 run on a real NES, and the RESET button returns to the menu with
> the cursor on the game. It is an early, experimental version; see [Own OS](#os-propio--own-os).

> **ES** — Proyecto independiente: no está afiliado a Krikzz ni a EverDrive, ni respaldado por ellos.
> «EverDrive» es una marca de su autor. Este README está en español e inglés; el resto de la
> documentación (`docs/`) está en español.
>
> **EN** — Independent project: not affiliated with or endorsed by Krikzz or EverDrive. "EverDrive" is
> a trademark of its owner. This README is in Spanish and English; the rest of the documentation
> (`docs/`) is in Spanish.

## Estado / Status

**ES**
- **195 mappers**: los 178 del firmware oficial 1.26 (desde la v0.6.0 también el **Famicom Disk System**, 254) y 17
  más (46, 59, 83, 114, 116, 121, 153, 155, 157, 159, 192, 194, 195, 209, 210, 215, 253).
- Siete RBF (`100.RBF`–`106.RBF`) que el OS carga según `MAPROUT.BIN`; cada uno cabe con holgura en
  el EP2C5 y cumple tiempos a 50 MHz.
- Sonido de expansión: VRC6, Sunsoft 5B, Namco 163, MMC5 y **VRC7 (FM)**, un sintetizador propio que
  da exactamente las mismas muestras que emu2413.
  Su volumen se cambia en el menú (Select+Start, «Opciones», de −4 a +4; ver `docs/sonido-volumen.md`).
- Validación: todos contra Mesen2 con el fuzz de ROMs sintéticas, bancos directos con pruebas de
  mutación y cientos de juegos reales (fotogramas comparados uno a uno). Las diferencias conocidas
  están en `docs/fase4-mappers.md`.
- **Hardware real**: hay un **banco de pruebas automático con una NES NTSC real** (mando emulado con un
  Arduino Nano, reset por cable, capturadora de vídeo y películas TAS de TASVideos comparadas escena a
  escena con Mesen2; ver `tools/consola/README.md`). Películas completas sin perder la
  sincronización: Super Mario Bros. y Nuts & Milk (0), Rainbow Islands (2), Fire 'n Ice (4),
  Wizards & Warriors III (7) y Metal Force (156); además, tramos de los mappers 3, 11, 30, 79 y 87 y la
  IRQ del 65 medida con una ROM de prueba. **Los RBF 103 a 106** también se han probado en la consola: 39
  juegos NTSC elegidos por cobertura, 20 segundos cada uno (MMC5, VRC7 y los mappers 35, 56, 59, 83, 90, 91,
  105, 111, 114, 116, 117, 121, 176, 194, 209, 211, 215, 219, 222 y 234). Más a fondo (jugando y con sus
  partidas): seis juegos MMC5 (`docs/mmc5-validacion.md`) y Kart Fighter y Somari (116), que en la consola van
  bien aunque Kart Fighter difiere en Mesen2. El resto de mappers solo se ha validado en el emulador.
- **RBF limpios**: cada RBF recibe el número de mapper tal cual está en la cabecera de la ROM. El OS v13 de
  fábrica cambia el 219 por 0 y el 220 por 4; hasta noviembre de 2026 el RTL deshacía ese cambio, y ya no.
  Con el OS de fábrica, el 219 (Toy Story) vuelve a no funcionar; con el OS propio sí debería, aunque no se ha
  probado en la consola.
- **OS propio** (`os/`): primera versión funcional, probada en la NES real. Ver
  [OS propio](#os-propio--own-os).

**EN**
- **195 mappers**: the 178 of the official 1.26 firmware (since v0.6.0 also the **Famicom Disk System**, 254) plus
  17 more (46, 59, 83, 114, 116, 121, 153, 155, 157, 159, 192, 194, 195, 209, 210, 215, 253).
- Seven RBF files (`100.RBF`–`106.RBF`) that the OS loads according to `MAPROUT.BIN`; each one fits in
  the EP2C5 with room to spare and meets timing at 50 MHz.
- Expansion audio: VRC6, Sunsoft 5B, Namco 163, MMC5 and **VRC7 (FM)**, our own synthesizer that
  produces exactly the same samples as emu2413.
  Its volume is set in the menu (Select+Start, «Opciones», −4 to +4; see `docs/sonido-volumen.md`).
- Validation: every mapper against Mesen2 with synthetic-ROM fuzzing, direct testbenches with mutation
  testing and hundreds of real games (frames compared one by one). Known differences are listed in
  `docs/fase4-mappers.md`.
- **Real hardware**: there is an **automated test bench with a real NTSC NES** (controller emulated
  by an Arduino Nano, wired reset, video capture and TASVideos TAS movies compared scene by scene
  against Mesen2; see `tools/consola/README.md`). Full movies without losing sync:
  Super Mario Bros. and Nuts & Milk (0), Rainbow Islands (2), Fire 'n Ice (4), Wizards & Warriors III
  (7) and Metal Force (156); plus stretches of mappers 3, 11, 30, 79 and 87 and the mapper 65 IRQ
  measured with a test ROM. **RBF 103 to 106** have been tested on the console too: 39 NTSC games picked by
  coverage, 20 seconds each (MMC5, VRC7 and mappers 35, 56, 59, 83, 90, 91, 105, 111, 114, 116, 117, 121,
  176, 194, 209, 211, 215, 219, 222 and 234). In more depth (playing, with their saves): six MMC5 games
  (`docs/mmc5-validacion.md`) and Kart Fighter and Somari (116), which work on the console although Kart Fighter
  differs in Mesen2. The remaining mappers have only been validated in the emulator.
- **Clean RBF files**: each RBF gets the mapper number exactly as written in the ROM header. The factory OS
  v13 turns 219 into 0 and 220 into 4; until November 2026 the RTL undid that change, and it no longer does.
  With the factory OS, mapper 219 (Toy Story) fails again; with our own OS it should work, although it has
  not been tested on the console.
- **Own OS** (`os/`): first working version, tested on a real NES. See [Own OS](#os-propio--own-os).

## Cartucho compatible / Supported cartridge

**ES** — Estos mappers están hechos para la versión **NO-PRO** del cartucho chino: el **EverDrive N8
China Version** con FPGA **Altera Cyclone II EP2C5T144C8** y CPLD Altera MAX II. **No sirven para el
EverDrive N8 PRO**, que usa otro hardware. Placas en las que se ha desarrollado
(etiquetas serigrafiadas en el circuito impreso):

**EN** — These mappers are made for the **NON-PRO** version of the Chinese cartridge: the **EverDrive N8
China Version** with an **Altera Cyclone II EP2C5T144C8** FPGA and an Altera MAX II CPLD. **They do not
work on the EverDrive N8 PRO**, which uses different hardware. Boards used during
development (labels printed on the circuit board):

| Cartucho / Cartridge | Conector / Connector | Etiqueta de la placa / Board label |
|---|---|---|
| NES | 72 pines / 72 pins | `V2.0 2025-1`, `WB211982` |
| Famicom | 60 pines / 60 pins | `V3.1 2024.07` |

**ES** — Otras revisiones de placa con la misma FPGA EP2C5 probablemente funcionen; si tienes una
distinta, cuéntanos en un *issue* la etiqueta de tu placa y el resultado.

**EN** — Other board revisions with the same EP2C5 FPGA will probably work; if yours is different,
please tell us its board label and your results in an *issue*.

## Probar en tu cartucho / Test it on your cartridge

> **ES** — **No hace falta compilar nada.** Descarga la compilación completa desde
> [Releases](https://github.com/LuiskAycardi/OpenFirmware-EverDrive-N8-ChinaVersion/releases) y sigue el
> `LEEME.md` del paquete: **copia de seguridad completa de tu SD**, formato **FAT32 con clúster de 32 KB** y
> copia de la carpeta `EDFC` del paquete (la primera) y de tus juegos. Para seguir con el OS de fábrica y usar
> solo nuestros mappers, el paquete anterior es la v0.3.0.
>
> **EN** — **You don't need to build anything.** Download the complete build from
> [Releases](https://github.com/LuiskAycardi/OpenFirmware-EverDrive-N8-ChinaVersion/releases) and follow the
> package's `LEEME.md`: **full backup of your SD card**, **FAT32 format with 32 KB clusters** and copy the
> package's `EDFC` folder (first) and your games. To keep the factory OS and use only our mappers, the previous
> package is v0.3.0.

**ES** — En [Releases](https://github.com/LuiskAycardi/OpenFirmware-EverDrive-N8-ChinaVersion/releases)
hay un paquete listo para la microSD: la carpeta `EDFC` completa (OS, `255.RBF`, mappers y `MAPROUT.BIN`), con
instrucciones en `LEEME.md`. Los resultados, buenos o malos, se agradecen como *issues*. El paquete se genera
con `make -C hdl build`, `make -C os` y `python3 -I release/make_release.py vX.Y.Z`.

**EN** — The [Releases](https://github.com/LuiskAycardi/OpenFirmware-EverDrive-N8-ChinaVersion/releases)
page has a package ready for the microSD card: the whole `EDFC` folder (OS, `255.RBF`, mappers and
`MAPROUT.BIN`), with instructions in `LEEME.md`. Results, good or bad, are very welcome as *issues*. The package
is built with `make -C hdl build`, `make -C os` and `python3 -I release/make_release.py vX.Y.Z`.

## OS propio / Own OS

**ES** — `os/` es un `OS.BIN` escrito desde cero en ensamblador 6502 (ca65), con licencia GPL-3.0-or-later.
Ocupa el lugar del `EDFC/OS.BIN` de fábrica. La BIOS del cartucho se sigue usando y no se toca. El `255.RBF`
(el RBF que la BIOS carga al encender) puede ser el de fábrica o **el nuestro** (`hdl/out/255.RBF`, solo el
modo OS, probado en la NES): con el nuestro no queda en la SD ningún archivo de Krikzz, pero el OS de fábrica
deja de arrancar.

Qué hace hoy:
- Arranca desde la BIOS y distingue el encendido, un reset en el menú y la vuelta desde un juego. Aguanta el
  botón RESET y el reset por mando del kit Lava RGB.
- Lee la microSD con un controlador propio: FAT16 y FAT32, SDHC y SDSC, con o sin MBR. Solo escribe las partidas.
- Recorre las carpetas de la tarjeta (16 entradas por página; A entra, B vuelve) y muestra los nombres largos con una
  fuente propia, pensada para televisores CRT y con caracteres españoles.
- **Lanza juegos**: lee la cabecera iNES, busca el RBF en `EDFC/MAPROUT.BIN`, carga el RBF en el FPGA, copia la
  PRG y la CHR y salta al juego con el número de mapper de la cabecera, sin traducirlo.

- **Partidas con pila** (desde la v0.5.0-beta): `EDFC/SAVE/<nombre de la ROM>.srm`, el mismo formato
  que el `.sav` de los emuladores. Se cargan al lanzar el juego y se guardan al volver al menú con RESET (o en el
  siguiente encendido).

Carga rápida: SMB3 (384 KiB) se carga en unos 3,8 s (antes 9,5 s).

- **Menú ordenado** (desde la v0.5.1-beta): orden alfabético con las carpetas primero, información del
  juego bajo el cursor (mapper, tamaños, pila), la entrada seleccionada en rojo, ◀▶ cambia de página, Select+◀▶
  salta de letra en letra y, al encender, vuelve al último juego.

Qué falta: modo banco y CRC del juego. **Es experimental**: pruébalo en una microSD de pruebas.

Para probarlo:
1. `make -C os` (necesita cc65 y Python 3).
2. En la microSD, renombra el `EDFC/OS.BIN` de fábrica a `EDFC/OS_V13.BIN` y copia `os/build/OS.BIN` en su
   lugar. Para volver al OS de fábrica, deshaz el cambio.
3. El archivo tiene que quedar **contiguo** en la tarjeta: lo más seguro es copiarlo en una tarjeta recién
   formateada.

Detalles en `os/LEEME.md`. La BIOS y el arranque están estudiados en `docs/bios-n8-clon.md` y
`docs/os-propio-viabilidad.md`. `tools/bios/` es un emulador propio del cartucho que ejecuta la BIOS real (a
partir de un volcado de la BIOS, que no está en el repositorio) para probar el OS en el PC antes de llevarlo a
la consola.

**EN** — `os/` is an `OS.BIN` written from scratch in 6502 assembly (ca65), licensed GPL-3.0-or-later. It
replaces the factory `EDFC/OS.BIN`. The cartridge BIOS is still used and left untouched. The `255.RBF` (the
RBF the BIOS loads at power-on) can be the factory one or **ours** (`hdl/out/255.RBF`, OS mode only, tested on
a NES): with ours no file from Krikzz is left on the SD card, but the factory OS no longer boots.

What it does today:
- It boots from the BIOS and tells apart a power-on, a reset in the menu and a return from a game. It handles
  the RESET button and the Lava RGB kit's controller reset.
- It reads the microSD card with its own driver: FAT16 and FAT32, SDHC and SDSC, with or without an MBR. The
  only thing it writes is saved games.
- It browses the card's folders (16 entries per page; A enters, B goes back) and shows long file names with its
  own font, designed for CRT TVs and with Spanish characters.
- **It launches games**: it reads the iNES header, looks up the RBF in `EDFC/MAPROUT.BIN`, loads the RBF into
  the FPGA, copies the PRG and CHR data and jumps to the game with the header's mapper number, untranslated.

- **Battery saves** (since v0.5.0-beta): `EDFC/SAVE/<ROM name>.srm`, the same format as emulator `.sav`
  files. They are loaded when the game starts and saved when you go back to the menu with RESET (or at the next
  power-on).

Fast loading: SMB3 (384 KiB) loads in about 3.8 s (it used to take 9.5 s).

- **Sorted menu** (since v0.5.1-beta): alphabetical order with folders first, game information under the
  cursor (mapper, sizes, battery), the selected entry in red, ◀▶ changes page, Select+◀▶ jumps from letter to letter
  and, at power-on, it goes back to the last game.

Still missing: test-bench mode and the game CRC. **It is experimental**: try it on a spare microSD card.

To try it:
1. `make -C os` (needs cc65 and Python 3).
2. On the microSD card, rename the factory `EDFC/OS.BIN` to `EDFC/OS_V13.BIN` and copy `os/build/OS.BIN` in
   its place. To go back to the factory OS, undo the change.
3. The file must end up **contiguous** on the card: the safest way is to copy it to a freshly formatted card.

Details are in `os/LEEME.md`. The BIOS and the boot process are studied in `docs/bios-n8-clon.md` and
`docs/os-propio-viabilidad.md`. `tools/bios/` is our own emulator of the cartridge that runs the real BIOS
(from a BIOS dump, which is not in the repository) so the OS can be tested on the PC before going to the
console.

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
- Para el OS propio, la BIOS del cartucho y el OS v13 se han estudiado en local (ejecutándolos en un emulador y
  leyendo su comportamiento) solo para conocer la interfaz con el hardware. El OS propio está escrito desde
  cero: no lleva código, tablas ni la fuente de Krikzz.

**Este repositorio no contiene** ningún firmware, BIOS, OS, RBF ni código de Krikzz, ni ROMs. Para usar los
RBF hace falta un N8 con su BIOS y su tarjeta SD; el OS y el `255.RBF` pueden ser los de fábrica o los
nuestros.

**EN**
- The registers and behaviour of each mapper come from the public description (NESdev Wiki) and are
  checked against Mesen2, which acts as the test bench oracle. Mesen2's sources are read to learn
  facts (addresses, bits, order of events), never translated line by line.
- The N8 hardware (FPGA pinout, OS configuration protocol, SD card layout) was obtained by reverse
  engineering; it is documented in `docs/hardware-fpga.md`, `docs/sd-analisis.md` and
  `docs/mappers-n8-oficial.md`.
- Krikzz's public MIT-licensed N8 PRO reference was consulted to understand a few boards; no code was
  copied.
- For our own OS, the cartridge BIOS and the OS v13 were studied locally (running them in an emulator and
  observing their behaviour) only to learn the hardware interface. Our OS is written from scratch: it
  contains no code, tables or font from Krikzz.

**This repository does not contain** any firmware, BIOS, OS, RBF or code from Krikzz, nor any ROMs. Using
the RBF files requires an N8 with its BIOS and its SD card; the OS and the `255.RBF` can be the factory ones
or ours.

## Estructura / Layout

| Carpeta / Folder | Contenido / Contents |
|---|---|
| `hdl/rtl/` | **ES** Diseño: `n8_top.v` (selección de mapper por RBF), mappers, chips de sonido, filtro de A12, DAC. **EN** Design: `n8_top.v` (mapper selection per RBF), mappers, sound chips, A12 filter, DAC. |
| `hdl/sim/` | **ES** Bancos de simulación con iverilog (`make sim`). **EN** iverilog simulation testbenches (`make sim`). |
| `hdl/tools/` | **ES** Generador de proyectos Quartus, `MAPROUT.BIN`, inventarios, pruebas de mutación. **EN** Quartus project generator, `MAPROUT.BIN`, inventories, mutation testing. |
| `hdl/quartus/` | **ES** Plantilla del proyecto Quartus II 13.0sp1 (pines y tiempos). **EN** Quartus II 13.0sp1 project template (pins and timing). |
| `os/` | **ES** OS propio: `src/` (arranque, SD, FAT, lanzador, menú), fuente y pruebas (`make -C os`). **EN** Our own OS: `src/` (boot, SD, FAT, launcher, menu), font and tests (`make -C os`). |
| `tools/bios/` | **ES** Emulador del cartucho (CPU, CPLD, FPGA en modo OS y SD) que ejecuta la BIOS real para probar el OS. **EN** Cartridge emulator (CPU, CPLD, FPGA in OS mode and SD) that runs the real BIOS to test the OS. |
| `tools/n8sim/` | **ES** Banco Mesen2 + Verilator: el RTL corre dentro de Mesen2 y se compara con su mapper (`difftest.py`, `fuzz/`). **EN** Mesen2 + Verilator bench: the RTL runs inside Mesen2 and is compared with its mapper (`difftest.py`, `fuzz/`). |
| `tools/fm/` | **ES** Oráculo y prueba muestra a muestra del FM del VRC7. **EN** Oracle and sample-exact test of the VRC7 FM. |
| `tools/consola/` | **ES** Pruebas automáticas en la consola real: mando emulado con Arduino, captura de vídeo y comparación. **EN** Automated tests on real hardware: Arduino-emulated controller, video capture and comparison. |
| `tools/pruebas-n8/`, `tools/pagina-pruebas/` | **ES** Plan de pruebas en consola y su página de resultados. **EN** Console test plan and its results page. |
| `release/` | **ES** Empaquetador de los releases e instrucciones para la SD. **EN** Release packager and SD card instructions. |
| `docs/` | **ES** Documentación del hardware, del banco y de cada fase. **EN** Documentation of the hardware, the bench and each phase (in Spanish). |

## Uso / Usage

**ES** — Esta sección es para compilar y probar el proyecto. Para usarlo en tu cartucho basta con la
versión compilada de [Releases](https://github.com/LuiskAycardi/OpenFirmware-EverDrive-N8-ChinaVersion/releases).

**EN** — This section is for building and testing the project. To use it on your cartridge, the
prebuilt version from [Releases](https://github.com/LuiskAycardi/OpenFirmware-EverDrive-N8-ChinaVersion/releases)
is all you need.

**ES** — Requisitos: Icarus Verilog, Python 3, Quartus II 13.0sp1 (para los RBF), Verilator y .NET (para
el banco Mesen2), cc65 (para el OS) y mtools, mkfs.fat y sfdisk (para las pruebas del OS).

**EN** — Requirements: Icarus Verilog, Python 3, Quartus II 13.0sp1 (for the RBF files), Verilator and
.NET (for the Mesen2 bench), cc65 (for the OS) and mtools, mkfs.fat and sfdisk (for the OS tests).

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

make -C os                       # os/build/OS.BIN (cc65)
python3 -I os/herramientas/probar_os.py --bios BIOS.bin --rbf 255.RBF --trabajo /tmp/carpeta-nueva
                                 # ES: el OS con la BIOS real en el emulador (volcado no incluido)
                                 # EN: the OS with the real BIOS in the emulator (dump not included)
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
