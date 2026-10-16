## A fixture enemy that refuses repair, like the Space Station (`can_be_repaired()` false). Test-only; the scene is
## `fixture_enemy.tscn` with this script swapped in by the test before it enters the tree.
extends "res://tests/helpers/fixture_enemy.gd"


func can_be_repaired() -> bool:
	return false
