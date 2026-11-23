## INTENT tests for the boss phase ladder: `BossPhase` (`global/boss/boss_phase.gd`) and `BossPhaseDriver` (`global/boss/boss_phase_driver.gd`),
## Phase 11 t1 (docs/plans/cmug256so0031m52wbxomst72/3-plan.md §2.1; row numbers below follow it).
##
## On `tests/helpers/fixture_modular_host.tscn`: parts `Open` (WEAPON, 100 HP: `EnemyModule.max_health` overrides the Health node), `Locked` (CORE, locked, 100 HP) and `Laser` (ENGINE, 100 HP), host
## `Health` 1000, every `hull_share` 0. The driver is added by each row. Everything is hand-driven (`destroy()`, `Health` writes), no physics.
extends GutTest

const HOST_SCENE: PackedScene = preload("res://tests/helpers/fixture_modular_host.tscn")

var _root: Node2D


func before_each() -> void:
	_root = Node2D.new()
	add_child_autofree(_root)


# ---------------------------------------------------------------------------------------------
# Builders
# ---------------------------------------------------------------------------------------------

func _host() -> BaseEnemy:
	var host := HOST_SCENE.instantiate() as BaseEnemy
	_root.add_child(host)
	return host


func _hull(host: Node) -> ModularHull:
	return host.get_node("ModularHull") as ModularHull


func _part(host: Node, part_name: String) -> EnemyModule:
	return host.get_node("Modules/" + part_name) as EnemyModule


func _health(host: Node) -> Health:
	return host.get_node("Health") as Health


const TWO := BossPhase.Change.MOVEMENT | BossPhase.Change.ATTACKS


func _phase(id: StringName, trigger: BossPhase.Trigger, changes: int = TWO) -> BossPhase:
	var p := BossPhase.new()
	p.phase_id = id
	p.trigger = trigger
	p.changes = changes
	return p


func _parts_phase(id: StringName, ids: Array[StringName], roles: Array[int] = [], count: int = 1) -> BossPhase:
	var p := _phase(id, BossPhase.Trigger.PARTS_DESTROYED)
	p.module_ids = ids
	p.roles = roles
	p.count = count
	return p


func _health_phase(id: StringName, module_id: StringName, ratio: float) -> BossPhase:
	var p := _phase(id, BossPhase.Trigger.HEALTH_AT_OR_BELOW)
	p.health_module = module_id
	p.health_ratio = ratio
	return p


func _start() -> BossPhase:
	return _phase(&"start", BossPhase.Trigger.START, 0)


## A driver on [param host] with [param phases], not yet bound. Returns the ordered list of entered ids as it is filled.
func _driver(host: Node, phases: Array[BossPhase], log: Array = []) -> BossPhaseDriver:
	var d := BossPhaseDriver.new()
	d.name = "PhaseDriver"
	d.phases = phases
	d.phase_entered.connect(func(index: int, id: StringName) -> void: log.append([index, id]))
	host.add_child(d)
	return d


func _bind(d: BossPhaseDriver, host: Node) -> void:
	d.bind(_hull(host), _health(host))


func _ids(log: Array) -> Array:
	return log.map(func(e): return e[1])


# ---------------------------------------------------------------------------------------------
# Row 1: START on bind
# ---------------------------------------------------------------------------------------------

func test_unbound_driver_is_in_no_phase() -> void:
	var host := _host()
	var d := _driver(host, [_start()])
	assert_eq(d.current_index(), -1, "nothing entered before bind()")
	assert_eq(d.current_id(), &"")


func test_start_phase_is_entered_on_bind_with_one_signal() -> void:
	var host := _host()
	var log := []
	var d := _driver(host, [_start(), _parts_phase(&"two", [&"open"])], log)
	_bind(d, host)
	assert_eq(log, [[0, &"start"]], "exactly one phase_entered(0, start)")
	assert_eq(d.current_index(), 0)
	assert_eq(d.current_id(), &"start")
	assert_true(d.has_reached(&"start"))
	assert_false(d.has_reached(&"two"))
	assert_eq(d.phase(1).phase_id, &"two")


func test_bind_counts_a_part_already_destroyed() -> void:
	var host := _host()
	_part(host, "Open").destroy()
	var log := []
	var d := _driver(host, [_start(), _parts_phase(&"two", [&"open"])], log)
	_bind(d, host)
	assert_eq(_ids(log), [&"start", &"two"], "a part destroyed before bind() counts")


# ---------------------------------------------------------------------------------------------
# Row 2: what counts as a destroyed part
# ---------------------------------------------------------------------------------------------

func test_parts_by_role_count_only_that_role() -> void:
	var host := _host()
	var roles: Array[int] = [EnemyModule.Role.ENGINE]
	var d := _driver(host, [_start(), _parts_phase(&"engines", [], roles)])
	_bind(d, host)
	_part(host, "Open").destroy()  # a WEAPON
	assert_eq(d.current_id(), &"start", "a weapon is not an engine")
	_part(host, "Laser").destroy()
	assert_eq(d.current_id(), &"engines")


func test_parts_by_ids_count_only_those_ids() -> void:
	var host := _host()
	var ids: Array[StringName] = [&"laser"]
	var d := _driver(host, [_start(), _parts_phase(&"ids", ids)])
	_bind(d, host)
	_part(host, "Open").destroy()
	assert_eq(d.current_id(), &"start", "open is not named")
	_part(host, "Laser").destroy()
	assert_eq(d.current_id(), &"ids")


func test_ids_win_over_roles_and_empty_both_means_any_part() -> void:
	var host := _host()
	var roles: Array[int] = [EnemyModule.Role.CORE]
	var ids: Array[StringName] = [&"open"]
	var d := _driver(host, [_start(), _parts_phase(&"ids", ids, roles)])
	_bind(d, host)
	_part(host, "Open").destroy()
	assert_eq(d.current_id(), &"ids", "module_ids is used and roles ignored when both are set")
	var host2 := _host()
	var d2 := _driver(host2, [_start(), _parts_phase(&"any", [], [], 2)])
	_bind(d2, host2)
	_part(host2, "Open").destroy()
	assert_eq(d2.current_id(), &"start", "one of two")
	_part(host2, "Laser").destroy()
	assert_eq(d2.current_id(), &"any", "any role counts when both lists are empty")


func test_a_locked_parts_deflected_hit_does_not_count() -> void:
	var host := _host()
	var roles: Array[int] = [EnemyModule.Role.CORE]
	var d := _driver(host, [_start(), _parts_phase(&"core", [], roles)])
	_bind(d, host)
	var locked := _part(host, "Locked")
	locked.hurt_box.received_damage.emit(5000)  # locked: pinged, not damaged
	assert_false(locked.is_destroyed())
	assert_eq(d.current_id(), &"start", "a deflected hit is not a destroyed part")
	locked.destroy()
	assert_eq(d.current_id(), &"core")


# ---------------------------------------------------------------------------------------------
# Row 3: a cascade
# ---------------------------------------------------------------------------------------------

func test_one_destroy_that_satisfies_two_rules_enters_both_in_order() -> void:
	var host := _host()
	var weapons: Array[int] = [EnemyModule.Role.WEAPON]
	var ids: Array[StringName] = [&"open"]
	var log := []
	var d := _driver(host, [_start(), _parts_phase(&"a", [], weapons), _parts_phase(&"b", ids)], log)
	_bind(d, host)
	log.clear()
	var frame := Engine.get_process_frames()
	_part(host, "Open").destroy()
	assert_eq(log, [[1, &"a"], [2, &"b"]], "two signals, in ladder order")
	assert_eq(Engine.get_process_frames(), frame, "inside the destroy() call")
	assert_eq(d.current_index(), 2)


# ---------------------------------------------------------------------------------------------
# Row 4: health boundary
# ---------------------------------------------------------------------------------------------

func test_part_health_enters_exactly_at_the_ratio_and_not_one_above() -> void:
	var host := _host()
	var d := _driver(host, [_start(), _health_phase(&"low", &"open", 0.5)])
	_bind(d, host)
	var open := _part(host, "Open")  # 100 HP: the threshold is 50
	open.health.set_health(51)
	assert_eq(d.current_id(), &"start", "51 of 100 is one above 0.5")
	open.health.set_health(50)
	assert_eq(d.current_id(), &"low", "50 of 100 is exactly at 0.5")


func test_host_health_enters_exactly_at_the_ratio_and_not_one_above() -> void:
	var host := _host()
	var d := _driver(host, [_start(), _health_phase(&"low", &"", 0.4)])
	_bind(d, host)
	_health(host).set_health(401)  # host max 1000
	assert_eq(d.current_id(), &"start")
	_health(host).set_health(400)
	assert_eq(d.current_id(), &"low")


func test_a_ratio_that_floats_just_under_an_integer_still_enters_at_it() -> void:
	# 0.29 * 100 is 28.999999999999996 in floating point: the boundary is the integer HP the ratio names.
	var host := _host()
	var d := _driver(host, [_start(), _health_phase(&"low", &"laser", 0.29)])
	_bind(d, host)
	_part(host, "Laser").health.set_health(29)
	assert_eq(d.current_id(), &"low")


# ---------------------------------------------------------------------------------------------
# Row 5: one way
# ---------------------------------------------------------------------------------------------

func test_a_repair_after_a_health_phase_does_not_step_back() -> void:
	var host := _host()
	var log := []
	var d := _driver(host, [_start(), _health_phase(&"low", &"", 0.5)], log)
	_bind(d, host)
	_health(host).set_health(400)
	assert_eq(d.current_id(), &"low")
	log.clear()
	_health(host).increase(600)
	assert_eq(d.current_id(), &"low", "healed to full, still in the later phase")
	assert_eq(log, [], "no signal for a repair")
	_health(host).set_health(300)
	assert_eq(log, [], "and no second entry")


# ---------------------------------------------------------------------------------------------
# Row 6: order
# ---------------------------------------------------------------------------------------------

func test_a_later_phase_waits_for_its_predecessor() -> void:
	var host := _host()
	var ids: Array[StringName] = [&"open"]
	var log := []
	var d := _driver(host, [_start(), _parts_phase(&"first", ids), _health_phase(&"second", &"", 0.9)], log)
	_bind(d, host)
	_health(host).set_health(800)  # the second rule holds already
	assert_eq(d.current_id(), &"start", "the next phase is first")
	_part(host, "Open").destroy()
	assert_eq(_ids(log), [&"start", &"first", &"second"], "entered in order once the predecessor has")


# ---------------------------------------------------------------------------------------------
# Row 7: validate()
# ---------------------------------------------------------------------------------------------

func _validate(phases: Array[BossPhase], host: Node = null) -> PackedStringArray:
	var d := BossPhaseDriver.new()
	d.phases = phases
	autofree(d)
	return d.validate(_hull(host) if host != null else null)


func test_validate_accepts_a_well_formed_ladder() -> void:
	var host := _host()
	var ids: Array[StringName] = [&"open", &"laser"]
	var phases: Array[BossPhase] = [_start(), _parts_phase(&"parts", ids, [], 2), _health_phase(&"low", &"laser", 0.3),
			_health_phase(&"lower", &"", 0.1)]
	assert_eq(_validate(phases, host), PackedStringArray(), "no errors with a hull")
	assert_eq(_validate(phases), PackedStringArray(), "no errors without one")


func test_validate_rejects_each_listed_error() -> void:
	var host := _host()
	var cases := {
		"no phases": [[] as Array[BossPhase], "no phases"],
		"index 0 not START": [[_parts_phase(&"p", [&"open"] as Array[StringName])] as Array[BossPhase], "START"],
		"START after index 0": [[_start(), _phase(&"s2", BossPhase.Trigger.START)] as Array[BossPhase], "START"],
		"duplicate id": [[_start(), _parts_phase(&"x", [&"open"] as Array[StringName]),
				_parts_phase(&"x", [&"laser"] as Array[StringName])] as Array[BossPhase], "duplicate"],
		"one-change phase": [[_start(), _phase(&"x", BossPhase.Trigger.PARTS_DESTROYED, BossPhase.Change.VISUALS)] as Array[BossPhase],
				"at least 2"],
		"zero-change phase": [[_start(), _phase(&"x", BossPhase.Trigger.PARTS_DESTROYED, 0)] as Array[BossPhase], "at least 2"],
		"count below 1": [[_start(), _parts_phase(&"x", [&"open"] as Array[StringName], [], 0)] as Array[BossPhase], "count"],
		"count above the countable parts": [[_start(), _parts_phase(&"x", [&"open"] as Array[StringName], [], 2)] as Array[BossPhase],
				"count"],
		"count above the parts of the role": [[_start(), _parts_phase(&"x", [] as Array[StringName],
				[EnemyModule.Role.ENGINE] as Array[int], 2)] as Array[BossPhase], "count"],
		"module id the hull lacks": [[_start(), _parts_phase(&"x", [&"nope"] as Array[StringName])] as Array[BossPhase], "nope"],
		"health module the hull lacks": [[_start(), _health_phase(&"x", &"nope", 0.5)] as Array[BossPhase], "nope"],
		"ratio 0": [[_start(), _health_phase(&"x", &"", 0.0)] as Array[BossPhase], "health_ratio"],
		"ratio 1": [[_start(), _health_phase(&"x", &"", 1.0)] as Array[BossPhase], "health_ratio"],
		"ratio above 1": [[_start(), _health_phase(&"x", &"", 1.5)] as Array[BossPhase], "health_ratio"],
	}
	for label in cases:
		var errors := _validate(cases[label][0], host)
		assert_gt(errors.size(), 0, "%s is an error" % label)
		var joined := "\n".join(errors)
		assert_true(joined.contains(cases[label][1]), "%s: the message names '%s' (got: %s)" % [label, cases[label][1], joined])


func test_hull_dependent_errors_need_a_hull() -> void:
	var phases: Array[BossPhase] = [_start(), _parts_phase(&"x", [&"nope"] as Array[StringName], [], 5)]
	assert_eq(_validate(phases).size(), 0, "without a hull only the hull-free rules run")


func test_change_count_counts_set_bits() -> void:
	assert_eq(BossPhase.change_count(0), 0)
	assert_eq(BossPhase.change_count(BossPhase.Change.MOVEMENT), 1)
	assert_eq(BossPhase.change_count(BossPhase.Change.ARENA | BossPhase.Change.VISUALS | BossPhase.Change.REINFORCEMENTS), 3)
	assert_eq(BossPhase.change_count(63), 6)
