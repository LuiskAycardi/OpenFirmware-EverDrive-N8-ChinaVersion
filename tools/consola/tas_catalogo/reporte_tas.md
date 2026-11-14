# TASVideos: revisión completa de las ROMs seleccionadas

Fecha de consulta: **14 de noviembre de 2026**. Revisión documental y de archivos; **sin validación de sincronización en Mesen2 ni en la NES**. Las dos reproducciones que se habían iniciado se detuvieron por instrucción del usuario y no se usan como evidencia.

Se cruzaron **204 ROMs** con **2062 publicaciones NES** (actuales e históricas). Se descargaron y revisaron las cabeceras de **las 809 películas FM2 del catálogo completo**, por checksum, sin depender del nombre del juego. Las entradas de las películas coincidentes se inspeccionaron para detectar requisitos que el banco no reproduce.

Fuentes: [API oficial](https://tasvideos.org/api), [catálogo NES de TASVideos](https://tasvideos.org/movies-nes). Los metadatos consultados, los ZIP originales y las películas coincidentes se conservan en esta carpeta. Las publicaciones se enlazan individualmente en las tablas.

## Resultado

- **14 ROMs** tienen al menos una FM2 con checksum exacto y entradas admitidas por el banco.
- **2** de ellas tienen una película marcada como verificada en consola por TASVideos.
- **3 ROMs** tienen FM2 con checksum exacto, pero requieren entradas/periféricos no admitidos.
- **3 ROMs adicionales** coinciden por hash con una versión de ROM del catálogo que tiene publicaciones en otro formato. Son candidatas a adaptar; no son ejecutables con el lector actual.

## Criterios aplicados

Se compara el MD5 de la ROM sin cabecera iNES con `romChecksum` de la FM2, tal como hace `tools/consola/tas.py`. La película debe ser NTSC, partir sin savestate/SRAM precargada, usar mando NES estándar en el primer puerto y no depender de Four Score, micrófono, segundo mando, periféricos adicionales o resets intermedios. Solo se admite la orden de encendido inicial; el banco actual no ejecuta los otros comandos de la película.

La verificación en consola corresponde a la película publicada y a la configuración usada por sus verificadores, no a nuestra NES/N8. El checksum exacto y el formato compatible no prueban sincronización con Mesen2 ni con el arranque desde el menú N8. El desplazamiento de entrada y el estado inicial siguen pendientes de validar.

Se incluyen películas sustituidas por otras más nuevas cuando son las que coinciden con nuestra ROM y formato. La columna «Histórica» identifica esos casos. Para elegir una película se prioriza verificación en consola, luego publicación vigente y después menor duración.

## FM2 con checksum exacto y entradas admitidas

| Mapper | ROM exacta | TAS recomendado | Duración | Verificado en consola por TASVideos | Histórica |
| --- | --- | --- | --- | --- | --- |
| 1 | Advanced Dungeons & Dragons - Heroes of the Lance (USA).nes | [4147](https://tasvideos.org/4147M) | 5:53 | No consta | Sí |
| 1 | Abadox - The Deadly Inner War (USA).nes | [2194](https://tasvideos.org/2194M) | 15:30 | Sí | No |
| 2 | Amagon (USA).nes | [1924](https://tasvideos.org/1924M) | 18:02 | No consta | No |
| 9 | Mike Tyson's Punch-Out!! (Japan, USA) (En) (Rev 1).nes | [1695](https://tasvideos.org/1695M) | 17:48 | No consta | Sí |
| 24 | Akumajou Densetsu (Japan).nes | [3357](https://tasvideos.org/3357M) | 24:48 | No consta | Sí |
| 65 | Spartan X 2 (Japan).nes | [2461](https://tasvideos.org/2461M) | 6:13 | No consta | No |
| 69 | Gimmick! (Japan).nes | [6243](https://tasvideos.org/6243M) | 4:12 | Sí | Sí |
| 75 | King Kong 2 - Ikari no Megaton Punch (Japan).nes | [4255](https://tasvideos.org/4255M) | 2:55 | No consta | No |
| 87 | Goonies (Japan).nes | [3302](https://tasvideos.org/3302M) | 2:28 | No consta | No |
| 141 | Q Boy (Asia) (En) (Unl).nes | [3166](https://tasvideos.org/3166M) | 30:42 | No consta | Sí |
| 184 | Atlantis no Nazo (Japan).nes | [1603](https://tasvideos.org/1603M) | 2:23 | No consta | Sí |
| 206 | Lupin Sansei - Pandora no Isan (Japan).nes | [3097](https://tasvideos.org/3097M) | 10:23 | No consta | No |
| 210 | Splatterhouse - Wanpaku Graffiti (Japan).nes | [2915](https://tasvideos.org/2915M) | 19:11 | No consta | No |
| 228 | Cheetahmen II (USA) (Unl).nes | [2156](https://tasvideos.org/2156M) | 2:20 | No consta | Sí |

## Coincidencia exacta de ROM, pero entradas no admitidas

| Mapper | ROM | Publicaciones FM2 | Motivo |
| --- | --- | --- | --- |
| 11 | Wally Bear and the No! Gang (USA) (Unl).nes | [2831](https://tasvideos.org/2831M) | Usa botones del segundo mando |
| 66 | Gumshoe (USA, Europe).nes | [2189](https://tasvideos.org/2189M) | Periférico adicional no admitido; Usa botones del segundo mando |
| 232 | Quattro Adventure (USA) (Unl).nes | [2755](https://tasvideos.org/2755M), [2758](https://tasvideos.org/2758M) | Reset/órdenes durante la película no reproducidos por el banco |

## Coincidencia de hash en catálogo, pero formato pendiente de adaptación

La coincidencia de MD5/SHA1 es con la versión de ROM registrada en TASVideos. No se ha convertido ni comprobado el flujo de entradas BK2/BKM.

| Mapper | ROM | Publicaciones | Formatos |
| --- | --- | --- | --- |
| 19 | Pac-Man - Championship Edition (USA, Europe) (Namco Museum Archives Vol 1).nes | [6687](https://tasvideos.org/6687M), [7061](https://tasvideos.org/7061M), [7064](https://tasvideos.org/7064M), [7191](https://tasvideos.org/7191M), [7192](https://tasvideos.org/7192M) | bk2 |
| 33 | Power Blazer (Japan).nes | [7346](https://tasvideos.org/7346M) | bk2 |
| 105 | Nintendo World Championships 1990 (USA) (Competition Cart).nes | [6742](https://tasvideos.org/6742M) | bk2 |

## Lista completa de las 204 ROMs

«Sin coincidencia FM2» significa que ninguna de las 809 películas FM2 publicadas consultadas declara el checksum de nuestra ROM. No significa que no pueda existir un TAS en envíos, userfiles, otras webs o formatos diferentes. Las coincidencias por título son orientativas y no sustituyen el checksum.

| Mapper | ROM seleccionada | Resultado para el banco actual | Publicaciones con checksum exacto | Publicaciones relacionadas por título |
| --- | --- | --- | --- | --- |
| 1 | Advanced Dungeons & Dragons - Heroes of the Lance (USA).nes | FM2 candidata; sincronización pendiente | [4147](https://tasvideos.org/4147M) | [2181](https://tasvideos.org/2181M), [4147](https://tasvideos.org/4147M), [4196](https://tasvideos.org/4196M), [4252](https://tasvideos.org/4252M) |
| 1 | Abadox - The Deadly Inner War (USA).nes | FM2 candidata; sincronización pendiente | [2194](https://tasvideos.org/2194M) | [2194](https://tasvideos.org/2194M) |
| 1 | Battle Chess (USA).nes | Sin coincidencia FM2 con esta ROM | — | [4987](https://tasvideos.org/4987M), [5158](https://tasvideos.org/5158M) |
| 2 | Amagon (USA).nes | FM2 candidata; sincronización pendiente | [1924](https://tasvideos.org/1924M) | [710](https://tasvideos.org/710M), [1924](https://tasvideos.org/1924M) |
| 3 | Adventure Island (USA).nes | Sin coincidencia FM2 con esta ROM | — | [560](https://tasvideos.org/560M), [3667](https://tasvideos.org/3667M) |
| 4 | Cyber Stadium Series - Base Wars (USA).nes | Sin coincidencia FM2 con esta ROM | — | [4642](https://tasvideos.org/4642M) |
| 5 | Aoki Ookami to Shiroki Mejika - Genchou Hishi (Japan).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 5 | Laser Invasion (USA).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 7 | Beetlejuice (USA).nes | Sin coincidencia FM2 con esta ROM | — | [3280](https://tasvideos.org/3280M), [3729](https://tasvideos.org/3729M), [3737](https://tasvideos.org/3737M), [3987](https://tasvideos.org/3987M), [5272](https://tasvideos.org/5272M), [6690](https://tasvideos.org/6690M), [6863](https://tasvideos.org/6863M) |
| 9 | Mike Tyson's Punch-Out!! (Japan, USA) (En) (Rev 1).nes | FM2 candidata; sincronización pendiente | [1695](https://tasvideos.org/1695M) | [59](https://tasvideos.org/59M), [215](https://tasvideos.org/215M), [229](https://tasvideos.org/229M), [408](https://tasvideos.org/408M), [544](https://tasvideos.org/544M), [627](https://tasvideos.org/627M), [630](https://tasvideos.org/630M), [766](https://tasvideos.org/766M), [1695](https://tasvideos.org/1695M), [2488](https://tasvideos.org/2488M), [4226](https://tasvideos.org/4226M), [6662](https://tasvideos.org/6662M), [6931](https://tasvideos.org/6931M) |
| 10 | Famicom Wars (Japan).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 11 | Bible Adventures (USA) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | [3230](https://tasvideos.org/3230M) |
| 11 | Wally Bear and the No! Gang (USA) (Unl).nes | FM2 exacta; requiere adaptar entradas/periféricos | [2831](https://tasvideos.org/2831M) | [2831](https://tasvideos.org/2831M), [4512](https://tasvideos.org/4512M) |
| 12 | Dragon Ball Z 5 (Asia) (En,Zh) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 13 | Videomation (USA).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 16 | Dragon Ball Z Gaiden - Saiya Jin Zetsumetsu Keikaku (Japan).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 16 | Akuma-kun - Makai no Wana (Japan).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 18 | Jajamaru Gekimaden - Maboroshi no Kinmajou (Japan).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 18 | Moe Pro! '90 - Kandou Hen (Japan).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 19 | Pac-Man - Championship Edition (USA, Europe) (Namco Museum Archives Vol 1).nes | ROM exacta en catálogo; requiere otro formato | [6687](https://tasvideos.org/6687M), [7061](https://tasvideos.org/7061M), [7064](https://tasvideos.org/7064M), [7191](https://tasvideos.org/7191M), [7192](https://tasvideos.org/7192M) | [6687](https://tasvideos.org/6687M), [7061](https://tasvideos.org/7061M), [7064](https://tasvideos.org/7064M), [7191](https://tasvideos.org/7191M), [7192](https://tasvideos.org/7192M) |
| 19 | Namco Classic (Japan).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 19 | Rolling Thunder (Japan).nes | Sin coincidencia FM2 con esta ROM | — | [373](https://tasvideos.org/373M), [1494](https://tasvideos.org/1494M) |
| 21 | Ganbare Goemon Gaiden 2 - Tenka no Zaihou (Japan).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 22 | Ganbare Pennant Race! (Japan).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 23 | Crisis Force (Japan).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 24 | Akumajou Densetsu (Japan).nes | FM2 candidata; sincronización pendiente | [1979](https://tasvideos.org/1979M), [3357](https://tasvideos.org/3357M), [3360](https://tasvideos.org/3360M) | [57](https://tasvideos.org/57M), [58](https://tasvideos.org/58M), [580](https://tasvideos.org/580M), [714](https://tasvideos.org/714M), [762](https://tasvideos.org/762M), [763](https://tasvideos.org/763M), [764](https://tasvideos.org/764M), [1979](https://tasvideos.org/1979M), [2753](https://tasvideos.org/2753M), [3224](https://tasvideos.org/3224M), [3357](https://tasvideos.org/3357M), [3360](https://tasvideos.org/3360M), [4218](https://tasvideos.org/4218M), [4895](https://tasvideos.org/4895M), [6930](https://tasvideos.org/6930M), [6942](https://tasvideos.org/6942M), [6974](https://tasvideos.org/6974M), [7006](https://tasvideos.org/7006M) |
| 25 | Gradius II (Japan) (En).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 25 | Teenage Mutant Ninja Turtles 2 - The Manhattan Project (Japan).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 26 | Mouryou Senki Madara (Japan).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 26 | Esper Dream 2 - Aratanaru Tatakai (Japan).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 27 | Mi Hun Che (Asia) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 28 | Action 53 Vol. 3 - Revenge of the Twins (World) (v1.5) (Disk 1) (Aftermarket) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 28 | Minekart Madness (World) (Aftermarket) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 30 | Mega Man 2 (USA) (iam8bit).nes | Sin coincidencia FM2 con esta ROM | — | [6](https://tasvideos.org/6M), [306](https://tasvideos.org/306M), [588](https://tasvideos.org/588M), [741](https://tasvideos.org/741M), [1242](https://tasvideos.org/1242M), [1346](https://tasvideos.org/1346M), [1649](https://tasvideos.org/1649M), [4006](https://tasvideos.org/4006M), [4057](https://tasvideos.org/4057M), [4410](https://tasvideos.org/4410M) |
| 31 | Famicompo Pico (World) (Aftermarket) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 32 | Ai Sensei no Oshiete - Watashi no Hoshi (Japan).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 32 | ImageFight (Japan).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 33 | Bakushou!! Jinsei Gekijou 2 (Japan).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 33 | Power Blazer (Japan).nes | ROM exacta en catálogo; requiere otro formato | [7346](https://tasvideos.org/7346M) | [7346](https://tasvideos.org/7346M) |
| 34 | Impossible Mission II (USA) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 34 | Deadly Towers (USA).nes | Sin coincidencia FM2 con esta ROM | — | [117](https://tasvideos.org/117M), [503](https://tasvideos.org/503M), [2655](https://tasvideos.org/2655M) |
| 35 | Wario Land 2 (Asia) (Ja) (JY039) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 36 | Policeman (Spain) (En) (Micro Genius) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 36 | Strike Wolf (Asia) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 38 | Crime Busters (Brazil) (En) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 40 | Super Mario Bros. 4 (Asia) (En) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 41 | Caltron - 6 in 1 (USA) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 42 | Ai Senshi Nicol (Asia) (Ja) (v1.0) (Kaiser) (KS-7050) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 42 | Green Beret (Asia) (En) (Kaiser) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 45 | Super 4-in-1 (Asia) (Ja) (K4022) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 45 | 7-in-1 Famicom Yarou Vol. 2 (Japan) (En) (Aftermarket) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 45 | Super 4-in-1 (Asia) (En,Ja) (K4033) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 47 | Super Spike V'Ball + Nintendo World Cup (USA).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 48 | Flintstones, The - The Rescue of Dino & Hoppy (Japan).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 50 | Super Mario Bros. 2 (Asia) (En) (761214 PCB) (N-32) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | [10](https://tasvideos.org/10M), [99](https://tasvideos.org/99M), [234](https://tasvideos.org/234M), [309](https://tasvideos.org/309M), [390](https://tasvideos.org/390M), [400](https://tasvideos.org/400M), [494](https://tasvideos.org/494M), [510](https://tasvideos.org/510M), [637](https://tasvideos.org/637M), [651](https://tasvideos.org/651M), [653](https://tasvideos.org/653M), [676](https://tasvideos.org/676M), [677](https://tasvideos.org/677M), [678](https://tasvideos.org/678M), [679](https://tasvideos.org/679M), [960](https://tasvideos.org/960M), [976](https://tasvideos.org/976M), [1001](https://tasvideos.org/1001M), [1002](https://tasvideos.org/1002M), [1724](https://tasvideos.org/1724M), [1746](https://tasvideos.org/1746M), [3446](https://tasvideos.org/3446M), [3640](https://tasvideos.org/3640M), [6366](https://tasvideos.org/6366M), [7280](https://tasvideos.org/7280M) |
| 56 | Super Mario Bros. 3 (Asia) (En) (Kaiser) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | [14](https://tasvideos.org/14M), [15](https://tasvideos.org/15M), [342](https://tasvideos.org/342M), [455](https://tasvideos.org/455M), [667](https://tasvideos.org/667M), [668](https://tasvideos.org/668M), [1053](https://tasvideos.org/1053M), [1059](https://tasvideos.org/1059M), [1286](https://tasvideos.org/1286M), [1558](https://tasvideos.org/1558M), [1590](https://tasvideos.org/1590M), [2588](https://tasvideos.org/2588M), [2835](https://tasvideos.org/2835M), [3028](https://tasvideos.org/3028M), [3050](https://tasvideos.org/3050M), [3812](https://tasvideos.org/3812M), [3922](https://tasvideos.org/3922M), [4032](https://tasvideos.org/4032M), [4554](https://tasvideos.org/4554M), [4567](https://tasvideos.org/4567M), [6892](https://tasvideos.org/6892M) |
| 57 | 52-in-1 (Asia) (En) (VT302) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 58 | Super Game 4-in-1 (Asia) (En) (FK-8004) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 59 | 62-in-1 Hi Game 2000 (Asia) (Ja) (PS5027) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 60 | Pinball & Baseball (Asia) (En) (Aftermarket) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 60 | 4-in-1 (SN 406) (Asia) (En) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 64 | Skull & Crossbones (USA) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 64 | Klax (USA) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 65 | Spartan X 2 (Japan).nes | FM2 candidata; sincronización pendiente | [2461](https://tasvideos.org/2461M) | [2461](https://tasvideos.org/2461M) |
| 66 | Gumshoe (USA, Europe).nes | FM2 exacta; requiere adaptar entradas/periféricos | [2189](https://tasvideos.org/2189M) | [2189](https://tasvideos.org/2189M) |
| 67 | Fantasy Zone II - Opa-Opa no Namida (Japan).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 68 | After Burner (Japan).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 68 | Nantettatte!! Baseball (Japan).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 69 | Gimmick! (Japan).nes | FM2 candidata; sincronización pendiente | [3168](https://tasvideos.org/3168M), [6243](https://tasvideos.org/6243M) | [110](https://tasvideos.org/110M), [414](https://tasvideos.org/414M), [439](https://tasvideos.org/439M), [579](https://tasvideos.org/579M), [1052](https://tasvideos.org/1052M), [1284](https://tasvideos.org/1284M), [1543](https://tasvideos.org/1543M), [1546](https://tasvideos.org/1546M), [3168](https://tasvideos.org/3168M), [6243](https://tasvideos.org/6243M), [7070](https://tasvideos.org/7070M) |
| 69 | Honoo no Toukyuuji - Dodge Danpei 2 (Japan).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 70 | Family Trainer 5 - Meiro Daisakusen (Japan).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 71 | Firehawk (Europe) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 72 | Moero!! Juudou Warriors (Japan).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 73 | Salamander (Japan).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 74 | Zhong Zhuang Ji Bing (China) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 75 | King Kong 2 - Ikari no Megaton Punch (Japan).nes | FM2 candidata; sincronización pendiente | [4255](https://tasvideos.org/4255M) | [721](https://tasvideos.org/721M), [2420](https://tasvideos.org/2420M), [4255](https://tasvideos.org/4255M) |
| 76 | Digital Devil Story - Megami Tensei (Japan).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 77 | Napoleon Senki (Japan).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 78 | Uchuusen Cosmo Carrier (Japan).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 79 | Silent Assault (Asia) (En) (72 pin cart) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | [2717](https://tasvideos.org/2717M) |
| 80 | Kyonshiizu 2 (Japan).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 82 | SD Keiji - Blader (Japan).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 83 | Super Blaster VII - Turbo 28 (Asia) (En) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 83 | Fatal Fury 2 (Asia) (En,Zh) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 85 | Lagrange Point (Japan).nes | Sin coincidencia FM2 con esta ROM | — | [1605](https://tasvideos.org/1605M) |
| 85 | Tiny Toon Adventures 2 - Montana Land e Youkoso (Japan).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 86 | Moero!! Pro Yakyuu (Japan) (Rev 1).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 87 | Goonies (Japan).nes | FM2 candidata; sincronización pendiente | [1373](https://tasvideos.org/1373M), [3302](https://tasvideos.org/3302M), [6133](https://tasvideos.org/6133M) | [83](https://tasvideos.org/83M), [609](https://tasvideos.org/609M), [1032](https://tasvideos.org/1032M), [1051](https://tasvideos.org/1051M), [1373](https://tasvideos.org/1373M), [3302](https://tasvideos.org/3302M), [6133](https://tasvideos.org/6133M) |
| 88 | Quinty (Japan).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 89 | Tenka no Goikenban - Mito Koumon (Japan).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 90 | Final Fight 3 (Asia) (En) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 90 | Super Mario & Sonic 2 (Asia) (Ja) (v1.1) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 90 | Super Mortal Kombat 2-in-1 (Asia) (En) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 90 | Mortal Kombat II Turbo (Asia) (En) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 91 | Super Fighter III (Asia) (En) (SuperVision) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 92 | Moero!! Pro Soccer (Japan).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 93 | Fantasy Zone (Japan) (Sunsoft).nes | Sin coincidencia FM2 con esta ROM | — | [743](https://tasvideos.org/743M), [4122](https://tasvideos.org/4122M) |
| 94 | Senjou no Ookami (Japan).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 95 | Dragon Buster (Japan).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 96 | Oeka Kids - Anpanman no Hiragana Daisuki (Japan).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 97 | Kaiketsu Yanchamaru (Japan).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 103 | Yume Koujou - Doki Doki Panic (Asia) (Ja) (Whirlwind Manu) (LH30) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 105 | Nintendo World Championships 1990 (USA) (Competition Cart).nes | ROM exacta en catálogo; requiere otro formato | [6742](https://tasvideos.org/6742M) | [6742](https://tasvideos.org/6742M) |
| 107 | Magic Dragon (Asia) (En) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 108 | Bubble Bobble (Asia) (En) (v1.0) (Whirlwind Manu) (LH31) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | [64](https://tasvideos.org/64M), [622](https://tasvideos.org/622M), [1449](https://tasvideos.org/1449M) |
| 111 | Anguna - Scourge of the Goblin King (USA) (Beta) (Aftermarket) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 112 | Fighting Hero III (Asia) (Ja) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 112 | Cobra Mission (Asia) (Ja) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 113 | Mindblower Pak (Australia) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 114 | Super Lion King (Asia) (En) (v1.0) (Super Game) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | [6636](https://tasvideos.org/6636M) |
| 114 | Pocahontas (Asia) (En) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 115 | Bao Qingtian (Asia) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 115 | AV Kyuukyoku Mahjong 2 (Asia) (Ja) (Ka Sheng) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 116 | AV Mei Shaonu Zhanshi (Asia) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 116 | AV Kyuukyoku Mahjong 2 (Asia) (Ja) (Ge De) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 117 | Labi Xiao Xin (Asia) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 118 | Ys III - Wanderers from Ys (Japan).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 118 | NES Play Action Football (USA).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 119 | High Speed (USA).nes | Sin coincidencia FM2 con esta ROM | — | [1228](https://tasvideos.org/1228M) |
| 121 | Ultimate Mortal Kombat 3 (Asia) (En) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 121 | Street Fighter Zero 2 '97 (Asia) (En) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 121 | Ultimate Mortal Kombat 4 (Asia) (En) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 121 | Panda Prince, The (Asia) (En) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 132 | Creatom (Spain) (En) (Micro Genius) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 133 | Jovial Race (Asia) (En) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 134 | 7-in-1 (Asia) (YH-708) (Aftermarket) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 134 | 6800000-in-1 (Asia) (En) (BS-5652) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 136 | Weilai Xiaozi - Joy Van Kid (Asia) (En) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 138 | Silver Eagle (Asia) (En) (72 pin cart) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 139 | Hell Fighter (Asia) (En) (72 pin cart) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 140 | Bio Senshi Dan - Increaser Tono Tatakai (Japan).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 141 | Popo Team (Asia) (En) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 141 | Q Boy (Asia) (En) (Unl).nes | FM2 candidata; sincronización pendiente | [3166](https://tasvideos.org/3166M) | [3166](https://tasvideos.org/3166M), [4713](https://tasvideos.org/4713M) |
| 142 | 1988 Jinpai Mali (Asia) (En) (Kaiser) (KS-7032) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 143 | Dancing Blocks (Asia) (Ja) (PAL) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 144 | Death Race (USA) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 145 | Sidewinder (Asia) (En) (72 pin cart) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 147 | Challenge of the Dragon (Asia) (En) (Sachen) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 148 | Bubble Bath Babes (USA) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 149 | Taiwan 16 Maque (Asia) (v1.0) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 150 | Olympic I.Q. (Asia) (Ja) (PAL) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 150 | Chess Academy (Asia) (Ja) (NTSC) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 150 | Lightgun Game 2 in 1 - Cosmocop + Cyber Monster (Asia) (Ja) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 152 | Arkanoid II (Japan) (En).nes | Sin coincidencia FM2 con esta ROM | — | [6372](https://tasvideos.org/6372M) |
| 153 | Famicom Jump II - Saikyou no 7 Nin (Japan).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 154 | Devil Man (Japan).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 155 | Money Game, The (Japan).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 155 | Tatakae!! Rahmen Man - Sakuretsu Choujin 102 Gei (Japan).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 156 | Janggun-ui Adeul (Korea) (En) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 156 | Koko Adventure (Korea) (En) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 157 | Battle Rush - Build Up Robot Tournament (Japan) (Datach).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 157 | SD Gundam - Gundam Wars (Japan) (Datach).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 158 | Alien Syndrome (USA) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 159 | Dragon Ball Z - Kyoushuu! Saiya Jin (Japan) (Rev 1).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 168 | Racermate Challenge II (USA) (v3.11.088) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 171 | Tuidaohu Mahjong (Asia) (Kaiser) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 172 | Venice Beach Volleyball (Asia) (En) (Super Mega) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | [5150](https://tasvideos.org/5150M) |
| 173 | F-15 City War (Asia) (En) (Idea-Tek) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 176 | Guimei Zhan Ji (China) (Aftermarket) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 176 | Super 9999999-in-1 (Asia) (En) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 176 | Sangokushi II - Haou no Tairiku (China) (Ja) (Waixing) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 178 | Pingpong (Asia) (En) (Aftermarket) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 180 | Crazy Climber (Japan).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 183 | Shuiguan Pipe (Asia) (En) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 184 | Atlantis no Nazo (Japan).nes | FM2 candidata; sincronización pendiente | [1603](https://tasvideos.org/1603M), [1837](https://tasvideos.org/1837M), [2840](https://tasvideos.org/2840M) | [21](https://tasvideos.org/21M), [410](https://tasvideos.org/410M), [461](https://tasvideos.org/461M), [1603](https://tasvideos.org/1603M), [1837](https://tasvideos.org/1837M), [2840](https://tasvideos.org/2840M) |
| 185 | Mighty Bomb Jack (Japan) (Rev 1).nes | Sin coincidencia FM2 con esta ROM | — | [926](https://tasvideos.org/926M), [5452](https://tasvideos.org/5452M), [5525](https://tasvideos.org/5525M), [5847](https://tasvideos.org/5847M), [6300](https://tasvideos.org/6300M), [6444](https://tasvideos.org/6444M), [6471](https://tasvideos.org/6471M), [6472](https://tasvideos.org/6472M) |
| 187 | King of Fighters 96, The (Asia) (En) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 188 | Karaoke Studio Senyou Cassette - Top Hit 20 Vol. 1 (Japan).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 189 | Gluk the Thunder Warrior (Spain) (En) (Micro Genius) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 190 | Magic Kid Googoo (Korea) (En) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 191 | Du Shen - Zhi Shai Zhanshi (China) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 193 | Fighting Hero (Asia) (En) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 194 | Touhou Rououmu (World) (Ja) (v1.00) (Beta 1) (Aftermarket) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 196 | Mali Boss (Asia) (Ja) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 196 | Mali & Lugi Fighting 2 (Asia) (Ja) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 197 | Mortal Kombat III - 28 People (Asia) (En) (NT-328) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 197 | Fighter V (Asia) (En) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 206 | Lupin Sansei - Pandora no Isan (Japan).nes | FM2 candidata; sincronización pendiente | [3097](https://tasvideos.org/3097M) | [3097](https://tasvideos.org/3097M) |
| 207 | Fudou Myouou Den (Japan).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 209 | Mighty Morphin - Power Rangers III (Asia) (En) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 209 | Shin Samurai Spirits 2 - Haoumaru Jigoku Hen (Asia) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 209 | Mike Tyson's Punch-Out!! (Asia) (En) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | [59](https://tasvideos.org/59M), [215](https://tasvideos.org/215M), [229](https://tasvideos.org/229M), [408](https://tasvideos.org/408M), [544](https://tasvideos.org/544M), [627](https://tasvideos.org/627M), [630](https://tasvideos.org/630M), [766](https://tasvideos.org/766M), [1695](https://tasvideos.org/1695M), [2488](https://tasvideos.org/2488M), [4226](https://tasvideos.org/4226M), [6662](https://tasvideos.org/6662M), [6931](https://tasvideos.org/6931M) |
| 210 | Family Circuit '91 (Japan) (En).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 210 | Splatterhouse - Wanpaku Graffiti (Japan).nes | FM2 candidata; sincronización pendiente | [2915](https://tasvideos.org/2915M) | [735](https://tasvideos.org/735M), [2915](https://tasvideos.org/2915M) |
| 211 | Tiny Toon Adventures 6 (Asia) (En) (J.Y. Company) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 212 | 150-in-1 Unchained Melody (Asia) (En) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 215 | 3-in-1 (Asia) (En) (Super 308) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 215 | 2-in-1 - Shuang Wang Ji (Asia) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 215 | Pocahontas 2 (Asia) (En) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 216 | Magic Jewelry II (Asia) (En) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 219 | Toy Story (Asia) (En) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | [3678](https://tasvideos.org/3678M) |
| 222 | Dragon Ninja (Asia) (Ja) (CTC-31) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 227 | 150-in-1 Golden 1992 (Asia) (En) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 228 | Cheetahmen II (USA) (Unl).nes | FM2 candidata; sincronización pendiente | [2156](https://tasvideos.org/2156M), [2487](https://tasvideos.org/2487M) | [2156](https://tasvideos.org/2156M), [2345](https://tasvideos.org/2345M), [2450](https://tasvideos.org/2450M), [2487](https://tasvideos.org/2487M), [4109](https://tasvideos.org/4109M) |
| 229 | 31-in-1 (Asia) (En) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 232 | Quattro Adventure (USA) (Unl).nes | FM2 exacta; requiere adaptar entradas/periféricos | [2755](https://tasvideos.org/2755M), [2758](https://tasvideos.org/2758M) | [1986](https://tasvideos.org/1986M), [2755](https://tasvideos.org/2755M), [2758](https://tasvideos.org/2758M) |
| 234 | Maxi 15 (USA) (Rev 1) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 238 | Contra Fighter (Asia) (En) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 240 | Shenghuo Liezhuan (Asia) (C&E) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 242 | 1996 Aoyunhui Jingji Ban 24-in-1 (Asia) (En) (CK-008) (Pirate).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 243 | Honey Peach (Asia) (En) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 244 | Decathlon (Asia) (Ja) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | — |
| 246 | Fengshenbang (Asia) (C&E) (Simplified) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | [5785](https://tasvideos.org/5785M) |
| 250 | Time Diver - Avenger (Asia) (En) (T-A1) (Unl).nes | Sin coincidencia FM2 con esta ROM | — | — |

## Archivos locales de las películas candidatas

| Mapper | ROM | Película | Otras FM2 compatibles |
| --- | --- | --- | --- |
| 1 | Advanced Dungeons & Dragons - Heroes of the Lance (USA).nes | [FM2 4147](fm2/4147.fm2) | [4147](https://tasvideos.org/4147M) |
| 1 | Abadox - The Deadly Inner War (USA).nes | [FM2 2194](fm2/2194.fm2) | [2194](https://tasvideos.org/2194M) |
| 2 | Amagon (USA).nes | [FM2 1924](fm2/1924.fm2) | [1924](https://tasvideos.org/1924M) |
| 9 | Mike Tyson's Punch-Out!! (Japan, USA) (En) (Rev 1).nes | [FM2 1695](fm2/1695.fm2) | [1695](https://tasvideos.org/1695M) |
| 24 | Akumajou Densetsu (Japan).nes | [FM2 3357](fm2/3357.fm2) | [3357](https://tasvideos.org/3357M), [3360](https://tasvideos.org/3360M), [1979](https://tasvideos.org/1979M) |
| 65 | Spartan X 2 (Japan).nes | [FM2 2461](fm2/2461.fm2) | [2461](https://tasvideos.org/2461M) |
| 69 | Gimmick! (Japan).nes | [FM2 6243](fm2/6243.fm2) | [6243](https://tasvideos.org/6243M), [3168](https://tasvideos.org/3168M) |
| 75 | King Kong 2 - Ikari no Megaton Punch (Japan).nes | [FM2 4255](fm2/4255.fm2) | [4255](https://tasvideos.org/4255M) |
| 87 | Goonies (Japan).nes | [FM2 3302](fm2/3302.fm2) | [3302](https://tasvideos.org/3302M), [6133](https://tasvideos.org/6133M), [1373](https://tasvideos.org/1373M) |
| 141 | Q Boy (Asia) (En) (Unl).nes | [FM2 3166](fm2/3166.fm2) | [3166](https://tasvideos.org/3166M) |
| 184 | Atlantis no Nazo (Japan).nes | [FM2 1603](fm2/1603.fm2) | [1603](https://tasvideos.org/1603M) |
| 206 | Lupin Sansei - Pandora no Isan (Japan).nes | [FM2 3097](fm2/3097.fm2) | [3097](https://tasvideos.org/3097M) |
| 210 | Splatterhouse - Wanpaku Graffiti (Japan).nes | [FM2 2915](fm2/2915.fm2) | [2915](https://tasvideos.org/2915M) |
| 228 | Cheetahmen II (USA) (Unl).nes | [FM2 2156](fm2/2156.fm2) | [2156](https://tasvideos.org/2156M) |

No se han copiado ROMs a la SD ni iniciado pruebas en la consola. La siguiente fase será comprobar sincronización únicamente después de presentar y revisar esta lista.

## Búsqueda en otros repositorios

Se revisaron 43 películas FM2 de fuentes externas. Las dos coincidencias exactas repiten una película ya revisada de Akumajou Densetsu. La selección sigue en 14 ROMs candidatas. [Fuentes, hallazgos y motivos de descarte](reporte_fuentes_externas.md).
