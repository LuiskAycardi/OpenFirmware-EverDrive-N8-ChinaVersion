# OS propio del EverDrive N8 clon — etapa 1: «hola mundo»

Primer `OS.BIN` propio (GPL-3.0-or-later). Todavía no lanza juegos: arranca, pinta una pantalla con una fuente
propia y mide lo que falta saber del hardware (ver [docs/os-propio-viabilidad.md](../docs/os-propio-viabilidad.md)
§6 y [docs/bios-n8-clon.md](../docs/bios-n8-clon.md)). Funciona con el `255.RBF` de fábrica.

**Qué no hace**, a propósito: no escribe ningún registro del CPLD, no toca la flash de la BIOS, no lee ni escribe
la SD y no toca la PRG-RAM de las partidas ni el estado del OS de fábrica. Solo escribe en la RAM de la CPU, en su
propia imagen (`$8000-$FFFF`), en la PPU y en el reg 130 del FPGA (banco de la CHR, igual que el v13).

## Compilar y probar en el PC

```bash
make -C os
```

Sale `os/build/OS.BIN`: 32 KiB, primer byte `SEI` y la página `$FC00` vacía. `comprobar_os.py` comprueba
estos requisitos en cada compilación.

Prueba con la BIOS real en el modelo de `tools/bios` (la BIOS no está en el repo, ver
[tools/bios/README.md](../tools/bios/README.md)):

```bash
python3 -I os/herramientas/probar_hola.py --bios /ruta/bios.bin --rbf ~/SD_Pruebas/EDFC/MAPS/255.RBF --trabajo /tmp/carpeta-nueva
```

Comprueba que:
- la BIOS salta a `$8000` y aparece la pantalla;
- el mando se ve en vivo;
- un reset sin BIOS pone ARRANQUES a 02;
- el OS no escribe en ningún registro del CPLD, ni en la flash, ni en la SD;
- la PRG-RAM de las partidas queda intacta.

## Instalar en la SD de pruebas

1. **Antes de nada, arranca una vez el OS de fábrica** después de la última partida con pila. El v13 guarda las
   partidas pendientes al arrancar y el nuestro no lo hace.
2. En la SD, copia `EDFC/OS.BIN` (el v13, md5 `f5ac5490…`) como `EDFC/OS_V13.BIN`. Guarda también una copia en
   el PC.
3. Borra `EDFC/OS.BIN` y copia `os/build/OS.BIN` en su lugar. Deja el `255.RBF` de fábrica.
4. **El archivo tiene que quedar contiguo** (docs/bios-n8-clon.md §3). Con 32 KiB, basta con que el clúster de la
   SD mida 32 KiB o más. Para ver el tamaño del clúster:
   ```bash
   stat -f -c %S /run/media/tester/SD_N8
   ```
   Si sale menos de 32768 y la pantalla no aparece, prueba en una SD recién formateada.

Para volver: borra `EDFC/OS.BIN` y copia `EDFC/OS_V13.BIN` como `EDFC/OS.BIN`. Nada más cambia.

## Qué anotar en la consola (foto de la pantalla)

| Fila | Qué es | En el emulador |
|---|---|---|
| ARRANQUES | veces que ha entrado el OS desde la última carga de la BIOS | 01 |
| A X Y S P | registros de la CPU tal como los deja la BIOS | `01 FF 00 FB 35` |
| REG2 REG9 R10 | registros 2, 9 y 10 leídos por `$4401` al entrar | `09 01 00` (el modelo devuelve lo escrito) |
| R138 R139 R140 4403 | registros 138-140 y el estado `$4403` al entrar | `FF FF FF 01` (el modelo no sabe más) |
| REG2 REG9 R138 4403 (AHORA) | los mismos, en vivo | — |
| MANDO | botones pulsados: A B S(elect) T (Start) U (arriba) D (abajo) L (izquierda) R (derecha) | — |
| FOTOGRAMAS | contador que avanza: el OS sigue vivo | — |

Pruebas que hacer, anotando ARRANQUES y las filas de registros después de cada una:
1. **Encender:** debería salir ARRANQUES 01.
2. **Select+B del kit Lava** (reset de la consola): **02** = el reset vuelve al OS sin pasar por la BIOS (lo que
   creemos); **01** = la BIOS arranca de cero.
3. **Botón RESET de la consola:** igual que el anterior.
4. **Apagar y encender:** 01.
5. Pulsar cada botón y comprobar que aparece su letra.
6. Fijarse en si R138 cambia mientras se pulsa o se suelta el reset (el v13 espera a que deje de valer `52`).

Si la pantalla sale negra o gris, apaga, vuelve al v13 y dime qué color salió.
