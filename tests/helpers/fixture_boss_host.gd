## The fixture boss for the reinforcement machinery (Phase 11 t2, docs/plans/cmug256so0031m52wbxomst72/3-plan.md §2.2): the armoured
## `fixture_modular_host.gd` root, plus `is_dying()` (ScoreTracker's duck-typed "pay nothing now" question), written by the test through
## `dying`. Scene: `tests/helpers/fixture_boss_host.tscn` — five parts under `Modules`:
##   Hangar     HANGAR, locked, 100 HP, a `Light`, a PERIODIC `Bay` (`hangar`, `opens_part`) whose `Mouth` sits 40 px outboard
##   Sector     WEAPON, 100 HP, a `Light`, an ON_SECTOR_LOSS `Bay` (`sector`) watching `watch_a` and `watch_b`
##   WatchA / WatchB / Other   WEAPON, 100 HP
## Payload scenes are set by the test. No `class_name`: test-only. Preload the scene.
extends "res://tests/helpers/fixture_modular_host.gd"

var dying: bool = false


func is_dying() -> bool:
	return dying
