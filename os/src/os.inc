; os.inc — constantes comunes del OS propio del N8 clon (GPL-3.0-or-later).

PPUCTRL   = $2000
PPUMASK   = $2001
PPUSTATUS = $2002
PPUSCROLL = $2005
PPUADDR   = $2006
PPUDATA   = $2007
APU_DMC   = $4010
APU_EST   = $4015
MANDO1    = $4016
MANDO2    = $4017
APU_CONT  = $4017
REG_SEL   = $4400               ; número de registro (CPLD y FPGA)
REG_DAT   = $4401               ; dato
CPLD_MODO = $4402               ; modo del CPLD: 3 normal, 5 mientras se configura el FPGA
CPLD_EST  = $4403               ; lectura: estado del CPLD (bit 0: SPI libre)
CPLD_CFG  = $4403               ; escritura: byte de configuración del FPGA (con CPLD_MODO = 5)
REG_CHR   = 130                 ; FPGA, modo OS: banco de la CHR visible en $0000-$1FFF de la PPU

; tipos de arranque (arranque.s)
TIPO_FRIO   = 0                 ; la BIOS acaba de cargar el OS.BIN
TIPO_RESET  = 1                 ; reset (botón o kit Lava) estando en el OS
TIPO_VUELTA = 2                 ; reset estando en un juego: el RBF ha vuelto al modo OS

; caracteres de la fuente fuera de ASCII (herramientas/fuente.py)
C_a = $80                       ; á
C_e = $81                       ; é
C_i = $82                       ; í
C_o = $83                       ; ó
C_u = $84                       ; ú
C_n = $85                       ; ñ
C_ud = $86                      ; ü
C_A = $87                       ; Á
C_E = $88                       ; É
C_I = $89                       ; Í
C_O = $8A                       ; Ó
C_U = $8B                       ; Ú
C_N = $8C                       ; Ñ
C_UD = $8D                      ; Ü
C_INT = $8E                     ; ¿
C_EXC = $8F                     ; ¡
C_CURSOR = $92                  ; cursor del menú
C_IZQ = $93                     ; ◀
C_PUNTOS = $94                  ; … (nombre cortado)

; motivos por los que no se puede lanzar un juego (lanzar.s)
L_NOINES    = 1                 ; no empieza por "NES" $1A
L_TAM       = 2                 ; PRG o CHR fuera de lo que cabe (512 KiB cada una)
L_MAPROUT   = 3                 ; no está EDFC/MAPROUT.BIN
L_SINMAPPER = 4                 ; MAPROUT no tiene RBF para ese mapper
L_SINRBF    = 5                 ; no está EDFC/MAPS/NNN.RBF
L_FRAG      = 6                 ; el RBF no está contiguo en la tarjeta
L_SD        = 7                 ; error de lectura (fat_error)
L_FPGA      = 8                 ; no llegan los datos durante la configuración

