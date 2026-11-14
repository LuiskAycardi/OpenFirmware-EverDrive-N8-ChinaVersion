"""Genera vocabularios locales de acciones por género; no ejecuta emuladores."""
import copy
import json
import pathlib

HERE=pathlib.Path(__file__).resolve().parent


def pulso(botones,n=12):return dict(pulsar=botones,duracion_pulso=n)
def mantener(botones):return dict(mantener=botones)
def secuencia(*pasos,repetir=False):
    return dict(secuencia=[dict(botones=b,fotogramas=n) for b,n in pasos],repetir=repetir)


def main():
    base=dict(arranque_fotogramas=240,arranque=[dict(desde=120,hasta=128,botones='start')],
      variantes_arranque=[
        dict(nombre='inicio_a',fotogramas=240,arranque=[dict(desde=120,hasta=132,botones='a')]),
        dict(nombre='inicio_start_a',fotogramas=360,arranque=[dict(desde=120,hasta=128,botones='start'),dict(desde=250,hasta=262,botones='a')])],
      escalas_duracion=[.5,1,2],vision=dict(roi=[0,40,256,240],ventana_temporal=3,tolerancia_celda=.12),
      objetivos=[],acciones={})
    menu={
      'menu_confirmar':pulso('a'), 'menu_volver':pulso('b'),
      'menu_abajo_confirmar':secuencia(('down',8),('',12),('a',8)),
      'menu_arriba_confirmar':secuencia(('up',8),('',12),('a',8)),
      'menu_empezar':pulso('start',8)}
    recuperar={
      'recuperar_esperar':{},
      'recuperar_retroceder':secuencia(('left',24),('',10),('a',10)),
      'recuperar_confirmar':secuencia(('',30),('a',10),('',20),('b',10))}
    acciones={
      'generico':dict(derecha=mantener('right'),izquierda=mantener('left'),arriba=mantener('up'),
        abajo=mantener('down'),a=pulso('a'),b=pulso('b'),derecha_a=dict(mantener='right',**pulso('a'))),
      'plataformas':dict(caminar=mantener('right'),correr=mantener('right+b'),
        salto_corto=dict(mantener='right',**pulso('a',8)),salto_largo=dict(mantener='right+b',**pulso('a',30)),
        dos_saltos=secuencia(('right+a',12),('right',18),('right+a',12),('right',18),repetir=True),
        escalera=mantener('up'),agacharse=mantener('down'),saltar_atras=dict(mantener='left',**pulso('a',16))),
      'accion_cenital':dict(norte=mantener('up'),sur=mantener('down'),este=mantener('right'),oeste=mantener('left'),
        avanzar_atacar=dict(mantener='up',**pulso('b')),rodear_atacar=secuencia(('right',20),('up',20),('b',8),('',12)),
        interactuar=pulso('a')),
      'lucha':dict(acercarse=mantener('right'),alejarse=mantener('left'),agacharse=mantener('down'),
        golpe_a=pulso('a',5),golpe_b=pulso('b',5),combo_ab=secuencia(('a',5),('',7),('b',5),('',7),repetir=True),
        diagonal_golpe=secuencia(('down',6),('down+right',6),('right+a',6),('',12)),
        salto_golpe=secuencia(('up',8),('a',8),('',16))),
      'beat_em_up':dict(avanzar=mantener('right'),retroceder=mantener('left'),
        cambiar_fila_arriba=mantener('up'),cambiar_fila_abajo=mantener('down'),
        combo=secuencia(('b',6),('',6),('b',6),('',6),repetir=True),
        salto_ataque=secuencia(('a',8),('a+b',8),('',16)),
        avanzar_golpear=secuencia(('right',20),('b',6),('',10)),
        buscar_enemigo=secuencia(('up+right',16),('down+right',16),('b',8))),
      'carreras':dict(acelerar=mantener('a'),acelerar_b=mantener('b'),
        curva_izquierda=mantener('left+a'),curva_derecha=mantener('right+a'),
        frenar_y_girar=secuencia(('b',12),('right',12),('a',36)),marcha=mantener('up')),
      'deportes':dict(correr_derecha=mantener('right'),correr_izquierda=mantener('left'),
        correr_arriba=mantener('up'),correr_abajo=mantener('down'),pase=pulso('a',6),tiro=pulso('b',12),
        carrera_tiro=secuencia(('right',24),('right+b',8),('',12)),
        alternar=secuencia(('a',4),('',4),('b',4),('',4),repetir=True)),
      'puzle':dict(izquierda=pulso('left',6),derecha=pulso('right',6),rotar_a=pulso('a',6),
        rotar_b=pulso('b',6),bajar=mantener('down'),confirmar=pulso('a',8),
        mover_rotar=secuencia(('left',6),('',6),('a',6),('',6),('down',24))),
      'rol':dict(explorar_norte=mantener('up'),explorar_este=mantener('right'),
        explorar_sur=mantener('down'),explorar_oeste=mantener('left'),hablar=pulso('a',8),
        dialogo=secuencia(('a',6),('',24),repetir=True),cancelar=pulso('b',8),
        elegir_opcion=secuencia(('down',6),('',10),('a',8))),
      'estrategia':dict(cursor_arriba=pulso('up',6),cursor_abajo=pulso('down',6),
        cursor_izquierda=pulso('left',6),cursor_derecha=pulso('right',6),seleccionar=pulso('a',8),
        seleccionar_mover=secuencia(('a',8),('',12),('right',8),('',12),('a',8)),cancelar=pulso('b',8)),
      'pinball':dict(lanzar=secuencia(('down',40),('',20)),lanzar_a=secuencia(('a',40),('',20)),
        paletas=secuencia(('left+a',8),('',8),('right+b',8),('',8),repetir=True),
        paleta_izquierda=pulso('left',12),paleta_derecha=pulso('a',12)),
      'multijuego':dict(elegir_a=pulso('a',10),elegir_b=pulso('b',10),
        elegir_siguiente=secuencia(('down',8),('',16),('a',8)),
        elegir_pagina=secuencia(('right',8),('',16),('a',8)),
        intentar_juego=secuencia(('right',30),('right+a',20),('b',10))),
    }
    for genero in ('disparos_horizontal','disparos_vertical'):
        acciones[genero]={}
        for direccion in ('','up','down','left','right'):
            for arma in ('a','b'):
                acciones[genero][f'{direccion or "quieto"}_{arma}']=dict(mantener=direccion,
                    pulsar=arma,duracion_pulso=2,periodo=4)
        acciones[genero]['barrido']=secuencia(('up+a',15),('right+a',15),('down+a',15),('left+a',15))
    # Mantener el nombre antiguo para invocaciones anteriores.
    acciones['disparos']=copy.deepcopy(acciones['disparos_horizontal'])
    perfiles={}
    for genero,macros in acciones.items():
        perfil=copy.deepcopy(base)
        perfil['acciones']={n:dict(a,fase='juego') for n,a in macros.items()}
        perfil['acciones'].update({n:dict(a,fase='menu') for n,a in menu.items()})
        perfil['acciones'].update({n:dict(a,fase='recuperacion') for n,a in recuperar.items()})
        if genero in ('rol','estrategia','multijuego'):perfil['vision']['roi']=[0,8,256,240]
        perfiles[genero]=perfil
    perfiles['periferico']=dict(copy.deepcopy(base),requiere_periferico=True,
                               descripcion='No puede explorar con un único mando NES estándar')
    (HERE/'explorador.json').write_text(json.dumps(perfiles,ensure_ascii=False,indent=1)+'\n')
    print(f'{len(perfiles)} perfiles escritos; no se ejecutó ningún emulador.')


if __name__=='__main__':main()
