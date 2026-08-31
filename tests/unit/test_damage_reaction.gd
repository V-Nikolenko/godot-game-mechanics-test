## Characterization tests for DamageReaction — the shared "ship takes a hit"
## wiring that routes HurtBox damage through an optional Shield into Health,
## and destroys the host entity on death.
extends GutTest

var _host: Node2D
var _health: Health
var _hurt: HurtBox
var _dr: DamageReaction


## Builds host → {Health, HurtBox, DamageReaction} with the host already in the
## tree, so every component's _ready() has run before setup() is called.
func _build(shield: Shield = null, hp: int = 100) -> void:
	_host = Node2D.new()
	add_child_autofree(_host)
	_health = Health.new()
	_health.max_health = hp
	_health.current_health = hp
	_host.add_child(_health)
	_hurt = HurtBox.new()
	_host.add_child(_hurt)
	if shield:
		_host.add_child(shield)
	_dr = DamageReaction.new()
	_host.add_child(_dr)
	_dr.setup(_health, shield, _hurt, null)   ## null sprite → the flash tween is skipped


func test_defaults() -> void:
	var dr := DamageReaction.new()
	assert_eq(dr.flash_color, Color(1.0, 0.4, 0.4, 1.0))
	assert_eq(dr.flash_time, 0.18)
	assert_false(dr.on_hit.is_valid(), "no extra on-hit reaction unless the host sets one")
	dr.free()


func test_setup_adds_an_explosion_effect_child() -> void:
	_build()
	var found := false
	for child in _dr.get_children():
		if child is ExplosionEffect:
			found = true
	assert_true(found, "the death explosion is owned by the DamageReaction")


func test_hurtbox_damage_reaches_health() -> void:
	_build()
	_hurt.received_damage.emit(30)
	assert_eq(_health.current_health, 70)


func test_a_shield_charge_absorbs_the_hit_entirely() -> void:
	var shield := Shield.new()
	shield.bind_progression = false
	shield.permanent_charges = 1
	_build(shield)

	_hurt.received_damage.emit(40)
	assert_eq(_health.current_health, 100, "the charge ate the whole hit, damage value irrelevant")
	assert_eq(shield.permanent_active, 0)

	_hurt.received_damage.emit(40)
	assert_eq(_health.current_health, 60, "with the shield spent, damage lands")


func test_the_on_hit_hook_runs_for_every_hit_including_absorbed_ones() -> void:
	var shield := Shield.new()
	shield.bind_progression = false
	shield.permanent_charges = 1
	_build(shield)
	var hits: Array[int] = []
	_dr.on_hit = func(d: int) -> void: hits.append(d)

	_hurt.received_damage.emit(5)        ## absorbed by the shield
	_hurt.received_damage.emit(7)        ## lands on health
	assert_eq(hits, [5, 7] as Array[int], "on_hit fires before the shield is consulted")


func test_death_emits_died_and_frees_the_host() -> void:
	_build(null, 10)
	var deaths: Array[bool] = []
	_dr.died.connect(func() -> void: deaths.append(true))

	_hurt.received_damage.emit(10)
	assert_eq(_health.current_health, 0)
	assert_eq(deaths.size(), 1, "died fires exactly once")
	assert_true(_host.is_queued_for_deletion(), "the host entity is destroyed")
	await wait_process_frames(2)


func test_overkill_still_dies_once() -> void:
	_build(null, 10)
	var deaths: Array[bool] = []
	_dr.died.connect(func() -> void: deaths.append(true))
	_hurt.received_damage.emit(9999)
	assert_eq(_health.current_health, 0)
	assert_eq(deaths.size(), 1)
	await wait_process_frames(2)


func test_setup_is_safe_to_call_twice() -> void:
	_build()
	_dr.setup(_health, null, _hurt, null)   ## guards against duplicate connections
	_hurt.received_damage.emit(10)
	assert_eq(_health.current_health, 90, "damage is applied once, not twice")
