# t13 — the Sniper's relocation cycle (task `cmuyk2qq0008loa2xqwco8raj`)

**Revision 2** (answers `4-review.md` round 1; the changes are listed in "Response to review round 1" at the end).

Builds epic plan `docs/plans/cmufs7ele0015nm2xvag3vrwc/3-plan.md` (Revision 2) §2.5 "Cycle", "Firing-point selection",
"Rail round"/`RailTrail`, the sniper row of §2.9.4, and the t13 row of §4. Context: `1-context.md`. The epic plan is
approved, so this plan only pins down what that text leaves open, and names the tests. Plan-review findings that
name this task are applied: **N3** (the attack-in-budget spawn offsets come from the live level-1 rows, so the far
(±120, −500) spawns are included) and **N9** (the attack-in-budget harness stays local to `test_sniper.gd`).

## Problem

Today an AI Sniper (the t12 shell) flies to the nearest point on its range ring and just sits there; it never aims,
never fires, and never moves again. Rail snipers in level 1 still use the legacy telegraph and are not touched here.

After this task an AI Sniper (Open Space, and Assault once t21/t22 take level 1 off rails) plays a readable loop:
it backs off, slides to a fresh firing angle *around* the player (never the same bearing twice in a row, never across
the player), stops dead, unfolds its barrel and shows a dim tracking line, then a bright locked line (white light —
the player's dodge window), fires a near-instant rail round that leaves a fading trail, and breaks away again. If a
rock stands between it and the player at the moment it would fire, it does not fire. In Assault it leaves when its
budget runs out, but never in the middle of an aim it has already shown — it finishes the shot first.

## Design

### Phases (`SniperBrain.Phase`, enum unchanged)

```
ENTER → SETTLE → AIM → LOCK → FIRE → BREAK_CONTACT → RELOCATE → SETTLE → …
            ↘ LOS blocked at SETTLE end / at the LOCK → FIRE tick → BREAK_CONTACT (no shot)
DECOY is reserved for t14 and never entered here.
```

**Deviation from the epic's diagram (`ENTER → BREAK_CONTACT → RELOCATE → SETTLE`):** ENTER *is* the seek to the first
firing point (the epic's own ENTER text), so it hands straight to SETTLE; a break before any shot has nothing to break
from. Logged in DECISIONS.

All phase changes go through `enter_phase()`, which keeps emitting `phase_changed(new_phase: int)`. Light: OFF
everywhere except AIM (CHARGING) and LOCK (COMMIT). Telegraph line: hidden everywhere except AIM (dim) and LOCK
(bright).

**Player model.** Each tick reads `TargetInfo.player(tree)` and keeps `v̄`, an exponential moving average of the
player's velocity with τ = `velocity_smoothing` (new field, 0.3 s, the Bomber's value); the first sample seeds it.
The **player frame** `f` = `v̄.normalized()` if `|v̄| ≥ frame_speed` (new field, 60), else `target.facing`, else UP.
A point's **bearing** = `f.angle_to(point − P)` (signed). `Δbearing(a, b) = |angle_difference(a, b)|`.

**ENTER.** On the first tick with a target, `choose_firing_point()` (below). With no previous bearing the separation
term is 0 and no tier applies, so it returns the **nearest legal candidate**. If nothing is legal, fall back to the
t12 `nearest_firing_point()`. `mover.arrive(point, relocate_speed)` with the existing arrival latch (`arrive_radius`
12); on arrival → SETTLE. `arrived` stays a public flag.

**SETTLE.** Request zero velocity, `face_toward(P)`. Once `velocity.length() < settle_epsilon` (2 px/s): re-check LOS
from the muzzle to the player (`TargetInfo.line_of_sight(muzzle, space, [actor RID])`): clear → AIM, blocked →
BREAK_CONTACT (counted in `refusals`). A `SETTLE_CAP` constant (1.5 s, far above the ≈ 0.37 s it takes to brake from
260 px/s at 700 px/s²) sends a sniper that somehow never settles to BREAK_CONTACT, so the loop cannot stall.

**AIM** (`aim_seconds` 1.3). Zero velocity. On entry the tracked direction `aim_dir` = muzzle → P. Every tick:
`want = intercept(muzzle, rail_speed).point` (the **full** intercept, R4.24); `aim_dir =
Steering.turn_toward(aim_dir, want − muzzle, aim_track_rate, delta)` (2 rad/s, never overshoots); `aim_point =
muzzle + aim_dir · |want − muzzle|`; `face_toward(aim_point)`; `telegraph.show_line(aim_point, false)`. Barrel
unfolds over `barrel_unfold_seconds` (new, 0.4) with an ease-out. LOCK is entered **on the same tick** as the last AIM
computation, so `lock_point` is that tick's aim (the lock-point row reads the intercept on that tick, no lag).

**LOCK** (`lock_seconds` 0.5). On entry `lock_point = aim_point` and `lock_origin = muzzle` are frozen
(`telegraph.show_line(lock_point, true)`, COMMIT). Zero velocity, `face_toward(lock_point)`. On the tick
`lock_seconds` is reached, LOS is re-checked on **both** lines: muzzle → player (as SETTLE) **and** muzzle →
`lock_point` (the line the round will fly; for a moving player the two differ). Either blocked → **refusal**: no round
is acquired, the light drops to OFF, the barrel folds, and the sniper goes to BREAK_CONTACT (or DISENGAGE if the budget
is pending). Both clear → FIRE.

**FIRE** (entered and left in one tick). `RailPool.acquire(muzzle)`, `set_direction(lock_point − muzzle)`, `speed =
rail_speed`, `HitBox.damage = rail_damage` (set from the private config, not left to the scene). Spawn a `RailTrail`
into the round's container. `shots_fired += 1`; `last_bearing` = the bearing of the actor's actual position in the
current player frame, `has_last_bearing = true`. Barrel starts folding (`barrel_fold_seconds` new, 0.3). Then
DISENGAGE if the budget is pending, else BREAK_CONTACT. A null `acquire()` (exhausted pool) is treated like a
refusal (no trail, no bearing).

**BREAK_CONTACT.** On entry `side` is fixed: the side of the player's line (`f` through `P`) the sniper is already on —
`s = sign(away.orthogonal() · (away − f·(away·f)))`, `+1` when that is 0 — so the lateral share never cuts across the
player's nose. Each tick: `v = Steering.break_contact(pos, P, v̄, side, break_speed)`, made corridor-safe (below),
`mover.request_velocity(v)`.
- **Clock.** `_break_time` counts from entry and is never reset; `_phase_time` is the retry clock.
- **Hold.** Once `_break_time ≥ break_min` and `d ≥ range + range_jitter` (past the far edge of the candidate band) the
  request is zero: a sniper that cannot find a point waits instead of flying off.
- **End.** When `_break_time ≥ break_min` and (`d ≥ 0.9 · range` or `_phase_time ≥ break_cap`):
  `choose_firing_point()`; a point → RELOCATE; nothing legal → `_phase_time = 0`, `_break_failed = true`, and it holds.
  Once a choice has failed, the distance clause no longer applies: it retries only after each further `break_cap`
  (the epic's "hold BREAK_CONTACT for another `break_cap`, then retry"), so a held sniper casts at most
  `max_los_rays` rays per `break_cap`.
- **`break_min` (new, 1.0 s) is a deviation the epic text does not state.** After FIRE the sniper is already at its
  firing range, so "until `d ≥ 0.9 · range`" would end BREAK_CONTACT on its first tick and RELOCATE would start at
  once — which contradicts the §4 post-shot row ("distance non-decreasing on every tick of the 1.0 s after FIRE").
  `break_contact` always has a positive radial component, and `EnemyMover.step` moves the velocity vector by
  `move_toward` toward a radial-positive request from rest, so the distance cannot shrink while it lasts.
- **Corridor-safe (Assault only, `mover.constraint != null`).** The corridor pushes an enemy that leaves its visible
  rect back in, at up to 200 px/s, which can be *toward* the player. So per axis, the outward direction is **blocked**
  when the room to that edge of `constraint.inner_rect()` is ≤ `s² / (2 · a_axis) + EDGE_KEEP (16 px)`, with
  `s = max(break_speed, |velocity_axis|)` (the most the rescaled request can be) and `a_axis = 0.5 · acceleration`.
  `EnemyMover.step` steps the whole velocity **vector** (`move_toward`), so one axis slows by only its share of the
  rate; the half is an assumption, and `EDGE_KEEP` plus taking `s` at full `break_speed` are the margin (worst case
  the reviewer computed: 146 px stopping against a 213 px threshold). Blocked outward components are zeroed. If what is
  left points toward the player (negative radial component) it is negated — the sniper slides along the wall the other
  way — and blocked components are zeroed again. The result is rescaled to `break_speed`, or zero in a corner. Open
  Space never runs this.

**RELOCATE.** `mover.arrive(point, relocate_speed)`. Within `arrive_radius` → SETTLE. Past the **travel cap** →
re-pick (keeping `last_bearing`). The travel cap is set with the point: `max(relocate_cap, travel / relocate_speed +
1 s)`. **Deviation:** a flat 4 s cap re-picks mid-route on most Open Space relocations (a 120–150° relocation at the
900 px range is a 1500–1800 px trip, ≈ 6–7 s), so the sniper would rarely reach the point it chose; the cap still
drops a point the player has left behind. Both ends of a relocation lie inside the visible rect in Assault (the
firing point inside `grow(−fire_margin)`, the break's end inside the visible rect by the corridor-safe rule), so the
straight path does too: the corridor's pressure never acts on it.

**`choose_firing_point() -> Vector2`** (`Vector2.INF` when nothing is legal). Public, and it records
`last_candidates` (an array of `{point, bearing, delta, tier, travel, score, rect_ok, cone_ok, path_ok, los}`; `los` is
`null` when no ray was spent on it), `last_choice_fallback: bool` and `last_los_rays: int` for the tests.
1. Candidates: the seven seeds ±60°, ±90°, ±135°, 180° relative to `f`, each with an rng jitter of ±`seed_jitter`
   (new, 15°), plus `random_candidates` (new, 3) uniform bearings; range = mode range ± mode jitter (rng).
2. Filters before scoring:
   - Assault: `inner_rect().grow(−fire_margin).has_point(point)`;
   - **path clearance (new, review finding 1):** the straight segment from the sniper to the point never passes closer
     to P than `min(pass_clearance_ratio · range, |sniper − P|)` (`pass_clearance_ratio` new, 0.45; the `min` lets a
     sniper that starts close in still leave);
   - forward cone: rejected if `|v̄| ≥ forward_cone_speed` (new, 200) and `|bearing| < forward_cone` (30°).
3. Tiers (only with a previous bearing): **A** `Δ ≥ min_bearing_change + BEARING_SLACK` (5°), **B** `Δ ≥
   min_bearing_change` (45°), **C** the rest. With no previous bearing every survivor is tier C and no fallback is
   reported.
   - **Why A exists (deviation, logged):** the bearing is chosen for the *point*, but the shot is fired from where
     the sniper actually settles (up to ~2° away at 680 px: the 12 px latch plus the braking overshoot). A point
     picked at exactly 45.1° could be fired from at 44°, failing the §4 row on the measured bearings. Tier A keeps a
     5° margin when the geometry allows; tier B is exactly the epic's hard rule; tier C is the epic's documented
     fallback, taken only when no candidate reaches 45°.
4. Score within a tier: `w_sep · clamp(Δ / 180°, 0, 1) − w_travel · travel / (2 · range)` (the epic's weights,
   unchanged).
5. LOS in rank order (tier, then score): the first candidate whose `LineOfSight.clear(candidate → P)` is true wins.
   At most `max_los_rays` (new, 6) rays; past the cap, or out of candidates → `Vector2.INF`.
6. `last_choice_fallback = has_last_bearing and winner.tier == C`; when true a verbose-gated line prints it (C15).

**Why 0.45 and not the reviewer's 0.6.** In Assault (range 680) the legal candidates for a player near the bottom of
the corridor lie round ±60° (the ±90° seeds fall outside the rect), and the chord between the two sides passes
`680 · cos 60° = 340 px` from the player. 0.6 (408 px) would forbid that crossing over the top of the player, leaving
only same-side moves (corrected in round 2: it would not push every choice into the fallback, but it would stop the
sniper ever switching sides there); 0.45 (306 px Assault, 405 px Open Space) still forbids every path through or near the
player (the 180° and 150–165° chords pass at 0–250 px) and caps a relocation at ≈ 127° of arc.

**Assault budget.** Unchanged clock. On expiry (acted on once): in AIM or LOCK set `disengage_pending` (the shot or the
refusal ends it); anywhere else → DISENGAGE at once (unchanged exit). The deferral is at most `aim_seconds +
lock_seconds` (1.8 s).

**Barrel** (placeholder until t15). The brain keeps `barrel_open` ∈ [0, 1], moved toward its target at
`1 / barrel_unfold_seconds` or `1 / barrel_fold_seconds`; the displayed `scale.y = lerp(BARREL_FOLDED (0.35), 1,
ease_out(barrel_open))`, and the barrel's position slides so its base (the +y end, nearest the hull) stays put. The
brain reads the barrel's unfolded position and texture height once, at its first tick, and applies the folded pose
then. No `rotation` is written anywhere (`test_no_sniper_script_writes_rotation`).

### `RailTrail` (new, `assault/scenes/projectiles/enemy_bullet/rounds/rail_trail.gd`)

`class_name RailTrail extends Line2D`, code-built (no texture, so the sprite-transparency gate is unaffected),
width 2, a pale red-white colour.
- `static func spawn(round_: Node2D, origin: Vector2, fade_seconds: float) -> RailTrail`: built and added to
  `round_.get_parent()` (the pool's container), starts **following**.
- Following: connects `round_.expired` **one-shot** to `_on_round_expired` (which takes the end point at that moment —
  the pool's recycle is deferred, so the round is still where it hit); keeps `weakref(round_)` only for the
  owner-death case (`BulletPool.cancel_active()` frees a round without emitting `expired`). `step(delta)` (called from
  `_physics_process`, and by tests) sets the far end to the round's position.
- On `expired`, an invalid weakref or a round queued for deletion it stops reading the round (a recycled round is
  still valid, parked in its pool), and **fades** `modulate.a` to 0 over `fade_seconds` on its own counter (no
  `Timer`, no `create_timer`), then `queue_free()`s itself. It owns itself; nothing else frees it.
- The rail fallback (`SniperTelegraph._fire_rail_shot`) is today's shot and gets no trail.

### Config fields added (flat; all [judgement] defaults)

`velocity_smoothing` 0.3, `frame_speed` 60, `forward_cone_speed` 200, `seed_jitter` 15, `random_candidates` 3,
`max_los_rays` 6, `pass_clearance_ratio` 0.45, `break_min` 1.0, `barrel_unfold_seconds` 0.4, `barrel_fold_seconds`
0.3. `.tres` unchanged (the defaults are the values). `trail_fade` (0.4) already exists.

### Scene / wiring

`sniper.gd::_apply_config` also hands the brain `muzzle`, `pool` and `barrel`. No scene node changes.

### Rejected alternatives

- Ending BREAK_CONTACT purely on distance (epic text): fails the post-shot row (above).
- Recording `last_bearing` from the chosen point instead of the real position: the rows measure real positions.
- Clamping the break request to the rect instead of zeroing the outward axis early: the mover's own acceleration
  still carries the ship over the edge into the corridor's pressure band.
- A `Timer`/tween for the trail fade or barrel: forbidden (brain clock, GUT `simulate`).
- Routing RELOCATE round the player through a ring waypoint (review alternative): more state and longer trips for the
  same guarantee the clearance filter gives.
- Re-weighting the score so travel beats separation (review alternative): changes the epic's approved weights.
- A reach filter (`travel ≤ relocate_speed · relocate_cap`) instead of the per-trip cap: tried; with the coarse seeds
  (60/90/135° ± 15°) at the 900 px Open Space range it left no ≥ 45° candidate on a typical cycle (measured 39° and
  25° changes).

## Build sequence

1. Config fields + `sniper.gd` wiring. (Compile check.)
2. `RailTrail` + its tests.
3. `choose_firing_point()` + its tests (nearest-first, tiers, corner fallback, forward cone, path clearance, LOS cap).
4. The cycle: SETTLE, AIM, LOCK (refusal), FIRE, BREAK_CONTACT (+ side rule, corridor-safe, hold), RELOCATE (+ travel
   cap), ENTER change, budget deferral, barrel. Dual cycle tests.
5. Update the t12 tests that pinned "ENTER is the only phase" / "holds still 8 s in" / "holds inside the grown rect".
6. Attack-in-budget row.
7. `REPO=/workspaces bash /agent/verify.sh`, `scripts/check-test-leaks.sh`.
8. Docs: `sniper/ENEMY.md`, `docs/architecture/modules/assault.md` (RailTrail), `docs/enemy-roster.md` if it describes
   the cycle, `DECISIONS.md` Ph4 lines (via `updating-project-docs`).

## Test plan (`tests/integration/test_sniper.gd`, appended; "dual" = `use_parameters(["open_space", "assault"])`)

Hand-ticked with a fixed `DT` as today; every brain is seeded (`rng_seed`) and the Assault budget is lifted
(`engage_seconds` 1000, set on the private config **before the first tick**, when `_start()` builds the budget) in every
multi-cycle case. Each round a test sees is recycled the way an expiry does (`expired.emit()` then `pool._recycle()`), so
the two-round pool never runs dry. Every asteroid fixture is a `StaticBody2D` on its default layer 1 (`ENVIRONMENT`,
part of `LineOfSight.BLOCK_MASK` — keep it there) in group `asteroids`, and every LOS case awaits a physics frame after
adding or removing one.

| Case | Asserts |
|---|---|
| `test_the_first_point_is_the_nearest_legal_candidate` (dual) | ENTER's point == the filter-passing candidate with the least travel; its ray was clear; `last_choice_fallback` false; 7 + `random_candidates` candidates. |
| `test_consecutive_firing_bearings_differ_by_45_degrees` (dual) | Stationary player; 4 shots; the 3 consecutive differences of the measured fire bearings (player frame) are ≥ 45°; from the first shot on, the sniper is never closer than `pass_clearance_ratio · range` (− 1 px). |
| `test_no_relocation_path_passes_through_the_player` (OS) | Sniper 1000 px out at bearing 0, `last_bearing` 0, 20 seeded choices: every chosen path's closest approach ≥ the clearance; some candidate was refused for its path. Fails with `pass_clearance_ratio` 0 (checked). |
| `test_corner_takes_the_fallback_only_when_no_45_degree_candidate_exists` (Assault) | Player at (1300, 1020), the corridor's bottom-right corner; `last_bearing` −45° (the middle of the ≈ 80° legal arc) and 0° (its edge). Each time: the point is inside `inner_rect().grow(−fire_margin)`; `last_choice_fallback == not any(candidate legal and Δ ≥ 45°)`; the middle takes the fallback and the edge does not. **Boundary.** |
| `test_the_forward_cone_is_empty_for_a_fast_player` (OS) | Sniper ahead of a 300 px/s player, `random_candidates` 40 so in-cone candidates exist: at least one candidate has \|bearing\| < 30°, every such one has `cone_ok == false` and every other `true`, and no chosen point is in the cone; at 100 px/s every candidate is `cone_ok`. Fails with the filter removed (checked). |
| `test_an_enclosed_player_spends_at_most_six_rays_and_holds_break_contact` (OS) | Player inside a 220 px asteroid: `choose_firing_point()` returns INF with `last_los_rays == 6`; a sniper put in BREAK_CONTACT 860 px out stays there for 3 · `break_cap`, never gets farther than one `break_min` of breaking plus braking, and ends still. **Boundary.** |
| `test_the_sniper_is_still_from_settle_end_to_the_shot` (dual) | `|v| < 2` every tick and drift < 1 px from AIM entry to the shot. |
| `test_after_the_shot_the_sniper_opens_the_range` (dual) | Stationary player, 1.0 s after FIRE: distance non-decreasing every tick; strictly greater at 0.25 s and 1.0 s; `v · (P − x) ≤ 0` every tick. |
| `test_break_contact_never_crosses_the_players_line` (dual) | Player at 200 px/s along x; the sniper breaks from above the line and from below it: the signed distance from the line keeps its sign, never shrinks, and grows by > 150 px (with the side flipped it grows ≈ 50 px — checked). |
| `test_assault_break_contact_stays_inside_the_corridor` (Assault) | Three setups — breaking outward at the top edge, a remainder toward the player that must be turned round, a corner: every tick inside `inner_rect()`, range non-decreasing, `v · (P − x) ≤ 0`; the corner one stays within 8 px, the others open the range. Fails with the corridor-safe step removed (checked). **Boundary.** |
| `test_commit_is_shown_only_in_lock_and_the_barrel_unfolds` (dual) | Over two whole cycles: COMMIT ⇔ LOCK; CHARGING only in AIM; the bright line ⇔ LOCK; barrel `scale.y` == 1.0 in LOCK and < 0.5 in RELOCATE. |
| `test_the_lock_point_is_the_full_intercept` (dual) | Player at constant (120, 0) px/s: on the LOCK-entry tick `lock_point ≈ TargetInfo.intercept(lock_origin, rail_speed).point` (≤ 2 px) and > 10 px ahead of the player; the round flies along `lock_point − muzzle` at `rail_speed` for `rail_damage`. |
| `test_a_rock_on_the_line_refuses_the_shot` (dual) | A rock dropped on the line during AIM: no round acquired, one refusal, LOCK → BREAK_CONTACT, the light not COMMIT; the rock removed → the next cycle fires. **Boundary.** |
| `test_a_fighter_body_on_the_line_does_not_block` (dual) | A `CharacterBody2D` on `ENVIRONMENT` at the same spot: the round is fired, no refusal. |
| `test_a_rock_at_settle_end_sends_it_back_to_break_contact` (dual) | A rock dropped near the player on the new point's line when the relocating sniper is 100 px from its point: it never enters AIM or shows CHARGING, SETTLE → BREAK_CONTACT, one refusal, no shot. |
| `test_the_trail_stops_on_the_rounds_expired_and_fades` (dual) | After FIRE a `RailTrail` is in the round's container and follows it; `expired` + the recycle (the round still valid, parked in its pool) stop it at the expiry point even when the parked round moves; it frees itself within `ceil(trail_fade / DT) + 2` ticks. |
| `test_the_trail_fades_when_the_owner_dies` (OS) | `cancel_active()` frees the round without `expired`: the trail stops and frees itself within the same bound. |
| `test_budget_expiry_in_aim_defers_disengage_to_the_shot` (Assault) | Expiry 0.2 s into AIM: AIM/LOCK until the shot, one round fired, DISENGAGE on the FIRE tick, deferral ≤ 1.8 s. **Boundary.** |
| `test_budget_expiry_in_relocate_disengages_on_that_tick` (Assault) | Expiry in RELOCATE → DISENGAGE on that tick. |
| `test_a_refusal_resolves_a_budget_expired_in_lock` (Assault) | Expiry in LOCK, then a rock on the line: the refusal hands over to DISENGAGE, no round, `disengage_pending` cleared. **Boundary.** |
| `test_every_level1_sniper_spawn_class_aims_inside_its_budget` | Every distinct sniper offset in the live `Level1Director._build_sections()` (formations expanded; the far (±120, −500) rows asserted present; top / bottom / side classes asserted present), rails and delays stripped, spawned through a real `WaveManager` under a real `ArenaCamera`. One run with all of them and the stub at the camera centre, continued until every sniper has left (prints time to AIM, budget left and shots per life); then **one run per offset** with the stub 200 px past the centre, away from that spawn (`−offset.normalized() · 200`). Each sniper enters AIM with `budget.remaining() > 0`. Each run's world is freed before the next, so `TargetInfo.player()` only ever sees that run's stub. |
| `test_the_attack_in_budget_row_can_fail` | The same row with `relocate_speed` 20 and `max_speed` 20 on one top spawn: AIM is never reached, and it disengages. **Boundary.** |
| t12 updates | `test_enter_seeks_…_open_space` → hands over to SETTLE on the ring band (range ± jitter), on its own side; `test_enter_in_assault_…` → stops at AIM and asserts the point inside the grown rect and the sniper within the latch plus braking of it; `test_enemy_dual_mode.gd::test_sniper_enter_comes_to_rest_…` → runs to AIM entry and asserts `arrived` and `|v| < 2` there. |

The two t12 cases that now fire without recycling (`test_assault_disengage_…`, `test_open_space_has_no_budget_…`) may
log a pool-exhausted `push_warning`; GUT does not count warnings as failures, and the cases do not assert on rounds.

Gates that must stay green: contact damage, contact geometry, hurtbox geometry, config isolation (new fields flat),
single writer (empty allowlist), signal arity, sprite transparency, UID, project load, suite integrity; and
`scripts/check-test-leaks.sh` (the trail uses no timers; the attack-in-budget row spawns with no delay, so
`WaveManager` creates no timer).

## Risks

- **LOS from hand-ticked tests.** `intersect_ray` is legal outside the physics flush; t2's tests already cast from
  test code. Bodies need one physics frame before a ray sees them — every LOS case awaits one.
- **Pool exhaustion in long hand-ticked runs**: rounds never move without physics frames; the tests recycle each
  round as an expiry would.
- **Many snipers in one WaveManager run** are ENVIRONMENT-layer bodies, so they show up on each other's rays; they
  are not blockers (opt-in) and cost at most 4 recasts.
- **Physics-process re-enable at `_ready`**: the row disables each spawned sniper's physics tick from its `ready`
  signal (Godot turns it on in `NOTIFICATION_READY`, before the signal).
- **Feel**: 1.0 s break, 5° slack, 0.45 clearance, the travel cap and the corridor slide are judgement values; nobody
  has played it. Open Space relocations of up to ≈ 127° of arc take several seconds.

## Out of scope

The decoy (t14), the sprite and the moving muzzle (t15), the hub idle (t19), level-1 migration and its deadline rows
(t21/t22). Rail snipers keep the legacy telegraph with no trail.

## Response to review round 1

| Finding | Resolution |
|---|---|
| 1 (blocking) RELOCATE flies past the player | Path-clearance filter (`pass_clearance_ratio` 0.45, reasoning above), plus `test_no_relocation_path_passes_through_the_player` (fails with the filter off — checked) and the closest-approach assertion in the 4-shot row. Corner boundary re-checked with the filter in `_legal`. Also found while building it: the flat 4 s relocate cap re-picked most Open Space relocations mid-route → per-trip travel cap (deviation, above). |
| 2 (blocking) corridor-safe untested | `test_assault_break_contact_stays_inside_the_corridor` with the three setups (fails with the step removed — checked). The threshold is now taken at full `break_speed` (a first version checked the pre-rescale component and let the corner case leak 12 px — the new test caught it). The vector-step wording is corrected. |
| 3 (blocking) side rule untested | `test_break_contact_never_crosses_the_players_line` (dual; fails with the side flipped — checked). |
| 4 (blocking) forward cone can pass with the filter deleted | Rewritten with 40 random candidates, in-cone presence asserted, every flag checked (fails with the filter removed — checked). |
| 5 t12 Assault ENTER test | Added to the update row. Pool-warning note added. |
| 6 Assault budget in the 4-shot row | Stated: `engage_seconds` raised on the private config before the first tick. |
| 7 ENTER → SETTLE | Stated as a deviation; logged in DECISIONS. |
| 8 hold rule | One rule: `_break_time` from entry (never reset) gates `break_min`; past `range + range_jitter` the request is zero. The enclosed-player row asserts the bound and the stop. |
| 9 precision points | Relocation-in-rect wording fixed; LOCK checks both the player line and the lock line; the lock point is frozen on the AIM tick it is computed; SETTLE-end refusal and LOCK-expiry-plus-refusal cases added; per-offset stub; asteroid layer stated. |
