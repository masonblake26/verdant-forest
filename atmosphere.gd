extends Node3D
## Port of atmosphere.ts addParticles() and volumetrics.ts: the floating motes, the light shafts (a world-wide fog
## volume with the original's noise mist, marched by Godot's volumetric fog against the sun's shadow), and the
## composite's haze-to-sky, grade and vignette (shaders/grade.gdshader). The sky itself lives in forest.gd.

const FM := preload("res://forest_math.gd")
const VOLUME_STRENGTH := 0.48
const VOLUME_DISTANCE := 132.0
const HAZE_START := 220.0
const HAZE_END := 435.0

var motes: ShaderMaterial


func _ready() -> void:
	var forest: Node = get_parent()
	_build_motes()
	_build_shafts(forest.env, forest.sun)
	_build_grade()


func _build_motes() -> void:
	var n := 600
	var r := FM.rng(218)
	var verts := PackedVector3Array()
	var seeds := PackedColorArray()
	verts.resize(n)
	seeds.resize(n)
	for i in n:
		var x: float = (r.call() - 0.5) * 110.0
		var y: float = 0.5 + r.call() * 16.0
		var z: float = (r.call() - 0.5) * 110.0
		verts[i] = Vector3(x, y, z)
		seeds[i] = Color(r.call(), 0.0, 0.0)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = seeds
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arr)
	motes = ShaderMaterial.new()
	motes.shader = load("res://shaders/particles.gdshader")
	var mi := MeshInstance3D.new()
	mi.name = "Motes"
	mi.mesh = mesh
	mi.material_override = motes
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-1e5, -1e3, -1e5), Vector3(2e5, 2e3, 2e5))   # wraps around the eye in the shader
	add_child(mi)


func _build_shafts(env: Environment, sun: DirectionalLight3D) -> void:
	env.fog_enabled = false                   # FogExp2 is in the grade pass
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0          # all the mist comes from the volume below
	env.volumetric_fog_length = VOLUME_DISTANCE
	env.volumetric_fog_anisotropy = _arg("aniso", 0.35)
	env.volumetric_fog_ambient_inject = _arg("fogamb", 0.0)
	env.volumetric_fog_sky_affect = 0.0
	env.volumetric_fog_detail_spread = 1.5
	sun.light_volumetric_fog_energy = _arg("fogsun", 0.5)
	var sh := ShaderMaterial.new()
	sh.shader = load("res://shaders/shafts.gdshader")
	sh.set_shader_parameter("strength", VOLUME_STRENGTH * _arg("mist", 1.0))
	sh.set_shader_parameter("shade_gain", _arg("shade", 3.0))
	var fv := FogVolume.new()
	fv.name = "Shafts"
	fv.shape = RenderingServer.FOG_VOLUME_SHAPE_WORLD
	fv.material = sh
	add_child(fv)


func _build_grade() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/grade.gdshader")
	mat.render_priority = -128
	mat.set_shader_parameter("top", FM.SKY_TOP)
	mat.set_shader_parameter("bottom", FM.SKY_BOTTOM)
	mat.set_shader_parameter("sun_dir", FM.SUN_DIRECTION.normalized())
	mat.set_shader_parameter("haze_start", HAZE_START)
	mat.set_shader_parameter("haze_end", HAZE_END)
	mat.set_shader_parameter("saturation", FM.SATURATION)
	mat.set_shader_parameter("fog_color", FM.FOG_COLOR)
	mat.set_shader_parameter("fog_density", FM.FOG_DENSITY)
	var mi := MeshInstance3D.new()
	mi.name = "Grade"
	mi.mesh = quad
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 16384.0
	add_child(mi)


func _process(_delta: float) -> void:
	# three.js sized the motes in framebuffer pixels at the reference 720p capture.
	motes.set_shader_parameter("px_scale", get_viewport().get_visible_rect().size.y / 720.0)


func _arg(k: String, d: float) -> float:
	var a: Dictionary = get_parent().args
	return float(a[k]) if a.has(k) else d
