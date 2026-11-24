; opciones.s — pantalla de opciones del menú (Select+Start). GPL-3.0-or-later, código propio.
;
; Por ahora una opción: el volumen del sonido de expansión (FDS, VRC6, VRC7, 5B, N163, MMC5; solo llega a la consola
; en la Famicom). ◀▶ cambian el paso de -4 a +4 (vol_reg 0-8; el 0 = 4 = el volumen calibrado de cada chip, ver
; hdl/rtl/n8_top.v), B o Start vuelven a la lista y lo guardan en el banco 8 (PRG-RAM con pila, $6120: "N8OP", paso,
; suma $5A + paso). El lanzador lo escribe en el reg 137 del FPGA (docs/sonido-volumen.md); opc_cargar
; (principal.s) lo lee al arrancar.
;
; No cabe en la ROM del OS: va en el segmento FDSOVL, con el código del FDS, en el banco 8 ($7000-$7FFF). Se llama
; con el banco 8 en la ventana $6000 (principal.s: opciones) y no cambia el reg 129 mientras corre. Ocupa las filas
; 7-25 de la pantalla, que son las que la lista vuelve a escribir al salir (subir_filas).

        .setcpu "6502"
        .include "os.inc"

        .export opc_pantalla
        .import vol_reg, ppu_dir, textos_fijos, espacio, sin_scroll, repetir, subir_filas, reencender, firma_opc
        .importzp ptr, nmis, botones, antes, nuevos, fila_sub, filas_pend, sel_ant

FILAS    = 16                   ; como principal.s
NT       = $2000
OPC      = $6120
FILA_ENC = NT + 7 * 32 + 2      ; la cabecera de la lista
FILA_OPC = NT + 10 * 32
FILA_VOL = FILA_OPC + 2 * 32 + 4

.macro en dir
        lda     #>(dir)
        ldx     #<(dir)
        jsr     ppu_dir
.endmacro

.macro texto dir, cad
        .byte   >(dir), <(dir)
        .byte   cad, 0
.endmacro

        .segment "FDSOVL"

opc_pantalla:
        lda     #0
        sta     PPUMASK
        en      FILA_ENC - 2            ; filas 7-25 en blanco
        ldx     #19
@f:     ldy     #32
@c:     jsr     espacio
        dey
        bne     @c
        dex
        bne     @f
        lda     #<textos_opc
        sta     ptr
        lda     #>textos_opc
        sta     ptr+1
        jsr     textos_fijos
        jsr     opc_valor
        lda     #$FF                    ; Select+Start, todavía pulsados, no cuentan
        sta     antes
        lda     nmis
@vb:    cmp     nmis
        beq     @vb
        jsr     sin_scroll
        lda     #%00001010
        sta     PPUMASK
@bucle: lda     nmis
@vb2:   cmp     nmis
        beq     @vb2
        lda     antes
        eor     #$FF
        and     botones
        sta     nuevos
        lda     botones
        sta     antes
        jsr     repetir                 ; mantener ◀ o ▶ repite
        lda     nuevos
        lsr                             ; derecha
        bcc     @izq
        lda     vol_reg
        cmp     #8
        bcs     @izq
        inc     vol_reg
@izq:   lda     nuevos
        and     #%00000010
        beq     @pinta
        lda     vol_reg
        beq     @pinta
        dec     vol_reg
@pinta: jsr     opc_valor               ; en el VBlank: 15 bytes
        jsr     sin_scroll
        lda     nuevos
        and     #%01010000              ; B o Start: volver
        beq     @bucle
        jsr     opc_guardar
        lda     #0
        sta     PPUMASK
        sta     fila_sub                ; la lista otra vez: cabecera, las 16 filas y la información
        ldx     #FILAS + 2
        stx     filas_pend
        jsr     subir_filas
        lda     #$FF                    ; el cursor se vuelve a pintar
        sta     sel_ant
        jmp     reencender

; El paso en pantalla: «◀ -2 ▶  ===------» (signo, cifra y una barra de 9).
opc_valor:
        en      FILA_VOL
        lda     #C_IZQ
        sta     PPUDATA
        jsr     espacio
        ldx     #'+'
        lda     vol_reg
        sec
        sbc     #4
        bcs     @pos
        eor     #$FF                    ; negativo: el valor absoluto (acarreo = 0: +1)
        adc     #1
        ldx     #'-'
@pos:   bne     @sig
        ldx     #' '                    ; el 0, sin signo
@sig:   stx     PPUDATA
        ora     #'0'
        sta     PPUDATA
        jsr     espacio
        lda     #C_CURSOR
        sta     PPUDATA
        jsr     espacio
        jsr     espacio
        ldx     #0
@b:     lda     #C_BLOQUE
        cpx     vol_reg
        bcc     @p
        beq     @p
        lda     #'-'
@p:     sta     PPUDATA
        inx
        cpx     #9
        bne     @b
        rts

opc_guardar:
        ldx     #3
@f:     lda     firma_opc,x
        sta     OPC,x
        dex
        bpl     @f
        lda     vol_reg
        sta     OPC+4
        clc
        adc     #$5A
        sta     OPC+5
        rts

textos_opc:
        texto   FILA_ENC,               "Opciones"
        texto   FILA_OPC + 2,           "Volumen del cartucho"
        texto   FILA_OPC + 4 * 32 + 2,  "0 = calibrado (de -4 a +4)"
        texto   FILA_OPC + 6 * 32 + 2,  "Solo se oye en la Famicom:"
        texto   FILA_OPC + 7 * 32 + 2,  "FDS VRC6 VRC7 5B N163 MMC5"
        texto   NT + 24 * 32 + 2,       {C_IZQ, C_CURSOR, " cambiar   B volver"}
        .byte   $FF
