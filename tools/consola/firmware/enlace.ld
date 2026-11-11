/* enlace.ld — mapa de memoria del ATmega328P para ld.lld (flash en 0, RAM en 0x800100 como en avr-gcc).
   30 KB de flash: deja sitio al cargador del Nano antiguo (2 KB) y al Optiboot (512 B). */
MEMORY {
  flash (rx)  : ORIGIN = 0,        LENGTH = 30K
  ram   (rw)  : ORIGIN = 0x800100, LENGTH = 2K
}
SECTIONS {
  .text : {
    KEEP(*(.vectors))
    *(.text .text.*)
    . = ALIGN(2);
  } > flash
  .data : {
    __data_start = .;
    *(.data .data.*)
    *(.rodata .rodata.*)
    . = ALIGN(2);
    __data_end = .;
  } > ram AT > flash
  __data_load_start = LOADADDR(.data);
  .bss (NOLOAD) : {
    __bss_start = .;
    *(.bss .bss.*)
    *(COMMON)
    __bss_end = .;
  } > ram
}
