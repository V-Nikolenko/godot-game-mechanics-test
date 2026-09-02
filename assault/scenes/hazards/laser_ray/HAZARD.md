# Laser Ray — The one-hit kill beam

**Role / threat:** A segmented vertical beam that instantly kills any entity it touches — player, enemy, or asteroid alike. It deals a fixed `_KILL_DAMAGE` of 9999 that exceeds any entity's max health, bypassing the normal `HitBox` type filter by emitting directly into the target's `HurtBox`. It is a positional/timing threat, not a destructible one: it has no HP and cannot be killed, only survived. A short telegraph (`warn_duration`) gives the player a window to dodge before the beam goes live, and while active it re-damages anything still inside it every 0.1 s to chew through invincibility frames and shield charges.

---

## Stats

| Property | Value |
|---|---|
| HP | n/a (indestructible) |
| Contact damage | 9999 (`_KILL_DAMAGE`, one-hit kill) |
| Score value | n/a (cannot be killed) |
| Beam geometry | `segment_count` × 128 px long, 56 px lit core (`_BEAM_WIDTH`) |
| `segment_count` | 12 (default; → 1536 px beam) |
| `warn_duration` | 0.0 (single ray); 3.0 s in `laser_wall.tscn` |
| `active_duration` | 4.0 s (0.0 = stay alive until `dissolve()`) |
| `auto_start` | true |
| Re-hit tick | every 0.1 s while idle/active |
| Hit mask | 128 \| 256 \| 512 (player + code-set enemy + .tscn enemy/asteroid hurtboxes) |
| `hit_mask_override` | 0 = use the mask above. Non-zero **replaces** it — see below. |
| Sprite | `giant_lasser.png` (128×128 atlas frames) |
| Scene | `laser_ray.tscn` (+ `laser_wall.tscn` variant) |

---

## Behaviour

**Geometry & spawning.** The emitter sits at the node origin; the beam is built from `segment_count` identical 128×128 tiles stacked along local +Y (so it extends "downward" in local space). The spawner rotates/positions the `LaserRay` node to aim it (0° = down, -90° = up, etc.). On `_ready()` it clones segment 0 (the `BeamSprite` template) into the remaining tiles so all share one `SpriteFrames` resource and animate frame-locked, then sizes a single `RectangleShape2D` hit zone (`_BEAM_WIDTH` × full length) to cover the lit core. If `auto_start` is true it fires immediately.

**State machine.** `laser_init → laser_increase → laser_idle (active, looping) → laser_dissolve`. Only segment 0 (the master) drives transitions via `animation_finished`; `_play_all()` switches every segment in lockstep:
- **INIT:** holds the thin warning line for `warn_duration`. With `warn_duration <= 0` it advances the instant the init frame finishes (no telegraph); otherwise a timer fires `_begin_increase`.
- **INCREASE:** charge-up animation.
- **IDLE:** plays the looping active beam, enables `monitoring`/`monitorable` (Godot immediately emits `area_entered` for any HurtBox already overlapping), and starts the continuous re-hit timer. If `active_duration > 0` a timer schedules `_begin_dissolve`.
- **DISSOLVE:** stops the timer, disables monitoring, plays the dissolve animation, then `queue_free()`s on completion.

**On contact.** When a `HurtBox` enters the live zone (`_on_area_entered`) the laser emits `received_damage(9999)` directly into it — an instant kill — and flashes `laser_damage` once. The repeating `_continuous_timer` (`_on_continuous_tick`, every 0.1 s during IDLE) re-emits the kill into every HurtBox still overlapping, handling targets that entered while invincible (PlayerBase has 0.5 s i-frames) or with shield charges to deplete.

**How it is destroyed.** The laser is never killed by damage — it self-terminates: either `active_duration` elapses, or an external `LevelDirector` calls `dissolve()` while IDLE. Both route through `_begin_dissolve` → dissolve animation → `queue_free()`.

**`laser_wall.tscn` variant.** Composes 12 `laser_ray` instances spaced 56 px apart (positions 28 → 644 px), each with `warn_duration = 3.0`, forming a solid wall of beams across the play-field that telegraphs for 3 seconds before going live — a dodge-the-gap set-piece rather than a single ray.

---

## `hit_mask_override` — for emitters mounted on an entity

The default `_HIT_MASK` (`128 | 256 | 512`) covers **every** known HurtBox layer, which is right for a hazard sitting in the play-field and wrong for a beam fired *by* something. Layer 512 is where most enemies' scene-authored hurtboxes live, including the space station's core — so a `LaserRay` spawned inside its own emitter's hull kills the emitter. Measured on the station: `[Health] SpaceStation took 9999 damage: 600 → 0 HP`, one frame after the laser phase starts.

`@export_flags_2d_physics var hit_mask_override: int = 0` replaces the whole mask when non-zero. `StationLaserPhase` sets `128` (player hurtbox only). Three rules:

- **It must be assigned BEFORE `add_child()`** — `_ready()` is what reads it. The export makes the requirement a declarative, directly assertable property of the beam rather than a silent ordering dependency on writing `$HitZone.collision_mask` after the fact.
- **`0` means "use the default", not "collide with nothing".** A beam that collides with nothing is inert, and that is not a configuration anyone wants.
- **It replaces the mask; it does not OR into it.**

Pinned by `tests/integration/test_laser_ray_hit_mask.gd`, which exists mainly to stop the *default* being silently narrowed — the race hazards and Level 1's laser columns all need the full `128 | 256 | 512`.

---

## Files

```
laser_ray/
├── HAZARD.md         ← this file
├── laser_ray.gd      ← LaserRay: segment building, animation state machine, kill logic
├── laser_ray.tscn    ← single beam scene (SpriteFrames + HitZone)
└── laser_wall.tscn   ← variant: 12 laser_ray instances forming a telegraphed wall
```
