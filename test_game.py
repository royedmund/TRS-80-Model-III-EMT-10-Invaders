#!/usr/bin/env python3
"""Execute the assembled CMD in a minimal Z80 instruction harness.
Mocks LDOS calls, keyboard, UART and timer. Not a hardware/full-system emulator.
Tests actual game opcodes; no real instruction timing, interrupts or hardware emulation.
"""
from pathlib import Path
import struct
ROOT=Path(__file__).resolve().parent
class CPU:
 def __init__(self,mode='midi',clock='3',break_at=400,uart_ok=True,action='full'):
  self.mem=bytearray(65536);p=0;cmd=(ROOT/'INVADERS.CMD').read_bytes()
  while cmd[p]==1:
   n=cmd[p+1] or 256;adr=int.from_bytes(cmd[p+2:p+4],'little');self.mem[adr:adr+n-2]=cmd[p+4:p+2+n];p+=n+2
  assert cmd[p:p+2]==bytes([2,2]);self.pc=int.from_bytes(cmd[p+2:p+4],'little');self.sp=0xf000
  self.r=[0]*8;self.z=False;self.c=False;self.pv=False;self.steps=0;self.ticks=0;self.smf=b'';self.mode=mode;self.max_score=0;self.seen_game=False;self.fired=False;self.moved=False;self.pos=0;self.clock=clock;self.break_at=break_at;self.uart_ok=uart_ok;self.uart=[];self.ports=[];self.text='';self.closed=False;self.action=action;self.intro_tick=None;self.game_tick=None;self.game_uart=None;self.first_frame=None;self.demo_enter=None;self.demo_return=None;self.demo_score=0;self.demo_frames=0

 def word(self,a):return self.mem[a]|self.mem[(a+1)&65535]<<8
 def writeword(self,a,x):self.mem[a]=x&255;self.mem[(a+1)&65535]=(x>>8)&255
 def pair(self,i):return self.sp if i==3 else (self.r[2*i]<<8)|self.r[2*i+1]
 def setpair(self,i,x):
  x&=65535
  if i==3:self.sp=x
  else:self.r[2*i]=x>>8;self.r[2*i+1]=x&255
 def get(self,i):
  if i!=6:return self.r[i]
  return self.mem[self.pair(2)]
 def set(self,i,x):
  if i==6:self.mem[self.pair(2)]=x&255
  else:self.r[i]=x&255
 def fetch(self):v=self.mem[self.pc];self.pc=(self.pc+1)&65535;return v
 def fetchw(self):lo=self.fetch();return lo|(self.fetch()<<8)
 def push(self,x):self.sp=(self.sp-2)&65535;self.writeword(self.sp,x)
 def pop(self):x=self.word(self.sp);self.sp=(self.sp+2)&65535;return x
 def cond(self,i):return [not self.z,self.z,not self.c,self.c,not self.pv,self.pv,False,False][i]
 def alu(self,op,v):
  a=self.r[7]
  if op==0:r=a+v;self.c=r>255
  elif op==2 or op==7:r=a-v;self.c=r<0
  elif op==4:r=a&v;self.c=False
  elif op==5:r=a^v;self.c=False
  elif op==6:r=a|v;self.c=False
  else:raise AssertionError(op)
  self.z=(r&255)==0
  if op!=7:self.r[7]=r&255
 def run(self,maxsteps=10000000):
  while self.steps<maxsteps:
   self.steps+=1
   # Mock 30/25 Hz ticks using a deterministic instruction-count clock.
   # Real-time performance and interrupt behaviour are not modelled.
   if self.steps%3000==0:
    self.ticks+=1;self.mem[0x4288]=self.ticks&255
   self.mem[0x3810]=4 if self.clock=='2' else 8
   p=self.pc
   if p==SYMS['intro_loop'] and self.intro_tick is None:self.intro_tick=self.ticks
   if p==SYMS['frame_wait'] and self.game_tick is None:self.game_tick=self.ticks;self.game_uart=len(self.uart);self.first_frame=bytes(self.mem[0x3c00:0x4000])
   if self.game_tick is not None:
    age=self.ticks-self.game_tick
    key=128 if age%9==0 else (32 if 10<=age<15 else (64 if 20<=age<25 else 0))
    if age>=100:key=4
   elif self.intro_tick is not None:
    age=self.ticks-self.intro_tick
    key=({'skip':128,'mute':2,'break':4}.get(self.action,0) if age>=30 else 0)
   else:key=(1 if self.mode=='midi' else 2)
   if self.mode.startswith('demo'):
    active=self.mem[SYMS['demo']]
    if active and self.demo_enter is None:self.demo_enter=self.ticks
    if self.demo_enter is not None and not active and p==SYMS['menu'] and self.demo_return is None:self.demo_return=self.ticks
    if self.demo_enter is None:key=128 if self.mode=='demo_manual' else 0
    elif self.demo_return is not None:key=4
    elif self.mode=='demo_manual' and self.ticks-self.demo_enter<4:key=128
    elif self.mode=='demo_manual' and 65<=self.ticks-self.demo_enter<68:key=1
    else:key=0
    if active and p==SYMS['frame_wait']:
     self.demo_score=max(self.demo_score,int(bytes(self.mem[SYMS['score']:SYMS['score']+4])))
   self.mem[0x3840]=key
   if self.break_at is not None and self.ticks>=self.break_at:self.mem[0x3840]=4
   if p==0x402d:return self
   if p==SYMS['frame_wait']:
    self.seen_game=True;self.fired |= self.mem[SYMS['shoty']]!=0;self.moved |= self.mem[SYMS['px']]!=31
    self.max_score=max(self.max_score,int(bytes(self.mem[SYMS['score']:SYMS['score']+4])))
   if p in (0x441c,0x4424,0x4428,0x0013,0x0049,0x0033):
    if p==0x441c:
     de=self.pair(1);self.mem[de:de+9]=b'TEST/MID\x03';self.z=True
    elif p==0x4424:self.z=True
    elif p==0x4428:self.closed=True;self.z=True
    elif p==0x0013:
     if self.pos<len(self.smf):self.r[7]=self.smf[self.pos];self.pos+=1;self.z=True
     else:self.r[7]=0x1c;self.z=False
    elif p==0x0049:self.r[7]=ord(self.clock)
    elif p==0x0033:self.text+=chr(self.r[7])
    self.pc=self.pop();continue
   op=self.fetch()
   if 0x40<=op<=0x7f:self.set((op>>3)&7,self.get(op&7))
   elif op&0xc7==0x06:self.set((op>>3)&7,self.fetch())
   elif op&0xcf==0x01:self.setpair((op>>4)&3,self.fetchw())
   elif op&0xcf in (0x03,0x0b):i=(op>>4)&3;self.setpair(i,self.pair(i)+(1 if op&15==3 else -1))
   elif op&0xc7 in (4,5):i=(op>>3)&7;v=(self.get(i)+(1 if op&7==4 else -1))&255;self.set(i,v);self.z=v==0
   elif op&0xcf==9:
    x=self.pair(2)+self.pair((op>>4)&3);self.setpair(2,x);self.c=x>65535
   elif op==0x3a:self.r[7]=self.mem[self.fetchw()]
   elif op==0x32:self.mem[self.fetchw()]=self.r[7]
   elif op==0x2a:self.setpair(2,self.word(self.fetchw()))
   elif op==0x22:self.writeword(self.fetchw(),self.pair(2))
   elif op==0x1a:self.r[7]=self.mem[self.pair(1)]
   elif op==0x12:self.mem[self.pair(1)]=self.r[7]
   elif op==0xeb:
    de=self.pair(1);self.setpair(1,self.pair(2));self.setpair(2,de)
   elif op==0xc6:v=self.r[7]+self.fetch();self.r[7]=v&255;self.c=v>255;self.z=self.r[7]==0
   elif 0x80<=op<=0xbf:self.alu((op>>3)&7,self.get(op&7))
   elif op in (0xd6,0xe6,0xee,0xf6,0xfe):self.alu((op>>3)&7,self.fetch())
   elif op==0xed:
    sub=self.fetch();i=(sub>>4)&3
    if sub==0xa0:
     hl=self.pair(2);de=self.pair(1);self.mem[de]=self.mem[hl]
     self.setpair(2,hl+1);self.setpair(1,de+1);self.setpair(0,self.pair(0)-1);self.pv=self.pair(0)!=0
    elif sub==0xb0:
     n=self.pair(0) or 65536;hl=self.pair(2);de=self.pair(1)
     for _ in range(n):self.mem[de]=self.mem[hl];hl=(hl+1)&65535;de=(de+1)&65535
     self.setpair(0,0);self.setpair(1,de);self.setpair(2,hl);self.pv=False
    elif sub&0xcf==0x43:self.writeword(self.fetchw(),self.pair(i))
    elif sub&0xcf==0x4b:self.setpair(i,self.word(self.fetchw()))
    elif sub&0xcf in (0x42,0x4a):
     x=self.pair(2);v=self.pair(i)+int(self.c);add=sub&15==10;res=x+v if add else x-v;self.setpair(2,res);self.c=res>65535 if add else res<0;self.z=(res&65535)==0
    else:raise AssertionError((hex(p),hex(op),hex(sub)))
   elif op==0xcb:sub=self.fetch();assert 0x40<=sub<=0x7f;self.z=not (self.get(sub&7)&(1<<((sub>>3)&7)))
   elif op==0xc3:self.pc=self.fetchw()
   elif op&0xc7==0xc2:a=self.fetchw();self.pc=a if self.cond((op>>3)&7) else self.pc
   elif op==0xcd:a=self.fetchw();self.push(self.pc);self.pc=a
   elif op==0xc9:self.pc=self.pop()
   elif op&0xc7==0xc0:
    if self.cond((op>>3)&7):self.pc=self.pop()
   elif op&0xcf==0xc5:i=(op>>4)&3;assert i<3;self.push(self.pair(i))
   elif op&0xcf==0xc1:i=(op>>4)&3;assert i<3;self.setpair(i,self.pop())
   elif op==0x10:
    d=self.fetch();self.r[0]=(self.r[0]-1)&255
    if self.r[0]:self.pc=(self.pc+(d if d<128 else d-256))&65535
   elif op==0xdb:assert self.fetch()==0xea;self.r[7]=64 if self.uart_ok else 0
   elif op==0xd3:
    port=self.fetch();v=self.r[7];self.ports.append((port,v))
    if port==0xeb:self.uart.append((self.ticks,v))
   else:raise AssertionError((hex(p),hex(op)))
  raise AssertionError('step limit exceeded')

SYMS={k:int(v,16) for v,k in (l.split() for l in (ROOT/'INVADERS.MAP').read_text().splitlines())}
def expected_intro(clock):
 # Read generated table from the CMD memory (checked separately against INTRO.MID).
 c=CPU(clock=clock);i=SYMS['intro25' if clock=='2' else 'intro30'];out=bytearray()
 while True:
  at,n=c.mem[i:i+2];i+=2
  if not n or at==(200 if clock=='2' else 240):break
  out.extend(c.mem[i:i+n]);i+=n
 return bytes.fromhex('B04000 B04200 B04300 B07B00')+out
if __name__=='__main__':
 for mode,clock,ready,action in [('midi','2',True,'full'),('midi','3',True,'full'),('midi','3',True,'skip'),('midi','3',True,'mute'),('fx','3',True,'full'),('midi','3',False,'full'),('midi','3',True,'break')]:
  c=CPU(mode,clock,uart_ok=ready,action=action).run();raw=bytes(v for _,v in c.uart)
  assert c.sp==0xf000
  if action=='break':assert not c.seen_game and raw.endswith(bytes.fromhex('B04000 B04200 B04300 B07B00'))
  else:
   assert c.seen_game and c.fired and c.moved,(mode,clock,action,c.seen_game,c.fired,c.moved)
   assert any(p==255 and v==1 for p,v in c.ports),'no cassette pulses'
  if mode=='midi' and ready:
   assert raw.startswith(bytes.fromhex('B04000 B04200 B04300 B07B00 C037'))
   if action=='full':
    assert raw.startswith(expected_intro(clock)),(clock,raw.hex())
    assert c.game_tick-c.intro_tick in ((200,201,202,203) if clock=='2' else (240,241,242,243)),(clock,c.game_tick,c.intro_tick)
   if action in ('full','skip'):
    assert raw[c.game_uart:].startswith(bytes.fromhex('B04000 B04200 B04300 B07B00 C047'))
    assert bytes.fromhex('902450 904344') in raw[c.game_uart:]
   if action=='mute':assert len(raw)==c.game_uart
   assert raw.endswith(bytes.fromhex('B04000 B04200 B04300 B07B00'))
  else:assert not raw
  print(f'PASS {mode} clock={clock} UART={ready} intro={action}: {len(raw)} UART bytes; gameplay={c.seen_game}; score={c.max_score}; intro ticks={None if c.game_tick is None or c.intro_tick is None else c.game_tick-c.intro_tick}')

 # Automatic attract and manual launch/cancel, using the same machine code.
 for mode,clock in [('demo_manual','2'),('demo_auto','3')]:
  c=CPU(mode,clock,break_at=None).run(maxsteps=16000000)
  assert c.demo_enter is not None and c.demo_return is not None,(mode,c.demo_enter,c.demo_return)
  assert c.fired and c.moved and c.demo_score>0,(mode,c.fired,c.moved,c.demo_score)
  assert bytes(c.mem[SYMS['hiscore']:SYMS['hiscore']+4])==b'0000'
  assert not c.uart and not any(p==255 and v for p,v in c.ports) and c.sp==0xf000
  if mode=='demo_auto':assert c.demo_enter in (180,181),(clock,c.demo_enter)
  else:assert 65<=c.demo_return-c.demo_enter<70
  assert b'DEMO - KEY FOR MENU' in c.first_frame
  print(f'PASS {mode} {clock}: launch {c.demo_enter}, return {c.demo_return}; score={c.demo_score}; silent, high score unchanged')
