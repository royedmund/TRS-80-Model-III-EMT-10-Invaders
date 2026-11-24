#!/usr/bin/env python3
"""Compare actual render opcodes using nominal Z80 T-states (no waits/IRQs).
Usage: python benchmark_render.py ../invaders-v04
Uses mock CPU, not a cycle-accurate emulator. Each test starts with identical
logical game state and compares resulting display and collision state.
"""
import sys
from pathlib import Path
import test_game as h
CURRENT=Path(__file__).resolve().parent

def cycles(c,p):
    op=c.mem[p]; sub=c.mem[(p+1)&65535]
    if 0x40<=op<=0x7f:return 7 if 6 in ((op>>3)&7,op&7) else 4
    if op&0xc7==6:return 10 if (op>>3)&7==6 else 7
    if op&0xcf==1:return 10
    if op&0xcf in (3,11):return 6
    if op&0xc7 in (4,5):return 11 if (op>>3)&7==6 else 4
    if op&0xcf==9:return 11
    if op in (0x3a,0x32):return 13
    if op in (0x2a,0x22):return 16
    if op in (0x1a,0x12):return 7
    if op==0xeb:return 4
    if op==0xc6:return 7
    if 0x80<=op<=0xbf:return 7 if op&7==6 else 4
    if op in (0xd6,0xe6,0xee,0xf6,0xfe):return 7
    if op==0xed:
        if sub==0xa0:return 16
        if sub==0xb0:return 21*((c.pair(0) or 65536)-1)+16
        if sub&0xcf in (0x43,0x4b):return 20
        if sub&0xcf in (0x42,0x4a):return 15
    if op==0xcb:return 12 if sub&7==6 else 8
    if op==0xc3 or op&0xc7==0xc2:return 10
    if op==0xcd:return 17
    if op==0xc9:return 10
    if op&0xc7==0xc0:return 11 if c.cond((op>>3)&7) else 5
    if op&0xcf==0xc5:return 11
    if op&0xcf==0xc1:return 10
    if op==0x10:return 13 if c.r[0]!=1 else 8
    if op in (0xdb,0xd3):return 11
    raise ValueError(f'Unsupported opcode {op:02x} at {p:04x}')

class ProfileCPU(h.CPU):
    # run() calls fetch at the start of each instruction as well as on operands;
    # step counter advances only for the first fetch of each instruction.
    def __init__(self):
        super().__init__(mode='fx',break_at=None)
        self.ts=0;self.laststep=-1
    def fetch(self):
        if self.laststep!=self.steps:
            self.ts+=cycles(self,self.pc);self.laststep=self.steps
        return super().fetch()

def choose(root):
    h.ROOT=root
    h.SYMS={k:int(v,16) for v,k in (l.split() for l in (root/'INVADERS.MAP').read_text().splitlines())}

def render(root,settings,flags):
    choose(root);sy=h.SYMS;c=ProfileCPU()
    def put(k,v):c.mem[sy[k]]=v
    def call(label):
        c.pc=sy[label];c.sp=0xf000;c.push(0x402d);c.run(maxsteps=c.steps+1000000);assert c.sp==0xf000
    for k,v in dict(ax=5,ay=2,px=31,lives=3,wave=1,alive=sum(flags),direction=1,anim=0,**{}).items():put(k,v)
    for k,v in settings.items():put(k,v)
    c.mem[sy['aliens']:sy['aliens']+35]=bytes(flags)
    c.mem[sy['shield']:sy['shield']+128]=bytes([32])*128
    for x in (5,21,37,53):c.setpair(2,sy['shield']+x);call('make_shield')
    c.ts=0;steps=c.steps;call('render');cost=c.ts
    state=tuple(c.mem[sy[k]] for k in ('shoty','alive','launchx','launchy','effect','ufox'))+tuple(bytes(c.mem[sy[k]:sy[k]+n]) for k,n in [('score',4),('hiscore',4),('aliens',35),('shield',128)])
    return cost,c.steps-steps,bytes(c.mem[0x3c00:0x4000]),state

def main():
    if len(sys.argv)!=2:raise SystemExit(__doc__)
    baseline=Path(sys.argv[1]).resolve()
    full=[1]*35;sparse=[int(i%4==0) for i in range(35)]
    cases=[('35 aliens, initial',{},full),('35 aliens, animation B',{'anim':1},full),('Laser hit',{'shotx':6,'shoty':2},full),('Formation over shields',{'ay':6,'ax':10},full),('Sparse formation',{'anim':1,'ax':18},sparse),('Demo HUD, bomb, saucer',{'demo':1,'bomby':10,'bombx':20,'ufox':40},full),('Mystery ship hit',{'ufox':20,'shotx':21,'shoty':1},full)]
    print('Scenario | v0.4 T-states | v0.5 T-states | reduction | same VRAM/state')
    for name,settings,flags in cases:
        a=render(baseline,settings,flags);b=render(CURRENT,settings,flags)
        assert a[2:]==b[2:],name
        print(f'{name} | {a[0]:,} | {b[0]:,} | {(1-b[0]/a[0])*100:.1f}% | PASS')
    # Sweep all valid formation depths, phases, edge positions and several shot positions.
    n=0
    for ay in range(2,7):
      for ax in (1,5,19):
       for anim in (0,1):
        for sy,sx in ((0,0),(ay,ax+1),(ay+2,ax+8),(ay+7,ax+43)):
         settings=dict(ay=ay,ax=ax,anim=anim,shoty=sy,shotx=sx)
         assert render(baseline,settings,full)[2:]==render(CURRENT,settings,full)[2:],settings
         n+=1
    print(f'PASS {n} additional render equivalence cases (VRAM and collision state).')
if __name__=='__main__':main()
