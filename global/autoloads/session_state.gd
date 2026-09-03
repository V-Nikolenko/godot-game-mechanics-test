# global/autoloads/session_state.gd
extends Node

## Persists temporary pickup effects across level transitions and game restarts.
## Permanent upgrades live in ShipProgressionState / ShipModuleState.
## This store tracks short-lived (but cross-session) buffs:
##   • temporary shield charges
##   • temporary HP pool
##   • timed damage multiplier (saved as Unix expiry timestamp)
##
## Usage — called automatically by PlayerBase._setup_components():
##   SessionState.apply_to(player)

const SAVE_PATH := "user://session.cfg"
const SECTION := "session"

const _KEY_TEMP_SHIELDS      := "temp_shield_count"
const _KEY_TEMP_HP_CURRENT   := "temp_health_current"
const _KEY_TEMP_HP_STACK     := "temp_health_stack_hp"
const _KEY_DMG_EXPIRY        := "temp_damage_expiry_time"
const _KEY_DMG_BONUS         := "temp_damage_bonus"

var _temp_shield_count: int   = 0
var _temp_hp_current:   int   = 0
var _temp_hp_stack:     int   = 0
var _dmg_expiry_time:   float = 0.0  ## Unix timestamp when the damage buff expires
var _dmg_bonus:         float = 0.0


func _ready() -> void:
	_load()


## Apply all saved temporary buffs to a freshly spawned player.
## Also connects component signals so future changes are auto-saved.
func apply_to(player: PlayerBase) -> void:
	## --- Temporary shields ---
	if _temp_shield_count > 0 and player.shield_component:
		for _i in _temp_shield_count:
			player.shield_component.add_temporary()

	## --- Temporary health ---
	if _temp_hp_current > 0 and player.temp_health_component and _temp_hp_stack > 0:
		player.temp_health_component.restore(_temp_hp_current, _temp_hp_stack)

	## --- Timed damage buff ---
	var remaining: float = _dmg_expiry_time - Time.get_unix_time_from_system()
	if remaining > 0.0 and _dmg_bonus > 0.0:
		player.apply_temp_damage_buff(_dmg_bonus, remaining)
	elif _dmg_bonus > 0.0:
		## Buff expired while the game was closed — clear the stale entry.
		_dmg_bonus = 0.0
		_dmg_expiry_time = 0.0
		_save()

	## --- Wire signals so future changes are saved automatically ---
	if player.shield_component:
		player.shield_component.shield_state_changed.connect(_on_shield_state_changed)
	if player.temp_health_component:
		## Bound so the handler can read the stack size off the component that emitted,
		## rather than reconstructing it from the `maximum` in the payload.
		player.temp_health_component.amount_changed.connect(
			_on_temp_health_changed.bind(player.temp_health_component)
		)


## Called by PlayerBase.apply_temp_damage_buff when a buff is applied or refreshed.
func save_temp_damage_buff(bonus: float, expiry_unix_time: float) -> void:
	_dmg_bonus = bonus
	_dmg_expiry_time = expiry_unix_time
	_save()


## Called by PlayerBase._on_temp_damage_expired when the buff timer fires.
func clear_temp_damage_buff() -> void:
	_dmg_bonus = 0.0
	_dmg_expiry_time = 0.0
	_save()


func _on_shield_state_changed(snap: Dictionary) -> void:
	_temp_shield_count = int(snap.get("temp_count", 0))
	_save()


## `maximum` is part of TempHealth.amount_changed's declared arity and is deliberately
## unused: the stack size is read from `source` (bound at connect time in apply_to), not
## recovered as `maximum / MAX_STACKS`. That division truncated toward zero the moment
## `maximum` was not an exact multiple of MAX_STACKS, handing the player back a smaller
## pool than the one they earned.
func _on_temp_health_changed(current: int, _maximum: int, source: TempHealth) -> void:
	_temp_hp_current = current
	_temp_hp_stack = source.stack_hp
	_save()


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, _KEY_TEMP_SHIELDS,    _temp_shield_count)
	cfg.set_value(SECTION, _KEY_TEMP_HP_CURRENT, _temp_hp_current)
	cfg.set_value(SECTION, _KEY_TEMP_HP_STACK,   _temp_hp_stack)
	cfg.set_value(SECTION, _KEY_DMG_EXPIRY,      _dmg_expiry_time)
	cfg.set_value(SECTION, _KEY_DMG_BONUS,       _dmg_bonus)
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_error("SessionState: failed to save (%s)" % error_string(err))


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	_temp_shield_count = cfg.get_value(SECTION, _KEY_TEMP_SHIELDS,    0)
	_temp_hp_current   = cfg.get_value(SECTION, _KEY_TEMP_HP_CURRENT, 0)
	_temp_hp_stack     = cfg.get_value(SECTION, _KEY_TEMP_HP_STACK,   0)
	_dmg_expiry_time   = cfg.get_value(SECTION, _KEY_DMG_EXPIRY,      0.0)
	_dmg_bonus         = cfg.get_value(SECTION, _KEY_DMG_BONUS,       0.0)
