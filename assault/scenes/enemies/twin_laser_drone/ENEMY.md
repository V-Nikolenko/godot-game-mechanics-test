# Twin-Laser Drone — the two ends of a moving laser

**Role:** Two small drones act as one large weapon: they fly to opposite sides of the player, hold a laser of fixed length between them, show it as a
warning line, then fly the whole line through where the player was and past it (IDEAS §6.10, Attack A).
**Fantasy / threat:** A wall of light that closes on you. Each drone is fragile; the threat is the line, and the line is only as strong as its weaker end.

> **Build state (Phase 8, t12).** Built: the drone scene and shell, the flat config, the `TwinLaserPair` rig (bind, owner group, leader-only phase clock,
> slots, latched frame, identical per-drone boosts, strain and collapse, the beam on drone A), `TwinLaserDroneBrain` (the full append-only `Phase` enum; FORM /
> TELEGRAPH / ADVANCE / BREAK / WAIT / SOLO / DISENGAGE played), Attack A in Open Space, the Assault rig (corridor-planned frames, one attack per life with the
> deferral bound), the `TwinLaserPairSpawn` spawner and `WaveBuilder.twin_laser_pair()`. **Attack B (t13):** the rig's `LAUNCHED` phase (appended) and the fixed launched
> frame, played when a Laser Tender launches a pair (`../laser_tender/ENEMY.md`); a SOLO drone with a live tender flies home and docks. **Hub idle and measured exit (t14):** the rig's `IDLE` phase (appended),
> the brains' IDLE / NOTICING / RETURNING, a recalled launched pair docking, and the Assault exit measured over `corridor_starts()` (below). **Not yet:** the art (t16: the hull is a code-drawn placeholder), hub and level-1 placement (t18 / t19). Plan: `docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md` §2.12;
> task plan `docs/plans/cmvqw0vnw018jqs2x5k4l6ahb/3-plan.md`. The beam itself is `twin_beam.tscn` (`assault/scenes/projectiles/enemy_beams/BEAMS.md`).

---

## Stats

| Property | Value |
|---|---|
| HP | 30 (`twin_laser_drone_config.tres`): one Standard or Sniper shot, two Spread pellets, three Gatling rounds |
| Damage | 8 contact (`ContactHitBox`, `ContactProfile` COLLISION); the beam deals its own (`twin_beam.tscn`: 12 per hit, re-hit 0.55 s) |
| Speed | `max_speed` 300, `acceleration` 900; ADVANCE `advance_speed` 240 (a boost); BREAK `break_speed` 260; DISENGAGE `exit_speed` 420 |
| Body | one `CircleShape2D` r 13 shared by the body (layer 1 / mask 1, so it stops on a wreck), the `HurtBox` and the `ContactHitBox` |
| Lens | `StateLight` at (0, 6), forward of the nose-down hull: CHARGING while the beam warns, ARMED while it burns, OFF otherwise |
| Sprite | placeholder, code-drawn in `_draw()` (dark r 13 disc, rim, lens dot); hit flash animates `.:self_modulate`. t16 replaces it |
| Scene / config | `twin_laser_drone.tscn` / `twin_laser_drone_config.tres` (flat `TwinLaserDroneConfig`) |
| Hazards | `hazard_avoidance` 0.6, `hazard_margin` 16, `hazard_resistance` 0.1 (they are the well-bait); `wreck_chance` 0; score 30; `counts_as_escape` true |
| Rig (group "Rig") | `rig_length` L 420, `length_tolerance` 16, `strain_seconds` 0.15, `standoff` 260, `overshoot` 200, `slot_tolerance` 24, `form_timeout` 3.0, `break_seconds` 1.2, `attack_period_min..max` 4.0..6.0 (Open Space) |
| Assault | `engage_seconds` 8.0 (one attack per life) |

Every value is a plan §2.21 *starting value* (judgement, not play-tested).

---

## The rig: `TwinLaserPair`

A `RefCounted` board both brains hold (the `SquadController` precedent). `TwinLaserPair.bind(a, b, controller = null)`:
- puts both drones (and the controller, if any) in `owner_group` = `&"twin_pair_<rig instance id>"`, so the beam never hurts its own pair or its tender;
- instantiates `twin_beam.tscn` as `TwinBeam`, a **child of drone A**, `setup(A, owner_group)` — one owner at every instant: A's death frees it with A;
- sets each brain's `pair` (duck-typed through the `Brain` child: the rig never names the drone or brain classes) and connects each drone's `died` and `tree_exiting`.

**Frame:** `centre`, `axis` u (unit, A → B), `normal` n (unit, from the player toward the line; the line advances along −n). `slot_of(A) = centre − u·L/2`,
`slot_of(B) = centre + u·L/2`. `separation_error() = | |A − B| − L |`.

**One clock:** `tick(delta, caller)` is a no-op unless `caller == leader()` (A while it lives, else B), so **phase transitions happen only in the leader's
tick**; each brain mirrors the rig phase and applies its own motion. `Phase { FORM, TELEGRAPH, ADVANCE, BREAK, COLLAPSED, WAIT }` (append-only; WAIT is the one
addition to §2.12's five, so both drones re-FORM on the same tick). `tick_beam(delta, caller)` (drone A only, every phase) feeds the beam its endpoints and strain
and ticks it, so a cancelled beam always fades out.

## Behaviour (Attack A)

- **FORM** — Open Space: n = (mid(A, B) − P).normalized(), taken outright on the first frame of every FORM (after an advance the drones are past the
  player) and then turned at most 90°/s (`FRAME_TURN_RATE`); `centre = P + n·standoff`; u = ±n.orthogonal(), signed so A takes
  the nearer slot (kept unless the drones are clearly crossed, by more than `slot_tolerance`). Each drone `arrive`s at its slot at `max_speed` plus the player's
  velocity as feed-forward (`add_nudge`), facing its partner. Both within `slot_tolerance` of their slots and `separation_error() ≤ length_tolerance` → TELEGRAPH;
  after `form_timeout` → BREAK (retry later).
- **TELEGRAPH** (refuses a tow) — the frame is **latched** (the shown line is the line that advances, `latched_player` = P); the drones hold their slots; the beam
  telegraphs for its `telegraph_seconds` 0.8 (yellow line on the exact path, lenses CHARGING). The rig moves on when the beam itself goes ACTIVE (one clock).
- **ADVANCE** (committed, refuses a tow) — both drones `mover.boost(−n, advance_speed, delta)` every tick (renewed per step, so a phase change stops it the next
  step; boost skips avoidance but keeps hazard drift and the corridor) for `advance_distance / advance_speed` = (260 + 200) / 240 = 1.92 s; the beam is lethal
  from its `ignite_grace` 0.1 s on and sweeps through the latched point.
- **BREAK** — beam `cancel()`; the drones separate along ±u at `break_speed` for `break_seconds`; then **WAIT** (Open Space) for a fresh period drawn from the
  leader's `rng` in `attack_period_min..max`, holding where BREAK left it, then FORM again. In Assault BREAK is only reached before the life's one attack (a
  FORM timeout or no corridor fit) and is followed by FORM.
- **Strain and collapse** — in TELEGRAPH and ADVANCE, `separation_error() > length_tolerance` strains the beam (`set_strained(true)`: never lethal, flickering);
  strained continuously for `strain_seconds` → COLLAPSED (`collapsed(true)`), then the survivors BREAK and re-FORM. Back inside the tolerance sooner → unstrained.
- **Kill one drone** — its `died` (or `tree_exiting`) breaks the pair for good **in the same call**: the beam is cancelled at once (A's death frees it with A; B's
  death leaves A to fade it), `collapsed(false)`. The survivor is **SOLO**: it can never relight the beam. Open Space: it `arrive`s at the controller if one is live,
  else it circles `patrol_anchor` alone on its `idle_radius` ring (t14). A tender takes it back (`LaserTender.dock()`) once it is within `dock_radius`. Assault: DISENGAGE.
- **Rails** — `on_suspended()` releases the drone from the rig (the pair breaks; a suspended drone A frees the beam, since nobody would tick its fade).

## Attack B: launched by a Laser Tender (t13)

`LaserTender.launch_pair(points)` binds the pair with the tender as `controller` and calls `TwinLaserPair.launch(point_a, point_b, speed, max_seconds)`:
- **LAUNCHED** (rig `Phase.LAUNCHED`, brain `Phase.LAUNCHED`; refuses a tow): each drone boosts straight from its cradle toward its own point at `launch_speed`
  for `min(|Q - start| / launch_speed, launch_max_seconds)`, renewed one step per tick; the last, partial step lands it on the point, the next tick stops it
  dead (a zero-speed boost: a boost keeps its speed), and the rig leaves LAUNCHED `LAUNCH_SETTLE_TICKS` 2 ticks after the longer boost. No strain check.
- **Fixed frame** (`frame_fixed`): `centre = mid(points)`, `u` from A's point to B's, `n` signed toward the line from the player. FORM keeps the frame (no
  player feed-forward); at the latch `n` is re-signed toward the latched player and the advance is `min((centre - P) · n, standoff) + overshoot` (Assault:
  also capped by the room in `inner_rect()` inset by `slot_tolerance`), so every advance is at most 1.92 s. `frame_fixed` is cleared on BREAK / COLLAPSED:
  the pair then runs ordinary Attack A cycles.

## Hub idle (t14; plan §2.14)

Open Space only, and only when the brain is not `start_engaged` (the Ph7 convention: behaviour rows set it to fight at once). Each brain of a standalone pair
(no controller) builds an `AnchorIdle` (config group "Idle": `perceive_radius` 650, `lose_radius` 1500, `notice_time` 0.35; `home_radius` = `idle_radius` +
`slot_tolerance`) round its `patrol_anchor`, which `TwinLaserPairSpawn` sets to its own position for both drones; **only the leader of an intact pair updates
it**, once a tick before the rig's tick (one clock).
- **IDLE** (rig `TwinLaserPair.Phase.IDLE`, appended): no frame, no strain, beam OFF. Both drones `orbit` the rig's `idle_anchor` at `idle_radius` 140 on
  opposite points (`idle_slot_angle()`: B at `idle_angle`, A at `+ PI`), the ring turning at `idle_speed` 0.5 rad/s.
- **NOTICING:** the leader within `perceive_radius` of the player: both drones stop, face it and blink their lens once (`StateLight.blink_once()`); after
  `notice_time` the rig `engage()`s -> FORM.
- **RETURNING:** the player past `lose_radius`: `stand_down(anchor)` (beam cancelled, frame unfixed), **never in a busy phase** (`is_busy()`: TELEGRAPH,
  ADVANCE, BREAK, COLLAPSED, LAUNCHED), so an attack already shown runs to the end of its BREAK first; the drones fly back to their ring points, then IDLE.
- **A launched pair** (a Laser Tender's) builds no `AnchorIdle`: its leader reads the controller's duck-typed `recalls_drones()` (true while the tender idles)
  and stands the rig down at the tender; both brains are RETURNING and `arrive` at it, and the tender docks them. A dead tender (or `recalls_drones()` false)
  re-engages the rig. A lone drone with no live controller circles its own anchor (SOLO).
- **The radius inequality** (asserted from config): the cycle's farthest drone–player distance `standoff + overshoot + L/2 + break_speed · break_seconds` =
  260 + 200 + 210 + 312 = 982 ≤ `lose_radius` 1500, so a pair mid-attack never loses its player.

## Assault (R8.18)

- **Frames are planned inside the corridor**, never clamped drone by drone: `TwinLaserPair.assault_frame(p, rect, …)` (pure) plans on the leader's
  `mover.constraint.inner_rect()` **inset by `slot_tolerance`**, so a drone within tolerance of a slot is inside `inner_rect()` and the constraint is the identity on both
  ends for the whole attack. Horizontal (preferred): the line `standoff` above the player, advancing down (n = UP), centre clamped along x so the whole line is inside.
  When the room above the player is < `standoff` (with `slot_tolerance` hysteresis once vertical): a vertical line beside the player on the roomier side, advancing
  across (n = ±RIGHT). The overshoot is clamped to the room past the player. Neither fits (or the rect is shorter than L along the line) → BREAK.
- **One attack per life:** the `EngagementBudget` (`engage_seconds` 8.0, counted from the drone's spawn) and `advances_started` decide; once an ADVANCE has started
  (finished or collapsed), or the budget runs out, both drones DISENGAGE — **except in TELEGRAPH or ADVANCE**: a budget expiring there lets the attack finish
  (deferral bound: DISENGAGE starts no later than `engage_seconds + telegraph_seconds + max_advance_seconds + 2 ticks` after spawn).
- **DISENGAGE:** `pair.release()`, `mover.release_constraint()`, `mover.max_speed = exit_speed`, exit along −n (the way the line was going; with no frame, the heading);
  freed outside `EnemyWorld.projectile_world_rect()` (strict compares). One drone disengaging breaks the pair, so the other follows on its own tick. DISENGAGE
  reads the player nowhere.
- **Measured exit (t14):** `tests/helpers/ph8_exit_keys.gd::drone_exit()` runs `SpecialistExitProbe.worst_disengage()` over `corridor_starts()` (1083 runs at
  10 px/s): worst **5.37 s** (from (−720, −720) heading down-right), plus `drone_reversal_seconds()` 0.463 s for a framed drone carrying `max_speed` against its
  exit = **5.83 s** (`drone_exit_bound()`), under 10 s.

## Spawning

`TwinLaserPairSpawn` (`twin_laser_pair_spawn.tscn`; not an enemy, never scored: `counts_toward_wave_clear` / `counts_as_escape` false, `score_value` 0) defers
`spawn_pair()` (public and idempotent): two drones as siblings in its parent (A first, so A leads on real physics) at ∓`rig_length / 2` along its local X, brains
seeded `rng_seed` / `rng_seed + 1` when non-zero, bound with `TwinLaserPair.bind()`, announced with `EventBus.enemy_spawned_orphan`, then it frees itself.
Spawn with `b.twin_laser_pair().at(x, y)` (the pair's midpoint, camera-relative). **Never in an `ENEMIES_CLEARED` section** (`test_engagement_deadline.gd`).

## Counterplay (IDEAS §6.10)

- **Move round an end:** the wall is slower than the player (240 < 360 px/s) and the player can reach an end before it arrives — the §2.3 twin row in
  `test_enemy_beams.gd`: `(L/2)/v_c + R = 0.83 s ≤ telegraph + standoff/advance_speed = 1.88 s`.
- **Destroy one drone:** 30 HP; the beam drops in the same call.
- **Bait into terrain or a gravity well:** a well's drift applies during the boost and a wreck stops a drone's body; either strains the line past
  `length_tolerance` and collapses it.
- **Use the beam on the formation:** the beam hurts every `player` / `allies` / `enemies` / `asteroids` target on its line except its own pair and controller.

## Design checklist (IDEAS §43)

| Question | Answer |
|---|---|
| Unique silhouette | Two small identical discs always 420 px apart with a line between them; never seen alone while attacking (final art t16) |
| Preferred distance | The line forms `standoff` 260 px from the player |
| Movement signature | Paired, mirrored: both slide into slots on either side of the player, then advance in lock-step |
| How it attacks | A held twin beam swept through the player's latched position |
| Player behind it | The frame is built from the player's bearing every FORM tick, so there is no "behind": the line re-forms round the player |
| Player boosts away | FORM follows (feed-forward of the player's velocity) until `form_timeout` 3 s, then BREAK and retry; a latched line never re-aims |
| Off-screen | Open Space needs no camera; the frame is world-space |
| Retreat / reposition | BREAK + WAIT between attacks (Open Space); DISENGAGE after its one attack (Assault) |
| Telegraph | 0.8 s yellow line on the exact path, both lenses CHARGING; red when lethal |
| Destroying it changes the encounter | Killing either drone deletes the whole wall; the survivor is harmless (SOLO) |
| Open Space without camera coordinates | Yes (both harnesses) |
| Assault, constrained | Yes: corridor-planned frames, horizontal from above or vertical from the side |
| Sprite communicates state | The lens light (CHARGING / ARMED / OFF); art t16 |
| Armour / shields / weak points | None: fragility is the counterplay |
| Works alone | No, by design: a lone drone is SOLO and cannot attack |
| Better combined | Yes: the line herds the player into other enemies' fire, and its friendly fire punishes enemies caught on it; t13's tender launches pairs |
| Deterministic tests | Yes: hand-ticked rows in both harnesses; the wreck row on real physics at 8× |

## Gates

`tests/integration/test_twin_laser_drones.gd` (INTENT, both harnesses): structure, config, the enum pins, the spawner, a source sweep proving the rig and spawner write no motion (the single-writer gate's matchers through any receiver); Attack A keeps its length on every TELEGRAPH /
ADVANCE tick against a standing and a 200 px/s stub (R8.24), the latch, killing A / killing B, the well strain with its no-well control (and the survivors' motion the tick after a kill or a collapse: out of the boost), friendly fire, the
leader clock, the death hook (`_gone`), a rail taking over either drone; the Assault frame planner, the inner-rect and vertical-rig rows, one attack per life (Open Space repeats), the budget deferral and its FORM-expiry boundary, `form_timeout` -> BREAK with no beam, a strain collapse in TELEGRAPH that BREAKs and re-FORMs without spending the attack;
the wreck row on real physics at 8× (read at the collapse) and its no-wreck control; the `WaveBuilder` row through a real `WaveManager`. Also: the twin / moving-wall fairness row in `test_enemy_beams.gd`; the
drone is in the rosters of `test_enemy_hurtbox_geometry.gd`, `test_contact_hitbox_geometry.gd`, `test_enemy_contact_damage.gd` and `test_wreck.gd`
(`_SHIP_SCENES`); `test_base_enemy.gd` (roster 19, authored COLLISION, the tow table: TELEGRAPH / ADVANCE / LAUNCHED); `test_enemy_dual_mode.gd`
(`test_twin_laser_drones_form_and_telegraph_in_both_modes`, the hazard-profile row); `test_engagement_deadline.gd` (no `ENEMIES_CLEARED` section holds a pair).
Hub idle (t14, `test_twin_laser_drones.gd`): the Idle config and the radius inequality (with a failing boundary), idle vs Assault vs `start_engaged`, a 30 s
orbit within `idle_radius + 8` with the beam OFF, notice at 649 / not at 651, RETURNING beyond 1500 (not at 1499), an attack in ADVANCE finishing before the
stand-down, a lone drone circling its anchor. The measured exit is `test_laser_tender.gd`'s (printed and < 10 s, memoised once, the stub trick, the reversal term).

## Files

```
twin_laser_drone/
├── ENEMY.md                      ← this file
├── twin_laser_drone.tscn / .gd   TwinLaserDrone (BaseEnemy shell)
├── twin_laser_drone_brain.gd     TwinLaserDroneBrain
├── twin_laser_pair.gd            TwinLaserPair (the rig, RefCounted)
├── twin_laser_pair_spawn.tscn / .gd   TwinLaserPairSpawn (wave / hub spawner)
└── twin_laser_drone_config.gd / .tres  TwinLaserDroneConfig (flat)
```
