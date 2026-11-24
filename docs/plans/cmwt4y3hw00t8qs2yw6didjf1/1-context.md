# Context — Phase 11 t9: Space Fortress art

Epic plan: `docs/plans/cmug256so0031m52wbxomst72/3-plan.md` §2.9 (art), §2.5.1 / §2.5.2 (scene, frozen part geometry).

## Modules and files involved
| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/enemies/space_fortress/space_fortress.tscn` | The fortress scene. Hull `Sprite2D` = `station_core.png` at scale 1.375; every part `Sprite` = `station_turret.png` / `station_core.png` at fractional scales; no part has a `wreck_texture`; `shutter_open_texture` / `core_open_texture` = `station_turret.png`; `Thrusters` and `CriticalOverlay` are empty `Node2D`s (visible false). | Every placeholder is replaced here. Geometry (shapes, positions, HomingPoints, mount slots) is frozen and must not change. |
| `assault/scenes/enemies/space_fortress/space_fortress.gd` | `_on_phase_entered` swaps generator textures to `shutter_open_texture` (`shields_exposed`), core to `core_open_texture` (`core_exposed`, never over a wreck), shows `Thrusters` (`core_exposed`) and `CriticalOverlay` (`critical`). `phase_snapshot().visuals` reads the texture paths and the two `visible` flags. | The art plugs into these exports. There is **no hangar door art hook**: the hangar is a plain `EnemyModule`; its doors are run by `BossReinforcements` (`door_changed(bay_id, open)` signal, `global/boss/boss_reinforcements.gd:37`). |
| `global/components/enemy_module.gd` | `intact_texture` written to `Sprite` in `_ready()`, `wreck_texture` on `destroy()` (else `WRECK_TINT`). | Wreck states come for free by setting `wreck_texture`. |
| `global/boss/boss_reinforcements.gd` | Door cycle: `door_changed.emit(bay_id, true)` on OPENING, `false` on CLOSED (also on a dead bay / host dying, line 399). | The fortress hangar's open-door texture must follow this signal. |
| `assault/scenes/enemies/defense_turret/mounts/spread_cannon_mount.tscn`, `rapid_pulse_mount.tscn` | t3 mount heads `turret_head_spread_cannon.png`, `turret_head_rapid_pulse.png`. | "May be redrawn in place" (optional). |
| `tests/integration/test_entity_sprite_transparency.gd` | Sweep over every `Texture2D`-valued node property of scenes under `assault/scenes/{enemies,...}`; ≥ 90 % opaque fails. | Must stay green; it reaches the new exports automatically. |
| `tests/integration/test_space_fortress.gd:505-530` | Asserts shutter / core-plating swaps and `core_open_texture != intact_texture`. | Must stay green with the real textures. |

## Existing code to reuse
| Path | What it gives us |
|---|---|
| `tests/integration/test_ph10_sprites.gd` | The template for the new gate: size / transparent corners / 15 % < opaque < 90 % per texture, wiring per part, destruction swaps to wreck, three door / plating states. |
| `assault/scenes/enemies/carrier/carrier_hangar_doors.gd` | The Ph10 door-art pattern (an `open_texture` export). The fortress has no `Doors` node and `BossReinforcements` writes no `open_amount`, so the fortress takes the simpler route: swap the hangar `Sprite` texture on `door_changed`. |
| `scripts/pixellab.sh`, `scripts/strip-sprite-bg.sh` | Saving PNGs safely; removing a painted background. |
| Ph10 t9 DECISIONS entry (DECISIONS.md:4183) | Workbench hand-drawing precedent: generated 32 px parts came out 3/4 and generated hulls had no exact empty sockets; hand-drawn through `pixelart_workbench` is strictly top-down and exactly hurtbox-sized. |

## Conventions that constrain this
- Strict high top-down, never isometric; ≤ 90 % opaque; transparent corners; save only with `scripts/pixellab.sh`; look at each image (6× upscale + in-layout composite).
- Art at scale 1, sized to the frozen hurtboxes of §2.5.2. Never pre-multiply by WORLD_SCALE.
- Never hand-type a `uid://` (ext_resources stay UID-less; `--import` writes `.import`).
- Never call it a "station" in new names.
