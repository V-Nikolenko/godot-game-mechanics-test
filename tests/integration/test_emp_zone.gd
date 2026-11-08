## INTENT tests for Phase 9 plan §2.13 (docs/plans/cmug23onr001pm52w9swwophy/3-plan.md, task t11): the neutral EMP zone.
##
## `EmpZone` (`assault/scenes/hazards/emp_zone/`) is a `Node2D` composing a child `HazardField` ("Field", kind `emp_zone`,
## radius 260, avoid_weight 0.6, cycle 1.0 / 0.25 / 4.75). It listens to `Field.phase_changed` and, on each change TO ACTIVE,
## calls `EmpPulse.emit(..., TARGET_ALL)` once for 2.0 s: the player (lock + boost refusal), every enemy that answers EMP, and
## seeking rockets. The field's own avoid weight (0.6 while telegraphing or lit, 0 quiet) is what makes enemies steer round it.
##
## Lock rows use both real player scenes, hand-ticked at 1/60 (the shape of `test_player_boost_disruption.gd`); enemy rows run in
## both harnesses (`tests/helpers/enemy_ai_harness.gd`). The zone's field is hand-ticked (`_physics_process(DT)`).
extends GutTest

const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")
const ZONE: PackedScene = preload("res://assault/scenes/hazards/emp_zone/emp_zone.tscn")
const SHIP_SCENE: PackedScene = preload("res://open_space/scenes/entities/player/player_ship.tscn")
const FIGHTER_PLAYER_SCENE: PackedScene = preload("res://assault/scenes/player/player_fighter.tscn")
const FIGHTER: PackedScene = preload("res://assault/scenes/enemies/fighter/fighter.tscn")
const HOMING_SCENE: PackedScene = preload("res://assault/scenes/projectiles/missiles/homing/homing_missile.tscn")
const SaveSandbox := preload("res://tests/helpers/save_sandbox.gd")

const MODES := ["open_space", "assault"]
const DT := 1.0 / 60.0
const MID := Vector2(640.0, 360.0)

## Stands in for a player in group `player`: records every `apply_emp`.
class _PlayerProbe extends Node2D:
	var hits: int = 0
	func apply_emp(_seconds: float, _source: Node) -> void:
		hits += 1


var _sandbox := SaveSandbox.new()


func before_all() -> void:
	_sandbox.capture()


func after_all() -> void:
	_sandbox.restore()


func after_each() -> void:
	DialogPlayer.is_active = false


# ── Helpers ─────────────────────────────────────────────────────────────────────────────────────────────────────────

func _world(mode: String) -> RefCounted:
	var h: RefCounted = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(h.root)
	h.player.global_position = MID + Vector2(2000.0, 0.0)  # far from any zone unless a test moves it
	return h


## A zone at [param at] under [param parent], its field hand-ticked.
func _zone(parent: Node, at: Vector2 = MID) -> EmpZone:
	var z := ZONE.instantiate() as EmpZone
	parent.add_child(z)
	z.global_position = at
	z.field().set_physics_process(false)
	return z


func _tick_zone(z: EmpZone, ticks: int) -> void:
	for i in ticks:
		z.field()._physics_process(DT)


## A real player of [param mode] in the tree, its own physics off.
func _player(mode: String) -> PlayerBase:
	var p: PlayerBase
	if mode == "open_space":
		p = SHIP_SCENE.instantiate() as PlayerBase
	else:
		p = FIGHTER_PLAYER_SCENE.instantiate() as PlayerBase
	add_child_autofree(p)
	p.set_physics_process(false)
	return p


## Ticks the zone's field to its first ACTIVE edge (the zone's TELEGRAPH is 1.0 s).
func _fire(z: EmpZone) -> void:
	var guard := 0
	while z.field().phase() != HazardField.Phase.ACTIVE and guard < 200:
		_tick_zone(z, 1)
		guard += 1


# ── The scene ───────────────────────────────────────────────────────────────────────────────────────────────────────

func test_the_scene_is_a_node2d_composing_a_field_with_the_planned_numbers() -> void:
	var z := ZONE.instantiate()
	assert_true(z is EmpZone)
	assert_false(z is HazardField, "composition, never a HazardField subclass")
	var f := z.get_node("Field") as HazardField
	assert_not_null(f)
	assert_eq(f.kind, &"emp_zone")
	assert_eq(f.radius, 260.0)
	assert_eq(f.avoid_weight, 0.6)
	assert_eq([f.cycle_telegraph, f.cycle_active, f.cycle_quiet], [1.0, 0.25, 4.75])
	assert_eq([f.pull_force, f.tangential_force, f.movement_penalty, f.stress_damage], [0.0, 0.0, 0.0, 0])
	assert_false(f.disables_abilities, "the lock comes from the EMP itself")
	assert_eq((z as EmpZone).emp_seconds, 2.0)
	assert_eq((z as EmpZone).radius(), 260.0)
	z.free()


func test_the_hub_sweep_helper_reads_an_emp_zone_as_260_not_0() -> void:
	var z := ZONE.instantiate()
	var script: GDScript = load("res://tests/integration/test_sector_hub_patrol.gd")
	var sweep = script.new()
	assert_eq(sweep._element_radius(z), 260.0, "an EmpZone is a Node2D parent: the sweep must read its radius")
	sweep.free()
	z.free()


# ── The player ──────────────────────────────────────────────────────────────────────────────────────────────────────

func test_the_player_at_the_edge_is_emp_d_and_one_pixel_outside_is_not(mode: String = use_parameters(MODES)) -> void:
	var box := Node2D.new()
	add_child_autofree(box)
	var z := _zone(box)
	var p := _player(mode)
	p.global_position = MID + Vector2(260.0, 0.0)
	var outside := _player(mode)
	outside.global_position = MID + Vector2(261.0, 0.0)
	_fire(z)
	assert_true(p.abilities_locked(), "%s: the edge is inside (centre distance <= radius)" % mode)
	assert_eq(p.boost_efficiency(), 0.0, "%s: boost refused" % mode)
	assert_true(p.is_emp_disrupted(), "%s" % mode)
	assert_false(p.allow_ability_press(), "%s: an H / K press is refused" % mode)
	assert_false(outside.abilities_locked(), "%s: 1 px outside is not" % mode)
	assert_false(outside.is_emp_disrupted(), "%s" % mode)
	for i in 119:
		p._step_disruption(DT)
	assert_true(p.abilities_locked(), "%s: still locked after 119 ticks" % mode)
	p._step_disruption(DT)
	assert_false(p.abilities_locked(), "%s: unlocked after 120 ticks (2.0 s)" % mode)


# ── Enemies and seekers ─────────────────────────────────────────────────────────────────────────────────────────────

func test_an_enemy_inside_is_emp_d_and_still_shootable(mode: String = use_parameters(MODES)) -> void:
	var h := _world(mode)
	var z := _zone(h.root)
	var inside := FIGHTER.instantiate() as Fighter
	h.root.add_child(inside)
	inside.global_position = MID + Vector2(0.0, 200.0)
	inside.set_physics_process(false)
	var outside := FIGHTER.instantiate() as Fighter
	h.root.add_child(outside)
	outside.global_position = MID + Vector2(0.0, 300.0)
	outside.set_physics_process(false)
	_fire(z)
	assert_true(inside.is_emp_disrupted(), "%s: the enemy inside is EMP'd" % mode)
	assert_false(outside.is_emp_disrupted(), "%s: 40 px beyond the radius is not" % mode)
	inside.health.current_health = 1
	var died: Array = []
	inside.died.connect(func() -> void: died.append(inside.is_emp_disrupted()))
	inside.hurt_box.received_damage.emit(5)
	assert_eq(died, [true], "%s: it was killed while EMP'd (it stays tangible)" % mode)


func test_a_player_homing_rocket_inside_loses_guidance(mode: String = use_parameters(MODES)) -> void:
	var h := _world(mode)
	var z := _zone(h.root)
	var target := Node2D.new()
	h.root.add_child(target)
	target.global_position = MID + Vector2(1500.0, 0.0)
	var r: homing_missile = HOMING_SCENE.instantiate()
	r.locked_target = target
	h.root.add_child(r)
	r.global_position = MID + Vector2(0.0, 100.0)
	r.rotation = 0.0
	r.set_physics_process(false)
	(r.get_node("ProjectileLifetime") as ProjectileLifetime).set_physics_process(false)
	r._physics_process(DT)
	_fire(z)
	var heading := r.rotation
	var kept := true
	for i in 30:
		r._physics_process(DT)
		kept = kept and absf(angle_difference(r.rotation, heading)) < 1e-5
	assert_true(kept, "%s: it flies straight after the pulse" % mode)


# ── The cycle ───────────────────────────────────────────────────────────────────────────────────────────────────────

func test_exactly_one_pulse_per_cycle_over_three_cycles(mode: String = use_parameters(MODES)) -> void:
	var h := _world(mode)
	var probe := _PlayerProbe.new()
	probe.add_to_group(&"player")
	h.root.add_child(probe)
	probe.global_position = MID
	var z := _zone(h.root)
	_tick_zone(z, 6 * 60 * 3)  # 1080 ticks = 3 cycles of 6 s
	assert_eq(probe.hits, 3, "%s: one emit per cycle, none on the telegraph start or the quiet" % mode)


func test_avoid_weight_is_0_6_while_telegraphing_and_lit_and_0_quiet() -> void:
	var box := Node2D.new()
	add_child_autofree(box)
	var z := _zone(box)
	assert_eq(z.field().hazard_info().avoid_weight, 0.6, "telegraph")
	_fire(z)
	assert_eq(z.field().hazard_info().avoid_weight, 0.6, "lit")
	_tick_zone(z, 30)
	assert_eq(z.field().phase(), HazardField.Phase.QUIET)
	assert_eq(z.field().hazard_info().avoid_weight, 0.0, "quiet")


func test_the_zone_pulses_once_per_active_edge_not_per_tick() -> void:
	var box := Node2D.new()
	add_child_autofree(box)
	var probe := _PlayerProbe.new()
	probe.add_to_group(&"player")
	box.add_child(probe)
	probe.global_position = MID
	var z := _zone(box)
	_fire(z)
	assert_eq(probe.hits, 1)
	_tick_zone(z, 5)  # still ACTIVE (0.25 s)
	assert_eq(probe.hits, 1, "the lit quarter-second does not pulse again")


# ── Avoidance and registration ──────────────────────────────────────────────────────────────────────────────────────

## One real Fighter APPROACH run (the `test_enemy_dual_mode.gd` well row's shape): down from (640, -360), then west along
## y ~ -168, through a zone at (320, -168). `avoid_weight` is the zone field's; 0 is the control.
func _fighter_past_a_zone(h: RefCounted, avoid_weight: float) -> float:
	var z := _zone(h.root, Vector2(320.0, -168.0))
	z.field().avoid_weight = avoid_weight
	_tick_zone(z, 1)  # the field publishes its numbers on its tick
	var f := FIGHTER.instantiate() as Fighter
	f.global_position = Vector2(640.0, -360.0)
	(f.get_node("Brain") as FighterBrain).start_engaged = true
	h.root.add_child(f)
	f.set_physics_process(false)
	f.config.engage_seconds = 1000.0
	var brain := f.get_node("Brain") as FighterBrain
	var closest := INF
	for _i in 600:
		var before := f.global_position
		f._physics_process(DT)
		f.global_position = before + f.velocity * DT
		closest = minf(closest, f.global_position.distance_to(z.global_position) - z.radius())
		if brain.phase == FighterBrain.Phase.RUN_IN:
			break
	f.free()
	z.free()
	return closest


func test_a_fighter_bends_round_a_zone_and_ignores_a_zero_weight_one(mode: String = use_parameters(MODES)) -> void:
	var h := _world(mode)
	h.player.global_position = MID
	var control := _fighter_past_a_zone(h, 0.0)
	var run := _fighter_past_a_zone(h, 0.6)
	assert_lt(control, -40.0, "%s: control: with no avoid weight the approach runs into the zone (%.1f)" % [mode, control])
	assert_gt(run, control + 40.0, "%s: at 0.6 it bends away (closest %.1f vs %.1f)" % [mode, run, control])


func test_freeing_the_zone_unregisters_its_field() -> void:
	var before := Hazards.count()
	var box := Node2D.new()
	add_child_autofree(box)
	var z := _zone(box)
	assert_eq(Hazards.count(), before + 1)
	z.free()
	assert_eq(Hazards.count(), before, "the field unregisters in _exit_tree")
