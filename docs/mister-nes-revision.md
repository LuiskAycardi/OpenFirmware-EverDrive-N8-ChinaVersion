# Revisión del core NES de MiSTer frente a nuestros mappers (2026-11-10)

Fuentes revisadas: https://github.com/MiSTer-devel/NES_MiSTer (clon de solo lectura, sin integrar en el
repo) y https://mister-devel.github.io/MkDocs_MiSTer/cores/highlights/nes/ (página de funciones: FDS con
cambio de cara automático, paletas, overscan, SNAC, "Extra Sprites"; sin datos de mappers).

## Licencia: cómo se puede usar
- **El core es GPL-3.0.** Copiar o traducir su RTL convertiría nuestro firmware en GPL-3. Se trata igual
  que Mesen2/Krikzz: **se lee para extraer hechos de comportamiento; el Verilog se escribe propio.**
- **Excepción: el sintetizador FM `rtl/SOUND/OPLL/VM2413` (Mitsutaka Okazaki, 2006)** tiene licencia tipo
  BSD: se puede redistribuir conservando el aviso, **pero la cláusula 3 prohíbe venderlo o usarlo en un
  producto comercial sin permiso**. Válido para uso personal o un proyecto abierto sin ánimo de lucro, con
  atribución; no es "open source" en sentido estricto. Decisión del usuario.

## Cobertura comparada
| | MiSTer | Nosotros |
|---|---|---|
| Mappers (< 256) | 144 + FDS (120 con savestate) | 180 |
| En común | 126 | 126 |
| Solo en uno | 18 (15 < 256 y 3 ≥ 256) | 54 |

- Tenemos 54 que MiSTer no soporta (casi todos multicarts y piratas de la lista v1.26: 12, 49–61, 115,
  117, 176, 182–188, 197–203, 213–222, 229–252…).
- De los 18 que solo tiene MiSTer, **14 no tienen ninguna ROM en la colección** (2993 ROMs): 39, 81, 83,
  162, 163, 194, 195, 208, 209, 218, 225, 255, 268, 413.
- Los útiles son:
  - **159** (6 ROMs: DBZ Kyoushuu Saiya Jin, Magical Taruruuto-kun 1 y 2, SD Gundam Gaiden).
  - **192** (2 ROMs: Ying Lie Qun Xia Zhuan, You Ling Xing Dong).
  - **153** (1 ROM: Famicom Jump II).
  - **547** (4 ROMs). Tiene número ≥ 256, que el MAPROUT de 1 byte del OS v13 no puede asignar: necesita
    nuestro propio OS.

## Oportunidades, por valor
1. **[HECHO 2026-11-10, ver `docs/fase4-mappers.md`] EEPROM 24C01/24C02 del Bandai FCG.** Nuestro `mapper_bandaifcg.v` dice "EEPROM no implementada".
   - La usan los guardados de **16 juegos del mapper 16** (DBZ II/III/Gaiden, SD Gundam Gaiden 2/3,
     Famicom Jump…).
   - Con un 24C01 es exactamente el **159** (+6 ROMs).
   - Implementación propia: máquina I2C desde la hoja de datos y NESdev (escritura en $800D bits 5 y 6,
     lectura del bit 4 en $6000). 256 bytes caben en un M4K.
   - Límite: dentro de la FPGA el contenido se pierde al apagar. Persistirlo exigiría reflejarlo en la
     PRG-RAM que guarda el OS; está por estudiar.
2. **[HECHO 2026-11-10, ver `docs/fase4-mappers.md`] 192 y 153, cambios pequeños.**
   - 192: variante Waixing del MMC3 con 4 KiB de CHR-RAM en los bancos 8–11, igual que los 74/191 que ya
     tenemos en `mapper_mmc3`.
   - 153: FCG con 8 KiB de SRAM y un bit de PRG exterior sacado de los registros de CHR.
3. **Sonido FM del VRC7 (85), solo Lagrange Point.** `mapper_vrc7.v` lo deja sin implementar.
   - Opción A: VM2413 (licencia anterior) en un RBF propio para el 85. Hay que medir los LE en el EP2C5.
   - Opción B: OPLL propio. Es un trabajo grande.
4. **Pista para el residual del MMC5 (diferencias en x0–23 en 3 juegos).**
   - MiSTer clasifica fondo y sprites contando **flancos de bajada de A13**, uno por tile.
   - El contador arranca en 2 al entrar en frame, va 0–1 en los dos tiles precargados, 2–33 en los
     visibles y 34–41 en los sprites; `is_sprite_fetch` se activa en 34 y se borra en 0.
   - Nuestro `mapper_mmc5.v` suma una vez **por lectura de NT**. En la fase de sprites la PPU hace dos
     lecturas basura de NT por sprite, así que nuestro contador podría avanzar el doble ahí.
   - Además, en MiSTer `$5204` borra el pendiente un ciclo después de la lectura.
   - Hay que verificarlo con trazas antes de cambiar nada.
5. **IRQ del JY (90): MiSTer no sirve de referencia.**
   - Cuenta solo con el IRQ activado, su prescaler descendente dispara en `==0` y pone el prescaler a 0
     en `$C002`.
   - Mesen2, contra el que validamos, se comporta de otra forma. Con dos emuladores en desacuerdo, el
     residual de ciclo del IRQ CpuClock solo se aclara en hardware real.
6. **FDS.** MiSTer lo tiene completo (disco, cambio de cara, audio). En el N8 hace falta que el OS cargue
   la imagen y cambie de cara: es un proyecto grande, para más adelante. `FDS.sv` sirve como referencia
   de hechos.

## Lo que no aplica al N8
En MiSTer la PPU está dentro de la FPGA y nosotros vamos en el bus del cartucho. Por eso no aplican:

- "Extra sprites".
- Savestates (la infraestructura de MiSTer).
- Paletas, overscan y región PAL/Dendy (las consolas son NTSC).
- SNAC.
- Mappers ≥ 256 sin un OS propio.

El límite físico del split del MMC5 (fine-Y en A0–A9) tampoco se resuelve con nada de MiSTer.
