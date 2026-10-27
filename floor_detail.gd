extends Node3D
## Port of floor-detail.ts: the tiny things where a walker looks: wood sorrel, star moss, curled dry leaves, grass
## seedheads and pebbles, gathered at the trail margins, along the logs and round the tree bases (no global blanket),
## kept off trunk flares, rocks and logs. One batch per 12 m cell and kind, shown within the original's ranges.

const FM := preload("res://forest_math.gd")
const FL := preload("res://flowers.gd")
const SF := preload("res://surfaces.gd")
const KINDS := ["sorrel", "moss-star", "curled-litter", "seedheads", "pebbles"]
const RANGE := [27.0, 20.0, 20.0, 42.0, 20.0]

var batches: Array = []     # [MultiMeshInstance3D, Vector3 center, radius, kind]
var clock := 0.3


static func _c(hex: String) -> Color:
	return Color(hex).srgb_to_linear()


static func geometry(kind: String, seed: int) -> ArrayMesh:
	var r := FM.rng(seed)
	var b := FL.B.new()
	if kind == "sorrel":
		# three heart-shaped leaflets per slender petiole, a folded midrib and a real notch at each tip
		for shoot in 4:
			var a: float = r.call() * TAU
			var h: float = 0.045 + r.call() * 0.085
			var bx: float = (r.call() - 0.5) * 0.11
			var base := Vector3(bx, 0.0, (r.call() - 0.5) * 0.11)
			var top := base + Vector3(cos(a) * 0.025, h, sin(a) * 0.025)
			FL.stem(b, [base, base.lerp(top, 0.5), top], 0.0018, _c("#719345"))
			for leaf in 3:
				var angle := a + leaf * TAU / 3.0
				var axis := Vector3(cos(angle), 0.0, sin(angle))
				var side := Vector3(-sin(angle), 0.0, cos(angle))
				var length: float = 0.036 + r.call() * 0.012
				var root := b.vertex(top, _c("#3c682c"), 0.5, 0.0)
				var mid := b.vertex(top + axis * (length * 0.55) + Vector3(0, 0.006, 0), _c("#608b35"), 0.5, 0.55)
				var outline := [[-0.25, 0.26], [-0.59, 0.60], [-0.52, 0.96], [-0.22, 1.04], [0, 0.86], [0.22, 1.04], [0.52, 0.96], [0.59, 0.60], [0.25, 0.26]]
				var ids := []
				for o in outline:
					var x: float = o[0]; var z: float = o[1]
					ids.append(b.vertex(top + axis * (z * length) + side * (x * length) + Vector3(0, absf(x) * -0.008 + z * 0.008, 0), _c("#567f32"), x + 0.5, z))
				b.tri(root, ids[0], mid)
				for i in ids.size() - 1:
					b.tri(mid, ids[i], ids[i + 1])
				b.tri(mid, ids[ids.size() - 1], root)
	elif kind == "moss-star":
		for shoot in 11:
			var angle: float = r.call() * TAU
			var radius := sqrt(r.call()) * 0.067
			var base := Vector3(cos(angle) * radius, 0.003, sin(angle) * radius)
			var h: float = 0.018 + r.call() * 0.03
			var top := base + Vector3(0, h, 0)
			FL.stem(b, [base, top], 0.0012, _c("#5c6f30"))
			for j in 5:
				FL.leaf(b, top + Vector3(0, -h * 0.3, 0), angle + j * TAU / 5.0, 0.019 + r.call() * 0.012, 0.005,
					_c("#658436" if j % 2 else "#769743"), 0.5, 3)
	elif kind == "curled-litter":
		for leaf in 3:
			var a: float = r.call() * TAU
			var bx: float = (r.call() - 0.5) * 0.12
			var base := Vector3(bx, 0.01, (r.call() - 0.5) * 0.12)
			var length: float = 0.075 + r.call() * 0.08
			var width := length * 0.43
			var axis := Vector3(cos(a), 0, sin(a))
			var side := Vector3(-sin(a), 0, cos(a))
			var rows := []
			for i in 8:
				var t := i / 7.0
				var w := pow(sin(t * PI), 0.68) * width * 0.5 * (0.73 if i % 2 else 1.12)
				var center := base + axis * (length * t)
				center.y += pow(t, 3.0) * length * 0.20
				var row := []
				var color := _c("#94703c" if leaf % 2 else "#b27b3d")
				if i == 0 or i == 7:
					row.append(b.vertex(center, color, 0.5, t))
				else:
					for s: int in [-1, 0, 1]:
						var p := center + side * (s * w)
						p.y += 0.003 if s == 0 else w * 0.34
						var k: float = 0.72 + r.call() * 0.25
						row.append(b.vertex(p, Color(color.r * k, color.g * k, color.b * k), (s + 1) * 0.5, t))
				rows.append(row)
			for i in 7:
				var ra: Array = rows[i]
				var rc: Array = rows[i + 1]
				if ra.size() == 1:
					b.tri(ra[0], rc[0], rc[1]); b.tri(ra[0], rc[1], rc[2])
				elif rc.size() == 1:
					b.tri(ra[0], rc[0], ra[1]); b.tri(ra[1], rc[0], ra[2])
				else:
					for j in 2:
						b.tri(ra[j], rc[j], ra[j + 1]); b.tri(ra[j + 1], rc[j], rc[j + 1])
			FL.stem(b, [base - axis * 0.025, base, base + axis * (length * 0.55) + Vector3(0, 0.012, 0)], 0.0017, _c("#785735"))
	elif kind == "seedheads":
		for i in 3:
			var a: float = r.call() * TAU
			var h: float = 0.42 + r.call() * 0.27
			var lean: float = 0.04 + r.call() * 0.06
			var at := func(t: float) -> Vector3: return Vector3(cos(a) * lean * t * t, h * t, sin(a) * lean * t * t)
			var stem_c := _c("#887544")
			var pts := []
			for j in 6:
				pts.append(at.call(j / 5.0))
			FL.stem(b, pts, 0.0025, stem_c)
			for j in 3:
				FL.leaf(b, at.call(0.15 + j * 0.17), a + j * 2.4, 0.13, 0.009, _c("#73834d"), 0.6, 4)
			for j in 7:
				var t := 0.72 + j * 0.034
				var center: Vector3 = at.call(t)
				var angle := a + j * 2.38
				var reach := 0.033 * (1.0 - (t - 0.72) * 2.0)
				var end := center + Vector3(cos(angle) * reach, 0.01, sin(angle) * reach)
				FL.stem(b, [center, end], 0.0014, stem_c, 3)
				for sgn in [-1.0, 1.0]:
					FL.leaf(b, end, angle + sgn * 0.29, 0.025, 0.006, _c("#9b8260"), 0.45, 3)
	else:
		return pebble(seed)
	return b.finish()


## IcosahedronGeometry(1, 1), merged and smooth: a small grey pebble dented by noise, a little squashed.
static func pebble(seed: int) -> ArrayMesh:
	var b := FL.B.new()
	var ids := {}
	var n := 2
	for f in range(0, SF.ICO_F.size(), 3):
		var c3 := []
		for k in 3:
			var v: Array = SF.ICO_V[SF.ICO_F[f + k]]
			c3.append(Vector3(v[0], v[1], v[2]))
		var grid := []
		for i in n + 1:
			var row := []
			for j in n - i + 1:
				var p: Vector3 = ((c3[0] * (n - i - j) + c3[1] * j + c3[2] * i) / n).normalized()
				var key := Vector3i((p * 10000.0).round())
				if not ids.has(key):
					var s := 0.84 + FM.noise(p.x * 4.0 + seed, p.z * 3.0 + p.y) * 0.24
					var k := 0.77 + FM.noise(p.x * 11.0, p.z * 14.0) * 0.25
					var col := _c("#8d8970")
					ids[key] = b.vertex(Vector3(p.x * s * 0.033, (p.y * s + 0.75) * 0.019, p.z * s * 0.026), Color(col.r * k, col.g * k, col.b * k))
				row.append(ids[key])
			grid.append(row)
		for i in n:
			for j in n - i:
				b.tri(grid[i][j], grid[i][j + 1], grid[i + 1][j])
				if j < n - i - 1:
					b.tri(grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j])
	return b.finish()


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	var trees: Node = get_parent().get_node_or_null("Vegetation")
	var surfaces: Node = get_parent().get_node_or_null("Surfaces")
	# wildflowers.ts createFloorExclusion: trunk flares, rock footprints and the logs
	var grid := {}
	var put := func(x: float, z: float, rad: float) -> void:
		var key := Vector2i(floori(x / 6.0), floori(z / 6.0))
		if not grid.has(key):
			grid[key] = []
		grid[key].append([x, z, rad])
	var tree_list := []
	if trees:
		for p: Dictionary in trees.positions:
			if absf(p.x) > 140.0 or absf(p.z) > 140.0:
				continue
			var rad: float = trees.variants[p.v].trunk_radius * p.s * 0.75 + 0.045
			put.call(p.x, p.z, rad + 0.1)
			tree_list.append([p.x, p.z, rad])
	if surfaces:
		for f in surfaces.footprints:
			put.call(f[0], f[1], f[2] + 0.08)
	var blocked := func(x: float, z: float) -> bool:
		var gx := floori(x / 6.0); var gz := floori(z / 6.0)
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				for q in grid.get(Vector2i(gx + dx, gz + dz), []):
					if (q[0] - x) * (q[0] - x) + (q[1] - z) * (q[1] - z) < q[2] * q[2]:
						return true
		return SF.inside_deadwood(x, z)

	var r := FM.rng(909127)
	var cells := {}
	var add := func(x: float, z: float, kind: int, scale: float) -> void:
		if blocked.call(x, z):
			return
		if kind != 2 and kind != 4 and FM.trail_distance(x, z) < 0.47:
			return
		var key := Vector3i(floori(x / 12.0), floori(z / 12.0), kind)
		if not cells.has(key):
			cells[key] = []
		var yaw: float = r.call() * TAU
		var s: float = scale * (0.68 + r.call() * 0.77)
		cells[key].append([x, z, yaw, s, 0.84 + r.call() * 0.23])
	# path margins, leaf pockets, deadwood margins and rooted tree islands
	for i in 13500:
		var z: float = (r.call() - 0.5) * 226.0
		var side := -1.0 if r.call() < 0.5 else 1.0
		var d: float = r.call()
		var off: float = r.call() * 0.58 if d < 0.23 else 0.7 + pow(r.call(), 1.8) * 5.2
		var x := FM.trail_at(z) + side * off
		var band := FM.noise(x * 0.73 + 91.0, z * 0.73)
		var kind := 4 if d < 0.15 else (2 if d < 0.38 else (1 if band < 0.31 else (0 if band < 0.67 else 3)))
		if kind == 3 and r.call() < 0.60:
			continue
		add.call(x, z, kind, 1.1 if kind == 0 else 1.0)
	# low sorrel and velvet moss fringing the bare tread, where the grass is shortest
	for i in 1450:
		var z: float = (r.call() - 0.5) * 207.0
		var side := -1.0 if r.call() < 0.5 else 1.0
		var x: float = FM.trail_at(z) + side * (0.49 + r.call() * 0.29)
		if FM.noise(z * 0.33 + 42.0, side * 0.76) > 0.23:
			add.call(x, z, 1 if i % 3 == 0 else 0, 0.84)
	for dw in SF.DEADWOOD_PLACEMENTS:
		var c := cos(dw[4]); var s := sin(dw[4])
		for i in 160:
			var along: float = (r.call() - 0.5) * (dw[2] + 0.7)
			var across: float = (-1.0 if r.call() < 0.5 else 1.0) * (0.48 + r.call() * 0.8)
			add.call(dw[0] + along * c - across * s, dw[1] - along * s - across * c, 2 if i % 5 == 0 else (0 if i % 3 == 0 else 1), 1.14)
	for t in tree_list:
		if Vector2(t[0], t[1]).length() > 99.0:
			continue
		for i in 25:
			var a: float = r.call() * TAU
			var d: float = t[2] + 0.12 + r.call() * 0.93
			add.call(t[0] + cos(a) * d, t[1] + sin(a) * d, 2 if i % 4 == 0 else (1 if i % 3 == 0 else 0), 1.0)

	var geos := []
	for i in KINDS.size():
		geos.append(geometry(KINDS[i], 782 + i * 193))
	var live := ShaderMaterial.new()
	live.shader = load("res://shaders/foliage.gdshader")
	live.set_shader_parameter("kind", 3)
	live.set_shader_parameter("roughness", 0.94)
	var dry := StandardMaterial3D.new()
	dry.vertex_color_use_as_albedo = true
	dry.roughness = 0.96
	dry.cull_mode = BaseMaterial3D.CULL_DISABLED
	var amounts := [0, 0, 0, 0, 0]
	for key: Vector3i in cells:
		var plants: Array = cells[key]
		var kind := key.z
		var center := Vector2(key.x * 12.0 + 6.0, key.y * 12.0 + 6.0)
		var origin := Vector3(center.x, FM.height_at(center.x, center.y), center.y)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = geos[kind]
		mm.instance_count = plants.size()
		for i in plants.size():
			var p: Array = plants[i]
			var x: float = p[0]; var z: float = p[1]
			var basis := Basis(Vector3.UP, p[2])
			if kind == 2 or kind == 4:   # dry leaves and pebbles lie along the slope
				var sx := (FM.height_at(x + 0.12, z) - FM.height_at(x - 0.12, z)) / 0.24
				var sz := (FM.height_at(x, z + 0.12) - FM.height_at(x, z - 0.12)) / 0.24
				basis = Basis(Quaternion(Vector3.UP, Vector3(-sx, 1.0, -sz).normalized())) * basis
			mm.set_instance_transform(i, Transform3D(basis.scaled(Vector3.ONE * p[3]), Vector3(x, FM.height_at(x, z) - 0.008, z) - origin))
			mm.set_instance_color(i, Color(p[4], p[4], p[4]))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = dry if kind == 2 or kind == 4 else live
		mi.position = origin
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		var aabb := mm.get_aabb()
		batches.append([mi, origin + aabb.get_center(), aabb.size.length() * 0.5, kind])
		amounts[kind] += plants.size()
	print("floor detail: sorrel %d, moss %d, curled leaves %d, seedheads %d, pebbles %d, %d ms" % (amounts + [Time.get_ticks_msec() - t0]))


func _process(delta: float) -> void:
	clock += delta
	if clock < 0.3:
		return
	clock = 0.0
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var c := cam.global_position
	for bt in batches:
		var d: float = c.distance_to(bt[1])
		bt[0].visible = d < bt[2] + RANGE[bt[3]]
		if bt[3] == 3:
			bt[0].cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if d < bt[2] + 18.0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
