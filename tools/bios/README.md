# tools/bios — la BIOS del N8 clon en un emulador propio

Banco para estudiar el arranque del EverDrive N8 clon y, más adelante, arrancar en el PC el OS propio con la BIOS
real antes de probarlo en la consola. Resultados en [docs/bios-n8-clon.md](../../docs/bios-n8-clon.md).

| Archivo | Qué es |
|---|---|
| `cpu6502.py` | CPU 6502 (opcodes oficiales, sin modo decimal) |
| `maquina.py` | RAM, PPU mínima, mando, CPLD (`$4400-$4403`), FPGA en modo OS y SD en modo SPI (SDHC/SDSC) |
| `estudio.py` | `arranque` (resumen de una imagen) y `pruebas` (11 casos que comprueban el documento) |
| `hacer_sd.sh` | crea una imagen FAT16/FAT32, con o sin MBR, con `EDFC/OS.BIN` y `EDFC/MAPS/255.RBF` |
| `fragmentar.py` | fragmenta archivos de una imagen FAT32 para probar la lectura contigua |

Todo es código propio (GPL-3.0-or-later) y solo usa la biblioteca estándar de Python. `hacer_sd.sh` y
`pruebas` necesitan mtools, mkfs.fat y sfdisk.

**La BIOS no está en el repositorio** (es de Krikzz). Hace falta un volcado propio de 16 KiB de la ventana
`$C000-$FFFF`. En este equipo están los dos trozos de 8 KiB de las sondas BIOS_RESPALDO:

```bash
cat bios_c0_primeros_8k.bin bios_e0_primeros_8k.bin > /ruta/fuera/del/repo/bios.bin
```

Uso:

```bash
python3 -I tools/bios/estudio.py pruebas --bios /ruta/bios.bin --os ~/SD_Pruebas/EDFC/OS.BIN --rbf ~/SD_Pruebas/EDFC/MAPS/255.RBF --trabajo /tmp/carpeta-vacia
```

```bash
python3 -I tools/bios/estudio.py arranque --bios /ruta/bios.bin --img sd.img --seguir 3000000
```

Límites del modelo:
- La CPU no cuenta ciclos reales, `$2002` alterna el VBlank en cada lectura y la NMI se dispara cada N
  instrucciones.
- Los bits del CPLD que no se conocen se guardan y se devuelven tal cual. `$4403` siempre dice «SPI libre, USB
  vacío».
- No modela la ROM interna del 255.RBF de fábrica (§4 del documento). Un OS que empiece por `$EA` no correrá aquí
  como en la consola, y uno en claro sí.
- La SD contesta a CMD0, 8, 55, ACMD41, 58, 9, 10, 12, 16, 17, 18, 24, 25 y 59. No comprueba los CRC.
