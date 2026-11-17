"""Small original synthesized croak and seamless woodland ambience."""
from pathlib import Path
import math,random,struct,wave
OUT=Path(__file__).resolve().parents[1]/'game/assets/audio'
OUT.mkdir(parents=True,exist_ok=True)
rate=22050
def save(name,seconds,function):
 with wave.open(str(OUT/name),'wb') as w:
  w.setparams((1,2,rate,0,'NONE','not compressed'))
  w.writeframes(b''.join(struct.pack('<h',int(max(-1,min(1,function(i/rate)))*30000)) for i in range(int(seconds*rate))))
def croak(t):
 result=0
 for start,width,frequency in [(0,.22,115),(.24,.33,89)]:
  u=(t-start)/width
  if 0<u<1:
   envelope=math.sin(math.pi*u)**.65
   phase=2*math.pi*frequency*t+1.4*math.sin(2*math.pi*35*t)
   result+=(math.sin(phase)+.35*math.sin(phase*2)+.15*math.sin(phase*3))*envelope*.42
 return result
save('croak.wav',.70,croak)
random.seed(710);phases=[random.uniform(0,math.tau) for _ in range(20)]
def woodland(t):
 water=sum(math.sin(math.tau*(37+i*13)*t+phases[i])*.004 for i in range(20))
 birds=0
 for start,pitch in [(2,2100),(6,2600),(11,1850),(15,2300)]:
  u=t-start
  if 0<u<.8:
   env=math.sin(math.pi*u/.8)**2
   birds+=math.sin(math.tau*(pitch*u+130*math.sin(u*19)))*env*.06
 return water+birds
save('woodland.wav',20,woodland)
