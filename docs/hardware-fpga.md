# N8 (original / clon) — interfaz de la FPGA

Fuente: kit de desarrollo publicado por Krikzz (`ref/krikzz-n8-dev/`, archivos de 2013–2017:
`fpga-mapper-sample.zip`, `mmc5-src.zip`). Aquí solo se documentan **hechos** (pines, protocolo);
el código de nuestros mappers se escribe desde cero.

Supuesto a verificar: el clon usa el mismo conexionado que el original (si no, los .RBF oficiales
no funcionarían en él). Primera prueba real: NROM propio (paso 5).

## Dispositivo
- Cyclone II **EP2C5T144C8**, I/O **3.3-V LVTTL**, configuración **Passive Serial** (la carga el CPLD MAX II desde SD).
- Pines no usados: entrada triestado con pull-up débil. nCEO y ASDO usados como I/O normal.
- El mapper de ejemplo y el MMC5 usan **exactamente las mismas 88 asignaciones**.

## Pinout (pin físico → señal)
Activo-bajo salvo que se indique. `cpu_ce` = /ROMSEL de la NES.

### Bus CPU
| Señal | Pines |
|---|---|
| cpu_addr[0..14] | 67, 65, 64, 63, 60, 48, 47, 45, 44, 43, 26, 25, 28, 24, 30 |
| cpu_dat[0..7] (bidir) | 87, 86, 81, 80, 72, 71, 70, 69 |
| cpu_ce (/ROMSEL) | 88 |
| cpu_rw | 94 |
| cpu_m2 | 27 |
| mclk (M2 otra vez, en pin de reloj global) | 21 |
| cpu_irq (open-drain: 0 o Z) | 96 |
| cpu_exp (EXP; en la Famicom, salida de sonido de expansión como PWM de 1 bit; Z sin chip de sonido) | 97 |

### Bus PPU
| Señal | Pines |
|---|---|
| ppu_addr[0..13] | 115, 114, 113, 112, 93, 91, 9, 92, 4, 104, 101, 103, 2, 3 |
| ppu_dat[0..7] (la FPGA solo lee; se deja en Z) | 119, 120, 121, 122, 139, 137, 136, 135 |
| ppu_rd / ppu_wr | 89 / 90 |
| ppu_ciram_ce / ppu_ciram_a10 | 99 / 100 |
| ppu_dir (dirección del transceptor de datos PPU; = /RD) | 7 |
| ppu_ex (habilita el transceptor; = !ciram_ce) | 8 |

### SRAM PRG (CY7C1049, 512 KB) y PRG-RAM (IS62LV1024, 128 KB)
| Señal | Pines |
|---|---|
| prg_map[0..8] → A10..A18 | 58, 59, 57, 55, 53, 73, 74, 75, 76 |
| prg_ce / prg_oe / prg_we | 52 / 79 / 51 |
| ram_ce / ram_oe / ram_we | 32 / 42 / 31 |

**A0–A9 de la SRAM vienen directo del bus CPU** (no pasan por la FPGA) → la granularidad
mínima de banco es 1 KB. Las dos memorias PRG comparten `prg_map`.

### SRAM CHR (CY7C1049, 512 KB)
| Señal | Pines |
|---|---|
| chr_map[0..8] → A10..A18 | 1, 144, 143, 142, 141, 133, 132, 129, 126 |
| chr_ce / chr_oe / chr_we | 118 / 134 / 125 |

A0–A9 directo del bus PPU, igual que en PRG.

### Otros
| Señal | Pin | Uso |
|---|---|---|
| clk | 17 | reloj del sistema: **50,000 MHz**, oscilador propio en la placa (visto en el N8 de Famicom y en el de NES) |
| max0, max1 (salidas) | 40, 41 | `bus_mode` hacia el CPLD |
| max2 (entrada) | 18 | `bios_off` desde el CPLD |

`bus_mode`: `11` = registros del CPLD desbloqueados (OS), `01` = juego (bloqueados),
`00` = LED / espía de bus, `10` = forzar salidas de bus.

## Protocolo OS ↔ FPGA (mapper 255, "OS map")
Todo .RBF debe incluir un bloque equivalente, porque el OS lo usa para configurar el juego
antes de saltar a él. Mientras `map_idx == 0xFF` está activo el modo OS.

- Registros en **$4400–$45FF** (/ROMSEL alto, A14..A9 = `100010`):
  - `$4400` (A1:A0 = 00): escribir número de registro.
  - `$4401` (A1:A0 = 01): escribir dato (solo en modo OS).
- Escrituras capturadas en flanco de bajada de M2.

| Reg | Nombre | Bits | Efecto |
|---|---|---|---|
| 128 | PRG_MAPA | 7:0 | banco de 2 KB de PRG visible para el OS |
| 129 | SRM_MAPA | 5:0 | banco de 8 KB de PRG-RAM en $6000 |
| 130 | CHR_MAPA | 6:0 | banco CHR visible para el OS |
| 131 | MAPPER | 7:0 | **número de mapper a activar** (≠ 0xFF → arranca el juego) |
| 132 | PRG_SIZE | 4:0 | máscara PRG A18..A14 = nº de bancos de 16 KB − 1 |
| 133 | CHR_SIZE | 5:0, bit 7 | máscara CHR A18..A13 = nº de bancos de 8 KB − 1; con **CHR-RAM** el OS escribe **$FF** |

⚠️ **Verificado en OS.BIN (v13, rutina en `$BB7E`):** con CHR-RAM (CHR = 0 en la cabecera),
el OS escribe `$FF` en el reg 133: bit 7 = CHR-RAM y la máscara **abierta del todo** (512 KB).
Por eso **cada mapper debe recortar él mismo la dirección de la CHR-RAM** (normalmente a 8 KB).
Si no lo hace, los bits altos de los registros CHR que tienen otros usos (p. ej. la selección de
PRG de SUROM) desplazan la CHR-RAM. Este fue el fallo gráfico de Dragon Warrior IV en la fase 1.
| 134 | MAP_CFG | 6:0 | opciones del mapper; bit 0 = **mirroring** (1 = vertical); bit 3 = **4 pantallas** (protocolo nuestro, ver abajo) |
| 135 | GG | — | carga de hasta 5 códigos Game Genie (escrituras byte a byte) |
| 136 | CART_CFG | 0 | modo de reset (corto/largo) |

**MAP_CFG y la cabecera iNES (OS v13, `$BDFB`):** el OS guarda `cabecera[6] & $1B`
(bits 0 mirroring, 1 batería, 3 cuatro pantallas, 4) en su estructura de la ROM. Una rutina con
tabla de parches por juego (`$AF64`) produce el valor final de MAP_CFG. **Comprobado en la consola:**
el bit 0 (mirroring, con NROM) y el bit 3 (4 pantallas, con Rad Racer II y nuestro RBF) llegan
igual que en la cabecera.
**Protocolo propio (para nuestro OS):** MAP_CFG bit 3 = 4 pantallas, igual que en la cabecera.
Con él activo, en modo juego el top-level manda `$2000-$3EFF` (con `$3000` espejo de `$2000`)
a 4 KB de la SRAM CHR, en `0x7E000-0x7EFFF` y sin máscara CHR_SIZE. La CIRAM se apaga y
`ppu_ex` = 0. Sirve para cualquier mapper. `0x7F000-0x7FFFF` se evita porque el menú del OS lo
ve en `$0000` con el registro 130 = 0.

**Excepciones a las 4 pantallas (fase 3c):** en los mappers 78 (Holy Diver), 137 (The Great Wall) y
154 (Devil Man) el bit 3 de la cabecera es una marca de "mirroring controlado por el mapper"
(convención iNES), no RAM extra: el top-level no activa la RAM de 4 pantallas con esos números. En
el 78 el bit elige además la placa (Holy Diver = mirroring H/V; sin él, pantalla única).

**CHR-RAM extra fuera de la máscara (fase 3c):** el bus de cada mapper tiene un bit 27, `chr_raw`, que
quita la máscara CHR_SIZE del OS en ese acceso. Lo usa el TQROM (119): 64 KB de CHR-ROM más 8 KB de
CHR-RAM, que van a CHR `0x7C000-0x7DFFF` (fuera de la ROM, de la RAM de 4 pantallas y del menú).

**Bus de datos de la PPU sin conducir = $FF (fase 3c):** los 8 pines `ppu_d` llevan el pull-up débil
de la FPGA (~25 kΩ, asignación del QSF). Cuando ni la SRAM CHR ni la CIRAM están seleccionadas, el
transceptor entrega a la PPU $FF en vez de un valor flotante. Lo necesitan los mappers que apagan
la CHR como protección (185: Mighty Bomb Jack exige D0 = 1) y el 93. No conduce nada: la SRAM CHR
lo vence sin problema.

**Varios RBF (fase 3c):** `hdl/rtl/n8_top.v` reparte los mappers con las macros `N8_RBF_100`
(fases 1-3b y sus variantes) y `N8_RBF_101` (chips nuevos de la fase 3c). `make build` genera un
proyecto de Quartus por RBF (`tools/gen_qsf.py`, desde la plantilla `quartus/n8_nrom.qsf`) y deja
`out/100.RBF` y `out/101.RBF`. MAPROUT.BIN dirige cada número de mapper a su RBF. En simulación y en
el banco de pruebas, sin macro, entran todos.

**Sonido de expansión (fase 3s):** sale por el pin 97 (`cpu_exp`) como señal de 1 bit. `audio_dac.v` es un
sigma-delta a 50 MHz: proporción de ciclos bajos = nivel / 1024; en silencio la salida está alta (misma
polaridad que el PWM del MMC5 del kit de Krikzz). En la Famicom la placa la filtra y la mezcla con el audio de
la consola; en el NES va al pin EXP, sin conectar. Con un mapper sin sonido el pin queda en Z.

**Conducir el bus de datos de la CPU: implementado en la fase 3d** (`n8_top.v`). Cada mapper con registros
legibles da `cpu_dout` y `cpu_doe` (bits que conduce el chip real; el resto, bus abierto: la FPGA deja esos
pines en Z y la CPU lee lo que quedó en el bus). El top conduce solo si: lectura, M2 alto, fuera del OS y la
habilitación estable dos ciclos de clk (40 ns: /ROMSEL baja 15-30 ns después de subir M2, y en ese hueco una
lectura de ROM en $C101 parece de $4101). Suelta al bajar M2 y apaga `prg_oe`/`ram_oe` mientras conduce. Los
testbenches vigilan esas reglas en todos los ciclos (tb_bus.vh) y hay mutaciones que lo comprueban.

**Hechos de partida (leídos en el kit de Krikzz,
`ref/krikzz-n8-dev/x/mmc5-src` y `fpga-mapper-sample`, sin copiar código):**
- Los pines `cpld_mode1:0` (max1:max0) eligen el modo de bus del CPLD: `11` registros del CPLD
  desbloqueados (OS), `01` juego (registros bloqueados), `00` LED / espía de bus, `10` forzar las
  salidas del bus. Nosotros ya usamos `11` en el OS y `01` en juego, igual que Krikzz.
- Su MMC5 para el N8 original conduce `cpu_dat` desde la FPGA **en modo `01`** (no cambia de modo)
  para las lecturas de sus registros y de la ExRAM. Condiciones: M2 alto, la habilitación también
  registrada en un flanco de `clk` (así no hay picos mientras la dirección cambia), y mientras la
  FPGA conduce, `prg_oe`/`ram_oe` quedan desactivados para que la SRAM no choque.
- El pack de fábrica de este clon trae ese tipo de RBF (005 = MMC5), así que el CPLD del clon deja
  pasar esas lecturas. Falta comprobarlo en la consola antes de dar por buena la parte eléctrica.

**Registros que usa el OS v13 en `$4400`:** 9, 10, 128–130, 132–134, 136, 138–140, más el 131
(escrito de forma indirecta). 138 se **lee** en `$4401`, y la FPGA nunca conduce el bus, así que
138–140 (y 9–10) son del CPLD. Libres conocidos: 135 (GG), 137, 141 en adelante.

**/RD de la PPU no sirve como reloj (hecho de hardware, 2026-11-05):** el primer MMC2/MMC4 cambiaba
sus latches con el flanco de subida de /RD tomando `ppu_a` en ese instante. En el banco era idéntico a
Mesen2, pero en la consola Punch-Out!! y Fire Emblem Gaiden mostraban tiles y letras con el banco
equivocado. Al subir /RD empieza el acceso siguiente (ALE abre el latch de direcciones de la consola), así
que la dirección puede cambiar justo en ese flanco; además la línea llega con rebotes. Solución: todo en
el dominio de `clk` (50 MHz): /RD sincronizado, la dirección se decodifica con /RD bajo y estable (2
muestras) y el cambio se aplica con /RD alto y estable (2 muestras). Mismo criterio que con A12: ninguna
señal de la PPU se usa como reloj directo. (Hecho confirmado leyendo el MMC2 del N8 PRO de Krikzz,
que también filtra /RD con el reloj del sistema; el código es propio.)

**Ruido en PPU A12 (hecho de hardware):** en las placas EverDrive llegan a la FPGA picos cortos en
A12. Los cartuchos MMC3 originales llevan un condensador en esa línea, y el núcleo MIT del N8 PRO
filtra A12 con histéresis por el mismo motivo. Sin filtro, un pico con A12 bajo cuenta como una
scanline más: la barra de estado de SMB3 saltaba en la consola. Cualquier mapper que detecte
flancos de A12 (MMC3, MMC6, Namco 108 con IRQ, etc.) debe filtrarla.

- Mapa de memoria en modo OS (corregido tras revisar el detalle):
  - `$4800–$4FFF`: **ventana de 2 KB a la SRAM PRG del juego**, banco elegido con el reg 128
    (PRG A18..A11 = reg, A10 = CPU A10). Lectura y escritura: así el OS copia la ROM a la SRAM.
  - `$6000–$7FFF`: PRG-RAM (128 KB) en bancos de 8 KB elegidos con el reg 129.
  - `$8000–$FFFF`: si `max2` (bios_off) = 1, 32 KB fijos de la PRG-RAM con A18..A15 = `0011`
    (offset 0x18000: el OS corre desde la RAM con pila). Si = 0, la FPGA no habilita nada
    (el código viene de la BIOS/flash a través del CPLD).
  - Bus PPU: CHR SRAM escribible en `$0000–$1FFF`, dos ventanas de 4 KB: con PPU A12 = 1 banco
    = reg 130, con A12 = 0 banco = reg 130 − 1 (bancos de 4 KB, CHR A18..A12).
  - Escritura de la SRAM PRG permitida **solo en modo OS**; en modo juego su /WE queda en 1.
- El registro de dirección (`$4400`) se escribe en cualquier modo; los datos (`$4401`) solo en modo OS.
- Polaridades en los pines: `ram_ce` es **activo-alto** (probablemente al CE2 de la IS62LV1024,
  así queda deshabilitada sin alimentación). `prg_ce`, `chr_ce`, `*_oe`, `*_we` son activo-bajo.
  `ppu_ciram_ce` activo-bajo (= PPU A13 negado en mapeos normales).
- Krikzz usa el pin **21 (`mclk`, reloj global) como M2** para todos los flancos; el pin 27
  (`cpu_m2`) está asignado pero no se usa en la lógica.
- Reset: `m2_ok` = M2 alto durante las últimas 4 muestras de `clk`; los /CE de PRG y PRG-RAM
  solo se activan con `m2_ok`. Si pasan 128 ciclos de `clk` sin flanco de M2 → se deshabilitan
  todas las memorias. Con CART_CFG.0 = 0 el mapper vuelve al menú tras 128 ciclos; con 1,
  tras 2^25 ciclos (reset corto = reiniciar juego, largo = volver al menú).
- **Reset**: si M2 deja de oscilar (botón RESET de la consola), un contador vuelve
  `map_idx` a 0xFF → regresa al menú. `m2_ok` bloquea los /CE hasta que M2 es estable.
- Los 128 KB de PRG-RAM contienen datos del OS en los 64 KB altos: un mapper **no debe**
  dejar que el juego escriba fuera de su zona de saves.

## Contrato de un mapper (bus interno de 49 bits)
Cada mapper entrega `map_out[48:0]` y el top-level lo enruta a los pines:

| Bits | Señal |
|---|---|
| 19:0 | prg_addr (se usan 18:10 → `prg_map`) |
| 39:20 | chr_addr (se usan 38:30 → `chr_map`) |
| 40 | ciram_a10 |
| 41 | ciram_ce |
| 42 | prg_we (RAM) |
| 43 | chr_we |
| 44 | irq (1 = IRQ activo) |
| 45 | rom_ce |
| 46 | ram_ce |
| 47 | chr_ce |
| 48 | snd (sin usar en el N8 original) |

Entradas comunes: bus CPU, bus PPU, `clk`, `map_cfg[7:0]`, `rst`.
Como hay pocos pines libres, los bancos PRG/CHR están limitados a **512 KB cada uno**.

## Formato .RBF / MAPROUT.BIN (de `mapper-install.txt`)
- .RBF = salida binaria de Quartus sin modificar; tamaño múltiplo de 512 rellenado con 0xFF.
- Nombre en MAYÚSCULAS en `/EDFC/MAPS/` (si no, el OS puede no encontrarlo).
- Un .RBF puede contener varios mappers.
- MAPROUT.BIN: dos tablas de 256 B. Offset 0x000 = mappers normales; 0x100 = mappers
  con save state. Índice = número de mapper; valor = nombre del .RBF en decimal
  (0 → `000.RBF`); 0xFF = no soportado. El registro 0xFF está reservado (siempre 0xFF);
  el 0xFE es para FDS.
- Por USB se puede cargar un .RBF directo a la FPGA sin tocar la SD (hasta el reset).
