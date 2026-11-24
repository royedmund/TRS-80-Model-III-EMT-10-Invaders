# TRS-80 Model III EMT-10 Invaders — Star Siege

An original Space Invaders-style Z80 game for a 48K TRS-80 Model III, with cassette sound effects and simultaneous Yamaha EMT-10 AWM music over the project's external 9600-baud RS-232-to-MIDI bridge.

**v0.4 development prototype (recreated arcade gameplay and attract mode)** — assembled and tested with a restricted opcode harness; not yet tested in trs80gp or on physical hardware. Target: LDOS 5.3.1, 64-column mode. Original music and graphics; no arcade ROM, commercial audio or video included.

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

At the title screen press 2 for 25 Hz LDOS ticks (50 Hz video) or 3 for 30 Hz ticks (60 Hz video), then ENTER to play the eight-second intro on the title screen and automatically start the game, or CLEAR to start with cassette effects only. During the intro SPACE skips to gameplay with music, CLEAR mutes MIDI for the round, and BREAK exits. Left/right arrows move, SPACE fires, BREAK exits. At game over ENTER returns to the menu. SPACE at the main menu starts the silent automatic gameplay demonstration. If no menu selection is made for about six seconds, the demo launches automatically. It runs for 20 seconds of observed game updates (longer if frames are missed), or until the demo loses; ENTER, CLEAR, arrows or SPACE return to the menu after the initial launch key is released. BREAK exits to LDOS. Demo scores never update the session high score. Serial capture should be empty in cassette-only mode. Exit with BREAK before closing the emulator to flush the note-off messages. Use `python capture_midi.py midi-capture.bin` after closing the capture. The file is raw MIDI messages, not a .MID file.

Expected opening bytes: `B0 40 00 B0 42 00 B0 43 00 B0 7B 00 C0 37` (pedals off, all notes off, Upright Bass + Brass). After the intro and explicit note-off cleanup, gameplay selects `C0 47` (Electric Bass + Brass) and plays pairs of notes, e.g. `90 24 50 90 43 44`. At exit explicit note-offs and pedal/all-notes-off follow. On real hardware the bridge converts 9600 8N1 to 31250 MIDI; never wire the RS-232 port straight to MIDI IN.

## Controls and test checklist

| Key | Menu | Gameplay / demo |
|---|---|---|
| 2 / 3 | Select 25 / 30 Hz | — |
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
- Embedded original 16-step bass/brass ostinato, using native EMT-10 Bass Split program 71 on channel 1. Non-blocking UART queue; no MIDI file parsing during gameplay. Missing or busy UART does not trap the main loop. Exit cleanup is bounded; with disconnected hardware delivery cannot be guaranteed.
- INTRO.MID: standalone original eight-second Upright Bass + Brass intro (program 55), format 0. Play it with MIDIPLAY from the related project. The same composition is embedded in the game as two compact event tables for 25/30 Hz. The title screen remains visible for eight seconds, then gameplay starts. The title sequence has no disk reads; a bounded flush and explicit note-offs handle skipping, muting and exit. If the UART stalls during the intro cleanup, MIDI is disabled for that round. Level-completion and game-over music are planned, not implemented.

## Build and test

`python build.py` assembles the restricted Z80 source (standard library only), creates INVADERS.CMD and INVADERS.MAP, and verifies CMD records. `python test_game.py` runs the audio/game-loop mock tests; `python test_graphics.py` verifies the new rendering and collision routines. `python make_intro.py` regenerates the standalone intro. Run `python embed_intro.py` to regenerate both embedded event tables before `python build.py`. See TESTS.txt for results. Mock tests verify manual and idle demo activation, demo scoring isolation and silent operation, both title clock rates and byte streams, skip, mute, BREAK during the title, no UART, movement, firing, scoring and cassette pulses; they do not model real timing, interrupts, display or electrical behaviour.

## Developer documentation

`INVADERS.ASM` includes numbered sections, a hardware and memory map, routine contracts, algorithm explanations and comments for every workspace declaration. See [SOURCE-GUIDE.md](SOURCE-GUIDE.md) for the frame scheduler, modification points, MIDI queue rules and build workflow. This edition adds silent attract mode to the v0.3 gameplay and graphics. See the generated map for current addresses.

## Related project

[TRS-80 Model III Simple MIDI Out](https://github.com/royedmund/TRS-80-Model-III-Simple-Midi-Out) — interface schematic, firmware and MIDI player. The repository is separate and has not been modified.

## Licence

MIT; see LICENSE. Original project materials only.

## Scope of this update

This is a new implementation inspired by Doug Kennedy’s 1980 Space Intruders, using its observed 7×5 formation, 14-pixel horizontal spacing, five-pixel vertical spacing and 6×3-pixel sprites as design references. No original code or bitmap tables are imported. Its private annotated reconstruction is separate. Original screen screenshots could not be fetched, so visual fidelity is based on binary analysis, not a side-by-side emulator comparison.

Limits: character-cell projectile collisions, fixed horizontal bounds, one player, one laser and one bomb, RAM-only high score, original silent attract sequence recreated; no two-player mode. The full-buffer blit and rendering may miss timer ticks on physical hardware; timing and sound need real testing. The eight-second title introduction and background MIDI remain from v0.2.
