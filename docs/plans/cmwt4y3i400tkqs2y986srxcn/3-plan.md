# t11 — Retire the space station; migrate every station test to the Space Fortress

Implements epic plan §2.11 (Ph11 owner choice 1) exactly; this plan only makes each row concrete.

## Problem
Level 1 and the hub fight the Space Fortress (t10, t13); the legacy `SpaceStation` is dead code that still costs gate time (its
own seven test files) and still anchors a dozen gates and comments. Player-facing: nothing changes. Developer-facing: one boss, and every
invariant the station proved (armour lets shots cross, collision bits, layer-0 root, death spectacle, hurtbox coverage, art transparency)
is proved on the fortress instead, never silently dropped.

## Design
Delete, then re-point. No production behaviour changes; production edits are deletions, a private variable rename in
`BossDeathSequence` (`_station` → `_host`, plan §2.4 named it so) and comments.

### Deletions
- `assault/scenes/enemies/space_station/` whole (scripts, scenes, config, `ENEMY.md`, `.uid` sidecars).
- `WaveBuilder.space_station()` and `SPACE_STATION`.
- `station_core.png`, `station_turret.png`, `station_turret_destroyed.png` and their `.import` files (no reference remains after the
  re-points below; checked with grep before deleting).
- `test_space_station.gd`, `test_station_laser_phase.gd`, `test_station_gunnery.gd`, `test_station_reinforcements.gd` (+ `.uid`):
  intent lives in `test_space_fortress.gd`, `test_fortress_weapons.gd`, `test_boss_reinforcements.gd`, `test_fortress_reinforcements.gd`.

### Renames + re-points (`git mv`, `.uid` sidecar moves with it)
1. `test_station_death_sequence.gd` → `test_boss_death_sequence.gd`, on a real fortress in a container (physics off on the root,
   so the mover never writes `rotation`; the death sequence's own physics process runs). Death trigger: `part(&"core").destroy()`
   (no armour to break). Rows kept one-for-one: wreck stays; `died` / `was_killed` at 0 HP once; no re-emit; corpse harmless
   (contact layer 256 → 0, hurtbox off); freed after `death_duration`; duration 0 = same-call free (`is_queued_for_deletion`);
   blasts land in the container at `blast_spread_radius` (150) off centre; offsets deterministic across two fortresses; every blast
   on the hull (`< hull_radius()` 176, read from the fortress, not 128); drift + darken; spin decays; config copy
   (`death_duration == cfg.death_sequence_duration`, shipped 2.4 s / 10 blasts); script defaults differ (`SpaceFortressConfig.new()`
   — read its defaults, pin them, and keep the "differs from 2.4 / 10" assertions); writing the node field never writes the config;
   the host-contract row (now `seq._host`).
2. `test_station_incoming_damage_paths.gd` → `test_fortress_incoming_damage_paths.gd`, real physics at 8×, both harnesses
   (`use_parameters(["open_space", "assault"])`), fortress physics off. South generator `destroy()`ed first where a battery must be
   reached (bubbles detach in the same call), so the shot meets the battery, not a bubble.
   - homing missile `locked_target = fortress`, fired from local (99, 300): steers via `homing_point()` to `BatterySpread`, the hull
     emits `armor_deflected`, the missile survives the hull and detonates on the battery for 100; root `health` unchanged.
   - warhead fired straight up local x 99: same, 50 damage.
   - asteroid at local (60, −50) (clear of every part: core 78 > 72, north generator 92 > 54, missiles battery 62.6 > 50): hull
     `armor_deflected` with 40, root health unchanged (bit 1024).
   - mining laser up local x 0 from 300 px below: endpoint at full ray length (not blocked by the layer-0 root) and the beam pings
     the parts on its line (`ShieldSouth.deflected`); a second row up x 99 with the south generator dead burns `BatterySpread`.
   - BOUNDARY: root `collision_layer = 1` → endpoint truncated at the hull edge (local y +176, ±2) and nothing on the line pinged.

### Row edits
- `test_enemy_contact_damage.gd`, `test_contact_hitbox_geometry.gd`: drop the `space_station` ROSTER entry (fortress already in).
- `test_enemy_hurtbox_geometry.gd`: drop ROSTER entry; `test_the_88x240_proposal_fails_this_sweep` → `test_shrinking_the_fortress_hull_hurtbox_to_the_core_fails_this_sweep`
  (fresh `CircleShape2D` r = the core's radius read from `Modules/Core/HurtBox`, assigned to the instance's hull hurtbox shape node; assert
  `_covers` false and the shortfall per edge = 176 − 44 = 132, read from the shapes); `test_the_station_core_hurtbox_spans_the_hull...` →
  `test_the_fortress_hull_hurtbox_covers_every_part` (hull covers body; every part's hurtbox reach — centre distance + radius, or farthest
  rectangle corner — ≤ the hull circle radius; non-vacuity: 9 parts measured). Header prose re-worded to the fortress (the 88×240 decision
  stays cited by its plan directory).
- `test_entity_sprite_transparency.gd`: `test_the_station_core_has_sky_around_it` → `test_the_fortress_hull_has_sky_around_it`
  (`fortress_hull.png` four corners alpha 0, opaque fraction < 0.60 — measure first and keep the bound only if it holds; else pin the
  measured value + slack); control texture → `battery_spread.png`. Re-check `MIN_SCENES` / `MIN_TEXTURES` floors still hold.
- `test_config_instance_isolation.gd`: delete the station-children row and `STATION_SCENE`; header line re-worded to the fortress row.
- `test_spawn_camera_pan.gd`: delete the two `StationReinforcements` rows and `STATION_SCENE` (t8 row 6 replaces them); header re-worded.
- `test_explosion_effect_placement.gd`: turret row → a fortress battery `destroy()`ed: exactly one burst in the fortress's container at the
  battery's global position (and none under the fortress).
- `test_level1_drone_spawns.gd`: delete the BOTTOM-squad row, `_STATION_SCENE` and the header mention.
- `test_base_enemy.gd`: delete the station-turret extra case and `_STATION_TURRET_SCENE`, replaced by "every fortress part's hurtbox mask
  is 1120" (the part value: bullets 64, rockets 32, asteroid 1024; root keeps 1121 in the sweep); `_EXCLUDED_FROM_GENERIC_DAMAGE_FLOW`
  drops `space_station`; `_MIN_ROSTER_SIZE` 26 → 25 and its list; refuse-repair row → the fortress; header re-worded.
- `test_enemy_bullet_lifetime.gd`: drop `StationGunnery.new()` and `space_station_config.tres` sources. Run, read `speeds.min()`, then
  `test_every_shipped_speed_source_is_at_or_above_150` → `test_the_slowest_shipped_speed_source_is_<name>_at_<v>` pinning name + value
  (≥ 150 still asserted as the floor that keeps the shipped 18 s honest); the derived test pins `expected_max_time = ceil(2274.06 / min) + 2`
  and `expected_max_distance` 2400 as the computed values and keeps asserting the shipped `max_time` 18 / `max_distance` 2400 ≥ them.
- `test_engagement_deadline.gd`: `STATION_REINFORCEMENTS_SOURCE` → the scan reads every `global/boss/*.gd`, every
  `assault/scenes/enemies/space_fortress/*.gd` and `space_fortress.tscn`; the sanity row asserts `space_fortress.tscn` was read and names a
  bay payload; the synthetic "station reinforcements naming emp_zone.tscn" boundary → "`space_fortress.tscn` naming emp_zone.tscn".
  The scanned set's current text has no needle (checked: grep clean).
- `test_enemy_module.gd` + `tests/helpers/fixture_modular_host.tscn`, one change: fixture `intact_texture` / `wreck_texture` → fortress
  `battery_spread.png` / `battery_spread_wreck.png`; `WRECK_TEXTURE` preload → `battery_spread_wreck.png`; the driver-comment citation re-worded.
- `test_level_1_sequence.gd`: rename the `_station` var to `_fortress` (no station type or preload is left; cosmetic).
- Comments (table rows "comments citing the station" and "comment-only citations"): re-word to the fortress's armoured hull or drop the
  history, no behaviour change. Including `boss_death_sequence.gd` and `space_fortress.gd`'s "The station's death order".
- Any other hit of the anchored grep: re-point or delete, named in the final report.

### Docs
`updating-project-docs` for the deletion: `docs/enemy-roster.md` (the `b.space_station()` entry), `docs/architecture/modules/assault.md` /
`PROJECT.md` / `CLAUDE.md` lines that name deleted files or tests (point them at the fortress replacements). t14 keeps the phase pass.
Gate-time row in `tests/README.md`. DECISIONS line only if something departs from §2.11.

## Build sequence
1. Record baseline GUT time (two `scripts/gate-time.sh` runs) — or reuse t13's recorded mean if measuring twice is too slow; note which.
2. Rename + rewrite the two re-pointed files; run them alone; green.
3. Row edits in the gates (one file at a time, each run alone).
4. Fixture retexture + `WRECK_TEXTURE`; run `test_enemy_module.gd`, `test_shield_sector.gd`, `test_boss_phase_rules.gd`.
5. Delete the four station test files, then the station folder, builder entries, PNGs; `godot --import`.
6. Comments; the anchored grep returns nothing outside `docs/`; Fortuna's `space_stations/` untouched (`git status`).
7. Docs; full gate `bash /agent/verify.sh`; `scripts/check-test-leaks.sh`; gate-time two runs; README row.

## Test plan
- `test_boss_death_sequence.gd`: 15 rows above; boundary: duration 0 frees in the same call; the no-contract host warning row.
- `test_fortress_incoming_damage_paths.gd`: 6 rows × 2 harnesses; boundary: layer-1 root truncates the beam at y +176.
- `test_enemy_hurtbox_geometry.gd`: boundary = core-sized hull hurtbox fails; coverage row with 9 parts.
- `test_enemy_bullet_lifetime.gd`: re-pinned min source and derived max_time; synthetic 100 px/s boundary unchanged.
- `test_engagement_deadline.gd`: scan reads the fortress scene; synthetic fortress-scene boundary fails.
- Gates that must stay green: roster / transparency / isolation / UID integrity / project load / suite integrity / signal arity.

## Risks
- A comment-only edit that drops a `class_name` mention could change script compile order: none of the edits touch code lines.
- Deleting `station_turret_destroyed.png` could re-open the leak `test_base_enemy.gd`'s comment describes — the reference goes away with
  the class; the leak check runs after.
- The transparency fraction bound for the fortress hull is unknown until measured.
- `test_project_load_integrity.gd` / UID integrity: deleting files with `.uid` sidecars and `.import` together leaves no dangling UID; a stale
  `.godot/uid_cache.bin` is handled by the `--import` step.

## Out of scope
Fortuna's `open_space/scenes/mission_*/space_stations/`; the `station_assault` section name; `SpaceFortressConfig.station_ring_factor`
(a fortress field, not the anchored pattern); historical docs under `docs/plans/`, `docs/epics-done/`, `docs/ideas/`; the phase-close docs (t14).

## Revisions after review round 1 (4-review.md, CHANGES_REQUESTED) — these supersede the rows above where they differ

- **B1 mining-laser boundary.** The fortress has two guards against blocking the beam: root layer 0 **and** `is_laser_blocking()` false
  (`space_fortress.gd:490`, read by `beam_behavior.gd:66-68`). Rows become: (a) layer-0 fortress: full-length beam, `ShieldSouth` /
  core pinged (as above); (b) **a layer-1 fortress still lets the beam through** (pins the second guard: endpoint full length, parts on the
  line still pinged); (c) BOUNDARY: a plain `StaticBody2D` on layer 1 with a r 176 `CircleShape2D` at the same place cuts the beam at the near
  edge (y + 176 ± 2) — proves the ray would block a layer-1 body that does not answer `is_laser_blocking()`, so (a) and (b) are not vacuous.
  DECISIONS line under "Phase 11, built in t11": §2.11's "a layer-1 root would block it" holds for a body but not for the fortress, whose
  `is_laser_blocking()` false is a second guard; the boundary is expressed on a plain body.
- **B2 death-sequence defaults.** `SpaceFortressConfig.new()` already defaults to 2.4 / 10, so the "differs" row moves to the nodes:
  `SpaceFortress.death_duration` script default 0.0 (≠ 2.4, read from a freshly instantiated, not-yet-ready fortress) and a fresh
  `BossDeathSequence`'s `_blast_count` 3 (≠ 10) — the same shape as `test_space_fortress.gd:724-725`; the config-copy row then proves the copy.
- **S1 no re-emit.** Re-entry is driven by `health.set_health(0)` three times (the hull refuses `received_damage` while dying, so a damage
  emit never reaches `_on_health_changed`); `died` stays 1.
- **S2 asteroid damage lands.** Added row: south generator destroyed, asteroid at local (150, 0) over `BatterySweep`: the battery takes 40
  (bit 1024 of the part mask 1120), root health unchanged.
- **M1** `test_base_enemy.gd`: the replacement row sweeps every BaseEnemy roster scene's `Modules/*/HurtBox` and asserts mask 1120 (heavy
  gunship, carrier, fortress today; non-vacuity: ≥ 3 hosts, ≥ 20 parts).
- **M2** transparency: `test_the_fortress_hull_has_sky_around_it` asserts four corner alphas 0 **and** no pixel with alpha > 0 farther than
  185 px from the image centre (measured 0); control `battery_spread.png` (71.3 %).
- **M3** bullet lifetime: `_every_shipped_enemy_bullet_speed()` stays a flat `Array[float]` (callers unchanged); a sibling
  `_named_speed_sources() -> Array` of `[name, speed]` pairs backs it, and the re-pinned row asserts the min pair's name and value.
- **M4** extra stale citations re-worded (no behaviour): `test_ram_corvette.gd:436`, `tests/README.md` station passages (point at the
  fortress replacements / mark history), `docs/assault-spawning-scoring-internals.md:272`, `docs/architecture/modules/global.md:438`,
  `assault/scenes/hazards/laser_ray/HAZARD.md:47`, `docs/BULLET_POOL.md`, `.claude/skills/pixel-art-generation/SKILL.md` (as history:
  the files are gone), CLAUDE.md's test list.
- **M5** step 4 also runs `tests/unit/test_boss_phase_driver.gd`.
- **M6** `test_level_1_sequence.gd` rename dropped (optional churn; it holds no station type or preload).
