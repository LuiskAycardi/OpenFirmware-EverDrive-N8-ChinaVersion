# OpenFirmware-EverDrive-N8-ChinaVersion — paquete de pruebas {VERSION}

Mappers libres (GPL-3.0-or-later) para el **EverDrive N8 clon chino con FPGA EP2C5**, listos para copiar
a la microSD. **Versión de pruebas**: todos los mappers coinciden con el emulador Mesen2 en el banco de
pruebas, pero **casi nada se ha probado aún en la consola real**. Para eso es este paquete: para que
quien tenga uno de estos cartuchos nos ayude a probarlos.

*English summary at the end.*

## Qué contiene

| Archivo | Para qué |
|---|---|
| `EDFC/MAPS/100.RBF` … `106.RBF` | Los mappers (7 archivos; cada uno lleva un grupo de mappers) |
| `EDFC/MAPROUT.BIN` | Tabla que le dice al OS qué RBF usar para cada mapper |
| `MAPPERS.txt` | Qué mappers hay en cada RBF |
| `SHA256SUMS.txt` | Sumas para comprobar que los archivos llegaron bien |
| `LICENSE` | Licencia GPL-3.0 (código fuente: commit `{COMMIT}` del repositorio) |

**No contiene** el OS, los RBF de fábrica ni ningún archivo de Krikzz: se usan los que ya tiene tu SD.

## Requisitos

- EverDrive N8 **clon chino con EP2C5** (el que se vende con la SD «de fábrica» de un pack vietnamita/chino),
  de NES o de Famicom.
- Su **OS de fábrica**. ⚠️ **No instales los OS oficiales 1.24–1.26 de Krikzz en el clon**: llevan un
  bloqueo contra clones.

## Instalación

1. **Haz una copia de seguridad de la carpeta `EDFC` de tu microSD** (sobre todo `EDFC/MAPROUT.BIN` y
   `EDFC/SAVE`).
2. Copia `EDFC/MAPS/100.RBF` … `106.RBF` a la carpeta `EDFC/MAPS/` de tu SD. **No borres** los RBF que
   ya están: el OS sigue usando `255.RBF` (el menú) y, para el Famicom Disk System, `254.RBF`.
3. Sustituye `EDFC/MAPROUT.BIN` de tu SD por el de este paquete.
4. Arranca un juego como siempre.

**Para volver atrás**: restaura tu `MAPROUT.BIN` original (los RBF nuevos pueden quedarse, el OS
de fábrica no los usa).

## Cosas que conviene saber

- **Save states**: este paquete no los implementa (la tabla de save states va vacía). Las partidas con
  pila (archivos `.SRM` de `EDFC/SAVE`) sí funcionan como siempre.
- **Sonido de expansión** (VRC6, VRC7, Sunsoft 5B, Namco 163, MMC5): solo se oye en la **Famicom**; la NES
  no mezcla el audio del cartucho.
- **ROMs PAL** (Europe): en una consola NTSC pueden ir rápidas, con basura o colgarse aunque el mapper
  esté bien. Para probar, mejor las versiones USA o Japón.
- **Diferencias conocidas** con el emulador (detalle en `docs/fase4-mappers.md` del repositorio):
  - MMC5 (mapper 5): el modo split vertical tiene limitaciones por el cableado de la SRAM.
  - Mapper 4 (MMC3): ignora la protección de escritura de la PRG-RAM (`$A001`), por compatibilidad con el MMC6.
  - Kart Fighter (116): en Mesen2 recibe una IRQ que aquí no llega; puede comportarse distinto.
  - Famicom Jump II (153): se cuelga si su partida empieza a cero (también en el emulador).
  - Varios juegos con efectos de pantalla partida pueden diferir unos pocos píxeles en la línea del corte.
- RBF que **ya se han cargado en la consola real**: 100, 101 y 102 (versiones anteriores). **Nunca
  probados en consola**: 103 (MMC5), 104, 105 y 106 (VRC7 con sonido FM).

## Cómo informar

Abre un *issue* en https://github.com/LuiskAycardi/OpenFirmware-EverDrive-N8-ChinaVersion/issues con:

- consola (NES / Famicom, NTSC / PAL) y modelo del cartucho;
- juego (nombre exacto de la ROM, mejor de No-Intro) y número de mapper;
- qué pasa: arranca bien, pantalla negra o gris, gráficos rotos, parpadeo, se cuelga, sonido…;
- si con tu SD de fábrica el mismo juego va bien o mal.

Los informes de «funciona bien» también sirven mucho.

---

## English summary

Free (GPL-3.0-or-later) mapper bitstreams for the **Chinese EverDrive N8 clone (EP2C5 FPGA)**, plus a
matching `MAPROUT.BIN`. **Test release**: everything matches the Mesen2 emulator on our test bench, but
almost nothing has been tried on real hardware yet. Back up your SD's `EDFC` folder, copy
`EDFC/MAPS/1xx.RBF` into `EDFC/MAPS/` (keep the existing files), replace `EDFC/MAPROUT.BIN`, and
report results as GitHub issues. Use the clone's factory OS; do **not** install Krikzz's official OS
1.24–1.26 on a clone. No Krikzz files are included.
