; principal.s — OS propio del EverDrive N8 clon, etapa 4: carpetas, nombres largos y lanzar un juego.
; GPL-3.0-or-later. La entrada y el tipo de arranque están en arranque.s; la SD en sd.s; la FAT en fat.s; el
; lanzador en lanzar.s.
;
; Con la pantalla apagada: inicializa la tarjeta, monta la FAT y recorre la carpeta actual una vez (cuenta las
; entradas y guarda dónde empieza cada página de 16). Después enciende la pantalla. Arriba y abajo mueven el
; cursor (al pasar del borde se cambia de página), derecha e izquierda cambian de página, A o Start abren la
; entrada (una carpeta se recorre; un juego se lanza) y B vuelve a la carpeta de arriba. Con Select pulsado no se
; hace nada: Select y luego Select+A es el reset del kit Lava. No escribe nunca en la tarjeta.
;
; Los nombres: el largo (LFN) si lo hay, si no el 8.3 (con las minúsculas que marca Windows en el byte 12); sin la
; extensión «.nes»; las carpetas acaban en «/»; si no cabe, «…». No se listan «.», «..», lo oculto ni lo que
; empieza por punto (archivos de macOS como «._juego.nes»).
;
; La ruta (hasta PROF carpetas), la caché de páginas y el texto de la lista viven en el segmento GRANDE, dentro de
; la imagen del OS: llegan a cero al encender y sobreviven a los resets y a la vuelta de un juego, así que al volver
; de un juego el menú abre su carpeta con el cursor sobre él.

        .setcpu "6502"
        .include "os.inc"

        .export principal, nmi
        .import tipo_arranque, arranques, resets, vueltas
        .import sd_iniciar, sd_error, sd_r1, sd_sdhc
        .import fat_montar, dir_abrir_raiz, dir_abrir_c, dir_siguiente, dir_guardar, dir_restaurar, ent_clus
        .import fat_error, fat_tipo, fat_spc, lfn_buf, lfn_val
        .import lanzar, l_error, nombre_rbf, ultimo_juego
        .import partida_pendiente, pt_err
        .importzp l_mapper
        .importzp dir_ent, dir_pos, clus

FILAS   = 16                    ; entradas por página
ANCHO   = 28                    ; columnas de texto (2-29)
MAX_PAG = 255                   ; páginas que se recuerdan: 4080 entradas por carpeta como mucho
PROF    = 8                     ; carpetas de profundidad
NOM     = 20                    ; caracteres del nombre de cada carpeta de la ruta
LFN_MAX = 64                    ; tamaño de lfn_buf (fat.s)

; ------------------------------------------------------------------------------------------------ variables
        .segment "ZEROPAGE"
ptr:        .res 2
botones:    .res 1              ; A en el bit 7 ... Derecha en el bit 0
tmp:        .res 1
tmp2:       .res 1
msk:        .res 1
nmis:       .res 2              ; lo incrementa la NMI: un fotograma = una NMI
mando_on:   .res 1              ; 0 mientras arranca: la NMI no lee el mando (ver nmi)
cuenta:     .res 1
sd_bien:    .res 1              ; 1 = hay carpeta y se puede navegar
sel_ant:    .res 1              ; fila donde está pintado el cursor ($FF = en ninguna)
antes:      .res 1              ; botones del fotograma anterior
nuevos:     .res 1              ; botones recién pulsados
dst:        .res 2              ; texto de la fila que se escribe
src:        .res 2              ; nombre que se copia
entradas:   .res 2              ; entradas de la carpeta
paginas:    .res 1
pagina:     .res 1              ; página a la vista
fila_c:     .res 1              ; fila del cursor (0-15)
filas_pag:  .res 1              ; entradas en la página a la vista
filas_pend: .res 1              ; filas de texto que faltan por subir a la PPU
fila_sub:   .res 1              ; siguiente fila que se sube
resto:      .res 1
dig:        .res 1
impreso:    .res 1
msj_ini:    .res 1              ; mensaje al encender la pantalla (lo que pasó con la partida pendiente)

        .segment "GRANDE"
pag_pos:    .res 12 * MAX_PAG   ; posición del recorrido al principio de cada página (fat.s: dir_guardar)
filas_txt:  .res (FILAS + 1) * ANCHO    ; fila 0: cabecera (carpeta y página); 1-16: la lista
filas_dir:  .res FILAS          ; $10 = la fila es una carpeta
corto_buf:  .res 14             ; nombre 8.3 como texto
num_buf:    .res 8
ruta_n:     .res 1              ; profundidad (0 = raíz)
ruta_clus:  .res 4 * PROF       ; clúster de cada carpeta de la ruta
ruta_pag:   .res PROF           ; página y fila del cursor en la carpeta de arriba (para volver con B)
ruta_fila:  .res PROF
ruta_nom:   .res NOM * PROF     ; nombre de cada carpeta (para la cabecera)

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

        lda     tipo_arranque           ; al encender, la raíz (GRANDE ya llega a cero; por si acaso)
        bne     @no_frio
        sta     ruta_n
@no_frio:
        jsr     sd_iniciar
        bcs     @error_sd
        jsr     fat_montar
        bcs     @error_fat
        jsr     datos_tarjeta
        jsr     partida_pendiente       ; la partida del último juego (vuelta de juego o encendido con pila)
        sta     msj_ini
        lda     #0
        sta     pagina
        sta     fila_c
        lda     tipo_arranque           ; al volver de un juego: su página y su fila
        cmp     #TIPO_VUELTA
        bne     @abrir
        lda     ultimo_juego
        sta     pagina
        lda     ultimo_juego+1
        sta     fila_c
@abrir: jsr     escanear
        bcc     @bien
        lda     ruta_n                  ; la carpeta guardada no se lee: a la raíz
        beq     @error_fat
        lda     #0
        sta     ruta_n
        sta     pagina
        sta     fila_c
        jsr     escanear
        bcs     @error_fat
@bien:  lda     #1
        sta     sd_bien
        jsr     leer_pagina
        ldx     #FILAS + 1
        jsr     subir_filas
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
        lda     #$FF
        sta     sel_ant
        sta     antes                   ; lo que esté pulsado al encender la pantalla no cuenta
        lda     msj_ini
        beq     encender
        jmp     mensaje
encender:
        lda     #$80
        sta     PPUCTRL
        lda     #1
        sta     mando_on
        lda     nmis
@vb:    cmp     nmis
        beq     @vb
        jsr     sin_scroll
        lda     #%00001010              ; fondo visible, también en la columna izquierda
        sta     PPUMASK

; Un paso por fotograma, sincronizado con la NMI. Lo que escribe en la PPU va al principio (VBlank): dos filas de
; texto pendientes como mucho (unos 1000 ciclos), el mando y el cursor.
bucle:
        lda     nmis
@vb:    cmp     nmis
        beq     @vb
        ldx     #2
        jsr     subir_filas
        jsr     valores_vivos
        jsr     cursor
        jsr     sin_scroll
        jsr     entrada
        jmp     bucle

; Pinta el cursor si ha cambiado de fila (durante el VBlank). Sin entradas, no hay cursor.
cursor: lda     sd_bien
        beq     @fin
        lda     filas_pag
        bne     @hay
        ldx     sel_ant
        bmi     @fin
        lda     #$FF
        sta     sel_ant
        lda     #' '
        jmp     @en
@hay:   lda     fila_c
        cmp     sel_ant
        beq     @fin
        ldx     sel_ant
        bmi     @pon
        lda     #' '
        jsr     @en
@pon:   ldx     fila_c
        stx     sel_ant
        lda     #C_CURSOR
@en:    pha
        lda     cur_hi,x
        pha
        lda     cur_lo,x
        tax
        pla
        jsr     ppu_dir
        pla
        sta     PPUDATA
@fin:   rts

; Sube a la PPU hasta X filas de texto pendientes (filas_txt -> pantalla).
subir_filas:
        stx     cuenta
@b:     lda     filas_pend
        beq     @fin
        ldx     fila_sub
        lda     sub_hi,x
        pha
        lda     sub_lo,x
        tax
        pla
        jsr     ppu_dir
        ldx     fila_sub
        lda     txt_lo,x
        sta     ptr
        lda     txt_hi,x
        sta     ptr+1
        ldy     #0
@c:     lda     (ptr),y
        sta     PPUDATA
        iny
        cpy     #ANCHO
        bne     @c
        inc     fila_sub
        dec     filas_pend
        dec     cuenta
        bne     @b
@fin:   rts

; Mando: con Select pulsado, nada. Abajo/arriba: cursor (cambia de página en el borde); derecha/izquierda: página;
; A o Start solos: abrir; B solo: volver.
entrada:
        lda     antes
        eor     #$FF
        and     botones
        sta     nuevos
        lda     botones
        sta     antes
        lda     sd_bien
        beq     @fin
        lda     botones
        and     #%00100000
        bne     @fin
        lda     nuevos
        and     #%00000100
        beq     @n1
        jsr     abajo
@n1:    lda     nuevos
        and     #%00001000
        beq     @n2
        jsr     arriba
@n2:    lda     nuevos
        and     #%00000001
        beq     @n3
        jsr     pag_der
@n3:    lda     nuevos
        and     #%00000010
        beq     @n4
        jsr     pag_izq
@n4:    lda     nuevos
        and     #%10010000              ; A o Start recién pulsados...
        beq     @n5
        lda     botones
        cmp     #%10000000              ; ...y solos
        beq     @abrir
        cmp     #%00010000
        beq     @abrir
@n5:    lda     nuevos
        and     #%01000000
        beq     @fin
        lda     botones
        cmp     #%01000000
        bne     @fin
        jmp     volver
@abrir: jmp     abrir_sel
@fin:   rts

abajo:  lda     filas_pag
        beq     @fin
        inc     fila_c
        lda     fila_c
        cmp     filas_pag
        bcc     @fin
        lda     #0
        sta     fila_c
        lda     paginas
        cmp     #2
        bcc     @fin
        jmp     pag_mas
@fin:   rts

arriba: lda     filas_pag
        beq     @fin
        lda     fila_c
        beq     @borde
        dec     fila_c
@fin:   rts
@borde: lda     paginas
        cmp     #2
        bcc     @ult
        lda     #FILAS                  ; leer_pagina lo deja en la última fila de la página
        sta     fila_c
        jmp     pag_menos
@ult:   ldx     filas_pag
        dex
        stx     fila_c
        rts

pag_der:
        lda     paginas
        cmp     #2
        bcc     pag_fin
pag_mas:
        ldx     pagina
        inx
        cpx     paginas
        bcc     @p
        ldx     #0
@p:     stx     pagina
        jmp     leer_pagina
pag_izq:
        lda     paginas
        cmp     #2
        bcc     pag_fin
pag_menos:
        ldx     pagina
        bne     @p
        ldx     paginas
@p:     dex
        stx     pagina
        jmp     leer_pagina
pag_fin:
        rts

; A sobre la fila del cursor: entra en la carpeta o lanza el juego.
abrir_sel:
        lda     filas_pag
        beq     @fin
        ldx     fila_c
        lda     filas_dir,x
        bne     entrar
        jmp     lanzar_sel
@fin:   rts

entrar: lda     ruta_n
        cmp     #PROF
        bcc     @cabe
        lda     #M_PROF
        jmp     mensaje
@cabe:  jsr     buscar_sel
        bcc     @ok
        lda     #L_SD
        jmp     mensaje
@ok:    ldx     ruta_n
        lda     pagina
        sta     ruta_pag,x
        lda     fila_c
        sta     ruta_fila,x
        jsr     ent_clus
        lda     ruta_n
        asl
        asl
        tax
        ldy     #0
@c:     lda     clus,y
        sta     ruta_clus,x
        inx
        iny
        cpy     #4
        bne     @c
        ldx     fila_c                  ; el nombre, del texto de la fila (sin la «/» final)
        inx
        jsr     fila_dst
        ldx     ruta_n
        lda     nom_desp,x
        tax
        ldy     #0
@n:     lda     (dst),y
        cmp     #'/'
        beq     @fin_n
        sta     ruta_nom,x
        inx
        iny
        cpy     #NOM
        bne     @n
        beq     @sube
@fin_n: lda     #0
        sta     ruta_nom,x
@sube:  inc     ruta_n
        lda     #0
        sta     pagina
        sta     fila_c
        jmp     cambiar_carpeta

; B: a la carpeta de arriba, con el cursor donde estaba.
volver: lda     ruta_n
        beq     @fin
        dec     ruta_n
        ldx     ruta_n
        lda     ruta_pag,x
        sta     pagina
        lda     ruta_fila,x
        sta     fila_c
        jmp     cambiar_carpeta
@fin:   rts

; Con la pantalla apagada: recorre la carpeta nueva, pinta su primera página y vuelve al bucle. Si no se puede
; leer, vuelve a la raíz y lo dice.
cambiar_carpeta:
        lda     #0
        sta     PPUMASK
        jsr     escanear
        bcc     @ok
        lda     #0
        sta     ruta_n
        sta     pagina
        sta     fila_c
        lda     fat_error
        pha
        jsr     escanear
        jsr     leer_pagina
        ldx     #FILAS + 1
        jsr     subir_filas
        pla
        sta     fat_error
        lda     #L_SD
        jmp     mensaje
@ok:    jsr     leer_pagina
        ldx     #FILAS + 1
        jsr     subir_filas
        jsr     borrar_msj
        jmp     reencender

; dir_ent = entrada de la fila del cursor (vuelve a la página y avanza). Acarreo = 1 si falla.
buscar_sel:
        lda     pagina
        jsr     pos_pagina
        jsr     dir_restaurar
        ldx     fila_c
@b:     stx     cuenta
        jsr     ent_sig
        bcs     @fin
        ldx     cuenta
        dex
        bpl     @b
        clc
@fin:   rts

; Lanza la entrada de la fila del cursor. Si no se puede, muestra por qué y vuelve al menú.
lanzar_sel:
        lda     #0
        sta     mando_on
        sta     PPUMASK
        sta     PPUCTRL
        jsr     buscar_sel
        bcs     @error_sd
        lda     pagina
        sta     ultimo_juego
        lda     fila_c
        sta     ultimo_juego+1
        jsr     lanzar                  ; solo vuelve si falla
        lda     l_error
        bne     mensaje
@error_sd:
        lda     #L_SD
; Muestra el mensaje A (L_* o M_*) con la pantalla apagada y vuelve al bucle.
mensaje:
        pha
        lda     #0
        sta     PPUMASK
        lda     #REG_CHR                ; la fuente: el lanzador puede haber movido el banco de la CHR
        sta     REG_SEL
        lda     #0
        sta     REG_DAT
        jsr     borrar_msj
        en      FILA_MSJ + 2
        pla
        pha
        tax
        lda     mensajes_lo-1,x
        sta     ptr
        lda     mensajes_hi-1,x
        sta     ptr+1
        jsr     cadena
        pla
        cmp     #L_SINMAPPER
        bne     @m5
        lda     l_mapper
        jsr     hex
        jmp     reencender
@m5:    cmp     #L_SINRBF
        bne     @m7
        ldx     #0
@n:     lda     nombre_rbf,x
        sta     PPUDATA
        inx
        cpx     #3
        bne     @n
        jmp     reencender
@m7:    cmp     #L_SD
        bne     @m12
        lda     fat_error
        jsr     hex
        jmp     reencender
@m12:   cmp     #L_ESCRIBIR
        beq     @err
        cmp     #L_PENDIENTE
        beq     @err
        cmp     #M_NOGUARDADA
        bne     reencender
@err:   lda     pt_err
        jsr     hex
reencender:
        ldx     #$FF
        txs
        stx     antes
        jmp     encender

borrar_msj:
        en      FILA_MSJ + 2
        ldx     #ANCHO
@b:     jsr     espacio
        dex
        bne     @b
        rts

; ------------------------------------------------------------------------------------------------ carpetas
; Abre la carpeta actual de la ruta.
abrir_actual:
        ldx     ruta_n
        bne     @sub
        jmp     dir_abrir_raiz
@sub:   dex
        txa
        asl
        asl
        tax
        ldy     #0
@c:     lda     ruta_clus,x
        sta     clus,y
        inx
        iny
        cpy     #4
        bne     @c
        jmp     dir_abrir_c

; Siguiente entrada que se lista (salta «.», «..», lo oculto y lo que empieza por punto). Acarreo = 1 al final.
ent_sig:
@otra:  jsr     dir_siguiente
        bcs     @fin
        ldy     #11
        lda     (dir_ent),y
        and     #$02
        bne     @otra
        ldy     #0
        lda     (dir_ent),y
        cmp     #'.'
        beq     @otra
        lda     lfn_val
        beq     @ok
        lda     lfn_buf
        cmp     #'.'
        beq     @otra
@ok:    clc
@fin:   rts

; Recorre la carpeta actual: cuenta las entradas y guarda dónde empieza cada página. Acarreo = 1 si falla.
escanear:
        lda     #0
        sta     fat_error
        sta     entradas
        sta     entradas+1
        jsr     abrir_actual
@sig:   lda     entradas
        and     #FILAS - 1
        bne     @leer
        lda     entradas+1              ; página = entradas / 16
        asl
        asl
        asl
        asl
        sta     tmp
        lda     entradas
        lsr
        lsr
        lsr
        lsr
        ora     tmp
        cmp     #MAX_PAG
        bcs     @fin
        jsr     pos_pagina
        jsr     dir_guardar
@leer:  jsr     ent_sig
        bcs     @fin
        inc     entradas
        bne     @sig
        inc     entradas+1
        jmp     @sig
@fin:   clc                             ; páginas = (entradas + 15) / 16
        lda     entradas
        adc     #FILAS - 1
        sta     tmp
        lda     entradas+1
        adc     #0
        asl
        asl
        asl
        asl
        sta     tmp2
        lda     tmp
        lsr
        lsr
        lsr
        lsr
        ora     tmp2
        sta     paginas
        lda     fat_error
        cmp     #1                      ; acarreo = 1 si hubo error
        rts

; dir_pos = pag_pos + 12 * A
pos_pagina:
        ldx     #0
        stx     tmp2
        asl
        rol     tmp2
        asl
        rol     tmp2                    ; tmp2:A = 4 * página
        sta     dir_pos
        ldx     tmp2
        stx     dir_pos+1
        asl
        rol     tmp2                    ; tmp2:A = 8 * página
        clc
        adc     dir_pos
        sta     dir_pos
        lda     tmp2
        adc     dir_pos+1
        sta     dir_pos+1
        clc
        lda     dir_pos
        adc     #<pag_pos
        sta     dir_pos
        lda     dir_pos+1
        adc     #>pag_pos
        sta     dir_pos+1
        rts

; Prepara el texto de la página `pagina` (filas_txt) y lo marca para subirlo. Deja el cursor dentro de la página.
leer_pagina:
        lda     pagina
        cmp     paginas
        bcc     @pag
        lda     #0
        sta     pagina
@pag:   lda     pagina
        jsr     pos_pagina
        jsr     dir_restaurar
        lda     #0
        sta     filas_pag
        ldx     #0
@r:     stx     cuenta
        jsr     ent_sig
        bcs     @vacias
        ldx     cuenta
        inx
        jsr     fila_dst
        ldy     #11
        lda     (dir_ent),y
        and     #$10
        ldx     cuenta
        sta     filas_dir,x
        jsr     nombre_en_fila
        inc     filas_pag
        ldx     cuenta
        inx
        cpx     #FILAS
        bne     @r
        beq     @vacia
@vacias:
        ldx     cuenta
@v:     stx     cuenta
        inx
        jsr     fila_dst
        jsr     fila_blanca
        ldx     cuenta
        inx
        cpx     #FILAS
        bne     @v
@vacia: lda     entradas
        ora     entradas+1
        bne     @cab
        ldx     #1
        jsr     fila_dst
        ldy     #0
@t:     lda     t_vacia,y
        beq     @cab
        sta     (dst),y
        iny
        bne     @t
@cab:   jsr     cabecera
        lda     fila_c
        cmp     filas_pag
        bcc     @ok
        ldx     filas_pag
        beq     @cero
        dex
        stx     fila_c
        jmp     @ok
@cero:  lda     #0
        sta     fila_c
@ok:    lda     #FILAS + 1
        sta     filas_pend
        lda     #0
        sta     fila_sub
        rts

; dst = texto de la fila X (0 = cabecera)
fila_dst:
        lda     txt_lo,x
        sta     dst
        lda     txt_hi,x
        sta     dst+1
        rts

fila_blanca:
        ldy     #ANCHO - 1
        lda     #' '
@b:     sta     (dst),y
        dey
        bpl     @b
        rts

; Cabecera: nombre de la carpeta (o «Raíz») y, a la derecha, página/páginas.
cabecera:
        ldx     #0
        jsr     fila_dst
        jsr     fila_blanca
        ldx     ruta_n
        bne     @sub
        ldy     #0
@r:     lda     t_raiz,y
        beq     @pag
        sta     (dst),y
        iny
        bne     @r
@sub:   lda     nom_desp-1,x
        tax
        ldy     #0
@n:     lda     ruta_nom,x
        beq     @pag
        sta     (dst),y
        inx
        iny
        cpy     #NOM
        bne     @n
@pag:   lda     paginas
        beq     @fin
        ldx     #0
        lda     pagina
        clc
        adc     #1
        jsr     dec_a
        lda     #'/'
        sta     num_buf,x
        inx
        lda     paginas
        jsr     dec_a
        stx     tmp
        lda     #ANCHO
        sec
        sbc     tmp
        tay
        ldx     #0
@cp:    lda     num_buf,x
        sta     (dst),y
        inx
        iny
        cpx     tmp
        bne     @cp
@fin:   rts

; A (0-255) en decimal, sin ceros delante, en num_buf a partir de X (X avanza).
dec_a:  sta     resto
        lda     #0
        sta     impreso
        ldy     #2
@d:     lda     #'0'
        sta     dig
@s:     lda     resto
        cmp     pot10,y
        bcc     @pon
        sbc     pot10,y
        sta     resto
        inc     dig
        jmp     @s
@pon:   lda     dig
        cmp     #'0'
        bne     @si
        lda     impreso
        bne     @si
        cpy     #0
        bne     @sig
@si:    lda     dig
        sta     num_buf,x
        inx
        lda     #1
        sta     impreso
@sig:   dey
        bpl     @d
        rts

; Escribe en (dst) el nombre de la entrada dir_ent, ANCHO caracteres con relleno.
nombre_en_fila:
        lda     lfn_val
        beq     @corto
        lda     #<lfn_buf
        sta     src
        lda     #>lfn_buf
        sta     src+1
        jmp     @ext
@corto: jsr     corto
@ext:   ldy     #11
        lda     (dir_ent),y
        and     #$10
        bne     @copiar
        jsr     quitar_nes
@copiar:
        ldy     #0
@c:     lda     (src),y
        beq     @fin_nom
        sta     (dst),y
        iny
        cpy     #ANCHO
        bne     @c
        lda     (src),y                 ; no cabe: «…» al final
        beq     @fin_nom
        lda     #C_PUNTOS
        ldy     #ANCHO - 1
        sta     (dst),y
        ldy     #ANCHO
@fin_nom:
        sty     tmp
        ldy     #11
        lda     (dir_ent),y
        and     #$10
        beq     @rell
        ldy     tmp                     ; carpeta: «/» al final (en la última columna si no cabe)
        cpy     #ANCHO
        bcc     @barra
        ldy     #ANCHO - 1
@barra: lda     #'/'
        sta     (dst),y
        iny
        jmp     @rell2
@rell:  ldy     tmp
@rell2: cpy     #ANCHO
        bcs     @fin
        lda     #' '
@r:     sta     (dst),y
        iny
        cpy     #ANCHO
        bne     @r
@fin:   rts

; Nombre 8.3 de dir_ent como texto en corto_buf (src apunta a él). Bits 3 y 4 del byte 12: base y extensión en
; minúsculas (así guarda Windows nombres como «zelda.nes» sin entrada larga).
corto:  ldy     #12
        lda     (dir_ent),y
        sta     tmp2
        lda     #$08
        sta     msk
        ldx     #0
        ldy     #0
@b:     lda     (dir_ent),y
        cmp     #' '
        beq     @e0
        jsr     car83
        sta     corto_buf,x
        inx
        iny
        cpy     #8
        bne     @b
@e0:    ldy     #8
        lda     (dir_ent),y
        cmp     #' '
        beq     @fin
        lda     #'.'
        sta     corto_buf,x
        inx
        lda     #$10
        sta     msk
@e:     lda     (dir_ent),y
        cmp     #' '
        beq     @fin
        jsr     car83
        sta     corto_buf,x
        inx
        iny
        cpy     #11
        bne     @e
@fin:   lda     #0
        sta     corto_buf,x
        lda     #<corto_buf
        sta     src
        lda     #>corto_buf
        sta     src+1
        rts

car83:  cmp     #$20
        bcc     @raro
        cmp     #$7F
        bcs     @raro
        cmp     #'A'
        bcc     @ya
        cmp     #'Z' + 1
        bcs     @ya
        pha
        lda     tmp2
        and     msk
        beq     @may
        pla
        ora     #$20
        rts
@may:   pla
        rts
@raro:  lda     #'?'
@ya:    rts

; Quita «.nes» (en mayúsculas o minúsculas) del final del nombre de (src).
quitar_nes:
        ldy     #0
@l:     lda     (src),y
        beq     @hay
        iny
        cpy     #LFN_MAX
        bne     @l
        rts
@hay:   cpy     #5
        bcc     @no
        dey
        lda     (src),y
        ora     #$20
        cmp     #'s'
        bne     @no
        dey
        lda     (src),y
        ora     #$20
        cmp     #'e'
        bne     @no
        dey
        lda     (src),y
        ora     #$20
        cmp     #'n'
        bne     @no
        dey
        lda     (src),y
        cmp     #'.'
        bne     @no
        lda     #0
        sta     (src),y
@no:    rts

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
        jmp     hex

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
        rts

; ------------------------------------------------------------------------------------------------ datos
        .segment "RODATA"

NT = $2000
FILA_TIT   = NT + 2 * 32
FILA_ARR   = NT + 3 * 32            ; y la siguiente (contadores)
FILA_SD    = NT + 5 * 32
FILA_RUTA  = NT + 7 * 32 + 2        ; cabecera: carpeta y página
FILA_LISTA = NT + 9 * 32 + 2        ; 16 filas (9-24)
FILA_MSJ   = NT + 25 * 32
FILA_AYUDA = NT + 26 * 32
FILA_MANDO = NT + 27 * 32

.macro texto dir, cad
        .byte   >(dir), <(dir)
        .byte   cad, 0
.endmacro

textos:
        texto   FILA_TIT + 2,       "OS propio N8 - etapa 5"
        texto   FILA_ARR + 2,       "Arranque:"
        texto   FILA_ARR + 32 + 2,  "Ent/res/vue:"
        texto   FILA_SD + 2,        "SD:"
        texto   FILA_AYUDA + 2,     {"A abrir  B volver  ", C_IZQ, C_CURSOR, " p", C_a, "gina"}
        texto   FILA_MANDO + 2,     "Mando:"
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
t_raiz:     .byte "Ra", C_i, "z", 0
t_vacia:    .byte "(carpeta vac", C_i, "a)", 0

; fila de la lista -> dirección de la PPU de su cursor (columna 1)
cur_lo:
        .repeat FILAS, i
        .byte   <(FILA_LISTA - 1 + 32 * i)
        .endrepeat
cur_hi:
        .repeat FILAS, i
        .byte   >(FILA_LISTA - 1 + 32 * i)
        .endrepeat
; fila de texto (0 = cabecera) -> dónde va en la pantalla y dónde está en filas_txt
sub_lo:
        .byte   <FILA_RUTA
        .repeat FILAS, i
        .byte   <(FILA_LISTA + 32 * i)
        .endrepeat
sub_hi:
        .byte   >FILA_RUTA
        .repeat FILAS, i
        .byte   >(FILA_LISTA + 32 * i)
        .endrepeat
txt_lo:
        .repeat FILAS + 1, i
        .byte   <(filas_txt + ANCHO * i)
        .endrepeat
txt_hi:
        .repeat FILAS + 1, i
        .byte   >(filas_txt + ANCHO * i)
        .endrepeat
nom_desp:
        .repeat PROF, i
        .byte   NOM * i
        .endrepeat
pot10:  .byte   1, 10, 100

; mensajes del lanzador (L_* de lanzar.s) y M_PROF
M_PROF = 9
m1:     .byte "No es una ROM iNES", 0
m2:     .byte "Tama", C_n, "o de ROM no admitido", 0
m3:     .byte "Falta EDFC/MAPROUT.BIN", 0
m4:     .byte "Mapper sin RBF: ", 0
m5:     .byte "No encuentro el RBF ", 0
m6:     .byte "RBF fragmentado en la SD", 0
m7:     .byte "Error de lectura ", 0
m8:     .byte "El FPGA no se configura", 0
m9:     .byte "Demasiadas carpetas", 0
m10:    .byte "Falta la carpeta EDFC/SAVE", 0
m11:    .byte "SD llena: no cabe la partida", 0
m12:    .byte "Error al escribir la SD ", 0
m13:    .byte "Partida vac", C_i, "a en EDFC/SAVE", 0
m14:    .byte "Sin guardar la anterior: ", 0
m15:    .byte "Partida guardada", 0
m16:    .byte "Partida no guardada: ", 0
m17:    .byte "Partida no encontrada", 0
mensajes_lo: .byte <m1, <m2, <m3, <m4, <m5, <m6, <m7, <m8, <m9, <m10, <m11, <m12, <m13, <m14, <m15, <m16, <m17
mensajes_hi: .byte >m1, >m2, >m3, >m4, >m5, >m6, >m7, >m8, >m9, >m10, >m11, >m12, >m13, >m14, >m15, >m16, >m17

cifras:
        .byte   "0123456789ABCDEF"
letras_mando:
        .byte   "ABSTUDLR"              ; A, B, Select, sTart, arriba (Up), abajo (Down), izquierda (Left), derecha (Right)
colores:
        .byte   $0F, $30, $10, $00,  $0F, $30, $10, $00,  $0F, $30, $10, $00,  $0F, $30, $10, $00
        .byte   $0F, $30, $10, $00,  $0F, $30, $10, $00,  $0F, $30, $10, $00,  $0F, $30, $10, $00
fuente:
        .incbin "fuente.chr"
