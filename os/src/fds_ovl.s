; fds_ovl.s — montar un disco FDS en la SRAM PRG antes de lanzarlo y guardarlo en la SD al volver (etapa F4,
; docs/fds-diseno.md). GPL-3.0-or-later, código propio.
;
; No cabe en la ROM del OS: va en el OS.BIN en el sitio de la zona de trabajo ($D400) y, al encender, antes de usar
; esa zona, el OS lo copia al banco 8 de la PRG-RAM ($7000, con pila: sobrevive a los resets). Se llama con el banco
; 8 en la ventana $6000 (lanzar.s: fds_carga y fds_pend) y nunca cambia el reg 129.
;
;   $7006 fds_bios       (antes de cargar el RBF) busca EDFC/DISKSYS.ROM, la copia a la SRAM PRG (0x7E000) y la
;                        reconoce por su CRC32 (con una tabla de 256 entradas que se hace en el banco 8): acarreo = 0
;                        y A = índice si se sabe parchear; si no, acarreo = 1 y A = L_SINBIOS, L_BIOSEMU, L_BIOSRARA
;                        o L_SD. Lee la BIOS una sola vez (antes, una para la suma y otra para copiarla).
;   $7000 fds_cargar     con el 254.RBF ya en el FPGA (modo OS): bloque del parche en 0x7D000 y número de caras en
;                        0x7DFFF, los enganches del parche en la BIOS de 0x7E000, cara k en k x 64 KiB con las
;                        lecturas de $4030/$4032/$4033 cambiadas (como tools/fds/fds.py: cambiar_cara) y la marca
;                        N8FD. Las caras se leen por tramos de clústeres seguidos (una lectura múltiple por tramo) y
;                        van del SPI a la ventana sin pasar por un búfer. Acarreo = 1 si falla: A = L_SD (fat_error)
;   $7003 fds_pendiente  si hay marca N8FD: deshace el cambio (fds.py: deshacer_cara) y escribe en el .fds los
;                        sectores que el juego cambió. A = 0 (nada), M_DISCO (guardado), M_PERDIDA (el archivo o el
;                        disco de la SRAM ya no son los de la marca: se borra sin escribir) con acarreo = 0; con
;                        acarreo = 1, A = M_NOGUARDADA (pt_err): la marca se queda para otro intento
;
; Banco 8 ($6000): $6000 N8SV y $6040 último juego (principal.s), $6180 marca N8FD, $6200 N8BK (banco.s), $6300
; lista de cambios (3 bytes: cara y posición del byte bajo), $6600 búfer de un sector, $6800 variables, $7000 código.
; La SRAM PRG no tiene pila: al encender (TIPO_FRIO) la marca se borra sin escribir nada.

        .setcpu "6502"
        .include "os.inc"

        .import tipo_arranque, pt_err, fds_caras, fds_desp, r_ini, l_ent, abrir_edfc
        .import dir_buscar, arch_abrir, arch_leer, arch_avanzar, arch_reabrir, arch_ini, arch_lba, sector
        .import fat_error, leer_sector, ent_clus, sd_escribir_sector, sd_error, arch_tam
        .import tramo_ini, tramo_sig, tr_lba, tr_n, tr_fin, fat_desp, sd_multi_ini, sd_parar, sd_base
        .importzp sd_lba, sd_ptr, dir_ent, nombre, clus, E_FIN, E_DATOS

REG_PRG   = 128                 ; banco de 2 KiB de la SRAM PRG en $4800-$4FFF
VENTANA   = $4800
MARCA     = $6180
LISTA     = $6300
BUF       = $6600
MAX_CAMB  = 255
CARA_LO   = <65500
CARA_HI   = >65500
K_FIJO    = 7                   ; 0x70000-0x7FFFF: el parche (pos. $D000) y la BIOS (pos. $E000)

        .segment "ZEROPAGE"
o_k:        .res 1              ; cara (o K_FIJO)
o_pos:      .res 2              ; posición en la cara
o_p:        .res 2              ; puntero en la ventana
o_bp:       .res 2              ; puntero en el búfer
o_lp:       .res 2              ; puntero en la lista de cambios
o_n:        .res 1              ; bytes del trozo (1-255)
o_y0:       .res 1              ; 256 - o_n: los bucles rápidos van con Y de o_y0 a 0 sobre o_bp = o_p - o_y0
o_t:        .res 1

        .segment "FDSBSS"
o_i:        .res 2              ; posición en el sector (0-512)
o_hdr:      .res 1              ; bytes de la cabecera fwNES que faltan por saltar
o_sentido:  .res 1              ; 0 = búfer -> SRAM (cargar), 1 = SRAM -> búfer (guardar)
o_bufb:     .res 2              ; el búfer del sector
o_caras:    .res 1
o_cuenta:   .res 1
o_j:        .res 1
o_y:        .res 1
o_yb:       .res 1
o_tam:      .res 2
o_tipo:     .res 1
o_fin:      .res 2
o_ultimo:   .res 1
o_base:     .res 2
o_b1:       .res 1
o_ncamb:    .res 1
MARCA_TAM = 22
o_bloques:  .res 2              ; bloques que quedan del tramo
o_crc:      .res 4
o_c:        .res 4
crc_t0:     .res 256            ; CRC32: los 4 bytes de cada entrada de la tabla, por separado
crc_t1:     .res 256
crc_t2:     .res 256
crc_t3:     .res 256
o_marca:    .res MARCA_TAM      ; "N8FD", versión, entrada (lba 4, índice 1), clúster (4), tamaño (4), caras,
                                ; cabecera (0 o 16), cambios, suma
M_LBA  = 5
M_IDX  = 9
M_CLUS = 10
M_TAM  = 14
M_CARAS = 18
M_DESP = 19
M_NCAMB = 20
M_SUMA = 21

        .segment "FDSOVL"
        jmp     fds_cargar              ; $7000
        jmp     fds_pendiente           ; $7003
        jmp     fds_bios                ; $7006

; ------------------------------------------------------------------------------------------------ cargar
fds_cargar:
        ; ---- el bloque del parche en 0x7D000 y el número de caras en 0x7DFFF
        lda     #K_FIJO
        sta     o_k
        lda     #<$D000
        sta     o_pos
        lda     #>$D000
        sta     o_pos+1
        jsr     fijar
        ldy     #0
@p1:    lda     parche,y
        sta     (o_p),y
        iny
        bne     @p1
        inc     o_p+1
@p2:    lda     parche+256,y
        sta     (o_p),y
        iny
        cpy     #<(PARCHE_TAM - 256)
        bne     @p2
        lda     #<$DFFF
        sta     o_pos
        lda     #>$DFFF
        sta     o_pos+1
        lda     fds_caras
        jsr     escribir_b
        jmp     @enganches
@err:   lda     #L_SD
        sec
        rts
        ; ---- los enganches de la tabla del parche, en la copia de la BIOS
@enganches:
        clc
        lda     parche+6
        adc     #<(parche - $5000)
        sta     o_bp
        lda     parche+7
        adc     #>(parche - $5000)
        sta     o_bp+1
@e:     ldy     #0
        lda     (o_bp),y
        sta     o_pos
        iny
        lda     (o_bp),y
        sta     o_pos+1
        ora     o_pos
        beq     @caras
        iny
        lda     (o_bp),y
        sta     o_cuenta
        clc
        lda     o_bp
        adc     #3
        sta     o_bp
        bcc     :+
        inc     o_bp+1
:       lda     #0
        sta     o_j
@eb:    ldy     o_j
        lda     (o_bp),y
        jsr     escribir_b
        inc     o_pos
        bne     :+
        inc     o_pos+1
:       inc     o_j
        lda     o_j
        cmp     o_cuenta
        bne     @eb
        clc
        lda     o_bp
        adc     o_cuenta
        sta     o_bp
        bcc     @e
        inc     o_bp+1
        jmp     @e
        ; ---- las caras: cara k en k x 64 KiB, por tramos de clústeres seguidos
@caras: ldx     #3
@ini:   lda     r_ini,x
        sta     arch_ini,x
        dex
        bpl     @ini
        jsr     tramo_ini
        lda     fds_caras
        sta     o_caras
        lda     fds_desp
        sta     o_hdr
        lda     #0
        sta     o_k
        sta     o_pos
        sta     o_pos+1
@tramo: jsr     tramo_sig
        bcc     :+
        jmp     @err
:       lda     tr_n                    ; bloques del tramo = clústeres x sectores por clúster
        sta     o_bloques
        lda     tr_n+1
        sta     o_bloques+1
        ldx     fat_desp
        beq     @lba
@x:     asl     o_bloques
        rol     o_bloques+1
        dex
        bne     @x
@lba:   ldx     #3
@l:     lda     tr_lba,x
        sta     sd_lba,x
        dex
        bpl     @l
        jsr     sd_multi_ini
        bcc     :+
        jmp     @err
:       lda     #2                      ; ráfaga y tarjeta seleccionada; el dato SPI en $4401
        sta     REG_SEL
        lda     sd_base
        ora     #%00000100
        sta     REG_DAT
        lda     #0
        sta     REG_SEL
@bloque:
        jsr     bloque_sd
        bcs     @err_tramo
        lda     o_k
        cmp     o_caras
        bcs     @todo
        lda     o_bloques
        bne     :+
        dec     o_bloques+1
:       dec     o_bloques
        lda     o_bloques
        ora     o_bloques+1
        bne     @bloque
        jsr     sd_parar                ; fin del tramo
        lda     tr_fin
        beq     @tramo
        lda     #<E_FIN                 ; el archivo se acaba antes que las caras
        sta     fat_error
        jmp     @err
@err_tramo:
        jsr     sd_parar
        lda     #<E_DATOS
        sta     fat_error
        jmp     @err
@todo:  jsr     sd_parar
        ; ---- las lecturas de $4030/$4032/$4033 en los archivos de programa
@cambiar:
        lda     #0
        sta     o_ncamb
        lda     #<LISTA
        sta     o_lp
        lda     #>LISTA
        sta     o_lp+1
        lda     #0
        sta     o_j
@cc:    lda     o_j
        jsr     cambiar_cara
        inc     o_j
        lda     o_j
        cmp     o_caras
        bne     @cc
        ; ---- la marca
        ldx     #4
@f:     lda     firma,x
        sta     o_marca,x
        dex
        bpl     @f
        ldx     #4
@ent:   lda     l_ent,x                 ; sector e índice de la entrada del .fds
        sta     o_marca+M_LBA,x
        dex
        bpl     @ent
        ldx     #3
@cl:    lda     r_ini,x
        sta     o_marca+M_CLUS,x
        dex
        bpl     @cl
        lda     fds_desp                ; tamaño = cabecera + caras x 65 500
        sta     o_marca+M_TAM
        lda     #0
        sta     o_marca+M_TAM+1
        sta     o_marca+M_TAM+2
        sta     o_marca+M_TAM+3
        ldx     o_caras
@tm:    clc
        lda     o_marca+M_TAM
        adc     #CARA_LO
        sta     o_marca+M_TAM
        lda     o_marca+M_TAM+1
        adc     #CARA_HI
        sta     o_marca+M_TAM+1
        lda     o_marca+M_TAM+2
        adc     #0
        sta     o_marca+M_TAM+2
        dex
        bne     @tm
        lda     o_caras
        sta     o_marca+M_CARAS
        lda     fds_desp
        sta     o_marca+M_DESP
        lda     o_ncamb
        sta     o_marca+M_NCAMB
        jsr     suma
        sta     o_marca+M_SUMA
        ldx     #MARCA_TAM - 1
@m:     lda     o_marca,x
        sta     MARCA,x
        dex
        bpl     @m
        clc
        rts

; ------------------------------------------------------------------------------------------------ guardar
fds_pendiente:
        ldx     #MARCA_TAM - 1
@l:     lda     MARCA,x
        sta     o_marca,x
        dex
        bpl     @l
        ldx     #4
@f:     lda     o_marca,x
        cmp     firma,x
        bne     @nada
        dex
        bpl     @f
        jsr     suma
        cmp     o_marca+M_SUMA
        beq     @hay
@nada:  lda     #0
        clc
        rts
@hay:   lda     tipo_arranque           ; al encender, la SRAM PRG ya no tiene el disco
        bne     :+
        jsr     borrar
        lda     #0
        clc
        rts
        ; ---- ¿la entrada sigue siendo el .fds de la marca?
:       ldx     #3
@lb:    lda     o_marca+M_LBA,x
        sta     sd_lba,x
        dex
        bpl     @lb
        jsr     leer_sector
        bcc     :+
        jmp     @err_fat
:       lda     o_marca+M_IDX           ; dir_ent = sector + 32 x índice
        and     #$0F
        sta     o_t
        lda     #0
        ldx     #5
@x:     asl     o_t
        rol
        dex
        bne     @x
        sta     dir_ent+1
        clc
        lda     o_t
        adc     #<sector
        sta     dir_ent
        lda     dir_ent+1
        adc     #>sector
        sta     dir_ent+1
        ldy     #0
        lda     (dir_ent),y
        beq     @perdido
        cmp     #$E5
        beq     @perdido
        ldy     #11
        lda     (dir_ent),y
        and     #$18
        bne     @perdido
        jsr     ent_clus
        ldx     #3
@c:     lda     clus,x
        cmp     o_marca+M_CLUS,x
        bne     @perdido
        dex
        bpl     @c
        ldy     #31
        ldx     #3
@t:     lda     (dir_ent),y
        cmp     o_marca+M_TAM,x
        bne     @perdido
        dey
        dex
        bpl     @t
        ; ---- ¿la SRAM sigue teniendo el disco? cada cara empieza por $01 y «*NINTENDO-HVC*»
        lda     o_marca+M_CARAS
        sta     o_caras
        lda     #0
        sta     o_k
@vk:    lda     #0
        sta     o_pos
        sta     o_pos+1
        jsr     fijar
        ldy     #14
@vb:    lda     (o_p),y
        cmp     bloque1,y
        bne     @perdido
        dey
        bpl     @vb
        inc     o_k
        lda     o_k
        cmp     o_caras
        bne     @vk
        beq     @deshacer
@perdido:
        jsr     borrar
        lda     #M_PERDIDA
        clc
        rts
        ; ---- deshacer el cambio donde sigue (si el juego reescribió el archivo, lo suyo se queda)
@deshacer:
        lda     #<LISTA
        sta     o_lp
        lda     #>LISTA
        sta     o_lp+1
        lda     o_marca+M_NCAMB
        sta     o_cuenta
@d:     lda     o_cuenta
        beq     @comparar
        ldy     #0
        lda     (o_lp),y
        sta     o_k
        iny
        lda     (o_lp),y
        sta     o_pos
        iny
        lda     (o_lp),y
        sta     o_pos+1
        jsr     leer_b
        clc
        adc     #2
        sta     o_b1
        jsr     es_reg
        bne     @dsig
        inc     o_pos
        bne     :+
        inc     o_pos+1
:       jsr     leer_b
        cmp     #$42
        bne     @dsig
        lda     #$40
        jsr     escribir_b
        lda     o_pos
        bne     :+
        dec     o_pos+1
:       dec     o_pos
        lda     o_b1
        jsr     escribir_b
@dsig:  clc
        lda     o_lp
        adc     #3
        sta     o_lp
        bcc     :+
        inc     o_lp+1
:       dec     o_cuenta
        jmp     @d
        ; ---- comparar cada sector del .fds con la SRAM y escribir los que cambiaron
@comparar:
        ldx     #3
@ini:   lda     o_marca+M_CLUS,x
        sta     arch_ini,x
        dex
        bpl     @ini
        jsr     arch_reabrir
        lda     o_marca+M_DESP
        sta     o_hdr
        lda     #0
        sta     o_k
        sta     o_pos
        sta     o_pos+1
        lda     #1
        sta     o_sentido
        lda     #<BUF
        sta     o_bufb
        lda     #>BUF
        sta     o_bufb+1
@s:     jsr     arch_leer
        bcs     @err_fat
        ldy     #0                      ; lo que no es del disco (cabecera fwNES), tal cual
@cp:    lda     sector,y
        sta     BUF,y
        lda     sector+256,y
        sta     BUF+256,y
        iny
        bne     @cp
        jsr     procesar
        ldy     #0
@cmp:   lda     sector,y
        cmp     BUF,y
        bne     @escribir
        lda     sector+256,y
        cmp     BUF+256,y
        bne     @escribir
        iny
        bne     @cmp
        beq     @sig
@escribir:
        ldx     #3
@el:    lda     arch_lba,x
        sta     sd_lba,x
        dex
        bpl     @el
        lda     #<BUF
        sta     sd_ptr
        lda     #>BUF
        sta     sd_ptr+1
        jsr     sd_escribir_sector
        bcs     @err_sd
@sig:   lda     o_k
        cmp     o_caras
        bcs     @hecho
        jsr     arch_avanzar
        bcc     @s
@err_fat:
        lda     fat_error
        jmp     @mal
@err_sd:
        lda     sd_error
@mal:   sta     pt_err
        lda     #M_NOGUARDADA
        sec
        rts
@hecho: jsr     borrar
        lda     #M_DISCO
        clc
        rts

; ------------------------------------------------------------------------------------------------ BIOS
fds_bios:
        jsr     abrir_edfc
        bcs     @falta
        lda     #<n_bios
        sta     nombre
        lda     #>n_bios
        sta     nombre+1
        jsr     dir_buscar
        bcc     @hay
@falta: lda     fat_error
        bne     @sd
        lda     #L_SINBIOS
        sec
        rts
@hay:   jsr     arch_abrir
        lda     arch_tam                ; 8192 bytes justos
        ora     arch_tam+2
        ora     arch_tam+3
        bne     @rara_l
        lda     arch_tam+1
        cmp     #$20
        beq     :+
@rara_l:
        jmp     @rara
:       jsr     crc_tabla
        lda     #$FF
        ldx     #3
@c0:    sta     o_crc,x
        dex
        bpl     @c0
        lda     #K_FIJO
        sta     o_k
        lda     #<$E000
        sta     o_pos
        lda     #>$E000
        sta     o_pos+1
        lda     #16
        sta     o_cuenta
@s:     jsr     arch_leer
        bcs     @sd
        jsr     fijar
        ldy     #0
@b1:    lda     sector,y
        sta     (o_p),y
        jsr     crc_byte
        iny
        bne     @b1
        inc     o_p+1
@b2:    lda     sector+256,y
        sta     (o_p),y
        jsr     crc_byte
        iny
        bne     @b2
        inc     o_pos+1
        inc     o_pos+1
        dec     o_cuenta
        beq     @suma
        jsr     arch_avanzar
        bcc     @s
@sd:    lda     #L_SD
        sec
        rts
@suma:  ldx     #3
@f:     lda     o_crc,x
        eor     #$FF
        sta     o_crc,x
        dex
        bpl     @f
        ldx     #0                      ; ¿está en la tabla de BIOS conocidas?
@e:     cpx     #FDS_BIOS_N
        bcs     @rara
        txa
        asl
        asl
        tay
        lda     fds_bios_crc,y
        cmp     o_crc
        bne     @sig
        lda     fds_bios_crc+1,y
        cmp     o_crc+1
        bne     @sig
        lda     fds_bios_crc+2,y
        cmp     o_crc+2
        bne     @sig
        lda     fds_bios_crc+3,y
        cmp     o_crc+3
        beq     @esta
@sig:   inx
        bne     @e
@esta:  cpx     #FDS_BIOS_SI
        bcs     @emu
        txa
        clc
        rts
@emu:   lda     #L_BIOSEMU
        sec
        rts
@rara:  lda     #L_BIOSRARA
        sec
        rts

; Tabla del CRC-32 de zlib (polinomio $EDB88320, reflejado), byte a byte, en crc_t0-crc_t3.
crc_tabla:
        ldx     #0
@i:     stx     o_c
        lda     #0
        sta     o_c+1
        sta     o_c+2
        sta     o_c+3
        ldy     #8
@b:     lsr     o_c+3
        ror     o_c+2
        ror     o_c+1
        ror     o_c
        bcc     @n
        lda     o_c+3
        eor     #$ED
        sta     o_c+3
        lda     o_c+2
        eor     #$B8
        sta     o_c+2
        lda     o_c+1
        eor     #$83
        sta     o_c+1
        lda     o_c
        eor     #$20
        sta     o_c
@n:     dey
        bne     @b
        lda     o_c
        sta     crc_t0,x
        lda     o_c+1
        sta     crc_t1,x
        lda     o_c+2
        sta     crc_t2,x
        lda     o_c+3
        sta     crc_t3,x
        inx
        bne     @i
        rts

; crc = (crc >> 8) ^ tabla[(crc ^ A) & $FF]. Usa X; no toca Y.
crc_byte:
        eor     o_crc
        tax
        lda     o_crc+1
        eor     crc_t0,x
        sta     o_crc
        lda     o_crc+2
        eor     crc_t1,x
        sta     o_crc+1
        lda     o_crc+3
        eor     crc_t2,x
        sta     o_crc+2
        lda     crc_t3,x
        sta     o_crc+3
        rts

; ------------------------------------------------------------------------------------------------ comunes
; Un bloque de 512 bytes de la lectura múltiple en curso (cada lectura de $4401 saca un byte), repartido entre las
; caras desde (o_k, o_pos): primero se salta lo que quede de la cabecera fwNES y, acabado el disco, lo que sobre.
; Acarreo = 1 si no llega el testigo del bloque.
bloque_sd:
        ldx     #0
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
@datos: lda     #0
        sta     o_i
        sta     o_i+1
        ldx     o_hdr
        beq     @l
        stx     o_i
@h:     lda     REG_DAT
        dex
        bne     @h
        stx     o_hdr                   ; X = 0
@l:     lda     o_i+1
        cmp     #>512
        bcs     @crc
        lda     o_k
        cmp     o_caras
        bcs     @resto
        jsr     medir
        jsr     fijar
        jsr     rapido
@c:     lda     REG_DAT
        sta     (o_bp),y
        iny
        bne     @c
        jsr     avanzar
        jmp     @l
@resto: lda     REG_DAT                 ; lo que sobra detrás de la última cara
        inc     o_i
        bne     :+
        inc     o_i+1
:       lda     o_i+1
        cmp     #>512
        bcc     @resto
@crc:   lda     REG_DAT                 ; CRC (no se comprueba)
        lda     REG_DAT
        clc
        rts

; o_n = lo menor de 255 y de lo que queda del sector (512 - o_i), de la cara y del banco de 2 KiB de la ventana.
medir:  lda     #255
        sta     o_n
        sec
        lda     #<512
        sbc     o_i
        tax
        lda     #>512
        sbc     o_i+1
        jsr     menor
        sec
        lda     #CARA_LO
        sbc     o_pos
        tax
        lda     #CARA_HI
        sbc     o_pos+1
        jsr     menor
        jmp     hasta_banco

; o_i y o_pos avanzan o_n; al final de una cara se pasa a la siguiente.
avanzar:
        clc
        lda     o_i
        adc     o_n
        sta     o_i
        bcc     :+
        inc     o_i+1
:       lda     o_n
        jsr     mas_pos
        lda     o_pos
        cmp     #CARA_LO
        bne     @ya
        lda     o_pos+1
        cmp     #CARA_HI
        bne     @ya
        lda     #0
        sta     o_pos
        sta     o_pos+1
        inc     o_k
@ya:    rts

; Reparte el sector que hay en el búfer (o_bufb) entre las caras, desde (o_k, o_pos): con o_sentido = 0 lo copia
; a la SRAM y con 1 copia la SRAM al búfer. Primero se salta lo que quede de la cabecera fwNES.
procesar:
        lda     #0
        sta     o_i
        sta     o_i+1
        lda     o_hdr
        beq     @l
        sta     o_i
        lda     #0
        sta     o_hdr
@l:     lda     o_k
        cmp     o_caras
        bcc     :+
        jmp     @fin
:
        lda     o_i+1
        cmp     #>512
        bcs     @fin
        jsr     medir
        jsr     fijar
        clc
        lda     o_bufb
        adc     o_i
        sta     o_bp
        lda     o_bufb+1
        adc     o_i+1
        sta     o_bp+1
        ldy     #0
        lda     o_sentido
        bne     @g
@c:     lda     (o_bp),y
        sta     (o_p),y
        iny
        cpy     o_n
        bne     @c
        beq     @avanza
@g:     lda     (o_p),y
        sta     (o_bp),y
        iny
        cpy     o_n
        bne     @g
@avanza:
        jsr     avanzar
        jmp     @l
@fin:   rts

; Prepara un bucle rápido de o_n bytes en la ventana: Y = o_y0 = 256 - o_n y o_bp = o_p - o_y0, así que
; (o_bp),y recorre o_p ... o_p + o_n - 1 y el bucle acaba cuando Y da la vuelta (sin CPY).
rapido: sec
        lda     #0
        sbc     o_n
        sta     o_y0
        sec
        lda     o_p
        sbc     o_y0
        sta     o_bp
        lda     o_p+1
        sbc     #0
        sta     o_bp+1
        ldy     o_y0
        rts

; A:X = un tope (alto:bajo): si es menor que o_n, pasa a ser o_n.
menor:  cmp     #0
        bne     @no
        cpx     o_n
        bcs     @no
        stx     o_n
@no:    rts

; Tope del banco de 2 KiB de la ventana: 2048 - (o_pos & 2047).
hasta_banco:
        lda     o_pos+1
        and     #$07
        sta     o_t
        sec
        lda     #0
        sbc     o_pos
        tax
        lda     #$08
        sbc     o_t
        jmp     menor

; Ventana en (o_k, o_pos): reg 128 = k x 32 + pos / 2048 y o_p = $4800 + pos % 2048.
fijar:  lda     o_pos+1
        lsr
        lsr
        lsr
        sta     o_t
        lda     o_k
        asl
        asl
        asl
        asl
        asl
        ora     o_t
        ldx     #REG_PRG
        stx     REG_SEL
        sta     REG_DAT
        ldx     #0                      ; deja seleccionado otra vez el dato SPI
        stx     REG_SEL
        lda     o_pos
        sta     o_p
        lda     o_pos+1
        and     #$07
        ora     #>VENTANA
        sta     o_p+1
        rts

; A = el byte de (o_k, o_pos).
leer_b: jsr     fijar
        ldy     #0
        lda     (o_p),y
        rts

; El byte A a (o_k, o_pos).
escribir_b:
        pha
        jsr     fijar
        pla
        ldy     #0
        sta     (o_p),y
        rts

; o_pos += A.
mas_pos:
        clc
        adc     o_pos
        sta     o_pos
        bcc     :+
        inc     o_pos+1
:       rts

; Z = 1 si A es $30, $32 o $33.
es_reg: cmp     #$30
        beq     @si
        cmp     #$32
        beq     @si
        cmp     #$33
@si:    rts

; Z = 1 si A es una de las instrucciones de lectura absoluta (fds.py: OPS_LEER).
es_op:  ldx     #OPS_N - 1
@b:     cmp     ops,x
        beq     @si
        dex
        bpl     @b
@si:    rts

borrar: lda     #0
        ldx     #MARCA_TAM - 1
@b:     sta     MARCA,x
        dex
        bpl     @b
        rts

; A = $A5 más los 21 primeros bytes de la marca.
suma:   lda     #$A5
        ldx     #MARCA_TAM - 2
        clc
@s:     adc     o_marca,x
        dex
        bpl     @s
        rts

; ------------------------------------------------------------------------------------------------ cambiar
; Recorre los archivos de la cara A (como fds.py: leer_cara) y cambia las lecturas en los de programa (tipo 0).
cambiar_cara:
        sta     o_k
        lda     #56
        sta     o_pos
        lda     #0
        sta     o_pos+1
        jsr     leer_b
        cmp     #2
        bne     @no
        lda     #58
        sta     o_pos
@arch:  lda     o_pos+1                 ; cabe la cabecera: pos + 16 <= 65 500
        cmp     #>(65500 - 16)
        bcc     @cabe
        bne     @no
        lda     o_pos
        cmp     #<(65500 - 16) + 1
        bcc     @cabe
@no:    rts
@cabe:  jsr     leer_b
        cmp     #3
        bne     @no
        lda     #13
        jsr     mas_pos
        jsr     leer_b
        sta     o_tam
        lda     #1
        jsr     mas_pos
        jsr     leer_b
        sta     o_tam+1
        lda     #1
        jsr     mas_pos
        jsr     leer_b
        sta     o_tipo
        lda     #1
        jsr     mas_pos                 ; el bloque 4
        lda     o_pos+1
        cmp     #CARA_HI
        bcc     @b4
        bne     @no
        lda     o_pos
        cmp     #CARA_LO
        bcs     @no
@b4:    jsr     leer_b
        cmp     #4
        bne     @no
        lda     #1
        jsr     mas_pos                 ; los datos: de o_pos a o_fin = o_pos + tamaño (hasta el final de la cara)
        lda     #0
        sta     o_ultimo
        clc
        lda     o_pos
        adc     o_tam
        sta     o_fin
        lda     o_pos+1
        adc     o_tam+1
        sta     o_fin+1
        bcs     @recorta
        cmp     #CARA_HI
        bcc     @dentro
        bne     @recorta
        lda     o_fin
        cmp     #CARA_LO + 1
        bcc     @dentro
@recorta:
        lda     #CARA_LO
        sta     o_fin
        lda     #CARA_HI
        sta     o_fin+1
        inc     o_ultimo
@dentro:
        lda     o_tipo
        bne     :+
        jsr     escanear
:       lda     o_ultimo
        bne     @fin
        lda     o_fin
        sta     o_pos
        lda     o_fin+1
        sta     o_pos+1
        jmp     @arch
@fin:   rts

; Busca en (o_k, o_pos..o_fin) cada $40 precedido de un registro ($30/$32/$33) y de una instrucción de lectura.
escanear:
        lda     #2
        jsr     mas_pos                 ; el $40 va dos bytes detrás de la instrucción
@trozo: lda     o_pos
        cmp     o_fin
        lda     o_pos+1
        sbc     o_fin+1
        bcs     @fin
        lda     #255
        sta     o_n
        sec
        lda     o_fin
        sbc     o_pos
        tax
        lda     o_fin+1
        sbc     o_pos+1
        jsr     menor
        jsr     hasta_banco
        jsr     fijar
        jsr     rapido
@b:     lda     (o_bp),y
        cmp     #$40
        beq     @hay
@sig:   iny
        bne     @b
        lda     o_n
        jsr     mas_pos
        jmp     @trozo
@hay:   sty     o_yb                    ; Y del bucle
        tya
        sec
        sbc     o_y0
        sta     o_y                     ; posición del $40 en el trozo
        jsr     mirar
        jsr     fijar                   ; mirar movió la ventana (o_bp sigue valiendo)
        ldy     o_yb
        jmp     @sig
@fin:   rts

; El $40 está en o_pos + o_y. Si delante hay registro e instrucción de lectura (y cabe en la lista): registro - 2
; y $42 en su lugar (la suma de los bytes no cambia), y apunta el cambio. o_pos queda igual.
mirar:  lda     o_pos
        sta     o_base
        lda     o_pos+1
        sta     o_base+1
        lda     o_ncamb
        cmp     #MAX_CAMB
        bcs     @fin
        lda     o_y
        jsr     mas_pos
        lda     o_pos                   ; o_pos = el registro
        bne     :+
        dec     o_pos+1
:       dec     o_pos
        jsr     leer_b
        sta     o_b1
        jsr     es_reg
        bne     @fin
        lda     o_pos
        bne     :+
        dec     o_pos+1
:       dec     o_pos
        jsr     leer_b
        jsr     es_op
        bne     @fin
        inc     o_pos                   ; otra vez el registro
        bne     :+
        inc     o_pos+1
:       lda     o_b1
        sec
        sbc     #2
        jsr     escribir_b
        ldy     #0                      ; apunta cara y posición
        lda     o_k
        sta     (o_lp),y
        iny
        lda     o_pos
        sta     (o_lp),y
        iny
        lda     o_pos+1
        sta     (o_lp),y
        clc
        lda     o_lp
        adc     #3
        sta     o_lp
        bcc     :+
        inc     o_lp+1
:       inc     o_ncamb
        inc     o_pos
        bne     :+
        inc     o_pos+1
:       lda     #$42
        jsr     escribir_b
@fin:   lda     o_base
        sta     o_pos
        lda     o_base+1
        sta     o_pos+1
        rts

firma:      .byte "N8FD", 1
bloque1:    .byte $01, "*NINTENDO-HVC*"
n_bios:     .byte "DISKSYS ROM"
        .include "fds_tablas.inc"        ; fds_bios_crc, FDS_BIOS_N, FDS_BIOS_SI (solo sumas)
ops:        .byte $AD, $AE, $AC, $2C, $BD, $B9, $BE, $BC, $0D, $2D, $4D, $CD, $EC, $CC
OPS_N = * - ops

; El bloque del parche (os/src/fds_parche.s, corre en $5000): se copia tal cual a 0x7D000.
parche:     .incbin "fds_parche.bin"
PARCHE_TAM = * - parche
        .assert PARCHE_TAM > 256 && PARCHE_TAM < 512, error, "el bloque del parche debe medir entre 257 y 511 bytes"
