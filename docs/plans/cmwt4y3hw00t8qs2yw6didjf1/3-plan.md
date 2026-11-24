# Space Fortress art (Phase 11 t9)

## Problem
The fortress fights with the old station's art: one 256 px station picture stretched to 352 px for the hull, the same turret picture shrunk onto all five
batteries, the station hull picture shrunk onto the hangar, both generators and the core. Nothing changes when a part dies except a grey tint, the generator
"shutter" and core "plating" both open onto the same turret picture, the hangar never shows its doors, and the thrusters and critical overlay show nothing. The
player cannot read which part is which, which sector is shielded, or which phase the boss is in. After this task every part has its own top-down art sized to
its hurtbox, a wreck, and the hangar / generators / core visibly open; thrusters and a crack-and-glow overlay mark the late phases.

## Design

### Textures (`assault/assets/sprites/enemies/space_fortress/`, scale 1, sizes = hurtbox bounding boxes of §2.5.2)
| File | Size | Use |
|---|---|---|
| `fortress_hull.png` (the §2.9 name) | 384 × 384 | hull `Sprite2D` (ring hull r ≤ 176 + bastions, empty sockets at every part centre, red faction stripes, cool edge highlight) |
| `battery_spread.png` / `_wreck.png` | 44 × 44 | `BatterySpread` intact / wreck (a turret base ring; the head is the mount's own art on top) |
| `battery_pulse.png` / `_wreck.png` | 44 × 44 | `BatteryPulse` |
| `battery_artillery.png` / `_wreck.png` | 44 × 44 | `BatteryArtillery` |
| `battery_missiles.png` / `_wreck.png` | 44 × 44 | `BatteryMissiles` |
| `battery_sweep.png` / `_wreck.png` | 44 × 44 | `BatterySweep` |
| `hangar_closed.png` / `hangar_open.png` / `hangar_wreck.png` | 36 × 56 | `Hangar` intact / new `SpaceFortress.hangar_open_texture` / wreck |
| `generator_closed.png` / `generator_open.png` / `generator_wreck.png` | 52 × 52 | both generators' intact / `shutter_open_texture` / wreck (shared by north and south; south uses the same art, `flip_v` so its emitter faces outward) |
| `core_plated.png` / `core_open.png` / `core_wreck.png` | 88 × 88 | `Core` intact / `core_open_texture` / wreck |
| `thruster.png` | 16 × 24 | four `Sprite2D` children of `Thrusters` on the rim between parts (bearings 67.5 / 112.5 / 247.5 / 292.5 deg, r ≈ 184, rotated so the plume points outward) |
| `critical_overlay.png` | 384 × 384 | one `Sprite2D` child of `CriticalOverlay` (cracks and orange glow over the ring; ≤ 90 % opaque, mostly transparent) |

Five distinct battery bases (each reads its weapon: spread = fan muzzle ring, pulse = twin capacitor pods, artillery = heavy armoured collar, missiles = tube grid,
sweep = lens/emitter collar) so a player tells which corner fires what even while the mount head turns. Wrecks are charred greys with ember pixels (Ph10 palette).
Palette shared with the Ph10 heavies: ink / navy / gunmetal hull, red faction stripes, cool-blue edge highlights.

**How it is made** (the `pixel-art-generation` skill is invoked before any PixelLab call; it was, at the start of this task): the hull and overlay are tried first as PixelLab generations (`create_map_object`, `view: "high top-down"`; 2–3 candidates); a 384 px
canvas is over the 40 000 px transparency cap, so a generated hull is cleaned with `strip-sprite-bg.sh`. The hull must have **empty sockets at the exact part
centres** — if no candidate does (the Ph10 finding), the hull is hand-drawn with `pixelart_workbench` (the plan allows the Ph10 workbench route). Parts at
44–88 px are hand-drawn through the workbench (Ph10: generated parts at this size came out 3/4 and cannot be made exactly hurtbox-sized), optionally
starting from a generated candidate re-drawn to size. A generated candidate that is right in angle and palette but has a socket in the wrong place may be corrected by a scripted pixel edit (a headless Godot `Image` script in `/tmp`, the same kind of post-process as `strip-sprite-bg.sh`: continue the ring bands across a misplaced socket, paint an empty well at an exact part centre); every such edit is named in DECISIONS. Every image is opened at 4–6× and in a composite at in-game layout (intact, all-wrecked, phase states).

Mount heads (`turret_head_spread_cannon.png`, `turret_head_rapid_pulse.png`): looked at on the new battery bases; redrawn in place only if they clash.

### Wiring (`space_fortress.tscn`, `space_fortress.gd`)
- Every `Sprite` scale → 1, every `intact_texture` / `wreck_texture` set; hull `Sprite2D` scale 1 (its `ShaderMaterial` hit flash stays).
- `shutter_open_texture` = `generator_open.png`, `core_open_texture` = `core_open.png`.
- **New export `hangar_open_texture: Texture2D`** on `SpaceFortress`: `_ready()` connects `_reinforcements.door_changed`; for `bay_id == &"hangar"` the hangar
  `Sprite` shows `hangar_open_texture` while open and `intact_texture` when closed, **never over a wreck** (`is_destroyed()` → no write), a null export does
  nothing. Rejected: a `CarrierHangarDoors` node (its `open_amount` is written only by `CarrierHangars`; `BossReinforcements` knows no door node, and adding one
  to a generic `global/boss` class for one texture is churn).
- `Thrusters`: four `Sprite2D` children (`Thruster0..3`); `CriticalOverlay`: one `Sprite2D` child (`Overlay`). Visibility logic unchanged (the parents' `visible`).
- No `CollisionShape2D`, shape, part position, `HomingPoint`, `MountSlots` or hull change (`git diff` checked).
- No station PNG referenced by `space_fortress.tscn` (the station's own scenes keep theirs until t11 deletes them).

## Build sequence
1. Write `tests/integration/test_fortress_sprites.gd` (fails: files missing, placeholders wired).
2. Draw / generate the hull; check at 2× and in composite; save.
3. Draw the five batteries + wrecks; composite on the hull with mount heads.
4. Hangar ×3, generator ×3, core ×3; composite in each phase state.
5. Thruster, critical overlay; composite of `critical` with thrusters.
6. Import, wire the scene, add `hangar_open_texture` + door handler.
7. GUT gate, transparency sweep, `test_space_fortress.gd`, full `bash /agent/verify.sh`; gate-time before / after.
8. Docs: invoke `updating-project-docs` (a new export and door-art hook): `ENEMY.md` art section, `assault.md` / `global.md` lines where the fortress art is described, a CLAUDE.md line for the fortress art and its gate (the Ph10 t9 precedent), the "placeholder until t9" comments in `space_fortress.gd` (lines 39-42 and the header), DECISIONS `### Phase 11, built in t9` (the hangar art hook; how the art was made, scripted edits included).

## Test plan — `tests/integration/test_fortress_sprites.gd` (intent)
1. `test_every_fortress_texture_exists_has_its_size_and_is_card_free` (parameterised over the 21 solid files; the overlay is row 1b): loads; exact size of the table; four corners alpha 0;
   15 % < fully-opaque fraction < 90 %; centre pixel drawn. The critical overlay is **not** in this row (it is meant to be mostly empty).
   1b. `test_the_critical_overlay_is_a_light_overlay`: 384 × 384, corners alpha 0, 1 % < visible (alpha > 0) fraction < 35 %, fully-opaque fraction < 20 %, so it never hides the hull.
2. `test_the_hull_is_wired_and_covers_its_body`: hull texture path, scale ONE, rotation 0, art ≥ 2 × r 176 both ways.
3. `test_every_part_is_wired` (parameterised over 9 parts): intact path, wreck path, intact ≠ wreck, `Sprite.texture == intact_texture`, scale ONE,
   **texture size == hurtbox bounding box** (circle 2r × 2r, rect size). The south generator `Sprite.flip_v` true, every other part false (pinned, the Ph10 mirrored-part rule).
4. `test_a_destroyed_part_swaps_to_its_wreck`: every part `destroy()`ed shows its wreck, `visual_state() == WRECK`.
5. `test_the_five_batteries_are_distinct`: five distinct intact and five distinct wreck textures.
6. `test_the_hangar_has_three_door_states`: closed ≠ open ≠ wreck; emitting `door_changed(&"hangar", true)` shows the open art, `false` the closed art; another
   bay id changes nothing; **boundary:** after `destroy()` a `door_changed(true)` / `(false)` leaves the wreck texture.
   6b. `test_the_hangar_shows_its_open_art_through_the_real_door_cycle`: a fortress in the tree, `_reinforcements.surge(&"hangar", 1)` then `tick(0.0, true)` (the real door cycle, no hand-emitted signal): the hangar Sprite shows the open art while `door_open(&"hangar")`, the closed art after the cycle ends. Catches a renamed bay id.
7. `test_the_generators_and_core_have_three_states`: shutter closed / open / wreck distinct, core plated / open / wreck distinct; `_open_shutters()` /
   `_open_core_plating()` show them; **boundary:** a wrecked core keeps its wreck when the plating opens.
8. `test_thrusters_and_overlay_are_wired`: four `Sprite2D`s under `Thrusters` with `thruster.png`, each outside the hull circle's r 176 and pointing outward
   (sprite +y away from the centre); `Overlay` = `critical_overlay.png` at scale 1; both parents start hidden.
9. `test_no_station_art_in_the_fortress_scene`: walks `space_fortress.tscn`'s own `PackedScene.get_state()` (as the transparency sweep does, never a live instance: a live one holds the rocket pools' `enemy_rocket.png` and `StateLight`'s code-built glow): every `Texture2D`-valued node property resolves under `assault/assets/sprites/enemies/space_fortress/` and none names `station_`; and the hull `Sprite2D` and every part `Sprite` are among them (so an empty walk cannot pass).
Plus the existing transparency sweep and `test_space_fortress.gd` stay green unchanged.

## Risks
- Generated hull lacks exact sockets → workbench route (cost: time, no generations).
- 384 px generated canvas paints a background → `strip-sprite-bg.sh`.
- Gate time: one new file of texture checks (~0.5 s expected); measured before / after with `scripts/gate-time.sh`.

## Out of scope
Any geometry, behaviour or phase-rule change; the station's own art (t11 deletes it); animated thruster flames.
