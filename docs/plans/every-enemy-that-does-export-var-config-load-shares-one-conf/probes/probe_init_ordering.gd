extends SceneTree
func _init() -> void: _run.call_deferred()
func _run() -> void:
	var shared := load("res://_probe3/pcfg.tres")
	var ps: PackedScene = load("res://_probe3/derived.tscn")
	var a := ps.instantiate()
	print("PRE-ADD: a.config == shared -> ", a.config == shared)
	a.config.max_health = 13   # the hazardous pre-add write
	var b := ps.instantiate()
	print("after pre-add write, fresh instance b.max_health = ", b.config.max_health, " (shipped 100)")
	print("shared.max_health = ", shared.max_health)
	root.add_child(a); root.add_child(b)
	print("a.config == b.config -> ", a.config == b.config)
	a.free(); b.free(); quit()
