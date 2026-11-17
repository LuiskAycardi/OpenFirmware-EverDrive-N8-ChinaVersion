; lanzar.s — lanzar un juego: cabecera iNES, MAPROUT, carga del RBF en el FPGA, copia de PRG y CHR, registros del
; FPGA y salto. GPL-3.0-or-later, código propio (docs/bios-n8-clon.md §1-§2, docs/hardware-fpga.md).
;
; El número de mapper va al FPGA TAL CUAL está en la cabecera (el OS v13 cambiaba el 219 por 0 y el 220 por 4).
;
; Pasos de `lanzar` (dir_ent = entrada de la ROM en el directorio; pantalla apagada y sin NMI):
;   1. cabecera iNES: PRG, CHR, mapper, byte 6;
;   2. EDFC/MAPROUT.BIN[mapper] = número del RBF ($FF = no hay);
;   3. EDFC/MAPS/NNN.RBF: tiene que estar contiguo, porque se pasa al FPGA con una sola lectura múltiple;
;   4. configurar el FPGA desde la RAM (ram_config): mientras se configura no hay nada en $8000-$FFFF;
;   5. copiar la PRG por la ventana $4800 (reg 128) y la CHR por la PPU (reg 130);
;   6. regs 132 (PRG), 133 (CHR), 134 (byte 6 de la cabecera), 136 (reset corto), marca en_juego y, desde la
;      RAM, reg 131 = mapper y salto al vector de reset del juego.
; Solo vuelve si algo falla: acarreo = 1 y l_error.

        .setcpu "6502"
        .include "os.inc"

        .export lanzar, l_error, l_rbf, nombre_rbf
        .exportzp l_mapper
        .import dir_abrir_raiz, dir_abrir, dir_buscar
        .import arch_abrir, arch_reabrir, arch_leer, arch_avanzar, arch_contiguo
        .import arch_lba, arch_tam, arch_ini, fat_error, sector
        .import sd_multi_ini, sd_parar, sd_base
        .import en_juego
        .importzp sd_lba, nombre
        .import __RAMCOD_LOAD__, __RAMCOD_RUN__, __RAMCOD_SIZE__

REG_PRG      = 128              ; banco de 2 KiB de la SRAM PRG en $4800-$4FFF
REG_MAPPER   = 131
REG_PRG_TAM  = 132
REG_CHR_TAM  = 133
REG_MAP_CFG  = 134
REG_CART_CFG = 136
VENTANA      = $4800

        .segment "ZEROPAGE"
src:        .res 2              ; medio sector que se está copiando
dsta:       .res 2              ; destino ajustado (destino - Y)
dst:        .res 2              ; destino en la ventana $4800
yfin:       .res 1
y0:         .res 1
cfg_n:      .res 2              ; bloques del RBF que faltan
cfg_reg2:   .res 1              ; reg 2 durante la carga: tarjeta seleccionada y ráfaga
l_mapper:   .res 1

        .segment "BSS"
l_error:    .res 1
l_rbf:      .res 1
l_prg16:    .res 1
l_chr8:     .res 1
l_cfg:      .res 1
l_trainer:  .res 1
r_ini:      .res 4              ; primer clúster de la ROM
prg_rest:   .res 3              ; bytes de PRG que faltan
chr_rest:   .res 3
chr_banco:  .res 2              ; bytes que faltan del tramo de 8 KiB de CHR
banco_prg:  .res 1
banco_chr:  .res 1
primera:    .res 1              ; el primer medio sector lleva la cabecera
nombre_rbf: .res 11

        .segment "CODE"

.macro copia4 destino, origen
        ldx     #3
:       lda     origen,x
        sta     destino,x
        dex
        bpl     :-
.endmacro

; X = registro del FPGA, A = valor.
fpga_reg:
        stx     REG_SEL
        sta     REG_DAT
        rts

falla:  sta     l_error
        sec
        rts
falla_sd:
        lda     #L_SD
        bne     falla

lanzar:
        lda     #0
        sta     l_error
        sta     fat_error
        ; ---- 1. cabecera
        jsr     arch_abrir
        copia4  r_ini, arch_ini
        jsr     arch_leer
        bcs     falla_sd
        ldx     #3
@firma: lda     sector,x
        cmp     firma_ines,x
        beq     @ok
        lda     #L_NOINES
        bne     falla
@ok:    dex
        bpl     @firma
        lda     sector+4
        sta     l_prg16
        beq     @tam
        cmp     #33
        bcs     @tam
        lda     sector+5
        sta     l_chr8
        cmp     #65
        bcc     @cab
@tam:   lda     #L_TAM
        bne     falla
@cab:   lda     sector+6
        and     #$1B
        sta     l_cfg
        lda     sector+6
        and     #$04
        sta     l_trainer
        lda     sector+6
        lsr
        lsr
        lsr
        lsr
        sta     l_mapper
        lda     sector+12               ; cabeceras antiguas con basura en los bytes 7-15: solo el nibble bajo
        ora     sector+13
        ora     sector+14
        ora     sector+15
        bne     @mapper
        lda     sector+7
        and     #$F0
        ora     l_mapper
        sta     l_mapper
@mapper:
        ; ---- 2. EDFC/MAPROUT.BIN
        jsr     abrir_edfc
        bcs     @sin_maprout
        lda     #<n_maprout
        sta     nombre
        lda     #>n_maprout
        sta     nombre+1
        jsr     dir_buscar
        bcc     @maprout
@sin_maprout:
        lda     fat_error
        beq     :+
        jmp     falla_sd
:       lda     #L_MAPROUT
        jmp     falla
@maprout:
        jsr     arch_abrir
        jsr     arch_leer
        bcc     @tabla
        jmp     falla_sd
@tabla: ldx     l_mapper
        lda     sector,x
        sta     l_rbf
        cmp     #$FF
        bne     @rbf
        lda     #L_SINMAPPER
        jmp     falla
        ; ---- 3. EDFC/MAPS/NNN.RBF
@rbf:   ldx     #10
@nom:   lda     n_rbf,x
        sta     nombre_rbf,x
        dex
        bpl     @nom
        lda     l_rbf
        ldx     #'0'
@cien:  cmp     #100
        bcc     @c2
        sbc     #100
        inx
        bne     @cien
@c2:    stx     nombre_rbf
        ldx     #'0'
@diez:  cmp     #10
        bcc     @d2
        sbc     #10
        inx
        bne     @diez
@d2:    stx     nombre_rbf+1
        ora     #'0'
        sta     nombre_rbf+2
        jsr     abrir_edfc
        bcs     @sin_rbf
        lda     #<n_maps
        sta     nombre
        lda     #>n_maps
        sta     nombre+1
        jsr     dir_buscar
        bcs     @sin_rbf
        jsr     dir_abrir
        lda     #<nombre_rbf
        sta     nombre
        lda     #>nombre_rbf
        sta     nombre+1
        jsr     dir_buscar
        bcc     @hay_rbf
@sin_rbf:
        lda     fat_error
        beq     :+
        jmp     falla_sd
:       lda     #L_SINRBF
        jmp     falla
@hay_rbf:
        jsr     arch_abrir
        jsr     arch_contiguo
        bcc     @contiguo
        lda     fat_error
        beq     :+
        jmp     falla_sd
:       lda     #L_FRAG
        jmp     falla
@contiguo:
        lda     arch_tam+1              ; bloques = tamaño / 512, redondeando hacia arriba
        sta     cfg_n
        lda     arch_tam+2
        lsr
        sta     cfg_n+1
        ror     cfg_n
        lda     arch_tam+1
        and     #$01
        ora     arch_tam
        beq     @bloques
        inc     cfg_n
        bne     @bloques
        inc     cfg_n+1
@bloques:
        ; ---- 4. configurar el FPGA
        ldx     #0                      ; rutinas a la RAM
@ram:   lda     __RAMCOD_LOAD__,x
        sta     __RAMCOD_RUN__,x
        inx
        cpx     #<__RAMCOD_SIZE__
        bne     @ram
        lda     sd_base
        ora     #%00000100              ; tarjeta seleccionada y ráfaga
        sta     cfg_reg2
        copia4  sd_lba, arch_lba
        jsr     sd_multi_ini
        bcc     :+
        jmp     falla_sd
:       jsr     ram_config              ; aquí cambia el FPGA; al volver, el RBF nuevo está en modo OS
        pha
        jsr     sd_parar
        pla
        beq     @rom
        lda     #L_FPGA
        jmp     falla

        ; ---- 5. PRG y CHR
@rom:   copia4  arch_ini, r_ini
        jsr     arch_reabrir
        lda     #0
        sta     prg_rest
        sta     prg_rest+1
        sta     chr_rest
        sta     banco_prg
        sta     dst
        lda     l_prg16                 ; x 16384
        lsr
        ror     prg_rest+1
        lsr
        ror     prg_rest+1
        sta     prg_rest+2
        lda     #0
        sta     chr_rest+1
        lda     l_chr8                  ; x 8192
        lsr
        ror     chr_rest+1
        lsr
        ror     chr_rest+1
        lsr
        ror     chr_rest+1
        sta     chr_rest+2
        lda     #>VENTANA
        sta     dst+1
        ldx     #REG_PRG
        lda     #0
        jsr     fpga_reg
        lda     #1                      ; CHR: $0000-$0FFF = banco 0 y $1000-$1FFF = banco 1
        sta     banco_chr
        jsr     tramo_chr
        lda     #1
        sta     primera
        lda     l_trainer
        beq     @sector
        jsr     arch_avanzar            ; 512 bytes de «trainer»: se saltan
        bcc     @sector
        jmp     falla_sd
@sector:
        lda     prg_rest
        ora     prg_rest+1
        ora     prg_rest+2
        ora     chr_rest
        ora     chr_rest+1
        ora     chr_rest+2
        beq     @copiado
        jsr     arch_leer
        bcc     :+
        jmp     falla_sd
:       lda     #<sector
        sta     src
        lda     #>sector
        sta     src+1
        jsr     medio
        inc     src+1
        jsr     medio
        jsr     arch_avanzar            ; si era el último sector, el bucle termina antes de leer otro
        jmp     @sector

        ; ---- 6. registros y salto
@copiado:
        ldx     #REG_PRG_TAM
        lda     l_prg16
        sec
        sbc     #1
        jsr     fpga_reg
        ldx     #REG_CHR_TAM
        lda     l_chr8
        bne     @rom_chr
        lda     #$FF                    ; CHR-RAM: bit 7 y máscara abierta, como el v13
        bne     @chr
@rom_chr:
        sec
        sbc     #1
@chr:   jsr     fpga_reg
        ldx     #REG_MAP_CFG
        lda     l_cfg
        jsr     fpga_reg
        ldx     #REG_CART_CFG
        lda     #0                      ; reset corto: el reset vuelve al OS
        jsr     fpga_reg
        lda     #1
        sta     en_juego
        jmp     ram_lanzar

; Abre EDFC desde la raíz. Acarreo = 1 si no está.
abrir_edfc:
        jsr     dir_abrir_raiz
        lda     #<n_edfc
        sta     nombre
        lda     #>n_edfc
        sta     nombre+1
        jsr     dir_buscar
        bcs     @no
        jsr     dir_abrir
        clc
@no:    rts

; Copia medio sector (256 bytes en `src`) en dos tramos: Y = 0-15 y 16-255. Como la cabecera mide 16 bytes, los
; cambios de banco de la PRG, el paso de PRG a CHR y los tramos de 8 KiB de CHR caen siempre entre dos tramos.
medio:  lda     primera
        beq     @a
        lda     #0                      ; la cabecera iNES: no se copia
        sta     primera
        beq     @b
@a:     ldy     #0
        lda     #16
        jsr     tramo
@b:     ldy     #16
        lda     #0                      ; 0 = hasta 256
; Copia (src),Y desde Y hasta A (sin incluirlo) a la PRG mientras quede, y después a la CHR.
tramo:  sta     yfin
        sty     y0
        lda     prg_rest
        ora     prg_rest+1
        ora     prg_rest+2
        beq     @chr
        sec                             ; destino ajustado para indexar con la misma Y
        lda     dst
        sbc     y0
        sta     dsta
        lda     dst+1
        sbc     #0
        sta     dsta+1
@p:     lda     (src),y
        sta     (dsta),y
        iny
        cpy     yfin
        bne     @p
        jsr     @n                      ; A = bytes copiados
        pha
        clc
        adc     dst
        sta     dst
        bcc     :+
        inc     dst+1
:       lda     dst+1
        cmp     #>(VENTANA + $800)
        bne     :+
        lda     #>VENTANA               ; siguiente banco de 2 KiB
        sta     dst+1
        inc     banco_prg
        ldx     #REG_PRG
        lda     banco_prg
        jsr     fpga_reg
:       pla
        sta     y0
        sec
        lda     prg_rest
        sbc     y0
        sta     prg_rest
        lda     prg_rest+1
        sbc     #0
        sta     prg_rest+1
        lda     prg_rest+2
        sbc     #0
        sta     prg_rest+2
        rts
@chr:   lda     chr_rest
        ora     chr_rest+1
        ora     chr_rest+2
        beq     @fin
@c:     lda     (src),y
        sta     PPUDATA
        iny
        cpy     yfin
        bne     @c
        jsr     @n
        sta     y0
        sec
        lda     chr_rest
        sbc     y0
        sta     chr_rest
        lda     chr_rest+1
        sbc     #0
        sta     chr_rest+1
        lda     chr_rest+2
        sbc     #0
        sta     chr_rest+2
        sec
        lda     chr_banco
        sbc     y0
        sta     chr_banco
        lda     chr_banco+1
        sbc     #0
        sta     chr_banco+1
        ora     chr_banco
        bne     @fin
        inc     banco_chr               ; siguientes 8 KiB
        inc     banco_chr
        jmp     tramo_chr
@fin:   rts
@n:     sec                             ; bytes del tramo: yfin - y0 (16 o 240)
        lda     yfin
        sbc     y0
        rts

; Prepara la PPU para escribir 8 KiB de CHR en los bancos banco_chr - 1 y banco_chr (de 4 KiB).
tramo_chr:
        ldx     #REG_CHR
        lda     banco_chr
        jsr     fpga_reg
        bit     PPUSTATUS
        lda     #0
        sta     PPUADDR
        sta     PPUADDR
        sta     chr_banco
        lda     #$20
        sta     chr_banco+1
        rts

        .segment "RODATA"
firma_ines: .byte "NES", $1A
n_edfc:     .byte "EDFC       "
n_maps:     .byte "MAPS       "
n_maprout:  .byte "MAPROUT BIN"
n_rbf:      .byte "000     RBF"

; ---------------------------------------------------------------------------------------------- en la RAM
; Estas dos rutinas se copian a la RAM de la CPU ($0200) antes de usarlas: mientras el FPGA se configura, y en
; cuanto el mapper deja de ser $FF, el OS ya no está en $8000-$FFFF. No llaman a nada de fuera.
        .segment "RAMCOD"

; Configura el FPGA con los cfg_n bloques de la lectura múltiple ya empezada (tarjeta seleccionada).
; Devuelve A = 0 si llegaron todos los bloques. Mismos pasos que la BIOS: reg 9 a 0 mientras dura, pulso de
; nCONFIG por el reg 6, $4402 = 5 y cada byte del bloque de $4401 a $4403. En esta ventana no se escribe nada en
; $8000-$FFFF (con el reg 9 a 0 ahí está la flash de la BIOS).
ram_config:
        lda     #9
        sta     REG_SEL
        lda     REG_DAT
        pha
        lda     #0
        sta     REG_DAT
        lda     #6                      ; nCONFIG: borra el FPGA
        sta     REG_SEL
        lda     #0
        sta     REG_DAT
        jsr     ram_espera
        lda     #1
        sta     REG_DAT
        jsr     ram_espera
        lda     #2                      ; ráfaga
        sta     REG_SEL
        lda     cfg_reg2
        sta     REG_DAT
        lda     #0
        sta     REG_SEL
        lda     #5
        sta     CPLD_MODO
@bloque:
        ldx     #0                      ; testigo del bloque
        ldy     #0
@t:     lda     REG_DAT
        cmp     #$FE
        beq     @datos
        dex
        bne     @t
        dey
        bne     @t
        ldx     #1                      ; no llega: error
        bne     @fin
@datos: ldy     #0
@p1:    lda     REG_DAT
        sta     CPLD_CFG
        iny
        bne     @p1
@p2:    lda     REG_DAT
        sta     CPLD_CFG
        iny
        bne     @p2
        lda     REG_DAT                 ; CRC
        lda     REG_DAT
        lda     cfg_n
        bne     :+
        dec     cfg_n+1
:       dec     cfg_n
        lda     cfg_n
        ora     cfg_n+1
        bne     @bloque
        ldx     #2                      ; relojes de sobra para que el FPGA termine de arrancar
        lda     #$FF
@x:     sta     CPLD_CFG
        iny
        bne     @x
        dex
        bne     @x                      ; sale con X = 0: bien
@fin:   lda     #3
        sta     CPLD_MODO
        lda     #2                      ; fin de la ráfaga y tarjeta libre
        sta     REG_SEL
        lda     cfg_reg2
        and     #%11111011
        sta     REG_DAT
        ora     #%00000010
        sta     REG_DAT
        lda     #9
        sta     REG_SEL
        pla
        sta     REG_DAT
        stx     cfg_n                   ; resultado
        jsr     ram_espera
        lda     #0                      ; el RBF nuevo arranca con sus registros a cero
        sta     REG_SEL
        lda     cfg_n
        rts

ram_espera:                             ; unos 30 ms
        ldx     #0
        ldy     #$20
@e:     dex
        bne     @e
        dey
        bne     @e
        rts

; Pone el mapper (l_mapper) y salta al juego. Como el v13: reg 131 al principio de un VBlank.
ram_lanzar:
        lda     #REG_MAPPER
        sta     REG_SEL
        bit     PPUSTATUS
@v:     bit     PPUSTATUS
        bpl     @v
        lda     l_mapper
        sta     REG_DAT                 ; desde aquí, $8000-$FFFF es el juego
        lda     #$FF
        sta     APU_CONT
        ldx     #$FD
        txs
        lda     #0
        tax
        tay
        jmp     ($FFFC)
