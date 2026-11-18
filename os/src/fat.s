; fat.s — FAT16 y FAT32 para el OS del N8 clon. GPL-3.0-or-later, código propio. Lee todo; escribe solo lo que
; hace falta para crear las partidas (partida.s): entradas de la FAT (las dos copias), la FSInfo y huecos nuevos en
; una carpeta. Nunca borra ni cambia de tamaño un archivo.
;
;   fat_montar        lee el sector 0 (MBR o sector de arranque sin particiones) y la BPB
;   dir_abrir_raiz    prepara el recorrido del directorio raíz
;   dir_abrir         lo mismo para la carpeta de la entrada dir_ent
;   dir_buscar        busca en el directorio abierto el nombre 8.3 de 11 bytes que apunta `nombre`
;   arch_abrir        prepara la lectura del archivo de la entrada dir_ent (deja arch_tam, arch_lba)
;   arch_leer         lee el sector actual del archivo en `sector`
;   arch_avanzar      pasa al sector siguiente (puede usar `sector` para mirar la FAT)
;   arch_contiguo     acarreo = 0 si los clústeres del archivo abierto van seguidos en la tarjeta
;   tramo_ini/_sig    recorre el archivo abierto por tramos de clústeres seguidos (para lecturas múltiples)
;   dir_siguiente     siguiente entrada de verdad (salta nombres largos, borrados y la etiqueta): deja dir_ent
;                     apuntando a sus 32 bytes; acarreo = 1 cuando no hay más (o hubo error: fat_error). Por el
;                     camino junta el nombre largo (LFN): si es válido para la entrada (suma de comprobación del
;                     nombre 8.3), lfn_val = 1 y lfn_buf tiene sus primeros 64 caracteres ya en códigos de la fuente
;                     (terminado en 0 si es más corto)
;   dir_abrir_c       abre la carpeta del clúster `clus` (0 = la raíz)
;   dir_guardar       guarda en (dir_pos) 12 bytes con la posición del recorrido (después de la última entrada)
;   dir_restaurar     vuelve a esa posición: el siguiente dir_siguiente sigue desde ahí
;   (escritura)
;   fat_libres        busca lib_k clústeres libres seguidos (desde la pista de la FSInfo): lib_ini
;   fat_poner         FAT[clus] = fat_v en el búfer de la FAT (se graba al cambiar de sector o con fat_grabar)
;   fat_grabar        graba el sector de la FAT modificado en todas las copias
;   fat_info_pista    FSInfo: libres = desconocido y siguiente libre = clus
;   dir_huecos        busca hc_n entradas libres seguidas en la carpeta abierta (la amplía con un clúster si hace
;                     falta): sus posiciones en hc_lba/hc_idx
;   leer_sector / grabar_sector   sector sd_lba <-> `sector`
; Además, dir_siguiente guarda el nombre largo en bruto (UCS-2) en lfn_crudo: lfn_crudo_n trozos de 13 caracteres.
; Límites de esta etapa: sectores de 512 bytes; FAT12 no; se decide FAT16/FAT32 por «sectores por FAT de 16 bits»
; distinto de cero (lo normal en tarjetas SD).

        .setcpu "6502"
        .include "os.inc"

        .export fat_montar, dir_abrir_raiz, dir_abrir, dir_siguiente, dir_buscar
        .export arch_abrir, arch_leer, arch_avanzar, arch_contiguo
        .export fat_error, fat_tipo, fat_spc, fat_part, fat_datos, sector
        .export arch_lba, arch_tam, arch_clus, arch_ini
        .export tramo_ini, tramo_sig, tr_lba, tr_n, tr_fin, fat_desp
        .export dir_abrir_c, dir_guardar, dir_restaurar, ent_clus, lfn_buf, lfn_val
        .export fat_libres, fat_poner, fat_grabar, fat_info_pista, dir_huecos, leer_sector, grabar_sector
        .export lib_k, lib_ini, fat_v, hc_n, hc_lba, hc_idx, lfn_crudo, lfn_crudo_n
        .export dir_lba, dir_idx, dir_clus, clus_a_lba
        .exportzp dir_ent, nombre, clus, dir_pos
        .import sd_leer_sector, sd_escribir_sector
        .importzp sd_lba, sd_ptr

E_FIRMA = 6                     ; el sector 0 no acaba en 55 AA
E_BPB   = 7                     ; sector de arranque no válido (o sectores que no son de 512 bytes)
E_SPC   = 8                     ; sectores por clúster no es potencia de 2
E_FIN   = 9                     ; el archivo se acaba antes de lo que dice su tamaño
E_LLENA = 13                    ; no quedan clústeres libres (o la carpeta no se puede ampliar)
        .export E_FIRMA, E_BPB, E_SPC, E_FIN, E_LLENA

        .segment "ZEROPAGE"
dir_ent:    .res 2              ; entrada actual (dentro de `sector`)
nombre:     .res 2              ; nombre 8.3 (11 bytes) que busca dir_buscar
clus:       .res 4              ; clúster de trabajo
dir_pos:    .res 2              ; dir_guardar / dir_restaurar: dónde van los 12 bytes
t32:        .res 4
t32b:       .res 4
fat_p:      .res 2              ; entrada de la FAT dentro de fat_buf (fat_ent_ptr)

        .segment "BSS"
sector:     .res 512            ; búfer de sector (directorios, cabeceras)
fat_buf:    .res 512            ; un sector de la FAT, con caché
fat_buf_lba: .res 4             ; qué sector de la tarjeta hay en fat_buf ($FFFFFFFF = ninguno)
tr_lba:     .res 4              ; tramo_sig: primer sector del tramo
tr_n:       .res 2              ; tramo_sig: clústeres seguidos del tramo
tr_fin:     .res 1              ; tramo_sig: 1 = era el último tramo del archivo
fat_error:  .res 1              ; 0 = bien; E_* de aquí o de sd.s
fat_tipo:   .res 1              ; 16 o 32
fat_spc:    .res 1              ; sectores por clúster
fat_desp:   .res 1              ; log2(fat_spc)
fat_part:   .res 4              ; primer sector de la partición
fat_ini:    .res 4              ; primer sector de la FAT
fat_datos:  .res 4              ; primer sector de la zona de datos (clúster 2)
fat_raiz:   .res 4              ; FAT32: clúster de la raíz; FAT16: primer sector de la raíz
fat_raiz_n: .res 2              ; FAT16: sectores de la raíz
fat_n:      .res 1              ; copias de la FAT
fat_sz:     .res 4              ; sectores de cada FAT
fat_max:    .res 4              ; último clúster válido
fat_info:   .res 4              ; sector de la FSInfo (FAT32); 0 = no hay
fat_sucio:  .res 1              ; 1 = fat_buf tiene cambios sin grabar
fat_pide:   .res 4
fat_k:      .res 1
fat_v:      .res 4              ; fat_poner: valor
lib_k:      .res 1              ; fat_libres: clústeres que hacen falta (1-255)
lib_n:      .res 1
lib_ini:    .res 4              ; fat_libres: el primero del tramo libre
lib_0:      .res 4              ; donde empezó la búsqueda
lib_vuelta: .res 1
hc_n:       .res 1              ; dir_huecos: entradas que hacen falta (1-21)
hc_k:       .res 1
hc_fin:     .res 1
hc_i:       .res 1
; dir_lba ... dir_estado: 12 bytes seguidos (dir_guardar los copia tal cual)
dir_lba:    .res 4              ; sector actual del directorio
dir_clus:   .res 4              ; clúster actual (0 = raíz fija de FAT16)
dir_quedan: .res 2              ; sectores que quedan en el tramo, contando el actual
dir_idx:    .res 1              ; entrada dentro del sector (0-15)
dir_estado: .res 1              ; 0 = hay que leer el sector; 1 = sector leído; 2 = hay que avanzar antes;
                                ; 3 = hay que leer el sector, apuntar a dir_idx y avanzar (tras dir_restaurar)
LFN_MAX = 64
lfn_buf:    .res LFN_MAX        ; nombre largo en códigos de la fuente
lfn_ok:     .res 1              ; 1 = se está juntando un nombre largo
lfn_ck:     .res 1              ; su suma de comprobación
lfn_val:    .res 1              ; 1 = la entrada devuelta tiene nombre largo válido
lfn_t:      .res 1
lfn_j:      .res 1
lfn_lo:     .res 1

        .segment "GRANDE"
LFN_TROZOS = 20                 ; 20 x 13 = 260 caracteres: cabe cualquier nombre largo (255)
lfn_crudo:  .res LFN_TROZOS * 26
lfn_crudo_n: .res 1             ; trozos del último nombre largo empezado
HC_MAX = 21
hc_lba:     .res 4 * HC_MAX
hc_idx:     .res HC_MAX
        .segment "BSS"
arch_lba:   .res 4              ; sector actual del archivo abierto
arch_clus:  .res 4              ; su clúster
arch_quedan: .res 1             ; sectores que quedan en el clúster, contando el actual
arch_tam:   .res 4              ; tamaño en bytes
arch_ini:   .res 4              ; primer clúster

        .segment "CODE"

; ---------------------------------------------------------------------------------------------- utilidades
; Lee el sector sd_lba en `sector`. Acarreo = 1 si falla.
leer:   lda     #<sector
        sta     sd_ptr
        lda     #>sector
        sta     sd_ptr+1
        jmp     sd_leer_sector

.macro copia32 destino, origen
        lda     origen
        sta     destino
        lda     origen+1
        sta     destino+1
        lda     origen+2
        sta     destino+2
        lda     origen+3
        sta     destino+3
.endmacro

.macro suma32 destino, origen       ; destino += origen
        clc
        lda     destino
        adc     origen
        sta     destino
        lda     destino+1
        adc     origen+1
        sta     destino+1
        lda     destino+2
        adc     origen+2
        sta     destino+2
        lda     destino+3
        adc     origen+3
        sta     destino+3
.endmacro

; ---------------------------------------------------------------------------------------------- montar
fat_montar:
        lda     #$FF                    ; caché de la FAT vacía
        sta     fat_buf_lba+3
        lda     #0
        sta     fat_sucio
        sta     fat_info
        sta     fat_info+1
        sta     fat_info+2
        sta     fat_info+3
        sta     fat_error
        sta     sd_lba
        sta     sd_lba+1
        sta     sd_lba+2
        sta     sd_lba+3
        sta     fat_part
        sta     fat_part+1
        sta     fat_part+2
        sta     fat_part+3
        jsr     leer
        bcc     @s0
        jmp     error_sd
@s0:    jsr     firma
        beq     @firmado
        lda     #E_FIRMA
        jmp     error
@firmado:
        jsr     es_bpb                  ; ¿tarjeta sin particiones?
        beq     @bpb
        copia32 fat_part, sector+$1BE+8 ; primera partición del MBR
        copia32 sd_lba, fat_part
        jsr     leer
        bcc     @s1
        jmp     error_sd
@s1:    jsr     firma
        bne     @mal
        jsr     es_bpb
        beq     @bpb
@mal:   lda     #E_BPB
        jmp     error

@bpb:   lda     sector+13               ; sectores por clúster: potencia de 2
        sta     fat_spc
        ldx     #0
@pot:   lsr
        bcs     @uno
        inx
        cpx     #8
        bne     @pot
@nopot: lda     #E_SPC
        jmp     error
@uno:   bne     @nopot                  ; quedaban más bits a 1
        stx     fat_desp

        ; fat_ini = partición + sectores reservados
        lda     sector+14
        sta     t32
        lda     sector+15
        sta     t32+1
        lda     #0
        sta     t32+2
        sta     t32+3
        copia32 fat_ini, fat_part
        suma32  fat_ini, t32

        ; sectores por FAT: de 16 bits (FAT16) o de 32 (FAT32)
        lda     #16
        sta     fat_tipo
        lda     sector+22
        sta     t32
        lda     sector+23
        sta     t32+1
        ora     t32
        bne     @tam
        lda     #32
        sta     fat_tipo
        copia32 t32, sector+36
@tam:   copia32 fat_sz, t32
        lda     sector+16
        sta     fat_n
        copia32 fat_datos, fat_ini      ; saltar las FAT (normalmente 2)
        ldx     sector+16
@fats:  suma32  fat_datos, t32
        dex
        bne     @fats

        lda     fat_tipo
        cmp     #32
        bne     @f16
        copia32 fat_raiz, sector+44     ; FAT32: la raíz es una cadena de clústeres
        lda     sector+48               ; FSInfo (sector relativo; 0 o $FFFF = no hay)
        ora     sector+49
        beq     @sin_info
        lda     sector+48
        and     sector+49
        cmp     #$FF
        bne     @info
@sin_info:
        jmp     @geom
@info:  lda     sector+48
        sta     t32
        lda     sector+49
        sta     t32+1
        lda     #0
        sta     t32+2
        sta     t32+3
        copia32 fat_info, fat_part
        suma32  fat_info, t32
        jmp     @geom
@f16:   copia32 fat_raiz, fat_datos     ; FAT16: raíz fija entre las FAT y los datos
        clc                             ; sectores = (entradas + 15) / 16
        lda     sector+17
        adc     #15
        sta     fat_raiz_n
        lda     sector+18
        adc     #0
        sta     fat_raiz_n+1
        ldx     #4
@div:   lsr     fat_raiz_n+1
        ror     fat_raiz_n
        dex
        bne     @div
        lda     fat_raiz_n
        sta     t32
        lda     fat_raiz_n+1
        sta     t32+1
        lda     #0
        sta     t32+2
        sta     t32+3
        suma32  fat_datos, t32
        ; clústeres = (sectores de la partición - (fat_datos - fat_part)) >> desp; fat_max = clústeres + 1
@geom:  lda     sector+19
        sta     t32b
        lda     sector+20
        sta     t32b+1
        ora     t32b
        beq     @tot32
        lda     #0
        sta     t32b+2
        sta     t32b+3
        beq     @resta
@tot32: copia32 t32b, sector+32
@resta: sec
        ldx     #0
        ldy     #4
@r:     lda     fat_datos,x
        sbc     fat_part,x
        sta     t32,x
        inx
        dey
        bne     @r
        sec
        ldx     #0
        ldy     #4
@r2:    lda     t32b,x
        sbc     t32,x
        sta     fat_max,x
        inx
        dey
        bne     @r2
        ldx     fat_desp
        beq     @mas1
@d:     lsr     fat_max+3
        ror     fat_max+2
        ror     fat_max+1
        ror     fat_max
        dex
        bne     @d
@mas1:  inc     fat_max
        bne     @ya
        inc     fat_max+1
        bne     @ya
        inc     fat_max+2
        bne     @ya
        inc     fat_max+3
@ya:    clc
        rts

error_sd:
        .import sd_error
        lda     sd_error
error:  sta     fat_error
        sec
        rts

; Z = 1 si `sector` acaba en 55 AA.
firma:  lda     sector+510
        cmp     #$55
        bne     @no
        lda     sector+511
        cmp     #$AA
@no:    rts

; Z = 1 si `sector` parece un sector de arranque FAT: salto al principio y 512 bytes por sector.
es_bpb: lda     sector
        cmp     #$EB
        beq     @salto
        cmp     #$E9
        bne     @no
@salto: lda     sector+11
        bne     @no
        lda     sector+12
        cmp     #$02
@no:    rts

; ---------------------------------------------------------------------------------------------- clústeres
; dir_lba = primer sector del clúster `clus`; dir_quedan = sectores por clúster.
clus_a_lba:
        sec
        lda     clus
        sbc     #2
        sta     dir_lba
        lda     clus+1
        sbc     #0
        sta     dir_lba+1
        lda     clus+2
        sbc     #0
        sta     dir_lba+2
        lda     clus+3
        sbc     #0
        sta     dir_lba+3
        ldx     fat_desp
        beq     @ya
@d:     asl     dir_lba
        rol     dir_lba+1
        rol     dir_lba+2
        rol     dir_lba+3
        dex
        bne     @d
@ya:    suma32  dir_lba, fat_datos
        lda     fat_spc
        sta     dir_quedan
        lda     #0
        sta     dir_quedan+1
        rts

; clus = clúster siguiente a `clus` según la FAT. Acarreo = 1 si era el último (o error de lectura: fat_error).
; Lee la FAT en su propio búfer (fat_buf), con caché de un sector: no toca `sector`.
clus_siguiente:
        jsr     fat_ent_ptr
        bcc     :+
        rts
:
        ldy     #0
        lda     (fat_p),y
        sta     clus
        iny
        lda     (fat_p),y
        sta     clus+1
        lda     fat_tipo
        cmp     #32
        beq     @f32
        lda     #0
        sta     clus+2
        sta     clus+3
        lda     clus+1
        cmp     #$FF                    ; >= $FFF8: fin de la cadena
        bne     @sigue
        lda     clus
        cmp     #$F8
        bcs     @ultimo
@sigue: clc
@fin:   rts
@ultimo:
        sec
        rts
@f32:   iny
        lda     (fat_p),y
        sta     clus+2
        iny
        lda     (fat_p),y
        and     #$0F
        sta     clus+3
        cmp     #$0F                    ; >= $0FFFFFF8: fin de la cadena
        bne     @sigue
        lda     clus+2
        and     clus+1
        cmp     #$FF
        bne     @sigue
        lda     clus
        cmp     #$F8
        bcs     @ultimo
        bcc     @sigue

; fat_p = dirección en fat_buf de la entrada del clúster `clus` (lee su sector de la FAT, con caché). Acarreo = 1 si
; falla (fat_error).
fat_ent_ptr:
        lda     fat_tipo
        cmp     #32
        beq     @f32
        ; FAT16: sector = fat_ini + clus/256; posición = (clus mod 256) x 2
        lda     clus+1
        sta     t32
        lda     #0
        sta     t32+1
        sta     t32+2
        sta     t32+3
        jsr     leer_fat
        bcc     :+
        rts
:
        lda     clus
        asl
        jmp     @ptr
        ; FAT32: sector = fat_ini + clus/128; posición = (clus mod 128) x 4
@f32:   copia32 t32, clus
        ldx     #7
@d7:    lsr     t32+3
        ror     t32+2
        ror     t32+1
        ror     t32
        dex
        bne     @d7
        jsr     leer_fat
        bcc     :+
        rts
:
        lda     clus
        and     #$7F
        asl
        asl
@ptr:   sta     fat_p                   ; acarreo = la mitad alta del sector
        lda     #>fat_buf
        adc     #0
        sta     fat_p+1
        lda     fat_p
        clc
        adc     #<fat_buf
        sta     fat_p
        bcc     :+
        inc     fat_p+1
:       clc
@fin:   rts

; fat_buf = sector fat_ini + t32 de la FAT (si no está ya). Si el que había tiene cambios, primero lo graba.
leer_fat:
        copia32 sd_lba, fat_ini
        suma32  sd_lba, t32
        ldx     #3                      ; ¿es el que ya está en fat_buf?
@cache: lda     sd_lba,x
        cmp     fat_buf_lba,x
        bne     @otro
        dex
        bpl     @cache
        clc
        rts
@otro:  lda     fat_sucio
        beq     @lee
        copia32 fat_pide, sd_lba        ; el que se pide
        jsr     fat_grabar
        bcs     @mal
        copia32 sd_lba, fat_pide
@lee:   lda     #<fat_buf
        sta     sd_ptr
        lda     #>fat_buf
        sta     sd_ptr+1
        jsr     sd_leer_sector
        bcc     @bien
        lda     sd_error
        sta     fat_error
@mal:   lda     #$FF                    ; búfer a medias: sin caché
        sta     fat_buf_lba+3
        sec
        rts
@bien:  copia32 fat_buf_lba, sd_lba
        rts

; ---------------------------------------------------------------------------------------------- escritura
; Graba fat_buf (si tiene cambios) en su sector y en el mismo sector de las demás copias de la FAT. Acarreo = 1 si
; falla (fat_error). Cambia sd_lba.
fat_grabar:
        lda     fat_sucio
        bne     @si
        clc
        rts
@si:    copia32 sd_lba, fat_buf_lba
        lda     fat_n
        sta     fat_k
@copia: lda     #<fat_buf
        sta     sd_ptr
        lda     #>fat_buf
        sta     sd_ptr+1
        jsr     sd_escribir_sector
        bcs     @mal
        dec     fat_k
        beq     @hecho
        suma32  sd_lba, fat_sz
        jmp     @copia
@hecho: lda     #0
        sta     fat_sucio
        clc
        rts
@mal:   lda     sd_error
        sta     fat_error
        sec
        rts

; FAT[clus] = fat_v, en fat_buf (FAT32: se conservan los 4 bits altos de la entrada). Acarreo = 1 si falla.
fat_poner:
        jsr     fat_ent_ptr
        bcc     :+
        rts
:
        ldy     #0
        lda     fat_v
        sta     (fat_p),y
        iny
        lda     fat_v+1
        sta     (fat_p),y
        lda     fat_tipo
        cmp     #32
        bne     @ya
        iny
        lda     fat_v+2
        sta     (fat_p),y
        iny
        lda     (fat_p),y
        and     #$F0
        sta     t32
        lda     fat_v+3
        and     #$0F
        ora     t32
        sta     (fat_p),y
@ya:    lda     #1
        sta     fat_sucio
        clc
@fin:   rts

; Acarreo = 1 si clus > fat_max.
clus_fuera:
        lda     fat_max
        cmp     clus
        lda     fat_max+1
        sbc     clus+1
        lda     fat_max+2
        sbc     clus+2
        lda     fat_max+3
        sbc     clus+3
        bcc     @si                     ; fat_max - clus < 0
        clc
        rts
@si:    sec
        rts

inc_clus:
        inc     clus
        bne     @ya
        inc     clus+1
        bne     @ya
        inc     clus+2
        bne     @ya
        inc     clus+3
@ya:    rts

; Busca lib_k clústeres libres seguidos. Empieza en la pista de la FSInfo (FAT32) o en el 2 y, al llegar al final,
; sigue desde el 2 hasta donde empezó. Acarreo = 0: lib_ini es el primero. Acarreo = 1: no hay (fat_error =
; E_LLENA) o falló una lectura. Usa `sector` (FSInfo) y cambia clus.
fat_libres:
        lda     #2
        sta     lib_0
        lda     #0
        sta     lib_0+1
        sta     lib_0+2
        sta     lib_0+3
        jsr     info_leer
        bcs     @desde
        ldx     #3                      ; pista = siguiente libre (492)
@p:     lda     sector+492,x
        sta     clus,x
        dex
        bpl     @p
        lda     clus+3                  ; entre 2 y fat_max; si no, desde el 2
        ora     clus+2
        ora     clus+1
        bne     @rango
        lda     clus
        cmp     #2
        bcc     @desde
@rango: jsr     clus_fuera
        bcs     @desde
        copia32 lib_0, clus
@desde: copia32 clus, lib_0
        lda     #0
        sta     lib_vuelta
        sta     lib_n
@sig:   jsr     clus_fuera
        bcc     @dentro
        lda     lib_vuelta              ; al final: desde el 2 (una sola vez)
        beq     :+
        jmp     @llena
:       inc     lib_vuelta
        lda     #0
        sta     lib_n
        sta     clus+1
        sta     clus+2
        sta     clus+3
        lda     #2
        sta     clus
@dentro:
        lda     lib_vuelta
        beq     @mirar
        lda     clus                    ; tras la vuelta: parar al llegar a donde se empezó
        cmp     lib_0
        lda     clus+1
        sbc     lib_0+1
        lda     clus+2
        sbc     lib_0+2
        lda     clus+3
        sbc     lib_0+3
        bcs     @llena
@mirar: jsr     fat_ent_ptr
        bcc     :+
        rts
:
        ldy     #0
        lda     (fat_p),y
        iny
        ora     (fat_p),y
        sta     t32
        lda     fat_tipo
        cmp     #32
        bne     @v
        iny
        lda     (fat_p),y
        ora     t32
        sta     t32
        iny
        lda     (fat_p),y
        and     #$0F
        ora     t32
        sta     t32
@v:     lda     t32
        bne     @ocupado
        lda     lib_n
        bne     @mas
        copia32 lib_ini, clus
@mas:   inc     lib_n
        lda     lib_n
        cmp     lib_k
        bne     @avanza
        clc
@fin:   rts
@ocupado:
        lda     #0
        sta     lib_n
@avanza:
        jsr     inc_clus
        jmp     @sig
@llena: lda     #E_LLENA
        sta     fat_error
        sec
        rts

; Lee la FSInfo en `sector` y comprueba sus firmas. Acarreo = 1 si no hay (FAT16), no vale o falla la lectura.
info_leer:
        lda     fat_info
        ora     fat_info+1
        ora     fat_info+2
        ora     fat_info+3
        beq     @no
        copia32 sd_lba, fat_info
        jsr     leer
        bcs     @no
        ldx     #3
@f:     lda     sector,x
        cmp     info_firma1,x
        bne     @no
        lda     sector+484,x
        cmp     info_firma2,x
        bne     @no
        dex
        bpl     @f
        clc
        rts
@no:    sec
        rts

; FSInfo: libres = $FFFFFFFF (desconocido, lo recalcula quien lo necesite) y pista = clus. Si no hay FSInfo, nada.
; Acarreo = 1 si falla la escritura. Usa `sector`.
fat_info_pista:
        jsr     info_leer
        bcc     @hay
        clc
        rts
@hay:   ldx     #3
@c:     lda     #$FF
        sta     sector+488,x
        lda     clus,x
        sta     sector+492,x
        dex
        bpl     @c
        copia32 sd_lba, fat_info
        jmp     grabar_sector

; `sector` -> sector sd_lba. Acarreo = 1 si falla (fat_error).
grabar_sector:
        lda     #<sector
        sta     sd_ptr
        lda     #>sector
        sta     sd_ptr+1
        jsr     sd_escribir_sector
        bcc     @bien
        lda     sd_error
        sta     fat_error
@bien:  rts

; sector sd_lba -> `sector`. Acarreo = 1 si falla (fat_error).
leer_sector:
        jsr     leer
        bcc     @bien
        lda     sd_error
        sta     fat_error
@bien:  rts

; Busca hc_n entradas libres seguidas ($E5, $00 o detrás de un $00) en la carpeta abierta con dir_abrir_c/dir_abrir.
; Deja sus posiciones (sector e índice 0-15) en hc_lba/hc_idx. Si la carpeta se acaba antes, le añade un clúster a
; cero. Acarreo = 1 si falla (fat_error). Usa `sector`.
dir_huecos:
        lda     #0
        sta     hc_k
        sta     hc_fin
@sector:
        copia32 sd_lba, dir_lba
        jsr     leer_sector
        bcc     :+
        rts
:       lda     #<sector
        sta     t32b
        lda     #>sector
        sta     t32b+1
        lda     #0
        sta     hc_i
@ent:   lda     hc_fin
        bne     @libre
        ldy     #0
        lda     (t32b),y
        beq     @cero
        cmp     #$E5
        beq     @libre
        lda     #0                      ; ocupada: el tramo vuelve a empezar
        sta     hc_k
        beq     @otra
@cero:  inc     hc_fin                  ; $00: esta y todas las de detrás están libres
@libre: lda     hc_k
        asl
        asl
        tax
        ldy     #0
@l:     lda     dir_lba,y
        sta     hc_lba,x
        inx
        iny
        cpy     #4
        bne     @l
        ldx     hc_k
        lda     hc_i
        sta     hc_idx,x
        inc     hc_k
        lda     hc_k
        cmp     hc_n
        beq     @hecho
@otra:  clc
        lda     t32b
        adc     #32
        sta     t32b
        bcc     :+
        inc     t32b+1
:       inc     hc_i
        lda     hc_i
        cmp     #16
        bne     @ent
        jsr     dir_sector_sig
        bcs     :+
        jmp     @sector
:       lda     fat_error
        bne     @mal
        jsr     dir_ampliar
        bcs     @mal
        jmp     @sector
@mal:   sec
        rts
@hecho: clc
        rts

; Añade a la carpeta abierta (dir_clus = su último clúster) un clúster nuevo, puesto a cero antes de enlazarlo. Deja
; el recorrido en su primer sector. Acarreo = 1 si falla. Una raíz fija de FAT16 no se puede ampliar (E_LLENA).
dir_ampliar:
        lda     dir_clus
        ora     dir_clus+1
        ora     dir_clus+2
        ora     dir_clus+3
        bne     @cadena
        lda     #E_LLENA
        sta     fat_error
        sec
        rts
@cadena:
        lda     #1
        sta     lib_k
        jsr     fat_libres
        bcc     :+
        rts
:
        ldx     #0                      ; `sector` a cero y a cada sector del clúster nuevo
        txa
@z:     sta     sector,x
        sta     sector+256,x
        inx
        bne     @z
        copia32 clus, lib_ini
        jsr     clus_a_lba
        copia32 sd_lba, dir_lba
@zs:    jsr     grabar_sector
        bcc     :+
        rts
:
        inc     sd_lba
        bne     :+
        inc     sd_lba+1
        bne     :+
        inc     sd_lba+2
        bne     :+
        inc     sd_lba+3
:       dec     dir_quedan
        bne     @zs
        copia32 clus, dir_clus          ; enlazar: último -> nuevo -> fin de cadena
        copia32 fat_v, lib_ini
        jsr     fat_poner
        bcc     :+
        rts
:
        copia32 clus, lib_ini
        jsr     fat_fin_cadena
        bcc     :+
        rts
:
        jsr     fat_grabar
        bcc     :+
        rts
:
        copia32 clus, lib_ini           ; pista: el siguiente al nuevo
        jsr     inc_clus
        jsr     fat_info_pista
        bcc     :+
        rts
:
        copia32 dir_clus, lib_ini
        copia32 clus, lib_ini
        jsr     clus_a_lba
        clc
        rts

; FAT[clus] = fin de cadena.
fat_fin_cadena:
        .export fat_fin_cadena
        lda     #$FF
        sta     fat_v
        sta     fat_v+1
        sta     fat_v+2
        lda     #$0F
        sta     fat_v+3
        jmp     fat_poner

; ---------------------------------------------------------------------------------------------- directorios
dir_abrir_raiz:
        lda     #0
        sta     dir_estado
        sta     lfn_ok
        lda     fat_tipo
        cmp     #32
        beq     @f32
        copia32 dir_lba, fat_raiz
        lda     fat_raiz_n
        sta     dir_quedan
        lda     fat_raiz_n+1
        sta     dir_quedan+1
        lda     #0                      ; sin cadena: tramo fijo
        sta     dir_clus
        sta     dir_clus+1
        sta     dir_clus+2
        sta     dir_clus+3
        rts
@f32:   copia32 dir_clus, fat_raiz
        copia32 clus, fat_raiz
        jmp     clus_a_lba

; Pasa al sector siguiente del directorio. Acarreo = 1 si se acabó.
dir_sector_sig:
        lda     dir_quedan
        bne     @dec
        dec     dir_quedan+1
@dec:   dec     dir_quedan
        lda     dir_quedan
        ora     dir_quedan+1
        beq     @tramo
        inc     dir_lba
        bne     @ok
        inc     dir_lba+1
        bne     @ok
        inc     dir_lba+2
        bne     @ok
        inc     dir_lba+3
@ok:    clc
        rts
@tramo: lda     dir_clus                ; fin del tramo: ¿hay cadena?
        ora     dir_clus+1
        ora     dir_clus+2
        ora     dir_clus+3
        beq     @fin
        copia32 clus, dir_clus
        jsr     clus_siguiente
        bcs     @fin
        copia32 dir_clus, clus
        jsr     clus_a_lba
        clc
        rts
@fin:   sec
        rts

dir_siguiente:
@otra:  lda     dir_estado
        cmp     #2
        bne     @sin_avanzar
        clc                             ; avanzar tras la entrada que se devolvió o se saltó
        lda     dir_ent
        adc     #32
        sta     dir_ent
        bcc     @sin
        inc     dir_ent+1
@sin:   inc     dir_idx
        lda     #1
        sta     dir_estado
        lda     dir_idx
        cmp     #16
        bne     @mirar
        jsr     dir_sector_sig
        bcs     @fin
        lda     #0
        sta     dir_estado
@sin_avanzar:
        lda     dir_estado
        cmp     #1
        beq     @mirar
        copia32 sd_lba, dir_lba
        jsr     leer
        bcc     @leido
        lda     sd_error
        sta     fat_error
@fin:   sec
        rts
@leido: lda     dir_estado
        cmp     #3
        bne     @nuevo
        lda     dir_idx                 ; reanudar: dir_ent = sector + 32 * dir_idx, y avanzar
        lsr
        lsr
        lsr
        clc
        adc     #>sector
        sta     dir_ent+1
        lda     dir_idx
        and     #7
        asl
        asl
        asl
        asl
        asl
        clc
        adc     #<sector
        sta     dir_ent
        bcc     @r
        inc     dir_ent+1
@r:     lda     #2
        sta     dir_estado
        jmp     @otra
@nuevo: lda     #<sector
        sta     dir_ent
        lda     #>sector
        sta     dir_ent+1
        lda     #0
        sta     dir_idx
@mirar: lda     #2
        sta     dir_estado
        ldy     #0
        lda     (dir_ent),y
        beq     @fin                    ; $00: no hay más entradas
        cmp     #$E5
        beq     @borrada
        ldy     #11
        lda     (dir_ent),y
        and     #$3F
        cmp     #$0F
        beq     @largo                  ; trozo de nombre largo
        and     #$08
        bne     @borrada                ; etiqueta del volumen
        jsr     lfn_cierra
        clc
        rts
@borrada:
        lda     #0
        sta     lfn_ok
        jmp     @otra
@largo: jsr     lfn_trozo
        jmp     @otra

; Trozo de nombre largo en dir_ent: 13 caracteres UCS-2 en la posición (orden - 1) * 13. El trozo con el bit $40
; es el último del nombre y el primero que aparece en el directorio: empieza un nombre nuevo.
lfn_trozo:
        ldy     #0
        lda     (dir_ent),y
        and     #$40
        beq     @medio
        ldx     #LFN_MAX
        lda     #0
@borra: sta     lfn_buf-1,x
        dex
        bne     @borra
        lda     #1
        sta     lfn_ok
        ldy     #13
        lda     (dir_ent),y
        sta     lfn_ck
        ldy     #0
        lda     (dir_ent),y
        and     #$1F
        sta     lfn_crudo_n
        jmp     @guarda
@medio: lda     lfn_ok
        beq     @fin
        ldy     #13
        lda     (dir_ent),y
        cmp     lfn_ck
        bne     @mal
@guarda:
        ldy     #0
        lda     (dir_ent),y
        and     #$1F
        beq     @mal
        jsr     lfn_a_crudo
        sec
        sbc     #1
        cmp     #5                      ; más allá de 64 caracteres: no se guarda
        bcs     @fin
        tax
        lda     lfn_pos,x
        tax
        lda     #0
        sta     lfn_j
@c:     ldy     lfn_j
        lda     lfn_offs,y
        tay
        lda     (dir_ent),y
        sta     lfn_lo
        iny
        lda     (dir_ent),y
        jsr     ucs_a_fuente
        cpx     #LFN_MAX
        bcs     @fin
        sta     lfn_buf,x
        inx
        inc     lfn_j
        lda     lfn_j
        cmp     #13
        bne     @c
@fin:   rts
@mal:   lda     #0
        sta     lfn_ok
        rts

; Copia en bruto los 13 caracteres UCS-2 del trozo dir_ent (orden A, 1-31) a lfn_crudo + (A - 1) x 26. Los trozos
; de más de LFN_TROZOS no se guardan. Conserva A; cambia X, Y, lfn_j y t32b.
lfn_a_crudo:
        pha
        cmp     #LFN_TROZOS + 1
        bcs     @no
        tax
        lda     crudo_lo-1,x
        sta     t32b
        lda     crudo_hi-1,x
        sta     t32b+1
        lda     #0
        sta     lfn_j
@c:     ldx     lfn_j
        ldy     lfn_offs,x
        lda     (dir_ent),y
        pha
        iny
        lda     (dir_ent),y
        tax
        lda     lfn_j
        asl
        tay
        pla
        sta     (t32b),y
        iny
        txa
        sta     (t32b),y
        inc     lfn_j
        lda     lfn_j
        cmp     #13
        bne     @c
@no:    pla
        rts

; Carácter UCS-2 (A = byte alto, lfn_lo = bajo) -> código de la fuente. 0 = fin del nombre ($0000 y el relleno
; $FFFF). Lo que la fuente no tiene sale como «?». No toca X.
ucs_a_fuente:
        cmp     #0
        bne     @alto
        lda     lfn_lo
        beq     @ya
        cmp     #$20
        bcc     @raro
        cmp     #$7F
        bcc     @ya
        ldy     #LATIN1_N - 1
@t:     cmp     latin1,y
        beq     @hay
        dey
        bpl     @t
@raro:  lda     #'?'
@ya:    rts
@hay:   lda     latin1_cod,y
        rts
@alto:  cmp     #$FF
        bne     @raro
        lda     lfn_lo
        cmp     #$FF
        bne     @raro
        lda     #0
        rts

; Entrada 8.3 en dir_ent: el nombre largo que se juntaba vale si su suma de comprobación es la de este nombre.
lfn_cierra:
        lda     #0
        sta     lfn_val
        lda     lfn_ok
        beq     @fin
        lda     #0
        sta     lfn_ok
        sta     lfn_t
        ldy     #0
@c:     lda     lfn_t
        lsr
        bcc     @s
        ora     #$80
@s:     clc
        adc     (dir_ent),y
        sta     lfn_t
        iny
        cpy     #11
        bne     @c
        cmp     lfn_ck
        bne     @fin
        lda     lfn_buf
        beq     @fin
        lda     #1
        sta     lfn_val
@fin:   rts

; Guarda la posición del recorrido en (dir_pos): 12 bytes.
dir_guardar:
        ldy     #0
@b:     lda     dir_lba,y
        sta     (dir_pos),y
        iny
        cpy     #12
        bne     @b
        rts

; Vuelve a la posición guardada en (dir_pos).
dir_restaurar:
        ldy     #11
@b:     lda     (dir_pos),y
        sta     dir_lba,y
        dey
        bpl     @b
        lda     #0
        sta     lfn_ok
        lda     dir_estado
        beq     @ya
        lda     #3
        sta     dir_estado
@ya:    rts

; Abre la carpeta del clúster `clus` (0 = la raíz, como en las entradas «..»).
dir_abrir_c:
        lda     clus
        ora     clus+1
        ora     clus+2
        ora     clus+3
        bne     @sub
        jmp     dir_abrir_raiz
@sub:   copia32 dir_clus, clus
        lda     #0
        sta     dir_estado
        sta     lfn_ok
        jmp     clus_a_lba

; Abre la carpeta de la entrada dir_ent.
dir_abrir:
        jsr     ent_clus
        copia32 dir_clus, clus
        lda     #0
        sta     dir_estado
        sta     lfn_ok
        jmp     clus_a_lba

; clus = primer clúster de la entrada dir_ent (en FAT16 la parte alta no se usa).
ent_clus:
        ldy     #26
        lda     (dir_ent),y
        sta     clus
        iny
        lda     (dir_ent),y
        sta     clus+1
        lda     #0
        sta     clus+2
        sta     clus+3
        lda     fat_tipo
        cmp     #32
        bne     @ya
        ldy     #20
        lda     (dir_ent),y
        sta     clus+2
        iny
        lda     (dir_ent),y
        sta     clus+3
@ya:    rts

; Busca `nombre` (11 bytes, 8.3 con espacios) en el directorio abierto. Acarreo = 0: dir_ent es la entrada.
dir_buscar:
@sig:   jsr     dir_siguiente
        bcs     @fin
        ldy     #10
@c:     lda     (dir_ent),y
        cmp     (nombre),y
        bne     @sig
        dey
        bpl     @c
        clc
@fin:   rts

; ---------------------------------------------------------------------------------------------- archivos
; Abre el archivo de la entrada dir_ent.
arch_abrir:
        ldy     #28
        ldx     #0
@t:     lda     (dir_ent),y
        sta     arch_tam,x
        iny
        inx
        cpx     #4
        bne     @t
        jsr     ent_clus
        copia32 arch_ini, clus
; Vuelve al principio del archivo abierto.
arch_reabrir:
        .export arch_reabrir
        copia32 clus, arch_ini
arch_a_clus:
        copia32 arch_clus, clus
        jsr     clus_a_lba              ; deja dir_lba y dir_quedan (no hay un directorio a medias)
        copia32 arch_lba, dir_lba
        lda     fat_spc
        sta     arch_quedan
        rts

; Lee el sector actual del archivo en `sector`. Acarreo = 1 si falla (fat_error).
arch_leer:
        copia32 sd_lba, arch_lba
        jsr     leer
        bcc     @bien
        lda     sd_error
        sta     fat_error
        sec
@bien:  rts

; Pasa al sector siguiente del archivo. Acarreo = 1 si no hay más clústeres o falla la lectura de la FAT.
arch_avanzar:
        dec     arch_quedan
        beq     @clus
        inc     arch_lba
        bne     @ok
        inc     arch_lba+1
        bne     @ok
        inc     arch_lba+2
        bne     @ok
        inc     arch_lba+3
@ok:    clc
        rts
@clus:  copia32 clus, arch_clus
        jsr     clus_siguiente
        bcs     @fin
        jsr     arch_a_clus
        clc
        rts
@fin:   lda     fat_error
        bne     @sal
        lda     #E_FIN
        sta     fat_error
@sal:   sec
        rts

; ¿Van seguidos en la tarjeta todos los clústeres del archivo abierto? Acarreo = 0: sí. Deja el archivo al
; principio. Usa `sector`.
arch_contiguo:
        copia32 clus, arch_ini
@sig:   copia32 t32b, clus
        jsr     clus_siguiente
        bcs     @fin                    ; último clúster: todos seguidos (o error de lectura: fat_error)
        inc     t32b
        bne     @cmp
        inc     t32b+1
        bne     @cmp
        inc     t32b+2
        bne     @cmp
        inc     t32b+3
@cmp:   ldx     #3
@c:     lda     clus,x
        cmp     t32b,x
        bne     @no
        dex
        bpl     @c
        bmi     @sig
@no:    jsr     arch_reabrir
        sec
        rts
@fin:   jsr     arch_reabrir
        lda     fat_error
        cmp     #1                      ; acarreo = 1 si hubo error de lectura
        rts

; ---------------------------------------------------------------------------------------------- tramos
; Prepara el recorrido por tramos del archivo abierto (desde su primer clúster).
tramo_ini:
        copia32 clus, arch_ini
        lda     #0
        sta     tr_fin
        rts

; Siguiente tramo de clústeres seguidos, empezando en `clus`: tr_lba = su primer sector, tr_n = clústeres;
; tr_fin = 1 si después no hay más. Deja `clus` en el primer clúster del tramo siguiente. Acarreo = 1 si falla
; la lectura de la FAT (fat_error). Cambia dir_lba y dir_quedan.
tramo_sig:
        jsr     clus_a_lba
        copia32 tr_lba, dir_lba
        lda     #1
        sta     tr_n
        lda     #0
        sta     tr_n+1
@sig:   copia32 t32b, clus
        jsr     clus_siguiente
        bcs     @ultimo
        inc     t32b                    ; ¿es el siguiente en la tarjeta?
        bne     @c
        inc     t32b+1
        bne     @c
        inc     t32b+2
        bne     @c
        inc     t32b+3
@c:     ldx     #3
@cmp:   lda     clus,x
        cmp     t32b,x
        bne     @corte
        dex
        bpl     @cmp
        inc     tr_n
        bne     @sig
        inc     tr_n+1
        bne     @sig
@corte: clc                             ; `clus` ya es el primero del tramo siguiente
        rts
@ultimo:
        lda     fat_error
        bne     @mal
        lda     #1
        sta     tr_fin
        clc
        rts
@mal:   sec
        rts

        .segment "RODATA"
info_firma1: .byte "RRaA"
info_firma2: .byte "rrAa"
lfn_pos:    .byte   0, 13, 26, 39, 52
crudo_lo:
        .repeat LFN_TROZOS, i
        .byte   <(lfn_crudo + 26 * i)
        .endrepeat
crudo_hi:
        .repeat LFN_TROZOS, i
        .byte   >(lfn_crudo + 26 * i)
        .endrepeat
lfn_offs:   .byte   1, 3, 5, 7, 9, 14, 16, 18, 20, 22, 24, 28, 30
; Latin-1 -> fuente: los caracteres españoles tienen su dibujo; otros acentos se quedan en la letra sin acento.
latin1:     .byte   $E1, $E9, $ED, $F3, $FA, $F1, $FC, $C1, $C9, $CD, $D3, $DA, $D1, $DC, $BF, $A1, $BA, $AA
            .byte   $E0, $E2, $E4, $E5, $E8, $EA, $EB, $EC, $EE, $EF, $F2, $F4, $F6, $F9, $FB, $E7
            .byte   $C0, $C2, $C4, $C5, $C8, $CA, $CB, $CC, $CE, $CF, $D2, $D4, $D6, $D9, $DB, $C7
latin1_cod: .byte   C_a, C_e, C_i, C_o, C_u, C_n, C_ud, C_A, C_E, C_I, C_O, C_U, C_N, C_UD, C_INT, C_EXC, $90, $91
            .byte   "aaaaeeeiiiooouuc"
            .byte   "AAAAEEEIIIOOOUUC"
LATIN1_N = * - latin1_cod
