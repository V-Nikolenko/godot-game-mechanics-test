# t5 — Space Fortress shell (task plan)

The approved design is the epic plan `docs/plans/cmug256so0031m52wbxomst72/3-plan.md` §2.5 (with §2.1, §2.2, §2.14–§2.16). This file does not redesign it: it fixes
the build order, the points the epic plan leaves to the implementer, and the concrete test rows.

## Problem
Level 1 ends on a box-shaped station fought from below. Phase 11 replaces it with a 360° Space Fortress. This task builds the boss's **body**: the armoured ring
hull, its nine parts, two shield sectors, the four-phase ladder with its vulnerability and visual consequences, death, EMP and every roster gate. It does not
move, shoot or launch yet (t6, t7, t16, t8); nothing places it in a level (t10, t13), so the player sees no change from this task alone.

## Design (only what the epic plan leaves open)

**Files.** `assault/scenes/enemies/space_fortress/`: `space_fortress.tscn`, `space_fortress.gd` (`SpaceFortress extends BaseEnemy`), `fortress_brain.gd`
(`FortressBrain extends EnemyBrain`), `space_fortress_config.gd` / `.tres` (flat `SpaceFortressConfig extends ShipConfig`), `ENEMY.md`; `WaveBuilder.space_fortress()` /
`SPACE_FORTRESS`.

**Scene** exactly §2.5.1 / §2.5.2, minus what later tasks add: no `MountSlots` (t7), no `Bay` (t8), no `HullMounts` / `HullBeams` / `PulseRing` (t7/t16) nodes yet. `Thrusters`
and `CriticalOverlay` are empty `Node2D`s (`visible = false`) so the phase handler has its visual targets now and t9 fills them. Each part: `Sprite`, `HurtBox`
(+ `CollisionShape2D`), `HomingPoint` (`Marker2D` at the part origin), `Light` (`StateLight`). Placeholder art: hull `station_core.png` at scale 1.375 (352 px), batteries
`station_turret.png` scaled to ~44 px, hangar / generators / core `station_core.png` scaled to their hurtboxes; `wreck_texture` null (the module's `WRECK_TINT`). Root exports
`shutter_open_texture` and `core_open_texture` (placeholder: `station_turret.png`) are the "opened" swaps. `EnemyMover` `constraint_mode` NONE, `turn_lerp` left for t6.

**Config** (`space_fortress_config.tres`, all flat): ShipConfig fields (`max_health` 1500 mirrors `core_health`, `collision_damage` 40, `score_value` 1500,
`counts_toward_wave_clear` / `counts_as_escape` true, `hazard_avoidance` 0, `wreck_chance` 0); `battery_health` 260, `hangar_health` 300, `shield_node_health` 360,
`core_health` 1500; `sector_shield_capacity` 120, `sector_shield_regen_delay` 3.0, `sector_shield_regen_seconds` 2.0, `sector_shield_reboot_seconds` 5.0, `sector_shield_pad` 8;
`shields_exposed_battery_losses` 2, `critical_core_ratio` 0.4 (both must equal the scene's `BossPhase` values; a row checks it); `death_sequence_duration` 2.4,
`death_blast_count` 10; `emp_factor` 0.4; `core_blink_period` 0.25; `escort_cap_open_space` 6, `escort_cap_assault` 4, `escort_boost_speed` 300, `escort_boost_seconds` 0.4
(the Carrier's launch boost; t8 may retune). t6–t8 append their own groups.

**Applying the config.** Parts write their `Health` in their own `_ready()` (before the root's), so the root's `_ready()` writes each part's `max_health` export **and** its
`Health.max_health` / `current_health` (the station's turret rule); root `Health` = `core_health`; `contact_hit_box.damage = collision_damage`; `death_duration =
death_sequence_duration` (a public var, the station's override point).

**Order in the root `_ready()`:** `super._ready()` → group `enemies` → owner group `fortress_<id>` → config → world anchoring (Carrier code) → mode (`EnemyWorld.arena(tree) !=
null`) → two `ShieldSector`s (north: artillery, missiles, hangar; south: spread, pulse, sweep) → `BossReinforcements.new(self, hull, driver, brain.rng, owner_group, cap by mode,
boost speed, boost seconds)` handed to the brain (`bind(self, hull, reinforcements)`) → core `destroyed` → `_on_core_destroyed` → `driver.phase_entered` → `_on_phase_entered` →
`driver.bind(hull, health)` (enters `batteries` synchronously).

**Phase consequences (t5's part, in `_on_phase_entered`; the brain gets `on_boss_phase(phase_id)`, a stub t6–t8 fill):**
- `batteries`: initial visual fields (shutters closed, plating closed, generator light SHIELDED, core light `&"off"`, thrusters / overlay hidden).
- `shields_exposed`: both generators `call_deferred("set_vulnerable", true)`; `_shutters_open = true` and each live generator's sprite → `shutter_open_texture`.
- `core_exposed`: core `call_deferred("set_vulnerable", true)`; `_core_plating_open = true`, live core sprite → `core_open_texture` (deferred, the Carrier R2-4 rule: never over a
  wreck); `Thrusters.visible = true`.
- `critical`: `CriticalOverlay.visible = true`; `_core_light_mode = &"blink"`: the root's `_process` toggles the core `Light` COMMIT ↔ OFF every `core_blink_period` while
  critical, not dying and the core is not a wreck.

**`phase_snapshot()`** — six keys, from phase-driven state only:
- `movement`, `attacks`, `arena`: `brain.movement_snapshot()` / `attacks_snapshot()` / `arena_snapshot()` — `[]` stubs until t6 / t7+t16 / t16 replace them.
- `reinforcements`: `[sorted activated bay ids, surge queued on entering this phase]` — `[[], 0]` until t8 (no bays).
- `vulnerable`: sorted ids with `is_vulnerable()` true, wrecks included, hangar excluded.
- `visuals`: `[shutter texture resource path (from `_shutters_open`), core plating path (from `_core_plating_open`), generator light state, core light mode, Thrusters.visible,
  CriticalOverlay.visible]`. **Clarification of §2.5.5:** "generator light states" / "core light state" are the states the **fortress keeps** the lights in (fields), not the live
  `Light.get_state()`: a part's wreck turns its own light OFF and a blinking light alternates, and either would make the key change without a phase (the "a part's death never
  changes a key" rule). The generator field is SHIELDED for the whole ladder in t5 (the light the sector shows); it is listed because t9 may change it per phase.

**Death** (§2.5.3, the station's order): `_on_health_changed(0)` latched once → `was_killed`, `died`, corpse harmless (hurtbox monitoring, contact layer, both deferred),
`suspend_ai()`, every hull mount `power_down()` (none until t7; iterates `hull.modules()` mounts), `brain.silence()` (t7 / t16 extend it: beams, ring, core-ring pool),
`reinforcements.scuttle_all()`, stop the blink, `death_started`, then the `Timer` child (`death_duration`) → `_finish_death()`: explode, `EscortContainer.of(self)` freed,
`queue_free()`. `death_duration` ≤ 0 finishes at once. `is_dying()`. Root hits while dying neither flash nor emit.

**EMP** (§2.5.6): `answers_emp()` = `is_dying() or super.answers_emp()`; `apply_emp(s, src)`: return while dying, else `super(s * config.emp_factor, src)`. `FortressBrain.
on_emp_started()`: every attached mount `scan(0.0)` (none until t7), `silence_weapons()` hook (t16), `reinforcements.tick(0.0, false)` once.

**Brain shell:** `enum Phase { IDLE, NOTICING, RETURNING, ENTER, HOLD, REPOSITION }`, `phase = IDLE`, `is_engaged()` → false (stub until t6), `accepts_tow()` false,
`attack_gate()` → false (stub until t7), `tick(delta)`: `reinforcements.tick(delta, is_engaged())` only. Never writes velocity / rotation (single-writer gate).

**Roster gates (§2.14):** add a `space_fortress` entry to the hand rosters of `test_enemy_contact_damage.gd`, `test_contact_hitbox_geometry.gd`,
`test_enemy_hurtbox_geometry.gd` (their completeness guards then pass); `test_base_enemy.gd` (its directory sweep finds the fortress: `_EXCLUDED_FROM_GENERIC_DAMAGE_FLOW`, `_AUTHORED_CONTACT_MODES` ARMOR, `_MIN_ROSTER_SIZE` 26, every-phase tow refusers — the Carrier precedent; epic §2.14 omits this file); `test_config_instance_isolation.gd` sweeps it automatically and gains the fortress identity row;
`test_boss_phase_rules.gd` asserts its sweep contains `space_fortress.tscn`; transparency, signal arity, single writer, layer names, project load: automatic sweeps.

## Build sequence
1. Config script + `.tres`; `WaveBuilder` entry.
2. `test_space_fortress.gd` rows 1–11 (red), roster-gate entries, isolation row, phase-rules expectation.
3. Brain shell; root script; scene (hand-written `.tscn`, no UIDs typed).
4. Green the new file in both harnesses; run the roster gates; `scripts/check-test-leaks.sh`; `scripts/gate-time.sh` ×2; `bash /agent/verify.sh`.
5. `ENEMY.md`, module-doc line in `assault.md` (the `updating-project-docs` skill; t14 does the phase pass), `tests/README.md` gate-time row, DECISIONS line for the snapshot
   clarification.

## Test plan — `tests/integration/test_space_fortress.gd` (rows = §2.5.7)
Hand-ticked rows spawn with `set_physics_process(false)`, in both harnesses (`MODES`). Real-physics rows scale the clock 8× (`_scale_clock`, restored in `after_each`).
1. **Geometry** (both): body / hurtbox / contact share one `CircleShape2D` r 176 (same sub-resource and scale); each part's position (0.01 px), role, `max_health` from config,
   `starts_vulnerable`, hurtbox shape and size; every part's hurtbox inside the hull circle (a circle: centre distance + radius; a rectangle: each of its four corners, so the 36 × 56 hangar (x radial) reaches 170.3 px) ≤ 176; boundary: a part moved to r 170 pokes out; root layer 0 / mask 0.
2. **Armour and lanes** (real, 8×, both): a bullet down local x 60 crosses the whole hull clear of every part → flies on (`range_px` end), `armor_deflected(50)`, root
   `Health` unchanged; a stream of bullets along the spread battery's diagonal lane: the first three are absorbed by the sector bubble (`hit_absorbed`, battery HP unchanged),
   the fourth damages the battery, the core's HP never moves.
3. **Locked parts** (real, 8×, both): a bullet down local x 0 crosses `ShieldNorth`, `Core`, `ShieldSouth` (all ping, none loses HP) and flies on; one along y 0 from the left
   crosses the hangar and the core, ending before the sweep battery; a `BeamDriver` up x 0 for 1 s and one nova: locked parts' HP unchanged, each pings; a nova lowers an open
   battery (the bubble does not stop direct emitters).
4. **Sector wiring** (both): a bubble on all five batteries and the hangar, none on generators / core; `capacity` 120, `reboot_seconds` 5, `regen_delay` 3, `regen_seconds` 2,
   radius = 22 + 8 (batteries) / hangar half-diagonal + 8; `destroy()` `shield_north` → north bubbles gone in the same call, south untouched; a destroyed battery's bubble
   freed; a HitBox delivered to the closed hangar's hurtbox is not absorbed (no `hit_absorbed`, hangar pings, HP unchanged).
5. **Ladder** (both): one battery → still `batteries`; second → `shields_exposed`, generators locked in that call and vulnerable after one physics frame; both generators →
   `core_exposed`, core vulnerable a frame later; core HP 601 → not `critical` (boundary), 600 → `critical`; the scene's `count` and `health_ratio` equal the config's.
6. **§25** (both, pinned path: spread, pulse → north, south → core to 40 %, hangar alive): for each entry, snapshot before the call and one physics frame after; changed keys ⊇
   declared ∩ {`vulnerable`, `visuals`} (t5's keys) and each declared change in t5's keys observed; **boundary:** one battery in `batteries` changes no key. Also: in
   `critical` the core light alternates COMMIT / OFF on the blink period (hand `_process`).
7. **Death** (both): `core.destroy()` → `died` once, `was_killed`, `death_started`, `is_dying()`, contact layer 256 → 0 (one frame), still in the tree; freed after a
   shortened `death_duration` (0.3 s); an `EscortContainer.ensure()`d container is freed with it; `death_duration` 0 → queued for deletion in the same call; a second
   `set_health(0)` re-emits nothing.
8. **EMP** (both): `EmpPulse.emit(..., 5.0, ..., TARGET_ENEMIES)` reaches it, `emp_seconds_left()` 2.0, mover halted (velocity zero), hurtboxes still monitoring and a battery
   still takes damage; **while dying:** a real `EMPBlastModule.try_activate(player)` → `process_mode` unchanged, `is_emp_disrupted()` false, freed `death_duration` after the
   core's death.
   Also: a core destroyed in the call that exposes it keeps its wreck (the deferred plating swap is skipped).
9. **Homing** (both): from a point near the spread battery → that battery's `homing_point()`; with every battery destroyed and generators still locked → the hangar is locked
   too, so the core's centre; with generators open → the nearer generator.
10. **Config** (both): `.tres` values (each field listed) win over the scene's authored `Health` values (a scene authored with a different part HP is overwritten — checked by
    the private copy carrying the `.tres` values and part `Health` equal to them); `DeathSequence`'s blast count = 10 (script default 3), read from the private copy; flat
    (the isolation sweep).
11. **Builder** (no harness): `WaveBuilder.SPACE_FORTRESS` path and `space_fortress()` loads a `SpaceFortress`; `FortressBrain.Phase` keys in order; ward / tow / repair refused;
    `rocket_clear_radius()` 184; `is_laser_blocking()` false; `world_anchored_x` true.

Isolation row (`test_config_instance_isolation.gd`): two fortresses, a `ConfigProbe` child in each sees the private copy (identity) and the two differ.

## Risks
- Real-physics bullets in the Assault harness: `world_anchored_x` shifts x; rows read positions after `add_child`.
- A bullet crossing several locked parts relies on `EnemyModule._resolve` deflection (Ph10, gated).
- Gate time: about 10 real-physics windows of ≤ 1 s at 8× plus two short death waits; target +1.5 s of the 2.0 s allotment.

## Out of scope
Movement, facing, spins (t6); batteries / attack gate (t7); beams, ring, core ring and their FADE tick (t16); bays and surges (t8); art (t9); level / hub placement
(t10 / t13); station retirement (t11).

## Revision 2 (answers review round 1, `4-review.md`)
- F1: `test_base_enemy.gd` joins the roster-gate list (see *Roster gates*).
- F2: row 1 tests a rectangle by its corners (implemented that way; the hangar rect is authored 36 × 56 with x radial).
- F3: row 10 writes distinct values on the private copy before `add_child` (`battery_health` 999, `core_health` 1234, `death_blast_count` 7) and asserts part
  `Health`, module export, root bar and the death sequence's blast count take them; row 4 does the same for the five sector params (77 / 1.5 / 0.75 / 9.0 / 4.0).
- F4: row 6 also asserts the live sprites (both generators show `shutter_open_texture` after `shields_exposed`, the core `core_open_texture` after
  `core_exposed`, the overlay shown in `critical`); row 7 adds the "never over a wreck" check. The clarification stays (and goes into DECISIONS).
- F5: row 8 sets the body's velocity to 40 px/s before the pulse, so "halted" is observable; the dying branch asserts the wreck is still in `enemies`.
- Row 3: the bullet along y 0 ends at x +50, 6 px past the core's edge and 78 px short of the sweep battery's hurtbox (128): it must fly on, never reach a bubble.
- Clarification: `_on_phase_entered` applies nothing once the fortress is dying (a part killed in the death sequence may still step the ladder).
- `HullBeams` is not added in t5 (t16 adds it with the beams).
