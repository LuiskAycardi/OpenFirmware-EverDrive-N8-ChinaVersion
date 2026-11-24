; boton.s — programa del disco de prueba del cambio de cara a mano (FDS en el N8). GPL-3.0-or-later, código propio.
;
; Lo carga la BIOS en $6000 (ver hacer_disco.py). Cada fotograma lee el mando 1 y enseña, con una fuente propia:
;   C  la cara que tiene puesta la FPGA ($4212)
;   N  la cuenta del botón de la FPGA ($4217: fotogramas seguidos con B + Select; 45 = ya dio la vuelta)
;   M  cómo se lee el mando: 0 = el programa lee $4016 él mismo (prueba el espía de la FPGA), 1 = con ReadPads de la
;      BIOS ($E9EB; prueba el aviso del parche). A cambia de modo.
;   P  el mando tal como se leyó (A = bit 7 ... derecha = bit 0)
; Las dos caras del disco tienen el mismo ID: solo B + Select mantenidos ~0,75 s cambian C.

        .setcpu "6502"

PPUCTRL   = $2000
PPUMASK   = $2001
PPUSTATUS = $2002
PPUSCROLL = $2005
PPUADDR   = $2006
PPUDATA   = $2007
MANDO1    = $4016
CARA      = $4212               ; registros del mapper FDS del N8 (hdl/rtl/mapper_fds.v)
BOTON     = $4217
READPADS  = $E9EB               ; BIOS: lee los mandos en $F5 (mando 1) y $00 (expansión)
PAD_BIOS  = $F5
BLANCO    = $10                 ; tile vacío
T_C       = $11
T_N       = $12
T_M       = $13
T_P       = $14

pad       = $10                 ; página cero propia (la BIOS usa $F5-$FF y $00-$0F al leer el mando)
ant       = $11
modo      = $12

        .segment "CODIGO"
reset:  sei
        cld
        ldx     #$FF
        txs
        lda     #0
        sta     PPUCTRL
        sta     PPUMASK
        sta     modo
        sta     ant
        jsr     vblank
        jsr     vblank
        ; ---- fuente: 16 cifras, un tile vacío y C N M P (solo el plano 0)
        lda     #0
        sta     PPUADDR
        sta     PPUADDR
        ldx     #0
@g:     ldy     #8
@p0:    lda     fuente,x
        sta     PPUDATA
        inx
        dey
        bne     @p0
        ldy     #8
        lda     #0
@p1:    sta     PPUDATA
        dey
        bne     @p1
        cpx     #21 * 8
        bne     @g
        ; ---- pantalla vacía, paleta y rótulos
        lda     #$20
        sta     PPUADDR
        lda     #$00
        sta     PPUADDR
        ldx     #4
        ldy     #0
        lda     #BLANCO
@nt:    sta     PPUDATA                 ; 1 KiB: tiles y atributos (los atributos dan igual: paleta 0 entera)
        iny
        bne     @nt
        dex
        bne     @nt
        lda     #$3F
        sta     PPUADDR
        lda     #$00
        sta     PPUADDR
        ldx     #0
@pal:   txa                             ; las 4 paletas del fondo, iguales (los atributos quedan a $10)
        and     #$03
        tay
        lda     paleta,y
        sta     PPUDATA
        inx
        cpx     #16
        bne     @pal
        ldx     #0
@rot:   lda     rotulos,x               ; dirección (alto, bajo) y tile
        beq     @bucle
        sta     PPUADDR
        lda     rotulos+1,x
        sta     PPUADDR
        lda     rotulos+2,x
        sta     PPUDATA
        inx
        inx
        inx
        bne     @rot
        ; ---- bucle: un fotograma por vuelta
@bucle: jsr     leer_mando
        lda     pad                     ; A (al pulsarla) cambia de modo
        and     #$80
        beq     @sin_a
        lda     ant
        and     #$80
        bne     @sin_a
        lda     modo
        eor     #1
        sta     modo
@sin_a: lda     pad
        sta     ant
        jsr     vblank
        lda     #$21                    ; C: fila 10, columna 12
        sta     PPUADDR
        lda     #$4C
        sta     PPUADDR
        lda     CARA
        and     #$07
        sta     PPUDATA
        lda     #$21                    ; N: fila 12
        sta     PPUADDR
        lda     #$8C
        sta     PPUADDR
        lda     BOTON
        jsr     hex
        lda     #$21                    ; M: fila 14
        sta     PPUADDR
        lda     #$CC
        sta     PPUADDR
        lda     modo
        sta     PPUDATA
        lda     #$22                    ; P: fila 16
        sta     PPUADDR
        lda     #$0C
        sta     PPUADDR
        lda     pad
        jsr     hex
        lda     #0
        sta     PPUSCROLL
        sta     PPUSCROLL
        sta     PPUCTRL
        lda     #$0A                    ; fondo visible, también en la columna izquierda
        sta     PPUMASK
        jmp     @bucle

; A en dos cifras hexadecimales en PPUDATA.
hex:    pha
        lsr
        lsr
        lsr
        lsr
        sta     PPUDATA
        pla
        and     #$0F
        sta     PPUDATA
        rts

; El mando 1 en `pad`: modo 0, leyendo $4016 (D0 y D1: el mando de expansión de la Famicom); modo 1, ReadPads.
leer_mando:
        lda     modo
        bne     @bios
        lda     #1
        sta     MANDO1
        lda     #0
        sta     MANDO1
        ldx     #8
@b:     lda     MANDO1
        and     #$03
        cmp     #$01                    ; acarreo = pulsado
        rol     pad
        dex
        bne     @b
        rts
@bios:  jsr     READPADS
        lda     PAD_BIOS
        ora     $00
        sta     pad
        rts

vblank: bit     PPUSTATUS
@v:     bit     PPUSTATUS
        bpl     @v
        rts

nmi:
irq:    rti

paleta:  .byte $0F, $30, $30, $30
rotulos: .byte $21, $4A, T_C,  $21, $8A, T_N,  $21, $CA, T_M,  $22, $0A, T_P,  0

; Fuente propia: 0-F, vacío, C, N, M, P (8 filas por tile, bit 7 a la izquierda).
fuente:
        .byte $3C,$66,$6E,$76,$66,$66,$3C,$00   ; 0
        .byte $18,$38,$18,$18,$18,$18,$7E,$00   ; 1
        .byte $3C,$66,$06,$1C,$30,$60,$7E,$00   ; 2
        .byte $3C,$66,$06,$1C,$06,$66,$3C,$00   ; 3
        .byte $0C,$1C,$3C,$6C,$7E,$0C,$0C,$00   ; 4
        .byte $7E,$60,$7C,$06,$06,$66,$3C,$00   ; 5
        .byte $1C,$30,$60,$7C,$66,$66,$3C,$00   ; 6
        .byte $7E,$06,$0C,$18,$30,$30,$30,$00   ; 7
        .byte $3C,$66,$66,$3C,$66,$66,$3C,$00   ; 8
        .byte $3C,$66,$66,$3E,$06,$0C,$38,$00   ; 9
        .byte $18,$3C,$66,$66,$7E,$66,$66,$00   ; A
        .byte $7C,$66,$66,$7C,$66,$66,$7C,$00   ; B
        .byte $3C,$66,$60,$60,$60,$66,$3C,$00   ; C
        .byte $78,$6C,$66,$66,$66,$6C,$78,$00   ; D
        .byte $7E,$60,$60,$7C,$60,$60,$7E,$00   ; E
        .byte $7E,$60,$60,$7C,$60,$60,$60,$00   ; F
        .byte $00,$00,$00,$00,$00,$00,$00,$00   ; vacío
        .byte $3C,$66,$60,$60,$60,$66,$3C,$00   ; C
        .byte $66,$76,$7E,$7E,$6E,$66,$66,$00   ; N
        .byte $63,$77,$7F,$6B,$63,$63,$63,$00   ; M
        .byte $7C,$66,$66,$7C,$60,$60,$60,$00   ; P

        .segment "VECTORES"
        .word   nmi, nmi, nmi, reset, irq       ; $DFF6: NMI 1-3, RESET, IRQ (los de los juegos del FDS)
