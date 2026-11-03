# Laser Tender — the controller ship that launches a moving laser wall

**Role:** A slow carrier with two Twin-Laser Drones docked in visible cradles. It holds at range, its cradles glow for a moment, and it launches both
drones in a V toward two points either side of where the player is going. They land as a `|---|` wall across that route, warn, and advance through it
as one wall of fixed length (IDEAS §6.10, Attack B: the "controller ship").
**Fantasy / threat:** Not a gun but a trap-setter: it cuts off the escape route instead of shooting at you. The real danger is the wall it puts out; the
tender itself is a priority target because killing it ends the supply of walls.

> **Build state (Phase 8, t13).** Built: the scene and shell, the flat config, `LaserTenderBrain` (the full append-only `Phase` enum; APPROACH / HOLD /
> LAUNCH / WAIT / REARM / DISENGAGE played), the `launch_pair(points)` seam, the Attack B points (Open Space prediction, Assault vertical / horizontal
> walls), the rig's LAUNCHED phase and fixed launched frame, one live pair, rearm, docking of a lone returning drone, the Assault variant (one launch per
> life, the cradle-telegraph deferral), `WaveBuilder.laser_tender()`. **Not yet:** the hub idle (`IDLE` / `NOTICING` / `RETURNING`, t14) and the
> measured Assault exit (t14), the art (t16: the hull and the docked drones are code-drawn / textureless placeholders), hub and level-1 placement (t18 /
> t19). Plan: `docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md` §2.13; task plan `docs/plans/cmvqw0vnz018nqs2xv56q6a0a/3-plan.md`. The drones and the rig
> are `../twin_laser_drone/` ([ENEMY.md](../twin_laser_drone/ENEMY.md)).

---

## Stats

| Property | Value |
|---|---|
| HP | 160 (`laser_tender_config.tres`) |
| Damage | 15 contact (`ContactHitBox`, `ContactProfile` COLLISION). No gun: the damage is its pair's beam (`twin_beam.tscn`) |
| Speed | `max_speed` 200, `acceleration` 400; DISENGAGE `exit_speed` 380 |
| Body | one `CircleShape2D` r 40 shared by the body (layer 1 / mask 1), the `HurtBox` (512 / 65) and the `ContactHitBox` (256 / 0) |
| Cradles | `CradleL` (-30, 10) and `CradleR` (30, 10), `Marker2D`s, each with a `DockedDrone` (`Polygon2D`, r 11, textureless) shown while that cradle holds a drone |
| Light | `StateLight` at (0, 10), between the cradles: CHARGING through the 0.6 s cradle telegraph (LAUNCH), OFF otherwise |
| Sprite | placeholder, code-drawn in `_draw()` (dark r 40 disc, rim, two cradle notches); hit flash animates `.:self_modulate`. t16 replaces it |
| Scene / config | `laser_tender.tscn` / `laser_tender_config.tres` (flat `LaserTenderConfig`) |
| Hazards | `hazard_avoidance` 0.8, `hazard_margin` 24, `hazard_resistance` 0.3; `wreck_chance` 0.35, `wreck_size` 1 (medium, the Mine Layer's); score 120; `counts_as_escape` true |

Every value is a plan §2.21 *starting value* (judgement, not play-tested).

---

## Behaviour

`LaserTenderBrain.Phase { APPROACH, HOLD, LAUNCH, WAIT, REARM, DISENGAGE, IDLE, NOTICING, RETURNING }` (append-only), `signal phase_changed(new_phase: int)`,
`signal launched(pair: TwinLaserPair)`. Transitions cascade inside one tick (APPROACH -> HOLD -> LAUNCH; REARM -> HOLD -> LAUNCH).

- **APPROACH / HOLD.** Open Space: `arrive` at `preferred_range` 650 from the player, facing it; within `range_tolerance` 80 -> HOLD, a broad arc
  (`mover.orbit`, `arc_rate` 0.12 rad/s, direction from the brain's rng). Assault: see below.
- **LAUNCH** (needs both cradles full, no live pair of its own, line of sight on the physics step): the cradle light CHARGING for `launch_telegraph` 0.6 s,
  then `launch_pair(attack_b_points())`. Refuses a tow (`accepts_tow()` false only here).
- **WAIT** while its pair is intact; then **REARM** for `rearm_seconds` 7.0 with empty cradles; then `rearm_cradles()` and HOLD again. **At most one live pair.**
- **Docking** (Open Space, every phase but DISENGAGE): a drone it launched (any rig) whose brain is SOLO (its partner died; t12 sends it to its live
  controller) within `dock_radius` 72 is taken back with `dock()`: freed without dying, one cradle refilled.

### `launch_pair(points: PackedVector2Array) -> TwinLaserPair` (the Ph10 / Ph11 seam)

Instantiates two drones from `drone_scene` at `CradleL` / `CradleR`, seeds each brain from the tender brain's rng, adds a mutual collision exception
with the tender (they start inside its body and dock back into it), adds both as siblings in the tender's parent (A first, so A leads on real physics),
binds them with `TwinLaserPair.bind(a, b, self)` (the tender joins the owner group, so its own pair's beam never hurts it), puts the rig in LAUNCHED
toward `points[0]` (A) / `points[1]` (B), empties the cradles and announces both with `EventBus.enemy_spawned_orphan`. **The caller orders the points.**
The drones are added **synchronously** (a logged deviation from §2.13's "deferred"): call it on the physics step or from idle code, never from a physics
callback, where a caller must `call_deferred` it. Null with fewer than two points, no parent or no drone scene.

### Attack B points (`attack_b_points()`, pure statics `open_space_points()` / `assault_points()` / `order_for_cradles()`)

`L`, `standoff` and `slot_tolerance` are the launched drone's own (a probe of `drone_scene`, so a swapped drone is planned with its numbers).
- **Open Space.** `t = min(lead_time_max 1.5, |P - tender| / launch_speed 520)`. Moving (>= 20 px/s): centre `P + v * t`, axis across the heading.
  Standing: centre `P + facing * standing_lead` 120, axis across the tender's bearing. `Q± = centre ± u * L/2`.
- **Assault** (inside the corridor's `inner_rect()` inset by `slot_tolerance`). `|v.x| >= strafe_speed_min` 60: a vertical wall at
  `x = P.x + sign(v.x) * assault_wall_lead` 180, centred on `P.y`; otherwise a horizontal wall `standoff` 260 above the player. Both clamped.
- **The V never crosses:** the left cradle takes the point that gives the shorter total leg length. The V's opening angle is geometry: a wall broadside to
  the tender opens 35°–90°, an end-on one (a player crossing the tender's bearing) only ≈ 10°–20° (logged; the rows assert "diverging, never crossing" there).

### The launched wall (in the rig, `twin_laser_pair.gd`)

- **LAUNCHED** (`TwinLaserPair.Phase.LAUNCHED`, appended): each drone boosts straight from its cradle to its point at `launch_speed` for
  `min(|Q - start| / launch_speed, launch_max_seconds 1.4)`; the last, partial step lands it on the point and the next tick stops it dead (a boost keeps
  its speed); the rig leaves LAUNCHED `LAUNCH_SETTLE_TICKS` 2 ticks after the longer boost. A capped leg ends `launch_speed * launch_max_seconds` = 728 px
  out and `arrive`s the rest.
- **Fixed frame:** `centre = mid(Q-, Q+)`, `u` from A's point to B's, `n` signed toward the line from the player. FORM keeps it (no player feed-forward);
  at the latch `n` is re-signed toward the latched player and the advance is `min((centre - P) · n, standoff) + overshoot` (Assault: also capped by the
  corridor's room). Then TELEGRAPH (latched) -> ADVANCE as one `|---|` wall, keeping its length (R8.24), then ordinary Attack A cycles until killed.
- **Consequence of §2.13's prediction horizon (logged):** the horizon covers the flight, not FORM or the 0.8 s telegraph, so a player who holds a constant
  velocity is already past the wall when it lights and it chases from behind; a player who turns back or slows meets it.

---

## Assault

- The tender enters from the top and holds in the **upper band** of the visible corridor: the hold point is `(clamp(P.x), view.top + assault_hold_depth 140)`,
  kept `2R + 40` px above the player, `2R` inside `inner_rect()`. APPROACH -> HOLD on reaching the band (its y within `HOLD_REACH` 24 of the hold point's,
  inside the view), not the point: the point tracks a strafing player's x and the tender never catches one at 360 px/s.
- **One launch per life**, only from inside the view. After it, or once `engage_seconds` 10.0 runs out before LAUNCH starts, DISENGAGE:
  `release_constraint()`, `max_speed = exit_speed`, straight out toward the nearest edge of the projectile world rect, freed once strictly outside it.
- **Launch-time bound:** a budget that expires during the cradle telegraph lets that launch finish, so a pair is launched no later than
  `spawn + engage_seconds + launch_telegraph + _TICK_SLACK`. The tender's life is at most that plus its exit (t14 measures the exit).
- A player hugging the top of the corridor can push the hold point above the view and so hold off the launch until the budget ends (the §2.13 "budget
  runs out before LAUNCH" case, accepted).
- The pair does its one attack and DISENGAGEs (t12's rule; every advance is at most `(standoff + overshoot) / advance_speed` = 1.92 s).

---

## Spawning

- `b.laser_tender().at(x, y)` (`WaveBuilder.LASER_TENDER`), camera-relative like every ship spawn. See [`docs/enemy-roster.md`](../../../../docs/enemy-roster.md).
- **Never in an `ENEMIES_CLEARED` section** (`test_engagement_deadline.gd`). Not placed in level 1 or the hub yet (t18 / t19).

---

## Counterplay (IDEAS §6.10)

- Read the cradle glow (0.6 s) and the V: the wall lands across your route, so change direction; it cannot re-aim once it shows its line.
- Go round an end before it arrives (a 360 px/s runner is never hit), or kill one drone (30 HP) to delete the wall.
- Lure a drone into a wreck or a well (t12's strain and collapse).
- Kill the tender: no more walls. It rearms for 7 s between pairs, and a lone survivor flies home to dock, which shows you it is out of drones.

## Design checklist (IDEAS §43)

| Question | Answer |
|---|---|
| Unique silhouette | A broad r 40 disc with two drones visibly docked side by side (final art t16) |
| Preferred distance | `preferred_range` 650 (Open Space); the upper band of the screen (Assault) |
| Movement signature | Slow, broad arc at range; never closes in |
| How it attacks | It launches its drones as a wall across the player's escape route |
| Player behind it | Points come from the player's position and velocity, not the tender's facing; it faces the player while holding |
| Player boosts away | The prediction leads by up to 1.5 s; a player who outruns that is chased by the wall from behind |
| Off-screen | Open Space needs no camera; world-space points |
| Retreat / reposition | WAIT / REARM on its arc (Open Space); DISENGAGE after its one launch (Assault) |
| Telegraph | The cradle light CHARGING for 0.6 s, then the visible V; the wall itself warns 0.8 s on its exact line |
| Destroying it changes the encounter | No more pairs; a surviving pair keeps attacking with Attack A |
| Open Space without camera coordinates | Yes (both harnesses) |
| Assault, constrained | Yes: a hold band, corridor-clamped walls, one launch per life |
| Sprite communicates state | Docked drones visible / hidden per cradle; the cradle light; art t16 |
| Armour / shields / weak points | None; 160 HP |
| Works alone | It needs its drones; with none docked it only waits / rearms |
| Better combined | Yes: the wall herds the player into other enemies' fire |
| Deterministic tests | Yes: hand-ticked rows in both harnesses; one real-physics row at 8× |

## Gates

`tests/integration/test_laser_tender.gd` (INTENT, both harnesses): structure, config, the enum pins; the cradle telegraph and the V (never crossing, straight
legs, on the point a tick after the boost, capped legs, `L` at the latch) over five geometries; the Open Space points (on the predicted path, across the
heading, the standing rule, the prediction horizon); Attack B keeps its length on every TELEGRAPH / ADVANCE tick (R8.24) with a latched frame, the sign rule and
the advance length; the wall hits a standing stub and misses one that runs round an end; the tender is never hit by its own pair's beam (a victim beside
it is); one live pair and rearm timing; a lone survivor docks (at once, and after a rearm); the Assault vertical / horizontal walls inside `inner_rect()`,
the band approach from above against a 360 px/s strafer, one launch per life then DISENGAGE, the cradle-telegraph deferral and its before-LAUNCH boundary;
the launch on real physics at 8× (collision exceptions, straight legs); the `WaveBuilder` row. Also: the rosters of `test_enemy_hurtbox_geometry.gd`,
`test_contact_hitbox_geometry.gd`, `test_enemy_contact_damage.gd`, `test_wreck.gd`; `test_base_enemy.gd` (roster 20, authored COLLISION, the tow table: LAUNCH);
`test_enemy_dual_mode.gd` (`test_laser_tender_launches_a_pair_in_both_modes`, the hazard-profile row); `test_engagement_deadline.gd`; the no-motion source sweep
in `test_twin_laser_drones.gd` covers `laser_tender.gd` and `laser_tender_brain.gd`.

## Files

```
laser_tender/
├── ENEMY.md                    ← this file
├── laser_tender.tscn / .gd     LaserTender (BaseEnemy shell, launch_pair / dock / rearm_cradles)
├── laser_tender_brain.gd       LaserTenderBrain
└── laser_tender_config.gd / .tres   LaserTenderConfig (flat)
```
