extends RefCounted
## Port of app/forest/math.ts and config.ts: the seeded generators, value noise, fbm, the terrain height field and
## the animal trail, with JavaScript's 32-bit integer maths (Math.imul, >>>) reproduced exactly so every placement
## matches the original scene.

const TAU := PI * 2.0

## Worker threads (tree variants, understory plants) build their meshes under this lock: without a threaded renderer
## the RenderingServer writes mesh storage directly, and concurrent add_surface_from_arrays crashed ~1 start-up in 8.
static var mesh_lock := Mutex.new()
const MASK := 0xFFFFFFFF

# config.ts
const SUN_COLOR := Color("#fff0cf")
const SUN_INTENSITY := 4.9
const SKY_COLOR := Color("#bed9e8")
const GROUND_COLOR := Color("#53603d")
const HEMI_INTENSITY := 1.9
const SKY_TOP := Color("#779fab")
const SKY_BOTTOM := Color("#a5c1c9")
const FOG_COLOR := Color("#91aca9")
const FOG_DENSITY := 0.0023
const EXPOSURE := 1.13
const SUN_DIRECTION := Vector3(-52.0, 58.0, -63.0)
const SATURATION := 1.085
const EXPLORATION := 95.0
const VEGETATION := 540.0
const TERRAIN := 1100.0
const CAMERA_FAR := 460.0
const TREE_FAR := 450.0
const HORIZON_LOD := 150.0


## 32-bit Math.imul.
static func imul(a: int, b: int) -> int:
	a &= MASK
	b &= MASK
	var lo := (a & 0xFFFF) * b
	var hi := ((a >> 16) * b) & 0xFFFF
	return (lo + (hi << 16)) & MASK


## Signed view of a 32-bit value (JavaScript's `| 0`).
static func i32(a: int) -> int:
	a &= MASK
	return a - 0x100000000 if a >= 0x80000000 else a


## math.ts rng(seed): mulberry32-style stream. Returns a Callable producing floats in [0, 1).
static func rng(seed: int) -> Callable:
	var st := [seed & MASK]
	return func() -> float:
		var s: int = (st[0] + 0x6D2B79F5) & MASK
		st[0] = s
		var t := imul(s ^ (s >> 15), 1 | s)
		t = ((t + imul(t ^ (t >> 7), 61 | t)) & MASK) ^ t
		return float((t ^ (t >> 14)) & MASK) / 4294967296.0


## FNV-1a of a string, as trees.js hashSeed / understory randomFor.
static func hash_seed(value: String) -> int:
	var h := 2166136261
	for ch in value.to_utf8_buffer():
		h = imul(h ^ ch, 16777619)
	return h & MASK


## trees.js randomSource(seed) and understory/botanical randomFor(seed): same stream, string-seeded.
static func random_source(seed: String) -> Callable:
	var st := [hash_seed(seed)]
	return func() -> float:
		var s: int = (st[0] + 0x6D2B79F5) & MASK
		st[0] = s
		var n := imul(s ^ (s >> 15), s | 1)
		n = n ^ ((n + imul(n ^ (n >> 7), n | 61)) & MASK)
		return float((n ^ (n >> 14)) & MASK) / 4294967296.0


static func _hash(x: int, z: int) -> float:
	var h := (imul(x, 374761393) + imul(z, 668265263)) & MASK
	h = imul(h ^ (h >> 13), 1274126177)
	return float((h ^ (h >> 16)) & MASK) / 4294967295.0


static func noise(x: float, z: float) -> float:
	var ix := floori(x)
	var iz := floori(z)
	var a := x - ix
	var b := z - iz
	var u := a * a * (3.0 - 2.0 * a)
	var v := b * b * (3.0 - 2.0 * b)
	return (_hash(ix, iz) * (1.0 - u) + _hash(ix + 1, iz) * u) * (1.0 - v) \
		+ (_hash(ix, iz + 1) * (1.0 - u) + _hash(ix + 1, iz + 1) * u) * v


static func fbm(x: float, z: float) -> float:
	return noise(x, z) * 0.53 + noise(x * 2.03 + 12.0, z * 2.03 + 5.0) * 0.27 + noise(x * 4.09, z * 4.09) * 0.13 \
		+ noise(x * 8.21, z * 8.21) * 0.07


## The terrain surface (the original interpolates a cached 0.96 m grid of this; the difference is sub-millimetre).
static func height_at(x: float, z: float) -> float:
	return (fbm(x * 0.045 + 14.0, z * 0.045 - 2.0) - 0.5) * 5.4 + sin(x * 0.037 + z * 0.013) * 1.5 + sin(z * 0.043) * 0.8 \
		+ (noise(x * 0.39, z * 0.39) - 0.5) * 0.12


static func trail_at(z: float) -> float:
	return sin(z * 0.09) * 3.6 + sin(z * 0.027) * 4.0


static func trail_distance(x: float, z: float) -> float:
	return absf(x - trail_at(z))
