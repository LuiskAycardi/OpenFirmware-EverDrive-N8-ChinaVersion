#!/bin/sh
# hacer_sd.sh <salida.img> <fat:16|32> <mbr:si|no> <carpeta_EDFC>
set -e
IMG=$1; FAT=$2; MBR=$3; SRC=$4
if [ "$FAT" = 32 ]; then MB=80; else MB=64; fi
rm -f "$IMG"; truncate -s ${MB}M "$IMG"
if [ "$MBR" = si ]; then
  if [ "$FAT" = 32 ]; then T=c; else T=6; fi
  echo "8192,,$T" | sfdisk -q "$IMG" >/dev/null
  OFF=8192
else OFF=0; fi
SECT=$(( (MB*2048) - OFF ))
mkfs.fat -F $FAT --offset $OFF -n N8PRUEBA "$IMG" $((SECT/2)) >/dev/null
export MTOOLS_SKIP_CHECK=1
I="$IMG@@$((OFF*512))"
mmd -i "$I" ::EDFC ::EDFC/MAPS ::EDFC/SAVE
mcopy -i "$I" "$SRC/OS.BIN" ::EDFC/OS.BIN
mcopy -i "$I" "$SRC/255.RBF" ::EDFC/MAPS/255.RBF
[ -f "$SRC/MAPROUT.BIN" ] && mcopy -i "$I" "$SRC/MAPROUT.BIN" ::EDFC/MAPROUT.BIN
true
