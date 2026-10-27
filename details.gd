extends Node3D
## Port of details.ts and trunk-life.ts: moss shoots sampled straight off the rock and log surfaces (no air gap),
## terrain-following exposed roots, scattered twigs and acorns, climbing ivy fixed to the real trunk rings, and
## bracket fungus shelves (fungus.gd). Distances are checked every 0.3 s, as the original's update(camera).

const FM := preload("res://forest_math.gd")
const FL := preload("res://flowers.gd")
const SF := preload("res://surfaces.gd")
const TreeGen := preload("res://tree_gen.gd")
const Fungus := preload("res://fungus.gd")

var moss_cells: Array = []      # [MultiMeshInstance3D, Vector2 center]
var roots: Array = []           # [MeshInstance3D, Vector2 center]
var attached: Array = []        # [[MeshInstance3D...], Vector2 center] (ivy and fungus, per tree)
var stats := {}
var clock := 0.3


static func _hsl(h: float, s: float, l: float) -> Color:
	# three.js Color.setHSL in its (linear) working space
	h = fposmod(h, 1.0)
	s = clampf(s, 0.0, 1.0)
	l = clampf(l, 0.0, 1.0)
	if s == 0.0:
		return Color(l, l, l)
	var q := l * (1.0 + s) if l <= 0.5 else l + s - l * s
	var p := 2.0 * l - q
	return Color(FL._hue(p, q, h + 1.0 / 3.0), FL._hue(p, q, h), FL._hue(p, q, h - 1.0 / 3.0))


## three.js TubeGeometry over points already spaced along the curve: rings of radial + 1 (seam doubled), the frame
## carried along the path, ring offset -cos N + sin B, faces (a, b, d) (b, c, d). `along` > 0 swaps to bark UVs
## (around, distance / along), as details.ts does for roots.
static func tube(b: FL.B, pts: Array, radii, radial: int, col: Color, squash := 1.0, along := 0.0) -> void:
	var n := pts.size()
	var first := ((pts[1] as Vector3) - (pts[0] as Vector3)).normalized()
	var nrm: Vector3 = TreeGen.frame(first)[0]
	var base := b.p.size()
	var dist := 0.0
	for i in n:
		var tg := ((pts[mini(i + 1, n - 1)] as Vector3) - (pts[maxi(i - 1, 0)] as Vector3)).normalized()
		nrm = (nrm - tg * nrm.dot(tg))
		if nrm.length_squared() < 1e-10:
			nrm = TreeGen.frame(tg)[0]
		nrm = nrm.normalized()
		var bin := tg.cross(nrm)
		if i > 0:
			dist += (pts[i] as Vector3).distance_to(pts[i - 1])
		var r: float = radii[i] if radii is Array else radii
		for j in radial + 1:
			var a := float(j) / radial * TAU
			var off := (nrm * -cos(a) + bin * sin(a)) * r
			off.y *= squash
			var t := float(i) / (n - 1)
			var uv := Vector2(float(j) / radial, t * along) if along > 0.0 else Vector2(t, float(j) / radial)
			b.vertex(pts[i] + off, col, uv.x, uv.y)
	for i in range(1, n):
		for j in range(1, radial + 1):
			var a := base + (radial + 1) * (i - 1) + (j - 1)
			var bb := base + (radial + 1) * i + (j - 1)
			var c := base + (radial + 1) * i + j
			var d := base + (radial + 1) * (i - 1) + j
			b.tri(a, bb, d); b.tri(bb, c, d)


static func _mesh_instance(mesh: Mesh, mat: Material, xf: Transform3D, shadows: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = xf
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	var trees: Node = get_parent().get_node_or_null("Vegetation")
	var surfaces: Node = get_parent().get_node_or_null("Surfaces")
	var r := FM.rng(846291)
	_moss(surfaces)
	if trees:
		_roots(trees)
	_twigs(r)
	if trees:
		_acorns(r, trees)
		_trunk_life(trees)
	print("details: %s, %d ms" % [stats, Time.get_ticks_msec() - t0])


# --- moss on stones and logs -------------------------------------------------------------------------------------

static func moss_clump(seed: int) -> ArrayMesh:
	var r := FM.rng(seed)
	var b := FL.B.new()
	for shoot in 9:
		var a: float = r.call() * TAU
		var h: float = 0.018 + r.call() * 0.055
		var bx: float = (r.call() - 0.5) * 0.045
		var bz: float = (r.call() - 0.5) * 0.045
		var stem := Vector3(bx, 0.0, bz)
		var tip := Vector3(bx + cos(a) * h * 0.25, h, bz + sin(a) * h * 0.25)
		var hh: float = 0.23 + r.call() * 0.035
		var ss: float = 0.42 + r.call() * 0.14
		var color := _hsl(hh, ss, 0.095 + r.call() * 0.055)
		for j in range(1, 7):
			var t := j / 7.0
			var center := stem.lerp(tip, t)
			var spread := (1.0 - t) * 0.0055 + 0.0008
			var dir := Vector3(cos(a + j * 2.4), 0.48, sin(a + j * 2.4)).normalized()
			var side := dir.cross(Vector3.UP).normalized() * (spread * 0.24)
			var end := center + dir * spread
			var i0 := b.vertex(center + side, color, 1.0, 0.0)
			var i1 := b.vertex(center - side, color, 0.0, 0.0)
			var i2 := b.vertex(end, color, 1.0, 1.0)
			b.tri(i0, i1, i2)
	return b.finish()


## details.ts sampleSurface: random triangles of the transformed mesh, kept where they face up (normal.y >= 0.24),
## stand clear of the ground and fall in a noise patch. One seeded stream per stone or log (the original ran one
## stream through all of them; the look is the same). The exact ground test runs only below the highest ground
## under the stone, only up-facing triangles are drawn, and the RNG and noise hash are inlined (4.5 s -> 2.1 s).
## forest_math noise with the hash inlined (the same values; the static calls dominated the moss start-up).
static func _noise(x: float, z: float) -> float:
	var ix := floori(x)
	var iz := floori(z)
	var a := x - ix
	var b := z - iz
	var u := a * a * (3.0 - 2.0 * a)
	var v := b * b * (3.0 - 2.0 * b)
	var hv := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	for k in 4:
		var h := ((((ix + (k & 1)) & 0xFFFFFFFF) * 374761393) + (((iz + (k >> 1)) & 0xFFFFFFFF) * 668265263)) & 0xFFFFFFFF
		h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
		hv[k] = float(h ^ (h >> 16)) / 4294967295.0
	return (hv[0] * (1.0 - u) + hv[1] * u) * (1.0 - v) + (hv[2] * (1.0 - u) + hv[3] * u) * v


func _moss_source(i: int, sources: Array, results: Array) -> void:
	var src: Array = sources[i]
	var p: PackedVector3Array = src[0]
	var gi: PackedInt32Array = src[1]
	var world: Transform3D = src[2]
	var count: int = src[3]
	var scale: float = src[4]
	var reach: float = src[5]
	var ground_max := -INF
	for k in 9:
		var gx := world.origin.x + (k % 3 - 1) * reach
		var gz := world.origin.z + (k / 3 - 1) * reach
		ground_max = maxf(ground_max, FM.height_at(gx, gz))
	ground_max += 0.35 + reach * 0.08   # slack for convex ground between the nine samples
	# Down-facing triangles were drawn and thrown away; draw only from the up-facing ones, in the same proportion.
	var nb := world.basis.inverse().transposed()
	var tri_a := PackedVector3Array(); var tri_e1 := PackedVector3Array(); var tri_e2 := PackedVector3Array()
	var tri_n := PackedVector3Array()
	var all := gi.size() / 3
	for k in range(0, gi.size(), 3):
		var a := p[gi[k]]; var bb := p[gi[k + 2]]; var c := p[gi[k + 1]]   # back to three.js winding
		var normal := (nb * (bb - a).cross(c - a)).normalized()
		if normal.y < 0.24:
			continue
		var wa := world * a
		tri_a.append(wa); tri_e1.append(world * bb - wa); tri_e2.append(world * c - wa); tri_n.append(normal)
	var tris := tri_a.size()
	var draws := roundi(count * float(tris) / all)
	var st := (846291 + i * 7919) & FM.MASK
	var out := []
	var rv := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0])
	for n in draws:
		# five draws of math.ts rng, inlined (triangle, u, v, scale, yaw)
		for d in 5:
			st = (st + 0x6D2B79F5) & 0xFFFFFFFF
			var t := ((st ^ (st >> 15)) * (1 | st)) & 0xFFFFFFFF   # Math.imul: the low 32 bits survive int64 wrap
			t = ((t + ((t ^ (t >> 7)) * (61 | t))) & 0xFFFFFFFF) ^ t
			rv[d] = float(t ^ (t >> 14)) / 4294967296.0
		var k := floori(rv[0] * tris)
		var u := rv[1]
		var v := rv[2]
		if u + v > 1.0:
			u = 1.0 - u; v = 1.0 - v
		var pt := tri_a[k] + tri_e1[k] * u + tri_e2[k] * v
		if _noise(pt.x * 3.0 + 7.0, pt.z * 3.0) < 0.31:
			continue
		if pt.y < ground_max and pt.y < FM.height_at(pt.x, pt.z) + 0.012:
			continue
		var normal := tri_n[k]
		var basis := Basis(Quaternion(Vector3.UP, normal)) * Basis(Vector3.UP, rv[4] * TAU) * Basis.from_scale(Vector3.ONE * ((0.65 + rv[3] * 0.85) * scale))
		out.append(Transform3D(basis, pt - normal * 0.002))
	results[i] = out


func _moss(surfaces: Node) -> void:
	var sources := []
	if surfaces:
		for rock in surfaces.rocks:
			var arr: Array = (rock.mesh as ArrayMesh).surface_get_arrays(0)
			for xf: Transform3D in rock.xforms:
				if Vector2(xf.origin.x, xf.origin.z).length() > 115.0:
					continue
				var s := xf.basis.x.length()
				sources.append([arr[Mesh.ARRAY_VERTEX], arr[Mesh.ARRAY_INDEX], xf, floori(minf(16000.0, 1900.0 * s * s)), 1.0, s * 1.6])
		for lg in surfaces.logs:
			var arr: Array = (lg.mesh as ArrayMesh).surface_get_arrays(0)
			sources.append([arr[Mesh.ARRAY_VERTEX], arr[Mesh.ARRAY_INDEX], lg.xform, floori(900.0 * (lg.mesh as ArrayMesh).get_aabb().size.x), 1.2, (lg.mesh as ArrayMesh).get_aabb().size.x * 0.5])
	var results := []
	results.resize(sources.size())
	for i in sources.size():   # serial: GDScript worker threads ran this twice as slow (measured)
		_moss_source(i, sources, results)
	var cells := {}
	for list in results:
		for xf: Transform3D in list:
			var key := Vector2i(floori(xf.origin.x / 10.0), floori(xf.origin.z / 10.0))
			if not cells.has(key):
				cells[key] = PackedFloat32Array()
			var o := xf.origin - Vector3(key.x * 10.0 + 5.0, 0.0, key.y * 10.0 + 5.0)
			var bs := xf.basis
			cells[key].append_array([bs.x.x, bs.y.x, bs.z.x, o.x, bs.x.y, bs.y.y, bs.z.y, o.y, bs.x.z, bs.y.z, bs.z.z, o.z])
	var clump := moss_clump(831)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/foliage.gdshader")
	mat.set_shader_parameter("kind", 1)
	mat.set_shader_parameter("roughness", 1.0)
	var total := 0
	for key: Vector2i in cells:
		var buf: PackedFloat32Array = cells[key]
		var center := Vector2(key.x * 10.0 + 5.0, key.y * 10.0 + 5.0)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = clump
		mm.instance_count = buf.size() / 12
		mm.buffer = buf
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = mat
		mi.position = Vector3(center.x, 0.0, center.y)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		moss_cells.append([mi, center])
		total += mm.instance_count
	stats["moss_shoots"] = total


# --- roots, twigs, acorns ----------------------------------------------------------------------------------------

func _roots(trees: Node) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/deadwood.gdshader")
	mat.set_shader_parameter("mossy", false)
	mat.set_shader_parameter("bark_color", load("res://textures/bark-color.jpg"))
	mat.set_shader_parameter("bark_normal", load("res://textures/bark-normal.jpg"))
	for i in trees.positions.size():
		var tree: Dictionary = trees.positions[i]
		if Vector2(tree.x, tree.z).length() > 110.0 or int(tree.v) % 4 == 3:
			continue
		var r := FM.rng(7351 + i * 291)
		var s: float = tree.s
		var b := FL.B.new()
		var count: int = 5 + floori(r.call() * 4)
		for root in count:
			var angle: float = float(root) / count * TAU + r.call() * 0.7
			var length: float = (1.1 + r.call() * 1.7) * s
			var pts := []
			for k in 11:
				var t := k / 10.0
				var reach := 0.3 * s + length * t
				var sway := sin(t * 4.7) * 0.15
				var x: float = tree.x + cos(angle) * reach - sin(angle) * sway
				var z: float = tree.z + sin(angle) * reach + cos(angle) * sway
				pts.append(Vector3(x, FM.height_at(x, z) + (0.12 * pow(1.0 - t, 1.8) - 0.012) * s, z))
			var path := TreeGen.spaced_points(pts, 15, 60)
			var radii := []
			for k in 16:
				radii.append(0.08 * s * (0.025 + pow(1.0 - k / 15.0, 1.3)))
			tube(b, path, radii, 7, Color.WHITE, 0.62, length / 1.8)
		var mi := _mesh_instance(b.finish(), mat, Transform3D.IDENTITY, true)
		add_child(mi)
		roots.append([mi, Vector2(tree.x, tree.z)])
	stats["root_systems"] = roots.size()


static func twig_geometry(seed: int) -> ArrayMesh:
	var r := FM.rng(seed)
	var length: float = 0.25 + r.call() * 0.65
	var pts := []
	for i in 7:
		var t := i / 6.0
		pts.append(Vector3(length * (t - 0.5), 0.015 + sin(t * 2.8) * 0.014, sin(t * 4.5) * 0.035))
	var b := FL.B.new()
	tube(b, TreeGen.spaced_points(pts, 8, 60), 0.008 + r.call() * 0.006, 5, Color.WHITE)
	for i in b.p.size():
		var q := b.p[i]
		q.y *= 0.3 + maxf(0.0, 1.0 - (q.x / length + 0.5)) * 0.7
		b.p[i] = q
	return b.finish()


func _twigs(r: Callable) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#53432d")
	mat.roughness = 0.97
	for variant in 5:
		var xfs := []
		for i in 800:
			var x: float = (r.call() - 0.5) * 132.0
			var z: float = (r.call() - 0.5) * 132.0
			var yaw: float = r.call() * TAU
			var s: float = 0.6 + r.call() * 0.8
			xfs.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), Vector3(x, FM.height_at(x, z) + 0.002, z)))
		add_child(SF._mmi(twig_geometry(836 + variant * 121), mat, xfs, false))
	stats["twigs"] = 4000


func _acorns(r: Callable, trees: Node) -> void:
	var b := FL.B.new()
	SF._cap(b, 0.015, 7, 5, PI, 0.0, Color(0.30, 0.16, 0.06))
	for i in b.p.size():
		b.p[i] = Vector3(b.p[i].x, b.p[i].y * 1.35 + 0.017, b.p[i].z)
	SF._cap(b, 0.018, 8, 4, PI * 0.52, 0.024, Color(0.16, 0.12, 0.055))
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.89
	var xfs := []
	for i in 850:
		var tree: Dictionary = trees.positions[i % 6]
		var angle: float = r.call() * TAU
		var radial: float = 0.8 + r.call() * 3.2
		var x: float = tree.x + cos(angle) * radial
		var z: float = tree.z + sin(angle) * radial
		var e := Vector3(r.call(), r.call() * 6.28, r.call() * 2.0)
		xfs.append(SF._xf(Vector3(x, FM.height_at(x, z) + 0.012, z), e, 0.7 + r.call() * 0.6))
	add_child(SF._mmi(b.finish(), mat, xfs, false))
	stats["acorns"] = 850


# --- trunk life: ivy and bracket fungus --------------------------------------------------------------------------

## trunk-life.ts trunkPoint: a point and outward normal on the real triangulated trunk rings (u around, v up).
static func trunk_point(rows: Array, u: float, v: float) -> Array:
	var row := mini(rows.size() - 2, floori(v * (rows.size() - 1)))
	var fv := v * (rows.size() - 1) - row
	var r0: PackedVector3Array = rows[row]
	var r1: PackedVector3Array = rows[row + 1]
	var around := fposmod(u, 1.0) * (r0.size() - 1)
	var column := floori(around)
	var fu := around - column
	var a := r0[column]; var b := r0[column + 1]; var c := r1[column]; var d := r1[column + 1]
	if fu + fv <= 1.0:
		return [a + (b - a) * fu + (c - a) * fv, (b - a).cross(c - a).normalized()]
	return [b * (1.0 - fv) + c * (1.0 - fu) + d * (fu + fv - 1.0), (d - b).cross(c - b).normalized()]


const IVY_OUTLINE := [[0, 0], [-0.25, 0.045], [-0.5, 0.28], [-0.31, 0.43], [-0.45, 0.70], [-0.17, 0.64], [0, 1],
	[0.17, 0.64], [0.45, 0.70], [0.31, 0.43], [0.5, 0.28], [0.25, 0.045]]


## trunk-life.ts ivyLeaves().leaf: a lobed, slightly domed ivy leaf facing out of the bark (flat-shaded triangles).
static func ivy_leaf(b: FL.B, r: Callable, base: Vector3, normal: Vector3, size: float) -> void:
	var up := (Vector3.UP - normal * normal.y).normalized()
	up = up.rotated(normal, (r.call() - 0.5) * 0.7)
	var side := up.cross(normal).normalized()
	var hh: float = 0.255 + r.call() * 0.035
	var ss: float = 0.39 + r.call() * 0.17
	var color := _hsl(hh, ss, 0.115 + r.call() * 0.07)
	var at := func(x: float, y: float, raised: float) -> Vector3:
		return base + side * (x * size) + up * (y * size) + normal * (raised * size)
	var center: Vector3 = at.call(0.0, 0.43, 0.08)
	var rings := []
	for i in IVY_OUTLINE.size():
		var x: float = IVY_OUTLINE[i][0]
		var y: float = IVY_OUTLINE[i][1]
		rings.append([Vector2(x + 0.5, y), at.call(x, y, 0.012 * sin(i * 2.1)), at.call(x * 0.53, 0.43 + (y - 0.43) * 0.53, 0.065)])
	var tri := func(p0: Vector3, p1: Vector3, p2: Vector3, uv: Array, shade: float) -> void:
		var c := Color(color.r * shade, color.g * shade, color.b * shade)
		var i0 := b.vertex(p0, c, uv[0].x, uv[0].y)
		var i1 := b.vertex(p1, c, uv[1].x, uv[1].y)
		var i2 := b.vertex(p2, c, uv[2].x, uv[2].y)
		b.tri(i0, i1, i2)
	var ca := Vector2(0.5, 0.43)
	for i in rings.size():
		var ra: Array = rings[i]
		var rb: Array = rings[(i + 1) % rings.size()]
		var ia := Vector2(0.5 + (ra[0].x - 0.5) * 0.53, 0.43 + (ra[0].y - 0.43) * 0.53)
		var ib := Vector2(0.5 + (rb[0].x - 0.5) * 0.53, 0.43 + (rb[0].y - 0.43) * 0.53)
		tri.call(center, rb[2], ra[2], [ca, ib, ia], 1.04)
		tri.call(ra[2], rb[2], ra[1], [ia, ib, ra[0]], 0.99)
		tri.call(ra[1], rb[2], rb[1], [ra[0], ib, rb[0]], 0.95)


static func _baked(mesh: ArrayMesh, xf: Transform3D) -> ArrayMesh:
	var arr := mesh.surface_get_arrays(0)
	var p: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	for i in p.size():
		p[i] = xf * p[i]
		n[i] = (xf.basis * n[i]).normalized()
	arr[Mesh.ARRAY_VERTEX] = p
	arr[Mesh.ARRAY_NORMAL] = n
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return out


func _trunk_life(trees: Node) -> void:
	var leaf_mat := ShaderMaterial.new()
	leaf_mat.shader = load("res://shaders/foliage.gdshader")
	leaf_mat.set_shader_parameter("kind", 0)
	leaf_mat.set_shader_parameter("roughness", 0.84)
	var stem_mat: ShaderMaterial = (trees.bark_mats[1] as ShaderMaterial).duplicate()
	stem_mat.set_shader_parameter("tint", Color("#625d36"))
	var fungus_mat := ShaderMaterial.new()
	fungus_mat.shader = load("res://shaders/attached.gdshader")
	# vegetation.ts treeSurfaces: every trunk within 120 m, its instance matrix and a position seed
	var surfaces := []
	for i in trees.positions.size():
		var p: Dictionary = trees.positions[i]
		if Vector2(p.x, p.z).length() < 120.0:
			surfaces.append({"rows": trees.variants[p.v].trunk_rows, "xf": trees.tree_matrices[i], "x": p.x, "z": p.z,
				"seed": floori((p.x + 220.0) * 7919.0 + (p.z + 220.0) * 104729.0)})
	var ivy := 0
	var ivy_leaves := 0
	for tree in surfaces:
		var r := FM.rng(tree.seed)
		var rows: Array = tree.rows
		if r.call() > 0.24 or rows.size() < 2:
			continue
		var lr := FM.rng(tree.seed + 117)
		var lb := FL.B.new()
		var sb := FL.B.new()
		var stems: int = 1 + floori(r.call() * 3)
		var top: float = rows[rows.size() - 1][0].y
		for stem in stems:
			var azimuth: float = r.call()
			var end := minf(0.78, (1.5 + r.call() * 3.6) / maxf(top, 1.0))
			var curve: float = r.call() * 0.20 - 0.10
			var pts := []
			for i in 65:
				var t := i / 64.0
				var v := 0.018 + (end - 0.018) * t
				var u := azimuth + t * curve + sin(t * 4.0 + stem) * 0.012
				var tp := trunk_point(rows, u, v)
				var pt: Vector3 = tp[0] + tp[1] * 0.004
				var nrm: Vector3 = tp[1]
				pts.append(pt)
				if i % 2 == 0 and i > 3 and r.call() < 0.88:
					var reach: float = 0.017 + r.call() * 0.026
					var petiole_end := pt + nrm * reach + Vector3((r.call() - 0.5) * 0.025, 0.009, 0.0)
					ivy_leaf(lb, lr, petiole_end, nrm, 0.065 + r.call() * 0.065)
					ivy_leaves += 1
					tube(sb, [pt, petiole_end], 0.0012, 3, Color.WHITE)
			tube(sb, TreeGen.spaced_points(pts, 100, 120), 0.0045, 4, Color.WHITE)
		var leaves := _mesh_instance(lb.finish(), leaf_mat, tree.xf, true)
		var stem_mi := _mesh_instance(sb.finish(), stem_mat, tree.xf, true)
		add_child(leaves)
		add_child(stem_mi)
		attached.append([[leaves, stem_mi], Vector2(tree.x, tree.z)])
		ivy += 1
	var brackets := 0
	for tree in surfaces:
		var r := FM.rng(tree.seed + 777)
		var rows: Array = tree.rows
		var hero: bool = Vector2(tree.x + 6.5, tree.z - 5.0).length() < 0.1
		if not hero and r.call() > 0.105:
			continue
		if rows.size() < 2:
			continue
		var azimuth: float = r.call()
		var xf: Transform3D = tree.xf
		if hero:   # the hero oak's shelf faces the entrance path
			var best := -INF
			var dir := Vector3(0.7, 0.0, 1.0).normalized()
			for i in 48:
				var score := (xf.basis * (trunk_point(rows, i / 48.0, 0.08)[1] as Vector3)).normalized().dot(dir)
				if score > best:
					best = score
					azimuth = i / 48.0
		var top: float = rows[rows.size() - 1][0].y
		var tp := trunk_point(rows, azimuth, (0.95 if hero else 0.45 + r.call() * 1.7) / maxf(top, 1.0))
		var normal: Vector3 = tp[1]
		var up := (Vector3.UP - normal * normal.y).normalized()
		var side := up.cross(normal).normalized()
		var placement := Transform3D(Basis(side, up, normal), (tp[0] as Vector3) - normal * 0.002)
		var mi := _mesh_instance(_baked(Fungus.geometry(tree.seed + 731), placement), fungus_mat, xf, true)
		add_child(mi)
		attached.append([[mi], Vector2(tree.x, tree.z)])
		brackets += 1
	stats["ivy_climbers"] = ivy
	stats["ivy_leaves"] = ivy_leaves
	stats["bracket_clusters"] = brackets


func _process(delta: float) -> void:
	clock += delta
	if clock < 0.3:
		return
	clock = 0.0
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var c := Vector2(cam.global_position.x, cam.global_position.z)
	for m in moss_cells:
		m[0].visible = c.distance_to(m[1]) < 31.0
	for m in roots:
		m[0].visible = c.distance_to(m[1]) < 42.0
	for g in attached:
		var d := c.distance_to(g[1])
		for mi: GeometryInstance3D in g[0]:
			mi.visible = d < 52.0
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if d < 34.0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
