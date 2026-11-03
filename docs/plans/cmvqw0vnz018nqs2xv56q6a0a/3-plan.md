# t13 — Laser Tender and Attack B: V-launch into a moving wall

Epic `cmug23ona0015m52w4t1m73bc` (Phase 8), plan task t13. Builds epic plan §2.13 on t12's rig (§2.12), with §2.3 and §2.19 (approved). This task plan
does not redesign them; it fixes what §2.13 leaves open (how a launched pair enters the rig, the launched frame and its advance, the tender's motion and
phase rules, docking, the Assault hold band, file and scene layout, test geometry). Where it says "§2.x", the epic plan wins. Context: `1-context.md`.
Baseline: `scripts/gate-time.sh` GUT `Time` **206.547 s**, 2546 tests (`7926c8e`).

**Revised after review round 1 (`4-review.md`):** B1 the V row covers the moving geometries; an end-on wall cannot give a 20° V with straight
non-crossing legs, so that row asserts the 20° rule on broadside geometries and "diverging, non-crossing, ends L apart" on end-on ones (logged); B2 row 13
pins the stub's motion both ways and row 7 asserts `n` from the sign rule at the latch, and the "wall lands behind a constant-velocity player, then chases"
consequence is logged; B3 the Assault APPROACH → HOLD trigger is the band (y only), with a spawn-from-above row against a strafing stub; B4 a real-physics
row at 8× with masks intact (exceptions, straight legs, real-step `add_child`). N1 shared recordings committed up front; N2 the advance cap logged as a
deviation; N3 docking covers every drone the tender launched; N4 public `rearm_cradles()`; N5 drone tuning read through `drone_scene`; N6 the tender brain
joins the any-receiver sweep; N7 stronger rows 6 / 7 / 10; N8 the hold point keeps clear of the player; N9 the seam's calling rule documented; N10 the
tender leaves a finished rig's owner group.

**Revised after review round 2:** R2-B1 row 5 checks the `L` separation on the latch tick (a capped leg ends short of its point at the end of
LAUNCHED); R2-B2 row 13b's point-rule boundary is read only before the stub's first reversal, with the stub starting at the left edge; R2-N1 gate trims
named; R2-N2 `dock()` text; R2-N3 the top-hugging-player case noted; R2-N4 noted.

**Revised after review round 3 (owner-authorised):** R2-B1 confirmed fixed; row 5's capped-leg clause is read on the LAUNCHED → FORM tick. R2-B2:
row 13b pins the tender's spawn at (1000, −200) and states the expected band time (≈ 3.0 s), reversal (≈ 3.97 s) and closest approach (≈ 111 px).

**As built (2026-11-03):** one change from this plan. A boost keeps its speed, so a drone boosting onto its point and then FORMing overshot
its slot by ≈ 90 px and strained the wall at the latch. LAUNCHED motion now boosts on every tick that starts before the leg's boost time (the
partial last step lands it), then stops dead on the next tick (a zero-speed boost); the rig leaves LAUNCHED `LAUNCH_SETTLE_TICKS` 2 ticks after
the longer boost (not on the tick the boost time is reached). A capped leg is therefore read on the last LAUNCHED tick (exactly 728 px), not
the LAUNCHED → FORM tick. Logged in `DECISIONS.md`. Rows 4 and 5 are one parameterised test (they share each launch); rows 7, 8, 9, 12 and 13
read memoised recordings.

## Problem

Today a Twin-Laser Drone pair can only form on the player from wherever it spawned (Attack A). Nothing launches drones, and nothing places a laser wall
where the player is *going*. After this task, a Laser Tender (a slow ≈ 96 px carrier with two drones docked in visible cradles) holds at range, its
cradles glow yellow for 0.6 s, and it launches both drones in a V toward two points either side of the player's predicted path. They land as a `|---|`
wall across the escape route, telegraph, and advance through the player as one wall of fixed length. The player escapes round an end, kills a drone, or
lures one into a well or a wreck (t12's counterplay, unchanged). The tender keeps one live pair at a time: while it lives it waits; once it is gone it
rearms for 7 s; a lone surviving drone flies home and docks. In Assault the tender enters from the top, sits in the upper band of the screen, launches
once (a vertical wall ahead of a strafing player, a horizontal one above a still player) and leaves.

## Design

### Files

New, `assault/scenes/enemies/laser_tender/`: `laser_tender.tscn`, `laser_tender.gd` (`LaserTender extends BaseEnemy`), `laser_tender_brain.gd`
(`LaserTenderBrain extends EnemyBrain`), `laser_tender_config.gd` (`LaserTenderConfig extends ShipConfig`, flat) + `laser_tender_config.tres`, `ENEMY.md`.
Edited: `twin_laser_pair.gd` (LAUNCHED + the launched frame), `twin_laser_drone_brain.gd` (LAUNCHED motion, no feed-forward on a launched frame),
`wave_builder.gd` (`LASER_TENDER`, `laser_tender()`), the §2.19 shared test files, `test_twin_laser_drones.gd` (the no-motion sweep gains
`laser_tender.gd`; one enum pin row updated), `test_engagement_deadline.gd`, docs.

Dependencies stay acyclic: the tender names the rig, the drone config class and its own brain / config; its brain names the tender, the rig and
`TwinLaserDroneBrain` (to read a returning drone's phase); the rig and the drone never name the tender (the rig keeps `controller: Node2D`).

### The ship (`laser_tender.tscn`, `LaserTender`)

Root `CharacterBody2D` `LaserTender` (layer 1 / mask 1). Children: `CollisionShape2D` (one `CircleShape2D` r 40, the `SubResource` shared by the next two),
`HurtBox` (layer 512, mask 65), `Health` (160), `HitFlashAnimationPlayer` (animates `.:self_modulate`, the drone's placeholder idiom), `ContactHitBox`
(layer 256, mask 0, `damage` 15, `damage_type` CONTACT, shared shape, scale 1), `ContactProfile` (mode COLLISION), `EnemyMover` (`constraint_mode`
AUTO), `Brain`, `StateLight` at (0, 10) (between the cradles: the cradle light), `CradleL` `Marker2D` at (−30, 10) and `CradleR` at (30, 10), each with a
child `DockedDrone` (`Polygon2D`, a textureless r 11 placeholder of a docked drone; t16 swaps in a sprite). Placeholder hull code-drawn in `_draw()` (a
dark r 40 disc, rim, two cradle notches). `sprite_forward_angle` stays `PI / 2`.

Script: `@export var config: LaserTenderConfig = load(...tres)`, `@export var drone_scene: PackedScene = load(twin_laser_drone.tscn)`. `_ready()`:
`super._ready()`, `add_to_group("enemies")`, `_apply_config` (health, score, contact damage, mover `max_speed` / `acceleration`, `brain.config`),
`_set_docked(2)`. Accessors: `brain()`, `state_light()`, `body_radius()`, `cradles() -> Array[Marker2D]` ([L, R]), `docked_count()`, `pair()` (the last
rig it launched, or null), `launches()`.

- **`launch_pair(points: PackedVector2Array) -> TwinLaserPair`** (the Ph10 / Ph11 seam): null when `points.size() < 2`, there is no parent or no drone
  scene. Instantiates drone A and B from `drone_scene`, places A at `CradleL`'s and B at `CradleR`'s global position (`parent.to_local`), seeds each
  brain's `rng_seed` from the tender brain's `rng` (`randi_range(1, 0x7FFFFFFF)`, never 0), adds a mutual collision exception with the tender (they start
  inside its r 40 body and dock into it), adds both to the tender's parent (A first, so A leads on real physics), `TwinLaserPair.bind(a, b, self)`,
  `rig.launch(points[0], points[1], config.launch_speed, config.launch_max_seconds)`, `_set_docked(0)`, `launches += 1`, then
  `EventBus.enemy_spawned_orphan` for each. Drone A takes `points[0]`: the caller orders the points (the brain's matching, below). **Added synchronously**,
  not deferred (deviation from §2.13's wording, logged): the only caller is the tender's brain tick on the physics step (never a physics callback, never a
  `_ready()`), where adding bodies is legal, and the hand-ticked rows see the drones at once. The doc comment states the seam's calling rule (review N9):
  call it on the physics step or from idle code, never from a physics callback (`area_entered` / `body_entered`), where a caller must `call_deferred` it.
  Every drone it launches is remembered in `_launched` (pruned of freed nodes) for docking (review N3). Before binding, if the previous rig's drones
  are all gone, the tender leaves that rig's `owner_group` (review N10; a live drone of it may still hold a fading beam, so the group is kept until then;
  only the previous rig is checked, so a rig with a live drone at the next launch keeps the tender in its group for good, which is harmless; R2-N4).
- **`dock(drone: Node2D) -> void`**: frees a returning drone (`queue_free()`) and counts it as docked (`_set_docked(min(docked + 1, 2))`, the next empty
  cradle's `DockedDrone` shown). Only the brain calls it, for a SOLO drone this tender launched (any rig, `launched_drones()`; review R2-N2).
- `rearm_cradles()`: the REARM end, `_set_docked(2)` (review N4: the brain never calls an underscore method).
- `_set_docked(n)`: `docked = n`, `CradleL/DockedDrone.visible = n >= 1`, `CradleR/DockedDrone.visible = n >= 2`.
- `launched_drones() -> Array[Node2D]`: the live drones it launched (any rig).
- `laser_tender.gd` writes no motion; it joins t12's any-receiver no-motion sweep.

### Config (`LaserTenderConfig`, flat; `.tres` = §2.13's starting values)

`ShipConfig` fields in the `.tres`: `max_health` 160, `collision_damage` 15, `score_value` 120, `hazard_avoidance` 0.8, `hazard_margin` 24,
`hazard_resistance` 0.3, `wreck_chance` 0.35, `wreck_size` 1 (medium). Own: Movement `max_speed` 200, `acceleration` 400; Launch `preferred_range` 650,
`launch_telegraph` 0.6, `launch_speed` 520, `launch_max_seconds` 1.4, `lead_time_max` 1.5, `rearm_seconds` 7.0, `assault_wall_lead` 180; Idle
`perceive_radius` 700, `lose_radius` 1600, `notice_time` 0.35, `idle_radius` 160, `idle_speed` 0.5 (declared for t14, unused here); Assault
`engage_seconds` 10.0, `exit_speed` 380. **Added** (each a number §2.13 states or implies, made data; logged): `standing_lead` 120 (the "facing · 120"
rule), `strafe_speed_min` 60 (the "|v.x| ≥ 60" rule), `range_tolerance` 80 (APPROACH → HOLD), `arc_rate` 0.12 rad/s (the broad arc), `dock_radius` 72
(touching distance 40 + 13, plus 19 px of reach), `assault_hold_depth` 140 (the Assault band: px below the view's top edge). `counts_as_escape` stays true.

### The rig: LAUNCHED and the launched frame (`twin_laser_pair.gd`)

- `enum Phase { FORM, TELEGRAPH, ADVANCE, BREAK, COLLAPSED, WAIT, LAUNCHED }` — **LAUNCHED appended** (append-only allows it; logged).
- New state: `frame_fixed: bool` (FORM does not re-derive the frame), `_launch_point`, `_launch_dir`, `_launch_seconds` (per side, A / B),
  `launch_speed`.
- **`launch(point_a, point_b, speed, max_seconds)`**: for each drone `start` = its position now, `dir = (point − start).normalized()`,
  `seconds = min(|point − start| / speed, max_seconds)` (§2.13); `has_frame = false`, `frame_fixed = false`, `_enter(LAUNCHED)`.
  Queries `launch_point_of(d)`, `launch_dir_of(d)`, `launch_seconds_of(d)`, `launch_speed`.
- **Leader tick, LAUNCHED**: no strain check. When `phase_time() + EPS ≥ max(launch seconds)` → `_fix_launched_frame()` → FORM. That sets
  `centre = mid(point_a, point_b)`, `axis = (point_b − point_a).normalized()` (u, A → B, so A's slot is `point_a`), `normal` = `axis.orthogonal()` signed
  toward the line from the player (`sign((centre − P) · ortho)`; within 1 px of the line, the sign is +1), `has_frame = true`, `frame_fixed = true`.
- **FORM on a fixed frame** (`_tick_form`): the frame is not updated (neither the Open Space follow nor the Assault planner); the slot / separation latch
  and `form_timeout` are unchanged. **At the latch** the normal is re-signed toward the line from the latched player (same rule; within 1 px it keeps the
  arrival sign) so the wall always advances at the player, and the advance distance is fixed:
  `advance_distance = min((centre − P) · n, standoff) + overshoot`, and in Assault `min(that, room)` where `room` is how far the centre can move along
  `−n` and stay inside `inner_rect().grow(−slot_tolerance)` (an axis-aligned wall, so both ends have the same room; the t12 inset rule). Capping the
  approach at `standoff` keeps every advance ≤ `(standoff + overshoot) / advance_speed` = 1.92 s, the §2.12 `max_advance_seconds`
  (`max(standoff 260, assault_wall_lead 180)` = 260), in both modes. **Deviation, logged (review N2):** §2.13 says "for |P − centre| + overshoot". The
  distance along the advance is the same thing when the player is on the normal; the `standoff` cap makes the advance *shorter* than §2.13's whenever
  the latched player is more than `standoff` from the line (a player that far away has escaped this wall; the pair re-forms with Attack A).
- **A consequence of §2.13's prediction horizon, logged (review B2):** `t = |P − tender| / launch_speed` covers the flight, not FORM or the 0.8 s
  telegraph, so a player who holds a constant velocity is already past the wall when it lights; the re-signed normal then makes the wall chase from
  behind (at 240 px/s against the player's own speed). A player who turns back, or slows, meets it: the wall cuts the route back, not the route ahead.
  The numbers are §2.13's starting values; t16 / t18 / t19 placement and tuning should know it.
- `frame_fixed` is cleared on BREAK / COLLAPSED entry, so the next FORM is an ordinary Attack A frame ("the pair continues with Attack A cycles").
- Everything else (TELEGRAPH latch, ADVANCE, strain, collapse, BREAK, WAIT, the Assault one-attack rule, kill handling) is t12's code, unchanged.

### The drone brain (`twin_laser_drone_brain.gd`)

- `_mirror`: rig LAUNCHED → `Phase.LAUNCHED` (a freshly launched drone's first tick enters it; `accepts_tow()` is already false there).
- LAUNCHED motion: while `pair.phase_time() <= launch_seconds_of(actor) + EPS`, `mover.boost(dir, s, delta)` (one step, renewed per tick, the t12 ADVANCE
  rule) with `s = clamp(((point − pos) · dir) / delta, 0, launch_speed)` (it stops on its point, no overshoot); after that `arrive(point, max_speed)`.
  No facing request while boosting (it faces its flight: the V reads), then `face_toward(partner)`.
- FORM on a fixed frame: `arrive(slot)` **without** the player-velocity nudge (the launched frame does not follow the player), facing the partner.
- Budgets are unchanged: an Assault drone's `EngagementBudget` starts on its first tick, i.e. at its launch (§2.12 "a launched drone: from its launch").

### The tender brain (`LaserTenderBrain`)

`enum Phase { APPROACH, HOLD, LAUNCH, WAIT, REARM, DISENGAGE, IDLE, NOTICING, RETURNING }` (append-only; IDLE / NOTICING / RETURNING are declared for t14
and request zero velocity here), `signal phase_changed(new_phase: int)`, `signal launched(pair: TwinLaserPair)` (emitted once per launch; test
handlers on it never capture the rig), `var config`, `var phase`, `var budget`, `var start_engaged := false` and
`var patrol_anchor := Vector2.INF` (t14 seams, as the drone's), `enter_phase(p)` (the one place a transition happens; works on a lone tender),
`accepts_tow()` false in LAUNCH, `on_suspended()` light OFF.

Each `tick(delta)`: first tick `_setup()` (budget, anchor, arc direction from `rng`). `expired = budget.update(delta)`: in LAUNCH → `_leave_after_launch =
true`; in any other phase but DISENGAGE → DISENGAGE (a budget that runs out before LAUNCH starts leaves without launching, §2.13). Then the dock check
(below), then by phase:
- **APPROACH** — Open Space: `arrive(P + (pos − P).normalized() · preferred_range)`, facing the player; `| |pos − P| − preferred_range | ≤ range_tolerance`
  → HOLD. Assault: `arrive(hold point)`; once in the band, `|pos.y − hold.y| ≤ HOLD_REACH` (24 px), and inside `EnemyWorld.view_rect()` → HOLD (review B3: the
  band, not the point, because `arrive` trails a hold point that tracks a strafing player's x by ≈ 50 px at 200 px/s and never catches one at 360).
- **HOLD** — the hold motion (below); `_can_launch()` → LAUNCH.
- **LAUNCH** — hold motion; light CHARGING; when `phase_time + EPS ≥ launch_telegraph` → `points = attack_b_points()`, `tender.launch_pair(points)`,
  `launched.emit(pair)`; then Assault or `_leave_after_launch` → DISENGAGE, else WAIT.
- **WAIT** — hold motion; when the last rig is no longer a live pair (`rig == null or not rig.is_intact()`) → REARM.
- **REARM** — hold motion; after `rearm_seconds` → `tender.rearm_cradles()` → HOLD (the docked pair is back).
- **DISENGAGE** — entry: `release_constraint()`, `max_speed = exit_speed`, exit direction = toward the nearest edge of `projectile_world_rect()` (axis-
  aligned, the corvette's idea written fresh; no rect → the heading); tick: free once strictly outside the rect, else `request_velocity(dir · exit_speed)`.
- `_can_launch()`: `docked_count() == 2`, no live pair, line of sight (`can_see_player()` on the physics step, assumed true off it — the turret's rule),
  and in Assault `launches() == 0` and the tender inside `EnemyWorld.view_rect()`.
- **Hold motion** — Open Space: a broad arc, `mover.orbit(P, preferred_range, arc_angle, max_speed)` with `arc_angle` synced to the bearing on entry and
  advancing `arc_rate · arc_dir · delta`, facing the player. Assault: `arrive(hold point)` facing the player, the **hold point** = `(clamp(P.x, r.x + 2R,
  r.end.x − 2R), clamp(view.position.y + assault_hold_depth, r.y + 2R, r.end.y − 2R))` with `r` = the mover's `constraint.inner_rect()`, `view` =
  `EnemyWorld.view_rect()`, `R` = body radius: the upper band of the visible part of the corridor, above the player; its y is also capped at
  `P.y − 2R − HOLD_CLEARANCE` (40 px) before the inner-rect clamp, so a player flying in the top band is not sat on (review N8). A player hugging
  the top of the corridor can therefore push the hold point above the view and hold off the launch until the budget ends; that is the §2.13 "budget
  runs out before LAUNCH" case, accepted and noted in `ENEMY.md` / `DECISIONS.md` (review R2-N3).
- **Dock check** (Open Space only, every tick, every phase but DISENGAGE): for each of `tender.launched_drones()` (every drone it launched, any rig;
  review N3), when the drone's brain is SOLO (its rig broke; it heads for its live controller, t12) and it is within `dock_radius` of the tender →
  `tender.dock(drone)`.
- Light: CHARGING in LAUNCH, OFF otherwise (set only on change).

**Attack B points (`attack_b_points() -> PackedVector2Array`, pure on a snapshot, public for rows).** `L = rig_length`, `standoff` and `slot_tolerance`
are the launched drone's tuning, read through the tender's `drone_scene` (review N5): `_setup()` instantiates it once, keeps its private config copy and
frees the probe, so a Ph10 / Ph11 caller that swaps `drone_scene` is planned with its own drone's numbers.
- Open Space: `t = min(lead_time_max, |P − tender| / launch_speed)`; moving (`|v| ≥ STANDING_SPEED` 20 px/s): `P̂ = P + v · t`, heading `h = v̂`;
  standing: `P̂ = P + facing · standing_lead`, `h = (P − tender)̂`. `u = h.orthogonal()`, `Q± = P̂ ± u · L/2`.
- Assault: `r = inner_rect().grow(−slot_tolerance)`. `|v.x| ≥ strafe_speed_min`: vertical wall `x = clamp(P.x + sign(v.x) · assault_wall_lead, r.x,
  r.end.x)`, `y = clamp(P.y, r.y + L/2, r.end.y − L/2)`, `Q± = (x, y ± L/2)`; else horizontal wall `x = clamp(P.x, r.x + L/2, r.end.x − L/2)`,
  `y = clamp(P.y − standoff, r.y, r.end.y)`, `Q± = (x ± L/2, y)` (`standoff` is the drone config's).
- **Order (the V never crosses):** points[0] goes to `CradleL`, points[1] to `CradleR`, choosing the assignment with the smaller total length
  `|CL − Q| + |CR − Q'|`. For two start / end pairs the shorter matching never crosses (if the segments crossed, swapping the ends would be strictly
  shorter by the triangle inequality), which is the property the rows check directly.
- **The V's opening angle is geometry, not a choice (review B1, logged).** The legs are straight and the matching never crosses, so the angle between
  them is roughly the angle the wall subtends from the tender. A wall broadside to the tender (a standing player; a player moving toward or away from
  it; the Assault still case) opens 35°–90°; a wall end-on to it (a player crossing the tender's bearing; the Assault strafe case with the tender above)
  opens only ≈ 10°–20°. §2.13's points and straight legs fix that; keeping a ≥ 20° V there would need the tender to manoeuvre for a broadside bearing
  before launching (a launch gate that can stall the one Assault launch). So the rows assert the 20° V on broadside geometries and, on every launch,
  that the legs diverge (never anti-parallel, never crossing, the drones end ≈ L apart from 60 px at the cradles).

**Assault life** (§2.13): the tender launches at most once; a budget that expires during LAUNCH lets that launch finish, so a pair is launched no later
than `spawn + engage_seconds + launch_telegraph + _TICK_SLACK`; the tender then DISENGAGEs (t14 measures the exit). The pair does its one attack and
DISENGAGEs (t12's rule; its advance ≤ 1.92 s, above).

### Alternatives rejected

- **Deferred launch (as worded in §2.13):** buys nothing on the physics step and makes every hand-ticked row await a frame; logged as a deviation.
- **A launched frame that keeps following the player in FORM:** that is Attack A; §2.13's wall must land "across the escape route" and stay there.
- **Launch to a point with `arrive` instead of a boost:** `arrive` brakes and curves under avoidance; §2.13 asks for a boost (straight V legs).
- **The plan's literal `n = (centre − P).normalized()`:** not perpendicular to the wall once the player moves; the wall would advance askew and strain.
  The normal is `u`'s orthogonal signed toward the line, which is the same direction when the player is on the normal.

## Build sequence

1. Progress notes; this plan reviewed (`4-review.md`).
2. **Tests first:** `tests/integration/test_laser_tender.gd` (rows below), shared-file edits (rosters, `test_wreck.gd`, `test_base_enemy.gd`,
   `test_enemy_dual_mode.gd`, `test_engagement_deadline.gd`, the sweep and enum pin in `test_twin_laser_drones.gd`). Run: fails (no classes).
3. Config + `.tres`, ship scene + shell; roster gates green.
4. Rig LAUNCHED + launched frame; drone LAUNCHED motion; tender brain Open Space (APPROACH / HOLD / LAUNCH / WAIT / REARM, docking, points).
5. Assault: hold band, Assault points, one launch per life, budget deferral, DISENGAGE.
6. `WaveBuilder`; wave row.
7. Full gate (`bash /agent/verify.sh`), `scripts/check-test-leaks.sh`, `scripts/gate-time.sh` after.
8. Docs: `ENEMY.md` (with the IDEAS §43 checklist), `docs/enemy-roster.md`, `docs/architecture/modules/assault.md`, `PROJECT.md` if it lists the roster,
   `CLAUDE.md` Phase 8 line, `DECISIONS.md` ("Phase 8, built in t13"), `tests/README.md` gate row; `updating-project-docs`.

## Test plan

`tests/integration/test_laser_tender.gd` — INTENT. Hand-ticked: each tick calls the tender's `_physics_process(DT)`, then drone A's, then B's, putting
each at `before + velocity · DT`, then moves the stub (t12's `_step`, extended). The tender and every launched drone have their body `collision_mask`
cleared (t12's finding). The stub is the harness player with a 14 px `HurtBox`. Numbers come from `laser_tender_config.tres`,
`twin_laser_drone_config.tres` (both preloaded, read only) and `EnemyBeamScenes.export_of(TWIN, …)`. Geometry: P = (640, 360); Open Space tender at
`P + (0, −preferred_range)` (it HOLDs on its first tick), Assault tender at the hold point (P = (640, 600)) so both launch on the first eligible tick.
A brain test seam `force_launch_ready()` is **not** needed: the geometry makes HOLD → LAUNCH immediate (rows 13b and 17 spawn from above instead).
**Shared recordings (review N1, committed up front):** rows 4 and 5 read one launch per case; rows 7, 8, 9 and 12 read one Attack B recording per case
(`_record_b()`: every tick's phase, frame, separation, strain, hits on the stub / victim / tender), so the file runs ≈ 16 hand-ticked scenarios plus
two real-physics ones.

Structure (no ticking):
1. `test_the_tender_is_one_r40_circle_shared_by_body_hurtbox_and_contact_box_with_two_cradles` — same `Shape2D` on all three, r 40; contact box layer
   256 / mask 0 / damage 15; COLLISION; StateLight; mover + brain; `CradleL` (−30, 10) and `CradleR` (30, 10) Marker2Ds, each with a visible
   `DockedDrone`; `docked_count()` 2.
2. `test_the_shipped_config_wins_over_the_scene` — health, contact damage, score, mover speed / acceleration and hazard profile from the `.tres`; every
   §2.13 value (and the six added fields) pinned once here.
3. `test_the_phase_enums_are_declared_in_full_and_in_order` — tender Phase keys (9, in order); the rig enum ends in LAUNCHED (t12's pin updated in
   `test_twin_laser_drones.gd` too).

Launch (both modes unless marked):
4. `test_the_cradle_telegraph_shows_for_launch_telegraph_before_the_drones_appear(mode)` — LAUNCH entered on tick 1; on every tick until the launch the
   light is CHARGING and no `TwinLaserDrone` exists; the drones appear at `launch_telegraph` (± 1 tick) after LAUNCH entry; both cradles' `DockedDrone`
   hide; both drones are in the rig's `owner_group` with the tender, their brains in LAUNCHED after their first tick; `accept_tow` false in LAUNCH.
5. `test_the_drones_leave_on_diverging_paths_that_never_cross(case)` — cases `open_space:standing`, `open_space:toward` (stub at 200 px/s toward the
   tender: a broadside wall), `assault:still` (broadside), `open_space:crossing` (200 px/s along +x) and `assault:strafe` (end-on). On every case: the
   segments cradle → point do not intersect; the angle between `launch_dir_of(A)` and `launch_dir_of(B)` is > 0° and < 160° (diverging, never
   anti-parallel); after 0.3 s each drone's displacement is within 5° of its launch direction (a straight leg); on the latch tick (the first TELEGRAPH tick) the drones are
   `rig_length` ± `length_tolerance` apart; each drone is within `slot_tolerance` of its point by `launch_seconds_of(it)` + 1 tick (or, when capped,
   has flown `launch_speed · launch_max_seconds` ± one tick's travel, **measured on the LAUNCHED → FORM tick** (≈ 727.7 px), not a tick later, where
   the deceleration leaves < 1 px of margin; review round 3). Broadside cases also: the angle is > 20° (§2.13's V). End-on cases print the
   angle (the logged geometric limit). Row 4 shares these launches.
6. `test_open_space_points_lie_on_the_predicted_path_across_the_heading(case)` (Open Space; cases `moving`, `standing`) — moving: a 200 px/s stub along
   +x; the latched wall's centre (rig `centre` at TELEGRAPH) is within 30 px of the stub's path line, ahead of the launch position, and `axis` is ⟂ the
   heading within 5°. Standing: centre = `P + facing · standing_lead` within 1 px and `axis` ⟂ `(P − tender)` within 5°. Plus pure
   `attack_b_points()` cases on a 360 px/s stub: at 650 px the lead is `650 / 520` = 1.25 s (uncapped), at 1000 px it is `lead_time_max` 1.5 s (capped,
   not 1.92), and the points are always `rig_length` apart.

Attack B wall (R8.24 for the V-launched wall):
7. `test_attack_b_keeps_its_length_on_every_telegraph_and_advance_tick(case)` — cases `open_space:0`, `open_space:200`, `assault:0`, `assault:200`
   (stub standing, or moving at 200 px/s along +x): on **every** TELEGRAPH and ADVANCE tick `separation_error() ≤ length_tolerance`, `strained` false,
   the frame identical on each such tick; `centre` and `axis` equal the launched ones (`mid(points)`, `points[1] − points[0]`); `normal` equals the sign
   rule computed by the test from the latched player (`sign((centre − P) · axis.orthogonal())`); ADVANCE lasts `D / advance_speed` ± 1 tick where the
   test computes `D = min((centre − P) · n, standoff) + overshoot` itself (Assault: also capped by the room in the inset rect).
8. `test_the_wall_advances_at_a_standing_player_and_hits_it(mode)` — standing stub: the wall moves along `−n` toward it (the stub's signed distance to the
   line changes sign during ADVANCE) and the stub is hit (≥ 1 hit, gaps ≥ `rehit_interval`).
9. `test_a_player_who_runs_round_an_end_is_not_hit(mode)` — the stub stands until TELEGRAPH, then runs along the wall's `axis` at 360 px/s (toward the
   nearer end): never hit; control in the same row: a still stub on the same setup is hit (row 8 shares the run).

One live pair, rearm, docking (Open Space; Assault launches once):
10. `test_no_launch_while_a_pair_lives_and_rearm_after_both_drones_die` — after the launch, the drones are left untouched (alive, the pair intact) and
    the tender alone is ticked for `rearm_seconds + 2 s`: it stays in WAIT and `launches()` stays 1. Both drones are killed: REARM on the next tick, no
    launch and `docked_count()` 0 for `rearm_seconds` (− 1 tick), then HOLD → LAUNCH → a second pair (`launches()` 2) at `rearm_seconds +
    launch_telegraph` after the second death, no earlier, and no later than that `+ TICK_SLACK`.
11. `test_a_lone_surviving_drone_flies_home_and_docks` — kill drone B on the first FORM tick: A goes SOLO, flies to the tender and is freed by
    `dock()` within 4 s; `docked_count()` 1 (one `DockedDrone` visible); no `died` on A (it docked, it did not die); the tender is in REARM. Second
    case (review N3): the survivor is held away (not ticked) through the rearm and a second launch, then released: it still docks, and
    `docked_count()` stays ≤ 2.
12. `test_the_tender_is_never_hit_by_its_pairs_beam(mode)` — after the latch, the tender is moved onto the wall's advance path at the stub's side (and a
    fixture victim beside it, both within the swept band): over the ADVANCE the victim loses HP, the tender none; the tender is in `owner_group`.

Assault:
13. `test_assault_vertical_wall_for_a_strafing_player_horizontal_for_a_still_one(case)` — cases `strafe_then_stop` (stub at 200 px/s along +x until
    the launch, then still), `strafe_on` (it keeps strafing) and `still`: both strafe cases → the launched frame's `axis` is vertical (|u.x| < 0.01) and
    the wall's x = `P_launch.x + assault_wall_lead`; `strafe_then_stop` → `normal` = +x (the wall is ahead and advances back at the player, which it
    hits); `strafe_on` → the stub is past the wall at the latch, `normal` = −x (re-signed: the wall chases from behind) and the wall's distance to the
    stub along `−n` is what the advance closes; `still` → `axis` horizontal, centre y = `P.y − standoff`, `normal` = UP. In every case, on every tick
    from launch to the end of ADVANCE both drones are inside `inner_rect()`; the tender launched from inside the view's upper band
    (`y ≤ view.y + assault_hold_depth + HOLD_REACH`).
13b. `test_assault_tender_from_above_reaches_its_band_and_launches_against_a_strafing_player` — hand-ticked, the tender spawned **at (1000, −200)**
    (200 px above the view, ahead of the stub's run; review round 3), the stub starting at the inset rect's left edge (x −76) and strafing at 360 px/s
    +x, reversing at the edges: it reaches HOLD and launches within `engage_seconds`. Boundary inside the row (review R2-B2), read only in the window
    before the stub's first reversal (at ≈ 3.97 s): the tender reaches the band (and HOLD) in that window (expected ≈ 3.0 s) while never being within
    `HOLD_REACH` of the moving hold *point* (closest approach expected ≈ 111 px), so the rejected point rule would not have fired there. The row prints
    the band time, the reversal time and the closest approach, so a geometry slip reads differently from a code bug.
14. `test_assault_one_launch_per_life_then_disengage` — after the launch the tender is in DISENGAGE with `constraint_released()`, `launches()` stays 1, and
    it is freed outside `projectile_world_rect()` within 5 s; the pair's drones DISENGAGE after their one ADVANCE (t12's rule, sampled once).
15. `test_assault_budget_expiring_in_the_cradle_telegraph_lets_the_launch_finish(case)` — cases `mid_telegraph` (budget expires 0.3 s into LAUNCH) and
    `before_launch` (boundary: `engage_seconds` 0.1, the tender spawned 300 px above its hold point so it is still in APPROACH): `mid_telegraph` launches
    at `engage_seconds + launch_telegraph + TICK_SLACK` or earlier, then DISENGAGE; `before_launch` DISENGAGEs at 0.1 s (± 1 tick) and never launches.

Real physics (8× clock, masks intact; review B4):
17. `test_on_real_physics_the_launch_flies_straight_out_of_the_tender(mode)` — the tender on real physics (Open Space at `preferred_range`; Assault
    spawned above the view with a stub strafing at 200 px/s, moved by a `_Ticker`): each launched drone is in the tender's
    `get_collision_exceptions()` and the tender in each drone's; 0.3 s after the launch each drone's displacement is within 5° of its launch direction
    and ≥ 0.8 · `launch_speed` · 0.3 px from its cradle (not pushed out sideways or held by the tender's body); each reaches its point within
    `slot_tolerance` by `launch_seconds_of + 2` physics ticks; both drones are inside the tree and in `enemies` on the launch tick itself (the
    synchronous add on a real step). Polled by `await wait_physics_frames(4)`, capped at 4 s of game time.

Through a real `WaveManager`:
16. `test_assault_wave_builder_spawns_a_laser_tender_through_a_real_wave_manager` — `b.wave(0.0, [b.laser_tender().at(0, -100)])`:
    `WaveBuilder.LASER_TENDER` is the scene path; after a few frames the container holds one `LaserTender` at `cam + 2 · (0, −100)` (read at
    `enemy_spawned`).

Shared files (§2.19):
- `test_enemy_hurtbox_geometry.gd`, `test_contact_hitbox_geometry.gd`, `test_enemy_contact_damage.gd`: the tender in each `ROSTER` (config path in the
  third). `test_wreck.gd`: `_SHIP_SCENES` gains it.
- `test_base_enemy.gd`: `_MIN_ROSTER_SIZE` 20, `_AUTHORED_CONTACT_MODES["laser_tender"] = COLLISION`, `_REFUSING_PHASES["laser_tender"] = ["LAUNCH"]`.
- `test_enemy_dual_mode.gd`: `test_laser_tender_launches_a_pair_in_both_modes(mode)` (spawned at its hold, hand-ticked: LAUNCH with the light CHARGING,
  then two drones in LAUNCHED bound with the tender in their owner group, cradles empty) and the `HAZARD_PROFILES` row (0.8 / 24 / 0.3).
- `test_engagement_deadline.gd`: `test_no_enemies_cleared_section_spawns_a_laser_tender` (with the boundary probe of the pair row).
- `test_twin_laser_drones.gd`: the no-motion sweep gains `laser_tender.gd` and `laser_tender_brain.gd` (review N6); the rig enum pin gains LAUNCHED.
- Automatic sweeps (no edit): config isolation, generic lethal flow and mask 1121, transparency, single writer, signal arity, load integrity, UID
  integrity.

Gate time (review R2-N1: the reviewer counts ≈ 25 scenarios and ≈ 2.1–2.7 s; planned trims: row 17's Assault case starts in the band, since 13b
covers the approach, and rows 8 and 12 share row 7's standing-stub recordings; measured after building, and an overrun is fixed by sharing or the 16×
clock, never by cutting an assertion). 2.0 s allotted. Original estimate (review N1): ≈ 16 shared hand-ticked scenarios of 2–8 s game time at three bodies (≈ 0.05–0.08 s each) ≈ 1.1 s,
the rearm row (≈ 18 s game time, mostly the tender alone) ≈ 0.15 s, the two real-physics rows ≈ 0.4 s, the wave row ≈ 0.1 s, structure and pure rows
≈ 0.1 s → ≈ 1.85 s. Over budget → share more scenarios or the 16× clock, never cut a mode or an assertion.

## Risks

- **Strain at the latch of a launched wall:** both drones arrive on fixed points from different distances; FORM's slot / separation latch guards it and
  row 7 measures it every tick.
- **The rig's u sign on a launched frame** is set from the points (A → B), not from the drones' positions; a drone short of its point (capped launch)
  still converges on its own slot, never the partner's.
- **Docking near a moving tender:** the SOLO drone `arrive`s at the tender's position; with the collision exception it reaches it; `dock_radius` 72
  leaves 19 px over touching distance.
- **Escape scoring of a docked drone:** docking runs in Open Space only (no `ScoreTracker` there); in Assault a lone drone DISENGAGEs (t12).
- **Self-reference leak:** `laser_tender.gd` names `TwinLaserPair` and its own config but never `LaserTender`; `check-test-leaks.sh` verifies.
- **Gate time:** measured before (206.547 s) and after.

## Out of scope

Hub idle (IDLE / NOTICING / RETURNING motion, `start_engaged` meaning, `AnchorIdle`) and the measured Assault exits (t14); art (t16); hub and level-1
placement (t18 / t19); Carrier / fortress launch bays (Ph10 / Ph11, through `launch_pair`).
