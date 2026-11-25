; lanzar.s — lanzar un juego: cabecera iNES, MAPROUT, carga del RBF en el FPGA, copia de PRG y CHR, registros del
; FPGA y salto. GPL-3.0-or-later, código propio (docs/bios-n8-clon.md §1-§2, docs/hardware-fpga.md).
;
; El número de mapper va al FPGA TAL CUAL está en la cabecera (el OS v13 cambiaba el 219 por 0 y el 220 por 4).
;
; Pasos de `lanzar` (dir_ent = entrada de la ROM en el directorio; pantalla apagada y sin NMI):
;   1. cabecera iNES: PRG, CHR, mapper, byte 6;
;      partidas (partida.s): primero se guarda la del juego anterior si quedó pendiente (si no se puede, no se
;      lanza nada); con pila (byte 6 bit 1), se busca o se crea EDFC/SAVE/<nombre>.srm y se copia a la PRG-RAM;
;   2. EDFC/MAPROUT.BIN[mapper] = número del RBF ($FF = no hay);
;   3. EDFC/MAPS/NNN.RBF: tiene que estar contiguo, porque se pasa al FPGA con una sola lectura múltiple;
;   4. configurar el FPGA desde la RAM (ram_config): mientras se configura no hay nada en $8000-$FFFF;
;   5. copiar la PRG por la ventana $4800 (reg 128) y la CHR por la PPU (reg 130);
;   6. regs 132 (PRG), 133 (CHR), 134 (byte 6 de la cabecera), 136 (reset corto), 137 (volumen), marca de partida pendiente (con
;      pila), marca en_juego y, desde la RAM, reg 131 = mapper y salto al vector de reset del juego.
; Solo vuelve si algo falla: acarreo = 1 y l_error.

        .setcpu "6502"
        .include "os.inc"

        .export l_sin_partida, r_ini, l_ent, fds_pend, fds_copiar
        .export lanzar, l_error, l_rbf, nombre_rbf, leer_cabecera, l_prg16, l_chr8, l_cfg, abrir_edfc
        .exportzp l_mapper
        .import dir_abrir_raiz, dir_abrir, dir_buscar
        .import fds_reconocer, banco_marca, dir_lba, dir_idx
        .import __FDSOVL_LOAD__, __FDSOVL_RUN__, __FDSOVL_SIZE__
        .import arch_abrir, arch_leer, arch_contiguo
        .import arch_lba, arch_tam, arch_ini, fat_error, sector
        .import tramo_ini, tramo_sig, tr_lba, tr_n, tr_fin, fat_desp
        .importzp E_FIN, E_DATOS
        .import sd_multi_ini, sd_parar, sd_base
        .import en_juego, vol_reg
        .import partida_nombre, partida_preparar, partida_marcar, partida_pendiente, pt_sect_nueva, pt_eep_tam
        .import eep_cargar, eep_aviso
        .importzp sd_lba, nombre
        .import __RAMCOD_LOAD__, __RAMCOD_RUN__, __RAMCOD_SIZE__

REG_PRG      = 128              ; banco de 2 KiB de la SRAM PRG en $4800-$4FFF
REG_MAPPER   = 131
REG_PRG_TAM  = 132
REG_CHR_TAM  = 133
REG_MAP_CFG  = 134
REG_CART_CFG = 136
REG_VOLUMEN  = 137              ; volumen del sonido de expansión: 0-8, 4 = calibrado (principal.s: opciones)
VENTANA      = $4800

        .segment "ZEROPAGE"
dsta:       .res 2              ; destino ajustado (destino - Y inicial)
dst:        .res 2              ; destino en la ventana $4800
y0:         .res 1              ; Y inicial del trozo (256 - n)
n_lo:       .res 1              ; tamaño del trozo: 16, 240 o 256 (n_lo = 0, n_hi = 1)
n_hi:       .res 1
bloques:    .res 2              ; bloques que quedan del tramo
cfg_n:      .res 2              ; bloques del RBF que faltan
cfg_reg2:   .res 1              ; reg 2 durante la carga: tarjeta seleccionada y ráfaga
l_mapper:   .res 1

        .segment "BSS"
l_error:    .res 1
l_sin_partida: .res 1           ; 1 = sin partida (modo banco con !ram=XX): ni se carga ni se deja pendiente
l_rbf:      .res 1
l_prg16:    .res 1
l_chr8:     .res 1
l_cfg:      .res 1
l_trainer:  .res 1
l_fds:      .res 1              ; 1 = se lanza un disco FDS (fds_ovl.s)
l_ent:      .res 5              ; sector e índice de la entrada de la ROM en su carpeta
r_ini:      .res 4              ; primer clúster de la ROM
prg_rest:   .res 3              ; bytes de PRG que faltan
chr_rest:   .res 3
chr_banco:  .res 2              ; bytes que faltan del tramo de 8 KiB de CHR
banco_prg:  .res 1
banco_chr:  .res 1
saltar:     .res 2              ; bytes del principio que no se copian (cabecera y «trainer»)
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
        copia4  l_ent, dir_lba          ; la entrada de la ROM (arch_abrir cambia dir_lba)
        lda     dir_idx
        sta     l_ent+4
        jsr     partida_nombre          ; con dir_ent y el nombre largo de la ROM, antes de leer nada más
        lda     #0
        sta     l_error
        sta     fat_error
        sta     l_fds
        ; ---- 1. cabecera
        jsr     arch_abrir
        copia4  r_ini, arch_ini
        jsr     arch_leer
        bcs     falla_sd
        jsr     leer_cabecera
        bcc     @mapper
        cmp     #L_NOINES
        bne     @falla
        jsr     fds_reconocer           ; ¿un disco FDS?
        bcc     @fds
        lda     #L_NOINES
@falla: jmp     falla                   ; A = L_*
@fds:   tax
        bne     @falla                  ; imagen mal o disco con carga propia
        jsr     fds_bios
        bcs     @falla
        lda     #254                    ; 254.RBF; la SRAM PRG entera (BIOS y caras) y CHR-RAM; sin partida
        sta     l_mapper
        lda     #32
        sta     l_prg16
        lda     #0
        sta     l_chr8
        sta     l_cfg
        inc     l_fds
        bne     @pend
@mapper:
        ; ---- 1b. partidas
        jsr     tam_partida             ; con la cabecera aún en `sector`
@pend:  jsr     partida_pendiente       ; la del juego anterior, si quedó sin guardar
        bcs     @no_pend
        jsr     fds_pend                ; y el disco FDS anterior (el juego nuevo pisa la SRAM PRG)
        bcc     :+
@no_pend:
        lda     #L_PENDIENTE
        jmp     falla
:       lda     l_fds
        bne     @sin_pila
        lda     l_sin_partida
        bne     @sin_pila
        jsr     con_pila
        beq     @sin_pila
        jsr     partida_preparar
        bcc     :+
        jmp     falla                   ; A = L_*
:       lda     pt_eep_tam              ; EEPROM: la partida vive en la FPGA, el aviso de apagar con RESET
        ora     pt_eep_tam+1
        beq     @sin_pila
        jsr     banco_marca
        jsr     eep_aviso
@sin_pila:
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

        ; ---- 5. PRG y CHR, con lecturas múltiples por tramos de clústeres seguidos y copia directa
@rom:   lda     l_fds
        beq     @ines
        jsr     fds_carga               ; disco FDS: BIOS, parche y caras (fds_ovl.s)
        bcc     :+
        jmp     falla                   ; A = L_*
:       jmp     @copiado
@ines:  copia4  arch_ini, r_ini
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
        lda     #16                     ; la cabecera, y 512 más si hay «trainer»
        sta     saltar
        lda     l_trainer
        beq     :+
        lda     #2
:       sta     saltar+1
        lda     #>VENTANA
        sta     dst+1
        ldx     #REG_PRG
        lda     #0
        jsr     fpga_reg
        lda     #1                      ; CHR: $0000-$0FFF = banco 0 y $1000-$1FFF = banco 1
        sta     banco_chr
        jsr     tramo_chr
        jsr     tramo_ini
@tramo: jsr     tramo_sig
        bcc     :+
        jmp     falla_sd
:       lda     tr_n                    ; bloques del tramo = clústeres x sectores por clúster
        sta     bloques
        lda     tr_n+1
        sta     bloques+1
        ldx     fat_desp
        beq     @lba
@x:     asl     bloques
        rol     bloques+1
        dex
        bne     @x
@lba:   copia4  sd_lba, tr_lba
        jsr     sd_multi_ini
        bcc     :+
        jmp     falla_sd
:       lda     #2                      ; ráfaga y tarjeta seleccionada; el dato SPI en $4401
        sta     REG_SEL
        lda     sd_base
        ora     #%00000100
        sta     REG_DAT
        lda     #0
        sta     REG_SEL
@bloque:
        jsr     bloque
        bcs     @err_tramo
        lda     saltar
        ora     saltar+1
        ora     prg_rest
        ora     prg_rest+1
        ora     prg_rest+2
        ora     chr_rest
        ora     chr_rest+1
        ora     chr_rest+2
        beq     @todo
        lda     bloques
        bne     :+
        dec     bloques+1
:       dec     bloques
        lda     bloques
        ora     bloques+1
        bne     @bloque
        jsr     sd_parar                ; fin del tramo
        lda     tr_fin
        bne     @corto                  ; el archivo se acaba antes de lo que dice la cabecera
        jmp     @tramo
@todo:  jsr     sd_parar
        jmp     @copiado
@corto: lda     #<E_FIN
        sta     fat_error
        jmp     falla_sd
@err_tramo:
        jsr     sd_parar
        lda     #<E_DATOS
        sta     fat_error
        jmp     falla_sd

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
        ldx     #REG_VOLUMEN
        lda     vol_reg
        jsr     fpga_reg
        lda     l_sin_partida
        bne     @salto
        jsr     con_pila
        beq     @salto
        lda     pt_eep_tam
        ora     pt_eep_tam+1
        beq     @marca
        jsr     banco_marca             ; EEPROM: la partida del banco 8 a la memoria de la FPGA
        jsr     eep_cargar
        bcc     @marca
        jmp     falla                   ; A = L_EEPROM
@marca: jsr     partida_marcar          ; al volver (o al encender, si la RAM tiene pila) se guarda
@salto: lda     #1
        sta     en_juego
        jmp     ram_lanzar

; El código del FDS (fds_ovl.s) corre en el banco 8 de la PRG-RAM, en $7000: estas tres lo ponen en la ventana.
fds_carga:
        jsr     banco_marca
        jmp     __FDSOVL_RUN__
fds_pend:
        jsr     banco_marca
        jmp     __FDSOVL_RUN__ + 3
fds_bios:                               ; la BIOS del usuario a la SRAM PRG y su CRC32
        jsr     banco_marca
        jmp     __FDSOVL_RUN__ + 6

; Al encender (antes de usar la zona de trabajo, donde viene en el OS.BIN): copia el código del FDS al banco 8.
fds_copiar:
        jsr     banco_marca
        lda     #<__FDSOVL_LOAD__
        sta     dsta
        lda     #>__FDSOVL_LOAD__
        sta     dsta+1
        lda     #<__FDSOVL_RUN__
        sta     dst
        lda     #>__FDSOVL_RUN__
        sta     dst+1
        ldx     #>(__FDSOVL_SIZE__ + 255)
        ldy     #0
@c:     lda     (dsta),y
        sta     (dst),y
        iny
        bne     @c
        inc     dsta+1
        inc     dst+1
        dex
        bne     @c
        rts

; Tamaño de una partida nueva, en sectores (pt_sect_nueva), según la cabecera que hay en `sector`: la PRG-NVRAM de
; NES 2.0 (64 << n bytes, entre 8 y 64 KiB); si no la declara, 32 KiB con el MMC5 (5) y 8 KiB con los demás.
; Z = 0 si el juego guarda partida: pila en la cabecera o EEPROM serie (el 157 siempre: la EEPROM de la base).
con_pila:
        lda     l_cfg
        and     #$02
        ora     pt_eep_tam
        ora     pt_eep_tam+1
        rts

; EEPROM serie del Bandai (eeprom.s): 159 = 24C01 (128 bytes), 16 con pila = 24C02 (256), 157 (Datach) = 24C02 de la
; base (256) y, con pila, la 24C01 del cartucho detrás (384). La partida es un sector. Sin EEPROM, pt_eep_tam = 0.
tam_partida:
        lda     #0
        sta     pt_eep_tam
        sta     pt_eep_tam+1
        lda     l_mapper
        cmp     #159
        bne     @n16
        lda     #$80
        sta     pt_eep_tam
        bne     @eep
@n16:   cmp     #16
        bne     @n157
        lda     l_cfg
        and     #$02
        beq     @tam
@e256:  inc     pt_eep_tam+1
@eep:   lda     #1
        sta     pt_sect_nueva
        rts
@n157:  cmp     #157
        bne     @tam
        lda     l_cfg
        and     #$02
        beq     @e256
        lda     #$80
        sta     pt_eep_tam
        bne     @e256
@tam:   lda     #16
        sta     pt_sect_nueva
        lda     sector+7
        and     #$0C
        cmp     #$08
        bne     @ines
        lda     sector+10
        lsr
        lsr
        lsr
        lsr
        beq     @ines
        sec
        sbc     #7                      ; 64 << 7 = 8 KiB
        bcc     @ya
        cmp     #3
        bcc     :+
        lda     #3                      ; 64 KiB como mucho
:       tax
        lda     #16
@d:     cpx     #0
        beq     @fin
        asl
        dex
        jmp     @d
@ines:  lda     l_mapper
        cmp     #5
        bne     @ya
        lda     #64
@fin:   sta     pt_sect_nueva
@ya:    rts

; Cabecera iNES / NES 2.0 que hay en `sector`: l_prg16, l_chr8, l_cfg (byte 6 & $1B), l_trainer y l_mapper.
; Acarreo = 1 si no se puede lanzar (A = L_NOINES, L_TAM o L_SINMAPPER). La usa también el menú (información).
leer_cabecera:
        ldx     #3
@firma: lda     sector,x
        cmp     firma_ines,x
        beq     @ok
        lda     #L_NOINES
        sec
        rts
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
        sec
        rts
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
        ; Byte 7 (nibble alto del mapper), según el formato de la cabecera (regla de nesdev.org):
        ;   bits 3-2 = 10: NES 2.0. Vale siempre, aunque los bytes 12-15 tengan datos (región, mando...). Los
        ;     bits 8-11 del mapper (byte 8) y los de tamaño (byte 9) tienen que ser 0: no hay RBF ni sitio para más.
        ;   bits 3-2 = 00 y bytes 12-15 a cero: iNES. Vale.
        ;   lo demás: cabecera antigua con basura en 7-15 («DiskDude!»): solo el nibble bajo.
        lda     sector+7
        and     #$0C
        cmp     #$08
        bne     @ines
        lda     sector+9
        beq     @n20
        lda     #L_TAM
        sec
        rts
@n20:   lda     sector+8
        and     #$0F
        beq     @alto
        lda     #L_SINMAPPER
        sec
        rts
@ines:  cmp     #0
        bne     @ya
        lda     sector+12
        ora     sector+13
        ora     sector+14
        ora     sector+15
        bne     @ya
@alto:  lda     sector+7
        and     #$F0
        ora     l_mapper
        sta     l_mapper
@ya:    clc
        rts

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

; Un bloque de 512 bytes de la lectura múltiple en curso (ráfaga: cada lectura de $4401 saca un byte). Se reparte
; en tres trozos: 16, 256 y 240 bytes. La cabecera iNES mide 16 bytes (y el «trainer», 512), así que los cambios de
; banco de la PRG, el paso de PRG a CHR y los tramos de 8 KiB de CHR caen siempre en la posición 16 de un bloque:
; cada trozo va entero a un solo destino. Acarreo = 1 si no llega el testigo del bloque.
bloque: ldx     #0
        ldy     #0
@t:     lda     REG_DAT
        cmp     #$FE
        beq     @datos
        dex
        bne     @t
        dey
        bne     @t
        sec
        rts
@datos: lda     #16
        jsr     trozo
        lda     #0                      ; 256
        jsr     trozo
        lda     #240
        jsr     trozo
        lda     REG_DAT                 ; CRC (no se comprueba)
        lda     REG_DAT
        clc
        rts

; Un trozo de A bytes (0 = 256; siempre múltiplo de 4) al destino que toque: se salta, a la PRG o a la CHR.
trozo:  sta     n_lo
        cmp     #1                      ; n_hi = 1 si son 256
        lda     #0
        rol
        eor     #1
        sta     n_hi
        lda     #0                      ; Y empieza en 256 - n y el bucle acaba cuando Y da la vuelta
        sec
        sbc     n_lo
        sta     y0
        tay
        lda     saltar
        ora     saltar+1
        bne     @salta
        lda     prg_rest
        ora     prg_rest+1
        ora     prg_rest+2
        bne     @prg
        lda     chr_rest
        ora     chr_rest+1
        ora     chr_rest+2
        beq     @nada
        jmp     @chr
@nada:  lda     REG_DAT                 ; lo que sobra al final del archivo
        iny
        bne     @nada
        rts
@salta: lda     REG_DAT
        iny
        bne     @salta
        sec
        lda     saltar
        sbc     n_lo
        sta     saltar
        lda     saltar+1
        sbc     n_hi
        sta     saltar+1
        rts

@prg:   sec                             ; puntero = destino - Y inicial, para indexar con Y
        lda     dst
        sbc     y0
        sta     dsta
        lda     dst+1
        sbc     #0
        sta     dsta+1
@p:     lda     REG_DAT
        sta     (dsta),y
        iny
        lda     REG_DAT
        sta     (dsta),y
        iny
        lda     REG_DAT
        sta     (dsta),y
        iny
        lda     REG_DAT
        sta     (dsta),y
        iny
        bne     @p
        clc                             ; destino += n
        lda     dst
        adc     n_lo
        sta     dst
        lda     dst+1
        adc     n_hi
        sta     dst+1
        cmp     #>(VENTANA + $800)
        bne     :+
        lda     #>VENTANA               ; siguiente banco de 2 KiB
        sta     dst+1
        inc     banco_prg
        ldx     #REG_PRG
        lda     banco_prg
        jsr     fpga_reg
        lda     #0                      ; deja seleccionado otra vez el dato SPI
        sta     REG_SEL
:       sec
        lda     prg_rest
        sbc     n_lo
        sta     prg_rest
        lda     prg_rest+1
        sbc     n_hi
        sta     prg_rest+1
        lda     prg_rest+2
        sbc     #0
        sta     prg_rest+2
        rts

@chr:   lda     REG_DAT
        sta     PPUDATA
        iny
        lda     REG_DAT
        sta     PPUDATA
        iny
        lda     REG_DAT
        sta     PPUDATA
        iny
        lda     REG_DAT
        sta     PPUDATA
        iny
        bne     @chr
        sec
        lda     chr_rest
        sbc     n_lo
        sta     chr_rest
        lda     chr_rest+1
        sbc     n_hi
        sta     chr_rest+1
        lda     chr_rest+2
        sbc     #0
        sta     chr_rest+2
        sec
        lda     chr_banco
        sbc     n_lo
        sta     chr_banco
        lda     chr_banco+1
        sbc     n_hi
        sta     chr_banco+1
        ora     chr_banco
        bne     :+
        inc     banco_chr               ; siguientes 8 KiB
        inc     banco_chr
        jsr     tramo_chr
        lda     #0                      ; deja seleccionado otra vez el dato SPI
        sta     REG_SEL
:       rts

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
