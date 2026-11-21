## INTENT tests for Phase 9 plan §2.3 (docs/plans/cmug23onr001pm52w9swwophy/3-plan.md, task t2): what the player SEES
## and what a later audio pass hears when the abilities are jammed.
##
## - `AbilityLockStatic`: a code-built overlay on `PlayerBase` (like `BoostDisruptionRing`), visible exactly while
##   `abilities_locked()`, alpha `0.3 + 0.6 * fill`, flashed to full alpha for 0.15 s by a refused press.
## - `JammedChip` + `LockGlyph`, code-built by `MissionHud` (shared by both HUD scenes): the chip's bar width is
##   `ability_lock_fill()`, a refusal flashes the chip, and with no player nothing shows and nothing is logged.
## - `EventBus.player_ability_lock_changed(locked)` once per edge; `player_ordnance_hijacked(rocket, source)` is declared
##   for t4 to emit.
##
## Both real player scenes, physics off, every step hand-ticked at 1/60 (the shape of `test_player_ability_lock.gd`).
extends GutTest

const SHIP_SCENE: PackedScene = preload("res://open_space/scenes/entities/player/player_ship.tscn")
const FIGHTER_SCENE: PackedScene = preload("res://assault/scenes/player/player_fighter.tscn")
const HUD_SCENES: Dictionary = {
	"open_space": preload("res://open_space/scenes/gui/hud.tscn"),
	"assault": preload("res://assault/scenes/gui/hud.tscn"),
}
const SaveSandbox := preload("res://tests/helpers/save_sandbox.gd")

const D: float = 1.0 / 60.0
const MODES: Array = ["open_space", "assault"]
const START: Vector2 = Vector2(640, 360)
const R: float = 240.0
const STAB: float = 0.75
const OUT: Vector2 = Vector2(R + 60.0, 0.0)

var _sandbox := SaveSandbox.new()


func before_all() -> void:
	_sandbox.capture()


func after_all() -> void:
	_sandbox.restore()


func after_each() -> void:
	DialogPlayer.is_active = false


# --- Helpers ----------------------------------------------------------------------------------------------------------

var _box: Node2D = null

func _player(mode: String) -> PlayerBase:
	## One player at a time: a mode loop must not leave the previous ship (and its jammer) in the tree.
	if is_instance_valid(_box):
		_box.get_parent().remove_child(_box)
		_box.free()
	var box := Node2D.new()
	_box = box
	add_child_autofree(box)
	var p := (SHIP_SCENE if mode == "open_space" else FIGHTER_SCENE).instantiate() as PlayerBase
	box.add_child(p)
	p.set_physics_process(false)
	p.global_position = START
	return p


func _jammer(p: PlayerBase) -> HazardField:
	var f := HazardField.new()
	f.kind = &"jammer"
	f.radius = R
	f.avoid_weight = 0.0
	f.disables_abilities = true
	f.stabilise_seconds = STAB
	f.position = p.global_position
	p.get_parent().add_child(f)
	return f


func _tick(p: PlayerBase, ticks: int) -> void:
	for i in range(ticks):
		p._step_disruption(D)


func _overlay(p: PlayerBase) -> Node2D:
	return p.get_node_or_null("AbilityLockStatic") as Node2D


## A HUD of [param mode] over an existing player, past its one awaited frame.
func _hud(mode: String) -> CanvasLayer:
	var hud := (HUD_SCENES[mode] as PackedScene).instantiate() as CanvasLayer
	add_child_autofree(hud)
	await get_tree().process_frame
	return hud


func _chip(hud: CanvasLayer) -> Control:
	return hud.get_node("JammedChip") as Control


func _glyph(hud: CanvasLayer) -> Control:
	return hud.get_node("WeaponContainer/LockGlyph") as Control


func _bar(hud: CanvasLayer) -> Control:
	return hud.get_node("JammedChip/Bar") as Control


# --- Ship overlay -----------------------------------------------------------------------------------------------------

func test_no_overlay_exists_until_the_first_lock() -> void:
	for mode in MODES:
		var p := _player(mode)
		_tick(p, 3)
		assert_null(_overlay(p), "%s: nothing is built for a ship that was never jammed" % mode)


func test_overlay_is_visible_on_the_lock_tick_and_hidden_on_the_unlock_tick() -> void:
	for mode in MODES:
		var p := _player(mode)
		_jammer(p)
		p._step_disruption(D)
		assert_true(p.abilities_locked(), "%s: locked on the first tick" % mode)
		var ov := _overlay(p)
		assert_not_null(ov, "%s: built on the first lock" % mode)
		assert_true(ov.visible, "%s: shown on the lock tick" % mode)
		p.global_position += OUT
		_tick(p, 1 + 44)
		assert_true(p.abilities_locked(), "%s: still locked one tick before the delay ends" % mode)
		assert_true(ov.visible, "%s: shown through the stabilisation delay" % mode)
		p._step_disruption(D)
		assert_false(p.abilities_locked(), "%s: unlocked 45 ticks after the exit tick" % mode)
		assert_false(ov.visible, "%s: hidden on the unlock tick" % mode)


func test_overlay_follows_a_timed_lock_from_the_call_to_its_last_tick() -> void:
	for mode in MODES:
		var p := _player(mode)
		p.apply_ability_lock(1.5, null)
		assert_true(_overlay(p).visible, "%s: shown at the call" % mode)
		_tick(p, 89)
		assert_true(_overlay(p).visible, "%s: shown on tick 89" % mode)
		_tick(p, 1)
		assert_false(_overlay(p).visible, "%s: hidden on tick 90" % mode)


func test_overlay_alpha_is_0_9_while_held_then_tracks_the_fill() -> void:
	for mode in MODES:
		var p := _player(mode)
		_jammer(p)
		_tick(p, 2)
		var ov := _overlay(p)
		assert_almost_eq(ov.modulate.a, 0.9, 0.001, "%s: held" % mode)
		p.global_position += OUT
		_tick(p, 1 + 20)
		var fill := p.ability_lock_fill()
		assert_between(fill, 0.0, 1.0, "precondition: mid-delay")
		assert_almost_eq(ov.modulate.a, 0.3 + 0.6 * fill, 0.001, "%s: stabilising alpha = 0.3 + 0.6 * fill" % mode)


func test_a_refused_press_flashes_the_overlay_for_0_15_seconds() -> void:
	for mode in MODES:
		var p := _player(mode)
		_jammer(p)
		_tick(p, 2)
		var ov := _overlay(p)
		assert_almost_eq(ov.modulate.a, 0.9, 0.001, "precondition: held")
		assert_false(p.allow_ability_press(), "refused")
		assert_almost_eq(ov.modulate.a, 1.0, 0.001, "%s: full alpha at the refusal" % mode)
		_tick(p, 8)
		assert_almost_eq(ov.modulate.a, 1.0, 0.001, "%s: still flashing at 8 ticks (0.133 s)" % mode)
		_tick(p, 2)
		assert_almost_eq(ov.modulate.a, 0.9, 0.001, "%s: back to held alpha after 0.15 s" % mode)


func test_overlay_is_a_set_of_jagged_arcs_that_rejitter() -> void:
	var p := _player("assault")
	p.apply_ability_lock(2.0, null)
	var ov := _overlay(p)
	var before: Array = ov.call(&"arcs").duplicate(true)
	assert_eq(before.size(), 6, "six arcs")
	_tick(p, 6)  # 0.1 s > the 0.08 s jitter interval
	assert_ne(ov.call(&"arcs"), before, "the arcs were re-jittered")


# --- EventBus ---------------------------------------------------------------------------------------------------------

func test_event_bus_fires_once_per_edge_with_the_right_value() -> void:
	for mode in MODES:
		var p := _player(mode)
		var got: Array = []
		var cb := func(locked: bool) -> void: got.append(locked)
		EventBus.player_ability_lock_changed.connect(cb)
		var f := _jammer(p)
		_tick(p, 5)
		assert_eq(got, [true], "%s: one true for the lock, none for the refreshes" % mode)
		p.apply_ability_lock(2.0, null)
		assert_eq(got, [true], "%s: a timed lock inside a field is no edge" % mode)
		p.global_position += OUT
		_tick(p, 1 + 60)
		assert_eq(got, [true], "%s: still held by the timed lock" % mode)
		_tick(p, 70)
		assert_eq(got, [true, false], "%s: one false when it ends" % mode)
		EventBus.player_ability_lock_changed.disconnect(cb)
		f.free()


func test_event_bus_matches_the_ships_own_signal() -> void:
	var p := _player("assault")
	var bus: Array = []
	var own: Array = []
	var cb := func(locked: bool) -> void: bus.append(locked)
	EventBus.player_ability_lock_changed.connect(cb)
	p.ability_lock_changed.connect(func(locked: bool) -> void: own.append(locked))
	p.apply_ability_lock(0.5, null)
	_tick(p, 40)
	EventBus.player_ability_lock_changed.disconnect(cb)
	assert_eq(bus, own)
	assert_eq(bus, [true, false])


func test_event_bus_declares_the_audio_seam_signals_with_their_arity() -> void:
	var args: Dictionary = {}
	for sig: Dictionary in EventBus.get_signal_list():
		args[sig["name"]] = (sig["args"] as Array).map(func(a: Dictionary) -> String: return a["name"])
	assert_eq(args.get(&"player_ability_lock_changed"), ["locked"])
	assert_eq(args.get(&"player_ordnance_hijacked"), ["rocket", "source"])


# --- HUD --------------------------------------------------------------------------------------------------------------

func test_hud_chip_and_glyph_follow_the_lock_in_both_modes() -> void:
	for mode in MODES:
		var p := _player(mode)
		var hud := await _hud(mode)
		hud._process(D)
		assert_false(_chip(hud).visible, "%s: chip hidden while unlocked" % mode)
		assert_false(_glyph(hud).visible, "%s: glyph hidden while unlocked" % mode)
		_jammer(p)
		p._step_disruption(D)
		hud._process(D)
		assert_true(_chip(hud).visible, "%s: chip shown on the lock tick" % mode)
		assert_true(_glyph(hud).visible, "%s: glyph shown on the lock tick" % mode)
		p.global_position += OUT
		_tick(p, 1 + 44)
		hud._process(D)
		assert_true(_chip(hud).visible, "%s: chip shown until the unlock tick" % mode)
		p._step_disruption(D)
		hud._process(D)
		assert_false(_chip(hud).visible, "%s: chip hidden on the unlock tick" % mode)
		assert_false(_glyph(hud).visible, "%s: glyph hidden on the unlock tick" % mode)
		hud.queue_free()
		await get_tree().process_frame


func test_hud_chip_bar_tracks_the_fill_within_one_pixel() -> void:
	for mode in MODES:
		var p := _player(mode)
		var hud := await _hud(mode)
		var full: float = JammedChip.BAR_WIDTH
		assert_gt(full, 20.0, "a readable bar")
		_jammer(p)
		_tick(p, 2)
		hud._process(D)
		assert_almost_eq(_bar(hud).size.x, full, 1.0, "%s: full while held" % mode)
		p.global_position += OUT
		for i in range(1 + 44):
			p._step_disruption(D)
			hud._process(D)
			assert_almost_eq(_bar(hud).size.x, p.ability_lock_fill() * full, 1.0, "%s: tick %d" % [mode, i])
		hud.queue_free()
		await get_tree().process_frame


func test_hud_chip_shows_a_timed_lock_full_then_gone() -> void:
	var p := _player("assault")
	var hud := await _hud("assault")
	p.apply_ability_lock(0.5, null)
	hud._process(D)
	assert_true(_chip(hud).visible)
	assert_almost_eq(_bar(hud).size.x, JammedChip.BAR_WIDTH, 1.0)
	_tick(p, 30)
	hud._process(D)
	assert_false(_chip(hud).visible, "nothing lingers after the unlock")


func test_a_refused_press_flashes_the_chip_red_for_0_2_seconds() -> void:
	for mode in MODES:
		var p := _player(mode)
		var hud := await _hud(mode)
		p.apply_ability_lock(2.0, null)
		hud._process(D)
		var chip := _chip(hud)
		assert_false(bool(chip.call(&"is_flashing")), "%s: calm before a refusal" % mode)
		assert_false(p.allow_ability_press(), "refused")
		hud._process(D)
		assert_true(bool(chip.call(&"is_flashing")), "%s: flashing after a refusal" % mode)
		assert_gt(chip.modulate.r, chip.modulate.g + 0.3, "%s: red" % mode)
		for i in range(10):
			hud._process(D)
		assert_true(bool(chip.call(&"is_flashing")), "%s: still flashing at 0.18 s" % mode)
		for i in range(3):
			hud._process(D)
		assert_false(bool(chip.call(&"is_flashing")), "%s: calm after 0.2 s" % mode)
		assert_eq(chip.modulate, Color.WHITE, "%s: the colour is restored" % mode)
		hud.queue_free()
		await get_tree().process_frame


func test_hud_with_no_player_shows_nothing_and_errors_nothing() -> void:
	for mode in MODES:
		var hud := await _hud(mode)
		for i in range(3):
			hud._process(D)
		assert_false(_chip(hud).visible, "%s: chip hidden" % mode)
		assert_false(_glyph(hud).visible, "%s: glyph hidden" % mode)
		hud.queue_free()
		await get_tree().process_frame
	assert_eq(get_errors().size(), 0, "no engine error logged")


func test_hud_hides_the_chip_when_the_player_is_freed() -> void:
	var p := _player("open_space")
	var hud := await _hud("open_space")
	p.apply_ability_lock(5.0, null)
	hud._process(D)
	assert_true(_chip(hud).visible)
	p.get_parent().remove_child(p)
	p.free()
	hud._process(D)
	assert_false(_chip(hud).visible, "a freed player leaves no chip behind")
	assert_false(_glyph(hud).visible)


func test_hud_picks_up_a_player_that_arrives_after_it() -> void:
	var hud := await _hud("assault")
	hud._process(D)
	var p := _player("assault")
	p.apply_ability_lock(5.0, null)
	hud._process(D)
	assert_true(_chip(hud).visible, "a hub player spawned after the HUD is still tracked")
	assert_false(p.allow_ability_press())
	hud._process(D)
	assert_true(bool(_chip(hud).call(&"is_flashing")), "and its refusals flash the chip")
