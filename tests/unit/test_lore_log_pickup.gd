## Characterization/intent tests for LoreLogPickup (global/pickups/lore_log_pickup.gd).
##
## No case here calls DialogPlayer.play() with non-empty text: cases 1-3 call _collect()
## directly (which never reaches _show_notification()), and case 4 pre-arms
## DialogPlayer.is_active before calling the real _on_body_entered() so
## PickupBase._show_notification()'s existing guard short-circuits before play() is ever
## referenced. See the sibling lore-log-pickup task's stuck review
## (docs/plans/flying-into-a-log-record-in-open-space-picks-it-up-and-tells/4-review.md) for why
## driving a real play() coroutine inside a test leaks a permanently-suspended
## GDScriptFunctionState invisible to the gate.
extends GutTest

const SaveSandbox := preload("res://tests/helpers/save_sandbox.gd")
const PlayerStub := preload("res://tests/helpers/player_stub.gd")

const FIXTURE_DIR := "res://tests/unit/fixtures/log_entries"

var _sandbox := SaveSandbox.new()
var _prev_catalogue_dir: String


func before_all() -> void:
	_sandbox.capture()
	_prev_catalogue_dir = LogState.catalogue_dir


func after_all() -> void:
	LogState.catalogue_dir = _prev_catalogue_dir
	LogState._load_catalogue()
	LogState._load()
	_sandbox.restore()


func before_each() -> void:
	LogState.catalogue_dir = FIXTURE_DIR
	_sandbox.clear_all()
	LogState._load_catalogue()
	LogState._load()


func after_each() -> void:
	DialogPlayer.is_active = false


func test_collecting_advances_log_state_to_the_lowest_sequence_entry() -> void:
	var pickup := LoreLogPickup.new()
	add_child_autofree(pickup)

	pickup._collect(PlayerStub.spawn())

	assert_eq(LogState.collected_count(), 1)
	assert_true(LogState.is_collected(&"entry_beta"), "entry_beta has the lowest sequence (0) in the fixture set")


func test_notification_text_names_the_collected_entry() -> void:
	var pickup := LoreLogPickup.new()
	add_child_autofree(pickup)

	pickup._collect(PlayerStub.spawn())

	assert_string_contains(pickup._get_dialog_text(), "Test Entry Beta")


func test_boundary_collecting_after_the_catalogue_is_exhausted_does_not_double_count() -> void:
	LogState.collect_next()
	LogState.collect_next()
	LogState.collect_next()
	assert_eq(LogState.collected_count(), 3, "fixture catalogue has exactly 3 entries")

	var pickup := LoreLogPickup.new()
	add_child_autofree(pickup)
	pickup._collect(PlayerStub.spawn())

	assert_eq(LogState.collected_count(), 3, "a fourth collection must not double-count")
	assert_eq(pickup._get_dialog_text(), "", "no false notification once the catalogue is exhausted")


func test_on_body_entered_collects_and_frees_the_pickup() -> void:
	## Pre-arm the notification guard so _show_notification() returns before DialogPlayer.play()
	## is ever referenced (see pickup_base.gd::_show_notification()'s first statement) — this
	## proves LoreLogPickup's _collect() override is reached through the real PickupBase signal
	## handler without starting a real dialog coroutine. The generic dispatch/queue_free plumbing
	## itself is already covered by tests/unit/test_pickup_base.gd.
	DialogPlayer.is_active = true
	var pickup := LoreLogPickup.new()
	add_child_autofree(pickup)
	var player := PlayerStub.spawn()
	add_child_autofree(player)

	pickup._on_body_entered(player)

	assert_true(pickup.is_queued_for_deletion())
	assert_eq(LogState.collected_count(), 1)
