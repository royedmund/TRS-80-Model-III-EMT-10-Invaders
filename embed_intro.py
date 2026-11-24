#!/usr/bin/env python3
"""Embed the original INTRO.MID as absolute LDOS tick events, two clock rates.
No dependencies. No MIDI parsing or disk reads during the game.
"""
from pathlib import Path
from collections import defaultdict
ROOT=Path(__file__).resolve().parent

def tables():
    raw=(ROOT/'INTRO.MID').read_bytes()
    assert raw[:14]==b'MThd\x00\x00\x00\x06\x00\x00\x00\x01\x00\x60'
    assert raw[14:18]==b'MTrk' and int.from_bytes(raw[18:22],'big')==len(raw)-22
    i=22; tick=0; tempo=500000; elapsed=0; events=[]; pitches=set()
    def vlq():
        nonlocal i
        n=0
        while True:
            b=raw[i];i+=1;n=(n<<7)|(b&127)
            if b<128:return n
    while i<len(raw):
        delta=vlq();tick+=delta;elapsed+=delta*tempo
        s=raw[i];i+=1
        if s==255:
            kind=raw[i];i+=1;n=vlq();payload=raw[i:i+n];i+=n
            if kind==81:tempo=int.from_bytes(payload,'big')
            if kind==47:break
            continue
        assert s in (128,144,176,192)
        n=1 if s==192 else 2; data=bytes([s])+raw[i:i+n];i+=n
        assert all(x<128 for x in data[1:])
        if s==144 and data[2]:pitches.add(data[1])
        events.append((elapsed,data))
    assert elapsed==8*96*1000000
    result=[]
    for hz in (25,30):
        groups=defaultdict(list)
        for t,data in events:
            at=(t*hz+48*1000000)//(96*1000000)
            groups[at].append(data)
        lines=[f'intro{hz}:']
        for at,messages in sorted(groups.items()):
            chunk=bytearray()
            for data in messages:
                if len(chunk)+len(data)>18:
                    lines.append('    db '+','.join(map(str,[at,len(chunk),*chunk])));chunk.clear()
                chunk.extend(data)
            if chunk:lines.append('    db '+','.join(map(str,[at,len(chunk),*chunk])))
        lines.append(f'    db {8*hz},0')
        result.extend(lines)
    result.append('intro_pitches: db '+','.join(map(str,sorted(pitches)))+',0')
    return '\n'.join(result)+'\n'

if __name__=='__main__':
    p=ROOT/'INVADERS.ASM';s=p.read_text();start='; BEGIN GENERATED INTRO TABLES\n';end='; END GENERATED INTRO TABLES\n';a=s.index(start)+len(start);b=s.index(end,a);p.write_text(s[:a]+tables()+s[b:]);print('Embedded INTRO.MID for both clocks')
