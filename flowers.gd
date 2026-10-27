extends Node3D
## Port of app/forest/wildflowers.ts: bluebells (nodding six-lobed bells on arching stems), red campion (cleft pink
## petals), buttercups and wood anemones, as real geometry. They grow in single-species drifts: ~100 coherent
## colonies along the trail, ten composed accents by the opening and 62 scattered across the wood, on the original's
## random stream (rng 493837), kept off the trail and out of trunk flares, batched per 18 m cell with a near and a
## far detail level.

const FM := preload("res://forest_math.gd")
const TAU := PI * 2.0
const KINDS := ["bluebell", "campion", "buttercup", "wood-anemone"]

var mat := ShaderMaterial.new()
var count := 0


static func _lin(hex: String) -> Color:
	return Color(hex).srgb_to_linear()


## wildflowers.ts naturalFlowerColor: the same hue and lightness at 70% saturation (HSL, in linear space as three.js).
static func _natural(hex: String) -> Color:
	var c := _lin(hex)
	var mx := maxf(c.r, maxf(c.g, c.b))
	var mn := minf(c.r, minf(c.g, c.b))
	var l := (mx + mn) * 0.5
	if mx == mn:
		return c
	var d := mx - mn
	var s := d / (2.0 - mx - mn) if l > 0.5 else d / (mx + mn)
	var h: float
	if mx == c.r:
		h = (c.g - c.b) / d + (6.0 if c.g < c.b else 0.0)
	elif mx == c.g:
		h = (c.b - c.r) / d + 2.0
	else:
		h = (c.r - c.g) / d + 4.0
	h /= 6.0
	s *= 0.7
	var q := l * (1.0 + s) if l < 0.5 else l + s - l * s
	var p := 2.0 * l - q
	return Color(_hue(p, q, h + 1.0 / 3.0), _hue(p, q, h), _hue(p, q, h - 1.0 / 3.0))


static func _hue(p: float, q: float, t: float) -> float:
	t = fposmod(t, 1.0)
	if t < 1.0 / 6.0:
		return p + (q - p) * 6.0 * t
	if t < 0.5:
		return q
	if t < 2.0 / 3.0:
		return p + (q - p) * 6.0 * (2.0 / 3.0 - t)
	return p


class B:
	var p := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var i := PackedInt32Array()

	func vertex(pt: Vector3, col: Color, u := 0.0, v := 0.0) -> int:
		p.append(pt); c.append(col); uv.append(Vector2(u, v))
		return p.size() - 1

	func tri(a: int, b: int, cc: int) -> void:
		i.append_array([a, cc, b])   # Godot winding

	func finish() -> ArrayMesh:
		var n := PackedVector3Array()
		n.resize(p.size())
		for k in range(0, i.size(), 3):
			var a := i[k]; var b := i[k + 2]; var cc := i[k + 1]
			var fn := (p[cc] - p[b]).cross(p[a] - p[b])
			n[a] += fn; n[b] += fn; n[cc] += fn
		for k in n.size():
			n[k] = n[k].normalized()
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = p; arr[Mesh.ARRAY_NORMAL] = n; arr[Mesh.ARRAY_COLOR] = c; arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_INDEX] = i
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m


static func _scale(c: Color, k: float) -> Color:
	return Color(c.r * k, c.g * k, c.b * k)


static func stem(b: B, points: Array, radius: float, color: Color, sides := 4) -> void:
	var rows := []
	var previous := Vector3(1, 0, 0)
	for i in points.size():
		var tg: Vector3 = ((points[mini(i + 1, points.size() - 1)] as Vector3) - (points[maxi(0, i - 1)] as Vector3)).normalized()
		var side := (previous - tg * previous.dot(tg)).normalized()
		if side.length_squared() < 1e-8:
			side = tg.cross(Vector3.UP).normalized()
		var other := tg.cross(side).normalized()
		previous = side
		var t := float(i) / (points.size() - 1)
		var w := radius * (1.0 - 0.72 * t)
		var row := []
		for j in sides:
			var a := float(j) / sides * TAU
			row.append(b.vertex(points[i] + side * (cos(a) * w) + other * (sin(a) * w), color, float(j) / sides, t))
		rows.append(row)
	for i in rows.size() - 1:
		for j in sides:
			var k := (j + 1) % sides
			b.tri(rows[i][j], rows[i + 1][j], rows[i][k])
			b.tri(rows[i][k], rows[i + 1][j], rows[i + 1][k])


static func leaf(b: B, base: Vector3, angle: float, length: float, width: float, color: Color, curl := 0.18, sections := 5) -> void:
	var axis := Vector3(cos(angle), 0.16, sin(angle))
	var side := Vector3(-sin(angle), 0, cos(angle))
	var rows := []
	for i in sections + 1:
		var t := float(i) / sections
		var w := pow(sin(PI * t), 0.72) * width * 0.5
		var center := base + axis * (length * t)
		center.y += length * curl * sin(t * PI * 0.9)
		var c := _scale(color, 0.8 + t * 0.26)
		var row := []
		if i == 0 or i == sections:
			row.append(b.vertex(center, c, 0.5, t))
		else:
			for j: int in [-1, 0, 1]:
				var pt := center + side * (j * w)
				pt.y += w * 0.14 if j == 0 else -w * 0.16
				row.append(b.vertex(pt, c, (j + 1) / 2.0, t))
		rows.append(row)
	for i in sections:
		var a: Array = rows[i]
		var c: Array = rows[i + 1]
		if a.size() == 1:
			b.tri(a[0], c[0], c[1]); b.tri(a[0], c[1], c[2])
		elif c.size() == 1:
			b.tri(a[0], c[0], a[1]); b.tri(a[1], c[0], a[2])
		else:
			for j in 2:
				b.tri(a[j], c[j], a[j + 1]); b.tri(a[j + 1], c[j], c[j + 1])


static func petal(b: B, center: Vector3, angle: float, length: float, width: float, color: Color, cupping: float, cleft := false, segments := 4) -> void:
	var axis := Vector3(cos(angle), 0, sin(angle))
	var side := Vector3(-sin(angle), 0, cos(angle))
	var low := segments < 4
	var sides := 8 if low else (16 if cleft else 12)
	var rings := 1 if low else 2
	var point := func(x: float, z: float) -> Vector3:
		var pt := center + axis * (x * length) + side * (z * width)
		pt.y += length * (cupping * x * x + z * z * 0.37 - 0.055 * sin(x * PI))
		return pt
	var middle := b.vertex(point.call(0.5, 0.0), _scale(color, 0.88), 0.5, 0.5)
	var rows := []
	for ring in range(1, rings + 1):
		var f := float(ring) / rings
		var row := []
		for i in sides:
			var a := float(i) / sides * TAU
			var notch := 0.095 * pow(maxf(0.0, cos(a)), 16.0) if cleft else 0.0
			var x := 0.5 + (0.49 * cos(a) - notch) * f
			var z := 0.5 * sin(a) * (0.73 + 0.27 * (cos(a) + 1.0) * 0.5) * f
			row.append(b.vertex(point.call(x, z), _scale(color, 0.84 + x * 0.16), z + 0.5, x))
		rows.append(row)
	for i in sides:
		b.tri(middle, rows[0][(i + 1) % sides], rows[0][i])
	for ring in rows.size() - 1:
		for i in sides:
			var j := (i + 1) % sides
			b.tri(rows[ring][i], rows[ring][j], rows[ring + 1][i])
			b.tri(rows[ring][j], rows[ring + 1][j], rows[ring + 1][i])


static func flower_center(b: B, pt: Vector3, radius: float, color: Color) -> void:
	var top := b.vertex(pt + Vector3(0, radius * 0.45, 0), color, 0.5, 0.5)
	var row := []
	for i in 9:
		var a := i / 9.0 * TAU
		row.append(b.vertex(pt + Vector3(cos(a) * radius, 0, sin(a) * radius), color, (cos(a) + 1.0) * 0.5, (sin(a) + 1.0) * 0.5))
	for i in 9:
		b.tri(top, row[i], row[(i + 1) % 9])


static func bell(b: B, center: Vector3, color: Color, angle: float, scale: float, low := false) -> void:
	var sides := 6 if low else 16
	var segments := 3 if low else 5
	var axis := Vector3(cos(angle) * 0.26, -1.0, sin(angle) * 0.26).normalized()
	var side := Vector3(-sin(angle), 0, cos(angle))
	var other := axis.cross(side).normalized()
	var rows := []
	for i in segments + 1:
		var t := float(i) / segments
		var radius := (0.0036 + sin(t * PI * 0.55) * 0.0088 + pow(t, 7.0) * 0.0015) * scale
		var row := []
		for j in sides:
			var a := float(j) / sides * TAU
			var lobe := ((0.0015 if low else cos(a * 6.0) * 0.0022) * scale) if i == segments else 0.0
			var rim := radius + (maxf(0.0, cos(a * 6.0)) * 0.0012 * scale if i == segments else 0.0)
			row.append(b.vertex(center + axis * (t * 0.058 * scale + lobe) + side * (cos(a) * rim) + other * (sin(a) * rim), _scale(color, 0.82 + t * 0.19), float(j) / sides, t))
		rows.append(row)
	for i in segments:
		for j in sides:
			var k := (j + 1) % sides
			b.tri(rows[i][j], rows[i + 1][j], rows[i][k])
			b.tri(rows[i][k], rows[i + 1][j], rows[i + 1][k])


static func geometry(kind: String, seed: int, low := false) -> ArrayMesh:
	var r := FM.rng(seed)
	var b := B.new()
	var phase: float = r.call() * TAU
	var STEM := _lin("#426226")
	var LEAF := _lin("#4c7c2e")
	if kind == "bluebell":
		var h: float = 0.59 + r.call() * 0.16
		var bend: float = 0.12 + r.call() * 0.06
		var curve := func(t: float) -> Vector3: return Vector3(cos(phase) * bend * t * t, h * (t - 0.09 * t * t), sin(phase) * bend * t * t)
		var pts := []
		for i in 9:
			pts.append(curve.call(i / 8.0))
		stem(b, pts, 0.006, STEM)
		for i in 4:
			leaf(b, Vector3(0, 0.012, 0), phase + i * 2.13, 0.22 + r.call() * 0.13, 0.019 + r.call() * 0.018, LEAF, 0.4, 3 if low else 6)
		for i in 6:
			var t := 0.4 + i * 0.098
			var st: Vector3 = curve.call(t)
			var a := phase + (0.43 if i % 2 else -0.43)
			var end: Vector3 = st + Vector3(cos(a) * (0.04 + r.call() * 0.025), 0.004, sin(a) * 0.06)
			stem(b, [st, st.lerp(end, 0.55) + Vector3(0, 0.018, 0), end], 0.0023, STEM)
			bell(b, end, _natural("#8170be" if i % 3 else "#7086bd"), a, 0.82 + r.call() * 0.22, low)
	else:
		var pink := kind == "campion"
		var gold := kind == "buttercup"
		var stems := 3 if pink or gold else 2
		var petal_color := _natural("#df729f" if pink else ("#e6bd4a" if gold else "#eae2e6"))
		var h := 0.72 if pink else (0.46 if gold else 0.38)
		for i in stems:
			var a := phase + i * TAU / stems
			var hp: float = h * (0.7 + r.call() * 0.36)
			var lean: float = 0.08 + r.call() * 0.06
			var end := Vector3(cos(a) * lean, hp, sin(a) * lean)
			var mid := end * 0.48
			mid.x *= 0.66
			mid.z *= 0.66
			stem(b, [Vector3.ZERO, mid, end], 0.0045 if pink else 0.0034, STEM)
			for j in 2:
				var t := 0.21 + j * 0.24
				leaf(b, end * t, a + j * PI, 0.085 + r.call() * 0.065, 0.036 if pink else 0.046, LEAF, 0.24, 3 if low else 5)
			var n := 5 if pink or gold else 6
			var rad := 0.027 if pink else (0.025 if gold else 0.028)
			for p in n:
				petal(b, end, a + float(p) / n * TAU, rad, rad * 0.99, petal_color, 0.19 if pink else (0.35 if gold else 0.22), pink, 2 if low else 4)
			flower_center(b, end + Vector3(0, 0.003, 0), 0.007 if pink else 0.011, _lin("#f3c5d7" if pink else ("#b58d16" if gold else "#d6b64f")))
		for i in 3:
			leaf(b, Vector3(0, 0.012, 0), phase + i * 2.2, 0.14 + r.call() * 0.055, 0.04, LEAF, 0.4, 3 if low else 5)
	return b.finish()


func _ready() -> void:
	mat.shader = load("res://shaders/foliage.gdshader")
	mat.set_shader_parameter("kind", 3)
	mat.set_shader_parameter("roughness", 0.71)
	var geos := []
	var lows := []
	for i in 4:
		geos.append(geometry(KINDS[i], 475 + i * 913))
		lows.append(geometry(KINDS[i], 475 + i * 913, true))
	var trees: Node = get_parent().get_node_or_null("Vegetation")
	var grid := {}
	if trees:
		for i in trees.positions.size():
			var p: Dictionary = trees.positions[i]
			if absf(p.x) > 140.0 or absf(p.z) > 140.0:
				continue
			var key := Vector2i(floori(p.x / 6.0), floori(p.z / 6.0))
			if not grid.has(key):
				grid[key] = []
			grid[key].append([p.x, p.z, trees.variants[p.v].trunk_radius * p.s * 0.75 + 0.045 + 0.1])
	var surfaces: Node = get_parent().get_node_or_null("Surfaces")
	if surfaces:
		for f in surfaces.footprints:
			var key := Vector2i(floori(f[0] / 6.0), floori(f[1] / 6.0))
			if not grid.has(key):
				grid[key] = []
			grid[key].append([f[0], f[1], f[2] + 0.08])
	var blocked := func(x: float, z: float) -> bool:
		var gx := floori(x / 6.0); var gz := floori(z / 6.0)
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				for q in grid.get(Vector2i(gx + dx, gz + dz), []):
					if (q[0] - x) * (q[0] - x) + (q[1] - z) * (q[1] - z) < q[2] * q[2]:
						return true
		return surfaces != null and surfaces.inside_deadwood(x, z)
	var r := FM.rng(493837)
	var cells := {}
	var add_drift := func(x: float, z: float, kind: int, radius: float, n: int) -> void:
		for i in n:
			var angle: float = r.call() * TAU
			var spread: float = sqrt(r.call()) * radius
			var px := x + cos(angle) * spread
			var pz := z + sin(angle) * spread * 0.64
			if FM.trail_distance(px, pz) < 0.58 or blocked.call(px, pz) or FM.noise(px * 1.3 + 41.0, pz * 1.3) < 0.22:
				continue
			var key := Vector3i(floori(px / 18.0), floori(pz / 18.0), kind)
			if not cells.has(key):
				cells[key] = []
			cells[key].append([px, pz, r.call() * TAU, 0.82 + r.call() * 0.55, 0.88 + r.call() * 0.2])
	for i in 100:
		var z: float = -116.0 + i * 2.35 + (r.call() - 0.5) * 2.5
		var side := 1.0 if i % 2 else -1.0
		var x: float = FM.trail_at(z) + side * (1.4 + r.call() * 4.2)
		var kind := 0 if i % 11 < 5 else (1 if i % 11 < 8 else (2 if i % 11 < 10 else 3))
		add_drift.call(x, z, kind, 1.4 + r.call() * 1.65, floori(64.0 * (1.0 + r.call() * 0.35)))
	for a in [[7.4, 15, 1, 1.9], [2.7, 11, 0, 2.4], [4.8, 4, 2, 1.9], [-4.2, 2.1, 0, 1.7], [-3.1, 3.5, 3, 1.3], [7.6, -9.5, 2, 1.8], [-1.4, -2, 0, 2.5], [-4.2, -11, 1, 2.3], [1.9, -21, 3, 2.1], [-7, -31, 0, 2.8]]:
		add_drift.call(a[0], a[1], a[2], a[3], 135)
	for i in 62:
		var a: float = r.call() * TAU
		var d: float = 18.0 + sqrt(r.call()) * 95.0
		add_drift.call(cos(a) * d, sin(a) * d, i % 4, 1.7 + r.call() * 1.7, 40)
	for key in cells:
		var plants: Array = cells[key]
		var c := Vector2(key.x * 18.0 + 9.0, key.y * 18.0 + 9.0)
		var origin := Vector3(c.x, FM.height_at(c.x, c.y), c.y)
		for level in 2:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = geos[key.z] if level == 0 else lows[key.z]
			mm.instance_count = plants.size()
			for k in plants.size():
				var p: Array = plants[k]
				var xf := Transform3D(Basis(Vector3.UP, p[2]).scaled(Vector3.ONE * p[3]), Vector3(p[0], FM.height_at(p[0], p[1]) - 0.008, p[1]) - origin)
				mm.set_instance_transform(k, xf)
				mm.set_instance_color(k, Color(p[4], p[4], p[4]))
			var mi := MultiMeshInstance3D.new()
			mi.multimesh = mm
			mi.material_override = mat
			mi.position = origin
			mi.visibility_range_begin = 0.0 if level == 0 else 16.0
			mi.visibility_range_end = 16.0 if level == 0 else 79.0
			mi.visibility_range_end_margin = 2.0
			mi.visibility_range_begin_margin = 2.0 if level == 1 else 0.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if level == 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
		count += plants.size()
	print("flowers: %d in %d batches" % [count, cells.size()])
