# Firmware del mando emulado (Arduino Nano/Uno, ATmega328P).
# Se compila con clang (destino AVR) y ld.lld: no hace falta avr-gcc ni avr-libc.
#   make            -> build/mando.hex (y se copia a mando.hex, el que va en el repositorio)
#   make sim        -> build/libmando_sim.so (la misma lógica para la prueba en seco)
#   make flash PUERTO=/dev/ttyUSB0           (flasheador propio, sin avrdude)
#   make flash-avrdude PUERTO=/dev/ttyUSB0 BAUD=57600   (Nano con cargador antiguo: 57600; Optiboot/Uno: 115200)

CLANG  ?= clang
LLD    ?= ld.lld
OBJCOPY ?= llvm-objcopy
SIZE   ?= llvm-size
PUERTO ?= /dev/ttyUSB0
BAUD   ?= 115200

AVRFLAGS = --target=avr -mmcu=atmega328p -Os -Wall -Wextra -ffreestanding -fno-builtin -fno-jump-tables \
           -ffunction-sections -fdata-sections

all: mando.hex

build:
	mkdir -p build

build/nucleo.o: nucleo.c nucleo.h | build
	$(CLANG) $(AVRFLAGS) -c nucleo.c -o $@
build/main_avr.o: main_avr.c nucleo.h avr328p.h | build
	$(CLANG) $(AVRFLAGS) -c main_avr.c -o $@
build/rt_avr.o: rt_avr.c | build
	$(CLANG) $(AVRFLAGS) -c rt_avr.c -o $@
build/arranque.o: arranque.S | build
	$(CLANG) --target=avr -mmcu=atmega328p -c arranque.S -o $@

OBJS = build/arranque.o build/main_avr.o build/nucleo.o build/rt_avr.o
build/mando.elf: $(OBJS) enlace.ld
	$(LLD) -T enlace.ld --gc-sections -e __reset $(OBJS) -o $@
	$(SIZE) $@

build/mando.hex: build/mando.elf
	$(OBJCOPY) -O ihex -j .text -j .data $< $@

mando.hex: build/mando.hex
	cp $< $@

sim: build/libmando_sim.so
build/libmando_sim.so: nucleo.c nucleo.h sim_hw.c | build
	$(CLANG) -O2 -Wall -Wextra -shared -fPIC nucleo.c sim_hw.c -o $@

flash: mando.hex
	python3 -I ../flashear.py --puerto $(PUERTO) mando.hex

flash-avrdude: mando.hex
	avrdude -p m328p -c arduino -P $(PUERTO) -b $(BAUD) -U flash:w:mando.hex:i

clean:
	rm -rf build

.PHONY: all sim flash flash-avrdude clean
