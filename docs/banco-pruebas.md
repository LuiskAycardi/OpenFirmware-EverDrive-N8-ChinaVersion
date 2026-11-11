# Banco de pruebas: nuestro Verilog dentro de Mesen2

Objetivo: probar los mappers con juegos reales **sin la consola**, de forma automática, y dejar
la consola solo para lo que ningún emulador ve (ruido eléctrico, tiempos reales, CPLD).

## Cómo funciona
```
Juego .nes ─► Mesen2 (CPU/PPU/APU precisas, sin ventana: --testrunner + Lua)
                 │ cada ciclo de CPU y cada acceso de la PPU
                 ▼
      N8FpgaMapper (puente) ─► libn8model.so = hdl/rtl/n8_top.v compilado con Verilator
                 │  M2, /ROMSEL, R/W, A0-A14, D0-D7, PPU A0-A13, /RD, /WR, clk, /IRQ
                 ▼
      memorias de la placa: SRAM PRG 512 KB, SRAM CHR 512 KB, PRG-RAM 128 KB, CIRAM 2 KB
```
- **Es el mismo Verilog que va a la FPGA** (top, interfaz del OS, máscaras, 4 pantallas, IRQ).
- Antes de arrancar, el puente configura la FPGA **como el OS v13**: registros 132 (PRG−1),
  133 (CHR−1 o `$FF` con CHR-RAM), 134 (`cabecera[6] & $1B`), 136 (0) y 131 (mapper), con
  ciclos de bus reales por `$4400/$4401`.
- Tiempo: relojes maestros NTSC (12 por ciclo de CPU). M2 alto 6 relojes por ciclo. La PPU se
  adelanta dentro de cada acceso al cartucho, para que A12 y M2 lleguen en el orden de la consola.
  `clk` es configurable (`N8_CLK_MHZ`). Desde el 2026-11-05 el valor por defecto es **50 MHz**, el del
  oscilador real (SCTF 50,000 MHz). Las tandas anteriores se hicieron a 25 MHz, que es el doble de
  rápido y dio los mismos resultados salvo en el tiempo exacto de la IRQ del MMC3 (blargg 4).
- **Prueba diferencial:** cada ROM se ejecuta dos veces con los mismos botones (secuencia
  determinista por semilla): con el mapper de Mesen2 (referencia) y con el nuestro. Se compara el
  hash de cada fotograma. Si divergen, el informe muestra el primer fotograma distinto: Mesen, N8
  y las diferencias en rojo.
- Configuración aislada (modo portable en `tools/n8sim/run` y `homes/wN`): base de datos de juegos
  desactivada (se usa la cabecera cruda, como el OS), RAM a ceros y sin audio. Antes de cada
  ejecución se borran `Saves/` y `SaveStates/`.

## Uso
```bash
cd tools/n8sim
make model                       # tras cambiar hdl/rtl (8 s)
make mesen                       # solo si cambia el puente o Mesen2 (minutos)
python3 -I difftest.py ROM1.nes ROM2.nes ...
python3 -I difftest.py --collection ~/Documents/SD_N8 --mappers 0,1,2,3,4,7 --per-mapper 10
#   --frames 1200 (20 s)  --clk 50  --jobs 7  --seed 7  --model otra_lib.so  --slot-base N
```
Informe: `tools/n8sim/reports/<fecha>/index.html` (y `results.json`).

**Mutaciones a nivel de juego:** se compila una copia del RTL con un error con
`make model OBJ=obj_x LIB=libn8model_x.so RTL="..."` y se pasa con `--model`.

## ⚠️ Fallo del propio banco corregido el 2026-11-05: no había mando conectado
`run/settings.json` solo desactivaba la base de datos, la RAM aleatoria y el audio. Sin `Nes.Port1.Type`,
Mesen2 deja el puerto 1 en `None` y **`emu.setInput()` no llega al juego**. Todas las tandas anteriores
(fases 1 a 3d, regresiones y sonido) se hicieron **sin botones**: compararon el arranque, los títulos y
las demos automáticas, pero no el juego en sí. Por eso el banco no vio fallos que el usuario encontró
en la consola dentro del juego. Ahora `run/settings.json` lleva `"Port1": {"Type": "NesController"}`
(comprobado: con Start en el fotograma 120, Super Mario Bros. está en el 1-1 en el 300 y Quattro Adventure
entra en Linus Spacehead). **Hay que repetir las tandas de regresión con mando.**

Otras mejoras del mismo día:
- `--script "ini-fin:boton+boton;..."` (variable `N8_SCRIPT`): botones fijos en lugar de los aleatorios,
  para llegar a una escena concreta. `--shots 300,600,...`: capturas extra en ambas ejecuciones.
- /RD de la PPU dura ahora un punto (4 relojes maestros) en vez de subir en el mismo instante: el puente
  lo sube en `Advance()`. Hace falta para la lógica que filtra /RD con `clk` (latches del MMC2/MMC4).
- ~~Límite conocido del banco~~ **(era un fallo del puente, corregido el 2026-11-06):** con el latch nuevo del
  MMC2/MMC4, Punch-Out y Fire Emblem divergían de Mesen2 (filas de tiles con el banco anterior). Causa: Mesen2 pone la
  dirección y lee en el mismo instante; `NotifyVramAddressChange` adelanta clk hasta 3 relojes maestros con la dirección
  puesta (fase ALE) y después `MapperReadVram` bajaba /RD con la subida programada a `PpuTime() + 4`, así que /RD
  quedaba bajo solo ~1 reloj maestro (2-3 ciclos de clk) y el latch, que necesita 5, unas veces capturaba y otras no.
  Ahora /RD dura 4 relojes maestros desde que baja (`max(PpuTime(), _now) + 4`). Con eso **Punch-Out sale idéntico a
  Mesen2 en 1500 fotogramas con el latch nuevo**. Solo afecta a los mappers que usan /RD (MMC2/MMC4).
  Reglas extra de /RD para el MMC2/MMC4 (2026-11-06, `N8_RD_RULES`, solo con los mappers 9 y 10, los únicos cuyo
  RTL mira /RD, para no mover el tiempo ya validado de los demás): 1 = sin el adelanto ALE de 3 relojes maestros
  tras el cambio de dirección (ese adelanto solo hace falta para la IRQ por A12), 2 = completar la fase baja de la
  lectura en curso antes del acceso siguiente (`FinishRead`), 4 = /RD alto al menos 2,4 relojes maestros entre
  lecturas. Ninguna pasa de la bajada de M2 de un acceso de la CPU en curso ni de cycleT + 11,5 (`RdLimit`;
  pasarla soltaba /ROMSEL antes de la lectura de la PRG y la CPU leía bus abierto).
  **Por defecto 4**: los dos Punch-Out idénticos a Mesen2; Fire Emblem Gaiden y Ankoku Ryuu con diferencias
  pequeñas (≤ 181 píxeles en 30 de 1500 fotogramas y ≤ 24 en 102). Con 7, los Fire Emblem idénticos y el retrato
  de Mike Tyson revuelto. El latch antiguo (instantáneo en el flanco, no depende de la duración de /RD) sale
  idéntico con cualquier regla, así que lo que queda es el banco: Mesen2 entrega a veces varias lecturas de la
  PPU con su tiempo por detrás del tiempo del modelo y el puente no puede dar a cada una su /RD real. Con
  `N8_TRACE_RD=1` se vieron disparos con /RD bajo 1-2 ciclos de clk (en la consola son ~9). El tiempo real lo
  cubre la prueba de tb_fase3b y lo decide la consola.

## Aceleración del banco (2026-11-05)
El coste está casi todo en el modelo de Verilator: cada flanco de clk recalcula todo lo que lleva el RBF, aunque
el juego use un solo mapper (~90-140 ns por evaluación, ~70 evaluaciones por ciclo de CPU).
- `--instancias` (`simtop.py`): un modelo por instancia de mapper. Copia `n8_top.v` cambiando las demás
  instancias por buses a cero; el selector, las máscaras, el OS, las 4 pantallas y el resto del top quedan
  igual, y la instancia del juego es el mismo Verilog. Los modelos se guardan en `models/<hash del RTL>/`.
  Super Mario Bros.: de 107 s a 64 s por 300 fotogramas, idéntico.
- El modelo se compila con clang en una sola unidad de compilación (Makefile): ~20-25 % más rápido.
- `--clk-auto`: 50 MHz solo en los mappers que usan clk (filtro de A12, latches del MMC2, motores de sonido) o que
  conducen el bus de la CPU (la habilitación espera 2 ciclos de clk); 25 MHz en el resto, donde clk solo mueve la
  vigilancia de M2 del OS y el DAC. La lista sale del propio RTL (`posedge clk`, `a12_filter`, macros _D/_XD/_DS).
- `--rom-list ARCHIVO` (una ruta por línea) y `--rtl CARPETA` (probar una copia congelada del RTL).
- La CPU es de 4 núcleos con 8 hilos: con 7 ejecuciones a la vez cada una va a ~0,5-0,6 de su velocidad sola.
- Varias tandas a la vez (o varias sesiones): cada una con su `--slot-base` (carpetas `homes/wN` distintas). Las
  `homes/w0`… las usa la tanda que se lanza sin esa opción. Los modelos de `models/<hash>/` se comparten.
- Para esperar a una tanda: `pgrep -f "[d]ifftest"` (con corchetes; sin ellos `pgrep -f` se encuentra a sí mismo
  dentro del bucle de espera y no termina nunca).

## ROM sintética: mappers sin juegos (`tools/n8sim/fuzz/`, desde el 2026-11-08)
Para comparar un mapper con Mesen2 sin depender de que haya juegos:
- `romgen.py` genera una ROM iNES 1.0 (como la ve el OS v13): cada KB de PRG y de CHR lleva su número en los bytes
  0-1, el resto de la PRG va a $FF (neutro ante conflictos de bus) y cada banco de 8 KB lleva el programa de prueba
  y el arranque (con los vectores), así que arranca sea cual sea el banco inicial. El programa se copia a la RAM y,
  con la PPU apagada y sin interrupciones, hace N escrituras pseudoaleatorias (LFSR de 16 bits) en $4100-$FFFF, con
  preferencia por las direcciones típicas de registros (bytes bajos $00-$03 y $F0-$FF) y sin escribir encima de sí
  mismo. Tras cada una lee el KB de PRG visible en $6000-$FC00, el de CHR en las 8 ventanas (por $2006/$2007) y el
  mirroring (4 escrituras y lecturas en las nametables), y lo deja en la RAM. Con CHR-RAM marca primero las ventanas.
- `fuzz.lua` registra cada paso (escritura y muestra de 100 bytes); `fuzz.py` ejecuta Mesen2 y nuestro modelo (por
  instancia, `--clk-auto`) y dice el primer paso distinto y qué ventana difiere. Tamaños reales de cada placa en
  `SIZES` (con más, Mesen2 ve otra placa). No compara lo que Mesen2 deja sin mapear al encender (bus abierto: PRG
  `$8080`, CHR `00 01`). `--ignorar 6000,chr,nt` quita zonas por decisiones conocidas (p. ej. PRG-RAM siempre activa).
- Uso: `python3 -I fuzz/fuzz.py 13 15 38 --pasos 500 --jobs 6 --ignorar 6000` → `reports/fuzz-*/resumen.txt`.
- Lo que no ve: la IRQ (las interrupciones están desactivadas), el sonido y la temporización. Mesen2 no es el
  hardware: cada diferencia se revisa (NESdev, Krikzz) antes de dar la razón a uno u otro (docs/fase4-mappers.md).

## Clasificación de resultados
- **idéntico:** todos los fotogramas coinciden.
- **diferencias menores:** al divergir se capturan hasta 5 fotogramas distintos y ninguno pasa
  de 32 píxeles. Puede ser una diferencia de tiempo fina y legítima, como el retardo del filtro
  de A12 frente a la IRQ instantánea de Mesen. Aun así conviene mirarla, porque un fallo del banco
  también puede dar pocos píxeles. Ejemplo: Dragon Warrior IV parecía "menor" (oleaje) y era el
  punto de PPU de más (ver abajo).
- **arranque:** solo difieren los primeros 10 fotogramas, antes de que el juego configure el
  mapper. Al encender, el estado de los registros es indefinido en el hardware: Mesen2 deja la
  CHR sin mapear (bus abierto) y nosotros arrancamos en el banco 0. Casos: Taito 33, Sunsoft 184.
- **Momento del latch (causa típica de "menor" en mappers sin IRQ):** nuestro mapper aplica las
  escrituras al bajar M2, como un 74HC161 real (que se carga al final del ciclo). Mesen2 las aplica
  al instante. Si el juego cambia el banco CHR a mitad de pantalla, unos pocos píxeles cambian.
  Comprobado con `N8_EARLY_WRITE=1` (modo que imita a Mesen2): Challenge of the Dragon (11) y
  Bakushou!! 2 (33) pasan a ser idénticos. Este modo excluye `$6000-$7FFF`.
- **diverge:** cualquier diferencia mayor (una barra desplazada una línea ya son ≥ 256 píxeles).
  Hay que revisarla.

## Validación del propio banco (2026-11-04)
- Super Mario Bros.: 600 fotogramas idénticos a la referencia (a 50 y a 25 MHz).
- **Reintroduciendo el fallo de Dragon Warrior IV** (CHR-RAM sin recortar), el banco lo detecta
  solo: en el fotograma 165 la referencia muestra "PRESENTED BY ENIX" y el mapper defectuoso deja
  la pantalla negra. Es el síntoma que se vio en la consola.
- **Tanda de los 34 juegos de `~/SD_Pruebas` (1200 fotogramas, 25 MHz): 33 idénticos** a
  Mesen2 (`tools/n8sim/reports/sd-pruebas-v2/`). El único distinto es Ninja Gaiden II, con 1–2
  píxeles en 2–3 fotogramas.
  - Ciclos, PC y OAM son iguales siempre. El primer byte distinto es la pila `$01F4` ($CA frente
    a $C8): la dirección de retorno de la IRQ difiere en una instrucción.
  - Es el **retardo del filtro de ruido de A12** (3 muestras de clk más la sincronización,
    ~80–120 ns): a veces la IRQ llega justo después de que la CPU la compruebe. Mesen2 no filtra.
  - A 50 MHz pasa en menos fotogramas, lo que encaja con esa explicación.
  - No es un fallo, pero es candidato a explicar el leve parpadeo arriba a la izquierda de la
    barra de SMB3 que se vio en la consola. Mejora posible: muestrear A12 en los dos flancos de
    clk para reducir el retardo sin debilitar el filtro, y comprobarlo en la consola.

## Sonido de expansión (desde la fase 3s)
Con `N8_AUDIO=1` (por ejemplo `N8_AUDIO=1 python3 -I difftest.py ...`) las dos ejecuciones escriben
`audio.txt` junto a `hashes.txt`: "ciclo de CPU, nivel" cada vez que cambia el nivel del chip de sonido.
La referencia es Mesen2 parcheado (Vrc6Audio.h y Sunsoft5bAudio.h llaman a `N8AudioLog.h`); en nuestro
modelo es el nivel que entra a `audio_dac.v` (salida `snd_level` de n8_sim_top). `audiodiff.py CARPETA`
compara las dos señales y tolera desfases de hasta 3 ciclos alrededor de cada cambio.
- Akumajou Densetsu (VRC6): idéntico en 35,7 millones de ciclos (51 984 cambios).
- Namco 163: Megami Tensei II, Erika to Satoru y Final Lap, equivalentes por fotograma (Mesen2 parcheado en
  Namco163Audio.h). Como en el 5B, la fase del motor (qué canal toca en cada momento) depende del arranque.
- Gimmick! (5B): no coincide ciclo a ciclo porque la fase de los generadores de tono depende del arranque
  (Mesen2: desde el encendido; N8: desde que sale del menú). `audiodiff.py` compara entonces por
  fotograma (nivel medio y número de cambios): equivalente en 3596 de 3599 fotogramas.
- El banco no oye el DAC de 1 bit ni el filtro de la placa: el volumen y el timbre se juzgan en la Famicom.

## Lecturas de registros (desde la fase 3d)
n8_sim_top saca `cpu_dout` y `cpu_doe` (bits que conduce la FPGA en ese momento). En cada lectura el puente
toma el valor de la SRAM o el bus abierto de Mesen2 y sustituye esos bits. Así los bits que el chip no
conduce dan el mismo bus abierto que en la referencia.

## Bus abierto de la PPU
Cuando el mapper no selecciona ni la SRAM CHR ni la CIRAM, el puente devuelve $FF a Mesen2, igual
que la placa con el pull-up débil de `ppu_d` (fase 3c, mappers 93 y 185). Mesen2, en su mapper
185, devuelve el bus abierto de su PPU con D0 = 1: si el juego solo comprueba que no lee la CHR,
las dos cosas dan el mismo resultado.

## Casos en que la referencia (Mesen2) se equivoca (fase 3c)
Con la base de datos de juegos desactivada, Mesen2 usa solo la cabecera, y en algunos juegos falla
donde nuestro RBF no. Hay que mirar las imágenes antes de dar un "diverge" por fallo nuestro:
- Fighting Hero III (112): Mesen2 se queda en una pantalla verde; el nuestro llega al título.
- Popo Team, Super Pang II (141) y Silver Eagle (138): CHR revuelta en Mesen2, correcta en el nuestro.
- Harikiri Stadium Heisei (82): el juego lee la RAM del X1-017 sin haber dado permiso. Mesen2 devuelve
  $00; el chip real no contesta y la CPU lee el bus abierto ($70), igual que el puente. Cambia la
  semilla del modo demo (se vio con `tools/n8sim/ramdiff.py`: RAM idéntica hasta el fotograma 10).

## Lo que el banco NO puede ver
| Tipo de fallo | ¿Lo detecta? |
|---|---|
| Lógica de mappers, máscaras, valores que envía el OS (p. ej. Dragon Warrior IV) | ✅ |
| Ruido eléctrico en A12 (el salto de la barra de SMB3) | ❌ (se cubre con el testbench con picos) |
| Frecuencia real de `clk`, tiempos de las SRAM, transceptores, CPLD | ❌ |
| Menú del OS, SD, carga de RBF | ❌ (haría falta un modelo del CPLD: fase B) |
| Juegos que necesitan una entrada concreta para llegar a cierta parte | parcial: la secuencia de botones es aleatoria pero fija |

## Detalles que costaron (para no repetirlos)
- Mesen2 lee el vector de reset **fuera** de un ciclo con `ProcessCpuClock`: el puente genera
  un ciclo de bus sintético (si no, la ROM no está habilitada porque `m2_ok` necesita M2 alto).
- El makefile de Mesen2 no sigue cabeceras: `MapperFactory` solo ve `CreateN8FpgaMapper()`,
  y `make mesen` recompila siempre el puente.
- `libn8model.so` debe compilarse con las mismas definiciones que el runtime de Verilator
  (`VM_TRACE=0`, `-faligned-new`…); si no, `VerilatedContext` cambia de forma y se corrompe
  la memoria.
- `emu.takeScreenshot()` devuelve el último fotograma **mostrado** (puede ir atrasado): las
  capturas salen de `emu.getScreenBuffer()`, el mismo búfer del hash.
- **El punto de PPU de más (el más traicionero).** `NesPpu::Run()` es un do/while que siempre
  ejecuta al menos un punto. Al adelantar la PPU dentro de un acceso al cartucho, la llamada de
  Mesen al cerrar el ciclo (`EndCpuCycle`) a veces no tenía nada pendiente y aun así ejecutaba un
  punto: la PPU se adelantaba a la CPU, la NMI caía en otra instrucción y el juego se desviaba.
  Daba diferencias en Solomon's Key, Battletoads, TMNT III y Dragon Warrior IV, que **no eran
  de los mappers**. Se encontró con `N8_STATE=1` (hash de RAM/OAM, ciclos y PC por fotograma) y
  `N8_DUMPS` (volcado de RAM): el primer byte distinto fue la pila `$01FD` (flag N del P guardado
  por la NMI). Solución: adelantar solo hasta un punto antes del final del ciclo.
- `--report-only CARPETA` reclasifica un informe existente sin repetir las ejecuciones.
- **clk solo avanza con los eventos.** Tras cada cambio de dirección de la PPU, el puente adelanta clk
  hasta 3 relojes maestros (sin pasar del cierre del ciclo de CPU). Sin eso, una IRQ provocada por A12
  se veía un ciclo tarde, porque Mesen2 muestrea la IRQ al cerrar el ciclo. Con el adelanto, Ninja
  Gaiden II pasa a ser idéntico. Aun así, el banco tiene ~1 punto de PPU de granularidad: las pruebas
  de tiempo exacto (blargg 4-scanline_timing) hay que hacerlas en la consola.
- `trace_mmc3.lua` (escrituras a $8000-$9FFF con scanline), `trace_irq.lua` (IRQ atendidas con
  scanline/punto) y `N8_TRACE_A12=1` (cambios de A12 e /IRQ vistos por el puente) sirven para
  localizar problemas de IRQ. Así se encontró el corte de Armadillo 40 líneas antes.
- Para depurar una divergencia: `N8_STATE=1` dice en qué fotograma empieza a cambiar el estado de
  la CPU (puede ser cientos de fotogramas antes de que se vea) y `N8_DUMPS=f1,f2` vuelca la RAM.

## Licencias
Mesen2 es GPL-3 (`tools/mesen2`, commit b9fa69d). El puente (`tools/n8sim/N8FpgaMapper.*`) es
GPL-3 por enlazarse con Mesen2. Es una herramienta de pruebas: no forma parte de los RBF ni del
OS. Los mappers de Mesen2 se usan solo como referencia de comportamiento (caja negra).
