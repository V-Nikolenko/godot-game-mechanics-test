## The test fixture enemy for the brain + mover contract (t10): a `BaseEnemy` root with the
## minimum children `BaseEnemy._ready()` needs, plus an `EnemyMover` and a `fixture_brain.gd`
## brain. Scene: `tests/helpers/fixture_enemy.tscn`.
##
## Adds nothing to `BaseEnemy` on purpose — the point is to exercise the base class's own
## physics tick and `suspend_ai()`. Being the root script of a scene that contains an
## `EnemyMover`, it is swept by `tests/integration/test_enemy_mover_single_writer.gd`.
##
## No `class_name`: test-only types stay out of the game's global class list. Preload the scene.
extends BaseEnemy
