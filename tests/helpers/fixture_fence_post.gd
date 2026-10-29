extends "res://tests/helpers/fixture_enemy.gd"
## A fixture enemy that answers the duck-typed `is_fence_post()` a laser-fence post will (docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md §2.10.5):
## a shield generator never shields one. Scene: `tests/helpers/fixture_fence_post.tscn`. No `class_name`: test-only.


func is_fence_post() -> bool:
	return true
