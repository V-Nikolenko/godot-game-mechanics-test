# Hacker Frigate — the electronic-warfare frigate that keeps out of your nose

**Role:** A medium frigate that attacks the player's tools rather than the hull (IDEAS §6.4). It hangs back at medium-long range on a lopsided arc,
slides out of the player's nose and off their flight line, and breaks off hard when rushed. Its weapon is the **Hijack Pulse**: a visible charge, then a
window in which control darts fly from its hull to the player's homing rockets and turn them back on the player.
**Fantasy / threat:** A support threat that is hard to pin down: it is never where the gun is pointing, and it punishes lazy rocket spam. The
counterplay is to hit it while it charges (any damage cancels the pulse), hold the homing rockets while it pulses, kill it (its darts vanish and its
claimed rockets fizzle), lure a claimed rocket into another enemy, or chase it down (a 420 px/s cruise catches it).

> **Build state (Phase 9, t9).** Built: the scene and shell, the flat config, `HackerFrigateBrain` (the full append-only `Phase` enum, every phase
> played), the Hijack Pulse (TELEGRAPH, PULSE, the `HijackPulse` dart, the Disruptor hook with `pulse_lock_seconds` 0 here),
> `WaveBuilder.hacker_frigate()`, the measured Assault exit (`tests/helpers/ph9_exit_keys.gd`). **Not yet:** the Disruptor variant's scene and config
> (t10), the art (t12; the hull is a placeholder `Polygon2D`), hub and level placement (t13 / t14). Plan:
> `docs/plans/cmug23onr001pm52w9swwophy/3-plan.md` §2.10, §2.11; task plans `docs/plans/cmw5k4yk400aiqs2xujalkqzf/3-plan.md` (t8) and
> `docs/plans/cmw5k4yk700amqs2xuk3t1oge/3-plan.md` (t9).

---

## Stats

| Property | Value |
|---|---|
| HP | 120 (`hacker_frigate_config.tres`) |
| Damage | 15 contact (`ContactHitBox`, `ContactProfile` COLLISION). No gun: its weapon is the Hijack Pulse, which deals no damage itself |
| Speed | `max_speed` 230, `acceleration` 700 (the Support Ship's), `max_turn_rate` 1.4; break-off burst 360 (Open Space); DISENGAGE `exit_speed` 300 |
| Body | one `CircleShape2D` r 40 shared by the body (layer 1 / mask 1), the `HurtBox` (512 / 65) and the `ContactHitBox` (256 / 0) |
| Dish | `Dish` (`Node2D` at (0, -14)) with a placeholder `Antenna` `Polygon2D`: folded at scale 0.6, it unfolds to 1.0 through TELEGRAPH and stays open in PULSE (t12 draws it) |
| Light | `Dish/StateLight`: CHARGING (yellow) in TELEGRAPH, COMMIT (white) in PULSE, OFF otherwise |
| Darts | `DartPool` (`BulletPool`, `pool_size` 4, no `persist_after_owner_death`) of `HijackPulse` (`assault/scenes/projectiles/hijack_pulse/`) |
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
- **TELEGRAPH / PULSE:** the Hijack Pulse, below. The arc goes on through both, both refuse a tow, and BREAK_OFF waits for the first HOLD_ARC tick
  after them.
- **EMP:** the `BaseEnemy` default (it answers EMP: halts, not ticked for the window, stays shootable); a burst in progress ends with the halt, and
  BREAK_OFF re-issues one after the window. `on_emp_started()` cancels a TELEGRAPH and ends a PULSE at once, without the lock hook, each with a
  fresh cooldown (deviation D2); darts already flying finish.

### Assault (§2.10)

Every target point goes through `_clamp_into_view()`: `EnemyWorld.view_rect().grow(-(view_margin 60 + VIEW_CLAMP_PAD 8))`. The 8 px pad keeps the hull
itself inside `grow(-60)`: `Steering.orbit`'s 60 px/s correction floor makes a body parked on its point wobble ±2.6 px. `view_clamp_bound` reports
whether the last clamp moved its point. An `EngagementBudget(engage_seconds 9.0)`; at expiry **DISENGAGE** (the corvette's exit: release the
corridor, `exit_speed` 300, curve toward the nearest edge of the projectile world rect at `min(max_turn_rate, acceleration / exit_speed)`, free
once strictly outside). A TELEGRAPH is cancelled on the expiry tick; a PULSE finishes its window (the lock hook still fires), then DISENGAGE. **Measured exit:** worst 5.67 s over `corridor_starts()` at [230, 10] px/s (2166
runs, 0 capped), through `PH9.hacker_exit()` only (`tests/helpers/ph9_exit_keys.gd`). Never in an ENEMIES_CLEARED section
(`test_engagement_deadline.gd`).

### Hub idle

Open Space, not `start_engaged`: an `AnchorIdle` round `patrol_anchor` (`perceive_radius` 760, `lose_radius` 1600, `notice_time` 0.35,
`home_radius` = `idle_radius` 160) runs ahead of the phase dispatch and never interrupts a TELEGRAPH / PULSE.
- **IDLE:** a ring of `idle_radius` 160 round the anchor, lopsided like its arc: `idle_speed` 0.45 rad/s the ccw way, 0.45 · 0.18 / 0.30 = 0.27 the cw way.
- **NOTICING:** stop, face the player; after `notice_time` -> HOLD_ARC.
- **RETURNING:** beyond `lose_radius`: `arrive` at the anchor, then IDLE.

### The Hijack Pulse (§2.11, t9)

- **When:** from HOLD_ARC (after the arc's request, never on a tick BREAK_OFF was entered) once the pulse cooldown has run out, the player is within
  `pulse_trigger_range` 870 (inclusive) and in sight, and in Assault fewer than `assault_pulses_per_life` 1 pulses have gone. The cooldown counts down in
  every phase: `first_pulse_delay` 2.0 at the start (and again on NOTICING), then `pulse_period_min..max` 6–8 s from the brain's rng after every PULSE
  or cancel. **Line of sight is the Ph6 rule:** only asteroids and wrecks block it, never an enemy body (so hiding the Hacker behind other enemies does
  not work in Ph9). It is cast only on the physics step; a hand-ticked test counts the line as clear (the `LaserTenderBrain` precedent).
- **TELEGRAPH** (`pulse_telegraph` 0.9 s): yellow light, the dish unfolding, a ring of 6 yellow dashes closing from r 60 to 40 round the hull. **Any
  damage cancels it** (`watch_health`: a decrease of `Health.current_health`; a repair does not), and so do an EMP, a lost player and the Assault budget's
  expiry (straight to DISENGAGE). A cancel draws a fresh cooldown.
- **PULSE** (`pulse_seconds` 1.6 s, entered on TELEGRAPH's last tick): white light, the dish open, a white-amber ripple from the dish every 0.4 s.
  Every tick (ticks 0..95) a dart goes to each rocket in `SeekingOrdnance.eligible(tree, hull, hijack_range 650)` (nearest first; claimable only:
  not already claimed, not done, not inside a lit jammer) that no live dart is already after and that is in sight, while this pulse's darts are under
  `max_claims_per_pulse` 3. **The cap counts darts** (deviation D1): a dart that misses still used its slot. Rockets already in flight are picked up on
  the first tick, rockets launched during the window on the tick after they appear. Warheads are never eligible; primary fire is never touched.
- **The dart** (`HijackPulse`, `assault/scenes/projectiles/hijack_pulse/`): a `Node2D` with **no collision areas**, launched from the hull centre (not
  the dish), homing exactly on its rocket at `speed` 900 px/s; within `claim_radius` 16 px it calls `rocket.retarget(player, -1.0, hacker)` (the
  rocket's own `hijack_seconds` window, t4) and expires on the same tick. The rocket draws the tether, not the dart. A freed / refusing rocket or a
  freed Hacker ends it unclaimed; a `ProjectileLifetime` (1.6 s / 1400 px / the Assault world rect) is the backstop, so a rocket 650 px out
  receding at 500 px/s outruns it (the dart expires 23 px short on tick 94). A 6 px white-amber diamond and a 3-dot fading trail, code-drawn.
- **PULSE end:** a fresh cooldown, then HOLD_ARC (DISENGAGE when the budget ran out during the window). **The Disruptor hook:** if `pulse_lock_seconds
  > 0` and the player is within `pulse_trigger_range` and in sight, `HackerFrigate.lock_player_abilities(pulse_lock_seconds)` calls the player's
  `apply_ability_lock(seconds, hacker)`. It is 0.0 on this ship (it never locks); t10's Disruptor sets 1.5. At the end, not the start, so a lock never
  stops the player launching into its own hijack.
- **Killing it** frees its darts (the pool has no `persist_after_owner_death`) and fizzles every rocket it claimed (t4: a claimed rocket fizzles
  the tick after its source is freed).
- **What it threatens, measured** (the t9 owner question). With t4's hijack tuning (380 px/s, 1.6 rad/s, 2.5 s, armed at 0.25 s and 60 px) a salvo
  that a still or strafing player fires at the Hacker is claimed heading away and fizzles before it can come back: closest approach ≈ 236–241 px
  (Open Space) and ≈ 161–166 px (Assault), no blast. The blast lands on a player whose claimed rockets were already heading back at them from
  ≥ 225 px (rockets locked on an enemy behind the player as they pass the Hacker), or who flies after their own rockets (sometimes: it hangs on a few
  degrees and tens of px). A player moving off the line at cruise speed and turning dodges a claimed salvo heading at them (closest ≈ 235 px Open
  Space, ≈ 150 px Assault); a still one takes one 18-point blast (the 0.5 s i-frames refuse the other two).

| Pulse field | Value | Meaning |
|---|---|---|
| `pulse_trigger_range` | 870 | The player's distance for TELEGRAPH and the lock hook: `preferred_range + range_drift + 60`, so the whole held band of both modes is inside |
| `hijack_range` | 650 | Rocket-claim reach round the hull |
| `max_claims_per_pulse` | 3 | Darts per PULSE |
| `pulse_telegraph` / `pulse_seconds` | 0.9 / 1.6 | The charge and the window (s) |
| `pulse_period_min` / `pulse_period_max` | 6.0 / 8.0 | The cooldown after a PULSE or a cancel (s) |
| `first_pulse_delay` | 2.0 | The cooldown at the start and on NOTICING (s) |
| `assault_pulses_per_life` | 1 | The only value that can bind: the earliest second TELEGRAPH (2.0 + 0.9 + 1.6 + 6.0 = 10.5 s) is past the 9.0 s budget |
| `pulse_lock_seconds` | 0.0 | The Disruptor hook (t10: 1.5) |

The dart's own tuning is on `hijack_pulse.tscn` (`speed` 900, `claim_radius` 16, lifetime 1.6 s / 1400 px; 1400 / 900 = 1.56 s fits, the round
lifetime sweep's row).

### Test seams

`force_orbit_direction(dir)` (±1; a cone still overrides it while inside), `orbit_angle()`, `orbit_speed(dir)`, `held_range()`, `in_cone`,
`cone_kind`, `view_clamp_bound`, `break_offs`, `start_engaged`, `patrol_anchor`. The pulse (read-only): `pulse_cooldown`, `pulses_fired`, `telegraphs`,
`telegraph_cancels`, `darts_fired`, `claims_this_pulse`, `live_darts()`; on the ship `dart_pool()`, `dish_open()`, `tell_kind()`, `charge_ring_radius()`,
`ripple_count()`. **A long movement row must switch the pulse off** (`first_pulse_delay = 1000`, as `test_hacker_frigate.gd::_spawn()` does).

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
break-off and life inside `view_rect().grow(-60)` (the life row with its real pulse), the measured exit and its memo / hook / source-sweep rows, hub
idle and notice at 760 px, the tow refusal of TELEGRAPH / PULSE, the budget expiry in TELEGRAPH and suspension. `tests/integration/test_hijack_pulse.gd`
(both harnesses; the line-of-sight and real-blast rows on real physics at 8x): the dart and pool structure, launch from the hull centre and the
claim tick, refused / freed / jammed rockets, in-flight and newly launched claims, the receding-rocket limit, the cap, no darts outside PULSE,
the 869 / 871 px trigger and 649 / 651 px claim reach, the cadence, the Disruptor hook (1.0 s test config: 60 ticks), the jammer, line of sight
(an enemy body never blocks, a wreck does; a bullet cancels the charge), source death, the tell, warheads, primary fire bit-identical, one pulse
per Assault life, EMP, fairness on both real player scenes and the arc through the window. `test_enemy_bullet_lifetime.gd` has the dart's row.
Roster gates: `test_enemy_contact_damage.gd`, `test_contact_hitbox_geometry.gd`, `test_enemy_hurtbox_geometry.gd`,
`test_base_enemy.gd` (tow table: TELEGRAPH / PULSE refuse), `test_enemy_dual_mode.gd` (hazard profile, closes to its range in both modes),
`test_engagement_deadline.gd` (no ENEMIES_CLEARED section), plus the automatic sweeps.
