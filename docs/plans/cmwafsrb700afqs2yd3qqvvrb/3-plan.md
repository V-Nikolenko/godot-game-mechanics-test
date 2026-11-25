# t6 — Carrier shell: armoured hull, seven parts, core exposure, movement in both modes

Task plan for Phase 10 t6 (epic `cmug23oo90029m52wae4clve0`). The design is the epic's approved plan §2.6 (with §2.1, §2.2, §2.9, §2.11, §2.16). This file fixes
the build-level choices §2.6 leaves open and the test list; it does not redesign anything. Each departure from a plan line is marked **(D)** and goes to
`docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md` under Phase 10 as "built in t6".

## Problem

There is no Carrier. After t6 a capital ship exists that the player takes apart: an armoured hull no projectile can hurt, carrying seven parts (two engines aft,
two gun batteries amidships, two hangars, a core). Shots cross the hull to whatever part they hit. Losing an engine makes it turn half as fast and list toward
the dead side; losing both leaves it barely able to turn. The core is plated (shots ping off it) until any three outer parts are wrecks, then it opens and the
ship panics; destroying the core kills it. Wrecked parts stay on the hull, dark, so its silhouette changes as it breaks. In Open Space it screens: it holds
the player at 600–950 px, turns a live battery side-on, never strays more than 900 px from its anchor, and in panic backs away inside that leash. In Assault
it crosses the corridor top to bottom at a constant 90 px/s, nose-down, swaying at most 30 px sideways — not even an EMP stops the crossing. Weapons (t7) and
hangar launches (t8) are not in this task: the gun parts carry an empty `MountSlots` and the hull an empty `HullMounts`.

## Design

### Files
`assault/scenes/enemies/carrier/`: `carrier.tscn`, `carrier.gd` (`class_name Carrier extends BaseEnemy`), `carrier_brain.gd` (`class_name CarrierBrain extends
EnemyBrain`), `carrier_config.gd` (`class_name CarrierConfig extends ShipConfig`, flat) + `carrier_config.tres`, `carrier_engine_plume.gd` (`class_name
CarrierEnginePlume extends Node2D`, code-drawn flame), `ENEMY.md`. `WaveBuilder.carrier()` / `CARRIER`. `BaseEnemy.emp_seconds_left()`. One line in
`SupportShipBrain.is_candidate()`.

### Scene (`carrier.tscn`, nose-down; port = local +x, stern = local −y)
```
Carrier (CharacterBody2D, carrier.gd)   collision_layer 0, mask 0 (D1)
  Sprite2D            stand-in hull art (D7), hit-flash material
  CollisionShape2D    RectangleShape2D 176 x 280 (SubResource "hull")
  HurtBox             layer 512, mask 1121, shape = "hull"
  Health              max 600 (from config; never lowered by damage, see below)
  HitFlashAnimationPlayer
  ContactHitBox       layer 256, mask 128, damage 15, damage_type 2, shape = "hull"
  ContactProfile      mode ARMOR (4), shove_speed 220
  EnemyMover          constraint_mode NONE
  Brain (CarrierBrain)
  StateLight          OFF in t6 (t7 drives it)
  HullMounts (Node2D) empty in t6 (t7: Bow, Dorsal)
  Modules (Node2D)
    EnginePort      ( 56, -116)  ENGINE  180 HP  hurtbox 48 x 48  Light = CarrierEnginePlume (points aft)
    EngineStarboard (-56, -116)  ENGINE  180 HP  hurtbox 48 x 48  Light = CarrierEnginePlume
    GunPort         ( 64,   40)  WEAPON  160 HP  hurtbox 48 x 48  MountSlots (empty; t7 adds the BURST_CANNON slot)
    GunStarboard    (-64,   40)  WEAPON  160 HP  hurtbox 48 x 48  MountSlots (empty)
    HangarPort      ( 60,  -56)  HANGAR  220 HP  hurtbox 64 x 56  starts_vulnerable false
    HangarStarboard (-60,  -56)  HANGAR  220 HP  hurtbox 64 x 56  starts_vulnerable false
    Core            (  0,    0)  CORE    600 HP  hurtbox 56 x 56  starts_vulnerable false
  ModularHull
```
Every part hurtbox lies within |x| ≤ 92 ≤ `module_x_extent` 100; no two part hurtboxes overlap (core 56 px so the hangars at x ≥ 28 do not touch it), so a shot
aimed at a part's centre meets only that part and the (deflecting) root. Each part's `Sprite` carries the stand-in `intact_texture` / `wreck_texture` (D7). Part
`HomingPoint` = none (the part centre, §2.6.2). `hull_share` 0 everywhere.

### Root (`carrier.gd`)
- `_ready()`: `super._ready()`, group `enemies`, owner group `carrier_<id>`, `_apply_config()` (health, score, `contact_hit_box.damage = collision_damage`, mover
  `max_speed` / `acceleration` / `braking` / `max_turn_rate`, brain config), world-anchored x (the jammer's line, only when `world_anchored_x` and an Assault arena),
  `_hull.module_destroyed.connect(_on_module_destroyed)`, `Core.destroyed.connect(_on_core_destroyed)`, `_brain.bind_hull(self, _hull)`. No `build_mounts()` call in t6
  (no slot exists; t7 adds it, then the hull slots).
- `deflects_hit(_hb) -> true`, `is_armored() -> true`, `is_laser_blocking() -> false`, `can_be_repaired() -> false`, `accepts_ward() -> false`,
  `launch_velocity()`, `rocket_clear_radius()` (half-diagonal + 4), `body_size()`, `modular_hull()`, `owner_group()`, `homing_point(from)` (the Gunship's loop:
  nearest live **vulnerable** part, else the hull centre).
- `_on_received_damage(damage)`: refuse — `armor_deflected.emit(damage)`, `hit_flash_player.play("hit")`; `Health` untouched (the Ram's armoured branch). So bullets,
  rockets, the beam, the nova and a level `LaserRay` all leave the hull bar alone. `signal armor_deflected(damage: int)`.
- **Core exposure:** `_on_module_destroyed(part)`: if not yet exposed and `_hull.destroyed_count([ENGINE, WEAPON, HANGAR]) >= config.core_exposure_count`:
  `_core_exposed = true`, `core.call_deferred("set_vulnerable", true)` (the kill lands in a physics flush; the next physics frame sees an open core),
  `_open_core_plating.call_deferred()` (the core `Sprite` swaps to `core_open_texture`, D7), `core_exposed.emit()` (`signal core_exposed`). `is_core_exposed()`. The
  brain reads it on its next tick and enters PANIC.
- **Death:** `_on_core_destroyed(_part)` → `health.set_health(0)` → the normal `BaseEnemy` death (`was_killed`, `died`, explosion, free; the wrecks go with it).
  `_open_core_plating()` does nothing on a destroyed core, so a same-frame kill never overwrites the core's wreck texture.
- **EMP refresh (review finding 2):** `apply_emp(seconds, source)` override: `var before := emp_seconds_left()`, `super.apply_emp(seconds, source)`; when `before > 0`
  and the window grew, `_carrier_brain.on_emp_refreshed()` (in Assault it re-commits the crossing boost to the new `emp_seconds_left()`). `BaseEnemy` only tells the
  brain about a window's start, so without this a second EMP inside the first would let the boost run out and stop the hull (acceleration 0) for the rest of it.
- **Free below the rect (review finding 3):** `_physics_process(delta)` override = `super._physics_process(delta)`, then, in Assault (the brain's mode flag),
  `if global_position.y − body_size().y / 2 > EnemyWorld.projectile_world_rect(tree).end.y: queue_free()`. On the root, not in the brain, because the brain is not
  ticked during an EMP window: the Assault life stays fixed by spawn y and speed, with no EMP term (t12's lane maths, §2.13). A position read and a free; no
  motion write (single-writer gate unaffected).
- **(D2) Hull `Health` = 600** (`config.max_health`, = the core's HP so any HP readout means something). It never moves before the core dies; it is not the kill
  path's input, only its output.

### Brain (`carrier_brain.gd`)
`enum Phase { CRUISE, SCREEN, PANIC, CROSS, IDLE, NOTICING, RETURNING }` (append-only), `signal phase_changed(new_phase: int)`, `enter_phase(p)` (the one transition
point), `start_engaged` and `patrol_anchor` seams (the Gunship's), `config: CarrierConfig`.

- **Mode** is decided once in `_start()` into `var assault: bool` (read-only for the root): Assault iff `EnemyWorld.arena(tree) != null` (the `EngagementBudget`
  rule). Assault → `enter_phase(CROSS)` and the CROSS limits below. Open Space → `start_engaged` ? SCREEN : CRUISE with an `AnchorIdle(patrol_anchor, perceive 1100,
  lose 1800, notice 0.6, idle_radius 220)`. **Every mover-limit write is keyed by the mode, never by the phase (review finding 1):** in Assault `max_speed`
  stays `assault_max_speed`, `acceleration` / `braking` stay 0 and `hazard_avoidance` stays 0 in every phase, PANIC included, whatever the engines; only
  `max_turn_rate` follows the engines (it never matters there: the hull faces straight down).
- **Tick order:** `_start()` once → engine state (`_update_engines()`) → if `carrier.is_core_exposed()` and not PANIC → `enter_phase(PANIC)` (from any phase; one
  tick after the deferred exposure, the "tick after exposure" of §2.7) → anchor idle (Open Space, not PANIC) → phase dispatch.
- **Engines (module death changes movement):** `engines_alive()` = live ENGINE parts, counted from `ModularHull.module_destroyed` (cached, not a per-tick
  `live()` array). `turn_factor()` 1 / `one_engine_turn` 0.5 / `no_engine_turn` 0.15; `speed_factor()` 1 / `one_engine_speed` 0.8 / `no_engine_speed` 0.4. Written on
  change (and at start) onto the mover: `max_turn_rate = config.max_turn_rate · turn_factor()`, and **in Open Space only** `max_speed = config.max_speed ·
  speed_factor()`. `list_sign()`: +1 / −1 toward the dead engine's side with exactly one engine
  lost, else 0 (port dead → the nose yaws toward local +x, i.e. rotation decreasing: −1; starboard dead → +1).
- **Facing with a list (D3).** `_face(desired_dir)` is the only facing call outside CROSS. With `list_sign() == 0` it is `mover.face_toward(pos + desired_dir · 100)`.
  With one engine lost it keeps a flag `_correcting`: the error `e = angle_difference(rotation, desired_rotation)`; `|e| > list_hold` (`deg_to_rad(list_hold_deg)`
  10°) sets it, `|e| <= LIST_SETTLED` (0.01 rad) clears it. Correcting → face the desired direction (the mover caps it at the scaled turn rate). Not correcting →
  face `rotation + list_sign · list_rate · delta` (the hull sags toward the dead side at `list_rate` 0.06 rad/s, below the one-engine cap 0.175). So a held heading
  saw-tooths: it drifts 10° in ≈ 2.9 s, then turns back. Why a deadband: a bias added to the facing *target* can never beat the mover's turn cap, so it only gives
  a fixed lean (a constant offset), not the drift §2.6.4 asks for ("the heading drifts by ≥ 0.05 rad/s with no turn request"); the deadband is what makes the hull sag
  while it holds, and a turn proper runs at the plain scaled cap (so the "≥ 1.8 t" row reads 2.0 t whichever way it turns).
- **Desired facing (SCREEN, PANIC):** live batteries = `hull.live(WEAPON)`; for each, its broadside heading (port: `bearing.rotated(PI/2)`, starboard:
  `bearing.rotated(-PI/2)`, the Gunship's mapping); the one with the smaller `|angle_difference|` from the current nose wins (the nearer side; a tie picks port); no live
  battery → the bow to the player (`bearing`).
- **SCREEN (Open Space, engaged).** d = distance to the player. Outside `screen_range_min` 600 .. `screen_range_max` 950: `arrive` at `player + dir(hull − player) ·
  (min + max) / 2`, that point clamped into the `leash_radius` 900 disc round `patrol_anchor` (`anchor + (p − anchor).limit_length(leash)`), at `max_speed ·
  speed_factor()`. Inside the band: `request_velocity(ZERO)`. Facing as above. If the hull itself is outside the leash it `arrive`s at the clamped point regardless (it
  only ever heads back in).
- **PANIC (Open Space).** `arrive` at `anchor − dir(player − anchor) · leash_radius` (the far side of its anchor from the player, on the leash circle; with the player
  on the anchor, the hull's own side), speed `max_speed · speed_factor()`; facing as SCREEN. Permanent.
- **CRUISE / NOTICING / RETURNING (Open Space idle).** `AnchorIdle.update()` → CRUISE: `mover.orbit(anchor, idle_radius, offset + idle_speed · t, max_speed)` with
  heading of travel; NOTICING: stop and face the player; COMBAT: SCREEN; RETURNING: `arrive` at the anchor. **IDLE** (D4): Open Space engaged with no player in the tree:
  `request_velocity(ZERO)` (no facing); it returns to SCREEN when one appears.
- **CROSS (Assault).** On entry (D5): `mover.max_speed = assault_max_speed` 110, `mover.acceleration = 0`, `mover.braking = 0` (instant: the crossing speed holds from
  the first tick and after an EMP halt, no ramp), `mover.hazard_avoidance = 0`, `_anchor_x = actor.global_position.x` (after the world-anchored shift, which ran in the
  root's `_ready()`). Each tick: `request_velocity(Vector2(vx, assault_cross_speed))`, `face_toward(pos + DOWN · 100)` (never rotated). The free-below check is the
  root's (above). **Sway `vx`** (review finding 10): the arc half-angle used is `SWAY_ARC_HALF_DEG` 75 (half the 150° battery traverse §2.7; t7 replaces the constant
  by a read of the battery slot's `traverse_deg_override` so there is one source) minus `SWAY_ARC_MARGIN_DEG` 10 = 65°. If the player's bearing already lies within 65°
  of a live battery's side direction (port: world +x at rotation 0, starboard: −x), `tx = x` (hold: it is already covered). Otherwise, per live battery, the x that
  puts the player on that 65° line: port `tx = player.x − |dy| · cot(65°)`, starboard `tx = player.x + |dy| · cot(65°)`; the one nearer the current x wins; no live
  battery → `tx = _anchor_x`. `tx` is clamped into `_anchor_x ± assault_sway_leash` 30, `vx = clampf((tx − x) · SWAY_GAIN 4.0, −cap, cap)`, `cap =
  assault_sway_speed 30 · sway_factor()` (1 / `one_engine_sway` 0.5 / `no_engine_sway` 0.1). Each tick moves x monotonically toward a target inside the band
  (`SWAY_GAIN · dt` = 0.067 < 1, no overshoot) from a start inside it, so x never leaves `_anchor_x ± 30`. `|v| ≤ √(30² + 90²) = 94.9 < 110`, so the cap never
  slows the descent; the hazard slow is `1 − p · (1 − 1.0) = 1` and the drift is zero at resistance 1.0, so a slow field never does either.
- **PANIC in Assault** is the CROSS motion with the phase reading PANIC (t7 / t8 read it); the mode-keyed limits keep it at 90 px/s with any engines.
- **EMP:** `on_emp_started()` and `on_emp_refreshed()`: in Assault (any phase) → `mover.boost(Vector2.DOWN, assault_cross_speed, actor.emp_seconds_left())` (the
  window is already set when `apply_emp` calls the brain; the boost has one tick left when the window ends, and the brain's own request is the same velocity, so the
  crossing never stalls). Open Space: nothing (the Ph9 halt; `on_emp_refreshed()` is a no-op there).
- `accepts_tow() -> false` in every phase; `on_suspended()` drops the anchor idle.

### `BaseEnemy.emp_seconds_left() -> float`
Returns `_emp_left` (0 outside a window). Read-only; nothing else changes in `BaseEnemy`.

### Config (`CarrierConfig`, flat; `.tres` values)
ShipConfig: `max_health` 600, `collision_damage` 15, `score_value` 600, `counts_as_escape` true, `hazard_avoidance` 0.5, `hazard_margin` 120, `hazard_resistance`
1.0, `wreck_chance` 0. Movement: `max_speed` 70, `acceleration` 40, `braking` 40, `max_turn_rate` 0.35. Engines: `one_engine_turn` 0.5, `no_engine_turn` 0.15,
`one_engine_speed` 0.8, `no_engine_speed` 0.4, `list_rate` 0.06, `list_hold_deg` 10.0. Screen: `screen_range_min` 600, `screen_range_max` 950, `leash_radius` 900.
Core: `core_exposure_count` 3. Assault: `assault_cross_speed` 90, `assault_max_speed` 110, `assault_sway_speed` 30, `one_engine_sway` 0.5, `no_engine_sway` 0.1,
`assault_sway_leash` 30. Geometry: `module_x_extent` 100. Idle: `perceive_radius` 1100, `lose_radius` 1800, `notice_time` 0.6, `idle_radius` 220, `idle_speed` 0.12.

### Support ward filter
`SupportShipBrain.is_candidate(e)`: after the `SupportShip` check, `if e.has_method(&"accepts_ward") and not e.accepts_ward(): return false`.

### Deviations (D)
- **D1** Root body `collision_layer` 0 / mask 0 — the station's rule the plan cites ("mask 0, ploughs through"; §2.6.1 also names ENEMY_HITBOX, but the station it
  points to is layer 0). Every other enemy root, the Gunship and the Ram included, is on the default layer 1, which the player body (layer 4, mask 1) collides with.
  On layer 0 the player can fly onto the hull: contact deals 15 and one 220 px/s shove **only on entry** (`HurtBox._on_area_entered`, `ContactProfile._on_contact`);
  hugging the hull is what t7's anti-approach pulse punishes. (`is_laser_blocking()` false already keeps the beam's block ray off the hull either way.)
- **D2** Hull Health 600, refused, set to 0 by the core's death.
- **D3** The list is a hold-deadband sag (`list_hold_deg` 10°, new config field), not a bias added to every request.
- **D4** Phase IDLE = engaged with no player.
- **D5** CROSS writes `acceleration` / `braking` 0 on the mover.
- **D6** `one_engine_speed` / `no_engine_speed` / `one_engine_sway` / `no_engine_sway` / `idle_speed` / `braking` are named config fields for §2.6.3's numbers.
- **D7** Stand-in art until t9: hull `station_core.png` scaled to 192 × 288, parts `station_turret.png` / `station_turret_destroyed.png`, the opened core
  `power_source_glow.png` (`Carrier.core_open_texture` export). t9 replaces textures only.

## Build sequence
1. `test_carrier.gd` structure rows + roster-gate rows (red) → config, scene, root, `WaveBuilder.carrier()`, `emp_seconds_left()`, ward line. Green: structure,
   roster gates, ward.
2. Projectile / direct-emitter rows (hull refusal, core lock with 0–2 parts in three combinations, exposure on the 3rd, core death, closed hangar) → green.
3. Brain: engines, facing with list, SCREEN, PANIC, CRUISE → movement rows green.
4. CROSS: speed, sway, EMP, free-below, never rotated → Assault rows green.
5. Wreckage / silhouette and contact rows; `test_engagement_deadline.gd` guard; ENEMY.md; DECISIONS; docs skill; gate time; `verify.sh`.

## Test plan (`tests/integration/test_carrier.gd`; "both" = the two harnesses, label-parameterised)

**Projectile / beam / nova rows (A) run once, on real physics at the 16× clock** (`_SPEEDUP` 16, the t1 rule for rows that wait a counted number of physics frames;
no row here has a tolerance finer than an idle frame), with every carrier's physics off and its position held, so the mode cannot change a result (the t2
precedent, `test_enemy_module.gd`'s header). They share **three carriers side by side** (x 300 / 900 / 1500, 600 px apart; the vertical beams cannot cross another
hull) and run their windows **concurrently**. Hand-ticked rows (B) run in both harnesses unless marked.

### A. Real physics, one scenario (`test_the_hull_refuses_and_the_core_opens_only_after_three_parts`, plus two small rows)
Windows, each a bullet (or two) and a 2 s beam (`BeamDriver` 300 px below the target, firing up; 120 frames) fired together, then a nova at idle time:
1. **Count 0** on all three carriers: a bullet at bare hull (local (0, 110): inside the body, clear of every part) flies on (not consumed), the root's `armor_deflected`
   count grows; a bullet at the core flies on, core HP unchanged, `deflected` grows; the beam on the **hull centre** (= the core centre) for 120 frames: the root's
   `armor_deflected` count grows (the beam targets the root through its centre: `beam_behavior.gd:93-101`) and core HP and hull Health are unchanged; on carrier A
   also a bullet and a second beam on the closed `HangarPort`: HP unchanged, `deflected` grows. Then a nova: hull Health, core and hangar HP unchanged; each core
   and the hangar `deflected` exactly once more; each root `armor_deflected` exactly once more.
2. **Count 1, count 2** (scripted `destroy()` at idle time, then 1 frame): the core window again (bullet + beam + nova): unchanged, `deflected`.
   Combinations: A {`EnginePort`, `EngineStarboard`}, B {`GunPort`, `HangarPort`}, C {`EnginePort`, `GunStarboard`} — the epic's three.
3. **The third part:** A `GunPort`, B `HangarStarboard` by scripted `destroy()` (hangars are locked: `destroy()` is the scripted kill; the real-shot kill of a locked
   hangar is t8's); **C `GunPort` killed by four real bullets** fired together (160 HP, 4 × 50) inside a physics flush (review finding 7): on the first observed frame
   where it reads destroyed, `Core.is_vulnerable()` is still false (the deferred `set_vulnerable` is pending) and `is_core_exposed()` is true; one frame later it is
   vulnerable.
4. **After exposure** (from the next physics frame): a bullet at each core is consumed and costs 50; the beam for 120 frames lowers each core; a nova lowers each by
   exactly 50; hull Health still 600 (the core has `hull_share` 0). The core `Sprite` shows `core_open_texture` (review finding 4).
5. **Boundary:** `core_exposure_count` is read from the shipped `.tres` (== 3, never typed in the row); a fourth carrier with a private config of 4 has its core still
   locked one frame after its third scripted destroy (no physics needed beyond that frame; it shares the window).
6. **Contact (both harnesses, real player scene):** the real player (`player_ship.tscn` / `player_fighter.tscn`, physics off, the jammer test's helper) placed so its
   hurtbox overlaps the hull's lower edge: within 4 frames its Health drops by exactly 15 and it gets one shove of 220 px/s pointing away from the hull centre
   (Open Space: `velocity` grows by it; Assault: `is_knockback_active()`); the carrier's Health is unchanged.

Frame budget: windows 1, 2 (×2), 4 at ≈ 122 frames + window 3 ≤ 30 + row 6 2 × 4 ≈ **550 physics frames at 16×** ≈ 0.6–0.8 s of wall time.

### B. Hand-ticked (1/60)
7. **Structure (both):** 7 parts — ids, roles, max HP 180 / 180 / 160 / 160 / 220 / 220 / 600, hangars and core locked, the rest open; the hull's contact box damage
   15, ContactProfile ARMOR / 220; every part hurtbox's x extent ≤ `module_x_extent` read from the `.tres`; **boundary:** the same check function on a fresh instance
   with `GunPort` moved to x 120 reports it. `homing_point()` from below with the core locked is a live open part's centre, never the core's; after exposure, from
   right above the core, the core (review finding 11).
8. **Config and builder:** every §2.16 value from the shipped `.tres`; `WaveBuilder.CARRIER` loads; `carrier()` returns a `SpawnConfig` for it; the `Phase` order.
9. **Core death kills (both):** `Core.destroy()` → `died` once, `was_killed`, queued for deletion; the core `Sprite` shows its `wreck_texture` (not the open plating).
10. **Engines change turning (Open Space only, review finding 8; Assault's half is row 15's sway caps):** still player 760 px away, hull nose at it, both sides 90°
    away: time to |error| ≤ 0.02 rad = t (≈ 4.5 s); one engine dead ≥ 1.8 t; both dead ≥ 5 t (one run per engine count). **List:** settled broadside, then
    `EnginePort.destroy()`: over the next 2.0 s the heading moves ≥ 0.10 rad, the nose turning toward port (its dot with the port direction grows); with
    `EngineStarboard` instead, toward starboard; **control:** both engines alive, < 0.01 rad. **Plume:** after `EnginePort.destroy()` its `Light` (the plume) is hidden
    and `EngineStarboard`'s is visible (review finding 11).
11. **Facing (Open Space):** settled against a still player: both batteries → a battery side within 20° of the player; `GunPort` dead → the starboard side; both dead
    → the bow.
12. **SCREEN (Open Space):** a still player 760 px away: over 20 s never closer than 600; a player starting 450 px away: the hull opens to ≥ 600 within 20 s and never
    closes in after; a player fleeing from the anchor at 120 px/s for 30 s: the hull never more than `leash + 50` from its anchor.
13. **PANIC (Open Space, review finding 9):** core exposed by destroying `GunPort`, `GunStarboard`, `HangarPort` (engines alive: full speed). (a) a still player at
    anchor + (500, 0): after 30 s the hull is within 60 px of anchor − (900, 0) and was never beyond `leash + 50`; (b) a player chasing the hull at 120 px/s for 30 s:
    never beyond `leash + 50` (the leash bound only).
14. **Wreckage stays (both):** destroy `EnginePort`, `GunPort`, `HangarStarboard`, `EngineStarboard` at 0, 2.5, 5, 7.5 s of a 10 s run: at each loss the set of parts
    whose `Sprite` shows its `wreck_texture` grows by exactly that part (1 → 2 → 3 → 4; the silhouette, review finding 4); each is still under `Modules`, `WRECK`, at
    10 s; from the frame after the third loss the core `Sprite` shows `core_open_texture`; then `Core.destroy()` → the carrier is queued for deletion.
15. **Assault CROSS (Assault harness):** per-tick dy = 1.5 px (90 ± 1 px/s) and rotation 0 on every tick of 6 s for: both engines, one, none; PANIC (core exposed)
    **then both engines destroyed** with `mover.max_speed` still 110 (review finding 1); inside a slow `HazardField` (penalty 0.6) covering the path; a 5 s
    `apply_emp` and 1 s after it; **a second 5 s EMP applied 3 s into the first**, every tick through 8 s and 1 s after (review finding 2). Mover `hazard_avoidance`
    reads 0 (config 0.5), `acceleration` 0.
16. **Sway (Assault):** the player stub held at the left view edge, then (a second carrier) at the right view edge, for a whole crossing from design y −260 until
    freed: x within `_anchor_x ± 30` on every tick. **Caps:** the player directly below (outside both arcs, so the target is a leash edge): max |vx| = 30 / 15 / 3
    (± 0.01) with 2 / 1 / 0 engines over 1 s. **World-anchored x:** with the camera panned (view centre x 740), a spawn at x 700 lands at world x 600; with
    `world_anchored_x` false it stays at 700.
17. **Freed below the rect (Assault):** queued for deletion on the first tick its top edge is below `projectile_world_rect().end.y`, not one tick before; **with a 5 s
    EMP applied 1 s before that tick, freed on the same tick** (review finding 3).
18. **Roster gates:** `test_enemy_contact_damage.gd` ROSTER + a carrier row (15 from the `.tres`), `test_contact_hitbox_geometry.gd`, `test_enemy_hurtbox_geometry.gd`,
    `test_base_enemy.gd` (excluded from the generic damage flow like the Ram and the station; an every-phase tow refuser; `_MIN_ROSTER_SIZE` +1),
    `test_enemy_dual_mode.gd` (`HAZARD_PROFILES` row 0.5 / 120 / 1.0; a spawn row per mode: Open Space with `start_engaged` → SCREEN; Assault → CROSS and y grows by
    90 px over 1 s), `test_support_ship.gd` (a carrier beside a fighter: `is_candidate(carrier)` false and the fighter is the ward; **control:** a fixture candidate whose
    `accepts_ward()` answers true is still a candidate), `test_engagement_deadline.gd` (no `ENEMIES_CLEARED` section spawns a Carrier; **boundary:** a carrier added
    to cloud_descent's last wave is seen, the twin-pair row's shape).

## Risks
- **Gate time** (2.0 s allotment): A is ≈ 550 frames at 16× (≈ 0.7 s); B is ≈ 25 000 hand ticks of a mount-less brain (the engine count is cached, no per-tick
  arrays) ≈ 0.8 s. Levers if over, none cutting an assertion: rows 10's three turn runs and 12's still-player run share one world per engine count; rows 15's six
  6 s runs become one carrier per variant ticked in a single loop.
- A kill inside a physics flush then a deferred `set_vulnerable`: row A3 exercises it with real bullets.
- Row A6 with a real player scene: the player's own physics is off; the contact box's `area_entered` needs real physics frames (counted, at 16×).

## Out of scope
Weapons, the pulse ring, PANIC's weapon effects (t7); hangar doors and launches (t8); art (t9); hub placement (t10); level-1 placement and the lane maths (t12).

## Review round 1 — what changed
1. Mover limits keyed by mode (`CarrierBrain.assault`), never by phase; row 15 kills both engines during Assault PANIC.
2. `Carrier.apply_emp()` override → `CarrierBrain.on_emp_refreshed()` re-commits the crossing boost; row 15's double-EMP case.
3. The free-below check moved to `Carrier._physics_process()` after `super`; row 17's EMP case.
4. Silhouette = the set of parts showing `wreck_texture`; explicit `core_open_texture` checks (rows A4, 14) and the wreck texture on core death (row 9);
   `_open_core_plating()` skips a destroyed core.
5. Frame budget: three carriers, concurrent windows, 16×; ≈ 550 frames.
6. The beam is aimed through the hull centre and `armor_deflected` is asserted (beam and nova).
7. Row A3: carrier C's third part dies to four real bullets inside a physics flush.
8. Row 10 is Open Space only; the Assault half is row 16's sway caps.
9. PANIC far side proved with a still player; the chaser bounds the leash only; the three parts named.
10. Sway holds when the player is already covered (65° = 75° − 10° margin); t7 reads the arc from the slot.
11. Plume and `homing_point()` rows. 12. Deadline guard boundary, dual-mode spawn row assertions, third parts named. 13. D1's reason corrected.

## Review round 2 — what changed (binding on the test plan above)
- **R2-1 HP ledger.** Every window ends with the row restoring each live, **open** (vulnerable, not destroyed) part of every carrier to full HP
  (`health.set_health(max_health)`): the novas (50 each to every open part on the map) and the beams' side burns are test wear, not the subject of the row,
  and the restore keeps any of them from killing a part by accident. The core is never restored after exposure (window 4 measures its loss). At the start
  of every window the row asserts `destroyed_count([ENGINE, WEAPON, HANGAR])` equals that window's count on each carrier (0, 1, 2, then 3). Ledger per open
  part per window, worst case (carrier A's `GunPort` / `EnginePort`, which the core beam does not cross): one nova 50 + ≤ 55 beam side burn < 160 → no part
  can die inside a window. Row A3 therefore stands as written: carrier C's `GunPort` is at 160 when the four 50-damage bullets arrive.
- **Hangar shots** (row A1, carrier A): the bullet and the second beam come **horizontally from outboard along local y −56** (from local (360, −56) firing −x),
  a line that crosses only the two locked hangars (`HangarPort` then `HangarStarboard`; the core spans y −28..28, the engines y −140..−92, the guns y 16..64).
- **R2-2:** row A3's "core still locked in the kill's frame" is asserted from a handler connected to carrier C's `GunPort.destroyed` (it records
  `Core.is_vulnerable()` and `is_core_exposed()` at that moment: false / true), not from the order of events in one physics frame; one frame later the core is
  vulnerable.
- **R2-3:** `homing_point()` probe point = local (0, 20) (just nose-ward of the core): with the core locked it returns `GunPort`'s centre (the nearer gun; tree
  order breaks the tie), after exposure the core's centre.
- **R2-4:** row 9 gains a same-frame case: three outer parts and then the core destroyed in one idle call (the deferred plating swap still pending) → after the
  next frame the core `Sprite` shows its `wreck_texture`, not `core_open_texture`.
- **R2-4 as built (round 3 note):** destroying the core frees the carrier in the same call, so the same-frame row records the core `Sprite`'s textures
  through its `texture_changed` signal and asserts `core_open_texture` never appears after `wreck_texture` (or calls `_open_core_plating()` on the destroyed
  core in the same frame and asserts the wreck texture still shows).
