extends RefCounted
## Port of app/forest/trees.js: deterministic temperate trees (oak, beech, birch) as real geometry, a swept trunk,
## root buttresses, diverging leaders, boughs, secondary branches, twigs and sprigs carrying individually cupped
## 8-, 4- or 2-triangle leaves. Same random streams as the original, so seed and species give the same tree.
## One pass builds all three detail levels (they consume identical random draws by construction), returning
## { wood: [high, medium, low] ArrayMesh, leaves: [...], height, radius, ground_ring: PackedVector3Array }.

const FM := preload("res://forest_math.gd")
const TAU := PI * 2.0
const UP := Vector3.UP
const DETAILS := ["high", "medium", "low"]

const SPECIES := {
	"oak": {"height": [18.0, 24.0], "girth": [0.46, 0.68], "leaf": [0.11, 0.18], "width": 0.51, "green": "#426332", "bark": 0.15},
	"beech": {"height": [20.0, 26.0], "girth": [0.38, 0.55], "leaf": [0.09, 0.15], "width": 0.59, "green": "#456639", "bark": 0.047},
	"birch": {"height": [17.0, 23.0], "girth": [0.22, 0.36], "leaf": [0.065, 0.115], "width": 0.69, "green": "#526e39", "bark": 0.069},
}


## GeometryWriter: positions, colours, uvs, (three.js CCW) triangles, seams, plus tangents for the bark normal map.
class Writer:
	var detail: String
	var pos := PackedVector3Array()
	var col := PackedColorArray()
	var uv := PackedVector2Array()
	var tan := PackedFloat32Array()
	var idx := PackedInt32Array()
	var seams: Array = []
	var leaf_ordinal := 0
	var leaf_count := 0
	var logical_max_y := 0.0
	var colors := true

	func _init(d: String, with_colors: bool) -> void:
		detail = d
		colors = with_colors

	func vertex(p: Vector3, c: Color, u := 0.0, v := 0.0, t := Vector3.RIGHT) -> int:
		pos.append(p)
		if colors:
			col.append(c)
		uv.append(Vector2(u, v))
		tan.append_array([t.x, t.y, t.z, 1.0])
		return pos.size() - 1

	func tri(a: int, b: int, c: int) -> void:
		idx.append_array([a, b, c])

	## three.js computeVertexNormals (area-weighted, n = (c-b) x (a-b)), seam rings averaged, Godot winding.
	func finish(scale: float) -> ArrayMesh:
		if pos.is_empty():
			return null
		var n := pos.size()
		var nrm := PackedVector3Array()
		nrm.resize(n)
		for i in range(0, idx.size(), 3):
			var a := idx[i]; var b := idx[i + 1]; var c := idx[i + 2]
			var fn := (pos[c] - pos[b]).cross(pos[a] - pos[b])
			nrm[a] += fn; nrm[b] += fn; nrm[c] += fn
		for i in n:
			nrm[i] = nrm[i].normalized()
		for s in seams:
			var m: Vector3 = (nrm[s[0]] + nrm[s[1]]).normalized()
			nrm[s[0]] = m
			nrm[s[1]] = m
		var gi := PackedInt32Array()
		gi.resize(idx.size())
		for i in range(0, idx.size(), 3):
			gi[i] = idx[i]; gi[i + 1] = idx[i + 2]; gi[i + 2] = idx[i + 1]
		var p2 := pos
		if scale != 1.0:
			p2 = PackedVector3Array()
			p2.resize(n)
			for i in n:
				p2[i] = pos[i] * scale
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = p2
		arr[Mesh.ARRAY_NORMAL] = nrm
		arr[Mesh.ARRAY_TANGENT] = tan
		arr[Mesh.ARRAY_TEX_UV] = uv
		if colors:
			arr[Mesh.ARRAY_COLOR] = col
		arr[Mesh.ARRAY_INDEX] = gi
		FM.mesh_lock.lock()
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		FM.mesh_lock.unlock()
		return mesh


var rng: Callable
var species: String
var p: Dictionary
var nominal_height: float
var crown_radius: float
var wood: Array = []     # Writer per detail
var leaves: Array = []
var green: Color
var leaf_scale := 1.2


static func _lin(hex: String) -> Color:
	return Color(hex).srgb_to_linear()


func between(a: float, b: float) -> float:
	return a + (b - a) * rng.call()


static func sample(points: Array, t: float) -> Vector3:
	var f := clampf(t, 0.0, 1.0) * (points.size() - 1)
	var i := mini(points.size() - 2, floori(f))
	return (points[i] as Vector3).lerp(points[i + 1], f - i)


static func tangent(points: Array, t: float) -> Vector3:
	return (sample(points, minf(1.0, t + 0.02)) - sample(points, maxf(0.0, t - 0.02))).normalized()


static func frame(axis: Vector3) -> Array:
	var reference := UP if absf(axis.y) < 0.92 else Vector3(0, 0, 1)
	var u := axis.cross(reference).normalized()
	return [u, axis.cross(u).normalized()]


static func _rotate(v: Vector3, axis: Vector3, angle: float) -> Vector3:
	return v.rotated(axis.normalized(), angle)


## Sweep a tapered ring mesh, frame transported along the axis; written into every detail level's writer.
func tube(writers: Array, points: Array, radii: Array, sides0: int, roughness: float, bark_scale := 1.0) -> Array:
	for i in points.size():
		var y: float = points[i].y + radii[i] * 1.25
		for w in writers:
			w.logical_max_y = maxf(w.logical_max_y, y)
	var phase: float = rng.call() * TAU
	var grain := []
	for k in sides0:
		grain.append(0.87 + rng.call() * 0.25)
	var high_rows := []
	for w in writers:
		var wr: Writer = w
		if wr.detail == "low" and radii[0] < 0.005:
			continue
		var sides := sides0
		if wr.detail == "medium":
			sides = maxi(3, ceili(sides0 * 0.72))
		elif wr.detail == "low":
			sides = maxi(3, ceili(sides0 * 0.47))
		var step := 1 if wr.detail == "high" else 2
		var u := Vector3.ZERO
		var have_u := false
		var distance := 0.0
		var rows := []
		var prev := -1
		for k in points.size():
			if k > 0:
				distance += (points[k] as Vector3).distance_to(points[k - 1])
			if k % step != 0 and k != points.size() - 1:
				continue
			var axis: Vector3 = ((points[mini(points.size() - 1, k + 1)] as Vector3) - (points[maxi(0, k - 1)] as Vector3)).normalized()
			if not have_u:
				u = frame(axis)[0]
				have_u = true
			else:
				u = u - axis * u.dot(axis)
				if u.length_squared() < 0.01:
					u = frame(axis)[0]
				u = u.normalized()
			var v := axis.cross(u).normalized()
			var row := []
			for j in sides + 1:
				var angle := float(j % sides) / sides * TAU
				var ridge := 1.0 + roughness * (0.6 * sin(angle * 5.0 + phase) + 0.28 * sin(angle * 9.0 - phase) + 0.12 * sin(k * 1.3 + angle * 3.0))
				var pt: Vector3 = points[k] + u * (cos(angle) * radii[k] * ridge) + v * (sin(angle) * radii[k] * ridge)
				if k == 0 and points[0].y == 0.0:
					pt.y = 0.0
				var t3 := -u * sin(angle) + v * cos(angle)
				row.append(wr.vertex(pt, Color.WHITE, float(j) / sides * bark_scale, distance / 1.8, t3))
			wr.seams.append([row[0], row[sides]])
			if prev >= 0:
				var pr: Array = rows[prev]
				for j in sides:
					wr.tri(pr[j], pr[j + 1], row[j])
					wr.tri(pr[j + 1], row[j + 1], row[j])
			rows.append(row)
			prev = rows.size() - 1
		if wr.detail == "high" or radii[0] > 0.007:
			var cap := wr.vertex(points[points.size() - 1], Color.WHITE, 0.5, distance / 1.8)
			var end: Array = rows[rows.size() - 1]
			for j in sides:
				wr.tri(cap, end[j], end[j + 1])
		if wr.detail == "high":
			high_rows = rows
	return high_rows


func branch_curve_unused() -> void:
	pass


static func taper(points: Array, radius: float, terminal := 0.004, power := 1.1) -> Array:
	var out := []
	var n := points.size()
	for i in n:
		out.append(terminal + (radius - terminal) * pow(1.0 - float(i) / (n - 1), power))
	return out


# ---- three.js CatmullRomCurve3 (centripetal) with getSpacedPoints ----

static func _crom_point(pts: Array, t: float) -> Vector3:
	var l := pts.size()
	var pp := (l - 1) * t
	var ip := floori(pp)
	var weight := pp - ip
	if weight == 0.0 and ip == l - 1:
		ip = l - 2
		weight = 1.0
	var p0: Vector3 = pts[ip - 1] if ip > 0 else (pts[0] as Vector3) - (pts[1] as Vector3) + (pts[0] as Vector3)
	var p1: Vector3 = pts[ip]
	var p2: Vector3 = pts[ip + 1]
	var p3: Vector3 = pts[ip + 2] if ip + 2 < l else (pts[l - 1] as Vector3) - (pts[l - 2] as Vector3) + (pts[l - 1] as Vector3)
	var dt0 := pow(p0.distance_squared_to(p1), 0.25)
	var dt1 := pow(p1.distance_squared_to(p2), 0.25)
	var dt2 := pow(p2.distance_squared_to(p3), 0.25)
	if dt1 < 1e-4:
		dt1 = 1.0
	if dt0 < 1e-4:
		dt0 = dt1
	if dt2 < 1e-4:
		dt2 = dt1
	var out := Vector3.ZERO
	for c in 3:
		var x0: float = p0[c]; var x1: float = p1[c]; var x2: float = p2[c]; var x3: float = p3[c]
		var t1 := ((x1 - x0) / dt0 - (x2 - x0) / (dt0 + dt1) + (x2 - x1) / dt1) * dt1
		var t2 := ((x2 - x1) / dt1 - (x3 - x1) / (dt1 + dt2) + (x3 - x2) / dt2) * dt1
		var c0 := x1
		var c1 := t1
		var c2 := -3.0 * x1 + 3.0 * x2 - 2.0 * t1 - t2
		var c3 := 2.0 * x1 - 2.0 * x2 + t1 + t2
		out[c] = c0 + c1 * weight + c2 * weight * weight + c3 * weight * weight * weight
	return out


static func spaced_points(pts: Array, segments: int, DIV := 200) -> Array:
	var lengths := PackedFloat64Array([0.0])
	var last := _crom_point(pts, 0.0)
	var sum := 0.0
	for i in range(1, DIV + 1):
		var cur := _crom_point(pts, float(i) / DIV)
		sum += cur.distance_to(last)
		lengths.append(sum)
		last = cur
	var out := []
	for d in segments + 1:
		var target := float(d) / segments * sum
		var lo := 0
		var hi := DIV
		var i := 0
		while lo <= hi:
			i = lo + (hi - lo) / 2
			var cmp := lengths[i] - target
			if cmp < 0.0:
				lo = i + 1
			elif cmp > 0.0:
				hi = i - 1
			else:
				hi = i
				break
		i = clampi(hi, 0, DIV - 1)
		var t: float
		if lengths[i] == target or d == segments:
			t = 1.0 if d == segments else float(i) / DIV
		else:
			t = (i + (target - lengths[i]) / (lengths[i + 1] - lengths[i])) / DIV
		out.append(_crom_point(pts, t))
	return out


func growth_path(origin: Vector3, target: Vector3, parent_dir: Vector3, segments := 8, tortuosity := 1.0) -> Array:
	var disp := target - origin
	var length := disp.length()
	var direction := disp.normalized()
	var fr := frame(direction)
	var side: Vector3 = fr[0]
	var bend: Vector3 = fr[1]
	var outgoing := parent_dir.normalized().lerp(direction, 0.42).normalized()
	var a := origin + outgoing * (length * 0.19)
	var b: Vector3 = origin.lerp(target, 0.45) + side * ((rng.call() - 0.5) * length * 0.28 * tortuosity)
	b += bend * ((rng.call() - 0.46) * length * 0.14 * tortuosity)
	var c: Vector3 = origin.lerp(target, 0.76) + side * ((rng.call() - 0.5) * length * 0.23 * tortuosity)
	c += bend * ((rng.call() - 0.4) * length * 0.12 * tortuosity)
	var pts := spaced_points([origin, a, b, c, target], segments)
	pts[0] = origin
	pts[pts.size() - 1] = target
	return pts


func diverging_leader(origin: Vector3, target: Vector3, segments := 20) -> Array:
	var horizontal := target - origin
	horizontal.y = 0.0
	var distance := horizontal.length()
	horizontal = horizontal.normalized()
	var side := Vector3(-horizontal.z, 0.0, horizontal.x)
	var initial_out: float = 0.45 + rng.call() * 0.28
	var vertical_bow: float = (rng.call() - 0.5) * 0.03
	var lateral_bow: float = (rng.call() - 0.5) * 0.012
	var upper_bow: float = (rng.call() - 0.5) * 0.006
	var pts := []
	for i in segments + 1:
		var t := float(i) / segments
		var radial := distance * (initial_out * t + (1.0 - initial_out) * t * t)
		var pt := origin + horizontal * radial + side * (distance * lateral_bow * sin(t * PI))
		pt.y = origin.y + (target.y - origin.y) * (t + vertical_bow * sin(t * PI) + upper_bow * sin(t * TAU))
		pts.append(pt)
	pts[0] = origin
	pts[pts.size() - 1] = target
	return pts


func root_buttress(angle: float, length: float, width: float, height: float) -> void:
	var forward := Vector3(cos(angle), 0.0, sin(angle))
	var side := Vector3(-sin(angle), 0.0, cos(angle))
	var bend: float = (rng.call() - 0.5) * 0.38
	for w in wood:
		var wr: Writer = w
		var rows := []
		for k in 7:
			var t := k / 6.0
			var center := forward * (length * t) + side * (sin(t * 2.5) * bend)
			var ww := width * pow(1.0 - t, 1.35) + 0.008
			var h := height * pow(1.0 - t, 2.05) + 0.005
			var row := []
			for j in 7:
				var theta := j / 6.0 * PI
				var pt := center + side * (cos(theta) * ww)
				pt.y = 0.0 if j == 0 or j == 6 else sin(theta) * h
				row.append(wr.vertex(pt, Color.WHITE, j / 6.0, length * t / 1.8, side))
			if k > 0:
				var pr: Array = rows[k - 1]
				for j in 6:
					wr.tri(pr[j], row[j], pr[j + 1])
					wr.tri(pr[j + 1], row[j], row[j + 1])
			rows.append(row)


func add_leaf(base: Vector3, direction: Vector3, size0: float, width_ratio: float, color: Color) -> void:
	var forward := direction.normalized()
	var side := UP.cross(forward)
	if side.length_squared() < 0.015:
		side = Vector3(1, 0, 0)
	side = _rotate(side.normalized(), forward, (rng.call() - 0.5) * 1.8)
	var normal := forward.cross(side).normalized()
	var twist: float = (rng.call() - 0.5) * 0.42
	var cup_k: float = 0.045 + rng.call() * 0.075
	var curve_k: float = rng.call() * 0.2 - 0.045
	var leaf_color: Color = color * (0.78 + rng.call() * 0.4)
	leaf_color.a = 1.0
	var tip_color: Color = leaf_color.lerp(_lin("#738648"), 0.08 + rng.call() * 0.14)
	var wide_first := 1.0 if species == "birch" else 0.84
	var wide_second := 0.54 if species == "birch" else 0.74
	for w in leaves:
		var wr: Writer = w
		var ordinal := wr.leaf_ordinal
		wr.leaf_ordinal += 1
		var retained := wr.detail == "high" or (ordinal % 3 == 0 if wr.detail == "medium" else ordinal % 6 == 0)
		if not retained:
			continue
		var leaf_detail := ("medium" if ordinal % 4 == 0 else "high") if wr.detail == "high" else ("medium" if wr.detail == "medium" else "low")
		var size := size0 * (1.6 if wr.detail == "medium" else (2.2 if wr.detail == "low" else 1.0))
		var cup := size * cup_k
		var curve := size * curve_k
		var width := size * width_ratio
		var lp := func(s: float, t: float) -> Vector3:
			return base + forward * (size * t) + side * (s * width * 0.5) \
				+ normal * (curve * t * t + cup * (1.0 - absf(s)) * sin(t * PI) + s * twist * size * t)
		wr.leaf_count += 1
		if leaf_detail != "high":
			var b := wr.vertex(base, leaf_color, 0.5, 0.0)
			var l := wr.vertex(lp.call(-1.0, 0.43), leaf_color, 0.0, 0.43)
			var r := wr.vertex(lp.call(1.0, 0.43), leaf_color, 1.0, 0.43)
			var tip := wr.vertex(lp.call(0.0, 1.0), tip_color, 0.5, 1.0)
			if leaf_detail == "medium":
				var cc: Color = leaf_color * 1.045
				cc.a = 1.0
				var center := wr.vertex(lp.call(0.0, 0.43), cc, 0.5, 0.43)
				wr.tri(b, l, center); wr.tri(b, center, r)
				wr.tri(l, tip, center); wr.tri(center, tip, r)
			else:
				wr.tri(b, l, tip); wr.tri(b, tip, r)
			continue
		var c1c: Color = leaf_color * 1.045
		c1c.a = 1.0
		var c2c: Color = tip_color * 1.025
		c2c.a = 1.0
		var b := wr.vertex(base, leaf_color, 0.5, 0.0)
		var l1 := wr.vertex(lp.call(-wide_first, 0.34), leaf_color, 0.0, 0.34)
		var c1 := wr.vertex(lp.call(0.0, 0.34), c1c, 0.5, 0.34)
		var r1 := wr.vertex(lp.call(wide_first, 0.34), leaf_color, 1.0, 0.34)
		var l2 := wr.vertex(lp.call(-wide_second, 0.73), tip_color, 0.15, 0.73)
		var c2 := wr.vertex(lp.call(0.0, 0.73), c2c, 0.5, 0.73)
		var r2 := wr.vertex(lp.call(wide_second, 0.73), tip_color, 0.85, 0.73)
		var tip := wr.vertex(lp.call(0.0, 1.0), tip_color, 0.5, 1.0)
		wr.tri(b, l1, c1); wr.tri(b, c1, r1)
		wr.tri(l1, l2, c1); wr.tri(l2, c2, c1)
		wr.tri(c1, c2, r1); wr.tri(c2, r2, r1)
		wr.tri(l2, tip, c2); wr.tri(c2, tip, r2)


func leaf_spray(path: Array, count0: int, vigor := 1.0, start_t := 0.15) -> void:
	var count := roundi(count0 * 2.7)
	var phase: float = rng.call() * TAU
	for j in count:
		var t := start_t + (1.0 - start_t) * (j + between(0.15, 0.85)) / count
		var base := sample(path, t)
		var axis := tangent(path, t)
		var fr := frame(axis)
		var angle := phase + j * 2.399963229728653 + between(-0.3, 0.3)
		var outward: Vector3 = fr[0] * cos(angle) + fr[1] * sin(angle)
		var direction := (axis * between(0.28, 0.67) + outward + UP * between(-0.18, 0.42)).normalized()
		var sunk := clampf((base.y / nominal_height - 0.44) * 0.45, 0.0, 0.25)
		var color: Color = green.lerp(_lin("#6c8140"), sunk) * vigor
		color.a = 1.0
		var leaf_length := between(p.leaf[0], p.leaf[1]) * between(0.91, 1.12) * leaf_scale
		for w in leaves:
			w.logical_max_y = maxf(w.logical_max_y, base.y + leaf_length * 2.1)
		add_leaf(base, direction, leaf_length, p.width, color)


func foliate_lobe(bough: Array, center: Vector3, hr: float, vr: float, bough_radius: float, sub_count := 3, twig_count := 5) -> void:
	leaf_spray(bough, 16, 0.94, 0.78)
	var phase: float = rng.call() * TAU
	for j in sub_count:
		var attachment := 0.4 + float(j) / sub_count * 0.48 + between(-0.035, 0.035)
		var origin := sample(bough, attachment)
		var a := phase + j * 2.39996 + between(-0.45, 0.45)
		var elevation := between(-0.55, 0.8)
		var reach := hr * sqrt(1.0 - elevation * elevation) * between(0.58, 0.95)
		var target := center + Vector3(cos(a) * reach, elevation * vr, sin(a) * reach)
		var secondary := growth_path(origin, target, tangent(bough, attachment), 6, 0.85)
		var secondary_radius := maxf(0.017, bough_radius * pow(1.0 - attachment, 0.9) * 0.53)
		tube(wood, secondary, taper(secondary, secondary_radius, 0.0038), 4, 0.027)
		leaf_spray(secondary, 12, between(0.88, 1.03), 0.65)
		for k in twig_count:
			var twig_t := 0.18 + float(k) / twig_count * 0.72 + between(-0.025, 0.025)
			var twig_origin := sample(secondary, twig_t)
			var twig_angle := a - 1.08 + float(k) / maxi(1, twig_count - 1) * 2.16 + between(-0.23, 0.23)
			var twig_elev := between(-0.75, 0.82)
			var twig_reach := hr * (between(0.16, 0.36) if k == 2 else between(0.57, 1.04))
			var twig_target := center + Vector3(cos(twig_angle) * twig_reach, twig_elev * vr, sin(twig_angle) * twig_reach)
			if species == "birch":
				twig_target.y -= between(0.05, 0.32)
			var twig := growth_path(twig_origin, twig_target, tangent(secondary, twig_t), 4, 0.64)
			var twig_radius := maxf(0.006, secondary_radius * (1.0 - twig_t) * 0.39)
			tube(wood, twig, taper(twig, twig_radius, 0.0016), 3, 0.015)
			leaf_spray(twig, 18, between(0.9, 1.04), 0.12)
			var sprig_phase: float = rng.call() * TAU
			for s in 6:
				var sprig_t := 0.12 + s * 0.14
				var start := sample(twig, sprig_t)
				var axis := tangent(twig, sprig_t)
				var fr := frame(axis)
				var angle := sprig_phase + s * 2.39996 + between(-0.25, 0.25)
				var dir: Vector3 = (fr[0] * cos(angle) + fr[1] * sin(angle) + axis * 0.36 + UP * (-0.07 if species == "birch" else 0.12)).normalized()
				var end := start + dir * between(0.32, 0.62)
				var sprig := [start, end]
				tube(wood, sprig, [0.0036, 0.0011], 3, 0.0)
				leaf_spray(sprig, 12, between(0.9, 1.04), 0.05)


func generate(seed: int, sp: String) -> Dictionary:
	species = sp if SPECIES.has(sp) else "oak"
	p = SPECIES[species]
	rng = FM.random_source("%s:%d" % [species, seed])
	nominal_height = between(p.height[0], p.height[1])
	var trunk_radius := between(p.girth[0], p.girth[1])
	wood = []
	leaves = []
	for d in DETAILS:
		wood.append(Writer.new(d, false))
		leaves.append(Writer.new(d, true))
	green = _lin(p.green)
	crown_radius = nominal_height * (0.318 if species == "oak" else (0.26 if species == "beech" else 0.198))
	var azimuth: float = rng.call() * TAU
	var stem_height := nominal_height * (between(0.445, 0.505) if species == "oak" else (0.87 if species == "beech" else 0.915))
	var lean := between(0.015, 0.037) * nominal_height
	var stem_target := Vector3(cos(azimuth) * lean, stem_height, sin(azimuth) * lean)
	var trunk := growth_path(Vector3.ZERO, stem_target, UP, 26, 0.3 if species == "oak" else 0.22)
	var stem_end_radius := trunk_radius * 0.69 if species == "oak" else 0.025
	var trunk_radii := []
	for i in trunk.size():
		var t := float(i) / (trunk.size() - 1)
		var radius: float
		if species == "oak":
			radius = trunk_radius * (1.0 - t * 0.22) if t < 0.81 else 0.014 + trunk_radius * 0.808 * pow((1.0 - t) / 0.19, 0.92)
		else:
			radius = stem_end_radius + (trunk_radius - stem_end_radius) * pow(1.0 - t, 0.9)
		trunk_radii.append(radius * (1.0 + 0.55 * exp(-t * 25.0)))
	var trunk_rows := tube(wood, trunk, trunk_radii, 12 if species == "birch" else 16, p.bark, 3.0)
	var root_count := 5 if species == "birch" else 7
	for i in root_count:
		root_buttress(float(i) / root_count * TAU + between(-0.24, 0.24), trunk_radius * between(3.2, 5.2),
			trunk_radius * between(0.4, 0.6), trunk_radius * between(1.0, 1.6))

	var scaffolds := []
	if species == "oak":
		var count: int = 2 + floori(rng.call() * 3)
		var weights := []
		var total := 0.0
		for i in count:
			weights.append(between(0.65, 1.2))
			total += weights[i]
		for i in count:
			var t := 0.83 if i == 0 else between(0.805, 0.855)
			var origin := sample(trunk, t)
			var angle := azimuth + float(i) / count * TAU + between(-0.37, 0.37)
			var radial := crown_radius * between(0.38, 0.63)
			var target := Vector3(cos(angle) * radial, nominal_height * between(0.79, 0.86), sin(angle) * radial)
			var path := diverging_leader(origin, target, 20)
			var radius := stem_end_radius * sqrt(weights[i] / total) * 1.04
			tube(wood, path, taper(path, radius, 0.023, 0.88), 10, p.bark * 0.8, 1.7)
			scaffolds.append({"path": path, "radius": radius, "angle": angle, "min": 0.39, "span": 0.51,
				"boughs": 5 if count == 2 else (4 if count == 3 else 3), "central": false})
	else:
		scaffolds.append({"path": trunk, "radius": trunk_radius * 0.44, "angle": azimuth, "min": 0.58, "span": 0.37, "boughs": 4, "central": true})
		for i in 2:
			var t := (0.49 if species == "birch" else 0.44) + i * 0.17 + between(-0.035, 0.035)
			var origin := sample(trunk, t)
			var angle := azimuth + i * 2.65 + between(-0.6, 0.6)
			var reach := crown_radius * between(0.42, 0.64)
			var target := Vector3(cos(angle) * reach, nominal_height * between(0.8, 0.88), sin(angle) * reach)
			var path := diverging_leader(origin, target, 16)
			var radius := trunk_radius * pow(1.0 - t, 0.8) * between(0.53, 0.64)
			tube(wood, path, taper(path, radius, 0.014), 8, p.bark * 0.7)
			scaffolds.append({"path": path, "radius": radius, "angle": angle, "min": 0.35, "span": 0.55, "boughs": 4, "central": false})

	for sc in scaffolds:
		var nb: int = sc.boughs
		for j in nb:
			var t: float = sc.min + float(j) / maxi(1, nb - 1) * sc.span + between(-0.025, 0.025)
			var origin := sample(sc.path, t)
			var inward := j >= 2 and not (nb == 5 and j == 3)
			var angle: float
			if sc.central:
				angle = sc.angle + j * 2.13 + between(-0.6, 0.6)
			else:
				angle = sc.angle + [-1.02, 0.96, 1.5, -0.06, -0.7][j] + between(-0.33, 0.33)
			var radial := crown_radius * (between(0.17, 0.38) if inward else between(0.63, 0.84))
			var lobe_y: float
			if j == 0:
				lobe_y = nominal_height * between(0.68, 0.76)
			elif j == 1:
				lobe_y = nominal_height * between(0.77, 0.85)
			elif j == 2:
				lobe_y = nominal_height * between(0.765, 0.82)
			elif inward:
				lobe_y = nominal_height * between(0.86, 0.92)
			else:
				lobe_y = nominal_height * between(0.82, 0.88)
			var center := Vector3(cos(angle) * radial, lobe_y, sin(angle) * radial)
			var end := center + Vector3(between(-0.22, 0.22), between(-0.32, 0.04), between(-0.22, 0.22))
			var bough := growth_path(origin, end, tangent(sc.path, t), 12, 0.83 if species == "oak" else 0.66)
			var radius := maxf(0.038, sc.radius * pow(1.0 - t, 0.73) * between(0.5, 0.72))
			tube(wood, bough, taper(bough, radius, 0.007, 1.03), 6, p.bark * 0.55)
			var hr := crown_radius * between(0.29 if inward else 0.31, 0.38 if inward else 0.4)
			var vr := nominal_height * between(0.1, 0.135)
			foliate_lobe(bough, center, hr, vr, radius)

	# lower growth: its own seed, so pruning history varies without moving the main crown
	var lower_growth := FM.random_source("%s:%d:lower-growth" % [species, seed])
	var retains := (FM.hash_seed("%s:%d:lower-branches" % [species, seed]) & 1) == 0
	var low_count := (2 if species == "oak" else 1) if retains else 0
	for i in low_count:
		var t := between(0.56, 0.75) if species == "oak" else between(0.29, 0.4)
		var origin := sample(trunk, t)
		var angle := azimuth + 1.9 + i * 2.5 + between(-0.55, 0.55)
		var reach := crown_radius * between(0.35, 0.58)
		var center := origin + Vector3(cos(angle) * reach, nominal_height * between(0.065, 0.12), sin(angle) * reach)
		var path := growth_path(origin, center, tangent(trunk, t).lerp(Vector3(cos(angle), 0.2, sin(angle)), 0.62), 8, 1.1)
		var radius := trunk_radius * between(0.12, 0.18)
		tube(wood, path, taper(path, radius, 0.004), 6, p.bark * 0.55)
		foliate_lobe(path, center, crown_radius * 0.17, nominal_height * 0.04, radius, 2, 3)
	var epi_count := 0
	if not retains and FM.hash_seed("%s:%d:epicormic-shoots" % [species, seed]) % 4 == 1:
		epi_count = 2 + floori(lower_growth.call() * 3)
	for i in epi_count:
		var t: float = 0.2 + float(i) / maxi(1, epi_count - 1) * 0.34 + (lower_growth.call() - 0.5) * 0.08
		var origin := sample(trunk, t)
		var angle: float = azimuth + lower_growth.call() * TAU
		var outward := Vector3(cos(angle), 0.0, sin(angle))
		var ri := t * (trunk_radii.size() - 1)
		var radius := lerpf(trunk_radii[floori(ri)], trunk_radii[ceili(ri)], fmod(ri, 1.0))
		var shoulder := origin + outward * (radius * 1.14) + UP * 0.04
		var end: Vector3 = shoulder + outward * (0.2 + lower_growth.call() * 0.26) + UP * (0.12 + lower_growth.call() * 0.2)
		var shoot := [origin, shoulder, end]
		tube(wood, shoot, [0.009, 0.0045, 0.0012], 3, 0.012)
		leaf_spray(shoot, 6, 0.94, 0.68)

	var max_y := 0.0
	for w in wood + leaves:
		max_y = maxf(max_y, w.logical_max_y)
	var tree_scale := minf(1.0, 26.0 / max_y)
	var out := {"wood": [], "leaves": [], "scale": tree_scale}
	for i in 3:
		out.wood.append((wood[i] as Writer).finish(tree_scale))
		out.leaves.append((leaves[i] as Writer).finish(tree_scale))
	var hw: Writer = wood[0]
	var ring := PackedVector3Array()
	for v in hw.pos:
		if absf(v.y) < 1e-7:
			ring.append(v * tree_scale)
	out["ground_ring"] = ring
	var trunk_ring := 0.0
	if trunk_rows.size() > 0:
		for vi in trunk_rows[0]:
			var v: Vector3 = hw.pos[vi] * tree_scale
			trunk_ring = maxf(trunk_ring, Vector2(v.x, v.z).length())
	out["trunk_radius"] = trunk_ring
	# trees.js trunkSurfaceRows (as positions): the high-detail trunk rings, which trunk-life.ts climbs and fixes to
	var rows := []
	for row in trunk_rows:
		var pts := PackedVector3Array()
		for vi in row:
			pts.append(hw.pos[vi] * tree_scale)
		rows.append(pts)
	out["trunk_rows"] = rows
	var aabb: AABB = out.wood[0].get_aabb().merge(out.leaves[0].get_aabb())
	out["height"] = aabb.end.y
	out["leaf_count"] = (leaves[0] as Writer).leaf_count
	return out
