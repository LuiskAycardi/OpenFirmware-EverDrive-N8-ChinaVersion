# Fase 4: los mappers de la v1.26 que faltaban (desde el 2026-11-08)

Objetivo: los 177 mappers de la lista oficial v1.26 (`docs/mappers-n8-oficial.md`). Al empezar teníamos 87
(84 de la lista, más 46, 155 y 210). **Faltaban 93**; solo 28 tienen juegos en la colección (71 ROMs, 30 MMC5).

## Método
1. **Hechos** de la descripción pública de NESdev (vía WebFetch: la web bloquea las descargas directas) y, para
   los mappers piratas poco documentados, de la implementación de Mesen2 (`tools/mesen2`, GPL-3), con la misma
   regla que el código de Krikzz: **se lee para entender direcciones y bits, nunca se copia ni se traduce línea a
   línea**. El Verilog es propio. Donde NESdev (descripción del hardware) y Mesen2 no coinciden, se sigue NESdev y
   se anota aquí.
2. **Prueba de ROM sintética** (`tools/n8sim/fuzz/`, ver docs/banco-pruebas.md): una ROM generada que escribe
   valores pseudoaleatorios en los registros y anota, tras cada escritura, qué KB de PRG y de CHR se ve en cada
   ventana y el mirroring. Se ejecuta con el mapper de Mesen2 y con nuestro Verilog y se compara paso a paso. Así se
   prueban también los mappers **sin juegos** en la colección.
3. **Banco con juegos** de la colección (difftest.py, 1500 fotogramas con mando) cuando los hay.
4. Testbenches y mutaciones de siempre para no romper lo anterior.

## Organización en los RBF
- **RBF 102** (antes solo Namco 163): `mapper_latch.v` (mappers de un solo registro, lote 1) y `mapper_mmc3b.v`
  (segunda instancia del MMC3 con `GRUPO = 1`: variantes del lote 2). El parámetro `GRUPO` de `mapper_mmc3.v` hace
  que cada RBF sintetice solo sus variantes: el MMC3 del RBF 100 queda como estaba (comprobado con la ROM sintética
  del mapper 4: idéntico).
- 144 en la instancia del Color Dreams (RBF 100) y 151 en la del VRC1 (RBF 101).
- **Tono de prueba movido del 250 al 247** (el 250 es oficial: Time Diver Avenger). ROM de la SD regenerada.

## Lote 1: mappers de un solo registro (`mapper_latch.v`, RBF 102)
13, 15, 38, 57, 58, 61, 94, 97, 101, 107, 145, 149, 177, 200, 201, 202, 203, 212, 213, 214, 216, 227, 229, 231,
240, 242, 244, 246 (+ 144 y 151 en otras instancias).
- ROM sintética: 23 de 30 idénticos a Mesen2 a la primera. Diferencias aceptadas:
  - **15**: NESdev dice que D7 (PRG A13) solo cuenta en el modo 2 y que en los modos 0 y 3 A14/A13 vienen de la
    CPU; Mesen2 suma o hace XOR con ese bit en los otros modos (bancos desalineados). Se sigue NESdev.
  - **97** (TAM-S1): NESdev: registro solo en $8000-$BFFF, PRG de 5 bits, D7 = mirroring (0 H, 1 V); Mesen2:
    $8000-$FFFF, 4 bits y cuatro modos con D7-D6. **Kaiketsu Yancha Maru sale idéntico** con la versión de NESdev.
  - **242**: NESdev describe modos NROM/UNROM (bits O, S, L) de los multicarts; con ellos Wai Xing Zhan Shi se
    quedaba en verde. La variante Waixing (la de los juegos) solo tiene el NROM-256 (A6-A3) y PRG-RAM: ahora es
    esa, y el juego y la ROM sintética salen idénticos.
  - **213**: Mesen2 lo trata como un 58 reducido (sin 16 KB ni mirroring); NESdev lo da como duplicado del 58.
  - **144** (Death Race): en la placa D0 lo pone la ROM (conflicto de bus); el N8 no ve la ROM durante una escritura.
    Se ignoran las escrituras en $8000 (lo que hace FCEUX). **Death Race sale idéntico.**
  - **13, 200**: solo estado al encender (indefinido en el hardware).
- Banco con juegos (`tools/n8sim/reports/fase4-lote1`, 12 ROMs): **idénticos** Videomation, Crime Busters,
  Senjou no Ookami, Kaiketsu Yancha Maru, Death Race, Sidewinder, Magic Jewelry 2, Decathlon y Wai Xing Zhan Shi
  (tras el cambio del 242); Feng Shen Bang y Taiwan Mahjong solo en el arranque; Sheng Huo Lie Zhuan 6 px.
- 177 (4 ROMs) y 15 (1 ROM) son de 1 MB de PRG: no caben en el N8 (máximo 512 KB).

## Lote 2: variantes del MMC3 (`mapper_mmc3.v` GRUPO 1, RBF 102)
12, 44, 45, 49, 52, 74, 134, 182, 187, 191, 196, 197, 198, 199, 205, 238, 245, 249, 250.
- ROM sintética: 16 de 19 idénticas tras dos correcciones:
  - 49 y 52: el registro exterior solo se carga con la PRG-RAM del MMC3 habilitada ($A001 = 10xxxxxx), como en la
    placa (lo usan sus salidas de RAM).
  - 196: A0 del MMC3 = A1|A2|A3 (|A1 solo por debajo de $C000), sustituyendo a A0.
- Diferencias aceptadas: **198** y **199**: Mesen2 solo atiende sus registros extra en la dirección exacta $8001;
  en un MMC3 se repiten en todas las impares de $8000-$9FFF. **197**: 16 de 500 pasos distintos en un caso de R0
  que Mesen2 no parece aplicar; sin juegos para decidir.
- No implementado: la IRQ "revisión A" del MMC3 que piden 12 (y 114); usan la nuestra (Sharp).
- Banco con juegos: Ying Xiong Yuan Yi Jing Chuan Qi (245) idéntico; Time Diver Avenger (250) un solo fotograma
  con 40 px en las dos últimas líneas (momento de la IRQ o del latch).

## Estado al cerrar los lotes 1 y 2
- **136 mappers** (49 nuevos). Cobertura de la colección: **2903 de 2993 ROMs (97,0 %)**; antes 2889 (96,5 %).
  Muchos de los nuevos no tienen juegos en la colección; 177 y 15 sí, pero son ROMs de 1 MB que el N8 no admite.
- RBF: 100.RBF 2804 LE (61 %), 101.RBF 3055 LE (66 %), **102.RBF 2508 LE (54 %)**, holgura de clk positiva en los
  tres (10,1 / 4,6 / 6,2 ns). md5: 100 051b7553…, 101 d8315abf…, 102 f802e6ca….
- 216/216 mutaciones; los 9 testbenches pasan.
- ~/SD_Pruebas: los tres RBF, MAPROUT con 137 entradas (136 mappers + el tono en el 247), PRUEBAS/11 Fase 4 (14
  juegos) y la ROM del tono regenerada con mapper 247.

## Otras correcciones encontradas con la ROM sintética (mappers antiguos)
- **Namco 108 (206, 76, 88, 95, 154):** el chip solo decodifica A15 y A0, así que los registros se repiten en todo
  $8000-$FFFF (Mesen2 y la referencia de Krikzz coinciden); el nuestro solo los atendía en $8000-$9FFF.
- Revisados y bien (las diferencias son de Mesen2 o del estado al encender): 71 (Krikzz y nosotros: banco solo en
  $C000-$FFFF), 11 (Mesen2 emula el conflicto de bus), 9/10/16/18/33/34/64/69 (bancos sin mapear al encender).

## Lote 3: más mappers sencillos (`mapper_latch.v`, RBF 102)
28, 30, 31, 51, 60, 77, 96, 103, 108, 164, 168, 171, 175, 178, 188, 190, 221.
- ROM sintética: idénticos a Mesen2 30, 31, 60, 103, 108, 164, 171, 175, 178, 190, 221 (y 168 salvo la marca inicial de la
  CHR-RAM). Diferencias aceptadas: **28** solo hasta que el juego escribe el banco exterior (al encender $FF, como dice
  NESdev: «at power on, the last 16 KiB of the ROM is mapped into $C000-$FFFF»; Mesen2 pone 0); **51, 188** estado al
  encender; **77** conflictos de bus; **96** Mesen2 no aplica el banco fijo de $1000 hasta el primer acceso a nametable.
- Errores encontrados y corregidos:
  - **96**: CHR-RAM de 32 KB (la recortábamos a 8 KB; la ROM sintética la probaba con CHR-ROM). Con eso los dos Oeka Kids
    salen idénticos.
  - **168**: el registro de bancos solo está en $8000-$BFFF; antes cada reconocimiento de IRQ ($C000-$FFFF) cambiaba los
    bancos y el Racermate daba «CARTRIDGE MEMORY BAD». Su IRQ contaba un ciclo tarde (ahora el ciclo de la escritura
    cuenta, como en FME-7/VRC y Mesen2).
  - **188** (Karaoke Studio): $6000-$7FFF devuelve los botones del micrófono, activos a nivel bajo; con bus abierto ($60)
    el juego los veía pulsados y avanzaba solo. Ahora: sin pulsar y sin sonido. Sin casete (PRG < 256 KB) los bancos
    externos dan bus abierto (como Mesen2); antes la ROM interna repetida parecía un casete. Los dos casetes, idénticos.
  - **190** (Magic Kid Googoo): PRG-RAM de 8 KB en $6000 y CHR lineal al encender (el logo se dibuja antes de
    escribirla).
- Banco con juegos: **los 10 de la colección idénticos** tras las correcciones: Napoleon Senki (77), San Guo Zhong Lie
  Zhuan (178), Oeka Kids ×2 (96), Karaoke Studio y sus casetes Vol. 1 y 2 (188), Magic Kid Googoo (190) y Racermate
  Challenge II ×2 (168). Salamander (73, lote 4) también idéntico.

## Lote 4: IRQ por ciclos de CPU (`mapper_irqcpu.v`, RBF 102)
40, 42, 50, 73, 106, 142. Un módulo con registros de banco compartidos y un contador de 16 bits.
- Convención de todos los contadores por ciclos: en la bajada de M2 se aplica primero la escritura y luego se cuenta.
  Así la IRQ cae en la misma instrucción que en Mesen2 (comprobado con la ROM sintética, que ahora registra la IRQ).
- ROM sintética: **142** idéntico. Diferencias por seguir a NESdev: **40/50** la línea es el bit 12 de un contador de 13 bits
  (CD4020): baja sola 4096 ciclos después si nadie la reconoce, y $A000 no reinicia la cuenta; **42** $E002 activa con D1
  (Mesen2 exige el valor 2); **73** el modo de 8 bits sí dispara (en Mesen2 nunca); **106** registro de mirroring
  ($800C, Mesen2 no lo tiene) y la IRQ con el contador parado en $FFFF (Mesen2: un ciclo después, al pasar a 0).
- Salamander (73) es el único juego de la colección.

## Lote 5: clones del VRC4 (`mapper_vrc24.v`, RBF 100)
27, 183, 252.
- **27**: A0 = A0, A1 = A1, con modo PRG. Idéntico a Mesen2.
- **183**: VRC4 conectado como el VRC4e (A0 = A2, A1 = A3) y ROM de 8 KB en $6000 elegida con A3-A0 de cualquier
  escritura en $6000-$7FFF (NESdev). Mesen2 sigue la implementación antigua que NESdev da por errónea: no se compara.
- **252**: VRC4 con A0 = A2, A1 = A3; los bancos de CHR 6 y 7 son CHR-RAM (zona libre de la SRAM CHR, como el TQROM);
  PRG-RAM 8 KB. Difiere de Mesen2 en eso y en el mirroring de $9000 (Mesen2 no lo tiene).

## Otras mejoras del banco
- ROM sintética: registro de la IRQ (manejador en el arranque de cada banco: si hubo IRQ en el paso, dirección de la
  instrucción interrumpida y X/Y), cabecera NES 2.0 con tamaños de CHR-RAM/PRG-RAM y tabla de zonas que no se comparan
  por mapper (`IGNORAR`). Con la IRQ, MMC3, FME-7, VRC4, Bandai, Jaleco y Sunsoft-4 salen idénticos también en el
  instante de la IRQ. Diferencias de Mesen2 vistas de paso: 65 (decodifica solo la dirección exacta), 64 y 19 (no aplica
  el cambio de modo hasta la siguiente escritura de banco).
- `hdl/sim/tb_fase4.v`: testbench de la fase 4; las mutaciones pasan a 265, todas detectadas.

## Estado (2026-11-08, tras los lotes 3-5)
- **162 mappers.** RBF: 100.RBF 2926 LE (63 %), 101.RBF 3068 LE (67 %), **102.RBF 4185 LE (91 %)**; holgura de clk
  10,8 / 5,2 / 7,0 ns. Los mappers siguientes no caben en el 102.

## Pendiente (18 mappers)
5 (MMC5, RBF propio), 35, 56, 90, 91, 99, 105, 111, 117, 165, 176, 186, 211, 219, 220, 222, 234, 248.

## Cierre de divergencias del grupo final (2026-11-09)

Revisión contra Mesen2 con ROM sintética (`fuzz.py`, 500 pasos). Hechos (NESdev +
clases Mesen2 leídas solo como referencia, sin copiar código):

- **35** (`hdl/rtl/mapper35.v`, nuevo): mapper propio simple (4×8K PRG $8000-$8003,
  8×1K CHR $9000-$9007, espejo $D001, IRQ MMC3 por A12). Se sacó del JY (que lo
  trataba como el ASIC completo). **Idéntico a Mesen2.** $6000 sin PRG-RAM (la placa
  no la lleva; Mesen2 la añade por el bit de batería → en `IGNORAR`).
- **90 / 211** (`mapper_jy.v`): corregidos (1) el decode de registros a `addr&0xF007`
  (A11 era significativo; $DBF9→D001, $BA02 etc. ahora llegan), (2) NT avanzado
  siempre activo en 211 y nunca en 90, (3) banca PRG a los 4 modos reales de Mesen2
  (defaults 0x3C/0x3E/0x3F, InvertPrgBits en modo 3, ventana alta del modo 1 sin
  desplazar), (4) IRQ del JY: el contador/prescaler avanzan aunque el IRQ esté
  deshabilitado (solo el disparo depende de enable) y el prescaler descendente
  dispara con el valor enmascarado ==1, (5) **banca CHR reescrita fiel a Mesen2**:
  `chrBlockMode` arranca en *false* (no-bloque) —antes se derivaba mal de un
  `outer` reseteado a 0 y daba bloque—, con `chrBlock` y `mirrorChr` de $D003,
  máscara/shift por modo y el latch de 4 KiB fijo en {0,4} (90/211 no tienen el
  latch estilo 209), (6) el latch CHR estilo-209 (ppuread) se quitó: solo aplica
  al mapper 209, que no implementamos.
  - **90: idéntico a Mesen2** en casi todas las semillas. Residual: exactitud de
    ciclo del IRQ de *fuente CpuClock* (contador libre que acumula la deriva del
    conteo de ciclos; aparece con algunas semillas, p. ej. 0x5a). No cerrable sin
    igualar el modelo de ciclo de CPU de Mesen2; los juegos usan sobre todo IRQ por
    scanline (A12).
  - **211: idéntico a Mesen2 ignorando nametables** (`--ignorar nt` → igual). El
    único residual es NT-vía-CHR con página fuera del CHR físico: Mesen2 la lee 0;
    este hardware envuelve `chr_a` a 9 bits (el ancho real del bus de la SRAM CHR).
    Igualarlo exigiría que el JY condujera el bus de datos PPU (como MMC5); los
    juegos nunca fijan esas páginas, así que es un artefacto solo de la ROM sintética.
- **91** (`mapper_scan4.v`): IRQ reimplementado al estilo MMC3 de Mesen2 (latch 7,
  A12 filtrada, cuenta descendente, dispara tras 8 subidas) en vez de "64 subidas
  crudas". **Idéntico a Mesen2.**
- **99** (`mapper_misc4.v`): el N8 sigue correctamente el bit2 de $4016 (selección
  PRG/CHR documentada de VS). Mesen2, en la ROM sintética, mantiene el banco CHR según
  su `ProcessCpuClock` (arbitraje VS, fuera del alcance del módulo): **diferencia del
  lado de Mesen2**, no del N8.
- **111, 117, 165**: ya idénticos a Mesen2 (111/117 sin cambios; 165 pasa salvo un
  borde de fase del latch MMC2 que aparece con algunas semillas).
- **115 / 248** (`mapper_mmc3.v`, GRUPO 2): 248 comparte el camino de 115. Ambos son
  `NO_RAM` (la placa no tiene PRG-RAM); Mesen2 añade WRAM en $6000 por la cabecera
  sintética → los dos van a `IGNORAR` para $6000. **Idénticos a Mesen2.** 248 usa la
  referencia 115 en `REFERENCE_MAPPER`.
- **219 (A9461 / Mesen MMC3_219): reimplementado, idéntico a Mesen2** (todas las
  semillas probadas). Esquema exReg de Mesen: $8000→er0=0,er1=v; $8002→er0=v,er1=0;
  $8001 aplica un banco PRG (er0 0x23-0x26, 4 bits scrambled) y/o CHR (por er1, con er2
  de base), init a los últimos 4 bancos PRG y CHR 0-7; el núcleo MMC3 solo conduce
  espejo/IRQ ($A000+). El RTL anterior (modos A9461 de Codex) no coincidía con Mesen2.
  En `mapper_mmc3.v` (GRUPO 2).
- **176 (Waixing FK23C): módulo propio `hdl/rtl/mapper_fk23c.v`, idéntico a Mesen2.**
  Sustituye al submapper-0 (SFC-12B) que vivía en `mapper_mmc3` (ahí queda anulado con
  `M176 = 0`). Validación: 6 semillas × 600 pasos, CHR-ROM y variante solo-CHR-RAM, todo
  idéntico (12/12), con cobertura de los 8 modos PRG, CHR directo/CNROM, MMC3 extendido
  (12 registros), CHR-RAM en caliente, "RAM en el primer banco CHR", WRAM bancada,
  single-screen y 374 pasos con IRQ. Test directo `tb_fk23c_direct` (101 comprobaciones,
  5/5 mutaciones detectadas). Claves de la implementación:
  - **Registros de config solo en `$5000-$5FFF` con A4=1** (Mesen registra solo
    `$5000-$5FFF` y `$8000-$FFFF`): `$7xxx` y `$4xxx` son RAM, nunca registros. Un primer
    intento los decodificaba y eso producía divergencias falsas de chrBase/prgBase.
  - Modos PRG 5-7 conservan el mapeo anterior: las 4 páginas PRG se latchean y solo siguen
    a los registros con modo 0-4.
  - WRAM de 32 KiB en 4 bancos de PRG-RAM: `$6000` = banco sel, `$4020-$5FFF` = sel+1 con
    la config de WRAM; sin ella `$6000` = banco 0 con protección. `$5xxx` es registro (no
    RAM) mientras los registros FK están activos. `$A001` con bit5=0 solo toma los bits 7:6.
  - CHR-RAM de 256 KiB en la mitad alta de la SRAM CHR (`chr_raw`): sirve para cartuchos
    solo-CHR-RAM y para CHR-ROM ≤256 KiB + CHR-RAM. Las páginas $F8-$FF de esa RAM solapan
    la zona que el OS usa para 4 pantallas/menú.
  - IRQ MMC3 por A12 que se activa 2 ciclos de CPU después de llegar a 0; solo `$E000`
    reconoce (un IRQ en retardo se activa aunque llegue `$E000` en medio).
  - Configuración de prueba: CHR-ROM de 256 KiB y sin batería (con batería Mesen2 usa 8 KiB
    de save RAM para la WRAM bancada y 32 KiB de work RAM en el resto).
  - Fuera de alcance: subtipos con PRG de 1/16 MiB (el N8 tiene 512 KiB).
- Pendiente aparte (previo a estos cambios): 165 en variante *solo CHR-RAM* difiere de
  Mesen2; no es una placa real (165 lleva CHR-ROM) y la prueba normal de 165 coincide.

Resumen fuzz (500 pasos): idénticos **35, 90, 91, 111, 115, 117, 165, 248** (90 salvo
el IRQ CpuClock de algunas semillas); **211** idéntico ignorando nametables (solo el
NT-oob); **99** correcto en el N8 (diferencia del arbitraje VS de Mesen2). Reportes en
`tools/n8sim/reports/` (retomar-final2, jy-chr2, jy-211-nont, jyfin-*).

## MMC5 (mapper 5, RBF 103) — en curso
Reimplementación propia (clean room), empezando por el mapper de más valor de los 18 pendientes. Primera versión
en `hdl/rtl/mapper_mmc5.v` (núcleo integrado en RBF 103; ver validación dirigida al final):
- Hecho: registros $5100-$5107, $5113-$5117 (banca PRG, 4 modos), $5120-$512B + $5130 (banca CHR, juegos
  sprite/fondo y tamaños 8/4/2/1 KB), protección de PRG-RAM ($5102/$5103), multiplicador ($5205/$5206, lectura),
  mapeo de nametables a CIRAM ($5105), IRQ por scanline ($5203/$5204) con detección por strobes de nametable.
- Pendiente (exige **conducir el bus de datos de la PPU** y alojar la ExRAM de 1 KB en la SRAM CHR — amplía la
  interfaz del mapper y n8_top): modo fill, ExRAM como nametable, atributos extendidos, split vertical
  ($5200-$5202) y el audio ($5000-$5015, dos pulsos + PCM). Los puertos `ppu_dout`/`ppu_doe`/`snd` ya están.
- Falta: wiring en n8_top (RBF 103), ROM sintética + comparación con Mesen2, testbench, mutaciones, Quartus.

Nota de alcance: completar MMC5 (verificación + ExRAM/fill/split/audio + integración) y los otros 17 pendientes
(35, 56, 90, 91, 99, 105, 111, 117, 165, 176, 186, 211, 219, 220, 222, 234, 248) es un trabajo de varias
iteraciones. Se hace por lotes, como las fases anteriores.


## MMC5: validación dirigida del núcleo (2026-11-09, Codex)

El generador de ROM sintética `tools/n8sim/fuzz/romgen.py` selecciona para mapper 5 un perfil que recorre
$5100/$5101, $5113-$5117, $5120-$5127 y $5130, con datos pseudoaleatorios reproducibles. Durante esta prueba
los bancos PRG $8000+ se fuerzan a ROM: la conmutación RAM/ROM y las escrituras de RAM no están cubiertas
por esta comparación. Se comparan las lecturas CPU/PPU sin renderizado; nametables e IRQ se excluyen explícitamente.

- `reports/mmc5-core-review`: 120 pasos del generador genérico antiguo; solo tocó $5202 y $5203. No valida bancos.
- `reports/mmc5-directed-v1`: también usa el generador genérico antiguo (la primera edición falló por ruta).
  No debe contarse como evidencia dirigida pese al nombre del directorio.
- `reports/mmc5-directed-v2`: 512 pasos dirigidos idénticos a Mesen2.
- `reports/mmc5-directed-seed1257`: 1.024 pasos dirigidos, semilla 0x1257, idénticos a Mesen2.
  La primera tanda ejercitó los cuatro modos PRG y los cuatro tamaños CHR.
- `reports/mmc5-simtop-regression`: mapper 0, 64 pasos idénticos; se corrigió `simtop.py` para declarar también
  las salidas DO/DOE/SND de una instancia N8_MAPPER_M5 eliminada al reducir el modelo de otro mapper.

`hdl/sim/tb_mmc5.v` amplía las comprobaciones directas: modo PRG 1, las ocho ventanas PPU en los cuatro tamaños
CHR, todas las 16 combinaciones de protección y las 65.536 multiplicaciones de 8 bits, con ambos bytes y
habilitación de lectura. El test termina con código de error si hay fallos. Pasó el testbench ampliado.
`hdl/tools/mutate_mmc5.py` introduce errores de producto, clave RAM, alineamiento PRG y selección de mitades CHR
para verificar que esas pruebas los detectan.

Reproducción desde tools/n8sim:

```
python3 -I fuzz/fuzz.py 5 --pasos 1024 --semilla 0x1257 --jobs 2 --slot-base 182 --ignorar nt,irq --out reports/mmc5-directed-recheck
```

Desde la raíz:

```
make -C hdl out/tb_mmc5.vvp
vvp -n hdl/out/tb_mmc5.vvp
python3 -B hdl/tools/mutate_mmc5.py
```

El MMC5 completo sigue pendiente: ExRAM, fill, atributos extendidos, sprites 8x16 con selección A/B,
split vertical, IRQ exacta, audio y validación de Quartus/hardware. Estas pruebas no certifican esos recursos.


## Ampliación MMC5 implementada (2026-11-09, Codex)

El núcleo ya incluye ExRAM interna, fill, atributos extendidos, CHR A/B, IRQ
y audio de pulsos/PCM, con bus PPU integrado en hardware y en el banco API v4.
El split es parcial por el cableado de los bits bajos de la SRAM CHR.
El estado vigente, pruebas y límites se detallan en `docs/mmc5-validacion.md`;
las listas anteriores de funciones futuras corresponden a etapas históricas.

## EEPROM serie del Bandai (16) y mapper 159 (2026-11-10)

Pista sacada de la revisión del core NES de MiSTer (`docs/mister-nes-revision.md`); implementación propia.
- `hdl/rtl/eeprom_24c0x.v`: EEPROM I2C con los dos protocolos, 24C02 (256 bytes, dirección de chip,
  MSB primero, escritura y lectura secuenciales) y 24C01 (128 bytes, 7 bits de dirección + R/W, LSB
  primero, un byte por operación). Memoria en un M4K, a cero al encender. Conducta paso a paso alineada con
  Mesen2 (salida a 0 hasta el primer START/STOP, sin vuelta de página en la 24C02).
- `mapper_bandaifcg.v`: `$xxxD` (D5 = SCL, D6 = SDA) alimenta la EEPROM y `$6000-$7FFF` devuelve D4 =
  EEPROM y D3 = 0 (macro `N8_MAPPER_D`). **El 159 se añade** al mismo módulo (24C01; registros solo en
  `$8000-$FFFF`). Total: 181 mappers.
- **Semántica por rango**: el OS no da el submapper, pero cada placa decodifica un solo rango. En
  `$6000-$7FFF` (FCG-1/2) `B/C` escriben el contador del IRQ y `A` no recarga; en `$8000-$FFFF` (LZ93D50)
  `B/C` son un latch que `A` copia y `D` es la EEPROM.
- Persistencia: el contenido dura la sesión de juego. Se pierde al apagar y también al lanzar otro juego,
  porque el OS recarga el RBF.

Validación:
- `tb_eeprom_direct` (476 comprobaciones, en `make sim`): escrituras y lecturas aleatorias y secuenciales,
  lectura de la dirección actual, chip no seleccionado, la 24C01 y sus límites, rangos de registros e IRQ
  FCG/LZ. Mutaciones detectadas: 6 de 7; la que no se detecta es equivalente, porque el reset fuerza la
  salida a 0.
- Fuzz frente a Mesen2: el 16 se prueba como dos placas reales (NES 2.0: `16_lz` = submapper 5 + EEPROM de
  256 bytes con escrituras en `$8000+`, `16_fcg` = submapper 4 con escrituras en `$6000-$7FFF`; opciones
  nuevas `submapper/nvram_bytes/wr_only` de `romgen.build`). Resultado: 8/8 idénticos con 4 semillas, con
  más de 500 pasos con IRQ en cada placa. El 159, 8/8.
- **Juegos reales (22 ROMs del 16 y el 159, 900 fotogramas, `difftest`):**
  - Sin EEPROM coincidían 9 de 22; con EEPROM coinciden **16 de 22**. Por ejemplo, Magical Taruruuto-kun 2
    se colgaba con la pantalla verde y ahora es idéntico.
  - 3 tienen diferencias menores (2–8 píxeles), las mismas que antes.
  - En los 3 que divergen el fallo es de la referencia: Mesen2 se congela en Famicom Jump y en Nishimura
    Kyoutarou Mystery (su base de datos los marca como FCG sin EEPROM) y pinta basura en SD Gundam Gaiden
    (original), mientras que el N8 muestra los juegos correctamente.
- RBF 100: 3316 LE (72 %), 2816 bits de M4K, timing cerrado.

## Mappers 192 y 153 (2026-11-10)

Segunda pista de la revisión de MiSTer. Implementación propia; 183 mappers en total.
- **192 (Waixing, MMC3 + 4 KiB de CHR-RAM):** en `mapper_mmc3.v`, GRUPO 2 (`mapper_mmc3c`, RBF 105). Los
  bancos CHR de 1 KiB `$08-$0B` van a la CHR-RAM, en la misma región aparte (`chr_raw`, `0x7C000`) que usan
  el 74 y el 191.
- **153 (Bandai LZ93D50 con SRAM, Famicom Jump II):** en `mapper_bandaifcg.v` (RBF 100).
  - 8 KiB de SRAM en `$6000`, activa al encender y controlada después por `$800D` D5. Como es PRG-RAM
    normal, el OS la guarda en la SD.
  - Bit de PRG exterior (512 KiB): el OR del bit 0 de los 8 registros de CHR.
  - Registros solo en `$8000+`, CHR-RAM sin banca y sin EEPROM.
  - La CHR-RAM de esta familia (16/153/159) ahora es lineal, igual que en Mesen2.
- Validación:
  - Fuzz frente a Mesen2: 8/8 idénticos con 4 semillas. En el 153 se ejercitaron el bit exterior y la SRAM
    activa e inactiva; en el 192, 341 lecturas de ventana cayeron en la CHR-RAM.
  - Tests directos: `tb_mmc3c_direct` (357, con el 192) y `tb_eeprom_direct` (488, con el 153).
  - Juegos reales:
    - Ying Lie Qun Xia Zhuan y You Ling Xing Dong (192): idénticos durante 1500 fotogramas, con la
      pantalla de nombre en caracteres chinos dibujada en la CHR-RAM.
    - Famicom Jump II (153): idéntico durante 1500 fotogramas y ya dentro del juego.
- **Famicom Jump II se cuelga si su SRAM empieza a cero.** Esto le pasa también en Mesen2 y no es cosa
  del mapper: con la SRAM a `$FF` o aleatoria arranca bien. Para probarlo, el banco tiene ahora
  `difftest.py --prgram-fill 0xFF`, que rellena igual la PRG-RAM del N8 (`N8_PRGRAM_FILL` en
  `N8FpgaMapper.cpp`) y la `.sav` de la referencia. **En la consola:** si el OS crea la `.SRM` llena de
  ceros, el juego se colgará con cualquier RBF. Habría que rellenarla con `$FF` antes de la primera
  partida.
- RBF 100: 3349 LE (73 %). RBF 105: 1690 LE (37 %). Timing cerrado en los dos.

## Sonido VRC7 (mapper 85, FM) — RBF 106 (Claude, 2026-11-10)

- **Qué es:** el VRC7 lleva un derivado del YM2413 con 6 canales FM de 2 operadores y 15 instrumentos
  fijos + 1 definible. Solo lo usa Lagrange Point (Japón). Hasta ahora el 85 tenía mapeo e IRQ pero no
  sonido.
- **Diseño propio** (`hdl/rtl/vrc7_fm.v`, ~400 líneas): un motor secuencial que procesa los 12 operadores
  uno tras otro con una copia de trabajo del operador (cargar → aplicar cambios pendientes → envolvente →
  fase → guardar) y una ruta de salida con las dos ROM (seno logarítmico de cuarto de onda y exponencial)
  en M4K. Una muestra por cada 36 ciclos de M2 (49 716 Hz, como el chip real a 3,58 MHz / 72) y ~130
  ciclos de 50 MHz por muestra. Las escrituras de registro entran en una cola de 8 y se aplican entre
  muestras.
- **Tablas** (`hdl/rtl/vrc7_tables.v`) generadas por `tools/fm/gen_vrc7_tables.py` a partir de sus
  fórmulas públicas (seno y exponencial), los instrumentos del VRC7 medidos por Nuke.YKT, el patrón del
  LFO de AM y la escala por tecla. El generador comprueba cada tabla contra el oráculo antes de escribir.
- **Oráculo:** emu2413 (MIT, el que trae Mesen2), configurado igual que `Vrc7Audio` de Mesen2, en
  `tools/fm/fmref.cpp` (solo herramienta de prueba; nada de emu2413 entra en el diseño).
- **Mapper** (`mapper_vrc7.v`): `$9010` (A4=1, A5=0) elige registro y `$9030` (A5=1) escribe; con `$E000`
  D6 = 1 se ignoran las escrituras y la salida queda en silencio (como Mesen2). Paso de dominio M2 → clk
  con conmutadores sincronizados. Nivel para `audio_dac.v`: 512 + muestra / 16, saturado a 0-1023.
- **RBF 106 solo para el 85** (`N8_MAPPER_S`, `snd_085`). El 85 sale del RBF 101. Al desplegar: copiar
  `106.RBF` a `EDFC/MAPS` y `maprout.py set MAPROUT.BIN 85 106`.
- Validación:
  - **Muestra a muestra:** `tools/fm/fmcheck.py` genera guiones aleatorios de escrituras (instrumentos,
    volumen, fnum/bloque, teclas, sustain, instrumento propio, registro de prueba, espejos y registros
    ignorados) y compara RTL con emu2413: **20/20 semillas idénticas, 800 000 muestras**.
  - `tb_vrc7_golden` en `make sim`: 27 301 muestras guardadas del oráculo (5 semillas + barrido de los 16
    multiplicadores), sin necesitar emu2413. Detecta 10/10 mutaciones del motor (realimentación, ML,
    patrones de envolvente, umbral DAMP, saturación de atenuación, LFO de AM, vibrato, tasa de sustain,
    forma de onda, reinicio de fase).
  - **Lagrange Point** frente a Mesen2 (registro de nivel `N8_AUDIO=1`, Mesen2 parcheado en
    `Vrc7Audio.h` con la misma escala): **equivalente por fotograma, 0 de 3599 fotogramas distintos**, ~1,96
    millones de cambios de nivel en cada lado. Ciclo a ciclo difieren en un 14 % de los ciclos porque la
    muestra del N8 cae en otra fase del divisor de 36 (Mesen2 usa un divisor de coma flotante).
    La música empieza pasada la pantalla de nombre; en el título el juego solo inicializa el chip.
- RBF 106: 3132 LE (68 %), 5632 bits de M4K, holgura de 0,50 ns a 50 MHz. RBF 101 sin el 85: 2834 LE (62 %), holgura 4,8 ns.

## Mapper 157 (Bandai Datach Joint ROM System) — RBF 100 (Claude, 2026-11-10)

- **Qué es:** la base Datach (LZ93D50 con lector de códigos de barras y una EEPROM 24C02 compartida por
  todos los juegos) y sus cartuchos de 256 KiB con 8 KiB de CHR-RAM. 7 juegos licenciados en No-Intro:
  eran los únicos licenciados del romset sin mapper en el N8.
- **Diseño** (en `mapper_bandaifcg.v`, reutiliza el LZ93D50 y `eeprom_24c0x.v`):
  - registros solo en `$8000-$FFFF`, como el 159; PRG de 16 KiB + último fijo; CHR-RAM sin banca;
  - 24C02 de la base en `$800D` (D5 = SCL, D6 = SDA), igual que el 16;
  - **24C01 del cartucho** (solo Battle Rush): SCL = bit 3 de las escrituras en `$8000-$8003`, SDA = bit 6
    de `$800D`. Se activa con el bit de pila de la cabecera (`cfg[1]`): Battle Rush es el único Datach con
    pila y 128 bytes de PRG-NVRAM, que es lo que usa Mesen2 para decidir si existe;
  - lectura en `$6000-$7FFF`: D4 = AND de las dos EEPROM, D3 = 0 (el N8 no tiene lector de códigos;
    los juegos se juegan sin tarjetas). Como en Mesen2, la 24C01 da 0 hasta su primer START/STOP.
- Validación:
  - `tb_eeprom_direct`: 728 comprobaciones (antes 488), 6/6 mutaciones del 157 detectadas (AND, bit de
    SCL, rango $8000-$8003, activación por pila, rango de registros, bit de SDA).
  - Fuzz frente a Mesen2: 8/8 idénticos (4 semillas × placa con 24C01 `_br` y sin ella `_base`).
    `fuzz.py` admite ahora `battery` en `BOARD_VARIANTS`.
  - Los 7 juegos, 1500 fotogramas con pulsaciones: **6 idénticos** (Battle Rush incluido) y J.League
    Super Top Players con una diferencia menor: el último tile (8 píxeles) de la línea 187 en 5
    fotogramas de una transición; después vuelve a ser idéntico. Es un cambio de paleta a mitad de
    pantalla que cae un ciclo de CPU a un lado u otro del borde del tile (IRQ por ciclos de CPU).
- RBF 100: 3501 LE (76 %), holgura 9,3 ns.
- Herramienta nueva: `hdl/tools/romset_mappers.py CARPETA` cuenta las ROMs por mapper y las cruza con
  `n8_top.v` (separa las de más de 512 KiB y las de mapper > 255).

## Lote pirata: 59, 83, 114, 116, 121, 194, 195, 209, 215, 253 — RBF 105 (Claude, 2026-11-10)

Los diez mappers con más ROMs del romset No-Intro que faltaban (todas piratas o aftermarket; ver
`hdl/tools/romset_mappers.py`). Datos de registro de NESdev y, para el detalle fino, de Mesen2 (leído
como referencia de hechos, sin copiar código).

- **209** (`mapper_jy.v`): el 90 con un latch de CHR tipo MMC2 en el modo de 4 KiB: lecturas de la PPU
  en `$0FD8`/`$0FE8` (y `$1FD8`/`$1FE8`) eligen el registro 0/2 (4/6); al encender {0, 4}.
- **194 / 195** (grupo 2 de `mapper_mmc3.v`): MMC3 de Waixing cuyos bancos de 1 KiB `$00-$01` (2 KiB) o
  `$00-$03` (4 KiB) son CHR-RAM, en la misma zona fuera de la máscara que el 192.
- **114** (grupo 2): registro de PRG en `$5000-$7FFF` (D7 = modo 16 KiB) y puertos del MMC3 cruzados
  (`$8001` = mirroring, `$A000` = selección con D2-D0 barajados, `$A001` = latch de IRQ, `$C000` = dato
  una vez por selección); IRQ del MMC3A (no dispara al recargar con 0 salvo recarga de `$C001`).
- **121** (grupo 2): protección en `$5000-$5FFF` (tabla de escritura y lectura), bit exterior por `$5180`
  y una tabla de comandos en `$8003`/`$8001` que carga tres bancos de PRG extra. El «hack» de Mesen2 para
  ROMs con PRG = CHR solo cambia el bit de CHR por encima de 256 KiB, que esos juegos no tienen.
- **215** (grupo 2, UNL-8237): `$5000`/`$5001` bancos exteriores de PRG/CHR y modo NROM, `$5007` elige la
  tabla que baraja el puerto y el valor de selección del MMC3.
- **59, 83, 253** (`mapper_pirate.v`, nuevo):
  - 59 (multicarts D1038): la dirección escrita es el registro; con A8 las lecturas de ROM devuelven los
    DIP (0).
  - 83 (Cony/Yoko): decodificación por dirección completa como el oráculo; PRG 8/16 KiB, CHR 1/2 KiB,
    4 bytes de RAM en `$5100`, IRQ por ciclos de CPU que se desactiva al llegar a 0.
  - 253 (Dragon Ball de Waixing): registros de CHR por nibbles, bancos 4/5 de **CHR-RAM de 2 KiB**,
    IRQ cada 114 ciclos de CPU. Como su CHR-ROM ocupa los 512 KiB enteros (y dos juegos usan los
    últimos bancos), la CHR-RAM es un **M4K de la FPGA que conduce el bus de datos de la PPU**, como la
    ExRAM del MMC5 (nueva macro `N8_MAPPER_XDP` y selector de conducción PPU por mapper en `n8_top.v`).
- **116** (`mapper116.v`, nuevo): placa con clones de VRC2, MMC3 y MMC1; `$4100` elige el chip activo
  (y con A0 reinicia el MMC1), cada uno conserva sus registros; IRQ del MMC3 solo con el MMC3 activo.
- Validación:
  - Fuzz frente a Mesen2: 194, 195, 114, 121, 215 idénticos (2 semillas); 59, 83, 253 idénticos (4
    semillas, tras corregir el rango `$8310-$8317` del 83); 116 idéntico (3 semillas). 209: diverge en las
    mismas semillas y pasos que el 90 (el residual ya conocido de la IRQ por ciclos del J.Y.); sin comparar
    nametables, nada más (las páginas de nametable más allá de la CHR son el residual del 211).
  - `tb_pirate_direct` (nuevo, 45 comprobaciones): CHR-RAM interna y forzado de ROM del 253, mirroring de
    arranque del 253, IRQ del 253 y del 83, RAM y DIP del 83, 59, cambio de chip del 116 y latch del 209;
    10/10 mutaciones detectadas.
  - **Juegos reales: los 68 del romset que caben (≤ 512 KiB), 1500 fotogramas con pulsaciones.**
    51 idénticos, 16 con diferencias menores y 1 distinto:
    - menores: de 1 a 12 píxeles (104 en Garou Densetsu Special) en una o dos líneas de un corte de
      pantalla por IRQ, en fotogramas sueltos: la misma temporización de un ciclo que en otros MMC3. Power
      Rangers III (209): 8 píxeles en la línea 0 durante la intro.
    - **Kart Fighter (116), distinto:** Mesen2 dispara una IRQ al volver al modo MMC3 porque congela su
      detector de A12 fuera de ese modo y además reacciona a un aviso de dirección de la PPU que no cambia
      la dirección (línea 240). Nada de eso es visible en el bus del cartucho; aquí esa IRQ no salta y el
      juego sigue otro camino desde el título. Hay que verlo en la consola.
  - Correcciones que salieron de los juegos: el 253 arranca con el mirroring de la cabecera (Mesen2 no lo
    cambia hasta `$9400`); su CHR-RAM se escribe una vez por pulso de /WR; el 116 deja leer la PRG-RAM en
    `$6000-$7FFF` (nunca escrita: allí todo son registros), como el oráculo.
- Banco de pruebas: `simtop.py`/`difftest.py` conocen la macro `N8_MAPPER_XDP`. El puente
  (`N8FpgaMapper.cpp`) deja correr `clk` antes de leer la PPU con cualquier mapper con RAM interna en el bus
  de la PPU (antes solo el MMC5) y, para el 253, da 3 flancos de `clk` extra en cada acceso a la PPU (sin
  mover el tiempo del banco): con `RdLimit()` recortando el avance, la RAM síncrona devolvía el dato de la
  dirección anterior y el texto chino del 253 salía corrupto. En la consola `clk` corre siempre.
- RBF 105: 3075 LE (67 %), 16 Kbit de M4K más, holgura 10,9 ns.
- **Total: 194 mappers.** Romset No-Intro: 170 de sus 275 mappers y 5998 ROMs que caben; faltan 185 ROMs
  que cabrían (105 mappers, casi todos con 1-3 ROMs piratas) además de las de más de 512 KiB y mapper > 255.

