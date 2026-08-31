## Characterization test for the EventBus autoload.
##
## EventBus is pure contract: it declares signals and nothing else. Every HUD and
## system in the game binds to these names and arities, so this test pins the whole
## surface. If a signal is renamed or its arguments change, this fails loudly and
## points at every subscriber that needs updating.
extends GutTest

const EventBusScript := preload("res://global/systems/event_bus.gd")

## signal name -> ordered argument names.
const EXPECTED: Dictionary = {
	"player_health_changed":     ["current", "maximum"],
	"player_overheat_changed":   ["percentage"],
	"player_weapon_changed":     ["mode"],
	"player_rocket_changed":     ["icon"],
	"player_died":               [],
	"ability_activated":         ["id", "damage_mult", "fire_rate_mult"],
	"ability_deselected":        [],
	"mission_wave_started":      ["wave_index"],
	"mission_complete":          [],
	"mission_failed":            [],
	"score_changed":             ["total"],
	"combo_changed":             ["multiplier", "decay_remaining"],
	"score_event":               ["world_position", "points", "reason"],
	"skill_challenge_completed": ["clean", "bonus"],
	"enemy_spawned_orphan":      ["enemy"],
}

var _declared: Dictionary = {}


func before_all() -> void:
	## Everything EventBus declares beyond what a bare Node already has.
	var base_names: Array = []
	var bare := Node.new()
	for sig: Dictionary in bare.get_signal_list():
		base_names.append(sig["name"])
	bare.free()

	var bus := EventBusScript.new()
	for sig: Dictionary in bus.get_signal_list():
		if sig["name"] in base_names:
			continue
		var arg_names: Array = []
		for arg: Dictionary in sig["args"]:
			arg_names.append(arg["name"])
		_declared[sig["name"]] = arg_names
	bus.free()


func test_every_expected_signal_exists_with_the_expected_arguments() -> void:
	for name: String in EXPECTED:
		assert_true(_declared.has(name), "EventBus declares '%s'" % name)
		if _declared.has(name):
			assert_eq(_declared[name], EXPECTED[name], "'%s' argument list" % name)


func test_event_bus_declares_nothing_beyond_the_documented_set() -> void:
	## Catches a signal added without a test — the point of a characterization
	## suite is that the contract cannot drift silently.
	var extras: Array = []
	for name: String in _declared:
		if not EXPECTED.has(name):
			extras.append(name)
	extras.sort()
	assert_eq(extras, [], "undocumented signals on EventBus")


func test_the_live_autoload_matches_the_script() -> void:
	## The autoload registered in project.godot must be this exact script.
	assert_eq(EventBus.get_script(), EventBusScript)
	for name: String in EXPECTED:
		assert_true(EventBus.has_signal(name), "autoload exposes '%s'" % name)


func test_signals_round_trip_through_the_live_autoload() -> void:
	var seen: Array = []
	var cb := func(current: int, maximum: int) -> void: seen.append([current, maximum])
	EventBus.player_health_changed.connect(cb)
	EventBus.player_health_changed.emit(30, 100)
	EventBus.player_health_changed.disconnect(cb)
	assert_eq(seen, [[30, 100]])
