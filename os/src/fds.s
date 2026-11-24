; fds.s — reconocer discos del Famicom Disk System (.fds) y la BIOS FDS del usuario. GPL-3.0-or-later, código propio.
;
;   fds_reconocer   con el primer sector del archivo en `sector` y su tamaño en arch_tam: acarreo = 1 si no es un
;                   disco FDS. Si lo es (acarreo = 0): fds_caras, fds_cod (3 letras), fds_rev y A = 0 si se puede
;                   usar, L_FDSMAL si la imagen está mal (tamaño o bloque 1) o L_FDSNO si es uno de los discos con
;                   rutina de disco propia (tabla fds_malos, por el CRC32 de sus primeros FDS_INI bytes)
;   (la BIOS del usuario, EDFC/DISKSYS.ROM, la busca y la reconoce fds_ovl.s: fds_bios, al copiarla a la SRAM)
;
; Formato: una cara mide 65 500 bytes; delante puede ir la cabecera fwNES (16 bytes: «FDS», $1A, caras). La cara
; empieza por el bloque 1: $01 y «*NINTENDO-HVC*», fabricante, código del juego (3 letras), tipo y revisión.
; Las tablas (fds_tablas.inc) las genera tools/fds/analizar.py: solo sumas, ningún byte de Nintendo.

        .setcpu "6502"
        .include "os.inc"

        .export fds_reconocer, fds_caras, fds_cod, fds_rev, fds_desp
        .import sector, arch_tam, arch_abrir, arch_leer, arch_avanzar, dir_buscar, abrir_edfc, fat_error
        .importzp nombre

CARA_LO  = <65500
CARA_HI  = >65500
MAX_CARAS = 7                   ; las que caben en la SRAM PRG de 512 KiB junto a la BIOS

        .segment "ZEROPAGE"
crc:        .res 4              ; CRC32 en curso (crc+0 = byte bajo)
fp:         .res 2              ; puntero a los datos

        .segment "BSS"
fds_caras:  .res 1
fds_cod:    .res 3
fds_rev:    .res 1
desp:       .res 1              ; 0 o 16 (cabecera fwNES)
fds_desp = desp
resto:      .res 3              ; tamaño que falta por repartir en caras
cuenta:     .res 1

        .segment "CODE"

fds_reconocer:
        ldx     #0                      ; ¿cabecera fwNES?
        ldy     #0
@f:     lda     sector,x
        cmp     firma_fwnes,x
        bne     @sin
        inx
        cpx     #4
        bne     @f
        ldy     #16
@sin:   sty     desp
        lda     sector,y                ; bloque 1
        cmp     #1
        beq     :+
        jmp     @no_es
:
        ldx     #0
@h:     lda     sector+1,y
        cmp     firma_hvc,x
        bne     @no_es
        iny
        inx
        cpx     #14
        bne     @h
        ldx     desp                    ; código del juego y revisión
        lda     sector+16,x
        sta     fds_cod
        lda     sector+17,x
        sta     fds_cod+1
        lda     sector+18,x
        sta     fds_cod+2
        lda     sector+20,x
        sta     fds_rev
        ; ---- caras = (tamaño - desp) / 65 500, exacto y entre 1 y MAX_CARAS
        lda     arch_tam+3
        bne     @mal
        sec
        lda     arch_tam
        sbc     desp
        sta     resto
        lda     arch_tam+1
        sbc     #0
        sta     resto+1
        lda     arch_tam+2
        sbc     #0
        sta     resto+2
        lda     #0
        sta     fds_caras
@c:     lda     resto
        ora     resto+1
        ora     resto+2
        beq     @caras
        sec
        lda     resto
        sbc     #CARA_LO
        sta     resto
        lda     resto+1
        sbc     #CARA_HI
        sta     resto+1
        lda     resto+2
        sbc     #0
        sta     resto+2
        bcc     @mal                    ; no es un múltiplo
        inc     fds_caras
        lda     fds_caras
        cmp     #MAX_CARAS + 1
        bne     @c
@mal:   lda     #L_FDSMAL
        clc
        rts
@no_es: lda     desp                    ; con cabecera fwNES y sin bloque 1: un FDS estropeado
        beq     :+
        lda     #L_FDSMAL
        clc
        rts
:       sec
        rts
@caras: lda     fds_caras
        beq     @mal
        ; ---- ¿uno de los discos con rutina de disco propia?
        jsr     crc_ini
        clc
        lda     #<sector
        adc     desp
        sta     fp
        lda     #>sector
        adc     #0
        sta     fp+1
        lda     #<FDS_INI
        ldx     #>FDS_INI
        jsr     crc_datos
        jsr     crc_fin
        lda     #<fds_malos
        ldx     #>fds_malos
        ldy     #FDS_MALOS_N
        jsr     crc_buscar
        bcs     @bien
        lda     #L_FDSNO
        clc
        rts
@bien:  lda     #0
        clc
        rts

; ------------------------------------------------------------------------------------------------ CRC32
; CRC-32 de zlib (polinomio $EDB88320, reflejado), de 4 en 4 bits con una tabla de 16 entradas.
crc_ini:
        lda     #$FF
        sta     crc
        sta     crc+1
        sta     crc+2
        sta     crc+3
        rts

crc_fin:
        ldx     #3
@x:     lda     crc,x
        eor     #$FF
        sta     crc,x
        dex
        bpl     @x
        rts

; Suma A (bajo) + X*256 bytes desde (fp). fp avanza.
crc_datos:
        sta     resto
        stx     resto+1
@b:     lda     resto
        ora     resto+1
        beq     @fin
        ldy     #0
        lda     (fp),y
        eor     crc
        sta     crc
        jsr     nibble
        jsr     nibble
        inc     fp
        bne     :+
        inc     fp+1
:       lda     resto
        bne     :+
        dec     resto+1
:       dec     resto
        jmp     @b
@fin:   rts

; crc = (crc >> 4) ^ tabla[crc & 15]
nibble: lda     crc
        and     #$0F
        asl
        asl
        tax
        ldy     #4
@d:     lsr     crc+3
        ror     crc+2
        ror     crc+1
        ror     crc
        dey
        bne     @d
        lda     crc
        eor     tabla_crc,x
        sta     crc
        lda     crc+1
        eor     tabla_crc+1,x
        sta     crc+1
        lda     crc+2
        eor     tabla_crc+2,x
        sta     crc+2
        lda     crc+3
        eor     tabla_crc+3,x
        sta     crc+3
        rts

; Busca crc en la tabla A/X de Y entradas de 4 bytes. Acarreo = 0 y X = índice si está.
crc_buscar:
        sta     fp
        stx     fp+1
        sty     cuenta
        ldx     #0
@e:     cpx     cuenta
        bcs     @no
        ldy     #0
@b:     lda     (fp),y
        cmp     crc,y
        bne     @sig
        iny
        cpy     #4
        bne     @b
        clc
        rts
@sig:   clc
        lda     fp
        adc     #4
        sta     fp
        bcc     :+
        inc     fp+1
:       inx
        bne     @e
@no:    sec
        rts

        .segment "RODATA"
firma_fwnes: .byte "FDS", $1A
firma_hvc:   .byte "*NINTENDO-HVC*"

        .include "fds_tablas.inc"
