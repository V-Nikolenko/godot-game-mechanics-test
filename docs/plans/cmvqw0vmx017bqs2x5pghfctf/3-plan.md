# t2 — Enemy lasers exist as a real weapon: `EnemyBeam`, `EnergyHitScan`, `EnemyBeamScenes`, three beam scenes

**Revision 2** answers the round-1 review (`4-review.md`): B1 (the real-frame cadence row runs at 4×, risk note rewritten with the measured numbers,
gate time re-estimated) and N1–N8 (cadence overrides and window, exact hand-ticked cadence, health headroom, `SaveSandbox`, the `Health` i-frame,
`cruise_speed()`, `BEAMS.md` notes, farthest-corner bounding radius).

Builds the epic plan's §2.1 / §2.2 / §2.3 (`docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md`, approved). This file is the task-level build plan: it fixes
the choices §2.1–§2.3 leave open and the order of work. It does not re-decide the design.

## Problem
Today only the level-1 `LaserRay` columns and the station boss have beams, and both are one-off: the ray is a one-hit kill on sprite animation timing,
the station's beam is boss code. No enemy can carry a laser. After this task a beam is a reusable weapon: a thin yellow warning line appears on the
exact path it will fire along, then a red/white beam hurts the player, the player's allies, asteroids and other enemies on that line — never the ships that
fired it — at a cadence the player's invincibility window can never swallow. Nothing in the game fires one yet (the turret tasks are the first owners).

## Design

### Files (all new, `assault/scenes/projectiles/enemy_beams/`)
| File | Content |
|---|---|
| `enemy_beam.gd` | `class_name EnemyBeam extends Node2D` |
| `energy_hit_scan.gd` | `class_name EnergyHitScan extends RefCounted`, static only |
| `enemy_beam_scenes.gd` | `class_name EnemyBeamScenes extends RefCounted`, static only |
| `beam.tscn`, `sweep_beam.tscn`, `lance.tscn` | Root `EnemyBeam`, script by path (no hand-typed uid), **every §2.1 table value authored explicitly** |
| `BEAMS.md` | Notes beside the scenes (owner contract, timeline, exports, friendly-fire rule, what t3/t5 add). Also states (review N7): the direct emit bypasses `HurtBox.accepted_damage_types` (a beam cuts a big asteroid that only takes ROCKET from player fire, as `BeamBehavior` and `LaserRay` already do), and a barrel-roll (`HurtBox.monitoring = false`) does not dodge a beam (the shape test reads shapes, not monitoring), as it already does not dodge `LaserRay` |
| `tests/integration/test_enemy_beams.gd` | The rows below |

### `EnemyBeam` (as §2.1, plus these fixed choices)
- Exports (script defaults = `beam.tscn` values): `kind`, `telegraph_seconds`, `commit_seconds`, `active_seconds`, `fade_seconds`, `ignite_grace`,
  `length`, `hit_half_width`, `draw_half_width`, `tip_grace_px`, `damage`, `rehit_interval`, `telegraph_width`, `sweep_arc_deg`, `sweep_rate`,
  `blocked_by_cover`, `registers_hazard`, `avoid_weight`, `hazard_pad`, `self_tick`. LANCE `rehit_interval = inf` in the `.tscn`.
- Clock: `_t` = seconds in the current phase, `_clock` = seconds since `start()` (the re-hit time base). `tick(delta)` adds `delta` to both, then
  advances phases in a loop (a large `delta` can cross several; each change emits `phase_changed` once) carrying the overshoot into the next phase
  (`_t = maxf(0, _t - duration)`), comparisons with `EPS = 1e-6` so 54 × (1/60) ends a 0.9 s telegraph on tick 54. `active_seconds` (or its
  override) `0` = held until `cancel()`.
- `start(telegraph_override := -1.0, active_override := -1.0)`: only from OFF / FADE (a call in TELEGRAPH / ACTIVE is ignored — beams never re-aim);
  latches the two durations, clears the re-hit table and the previous hit segment, emits `phase_changed(TELEGRAPH)`. `cancel()`: TELEGRAPH → OFF,
  ACTIVE → FADE, else no-op.
- `is_lethal()`: ACTIVE, `_t + EPS >= ignite_grace`, not strained. `is_committed()`: TELEGRAPH, `commit_seconds > 0` and
  `telegraph − _t <= commit_seconds + EPS` (generic; only the LANCE ships a non-zero commit).
- Geometry: emitter kinds from `global_position` along `Vector2.RIGHT.rotated(global_rotation)`; hit segment `[0, length − tip_grace_px]`. TWIN
  (built by t5) uses `set_endpoints(a, b)` and trims `tip_grace_px` at both ends; the code path exists so the declared API is real, but no scene uses it
  in this task. `hit_segments()` returns `[PackedVector2Array([a, b])]` while lethal, else `[]` (t5 adds cover clipping).
- Declared for t5, minimal here: `set_endpoints(a, b)` stores the endpoints; `set_strained(on)` stores the flag and `is_lethal()` honours it (the flicker
  drawing is t5's); `hazard_info()` returns `null` (no scene in this task has `registers_hazard`); `blocked_by_cover` is an export with no cast yet.
- Hit scan, each tick while lethal (after the phase advance): band = `RectangleShape2D(hit_len, 2·hit_half_width)` at the segment midpoint, rotated
  to it; plus, when the previous tick was also lethal, the swept triangles `(a0, b0, b1)` and `(a0, b1, a1)` as `ConvexPolygonShape2D`s, each skipped
  when its doubled area < 1e-3 (the emitter origin is shared, so the second one is degenerate for a pure rotation). Candidates from
  `EnergyHitScan.candidates(tree)`, minus `is_exempt`, minus a broad phase, then `hits_band` against the band and each triangle; a hit target within
  its re-hit window is skipped; otherwise `deliver()` and emit `target_hit(target, damage)`. The previous segment is reset whenever the beam is not lethal.
- Broad phase (a refinement of §2.2's "+200 px"): skip a target whose centre is farther than `hit_half_width + EnergyHitScan.bounding_radius(target)`
  from the swept region (the segment, or the quad of the previous and current segments). Same cost class, never wrong for a large hurtbox.
- Drawing: three code-built `Line2D` children built in `_ready()` (`Telegraph`, `Glow`, `Core`), `antialiased = false`, `top_level = true`, points in
  global space from the drawn segment (emitter to the full `length`; the hit segment is shorter by `tip_grace_px`). TELEGRAPH: only `Telegraph`,
  width `telegraph_width`, `Color(1.0, 0.85, 0.3, 0.55)`, white while `is_committed()`. ACTIVE / FADE: `Glow` (faction red, width `2·draw_half_width·s`)
  and `Core` (white-hot, width `hit_half_width·s`), `s` easing in over `ignite_grace` and out over `fade_seconds`. OFF: all hidden. Redrawn at the end of
  every `tick()` and on `start()` / `cancel()`.
- `_physics_process(delta)`: `if self_tick: tick(delta)`; `set_physics_process(self_tick)` in `_ready()` so an owner-driven beam has no process at all.

### `EnergyHitScan` (static, as §2.2)
`candidates(tree) -> Array[Node2D]` (groups `player`, `allies`, `enemies`, `asteroids`, de-duplicated, skipping queued-for-deletion);
`is_exempt(target, host, owner_group) -> bool`; `hits_band(band: Shape2D, band_xform: Transform2D, target: Node2D) -> bool` over every enabled
`CollisionShape2D` under `Hazards.hurt_box_of(target)` (`cs.global_transform`, so node scale and rotation count); `bounding_radius(target) -> float`
(max over those shapes of `|shape origin − target centre| + the farthest corner of shape.get_rect() from the shape origin × max |scale|`,
so an off-centre polygon is never under-estimated; review N8); `deliver(target, damage) -> bool`. A target with no hurtbox (the harness's fake player)
answers `hits_band` false and `bounding_radius` 0 and is never delivered to.

### `EnemyBeamScenes`
`scene_for(kind: EnemyBeam.Kind) -> PackedScene` (null for TWIN until t5), `export_of(kind, property, fallback, node_path := ^".")` and a public
`export_of_scene(scene, property, fallback, node_path := ^".")` that `export_of` calls — so a gate's boundary case runs the same predicate on a
synthetic `PackedScene` (an instance with one value changed, re-`pack()`ed). Fallbacks passed by the gates are the script defaults
(`Script.get_property_default_value`), never typed numbers.

## Build sequence
1. `test_enemy_beams.gd` with every row below (red: the classes do not exist).
2. `energy_hit_scan.gd`, `enemy_beam.gd`, `enemy_beam_scenes.gd`, the three `.tscn` files. Import, run the file until green in both harnesses.
3. `BEAMS.md`; `DECISIONS.md` "Phase 8, built in t2"; `tests/README.md` → Gate time row; `updating-project-docs` (new component family:
   `global.md`/`assault.md` module docs, `PROJECT.md` conventions line, CLAUDE.md test list entry).
4. `scripts/check-test-leaks.sh` (the cadence rows await), `scripts/gate-time.sh` after, `bash /agent/verify.sh`.

## Test plan (`tests/integration/test_enemy_beams.gd`; hand-ticked at `DT = 1/60` unless marked; "both" = `use_parameters(["open_space", "assault"])`)
Fixtures: `fixture_enemy.tscn` + 14 px circle on its `HurtBox` + group `enemies`, all at runtime; host = a fixture at the emitter.
Every number below is read from the scenes (`EnemyBeamScenes.export_of`, player scene instances), never typed.

§2.1
- `test_timeline_phases_and_lethality` (both): not hit after `n_tel − 1` ticks; ACTIVE after `n_tel`; not hit after `n_tel + n_ign − 1`; hit after
  `n_tel + n_ign`; not hit during FADE / OFF (a second, fresh fixture placed on the line once ACTIVE ends, so the re-hit table cannot be what spares it);
  `phase_changed` once per change with one `int` (TELEGRAPH, ACTIVE, FADE, OFF in order).
- `test_cancel_in_telegraph_goes_off_with_no_hits_and_in_active_goes_fade` (both).
- `test_rehit_cadence_over_two_seconds` (both): BEAM started with `start(-1, 0.0)` (held: `beam.tscn`'s own ACTIVE is 1.2 s, too short; review N1);
  the window starts on the first lethal tick and runs `round(2.0 / DT)` ticks; **exactly** `floor(2.0 / rehit_interval) + 1` hits, consecutive hits
  exactly `ceil(rehit_interval / DT − EPS)` ticks apart (33 today; review N2 — hand-ticked is deterministic, so no ± 1). LANCE: a fixture held on the
  line for the whole ACTIVE is hit exactly once.
- `test_telegraph_width_is_at_least_3_and_drawn` (both): every built scene ≥ 3 and the `Telegraph` `Line2D.width` equals it during TELEGRAPH;
  boundary: a synthetic copy at 2 px fails the same predicate.
- `test_swept_hit_between_two_ticks` (both): a rotation step that leaves the 14 px fixture outside **both** tick bands (asserted with
  `hits_band` directly — so only the swept triangles can hit it) is hit. *Deviation note:* §2.1 suggests "the tip jumps 40 px per tick"; at the
  beam's 676 px hit length a 40 px tip jump leaves at most a 19 px half-gap, inside the 12 + 14 = 26 px band reach, so that rate would not need the
  swept test at all. The row uses a 0.2 rad step (140 px tip jump) and proves the band-miss precondition instead.
- `test_tip_grace` (both): hurtbox edge 1 px beyond `length − tip_grace_px` not hit; 1 px inside hit.
- `test_width_plus_minus_one_px` (both): edge at `hit_half_width + 1` not hit, at `hit_half_width − 1` hit.
- `test_exact_rectangle_wing_crosses` (both): 96 × 44 rectangle, centre 40 px off, rotated 90° → hit; control unrotated → not hit.
- `test_export_table_read_through_export_of` : for every built kind and every table export, `export_of` equals a fresh instance's value.
§2.2
- `test_victims` (both): fixture enemy, asteroid, the real player scene of that mode (shield zeroed), the real ally fighter (Assault) are each hit for
  `damage`; `target_hit` fires once per delivered hit.
- `test_owner_set_is_exempt` (both): host and an `owner_group` member untouched; control: an identical fixture outside the group is hit.
- `test_plated_ram_takes_no_health_damage` (both): the hit is delivered (`target_hit`), health unchanged.
- `test_sustained_shield_is_bypassed` (both): full damage to health, shield points unchanged.
- `test_ordnance_is_never_hit` (both): a live `EnemyMine` and `EnemyRocket` on the line: no `received_damage`, still live.
- `test_beam_kill_scores` (both): a fixture at `damage` HP is killed, `was_killed == true`.
- `test_rehit_interval_exceeds_player_invincibility` (static): every built scene's `rehit_interval` > every i-frame window of both player scenes:
  `PlayerBase.invincibility_sec`, and `HealthComponent.invincibility_time_in_sec` when that component's `invincibility_frames_enabled` (off in both
  scenes today; review N5); boundary: a synthetic `beam.tscn` copy at 0.5 fails.
- `test_player_cadence_on_real_frames` (both, real physics at **4×** — review B1, see Risks; `_Ticker`): the real player of that mode (shield zeroed,
  `max_health` / `current_health` raised to `10 × damage` so a "+1" hit can never reach the death path; review N3) held on a `beam.tscn` line,
  `start(0.0, 0.0)` (no telegraph: the row is about ACTIVE; held, then `cancel()`ed by the ticker `round(2.0 / DT)` ticks after the first lethal tick;
  review N1). It loses health in `floor(2.0 / rehit_interval) + 1` ± 1 steps of `damage` (the epic's tolerance, for the real-frame boundary tick),
  **and** delivered hits (`target_hit` on the player) == health-loss steps: no hit refused by i-frames. `SaveSandbox` `capture()` / `restore()` in
  `before_all` / `after_all` (real player scenes run `SessionState.apply_to`; review N4, the `test_enemy_rockets.gd` pattern).
§2.3 (each with a failing synthetic boundary run through the same predicate)
- `test_fairness_static_beams`: BEAM and SWEEP `telegraph_seconds ≥ R + (hit_half_width + r_p) / v_c`; boundary: telegraph just below.
- `test_fairness_sweep_tip_never_outruns_the_player`: `sweep_rate × length ≤ v_c`; boundary: rate pushing it 1 px/s over.
- `test_fairness_lance_commit_and_reaction`: `commit ≥ 0.5`, `telegraph − commit ≥ R`; boundaries: commit 0.45; telegraph − commit 0.2.
`R = 0.25` and the 0.5 s reactable floor are rule constants (§2.3). Both player scenes are instantiated off-tree (no `_ready()`; transforms compose
without an engine error, checked by the review): `r_p` = the larger of the two hurtboxes' circumscribed radii about the body origin (from local
transforms: 14.5 px for the fighter), `v_c` = `minf` of both instances' `cruise_speed()` (360 today: the fighter's `MovementStateMachine/MoveState.move_speed`;
the ship's `max_speed` 420; review N6).

## Risks
- **I-frame `Timer` vs physics clock (review B1, measured):** the player's 0.5 s timer runs on idle frames, and headless Godot sleeps ~6.9 ms per idle
  frame (`low_processor_usage_mode_sleep_usec`), so at 8× an idle frame spans ~0.055 game-s (median 3, max 7 physics steps) — wider than the
  0.05 s margin — and the reviewer's probe refused 4 of 110 re-hits per run (≈ 1 failing run in 5 for this row). At 4× (median 2, max 3 steps,
  0.028 s) and 2× it refused 0 of 110. So the cadence row runs at **4×** (`_SPEEDUP_CADENCE = 4`, its own `_scale_clock(4)`), per `tests/README.md`
  → Gate time rule 1 (a row whose tolerance is tighter than one idle frame stays at a lower multiplier). The epic's "8×" was a gate-time choice; the
  change is logged in `DECISIONS.md`.
- **Gate time** (+2.0 s): the hand-ticked rows cost milliseconds each (~0.3 s together with scene instancing); the two cadence rows ≈ 2.1 s game each
  at 4× ≈ 0.55 s real each, ≈ 1.1 s plus setup. Estimated ≈ 1.5 s, inside the allotment; if it is not, share one player scenario, never go back to 8×.
- `test_project_load_integrity.gd` instantiates every new scene: the beam must build its lines in `_ready()` without warnings.

## Out of scope (other tasks)
`twin_beam.tscn`, cover clipping, strain flicker, laser-wall hazard registration (t5); `EnergyRing` (t3); `HazardInfo` segments (t4); any owner
(turrets t6+). `LaserRay`, `StationLaserPhase` and their tests are not touched.
