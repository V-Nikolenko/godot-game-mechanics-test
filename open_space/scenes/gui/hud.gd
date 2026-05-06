# open_space/scenes/gui/hud.gd
extends CanvasLayer

@onready var health_shield_bar: HealthShieldBar = $HealthShieldBar

func _ready() -> void:
	## Wait one frame for the player to be ready.
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var p := players[0]
	var health := p.get_node_or_null("HealthComponent") as Health
	var shield := p.get_node_or_null("ShieldComponent") as Shield
	if health and shield:
		health_shield_bar.setup(health, shield)
