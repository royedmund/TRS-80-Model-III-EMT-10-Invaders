# Star Siege v0.4 — Z80 developer guide

This edition recreates the classic 35-alien formation using the existing documented Star Siege engine. `INVADERS.ASM` is newly developed code; the original disassembly is a separate private reference.

## Reading the source

| Section | Entry labels | Responsibility |
|---|---|---|
| 01–02 | `start`, `menu`, `begin` | LDOS entry, clock/audio selection, game reset |
| 03 | `title_intro`, `intro_loop`, `intro_cleanup` | Eight-second title music and safe skip/mute/exit |
| 04 | `newwave`, `frame_wait` | Wave initialisation and foreground scheduler |
| 05–07 | `player`, `advance_shot`, `advance_aliens`, `advance_bomb` | Input, movement, projectiles and damage |
| 08–09 | `cell`, `blank`, `present`, `text`, `render`, `score_add` | Back buffer, character graphics, alien collisions and scoring |
| 10 | `effect_play`, `tone` | Cassette sound effects |
| 11 | `midi_pump`, `music_tick` | UART transmission and looping background music |
| 12 | `midi_stop`, `gameover`, `quit` | Audio cleanup, menu return and LDOS exit |
| 13–14 | `title`, `bassline`, `intro25`, `intro30`, `introptr` | Constants, generated music and RAM workspace |

The source header contains the memory map, hardware ports, calling convention and high-level control flow. Individual routines document their inputs, outputs, clobbers and/or state changes. RAM declarations have inline descriptions.

## Attract mode

`menu_timer_reset` snapshots the low byte of TIMER$. `menu_idle` uses unsigned subtraction so a single wrap is harmless; thresholds are 150/180 ticks for 25/30 Hz. `demo_start` selects silent mode, resets the lane index and initializes 500/600 observed updates. `demo_keys` returns synthetic keyboard bits; the normal player routine handles movement and firing. The patrol visits columns 13, 29, 45 and 59. `demo_cancel` gates input until the launch key has been released. `demo_end` clears the demo flag and cassette output and waits for cancellation keys to release before redrawing the menu. `score_add` does not update high score during demo; `effect_play` suppresses cassette pulses. `demo`, `demogate`, `demoindex`, `demoticks`, `menutick` are the relevant workspace symbols. The demo uses the normal enemy movement, scoring and collision rules.

## Frame scheduler

```text
Wait for TIMER$ change, pumping MIDI and polling BREAK
  -> read player keys
  -> advance laser and test shield
  -> move invader formation if due
  -> check invasion depth
  -> advance bomb / test player and shield
  -> advance mystery saucer
  -> render and resolve laser/alien collisions
  -> play pending cassette effect
  -> schedule next MIDI beat, pump UART
  -> check lives and remaining invaders
  -> repeat or start next wave / game over
```

There is no interrupt-driven game loop. The existing LDOS timer interrupt supplies the timebase. Missed ticks are not replayed. The full 1 KB screen is composed in RAM, then copied to video memory with `LDIR`; this is not hardware double buffering.

## Where to make changes

- **Alien speed:** thresholds and delays in `advance_aliens` / `alien_speed`. Wave 2 onwards subtracts one tick. Bounds are fixed to the original formation geometry; update the bounds if changing alien spacing or count.
- **Sprites:** `sprite_ptrs` selects one of 18 six-byte packed masks (3 types × 2 frames × 3 vertical phases); `row_offsets` and `row_phases` encode the five-pixel row pitch. `draw_sprite` merges masks across two rows. Cannon codes are in `render_player`; projectiles in `render` / `render_bomb`. Collision remains character-cell based. `cell` does not bounds-check.
- **Shields:** starting offsets in `newwave`, width in `make_shield`, two collision rows in `shield_hit` and screen offset in `render`. Keep all these consistent.
- **Cassette FX:** cycle counts and half-period counters in `effect_play`, `fx_shot`, `fx_hit`. These are blocking CPU delay loops, so keep them short. Effects have one shared pending slot, not a queue.
- **Background music:** `bassline` and `leadline` contain 16 MIDI pitches each, with index wrapped by `AND 15`. Adjust both table lengths and wrap logic together if extending. `setup_midi` contains the program change, decimal 71 (`C0 47` hex). Bass notes must remain below 55 and upper notes at or above 55 for the intended EMT-10 split. `musicrate` is selected in the menu.
- **Title music:** edit `make_intro.py` and run `python make_intro.py`, then `python embed_intro.py`. The current generator is specific to an eight-second, 96 PPQN, format-0 file and the 25/30 Hz tables. The generated records store one-byte absolute deadlines and payloads up to 18 bytes. Longer intros need changes to timing and generator validation, not just a new MIDI file. Keep the generated-table markers exactly as written.

## UART invariant

`qcount` is the number of pending bytes, `qpos` is the read offset. Producers may fill the 18-byte batch only after the previous batch is drained. `midi_pump` sends at most one byte if EA bit 6 is ready and resets `qpos` when the queue becomes empty. Full status bytes are used, not running status. Preserve this contract if adding new music or sound routines. Cleanup uses bounded polling rather than waiting indefinitely on a missing UART; messages are not guaranteed to reach a disconnected device.

## Build and regression checks

```sh
python build.py
python test_game.py
python test_graphics.py
```

The assembler supports the limited syntax used by this source; it is not a full general-purpose Z80 assembler. It writes `INVADERS.CMD` and `INVADERS.MAP`. Rebuild after editing; compare against the baseline if making documentation-only changes. Mock tests cover manual and automatic attract mode, score isolation, the intro, keyboard/movement, firing/scoring, cassette output, MIDI mode, cleanup and unavailable UART. They do not establish cycle-accurate timing or compatibility with actual LDOS, trs80gp or hardware.

## Current constraints

Single player, one laser and one bomb, fixed 35-alien formation bounds, mystery UFO worth 500, session-only high score, no victory or game-over music yet. Score wraps at 10000, wave display is a single hexadecimal digit, and wave state is an eight-bit counter. The game uses a private stack and assumes RAM 6000H–73C1H is available. It clears the display and restores the original stack at exit, but does not restore the previous UART settings. Hardware audio and timing remain to be tested.
