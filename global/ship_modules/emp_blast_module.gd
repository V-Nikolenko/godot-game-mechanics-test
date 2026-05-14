# global/ship_modules/emp_blast_module.gd
class_name EMPBlastModule
extends ShipModuleBase

const _STUN_DURATION: float = 5.0
const _COOLDOWN: float = 15.0

## Classes/groups that are immune to the EMP stun.
const _IMMUNE_CLASSES: Array[String] = ["BigAsteroid", "SmallAsteroid", "Asteroid", "RamShip"]

var _cooldown_left: float = 0.0

func get_display_name() -> String: return "EMP Blast"
func get_description() -> String:
	return "Press H to emit a ship-wide electromagnetic pulse. Stuns all nearby enemies for 5 seconds. 15-second cooldown. Asteroids and ram ships are immune."
func get_icon() -> Texture2D:
	return null
func get_slot() -> StringName: return &"cockpit"

func apply(_player: Node) -> void:
	pass  ## No passive effect.

func remove(_player: Node) -> void:
	pass  ## Cooldown just stops ticking; no cleanup needed.

func try_activate(player: Node) -> bool:
	if _cooldown_left > 0.0:
		return false
	_cooldown_left = _COOLDOWN
	_spawn_emp_visual(player as Node2D)
	var enemies := player.get_tree().get_nodes_in_group("enemies")
	for e: Node in enemies:
		if _is_immune(e):
			continue
		_stun_enemy(e, player)
	return true

func tick(_player: Node, delta: float) -> void:
	if _cooldown_left > 0.0:
		_cooldown_left -= delta

func _is_immune(node: Node) -> bool:
	for class_name_str: String in _IMMUNE_CLASSES:
		if node.is_class(class_name_str):
			return true
		var scr: Script = node.get_script() as Script
		if scr != null and scr.get_global_name() == class_name_str:
			return true
	return false

func _stun_enemy(enemy: Node, player: Node) -> void:
	if enemy.process_mode == Node.PROCESS_MODE_DISABLED:
		return  ## Already stunned.
	enemy.set_process_mode(Node.PROCESS_MODE_DISABLED)
	var timer := player.get_tree().create_timer(_STUN_DURATION)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(enemy):
			enemy.set_process_mode(Node.PROCESS_MODE_INHERIT)
	)

func _spawn_emp_visual(actor: Node2D) -> void:
	if actor == null:
		return
	var ring := Node2D.new()
	actor.get_parent().add_child(ring)
	ring.global_position = actor.global_position
	var line := Line2D.new()
	line.width = 4.0
	line.default_color = Color(0.2, 1.0, 0.5, 0.9)
	var pts: PackedVector2Array
	for i: int in 33:
		var angle: float = TAU * i / 32
		pts.append(Vector2(cos(angle), sin(angle)) * 10.0)
	line.points = pts
	ring.add_child(line)
	var t := ring.create_tween()
	t.tween_property(ring, "scale", Vector2(80.0, 80.0), 0.35) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(line, "modulate:a", 0.0, 0.35)
	t.tween_callback(ring.queue_free)
