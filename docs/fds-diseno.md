# Soporte del Famicom Disk System (FDS): diseño

Estado (2026-11-19): diseño decidido (BIOS del usuario en la SD, parcheada por nuestro OS). Hecho: análisis de
BIOS e imágenes (`tools/fds`, [fds-compatibilidad.md](fds-compatibilidad.md)) y reconocimiento en el OS (`os/src/fds.s`).

## El problema de fondo: la SRAM no se puede direccionar byte a byte
En el N8 clon, **A0-A9 de las SRAM (PRG, PRG-RAM y CHR) vienen directos del bus de la consola**; la FPGA solo pone
A10-A18 (`prg_map`/`chr_map`, ver `hardware-fpga.md`). El FDS real entrega el disco **byte a byte por un registro
fijo** (`$4031`): cuando la CPU lo lee, A0-A9 valen siempre `$031`, así que la FPGA no puede sacar «el byte N del
disco» de la SRAM en ese ciclo (solo llegaría a 512 posiciones por memoria). La RAM interna de la EP2C5 (26 M4K,
~13 KiB) tampoco da para una cara (65 500 B).

Hechos del 254.RBF de Krikzz (netlist de `~/n8-firmware/artifacts/ep2c5-handshake/mapper-signature/254.v`, solo
leído para entender, nada copiado): lleva **16 M4K de solo lectura = 8 KiB de código propio** (no es la BIOS de
Nintendo: 20 130 bits a uno frente a ~28 000 de cualquier BIOS FDS) y **8 M4K de 4096×1 que se llenan desde
`ppu_dat`** (un búfer de 4 KiB leído de la SRAM CHR por el lado de la FPGA, con el transceptor de la PPU cerrado).
O sea, él tampoco sirve `$4031` desde la SRAM tal cual.

**Esos 8 KiB son la BIOS de Nintendo Rev 1 modificada** (reconstruidos del netlist el 2026-11-18: cada bit coincide
con la Rev 1 en el ~87 %, mismo orden y polaridad; vectores idénticos). Difieren 1625 bytes en 23 tramos: parches
pequeños justo en las rutinas de disco (`$E1CE-$E1D2` transferencia por IRQ, `$E57A`, `$E6BB-$E734` control y
estado, `$EEBB-$EFEA`, `$F56D-$F5AC`) y ~1,7 KiB de código suyo en `$F735-$FE2D`. Es decir: Krikzz hizo lo mismo que
se propone aquí (parchear las rutinas de disco de la BIOS), pero **distribuye la BIOS de Nintendo dentro del RBF**,
cosa que un proyecto GPL no puede hacer. Nada de su código se usa: solo confirma qué rutinas hay que tocar.

## Propuesta: BIOS del usuario parcheada en memoria + ventana de disco
1. **BIOS**: la pone el usuario en la SD (no se distribuye: es de Nintendo), p. ej. `EDFC/DISKSYS.ROM` (8 KiB; se
   aceptan Rev 1, Rev 0 y Twin Famicom, comprobadas por CRC32; las de emulador no: GameCube, 3DS y Game & Watch
   llevan opcodes trampa o rutinas de disco vaciadas). Nuestro OS la copia a la SRAM PRG y le aplica **parches propios**
   (una lista de direcciones y bytes generada por nuestro código) solo en la copia en memoria.
2. **Disco en la SRAM PRG**, cara k en `k × 64 KiB` (65 500 B; las 396 imágenes de la colección tienen 1 o 2 caras,
   sin cabecera fwNES; caben hasta 7 caras). BIOS en `0x7E000`.
3. **Ventana de disco** propia del RBF 254: con un bit de habilitación (registro privado), `$4800-$4FFF` lee y
   escribe 2 KiB de la cara actual; un registro de banco da A11-A16 y la cara A17-A18. La CPU pone A0-A10, así que
   el problema de arriba desaparece. Fuera de la transferencia la ventana está apagada (bus abierto, como el FDS).
4. **Parches de la BIOS**: la transferencia real va por IRQ (`$4031` se lee solo en `$E1CE`/`$E1E5`, `$4024` se
   escribe en `$E1D1`/`$E6C0`; el control `$4025`/`$4030`/`$4032` en ~20 instrucciones de `$E6xx-$E7xx`, Rev 1).
   El paso de cada byte es `$E7A3` (`CLI` y `JMP *`: espera la IRQ del disco, cuyo manejador en `$E1C7` lee
   `$4031`, desapila y devuelve el byte) tras `$E794` (prepara `$0101` y `$4025`): enganchando esos dos puntos
   pasan por nuestra rutina todas las transferencias de la BIOS. Las de fin de bloque (`$E706`, `$E729`) leen el
   CRC y el estado; el HDL contestará «bien» o se enganchan también. En Rev 0 y Twin Famicom estas rutinas están
   en las mismas direcciones y son iguales byte a byte.
   Se cambian las rutinas de bajo nivel (empezar bloque, pasar byte, fin de bloque, disco listo) por otras que
   mueven una «cabeza» sobre la ventana. Todo lo que está por encima (LoadFiles, WriteFile, la pantalla de arranque
   y las rutinas de utilidad que llaman los juegos) queda intacto. Carga varias veces más rápida que el disco real.
5. **Cambio de cara automático**: el parche de «comprobar cabecera» busca entre las caras cargadas la que pide el
   juego (ID y número de cara) y la elige; si ninguna coincide, se comporta como la BIOS (pide el disco).
6. **RAM del FDS** (32 KiB en `$6000-$DFFF`): PRG-RAM, bancos 0-3. **CHR-RAM** 8 KiB en la SRAM CHR.
7. **Registros FDS en el HDL**: temporizador e IRQ (`$4020-$4022`, `$4023`), `$4025` (mirroring, motor, modo),
   `$4030`/`$4032` (estado: disco dentro, listo), `$4033` (batería bien). El sonido (`$4040-$4092`) en una etapa
   aparte; solo se oye en la Famicom.
8. **Guardar el disco**: la SRAM PRG no tiene pila. Al lanzar, el OS deja una marca «N8FD» con la ruta en el banco 8
   de la PRG-RAM (como «N8SV»). Al volver con RESET, el OS compara cada sector de 512 B de la SRAM con el `.fds` de
   la SD y escribe solo los que cambiaron. **Apagar sin RESET pierde lo escrito** (igual que en el N8 original):
   se avisa en el LEEME.

Límite conocido (medido: 17 de 396 en la colección, casi todos herramientas de copia): los juegos que traen **su propia rutina de disco** (leen `$4031` sin pasar por la BIOS) no
cargarán con este método. Se medirán con el banco; si son importantes, se estudia un camino por hardware (búfer M4K).

Alternativa a largo plazo: una **BIOS libre propia** (GPL) con las mismas direcciones de entrada que la de
Nintendo. Evita pedir la BIOS al usuario, pero es mucho más trabajo (los juegos llaman a decenas de rutinas).

## Resultado de F0 en la NES (2026-11-20)
- **La SRAM PRG se escribe en modo juego:** el disco puede vivir ahí y el juego escribirlo (448 KiB, 0 errores).
- **Las lecturas que conduce la FPGA no llegan en `$4000-$41FF`** (bus abierto) y sí en `$4200-$7FFF`. Por eso:
  - la BIOS parcheada no lee `$4030`/`$4031`/`$4032`: lee el estado y los datos por la ventana y por registros
    propios en `$42xx` o más arriba;
  - los juegos que leen `$4032` (340 de 396) verán `$40`: bit 0 = 0 (disco dentro), bit 1 = 0 (listo), bit 2 = 0
    (no protegido), que es justo lo que deben ver;
  - los que leen `$4030` para reconocer la IRQ del temporizador la reconocen igual (la FPGA ve la dirección aunque no
    pueda dar el dato), pero leerán `$40` (bit 6 = 1, «fin de la cabeza»); hay que comprobar que ninguno lo use;
  - las lecturas del sonido (`$4090`, `$4092`) dan `$40`; casi nadie las usa;
  - en el N8 de Famicom, sin transceptores, puede que todo llegue (sin medir).

## Etapas
- **F0, prueba en la consola** (hecha, ver arriba): un RBF mínimo que escriba la SRAM PRG en modo juego y conduzca lecturas en
  `$4020-$4FFF` (confirma que el CPLD no lo bloquea).
- **F1, HDL** (hecha el 2026-11-20): `hdl/rtl/mapper_fds.v` en el `254.RBF`, `hdl/sim/tb_fds.v` (con 5 mutaciones
  que el banco detecta). Mapa:
  - SRAM PRG: cara k en `k × 64 KiB` (k = 0-6), código del parche en `0x7D000` (4 KiB), BIOS en `0x7E000` (8 KiB).
  - CPU: `$E000-$FFFF` BIOS; `$6000-$DFFF` RAM de 32 KiB (PRG-RAM, bancos 0-3); `$5000-$5FFF` parche (solo
    lectura); `$4800-$4FFF` ventana del disco con `$4210` D0 = 1, cara en `$4212` (D2-D0) y banco de 2 KiB en
    `$4211` (D4-D0), los dos legibles; `$422E` = `$4030` (legible en la NES); `$4230` = `$4032` con «disco
    fuera» emulado y `$4231` = `$4033` = `$80` (ver F3).
  - FDS: `$4020-$4023` temporizador y habilitación, `$4025` D3 mirroring; `$4030` D0 IRQ / D3 mirroring (leerlo
    reconoce), `$4032` = dentro y listo, `$4033` D7 = batería bien (estas tres solo llegan si la placa lo deja).
  - Sin sonido (F6) ni IRQ del disco (la BIOS parcheada no la usa).
  testbench y mutaciones; MAPROUT[254] = 254.
- **F2, parches** (hecha el 2026-11-21): `os/src/fds_parche.s` (316 bytes en `$5000`, 383 tras F3, con su tabla de enganches) y
  `tools/fds/probar_parche.py` (6502 propio, modelo del mapper, PPU mínima; `--api` llama a `LoadFiles` en la cara 2
  y a `WriteFile`). Enganches de la Rev 1 (iguales en Rev 0 y Twin Famicom): `$E7A3` xfer, `$E794` inicio,
  `$E706`/`$E729`/`$E57A` fin (sin CRC), `$E64D` arranque (sin mirar la pila en `$4033`), `$E4D4` saltar (bytes
  que la BIOS se saltaba con IRQ del disco) y los 5 `JSR $E445` → `buscar_cara` (cambio de cara automático por el
  ID). La cabeza del disco vive en la FPGA (`$4213`-`$4216`): el parche no toca la RAM del juego.
  Resultado con la BIOS Rev 1 sobre los 364 discos «sí» del análisis: **327 todo bien** (arranque con los archivos
  idénticos al disco, cada archivo de la cara 2 por `LoadFiles` y `WriteFile` cambiando solo el byte tocado);
  14 sin archivos de arranque en la cara A (discos 2, «Kouhen»: tampoco arrancan en la consola); 7 con el mismo ID
  en las dos caras (el cambio automático no sabe elegir: hará falta cambiar la cara a mano); 16 con problemas de
  arranque (11 sin licencia o de desarrollo, Doremikko y Tantei Club II Kouhen), a mirar en F3 con Mesen2 (el banco
  no lleva la cuenta de ciclos real). Rev 0 y Twin Famicom: Zelda y Super Mario Bros. 2 arrancan igual.
  la versión; el parche va en el OS (código propio).
- **F3, simulador** (hecha el 2026-11-23): `tools/fds/comparar_mesen.py` pone cada `.fds` en el FDS de Mesen2 (BIOS
  sin tocar, cambio de cara automático) y el mismo disco como iNES 254 (la SRAM que dejará el OS) en Mesen2 con
  nuestro HDL (`tools/n8sim`), y mide cuántas pantallas del N8 salen también en la referencia. Resultados (BIOS Rev 1):
  - los 16 discos con arranque raro en el banco de Python: funcionan 14; fallan **Quick Hunter** (se queda en NOW
    LOADING, esperas en `$E157`/`$E1C5`, a investigar) y **Kosodate Gokko** (rutina de disco propia, esperado);
  - muestra de 26 discos «sí» (uno de cada 14): los 26 arrancan y juegan. Dos marcas falsas de la medida: Golf
    («distinto»: la demo sale con otro viento) y Fruits Mahjong 3 Disk 2 («quieto»: un disco 2 tampoco arranca en
    la referencia). Zelda y Super Mario Bros. 2 juegan igual que en la referencia.
  - **Quick Hunter y el cambio de cara, arreglados** (2026-11-23). Tres causas; la primera afecta a muchos más:
    1. **Sacar el disco.** 165 de los 396 discos esperan en `$4032` bit 0 a que se saque el disco antes de pedir
       la otra cara (Zelda, Metroid, SMB2, Quick Hunter…). En el N8 de NES `$4032` da `$40` (bus abierto): el
       disco nunca sale y el juego se cuelga. Arreglo: el HDL emula el «disco fuera» con el mismo criterio que
       el cambio automático de Mesen2 (más de 20 lecturas de `$4032` con huecos de menos de 100 fotogramas y
       77 fotogramas sin leer el disco → fuera 77 fotogramas, luego dentro), y lo da en `$4230`, que sí llega.
       Para que el juego lo lea, **el OS cambia la imagen al montarla en la SRAM** (`fds.cambiar_cara`): en los
       archivos de programa (también los ocultos), cada lectura absoluta (LDA/LDX/LDY/BIT/ORA/AND/EOR/CMP/CPX/
       CPY, también indexadas) de `$4030`/`$4032`/`$4033` pasa a `$422E`/`$4230`/`$4231`: byte bajo − 2 y byte
       alto + 2, así **la suma de los bytes no cambia** (Ai Senshi Nicol suma su código al arrancar y se reinicia
       si no cuadra: un primer filtro en la FPGA que solo cambiaba el byte alto lo rompía). Al guardar el disco
       en la SD, el OS lo deshace en las posiciones apuntadas (`fds.deshacer_cara`), solo donde el cambio sigue.
       En la colección: 340 discos, 1839 lecturas; en los 396 la suma de cada cara queda igual y deshacer da el
       disco original. La BIOS sigue viendo `$4032` = dentro.
    2. **Restos en la pila.** La BIOS espera cada byte con `CLI; JMP $E7A4`; la IRQ del disco apila `$E7`, `$A4`
       y P, y su manejador los desapila sin borrarlos. Quick Hunter lee ese resto (`$01F0` = `$A0`, código que
       ejecuta en `$6855`). El parche deja los mismos bytes en la pila en xfer, inicio y las dos esperas del CRC
       de fin (la segunda con N = 1, como tras `STA $4025`).
    3. **CheckDiskHeader directo.** El cambio de cara automático enganchaba las 5 llamadas de la BIOS a `$E445`,
       pero 18 discos la llaman ellos mismos (Doki Doki Panic se quedaba en «A B SIDE ERR 07», Shin Onigashima
       Zenpen, Deep Dungeon...). Ahora se engancha `$E445` (igual en Rev 0, Rev 1 y Twin Famicom): `buscar_cara`
       elige la cara, hace el `JSR $E6E3` que tapa el enganche y sigue en `$E448`. El parche mide 383 bytes.
    Resultado en Mesen2 (N8 simulado frente al FDS de Mesen2): el cambio de cara completo, con el «disco fuera»,
    funciona. Zelda saca el disco en el fotograma 640 y lee la cara B en el 719; Doki Doki Panic, en el 695 y el
    805; Ai Senshi Nicol ya no se reinicia y cambia en el 2573 y el 2653; Quick Hunter llega a las pantallas de
    la referencia. El banco de Python sobre los 364 discos «sí» da **336 todo bien**. Quick Hunter pasa a bien.
    Bishoujo Kachinuki Renju y Jingorou pasan a fallo, pero en el banco pasan o fallan según cuántas
    instrucciones cuente por fotograma, también con el parche anterior: activan la NMI escribiendo en `$2000`
    durante la carga, y el banco no cuenta ciclos. En Mesen2, que sí los cuenta, los dos juegan. Falta
    comprobarlo en la consola (F5).
- **F4, OS**: `.fds` en el menú, carga de BIOS y caras (con `cambiar_cara`), lanzamiento, marca N8FD, guardado al
  volver (con `deshacer_cara`).
- **F5, consola**: tanda de juegos FDS en la Famicom (y en la NES, sin sonido de expansión).
- **F6, sonido FDS**.
