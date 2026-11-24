# Disco de prueba del cambio de cara a mano

Un disco FDS de dos caras con el mismo ID (como los 14 de la colección en los que el cambio de cara automático no sabe
elegir). Su programa (`boton.s`) enseña cada fotograma:

| Fila | Qué es |
|---|---|
| `C` | la cara que tiene puesta la FPGA (`$4212`) |
| `N` | la cuenta del botón (`$4217`): fotogramas seguidos con B + Select; en `2D` (45) da la vuelta |
| `M` | cómo lee el mando: `0` = el programa lee `$4016` (prueba el espía de la FPGA), `1` = con ReadPads de la BIOS (prueba el aviso del parche). **A** cambia de modo |
| `P` | el mando tal como se leyó (A = bit 7 … derecha = bit 0) |

```bash
make -C tools/fds/prueba_boton
python3 -I tools/fds/prueba_boton/hacer_disco.py --kyodaku-de "/ruta/a/un/disco.fds"
```

La BIOS comprueba al arrancar el archivo de licencia del disco (`KYODAKU-`): `hacer_disco.py` lo copia de un disco
del usuario al hacer la imagen (`BOTON.fds`, que no entra en el repositorio).

Resultado en Mesen2 con nuestro HDL (2026-11-24): en modo 1, B + Select del fotograma 900 al 1000 → la cuenta sube
de 1 en 1 y en el fotograma 945 `C` pasa de 0 a 1; al soltar, `N` vuelve a 0. En modo 0 no cambia nada en Mesen2:
su puente no le pasa al modelo las lecturas de `$4016` (las atiende Mesen); el espía solo se puede probar en la
consola.

**En la NES (2026-11-24):** modo 1, igual que en Mesen2: `N` sube hasta `2D`, `C` pasa de 0 a 1 y, con otra
pulsación, de 1 a 0. Modo 0: `P` = `60` (el programa ve B + Select) pero `N` se queda en `00`: el N8 de NES no deja que
la FPGA vea el dato de `$4016`. RESET vuelve al OS bien («vuelta de juego»). Falta el N8 de Famicom.
