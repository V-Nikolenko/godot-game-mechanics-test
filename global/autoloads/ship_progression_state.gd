# global/autoloads/ship_progression_state.gd
## Persists permanent ship upgrades that survive across runs.
## Currently tracks: permanent shield slot count, open-space boost charge capacity.
## Registered as autoload "ShipProgressionState" in project.godot.
extends Node

const SAVE_PATH := "user://ship_progression.cfg"
const SECTION := "progression"
const KEY_SHIELDS := "permanent_shield_count"
const MIN_SHIELDS: int = 1
const MAX_SHIELDS: int = 5
const KEY_BOOST := "boost_charge_count"
const MIN_BOOST_CHARGES: int = 2
const MAX_BOOST_CHARGES: int = 5

signal permanent_shield_count_changed(new_count: int)
signal boost_charge_count_changed(new_count: int)

var _permanent_shield_count: int = MIN_SHIELDS
var _boost_charge_count: int = MIN_BOOST_CHARGES

var permanent_shield_count: int:
	get: return _permanent_shield_count

var boost_charge_count: int:
	get: return _boost_charge_count

func _ready() -> void:
	_load()

func set_permanent_shield_count(n: int) -> void:
	var clamped: int = clampi(n, MIN_SHIELDS, MAX_SHIELDS)
	if clamped == permanent_shield_count:
		return
	_permanent_shield_count = clamped
	_save()
	permanent_shield_count_changed.emit(clamped)

## Convenience for the future shield-up pickup.
## Returns true if the count was incremented, false if already at cap.
func add_permanent_shield() -> bool:
	if permanent_shield_count >= MAX_SHIELDS:
		return false
	set_permanent_shield_count(permanent_shield_count + 1)
	return true

func set_boost_charge_count(n: int) -> void:
	var clamped: int = clampi(n, MIN_BOOST_CHARGES, MAX_BOOST_CHARGES)
	if clamped == boost_charge_count:
		return
	_boost_charge_count = clamped
	_save()
	boost_charge_count_changed.emit(clamped)

## Used by ShipBoostUpPickup. Returns true if the count was incremented, false if already at cap.
func add_boost_charge() -> bool:
	if boost_charge_count >= MAX_BOOST_CHARGES:
		return false
	set_boost_charge_count(boost_charge_count + 1)
	return true

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, KEY_SHIELDS, _permanent_shield_count)
	cfg.set_value(SECTION, KEY_BOOST, _boost_charge_count)
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_error("ShipProgressionState: failed to save (%s)" % error_string(err))

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	var raw: int = int(cfg.get_value(SECTION, KEY_SHIELDS, MIN_SHIELDS))
	if raw < MIN_SHIELDS or raw > MAX_SHIELDS:
		push_warning("ShipProgressionState: saved value %d out of range [%d..%d], clamping" \
				% [raw, MIN_SHIELDS, MAX_SHIELDS])
	_permanent_shield_count = clampi(raw, MIN_SHIELDS, MAX_SHIELDS)

	var raw_boost: int = int(cfg.get_value(SECTION, KEY_BOOST, MIN_BOOST_CHARGES))
	if raw_boost < MIN_BOOST_CHARGES or raw_boost > MAX_BOOST_CHARGES:
		push_warning("ShipProgressionState: saved boost value %d out of range [%d..%d], clamping" \
				% [raw_boost, MIN_BOOST_CHARGES, MAX_BOOST_CHARGES])
	_boost_charge_count = clampi(raw_boost, MIN_BOOST_CHARGES, MAX_BOOST_CHARGES)
