# Star Siege v0.5 — performance engineering

Baseline: v0.4 published game. Optimisation is restricted to the renderer and decimal scoring; controls, game rules, timer selection, audio sequencing and sprite geometry are unchanged. New executable is 5,359 bytes, versus 5,142 bytes (+217). Loaded range 6000H–7496H.

## Reproduce

Extract the original v0.4 ZIP into a separate directory and this release into another. From v0.5:

```sh
python build.py
python test_game.py
python test_graphics.py
python benchmark_render.py ../invaders-v04
```

Point the last argument at the extracted directory containing the original INVADERS.CMD and INVADERS.MAP. The benchmark executes both CMD files with the same extended mock CPU and sums standard nominal Z80 instruction T-states (including repeated LDIR iterations). It compares full 1 KB VRAM and relevant collision state. It does not model actual memory contention, interrupt overhead, UART timings, or real elapsed time. The mock gameplay clock is instruction-count based, so observed game score/timing can vary between builds. This is not an emulator FPS benchmark.

## Results

See BENCHMARK.txt for seven representative scenarios and 120 additional state comparisons. All 127 compare identical screen and collision state. Opening frame: 35.0% reduction in estimated renderer T-states (1.54x renderer throughput). On a nominal 2.03 MHz Model III, the renderer alone requires about 30 ms instead of 46 ms. The 30 Hz budget is about 33 ms for the entire frame; the 25 Hz budget is 40 ms. Full frame performance is not guaranteed, especially near bunkers, while playing cassette effects or when servicing interrupts. Do not increase emulator CPU speed for the first real-time test.

## Next steps

If actual testing still shows missed ticks, consider retaining a cached static formation layer, dirty-region VRAM updates and a timer-driven cassette effect sequencer. These require additional collision and timing regression tests. The v0.5 changes deliberately avoid interrupt masking, using SP as a graphics pointer, or modifying DOS memory.

## Emulator

Use the same trs80gp launch commands in README.md. Test at normal CPU speed with the correct clock selected. Compare the same gameplay sequence in v0.4 and v0.5 and check raw MIDI output and audible effects. No physical or trs80gp run was performed for this release.
