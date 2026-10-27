extends Node3D
## Port of surfaces.ts: moss-covered rocks, seven fallen logs with broken ends, splinters and branch stubs, leaf litter
## and mushroom clusters, with the original's seeded streams so every one lands where it did. Runs before the
## vegetation modules, which keep their plants off the rock footprints and out of the logs (insideDeadwood).

const FM := preload("res://forest_math.gd")
const FL := preload("res://flowers.gd")

## [x, z, length, radius, angle]
const DEADWOOD_PLACEMENTS := [[-6.0, 3.0, 4.8, 0.39, 1.1], [6.0, -7.0, 6.2, 0.52, 2.2], [-14.0, -12.0, 8.8, 0.56, 1.9],
	[22.0, 10.0, 5.2, 0.42, 0.5], [-27.0, -25.0, 7.1, 0.45, 2.7], [17.0, -32.0, 6.6, 0.63, 1.1], [36.0, -17.0, 8.3, 0.63, 2.8]]

var footprints: Array = []     # rock footprints [x, z, r]
var rocks: Array = []          # {mesh, xforms} per rock variant (details.ts samples their surfaces)
var logs: Array = []           # {mesh, xform} per log body (mossSurface)


## surfaces.ts insideDeadwood: inside a log's rotated rectangle.
static func inside_deadwood(x: float, z: float) -> bool:
	for d in DEADWOOD_PLACEMENTS:
		var dx: float = x - d[0]
		var dz: float = z - d[1]
		var c := cos(d[4]); var s := sin(d[4])
		if absf(dx * c - dz * s) < d[2] * 0.5 + 0.08 and absf(dx * s + dz * c) < d[3] * 0.95:
			return true
	return false


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	_rocks()
	_deadwood()
	_litter()
	_mushrooms()
	print("surfaces: %d rocks, %d logs, %d ms" % [footprints.size(), logs.size(), Time.get_ticks_msec() - t0])


## three.js CylinderGeometry into a builder (rows top to bottom, optional caps), returning the side grid.
static func cylinder(b: FL.B, rt: float, rb: float, h: float, sides: int, rows: int, open: bool, col: Color,
		xf := Transform3D.IDENTITY) -> Array:
	var grid := []
	for y in rows + 1:
		var v := float(y) / rows
		var radius := v * (rb - rt) + rt
		var row := []
		for x in sides + 1:
			var u := float(x) / sides
			var th := u * TAU
			row.append(b.vertex(xf * Vector3(radius * sin(th), -v * h + h * 0.5, radius * cos(th)), col, u, v))
		grid.append(row)
	for x in sides:
		for y in rows:
			var a: int = grid[y][x]; var bb: int = grid[y + 1][x]; var c: int = grid[y + 1][x + 1]; var d: int = grid[y][x + 1]
			b.tri(a, bb, d); b.tri(bb, c, d)
	if not open:
		for top in [true, false]:
			var radius := rt if top else rb
			var sgn := 1.0 if top else -1.0
			var centers := []
			for x in sides:
				centers.append(b.vertex(xf * Vector3(0.0, h * 0.5 * sgn, 0.0), col, 0.5, 0.5))
			var ring := []
			for x in sides + 1:
				var th := float(x) / sides * TAU
				ring.append(b.vertex(xf * Vector3(radius * sin(th), h * 0.5 * sgn, radius * cos(th)), col))
			for x in sides:
				if top:
					b.tri(ring[x], ring[x + 1], centers[x])
				else:
					b.tri(ring[x + 1], ring[x], centers[x])
	return grid


static func _xf(pos: Vector3, euler: Vector3, scale: float) -> Transform3D:
	return Transform3D(Basis.from_euler(euler, EULER_ORDER_XYZ).scaled(Vector3.ONE * scale), pos)


static func _mmi(mesh: Mesh, mat: Material, xfs: Array, shadows: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# --- rocks -------------------------------------------------------------------------------------------------------

const ICO_T := 1.618033988749895
const ICO_V := [[-1, ICO_T, 0], [1, ICO_T, 0], [-1, -ICO_T, 0], [1, -ICO_T, 0], [0, -1, ICO_T], [0, 1, ICO_T],
	[0, -1, -ICO_T], [0, 1, -ICO_T], [ICO_T, 0, -1], [ICO_T, 0, 1], [-ICO_T, 0, -1], [-ICO_T, 0, 1]]
const ICO_F := [0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
	3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1]


## surfaces.ts rockGeometry: an IcosahedronGeometry(1, 4) (each face split 5 x 5, projected to the sphere), merged,
## squashed by the seed's stream and dented by two noise octaves, with a grey vertex mottle.
static func rock_geometry(seed: int) -> ArrayMesh:
	var r := FM.rng(seed)
	var sx: float = 0.7 + r.call() * 0.9
	var sy: float = 0.44 + r.call() * 0.6
	var sz: float = 0.6 + r.call() * 0.85
	var b := FL.B.new()
	var ids := {}
	var n := 5
	for f in range(0, ICO_F.size(), 3):
		var a := Vector3(ICO_V[ICO_F[f]][0], ICO_V[ICO_F[f]][1], ICO_V[ICO_F[f]][2])
		var bv := Vector3(ICO_V[ICO_F[f + 1]][0], ICO_V[ICO_F[f + 1]][1], ICO_V[ICO_F[f + 1]][2])
		var c := Vector3(ICO_V[ICO_F[f + 2]][0], ICO_V[ICO_F[f + 2]][1], ICO_V[ICO_F[f + 2]][2])
		var grid := []
		for i in n + 1:
			var row := []
			for j in n - i + 1:
				var p := ((a * (n - i - j) + bv * j + c * i) / n).normalized()
				var key := Vector3i((p * 10000.0).round())
				if not ids.has(key):
					var fx := 0.80 + FM.noise(p.x * 3.0 + seed, p.y * 2.0 + p.z * 2.0) * 0.3 + FM.noise(p.x * 11.0 + p.z * 3.0, p.y * 7.0) * 0.05
					var q := 0.76 + FM.noise(p.x * 17.0, p.y * 16.0 + p.z) * 0.22
					ids[key] = b.vertex(Vector3(p.x * fx * sx, p.y * fx * sy, p.z * fx * sz), Color(q, q, q * 0.97))
				row.append(ids[key])
			grid.append(row)
		for i in n:
			for j in n - i:
				b.tri(grid[i][j], grid[i][j + 1], grid[i + 1][j])
				if j < n - i - 1:
					b.tri(grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j])
	return b.finish()


func _rocks() -> void:
	var r := FM.rng(899)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/rock.gdshader")
	mat.set_shader_parameter("rock_color", load("res://textures/rock-color.jpg"))
	mat.set_shader_parameter("rock_normal", load("res://textures/rock-normal.jpg"))
	for v in 5:
		var geo := rock_geometry(v * 11 + 43)
		var xfs := []
		for i in 90:
			var x: float = (r.call() - 0.5) * 220.0
			var z: float = (r.call() - 0.5) * 220.0
			var s: float = (0.18 + r.call() * 0.55) if i < 60 else (0.65 + r.call() * 1.6)
			if v == 0 and i < 4:
				x = [-3.7, 5.2, 6.4, -8.5][i]; z = [7.0, 1.0, -0.5, -11.0][i]; s = [1.3, 2.0, 1.5, 2.4][i]
			footprints.append([x, z, s * 0.88])
			var ex: float = (r.call() - 0.5) * 0.3
			var ey: float = r.call() * 6.28
			var ez: float = (r.call() - 0.5) * 0.2
			xfs.append(_xf(Vector3(x, FM.height_at(x, z) + s * 0.12, z), Vector3(ex, ey, ez), s))
		add_child(_mmi(geo, mat, xfs, true))
		rocks.append({"mesh": geo, "xforms": xfs})


# --- deadwood ----------------------------------------------------------------------------------------------------

## surfaces.ts brokenEnd: the torn rim, a ring of pale wood stepped inward, and a dark hollow behind it.
static func _broken_end(b: FL.B, body: FL.B, ring: Array, side: float, radius: float) -> void:
	var sides := ring.size()
	var outer := []; var oid := []; var iid := []; var bid := []
	var push := func(v: Vector3, k: float) -> int:
		return b.vertex(v, Color(k, k * 0.94, k * 0.81), v.z / (radius * 2.0) + 0.5, v.y / (radius * 2.0) + 0.5)
	for j in sides:
		var v: Vector3 = body.p[ring[j]]
		outer.append(v)
		oid.append(push.call(v, 0.69 + 0.12 * sin(j * 1.7)))
	var center := Vector3.ZERO
	for v in outer:
		center += v
	center /= sides
	for j in sides:
		var v: Vector3 = (outer[j] - center) * (0.59 + 0.08 * sin(j * 2.1)) + center
		v.x -= side * (0.018 + 0.035 * sin(j * 3.7))
		iid.append(push.call(v, 0.62))
		var back := v
		back.x -= side * (0.23 + radius * 0.4)
		back.y *= 0.77; back.z *= 0.77
		bid.append(push.call(back, 0.12))
	var bc: int = push.call(center + Vector3(-side * (0.27 + radius * 0.4), 0.0, 0.0), 0.055)
	for j in sides:
		var k := (j + 1) % sides
		b.tri(oid[j], oid[k], iid[j]); b.tri(oid[k], iid[k], iid[j])
		b.tri(iid[j], iid[k], bid[j]); b.tri(iid[k], bid[k], bid[j])
		b.tri(bid[j], bid[k], bc)


func _deadwood() -> void:
	var r := FM.rng(616)
	var bc: Texture2D = load("res://textures/bark-color.jpg")
	var bn: Texture2D = load("res://textures/bark-normal.jpg")
	var log_mat := ShaderMaterial.new()
	log_mat.shader = load("res://shaders/deadwood.gdshader")
	log_mat.set_shader_parameter("bark_color", bc)
	log_mat.set_shader_parameter("bark_normal", bn)
	var bark_mat := log_mat.duplicate()
	bark_mat.set_shader_parameter("mossy", false)
	var end_mat := StandardMaterial3D.new()
	end_mat.albedo_color = Color("#c3a273")
	end_mat.albedo_texture = load("res://textures/endgrain.jpg")
	end_mat.vertex_color_use_as_albedo = true
	end_mat.roughness = 0.98
	end_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var splinter_col := Color(0.66, 0.62, 0.53)
	for d in DEADWOOD_PLACEMENTS:
		var x: float = d[0]; var z: float = d[1]; var ln: float = d[2]; var rad: float = d[3]
		var sides := 28; var rows := 22
		var lb := FL.B.new()
		var grid := cylinder(lb, rad * 0.72, rad, ln, sides, rows, true, Color.WHITE)
		for i in lb.p.size():
			var p0: Vector3 = lb.p[i]
			var px := -p0.y; var y := p0.x; var pz := p0.z    # rotateZ(PI / 2)
			var theta := atan2(pz, y)
			var nn := FM.noise(px * 4.0 + 22.0, pz * 6.0 + y * 8.0)
			var end_w := pow(absf(px) / (ln * 0.5), 12.0)
			var ragged := (sin(theta * 7.7) * 0.085 + sin(theta * 13.3 + 0.7) * 0.033) * end_w
			lb.p[i] = Vector3(px + ragged, (y + sin(px * 0.6) * 0.08) * (1.0 + nn * 0.09), pz * (0.93 + nn * 0.14))
			lb.uv[i] = Vector2(lb.uv[i].x * 2.0, (1.0 - lb.uv[i].y) * ln / 1.8)
		var eb := FL.B.new()
		for side in [-1.0, 1.0]:
			var ring_row: Array = grid[0] if side < 0.0 else grid[rows]
			_broken_end(eb, lb, ring_row.slice(0, sides), side, rad)
		for i in 14:
			var side := 1.0 if i % 2 else -1.0
			var theta: float = r.call() * TAU
			var length: float = 0.13 + r.call() * 0.33
			var br: float = 0.018 + r.call() * 0.025
			var dir := Vector3(side, (r.call() - 0.5) * 0.7, (r.call() - 0.5) * 0.7).normalized()
			var q := Quaternion(Vector3.UP, dir)
			var xf := Transform3D(Basis(q), Vector3(side * ln * 0.5, cos(theta) * rad * 0.64, sin(theta) * rad * 0.65)) \
				* Transform3D(Basis.IDENTITY, Vector3(0.0, length * 0.5, 0.0))
			cylinder(eb, 0.0, br, length, 3, 1, false, splinter_col, xf)
		var sb := FL.B.new()
		for i in 5:
			var length: float = 0.3 + r.call() * 0.8
			var bx: float = (r.call() - 0.5) * ln
			var bz: float = (r.call() - 0.5) * rad
			var rz: float = (r.call() - 0.5) * 1.5
			cylinder(sb, 0.023, 0.095, length, 9, 4, false, Color.WHITE,
				Transform3D(Basis(Vector3.BACK, rz), Vector3(bx, rad * 0.72 + length * 0.3, bz)))
		var mesh := lb.finish()
		var group := Transform3D(Basis(Vector3.UP, d[4]), Vector3(x, FM.height_at(x, z) + rad * 0.66, z))
		for part in [[mesh, log_mat], [eb.finish(), end_mat], [sb.finish(), bark_mat]]:
			var mi := MeshInstance3D.new()
			mi.mesh = part[0]
			mi.material_override = part[1]
			mi.transform = group
			add_child(mi)
		logs.append({"mesh": mesh, "xform": group})


# --- litter and mushrooms ----------------------------------------------------------------------------------------

## surfaces.ts litterGeometry: a small curled leaf (ShapeGeometry, 3 divisions per curve) lying on the ground.
static func litter_geometry(seed: int) -> ArrayMesh:
	var r := FM.rng(seed)
	var pts := PackedVector2Array([Vector2.ZERO])
	var bez := func(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2) -> void:
		for k in range(1, 4):
			var t := k / 3.0
			pts.append(p0.bezier_interpolate(p1, p2, p3, t))
	var quad := func(p0: Vector2, p1: Vector2, p2: Vector2) -> void:
		for k in range(1, 4):
			var t := k / 3.0
			pts.append(p0.lerp(p1, t).lerp(p1.lerp(p2, t), t))
	bez.call(Vector2.ZERO, Vector2(-0.038, 0.017), Vector2(-0.07, 0.05), Vector2(-0.037, 0.091))
	quad.call(Vector2(-0.037, 0.091), Vector2(-0.011, 0.12), Vector2(0.0, 0.14))
	quad.call(Vector2(0.0, 0.14), Vector2(0.018, 0.10), Vector2(0.04, 0.073))
	quad.call(Vector2(0.04, 0.073), Vector2(0.06, 0.036), Vector2.ZERO)
	pts.resize(pts.size() - 1)    # the closing point repeats the first
	var b := FL.B.new()
	for p in pts:
		var nn: float = 0.78 + r.call() * 0.22
		var z := -p.y
		b.vertex(Vector3(p.x, 0.008 + sin(-z * 25.0) * 0.022 + absf(p.x) * 0.15, z), Color(0.28 * nn, 0.15 * nn, 0.047 * nn))
	var tris := Geometry2D.triangulate_polygon(pts)
	for k in range(0, tris.size(), 3):
		b.tri(tris[k], tris[k + 2], tris[k + 1])
	return b.finish()


func _litter() -> void:
	var r := FM.rng(516)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var xfs := []
	for i in 17000:
		var x: float = (r.call() - 0.5) * 150.0
		var z: float = (r.call() - 0.5) * 150.0
		var ry: float = r.call() * 6.28
		xfs.append(_xf(Vector3(x, FM.height_at(x, z) + 0.012, z), Vector3(0.0, ry, 0.0), 0.6 + r.call() * 1.1))
	add_child(_mmi(litter_geometry(55), mat, xfs, false))


## three.js SphereGeometry(radius, 12, 7, 0, 2PI, 0, thetaLength): an open cap, single-sided like the original.
static func _cap(b: FL.B, radius: float, ws: int, hs: int, theta_len: float, y0: float, col: Color) -> void:
	var grid := []
	for iy in hs + 1:
		var v := float(iy) / hs
		var row := []
		for ix in ws + 1:
			var u := float(ix) / ws
			row.append(b.vertex(Vector3(-radius * cos(u * TAU) * sin(v * theta_len), radius * cos(v * theta_len) + y0,
				radius * sin(u * TAU) * sin(v * theta_len)), col, u, 1.0 - v))
		grid.append(row)
	for iy in hs:
		for ix in ws:
			var a: int = grid[iy][ix + 1]; var bb: int = grid[iy][ix]; var c: int = grid[iy + 1][ix]; var d: int = grid[iy + 1][ix + 1]
			if iy != 0:
				b.tri(a, bb, d)
			b.tri(bb, c, d)


func _mushrooms() -> void:
	var r := FM.rng(735)
	var b := FL.B.new()
	_cap(b, 0.066, 12, 7, PI * 0.55, 0.14, Color(0.38, 0.23, 0.11))
	cylinder(b, 0.012, 0.018, 0.16, 7, 1, false, Color(0.56, 0.49, 0.35), Transform3D(Basis.IDENTITY, Vector3(0.0, 0.07, 0.0)))
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.85
	var xfs := []
	for i in 400:
		var patch := i / 8
		var x: float = sin(patch * 18.37) * 44.0 + (r.call() - 0.5) * 0.9
		var z: float = cos(patch * 7.26) * 44.0 + (r.call() - 0.5) * 0.9
		var ex: float = (r.call() - 0.5) * 0.3
		var ey: float = r.call() * 6.28
		var ez: float = (r.call() - 0.5) * 0.3
		xfs.append(_xf(Vector3(x, FM.height_at(x, z), z), Vector3(ex, ey, ez), 0.65 + r.call() * 1.2))
	add_child(_mmi(b.finish(), mat, xfs, true))
