; principal.s — OS propio del EverDrive N8 clon, etapa 2: lectura de la SD.
; GPL-3.0-or-later. La entrada y el tipo de arranque están en arranque.s; la SD en sd.s; la FAT en fat.s.
;
; Con la pantalla apagada: inicializa la tarjeta, monta la FAT, lista la raíz y mide cuánto tarda en leer 64
; sectores (32 KiB). Después enciende la pantalla y muestra
; el mando y un contador de fotogramas. No escribe nunca en la tarjeta.

        .setcpu "6502"
        .include "os.inc"

        .export principal, nmi
        .import tipo_arranque, arranques, resets, vueltas
        .import sd_iniciar, sd_leer_sector, sd_error, sd_r1, sd_sdhc
        .import fat_montar, dir_abrir_raiz, dir_siguiente
        .import fat_error, fat_tipo, fat_spc, fat_part, fat_datos, sector
        .importzp sd_lba, sd_ptr, dir_ent

LINEAS_LISTA = 13               ; entradas de la raíz que caben en pantalla
SECTORES_PRUEBA = 64            ; 32 KiB

; ------------------------------------------------------------------------------------------------ variables
        .segment "ZEROPAGE"
ptr:        .res 2
botones:    .res 1              ; A en el bit 7 ... Derecha en el bit 0
fotogramas: .res 2
tmp:        .res 1
nmis:       .res 2              ; lo incrementa la NMI: un fotograma = una NMI
mando_on:   .res 1              ; 0 mientras arranca: la NMI no lee el mando (ver nmi)
fila:       .res 2              ; dirección de la PPU de la línea de la lista
entradas:   .res 1              ; entradas de la raíz
cuenta:     .res 1
t_rapido:   .res 2              ; fotogramas de la prueba de lectura

; ------------------------------------------------------------------------------------------------ código
        .segment "CODE"

.macro en dir                   ; coloca la escritura de la PPU en una dirección de la pantalla
        lda     #>(dir)
        ldx     #<(dir)
        jsr     ppu_dir
.endmacro

.macro escribe txt              ; escribe una cadena fija
        lda     #<txt
        sta     ptr
        lda     #>txt
        sta     ptr+1
        jsr     cadena
.endmacro

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
        jsr     valores_arranque

        lda     #$80                    ; NMI activa con la pantalla apagada: cuenta fotogramas y lee el mando
        sta     PPUCTRL

        jsr     sd_iniciar
        bcs     @error_sd
        jsr     fat_montar
        bcs     @error_fat
        jsr     datos_tarjeta
        jsr     lista_raiz
        jsr     prueba_velocidad
        jmp     @pantalla
@error_sd:
        lda     sd_error
        jmp     @error
@error_fat:
        lda     fat_error
@error: pha
        en      FILA_SD + 6
        escribe t_error
        pla
        jsr     hex
        escribe t_r1
        lda     sd_r1
        jsr     hex

@pantalla:
        lda     #1
        sta     mando_on
        lda     nmis
@vb:    cmp     nmis
        beq     @vb
        jsr     sin_scroll
        lda     #%00001010              ; fondo visible, también en la columna izquierda
        sta     PPUMASK

; Un paso por fotograma, sincronizado con la NMI.
bucle:
        lda     nmis
@vb:    cmp     nmis
        beq     @vb
        jsr     valores_vivos
        jsr     sin_scroll
        inc     fotogramas
        bne     bucle
        inc     fotogramas+1
        jmp     bucle

; NMI: lee el mando una vez por fotograma, como el v13 (puerto 1 y el de expansión de la Famicom: bits 0 y 1 de
; $4016 y $4017). El kit Lava ve las mismas lecturas para su reset (Select ~2 s y luego Select+A).
; No toca $4400/$4401: puede caer en mitad de una lectura de la SD.
; Mientras el OS arranca (mando_on = 0) no lee el mando: así cada reset deja un silencio largo sin LATCH (lo que
; tarda en leer la SD), que el Nano del banco cuenta como un reset. Con la lectura activa desde el principio el
; silencio era de 54 ms, menos que su umbral de 60 ms (medido en la NES).
nmi:    pha
        txa
        pha
        lda     mando_on
        beq     @sin_mando
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
@sin_mando:
        inc     nmis
        bne     @fin
        inc     nmis+1
@fin:   pla
        tax
        pla
        rti

; ------------------------------------------------------------------------------------------------ SD en pantalla
datos_tarjeta:
        en      FILA_SD + 6
        lda     sd_sdhc
        beq     @sdsc
        escribe t_sdhc
        jmp     @fat
@sdsc:  escribe t_sdsc
@fat:   lda     fat_tipo
        cmp     #32
        beq     @f32
        escribe t_fat16
        jmp     @spc
@f32:   escribe t_fat32
@spc:   lda     fat_spc
        jsr     hex
        en      FILA_SD + 32 + 7
        ldx     #3
        jsr     @hex32p
        en      FILA_SD + 32 + 22
        ldx     #3
@d:     stx     tmp
        lda     fat_datos,x
        jsr     hex
        ldx     tmp
        dex
        bpl     @d
        rts
@hex32p:
        stx     tmp
        lda     fat_part,x
        jsr     hex
        ldx     tmp
        dex
        bpl     @hex32p
        rts

; Lista la raíz: nombre 8.3 y tamaño (o <DIR>), LINEAS_LISTA como mucho; cuenta todas las entradas.
lista_raiz:
        lda     #<FILA_LISTA
        sta     fila
        lda     #>FILA_LISTA
        sta     fila+1
        lda     #0
        sta     entradas
        jsr     dir_abrir_raiz
@sig:   jsr     dir_siguiente
        bcs     @fin
        inc     entradas
        lda     entradas
        cmp     #LINEAS_LISTA + 1
        bcs     @sig                    ; ya no cabe: solo se cuenta
        lda     fila+1
        ldx     fila
        jsr     ppu_dir
        clc
        lda     fila
        adc     #32
        sta     fila
        bcc     @nombre
        inc     fila+1
@nombre:
        ldy     #0
@n:     jsr     letra
        iny
        cpy     #8
        bne     @n
        lda     #'.'
        sta     PPUDATA
@x:     jsr     letra
        iny
        cpy     #11
        bne     @x
        jsr     espacio
        ldy     #11
        lda     (dir_ent),y
        and     #$10
        beq     @tam
        escribe t_dir
        jmp     @sig
@tam:   ldy     #31
@t:     sty     tmp
        lda     (dir_ent),y
        jsr     hex
        ldy     tmp
        dey
        cpy     #27
        bne     @t
        jmp     @sig
@fin:   en      FILA_SD + 64 + 11
        lda     entradas
        jsr     hex
        lda     fat_error               ; si la lista se cortó por un error de lectura, se ve aquí
        beq     @bien
        jsr     espacio
        lda     #'E'
        sta     PPUDATA
        lda     fat_error
        jsr     hex
@bien:  rts

; Escribe el carácter Y de la entrada; lo que no es ASCII imprimible sale como «?».
letra:  lda     (dir_ent),y
        cmp     #$20
        bcc     @raro
        cmp     #$7F
        bcc     @ya
@raro:  lda     #'?'
@ya:    sta     PPUDATA
        rts

; Lee SECTORES_PRUEBA sectores desde el principio de la partición y cuenta los fotogramas.
; (Con el bit 0 del reg 2 a 0 las lecturas en ráfaga fallan: medido en la NES el 2026-11-16. Es el SPI rápido.)
prueba_velocidad:
        jsr     @medir
        sta     t_rapido
        stx     t_rapido+1
        php
        en      FILA_SD + 96 + 12
        plp
        bcs     @er
        lda     t_rapido+1
        jsr     hex
        lda     t_rapido
        jmp     hex
@er:    escribe t_fallo
        rts

; Devuelve A,X = fotogramas (bajo, alto) y acarreo = 1 si alguna lectura falló.
@medir: lda     fat_part
        sta     sd_lba
        lda     fat_part+1
        sta     sd_lba+1
        lda     fat_part+2
        sta     sd_lba+2
        lda     fat_part+3
        sta     sd_lba+3
        lda     #<sector
        sta     sd_ptr
        lda     #>sector
        sta     sd_ptr+1
        lda     #SECTORES_PRUEBA
        sta     cuenta
        lda     nmis                    ; esperar al principio de un fotograma
@e:     cmp     nmis
        beq     @e
        lda     nmis
        sta     fila
        lda     nmis+1
        sta     fila+1
@s:     jsr     sd_leer_sector
        bcs     @mal
        inc     sd_lba
        bne     @c
        inc     sd_lba+1
@c:     dec     cuenta
        bne     @s
        sec
        lda     nmis
        sbc     fila
        pha
        lda     nmis+1
        sbc     fila+1
        tax
        pla
        clc
        rts
@mal:   lda     #0
        tax
        sec
        rts

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

; Escribe A en hexadecimal en PPUDATA. Usa Y.
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
        ldx     #8                      ; 8 x 256 = 2048 bytes (128 tiles: $20-$9F)
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

valores_arranque:
        en      FILA_ARR + 12
        ldx     tipo_arranque
        lda     nombres_tipo_lo,x
        sta     ptr
        lda     nombres_tipo_hi,x
        sta     ptr+1
        jsr     cadena
        en      FILA_ARR + 32 + 15
        lda     arranques
        jsr     hex
        jsr     espacio
        lda     resets
        jsr     hex
        jsr     espacio
        lda     vueltas
        jmp     hex

valores_vivos:
        en      FILA_MANDO + 9
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
        en      FILA_MANDO + 32 + 14
        lda     fotogramas+1
        jsr     hex
        lda     fotogramas
        jmp     hex

; ------------------------------------------------------------------------------------------------ datos
        .segment "RODATA"

NT = $2000
FILA_TIT   = NT + 2 * 32
FILA_ARR   = NT + 3 * 32
FILA_SD    = NT + 6 * 32
FILA_LISTA = NT + 11 * 32 + 2
FILA_MANDO = NT + 25 * 32

.macro texto dir, cad
        .byte   >(dir), <(dir)
        .byte   cad, 0
.endmacro

textos:
        texto   FILA_TIT + 2,       "OS propio N8 - etapa 2: SD"
        texto   FILA_ARR + 2,       "Arranque:"
        texto   FILA_ARR + 32 + 2,  "Ent/res/vue:"
        texto   FILA_SD + 2,        "SD:"
        texto   FILA_SD + 32 + 2,   "Part          Datos"
        texto   FILA_SD + 64 + 2,   {"En ra", C_i, "z:"}
        texto   FILA_SD + 96 + 2,   "32K en f:      fotogramas"
        texto   FILA_MANDO + 2,     "Mando:"
        texto   FILA_MANDO + 32 + 2, "Fotogramas:"
        .byte   $FF

nombre_frio:    .byte "fr", C_i, "o (BIOS)", 0
nombre_reset:   .byte "reset", 0
nombre_vuelta:  .byte "vuelta de juego", 0
nombres_tipo_lo: .byte <nombre_frio, <nombre_reset, <nombre_vuelta
nombres_tipo_hi: .byte >nombre_frio, >nombre_reset, >nombre_vuelta

t_sdhc:     .byte "SDHC ", 0
t_sdsc:     .byte "SDSC ", 0
t_fat16:    .byte "FAT16 cl", C_u, "ster ", 0
t_fat32:    .byte "FAT32 cl", C_u, "ster ", 0
t_error:    .byte "error ", 0
t_r1:       .byte " R1=", 0
t_dir:      .byte "<DIR>", 0
t_fallo:    .byte "fallo", 0

cifras:
        .byte   "0123456789ABCDEF"
letras_mando:
        .byte   "ABSTUDLR"              ; A, B, Select, sTart, arriba (Up), abajo (Down), izquierda (Left), derecha (Right)
colores:
        .byte   $0F, $30, $10, $00,  $0F, $30, $10, $00,  $0F, $30, $10, $00,  $0F, $30, $10, $00
        .byte   $0F, $30, $10, $00,  $0F, $30, $10, $00,  $0F, $30, $10, $00,  $0F, $30, $10, $00
fuente:
        .incbin "fuente.chr"
