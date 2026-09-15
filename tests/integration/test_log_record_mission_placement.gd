## Proves a log record placed inside a real mission scene — one assault level, one
## infiltration level — is actually reachable by that mode's real player, not just that the
## InfoLogInteractable class itself works in isolation (already covered by
## tests/unit/test_info_log_interactable.gd).
##
## Each scene is instantiated but never added to the tree as a whole: level_1.tscn's other
## nodes (WaveManager, LevelDirector, ScoreTracker) run real, non-trivial _ready() side effects
## (adding a HUD to the tree root, scheduling director sections) that have nothing to do with
## this test and are already covered by tests/integration/test_level_1_sequence.gd. Instead the
## placed LogRecord node is located via find_child(), detached from the discarded instance, and
## added to the test on its own — its own _ready() (PromptLabel wiring) still runs normally.
##
## No test here starts a real DialogPlayer.play() coroutine — same leak trap as
## test_info_log_interactable.gd (see its header). Reachability is proven by the prompt
## appearing on body_entered, the same signal both InfoLogInteractable and PickupBase gate on.
extends GutTest

const LEVEL_1_SCENE: PackedScene = preload("res://assault/scenes/levels/edelia/1/level_1.tscn")
const TEST_ISOMETRIC_SCENE: PackedScene = preload("res://infiltration/scenes/levels/TestIsometricScene.tscn")
const INFILTRATION_PLAYER_SCENE: PackedScene = preload("res://infiltration/scenes/entities/player/player.tscn")
const PlayerStub := preload("res://tests/helpers/player_stub.gd")


func _extract_log_record(scene: PackedScene) -> InfoLogInteractable:
	var root := scene.instantiate()
	var log_record := root.find_child("LogRecord", true, false) as InfoLogInteractable
	if log_record != null:
		log_record.get_parent().remove_child(log_record)
	root.free()
	return log_record


func test_level_1_places_a_reachable_log_record() -> void:
	var log_record := _extract_log_record(LEVEL_1_SCENE)
	assert_not_null(log_record, "level_1.tscn must contain an InfoLogInteractable named LogRecord")
	add_child_autofree(log_record)

	var player := PlayerStub.spawn()
	add_child_autofree(player)

	log_record._on_body_entered(player)

	assert_true(log_record._prompt.visible, "the assault player must reach the placed log record")


func test_test_isometric_scene_places_a_reachable_log_record() -> void:
	var log_record := _extract_log_record(TEST_ISOMETRIC_SCENE)
	assert_not_null(log_record,
		"TestIsometricScene.tscn must contain an InfoLogInteractable named LogRecord")
	add_child_autofree(log_record)

	## The real infiltration player scene, not a stub — this is the end-to-end proof that the
	## group-membership fix (infiltration/scenes/entities/player/player.gd::_ready()) actually
	## makes the ground player visible to a log record, not just to a synthetic body.
	var player := INFILTRATION_PLAYER_SCENE.instantiate()
	add_child_autofree(player)

	log_record._on_body_entered(player)

	assert_true(log_record._prompt.visible, "the infiltration player must reach the placed log record")


## The group fix alone is not sufficient: InfoLogInteractable's Area2D only ever emits
## body_entered for a body whose collision_layer overlaps its collision_mask (4, the
## "environemnt_player" layer every pickup/interactable uses to detect the player) — group
## membership is a second, independent gate INSIDE the handler, checked only once the signal has
## already fired. The two tests above call _on_body_entered() directly and would pass even if the
## infiltration player were never physically detectable at all. This test goes through real
## physics: both bodies are placed overlapping and added to the tree with no direct method call,
## proving infiltration/scenes/entities/player/player.tscn's collision_layer = 4 (added alongside
## the group fix) actually lets the signal fire in real gameplay.
func test_test_isometric_scene_log_record_detects_the_real_player_via_physics() -> void:
	var log_record := _extract_log_record(TEST_ISOMETRIC_SCENE)
	assert_not_null(log_record)
	add_child_autofree(log_record)

	var player := INFILTRATION_PLAYER_SCENE.instantiate()
	add_child_autofree(player)

	## The player's own CollisionShape2D sits at a local offset (Vector2(0, 14) in the shipped
	## scene, roughly the sprite's feet), not at the CharacterBody2D's own origin — position the
	## log record at the shape's actual global position rather than the body's, or the two never
	## overlap regardless of layer/mask.
	var player_shape := player.get_node("CollisionShape2D") as CollisionShape2D
	log_record.global_position = player_shape.global_position

	for _i in range(4):
		await get_tree().physics_frame

	assert_true(log_record._prompt.visible,
		"the interactable's Area2D must actually detect the player's physics body, not just be reachable by a direct call")
