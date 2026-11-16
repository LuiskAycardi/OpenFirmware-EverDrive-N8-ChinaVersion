; fat.s — FAT16 y FAT32 de solo lectura para el OS del N8 clon. GPL-3.0-or-later, código propio.
;
;   fat_montar        lee el sector 0 (MBR o sector de arranque sin particiones) y la BPB
;   dir_abrir_raiz    prepara el recorrido del directorio raíz
;   dir_siguiente     siguiente entrada de verdad (salta nombres largos, borrados y la etiqueta): deja dir_ent
;                     apuntando a sus 32 bytes; acarreo = 1 cuando no hay más (o hubo error: fat_error)
; Límites de esta etapa: sectores de 512 bytes; FAT12 no; se decide FAT16/FAT32 por «sectores por FAT de 16 bits»
; distinto de cero (lo normal en tarjetas SD).

        .setcpu "6502"
        .include "os.inc"

        .export fat_montar, dir_abrir_raiz, dir_siguiente
        .export fat_error, fat_tipo, fat_spc, fat_part, fat_datos, sector
        .exportzp dir_ent
        .import sd_leer_sector
        .importzp sd_lba, sd_ptr

E_FIRMA = 6                     ; el sector 0 no acaba en 55 AA
E_BPB   = 7                     ; sector de arranque no válido (o sectores que no son de 512 bytes)
E_SPC   = 8                     ; sectores por clúster no es potencia de 2
        .export E_FIRMA, E_BPB, E_SPC

        .segment "ZEROPAGE"
dir_ent:    .res 2              ; entrada actual (dentro de `sector`)
clus:       .res 4              ; clúster de trabajo
t32:        .res 4

        .segment "BSS"
sector:     .res 512            ; el único búfer de sector
fat_error:  .res 1              ; 0 = bien; E_* de aquí o de sd.s
fat_tipo:   .res 1              ; 16 o 32
fat_spc:    .res 1              ; sectores por clúster
fat_desp:   .res 1              ; log2(fat_spc)
fat_part:   .res 4              ; primer sector de la partición
fat_ini:    .res 4              ; primer sector de la FAT
fat_datos:  .res 4              ; primer sector de la zona de datos (clúster 2)
fat_raiz:   .res 4              ; FAT32: clúster de la raíz; FAT16: primer sector de la raíz
fat_raiz_n: .res 2              ; FAT16: sectores de la raíz
dir_lba:    .res 4              ; sector actual del directorio
dir_clus:   .res 4              ; clúster actual (0 = raíz fija de FAT16)
dir_quedan: .res 2              ; sectores que quedan en el tramo, contando el actual
dir_idx:    .res 1              ; entrada dentro del sector (0-15)
dir_estado: .res 1              ; 0 = hay que leer el sector; 1 = sector leído; 2 = hay que avanzar antes

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
        lda     #0
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
@tam:   copia32 fat_datos, fat_ini      ; saltar las FAT (normalmente 2)
        ldx     sector+16
@fats:  suma32  fat_datos, t32
        dex
        bne     @fats

        lda     fat_tipo
        cmp     #32
        bne     @f16
        copia32 fat_raiz, sector+44     ; FAT32: la raíz es una cadena de clústeres
        clc
        rts
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
        clc
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
; Usa `sector`.
clus_siguiente:
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
        jsr     @leer_fat
        bcs     @fin
        lda     clus
        asl
        tay
        bcs     @alta16
        lda     sector,y
        sta     clus
        lda     sector+1,y
        jmp     @v16
@alta16:
        lda     sector+256,y
        sta     clus
        lda     sector+257,y
@v16:   sta     clus+1
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

        ; FAT32: sector = fat_ini + clus/128; posición = (clus mod 128) x 4
@f32:   copia32 t32, clus
        ldx     #7
@d7:    lsr     t32+3
        ror     t32+2
        ror     t32+1
        ror     t32
        dex
        bne     @d7
        jsr     @leer_fat
        bcs     @fin
        lda     clus
        and     #$7F
        asl
        asl
        tay
        bcs     @alta32
        lda     sector,y
        sta     clus
        lda     sector+1,y
        sta     clus+1
        lda     sector+2,y
        sta     clus+2
        lda     sector+3,y
        jmp     @v32
@alta32:
        lda     sector+256,y
        sta     clus
        lda     sector+257,y
        sta     clus+1
        lda     sector+258,y
        sta     clus+2
        lda     sector+259,y
@v32:   and     #$0F
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

@leer_fat:
        copia32 sd_lba, fat_ini
        suma32  sd_lba, t32
        jsr     leer
        bcc     @bien
        lda     sd_error
        sta     fat_error
        sec
@bien:  rts

; ---------------------------------------------------------------------------------------------- directorios
dir_abrir_raiz:
        lda     #0
        sta     dir_estado
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
        bne     @mirar
        copia32 sd_lba, dir_lba
        jsr     leer
        bcc     @leido
        lda     sd_error
        sta     fat_error
@fin:   sec
        rts
@leido: lda     #<sector
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
        beq     @otra                   ; borrada
        ldy     #11
        lda     (dir_ent),y
        and     #$3F
        cmp     #$0F
        beq     @otra                   ; trozo de nombre largo
        and     #$08
        bne     @otra                   ; etiqueta del volumen
        clc
        rts
