# Estudio de viabilidad: un OS propio para el EverDrive N8 clon

Fecha: 2026-11-16. Estado: estudio, sin código. Licencia del OS que se propone: GPL-3.0-or-later, como el resto
del repositorio.

**Conclusión corta.** Es viable, y casi todo lo que el OS necesita está identificado. La BIOS de la flash
arranca un `OS.BIN` sin cifrar: el OS 1.26 de VTX, que va en texto plano, y sus variantes parcheadas ya han
arrancado en este clon. El protocolo del FPGA (registros 128-136) ya lo implementan nuestros RBF. El
protocolo de la SD y de la carga del FPGA está en la BIOS, que se puede leer. Lo que falta medir son detalles de
algunos bits del CPLD y el estado exacto en que la BIOS deja la consola. Se mide con un «hola mundo» en la
consola (etapa 1). Volver al OS de fábrica consiste en copiar otra vez un archivo a la SD.

> **Actualización (2026-11-16, más tarde):** la BIOS se ha ejecutado entera en un emulador propio
> ([bios-n8-clon.md](bios-n8-clon.md), `tools/bios/`). Resuelve el §1.4: los bloques ilegibles del v13 los
> desofusca el 255.RBF de fábrica, y un OS en claro funciona con él si no empieza por `$EA`. También fija
> requisitos nuevos para el OS.BIN (tamaño múltiplo de 8 KiB, archivo contiguo en la SD) y corrige el §2.6: el
> reset probablemente no pasa por la BIOS. Donde este documento y aquel no coincidan, vale aquel.

Reglas de este trabajo: el `OS.BIN` v13 y la BIOS se leen y se desensamblan (da65) en una carpeta temporal,
fuera del repositorio. **Aquí no se copia código ni tablas de Krikzz** y no se commitea ningún binario suyo. Lo
que sigue describe comportamiento (registros, orden de las operaciones, formatos), igual que
[hardware-fpga.md](hardware-fpga.md).

## 0. Fuentes y cómo se reproducen

| Fuente | Dónde | Qué aporta |
|---|---|---|
| `OS.BIN` v13 de fábrica (57 344 B, md5 `f5ac5490…`) | SD del usuario (`~/SD_Pruebas/EDFC/OS.BIN`) | protocolo OS↔FPGA, menú, traducciones de mapper |
| `OS.BIN` 1.26 VTX (texto plano) | `~/Downloads/nesos-v1.26_vtx/` | solo para comparar la estructura; tiene otro protocolo (ver CONTEXTO del archivo n8-firmware) |
| BIOS del clon: volcado de 16 KiB (`$C000-$FFFF`, la ventana se repite en `$8000`) | `~/n8-firmware/artifacts/ep2c5-handshake/bios-respaldo/captura-usuario/` (`bios_c0_*` + `bios_e0_*`), sacado con las sondas BIOS_RESPALDO | arranque, controlador de la SD, FAT, carga del 255.RBF y del OS.BIN, puerto USB |
| RTL propio | [`hdl/rtl/n8_os_iface.v`](../hdl/rtl/n8_os_iface.v), [`hdl/rtl/n8_top.v`](../hdl/rtl/n8_top.v) | lado FPGA del protocolo (ya probado en la NES) |
| Ingeniería inversa del 1.26 | `~/n8-firmware/docs/re-os-1.26*.md` | sondas en la consola: ejecutar código propio en el lugar del OS |

Para repetir el desensamblado (en el scratchpad, nunca en el repo):

```bash
da65 --cpu 6502 --start-addr 0x2000 -o os.s OS.BIN
```

```bash
cat bios_c0_primeros_8k.bin bios_e0_primeros_8k.bin > bios.bin && da65 --cpu 6502 --start-addr 0xC000 -o bios.s bios.bin
```

Los dos son código de **cc65** (pila de C en `$28/$29`, `sta ($28),y` por todas partes). Un OS propio en cc65
(C y ensamblador; licencia zlib) encaja con la misma cadena de herramientas que ya usa el proyecto (`ca65`,
`ld65`).

## 1. Cadena de arranque

### 1.1 Lo que hace la BIOS (leído en el volcado)

1. **Reset** (`$FC40` en la flash): `SEI`, `CLD`, pila en `$FF`, escribe `3` en `$4402` (modo normal del
   CPLD, ver §2.1), espera y salta al arranque en C (`$C000`).
2. **crt0 de cc65:** apaga la PPU, borra `$0000-$07FF`, copia sus datos iniciales a `$0300` y deja la pila de
   C en `$0800`.
3. Inicializa la SD y la FAT. Si algo falla, muestra uno de estos mensajes: «SD initialization error», «FAT
   initialization error», «SD card I/O error» o «System files not found!» (con instrucciones de bajar
   nesos.zip). También trae una «self test» (CHR, REG, SRM, PRG, SPI) que no se ha visto en la consola.
4. Abre `EDFC/`, `EDFC/MAPS/`, `EDFC/OS.BIN` y `EDFC/MAPS/255.RBF` (nombres 8.3 escritos en la BIOS: **los
   dos archivos y las dos carpetas son obligatorios**).
5. **Configura el FPGA con el 255.RBF**: pulso en el registro 6 del CPLD (§2.2) y bloques de la SD pasados
   directamente al puerto de configuración (`$4403`).
6. **Copia el OS.BIN a la PRG-RAM** por la ventana `$6000-$7FFF`, cambiando de banco con el registro 129 del
   FPGA (el 255.RBF ya está activo).
7. **Copia su última página (`$FC00-$FFFF`, 1 KiB) a la PRG-RAM**, en el mismo sitio que ocupará en
   `$FC00-$FFFF` (banco 15 de `$6000`, es decir `$7C00-$7FFF`), y pone a 1 el bit 0 del registro 9 del CPLD.
   El código sigue sin saltos, porque la página es idéntica en la flash y en la RAM. Luego salta a `$8000`.
   (Esa secuencia está tal cual en la orden USB «r»; la ruta de la SD termina en una llamada indirecta que
   lleva al mismo sitio, pero no se ha seguido instrucción a instrucción.)

### 1.2 Mapa resultante

Según [hardware-fpga.md](hardware-fpga.md) y `n8_os_iface.v`, con `bios_off` = 1, el 255.RBF sirve en
`$8000-$FFFF` los 32 KiB de PRG-RAM `0x18000-0x1FFFF`. El `OS.BIN` mide `0xE000` y sus vectores caen en
`$FFFA`, así que se carga con base `$2000`:

| CPU | Byte del `OS.BIN` | PRG-RAM | Cómo lo ve el OS |
|---|---|---|---|
| `$2000-$7FFF` (direcciones del enlazador) | `0x0000-0x5FFF` | `0x12000-0x17FFF` | bancos 9-11 de la ventana `$6000` (reg 129) |
| `$8000-$FBFF` | `0x6000-0xDBFF` | `0x18000-0x1FBFF` | directo |
| `$FC00-$FFFF` | `0xDC00-0xDFFF` (**vacío**) | `0x1FC00-0x1FFFF` | la BIOS lo pisa con su página de E/S y sus vectores |

- Tanto v13 como 1.26 dejan `$FC00-$FFF9` a cero: **el OS propio tampoco debe poner nada ahí**. Después del
  traspaso, los vectores que ve la CPU son los de la BIOS (NMI e IRQ en un `RTI` y RESET en `$FC40`). El OS
  tiene que escribir los suyos en la RAM antes de activar la NMI.
- Esa página trae las rutinas de bajo nivel de la BIOS (SPI, lectura de sectores, carga del FPGA, USB). El
  v13 la usa al menos una vez (`JSR $FFA9`). El OS propio no debe depender de ella: tendrá sus propias rutinas
  (§2.1). Así funciona aunque cambie la BIOS de otro clon, y no hay que llamar a código de Krikzz.
- La PRG-RAM baja (`0x00000-0x0FFFF`) es la de las partidas. `0x10000-0x11FFF` (8 KiB) queda libre para el
  estado del OS.
- **Tamaño máximo de un OS propio:** 55 KiB (`0x12000-0x1FBFF`), de los que 31 KiB se ejecutan directamente
  (`$8000-$FBFF`). El resto son datos o código que se ejecuta por bancos de 8 KiB en `$6000`. No hay que ocupar
  todo el archivo. Lo que manda es que su tamaño sea un **múltiplo de 8 KiB**: la BIOS lo alinea para que
  termine en `0x1FFFF` y trunca el resto ([bios-n8-clon.md](bios-n8-clon.md) §3).

### 1.3 Estado que deja la BIOS (por medir en la etapa 1)

| Elemento | Lo que se espera | Seguridad |
|---|---|---|
| CPU | `SEI`, `CLD`, S en algún valor de la pila de la BIOS | supuesto: el OS se pone su propia pila |
| RAM `$0000-$07FF` | datos y BSS de la BIOS (`$0300-$05FF`), pila de C en `$0700-$07FF` | leído; el OS debe borrarla |
| PPU | apagada (`$2000` = `$2001` = 0) o con la paleta del arranque | leído en parte |
| FPGA | 255.RBF de fábrica, mapper = `$FF` (modo OS) | seguro: sin él no correría el OS |
| CPLD | reg 9 bit 0 = 1, `$4402` = 3, SD inicializada con /CS alto | deducido de la BIOS; falta leerlo de vuelta |
| SD | inicializada; ¿SDHC?, ¿velocidad rápida? | por medir |

### 1.4 Lo que no cuadra todavía: el v13 tiene bloques ilegibles

El `OS.BIN` v13 tiene unos 20 KiB con entropía ≈ 7,95 bits/byte (aleatorios a efectos prácticos): `$4000-$5FFF`,
`$8000-$9FFF` y `$E000-$EFFF`. **Los tres vectores apuntan a `$8000-$81xx`**, dentro de esa zona, y el código
legible (`$A000-$DFFF`, `$F000-$FBFF`) llama a rutinas en `$EExx-$EFxx` (el runtime de cc65). Tampoco aparecen en
la parte legible accesos a `$4402`/`$4403` ni al registro 0 del CPLD. Es decir: **el controlador de la SD y del
FPGA del v13 está en esos bloques**, cifrados o comprimidos. El 1.24-1.26 de VTX no tiene esos bloques: es
texto plano desde `$8000` (`SEI, CLD, LDX #$FF, TXS…`).

Como la BIOS del clon es la misma para los dos y **el 1.26 en texto plano y sus parches arrancaron en esta
consola** (sonda r5: Super Mario Bros. y PROBE_126 en verde, `re-os-1.26-stub-original-r5.md`), la BIOS no
exige el cifrado. O lo deshace solo cuando reconoce el formato del v13, o el v13 lo deshace él mismo por un
camino que todavía no hemos visto. Para el OS propio basta lo primero: **un `OS.BIN` en texto plano arranca**.
Lo único que perdemos es leer la capa de E/S del v13, y la de la BIOS la sustituye.

**Resuelto** ([bios-n8-clon.md](bios-n8-clon.md) §4): la BIOS copia el archivo sin tocarlo, y es el 255.RBF de
fábrica el que sirve un cargador interno cuando la CPU lee `$EA` en `$8000`. Ese cargador desofusca los tres
bloques. Con otro primer byte, el FPGA no interviene.

## 2. Interfaces que necesita un OS

Todas pasan por los dos puertos que comparten el CPLD y el FPGA: **`$4400` (número de registro) y `$4401`
(dato)**, y por dos puertos que solo tiene el CPLD, **`$4402` y `$4403`**. El FPGA solo atiende los registros 128 en
adelante, y el CPLD los bajos (0-10, que sepamos). El v13 lee además el 138 (ver §2.4).

### 2.1 Lectura y escritura de la SD (SPI en el CPLD)

**Se sabe (leído en la BIOS):**

| Puerto / registro | Uso |
|---|---|
| reg 0 por `$4401` | **dato SPI de la SD.** Escribir envía un byte. Leer devuelve el último recibido. |
| reg 2 por `$4401` (lectura y escritura) | **control de la SD.** Bit 0 = velocidad del SPI (lento para la inicialización y rápido después; supuesto). Bit 1 = /CS de la tarjeta (1 = libre). Bit 2 = **modo ráfaga**: con él a 1, cada lectura de `$4401` saca un byte nuevo (envía `$FF`), así que un sector de 512 bytes se lee con 512 lecturas seguidas. Bit 3 (solo lectura) = algo de estado: ¿tarjeta presente o protección contra escritura? |
| `$4403` bit 0 (lectura) | SPI libre (la BIOS lo espera después de enviar un byte fuera del modo ráfaga) |

Protocolo: SD en modo SPI normal (CMD0, CMD8, ACMD41, CMD58, CMD17/18 de lectura y CMD24/25 de escritura, con los
testigos `$FE`, `$FC` y `$FD`). La BIOS escribe en la SD con escritura múltiple (`$FC` por bloque y `$FD` para
terminar). Por encima va una FAT (la BIOS tiene la suya) que sabe recorrer carpetas.

**Falta:** el significado exacto de los bits 0 y 3 del reg 2. También si hay que esperar al bit 0 de `$4403` en
modo ráfaga (la BIOS no espera: el CPLD debe de ir más rápido que la CPU) y qué velocidad tiene el SPI.

**Cómo averiguarlo:** etapa 2 (lectura del sector 0 con los dos valores del bit 0 y medida del tiempo). Leer el
reg 2 con y sin tarjeta, y con la pestaña de protección.

**Controlador FAT:** hay que escribirlo o reutilizar uno libre compatible con GPL-3.0. FatFs (licencia BSD de un
artículo) o Petit FatFs (≈ 2-4 KiB, lectura completa, pero solo escribe sin cambiar el tamaño del archivo).
Hace falta FAT32 con SDHC, nombres largos (LFN) para el menú y crear archivos para las partidas. Opción
recomendada: lectura propia y pequeña (FAT16/32, LFN, ordenar en la PRG-RAM) y escritura limitada a sobrescribir
archivos `.SRM` que ya tengan su tamaño. Así un fallo no puede corromper la tabla FAT. Crear la `.SRM` vacía
llega en una etapa posterior.

### 2.2 Carga de un RBF en el FPGA

**Se sabe (BIOS):**

1. Guardar el reg 9 y poner el bit 0 a 0 durante la carga. La BIOS lo hace, probablemente para que el FPGA
   desconfigurado no deje sin código a la CPU. **Ojo:** con el bit 0 a 0, `$8000-$FFFF` vuelve a ser la flash. La
   rutina de carga debe correr desde la RAM de la CPU (`$0000-$07FF`) o desde la ventana `$6000`.
2. **reg 6 = 0 y después reg 6 = 1, con esperas entre medias** (nCONFIG del Cyclone II: borra el FPGA y empieza una
   configuración Passive Serial).
3. Seleccionar la SD (reg 2 bit 1 = 0, modo ráfaga) y el reg 0. Escribir **`$4402` = 5** (modo «configuración»).
4. Por cada bloque: esperar el testigo `$FE` y pasar los 512 bytes **leyendo `$4401` y escribiendo cada byte en
   `$4403`**. El CPLD lo serializa hacia DATA0/DCLK. Descartar el CRC.
5. `$4402` = 3, soltar la SD y devolver el reg 9 a su valor.

El número de bloques sale del tamaño del archivo. Los RBF se rellenan con `$FF` hasta un múltiplo de 512 (ver
[hardware-fpga.md](hardware-fpga.md), «Formato .RBF»), así que no hay que cortar a mitad de sector. Los sectores del
archivo deben ir seguidos en la SD (el bucle de la BIOS lee de un tirón). Si no lo están, hay que repetir el bucle
por cada tramo de clústeres seguidos.

**Falta:** si el CPLD informa de CONF_DONE o nSTATUS (no se ha visto que la BIOS lo compruebe) y cuánto hay que
esperar después de nCONFIG.

**Cómo averiguarlo:** etapa 3. Cargar nuestro 100.RBF y comprobar que contesta, por ejemplo leyendo un registro que
el FPGA conduzca (fase 3d) o lanzando un NROM. Probar también con un RBF roto a propósito para ver si algún bit de
`$4403` o del reg 2 cambia.

### 2.3 Carga de la ROM en las SRAM de PRG y CHR (registros 128-130)

**Se sabe (y ya está implementado en nuestro RTL, `n8_os_iface.v`):**

- **PRG:** ventana de 2 KiB en `$4800-$4FFF` de la SRAM PRG. El reg 128 elige el banco de 2 KiB (PRG
  A18..A11). Se lee y se escribe, solo en modo OS.
- **CHR:** con la PPU apagada, `$0000-$1FFF` de la PPU es la SRAM CHR. Con A12 = 1 se ve el banco de 4 KiB del reg
  130 y con A12 = 0 el anterior (reg 130 − 1). Se escribe con `$2006`/`$2007`. Hay que evitar la zona de
  `0x7E000-0x7FFFF` si se usa la RAM de cuatro pantallas o el menú (ver hardware-fpga.md).
- **PRG-RAM:** reg 129, banco de 8 KiB en `$6000`.
- Rendimiento: la BIOS tiene una rutina que pasa sectores de la SD **directamente a `$2007`**. La CHR no necesita
  una copia intermedia, y la PRG puede ir de la SD a `$4800` en el mismo bucle. Con unos 10 ciclos por byte, una
  ROM de 512 KiB tarda unos 3 s. Más vale contar el tiempo en la etapa 3.

**Falta:** nada esencial. Cuando haya ROMs reales hay que comprobar si la PPU tiene que estar en VBlank o basta
con tenerla apagada.

### 2.4 Configuración del juego (131-136) y salto

**Se sabe (hardware-fpga.md, `n8_os_iface.v`, `N8FpgaMapper.cpp`, que imita al v13):**

| Reg | Valor que escribe el v13 |
|---|---|
| 132 | bancos de 16 KiB − 1 (`cabecera[4] − 1`) |
| 133 | bancos de 8 KiB − 1. **Con CHR-RAM, `$FF`** (bit 7 = CHR-RAM; máscara abierta) |
| 134 | MAP_CFG: `cabecera[6] & $1B`, pasado por la tabla de parches (§3) |
| 136 | modo de reset (bit 0: corto o largo) |
| 135 | Game Genie (nuestros RBF lo ignoran) |
| 131 | **número de mapper, el último**: al escribirlo, el FPGA sale del modo OS |

- Antes de lanzar el juego, el v13 escribe además **reg 9 = 5** (bit 0, el de la BIOS desconectada, y bit 2) y toca
  los bits 2-4 del reg 9 según el juego (lectura, modificación y escritura con las máscaras `$EB` y `$08`). Lee el
  **reg 138** y lo guarda en su estructura de la ROM. Ninguno de los dos está documentado. Hipótesis: el bit 2 del
  reg 9 pone el CPLD en «modo juego» (bloquea sus registros, que en el FPGA se corresponde con `bus_mode` = 01) y
  el bit 3 es el modo de reset o la protección de la PRG-RAM.
- **Salto:** la escritura del reg 131 y el `JMP ($FFFC)` tienen que ejecutarse desde la RAM de la CPU, porque en
  cuanto cambia el mapper `$8000-$FFFF` pasa a ser la ROM del juego. Las sondas del 1.26 lo hicieron así en la
  consola (código en `$0400`, `re-os-1.26-stub-original-r5.md`). El estado de la CPU al saltar debería imitar a
  un reset: `SEI`, `CLD`, S = `$FD`, APU callada (`$4015` = 0 y `$4017` = `$40`) y PPU apagada.

**Falta:** el significado de los bits 2-4 del reg 9, de los regs 10 y 138-140, y si el 138 lo contesta el CPLD.

**Cómo averiguarlo:** etapa 1 (leer el reg 138 y el 9 y mostrarlos en pantalla). Etapa 4: lanzar el mismo juego
con el reg 9 a 1 y a 5 y ver qué cambia, por ejemplo si `$4400` sigue aceptando escrituras dentro del juego o qué
pasa al pulsar reset. Si hace falta, se puede leer lo que haga el v13 con un juego concreto desde su estructura
en la PRG-RAM.

### 2.5 Partidas en `EDFC/SAVE`

**Se sabe:**

- En la SD de fábrica, las partidas se guardan en `EDFC/SAVE/` **con el mismo nombre que la ROM (`.nes`) y 32 KiB
  cada una** (por ejemplo `Kirby's Adventure (USA).nes`), no como `.SRM`. El formato del OS propio se puede
  elegir (§3), pero para no perder las partidas de siempre hay que **leer el formato del v13**.
- Mientras se juega, la partida vive en la PRG-RAM con pila (64 KiB bajos). El v13 la vuelca a la SD **la vez
  siguiente que arranca el OS**, después de un reset. Al arrancar, el v13 mira el byte `$7FFF` del banco 3 de la
  PRG-RAM y lo compara con `'S'`, una marca de «hay partida que guardar». Esa parte del menú no la hemos visto.
- La sonda BIOS_RESPALDO dio por supuesto ese volcado, pero **en la consola no se ha confirmado** que una partida
  sobreviva a un apagado sin reset.
- Famicom Jump II se cuelga si la PRG-RAM empieza a cero (fase 4): un OS propio debe **rellenar con `$FF`** las
  partidas nuevas.

**Falta:** qué parte de la PRG-RAM es de cada juego (¿32 KiB a partir de `0x00000`?), cuándo se escribe la marca y
qué pasa si se apaga sin reset.

**Cómo averiguarlo:** con el v13 de fábrica, jugar a un juego con pila, pulsar reset y comparar la SD antes y
después (archivo nuevo o modificado y su contenido frente a la partida de Mesen2). En la etapa 5 de nuestro OS se
repite con nuestro formato. Hay que guardar antes una copia de `EDFC/SAVE`.

### 2.6 Reset con Select+B (kit Lava)

**Se sabe:**

- El kit Lava genera un reset de la consola. M2 deja de oscilar y el FPGA (el RBF del juego, que incluye la
  interfaz OS) pone el mapper a `$FF` pasados 128 ciclos de `clk`, o 2^25 con el reset largo (reg 136). Por eso
  **cada RBF tiene que llevar `n8_os_iface`**.
- Después, la CPU lee el vector de reset. Si el CPLD mantiene el bit 0 del reg 9, el vector sale de la PRG-RAM, es
  decir, el de la página que copió la BIOS (`$FC40`). Ese código salta a `$C000`, y en la RAM `$C000` es código del
  OS, no su entrada. *Corregido después:* el v13 sobrescribe esos vectores en la RAM (RESET = `$8000`), así que lo
  más probable es que el reset vuelva al v13 ya cargado **sin pasar por la BIOS**, con el RBF del juego en modo OS
  ([bios-n8-clon.md](bios-n8-clon.md) §7). Sigue por medir.

**Falta:** confirmarlo. **Cómo:** en la etapa 1, el «hola mundo» cuenta en la PRG-RAM alta cuántas veces ha
arrancado y anota si la página `$FC00` de la RAM ha cambiado. Si después de Select+B el contador sube y el 255.RBF
está cargado (un registro que solo tenga el 255), la BIOS ha hecho un arranque completo.

### 2.7 USB (si la placa lo trae)

La BIOS atiende un USB de tipo FIFO: datos por el reg 1 y `$4403` bit 1 = hay byte que leer, bit 2 = se puede
escribir. Tiene órdenes de un byte precedidas de `'*'`: `t` (prueba), `f` (cargar el FPGA desde el PC), `r`
(arrancar el OS) y `b`. Si el clon tiene el conector, esto daría un modo de desarrollo sin mover la SD: cargar un
RBF o un OS.BIN desde el PC. **Falta:** comprobar si la placa lo lleva (el original tiene mini-USB).

## 3. Peculiaridades del v13 que un OS propio arreglaría

| Peculiaridad | Efecto hoy | En el OS propio |
|---|---|---|
| Lista en el **orden de la FAT**, sin ordenar ([memoria «menu-os-orden-fat»]) | Hay que copiar a la SD archivo por archivo y en orden. `cp -r` desordena y `menu.entradas()` del banco falla fuera de la pantalla | ordenar por nombre (sin distinguir mayúsculas, con número natural) en la PRG-RAM libre |
| **Páginas de 21 entradas**, Derecha/Izquierda para cambiar de página | navegación lenta en carpetas de cientos de ROMs; el banco tiene que contar páginas | desplazamiento continuo, saltar por letra, buscar |
| **Traducción de mappers** (`$B182`): 219 → 0 y 220 → 4 antes del reg 131, pero el RBF se elige con el número original | Toy Story salía gris; `n8_top.v` tiene un apaño («0 con PRG > 32 KiB» = 219) | pasar el número de la cabecera tal cual. El apaño de `n8_top.v` se queda mientras haya que convivir con el v13 |
| **Tabla de parches de MAP_CFG** por juego (`$AF64`, compara datos de la ROM y cambia bits) | comportamiento oculto que no reproduce el banco de Mesen2 (el puente pasa la cabecera cruda) | sin tabla: la cabecera (NES 2.0 si la hay) manda. Si algún juego necesita un caso especial, se resuelve en su mapper y queda documentado en el repo |
| Solo iNES 1.0 y un byte de mapper (≤ 255) | no hay submappers; los alias se resuelven en el RTL | leer NES 2.0 (submapper, tamaños de RAM) y pasar la información por registros libres (137, 141+) |
| Partidas de 32 KiB con el nombre de la ROM, guardadas al reset siguiente | si se apaga sin reset se pierde la partida (por confirmar) | guardar al volver al menú y avisar en pantalla. Mantener la compatibilidad con el formato del v13 |
| 1 KiB de código de la BIOS en `$FC00` y vectores de la BIOS | el OS depende de una página que no es suya | rutinas propias; vectores propios en la RAM |
| Bloques cifrados u ofuscados | no se puede auditar ni parchear el controlador | todo el código en el repo, GPL |

## 4. Ventajas para el banco de pruebas (`tools/consola/`)

Hoy el banco lee la pantalla para saber dónde está el cursor (`menu.py`: OCR de la fuente del menú, páginas de 21,
orden de la FAT), pulsa botones hasta llegar a la ROM y vuelve con Select+B. Un OS propio puede tener un **modo
banco**:

1. **Lanzar por nombre sin navegar.** Un archivo `EDFC/AUTO.TXT` con una ruta. Al arrancar, el OS lanza esa ROM sin
   mostrar el menú (y si falta, enseña el menú normal). Así se ahorran `ir_a_carpeta`, `elegir` y los fallos de
   «no consigo elegir».
2. **Listas de ejecución.** `EDFC/LISTA.TXT` con N rutas. El OS guarda en la PRG-RAM alta (`0x10000-0x11FFF`) el
   índice actual y, después de cada Select+B, lanza la siguiente. Una tanda completa (como la de cobertura del
   13-11) correría sin tocar el menú. El PC solo mira la captura, pulsa los guiones y hace el reset.
3. **Identificación en pantalla.** Antes de saltar al juego, un fotograma con el nombre, el CRC32, el mapper y el
   RBF en letras grandes, o un código de barras de colores que `captura.py` lea sin OCR. La captura queda
   etiquetada aunque la SD esté desordenada.
4. **Informe en la SD.** El OS escribe en un archivo, sobrescribiendo una `.TXT` de tamaño fijo, qué lanzó, cuándo
   y con qué registros. Si un juego cuelga la consola, la siguiente vuelta deja constancia de dónde iba la lista.
5. **Sin traducciones ni parches ocultos.** Lo que se lanza en la consola es exactamente lo que el banco de Mesen2
   simula: el puente `N8FpgaMapper.cpp` dejaría de imitar el `$B182`.
6. **Una ROM de diagnóstico integrada**: mostrar los registros del CPLD, una prueba de la SRAM (como la «self test»
   de la BIOS) y la versión de cada RBF. Sirve también para estudiar el CPLD (§2.4).

## 5. Riesgos

| Riesgo | Gravedad | Mitigación |
|---|---|---|
| **Escribir en la flash de la BIOS** por error (el M29W160 acepta órdenes en `$8000-$FFFF` con el bit 0 del reg 9 a 0) | alta: sin BIOS el cartucho no arranca y hace falta un programador | el OS nunca escribe en `$8000-$FFFF` con la BIOS conectada. La carga del FPGA corre desde la RAM y no escribe en esa zona. Revisión de código específica para eso. Las sondas del 1.26 solo usaron la consulta CFI (`$98`/`$F0`) |
| Corromper la FAT de la SD al escribir | media | SD de pruebas e imagen con `dd` antes de cada etapa con escritura. En las primeras etapas, solo sobrescribir archivos que ya existen |
| Perder partidas de la PRG-RAM con pila | media | copiar `EDFC/SAVE` y no tocar `0x00000-0x0FFFF` fuera de la rutina de partidas |
| Bits del CPLD que no entendemos (reg 9 bits 2-4, reg 10, 138-140) | media: un juego que no guarda o un reset que no vuelve | medirlos en las etapas 1 y 4 y, mientras tanto, copiar los valores del v13 (son números que describen el hardware, no código) |
| La BIOS de otros clones es distinta | baja | no depender de la página `$FC00` de la BIOS; detectarla y avisar |
| Tiempo: FAT, LFN, ordenar y partidas son el grueso del trabajo | — | etapas pequeñas, cada una usable; cc65 en C para el menú y ensamblador para la E/S |
| Licencia | baja | código propio. Si se usa FatFs o Petit FatFs, su licencia BSD es compatible con GPL-3.0 |

**Volver al OS de fábrica:** el v13 es un archivo. Basta con copiar el `OS.BIN` de fábrica (57 344 B, md5
`f5ac5490a1556def02829b020e14ca80`, copia en `~/Documents/SD_N8/EDFC/`) encima del nuestro en `EDFC/`. La BIOS y el
255.RBF no cambian. Si nuestro OS se cuelga antes de pintar nada, no pasa nada más: se apaga, se cambia el archivo
en el PC y listo. Ninguna etapa toca la flash.

## 6. Plan por etapas

Cada etapa produce un `OS.BIN` que se puede probar, y la anterior sigue disponible. Antes de empezar: SD de pruebas
con `EDFC/MAPS/255.RBF` de fábrica, nuestros 100-106, `MAPROUT.BIN` y una copia del v13 al lado (`OS_V13.BIN`)
para volver.

0. **Preparación (sin consola).** Proyecto cc65 en `os/` (enlazador a `$8000-$FBFF` más bancos en `$6000`;
   archivo de tamaño múltiplo de 8 KiB, primer byte distinto de `$EA` y `$FC00-$FFFF` vacío). El modelo del CPLD y
   de la SD ya existe en `tools/bios/` y arranca el OS con la BIOS real en el PC. Falta llevarlo a Mesen2 si hace
   falta ver la imagen.
1. **«Hola mundo».** *Hecho en [`os/`](../os/LEEME.md); probado con la BIOS real en el emulador, falta la consola.* Pinta texto, lee el mando y muestra en hexadecimal: S, los regs 2, 9, 10 y 138-140 leídos por
   `$4401`, `$4403`, los primeros bytes de la RAM de la CPU y de la página `$FC00`, y un contador de arranques en la
   PRG-RAM alta. Responde a §1.3, §2.4 y §2.6. Select+B prueba el camino del reset.
2. **SD.** Inicialización propia (CMD0/8/ACMD41/58), lectura del sector 0, MBR, partición y FAT32. Muestra la raíz.
   Mide la velocidad con el bit 0 del reg 2 a 0 y a 1.
3. **Lanzar un NROM.** Cargar `100.RBF` (§2.2), copiar PRG y CHR (§2.3), regs 132-134 y 136, y saltar desde la RAM
   (§2.4). Prueba: `calibracion.nes` del banco y Super Mario Bros.
4. **Todos los mappers.** `MAPROUT.BIN`, número de la cabecera sin traducir, CHR-RAM (`$FF`), cuatro pantallas,
   ROMs grandes y cargas por tramos de clústeres. Prueba: la tanda de cobertura (`tools/n8sim/cobertura.py`) con el
   banco de la consola. Aquí se estudian los bits 2-4 del reg 9.
5. **Partidas.** Leer y escribir el formato del v13 (§2.5), con relleno `$FF` para las nuevas. Guardar al volver al
   menú. Prueba: Zelda y Kirby con partidas de verdad, con copia previa de `EDFC/SAVE`.
6. **Menú completo.** Orden alfabético, LFN, carpetas, desplazamiento continuo, búsqueda por letra, último juego e
   información de la ROM (mapper, tamaños, CRC).
7. **Modo banco** (§4): `AUTO.TXT`, `LISTA.TXT`, fotograma de identificación e informe en la SD. Adaptar
   `tools/consola/` para que no navegue cuando el OS propio está presente.
8. **Opcional: 255.RBF propio** (el modo OS de `n8_os_iface.v` como RBF aparte). Así solo quedarían de Krikzz la
   BIOS de la flash y el CPLD, que no se tocan.

Orden de esfuerzo estimado: las etapas 0-3 son lo que confirma la viabilidad en la consola. Las etapas 4-6
concentran el trabajo (FAT, partidas y menú). La 7 es la que más ahorra en el banco.

## 7. Resumen de lo que falta medir

| Pregunta | Etapa | Bloquea |
|---|---|---|
| Estado exacto al saltar a `$8000` (S, regs 2 y 9, PPU, SD) | 1 | no (el OS lo reinicia todo) |
| ¿Select+B pasa por la BIOS (arranque completo)? | 1 | partidas y lista del banco |
| Bits 0 y 3 del reg 2; velocidad del SPI | 2 | no |
| ¿Hay CONF_DONE o nSTATUS en el CPLD? Esperas de nCONFIG | 3 | no (la BIOS carga a ciegas) |
| Bits 2-4 del reg 9, reg 10, regs 138-140 | 1 y 4 | puede afectar a partidas y reset |
| Formato y momento del volcado de partidas del v13 | 5 (con el v13 de fábrica) | compatibilidad con las partidas existentes |
| ¿El clon lleva el USB? | cualquiera (mirar la placa) | no |
| ¿Cómo se descifran los bloques del v13? | — | no (curiosidad) |
