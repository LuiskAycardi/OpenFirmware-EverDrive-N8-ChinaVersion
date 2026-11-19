"""fds.py — Lectura de imágenes del Famicom Disk System (.fds) y de las BIOS FDS (GPL-3.0-or-later).

Código propio. No contiene ningún byte de la BIOS ni de los juegos: solo sumas CRC32 (para reconocer los volcados que
tiene el usuario) y el formato público de los bloques del disco (nesdev.org, «FDS disk format»).

Formato de una cara en un .fds (65 500 bytes, sin huecos ni CRC entre bloques):
  bloque 1 (56 B): $01, «*NINTENDO-HVC*», fabricante, código del juego (3 letras), tipo, revisión, cara, disco, ...
  bloque 2 (2 B):  $02, número de archivos (los que lee la BIOS; puede haber más, «ocultos», detrás)
  por archivo: bloque 3 (16 B): $03, n.º, ID, nombre (8), dirección (2), tamaño (2), tipo (0 PRG, 1 CHR, 2 NT)
               bloque 4 (1 + tamaño): $04 y los datos
Puede llevar delante la cabecera de fwNES (16 B: «FDS», $1A, número de caras, ceros).
"""
import zlib

CARA = 65500
FIRMA = b'*NINTENDO-HVC*'

# BIOS conocidas: CRC32 -> (nombre, estado, explicación). «si» = se puede parchear con los puntos de enganche de la
# Rev 1 (las rutinas de disco $E68F-$E7BA y $E1C7-$E1F5 son las mismas); «no» = volcado de un emulador: lleva
# opcodes trampa ($42, $E7...) o rutinas de disco vaciadas que en un 6502 real cuelgan la consola.
BIOS = {
    0x5E607DCF: ('Rev 1', 'si', 'la BIOS de referencia del parche'),
    0x4DF24A6C: ('Twin Famicom', 'si', 'igual que la Rev 1 salvo datos de la pantalla de arranque ($F6A3-$FA34)'),
    0x1C7AE5D5: ('Rev 0', 'si', 'cambia la rutina del motor ($E64E-$E68A); bloques y bytes, iguales a la Rev 1'),
    0x0BA8D953: ('GameCube', 'no', 'opcodes trampa del emulador en $E239, $E406, $E7A4 y $EEF4'),
    0x17E30673: ('3DS VC', 'no', 'trampas del emulador ($E153, $E1F8, $E239, $E40A) y saltos cambiados'),
    0x34E2B2C7: ('3DS VC alt', 'no', 'como la 3DS VC, con más cambios ($EB14-$EB57)'),
    0x7D8F0C3C: ('Game & Watch', 'no', 'rutinas de disco vaciadas con NOP (las hace su emulador)'),
}

# Registros del disco. Leer $4031 o escribir $4024 sin pasar por la BIOS = rutina de disco propia del juego.
REG_DATOS_LEER = 0x4031
REG_DATOS_ESCRIBIR = 0x4024
REGS_ESTADO = (0x4030, 0x4032)
LEER = {0xAD: 'LDA', 0xAE: 'LDX', 0xAC: 'LDY', 0x2C: 'BIT', 0xBD: 'LDA,X', 0xB9: 'LDA,Y'}
ESCRIBIR = {0x8D: 'STA', 0x8E: 'STX', 0x8C: 'STY'}


def bios_info(datos):
    """(crc, nombre, estado, explicación) de un volcado de BIOS; estado «?» si no se conoce o no mide 8 KiB."""
    crc = zlib.crc32(datos)
    if len(datos) != 8192:
        return crc, None, '?', f'mide {len(datos)} bytes, no 8192'
    nombre, estado, texto = BIOS.get(crc, (None, '?', 'BIOS desconocida'))
    return crc, nombre, estado, texto


def caras(datos):
    """Lista de caras (bytes de 65 500) y si tenía cabecera fwNES. ValueError si el tamaño no cuadra."""
    cab = datos[:4] == b'FDS\x1a'
    cuerpo = datos[16:] if cab else datos
    if len(cuerpo) == 0 or len(cuerpo) % CARA:
        raise ValueError(f'tamaño {len(datos)}: no es un múltiplo de {CARA}' + (' (con cabecera)' if cab else ''))
    return [cuerpo[i:i + CARA] for i in range(0, len(cuerpo), CARA)], cab


def leer_cara(c):
    """Recorre los bloques de una cara. Devuelve un dict con la cabecera, los archivos (declarados y ocultos) y los
    problemas encontrados."""
    r = {'problemas': [], 'archivos': []}
    if c[0] != 1 or c[1:15] != FIRMA:
        r['problemas'].append('sin bloque 1 válido («*NINTENDO-HVC*»)')
        return r
    r['fabricante'] = c[15]
    r['codigo'] = c[16:19].decode('latin-1')
    r['tipo'] = chr(c[19]) if 32 <= c[19] < 127 else f'${c[19]:02X}'
    r['revision'] = c[20]
    r['cara'] = c[21]
    r['disco'] = c[22]
    r['arranque'] = c[25]          # los archivos con ID <= este se cargan al arrancar
    p = 56
    if c[p] != 2:
        r['problemas'].append('sin bloque 2')
        return r
    r['declarados'] = c[p + 1]
    p += 2
    n = 0
    while p + 16 <= len(c) and c[p] == 3:
        cab = c[p:p + 16]
        tam = cab[13] | cab[14] << 8
        arch = {'n': cab[1], 'id': cab[2], 'nombre': cab[3:11].decode('latin-1', 'replace').rstrip('\0 '),
                'dir': cab[11] | cab[12] << 8, 'tam': tam, 'tipo': cab[15], 'oculto': n >= r['declarados']}
        p += 16
        if p >= len(c) or c[p] != 4:
            r['problemas'].append(f'archivo {n}: falta el bloque 4')
            break
        arch['datos'] = c[p + 1:p + 1 + tam]
        if len(arch['datos']) < tam:
            r['problemas'].append(f'archivo {n}: cortado al final de la cara')
        p += 1 + tam
        r['archivos'].append(arch)
        n += 1
    if n < r['declarados']:
        r['problemas'].append(f'declara {r["declarados"]} archivos y solo hay {n}')
    r['usado'] = p
    return r


def accesos(datos, base):
    """Accesos absolutos a los registros del FDS en un archivo PRG: {(op, reg): [direcciones]}. Es una búsqueda de
    patrones sobre bytes, así que puede dar falsos positivos en zonas de datos."""
    r = {}
    for i in range(len(datos) - 2):
        op = datos[i]
        a = datos[i + 1] | datos[i + 2] << 8
        if 0x4020 <= a <= 0x4097 and (op in LEER or op in ESCRIBIR):
            nombre = LEER.get(op) or ESCRIBIR[op]
            r.setdefault((nombre, a), []).append(base + i)
    return r
