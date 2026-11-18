; partida.s — partidas con pila en EDFC/SAVE. GPL-3.0-or-later, código propio.
;
; Formato: EDFC/SAVE/<nombre de la ROM sin la extensión>.srm, el contenido de la PRG-RAM tal cual desde 0x00000
; (8 KiB por defecto, 32 KiB con el MMC5, o lo que declare una cabecera NES 2.0, hasta 64 KiB). Es lo mismo que un
; .sav de un emulador: se pueden copiar en los dos sentidos. Una ROM sin nombre largo (ZELDA.NES) da ZELDA.SRM; con
; nombre largo, la partida lleva el mismo nombre largo y un nombre 8.3 inventado (8 cifras hexadecimales de un
; resumen del nombre). Varias ROMs con el mismo nombre en carpetas distintas comparten la partida.
;
;   partida_nombre      (al empezar a lanzar, con dir_ent en la entrada de la ROM) prepara el nombre de la partida
;   partida_preparar    busca la partida y, si no está, la crea llena de $FF; la copia a la PRG-RAM
;   partida_marcar      (justo antes de saltar al juego) deja la marca de «partida pendiente» en el banco 8
;   partida_pendiente   si hay marca, vuelca la PRG-RAM encima del archivo y borra la marca
;
; La marca vive en la PRG-RAM 0x10000 (banco 8, ventana $6000): fuera de los 64 KiB de las partidas, fuera de lo
; que carga la BIOS (el OS.BIN propio ocupa 0x18000-0x1FFFF y el v13, 0x12000-0x1FFFF) y ningún mapper la toca. Si
; la RAM tiene pila, sobrevive al apagado: la partida se guarda en el encendido siguiente.
;
; Escritura en la tarjeta: solo se sobrescriben los sectores de un archivo que ya existe, sin cambiar su tamaño. Al
; crear uno, el orden es: huecos en la carpeta (ampliada si hace falta), datos, cadena en la FAT (todas las copias)
; y FSInfo, y la entrada de la carpeta al final. Un corte a medias deja, como mucho, clústeres perdidos.

        .setcpu "6502"
        .include "os.inc"

        .export partida_nombre, partida_preparar, partida_marcar, partida_pendiente, pt_err, pt_sect_nueva
        .export partida_hay_marca, banco_marca, pt_nom, pt_len, igual_largo
        .import dir_abrir_raiz, dir_abrir, dir_abrir_c, dir_buscar, dir_siguiente, ent_clus
        .import arch_abrir, arch_avanzar, arch_lba
        .import fat_error, fat_spc, fat_desp, sector, lfn_val, lfn_crudo, lfn_crudo_n
        .import fat_libres, fat_poner, fat_grabar, fat_info_pista, fat_fin_cadena, dir_huecos
        .import leer_sector, grabar_sector, clus_a_lba
        .import lib_k, lib_ini, fat_v, hc_n, hc_lba, hc_idx, dir_lba, dir_idx
        .import sd_leer_sector, sd_escribir_sector, sd_error
        .importzp dir_ent, nombre, clus, sd_lba, sd_ptr

E_LLENA_FAT = 13                ; fat.s: E_LLENA
REG_RAM     = 129               ; banco de 8 KiB de la PRG-RAM en $6000
VENT        = $6000
BANCO_MARCA = 8
MAX_SECT    = 128               ; 64 KiB
NOM_MAX     = 255               ; caracteres de un nombre largo

        .segment "ZEROPAGE"
pp:         .res 2
qq:         .res 2

        .segment "GRANDE"
pt_nom:     .res 2 * NOM_MAX    ; nombre largo de la partida, UCS-2
pt_len:     .res 1              ; sus caracteres
pt_lfn:     .res 1              ; 1 = la partida lleva nombre largo
pt_corto:   .res 11             ; nombre 8.3
pt_caso:    .res 1              ; byte 12 de la entrada (minúsculas del 8.3)
pt_hash:    .res 4
pt_dclus:   .res 4              ; clúster de EDFC/SAVE
pt_eclus:   .res 4              ; clúster de EDFC
pt_lba:     .res 4              ; sector de la entrada 8.3 de la partida
pt_idx:     .res 1              ; y su número dentro del sector
pt_clus:    .res 4              ; primer clúster del archivo
pt_tam:     .res 4              ; tamaño en bytes
pt_sect_nueva: .res 1           ; sectores de una partida nueva (lo pone lanzar.s: 16-128)
pt_sect:    .res 1              ; sectores que se copian
pt_i:       .res 1
pt_n:       .res 1              ; entradas de la carpeta (nombre largo + 8.3)
pt_ent:     .res 32             ; entrada que se está montando
pt_cur:     .res 4              ; sector de la carpeta que hay en `sector`
pt_cur_ok:  .res 1
pt_col:     .res 1              ; 1 = el nombre 8.3 inventado ya lo usa otro archivo
pt_hallada: .res 1
pt_intentos: .res 1
pt_ck:      .res 1
pt_err:     .res 1              ; fat_error del último fallo (para el mensaje)
MARCA_TAM = 19
pt_marca:   .res MARCA_TAM      ; "N8SV", versión, lba(4), idx, clus(4), tam(4), suma

        .segment "CODE"

.macro copia4 destino, origen
        ldx     #3
:       lda     origen,x
        sta     destino,x
        dex
        bpl     :-
.endmacro

; ------------------------------------------------------------------------------------------------ nombre
; Con dir_ent en la entrada 8.3 de la ROM y lfn_val/lfn_crudo recién leídos con ella.
partida_nombre:
        ldy     #10
@c:     lda     (dir_ent),y
        sta     pt_corto,y
        dey
        bpl     @c
        ldy     #12
        lda     (dir_ent),y
        and     #$18
        sta     pt_caso
        lda     lfn_val
        sta     pt_lfn
        bne     @largo
        lda     #'S'                    ; ZELDA.NES -> ZELDA.SRM (con las minúsculas que tuviera)
        sta     pt_corto+8
        lda     #'R'
        sta     pt_corto+9
        lda     #'M'
        sta     pt_corto+10
        rts
@largo: lda     #<lfn_crudo
        sta     pp
        lda     #>lfn_crudo
        sta     pp+1
        lda     #<pt_nom
        sta     qq
        lda     #>pt_nom
        sta     qq+1
        lda     lfn_crudo_n             ; trozos guardados (como mucho 20); el nombre, hasta 255 caracteres
        cmp     #21
        bcc     :+
        lda     #20
:       sta     pt_i
        lda     #0
        sta     pt_len
        ldx     pt_i                    ; X = trozos que quedan; pt_sect = caracteres que quedan del trozo
@trozo: lda     #13
        sta     pt_sect
@car:   ldy     #0
        lda     (pp),y
        iny
        ora     (pp),y
        beq     @fin                    ; $0000: fin del nombre
        lda     (pp),y
        dey
        and     (pp),y
        cmp     #$FF
        beq     @fin                    ; $FFFF: relleno
        lda     (pp),y
        sta     (qq),y
        iny
        lda     (pp),y
        sta     (qq),y
        inc     pt_len
        lda     pt_len
        cmp     #NOM_MAX
        beq     @fin
        jsr     avanza_pq
        dec     pt_sect
        bne     @car
        dex
        bne     @trozo
@fin:   ; la extensión: desde el último «.» (que no sea el primer carácter); si no hay, al final
        ldx     pt_len
@punto: dex
        beq     @sin_punto
        txa
        jsr     car_ptr
        ldy     #1
        lda     (pp),y
        bne     @punto
        dey
        lda     (pp),y
        cmp     #'.'
        bne     @punto
        stx     pt_len
@sin_punto:
        lda     pt_len                  ; que quepan los 4 de «.srm»
        cmp     #NOM_MAX - 3
        bcc     :+
        lda     #NOM_MAX - 4
        sta     pt_len
:       jsr     car_ptr
        ldx     #0
        ldy     #0
@ext:   lda     ext_srm,x
        sta     (pp),y
        iny
        lda     #0
        sta     (pp),y
        iny
        inx
        cpx     #4
        bne     @ext
        lda     pt_len
        clc
        adc     #4
        sta     pt_len
        ; resumen del nombre (h = h x 33 + c, sin distinguir mayúsculas de ASCII): el nombre 8.3 inventado
        lda     #<5381
        sta     pt_hash
        lda     #>5381
        sta     pt_hash+1
        lda     #0
        sta     pt_hash+2
        sta     pt_hash+3
        sta     pt_caso
        sta     pt_i
@h:     lda     pt_i
        jsr     car_ptr
        ldy     #1
        lda     (pp),y
        sta     pt_ck
        dey
        lda     (pp),y
        ldx     pt_ck
        bne     :+
        jsr     minus
:       jsr     hash_mas                ; (cambia pp y qq)
        lda     pt_ck
        jsr     hash_mas
        inc     pt_i
        lda     pt_i
        cmp     pt_len
        bne     @h
        jmp     corto_hash

; pp = pt_nom + 2 x A (el carácter número A). No toca X ni Y.
car_ptr:
        asl
        sta     pp
        lda     #0
        rol
        sta     pp+1
        clc
        lda     pp
        adc     #<pt_nom
        sta     pp
        lda     pp+1
        adc     #>pt_nom
        sta     pp+1
        rts

avanza_pq:
        clc
        lda     pp
        adc     #2
        sta     pp
        bcc     :+
        inc     pp+1
:       clc
        lda     qq
        adc     #2
        sta     qq
        bcc     :+
        inc     qq+1
:       rts

; pt_hash = pt_hash x 33 + A.
hash_mas:
        pha
        lda     pt_hash
        sta     qq
        lda     pt_hash+1
        sta     qq+1
        lda     pt_hash+2
        sta     pp
        lda     pt_hash+3
        sta     pp+1
        ldy     #5                      ; x 32
@s:     asl     pt_hash
        rol     pt_hash+1
        rol     pt_hash+2
        rol     pt_hash+3
        dey
        bne     @s
        clc                             ; + h
        lda     pt_hash
        adc     qq
        sta     pt_hash
        lda     pt_hash+1
        adc     qq+1
        sta     pt_hash+1
        lda     pt_hash+2
        adc     pp
        sta     pt_hash+2
        lda     pt_hash+3
        adc     pp+1
        sta     pt_hash+3
        pla                             ; + c
        clc
        adc     pt_hash
        sta     pt_hash
        bcc     @ya
        inc     pt_hash+1
        bne     @ya
        inc     pt_hash+2
        bne     @ya
        inc     pt_hash+3
@ya:    rts

; pt_corto = las 8 cifras hexadecimales de pt_hash + «SRM».
corto_hash:
        ldx     #3
        ldy     #0
@b:     lda     pt_hash,x
        lsr
        lsr
        lsr
        lsr
        jsr     @cifra
        lda     pt_hash,x
        and     #$0F
        jsr     @cifra
        dex
        bpl     @b
        lda     #'S'
        sta     pt_corto+8
        lda     #'R'
        sta     pt_corto+9
        lda     #'M'
        sta     pt_corto+10
        rts
@cifra: cmp     #10
        bcc     :+
        adc     #'A' - 10 - 1 - '0'     ; acarreo = 1
:       adc     #'0'
        sta     pt_corto,y
        iny
        rts

; ------------------------------------------------------------------------------------------------ buscar
; Abre EDFC/SAVE (pt_dclus) y busca la partida. Acarreo = 1: error (A = L_*). Si no, pt_hallada = 1 con pt_lba,
; pt_idx, pt_clus y pt_tam; pt_col = 1 si el nombre 8.3 inventado ya es de otro archivo.
buscar:
        lda     #0
        sta     pt_hallada
        sta     pt_col
        jsr     dir_abrir_raiz
        lda     #<n_edfc
        sta     nombre
        lda     #>n_edfc
        sta     nombre+1
        jsr     dir_buscar
        bcc     :+
        jmp     @sin_save
:       jsr     ent_clus
        copia4  pt_eclus, clus
        jsr     dir_abrir
        lda     #<n_save
        sta     nombre
        lda     #>n_save
        sta     nombre+1
        jsr     dir_buscar
        bcc     @hay_save
        lda     fat_error
        beq     :+
        jmp     @err
:       jsr     crear_save              ; no está: se crea (vacía, así que la partida tampoco está)
        bcs     :+
        lda     #0
        sta     pt_col
:       rts
@hay_save:
        ldy     #11
        lda     (dir_ent),y
        and     #$10
        beq     @sin_save
        jsr     ent_clus
        copia4  pt_dclus, clus
        jsr     dir_abrir
@sig:   jsr     dir_siguiente
        bcs     @fin_dir
        ldy     #11
        lda     (dir_ent),y
        and     #$18                    ; carpetas y etiqueta: no
        bne     @sig
        jsr     igual_corto
        bne     @largo
        lda     pt_lfn
        beq     @hallada                ; sin nombre largo: el 8.3 decide
        lda     #1                      ; con nombre largo: el 8.3 inventado está ocupado (salvo que sea ella)
        sta     pt_col
@largo: lda     pt_lfn
        beq     @sig
        lda     lfn_val
        beq     @sig
        jsr     igual_largo
        bne     @sig
@hallada:
        lda     #1
        sta     pt_hallada
        lda     #0
        sta     pt_col
        copia4  pt_lba, dir_lba
        lda     dir_idx
        sta     pt_idx
        jsr     ent_clus
        copia4  pt_clus, clus
        ldy     #28
        ldx     #0
@t:     lda     (dir_ent),y
        sta     pt_tam,x
        iny
        inx
        cpx     #4
        bne     @t
        clc
        rts
@fin_dir:
        lda     fat_error
        bne     @err
        clc
        rts
@sin_save:
        lda     fat_error
        bne     @err
        lda     #L_SINSAVE
        sec
        rts
@err:   sta     pt_err
        lda     #L_SD
        sec
        rts

; Crea la carpeta EDFC/SAVE (pt_eclus = clúster de EDFC): un clúster a cero con «.» y «..», fin de cadena en la
; FAT y su entrada en EDFC, en ese orden. Deja pt_dclus. Acarreo = 1: error (A = L_*).
crear_save:
        copia4  clus, pt_eclus
        jsr     dir_abrir_c
        lda     #1
        sta     hc_n
        jsr     dir_huecos
        bcc     :+
        jmp     err_escr
:       lda     #1
        sta     lib_k
        jsr     fat_libres
        bcc     :+
        jmp     err_escr
:       ldx     #0                      ; el clúster nuevo: «.» y «..» en el primer sector, el resto a cero
        txa
@z:     sta     sector,x
        sta     sector+256,x
        inx
        bne     @z
        copia4  clus, lib_ini
        lda     #<n_punto
        ldx     #>n_punto
        jsr     ent_carpeta
        ldx     #31
@p1:    lda     pt_ent,x
        sta     sector,x
        dex
        bpl     @p1
        copia4  clus, pt_eclus          ; «..» = EDFC (no es la raíz)
        lda     #<n_puntos
        ldx     #>n_puntos
        jsr     ent_carpeta
        ldx     #31
@p2:    lda     pt_ent,x
        sta     sector+32,x
        dex
        bpl     @p2
        copia4  clus, lib_ini
        jsr     clus_a_lba
        copia4  sd_lba, dir_lba
        lda     fat_spc
        sta     pt_sect
@s:     jsr     grabar_sector
        bcc     :+
        jmp     err_escr
:       jsr     inc_lba
        ldx     #63                     ; los demás sectores, a cero
        lda     #0
@zz:    sta     sector,x
        dex
        bpl     @zz
        dec     pt_sect
        bne     @s
        copia4  clus, lib_ini
        jsr     fat_fin_cadena
        bcc     :+
        jmp     err_escr
:       jsr     fat_grabar
        bcc     :+
        jmp     err_escr
:       copia4  clus, lib_ini
        jsr     inc_clus4
        jsr     fat_info_pista
        bcc     :+
        jmp     err_escr
:       copia4  sd_lba, hc_lba          ; la entrada «SAVE» en EDFC
        jsr     leer_sector
        bcc     :+
        jmp     err_escr
:       copia4  clus, lib_ini
        lda     #<n_save
        ldx     #>n_save
        jsr     ent_carpeta
        lda     hc_idx
        jsr     ent_ptr
        ldy     #31
@e:     lda     pt_ent,y
        sta     (pp),y
        dey
        bpl     @e
        copia4  sd_lba, hc_lba
        jsr     grabar_sector
        bcc     :+
        jmp     err_escr
:       copia4  pt_dclus, lib_ini
        clc
        rts

inc_clus4:
        inc     clus
        bne     @ya
        inc     clus+1
        bne     @ya
        inc     clus+2
        bne     @ya
        inc     clus+3
@ya:    rts

; pt_ent = entrada de una carpeta con el nombre 8.3 de A (bajo) / X (alto) y el clúster `clus`.
ent_carpeta:
        sta     qq
        stx     qq+1
        ldy     #31
        lda     #0
@z:     sta     pt_ent,y
        dey
        bpl     @z
        ldy     #10
@n:     lda     (qq),y
        sta     pt_ent,y
        dey
        bpl     @n
        lda     #$10
        sta     pt_ent+11
        lda     #<FECHA
        sta     pt_ent+16
        sta     pt_ent+18
        sta     pt_ent+24
        lda     #>FECHA
        sta     pt_ent+17
        sta     pt_ent+19
        sta     pt_ent+25
        lda     clus+2
        sta     pt_ent+20
        lda     clus+3
        sta     pt_ent+21
        lda     clus
        sta     pt_ent+26
        lda     clus+1
        sta     pt_ent+27
        rts

; Z = 1 si la entrada dir_ent tiene el nombre 8.3 pt_corto.
igual_corto:
        ldy     #10
@c:     lda     (dir_ent),y
        cmp     pt_corto,y
        bne     @no
        dey
        bpl     @c
        lda     #0
@no:    rts

; Z = 1 si el nombre largo recién leído (lfn_crudo) es pt_nom, sin distinguir mayúsculas de ASCII.
igual_largo:
        lda     lfn_crudo_n             ; caracteres guardados: trozos x 13 (como mucho 260)
        cmp     #21
        bcs     @no                     ; más largo de lo que puede ser
        jsr     cap13
        lda     pt_cap+1                ; si pt_len > tope, el nombre de la entrada es más corto
        bne     :+
        lda     pt_cap
        cmp     pt_len
        bcc     @no
:       lda     #<lfn_crudo
        sta     pp
        lda     #>lfn_crudo
        sta     pp+1
        lda     #<pt_nom
        sta     qq
        lda     #>pt_nom
        sta     qq+1
        ldx     #0
@c:     ldy     #1
        lda     (qq),y
        cmp     (pp),y
        bne     @no
        dey
        lda     (pp),y
        jsr     minus
        sta     pt_ck
        lda     (qq),y
        jsr     minus
        cmp     pt_ck
        bne     @no
        jsr     avanza_pq
        inx
        cpx     pt_len
        bne     @c
        ; después tiene que acabar: $0000, $FFFF o el final del último trozo
        lda     pt_cap+1
        bne     :+
        lda     pt_cap
        cmp     pt_len
        beq     @si
:       ldy     #0
        lda     (pp),y
        iny
        ora     (pp),y
        beq     @si
        lda     (pp),y
        dey
        and     (pp),y
        cmp     #$FF
        beq     @si
@no:    lda     #1
        rts
@si:    lda     #0
        rts

; A = carácter bajo (alto 0, ya comprobado igual): mayúscula ASCII -> minúscula. Si el alto no es 0 da igual: los
; dos se comparan sin plegar porque solo se pliega $41-$5A.
minus:  cmp     #'A'
        bcc     @ya
        cmp     #'Z' + 1
        bcs     @ya
        ora     #$20
@ya:    rts

; pt_cap = lfn_crudo_n x 13 (16 bits).
cap13:  lda     #0
        sta     pt_cap
        sta     pt_cap+1
        ldx     lfn_crudo_n
        beq     @ya
@m:     clc
        lda     pt_cap
        adc     #13
        sta     pt_cap
        bcc     :+
        inc     pt_cap+1
:       dex
        bne     @m
@ya:    rts

; ------------------------------------------------------------------------------------------------ crear
; Crea la partida (pt_sect_nueva sectores, llenos de $FF) en EDFC/SAVE. Acarreo = 1: error (A = L_*).
crear:
        lda     #1                      ; entradas: 8.3 y, si hay nombre largo, un trozo por cada 13 caracteres
        sta     pt_n
        lda     pt_lfn
        beq     @huecos
        lda     pt_len
        ldx     #0
@d13:   inx
        sec
        sbc     #13
        beq     @ent
        bcs     @d13
@ent:   inx
        stx     pt_n
@huecos:
        copia4  clus, pt_dclus
        jsr     dir_abrir_c
        lda     pt_n
        sta     hc_n
        jsr     dir_huecos
        bcc     :+
        jmp     err_escr
:       ; clústeres = (sectores + spc - 1) >> desp
        lda     pt_sect_nueva
        clc
        adc     fat_spc
        sec
        sbc     #1
        ldx     fat_desp
        beq     @k
@dk:    lsr
        dex
        bne     @dk
@k:     cmp     #0                      ; con más sectores que 255 por clúster no pasa: spc <= 128
        bne     :+
        lda     #1
:       sta     lib_k
        sta     pt_i
        jsr     fat_libres
        bcc     :+
        jmp     err_escr
:       ; datos: $FF en los sectores del archivo (el tramo es contiguo)
        ldx     #0
        lda     #$FF
@ff:    sta     sector,x
        sta     sector+256,x
        inx
        bne     @ff
        copia4  clus, lib_ini
        jsr     clus_a_lba
        copia4  sd_lba, dir_lba
        lda     pt_sect_nueva
        sta     pt_sect
@dat:   jsr     grabar_sector
        bcc     :+
        jmp     err_escr
:       jsr     inc_lba
        dec     pt_sect
        bne     @dat
        ; cadena en la FAT
        copia4  clus, lib_ini
@cad:   dec     pt_i
        beq     @ultimo
        ldx     #3
@v:     lda     clus,x
        sta     fat_v,x
        dex
        bpl     @v
        inc     fat_v
        bne     :+
        inc     fat_v+1
        bne     :+
        inc     fat_v+2
        bne     :+
        inc     fat_v+3
:       jsr     fat_poner
        bcc     :+
        jmp     err_escr
:       copia4  clus, fat_v
        jmp     @cad
@ultimo:
        jsr     fat_fin_cadena
        bcc     :+
        jmp     err_escr
:       jsr     fat_grabar
        bcc     :+
        jmp     err_escr
:       inc     clus                    ; pista de la FSInfo: el siguiente
        bne     :+
        inc     clus+1
        bne     :+
        inc     clus+2
        bne     :+
        inc     clus+3
:       jsr     fat_info_pista
        bcc     :+
        jmp     err_escr
:       ; entradas de la carpeta, por orden: los trozos del nombre largo (del último al primero) y la 8.3
        copia4  pt_clus, lib_ini
        lda     pt_sect_nueva           ; tamaño = sectores x 512
        asl
        sta     pt_tam+1
        lda     #0
        rol
        sta     pt_tam+2
        lda     #0
        sta     pt_tam
        sta     pt_tam+3
        sta     pt_cur_ok
        sta     pt_i
@entrada:
        jsr     montar_ent
        lda     pt_i                    ; hc_lba[pt_i]: ¿es el sector que ya está en `sector`?
        asl
        asl
        tax
        lda     pt_cur_ok
        beq     @leer
        ldy     #0
@cmp:   lda     hc_lba,x
        cmp     pt_cur,y
        bne     @otro
        inx
        iny
        cpy     #4
        bne     @cmp
        beq     @poner
@otro:  copia4  sd_lba, pt_cur          ; graba el anterior
        jsr     grabar_sector
        bcs     err_escr
@leer:  lda     pt_i
        asl
        asl
        tax
        ldy     #0
@l:     lda     hc_lba,x
        sta     pt_cur,y
        sta     sd_lba,y
        inx
        iny
        cpy     #4
        bne     @l
        jsr     leer_sector
        bcs     err_escr
        lda     #1
        sta     pt_cur_ok
@poner: ldx     pt_i
        lda     hc_idx,x
        jsr     ent_ptr
        ldy     #31
@p:     lda     pt_ent,y
        sta     (pp),y
        dey
        bpl     @p
        inc     pt_i
        lda     pt_i
        cmp     pt_n
        bne     @entrada
        copia4  sd_lba, pt_cur
        jsr     grabar_sector
        bcs     err_escr
        ldx     pt_n                    ; la 8.3 es la última
        dex
        lda     hc_idx,x
        sta     pt_idx
        txa
        asl
        asl
        tax
        ldy     #0
@u:     lda     hc_lba,x
        sta     pt_lba,y
        inx
        iny
        cpy     #4
        bne     @u
        clc
        rts

err_escr:
        lda     fat_error
        sta     pt_err
        cmp     #E_LLENA_FAT
        bne     :+
        lda     #L_LLENA
        sec
        rts
:       lda     #L_ESCRIBIR
        sec
        rts

inc_lba:
        inc     sd_lba
        bne     @ya
        inc     sd_lba+1
        bne     @ya
        inc     sd_lba+2
        bne     @ya
        inc     sd_lba+3
@ya:    rts

; pp = sector + 32 x A (A = 0-15).
ent_ptr:
        pha
        lsr
        lsr
        lsr
        clc
        adc     #>sector
        sta     pp+1
        pla
        and     #7
        asl
        asl
        asl
        asl
        asl
        clc
        adc     #<sector
        sta     pp
        bcc     :+
        inc     pp+1
:       rts

; pt_ent = entrada número pt_i de las pt_n de la partida.
montar_ent:
        ldx     pt_n
        dex
        cpx     pt_i
        bne     @trozo
        ; 8.3: nombre, archivo, minúsculas, fechas fijas (no hay reloj), clúster y tamaño
        ldy     #31
        lda     #0
@z:     sta     pt_ent,y
        dey
        bpl     @z
        ldy     #10
@n:     lda     pt_corto,y
        sta     pt_ent,y
        dey
        bpl     @n
        lda     #$20
        sta     pt_ent+11
        lda     pt_caso
        sta     pt_ent+12
        lda     #<FECHA
        sta     pt_ent+16
        sta     pt_ent+18
        sta     pt_ent+24
        lda     #>FECHA
        sta     pt_ent+17
        sta     pt_ent+19
        sta     pt_ent+25
        lda     pt_clus+2
        sta     pt_ent+20
        lda     pt_clus+3
        sta     pt_ent+21
        lda     pt_clus
        sta     pt_ent+26
        lda     pt_clus+1
        sta     pt_ent+27
        ldx     #3
@t:     lda     pt_tam,x
        sta     pt_ent+28,x
        dex
        bpl     @t
        rts
        ; trozo del nombre largo: orden = pt_n - 1 - pt_i (el primero lleva $40)
@trozo: txa
        sec
        sbc     pt_i
        sta     pt_ent
        sta     pt_sect                 ; orden (1-20)
        lda     pt_i
        bne     :+
        lda     pt_ent
        ora     #$40
        sta     pt_ent
:       lda     #$0F
        sta     pt_ent+11
        lda     #0
        sta     pt_ent+12
        sta     pt_ent+26
        sta     pt_ent+27
        jsr     suma_corto
        sta     pt_ent+13
        ldx     pt_sect                 ; primer carácter: (orden - 1) x 13
        dex
        lda     #0
@x13:   cpx     #0
        beq     @c0
        clc
        adc     #13
        dex
        jmp     @x13
@c0:    sta     pt_ck                   ; índice del carácter
        lda     #0
        sta     pt_fuera
        ldx     #0
@car:   ldy     lfn_offs,x
        lda     pt_fuera                ; pasado el carácter 255: relleno
        bne     @relleno
        lda     pt_ck
        cmp     pt_len
        bcc     @letra
        beq     @cero
@relleno:
        lda     #$FF
        sta     pt_ent,y
        sta     pt_ent+1,y
        bne     @sig
@cero:  lda     #0
        sta     pt_ent,y
        sta     pt_ent+1,y
        beq     @sig
@letra: asl
        sta     qq
        lda     #0
        rol
        sta     qq+1
        clc
        lda     qq
        adc     #<pt_nom
        sta     qq
        lda     qq+1
        adc     #>pt_nom
        sta     qq+1
        sty     pt_cur_tmp
        ldy     #0
        lda     (qq),y
        pha
        iny
        lda     (qq),y
        ldy     pt_cur_tmp
        sta     pt_ent+1,y
        pla
        sta     pt_ent,y
@sig:   inc     pt_ck
        bne     :+
        inc     pt_fuera
:       inx
        cpx     #13
        bne     @car
        rts

; A = suma de comprobación del nombre 8.3 pt_corto (la de los trozos del nombre largo).
suma_corto:
        lda     #0
        ldy     #0
@c:     lsr
        bcc     :+
        ora     #$80
:       clc
        adc     pt_corto,y
        iny
        cpy     #11
        bne     @c
        rts

; ------------------------------------------------------------------------------------------------ preparar
; Busca la partida (o la crea) y la copia a la PRG-RAM desde 0x00000. Acarreo = 1: no se puede (A = L_*).
partida_preparar:
        lda     #8
        sta     pt_intentos
@busca: jsr     buscar
        bcc     :+
        rts
:       lda     pt_hallada
        bne     @cargar
        lda     pt_col                  ; el 8.3 inventado está cogido: otro resumen
        beq     @nueva
        dec     pt_intentos
        beq     @nueva                  ; (no debería pasar)
        inc     pt_hash
        jsr     corto_hash
        jmp     @busca
@nueva: jsr     crear
        bcc     :+
        rts
:       lda     pt_sect_nueva           ; la RAM, llena de $FF
        sta     pt_sect
        lda     #0
        sta     pt_i
@ff:    jsr     ventana
        ldy     #0
        lda     #$FF
@f:     sta     (sd_ptr),y
        iny
        bne     @f
        inc     sd_ptr+1
@f2:    sta     (sd_ptr),y
        iny
        bne     @f2
        inc     pt_i
        lda     pt_i
        cmp     pt_sect
        bne     @ff
        clc
        rts

@cargar:
        jsr     abrir_partida
        bcc     :+
        rts
:       lda     #0
        sta     pt_i
@lee:   jsr     ventana
        copia4  sd_lba, arch_lba
        jsr     sd_leer_sector
        bcs     @err_sd
        inc     pt_i
        lda     pt_i
        cmp     pt_sect
        beq     @resto
        jsr     arch_avanzar
        bcc     @lee
        lda     fat_error
        jmp     @err
@resto: lda     pt_sect                 ; si mide menos de 8 KiB, el resto de los 8 KiB a $FF
        cmp     #16
        bcs     @hecho
        jsr     ventana
        ldy     #0
        lda     #$FF
@r:     sta     (sd_ptr),y
        iny
        bne     @r
        inc     sd_ptr+1
@r2:    sta     (sd_ptr),y
        iny
        bne     @r2
        inc     pt_i
        lda     pt_i
        cmp     #16
        bne     @resto
@hecho: clc
        rts
@err_sd:
        lda     sd_error
@err:   sta     pt_err
        sta     fat_error
        lda     #L_SD
        sec
        rts

; Banco de la PRG-RAM y sd_ptr para el sector pt_i del archivo (16 por banco de 8 KiB).
ventana:
        lda     #REG_RAM
        sta     REG_SEL
        lda     pt_i
        lsr
        lsr
        lsr
        lsr
        sta     REG_DAT
        lda     #0                      ; el dato SPI vuelve a estar en $4401
        sta     REG_SEL
        lda     pt_i
        and     #$0F
        asl
        clc
        adc     #>VENT
        sta     sd_ptr+1
        lda     #<VENT
        sta     sd_ptr
        rts

; Lee la entrada de la partida (pt_lba, pt_idx), comprueba que sigue siendo el archivo pt_clus de pt_tam bytes y lo
; abre: pt_sect = sectores que se copian (hasta 64 KiB). Acarreo = 1: A = L_SD (no se lee) o L_PERDIDA (no es ella).
abrir_partida:
        copia4  sd_lba, pt_lba
        jsr     leer_sector
        bcc     :+
        lda     fat_error
        sta     pt_err
        lda     #L_SD
        rts
:       lda     pt_idx
        jsr     ent_ptr
        lda     pp
        sta     dir_ent
        lda     pp+1
        sta     dir_ent+1
        ldy     #0
        lda     (dir_ent),y
        beq     @no
        cmp     #$E5
        beq     @no
        ldy     #11
        lda     (dir_ent),y
        and     #$18
        bne     @no
        jsr     ent_clus
        ldx     #3
@c:     lda     clus,x
        cmp     pt_clus,x
        bne     @no
        dex
        bpl     @c
        ldy     #31
        ldx     #3
@t:     lda     (dir_ent),y
        cmp     pt_tam,x
        bne     @no
        dey
        dex
        bpl     @t
        lda     pt_tam                  ; sectores = tamaño / 512 redondeando hacia arriba, entre 1 y 128
        ora     pt_tam+1
        ora     pt_tam+2
        ora     pt_tam+3
        beq     @no                     ; vacía: no tiene clústeres donde escribir
        lda     pt_tam+3
        ora     pt_tam+2
        bne     @max
        lda     pt_tam+1
        lsr
        sta     pt_sect
        lda     pt_tam+1
        and     #1
        ora     pt_tam
        beq     :+
        inc     pt_sect
:       lda     pt_sect
        cmp     #MAX_SECT + 1
        bcc     @abre
@max:   lda     #MAX_SECT
        sta     pt_sect
@abre:  jsr     arch_abrir
        clc
        rts
@no:    lda     #L_PERDIDA
        sec
        rts

; ------------------------------------------------------------------------------------------------ marca
; Deja en el banco 8 la marca de «partida pendiente» con la posición del archivo.
partida_marcar:
        lda     #'N'
        sta     pt_marca
        lda     #'8'
        sta     pt_marca+1
        lda     #'S'
        sta     pt_marca+2
        lda     #'V'
        sta     pt_marca+3
        lda     #1
        sta     pt_marca+4
        ldx     #3
@c:     lda     pt_lba,x
        sta     pt_marca+5,x
        lda     pt_clus,x
        sta     pt_marca+10,x
        lda     pt_tam,x
        sta     pt_marca+14,x
        dex
        bpl     @c
        lda     pt_idx
        sta     pt_marca+9
        jsr     suma_marca
        sta     pt_marca+18
        jsr     banco_marca
        ldx     #MARCA_TAM - 1
@m:     lda     pt_marca,x
        sta     VENT,x
        dex
        bpl     @m
        rts

banco_marca:
        lda     #REG_RAM
        sta     REG_SEL
        lda     #BANCO_MARCA
        sta     REG_DAT
        lda     #0
        sta     REG_SEL
        rts

; A = suma de los 18 primeros bytes de pt_marca, más $A5.
suma_marca:
        lda     #$A5
        ldx     #MARCA_TAM - 2
        clc
@s:     adc     pt_marca,x
        dex
        bpl     @s
        rts

; Si hay una partida pendiente, la vuelca de la PRG-RAM a su archivo y borra la marca. Devuelve:
;   acarreo = 0, A = 0              no había nada
;   acarreo = 0, A = M_GUARDADA     guardada
;   acarreo = 0, A = M_PERDIDA      la marca no coincide con ningún archivo: se borra sin escribir
;   acarreo = 1, A = M_NOGUARDADA   error de la tarjeta (pt_err): la marca se queda para otro intento
partida_pendiente:
        jsr     partida_hay_marca
        bcs     @vale
        lda     #0
        rts
@vale:  ldx     #3
@c:     lda     pt_marca+5,x
        sta     pt_lba,x
        lda     pt_marca+10,x
        sta     pt_clus,x
        lda     pt_marca+14,x
        sta     pt_tam,x
        dex
        bpl     @c
        lda     pt_marca+9
        and     #$0F
        sta     pt_idx
        jsr     abrir_partida
        bcc     @escribe
        cmp     #L_PERDIDA
        bne     @mal
        jsr     borrar_marca
        lda     #M_PERDIDA
        clc
        rts
@escribe:
        lda     #0
        sta     pt_i
@e:     jsr     ventana
        copia4  sd_lba, arch_lba
        jsr     sd_escribir_sector
        bcs     @err_sd
        inc     pt_i
        lda     pt_i
        cmp     pt_sect
        beq     @hecho
        jsr     arch_avanzar
        bcc     @e
        lda     fat_error
        sta     pt_err
        jmp     @mal
@err_sd:
        lda     sd_error
        sta     pt_err
@mal:   lda     #M_NOGUARDADA
        sec
        rts
@hecho: jsr     borrar_marca
        lda     #M_GUARDADA
        clc
        rts

; Lee la marca del banco 8 en pt_marca. Acarreo = 1 si es válida (hay una partida pendiente en la PRG-RAM).
partida_hay_marca:
        jsr     banco_marca
        ldx     #MARCA_TAM - 1
@l:     lda     VENT,x
        sta     pt_marca,x
        dex
        bpl     @l
        ldx     #4
@f:     lda     pt_marca,x
        cmp     firma_marca,x
        bne     @no
        dex
        bpl     @f
        jsr     suma_marca
        cmp     pt_marca+18
        bne     @no
        sec
        rts
@no:    clc
        rts

borrar_marca:
        jsr     banco_marca
        lda     #0
        ldx     #MARCA_TAM - 1
@b:     sta     VENT,x
        dex
        bpl     @b
        rts

        .segment "RODATA"
FECHA = ((2026 - 1980) << 9) | (1 << 5) | 1    ; 1-1-2026: no hay reloj
firma_marca: .byte "N8SV", 1
ext_srm:    .byte ".srm"
n_edfc:     .byte "EDFC       "
n_save:     .byte "SAVE       "
n_punto:    .byte ".          "
n_puntos:   .byte "..         "
lfn_offs:   .byte   1, 3, 5, 7, 9, 14, 16, 18, 20, 22, 24, 28, 30
        .segment "GRANDE"
pt_cur_tmp: .res 1
pt_fuera:   .res 1
pt_cap:     .res 2
