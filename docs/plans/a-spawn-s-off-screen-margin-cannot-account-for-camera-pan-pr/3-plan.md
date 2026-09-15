# Spawn positions must account for camera pan

## Problem

A design-space spawn offset ("appear just off the bottom edge") is meant to be relative to what
the player can actually see. Today it is computed relative to the level's fixed origin instead,
because every spawn site adds the offset to `cam.global_position`, which `ArenaCamera` pins at
`(640, 360)` forever — all panning happens through `Camera2D.offset` (`arena_camera.gd:5-12,
89-90`), which is never added in. `offset` can reach ±380 px vertically and ±100 px horizontally
(`V_LIMIT`/`H_LIMIT`, `:38-39`). A player parked at the bottom of the vertical pan range can watch
a "bottom edge" spawn appear on screen, because the real bottom edge moved with them and the spawn
math didn't.

This was found and deliberately deferred while building station reinforcements (EPIC sub-item 4b)
rather than special-cased for one node — see `1-context.md`. It affects the whole spawn convention:
`WaveManager` (every scripted wave in the game), `StationReinforcements` (the station mini-boss's
add spawns), and `Level1Director`'s bonus-drone spawner.

## Design

Add `cam.offset` to the reference point at all three spawn sites, so a spawn resolves against
*where the camera is actually looking*, not its resting position. `Camera2D.offset` is a stock
engine property — every site already holds a plain `Camera2D` from `get_viewport().get_camera_2d()`
and can read `.offset` with no cast.

- `wave_manager.gd:172` — `cam.global_position + cam.offset + spawn.get("offset", Vector2.ZERO) * ArenaCamera.WORLD_SCALE`
- `station_reinforcements.gd`'s `_spawn_origin()` (`:282-286`) — return `cam.global_position +
  cam.offset` when a camera exists (the no-camera fallback `(SCREEN_W, SCREEN_H) * 0.5` is
  unchanged: it already models a camera at rest, i.e. `offset == Vector2.ZERO`, so nothing to add).
  `_spawn_entry()` (`:238`) needs no change — it already calls `_spawn_origin()`.
- `level_1_director.gd:125` — `cam.global_position + cam.offset + camera_offset`. (This site's
  `camera_offset` param is raw world px, not design units — untouched, it's a different
  pre-existing property of this one call site, not part of this fix.)

**Alternative considered: a new `ArenaCamera.get_pan_offset()` that excludes `CameraShake`.**
Rejected — `offset` already carries shake noise into player-follow, so a spawn seeing a few px of
that at the instant it lands is invisible against margins measured in tens/hundreds of px, and it
would require casting `Camera2D` to `ArenaCamera` at every call site (and add a fourth in tests
using a bare `Camera2D`, which is otherwise sufficient to exercise this). `score_popup.gd:34`
already uses `cam.global_position + cam.offset` for exactly this purpose — this fix makes spawn
math consistent with that existing precedent, not a new pattern.

**Off-screen despawn/exit checks, and `gunship`/`light_assault_ship` `_hold_y` waypoints, are out
of scope** — see `1-context.md` for why each is a different mechanism than spawn placement.

### Consequence for the station-reinforcements margin budget

`ENEMY.md:277-278` and `docs/plans/station-reinforcements/3-plan.md:315-320` both document
`V_LIMIT` as deliberately excluded from the vertical spawn-margin budget, because until now every
spawn resolved against the camera's fixed centre rather than the panned view. After this fix that
is no longer true: reinforcement offsets resolve against the actual visible centre, so the
existing margin (`360 + 37 = 397` against a design `±290` = `580` world px) is valid on its own
terms without needing `V_LIMIT` headroom, because panning no longer moves the *relative* spawn
position at all — it moves with the view. Update both docs to record that this is resolved, not to
change the shipped margin numbers (they still hold with room to spare; changing them is not part of
this fix).

## Build sequence

1. Write failing tests (below) proving each of the three sites ignores `cam.offset` today.
2. Fix `wave_manager.gd:172`.
3. Fix `station_reinforcements.gd`'s `_spawn_origin()`.
4. Fix `level_1_director.gd:125`.
5. Run the new tests — they should now pass — then the full suite.
6. Update `ENEMY.md`, `docs/plans/station-reinforcements/3-plan.md`'s risk note, and
   `arena_camera.gd:7-11`'s header comment per the "Consequence" section above and the "Header
   comment" note below (small doc edits, not a design change — covered here rather than as a
   separate docs pass since all three are a paragraph or two tied directly to this fix).

### Header comment that becomes false

`arena_camera.gd:7-11` currently asserts, as a design guarantee: "This keeps cam.global_position
stable so: ... WaveManager spawn positions (cam.global_position + entry_offset) always resolve
from the fixed screen centre — no drift on delayed spawns." After this fix, a delayed spawn
(`WaveManager._spawn_with_delay()` awaits before calling `_spawn_ship()`) resolves against
`cam.global_position + cam.offset` at the moment the delay elapses, not against the fixed centre —
a real, desirable behaviour change (a delayed spawn now tracks wherever the player has panned to
by the time it fires, instead of the camera's rest position). Update the comment to describe the
new guarantee: `global_position` staying fixed keeps `EnemyPathMover`'s cam-scroll delta at exactly
0 (unchanged — that guarantee is untouched by this fix, since it depends only on
`global_position` never moving, not on how spawn code reads `offset`), and spawn positions now
resolve against the camera's actual current view (`global_position + offset`), intentionally
including whatever pan has happened by the time a delayed spawn fires.

## Test plan

New test file `tests/integration/test_spawn_camera_pan.gd` (`extends GutTest`) — `integration/`,
not `unit/`, because case 2 instantiates the real `space_station.tscn` scene and case 3 loads the
real `bonus_drone.tscn`, which `tests/README.md`'s `unit/` = "no scene loading" rule excludes —
covering all three sites
with a bare `Camera2D` (no `ArenaCamera` script needed — the fix only reads the stock `.offset`
property) added to the tree and returned by `get_viewport().get_camera_2d()`:

1. **`WaveManager._spawn_ship()` includes camera offset.** Build a `WaveManager` with a container,
   a camera at `global_position (640, 360)` with `offset = Vector2(0, 380)` (max vertical pan,
   `ArenaCamera.V_LIMIT`), register a wave with one spawn at design offset `(0, 150)`, trigger it,
   and assert the spawned entity's `global_position` is `(640, 360) + Vector2(0, 380) +
   Vector2(0, 150) * ArenaCamera.WORLD_SCALE` — i.e. `(640, 1040)`. **Boundary:** re-run with
   `offset = Vector2.ZERO` and assert the position matches today's (unchanged) formula exactly, so
   the fix is additive, not a rewrite of the at-rest case.
2. **`StationReinforcements._spawn_origin()` includes camera offset.** Same camera setup; spawn a
   squad and assert an entry's `global_position` includes the offset the same way. **Boundary:**
   with no camera in the tree at all, assert `_spawn_origin()` still returns the `(640, 360)`
   fallback unchanged (proves the no-camera path, exercised by every existing reinforcements test,
   is untouched).
3. **`Level1Director._spawn_bonus_drone()` includes camera offset.** `Level1Director._ready()`
   does a lot unrelated to this fix (builds sections, wires `director.start()`, deferred-adds a
   HUD scene to `get_tree().root`) and crashes outright with unset `@export`s — reproducing that
   whole path is not needed just to exercise one method's arithmetic, and reproducing it anyway
   is what create the orphan-node mess a naive attempt hits. Instead:
   - `add_child_autofree()` a **plain, scriptless `Node`** (this fires `NOTIFICATION_READY` on a
     node with no override, i.e. a no-op).
   - **Then** call `.set_script(preload(".../level_1_director.gd"))` on it. Verified empirically
     for this plan (a throwaway headless `SceneTree` probe): attaching a script to a node *after*
     it has already entered the tree does **not** invoke that script's `_ready()` — the engine's
     ready notification already fired before the new script existed — while `get_viewport()`
     already works, because the node is genuinely in the tree. This reaches the exact code path
     under test (`get_viewport().get_camera_2d()` inside `_spawn_bonus_drone()`) with zero of
     `_ready()`'s side effects: no HUD instance, no section building, no orphans.
   - Set `wave_manager` via `.set("wave_manager", wm)` (a real `WaveManager` with `enemy_container`
     pointed at an `add_child_autofree()`d `Node2D`), add the same camera as the other two cases,
     then call `_spawn_bonus_drone_left_to_right()` and assert the drone's `global_position` is
     `(640, 360) + Vector2(0, 380) + Vector2(-680, 60)` (raw px, not design-scaled — matching the
     existing convention at this one site).

## Risks

- **Test camera bleed.** GUT's `get_viewport()` is shared across the test's own tree; a leftover
  `Camera2D` from a prior case could be picked up by `get_camera_2d()` in a later one. Mitigate
  with `add_child_autofree()` for every camera and instantiate a fresh `WaveManager` /
  `StationReinforcements` / director script per test case (`before_each`), matching the pattern
  `test_station_reinforcements.gd` already uses.
- **`Level1Director._ready()` is heavy and crashes on a bare instance.** Confirmed directly:
  `add_child_autofree()`ing a fresh `Level1Director.new()` with no exports set throws in
  `_ready()` (`director.add_section(...)` on a null `director` export) and, even if `director`/
  `wave_manager` are pre-wired to avoid that crash, `_ready()` still deferred-adds a HUD scene
  instance to `get_tree().root` and builds every Level 1 section — dozens of nodes the test would
  then have to hunt down and free. The set-script-after-entering-tree technique in test case 3
  above sidesteps this category of risk entirely rather than mitigating it after the fact — no
  `_ready()` call means no HUD, no sections, no orphans, by construction.

## Out of scope

- Off-screen despawn/exit checks and `_hold_y` waypoint calculations (see `1-context.md`).
- Changing the station-reinforcements shipped margin values — only the doc explanation of why
  `V_LIMIT` was excluded is updated, per "Consequence" above.
- Any change to `ArenaCamera` itself (no new public API, no behaviour change to panning or shake).
