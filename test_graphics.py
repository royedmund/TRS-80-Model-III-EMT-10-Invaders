#!/usr/bin/env python3
"""Focused opcode tests for the recreated 35-alien graphics and collisions."""
from test_game import CPU,SYMS
from pathlib import Path

def put(c,label,value):c.mem[SYMS[label]]=value
def get(c,label):return c.mem[SYMS[label]]
def call(c,label):
    c.pc=SYMS[label];c.sp=0xf000;c.push(0x402d);c.run(maxsteps=c.steps+500000)
    assert c.sp==0xf000

def initial():
    c=CPU(mode='fx',break_at=None)
    for k,v in {'ax':5,'ay':2,'px':31,'lives':3,'wave':1,'alive':35,'direction':1,'anim':0}.items():put(c,k,v)
    c.mem[SYMS['aliens']:SYMS['aliens']+35]=bytes([1])*35
    c.mem[SYMS['shield']:SYMS['shield']+128]=bytes([32])*128
    for x in (5,21,37,53):
        c.setpair(2,SYMS['shield']+x);call(c,'make_shield')
    return c
c=initial();call(c,'render');v=bytes(c.mem[0x3c00:0x4000]);assert b'SCORE:0000  HI:0000  LIVES:3  WAVE:1' in v[:64]
# Every alien has at least one lit pixel in its two-row bounding box.
for row,dy in enumerate((0,1,3,5,6)):
    for col in range(7):
        x=5+7*col;y=2+dy
        assert any(128<b<=191 for b in v[y*64+x:y*64+x+3]+v[(y+1)*64+x:(y+1)*64+x+3]),(row,col)
assert all(v[11*64+x+2]==191 for x in (5,21,37,53))
Path(__file__).with_name('FIRST-FRAME.BIN').write_bytes(v)
put(c,'anim',1);call(c,'render');assert bytes(c.mem[0x3c00:0x4000])!=v
print('PASS first frame: 35 visible alien masks, four shields, HUD and animation')
for row,points in enumerate((25,20,20,10,10)):
    c=initial();put(c,'shotx',6);put(c,'shoty',2+(0,1,3,5,6)[row]);call(c,'render')
    assert get(c,'alive')==34 and c.mem[SYMS['aliens']+row*7]==0 and get(c,'shoty')==0
    assert int(bytes(c.mem[SYMS['score']:SYMS['score']+4]))==points
    assert int(bytes(c.mem[SYMS['hiscore']:SYMS['hiscore']+4]))==points
print('PASS five row hits, distinct 25/20/10 scoring and high score')
c=initial();put(c,'ufox',20);put(c,'shotx',21);put(c,'shoty',1);call(c,'render');assert not get(c,'ufox') and not get(c,'shoty');assert bytes(c.mem[SYMS['score']:SYMS['score']+4])==b'0500';print('PASS mystery saucer 500-point hit')
for row in (11,12):
    c=initial();put(c,'shotx',5);put(c,'shoty',row+1);call(c,'advance_shot');assert get(c,'shoty')==0 and c.mem[SYMS['shield']+(row-11)*64+5]==32
print('PASS projectile damages either bunker row')
c=initial();put(c,'launchy',13);put(c,'launchx',32);put(c,'bombwait',1);call(c,'advance_bomb');assert get(c,'lives')==2 and get(c,'bomby')==0
print('PASS bomb spawned at cannon height hits immediately')
