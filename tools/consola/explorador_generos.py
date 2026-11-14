"""Asignación orientativa por título; nunca deduce género a partir del mapper."""
import pathlib
import re

# Reglas locales para escoger vocabularios iniciales; no son etiquetas verificadas
# ni indican que el bot conozca las mecánicas o el objetivo de estos juegos.
REGLAS=[
 ('multijuego',r'\d+[- ]in[- ]\d+|\d+\+\d+[- ]in|Action 53|Caltron|Quattro|Maxi 15|Mindblower|Unchained Melody|World Championships'),
 ('estrategia',r'Battle Chess|Chess Academy|Famicom Wars|Aoki Ookami|Napoleon Senki|Sangokushi|Olympic I\.Q\.|Bakushou|Money Game|Ai Sensei'),
 ('rol',r'Dragon Ball Z Gaiden|Kyoushuu|Akuma-kun|Ganbare Goemon Gaiden|Madara|Lagrange Point|Megami Tensei|SD Keiji|Famicom Jump|Fengshen|Zhong Zhuang|Shenghuo|Guimei'),
 ('lucha',r'Punch-Out|Mortal Kombat|Street Fighter|Fighter V|Fatal Fury|Super Fighter|Super Blaster|King of Fighters|Fighting Hero|Juudou|Super Mortal|Mali & Lugi'),
 ('beat_em_up',r'Teenage Mutant Ninja|Final Fight|Janggun|Bao Qingtian|Rahmen Man|Power Rangers|Shin Samurai'),
 ('deportes',r'Base Wars|Baseball|Yakyuu|Pro!.*90|Namco Classic|Pennant|Soccer|Football|V.Ball|Volleyball|Dodge Danpei|Decathlon|Pingpong'),
 ('carreras',r'Minekart|Family Circuit|Jovial Race|Death Race|Mi Hun Che'),
 ('pinball',r'^High Speed|Pinball'),
 ('puzle',r'Klax|Pac-Man|Quinty|Shuiguan|Dancing Blocks|Bubble Bath|Magic Jewelry|Mahjong|Maque|Honey Peach|Popo Team'),
 ('disparos_vertical',r'ImageFight|Crisis Force|Firehawk|F-15|Sidewinder|Touhou'),
 ('disparos_horizontal',r'Abadox|Gradius|Salamander|Fantasy Zone|After Burner|Uchuusen|Laser Invasion|Cobra Mission'),
 ('accion_cenital',r'King Kong 2|Ai Senshi Nicol|Esper Dream|Senjou no Ookami|Alien Syndrome|Anguna'),
 ('plataformas',r'Heroes of the Lance|Doki Doki Panic|Bubble Bobble|Toy Story|Amagon|Adventure Island|Beetlejuice|Bible Adventures|Wally Bear|Akumajou|Tiny Toon|Rolling Thunder|Power Blazer|Impossible Mission|Deadly Towers|Wario|Super Mario|Flintstones|Green Beret|Skull & Crossbones|Spartan|Gimmick|Dragon Buster|Kaiketsu|Goonies|Magic Dragon|Mega Man|Rockman|Super Lion King|Pocahontas|Labi Xiao Xin|Panda Prince|Weilai Xiaozi|Bio Senshi|Q Boy|Challenge of the Dragon|Ys III|Devil Man|Koko Adventure|Lupin|Splatterhouse|Atlantis|Mighty Bomb|Cheetahmen|Time Diver|Gluk|Magic Kid|Fudou Myouou|Mali Boss|Dragon Ninja|Jajamaru|Silent Assault|Kyonshiizu|Hell Fighter')]

DISPOSITIVOS={7:'Zapper VS',8:'Zapper',9:'dos Zapper',10:'Bandai Hyper Shot',
 11:'Power Pad',12:'Power Pad',13:'Family Trainer',14:'Family Trainer',
 15:'Arkanoid paddle',16:'Arkanoid paddle',17:'dos Arkanoid paddle',
 19:'Pachinko',20:'Exciting Boxing',21:'mando Mahjong',22:'Party Tap',23:'tableta Oeka Kids',
 24:'lector Barcode Battler',25:'piano',26:'Pokkun Moguraa',27:'Top Rider',
 28:'dos mandos para un jugador',30:'teclado Doremikko',31:'R.O.B.',
 35:'teclado Family BASIC',36:'teclado PEC',37:'teclado Bit79',38:'teclado Subor',
 39:'Subor y ratón',40:'Subor y ratón',41:'ratón SNES',44:'bicicleta Racermate',45:'U-Force'}


def clasificar(rom):
    ruta=pathlib.Path(rom)
    nombre=ruta.name
    with ruta.open('rb') as f:h=f.read(16)
    periferico=None
    if len(h)==16 and h[:4]==b'NES\x1a' and h[7]&12==8:
        periferico=DISPOSITIVOS.get(h[15])
    if periferico:
        return dict(perfil='periferico',fuente='Dispositivo de entrada declarado en cabecera NES 2.0',
                    revisar=True,dispositivo=periferico,
                    estado='Revisar si existe un modo compatible con mando estándar antes de automatizar')
    for perfil,patron in REGLAS:
        if re.search(patron,nombre,re.I):
            return dict(perfil=perfil,fuente='Regla local por título; género orientativo',
                        revisar=True,dispositivo=None,estado='Pendiente de validar controles y progreso')
    return dict(perfil='generico',fuente='Sin clasificación suficiente',revisar=True,
                dispositivo=None,estado='Revisar género antes de una tanda extensa')
