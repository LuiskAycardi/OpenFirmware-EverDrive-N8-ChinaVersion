"""Compara la RAM de la CPU (interna, OAM y $6000-$7FFF) entre Mesen2 y nuestro RBF en varios
fotogramas, para encontrar el primero en que el estado del juego se separa.

  python3 -I ramdiff.py ROM CARPETA_SALIDA 2,10,30,60
Usa las carpetas homes/w6 y homes/w7 (no lanzar a la vez que una tanda de difftest con 7 o más).
"""
import sys, os, pathlib, types
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import difftest as dt
rom = sys.argv[1]; out = pathlib.Path(sys.argv[2])
frames = [int(x) for x in sys.argv[3].split(",")]
os.environ['N8_DUMPS'] = ','.join(map(str, frames))
args = types.SimpleNamespace(model=str(dt.HERE / 'libn8model.so'), clk=25.0)
import concurrent.futures as cf
def go(i_mode):
    i, mode = i_mode
    home = dt.prepare_home(i)
    return dt.run_one(home, rom, mode, max(frames) + 2, 7, [], out / mode, args)
with cf.ThreadPoolExecutor(2) as ex:
    r = list(ex.map(go, [(6, 'ref'), (7, 'n8')]))
print([x['exit'] for x in r])
for f in frames:
    a = (out / 'ref' / f'ram{f:05d}.bin').read_bytes(); b = (out / 'n8' / f'ram{f:05d}.bin').read_bytes()
    d = [i for i in range(len(a)) if a[i] != b[i]]
    def name(i):
        return f'${i:04X}' if i < 0x800 else (f'OAM{i-0x800:02X}' if i < 0x900 else f'${0x6000 + i - 0x900:04X}')
    print(f, len(d), ' '.join(f'{name(i)}:{a[i]:02X}/{b[i]:02X}' for i in d[:12]))
