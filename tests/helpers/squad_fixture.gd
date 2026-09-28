## The spawn fixture for `test_wave_squads.gd` (t5): a plain `Node2D` with a `squad` property, the
## minimum shape `WaveManager._spawn_ship()` looks for (docs/plans/cmufs7ek60001nm2x6d0bt2et/
## 3-plan.md §2.4.1's "duck-typed through `in`"). It never calls `SquadController.join()` itself —
## that is an `EnemyBrain`'s job, out of scope here. This file only has to prove WaveManager wires
## the right board into the right property before add_child.
##
## No `class_name`: test-only types stay out of the game's global class list. Preload it and build
## a `PackedScene` around it, the same pattern as `_blank_ship_scene()` elsewhere in the suite.
extends Node2D

var squad: SquadController
