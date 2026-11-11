"""Plan de pruebas en consola del N8: datos únicos -> página (index.html) y docs/plan-pruebas-consola.md.

  python3 -I plan_pruebas.py CARPETA_SALIDA ../../docs/plan-pruebas-consola.md
  -> CARPETA_SALIDA/plan.json; la página es plantilla.html con __PLAN__ sustituido por ese JSON, publicada en
     https://claude.ai/artifact/M7ivqPxY2kGrvWydGXVXPd (los resultados viven en su colección `resultados`;
     los id de los juegos no deben cambiar o se pierden los resultados ya marcados).
"""
import json, re, pathlib, sys, unicodedata

def slug(s):
    s = unicodedata.normalize('NFKD', s).encode('ascii', 'ignore').decode()
    return re.sub(r'[^a-z0-9]+', '-', s.lower()).strip('-')[:40]

# (nombre, mapper, qué mirar, anotar, pila, tipo)   tipo: n = normal, b = blargg, s = sonido
SECCIONES = [
 # ============================================================ NES
 ("nes", "Repetir tras las correcciones del 5 de noviembre",
  "PRUEBAS/10 Repetir (y tu SD de fábrica para las comparaciones)", "100.RBF y 101.RBF nuevos",
  "Antes: copia a la microSD los RBF nuevos 100 y 101 (EDFC/MAPS) y la carpeta PRUEBAS/10 Repetir. Los RBF son los optimizados del 5 de noviembre (más pequeños; mismo comportamiento comprobado en el emulador). Los cuatro juegos del final de la lista comprueban justo las partes que cambiaron. Los tres últimos se prueban con tu SD de fábrica de siempre, en el mismo NES: sirven para saber si los sprites negros son de nuestro mapper o del juego/consola (en el emulador salen bien con nuestro mapper). Ojo con las ROMs (Europe)/(PAL): están hechas para consolas PAL y en tu NES y tu Famicom (NTSC) pueden ir rápidas, con basura o colgarse aunque el mapper esté bien.",
  [
   ("Mike Tyson's Punch-Out!! (repetir)", "9 MMC2", "Latch del MMC2 corregido. Caras, poses y público sin tiles cambiados; pelea un par de asaltos.", "", False, "n"),
   ("Fire Emblem Gaiden (repetir)", "10 MMC4", "Latch del MMC4 corregido. Textos, menús y nombres sin letras rotas.", "", False, "n"),
   ("Fire Emblem - Ankoku Ryuu to Hikari no Tsurugi", "10 MMC4", "El juego en el que Krikzz corrigió el MMC4. Textos y mapa sin letras rotas.", "", False, "n"),
   ("Gimmick! (Japan)", "69 FME-7", "La versión normal (la Memorial Series no arranca ni en el emulador). En el NES suena sin la música del 5B: es normal.", "", False, "n"),
   ("High Speed (USA)", "119 TQROM", "La versión de EE. UU. La europea (PAL) falla también en el emulador cuando se le da la velocidad de una consola NTSC como la tuya: título con basura y pantalla negra, justo lo que viste.", "", False, "n"),
   ("Pin Bot (USA)", "119 TQROM", "Igual que High Speed: la europea se cuelga en una consola NTSC (también en el emulador). Prueba esta.", "", False, "n"),
   ("Fantastic Adventures of Dizzy (USA)", "71 Camerica", "Versión NTSC (la que probaste era la europea, PAL, hecha para otra velocidad de consola). ¿Siguen saliendo sprites negros?", "", False, "n"),
   ("Quattro Adventure con la SD de fábrica", "232", "Mismo juego y misma escena donde viste los sprites negros, pero con tu SD de fábrica.", "Si se ve igual (negro) o bien.", False, "n"),
   ("Magic Giral con la SD de fábrica", "0 NROM", "Juega hasta que se quite una prenda, con tu SD de fábrica.", "Si parpadea / se pone negro igual o no.", False, "n"),
   ("Dizzy (Europe) con la SD de fábrica", "71 Camerica", "La versión europea con tu SD de fábrica.", "Si salen los sprites negros igual o no.", False, "n"),
   ("Gradius II (Japan)", "25 VRC4", "Contador de IRQ de los VRC optimizado: los efectos de scroll y la parte fija de abajo como antes (ya iba bien).", "", False, "n"),
   ("Akumajou Densetsu (Japan)", "24 VRC6", "IRQ del VRC6 (barra de estado fija al hacer scroll). En el NES no suena la música del VRC6: es normal.", "", False, "n"),
   ("Lagrange Point (Japan)", "85 VRC7", "IRQ del VRC7. Sin la música FM (no implementada): es normal.", "", False, "n"),
   ("Minelvaton Saga (Japan)", "80 Taito X1-005", "La RAM interna del chip (donde guarda) cambió de sitio en la PRG-RAM. Crea partida, guarda, apaga 10 s y carga.", "Si guarda y recupera la partida.", True, "n"),
  ]),
 ("nes", "Regresión: NROM, MMC1, UxROM, CNROM y AxROM",
  "PRUEBAS/ (raíz), 1 MMC1, 2 UxROM, 3 CNROM, 7 AxROM", "100.RBF",
  "Ya funcionaron en la fase 1. Desde entonces el RBF 100 ha cambiado mucho: basta con arrancar cada uno y jugar un minuto.",
  [
   ("Super Mario Bros.", "0 NROM", "Juega el 1-1 y entra en una tubería (1-2 subterráneo).", "", False, "n"),
   ("Balloon Fight", "0 NROM", "Arranca y juega una fase.", "", False, "n"),
   ("Excitebike", "0 NROM", "Arranca y haz una carrera corta.", "", False, "n"),
   ("Ice Climber", "0 NROM", "Arranca y sube un par de pisos (scroll vertical).", "", False, "n"),
   ("Magic Giral", "0 NROM", "Arranca y juega un minuto.", "", False, "n"),
   ("Castlevania II - Simon's Quest", "1 MMC1", "Entra en la primera ciudad; textos legibles.", "", False, "n"),
   ("Dragon Warrior IV", "1 MMC1 (SUROM)", "Era el fallo gráfico de la fase 1. Crea partida, juega un poco y guarda.", "Si guarda y recupera la partida.", True, "n"),
   ("Final Fantasy", "1 MMC1", "Guarda en una posada.", "Si la partida sigue tras apagar.", True, "n"),
   ("The Legend of Zelda", "1 MMC1", "Crea partida, guarda (Continue/Save) y apaga.", "Si la partida sigue tras apagar.", True, "n"),
   ("Mega Man 2", "1 MMC1", "Elige un jefe y juega el principio del nivel.", "", False, "n"),
   ("Metroid", "1 MMC1", "Pasa por unas salas con scroll vertical y horizontal.", "Basura en los bordes al hacer scroll.", False, "n"),
   ("Castlevania", "2 UxROM", "Juega el primer nivel.", "", False, "n"),
   ("Contra", "2 UxROM", "Juega el primer nivel.", "", False, "n"),
   ("DuckTales", "2 UxROM", "Elige un nivel y juega un poco.", "", False, "n"),
   ("Mega Man", "2 UxROM", "Elige un jefe y juega un poco.", "", False, "n"),
   ("Adventure Island", "3 CNROM", "Juega el 1-1.", "", False, "n"),
   ("Arkanoid", "3 CNROM", "Juega la primera pantalla (sin el mando especial se mueve mal: es normal).", "", False, "n"),
   ("Gradius", "3 CNROM", "Juega el principio del nivel 1.", "", False, "n"),
   ("Solomon's Key", "3 CNROM", "Juega la primera sala.", "", False, "n"),
   ("Battletoads", "7 AxROM", "Juega el nivel 1.", "", False, "n"),
   ("Marble Madness", "7 AxROM", "Juega la primera pista.", "", False, "n"),
   ("R.C. Pro-Am", "7 AxROM", "Haz una carrera.", "", False, "n"),
   ("Wizards & Warriors", "7 AxROM", "Juega el principio del nivel 1.", "", False, "n"),
  ]),
 ("nes", "MMC3 (fase 2)", "PRUEBAS/4 MMC3", "100.RBF",
  "El MMC3 corta la pantalla con su IRQ (barras de estado). Fíjate en que las barras no tiemblen ni salten.",
  [
   ("Super Mario Bros. 3", "4 MMC3", "La barra de abajo no debe saltar. Mira la esquina superior izquierda: antes había un leve parpadeo.", "¿Sigue el parpadeo? ¿Lo ves igual con la SD de fábrica?", False, "n"),
   ("Super Mario Bros. 2", "4 MMC3", "Juega el 1-1.", "", False, "n"),
   ("Kirby's Adventure", "4 MMC3", "Barra de estado de abajo estable. Guarda partida (se guarda sola al pasar de nivel).", "Si la partida sigue tras apagar.", True, "n"),
   ("Mega Man 3", "4 MMC3", "Elige un jefe; barra de energía estable.", "", False, "n"),
   ("Mega Man 4", "4 MMC3 (CHR-RAM)", "Elige un jefe; gráficos correctos (usa CHR-RAM).", "", False, "n"),
   ("Mega Man 5", "4 MMC3", "Elige un jefe y juega un poco.", "", False, "n"),
   ("Ninja Gaiden II", "4 MMC3", "Escenas de introducción y barra superior del nivel 1.", "", False, "n"),
   ("TMNT III: The Manhattan Project", "4 MMC3", "Barra de estado y primer nivel.", "", False, "n"),
   ("Crystalis", "4 MMC3", "Guarda partida (en el menú, con un objeto de guardar o al principio).", "Si la partida sigue tras apagar.", True, "n"),
   ("StarTropics", "4 MMC3 (MMC6)", "Guarda partida.", "Si la partida sigue tras apagar.", True, "n"),
   ("Rad Racer II", "4 MMC3 (4 pantallas)", "Ya funcionó; comprobar que sigue igual (carretera y fondo).", "", False, "n"),
  ]),
 ("nes", "Pruebas automáticas del MMC3 (blargg)", "PRUEBAS/8 Tests MMC3", "100.RBF",
  "Cada ROM escribe el resultado en pantalla en pocos segundos. Anota el texto exacto (Passed o Failed #n).",
  [
   ("1-clocking", "4 MMC3", "Esperado: Passed.", "Texto que sale en pantalla.", False, "b"),
   ("2-details", "4 MMC3", "Esperado: Passed.", "Texto que sale en pantalla.", False, "b"),
   ("3-A12_clocking", "4 MMC3", "Esperado: Passed.", "Texto que sale en pantalla.", False, "b"),
   ("4-scanline_timing", "4 MMC3", "La prueba decisiva: mide el tiempo exacto de la IRQ. En el banco falla; aquí decide si hay que acelerar el filtro de A12.", "Texto exacto (Passed o Failed #n).", False, "b"),
   ("5-MMC3", "4 MMC3", "Esperado: Passed.", "Texto que sale en pantalla.", False, "b"),
   ("6-MMC3_alt", "4 MMC3", "Esperado: Failed #2 (prueba otra revisión del chip; es normal).", "Texto que sale en pantalla.", False, "b"),
  ]),
 ("nes", "Fase 3a: 17 mappers sencillos", "PRUEBAS/5 Fase 3a", "100.RBF",
  "Arranca cada uno y juega un minuto. Lo importante: que arranque y que los gráficos y el scroll estén bien.",
  [
   ("Bible Adventures", "11 Color Dreams", "Elige un juego del menú y juega.", "", False, "n"),
   ("Akira", "33 Taito TC0190", "Arranca; pantallas de texto y gráficos.", "", False, "n"),
   ("Deadly Towers", "34 BNROM", "Juega; cambio de pantallas.", "", False, "n"),
   ("Impossible Mission II", "34 NINA-001", "Arranca y juega.", "", False, "n"),
   ("Dragon Power", "66 GxROM", "Arranca y juega.", "", False, "n"),
   ("Kamen Rider Club", "70 Bandai", "Arranca y juega.", "", False, "n"),
   ("The Fantastic Adventures of Dizzy", "71 Camerica", "Muévete entre pantallas.", "", False, "n"),
   ("Firehawk", "71 Camerica", "Juega el principio (pantalla única).", "", False, "n"),
   ("Double Strike", "79 NINA-03", "Arranca y juega.", "", False, "n"),
   ("Moero!! Pro Yakyuu", "86 Jaleco", "Arranca y juega. La voz (\"Play ball\") no suena: no está implementada.", "", False, "n"),
   ("Goonies (Japan)", "87 Jaleco", "Arranca y juega.", "", False, "n"),
   ("HES 6-Pak", "113 HES", "Elige varios juegos del menú.", "Cuáles fallan, si alguno.", False, "n"),
   ("Bio Senshi Dan", "140 Jaleco", "Arranca y juega.", "", False, "n"),
   ("Galactic Crusader", "146 NINA-06", "Arranca y juega.", "", False, "n"),
   ("Mahjong World", "148 Sachen", "Arranca (los primeros instantes pueden mostrar basura) y juega.", "", False, "n"),
   ("Saint Seiya - Ougon Densetsu", "152 Bandai", "Arranca y juega.", "", False, "n"),
   ("Madoola no Tsubasa", "184 Sunsoft-1", "Arranca y juega.", "", False, "n"),
   ("Fantasy Zone (Tengen)", "206 Namco 108", "Juega el primer nivel.", "", False, "n"),
   ("Gauntlet (Tengen)", "206 Namco 108, 4 pantallas", "Recorre el laberinto en las cuatro direcciones.", "", False, "n"),
   ("Quattro Adventure", "232 Camerica", "Prueba los 4 juegos del menú.", "Cuáles fallan, si alguno.", False, "n"),
  ]),
 ("nes", "Fase 3b: mappers complejos", "PRUEBAS/7 Fase 3b", "100.RBF",
  "Chips con IRQ y bancos finos. Fíjate en las barras de estado, los efectos a media pantalla y las partidas con pila.",
  [
   ("Mike Tyson's Punch-Out!!", "9 MMC2", "REPETIR con el 100.RBF nuevo (latch del MMC2 corregido el 5-nov). Las caras y poses de los boxeadores cambian bien, sin tiles cambiados.", "", False, "n"),
   ("Fire Emblem Gaiden", "10 MMC4", "REPETIR con el 100.RBF nuevo (latch del MMC4 corregido el 5-nov). Textos y menús sin letras rotas; guarda partida.", "Si la partida sigue tras apagar.", True, "n"),
   ("Dragon Ball Z II", "16 Bandai FCG", "Efectos y barra (IRQ). NO guarda partida: su EEPROM no está hecha; es lo esperado.", "", False, "n"),
   ("Goal!!", "18 Jaleco SS88006", "Arranca y juega un partido (IRQ).", "", False, "n"),
   ("Wai Wai World 2", "21 VRC4", "Juega el principio.", "", False, "n"),
   ("Ganbare Pennant Race!", "22 VRC2a", "Arranca y juega.", "", False, "n"),
   ("Contra (Japan)", "23 VRC2b", "Mapa del principio y primer nivel.", "", False, "n"),
   ("Getsu Fuuma Den", "23 VRC2b/VRC4e", "Arranca y juega.", "", False, "n"),
   ("Gradius II", "25 VRC4", "Efectos a media pantalla del nivel 1.", "", False, "n"),
   ("TMNT (Japan)", "25 VRC4", "Arranca y juega.", "", False, "n"),
   ("Dynamite Batman", "69 FME-7", "Juega; barra de estado (IRQ).", "", False, "n"),
   ("Gimmick! (Memorial Series)", "69 FME-7 + 5B", "Esta ROM no arranca ni en el emulador (es la versión modificada del recopilatorio de PS1): no es fallo del mapper. Prueba en su lugar 9c Prueba sonido (Famicom)/Gimmick! (Japan), que también arranca en el NES (sin la música del 5B).", "", False, "n"),
   ("Armadillo", "118 TxSROM", "En la intro, el corte de pantalla debe quedar en su sitio (abajo, no a media pantalla).", "", False, "n"),
   ("Goal! Two", "118 TxSROM", "Arranca y juega un partido.", "", False, "n"),
   ("Family Circuit '91", "210 Namco 175", "Guarda (opciones o datos de carrera).", "Si los datos siguen tras apagar.", True, "n"),
   ("Famista '94", "210 Namco 340", "Arranca y juega.", "", False, "n"),
  ]),
 ("nes", "Fase 3c: variantes en el RBF 100", "PRUEBAS/9a Fase 3c RBF 100", "100.RBF",
  "Variantes de MMC1, UxROM, CNROM, MMC3, Namco 108 y Taito. Dos comprueban algo eléctrico: Mighty Bomb Jack y High Speed.",
  [
   ("Mighty Bomb Jack", "185 CNROM con protección", "IMPORTANTE: tiene que arrancar. Comprueba la CHR apagada leída como $FF (pull-up del bus de la PPU).", "Si arranca o se queda en negro.", False, "n"),
   ("B-Wings", "185 CNROM con protección", "Tiene que arrancar (misma protección).", "", False, "n"),
   ("High Speed", "119 TQROM", "IMPORTANTE: marcador y textos del pinball, que se dibujan en CHR-RAM extra.", "Gráficos del marcador rotos o bien.", False, "n"),
   ("Pin Bot", "119 TQROM", "Tablero y marcador.", "", False, "n"),
   ("The Jetsons", "48 Taito TC0690", "Barra de estado sin temblar.", "", False, "n"),
   ("The Flintstones (Japan)", "48 Taito TC0690", "Barra de estado sin temblar.", "", False, "n"),
   ("Bubble Bobble 2", "48 Taito TC0690", "Arranca y juega.", "", False, "n"),
   ("Super Mario Bros. + Tetris + NWC", "37 MMC3 multijuego", "El menú y los tres juegos.", "Cuáles fallan, si alguno.", False, "n"),
   ("Super Spike V'Ball + NWC", "47 MMC3 multijuego", "Los dos juegos.", "", False, "n"),
   ("Lei Dian II", "115 MMC3 Kasheng", "Arranca y juega.", "", False, "n"),
   ("Thunder Warrior", "189 MMC3 TXC", "Arranca y juega.", "", False, "n"),
   ("Megami Tensei (Digital Devil Story)", "76 Namco 108", "Arranca; mapa y textos.", "", False, "n"),
   ("Dragon Spirit", "88 Namco 108", "Juega el primer nivel.", "", False, "n"),
   ("Dragon Buster", "95 Namco 108", "Arranca y juega (mirroring por registro).", "", False, "n"),
   ("Devil Man", "154 Namco 108", "Arranca; cambios de pantalla correctos.", "", False, "n"),
   ("The Money Game", "155 MMC1A", "Arranca y juega.", "", False, "n"),
   ("Crazy Climber", "180 UNROM", "Arranca (se juega con dos mandos; basta con ver que va).", "", False, "n"),
  ]),
 ("nes", "Fase 3c: chips nuevos en el RBF 101", "PRUEBAS/9b Fase 3c RBF 101", "101.RBF",
  "Primera vez que se usa el RBF 101 en la consola. Si NINGUNO arranca, el problema es el RBF entero: avísame en seguida.",
  [
   ("Shinobi", "64 RAMBO-1", "Primer nivel; barra de estado.", "", False, "n"),
   ("Rolling Thunder", "64 RAMBO-1", "Primer nivel.", "", False, "n"),
   ("Klax", "64 RAMBO-1", "Arranca y juega.", "", False, "n"),
   ("Alien Syndrome", "158 RAMBO-1", "Arranca; mirroring al moverse.", "", False, "n"),
   ("After Burner", "68 Sunsoft-4", "El cielo y el suelo usan nametables de CHR-ROM: tienen que verse bien.", "", False, "n"),
   ("Maharaja", "68 Sunsoft-4", "Guarda partida.", "Si la partida sigue tras apagar.", True, "n"),
   ("Minelvaton Saga", "80 Taito X1-005", "Guarda partida (RAM del chip).", "Si la partida sigue tras apagar.", True, "n"),
   ("Fudou Myouou Den", "207 Taito X1-005", "Arranca; cambios de pantalla.", "", False, "n"),
   ("SD Keiji - Blader", "82 Taito X1-017", "Guarda partida.", "Si la partida sigue tras apagar.", True, "n"),
   ("Image Fight", "32 Irem G-101", "Primer nivel.", "", False, "n"),
   ("Spartan X 2", "65 Irem H3001", "Primer nivel; barra (IRQ).", "", False, "n"),
   ("Holy Diver", "78 Irem", "Haz scroll: el mirroring debe ser correcto (sin basura).", "", False, "n"),
   ("Uchuusen Cosmo Carrier", "78 Jaleco", "Arranca (pantalla única).", "", False, "n"),
   ("Ganbare Goemon!", "75 VRC1", "Primer nivel.", "", False, "n"),
   ("Akumajou Densetsu", "24 VRC6", "Gráficos y juego. En el NES falta la música extra: es normal.", "", False, "n"),
   ("Mouryou Senki Madara", "26 VRC6b", "Arranca y guarda partida.", "Si la partida sigue tras apagar.", True, "n"),
   ("Lagrange Point", "85 VRC7", "Arranca y guarda. No tiene música FM (VRC7 sin sonido todavía).", "Si la partida sigue tras apagar.", True, "n"),
   ("Fantasy Zone II", "67 Sunsoft-3", "Primer nivel (IRQ).", "", False, "n"),
   ("Fantasy Zone (Sunsoft)", "93 Sunsoft-2", "Arranca y juega.", "", False, "n"),
   ("Tenka no Goikenban - Mito Koumon", "89 Sunsoft-2", "Arranca y juega.", "", False, "n"),
   ("Pinball Quest", "72 Jaleco", "Arranca y juega.", "", False, "n"),
   ("Moero!! Pro Soccer", "92 Jaleco", "Arranca y juega.", "", False, "n"),
   ("Super Pang", "141 Sachen 8259A", "Arranca y juega.", "", False, "n"),
   ("Silver Eagle", "138 Sachen 8259B", "En el emulador de referencia sale mal; en el N8 debería verse bien.", "", False, "n"),
   ("Final Combat", "139 Sachen 8259C", "Arranca y juega.", "", False, "n"),
   ("The Great Wall", "137 Sachen 8259D", "Arranca y juega.", "", False, "n"),
   ("Honey Peach", "243 Sachen", "Arranca y juega.", "", False, "n"),
   ("Jovial Race", "133 Sachen", "Arranca y juega.", "", False, "n"),
   ("Huang Di", "112 NTDEC", "Arranca y juega.", "", False, "n"),
   ("War in the Gulf", "193 NTDEC", "Arranca y juega.", "", False, "n"),
   ("Metal Force", "156 Daou", "Arranca y juega.", "", False, "n"),
   ("Caltron 6 in 1", "41 Caltron", "Prueba varios juegos del menú.", "Cuáles fallan, si alguno.", False, "n"),
   ("Cheetahmen II", "228 Action 52", "Arranca y juega.", "", False, "n"),
   ("Xing Ji Zheng Ba", "241", "Arranca y juega.", "", False, "n"),
  ]),
 ("nes", "Fase 3d: la FPGA responde lecturas de la CPU", "PRUEBAS/9d Fase 3d lecturas", "101.RBF y 100.RBF (115)",
  "Primera vez que la FPGA envía datos a la CPU. Si leen un valor equivocado suelen quedarse en negro o reiniciarse (protección). Que arranquen es la prueba.",
  [
   ("Chinese Checkers", "150 Sachen", "Arranca y juega.", "Si arranca o se queda en negro.", False, "n"),
   ("English, Pyramid", "150 Sachen", "Arranca y juega.", "Si arranca o se queda en negro.", False, "n"),
   ("Bingo (TXC)", "132 TXC", "Arranca.", "Si arranca o se queda en negro.", False, "n"),
   ("1991 Du Ma Racing", "132 TXC", "Arranca y juega.", "Si arranca o se queda en negro.", False, "n"),
   ("Mahjong Block (Idea-Tek)", "172 TXC JV001", "Arranca; mirroring correcto.", "Si arranca o se queda en negro.", False, "n"),
   ("F-15 City War (Idea-Tek)", "173 TXC", "Arranca y juega.", "Si arranca o se queda en negro.", False, "n"),
   ("Mahjong Trap", "136 Sachen", "Arranca.", "Si arranca o se queda en negro.", False, "n"),
   ("Challenge of the Dragon", "147 Sachen", "Arranca y juega.", "Si arranca o se queda en negro.", False, "n"),
   ("Strike Wolf", "36 TXC", "Arranca y juega.", "Si arranca o se queda en negro.", False, "n"),
   ("Magical Mathematics", "143 Sachen", "Arranca (lee la protección en $4100).", "Si arranca o se queda en negro.", False, "n"),
   ("Shisen Mahjong 2", "115 Kasheng", "Arranca.", "Si arranca o se queda en negro.", False, "n"),
  ]),
 ("nes", "Namco 163", "PRUEBAS/9e Namco 163", "102.RBF",
  "Primera vez que se usa el RBF 102. Los primeros instantes de algunos juegos pueden mostrar basura: el chip arranca con registros indefinidos.",
  [
   ("Megami Tensei II", "19 Namco 163", "Arranca (usa la CIRAM como CHR) y guarda partida.", "Si la partida sigue tras apagar.", True, "n"),
   ("Final Lap", "19 Namco 163", "Haz una carrera.", "", False, "n"),
   ("Erika to Satoru no Yume Bouken", "19 Namco 163", "Arranca y juega.", "", False, "n"),
   ("Battle Fleet", "19 Namco 163", "Arranca y juega.", "", False, "n"),
   ("Famista '90", "19 Namco 163", "Arranca y juega un partido.", "", False, "n"),
  ]),
 # ============================================================ FAMICOM
 ("famicom", "Prueba de tono", "PRUEBAS/9c Prueba sonido (Famicom)", "100.RBF",
  "Hazla la primera. Comprueba que el audio del cartucho llega a la Famicom AV.",
  [
   ("Tono 1 kHz (mapper 250, Balloon Fight)", "250 prueba", "Encima de la música de Balloon Fight debe sonar un pitido de 1 kHz, medio segundo sí y medio no.", "Se oye / no se oye / zumbido o ruido fuerte (si hay zumbido fuerte, saca el cartucho).", False, "s"),
  ]),
 ("famicom", "Sonido de expansión", "PRUEBAS/9c Prueba sonido (Famicom) y 9e Namco 163", "101, 100 y 102.RBF",
  "Solo si el tono se oye. Escucha la música y anota el volumen de los canales extra frente al sonido normal de la consola.",
  [
   ("Akumajou Densetsu", "24 VRC6", "La música lleva dos pulsos y una sierra extra: suena más llena que Castlevania III de NES.", "Cómo suena y volumen.", False, "s"),
   ("Gimmick!", "69 Sunsoft 5B", "La música usa los tres canales del 5B.", "Cómo suena y volumen.", False, "s"),
   ("Mouryou Senki Madara", "26 VRC6b", "Música VRC6 (puede tardar en aparecer: avanza un poco).", "Cómo suena y volumen.", False, "s"),
   ("Esper Dream 2", "26 VRC6b", "Música VRC6 (avanza un poco en el juego).", "Cómo suena y volumen.", False, "s"),
   ("Final Lap", "19 Namco 163", "Música del N163.", "Cómo suena y volumen.", False, "s"),
   ("Erika to Satoru no Yume Bouken", "19 Namco 163", "Música del N163.", "Cómo suena y volumen.", False, "s"),
   ("Megami Tensei II", "19 Namco 163", "Música del N163.", "Cómo suena y volumen.", False, "s"),
   ("Lagrange Point", "85 VRC7", "Sin música FM todavía: comprueba solo que no salga ruido raro.", "", False, "s"),
  ]),
 ("famicom", "Lecturas sin transceptores", "PRUEBAS/9d Fase 3d lecturas", "101.RBF y 100.RBF (115)",
  "La placa de Famicom no tiene transceptores: la FPGA llega al bus de la consola por 100 ohmios. Repite las lecturas aquí.",
  [
   ("Chinese Checkers", "150 Sachen", "Arranca y juega.", "Si arranca o se queda en negro.", False, "n"),
   ("English, Pyramid", "150 Sachen", "Arranca y juega.", "Si arranca o se queda en negro.", False, "n"),
   ("Bingo (TXC)", "132 TXC", "Arranca.", "Si arranca o se queda en negro.", False, "n"),
   ("1991 Du Ma Racing", "132 TXC", "Arranca y juega.", "Si arranca o se queda en negro.", False, "n"),
   ("Mahjong Block (Idea-Tek)", "172 TXC JV001", "Arranca.", "Si arranca o se queda en negro.", False, "n"),
   ("F-15 City War (Idea-Tek)", "173 TXC", "Arranca y juega.", "Si arranca o se queda en negro.", False, "n"),
   ("Mahjong Trap", "136 Sachen", "Arranca.", "Si arranca o se queda en negro.", False, "n"),
   ("Challenge of the Dragon", "147 Sachen", "Arranca y juega.", "Si arranca o se queda en negro.", False, "n"),
   ("Strike Wolf", "36 TXC", "Arranca y juega.", "Si arranca o se queda en negro.", False, "n"),
   ("Magical Mathematics", "143 Sachen", "Arranca.", "Si arranca o se queda en negro.", False, "n"),
   ("Shisen Mahjong 2", "115 Kasheng", "Arranca.", "Si arranca o se queda en negro.", False, "n"),
  ]),
 ("famicom", "Comprobación general en la placa de Famicom", "varias carpetas", "100, 101 y 102.RBF",
  "Confirma que los RBF funcionan igual en esta placa, sobre todo lo que depende de la electrónica.",
  [
   ("Super Mario Bros.", "0 NROM (raíz)", "Juega el 1-1.", "", False, "n"),
   ("The Legend of Zelda", "1 MMC1 (1 MMC1)", "Guarda y recupera (pila de esta placa).", "Si la partida sigue tras apagar.", True, "n"),
   ("Super Mario Bros. 3", "4 MMC3 (4 MMC3)", "Barra de estado sin saltos; mira también el parpadeo de arriba a la izquierda.", "", False, "n"),
   ("Rad Racer II", "4 MMC3, 4 pantallas", "Carretera y fondo correctos.", "", False, "n"),
   ("Mega Man 4", "4 MMC3 CHR-RAM", "Elige un jefe; gráficos correctos.", "", False, "n"),
   ("Armadillo", "118 TxSROM (7 Fase 3b)", "Corte de pantalla de la intro en su sitio.", "", False, "n"),
   ("Mighty Bomb Jack", "185 (9a)", "Tiene que arrancar: aquí el pull-up de la PPU llega a la consola sin transceptor.", "Si arranca o se queda en negro.", False, "n"),
   ("High Speed", "119 TQROM (9a)", "Marcador del pinball correcto.", "", False, "n"),
   ("Shinobi", "64 RAMBO-1 (9b)", "Primer nivel (RBF 101).", "", False, "n"),
   ("Battle Fleet", "19 Namco 163 (9e)", "Arranca (RBF 102).", "", False, "n"),
  ]),
]

items = []
secciones = []
for consola, titulo, carpeta, rbf, intro, juegos in SECCIONES:
    sid = f"{consola}-{slug(titulo)}"
    lst = []
    for (n, m, mirar, anota, pila, tipo) in juegos:
        gid = f"{consola}-{slug(carpeta.split(',')[0])}-{slug(n)}"[:120]
        gid = re.sub(r'-+', '-', gid)
        assert gid not in [i['id'] for i in items], gid
        it = {"id": gid, "n": n, "m": m, "mirar": mirar, "anota": anota, "pila": pila, "tipo": tipo}
        items.append(it); lst.append(it)
    secciones.append({"id": sid, "consola": consola, "titulo": titulo, "carpeta": carpeta, "rbf": rbf, "intro": intro, "juegos": lst})

print(len(items), 'juegos;', sum(1 for i in items if i['id'].startswith('nes')), 'NES,', sum(1 for i in items if i['id'].startswith('famicom')), 'Famicom', file=sys.stderr)

out_dir = pathlib.Path(sys.argv[1])
(out_dir / 'plan.json').write_text(json.dumps(secciones, ensure_ascii=False))

# ---------------- Markdown para el repositorio
md = ["# Plan de pruebas en consola (N8 de NES y N8 de Famicom)", "",
      "Generado el 2026-11-05. La versión interactiva (con resultados que Claude puede leer) es la página",
      "\"Pruebas N8\" publicada en claude.ai. Aquí, la misma lista en texto.", "",
      "**Cómo probar:** arranca cada juego y juega uno o dos minutos. Marca OK si todo va como debe. Si falla,",
      "anota qué ves (pantalla negra o gris, gráficos rotos, parpadeo, se reinicia, se cuelga), en qué momento",
      "y si se repite. **Partidas con pila:** guarda, apaga la consola 10 segundos, enciende, vuelve a cargar el",
      "juego desde el menú del N8 y comprueba la partida.", ""]
for con, nombre in (("nes", "NES (N8 de NES)"), ("famicom", "Famicom AV (N8 de Famicom)")):
    md.append(f"## {nombre}"); md.append("")
    for s in secciones:
        if s["consola"] != con: continue
        md.append(f"### {s['titulo']}"); md.append(f"Carpeta: `{s['carpeta']}` · RBF: {s['rbf']}"); md.append("")
        md.append(s["intro"]); md.append("")
        md.append("| Juego | Mapper | Qué mirar | Qué anotar |"); md.append("|---|---|---|---|")
        for j in s["juegos"]:
            anota = j["anota"] or "OK o qué falla"
            if j["pila"]: anota += " (pila)"
            md.append(f"| {j['n']} | {j['m']} | {j['mirar']} | {anota} |")
        md.append("")
pathlib.Path(sys.argv[2]).write_text("\n".join(md) + "\n")
