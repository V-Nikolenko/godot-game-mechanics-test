# Wreck and derelict-structure art (Phase 6, t9)

Strict top-down, transparent, dead (no lit engines, windows or weapon lights). Scenes using them: t10 / t12.

| File | Size | Reads as | PixelLab object |
|---|---|---|---|
| `wreck_small.png` | 40 | charred drone-sized hull chunk, one wing stub, dull crimson flecks | `b86c6393` (yellow / white glints removed) |
| `wreck_medium.png` | 72 | fighter-class hull, one wing torn off, dark canopy, scorch | `59a5685c` (reds dulled) |
| `wreck_large.png` | 110 | gunship hull snapped in two, tail half pushed 3 px apart, scorched break | `7091a333` (carved and scorched in Godot) |
| `wreck_explosive_glow.png` (+ `wreck_explosive_glow_frames.tres`, `fuse`) | 2 x 48 | overlay: exposed ordnance glow, frame 0 dim ember, frame 1 hot orange | `906d2023` (dim frame derived by darkening) |
| `structure_satellite.png` | 96 | satellite, right panel shattered, antenna boom snapped | `463b743b` (value lifted 1.5x) |
| `structure_cargo_platform.png` | 128 | container deck, grey-blue with faded crimson containers | `d94532d9` (as generated) |
| `structure_station_module.png` | 128 | cross-shaped docking module, two arms ripped off | `6668849c` (orange tears recoloured charcoal, arm tips carved) |

All from `create_map_object`, `view: "high top-down"`. Orange is reserved for the armed / fuse state, so it
appears only in the glow overlay. Drifting debris reuses `environment/debris_1..6.png`.
