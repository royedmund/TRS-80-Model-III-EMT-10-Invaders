# Star Siege v0.6 — gameplay audio clock

## Rationale

v0.5 counted completed game updates to time its 16-step ostinato. Missing
a video tick could slow the soundtrack. v0.6 uses a separate logical
music clock sampled from LDOS TIMER$ at 4288H. The scheduler consumes
one elapsed tick per service call, modulo 256, and never overwrites a
pending UART batch. It keeps its phase across wave changes.

Service runs in the wait loop, between game routines and between
formation rows, where register values are not live. The UART pump
attempts one byte per call. No custom ISR, DI/EI, disk access, or blocking
UART waits during gameplay. The 18-byte staging queue is unchanged.
Cassette effects are still short blocking tone loops. The original
intro already used elapsed ticks, and remains raw for immediate audio
and skip response.

## Transport

| Menu | LDOS tick | Wire mode |
|---|---|---|
| 2 | 25 Hz | raw MIDI (default) |
| 3 | 30 Hz | raw MIDI |
| 4 | 25 Hz | timed Nano |
| 5 | 30 Hz | timed Nano |

Timed gameplay uses the existing MIDIPlay buffered firmware (v0.8/0.9);
no wiring changes or separate sketch. FD/F9 starts the session; F8
advances one tick, with subsequent channel messages due on that tick;
FC discards buffered notes and requests firmware panic. The title
uses ordinary channel messages in every mode. The game still uses
program 55 for title and 71 for gameplay. A normal beat contains 12 MIDI
bytes (two note-offs, two note-ons), or 13 wire bytes with a tick marker.

At five beats/sec, the steady-state background stream is about 60
musical bytes/sec, plus 25 or 30 tick markers in timed mode. The
9600-baud 8N1 link can carry at most 960 bytes/sec, but foreground CPU
service and physical UART readiness can reduce effective throughput.
The Nano's 192 entries / 960 bytes of SRAM hold timestamped musical
bytes, not transport tokens. The nominal 160 ms lead absorbs moderate
host jitter; it does not eliminate all jitter or restore lost bytes.

On BREAK/game over, timed mode drops the host staging batch and sends
FC through a bounded polling routine, rather than allowing stale notes
to drain. The firmware handles pedal reset and CC123 on all channels.
Raw mode retains explicit old-pitch note-offs and controller cleanup.
If the connection is lost, cancellation delivery is not guaranteed; the
timed firmware has a two-second watchdog. No return telemetry.

## Verified in this build

A JavaScript implementation of the repository's restricted assembler
reproduced the committed v0.5 CMD byte for byte and built the v0.6 CMD:
5,671 bytes, load 6000H–75CAH. The v0.6 code and map were committed.
A separate restricted Z80 opcode harness exercised the actual CMD:

- PASS raw 25/30 Hz: clock wrap and catch-up, four beats, no tokens.
- PASS timed 25/30 Hz: clock wrap and catch-up, four beats, 16/19 F8 markers.
- PASS UART stall preserves batch; cancellation sends only FC.
- PASS unavailable UART cancellation is bounded.
- PASS disabled audio service is silent.
- PASS full CMD mock raw 25/30 Hz (535/499 UART bytes).
- PASS full CMD mock timed 25/30 Hz (621/584 UART bytes).
- PASS timed selection with intro skip (398 bytes), mute (77),
  and BREAK during intro (77). All full runs restored the caller stack.

The harness uses deterministic instruction-count ticks and immediate
UART-ready status unless explicitly stalled. It does not measure
throughput, actual tempo, audio quality, electrical behaviour or frame
rate. The mock gameplay tests above check reaching gameplay and exiting;
they are not a comprehensive graphics/collision regression. The
repository's Python build and full prior regression suites were not
executed in this environment; the new Python test_audio_clock.py
reproduces the targeted cases using the repository's existing harness.

## Local build and test

```
python build.py
python test_game.py
python test_graphics.py
python test_audio_clock.py
```

Use the branch CMD on the Model III. Raw first; then test the same
piece using buffered mode with the correct Nano firmware. Listen for
steady tempo during busy graphics and verify BREAK stops delayed music.
Repeat across wave transitions, game over, and no-UART conditions.

## Remaining limits

The low-byte clock must be consumed within 256 ticks to avoid ambiguity.
A long stall or CPU starvation beyond the lookahead cannot be repaired;
late events may bunch. Buffered gameplay has deliberate latency and
depends on the EMT-10 accepting CC123 for panic. The same firmware
is not yet hardware-verified in timed mode. No adaptive soundtrack,
wave fanfare or game-over score has been added. No emulator or real
hardware test of v0.6 has been performed. Keep raw mode as fallback.
