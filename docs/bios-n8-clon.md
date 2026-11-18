# La BIOS del EverDrive N8 clon: qué hace y qué exige a un OS

Fecha: 2026-11-16. Base para el OS propio (ver [os-propio-viabilidad.md](os-propio-viabilidad.md)). Aquí solo hay
comportamiento: no se copia código ni datos de Krikzz. La BIOS (16 KiB de la flash) y el `OS.BIN` v13 se leyeron
y se ejecutaron en local, fuera del repositorio.

## Cómo se ha estudiado

1. **Volcado de la BIOS**: 16 KiB de la ventana `$C000-$FFFF`, que la flash repite en `$8000-$BFFF`. Salió de las
   sondas BIOS_RESPALDO del archivo n8-firmware y no está en el repo.
2. **Emulador propio** en [`tools/bios/`](../tools/bios/README.md): CPU 6502, CPLD (`$4400-$4403`), FPGA en modo
   OS y SD en modo SPI con una imagen FAT de verdad. Se ejecutan la BIOS y el v13 completos, y todo lo que hacen con
   el hardware queda registrado. `estudio.py pruebas` repite los experimentos de abajo (11 casos, todos «ok»).
3. **Netlist del `255.RBF` de fábrica**, exportada a Verilog con el decompilador de n8-firmware
   (`tools/ep2c5-re/export_v.py`) y simulada con iverilog. La simulación da cuándo conduce el FPGA el bus de la CPU.

Lo que depende de la consola y no se ha medido allí va marcado como **(por medir)**.

## 1. Arranque, paso a paso

Unas 700 000 instrucciones desde el encendido hasta el OS (del orden de 1-2 s en la consola). La BIOS **no lee el
mando**: no hay ningún menú oculto activado con botones.

1. Reset en `$FC40`: `SEI`, `CLD`, pila en `$FF`, `$4402` = 3 y salto al arranque de cc65 (borra la RAM, copia
   sus datos a `$0300` y pone la pila de C en `$0800`).
2. **SD:** reg 2 = 0. Orden de inicialización: CMD0, CMD8, ACMD41 (repetida hasta que la tarjeta sale de *idle*)
   y CMD58, que le dice si es SDHC. Después pone el bit 3 del reg 2 si es SDHC y el bit 0 (§2).
3. **FAT:** lee el MBR (sector 0) y el sector de arranque de la partición. Funciona con FAT16 y FAT32, con o sin MBR
   y con tarjetas SDSC (direcciones en bytes) o SDHC (en bloques).
4. Busca `EDFC/`, `EDFC/MAPS/`, `EDFC/OS.BIN` y `EDFC/MAPS/255.RBF`, solo con nombres 8.3. Si falta algo, pinta
   «ERROR:xx» y se queda parada (§5).
5. **Configura el FPGA con el 255.RBF:** guarda el reg 9 y lo pone a 0, da un pulso 0 → 1 en el reg 6 (nCONFIG),
   selecciona la SD en modo ráfaga, pone `$4402` = 5 y pasa cada byte del sector del reg 0 (`$4401`) al puerto de
   configuración `$4403`. Termina con `$4402` = 3 y el reg 9 restaurado.
6. **Copia el OS.BIN a la PRG-RAM** por la ventana `$6000` (reg 129), banco a banco y de 8 KiB en 8 KiB.
7. Pone el reg 9 a 0, **copia su página `$FC00-$FFFF`** (1 KiB, con sus vectores) al banco 15 de la PRG-RAM, pone
   el reg 9 a 1 y salta a **`$8000`**. Es la misma rutina que atiende la orden USB «r».

### Estado al saltar a `$8000` (en el modelo)

| Elemento | Valor |
|---|---|
| CPU | A = `$01`, X = `$FF`, Y = `$00`, S = `$FB`, P = `$35` (I = 1, D = 0). **Igual en la NES** |
| RAM | páginas `$00`, `$01`, `$03`, `$05` y `$07` usadas por la BIOS; el OS debe borrarlas |
| PPU | `$2000` = `$2001` = 0 (sin NMI y sin dibujar); paleta de fondo a `$21` |
| CPLD | reg 9 = 1, reg 2 = `$09` (SDHC, bit 0 y tarjeta seleccionada), reg 6 = 1, `$4402` = 3, reg seleccionado 9. **En la NES: reg 2 = `$09`, reg 9 = `$01`, reg 10 = `$01`** |
| FPGA | 255.RBF en modo OS; reg 128 = 0, reg 129 = 15, reg 130 = 0 |
| `$FC00-$FFFF` | página de la BIOS, con sus vectores: NMI e IRQ apuntan a un `RTI` y RESET a `$FC40` |

## 2. Registros del CPLD (lo que se sabe)

| Puerto / reg | Uso | Seguridad |
|---|---|---|
| `$4400` | número de registro (lo comparten el CPLD y el FPGA) | seguro |
| reg 0 por `$4401` | dato SPI de la SD. Escribir envía un byte; leer devuelve el último recibido o, en ráfaga, uno nuevo | seguro (BIOS y v13 en el modelo) |
| reg 1 por `$4401` | dato USB (FIFO) | leído en la BIOS; falta saber si el clon lo lleva |
| reg 2 bit 0 | **SPI rápido.** La BIOS lo pone tras inicializar la tarjeta. Medido en la NES con el OS propio: con el bit a 0 las órdenes funcionan (esperando al bit 0 de `$4403`), pero la lectura de datos en ráfaga falla; con el bit a 1 se leen 32 KiB en 18 fotogramas (unos 109 KiB/s, sector a sector) | medido |
| reg 2 bit 1 | /CS de la SD: 0 = tarjeta seleccionada | seguro |
| reg 2 bit 2 | ráfaga: cada lectura de `$4401` saca un byte nuevo de la SD | seguro |
| reg 2 bit 3 | **la tarjeta es SDHC** (la BIOS lo pone solo con SDHC; el v13 lo consulta) | seguro en el modelo |
| reg 6 | nCONFIG del FPGA (0 y después 1) | seguro |
| reg 9 bits 1:0 | qué hay en `$8000-$FFFF`: `01` = PRG-RAM (OS), `00` = flash de la BIOS. El v13 usa otro valor para consultar la identificación de la flash; **un OS propio no lo necesita y no debe usarlo** | 01/00 seguros |
| reg 9 bit 2 | el v13 escribe 5 antes de lanzar un juego | **(por medir)** |
| reg 10 | el v13 lo escribe. En la NES se lee `$01` al entrar en el OS (no es bus abierto) | valor medido; significado **(por medir)** |
| regs 138-140 | el v13 lee el 138 en bucle mientras vale `'R'` (`$52`). **En la NES, con el 255.RBF del clon, los tres dan `$44`: bus abierto** (el último byte del bus es el alto de `$4400`). Nadie contesta: el 255.RBF del clon no los implementa | medido |
| `$4402` | modo: 3 normal, 5 mientras se configura el FPGA | seguro |
| `$4403` lectura | bit 0 = SPI libre; bit 1 = USB con dato; bit 2 = USB con sitio. En la NES, en reposo: `$01` | bit 0 seguro |
| `$4403` escritura | byte de configuración del FPGA (con `$4402` = 5) | seguro |

## 3. Requisitos para el `OS.BIN`

Todos están comprobados en el modelo con la BIOS real (`estudio.py pruebas`):

- **Tamaño: múltiplo de 8 KiB.** La BIOS carga `tamaño / 8192` bancos (truncando) y alinea el archivo para que
  **termine en `0x1FFFF`**: 56 KiB van a `0x12000`, 16 KiB a `0x1C000` y 64 KiB a `0x10000`. Lo que no llena un
  banco entero se pierde: un archivo de 20 000 bytes carga solo 16 KiB. Más de 64 KiB invadiría la PRG-RAM de las
  partidas (`0x00000-0x0FFFF`).
- **La BIOS sirve `$8000-$FFFF` desde `0x18000-0x1FFFF` y salta a `$8000`.** El OS tiene que acabar en `$FFFF`
  y tener su entrada en `$8000`.
- **`$FC00-$FFFF` es de la BIOS:** la copia encima del archivo. El OS no debe poner nada ahí; si quiere vectores
  propios, los escribe en la RAM ya en marcha (el v13 lo hace).
- **El primer byte de `$8000` no puede ser `$EA` (NOP).** Ver §4.
- **Archivo contiguo en la SD.** La BIOS solo toma de la FAT el primer clúster y el tamaño, y lee el `OS.BIN` y el
  `255.RBF` de un tirón (un CMD18). Con un archivo fragmentado llegan otros datos (comprobado). Hay que copiarlos en
  una tarjeta recién formateada o sin huecos; reemplazar el archivo en una SD muy usada puede fragmentarlo.
- **Nombres 8.3 en mayúsculas** (`OS.BIN`, `255.RBF`) dentro de `EDFC/` y `EDFC/MAPS/`.
- El 255.RBF se envía al FPGA con algo más del doble de bloques que mide el archivo. El FPGA ignora lo que sobra
  después de configurarse; da igual cuál sea el contenido de los sectores siguientes.

## 4. El 255.RBF de fábrica y los bloques ilegibles del v13

En el v13, `$4000-$5FFF`, `$8000-$9FFF` y `$E000-$FBFF` no son legibles tal como están en el archivo. **Los
desofusca el 255.RBF de fábrica**, no la BIOS (la BIOS copia el archivo sin tocarlo, comprobado):

- El 255.RBF del clon (105 LE) lleva un bloque M4K con **un cargador de 256 bytes**. Mientras está activo, el FPGA
  lo sirve en todo `$8000-$FFFF` (indexado con `A7..A0`), conduce el bus de la CPU, apaga la PRG-RAM y pone el
  CPLD en modo 00.
- **Se activa cuando la CPU lee `$EA` en `$8000`** con `bios_off` = 1, y se apaga cuando vuelve a leer en `$8000`
  un byte distinto. El v13 empieza por `$EA`. El cargador transforma en su sitio esos tres bloques de la PRG-RAM
  por la ventana `$6000`, escribe `$78` (`SEI`) en `$8000` y salta allí. Desde ese momento corre el v13 normal.
  Simulado con la netlist exportada (iverilog): con `$78` en `$8000` el FPGA no conduce nunca. Con `$EA`, conduce
  desde la lectura siguiente hasta que `$8000` deja de valer `$EA`.
- Con ese modelo, el v13 completo arranca en el emulador y llega a su menú.

**Consecuencias para el OS propio:**
1. **Puede usar el 255.RBF de fábrica** si su primer byte en `$8000` no es `$EA` (lo normal es `SEI`) y nunca deja
   `$EA` en `$8000` mientras corre. No hace falta ni la clave ni la transformación: no se toca la protección del v13.
2. El OS propio y el v13 pueden convivir con el mismo 255.RBF. Volver al de fábrica es cambiar solo el `OS.BIN`.
3. **Hecho el 2026-11-17: 255.RBF propio** (`make -C hdl out/255.RBF`, macro `N8_RBF_255`: solo `n8_os_iface` y el
   NROM, 133 LE). `hdl/sim/tb_255.v` reproduce los pasos 6 y 7 de la BIOS. Probado en la NES con el OS propio:
   arranque en frío, carpetas, SMB3 (RBF 100) y un MMC5 (RBF 103), RESET y el kit Lava. Con él no arranca el v13
   (necesita el cargador del 255 de fábrica). Antes decía: un 255.RBF propio sigue siendo opcional (etapa 8 del
   plan). Tendría que mantener el mapa del modo OS
   (`n8_os_iface.v`).

## 5. Errores que muestra la BIOS

Pinta un recuadro con «ERROR:xx» (hexadecimal) y se queda en un bucle. Hay que apagar.

| Código | Causa | Texto |
|---|---|---|
| `10` | no hay `EDFC/` (SD vacía) | System files not found! + instrucciones |
| `12` | no hay `EDFC/OS.BIN` | ídem |
| `13` | no hay `EDFC/MAPS/255.RBF` | ídem |
| `40` | la SD no contesta | SD initialization error |
| (otros) | FAT o E/S | FAT initialization error, SD card I/O error |

El `11` debe de ser `EDFC/MAPS/` (no se ha probado).

## 6. La página `$FC00-$FFFF`: lo que el v13 usa de la BIOS

La página copiada empieza con una tabla de números de registro del FPGA y una de **direcciones de rutinas**:
USB (leer y escribir byte o bloque, ¿hay dato?), SPI (enviar, esperar), SD (orden, leer sectores a la RAM o a
`$2007`, escribir sectores, /CS, velocidad), cargar el FPGA, arrancar el OS y consultar el reg 2. **El v13 no tiene
controlador de SD propio:** sus datos guardan direcciones fijas de esas rutinas y las llama (en el emulador lee el
directorio con las rutinas de lectura de sectores y la orden CMD18/CMD12 de la BIOS). Por eso el v13 depende de
la disposición exacta de esta BIOS.

El OS propio tendrá rutinas SPI y SD propias, escritas a partir de §2. No depende de esa página ni llama a código
de Krikzz.

**USB:** la BIOS tiene un bucle de órdenes (`'*'` seguido de `t`, `f`, `b`, `r`). Sirven para probar la conexión,
cargar el FPGA, escribir bancos de la PRG-RAM y arrancar el OS sin la SD. La BIOS no entra sola en ese bucle:
entra cuando el OS salta a su rutina (el v13 consulta el USB en su bucle principal). Si la placa trae USB, sería
un camino de desarrollo sin mover la SD **(por medir: ¿el clon lleva el conector?)**.

## 7. Reset de la consola (botón RESET, kit Lava y Select+B)

**Medido en la NES (2026-11-16, OS de la etapa 1, `os/`):** después de pulsar el botón RESET, la pantalla dio
ARRANQUES = 02 y el contador de fotogramas volvió a cero. Los registros de la CPU al entrar eran `01 00 04 FC 36`
(la BIOS deja `01 FF 00 FB 35`) y el reg 9 seguía a 01. **El reset no pasa por la BIOS:** el CPLD mantiene el bit 0
del reg 9 y la CPU entra por el vector RESET que el OS dejó en la RAM.

**Qué devuelve al menú (medido el mismo día con el v13, el Nano y la capturadora):**

| Disparador | En el menú | Dentro de un juego (SMB, RBF 100) |
|---|---|---|
| Botón RESET (PC817 del Nano, 300 ms) | — | **vuelve al menú del OS** con el cursor en el juego (pantalla negra, menú en menos de 1 s; unos 1,4 s sin leer el mando) |
| Kit Lava: Select 2 s y luego A **1 s** | resetea la CPU (nuestro OS: ARRANQUES 02) | un solo reset: **el juego vuelve a arrancar** con la CHR corrompida |
| Kit Lava: Select 2,5 s y luego Select+A **5 s** | — | **vuelve al menú del OS** con el cursor en el juego. Mientras Select+A sigue pulsado, el Lava repite el reset: unos 0,7 s sin leer el mando cada 1,4 s |
| Select+B, 5-8 s | v13: abre su «Main Menu» (Select); nuestro OS: nada | nada (el juego sigue) |

- **Repetido con el firmware del Nano de 60 ms (mismo día, v13):** en el menú, `reset-mando 2500 5000` da `reset=4
  sil=751`; dentro de SMB da `reset=5 sil=751` y vuelve al menú; `reset-boton 1000` vuelve al menú. Con Select+A
  solo 0,8 s (`reset=1`) esta vez **también volvió al menú**, cuando en la primera prueba (1 s) el juego volvió a
  arrancar con la CHR corrompida: con un solo reset del Lava el resultado no es fiable, así que el banco mantiene 5 s.
- **Select+B no es un reset** en esta consola. El banco (`tools/consola/prueba.py`) vuelve al menú con el reset por
  el botón y, si no basta, con el reset por el mando del Lava (antes pulsaba Select+B, que no hacía nada).
- El Lava tira de la misma línea que el botón. Con una pulsación corta de Select+A da un solo reset y el juego vuelve
  a arrancar en su mapper (la CHR corrompida no está explicada). Manteniendo Select+A unos 5 s, los resets
  repetidos acaban devolviendo al menú: el FPGA vuelve al modo OS cuando M2 se para al menos 128 ciclos de `clk`
  (`n8_os_iface.v`). En el banco son dos funciones separadas: el **reset por el botón** (`mando.py reset-boton`,
  orden H del Nano, PC817 en D2) y el **reset por el mando** (`mando.py reset-mando`, orden R: Select 2,5 s y luego
  Select+A 5 s). Con el firmware nuevo, desde SMB: 5 resets vistos y vuelta al menú.
- Fuentes del Lava: [amaiorano.io](https://amaiorano.io/2025/09/03/lava-rgb.html) (cableado RST, CLK, DATA, LATCH
  y la combinación) y [nesdev](https://forums.nesdev.org/viewtopic.php?t=25963).


El v13 escribe en la RAM sus propios vectores: RESET = `$8000`, NMI = `$80D1` e IRQ = `$8108`. Además, el
cargador del 255.RBF deja `$8000` = `SEI`. Así que, después de un reset, si el CPLD mantiene el bit 0 del reg 9, la
CPU vuelve a entrar en el v13 que ya está en la RAM, sin pasar por la BIOS. El FPGA sigue con el RBF del juego en
modo OS: por eso **todo RBF tiene que llevar el modo OS** (`n8_os_iface.v`). **(Por medir** que el CPLD no baje el
bit 0 con el reset; la etapa 1 del plan lo responde con un contador de arranques.**)**

**Hecho en el OS propio** (`os/src/arranque.s`, probado en la NES el 2026-11-16): distingue encendido, reset en el
OS y vuelta de un juego, y aguanta la ráfaga de 4 resets del Lava (contadores 01/00/00 → 02/01/00 con el botón →
06/05/00 con el Lava). Detalles en [os/LEEME.md](../os/LEEME.md).

Para el OS propio:
- Instalar sus vectores en `$FFFA-$FFFF` de la RAM nada más arrancar, con RESET apuntando a una entrada que
  funcione igual sin la BIOS (con el RBF del juego en modo OS) y con el CPLD en el estado que deja el juego.
- No suponer que el 255.RBF está cargado después de un reset.

## 8. Qué cambia en el estudio de viabilidad

- §1.4 resuelto: los bloques del v13 los desofusca el 255.RBF de fábrica, y un OS en claro funciona con él si no
  empieza por `$EA`.
- Requisitos nuevos para el OS.BIN: tamaño múltiplo de 8 KiB, archivo contiguo y nada en `$FC00`.
- El reset de la consola probablemente no pasa por la BIOS (§7). Sustituye a la hipótesis contraria del estudio.
- Bits 1, 2 y 3 del reg 2 identificados. Quedan por medir el bit 0 del reg 2, los bits 2-4 del reg 9 y los regs 10 y
  138-140.
- Banco de etapa 0 disponible: `tools/bios/` ejecuta la BIOS y servirá para arrancar el OS propio en el PC antes que
  en la consola.
