# Hacker Frigate — the electronic-warfare frigate that keeps out of your nose

**Role:** A medium frigate that attacks the player's tools rather than the hull (IDEAS §6.4). It hangs back at medium-long range on a lopsided arc,
slides out of the player's nose and off their flight line, and breaks off hard when rushed. Its weapon, the Hijack Pulse that turns the player's homing
rockets back on them, arrives in t9.
**Fantasy / threat:** A support threat that is hard to pin down: it is never where the gun is pointing. The counterplay is to commit — chase it down
(a 420 px/s cruise catches it), or kill it before it pulses.

> **Build state (Phase 9, t8).** Built: the scene and shell, the flat config, `HackerFrigateBrain` (the full append-only `Phase` enum; HOLD_ARC,
> BREAK_OFF, DISENGAGE and the hub idle played; **TELEGRAPH / PULSE are stubs** that go straight back to HOLD_ARC, and `_want_pulse()` is false),
> `WaveBuilder.hacker_frigate()`, the measured Assault exit (`tests/helpers/ph9_exit_keys.gd`). **Not yet:** the Hijack Pulse and its config fields
> (t9), the Disruptor variant (t10), the art (t12; the hull is a placeholder `Polygon2D`), hub and level placement (t13 / t14). Plan:
> `docs/plans/cmug23onr001pm52w9swwophy/3-plan.md` §2.10; task plan `docs/plans/cmw5k4yk400aiqs2xujalkqzf/3-plan.md`.

---

## Stats

| Property | Value |
|---|---|
| HP | 120 (`hacker_frigate_config.tres`) |
| Damage | 15 contact (`ContactHitBox`, `ContactProfile` COLLISION). No gun |
| Speed | `max_speed` 230, `acceleration` 700 (the Support Ship's), `max_turn_rate` 1.4; break-off burst 360 (Open Space); DISENGAGE `exit_speed` 300 |
| Body | one `CircleShape2D` r 40 shared by the body (layer 1 / mask 1), the `HurtBox` (512 / 65) and the `ContactHitBox` (256 / 0) |
| Dish | `Dish` (`Node2D` at (0, -14)) with a placeholder `Antenna` `Polygon2D`: the part t9 unfolds in TELEGRAPH and t12 draws |
| Light | `Dish/StateLight`, OFF in every t8 phase (t9: CHARGING in TELEGRAPH) |
| Hull | `Hull` placeholder `Polygon2D` (~88 × 90 px, nose-down wedge) until t12; the hit flash animates `Hull:self_modulate` |
| Scene / config | `hacker_frigate.tscn` / `hacker_frigate_config.tres` (flat `HackerFrigateConfig`) |
| Hazards | `hazard_avoidance` 0.7, `hazard_margin` 80, `hazard_resistance` 0.4 (the corvette's); `wreck_chance` 0.4, `wreck_size` 1; score 90 |

Every value is a plan §2.19 *starting value* (judgement, not play-tested).

---

## Behaviour

`HackerFrigateBrain.Phase { HOLD_ARC, TELEGRAPH, PULSE, BREAK_OFF, DISENGAGE, IDLE, NOTICING, RETURNING }` (append-only),
`signal phase_changed(new_phase: int)`. `enter_phase()` is the one transition (and the test seam).

- **HOLD_ARC** (composed from the Missile Corvette's; copied, not inherited). It orbits the player at `held_range()` — `preferred_range` 720 (Open Space)
  or `assault_preferred_range` 520 (Assault) — plus a slow `sin` drift of ± `range_drift` 90 (period 6–9 s). The arc is **lopsided**: `orbit_dir` +1
  (clockwise on screen, the bearing angle growing) runs at `orbit_speed_cw` 0.18 rad/s, -1 at `orbit_speed_ccw` 0.30 rad/s, and the direction reverses
  every `reversal_min`..`reversal_max` 3–6 s (from the brain's rng). The motion is the corvette's target-angle pattern (`_orbit_angle += dir · speed · dt`,
  then `Steering.orbit` toward that point at up to `max_speed`); there is no APPROACH: the orbit's correction closes a far start at `max_speed`. The
  nose faces the player.
- **Bearing penalty** (§18.6: stay out of the easiest attack angle and off the route). Two cones round the player, read from `TargetInfo` and from the
  config **every tick**: the **nose cone** ± `nose_cone_deg` 30 round its facing, then the **route cone** ± `route_cone_deg` 25 round its velocity
  (only above `route_min_speed` 80 px/s). While its bearing lies inside one, the arc is forced toward that cone's **nearer edge** (on the centre line it
  keeps its direction) at `cone_escape_speed` 0.30 rad/s, and no reversal is drawn. `in_cone` / `cone_kind` report it. It does not out-turn a player who
  keeps turning: it slides out of a nose that stopped, the short way, in about 1.3–1.7 s. A player faster than 230 px/s simply outruns it.
- **BREAK_OFF** (entered from HOLD_ARC inside `min_range` 420 once `break_rearm_seconds` 1.0 have passed since the last one; the first move is made on the
  entry tick). **Open Space:** committed `mover.boost` bursts at `break_speed` 360 for `break_burst_seconds` 0.8 along
  `Steering.break_contact(..., break_lateral_weight 0.25)` (side from the rng on entry), re-issued at each burst's end. Against a closing threat
  `break_contact` doubles the lateral share, so the radial part is 360 / √1.25 ≈ 322 px/s: it out-runs a 300 px/s rusher and loses to the player's
  420 px/s cruise. **Assault:** no boost (the view clamp is a target clamp a boost would bypass): a `max_speed` request toward a point 230 px ahead along
  the same line, clamped into view. It ends beyond `min_range + break_exit_margin` (540 px) or after `break_max_seconds` 3.0, then the rearm.
- **TELEGRAPH / PULSE:** stubs until t9 (straight back to HOLD_ARC; DISENGAGE if the budget expired meanwhile). Both refuse a tow.
- **EMP:** the `BaseEnemy` default (it answers EMP: halts, not ticked for the window, stays shootable); a burst in progress ends with the halt, and
  BREAK_OFF re-issues one after the window.

### Assault (§2.10)

Every target point goes through `_clamp_into_view()`: `EnemyWorld.view_rect().grow(-(view_margin 60 + VIEW_CLAMP_PAD 8))`. The 8 px pad keeps the hull
itself inside `grow(-60)`: `Steering.orbit`'s 60 px/s correction floor makes a body parked on its point wobble ±2.6 px. `view_clamp_bound` reports
whether the last clamp moved its point. An `EngagementBudget(engage_seconds 9.0)`; at expiry **DISENGAGE** (the corvette's exit: release the
corridor, `exit_speed` 300, curve toward the nearest edge of the projectile world rect at `min(max_turn_rate, acceleration / exit_speed)`, free
once strictly outside). A TELEGRAPH / PULSE finishes first (t9). **Measured exit:** worst 5.67 s over `corridor_starts()` at [230, 10] px/s (2166
runs, 0 capped), through `PH9.hacker_exit()` only (`tests/helpers/ph9_exit_keys.gd`). Never in an ENEMIES_CLEARED section
(`test_engagement_deadline.gd`).

### Hub idle

Open Space, not `start_engaged`: an `AnchorIdle` round `patrol_anchor` (`perceive_radius` 760, `lose_radius` 1600, `notice_time` 0.35,
`home_radius` = `idle_radius` 160) runs ahead of the phase dispatch and never interrupts a TELEGRAPH / PULSE.
- **IDLE:** a ring of `idle_radius` 160 round the anchor, lopsided like its arc: `idle_speed` 0.45 rad/s the ccw way, 0.45 · 0.18 / 0.30 = 0.27 the cw way.
- **NOTICING:** stop, face the player; after `notice_time` -> HOLD_ARC.
- **RETURNING:** beyond `lose_radius`: `arrive` at the anchor, then IDLE.

### Test seams

`force_orbit_direction(dir)` (±1; a cone still overrides it while inside), `orbit_angle()`, `orbit_speed(dir)`, `held_range()`, `in_cone`,
`cone_kind`, `view_clamp_bound`, `break_offs`, `start_engaged`, `patrol_anchor`.

---

## Measured cone exits (t8, GUT)

The plan's cone-row procedure (warm-up 2.0 s in a forced direction, cones 0, reversals held, `range_drift` 0; then the cone axis snapped to the bearing
± 10°). Seconds to leave the cone through the near edge (first snap / re-snap 3.5 s after the exit):

| Case | Nose, 720 px (bound 2.2) | Nose, 520 px Assault (bound 1.9) | Route, 100 px/s player (bound 1.8) | Control (cone 0): still inside at the bound; exits at |
|---|---|---|---|---|
| 0.18 rad/s, far way | 1.55 / 1.70 | 1.55 / 1.63 | 1.25 / 1.18 | nose 3.88 (far edge); route 3.27 |
| 0.30 rad/s, far way | 1.70 / 1.55 | 1.63 / 1.55 | 1.60 / 1.10 | nose 2.33 (far edge); route 1.85 |
| 0.18 rad/s, near way | 1.27 / 1.27 | 1.27 / 1.27 | 0.88 / 1.03 | — |

Far-way time ≤ 0.43 s in every case (bound 0.5). The tightest margins: the route 0.30 rad/s control (1.85 s against 1.8) and its far-way time (0.43 s).

---

## Tests

`tests/integration/test_hacker_frigate.gd` (both harnesses): structure and config, holds range, the lopsided arcs (hull bearing rate) and reversals over
4 seeds, the nose and route cone rows with their controls, the 360 px/s outrun, the 300 px/s rusher and the 420 px/s chase (with controls), the Assault
break-off and life inside `view_rect().grow(-60)`, the measured exit and its memo / hook / source-sweep rows, hub idle and notice at 760 px, the stubs,
the budget deferral and suspension. Roster gates: `test_enemy_contact_damage.gd`, `test_contact_hitbox_geometry.gd`, `test_enemy_hurtbox_geometry.gd`,
`test_base_enemy.gd` (tow table: TELEGRAPH / PULSE refuse), `test_enemy_dual_mode.gd` (hazard profile, closes to its range in both modes),
`test_engagement_deadline.gd` (no ENEMIES_CLEARED section), plus the automatic sweeps.
