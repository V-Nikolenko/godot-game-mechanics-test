## Integration characterization test: the full player damage chain and the
## SessionState buff restore that runs when a player spawns.
##
## Chain order in PlayerBase._apply_damage:
##     invincible? → shield charge → temporary HP pool → Health
##
## `tests/helpers/player_stub.gd` stands in for the assault / open-space ships: a
## PlayerBase with only the components `_setup_components()` looks up by name.
## That is enough to exercise the shared base without dragging a whole mission
## scene into the suite.
extends GutTest

const SaveSandbox := preload("res://tests/helpers/save_sandbox.gd")
const PlayerStub := preload("res://tests/helpers/player_stub.gd")

var _sandbox := SaveSandbox.new()
var _saved_session: Array = []


func before_all() -> void:
	_sandbox.capture()


func after_all() -> void:
	_sandbox.restore()


func before_each() -> void:
	## SessionState is a live autoload; blank its buffs so apply_to() is a no-op
	## unless a test deliberately seeds one.
	_saved_session = [
		SessionState._temp_shield_count,
		SessionState._temp_hp_current,
		SessionState._temp_hp_stack,
		SessionState._dmg_expiry_time,
		SessionState._dmg_bonus,
	]
	_zero_session()


func after_each() -> void:
	SessionState._temp_shield_count = _saved_session[0]
	SessionState._temp_hp_current   = _saved_session[1]
	SessionState._temp_hp_stack     = _saved_session[2]
	SessionState._dmg_expiry_time   = _saved_session[3]
	SessionState._dmg_bonus         = _saved_session[4]


func _zero_session() -> void:
	SessionState._temp_shield_count = 0
	SessionState._temp_hp_current = 0
	SessionState._temp_hp_stack = 0
	SessionState._dmg_expiry_time = 0.0
	SessionState._dmg_bonus = 0.0


func _spawn_player(hp: int = 100, permanent_shields: int = 1) -> PlayerBase:
	var p: PlayerBase = PlayerStub.spawn(hp, permanent_shields)
	add_child_autofree(p)
	return p


## Damage is followed by an invincibility window; clear it so the next call in a
## test exercises the next link of the chain rather than the i-frame guard.
func _clear_invincibility(p: PlayerBase) -> void:
	p._is_invincible = false


func test_components_are_wired_up_on_spawn() -> void:
	var p := _spawn_player()
	assert_not_null(p.health_component)
	assert_not_null(p.shield_component)
	assert_not_null(p.overheat_component)
	assert_not_null(p.temp_health_component)
	assert_true(p.is_in_group("player"))


func test_multiplier_defaults() -> void:
	var p := _spawn_player()
	assert_eq(p.damage_multiplier, 1.0)
	assert_eq(p.fire_rate_multiplier, 1.0)
	assert_eq(p.damage_reduction, 0.0)
	assert_true(p.can_attack)
	assert_false(p.overdrive_active)
	assert_false(p.pierce_module_active)
	assert_eq(p.invincibility_sec, 0.5)


func test_the_shield_takes_the_first_hit() -> void:
	var p := _spawn_player(100, 1)
	p._apply_damage(40)
	assert_eq(p.shield_component.permanent_active, 0, "the charge is spent")
	assert_eq(p.health_component.current_health, 100, "no matter how big the hit")
	assert_true(p._is_invincible, "absorbing still grants i-frames")


func test_temp_hp_drains_before_health() -> void:
	var p := _spawn_player(100, 0)
	p.temp_health_component.add_stack(100)   ## +50 temp HP
	p._apply_damage(20)
	assert_eq(p.temp_health_component.current_temp, 30)
	assert_eq(p.health_component.current_health, 100, "regular health is untouched")


func test_damage_larger_than_the_temp_pool_spills_into_health() -> void:
	var p := _spawn_player(100, 0)
	p.temp_health_component.add_stack(100)   ## +50 temp HP
	p._apply_damage(80)
	assert_eq(p.temp_health_component.current_temp, 0)
	assert_eq(p.health_component.current_health, 70, "50 absorbed, 30 through to health")


func test_damage_reaches_health_once_shield_and_temp_pool_are_gone() -> void:
	var p := _spawn_player(100, 0)
	p._apply_damage(25)
	assert_eq(p.health_component.current_health, 75)


func test_invincibility_swallows_a_simultaneous_second_projectile() -> void:
	var p := _spawn_player(100, 0)
	p._apply_damage(25)
	p._apply_damage(25)
	assert_eq(p.health_component.current_health, 75, "the burst counts as one hit")
	_clear_invincibility(p)
	p._apply_damage(25)
	assert_eq(p.health_component.current_health, 50, "and lands again once the window ends")


func test_damage_reduction_only_applies_to_health_damage() -> void:
	var p := _spawn_player(100, 1)
	p.damage_reduction = 0.5
	p._apply_damage(40)
	assert_eq(p.shield_component.permanent_active, 0)
	assert_eq(p.health_component.current_health, 100, "shields are binary, reduction is moot")
	_clear_invincibility(p)
	p._apply_damage(40)
	assert_eq(p.health_component.current_health, 80, "now the 50% reduction bites: 40 -> 20")


func test_health_changes_are_broadcast_on_the_event_bus() -> void:
	var p := _spawn_player(80, 0)
	var seen: Array = []
	var cb := func(current: int, maximum: int) -> void: seen.append([current, maximum])
	EventBus.player_health_changed.connect(cb)
	p._apply_damage(30)
	EventBus.player_health_changed.disconnect(cb)
	assert_eq(seen, [[50, 80]])


func test_a_temp_damage_buff_stacks_on_the_baseline_and_is_persisted() -> void:
	var p := _spawn_player()
	p.apply_temp_damage_buff(0.5, 60.0)
	assert_almost_eq(p.damage_multiplier, 1.5, 0.0001)
	assert_almost_eq(SessionState._dmg_bonus, 0.5, 0.0001)
	assert_gt(SessionState._dmg_expiry_time, Time.get_unix_time_from_system())


func test_reapplying_a_buff_does_not_compound_it() -> void:
	var p := _spawn_player()
	p.apply_temp_damage_buff(0.5, 60.0)
	p.apply_temp_damage_buff(0.5, 60.0)
	assert_almost_eq(p.damage_multiplier, 1.5, 0.0001, "refreshing re-bases instead of stacking")


func test_buff_expiry_restores_the_exact_baseline_and_clears_the_save() -> void:
	var p := _spawn_player()
	p.apply_temp_damage_buff(0.75, 60.0)
	p._on_temp_damage_expired()
	assert_almost_eq(p.damage_multiplier, 1.0, 0.0001)
	assert_eq(SessionState._dmg_bonus, 0.0)
	assert_eq(SessionState._dmg_expiry_time, 0.0)


func test_saved_temporary_shields_are_restored_on_spawn() -> void:
	SessionState._temp_shield_count = 2
	var p := _spawn_player(100, 1)
	assert_eq(p.shield_component.temporary_count, 2, "temp charges survive a level transition")
	assert_eq(p.shield_component.permanent_active, 1)


func test_saved_temp_hp_is_restored_on_spawn() -> void:
	SessionState._temp_hp_current = 30
	SessionState._temp_hp_stack = 10
	var p := _spawn_player()
	assert_eq(p.temp_health_component.current_temp, 30)
	assert_eq(p.temp_health_component.max_temp, 50)


func test_an_expired_damage_buff_is_dropped_rather_than_reapplied() -> void:
	SessionState._dmg_bonus = 0.5
	SessionState._dmg_expiry_time = Time.get_unix_time_from_system() - 100.0
	var p := _spawn_player()
	assert_almost_eq(p.damage_multiplier, 1.0, 0.0001, "a buff that lapsed while closed is void")
	assert_eq(SessionState._dmg_bonus, 0.0, "and the stale entry is cleared")


func test_a_still_running_damage_buff_is_reapplied_on_spawn() -> void:
	SessionState._dmg_bonus = 0.5
	SessionState._dmg_expiry_time = Time.get_unix_time_from_system() + 120.0
	var p := _spawn_player()
	assert_almost_eq(p.damage_multiplier, 1.5, 0.0001, "the remaining buff time carries over")


func test_shield_changes_after_spawn_are_written_back_to_session_state() -> void:
	var p := _spawn_player(100, 1)
	p.shield_component.add_temporary()
	p.shield_component.add_temporary()
	assert_eq(SessionState._temp_shield_count, 2, "apply_to() subscribed to the shield")
	p._apply_damage(10)                  ## spends one temporary charge
	assert_eq(SessionState._temp_shield_count, 1)
