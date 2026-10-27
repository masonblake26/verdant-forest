extends RefCounted
## Port of bracket-fungus.js: a seeded cluster of two or three closed shelf fungi. The bark attachment is the local
## origin, +Z points out of the bark and +Y up. Each shelf has a ribbed, dished top, a cream underside with recessed
## pore pits and a pale rounded rim; three habits (ochre fan pair, layered cream shelves, russet asymmetric pair).

const FM := preload("res://forest_math.gd")
const FL := preload("res://flowers.gd")


## bracket-fungus.js seeded(): FNV-1a of String(seed) with its own counter stream (JavaScript number semantics).
static func _stream(seed: int) -> Callable:
	var st := [FM.hash_seed(str(seed))]
	return func() -> float:
		st[0] += 0x6D2B79F5          # a JavaScript number: grows past 32 bits, read through ToInt32/ToUint32
		var h: int = st[0]
		var n := FM.i32(FM.imul(FM.i32(h) ^ FM.i32((h & FM.MASK) >> 15), FM.i32(1 | FM.i32(h))))
		n = FM.i32(n ^ FM.i32(n + FM.i32(FM.imul(n ^ FM.i32((n & FM.MASK) >> 7), FM.i32(61 | n)))))
		return float((n ^ ((n & FM.MASK) >> 14)) & FM.MASK) / 4294967296.0


static func _mix(a: Color, b: Color, t: float) -> Color:
	return Color(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t)


static func _tone(a: Color, t: float) -> Color:
	return Color(a.r * t, a.g * t, a.b * t)


static func geometry(seed: int) -> ArrayMesh:
	var rng := _stream(seed)
	var habit := posmod(seed, 3)
	var b := FL.B.new()
	var ochre: Color = [Color(0.171, 0.082, 0.026), Color(0.207, 0.122, 0.043), Color(0.133, 0.071, 0.035)][habit]
	var band: Color = [Color(0.305, 0.194, 0.082), Color(0.348, 0.247, 0.116), Color(0.270, 0.185, 0.104)][habit]
	var cream := Color(0.510, 0.432, 0.294)
	var pores := Color(0.285, 0.245, 0.170)
	var cap_count := 3 if habit == 1 else 2
	var widths := [0.153 + rng.call() * 0.027, 0.080 + rng.call() * 0.027, 0.065 + rng.call() * 0.014]
	var roots := [Vector3.ZERO, Vector3(-0.024 if habit == 2 else 0.022, 0.033 + rng.call() * 0.010, 0.0),
		Vector3(-0.025, -0.026 - rng.call() * 0.008, 0.0)]
	const R := 7
	const A := 24
	for cap in cap_count:
		var width: float = widths[cap]
		var reach: float = width * (0.51 + rng.call() * 0.105)
		var root: Vector3 = roots[cap]
		var phase: float = rng.call() * TAU
		var tilt: float = (rng.call() - 0.5) * 0.10
		var skew := (0.15 if habit == 2 else 0.025) * (-1.0 if cap % 2 else 1.0)
		var thickness: float = (0.0042 + rng.call() * 0.0016) if cap == 0 else (0.0030 + rng.call() * 0.0009)
		var arch: float = width * (0.044 + rng.call() * 0.016)
		var radial_shade := func(r: float, a: float) -> Color:
			var growth := 0.5 + sin(r * 30.0 + sin(a * 3.0 + phase) * 0.24 + phase) * 0.5
			var color := _mix(ochre, band, 0.14 + growth * 0.58)
			var wear := (0.5 + 0.5 * sin(a * 4.7 + phase)) * 0.12
			color = _mix(color, cream, clampf((r - 0.89) / 0.11, 0.0, 1.0) * (0.73 + wear))
			return _tone(color, 0.94 + sin(a * 8.3 + phase) * 0.037)
		var rings := [[], []]
		for side in 2:
			rings[side].append([b.vertex(root + Vector3(0.0, (-0.5 if side else 0.5) * thickness, 0.0),
				cream if side else radial_shade.call(0.0, 0.0), 0.5, 0.0)])
			for j in range(1, R + 1):
				var r := float(j) / R
				var ring := []
				for k in A + 1:
					var a := (float(k) / A - 0.5) * PI
					var forward := maxf(0.0, cos(a))
					var ripples := 1.0 + r * (sin(a * 7.1 + phase) * 0.026 + sin(a * 13.3 - phase) * 0.014)
					var x: float = width * 0.81 * sin(a) * (0.4 + 0.6 * forward) * r * ripples + reach * skew * r * pow(forward, 0.8)
					var z: float = reach * pow(forward, 0.88) * r * ripples
					var rib := sin(a * 13.0 + r * 2.4 + phase) * width * 0.0045 * pow(r, 0.55) * (1.0 - r * 0.30)
					var dish: float = arch * sin(r * PI * 0.94) * (0.72 + forward * 0.28)
					var edge_wave := pow(r, 4.0) * width * (0.0075 * sin(a * 5.0 + phase) + 0.0035 * sin(a * 11.7 + phase))
					var half := thickness * (0.50 - r * 0.35)
					var y: float = root.y + dish + edge_wave + tilt * x + ((-half - rib * 0.15) if side else (half + rib))
					var col: Color = _tone(cream, 0.94 + 0.025 * sin(a * 8.0 + r * 17.0)) if side else radial_shade.call(r, a)
					ring.append(b.vertex(Vector3(root.x + x, y, z), col, 0.5 + x / width, z / reach))
				rings[side].append(ring)
		# An underside triangle becomes an inset triangular pit with a recessed centre (no floating pore decals).
		var bottom_face := func(a: int, bb: int, c: int, pore: bool) -> void:
			if not pore:
				b.tri(a, bb, c)
				return
			var outer := [a, bb, c]
			var center := (b.p[a] + b.p[bb] + b.p[c]) / 3.0
			var max_radius := width * 0.006
			var ring := []
			for q in outer:
				var qp: Vector3 = b.p[q]
				var t := minf(0.24, max_radius / Vector2(qp.x - center.x, qp.z - center.z).length())
				ring.append(b.vertex(center + (qp - center) * t, _tone(cream, 0.94)))
			var pit := b.vertex(center + Vector3(0.0, width * 0.0022, 0.0), pores)
			for k in 3:
				var n := (k + 1) % 3
				b.tri(outer[k], outer[n], ring[k]); b.tri(outer[n], ring[n], ring[k])
				b.tri(ring[k], ring[n], pit)
		for side in 2:
			var row: Array = rings[side]
			for k in A:
				if side:
					b.tri(row[0][0], row[1][k + 1], row[1][k])
				else:
					b.tri(row[0][0], row[1][k], row[1][k + 1])
			for j in range(1, R):
				for k in A:
					var a: int = row[j][k]; var bb: int = row[j + 1][k]; var c: int = row[j][k + 1]; var d: int = row[j + 1][k + 1]
					if side:
						bottom_face.call(a, c, bb, j >= 2 and j <= 5 and k % 3 == (j + cap) % 3)
						bottom_face.call(c, d, bb, false)
					else:
						b.tri(a, bb, c); b.tri(c, bb, d)
		for k in A:
			var a: int = rings[0][R][k]; var bb: int = rings[0][R][k + 1]; var c: int = rings[1][R][k]; var d: int = rings[1][R][k + 1]
			b.tri(a, c, bb); b.tri(bb, c, d)
		# The back closes against the bark plane; the primary back face includes the attachment anchor (origin).
		var anchor := b.vertex(root, _mix(ochre, cream, 0.22))
		for edge in [0, A]:
			for j in R:
				var a: int = rings[0][j][0 if j == 0 else edge]; var bb: int = rings[0][j + 1][edge]
				var c: int = rings[1][j][0 if j == 0 else edge]; var d: int = rings[1][j + 1][edge]
				var face := func(x: int, y: int, z: int) -> void:
					if edge == 0:
						b.tri(x, z, y)
					else:
						b.tri(x, y, z)
				if j == 0:
					face.call(a, bb, anchor); face.call(anchor, bb, c)
				else:
					face.call(a, bb, c)
				face.call(bb, d, c)
	return b.finish()
