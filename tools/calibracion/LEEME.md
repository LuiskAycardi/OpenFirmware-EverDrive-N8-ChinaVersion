# Calibración del volumen del sonido de expansión

> ☕ ¿Te resulta útil? Apoya el proyecto en **[Ko-fi](https://ko-fi.com/luiskaycardi)** / Find it useful? Support the
> project on **[Ko-fi](https://ko-fi.com/luiskaycardi)**.

Mide en una Famicom cuánto suena cada chip de sonido del cartucho frente al APU de la consola, para ajustar su
ganancia base (`hdl/tools/gen_ganancia.py`, `MEDIDO`). Resultados y método: [docs/sonido-volumen.md](../../docs/sonido-volumen.md).

```bash
python3 -I tools/calibracion/hacer.py --kyodaku-de "/ruta/a/un/disco.fds"    # ROMs y disco en tools/calibracion/out
```

Salen `CAL VRC6.nes`, `CAL 5B.nes`, `CAL N163.nes`, `CAL VRC7.nes`, `CAL MMC5.nes` y `CAL FDS.fds` (el disco lleva el
archivo de licencia `KYODAKU-` copiado de un disco del usuario: no entra en el repositorio). Cada una repite: 1 s del
pulso 1 del APU, 0,5 s de silencio, 2 s de la misma nota en el chip y 0,5 s de silencio, todo a ~440 Hz y a volumen
máximo. La pantalla queda negra. Leen el mando en cada fotograma, para que funcione el reset del kit Lava.

Con la ROM sonando en la consola y el audio entrando por la capturadora (en este PC, la MS2109 es `hw:3,0`):

```bash
python3 -I tools/calibracion/medir.py VRC6 --grabar 16 vrc6.wav
python3 -I tools/calibracion/medir.py VRC7 --grabar 16 vrc7.wav --vrc7-amp 2024
```

Da la proporción chip/APU medida, la de Mesen2, la corrección y la ganancia base calibrada. Si se graba con otro paso
de volumen del OS que el 0, se indica con `--paso`. `--vrc7-amp` es la amplitud del seno del instrumento de la ROM
en unidades de Mesen2 (2024, medida con `N8_AUDIO=1` en `tools/n8sim/difftest.py`).
