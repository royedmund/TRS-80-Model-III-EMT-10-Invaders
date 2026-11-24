# TRS-80 Model III EMT-10 Invaders — Star Siege

An original Space Invaders-style Z80 game for a 48K TRS-80 Model III, with cassette sound effects and simultaneous Yamaha EMT-10 AWM music over the project's external 9600-baud RS-232-to-MIDI bridge.

**v0.1 development prototype** — assembled and tested with a restricted opcode harness; not yet tested in trs80gp or on physical hardware. Target: LDOS 5.3.1, 64-column mode. Original music and graphics; no arcade ROM, commercial audio or video included.

## Quick start in trs80gp

Boot a Model III LDOS 5.3.1 disk with 48K RAM. From a DOS prompt, use File → Run to load INVADERS.CMD, or copy the CMD in binary mode to the disk and enter `INVADERS`.

For a serial capture, launch the emulator from the folder containing the files (replace ldos.dsk with your actual boot disk):

```text
trs80gp -m3 -r ">midi-capture.bin" ldos.dsk INVADERS.CMD
```

The quoted `>midi-capture.bin` is the emulator endpoint, not shell redirection. Alternatively select a file output endpoint via Serial → Port A if offered by your version. The emulator's documentation is at https://48k.ca/trs80gp.html. Run from LDOS rather than bare ROM BASIC: the game needs the LDOS TIMER$ at 4288H and exits via 402DH. Keep real-time emulation speed for timing tests.

At the title screen press 2 for 25 Hz LDOS ticks (50 Hz video) or 3 for 30 Hz ticks (60 Hz video), then ENTER for MIDI + cassette effects or CLEAR for cassette effects only. Left/right arrows move, SPACE fires, BREAK exits. At game over ENTER returns to the menu. Serial capture should be empty in cassette-only mode. Exit with BREAK before closing the emulator to flush the note-off messages. Use `python capture_midi.py midi-capture.bin` after closing the capture. The file is raw MIDI messages, not a .MID file.

Expected opening bytes: `B0 40 00 B0 42 00 B0 43 00 B0 7B 00 C0 47` (pedals off, all notes off, Electric Bass + Brass). Then pairs of note-offs and note-ons, e.g. `90 24 50 90 43 44` for bass and brass. At exit explicit note-offs and pedal/all-notes-off follow. On real hardware the bridge converts 9600 8N1 to 31250 MIDI; never wire the RS-232 port straight to MIDI IN.

## Game and audio

- 24 invaders, three shields, player laser, enemy bombs, score, lives, successive waves and faster aliens as their numbers fall.
- Direct keyboard matrix, 1 KB RAM screen buffer and block sprites. One update per observed LDOS tick, not cycle-exact timing. No disk reads during play.
- Cassette output FFH produces short procedural firing, hit and damage sounds. The brief effect loops are blocking; actual pitch/volume need testing.
- Embedded original 16-step bass/brass ostinato, using native EMT-10 Bass Split program 71 on channel 1. Non-blocking UART queue; no MIDI file parsing during gameplay. Missing or busy UART does not trap the main loop. Exit cleanup is bounded; with disconnected hardware delivery cannot be guaranteed.
- INTRO.MID: standalone original eight-second Upright Bass + Brass intro (program 55), format 0. Play it with MIDIPLAY from the related project. Intro integration, level-completion and game-over music are planned, not implemented.

## Build and test

`python build.py` assembles the restricted Z80 source (standard library only), creates INVADERS.CMD and INVADERS.MAP, and verifies CMD records. `python test_game.py` runs the mock opcode tests. `python make_intro.py` regenerates the standalone intro. See TESTS.txt for results. Mock tests verify game movement, firing, scoring, cassette pulses, serial message stream, unready UART and BREAK exit; they do not model real timing, interrupts, display or electrical behaviour.

## Related project

[TRS-80 Model III Simple MIDI Out](https://github.com/royedmund/TRS-80-Model-III-Simple-Midi-Out) — interface schematic, firmware and MIDI player. The repository is separate and has not been modified.

## Licence

MIT; see LICENSE. Original project materials only.
