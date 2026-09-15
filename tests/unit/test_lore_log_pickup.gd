## Unit tests for LoreLogPickup (global/pickups/lore_log_pickup.gd).
##
## No scene loading — exercises the live LogState/DialogPlayer autoloads directly, matching
## test_dialog_player.gd / test_log_state.gd's pattern (tests/README.md: unit/ is
## "no scene loading").
##
## ⚠️ Autoload state. LoreLogPickup._collect() calls the live LogState autoload, and the whole
## suite shares it, so before_all/after_all snapshot and restore catalogue_dir and _collected on
## top of SaveSandbox — the same pattern test_weapon_unlock_sources.gd uses for UpgradeState.
extends GutTest

const LoreLogPickupScript := preload("res://global/pickups/lore_log_pickup.gd")
const PlayerStub := preload("res://tests/helpers/player_stub.gd")
const SaveSandbox := preload("res://tests/helpers/save_sandbox.gd")

const FIXTURE_DIR := "res://tests/unit/fixtures/log_entries"

var _sandbox := SaveSandbox.new()
var _saved_catalogue_dir: String
var _saved_collected: Dictionary


func before_all() -> void:
	_sandbox.capture()
	_saved_catalogue_dir = LogState.catalogue_dir
	_saved_collected = LogState._collected.duplicate()


func after_all() -> void:
	LogState.catalogue_dir = _saved_catalogue_dir
	LogState._collected = _saved_collected
	_sandbox.restore()


func before_each() -> void:
	LogState.catalogue_dir = FIXTURE_DIR
	_sandbox.clear_all()
	LogState._load_catalogue()
	LogState._load()


func _fresh_pickup() -> PickupBase:
	return LoreLogPickupScript.new()


func test_colliding_with_the_pickup_collects_the_next_entry_and_advances_log_state() -> void:
	var pickup := _fresh_pickup()
	var player := PlayerStub.spawn()
	add_child_autofree(player)

	pickup._collect(player)

	assert_eq(LogState.collected_count(), 1)
	assert_true(LogState.is_collected(&"entry_beta"), "lowest sequence in the fixture set")
	pickup.free()


func test_the_notification_names_the_entry() -> void:
	var pickup := _fresh_pickup()
	var player := PlayerStub.spawn()
	add_child_autofree(player)

	pickup._collect(player)

	assert_true(pickup._get_dialog_text().contains("Test Entry Beta"))
	pickup.free()


## Boundary: collecting after the catalogue is exhausted does not double-count.
func test_collecting_after_the_catalogue_is_exhausted_does_not_double_count() -> void:
	var player := PlayerStub.spawn()
	add_child_autofree(player)

	for i in range(3):
		var draining := _fresh_pickup()
		draining._collect(player)
		draining.free()
	assert_eq(LogState.collected_count(), 3, "fixture catalogue fully drained")

	var extra := _fresh_pickup()
	extra._collect(player)

	assert_eq(LogState.collected_count(), 3, "collecting after exhaustion does not double-count")
	assert_eq(extra._get_dialog_text(), "", "no false notification once nothing is left")
	extra.free()


## `_on_body_entered` end-to-end, proving the wiring through PickupBase (collect + queue_free)
## rather than just the overridden hooks in isolation. DialogPlayer.is_active is pre-set so
## PickupBase._show_notification()'s existing guard short-circuits before DialogPlayer.play() is
## ever called — no coroutine starts, so there is no `await` left suspended when the test ends.
func test_on_body_entered_collects_and_frees_the_pickup() -> void:
	var pickup := _fresh_pickup()
	add_child_autofree(pickup)
	var player := PlayerStub.spawn()
	add_child_autofree(player)

	DialogPlayer.is_active = true
	pickup._on_body_entered(player)
	DialogPlayer.is_active = false

	assert_true(pickup.is_queued_for_deletion())
	assert_eq(LogState.collected_count(), 1)
