"""Revisión conservadora de cabecera contra memoria física y mapeo RTL del N8."""
import difftest


def revisar(ruta):
    i = difftest.ines(ruta)
    if i is None:
        return dict(admitida=False, errores=['Cabecera incompleta o inválida'], avisos=[])
    errores, avisos = [], []
    problema = difftest.supported(i)
    if problema:
        errores.append(problema)
    if i['extended_rom_encoding']:
        errores.append('OS v13 y puente configuran bancos con bytes iNES; codificación ROM extendida no soportada')
    if i['file_bytes'] < 16 + 512 * i['trainer'] + i['prg_bytes'] + i['chr_bytes']:
        errores.append('Archivo truncado: faltan datos de ROM declarados')
    if i['console_type'] != 0:
        errores.append('Cabecera para consola distinta de NES/Famicom estándar')
    if not i['nes2']:
        avisos.append('iNES no declara RAM con precisión; requiere revisión de placa')
    else:
        pram = i['prg_ram_bytes'] + i['prg_nvram_bytes']
        cram = i['chr_ram_bytes'] + i['chr_nvram_bytes']
        if pram > 65536:
            errores.append('PRG-RAM + NVRAM > 64 KiB libres; los 64 KiB superiores están reservados al OS')
        # Capacidades visibles en los módulos de los mappers pendientes; el resto
        # no se certifica por inferencia a partir de la cantidad de SRAM física.
        pendientes = {12,28,31,35,40,42,45,50,56,57,58,59,60,74,83,90,91,103,
                      107,108,111,114,117,121,134,142,171,176,178,183,187,191,
                      194,196,197,209,211,215,219,222,227,229,238,242}
        if i['mapper'] in pendientes:
            pram_limite = {103:16384, 176:32768}.get(i['mapper'], 8192)
            if pram > pram_limite:
                errores.append(f'RAM declarada ({pram} bytes) supera ventana RTL revisada ({pram_limite})')
            if not i['chr_bytes']:
                cram_limite = {28:32768, 111:32768, 176:262144}.get(i['mapper'],8192)
                if cram > cram_limite:
                    errores.append(f'CHR-RAM declarada ({cram} bytes) supera banca RTL revisada ({cram_limite})')
        if i['chr_bytes'] + cram > 524288 and i['mapper'] not in (5,253):
            errores.append('CHR-ROM + CHR-RAM/NVRAM excede SRAM CHR de 512 KiB')
        if i['mapper'] in (74,119,165,191,192,194,195,199,252) and i['chr_bytes'] > 0x7c000:
            errores.append('CHR-ROM invade región reservada para CHR-RAM mixta en 0x7C000')
        if i['mapper'] == 176 and i['chr_bytes'] > 262144:
            errores.append('FK23C reserva mitad superior de SRAM CHR para RAM; ROM > 256 KiB puede solaparla')
    if i['submapper']:
        avisos.append('OS v13 no transmite submapper al RTL: cobertura no certifica esta variante de placa')
    if i['four_screen']:
        avisos.append('Revisar ubicación de nametables/4 pantallas frente a bancos CHR; la cabecera no prueba ausencia de solapes')
    avisos.append('Cumplir memoria no acredita corrección, arranque ni funcionamiento en consola')
    return dict(admitida=not errores, errores=errores, avisos=avisos, cabecera=i)
