#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Original eight-second EMT-10 intro, no external dependencies."""
from pathlib import Path
import struct

PPQN = 96

def vlq(n):
    b = [n & 127]
    while n >= 128:
        n >>= 7
        b.insert(0, (n & 127) | 128)
    return bytes(b)

def make():
    events = [(0, 0, bytes.fromhex('ff510307a120')),
              (0, 1, bytes([192, 55]))]  # Upright Bass + Brass
    def note(t, n, vel, duration):
        events.append((t, 3, bytes([144, n, vel])))
        events.append((t+duration, 0, bytes([128, n, 0])))
    for t,n in enumerate([36,36,39,35,36,43,39,35,36,36,41,43,38,35,36,36]):
        note(t*96,n,86 if t%4==0 else 67,72)
    for t,n in [(384,60),(480,63),(576,67),(672,70),(1152,70),(1248,67),(1344,63)]:
        note(t,n,91,80)
    for t,chord in [(768,[60,63,67]),(960,[62,65,70]),(1440,[60,63,67,72])]:
        for n in chord: note(t,n,100,90)
    events.append((1536,4,bytes([176,123,0])))
    events.append((1536,5,bytes.fromhex('ff2f00')))
    tr=bytearray();last=0
    for tick,_,data in sorted(events):
        tr.extend(vlq(tick-last));tr.extend(data);last=tick
    return b'MThd'+struct.pack('>IHHH',6,0,1,PPQN)+b'MTrk'+struct.pack('>I',len(tr))+tr

if __name__ == '__main__':
    p=Path(__file__).with_name('INTRO.MID');p.write_bytes(make())
    print(f'{p.name}: {p.stat().st_size} bytes, 8 seconds')
