#!/usr/bin/env python3
"""Cassette FX regression checks; run after python build.py."""
from test_game import CPU, SYMS

def call(c,label):
    c.push(0x402d)
    c.pc=SYMS[label]
    c.run(maxsteps=c.steps+2000000)
    assert c.sp==0xf000

def put(c,k,v):
    c.mem[SYMS[k]]=v

def get(c,k):
    return c.mem[SYMS[k]]

def cassette(c):
    return [v for p,v in c.ports if p==255]

for effect,pairs in [(1,16),(2,24),(3,18),(4,28)]:
    c=CPU(break_at=None)
    put(c,'effect',effect)
    call(c,'effect_play')
    assert cassette(c)==[1,0]*pairs
    assert get(c,'effect')==0
    print('PASS effect',effect,pairs,'pulse pairs')

for demo,effect in [(1,1),(0,0)]:
    c=CPU(break_at=None)
    put(c,'demo',demo)
    put(c,'effect',effect)
    call(c,'effect_play')
    assert not cassette(c) and not get(c,'effect')
print('PASS demo and idle silence')

c=CPU(break_at=None)
put(c,'midi',1)
put(c,'musicwait',6)
put(c,'effect',4)
put(c,'qcount',3)
c.mem[SYMS['queue']:SYMS['queue']+3]=bytes([144,60,80])
call(c,'effect_play')
assert cassette(c)==[1,0]*28
assert bytes(v for _,v in c.uart)==bytes([144,60,80])
print('PASS MIDI service during explosion')

c=CPU(break_at=None)
put(c,'ufox',20)
put(c,'shotx',21)
put(c,'shoty',1)
call(c,'render_ufo')
assert get(c,'effect')==4 and not get(c,'ufox') and not get(c,'shoty')
assert bytes(c.mem[SYMS['score']:SYMS['score']+4])==b'0500'
print('PASS UFO hit selects unique explosion and awards 500 points')
