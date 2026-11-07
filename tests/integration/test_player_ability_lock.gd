## INTENT tests for Phase 9 plan §2.1 / §2.2 (docs/plans/cmug23onr001pm52w9swwophy/3-plan.md; task plan
## docs/plans/cmw5k4yjg009qqs2xbibatkiy/3-plan.md): the player-side ability lock.
##
## Inside a lit jammer field (a hazard with `disables_abilities`, sampled by the body through `Hazards.jammer_at()`) and
## for a timed lock (`apply_ability_lock(seconds, source)`), every H press (`try_activate()` of each ship module) and the
## K rocket launch are refused with nothing spent. The lock ends `stabilise_seconds` after the ship leaves the field (a
## timed lock ends with no delay). Movement, Shift boost, dash, warp, primary fire, `switch_weapon` and module cooldowns
## never change. Every lock clock follows the 1e-6 rule, so a lock of `s` seconds at 1/60 ends on tick `round(s * 60)`.
##
## Both real players (`player_ship.tscn`, `player_fighter.tscn`), each in its own `box` (module rings, warp ghosts and
## overlays land in the ship's parent), with their own `_physics_process` off and every step hand-ticked at 60 Hz, the
## shape of `test_player_boost_disruption.gd`. The jammer is a plain `HazardField` built from props before it enters the
## tree; no jammer enemy exists yet.
##
## H presses go through `Viewport.push_input()`, the engine's own dispatch to every `_input` in the tree, so only one
## player may be in the tree when one is pushed (asserted). K presses call `RocketState._on_action()` directly: the
## `MovementController` reads `Input` in `_process` and would need real frames.
##
## The two lockstep rows (primary fire, movement) start with one awaited idle frame and nothing else awaits. Within one
## process frame `Input.is_action_just_pressed` / `just_released` stay true on every tick once set (Godot 4.6's non-legacy
## semantics), and inside a physics frame a fresh `action_press()` is not "just pressed" at all, so the rows run in idle
## context and step ship A and ship B in lockstep, one tick of each per loop iteration. The sniper therefore re-arms on
## every tick; only A == B is asserted, never a sniper count or timing. `move_and_slide()` off a physics frame moves by the
## real frame delta, so the movement row asserts no distance, only A == B and the velocities each verb sets (which use
## the fixed D). The control ship sees the SAME registered field,
## out of reach, so both runs take identical `Hazards.count() > 0` paths and any difference can only come from the lock.
extends GutTest

const SHIP_SCENE: PackedScene = preload("res://open_space/scenes/entities/player/player_ship.tscn")
const FIGHTER_SCENE: PackedScene = preload("res://assault/scenes/player/player_fighter.tscn")
const SaveSandbox := preload("res://tests/helpers/save_sandbox.gd")

const D: float = 1.0 / 60.0
const MODES: Array = ["open_space", "assault"]
const START: Vector2 = Vector2(640, 360)
## The jammer used everywhere: the plan §2.2 fixture.
const R: float = 240.0
const STAB: float = 0.75
## Moves a ship from a field's centre to 60 px outside its edge (inside the Assault bounds from START).
const OUT: Vector2 = Vector2(R + 60.0, 0.0)
const FAR: Vector2 = Vector2(5000, 5000)

## Every module whose script overrides `try_activate()`, with a readable "spent" probe in `_spent()`.
const _SPENT_IDS: Array[StringName] = [&"trajectory_calc", &"emp_blast", &"ai_targeting", &"cockpit_heal", &"parry",
	&"shield_overload", &"final_resort", &"plasma_nova", &"overheat_nullifier", &"engine_boost"]

var _sandbox := SaveSandbox.new()
var _saved_equipped: Dictionary = {}
var _saved_unlocked: Dictionary = {}


func before_all() -> void:
	_sandbox.capture()
	for slot: StringName in ShipModuleState.SLOTS:
		_saved_equipped[slot] = ShipModuleState.get_equipped(slot)
		_saved_unlocked[slot] = (ShipModuleState._unlocked[slot] as Array).duplicate()


func after_all() -> void:
	for slot: StringName in ShipModuleState.SLOTS:
		ShipModuleState._equipped[slot] = _saved_equipped[slot]
		ShipModuleState._unlocked[slot] = _saved_unlocked[slot]
	_sandbox.restore()


func before_each() -> void:
	for slot: StringName in ShipModuleState.SLOTS:
		ShipModuleState._equipped[slot] = &""


func after_each() -> void:
	for action: StringName in [&"shoot", &"move_up", &"move_left", &"move_right", &"boost"]:
		Input.action_release(action)
	DialogPlayer.is_active = false
	Engine.time_scale = 1.0
	randomize()


# --- Helpers ----------------------------------------------------------------------------------------------------------


## A real player in its own autofreed `box`, physics off, at [param at], facing up and still.
func _player(mode: String, at: Vector2 = START) -> PlayerBase:
	var box := Node2D.new()
	add_child_autofree(box)
	var p := (SHIP_SCENE if mode == "open_space" else FIGHTER_SCENE).instantiate() as PlayerBase
	box.add_child(p)
	p.set_physics_process(false)
	p.global_position = at
	p.rotation = 0.0
	p.velocity = Vector2.ZERO
	return p


## Frees a player's box (and everything a module spawned into it) now, so the next player is alone in the tree.
func _free_box(p: PlayerBase) -> void:
	var box := p.get_parent()
	box.get_parent().remove_child(box)
	box.free()


## The plan §2.2 jammer: a plain lit `HazardField`, built from props BEFORE it enters the tree. Parented to
## [param parent] when given (freed with it), else autofreed.
func _jammer(at: Vector2, props: Dictionary = {}, parent: Node = null) -> HazardField:
	var f := HazardField.new()
	f.kind = &"jammer"
	f.radius = R
	f.avoid_weight = 0.0
	f.disables_abilities = true
	f.stabilise_seconds = STAB
	for key in props:
		f.set(key, props[key])
	f.position = at
	if parent != null:
		parent.add_child(f)
	else:
		add_child_autofree(f)
	return f


## A lit field on the ship, sampled once: locked. The field lives in the ship's box.
func _lock(p: PlayerBase) -> HazardField:
	var f := _jammer(p.global_position, {}, p.get_parent())
	p._step_disruption(D)
	assert_true(p.abilities_locked(), "precondition: locked in a lit field")
	return f


func _tick(p: PlayerBase, ticks: int) -> void:
	for i in range(ticks):
		p._step_disruption(D)


## Moves the ship out of the field and ticks the exit tick T plus the 45 ticks of the 0.75 s delay: unlocked at T+45.
func _leave_and_unlock(p: PlayerBase) -> void:
	p.global_position += OUT
	_tick(p, 1 + 45)
	assert_false(p.abilities_locked(), "precondition: unlocked 45 ticks after the exit tick")


## Records every `ability_lock_changed` value.
func _lock_log(p: PlayerBase) -> Array:
	var got: Array = []
	p.ability_lock_changed.connect(func(locked: bool) -> void: got.append(locked))
	return got


## Records every `ability_press_refused` (one `true` per refusal).
func _refusal_log(p: PlayerBase) -> Array:
	var got: Array = []
	p.ability_press_refused.connect(func() -> void: got.append(true))
	return got


## Pushes one H press through the engine's own input dispatch and returns whether anything consumed it.
func _push_h() -> bool:
	assert_eq(get_tree().get_nodes_in_group(&"player").size(), 1, "precondition: exactly one player gets the push")
	var ev := InputEventAction.new()
	ev.action = &"use_ability"
	ev.pressed = true
	get_viewport().push_input(ev)
	return get_viewport().is_input_handled()


## Puts module [param id] on the ship exactly where both H loops look for it.
func _equip_module(p: PlayerBase, id: StringName) -> ShipModuleBase:
	var mod := ShipModuleBase.create(id)
	mod.apply(p)
	p._module_pool[id] = mod
	return mod


## True once module [param id] has spent its activation (a cooldown, a running effect, a used resource).
func _spent(id: StringName, mod: ShipModuleBase, p: PlayerBase) -> bool:
	match id:
		&"trajectory_calc", &"final_resort":
			return bool(mod.get(&"_active"))
		&"emp_blast", &"plasma_nova", &"overheat_nullifier", &"ai_targeting":
			return float(mod.get(&"_cooldown_left")) > 0.0
		&"parry":
			return bool(mod.get(&"_active")) or float(mod.get(&"_cooldown_left")) > 0.0
		&"cockpit_heal":
			return float(mod.get(&"_passive_lockout")) > 0.0
		&"shield_overload":
			return p.shield_component.temporary_count == 0
		&"engine_boost":
			return p.engine_boost_active
	return false


func _rocket_state(p: PlayerBase) -> RocketState:
	return p.get_node("AttackStateMachine/WarheadMissileShootingState") as RocketState


func _weapon_state(p: PlayerBase) -> WeaponState:
	return p.get_node("AttackStateMachine/WeaponState") as WeaponState


## A target the beam can find (group `enemies`, a child `HurtBox`), logging every damage it receives into [param rec].
func _dummy(parent: Node, at: Vector2, rec: Array, clock: Array) -> Node2D:
	var dummy := Node2D.new()
	var hb := HurtBox.new()
	hb.name = "HurtBox"
	hb.received_damage.connect(func(d: int) -> void: rec.append(["hit", clock[0], d]))
	dummy.add_child(hb)
	dummy.add_to_group(&"enemies")
	parent.add_child(dummy)
	dummy.global_position = at
	return dummy


# --- The API ----------------------------------------------------------------------------------------------------------


func test_the_signals_are_declared_with_their_arity(mode: String = use_parameters(MODES)) -> void:
	var p := _player(mode)
	var found: Dictionary = {}
	for s: Dictionary in p.get_signal_list():
		found[s.name] = s.args
	assert_true(found.has("ability_lock_changed"), "%s: ability_lock_changed is declared" % mode)
	assert_true(found.has("ability_press_refused"), "%s: ability_press_refused is declared" % mode)
	if found.has("ability_lock_changed"):
		var args: Array = found["ability_lock_changed"]
		assert_eq(args.size(), 1, "%s: ability_lock_changed(locked: bool) declares one argument" % mode)
		if args.size() == 1:
			assert_eq(int(args[0].type), TYPE_BOOL, "%s: and it is a bool" % mode)
	if found.has("ability_press_refused"):
		assert_eq((found["ability_press_refused"] as Array).size(), 0, "%s: ability_press_refused() has none" % mode)


# --- Field timing (both ships, driven through `_step_disruption(D)`) --------------------------------------------------


func test_locked_on_the_first_tick_inside(mode: String = use_parameters(MODES)) -> void:
	var p := _player(mode)
	var got := _lock_log(p)
	var f := _jammer(p.global_position + Vector2(R + 1.0, 0.0))
	_tick(p, 1)
	assert_false(p.abilities_locked(), "%s: 1 px outside the radius: unlocked" % mode)
	assert_eq(p.ability_lock_fill(), 0.0, "%s: fill 0 unlocked" % mode)
	f.position = p.global_position + Vector2(R, 0.0)
	assert_false(p.abilities_locked(), "%s: the field is sampled by the tick, not on its arrival" % mode)
	_tick(p, 1)
	assert_true(p.abilities_locked(), "%s: exactly at the radius the first tick locks" % mode)
	assert_eq(p.ability_lock_fill(), 1.0, "%s: fill 1 while in a field" % mode)
	assert_eq(got, [true], "%s: ability_lock_changed(true) exactly once" % mode)
	_tick(p, 30)
	assert_eq(got, [true], "%s: and never again while inside" % mode)


func test_unlocks_exactly_45_ticks_after_the_exit_tick(mode: String = use_parameters(MODES)) -> void:
	var p := _player(mode)
	var got := _lock_log(p)
	_lock(p)
	p.global_position += OUT
	_tick(p, 1)  # the exit tick T
	assert_true(p.abilities_locked(), "%s: locked on the exit tick" % mode)
	assert_eq(p.ability_lock_fill(), 1.0, "%s: the delay starts full" % mode)
	var prev: float = p.ability_lock_fill()
	var monotone := true
	for k in range(1, 45):
		_tick(p, 1)
		assert_true(p.abilities_locked(), "%s: still locked at T+%d" % [mode, k])
		monotone = monotone and p.ability_lock_fill() < prev and p.ability_lock_fill() > 0.0
		prev = p.ability_lock_fill()
	assert_true(monotone, "%s: fill falls strictly every tick from T to T+44" % mode)
	_tick(p, 1)
	assert_false(p.abilities_locked(), "%s: unlocked at T+45 (0.75 s after the exit tick)" % mode)
	assert_eq(p.ability_lock_fill(), 0.0, "%s: fill 0 once unlocked" % mode)
	assert_eq(got, [true, false], "%s: one true, one false" % mode)


func test_re_entry_restarts_the_delay(mode: String = use_parameters(MODES)) -> void:
	var p := _player(mode)
	var got := _lock_log(p)
	var f := _lock(p)
	p.global_position += OUT
	_tick(p, 20)  # T .. T+19
	assert_lt(p.ability_lock_fill(), 1.0, "%s: precondition: stabilising" % mode)
	p.global_position = f.position
	_tick(p, 1)  # T+20: back inside
	assert_true(p.abilities_locked(), "%s: locked again inside" % mode)
	assert_eq(p.ability_lock_fill(), 1.0, "%s: fill back to 1.0" % mode)
	_tick(p, 10)
	p.global_position += OUT
	_tick(p, 1)  # T2
	_tick(p, 44)
	assert_true(p.abilities_locked(), "%s: locked at T2+44: the full delay restarted" % mode)
	_tick(p, 1)
	assert_false(p.abilities_locked(), "%s: unlocked at T2+45" % mode)
	assert_eq(got, [true, false], "%s: re-entry during the delay is no new edge" % mode)


func test_leaving_the_inner_of_two_fields_starts_no_delay(mode: String = use_parameters(MODES)) -> void:
	var p := _player(mode)
	var got := _lock_log(p)
	_jammer(p.global_position)
	_jammer(p.global_position + Vector2(0.0, -200.0), {radius = 60.0, stabilise_seconds = 1.25})
	p.global_position += Vector2(0.0, -200.0)
	_tick(p, 1)
	assert_true(p.abilities_locked(), "%s: inside both" % mode)
	p.global_position = START + Vector2(0.0, -100.0)  # inside the outer only
	_tick(p, 10)
	assert_eq(p.ability_lock_fill(), 1.0, "%s: still in a field, so no stabilisation fraction" % mode)
	p.global_position = START + OUT
	_tick(p, 1)  # the exit tick T
	_tick(p, 44)
	assert_true(p.abilities_locked(), "%s: locked at T+44" % mode)
	_tick(p, 1)
	assert_false(p.abilities_locked(), "%s: unlocked at T+45: the outer field's 0.75 s, not the inner's 1.25 s" % mode)
	assert_eq(got, [true, false], "%s" % mode)


func test_a_pulsed_field_locks_only_while_active(mode: String = use_parameters(MODES)) -> void:
	var p := _player(mode)
	var got := _lock_log(p)
	var f := _jammer(p.global_position, {cycle_telegraph = 1.0, cycle_active = 2.0, cycle_quiet = 1.0})
	var guard := 0
	var telegraph_locked := false
	while f.phase() == HazardField.Phase.TELEGRAPH and guard < 200:
		p._step_disruption(D)
		telegraph_locked = telegraph_locked or p.abilities_locked()
		f._physics_process(D)
		guard += 1
	assert_false(telegraph_locked, "%s: never locked while the field telegraphs" % mode)
	assert_eq(f.phase(), HazardField.Phase.ACTIVE, "%s: precondition: the field lit" % mode)
	p._step_disruption(D)
	assert_true(p.abilities_locked(), "%s: locked on the first tick the field is ACTIVE" % mode)
	guard = 0
	while f.phase() == HazardField.Phase.ACTIVE and guard < 200:
		f._physics_process(D)
		if f.phase() == HazardField.Phase.ACTIVE:
			p._step_disruption(D)
		guard += 1
	assert_eq(f.phase(), HazardField.Phase.QUIET, "%s: precondition: the field went quiet" % mode)
	p._step_disruption(D)  # Q: the first tick sampled in QUIET is the exit tick
	assert_true(p.abilities_locked(), "%s: locked on the ACTIVE -> QUIET edge" % mode)
	for k in range(1, 45):
		f._physics_process(D)
		p._step_disruption(D)
	assert_true(p.abilities_locked(), "%s: locked at Q+44" % mode)
	f._physics_process(D)
	p._step_disruption(D)
	assert_eq(f.phase(), HazardField.Phase.QUIET, "%s: precondition: still quiet" % mode)
	assert_false(p.abilities_locked(), "%s: unlocked at Q+45" % mode)
	assert_eq(got, [true, false], "%s" % mode)


func test_a_freed_field_starts_the_delay(mode: String = use_parameters(MODES)) -> void:
	var p := _player(mode)
	var got := _lock_log(p)
	var f := _jammer(p.global_position)
	_tick(p, 1)
	assert_true(p.abilities_locked(), "%s: precondition: locked" % mode)
	remove_child(f)
	f.free()
	assert_eq(Hazards.count(), 0, "%s: the freed field unregistered" % mode)
	_tick(p, 1)  # the exit tick
	_tick(p, 44)
	assert_true(p.abilities_locked(), "%s: locked through exit + 44" % mode)
	_tick(p, 1)
	assert_false(p.abilities_locked(), "%s: unlocked at exit + 45" % mode)
	assert_eq(got, [true, false], "%s" % mode)


# --- Timed locks ------------------------------------------------------------------------------------------------------


func test_a_timed_lock_ends_on_tick_90_with_no_stabilisation(mode: String = use_parameters(MODES)) -> void:
	var p := _player(mode)
	var got := _lock_log(p)
	p.apply_ability_lock(1.5, null)
	assert_eq(got, [true], "%s: announced at the call" % mode)
	assert_true(p.abilities_locked(), "%s: locked at once" % mode)
	var all_locked := true
	var all_full := true
	for i in range(1, 90):
		_tick(p, 1)
		all_locked = all_locked and p.abilities_locked()
		all_full = all_full and p.ability_lock_fill() == 1.0
	assert_true(all_locked, "%s: locked after ticks 1 .. 89" % mode)
	assert_true(all_full, "%s: fill 1.0 throughout, never a stabilisation fraction" % mode)
	_tick(p, 1)
	assert_false(p.abilities_locked(), "%s: unlocked after tick 90 exactly (1.5 s, the 1e-6 rule)" % mode)
	assert_eq(p.ability_lock_fill(), 0.0, "%s: and no stabilisation delay follows" % mode)
	assert_eq(got, [true, false], "%s" % mode)


func test_timed_locks_longest_wins_and_never_add(mode: String = use_parameters(MODES)) -> void:
	var p := _player(mode)
	var got := _lock_log(p)
	p.apply_ability_lock(1.5, null)
	_tick(p, 30)
	p.apply_ability_lock(0.5, null)
	_tick(p, 59)  # tick 89
	assert_true(p.abilities_locked(), "%s: a shorter second lock does not shorten the first" % mode)
	_tick(p, 1)  # tick 90
	assert_false(p.abilities_locked(), "%s: the 1.5 s lock ends on tick 90" % mode)
	assert_eq(got, [true, false], "%s: a refresh is no edge" % mode)

	var q := _player(mode)
	var got_q := _lock_log(q)
	q.apply_ability_lock(1.0, null)
	_tick(q, 30)
	q.apply_ability_lock(2.0, null)
	_tick(q, 30)  # tick 60
	assert_true(q.abilities_locked(), "%s: a longer second lock extends past the first's tick 60" % mode)
	_tick(q, 89)  # tick 149
	assert_true(q.abilities_locked(), "%s: still locked at tick 149" % mode)
	_tick(q, 1)  # tick 150
	assert_false(q.abilities_locked(), "%s: unlocked on tick 150 (2.0 s from tick 30), not 180 (never added)" % mode)
	assert_eq(got_q, [true, false], "%s" % mode)


func test_zero_or_negative_seconds_is_no_lock(mode: String = use_parameters(MODES)) -> void:
	var p := _player(mode)
	var got := _lock_log(p)
	p.apply_ability_lock(0.0, null)
	p.apply_ability_lock(-1.0, null)
	assert_false(p.abilities_locked(), "%s" % mode)
	_tick(p, 1)
	assert_false(p.abilities_locked(), "%s" % mode)
	assert_eq(got, [], "%s: nothing announced" % mode)


func test_a_field_and_a_timed_lock_never_shorten_each_other(mode: String = use_parameters(MODES)) -> void:
	var p := _player(mode)
	var got := _lock_log(p)
	var f := _jammer(p.global_position)
	p.apply_ability_lock(1.5, null)
	_tick(p, 29)
	p.global_position += OUT
	_tick(p, 1)  # tick 30 is the exit tick; its delay ends on tick 75
	_tick(p, 59)  # tick 89
	assert_true(p.abilities_locked(), "%s: the timed lock outlasts the field's delay (not unlocked at 75)" % mode)
	_tick(p, 1)  # tick 90
	assert_false(p.abilities_locked(), "%s: unlocked on tick 90" % mode)
	assert_eq(got, [true, false], "%s" % mode)

	var q := _player(mode, START + Vector2(0, 400))
	var got_q := _lock_log(q)
	f.position = q.global_position
	q.apply_ability_lock(0.5, null)
	_tick(q, 19)
	q.global_position += OUT
	_tick(q, 1)  # tick 20 is the exit tick; its delay ends on tick 65
	_tick(q, 44)  # tick 64 (the timed lock ended on tick 30)
	assert_true(q.abilities_locked(), "%s: the field's delay outlasts the timed lock (not unlocked at 30)" % mode)
	_tick(q, 1)  # tick 65
	assert_false(q.abilities_locked(), "%s: unlocked on tick 65" % mode)
	assert_eq(got_q, [true, false], "%s" % mode)


## BOUNDARY: the 1e-6 clock rule. Without the epsilon the residual of 90 steps of 1/60 from 1.5 is positive and the lock
## would end on tick 91.
func test_tick_clock_reaches_exactly_zero_on_tick_90() -> void:
	var x: float = 1.5
	for i in 90:
		x = PlayerBase._tick_clock(x, D)
	assert_eq(x, 0.0, "1.5 s, 90 steps: exactly 0.0")
	var y: float = 2.0
	for i in 120:
		y = PlayerBase._tick_clock(y, D)
	assert_eq(y, 0.0, "2.0 s, 120 steps: exactly 0.0")
	var z: float = 1.5
	for i in 89:
		z = PlayerBase._tick_clock(z, D)
	assert_gt(z, 0.0, "still running after 89 steps")
	var plain: float = 1.5
	for i in 90:
		plain -= D
	assert_gt(plain, 0.0, "control: plain subtraction leaves a positive residual (the premise of the epsilon)")


# --- The clock is wired into each ship's own physics tick (anti-inert) ------------------------------------------------
# Every timing row above steps `_step_disruption()` by hand, so all of them stay green on a build whose ships never call
# the lock's step. This one drives only the ship's own `_physics_process`.


func test_the_ships_own_physics_tick_steps_the_lock(mode: String = use_parameters(MODES)) -> void:
	var p := _player(mode)
	_jammer(p.global_position)
	p._physics_process(D)
	assert_true(p.abilities_locked(), "%s: the ship's own tick sampled the field" % mode)
	p.global_position += OUT
	p._physics_process(D)  # the exit tick
	for i in 44:
		p._physics_process(D)
	assert_true(p.abilities_locked(), "%s: locked at T+44" % mode)
	p._physics_process(D)
	assert_false(p.abilities_locked(), "%s: unlocked at T+45 through the ship's own tick" % mode)


func test_assault_lock_clock_runs_through_a_dialog() -> void:
	var f := _player("assault")
	DialogPlayer.is_active = true
	f.apply_ability_lock(0.1, null)
	for i in 6:
		f._physics_process(D)
	assert_false(f.abilities_locked(), "the dialog's early return comes after the lock's clock")


# --- H: every active module refused with nothing spent ----------------------------------------------------------------


func test_every_active_module_is_in_the_spend_table() -> void:
	var active: Array = []
	for slot: StringName in ShipModuleState.SLOT_MODULES:
		for id: StringName in ShipModuleState.SLOT_MODULES[slot]:
			if id == &"":
				continue
			var mod := ShipModuleBase.create(id)
			var path: String = (mod.get_script() as Script).resource_path
			if FileAccess.get_file_as_string(path).contains("func try_activate("):
				active.append(String(id))
	active.sort()
	var table: Array = []
	for id: StringName in _SPENT_IDS:
		table.append(String(id))
	table.sort()
	assert_eq(active, table, "every module that overrides try_activate() has a spend probe here")


func test_h_is_refused_while_locked_with_nothing_spent_for_every_module(mode: String = use_parameters(MODES)) -> void:
	for id: StringName in _SPENT_IDS:
		var p := _player(mode)
		var mod := _equip_module(p, id)
		var refusals := _refusal_log(p)
		if id == &"ai_targeting":
			var target := Node2D.new()
			target.add_to_group(&"enemies")
			p.get_parent().add_child(target)
			target.global_position = p.global_position + Vector2(0, -300)
		if id == &"shield_overload":
			p.shield_component.add_temporary()
		_lock(p)
		var h_skipped: bool = mode == "open_space" and mod.is_open_space_boost_verb()
		assert_true(_push_h(), "%s %s: a locked press is consumed" % [mode, id])
		assert_false(_spent(id, mod, p), "%s %s: and spends nothing" % [mode, id])
		assert_eq(refusals.size(), 1, "%s %s: one ability_press_refused" % [mode, id])
		_leave_and_unlock(p)
		assert_false(p.abilities_locked(), "%s %s: precondition: unlocked" % [mode, id])
		if id != &"ai_targeting":
			assert_true(get_tree().get_nodes_in_group(&"enemies").is_empty(),
					"%s %s: precondition: no enemy for an area effect to touch" % [mode, id])
		var root_before: Array = get_tree().root.get_children()
		var handled := _push_h()
		if h_skipped:
			assert_false(handled, "%s %s: unlocked, H still never fires the Boost Drive (unchanged)" % [mode, id])
			assert_false(_spent(id, mod, p), "%s %s: and spends nothing" % [mode, id])
		else:
			assert_true(handled, "%s %s: unlocked, the same press is consumed" % [mode, id])
			assert_true(_spent(id, mod, p), "%s %s: and activates the module" % [mode, id])
		assert_eq(refusals.size(), 1, "%s %s: no refusal once unlocked" % [mode, id])
		mod.remove(p)
		for node: Node in get_tree().root.get_children():
			if not root_before.has(node):
				node.get_parent().remove_child(node)
				node.free()
		_free_box(p)
		Engine.time_scale = 1.0


func test_h_boundary_refused_on_t44_accepted_on_t45(mode: String = use_parameters(MODES)) -> void:
	var p := _player(mode)
	var mod := _equip_module(p, &"emp_blast")
	var refusals := _refusal_log(p)
	_lock(p)
	p.global_position += OUT
	_tick(p, 1)  # T
	_tick(p, 44)
	assert_true(get_tree().get_nodes_in_group(&"enemies").is_empty(), "%s: precondition: no enemies" % mode)
	_push_h()
	assert_eq(float(mod.get(&"_cooldown_left")), 0.0, "%s: refused at T+44, nothing spent" % mode)
	assert_eq(refusals.size(), 1, "%s: one refusal at T+44" % mode)
	_tick(p, 1)
	assert_true(_push_h(), "%s: accepted at T+45" % mode)
	assert_eq(float(mod.get(&"_cooldown_left")), 15.0, "%s: EMP Blast's 15 s cooldown started" % mode)
	assert_eq(refusals.size(), 1, "%s: no refusal at T+45" % mode)


func test_a_locked_press_with_no_active_module_is_still_handled(mode: String = use_parameters(MODES)) -> void:
	var p := _player(mode)
	var refusals := _refusal_log(p)
	_lock(p)
	assert_true(_push_h(), "%s: locked, the press is consumed" % mode)
	assert_eq(refusals.size(), 1, "%s: and refused" % mode)
	_free_box(p)
	var q := _player(mode)
	var q_refusals := _refusal_log(q)
	assert_false(_push_h(), "%s: control: unlocked with nothing to fire, the press is not consumed" % mode)
	assert_eq(q_refusals.size(), 0, "%s: and nothing is refused" % mode)


func test_assault_a_locked_press_during_a_dialog_is_ignored() -> void:
	var f := _player("assault")
	var mod := _equip_module(f, &"emp_blast")
	var refusals := _refusal_log(f)
	_lock(f)
	DialogPlayer.is_active = true
	assert_false(_push_h(), "a dialog's return comes first: the press is neither consumed")
	assert_eq(refusals.size(), 0, "nor refused")
	assert_eq(float(mod.get(&"_cooldown_left")), 0.0, "nor spent")


func test_module_cooldowns_keep_ticking_while_locked(mode: String = use_parameters(MODES)) -> void:
	var p := _player(mode)
	var mod := _equip_module(p, &"emp_blast")
	mod.set(&"_cooldown_left", 10.0)
	p.apply_ability_lock(3.0, null)
	for i in 179:
		p._physics_process(D)
	assert_true(p.abilities_locked(), "%s: locked after tick 179" % mode)
	p._physics_process(D)
	assert_false(p.abilities_locked(), "%s: unlocked after tick 180" % mode)
	assert_almost_eq(float(mod.get(&"_cooldown_left")), 7.0, 1e-6,
			"%s: 3 s of the cooldown ran while locked, so the lock cost no time" % mode)


# --- K: both rocket types ---------------------------------------------------------------------------------------------


func test_k_is_refused_while_locked_for_both_rocket_types(mode: String = use_parameters(MODES)) -> void:
	for kind: int in [0, 1]:
		var p := _player(mode)
		var rs := _rocket_state(p)
		rs.select_sub_weapon(kind)
		var refusals := _refusal_log(p)
		_lock(p)
		var children: int = rs.get_child_count()
		assert_true(rs.cooldown_timer.is_stopped(), "%s kind %d: precondition: no cooldown running" % [mode, kind])
		rs._on_action("special_weapon")
		assert_true(rs.cooldown_timer.is_stopped(), "%s kind %d: no CooldownTimer started" % [mode, kind])
		assert_eq(rs.get_child_count(), children, "%s kind %d: no rocket launched" % [mode, kind])
		assert_eq(refusals.size(), 1, "%s kind %d: one refusal" % [mode, kind])
		_leave_and_unlock(p)
		rs._on_action("special_weapon")
		assert_eq(rs.get_child_count(), children + 3, "%s kind %d: unlocked, the same press launches 3" % [mode, kind])
		assert_false(rs.cooldown_timer.is_stopped(), "%s kind %d: and starts the cooldown" % [mode, kind])
		assert_eq(refusals.size(), 1, "%s kind %d: no refusal once unlocked" % [mode, kind])


func test_k_during_the_cooldown_is_not_a_refusal(mode: String = use_parameters(MODES)) -> void:
	var p := _player(mode)
	var rs := _rocket_state(p)
	var refusals := _refusal_log(p)
	rs._on_action("special_weapon")
	var children: int = rs.get_child_count()
	assert_false(rs.cooldown_timer.is_stopped(), "%s: precondition: cooling down" % mode)
	rs._on_action("special_weapon")
	assert_eq(rs.get_child_count(), children, "%s: no launch during the cooldown" % mode)
	assert_eq(refusals.size(), 0, "%s: and no refusal (the cooldown is no lock)" % mode)
	_lock(p)
	rs._on_action("special_weapon")
	assert_eq(rs.get_child_count(), children, "%s: locked and cooling down: no launch" % mode)
	assert_eq(refusals.size(), 0, "%s: still no refusal: the cooldown is checked first" % mode)


func test_switch_weapon_still_switches_while_locked(mode: String = use_parameters(MODES)) -> void:
	var p := _player(mode)
	var rs := _rocket_state(p)
	var refusals := _refusal_log(p)
	var changed: Array = []
	rs.weapon_changed.connect(func(icon: Texture2D) -> void: changed.append(icon))
	_lock(p)
	var before: int = rs.get_type()
	rs._on_action("switch_weapon")
	assert_eq(rs.get_type(), 1 - before, "%s: switched" % mode)
	assert_eq(changed.size(), 1, "%s: weapon_changed once" % mode)
	assert_eq(refusals.size(), 0, "%s: switch_weapon is never refused" % mode)


# --- Never affected: primary fire and movement (lockstep, idle context) -----------------------------------------------


func test_primary_fire_is_identical_inside_a_lit_field(mode: String = use_parameters(MODES)) -> void:
	await get_tree().process_frame  # idle context for Input's just-pressed edges: see the header
	for id: StringName in UpgradeState.ALL_IDS:
		var a := _player(mode, START)
		var b := _player(mode, START + Vector2(1200, 0))
		_jammer(b.global_position, {}, b.get_parent())
		var clock: Array = [0]
		var logs: Array = [[], []]
		var states: Array = []
		for i in 2:
			var p: PlayerBase = [a, b][i]
			var ws := _weapon_state(p)
			ws._active_id = id
			states.append(ws)
			var rec: Array = logs[i]
			ws.child_entered_tree.connect(func(n: Node) -> void:
				var bullet := n as Bullet
				if bullet != null:
					rec.append(["shot", clock[0], bullet.damage, bullet.rotation]))
			_dummy(p.get_parent(), ws.weapon_muzzles[0].global_position + Vector2(0, -300), rec, clock)
		var b_locked := true
		for t in 120:
			clock[0] = t
			if t == 0:
				Input.action_press("shoot")
			elif t == 60:
				Input.action_release("shoot")
			for i in 2:
				var p: PlayerBase = [a, b][i]
				p._step_disruption(D)
				seed(t)
				(states[i] as WeaponState)._physics_process(D)
			b_locked = b_locked and b.abilities_locked()
		Input.action_release("shoot")
		assert_true(b_locked, "%s %s: B was locked on every tick" % [mode, id])
		assert_false(a.abilities_locked(), "%s %s: control: A never was" % [mode, id])
		assert_gt((logs[0] as Array).size(), 0, "%s %s: non-vacuous: the weapon fired or hit" % [mode, id])
		assert_eq(logs[1], logs[0], "%s %s: shots, cadence and damage are bit-identical inside a lit field" % [mode, id])
		_free_box(a)
		_free_box(b)


func test_movement_is_identical_inside_a_lit_field(mode: String = use_parameters(MODES)) -> void:
	await get_tree().process_frame  # idle context for Input's just-pressed edges: see the header
	var a := _player(mode)
	var b := _player(mode)
	for p: PlayerBase in [a, b]:
		p.collision_layer = 0
		p.collision_mask = 0
	var field := _jammer(FAR)
	var tracks: Array = [[], []]
	var b_locked := true
	if mode == "open_space":
		for p: PlayerBase in [a, b]:
			(p as OpenSpacePlayerShip)._turn.set_scheme(&"keys", p.rotation)
		Input.action_press("move_up")
		Input.action_press("move_left")
		var start_rot: float = a.rotation
		for t in 60:
			if t == 10:
				Input.action_press("boost")
			field.position = FAR
			a._physics_process(D)
			field.position = b.global_position
			b._physics_process(D)
			b_locked = b_locked and b.abilities_locked()
			if t == 10:
				assert_true((a as OpenSpacePlayerShip)._boosting, "non-vacuous: the Shift boost fired on tick 10")
				assert_gt(a.velocity.length(), (a as OpenSpacePlayerShip).max_speed, "and sped the ship past cruise")
			for i in 2:
				var p: PlayerBase = [a, b][i]
				(tracks[i] as Array).append([p.global_position, p.velocity, p.rotation])
		assert_ne(a.rotation, start_rot, "non-vacuous: the ship turned")
		assert_gt(a.velocity.length(), 0.0, "non-vacuous: the ship is flying")
		assert_ne(a.global_position, START, "non-vacuous: and it moved")
	else:
		var machines: Array = []
		var dashes: Array = []
		for p: PlayerBase in [a, b]:
			machines.append(p.get_node("MovementStateMachine"))
			dashes.append(p.get_node("MovementStateMachine/DashState"))
			p.get_node("MovementStateMachine/MoveState").start_state_transition("move_right")
		Input.action_press("move_right")
		var dashed := true
		var moved_right := true
		for t in 60:
			for i in 2:
				var p: PlayerBase = [a, b][i]
				field.position = FAR if i == 0 else p.global_position
				if t == 20:
					(dashes[i] as DashState).start_state_transition("move_up")
				p._physics_process(D)
				(machines[i] as StateMachine)._process(D)
				(tracks[i] as Array).append([p.global_position, p.velocity, p.rotation])
			b_locked = b_locked and b.abilities_locked()
			if t < 20:
				moved_right = moved_right and a.velocity == Vector2(360.0, 0.0)
			else:
				dashed = dashed and (machines[0] as StateMachine).current_state == dashes[0] and a.velocity.y < 0.0
		assert_true(moved_right, "non-vacuous: A flew right at MoveState's 360 px/s until tick 20")
		assert_true(dashed, "non-vacuous: A was in DashState from tick 20 and moving forward")
		assert_gt(a.global_position.x, START.x, "non-vacuous: and it moved right")
		# The warp blink, on a pair of its own.
		var wa := _player(mode)
		var wb := _player(mode)
		var shifts: Array = []
		for i in 2:
			var w: PlayerBase = [wa, wb][i]
			WarpModule.new().apply(w)
			field.position = FAR if i == 0 else w.global_position
			w._step_disruption(D)
			var start: Vector2 = w.global_position
			(w.get_node("MovementStateMachine/DashState") as DashState).start_state_transition("move_right")
			shifts.append(w.global_position - start)
		assert_true(wb.abilities_locked(), "the warping ship B is locked")
		assert_almost_eq((shifts[0] as Vector2).x, 120.0, 0.0001, "non-vacuous: A blinked 120 px")
		assert_eq(shifts[1], shifts[0], "the warp blink is bit-identical inside a lit field")
	assert_true(b_locked, "%s: B was locked on every tick" % mode)
	assert_false(a.abilities_locked(), "%s: control: A never was" % mode)
	assert_eq(tracks[1], tracks[0], "%s: position, velocity and rotation are bit-identical inside a lit field" % mode)


func test_open_space_boost_drive_on_shift_fires_while_locked() -> void:
	ShipModuleState.unlock(&"engines", &"engine_boost")
	ShipModuleState.equip(&"engines", &"engine_boost")
	var ship := _player("open_space") as OpenSpacePlayerShip
	_lock(ship)
	var meter := ship._boost_meter
	var charges: float = meter.charges
	ship._step_boost(true, true, D)
	assert_true(ship.engine_boost_active, "the Boost Drive on Shift is a movement verb: never locked")
	assert_almost_eq(meter.charges, charges - meter.tank_size(), 0.0001, "one tank spent")


# --- No hazard: every lock observable untouched -----------------------------------------------------------------------


func test_no_hazard_leaves_every_lock_observable_untouched(mode: String = use_parameters(MODES)) -> void:
	assert_eq(Hazards.count(), 0, "precondition: no hazard registered")
	var p := _player(mode)
	var mod := _equip_module(p, &"emp_blast")
	var got := _lock_log(p)
	var refusals := _refusal_log(p)
	var always_open := true
	for i in 120:
		p._physics_process(D)
		always_open = always_open and not p.abilities_locked() and p.ability_lock_fill() == 0.0
	assert_true(always_open, "%s: unlocked with fill 0.0 on every tick" % mode)
	assert_eq(got, [], "%s: ability_lock_changed never emitted" % mode)
	assert_true(get_tree().get_nodes_in_group(&"enemies").is_empty(), "%s: precondition: no enemies" % mode)
	assert_true(_push_h(), "%s: an H press goes through" % mode)
	assert_eq(float(mod.get(&"_cooldown_left")), 15.0, "%s: and fires EMP Blast" % mode)
	var rs := _rocket_state(p)
	var children: int = rs.get_child_count()
	rs._on_action("special_weapon")
	assert_eq(rs.get_child_count(), children + 3, "%s: a K press launches" % mode)
	assert_eq(refusals, [], "%s: ability_press_refused never emitted" % mode)
	assert_eq(Hazards.count(), 0, "%s: still no hazard" % mode)
