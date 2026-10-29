# t6 — A stationary defense turret: shell, `TurretMount` + burst cannon, `AssaultDrift`

Epic `cmug23ona0015m52w4t1m73bc` (Phase 8), plan task t6. Builds epic plan §2.7 and §2.19 (approved). This task plan only fixes what §2.7
leaves open (the mount's internal cycle, file split, scene layout, test geometry). Context: `1-context.md`. **Revision 3** (APPROVED in round 3, with the two numeric fixes A1 (clock comparisons carry the 1e-6 slack `EnemyBeam` uses, so 24 / 132
ticks hold) and A2 (row 3 below) applied) answers
round 2 of `4-review.md` (R2-B1 → `_weapon_tick` / `_telegraph_done` and row 16; R2-B2 → row 3; N2-1..N2-4 inline). Revision 2 answered round 1
(B1 → row 3, B2 → the cooldown clock and row 5, B3 → per-row estimate, rows merged and early exits, N1–N11 inline).

## Problem

Phase 8 needs static gun emplacements. Today every enemy is a ship that flies, and nothing in the roster is a fixed point that turns a head,
tracks the player and fires. The player should meet a turret that:
- sits still with its head slowly scanning;
- notices them with a blink when they come close (Open Space) or when it scrolls into view (Assault);
- swings its head round at a readable turn rate;
- leads its shots partway, so a strafing player is threatened but can dodge;
- fires 4-round bursts with a charge cue;
- holds fire behind cover;
- goes dark and droops when unpowered.

In Assault it scrolls down the corridor like wreckage. A turret that scrolls off the bottom never breaks the combo.

The aiming and firing part (`TurretMount`) must not know its host, so phase 10 can bolt the same mounts onto big ships.

## Design

### Files (all new unless marked)
```
assault/scenes/enemies/defense_turret/
  defense_turret.tscn, defense_turret.gd           DefenseTurret extends BaseEnemy
  defense_turret_brain.gd                          DefenseTurretBrain extends EnemyBrain
  defense_turret_config.gd, defense_turret_config.tres
  turret_mount_slot.gd                             TurretMountSlot extends Marker2D
  ENEMY.md
  mounts/turret_mount.gd                           TurretMount extends Node2D (the cycle; abstract weapon hooks)
  mounts/burst_cannon_mount.gd, burst_cannon_mount.tscn   BurstCannonMount extends TurretMount
  mounts/turret_mount_scenes.gd                    TurretMountScenes
global/components/assault_drift.gd                 AssaultDrift extends Node
assault/scenes/systems/wave_builder.gd             (edit) DEFENSE_TURRET + defense_turret()
```
`TurretMountSlot` lives next to the turret (it belongs to hosts, not to mounts). It is a separate `class_name` file so a later host (the heavy emplacement,
Ph10 ships) authors the same marker.

### `TurretMount` (the Ph10 seam) — the cycle in the base, the weapon in a subclass
The epic plan names one `TurretMount` class carrying `Variant`, `Phase` and the methods. Later tasks add variants "on the TurretMount cycle"
(t7 sweep / beam cannon / lance, t8 rockets / ring). So the base class owns the cycle, the aim, the rotation, the scan and the cooldown. Each
variant is a subclass with its own script and scene that overrides a few hooks. The rejected alternative is one script with `match variant`
everywhere, which would make t7/t8 edit every method.

Base exports (each mount scene authors its own values):
- `turn_rate` 2.0 rad/s, `fire_range` 700 (renamed from §2.7's `range`, which shadows the built-in `range()`; review N9), `lead_blend` 0.6,
  `fire_cone_deg` 8, `scan_arc_deg` 90, `scan_speed` 0.4, `cooldown_seconds` 2.2;
- `rest_bearing_deg` 90. Godot angle convention: 0 = +X, 90 = straight down, the Assault "towards the player" default. It is **local to the
  mount's parent**, so a rotating Ph10 hull scans and droops relative to itself. The host copies the slot's value onto it before `setup()`.

Base API (as §2.7):
- `setup(host, pools, owner_group)`, `tick(delta, target: TargetInfo, can_fire: bool)`, `scan(delta)`, `power_down()`,
  `pool_specs() -> Array[Dictionary]`, `muzzle_position()`, `aim_error()`, `phase()`;
- plus `aim_point() -> Vector2` (the last point aimed at, read by the lead row), `owner_group() -> StringName`,
  `fires_past_cover() -> bool` (false; the rocket battery says true in t8), `is_committed() -> bool` (false; the lance in t7),
  `cooldown_left() -> float`;
- `var rng: RandomNumberGenerator`: the host assigns its brain's `rng` before `setup()`, so the scan's phase offset comes "from the host's rng".
  If null, the mount makes its own randomised one;
- `var telegraph_gate: Callable` (review N3, N2-1): empty by default (always allowed). Otherwise `telegraph_gate.call() -> bool`, with the host
  binding itself (e.g. `group.request_telegraph.bind(turret)`), so a t8 `TurretGroup` can hold the TRACK → TELEGRAPH step (the §2.10 stagger)
  without the mount ever reading its host's type. It is consulted **last**: only once the cooldown, `_wants_telegraph()` and the cone checks
  have all passed, so a grant (which uses up the group's 0.3 s stagger window) is never wasted on a mount that could not fire. On a refusal the
  mount stays in TRACK and asks again next tick.

Virtual hooks (the subclass surface, review N3):

| Hook | Base default | Overridden by |
|---|---|---|
| `_aim_point_for(target)` | projectile lead (below) | t7 beams: `P + v · lead_horizon · lead_blend` |
| `_shot_speed()` | 0 | burst: `round_speed` |
| `_tracks(phase, phase_clock) -> bool` | true | t7: the beam cannon and sweep false from TELEGRAPH on; the lance true only for its first part |
| `_wants_telegraph(target, can_fire) -> bool` | `can_fire`, target within `fire_range` of the muzzle, and `aim_error() ≤ fire_cone_deg / 2` | t8 ring: `trigger_range`, no cone |
| `_telegraph_seconds()` | 0 | burst: `charge_seconds` |
| `_telegraph_done() -> bool` | `phase_clock ≥ _telegraph_seconds()` | t7 beams: `beam.phase() == ACTIVE` (one clock decides the step) |
| `_weapon_tick(delta)` | — | t7 / t8: the owner-ticked beam / ring (`EnemyBeam.tick()`, `EnergyRing.tick()`). Called **once per `tick()` and per `scan()` in every phase, UNPOWERED included**, after the cycle step, so a telegraph, an ACTIVE and a FADE all run on the weapon's own clock and a fading beam finishes in COOLDOWN, SCAN and UNPOWERED (review R2-B1) |
| `_on_telegraph_start()` | — | t7 beams: `start()` the beam |
| `_fire_tick(delta, can_fire) -> bool` (true = done) | true | every variant |
| `_stop_weapon()` | — | burst: stop the clock; t7 beams: cancel / fade |
| `pool_specs()` | `[]` | burst, t8 rockets |

Signals:
- `phase_changed(phase: int)`;
- `round_fired(projectile: Node2D)`, so rows can see each launched projectile.

Muzzle: a `Muzzle` `Marker2D` child of the mount scene on local +X (the emitter convention). `muzzle_position()` is its global position.

**Rotation.** Only `rotation` of the mount itself is written (`rotation = rotate_toward(rotation, desired, turn_rate · delta)`). `desired` is
the aim bearing minus the parent's `global_rotation`, so a rotating Ph10 host works unchanged. `aim_error()` is
`absf(angle_difference(global_rotation, (aim_point − global_position).angle()))`. It is measured from the **pivot** (the mount's own position),
and every round leaves along the mount's facing.

**Aim (R8.9).** For projectile variants, `aim_point = P.lerp(target.intercept(muzzle, _shot_speed()).point, lead_blend)`. `intercept` already
falls back to `P`.

**The cooldown is its own clock (review B2).** `_cooldown_left` is set to `cooldown_seconds` when a FIRE ends. It counts down on every
`tick()` / `scan()` in every phase, SCAN included, and TRACK → TELEGRAPH is refused while it is > 0. So a turret whose perception flickers
(an Assault turret at the edge of a panning view) can never fire faster than its exports. Only `power_down()` clears it. That keeps the pool
derivation, charge + burst + cooldown, a true minimum period.

**The cycle** (`Phase { SCAN, TRACK, TELEGRAPH, FIRE, COOLDOWN, UNPOWERED }`), run by `tick()`:

| Phase | Each tick | Leaves to |
|---|---|---|
| SCAN | `tick()` with a target enters TRACK, then runs TRACK in the same tick | — |
| TRACK | aim; turn if `_tracks()` | TELEGRAPH when `_cooldown_left ≤ 0`, `_wants_telegraph()` and `telegraph_gate` allow it (checked after this tick's turn); then `_on_telegraph_start()` |
| TELEGRAPH | aim + turn if `_tracks()` | TRACK if `can_fire` turns false (charge cancelled, `_stop_weapon()`); FIRE when `_telegraph_done()`, then `_fire_tick(0, can_fire)` in the same tick (the burst's first round leaves on the tick the charge ends) |
| FIRE | aim + turn if `_tracks()`, `_fire_tick(delta, can_fire)` | COOLDOWN when it returns true; `_cooldown_left = cooldown_seconds` |
| COOLDOWN | aim + turn if `_tracks()` | TRACK when `_cooldown_left ≤ 0` (the TELEGRAPH check waits for the next tick) |
| UNPOWERED | ease toward `rest_bearing_deg` at `turn_rate` (the droop) | never (this phase) |

**Tick order** (review N2-3), each `tick()` / `scan()`:
1. `_cooldown_left -= delta` (a cooldown set on tick k first counts on tick k + 1).
2. `phase_clock += delta` for the phase in force (a phase entered on tick k reads 0 for the rest of tick k and `DT` on tick k + 1). So a 0.4 s
   charge entered on tick k fires on tick k + 24, and a 2.2 s cooldown set on tick k frees TRACK on tick k + 132.
3. The phase step in the table, with aim and turn first.
4. `_weapon_tick(delta)`.

**Any exit from FIRE except `power_down()` starts the cooldown** (review N2-2): the burst finishing, `can_fire` turning false mid-burst, or a
`scan()` (perception lost) mid-burst. So a cut burst plus a re-perception can never put more than one burst's rounds inside one cooldown.

Other inputs:
- `tick()` with no target (`has_target` false) behaves as `scan()`.
- `scan(delta)` from any live phase: `_stop_weapon()`, then SCAN, then one scan step. The cooldown keeps counting.
- The scan is a triangle sweep. An offset in `[-arc/2, +arc/2]` moves at `scan_speed` and bounces at the edges, and the mount turns toward
  `rest + offset` at `turn_rate`. Since `scan_speed` < `turn_rate`, once it is on the arc it follows it exactly.
- `setup()` draws the start offset and direction from `rng` and sets `rotation` to `rest + offset`, so a fresh turret is already on its arc.

`power_down()` is idempotent:
- the subclass `_stop_weapon()` runs. The burst cannon stops its `BurstClock`, so there is no further `acquire()`; rounds already in flight
  belong to the pool. t7's beams cancel or fade in their own `_stop_weapon()`;
- the cooldown is cleared;
- the phase becomes UNPOWERED. Every later `tick()` / `scan()` only droops.

**`BurstCannonMount`** (`burst_cannon_mount.gd` + `.tscn`):
- Exports `charge_seconds` 0.4, `burst_count` 4, `burst_gap` 0.12, `round_speed` 300, `round_scene` = `pulse_round.tscn`. The scene also
  authors the base values above.
- `pool_specs()` returns `[{name = "PulsePool", scene = round_scene, size, persist = false}]`.
  - `size = EnemyRounds.pool_size_for(burst_count, round max_time, charge_seconds + (burst_count − 1) · burst_gap + cooldown_seconds)`.
  - The round's `max_time` is read without instantiating the scene: `EnemyBeamScenes.export_of_scene(round_scene, &"max_time", 18.0,
    ^"ProjectileLifetime")`. `pulse_round.tscn` authors the override (review N7).
  - That gives 4 · ceil(8 / 2.96) = 12.
- `_fire_tick(delta, can_fire)`:
  - On its first call, it starts `BurstClock(burst_count, burst_gap)` and advances it by 0, so the first round leaves on the tick the charge
    ends.
  - Each later tick it calls `advance(delta)`. Each due shot launches only while `aim_error() ≤ fire_cone_deg / 2`. Otherwise it is **held**
    (dropped and counted in `shots_held`), so no round ever leaves outside the cone.
  - `can_fire` false stops the burst.
  - It is done when the clock is no longer running.
- Launch: `pools["PulsePool"].acquire(muzzle_position())`, then `speed = round_speed`, `set_direction(Vector2.RIGHT.rotated(global_rotation))`,
  then emit `round_fired`. A null `acquire()` (exhausted) is counted in `shots_refused`.
- Placeholder art: `_draw()` draws a head disc (r 13) and a barrel along +X to the muzzle (x 28). It is code-drawn, so the sprite-transparency
  sweep has nothing to read. The art task replaces it.

**`TurretMountScenes`**: `scene_for(variant)` returns the BURST_CANNON scene now, and null with no error for unbuilt variants.
`export_of(variant, property, fallback, node_path = ^".")` delegates to `EnemyBeamScenes.export_of_scene()`, which is generic over any
`PackedScene`.

### `DefenseTurret` (root)
Scene `defense_turret.tscn`, node order:
- `DefenseTurret` (CharacterBody2D, layer 1 / mask 1 — the enemy-root default);
- `CollisionShape2D` (CircleShape2D r 28, one SubResource);
- `HurtBox` (layer 512, mask 65), with a `CollisionShape2D` on the same SubResource;
- `Health` (90);
- `HitFlashAnimationPlayer`: RESET and a 0.2 s `hit` animation on `.:self_modulate` (a white flash of the code-drawn base);
- `ContactProfile` (mode NONE), and **no `ContactHitBox`**;
- `Brain` (`DefenseTurretBrain`);
- `AssaultDrift`;
- `MountSlots` (Node2D) holding `Slot0` (`TurretMountSlot`, BURST_CANNON, `rest_bearing_deg` 90, `turn_rate_override` −1);
- `StateLight` at (0, 0), last so it draws over the head.

Script:
- `@export var config: DefenseTurretConfig = load(...)`; `@export var variant := -1`.
- `_ready()` runs in this order:
  - `super._ready()`, then `add_to_group("enemies")`;
  - apply config: health, score, the drift's `speed = assault_drift_speed`, `brain.config`;
  - resolve the owner group: the group's, or `&"turret_<instance id>"`, joined with `add_to_group`;
  - build mounts. For each `TurretMountSlot` child of `MountSlots` (index i):
    - pick the variant: the slot's, or `variant` for slot 0 when ≥ 0;
    - get the scene from `TurretMountScenes.scene_for`. A null scene means the variant is not built yet: `push_warning` and skip the slot;
    - instantiate, set `rest_bearing_deg` from the slot, set `turn_rate` from `turn_rate_override` when ≥ 0, set `rng = brain.rng`;
    - `slot.add_child(mount)`;
    - for each pool spec add a `BulletPool` (`bullet_scene`, `pool_size`, `persist_after_owner_death`) as a **root child** named
      `"%s_%d" % [spec.name, i]`, so the pool's `_ready()` resolves the container as the turret's parent;
    - `mount.setup(self, {spec.name: pool}, owner_group)`;
  - `brain.bind_mounts(mounts)`.
- `set_powered(on)`: the first `false` sets `_powered = false` and calls `brain.power_down()`. That makes the brain UNPOWERED, which calls every
  mount's `power_down()` and turns the light OFF. Any later call, including `true`, is ignored. `is_powered()` reads the flag.
- `set_turret_group(group)` is meant to be called before `add_child`. It stores the group and joins `group.owner_group` at `_ready()`, read
  duck-typed (`group.get("owner_group")`), because `TurretGroup` arrives in t8. Also: `turret_group()`, `owner_group()`, `mounts()`.
- `is_laser_blocking()` → false. `_draw()` draws the base: a dark disc of r 30 with a rim.

### `DefenseTurretBrain`
- `Phase { SCAN, NOTICING, ENGAGED, UNPOWERED }` (append-only), `signal phase_changed(new_phase: int)`, `enter_phase(p)`, `phase`, `config`.
- Exports: `start_engaged := false`, a test seam (it starts ENGAGED; Assault view gating still applies).
- `bind_mounts(mounts)` takes the list from the root.
- `tick(delta)`, with `target = TargetInfo.player(tree)`:
  - UNPOWERED: `mount.tick(delta, target, false)` for each mount (they only droop), then return.
  - `perceived`:
    - Assault (`EnemyWorld.has_view_rect`): `target.has_target and view_rect().has_point(actor.global_position)`;
    - Open Space: `target.has_target and d ≤ (lose_radius if phase in {NOTICING, ENGAGED} else perceive_radius)`.
  - SCAN: if perceived → NOTICING (+ `blink_once()`, clock 0). Each mount `scan(delta)`.
  - NOTICING: not perceived → SCAN; clock ≥ `notice_time` → ENGAGED. Each mount `scan(delta)`.
  - ENGAGED: not perceived → SCAN. Otherwise:
    - `sees = can_see_player() if Engine.is_in_physics_frame() else true` (hand-ticked rows never cast);
    - `can_fire = sees or mount.fires_past_cover()`, per mount;
    - `mount.tick(delta, target, can_fire)`.
  - Then the light.
- `power_down()`: enter UNPOWERED, every mount `power_down()`, light OFF.
- `accepts_tow()` → false (moot: no mover).
- Light: CHARGING if any mount is in TELEGRAPH; else COMMIT if any `is_committed()`; else ARMED if any mount is in TRACK / FIRE / COOLDOWN
  with its `can_fire`; else OFF. It is only written when it differs from `get_state()`, so NOTICING's blink is not cut short.

  **Reading:** §2.7 lists "FIRE or TRACK with `can_fire`". COOLDOWN is added, so the light does not drop out for 2.2 s between bursts of a turret
  that is still a live threat. Recorded in DECISIONS.

### `DefenseTurretConfig` + `.tres`
Flat, `extends ShipConfig`.

| Group | Field | Value |
|---|---|---|
| Defense | `max_health` | 90 |
| Defense | `collision_damage` | 0 |
| Scoring | `score_value` | 60 |
| Scoring | `counts_as_escape` | **false** |
| Perception | `perceive_radius` | 900 |
| Perception | `lose_radius` | 1100 |
| Perception | `notice_time` | 0.3 |
| Assault | `assault_drift_speed` | 60 |
| Hazards | `hazard_avoidance` | 0 |
| Hazards | `hazard_margin` | 0 |
| Hazards | `wreck_chance` | 0 |

### `AssaultDrift` (`global/components/assault_drift.gd`)
- `@export var speed := 60.0`. `_physics_process(delta)` calls `step(delta)`.
- `step(delta)`, only with a parent `Node2D` in the tree and `EnemyWorld.arena(tree) != null`: `parent.global_position.y += speed · delta`.
  Then, if `has_projectile_world_rect` and `parent.global_position.y > projectile_world_rect().end.y`, `parent.queue_free()`. A parent already
  queued is skipped.
- `velocity()` returns `(0, speed)` with an arena, ZERO otherwise.
- It writes only the parent's position, and never names `ArenaCamera`.

### `WaveBuilder`
`const DEFENSE_TURRET := "res://assault/scenes/enemies/defense_turret/defense_turret.tscn"`,
`func defense_turret() -> SpawnConfig: return SpawnConfig.new(DEFENSE_TURRET)`.
A variant is set with `.prop("variant", TurretMount.Variant.X)`.

## Build sequence
1. Tests first: `tests/integration/test_defense_turret.gd` (every row below) plus the roster-gate edits. Watch them fail (missing scene and
   classes).
2. `AssaultDrift`, `DefenseTurretConfig` + `.tres`, `TurretMountSlot`.
3. `TurretMount`, `BurstCannonMount` + scene, `TurretMountScenes`.
4. `DefenseTurretBrain`, `DefenseTurret` + scene.
5. `WaveBuilder`, the bullet-lifetime speed row, `ENEMY.md`.
6. Run the turret file, then the roster gates, then `scripts/check-test-leaks.sh`, then `scripts/gate-time.sh`, then `verify.sh`.
7. Docs (`updating-project-docs`), DECISIONS "Phase 8, built in t6" (including: `range` → `fire_range` for t9 and §2.10's coverage rule;
   the hook table; the cooldown clock; COOLDOWN lit ARMED; the separate tow row), the `tests/README.md` gate-time row.

## Test plan — `tests/integration/test_defense_turret.gd`

Every row is parameterised on `use_parameters(["open_space", "assault"])` unless marked.

**How rows are driven.**
- Rows are hand-ticked: `turret.set_physics_process(false)`, the drift's too, and they step `turret._physics_process(DT)` — the real brain →
  mount path.
- Rows that need ENGAGED from the first tick set `brain.start_engaged`.
- In Assault rows the drift is not stepped unless the row is about drift, so the turret stays where it was placed.
- Tuning is read through `TurretMountScenes.export_of(BURST_CANNON, …)` with the script's `get_property_default_value()` as the fallback
  (review N8), and from the shipped `.tres`; no tuning number is typed.
- Angles are compared with `angle_difference` (review N1).
- A "within X s" wait stops on the event and uses X only as a timeout (review B3).

**Placement.**
- Turret at T = (640, 300).
- Player stub at (640, 600): 300 px away, inside the view and inside range.
- Assault rows keep everything inside the 1280 × 720 view unless the row is about the view.

Rows:
1. **Static shell, rotation and turn rate** (old rows 1 + 2 merged, review B3 / N1 / N10).
   - The turret is `start_engaged`; the stub sits at T + (0, −300), **opposite** the rest bearing of 90°.
   - Every tick, `|angle_difference(Δ mount.rotation)| ≤ turn_rate · DT + 1e-4`.
   - Aim error drops below 1° within `π / turn_rate + 2 · DT` of the first tick.
   - The stub then circles T at 300 px, one turn in 3 s.
   - Throughout: the root `rotation` is exactly 0, the root `global_position` is unchanged (both harnesses: the drift is not stepped), and
     `MountSlots` and `Slot0` transforms are unchanged. So the mount is the only thing that rotated.
   - Static checks:
     - `_mover == null`;
     - `is_ai_driven()` false and `accept_tow()` false;
     - `is_laser_blocking()` false;
     - in group `enemies`;
     - `contact_profile.mode == NONE`;
     - no `ContactHitBox`.
2. **Partial lead.**
   - The stub starts at T + (−250, 300) and crosses at (200, 0) px/s; it is re-placed each tick by `p += v · DT`, with `velocity` set on the
     body.
   - At tick 30, `aim_point()` equals `P.lerp(intercept(muzzle, round_speed).point, lead_blend)` within 2 px. The expected value comes from a
     fresh `TargetInfo.of(stub)` with the mount's own `muzzle_position()`.
   - Boundary: the point is more than 20 px from both `P` and the full intercept, so neither "no lead" nor "full lead" passes.
3. **No round outside the cone** (review B1, R2-B2).
   - The turret is `start_engaged`; the stub **stands** 300 px below, so the bearing change is exactly the jump (review round 3, A2).
   - At the **first** burst's first round, the stub is teleported round T by `1.6 · turn_rate · burst_gap` rad of bearing (about 22°, read from
     the exports). The 2nd shot is then due while the error is still ≥ 6.7° (held), and the mount is back inside the 4° half-cone for the 3rd.
   - At each `round_fired`:
     - `mount.aim_error() ≤ fire_cone_deg / 2 + 1e-4` rad, measured from the pivot, the quantity the mount gates on;
     - the round's heading (`_direction`) equals the mount's facing within 1e-4 rad.
   - Boundary:
     - `shots_held > 0` after the jump, so a due shot was held, not fired wide;
     - at least one round leaves after the jump within the same burst (the 3rd), so the gate also lets a round through near the cone edge.
   - The row ends at the burst's end, with a 3 s timeout.
4. **Burst cadence.**
   - A standing stub; record the `round_fired` times until the third burst's first round, with a 6.5 s timeout.
   - Bursts are exactly `burst_count` rounds.
   - In-burst gaps are `burst_gap` ± 1 tick.
   - From a burst's last round to the next burst's first: ≥ `cooldown_seconds + charge_seconds − 1e-6`, and ≤ that + 2 ticks.
   - The first round comes ≥ `charge_seconds − 1e-6` after TELEGRAPH begins (`phase_changed`; review N6).
5. **Perception flicker keeps the cooldown, Open Space only** (review B2, N2-2). Two cases:
   - (a) After the first burst's last round, the stub moves beyond `lose_radius` for 0.2 s (the brain goes to SCAN), then comes back. The next
     first round is ≥ last round + `cooldown_seconds + charge_seconds − DT`.
   - (b) Mid-burst, right after its second round, the same 0.2 s drop. The burst is cut at 2 rounds, and the next first round is ≥ the cut +
     `cooldown_seconds + charge_seconds − DT`.
   - Control: in both, `cooldown_left()` is still > 0 when perception returns.
6. **Scan.**
   - The player is removed from group `player`; 9 s of ticks.
   - Throughout: `|angle_difference(mount.rotation, rest)| ≤ arc/2 + 1e-3`, and `|Δ| ≤ scan_speed · DT + 1e-4`.
   - The swept span reaches ≥ arc − 1°.
   - Two brain seeds give different start offsets, which shows the offset comes from the rng.
7. **Perception, Open Space only.**
   - At 899 px: NOTICING on the first tick, with the light blinking (CHARGING shown, `get_state()` OFF). ENGAGED after `notice_time`, ± 1 tick.
   - At 901 px: still SCAN after 1 s.
   - Once ENGAGED, moved to 1099 px it stays ENGAGED; at 1101 px it goes to SCAN.
8. **Assault view gate, Assault only.**
   - The turret starts at y = −90 (the view top is 0), with `start_engaged`, and the real drift steps each tick.
   - No `round_fired` while the turret's centre is above `view_rect().position.y`.
   - A round within 4 s of entering, stopping on the first.
9. **Drift.** The speed is read from the shipped `.tres` `assault_drift_speed` (review N11).
   - Assault: `step()` 60 times at DT moves y by `speed · 1.0` ± 0.01, and `velocity() == (0, speed)`.
   - Open Space: y is unchanged and `velocity()` is ZERO.
   - Assault: a turret at `end.y − 1` stepped 0.1 s is queued for deletion.
10. **Not an escape, Assault only (one awaited frame).**
    - A real `ScoreTracker` is set up: `start_tracking`, `set_process(false)`, `_combo` 4.0.
    - The turret is added, then announced through `EventBus.enemy_spawned_orphan`; `counts_as_escape` is read from the live node (review N11).
    - It drifts out (`step` past `end.y`) and one `process_frame` is awaited: the combo is still 4.0.
    - Control: a fixture enemy registered the same way and freed takes the combo to 3.0.
11. **`turn_rate_override`, Open Space only (structural).**
    - A turret whose `Slot0.turn_rate_override` is set to 1.2 before `add_child`: its mount's `turn_rate` is 1.2.
    - The shipped turret (−1): the mount's `turn_rate` equals the scene export, 2.0.
    - `variant` 0 gives a `BurstCannonMount`.
12. **Power down mid-burst** (review N2).
    - Fire until the second `round_fired`, then `set_powered(false)`.
    - No further acquire: 0 more `round_fired` over 2 s of ticks, and the pool's `_idle.size()` is unchanged.
    - Rounds already in flight are unaffected: each in-flight round's `_physics_process(DT)` is stepped by hand for 10 ticks; it moves
      `speed · 10 · DT`, stays valid, and stays in the container.
    - Light OFF; the brain is UNPOWERED; the mount phase is UNPOWERED.
    - The mount is at rest (< 0.5°) within `π / turn_rate` s.
    - `set_powered(true)` is ignored: still UNPOWERED.
    - A second `power_down()` is harmless.
13. **Pools and container.**
    - Exactly one `BulletPool` child of the root: `PulsePool_0`, size = `pool_specs()[0].size`, `bullet_scene` = the Pulse round.
    - A fired round has `get_parent() == turret.get_parent()`.
14. **Owner group, Open Space only.**
    - Without a group the turret is in `&"turret_<id>"`, and `mount.owner_group()` is that name.
    - With a stub group object (`owner_group = &"g_test"`) passed through `set_turret_group` before `add_child`, it is in `g_test`.
15. **Real physics at 8×, both harnesses: line of sight, then the mining beam** (old rows 13 + 14 in one world, review B3 / N4).
    - Setup: a still `wreck_medium` (`set_physics_process(false)`) at T + (0, 200), the player at T + (0, 400), and the turret
      `start_engaged`. The turret is added only after 2 awaited physics frames, so the ray can see the wreck body.
      - In Assault the turret drifts about 90 px during the row (300 → 390); the wreck at 500 and the player at 700 stay between and below it.
    - (a) Line of sight. Over 1.5 s: no round.
    - (b) The wreck is freed: a round within 1.5 s, stopping on the first.
    - (c) A real `BeamBehavior` driver (the ram row's) is placed 250 px below the turret, firing up. The turret's health drops below 90 within
      40 ticks, stopping on the first drop. A blocking root would have stopped the beam, so this also proves `is_laser_blocking() == false`.

16. **Every phase ticks the weapon, Open Space only (structural; review R2-B1).**
    - A fixture `TurretMount` subclass (`tests/helpers/fixture_turret_mount.gd`, no `class_name`) counts `_weapon_tick` calls per phase, and
      answers `_telegraph_done()` from a flag the row sets.
    - It runs SCAN (no target), TRACK, TELEGRAPH (held until the flag is set, past `_telegraph_seconds()`, which proves the hook decides the
      step), FIRE, COOLDOWN, then `power_down()` and UNPOWERED.
    - Exactly one `_weapon_tick` per `tick()` / `scan()` call in every one of the six phases.

**Roster gates and others.**
- The three `ROSTER`s, `_SHIP_SCENES`, `_MIN_ROSTER_SIZE` → 14, and `_AUTHORED_CONTACT_MODES`.
- `test_base_enemy.gd::test_a_mover_less_turret_brain_refuses_a_tow_in_every_phase` (review N5):
  - It is a new row, not a `_REFUSING_PHASES` entry: that table needs an accepting phase, and the turret has none.
  - It reaches the brain by `get_node("Brain")` and the phases through `get_script_constant_map()["Phase"]`, never by class name (the file's
    leak note).
  - In every phase it asserts both `brain.accepts_tow() == false` and `turret.accept_tow(v) == false`.
  - The deviation is logged in DECISIONS.
- `test_enemy_dual_mode.gd::test_defense_turret_engages_in_both_modes_and_drifts_only_in_assault`.
- `test_enemy_bullet_lifetime.gd`: the mount's `round_speed` joins the Pulse entry and the shipped-speed list.

## Risks

**Gate time** (allotment 1.5 s; per-row estimate, review B3):

| Rows | Cases | Estimate |
|---|---|---|
| Hand-ticked, both harnesses: 1–4, 6, 9, 12, 13 (≤ 7 s of ticks each, one turret) | 16 | ≈ 0.04 s each → 0.65 s |
| Single-harness: 5, 7, 8, 10, 11, 14 (row 10 awaits one frame) | 6 | ≈ 0.15 s |
| Row 15, real physics at 8×: ≤ 1.5 + 1.5 + 0.7 s of game time per harness, early exits | 2 | ≈ 0.25 s each → 0.5 s |
| Roster and lifetime additions: one more scene in about 8 sweeps, the dual-mode case and the tow row | — | ≈ 0.15 s |

The total is about 1.45 s. If it runs over, the lever (§2.20) is: first share one world across rows 2–4 (one crossing-stub run feeds the lead,
cone and cadence assertions), then shorten row 15's (a) window to `charge_seconds` + 2 bursts' worth. No assertion is cut.

**Other risks.**
- **The ±1-tick cadence.** `BurstClock` subtract-not-reset keeps the 0.12 s gap within a tick (7.2 ticks).
- **The ScoreTracker frame.** `tree_exited` fires when the queued free runs, at the end of the frame, so the row awaits `process_frame`.
- **The `test_base_enemy` sweep.** The generic lethal flow frees the turret in a plain `Node2D` container. With no ArenaCamera, `AssaultDrift`
  does nothing.

## Out of scope
- The other mount variants (t7, t8).
- `TurretGroup`, stagger, power source, shield generator (t8–t9s).
- The heavy emplacement (t11).
- Art (t15).
- Hub and level placement (t18, t19).
- Re-powering (Ph20).
