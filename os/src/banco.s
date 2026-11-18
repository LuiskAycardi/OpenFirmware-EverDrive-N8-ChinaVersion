; banco.s — modo banco: lanzar los juegos de una lista, para las pruebas automáticas en la consola
; (tools/consola). GPL-3.0-or-later, código propio.
;
; Si existe EDFC/BANCO.TXT, al arrancar el OS no enseña el menú, sino la pantalla de banco con una entrada de la
; lista: su número («Modo banco 12/154»), la ruta, el mapper y los tamaños y dos filas de bloques con el número en
; binario (16 bits, del más alto al más bajo, entre dos bloques de marca) y su complemento, que el PC lee en la
; captura sin OCR. Mando: Start lanza la entrada; derecha / izquierda pasan a la siguiente / anterior; B sale al
; menú normal hasta el siguiente encendido.
;
; BANCO.TXT: una ruta por línea desde la raíz de la SD («PRUEBAS/1 MMC1/Metroid (USA).nes»), en UTF-8, con los
; nombres largos tal cual (sin distinguir mayúsculas de ASCII) o los 8.3. Las líneas vacías y las que empiezan por
; «#» no cuentan. Fin de línea LF o CR LF. Directiva (línea que empieza por «!», no cuenta como entrada):
;   !ram=XX   antes de cada lanzamiento, la PRG-RAM de las partidas (64 KiB) a $XX y los juegos con pila sin su
;             partida: ni se carga ni se guarda (las pruebas no tocan las partidas de verdad y el juego arranca como
;             en Mesen2, que empieza con la RAM a cero: !ram=00).
;
; El número de la entrada se guarda en la PRG-RAM con pila (banco 8, $6200, con la identidad del archivo: si
; BANCO.TXT cambia, se vuelve a la primera). Al lanzar, se guarda ya el de la siguiente: después del juego, el botón
; RESET (o el kit Lava) vuelve a la pantalla de banco con la entrada siguiente. Si el lanzamiento falla, la pantalla
; vuelve enseguida con la siguiente y el motivo en la fila 25.

        .setcpu "6502"
        .include "os.inc"

        .export banco
        .import principal, ppu_dir, cadena, info_de_ent, dec16, fila_blanca, copia_src, mensajes_lo, mensajes_hi
        .importzp ptr, dst, src, botones, nmis, mando_on, w16
        .import dir_abrir_raiz, dir_buscar, dir_abrir, dir_siguiente, ent_clus
        .import arch_abrir, arch_leer, arch_avanzar, arch_tam, sector, lfn_val, ucs_a_fuente, lfn_lo
        .import pt_nom, pt_len, igual_largo, banco_marca
        .import lanzar, l_error, abrir_edfc, l_sin_partida
        .importzp dir_ent, nombre, clus

ANCHO   = 28
NT      = $2000
FILA_TIT  = NT + 7 * 32 + 2
FILA_RUTA = NT + 9 * 32 + 2     ; 3 filas
FILA_INF  = NT + 13 * 32 + 2
FILA_COD  = NT + 16 * 32 + 2    ; 2 filas: el número y su complemento
FILA_MSJ  = NT + 25 * 32 + 2
FILA_AYU  = NT + 26 * 32 + 2
VENT    = $6000
PUESTO  = VENT + $200
REG_RAM = 129           ; banco 8: "N8BK", clúster (4), tamaño (4), entrada (2), suma

        .segment "ZEROPAGE"
bp:         .res 2              ; byte del sector que se lee / carácter de la línea
quedan:     .res 4              ; bytes del archivo que faltan
bk_len:     .res 1

        .segment "GRANDE"
bk_linea:   .res 256            ; la línea de la entrada a la vista (UTF-8, terminada en 0)
bk_texto:   .res ANCHO          ; una fila de texto
bk_n:       .res 2              ; entradas de la lista
bk_i:       .res 2              ; entrada a la vista (bk_n = «lista terminada»)
bk_cuenta:  .res 2
bk_hay:     .res 1              ; 1 = la línea de bk_i se ha encontrado
bk_primero: .res 1
bk_salir:   .res 1              ; 1 = el usuario salió al menú con B (hasta apagar: GRANDE llega a cero)
bk_err:     .res 1              ; motivo del último lanzamiento fallido (L_*), 0 = nada
bk_clus:    .res 4              ; identidad de BANCO.TXT: primer clúster y tamaño
bk_tam:     .res 4
bk_ant:     .res 1
bk_ult:     .res 1              ; 1 = el último componente de la ruta
bk_marca:   .res 15
bk_dir:     .res 8              ; la línea de una directiva («!ram=00»)
bk_ram_on:  .res 1              ; 1 = hay !ram=XX
bk_ram_val: .res 1

        .segment "CODE"

; Desde principal, con la SD montada y la pantalla apagada. Si no hay lista (o el usuario salió con B), vuelve con
; acarreo = 0 y sigue el menú. Si la hay, no vuelve.
banco:
        lda     bk_salir
        bne     @no
        jsr     abrir_lista
        bcs     @no
        jsr     cargar_puesto
        jmp     pantalla
@no:    clc
        rts

; ------------------------------------------------------------------------------------------------ la lista
; Abre EDFC/BANCO.TXT (deja bk_clus y bk_tam). Acarreo = 1 si no está.
abrir_lista:
        jsr     abrir_edfc
        bcs     @no
        lda     #<n_banco
        sta     nombre
        lda     #>n_banco
        sta     nombre+1
        jsr     dir_buscar
        bcs     @no
        ldy     #11
        lda     (dir_ent),y
        and     #$18
        bne     @no
        jsr     ent_clus
        ldx     #3
@c:     lda     clus,x
        sta     bk_clus,x
        dex
        bpl     @c
        ldy     #28
        ldx     #0
@t:     lda     (dir_ent),y
        sta     bk_tam,x
        iny
        inx
        cpx     #4
        bne     @t
        jsr     arch_abrir
        clc
        rts
@no:    sec
        rts

; Recorre la lista: bk_n = entradas y, si existe, la línea bk_i en bk_linea (bk_hay = 1).
leer_lista:
        lda     #0
        sta     bk_n
        sta     bk_n+1
        sta     bk_hay
        sta     bk_len
        sta     bk_linea
        sta     bk_ram_on
        jsr     abrir_lista
        bcs     @fin
        ldx     #3
@q:     lda     bk_tam,x
        sta     quedan,x
        dex
        bpl     @q
        jsr     arch_leer
        bcs     @fin
        lda     #<sector
        sta     bp
        lda     #>sector
        sta     bp+1
@b:     jsr     sig_byte
        bcs     @eof
        cmp     #$0A
        beq     @nl
        cmp     #$0D
        beq     @b
        ldx     bk_len
        bne     :+
        sta     bk_primero
:       cpx     #255                    ; la línea, solo si es la que se busca (y hasta 255 bytes)
        bcs     @b
        inc     bk_len
        tay
        lda     bk_primero              ; directiva: a bk_dir (8 bytes)
        cmp     #'!'
        bne     @normal
        cpx     #8
        bcs     @b
        tya
        sta     bk_dir,x
        jmp     @b
@normal:
        lda     bk_n
        cmp     bk_i
        bne     @b
        lda     bk_n+1
        cmp     bk_i+1
        bne     @b
        tya
        sta     bk_linea,x
        lda     #0
        sta     bk_linea+1,x
        beq     @b
@nl:    jsr     fin_linea
        jmp     @b
@eof:   jsr     fin_linea
@fin:   rts

; Fin de una línea: si no está vacía ni es un comentario, cuenta (y si era la buscada, queda).
fin_linea:
        lda     bk_len
        beq     @fin
        lda     bk_primero
        cmp     #'#'
        beq     @fin
        cmp     #'!'
        bne     :+
        jsr     directiva
        jmp     @fin
:
        lda     bk_n
        cmp     bk_i
        bne     @cuenta
        lda     bk_n+1
        cmp     bk_i+1
        bne     @cuenta
        lda     #1
        sta     bk_hay
@cuenta:
        inc     bk_n
        bne     @fin
        inc     bk_n+1
@fin:   lda     #0
        sta     bk_len
        rts

; La directiva de bk_dir (bk_len bytes): «!ram=XX» (XX en hexadecimal). Las demás se ignoran.
directiva:
        lda     bk_len
        cmp     #7
        bcc     @fin
        ldx     #4
@c:     lda     bk_dir,x
        cmp     t_ram_dir,x
        bne     @fin
        dex
        bpl     @c
        lda     bk_dir+5
        jsr     cifra_hex
        bcs     @fin
        asl
        asl
        asl
        asl
        sta     bk_ram_val
        lda     bk_dir+6
        jsr     cifra_hex
        bcs     @fin
        ora     bk_ram_val
        sta     bk_ram_val
        lda     #1
        sta     bk_ram_on
@fin:   rts

; A = valor de la cifra hexadecimal A (acarreo = 1 si no lo es).
cifra_hex:
        cmp     #'0'
        bcc     @no
        cmp     #'9' + 1
        bcc     @dig
        ora     #$20
        cmp     #'a'
        bcc     @no
        cmp     #'f' + 1
        bcs     @no
        sbc     #'a' - 10 - 1           ; acarreo = 0
        clc
        rts
@dig:   sbc     #'0' - 1                ; acarreo = 0
        clc
        rts
@no:    sec
        rts

; Con !ram=XX: los 8 bancos de la PRG-RAM de las partidas (0x00000-0x0FFFF) a XX.
llenar_ram:
        ldx     #0
@banco: lda     #REG_RAM
        sta     REG_SEL
        stx     REG_DAT
        lda     #0
        sta     REG_SEL
        lda     #<VENT
        sta     bp
        lda     #>VENT
        sta     bp+1
        lda     bk_ram_val
        ldy     #0
@b:     sta     (bp),y
        iny
        bne     @b
        inc     bp+1
        ldy     bp+1
        cpy     #>(VENT + $2000)
        ldy     #0
        bcc     @b
        inx
        cpx     #8
        bne     @banco
        rts

; A = siguiente byte del archivo. Acarreo = 1 al final (o si falla la lectura).
sig_byte:
        lda     quedan
        ora     quedan+1
        ora     quedan+2
        ora     quedan+3
        beq     @fin
        lda     bp+1
        cmp     #>(sector + 512)
        bne     @hay
        lda     bp
        cmp     #<(sector + 512)
        bne     @hay
        jsr     arch_avanzar
        bcs     @fin
        jsr     arch_leer
        bcs     @fin
        lda     #<sector
        sta     bp
        lda     #>sector
        sta     bp+1
@hay:   lda     quedan                  ; quedan - 1
        bne     @d0
        lda     quedan+1
        bne     @d1
        lda     quedan+2
        bne     @d2
        dec     quedan+3
@d2:    dec     quedan+2
@d1:    dec     quedan+1
@d0:    dec     quedan
        ldy     #0
        lda     (bp),y
        inc     bp
        bne     :+
        inc     bp+1
:       clc
        rts
@fin:   sec
        rts

; ------------------------------------------------------------------------------------------------ el puesto
; bk_i = la entrada guardada en el banco 8 si la firma, la suma y la identidad de BANCO.TXT valen; si no, 0.
cargar_puesto:
        jsr     banco_marca
        ldx     #14
@l:     lda     PUESTO,x
        sta     bk_marca,x
        dex
        bpl     @l
        lda     #0
        sta     bk_i
        sta     bk_i+1
        ldx     #3
@f:     lda     bk_marca,x
        cmp     firma_bk,x
        bne     @no
        lda     bk_marca+4,x
        cmp     bk_clus,x
        bne     @no
        lda     bk_marca+8,x
        cmp     bk_tam,x
        bne     @no
        dex
        bpl     @f
        jsr     suma_puesto
        cmp     bk_marca+14
        bne     @no
        lda     bk_marca+12
        sta     bk_i
        lda     bk_marca+13
        sta     bk_i+1
@no:    rts

guardar_puesto:
        ldx     #3
@c:     lda     firma_bk,x
        sta     bk_marca,x
        lda     bk_clus,x
        sta     bk_marca+4,x
        lda     bk_tam,x
        sta     bk_marca+8,x
        dex
        bpl     @c
        lda     bk_i
        sta     bk_marca+12
        lda     bk_i+1
        sta     bk_marca+13
        jsr     suma_puesto
        sta     bk_marca+14
        jsr     banco_marca
        ldx     #14
@g:     lda     bk_marca,x
        sta     PUESTO,x
        dex
        bpl     @g
        rts

suma_puesto:
        lda     #$3C
        ldx     #13
@s:     clc
        adc     bk_marca,x
        dex
        bpl     @s
        rts

; ------------------------------------------------------------------------------------------------ la ruta
; Busca en la SD la ruta de bk_linea (UTF-8). Acarreo = 0: dir_ent es el archivo (con su nombre largo recién leído,
; como lo deja el menú para lanzar).
resolver:
        jsr     dir_abrir_raiz
        lda     #<bk_linea
        sta     bp
        lda     #>bk_linea
        sta     bp+1
@comp:  jsr     componente
        lda     pt_len
        bne     @busca
        lda     bk_ult                  ; componente vacío («//» o «/» al final)
        bne     @no
        beq     @comp
@busca: jsr     dir_siguiente
        bcs     @no
        lda     lfn_val
        beq     @corto
        jsr     igual_largo
        beq     @si
@corto: jsr     igual_83
        bne     @busca
@si:    ldy     #11
        lda     (dir_ent),y
        and     #$10
        ldx     bk_ult
        bne     @arch
        cmp     #0                      ; en medio de la ruta: tiene que ser una carpeta
        beq     @no
        jsr     dir_abrir
        jmp     @comp
@arch:  cmp     #0                      ; al final: un archivo
        bne     @no
        clc
        rts
@no:    sec
        rts

; El siguiente componente de la ruta (bp) en pt_nom (UCS-2) y pt_len. bk_ult = 1 si era el último.
componente:
        lda     #0
        sta     pt_len
        sta     bk_ult
@c:     ldy     #0
        lda     (bp),y
        bne     :+
        inc     bk_ult
        rts
:       jsr     avanza
        cmp     #'/'
        bne     :+
        rts
:       cmp     #$80
        bcc     @ascii
        cmp     #$E0
        bcs     @tres
        cmp     #$C0
        bcc     @raro
        ; 110xxxxx 10yyyyyy -> 00000xxx xxyyyyyy
        pha
        lsr
        lsr
        and     #$07
        sta     bk_ant                  ; alto
        pla
        and     #$03
        jsr     bajo_6
        jmp     @pon
@tres:  cmp     #$F0
        bcs     @raro
        ; 1110xxxx 10yyyyyy 10zzzzzz -> xxxxyyyy yyzzzzzz
        asl
        asl
        asl
        asl
        sta     bk_ant
        ldy     #0
        lda     (bp),y
        jsr     avanza
        pha
        lsr
        lsr
        and     #$0F
        ora     bk_ant
        sta     bk_ant
        pla
        and     #$03
        jsr     bajo_6
        jmp     @pon
@raro:  lda     #$FF                    ; 4 bytes o mal formado: un carácter que no coincide con nada
        sta     bk_ant
        lda     #$FD
        jmp     @pon2
@ascii: ldx     #0
        stx     bk_ant
@pon2:  sta     lfn_lo
        jmp     @pon3
@pon:   sta     lfn_lo
@pon3:  lda     pt_len
        cmp     #255
        bcs     @c
        asl                             ; pt_nom + 2 x pt_len
        sta     ptr
        lda     #0
        rol
        sta     ptr+1
        clc
        lda     ptr
        adc     #<pt_nom
        sta     ptr
        lda     ptr+1
        adc     #>pt_nom
        sta     ptr+1
        ldy     #0
        lda     lfn_lo
        sta     (ptr),y
        iny
        lda     bk_ant
        sta     (ptr),y
        inc     pt_len
        jmp     @c

; A = 2 bits altos del byte bajo; el siguiente byte (10zzzzzz) da los 6 bajos. Devuelve el byte bajo.
bajo_6: asl
        asl
        asl
        asl
        asl
        asl
        sta     lfn_lo
        ldy     #0
        lda     (bp),y
        jsr     avanza
        and     #$3F
        ora     lfn_lo
        rts

avanza: inc     bp
        bne     :+
        inc     bp+1
:       rts

; Z = 1 si el nombre 8.3 de dir_ent («NOMBRE.EXT») es pt_nom, sin distinguir mayúsculas.
igual_83:
        ldx     #0                      ; carácter de pt_nom
        ldy     #0
@n:     lda     (dir_ent),y
        cmp     #' '
        beq     @ext
        jsr     igual_car
        bne     @no
        iny
        cpy     #8
        bne     @n
@ext:   ldy     #8
        lda     (dir_ent),y
        cmp     #' '
        beq     @fin
        lda     #'.'
        jsr     igual_car
        bne     @no
@e:     lda     (dir_ent),y
        cmp     #' '
        beq     @fin
        jsr     igual_car
        bne     @no
        iny
        cpy     #11
        bne     @e
@fin:   cpx     pt_len
        rts
@no:    lda     #1
        rts

; Z = 1 si el carácter X de pt_nom es A (mayúsculas ASCII). X avanza. Conserva Y.
igual_car:
        sta     bk_ant
        cpx     pt_len
        bcs     @no
        txa
        asl
        sty     lfn_lo
        tay
        lda     pt_nom+1,y
        bne     @no2
        lda     pt_nom,y
        ldy     lfn_lo
        cmp     #'a'
        bcc     :+
        cmp     #'z' + 1
        bcs     :+
        and     #$DF
:       inx
        cmp     bk_ant
        rts
@no2:   ldy     lfn_lo
@no:    lda     #1
        rts

; ------------------------------------------------------------------------------------------------ pantalla
pantalla:
        lda     #0
        sta     mando_on
        sta     PPUMASK
        lda     #$80
        sta     PPUCTRL
        jsr     leer_lista
        ldx     #7                      ; filas 7-27 en blanco
@borra: txa
        pha
        jsr     fila_ppu_x
        ldx     #32
        lda     #' '
@b:     sta     PPUDATA
        dex
        bne     @b
        pla
        tax
        inx
        cpx     #28
        bne     @borra
        ; título: «Modo banco  i/n»
        jsr     texto_blanco
        ldy     #0
        lda     #<t_banco
        sta     src
        lda     #>t_banco
        sta     src+1
        jsr     copia_src
        lda     bk_i
        clc
        adc     #1
        sta     w16
        lda     bk_i+1
        adc     #0
        sta     w16+1
        jsr     dec16_grande
        lda     #'/'
        sta     (dst),y
        iny
        lda     bk_n
        sta     w16
        lda     bk_n+1
        sta     w16+1
        jsr     dec16_grande
        lda     bk_ram_on               ; «  RAM=XX» con la directiva
        beq     @tit
        ldx     #0
@r:     lda     t_ram_tit,x
        beq     :+
        sta     (dst),y
        iny
        inx
        bne     @r
:       lda     bk_ram_val
        lsr
        lsr
        lsr
        lsr
        tax
        lda     cifras_hex,x
        sta     (dst),y
        iny
        lda     bk_ram_val
        and     #$0F
        tax
        lda     cifras_hex,x
        sta     (dst),y
@tit:   lda     #>FILA_TIT
        ldx     #<FILA_TIT
        jsr     texto_ppu
        lda     bk_hay
        bne     @hay
        jsr     texto_blanco            ; sin entrada: lista terminada
        ldy     #0
        lda     #<t_fin
        sta     src
        lda     #>t_fin
        sta     src+1
        jsr     copia_src
        lda     #>FILA_RUTA
        ldx     #<FILA_RUTA
        jsr     texto_ppu
        jmp     @codigo
@hay:   jsr     pintar_ruta
        jsr     texto_blanco            ; información (o que no está)
        jsr     resolver
        bcs     @falta
        jsr     texto_blanco
        jsr     info_de_ent
        jmp     @inf
@falta: ldy     #0
        lda     #<m_noarch
        sta     src
        lda     #>m_noarch
        sta     src+1
        jsr     copia_src
@inf:   lda     #>FILA_INF
        ldx     #<FILA_INF
        jsr     texto_ppu
@codigo:
        jsr     pintar_codigo
        lda     bk_err                  ; el motivo del último fallo
        beq     @ayuda
        tax
        lda     mensajes_lo-1,x
        sta     src
        lda     mensajes_hi-1,x
        sta     src+1
        jsr     texto_blanco
        ldy     #0
        jsr     copia_src
        lda     #>FILA_MSJ
        ldx     #<FILA_MSJ
        jsr     texto_ppu
@ayuda: lda     #>FILA_AYU
        ldx     #<FILA_AYU
        jsr     ppu_dir
        lda     #<t_ayuda
        sta     ptr
        lda     #>t_ayuda
        sta     ptr+1
        jsr     cadena
        ; pantalla encendida y el mando
        lda     nmis
@v:     cmp     nmis
        beq     @v
        bit     PPUSTATUS
        lda     #0
        sta     PPUADDR
        sta     PPUADDR
        sta     PPUSCROLL
        sta     PPUSCROLL
        lda     #%00001010
        sta     PPUMASK
        lda     #$FF
        sta     bk_ant                  ; lo que esté pulsado al encender no cuenta
        lda     #1
        sta     mando_on
@bucle: lda     nmis
@vb:    cmp     nmis
        beq     @vb
        lda     bk_ant
        eor     #$FF
        and     botones
        tax                             ; recién pulsados
        lda     botones
        sta     bk_ant
        cmp     #%00010000              ; Start solo
        bne     :+
        txa
        and     #%00010000
        beq     @bucle
        jmp     lanzar_i
:       cmp     #%01000000              ; B solo
        bne     :+
        txa
        and     #%01000000
        beq     @bucle
        jmp     al_menu
:       lda     botones
        and     #%00100000              ; con Select, nada (reset del kit Lava)
        bne     @bucle
        txa
        and     #%00000001
        bne     @der
        txa
        and     #%00000010
        bne     @izq
        jmp     @bucle
@der:   lda     bk_i                    ; siguiente (tras «terminada», la primera)
        cmp     bk_n
        bne     :+
        lda     bk_i+1
        cmp     bk_n+1
        bne     :+
        lda     #0
        sta     bk_i
        sta     bk_i+1
        jmp     @otra
:       inc     bk_i
        bne     @otra
        inc     bk_i+1
        jmp     @otra
@izq:   lda     bk_i                    ; anterior (desde la primera, «terminada»)
        ora     bk_i+1
        bne     :+
        lda     bk_n
        sta     bk_i
        lda     bk_n+1
        sta     bk_i+1
        jmp     @otra
:       lda     bk_i
        bne     :+
        dec     bk_i+1
:       dec     bk_i
@otra:  lda     #0
        sta     bk_err
        jsr     guardar_puesto
        jmp     pantalla

; Start: lanza la entrada (si la hay). Antes deja guardada la siguiente.
lanzar_i:
        lda     bk_hay
        bne     :+
        jmp     pantalla
:       lda     #0
        sta     mando_on
        sta     PPUMASK
        sta     PPUCTRL
        sta     bk_err
        inc     bk_i
        bne     :+
        inc     bk_i+1
:       jsr     guardar_puesto
        jsr     resolver
        bcc     @lanza
        lda     #M_NOARCH
        sta     bk_err
        jmp     pantalla
@lanza: lda     bk_ram_on               ; !ram=XX: la RAM a XX y sin partidas
        sta     l_sin_partida
        beq     :+
        jsr     llenar_ram
:       jsr     lanzar                  ; solo vuelve si falla
        lda     #0
        sta     l_sin_partida
        lda     l_error
        sta     bk_err
        jmp     pantalla

; B: al menú normal hasta el siguiente encendido (el OS vuelve a empezar sin la lista).
al_menu:
        lda     #1
        sta     bk_salir
        lda     #0
        sta     mando_on
        sta     PPUMASK
        sta     PPUCTRL
        ldx     #$FF
        txs
        jmp     principal

; ------------------------------------------------------------------------------------------------ ayudas de pantalla
; dst = bk_texto, en blanco.
texto_blanco:
        lda     #<bk_texto
        sta     dst
        lda     #>bk_texto
        sta     dst+1
        jmp     fila_blanca

; bk_texto -> PPU en A (alto) / X (bajo).
texto_ppu:
        jsr     ppu_dir
        ldy     #0
@c:     lda     bk_texto,y
        sta     PPUDATA
        iny
        cpy     #ANCHO
        bne     @c
        rts

; PPU en la fila X (columna 0).
fila_ppu_x:
        lda     #0
        sta     ptr+1
        txa
        asl
        asl
        asl
        asl
        rol     ptr+1
        asl
        rol     ptr+1
        tax
        lda     ptr+1
        ora     #>NT
        jmp     ppu_dir

; w16 (0-65535) en decimal en (dst) desde Y. dec16 de principal llega a 999: aquí, millares y decenas de millar.
dec16_grande:
        lda     #0
        sta     bk_primero              ; 1 = ya se ha escrito una cifra
        ldx     #1
@d:     lda     #'0'
        sta     bk_cuenta
@s:     lda     w16
        cmp     mil_lo,x
        lda     w16+1
        sbc     mil_hi,x
        bcc     @pon
        lda     w16
        sbc     mil_lo,x
        sta     w16
        lda     w16+1
        sbc     mil_hi,x
        sta     w16+1
        inc     bk_cuenta
        jmp     @s
@pon:   lda     bk_cuenta
        cmp     #'0'
        bne     @si
        lda     bk_primero
        beq     @sig
@si:    lda     bk_cuenta
        sta     (dst),y
        iny
        lda     #1
        sta     bk_primero
@sig:   dex
        bpl     @d
        lda     bk_primero              ; el resto (< 1000), con ceros si ya hay millares
        beq     @tres
        lda     w16+1
        bne     @tres
        lda     w16
        cmp     #100
        bcs     @tres
        lda     #'0'
        sta     (dst),y
        iny
        lda     w16
        cmp     #10
        bcs     @tres
        lda     #'0'
        sta     (dst),y
        iny
@tres:  jmp     dec16

; La ruta de bk_linea en 3 filas de 28 (UTF-8 -> fuente), con «…» si no cabe.
pintar_ruta:
        lda     #<bk_linea
        sta     bp
        lda     #>bk_linea
        sta     bp+1
        lda     #0
        sta     bk_cuenta               ; fila (0-2)
@fila:  jsr     texto_blanco
        ldx     #0
@car:   ldy     #0
        lda     (bp),y
        beq     @pinta
        cpx     #ANCHO
        bcs     @pinta
        txa
        pha
        jsr     car_utf8                ; A = código de la fuente
        sta     bk_ant
        pla
        tay
        lda     bk_ant
        sta     bk_texto,y
        iny
        tya
        tax
        jmp     @car
@pinta: lda     bk_cuenta               ; ¿última fila y queda texto? «…»
        cmp     #2
        bne     :+
        ldy     #0
        lda     (bp),y
        beq     :+
        lda     #C_PUNTOS
        sta     bk_texto + ANCHO - 1
:       lda     bk_cuenta
        asl
        asl
        asl
        asl
        asl                             ; x 32
        clc
        adc     #<FILA_RUTA
        tax
        lda     #>FILA_RUTA
        adc     #0
        jsr     texto_ppu
        inc     bk_cuenta
        lda     bk_cuenta
        cmp     #3
        bcs     @fin
        ldy     #0
        lda     (bp),y
        bne     @fila
@fin:   rts

; El carácter UTF-8 de (bp) (avanza) como código de la fuente.
car_utf8:
        ldy     #0
        lda     (bp),y
        jsr     avanza
        cmp     #$80
        bcc     @ya
        cmp     #$E0
        bcs     @largo
        cmp     #$C0
        bcc     @raro
        pha                             ; 2 bytes: Latin-1 y algo más
        lsr
        lsr
        and     #$07
        sta     bk_ant
        pla
        and     #$03
        jsr     bajo_6
        sta     lfn_lo
        lda     bk_ant
        jmp     ucs_a_fuente
@largo: ldy     #0                      ; 3 o 4 bytes: saltar las continuaciones
@s:     lda     (bp),y
        and     #$C0
        cmp     #$80
        bne     @raro
        jsr     avanza
        jmp     @s
@raro:  lda     #'?'
@ya:    rts

; Las dos filas del código: bloque, los 16 bits de bk_i (o de su complemento), bloque.
pintar_codigo:
        lda     #>FILA_COD
        ldx     #<FILA_COD
        jsr     ppu_dir
        lda     bk_i
        sta     w16
        lda     bk_i+1
        sta     w16+1
        jsr     @fila
        lda     #>(FILA_COD + 32)
        ldx     #<(FILA_COD + 32)
        jsr     ppu_dir
        lda     bk_i
        eor     #$FF
        sta     w16
        lda     bk_i+1
        eor     #$FF
        sta     w16+1
@fila:  lda     #C_BLOQUE
        sta     PPUDATA
        ldx     #16
@b:     asl     w16
        rol     w16+1
        lda     #' '
        bcc     :+
        lda     #C_BLOQUE
:       sta     PPUDATA
        dex
        bne     @b
        lda     #C_BLOQUE
        sta     PPUDATA
        rts

        .segment "RODATA"
firma_bk:   .byte "N8BK"
n_banco:    .byte "BANCO   TXT"
t_banco:    .byte "Modo banco  ", 0
t_fin:      .byte "Lista terminada", 0
t_ayuda:    .byte "Start lanzar ", C_IZQ, C_CURSOR, " otra B men", C_u, 0
m_noarch:   .byte "No encuentro el archivo", 0
t_ram_dir:  .byte "!ram="
t_ram_tit:  .byte "  RAM=", 0
cifras_hex: .byte "0123456789ABCDEF"
mil_lo:     .byte <1000, <10000
mil_hi:     .byte >1000, >10000
