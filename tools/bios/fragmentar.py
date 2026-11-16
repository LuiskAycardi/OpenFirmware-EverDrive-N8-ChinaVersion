"""fragmentar.py IMG OFFSET_SECTOR RUTA... — mueve el 2.º clúster de cada archivo (FAT32) a un clúster libre lejano."""
import struct, sys
img=bytearray(open(sys.argv[1],'rb').read()); off=int(sys.argv[2])*512
bs=img[off:off+512]
bps=struct.unpack('<H',bs[11:13])[0]; spc=bs[13]; res=struct.unpack('<H',bs[14:16])[0]; nf=bs[16]
fsz=struct.unpack('<I',bs[36:40])[0]; root=struct.unpack('<I',bs[44:48])[0]
fat=off+res*bps; data=fat+nf*fsz*bps; cl=spc*bps
def g(c): return struct.unpack('<I',img[fat+4*c:fat+4*c+4])[0]&0x0FFFFFFF
def s(c,v):
    for k in range(nf): img[fat+k*fsz*bps+4*c:fat+k*fsz*bps+4*c+4]=struct.pack('<I',v)
def cad(c):
    r=[c]
    while g(c)<0x0FFFFFF8: c=g(c); r.append(c)
    return r
def dirent(dc, nombre):
    for c in cad(dc):
        b=data+(c-2)*cl
        for e in range(0,cl,32):
            n=img[b+e:b+e+11]
            if n==nombre: return b+e
    raise SystemExit('no encuentro '+repr(nombre))
def n83(x):
    a,_,e=x.partition('.'); return (a.ljust(8)+e.ljust(3)).upper().encode()
libre=fsz*bps//4-1000
for ruta in sys.argv[3:]:
    dc=root
    partes=ruta.split('/')
    for p in partes[:-1]:
        e=dirent(dc,n83(p)); dc=struct.unpack('<H',img[e+20:e+22])[0]<<16|struct.unpack('<H',img[e+26:e+28])[0]
    e=dirent(dc,n83(partes[-1])); c0=struct.unpack('<H',img[e+20:e+22])[0]<<16|struct.unpack('<H',img[e+26:e+28])[0]
    ch=cad(c0)
    while g(libre)!=0: libre-=1
    a,b=ch[1],libre
    img[data+(b-2)*cl:data+(b-1)*cl]=img[data+(a-2)*cl:data+(a-1)*cl]
    s(ch[0],b); s(b,g(a)); s(a,0); img[data+(a-2)*cl:data+(a-1)*cl]=bytes(cl)
    libre-=7
    print(ruta,'clúster',a,'->',b,'cadena',len(ch))
open(sys.argv[1],'wb').write(img)
