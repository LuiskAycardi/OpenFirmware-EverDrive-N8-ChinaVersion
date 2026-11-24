# Volumen del sonido de expansión

Desde el 2026-11-24 los RBF con sonido de expansión (FDS 254, VRC6 101, VRC7 106, Sunsoft 5B 100, Namco 163 102 y
MMC5 103) llevan una **etapa de ganancia** delante del convertidor del pin 97, y el OS tiene una **pantalla de
opciones** para subir o bajar ese volumen. El sonido solo llega a la consola en la **Famicom** (en el NES el pin
EXP no está conectado).

## En el menú

**Select+Start** abre «Opciones». **◀ ▶** cambian el volumen de **−4 a +4** (mantenidos, se repiten); **0** es el
volumen calibrado de cada chip. **B** o **Start** vuelven a la lista. El paso se guarda en la PRG-RAM con pila
(banco 8, `$6120`: `N8OP`, paso 0-8, suma `$5A` + paso) y se aplica a todos los juegos que se lancen después; si la
firma o la suma no valen (RAM sin pila, primera vez), el volumen es el calibrado.

Cada paso es ~3 dB (×√2): de ×1/4 (−4) a ×4 (+4). Con +3 y +4 los chips que ya suenan fuerte pueden recortar en
los picos (la etapa satura en el fondo de escala, nunca da la vuelta).

## En la FPGA

- **Reg 137** (modo OS, propio): paso 0-8 (4 = calibrado). Vale 4 al configurar la FPGA, así que un OS que no lo
  escriba (el v13 de fábrica) deja el volumen calibrado; un valor mayor que 8 también. El lanzador lo escribe tras
  los 132-136 (`os/src/lanzar.s`).
- `audio_dac.v`: `salida = centro_sal + (nivel − centro_ent) × ganancia / 256`, calculada a 14 bits (×16) y
  saturada, después del filtro que espera dos muestras iguales del nivel (dominio de 50 MHz, dos registros más).
  El modulador sigma-delta trabaja a 14 bits: con ganancia 256 (×1) la densidad de pulsos es nivel / 1024, igual
  que antes, y con ganancias pequeñas no se pierde resolución (el FDS en −4 sigue teniendo sus 64 niveles).
- N163 (reposo 240) y VRC7 (reposo 512) son bipolares: la ganancia se aplica alrededor del reposo, que va al centro
  de la salida (512), para que no recorten antes por un lado.
- `n8_top.v`, función `ganancia(chip, paso)`: tabla generada por `hdl/tools/gen_ganancia.py`.

## Ganancia base de cada chip (provisional)

Hasta la calibración, la proporción entre chips es la de la mezcla de Mesen2 (`NesSoundMixer::GetOutputVolume`,
medida por sus autores sobre consolas reales), tomando el **VRC6 como referencia** (ganancia ×1: suena igual que
en la v0.6.0):

| Chip | Nivel del HDL | Peso en Mesen2 | Unidades de Mesen2 por nivel | Ganancia base (/256) | Máximo en paso 0 |
|---|---|---|---|---|---|
| VRC6 | (pulsos + sierra) × 8, hasta 488 | ×75 (15 × 5) | 9,375 | 256 (×1) | 488 |
| FDS | nivel 0-63 × 16 | ×20 | 1,25 | 34 (×0,13) | 134 |
| Sunsoft 5B | suma de la tabla, hasta 531 | ×15 | 15 | 410 (×1,6) | 850 |
| Namco 163 | 240 ± media × 2 | ×20 | 10 | 273 (×1,07) | 512 ± 256 |
| VRC7 | 512 + muestra / 16 | ×1 | 16 | 437 (×1,71) | 512 ± (según el juego) |
| MMC5 | pulsos + PCM, hasta 285 | ×43 | 43 | 1174 (×4,6) | 137 (pulsos), satura con PCM alto |
| tono de prueba (mapper 247) | 192 | — | — | 256 (×1) | 192 |

Así el fondo de escala del convertidor (1023) equivale a unas 9600 unidades de Mesen2, casi el doble del máximo del
APU (~5000): queda margen para los chips más fuertes. Lo que no se sabe sin medir es **cuánto suena el pin 97 frente
al APU** en la Famicom (depende del filtro y de la resistencia de mezcla de la placa): eso lo fija la calibración.

## Calibración en la Famicom (pendiente)

1. Una ROM de prueba propia por chip que alterne, cada segundo, una nota del APU (pulso a volumen 15, ciclo 50 %) y
   una del chip a volumen conocido (en el FDS, un disco de prueba).
2. Grabar el audio de la Famicom por la capturadora (HDMI del GBSC) y medir el nivel de las dos notas.
3. Comparar la proporción con la de Mesen2 para esas mismas notas y ajustar el factor común (y, si un chip se aparta,
   su base) en `gen_ganancia.py`; regenerar la tabla de `n8_top.v` y compilar los RBF.

## Pruebas

- `make -C hdl sim TBS=tb_sonido`: la densidad de pulsos del VRC6 en los 9 pasos, la saturación con ×4, el paso por
  defecto y fuera de rango, que se conserva al volver al menú, las ganancias base y el centro del N163 y el VRC7.
- `os/herramientas/probar_os.py`, bloque «opciones»: la pantalla, ◀▶ con tope y repetición, B y Start vuelven a la
  lista igual que estaba, lo guardado en el banco 8, el reg 137 al lanzar, al encender con la RAM con pila, con la
  suma mal y con la RAM a cero.
