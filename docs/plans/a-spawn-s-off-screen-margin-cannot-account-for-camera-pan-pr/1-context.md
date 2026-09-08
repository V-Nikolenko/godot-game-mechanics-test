# Context

## The bug

`ArenaCamera` (`assault/scenes/systems/arena_camera.gd:5-12`) deliberately pins
`global_position` at the level origin `(640, 360)` forever, and does all player-follow panning
through the inherited `Camera2D.offset` property (`:89-90`, `_physics_process`). `offset` can
reach `±H_LIMIT` (100) horizontally and `±V_LIMIT` (380) vertically (`:38-39`).

Every place that turns a design-space spawn offset into a world position adds it to
`cam.global_position` only, ignoring `cam.offset` entirely. Because `global_position` never moves,
this is equivalent to always spawning relative to the level origin, never to what is actually
on screen. A design offset that is meant to land "just off the bottom edge of the screen" is
computed against the *rest* position of the screen — if the player has panned the camera down
(possible up to 380 px), the real bottom edge has moved 380 px further down and the spawn can
land inside the visible area instead of outside it.

This was found and consciously deferred while building the station reinforcements feature (EPIC
sub-item 4b): `docs/plans/station-reinforcements/3-plan.md:315-320` and
`assault/scenes/enemies/space_station/ENEMY.md:277-278` both document "V_LIMIT deliberately
excluded from the vertical margin budget" as a known, pre-existing, project-wide gap — not
something to special-case for one node.

## The three spawn sites

All three resolve a spawn position as `<camera reference point> + <design offset> * WORLD_SCALE`
(one exception noted below). All three need the same fix: add `cam.offset` to the reference point.

| File:line | Function | Current formula |
|---|---|---|
| `assault/scenes/systems/wave_manager/wave_manager.gd:172` | `_spawn_ship()` | `cam.global_position + spawn.offset * ArenaCamera.WORLD_SCALE` |
| `assault/scenes/enemies/space_station/station_reinforcements.gd:238` (via `_spawn_origin()` at `:282-286`) | `_spawn_entry()` | `_spawn_origin() + entry.base_offset * ArenaCamera.WORLD_SCALE`, where `_spawn_origin()` returns `cam.global_position` (or the `(640,360)` fallback when there is no camera — the fallback is correct precisely because it equals `global_position` when at rest, per the function's own doc comment) |
| `assault/scenes/levels/edelia/1/level_1_director.gd:125` | `_spawn_bonus_drone()` | `cam.global_position + camera_offset` — **raw world px, not design units** (comment at `station_reinforcements.gd:226-229` calls this out explicitly as the one spawn site that does NOT scale by `WORLD_SCALE`) |

`Camera2D.offset` is a stock engine property (used directly by `ArenaCamera`'s own
`_physics_process`, not a custom field), so every call site can read `cam.offset` with no cast —
`get_viewport().get_camera_2d()` already returns a plain `Camera2D` at all three sites.

### Why `cam.offset`, not a new "pan" getter

`ArenaCamera.offset` is `_follow_offset + CameraShake.get_offset()` (`arena_camera.gd:90`), so it
also carries momentary shake noise. Spawns picking up a few px of shake at the instant they land
is invisible against margins measured in tens/hundreds of px, and a separate pan-only getter would
be a new public surface for a distinction nothing needs. Using the stock `offset` property also
means a bare `Camera2D` (no `ArenaCamera` script) is enough to exercise the fix in a test — no
custom node required.

## What does NOT change (out of scope)

- **Off-screen despawn/exit checks** (`enemy_path_mover.gd:106-109`, `kamikaze_drone.gd:72`,
  `drone_interceptor.gd:132-135`, `bomb.gd:96`, `bomber.gd:52`, `ram_ship.gd:67`,
  `small_asteroid.gd:29-32`, `ally_fighter.gd:71`, `strafe_exit_state.gd:21-22`). These compare a
  *live* position against `cam.global_position ± viewport/2 ± margin` every frame to decide when to
  free an entity. The task is specifically about spawn positioning ("a spawn's off-screen margin"),
  and these are a different mechanism (continuous bound checks, not a one-shot placement). Folding
  them in would multiply this from three call sites to a dozen with a different fix shape each
  (some would need the *current* frame's offset, which they already have via `cam.offset` — TODO
  note only, not code changed here).
- **`gunship.gd:58` / `approach_state.gd:20` `_hold_y`.** These compute a *waypoint* the ship
  flies to and stops at, sampled once in `_ready()`/on enter — not a spawn position. Same
  pinned-origin arithmetic, same latent inaccuracy, but a different feature (where an already-live
  enemy holds station) than "where does a spawn appear." Left alone; not "a spawn offset."
- **`score_popup.gd:34`** already does this correctly (`world_pos - (cam.global_position +
  cam.offset) + size * 0.5`) — it is the existing precedent that the fix's formula is right.

## Existing test coverage

No test currently builds a camera for `WaveManager`, `StationReinforcements`, or
`Level1Director`'s bonus-drone spawner:
- `tests/integration/test_station_assault_section.gd:8` states outright "there is no camera and
  no level scene, so `WaveManager._spawn_ship()` returns early" — waves are exercised for
  scheduling/sequencing only, spawning nothing.
- `tests/integration/test_level_1_sequence.gd` adds the station directly to the container; it
  never lets a wave-manager spawn actually run either.
- `tests/integration/test_station_reinforcements.gd` never adds a `Camera2D`, so
  `_spawn_origin()` always takes the no-camera fallback branch.

So the fix is currently *unreachable* by the suite — a new test has to add a real `Camera2D` (a
bare one is enough; no `ArenaCamera` behaviour is needed) with a non-zero `.offset` and assert the
spawned position includes it. That test is also what proves the bug today: written against the
current code, it fails.

## Conventions this touches

- Spawn offsets are authored in 640×360 design space and scaled by `ArenaCamera.WORLD_SCALE` at
  spawn — untouched by this fix, which only changes the *origin* the offset is added to.
- `tests/README.md`'s `user://` sandbox and `LevelDirector` coroutine-leak notes don't apply here
  (no timers, no save files) — the signal-arity note doesn't apply either (no new signals).
