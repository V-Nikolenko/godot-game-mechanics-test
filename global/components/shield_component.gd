# global/components/shield_component.gd
## Discrete-charge shield. Each charge absorbs ONE incoming hit in full.
## Permanent charges regenerate (1 per REGEN_INTERVAL_SEC of no damage).
## Temporary charges are consumed and not refilled.
##
## Damage flow lives in PlayerBase._apply_damage:
##   if shield_component.consume_one():
##       return                            # one mistake absorbed
##   health_component.decrease(damage)
##
## UI (ShieldIconStrip) subscribes to shield_state_changed and renders icons
## from snapshot keys: perm_active, perm_max, temp_count, hacked.
class_name Shield
extends Node

@export var max_temporary: int = 5            ## hard cap on temp stack — expected to be retuned later

const REGEN_INTERVAL_SEC: float = 5.0

signal shield_state_changed(snapshot: Dictionary)
## Emitted when a pickup tries to add/restore shields but the cap was already reached.
## BubbleShield listens here to play the pickup animation even when totals don't change.
signal shield_pickup_collected

var permanent_max: int = 1       ## set in _ready from ShipProgressionState (≤ MAX_SHIELDS)
var permanent_active: int = 0    ## ≤ permanent_max
var temporary_count: int = 0     ## ≤ max_temporary
var is_hacked: bool = false

var _regen_timer: Timer = null

func _ready() -> void:
	permanent_max = ShipProgressionState.permanent_shield_count
	permanent_active = permanent_max
	ShipProgressionState.permanent_shield_count_changed.connect(_on_progression_changed)

	_regen_timer = Timer.new()
	_regen_timer.one_shot = true
	_regen_timer.wait_time = REGEN_INTERVAL_SEC
	_regen_timer.timeout.connect(_on_regen_tick)
	add_child(_regen_timer)
	_emit_snapshot()

## Pop one charge. Returns true if the hit was absorbed.
## Normal path: temporary stack first, then permanent.
## Hacked path: drains ALL charges (perm + temp) in a single call and returns true once.
##              Subsequent calls while still hacked with zero charges return false.
func consume_one() -> bool:
	if is_hacked:
		if permanent_active <= 0 and temporary_count <= 0:
			return false
		permanent_active = 0
		temporary_count = 0
		_restart_regen()
		_emit_snapshot()
		return true

	if temporary_count > 0:
		temporary_count -= 1
		_restart_regen()
		_emit_snapshot()
		return true

	if permanent_active > 0:
		permanent_active -= 1
		_restart_regen()
		_emit_snapshot()
		return true

	return false

## Push +1 onto the temp stack. Returns false if already at cap.
func add_temporary() -> bool:
	if temporary_count >= max_temporary:
		shield_pickup_collected.emit()   ## cap hit — still notify visuals
		return false
	temporary_count += 1
	_emit_snapshot()
	return true

## Refill all permanent shields (used by armor_tank pickup, future spec).
func restore_all_permanent() -> void:
	if permanent_active >= permanent_max:
		shield_pickup_collected.emit()   ## already full — still notify visuals
		return
	permanent_active = permanent_max
	_emit_snapshot()

## Drain everything. Used by ShieldOverloadModule.
func set_all_zero() -> void:
	if permanent_active == 0 and temporary_count == 0:
		return
	permanent_active = 0
	temporary_count = 0
	_restart_regen()
	_emit_snapshot()

## API hook for the future hacked-state trigger (no caller yet).
func set_hacked(value: bool) -> void:
	if is_hacked == value:
		return
	is_hacked = value
	_emit_snapshot()

func _on_progression_changed(new_max: int) -> void:
	permanent_max = new_max
	## Clamp first so a shrink (rare — debug/console only) keeps the invariant
	## permanent_active <= permanent_max.
	permanent_active = clampi(permanent_active, 0, permanent_max)
	## Auto-fill the new slot if the player has unlocked one (e.g. picked up shield_up mid-mission).
	if permanent_active < permanent_max:
		permanent_active = mini(permanent_active + 1, permanent_max)
	_emit_snapshot()

func _on_regen_tick() -> void:
	if permanent_active >= permanent_max:
		return
	permanent_active += 1
	_emit_snapshot()
	if permanent_active < permanent_max:
		_regen_timer.start()

func _restart_regen() -> void:
	if _regen_timer:
		_regen_timer.start()

func _emit_snapshot() -> void:
	var snap := {
		"perm_active": permanent_active,
		"perm_max": permanent_max,
		"temp_count": temporary_count,
		"hacked": is_hacked,
	}
	print("[Shield] %s" % str(snap))
	shield_state_changed.emit(snap)
