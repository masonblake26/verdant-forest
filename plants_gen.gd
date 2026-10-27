extends RefCounted
## Port of app/forest/understory.js (grass) and botanical-refinement.js (ferns, shrubs, herbs): curved, indexed,
## vertex-coloured plant geometry in metres. Ferns are bipinnate up close (separate curved pinnules on a tubular
## costa), pinnatifid at medium range and folded laminae far away, with ageing fronds and fiddleheads; shrubs carry
## toothed broad leaves; herbs are wood sorrel, a flowering weed, ivy, nettles and ramsons.

const FM := preload("res://forest_math.gd")
const TAU := PI * 2.0
const UP := Vector3.UP
const GREEN := Color(0.055, 0.119, 0.035)
const FRESH := Color(0.135, 0.204, 0.060)
const STEM := Color(0.078, 0.087, 0.024)
const BARK := Color(0.086, 0.060, 0.037)


static func tone(c: Color, m: float) -> Color:
	return Color(c.r * m, c.g * m, c.b * m)


static func blend(a: Color, b: Color, t: float) -> Color:
	return Color(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t)


static func V(x := 0.0, y := 0.0, z := 0.0) -> Vector3:
	return Vector3(x, y, z)


class MB:
	var p := PackedVector3Array()
	var uv := PackedVector2Array()
	var c := PackedColorArray()
	var i := PackedInt32Array()
	var pinnules := 0

	func vertex(pt: Vector3, u: float, v: float, col: Color) -> int:
		p.append(pt)
		uv.append(Vector2(u, v))
		c.append(col)
		return p.size() - 1

	func tri(a: int, b: int, cc: int) -> void:
		i.append_array([a, b, cc])

	## understory MeshBuilder.finish: lowest surface to y = 0, uniform scale, three.js normals, Godot winding.
	func finish(scale := 1.0) -> ArrayMesh:
		var lowest := INF
		for v in p:
			lowest = minf(lowest, v.y)
		var n := p.size()
		var pos := PackedVector3Array()
		pos.resize(n)
		for k in n:
			pos[k] = Vector3(p[k].x * scale, (p[k].y - lowest) * scale, p[k].z * scale)
		var nrm := PackedVector3Array()
		nrm.resize(n)
		for k in range(0, i.size(), 3):
			var a := i[k]; var b := i[k + 1]; var cc := i[k + 2]
			var fn := (pos[cc] - pos[b]).cross(pos[a] - pos[b])
			nrm[a] += fn; nrm[b] += fn; nrm[cc] += fn
		for k in n:
			nrm[k] = nrm[k].normalized()
		var gi := PackedInt32Array()
		gi.resize(i.size())
		for k in range(0, i.size(), 3):
			gi[k] = i[k]; gi[k + 1] = i[k + 2]; gi[k + 2] = i[k + 1]
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = pos
		arr[Mesh.ARRAY_NORMAL] = nrm
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_COLOR] = c
		arr[Mesh.ARRAY_INDEX] = gi
		FM.mesh_lock.lock()
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		FM.mesh_lock.unlock()
		return m


static func frame(t0: Vector3) -> Array:
	var t := t0.normalized()
	var reference := Vector3(1, 0, 0) if absf(t.y) > 0.92 else UP
	var a := reference.cross(t).normalized()
	return [a, t.cross(a).normalized()]


static func tube(mesh: MB, points: Array, root_r: float, tip_r: float, color: Color, sides := 5, caps := true) -> void:
	var rings := []
	var prev_a := Vector3.ZERO
	var have := false
	for j in points.size():
		var tg: Vector3 = ((points[mini(j + 1, points.size() - 1)] as Vector3) - (points[maxi(j - 1, 0)] as Vector3)).normalized()
		var a: Vector3 = prev_a - tg * prev_a.dot(tg) if have else frame(tg)[0]
		if a.length_squared() < 1e-10:
			a = frame(tg)[0]
		a = a.normalized()
		var b := tg.cross(a).normalized()
		prev_a = a
		have = true
		var t := float(j) / (points.size() - 1)
		var radius := root_r + (tip_r - root_r) * t
		var ring := []
		for k in sides:
			var ang := k * TAU / sides
			ring.append(mesh.vertex(points[j] + a * (cos(ang) * radius) + b * (sin(ang) * radius), float(k) / sides, t, tone(color, 0.91 + t * 0.14)))
		rings.append(ring)
	for j in rings.size() - 1:
		for k in sides:
			var nx := (k + 1) % sides
			mesh.tri(rings[j][k], rings[j][nx], rings[j + 1][k])
			mesh.tri(rings[j][nx], rings[j + 1][nx], rings[j + 1][k])
	if caps:
		for end in [0, rings.size() - 1]:
			var center := mesh.vertex(points[end], 0.5, 1.0 if end else 0.0, color)
			var cap := []
			for idx in rings[end]:
				cap.append(mesh.vertex(mesh.p[idx], 0.0, 0.0, color))
			for k in sides:
				var nx := (k + 1) % sides
				if end == 0:
					mesh.tri(center, cap[nx], cap[k])
				else:
					mesh.tri(center, cap[k], cap[nx])


static func sample_curve(fn: Callable, segments: int) -> Array:
	var out := []
	for j in segments + 1:
		out.append(fn.call(float(j) / segments))
	return out


static func _leaf_frame(direction: Vector3, plane_normal := UP) -> Array:
	var axis := direction.normalized()
	var side := plane_normal.cross(axis).normalized()
	if side.length_squared() < 1e-8:
		side = Vector3(1, 0, 0)
	var normal := axis.cross(side).normalized()
	return [axis, side, normal]


static func folded_leaf(mesh: MB, base: Vector3, direction: Vector3, length: float, width: float, color: Color, o := {}) -> void:
	var curl: float = o.get("curl", 0.15)
	var twist: float = o.get("twist", 0.0)
	var ridge: float = o.get("ridge", 0.08)
	var f := _leaf_frame(direction)
	var axis: Vector3 = f[0]; var side: Vector3 = f[1]; var normal: Vector3 = f[2]
	if normal.y < 0.0:
		normal = -normal; side = -side
	side = side.rotated(axis, twist * 0.5)
	var middle := base + axis * (length * 0.5) + normal * (length * curl * 0.156 - width * (0.12 + ridge))
	var tip := base + axis * length + normal * (length * curl * sin(PI * 0.9))
	var a := mesh.vertex(base, 0.5, 0.0, color)
	var l := mesh.vertex(middle - side * (width * 0.5), 0.0, 0.5, tone(color, 0.96))
	var t := mesh.vertex(tip, 0.5, 1.0, blend(color, FRESH, 0.12))
	var r := mesh.vertex(middle + side * (width * 0.5), 1.0, 0.5, tone(color, 0.98))
	mesh.tri(a, l, t)
	mesh.tri(a, t, r)


static func fern_pinna(mesh: MB, base: Vector3, direction: Vector3, length: float, width: float, color: Color, o := {}) -> void:
	var curl: float = o.get("curl", 0.12)
	var twist: float = o.get("twist", 0.0)
	var detail: String = o.get("detail", "high")
	var dry: float = o.get("dry", 0.0)
	var f := _leaf_frame(direction)
	var axis: Vector3 = f[0]; var side: Vector3 = f[1]; var normal: Vector3 = f[2]
	var lobes := (3 + floori(length * 4.0)) if detail == "medium" else (6 + floori(length * 8.0))
	var at := func(t: float, transverse: float) -> Vector3:
		var across := side.rotated(axis, twist * t)
		return base + axis * (length * t) + normal * (length * (curl * sin(t * PI * 0.9) + (0.025 + dry * 0.075) * pow(maxf(0.0, (t - 0.72) / 0.28), 2.0))) \
			+ across * transverse + normal * (-absf(transverse) * 0.08)
	var shade := func(t: float) -> Color: return blend(color, Color(0.22, 0.155, 0.065), dry * t * 0.42)
	var rows := []
	for j in lobes + 1:
		var t := float(j) / lobes
		var half := width * 0.055 * pow(sin(t * PI), 0.75)
		if j == 0 or j == lobes:
			rows.append([mesh.vertex(at.call(t, 0.0), 0.5, t, tone(shade.call(t), 1.06))])
		else:
			rows.append([mesh.vertex(at.call(t, -half), 0.0, t, tone(shade.call(t), 1.05)), mesh.vertex(at.call(t, half), 1.0, t, tone(shade.call(t), 1.05))])
	mesh.tri(rows[0][0], rows[1][0], rows[1][1])
	for j in range(1, lobes - 1):
		mesh.tri(rows[j][0], rows[j + 1][0], rows[j][1])
		mesh.tri(rows[j][1], rows[j + 1][0], rows[j + 1][1])
	mesh.tri(rows[lobes - 1][0], rows[lobes][0], rows[lobes - 1][1])
	for j in lobes:
		var t0 := float(j) / lobes
		var t1 := float(j + 1) / lobes
		for sign: float in [-1.0, 1.0]:
			var tl := t0 + (t1 - t0) * 0.22
			var tp := t0 + (t1 - t0) * 0.5
			var ts := t0 + (t1 - t0) * 0.72
			var env := pow(sin(tp * PI), 0.72)
			var lw := width * 0.5 * env * (1.0 - dry * 0.08 * (j % 2))
			var root0: int = rows[j][0 if j == 0 else (0 if sign < 0 else 1)]
			var root1: int = rows[j + 1][0 if j + 1 == lobes else (0 if sign < 0 else 1)]
			var lower := mesh.vertex(at.call(tl, sign * lw * 0.66), 0.14 if sign < 0 else 0.86, tl, tone(shade.call(tl), 0.98))
			var peak := mesh.vertex(at.call(tp, sign * lw) + normal * (lw * (0.055 + dry * 0.08)), 0.0 if sign < 0 else 1.0, tp, shade.call(tp))
			var shoulder := mesh.vertex(at.call(ts, sign * lw * 0.55), 0.2 if sign < 0 else 0.8, ts, tone(shade.call(ts), 0.96))
			if sign < 0:
				mesh.tri(root0, lower, peak); mesh.tri(root0, peak, shoulder); mesh.tri(root0, shoulder, root1)
			else:
				mesh.tri(root0, peak, lower); mesh.tri(root0, shoulder, peak); mesh.tri(root0, root1, shoulder)


static func lance_leaf(mesh: MB, base: Vector3, direction: Vector3, length: float, width: float, color: Color, o := {}) -> void:
	var sections: int = o.get("sections", 5)
	var curl: float = o.get("curl", 0.15)
	var twist: float = o.get("twist", 0.0)
	var serration: float = o.get("serration", 0.0)
	var ridge: float = o.get("ridge", 0.08)
	var f := _leaf_frame(direction, o.get("planeNormal", UP))
	var axis: Vector3 = f[0]; var side: Vector3 = f[1]; var normal: Vector3 = f[2]
	if normal.y < 0.0:
		normal = -normal; side = -side
	var tipc: Color = o.get("tipColor", tone(FRESH, 0.87))
	var rows := []
	for j in sections + 1:
		var t := float(j) / sections
		var center := base + axis * (length * t) + normal * (length * curl * sin(t * PI * 0.9))
		var w := width * 0.5 * pow(sin(t * PI), 0.77) * (1.0 + serration * (1.0 if j % 2 else -1.0))
		var lc := blend(color, tipc, t * 0.16)
		if j == 0 or j == sections:
			rows.append([mesh.vertex(center, 0.5, t, lc)])
			continue
		var side_at := side.rotated(axis, twist * t)
		var row := []
		for s: float in [-1.0, 0.0, 1.0]:
			row.append(mesh.vertex(center + side_at * (s * w) + normal * (w * ridge if s == 0.0 else -w * 0.075), (s + 1.0) / 2.0, t, tone(lc, 1.065 if s == 0.0 else 0.96)))
		rows.append(row)
	mesh.tri(rows[0][0], rows[1][0], rows[1][1])
	mesh.tri(rows[0][0], rows[1][1], rows[1][2])
	for j in range(1, sections - 1):
		for k in 2:
			mesh.tri(rows[j][k], rows[j + 1][k], rows[j][k + 1])
			mesh.tri(rows[j][k + 1], rows[j + 1][k], rows[j + 1][k + 1])
	var last: Array = rows[sections - 1]
	var tip: int = rows[sections][0]
	mesh.tri(last[0], tip, last[1])
	mesh.tri(last[1], tip, last[2])


static func bipinnate_pinna(mesh: MB, base: Vector3, direction: Vector3, length: float, width: float, color: Color, o := {}) -> void:
	var curl: float = o.get("curl", 0.12)
	var twist: float = o.get("twist", 0.0)
	var dry: float = o.get("dry", 0.0)
	var f := _leaf_frame(direction)
	var axis: Vector3 = f[0]; var side: Vector3 = f[1]; var normal: Vector3 = f[2]
	var ideal := func(t: float) -> Vector3:
		return base + axis * (length * t) + normal * (length * (curl * sin(t * PI * 0.9) + (0.018 + dry * 0.065) * pow(maxf(0.0, (t - 0.74) / 0.26), 2.0)))
	var costa := sample_curve(ideal, 5)
	var at := func(t: float) -> Vector3:
		var smp := clampf(t, 0.0, 1.0) * 5.0
		var seg := mini(4, floori(smp))
		return (costa[seg] as Vector3).lerp(costa[seg + 1], smp - seg)
	tube(mesh, costa, maxf(0.00026, width * 0.013), 0.00013, blend(STEM, color, 0.54), 4)
	var pairs := 10 + floori(length * 12.0)
	for pair in pairs:
		for sign: float in [-1.0, 1.0]:
			var t := 0.075 + float(pair) / (pairs - 1) * 0.82 + (0.012 if sign > 0 else 0.0)
			var env := pow(sin(t * PI), 0.72) * (1.0 - t * 0.12)
			var across := side.rotated(axis, twist * t)
			var pn := normal.rotated(axis, twist * t)
			var wav := sin(pair * 2.27 + sign * 0.61 + length * 43.0)
			var pdir := (across * sign + axis * (0.3 + t * 0.13 + wav * 0.055) + pn * (0.045 + wav * 0.025)).normalized()
			var plen := width * 0.59 * env * (1.0 + wav * 0.045)
			var pw := minf(length / pairs * 0.85, plen * 0.48)
			var opts := {"sections": 4, "curl": 0.075 + dry * 0.17 + wav * 0.025, "twist": sign * (0.055 + dry * 0.15),
				"serration": 0.055, "ridge": 0.23, "planeNormal": pn}
			if dry > 0.25:
				opts["tipColor"] = Color(0.235, 0.153, 0.057)
			lance_leaf(mesh, at.call(t), pdir, plen, pw, tone(color, 0.965 + (wav + 1.0) * 0.038), opts)
			mesh.pinnules += 1
	lance_leaf(mesh, at.call(0.92), axis + normal * 0.08, length * 0.095, width * 0.17, tone(color, 1.025),
		{"sections": 5, "curl": 0.12 + dry * 0.17, "ridge": 0.19, "planeNormal": normal})


static func fern(seed: int, detail := "high") -> ArrayMesh:
	var rng := FM.random_source(str(seed))
	var mesh := MB.new()
	var low := detail == "low"
	var medium := detail == "medium"
	var age := FM.random_source("%d:fern-life-cycle" % seed)
	var count: int = 8 + floori(rng.call() * 3)
	var height: float = 0.82 + rng.call() * 0.3
	var azimuth: float = rng.call() * TAU
	for fi in count:
		var dry: float = (0.3 + age.call() * 0.42) if fi == count - 1 else ((age.call() * 0.15) if fi == count - 2 else 0.0)
		var wear: float = age.call()
		var angle: float = azimuth + fi * TAU / count + (rng.call() - 0.5) * 0.32
		var radial := V(cos(angle), 0, sin(angle))
		var lateral := V(-sin(angle), 0, cos(angle))
		var h: float = height * (1.0 if fi == 0 else 0.68 + rng.call() * 0.32) * (1.0 - dry * 0.4)
		var reach: float = 0.62 + rng.call() * 0.32 + (1.0 - h / height) * 0.24
		var sway: float = (rng.call() - 0.5) * 0.17
		var ideal := func(t: float) -> Vector3:
			return radial * (0.018 + reach * pow(t, 1.65)) + lateral * (sway * t * t) + V(0, h * sin(t * PI * 0.75), 0)
		var skeleton := sample_curve(ideal, 16)
		var curve := func(t: float) -> Vector3:
			var smp := clampf(t, 0.0, 1.0) * 16.0
			var seg := mini(15, floori(smp))
			return (skeleton[seg] as Vector3).lerp(skeleton[seg + 1], smp - seg)
		var frond := blend(GREEN, Color(0.21, 0.145, 0.062), dry)
		tube(mesh, skeleton, 0.008, 0.0008, blend(blend(STEM, GREEN, 0.45), Color(0.19, 0.115, 0.04), dry), 3 if low else (4 if medium else 5))
		var pairs: int = 15 + floori(rng.call() * 4)
		for p in pairs:
			var t := 0.14 + float(p) / (pairs - 1) * 0.82
			var env := pow(sin(PI * ((t - 0.05) / 0.95)), 0.84)
			var length: float = (0.22 + rng.call() * 0.055) * maxf(0.08, env) * (1.0 - t * 0.24)
			for sign: float in [-1.0, 1.0]:
				var at := clampf(t + (0.006 if sign == 1.0 else -0.006), 0.0, 1.0)
				var origin: Vector3 = curve.call(at)
				var dir: Vector3 = lateral * sign + radial * (0.26 + t * 0.31) + V(0, 0.14 - t * 0.28 + (rng.call() - 0.5) * 0.16, 0)
				var ll: float = length * (0.92 + rng.call() * 0.16)
				var lw: float = length * (0.22 + rng.call() * 0.065)
				var lc := tone(frond, 0.89 + rng.call() * 0.37)
				var opts := {"detail": "medium" if medium else "high", "dry": dry, "curl": 0.045 + rng.call() * 0.13,
					"twist": sign * (0.05 + rng.call() * 0.19), "ridge": 0.14}
				if dry > 0.25 and ((p * 7 + fi + (3 if sign > 0 else 0)) % 13) < 1 + floori(wear * 2.0):
					continue
				_fern_leaf(mesh, low, medium, origin, dir, ll, lw, lc, opts)
		_fern_leaf(mesh, low, medium, curve.call(0.95), radial + V(0, -0.3, 0), 0.075, 0.018, tone(frond, 1.05),
			{"detail": "medium" if medium else "high", "dry": dry, "curl": 0.2})
	var fiddleheads: int = 1 + floori(age.call() * 2)
	for y in fiddleheads:
		var angle: float = age.call() * TAU
		var h: float = 0.28 + age.call() * 0.25
		var radius: float = 0.025 + age.call() * 0.019
		var radial := V(cos(angle), 0, sin(angle))
		var stalk := func(t: float) -> Vector3: return radial * (0.035 + 0.032 * t * t) + V(0, h * t, 0)
		var top: Vector3 = stalk.call(1.0)
		tube(mesh, sample_curve(stalk, 4 if low else 7), 0.0032, 0.0026, Color(0.155, 0.153, 0.049), 3 if low else 4)
		var coil := func(t: float) -> Vector3:
			var a := t * TAU * 1.24
			var r := radius * (1.0 - t * 0.81)
			return top + radial * (radius - r * cos(a)) + V(0, r * sin(a), 0)
		tube(mesh, sample_curve(coil, 11 if low else (17 if medium else 25)), 0.0026, 0.0009, Color(0.168, 0.165, 0.056), 3 if low else 4)
	return mesh.finish()


static func _fern_leaf(mesh: MB, low: bool, medium: bool, base: Vector3, dir: Vector3, l: float, w: float, c: Color, o: Dictionary) -> void:
	if low:
		folded_leaf(mesh, base, dir, l, w, c, o)
	elif medium:
		fern_pinna(mesh, base, dir, l, w, c, o)
	else:
		bipinnate_pinna(mesh, base, dir, l, w, c, o)


static func shrub_leaf(mesh: MB, base: Vector3, direction: Vector3, length: float, width: float, color: Color, o := {}) -> void:
	var curl: float = o.get("curl", 0.1)
	var twist: float = o.get("twist", 0.0)
	var asym: float = o.get("asymmetry", 0.0)
	var age: float = o.get("age", 0.0)
	var damage: int = o.get("damage", -1)
	var phase: float = o.get("phase", 0.0)
	var f := _leaf_frame(direction)
	var axis: Vector3 = f[0]; var side: Vector3 = f[1]; var normal: Vector3 = f[2]
	if normal.y < 0.0:
		normal = -normal; side = -side
	var envelope := func(t: float) -> float: return pow(sin(PI * pow(t, 0.83 + sin(phase) * 0.075)), 0.7 + cos(phase) * 0.065)
	var at := func(t: float, across: float, tooth: float) -> Vector3:
		var shape: float = envelope.call(t)
		var sg := signf(across)
		var half := width * 0.5 * shape * (1.0 + sg * asym + 0.045 * sin(t * PI * 2.0 + phase + sg))
		var u := across * half * tooth
		var side_at := side.rotated(axis, twist * (t - 0.12))
		var up_at := normal.rotated(axis, twist * (t - 0.12))
		var camber := length * (curl * sin(t * PI) - (0.045 + age * 0.1) * pow(t, 4.0))
		var aa := absf(across)
		var fold := width * shape * (0.022 * (1.0 - aa) - 0.145 * aa - 0.022 * across * across + 0.064 * pow(aa, 8.0))
		return base + axis * (length * t) + side * (length * asym * 0.22 * sin(t * PI)) + side_at * u + normal * camber \
			+ up_at * (fold + width * 0.008 * sin(t * 19.0 + phase) * aa)
	var shade := func(t: float, across: float) -> Color:
		var mott := (0.5 + 0.5 * sin(t * 15.0 + across * 4.0 + phase)) * age
		var cc := blend(color, Color(0.17, 0.142, 0.048), mott * 0.36 + age * 0.28 * pow(absf(across), 3.0))
		return tone(cc, 1.0 + (1.0 - absf(across)) * 0.055 + sin(t * 11.0 + phase) * 0.019)
	var vtx := func(t: float, across: float, tooth := 1.0) -> int:
		return mesh.vertex(at.call(t, across, tooth), (across + 1.0) * 0.5, t, shade.call(t, across))
	var bi: int = vtx.call(0.0, 0.0)
	var ti: int = vtx.call(1.0, 0.0)
	var midrib := []
	for t: float in [0.0, 0.19, 0.41, 0.64, 0.83, 1.0]:
		midrib.append({"t": t, "i": bi if t == 0.0 else (ti if t == 1.0 else vtx.call(t, 0.0))})
	for sign: float in [-1.0, 1.0]:
		var inner := []
		for t: float in [0.0, 0.31, 0.68, 1.0]:
			inner.append({"t": t, "i": bi if t == 0.0 else (ti if t == 1.0 else vtx.call(t, sign * 0.79))})
		var edge := []
		for j in 19:
			var t := (j + (0.0 if j == 0 or j == 18 else 0.11 * sin(j * 2.13 + phase + sign))) / 18.0
			if j == 0 or j == 18:
				edge.append({"t": t, "i": bi if j == 0 else ti})
				continue
			var tooth := (1.029 if j % 2 else 0.964) + 0.012 * sin(j * 2.73 + phase + sign) - (0.085 if damage == j and sign < 0 else 0.0)
			edge.append({"t": t, "i": vtx.call(t, sign, tooth)})
		_strip(mesh, midrib, inner, sign)
		_strip(mesh, inner, edge, sign)


static func _strip(mesh: MB, a: Array, b: Array, sign: float) -> void:
	var i := 0
	var j := 0
	while i < a.size() - 1 or j < b.size() - 1:
		var x: int; var y: int; var z: int
		if j == b.size() - 1 or (i < a.size() - 1 and a[i + 1].t <= b[j + 1].t):
			x = a[i].i; y = a[i + 1].i; z = b[j].i
			i += 1
		else:
			x = a[i].i; y = b[j + 1].i; z = b[j].i
			j += 1
		if x == y or y == z or z == x:
			continue
		if sign > 0:
			mesh.tri(x, y, z)
		else:
			mesh.tri(x, z, y)


static func shrub(seed: int, low := false) -> ArrayMesh:
	if not low:
		return _detailed_shrub(seed)
	var rng := FM.random_source(str(seed))
	var mesh := MB.new()
	var stems: int = 5 + floori(rng.call() * 2)
	var height: float = 1.18 + rng.call() * 0.43
	var phase: float = rng.call() * TAU
	for s in stems:
		var angle: float = phase + s * TAU / stems + (rng.call() - 0.5) * 0.8
		var radial := V(cos(angle), 0, sin(angle))
		var lateral := V(-sin(angle), 0, cos(angle))
		var bend: float = 0.25 + rng.call() * 0.34
		var h: float = height * (0.67 + rng.call() * 0.33)
		var curve := func(t: float) -> Vector3: return radial * (0.055 + bend * t * t) + lateral * (sin(t * PI) * 0.07) + V(0, t * h, 0)
		tube(mesh, sample_curve(curve, 3), 0.014 + rng.call() * 0.006, 0.0022, BARK, 3)
		var branches: int = 5 + floori(rng.call() * 2)
		for b in branches:
			var t := 0.12 + float(b) / (branches - 1) * 0.79
			var start: Vector3 = curve.call(t)
			var sign := -1.0 if b % 2 else 1.0
			var reach: float = (0.29 + rng.call() * 0.2) * (1.09 - t * 0.33)
			var bdir: Vector3 = (lateral * (sign * (0.7 + rng.call() * 0.35)) + radial * (0.48 + rng.call() * 0.42)).normalized()
			var rise: float = 0.11 + rng.call() * 0.17
			var twig := func(u: float) -> Vector3: return start + bdir * (reach * u) + V(0, rise * u + sin(u * PI) * 0.045, 0)
			tube(mesh, sample_curve(twig, 2), 0.0052 * (1.0 - t * 0.42), 0.0008, tone(BARK, 1.14), 3)
			var leaf_count: int = 8 + floori(rng.call() * 2)
			for l in leaf_count:
				var u := 0.06 + float(l) / (leaf_count - 1) * 0.92
				var attach: Vector3 = twig.call(u)
				var ls := -1.0 if l % 2 else 1.0
				var cross := V(-bdir.z, 0, bdir.x)
				var ldir: Vector3 = (cross * (ls * (0.65 + rng.call() * 0.4)) + bdir * (0.42 + rng.call() * 0.35) + V(0, (rng.call() - 0.48) * 0.7, 0)).normalized()
				var len: float = (0.16 + rng.call() * 0.095) * (1.07 - u * 0.16)
				folded_leaf(mesh, attach, ldir, len + 0.014, len * (0.54 + rng.call() * 0.27), tone(GREEN, 0.82 + rng.call() * 0.56),
					{"sections": 4, "curl": 0.1 + rng.call() * 0.12, "twist": (rng.call() - 0.5) * 0.65, "serration": 0.035, "ridge": 0.1})
		for terminal in 2:
			var dir := radial + lateral * (0.55 if terminal else -0.55) + V(0, 0.4 + terminal * 0.15, 0)
			folded_leaf(mesh, curve.call(0.98 + terminal * 0.02), dir, 0.1 if terminal else 0.14, 0.065 if terminal else 0.09, tone(GREEN, 1.2),
				{"sections": 4, "curl": 0.17, "twist": 0.15, "ridge": 0.11})
	return mesh.finish()


static func _detailed_shrub(seed: int) -> ArrayMesh:
	var rng := FM.random_source(str(seed))
	var shape := FM.random_source("%d:broadleaf-shape" % seed)
	var mesh := MB.new()
	var stems: int = 5 + floori(rng.call() * 2)
	var height: float = 1.18 + rng.call() * 0.43
	var phase: float = rng.call() * TAU
	for s in stems:
		var angle: float = phase + s * TAU / stems + (rng.call() - 0.5) * 0.8
		var radial := V(cos(angle), 0, sin(angle))
		var lateral := V(-sin(angle), 0, cos(angle))
		var bend: float = 0.25 + rng.call() * 0.34
		var h: float = height * (0.67 + rng.call() * 0.33)
		var lean: float = 0.76 + shape.call() * 0.55
		var sway: float = (shape.call() - 0.5) * 0.18
		var droop: float = shape.call() * 0.075
		var stem := sample_curve(func(t: float) -> Vector3:
			return radial * (0.055 + bend * lean * t * t) + lateral * (sin(t * PI) * 0.07 + sway * t * t) + V(0, h * (t - droop * pow(t, 4.0)), 0), 8)
		tube(mesh, stem, 0.0115 + rng.call() * 0.005, 0.0016, tone(BARK, 0.92 + shape.call() * 0.19), 5)
		var branches: int = 5 + floori(rng.call() * 2)
		for b in branches:
			var t := 0.12 + float(b) / (branches - 1) * 0.79
			var start := _at(stem, 8, t)
			var sign := -1.0 if b % 2 else 1.0
			var reach: float = (0.29 + rng.call() * 0.2) * (1.09 - t * 0.33)
			var bdir: Vector3 = (lateral * (sign * (0.7 + rng.call() * 0.35)) + radial * (0.48 + rng.call() * 0.42)).normalized()
			var cross := V(-bdir.z, 0, bdir.x)
			var rise: float = 0.11 + rng.call() * 0.17
			var sweep: float = (shape.call() - 0.5) * 0.17
			var sag: float = 0.025 + shape.call() * 0.1
			var twig := sample_curve(func(u: float) -> Vector3:
				return start + bdir * (reach * u) + cross * (sweep * u * u) + V(0, rise * u + sin(u * PI) * 0.06 - sag * u * u, 0), 4)
			tube(mesh, twig, 0.0039 * (1.0 - t * 0.4), 0.00065, blend(BARK, STEM, 0.25 + t * 0.3), 4)
			var leaf_count: int = 8 + floori(rng.call() * 2)
			var retained := {}
			for j in 5:
				retained[roundi(j * (leaf_count - 1) / 4.0)] = true
			for l in leaf_count:
				var u: float = 0.09 + float(l) / (leaf_count - 1) * 0.87 + (shape.call() - 0.5) * 0.035
				var attach := _at(twig, 4, u)
				var ls := -1.0 if l % 2 else 1.0
				var ldir: Vector3 = (cross * (ls * (0.7 + rng.call() * 0.45)) + bdir * (0.28 + rng.call() * 0.47) + V(0, (rng.call() - 0.47) * 0.7, 0)).normalized()
				var size_d: float = rng.call(); var width_d: float = rng.call(); var color_d: float = rng.call()
				var curl_d: float = rng.call(); var twist_d: float = rng.call()
				if not retained.has(l):
					continue
				var maturity := pow(1.0 - u, 0.38)
				var len: float = (0.118 + size_d * 0.07) * (0.66 + maturity * 0.54) * (0.82 + shape.call() * 0.32)
				var pl: float = len * (0.105 + shape.call() * 0.06)
				var pend := attach + ldir * pl
				var pmid := attach.lerp(pend, 0.5) + V(0, pl * 0.12, 0)
				tube(mesh, [attach, pmid, pend], 0.0008, 0.00042, blend(STEM, GREEN, 0.25 + u * 0.32), 3, false)
				var age: float = (0.22 + shape.call() * 0.34) if (shape.call() < 0.12 and u < 0.76) else 0.0
				var col := tone(blend(GREEN, FRESH, 0.1 + (1.0 - maturity) * 0.24), 0.83 + color_d * 0.34)
				var asym: float = (shape.call() - 0.5) * 0.19
				var dmg: int = (3 + floori(shape.call() * 7)) if age > 0.3 else -1
				shrub_leaf(mesh, pend, ldir, len, len * (0.65 + width_d * 0.2), col,
					{"curl": 0.045 + curl_d * 0.1, "twist": (twist_d - 0.5) * 0.65, "asymmetry": asym, "age": age, "damage": dmg, "phase": shape.call() * TAU})
		for terminal in 2:
			var dir: Vector3 = (radial + lateral * (0.55 if terminal else -0.55) + V(0, 0.48 + terminal * 0.18, 0)).normalized()
			var root := _at(stem, 8, 0.975 + terminal * 0.025)
			var end := root + dir * 0.01
			tube(mesh, [root, end], 0.00075, 0.0004, STEM, 3, false)
			shrub_leaf(mesh, end, dir, 0.059 if terminal else 0.082, 0.035 if terminal else 0.056, blend(GREEN, FRESH, 0.4),
				{"curl": 0.13, "twist": -0.33 if terminal else 0.26, "asymmetry": 0.045, "phase": shape.call() * TAU})
	return mesh.finish()


static func _at(points: Array, segments: int, t: float) -> Vector3:
	var u := clampf(t, 0.0, 1.0) * segments
	var j := mini(segments - 1, floori(u))
	return (points[j] as Vector3).lerp(points[j + 1], u - j)


static func _sorrel_leaf(mesh: MB, base: Vector3, angle: float, size: float, lift: float, color: Color) -> void:
	var axis := V(cos(angle), lift, sin(angle)).normalized()
	var side := V(-sin(angle), 0, cos(angle))
	var outline := [[0, 0], [0.14, -0.23], [0.38, -0.45], [0.63, -0.53], [0.83, -0.48], [0.96, -0.3], [0.95, -0.14], [0.78, 0],
		[0.95, 0.14], [0.96, 0.3], [0.83, 0.48], [0.63, 0.53], [0.38, 0.45], [0.14, 0.23]]
	var point := func(x: float, z: float) -> Vector3: return base + axis * (x * size) + side * (z * size) + V(0, size * (0.09 * sin(x * PI) - 0.18 * absf(z)), 0)
	var center := mesh.vertex(point.call(0.48, 0.0), 0.5, 0.48, tone(color, 1.045))
	var edge := []
	for o in outline:
		edge.append(mesh.vertex(point.call(o[0], o[1]), 0.5 + o[1] / 1.06, o[0], color))
	for i in edge.size():
		mesh.tri(center, edge[(i + 1) % edge.size()], edge[i])


static func _flower(mesh: MB, center: Vector3, radius: float, rng: Callable, petals := 5, sections := 3) -> void:
	var phase: float = rng.call() * TAU
	for p in petals:
		var angle := phase + p * TAU / petals
		var dir := V(cos(angle), 0.16, sin(angle))
		lance_leaf(mesh, center + dir * (radius * 0.12), dir, radius, radius * 0.66, Color(0.7, 0.72, 0.64), {"sections": sections, "curl": 0.05, "ridge": 0.02})
	var c := mesh.vertex(center + V(0, radius * 0.18, 0), 0.5, 0.5, Color(0.49, 0.32, 0.035))
	var ring := []
	for p in 8:
		var a := p * TAU / 8.0
		ring.append(mesh.vertex(center + V(cos(a) * radius * 0.25, radius * 0.04, sin(a) * radius * 0.25), cos(a) * 0.5 + 0.5, sin(a) * 0.5 + 0.5, Color(0.52, 0.38, 0.043)))
	for p in 8:
		mesh.tri(c, ring[(p + 1) % 8], ring[p])


static func _ivy_leaf(mesh: MB, base: Vector3, angle: float, size: float, lift: float, color: Color) -> void:
	var axis := V(cos(angle), lift, sin(angle)).normalized()
	var side := V(-sin(angle), 0, cos(angle))
	var outline := [[0, 0], [0, -0.22], [0.18, -0.38], [0.27, -0.2], [0.5, -0.5], [0.55, -0.18], [1, 0], [0.55, 0.18], [0.5, 0.5], [0.27, 0.2], [0.18, 0.38], [0, 0.22]]
	var point := func(x: float, z: float, raised := 0.0) -> Vector3: return base + axis * (x * size) + side * (z * size) + V(0, size * (0.045 * sin(x * PI) - 0.12 * absf(z)) + raised, 0)
	var center := mesh.vertex(point.call(0.3, 0.0), 0.5, 0.3, tone(color, 1.04))
	var ring := []
	for o in outline:
		ring.append(mesh.vertex(point.call(o[0], o[1]), o[1] + 0.5, o[0], color))
	for i in ring.size():
		mesh.tri(center, ring[(i + 1) % ring.size()], ring[i])
	for e in [[0.02, 0], [0.18, -0.38], [0.5, -0.5], [1, 0], [0.5, 0.5], [0.18, 0.38]]:
		var dx: float = e[0] - 0.3
		var dz: float = e[1]
		var mag := sqrt(dx * dx + dz * dz)
		var w := 0.0034
		var px := -dz / mag * w
		var pz := dx / mag * w
		var vc := blend(color, Color(0.12, 0.19, 0.09), 0.56)
		var a := mesh.vertex(point.call(0.3 - px, -pz, 0.00025), 0, 0, vc)
		var b := mesh.vertex(point.call(0.3 + px, pz, 0.00025), 1, 0, vc)
		var c := mesh.vertex(point.call(e[0] - px * 0.3, e[1] - pz * 0.3, 0.00025), 0, 1, vc)
		var d := mesh.vertex(point.call(e[0] + px * 0.3, e[1] + pz * 0.3, 0.00025), 1, 1, vc)
		mesh.tri(a, b, c)
		mesh.tri(b, d, c)


static func herb(seed: int, type: String) -> ArrayMesh:
	var rng := FM.random_source(str(seed))
	var mesh := MB.new()
	if type == "ivy":
		var runners: int = 3 + floori(rng.call() * 2)
		var phase: float = rng.call() * TAU
		for r in runners:
			var angle: float = phase + r * TAU / runners + rng.call() * 0.3
			var axis := V(cos(angle), 0, sin(angle))
			var side := V(-sin(angle), 0, cos(angle))
			var reach: float = 0.26 + rng.call() * 0.24
			var runner := func(t: float) -> Vector3: return axis * (reach * t) + side * (sin(t * PI * 1.35) * 0.035) + V(0, 0.014 + sin(t * PI) * 0.013, 0)
			tube(mesh, sample_curve(runner, 6), 0.0028, 0.0011, Color(0.08, 0.096, 0.039), 3)
			var count: int = 5 + floori(rng.call() * 3)
			for l in count:
				var t := 0.06 + float(l) / (count - 1) * 0.91
				var la: float = angle + (-1.0 if l % 2 else 1.0) * (0.69 + rng.call() * 0.25)
				var base: Vector3 = runner.call(t)
				var pet := V(cos(la) * 0.024, 0.045 + rng.call() * 0.025, sin(la) * 0.024)
				tube(mesh, [base, base + pet], 0.00125, 0.0008, STEM, 3)
				_ivy_leaf(mesh, base + pet, la, 0.078 + rng.call() * 0.065, (rng.call() - 0.5) * 0.2, tone(Color(0.033, 0.078, 0.035), 0.85 + rng.call() * 0.4))
		return mesh.finish()
	if type == "nettle":
		var stems: int = 3 + floori(rng.call() * 3)
		var phase: float = rng.call() * TAU
		for s in stems:
			var angle := phase + s * 2.3999632297
			var height: float = 0.26 + rng.call() * 0.29
			var axis := V(cos(angle), 0, sin(angle))
			var root: Vector3 = axis * (0.018 + rng.call() * 0.115)
			var stalk := func(t: float) -> Vector3: return root + axis * (height * 0.17 * t * t) + V(0, height * t, 0)
			tube(mesh, sample_curve(stalk, 4), 0.003, 0.0009, Color(0.071, 0.104, 0.031), 4)
			for node in 4:
				var t := 0.25 + node * 0.235
				for sign: float in [-1.0, 1.0]:
					var a := angle + node * PI * 0.5
					var dir := V(cos(a) * sign, 0.18 + node * 0.09, sin(a) * sign)
					var length: float = (0.108 + rng.call() * 0.047) * (1.0 - node * 0.12)
					lance_leaf(mesh, stalk.call(t), dir, length, length * (0.53 + rng.call() * 0.1), tone(Color(0.05, 0.129, 0.036), 0.93 + rng.call() * 0.29),
						{"sections": 11, "curl": 0.09, "twist": sign * 0.1, "ridge": 0.18, "serration": 0.13})
		return mesh.finish()
	if type == "ramsons":
		var plants: int = 4 + floori(rng.call() * 3)
		var phase: float = rng.call() * TAU
		for p in plants:
			var angle := phase + p * 2.3999632297
			var radius: float = 0.025 + rng.call() * 0.12
			var root := V(cos(angle) * radius, 0, sin(angle) * radius)
			for side: float in [-1.0, 1.0]:
				var a := angle + side * 0.4
				var length: float = 0.19 + rng.call() * 0.14
				var dir := V(cos(a) * 0.64, 0.72 + rng.call() * 0.24, sin(a) * 0.64)
				var base := root + V(0, 0.025, 0)
				tube(mesh, [root, base], 0.0018, 0.0011, STEM, 3)
				lance_leaf(mesh, base, dir, length, length * (0.23 + rng.call() * 0.08), tone(Color(0.046, 0.113, 0.04), 0.87 + rng.call() * 0.38),
					{"sections": 8, "curl": 0.085, "twist": side * 0.15, "ridge": 0.12})
			if p < 2:
				var height: float = 0.25 + rng.call() * 0.1
				var top := root + V(cos(angle) * 0.025, height, sin(angle) * 0.025)
				tube(mesh, sample_curve(func(t: float) -> Vector3: return root.lerp(top, t), 4), 0.0018, 0.0009, STEM, 4)
				var count: int = 5 + floori(rng.call() * 3)
				for fl in count:
					var a := angle + fl * TAU / count
					var tip := top + V(cos(a) * 0.025, 0.014 + rng.call() * 0.021, sin(a) * 0.025)
					tube(mesh, [top, tip], 0.00075, 0.0005, tone(STEM, 1.2), 3, false)
					_flower(mesh, tip, 0.009 + rng.call() * 0.0045, rng, 6, 2)
		return mesh.finish()
	var flowering := type == "flower"
	var count: int = (4 + floori(rng.call() * 3)) if flowering else (6 + floori(rng.call() * 3))
	var phase: float = rng.call() * TAU
	for i in count:
		var angle: float = phase + i * TAU / count + (rng.call() - 0.5) * 0.45
		var radius: float = 0.025 + rng.call() * (0.12 if flowering else 0.11)
		var root := V(cos(angle) * radius, 0, sin(angle) * radius)
		var height: float = (0.19 + rng.call() * 0.2) if flowering else (0.055 + rng.call() * 0.085)
		var offset := V(cos(angle) * height * 0.28, height, sin(angle) * height * 0.28)
		var curve := func(t: float) -> Vector3: return root + offset * t + V(sin(angle + 0.8) * sin(t * PI) * 0.016, 0, cos(angle + 0.8) * sin(t * PI) * 0.016)
		tube(mesh, sample_curve(curve, 4), 0.0018 if flowering else 0.0014, 0.0007, STEM, 4)
		if flowering:
			for j in 2:
				for sign: float in [-1.0, 1.0]:
					var dir := V(cos(angle + j * 1.3) * sign, 0.26, sin(angle + j * 1.3) * sign)
					lance_leaf(mesh, curve.call(0.24 + j * 0.31), dir, 0.05 + rng.call() * 0.035, 0.019, tone(GREEN, 0.95 + rng.call() * 0.25), {"sections": 3, "curl": 0.1, "twist": sign * 0.13})
			_flower(mesh, curve.call(1.0), 0.018 + rng.call() * 0.012, rng)
		else:
			var top: Vector3 = curve.call(1.0)
			var size: float = 0.043 + rng.call() * 0.031
			for l in 3:
				_sorrel_leaf(mesh, top, angle + l * TAU / 3.0, size * (0.94 + rng.call() * 0.12), (rng.call() - 0.5) * 0.22, tone(GREEN, 1.0 + rng.call() * 0.38))
	return mesh.finish()


## understory.js createGrassGeometry: 20-28 curved, twisting blades from one clump (folded with a midrib up close).
static func grass(seed: int, detail := "high") -> ArrayMesh:
	var rng := FM.random_source(str(seed))
	var mesh := MB.new()
	var blades: int = 20 + floori(rng.call() * 9)
	var phase: float = rng.call() * TAU
	for b in blades:
		var angle: float = phase + b * 2.3999632297 + (rng.call() - 0.5) * 0.6
		var axis := V(cos(angle), 0, sin(angle))
		var side := V(-sin(angle), 0, cos(angle))
		var root: Vector3 = axis * (rng.call() * 0.06)
		var upright := b % 3 == 0
		var height: float = 0.25 + rng.call() * 0.45
		var width: float = 0.004 + pow(rng.call(), 2.0) * (0.014 if upright else 0.02)
		var lean: float = (0.12 + rng.call() * 0.22) if upright else (0.5 + rng.call() * 0.48)
		var twist: float = (rng.call() - 0.5) * 0.9
		var shade: float = 0.84 + rng.call() * 0.23
		var segments := 1 if detail == "low" else (2 if detail == "medium" else 8)
		var folded := detail == "high"
		var rows := []
		for j in segments + 1:
			var t := float(j) / segments
			var vertical := ((t - 0.05 * t * t * t) / 0.95) if upright else sin(t * PI * 0.66)
			var center := root + axis * (height * lean * t * t) + V(0, height * vertical, 0)
			var w := width * pow(1.0 - t, 0.65) * 0.5 * (1.17 if detail == "low" else 1.0)
			var color := tone(blend(Color(0.038, 0.068, 0.025), Color(0.135, 0.194, 0.064), t * 0.88), shade)
			if j == segments:
				rows.append([mesh.vertex(center, 0.5, t, color)])
				continue
			var dy := ((1.0 - 0.15 * t * t) / 0.95) if upright else PI * 0.66 * cos(t * PI * 0.66)
			var tg := (axis * (2.0 * lean * t) + V(0, dy, 0)).normalized()
			var cross := side.rotated(tg, twist * t)
			var ln := tg.cross(cross).normalized()
			var row := []
			for s: float in ([-1.0, 0.0, 1.0] if folded else [-1.0, 1.0]):
				row.append(mesh.vertex(center + cross * (s * w) + ln * (w * 0.25 if folded and s == 0.0 else 0.0), (s + 1.0) * 0.5, t,
					tone(color, 0.97 if s < 0 else (1.055 if s == 0.0 else 1.03))))
			rows.append(row)
		var nk := 2 if folded else 1
		for j in segments - 1:
			for k in nk:
				mesh.tri(rows[j][k], rows[j][k + 1], rows[j + 1][k])
				mesh.tri(rows[j][k + 1], rows[j + 1][k + 1], rows[j + 1][k])
		for k in nk:
			mesh.tri(rows[segments - 1][k], rows[segments - 1][k + 1], rows[segments][0])
	return mesh.finish()
