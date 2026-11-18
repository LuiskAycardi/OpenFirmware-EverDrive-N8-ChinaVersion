# OS propio del EverDrive N8 clon — etapa 4: carpetas y nombres largos

`OS.BIN` propio (GPL-3.0-or-later): arranca desde la BIOS del cartucho, lee la microSD (solo lectura), recorre sus
carpetas con nombres largos y lanza los juegos con nuestros RBF (ver
[docs/os-propio-viabilidad.md](../docs/os-propio-viabilidad.md) y [docs/bios-n8-clon.md](../docs/bios-n8-clon.md)).
Funciona con el `255.RBF` de fábrica.

**Qué no hace**, a propósito: no toca la flash de la BIOS, no escribe en la SD y no toca la PRG-RAM de las
partidas ni el estado del OS de fábrica. Solo escribe en la RAM de la CPU, en su propia imagen (`$8000-$FFFF`), en
la PPU, en el reg 130 del FPGA (banco de la CHR, igual que el v13) y, al arrancar, reg 9 = 01 en el CPLD (el valor
que deja la BIOS).

## Compilar y probar en el PC

```bash
make -C os
```

Sale `os/build/OS.BIN`: 32 KiB, primer byte `SEI` y la página `$FC00` vacía. `comprobar_os.py` comprueba
estos requisitos en cada compilación.

Prueba con la BIOS real en el modelo de `tools/bios` (la BIOS no está en el repo, ver
[tools/bios/README.md](../tools/bios/README.md)):

```bash
python3 -I os/herramientas/probar_os.py --bios /ruta/bios.bin --rbf ~/SD_Pruebas/EDFC/MAPS/255.RBF --trabajo /tmp/carpeta-nueva
```

Comprueba (19 casos) que:
- la BIOS salta a `$8000` y aparece la pantalla, con el mando en vivo;
- el encendido sale como FRIO, un reset como RESET y una vuelta de juego como VUELTA DE JUEGO, con sus contadores;
- una ráfaga de resets como la del kit Lava no rompe nada;
- del CPLD solo se escribe reg 9 = 01, y no se toca la flash, la SD ni la PRG-RAM de las partidas.

## Instalar en la SD de pruebas

1. **Antes de nada, arranca una vez el OS de fábrica** después de la última partida con pila. El v13 guarda las
   partidas pendientes al arrancar y el nuestro no lo hace.
2. En la SD, copia `EDFC/OS.BIN` (el v13, md5 `f5ac5490…`) como `EDFC/OS_V13.BIN`. Guarda también una copia en
   el PC.
3. Borra `EDFC/OS.BIN` y copia `os/build/OS.BIN` en su lugar. Deja el `255.RBF` de fábrica.
4. **El archivo tiene que quedar contiguo** (docs/bios-n8-clon.md §3). Con 32 KiB, basta con que el clúster de la
   SD mida 32 KiB o más. Para ver el tamaño del clúster:
   ```bash
   stat -f -c %S /run/media/tester/SD_N8
   ```
   Si sale menos de 32768 y la pantalla no aparece, prueba en una SD recién formateada.

Para volver: borra `EDFC/OS.BIN` y copia `EDFC/OS_V13.BIN` como `EDFC/OS.BIN`. Nada más cambia.

## Arranque y reset (`src/arranque.s`)

La CPU entra siempre por `$8000`, en modo OS. El OS distingue tres casos con una firma (`N8OS`) en su zona de
estado, que está dentro del propio OS.BIN en la PRG-RAM: sobrevive a los resets y la BIOS la deja a cero en cada
encendido.

| Tipo | Cuándo | Cómo se reconoce |
|---|---|---|
| **FRIO (BIOS)** | encendido: la BIOS acaba de cargar el OS.BIN | no hay firma |
| **RESET** | botón RESET o kit Lava (Select ~2 s y luego Select+A) estando en el OS | hay firma y `en_juego` = 0 |
| **VUELTA DE JUEGO** | reset estando en un juego: el RBF vuelve al modo OS | hay firma y `en_juego` = 1 |

- El reset no pasa por la BIOS: la CPU usa el vector RESET que el OS deja en la RAM (`$FFFC`).
- Con el Lava llegan varios resets seguidos (cada 1,4 s mientras se mantiene Select+A), así que la entrada es
  rápida y repetible.
- En los tres casos deja igual el hardware: PPU y APU apagadas y sin interrupciones, reg 9 = 01, vectores propios,
  RAM de la CPU a cero y espera de dos VBlank.
- **Contrato con el lanzador de juegos (etapa 3):** antes de escribir el reg 131, poner `en_juego` = 1 y guardar
  en `ultimo_juego` (2 bytes) lo necesario para volver a poner el cursor sobre el juego. El arranque borra la marca.
- El mando se lee una vez por fotograma en la NMI, como el v13 (`$4017 | $4016`, bits 0 y 1).

## La pantalla

| Fila | Qué es |
|---|---|
| 2 | título y etapa |
| 3 `Arranque:` | tipo del último arranque: frío (BIOS), reset o vuelta de juego |
| 4 `Ent/res/vue:` | contadores desde el último encendido: entradas, resets y vueltas de un juego |
| 5 `SD:` | SDHC o SDSC, FAT16 o FAT32 y sectores por clúster (o `error nn R1=xx`) |
| 7 | carpeta actual («Raíz» o su nombre) y, a la derecha, página/páginas |
| 9-24 | la lista: 16 entradas por página |
| 25 | mensajes (por qué no se puede lanzar algo) |
| 26 | ayuda: `A abrir  B volver  ◀▶ página` |
| 27 `Mando:` | botones en vivo: A B S(elect) T (Start) U (arriba) D (abajo) L (izquierda) R (derecha) |

Los registros de la CPU y del CPLD al entrar se siguen guardando en el estado (`e_*` de `arranque.s`), pero ya no se
ven en pantalla. Las primeras etapas también mostraban la partición, la zona de datos y una medida de lectura de
32 KiB; se quitaron para dejar sitio a la lista (y el arranque es unos 0,3 s más rápido).

## Resultados en la NES (2026-11-16, con la capturadora y el Nano)

| Paso | ARRANQUE | Entradas / resets / vueltas |
|---|---|---|
| Encendido | FRIO (BIOS) | 01 / 00 / 00 |
| `mando.py reset-boton` | RESET | 02 / 01 / 00 |
| `mando.py reset-mando` (Lava, Select 2,5 s y Select+A 5 s) | RESET | 06 / 05 / 00 (4 resets seguidos) |
| `mando.py reset-boton` | RESET | 07 / 06 / 00 |

- Registros al entrar en frío: CPU `01 FF 00 FB 35`; reg 2 = `09`, reg 9 = `01`, reg 10 = `01`; regs 138-140 =
  `44` (bus abierto); `$4403` = `01`. Los 8 botones se leen bien.
- La VUELTA DE JUEGO solo está probada en el emulador: hace falta el lanzador de la etapa 3.
- El Nano cuenta los mismos resets que la pantalla: `reset-mando` devuelve `reset=4 sil=87` y RESETS sube 4. Este
  OS está 87 ms sin leer el mando en cada reset (el v13, unos 700 ms); el Nano cuenta como reset 60 ms de silencio, el punto medio
  entre un fotograma sin lectura (33 ms) y esos 87 ms.
- Historia de las pruebas del reset (Select+B no resetea, ni con el v13; el Lava usa Select y luego Select+A; cuatro
  formas de leer el mando y el bit 2 del reg 9 no cambian nada): [docs/bios-n8-clon.md](../docs/bios-n8-clon.md) §7.

## Etapa 2: lectura de la SD (`src/sd.s`, `src/fat.s`)

- **Solo lectura:** el código no tiene ninguna orden de escritura en la tarjeta.
- `sd.s`: SPI por el CPLD (reg 0 dato, reg 2 control, `$4403` bit 0 libre). Al arrancar corta con CMD12 la lectura
  múltiple que deja la BIOS y vuelve a inicializar la tarjeta (CMD0, CMD8, ACMD41, CMD58), con el reg 2 como lo
  usa la BIOS: bits 0 y 3 a cero mientras inicializa; después bit 0 (rápido) y bit 3 si es SDHC. Lee sectores con
  CMD17 y el modo ráfaga.
- `fat.s`: MBR o tarjeta sin particiones, FAT16 y FAT32, y el directorio raíz siguiendo la cadena de clústeres
  (salta nombres largos, borrados y la etiqueta). Por ahora muestra solo los nombres cortos 8.3.
- La pantalla (`src/principal.s`) muestra la tarjeta, la FAT, el número de entradas de la raíz, las 13 primeras y
  el tiempo de leer 32 KiB. Si algo falla, `SD: ERROR nn R1=xx` (01 CMD0, 02 ACMD41, 03 CMD58, 04 CMD17, 05 datos,
  06 firma del sector 0, 07 sector de arranque, 08 clúster).
- El mando no se lee hasta que termina el arranque: cada reset deja un silencio largo sin LATCH, que el Nano del
  banco cuenta como reset.

### Resultados en la NES (2026-11-16)

- Tarjeta de 4 GB: `SDHC FAT32 CLUSTER 08`, partición en `0x800`, datos en `0x4320`; raíz con 5 entradas, todas
  correctas (EDFC, PRUEBAS, IRQ65.NES y los dos Super Mario con su tamaño).
- 32 KiB en 18 fotogramas (`0012`): unos 109 KiB/s leyendo sector a sector.
- Con el bit 0 del reg 2 a 0, la lectura de datos falla: es el SPI rápido (la prueba se quitó del arranque).
- Botón RESET y ráfaga de 4 resets del Lava (algunos en mitad de la lectura): después lee la tarjeta sin errores.
- Con la NMI leyendo el mando desde el principio, el Nano veía solo 54 ms de silencio por reset y no los contaba;
  por eso ahora el mando no se lee durante el arranque. Probado en la NES: el silencio por reset pasa a 419 ms y
  el Nano cuenta igual que la pantalla (`reset-mando` con 5 s: `reset=4`, contadores 02/01 → 06/05; con 2 s:
  `reset=2`, 06/05 → 08/07). La tarjeta se lee bien después de cada reset.

## La fuente (`herramientas/fuente.py`)

Dibujada desde cero para verse bien en un CRT: trazos de 2 píxeles, formas redondeadas, mayúsculas y minúsculas.
Lleva á é í ó ú ñ ü, sus mayúsculas, ¿ ¡ º ª y un cursor (tiles `$20-$9F`; las constantes de los caracteres que no
son ASCII están en `src/os.inc`). Para ver una muestra:

```bash
python3 -I os/herramientas/fuente.py /tmp/fuente.chr /tmp/fuente.png
```

## Etapa 3: lanzar un juego (`src/lanzar.s`)

En la lista, **A o Start** sobre un juego lo lanzan (las carpetas: etapa 4). Con Select pulsado no se
lanza nada: Select y luego Select+A es el reset del kit Lava.

1. **Cabecera iNES:** PRG (hasta 512 KiB), CHR (hasta 512 KiB), mapper y byte 6. Si hay «trainer», se salta.
2. **`EDFC/MAPROUT.BIN`:** el byte número *mapper* da el RBF (`$FF` = no hay).
3. **`EDFC/MAPS/NNN.RBF`:** tiene que estar contiguo en la tarjeta (se comprueba en la FAT); se pasa al FPGA con una
   lectura múltiple.
4. **Carga del FPGA**, desde la RAM de la CPU (`$0200`), porque mientras tanto no hay nada en `$8000-$FFFF`: reg 9 a 0,
   pulso de nCONFIG (reg 6), `$4402` = 5, cada byte de `$4401` a `$4403`, 512 bytes `$FF` de relojes de sobra,
   `$4402` = 3 y reg 9 de vuelta a 1. Son los pasos de la BIOS.
5. **PRG** por la ventana `$4800` (reg 128) y **CHR** por la PPU (reg 130). **Carga rápida:** la ROM se lee con una
   lectura múltiple (CMD18) por cada tramo de clústeres seguidos, y cada bloque de 512 bytes va directo del SPI a
   `$4800` o a `PPUDATA`, sin búfer. Como la cabecera iNES ocupa 16 bytes (528 con trainer), todos los cortes (bancos
   de 2 KiB de PRG, paso de PRG a CHR, bancos de 8 KiB de CHR) caen en el byte 16 de un bloque: cada bloque se copia
   en trozos de 16, 256 y 240 bytes con bucles desenrollados. Los sectores de la FAT se guardan en caché.
6. **Registros:** 132 = bancos de 16 KiB − 1; 133 = bancos de 8 KiB − 1, o `$FF` con CHR-RAM; 134 = byte 6 de la
   cabecera `& $1B`; 136 = 0. Marca `en_juego` y, desde la RAM, **reg 131 = mapper de la cabecera, sin traducir**, y
   salto al vector de reset del juego (S = `$FD`, A = X = Y = 0, `$4017` = `$FF` como el v13).

Al resetear dentro del juego (botón RESET, o el Lava mantenido), el OS arranca como «vuelta de juego» y deja el
cursor sobre el juego.

Si algo falla, lo dice en pantalla y el menú sigue: «No es una ROM iNES», «Tamaño de ROM no admitido», «Falta
EDFC/MAPROUT.BIN», «Mapper sin RBF: nn», «No encuentro el RBF nnn», «RBF fragmentado en la SD», «Error de lectura
nn», «El FPGA no se configura».

Límites: no hay partidas guardadas (un juego con pila arranca con lo que haya en la PRG-RAM).

### Resultados en la NES (2026-11-17, con la capturadora y el Nano)

- **Super Mario Bros.** (mapper 0, 40 KiB): se lanza con A, juega con el 100.RBF; carga en 1,7 s.
- **Super Mario Bros. 3** (mapper 4/MMC3, 384 KiB): título y menú correctos; carga en unos 9,5 s (unos 40 KiB/s).
- **Carga rápida** (2026-11-17, de pulsar A a ver el juego, medido con la capturadora): SMB3 en **3,8 s** (antes
  9,5 s) y SMB en **1,5 s** (antes 1,7 s). Descontando lo fijo (RBF y arranque, ~1,2 s), unos 145 KiB/s.
- **Botón RESET dentro de un juego:** vuelve al menú como «vuelta de juego», con el cursor sobre el juego.
- **Reset por el mando (Lava) en el menú:** 4 resets, los mismos en el Nano y en la pantalla.
- A sobre una carpeta: «Carpetas: en otra etapa» (hasta la etapa 4).
- Una vez se vio SMB3 con los gráficos revueltos tras un reset; lo más probable es un reset corto del Lava dentro
  del juego (el juego vuelve a arrancar sin pasar por el menú, igual que con el v13). No se ha reproducido.
- Al enchufar el Nano con la consola encendida, la consola quedó colgada y el botón RESET no la recuperó: hubo que
  apagar. Probablemente los pulsos de la línea de datos lanzaron algo a medias.

## Etapa 4: carpetas y nombres largos (`src/principal.s`, `src/fat.s`)

**Mando:** arriba y abajo mueven el cursor (al pasar del borde, a la página siguiente o anterior, dando la vuelta);
derecha e izquierda cambian de página; **A o Start** abren la entrada: una carpeta se recorre y un juego se lanza;
**B** vuelve a la carpeta de arriba con el cursor donde estaba. Con Select pulsado no se hace nada (Select y luego
Select+A es el reset del kit Lava).

**Nombres:**
- El nombre largo (LFN) si lo hay y es válido: sus trozos se juntan en `dir_siguiente` y valen si la suma de
  comprobación coincide con la del nombre 8.3 que los sigue. Se guardan los primeros 64 caracteres.
- Los caracteres UCS-2 pasan a la fuente: ASCII tal cual; á é í ó ú ñ ü Á É Í Ó Ú Ñ Ü ¿ ¡ º ª con su dibujo; otros
  acentos latinos (à ö ç…) en la letra sin acento; lo demás, «?».
- Sin nombre largo, el 8.3, con las minúsculas que marca Windows en el byte 12 (`zelda.nes`).
- Sin la extensión `.nes`; las carpetas acaban en «/»; si no cabe en 28 columnas, «…» al final.
- No se listan «.», «..», lo oculto ni lo que empieza por punto (como los `._juego.nes` que deja macOS).

**Cómo:** al entrar en una carpeta, el OS la recorre una vez con la pantalla apagada: cuenta las entradas y guarda
dónde empieza cada página (12 bytes por página: sector, clúster, sectores que quedan, entrada y estado; `dir_guardar`
de `fat.s`). Cambiar de página es volver a esa posición (`dir_restaurar`) y leer 16 entradas, con la pantalla
encendida: el texto se prepara en la RAM y se sube a la PPU a dos filas por fotograma. Caben 255 páginas (4080
entradas por carpeta) y 8 carpetas de profundidad («Demasiadas carpetas»).

**Memoria:** la caché de páginas, el texto de la lista y la ruta (clúster, página y fila del cursor y nombre de cada
carpeta) están en el segmento `GRANDE` (`$E000-$FAFF`), dentro de la imagen del OS en la PRG-RAM: la BIOS lo deja a
cero al encender y sobrevive a los resets y a la vuelta de un juego. Por eso, al volver de un juego con RESET, el menú
abre su carpeta con el cursor sobre él; un reset estando en el menú se queda en la carpeta.

**Pruebas** (`herramientas/probar_os.py`): raíz de 62 entradas en 4 páginas (FAT16 y FAT32) con izquierda y derecha
dando la vuelta; entrar en EDFC y volver con B; una carpeta con 40 juegos de nombre largo con acentos (3 páginas,
cambio de página por el borde), una carpeta vacía, un archivo borrado con nombre largo, un `._` de macOS, un archivo
oculto, un nombre cortado, un 8.3 en minúsculas, otros acentos; lanzar un juego MMC3 a dos carpetas de profundidad y
volver a él con RESET; volver a la raíz con B.

### Resultados en la NES (2026-11-17, con la capturadora y el Nano, SD de pruebas de 4 GB)

- Raíz y `PRUEBAS` (26 entradas, 2 páginas): nombres largos, «/» en las carpetas, «…» en los que no caben; Derecha
  pasa a la página 2/2.
- Entrar en `PRUEBAS/5 Fase 3a` y lanzar Akira (mapper 33): arranca. **RESET** vuelve a `5 Fase 3a` («vuelta de
  juego») con el cursor sobre Akira; **B** sube a `PRUEBAS` con el cursor sobre `5 Fase 3a`, y otro B a la raíz con
  el cursor sobre `PRUEBAS`.
- `PRUEBAS/14 RBF 105` (45 entradas, 3 páginas): Arriba en la primera fila lleva a la 3/3 con el cursor en la última.
- **Reset por el mando (Lava) dentro de una carpeta:** 4 resets en el Nano y en la pantalla (`Ent/res/vue: 06 04
  01`); el menú se queda en la carpeta.
- **Toy Story (mapper 219)** se quedaba en negro: su cabecera es NES 2.0 (byte 7 = `$D8`) con datos en los bytes
  12 y 15 (región y mando), y el lanzador la tomaba por una cabecera antigua con basura y usaba solo el nibble bajo:
  mapper 11. Corregido (ver «Cabecera» abajo): Toy Story y Wario Land 2 (35) arrancan. De las 255 ROMs de la
  colección de pruebas, 93 tienen esa cabecera y salían con el mapper equivocado.

**Cabecera** (`lanzar.s`, paso 1), según la regla de nesdev.org: si los bits 3-2 del byte 7 valen `10` es NES 2.0 y
el nibble alto del byte 7 vale siempre (si el byte 8 pide un mapper de más de 8 bits: «Mapper sin RBF»; si el byte
9 pide más tamaño: «Tamaño de ROM no admitido»). Si valen `00` y los bytes 12-15 son cero, iNES: también vale. En
otro caso (como «DiskDude!»), solo el nibble bajo del byte 6.

Pendiente: partidas guardadas, menú completo (orden alfabético, información del
juego), modo banco.
