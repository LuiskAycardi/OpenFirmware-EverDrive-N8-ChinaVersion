; orden.s — orden alfabético de la carpeta del menú. GPL-3.0-or-later, código propio.
;
; Al recorrer una carpeta (principal.s: escanear), cada entrada listada k (0, 1, 2… en el orden de la FAT) deja su
; clave de 32 bytes en la PRG-RAM de las partidas, bancos 0-7 por la ventana $6000: 256 claves por banco, 2048 como
; mucho. Esa RAM está libre en el menú: la partida del último juego ya se guardó al arrancar (partida_pendiente) y
; al lanzar otro juego su partida se vuelve a cargar desde la SD. Si queda una partida sin guardar, la RAM no se
; toca y la carpeta sale en el orden de la FAT; también si tiene más de ORD_MAX entradas.
;
; Clave: byte 0 = 0 para las carpetas y 1 para los archivos (carpetas primero); bytes 1-31 = el nombre que se ve,
; con las minúsculas en mayúsculas, los acentos sin acento y la ñ entre la n y la o; relleno a cero (los nombres
; cortos van antes: «Final Fantasy» < «Final Fantasy II»). Si dos claves son iguales manda el orden de la FAT.
;
; Además, antes de leer cada entrada se guarda la posición del recorrido (12 bytes de fat.s: dir_guardar) en los
; bancos 9-11 (682 por banco): así cada fila de una página ordenada se lee directamente, con una o dos lecturas de
; la SD, sin volver a recorrer la página de 16 en el orden de la FAT. Por eso el máximo es 3 x 682 = 2046.
;
; El orden queda en ord_idx (2 bytes por entrada, en la imagen del OS): ord_idx[i] = k de la entrada que va en el
; puesto i. Se ordena con heapsort (sin memoria extra, n log n comparaciones).
;
;   orden_ini       antes de recorrer: decide si se puede ordenar (ord_on)
;   orden_clave     guarda la clave de la entrada k (ord_k) con el nombre de (ord_src) y A = 0 carpeta / 1 archivo
;   orden_fin       con n entradas (ord_n): ordena (ord_ok = 1) o deja el orden de la FAT
;   orden_k         A:X = puesto i -> k (A bajo, X alto); si no está ordenada, k = i
;   orden_pos_ptr   dir_pos = dónde guardar la posición del recorrido antes de la entrada ord_k (bancos 9-11)
;   orden_pos_traer dir_pos = esa posición, copiada a la RAM (para dir_restaurar y leer la entrada k directamente)
;   orden_puesto    A:X = k -> su puesto i (la inversa de orden_k; sin orden, i = k)
;   orden_letra     A = primera letra de la clave del puesto i (A:X), para saltar de letra en letra

        .setcpu "6502"
        .include "os.inc"

        .export orden_ini, orden_clave, orden_fin, orden_k, orden_letra, ord_on, ord_ok
        .export orden_pos_ptr, orden_pos_traer, orden_puesto
        .importzp dir_pos
        .exportzp ord_src, ord_k, ord_n
        .import partida_hay_marca

REG_RAM = 129
VENT    = $6000
ORD_MAX = 2046                  ; claves: 8 bancos de 256; posiciones: 3 bancos de 682
POS_BANCO = 9
POS_N   = 682                   ; posiciones de 12 bytes por banco de 8 KiB
CLAVE   = 32

        .segment "ZEROPAGE"
ord_src:    .res 2              ; nombre (códigos de la fuente, terminado en 0)
ord_k:      .res 2
ord_n:      .res 2
op:         .res 2              ; puntero a una clave en la ventana
oi:         .res 2              ; puntero a ord_idx[...]
h_raiz:     .res 2
h_hijo:     .res 2
h_fin:      .res 2              ; tamaño del montículo
h_a:        .res 2              ; k de las dos entradas que se comparan
h_b:        .res 2

        .segment "TRABAJO"
ord_idx:    .res 2 * ORD_MAX

        .segment "GRANDE"
ord_on:     .res 1              ; 1 = se están guardando claves
ord_ok:     .res 1              ; 1 = la carpeta actual está ordenada
clave_a:    .res CLAVE
pos_buf:    .res 12

        .segment "CODE"

orden_ini:
        lda     #0
        sta     ord_ok
        sta     ord_on
        jsr     partida_hay_marca       ; acarreo = 1: hay una partida sin guardar en la RAM
        bcs     @no
        inc     ord_on
@no:    rts

; op = clave de la entrada ord_k en la ventana (y el banco puesto). Acarreo = 1 si k >= 2048 (8 bancos).
clave_ptr:
        lda     ord_k+1
        cmp     #8
        bcs     @fuera
        jsr     banco_k                 ; A = banco
        lda     ord_k
        and     #7
        asl
        asl
        asl
        asl
        asl
        sta     op
        lda     ord_k
        lsr
        lsr
        lsr
        clc
        adc     #>VENT
        sta     op+1
        clc
@fuera: rts

; Pone en la ventana el banco de la clave ord_k (k / 256: 0-7).
banco_k:
        lda     #REG_RAM
        sta     REG_SEL
        lda     ord_k+1
        sta     REG_DAT
        lda     #0
        sta     REG_SEL
        rts

; Guarda la clave de la entrada ord_k: A = 0 carpeta / 1 archivo, nombre en (ord_src).
orden_clave:
        ldx     ord_on
        beq     @fin
        pha
        jsr     clave_ptr
        pla
        bcs     @fin
        ldy     #0
        sta     (op),y
@c:     lda     (ord_src),y
        beq     @cero
        jsr     plegar
        iny
        sta     (op),y
        cpy     #CLAVE - 1
        bne     @c
        rts
@cero:  iny
@z:     sta     (op),y                  ; A = 0
        iny
        cpy     #CLAVE
        bne     @z
@fin:   rts

; Carácter de la fuente -> carácter de la clave. No toca X ni Y.
plegar: cmp     #'a'
        bcc     @mayus
        cmp     #'z' + 1
        bcs     @mayus
        and     #$DF                    ; a-z -> A-Z
@mayus: cmp     #C_a                    ; $80-$8F: acentos (tabla)
        bcc     @asc
        cmp     #C_EXC + 1
        bcs     @ya
        sty     op_y
        tay
        lda     sin_acento - C_a,y
        ldy     op_y
        cmp     #'N' + $80              ; marca de la ñ
        beq     @enie
@asc:   cmp     #'O'                    ; O-Z (y [\]^_`) un puesto más arriba: la ñ va entre N y O
        bcc     @ya
        cmp     #'`' + 1
        bcs     @ya
        clc
        adc     #1
@ya:    rts
@enie:  lda     #'O'
        rts

; Ordena las ord_n entradas si se guardaron todas sus claves. Si no, ord_ok = 0 (orden de la FAT).
orden_fin:
        lda     #0
        sta     ord_ok
        lda     ord_on
        beq     @fin
        lda     ord_n                   ; ord_n <= ORD_MAX
        cmp     #<(ORD_MAX + 1)
        lda     ord_n+1
        sbc     #>(ORD_MAX + 1)
        bcs     @fin
        lda     ord_n                   ; vacía: nada que ordenar
        ora     ord_n+1
        beq     @fin
        ; ord_idx[i] = i
        lda     #<ord_idx
        sta     oi
        lda     #>ord_idx
        sta     oi+1
        lda     #0
        sta     h_a
        sta     h_a+1
@ini:   ldy     #0
        lda     h_a
        sta     (oi),y
        iny
        lda     h_a+1
        sta     (oi),y
        jsr     oi_mas
        inc     h_a
        bne     :+
        inc     h_a+1
:       lda     h_a
        cmp     ord_n
        bne     @ini
        lda     h_a+1
        cmp     ord_n+1
        bne     @ini
        jsr     heapsort
        lda     #1
        sta     ord_ok
@fin:   rts

oi_mas: clc
        lda     oi
        adc     #2
        sta     oi
        bcc     :+
        inc     oi+1
:       rts

; ------------------------------------------------------------------------------------------------ heapsort
heapsort:
        lda     ord_n
        sta     h_fin
        lda     ord_n+1
        sta     h_fin+1
        ; montículo: raíz desde n/2 - 1 hasta 0
        lda     ord_n+1
        lsr
        sta     h_hijo+1
        lda     ord_n
        ror
        sta     h_hijo                  ; h_hijo = n / 2 (se usa como contador)
@monta: lda     h_hijo
        ora     h_hijo+1
        beq     @saca
        lda     h_hijo
        bne     :+
        dec     h_hijo+1
:       dec     h_hijo
        lda     h_hijo
        sta     h_raiz
        lda     h_hijo+1
        sta     h_raiz+1
        lda     h_hijo                  ; hundir() usa h_hijo: se guarda en la pila
        pha
        lda     h_hijo+1
        pha
        jsr     hundir
        pla
        sta     h_hijo+1
        pla
        sta     h_hijo
        jmp     @monta
        ; sacar: el mayor (puesto 0) al final, y hundir la raíz en el resto
@saca:  lda     h_fin
        sec
        sbc     #1
        sta     h_fin
        lda     h_fin+1
        sbc     #0
        sta     h_fin+1
        ora     h_fin
        beq     @hecho                  ; queda uno
        lda     #0
        sta     h_raiz
        sta     h_raiz+1
        lda     h_fin
        sta     h_hijo
        lda     h_fin+1
        sta     h_hijo+1
        jsr     cambiar                 ; ord_idx[0] <-> ord_idx[fin]
        lda     #0
        sta     h_raiz
        sta     h_raiz+1
        jsr     hundir                  ; con h_fin elementos
        jmp     @saca
@hecho: rts

; Hunde ord_idx[h_raiz] en el montículo de h_fin elementos.
hundir:
@b:     lda     h_raiz                  ; hijo = 2 x raíz + 1
        asl
        sta     h_hijo
        lda     h_raiz+1
        rol
        sta     h_hijo+1
        inc     h_hijo
        bne     :+
        inc     h_hijo+1
:       lda     h_hijo                  ; ¿hijo >= fin?
        cmp     h_fin
        lda     h_hijo+1
        sbc     h_fin+1
        bcs     @fin
        ; si hijo + 1 < fin y clave(hijo + 1) > clave(hijo): hijo + 1
        lda     h_hijo
        clc
        adc     #1
        tax
        lda     h_hijo+1
        adc     #0
        tay
        txa
        cmp     h_fin
        tya
        sbc     h_fin+1
        bcs     @uno
        lda     h_hijo
        ldx     h_hijo+1
        jsr     leer_idx
        sta     h_b
        stx     h_b+1
        txa
        pha
        lda     h_hijo
        clc
        adc     #1
        pha
        lda     h_hijo+1
        adc     #0
        tax
        pla
        jsr     leer_idx
        sta     h_a
        stx     h_a+1
        pla
        jsr     mayor                   ; ¿clave(h_a) > clave(h_b)?
        bcc     @uno
        inc     h_hijo
        bne     @uno
        inc     h_hijo+1
@uno:   ; si clave(hijo) > clave(raíz): cambiar y seguir
        lda     h_hijo
        ldx     h_hijo+1
        jsr     leer_idx
        sta     h_a
        stx     h_a+1
        lda     h_raiz
        ldx     h_raiz+1
        jsr     leer_idx
        sta     h_b
        stx     h_b+1
        jsr     mayor
        bcc     @fin
        jsr     cambiar
        lda     h_hijo
        sta     h_raiz
        lda     h_hijo+1
        sta     h_raiz+1
        jmp     @b
@fin:   rts

; oi = &ord_idx[A:X]
oi_de:  sta     oi
        stx     oi+1
        asl     oi
        rol     oi+1
        clc
        lda     oi
        adc     #<ord_idx
        sta     oi
        lda     oi+1
        adc     #>ord_idx
        sta     oi+1
        rts

; A:X = ord_idx[A:X]
leer_idx:
        jsr     oi_de
        ldy     #1
        lda     (oi),y
        tax
        dey
        lda     (oi),y
        rts

; ord_idx[h_raiz] <-> ord_idx[h_hijo]
cambiar:
        lda     h_raiz
        ldx     h_raiz+1
        jsr     leer_idx
        sta     h_a
        stx     h_a+1
        lda     h_hijo
        ldx     h_hijo+1
        jsr     leer_idx
        sta     h_b
        stx     h_b+1
        lda     h_raiz                  ; ord_idx[raíz] = b
        ldx     h_raiz+1
        jsr     oi_de
        ldy     #0
        lda     h_b
        sta     (oi),y
        iny
        lda     h_b+1
        sta     (oi),y
        lda     h_hijo                  ; ord_idx[hijo] = a
        ldx     h_hijo+1
        jsr     oi_de
        ldy     #0
        lda     h_a
        sta     (oi),y
        iny
        lda     h_a+1
        sta     (oi),y
        rts

; Acarreo = 1 si clave(h_a) > clave(h_b) (con claves iguales, si h_a > h_b: orden de la FAT).
mayor:  lda     h_a                     ; clave de a -> clave_a
        sta     ord_k
        lda     h_a+1
        sta     ord_k+1
        jsr     clave_ptr
        ldy     #CLAVE - 1
@c:     lda     (op),y
        sta     clave_a,y
        dey
        bpl     @c
        lda     h_b
        sta     ord_k
        lda     h_b+1
        sta     ord_k+1
        jsr     clave_ptr
        ldy     #0
@m:     lda     clave_a,y
        cmp     (op),y
        bne     @dif
        iny
        cpy     #CLAVE
        bne     @m
        lda     h_b                     ; iguales: por k
        cmp     h_a
        lda     h_b+1
        sbc     h_a+1                   ; acarreo = 0 si b < a, es decir a > b
        bcc     @si
        clc
        rts
@si:    sec
        rts
@dif:   beq     @no                     ; (no pasa)
        bcs     @si2                    ; clave_a > clave_b
@no:    clc
        rts
@si2:   sec
        rts

; ------------------------------------------------------------------------------------------------ posiciones
; dir_pos = posición de la entrada ord_k en la ventana (banco 9 + k / 682, k mod 682 x 12). Acarreo = 1 si no se
; guardan (no se ordena o k >= ORD_MAX).
orden_pos_ptr:
        lda     ord_on
        beq     @no
        lda     ord_k
        cmp     #<ORD_MAX
        lda     ord_k+1
        sbc     #>ORD_MAX
        bcs     @no
        lda     ord_k                   ; h_a = k mod 682, X = k / 682
        sta     h_a
        lda     ord_k+1
        sta     h_a+1
        ldx     #0
@div:   lda     h_a
        cmp     #<POS_N
        lda     h_a+1
        sbc     #>POS_N
        bcc     @r
        lda     h_a
        sbc     #<POS_N                 ; acarreo = 1
        sta     h_a
        lda     h_a+1
        sbc     #>POS_N
        sta     h_a+1
        inx
        bne     @div
@r:     lda     #REG_RAM
        sta     REG_SEL
        txa
        clc
        adc     #POS_BANCO
        sta     REG_DAT
        lda     #0
        sta     REG_SEL
        lda     h_a                     ; x 12 = x 8 + x 4
        asl
        sta     dir_pos
        lda     h_a+1
        rol
        sta     dir_pos+1
        asl     dir_pos
        rol     dir_pos+1               ; x 4
        lda     dir_pos
        sta     op
        lda     dir_pos+1
        sta     op+1
        asl     dir_pos
        rol     dir_pos+1               ; x 8
        clc
        lda     dir_pos
        adc     op
        sta     dir_pos
        lda     dir_pos+1
        adc     op+1
        adc     #>VENT
        sta     dir_pos+1
        clc
        rts
@no:    sec
        rts

; dir_pos = pos_buf con la posición guardada de la entrada ord_k. Acarreo = 1 si no hay (solo con ord_ok).
orden_pos_traer:
        lda     ord_ok
        beq     @no
        jsr     orden_pos_ptr
        bcs     @no
        ldy     #11
@c:     lda     (dir_pos),y
        sta     pos_buf,y
        dey
        bpl     @c
        lda     #<pos_buf
        sta     dir_pos
        lda     #>pos_buf
        sta     dir_pos+1
        clc
        rts
@no:    sec
        rts

; ------------------------------------------------------------------------------------------------ consultas
; A:X (puesto i) -> A:X (k). Sin orden, k = i.
orden_k:
        ldy     ord_ok
        beq     @igual
        jmp     leer_idx
@igual: rts

; A:X (k) -> A:X (puesto i con ord_idx[i] = k). Sin orden, o si no está, i = k.
orden_puesto:
        sta     h_a
        stx     h_a+1
        lda     ord_ok
        beq     @igual
        lda     #<ord_idx
        sta     oi
        lda     #>ord_idx
        sta     oi+1
        lda     #0
        sta     h_b
        sta     h_b+1
@b:     lda     h_b                     ; ¿i = n?
        cmp     ord_n
        bne     :+
        lda     h_b+1
        cmp     ord_n+1
        beq     @igual
:       ldy     #0
        lda     (oi),y
        cmp     h_a
        bne     @sig
        iny
        lda     (oi),y
        cmp     h_a+1
        bne     @sig
        lda     h_b
        ldx     h_b+1
        rts
@sig:   jsr     oi_mas
        inc     h_b
        bne     @b
        inc     h_b+1
        bne     @b
@igual: lda     h_a
        ldx     h_a+1
        rts

; A = primera letra de la clave del puesto A:X (con el tipo delante: carpetas < archivos). Solo con ord_ok.
orden_letra:
        jsr     orden_k
        sta     ord_k
        stx     ord_k+1
        jsr     clave_ptr
        ldy     #0
        lda     (op),y                  ; 0 carpeta / 1 archivo
        asl
        asl
        asl
        asl
        asl
        asl
        asl
        sta     op_y
        iny
        lda     (op),y
        ora     op_y                    ; bit 7 = archivo
        rts

        .segment "RODATA"
; $80-$8F de la fuente (os.inc): á é í ó ú ñ ü Á É Í Ó Ú Ñ Ü ¿ ¡ (la ñ lleva la marca N + $80)
sin_acento: .byte "AEIOU", 'N' + $80, "UAEIOU", 'N' + $80, "U", $8E, $8F

        .segment "GRANDE"
op_y:       .res 1
