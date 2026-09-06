# Context — should the station's core HurtBox be narrowed to 88 x 240?

## The question, restated

`assault/scenes/enemies/space_station/space_station.tscn` declares **one**
`RectangleShape2D` sub-resource of `size = Vector2(240, 240)` (`:22-23`) and hands the same
resource to **both** the body `CollisionShape2D` (`:71-72`) and the core `HurtBox`'s
`CollisionShape2D` (`:80-81`). The backlog asks whether the `HurtBox` should instead get its own
88-wide shape so that its x-extents `[-44, 44]` become disjoint from the four turret hurtboxes'
`[50, 102]`.

It is explicitly framed as a **design call, not a bug fix** — the reachability worry that
originally motivated it turned out to be false.

## Modules and files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/enemies/space_station/space_station.tscn` | The mini-boss scene | Holds the single shared `RectangleShape2D_ss` and the four turret instances at `(±76, ±76)` |
| `assault/scenes/enemies/space_station/space_station.gd` | `SpaceStation extends BaseEnemy` | `_on_received_damage` refuses damage while `is_armored()`, emitting `armor_deflected` + hit flash instead |
| `assault/scenes/enemies/space_station/station_turret.tscn` | One gun emplacement | `CircleShape2D` `radius = 26` at the turret's local origin; scene positions put it at `(±76, ±76)` |
| `assault/scenes/enemies/space_station/station_turret.gd` | `StationTurret` | `_destroy()` closes its own hurtbox, so a dead turret stops being a target |
| `assault/scenes/enemies/space_station/station_laser_phase.gd` | Phase 2 | `_physics_process` spins `_station.rotation` continuously — **the core hurtbox rotates with the hull** |
| `assault/assets/sprites/enemies/station_core.png` | The hull art | **256 x 256** (verified from the PNG IHDR), so the visible hull is 16 px wider than the 240 collider on each axis |
| `tests/integration/test_space_station.gd` | Intent tests for the armour rule | Drives damage by emitting `received_damage` directly, so it asserts nothing about geometry |
| `tests/integration/test_contact_hitbox_geometry.gd` | Project-wide invariant over contact `HitBox` geometry | The exact harness and file idiom a hurtbox-geometry invariant should mirror |

## Measured geometry (all values are scene-local pixels, sprites are authored at final size)

| Region | x-extent | y-extent |
|---|---|---|
| Visible hull (`station_core.png`) | `[-128, 128]` | `[-128, 128]` |
| Body `CollisionShape2D` (240 x 240) | `[-120, 120]` | `[-120, 120]` |
| Core `HurtBox` **today** (same 240 x 240 resource) | `[-120, 120]` | `[-120, 120]` |
| Core `HurtBox` **as proposed** (88 x 240) | `[-44, 44]` | `[-120, 120]` |
| Turret hurtbox, right pair (circle r = 26 at x = 76) | `[50, 102]` | `[50, 102]` and `[-102, -50]` |

The player fires **up** (`-Y`) in the assault autoscroller, so a shot's fate is decided by its
`x` alone while the hull is axis-aligned. Under the proposed 88-wide core:

- `|x| < 44` → core (deflected in phase 1, damaging in phase 2)
- `44 <= |x| < 50` → **hits nothing** (6 px lane each side)
- `50 <= |x| <= 102` → a turret, but only in the two `y` bands the circles occupy
- `102 < |x| <= 128` → **hits nothing** (26 px lane each side, all of it over visibly solid hull)

That is `2 x (6 + 26) = 64` px of a 256 px-wide boss — **25 % of its visible width** — that
swallows shots with no feedback of any kind while the hull is axis-aligned.

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `tests/integration/test_contact_hitbox_geometry.gd` | A finished roster-sweep harness: throwaway `Node2D` container per entity, `add_child_autofree`, direct-children-only search, plus two anti-vacuity guards worth copying |
| `tests/integration/test_enemy_contact_damage.gd` | The same roster, and the precedent for an invariant test over *balance/geometry data* rather than files |
| `global/components/hurtbox_component.gd` | `HurtBox` — the node type the sweep would look for |
| `assault/scenes/enemies/*/ *.tscn` (10 enemies) | The de-facto convention, measured below |

### The convention the rest of the roster already follows

Every assault enemy hands its **body `CollisionShape2D`'s own `Shape2D` resource** to its
`HurtBox`, at the same scale:

| Enemy | Body shape / scale | HurtBox shape / scale | Delta |
|---|---|---|---|
| `bomber` | `CircleShape2D_bm` r22, identity | same resource, identity | 0 |
| `bonus_drone` | `CircleShape2D_bd` r12, identity | same resource, identity | 0 |
| `drone_interceptor` | `CircleShape2D_dri` r10, x3.0799994 | same resource, x3.079999 | ~0.000004 px |
| `gunship` | `CircleShape2D_gs` r18, x2.3077412 | same resource, x2.289032 | hurtbox **0.34 px smaller** |
| `interceptor` | `CircleShape2D_int` r14, x1.8000002 | same resource, x1.8 | ~0.000003 px |
| `kamikaze_drone` | `CircleShape2D_kd`, identity | same resource, identity | 0 |
| `light_assault_ship` | `CircleShape2D_siexo` r13, x2.199998 | same resource, x2.199998 | 0 |
| `ram_ship` | `CircleShape2D_rs` r36, identity | same resource, identity | 0 |
| `sniper_enemy` | `CircleShape2D_se` r14, x1.4400002 | same resource, x1.4505496 | hurtbox **0.15 px larger** |
| `space_station` | `RectangleShape2D_ss` 240x240, identity | same resource, identity | 0 |

**Ten out of ten.** The station is not an outlier that needs bringing into line — narrowing it
would make it the only enemy in the game whose damageable area is smaller than the hull the
player can see. The two sub-pixel deltas are hand-dragged editor scale handles, not intent.

## Conventions that constrain this

- **`CLAUDE.md`, composition over inheritance** — the station is assembled from
  `global/components/`; any answer has to work through the existing `HurtBox` node, not a new
  bespoke mechanism.
- **Commit `501d662` — "Give every contact hitbox the hull the player can see."** The project
  has just spent a cycle establishing that a collision box smaller than the visible ship is a
  *defect*: the gunship's 41.5 px hull rammed with an 18 px box and 62 % of it passed through
  the player like a ghost. `tests/integration/test_contact_hitbox_geometry.gd` is the gate that
  came out of it. Narrowing a hurtbox to 37 % of its hull's width is the same defect class,
  applied deliberately.
- **Bullets are not consumed by the first hurtbox they overlap.** The repo's own recorded
  finding (`code-health-backlog`, "Two consecutive reviews asserted that a player bullet dies on
  its first hurtbox overlap"): `bullet.gd:84` emits `expired` without `queue_free()`, the only
  `queue_free()` at `:49` is gated on `range_px > 0.0`, and `weapons/modes/default.tres` sets
  `range_px = 0.0`. **The original justification for narrowing — "a bullet fired up a turret
  lane triggers a core deflection before it reaches the turret" — is therefore purely cosmetic:
  the bullet deflects off the core *and still hits the turret for full damage in the same
  pass.*** Nothing is lost; a hull flash is added.
- **The hull rotates in phase 2.** `station_laser_phase.gd` spins `_station.rotation` at
  `laser_rotation_speed = 0.5 rad/s` for the whole second half. The core `HurtBox` is a child of
  the station, so whatever shape it has rotates with it.
- **`ArenaCamera.WORLD_SCALE`** does **not** apply here: `ENEMY.md` is explicit that station
  sprites and the turret offsets `(±76, ±76)` are final on-screen pixels, not design units.

## The active epic that overlaps this question

`BACKLOG.json` epic `boss-fight-escalation-shared-hull-flying-laser-projectors-de` is **active**
(user-approved), and its first task is titled, verbatim:

> **1. Every shot that lands on the station hurts the station.**

It replaces the five separate HP pools with one shared pool, so that "hits on a turret, on a
laser projector, or on the core all draw down the same station health". A narrowed core hurtbox
is directly hostile to that goal: shots through the hull shoulders would land on *nothing at
all*, which is strictly worse than today's deflection, and the epic would have to re-widen the
shape as its first act.

## Open questions for research

1. What is the shipped-genre convention for **enemy/boss** hitbox size relative to the sprite in
   a vertical shmup? (The tiny-hitbox rule is famously a *player* rule — does it invert for
   enemies?)
2. How do shipped multi-part bosses ("shoot the guns, then the core") separate a part hit from a
   body hit, if not by making the body's hurtbox disjoint from the parts'?
3. Is there a real cost to a boss body that reports a no-damage "deflect" on a hit that also
   damages a part — i.e. does the double feedback read as noise or as information?
