extends SceneTree
func _init() -> void: _run.call_deferred()
func _run() -> void:
	for v in ["init_v", "et_v", "ini_v"]:
		var ps: PackedScene = load("res://_probe3/%s.tscn" % v)
		for in_tree in [false, true]:
			var n := ps.instantiate()
			if in_tree: root.add_child(n)
			n.scene_file_path = ""
			var packed := PackedScene.new(); packed.pack(n)
			var out := "res://_probe3/out.tscn"
			ResourceSaver.save(packed, out)
			var txt := FileAccess.get_file_as_string(out)
			print("%-8s in_tree=%-5s sub_resource=%s ext_resource_cfg=%s" % [v, str(in_tree),
				str(txt.contains("[sub_resource")), str(txt.contains("pcfg.tres"))])
			if in_tree: n.free()
			else: n.free()
	quit()
