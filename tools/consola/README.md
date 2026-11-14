# Pruebas de mappers en la consola, automáticas

Sustituye a marcar a mano la página "Pruebas N8". Tú solo mueves la microSD. El PC:
- hace de **mando 1** con un Arduino Nano;
- **ve la consola** por la capturadora;
- **navega por el menú** del OS v13 hasta cada ROM;
- **juega** con el mismo guion que el banco de pruebas;
- **compara** cada escena con Mesen2;
- **vuelve al menú** con el reset del kit Lava (Select+B).

Si un juego se cuelga y ya no lee el mando, el reset no llega: entonces te avisa (pitido y notificación) para
que apagues y enciendas, y sigue solo con el siguiente juego en cuanto vuelve a ver el menú.

```
 PC ──USB── Arduino Nano ──(alargador cortado)── puerto de mando 1 ── NES / Famicom AV (kit Lava RGB)
 PC ──USB── capturadora HDMI (720p60) ── GBS-Control ── RGBS + audio de la consola
```

## Lo que tienes que hacer tú (una vez)
1. **Soldar el mando**: alargador de NES cortado + 1 resistencia de 1 kΩ + un puente. Opcional: otra de
   47-100 kΩ para el sensor de encendido. Todo en [CONEXION.md](CONEXION.md).
   - Con el Nano (5 V) **no hace falta el adaptador de niveles** BSS138/74AHCT125: no lo compres.
   - Nunca unas el +5V de la consola con el 5V del Nano.
2. **Permiso para el puerto serie** (Arch/CachyOS):
   ```bash
   sudo usermod -aG uucp tester
   ```
   Luego cierra la sesión y vuelve a entrar. Tu usuario ya está en el grupo `video` (capturadora) y `audio`.
3. **Grabar el firmware en el Nano**: enchúfalo por USB y ejecuta:
   ```bash
   python3 -I tools/consola/flashear.py
   ```
   - No hace falta instalar nada: `firmware/mando.hex` ya está compilado y `flashear.py` habla directamente con el
     cargador del Nano.
   - Si falla con un clon, prueba `--baud 57600` (cargador antiguo) o pulsa RESET en el Nano justo al lanzarlo.
   - Alternativa con avrdude: `sudo pacman -S avrdude` y `make -C tools/consola/firmware flash-avrdude BAUD=57600`.
4. **Copiar la ROM de calibración a la microSD**, junto con lo demás la próxima vez que la actualices:
   `tools/consola/rom/calibracion.nes` → `PRUEBAS/0 Calibracion/calibracion.nes`. Es NROM: usa el mapper 0 de
   nuestro 100.RBF.
5. **Conectar la capturadora** (GBS-Control a 720p60) y comprobar que se ve todo:
   ```bash
   python3 -I tools/consola/prueba.py dispositivos
   ```
   Tiene que salir el Nano (CH340 → `/dev/ttyUSB0`; `/dev/ttyACM0` con el Uno o con un CH340 CDC), la capturadora con
   "MJPG 1280x720 a 60 fps: sí" y su tarjeta de sonido.
   La capturadora (MS2109) pinta barras de color cuando no tiene señal HDMI y también durante ~1 s cada vez
   que se abre en frío; `captura.py` las reconoce y las descarta. Si `--foto` solo da barras, el GBS-Control no
   está sacando imagen. Cierra la app de cámara antes de las pruebas: el dispositivo es de un solo programa.
   Con el GBS-Control a 720p, el NES ocupa x ≈ 38-1255 y toda la altura (escala ≈ 4,76 x 3,01).
6. **Primera prueba del mando** con la consola encendida en el menú:
   ```bash
   python3 -I tools/consola/mando.py estado
   ```
   Tiene que contar LATCH (`lat=` subiendo y `per16≈66557`, el periodo NTSC). Con `mando.py toca down 100` el
   cursor del menú baja una fila.

## Uso normal
Las opciones (puerto, capturadora, carpeta de la SD, teclas del menú, retrasos) van en `config.json`. Copia
`config.ejemplo.json` y cambia solo lo necesario; sin él, todo se busca solo.

### Control visual local (experimental, Super Mario Bros.)

`controlador.py` analiza el vídeo continuamente y manda pulsos cortos al Nano; no espera una revisión humana
de cada captura. El perfil inicial reconoce la ropa de Mario, el marcador, suelo, huecos y obstáculos.
Solo cuenta un nivel terminado al observar el siguiente marcador de nivel; un arranque correcto no cuenta.
La primera prueba física de 90 s avanzó y saltó, pero **no completó 1-1**: el perfil necesita ajustes de juego.
Todavía no es un jugador general ni una validación de tres niveles para todos los mappers.

```bash
python3 -I tools/consola/latencia.py --repeticiones 32
python3 -I tools/consola/controlador.py --segundos 180
python3 -I tools/consola/prueba_controlador.py
python3 -I tools/consola/evaluar_controlador.py RUTA_DEL_INFORME/video.mp4
```

Ejecutar desde la raíz del proyecto. El controlador carga SMB de la SD y pulsa Start; `--en-juego` omite ese
paso cuando ya está en una partida **sin pausa**. Guarda MP4, decisiones JSONL, marcadores y resultado en
`informes/control-smb-*`. Los pulsos vencen en 250 ms aunque se interrumpa el proceso; ante vídeo ausente o
antiguo deja de renovarlos. Cada juego futuro necesita un perfil propio.

`latencia.py` carga la ROM de calibración y mide 32 pulsaciones y 32 liberaciones repartidas entre los ocho
botones. `--en-rom` evita navegar si esa ROM ya está cargada; se verifica su estructura antes de medir.
Guarda muestras y percentiles en `datos/latencia_input.json` y un informe con vídeo. El retardo medido es
**orden del PC → indicador visible**, incluyendo USB, lectura del mando, actualización de la ROM y vídeo;
no es la latencia exclusiva de la capturadora ni se debe confundir con `calibracion.json.retraso_s`.
El controlador predictivo v2 carga las medianas de pulsación y liberación por separado, más la variación
hasta el percentil 90. Mide velocidad a partir del sprite y del scroll del escenario, y velocidad relativa
de los peligros. Proyecta sus distancias durante el retardo medido y el tiempo transcurrido desde recibir
la imagen; usa la variación como margen adicional. El retardo host→imagen se aplica una sola vez: no se
suma de nuevo como si se hubiera medido por separado vídeo y mando. También confirma apoyo estable,
salto pendiente, vuelo y liberación efectiva de A antes de repetir el salto. La pérdida de visión cancela
el pulso mediante la misma orden de liberación calibrada; el vencimiento de 250 ms cubre un fallo del host.
Los JSONL guardan velocidad, horizonte y distancias predichas para poder revisar cada decisión.
`evaluar_controlador.py` compara, a 100 ms, la posición sin actualizar, la antigua velocidad fija de
160 px/s y la nueva predicción visual. Usa pares compatibles del mismo peligro detectado; es una
comprobación del seguimiento, no una medida de éxito del juego ni coordenadas externas de referencia.
Sigue siendo un perfil experimental: compensar latencia no sustituye la estrategia de cada nivel.
Repetir la medición tras cambiar GBS, capturadora o configuración de vídeo.

```bash
cd tools/consola
python3 -I prueba.py calibrar          # la primera vez, o si cambias algo en el GBS-Control
python3 -I prueba.py referencias       # capturas de Mesen2 de toda la lista (una vez; ~10 min)
python3 -I prueba.py ejecutar          # la lista de la NES de la página (154 juegos, ~1,5 h)
python3 -I prueba.py ejecutar --consola famicom
python3 -I prueba.py ejecutar --carpeta "PRUEBAS/9e Namco 163"
python3 -I prueba.py ejecutar --solo "Mega Man" --max 2
```
- **calibrar**:
  1. Si no hay calibración, encuentra la rejilla del texto del menú.
  2. Navega hasta la ROM de calibración y calcula el recorte exacto de los 256x240 dentro de 720p.
  3. Comprueba los 8 botones uno a uno, porque la ROM muestra lo que lee.
  4. Mide el retraso de la cadena de vídeo con el contador de la ROM.
  5. Guarda todo en `datos/calibracion.json`.
- **ejecutar**:
  - El informe queda en `informes/<fecha>/index.html`: consola y Mesen2 lado a lado en cada escena, el vídeo de
    cada juego (`clip.mp4`) y el audio (`audio.wav`).
  - Va guardando a medida que avanza: si lo paras con Ctrl+C, lo hecho queda.
- **Prueba en seco** (sin hardware):
  ```bash
  python3 -I prueba.py ejecutar --seco --max 3 --fotogramas 600
  ```
  - Simula la consola, el Nano y la capturadora:
    - el Nano es la lógica real del firmware, compilada para el PC y conectada por un pty;
    - el menú imita al del OS v13;
    - cada juego pone las imágenes de Mesen2.
  - Al 2.º juego le pone pantalla negra y al 3.º lo cuelga a propósito, para comprobar que se detectan.

## Cómo decide
- **Fotograma**:
  - Es el número del banco: fotogramas completos desde el arranque, igual que `N8_SCRIPT` en
    `tools/n8sim/run_test.lua`.
  - Mesen2 (`mesen_ref.lua`) apunta en qué fotogramas lee el mando el juego. El primero, `p0`, es el que el Nano
    asigna al primer LATCH que llega tras el silencio de la carga del OS.
  - A partir de ahí, el Nano cuenta los fotogramas con los LATCH y los aplica al guion él solo, sin depender del
    USB.
- **Escenas**:
  - En cada fotograma de `shots` se toma la ventana de vídeo de ±0,35 s alrededor del momento esperado (con el
    retraso medido) y se elige el cuadro que mejor encaja con la captura de Mesen2.
  - Se compara por **clases de color**: el color que tiene cada color de Mesen2 en la captura. Así da igual la
    paleta del kit RGB. Se perdonan los bordes y desplazamientos de hasta 2 píxeles.
  - **ok**: ≤ 3 % de píxeles distintos.
  - **parecido**: ≤ 12 % con la misma estructura. Es típico de la RAM aleatoria: enemigos o demos distintos.
  - **distinto** / **basura** / **negra**: lo demás.
- **Cuelgue**: el juego deja de leer el mando 3 s con la imagen congelada, o 12 s en cualquier caso.
- **Sonido**: se graba siempre.
  - La prueba del tono de 1 kHz (mapper 250) se juzga sola.
  - La música de los chips de expansión hay que escucharla: queda el `audio.wav` en el informe.
- Las pruebas con la SD de fábrica y las de pila (guardar, apagar, cargar) siguen siendo a mano. Las de pila se
  ejecutan igual: el juego se prueba, pero no la partida guardada.

### Guiones

Para generar recorridos propios sin depender de un TAS publicado, está el bot v2
[`explorador.py`](explorador.py): conserva rutas por celdas visuales, explora con
acciones por género y penaliza bucles. Exporta FM2 y puede repetirlas desde encendido
antes de llevarlas al Nano. Incluye objetivos visuales vinculados a la ROM, varias
rutas y un plan orientativo de las 204 ROMs. **No se ha validado todavía con juegos
reales y no certifica superar niveles.** Uso, fuentes, presupuestos y límites en
[`EXPLORADOR.md`](EXPLORADOR.md).

`guiones.json`: uno por defecto (Start para pasar los títulos y un poco de movimiento), otro sin botones para las
ROM de blargg, y los que quieras por ROM en `por_rom`, con `guion`, `shots` y `fotogramas`. El formato es el de
`N8_SCRIPT` y admite 64 tramos como máximo. Con el mismo guion se pueden sacar las capturas de nuestro Verilog en
el banco (lento):
```bash
python3 -I prueba.py referencias --banco --carpeta "PRUEBAS/4 MMC3"
```
Llama a `tools/n8sim/difftest.py --script ... --shots ...` con `--slot-base 40` para no pisar otras tandas.

## Resultados en la página "Pruebas N8"
Cada informe deja `resultados_pagina.json`:
- Usa el formato de la colección `resultados` de https://claude.ai/artifact/M7ivqPxY2kGrvWydGXVXPd: id
  `nes-<carpeta>-<juego>` o `famicom-…`, generado con el mismo `tools/pagina-pruebas/plan_pruebas.py`, y los
  campos `estado`, `nota`, `vol`, `consola` y `t`.
- `estado` es "ok" o "falla". Se deja vacío lo dudoso ("parecido"), que tiene que mirar alguien.
- La `nota` empieza por `[auto <fecha>]`.

Para subirlo, pídele a Claude: *"sube tools/consola/informes/<fecha>/resultados_pagina.json a la página de
pruebas"*. Claude lo escribe con ArtifactData y no pisa lo que hayas marcado tú a mano: solo sustituye las notas
que empiezan por `[auto`.

## Archivos
| Archivo | Qué es |
|---|---|
| `CONEXION.md` | cableado del Nano al puerto del mando |
| `firmware/` | firmware del Nano: `nucleo.c` (lógica), `main_avr.c` + `arranque.S` (SPI esclavo = CD4021, interrupción de LATCH), `mando.hex` compilado con clang/ld.lld (`make -C firmware`) |
| `flashear.py`, `serie.py` | grabar el Nano (STK500) y puerto serie con la biblioteca estándar |
| `mando.py` | cliente del protocolo del Nano, también a mano (`estado`, `monitor`, `toca`, `reset`, `guion`) |
| `captura.py` | ffmpeg: capturadora (v4l2, MJPEG 720p60) recortada a 256x240, clips MP4 y audio ALSA |
| `calibrar.py` | geometría de la imagen (ROM de calibración o menú) y mapa de colores |
| `rom/hacer_rom.py` | la ROM de calibración, con su ensamblador 6502 mínimo |
| `menu.py` | lectura del menú del OS v13 (fuente aprendida) y navegación |
| `referencia.py`, `mesen_ref.lua` | capturas de Mesen2 y fotogramas en que el juego lee el mando |
| `comparar.py`, `sonido.py` | veredictos de imagen y audio |
| `prueba.py` | todo junto, informe y resultados para la página |
| `simulador.py` | consola, Nano y capturadora simulados (`--seco`) |
| `prueba_firmware.py` | pruebas de la lógica del firmware con tiempo simulado (guion, lecturas dobles, armado, reset) |
| `datos/` | lo aprendido en la consola real: calibración, fuente del menú, cursor |
