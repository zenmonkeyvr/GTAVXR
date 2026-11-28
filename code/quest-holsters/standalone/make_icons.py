from pathlib import Path
from struct import unpack_from as un
import sys
d=Path(sys.argv[1])
s=(d/'hud.gfx').read_bytes()
def rectlen(b):return (5+4*(b[0]>>3)+7)//8
def tags(b):
 off=0
 while off<len(b):
  h,=un('<H',b,off);off+=2;n=h&63
  if n==63:n,=un('<I',b,off);off+=4
  yield h>>6,b[off:off+n];off+=n
root=list(tags(s[12+rectlen(s[8:]):]))
class Bits:
 def __init__(self,b): self.b=b;self.i=0
 def get(self,n,signed=False):
  x=0
  for _ in range(n):
   x=x*2+((self.b[self.i//8]>>(7-self.i%8))&1);self.i+=1
  return x-(1<<n) if signed and n and x>>(n-1) else x
 def pair(self,n):return (self.get(n,True),self.get(n,True))
sprites={un('<H',b)[0]:b for t,b in root if t==39}
shapes={un('<H',b)[0]:b for t,b in root if t in (2,22,32)}
exports={b[4:-1].decode():un('<H',b,2)[0] for t,b in root if t==56 and b[:2]==b'\1\0'}
import re
wanted=[int(x,16) for x in re.findall(r'\{0x([0-9A-F]+)u,',Path(sys.argv[2]).read_text())]
mapping={}
for k in range(8):
 h=None
 for t,b in tags(sprites[exports['SLOT_WEAPONS_'+str(k)]][4:]):
  if t==43 and b.startswith(b'INT'):h=int(b[3:-1])&0xffffffff
  if h and t==26 and b[0]&2:mapping[h]=un('<H',b,3)[0];h=None
def leaf(i):
 if i in shapes:return i
 if i in sprites:
  for t,b in tags(sprites[i][4:]):
   if t==26 and b[0]&2:return leaf(un('<H',b,3)[0])

from PIL import Image,ImageDraw
from struct import pack
textures={un('<H',b)[0]:Image.open(d/(b[11:11+b[10]].decode().lower()+'.dds')).convert('RGBA') for t,b in root if t==1009 and b[11:].startswith(b'Weapons')}
def render(i):
 b=shapes[i];r=Bits(b[2:]);n=r.get(5);x0,x1=r.pair(n);y0,y1=r.pair(n)
 off=2+rectlen(b[2:]);nf=b[off];off+=1;styles=[]
 for _ in range(nf):
  assert b[off] in (64,65,66,67)
  tex=un('<H',b,off+1)[0];r=Bits(b[off+3:])
  sx,sy=(v/65536 for v in r.pair(r.get(5))) if r.get(1) else (1,1)
  rx,ry=(v/65536 for v in r.pair(r.get(5))) if r.get(1) else (0,0)
  tx,ty=r.pair(r.get(5));styles.append((tex,sx,sy,rx,ry,tx,ty));off+=3+(r.i+7)//8
 assert b[off]==0
 r=Bits(b[off+1:]);fb=r.get(4);lb=r.get(4);paths=[[] for _ in styles];path=[];x=y=0;f0=f1=0
 def flush():
  if len(path)>2:
   for index in set([f0,f1])-{0}:paths[index-1].append(path[:])
 while True:
  if r.get(1):
   straight=r.get(1);n=r.get(4)+2
   if straight:
    if r.get(1):dx,dy=r.pair(n)
    elif r.get(1):dx,dy=0,r.get(n,True)
    else:dx,dy=r.get(n,True),0
    x+=dx;y+=dy;path.append((x,y))
   else:
    dx,dy=r.pair(n);ax,ay=r.pair(n);cx,cy=x+dx,y+dy;ex,ey=cx+ax,cy+ay
    for t in (.25,.5,.75,1):path.append(((1-t)**2*x+2*t*(1-t)*cx+t*t*ex,(1-t)**2*y+2*t*(1-t)*cy+t*t*ey))
    x,y=ex,ey
  else:
   flags=r.get(5);flush()
   if not flags:break
   assert not(flags&16)
   if flags&1:x,y=r.pair(r.get(5))
   if flags&2:f0=r.get(fb)
   if flags&4:f1=r.get(fb)
   if flags&8:r.get(lb)
   path=[(x,y)]
 scale=min(170/(x1-x0),78/(y1-y0))
 size=(max(1,round((x1-x0)*scale)),max(1,round((y1-y0)*scale)))
 image=Image.new('RGBA',size)
 for style,polys in zip(styles,paths):
  tex,sx,sy,rx,ry,tx,ty=style
  det=sx*sy-rx*ry
  matrix=(sy/det/scale,-ry/det/scale,(sy*(x0-tx)-ry*(y0-ty))/det,-rx/det/scale,sx/det/scale,(sx*(y0-ty)-rx*(x0-tx))/det)
  pixels=textures[tex].transform(size,Image.Transform.AFFINE,matrix,Image.Resampling.BICUBIC)
  mask=Image.new('L',size);pen=ImageDraw.Draw(mask)
  for poly in polys:pen.polygon([((x-x0)*scale,(y-y0)*scale) for x,y in poly],fill=255)
  image.paste(pixels,(0,0),mask)
 assert image.getbbox()
 return image
mapping[0xa0973d5e]=exports['WEAPON_THROWN_BZ_GAS']
images={h:render(leaf(mapping[h])) for h in wanted if h in mapping}
out=d/'original-hud.icons'
with out.open('wb') as f:
 f.write(b'GWH1'+pack('<I',len(images)))
 for h,im in images.items():f.write(pack('<IHH',h,*im.size)+im.tobytes())

if len(images)!=108: raise ValueError("This GTA V HUD version is unsupported")
print("Generated 108 weapon icons from your game.")
