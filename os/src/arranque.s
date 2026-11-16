; arranque.s — entrada del OS propio del EverDrive N8 clon: clasifica el arranque y deja el hardware en un estado
; conocido. GPL-3.0-or-later. Ver docs/bios-n8-clon.md §1, §3, §4 y §7.
;
; Por dónde entra la CPU en $8000 (siempre en modo OS: el FPGA con el mapper $FF y el reg 9 del CPLD = x1):
;   FRÍO    la BIOS acaba de cargar el OS.BIN (encendido): la zona de estado de la imagen llega a cero.
;   RESET   botón RESET o reset del kit Lava (Select ~2 s y luego Select+A) estando en el OS. No pasa por la BIOS:
;           la CPU usa el vector RESET que dejamos en la RAM. Con el Lava llegan varios seguidos (unos 0,7 s cada
;           1,4 s mientras se mantiene Select+A), así que esta entrada tiene que ser rápida y repetible.
;   VUELTA  igual que RESET, pero estábamos en un juego: el RBF del juego vuelve al modo OS cuando M2 se para (botón
;           RESET, o el Lava mantenido unos 5 s; con un reset corto del Lava el juego solo vuelve a arrancar y aquí no
;           entramos). La RAM de la CPU, la PPU, la APU y el reg 9 llegan como los dejó el juego.
; Contrato con el lanzador de juegos (etapa 3): justo antes de escribir el reg 131, poner `en_juego` = 1 y guardar en
; `ultimo_juego` lo que haga falta para volver a él (por ejemplo, el índice en la lista). Aquí se lee y se borra.
;
; La zona de estado (segmento ESTADO, $FB00) forma parte del OS.BIN, que vive en la PRG-RAM: sobrevive a los resets y
; la BIOS la vuelve a poner a cero al cargar el archivo en cada encendido.

        .setcpu "6502"

        .include "os.inc"
        .export reset, nada
        .export tipo_arranque, arranques, resets, vueltas, ultimo_juego, en_juego
        .export e_a, e_x, e_y, e_s, e_p, e_regs, e_4403
        .import principal, nmi

REG9_OS   = %00000001           ; reg 9 del CPLD en el OS: bits 1:0 = 01 ($8000-$FFFF = PRG-RAM), sin más bits.
                                ; Es lo que deja la BIOS. Un juego (o el lanzador del v13) puede haber puesto los
                                ; bits 2-4; los bits 1:0 no cambian (estamos corriendo en esa RAM).

; ------------------------------------------------------------------------------------------------ estado
        .segment "ESTADO"
firma:          .res 4          ; "N8OS" cuando el estado es válido (si no, arranque en frío)
tipo_arranque:  .res 1          ; TIPO_FRIO, TIPO_RESET o TIPO_VUELTA
arranques:      .res 1          ; entradas desde la última carga de la BIOS (la primera es la del frío)
resets:         .res 1          ; resets dentro del OS
vueltas:        .res 1          ; vueltas desde un juego
en_juego:       .res 1          ; lo pone el lanzador antes de saltar al juego
ultimo_juego:   .res 2          ; lo deja el lanzador; el menú lo usa para poner el cursor
e_a:            .res 1          ; registros de la CPU al entrar (diagnóstico)
e_x:            .res 1
e_y:            .res 1
e_s:            .res 1
e_p:            .res 1
e_regs:         .res 6          ; regs 2, 9, 10, 138, 139, 140 al entrar, antes de tocar nada
e_4403:         .res 1

; ------------------------------------------------------------------------------------------------ entrada
        .segment "ARRANQUE"

; $8000. El primer byte no puede ser $EA: el 255.RBF de fábrica activaría su cargador (bios-n8-clon.md §4).
reset:
        sei                             ; $78
        sta     e_a
        stx     e_x
        sty     e_y
        php
        pla
        sta     e_p
        tsx
        stx     e_s
        cld
        ldx     #$FF
        txs

        ; registros del CPLD tal como llegan (solo lectura)
        ldx     #0
@regs:  lda     regs_medidos,x
        sta     REG_SEL
        lda     REG_DAT
        sta     e_regs,x
        inx
        cpx     #6
        bne     @regs
        lda     CPLD_EST
        sta     e_4403

        ; clasificar
        ldx     #3
@firma: lda     firma,x
        cmp     texto_firma,x
        bne     @frio
        dex
        bpl     @firma
        lda     en_juego
        beq     @reset
        lda     #0
        sta     en_juego
        inc     vueltas
        lda     #TIPO_VUELTA
        bne     @tipo
@reset: inc     resets
        lda     #TIPO_RESET
        bne     @tipo
@frio:  lda     #0                      ; estado nuevo
        ldx     #(e_a - firma - 1)
@cero:  sta     firma,x
        dex
        bpl     @cero
        ldx     #3
@copia: lda     texto_firma,x
        sta     firma,x
        dex
        bpl     @copia
        lda     #TIPO_FRIO
@tipo:  sta     tipo_arranque
        inc     arranques

        ; hardware a un estado conocido (valga para frío, reset y vuelta de un juego)
        lda     #0
        sta     PPUCTRL                 ; sin NMI
        sta     PPUMASK                 ; sin dibujar
        sta     APU_DMC                 ; sin IRQ del DMC
        sta     APU_EST                 ; canales callados
        lda     #$40
        sta     APU_CONT                ; sin IRQ de la secuencia de la APU
        bit     APU_EST                 ; borrar IRQ pendientes
        lda     #9
        sta     REG_SEL
        lda     #REG9_OS
        sta     REG_DAT

        ; vectores propios en la RAM (la BIOS dejó los suyos al copiar su página $FC00)
        lda     #<nada                  ; NMI provisional (está apagada) hasta tener la de verdad
        sta     $FFFA
        lda     #>nada
        sta     $FFFB
        lda     #<reset
        sta     $FFFC
        lda     #>reset
        sta     $FFFD
        lda     #<nada
        sta     $FFFE
        lda     #>nada
        sta     $FFFF

        ; RAM de la CPU a cero (la pila está vacía: no hemos llamado a nada)
        lda     #0
        tax
@ram:   sta     $0000,x
        sta     $0100,x
        sta     $0200,x
        sta     $0300,x
        sta     $0400,x
        sta     $0500,x
        sta     $0600,x
        sta     $0700,x
        inx
        bne     @ram

        ; la PPU se resetea con la consola: esperar a que arranque (dos VBlank)
        bit     PPUSTATUS
@vb1:   bit     PPUSTATUS
        bpl     @vb1
@vb2:   bit     PPUSTATUS
        bpl     @vb2

        ; ahora sí, la NMI de verdad
        lda     #<nmi
        sta     $FFFA
        lda     #>nmi
        sta     $FFFB
        jmp     principal

nada:   rti

        .segment "RODATA"
texto_firma:
        .byte   "N8OS"
regs_medidos:
        .byte   2, 9, 10, 138, 139, 140

; La BIOS pisa estos vectores con los suyos al copiar su página $FC00; los de verdad se escriben en `reset`.
        .segment "VECTORS"
        .word   nada, reset, nada
