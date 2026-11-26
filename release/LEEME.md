# OpenFirmware-EverDrive-N8-ChinaVersion — compilación completa propia / complete own build {VERSION} (beta)

> ☕ ¿Te resulta útil? Apoya el proyecto en **[Ko-fi](https://ko-fi.com/luiskaycardi)** / Find it useful? Support the
> project on **[Ko-fi](https://ko-fi.com/luiskaycardi)**.

**ES** — Firmware libre (GPL-3.0-or-later) para la microSD del **EverDrive N8 China Version** (clon chino con
FPGA EP2C5, versión NO-PRO) de **Famicom y NES**. Es una **compilación completa y propia**: todo lo que el
cartucho lee de la tarjeta sale de nuestro repositorio, **sin ningún archivo de Krikzz ni de fábrica**:

- nuestro **OS** (`EDFC/OS.BIN`): el menú, escrito desde cero;
- nuestro **255.RBF** (`EDFC/MAPS/255.RBF`): lo que el FPGA carga al encender para que funcione el menú;
- nuestros **mappers** (`EDFC/MAPS/100.RBF` … `106.RBF`, 194 mappers), el del **Famicom Disk System**
  (`EDFC/MAPS/254.RBF`) y su tabla (`EDFC/MAPROUT.BIN`).

Del cartucho solo se usa su **BIOS** (en la memoria flash del propio cartucho), que no se toca. **Es una
beta**: funciona en una NES real, pero todavía le faltan cosas (ver «Qué falta»). **Novedad de la v0.5.0: guarda
las partidas con pila** (ver «Partidas»). **Novedad de la v0.5.1: menú ordenado** (alfabético, con la entrada
elegida en rojo, la información del juego, saltos por letra y vuelta al último juego al encender) y **modo banco**
para pruebas automáticas (ver «Uso»). **Novedad de la v0.6.0: Famicom Disk System** (discos `.fds`, con tu propia
BIOS FDS; ver «Famicom Disk System»), carga rápida y cambio de cara automático. **Novedad de la v0.6.1: volumen del
sonido de expansión** (FDS, VRC6, VRC7, 5B, N163, MMC5; se oye en la Famicom) en la pantalla de opciones,
**Select + Start**. **Novedad de la v0.6.2: volumen calibrado en una Famicom** (cada chip suena frente al de la
consola como en el emulador Mesen2) y arreglado el reset del kit Lava al salir de un disco FDS. **Novedad de la
v0.6.3: partidas de los juegos con EEPROM** de Bandai (Dragon Ball Z, SD Gundam Gaiden, Datach…; ver «Partidas»). **Novedad de la v0.6.4: MMC5 corregido y verificado en una NES real**
(los sprites de 8x16 ya no toman tiles del fondo; split vertical de Uchuu Keibitai SDF comprobado). **Novedad de la
v0.6.5: el Namco 163 alterna sus canales como el chip real** (con muchos canales se oye su pitido agudo, como en el
cartucho original; volumen sin cambios).

**EN** — Free (GPL-3.0-or-later) firmware for the microSD card of the **EverDrive N8 China Version** (Chinese
clone with an EP2C5 FPGA, NON-PRO version), **Famicom and NES** cartridges. It is a **complete own build**:
everything the cartridge reads from the card comes from our repository, **with no file from Krikzz or from
the factory**:

- our **OS** (`EDFC/OS.BIN`): the menu, written from scratch;
- our **255.RBF** (`EDFC/MAPS/255.RBF`): what the FPGA loads at power-on so that the menu works;
- our **mappers** (`EDFC/MAPS/100.RBF` … `106.RBF`, 194 mappers), the **Famicom Disk System** one
  (`EDFC/MAPS/254.RBF`) and their table (`EDFC/MAPROUT.BIN`).

Only the cartridge's **BIOS** (in the cartridge's own flash memory) is used, and it is left untouched. **This
is a beta**: it works on a real NES, but things are still missing (see "What is missing"). **New in v0.5.0: it
saves battery-backed games** (see "Saved games"). **New in v0.5.1: a sorted menu** (alphabetical, with the selected
entry in red, game information, letter jumps and back to the last game at power-on) and a **test-bench mode** for
automated tests (see "Usage"). **New in v0.6.0: Famicom Disk System** (`.fds` disks, with your own FDS BIOS; see
"Famicom Disk System"), fast loading and automatic side switching. **New in v0.6.1: expansion audio volume**
(FDS, VRC6, VRC7, 5B, N163, MMC5; heard on the Famicom) in the options screen, **Select + Start**. **New in v0.6.2:
volume calibrated on a Famicom** (each chip sounds against the console's own sound as in the Mesen2 emulator) and a fix
for the Lava kit reset when leaving an FDS disk. **New in v0.6.3: saves for games with an EEPROM** from Bandai (Dragon
Ball Z, SD Gundam Gaiden, Datach…; see "Saved games"). **New in v0.6.4: MMC5 fixed and verified on a real NES** (8x16 sprites
no longer take background tiles; Uchuu Keibitai SDF's vertical split checked). **New in v0.6.5: the Namco 163 cycles
through its channels like the real chip** (with many channels you hear its high-pitched whine, as on the original
cartridge; volume unchanged).

## Qué contiene / Contents

| Archivo / File | Para qué / Purpose |
|---|---|
| `SD/` | **ES** Lo que va en la raíz de la microSD: la carpeta `EDFC` completa. **EN** What goes in the root of the microSD card: the whole `EDFC` folder. |
| `SD/EDFC/OS.BIN` | **ES** Nuestro OS (el menú). **EN** Our OS (the menu). |
| `SD/EDFC/MAPS/255.RBF` | **ES** Nuestro RBF del modo OS: la BIOS lo carga al encender. **EN** Our OS-mode RBF: the BIOS loads it at power-on. |
| `SD/EDFC/MAPS/100.RBF` … `106.RBF` | **ES** Los mappers (cada archivo lleva un grupo). **EN** The mappers (each file holds a group). |
| `SD/EDFC/MAPS/254.RBF` | **ES** El Famicom Disk System (con tu BIOS FDS en `EDFC/DISKSYS.ROM`). **EN** The Famicom Disk System (with your FDS BIOS in `EDFC/DISKSYS.ROM`). |
| `SD/EDFC/MAPROUT.BIN` | **ES** Qué RBF usa cada mapper. **EN** Which RBF each mapper uses. |
| `SD/EDFC/SAVE/` | **ES** Carpeta (vacía) para las partidas; el OS la crea si falta. **EN** (Empty) folder for saved games; the OS creates it if missing. |
| `MAPPERS.txt` | **ES** Lista de mappers por RBF. **EN** List of mappers per RBF. |
| `SHA256SUMS.txt` | **ES** Sumas para comprobar que los archivos llegaron bien. **EN** Checksums to verify the files. |
| `LICENSE` | **ES** Licencia GPL-3.0 (código fuente: commit `{COMMIT}` del repositorio). **EN** GPL-3.0 license (source code: repository commit `{COMMIT}`). |

## Requisitos / Requirements

**ES**
- **EverDrive N8 China Version, versión NO-PRO** (FPGA Cyclone II EP2C5), de NES o de Famicom. **No sirve para
  el EverDrive N8 PRO ni para el N8 original de Krikzz.** Placas usadas en el desarrollo (etiqueta del circuito
  impreso): NES (72 pines) `V2.0 2025-1`, `WB211982`; Famicom (60 pines) `V3.1 2024.07`.
- Una **microSD SDHC de 4 a 32 GB** (también vale una SDSC de 2 GB o menos). Las de 64 GB o más vienen en exFAT:
  sirven si se formatean en FAT32 (ver abajo), pero no hacen falta.
- Un PC con lector de tarjetas.
- Probado en una **NES NTSC**. En la Famicom los mappers ya se probaron con el OS de fábrica, pero nuestro OS y
  nuestro 255 todavía no: si tienes una, cuéntanos cómo te va.

**EN**
- **EverDrive N8 China Version, NON-PRO version** (Cyclone II EP2C5 FPGA), NES or Famicom. **It does not work
  on the EverDrive N8 PRO or on Krikzz's original N8.** Boards used during development (label on the circuit
  board): NES (72 pins) `V2.0 2025-1`, `WB211982`; Famicom (60 pins) `V3.1 2024.07`.
- An **SDHC microSD card from 4 to 32 GB** (an SDSC card of 2 GB or less also works). Cards of 64 GB or more
  come formatted as exFAT: they work if formatted as FAT32 (see below), but they are not needed.
- A PC with a card reader.
- Tested on an **NTSC NES**. On the Famicom the mappers were already tested with the factory OS, but our OS and
  our 255 have not been yet: if you have one, let us know how it goes.

## Instalación / Installation

### 1. Copia de seguridad completa de tu SD de fábrica / Full backup of your factory SD card

**ES** — **Antes de nada, guarda todo lo que hay en tu microSD.** Ahí están el OS y el 255.RBF de fábrica (los
necesitarás para volver atrás) y tus partidas guardadas del OS de fábrica (`EDFC/SAVE`), que este firmware no lee
(usa su propio formato, ver «Partidas»).

- **Lo mínimo:** copia **todo** el contenido de la tarjeta (todas las carpetas y archivos, incluida `EDFC`
  entera) a una carpeta de tu PC, por ejemplo `N8-SD-original`. Comprueba que la copia ocupa lo mismo que la
  tarjeta.
- **Lo mejor:** además, haz una **imagen** de la tarjeta entera, que la deja exactamente como estaba:
  - Windows: con un programa de imágenes de disco (por ejemplo Win32 Disk Imager, «Read»).
  - Linux: `sudo dd if=/dev/sdX of=N8-SD-original.img bs=4M status=progress` (cambia `sdX` por tu tarjeta:
    míralo con `lsblk`).
  - macOS: `diskutil list` para ver el disco y `sudo dd if=/dev/rdiskN of=N8-SD-original.img bs=4m`.
- Guarda la copia en un sitio seguro. Mejor aún: usa **otra microSD** para este firmware y deja la de fábrica
  intacta.

**EN** — **Before anything else, save everything on your microSD card.** It holds the factory OS and 255.RBF
(you will need them to go back) and the factory OS's saved games (`EDFC/SAVE`), which this firmware does not read
(it uses its own format, see "Saved games").

- **The minimum:** copy **all** the contents of the card (every folder and file, including the whole `EDFC`
  folder) to a folder on your PC, for example `N8-SD-original`. Check that the copy is the same size as the
  card's contents.
- **Best:** also make an **image** of the whole card, which restores it exactly as it was:
  - Windows: with a disk imaging program (for example Win32 Disk Imager, "Read").
  - Linux: `sudo dd if=/dev/sdX of=N8-SD-original.img bs=4M status=progress` (replace `sdX` with your card:
    check it with `lsblk`).
  - macOS: `diskutil list` to find the disk and `sudo dd if=/dev/rdiskN of=N8-SD-original.img bs=4m`.
- Keep the backup somewhere safe. Even better: use **another microSD card** for this firmware and leave the
  factory one untouched.

### 2. Formatear la SD / Format the SD card

**ES** — Formatea la tarjeta en **FAT32** con **unidad de asignación (tamaño de clúster) de 32 KB** (32768
bytes, 64 sectores), con la tabla de particiones normal de las tarjetas (MBR, una sola partición). ⚠️
**Formatear borra todo lo que hay en la tarjeta**: haz antes la copia del paso 1 y asegúrate de elegir la
tarjeta correcta.

- **Windows** (tarjetas de hasta 32 GB): Explorador → clic derecho en la tarjeta → Formatear → Sistema de
  archivos **FAT32**, Tamaño de la unidad de asignación **32 kilobytes**, Formato rápido. O en una consola:
  `format X: /FS:FAT32 /A:32K /Q /V:N8` (cambia `X` por la letra de tu tarjeta).
- **Linux:** `sudo mkfs.fat -F 32 -s 64 -n N8 /dev/sdX1` (la partición de la tarjeta: compruébalo con `lsblk`).
- **macOS:** `diskutil list`, `diskutil unmountDisk /dev/diskN` y `sudo newfs_msdos -F 32 -c 64 -v N8
  /dev/rdiskNs1`.
- También vale el formateador oficial de la SD Association («SD Memory Card Formatter»): en tarjetas de 4 a 32 GB
  usa FAT32 con 32 KB.

Por qué así: la BIOS del cartucho solo lee **FAT16 y FAT32** (no exFAT ni NTFS), y los archivos del sistema
(`OS.BIN` y los `.RBF`) tienen que quedar **contiguos** en la tarjeta, que es lo que pasa en una tarjeta recién
formateada. 32 KB es el tamaño estándar para tarjetas SDHC. También funcionan otros tamaños: en la NES se probó
una tarjeta de 4 GB con clúster de 4 KB, y en nuestro emulador del cartucho (con su BIOS real) FAT32 con 32 KB y
512 bytes y FAT16.

**EN** — Format the card as **FAT32** with a **32 KB allocation unit (cluster size)** (32768 bytes, 64 sectors),
with the usual partition table of SD cards (MBR, a single partition). ⚠️ **Formatting erases everything on the
card**: make the backup in step 1 first and make sure you pick the right card.

- **Windows** (cards up to 32 GB): File Explorer → right-click the card → Format → File system **FAT32**,
  Allocation unit size **32 kilobytes**, Quick format. Or in a console: `format X: /FS:FAT32 /A:32K /Q /V:N8`
  (replace `X` with your card's drive letter).
- **Linux:** `sudo mkfs.fat -F 32 -s 64 -n N8 /dev/sdX1` (the card's partition: check it with `lsblk`).
- **macOS:** `diskutil list`, `diskutil unmountDisk /dev/diskN` and `sudo newfs_msdos -F 32 -c 64 -v N8
  /dev/rdiskNs1`.
- The SD Association's official formatter ("SD Memory Card Formatter") also works: on 4 to 32 GB cards it uses
  FAT32 with 32 KB.

Why: the cartridge's BIOS only reads **FAT16 and FAT32** (not exFAT or NTFS), and the system files (`OS.BIN`
and the `.RBF` files) must be **contiguous** on the card, which is what happens on a freshly formatted card.
32 KB is the standard size for SDHC cards. Other sizes work too: a 4 GB card with 4 KB clusters was tested on the
NES, and FAT32 with 32 KB and 512 bytes and FAT16 in our emulator of the cartridge (with its real BIOS).

### 3. Copiar la compilación / Copy the build

**ES**
1. Descomprime el zip.
2. Con la tarjeta **recién formateada y vacía**, copia **primero** la carpeta `EDFC` que está dentro de `SD/`
   a la **raíz** de la tarjeta (tiene que quedar `EDFC/OS.BIN`, `EDFC/MAPROUT.BIN` y `EDFC/MAPS/…` en la raíz).
   Copiarla la primera es lo que garantiza que sus archivos queden contiguos.
3. **Después**, copia tus juegos (`.nes`), en la raíz o en las carpetas que quieras. Con los nombres de siempre:
   el menú muestra los nombres largos, con acentos.
4. **No copies nada de la copia de seguridad** (ni el `OS.BIN`, ni los `.RBF`, ni `EDFC/SAVE` de fábrica).
5. Expulsa la tarjeta de forma segura, ponla en el cartucho y enciende la consola. Debe salir el menú
   **«OS propio N8»** con la lista de la tarjeta.

**EN**
1. Unzip the file.
2. With the card **freshly formatted and empty**, copy the `EDFC` folder inside `SD/` **first**, to the **root**
   of the card (you must end up with `EDFC/OS.BIN`, `EDFC/MAPROUT.BIN` and `EDFC/MAPS/…` in the root). Copying
   it first is what keeps its files contiguous.
3. **Then** copy your games (`.nes`), in the root or in any folders you like, with their usual names: the menu
   shows long file names, with accents.
4. **Do not copy anything from the backup** (not the factory `OS.BIN`, the `.RBF` files or `EDFC/SAVE`).
5. Eject the card safely, put it in the cartridge and switch the console on. The **"OS propio N8"** menu should
   appear with the card's list.

### Actualizar desde la v0.4.0, v0.5.0 o v0.5.1 / Updating from v0.4.0, v0.5.0 or v0.5.1

**ES** — Copia encima de los de la tarjeta `SD/EDFC/OS.BIN`, `SD/EDFC/MAPROUT.BIN` y `SD/EDFC/MAPS/254.RBF` (este
es nuevo). Los demás RBF también se recompilaron, pero no cambian en nada: puedes dejarlos. En una tarjeta con
clúster de 32 KB el `OS.BIN` ocupa un solo clúster, así que sigue contiguo; si el menú dice «RBF fragmentado en la
SD» al lanzar un `.fds`, formatea y copia `EDFC` la primera. La carpeta `EDFC/SAVE` no hace falta: el OS la crea la
primera vez que lanzas un juego con pila.

**EN** — Copy `SD/EDFC/OS.BIN`, `SD/EDFC/MAPROUT.BIN` and `SD/EDFC/MAPS/254.RBF` (this one is new) over the ones
on the card. The other RBF files were rebuilt too, but nothing changes in them: you can keep yours. On a card with
32 KB clusters `OS.BIN` takes a single cluster, so it stays contiguous; if the menu says "RBF fragmentado en la SD"
when launching an `.fds`, format and copy `EDFC` first. The `EDFC/SAVE` folder is not needed: the OS creates it the
first time you launch a battery-backed game.

### Si no arranca / If it does not boot

**ES**
- **«ERROR:10», «ERROR:12» o «ERROR:13»** (lo pinta la BIOS): falta `EDFC`, `EDFC/OS.BIN` o
  `EDFC/MAPS/255.RBF`. Revisa que `EDFC` esté en la raíz, no dentro de otra carpeta (por ejemplo `SD/EDFC`).
- **Pantalla negra o gris al encender:** casi siempre es un archivo fragmentado. Vuelve a formatear y copia
  `EDFC` la primera, antes que los juegos.
- **«RBF fragmentado en la SD»** al lanzar un juego: igual, formatea y copia `EDFC` la primera.

**EN**
- **"ERROR:10", "ERROR:12" or "ERROR:13"** (drawn by the BIOS): `EDFC`, `EDFC/OS.BIN` or `EDFC/MAPS/255.RBF` is
  missing. Check that `EDFC` is in the root, not inside another folder (for example `SD/EDFC`).
- **Black or grey screen at power-on:** almost always a fragmented file. Format again and copy `EDFC` first,
  before the games.
- **"RBF fragmentado en la SD"** when launching a game: the same, format and copy `EDFC` first.

### Volver al firmware de fábrica / Going back to the factory firmware

**ES** — Restaura la imagen del paso 1 (Win32 Disk Imager «Write», o `dd` al revés), o formatea la tarjeta y
copia de vuelta **todo** lo que guardaste, empezando por la carpeta `EDFC`. El cartucho no se modifica en
ningún momento: con tu SD de fábrica funciona exactamente igual que antes.

**EN** — Restore the image from step 1 (Win32 Disk Imager "Write", or `dd` the other way round), or format the
card and copy back **everything** you saved, starting with the `EDFC` folder. The cartridge is never modified:
with your factory SD card it works exactly as before.

## Uso / Usage

**ES**
- **Arriba/Abajo**: mover el cursor dentro de la página (la entrada seleccionada va en rojo).
- **Izquierda/Derecha**: cambiar de página (16 entradas por página).
- **Select + Izquierda/Derecha**: saltar a la letra anterior o siguiente (la lista va en orden alfabético).
- **Select + Start**: pantalla de opciones. «Volumen del cartucho»: ◀▶ de −4 a +4 (0 = el volumen calibrado de cada
  chip; unos 3 dB por paso); B o Start vuelven. Se guarda en la memoria con pila del cartucho y vale para todos los
  juegos con sonido de expansión (solo se oye en la Famicom; en la NES el pin no está conectado).
- Con el cursor quieto, abajo sale el mapper, los tamaños y si el juego tiene pila.
- Al encender, el menú vuelve a la carpeta del último juego que lanzaste, con el cursor sobre él.
- **Modo banco** (para pruebas automáticas con un PC, `tools/consola` del repositorio): si la tarjeta tiene
  `EDFC/BANCO.TXT` (una ruta por línea), el OS enseña una pantalla con una entrada de la lista en vez del menú; Start
  la lanza, ◀▶ cambian de entrada y B vuelve al menú. Sin ese archivo, nada cambia.
- **A o Start**: entrar en una carpeta o lanzar el juego.
- **B**: volver a la carpeta de arriba.
- **RESET** de la consola dentro de un juego: vuelve al menú, a la carpeta del juego y con el cursor sobre él.
  Con el kit Lava RGB, mantener Select y luego Select+A unos segundos hace lo mismo.
- La pantalla también muestra datos del arranque, de la tarjeta y del mando: es una beta y nos ayudan a
  diagnosticar.

### Partidas

- Los juegos con pila (Zelda, Final Fantasy, Kirby…) guardan en `EDFC/SAVE/<nombre de la ROM>.srm`. El archivo se
  crea solo la primera vez (8 KB, 32 KB con MMC5, o lo que declare una cabecera NES 2.0).
- Se carga al lanzar el juego y **se guarda en la SD al volver al menú con RESET** (o con el kit Lava). En la parte
  de abajo sale «Partida guardada».
- **También si apagas dentro del juego:** la RAM del cartucho tiene pila (probado con 30 minutos apagada) y la
  partida se guarda en la SD la próxima vez que enciendes («Partida guardada» al arrancar).
- Es el mismo formato que el `.sav` de los emuladores (Mesen, FCEUX…): puedes copiar partidas entre el PC y el
  cartucho cambiando la extensión. Las partidas del OS de fábrica no se leen.
- La fecha de los archivos es fija (1-1-2026): el cartucho no tiene reloj.
- **Juegos con EEPROM** (desde la v0.6.3): algunos de Bandai guardan en una EEPROM serie (mapper 159: Dragon Ball Z:
  Kyoushuu! Saiya Jin, SD Gundam Gaiden, Magical Taruruuto-kun; mapper 16 con pila: Dragon Ball Z II/III/Gaiden, SD
  Gundam Gaiden 2/3, Rokudenashi Blues; mapper 157: los Datach). Su `.srm` mide 128, 256 o 384 bytes (Battle Rush:
  256 de la base y 128 del cartucho), lo mismo que el `.eeprom128`/`.eeprom256` de Mesen2. **Esa EEPROM está dentro
  del FPGA y no tiene pila: sal siempre con RESET antes de apagar** (el menú lo recuerda al lanzarlos). Si apagas
  dentro del juego, se pierde lo de esa sesión y al encender sale «EEPROM perdida al apagar».

**EN**
- **Up/Down**: move the cursor within the page (the selected entry is shown in red).
- **Left/Right**: change page (16 entries per page).
- **Select + Left/Right**: jump to the previous or next letter (the list is in alphabetical order).
- **Select + Start**: options screen. «Volumen del cartucho» (cartridge volume): ◀▶ from −4 to +4 (0 = each chip's
  calibrated volume; about 3 dB per step); B or Start go back. It is kept in the cartridge's battery-backed memory
  and applies to every game with expansion audio (only heard on the Famicom; on the NES the pin is not connected).
- With the cursor still, the bottom line shows the mapper, the sizes and whether the game has a battery.
- At power-on, the menu goes back to the folder of the last game you launched, with the cursor on it.
- **Test-bench mode** (for automated tests with a PC, the repository's `tools/consola`): if the card has
  `EDFC/BANCO.TXT` (one path per line), the OS shows a screen with one entry of the list instead of the menu; Start
  launches it, ◀▶ change entry and B goes back to the menu. Without that file, nothing changes.
- **A or Start**: enter a folder or launch the game.
- **B**: go back to the folder above.
- Console **RESET** inside a game: returns to the menu, to the game's folder and with the cursor on it. With the
  Lava RGB kit, holding Select and then Select+A for a few seconds does the same.
- The screen also shows boot, card and controller data: this is a beta and they help us diagnose problems.

### Saved games

- Battery-backed games (Zelda, Final Fantasy, Kirby…) save to `EDFC/SAVE/<ROM name>.srm`. The file is created
  automatically the first time (8 KB, 32 KB with MMC5, or whatever an NES 2.0 header declares).
- It is loaded when the game starts and **written to the SD card when you go back to the menu with RESET** (or with
  the Lava kit). "Partida guardada" appears at the bottom.
- **Also if you switch off inside the game:** the cartridge RAM is battery-backed (tested with 30 minutes off) and
  the save is written to the SD card the next time you switch on ("Partida guardada" at boot).
- It is the same format as emulator `.sav` files (Mesen, FCEUX…): you can copy saves between the PC and the
  cartridge by changing the extension. The factory OS's saves are not read.
- File dates are fixed (1-1-2026): the cartridge has no clock.
- **Games with an EEPROM** (since v0.6.3): some Bandai games save to a serial EEPROM (mapper 159: Dragon Ball Z:
  Kyoushuu! Saiya Jin, SD Gundam Gaiden, Magical Taruruuto-kun; mapper 16 with battery: Dragon Ball Z II/III/Gaiden,
  SD Gundam Gaiden 2/3, Rokudenashi Blues; mapper 157: the Datach games). Their `.srm` is 128, 256 or 384 bytes
  (Battle Rush: 256 of the base unit and 128 of the cartridge), the same as Mesen2's `.eeprom128`/`.eeprom256`.
  **That EEPROM lives inside the FPGA and has no battery: always leave with RESET before switching off** (the menu
  reminds you when you launch them). If you switch off inside the game, that session is lost and "EEPROM perdida al
  apagar" appears at power-on.

## Famicom Disk System

**ES**
- **La BIOS FDS la pones tú** (es de Nintendo y no se distribuye): copia tu volcado como `EDFC/DISKSYS.ROM` (8 KB).
  Valen la **Rev 1**, la **Rev 0** y la de la **Twin Famicom** (se reconocen por su suma); las de emuladores
  (GameCube, 3DS, Game & Watch) no, porque llevan trucos que cuelgan una consola real. Si falta o no vale, el menú lo
  dice al lanzar un disco.
- Copia los discos (`.fds`, con o sin cabecera fwNES) donde quieras y lánzalos como un `.nes`. Antes de saltar a la
  BIOS, el OS los copia al cartucho (unos 4 s con dos caras).
- **Cambio de cara automático:** cuando el juego pide la otra cara, el OS la «mete» sola.
- **Cambio de cara a mano:** en los pocos discos con el mismo ID en las dos caras (casi todos de Hacker International)
  el cambio automático no sabe cuál quiere el juego: mantén **B + Select** ~1 s para darle la vuelta al disco. En la
  NES funciona en los juegos que leen el mando con la BIOS (todos esos discos menos dos); en la Famicom, en todos.
- **Lo que el juego escribe en el disco** (partidas de Zelda, Metroid…) **se guarda en el `.fds` de la SD al volver al
  menú con RESET** («Disco FDS guardado»). **Si apagas sin RESET, se pierde**: la memoria del disco no tiene pila.
- **17 discos no cargan** (casi todos herramientas de copia, que leen el disco sin la BIOS): el menú dice «Disco FDS
  con carga propia».
- El sonido del FDS solo se oye en la Famicom.

**EN**
- **You provide the FDS BIOS** (it belongs to Nintendo and is not distributed): copy your dump as `EDFC/DISKSYS.ROM`
  (8 KB). **Rev 1**, **Rev 0** and the **Twin Famicom** one work (they are recognised by their checksum); emulator
  ones (GameCube, 3DS, Game & Watch) do not, because they carry tricks that hang a real console. If it is missing or
  not valid, the menu says so when you launch a disk.
- Copy the disks (`.fds`, with or without an fwNES header) wherever you like and launch them like an `.nes`. Before
  jumping to the BIOS, the OS copies them to the cartridge (about 4 s with two sides).
- **Automatic side switching:** when the game asks for the other side, the OS "inserts" it by itself.
- **Manual side switching:** on the few disks with the same ID on both sides (almost all from Hacker International)
  the automatic switch cannot tell which one the game wants: hold **B + Select** for ~1 s to flip the disk. On the
  NES it works in games that read the controller through the BIOS (all those disks but two); on the Famicom, in all.
- **What the game writes to the disk** (Zelda, Metroid saves…) **is saved to the `.fds` on the SD card when you go
  back to the menu with RESET** ("Disco FDS guardado"). **If you switch off without RESET, it is lost**: the disk
  memory has no battery.
- **17 disks do not load** (almost all copy tools, which read the disk without the BIOS): the menu says "Disco FDS
  con carga propia".
- The FDS sound is only heard on the Famicom.

## Qué falta / What is missing

**ES**
- Partidas en la RAM interna del Namco 163 (ningún juego conocido guarda ahí; la PRG-RAM del N163 sí se guarda).
- Save states y Game Genie.
- **Sonido de expansión** (VRC6, VRC7, Sunsoft 5B, Namco 163, MMC5, FDS): solo se oye en la **Famicom**; la NES no
  mezcla el audio del cartucho. El volumen se cambia con Select + Start (calibrado en una Famicom AV).
- FDS: probado en una NES y en una Famicom reales. Hasta la v0.6.1, el reset del kit Lava RGB (Select y luego
  Select+A) al salir de un disco podía repetirse sin fin y dejar la SD sin contestar («SD: error 01», solo se
  arreglaba apagando); corregido en la v0.6.2.

**EN**
- Saves in the Namco 163's internal RAM (no known game saves there; the N163's PRG-RAM is saved).
- Save states and Game Genie.
- **Expansion audio** (VRC6, VRC7, Sunsoft 5B, Namco 163, MMC5, FDS): only heard on the **Famicom**; the NES does not
  mix the cartridge audio. The volume is set with Select + Start (calibrated on a Famicom AV).
- FDS: tested on a real NES and a real Famicom. Up to v0.6.1, the Lava RGB kit reset (Select then Select+A) when
  leaving a disk could repeat endlessly and leave the SD card unresponsive ("SD: error 01", only fixed by switching
  off); fixed in v0.6.2.

## Cosas que conviene saber / Good to know

**ES**
- **ROMs PAL** (Europe): en una consola NTSC pueden ir rápidas, con basura o colgarse aunque el mapper esté
  bien. Mejor las versiones USA o Japón.
- **Cabeceras:** el menú lee bien las cabeceras iNES y NES 2.0 (en v0.2.x el OS propio leía mal las NES 2.0 y
  lanzaba esas ROMs con el mapper equivocado; corregido en v0.3.0).
- **Diferencias conocidas** con el emulador Mesen2 (detalle en `docs/fase4-mappers.md` del repositorio): el
  split vertical del MMC5 solo admite el desplazamiento fino que permite el cableado, como los cartuchos de Nintendo (en la consola, Uchuu Keibitai SDF se ve bien); Kart Fighter (116) recibe en Mesen2 una
  IRQ que aquí no llega (en una NES real el juego va bien con nuestro mapper: la diferencia es del emulador); Famicom Jump II (153) se cuelga si su partida empieza a cero (también en el emulador);
  algunos efectos de pantalla partida difieren unos píxeles en la línea del corte.
- **Qué está probado en una NES real:**
  - con este OS y este 255: arranque, carpetas y páginas, RESET y kit Lava, Super Mario Bros. (0), Super Mario
    Bros. 3 (4), Akira (33), Wario Land 2 (35), Toy Story (219), los MMC5 Castlevania III, Just Breed, Uchuu Keibitai SDF, Laser
    Invasion, Bandit Kings y Aoki Ookami (con sus partidas), y Kart Fighter y Somari (116); partidas de Zelda (MMC1):
    crear, guardar con RESET y con el apagado, y la tarjeta revisada después con `fsck.fat`;
  - los mappers, con el OS de fábrica: 71 mappers entre las pruebas a mano, una tanda automática de 39 juegos
    (RBF 103-106) y películas TAS de TASVideos comparadas con Mesen2. El resto, solo en el emulador. Lista en el
    README del repositorio.

**EN**
- **PAL ROMs** (Europe): on an NTSC console they may run fast, show garbage or hang even if the mapper is fine.
  Prefer the USA or Japan versions.
- **Headers:** the menu reads iNES and NES 2.0 headers correctly (in v0.2.x our OS misread NES 2.0 headers and
  launched those ROMs with the wrong mapper; fixed in v0.3.0).
- **Known differences** from the Mesen2 emulator (details in the repository's `docs/fase4-mappers.md`): the MMC5
  vertical split only allows the fine scroll the wiring permits, like Nintendo's own boards (Uchuu Keibitai SDF looks right on the console); Kart Fighter (116) receives an IRQ in Mesen2 that does not arrive
  here (on a real NES the game works with our mapper: the difference is the emulator's); Famicom Jump II (153) hangs if its save starts zeroed (also in the emulator); some split-screen effects
  differ by a few pixels on the split line.
- **What has been tested on a real NES:**
  - with this OS and this 255: boot, folders and pages, RESET and the Lava kit, Super Mario Bros. (0), Super
    Mario Bros. 3 (4), Akira (33), Wario Land 2 (35), Toy Story (219), the MMC5 games Castlevania III, Just Breed, Uchuu Keibitai SDF,
    Laser Invasion, Bandit Kings and Aoki Ookami (with their saves), and Kart Fighter and Somari (116); Zelda (MMC1) saves:
    creating, saving with RESET and at power-off, and the card checked afterwards with `fsck.fat`;
  - the mappers, with the factory OS: 71 mappers across manual tests, an automated run of 39 games (RBF
    103-106) and TASVideos TAS movies compared with Mesen2. The rest only in the emulator. List in the
    repository README.

## Cómo informar / How to report

**ES** — Abre un *issue* en https://github.com/LuiskAycardi/OpenFirmware-EverDrive-N8-ChinaVersion/issues con:
la consola (NES / Famicom, NTSC / PAL) y la placa del cartucho; la tarjeta (tamaño, formato y clúster); el juego
(nombre exacto de la ROM, mejor de No-Intro) y su mapper; qué pasa (arranca bien, pantalla negra o gris, gráficos
rotos, se cuelga, sonido…) y, si puedes, una foto del menú. Los informes de «funciona bien» también sirven mucho.

**EN** — Open an *issue* at https://github.com/LuiskAycardi/OpenFirmware-EverDrive-N8-ChinaVersion/issues with:
the console (NES / Famicom, NTSC / PAL) and the cartridge board; the card (size, format and cluster size); the
game (exact ROM name, preferably No-Intro) and its mapper; what happens (boots fine, black or grey screen, broken
graphics, hang, sound…) and, if you can, a photo of the menu. "It works" reports help a lot too.
