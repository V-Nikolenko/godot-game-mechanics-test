# Jamming Structure (Phase 9 t7)

Builds epic plan §2.8, §2.9 and the jammer half of §2.15 (`docs/plans/cmug23onr001pm52w9swwophy/3-plan.md`). This task plan does not
redesign them; it pins what they leave open and the build / test order. Context: `1-context.md`.

## Problem
The ability lock (t1), its tells (t2), the seekers' jammer rule (t4) and the EMP routing (t5, t6) exist, but nothing in the game makes a
jammer field: the player only meets one in tests. After this task:
- Three jamming towers exist (local, sector, pulsed). Each stands still (drifts with the corridor in Assault), shows a crawling amber-white
  static ring at its field radius and a small state light, and inside the ring the player's H abilities and K rockets are refused (the t1
  lock), with the 0.75 s / 1.25 s grace after leaving. The pulsed one telegraphs (ring flicker, light blinking) for 0.8 s, is lit for 3.0 s,
  then quiet for 2.5 s.
- Enemy ships fly through the field as if it were empty space (avoid weight 0).
- Seeking rockets fly straight inside a lit field: the player's (already, t4) and now an enemy Pursuit / Cluster rocket. A Missile Corvette
  whose target stands in a field fires Dumb salvos instead of Pursuit / Cluster.
- The player can kill a tower with the main gun from inside the field, or step out and fire EMP Blast: the field goes quiet for 5 s and the
  tower stays shootable.

## Design

### 1. `HazardField.suppress(seconds)` (`global/hazards/hazard_field.gd`)
- `var _suppressed_left := 0.0`. `suppress(seconds: float) -> void`: no-op for `seconds <= 0`; `_suppressed_left = maxf(_suppressed_left,
  seconds)` (longest wins); `_refresh_info()` at once (the player's next tick sees it).
- `is_suppressed() -> bool: return _suppressed_left > 0.0`.
- `_physics_process`: after the `duration` check and before the cycle step, `if _suppressed_left > 0.0: _suppressed_left -= delta; if
  _suppressed_left <= 1e-6: _suppressed_left = 0.0`. The cycle clock is never touched (a pulsed field keeps its phase underneath).
- `_refresh_info()`: `_info.disables_abilities = disables_abilities and active and _suppressed_left <= 0.0`. Nothing else changes (forces,
  slow, avoid weight, stress are unaffected: suppression is the jammer's EMP answer, and every Ph6–Ph8 field is never suppressed, so it is
  bit-identical).
- `restart_cycle() -> void`: `_cycle_clock = 0.0; _phase = _phase_at(0.0); _refresh_info()` — exactly what `_enter_tree()` does; the jammer
  calls it after writing its config values onto the field in `_ready()` (the field entered the tree first with the scene values; a row pins
  that scene and config values match, so in shipped scenes this is a no-op, but a config overridden before `add_child` still takes).

### 2. `JammingStructure` (`assault/scenes/enemies/jamming_structure/jamming_structure.gd`, `class_name JammingStructure extends BaseEnemy`)
- Exports: `config: JammingStructureConfig = load(".../jamming_structure_config.tres")`, `world_anchored_x := true`.
- `_ready()`: `super._ready()`, `add_to_group("enemies")`; from config: `health.max_health/current_health`, `_drift.speed =
  config.assault_drift_speed`, `Field.radius = field_radius`, `stabilise_seconds`, `cycle_telegraph/active/quiet`, then
  `Field.restart_cycle()`. World anchoring as `TurretGroup._ready()`: `if world_anchored_x and EnemyWorld.has_view_rect(tree) and
  EnemyWorld.has_projectile_world_rect(tree): global_position.x -= view_rect.center.x - projectile_world_rect.center.x`.
- `field() -> HazardField`, `is_laser_blocking() -> false`.
- EMP: `answers_emp() -> true`; `apply_emp(seconds, source)`: return for `seconds <= 0`; `super.apply_emp(seconds, source)` (BaseEnemy's
  clock, overlay and longest-wins; no brain / mover so nothing else runs; its clock is counted ahead of the no-brain return, t5), then
  `field().suppress(seconds)`. `is_emp_disrupted()` is BaseEnemy's. The root, body, HurtBox and health are untouched (shootable).
- State light (`_process(delta)`, visual only, `_update_light(delta)` hand-callable): suppressed or QUIET -> `OFF`; ACTIVE -> `ARMED`;
  TELEGRAPH -> alternates `CHARGING` / `OFF` every 0.1 s (blink). Never cyan / violet.
- No `_physics_process` override (BaseEnemy's counts the EMP window).
- Death is BaseEnemy's: the root frees, `Field._exit_tree()` unregisters, the player's next tick is an exit tick.

### 3. `JammingStructureConfig extends ShipConfig` (flat)
`assault_drift_speed` 60, `field_radius`, `stabilise_seconds`, `cycle_telegraph`, `cycle_active`, `cycle_quiet` (all 0 = always on).
`.tres` values per the epic table: local 140 HP / r 240 / always on / 0.75 s / score 60; sector 260 / 640 / always on / 1.25 / 120; pulsed
160 / 300 / 0.8·3.0·2.5 / 0.75 / 80. All: `collision_damage` 0, `counts_as_escape` false, `hazard_avoidance` 0, `hazard_margin` 0,
`hazard_resistance` 0, `wreck_chance` 0.

### 4. `JammerFieldArt` (`jammer_field_art.gd`, `class_name JammerFieldArt extends Node2D`, child of `Field`)
`_process(delta)`: `_clock += delta; queue_redraw()`. `look() -> int` (`Look { LIT, FLICKER, QUIET }`): QUIET when the field is QUIET or
suppressed, FLICKER in TELEGRAPH, LIT in ACTIVE. `ring_alpha() -> float`: LIT 0.35; FLICKER 0.35 / 0.1 toggling every 0.1 s of `_clock`;
QUIET 0.08. `_draw()`: LIT / FLICKER: a fill circle alpha 0.05 (LIT only) and 48 dashed arcs, each half of its `TAU / 48` slot, width 3,
`Color(1.0, 0.85, 0.55, ring_alpha())`, start angle offset by `0.4 * _clock` (the crawl; the node's `rotation` is never written); QUIET: one
1 px arc at alpha 0.08. `z_index` 4 (the EMP zone art's).

### 5. Scenes (written UID-less, no hand-typed UIDs)
`jamming_structure.tscn`: root `JammingStructure` (CharacterBody2D, layer 1 / mask 1 default), `CollisionShape2D` (CircleShape2D r 28),
`HurtBox` (layer 512, mask 65, the same circle sub-resource), `Health` (140), `HitFlashAnimationPlayer` (RESET / hit on `Hull:self_modulate`),
`ContactProfile` (mode 0 = NONE), `AssaultDrift` (60), `Hull` (placeholder `Polygon2D`, hexagon r 28, dark slate, no texture), `Emitter`
(`Polygon2D` dish r 10), `StateLight` (at the emitter), `Field` (`HazardField`: kind `jammer`, radius 240, core_radius 0, pull 0, penalty 0,
avoid 0, disables_abilities true, stabilise 0.75, cycles 0) with child `Art` (`JammerFieldArt`). No `ContactHitBox`, no brain, no mover.
`sector_jammer/sector_jammer.tscn`: same node list, own copy (not an inherited scene: the circle radius differs and an inherited scene's
sub-resource override is the harder thing to review), body r 42, Health 260, Field radius 640 / stabilise 1.25, `config` = its `.tres`.
`pulsed_jammer/pulsed_jammer.tscn`: r 28, Health 160, Field radius 300 / stabilise 0.75 / cycles 0.8 / 3.0 / 2.5, its `.tres`.
Each directory holds exactly one `*config*.tres`. Placeholder visuals until t12 (art task).

### 6. `WaveBuilder`
`JAMMER`, `SECTOR_JAMMER`, `PULSED_JAMMER` path constants and `jammer(variant: StringName = &"local") -> SpawnConfig` (`&"sector"`,
`&"pulsed"`, otherwise local; an unknown name `push_error`s and gives local). Doc comment: world-anchored x, sector is Open Space only, never
in an `ENEMIES_CLEARED` section.

### 7. `EnemyRocket` (`enemy_rocket.gd`)
In `_tick()`: `if is_guiding() and not _in_lit_jammer(): _steer(delta)`, with `_in_lit_jammer() -> bool: return Hazards.count() > 0 and
Hazards.jammer_at(global_position) != null`. `is_guiding()`, `_clock`, arming, blast and the EMP `_jammed` flag are unchanged, so with no
hazard registered the path is the same code path as before (every Ph5 row bit-identical). A rocket that leaves the field inside its
guidance window steers again.

### 8. `MissileCorvetteBrain._roll_kind()`
After the existing 1-in-4 swap (so the rng sequence is unchanged): `if (kind == PURSUIT or kind == CLUSTER) and Hazards.count() > 0 and
Hazards.jammer_at(target.position) != null: kind = DUMB`. `choose_kind()` and the forced branch (returns first) unchanged.

### 9. EMP Blast
No code change (t6 routes by `answers_emp()`; `JammingStructure` answers true). Its rows land here (§Test plan).

## Build sequence
1. Tests: `test_hazard_field.gd` suppress rows; `test_jamming_structure.gd` (all rows, failing: classes missing); corvette rows; EMP Blast
   jammer rows; roster entries. Watch them fail (parse errors count as failing for missing classes).
2. `HazardField.suppress` / `is_suppressed` / `restart_cycle`.
3. Config script + three `.tres`; `JammerFieldArt`; `JammingStructure`; three scenes.
4. `WaveBuilder` constants + `jammer()`.
5. `EnemyRocket` jammer skip; corvette downgrade.
6. Roster gate entries; `ENEMIES_CLEARED` guard + sector-never-in-Assault guard rows.
7. Run the new files, then `verify.sh`, `check-test-leaks.sh`, `gate-time.sh`.
8. Docs: `ENEMY.md` ×1 (covers the three variants), `docs/enemy-roster.md`, `assault.md` / `global.md` / `PROJECT.md` lines, `CLAUDE.md`
   line, `DECISIONS.md` "built in t7", `tests/README.md` gate row.

## Test plan
`tests/unit/test_hazard_field.gd` (additions):
- `test_suppress_quiets_disables_abilities_for_the_window_and_keeps_the_cycle`: a lit always-on jammer field, `suppress(1.0)`: info false at
  once, still false after tick 59, true after tick 60 (clock rule); a second `suppress(0.5)` mid-window does not shorten it (longest wins);
  `suppress(0)` is a no-op. Boundary: a non-jammer field (`disables_abilities` false) is bit-identical (all info fields) with and without suppress.

`tests/integration/test_jamming_structure.gd` (both harnesses where the row is mode-dependent; real player scenes for the lock rows):
1. `test_each_variant_matches_its_config_and_registers_a_jammer(variant)` ×3 (both harnesses inside): the plan table values in the `.tres`;
   the scene `Field` exports equal the config; `Health.max_health` equals the config; the registered info: kind `jammer`, avoid 0, pull 0,
   penalty 0, radius, `stabilise_seconds`, `disables_abilities` true (local / sector); `Hazards.jammer_at` at radius − 1 found, radius + 1 not.
   Also: in `enemies`, `is_laser_blocking()` false, `accept_tow()` false, `counts_as_escape` false, `ContactProfile` NONE, no
   `ContactHitBox`, no brain / mover.
2. `test_pulsed_phases_follow_0_8_3_0_2_5_and_lock_only_in_active`: hand-ticked; the phase changes on exactly ticks 48 (-> ACTIVE, 0.8 s),
   229 (-> QUIET; the `fposmod` sum sits just under 3.8 on tick 228), 379 (-> TELEGRAPH) and 427 (-> ACTIVE); pinned exactly (measured in headless
   Godot by the review, deterministic); `jammer_at(centre)` non-null exactly in ACTIVE; art look / light state per phase.
3. `test_a_real_ship_inside_is_locked_and_unlocks_0_75_s_after_the_jammer_is_shot_dead(mode)` (both real player scenes): ship at the centre,
   one sample = locked; real `bullet.tscn` shots from inside the field (real physics, 8×) kill the jammer (`was_killed`); the next sample is
   the exit tick T; locked at T+44, unlocked at T+45.
4. `test_assault_drift_is_60_px_s_and_frees_below_the_world_rect_and_x_is_world_anchored`: Assault harness, camera panned +100: spawned at
   the WaveManager formula for design `(-64, -100)`, root x = 640 + 2·(−64) = 512; drift +60 px over 60 hand-steps; placed below the world
   rect, one step queues it; the `Field` moves with it. Control: `world_anchored_x` false keeps 612. Open Space: no drift, x untouched.
5. `test_a_fighters_path_through_a_jammer_field_is_unchanged(mode)`: the real Fighter APPROACH (the `_fighter_past_a_well` shape) with a real
   local jammer whose field covers the leg (body 120 px off the line) vs. a run with no jammer: positions equal tick for tick (≤ 1e-4 px);
   non-vacuity: the path enters the field.
6. `test_an_enemy_pursuit_rocket_flies_straight_inside_a_lit_field_and_steers_after(mode)`: hand-ticked Pursuit rocket entering a small lit
   field (r 100) inside its guidance window: heading constant on every tick inside; it turns again after leaving (still guiding). Control:
   the same rocket with no field turns inside that stretch. DUMB rocket: path identical with and without the field.
7. `test_a_pulsed_field_in_quiet_jams_nothing`: a pulsed jammer stepped into QUIET over a Pursuit rocket's path: the rocket's headings equal
   a no-field twin's.
8. `test_a_suppressed_pulsed_jammer_keeps_its_cycle_phase`: two pulsed jammers stepped into ACTIVE; `apply_emp(2.0, null)` on one: its info
   quiet while the twin's is lit, `is_emp_disrupted()` true, `EmpStatic` visible, art look QUIET, light OFF; after 120 ticks phase and
   `phase_progress()` equal the twin's, and once both are in ACTIVE again both are lit.
9. `test_wave_builder_jammer_variants`: `jammer()` / `jammer(&"sector")` / `jammer(&"pulsed")` scene paths equal the constants and load as
   `JammingStructure`.

`tests/integration/test_emp_blast_module.gd` (additions, both real player scenes, hand-ticked at 1/60 except the bullet):
10. `test_from_outside_the_field_the_blast_switches_a_jammer_off_for_five_seconds(mode)`: ship 120 px outside the local field (unlocked),
    `emp_blast` equipped, H pushed through the real `_input` (`Viewport.push_input`): handled, cooldown 15; field info `disables_abilities`
    false at once and after one jammer tick; a real bullet (8×) damages the jammer meanwhile (field clock frozen while it flies: jammer
    and field are hand-ticked); the field is quiet after tick 299 and lit by tick 301 (5.0 s ±1 tick).
11. `test_inside_a_lit_field_the_blast_press_is_refused(mode)`: ship at the centre, one sample (locked); H pushed: `ability_press_refused`
    once, `_cooldown_left` 0, field still lit, jammer not EMP'd.
12. `test_a_direct_try_activate_from_inside_quiets_the_field_and_the_ship_unlocks_0_75_s_later(mode)`: documented as bypassing the seam
    (which would refuse it); `try_activate(player)` true; field quiet at once; next sample = exit tick T; locked at T+44, unlocked T+45.

`tests/integration/test_missile_corvette.gd` (additions):
13. `test_a_player_inside_a_jammer_field_turns_pursuit_and_cluster_rolls_dumb`: the 200-roll loop of
    `test_one_dumb_choice_in_four_becomes_a_pursuit_salvo` with a jammer field on the player: dumb case 200 DUMB (the swap's Pursuit is
    downgraded), cluster case 200 DUMB, warhead case 200 WARHEAD. Control: the field 600 px away from the player → the existing shares
    (Pursuit share 0.15–0.35, 200 CLUSTER). `force_next_kind(PURSUIT)` inside the field still fires PURSUIT.

Roster gates: `test_enemy_contact_damage.gd` / `test_contact_hitbox_geometry.gd` ROSTER (+3, `no_hitbox`), `test_enemy_hurtbox_geometry.gd`
ROSTER (+3), `test_base_enemy.gd` (`_AUTHORED_CONTACT_MODES` +3 NONE, `_MIN_ROSTER_SIZE` 20 → 23), `test_enemy_dual_mode.gd`
(`test_jammers_lock_in_both_modes_and_drift_only_in_assault(case)` — 3 variants × 2 modes: in `enemies`, `jammer_at` found at the centre,
drift only in Assault), `test_engagement_deadline.gd` (`test_no_enemies_cleared_section_spawns_a_jammer` for all three paths + boundary;
`test_no_assault_section_spawns_a_sector_jammer` + boundary). Automatic: config isolation, sprite transparency, project load, signal arity.

Boundary cases: tick 299 / 301 for the 5 s window; T+44 / T+45 for the delay; radius ± 1 for `jammer_at`; the guard-row boundaries.

## Risks
- Real-bullet rows: the bullet must reach the HurtBox in a few frames; place it 60 px away aimed at the centre (the t6 fighter row's shape).
- `move_and_slide()` on a hand-ticked Fighter near the jammer body: the body is placed 120 px off the approach line.
- Gate time: allotment 2.7 s. Most rows hand-ticked; the three bullet rows at 8×.
- `_push_h()` requires exactly one player in the tree: each EMP Blast row frees its box before the other mode's ship is built.

## Out of scope
Art (t12), hub placement (t13), level 1 placement (t14), the Hacker (t8–t10), docs beyond this task's lines (t15).

## Revision 1 (review round 1, `4-review.md`)

1. **EMP zone reaches a jammer (deferred t11 row).** New row in `tests/integration/test_emp_zone.gd`,
   `test_a_jammer_inside_the_zone_goes_quiet_for_the_pulse(mode)`: a hand-ticked local jammer whose centre is exactly 260 px (the edge: inside by `<= radius`) from the zone centre and a
   twin 261 px away; the zone's field stepped to its TELEGRAPH -> ACTIVE edge: the near jammer's info is quiet on that tick, `is_emp_disrupted()`;
   still quiet after 119 jammer ticks, lit after 120 (2.0 s); the far twin stays lit throughout. Both harnesses. Build step 1; gate-time ≈ +0.05 s.
2. **Pulsed ticks** pinned exactly at 48 / 229 / 379 / 427 (row 2 text corrected above).
3. **Spot selectors treat a jammer field as their own ground (option a).** `SniperBrain._candidate()` (the non-blocker `hazard_ok` loop),
   `SniperBrain._inside_other_hazard()` and `FighterBrain._inside_other_hazard()` skip `info.kind == &"jammer"` (`continue`). No Ph4–Ph8 hazard
   has that kind, so every earlier row is bit-identical. Logged in `DECISIONS.md` under "Phase 9, built in t7". Rows (in
   `test_jamming_structure.gd`, both harnesses, the `test_sniper.gd::test_a_candidate_inside_a_well_is_never_chosen` shape):
   `test_a_snipers_firing_point_inside_a_jammer_field_is_kept`: the control sniper's point; a real local jammer centred on it; a second sniper
   with the same seed picks the same point and every candidate in the field is `hazard_ok`; boundary/control: the same point under a well
   stand-in (`FIXTURE_WRECK` non-blocker, kind gravity_well) is rejected (that existing row, unchanged). And
   `test_a_fighter_cover_point_inside_a_jammer_field_is_kept`: `FighterBrain._inside_other_hazard(point, wreck_info)` with a lit jammer over the
   point returns false; with a gravity-well field over it, true.
4. **Corvette row** gains a "pursuit" case (player fleeing radially at 350 px/s, above `pursuit_flee_speed`, the
   `test_a_fleeing_player_draws_a_pursuit_salvo` set-up): 200 DUMB inside the field; control 600 px away: 200 PURSUIT.
5. **Fighter row positive control:** the same jammer field set to `avoid_weight = 1.0` (written on the field, refreshed) bends the path
   (worst deviation > 5 px), proving avoidance is live in that set-up.
6. **Timing statements.** Row 3: the exit tick T is the first player sample taken after `not is_instance_valid(jammer)` and
   `Hazards.jammer_at(player) == null` (the field stays registered between `was_killed` and the deletion flush). Row 10: the jammer root, its
   `Field`, `Field/Art` and `AssaultDrift` have physics / process off for the whole row, so the 8× frames the bullet flies on advance neither
   the BaseEnemy EMP clock nor the suppression clock; both are hand-ticked root first, then the field.
8. **`restart_cycle()`** gets a row: a local jammer whose private config is given cycle 1.0 / 1.0 / 1.0 and `field_radius` 100 before
   `add_child` registers radius 100 and starts in TELEGRAPH, unlit, at once (plus the unit row in `test_hazard_field.gd`).
9. **Cluster note:** only `_steer()` is skipped; a Cluster rocket's split still aims at its predicted point inside a field. ENEMY.md says so.
