extends CharacterBody2D

@onready var hurt_box: HurtBox = $HurtBox
@onready var heatlh_component: Health = $HealthComponent
@onready var overheat_component: Overheat = $OverheatComponent

var can_attack: bool = true

func _ready() -> void:
	overheat_component.overheat.connect(handle_overheat)

func handle_overheat(overheat_percentage: float) -> void:
	if (overheat_percentage >= 100):
		can_attack = false
		return
	
	if (overheat_percentage >= 80 && !can_attack):
		return
	
	if (overheat_percentage < 80 && !can_attack):
		can_attack = true
		return
	
