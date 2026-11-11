# Prueba del mapper NROM propio en la consola

## 0. Requisitos
- iverilog para simular: `sudo pacman -S iverilog`
- Quartus II 13.0sp1 Web Edition (Linux), con `quartus_sh` en el PATH.

## 1. Simular y compilar
```
make -C hdl sim      # debe terminar con "OK: todas las pruebas pasaron"
make -C hdl build    # genera hdl/out/NROM.RBF
```
Comprobar el tamaño que imprime `pad_rbf.py`: los RBF oficiales miden 50–75 KB.
Si sale ~150 KB, el bitstream no va comprimido. Hay que activar la compresión
(Device → Device and Pin Options → Configuration → "Generate compressed bitstreams")
antes de probarlo en la consola.

Revisar también el informe del fitter: **0 pines con conflicto** y las señales `*_n` en los pines esperados.

## 2a. Opción recomendada: SD limpia de pruebas (`~/SD_Pruebas`)
Copiar **el contenido** de `~/SD_Pruebas` a la raíz de una microSD FAT32 vacía:
```
EDFC/OS.BIN          OS v13 (copiado de la SD original)
EDFC/MAPROUT.BIN     78 mappers: 47 -> 100.RBF y 31 -> 101.RBF; el resto 0xFF (sin soporte)
EDFC/MAPS/100.RBF    fases 1-3b y sus variantes (hdl/out/100.RBF)
EDFC/MAPS/101.RBF    chips nuevos de la fase 3c (hdl/out/101.RBF)
EDFC/MAPS/255.RBF    mapper del menú (original)
EDFC/SAVE/           partidas guardadas (no borrar al actualizar)
PRUEBAS/             juegos de prueba por fase
```
- La tabla de save state está vacía (0xFF), así que el OS cae siempre en la tabla normal y no
  hace falta desactivar los save states.
- Un juego con un mapper fuera de la tabla dará "mapper no soportado". Es lo esperado.
- Al recompilar (`make -C hdl build`) hay que volver a copiar `hdl/out/100.RBF` y `hdl/out/101.RBF`
  a `EDFC/MAPS/`.

## 2b. Alternativa: instalar en la microSD de uso diario (reversible)
Usa el número de RBF **100** (libre) y redirige solo el mapper 0:
```
cp hdl/out/NROM.RBF /RUTA/SD/EDFC/MAPS/100.RBF
python3 hdl/tools/maprout.py set /RUTA/SD/EDFC/MAPROUT.BIN 0 100
```
⚠️ La tabla de *save state* también tiene el mapper 0 (→ `252.RBF`). Si la opción de save
states del menú está activada, el OS usará 252 en lugar de nuestro RBF. Hay que **desactivar
los save states** en las opciones durante la prueba (o cambiar la entrada con `--savestate`).

## 3. Juegos de prueba (mapper 0, en tu SD)
| Juego | PRG | CHR | Mirroring | Qué prueba |
|---|---|---|---|---|
| Super Mario Bros. (World) (HVC-SM) | 32 KB | 8 KB | V | NROM-256, scroll horizontal |
| Balloon Fight (USA) | 16 KB | 8 KB | H | NROM-128 (espejo de 16 KB) |
| Ice Climber (Japan) (En) | 16 KB | 8 KB | H | NROM-128, scroll vertical |
| Excitebike (Japan, USA) | 16 KB | 8 KB | V | Sprite 0 / split de pantalla |
| Magic Giral (Asia) (Unl) | 16 KB | CHR-RAM | H | escritura de CHR-RAM |

Comprobar en cada uno:
1. Arranca y se ve correcto (gráficos y scroll sin basura).
2. **RESET** de la consola → vuelve al menú del EverDrive.
3. Desde el menú, cargar otro juego (prueba que el modo OS sigue funcionando).

## 3b. Fase 2: MMC3 (mapper 4), carpeta `PRUEBAS/4 MMC3/`
| Juego | PRG | CHR | Qué prueba |
|---|---|---|---|
| Super Mario Bros. 3 (USA) (Rev 1) | 256 KB | 128 KB | IRQ: barra de estado fija abajo, cambios de mirroring |
| Kirby's Adventure (USA) (Rev 1) | 512 KB | 256 KB | tamaño máximo, IRQ intensiva, partida con pila |
| Mega Man 3 (USA) | 256 KB | 128 KB | IRQ (pantalla de selección, pausa) |
| Mega Man 4 (USA) (Rev 1) | 512 KB | CHR-RAM | CHR-RAM recortada a 8 KB (regla de DW IV) |
| Mega Man 5 (USA) | 256 KB | 256 KB | efectos con IRQ (escenarios con ondas/split) |
| Super Mario Bros. 2 (USA) (Rev 1) | 128 KB | 128 KB | bancos CHR de 1 KB animados |
| Ninja Gaiden II (USA) | 128 KB | 128 KB | escenas con splits por IRQ |
| TMNT III - The Manhattan Project (USA) | 256 KB | 256 KB | IRQ + bancos CHR |
| Crystalis (USA) | 256 KB | 128 KB | partida con pila, barra de estado |
| StarTropics (USA) | 256 KB | 256 KB | MMC6 tratado como MMC3; partida con pila |
| Rad Racer II (USA) | 64 KB | 64 KB | **4 pantallas** (MAP_CFG bit 3): carretera y marcador sin basura |

Comprobar sobre todo: que las barras de estado y los splits queden quietos (sin temblar ni
saltar de línea), que no haya basura gráfica y que las partidas se guarden y se recuperen.
Rad Racer II: si se ve bien, el OS original sí envía el bit de 4 pantallas. Si se ve mal
(pantallas repetidas o basura en la mitad de la imagen), el OS no lo envía y solo funcionará
con nuestro OS.

## 3c. Fase 3a: 17 mappers discretos, carpeta `PRUEBAS/5 Fase 3a/`
Cada archivo empieza por su número de mapper. Todos son idénticos a Mesen2 en el banco de pruebas
(salvo Firehawk y Mahjong World: unos pocos píxeles por el momento del latch o del arranque).
| Mapper | Juego | Qué mirar |
|---|---|---|
| 11 | Bible Adventures | arranca, gráficos y cambio de nivel |
| 33 | Akira | Taito: bancos PRG/CHR y cambio de mirroring |
| 34 | Deadly Towers / Impossible Mission II | BNROM (CHR-RAM) y NINA-001 (CHR-ROM, PRG-RAM) |
| 66 | Dragon Power | GxROM |
| 70 | Kamen Rider Club | Bandai |
| 71 | Fantastic Adventures of Dizzy / **Firehawk** | Camerica; Firehawk usa pantalla única por `$9000` |
| 79 | Double Strike | NINA-03/06 (registro en `$4100`) |
| 86 | Moero!! Pro Yakyuu | Jaleco JF-13 (sin la voz digitalizada: no implementada) |
| 87 | Goonies (Japan) | Jaleco (bits CHR cruzados) |
| 113 | HES 6-Pak | ⚠️ ROM australiana (PAL): si va rápida es por la región, no por el mapper |
| 140 | Bio Senshi Dan | Jaleco JF-11/14 |
| 146 | Galactic Crusader | Sachen (= 79) |
| 148 | Mahjong World | Sachen SA-0037 |
| 152 | Saint Seiya - Ougon Densetsu | Bandai con pantalla única |
| 184 | Madoola no Tsubasa | Sunsoft-1 |
| 206 | **Gauntlet** / Fantasy Zone | Namco 108; Gauntlet usa **4 pantallas** |
| 232 | Quattro Adventure | Camerica multijuego: probar varios de los 4 juegos |

Basta con que cada uno arranque, se vea bien un par de minutos y pase de pantalla o nivel.
Avisar sobre todo de basura gráfica, pantallas repetidas o cuelgues.

## 3d. Fase 3b: mappers complejos, carpeta `PRUEBAS/7 Fase 3b/`
| Mapper | Juego | Qué mirar |
|---|---|---|
| 9 | Mike Tyson's Punch-Out!! | MMC2: los gráficos de los boxeadores cambian bien (bancos por latch) |
| 10 | Fire Emblem Gaiden | MMC4; partida con pila |
| 16 | Dragon Ball Z II | Bandai FCG: barra/efectos por IRQ. ⚠️ **No guarda partida** (EEPROM pendiente) |
| 18 | Goal!! | Jaleco SS88006, IRQ |
| 21 | Wai Wai World 2 | VRC4 |
| 22 | Ganbare Pennant Race! | VRC2a |
| 23 | Contra (Japan) / Getsu Fuuma Den | VRC2b/VRC4e |
| 25 | Gradius II / TMNT (Japan) | VRC4: efectos de IRQ |
| 69 | Gimmick! / Dynamite Batman | FME-7: IRQ, barra de estado |
| 118 | Goal! Two / **Armadillo** | TxSROM; en Armadillo, el corte de pantalla de la intro en su sitio |
| 210 | Famista '94 / Family Circuit '91 | Namco 175/340 |

## 3f. Fase 3c: carpetas `PRUEBAS/9a Fase 3c RBF 100/` y `PRUEBAS/9b Fase 3c RBF 101/`
Los juegos de `9a` cargan `100.RBF` y los de `9b` cargan `101.RBF` (lo decide MAPROUT). Todos dieron
el mismo resultado que Mesen2 en el banco, salvo los marcados. Lo importante en la consola es lo
eléctrico y lo que el banco no ve:
| Mapper | Juego | Qué mirar |
|---|---|---|
| 185 | **Mighty Bomb Jack** / B-Wings | arranca (protección: necesita leer $FF con la CHR apagada; prueba el pull-up de `ppu_d`) |
| 48 | The Jetsons / The Flintstones / Bubble Bobble 2 | barra de estado y efectos por IRQ sin temblores |
| 37 / 47 | SMB + Tetris + NWC / Super Spike V'Ball + NWC | el menú elige juego y cada uno arranca |
| 119 | **High Speed** / Pin Bot | TQROM: gráficos que el juego dibuja en CHR-RAM (marcadores, tablero) |
| 76, 88, 95, 154 | Megami Tensei, Dragon Spirit, Dragon Buster, Devil Man | Namco 108: gráficos y mirroring |
| 155, 180, 115, 189 | Money Game, Crazy Climber, Lei Dian II, Thunder Warrior | arranque y juego |
| 64 / 158 | Shinobi, Rolling Thunder, Klax / Alien Syndrome | RAMBO-1: divisiones de pantalla por IRQ |
| 80 / 207 | **Minelvaton Saga** / Fudou Myouou Den | X1-005; Minelvaton guarda en la RAM del chip (pila) |
| 82 | **SD Keiji Blader** | X1-017; partida con pila |
| 68 | **After Burner** / Maharaja | Sunsoft-4: el cielo/suelo usa nametables de CHR-ROM; Maharaja guarda |
| 24 / 26 | Akumajou Densetsu / Madara | VRC6 (sin la música extra: en el NES no suena) |
| 85 | Lagrange Point | VRC7 (sin la música FM); partida con pila |
| 78 | **Holy Diver** / Cosmo Carrier | mirroring correcto al hacer scroll (Holy Diver usa el bit de 4 pantallas como marca) |
| 93 / 89 | Fantasy Zone / Mito Koumon | Sunsoft-2 |
| 67 | Fantasy Zone II | Sunsoft-3: IRQ |
| 65, 32, 75, 72, 92 | Spartan X 2, Image Fight, Goemon, Pinball Quest, Pro Soccer | Irem, VRC1, Jaleco |
| Sachen / NTDEC / otros | Super Pang, **Silver Eagle**, Final Combat, Great Wall, Jovial Race, Honey Peach, Huang Di, Metal Force, War in the Gulf, Caltron, Cheetahmen II, Xing Ji Zheng Ba | arranque y gráficos. En Silver Eagle Mesen2 falla y nuestro RBF no |

## 3g. Prueba de sonido de expansión (solo en la **Famicom**), carpeta `PRUEBAS/9c Prueba sonido (Famicom)/`
Primero `Tono 1 kHz (mapper 250, Balloon Fight).nes`: es Balloon Fight con el número de mapper
cambiado a 250. Con él, 100.RBF saca por el pin 97 un pitido de 1 kHz, medio segundo sí y medio no,
encima de la música del juego.
| Resultado | Qué significa |
|---|---|
| Se oye el pitido intermitente y el juego va normal | el camino del audio funciona: se pueden hacer VRC6, Sunsoft 5B, N163... |
| El juego va pero no se oye nada | el audio no sale por el pin 97 en esta placa, o la Famicom AV no lo mezcla: avisar |
| Zumbido continuo o ruido fuerte | quitar el cartucho y avisar (polaridad o filtro distintos) |
En el NES no se oye nada (es lo esperado: la consola no mezcla el audio del cartucho).

Si el pitido se oye, los juegos con sonido de expansión de la misma carpeta:
| Mapper | Juego | Qué escuchar |
|---|---|---|
| 24 (VRC6) | Akumajou Densetsu | la música lleva dos pulsos y una sierra extra: más llena que la de Castlevania III (NES) |
| 26 (VRC6b) | Mouryou Senki Madara / Esper Dream 2 | igual (en Madara, partida con pila) |
| 69 (5B) | Gimmick! | la música usa los 3 canales del 5B; volumen y timbre parecidos a una grabación de la Famicom |
Anotar también el **volumen relativo** frente al sonido normal de la consola (muy bajo / bien / saturado):
la escala se ajusta en `hdl/rtl` sin cambiar nada más.

## 3h. Fase 3d: la FPGA responde lecturas, carpeta `PRUEBAS/9d Fase 3d lecturas/`
Es la primera vez que la FPGA conduce el bus de datos de la CPU. Estos juegos leen registros del
mapper y, si leen un valor equivocado, suelen quedarse en negro o reiniciarse (protección). Probar
**primero en el NES** (con transceptores) y después en la Famicom (sin transceptores).
| Mapper | Juego | Qué mirar |
|---|---|---|
| 150 | Chinese Checkers / English Pyramid | arranca y se juega (comprueba el registro leído) |
| 132 | Bingo / 1991 Du Ma Racing | arranca (protección TXC) |
| 172 | Mahjong Block (Idea-Tek) | arranca; mirroring correcto |
| 173 | F-15 City War (Idea-Tek) | arranca; gráficos |
| 136 | Mahjong Trap | arranca |
| 147 | Challenge of the Dragon | arranca y juega |
| 36 | Strike Wolf | arranca y juega |
| 143 | Magical Mathematics | arranca (lee la protección en $4100) |
| 115 | Shisen Mahjong 2 | arranca |
Si alguno se cuelga en la consola pero el resto va bien, anotar cuál: el banco dice que todos dan lo
mismo que Mesen2, así que sería un problema eléctrico o de tiempos del bus en ese caso concreto.

## 3i. Namco 163 (RBF 102), carpeta `PRUEBAS/9e Namco 163/`
| Juego | Qué mirar |
|---|---|
| Megami Tensei II | arranca, gráficos (usa CIRAM como CHR); **partida con pila** en la PRG-RAM |
| Final Lap | en la Famicom, la música lleva los canales del N163 |
| Erika to Satoru no Yume Bouken | en la Famicom, música del N163 |
| Battle Fleet / Famista '90 | arranque, IRQ y gráficos |
Los primeros fotogramas de algunos juegos pueden salir con basura: el N163 arranca con registros
indefinidos y esos juegos tardan en escribirlos (también pasa en el chip real).

## 3e. Pruebas automáticas del MMC3 (blargg), carpeta `PRUEBAS/8 Tests MMC3/`
Cada ROM escribe el resultado en pantalla en pocos segundos: anotar "Passed" o "Failed #n".
| ROM | Esperado | Qué mide |
|---|---|---|
| 1-clocking | Passed | contador por A12 |
| 2-details | Passed | detalles de recarga/IRQ |
| 3-A12_clocking | Passed | filtro de A12 |
| **4-scanline_timing** | Passed | **tiempo exacto de la IRQ** (el banco no lo puede medir: es la prueba decisiva del retardo de nuestro filtro) |
| 5-MMC3 | Passed | comportamiento de la revisión B (SMB3, Mega Man 3) |
| 6-MMC3_alt | Failed #2 | prueba la revisión A: es normal que falle |

## 4. Si algo falla
- Pantalla negra o gris: apagar y encender. El OS vuelve a cargar todo desde la SD,
  y el RBF solo vive en la FPGA hasta el siguiente reset.
- Revertir: `python3 hdl/tools/maprout.py set /RUTA/SD/EDFC/MAPROUT.BIN 0 0`
  (o restaurar la copia `.bak-*` que crea el script).
- Riesgo eléctrico: el diseño nunca conduce los buses de datos (siempre en Z) y usa
  exactamente los mismos pines y direcciones que los RBF oficiales.
- Partidas guardadas: NROM solo toca los primeros 8 KB de la PRG-RAM. Aun así, conviene
  tener copia de `/EDFC/SAVE/` (ya está en la copia de la SD).
