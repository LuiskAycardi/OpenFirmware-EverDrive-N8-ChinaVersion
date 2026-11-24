# Makefile del arnés que mete en snd_fds.v las escrituras de sonido del FDS de Mesen2 (necesita Verilator).
RTL := ../../../hdl/rtl/snd_fds.v

replay: main.cpp $(RTL)
	verilator --cc --exe --build -O3 -Wno-fatal -Wno-lint -Wno-style --top-module snd_fds -Mdir obj $(RTL) main.cpp -o ../replay > /dev/null

clean:
	rm -rf obj replay
