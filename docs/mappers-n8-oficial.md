# Mappers del EverDrive N8 original (legacy) — análisis 2026-11-04

Fuentes: paquetes oficiales `nesos-v1.23.zip` y `nesos-v1.26.zip`, `changelist.txt` y
`mappers.png` de krikzz.com/pub/support/everdrive-n8/original-series/. Están guardados en
`ref/krikzz-n8-os/` **solo para analizarlos: no instalarlos** (1.24–1.26 llevan el killswitch
contra clones). También se usa una copia local de la SD de fábrica del clon.

## Cifras
| Versión | Mappers en MAPROUT | RBF | Save state |
|---|---|---|---|
| v13 original de fábrica (2015, `MAPROUT - O.BIN`) | 117 | 18 | tabla aparte (31 mappers) |
| Pack de fábrica actual (v13 + 35 portados) | 152 (el 90 apunta a un RBF que falta) | 24 | 31 |
| **Oficial v1.23 = v1.26** (2020–2021) | **178 = 177 + FDS (254)** | 16 | todos (MAPROUT de 256 B, sin tabla) |

`mappers.png` oficial (27.12.2020, según No-Intro): **177 soportados**, 7 existentes no
soportados (8, 14, 116, 128, 130, 159, 160) y 72 números que ningún juego usa.

v1.23 y v1.26 tienen la misma tabla. Cambian 6 RBF (002, 004, 005, 007, 085, 254): correcciones
de MMC5, FDS, MMC3 y el núcleo YM2413 del VRC7.

## Agrupación de la v1.26 (un RBF contiene varios mappers)
| RBF | Mappers |
|---|---|
| 000 | 0, 2, 3, 7, 16, 18, 32, 33, 36, 38, 48, 66, 71, 87, 140, 219 |
| 001 | 11, 13, 34, 65, 67, 68, 70, 72, 76, 77, 78, 80, 82, 86, 88, 89, 92–97, 144, 152, 154, 180, 184, 185, 206, 232 |
| 002 | 15, 28, 31, 40, 41, 42, 57, 58, 61, 91, 99, 101, 107, 112, 164, 168, 178, 188, 193, 200–203, 212, 227, 231, 234, 240–242, 246 |
| 003 | 79, 90, 113, 133, 137–139, 141, 146–148, 150, 211, 243 |
| 004 | 1, 4, 9, 10, 220 |
| 005 | 5 (MMC5) |
| 006 | 12, 47, 64, 74, 115, 118, 119, 158, 182, 189, 191, 196, 205, 245 |
| 007 | 30, 111, 190, 207 |
| 019 / 069 / 085 | 19 (N163) / 69 (FME-7) / 85 (VRC7) |
| 021 | 21–26, 73, 75, 151 (VRC) |
| 027 | 27, 50, 106, 108, 117, 142, 143, 145, 149, 156, 165, 171, 175, 176, 183, 199, 213, 216, 222, 252 |
| 037 | 35, 37, 44, 45, 49, 51, 52, 60, 105, 177, 197, 214, 228, 229, 238, 244, 248–250 |
| 056 | 56, 103, 132, 134, 136, 172, 173, 186, 187, 198, 221 |
| 254 | FDS |

Mappers de la v1.26 que no están en el pack de fábrica (26): 27, 35, 44, 50, 56, 60, 103, 106,
111, 117, 132, 134, 136, 144, 168, 172, 173, 183, 186, 187, 190, 198, 199, 221, 238, 248.

## Datos útiles del changelog
- MMC3 con 4 pantallas desde s2m4 (2013): coincide con Rad Racer II funcionando.
- La IRQ del MMC3 se retocó en v4, v5, v6, v12, v16, v1.21 y v1.25: es la parte delicada en
  este hardware (en nuestro caso, el ruido en A12).
- v1.20: save states para todos los mappers, MMC5 completo, audio de FDS, Sunsoft 5B y VRC7, y
  unos 57 mappers nuevos portados del N8 PRO.

## Cobertura sobre la colección de la SD (2993 ROMs, 126 mappers distintos)
| Conjunto | ROMs que cubre |
|---|---|
| Nuestros mappers tras la fase 2 (0, 1, 2, 3, 4, 7) | 2302 (76,9 %) |
| **Tras la fase 3a (23 mappers)** | **2570 (85,9 %)** |
| Tras la fase 3b (34 mappers) | 2686 (89,7 %) |
| Tras la fase 3c (78 mappers, RBF 100 + 101) | 2828 (94,5 %) |
| Tras la fase 3d-1 (86 mappers: lecturas de registros) | 2869 (95,9 %) |
| **Tras la fase 3d-2 (87 mappers: + Namco 163, RBF 102)** | **2893 (96,7 %)** |
| + 38 discretos/simples (11, 206, 79, 71, 66, 150, 87, 185, 146, 33…) | 2643 (88,3 %) |
| + 24 complejos (5, 19, 23, 69, 18, 16, 64, 9, 68, 75, 25…) | 2849 (95,2 %) |
| v13 original de fábrica | 2889 (96,5 %) |
| Pack de fábrica actual | 2924 (97,7 %) |
| Oficial v1.26 | 2947 (98,5 %) |
| **Fábrica + nuestros (SD combinada, 158 mappers)** | **2956 (98,8 %)** |
| **Tras la fase 4, lotes 1 y 2 (136 mappers, 2026-11-08)** | **2903 (97,0 %)** |

**SD combinada (cálculo del 2026-11-05):** los RBF de fábrica se llaman 000–118 y 249–255 y los nuestros
100–102, así que caben juntos y un solo MAPROUT elige el RBF de cada mapper. Solo para uso personal (los de
fábrica no se distribuyen). Supera a la v1.26 porque los nuestros añaden 210 (13 ROMs), 46, 155 y los TXC.
Completar los 177 de la v1.26 aporta poco: de los 27 mappers oficiales que faltan en el pack, 4 ya son
nuestros (132, 136, 172, 173); los otros 23 (incluido el 90) suman 8 ROMs: 168 Racermate (6, necesita su
bicicleta), 144 (1) y 190 (1). Los otros 20 no tienen ningún juego en la colección.
Fuera de la combinada quedan 37 ROMs: 157 Datach (7, lector de códigos), 159 EEPROM (6), 168 (6), mappers
≥ 256 que el MAPROUT de 1 byte de v13 no puede asignar (547 ×4, 516 ×2, 521, 515, 262), 116 (3), 192 (2),
144, 190, 179 y 153. Casi todo eso necesita nuestro OS (mappers ≥ 256, guardar la EEPROM) o accesorios.
Fábrica y no nuestros: 63 ROMs, la mitad MMC5 (30).

Ni la v1.26 cubre 46 ROMs: 210 (13), 157 (7), 159 (6), 547 (4), 116 (3) y otros sueltos. El
mapper 90, roto en el pack, no tiene ninguna ROM en la colección.
Orden recomendado para la fase 3: primero los discretos y simples por número de juegos (11, 206,
79, 71, 66, 150, 87, 185…), después los complejos (5, 19, 23, 69, 18, 16…).

Siguientes por número de ROMs (tras la fase 3c): 5 MMC5 (30), 19 N163 (24), 150 Sachen (17), 132 TXC (7),
157 Datach (7), 159 Bandai con EEPROM (6), 168 Racermate (6, necesita su bicicleta). Los primeros
necesitan que la FPGA conduzca el bus de datos de la CPU (lecturas de registros o de EEPROM).

Siguientes por número de ROMs (tras la fase 3a, histórico): 5 MMC5 (30), 19 N163 (24), 23 VRC2/4 (19),
150 Sachen (17), 69 FME-7 (17), 18 Jaleco SS88006 (17), 16 Bandai FCG (16), 210 Namco 175/340 (13),
185 CNROM con protección (11), 64 Tengen RAMBO-1 (9), 9 MMC2 (9).
