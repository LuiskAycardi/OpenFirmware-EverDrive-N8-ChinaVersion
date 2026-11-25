#!/usr/bin/env python3
"""probar_os.py --bios BIOS.bin --rbf 255.RBF --trabajo DIR — Prueba el OS (etapa 6) con la BIOS real en el modelo
de tools/bios: arranque y resets, mando, lectura de la SD (FAT16/FAT32, SDHC/SDSC, con y sin MBR, raíz con cadena
de clústeres, reset a mitad de lectura, tarjeta muda) y lanzamiento de juegos (carga del RBF, PRG, CHR, registros,
salto, vuelta al menú y errores), carpetas (entrar, volver, páginas, vuelta de un juego dentro de una carpeta) y
nombres largos (acentos, cortados, ocultos, borrados) y partidas con pila (crear, cargar, guardar al volver y al
encender, nombres largos, carpeta ampliada, FAT16, SDSC, tarjeta que no deja escribir), menú ordenado (carpetas primero, acentos, ñ), información del juego, repetición,
saltos por letra, último juego al encender y la pantalla de opciones (volumen del sonido de expansión). Comprueba que solo escribe
en la tarjeta las partidas (y lo que la FAT necesita para crearlas, validado con fsck.fat) y nunca en la flash."""
import argparse, os, pathlib, shutil, subprocess, sys

RAIZ = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(RAIZ / 'tools/bios'))
from maquina import Maquina, SD   # noqa: E402
Maquina.ROJO = True                 # la fila seleccionada va en rojo (tiles = código ^ $80)

p = argparse.ArgumentParser()
p.add_argument('--bios', required=True)
p.add_argument('--rbf', required=True)
p.add_argument('--trabajo', required=True)
p.add_argument('--os', default=str(RAIZ / 'os/build/OS.BIN'))
a = p.parse_args()
t = pathlib.Path(a.trabajo)
t.mkdir(parents=True, exist_ok=True)
(t / 'edfc').mkdir(exist_ok=True)
shutil.copy(a.os, t / 'edfc/OS.BIN')
shutil.copy(a.rbf, t / 'edfc/255.RBF')
os.environ.setdefault('MTOOLS_SKIP_CHECK', '1')
os.environ['LC_ALL'] = 'C.UTF-8'          # mtools: nombres largos con acentos
bios = pathlib.Path(a.bios).read_bytes()

def imagen(nombre, fat, mbr, archivos):
    """Imagen con EDFC, una carpeta y `archivos` (nombre -> tamaño) en la raíz, en ese orden."""
    img = t / nombre
    subprocess.run(['sh', str(RAIZ / 'tools/bios/hacer_sd.sh'), str(img), str(fat), 'si' if mbr else 'no',
                    str(t / 'edfc')], check=True, stdout=subprocess.DEVNULL)
    dest = f'{img}@@{8192 * 512}' if mbr else str(img)
    subprocess.run(['mmd', '-i', dest, '::PRUEBAS'], check=True)
    for n, tam in archivos:
        f = t / 'tmp.bin'
        f.write_bytes(bytes((i * 31 + len(n)) & 0xFF for i in range(tam)))
        subprocess.run(['mcopy', '-i', dest, str(f), f'::{n}'], check=True)
    return img

fallos = []
def comprobar(cond, texto):
    print(('ok    ' if cond else 'FALLO ') + texto)
    if not cond:
        fallos.append(texto)

def particion(m, desp=8192 * 512):
    f = t / 'part.img'
    f.write_bytes(bytes(m.sd.img[desp:]) if isinstance(m, Maquina) else m[desp:])
    return f

def fsck(m, desp=8192 * 512):
    """Avisos de fsck.fat -n (sin el de la FSInfo «sin calcular», que es lo que deja el OS a propósito)."""
    r = subprocess.run(['fsck.fat', '-n', str(particion(m, desp))], capture_output=True, text=True)
    avisos = [l for l in r.stdout.split('\n') if l and not l.startswith('fsck.fat ') and 'files,' not in l
              and 'Free cluster summary uninitialized' not in l]
    return avisos + ([f'salida {r.returncode}'] if r.returncode else [])

def leer_archivo(m, ruta, desp=8192 * 512):
    f = t / 'sacado.bin'
    f.unlink(missing_ok=True)
    r = subprocess.run(['mcopy', '-n', '-i', str(particion(m, desp)), f'::{ruta}', str(f)], capture_output=True)
    return f.read_bytes() if r.returncode == 0 else None

def nombres_save(m, desp=8192 * 512):
    r = subprocess.run(['mdir', '-b', '-i', str(particion(m, desp)), '::EDFC/SAVE'], capture_output=True, text=True)
    return sorted(l.rsplit('/', 1)[-1] for l in r.stdout.split('\n') if l.strip())

etiquetas = {}
for linea in (pathlib.Path(a.os).parent / 'os.lbl').read_text().split('\n'):
    if linea.startswith('al '):
        _, dire, nombre = linea.split()
        etiquetas[nombre.lstrip('.')] = int(dire, 16)

def lista(pan):
    """Las entradas de la lista (filas 9-24), sin el cursor."""
    return [l[3:].lstrip(' ▶') for l in pan.split('\n') if 9 <= int(l[:2]) <= 24]

def cursor_en(pan, texto):
    return any(l[3:] == ' ▶' + texto for l in pan.split('\n') if 9 <= int(l[:2]) <= 24)

def sin_cursor(pan):
    return not any('▶' in l for l in pan.split('\n') if 9 <= int(l[:2]) <= 24)

def cabecera(pan):
    return ' '.join(next((l[3:] for l in pan.split('\n') if l[:2] == ' 7'), '').split())

def lista_raiz(pan):
    filas = [l[3:] for l in pan.split('\n')]
    return (any(l.strip().startswith('Raíz') and l.rstrip().endswith('1/1') for l in filas)
            and [l.strip(' ▶') for l in filas if l.startswith(' ') and l.strip(' ▶') in
                 ('EDFC/', 'PRUEBAS/', 'IRQ65', 'Super Mario Bros. (World)', 'ZELDA', 'NOTAS.TXT')]
            == ['EDFC/', 'PRUEBAS/', 'IRQ65', 'NOTAS.TXT', 'Super Mario Bros. (World)', 'ZELDA'])

def fila25(pan):
    return next((l[3:].strip() for l in pan.split('\n') if l[:2] == '25'), '')

def arrancar(img, sdhc=True, sd=None):
    m = Maquina(bios, sd or SD(pathlib.Path(img).read_bytes(), sdhc=sdhc))
    ok = m.arrancar_bios() == 'parada' and m.cpu.pc == 0x8000
    m.n_log = len(m.log)
    m.partidas = bytes(m.prgram[:0x12000])
    m.prg_antes = dict(m.escrituras_prgram)
    return m, ok

def estado(m, nombre):
    return m.prgram[0x18000 | (etiquetas[nombre] & 0x7FFF)]
def contadores(m):
    return estado(m, 'arranques'), estado(m, 'resets'), estado(m, 'vueltas')
def solo_lectura(m):
    ordenes = {e[0] for e in m.log[m.n_log:] if e[0].startswith('SD_')}
    return not m.sd.escrituras and ordenes <= {'SD_CMD0', 'SD_CMD8', 'SD_CMD55', 'SD_ACMD41', 'SD_CMD58', 'SD_CMD16',
                                               'SD_CMD17', 'SD_CMD18', 'SD_CMD12'}
PASOS = 2_500_000

def toca(m, mascara):
    m.pad = mascara; m.correr(30_000, nmi_cada=9000); m.pad = 0; m.correr(30_000, nmi_cada=9000)

def pulsa(m, mascara, despues=150_000):
    """Pulsa y espera a que la página nueva termine de subir a la PPU (2 filas por fotograma)."""
    toca(m, mascara)
    m.correr(despues, nmi_cada=9000)

ARCHIVOS = [('IRQ65.NES', 24592), ('Super Mario Bros. (World).nes', 40976), ('ZELDA.NES', 131088), ('NOTAS.TXT', 300)]

# ------------------------------------------------------------------ FAT32 con MBR, SDHC: el caso de la SD real
img32 = imagen('f32.img', 32, True, ARCHIVOS)
m, ok = arrancar(img32)
comprobar(ok, 'la BIOS salta a $8000')
r = m.correr(PASOS, nmi_cada=9000)
pan = m.pantalla()
comprobar(r == 'limite', 'el OS sigue corriendo (sin opcodes ilegales)')
comprobar('OS propio N8 - etapa 6' in pan and 'Arranque: frío (BIOS)' in pan and contadores(m) == (1, 0, 0),
          'encendido: FRIO, contadores 1/0/0')
comprobar(m.ppu_mask & 0x08 and m.ppu_ctrl & 0x80, 'fondo visible y NMI activa')
comprobar('SD: SDHC FAT32 clúster 01' in pan, 'tarjeta SDHC, FAT32')
comprobar(lista_raiz(pan), 'la raíz: cabecera «Raíz 1/1» y las 6 entradas, en orden alfabético (carpetas primero)')
comprobar(lista(pan) == ['EDFC/', 'PRUEBAS/', 'IRQ65', 'NOTAS.TXT', 'Super Mario Bros. (World)', 'ZELDA'],
          f'en la lista: {lista(pan)}')
comprobar('▶EDFC/' in pan and '.NES' not in pan and '.nes' not in pan,
          'cursor en la primera entrada; sin la extensión .nes (nombre largo y 8.3)')
comprobar(m.cpld[2] == 0x0B, f'reg 2 al terminar = $0B: rápido, tarjeta libre, SDHC (${m.cpld[2]:02X})')
comprobar(solo_lectura(m), 'solo órdenes de lectura; ninguna escritura en la tarjeta')
m.pad = 0x80 | 0x20
m.correr(60_000, nmi_cada=9000)
comprobar('Mando: A - S - - - - -' in m.pantalla(), 'el mando se ve en vivo (Select+A)')
m.pad = 0

# resets: en el OS, en ráfaga (alguno a mitad de la lectura de la SD) y vuelta de un juego
m.cpu.reset()
m.correr(PASOS, nmi_cada=9000)
comprobar('Arranque: reset' in m.pantalla() and contadores(m) == (2, 1, 0) and lista_raiz(m.pantalla()),
          'reset en el OS: RESET 2/1/0 y la SD se vuelve a leer bien')
for pasos in (500, 3000, 20_000, 60_000, 150_000, 400_000):      # los últimos caen dentro de la lectura de la SD
    m.correr(pasos, nmi_cada=9000)
    m.cpu.reset()
m.correr(PASOS, nmi_cada=9000)
pan = m.pantalla()
comprobar('Arranque: reset' in pan and contadores(m) == (8, 7, 0) and lista_raiz(pan) and 'error' not in pan,
          f'ráfaga de 6 resets, algunos a mitad de lectura: contadores {contadores(m)} y la SD bien')
m.prgram[0x18000 | (etiquetas['en_juego'] & 0x7FFF)] = 1
m.cpld[9] = 0x15
m.cpld[2] = 0x0D                          # tarjeta seleccionada y en ráfaga, como si se hubiera cortado una lectura
for i in range(0x800):
    m.ram[i] = 0xA5
m.cpu.reset()
m.correr(PASOS, nmi_cada=9000)
pan = m.pantalla()
comprobar('Arranque: vuelta de juego' in pan and contadores(m) == (9, 7, 1) and lista_raiz(pan),
          'vuelta de un juego: VUELTA DE JUEGO 9/7/1 y la SD bien')
comprobar(estado(m, 'en_juego') == 0 and m.cpld[9] == 1, 'marca en_juego borrada y reg 9 = 01')
cpld = [e for e in m.log[m.n_log:] if e[0] == 'CPLD']
comprobar(all(e[1] in (2, 9) for e in cpld) and all(e[3] == 1 for e in cpld if e[1] == 9),
          'del CPLD solo escribe el reg 2 (SD) y reg 9 = 01')
otros = [e for e in m.log[m.n_log:] if e[0] in ('4402', 'ESCRITURA_EN_FLASH', 'USB_TX') or (e[0] == 'FPGA' and e[1] not in (129, 130))]
comprobar(not otros, f'no toca la flash, $4402 ni otros registros del FPGA que el 129 (marca de partida) y el 130 ({otros[:3]})')
tocados = {b for b, n in m.escrituras_prgram.items() if n != m.prg_antes.get(b, 0)}
ovl = pathlib.Path(a.os).read_bytes()[0x5400:0x6400]       # el código del FDS: al encender va al banco 8, en $7000
comprobar(tocados <= set(range(12)) and bytes(m.prgram[0x10000:0x11000]) == m.partidas[0x10000:0x11000]
          and bytes(m.prgram[0x11000:0x12000]) == ovl,
          f'en la PRG-RAM solo escribe el orden (claves en los bancos 0-7, posiciones en 9-11) y, del banco 8, solo el código del FDS en $7000 ({sorted(tocados)})')
comprobar(solo_lectura(m) and bytes(m.sd.img) == pathlib.Path(img32).read_bytes(), 'la imagen de la SD queda idéntica')

# ------------------------------------------------------------------ otras tarjetas
m, ok = arrancar(img32, sdhc=False)
m.correr(PASOS, nmi_cada=9000)
pan = m.pantalla()
comprobar('SD: SDSC FAT32' in pan and lista_raiz(pan) and m.cpld[2] == 0x03,
          'SDSC (direcciones en bytes): misma lista; reg 2 = $03')

m, ok = arrancar(imagen('f16.img', 16, True, ARCHIVOS))
m.correr(PASOS, nmi_cada=9000)
pan = m.pantalla()
comprobar('SD: SDHC FAT16 clúster' in pan and lista_raiz(pan), 'FAT16 con MBR')

m, ok = arrancar(imagen('f32nombr.img', 32, False, ARCHIVOS))
m.correr(PASOS, nmi_cada=9000)
pan = m.pantalla()
comprobar('FAT32' in pan and lista_raiz(pan), 'FAT32 sin MBR (sin particiones)')

muchos = [(f'J{i:03d}.NES', 16 + i) for i in range(60)]
for fat in (32, 16):
    m, ok = arrancar(imagen(f'muchos{fat}.img', fat, True, muchos))
    m.correr(PASOS + 1_500_000, nmi_cada=9000)
    pan = m.pantalla()
    comprobar(cabecera(pan) == 'Raíz 1/4' and lista(pan)[-1] == 'J013' and len(lista(pan)) == 16 and 'error' not in pan,
              f'FAT{fat}: raíz de 62 entradas (varios sectores{" y cadena de clústeres" if fat == 32 else ""}): 4 páginas de 16')
    for _ in range(3):
        pulsa(m, 0x02)                    # izquierda: de la 1 a la 4, 3 y 2
    pan = m.pantalla()
    comprobar(cabecera(pan) == 'Raíz 2/4' and lista(pan) == [f'J{i:03d}' for i in range(14, 30)] and cursor_en(pan, 'J014'),
              f'FAT{fat}: izquierda da la vuelta (1 -> 4 -> 3 -> 2) y la página 2 son J014-J029')
    pulsa(m, 0x01)
    pulsa(m, 0x01)
    pan = m.pantalla()
    comprobar(cabecera(pan) == 'Raíz 4/4' and lista(pan) == [f'J{i:03d}' for i in range(46, 60)],
              f'FAT{fat}: derecha dos veces: la última página, con 14')
    comprobar(solo_lectura(m), f'FAT{fat}: solo lectura')

class SDmuda(SD):
    def byte(self, v, cs):
        return 0xFF
m, ok = arrancar(img32)
m.sd.__class__ = SDmuda                   # la tarjeta deja de contestar después de que la BIOS cargue el OS
r = m.correr(PASOS, nmi_cada=9000)
pan = m.pantalla()
comprobar(r == 'limite' and 'SD: error 01 R1=FF' in pan and 'Mando:' in pan and m.ppu_mask & 0x08,
          'tarjeta muda: ERROR 01 en pantalla y el OS sigue vivo')

# ------------------------------------------------------------------ etapa 3: lanzar juegos
def rom(prg16, chr8, mapper, byte6=0, trainer=False, semilla=1, cola=None):
    """ROM iNES de prueba: datos reconocibles y, en el vector de reset ($C000 del último banco), un programa que
    deja una marca en $0700 (A5, el primer byte de la PRG y S) y se queda en un bucle."""
    prg = bytearray((i * 13 + semilla) & 0xFF for i in range(prg16 * 16384))
    cod = bytes([0xA9, 0xA5, 0x8D, 0x00, 0x07, 0xAD, 0x00, 0x80, 0x8D, 0x01, 0x07, 0xBA, 0x8E, 0x02, 0x07, 0x4C, 0x0F, 0xC0])
    prg[-0x4000:-0x4000 + len(cod)] = cod
    prg[-6:] = bytes([0x0F, 0xC0, 0x00, 0xC0, 0x0F, 0xC0])
    chr_ = bytes((i * 3 + semilla) & 0xFF for i in range(chr8 * 8192))
    cab = bytes([0x4E, 0x45, 0x53, 0x1A, prg16, chr8, (mapper & 15) << 4 | byte6 | (4 if trainer else 0), mapper & 0xF0]) + bytes(8)
    if cola is not None:                  # bytes 7-15 tal cual (NES 2.0, basura de cabeceras antiguas)
        cab = cab[:7] + bytes(cola)
    return cab + (bytes(range(256)) * 2 if trainer else b'') + bytes(prg) + chr_, bytes(prg), chr_

maprout = bytearray([0xFF]) * 512
for mp, r in ((0, 100), (4, 100), (1, 101), (219, 105), (254, 254)):
    maprout[mp] = r
(t / 'edfc/MAPROUT.BIN').write_bytes(maprout)
rbf100 = bytes((i * 7 + 1) & 0xFF for i in range(51200))
rbf105 = bytes((i * 5 + 3) & 0xFF for i in range(76288 - 300))        # tamaño que no es múltiplo de 512
ROMS = [('JUEGO.NES', rom(2, 1, 0, byte6=1)), ('CHRRAM.NES', rom(1, 0, 0, semilla=2)),
        ('MMC3.NES', rom(8, 8, 4, byte6=2, semilla=3)), ('TRAINER.NES', rom(2, 1, 0, trainer=True, semilla=4)),
        ('M219.NES', rom(4, 2, 219, semilla=5)), ('NOTAS.TXT', (b'no soy una ROM' * 40, b'', b'')),
        ('SINRBF.NES', rom(2, 1, 65, semilla=6)), ('FALTA.NES', rom(2, 1, 1, semilla=7)),
        # la cabecera de «219 Toy Story (Asia) (En) (Pirate).nes»: NES 2.0 con región y mando en los bytes 12 y 15
        ('NES20.NES', rom(4, 2, 219, semilla=8, cola=[0xD8, 0, 0, 0, 0, 2, 0, 0, 1])),
        # «DiskDude!» en los bytes 7-15: solo vale el nibble bajo (mapper 4)
        ('DUDE.NES', rom(8, 8, 0x44, semilla=9, cola=b'DiskDude!'))]

def imagen3(nombre, fragmentar=False, fragmentar_roms=(), fat=32):
    img = t / nombre
    subprocess.run(['sh', str(RAIZ / 'tools/bios/hacer_sd.sh'), str(img), str(fat), 'si', str(t / 'edfc')], check=True,
                   stdout=subprocess.DEVNULL)
    dest = f'{img}@@{8192 * 512}'
    subprocess.run(['mmd', '-i', dest, '::PRUEBAS'], check=True)
    for n, datos in (('EDFC/MAPS/100.RBF', rbf100), ('EDFC/MAPS/105.RBF', rbf105)) + tuple((n, r[0]) for n, r in ROMS):
        f = t / 'tmp.bin'
        f.write_bytes(datos)
        subprocess.run(['mcopy', '-i', dest, str(f), f'::{n}'], check=True)
    if fragmentar:
        subprocess.run([sys.executable, '-I', str(RAIZ / 'tools/bios/fragmentar.py'), str(img), '8192',
                        'EDFC/MAPS/100.RBF'], check=True, stdout=subprocess.DEVNULL)
    if fragmentar_roms:
        subprocess.run([sys.executable, '-I', str(RAIZ / 'tools/bios/fragmentar.py'), str(img), '8192',
                        *fragmentar_roms], check=True, stdout=subprocess.DEVNULL)
    return img


def visto(nombre):
    """Cómo sale un archivo en el menú: sin «.nes» ni «.fds»."""
    return nombre[:-4] if nombre.lower().endswith(('.nes', '.fds')) else nombre

def ir_a_nombre(m, texto, maximo=40):
    """Lleva el cursor a la fila `texto`: la busca en la página (derecha pasa a la siguiente, dando la vuelta) y
    sube o baja hasta ella. No depende del orden de la lista."""
    for _ in range(maximo):
        pan = m.pantalla()
        filas = lista(pan)
        if texto in filas:
            actual = next((i for i, l in enumerate(filas) if cursor_en(pan, l)), 0)
            for _ in range(abs(filas.index(texto) - actual)):
                toca(m, 0x04 if filas.index(texto) > actual else 0x08)
            m.correr(60_000, nmi_cada=9000)
            return cursor_en(m.pantalla(), texto)
        pulsa(m, 0x01)
    return False

def menu3(img, nombre):
    """Arranca, baja el cursor hasta `nombre` y devuelve la máquina."""
    m, ok = arrancar(img)
    m.correr(PASOS, nmi_cada=9000)
    m.pc_en_config.clear()
    m.n_cfg = len(m.fpga_cfgs)
    ir_a_nombre(m, visto(nombre))
    m.n_cfg = len(m.fpga_cfgs)
    return m

def lanzar(m, boton=0x80):
    m.pad = boton
    r = m.correr(6_000_000, lambda m: m.mapper != 0xFF, nmi_cada=9000)
    m.pad = 0
    return r == 'parada'

img3 = imagen3('e3.img')
for nombre, prg16, chr8, mapper, r132, r133, r134, rbf in (
        ('JUEGO.NES', 2, 1, 0, 1, 0, 1, rbf100), ('CHRRAM.NES', 1, 0, 0, 0, 0xFF, 0, rbf100),
        ('MMC3.NES', 8, 8, 4, 7, 7, 2, rbf100), ('TRAINER.NES', 2, 1, 0, 1, 0, 0, rbf100),
        ('M219.NES', 4, 2, 219, 3, 1, 0x10, rbf105), ('NES20.NES', 4, 2, 219, 3, 1, 0x10, rbf105),
        ('DUDE.NES', 8, 8, 4, 7, 7, 0, rbf100)):
    _, prg, chr_ = dict(ROMS)[nombre]
    m = menu3(img3, nombre)
    comprobar(('▶' + nombre.split('.')[0]) in m.pantalla(), f'{nombre}: el cursor llega a la entrada')
    ok = lanzar(m)
    comprobar(ok and m.mapper == mapper and m.cpu.pc < 0x0800,
              f'{nombre}: reg 131 = {mapper} (el de la cabecera), escrito desde la RAM')
    cfg = m.fpga_cfgs[m.n_cfg:]
    comprobar(len(cfg) == 1 and bytes(cfg[0][:len(rbf)]) == rbf and len(cfg[0]) >= len(rbf) + 256,
              f'{nombre}: el FPGA recibe el RBF entero y relojes de sobra ({len(cfg[0]) if cfg else 0} bytes)')
    comprobar(not m.pc_en_config, f'{nombre}: nada se ejecuta en $8000-$FFFF mientras se configura el FPGA')
    r9 = [(e[2], e[3]) for e in m.log[m.n_log:] if e[0] == 'CPLD' and e[1] == 9]
    comprobar((1, 0) in r9 and r9[-1] == (0, 1) and m.cpld[9] == 1, f'{nombre}: reg 9 a 0 durante la carga y de vuelta a 1')
    comprobar(bytes(m.prgrom[:len(prg)]) == prg, f'{nombre}: la PRG ({len(prg) // 1024} KiB) queda igual en la SRAM')
    comprobar(bytes(m.chr[:len(chr_)]) == chr_, f'{nombre}: la CHR ({len(chr_) // 1024} KiB) queda igual en la SRAM')
    comprobar((m.fpga.get(132), m.fpga.get(133), m.fpga.get(134), m.fpga.get(136)) == (r132, r133, r134, 0),
              f'{nombre}: regs 132/133/134/136 = {r132:02X}/{r133:02X}/{r134:02X}/00')
    pila = nombre == 'MMC3.NES'           # byte 6 = 2: con pila, crea EDFC/SAVE/MMC3.SRM
    comprobar(estado(m, 'en_juego') == 1 and (pila or solo_lectura(m)) and not [e for e in m.log[m.n_log:] if e[0] == 'ESCRITURA_EN_FLASH'],
              f'{nombre}: marca en_juego puesta; {"crea su partida" if pila else "la SD solo se lee"}; nada escrito en la flash')
    if mapper == 0:
        m.correr(3000)
        comprobar(bytes(m.ram[0x700:0x703]) == bytes([0xA5, prg[0], 0xFD]), f'{nombre}: el juego corre (marca en la RAM, S = $FD)')
        m.reset_consola()
        m.correr(PASOS, nmi_cada=9000)
        pan = m.pantalla()
        comprobar('Arranque: vuelta de juego' in pan and contadores(m) == (2, 0, 1) and ('▶' + nombre.split('.')[0]) in pan,
                  f'{nombre}: tras el reset, «vuelta de juego» 2/0/1 y el cursor sobre el juego')

for nombre, mensaje in (('NOTAS.TXT', 'No es una ROM iNES'), ('SINRBF.NES', 'Mapper sin RBF: 41'), ('FALTA.NES', 'No encuentro el RBF 101')):
    m = menu3(img3, nombre)
    ok = lanzar(m)
    m.correr(200_000, nmi_cada=9000)
    comprobar(not ok and mensaje in m.pantalla() and m.ppu_mask & 0x08 and not m.fpga_cfgs[m.n_cfg:],
              f'{nombre}: no se lanza, «{mensaje}», el FPGA no se toca y el menú sigue')
    toca(m, 0x08)
    comprobar('▶' in m.pantalla() and estado(m, 'en_juego') == 0, f'{nombre}: el cursor se sigue moviendo')
m, ok = arrancar(img3)
m.correr(PASOS, nmi_cada=9000)
lanzo = lanzar(m)
m.correr(1_000_000, nmi_cada=9000)
pan = m.pantalla()
comprobar(not lanzo and cabecera(pan) == 'EDFC 1/1' and lista(pan) == ['MAPS/', 'SAVE/', 'MAPROUT.BIN', 'OS.BIN']
          and cursor_en(pan, 'MAPS/') and m.ppu_mask & 0x08, f'A sobre EDFC: entra en la carpeta ({lista(pan)})')
pulsa(m, 0x40, 1_000_000)
pan = m.pantalla()
comprobar(cabecera(pan) == 'Raíz 1/1' and cursor_en(pan, 'EDFC/'), 'B: vuelve a la raíz con el cursor sobre EDFC')
pulsa(m, 0x40, 1_000_000)
pan = m.pantalla()
comprobar(cabecera(pan) == 'Raíz 1/1' and cursor_en(pan, 'EDFC/') and solo_lectura(m), 'B en la raíz: no hace nada')
m = menu3(img3, 'JUEGO.NES')
comprobar(not lanzar(m, 0x80 | 0x20), 'Select+A (reset del kit Lava) no lanza el juego')
m = menu3(img3, 'JUEGO.NES')
comprobar(lanzar(m, 0x10) and m.mapper == 0, 'Start también lanza')

# ------------------------------------------------------------------ etapa 4: carpetas y nombres largos
def imagen4(nombre):
    img = imagen3(nombre)
    dest = f'{img}@@{8192 * 512}'
    def copia(datos, destino):
        f = t / 'tmp.bin'
        f.write_bytes(datos)
        subprocess.run(['mcopy', '-i', dest, str(f), destino], check=True)
    subprocess.run(['mmd', '-i', dest, '::Juegos', '::Juegos/Mapper 4 (MMC3)', '::Juegos/Vacía'], check=True)
    for i in range(40):
        copia(bytes(100), f'::Juegos/Juego de prueba número {i:02d}.nes')
    copia(bytes(50), '::Juegos/borrado con nombre largo.nes')
    subprocess.run(['mdel', '-i', dest, '::Juegos/borrado con nombre largo.nes'], check=True)
    copia(dict(ROMS)['MMC3.NES'][0], '::Juegos/Mapper 4 (MMC3)/Súper Prueba ñ (España).nes')
    copia(bytes(10), '::Juegos/Mapper 4 (MMC3)/._Súper Prueba ñ (España).nes')
    copia(bytes(10), '::Juegos/Mapper 4 (MMC3)/OCULTO.NES')
    subprocess.run(['mattrib', '-i', dest, '+h', '::Juegos/Mapper 4 (MMC3)/OCULTO.NES'], check=True)
    copia(bytes(10), '::Juegos/Mapper 4 (MMC3)/Un nombre larguísimo que no cabe en la pantalla.nes')
    copia(bytes(10), '::Juegos/Mapper 4 (MMC3)/zelda.nes')
    copia(bytes(10), '::Juegos/Mapper 4 (MMC3)/Ölçü àèìòù ÇÄÖ.nes')
    return img

img4 = imagen4('e4.img')
m, ok = arrancar(img4)
m.correr(PASOS, nmi_cada=9000)
pan = m.pantalla()
comprobar(lista(pan)[:3] == ['EDFC/', 'Juegos/', 'PRUEBAS/'], 'la carpeta «Juegos» (nombre largo con minúsculas), con las carpetas')
ir_a_nombre(m, 'Juegos/')
comprobar(cursor_en(m.pantalla(), 'Juegos/'), 'el cursor llega a Juegos/')
pulsa(m, 0x80, 2_000_000)
pan = m.pantalla()
comprobar(cabecera(pan) == 'Juegos 1/3' and cursor_en(pan, 'Mapper 4 (MMC3)/')
          and lista(pan) == ['Mapper 4 (MMC3)/', 'Vacía/'] + [f'Juego de prueba número {i:02d}' for i in range(14)],
          'dentro de Juegos: cabecera «Juegos 1/3», carpetas, acentos, 16 por página; el borrado no sale')
comprobar(m.rojas() == {9}, f'la fila del cursor (la 9) va en rojo y las demás no ({sorted(m.rojas())})')
toca(m, 0x08)
m.correr(150_000, nmi_cada=9000)
pan = m.pantalla()
comprobar(cabecera(pan) == 'Juegos 1/3' and cursor_en(pan, 'Mapper 4 (MMC3)/'),
          'arriba en la primera fila: el cursor se queda (no cambia de página)')
for _ in range(20):
    toca(m, 0x04)
m.correr(150_000, nmi_cada=9000)
pan = m.pantalla()
comprobar(cabecera(pan) == 'Juegos 1/3' and cursor_en(pan, 'Juego de prueba número 13') and m.rojas() == {24},
          f'abajo hasta el final: se para en la última fila de la página, que va en rojo ({sorted(m.rojas())})')
for _ in range(15):
    toca(m, 0x08)
m.correr(150_000, nmi_cada=9000)
comprobar(cursor_en(m.pantalla(), 'Mapper 4 (MMC3)/') and m.rojas() == {9}, 'y arriba vuelve a la primera fila')
pulsa(m, 0x02)
comprobar(cabecera(m.pantalla()) == 'Juegos 3/3' and cursor_en(m.pantalla(), 'Juego de prueba número 30') and m.rojas() == {9},
          'izquierda desde la página 1: la 3 (dando la vuelta), con la fila del cursor en rojo')
pulsa(m, 0x01)
comprobar(cabecera(m.pantalla()) == 'Juegos 1/3' and cursor_en(m.pantalla(), 'Mapper 4 (MMC3)/'), 'derecha: vuelve a la 1')
pulsa(m, 0x01)
comprobar(cabecera(m.pantalla()) == 'Juegos 2/3' and cursor_en(m.pantalla(), 'Juego de prueba número 14'), 'derecha: página 2')
pulsa(m, 0x02)
toca(m, 0x04)
pulsa(m, 0x80, 1_000_000)
pan = m.pantalla()
comprobar(cabecera(pan) == 'Vacía' and lista(pan) == ['(carpeta vacía)'] and sin_cursor(pan), 'carpeta vacía: aviso y sin cursor')
pulsa(m, 0x40, 2_000_000)
comprobar(cursor_en(m.pantalla(), 'Vacía/') and cabecera(m.pantalla()) == 'Juegos 1/3', 'B: vuelve a Juegos con el cursor sobre Vacía/')
toca(m, 0x08)
pulsa(m, 0x80, 1_000_000)
pan = m.pantalla()
comprobar(cabecera(pan) == 'Mapper 4 (MMC3) 1/1' and 'Súper Prueba ñ (España)' in lista(pan), 'nombre largo con ú y ñ')
comprobar(lista(pan) == ['Olcü aeiou CAO', 'Súper Prueba ñ (España)', 'Un nombre larguísimo que no…', 'zelda'],
          f'sin «._» de macOS ni ocultos; cortado con «…»; «zelda» (8.3 en minúsculas); otros acentos sin acento: {lista(pan)}')
comprobar(solo_lectura(m), 'navegar por carpetas: solo lectura')
ir_a_nombre(m, 'Súper Prueba ñ (España)')
m.n_cfg = len(m.fpga_cfgs)
_, prg, chr_ = dict(ROMS)['MMC3.NES']
ok = lanzar(m)
comprobar(ok and m.mapper == 4 and bytes(m.prgrom[:len(prg)]) == prg and bytes(m.chr[:len(chr_)]) == chr_,
          'lanza un juego de una subcarpeta (2 niveles): MMC3, PRG y CHR iguales')
m.reset_consola()
m.correr(PASOS, nmi_cada=9000)
pan = m.pantalla()
comprobar('Arranque: vuelta de juego' in pan and cabecera(pan) == 'Mapper 4 (MMC3) 1/1' and cursor_en(pan, 'Súper Prueba ñ (España)'),
          'tras el reset: vuelve a la subcarpeta con el cursor sobre el juego')
pulsa(m, 0x40, 2_000_000)
comprobar(cursor_en(m.pantalla(), 'Mapper 4 (MMC3)/') and cabecera(m.pantalla()) == 'Juegos 1/3', 'B: a Juegos, cursor sobre la subcarpeta')
pulsa(m, 0x40, 1_000_000)
comprobar(cursor_en(m.pantalla(), 'Juegos/') and cabecera(m.pantalla()) == 'Raíz 1/1', 'B: a la raíz, cursor sobre Juegos')
m.cpu.reset()
m.correr(PASOS, nmi_cada=9000)
comprobar('Arranque: reset' in m.pantalla() and 'Raíz' in m.pantalla(), 'reset en el menú: sigue en la carpeta (raíz)')
comprobar(fsck(m) == [] and leer_archivo(m, 'EDFC/SAVE/Súper Prueba ñ (España).srm') == bytes([0xFF]) * 8192,
          'la partida del juego de la subcarpeta: «Súper Prueba ñ (España).srm», y la FAT sin errores')


# ------------------------------------------------------------------ etapa 5: partidas con pila
PILA = [('Juego con pila (USA).nes', rom(2, 1, 0, byte6=2, semilla=11)),
        ('Otro juego (Japan).nes', rom(2, 1, 0, byte6=2, semilla=12)),
        # NES 2.0 con 32 KiB de PRG-NVRAM (byte 10 = $90: 64 << 9)
        ('Grande NES 2.0.nes', rom(2, 1, 0, byte6=2, semilla=13, cola=[0x08, 0, 0, 0x90, 0, 0, 0, 0, 0]))]
OTRA = bytes((i * 7 + 5) & 0xFF for i in range(8192))          # partida que ya estaba (copiada de un emulador)
FF8 = bytes([0xFF]) * 8192

def imagen5(nombre, fat=32, relleno=0, ocupar=False, sin_save=False):
    img = imagen3(nombre, fat=fat)
    dest = f'{img}@@{8192 * 512}'
    def copia(datos, destino):
        f = t / 'tmp.bin'
        f.write_bytes(datos)
        subprocess.run(['mcopy', '-i', dest, str(f), destino], check=True)
    for n, r in PILA:
        copia(r[0], f'::{n}')
    if sin_save:
        subprocess.run(['mrd', '-i', dest, '::EDFC/SAVE'], check=True)
    else:
        copia(OTRA, '::EDFC/SAVE/OTRO JUEGO (Japan).SRM')           # mayúsculas distintas: tiene que valer
    for i in range(relleno):
        copia(b'x', f'::EDFC/SAVE/R{i:02d}.BIN')
    if ocupar:                                                      # casi llena: menos de 8 KiB libres
        out = subprocess.run(['mdir', '-i', dest, '::'], capture_output=True, text=True).stdout
        libres = int(out.strip().split('\n')[-1].split('bytes')[0].replace(' ', ''))
        f = t / 'grande.bin'
        with open(f, 'wb') as g:
            g.truncate(libres - 2048)
        subprocess.run(['mcopy', '-i', dest, str(f), '::RELLENO.BIN'], check=True)
    return img

def encender(img_bytes, prgram=None, sdhc=True, sd=None):
    m = Maquina(bios, sd or SD(img_bytes, sdhc=sdhc), prgram=prgram)
    ok = m.arrancar_bios() == 'parada' and m.cpu.pc == 0x8000
    m.n_log = len(m.log)
    m.correr(PASOS, nmi_cada=9000)
    m.n_cfg = len(m.fpga_cfgs)
    return m, ok

def ir_a(m, nombre):
    """Baja hasta la ROM `nombre` de PILA."""
    ir_a_nombre(m, visto(nombre))

def suma_marca(r):
    """La suma de partida.s: $A5 + bytes 17..0 con ADC (el acarreo se arrastra)."""
    a, c = 0xA5, 0
    for x in reversed(r[0x10000:0x10012]):
        v = a + x + c
        a, c = v & 0xFF, v >> 8
    return a

def marca(m):
    return bytes(m.prgram[0x10000:0x10004]) == b'N8SV'

def escrituras(m):
    return [e for e in m.log[m.n_log:] if e[0] == 'SD_CMD24']

def volver(m):
    m.correr(3000)
    m.reset_consola()
    m.correr(PASOS, nmi_cada=9000)
    return m.pantalla()

JP = 'Juego con pila (USA)'
img5 = imagen5('e5.img')
m, ok = encender(pathlib.Path(img5).read_bytes())
ir_a(m, JP + '.nes')
comprobar(cursor_en(m.pantalla(), JP), 'partidas: el cursor llega al juego con pila')
m.prgram[:0x2000] = bytes(0x2000)
ok = lanzar(m)
comprobar(ok and m.mapper == 0 and leer_archivo(m, f'EDFC/SAVE/{JP}.srm') == FF8 and bytes(m.prgram[:0x2000]) == FF8,
          'juego con pila sin partida: crea «EDFC/SAVE/Juego con pila (USA).srm» (8 KiB a $FF) y la PRG-RAM queda a $FF')
comprobar(marca(m) and fsck(m) == [], 'marca de partida pendiente en el banco 8; fsck.fat sin errores')
comprobar(nombres_save(m) == sorted([f'{JP}.srm', 'OTRO JUEGO (Japan).SRM']), f'EDFC/SAVE: {nombres_save(m)}')
comprobar(not [e for e in m.log if e[0] == 'ESCRITURA_EN_FLASH'], 'nada escrito en la flash')
PAT = bytes((i * 11 + 3) & 0xFF for i in range(8192))
m.prgram[:0x2000] = PAT                    # lo que guarda el juego
pan = volver(m)
comprobar('Arranque: vuelta de juego' in pan and 'Partida guardada' in pan and cursor_en(pan, JP),
          'RESET en el juego: «Partida guardada», con el cursor sobre el juego')
comprobar(leer_archivo(m, f'EDFC/SAVE/{JP}.srm') == PAT and not marca(m) and fsck(m) == [],
          'el .srm tiene lo que dejó el juego, la marca se borra y la FAT sigue bien')
n_esc = len(escrituras(m))
m.prgram[:0x2000] = bytes(0x2000)
m.n_cfg = len(m.fpga_cfgs)
ok = lanzar(m)
comprobar(ok and bytes(m.prgram[:0x2000]) == PAT and len(escrituras(m)) == n_esc and len(nombres_save(m)) == 2,
          'al lanzarlo otra vez carga la partida guardada, sin escribir nada ni crear otra')
PAT2 = bytes((i * 5 + 9) & 0xFF for i in range(8192))
m.prgram[:0x2000] = PAT2
ram = bytearray(m.prgram)
ram[0x12000:] = bytes(len(ram) - 0x12000)  # al encender, la BIOS vuelve a cargar el OS
m2, ok = encender(bytes(m.sd.img), prgram=ram)
pan = m2.pantalla()
comprobar(ok and 'Arranque: frío (BIOS)' in pan and 'Partida guardada' in pan and leer_archivo(m2, f'EDFC/SAVE/{JP}.srm') == PAT2
          and not marca(m2) and fsck(m2) == [], 'apagado dentro del juego (RAM con pila): al encender se guarda la partida')
m3, ok = encender(bytes(m.sd.img))           # RAM sin pila: llega a cero, no hay marca
comprobar(ok and 'Partida' not in m3.pantalla() and solo_lectura(m3), 'encendido con la RAM a cero: no escribe nada')
mal = bytearray(ram)
mal[0x10012] ^= 1                            # marca con la suma mal
comprobar(suma_marca(ram) == ram[0x10012], 'la suma de la marca se calcula como en partida.s')
m3, ok = encender(bytes(m.sd.img), prgram=mal)
comprobar(ok and 'Partida' not in m3.pantalla() and solo_lectura(m3), 'marca con la suma de comprobación mal: no escribe nada')
mal = bytearray(ram)
mal[0x1000A] ^= 0x40                         # marca que apunta a otro clúster (con su suma bien)
mal[0x10012] = suma_marca(mal)
m3, ok = encender(bytes(m.sd.img), prgram=mal)
comprobar(ok and 'Partida no encontrada' in m3.pantalla() and solo_lectura(m3) and not marca(m3),
          'marca que no coincide con el archivo: «Partida no encontrada», no escribe y la borra')

m, ok = encender(pathlib.Path(img5).read_bytes())
ir_a(m, 'Otro juego (Japan).nes')
ok = lanzar(m)
comprobar(ok and bytes(m.prgram[:0x2000]) == OTRA and len(nombres_save(m)) == 1 and not escrituras(m),
          'partida que ya estaba («OTRO JUEGO (Japan).SRM», otras mayúsculas): se carga, sin crear nada')
m, ok = encender(pathlib.Path(img5).read_bytes())
ir_a(m, 'Grande NES 2.0.nes')
ok = lanzar(m)
comprobar(ok and leer_archivo(m, 'EDFC/SAVE/Grande NES 2.0.srm') == bytes([0xFF]) * 32768 and bytes(m.prgram[:0x8000]) == bytes([0xFF]) * 32768,
          'NES 2.0 con 32 KiB de PRG-NVRAM: partida de 32 KiB (4 bancos de la PRG-RAM)')
PAT32 = bytes((i * 3 + (i >> 9)) & 0xFF for i in range(32768))
m.prgram[:0x8000] = PAT32
pan = volver(m)
comprobar('Partida guardada' in pan and leer_archivo(m, 'EDFC/SAVE/Grande NES 2.0.srm') == PAT32 and fsck(m) == [],
          'los 32 KiB se guardan al volver')
m, ok = encender(pathlib.Path(img5).read_bytes())
ir_a_nombre(m, 'MMC3')
ok = lanzar(m)
comprobar(ok and 'MMC3.SRM' in nombres_save(m) and leer_archivo(m, 'EDFC/SAVE/MMC3.SRM') == FF8 and fsck(m) == [],
          'ROM con nombre 8.3 (MMC3.NES): su partida es MMC3.SRM, sin nombre largo')

# carpeta SAVE casi llena (clúster de 512 bytes = 16 entradas): la partida nueva empieza en el clúster y sigue en otro
m, ok = encender(pathlib.Path(imagen5('e5dir.img', relleno=9)).read_bytes())
ir_a(m, JP + '.nes')
ok = lanzar(m)
comprobar(ok and leer_archivo(m, f'EDFC/SAVE/{JP}.srm') == FF8 and fsck(m) == [] and len(nombres_save(m)) == 11,
          'EDFC/SAVE sin sitio: se le añade un clúster y el nombre largo queda partido entre los dos; fsck.fat bien')
m.prgram[:0x2000] = PAT
pan = volver(m)
comprobar('Partida guardada' in pan and leer_archivo(m, f'EDFC/SAVE/{JP}.srm') == PAT, 'y se guarda bien al volver')

# sin la carpeta EDFC/SAVE (la SD de la v0.4.0-beta no la trae): se crea
m, ok = encender(pathlib.Path(imagen5('e5sinsave.img', sin_save=True)).read_bytes())
ir_a(m, JP + '.nes')
ok = lanzar(m)
comprobar(ok and nombres_save(m) == [f'{JP}.srm'] and leer_archivo(m, f'EDFC/SAVE/{JP}.srm') == FF8 and fsck(m) == [],
          'sin EDFC/SAVE: crea la carpeta («.» y «..») y la partida; fsck.fat sin errores')

# FAT16 y SDSC
m, ok = encender(pathlib.Path(imagen5('e5f16.img', fat=16)).read_bytes())
ir_a(m, JP + '.nes')
ok = lanzar(m)
m.prgram[:0x2000] = PAT
pan = volver(m)
comprobar(ok and 'FAT16' in pan and 'Partida guardada' in pan and leer_archivo(m, f'EDFC/SAVE/{JP}.srm') == PAT and fsck(m) == [],
          'FAT16: crea, guarda al volver y fsck.fat sin errores')
m, ok = encender(pathlib.Path(img5).read_bytes(), sdhc=False)
ir_a(m, JP + '.nes')
ok = lanzar(m)
m.prgram[:0x2000] = PAT
pan = volver(m)
comprobar(ok and 'SDSC' in pan and 'Partida guardada' in pan and leer_archivo(m, f'EDFC/SAVE/{JP}.srm') == PAT and fsck(m) == [],
          'SDSC (direcciones en bytes): crea y guarda')

# tarjeta llena
m, ok = encender(pathlib.Path(imagen5('e5llena.img', fat=16, ocupar=True)).read_bytes())
ir_a(m, JP + '.nes')
ok = lanzar(m)
m.correr(200_000, nmi_cada=9000)
comprobar(not ok and 'SD llena: no cabe la partida' in m.pantalla() and not m.fpga_cfgs[m.n_cfg:] and fsck(m) == [],
          'SD sin sitio: «SD llena», no lanza y la FAT queda bien')

# tarjeta que no deja escribir (protegida): la marca se queda y no se lanza nada hasta guardar
class SDprotegida(SD):
    def byte(self, v, cs):
        if cs and self.modo == 'escribir' and self.wbuf is not None and len(self.wbuf) == 514:
            self.wbuf = None
            self.modo = None
            self.salida.extend([0x0D, 0xFF])           # bloque rechazado (error de escritura)
            return 0xFF
        return super().byte(v, cs)
m, ok = encender(pathlib.Path(img5).read_bytes())
ir_a(m, JP + '.nes')
ok = lanzar(m)
m.prgram[:0x2000] = PAT
m.sd.__class__ = SDprotegida
pan = volver(m)
comprobar('Partida no guardada: 0B' in pan and marca(m), 'tarjeta que no deja escribir: «Partida no guardada: 0B» y la marca se queda')
comprobar(lista(pan)[:4] == ['EDFC/', 'PRUEBAS/', 'JUEGO', 'CHRRAM'] and bytes(m.prgram[:0x2000]) == PAT,
          'con la partida sin guardar en la RAM, la lista sale en el orden de la FAT (sin claves en la PRG-RAM)')
toca(m, 0x08)                                # arriba: a NOTAS.TXT... el cursor está en el juego; subir y bajar
toca(m, 0x04)
m.n_cfg = len(m.fpga_cfgs)
lanzo = lanzar(m)
m.correr(200_000, nmi_cada=9000)
comprobar(not lanzo and 'Sin guardar la anterior: 0B' in m.pantalla() and not m.fpga_cfgs[m.n_cfg:] and bytes(m.prgram[:0x2000]) == PAT,
          'con la partida sin guardar no se lanza nada (ni se toca la PRG-RAM)')
m.sd.__class__ = SD
m.cpu.reset()
m.correr(PASOS, nmi_cada=9000)
comprobar('Partida guardada' in m.pantalla() and leer_archivo(m, f'EDFC/SAVE/{JP}.srm') == PAT and not marca(m),
          'cuando la tarjeta vuelve a dejar escribir, el reset guarda la partida')
m, ok = encender(pathlib.Path(img5).read_bytes(), sd=SDprotegida(pathlib.Path(img5).read_bytes()))
ir_a(m, JP + '.nes')
lanzo = lanzar(m)
m.correr(200_000, nmi_cada=9000)
comprobar(not lanzo and 'Error al escribir la SD 0B' in m.pantalla() and not m.fpga_cfgs[m.n_cfg:],
          'no se puede crear la partida: «Error al escribir la SD 0B» y no lanza')

# ------------------------------------------------------------------ etapa 6: menú ordenado, información y último juego
def imagen6(nombre):
    img = imagen3(nombre)
    dest = f'{img}@@{8192 * 512}'
    subprocess.run(['mmd', '-i', dest, '::zeta', '::Ábaco'], check=True)
    for n, datos in (('Ñandú.nes', rom(16, 16, 4, semilla=21)[0]), ('nube.nes', rom(1, 1, 2, semilla=22)[0]),
                     ('Final Fantasy II.nes', rom(2, 1, 1, byte6=2, semilla=23)[0]),
                     ('Final Fantasy.nes', rom(2, 1, 1, byte6=2, semilla=24)[0]),
                     ('Ábaco/Sin pila.nes', rom(2, 1, 0, semilla=25)[0])):
        f = t / 'tmp.bin'
        f.write_bytes(datos)
        subprocess.run(['mcopy', '-i', dest, str(f), f'::{n}'], check=True)
    return img

ORDEN6 = ['Ábaco/', 'EDFC/', 'PRUEBAS/', 'zeta/', 'CHRRAM', 'DUDE', 'FALTA', 'Final Fantasy', 'Final Fantasy II',
          'JUEGO', 'M219', 'MMC3', 'NES20', 'NOTAS.TXT', 'nube', 'Ñandú', 'SINRBF', 'TRAINER']
img6 = imagen6('e6.img')
m, ok = arrancar(img6)
m.correr(PASOS, nmi_cada=9000)
pan = m.pantalla()
comprobar(cabecera(pan) == 'Raíz 1/2' and lista(pan) == ORDEN6[:16],
          f'orden alfabético: carpetas primero, sin mayúsculas ni acentos, «Final Fantasy» < «II», ñ tras la n: {lista(pan)}')
pulsa(m, 0x01)
comprobar(cabecera(m.pantalla()) == 'Raíz 2/2' and lista(m.pantalla()) == ORDEN6[16:], 'página 2 del orden')
pulsa(m, 0x02)
m.correr(300_000, nmi_cada=9000)
comprobar(fila25(m.pantalla()) == '', 'cursor sobre una carpeta: la fila de información queda vacía')
for nombre, info in (('Final Fantasy II', 'Mapper 1  32K+8K  pila'), ('CHRRAM', 'Mapper 0  16K+RAM'),
                     ('Ñandú', 'Mapper 4  256K+128K'), ('NOTAS.TXT', 'No es una ROM iNES'), ('M219', 'Mapper 219  64K+16K')):
    ir_a_nombre(m, nombre)
    m.correr(300_000, nmi_cada=9000)
    comprobar(fila25(m.pantalla()) == info, f'información de {nombre}: «{fila25(m.pantalla())}»')
toca(m, 0x08)                                # se mueve: la fila se vacía enseguida (no queda la del juego anterior)
comprobar(fila25(m.pantalla()) == '', f'al mover el cursor, la fila de información se vacía: «{fila25(m.pantalla())}»')
m.correr(300_000, nmi_cada=9000)
comprobar(fila25(m.pantalla()) == 'Mapper 0  32K+8K', f'y luego sale la del juego nuevo (JUEGO, encima de M219): «{fila25(m.pantalla())}»')
comprobar(solo_lectura(m), 'el orden y la información no escriben en la tarjeta')

m, ok = arrancar(img6)                      # repetición: abajo mantenido
m.correr(PASOS, nmi_cada=9000)
m.pad = 0x04
m.correr(60 * 9000, nmi_cada=9000)
m.pad = 0
m.correr(200_000, nmi_cada=9000)
fila = next((i for i, l in enumerate(lista(m.pantalla())) if cursor_en(m.pantalla(), l)), 0)
comprobar(fila >= 6, f'abajo mantenido un segundo: el cursor se repite (fila {fila})')

def con_select(m, boton):
    m.pad = 0x20
    m.correr(20_000, nmi_cada=9000)
    m.pad = 0x20 | boton
    m.correr(30_000, nmi_cada=9000)
    m.pad = 0x20
    m.correr(30_000, nmi_cada=9000)
    m.pad = 0
    m.correr(300_000, nmi_cada=9000)
m, ok = arrancar(img6)
m.correr(PASOS, nmi_cada=9000)
con_select(m, 0x01)
comprobar(cursor_en(m.pantalla(), 'EDFC/'), 'Select+derecha en «Ábaco/»: a la siguiente letra («EDFC/»)')
ir_a_nombre(m, 'FALTA')
con_select(m, 0x01)
comprobar(cursor_en(m.pantalla(), 'JUEGO'), 'Select+derecha en «FALTA»: salta las F y va a «JUEGO»')
ir_a_nombre(m, 'Final Fantasy II')
con_select(m, 0x02)
comprobar(cursor_en(m.pantalla(), 'FALTA'), 'Select+izquierda en «Final Fantasy II»: al principio de la F')
con_select(m, 0x02)
comprobar(cursor_en(m.pantalla(), 'DUDE'), 'Select+izquierda otra vez: a la letra anterior («DUDE»)')
ir_a_nombre(m, 'SINRBF')
con_select(m, 0x01)
con_select(m, 0x01)
comprobar(cursor_en(m.pantalla(), 'Ábaco/') and cabecera(m.pantalla()) == 'Raíz 1/2',
          'Select+derecha en la última letra: vuelve al principio (y cambia de página)')

m, ok = arrancar(img6)                      # último juego: al encender con la RAM con pila
m.correr(PASOS, nmi_cada=9000)
ir_a_nombre(m, 'Ábaco/')
pulsa(m, 0x80, 1_000_000)
ir_a_nombre(m, 'Sin pila')
ok = lanzar(m)
ram = bytearray(m.prgram)
ram[0x12000:] = bytes(len(ram) - 0x12000)
m2, ok2 = encender(bytes(m.sd.img), prgram=ram)
pan = m2.pantalla()
comprobar(ok and 'Arranque: frío (BIOS)' in pan and cabecera(pan) == 'Ábaco 1/1' and cursor_en(pan, 'Sin pila'),
          'al encender (RAM con pila): abre la carpeta del último juego con el cursor sobre él')
pulsa(m2, 0x40, 1_000_000)
comprobar(cabecera(m2.pantalla()) == 'Raíz 1/2' and cursor_en(m2.pantalla(), 'Ábaco/'), 'y B vuelve a la raíz con el cursor sobre la carpeta')
m3, ok3 = encender(bytes(m.sd.img))
comprobar(cabecera(m3.pantalla()) == 'Raíz 1/2' and cursor_en(m3.pantalla(), 'Ábaco/'), 'con la RAM a cero: la raíz')

# ------------------------------------------------------------------ etapa 7: modo banco (EDFC/BANCO.TXT)
def codigo_banco(pan):
    """El número que pintan las filas 16 y 17 (bloques = 1, entre dos bloques de marca; la 17 es el complemento),
    como lo leerá el PC. None si no es válido."""
    filas = {int(l[:2]): l[3:] for l in pan.split('\n')}
    a, b = filas.get(16, '').ljust(20)[2:20], filas.get(17, '').ljust(20)[2:20]
    if not (a[0] == a[17] == b[0] == b[17] == '█'):
        return None
    va = int(''.join('1' if c == '█' else '0' for c in a[1:17]), 2)
    vb = int(''.join('1' if c == '█' else '0' for c in b[1:17]), 2)
    return va if va ^ vb == 0xFFFF else None

def titulo_banco(pan):
    return next((l[3:].strip() for l in pan.split('\n') if l[:2] == ' 7'), '')

LISTA7 = '# lista de prueba\n\nJUEGO.NES\r\nJuegos/Mapper 4 (MMC3)/Súper Prueba ñ (España).nes\nNO/EXISTE.nes\nzelda.nes\n'
def imagen7(nombre, lista=LISTA7):
    img = imagen4(nombre)
    dest = f'{img}@@{8192 * 512}'
    f = t / 'tmp.bin'
    f.write_bytes(lista.encode())
    subprocess.run(['mcopy', '-i', dest, str(f), '::EDFC/BANCO.TXT'], check=True)
    f.write_bytes(dict(ROMS)['JUEGO.NES'][0])
    subprocess.run(['mcopy', '-i', dest, '-o', str(f), '::ZELDA.NES'], check=True)
    return img

img7 = imagen7('e7.img')
m, ok = arrancar(img7)
m.correr(PASOS + 1_000_000, nmi_cada=9000)
pan = m.pantalla()
comprobar(titulo_banco(pan) == 'Modo banco  1/4' and 'JUEGO.NES' in pan and fila25(pan) == '' and codigo_banco(pan) == 0,
          f'con BANCO.TXT: pantalla de banco, entrada 1/4 (sin la línea vacía ni el comentario), código 0: {titulo_banco(pan)}')
comprobar(any('Mapper 0  32K+8K' in l for l in pan.split('\n')) and m.rojas() == set(), 'información de la entrada; sin rojo')
comprobar(solo_lectura(m), 'la pantalla de banco no escribe en la tarjeta')
ok = lanzar(m, 0x10)
_, prg, chr_ = dict(ROMS)['JUEGO.NES']
comprobar(ok and m.mapper == 0 and bytes(m.prgrom[:len(prg)]) == prg, 'Start lanza la entrada (JUEGO.NES, mapper 0)')
m.reset_consola()
m.correr(PASOS + 1_000_000, nmi_cada=9000)
pan = m.pantalla()
ruta7 = ''.join(l[3:].ljust(30)[2:30] for l in pan.split('\n') if 9 <= int(l[:2]) <= 11)
comprobar(titulo_banco(pan) == 'Modo banco  2/4' and codigo_banco(pan) == 1 and 'Súper Prueba ñ' in ruta7,
          f'RESET en el juego: la pantalla de banco con la siguiente (2/4, código 1, nombre largo con ñ en UTF-8)')
ok = lanzar(m, 0x10)
_, prg, chr_ = dict(ROMS)['MMC3.NES']
comprobar(ok and m.mapper == 4 and bytes(m.prgrom[:len(prg)]) == prg, 'lanza la ruta con carpetas y nombre largo (MMC3)')
m.reset_consola()
m.correr(PASOS + 1_000_000, nmi_cada=9000)
pan = m.pantalla()
comprobar(titulo_banco(pan) == 'Modo banco  3/4' and 'No encuentro el archivo' in pan and codigo_banco(pan) == 2,
          'la entrada 3 no existe: «No encuentro el archivo»')
m.n_cfg = len(m.fpga_cfgs)
lanzo = lanzar(m, 0x10)
m.correr(500_000, nmi_cada=9000)
pan = m.pantalla()
comprobar(not lanzo and titulo_banco(pan) == 'Modo banco  4/4' and fila25(pan) == 'No encuentro el archivo'
          and not m.fpga_cfgs[m.n_cfg:], 'Start sobre ella: no lanza, pasa a la 4 y dice por qué en la fila 25')
pulsa(m, 0x01, 2_000_000)
pan = m.pantalla()
comprobar(titulo_banco(pan) == 'Modo banco  5/4' and 'Lista terminada' in pan and codigo_banco(pan) == 4, 'derecha: «Lista terminada» (5/4)')
pulsa(m, 0x01, 2_000_000)
comprobar(titulo_banco(m.pantalla()) == 'Modo banco  1/4' and codigo_banco(m.pantalla()) == 0, 'derecha otra vez: vuelve a la 1')
pulsa(m, 0x02, 2_000_000)
pulsa(m, 0x02, 2_000_000)
comprobar(titulo_banco(m.pantalla()) == 'Modo banco  4/4' and 'zelda.nes' in m.pantalla(), 'izquierda dos veces: la 4 (zelda.nes, 8.3 en minúsculas)')
ram = bytearray(m.prgram)
ram[0x12000:] = bytes(len(ram) - 0x12000)
m2, ok2 = encender(bytes(m.sd.img), prgram=ram)
m2.correr(1_000_000, nmi_cada=9000)
comprobar(titulo_banco(m2.pantalla()) == 'Modo banco  4/4', 'al encender (RAM con pila) sigue en la misma entrada')
m3, ok3 = encender(bytes(m.sd.img))
m3.correr(1_000_000, nmi_cada=9000)
comprobar(titulo_banco(m3.pantalla()) == 'Modo banco  1/4', 'con la RAM a cero: la primera')
pulsa(m, 0x40, 3_000_000)
pan = m.pantalla()
comprobar(cabecera(pan) == 'Raíz 1/1' and 'Modo banco' not in pan, 'B: sale al menú normal')
m.cpu.reset()
m.correr(PASOS + 1_000_000, nmi_cada=9000)
comprobar('Modo banco' not in m.pantalla() and cabecera(m.pantalla()) == 'Raíz 1/1', 'y un reset lo deja en el menú (hasta apagar)')
img7c = imagen7('e7c.img', lista='!ram=00\nMMC3.NES\nJUEGO.NES\n')
m5, ok5 = encender(pathlib.Path(img7c).read_bytes())
m5.correr(1_000_000, nmi_cada=9000)
pan = m5.pantalla()
comprobar(titulo_banco(pan) == 'Modo banco  1/2  RAM=00', f'!ram=00: no cuenta como entrada y sale en el título: {titulo_banco(pan)}')
m5.prgram[:0x10000] = bytes([0x5A]) * 0x10000
ok5 = lanzar(m5, 0x10)
comprobar(ok5 and m5.mapper == 4 and bytes(m5.prgram[:0x10000]) == bytes(0x10000) and not marca(m5)
          and 'MMC3.SRM' not in nombres_save(m5) and not escrituras(m5),
          'juego con pila con !ram=00: los 64 KiB de la PRG-RAM a $00, sin partida (no se crea ni se marca) y sin escribir')
m5.prgram[:0x2000] = PAT
m5.reset_consola()
m5.correr(PASOS + 1_000_000, nmi_cada=9000)
comprobar(titulo_banco(m5.pantalla()) == 'Modo banco  2/2  RAM=00' and 'Partida' not in m5.pantalla() and not escrituras(m5),
          'tras el RESET: la siguiente, y lo que «guardó» el juego no se escribe en la SD')
img7b = imagen7('e7b.img', lista='zelda.nes\nJUEGO.NES\n')
m4, ok4 = encender(pathlib.Path(img7b).read_bytes(), prgram=ram)
m4.correr(1_000_000, nmi_cada=9000)
comprobar(titulo_banco(m4.pantalla()) == 'Modo banco  1/2', 'otra BANCO.TXT (otro tamaño): empieza por la primera aunque la RAM guarde otra entrada')

# ------------------------------------------------------------------ FDS: reconocer discos y la BIOS (fds.s)
import zlib
sys.path.insert(0, str(RAIZ / 'tools/fds'))
import fds as fdsmod

def forzar_crc(datos, pos, objetivo):
    """Cambia datos[pos:pos+4] para que zlib.crc32(datos) == objetivo (el CRC es lineal: 32 ecuaciones)."""
    d = bytearray(datos)
    d[pos:pos + 4] = bytes(4)
    base = zlib.crc32(d)
    base_v = {}                                 # base de los efectos de cada bit, por su bit más alto
    for b in range(32):
        e = bytearray(d)
        e[pos + b // 8] ^= 1 << (b % 8)
        v, m = zlib.crc32(e) ^ base, 1 << b
        while v:
            h = v.bit_length() - 1
            if h not in base_v:
                base_v[h] = (v, m)
                break
            v ^= base_v[h][0]
            m ^= base_v[h][1]
    meta, x = objetivo ^ base, 0
    for h in sorted(base_v, reverse=True):
        if meta >> h & 1:
            meta ^= base_v[h][0]
            x ^= base_v[h][1]
    assert meta == 0
    d[pos:pos + 4] = x.to_bytes(4, 'little')
    assert zlib.crc32(d) == objetivo
    return bytes(d)

def cara_fds(codigo=b'ABC', rev=2, cara=0, semilla=1):
    """Una cara sintética (formato público del FDS): bloque 1, bloque 2 con un archivo, bloques 3 y 4."""
    b1 = bytes([1]) + fdsmod.FIRMA + bytes([0x01]) + codigo + b' ' + bytes([rev, cara, 0, 0, 0, 0x0F]) + bytes([0xFF] * 5)
    b1 = b1 + bytes(56 - len(b1))
    datos = bytes((i * 13 + semilla) & 0xFF for i in range(1024))
    c = b1 + bytes([2, 1]) + bytes([3, 0, 0]) + b'PROGRAMA' + bytes([0x00, 0x60, 0x00, 0x04, 0]) + bytes([4]) + datos
    return c + bytes(fdsmod.CARA - len(c))

FDS2 = cara_fds() + cara_fds(cara=1)
FDS_FW = b'FDS\x1a' + bytes([1]) + bytes(11) + cara_fds(codigo=b'XYZ', rev=0)
FDS_MAL = cara_fds() + bytes(10)
inc = (RAIZ / 'os/src/fds_tablas.inc').read_text()
malos = [int(l.split('$')[1][:8], 16) for l in inc.split('fds_malos:')[1].split('\n') if '.dword' in l]
bios_si = [c for c, b in fdsmod.BIOS.items() if b[1] == 'si']
bios_no = [c for c, b in fdsmod.BIOS.items() if b[1] != 'si']
FDS_PROPIO = forzar_crc(cara_fds(semilla=7)[:fdsmod.INI], 400, malos[0]) + cara_fds(semilla=7)[fdsmod.INI:]
RELLENO_BIOS = bytes((i * 101 + 3) & 0xFF for i in range(8192))      # no es la BIOS: datos propios

def imagen_fds(nombre, bios_fds):
    img = imagen3(nombre)
    dest = f'{img}@@{8192 * 512}'
    archivos = [('Disco (Japan).fds', FDS2), ('Con cabecera.FDS', FDS_FW), ('Roto.fds', FDS_MAL),
                ('Carga propia.fds', FDS_PROPIO)]
    if bios_fds is not None:
        archivos.append(('EDFC/DISKSYS.ROM', bios_fds))
    for n, datos in archivos:
        f = t / 'tmp.bin'
        f.write_bytes(datos)
        subprocess.run(['mcopy', '-i', dest, str(f), f'::{n}'], check=True)
    return img

imgf = imagen_fds('fds1.img', forzar_crc(RELLENO_BIOS, 100, bios_si[0]))
m, ok = arrancar(imgf)
m.correr(PASOS, nmi_cada=9000)
filas = lista(m.pantalla())
comprobar('Disco (Japan)' in filas and 'Con cabecera' in filas and 'Roto' in filas,
          f'los .fds salen en el menú sin la extensión: {[f for f in filas if "fds" in f.lower() or f in ("Roto", "Con cabecera")]}')
for nombre, info in (('Disco (Japan)', 'Disco FDS  2 caras  ABC r2'), ('Con cabecera', 'Disco FDS  1 cara  XYZ r0'),
                     ('Roto', 'Imagen FDS no válida'), ('Carga propia', 'Disco FDS con carga propia')):
    ir_a_nombre(m, nombre)
    m.correr(300_000, nmi_cada=9000)
    comprobar(fila25(m.pantalla()) == info, f'información de {nombre}: «{fila25(m.pantalla())}»')
for bios_fds, mensaje in ((forzar_crc(RELLENO_BIOS, 100, bios_si[0]), 'No encuentro el RBF 254'),
                          (forzar_crc(RELLENO_BIOS, 100, bios_si[2]), 'No encuentro el RBF 254'),
                          (forzar_crc(RELLENO_BIOS, 100, bios_no[0]), 'BIOS FDS de emulador'),
                          (RELLENO_BIOS, 'BIOS FDS desconocida'), (RELLENO_BIOS[:4096], 'BIOS FDS desconocida'),
                          (None, 'Falta EDFC/DISKSYS.ROM')):
    img = imagen_fds('fds2.img', bios_fds)
    m = menu3(img, 'Disco (Japan).fds')
    m.correr(100_000, nmi_cada=9000)
    ir_a_nombre(m, 'Disco (Japan)')
    ok = lanzar(m)
    m.correr(200_000, nmi_cada=9000)
    comprobar(not ok and mensaje in m.pantalla() and m.ppu_mask & 0x08 and not m.fpga_cfgs[m.n_cfg:] and solo_lectura(m),
              f'lanzar un .fds con {"sin BIOS" if bios_fds is None else f"BIOS de {len(bios_fds)} B CRC {zlib.crc32(bios_fds):08X}"}: «{mensaje}», sin tocar el FPGA ni escribir')
for nombre, mensaje in (('Roto', 'Imagen FDS no válida'), ('Carga propia', 'Disco FDS con carga propia')):
    m = menu3(imgf, 'Disco (Japan).fds')
    ir_a_nombre(m, nombre)
    ok = lanzar(m)
    m.correr(200_000, nmi_cada=9000)
    comprobar(not ok and mensaje in m.pantalla(), f'lanzar {nombre}: «{mensaje}»')

# ------------------------------------------------------------------ F4: lanzar un disco FDS y guardarlo al volver
rbf254 = bytes((i * 11 + 5) & 0xFF for i in range(40000))
parche_bin = (RAIZ / 'os/build/fds_parche.bin').read_bytes()
BIOS_F4 = forzar_crc(RELLENO_BIOS, 100, bios_si[0])

def poner(d, pos, b):
    d[pos:pos + len(b)] = b

def cara_f4(codigo, cara, semilla):
    """Cara sintética con un PRG grande (lecturas de $403x por todas partes, una a caballo entre dos bancos de 2 KiB
    de la ventana), un CHR con los mismos bytes (no se tocan) y un PRG oculto."""
    b1 = bytes([1]) + fdsmod.FIRMA + bytes([0x01]) + codigo + b' ' + bytes([1, cara, 0, 0, 0, 0x0F]) + bytes([0xFF] * 5)
    b1 = b1 + bytes(56 - len(b1))
    prg = bytearray((i * 13 + semilla) & 0xFF for i in range(6000))
    ini = 56 + 2 + 16 + 1                                   # donde empiezan los datos del PRG en la cara
    for off, b in ((10, b'\xAD\x32\x40'), (300, b'\x2C\x30\x40'), (301 + 2048, b'\xBD\x33\x40'),
                   (2046 - ini, b'\xAD\x32\x40'), (4095 - ini, b'\xAE\x30\x40'), (900, b'\x8D\x32\x40'),
                   (1000, b'\xAD\x31\x40'), (1100, b'\xAD\x32\x41'), (5997, b'\xCD\x32\x40')):
        poner(prg, off, b)
    chr_ = bytearray(512)
    poner(chr_, 40, b'\xAD\x32\x40')
    oculto = bytearray(64)
    poner(oculto, 5, b'\xAD\x30\x40')
    c = b1 + bytes([2, 2])
    for n, (nom, dire, datos, tipo) in enumerate(((b'PROGRAMA', 0x6000, prg, 0), (b'GRAFICOS', 0x0000, chr_, 1),
                                                  (b'OCULTO  ', 0x7000, oculto, 0))):
        c += bytes([3, n, n]) + nom + bytes([dire & 0xFF, dire >> 8, len(datos) & 0xFF, len(datos) >> 8, tipo])
        c += bytes([4]) + bytes(datos)
    return c + bytes((i * 7 + semilla) & 0xFF for i in range(fdsmod.CARA - len(c)))

CARAS_F4 = [cara_f4(b'NFD', 0, 3), cara_f4(b'NFD', 1, 9)]
FDS_F4 = b'FDS\x1a' + bytes([2]) + bytes(11) + b''.join(CARAS_F4)        # con cabecera fwNES: 16 bytes delante

def imagen_f4(nombre):
    img = imagen3(nombre)
    dest = f'{img}@@{8192 * 512}'
    for n, datos in (('EDFC/MAPS/254.RBF', rbf254), ('EDFC/DISKSYS.ROM', BIOS_F4), ('Disco F4.fds', FDS_F4)):
        f = t / 'tmp.bin'
        f.write_bytes(datos)
        subprocess.run(['mcopy', '-i', dest, str(f), f'::{n}'], check=True)
    return img

esperado = fdsmod.montar_sram(BIOS_F4, parche_bin, CARAS_F4)
cambios = [fdsmod.cambiar_cara(c)[1] for c in CARAS_F4]
img_f4 = imagen_f4('f4.img')
m = menu3(img_f4, 'Disco F4.fds')
comprobar(cursor_en(m.pantalla(), 'Disco F4'), 'F4: el cursor llega al disco')
def lanzar_f4(m):
    m.pad = 0x80
    r = m.correr(60_000_000, lambda m: m.mapper != 0xFF, nmi_cada=9000)
    m.pad = 0
    return r == 'parada'

ok = lanzar_f4(m)
comprobar(ok and m.mapper == 254 and m.cpu.pc < 0x0800, 'F4: reg 131 = 254, escrito desde la RAM')
cfg = m.fpga_cfgs[m.n_cfg:]
comprobar(len(cfg) == 1 and bytes(cfg[0][:len(rbf254)]) == rbf254, 'F4: el FPGA recibe el 254.RBF')
comprobar((m.fpga.get(132), m.fpga.get(133), m.fpga.get(134), m.fpga.get(136)) == (31, 0xFF, 0, 0),
          f'F4: regs 132/133/134/136 = 1F/FF/00/00 ({[m.fpga.get(r) for r in (132, 133, 134, 136)]})')
for k in range(2):
    a = k * 0x10000
    comprobar(m.prgrom[a:a + fdsmod.CARA] == esperado[a:a + fdsmod.CARA],
              f'F4: cara {k} en la SRAM como fds.cambiar_cara ({len(cambios[k])} lecturas cambiadas)')
comprobar(m.prgrom[0x7D000:0x7D000 + len(parche_bin)] == parche_bin and m.prgrom[0x7DFFF] == 2,
          'F4: el bloque del parche en 0x7D000 y 2 caras en 0x7DFFF')
comprobar(m.prgrom[0x7E000:0x80000] == esperado[0x7E000:0x80000], 'F4: la BIOS en 0x7E000 con los enganches del parche')
mk = m.prgram[0x10180:0x10180 + 22]
comprobar(mk[:5] == b'N8FD\x01' and mk[18:21] == bytes([2, 16, sum(map(len, cambios))])
          and int.from_bytes(mk[14:18], 'little') == len(FDS_F4),
          f'F4: marca N8FD en el banco 8 (2 caras, cabecera 16, {sum(map(len, cambios))} cambios, tamaño {len(FDS_F4)})')
comprobar(solo_lectura(m) and estado(m, 'en_juego') == 1, 'F4: la SD solo se lee; marca en_juego puesta')

# el juego escribe en el disco: un byte del PRG, una lectura cambiada reescrita entera y el final de la cara 2
sram = m.prgrom
sram[75 + 500] ^= 0xFF
p0 = cambios[0][0]
sram[p0:p0 + 2] = b'\x11\x22'
sram[0x10000 + 65499] ^= 0x5A
caras_juego = [bytes(sram[k * 0x10000:k * 0x10000 + fdsmod.CARA]) for k in range(2)]
fds_esperado = FDS_F4[:16] + b''.join(fdsmod.deshacer_cara(c, cambios[k]) for k, c in enumerate(caras_juego))
dif = {i // 512 for i in range(len(FDS_F4)) if FDS_F4[i] != fds_esperado[i]}
n24 = len(escrituras(m))
m.reset_consola()
nmi0, lat0 = m.n_nmi, len(m.latches)
m.correr(60_000_000, lambda m: m.prgram[0x10180] != 0x4E, nmi_cada=9000)     # hasta que se borra la marca
lat = [(n - nmi0, pan) for n, pan in m.latches[lat0:]]
comprobar(lat and lat[0][0] >= 6 and any(not pan for _, pan in lat),
          f'F4: al volver, ningún LATCH del mando en las 6 primeras NMI (el Nano ve el reset) y sí mientras se compara '
          f'el disco con la pantalla apagada (el kit Lava ve los botones sueltos) (primero en la NMI {lat[0][0] if lat else "-"}, '
          f'{sum(1 for _, p in lat if not p)} con la pantalla apagada)')
m.correr(PASOS, nmi_cada=9000)
pan = m.pantalla()
comprobar('Disco FDS guardado' in pan and 'Arranque: vuelta de juego' in pan, f'F4: al volver, «Disco FDS guardado» ({fila25(pan)})')
comprobar(leer_archivo(m, 'Disco F4.fds') == fds_esperado,
          'F4: el .fds de la SD = el disco con lo que escribió el juego y las lecturas otra vez como estaban')
comprobar(len(escrituras(m)) - n24 == len(dif) and fsck(m) == [],
          f'F4: solo se escriben los {len(dif)} sectores que cambiaron ({len(escrituras(m)) - n24}); fsck.fat sin errores')
comprobar(m.prgram[0x10180:0x10184] != b'N8FD', 'F4: la marca N8FD se borra')

# lanzar otra vez y apagar sin RESET: al encender no se escribe nada (la SRAM PRG no tiene pila)
m2 = Maquina(bios, SD(bytes(m.sd.img), sdhc=True), prgram=m.prgram)
m2.arrancar_bios()
m2.correr(PASOS, nmi_cada=9000)
m2.n_cfg = len(m2.fpga_cfgs)
ir_a_nombre(m2, 'Disco F4')
ok = lanzar_f4(m2)
comprobar(ok and m2.prgram[0x10180:0x10184] == b'N8FD', 'F4: el disco guardado se vuelve a lanzar (marca N8FD)')
img_ahora = bytes(m2.sd.img)
m3, _ = encender(img_ahora, prgram=m2.prgram)
comprobar(not escrituras(m3) and m3.prgram[0x10180:0x10184] != b'N8FD' and 'Disco F4' in lista(m3.pantalla()),
          'F4: encender con la marca N8FD: se borra sin escribir en la SD')


# ------------------------------------------------------------------ opciones: volumen del sonido de expansión
def fila_vol(pan):
    return next((l[3:].strip() for l in pan.split('\n') if l[:2] == '12'), '')
def vol_txt(paso):
    v = paso - 4
    return '◀ ' + (' 0' if v == 0 else f'{v:+d}') + ' ▶  ' + '█' * (paso + 1) + '-' * (8 - paso)
def sel_start(m):
    """Select y luego Select+Start, como lo pulsa una persona."""
    m.pad = 0x20; m.correr(20_000, nmi_cada=9000)
    m.pad = 0x30; m.correr(30_000, nmi_cada=9000)
    m.pad = 0; m.correr(300_000, nmi_cada=9000)
def opc_guardado(m):
    r = m.prgram[0x10120:0x10126]
    return bytes(r[:4]) == b'N8OP' and r[5] == (0x5A + r[4]) & 0xFF and r[4]
m = menu3(img3, 'JUEGO.NES')
pan0 = m.pantalla()
sel_start(m)
pan = m.pantalla()
comprobar(m.mapper == 0xFF and 'Opciones' in pan and 'Volumen del cartucho' in pan and fila_vol(pan) == vol_txt(4)
          and m.ppu_mask & 0x08 and not any(l[4:5] == '▶' for l in pan.split('\n') if 9 <= int(l[:2]) <= 24),
          f'Select+Start: la pantalla de opciones, con el volumen calibrado («{fila_vol(pan)}») y sin lanzar nada')
for _ in range(3):
    toca(m, 0x01)
comprobar(fila_vol(m.pantalla()) == vol_txt(7), f'▶ tres veces: +3 («{fila_vol(m.pantalla())}»)')
for _ in range(3):
    toca(m, 0x01)
comprobar(fila_vol(m.pantalla()) == vol_txt(8), 'más ▶: se queda en +4')
m.pad = 0x02
m.correr(1_500_000, nmi_cada=9000)            # ◀ mantenido: se repite hasta -4
m.pad = 0
m.correr(30_000, nmi_cada=9000)
comprobar(fila_vol(m.pantalla()) == vol_txt(0), f'◀ mantenido: se repite y se queda en -4 («{fila_vol(m.pantalla())}»)')
toca(m, 0x01)
pulsa(m, 0x40, 300_000)
pan = m.pantalla()
def lista_y_cabecera(pan):
    return [l for l in pan.split('\n') if 7 <= int(l[:2]) <= 24]
comprobar(lista_y_cabecera(pan) == lista_y_cabecera(pan0) and cursor_en(pan, 'JUEGO') and opc_guardado(m) == 1,
          'B: vuelve a la lista igual que estaba (cursor incluido) y guarda el paso 1 (-3) en el banco 8 con firma y suma')
comprobar(solo_lectura(m) and m.mapper == 0xFF, 'opciones: la SD solo se lee y no se lanza nada')
ok = lanzar(m)
comprobar(ok and m.mapper == 0 and m.fpga.get(137) == 1, f'al lanzar: reg 137 = 1 (-3) ({m.fpga.get(137)})')
ram = bytearray(m.prgram)
m2, ok2 = encender(bytes(m.sd.img), prgram=ram)
sel_start(m2)
comprobar(fila_vol(m2.pantalla()) == vol_txt(1), 'al encender (RAM con pila): las opciones muestran el paso guardado (-3)')
pulsa(m2, 0x10, 300_000)
comprobar(cursor_en(m2.pantalla(), 'JUEGO') and 'Opciones' not in m2.pantalla(), 'Start también vuelve a la lista')
ok = lanzar(m2)
comprobar(ok and m2.fpga.get(137) == 1, 'y el juego se lanza con el reg 137 = 1')
ram[0x10125] ^= 0xFF
m3, ok3 = encender(bytes(m.sd.img), prgram=ram)
ok = lanzar(m3)
comprobar(ok and m3.fpga.get(137) == 4, 'suma del banco 8 mal: volumen calibrado (reg 137 = 4)')
m4, ok4 = encender(bytes(m.sd.img))
ir_a_nombre(m4, 'JUEGO')
ok = lanzar(m4)
comprobar(ok and m4.fpga.get(137) == 4, 'RAM a cero: volumen calibrado (reg 137 = 4)')
m = menu3(imagen3('e3frag.img', fragmentar=True), 'JUEGO.NES')
ok = lanzar(m)
m.correr(200_000, nmi_cada=9000)
comprobar(not ok and 'RBF fragmentado en la SD' in m.pantalla() and not m.fpga_cfgs[m.n_cfg:],
          'RBF fragmentado: aviso y el FPGA no se toca')

# ROMs fragmentadas en la tarjeta: la copia va por tramos de clústeres seguidos (varias lecturas múltiples)
img3f = imagen3('e3romfrag.img', fragmentar_roms=('JUEGO.NES', 'MMC3.NES', 'TRAINER.NES'))
for nombre in ('JUEGO.NES', 'MMC3.NES', 'TRAINER.NES'):
    _, prg, chr_ = dict(ROMS)[nombre]
    m = menu3(img3f, nombre)
    n18 = sum(1 for e in m.log[m.n_log:] if e[0] == 'SD_CMD18')
    c0 = m.cpu.ciclos
    ok = lanzar(m)
    n18 = sum(1 for e in m.log[m.n_log:] if e[0] == 'SD_CMD18') - n18
    comprobar(ok and bytes(m.prgrom[:len(prg)]) == prg and bytes(m.chr[:len(chr_)]) == chr_ and n18 >= 4,
              f'{nombre} fragmentada: PRG y CHR iguales, {n18} lecturas múltiples (RBF + 3 tramos de la ROM)')

print('pantalla del caso FAT32:')
m, ok = arrancar(img32)
m.correr(PASOS, nmi_cada=9000)
print(m.pantalla())
sys.exit(1 if fallos else 0)
