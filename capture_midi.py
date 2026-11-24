#!/usr/bin/env python3
"""Decode this game's raw RS-232 capture (not a Standard MIDI File)."""
import argparse
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('capture',type=Path)
a=p.parse_args(); data=a.capture.read_bytes(); i=0; notes=set(); counts={}
while i<len(data):
    start=i; s=data[i]; i+=1
    kind=s&0xf0; channel=(s&15)+1
    if kind not in (0x80,0x90,0xb0,0xc0):
        raise SystemExit(f'Unexpected status {s:02X} at {start}; expected full MIDI status')
    n=1 if kind==0xc0 else 2
    if i+n>len(data):
        print(f'Incomplete last message at {start}');break
    d=data[i:i+n];i+=n
    if any(x>=128 for x in d):raise SystemExit(f'Invalid data at {start}')
    label={0x80:'Note off',0x90:'Note on',0xb0:'Control',0xc0:'Program'}[kind]
    if kind==0x90 and d[1]:notes.add((channel,d[0]))
    elif kind in (0x80,0x90):notes.discard((channel,d[0]))
    elif kind==0xb0 and d[0]==123:notes={k for k in notes if k[0]!=channel}
    counts[label]=counts.get(label,0)+1
    print(f'{start:06X}  {data[start:i].hex(" ").upper():8}  Ch {channel:2}  {label:8}  '+', '.join(map(str,d)))
print(f'{len(data)} bytes; {counts}; remaining active notes: {sorted(notes)}')
