# global/ship_modules/plasma_nova_module.gd
class_name PlasmaNovaModule
extends ShipModuleBase

const _DAMAGE: int = 50
const _COOLDOWN: float = 30.0

## Visual constants.
const _FLASH_COLOR: Color = Color(0.85, 0.5, 1.0, 0.75)
const _FLASH_CANVAS_LAYER: int = 128
const _FLASH_FADE_DURATION: float = 0.5

var _cooldown_left: float = 0.0

func get_display_name() -> String: return "Plasma Nova"
func get_description() -> String:
	return "Press H to release a burst of superheated plasma. Deals 50 damage to every enemy on screen simultaneously. 30-second cooldown."
func get_icon() -> Texture2D:
	return null
func get_slot() -> StringName: return &"weapons"

func apply(_player: Node) -> void:
	pass

func remove(_player: Node) -> void:
	pass

func try_activate(player: Node) -> bool:
	if _cooldown_left > 0.0:
		return false
	_cooldown_left = _COOLDOWN

	## Damage all enemies.
	var enemies := player.get_tree().get_nodes_in_group("enemies")
	for e: Node in enemies:
		var n := e as Node2D
		if n == null:
			continue
		var hb := n.get_node_or_null("HurtBox") as HurtBox
		if hb:
			hb.received_damage.emit(_DAMAGE)

	## Screen-wide purple flash.
	_spawn_flash(player as Node2D)
	return true

func tick(_player: Node, delta: float) -> void:
	if _cooldown_left > 0.0:
		_cooldown_left -= delta

func _spawn_flash(actor: Node2D) -> void:
	var overlay := ColorRect.new()
	overlay.color = _FLASH_COLOR
	var canvas := CanvasLayer.new()
	canvas.layer = _FLASH_CANVAS_LAYER
	canvas.add_child(overlay)
	actor.get_tree().root.add_child(canvas)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var t := canvas.create_tween()
	t.tween_property(overlay, "modulate:a", 0.0, _FLASH_FADE_DURATION)
	t.tween_callback(canvas.queue_free)
