## Builds a minimal test world for a behaviour spec that must run unchanged in Open Space and in
## Assault (docs/plans/cmufklb100001p92xs1ey2fb1/3-plan.md §4 row test_enemy_dual_mode.gd, P-17,
## task t12-dual-harness).
##
## `open_space()` puts nothing but a fake player in the tree, so an `AUTO` `EnemyMover` resolves no
## constraint (`EnemyWorld.movement_constraint()` finds no provider). `assault()` also adds an
## `ArenaCamera`, so the SAME `AUTO` `EnemyMover` picks up `AssaultCorridorConstraint` through that
## same lookup — the real game's own resolution path, never constructed by hand here.
##
## Each harness's `root` already holds the fake player: a bare `CharacterBody2D` in group
## "player" (the group `TargetInfo.player()` and `EnemyWorld` read), whose `global_position` and
## `velocity` the test sets directly. No `PlayerBase`, no input, no sprites — nothing a brain or
## mover needs to know about beyond the group and those two properties.
##
## The caller adds `root` to the tree itself (`add_child_autofree(harness.root)`), then parents any
## enemy under it — after that, both `ArenaCamera` (if present) and the player are already resolvable
## through `get_tree()`.
##
## No `class_name`: test-only, like every other `tests/helpers/` fixture. Preload it instead:
##     const HARNESS := preload("res://tests/helpers/enemy_ai_harness.gd")
##     var harness = HARNESS.assault()
extends RefCounted

## "open_space" or "assault" — for assertion messages, not behaviour.
var label: String
var is_assault: bool
var root: Node2D
var player: CharacterBody2D


static func open_space() -> RefCounted:
	return _build("open_space", false)


static func assault() -> RefCounted:
	return _build("assault", true)


static func _build(build_label: String, assault_mode: bool) -> RefCounted:
	var h: RefCounted = (load("res://tests/helpers/enemy_ai_harness.gd") as GDScript).new()
	h.label = build_label
	h.is_assault = assault_mode

	h.root = Node2D.new()
	h.root.name = "AssaultWorld" if assault_mode else "OpenSpaceWorld"

	h.player = CharacterBody2D.new()
	h.player.name = "Player"
	h.player.add_to_group(&"player")
	h.root.add_child(h.player)

	if assault_mode:
		var cam := ArenaCamera.new()
		cam.name = "ArenaCamera"
		cam.global_position = Vector2(640.0, 360.0)
		h.root.add_child(cam)

	return h
