## A fixture enemy that answers the duck-typed `accepts_ward()` with true: the control for the Carrier's refusal (Phase 10 t6), so the ward
## filter is shown to read the answer and not merely the method's presence. Test-only; the scene is `fixture_enemy.tscn` with this script
## swapped in by the test before it enters the tree.
extends "res://tests/helpers/fixture_enemy.gd"


func accepts_ward() -> bool:
	return true
