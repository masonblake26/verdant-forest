extends SceneTree
## Times the tree generator and prints each variant's size: godot --headless --path . -s tools/tree_check.gd -- --n=1

const TreeGen := preload("res://tree_gen.gd")

func _init() -> void:
	var n := 1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--n="):
			n = int(a.substr(4))
	for i in n:
		var species: String = ["oak", "beech", "oak", "birch"][i % 4]
		var t0 := Time.get_ticks_msec()
		var g := TreeGen.new()
		var r: Dictionary = g.generate(215 + i * 819, species)
		var parts := []
		for k in 3:
			var w: ArrayMesh = r.wood[k]
			var l: ArrayMesh = r.leaves[k]
			parts.append("%s %dk/%dk tris" % [TreeGen.DETAILS[k], (w.surface_get_array_index_len(0) / 3) / 1000 if w else 0, (l.surface_get_array_index_len(0) / 3) / 1000 if l else 0])
		print("%d %s: %d ms, h %.1f m, leaves %d, %s, trunk r %.2f" % [i, species, Time.get_ticks_msec() - t0, r.height, r.leaf_count, ", ".join(parts), r.trunk_radius])
	quit()
