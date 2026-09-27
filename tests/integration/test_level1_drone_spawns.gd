## Characterization: pins every Kamikaze Drone and Razor Drone spawn in Level 1, the space
## station's BOTTOM reinforcement squad, and Open Space's ambient PatrolDrone spawn — the state of
## the world BEFORE Enemy rework phase 2 touches any of it
## (docs/plans/cmufs7ek60001nm2x6d0bt2et/3-plan.md §3 step 1). t14/t15/t16 replace the enemies these
## pins describe; this file exists so those tasks start from a known-true baseline instead of
## trusting memory of what the level "used to do".
##
## NOT an invariant — the opposite of `test_enemy_contact_damage.gd`'s "config drift is a bug".
## Every number here is a deliberate design choice this file freezes, not a rule it derives. A
## failure means "the drone spawns changed", which is expected and desired starting at t14 — at
## that point this file (and `test_level1_drone_exit.gd`, t15) gets rewritten, not "fixed".
##
## ── Why `_build_sections()`, not the level scene ─────────────────────────────────────────────
##
## `Level1Director._build_sections()` is split out of `_ready()` specifically so it can be called
## on a bare, never-entered-tree instance (`level_1_director.gd:198-200`): every builder touches
## only `LevelSection.new()`, `preload()` and `WaveBuilder` (a `RefCounted`). That lets this file
## read the wave data directly, in the same units and same code path `WaveManager` consumes,
## instead of re-deriving it by reading the script's text — a scene that could drift from a
## refactor no text-scan would notice.
##
## ── The peak-concurrency numbers ─────────────────────────────────────────────────────────────
##
## `DroneConcurrency` (`tests/helpers/level1_drone_concurrency.gd`) computes, for every DRONE /
## RAZOR_DRONE spawn moment in a section (formations expanded through
## `FormationResource.compute_slots()`, exactly as `WaveManager._expand_formation()` does), the
## largest number simultaneously alive under a fixed lifetime window. At today's legacy lifetime
## (each drone dies in a single ramming pass, well under the plan's assumed 3.5 s), the computed
## peaks are 14 / 6 / 5 — the plan's §5 numbers, verified here rather than merely quoted.
extends GutTest

const _DIRECTOR_SCRIPT := "res://assault/scenes/levels/edelia/1/level_1_director.gd"
const _STATION_SCENE: PackedScene = preload("res://assault/scenes/enemies/space_station/space_station.tscn")
const _HUB_SCENE: PackedScene = preload("res://open_space/scenes/levels/sector_hub.tscn")
const _HUB_SCRIPT := "res://open_space/scenes/levels/sector_hub.gd"

const DroneConcurrency := preload("res://tests/helpers/level1_drone_concurrency.gd")

const _DRONE := WaveBuilder.DRONE
const _RAZOR_DRONE := WaveBuilder.RAZOR_DRONE

## Legacy lifetime: every drone in the shipped level dies (or is culled) within one ramming pass,
## which is over well inside 3.5 s — the plan's §5 assumption, pinned as a computed value below
## rather than merely asserted.
const _LEGACY_LIFETIME: float = 3.5

## Every DRONE / RAZOR_DRONE entry in `_build_sections()`, in encounter order, as pinned by
## hand from the live data on 2026-09-27 (`git log` / this task's HEAD). `formation`/`formation_count`
## are `&"none"`/`-1` for an unformationed entry. Regenerate by walking `_build_sections()` the same
## way `_actual_drone_spawns()` below does — never hand-edit a single row without re-deriving the
## whole table, or a typo would pass by accident.
const EXPECTED: Array[Dictionary] = [
	{"section": &"deep_space", "kind": "DRONE", "trigger": 1.00, "offset": Vector2(-260.0, -400.0), "delay": 0.00, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"deep_space", "kind": "DRONE", "trigger": 1.00, "offset": Vector2(260.0, -400.0), "delay": 0.20, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"deep_space", "kind": "RAZOR_DRONE", "trigger": 1.50, "offset": Vector2(-160.0, -420.0), "delay": 0.00, "formation": &"none", "formation_count": -1, "movement": false},
	{"section": &"deep_space", "kind": "RAZOR_DRONE", "trigger": 1.50, "offset": Vector2(160.0, -420.0), "delay": 0.35, "formation": &"none", "formation_count": -1, "movement": false},
	{"section": &"deep_space", "kind": "DRONE", "trigger": 2.00, "offset": Vector2(-220.0, -400.0), "delay": 0.10, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"deep_space", "kind": "DRONE", "trigger": 2.00, "offset": Vector2(220.0, -400.0), "delay": 0.10, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"deep_space", "kind": "DRONE", "trigger": 3.00, "offset": Vector2(120.0, -400.0), "delay": 0.00, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"deep_space", "kind": "DRONE", "trigger": 3.00, "offset": Vector2(180.0, -400.0), "delay": 0.25, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"deep_space", "kind": "DRONE", "trigger": 3.00, "offset": Vector2(240.0, -400.0), "delay": 0.50, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"deep_space", "kind": "DRONE", "trigger": 4.00, "offset": Vector2(-220.0, -400.0), "delay": 0.00, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"deep_space", "kind": "DRONE", "trigger": 4.00, "offset": Vector2(220.0, -400.0), "delay": 0.30, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"deep_space", "kind": "DRONE", "trigger": 4.00, "offset": Vector2(0.0, -400.0), "delay": 0.40, "formation": &"ClusterFormation", "formation_count": 3, "movement": true},
	{"section": &"deep_space", "kind": "DRONE", "trigger": 8.00, "offset": Vector2(-140.0, -400.0), "delay": 0.50, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"deep_space", "kind": "DRONE", "trigger": 8.00, "offset": Vector2(140.0, -400.0), "delay": 0.70, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"deep_space", "kind": "DRONE", "trigger": 9.50, "offset": Vector2(-100.0, -400.0), "delay": 0.00, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"deep_space", "kind": "DRONE", "trigger": 9.50, "offset": Vector2(0.0, -400.0), "delay": 0.20, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"deep_space", "kind": "DRONE", "trigger": 9.50, "offset": Vector2(100.0, -400.0), "delay": 0.40, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"deep_space", "kind": "DRONE", "trigger": 11.00, "offset": Vector2(0.0, -400.0), "delay": 0.50, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"deep_space", "kind": "DRONE", "trigger": 12.50, "offset": Vector2(0.0, -400.0), "delay": 0.00, "formation": &"WedgeFormation", "formation_count": 3, "movement": true},
	{"section": &"deep_space", "kind": "DRONE", "trigger": 14.00, "offset": Vector2(200.0, -400.0), "delay": 0.50, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"deep_space", "kind": "DRONE", "trigger": 14.00, "offset": Vector2(-200.0, -400.0), "delay": 0.50, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"deep_space", "kind": "DRONE", "trigger": 16.00, "offset": Vector2(0.0, -400.0), "delay": 0.00, "formation": &"LineFormation", "formation_count": 4, "movement": true},
	{"section": &"deep_space", "kind": "DRONE", "trigger": 17.00, "offset": Vector2(0.0, -400.0), "delay": 0.00, "formation": &"ClusterFormation", "formation_count": 4, "movement": true},
	{"section": &"deep_space", "kind": "DRONE", "trigger": 20.00, "offset": Vector2(0.0, -400.0), "delay": 0.30, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"deep_space", "kind": "DRONE", "trigger": 21.00, "offset": Vector2(-110.0, -400.0), "delay": 0.00, "formation": &"ClusterFormation", "formation_count": 3, "movement": true},
	{"section": &"deep_space", "kind": "DRONE", "trigger": 22.00, "offset": Vector2(-60.0, -400.0), "delay": 0.00, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"deep_space", "kind": "DRONE", "trigger": 22.00, "offset": Vector2(0.0, -400.0), "delay": 0.00, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"deep_space", "kind": "DRONE", "trigger": 22.00, "offset": Vector2(60.0, -400.0), "delay": 0.00, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"deep_space", "kind": "DRONE", "trigger": 22.00, "offset": Vector2(30.0, -400.0), "delay": 0.20, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"deep_space", "kind": "DRONE", "trigger": 22.00, "offset": Vector2(-120.0, -400.0), "delay": 0.35, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"deep_space", "kind": "DRONE", "trigger": 22.00, "offset": Vector2(120.0, -400.0), "delay": 0.35, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"deep_space", "kind": "DRONE", "trigger": 23.00, "offset": Vector2(-180.0, -400.0), "delay": 0.00, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"deep_space", "kind": "DRONE", "trigger": 23.00, "offset": Vector2(180.0, -400.0), "delay": 0.15, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"deep_space", "kind": "DRONE", "trigger": 26.00, "offset": Vector2(0.0, -400.0), "delay": 0.30, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"deep_space", "kind": "DRONE", "trigger": 27.00, "offset": Vector2(-100.0, -400.0), "delay": 0.00, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"deep_space", "kind": "DRONE", "trigger": 27.00, "offset": Vector2(0.0, -400.0), "delay": 0.15, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"deep_space", "kind": "DRONE", "trigger": 27.00, "offset": Vector2(100.0, -400.0), "delay": 0.30, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"deep_space", "kind": "DRONE", "trigger": 28.00, "offset": Vector2(-200.0, -400.0), "delay": 0.00, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"deep_space", "kind": "DRONE", "trigger": 28.00, "offset": Vector2(-100.0, -400.0), "delay": 0.10, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"deep_space", "kind": "DRONE", "trigger": 28.00, "offset": Vector2(-50.0, -400.0), "delay": 0.15, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"deep_space", "kind": "DRONE", "trigger": 28.00, "offset": Vector2(0.0, -400.0), "delay": 0.25, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"deep_space", "kind": "DRONE", "trigger": 28.00, "offset": Vector2(50.0, -400.0), "delay": 0.30, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"deep_space", "kind": "DRONE", "trigger": 28.00, "offset": Vector2(100.0, -400.0), "delay": 0.35, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"deep_space", "kind": "DRONE", "trigger": 28.00, "offset": Vector2(200.0, -400.0), "delay": 0.45, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"planet_approach", "kind": "DRONE", "trigger": 2.00, "offset": Vector2(-180.0, -400.0), "delay": 0.00, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"planet_approach", "kind": "DRONE", "trigger": 2.00, "offset": Vector2(180.0, -400.0), "delay": 0.20, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"planet_approach", "kind": "DRONE", "trigger": 5.00, "offset": Vector2(160.0, -400.0), "delay": 0.40, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"planet_approach", "kind": "DRONE", "trigger": 8.00, "offset": Vector2(0.0, -400.0), "delay": 0.00, "formation": &"ClusterFormation", "formation_count": 3, "movement": true},
	{"section": &"planet_approach", "kind": "DRONE", "trigger": 13.00, "offset": Vector2(-60.0, -400.0), "delay": 0.00, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"planet_approach", "kind": "DRONE", "trigger": 13.00, "offset": Vector2(60.0, -400.0), "delay": 0.25, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"planet_approach", "kind": "DRONE", "trigger": 16.00, "offset": Vector2(-80.0, -400.0), "delay": 0.40, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"planet_approach", "kind": "DRONE", "trigger": 16.00, "offset": Vector2(0.0, -400.0), "delay": 0.50, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"planet_approach", "kind": "DRONE", "trigger": 16.00, "offset": Vector2(80.0, -400.0), "delay": 0.60, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"planet_approach", "kind": "DRONE", "trigger": 24.00, "offset": Vector2(0.0, -400.0), "delay": 0.00, "formation": &"WedgeFormation", "formation_count": 4, "movement": true},
	{"section": &"planet_approach", "kind": "DRONE", "trigger": 32.00, "offset": Vector2(120.0, -400.0), "delay": 0.30, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"planet_approach", "kind": "DRONE", "trigger": 35.00, "offset": Vector2(-95.0, -400.0), "delay": 0.00, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"planet_approach", "kind": "DRONE", "trigger": 35.00, "offset": Vector2(-36.0, -400.0), "delay": 0.30, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"planet_approach", "kind": "DRONE", "trigger": 35.00, "offset": Vector2(24.0, -400.0), "delay": 0.60, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"planet_approach", "kind": "DRONE", "trigger": 35.00, "offset": Vector2(84.0, -400.0), "delay": 0.90, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"planet_approach", "kind": "DRONE", "trigger": 35.00, "offset": Vector2(180.0, -400.0), "delay": 0.40, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"planet_approach", "kind": "DRONE", "trigger": 35.00, "offset": Vector2(240.0, -400.0), "delay": 0.70, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"planet_approach", "kind": "DRONE", "trigger": 42.00, "offset": Vector2(140.0, -400.0), "delay": 0.00, "formation": &"ClusterFormation", "formation_count": 3, "movement": true},
	{"section": &"planet_approach", "kind": "DRONE", "trigger": 44.00, "offset": Vector2(0.0, -400.0), "delay": 0.60, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"planet_approach", "kind": "DRONE", "trigger": 44.00, "offset": Vector2(-80.0, -400.0), "delay": 0.80, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"planet_approach", "kind": "DRONE", "trigger": 44.00, "offset": Vector2(80.0, -400.0), "delay": 0.80, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"planet_approach", "kind": "DRONE", "trigger": 50.00, "offset": Vector2(-200.0, -400.0), "delay": 0.30, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"planet_approach", "kind": "DRONE", "trigger": 50.00, "offset": Vector2(200.0, -400.0), "delay": 0.30, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"planet_approach", "kind": "DRONE", "trigger": 53.00, "offset": Vector2(0.0, -400.0), "delay": 0.00, "formation": &"WedgeFormation", "formation_count": 3, "movement": true},
	{"section": &"planet_approach", "kind": "DRONE", "trigger": 58.00, "offset": Vector2(-72.0, -400.0), "delay": 0.40, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"planet_approach", "kind": "DRONE", "trigger": 58.00, "offset": Vector2(72.0, -400.0), "delay": 0.40, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"planet_approach", "kind": "DRONE", "trigger": 62.00, "offset": Vector2(-150.0, -400.0), "delay": 0.00, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"planet_approach", "kind": "DRONE", "trigger": 62.00, "offset": Vector2(150.0, -400.0), "delay": 0.30, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"planet_approach", "kind": "DRONE", "trigger": 68.00, "offset": Vector2(-220.0, -400.0), "delay": 0.00, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"planet_approach", "kind": "DRONE", "trigger": 68.00, "offset": Vector2(-110.0, -400.0), "delay": 0.15, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"planet_approach", "kind": "DRONE", "trigger": 68.00, "offset": Vector2(0.0, -400.0), "delay": 0.30, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"planet_approach", "kind": "DRONE", "trigger": 68.00, "offset": Vector2(110.0, -400.0), "delay": 0.45, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"planet_approach", "kind": "DRONE", "trigger": 68.00, "offset": Vector2(220.0, -400.0), "delay": 0.60, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"planet_approach", "kind": "DRONE", "trigger": 75.00, "offset": Vector2(0.0, -400.0), "delay": 0.00, "formation": &"ClusterFormation", "formation_count": 4, "movement": true},
	{"section": &"planet_approach", "kind": "DRONE", "trigger": 84.00, "offset": Vector2(0.0, -400.0), "delay": 0.00, "formation": &"WedgeFormation", "formation_count": 5, "movement": true},
	{"section": &"planet_approach", "kind": "DRONE", "trigger": 95.00, "offset": Vector2(95.0, -400.0), "delay": 0.00, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"planet_approach", "kind": "DRONE", "trigger": 95.00, "offset": Vector2(36.0, -400.0), "delay": 0.30, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"planet_approach", "kind": "DRONE", "trigger": 95.00, "offset": Vector2(-24.0, -400.0), "delay": 0.60, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"planet_approach", "kind": "DRONE", "trigger": 95.00, "offset": Vector2(-84.0, -400.0), "delay": 0.90, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"planet_approach", "kind": "DRONE", "trigger": 95.00, "offset": Vector2(-150.0, -400.0), "delay": 1.10, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"planet_approach", "kind": "DRONE", "trigger": 95.00, "offset": Vector2(150.0, -400.0), "delay": 1.10, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"planet_approach", "kind": "DRONE", "trigger": 106.00, "offset": Vector2(-220.0, -400.0), "delay": 0.00, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"planet_approach", "kind": "DRONE", "trigger": 106.00, "offset": Vector2(-110.0, -400.0), "delay": 0.15, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"planet_approach", "kind": "DRONE", "trigger": 106.00, "offset": Vector2(0.0, -400.0), "delay": 0.30, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"planet_approach", "kind": "DRONE", "trigger": 106.00, "offset": Vector2(110.0, -400.0), "delay": 0.45, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"planet_approach", "kind": "DRONE", "trigger": 106.00, "offset": Vector2(220.0, -400.0), "delay": 0.60, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"cloud_descent", "kind": "DRONE", "trigger": 2.00, "offset": Vector2(-130.0, -400.0), "delay": 0.00, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"cloud_descent", "kind": "DRONE", "trigger": 2.00, "offset": Vector2(130.0, -400.0), "delay": 0.30, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"cloud_descent", "kind": "DRONE", "trigger": 5.00, "offset": Vector2(-500.0, 150.0), "delay": 0.90, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"cloud_descent", "kind": "DRONE", "trigger": 9.00, "offset": Vector2(0.0, -400.0), "delay": 0.00, "formation": &"WedgeFormation", "formation_count": 3, "movement": true},
	{"section": &"cloud_descent", "kind": "DRONE", "trigger": 14.00, "offset": Vector2(500.0, 150.0), "delay": 0.90, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"cloud_descent", "kind": "DRONE", "trigger": 18.00, "offset": Vector2(0.0, -400.0), "delay": 0.00, "formation": &"ClusterFormation", "formation_count": 4, "movement": true},
	{"section": &"cloud_descent", "kind": "DRONE", "trigger": 22.00, "offset": Vector2(-150.0, 400.0), "delay": 0.00, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"cloud_descent", "kind": "DRONE", "trigger": 22.00, "offset": Vector2(-75.0, 400.0), "delay": 0.20, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"cloud_descent", "kind": "DRONE", "trigger": 22.00, "offset": Vector2(0.0, 400.0), "delay": 0.40, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"cloud_descent", "kind": "DRONE", "trigger": 22.00, "offset": Vector2(75.0, 400.0), "delay": 0.60, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"cloud_descent", "kind": "DRONE", "trigger": 22.00, "offset": Vector2(150.0, 400.0), "delay": 0.80, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"cloud_descent", "kind": "DRONE", "trigger": 32.00, "offset": Vector2(0.0, -400.0), "delay": 0.50, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"cloud_descent", "kind": "DRONE", "trigger": 36.00, "offset": Vector2(0.0, -400.0), "delay": 0.00, "formation": &"WedgeFormation", "formation_count": 4, "movement": true},
	{"section": &"cloud_descent", "kind": "DRONE", "trigger": 46.00, "offset": Vector2(-100.0, 400.0), "delay": 0.00, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"cloud_descent", "kind": "DRONE", "trigger": 46.00, "offset": Vector2(0.0, 400.0), "delay": 0.20, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"cloud_descent", "kind": "DRONE", "trigger": 46.00, "offset": Vector2(100.0, 400.0), "delay": 0.40, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"cloud_descent", "kind": "DRONE", "trigger": 56.00, "offset": Vector2(-130.0, 400.0), "delay": 0.00, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"cloud_descent", "kind": "DRONE", "trigger": 56.00, "offset": Vector2(-65.0, 400.0), "delay": 0.20, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"cloud_descent", "kind": "DRONE", "trigger": 56.00, "offset": Vector2(0.0, 400.0), "delay": 0.40, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"cloud_descent", "kind": "DRONE", "trigger": 56.00, "offset": Vector2(65.0, 400.0), "delay": 0.60, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"cloud_descent", "kind": "DRONE", "trigger": 56.00, "offset": Vector2(130.0, 400.0), "delay": 0.80, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"cloud_descent", "kind": "DRONE", "trigger": 62.00, "offset": Vector2(0.0, -400.0), "delay": 0.50, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"cloud_descent", "kind": "DRONE", "trigger": 62.00, "offset": Vector2(-150.0, -400.0), "delay": 0.70, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"cloud_descent", "kind": "DRONE", "trigger": 62.00, "offset": Vector2(150.0, -400.0), "delay": 0.70, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"cloud_descent", "kind": "DRONE", "trigger": 68.00, "offset": Vector2(-100.0, 400.0), "delay": 0.00, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"cloud_descent", "kind": "DRONE", "trigger": 68.00, "offset": Vector2(100.0, 400.0), "delay": 0.30, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"cloud_descent", "kind": "DRONE", "trigger": 76.00, "offset": Vector2(-180.0, -400.0), "delay": 0.00, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"cloud_descent", "kind": "DRONE", "trigger": 76.00, "offset": Vector2(-90.0, -400.0), "delay": 0.20, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"cloud_descent", "kind": "DRONE", "trigger": 76.00, "offset": Vector2(0.0, -400.0), "delay": 0.40, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"cloud_descent", "kind": "DRONE", "trigger": 76.00, "offset": Vector2(90.0, -400.0), "delay": 0.60, "formation": &"none", "formation_count": -1, "movement": true},
	{"section": &"cloud_descent", "kind": "DRONE", "trigger": 76.00, "offset": Vector2(180.0, -400.0), "delay": 0.80, "formation": &"none", "formation_count": -1, "movement": true},
]

## Legacy per-section peaks at `_LEGACY_LIFETIME`, from plan §5's precomputed table — asserted as
## computed values below, not merely quoted.
const _EXPECTED_LEGACY_PEAKS: Dictionary = {
	&"deep_space": 14,
	&"planet_approach": 6,
	&"cloud_descent": 5,
}


## Callable on a bare, never-entered-tree instance — see the file header.
func _build_sections() -> Array[LevelSection]:
	var script := load(_DIRECTOR_SCRIPT)
	var inst: Node = script.new()
	var sections: Array[LevelSection] = inst._build_sections()
	inst.free()
	return sections


## Walks every wave of every section and records one row per DRONE / RAZOR_DRONE entry, in
## the same shape as `EXPECTED`. Formations are recorded as a class name + count, never expanded
## into per-slot rows — `EXPECTED` pins entries (what `WaveBuilder` authors), not spawned ships
## (what `WaveManager` produces); `DroneConcurrency.spawn_times()` is what expands them.
func _actual_drone_spawns(sections: Array[LevelSection]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for section: LevelSection in sections:
		for wave: WaveResource in section.waves:
			for entry: SpawnEntryResource in wave.entries:
				var path: String = entry.ship_scene.resource_path if entry.ship_scene else ""
				if path != _DRONE and path != _RAZOR_DRONE:
					continue
				var formation_name: StringName = &"none"
				var formation_count: int = -1
				if entry.formation:
					var f: FormationResource = entry.formation
					formation_name = f.get_script().get_global_name()
					formation_count = f.count
				out.append({
					"section": section.section_name,
					"kind": "DRONE" if path == _DRONE else "RAZOR_DRONE",
					"trigger": wave.trigger_time,
					"offset": entry.base_offset,
					"delay": entry.spawn_delay,
					"formation": formation_name,
					"formation_count": formation_count,
					"movement": entry.movement != null,
				})
	return out


# ── The pin ───────────────────────────────────────────────────────────────────

func test_pinned_drone_and_razor_drone_spawns_match_todays_data() -> void:
	var actual := _actual_drone_spawns(_build_sections())
	assert_eq(actual.size(), EXPECTED.size(),
		"the number of DRONE/RAZOR_DRONE entries in _build_sections() has changed")
	assert_eq(actual, EXPECTED,
		"a drone or razor drone spawn's section, trigger, offset, delay, formation or movement changed")


## All 121 pinned rows, split by kind. If this count ever drifts from `EXPECTED.size()` the roster
## text above is stale relative to itself, independent of whether `_build_sections()` changed.
func test_the_pin_itself_is_internally_consistent() -> void:
	var drone_rows := 0
	var razor_rows := 0
	for row: Dictionary in EXPECTED:
		if row["kind"] == "DRONE":
			drone_rows += 1
		else:
			razor_rows += 1
	assert_eq(drone_rows + razor_rows, EXPECTED.size())
	assert_gt(drone_rows, 0, "the pin must contain drone rows or this file asserts nothing")
	assert_eq(razor_rows, 2, "level 1 has exactly one razor_drone pair today")


## Every drone line ships with a movement (it flies a path); both razor drone lines do not (razor
## drones are self-managed AI — `docs/enemy-roster.md`, `wave_builder.gd:288-292`). Called
## out as its own case per the task's acceptance criteria, even though the full-row comparison
## above already implies it.
func test_every_drone_has_movement_and_every_razor_drone_does_not() -> void:
	for row: Dictionary in EXPECTED:
		if row["kind"] == "DRONE":
			assert_true(row["movement"], "drone at %s (%s) has no movement" % [row["offset"], row["section"]])
		else:
			assert_false(row["movement"], "razor_drone at %s (%s) unexpectedly has a movement" % [row["offset"], row["section"]])


## The specific regression this pin exists to catch once t15 removes every drone's `.move()`
## (§2.10 step 2, plan §4 row for this file: "movement == null for every drone and razor... A
## drone line re-given `.move()` fails"). Verified now, against today's data, by hand-flipping one
## row's `movement` to `false` and observing `test_pinned_drone_and_razor_drone_spawns_match_todays_data`
## go red — see the task's acceptance criteria. Left as a comment rather than code because doing it
## in-line would require mutating `EXPECTED`, which is a `const`.


## Count formations directly from a fresh call to `_build_sections()` — not derived from
## `EXPECTED` — so this is a standalone confirmation of the plan's "14 drone formations (cluster
## x7, wedge x6, line x1)", counted from data.
func test_level_1_has_14_drone_formations_by_type() -> void:
	var counts: Dictionary = {}
	var total := 0
	for section: LevelSection in _build_sections():
		for wave: WaveResource in section.waves:
			for entry: SpawnEntryResource in wave.entries:
				if entry.ship_scene == null or entry.ship_scene.resource_path != _DRONE:
					continue
				if entry.formation == null:
					continue
				var cname: StringName = entry.formation.get_script().get_global_name()
				counts[cname] = counts.get(cname, 0) + 1
				total += 1
	assert_eq(total, 14, "level 1 must have exactly 14 drone formations")
	assert_eq(int(counts.get(&"ClusterFormation", 0)), 7, "cluster formation count")
	assert_eq(int(counts.get(&"WedgeFormation", 0)), 6, "wedge formation count")
	assert_eq(int(counts.get(&"LineFormation", 0)), 1, "line formation count")


# ── Peak concurrency (plan §5 C3) ───────────────────────────────────────────────

func test_legacy_peak_concurrency_per_section() -> void:
	var ship_paths: Array[String] = [_DRONE, _RAZOR_DRONE]
	for section: LevelSection in _build_sections():
		if not _EXPECTED_LEGACY_PEAKS.has(section.section_name):
			continue
		var times := DroneConcurrency.spawn_times(section, ship_paths)
		var peak: int = DroneConcurrency.peak_concurrency(times, _LEGACY_LIFETIME)
		assert_eq(peak, int(_EXPECTED_LEGACY_PEAKS[section.section_name]),
			"%s: legacy peak concurrent drones changed" % section.section_name)


## Boundary: a section with no drones at all must compute a peak of 0, not error or return a
## stale value from a previous section's spawn_times().
func test_a_section_with_no_drones_has_zero_peak_concurrency() -> void:
	for section: LevelSection in _build_sections():
		if section.section_name != &"asteroid_belt":
			continue
		var times := DroneConcurrency.spawn_times(section, [_DRONE, _RAZOR_DRONE])
		assert_eq(times.size(), 0, "asteroid_belt spawns no drones or razor drones")
		assert_eq(DroneConcurrency.peak_concurrency(times, _LEGACY_LIFETIME), 0)


# ── The space station's BOTTOM reinforcement squad ──────────────────────────────

## `StationReinforcements.squads()` order is the `Edge` enum's declaration order — LEFT, RIGHT,
## BOTTOM, TOP (`station_reinforcements.gd:58,157-195`) — so index 2 is BOTTOM.
func test_station_reinforcements_bottom_squad_is_two_drones_straight_170() -> void:
	var container := Node2D.new()
	add_child_autofree(container)
	var station := _STATION_SCENE.instantiate() as SpaceStation
	container.add_child(station)
	var reinf := station.get_node("Reinforcements") as StationReinforcements

	var squads: Array = reinf.squads()
	assert_gt(squads.size(), 2, "station reinforcements must have at least a BOTTOM squad")
	if squads.size() <= 2:
		return
	var bottom: Array = squads[2]
	assert_eq(bottom.size(), 2, "the BOTTOM squad must be exactly two ships")

	var offsets: Array[Vector2] = []
	for entry: SpawnEntryResource in bottom:
		assert_eq(entry.ship_scene.resource_path, _DRONE, "BOTTOM squad must be drones")
		offsets.append(entry.base_offset)
		assert_not_null(entry.movement, "BOTTOM squad entry has no movement")
		var m := entry.movement as StraightMovement
		assert_not_null(m, "BOTTOM squad entry must use StraightMovement")
		if m != null:
			assert_almost_eq(m.speed, 170.0, 0.001, "BOTTOM squad speed changed")
			assert_almost_eq(m.angle, PI, 0.001, "BOTTOM squad angle changed")
		assert_eq(entry.exit_mode, EnemyPathMover.ExitMode.FREE_ON_DURATION,
			"BOTTOM squad must free_after (FREE_ON_DURATION)")
		assert_almost_eq(entry.exit_time, reinf.reinforcement_lifetime, 0.001,
			"BOTTOM squad free_after duration changed")
	assert_true(offsets.has(Vector2(-100.0, 290.0)), "BOTTOM squad missing its left offset")
	assert_true(offsets.has(Vector2(100.0, 290.0)), "BOTTOM squad missing its right offset")


# ── The Open Space hub's ambient PatrolDrone spawn ──────────────────────────────

## `sector_hub.tscn` is instantiated but never added to the tree, per the established pattern in
## `test_hub_log_placement.gd` / `test_weapon_unlock_sources.gd`: `_ready()` boots a real player,
## HUD and mission wiring this test needs none of. Reading the exported spawn parameters directly
## is enough to pin "3 PatrolDrones, 300-600 px from origin" — `_spawn_initial_drones()` places
## each at `randf_range(spawn_radius * 0.5, spawn_radius)`.
func test_sector_hub_spawns_three_patrol_drones_in_a_300_to_600_band() -> void:
	var hub := _HUB_SCENE.instantiate()
	assert_eq(int(hub.drone_count), 3, "SectorHub.drone_count changed")
	assert_almost_eq(float(hub.spawn_radius), 600.0, 0.001, "SectorHub.spawn_radius changed")

	var constants: Dictionary = load(_HUB_SCRIPT).get_script_constant_map()
	assert_true(constants.has("PATROL_DRONE"), "SectorHub must still reference a PATROL_DRONE scene")
	var patrol_drone: PackedScene = constants.get("PATROL_DRONE")
	assert_eq(patrol_drone.resource_path, "res://open_space/scenes/entities/enemies/patrol_drone.tscn",
		"SectorHub's ambient spawn must still be PatrolDrone")
	hub.free()
