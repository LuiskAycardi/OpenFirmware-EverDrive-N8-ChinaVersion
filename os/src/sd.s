; sd.s — tarjeta SD por el SPI del CPLD del N8 clon. SOLO LECTURA: no hay ninguna orden de escritura (CMD24/25).
; GPL-3.0-or-later. Código propio, escrito a partir de los registros descritos en docs/bios-n8-clon.md §2:
;   reg 0 por $4401   dato SPI: escribir envía un byte; leer devuelve el último recibido o, en ráfaga, saca otro
;   reg 2             bit 0 = lo pone la BIOS tras inicializar (¿SPI rápido?), bit 1 = /CS (1 = tarjeta libre),
;                     bit 2 = ráfaga (cada lectura de $4401 saca un byte nuevo), bit 3 = «la tarjeta es SDHC»
;   $4403 bit 0       SPI libre
; Protocolo: SD en modo SPI (CMD0, CMD8, ACMD41, CMD58, CMD16, CMD17, CMD12).
;
; La BIOS deja la tarjeta a mitad de una lectura múltiple (CMD18 sin CMD12), y un reset puede cortar una lectura
; nuestra: por eso sd_iniciar empieza con CMD12 y vuelve a inicializar la tarjeta desde CMD0.

        .setcpu "6502"
        .include "os.inc"

        .export sd_iniciar, sd_leer_sector, sd_rapido
        .export sd_error, sd_r1, sd_sdhc
        .exportzp sd_lba, sd_ptr

R2_RAPIDO = %00000001
R2_LIBRE  = %00000010           ; /CS alto
R2_RAFAGA = %00000100
R2_SDHC   = %00001000

; códigos de sd_error (0 = bien)
E_CMD0   = 1                    ; la tarjeta no contesta a CMD0
E_ACMD41 = 2                    ; no sale del estado de reposo
E_CMD58  = 3
E_CMD17  = 4                    ; la orden de lectura da error (sd_r1)
E_DATOS  = 5                    ; no llega el testigo de datos
        .export E_CMD0, E_ACMD41, E_CMD58, E_CMD17, E_DATOS

        .segment "ZEROPAGE"
sd_lba:     .res 4              ; sector a leer (byte bajo primero)
sd_ptr:     .res 2              ; destino de los 512 bytes
sd_arg:     .res 4              ; argumento de la orden, byte alto primero
sd_c:       .res 1              ; número de orden
sd_crc:     .res 1
sd_n:       .res 2              ; contadores de espera

        .segment "BSS"
sd_base:    .res 1              ; bits 0 y 3 del reg 2 (rápido, SDHC)
sd_error:   .res 1
sd_r1:      .res 1              ; última respuesta R1
sd_sdhc:    .res 1              ; 1 = direcciones por bloque
sd_v2:      .res 1              ; contestó a CMD8

        .segment "CODE"

; ---------------------------------------------------------------------------------------------- reg 2 y SPI
; Escribe A en el reg 2 y deja seleccionado el reg 0 (dato SPI).
reg2:   pha
        lda     #2
        sta     REG_SEL
        pla
        sta     REG_DAT
        lda     #0
        sta     REG_SEL
        rts

cs_bajo:                                ; tarjeta seleccionada, sin ráfaga
        lda     sd_base
        jmp     reg2
cs_alto:
        lda     sd_base
        ora     #R2_LIBRE
        jmp     reg2

; Envía A y devuelve en A el byte recibido. Espera a que el SPI quede libre (con tope). Usa X.
spi:    sta     REG_DAT
        ldx     #0
@e:     lda     CPLD_EST
        lsr
        bcs     @ya
        dex
        bne     @e
@ya:    lda     REG_DAT
        rts

; Suelta la tarjeta y le da 8 relojes más.
sd_fin: jsr     cs_alto
        lda     #$FF
        jmp     spi

; Envía la orden sd_c con sd_arg y sd_crc (la tarjeta ya seleccionada) y espera la respuesta R1.
; Devuelve A = sd_r1 ($FF = no contestó).
sd_cmd: lda     #$FF
        jsr     spi
        lda     sd_c
        ora     #$40
        jsr     spi
        lda     sd_arg
        jsr     spi
        lda     sd_arg+1
        jsr     spi
        lda     sd_arg+2
        jsr     spi
        lda     sd_arg+3
        jsr     spi
        lda     sd_crc
        jsr     spi
        lda     #0
        sta     sd_n                    ; 256 intentos
@r:     lda     #$FF
        jsr     spi
        cmp     #$FF
        bne     @fin
        dec     sd_n
        bne     @r
@fin:   sta     sd_r1
        lda     sd_r1                   ; banderas según R1 (Z = 1 si es $00)
        rts

arg_cero:
        lda     #0
        sta     sd_arg
        sta     sd_arg+1
        sta     sd_arg+2
        sta     sd_arg+3
        lda     #$FF
        sta     sd_crc
        rts

; Orden A sin argumento, completa (selecciona, envía, suelta). Devuelve A = R1.
orden_simple:
        sta     sd_c
        jsr     cs_bajo
        jsr     sd_cmd
        jsr     sd_fin
        lda     sd_r1
        rts

; ---------------------------------------------------------------------------------------------- inicialización
; Devuelve acarreo = 1 y sd_error si falla.
sd_iniciar:
        lda     #0
        sta     sd_error
        sta     sd_sdhc
        sta     sd_v2
        sta     sd_base                 ; como la BIOS mientras inicializa: bits 0 y 3 a cero
        jsr     cs_alto
        ldy     #10                     ; 80 relojes con la tarjeta libre
@rel:   lda     #$FF
        jsr     spi
        dey
        bne     @rel

        ; cortar una lectura múltiple a medias (la que deja la BIOS)
        jsr     arg_cero
        lda     #12
        sta     sd_c
        jsr     cs_bajo
        jsr     sd_cmd
        ldy     #0                      ; esperar a que deje de estar ocupada
@ocu:   lda     #$FF
        jsr     spi
        cmp     #$FF
        beq     @libre
        dey
        bne     @ocu
@libre: jsr     sd_fin

        ; CMD0: a reposo
        ldy     #16
@c0:    jsr     arg_cero
        lda     #$95
        sta     sd_crc
        lda     #0
        jsr     orden_simple
        cmp     #$01
        beq     @reposo
        dey
        bne     @c0
        lda     #E_CMD0
        jmp     error

        ; CMD8: ¿tarjeta de la versión 2?
@reposo:
        jsr     arg_cero
        lda     #$01
        sta     sd_arg+2
        lda     #$AA
        sta     sd_arg+3
        lda     #$87
        sta     sd_crc
        lda     #8
        sta     sd_c
        jsr     cs_bajo
        jsr     sd_cmd
        cmp     #$01
        bne     @sin8
        inc     sd_v2
        ldy     #4                      ; los 4 bytes de R7 no se usan
@r7:    lda     #$FF
        jsr     spi
        dey
        bne     @r7
@sin8:  jsr     sd_fin

        ; ACMD41 hasta que salga del reposo
        lda     #0
        sta     sd_n+1                  ; hasta 4096 intentos
        lda     #$10
        sta     sd_n+1
        ldy     #0
@a41:   jsr     arg_cero
        lda     #55
        jsr     orden_simple
        jsr     arg_cero
        lda     sd_v2
        beq     @sin_hcs
        lda     #$40                    ; HCS: admitimos SDHC
        sta     sd_arg
@sin_hcs:
        lda     #41
        jsr     orden_simple
        beq     @lista
        dey
        bne     @a41
        dec     sd_n+1
        bne     @a41
        lda     #E_ACMD41
        jmp     error

        ; CMD58: ¿direcciones por bloque?
@lista: lda     sd_v2
        beq     @sdsc
        jsr     arg_cero
        lda     #58
        sta     sd_c
        jsr     cs_bajo
        jsr     sd_cmd
        beq     @ocr
        jsr     sd_fin
        lda     #E_CMD58
        jmp     error
@ocr:   lda     #$FF
        jsr     spi                     ; primer byte del OCR: bit 6 = CCS
        and     #$40
        beq     @resto
        lda     #1
        sta     sd_sdhc
@resto: ldy     #3
@o:     lda     #$FF
        jsr     spi
        dey
        bne     @o
        jsr     sd_fin
        lda     sd_sdhc
        bne     @fin
@sdsc:  jsr     arg_cero                ; SDSC: bloques de 512 bytes
        lda     #$02
        sta     sd_arg+2
        lda     #16
        jsr     orden_simple
@fin:   lda     #1                      ; como la BIOS tras inicializar: bit 0 y, si es SDHC, bit 3
        jsr     sd_rapido
        clc
        rts

error:  sta     sd_error
        jsr     cs_alto
        sec
        rts

; A = 1: pone el bit 0 del reg 2 (lo que hace la BIOS antes de leer archivos); A = 0: lo quita. Mantiene el bit 3.
sd_rapido:
        and     #R2_RAPIDO
        ldx     sd_sdhc
        beq     @no
        ora     #R2_SDHC
@no:    sta     sd_base
        jmp     cs_alto

; ---------------------------------------------------------------------------------------------- lectura
; Lee el sector sd_lba en (sd_ptr), 512 bytes. No cambia sd_lba ni sd_ptr. Acarreo = 1 y sd_error si falla.
sd_leer_sector:
        lda     sd_sdhc
        beq     @bytes
        lda     sd_lba+3                ; SDHC: número de bloque
        sta     sd_arg
        lda     sd_lba+2
        sta     sd_arg+1
        lda     sd_lba+1
        sta     sd_arg+2
        lda     sd_lba
        sta     sd_arg+3
        jmp     @orden
@bytes: lda     sd_lba                  ; SDSC: dirección en bytes = sector x 512
        asl
        sta     sd_arg+2
        lda     sd_lba+1
        rol
        sta     sd_arg+1
        lda     sd_lba+2
        rol
        sta     sd_arg
        lda     #0
        sta     sd_arg+3
@orden: lda     #$FF
        sta     sd_crc
        lda     #17
        sta     sd_c
        jsr     cs_bajo
        jsr     sd_cmd
        beq     @datos
        jsr     sd_fin
        lda     #E_CMD17
        jmp     error

        ; Ráfaga: cada lectura de $4401 saca otro byte. Se espera el testigo $FE sin suponer nada del primer
        ; byte leído (puede ser el último recibido antes de activar la ráfaga).
@datos: lda     sd_base
        ora     #R2_RAFAGA
        jsr     reg2
        lda     #0
        sta     sd_n
        sta     sd_n+1
@tes:   lda     REG_DAT
        cmp     #$FE
        beq     @bloque
        dec     sd_n
        bne     @tes
        dec     sd_n+1
        bne     @tes
        jsr     cs_bajo
        jsr     sd_fin
        lda     #E_DATOS
        jmp     error
@bloque:
        ldy     #0
@p1:    lda     REG_DAT
        sta     (sd_ptr),y
        iny
        bne     @p1
        inc     sd_ptr+1
@p2:    lda     REG_DAT
        sta     (sd_ptr),y
        iny
        bne     @p2
        dec     sd_ptr+1
        lda     REG_DAT                 ; CRC (no se comprueba)
        lda     REG_DAT
        jsr     cs_bajo                 ; fin de la ráfaga
        jsr     sd_fin
        clc
        rts
