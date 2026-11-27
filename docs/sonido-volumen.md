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
- N163 (reposo 240) y VRC7 (reposo 512) son bipolares (el N163, desde el 2026-11-26, alterna sus canales como el chip
  real; la calibración se hizo con un canal, así que no cambia): la ganancia se aplica alrededor del reposo, que va al centro
  de la salida (512), para que no recorten antes por un lado.
- `n8_top.v`, función `ganancia(chip, paso)`: tabla generada por `hdl/tools/gen_ganancia.py`.

## Ganancia base de cada chip (calibrada en la Famicom el 2026-11-24)

Punto de partida: la proporción de mezcla de Mesen2 (`NesSoundMixer::GetOutputVolume`), con el VRC6 como referencia.
Después se midió en la consola cuánto suena cada chip frente al APU y se corrigió cada base para que la proporción
sea la de Mesen2:

| Chip | Nivel del HDL | Peso en Mesen2 | Chip / APU en Mesen2 | Medido con la base de Mesen2 | Corrección | Base (/256) |
|---|---|---|---|---|---|---|
| VRC6 | (pulsos + sierra) × 8, hasta 488 | ×75 (15 × 5) | 1,506 | 1,136 | ×1,326 | 256 → **339** |
| FDS | nivel 0-63 × 16 | ×20 | 1,687 | 1,327 | ×1,272 | 34 → **43** |
| Sunsoft 5B | suma de la tabla, hasta 531 | ×15 | 3,555 | 2,709 | ×1,312 | 410 → **537** |
| Namco 163 | 240 ± media × 2 | ×20 | 6,025 | 4,827 | ×1,248 | 273 → **341** |
| VRC7 | 512 + muestra / 16 | ×1 | 4,257 | 3,399 | ×1,252 | 437 → **547** |
| MMC5 | 2 × pulsos + PCM × 33/32, hasta 322 (desde el 26-11; antes pulsos + PCM y base 1519) | ×21,5 | 0,864 | 0,668 | ×1,294 | 587 → **760** |
| tono de prueba (mapper 247) | 192 | — | — | — | — | 256 |

«Chip / APU» es la amplitud de la nota de 440 Hz del chip a su volumen máximo frente al pulso 1 del APU a volumen 15.
Las proporciones de Mesen2 entre chips se cumplen en la consola con un ±3 %: solo faltaba un factor común de ~×1,28.
Se usa la corrección medida de cada chip (la diferencia entre ellas, ±0,25 dB, no se oye).

**Recorte:** con el volumen calibrado, casi nada llega al fondo de escala del convertidor. Solo el 5B con sus tres canales a volumen 15 a la vez. Con pasos positivos recortan antes los
chips más fuertes (5B, N163, VRC7): es el precio de subir el volumen.

## Calibración (`tools/calibracion`, 2026-11-24)

- Famicom AV (con kit Lava RGB → GBS-Control → capturadora HDMI MS2109, audio a 48 kHz) y el **N8 de Famicom**, con
  la v0.6.1-beta (la primera vez que nuestro OS y nuestro 255.RBF corren en el N8 de Famicom: arrancan bien).
- `cal.s` (una ROM por chip: VRC6, 5B, N163, VRC7, MMC5, y un disco para el FDS) alterna 1 s del pulso del APU, 0,5 s
  de silencio, 2 s del chip y 0,5 s de silencio, todo a ~440 Hz. Validadas en Mesen2 con N8_AUDIO: los niveles son
  los mismos con su mapper y con nuestro HDL.
- `medir.py` graba 16 s, separa los tramos por duración y compara la amplitud de la fundamental de 440 Hz
  (los filtros de la consola, del GBS-Control y de la capturadora afectan igual a las dos notas). La dispersión entre
  tramos de una grabación fue del 0,0 %; el nivel del APU varió un ±4 % entre grabaciones (por eso se mide la
  proporción dentro de cada una).
- **Comprobación con los RBF calibrados** (misma tarde, mismas ROMs): chip / APU medido frente a Mesen2: VRC6 1,532
  (1,506), 5B 3,610 (3,555), N163 5,940 (6,025), MMC5 0,875 (0,864), VRC7 4,260 (4,257), FDS 1,687 (1,687). Todos a
  menos de un 1,7 % de Mesen2 (±0,15 dB).
- **Repetición** (otra sesión, tras apagar y encender): VRC6 1,607, 5B 3,740, N163 6,118, MMC5 0,898, VRC7 4,357,
  FDS 1,721 (entre +1,5 % y +6,7 %). La amplitud de cada chip fue la misma que en la comprobación anterior, con un 0,1 %
  de diferencia; lo que cambió fue el pulso del APU (un ~3 % más bajo). La salida del cartucho es estable y la
  proporción oscila un ±3 % (±0,3 dB) entre sesiones por la propia consola, así que no se recalibra. Con el N163 y el
  VRC7 (reposo a media escala) el APU sale un ~3,5 % más bajo en las dos tandas.
- `medir.py` descarta los tramos cortados por el principio o el final de la grabación. Antes, el final de una nota
  del chip cortado a 0,72 s se contaba como un tramo del APU (el «tramo irregular» del FDS en la comprobación).
- Lección: el reset del kit Lava solo funciona si el programa lee el mando. Las primeras ROMs no lo leían; ahora
  `cal.s` lo lee en cada fotograma.

## Pruebas

- `make -C hdl sim TBS=tb_sonido`: la densidad de pulsos del VRC6 en los 9 pasos, la saturación con ×4, el paso por
  defecto y fuera de rango, que se conserva al volver al menú, las ganancias base y el centro del N163 y el VRC7.
- `os/herramientas/probar_os.py`, bloque «opciones»: la pantalla, ◀▶ con tope y repetición, B y Start vuelven a la
  lista igual que estaba, lo guardado en el banco 8, el reg 137 al lanzar, al encender con la RAM con pila, con la
  suma mal y con la RAM a cero.

## Famicom, 2026-11-26: N163 alternando canales y MMC5

Grabado con la capturadora (MS2109, 48 kHz) con el 102.RBF que alterna los canales del N163:
- Erika to Satoru (8 canales): pico de **+32,8 dB** sobre el fondo en 14 750 Hz, el pitido de la alternancia
  (1 789 773 / 120 = 14 915 Hz; el 1 % de diferencia es del reloj de la capturadora). Música a −25 dBFS.
- Megami Tensei II: pico de +13,5 dB a 15 kHz (menos canales a la vez); la intro (con su estática de televisión)
  igual que en Mesen2.
- Just Breed (MMC5): la música de la intro suena a −27 dBFS; las pantallas de partidas y nombre no tienen música
  (en Mesen2 tampoco).
- El PCM del MMC5 (voces de Shin 4 Nin Uchi Mahjong): ver la sección siguiente.

## Famicom, 2026-11-26: PCM del MMC5 frente al DMC

NESdev (MMC5_audio): el PCM ($5011) es «equivalent in volume to the APU with equivalent input» y, con su bit de
más, puede sonar el doble que el DMC. Mesen2 (y nuestro RTL hasta la v0.6.5) le daba el mismo peso que a un paso de
pulso. Los hilos del foro de NESdev no traen medidas. Se mide con la consola como referencia, igual que el volumen:
- `CAL PCM.nes` (cal.s con `CHIP=7`, mapper 5): onda cuadrada de 437 Hz entre los niveles 1 y 65 durante 1 s en el
  DMC del APU ($4011) y 2 s en el PCM ($5011), hecha con un bucle de CPU. `medir.py PCM` da la proporción PCM / DMC.
  Mesen2 daría 1,575 (su DMC no lineal frente al PCM sumado a los pulsos); NESdev, 1.
- **Con el 103.RBF de la v0.6.5: 1,934 y 1,949.** En Shin 4 Nin las voces saturaban la capturadora (pico 1,0) y el
  sonido más fuerte llegaba a 10 veces la música.
- **Arreglo** (`snd_mmc5.v`): nivel = 2 × (pulso 1 + pulso 2) + PCM + PCM / 32, o sea el PCM a 33/64 = 0,516 de un paso
  de pulso, sin multiplicador y sin perder los 8 bits. La base del MMC5 pasa de 1519 a 760, así que los pulsos suenan
  igual que antes. Con el máximo (322) el convertidor ya no recorta (956 de 1023 con el paso 0).
- **Con el RBF nuevo: 1,105 y 1,105** (otra sesión, tras apagar). El PCM bajó lo previsto (×0,527 frente a ×0,516),
  pero el DMC de la consola midió un 8 % menos que en la primera sesión: los pesos que darían 1 en cada sesión son
  0,515 y 0,467, y el elegido queda dentro de esa variación (±0,5 dB). En Shin 4 Nin ya no satura (pico 0,83) y el
  sonido más fuerte queda a 5 veces la música.
- El banco compara con el Mesen2 local, que registra en `Mmc5Audio.h` la misma escala (parche en
  `tools/mesen2-n8.patch`): `CAL PCM` sale idéntico ciclo a ciclo. El modo lectura y la IRQ del PCM, que Mesen2 no
  implementa, siguen cubiertos solo por `tb_snd_mmc5`.
