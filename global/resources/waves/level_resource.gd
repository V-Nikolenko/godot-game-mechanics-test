## LevelResource — ordered list of waves defining a complete level.
## Pass to WaveManager.load_level() instead of calling register_wave() manually.
class_name LevelResource
extends Resource

@export var level_name: String = "Unnamed Level"
@export var waves: Array[WaveResource] = []
