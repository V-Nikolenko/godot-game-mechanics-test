extends Resource
class_name PlayerDashSettings

@export var enabled: bool = true
@export var dash_speed: float = 300.0
@export var dash_duration: float = 0.2
@export var dash_cooldown: float = 0.5
@export var afterimage_interval: float = 0.05

# Reserved for later upgrade modules such as i-frames or dash damage.
@export var grants_invulnerability: bool = false
@export var damages_targets_on_contact: bool = false
