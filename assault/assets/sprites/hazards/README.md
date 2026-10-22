# Hazard field art (Phase 6, t5)

Strict top-down, transparent. The full field radius is drawn in code (`_draw()`), so these stay small.

| File | Size | Frames | Reads as |
|---|---|---|---|
| `gravity_well.png` (+ `gravity_well_frames.tres`, `swirl`) | 192, 8 | 8 | indigo/orange accretion arms around a dark core ringed in bright gold |
| `energy_anomaly.png` (+ `energy_anomaly_frames.tres`, `dim` 0-3 / `lit` 4-7) | 160 | 8 | violet/magenta spiked starburst of rings with a pink-white nucleus; never cyan |
| `gravity_field.png` | 128 | 1 | translucent lime-green ripple ring (scale / fade in code) |
| `reactor_field.png` (+ `reactor_field_frames.tres`, `burn`) | 96 | 4 | orange-red flame disc with a yellow-white hot centre |

`*_base.png` are the raw PixelLab map-object outputs (`create_map_object`, `view: "high top-down"`). The strips
were built from them by rotating / brightening (PixelLab cannot animate map objects); `gravity_field.png` is the
base hue-shifted from teal to lime (cyan means shield) at 80 % alpha. Gated by `tests/integration/test_hazard_art.gd`.
