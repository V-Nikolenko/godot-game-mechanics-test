## Characterization: pins every Fighter (`WaveBuilder.FIGHTER`, now `Fighter`/
## `fighter.tscn` today) and Gatling Interceptor (`WaveBuilder.GATLING_INTERCEPTOR`, now
## `GatlingInterceptor`/`gatling_interceptor.tscn`) spawn in Level 1 — the state of the world BEFORE Enemy rework
## phase 3 touches any of it (docs/plans/cmufs7ekv000lnm2x7nbswijy/3-plan.md §2.9.1, task t1-pin).
## t6/t7 renamed the scenes and classes this file points at (no behaviour change, so this pin stays
## green); t16/t17 strip `.move()`/`.free_after()`/`shoot_*()` from the DURATION and ENEMIES_CLEARED
## sections respectively, at which point the per-section "live equals constant" legacy check below
## is retired for that section only, per §2.9.1 — the frozen `_LEGACY_PEAK_FIGHTERS` /
## `_LEGACY_PEAK_SHOTS_PER_S` constants themselves are NOT deleted: t16/t17's own density gates keep
## dividing by them.
##
## NOT an invariant — like `test_level1_drone_spawns.gd`, every number here is a deliberate design
## choice this file freezes, not a rule it derives. A failure means "the fighter/interceptor spawns
## changed", which is expected starting at t6 (rename) and t8-t17 (AI rebuild + migration).
##
## ── t16: deep_space and planet_approach are AI sections now ───────────────────────────────────
##
## t16 (docs/plans/cmulwkarm00cpqj2xfwq3ue8h/3-plan.md) took their fighters and the Gatling pair off
## rails: their 37 rows below keep trigger, offset, delay and formation, with `movement` false,
## `free_after` 0 and no `aim_mode`. Their density gates are at the bottom of this file (all-alive
## and attack-capable, analytic) and in `test_level1_fighter_fire_density.gd` (shots/s, measured on a
## real `WaveManager` run — the owner's option A, docs/plans/cmulwkarm00cpqj2xfwq3ue8h/5-escalation.md).
## t17 (docs/plans/cmulwkarp00ctqj2x6ih09c0k/3-plan.md) did the same for cloud_descent's 27 rows: nothing
## in level 1 flies a fighter or Gatling rail any more, and cloud_descent's gates divide by its own frozen
## constants (8 fighters, 15.0 shots/s).
##
## ── Why `_build_sections()`, not the level scene ─────────────────────────────────────────────
##
## Same reasoning as `test_level1_drone_spawns.gd`: `Level1Director._build_sections()` is callable
## on a bare, never-entered-tree instance, so this reads the wave data directly, in the same units
## and same code path `WaveManager` consumes.
##
## ── The legacy baselines are frozen constants, not re-derived every run ─────────────────────────
##
## Unlike Ph2's drones (one shared `_LEGACY_LIFETIME`, because every legacy drone dies in the same
## single ramming pass well under it), a fighter/interceptor rail has no shared lifetime: each
## entry's on-screen time is its OWN `free_after`, or its OWN `MovementResource` sampled from its
## OWN spawn offset until it leaves `ArenaCamera.enemy_cull_rect()` (review B6). `_rail_lifetime()`
## below reproduces exactly what `EnemyPathMover` does at runtime:
##   - `FREE_ON_DURATION` → `exit_time` (`enemy_path_mover.gd:97-99`);
##   - otherwise → sample `movement.sample(t) * ArenaCamera.WORLD_SCALE` from the entry's own
##     offset (`enemy_path_mover.gd:83-84`), and cull the instant it next exits
##     `enemy_cull_rect()` AFTER having been inside it at least once — the same has-been-on-screen
##     gate `_check_off_screen()` applies (`enemy_path_mover.gd:106-123`) — capped at 20 s.
## A `PlayerFocusMovement` (the deep_space interceptor pair) has no live player to aim at here, so
## its `direction` is set toward the camera centre from its own offset, matching the plan's "any
## player-focused movement aimed at the camera centre" (§2.9.1) — in the shipped game the camera
## tracks the player tightly (a 40x30 deadzone), so this is the same target `EnemyPathMover._ready()`
## would resolve against a stationary player.
##
## `_LEGACY_PEAK_SHOTS_PER_S` applies review N6's correction: a legacy shooter's rate is
## `min(1 / fire_interval, pool_size / round_lifetime)`, not a flat `1 / fire_interval` — a 20-round
## pool cannot sustain the Gatling's 1/0.09 s/round forever. `round_lifetime` is `max_distance /
## bullet_speed` — the same formula the plan's own pool-sizing arithmetic uses throughout §2.2
## ("lifetime = max_distance / speed") — with `max_distance` read live off `ProjectileLifetime` on
## the round each ship's own pool fires (review round 1 finding 3, t10 review A4; NOT
## `ArenaCamera.projectile_world_rect()`'s diagonal, which is a camera/culling rect no shot's own
## expiry rule ever consults). Pool size, fire interval and bullet speed are likewise read live by
## instantiating the actual ships, never hand-typed (review round 1 finding 2) — see
## `_live_attack_stats()`. Only the interceptor's rate is actually capped by this (its pool —
## 20 when frozen, 36 since t10 — against its round life caps it well below its flat 1/0.09 rate; the
## pair sits outside deep_space's peak window, so the frozen peak is unaffected); the fighter's
## forward/aimed rates stay well under their own pool's ceiling.
##
## Both constants are filled in from the FIRST computed run — nothing here is typed from the plan
## — and `test_legacy_peak_fighters_and_shots_per_s_match_frozen_constants()` asserts the live
## computation equals them, section by section, while the rails exist.
extends GutTest

const _DIRECTOR_SCRIPT := "res://assault/scenes/levels/edelia/1/level_1_director.gd"

const DroneConcurrency := preload("res://tests/helpers/level1_drone_concurrency.gd")

const _FIGHTER := WaveBuilder.FIGHTER
const _GATLING := WaveBuilder.GATLING_INTERCEPTOR

## The rail sampling cap (§2.9.1) and step. 20 s comfortably exceeds every real rail's lifetime
## (the longest `free_after` in the pin below is 12 s); 0.02 s keeps the cull-rect crossing
## reasonably precise without the sweep costing real time — this runs once per section.
const _CULL_CAP: float = 20.0
const _CULL_STEP: float = 0.02


## Every FIGHTER / GATLING_INTERCEPTOR entry in `_build_sections()`, in encounter order, as pinned from a
## computed run of `_actual_fighter_spawns()` below (this task's HEAD — see `git log`). `aim_mode`
## is the literal `SpawnConfig.shoot_forward()`/`.shoot_at_player()` string ("" when neither was
## called — a rail ship then falls back to its config default, "PLAYER"; an AI ship ignores it).
## deep_space and planet_approach rows are AI rows since t16, cloud_descent's since t17 (no movement, no aim_mode). `free_after` is the
## `.free_after(seconds)` value, or 0.0 when the entry uses the default FREE_ON_SCREEN_EXIT.
## Regenerate by walking `_build_sections()` the same way `_actual_fighter_spawns()` does — never
## hand-edit a single row without re-deriving the whole table.
const EXPECTED: Array[Dictionary] = [
	{"section": &"deep_space", "kind": "GATLING_INTERCEPTOR", "trigger": 0.00, "offset": Vector2(-200.0, -420.0), "delay": 0.00, "formation": &"none", "formation_count": -1, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"deep_space", "kind": "GATLING_INTERCEPTOR", "trigger": 0.00, "offset": Vector2(200.0, -420.0), "delay": 0.40, "formation": &"none", "formation_count": -1, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"deep_space", "kind": "FIGHTER", "trigger": 2.00, "offset": Vector2(-150.0, -400.0), "delay": 0.50, "formation": &"VFormation", "formation_count": 5, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"deep_space", "kind": "FIGHTER", "trigger": 5.00, "offset": Vector2(260.0, -400.0), "delay": 0.50, "formation": &"VFormation", "formation_count": 3, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"deep_space", "kind": "FIGHTER", "trigger": 6.50, "offset": Vector2(-500.0, -30.0), "delay": 0.00, "formation": &"none", "formation_count": -1, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"deep_space", "kind": "FIGHTER", "trigger": 6.50, "offset": Vector2(500.0, -30.0), "delay": 0.30, "formation": &"none", "formation_count": -1, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"deep_space", "kind": "FIGHTER", "trigger": 8.00, "offset": Vector2(370.0, -400.0), "delay": 0.00, "formation": &"DiagonalFormation", "formation_count": 5, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"deep_space", "kind": "FIGHTER", "trigger": 13.50, "offset": Vector2(-500.0, 30.0), "delay": 0.00, "formation": &"none", "formation_count": -1, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"deep_space", "kind": "FIGHTER", "trigger": 14.00, "offset": Vector2(-370.0, -400.0), "delay": 0.00, "formation": &"DiagonalFormation", "formation_count": 5, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"deep_space", "kind": "FIGHTER", "trigger": 17.00, "offset": Vector2(-500.0, 30.0), "delay": 0.40, "formation": &"none", "formation_count": -1, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"deep_space", "kind": "FIGHTER", "trigger": 18.50, "offset": Vector2(-500.0, 0.0), "delay": 0.00, "formation": &"none", "formation_count": -1, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"deep_space", "kind": "FIGHTER", "trigger": 18.50, "offset": Vector2(500.0, 0.0), "delay": 0.30, "formation": &"none", "formation_count": -1, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"deep_space", "kind": "FIGHTER", "trigger": 20.00, "offset": Vector2(260.0, -400.0), "delay": 0.50, "formation": &"none", "formation_count": -1, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"deep_space", "kind": "FIGHTER", "trigger": 20.00, "offset": Vector2(-260.0, -400.0), "delay": 0.50, "formation": &"none", "formation_count": -1, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"deep_space", "kind": "FIGHTER", "trigger": 24.00, "offset": Vector2(0.0, -400.0), "delay": 0.00, "formation": &"WedgeFormation", "formation_count": 5, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"deep_space", "kind": "FIGHTER", "trigger": 25.00, "offset": Vector2(-500.0, -30.0), "delay": 0.00, "formation": &"none", "formation_count": -1, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"deep_space", "kind": "FIGHTER", "trigger": 25.00, "offset": Vector2(500.0, -30.0), "delay": 0.40, "formation": &"none", "formation_count": -1, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"deep_space", "kind": "FIGHTER", "trigger": 29.00, "offset": Vector2(0.0, -400.0), "delay": 0.30, "formation": &"none", "formation_count": -1, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"planet_approach", "kind": "FIGHTER", "trigger": 5.00, "offset": Vector2(-260.0, -400.0), "delay": 0.00, "formation": &"VFormation", "formation_count": 3, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"planet_approach", "kind": "FIGHTER", "trigger": 11.00, "offset": Vector2(-500.0, -30.0), "delay": 0.00, "formation": &"none", "formation_count": -1, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"planet_approach", "kind": "FIGHTER", "trigger": 20.00, "offset": Vector2(260.0, -400.0), "delay": 0.00, "formation": &"VFormation", "formation_count": 3, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"planet_approach", "kind": "FIGHTER", "trigger": 20.00, "offset": Vector2(-500.0, 30.0), "delay": 0.50, "formation": &"none", "formation_count": -1, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"planet_approach", "kind": "FIGHTER", "trigger": 39.00, "offset": Vector2(-500.0, 50.0), "delay": 0.00, "formation": &"none", "formation_count": -1, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"planet_approach", "kind": "FIGHTER", "trigger": 39.00, "offset": Vector2(500.0, 50.0), "delay": 0.40, "formation": &"none", "formation_count": -1, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"planet_approach", "kind": "FIGHTER", "trigger": 47.00, "offset": Vector2(500.0, -30.0), "delay": 0.00, "formation": &"none", "formation_count": -1, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"planet_approach", "kind": "FIGHTER", "trigger": 50.00, "offset": Vector2(0.0, -400.0), "delay": 0.00, "formation": &"VFormation", "formation_count": 5, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"planet_approach", "kind": "FIGHTER", "trigger": 58.00, "offset": Vector2(-500.0, -30.0), "delay": 0.60, "formation": &"none", "formation_count": -1, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"planet_approach", "kind": "FIGHTER", "trigger": 58.00, "offset": Vector2(500.0, -30.0), "delay": 0.60, "formation": &"none", "formation_count": -1, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"planet_approach", "kind": "FIGHTER", "trigger": 72.00, "offset": Vector2(-220.0, -400.0), "delay": 0.00, "formation": &"DiagonalFormation", "formation_count": 3, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"planet_approach", "kind": "FIGHTER", "trigger": 72.00, "offset": Vector2(220.0, -400.0), "delay": 0.30, "formation": &"DiagonalFormation", "formation_count": 3, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"planet_approach", "kind": "FIGHTER", "trigger": 78.00, "offset": Vector2(-500.0, 60.0), "delay": 0.00, "formation": &"none", "formation_count": -1, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"planet_approach", "kind": "FIGHTER", "trigger": 78.00, "offset": Vector2(500.0, 60.0), "delay": 0.30, "formation": &"none", "formation_count": -1, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"planet_approach", "kind": "FIGHTER", "trigger": 80.00, "offset": Vector2(375.0, -400.0), "delay": 0.00, "formation": &"DiagonalFormation", "formation_count": 5, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"planet_approach", "kind": "FIGHTER", "trigger": 80.00, "offset": Vector2(-280.0, -400.0), "delay": 0.40, "formation": &"DiagonalFormation", "formation_count": 3, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"planet_approach", "kind": "FIGHTER", "trigger": 98.00, "offset": Vector2(-180.0, -400.0), "delay": 0.40, "formation": &"none", "formation_count": -1, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"planet_approach", "kind": "FIGHTER", "trigger": 98.00, "offset": Vector2(180.0, -400.0), "delay": 0.40, "formation": &"none", "formation_count": -1, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"planet_approach", "kind": "FIGHTER", "trigger": 102.00, "offset": Vector2(0.0, -400.0), "delay": 0.00, "formation": &"WedgeFormation", "formation_count": 5, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"cloud_descent", "kind": "FIGHTER", "trigger": 5.00, "offset": Vector2(-500.0, 20.0), "delay": 0.00, "formation": &"none", "formation_count": -1, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"cloud_descent", "kind": "FIGHTER", "trigger": 5.00, "offset": Vector2(-500.0, 60.0), "delay": 0.30, "formation": &"none", "formation_count": -1, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"cloud_descent", "kind": "FIGHTER", "trigger": 5.00, "offset": Vector2(-500.0, 100.0), "delay": 0.60, "formation": &"none", "formation_count": -1, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"cloud_descent", "kind": "FIGHTER", "trigger": 14.00, "offset": Vector2(500.0, 20.0), "delay": 0.00, "formation": &"none", "formation_count": -1, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"cloud_descent", "kind": "FIGHTER", "trigger": 14.00, "offset": Vector2(500.0, 60.0), "delay": 0.30, "formation": &"none", "formation_count": -1, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"cloud_descent", "kind": "FIGHTER", "trigger": 14.00, "offset": Vector2(500.0, 100.0), "delay": 0.60, "formation": &"none", "formation_count": -1, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"cloud_descent", "kind": "FIGHTER", "trigger": 26.00, "offset": Vector2(-260.0, -400.0), "delay": 0.00, "formation": &"none", "formation_count": -1, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"cloud_descent", "kind": "FIGHTER", "trigger": 26.00, "offset": Vector2(260.0, -400.0), "delay": 0.30, "formation": &"none", "formation_count": -1, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"cloud_descent", "kind": "FIGHTER", "trigger": 38.00, "offset": Vector2(-500.0, 0.0), "delay": 0.00, "formation": &"none", "formation_count": -1, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"cloud_descent", "kind": "FIGHTER", "trigger": 38.00, "offset": Vector2(500.0, 0.0), "delay": 0.30, "formation": &"none", "formation_count": -1, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"cloud_descent", "kind": "FIGHTER", "trigger": 42.00, "offset": Vector2(-500.0, 0.0), "delay": 0.00, "formation": &"none", "formation_count": -1, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"cloud_descent", "kind": "FIGHTER", "trigger": 42.00, "offset": Vector2(-500.0, 60.0), "delay": 0.40, "formation": &"none", "formation_count": -1, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"cloud_descent", "kind": "FIGHTER", "trigger": 42.00, "offset": Vector2(500.0, 0.0), "delay": 0.00, "formation": &"none", "formation_count": -1, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"cloud_descent", "kind": "FIGHTER", "trigger": 42.00, "offset": Vector2(500.0, 60.0), "delay": 0.40, "formation": &"none", "formation_count": -1, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"cloud_descent", "kind": "FIGHTER", "trigger": 42.00, "offset": Vector2(-500.0, 120.0), "delay": 0.80, "formation": &"none", "formation_count": -1, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"cloud_descent", "kind": "FIGHTER", "trigger": 42.00, "offset": Vector2(500.0, 120.0), "delay": 0.80, "formation": &"none", "formation_count": -1, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"cloud_descent", "kind": "FIGHTER", "trigger": 50.00, "offset": Vector2(-65.0, -400.0), "delay": 0.80, "formation": &"none", "formation_count": -1, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"cloud_descent", "kind": "FIGHTER", "trigger": 50.00, "offset": Vector2(0.0, -400.0), "delay": 0.80, "formation": &"none", "formation_count": -1, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"cloud_descent", "kind": "FIGHTER", "trigger": 50.00, "offset": Vector2(65.0, -400.0), "delay": 0.80, "formation": &"none", "formation_count": -1, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"cloud_descent", "kind": "FIGHTER", "trigger": 59.00, "offset": Vector2(0.0, -400.0), "delay": 0.00, "formation": &"WedgeFormation", "formation_count": 3, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"cloud_descent", "kind": "FIGHTER", "trigger": 66.00, "offset": Vector2(-500.0, 40.0), "delay": 0.00, "formation": &"none", "formation_count": -1, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"cloud_descent", "kind": "FIGHTER", "trigger": 66.00, "offset": Vector2(500.0, 40.0), "delay": 0.00, "formation": &"none", "formation_count": -1, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"cloud_descent", "kind": "FIGHTER", "trigger": 72.00, "offset": Vector2(-500.0, 40.0), "delay": 0.00, "formation": &"none", "formation_count": -1, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"cloud_descent", "kind": "FIGHTER", "trigger": 72.00, "offset": Vector2(500.0, 40.0), "delay": 0.00, "formation": &"none", "formation_count": -1, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"cloud_descent", "kind": "FIGHTER", "trigger": 72.00, "offset": Vector2(0.0, -400.0), "delay": 0.50, "formation": &"VFormation", "formation_count": 3, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"cloud_descent", "kind": "FIGHTER", "trigger": 72.00, "offset": Vector2(-500.0, 100.0), "delay": 0.80, "formation": &"none", "formation_count": -1, "aim_mode": "", "free_after": 0.00, "movement": false},
	{"section": &"cloud_descent", "kind": "FIGHTER", "trigger": 72.00, "offset": Vector2(500.0, 100.0), "delay": 0.80, "formation": &"none", "formation_count": -1, "aim_mode": "", "free_after": 0.00, "movement": false},
]

## Legacy per-section peaks, from a computed run — asserted as computed values below, not merely
## quoted (§2.9.1, review B6).
const _LEGACY_PEAK_FIGHTERS: Dictionary = {
	&"deep_space": 10,
	&"planet_approach": 10,
	&"cloud_descent": 8,
}

const _LEGACY_PEAK_SHOTS_PER_S: Dictionary = {
	&"deep_space": 31.25,
	&"planet_approach": 33.333333333333336,
	&"cloud_descent": 15.0,
}


## Callable on a bare, never-entered-tree instance — see the file header.
func _build_sections() -> Array[LevelSection]:
	var script := load(_DIRECTOR_SCRIPT)
	var inst: Node = script.new()
	var sections: Array[LevelSection] = inst._build_sections()
	inst.free()
	return sections


## One row per FIGHTER / GATLING_INTERCEPTOR entry, in the same shape as `EXPECTED`. Formations are
## recorded as a class name + count, never expanded into per-slot rows, matching
## `test_level1_drone_spawns.gd`'s convention.
func _actual_fighter_spawns(sections: Array[LevelSection]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for section: LevelSection in sections:
		for wave: WaveResource in section.waves:
			for entry: SpawnEntryResource in wave.entries:
				var path: String = entry.ship_scene.resource_path if entry.ship_scene else ""
				if path != _FIGHTER and path != _GATLING:
					continue
				var formation_name: StringName = &"none"
				var formation_count: int = -1
				if entry.formation:
					var f: FormationResource = entry.formation
					formation_name = f.get_script().get_global_name()
					formation_count = f.count
				var free_after: float = entry.exit_time if entry.exit_mode == EnemyPathMover.ExitMode.FREE_ON_DURATION else 0.0
				out.append({
					"section": section.section_name,
					"kind": "FIGHTER" if path == _FIGHTER else "GATLING_INTERCEPTOR",
					"trigger": wave.trigger_time,
					"offset": entry.base_offset,
					"delay": entry.spawn_delay,
					"formation": formation_name,
					"formation_count": formation_count,
					"aim_mode": String(entry.initial_props.get("aim_mode", "")),
					"free_after": free_after,
					"movement": entry.movement != null,
				})
	return out


# ── The pin ───────────────────────────────────────────────────────────────────

func test_pinned_fighter_and_gatling_spawns_match_todays_data() -> void:
	var actual := _actual_fighter_spawns(_build_sections())
	assert_eq(actual.size(), EXPECTED.size(),
		"the number of FIGHTER/GATLING_INTERCEPTOR entries in _build_sections() has changed")
	assert_eq(actual, EXPECTED,
		"a fighter or interceptor spawn's section, trigger, offset, delay, formation, aim_mode, "
			+ "free_after or movement changed")


## 64 pinned rows (62 fighter + 2 interceptor), split by kind and section, cross-checked against
## themselves so a stale hand-edit of the roster text is caught independent of whether
## `_build_sections()` changed.
func test_the_pin_itself_is_internally_consistent() -> void:
	var fighter_rows := 0
	var interceptor_rows := 0
	var by_section: Dictionary = {}
	for row: Dictionary in EXPECTED:
		if row["kind"] == "FIGHTER":
			fighter_rows += 1
		else:
			interceptor_rows += 1
		var section: StringName = row["section"]
		by_section[section] = int(by_section.get(section, 0)) + 1
	assert_eq(fighter_rows + interceptor_rows, EXPECTED.size())
	assert_eq(interceptor_rows, 2, "level 1 has exactly one interceptor pair today")
	assert_eq(int(by_section.get(&"deep_space", 0)), 18, "deep_space row count changed")
	assert_eq(int(by_section.get(&"planet_approach", 0)), 19, "planet_approach row count changed")
	assert_eq(int(by_section.get(&"cloud_descent", 0)), 27, "cloud_descent row count changed")


## Boundary (the task's acceptance criterion): a fighter line's delay changed in memory must not
## match the pin. Done on a fresh `_build_sections()` result, so nothing shared is mutated.
func test_a_fighter_lines_delay_changed_fails_the_pin() -> void:
	var sections := _build_sections()
	var mutated := false
	for section: LevelSection in sections:
		for wave: WaveResource in section.waves:
			for entry: SpawnEntryResource in wave.entries:
				if not mutated and entry.ship_scene and entry.ship_scene.resource_path == _FIGHTER:
					entry.spawn_delay += 1.0
					mutated = true
	assert_true(mutated, "sanity: level 1 has a fighter line to mutate")
	assert_ne(_actual_fighter_spawns(sections), EXPECTED,
		"a fighter line with a changed delay must not match the pin")


# ── Legacy peak concurrency and shots/s (§2.9.1, review B6/N6) ─────────────────────────────────

## `FREE_ON_DURATION` → `exit_time`. Otherwise sample `movement` (a `PlayerFocusMovement` is
## duplicated with its `direction` aimed at the camera centre — see the class doc) from `offset`
## until it next leaves `enemy_cull_rect()` after having been inside it, capped at `_CULL_CAP`.
## `cam` is bound in by the caller (`DroneConcurrency.spawn_intervals()`'s `lifetime_fn` contract).
func _rail_lifetime(path: String, offset: Vector2, movement: MovementResource, exit_mode: int,
		exit_time: float, cam: ArenaCamera) -> float:
	if exit_mode == EnemyPathMover.ExitMode.FREE_ON_DURATION:
		return exit_time
	if movement == null:
		return 0.0
	var m := movement
	if m is PlayerFocusMovement:
		m = m.duplicate() as PlayerFocusMovement
		(m as PlayerFocusMovement).direction = (-offset).normalized()
	var rect := cam.enemy_cull_rect()
	var has_been_on_screen := false
	var t := 0.0
	while t <= _CULL_CAP:
		var world: Vector2 = (offset + m.sample(t)) * ArenaCamera.WORLD_SCALE
		var inside := rect.has_point(world)
		if not has_been_on_screen:
			if inside:
				has_been_on_screen = true
		else:
			if not inside:
				return t
		t += _CULL_STEP
	return _CULL_CAP


## Instantiates `path` as a child of `container` — two levels under a scene-tree node, matching
## `BulletPool._ready()`'s `pool -> ship -> container` resolution — so `_ready()` actually builds
## the pool and the `AttackController`. `aim_mode` is set first when non-empty, so it is read by
## `fighter.gd:32` before `_ready()` runs. Caller frees the returned ship.
func _spawn_in(container: Node2D, path: String, aim_mode: String) -> Node:
	var ship: Node = (load(path) as PackedScene).instantiate()
	if aim_mode != "":
		ship.set("aim_mode", aim_mode)
	container.add_child(ship)
	return ship


## A ship's own `BulletPool` and `AttackController.pattern`, found by type rather than by field
## name — `Fighter.bullet_pool` is public but `GatlingInterceptor._bullet_pool` is not, and this
## must read both the same way. Frees `ship`.
##
## Every AI ship (one with a `Brain`: the Fighter since t8a, the Gatling Interceptor since t10) is read
## the way it fires on a rail: `suspend_ai()` installs the rail pattern from its config. The Fighter's
## second pool / controller (`ForwardPool`, `ForwardAttack`, AI-only) are skipped.
##
## `max_distance` is read from the round the ship's own pool fires (t10 review A4), not a shared bullet
## scene: the Fighter fires Pulse and the Gatling Gatling Stream, both 1400 px against the legacy
## round's 2400. At the time of t10 every section's peak is unchanged by this (measured: the deep_space
## peak window holds no interceptor, and the fighters are capped by their interval, not their pool).
func _attack_stats_of(ship: Node) -> Dictionary:
	if ship is BaseEnemy and ship.get_node_or_null("Brain") != null:
		(ship as BaseEnemy).suspend_ai()
	var pool: BulletPool = null
	var pattern: AttackPatternResource = null
	for child in ship.get_children():
		if child.name == &"ForwardPool" or child.name == &"ForwardAttack":
			continue
		if child is BulletPool:
			pool = child as BulletPool
		elif child is AttackController:
			pattern = (child as AttackController).pattern
	assert_not_null(pool, "%s has no BulletPool child" % ship.name)
	assert_not_null(pattern, "%s has no AttackController.pattern" % ship.name)
	var stats: Dictionary = {
		"pool_size": pool.pool_size,
		"fire_interval": pattern.fire_interval,
		"bullet_speed": float(pattern.get("bullet_speed")),
		"max_distance": _round_max_distance(pool.bullet_scene),
	}
	ship.free()
	return stats


## The `ProjectileLifetime.max_distance` of the round `bullet_scene` fires.
func _round_max_distance(bullet_scene: PackedScene) -> float:
	var bullet: Node = bullet_scene.instantiate()
	var max_distance: float = (bullet.get_node("ProjectileLifetime") as ProjectileLifetime).max_distance
	bullet.free()
	return max_distance


## Review round 1 finding 2: pool sizes, fire intervals and bullet speeds read live by
## instantiating the real ships, never hand-typed. Computed once and memoized for the file's run —
## the same one-time-setup shape `before_all()` uses elsewhere in this suite (tests/README.md);
## kept lazy here because only two of this file's tests need it.
var _live_cache: Dictionary = {}

func _live_attack_stats() -> Dictionary:
	if not _live_cache.is_empty():
		return _live_cache
	var outer := Node2D.new()
	add_child_autofree(outer)
	var container := Node2D.new()
	outer.add_child(container)

	var forward := _attack_stats_of(_spawn_in(container, _FIGHTER, "FORWARD"))
	var aimed := _attack_stats_of(_spawn_in(container, _FIGHTER, "PLAYER"))
	var interceptor := _attack_stats_of(_spawn_in(container, _GATLING, ""))

	_live_cache = {
		"fighter_max_distance": float(forward["max_distance"]),
		"fighter_pool_size": int(forward["pool_size"]),
		"fighter_forward_interval": float(forward["fire_interval"]),
		"fighter_forward_speed": float(forward["bullet_speed"]),
		"fighter_aimed_interval": float(aimed["fire_interval"]),
		"fighter_aimed_speed": float(aimed["bullet_speed"]),
		"interceptor_max_distance": float(interceptor["max_distance"]),
		"interceptor_pool_size": int(interceptor["pool_size"]),
		"interceptor_interval": float(interceptor["fire_interval"]),
		"interceptor_speed": float(interceptor["bullet_speed"]),
	}
	return _live_cache


## Review round 1 finding 3: `min(flat fire rate, pool_size / round_lifetime)`, where
## `round_lifetime` is `max_distance / bullet_speed` — the plan's own pool-sizing formula
## throughout §2.2 ("lifetime = max_distance / speed") — never `projectile_world_rect()`'s
## diagonal, which no shot's own expiry rule (`ProjectileLifetime`) actually consults.
func _capped_rate(flat: float, bullet_speed: float, pool_size: int, max_distance: float) -> float:
	var round_lifetime: float = max_distance / bullet_speed
	return minf(flat, float(pool_size) / round_lifetime)


func _rate_for(path: String, _offset: Vector2, _movement: MovementResource, _exit_mode: int,
		_exit_time: float, aim_mode: String) -> float:
	var live := _live_attack_stats()
	if path == _GATLING:
		return _capped_rate(1.0 / live["interceptor_interval"], live["interceptor_speed"],
			live["interceptor_pool_size"], live["interceptor_max_distance"])
	if aim_mode == "FORWARD":
		return _capped_rate(1.0 / live["fighter_forward_interval"], live["fighter_forward_speed"],
			live["fighter_pool_size"], live["fighter_max_distance"])
	return _capped_rate(1.0 / live["fighter_aimed_interval"], live["fighter_aimed_speed"],
		live["fighter_pool_size"], live["fighter_max_distance"])


## The sections whose rails still exist, so their frozen constants can still be recomputed from live
## data. t16 retired deep_space and planet_approach from this check: their `.move()` / `.free_after()`
## / `shoot_*()` are gone, so there is nothing left to recompute the constants FROM — the constants
## stay frozen above and the t16 density gates keep dividing by them (review B6). t17 retired cloud_descent
## the same way, so this is empty; the check re-arms by itself if a section is ever put back on rails.
const _RAIL_SECTIONS: Array[StringName] = []


func test_legacy_peak_fighters_and_shots_per_s_match_frozen_constants() -> void:
	var cam := ArenaCamera.new()
	add_child_autofree(cam)
	var ship_paths: Array[String] = [_FIGHTER, _GATLING]
	var lifetime_fn := Callable(self, "_rail_lifetime").bind(cam)
	var rate_fn := Callable(self, "_rate_for")

	var checked := 0
	for section: LevelSection in _build_sections():
		if not _RAIL_SECTIONS.has(section.section_name):
			continue
		checked += 1
		var intervals := DroneConcurrency.spawn_intervals(section, ship_paths, lifetime_fn, rate_fn)
		var peak_count := DroneConcurrency.peak_interval_count(intervals)
		var peak_rate := DroneConcurrency.peak_interval_rate(intervals)
		assert_eq(peak_count, int(_LEGACY_PEAK_FIGHTERS[section.section_name]),
			"%s: legacy peak concurrent fighters/interceptors changed" % section.section_name)
		assert_almost_eq(peak_rate, float(_LEGACY_PEAK_SHOTS_PER_S[section.section_name]), 0.01,
			"%s: legacy peak shots/s changed" % section.section_name)
	assert_eq(checked, _RAIL_SECTIONS.size(), "sanity: every section still on rails was checked")
	# Never vacuous: with no section on rails, every frozen constant must still be divided by a gate.
	for frozen: Dictionary in [_LEGACY_PEAK_FIGHTERS, _LEGACY_PEAK_SHOTS_PER_S]:
		for key: StringName in frozen:
			assert_true(_RAIL_SECTIONS.has(key) or MIGRATED_SECTIONS.has(key),
				"frozen constant for %s is neither live-checked nor gated" % key)


## Boundary for the shared helper: an empty section computes a peak of 0, never an error or a
## stale value from a previous section.
func test_a_section_with_no_fighters_has_zero_peak_concurrency_and_rate() -> void:
	var cam := ArenaCamera.new()
	add_child_autofree(cam)
	var ship_paths: Array[String] = [_FIGHTER, _GATLING]
	var lifetime_fn := Callable(self, "_rail_lifetime").bind(cam)
	var rate_fn := Callable(self, "_rate_for")
	for section: LevelSection in _build_sections():
		if section.section_name != &"asteroid_belt":
			continue
		var intervals := DroneConcurrency.spawn_intervals(section, ship_paths, lifetime_fn, rate_fn)
		assert_eq(intervals.size(), 0, "asteroid_belt spawns no fighters or interceptors")
		assert_eq(DroneConcurrency.peak_interval_count(intervals), 0)
		assert_eq(DroneConcurrency.peak_interval_rate(intervals), 0.0)


# ── t16: deep_space and planet_approach off rails (docs/plans/cmulwkarm00cpqj2xfwq3ue8h/3-plan.md) ──

## The sections t16 (deep_space, planet_approach) and t17 (cloud_descent) migrated. Their shots/s gate is measured, not computed — see
## `test_level1_fighter_fire_density.gd` (owner option A).
const MIGRATED_SECTIONS: Array[StringName] = [&"deep_space", &"planet_approach", &"cloud_descent"]

## Ratios of epic §2.9.2, against the FROZEN `_LEGACY_PEAK_FIGHTERS` (never recomputed — the rails it
## was computed from are gone). Shots/s's 1.25 lives in the measured gate's file.
const _ALL_ALIVE_RATIO := 2.0
const _CAPABLE_RATIO := 1.5

const _FIGHTER_CONFIG: FighterConfig = preload("res://assault/scenes/enemies/fighter/fighter_config.tres")
const _GATLING_CONFIG: GatlingInterceptorConfig = \
	preload("res://assault/scenes/enemies/gatling_interceptor/gatling_interceptor_config.tres")


func test_migrated_sections_have_no_rail_left() -> void:
	var checked := 0
	for section: LevelSection in _build_sections():
		if not MIGRATED_SECTIONS.has(section.section_name):
			continue
		for wave: WaveResource in section.waves:
			for entry: SpawnEntryResource in wave.entries:
				var path: String = entry.ship_scene.resource_path if entry.ship_scene else ""
				if path != _FIGHTER and path != _GATLING:
					continue
				checked += 1
				var where := "%s @ %.1f s, offset %s" % [section.section_name, wave.trigger_time, entry.base_offset]
				assert_null(entry.movement, "%s still has a rail (.move())" % where)
				assert_ne(entry.exit_mode, EnemyPathMover.ExitMode.FREE_ON_DURATION,
					"%s still has .free_after()" % where)
				assert_false(entry.initial_props.has("aim_mode"), "%s still has a shoot_*() aim_mode" % where)
	assert_eq(checked, 64, "sanity: the 18 + 19 + 27 migrated fighter/Gatling lines were all checked")


## Loose lines of one kind that share a wave fight as one squad, tagged `w<wave index>f` (fighters) or
## `w<wave index>g` (Gatlings) — the Ph2 convention. A lone loose line stays untagged: `WaveManager`
## keys it as a squad of one either way.
func test_loose_pairs_are_tagged_with_their_wave_index() -> void:
	var tagged := 0
	for section: LevelSection in _build_sections():
		if not MIGRATED_SECTIONS.has(section.section_name):
			continue
		for wave_index in section.waves.size():
			var wave: WaveResource = section.waves[wave_index]
			for path: String in [_FIGHTER, _GATLING]:
				var loose: Array[SpawnEntryResource] = []
				for entry: SpawnEntryResource in wave.entries:
					if entry.ship_scene and entry.ship_scene.resource_path == path and entry.formation == null:
						loose.append(entry)
				if loose.size() < 2:
					continue
				var expected := "w%d%s" % [wave_index, "g" if path == _GATLING else "f"]
				for entry: SpawnEntryResource in loose:
					tagged += 1
					assert_eq(String(entry.squad_id), expected, "%s wave %d (%.1f s): loose %s line's squad tag"
						% [section.section_name, wave_index, wave.trigger_time, path.get_file()])
	assert_eq(tagged, 43,
		"sanity: 18 loose lines across deep_space / planet_approach + 25 in cloud_descent's 8 fighter squads")


## Boundary: a migrated fighter line given a rail again must not match the pin.
func test_a_fighter_line_given_move_again_fails_the_pin() -> void:
	var sections := _build_sections()
	var mutated := false
	for section: LevelSection in sections:
		if section.section_name != &"deep_space":
			continue
		for wave: WaveResource in section.waves:
			for entry: SpawnEntryResource in wave.entries:
				if not mutated and entry.ship_scene and entry.ship_scene.resource_path == _FIGHTER:
					entry.movement = StraightMovement.new()
					mutated = true
	assert_true(mutated, "sanity: deep_space has a fighter line to mutate")
	assert_ne(_actual_fighter_spawns(sections), EXPECTED,
		"a deep_space fighter line with .move() put back must not match the pin")


## Half the shorter side of the live `projectile_world_rect()` — the farthest a ship can be from
## its nearest exit edge (the same `exit_distance` `test_engagement_deadline.gd` uses).
func _exit_distance() -> float:
	var cam := ArenaCamera.new()
	add_child_autofree(cam)
	var rect := cam.projectile_world_rect()
	return minf(rect.size.x, rect.size.y) / 2.0


## Each AI kind's lifetime, attackers per squad and analytic rate, from the shipped configs — see
## `DroneConcurrency.ai_shooter_kinds()`.
func _ai_kinds() -> Dictionary:
	return DroneConcurrency.ai_shooter_kinds(_FIGHTER_CONFIG, _GATLING_CONFIG, _exit_distance())


## The all-alive and attack-capable gates for one section's intervals, with every figure printed.
func _assert_count_gates(name: StringName, intervals: Array[Dictionary]) -> void:
	var legacy := int(_LEGACY_PEAK_FIGHTERS[name])
	var all_alive := DroneConcurrency.peak_intervals(intervals)
	var capable := DroneConcurrency.peak_intervals(intervals, true)
	gut.p("%s: all-alive peak %d (limit %.1f = %.1f x frozen %d); attack-capable peak %d (limit %.1f), "
		% [name, all_alive, _ALL_ALIVE_RATIO * legacy, _ALL_ALIVE_RATIO, legacy, capable, _CAPABLE_RATIO * legacy]
		+ "min(alive, cap) model %d; analytic shots/s %.2f (printed only, frozen %.2f)"
		% [DroneConcurrency.peak_min_alive_cap(intervals), DroneConcurrency.peak_interval_rate(intervals),
			float(_LEGACY_PEAK_SHOTS_PER_S[name])])
	assert_lte(float(all_alive), _ALL_ALIVE_RATIO * legacy, "%s: all-alive peak over %.1fx legacy" % [name, _ALL_ALIVE_RATIO])
	assert_lte(float(capable), _CAPABLE_RATIO * legacy, "%s: attack-capable peak over %.1fx legacy" % [name, _CAPABLE_RATIO])


func test_migrated_sections_all_alive_and_attack_capable_peaks_within_their_ratios() -> void:
	var kinds := _ai_kinds()
	gut.p("AI lifetimes: fighter %.2f s, Gatling %.2f s" % [kinds[_FIGHTER]["life"], kinds[_GATLING]["life"]])
	var checked := 0
	for section: LevelSection in _build_sections():
		if not MIGRATED_SECTIONS.has(section.section_name):
			continue
		checked += 1
		_assert_count_gates(section.section_name, DroneConcurrency.shooter_squad_intervals(section, kinds))
	assert_eq(checked, MIGRATED_SECTIONS.size(), "sanity: every migrated section was checked")


## Boundary: the count gates can reject. One extra V of 3 fighters at planet_approach's own
## attack-capable peak moment pushes that peak past 1.5x the frozen constant; two more Vs of 5 push
## the all-alive peak past 2.0x. Computed through the same `shooter_squad_intervals()` the gate uses,
## on a fresh `_build_sections()`, so nothing shared is mutated.
func test_extra_formations_at_the_peak_break_the_count_gates() -> void:
	var kinds := _ai_kinds()
	var section: LevelSection = null
	for s: LevelSection in _build_sections():
		if s.section_name == &"planet_approach":
			section = s
	assert_not_null(section, "sanity: level 1 has planet_approach")
	if section == null:
		return
	var legacy := int(_LEGACY_PEAK_FIGHTERS[&"planet_approach"])
	var before := DroneConcurrency.shooter_squad_intervals(section, kinds)
	var t_peak := DroneConcurrency.capable_peak_time(before)
	var capable_before := DroneConcurrency.peak_intervals(before, true)
	var all_before := DroneConcurrency.peak_intervals(before)

	var b := WaveBuilder.new()
	section.waves.append(b.wave(t_peak, [b.fighter().formation(b.v_formation(3, 40.0, 12.0, 0.0)).at(0, -400)]))
	var with_v3 := DroneConcurrency.shooter_squad_intervals(section, kinds)
	var capable_after := DroneConcurrency.peak_intervals(with_v3, true)
	gut.p("planet_approach + V3 at %.2f s: attack-capable %d -> %d (limit %.1f)"
		% [t_peak, capable_before, capable_after, _CAPABLE_RATIO * legacy])
	assert_eq(capable_after, capable_before + 3, "a V of 3 at the capable peak adds exactly its 3 attackers")
	assert_gt(float(capable_after), _CAPABLE_RATIO * legacy, "the attack-capable gate must reject this")

	section.waves.append(b.wave(t_peak, [
		b.fighter().formation(b.v_formation(5, 40.0, 12.0, 0.0)).at(-200, -400),
		b.fighter().formation(b.v_formation(5, 40.0, 12.0, 0.0)).at(200, -400),
	]))
	var all_after := DroneConcurrency.peak_intervals(DroneConcurrency.shooter_squad_intervals(section, kinds))
	gut.p("planet_approach + V3 + 2 x V5 at %.2f s: all-alive %d -> %d (limit %.1f)"
		% [t_peak, all_before, all_after, _ALL_ALIVE_RATIO * legacy])
	assert_gt(float(all_after), _ALL_ALIVE_RATIO * legacy, "the all-alive gate must reject this")
