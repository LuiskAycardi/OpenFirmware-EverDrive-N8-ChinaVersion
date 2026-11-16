; hola.s — OS propio del EverDrive N8 clon, etapa 1: «hola mundo» y medidas.
; GPL-3.0-or-later. Requisitos del arranque en docs/bios-n8-clon.md §3.
;
; Qué hace:
;  - guarda los registros de la CPU tal como los deja la BIOS y lee (sin escribir nada en ellos) los registros
;    2, 9, 10, 138, 139 y 140 por $4401, y el estado de $4403;
;  - cuenta los arranques en una variable dentro de su propia imagen: la BIOS la vuelve a poner a 0 cada vez que
;    copia el OS.BIN, así que 01 = arranque desde la BIOS y 02 o más = reset que no pasó por la BIOS;
;  - pinta todo con una fuente propia y muestra en vivo el mando, los registros 2, 9 y 138, $4403 y un contador
;    de fotogramas.
; Solo escribe en: RAM de la CPU, su propia imagen en $8000-$FFFF (PRG-RAM), la PPU, el reg 130 del FPGA (banco de
; la CHR en modo OS, como el v13) y el número de registro de $4400. No escribe ningún registro del CPLD.

        .setcpu "6502"

PPUCTRL   = $2000
PPUMASK   = $2001
PPUSTATUS = $2002
PPUSCROLL = $2005
PPUADDR   = $2006
PPUDATA   = $2007
APU_DMC   = $4010
APU_EST   = $4015
MANDO1    = $4016
APU_CONT  = $4017
REG_SEL   = $4400
REG_DAT   = $4401
CPLD_EST  = $4403
REG_CHR   = 130                 ; FPGA, modo OS: banco de la CHR visible en $0000-$1FFF de la PPU

; ------------------------------------------------------------------------------------------------ variables
        .segment "ZEROPAGE"
ptr:        .res 2
botones:    .res 1
fotogramas: .res 2
vivo:       .res 4              ; reg 2, reg 9, reg 138, $4403 en el fotograma actual
tmp:        .res 1
nmis:       .res 1              ; lo incrementa la NMI: un fotograma = una NMI

; En la propia imagen (PRG-RAM): no se borra al arrancar; la BIOS la recarga a 0 en cada arranque completo.
        .segment "ESTADO"
arranques:  .res 1
e_a:        .res 1
e_x:        .res 1
e_y:        .res 1
e_s:        .res 1
e_p:        .res 1
e_regs:     .res 6              ; regs 2, 9, 10, 138, 139, 140 al entrar
e_4403:     .res 1

; ------------------------------------------------------------------------------------------------ código
        .segment "CODE"

; Entrada desde la BIOS (salta a $8000) y desde el vector RESET que instalamos en la RAM.
; El primer byte tiene que ser distinto de $EA (docs/bios-n8-clon.md §4): SEI = $78.
reset:
        sei
        sta     e_a
        stx     e_x
        sty     e_y
        php
        pla
        sta     e_p
        tsx
        stx     e_s
        cld
        ldx     #$FF
        txs
        inc     arranques

        ldx     #0
@regs:  lda     regs_medidos,x
        sta     REG_SEL
        lda     REG_DAT
        sta     e_regs,x
        inx
        cpx     #6
        bne     @regs
        lda     CPLD_EST
        sta     e_4403

        ; vectores propios en la RAM (la BIOS dejó los suyos en $FFFA-$FFFF)
        lda     #<nmi
        sta     $FFFA
        lda     #>nmi
        sta     $FFFB
        lda     #<reset
        sta     $FFFC
        lda     #>reset
        sta     $FFFD
        lda     #<nada
        sta     $FFFE
        lda     #>nada
        sta     $FFFF

        lda     #0
        sta     PPUCTRL
        sta     PPUMASK
        sta     APU_DMC
        sta     APU_EST
        lda     #$40
        sta     APU_CONT

        ; borrar la RAM de la CPU (la pila está vacía: S = $FF y no hemos llamado a nada)
        lda     #0
        tax
@ram:   sta     $0000,x
        sta     $0100,x
        sta     $0200,x
        sta     $0300,x
        sta     $0400,x
        sta     $0500,x
        sta     $0600,x
        sta     $0700,x
        inx
        bne     @ram

        bit     PPUSTATUS
@vb1:   bit     PPUSTATUS
        bpl     @vb1
@vb2:   bit     PPUSTATUS
        bpl     @vb2

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
        jsr     valores_fijos

@vb3:   bit     PPUSTATUS
        bpl     @vb3
        jsr     sin_scroll                  ; activa la NMI
        lda     #%00001010              ; fondo visible, también en la columna izquierda
        sta     PPUMASK

; Un paso por fotograma, sincronizado con la NMI: leer $2002 en un bucle pierde algún VBlank, y el kit Lava
; necesita ver Select+B en todos los fotogramas seguidos (comprobado en la NES: con la espera por $2002 no
; reseteaba).
bucle:
        lda     nmis
@vb:    cmp     nmis
        beq     @vb
        jsr     valores_vivos
        jsr     sin_scroll
        inc     fotogramas
        bne     @sin_acarreo
        inc     fotogramas+1
@sin_acarreo:
        jsr     leer_mando
        jsr     medir_vivos
        jmp     bucle

nmi:    inc     nmis
nada:   rti

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

; Escribe A en hexadecimal en PPUDATA.
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

subir_fuente:
        lda     #$02                    ; tile $20 = $0200 del patrón 0
        ldx     #$00
        jsr     ppu_dir
        lda     #<fuente
        sta     ptr
        lda     #>fuente
        sta     ptr+1
        ldx     #4                      ; 4 x 256 = 1024 bytes (64 tiles)
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

valores_fijos:
        lda     #>(FILA_ARR + 13)
        ldx     #<(FILA_ARR + 13)
        jsr     ppu_dir
        lda     arranques
        jsr     hex

        lda     #>(FILA_CPU + 2)
        ldx     #<(FILA_CPU + 2)
        jsr     ppu_dir
        ldx     #0
@c:     lda     e_a,x                   ; e_a, e_x, e_y, e_s, e_p seguidos
        stx     tmp
        jsr     hex
        jsr     espacio
        ldx     tmp
        inx
        cpx     #5
        bne     @c

        lda     #>(FILA_REG1 + 2)
        ldx     #<(FILA_REG1 + 2)
        jsr     ppu_dir
        ldx     #0
@r1:    lda     e_regs,x
        stx     tmp
        jsr     hex
        jsr     espacio
        jsr     espacio
        jsr     espacio
        ldx     tmp
        inx
        cpx     #3
        bne     @r1

        lda     #>(FILA_REG2 + 2)
        ldx     #<(FILA_REG2 + 2)
        jsr     ppu_dir
        ldx     #3
@r2:    lda     e_regs,x
        stx     tmp
        jsr     hex
        jsr     espacio
        jsr     espacio
        jsr     espacio
        ldx     tmp
        inx
        cpx     #6
        bne     @r2
        lda     e_4403
        jsr     hex
        rts

medir_vivos:
        lda     #2
        sta     REG_SEL
        lda     REG_DAT
        sta     vivo
        lda     #9
        sta     REG_SEL
        lda     REG_DAT
        sta     vivo+1
        lda     #138
        sta     REG_SEL
        lda     REG_DAT
        sta     vivo+2
        lda     CPLD_EST
        sta     vivo+3
        rts

valores_vivos:
        lda     #>(FILA_VIVO + 2)
        ldx     #<(FILA_VIVO + 2)
        jsr     ppu_dir
        ldx     #0
@v:     lda     vivo,x
        stx     tmp
        jsr     hex
        jsr     espacio
        jsr     espacio
        jsr     espacio
        ldx     tmp
        inx
        cpx     #4
        bne     @v

        lda     #>(FILA_MANDO + 9)
        ldx     #<(FILA_MANDO + 9)
        jsr     ppu_dir
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

        lda     #>(FILA_FOTO + 14)
        ldx     #<(FILA_FOTO + 14)
        jsr     ppu_dir
        lda     fotogramas+1
        jsr     hex
        lda     fotogramas
        jsr     hex
        rts

leer_mando:
        lda     #1
        sta     MANDO1
        lda     #0
        sta     MANDO1
        ldx     #8
@b:     lda     MANDO1
        lsr                             ; bit 0 -> acarreo
        rol     botones                 ; A primero: queda en el bit 7
        dex
        bne     @b
        rts

; ------------------------------------------------------------------------------------------------ datos
        .segment "RODATA"

NT = $2000
FILA_TIT   = NT + 3 * 32
FILA_ARR   = NT + 6 * 32
FILA_CPU   = NT + 10 * 32
FILA_REG1  = NT + 13 * 32
FILA_REG2  = NT + 16 * 32
FILA_VIVO  = NT + 19 * 32
FILA_MANDO = NT + 21 * 32
FILA_FOTO  = NT + 22 * 32

.macro texto dir, cadena
        .byte   >(dir), <(dir)
        .byte   cadena, 0
.endmacro

textos:
        texto   FILA_TIT + 2,      "OS PROPIO N8 - HOLA MUNDO"
        texto   FILA_TIT + 32 + 2, "ETAPA 1    GPL-3.0-OR-LATER"
        texto   FILA_ARR + 2,      "ARRANQUES:"
        texto   FILA_ARR + 32 + 2, "01 = DESDE LA BIOS"
        texto   FILA_CPU - 32 + 2, "A  X  Y  S  P  (AL ENTRAR)"
        texto   FILA_REG1 - 32 + 2, "REG2 REG9 R10  (AL ENTRAR)"
        texto   FILA_REG2 - 32 + 2, "R138 R139 R140 4403"
        texto   FILA_VIVO - 32 + 2, "REG2 REG9 R138 4403  (AHORA)"
        texto   FILA_MANDO + 2,    "MANDO:"
        texto   FILA_FOTO + 2,     "FOTOGRAMAS:"
        texto   NT + 24 * 32 + 2,  "SELECT+B: PROBAR EL RESET"
        texto   NT + 25 * 32 + 2,  "VOLVER AL OS DE FABRICA:"
        texto   NT + 26 * 32 + 2,  "COPIA OS_V13.BIN COMO OS.BIN"
        .byte   $FF

regs_medidos:
        .byte   2, 9, 10, 138, 139, 140
cifras:
        .byte   "0123456789ABCDEF"
letras_mando:
        .byte   "ABSTUDLR"              ; A, B, Select, sTart, arriba (Up), abajo (Down), izquierda (Left), derecha (Right)
colores:
        .byte   $0F, $30, $10, $00,  $0F, $30, $10, $00,  $0F, $30, $10, $00,  $0F, $30, $10, $00
        .byte   $0F, $30, $10, $00,  $0F, $30, $10, $00,  $0F, $30, $10, $00,  $0F, $30, $10, $00
fuente:
        .incbin "fuente.chr"

; ------------------------------------------------------------------------------------------------ vectores
; La BIOS los pisa con los suyos al copiar su página $FC00; los de verdad se instalan en reset.
        .segment "VECTORS"
        .word   nmi, reset, nada
