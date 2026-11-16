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
CPLD_EST  = $4403               ; estado del CPLD (bit 0: SPI libre)
REG_CHR   = 130                 ; FPGA, modo OS: banco de la CHR visible en $0000-$1FFF de la PPU

; tipos de arranque (arranque.s)
TIPO_FRIO   = 0                 ; la BIOS acaba de cargar el OS.BIN
TIPO_RESET  = 1                 ; reset (botón o kit Lava) estando en el OS
TIPO_VUELTA = 2                 ; reset estando en un juego: el RBF ha vuelto al modo OS
