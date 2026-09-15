## Characterization + intent tests for PickupBase (global/pickups/pickup_base.gd).
##
## No shipped PickupBase subclass is tested directly here — the 9 real subclasses
## (armor_tank_pickup.gd etc.) are ship-specific and only ever placed in open_space/assault.
## These are tiny test-doubles that exercise the base class's dispatch/persistence logic in
## isolation: the widened detection (a non-PlayerBase body reaching the opt-in _collect_any
## hook), and the persistent_id restart-safety primitive.
extends GutTest

const SaveSandbox := preload("res://tests/helpers/save_sandbox.gd")
const PlayerStub := preload("res://tests/helpers/player_stub.gd")

var _sandbox := SaveSandbox.new()


## Records a _collect(PlayerBase) call. Mirrors every one of the 9 real subclasses' shape.
class RecordingPickup extends PickupBase:
	var collect_calls: int = 0

	func _collect(_player: PlayerBase) -> void:
		collect_calls += 1


## A pickup that opts into the generic (non-PlayerBase) path, the shape a future
## infiltration-aware pickup (e.g. LoreLogPickup) would take.
class GenericAwarePickup extends PickupBase:
	var collect_any_calls: int = 0

	func _collect_any(_body: Node2D) -> bool:
		collect_any_calls += 1
		return true


func before_all() -> void:
	_sandbox.capture()


func after_all() -> void:
	_sandbox.restore()


func before_each() -> void:
	_sandbox.clear_all()
	PickupState._load()


func test_a_playerbase_body_is_collected_as_before() -> void:
	var pickup := RecordingPickup.new()
	add_child_autofree(pickup)
	var player := PlayerStub.spawn()
	add_child_autofree(player)

	pickup._on_body_entered(player)

	assert_eq(pickup.collect_calls, 1)
	assert_true(pickup.is_queued_for_deletion())


## Boundary case for the round-1-reviewed fix: a plain Node2D body (the shape of the
## infiltration player) reaching a subclass that has NOT opted into the generic path must be
## left completely inert — no collect, no consumption, exactly as if detection had never
## widened for it.
func test_a_non_playerbase_body_against_the_default_hook_is_ignored() -> void:
	var pickup := RecordingPickup.new()
	add_child_autofree(pickup)
	var body := Node2D.new()
	body.add_to_group("player")
	add_child_autofree(body)

	pickup._on_body_entered(body)

	assert_eq(pickup.collect_calls, 0, "the default _collect_any never calls _collect")
	assert_false(pickup.is_queued_for_deletion(), "an unhandled body must not consume the pickup")


## The opt-in path: a subclass that overrides _collect_any and returns true is reached by a
## plain Node2D body and consumes itself normally.
func test_a_non_playerbase_body_against_an_opted_in_hook_is_collected() -> void:
	var pickup := GenericAwarePickup.new()
	add_child_autofree(pickup)
	var body := Node2D.new()
	body.add_to_group("player")
	add_child_autofree(body)

	pickup._on_body_entered(body)

	assert_eq(pickup.collect_any_calls, 1)
	assert_true(pickup.is_queued_for_deletion())


func test_a_non_player_group_body_is_ignored_entirely() -> void:
	var pickup := RecordingPickup.new()
	add_child_autofree(pickup)
	var body := Node2D.new()
	add_child_autofree(body)

	pickup._on_body_entered(body)

	assert_eq(pickup.collect_calls, 0)
	assert_false(pickup.is_queued_for_deletion())


## Characterization: every existing pickup leaves persistent_id at its default "" and must
## collect every time, matching current behavior exactly.
func test_empty_persistent_id_collects_every_time() -> void:
	var pickup := GenericAwarePickup.new()
	add_child_autofree(pickup)
	var player := PlayerStub.spawn()
	add_child_autofree(player)

	pickup._on_body_entered(player)

	assert_eq(pickup.collect_any_calls, 0, "a PlayerBase body goes through _collect, not _collect_any")
	assert_true(pickup.is_queued_for_deletion())


## The restart/replay boundary case the task exists to fix: a scene reload respawns a fresh
## node with the same persistent_id. The second instance must not re-collect.
func test_persistent_id_pickup_does_not_double_collect_across_a_simulated_reload() -> void:
	var first := RecordingPickup.new()
	first.persistent_id = &"level_1_lore_log"
	add_child_autofree(first)
	var player := PlayerStub.spawn()
	add_child_autofree(player)

	first._on_body_entered(player)
	assert_eq(first.collect_calls, 1)
	assert_true(PickupState.has_collected(&"level_1_lore_log"))

	## Simulate the scene reload: a brand-new node instance, same persistent_id.
	var second := RecordingPickup.new()
	second.persistent_id = &"level_1_lore_log"
	add_child_autofree(second)

	second._on_body_entered(player)

	assert_eq(second.collect_calls, 0, "a respawned pickup must not re-grant an already-collected id")
	assert_true(second.is_queued_for_deletion(), "it still removes itself silently")
