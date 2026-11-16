; hola.s — OS propio del EverDrive N8 clon, etapa 1: pantalla de diagnóstico del arranque y del reset.
; GPL-3.0-or-later. La entrada y la clasificación del arranque están en arranque.s.
;
; Muestra: tipo de arranque (frío desde la BIOS, reset en el OS o vuelta de un juego), los contadores, los registros
; de la CPU y del CPLD tal como llegaron, los registros 2, 9 y 138 y $4403 en vivo, el mando y un contador de
; fotogramas. Escribe solo en: RAM de la CPU, su propia imagen ($8000-$FFFF, PRG-RAM), la PPU, el reg 130 del FPGA
; (banco de la CHR en modo OS, como el v13), el número de registro de $4400 y, al arrancar, el reg 9 = 01.

        .setcpu "6502"
        .include "os.inc"

        .export principal, nmi
        .import tipo_arranque, arranques, resets, vueltas
        .import e_a, e_regs, e_4403

; ------------------------------------------------------------------------------------------------ variables
        .segment "ZEROPAGE"
ptr:        .res 2
botones:    .res 1              ; A en el bit 7 ... Derecha en el bit 0
fotogramas: .res 2
vivo:       .res 4              ; reg 2, reg 9, reg 138, $4403 en el fotograma actual
tmp:        .res 1
nmis:       .res 1              ; lo incrementa la NMI: un fotograma = una NMI

; ------------------------------------------------------------------------------------------------ código
        .segment "CODE"

principal:
        lda     #REG_CHR
        sta     REG_SEL
        lda     #0
        sta     REG_DAT

        jsr     subir_fuente
        jsr     paleta
        jsr     borrar_pantalla
        lda     #<textos
        sta     ptr
        lda     #>textos
        sta     ptr+1
        jsr     textos_fijos
        jsr     valores_fijos

@vb:    bit     PPUSTATUS
        bpl     @vb
        jsr     sin_scroll              ; activa la NMI
        lda     #%00001010              ; fondo visible, también en la columna izquierda
        sta     PPUMASK

; Un paso por fotograma, sincronizado con la NMI (leer $2002 en un bucle pierde algún VBlank).
bucle:
        lda     nmis
@vb:    cmp     nmis
        beq     @vb
        jsr     valores_vivos
        jsr     sin_scroll
        inc     fotogramas
        bne     @sin_acarreo
        inc     fotogramas+1
@sin_acarreo:
        jsr     medir_vivos
        jmp     bucle

; NMI: lee el mando una vez por fotograma, como el v13 (puerto 1 y el de expansión de la Famicom: bits 0 y 1 de
; $4016 y $4017). El kit Lava ve las mismas lecturas para su reset (Select ~2 s y luego Select+A).
nmi:    pha
        txa
        pha
        lda     #1
        sta     MANDO1
        lda     #0
        sta     MANDO1
        ldx     #8
@b:     lda     MANDO2
        ora     MANDO1
        and     #%00000011
        cmp     #1                      ; acarreo = algún bit a 1
        rol     botones
        dex
        bne     @b
        inc     nmis
        pla
        tax
        pla
        rti

; ------------------------------------------------------------------------------------------------ rutinas
sin_scroll:
        lda     #0
        sta     PPUSCROLL
        sta     PPUSCROLL
        lda     #$80
        sta     PPUCTRL                 ; NMI activa, nametable 0, patrones del fondo en $0000
        rts

; ppu_dir: A = byte alto, X = byte bajo
ppu_dir:
        bit     PPUSTATUS
        sta     PPUADDR
        stx     PPUADDR
        rts

; Escribe A en hexadecimal en PPUDATA.
hex:
        pha
        lsr
        lsr
        lsr
        lsr
        tay
        lda     cifras,y
        sta     PPUDATA
        pla
        and     #$0F
        tay
        lda     cifras,y
        sta     PPUDATA
        rts

espacio:
        lda     #' '
        sta     PPUDATA
        rts

; Escribe en PPUDATA el texto de 0 terminado que apunta ptr.
cadena:
        ldy     #0
@c:     lda     (ptr),y
        beq     @fin
        sta     PPUDATA
        iny
        bne     @c
@fin:   rts

subir_fuente:
        lda     #$02                    ; tile $20 = $0200 del patrón 0
        ldx     #$00
        jsr     ppu_dir
        lda     #<fuente
        sta     ptr
        lda     #>fuente
        sta     ptr+1
        ldx     #4                      ; 4 x 256 = 1024 bytes (64 tiles)
        ldy     #0
@b:     lda     (ptr),y
        sta     PPUDATA
        iny
        bne     @b
        inc     ptr+1
        dex
        bne     @b
        rts

paleta:
        lda     #$3F
        ldx     #$00
        jsr     ppu_dir
        ldx     #0
@b:     lda     colores,x
        sta     PPUDATA
        inx
        cpx     #32
        bne     @b
        rts

borrar_pantalla:
        lda     #$20
        ldx     #$00
        jsr     ppu_dir
        lda     #' '
        ldx     #0
        ldy     #4                      ; 1024 bytes: 960 de tiles + 64 de atributos (ver abajo)
@b:     sta     PPUDATA
        inx
        bne     @b
        dey
        bne     @b
        lda     #$23                    ; atributos a 0 (paleta 0)
        ldx     #$C0
        jsr     ppu_dir
        lda     #0
        ldx     #64
@a:     sta     PPUDATA
        dex
        bne     @a
        rts

; Registros con formato: dirección alta, baja, texto, 0. Termina con un byte alto $FF.
textos_fijos:
        ldy     #0
@r:     lda     (ptr),y
        cmp     #$FF
        beq     @fin
        pha
        iny
        lda     (ptr),y
        tax
        pla
        jsr     ppu_dir
        iny
@c:     lda     (ptr),y
        beq     @fin_texto
        sta     PPUDATA
        iny
        bne     @c
@fin_texto:
        iny
        tya                             ; avanzar ptr para no depender de Y < 256
        clc
        adc     ptr
        sta     ptr
        bcc     @sin
        inc     ptr+1
@sin:   ldy     #0
        jmp     @r
@fin:   rts

valores_fijos:
        lda     #>(FILA_TIPO + 11)
        ldx     #<(FILA_TIPO + 11)
        jsr     ppu_dir
        ldx     tipo_arranque
        lda     nombres_tipo_lo,x
        sta     ptr
        lda     nombres_tipo_hi,x
        sta     ptr+1
        jsr     cadena

        lda     #>(FILA_CONT + 32 + 2)
        ldx     #<(FILA_CONT + 32 + 2)
        jsr     ppu_dir
        lda     arranques
        jsr     hex
        ldx     #8
@e1:    jsr     espacio
        dex
        bne     @e1
        lda     resets
        jsr     hex
        ldx     #6
@e2:    jsr     espacio
        dex
        bne     @e2
        lda     vueltas
        jsr     hex

        lda     #>(FILA_CPU + 2)
        ldx     #<(FILA_CPU + 2)
        jsr     ppu_dir
        ldx     #0
@c:     lda     e_a,x                   ; e_a, e_x, e_y, e_s, e_p seguidos
        stx     tmp
        jsr     hex
        jsr     espacio
        ldx     tmp
        inx
        cpx     #5
        bne     @c

        lda     #>(FILA_REG + 2)
        ldx     #<(FILA_REG + 2)
        jsr     ppu_dir
        ldx     #0
@r:     lda     e_regs,x
        stx     tmp
        jsr     hex
        jsr     espacio
        ldx     tmp
        inx
        cpx     #6
        bne     @r
        lda     e_4403
        jsr     hex
        rts

medir_vivos:
        lda     #2
        sta     REG_SEL
        lda     REG_DAT
        sta     vivo
        lda     #9
        sta     REG_SEL
        lda     REG_DAT
        sta     vivo+1
        lda     #138
        sta     REG_SEL
        lda     REG_DAT
        sta     vivo+2
        lda     CPLD_EST
        sta     vivo+3
        rts

valores_vivos:
        lda     #>(FILA_VIVO + 2)
        ldx     #<(FILA_VIVO + 2)
        jsr     ppu_dir
        ldx     #0
@v:     lda     vivo,x
        stx     tmp
        jsr     hex
        jsr     espacio
        jsr     espacio
        jsr     espacio
        ldx     tmp
        inx
        cpx     #4
        bne     @v

        lda     #>(FILA_MANDO + 9)
        ldx     #<(FILA_MANDO + 9)
        jsr     ppu_dir
        lda     botones
        sta     tmp
        ldx     #0
@m:     asl     tmp
        lda     #'-'
        bcc     @no
        lda     letras_mando,x
@no:    sta     PPUDATA
        lda     #' '
        sta     PPUDATA
        inx
        cpx     #8
        bne     @m

        lda     #>(FILA_FOTO + 14)
        ldx     #<(FILA_FOTO + 14)
        jsr     ppu_dir
        lda     fotogramas+1
        jsr     hex
        lda     fotogramas
        jsr     hex
        rts

; ------------------------------------------------------------------------------------------------ datos
        .segment "RODATA"

NT = $2000
FILA_TIT   = NT + 3 * 32
FILA_TIPO  = NT + 6 * 32
FILA_CONT  = NT + 8 * 32
FILA_CPU   = NT + 12 * 32
FILA_REG   = NT + 15 * 32
FILA_VIVO  = NT + 18 * 32
FILA_MANDO = NT + 20 * 32
FILA_FOTO  = NT + 21 * 32

.macro texto dir, cad
        .byte   >(dir), <(dir)
        .byte   cad, 0
.endmacro

textos:
        texto   FILA_TIT + 2,       "OS PROPIO N8 - ARRANQUE"
        texto   FILA_TIT + 32 + 2,  "ETAPA 1    GPL-3.0-OR-LATER"
        texto   FILA_TIPO + 2,      "ARRANQUE:"
        texto   FILA_CONT + 2,      "ENTRADAS  RESETS  VUELTAS"
        texto   FILA_CPU - 32 + 2,  "A  X  Y  S  P  (AL ENTRAR)"
        texto   FILA_REG - 32 + 2,  "R2 R9 RA 8A 8B 8C 4403"
        texto   FILA_VIVO - 32 + 2, "REG2 REG9 R138 4403 (AHORA)"
        texto   FILA_MANDO + 2,     "MANDO:"
        texto   FILA_FOTO + 2,      "FOTOGRAMAS:"
        texto   NT + 23 * 32 + 2,   "RESET: BOTON RESET, O SELECT"
        texto   NT + 24 * 32 + 2,   "2 S Y LUEGO SELECT+A (LAVA)"
        texto   NT + 25 * 32 + 2,   "VOLVER AL OS DE FABRICA:"
        texto   NT + 26 * 32 + 2,   "COPIA OS_V13.BIN COMO OS.BIN"
        .byte   $FF

nombre_frio:    .byte "FRIO (BIOS)", 0
nombre_reset:   .byte "RESET", 0
nombre_vuelta:  .byte "VUELTA DE JUEGO", 0
nombres_tipo_lo: .byte <nombre_frio, <nombre_reset, <nombre_vuelta
nombres_tipo_hi: .byte >nombre_frio, >nombre_reset, >nombre_vuelta

cifras:
        .byte   "0123456789ABCDEF"
letras_mando:
        .byte   "ABSTUDLR"              ; A, B, Select, sTart, arriba (Up), abajo (Down), izquierda (Left), derecha (Right)
colores:
        .byte   $0F, $30, $10, $00,  $0F, $30, $10, $00,  $0F, $30, $10, $00,  $0F, $30, $10, $00
        .byte   $0F, $30, $10, $00,  $0F, $30, $10, $00,  $0F, $30, $10, $00,  $0F, $30, $10, $00
fuente:
        .incbin "fuente.chr"
