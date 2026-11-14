# Búsqueda de TAS en repositorios externos

Fecha: **14 de noviembre de 2026**. Revisión estática de fuentes y archivos; **sin ejecutar Mesen, FCEUX ni la consola**.

Se inspeccionaron **14 árboles completos de repositorios GitHub** y el índice público de dwangoAC en acbit. Se descargaron **43 películas FM2** (contando copias/versiones) y se cruzaron contra los checksums de las **204 ROMs seleccionadas**.

Resultado: **0 ROMs adicionales** con FM2 utilizable por el banco actual. Las **2 coincidencias exactas** corresponden a Akumajou Densetsu, que ya estaba entre las 14 candidatas. Ambas tienen las mismas entradas y órdenes que [TASVideos 1979](https://tasvideos.org/1979M); no son recorridos nuevos.

## Fuentes inspeccionadas

| Fuente | Resultado del árbol/índice |
| --- | --- |
| [https://acbit.net/static/tas/](https://acbit.net/static/tas/) | Índice consultado |
| [https://github.com/ChuckCaplan/TASDeck](https://github.com/ChuckCaplan/TASDeck) | 0 archivos FM2; 3 películas de otros formatos |
| [https://github.com/TAS-S/Movies](https://github.com/TAS-S/Movies) | 0 archivos FM2; 0 películas de otros formatos |
| [https://github.com/TASEmulators/fceux](https://github.com/TASEmulators/fceux) | 0 archivos FM2; 0 películas de otros formatos |
| [https://github.com/WolffTech/nes-wallpaper](https://github.com/WolffTech/nes-wallpaper) | 1 archivos FM2; 0 películas de otros formatos |
| [https://github.com/bigbass1997/VeriTAS](https://github.com/bigbass1997/VeriTAS) | 0 archivos FM2; 0 películas de otros formatos |
| [https://github.com/camdenspielman-hub/TAS_Fun-](https://github.com/camdenspielman-hub/TAS_Fun-) | 24 archivos FM2; 0 películas de otros formatos |
| [https://github.com/cupidthecat/cupid-nes](https://github.com/cupidthecat/cupid-nes) | 0 archivos FM2; 0 películas de otros formatos |
| [https://github.com/ddugovic/tasbot](https://github.com/ddugovic/tasbot) | 0 archivos FM2; 0 películas de otros formatos |
| [https://github.com/doublegate/RustyNES](https://github.com/doublegate/RustyNES) | 0 archivos FM2; 0 películas de otros formatos |
| [https://github.com/heliacode/retrochallenges-assets](https://github.com/heliacode/retrochallenges-assets) | 1 archivos FM2; 2 películas de otros formatos |
| [https://github.com/jedahan/autones](https://github.com/jedahan/autones) | 7 archivos FM2; 0 películas de otros formatos |
| [https://github.com/mcfbytes/Tasty_MiSTer](https://github.com/mcfbytes/Tasty_MiSTer) | 0 archivos FM2; 0 películas de otros formatos |
| [https://github.com/taba256/TAS-Movie-Files](https://github.com/taba256/TAS-Movie-Files) | 0 archivos FM2; 7 películas de otros formatos |
| [https://github.com/taiyuuki/nes-sim](https://github.com/taiyuuki/nes-sim) | 0 archivos FM2; 0 películas de otros formatos |

Microstorage (`dehacked.2y.net`) se intentó por HTTPS y HTTP: ambas conexiones fueron rechazadas. No se cuentan sus archivos como revisados.

## Hallazgos relevantes

| Juego seleccionado | Mapper | Fuente | Resultado |
| --- | --- | --- | --- |
| Akumajou Densetsu (Japan) | 24 | [jedahan/autones](https://github.com/jedahan/autones/tree/master/movies) | Dos FM2 con checksum exacto y entradas admitidas; ambas duplican las entradas de TASVideos 1979. |
| High Speed (USA) | 119 | [Archivo de dwangoAC](https://acbit.net/static/tas/) | Cuatro películas/versiones declaran MD5 `e9604d2edfe39495d617d51144942d94`; nuestra ROM declara/calcula `b472f97c9f85b13eaabc4400cfe3b7bd`. Tampoco coincide la ROM europea disponible. No se aceptan por nombre. |
| Crazy Climber (Japan) | 180 | [Archivo de dwangoAC](https://acbit.net/static/tas/) | La BK2 encontrada declara plataforma WSWAN y núcleo Cygne/Mednafen: es WonderSwan, no NES. |
| Mega Man 2 (USA) (iam8bit) | 30 | [TAS_Fun-](https://github.com/camdenspielman-hub/TAS_Fun-) y [retrochallenges-assets](https://github.com/heliacode/retrochallenges-assets) | Se localizaron películas de Rockman/Mega Man 2; sus checksums no coinciden con nuestra ROM seleccionada. |
| Juegos del paquete TASDeck | — | [TASDeck](https://github.com/ChuckCaplan/TASDeck) | Tres dumps R08 inventariados; no se han convertido ni se acredita identidad de ROM con ellos. |

## Auditoría de las 43 películas FM2

| Archivo | Fuente | Coincidencia exacta | Resultado |
| --- | --- | --- | --- |
| 335-level-nes-tetris-level70steve.fm2 | [Origen](https://acbit.net/static/tas/335-level-nes-tetris-level70steve.fm2) | No | Checksum de película no coincide con ninguna ROM seleccionada |
| High Speed (U)-AC.fm2 | [Origen](https://acbit.net/static/tas/High%20Speed%20(U)-AC.fm2) | No | Checksum de película no coincide con ninguna ROM seleccionada |
| High Speed (U)-AC.fm2 | [Origen](https://acbit.net/static/tas/High_Speed-AC_Luck_Manipulation_Improvement_WIP.zip) | No | Checksum de película no coincide con ninguna ROM seleccionada |
| High Speed (U)-dwangoac.fm2 | [Origen](https://acbit.net/static/tas/High_Speed-dwangoac.zip) | No | Checksum de película no coincide con ninguna ROM seleccionada |
| High Speed (U)-AC.fm2 | [Origen](https://acbit.net/static/tas/High_Speed_WIP_by_AC.zip) | No | Checksum de película no coincide con ninguna ROM seleccionada |
| Otocky-TASEdit-WIP-dwangoAC.fm2 | [Origen](https://acbit.net/static/tas/Otocky-TASEdit-WIP-dwangoAC.fm2) | No | Checksum de película no coincide con ninguna ROM seleccionada |
| Otocky-WIP-dwangoAC-03.fm2 | [Origen](https://acbit.net/static/tas/Otocky-WIP-dwangoAC-03.fm2) | No | Checksum de película no coincide con ninguna ROM seleccionada |
| Otocky-WIP-dwangoAC-04.fm2 | [Origen](https://acbit.net/static/tas/Otocky-WIP-dwangoAC-04.fm2) | No | Checksum de película no coincide con ninguna ROM seleccionada |
| Otocky_WIP-dwangoAC.fm2 | [Origen](https://acbit.net/static/tas/Otocky_WIP-dwangoAC.fm2) | No | Checksum de película no coincide con ninguna ROM seleccionada |
| SMB3ForNewScreenSavers.fm2 | [Origen](https://acbit.net/static/tas/SMB3ForNewScreenSavers.fm2) | No | Checksum de película no coincide con ninguna ROM seleccionada |
| TestData/nestest.fm2 | [Origen](https://github.com/WolffTech/nes-wallpaper/blob/HEAD/TestData/nestest.fm2) | No | Checksum de película no coincide con ninguna ROM seleccionada |
| movies/rockman2-v1-85278.fm2 | [Origen](https://github.com/camdenspielman-hub/TAS_Fun-/blob/HEAD/movies/rockman2-v1-85278.fm2) | No | Checksum de película no coincide con ninguna ROM seleccionada |
| movies/rockman2-v2-85274.fm2 | [Origen](https://github.com/camdenspielman-hub/TAS_Fun-/blob/HEAD/movies/rockman2-v2-85274.fm2) | No | Checksum de película no coincide con ninguna ROM seleccionada |
| movies/rockman2-v3-85220.fm2 | [Origen](https://github.com/camdenspielman-hub/TAS_Fun-/blob/HEAD/movies/rockman2-v3-85220.fm2) | No | Checksum de película no coincide con ninguna ROM seleccionada |
| movies/rockman2-v3a-85254.fm2 | [Origen](https://github.com/camdenspielman-hub/TAS_Fun-/blob/HEAD/movies/rockman2-v3a-85254.fm2) | No | Checksum de película no coincide con ninguna ROM seleccionada |
| movies/rockman2-v4-85171.fm2 | [Origen](https://github.com/camdenspielman-hub/TAS_Fun-/blob/HEAD/movies/rockman2-v4-85171.fm2) | No | Checksum de película no coincide con ninguna ROM seleccionada |
| movies/rockman2-v4.1-85164.fm2 | [Origen](https://github.com/camdenspielman-hub/TAS_Fun-/blob/HEAD/movies/rockman2-v4.1-85164.fm2) | No | Checksum de película no coincide con ninguna ROM seleccionada |
| movies/rockman2-v4.2-85160.fm2 | [Origen](https://github.com/camdenspielman-hub/TAS_Fun-/blob/HEAD/movies/rockman2-v4.2-85160.fm2) | No | Checksum de película no coincide con ninguna ROM seleccionada |
| movies/rockman2-v5-85056.fm2 | [Origen](https://github.com/camdenspielman-hub/TAS_Fun-/blob/HEAD/movies/rockman2-v5-85056.fm2) | No | Checksum de película no coincide con ninguna ROM seleccionada |
| movies/rockman2-v5.1-85040.fm2 | [Origen](https://github.com/camdenspielman-hub/TAS_Fun-/blob/HEAD/movies/rockman2-v5.1-85040.fm2) | No | Checksum de película no coincide con ninguna ROM seleccionada |
| movies/rockman2-v5.2-85039.fm2 | [Origen](https://github.com/camdenspielman-hub/TAS_Fun-/blob/HEAD/movies/rockman2-v5.2-85039.fm2) | No | Checksum de película no coincide con ninguna ROM seleccionada |
| movies/rockman2-v5.3-85037.fm2 | [Origen](https://github.com/camdenspielman-hub/TAS_Fun-/blob/HEAD/movies/rockman2-v5.3-85037.fm2) | No | Checksum de película no coincide con ninguna ROM seleccionada |
| movies/rockman2-v5.4-85029.fm2 | [Origen](https://github.com/camdenspielman-hub/TAS_Fun-/blob/HEAD/movies/rockman2-v5.4-85029.fm2) | No | Checksum de película no coincide con ninguna ROM seleccionada |
| movies/rockman2-v5.5-85025.fm2 | [Origen](https://github.com/camdenspielman-hub/TAS_Fun-/blob/HEAD/movies/rockman2-v5.5-85025.fm2) | No | Checksum de película no coincide con ninguna ROM seleccionada |
| movies/rockman2-v5.6-85024.fm2 | [Origen](https://github.com/camdenspielman-hub/TAS_Fun-/blob/HEAD/movies/rockman2-v5.6-85024.fm2) | No | Checksum de película no coincide con ninguna ROM seleccionada |
| movies/rockman2-v5.7-85020.fm2 | [Origen](https://github.com/camdenspielman-hub/TAS_Fun-/blob/HEAD/movies/rockman2-v5.7-85020.fm2) | No | Checksum de película no coincide con ninguna ROM seleccionada |
| movies/rockman2-v5.8-85019.fm2 | [Origen](https://github.com/camdenspielman-hub/TAS_Fun-/blob/HEAD/movies/rockman2-v5.8-85019.fm2) | No | Checksum de película no coincide con ninguna ROM seleccionada |
| movies/rockman2-v5.9-85018.fm2 | [Origen](https://github.com/camdenspielman-hub/TAS_Fun-/blob/HEAD/movies/rockman2-v5.9-85018.fm2) | No | Checksum de película no coincide con ninguna ROM seleccionada |
| movies/rockman2-v6.0-85014.fm2 | [Origen](https://github.com/camdenspielman-hub/TAS_Fun-/blob/HEAD/movies/rockman2-v6.0-85014.fm2) | No | Checksum de película no coincide con ninguna ROM seleccionada |
| movies/rockman2-v6.1-85011.fm2 | [Origen](https://github.com/camdenspielman-hub/TAS_Fun-/blob/HEAD/movies/rockman2-v6.1-85011.fm2) | No | Checksum de película no coincide con ninguna ROM seleccionada |
| movies/rockman2-v6.2-85010.fm2 | [Origen](https://github.com/camdenspielman-hub/TAS_Fun-/blob/HEAD/movies/rockman2-v6.2-85010.fm2) | No | Checksum de película no coincide con ninguna ROM seleccionada |
| movies/rockman2-v6.3-85006.fm2 | [Origen](https://github.com/camdenspielman-hub/TAS_Fun-/blob/HEAD/movies/rockman2-v6.3-85006.fm2) | No | Checksum de película no coincide con ninguna ROM seleccionada |
| movies/rockman2-v6.4-85005.fm2 | [Origen](https://github.com/camdenspielman-hub/TAS_Fun-/blob/HEAD/movies/rockman2-v6.4-85005.fm2) | No | Checksum de película no coincide con ninguna ROM seleccionada |
| movies/rockman2-v6.5-85004.fm2 | [Origen](https://github.com/camdenspielman-hub/TAS_Fun-/blob/HEAD/movies/rockman2-v6.5-85004.fm2) | No | Checksum de película no coincide con ninguna ROM seleccionada |
| movies/rockman2-v6.6-84995.fm2 | [Origen](https://github.com/camdenspielman-hub/TAS_Fun-/blob/HEAD/movies/rockman2-v6.6-84995.fm2) | No | Checksum de película no coincide con ninguna ROM seleccionada |
| tas/megaman2/shinryuu-megaman2j.fm2 | [Origen](https://github.com/heliacode/retrochallenges-assets/blob/HEAD/tas/megaman2/shinryuu-megaman2j.fm2) | No | Checksum de película no coincide con ninguna ROM seleccionada |
| movies/aglar-star_wars.fm2 | [Origen](https://github.com/jedahan/autones/blob/HEAD/movies/aglar-star_wars.fm2) | No | Checksum de película no coincide con ninguna ROM seleccionada |
| movies/micro-ghosts_n_goblins.fm2 | [Origen](https://github.com/jedahan/autones/blob/HEAD/movies/micro-ghosts_n_goblins.fm2) | No | Checksum de película no coincide con ninguna ROM seleccionada |
| movies/micro-super_mario_bros..fm2 | [Origen](https://github.com/jedahan/autones/blob/HEAD/movies/micro-super_mario_bros..fm2) | No | Checksum de película no coincide con ninguna ROM seleccionada |
| movies/micro_ghosts_n_goblins.fm2 | [Origen](https://github.com/jedahan/autones/blob/HEAD/movies/micro_ghosts_n_goblins.fm2) | No | Checksum de película no coincide con ninguna ROM seleccionada |
| movies/micro_super_mario_bros..fm2 | [Origen](https://github.com/jedahan/autones/blob/HEAD/movies/micro_super_mario_bros..fm2) | No | Checksum de película no coincide con ninguna ROM seleccionada |
| movies/scrimpeh-akumajou_densetsu.fm2 | [Origen](https://github.com/jedahan/autones/blob/HEAD/movies/scrimpeh-akumajou_densetsu.fm2) | Akumajou Densetsu (Japan).nes | Formato/entradas admitidos; sincronización pendiente; mismas entradas que TASVideos 1979 |
| movies/scrimpeh-cv3jgrant.fm2 | [Origen](https://github.com/jedahan/autones/blob/HEAD/movies/scrimpeh-cv3jgrant.fm2) | Akumajou Densetsu (Japan).nes | Formato/entradas admitidos; sincronización pendiente; mismas entradas que TASVideos 1979 |

Las copias GitHub se comprobaron contra el SHA del blob publicado en el árbol consultado. Se conservaron las fuentes, archivos descargados y hashes. No se descargaron ROMs ni se ejecutó código de los repositorios externos.

La búsqueda cubre las fuentes enumeradas; no demuestra que no existan otras películas en archivos privados, envíos, userfiles o repositorios no encontrados. La lista principal sigue teniendo **14 ROMs con FM2 candidata**, pendientes de sincronización.
