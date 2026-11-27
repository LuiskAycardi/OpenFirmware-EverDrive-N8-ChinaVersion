; cal.s — ROM de calibración del volumen del sonido de expansión (GPL-3.0-or-later, código propio).
;
; En bucle: pulso 1 del APU (440 Hz, ciclo 50 %, volumen 15) durante 60 fotogramas, 30 de silencio, la misma nota en
; el chip de sonido del cartucho durante 120 fotogramas y 30 de silencio. Las duraciones distintas sirven para
; reconocer cada tramo en la grabación (medir.py). La pantalla queda negra.
;
; Se ensambla una vez por chip con -D CHIP=n (hacer.py):
;   1 FDS (programa de disco en $6000)  2 VRC6 (24)  3 Sunsoft 5B (69)  4 Namco 163 (19)  5 VRC7 (85)  6 MMC5 (5)
; Notas del chip, todas a ~440 Hz y a su volumen máximo:
;   VRC6  pulso 1, ciclo 8/16, volumen 15, periodo 253
;   5B    tono A, volumen 15, periodo 127 (CPU / 32 / 127)
;   N163  canal 7 solo (1 canal), onda de 16 muestras (8 x 15, 8 x 0), volumen 15
;   VRC7  instrumento propio: portadora seno (multiplicador 1), moduladora a TL 63, canal 0 a volumen máximo
;   MMC5  pulso 1, como el del APU
;   FDS   onda de 64 muestras (32 x 63, 32 x 0), ganancia 32, volumen general máximo
;
; CHIP=7 (PCM, mapper 5) es otra prueba: compara el canal PCM del MMC5 ($5011) con el DMC del APU ($4011). El tramo
; de 60 fotogramas es una onda cuadrada de ~440 Hz en $4011 y el de 120, la misma onda en $5011, las dos entre los
; niveles 1 y 65 (64 pasos; el PCM ignora el 0). Las ondas las hace la CPU con un bucle de retardo. Según NESdev el
; PCM suena «como el APU con la misma entrada»: la proporción PCM / DMC tendría que salir 1.

        .setcpu "6502"

PPUCTRL   = $2000
PPUMASK   = $2001
PPUSTATUS = $2002

FDS_C  = 1
VRC6_C = 2
S5B_C  = 3
N163_C = 4
VRC7_C = 5
MMC5_C = 6
PCM_C  = 7

.if CHIP = FDS_C
        .segment "CODIGO"
.else
        .segment "HDR"
        MAPPER .set 0
  .if CHIP = VRC6_C
        MAPPER .set 24
  .elseif CHIP = S5B_C
        MAPPER .set 69
  .elseif CHIP = N163_C
        MAPPER .set 19
  .elseif CHIP = VRC7_C
        MAPPER .set 85
  .elseif CHIP = MMC5_C || CHIP = PCM_C
        MAPPER .set 5
  .endif
        .byte   "NES", $1A, 2, 1, (MAPPER & $0F) << 4, MAPPER & $F0, 0, 0, 0, 0, 0, 0, 0, 0
        .segment "CODIGO"
.endif

.if CHIP = PCM_C
destino = $00                                   ; registro de la onda: $4011 (DMC) o $5011 (PCM)

reset:  sei
        cld
        ldx     #$FF
        txs
        lda     #0
        sta     PPUCTRL
        sta     PPUMASK
        jsr     vblank
        jsr     vblank
        lda     #$40                    ; APU: sin IRQ del contador de tramas
        sta     $4017
        lda     #$00                    ; canales del APU apagados ($4011 se carga igual)
        sta     $4015
        lda     #3                      ; MMC5: PRG de 8 KiB (el último banco, fijo, es este código)
        sta     $5100
        lda     #$00                    ; PCM en modo escritura, sin IRQ; pulsos del MMC5 apagados
        sta     $5010
        sta     $5015
        lda     #1
        sta     $4011
        sta     $5011
        lda     #$11
        sta     destino
bucle:  lda     #$40                    ; DMC
        sta     destino+1
        ldx     #60
        jsr     cuadrada
        ldx     #30
        jsr     esperar
        lda     #$50                    ; PCM del MMC5
        sta     destino+1
        ldx     #120
        jsr     cuadrada
        ldx     #30
        jsr     esperar
        jmp     bucle

; Onda cuadrada (niveles 65 y 1) en (destino) durante X fotogramas. Cada semiperiodo son ~2040 ciclos (~440 Hz) y
; al final de cada uno se mira el VBlank ($2002 bit 7, que dura ~2270 ciclos: no se pierde) y se lee el mando.
cuadrada:
        ldy     #0
        lda     #65
        sta     (destino),y
        jsr     medio
        cpx     #0
        beq     @fin
        ldy     #0
        lda     #1
        sta     (destino),y
        jsr     medio
        cpx     #0
        bne     cuadrada
@fin:   lda     #1                      ; deja el nivel bajo
        ldy     #0
        sta     (destino),y
        rts
medio:  ldy     #183                    ; 183 x 11 ciclos
@d:     nop
        nop
        nop
        dey
        bne     @d
        bit     PPUSTATUS
        bpl     @n
        jsr     mando
        dex
@n:     rts

mando:  lda     #1
        sta     $4016
        lda     #0
        sta     $4016
        ldy     #8
@m:     lda     $4016
        dey
        bne     @m
        rts
.else
reset:  sei
        cld
        ldx     #$FF
        txs
        lda     #0
        sta     PPUCTRL
        sta     PPUMASK
        jsr     vblank
        jsr     vblank
        lda     #$40                    ; APU: sin IRQ del contador de tramas
        sta     $4017
        lda     #$01                    ; solo el pulso 1
        sta     $4015
        lda     #$08                    ; barrido apagado
        sta     $4001
        jsr     chip_ini
bucle:  lda     #$BF                    ; APU: ciclo 50 %, contador parado, volumen fijo 15
        sta     $4000
        lda     #<253
        sta     $4002
        lda     #>253
        sta     $4003
        ldx     #60
        jsr     esperar
        lda     #$B0                    ; volumen 0
        sta     $4000
        ldx     #30
        jsr     esperar
        jsr     chip_on
        ldx     #120
        jsr     esperar
        jsr     chip_off
        ldx     #30
        jsr     esperar
        jmp     bucle
.endif

; Espera X fotogramas leyendo el mando en cada uno: sin lecturas del mando, el reset del kit Lava RGB (Select y luego
; Select+A) no ve los botones y no resetea (2026-11-24, en la Famicom).
esperar:
@f:     jsr     vblank
        lda     #1
        sta     $4016
        lda     #0
        sta     $4016
        ldy     #8
@m:     lda     $4016
        dey
        bne     @m
        dex
        bne     @f
        rts

vblank: bit     PPUSTATUS
@v:     bit     PPUSTATUS
        bpl     @v
        rts

nmi:
irq:    rti

; ------------------------------------------------------------------------------------------------ chips
.if CHIP = VRC6_C
chip_ini:
        lda     #0
        sta     $9003                   ; sin parar ni dividir la frecuencia
        rts
chip_on:
        lda     #$7F                    ; ciclo 8/16, volumen 15
        sta     $9000
        lda     #<253
        sta     $9001
        lda     #$80 | >253
        sta     $9002
        rts
chip_off:
        lda     #0
        sta     $9002
        rts

.elseif CHIP = S5B_C
r5b:    stx     $C000
        sta     $E000
        rts
chip_ini:
        ldx     #7
        lda     #$3E                    ; solo el tono A
        jsr     r5b
        ldx     #0
        lda     #127
        jsr     r5b
        ldx     #1
        lda     #0
        jmp     r5b
chip_on:
        ldx     #8
        lda     #$0F
        jmp     r5b
chip_off:
        ldx     #8
        lda     #0
        jmp     r5b

.elseif CHIP = N163_C
FREQ = 3867                             ; 440 x 15 x 65536 x 16 / 1789773
chip_ini:
        lda     #0                      ; $E000 D6 = 0: sonido encendido
        sta     $E000
        lda     #$80                    ; onda en la RAM de sonido, desde el nibble 0
        sta     $F800
        ldx     #0
@w:     lda     onda,x
        sta     $4800
        inx
        cpx     #8
        bne     @w
        lda     #$80 | $78              ; canal 7: $78-$7E
        sta     $F800
        ldx     #0
@r:     lda     canal,x
        sta     $4800
        inx
        cpx     #7
        bne     @r
        rts
chip_on:
        lda     #$7F
        sta     $F800
        lda     #$0F                    ; 1 canal, volumen 15
        sta     $4800
        rts
chip_off:
        lda     #$7F
        sta     $F800
        lda     #$00
        sta     $4800
        rts
onda:   .byte   $FF, $FF, $FF, $FF, $00, $00, $00, $00
canal:  .byte   <FREQ, 0, >FREQ, 0, $F0, 0, 0     ; frecuencia, fase, longitud 16 (256 - 16), dirección 0

.elseif CHIP = VRC7_C
rv7:    stx     $9010
        jsr     pausa
        sta     $9030
pausa:  ldy     #10                     ; ~50 ciclos entre escrituras (el chip pide 42)
@p:     dey
        bne     @p
        rts
chip_ini:
        lda     #0                      ; $E000 D6 = 0: sonido encendido
        sta     $E000
        ldx     #0
@i:     lda     inst,x
        jsr     rv7
        inx
        cpx     #8
        bne     @i
        ldx     #$10
        lda     #<290                   ; F-num 290, bloque 4: 49716 x 290 / 2^15 = 440 Hz
        jsr     rv7
        ldx     #$30
        lda     #$00                    ; instrumento 0 (el propio), volumen máximo
        jmp     rv7
chip_on:
        ldx     #$20
        lda     #$10 | (4 << 1) | (>290)
        jmp     rv7
chip_off:
        ldx     #$20
        lda     #(4 << 1) | (>290)
        jmp     rv7
inst:   .byte   $20, $21, $3F, $00, $F0, $F0, $0F, $0F

.elseif CHIP = MMC5_C
chip_ini:
        lda     #3
        sta     $5100
        lda     #$01
        sta     $5015
        rts
chip_on:
        lda     #$BF
        sta     $5000
        lda     #<253
        sta     $5002
        lda     #>253
        sta     $5003
        rts
chip_off:
        lda     #$B0
        sta     $5000
        rts

.elseif CHIP = FDS_C
FREQ = 1031                             ; 440 x 65536 x 64 / 1789773
chip_ini:
        lda     #$83                    ; disco y sonido activos
        sta     $4023
        lda     #$80                    ; escribir la onda, volumen general máximo
        sta     $4089
        ldx     #0
@w:     lda     #63
        cpx     #32
        bcc     @a
        lda     #0
@a:     sta     $4040,x
        inx
        cpx     #64
        bne     @w
        lda     #$00
        sta     $4089
        lda     #$80                    ; envolvente de la modulación parada; modulación apagada
        sta     $4084
        sta     $4087
        lda     #$80                    ; ganancia 0 (silencio)
        sta     $4080
        lda     #<FREQ
        sta     $4082
        lda     #>FREQ
        sta     $4083
        rts
chip_on:
        lda     #$80 | 32               ; ganancia directa 32
        sta     $4080
        rts
chip_off:
        lda     #$80
        sta     $4080
        rts
.endif

        .segment "VECTORES"
.if CHIP = FDS_C
        .word   nmi, nmi, nmi, reset, irq        ; $DFF6: NMI 1-3, RESET, IRQ
.else
        .word   nmi, reset, irq
.endif
