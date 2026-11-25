# TRS-80 Model III EMT-10 Invaders — Star Siege

An original Space Invaders-style Z80 game for a 48K TRS-80 Model III, with cassette sound effects and simultaneous Yamaha EMT-10 AWM music over the project's external 9600-baud RS-232-to-MIDI bridge.

**v0.8 cassette laser and explosions prototype (based on v0.7 adaptive soundtrack)** — assembled and tested with a restricted opcode harness; not yet tested in trs80gp or on physical hardware. Target: LDOS 5.3.1, 64-column mode. Original music and graphics; no arcade ROM, commercial audio or video included.

## v0.8 cassette sound effects

The original adaptive EMT-10 soundtrack is unchanged. Cassette output
now uses editable, asymmetric pulse-width tables. The player laser
sweeps from a sharp attack into a lower tail, an alien hit produces
an irregular crackling explosion, and the mystery saucer has its own
longer, deeper explosion. Player damage retains its previous sweep.
Music service runs every four pulses while cassette output is low.
The demo remains silent. No new wiring, sound hardware or firmware.

| Effect | Pulse pairs | Approx. duration (MIDI off, 2.027 MHz) |
|---|---:|---:|
| Laser | 16 | 9.1 ms |
| Alien explosion | 24 | 18.1 ms |
| Player damage | 18 | 8 ms |
| Mystery saucer explosion | 28 | 29.7 ms |

Estimated instruction timing excludes hardware wait states and interrupt
overhead; MIDI service may lengthen effects. Actual pitch, loudness
and sound quality require listening on real hardware. Effects remain
short blocking bursts, so gameplay performance may change slightly.
The v0.8 CMD was assembled after a byte-identical v0.7 rebuild; targeted
opcode tests verified all four output pulse sequences, output ending low,
silent demo/idle paths, and transmission of three pending MIDI bytes during
the saucer explosion. Full v0.8 game/emulator/hardware tests not yet run.
See test_cassette_fx.py for reproducible local tests.

## v0.7 adaptive soundtrack

The original gameplay bass/brass phrase accelerates as the alien formation
descends. The tempo is recalculated at each note pair; the melody is not
restarted, and each new wave returns to the opening speed. Applies in
raw and timed modes. The timer selector, serial protocol, intro music,
graphics and cassette effects are unchanged.

| Formation top row (ay) | 25 Hz step | 30 Hz step |
|---|---:|---:|
| 2 — new wave | 200 ms | 200 ms |
| 3 | 160 ms | 167 ms |
| 4 | 120 ms | 133 ms |
| 5 | 120 ms | 100 ms |
| 6 — last playable row | 80 ms | 67 ms |

The 25 Hz clock has coarser timing, so rows 4/5 share a rate.
At fastest tempo the theoretical stream is 180 musical bytes/sec at
30 Hz plus 30 transport markers in buffered mode (210 bytes/sec);
actual sustained UART service and timing have not been measured.
The v0.7 CMD was assembled after reproducing the v0.6 CMD byte for byte.
The emitted tempo-selection routine passed 512 opcode-level checks
(256 depth values at each clock). Full v0.7 gameplay and hardware
regression tests remain outstanding. See test_audio_clock.py for local
regression cases. The previous v0.6 architecture and test results follow.

## v0.6 audio-clock prototype

This release keeps the v0.5 graphics, rules, original intro and bass/brass
ostinato, and adds the following audio changes:

- Music advances from the elapsed LDOS TIMER$ low byte rather than the
  number of completed gameplay updates. The game still uses observed
  updates; audio catches up independently.
- UART service is non-blocking in gameplay, including between alien rows,
  and uses the original bounded 18-byte host staging buffer.
- 2/3 select raw MIDI at 25/30 Hz; 4/5 select timed Nano transport at 25/30 Hz.
  Default raw 25 Hz. The selected mode appears at the bottom of the menu.
- **Only use 4/5 with the MIDIPLAY v0.8/v0.9 buffered Nano firmware.**
  Same hardware and sketch, no wiring change. The title remains raw in all
  modes. Timed transport starts at gameplay and stops on BREAK/game over.
- The Nano receives FD (25 Hz) or F9 (30 Hz) start, F8 per elapsed tick
  including rests, and FC to cancel. These are link-control bytes, not
  musical events. FC discards delayed music and triggers firmware panic
  (pedal resets and all-notes-off). Raw mode retains explicit note-offs.
- The Arduino FIFO provides nominal 160 ms lookahead for background music.
  Cassette effects remain immediate and unchanged. Buffering is optional
  because delays may be perceptible for gameplay-synchronised sounds.

Download INVADERS.CMD and transfer it to LDOS in binary mode.
Launch using the existing trs80gp command. First test raw mode 2/3; next
test buffered 4/5 after installing the compatible Nano sketch linked in
the [MIDI player repository](https://github.com/royedmund/TRS-80-Model-III-Simple-Midi-Out/tree/main/player/firmware/serial_to_midi_buffered).
Select the actual LDOS tick frequency. The raw capture decoder is intended
for modes 2/3, not the timed protocol.

See [AUDIO-CLOCK.md](AUDIO-CLOCK.md) for the new design and checks.
The CMD was assembled with a baseline-verified assembler and exercised
with a restricted opcode harness, not trs80gp or real hardware.

## Real hardware — RS-232 to MIDI setup

Star Siege uses the same external interface and Arduino firmware as the
[TRS-80 Model III Simple MIDI Out / MIDIPlay project](https://github.com/royedmund/TRS-80-Model-III-Simple-Midi-Out).
No modification to the Model III or separate game-specific firmware is needed.
MIDIPlay is useful for testing the interface independently; the game does
not require MIDIPlay to be loaded or running.

### 1. Build and connect the interface

Required: a Model III with 48 KB RAM and its RS-232 interface, a MAX3232
RS-232-to-logic converter, classic 5 V Arduino Nano (ATmega328P),
5-pin DIN MIDI OUT socket, two 220-ohm resistors, regulated 5 V supply,
and an EMT-10 or compatible MIDI receiver. The game's native program
numbers are specifically intended for the EMT-10.

```text
Model III DB-25 RS-232 TXD (9600 baud, 8N1)
        |
        v
MAX3232 RS-232 level converter
        |
        v
Arduino Nano D10 (software serial RX)
        |
        v
Arduino Nano D1 (hardware TX, 31250 baud)
        |
        v
MIDI OUT DIN --> Yamaha EMT-10 MIDI IN --> amplifier
```

Follow the [complete wiring instructions and parts list](https://github.com/royedmund/TRS-80-Model-III-Simple-Midi-Out#parts-list)
and [interface schematic](https://github.com/royedmund/TRS-80-Model-III-Simple-Midi-Out/blob/main/hardware/minimal-midi-out.svg).
The Nano receives logic-level serial on D10 and transmits MIDI on D1.
**Never connect the Model III RS-232 output directly to MIDI IN or the
Arduino logic input.** Use the MAX3232 and the documented MIDI output
circuit. The direct Nano MIDI output is a prototype; a buffered
specification-compliant MIDI output is preferred for production.
Disconnect MIDI during Nano programming/reset to avoid bootloader traffic.

### 2. Install Arduino firmware

In Arduino IDE select the classic Nano, ATmega328P, the correct serial
port and bootloader option for the board. Choose one of the following:

- [Original transparent serial-to-MIDI sketch](https://github.com/royedmund/TRS-80-Model-III-Simple-Midi-Out/blob/main/firmware/serial_to_midi/serial_to_midi.ino):
  raw modes 2/3 only.
- [Buffered serial-to-MIDI sketch](https://github.com/royedmund/TRS-80-Model-III-Simple-Midi-Out/blob/main/player/firmware/serial_to_midi_buffered/serial_to_midi_buffered.ino):
  raw modes 2/3 and optional timed modes 4/5. Check Arduino IDE
  compilation and SRAM usage before uploading. The timed firmware
  uses a 192-entry FIFO and nominal 160 ms lookahead.

The buffered sketch reserves five link-control bytes and is not a
general-purpose transparent MIDI real-time bridge. **Do not select
game modes 4/5 with the original transparent firmware.** No wiring
change is required between these two sketches.

### 3. Test with MIDIPlay before running the game

Set the EMT-10 to receive channel 1 (or OMNI) and connect its audio
output to an amplifier. Transfer
[MIDIPLAY.CMD](https://github.com/royedmund/TRS-80-Model-III-Simple-Midi-Out/blob/main/player/MIDIPLAY.CMD)
and [ROCKRAW.MID](https://github.com/royedmund/TRS-80-Model-III-Simple-Midi-Out/blob/main/player/ROCKRAW.MID)
to an LDOS disk in binary mode. Follow the
[MIDIPlay player instructions](https://github.com/royedmund/TRS-80-Model-III-Simple-Midi-Out/blob/main/player/README.md).
At the LDOS prompt, assuming the files are on drive 0:

```text
MIDIPLAY ROCKRAW/MID:0
```

Select the correct LDOS tick rate: 2 = raw 25 Hz, 3 = raw 30 Hz,
4 = timed 25 Hz or 5 = timed 30 Hz (buffered sketch only).
First verify raw playback and BREAK, then try timed playback.
The TRS-80 link is 9600 baud, 8N1; the Nano MIDI output is 31250 baud.
Disable flow control and text translation when using other serial tools.

### 4. Start Star Siege on the Model III

Transfer INVADERS.CMD in binary mode to the LDOS disk and type:

```text
INVADERS
```

Choose 2/3 for raw or 4/5 for timed playback, matching the installed
firmware and actual LDOS timer frequency, then press ENTER. The title
music uses raw MIDI in every mode. Gameplay music uses the chosen
transport. CLEAR starts a cassette-only game; SPACE starts the silent
demo. BREAK exits to LDOS and stops music.

Cassette sound effects are generated independently through the Model III
cassette output (port FFH). Connect to a suitable cassette audio
monitor/amplifier using the appropriate cable, separate from the EMT-10
audio path. Do not directly tie the two audio outputs together.

### 5. Troubleshooting

- No MIDI: check MAX3232 direction, shared logic ground, Nano D10/D1
  connections, DIN pin numbering, EMT-10 receive channel and audio output.
  Confirm raw MIDIPlay playback first.
- Incorrect tempo: check LDOS tick selection (25 or 30 Hz).
- Buffered faults: check firmware, onboard LED, serial wiring and SRAM
  usage. Reset the Nano and use raw playback as a fallback.
- Stuck notes: press BREAK; if cleanup cannot reach the module, reset
  the EMT-10 using its normal procedure.
- For the detailed interface design, firmware notes and standalone
  MIDI demonstrations, see the [MIDIPlay repository](https://github.com/royedmund/TRS-80-Model-III-Simple-Midi-Out).

## Quick start in trs80gp

Use the Model III with 48K RAM and LDOS 5.3.1. The current trs80gp includes an LDOS boot disk, so no external disk image is needed. In Windows PowerShell, open the project folder and run:

```powershell
.\trs80gp.exe -m3 -ld INVADERS.CMD
```

If the executable is on PATH, use `trs80gp` instead. The emulator boots LDOS and loads the host CMD at the DOS prompt. Alternatively boot LDOS, then use File → Run to load INVADERS.CMD, or copy the CMD in binary mode onto an LDOS disk and enter `INVADERS`.

For a serial capture, launch from the project folder (use `./trs80gp` on Linux/macOS if needed):

```text
trs80gp -m3 -ld -r ">midi-capture.bin" INVADERS.CMD
```

The quoted `>midi-capture.bin` is the emulator endpoint, not shell redirection. Alternatively select a file output endpoint via Serial → Port A if offered by your version. The emulator's documentation is at https://48k.ca/trs80gp.html. Run from LDOS rather than bare ROM BASIC: the game needs the LDOS TIMER$ at 4288H and exits via 402DH. Keep real-time emulation speed for timing tests.

To use your own LDOS image instead, replace `-ld` with `-d0 "ldos.dsk"`. Do not use a bare BASIC session or rely on the default TRSDOS boot.

At the title screen press 2 for raw 25 Hz LDOS ticks (50 Hz video) or 3 for raw 30 Hz ticks (60 Hz video), or 4/5 for timed 25/30 Hz with the compatible buffered Nano firmware, then ENTER to play the eight-second intro on the title screen and automatically start the game, or CLEAR to start with cassette effects only. During the intro SPACE skips to gameplay with music, CLEAR mutes MIDI for the round, and BREAK exits. Left/right arrows move, SPACE fires, BREAK exits. At game over ENTER returns to the menu. SPACE at the main menu starts the silent automatic gameplay demonstration. If no menu selection is made for about six seconds, the demo launches automatically. It runs for 20 seconds of observed game updates (longer if frames are missed), or until the demo loses; ENTER, CLEAR, arrows or SPACE return to the menu after the initial launch key is released. BREAK exits to LDOS. Demo scores never update the session high score. Serial capture should be empty in cassette-only mode. Exit with BREAK before closing the emulator to flush the note-off messages. Use `python capture_midi.py midi-capture.bin` after closing the capture. For raw modes 2/3 the file contains raw MIDI messages, not a .MID file; timed captures also contain transport tokens and are not supported by the raw decoder.

Expected opening bytes: `B0 40 00 B0 42 00 B0 43 00 B0 7B 00 C0 37` (pedals off, all notes off, Upright Bass + Brass). After the intro and explicit note-off cleanup, gameplay selects `C0 47` (Electric Bass + Brass) and plays pairs of notes, e.g. `90 24 50 90 43 44`. In raw mode, exit sends explicit note-offs and pedal/all-notes-off. In timed gameplay, FC cancels queued music and the Nano performs panic cleanup. On real hardware the bridge converts 9600 8N1 to 31250 MIDI; never wire the RS-232 port straight to MIDI IN.

## Controls and test checklist

| Key | Menu | Gameplay / demo |
|---|---|---|
| 2 / 3 | Select raw 25 / 30 Hz | — |
| 4 / 5 | Select buffered 25 / 30 Hz (compatible Nano only) | — |
| ENTER | Intro and MIDI game | Demo: return to menu |
| CLEAR | Cassette-only game | Intro: mute; demo: return |
| SPACE | Start silent demo | Fire; intro: skip; demo: return |
| LEFT / RIGHT | — | Move; demo: return |
| BREAK | Exit | Exit |

1. Launch and select the actual LDOS tick rate (normally 30 Hz at 60 Hz video).
2. Wait six seconds to see the attract mode; press SPACE to return.
3. Press ENTER to test intro and gameplay MIDI; press BREAK to exit cleanly.
4. Decode the raw serial capture with `python capture_midi.py midi-capture.bin`.
5. In a separate run, test CLEAR and confirm there are no game-generated MIDI bytes.

## Game and audio

- 35 invaders (seven columns, five rows), four two-row bunkers, three animated alien types, mystery saucer, session high score, player laser, enemy bombs, score, lives, successive waves and faster aliens as their numbers fall.
- Direct keyboard matrix, 1 KB RAM screen buffer and block sprites. One update per observed LDOS tick, not cycle-exact timing. No disk reads during play.
- Cassette output FFH produces short procedural firing, hit and damage sounds. The brief effect loops are blocking; actual pitch/volume need testing.
- Embedded original 16-step bass/brass ostinato, using native EMT-10 Bass Split program 71 on channel 1. Non-blocking UART queue, elapsed-clock scheduler, optional timed Nano transport; no MIDI file parsing during gameplay. Missing or busy UART does not trap the main loop. Exit cleanup is bounded; with disconnected hardware delivery cannot be guaranteed.
- INTRO.MID: standalone original eight-second Upright Bass + Brass intro (program 55), format 0. Play it with MIDIPLAY from the related project. The same composition is embedded in the game as two compact event tables for 25/30 Hz. The title screen remains visible for eight seconds, then gameplay starts. The title sequence has no disk reads; a bounded flush and explicit note-offs handle skipping, muting and exit. If the UART stalls during the intro cleanup, MIDI is disabled for that round. Level-completion and game-over music are planned, not implemented.

## Performance improvements in v0.5

- Unrolled screen clear and 32-byte LDI blit; interrupts remain enabled.
- Cached alien row addresses and laser row intersection; direct mask copying on clear rows, original-style mask merging near bunkers.
- Decimal scoring adds the award directly instead of incrementing once per point.
- No changes to game rules, intended timer rate, audio sequence or artwork. Empty sprite mask bytes now use ASCII space (32), not zero.

Estimated nominal Z80 T-states for a complete opening-frame render: 93,084 (v0.4) to 60,466 (v0.5), 35.0% less work. At approximately 2.03 MHz this is about 46 ms to 30 ms of rendering alone, excluding interrupts, memory waits, game logic, effects and serial service. This is not measured FPS. The full game may still miss 25/30 Hz ticks. See [PERFORMANCE.md](PERFORMANCE.md) and BENCHMARK.txt for details.

## Build and test

`python build.py` assembles the restricted Z80 source (standard library only), creates INVADERS.CMD and INVADERS.MAP, and verifies CMD records. `python test_game.py` runs the audio/game-loop mock tests; `python test_graphics.py` verifies the new rendering and collision routines. `python make_intro.py` regenerates the standalone intro. Run `python embed_intro.py` to regenerate both embedded event tables before `python build.py`. Run `python test_audio_clock.py` and `python test_cassette_fx.py` for the added regression cases. See TESTS.txt for historical results and the v0.6–v0.8 sections above for targeted checks. Mock tests verify manual and idle demo activation, demo scoring isolation and silent operation, both title clock rates and byte streams, skip, mute, BREAK during the title, no UART, movement, firing, scoring and cassette pulses; they do not model real timing, interrupts, display or electrical behaviour.

## Developer documentation

`INVADERS.ASM` includes numbered sections, a hardware and memory map, routine contracts, algorithm explanations and comments for every workspace declaration. See [SOURCE-GUIDE.md](SOURCE-GUIDE.md) for the frame scheduler, modification points, MIDI queue rules and build workflow. This edition preserves the v0.4 attract mode and v0.5 rendering and scoring improvements while replacing the gameplay music scheduler. See the generated map for current addresses.

## Related project

[TRS-80 Model III Simple MIDI Out](https://github.com/royedmund/TRS-80-Model-III-Simple-Midi-Out) — interface schematic, firmware and MIDI player. The repository is separate and has not been modified.

## Licence

MIT; see LICENSE. Original project materials only.

## Scope of this update

This is a new implementation inspired by Doug Kennedy’s 1980 Space Intruders, using its observed 7×5 formation, 14-pixel horizontal spacing, five-pixel vertical spacing and 6×3-pixel sprites as design references. No original code or bitmap tables are imported. Its private annotated reconstruction is separate. Original screen screenshots could not be fetched, so visual fidelity is based on binary analysis, not a side-by-side emulator comparison.

Limits: character-cell projectile collisions, fixed horizontal bounds, one player, one laser and one bomb, RAM-only high score, original silent attract sequence recreated; no two-player mode. The optimised full-buffer blit and rendering may still miss timer ticks on physical hardware; timing and sound need real testing. The eight-second title introduction and background MIDI remain from v0.2.
