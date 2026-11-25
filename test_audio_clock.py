#!/usr/bin/env python3
"""v0.6 regression cases for assembled audio routines and CMD.
Uses test_game.CPU; not a cycle-accurate emulator or Arduino simulation.
Run after python build.py.
"""
from test_game import CPU, SYMS

def call(c, label):
    c.push(0x402d)
    c.pc = SYMS[label]
    c.run(maxsteps=c.steps + 2000000)
    assert c.sp == 0xf000

def put(c, label, value):
    c.mem[SYMS[label]] = value

def get(c, label):
    return c.mem[SYMS[label]]

def out(c):
    return bytes(v for _, v in c.uart)

for buffered in (0, 1):
    for rate in (5, 6):
        c = CPU(break_at=None)
        for label, value in [('midi',1), ('streaming',buffered),
                             ('musicrate',rate), ('musicwait',1),
                             ('musicclock',253)]:
            put(c,label,value)
        target = (253+rate*3+1)&255
        # Freeze mock time across calls to test a known elapsed interval.
        for _ in range(300):
            c.steps = 0
            c.mem[0x4288] = target
            call(c,'music_service')
        stream = out(c)
        assert get(c,'musicclock') == target
        assert get(c,'musicindex') == 4 and get(c,'qcount') == 0
        assert stream.count(248) == (rate*3+1 if buffered else 0)
        payload = stream.replace(bytes([248]),b'')
        assert len(payload) == 48
        assert payload[:12] == bytes.fromhex('800000 800000 902450 904344')
        print('PASS wrap/catch-up:', 'timed' if buffered else 'raw', rate*5, 'Hz')

c=CPU(break_at=None)
for label,value in [('midi',1),('streaming',1),('musicrate',6),('musicwait',1)]:
    put(c,label,value)
c.mem[0x4288]=1
call(c,'music_service')
c.uart_ok=False
for _ in range(10): call(c,'music_service')
assert get(c,'qcount')==13 and get(c,'qpos')==0
c.uart_ok=True
call(c,'midi_stop')
assert out(c)==bytes([252])
print('PASS stall preserves batch; cancel discards it')

c=CPU(break_at=None,uart_ok=False)
put(c,'midi',1);put(c,'streaming',1)
call(c,'midi_stop')
assert not out(c) and get(c,'streaming')==0
print('PASS unavailable UART bounded cancellation')

c=CPU(break_at=None)
c.mem[0x4288]=10
call(c,'music_service')
assert not out(c)
print('PASS silent service')

for clock,action in [('2','full'),('3','full'),('4','full'),('5','full'),
                     ('5','skip'),('5','mute'),('5','break')]:
    c=CPU(clock=clock,action=action).run()
    raw=out(c)
    assert c.sp==0xf000
    assert raw.startswith(bytes.fromhex('B04000 B04200 B04300 B07B00 C037'))
    if action=='break':
        assert not c.seen_game and 252 not in raw
    else:
        assert c.seen_game
        game=raw[c.game_uart:]
        if action=='mute':
            assert not game
        elif clock in ('4','5'):
            assert game[0]==(253 if clock=='4' else 249)
            assert game[-1]==252 and 248 in game
        else:
            assert not any(v in game for v in (248,249,253,252))
            assert game.startswith(bytes.fromhex('B04000 B04200 B04300 B07B00 C047'))
    print('PASS CMD mock:',clock,action,len(raw),'bytes')
