## Unit tests for `EnemyShield` (global/components/enemy_shield.gd), hand-ticked.
##
## INTENT tests: they cover new code (Phase 5 t2, docs/plans/cmufs7elw001pnm2xr3b6fteb/3-plan.md
## §2.3). Fake `HitBox`es are placed around a host at a bearing; nothing awaits a frame, and the
## shield's own `_physics_process` is switched off so only `_tick()` advances its clocks.
extends GutTest

const ORIGIN := Vector2(300.0, 200.0)
const STEP: float = 1.0 / 60.0


## A host that answers the hit-blind armour query (an armoured Ram's hull).
class ArmouredHost extends Node2D:
	var armored: bool = true

	func is_armored() -> bool:
		return armored


## A host whose `deflects_hit` has a side effect (an `ArmorPlate`'s damages the plate): counted.
class CountingHost extends Node2D:
	var deflects_asked: int = 0

	func is_armored() -> bool:
		return false

	func deflects_hit(_hit_box: HitBox) -> bool:
		deflects_asked += 1
		return true


var _host: Node2D
var _hurt: HurtBox
var _shield: EnemyShield


## Builds host + HurtBox + shield (facing DOWN), configured by `setup` before it enters the tree.
func _rig(host: Node2D = null, setup: Callable = Callable()) -> EnemyShield:
	_host = host if host != null else Node2D.new()
	add_child_autofree(_host)
	_host.global_position = ORIGIN
	_hurt = HurtBox.new()
	_host.add_child(_hurt)
	_shield = EnemyShield.new()
	if setup.is_valid():
		setup.call(_shield)
	_host.add_child(_shield)
	_shield.set_physics_process(false)
	assert_true(_shield.attach(_hurt), "the shield takes the hurtbox's slot")
	_shield.face(Vector2.DOWN)
	return _shield


## A HitBox `off_deg` degrees off the shield's DOWN facing, 50 px from the host.
func _hit(off_deg: float, damage: int = 10) -> HitBox:
	var hb := HitBox.new()
	hb.damage = damage
	add_child_autofree(hb)
	hb.global_position = ORIGIN + Vector2.DOWN.rotated(deg_to_rad(off_deg)) * 50.0
	return hb


func _run(seconds: float) -> void:
	for i in roundi(seconds / STEP):
		_shield._tick(STEP)


func _count(sig: Signal) -> Array[int]:
	var n: Array[int] = [0]
	sig.connect(func(_a = null, _b = null) -> void: n[0] += 1)
	return n


# ---------------------------------------------------------------------------------------------
# The arc
# ---------------------------------------------------------------------------------------------

func test_a_hit_inside_the_arc_is_absorbed_and_costs_its_damage() -> void:
	var shield := _rig()
	var seen: Array = []
	shield.absorbed.connect(func(hb: HitBox, remaining: int) -> void: seen.append([hb, remaining]))
	var hit := _hit(0.0, 15)
	assert_true(shield.absorbs_hit(hit))
	assert_eq(shield.points(), 25)
	assert_eq(seen, [[hit, 25]], "absorbed carries the hit and what is left")


func test_the_110_degree_arc_edge_is_54_absorbed_56_lands() -> void:
	var shield := _rig()
	assert_true(shield.absorbs_hit(_hit(54.0)), "54° off the facing is inside a 110° arc")
	assert_true(shield.absorbs_hit(_hit(-54.0)), "on both sides")
	assert_false(shield.absorbs_hit(_hit(56.0)), "56° off lands on the hull")
	assert_false(shield.absorbs_hit(_hit(-56.0)))
	assert_eq(shield.points(), 20, "only the two absorbed hits cost points")


func test_a_hit_through_the_hurtbox_from_outside_the_arc_reaches_the_hull() -> void:
	_rig()
	var damage: Array[int] = []
	var absorbed: Array[int] = [0]
	_hurt.received_damage.connect(func(d: int) -> void: damage.append(d))
	_hurt.hit_absorbed.connect(func(_hb: HitBox) -> void: absorbed[0] += 1)
	_hurt._on_area_entered(_hit(0.0, 7))
	_hurt._on_area_entered(_hit(180.0, 9))
	assert_eq(absorbed[0], 1, "the front hit is absorbed")
	assert_eq(damage, [9] as Array[int], "the rear hit lands on the hull")


func test_a_bubble_absorbs_from_behind() -> void:
	var shield := _rig(null, func(s: EnemyShield) -> void: s.arc_deg = 360.0)
	assert_true(shield.absorbs_hit(_hit(180.0)))
	assert_true(shield.absorbs_hit(_hit(90.0)))


func test_widening_the_arc_while_attached_takes_effect_on_the_next_hit() -> void:
	var shield := _rig()
	assert_false(shield.absorbs_hit(_hit(180.0)), "a 110° arc does not cover the rear")
	shield.arc_deg = 360.0
	assert_true(shield.absorbs_hit(_hit(180.0)), "the escort's 360° bubble does")


# ---------------------------------------------------------------------------------------------
# Break, reboot and refill
# ---------------------------------------------------------------------------------------------

func test_capacity_40_against_three_25_damage_hits() -> void:
	var shield := _rig()
	var broken := _count(shield.broken)
	var damage: Array[int] = []
	var absorbed: Array[int] = [0]
	_hurt.received_damage.connect(func(d: int) -> void: damage.append(d))
	_hurt.hit_absorbed.connect(func(_hb: HitBox) -> void: absorbed[0] += 1)

	_hurt._on_area_entered(_hit(0.0, 25))
	assert_eq(shield.points(), 15, "the first is absorbed, 15 left")
	assert_eq(broken[0], 0)
	_hurt._on_area_entered(_hit(0.0, 25))
	assert_eq(absorbed[0], 2, "the breaking hit is absorbed whole: no bleed-through")
	assert_eq(damage, [] as Array[int])
	assert_eq(shield.points(), 0)
	assert_eq(broken[0], 1)
	_hurt._on_area_entered(_hit(0.0, 25))
	assert_eq(damage, [25] as Array[int], "the third lands on the hull")
	assert_eq(broken[0], 1, "broken fires once")


func test_nothing_is_absorbed_while_rebooting() -> void:
	var shield := _rig()
	var restored := _count(shield.restored)
	assert_true(shield.absorbs_hit(_hit(0.0, 40)))
	assert_false(shield.is_up())
	_run(shield.reboot_seconds - STEP)
	assert_false(shield.is_up(), "one tick before the reboot ends it is still down")
	assert_false(shield.absorbs_hit(_hit(0.0, 1)), "and absorbs nothing")
	assert_eq(shield.points(), 0)
	_run(6.0 * STEP)
	assert_true(shield.is_up(), "after the reboot it refills from 0 at once, with no extra regen_delay")
	assert_true(shield.points() > 0 and shield.points() < shield.capacity)
	_run(shield.regen_seconds - 0.1 - 5.0 * STEP)
	assert_lt(shield.points(), shield.capacity, "not full before reboot_seconds + regen_seconds")
	assert_eq(restored[0], 0)
	_run(0.1 + 2.0 * STEP)
	assert_eq(shield.points(), shield.capacity, "full at reboot_seconds + regen_seconds")
	assert_eq(restored[0], 1)


func test_regen_waits_for_the_delay_after_the_last_hit_then_refills() -> void:
	var shield := _rig()
	var restored := _count(shield.restored)
	shield.absorbs_hit(_hit(0.0, 20))
	_run(2.0)
	shield.absorbs_hit(_hit(0.0, 10))
	assert_eq(shield.points(), 10)
	_run(shield.regen_delay - 0.05)
	assert_eq(shield.points(), 10, "every absorbed hit restarts the regen delay")
	# 30 points at 40 per 1.5 s take 1.125 s.
	_run(0.05 + 1.05)
	assert_lt(shield.points(), shield.capacity, "not full before the linear refill time")
	assert_gt(shield.points(), 10)
	_run(0.1)
	assert_eq(shield.points(), shield.capacity)
	assert_eq(restored[0], 1)
	_run(1.0)
	assert_eq(restored[0], 1, "restored once per refill")


# ---------------------------------------------------------------------------------------------
# Facing
# ---------------------------------------------------------------------------------------------

func test_the_facing_turns_at_exactly_turn_rate_then_settles_without_overshoot() -> void:
	var shield := _rig()
	var bearing := Vector2(1.0, -100.0)  # nearly behind
	shield.set_threat_point(ORIGIN + bearing)
	var step := shield.turn_rate * STEP
	var off := shield.facing().angle_to(bearing)
	var start_sign := signf(off)
	var bad_steps := 0
	var grew := 0
	var overshot := 0
	for i in roundi(2.5 / STEP):
		var before := shield.facing()
		shield._tick(STEP)
		var now := shield.facing().angle_to(bearing)
		if absf(off) > step and absf(absf(before.angle_to(shield.facing())) - step) > 0.0001:
			bad_steps += 1
		if absf(now) > absf(off) + 0.000001:
			grew += 1
		if absf(now) > 0.000001 and signf(now) != start_sign:
			overshot += 1
		off = now
	assert_eq(bad_steps, 0, "every tick far off the bearing turns by exactly turn_rate × delta")
	assert_eq(grew, 0, "the angle to the bearing never grows")
	assert_eq(overshot, 0, "it never swings past the bearing")
	assert_almost_eq(off, 0.0, 0.001, "it settles on the bearing to the threat point")


func test_with_no_threat_point_the_facing_holds() -> void:
	var shield := _rig()
	shield.face(Vector2.LEFT)
	_run(1.0)
	assert_almost_eq(shield.facing().angle_to(Vector2.LEFT), 0.0, 0.000001, "face() stays put")


func test_the_facing_never_writes_rotation() -> void:
	var shield := _rig()
	shield.set_threat_point(ORIGIN + Vector2.RIGHT * 100.0)
	_run(1.0)
	assert_eq(shield.rotation, 0.0)
	assert_eq(_host.rotation, 0.0)


# ---------------------------------------------------------------------------------------------
# Sustain mode and detaching
# ---------------------------------------------------------------------------------------------

func test_a_sustained_shield_lapses_a_heartbeat_after_the_last_sustain_then_fades_and_frees() -> void:
	var shield := _rig(null, func(s: EnemyShield) -> void: s.sustain_mode = true)
	var lapsed := _count(shield.lapsed)
	shield.sustain(ORIGIN + Vector2.DOWN * 100.0)
	_run(0.25)
	shield.sustain(ORIGIN + Vector2.DOWN * 100.0)
	_run(0.25)
	assert_eq(lapsed[0], 0, "each sustain() refreshes the heartbeat")
	assert_true(shield.absorbs_hit(_hit(0.0, 1)))
	_run(0.1)
	assert_eq(lapsed[0], 1, "0.35 s after the last sustain() it lapses")
	assert_false(shield.absorbs_hit(_hit(0.0, 1)), "a lapsed shield absorbs nothing")
	assert_false(_hurt.has_absorber(), "the slot is released at the lapse, not after the fade")
	var damage: Array[int] = []
	_hurt.received_damage.connect(func(d: int) -> void: damage.append(d))
	_hurt._on_area_entered(_hit(0.0, 3))
	assert_eq(damage, [3] as Array[int], "the next hit lands on the hull during the fade")
	var next := EnemyShield.new()
	_host.add_child(next)
	next.set_physics_process(false)
	assert_true(next.attach(_hurt), "a new shield can attach during the fade")
	assert_false(shield.is_queued_for_deletion(), "it fades first")
	_run(shield.fade_seconds + STEP)
	assert_true(shield.is_queued_for_deletion(), "then frees itself")
	assert_eq(lapsed[0], 1, "lapsed once")
	await get_tree().process_frame
	assert_false(is_instance_valid(shield))
	assert_true(_hurt.has_absorber(), "the faded shield's exit leaves the new shield's slot alone")


func test_leaving_the_tree_clears_the_hurtbox_slot() -> void:
	var shield := _rig()
	assert_true(_hurt.has_absorber())
	_host.remove_child(shield)
	assert_false(_hurt.has_absorber(), "a detached shield no longer holds the slot")
	shield.free()


# ---------------------------------------------------------------------------------------------
# Armoured hosts (review finding 9)
# ---------------------------------------------------------------------------------------------

func test_an_armoured_host_is_not_shielded_until_it_is_exposed() -> void:
	var host := ArmouredHost.new()
	var shield := _rig(host)
	assert_false(shield.absorbs_hit(_hit(0.0, 10)), "an armoured hull lets the hit through to its plates")
	assert_eq(shield.points(), 40, "and the shield spends nothing on it")
	host.armored = false
	assert_true(shield.absorbs_hit(_hit(0.0, 10)))
	assert_eq(shield.points(), 30)


func test_deflects_hit_is_never_asked() -> void:
	var host := CountingHost.new()
	var shield := _rig(host)
	assert_true(shield.absorbs_hit(_hit(0.0, 10)))
	assert_false(shield.absorbs_hit(_hit(180.0, 10)))
	assert_eq(host.deflects_asked, 0, "the shield asks only the hit-blind is_armored()")
