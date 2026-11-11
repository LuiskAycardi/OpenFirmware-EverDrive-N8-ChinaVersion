#!/bin/sh
# mesen2-setup.sh — prepara tools/mesen2 (Mesen2 + los cambios del banco N8) a partir de git.
# Mesen2 (GPL-3, SourMesen) no se guarda en este repositorio: se clona en la versión fijada y se le
# aplica tools/mesen2-n8.patch (registro de audio N8AudioLog, alta del mapper puente en MapperFactory,
# acceso al reloj maestro para el puente, makefile con N8SIM). El puente (tools/n8sim/N8FpgaMapper.*)
# se enlaza con symlinks. Después: make -C tools/n8sim mesen
#
# Para regenerar el parche tras cambiar Mesen2:  git -C tools/mesen2 diff > tools/mesen2-n8.patch
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
BASE=b9fa69d          # commit de Mesen2 sobre el que está hecho el parche
if [ ! -d "$HERE/mesen2/.git" ]; then
    git clone https://github.com/SourMesen/Mesen2.git "$HERE/mesen2"
fi
git -C "$HERE/mesen2" checkout -q "$BASE"
if git -C "$HERE/mesen2" apply --check "$HERE/mesen2-n8.patch" 2>/dev/null; then
    git -C "$HERE/mesen2" apply "$HERE/mesen2-n8.patch"
    echo "parche aplicado"
else
    echo "el parche ya está aplicado (o no aplica limpio): revisar git -C tools/mesen2 status"
fi
mkdir -p "$HERE/mesen2/Core/NES/Mappers/N8"
ln -sfn ../../../../../n8sim/N8FpgaMapper.cpp "$HERE/mesen2/Core/NES/Mappers/N8/N8FpgaMapper.cpp"
ln -sfn ../../../../../n8sim/N8FpgaMapper.h   "$HERE/mesen2/Core/NES/Mappers/N8/N8FpgaMapper.h"
echo "listo: make -C tools/n8sim mesen"
