## INVARIANT test: the sector hub actually places findable log records, and the catalogue total
## matches what is placeable — the task's literal "done when" criteria, checked in code rather
## than by hand count so it stays true if either side changes later without the other.
##
## Lives in integration/ because it loads a real scene (tests/README.md: unit/ is "no scene
## loading"). sector_hub.tscn is instantiated but never added to the tree — walking the node list
## needs none of its _ready() side effects.
##
## Never drives a real DialogPlayer.play(): the extracted LoreLogPickup is exercised via a direct
## _collect() call, never _on_body_entered(), which would reach _show_notification() with
## non-empty text and start a real coroutine — same trap tests/README.md documents for the
## sibling lore-log-pickup task's review.
extends GutTest

const HUB_SCENE: PackedScene = preload("res://open_space/scenes/levels/sector_hub.tscn")
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
	## Restored directly rather than via _load_catalogue()/_load() — the sandboxed on-disk save
	## file is restored separately below, and reloading against it here (while the swap in
	## test_a_placed_lore_log_pickup_is_a_real_working_pickup is still mid-flight in the same
	## process) would warn about ids the production catalogue does not know. Same pattern
	## test_lore_log_pickup.gd uses.
	LogState.catalogue_dir = _saved_catalogue_dir
	LogState._load_catalogue()
	LogState._collected = _saved_collected
	_sandbox.restore()


func _walk(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for child: Node in node.get_children():
		out.append_array(_walk(child))
	return out


func _lore_log_pickups(root: Node) -> Array[LoreLogPickup]:
	var found: Array[LoreLogPickup] = []
	for node: Node in _walk(root):
		if node is LoreLogPickup:
			found.append(node as LoreLogPickup)
	return found


func _info_log_interactables(root: Node) -> Array[InfoLogInteractable]:
	var found: Array[InfoLogInteractable] = []
	for node: Node in _walk(root):
		if node is InfoLogInteractable:
			found.append(node as InfoLogInteractable)
	return found


func test_hub_places_at_least_three_lore_logs_and_two_info_logs() -> void:
	var hub := HUB_SCENE.instantiate()
	assert_gte(_lore_log_pickups(hub).size(), 3,
		"sector_hub.tscn must place at least 3 LoreLogPickup instances")
	assert_gte(_info_log_interactables(hub).size(), 2,
		"sector_hub.tscn must place at least 2 InfoLogInteractable instances")
	hub.free()


func test_catalogue_total_matches_placed_lore_log_count() -> void:
	var hub := HUB_SCENE.instantiate()
	var placed := _lore_log_pickups(hub).size()
	assert_eq(LogState.total_count(), placed,
		"LogState's live catalogue total must match the number of LoreLogPickup instances placed in the hub")
	hub.free()


func test_a_placed_lore_log_pickup_is_a_real_working_pickup() -> void:
	## Swaps the live LogState's catalogue to the fixture set for this test only, and restores it
	## before returning — LoreLogPickup._collect() calls the live autoload, not an instance this
	## test controls, so leaving the swap in place would leak into whichever test runs next.
	LogState.catalogue_dir = FIXTURE_DIR
	LogState._load_catalogue()
	LogState._collected.clear()

	var hub := HUB_SCENE.instantiate()
	var pickups := _lore_log_pickups(hub)
	var pickup: LoreLogPickup = pickups[0] if not pickups.is_empty() else null
	if pickup != null:
		pickup.get_parent().remove_child(pickup)
	hub.free()

	assert_not_null(pickup, "sector_hub.tscn must place at least one LoreLogPickup")
	if pickup != null:
		add_child_autofree(pickup)
		var player := PlayerStub.spawn()
		add_child_autofree(player)

		pickup._collect(player)

		assert_eq(LogState.collected_count(), 1,
			"a placed LoreLogPickup must actually advance LogState when collected")

	LogState.catalogue_dir = _saved_catalogue_dir
	LogState._load_catalogue()
	LogState._collected = _saved_collected


func test_a_placed_info_log_has_real_message_text() -> void:
	var hub := HUB_SCENE.instantiate()
	var interactables := _info_log_interactables(hub)
	assert_false(interactables.is_empty())
	if not interactables.is_empty():
		assert_false(interactables[0].message.is_empty(),
			"a placed InfoLogInteractable must not ship with an empty message")
	hub.free()
