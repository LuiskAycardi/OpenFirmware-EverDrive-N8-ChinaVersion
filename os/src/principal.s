; principal.s — OS propio del EverDrive N8 clon, etapa 6: menú ordenado, información del juego y último juego.
; GPL-3.0-or-later. La entrada y el tipo de arranque están en arranque.s; la SD en sd.s; la FAT en fat.s; el
; lanzador en lanzar.s.
;
; Con la pantalla apagada: inicializa la tarjeta, monta la FAT y recorre la carpeta actual una vez (cuenta las
; entradas y guarda dónde empieza cada página de 16). Después enciende la pantalla. Arriba y abajo mueven el
; cursor (al pasar del borde se cambia de página), derecha e izquierda cambian de página, A o Start abren la
; entrada (una carpeta se recorre; un juego se lanza) y B vuelve a la carpeta de arriba. Mantener una dirección la
; repite. Con Select pulsado solo valen derecha e izquierda (saltan a la letra siguiente o anterior): Select y luego
; Select+A es el reset del kit Lava. La lista va en orden alfabético (orden.s), con las carpetas primero; con el
; cursor quieto, la fila 25 muestra el mapper, los tamaños y si el juego tiene pila. La carpeta y el juego del último
; lanzamiento se guardan en la PRG-RAM con pila (banco 8): al encender, el menú vuelve a ellos.
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
        .import partida_pendiente, pt_err, banco_marca
        .import orden_ini, orden_clave, orden_fin, orden_k, orden_letra, ord_ok, orden_pos_ptr, orden_pos_traer
        .import orden_puesto
        .importzp ord_src, ord_k, ord_n
        .import leer_cabecera, l_prg16, l_chr8, l_cfg, arch_abrir, arch_leer
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
w16:        .res 2              ; puesto o k en curso
cuenta2:    .res 1
info_pag:   .res 1              ; dónde estaba el cursor la última vez (fila 25: información del juego)
info_fila:  .res 1
info_cnt:   .res 1              ; fotogramas que faltan para leer la información (0 = ya está o no toca)
info_borrar: .res 1             ; 1 = vaciar la fila 25 (el cursor se ha movido)
rep_dir:    .res 1              ; dirección mantenida y fotogramas que lleva (repetición)
rep_cnt:    .res 1
sel_k:      .res 2              ; k (orden de la FAT) de la entrada del cursor (buscar_sel)
cur_k:      .res 2              ; k donde hay que poner el cursor después de recorrer la carpeta
cur_k_ok:   .res 1
ini_p:      .res 2              ; letra_ant: puesto de partida
pend_ini:   .res 1              ; filas pendientes al empezar el fotograma
repintar:   .res 1              ; 1 = se ha leído una página: volver a poner en rojo la fila del cursor

        .segment "GRANDE"
pag_pos:    .res 12 * MAX_PAG   ; posición del recorrido al principio de cada página (fat.s: dir_guardar)
filas_txt:  .res (FILAS + 2) * ANCHO    ; fila 0: cabecera (carpeta y página); 1-16: la lista; 17: información
filas_dir:  .res FILAS          ; $10 = la fila es una carpeta
corto_buf:  .res 14             ; nombre 8.3 como texto
num_buf:    .res 8
ruta_n:     .res 1              ; profundidad (0 = raíz)
ruta_clus:  .res 4 * PROF       ; clúster de cada carpeta de la ruta
ruta_pag:   .res PROF           ; página y fila del cursor en la carpeta de arriba (para volver con B)
ruta_fila:  .res PROF
ruta_nom:   .res NOM * PROF     ; nombre de cada carpeta (para la cabecera)
RUTA_TAM = 1 + 4 * PROF + PROF + PROF + NOM * PROF      ; ruta_n ... ruta_nom, seguidos

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
        bcc     :+
        jmp     @error_sd
:       jsr     fat_montar
        bcc     :+
        jmp     @error_fat
:       jsr     datos_tarjeta
        jsr     partida_pendiente       ; la partida del último juego (vuelta de juego o encendido con pila)
        sta     msj_ini
        lda     #0
        sta     pagina
        sta     fila_c
        lda     tipo_arranque           ; al encender: la carpeta y el juego del último lanzamiento
        bne     @no_frio2
        jsr     cargar_ultimo
        jmp     @abrir
@no_frio2:
        lda     tipo_arranque           ; al volver de un juego: el cursor sobre él (su k en la carpeta)
        cmp     #TIPO_VUELTA
        bne     @abrir
        lda     ultimo_juego
        sta     cur_k
        lda     ultimo_juego+1
        sta     cur_k+1
        lda     #1
        sta     cur_k_ok
@abrir: jsr     escanear
        bcc     @bien
        lda     #0
        sta     cur_k_ok
        lda     ruta_n                  ; la carpeta guardada no se lee: a la raíz
        beq     @error_fat
        lda     #0
        sta     ruta_n
        sta     pagina
        sta     fila_c
        jsr     escanear
        bcs     @error_fat
@bien:  lda     cur_k_ok                ; k -> su puesto en el orden de ahora: página y fila
        beq     @sin_k
        lda     cur_k
        ldx     cur_k+1
        jsr     orden_puesto
        sta     w16
        stx     w16+1
        lda     w16
        cmp     entradas
        lda     w16+1
        sbc     entradas+1
        bcs     @sin_k                  ; ya no está (otra tarjeta): al principio
        lda     w16
        and     #FILAS - 1
        sta     fila_c
        lda     w16+1
        asl
        asl
        asl
        asl
        sta     tmp
        lda     w16
        lsr
        lsr
        lsr
        lsr
        ora     tmp
        sta     pagina
@sin_k: lda     #1
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
        sta     info_pag                ; ($FF) la información del juego, cuando el cursor se quede quieto
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
        lda     filas_pend              ; ¿hay filas que subir en este fotograma? (el cursor espera)
        sta     pend_ini
        ldx     #2
        jsr     subir_filas
        jsr     valores_vivos
        jsr     cursor
        jsr     sin_scroll
        jsr     entrada
        jsr     info_tick
        jmp     bucle

; Cursor y fila seleccionada en rojo (durante el VBlank): si el cursor ha cambiado de fila, la fila de antes vuelve
; a su texto normal (y sin ▶) y la nueva se escribe con los tiles rojos (código XOR $80, fuente.py) y el ▶ rojo. Solo
; en un fotograma sin filas de texto pendientes (no caben las dos cosas en el VBlank). Después de leer una página
; (`repintar`), la fila seleccionada ya llegó en normal: se vuelve a poner en rojo. Sin entradas, no hay cursor.
cursor: lda     sd_bien
        beq     @fin
        lda     pend_ini
        bne     @fin
        lda     repintar
        bne     @rep
        lda     filas_pag
        beq     @sin
        lda     fila_c
        cmp     sel_ant
        beq     @fin
        ldx     sel_ant
        bmi     @pon
        lda     #0                      ; la de antes, normal
        jsr     fila_ppu
@pon:   ldx     fila_c
        stx     sel_ant
        lda     #$80                    ; la nueva, en rojo
        jmp     fila_ppu
@rep:   lda     #0
        sta     repintar
        ldx     sel_ant                 ; quitar el ▶ de la fila de antes (su texto ya es el nuevo)
        bmi     @r2
        lda     cur_hi,x
        pha
        lda     cur_lo,x
        tax
        pla
        jsr     ppu_dir
        lda     #' '
        sta     PPUDATA
@r2:    lda     filas_pag
        beq     @nada
        ldx     fila_c
        stx     sel_ant
        lda     #$80
        jmp     fila_ppu
@sin:   ldx     sel_ant
        bmi     @fin
        lda     #0
        jsr     fila_ppu
@nada:  lda     #$FF
        sta     sel_ant
@fin:   rts

; Escribe en la PPU la fila X de la lista: el ▶ (o un espacio) y su texto, con los códigos XOR A ($80 = rojo).
fila_ppu:
        sta     msk
        lda     cur_hi,x                ; columna 1: el cursor
        pha
        lda     cur_lo,x
        pha
        inx                             ; texto: filas_txt fila X + 1
        lda     txt_lo,x
        sta     ptr
        lda     txt_hi,x
        sta     ptr+1
        pla
        tax
        pla
        jsr     ppu_dir
        lda     msk
        beq     @blanco
        lda     #C_CURSOR ^ $80
        bne     @c
@blanco:
        lda     #' '
@c:     sta     PPUDATA
        ldy     #0
@t:     lda     (ptr),y
        eor     msk
        sta     PPUDATA
        iny
        cpy     #ANCHO
        bne     @t
        rts

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
        jsr     repetir
        lda     sd_bien
        beq     @fin
        lda     botones
        and     #%00100000
        beq     @sin_sel
        lda     nuevos                  ; Select + derecha / izquierda: letra siguiente / anterior
        and     #%00000001
        beq     :+
        jmp     letra_sig
:       lda     nuevos
        and     #%00000010
        beq     @fin
        jmp     letra_ant
@sin_sel:
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

; Mantener una dirección: a los 20 fotogramas se repite cada 4 (como si se volviera a pulsar).
repetir:
        lda     botones
        and     #%00001111
        beq     @cero
        cmp     rep_dir
        beq     @mismo
        sta     rep_dir
        lda     #0
        sta     rep_cnt
        rts
@mismo: inc     rep_cnt
        lda     rep_cnt
        cmp     #20
        bcc     @fin
        lda     #16
        sta     rep_cnt
        lda     rep_dir
        ora     nuevos
        sta     nuevos
@fin:   rts
@cero:  sta     rep_dir
        sta     rep_cnt
        rts

; Arriba y abajo se quedan en la página: paran en la primera y en la última fila (las páginas, con derecha e
; izquierda).
abajo:  ldx     fila_c
        inx
        cpx     filas_pag
        bcs     @fin
        stx     fila_c
@fin:   rts

arriba: lda     fila_c
        beq     @fin
        dec     fila_c
@fin:   rts

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
        lda     #$FF                    ; carpeta nueva: información del juego cuando el cursor se quede quieto
        sta     info_pag
        jmp     reencender

; dir_ent = entrada de la fila del cursor. Acarreo = 1 si falla.
buscar_sel:
        lda     fila_c
        jsr     puesto
        jsr     orden_k
        sta     sel_k
        stx     sel_k+1
; dir_ent = entrada k (A bajo, X alto) en el orden de la FAT: vuelve al principio de su página de 16 (pag_pos) y
; avanza. Acarreo = 1 si falla.
traer_k:
        sta     w16
        stx     w16+1
        sta     ord_k
        stx     ord_k+1
        jsr     orden_pos_traer         ; carpeta ordenada: su posición exacta
        bcs     @pagina
        jsr     dir_restaurar
        jmp     ent_sig
@pagina:
        lda     w16+1                   ; página = k / 16
        asl
        asl
        asl
        asl
        sta     tmp
        lda     w16
        lsr
        lsr
        lsr
        lsr
        ora     tmp
        jsr     pos_pagina
        jsr     dir_restaurar
        lda     w16
        and     #FILAS - 1
        tax
@b:     stx     cuenta2
        jsr     ent_sig
        bcs     @fin
        ldx     cuenta2
        dex
        bpl     @b
        clc
@fin:   rts

; A:X = puesto de la fila A de la página a la vista (pagina x 16 + A).
puesto: sta     tmp
        lda     pagina
        sta     w16
        lda     #0
        sta     w16+1
        ldx     #4
@x:     asl     w16
        rol     w16+1
        dex
        bne     @x
        lda     w16
        ora     tmp
        ldx     w16+1
        rts

; Lanza la entrada de la fila del cursor. Si no se puede, muestra por qué y vuelve al menú.
lanzar_sel:
        lda     #0
        sta     mando_on
        sta     PPUMASK
        sta     PPUCTRL
        jsr     buscar_sel
        bcs     @error_sd
        lda     sel_k
        sta     ultimo_juego
        lda     sel_k+1
        sta     ultimo_juego+1
        jsr     guardar_ultimo
        jsr     lanzar                  ; solo vuelve si falla
        lda     l_error
        pha
        jsr     escanear                ; la partida pudo pisar las claves del orden (PRG-RAM): se rehacen
        pla
        bne     mensaje
@error_sd:
        lda     #L_SD
; Muestra el mensaje A (L_* o M_*) con la pantalla apagada y vuelve al bucle.
mensaje:
        pha
        lda     pagina                  ; que la información del juego no tape el mensaje hasta que se mueva el cursor
        sta     info_pag
        lda     fila_c
        sta     info_fila
        lda     #0
        sta     info_cnt
        sta     info_borrar
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
        jsr     orden_ini
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
@leer:  lda     entradas                ; posición antes de la entrada (para leerla luego directamente)
        sta     ord_k
        lda     entradas+1
        sta     ord_k+1
        jsr     orden_pos_ptr
        bcs     :+
        jsr     dir_guardar
:       jsr     ent_sig
        bcs     @fin
        jsr     clave_ent
        inc     entradas
        bne     @sig
        inc     entradas+1
        jmp     @sig
@fin:   lda     entradas
        sta     ord_n
        lda     entradas+1
        sta     ord_n+1
        jsr     orden_fin
        clc                             ; páginas = (entradas + 15) / 16
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

; Clave del orden de la entrada dir_ent, que es la número `entradas` de la carpeta.
clave_ent:
        lda     entradas
        sta     ord_k
        lda     entradas+1
        sta     ord_k+1
        jsr     nombre_src
        lda     src
        sta     ord_src
        lda     src+1
        sta     ord_src+1
        ldy     #11
        lda     (dir_ent),y
        and     #$10
        beq     @arch
        lda     #0
        jmp     orden_clave
@arch:  lda     #1
        jmp     orden_clave

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
@pag:   lda     #0
        sta     filas_pag
        lda     ord_ok
        beq     @fat
        ldx     #0                      ; en orden: cada fila es la entrada k = ord_idx[puesto]
@ro:    stx     cuenta
        txa
        jsr     puesto
        cpx     entradas+1              ; puesto >= entradas: filas vacías
        bcc     @dentro
        bne     @vac
        cmp     entradas
        bcs     @vac
@dentro:
        jsr     orden_k
        jsr     traer_k
        bcs     @vac
        jsr     @poner
        ldx     cuenta
        inx
        cpx     #FILAS
        bne     @ro
        beq     @vacia
@vac:   jmp     @vacias
@fat:   lda     pagina                  ; sin orden: las 16 seguidas desde el principio de la página
        jsr     pos_pagina
        jsr     dir_restaurar
        ldx     #0
@r:     stx     cuenta
        jsr     ent_sig
        bcs     @vacias
        jsr     @poner
        ldx     cuenta
        inx
        cpx     #FILAS
        bne     @r
        beq     @vacia
; Texto y tipo de la fila `cuenta` con la entrada dir_ent.
@poner:
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
        rts
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
        lda     #1
        sta     repintar
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
        jsr     nombre_src
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

; src = el nombre que se ve de la entrada dir_ent: el largo o el 8.3, sin «.nes» si es un archivo.
nombre_src:
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
        bne     @fin
        jmp     quitar_nes
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

; ------------------------------------------------------------------------------------------------ información
; Con el cursor quieto 12 fotogramas (y la página ya subida), la fila 25 dice el mapper, los tamaños y si tiene pila.
info_tick:
        lda     sd_bien
        beq     @fin
        lda     pagina
        cmp     info_pag
        bne     @mov
        lda     fila_c
        cmp     info_fila
        bne     @mov
        lda     filas_pend
        bne     @fin
        lda     info_borrar             ; primero, vaciar la fila (que no se vea la información de otro juego)
        beq     @cuenta
        lda     #0
        sta     info_borrar
        ldx     #FILA_INFO
        jsr     fila_dst
        jsr     fila_blanca
        jmp     subir_info
@cuenta:
        lda     info_cnt
        beq     @fin
        dec     info_cnt
        bne     @fin
        jmp     mostrar_info
@mov:   lda     pagina
        sta     info_pag
        lda     fila_c
        sta     info_fila
        lda     #12
        sta     info_cnt
        lda     #1
        sta     info_borrar
@fin:   rts

; Prepara la fila de información (filas_txt 17) de la entrada del cursor y la marca para subirla.
FILA_INFO = FILAS + 1
mostrar_info:
        ldx     #FILA_INFO
        jsr     fila_dst
        jsr     fila_blanca
        lda     filas_pag
        beq     @nada
        ldx     fila_c
        lda     filas_dir,x
        bne     @nada                   ; carpeta: nada
        jsr     buscar_sel
        bcs     @nada
        jsr     arch_abrir
        jsr     arch_leer
        bcc     :+
@nada:  jmp     @sube
:       jsr     leer_cabecera
        bcc     @rom
        tax                             ; no se puede lanzar: el mismo texto que al intentarlo
        lda     mensajes_lo-1,x
        sta     src
        lda     mensajes_hi-1,x
        sta     src+1
        ldy     #0
        jsr     copia_src
        jmp     @sube
@rom:   ldy     #0                      ; «Mapper N  PRGK+CHRK  pila»
        lda     #<t_mapper
        sta     src
        lda     #>t_mapper
        sta     src+1
        jsr     copia_src
        lda     l_mapper
        sta     w16
        lda     #0
        sta     w16+1
        jsr     dec16
        lda     #' '
        sta     (dst),y
        iny
        sta     (dst),y
        iny
        lda     l_prg16                 ; x 16 KiB
        sta     w16
        lda     #0
        sta     w16+1
        ldx     #4
@p:     asl     w16
        rol     w16+1
        dex
        bne     @p
        jsr     dec16
        lda     #'K'
        sta     (dst),y
        iny
        lda     #'+'
        sta     (dst),y
        iny
        lda     l_chr8
        bne     @chr
        lda     #<t_ram
        sta     src
        lda     #>t_ram
        sta     src+1
        jsr     copia_src
        jmp     @pila
@chr:   sta     w16                     ; x 8 KiB
        lda     #0
        sta     w16+1
        ldx     #3
@c:     asl     w16
        rol     w16+1
        dex
        bne     @c
        jsr     dec16
        lda     #'K'
        sta     (dst),y
        iny
@pila:  lda     l_cfg
        and     #$02
        beq     @sube
        lda     #<t_pila
        sta     src
        lda     #>t_pila
        sta     src+1
        jsr     copia_src
@sube:
subir_info:
        lda     #FILA_INFO
        sta     fila_sub
        lda     #1
        sta     filas_pend
        rts

; Copia la cadena (src) a (dst) desde la columna Y (Y avanza; como mucho hasta ANCHO).
copia_src:
        sty     tmp
        ldy     #0
@c:     lda     (src),y
        beq     @fin
        sty     tmp2
        ldy     tmp
        cpy     #ANCHO
        bcs     @fin
        sta     (dst),y
        inc     tmp
        ldy     tmp2
        iny
        bne     @c
@fin:   ldy     tmp
        rts

; w16 (0-999) en decimal, sin ceros delante, en (dst) desde la columna Y (Y avanza).
dec16:  lda     #0
        sta     impreso
        ldx     #2
@d:     lda     #'0'
        sta     dig
@s:     lda     w16                     ; ¿w16 >= 10^x?
        cmp     pot10,x
        lda     w16+1
        sbc     pot10_hi,x
        bcc     @pon
        lda     w16
        sbc     pot10,x                 ; acarreo = 1
        sta     w16
        lda     w16+1
        sbc     pot10_hi,x
        sta     w16+1
        inc     dig
        jmp     @s
@pon:   lda     dig
        cmp     #'0'
        bne     @si
        lda     impreso
        bne     @si
        cpx     #0
        bne     @sig
@si:    lda     dig
        sta     (dst),y
        iny
        lda     #1
        sta     impreso
@sig:   dex
        bpl     @d
        rts

; ------------------------------------------------------------------------------------------------ saltos por letra
; Select + derecha: al primer puesto con otra letra (o al principio, desde la última). Solo con la carpeta ordenada.
letra_sig:
        lda     ord_ok
        beq     @fin
        lda     filas_pag
        beq     @fin
        lda     fila_c
        jsr     puesto
        sta     w16
        stx     w16+1
        jsr     orden_letra
        sta     tmp2                    ; letra actual
@b:     inc     w16
        bne     :+
        inc     w16+1
:       lda     w16                     ; ¿al final? al principio
        cmp     entradas
        lda     w16+1
        sbc     entradas+1
        bcs     @cero
        lda     w16
        ldx     w16+1
        jsr     orden_letra
        cmp     tmp2
        beq     @b
        jmp     ir_puesto
@cero:  lda     #0
        sta     w16
        sta     w16+1
        jmp     ir_puesto
@fin:   rts

; Select + izquierda: al principio de la letra actual o, si ya se está en él, al de la anterior.
letra_ant:
        lda     ord_ok
        beq     @fin
        lda     filas_pag
        beq     @fin
        lda     fila_c
        jsr     puesto
        sta     w16
        stx     w16+1
        jsr     inicio_letra
        lda     w16                     ; ¿se ha movido?
        cmp     ini_p                   ; (ini_p guarda el puesto de partida)
        bne     @ir
        lda     w16+1
        cmp     ini_p+1
        bne     @ir
        lda     w16                     ; ya al principio: la letra anterior (o la última, desde el 0)
        ora     w16+1
        bne     @atras
        lda     entradas
        sta     w16
        lda     entradas+1
        sta     w16+1
@atras: lda     w16
        bne     :+
        dec     w16+1
:       dec     w16
        jsr     inicio_letra
@ir:    jmp     ir_puesto
@fin:   rts

; w16 = primer puesto de la racha de letras de w16 (hacia atrás). Deja en ini_p el puesto de partida.
inicio_letra:
        lda     w16
        sta     ini_p
        lda     w16+1
        sta     ini_p+1
        lda     w16
        ldx     w16+1
        jsr     orden_letra
        sta     tmp2
@b:     lda     w16
        ora     w16+1
        beq     @fin
        lda     w16                     ; ¿la de antes tiene la misma letra?
        sec
        sbc     #1
        pha
        lda     w16+1
        sbc     #0
        tax
        pla
        pha
        stx     tmp
        jsr     orden_letra
        cmp     tmp2
        bne     @fin2
        pla
        sta     w16
        lda     tmp
        sta     w16+1
        jmp     @b
@fin2:  pla
@fin:   rts

; Lleva el cursor al puesto w16 (página y fila) y pide la página.
ir_puesto:
        lda     w16
        and     #FILAS - 1
        sta     fila_c
        lda     w16+1
        asl
        asl
        asl
        asl
        sta     tmp
        lda     w16
        lsr
        lsr
        lsr
        lsr
        ora     tmp
        sta     pagina
        jmp     leer_pagina

; ------------------------------------------------------------------------------------------------ último juego
; Guarda en el banco 8 (PRG-RAM con pila, detrás de la marca de partida) la ruta y el cursor del juego que se lanza.
ULT = $6040
guardar_ultimo:
        jsr     banco_marca
        ldx     #3
@f:     lda     firma_ult,x
        sta     ULT,x
        dex
        bpl     @f
        lda     #$5A
        sta     tmp
        ldx     #0
@r:     lda     ruta_n,x
        sta     ULT+4,x
        clc
        adc     tmp
        sta     tmp
        inx
        cpx     #RUTA_TAM
        bne     @r
        lda     sel_k                   ; el juego: su k en la carpeta
        sta     ULT+4+RUTA_TAM
        clc
        adc     tmp
        sta     tmp
        lda     sel_k+1
        sta     ULT+5+RUTA_TAM
        clc
        adc     tmp
        sta     ULT+6+RUTA_TAM
        rts

; Al encender: si el banco 8 tiene un último juego válido y su carpeta sigue ahí, lo pone en la ruta y el cursor.
cargar_ultimo:
        jsr     banco_marca
        ldx     #3
@f:     lda     ULT,x
        cmp     firma_ult,x
        bne     @no
        dex
        bpl     @f
        lda     #$5A
        ldx     #0
@s:     clc
        adc     ULT+4,x
        inx
        cpx     #RUTA_TAM + 2
        bne     @s
        cmp     ULT+6+RUTA_TAM
        bne     @no
        lda     ULT+4                   ; profundidad
        cmp     #PROF + 1
        bcs     @no
        ldx     #0
@c:     lda     ULT+4,x
        sta     ruta_n,x
        inx
        cpx     #RUTA_TAM
        bne     @c
        lda     ULT+4+RUTA_TAM
        sta     cur_k
        lda     ULT+5+RUTA_TAM
        sta     cur_k+1
        lda     #1
        sta     cur_k_ok
        lda     ruta_n                  ; la carpeta tiene que seguir siendo una carpeta: su primera entrada es «.»
        beq     @si
        jsr     abrir_actual
        jsr     dir_siguiente
        bcs     @raiz
        ldy     #10
@p:     lda     (dir_ent),y
        cmp     n_punto,y
        bne     @raiz
        dey
        bpl     @p
        ldy     #11
        lda     (dir_ent),y
        and     #$10
        beq     @raiz
@si:    rts
@raiz:  lda     #0
        sta     ruta_n
        sta     cur_k_ok
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
        lda     #$00                    ; el patrón 0 entero: $20-$9F normal, el resto en rojo (fuente.py)
        ldx     #$00
        jsr     ppu_dir
        lda     #<fuente
        sta     ptr
        lda     #>fuente
        sta     ptr+1
        ldx     #16                     ; 16 x 256 = 4096 bytes (256 tiles)
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
        texto   FILA_TIT + 2,       "OS propio N8 - etapa 6"
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
t_mapper:   .byte "Mapper ", 0
t_pila:     .byte "  pila", 0
t_ram:      .byte "RAM", 0
firma_ult:  .byte "N8UL"

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
        .byte   <(FILA_MSJ + 2)
sub_hi:
        .byte   >FILA_RUTA
        .repeat FILAS, i
        .byte   >(FILA_LISTA + 32 * i)
        .endrepeat
        .byte   >(FILA_MSJ + 2)
txt_lo:
        .repeat FILAS + 2, i
        .byte   <(filas_txt + ANCHO * i)
        .endrepeat
txt_hi:
        .repeat FILAS + 2, i
        .byte   >(filas_txt + ANCHO * i)
        .endrepeat
nom_desp:
        .repeat PROF, i
        .byte   NOM * i
        .endrepeat
pot10:  .byte   1, 10, 100
pot10_hi: .byte 0, 0, 0
n_punto: .byte  ".          "

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
        .byte   $0F, $30, $16, $00,  $0F, $30, $16, $00,  $0F, $30, $16, $00,  $0F, $30, $16, $00    ; 2 = rojo
        .byte   $0F, $30, $16, $00,  $0F, $30, $16, $00,  $0F, $30, $16, $00,  $0F, $30, $16, $00
fuente:
        .incbin "fuente.chr"
