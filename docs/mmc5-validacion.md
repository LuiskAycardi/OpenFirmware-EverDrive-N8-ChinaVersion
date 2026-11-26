# MMC5 propio: implementación y validación (2026-11-09)

Estado: RBF 103 experimental. ExRAM, fill, atributos extendidos, selección CHR A/B,
IRQ y audio implementados; split limitado por las direcciones bajas de la SRAM.
No constituye todavía compatibilidad MMC5 completa ni validación en consola.
Los 162 mappers previamente completados se contabilizan aparte de este MMC5.

## Implementación

- `hdl/rtl/mapper_mmc5.v`: cuatro modos PRG y CHR; $5113 y bancos RAM limitados
  a tres bits para no acceder a la SRAM reservada al OS; protección por claves;
  multiplicador; selección CHR por PPUCTRL real (también registros espejo).
- `hdl/rtl/mmc5_exram.v`: 1024x8 de doble puerto síncrono, inferido en dos M4K.
  Modos CPU de escritura durante rendering/cero fuera de frame (0/1), RAM (2)
  y solo lectura (3). Datos retenidos durante reset del mapper. NT fuente 2
  accesible desde PPU en modos 0/1; fuente 3 genera fill y atributos replicados.
- Atributos extendidos: dirección de la última lectura NT, paleta replicada y
  banco CHR de 4KB determinado por ExRAM y $5130. Bancos A/B según sprites
  8x8/8x16, último conjunto escrito fuera de frame y fase de fetch.
- Scanline: tres lecturas NT idénticas arman el detector, lectura posterior
  cuenta la línea, estado in-frame y timeout de tres M2 sin lectura PPU,
  limpieza por vector NMI, pendiente/enable y reconocimiento de $5204.
- `hdl/rtl/snd_mmc5.v`: dos pulsos sin sweep, timer/duty, length/halt y
  envelope; DAC PCM con modos de escritura/lectura, IRQ por cero y estado.
  Mezcla lineal sin calibración analógica; divisor de frame 7424 ciclos CPU
  (estimación de la referencia de hardware, aún sin contrastar en consola).
  El modelo Mesen2 consultado deja PCM read/IRQ como TODO: no es un oráculo
  suficiente para verificar esas funciones; se probaron por separado.
- `n8_top.v`: conducción de datos PPU por bit exclusivamente en lectura,
  con /WR inactivo, juego MMC5 y memoria habilitada; SRAM OE y CIRAM quedan
  desactivados cuando conduce la FPGA. La salida vuelve a Z en OS/reset.
  Macro N8_RBF_103 aislada; audio/lecturas MMC5 ya no dependen de RBF102.

## Split: límite físico explícito

Se implementaron registros $5200-$5202, selección de región, tile/paleta
ExRAM y banco CHR. El desplazamiento vertical fino NO se puede sustituir por
este mapa de señales: A0..A9 de la SRAM CHR están conectadas directamente a
la PPU. Cambiar sus tres bits inferiores desde el mapper no es posible.
El resultado es correcto solo cuando el fine-Y solicitado coincide con el
que ya presenta la PPU. `split_fine_y_conflict` identifica el caso incompatible.
La prueba de origen de tile del split fija el estado del contador de fetch:
no es una prueba integral de temporización de split ni del desplazamiento.
No se presenta esta parte como implementación completa de split vertical.

## Banco de pruebas

API n8model v4 agrega PPU din/dout/doe y el bus CPU leído para PCM. El puente
observa escrituras PPUCTRL conservando el dispositivo PPU original; el
observador se registra después de reset/power-on para no colisionar con el
registro inicial de dispositivos. Los strobes de escritura PPU permanecen
activos durante relojes FPGA suficientes para la ExRAM síncrona. La caché
incluye la cabecera de la API. El ejecutor fuzz registra códigos de salida
negativos y retorna error cuando hay divergencias.

## Evidencia

- `tools/n8sim/reports/mmc5-unit-regression.json`: 14 testbenches pasaron,
  incluidos bancos/multiplicador, ExRAM/PPU y buses reales de n8_top.
- Multiplicación: 65536 parejas, ambos bytes; protección: 16 combinaciones;
  PRG/CHR: cuatro modos y ocho ventanas PPU; clave RAM alta no alcanza OS.
- `tb_mmc5_ext`: modo RAM/solo lectura, acceso PPU, fill, atributos extendidos,
  marcador IRQ sin contar tiles comunes, reconocimiento, CHR A/B y split parcial.
- `tb_mmc5_bus`: datos CPU/PPU, exclusión de SRAM/CIRAM y liberación en menú.
- `tb_snd_mmc5`: duty, habilitación y expiración/halt de length, envelope,
  sweep inerte, PCM y petición/reconocimiento de IRQ.
- `mutate_mmc5.py`: 4/4 mutaciones detectadas; `mutate_mmc5_ppu.py`: 6/6.
- `reports/mmc5-final-banks-nt`: 512 pasos dirigidos idénticos a Mesen2,
  comparando PRG/CHR/nametables y excluyendo únicamente el campo IRQ.
  Incluye modos ExRAM y fill. No certifica rendering ni IRQ por fotograma.
- `reports/mmc5-api4-regression`: NROM y MMC3, 64 pasos cada uno, idénticos.
- `reports/mmc5-games-initial`: 180 fotogramas, Castlevania III (máx 15 píxeles),
  Just Breed (9), Gemfire (56), diferencias pendientes de clasificar.
- `reports/mmc5-games-final`: repetición con puente y ExRAM corregidos, mismos
  máximos: Castlevania III 15 píxeles (4/180 frames), Just Breed 9 (61/180),
  Gemfire 56 (15/180). Todos los píxeles examinados en el borde izquierdo:
  cajas x16..23, x8..15 y x0..7 respectivamente. No asumir equivalencia por compilar.
- Quartus: `hdl/out/103.RBF`, 59.392 bytes, EP2C5T144C8, 1.037 LE (23%),
  8.192 bits en M4K, setup clk +6,069 ns y hold mínimo +0,215 ns.
  SHA256: `5983d2dce84700cfbc4f5fe8e143459daf071310b45299c35066cce8da71bc06`.
  Informes en hdl/quartus/rbf103/output_files.

Las tandas `mmc5-ppu-integration` y `mmc5-ppu-recheck` fallaron al cargar por
el orden de registro del observador; las primeras `mmc5-ppu-mode1-*` también
fallaron por el strobe demasiado corto. Son ensayos históricos fallidos,
no evidencia positiva. Los informes posteriores documentan las correcciones.

## Experimento de instante de escritura

`reports/mmc5-games-early-write`, con N8_EARLY_WRITE=1, 180 fotogramas:
Castlevania III coincide completo; Gemfire queda en hasta 8 píxeles;
Just Breed empeora (hasta 5.476 píxeles). Este modo cambia el orden temporal
de escrituras y accesos PPU: no es una corrección general ni se aplica al RTL.
La ejecución normal conserva el flanco negativo de M2. Los resultados apoyan
que el instante de escritura influye en las diferencias, pero no prueban que
cada diferencia restante sea exclusivamente del banco. Mantenerlas abiertas.

Quedan pendientes: pruebas extensas de juego y de IRQ/audio contra hardware,
calibración de mezcla y revisión de la frecuencia del frame de audio, y resolver
el límite físico de fine-Y para poder afirmar split completo. Los tests de
Mesen2 de 180 fotogramas no certifican todas las pantallas ni todos los juegos.

## Prueba en la NES (2026-11-25, v0.6.3-beta, 103.RBF de la release)

Primera prueba del 103 en la consola (NES con kit Lava RGB, capturadora y mando emulado con el Nano). Motivo: en la
prueba de concepto del «modo imagen» del OS se vio que el transceptor de datos de la PPU (`ppu_ex = s_ciram_en` en
`n8_top.v`) queda desconectado con A13=1 si la CIRAM está habilitada, y se sospechaba que el MMC5 tenía el mismo
fallo. No lo tiene: `nt_internal` pone `ciram_en = 0` solo por dirección (y por el contador de fetch) en todas las
lecturas que sirve la FPGA (ExRAM como nametable, fill, atributos extendidos, split), así que `ppu_ex` baja antes de
/RD. `tb_mmc5_bus` lo comprueba ahora con /RD alto y durante la lectura (fill, atributo del fill, ExRAM como
nametable en lectura y escritura, y CIRAM normal); con el fallo provocado (`ciram_en = ppu_a[13]`) da 6 errores.

| Juego (NTSC) | Qué se vio | Resultado |
|---|---|---|
| Castlevania III (USA) | intro en tira de película, título, escena de la oración, fase 1 con marcador, scroll, velas | bien |
| Just Breed (Japan) | partidas, nombre, intro con kanji, pueblo con color por casilla y scroll; «Partida guardada» al volver | bien |
| Uchuu Keibitai SDF (Japan) | título, despegue, juego, READY, Game Over y continuar | bien (no se identificó la escena del split) |
| Laser Invasion (USA) | título, sesión informativa con retrato, selección de equipo, cabina con el marcador partido por la IRQ | bien |
| Bandit Kings of Ancient China (USA) | logos, título, menús y escenarios; «Partida guardada» al volver | bien |
| Aoki Ookami to Shiroki Mejika - Genchou Hishi (Japan) | logos, título, mapa con ventanas, retratos y kanji | bien |

Ninguna imagen con bloques de 16x16 de paletas al azar (el síntoma del transceptor). Sin comprobar: el sonido del
MMC5 (el NES no saca el audio de expansión), el split vertical en una escena que lo use de verdad (con su límite de
fine-Y) y partidas largas. Metal Slader Glory (512 KiB de CHR) no cabe en la SRAM CHR del N8 (0x7F000 es del menú).

## Reproducción desde la raíz

```
make -C hdl sim
python3 -B hdl/tools/mutate_mmc5.py
python3 -B hdl/tools/mutate_mmc5_ppu.py
make -C hdl out/103.RBF
```

`make sim` usa ahora `hdl/tools/run_sim.py`: propaga códigos de salida y
detecta los mensajes FALLO/FALLARON de testbenches antiguos. Se verificó con
una prueba correcta, una que solo imprime FALLO y otra que usa $fatal.
El banco fuzz también devuelve error si una comparación no coincide.
