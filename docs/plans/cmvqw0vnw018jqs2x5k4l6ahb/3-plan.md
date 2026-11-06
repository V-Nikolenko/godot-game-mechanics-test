# t12 — Twin-Laser Drones, the `TwinLaserPair` rig and Attack A

Epic `cmug23ona0015m52w4t1m73bc` (Phase 8), plan task t12. Builds epic plan §2.12 with §2.1, §2.3, §2.4 and §2.19 (approved). This task plan does
not redesign them; it fixes what they leave open (the rig's tick protocol, the phase mapping between rig and brain, the Assault frame planner, the
WAIT and SOLO motion, file layout, scene layout, test geometry). Where it says "§2.x", the epic plan wins. Context: `1-context.md`.
Baseline: `scripts/gate-time.sh` GUT `Time` **204.634 s**, 2518 tests (measured at the start of this task, `4772ffc`).

**Revised after review round 1 (`4-review.md`):** B1 the ADVANCE boost is a one-step boost renewed each tick (brain §6) and rows 7–9 assert the
survivors' motion on the next tick; B2 row 5's moving cases spawn off their slots and assert the latch happens while the drones move; B3 row 17 reads
its geometry at the collapse against the derived strain lag, and row 17b is its real-physics no-wreck control. N1 every FORM's first frame takes
`n_target` outright (row 15 checks the re-FORM); N2 the rig's own `_gone` / `_broken` flags; N3 row 4b; N4 the lens in row 5; N5 row 18 reads at
the orphan emission; N6 row 11b; N7 row 16's latch-tick case; N8 docs. Also from building: hand-ticked drones clear their body `collision_mask`
(test plan preamble), and in Assault a strain collapse during ADVANCE ends the life's attack (brain §5).

## Problem

Today the only enemy lasers in the game are fixed: turret beams, fences, the station. Nothing moves a laser *at* the player. After this task, two small
drones fly to opposite sides of the player, hold a laser of fixed length between them, show it as a warning line, and then fly the whole line
through the player's position and past it. The player escapes by reaching an end of the line (it is slower than the player), by killing either
drone (the beam drops at once), or by baiting a drone into a gravity well or a wreck (the line strains, flickers harmlessly and collapses). In
Open Space the pair repeats the attack every few seconds; in Assault it attacks once inside the corridor and then leaves. Every enemy caught on the
line is hurt too.

## Design

### Files (all new unless marked)

`assault/scenes/enemies/twin_laser_drone/`:
- `twin_laser_drone.gd` — `class_name TwinLaserDrone extends BaseEnemy` (the shell).
- `twin_laser_drone_brain.gd` — `class_name TwinLaserDroneBrain extends EnemyBrain`.
- `twin_laser_pair.gd` — `class_name TwinLaserPair extends RefCounted` (the rig).
- `twin_laser_pair_spawn.gd` + `twin_laser_pair_spawn.tscn` — `class_name TwinLaserPairSpawn extends Node2D`.
- `twin_laser_drone_config.gd` + `twin_laser_drone_config.tres` — `class_name TwinLaserDroneConfig extends ShipConfig` (flat).
- `twin_laser_drone.tscn`, `ENEMY.md`.

Script dependencies stay acyclic: the rig names `EnemyBeam`, `EnemyBeamScenes`, `EnemyBrain`, `TargetInfo` and the config class, **never the brain or
the drone class** (it reaches a drone's brain duck-typed through `get_node("Brain")` and `set(&"pair", …)`); the brain names the rig and the config;
the drone names the brain and the config; the spawner names the rig and loads the drone scene by path. `TwinLaserPair` names itself in its own static
`bind()` (the `TargetInfo` precedent, a RefCounted); `scripts/check-test-leaks.sh` is the proof it does not leak (the `enemy_mine.gd` trap was a Node
script). If it does leak, the factory moves out of the class (a static `TwinLaserPairSpawn.bind_pair()` that calls `TwinLaserPair.new()` and an
instance `setup(a, b, controller)`), so the rig's own file never names its class.

Edited: `assault/scenes/systems/wave_builder.gd` (`TWIN_LASER_PAIR`, `twin_laser_pair()`), the shared test files of §2.19, `test_enemy_beams.gd`,
`test_engagement_deadline.gd`, docs.

### The drone (`twin_laser_drone.tscn`, `TwinLaserDrone`)

Root `CharacterBody2D` `TwinLaserDrone` (layer 1 / mask 1 like every enemy body, so it stops on a wreck). Children: `CollisionShape2D` (one
`CircleShape2D` r 13, the one `SubResource` shared by the next two), `HurtBox` (layer 512, mask 65, the shared shape), `Health` (30),
`HitFlashAnimationPlayer` (animates `.:self_modulate`, the turret's placeholder idiom), `ContactHitBox` (layer 256, mask 0, `damage` 8,
`damage_type` CONTACT, the shared shape, scale 1), `ContactProfile` (mode COLLISION, authored), `EnemyMover` (`constraint_mode` AUTO), `Brain`,
`StateLight` at (0, 6) (the lens, forward of the nose-down hull).

`_ready()`: `super._ready()`, `add_to_group("enemies")`, `_apply_config(config)` (health, score, contact damage, mover `max_speed` / `acceleration`,
`brain.config`), `queue_redraw()`. Placeholder art is code-drawn in `_draw()` (a dark r 13 disc with a lens dot at the nose); t16 replaces it. No
`_physics_process` (the shared `BaseEnemy` tick). Accessors: `brain()`, `pair()` (= `brain().pair`), `state_light()`, `body_radius()`.
`sprite_forward_angle` stays `PI / 2`.

### Config (`TwinLaserDroneConfig`, flat; `.tres` = §2.12's starting values)

`ShipConfig` fields in the `.tres`: `max_health` 30, `collision_damage` 8, `score_value` 30, `hazard_avoidance` 0.6, `hazard_margin` 16,
`hazard_resistance` 0.1, `wreck_chance` 0. Own fields: group Movement `max_speed` 300, `acceleration` 900; group Rig `rig_length` 420,
`length_tolerance` 16, `strain_seconds` 0.15, `advance_speed` 240, `standoff` 260, `overshoot` 200, `slot_tolerance` 24, `form_timeout` 3.0,
`break_seconds` 1.2, `break_speed` 260, `attack_period_min` 4.0, `attack_period_max` 6.0; group Assault `engage_seconds` 8.0, `exit_speed` 420.
`counts_as_escape` stays true (a drone is not static).

### The rig (`TwinLaserPair`)

```
enum Phase { FORM, TELEGRAPH, ADVANCE, BREAK, COLLAPSED, WAIT }   # §2.12's five, WAIT appended (append-only allows it)
signal phase_changed(new_phase: int)
signal collapsed(intact: bool)       # true = a strain collapse with both drones alive; false = the pair broke for good
const FRAME_TURN_RATE := PI / 2.0    # rad/s, §2.12's "a turn of at most 90°/s"
const EPS := 1e-6                    # summed-delta slack, as EnemyBeam / TurretMount
var drone_a, drone_b, controller: Node2D
var owner_group: StringName          # &"twin_pair_%d" % get_instance_id()
var beam: EnemyBeam                  # a child of drone_a
var config: TwinLaserDroneConfig     # drone_a's private copy
var phase := Phase.FORM
var centre, axis (u), normal (n): Vector2;  var has_frame := false;  var vertical := false
var advance_distance, advance_left: float;  var latched_player: Vector2;  var player_velocity: Vector2
var advances_started := 0;  var collapses := 0;  var strained := false;  var strain_time := 0.0;  var wait_seconds := 0.0
```

WAIT is a rig phase because the two drones must re-FORM on the same tick, which needs one shared clock (a brain-only WAIT would need two clocks
that agree). Logged in `DECISIONS.md` as the one addition to the rig enum.

- `static func bind(a, b, controller = null) -> TwinLaserPair`: builds the rig, `owner_group` from its instance id, adds `a`, `b` and the controller
  (if any) to it, instantiates `EnemyBeamScenes.scene_for(TWIN)` as `TwinBeam`, `a.add_child(beam)`, `beam.setup(a, owner_group)`, sets each drone's
  `Brain.pair` (duck-typed), connects each drone's `died` and `tree_exiting` (one-shot) to `_on_drone_gone(drone)` (the `LaserFence` shape), and
  records the starting endpoints. Works on drones in or out of the tree.
- **`_gone`** (the rig's own flag, a set of instance ids; review N2): a drone is put in it by `_on_drone_gone` (its `died` or `tree_exiting`) and by
  `release()`. `died` is emitted *before* `queue_free()` (`base_enemy.gd`), so "queued for deletion" alone is not yet true inside the death hook; the
  rig reads `_gone` first. `_broken` (the pair broke for good) is the second flag.
- `leader()`: `drone_a` while it is live (valid, not queued for deletion, not in `_gone`), else `drone_b`.
- `is_intact()`: not `_broken`, both drones live as above, and neither `is_ai_suspended()`.
- `partner_of(d)`, `side_of(d)` (−1 for A, +1 for B), `slot_of(d) = centre + side_of(d) · u · L/2` (A at −u; the drone's own position before the first
  frame), `separation_error() = | |A − B| − L |` (INF unless both are valid), `advance_dir() = −n`, `phase_time()`.
- `release(d)`: the drone leaves the rig for good (DISENGAGE, a rail): the pair breaks (below). If `d` owns the beam and is suspended, the beam is
  freed (nobody would tick its fade).
- **`tick(delta, caller)`**: returns at once unless `caller == leader()`, so **phase transitions happen only in the leader's tick** (§2.12). It reads
  `TargetInfo.player()` once (the rig's only player read; `player_velocity` is that snapshot) and the leader's corridor rect (its brain's
  `mover.constraint.inner_rect()` when the constraint is present and not released; empty = Open Space). Then by phase:
  - not intact and not COLLAPSED → break for good (catch-all; the signals normally get there first).
  - **FORM**: update the frame (below); if the Assault planner finds no fit → BREAK; if both drones are within `slot_tolerance` of their slots
    and `separation_error() ≤ length_tolerance` → TELEGRAPH (latch: the frame stops updating, `latched_player = P`, `beam.start()`); else after
    `form_timeout` → BREAK.
  - **TELEGRAPH**: strain check; when `beam.phase() == ACTIVE` → ADVANCE (`advances_started += 1`, `advance_left = advance_distance / advance_speed`).
    Reading the beam's own phase keeps one clock (it went ACTIVE in the previous tick's `tick_beam`, so the advance starts one tick into ACTIVE,
    inside `ignite_grace` 0.1).
  - **ADVANCE**: strain check; `advance_left -= delta`; at `≤ EPS` → BREAK.
  - **BREAK**: entry cancels the beam; after `break_seconds` → WAIT (Open Space; `wait_seconds = rng.randf_range(attack_period_min, _max)` from the
    leader's brain `rng`) or FORM (Assault: a retry; a pair that already advanced never gets here as a pair, see the brain).
  - **WAIT**: after `wait_seconds` → FORM.
  - **COLLAPSED** with the pair intact (a strain collapse) → BREAK on the next leader tick ("survivors BREAK and re-FORM"); not intact → stays.
- **Strain** (TELEGRAPH and ADVANCE, leader's tick): `separation_error() > length_tolerance` → `strained = true`; the first strained tick sets
  `strain_time = 0`, each later one adds `delta`; at `strain_time + EPS ≥ strain_seconds` → COLLAPSED (`beam.cancel()`, `collapses += 1`,
  `collapsed.emit(true)`). Back within tolerance → `strained = false`, `strain_time = 0`. Every other phase clears it. So the collapse lands
  `strain_seconds` after the strain began, which a row checks to the tick.
- **Breaking for good** (`_on_drone_gone`, `release`, the catch-all): phase COLLAPSED for good, `strained = false`, `beam.cancel()` if the beam is
  still valid (A's death frees it with A; B's death leaves A to fade it), `collapsed.emit(false)` once. **Killing either drone ends the beam in the
  same call** as the kill, so "within one tick" holds with zero ticks.
- **`tick_beam(delta, caller)`**: only for `caller == drone_a` with a valid beam: `set_endpoints(A, B or B's last position)`,
  `set_strained(strained)`, `beam.tick(delta)`. Called by A's brain at the end of every tick, in every phase (DISENGAGE and SOLO included), so a
  cancelled beam always fades out to OFF.

**The frame.**
- **Open Space** (FORM only): `n_target = (mid(A, B) − P).normalized()` (the current `n` if that is zero); the first frame **of every FORM** (the
  first ever, and every re-FORM from BREAK or WAIT; review N1) takes it outright and re-derives the `u` sign from the drones' positions, later frames
  turn `n` toward it by at most `FRAME_TURN_RATE · delta`. (After an advance the drones sit `overshoot` past the player, so the old `n` points the
  wrong way; turning it 180° at 90°/s would swing the slots at ≈ 525 px/s, faster than `max_speed`.) `centre = P + n · standoff`; `u = ±n.orthogonal()`, with the sign that puts A
  on the −u side, i.e. `sign((B − A) · n.orthogonal())`, **kept from the previous frame unless** `(B − A) · u < 0` **and**
  `|(B − A) · n.orthogonal()| > slot_tolerance` (hysteresis: two drones nearly in line along n never swap slots back and forth). The advance is
  `standoff + overshoot` = 460 px, i.e. 1.917 s at 240 px/s.
- **Assault**: `static func assault_frame(p, rect, length, standoff, overshoot, prev_vertical, prev_side, hysteresis) -> Dictionary` (pure, unit-
  tested; `{}` = no fit). `rect` is the corridor's `inner_rect()` **grown by −`slot_tolerance`**, so a drone within `slot_tolerance` of a slot is
  inside `inner_rect()` and the corridor constraint is the identity on both ends for the whole attack (the constraint never bends one end).
  - horizontal (preferred): fits when the room above the player `p.y − rect.position.y ≥ standoff` (and, when the previous frame was vertical,
    `≥ standoff + hysteresis`); `n = UP`, `centre = (clamp(p.x, rect.x + L/2, rect.end.x − L/2), p.y − standoff)`; the overshoot is clamped to the
    room below, `clamp(rect.end.y − p.y, 0, overshoot)`.
  - vertical: on the side with more room (the previous side kept unless the other has more by over `hysteresis`); fits when that room
    `≥ standoff`; `n = ±RIGHT` pointing at that side, `centre = (p.x ± standoff, clamp(p.y, rect.y + L/2, rect.end.y − L/2))`; the overshoot is
    clamped to the room on the other side.
  - neither, or a rect shorter than `L` along `u` → `{}` → BREAK (§2.12 "If neither fits, BREAK").
  - result `{centre, normal, vertical, side, advance}`; `u` takes the same sign rule as Open Space. `hysteresis` = `slot_tolerance`.
  The centre is clamped along `u` only, so the line still covers the player (|p − centre| along u ≤ L/2 whenever the player is inside `rect`).

### The brain (`TwinLaserDroneBrain`)

`enum Phase { FORM, TELEGRAPH, ADVANCE, BREAK, WAIT, SOLO, DISENGAGE, LAUNCHED, IDLE, NOTICING, RETURNING }` (append-only, declared in full; this
task plays the first seven), `signal phase_changed(new_phase: int)`, `var config`, `var pair: TwinLaserPair`, `var phase`, `var budget`,
`var start_engaged := false` (a t14 seam: there is no idle yet; the tow table sets it), `var patrol_anchor := Vector2.INF` (defaults to the spawn
position). `enter_phase(p)` is the one place a transition happens (the Mine Layer's seam: runs `p`'s entry code, then emits); it works on a lone
drone (no pair), which the tow table and t14's exit probe rely on.

Each `tick(delta)`:
1. first tick: `_setup()` (`budget = EngagementBudget.new(engage_seconds, tree)`, `patrol_anchor`).
2. `expired = budget.update(delta)`.
3. DISENGAGE → its tick, the beam tick, done.
4. `pair.tick(delta, actor)` (a no-op unless this drone leads).
5. No pair, or not intact → Assault: DISENGAGE; Open Space: SOLO.
   Intact → **Assault rule**: if `budget.active` and the rig is not in TELEGRAPH / ADVANCE and (`expired` or `pair.advances_started > 0`) →
   DISENGAGE (**one ADVANCE per life; a budget that expires in TELEGRAPH or ADVANCE lets that attack finish**). So a strain collapse *during*
   ADVANCE ends the life's attack in Assault (both DISENGAGE on the collapse tick: `collapsed(true)` then `collapsed(false)`), while a collapse in
   TELEGRAPH (no advance yet) BREAKs and re-FORMs. Otherwise mirror the rig:
   FORM/TELEGRAPH/ADVANCE/BREAK/WAIT → the same; COLLAPSED (intact) → BREAK.
6. Motion for the phase (requests only):
   - FORM: `mover.arrive(pair.slot_of(actor), max_speed)` + `mover.add_nudge(pair.player_velocity)` (the feed-forward), `face_toward(partner)`.
   - TELEGRAPH: `arrive(slot)` on the latched frame, `face_toward(partner)`.
   - ADVANCE: `mover.boost(pair.advance_dir(), advance_speed, delta)` every tick — **a one-step boost renewed each tick** (review B1:
     `EnemyMover.boost()` ignores every request for its whole duration and cannot be cancelled, so a boost for `advance_left` would keep a survivor
     flying along −n for up to ≈ 1.4 s after a kill or a collapse); the rig's `advance_left` is the one clock. Identical on both drones (boost skips
     avoidance and accel, keeps the well's drift and the corridor) — `face_toward(partner)`. Leaving ADVANCE for any reason, the next step is
     un-boosted.
   - BREAK: `request_velocity(u · side_of(actor) · break_speed)` (A along −u, B along +u).
   - WAIT: `arrive(_hold_point)` (where BREAK left it, latched on entry), `face_toward(partner)`.
   - SOLO (Open Space): `arrive(controller if live else patrol_anchor, max_speed)` (t13 adds docking, t14 the idle).
   - LAUNCHED / IDLE / NOTICING / RETURNING: `request_velocity(ZERO)` until t13 / t14 give them motion.
7. `pair.tick_beam(delta, actor)`; the lens light: CHARGING while the beam TELEGRAPHs, ARMED while it is ACTIVE, OFF otherwise and in SOLO /
   DISENGAGE (set only on change).

DISENGAGE entry: `pair.release(actor)`, `exit_dir = −pair.normal` when the pair has a frame (§2.12 "exit along −n"), else the heading (velocity
above 1 px/s, else the nose); `mover.release_constraint()`, `mover.max_speed = exit_speed`. Tick: free once outside `projectile_world_rect()`
(strict compares, the Mine Layer's), else `request_velocity(exit_dir · exit_speed)`. When one drone disengages, its release breaks the pair, so the
other goes SOLO → DISENGAGE on its own tick (Assault) — normally the same frame, since both budgets started on the same tick.
`accepts_tow()`: false in TELEGRAPH, ADVANCE, LAUNCHED. `on_suspended()`: `pair.release(actor)`, light OFF.

**Tick order.** Drone A is added to the container before B, so on real physics A (the leader) ticks first and B mirrors the new rig phase in the
same frame; hand-ticked rows tick A then B. If the order were reversed, B would lag one tick: at most `advance_speed / 60` = 4 px in ADVANCE, inside
`length_tolerance` 16 (§2.12).

**Assault life bound** (§2.12): a drone's DISENGAGE starts no later than `engage_seconds + telegraph_seconds + max_advance_seconds + _TICK_SLACK`
after its spawn, `max_advance_seconds = (max(standoff, assault_wall_lead) + overshoot) / advance_speed`. `assault_wall_lead` is the tender's
(t13); this task's Attack A advance is `(standoff + overshoot) / advance_speed` = 1.917 s, which a row bounds.

### The spawner (`TwinLaserPairSpawn`)

`@export var rng_seed := 0`, `@export var drone_scene: PackedScene` (= `twin_laser_drone.tscn`), `counts_toward_wave_clear` / `counts_as_escape`
false, `score_value` 0. `_ready()` defers `spawn_pair()`; **`spawn_pair() -> TwinLaserPair` is public and idempotent** (the `TurretGroup.spawn_members()`
precedent: hand-ticked rows call it directly): instantiates A and B, places them at `global_position ∓ global_transform.x.normalized() · L/2` (L read
from A's config), seeds their brains (`rng_seed`, `rng_seed + 1` when non-zero), adds both to the spawner's parent (A first), `TwinLaserPair.bind(a, b)`,
`EventBus.enemy_spawned_orphan` for each, then `queue_free()`. `pair()` returns the rig. `WaveBuilder.twin_laser_pair()` spawns it
(`TWIN_LASER_PAIR` = its path); the design-space offset is camera-relative like every non-structure spawn.

### Alternatives rejected

- **Rig as a `Node` (a third scene node owning the beam):** one more owner to keep alive and free; the RefCounted board held by both brains is the
  `SquadController` precedent §2.12 names, and the beam already has an owner (drone A).
- **Rig-only phases (no mirrored brain phases):** the tow table, the light and t13's LAUNCHED need a per-drone phase; mirroring is one `match`.
- **Rig clock for TELEGRAPH → ADVANCE:** two clocks for one event; reading `beam.phase()` keeps the beam the authority on its own telegraph.
- **Clamping drones (not frames) to the corridor:** that is exactly the "constraint bends one end" failure §2.12 avoids; frames are planned inside an
  inset rect instead.

## Build sequence

1. Progress notes; this plan reviewed (`4-review.md`).
2. **Tests first:** `tests/integration/test_twin_laser_drones.gd` (rows below), the twin fairness row in `test_enemy_beams.gd`, the shared-file edits
   (rosters, `test_wreck.gd`, `test_base_enemy.gd`, `test_enemy_dual_mode.gd`, `test_engagement_deadline.gd`). Run the new file: it fails (the
   classes do not exist).
3. Config script + `.tres`, drone scene + shell script; roster gates green.
4. `TwinLaserPair` + brain: FORM / TELEGRAPH / ADVANCE / BREAK / WAIT / SOLO / DISENGAGE in Open Space; the length, latch, kill, strain and
   friendly-fire rows green.
5. Assault: `assault_frame()`, the inset, the one-attack rule and deferral, DISENGAGE; the Assault rows green.
6. Spawner + `WaveBuilder`; the spawner and wave rows; the real-physics wreck row.
7. Full gate (`bash /agent/verify.sh`), `scripts/check-test-leaks.sh`, `scripts/gate-time.sh` after.
8. Docs: `ENEMY.md`, `docs/enemy-roster.md`, `docs/architecture/modules/assault.md`, `DECISIONS.md` (Phase 8, built in t12), `tests/README.md`
   gate row; the `updating-project-docs` skill.

## Test plan

`tests/integration/test_twin_laser_drones.gd` — INTENT. Hand-ticked in both harnesses (`use_parameters(MODES)` over label strings) unless marked:
each tick calls `A._physics_process(DT)` then `B._physics_process(DT)` and integrates `position = before + velocity · DT` (the Mine Layer helper),
then moves the stub. **A hand-ticked drone's body `collision_mask` is cleared**: with no physics step between hand ticks the broadphase keeps every
body at its spawn point, so `move_and_slide()` would stop drone A on drone B's stale spawn position (found while building: an Assault-only "never
telegraphs"); body contact is exercised only by the real-physics rows. The stub is the harness player given a `HurtBox` with a 14 px circle (so the
beam can hit it) and a test-set velocity. Numbers come from `twin_laser_drone_config.tres` (preloaded, read only) and `EnemyBeamScenes.export_of(TWIN, …)`.
Geometry: player P = (640, 360); the spawner at `P + (0, −standoff)` with rotation 0, so the drones start on their slots (n = UP, u = +x, A on the left)
and the first TELEGRAPH comes within a tick or two. FORM convergence is exercised by the moving-stub cases (spawned 120 px off their slots, review B2),
the Assault side case and the dual-mode case.

Structure (Open Space, no ticking):
1. `test_the_drone_is_one_r13_circle_shared_by_body_hurtbox_and_contact_box_with_a_mover_brain_and_lens` — the same `Shape2D` object on all three,
   r 13, contact box layer 256 / mask 0 / damage 8, ContactProfile COLLISION, StateLight present, mover + brain present.
2. `test_the_shipped_config_wins_over_the_scene` — health 30, contact damage, score, mover `max_speed` / `acceleration` and hazard profile equal the
   `.tres`; every §2.12 rig and Assault value pinned once here against the `.tres`.
3. `test_the_phase_enums_are_declared_in_full_and_in_order` — brain Phase keys = the 11 names in order; rig Phase keys = FORM, TELEGRAPH, ADVANCE,
   BREAK, COLLAPSED, WAIT (append-only pin).
4. `test_the_spawner_places_two_drones_half_a_rig_length_along_its_local_x_binds_them_and_frees_itself(mode)` — spawner rotated 90°: drones at
   `±L/2` along its rotated x; both in `owner_group` and `enemies`; the beam is A's child, kind TWIN, host A, same owner group; two
   `enemy_spawned_orphan` emissions; brains seeded `s` / `s + 1`; spawner queued for deletion; its scoring flags false; a second `spawn_pair()` call
   spawns nothing (idempotent).
4b. `test_the_rig_and_the_spawner_write_no_motion` (review N3) — a source sweep of `twin_laser_pair.gd` and `twin_laser_pair_spawn.gd` for a
   `velocity` / `rotation` write (`=`, `+=`, `-=`, `*=`) or a `move_and_slide(` through **any** receiver (the single-writer gate only sweeps `actor.` /
   `body.` / `self.` receivers, and these files hold the drones as `drone_a` / `drone_b` / `drone`); a synthetic line `drone_b.velocity = Vector2.ZERO`
   matches (boundary). The spawner's one `drone.position = …` before `add_child` is placement, not motion. *As built (review round 2, 1):* the
   matcher is the single-writer gate's own (`_PROPS` / `_ASSIGN` / `_CALLS` and its `_hits()`, made `static` so this file reuses them, comments and
   strings blanked) behind an any-identifier receiver `\b\w+\.`, plus `move_and_(slide|collide)(`; five synthetic writes match and four reads /
   placements / comments (`player_velocity = target.velocity …`, `normal.rotated(…)`, `drone.position = at`, a commented write) do not.

Attack A (R8.24 "moving wall keeps its length"):
5. `test_attack_a_keeps_its_length_on_every_telegraph_and_advance_tick(case)` — cases `open_space:0`, `open_space:200`, `assault:0`, `assault:200`
   (stub standing, or crossing at 200 px/s along +x), spawned **120 px off its slots along −u** so FORM has to fly. Runs FORM → TELEGRAPH → ADVANCE →
   BREAK. Asserts on **every** TELEGRAPH and ADVANCE tick `separation_error() ≤ length_tolerance` (the worst printed) and `strained == false`; the
   frame (`centre`, `axis`, `normal`) is identical on every TELEGRAPH / ADVANCE tick; ADVANCE lasts `(standoff + overshoot) / advance_speed` ± 1 tick;
   the beam is lethal on every ADVANCE tick from `ignite_grace` on; on every tick of the run both lenses show the beam's state (CHARGING while it
   telegraphs, ARMED while it is ACTIVE, OFF otherwise — review N4); the standing stub is hit **exactly once**, the crossing one at most once, and no two
   hits on one target are closer than `rehit_interval`. Boundaries inside the 200 px/s cases (review B2): the FORM frame did move (`centre` changed by
   > 100 px before the latch) and both drones' own speed on the latch tick is ≥ 100 px/s (the latch happens while they move, so the overshoot risk is
   exercised and measured by the length check on every TELEGRAPH tick).
6. `test_a_stub_moving_during_telegraph_does_not_move_the_line_and_the_advance_crosses_the_latched_point(mode)` — the stub stands until TELEGRAPH,
   then runs 300 px/s along +x. The frame never changes; the drones' midpoint stays within `slot_tolerance` of the latched centre through TELEGRAPH;
   during ADVANCE the signed distance from `latched_player` to the line A–B changes sign while its projection on u lies inside the segment; the
   (moved) stub is never hit.
7. `test_killing_drone_a_mid_advance_ends_the_beam_at_once_and_frees_it_with_a(mode)` — kill A (lethal `received_damage`) on the 30th ADVANCE tick:
   `beam.is_lethal()` false **before any further tick**; rig COLLAPSED, `collapsed(false)` once; after one process frame the beam is freed; B is the
   leader, enters SOLO (Open Space) / DISENGAGE (Assault) on its next tick, and on that tick (review B1) B's mover is **not boosting** and its own
   velocity has turned toward its new request (SOLO: the change points at `patrol_anchor`; DISENGAGE: speed along −n above `advance_speed`, heading
   for `exit_speed`); in 2.0 s of ticks nothing is hit and nothing relights.
8. `test_killing_drone_b_mid_advance_makes_a_cancel_the_beam_and_never_relight_it(mode)` — kill B the same way: not lethal before any tick; A goes
   SOLO / DISENGAGE with the same motion checks as row 7; over 2.0 s A's ticks fade the beam to OFF, it is never lethal again, `start()` is never
   called again (phase never TELEGRAPH), and A's lens ends OFF.
9. `test_a_well_beside_drone_bs_path_strains_the_beam_and_it_collapses_after_strain_seconds(mode)` — a `HazardField` gravity well (radius 420, core
   90, pull 520, the dual-mode fixture's numbers) placed before the spawn at `B_slot + u · 340 − n · 300`: 453 px from B's slot (outside its reach,
   so FORM and TELEGRAPH are unaffected), 340 px beside B's path, ≥ 720 px from A's path. Asserts: the first strained tick is in ADVANCE; the beam is
   never lethal while strained; the collapse (`collapsed(true)`) arrives `strain_seconds` after the first strained tick (± 1 tick) with both drones
   alive; B's lateral displacement from its path > `length_tolerance / 2`. Then, on the next tick: Open Space — the rig is in BREAK and both movers
   are **not boosting**, B's own velocity has gained a +u component (its break side) and lost speed along −n (review B1); Assault — the collapse
   ended the life's one attack: `collapsed(false)` follows in the same tick and both brains are in DISENGAGE. **Control in the same row:** the same
   spawn without the well runs the whole ADVANCE to BREAK with no strained tick and no `collapsed(true)` (each world is freed out of the tree before
   the next, so the control never sees the well).
10. `test_the_beam_hurts_an_enemy_on_its_line_but_never_its_drones_or_controller(mode)` — two drones bound by hand with
    `TwinLaserPair.bind(a, b, controller)`, a fixture controller and a fixture victim both in the advance path (P − u·100 and P + u·100): the victim
    loses HP, the controller none, A and B none; the controller is in `owner_group`.
11. `test_only_the_leaders_tick_advances_the_rig` — Open Space: ticking only B leaves `phase` and `phase_time()` unchanged while A lives; ticking A
    advances them; after A dies B is `leader()`.
11a. `test_inside_the_death_hook_the_rig_already_counts_the_drone_gone` (review N2) — a handler connected to A's `died` after the rig's own sees
    A not yet queued for deletion, yet `leader() == B` and `is_intact() == false`: the rig reads its own `_gone` flag. The only row that pins N2 (row 11
    reads `leader()` after `received_damage.emit()` returns, when `queue_free()` has already run).
11b. `test_a_rail_taking_over_a_drone_breaks_the_pair(mode)` (review N6) — in TELEGRAPH, `A.suspend_ai()`: the pair is broken (`collapsed(false)`)
    and after one process frame the beam is freed and no `laser_wall` hazard of the pair is registered; a second pair, `B.suspend_ai()` in TELEGRAPH:
    the beam goes OFF at once (a TELEGRAPH cancel), is never lethal over 1 s of A's ticks, and A goes SOLO / DISENGAGE.

Assault (the Assault harness; the Open Space counterpart where marked):
12. `test_assault_frame_planner_clamps_switches_sides_and_refuses` — pure `assault_frame()` calls on the inset `inner_rect()`: centre player →
    horizontal, `n = UP`; player 30 px from the left edge → centre clamped to `rect.x + L/2`, |p − centre| along u ≤ L/2; player 106 px below the
    top → vertical toward the roomier side; room below 50 px → advance = standoff + 50; hysteresis: a previous vertical frame stays vertical at
    `standoff + 10` of room and switches at `standoff + slot_tolerance + 1`; the side is kept within `hysteresis` and switched past it; a 300 × 300
    rect → `{}`, and a 500 × 500 rect with room for neither shape → `{}`.
13. `test_assault_rig_stays_inside_inner_rect_with_the_player_by_a_side_edge` — P = (−40, 360), the spawn 300 px right of the clamped slots so FORM
    has to travel: on every TELEGRAPH / ADVANCE tick both drones are inside `inner_rect()` and `separation_error() ≤ length_tolerance`; the line
    still crosses the stub (hit once).
14. `test_assault_rig_is_vertical_when_the_room_above_the_player_is_short` — P = (400, −250) (106 px of inset room above < 260): `normal` = +RIGHT
    (956 px of room right vs 476 left), both drones at x ≈ P.x + standoff, inside `inner_rect()` on every TELEGRAPH / ADVANCE tick, advancing along
    −x; the stub is hit once.
15. `test_one_advance_per_assault_life_then_disengage_but_open_space_repeats(mode)` — Assault: after the ADVANCE both drones DISENGAGE with
    `constraint_released()`, `advances_started` stays 1, no second TELEGRAPH, and both are freed outside `projectile_world_rect()` within 5 s.
    Open Space: BREAK, then WAIT for a period in `[attack_period_min, attack_period_max]`, then FORM and a second TELEGRAPH (`advances_started` 2)
    that starts within `form_timeout` of the re-FORM with no BREAK in between, on a frame on the drones' side (`n · (mid(A, B) − P) > 0` at the
    latch; review N1).
16. `test_assault_budget_expiring_in_telegraph_lets_the_attack_finish_then_disengages(case)` — cases `latch` (the budget expires on the latch tick,
    the worst case of review N7: 47 + 1 + 115 = 163 ticks to DISENGAGE against a 2.75 s bound) and `mid_telegraph` (0.3 s into TELEGRAPH); both
    drones' `engage_seconds` set on their private configs before the first tick: the ADVANCE still runs in full and hits the stub, then DISENGAGE,
    starting no later than `engage_seconds + telegraph_seconds + (standoff + overshoot) / advance_speed + _TICK_SLACK` (2/60 s) after spawn.
16b. `test_assault_a_pair_whose_budget_expires_in_form_disengages_without_telegraphing` (boundary) — a pair spawned 600 px off its slots with
    `engage_seconds` 0.2 never TELEGRAPHs and DISENGAGEs at 0.2 s (± 1 tick).
16c. `test_a_pair_that_cannot_reach_its_slots_breaks_at_form_timeout_without_a_beam(mode)` (review round 2, 3a) — a pair spawned 600 px off its
    slots with both movers' `max_speed` 10: BREAK at `form_timeout` (± 1 tick), the beam never started (OFF, no TELEGRAPH), both brains BREAK; after
    `break_seconds` WAIT (Open Space) or FORM again (Assault); `advances_started` 0, the pair intact.
16d. `test_a_strain_collapse_in_telegraph_breaks_and_re_forms_without_spending_the_attack(mode)` (review round 2, 3b) — after the latch, B is held
    150 px off its slot along n after every tick: `collapsed(true)` once, `strain_seconds` (± 2 ticks) after the strain began, with the beam OFF (a
    TELEGRAPH cancel); `advances_started` 0; both brains BREAK (never DISENGAGE / SOLO); then WAIT (Open Space) or FORM (Assault), and in Assault
    the owed attack re-forms (TELEGRAPH) with the corridor still held.

Real physics (8× clock, `_scale_clock()` / `_restore_clock()`):
17. `test_a_wreck_in_front_of_drone_b_stops_it_and_the_beam_strains_and_collapses(mode)` — real physics in both harnesses, standing stub; when
    the rig enters TELEGRAPH the test adds `wreck_large.tscn` (`assault_drift` 0) at `B + advance_dir · (body_radius + 60)`; B's boosted body stops on
    it, the rig strains and reaches `collapsed(true)` with both drones alive (Assault: then `collapsed(false)`, the one attack is over). Read **at
    the collapse** (in the `collapsed` handler, review B3): B's progress along −n ≤ `60 − wreck.body_radius() + 2` (the gap to the wreck; it stopped
    short), and A's progress minus B's ≥ `sqrt((L + tol)² − L²)` (≈ 117 px: the lag at which `| |A − B| − L |` first exceeds `length_tolerance`)
    and ≤ that + `advance_speed · (strain_seconds + 2 ticks)` (review round 2, 5: the collapse timing pinned on real physics too).
    Polled by `await wait_physics_frames(4)` with an early exit; capped at 6 s of game time.
17b. `test_with_no_wreck_the_same_real_physics_attack_runs_to_its_end_unstrained(mode)` — **the wreck row's no-hazard control** (review B3): the same
    real-physics spawn with no wreck reaches BREAK with no `collapsed(true)`; a `_Sampler` child (added after the drones, so it runs last each physics
    frame) checks `separation_error() ≤ length_tolerance` on every TELEGRAPH / ADVANCE physics frame (R8.24 under the engine's own tick order).

Through a real `WaveManager` (Assault):
18. `test_assault_wave_builder_spawns_a_bound_pair_through_a_real_wave_manager` — `b.wave(0.0, [b.twin_laser_pair().at(0, -100)])`:
    `WaveBuilder.TWIN_LASER_PAIR` is the spawner path; after a few frames the container holds exactly two `TwinLaserDrone`s sharing one pair and no
    spawner; the drones' midpoint **read on their `enemy_spawned_orphan` emissions** (before any AI tick, review N5) is `cam + 2 · (0, −100)`.

`tests/integration/test_enemy_beams.gd`:
19. `test_fairness_twin_moving_wall_lets_the_player_reach_an_end` — from `twin_laser_drone_config.tres` (`advance_speed`, `rig_length`, `standoff`),
    `twin_beam.tscn` (`telegraph_seconds`, `hit_half_width`) and `_player_terms()`: `advance_speed < v_c`;
    `(L/2)/v_c + R ≤ telegraph + standoff/advance_speed`; the static rule for the twin before it moves. Boundaries: a config duplicate with
    `advance_speed = v_c` fails the first; one with `standoff` 0 fails the second; a `twin_beam.tscn` synthetic with a telegraph 0.01 s under the static
    bound fails the third.

Shared files (the §2.19 chain):
- `test_enemy_hurtbox_geometry.gd`, `test_contact_hitbox_geometry.gd`, `test_enemy_contact_damage.gd`: the drone in each `ROSTER` (with a hitbox;
  config path in the third).
- `test_wreck.gd`: `_SHIP_SCENES` gains the drone.
- `test_base_enemy.gd`: `_MIN_ROSTER_SIZE` 19 (and its comment), `_AUTHORED_CONTACT_MODES["twin_laser_drone"] = COLLISION`,
  `_REFUSING_PHASES["twin_laser_drone"] = ["TELEGRAPH", "ADVANCE", "LAUNCHED"]`; the tow row's "unlisted" fallback becomes APPROACH → ENTER → FORM
  (the drone has neither of the first two).
- `test_enemy_dual_mode.gd`: `test_twin_laser_drones_form_and_telegraph_in_both_modes(mode)` (spawn through `TwinLaserPairSpawn.spawn_pair()`, one
  TELEGRAPH with both lenses CHARGING, the beam registered as a `laser_wall` hazard exempting the pair, in Assault both drones inside
  `inner_rect()`), and the drone's `HAZARD_PROFILES` row (0.6 / 16 / 0.1).
- `test_engagement_deadline.gd`: `test_no_enemies_cleared_section_spawns_a_twin_laser_pair` (with the boundary probe of the fence row).
- Automatic sweeps (no edit): config isolation, generic lethal flow and mask 1121, transparency, single writer, signal arity, load integrity,
  UID integrity.

Gate time: 2.5 s allotted. Estimate: ~18 hand-ticked scenario runs of 3–12 s of game time (≈ 0.03–0.09 s each) ≈ 1.0 s, the wreck row
and its no-wreck control ≈ 0.3 s per mode each (row 17b runs the whole attack), the wave row ≈ 0.1 s, roster / fairness rows ≈ 0.1 s → ≈ 2.4 s
(review round 2, 4). *Measured:* the file runs in ≈ 2.0 s on its own, and `scripts/gate-time.sh` went 204.634 → 206.423 s (+1.8 s, 2518 → 2546 tests). Over budget →
share scenarios (rows 5, 6 and 13 can share a run) or the 16× clock, never cut a mode or an assertion.

## Risks

- **`Steering.arrive` overshoot at the latch** (a drone moving 200 px/s with the slot must stop on the latched slot): both drones carry the same
  feed-forward velocity, so they overshoot together and the separation holds; the length row measures it on every tick. If it does not hold, the
  TELEGRAPH hold uses `hold_position` (an internal change, logged).
- **Tick order in production**: A is added first and leads; a reversed order costs ≤ 4 px (§2.12).
- **The well row's geometry** depends on `HazardField`'s falloff; the numbers above are a first placement and the row prints the displacement.
- **The wreck row** depends on a ship body stopping on a wreck; `test_wreck.gd` already gates that for every ship scene, the drone included.
- **Docs (review N8):** `ENEMY.md` carries the IDEAS §43 design checklist (R8.25); `CLAUDE.md`'s Phase 8 gates paragraph gains the twin pair.
- **Self-reference leak** in `twin_laser_pair.gd` (the `enemy_mine.gd` trap): checked with `scripts/check-test-leaks.sh`.
- **A lambda on the rig's own signal that captures the rig** is a RefCounted cycle and leaks at exit (hit while building: the wreck row's
  `phase_changed` handler); test handlers on rig signals capture a `weakref(rig)` or the drones (Nodes), never the rig.
- **Gate time**: 2.5 s; measured before and after.

## Out of scope

Attack B, `LAUNCHED` motion, the Laser Tender and docking (t13); hub idle (`IDLE` / `NOTICING` / `RETURNING`, `start_engaged` semantics,
`AnchorIdle`) and the measured Assault exit (t14); art (t16); hub and level-1 placement (t18 / t19); re-pairing lone drones (Ph14); a rotating twin
beam (Ph11).
