# Plan de pruebas en consola (N8 de NES y N8 de Famicom)

Generado por tools/pruebas-n8/generar.py desde plan.json. La versión interactiva (con resultados que
Claude puede leer) es la página "Pruebas N8" publicada en claude.ai. Aquí, la misma lista en texto.

**Cómo probar:** arranca cada juego y juega uno o dos minutos. Marca OK si todo va como debe. Si falla,
anota qué ves (pantalla negra o gris, gráficos rotos, parpadeo, se reinicia, se cuelga), en qué momento
y si se repite. **Partidas con pila:** guarda, apaga la consola 10 segundos, enciende, vuelve a cargar el
juego desde el menú del N8 y comprueba la partida.

## NES (N8 de NES)

### Repetir tras las correcciones y la optimización (5 y 6 de noviembre)
Carpeta: `PRUEBAS/10 Repetir (y tu SD de fábrica para las comparaciones)` · RBF: 100.RBF, 101.RBF y 102.RBF nuevos (8 de noviembre)

Antes: copia a la microSD los tres RBF nuevos (EDFC/MAPS/100.RBF, 101.RBF y 102.RBF), el MAPROUT.BIN nuevo (EDFC) y las carpetas PRUEBAS/10 Repetir y PRUEBAS/11 Fase 4. No toques EDFC/SAVE. Los RBF del 6 de noviembre están optimizados (menos lógica, mismo comportamiento comprobado en el emulador); los cuatro últimos juegos de esta lista prueban justo lo que se tocó. Los tres últimos se prueban con tu SD de fábrica de siempre, en el mismo NES: sirven para saber si los sprites negros son de nuestro mapper o del juego/consola (en el emulador salen bien con nuestro mapper). Ojo con las ROMs (Europe)/(PAL): están hechas para consolas PAL y en tu NES y tu Famicom (NTSC) pueden ir rápidas, con basura o colgarse aunque el mapper esté bien.

| Juego | Mapper | Qué mirar | Qué anotar |
|---|---|---|---|
| Mike Tyson's Punch-Out!! (repetir) | 9 MMC2 | Latch del MMC2 corregido. Caras, poses y público sin tiles cambiados; pelea un par de asaltos. | OK o qué falla |
| Fire Emblem Gaiden (repetir) | 10 MMC4 | Latch del MMC4 corregido. Textos, menús y nombres sin letras rotas. | OK o qué falla |
| Fire Emblem - Ankoku Ryuu to Hikari no Tsurugi | 10 MMC4 | El juego en el que Krikzz corrigió el MMC4. Textos y mapa sin letras rotas. | OK o qué falla |
| Gimmick! (Japan) | 69 FME-7 | La versión normal (la Memorial Series no arranca ni en el emulador). En el NES suena sin la música del 5B: es normal. | OK o qué falla |
| High Speed (USA) | 119 TQROM | La versión de EE. UU. La europea (PAL) falla también en el emulador cuando se le da la velocidad de una consola NTSC como la tuya: título con basura y pantalla negra, justo lo que viste. | OK o qué falla |
| Pin Bot (USA) | 119 TQROM | Igual que High Speed: la europea se cuelga en una consola NTSC (también en el emulador). Prueba esta. | OK o qué falla |
| Fantastic Adventures of Dizzy (USA) | 71 Camerica | Versión NTSC (la que probaste era la europea, PAL, hecha para otra velocidad de consola). ¿Siguen saliendo sprites negros? | OK o qué falla |
| Quattro Adventure con la SD de fábrica | 232 | Mismo juego y misma escena donde viste los sprites negros, pero con tu SD de fábrica. | Si se ve igual (negro) o bien. |
| Magic Giral con la SD de fábrica | 0 NROM | Juega hasta que se quite una prenda, con tu SD de fábrica. | Si parpadea / se pone negro igual o no. |
| Dizzy (Europe) con la SD de fábrica | 71 Camerica | La versión europea con tu SD de fábrica. | Si salen los sprites negros igual o no. |
| Gradius II (Japan) | 25 VRC4 | Contador de IRQ de los VRC optimizado. Juega el nivel 1: los efectos y la parte de abajo de la pantalla no deben temblar ni cortarse en otro sitio. | OK o qué falla |
| Akumajou Densetsu (Japan) | 24 VRC6 | Misma IRQ (VRC6). La barra de estado de arriba debe quedarse quieta al avanzar. En el NES no suena la música del VRC6: es normal. | OK o qué falla |
| Lagrange Point (Japan) | 85 VRC7 | Misma IRQ (VRC7). Llega al mapa y abre un menú. Sin la música FM: es normal (no está hecha). | OK o qué falla |
| Wagyan Land 2 (Japan) | 210 Namco 340 | Detección del Namco 340 corregida (el banco con mando vio una columna rota y la barra de abajo sin texto). Juega el primer nivel: ni columnas raras ni barra sin letras. | OK o qué falla |
| Minelvaton Saga (Japan) | 80 X1-005 | La RAM interna del chip (la que guarda la partida) cambió de sitio en la PRG-RAM. Empieza, guarda en el juego, apaga 10 segundos y vuelve a cargar. | Si la partida sigue tras apagar. (pila) |

### Fase 4: mappers nuevos (lotes 1 y 2)
Carpeta: `PRUEBAS/11 Fase 4` · RBF: 102.RBF (144 en el 100)

Primeros 49 mappers de la fase 4 (los que faltaban para los 177 de la lista oficial). Estos 14 son los que tienen juego en tu colección; en el emulador todos arrancan igual que con el mapper de referencia. Arranca cada uno y juega un poco.

| Juego | Mapper | Qué mirar | Qué anotar |
|---|---|---|---|
| Videomation (USA) | 13 CPROM | Programa de dibujo con 16 KB de CHR-RAM: dibuja algo y cambia de herramienta; los gráficos no deben corromperse. | OK o qué falla |
| Crime Busters (Brazil) | 38 Bit Corp | Juego de pistola: basta con ver que arranca y llega al juego (sin la Zapper no se puede jugar). | OK o qué falla |
| Senjou no Ookami (Japan) | 94 UN1ROM | Commando japonés: juega el principio. | OK o qué falla |
| Kaiketsu Yancha Maru (Japan) | 97 Irem TAM-S1 | Juega el primer nivel (mirroring y bancos). | OK o qué falla |
| Death Race (USA) | 144 AGCI | Variante de Color Dreams con un conflicto de bus que el N8 no puede imitar: comprueba que arranca y juega una carrera. | OK o qué falla |
| Sidewinder (Asia, PAL) | 145 Sachen | ROM PAL: puede ir rápida en tu consola NTSC sin culpa del mapper. Mira que arranque. | OK o qué falla |
| Taiwan Mahjong 16 | 149 Sachen | Arranca (los primeros instantes pueden salir con basura) y entra en una partida. | OK o qué falla |
| Magic Jewelry 2 | 216 | Juega una partida (tipo Columns). | OK o qué falla |
| Sheng Huo Lie Zhuan | 240 | RPG chino: llega a la primera pantalla de juego. | OK o qué falla |
| Wai Xing Zhan Shi | 242 Waixing | Llega al título y pulsa Start. | OK o qué falla |
| Decathlon (Asia) | 244 C&E | Haz una prueba (cambia de bancos por tabla). | OK o qué falla |
| Ying Xiong Yuan Yi Jing Chuan Qi | 245 MMC3 Waixing | RPG chino con CHR-RAM: llega al juego; textos legibles. | OK o qué falla |
| Feng Shen Bang | 246 | RPG chino: arranca y llega al juego. | OK o qué falla |
| Time Diver Avenger | 250 MMC3 Nitra | Juega el primer nivel (IRQ del MMC3). | OK o qué falla |

### Regresión: NROM, MMC1, UxROM, CNROM y AxROM
Carpeta: `PRUEBAS/ (raíz), 1 MMC1, 2 UxROM, 3 CNROM, 7 AxROM` · RBF: 100.RBF

Ya funcionaron en la fase 1. Desde entonces el RBF 100 ha cambiado mucho: basta con arrancar cada uno y jugar un minuto.

| Juego | Mapper | Qué mirar | Qué anotar |
|---|---|---|---|
| Super Mario Bros. | 0 NROM | Juega el 1-1 y entra en una tubería (1-2 subterráneo). | OK o qué falla |
| Balloon Fight | 0 NROM | Arranca y juega una fase. | OK o qué falla |
| Excitebike | 0 NROM | Arranca y haz una carrera corta. | OK o qué falla |
| Ice Climber | 0 NROM | Arranca y sube un par de pisos (scroll vertical). | OK o qué falla |
| Magic Giral | 0 NROM | Arranca y juega un minuto. | OK o qué falla |
| Castlevania II - Simon's Quest | 1 MMC1 | Entra en la primera ciudad; textos legibles. | OK o qué falla |
| Dragon Warrior IV | 1 MMC1 (SUROM) | Era el fallo gráfico de la fase 1. Crea partida, juega un poco y guarda. | Si guarda y recupera la partida. (pila) |
| Final Fantasy | 1 MMC1 | Guarda en una posada. | Si la partida sigue tras apagar. (pila) |
| The Legend of Zelda | 1 MMC1 | Crea partida, guarda (Continue/Save) y apaga. | Si la partida sigue tras apagar. (pila) |
| Mega Man 2 | 1 MMC1 | Elige un jefe y juega el principio del nivel. | OK o qué falla |
| Metroid | 1 MMC1 | Pasa por unas salas con scroll vertical y horizontal. | Basura en los bordes al hacer scroll. |
| Castlevania | 2 UxROM | Juega el primer nivel. | OK o qué falla |
| Contra | 2 UxROM | Juega el primer nivel. | OK o qué falla |
| DuckTales | 2 UxROM | Elige un nivel y juega un poco. | OK o qué falla |
| Mega Man | 2 UxROM | Elige un jefe y juega un poco. | OK o qué falla |
| Adventure Island | 3 CNROM | Juega el 1-1. | OK o qué falla |
| Arkanoid | 3 CNROM | Juega la primera pantalla (sin el mando especial se mueve mal: es normal). | OK o qué falla |
| Gradius | 3 CNROM | Juega el principio del nivel 1. | OK o qué falla |
| Solomon's Key | 3 CNROM | Juega la primera sala. | OK o qué falla |
| Battletoads | 7 AxROM | Juega el nivel 1. | OK o qué falla |
| Marble Madness | 7 AxROM | Juega la primera pista. | OK o qué falla |
| R.C. Pro-Am | 7 AxROM | Haz una carrera. | OK o qué falla |
| Wizards & Warriors | 7 AxROM | Juega el principio del nivel 1. | OK o qué falla |

### MMC3 (fase 2)
Carpeta: `PRUEBAS/4 MMC3` · RBF: 100.RBF

El MMC3 corta la pantalla con su IRQ (barras de estado). Fíjate en que las barras no tiemblen ni salten.

| Juego | Mapper | Qué mirar | Qué anotar |
|---|---|---|---|
| Super Mario Bros. 3 | 4 MMC3 | La barra de abajo no debe saltar. Mira la esquina superior izquierda: antes había un leve parpadeo. | ¿Sigue el parpadeo? ¿Lo ves igual con la SD de fábrica? |
| Super Mario Bros. 2 | 4 MMC3 | Juega el 1-1. | OK o qué falla |
| Kirby's Adventure | 4 MMC3 | Barra de estado de abajo estable. Guarda partida (se guarda sola al pasar de nivel). | Si la partida sigue tras apagar. (pila) |
| Mega Man 3 | 4 MMC3 | Elige un jefe; barra de energía estable. | OK o qué falla |
| Mega Man 4 | 4 MMC3 (CHR-RAM) | Elige un jefe; gráficos correctos (usa CHR-RAM). | OK o qué falla |
| Mega Man 5 | 4 MMC3 | Elige un jefe y juega un poco. | OK o qué falla |
| Ninja Gaiden II | 4 MMC3 | Escenas de introducción y barra superior del nivel 1. | OK o qué falla |
| TMNT III: The Manhattan Project | 4 MMC3 | Barra de estado y primer nivel. | OK o qué falla |
| Crystalis | 4 MMC3 | Guarda partida (en el menú, con un objeto de guardar o al principio). | Si la partida sigue tras apagar. (pila) |
| StarTropics | 4 MMC3 (MMC6) | Guarda partida. | Si la partida sigue tras apagar. (pila) |
| Rad Racer II | 4 MMC3 (4 pantallas) | Ya funcionó; comprobar que sigue igual (carretera y fondo). | OK o qué falla |

### Pruebas automáticas del MMC3 (blargg)
Carpeta: `PRUEBAS/8 Tests MMC3` · RBF: 100.RBF

Cada ROM escribe el resultado en pantalla en pocos segundos. Anota el texto exacto (Passed o Failed #n).

| Juego | Mapper | Qué mirar | Qué anotar |
|---|---|---|---|
| 1-clocking | 4 MMC3 | Esperado: Passed. | Texto que sale en pantalla. |
| 2-details | 4 MMC3 | Esperado: Passed. | Texto que sale en pantalla. |
| 3-A12_clocking | 4 MMC3 | Esperado: Passed. | Texto que sale en pantalla. |
| 4-scanline_timing | 4 MMC3 | La prueba decisiva: mide el tiempo exacto de la IRQ. En el banco falla; aquí decide si hay que acelerar el filtro de A12. | Texto exacto (Passed o Failed #n). |
| 5-MMC3 | 4 MMC3 | Esperado: Passed. | Texto que sale en pantalla. |
| 6-MMC3_alt | 4 MMC3 | Esperado: Failed #2 (prueba otra revisión del chip; es normal). | Texto que sale en pantalla. |

### Fase 3a: 17 mappers sencillos
Carpeta: `PRUEBAS/5 Fase 3a` · RBF: 100.RBF

Arranca cada uno y juega un minuto. Lo importante: que arranque y que los gráficos y el scroll estén bien.

| Juego | Mapper | Qué mirar | Qué anotar |
|---|---|---|---|
| Bible Adventures | 11 Color Dreams | Elige un juego del menú y juega. | OK o qué falla |
| Akira | 33 Taito TC0190 | Arranca; pantallas de texto y gráficos. | OK o qué falla |
| Deadly Towers | 34 BNROM | Juega; cambio de pantallas. | OK o qué falla |
| Impossible Mission II | 34 NINA-001 | Arranca y juega. | OK o qué falla |
| Dragon Power | 66 GxROM | Arranca y juega. | OK o qué falla |
| Kamen Rider Club | 70 Bandai | Arranca y juega. | OK o qué falla |
| The Fantastic Adventures of Dizzy | 71 Camerica | Muévete entre pantallas. | OK o qué falla |
| Firehawk | 71 Camerica | Juega el principio (pantalla única). | OK o qué falla |
| Double Strike | 79 NINA-03 | Arranca y juega. | OK o qué falla |
| Moero!! Pro Yakyuu | 86 Jaleco | Arranca y juega. La voz ("Play ball") no suena: no está implementada. | OK o qué falla |
| Goonies (Japan) | 87 Jaleco | Arranca y juega. | OK o qué falla |
| HES 6-Pak | 113 HES | Elige varios juegos del menú. | Cuáles fallan, si alguno. |
| Bio Senshi Dan | 140 Jaleco | Arranca y juega. | OK o qué falla |
| Galactic Crusader | 146 NINA-06 | Arranca y juega. | OK o qué falla |
| Mahjong World | 148 Sachen | Arranca (los primeros instantes pueden mostrar basura) y juega. | OK o qué falla |
| Saint Seiya - Ougon Densetsu | 152 Bandai | Arranca y juega. | OK o qué falla |
| Madoola no Tsubasa | 184 Sunsoft-1 | Arranca y juega. | OK o qué falla |
| Fantasy Zone (Tengen) | 206 Namco 108 | Juega el primer nivel. | OK o qué falla |
| Gauntlet (Tengen) | 206 Namco 108, 4 pantallas | Recorre el laberinto en las cuatro direcciones. | OK o qué falla |
| Quattro Adventure | 232 Camerica | Prueba los 4 juegos del menú. | Cuáles fallan, si alguno. |

### Fase 3b: mappers complejos
Carpeta: `PRUEBAS/7 Fase 3b` · RBF: 100.RBF

Chips con IRQ y bancos finos. Fíjate en las barras de estado, los efectos a media pantalla y las partidas con pila.

| Juego | Mapper | Qué mirar | Qué anotar |
|---|---|---|---|
| Mike Tyson's Punch-Out!! | 9 MMC2 | REPETIR con el 100.RBF nuevo (latch del MMC2 corregido el 5-nov). Las caras y poses de los boxeadores cambian bien, sin tiles cambiados. | OK o qué falla |
| Fire Emblem Gaiden | 10 MMC4 | REPETIR con el 100.RBF nuevo (latch del MMC4 corregido el 5-nov). Textos y menús sin letras rotas; guarda partida. | Si la partida sigue tras apagar. (pila) |
| Dragon Ball Z II | 16 Bandai FCG | Efectos y barra (IRQ). NO guarda partida: su EEPROM no está hecha; es lo esperado. | OK o qué falla |
| Goal!! | 18 Jaleco SS88006 | Arranca y juega un partido (IRQ). | OK o qué falla |
| Wai Wai World 2 | 21 VRC4 | Juega el principio. | OK o qué falla |
| Ganbare Pennant Race! | 22 VRC2a | Arranca y juega. | OK o qué falla |
| Contra (Japan) | 23 VRC2b | Mapa del principio y primer nivel. | OK o qué falla |
| Getsu Fuuma Den | 23 VRC2b/VRC4e | Arranca y juega. | OK o qué falla |
| Gradius II | 25 VRC4 | Efectos a media pantalla del nivel 1. | OK o qué falla |
| TMNT (Japan) | 25 VRC4 | Arranca y juega. | OK o qué falla |
| Dynamite Batman | 69 FME-7 | Juega; barra de estado (IRQ). | OK o qué falla |
| Gimmick! (Memorial Series) | 69 FME-7 + 5B | Esta ROM no arranca ni en el emulador (es la versión modificada del recopilatorio de PS1): no es fallo del mapper. Prueba en su lugar 9c Prueba sonido (Famicom)/Gimmick! (Japan), que también arranca en el NES (sin la música del 5B). | OK o qué falla |
| Armadillo | 118 TxSROM | En la intro, el corte de pantalla debe quedar en su sitio (abajo, no a media pantalla). | OK o qué falla |
| Goal! Two | 118 TxSROM | Arranca y juega un partido. | OK o qué falla |
| Family Circuit '91 | 210 Namco 175 | Guarda (opciones o datos de carrera). | Si los datos siguen tras apagar. (pila) |
| Famista '94 | 210 Namco 340 | Arranca y juega. | OK o qué falla |

### Fase 3c: variantes en el RBF 100
Carpeta: `PRUEBAS/9a Fase 3c RBF 100` · RBF: 100.RBF

Variantes de MMC1, UxROM, CNROM, MMC3, Namco 108 y Taito. Dos comprueban algo eléctrico: Mighty Bomb Jack y High Speed.

| Juego | Mapper | Qué mirar | Qué anotar |
|---|---|---|---|
| Mighty Bomb Jack | 185 CNROM con protección | IMPORTANTE: tiene que arrancar. Comprueba la CHR apagada leída como $FF (pull-up del bus de la PPU). | Si arranca o se queda en negro. |
| B-Wings | 185 CNROM con protección | Tiene que arrancar (misma protección). | OK o qué falla |
| High Speed | 119 TQROM | IMPORTANTE: marcador y textos del pinball, que se dibujan en CHR-RAM extra. | Gráficos del marcador rotos o bien. |
| Pin Bot | 119 TQROM | Tablero y marcador. | OK o qué falla |
| The Jetsons | 48 Taito TC0690 | Barra de estado sin temblar. | OK o qué falla |
| The Flintstones (Japan) | 48 Taito TC0690 | Barra de estado sin temblar. | OK o qué falla |
| Bubble Bobble 2 | 48 Taito TC0690 | Arranca y juega. | OK o qué falla |
| Super Mario Bros. + Tetris + NWC | 37 MMC3 multijuego | El menú y los tres juegos. | Cuáles fallan, si alguno. |
| Super Spike V'Ball + NWC | 47 MMC3 multijuego | Los dos juegos. | OK o qué falla |
| Lei Dian II | 115 MMC3 Kasheng | Arranca y juega. | OK o qué falla |
| Thunder Warrior | 189 MMC3 TXC | Arranca y juega. | OK o qué falla |
| Megami Tensei (Digital Devil Story) | 76 Namco 108 | Arranca; mapa y textos. | OK o qué falla |
| Dragon Spirit | 88 Namco 108 | Juega el primer nivel. | OK o qué falla |
| Dragon Buster | 95 Namco 108 | Arranca y juega (mirroring por registro). | OK o qué falla |
| Devil Man | 154 Namco 108 | Arranca; cambios de pantalla correctos. | OK o qué falla |
| The Money Game | 155 MMC1A | Arranca y juega. | OK o qué falla |
| Crazy Climber | 180 UNROM | Arranca (se juega con dos mandos; basta con ver que va). | OK o qué falla |

### Fase 3c: chips nuevos en el RBF 101
Carpeta: `PRUEBAS/9b Fase 3c RBF 101` · RBF: 101.RBF

Primera vez que se usa el RBF 101 en la consola. Si NINGUNO arranca, el problema es el RBF entero: avísame en seguida.

| Juego | Mapper | Qué mirar | Qué anotar |
|---|---|---|---|
| Shinobi | 64 RAMBO-1 | Primer nivel; barra de estado. | OK o qué falla |
| Rolling Thunder | 64 RAMBO-1 | Primer nivel. | OK o qué falla |
| Klax | 64 RAMBO-1 | Arranca y juega. | OK o qué falla |
| Alien Syndrome | 158 RAMBO-1 | Arranca; mirroring al moverse. | OK o qué falla |
| After Burner | 68 Sunsoft-4 | El cielo y el suelo usan nametables de CHR-ROM: tienen que verse bien. | OK o qué falla |
| Maharaja | 68 Sunsoft-4 | Guarda partida. | Si la partida sigue tras apagar. (pila) |
| Minelvaton Saga | 80 Taito X1-005 | Guarda partida (RAM del chip). | Si la partida sigue tras apagar. (pila) |
| Fudou Myouou Den | 207 Taito X1-005 | Arranca; cambios de pantalla. | OK o qué falla |
| SD Keiji - Blader | 82 Taito X1-017 | Guarda partida. | Si la partida sigue tras apagar. (pila) |
| Image Fight | 32 Irem G-101 | Primer nivel. | OK o qué falla |
| Spartan X 2 | 65 Irem H3001 | Primer nivel; barra (IRQ). | OK o qué falla |
| Holy Diver | 78 Irem | Haz scroll: el mirroring debe ser correcto (sin basura). | OK o qué falla |
| Uchuusen Cosmo Carrier | 78 Jaleco | Arranca (pantalla única). | OK o qué falla |
| Ganbare Goemon! | 75 VRC1 | Primer nivel. | OK o qué falla |
| Akumajou Densetsu | 24 VRC6 | Gráficos y juego. En el NES falta la música extra: es normal. | OK o qué falla |
| Mouryou Senki Madara | 26 VRC6b | Arranca y guarda partida. | Si la partida sigue tras apagar. (pila) |
| Lagrange Point | 85 VRC7 | Arranca y guarda. No tiene música FM (VRC7 sin sonido todavía). | Si la partida sigue tras apagar. (pila) |
| Fantasy Zone II | 67 Sunsoft-3 | Primer nivel (IRQ). | OK o qué falla |
| Fantasy Zone (Sunsoft) | 93 Sunsoft-2 | Arranca y juega. | OK o qué falla |
| Tenka no Goikenban - Mito Koumon | 89 Sunsoft-2 | Arranca y juega. | OK o qué falla |
| Pinball Quest | 72 Jaleco | Arranca y juega. | OK o qué falla |
| Moero!! Pro Soccer | 92 Jaleco | Arranca y juega. | OK o qué falla |
| Super Pang | 141 Sachen 8259A | Arranca y juega. | OK o qué falla |
| Silver Eagle | 138 Sachen 8259B | En el emulador de referencia sale mal; en el N8 debería verse bien. | OK o qué falla |
| Final Combat | 139 Sachen 8259C | Arranca y juega. | OK o qué falla |
| The Great Wall | 137 Sachen 8259D | Arranca y juega. | OK o qué falla |
| Honey Peach | 243 Sachen | Arranca y juega. | OK o qué falla |
| Jovial Race | 133 Sachen | Arranca y juega. | OK o qué falla |
| Huang Di | 112 NTDEC | Arranca y juega. | OK o qué falla |
| War in the Gulf | 193 NTDEC | Arranca y juega. | OK o qué falla |
| Metal Force | 156 Daou | Arranca y juega. | OK o qué falla |
| Caltron 6 in 1 | 41 Caltron | Prueba varios juegos del menú. | Cuáles fallan, si alguno. |
| Cheetahmen II | 228 Action 52 | Arranca y juega. | OK o qué falla |
| Xing Ji Zheng Ba | 241 | Arranca y juega. | OK o qué falla |

### Fase 3d: la FPGA responde lecturas de la CPU
Carpeta: `PRUEBAS/9d Fase 3d lecturas` · RBF: 101.RBF y 100.RBF (115)

Primera vez que la FPGA envía datos a la CPU. Si leen un valor equivocado suelen quedarse en negro o reiniciarse (protección). Que arranquen es la prueba.

| Juego | Mapper | Qué mirar | Qué anotar |
|---|---|---|---|
| Chinese Checkers | 150 Sachen | Arranca y juega. | Si arranca o se queda en negro. |
| English, Pyramid | 150 Sachen | Arranca y juega. | Si arranca o se queda en negro. |
| Bingo (TXC) | 132 TXC | Arranca. | Si arranca o se queda en negro. |
| 1991 Du Ma Racing | 132 TXC | Arranca y juega. | Si arranca o se queda en negro. |
| Mahjong Block (Idea-Tek) | 172 TXC JV001 | Arranca; mirroring correcto. | Si arranca o se queda en negro. |
| F-15 City War (Idea-Tek) | 173 TXC | Arranca y juega. | Si arranca o se queda en negro. |
| Mahjong Trap | 136 Sachen | Arranca. | Si arranca o se queda en negro. |
| Challenge of the Dragon | 147 Sachen | Arranca y juega. | Si arranca o se queda en negro. |
| Strike Wolf | 36 TXC | Arranca y juega. | Si arranca o se queda en negro. |
| Magical Mathematics | 143 Sachen | Arranca (lee la protección en $4100). | Si arranca o se queda en negro. |
| Shisen Mahjong 2 | 115 Kasheng | Arranca. | Si arranca o se queda en negro. |

### Namco 163
Carpeta: `PRUEBAS/9e Namco 163` · RBF: 102.RBF

Primera vez que se usa el RBF 102. Los primeros instantes de algunos juegos pueden mostrar basura: el chip arranca con registros indefinidos.

| Juego | Mapper | Qué mirar | Qué anotar |
|---|---|---|---|
| Megami Tensei II | 19 Namco 163 | Arranca (usa la CIRAM como CHR) y guarda partida. | Si la partida sigue tras apagar. (pila) |
| Final Lap | 19 Namco 163 | Haz una carrera. | OK o qué falla |
| Erika to Satoru no Yume Bouken | 19 Namco 163 | Arranca y juega. | OK o qué falla |
| Battle Fleet | 19 Namco 163 | Arranca y juega. | OK o qué falla |
| Famista '90 | 19 Namco 163 | Arranca y juega un partido. | OK o qué falla |

## Famicom AV (N8 de Famicom)

### Prueba de tono
Carpeta: `PRUEBAS/9c Prueba sonido (Famicom)` · RBF: 100.RBF

Hazla la primera. Comprueba que el audio del cartucho llega a la Famicom AV.

| Juego | Mapper | Qué mirar | Qué anotar |
|---|---|---|---|
| Tono 1 kHz (mapper 247, Balloon Fight) | 247 prueba | Encima de la música de Balloon Fight debe sonar un pitido de 1 kHz, medio segundo sí y medio no. (El tono pasó del mapper 250 al 247: el 250 es un juego oficial.) | Se oye / no se oye / zumbido o ruido fuerte (si hay zumbido fuerte, saca el cartucho). |

### Sonido de expansión
Carpeta: `PRUEBAS/9c Prueba sonido (Famicom) y 9e Namco 163` · RBF: 101, 100 y 102.RBF

Solo si el tono se oye. Escucha la música y anota el volumen de los canales extra frente al sonido normal de la consola.

| Juego | Mapper | Qué mirar | Qué anotar |
|---|---|---|---|
| Akumajou Densetsu | 24 VRC6 | La música lleva dos pulsos y una sierra extra: suena más llena que Castlevania III de NES. | Cómo suena y volumen. |
| Gimmick! | 69 Sunsoft 5B | La música usa los tres canales del 5B. | Cómo suena y volumen. |
| Mouryou Senki Madara | 26 VRC6b | Música VRC6 (puede tardar en aparecer: avanza un poco). | Cómo suena y volumen. |
| Esper Dream 2 | 26 VRC6b | Música VRC6 (avanza un poco en el juego). | Cómo suena y volumen. |
| Final Lap | 19 Namco 163 | Música del N163. | Cómo suena y volumen. |
| Erika to Satoru no Yume Bouken | 19 Namco 163 | Música del N163. | Cómo suena y volumen. |
| Megami Tensei II | 19 Namco 163 | Música del N163. | Cómo suena y volumen. |
| Lagrange Point | 85 VRC7 | Sin música FM todavía: comprueba solo que no salga ruido raro. | OK o qué falla |

### Lecturas sin transceptores
Carpeta: `PRUEBAS/9d Fase 3d lecturas` · RBF: 101.RBF y 100.RBF (115)

La placa de Famicom no tiene transceptores: la FPGA llega al bus de la consola por 100 ohmios. Repite las lecturas aquí.

| Juego | Mapper | Qué mirar | Qué anotar |
|---|---|---|---|
| Chinese Checkers | 150 Sachen | Arranca y juega. | Si arranca o se queda en negro. |
| English, Pyramid | 150 Sachen | Arranca y juega. | Si arranca o se queda en negro. |
| Bingo (TXC) | 132 TXC | Arranca. | Si arranca o se queda en negro. |
| 1991 Du Ma Racing | 132 TXC | Arranca y juega. | Si arranca o se queda en negro. |
| Mahjong Block (Idea-Tek) | 172 TXC JV001 | Arranca. | Si arranca o se queda en negro. |
| F-15 City War (Idea-Tek) | 173 TXC | Arranca y juega. | Si arranca o se queda en negro. |
| Mahjong Trap | 136 Sachen | Arranca. | Si arranca o se queda en negro. |
| Challenge of the Dragon | 147 Sachen | Arranca y juega. | Si arranca o se queda en negro. |
| Strike Wolf | 36 TXC | Arranca y juega. | Si arranca o se queda en negro. |
| Magical Mathematics | 143 Sachen | Arranca. | Si arranca o se queda en negro. |
| Shisen Mahjong 2 | 115 Kasheng | Arranca. | Si arranca o se queda en negro. |

### Comprobación general en la placa de Famicom
Carpeta: `varias carpetas` · RBF: 100, 101 y 102.RBF

Confirma que los RBF funcionan igual en esta placa, sobre todo lo que depende de la electrónica.

| Juego | Mapper | Qué mirar | Qué anotar |
|---|---|---|---|
| Super Mario Bros. | 0 NROM (raíz) | Juega el 1-1. | OK o qué falla |
| The Legend of Zelda | 1 MMC1 (1 MMC1) | Guarda y recupera (pila de esta placa). | Si la partida sigue tras apagar. (pila) |
| Super Mario Bros. 3 | 4 MMC3 (4 MMC3) | Barra de estado sin saltos; mira también el parpadeo de arriba a la izquierda. | OK o qué falla |
| Rad Racer II | 4 MMC3, 4 pantallas | Carretera y fondo correctos. | OK o qué falla |
| Mega Man 4 | 4 MMC3 CHR-RAM | Elige un jefe; gráficos correctos. | OK o qué falla |
| Armadillo | 118 TxSROM (7 Fase 3b) | Corte de pantalla de la intro en su sitio. | OK o qué falla |
| Mighty Bomb Jack | 185 (9a) | Tiene que arrancar: aquí el pull-up de la PPU llega a la consola sin transceptor. | Si arranca o se queda en negro. |
| High Speed | 119 TQROM (9a) | Marcador del pinball correcto. | OK o qué falla |
| Shinobi | 64 RAMBO-1 (9b) | Primer nivel (RBF 101). | OK o qué falla |
| Battle Fleet | 19 Namco 163 (9e) | Arranca (RBF 102). | OK o qué falla |

