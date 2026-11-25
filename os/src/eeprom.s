; eeprom.s — partidas de las EEPROM serie del Bandai (mappers 16, 157 y 159). GPL-3.0-or-later, código propio.
;
; La EEPROM del juego vive en la FPGA (hdl/rtl/eeprom_24c0x.v, en el 100.RBF), no en la PRG-RAM con pila. En el
; modo OS el mapper está en reset y su memoria se ve en una ventana (hdl/rtl/mapper_bandaifcg.v):
;   $5400-$54FF  EEPROM principal (24C02 de 256 bytes; la 24C01 del 159 usa $5400-$547F)
;   $5500-$557F  24C01 del cartucho del Datach (Battle Rush)
;   $5580-$55FF  se lee $A5 (con otro RBF, o recién encendida la consola, ahí hay bus abierto: $55)
; El RBF sigue cargado tras un RESET, así que la memoria sobrevive al RESET pero no al apagado.
;
; La partida pasa por el banco 8 de la PRG-RAM ($6E00-$6FFF, un sector): partida.s lee ahí el .srm al lanzar
; (pt_eep) y lo escribe desde ahí al guardar. Formato del .srm: los bytes de la EEPROM tal cual, 256 (16 y 157),
; 128 (159) o 384 (157 con la 24C01 del cartucho: 256 de la base y después 128 del cartucho), como los .sav de los
; emuladores (Mesen2 los llama .eeprom256 y .eeprom128; el de 384, en dos archivos).
;
; Va en el segmento FDSOVL (banco 8, $7000-$7FFF, con el código del FDS): se llama con el banco 8 en la ventana.
;   eep_cargar  (con el RBF del juego ya en el FPGA, antes de saltar) $6E00 -> ventana, y la relee. Acarreo = 1
;               (A = L_EEPROM) si no coincide o no está la firma $A5: no se lanza.
;   eep_volcar  (al guardar, con la marca de partida pendiente de EEPROM) ventana -> $6E00. Acarreo = 1 si no está
;               la firma: la FPGA se recargó (apagado) y la partida de esta sesión se perdió.
;   eep_aviso   (al lanzar) «Pulsa RESET antes de apagar» en la fila de mensajes, 1,5 s con la pantalla encendida.

        .setcpu "6502"
        .include "os.inc"

        .export eep_cargar, eep_volcar, eep_aviso
        .import ppu_dir, cadena, espacio, sin_scroll
        .importzp ptr

EEP     = $5400
EEP_X   = $5500
EEP_ID  = $5580
FIRMA   = $A5
BUF_E   = $6E00
FILA_MSJ = $2000 + 25 * 32

        .segment "FDSOVL"

eep_cargar:
        ldx     #0
@c:     lda     BUF_E,x
        sta     EEP,x
        cmp     EEP,x
        bne     @mal
        lda     BUF_E+$80,x
        sta     EEP+$80,x
        cmp     EEP+$80,x
        bne     @mal
        lda     BUF_E+$100,x
        sta     EEP_X,x
        cmp     EEP_X,x
        bne     @mal
        inx
        bpl     @c
        lda     EEP_ID
        cmp     #FIRMA
        bne     @mal
        clc
        rts
@mal:   lda     #L_EEPROM
        sec
        rts

eep_volcar:
        lda     EEP_ID
        cmp     #FIRMA
        bne     @no
        lda     EEP_ID+$7F
        cmp     #FIRMA
        bne     @no
        ldx     #0
@c:     lda     EEP,x
        sta     BUF_E,x
        lda     EEP+$80,x
        sta     BUF_E+$80,x
        lda     EEP_X,x
        sta     BUF_E+$100,x
        inx
        bpl     @c
        clc
        rts
@no:    sec
        rts

; La pantalla está apagada (lanzar_sel) y sin NMI: se espera el VBlank leyendo PPUSTATUS.
eep_aviso:
        lda     #>(FILA_MSJ + 2)
        ldx     #<(FILA_MSJ + 2)
        jsr     ppu_dir
        lda     #<t_aviso
        sta     ptr
        lda     #>t_aviso
        sta     ptr+1
        jsr     cadena
        ldx     #28 - (t_aviso_fin - t_aviso)
@b:     jsr     espacio
        dex
        bne     @b
        jsr     sin_scroll
        ldx     #90
@v:     bit     PPUSTATUS
        bpl     @v
        lda     #%00001010
        sta     PPUMASK
        dex
        bne     @v
        lda     #0
        sta     PPUMASK
        rts

t_aviso: .byte "Pulsa RESET antes de apagar"
t_aviso_fin:
        .byte 0
