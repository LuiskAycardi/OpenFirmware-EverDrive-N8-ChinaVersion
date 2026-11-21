; f0.s — Prueba F0 del soporte FDS en la consola (docs/fds-diseno.md). GPL-3.0-or-later, código propio.
; Con el mapper 254 de prueba (hdl/rtl/mapper_prueba254.v) comprueba, con la pantalla apagada:
;   1. $40F1 se lee como $A5 (la FPGA conduce lecturas en $40xx);
;   2. $40F2 devuelve el banco escrito en $40F0 (los 256 valores);
;   3. la SRAM PRG se escribe en modo juego: un patrón distinto en cada banco $10-$FF de la ventana $4800 (448 KiB)
;      y luego se lee entero (un banco que se pisa con otro, o una línea de dirección pegada, da errores);
;   4. los bancos 0-15 vistos por la ventana son la propia ROM ($8000-$FFFF).
; Después enseña el resultado: fondo verde si todo va bien y rojo si algo falla, con una línea por prueba.

PPUCTRL   = $2000
PPUMASK   = $2001
PPUSTATUS = $2002
PPUSCROLL = $2005
PPUADDR   = $2006
PPUDATA   = $2007
BANCO     = $40F0
CONST     = $40F1
ECO       = $40F2
VENTANA   = $4800

        .segment "CABECERA"
        .byte   "NES", $1A, 2, 1, $E1, $F0, 0, 0, 0, 0, 0, 0, 0, 0     ; mapper 254, mirroring vertical

        .segment "ZEROPAGE"
p:      .res 2                  ; puntero a la ventana
q:      .res 2                  ; puntero a la ROM
banco:  .res 1
pag:    .res 1
xpag:   .res 1                  ; parte del patrón que cambia con la página de 256 bytes
err1:   .res 1
err2:   .res 1
err3:   .res 2
err4:   .res 2
t:      .res 2                  ; texto a escribir
fila:   .res 1

        .segment "CODE"
reset:  sei
        cld
        ldx     #$FF
        txs
        lda     #0
        sta     PPUCTRL
        sta     PPUMASK
        bit     PPUSTATUS
:       bit     PPUSTATUS
        bpl     :-
:       bit     PPUSTATUS
        bpl     :-
        ldx     #0
        stx     err1
        stx     err2
        stx     err3
        stx     err3+1
        stx     err4
        stx     err4+1
        ; ---- 1. $40F1 = $A5
@c1:    lda     CONST
        cmp     #$A5
        beq     :+
        inc     err1
:       dex
        bne     @c1
        ; ---- 2. eco del banco
@c2:    stx     BANCO
        cpx     ECO
        beq     :+
        inc     err2
:       inx
        bne     @c2
        ; ---- 3. escribir los bancos $10-$FF y leerlos
        lda     #$10
        sta     banco
@e3:    jsr     abrir
@ep:    ldy     #0
@eb:    tya
        eor     banco
        eor     xpag
        sta     (p),y
        iny
        bne     @eb
        jsr     sig_pag
        bne     @ep
        inc     banco
        bne     @e3
        lda     #$10
        sta     banco
@l3:    jsr     abrir
@lp:    ldy     #0
@lb:    tya
        eor     banco
        eor     xpag
        cmp     (p),y
        beq     :+
        inc     err3
        bne     :+
        inc     err3+1
:       iny
        bne     @lb
        jsr     sig_pag
        bne     @lp
        inc     banco
        bne     @l3
        ; ---- 4. bancos 0-15 = la ROM
        lda     #0
        sta     banco
        sta     q
        lda     #$80
        sta     q+1
@r4:    jsr     abrir
@rp:    ldy     #0
@rb:    lda     (p),y
        cmp     (q),y
        beq     :+
        inc     err4
        bne     :+
        inc     err4+1
:       iny
        bne     @rb
        inc     q+1
        jsr     sig_pag
        bne     @rp
        inc     banco
        lda     banco
        cmp     #16
        bne     @r4
        ; ---- resultado en pantalla
        jsr     pantalla
@fin:   jmp     @fin

; Abre el banco `banco` en la ventana: p = $4800, pag = 0.
abrir:  lda     banco
        sta     BANCO
        lda     #<VENTANA
        sta     p
        lda     #>VENTANA
        sta     p+1
        lda     #0
        sta     pag
        sta     xpag
        rts

; Siguiente página de 256 bytes de la ventana. Z = 1 al acabar las 8.
sig_pag:
        inc     p+1
        clc
        lda     xpag
        adc     #$3B
        sta     xpag
        inc     pag
        lda     pag
        cmp     #8
        rts

; ------------------------------------------------------------------ pantalla
pantalla:
        lda     #$3F                    ; paleta: fondo verde o rojo, texto blanco
        sta     PPUADDR
        lda     #$00
        sta     PPUADDR
        lda     err1
        ora     err2
        ora     err3
        ora     err3+1
        ora     err4
        ora     err4+1
        beq     :+
        lda     #$16                    ; rojo
        bne     :++
:       lda     #$1A                    ; verde
:       ldx     #4
@pal:   sta     PPUDATA
        pha
        lda     #$30
        sta     PPUDATA
        sta     PPUDATA
        sta     PPUDATA
        pla
        dex
        bne     @pal
        lda     #$20                    ; nametable a espacios
        sta     PPUADDR
        lda     #$00
        sta     PPUADDR
        lda     #' '
        ldx     #0
        ldy     #4
@nt:    sta     PPUDATA
        inx
        bne     @nt
        dey
        bne     @nt
        lda     #$23                    ; atributos a 0 (después de los espacios)
        sta     PPUADDR
        lda     #$C0
        sta     PPUADDR
        lda     #0
        ldx     #64
@at:    sta     PPUDATA
        dex
        bne     @at
        ; textos
        ldx     #8
        lda     #<t_titulo
        ldy     #>t_titulo
        jsr     linea
        ldx     #11
        lda     #<t_c1
        ldy     #>t_c1
        jsr     linea
        lda     err1
        jsr     veredicto
        ldx     #13
        lda     #<t_c2
        ldy     #>t_c2
        jsr     linea
        lda     err2
        jsr     veredicto
        ldx     #15
        lda     #<t_c3
        ldy     #>t_c3
        jsr     linea
        lda     err3
        ora     err3+1
        jsr     veredicto
        lda     err3+1
        jsr     hex
        lda     err3
        jsr     hex
        ldx     #17
        lda     #<t_c4
        ldy     #>t_c4
        jsr     linea
        lda     err4
        ora     err4+1
        jsr     veredicto
        lda     err4+1
        jsr     hex
        lda     err4
        jsr     hex
        lda     #0
        sta     PPUSCROLL
        sta     PPUSCROLL
        sta     PPUCTRL
        lda     #$0A                    ; fondo encendido, sin recorte a la izquierda
        sta     PPUMASK
        rts

; Pone el cursor de la PPU en la fila X, columna 3, y escribe el texto A/Y (terminado en 0).
linea:  sta     t
        sty     t+1
        stx     fila
        lda     #0
        sta     p+1
        txa
        asl
        asl
        asl
        asl
        rol     p+1
        asl
        rol     p+1
        ora     #3
        pha
        lda     p+1
        ora     #$20
        sta     PPUADDR
        pla
        sta     PPUADDR
        ldy     #0
@l:     lda     (t),y
        beq     @f
        sta     PPUDATA
        iny
        bne     @l
@f:     rts

; A = 0: «BIEN »; si no, «MAL  ».
veredicto:
        cmp     #0
        bne     :+
        lda     #<t_bien
        ldy     #>t_bien
        jmp     @t
:       lda     #<t_mal
        ldy     #>t_mal
@t:     sta     t
        sty     t+1
        ldy     #0
@l:     lda     (t),y
        beq     @f
        sta     PPUDATA
        iny
        bne     @l
@f:     rts

hex:    pha
        lsr
        lsr
        lsr
        lsr
        tax
        lda     cifras,x
        sta     PPUDATA
        pla
        and     #$0F
        tax
        lda     cifras,x
        sta     PPUDATA
        rts

nmi:
irq:    rti

        .segment "RODATA"
t_titulo: .byte "PRUEBA F0 DEL FDS", 0
t_c1:   .byte "LECTURA $40F1   ", 0
t_c2:   .byte "ECO   $40F2     ", 0
t_c3:   .byte "SRAM PRG ESCRITA ", 0
t_c4:   .byte "ROM POR VENTANA ", 0
t_bien: .byte "BIEN ", 0
t_mal:  .byte "MAL  ", 0
cifras: .byte "0123456789ABCDEF"

        .segment "VECTORS"
        .word   nmi, reset, irq

        .segment "CHARS"
        .incbin "fuente.chr"
        .incbin "fuente.chr"
