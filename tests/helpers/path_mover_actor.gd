## A minimal `CharacterBody2D` stand-in for `EnemyPathMover`'s host actor.
##
## `EnemyPathMover` only needs `get_parent() as CharacterBody2D`
## (`enemy_path_mover.gd:35`) plus, optionally, a sibling-free child node named "AIStateMachine"
## to disable (`enemy_path_mover.gd:63-65`, a plain name lookup — no `StateMachine` script
## required). This fixture pulls in neither, so `tests/integration/test_enemy_path_mover.gd` can
## pin the mover's own behaviour without BaseEnemy's config/HurtBox/AttackController machinery
## riding along.
##
## Deliberately has no `class_name`: test-only types should not appear in the game's global
## class list. Preload it instead:
##     const PathMoverActor := preload("res://tests/helpers/path_mover_actor.gd")
##     var actor: CharacterBody2D = PathMoverActor.new()
##
## The file name avoids the `test_` prefix so GUT does not try to collect it as a test script.
extends CharacterBody2D
