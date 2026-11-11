# Análisis de la microSD de fábrica del clon (copia local, 2026-11-04)

## Resumen
- 636 MB, 3005 ROMs .nes repartidas en carpetas `FC 0 A` … `FC U V W X Y Z`.
- Carpeta del sistema: `/EDFC/` (OS.BIN, MAPROUT.BIN, MAPS/, SAVE/).
- 49 archivos `._*`: metadatos de macOS (AppleDouble) de cuando alguien copió la SD en un Mac. Inofensivos.
- El "pack" procede de un vendedor/comunidad vietnamita (Readme.txt en vietnamita, UTF-16).

## Versión del OS
- `OS.BIN`: 57 344 bytes (0xE000), fecha **2015-09-27**, SHA-256
  `7f9adf2b6cfde138a657e2c20a319882c74f65e88b8e7f8f94a5998ffc82b72b`.
- La fecha coincide exactamente con **nesos-v13 (27.09.2015)** del changelog oficial
  (v13 = "compatibilidad con el adaptador Hi-Def NES HDMI"). No se pudo confirmar por hash:
  Krikzz solo publica hoy las versiones 1.20–1.26.
- Los vectores de 6502 al final del archivo son NMI=$80D1, RESET=$8000, IRQ=$8108.
- El texto del menú no aparece en ASCII ni con desplazamientos simples: probablemente usa
  codificación de tiles propia o está comprimido (pendiente para la fase B).
- ⚠️ v13 es muy anterior a 1.24–1.26 (killswitch contra clones). **No actualizar.**

## MAPS/ (29 archivos .RBF)
- Todos empiezan con bytes 0xFF y están rellenados con 0xFF hasta un múltiplo de 512,
  salvo dos de la comunidad:
  - `030.RBF` (2018): tamaño no múltiplo de 512 (funciona igual).
  - `031.RBF` (2015-08, actualizado a mano en 2019): termina con el texto basura
    `][255][255]…` pegado al final. El OS lo carga igual, porque la FPGA ignora lo que sobra
    después del bitstream.
- Tamaños de 51–73 KB, mucho menos que el bitstream sin comprimir del EP2C5 (~150 KB) →
  **los .RBF están comprimidos**. El .qsf de referencia no fija la compresión de forma explícita,
  así que es el valor por defecto de Quartus para Cyclone II en Passive Serial. Hay que verificar
  que nuestro .RBF salga de un tamaño parecido (~50–70 KB).
- La mayoría tiene fecha 2014-04-16 (época del OS v9.1). Los archivos `003`, `027`, `037` (2018),
  `030` (2018) y `085` (2017) son posteriores: alguien portó mappers de OS más nuevos al pack v13.
- `249–254.RBF`: mappers con save state. `255.RBF`: mapper del OS/menú (no figura en la tabla,
  el OS lo carga directamente).

## MAPROUT.BIN
- Tabla normal: 152 mappers soportados. Tabla de save state: 31 mappers.
- Hay dos copias de respaldo: `MAPROUT - O.BIN` (2015, la original de v13, 117 mappers)
  y `MAPROUT_31.BAK` (2019, la original + el mapper 31).
- La versión actual añade 35 entradas sobre la original: 30 (→030), 37/45/49/51/52/105/177/197/
  214/228/229/244/249/250 (→037), 108/142/143/145/149/156/165/171/175/176/213/216/222/252 (→027),
  137/138/139/141/147/211 (→003) y 85 (→085, antes →022).
- **Problema encontrado:** el mapper **90** apunta a `090.RBF`, que **no existe** en MAPS/ →
  los juegos con mapper 90 fallarán.
- Un RBF puede contener varios mappers; p. ej. `000.RBF` atiende 0, 3, 7, 11, 13, 15, 34…

## Implicaciones para el proyecto
1. Base de pruebas: OS v13 + método "RBF con el mismo nombre que la ROM" o entrada propia en
   MAPROUT.BIN (hay hueco libre, p. ej. un número de RBF sin usar).
2. Antes de tocar la SD: guardar copia de `MAPROUT.BIN` (ya hay dos .BAK).
3. Compilar con compresión de bitstream y rellenar con 0xFF hasta múltiplo de 512.
