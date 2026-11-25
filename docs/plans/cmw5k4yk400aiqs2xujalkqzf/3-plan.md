# Hacker Frigate: shell and movement (Phase 9 t8)

Builds epic plan §2.10 and the Hacker half of §2.15 (`docs/plans/cmug23onr001pm52w9swwophy/3-plan.md`). It does not redesign them; it pins
what they leave open and the build / test order. Context: `1-context.md`.

## Problem
Phase 9 needs an enemy that attacks the player's tools from range (t9 adds the Hijack Pulse). Before it can pulse it has to *move* like a
hacker: hang back at medium-long range on a lopsided arc that is hard to predict, slide out of the player's nose and off their flight line
instead of sitting where it is easiest to shoot, back off hard when rushed (but lose to a determined player at full cruise), stay on screen
in Assault for a 9 s life and then leave, and patrol quietly in the hub until the player comes close. After this task the Hacker exists,
does all of that, and has no weapon yet.

## Design

### 1. Files (`assault/scenes/enemies/hacker_frigate/`)
- `hacker_frigate_config.gd` — `class_name HackerFrigateConfig extends ShipConfig`, flat `@export_group`s: Movement (`max_speed` 230,
  `acceleration` 700, `max_turn_rate` 1.4), Range (`preferred_range` 720, `assault_preferred_range` 520, `range_drift` 90, `min_range` 420),
  Arc (`orbit_speed_cw` 0.18, `orbit_speed_ccw` 0.30, `reversal_min` 3.0, `reversal_max` 6.0), Cones (`nose_cone_deg` 30, `route_cone_deg`
  25, `route_min_speed` 80, `cone_escape_speed` 0.30), Break-off (`break_speed` 360, `break_lateral_weight` 0.25, `break_burst_seconds` 0.8,
  `break_exit_margin` 120, `break_max_seconds` 3.0, `break_rearm_seconds` 1.0), Assault (`view_margin` 60, `engage_seconds` 9.0,
  `exit_speed` 300), Idle (`perceive_radius` 760, `lose_radius` 1600, `notice_time` 0.35, `idle_radius` 160, `idle_speed` 0.45).
  `break_exit_margin` is the §2.10 "`min_range + 120`" written as a field so 540 is not a magic number (the only field not literally named in
  §2.10; logged). `.tres`: those values + `max_health` 120, `collision_damage` 15, `score_value` 90, `hazard_avoidance` 0.7,
  `hazard_margin` 80, `hazard_resistance` 0.4, `wreck_chance` 0.4, `wreck_size` 1. No pulse fields (t9).
- `hacker_frigate.gd` — `class_name HackerFrigate extends BaseEnemy`. `@export var config: HackerFrigateConfig = load(...tres)`. `_ready()`:
  `super._ready()`, `add_to_group("enemies")`, `_apply_config()` (health, score, contact damage, mover `max_speed` / `acceleration` /
  `max_turn_rate`, `brain.config`). Accessors `brain()`, `dish() -> Node2D`, `state_light() -> StateLight`, `body_radius()`. No
  `_physics_process`, no motion writes (single-writer sweep). No weapon, no rail fallback (it is never railed; t9 owns the pulse).
- `hacker_frigate.tscn` — root `HackerFrigate` (`CharacterBody2D`); one `CircleShape2D` r 40 shared by `CollisionShape2D`,
  `HurtBox/CollisionShape2D` (layer 512, mask 65) and `ContactHitBox/CollisionShape2D` (layer 256, mask 0, damage 15, `damage_type` 2);
  `Health` 120; `HitFlashAnimationPlayer` animating `Hull:self_modulate` (the jammer's placeholder shape); `ContactProfile` mode 1
  (COLLISION); `EnemyMover` (`constraint_mode` 0); `Brain`; `Hull` (`Polygon2D`, a ~96 × 96 px nose-down wedge, placeholder until t12);
  `Dish` (`Node2D` at the hull's spine with a small `Polygon2D` child: the antenna part t9 unfolds and t12 draws); `StateLight` as a child of
  `Dish`. No `Sprite2D` until t12 (the jammer precedent: no texture, so the transparency sweep has nothing to read), so no hit-flash shader.
  UID-less.
- `hacker_frigate_brain.gd` — below. `ENEMY.md` — behaviour, phases, numbers, the cone table.
- `assault/scenes/systems/wave_builder.gd`: `const HACKER_FRIGATE := ".../hacker_frigate.tscn"`, `func hacker_frigate() -> SpawnConfig`.

### 2. Brain (`class_name HackerFrigateBrain extends EnemyBrain`)
`enum Phase { HOLD_ARC, TELEGRAPH, PULSE, BREAK_OFF, DISENGAGE, IDLE, NOTICING, RETURNING }`; `signal phase_changed(new_phase: int)`;
`enter_phase(p)` is the one transition (test seam). Fields as the corvette: `config`, `budget`, `phase`, `start_engaged`, `patrol_anchor`,
`anchor_idle`, `idle_phase_offset`, `orbit_dir`. `tick()` = the corvette's shape: `_start()` once, budget update → DISENGAGE (deferred while
TELEGRAPH / PULSE, the corvette's `_disengage_pending`, so t9 inherits it), `_tick_anchor_idle()` when present, then the phase dispatch.

**Orbit direction convention.** `orbit_dir` +1 advances `_orbit_angle` (y-down screen: clockwise) at `orbit_speed_cw` 0.18; −1 at
`orbit_speed_ccw` 0.30. `orbit_speed(dir)` returns the one for a direction. `force_orbit_direction(dir: int)` runs `_start()` if needed,
then sets `orbit_dir = signf(dir)` (the test seam; the cone still overrides it while inside).

**HOLD_ARC** (`_tick_hold_arc(delta)`): with no target, request nothing. Else:
1. Distance `< min_range` and `_rearm_left <= 0` → `enter_phase(BREAK_OFF)` and run `_tick_break_off(delta)` in the same tick (the first
   burst / request is made on the entry tick: no braking tick), return.
2. `_arc_motion(delta, target)`: sync `_orbit_angle` to the body bearing on the first tick after any phase entry (`_orbit_synced`, as the
   corvette); `cone := _cone_edge_dir(target)` (below); if `cone != 0` (inside a cone): `orbit_dir = cone` (on the axis that is the
   current direction), angular speed = `cone_escape_speed`, the reversal clock is not decremented; else angular speed =
   `orbit_speed(orbit_dir)` and the reversal clock runs (`_reversal_left -= delta`, flip + redraw from `rng` at `<= 0`).
   `_orbit_angle += orbit_dir · speed · delta`; radius `held_range() + range_drift · sin(TAU·t/period + phase)` (the corvette's drift, period
   6–9 s from `rng`); anchor `target + RIGHT.rotated(_orbit_angle) · radius`, through `_clamp_into_view()`; request
   `Steering.orbit(pos, anchor, 0.0, 0.0, max_speed)` (radius 0 makes the anchor the centre: exactly the corvette's correction toward the
   clamped point; in Open Space the clamp is the identity, so it equals `Steering.orbit(pos, target, radius, angle, max_speed)`);
   `face_toward(target)`.
3. `_want_pulse()` returns false (t9) → `enter_phase(TELEGRAPH)` is unreachable from HOLD_ARC in t8.

**Cones** (`_cone_edge_dir(target) -> float`, config read every call, never cached): bearing `b = pos − target.position`.
- Nose: if `nose_cone_deg > 0` and `target.facing != 0`: `a = target.facing.angle_to(b)`; inside if `absf(a) < deg_to_rad(nose_cone_deg)`.
- Route: else, if `route_cone_deg > 0` and `target.velocity.length() > route_min_speed`: same with the velocity's direction and `route_cone_deg`.
- Inside a cone → return `signf(a)` (the direction of increasing `|a|` toward the nearer edge, in `_orbit_angle`'s sense, because
  `_orbit_angle` is the bearing's angle). `a == 0` (on the centre line) returns the current `orbit_dir`, so the direction is kept and the
  escape speed still applies. Outside both → 0. Read-only `in_cone() -> bool` and `cone_kind() -> StringName` (`&"nose"` / `&"route"` / `&""`)
  are set each tick for tests and `ENEMY.md`.
- Forced flips do **not** resync `_orbit_angle` to the body (the corvette pattern; the anchor's ≈ 54 px lead at 216 px/s is crossed in
  ≈ 0.12 s). If the rows' measured far-way time or exit misses the bound with every control still failing, resync on a forced flip and log it.

**BREAK_OFF** (`_tick_break_off(delta)`): entry draws `_break_side = ±1` from `rng`, `_phase_time = 0`.
- End (checked first each tick): distance `> min_range + break_exit_margin` or `_phase_time >= break_max_seconds − 1e-6` →
  `_rearm_left = break_rearm_seconds`, `enter_phase(HOLD_ARC)`. `_rearm_left` counts down in every phase. A boost still running at the end
  finishes on its own (≤ 0.8 s; committed, the mover ignores requests meanwhile).
- Open Space (no view rect): when `not mover.is_boosting()`: `mover.boost(Steering.break_contact(pos, p, v, _break_side, 1.0,
  break_lateral_weight).normalized(), break_speed, break_burst_seconds)`. So bursts chain while inside 540.
- Assault (view rect present): no boost. `dir = break_contact(..., 1.0, break_lateral_weight).normalized()` (unit); request
  `Steering.orbit(pos, _clamp_into_view(pos + dir · max_speed · BREAK_LOOKAHEAD), 0, 0, max_speed)` with `BREAK_LOOKAHEAD` 1.0 s (a point
  230 px ahead), so the move is full speed until the clamp edge, then slides along it.
- `face_toward(target)` throughout.

**View clamp** (`_clamp_into_view(p)`): identity with no view rect; else clamp into `view_rect().grow(−(view_margin + VIEW_CLAMP_PAD))`,
`VIEW_CLAMP_PAD` 8 px, and set `view_clamp_bound = (clamped != p)` (read-only, for the "never binds" assertion). The pad exists because
`Steering.orbit`'s 60 px/s correction floor makes a body parked on its anchor wobble ±2.6 px (`60² / (2·700)`); without it a hull parked on
the clamp line would sit 2–3 px outside `grow(−60)`, the bound the rows assert. Logged in DECISIONS.

**TELEGRAPH / PULSE**: stubs. Entry turns `StateLight` OFF; the tick goes straight back to HOLD_ARC (or DISENGAGE when pending). `accepts_tow()`
false in both.

**DISENGAGE**: the corvette's `_enter_disengage()` / `_tick_disengage()` verbatim (release constraint, `max_speed = exit_speed`, nearest edge of
`projectile_world_rect()` + 64 px overshoot, curve at `min(max_turn_rate, acceleration / exit_speed)`, free when strictly outside).

**Hub idle**: `AnchorIdle(patrol_anchor, perceive_radius, lose_radius, notice_time, idle_radius)` when `not budget.active and not
start_engaged`. IDLE: `mover.orbit(patrol_anchor, idle_radius, idle_phase_offset + orbit_dir · idle_speed · k · _phase_time, max_speed)` with
`k = orbit_speed(orbit_dir) / orbit_speed_ccw` (0.45 rad/s one way, 0.27 the other: "asymmetric like its combat arc", logged). NOTICING:
stop, face the player; COMBAT from NOTICING → HOLD_ARC (there is no APPROACH: the orbit's anchor correction closes the range at
`max_speed`). RETURNING: `arrive(patrol_anchor)`. `on_suspended()`: `anchor_idle = null`, light OFF.

### 3. Exit keys (`tests/helpers/ph9_exit_keys.gd`, no `class_name`)
The Ph8 file's shape: `const CAP := 20.0`, `SLOW_START := 10.0`, `hacker_exit(host) -> Dictionary` =
`PROBE.worst_disengage(host, load(HACKER_SCENE_PATH), HackerFrigateBrain.Phase.DISENGAGE, [config.max_speed, 10], CAP, corridor_starts(host),
prepare_probe)`; `corridor_starts(host)` built exactly as Ph8's; static `prepare_probe(ship)` takes every node out of group `player` (Ph7
gate-time rule 3; the Hacker's DISENGAGE never reads the player, pinned by a bit-identical row). t9's Disruptor and t14 add their keys here.

### Alternatives rejected
- Inheriting `MissileCorvetteBrain` — §2.10 says copy, and the phase enums differ.
- A real `Sprite2D` placeholder texture — the sweep and t12 would then have to replace a texture; the jammer's `Polygon2D` precedent is cheaper.
- Recomputing the break-off direction every tick in Open Space — §2.10 makes it a committed burst re-issued at its end.

## Build sequence
1. Config script + `.tres`, brain skeleton (phases, enter_phase, stubs), root script, scene, `WaveBuilder` entry — the scene loads (project-load
   sweep, roster gates).
2. Roster gates and tow table (`test_enemy_contact_damage.gd` 15, `test_contact_hitbox_geometry.gd`, `test_enemy_hurtbox_geometry.gd`,
   `test_base_enemy.gd` `_MIN_ROSTER_SIZE` 24 + `_AUTHORED_CONTACT_MODES` COLLISION + `_REFUSING_PHASES` `["TELEGRAPH", "PULSE"]` with the
   unlisted-phase fallback extended to HOLD_ARC, `test_enemy_dual_mode.gd` `HAZARD_PROFILES` + one spawn row, `test_engagement_deadline.gd`
   ENEMIES_CLEARED guard row for `WaveBuilder.HACKER_FRIGATE`).
3. `test_hacker_frigate.gd` structure + HOLD_ARC rows (range, arcs, reversals) → implement HOLD_ARC.
4. Cone rows → implement the cones; record measured exits.
5. Break-off rows → implement BREAK_OFF.
6. Assault rows, `ph9_exit_keys.gd`, DISENGAGE → implement clamp and exit.
7. Hub idle rows → implement idle.
8. Docs (`updating-project-docs`), DECISIONS "built in t8", gate-time row, `verify.sh`, `check-test-leaks.sh`.

## Test plan (`tests/integration/test_hacker_frigate.gd`; hand-ticked at 1/60, both harnesses unless noted, label-parameterised)
Helpers: `_spawn(h, pos, props := {}, seed := 1)` writes `engage_seconds = 1000` and then `props` onto `hacker.config` after
`instantiate()` and before `add_child` (`start_engaged = true`, physics off). The budget is live in the Assault harness and would end every
long row at 9 s (the Support Ship tests' precedent); only the Assault-life rows pass `engage_seconds` 9.0 back in, and the probe uses the
shipped scene. **Assault placement** for every Assault row except the life row: the player at (640, 620) (centred, 100 px above the view's
bottom edge), facing UP, the hull started on the 520 ring at the bearing the row names (0° = straight above). The 520 ring fits inside the
clamp rect up to ≈ 93° from straight up, so each row keeps the hull inside that sector. `_tick()` = `_physics_process(dt)` then `position = before + velocity·dt`; the test moves the player
itself (`position += velocity·dt`).
- **Structure**: one r 40 circle shared by body / hurtbox / contact box; `ContactProfile` COLLISION, contact damage 15; config applied to the mover;
  `Dish` + `StateLight` present; `sprite_forward_angle` PI/2; in `enemies`; `WaveBuilder.hacker_frigate()` points at the scene; the phase enum's
  order pinned (append-only).
- **Holds range** (both; cones 0, still player). Open Space: start on `held_range()`, shipped reversals and drift, 20 s inside
  `held_range() ± (range_drift + 60)`; start 1100 px out: inside the band within 3 s and every tick after, to 20 s. Assault: start at −30°,
  reversals held, `force_orbit_direction(+1)` (0.18 rad/s: ≤ 62° of travel), 6 s in band; far start 900 px straight above (y −280, inside the
  corridor): in band within 3 s, then to 6 s. Control (both): the far start with `max_speed` 1 → never inside. The far start is the row's
  teeth (a ship that never moves passes the on-ring half).
- **Asymmetric arcs** (both; cones 0, `range_drift` 0, reversals held): `force_orbit_direction(+1)` and, on a fresh instance, `(−1)`; after a
  1 s settle the **hull's bearing** (not the target angle) turns at 0.18 / 0.30 ± 0.01 rad/s over the next 3 s (Assault starts at −40° for
  +1 and +40° for −1, so 4 s ends within 69° of straight up). Control: `orbit_speed_ccw = orbit_speed_cw` → the two rates differ by < 0.01.
  **Reversals** (both; cones 0; Assault start straight above): seeds 1–4, shipped reversal times, 10 s: ≥ 1 sign change of `orbit_dir` per
  seed, and the brain never left HOLD_ARC (a break-off would pause the clock). Control: reversal 30 s → none.
- **Nose cone** (Open Space at 720; Assault at 520): the §2.10 cone-row procedure. Cases `cw_far` (+1, 0.18, far way), `ccw_far` (−1, 0.30,
  far way), `cw_near` (+1, near way). Main (30°): exit through the near edge (sign of the exit offset = −s) within 2.2 s (720) / 1.9 s (520);
  far-way time ≤ 0.5 s; re-snap 3.5 s after the exit (same case rule, read off the current motion) exits again within the bound. Control (0°):
  both far-way cases still inside ± 30° at the bound. Assault: player centred 100 px above the view's bottom edge; far-way cases start
  straight above; the near-way case starts 45° to the side it moves away from (it never turns back, so its whole run — warm-up, exit, 3.5 s,
  exit — is ≈ 96° of arc; started 45° off it ends ≈ 51° past straight up, inside the ≈ 93° the clamp rect allows). Each tick: hull inside `view_rect().grow(−60)` and
  `view_clamp_bound == false`. The measured exits are printed (`gut.p`) and recorded in DECISIONS.
- **Route cone** (Open Space, 720): player at 100 px/s, facing ⟂ the bearing, `nose_cone_deg` 0; route 25°: same three cases, exit within 1.8 s
  through the near edge, far-way time ≤ 0.5 s. Control (route 0°): both far-way cases inside at 1.8 s. **Outrun**: player cruising at 360 px/s
  directly away: distance exceeds `held_range() + range_drift` within 5 s (documented limit).
- **Break-off** (Open Space): rusher at 300 px/s re-aimed at the hull every tick, from 600 px, 4.0 s, then stops: BREAK_OFF within one tick of
  the first (post-move) reading inside 420 (the brain reads the pre-move distance); distance ≥ 360 always; HOLD_ARC within `(540 − d_min)/322 + 1.0 s` of the stop. Control `min_range` 0: distance < 340 at some
  tick. **Chase** 420 px/s: the first BREAK_OFF lasts 3.0 s ± 1 tick, the next starts ≥ 1.0 s after it ended. Controls: `break_max_seconds`
  100 → still in BREAK_OFF at 3.1 s; `break_rearm_seconds` 0 → the next starts < 1.0 s after. Also: on a burst's first tick the radial speed
  against a 300 px/s rusher is 322 ± 2 px/s (the √1.25 figure; later in a burst the line of sight swings and the radial grows).
- **Break-off (Assault)**: hull at view centre-top, player 300 px below moving up at 200 px/s: BREAK_OFF starts, no `mover.is_boosting()` ever,
  hull inside `grow(−60)` every tick, back to HOLD_ARC by 3.0 s. Control `view_margin` −2000: the hull leaves `grow(−60)`.
- **Assault life**: player at the view centre (the 520 ring pokes out of the view top and bottom, so the clamp binds): hull inside `grow(−60)`
  every tick for 9.0 s; DISENGAGE on the tick the budget expires (540 ± 1); freed within the measured exit (+ 1 tick). Control `view_margin`
  −2000: the hull leaves `grow(−60)` in the 9 s.
- **Measured exit**: `PH9.hacker_exit(self)` in `before_all()`; 2166 runs, 0 capped, < 10 s; a second call is a memo hit; the probe hook
  leaves one exit bit-identical; a source sweep finds no `worst_disengage(` naming `HackerFrigateBrain` outside `ph9_exit_keys.gd`
  (synthetic boundary fires).
- **Hub idle** (Open Space, `start_engaged` false). The player is re-placed **every tick** at a fixed distance from the **hull** along a
  fixed direction (the hull circles 160 px round the anchor, so an anchor-relative distance would swing ± 160): at 900 px for 4 s → IDLE every
  tick, hull inside `idle_radius + 40` of the anchor; then at 740 px → NOTICING on that tick, HOLD_ARC 0.35 s (21 ticks ± 1) later. Control:
  at 780 px for 4 s → still IDLE. Assault cold start: no idle (HOLD_ARC).
- **Stubs**: `enter_phase(TELEGRAPH)` / `PULSE` → back to HOLD_ARC on the next tick; never entered from HOLD_ARC in 10 s; tow refused in
  both. Deferral: the budget expiring while in TELEGRAPH → DISENGAGE on the next tick, not HOLD_ARC (control: from HOLD_ARC, DISENGAGE on
  the expiry tick itself).
- **Suspension**: `suspend_ai()` → `on_suspended()` turns the light OFF and drops `anchor_idle`.
- **Roster** (§2.15): the gate files above, and the automatic sweeps.

## Risks
- The measured cone exits differ from the plan's simulation (e.g. the un-synced anchor). Bounds kept; the fix is the logged resync above; a
  bound that cannot be met with failing controls → `Result: ESCALATE`.
- Gate time: the corridor probe is 2166 hand-ticked runs (Ph8 tender ≈ the same). Allotment 4.0 s.

## Out of scope
TELEGRAPH / PULSE, the dart, `_want_pulse()`, pulse config fields (t9); the Disruptor (t10); art (t12); hub / level placement (t13 / t14).
