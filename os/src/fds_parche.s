; fds_parche.s — Rutinas de disco que sustituyen a las de la BIOS FDS del usuario (etapa F2, docs/fds-diseno.md).
; GPL-3.0-or-later, código propio. Corre en $5000-$5FFF (SRAM PRG 0x7D000, ver hdl/rtl/mapper_fds.v): el OS copia
; este bloque allí, escribe en $5FFF el número de caras del disco y aplica la tabla `enganches` a su copia de la
; BIOS (en 0x7E000). En el repositorio no hay ningún byte de la BIOS: solo las direcciones donde se engancha.
;
; Por qué: en el N8 la FPGA no puede servir el disco byte a byte por $4031 (A0-A9 de la SRAM vienen del bus de la
; consola). El disco está en la SRAM PRG y se ve por una ventana de 1 KB ($4800-$4BFF) en el banco de la «cabeza»,
; cuya posición guarda la FPGA ($4213/$4214; $4215 la avanza). Estas rutinas no tocan la RAM del juego ni la
; página cero salvo $FA, $F9 (copias de $4025 y $4026 que la propia BIOS mantiene) y $0101, igual que la BIOS; para
; guardar un byte usan $4216, un registro de la FPGA.
;
; Enganches (direcciones de la Rev 1; iguales en la Rev 0 y en la Twin Famicom, comprobado byte a byte):
;   $E7A3  pasar un byte          -> xfer      (la BIOS espera la IRQ del disco y lee $4031)
;   $E794  empezar un bloque      -> inicio    (lectura: devuelve el tipo de bloque; escritura: no guarda la marca $80)
;   $E706  fin de bloque (leer)   -> fin       (el .fds no lleva CRC: no se consume nada; tampoco se leen $4030 y
;   $E729  fin de bloque (escr.)  -> fin        $4032, que en el N8 de NES no llegan a la CPU)
;   $E57A  fin de un archivo que se salta: la BIOS lee ella misma los 2 bytes de CRC y va a $E74C -> fin
;   $E64D  motor y disco listo    -> arranque  (cabeza al principio de la cara; sin mirar la pila en $4033)
;   $E4D4  esperar a que las IRQ del disco se salten $0101 bytes (el nombre del archivo, mientras la CPU compara
;          el ID)                 -> saltar    (avanza la cabeza esos bytes de golpe)
;   JSR $E445 en $E21A, $E26B, $E290, $E2AB y $E2F7 (comprobar la cabecera del disco) -> buscar_cara, que elige la
;          cara cuyo ID coincide con el que pide el juego y luego salta a $E445: cambio de cara automático.

        .setcpu "6502"

VENTANA   = $4800               ; 1 KB del banco de la cabeza
VENT_ON   = $4210               ; D0 = ventana activa
CARA      = $4212
CAB_LO    = $4213
CAB_HI    = $4214
AVANZA    = $4215
APOYO     = $4216
FILTRO    = $4217               ; filtro de las lecturas de $403x (ver hdl/rtl/mapper_fds.v)
REG_4025  = $4025
REG_4026  = $4026
COPIA4025 = $FA                 ; la BIOS guarda aquí lo último escrito en $4025 (D2 = 1: lectura)
COPIA4026 = $F9
MODO_IRQ  = $0101               ; la BIOS: $40 = la próxima IRQ es del disco
CARAS     = $5FFF               ; lo escribe el OS
ID_BIOS   = $00                 ; puntero al ID que pide el juego (lo deja la BIOS antes de $E445)
COMPROBAR = $E445               ; comprobar la cabecera (de la BIOS)

        .segment "PARCHE"
cabecera:
        .byte   "N8FDS", 1                  ; firma y versión del bloque
        .word   enganches                   ; tabla para el OS

; ------------------------------------------------------------------ xfer (en lugar de $E7A3)
; Entrada: A = byte a escribir (modo escritura). Salida: A = X = el byte (leído o escrito); Y y el acarreo, como
; estaban; I = 1 (la BIOS sale de su IRQ sin RTI, así que también deja las interrupciones cerradas).
; Cada byte pasa por el filtro de $4217: al leer, las lecturas de $4030/$4032/$4033 del juego pasan a $42xx (que sí
; llegan a la CPU en la NES); al escribir, se deshace el cambio para que el disco quede como era.
xfer:   php
        sta     APOYO
        ldx     CAB_LO
        lda     COPIA4025
        and     #$04
        bne     @lee
        lda     APOYO                       ; escritura: lo que va al disco, sin el cambio
        sta     FILTRO
        lda     CAB_HI
        and     #$03                        ; página de 256 bytes dentro del KB de la ventana
        beq     @e0
        cmp     #$01
        beq     @e1
        cmp     #$02
        beq     @e2
        lda     FILTRO
        sta     VENTANA + $300,x
        jmp     @esc
@e2:    lda     FILTRO
        sta     VENTANA + $200,x
        jmp     @esc
@e1:    lda     FILTRO
        sta     VENTANA + $100,x
        jmp     @esc
@e0:    lda     FILTRO
        sta     VENTANA,x
@esc:   lda     APOYO
        jmp     @fin
@lee:   lda     CAB_HI
        and     #$03
        beq     @p0
        cmp     #$01
        beq     @p1
        cmp     #$02
        beq     @p2
        lda     VENTANA + $300,x
        jmp     @fil
@p2:    lda     VENTANA + $200,x
        jmp     @fil
@p1:    lda     VENTANA + $100,x
        jmp     @fil
@p0:    lda     VENTANA,x
@fil:   sta     FILTRO
        lda     FILTRO
@fin:   sta     AVANZA                      ; la cabeza avanza (el valor da igual)
        sta     APOYO
        ; sigue en residuo

; ------------------------------------------------------------------ residuo (final común de xfer e inicio)
; Entrada: P del que llama apilado (php) y APOYO = el byte que se devuelve. La BIOS pasa cada byte esperando la IRQ
; del disco en $E7A4 (CLI y JMP *), así que la IRQ deja debajo de la pila $E7, $A4 y P (con I = 0 y B = 0), que su
; manejador desapila sin borrarlos. Hay juegos que usan esos restos como protección (Quick Hunter salta a una
; dirección sacada de $01F0): se dejan los mismos tres bytes en los mismos sitios. Sale con A = X = el byte, el
; acarreo como estaba e I = 1.
residuo:
        tsx                                 ; X = s - 1 (s: la cima de la pila al entrar)
        lda     $0101,x                     ; P del que llama
        and     #$EB                        ; B = 0, I = 0
        ora     #$20
        sta     a:$00FF,x                   ; s - 2: P
        lda     #$A4
        sta     $0100,x                     ; s - 1: byte bajo de la vuelta ($E7A4)
        plp
        lda     #$E7
        sta     $0101,x                     ; s: byte alto
        sei
        lda     APOYO
        tax
        rts

; ------------------------------------------------------------------ inicio (en lugar de $E794)
; Lo mismo que hace la BIOS al empezar un bloque ($0101 = $40, $4025 D7 = 1, y los flags que deja: N = 1 por
; cargar $4025 en X) y luego: en lectura, el primer byte del bloque (su tipo); en escritura, nada (la marca $80
; que trae A no va en el .fds), pero con los restos en la pila de la IRQ que la BIOS esperaba.
inicio: ldx     #$40
        stx     MODO_IRQ
        rol     COPIA4025
        sec
        ror     COPIA4025                   ; D7 = 1, el resto igual
        ldx     COPIA4025
        stx     REG_4025
        php                                 ; los flags de la BIOS en $E7A3
        pha
        txa
        and     #$04
        bne     @lee
        pla
        sta     APOYO
        jmp     residuo                     ; escritura (el P de la BIOS sigue apilado)
@lee:   pla
        plp
        jmp     xfer

; ------------------------------------------------------------------ fin (en lugar de $E706 y $E729)
; Deja $4025 como la BIOS al acabar un bloque (lectura, transferencia parada) sin leer CRC ni estado. La BIOS
; espera aquí los 2 bytes de CRC (un nivel de pila más abajo; el segundo con N = 1 tras poner $4025 D4): se dejan
; sus restos en la pila con crc.
fin:    jsr     crc
        lda     COPIA4025
        ora     #$10
        sta     COPIA4025
        sta     REG_4025
        jsr     crc
        lda     COPIA4025
        and     #$2F
        ora     #$04
        sta     COPIA4025
        sta     REG_4025
        clc
        rts

crc:    php
        jmp     residuo

; ------------------------------------------------------------------ arranque (en lugar de $E64D)
; Motor en marcha y disco listo, como la BIOS ($4026 D7, $4025 = motor y lectura, conservando el mirroring), con la
; cabeza al principio de la cara y la ventana activa. Sin esperas ni comprobación de la pila.
arranque:
        lda     COPIA4026
        ora     #$80
        sta     COPIA4026
        sta     REG_4026
        lda     COPIA4025
        and     #$08
        ora     #$25
        sta     REG_4025                    ; motor en marcha
        and     #$FD
        sta     COPIA4025
        sta     REG_4025
        lda     #0
        sta     CAB_LO
        sta     CAB_HI
        lda     #1
        sta     VENT_ON
        clc
        rts

; ------------------------------------------------------------------ saltar (en lugar de la espera de $E4D4)
; La BIOS pone en $0101 cuántos bytes deben saltarse las IRQ del disco y espera a que llegue a 0. Aquí no hay IRQ
; del disco: la cabeza avanza esos bytes ya. Sale como la espera: A = 0, Z = 1, X intacto.
saltar: txa
        pha
        ldx     MODO_IRQ
        beq     @ya
@paso:  sta     AVANZA
        dex
        bne     @paso
@ya:    stx     MODO_IRQ
        pla
        tax
        lda     #0
        rts

; ------------------------------------------------------------------ buscar_cara (antes de $E445)
; Busca, desde la cara 0, la primera cuyo ID (bytes 15-24 del bloque 1) coincide con los 10 bytes que pide el
; juego en (ID_BIOS),y ($FF = cualquiera, como en la BIOS). Si ninguna coincide, deja la cara que había: la BIOS
; dará su error de disco equivocado, como en la consola.
buscar_cara:
        lda     CARA
        pha
        lda     #1
        sta     VENT_ON
        lda     #0
@cara:  sta     CARA
        lda     #0
        sta     CAB_LO
        sta     CAB_HI
        ldy     #0
@byte:  lda     (ID_BIOS),y
        cmp     #$FF
        beq     @igual
        cmp     VENTANA + 15,y
        bne     @otra
@igual: iny
        cpy     #10
        bne     @byte
        pla                                 ; esta vale
        jmp     COMPROBAR
@otra:  ldx     CARA
        inx
        txa
        cmp     CARAS
        bcc     @cara
        pla                                 ; ninguna: la de antes
        sta     CARA
        jmp     COMPROBAR

; ------------------------------------------------------------------ tabla de enganches para el OS
; Por entrada: dirección en la BIOS, número de bytes y los bytes. Termina con la dirección 0.
enganches:
        .word   $E7A3
        .byte   3, $4C, <xfer, >xfer
        .word   $E794
        .byte   3, $4C, <inicio, >inicio
        .word   $E706
        .byte   3, $4C, <fin, >fin
        .word   $E729
        .byte   3, $4C, <fin, >fin
        .word   $E57A
        .byte   3, $4C, <fin, >fin
        .word   $E64D
        .byte   3, $4C, <arranque, >arranque
        .word   $E4D4
        .byte   3, $4C, <saltar, >saltar
        .word   $E21B                       ; operando de un JSR $E445
        .byte   2, <buscar_cara, >buscar_cara
        .word   $E26C                       ; operando de un JSR $E445
        .byte   2, <buscar_cara, >buscar_cara
        .word   $E291                       ; operando de un JSR $E445
        .byte   2, <buscar_cara, >buscar_cara
        .word   $E2AC                       ; operando de un JSR $E445
        .byte   2, <buscar_cara, >buscar_cara
        .word   $E2F8                       ; operando de un JSR $E445
        .byte   2, <buscar_cara, >buscar_cara
        .word   0
