extends Node3D
## Port of the understory half of app/forest/vegetation.ts. Grass: a pool of 10 m patches kept around the camera
## out to ~90 m; each patch is a MultiMesh of 2,300 clump slots placed on the GPU (shaders/grass.gdshader), switching
## high/medium/low blade detail and thinning by distance. Ferns, shrubs and herbs: placed per 20 m cell with the
## original's rules (trail margins, ground-noise patches, kept off trunks and logs, per-plant tint), bucketed per
## 10 m with high/medium/low detail by visibility range. Individual positions come from per-cell seeded streams
## (the original's single shared stream would mean replaying ~40 million draws in GDScript).

const FM := preload("res://forest_math.gd")
const PG := preload("res://plants_gen.gd")
const SF := preload("res://surfaces.gd")
const PATCH := 10.0
const PER_PATCH := 2300
const GRASS_RADIUS := 9      # patches each side of the camera's patch (~95 m)
const MASK_EXTENT := 400.0
const MASK_RES := 1024

var grass: Array = []        # [high, medium, low] per variant (4 variants)
var ferns: Array = []
var shrubs: Array = []
var herbs: Array = []
var grass_mat := ShaderMaterial.new()
var fern_mat := ShaderMaterial.new()
var shrub_mat := ShaderMaterial.new()
var herb_mat := ShaderMaterial.new()
var mask := Image.create(MASK_RES, MASK_RES, false, Image.FORMAT_R8)
var mask_tex: ImageTexture
var patches := {}            # Vector2i -> MultiMeshInstance3D
var pool: Array = []
var identity := PackedFloat32Array()
var last_center := Vector2i(999999, 999999)
var clock := 0.0
var trees: Node
var surfaces: Node


func _ready() -> void:
	trees = get_parent().get_node_or_null("Vegetation")
	surfaces = get_parent().get_node_or_null("Surfaces")
	var t0 := Time.get_ticks_msec()
	_build_meshes()
	_build_materials()
	_build_mask()
	_place_plants()
	identity.resize(PER_PATCH * 12)
	for i in PER_PATCH:
		identity[i * 12] = 1.0
		identity[i * 12 + 5] = 1.0
		identity[i * 12 + 10] = 1.0
	print("understory: %d ms" % (Time.get_ticks_msec() - t0))


func _build_meshes() -> void:
	var jobs := []
	for i in 4:
		jobs.append(["grass", i]); jobs.append(["fern", i])
	for i in 3:
		jobs.append(["shrub", i])
	for i in 5:
		jobs.append(["herb", i])
	var out := []
	out.resize(jobs.size())
	var task := WorkerThreadPool.add_group_task(func(k: int) -> void:
		var j: Array = jobs[k]
		match j[0]:
			"grass":
				out[k] = [PG.grass(478 + j[1] * 137), PG.grass(478 + j[1] * 137, "medium"), PG.grass(478 + j[1] * 137, "low")]
			"fern":
				out[k] = [PG.fern(137 + j[1] * 411), PG.fern(137 + j[1] * 411, "medium"), PG.fern(137 + j[1] * 411, "low")]
			"shrub":
				out[k] = [PG.shrub(1478 + j[1] * 97), PG.shrub(1478 + j[1] * 97, true)]
			"herb":
				out[k] = [PG.herb([113, 598, 727, 824, 915][j[1]], ["sorrel", "flower", "ivy", "nettle", "ramsons"][j[1]])]
		, jobs.size(), -1, true, "plants")
	WorkerThreadPool.wait_for_group_task_completion(task)
	for k in jobs.size():
		match jobs[k][0]:
			"grass": grass.append(out[k])
			"fern": ferns.append(out[k])
			"shrub": shrubs.append(out[k])
			"herb": herbs.append(out[k])


func _build_materials() -> void:
	grass_mat.shader = load("res://shaders/grass.gdshader")
	grass_mat.set_shader_parameter("per_patch", float(PER_PATCH))
	grass_mat.set_shader_parameter("patch_size", PATCH)
	grass_mat.set_shader_parameter("mask_extent", MASK_EXTENT)
	for pair in [[fern_mat, 2, 0.87], [shrub_mat, 3, 0.87], [herb_mat, 1, 0.87]]:
		var m: ShaderMaterial = pair[0]
		m.shader = load("res://shaders/foliage.gdshader")
		m.set_shader_parameter("kind", pair[1])
		m.set_shader_parameter("roughness", pair[2])


## Footprints the grass shader keeps clear: trunk flares, rock footprints (vegetation.ts blocked: r * 0.85) and logs.
func _build_mask() -> void:
	mask.fill(Color.BLACK)
	if trees:
		for i in trees.positions.size():
			var p: Dictionary = trees.positions[i]
			if absf(p.x) < MASK_EXTENT * 0.5 and absf(p.z) < MASK_EXTENT * 0.5:
				add_footprint(p.x, p.z, trees.variants[p.v].trunk_radius * p.s * 0.75 + 0.045)
	if surfaces:
		for f in surfaces.footprints:
			add_footprint(f[0], f[1], f[2] * 0.85)
		var px := MASK_EXTENT / MASK_RES
		for d in SF.DEADWOOD_PLACEMENTS:
			var reach: float = d[2] * 0.5 + 0.6
			for j in range(floori((d[1] - reach) / px + MASK_RES * 0.5), ceili((d[1] + reach) / px + MASK_RES * 0.5) + 1):
				for i in range(floori((d[0] - reach) / px + MASK_RES * 0.5), ceili((d[0] + reach) / px + MASK_RES * 0.5) + 1):
					if SF.inside_deadwood((i + 0.5 - MASK_RES * 0.5) * px, (j + 0.5 - MASK_RES * 0.5) * px):
						mask.set_pixel(i, j, Color.WHITE)
	mask_tex = ImageTexture.create_from_image(mask)
	grass_mat.set_shader_parameter("block_mask", mask_tex)


func add_footprint(x: float, z: float, r: float) -> void:
	var px := MASK_RES / MASK_EXTENT
	var cx := (x / MASK_EXTENT + 0.5) * MASK_RES
	var cz := (z / MASK_EXTENT + 0.5) * MASK_RES
	var rr := r * px
	for j in range(floori(cz - rr), ceili(cz + rr) + 1):
		for i in range(floori(cx - rr), ceili(cx + rr) + 1):
			if i >= 0 and j >= 0 and i < MASK_RES and j < MASK_RES and Vector2(i - cx, j - cz).length() <= rr:
				mask.set_pixel(i, j, Color.WHITE)


func refresh_mask() -> void:
	mask_tex.update(mask)


func _blocked(x: float, z: float) -> bool:
	var u := floori((x / MASK_EXTENT + 0.5) * MASK_RES)
	var v := floori((z / MASK_EXTENT + 0.5) * MASK_RES)
	return (u >= 0 and v >= 0 and u < MASK_RES and v < MASK_RES and mask.get_pixel(u, v).r > 0.5) \
		or (surfaces != null and SF.inside_deadwood(x, z))


func _place_plants() -> void:
	var catalog := [
		{"kind": "fern", "geos": ferns, "mat": fern_mat, "count": 165, "ranges": [10.0, 24.0, 70.0], "shadow": true},
		{"kind": "shrub", "geos": shrubs, "mat": shrub_mat, "count": 21, "ranges": [16.0, 100.0], "shadow": true},
		{"kind": "herb", "geos": herbs, "mat": herb_mat, "count": 160, "ranges": [48.0], "shadow": false},
	]
	for ci in catalog.size():
		var item: Dictionary = catalog[ci]
		for cz in range(-10, 10):
			for cx in range(-10, 10):
				var center := Vector2(cx * 20.0 + 10.0, cz * 20.0 + 10.0)
				var outside := absf(center.x) > 120.0 or absf(center.y) > 120.0
				var capacity: int = floori(item.count * (0.55 if outside else 1.0))
				var variant: int = absi(cx * 31 + cz * 17) % item.geos.size()
				var r := FM.rng(FM.hash_seed("%s:%d:%d" % [item.kind, cx, cz]))
				var buckets := [[], [], [], []]
				for i in capacity:
					var x: float = cx * 20.0 + r.call() * 20.0
					var z: float = cz * 20.0 + r.call() * 20.0
					var d := FM.trail_distance(x, z)
					var n := FM.noise(x * 0.19 + 11.0, z * 0.19)
					if d < 0.34 and r.call() < 0.77:
						continue
					if item.kind == "fern" and (d < 0.85 or n < 0.23):
						continue
					if item.kind == "shrub" and (d < 1.8 or n < 0.31):
						continue
					if _blocked(x, z):
						continue
					var y := FM.height_at(x, z) - 0.015
					var pitch: float = (r.call() - 0.5) * 0.12
					var yaw: float = r.call() * 6.28
					var roll: float = (r.call() - 0.5) * 0.12
					var scale: float = (0.55 + r.call() * 0.84) if item.kind == "fern" else ((0.6 + r.call() * 0.8) if item.kind == "shrub" else (0.8 + r.call() * 0.8))
					if d < 0.68:
						scale *= 0.28
					var sx: float = scale * (0.8 + r.call() * 0.4)
					var sz: float = scale * (0.8 + r.call() * 0.4)
					var col := Color(0.83 + r.call() * 0.28, 0.85 + r.call() * 0.22, 0.8 + r.call() * 0.3)
					var basis := Basis.from_euler(Vector3(pitch, yaw, roll), EULER_ORDER_XYZ) * Basis.from_scale(Vector3(sx, scale, sz))
					var q := (1 if x >= center.x else 0) + (2 if z >= center.y else 0)
					buckets[q].append([Transform3D(basis, Vector3(x, y, z)), col])
				for q in 4:
					if buckets[q].is_empty():
						continue
					var bc := Vector2(center.x + (5.0 if q % 2 else -5.0), center.y + (5.0 if q > 1 else -5.0))
					var origin := Vector3(bc.x, FM.height_at(bc.x, bc.y), bc.y)
					var lods: Array = item.geos[variant]
					var ranges: Array = item.ranges
					for level in ranges.size():
						var mm := MultiMesh.new()
						mm.transform_format = MultiMesh.TRANSFORM_3D
						mm.use_colors = true
						mm.mesh = lods[mini(level, lods.size() - 1)]
						mm.instance_count = buckets[q].size()
						var inv := Transform3D(Basis.IDENTITY, -origin)
						for k in buckets[q].size():
							mm.set_instance_transform(k, inv * buckets[q][k][0])
							mm.set_instance_color(k, buckets[q][k][1])
						var mi := MultiMeshInstance3D.new()
						mi.multimesh = mm
						mi.material_override = item.mat
						mi.position = origin
						mi.visibility_range_begin = 0.0 if level == 0 else ranges[level - 1]
						mi.visibility_range_end = ranges[level]
						mi.visibility_range_begin_margin = 2.0 if level > 0 else 0.0
						mi.visibility_range_end_margin = 2.0
						mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
						mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if item.shadow and level < 2 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
						add_child(mi)


## Grass patches follow the camera: a (2R+1)^2 pool re-targeted whenever the camera crosses a patch boundary;
## each patch's blade detail and drawn share follow its distance (the original's LOD and density steps).
func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp := Vector2(cam.global_position.x, cam.global_position.z)
	var center := Vector2i(floori(cp.x / PATCH), floori(cp.y / PATCH))
	if center != last_center:
		last_center = center
		var want := {}
		for dz in range(-GRASS_RADIUS, GRASS_RADIUS + 1):
			for dx in range(-GRASS_RADIUS, GRASS_RADIUS + 1):
				want[center + Vector2i(dx, dz)] = true
		for key in patches.keys():
			if not want.has(key):
				pool.append(patches[key])
				patches.erase(key)
		for key in want:
			if patches.has(key):
				continue
			var mi: MultiMeshInstance3D = pool.pop_back() if not pool.is_empty() else _new_patch()
			var o := Vector2(key.x * PATCH, key.y * PATCH)
			var c := o + Vector2(PATCH * 0.5, PATCH * 0.5)
			mi.position = Vector3(c.x, FM.height_at(c.x, c.y), c.y)
			mi.set_instance_shader_parameter("patch_origin", o)
			mi.set_meta("center", c)
			mi.set_meta("variant", absi(key.x * 31 + key.y * 17) % 4)
			mi.set_meta("lod", -1)
			patches[key] = mi
		clock = 0.0
	clock -= delta
	if clock > 0.0:
		return
	clock = 0.3
	for key in patches:
		var mi: MultiMeshInstance3D = patches[key]
		var c: Vector2 = mi.get_meta("center")
		var d := cp.distance_to(c)
		var lod := 0 if d < 9.0 else (1 if d < 23.0 else 2)
		if lod != mi.get_meta("lod"):
			mi.set_meta("lod", lod)
			mi.multimesh.mesh = grass[mi.get_meta("variant")][lod]
		var outside := absf(c.x) > 120.0 or absf(c.y) > 120.0
		var count := floori(PER_PATCH * (0.55 if outside else 1.0))
		mi.multimesh.visible_instance_count = mini(count, ceili(count * (_density(maxf(0.0, d - 7.5)) + 0.029)))
		mi.visible = d < 95.0


func _new_patch() -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = grass[0][2]
	mm.instance_count = PER_PATCH
	mm.buffer = identity
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = grass_mat
	mi.custom_aabb = AABB(Vector3(-PATCH * 0.5 - 1.0, -3.0, -PATCH * 0.5 - 1.0), Vector3(PATCH + 2.0, 6.0, PATCH + 2.0))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


static func _density(d: float) -> float:
	if d < 22.0:
		return 1.0
	if d < 36.0:
		return lerpf(1.0, 0.55, (d - 22.0) / 14.0)
	if d < 51.0:
		return lerpf(0.55, 0.22, (d - 36.0) / 15.0)
	if d < 70.0:
		return lerpf(0.22, 0.1, (d - 51.0) / 19.0)
	return lerpf(0.1, 0.0, clampf((d - 70.0) / 18.0, 0.0, 1.0))
