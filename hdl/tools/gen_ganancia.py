#!/usr/bin/env python3
"""Tabla de ganancias del sonido de expansión (función ganancia() de hdl/rtl/n8_top.v).

ganancia = base del chip x factor del paso de volumen, en unidades de 1/256. Uso: python3 -I gen_ganancia.py
y copiar la salida en n8_top.v.

Base del chip (provisional hasta la calibración con la Famicom, docs/sonido-volumen.md): la proporción de mezcla
de Mesen2 (NesSoundMixer::GetOutputVolume) entre el nivel de cada chip en el HDL y su peso en Mesen2, tomando el
VRC6 como referencia (ganancia 1, el mismo volumen de antes):
  unidades de Mesen2 por nivel del HDL: FDS 20/16, VRC6 75/8, 5B 15/1, N163 20/2, VRC7 1/(1/16), MMC5 43/1
  base = 256 x u / (75/8)
Calibrada en la Famicom (2026-11-24, tools/calibracion): las ROMs de calibración alternan una nota del APU y la
misma nota del chip; la proporción medida en la consola, frente a la de Mesen2, da una corrección por chip (MEDIDO).
Todas quedan entre x1,25 y x1,33 (las proporciones de Mesen2 entre chips se cumplen al 3 %): con ellas cada chip
suena frente al APU como en Mesen2.
Paso del usuario 0-8 (en el menú, -4 a +4): factor 2^((paso-4)/2), unos 3 dB por paso, de x1/4 a x4.
"""

U = {"tono": 75 / 8, "fds": 20 / 16, "vrc6": 75 / 8, "5b": 15.0, "n163": 10.0, "vrc7": 16.0, "mmc5": 43.0}
CHIPS = ["tono", "fds", "vrc6", "5b", "n163", "vrc7", "mmc5"]
# corrección medida en la Famicom AV con el N8 de Famicom (Mesen2 / medido, medir.py); el tono de prueba no se toca
MEDIDO = {"tono": 1.0, "fds": 1.272, "vrc6": 1.326, "5b": 1.312, "n163": 1.248, "vrc7": 1.252, "mmc5": 1.294}


def base(chip):
    return round(256 * U[chip] / (75 / 8) * MEDIDO[chip])


def factor(paso):
    return round(256 * 2 ** ((paso - 4) / 2))


def ganancia(chip, paso):
    return (base(chip) * factor(paso) + 128) >> 8


if __name__ == "__main__":
    for i, c in enumerate(CHIPS):
        fila = ", ".join(f"{ganancia(c, p):4d}" for p in range(9))
        print(f"            // {c:5s} base {base(c):4d}")
        for p in range(9):
            print(f"            {{3'd{i}, 4'd{p}}}: ganancia = 13'd{ganancia(c, p)};")
