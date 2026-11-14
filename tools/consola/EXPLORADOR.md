# Bot explorador v2: recorridos propios por género

El bot prueba acciones en Mesen2 con su mapper nativo y exporta los botones por
fotograma a FM2. La NES reproduce después esa misma secuencia con el Nano.
No es una red neuronal entrenada y no exige GPU.

## Estado comprobado

Implementado y probado con imágenes, grafos y un emulador simulado en las pruebas
de software. **No se han ejecutado juegos con este bot en Mesen2 ni en la NES.**
Las mejoras no tienen todavía una medida de rendimiento en juegos reales. No se
promete completar toda la biblioteca. El controlador visual anterior de SMB es
un experimento separado.

## Mejoras

- Archivo acotado de rutas hacia celdas visuales: vuelve a ramas anteriores cuando
  una ruta se estanca. Las visitas, fallos y acciones probadas modifican la selección.
- Cada intento reproduce su prefijo desde encendido. No introduce savestates,
  trucos ni escrituras externas en RAM. No usa direcciones de RAM para decidir.
- Acciones compuestas con pulsación/liberación, disparos periódicos, saltos y combos.
  Duraciones de medio bloque, un bloque o dos, dentro del horizonte configurado.
- Arranques alternativos con Start, A y Start seguido de A. Propone acciones de
  menú y recuperación al detectar indicios de estancamiento; no reconoce por ello
  con certeza una muerte o un menú.
- ROI visual configurable, imágenes reducidas/cuantizadas, distancia entre celdas
  y mediana temporal causal. Penaliza bucles, capturas uniformes y estancamiento.
  No elimina todo el parpadeo ni distingue por sí sola títulos y partidas.
- Guarda historial y archivo durante la búsqueda. Los intentos quedan para inspección
  si se interrumpe, pero no se reanuda exactamente la búsqueda interna de ese juego.
- Exporta la mejor ruta a `recorrido.fm2` y alternativas a `rutas/01`, `rutas/02`, etc.,
  cada una con manifiesto propio. `solo_arranque` identifica rutas sin extensiones.

La novedad visual **no mide cobertura RTL ni demuestra superar niveles**. El archivo
conserva puntos finales evaluados, no todos los estados internos del emulador.
Regresar desde encendido vuelve a ejecutar prefijos y aumenta el coste con la longitud.

## Géneros y controles

Hay 16 perfiles: genérico, plataformas, acción cenital, lucha, beat 'em up,
carreras, deportes, puzle, rol, estrategia, pinball, multijuego, disparos horizontales,
disparos verticales, el alias antiguo `disparos` y un perfil para periféricos.
Cada vocabulario distingue fases `menu`, `juego` y `recuperacion`.

El [plan de 204 ROMs](datos/plan_explorador.md) propone géneros por reglas de título,
**nunca por el mapper**; todas las propuestas están marcadas para revisión.
A no es siempre salto ni B siempre ataque. Las ROMs sin clasificación suficiente
mantienen el perfil genérico. Las cabeceras que declaran periféricos especiales se
separan de la ejecución con mando estándar. Esto no significa que todos sus modos
necesiten ese periférico: hay que revisar un modo de mando compatible.

Los vocabularios están en `perfiles/explorador.json`. El generador
`perfiles/generar_explorador.py` los reconstruye y sobrescribe ese archivo.
Los ajustes particulares deben ir en `perfiles/juegos_explorador.json`.

## Objetivos por ROM

`juegos_explorador.json` tiene un objeto `por_sha256` indexado por el SHA256 exacto
de la ROM. Puede ajustar arranque, acciones, visión y objetivos de un juego sin
alterar los demás del género. **No hay victorias reales configuradas o validadas.**

Un objetivo visual requiere `nombre`, `tipo` (`nivel`, `juego`, `menu` o `muerte`),
`rom_sha256`, `plantilla`, `roi`, `consecutivas` y `error_maximo`. La plantilla debe
coincidir con la ROI, tener al menos 256 píxeles y no ser uniforme. Se exigen al
menos dos capturas consecutivas. Se verifican los hashes de ROM y plantillas.

Coincidir confirma que se observó **la plantilla configurada**. Su significado de
victoria o muerte debe etiquetarse y validarse para ese juego; un recorte ambiguo
puede dar falsos positivos. Sin objetivos, `nivel_completado` y `juego_completado`
quedan sin confirmar.

## Repetición

`verificar` inicia una ejecución independiente sin reutilizar capturas anteriores.
Compara píxeles RGB en los puntos de captura, primer LATCH y archivo completo de
lecturas del mando. Comprueba hashes de ROM, FM2, motores, Mesen, Lua, ajustes,
perfiles y plantillas. No compara todos los fotogramas ni todos los estados internos.
Una repetición idéntica en Mesen sigue pendiente de comparación en la NES: el
estado inicial real y la alineación tras el menú N8 pueden producir diferencias.

## Uso preparado

No ejecutan emuladores ni hardware:

```bash
python3 -I tools/consola/explorador.py plan
python3 -m unittest discover -s tools/consola -p 'prueba_explorador*.py'
```

Los siguientes **sí ejecutan Mesen2**, pero no controlan hardware. Se dejan
preparados para un piloto posterior:

```bash
python3 -I tools/consola/explorador.py explorar \
  --rom "/ruta/a/juego.nes" --perfil auto --motor archivo \
  --evaluaciones 120 --profundidad 36 --bloque 90 --rutas 5 \
  --out tools/consola/informes/explorador-piloto
python3 -I tools/consola/explorador.py verificar \
  tools/consola/informes/explorador-piloto
```

Ese presupuesto permite rutas de hasta unos 60 segundos, sin garantizar alcanzar
esa longitud ni encontrar progreso. Los valores por defecto son 48 evaluaciones,
profundidad 16, bloques de 90, hasta 128 celdas y 3 rutas exportadas. El horizonte
es arranque más largo + profundidad × bloque, unos 30 segundos con estos perfiles.
`--motor haz` conserva el buscador inicial. `--ancho` controla ese haz antiguo;
`--archivo-max` controla el archivo v2. Más presupuesto consume CPU/disco y no
asegura mejor resultado.

```bash
python3 -I tools/consola/explorador.py lote \
  --out tools/consola/informes/explorador-lote --limite 3 --motor archivo
```

`--limite 204` permite intentar el plan completo. Los fallos se registran y no se
repiten salvo con `--reintentar-fallidas`. Los resultados completados se reutilizan
solo si coinciden archivos, objetivos y parámetros. El lote verifica la ruta
principal; las alternativas deben verificarse aparte:

```bash
python3 -I tools/consola/explorador.py verificar \
  tools/consola/informes/explorador-piloto/rutas/02
```

Para llevar después una película revisada a la NES se usa el banco existente.
**Este último comando sí controla la consola**; la ROM en la SD debe coincidir:

```bash
python3 -I tools/consola/prueba.py tas \
  --pelicula tools/consola/informes/explorador-piloto/recorrido.fm2 \
  --rom "PRUEBAS/ruta/juego.nes" --desfase 1
```

Ninguna de estas tandas se ejecutó al preparar la v2.

## Fuentes que orientaron el diseño

- [Go-Explore, Ecoffet et al.](https://arxiv.org/abs/1901.10995): conservar estados
  y regresar antes de explorar evita perder rutas prometedoras. Aquí se adapta a
  celdas visuales y retorno mediante botones desde encendido. No se implementa el
  algoritmo completo ni su robustificación por aprendizaje; no se trasladan sus
  resultados de Atari a NES.
- [Gym Retro: Game Integration](https://retro.readthedocs.io/en/latest/integration.html):
  distingue arranque, recompensa y condición de fin por juego. Aquí se separan
  acciones y objetivos visuales vinculados a la ROM, sin importar savestates ni
  direcciones de RAM.
- [Procgen, Cobbe et al.](https://arxiv.org/abs/1912.01588): estudia diversidad y
  generalización. Motiva evaluar distintos géneros y juegos; un éxito en SMB no
  demostraría que el bot funciona en toda la biblioteca.
