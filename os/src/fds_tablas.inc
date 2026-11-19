; fds_tablas.inc — generado por tools/fds/analizar.py --inc (no editar a mano). GPL-3.0-or-later.
; Solo sumas CRC32: ningún byte de las BIOS ni de los juegos.

FDS_INI     = 496                ; bytes del principio del disco que entran en la suma de fds_malos
FDS_BIOS_SI = 3                  ; las primeras de fds_bios se pueden parchear
FDS_BIOS_N  = 7
FDS_MALOS_N = 17

fds_bios_crc:
        .dword  $5E607DCF      ; Rev 1
        .dword  $4DF24A6C      ; Twin Famicom
        .dword  $1C7AE5D5      ; Rev 0
        .dword  $0BA8D953      ; GameCube
        .dword  $17E30673      ; 3DS VC
        .dword  $34E2B2C7      ; 3DS VC alt
        .dword  $7D8F0C3C      ; Game & Watch

; CRC-32 (polinomio $EDB88320 reflejado) de 4 en 4 bits
tabla_crc:
        .dword  $00000000
        .dword  $1DB71064
        .dword  $3B6E20C8
        .dword  $26D930AC
        .dword  $76DC4190
        .dword  $6B6B51F4
        .dword  $4DB26158
        .dword  $5005713C
        .dword  $EDB88320
        .dword  $F00F9344
        .dword  $D6D6A3E8
        .dword  $CB61B38C
        .dword  $9B64C2B0
        .dword  $86D3D2D4
        .dword  $A00AE278
        .dword  $BDBDF21C

; discos con rutina de disco propia (no cargan con la BIOS parcheada)
fds_malos:
        .dword  $076C4BEF      ; Sunsoft Dev Disk Lot - 'E180L05' no. 2 and no. 3 (Japan)
        .dword  $115B0E2F      ; Disk Hacker II - Copy Plus 3 (Japan) (Unl)
        .dword  $122DE053      ; Bishoujo Sexy Derby (Japan) (Unl)
        .dword  $1E6977D7      ; Tantei Jinguuji Saburou - Kiken na Futari - Kouhen (Japan)
        .dword  $3C37DCED      ; Disk Keeper (Japan) (Unl)
        .dword  $51D57940      ; Disk Hacker - Version 1.0 (Japan) (Unl)
        .dword  $675C152F      ; FMC Disk Card Checker Ver 1.3 (Japan) (Rev 2) (Developer Card)
        .dword  $69ABC0E8      ; Kosodate Gokko (Japan) (Unl)
        .dword  $73968DD4      ; Souseiki Fammy - ROM-QD for 256K+64K (Japan) (Unl)
        .dword  $756E1696      ; Tonkachi Editor (Japan) (Unl)
        .dword  $8D348880      ; Bishoujo Hanafuda Club Vol.1 - Oichokabu Hen (Japan) (Unl)
        .dword  $ADB58C82      ; Sunsoft Dev Disk Lot - 'E180L05' no. 1 (Japan)
        .dword  $C3DE77B0      ; Disk Hacker - Version 1.2 (Japan) (Unl)
        .dword  $DB5BE0DE      ; Casino de Pink (Japan) (Unl) [b]
        .dword  $E613F3F9      ; Tantei Jinguuji Saburou - Kiken na Futari - Kouhen (Japan) (Virtual Console)
        .dword  $FDEF2559      ; Disk Hacker - Version 1.3 (Japan) (Unl)
        .dword  $FFC55B81      ; Aki to Tsukasa no Fushigi no Kabe (Japan) (Unl)
