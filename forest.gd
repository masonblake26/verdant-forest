extends Node3D
## Verdant Forest, a Godot 4.7 port of the procedural three.js woodland (app/forest in the original). This scene
## owns the sky, sun, fog, terrain and the camera; the vegetation and detail modules add themselves under it.
## Game-style camera: the mouse is captured and looks around, the movement keys move relative to the view, the wheel
## glides along it, Esc frees the mouse. Keys and toggles live in the settings panel (settings_ui.gd).
## Command-line options go after `--`; README.md lists them.

const FM := preload("res://forest_math.gd")
const UI := preload("res://settings_ui.gd")

const VIEWPOINTS := {
	"entrance": [Vector3(5.55, 1.72, 20.0), Vector3(2.5, 2.2, 3.0)],
	"ferns": [Vector3(-5.5, 1.3, 6.0), Vector3(-4.0, 1.0, 0.0)],
	"grove": [Vector3(12.0, 2.6, -12.0), Vector3(-5.0, 5.0, -31.0)],
	"deadwood": [Vector3(9.2, 1.7, -9.3), Vector3(5.7, 0.6, -7.3)],
	"canopy": [Vector3(-2.0, 5.0, 9.0), Vector3(-8.0, 18.0, -4.0)],
	"ridge": [Vector3(-25.0, 4.0, -18.0), Vector3(2.0, 5.0, -7.0)],
	"reverse": [Vector3(-2.0, 2.0, -14.0), Vector3(1.0, 3.0, 20.0)],
	"aerial": [Vector3(-15.0, 24.0, 25.0), Vector3(0.0, 13.0, -8.0)],
}

var args := {}
var cam: Camera3D
var env: Environment
var sun: DirectionalLight3D
var ui: CanvasLayer
var border: MeshInstance3D
var sharpen: CanvasLayer
var yaw := 0.0
var pitch := 0.0
var tyaw := 0.0
var tpitch := 0.0
var velocity := Vector3.ZERO
var time := 0.0
var frames := 0
var bench_t0 := 0
var fps_acc := 0.0
var fps_n := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else ""
	_place_window()
	_build_environment()
	_build_terrain()
	cam = Camera3D.new()
	cam.fov = _arg("fov", 58.0)
	cam.near = 0.06
	cam.far = FM.CAMERA_FAR
	add_child(cam)
	jump(args.get("view", "entrance"))
	for mod in ["res://surfaces.gd", "res://vegetation.gd", "res://understory.gd", "res://flowers.gd", "res://details.gd", "res://floor_detail.gd", "res://atmosphere.gd"]:
		if ResourceLoader.exists(mod):
			var node: Node = load(mod).new()
			node.name = mod.get_file().get_basename().capitalize().replace(" ", "")
			add_child(node)
	_build_border()
	_build_sharpen()
	if not _scripted() or args.has("ui"):        # --ui shows the panel in test shots
		ui = UI.new()
		ui.forest = self
		add_child(ui)
	if not _scripted():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## The window is created tiny, borderless, unfocusable and minimised (project.godot), because Godot pulls a window
## created off every screen back onto the main one. Shots and benches keep it unfocusable and park it far off-screen
## (moving it from script isn't clamped), so a test run never shows up or takes focus; a normal launch takes focus back
## and opens windowed (or fullscreen if that was saved in the settings panel).
func _place_window() -> void:
	var w := get_window()
	if _scripted():
		w.mode = Window.MODE_WINDOWED
		w.size = Vector2i(int(args.get("w", "1600")), int(args.get("h", "900")))
		w.position = Vector2i(-40000, -40000)
		print("window: %s at %s, screens %s" % [w.size, DisplayServer.window_get_position(), DisplayServer.get_screen_count()])
		return
	w.set_flag(Window.FLAG_NO_FOCUS, false)
	_set_fullscreen(bool(UI.load_cfg().get_value("settings", "fullscreen", false)) and not args.has("w"))
	w.grab_focus()


## Windowed: centred, 80% of the screen (or --w x --h); fullscreen: borderless over the whole screen.
func _set_fullscreen(on: bool) -> void:
	var w := get_window()
	if on:
		w.mode = Window.MODE_FULLSCREEN
		return
	w.mode = Window.MODE_WINDOWED
	w.set_flag(Window.FLAG_BORDERLESS, false)
	var usable := DisplayServer.screen_get_usable_rect(w.current_screen)
	w.size = Vector2i(int(args.w), int(args.h)) if args.has("w") and args.has("h") else Vector2i(Vector2(usable.size) * 0.8)
	w.position = usable.position + (usable.size - w.size) / 2


## What the settings panel's toggles do (stats and the panel itself are the panel's own business).
func apply_setting(id: String, on: bool) -> void:
	match id:
		"fullscreen":
			if not _scripted() and (get_window().mode == Window.MODE_FULLSCREEN) != on:
				_set_fullscreen(on)
		"msaa":   # TAA + sharpening by default (steady grass, detail put back); MSAA is crisper but the grass crawls
			get_viewport().use_taa = not on
			get_viewport().msaa_3d = Viewport.MSAA_4X if on else Viewport.MSAA_DISABLED
			sharpen.visible = not on
		"border":
			border.visible = on or args.has("border")


func action(id: String) -> void:
	if id == "home":
		jump("entrance")


func _scripted() -> bool:
	return args.has("shot") or args.has("bench")


func _build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/sky.gdshader")
	sm.set_shader_parameter("top", FM.SKY_TOP)
	sm.set_shader_parameter("bottom", FM.SKY_BOTTOM)
	sm.set_shader_parameter("hemi_sky", FM.SKY_COLOR)
	sm.set_shader_parameter("hemi_ground", FM.GROUND_COLOR)
	sm.set_shader_parameter("sun_dir", FM.SUN_DIRECTION.normalized())
	sm.set_shader_parameter("ambient_gain", _arg("ambient", FM.HEMI_INTENSITY / PI))
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = _arg("exposure", FM.EXPOSURE)
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = FM.FOG_COLOR
	env.fog_density = FM.FOG_DENSITY
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.0
	env.ssao_enabled = true
	env.ssao_radius = 0.8
	env.ssao_intensity = 1.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.light_color = FM.SUN_COLOR
	sun.light_energy = _arg("sun", FM.SUN_INTENSITY / PI)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 280.0
	# the near cascades keep the metres they had at 140 m (14, 28, 70), so close shadows stay as sharp
	sun.directional_shadow_split_1 = 0.05
	sun.directional_shadow_split_2 = 0.1
	sun.directional_shadow_split_3 = 0.25
	sun.directional_shadow_blend_splits = true    # no visible step in sharpness where one band hands over to the next
	sun.shadow_blur = 1.2
	add_child(sun)
	sun.look_at_from_position(Vector3.ZERO, -FM.SUN_DIRECTION.normalized(), Vector3.UP)


## A flat grid, fine (1 m) over the exploration area and coarser outwards to the 1.1 km terrain edge; the ground
## shader lifts it to the height field.
func _build_terrain() -> void:
	var axis := PackedFloat32Array()
	var x := -FM.TERRAIN * 0.5
	while x < FM.TERRAIN * 0.5:
		axis.append(x)
		var ax := absf(x)
		x += 1.0 if ax < 130.0 else (2.0 + (ax - 130.0) * 0.03)
	axis.append(FM.TERRAIN * 0.5)
	var n := axis.size()
	var verts := PackedVector3Array()
	verts.resize(n * n)
	for j in n:
		for i in n:
			verts[j * n + i] = Vector3(axis[i], 0.0, axis[j])
	var idx := PackedInt32Array()
	idx.resize((n - 1) * (n - 1) * 6)
	var k := 0
	for j in n - 1:
		for i in n - 1:
			var a := j * n + i
			idx[k] = a; idx[k + 1] = a + 1; idx[k + 2] = a + n
			idx[k + 3] = a + 1; idx[k + 4] = a + n + 1; idx[k + 5] = a + n
			k += 6
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/ground.gdshader")
	mat.set_shader_parameter("ground_color", load("res://textures/ground-color.jpg"))
	mat.set_shader_parameter("ground_normal", load("res://textures/ground-normal.jpg"))
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = mesh
	mi.material_override = mat
	mi.custom_aabb = AABB(Vector3(-FM.TERRAIN * 0.5, -12.0, -FM.TERRAIN * 0.5), Vector3(FM.TERRAIN, 24.0, FM.TERRAIN))
	add_child(mi)


## The walkable edge (settings panel, off by default): a 2.4 m light curtain on the ground along the square the camera
## clamp keeps you inside, sampled every metre so it follows the terrain.
## Contrast-adaptive sharpening over the finished frame, below the settings panel: puts back the fine detail TAA
## softens (0.7 measured as ~MSAA sharpness with far less shimmer in the grass).
func _build_sharpen() -> void:
	sharpen = CanvasLayer.new()
	sharpen.layer = -10
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/sharpen.gdshader")
	m.set_shader_parameter("amount", 0.7)
	rect.material = m
	sharpen.add_child(rect)
	add_child(sharpen)


func _build_border() -> void:
	var e := FM.EXPLORATION
	var corners := [Vector2(-e, -e), Vector2(e, -e), Vector2(e, e), Vector2(-e, e), Vector2(-e, -e)]
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var run := 0.0
	for c in 4:
		var a: Vector2 = corners[c]
		var b: Vector2 = corners[c + 1]
		var steps := int(a.distance_to(b))
		for i in steps + 1:
			var q := a.lerp(b, float(i) / steps)
			var h := FM.height_at(q.x, q.y)
			var base := verts.size()
			verts.append(Vector3(q.x, h - 0.05, q.y)); uvs.append(Vector2(run + i, 0.0))
			verts.append(Vector3(q.x, h + 2.4, q.y)); uvs.append(Vector2(run + i, 1.0))
			if i > 0:
				idx.append_array([base - 2, base - 1, base, base - 1, base + 1, base])
		run += steps
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/border.gdshader")
	border = MeshInstance3D.new()
	border.name = "WalkableEdge"
	border.mesh = mesh
	border.material_override = mat
	border.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	border.visible = args.has("border")
	add_child(border)


func _arg(k: String, d: float) -> float:
	return float(args[k]) if args.has(k) else d


func jump(name: String) -> void:
	var v: Array = VIEWPOINTS.get(name, VIEWPOINTS.entrance)
	var p: Vector3 = v[0]
	var t: Vector3 = v[1]
	if args.has("cam") and name == args.get("view", "entrance"):   # --cam=x,y,z,tx,ty,tz (heights above ground)
		var c: PackedFloat64Array = args.cam.split_floats(",")
		p = Vector3(c[0], c[1], c[2]); t = Vector3(c[3], c[4], c[5])
	p.y += FM.height_at(p.x, p.z)
	t.y += FM.height_at(t.x, t.z)
	cam.global_position = p
	var f := (t - p).normalized()
	yaw = atan2(-f.x, -f.z)
	pitch = asin(f.y)
	tyaw = yaw
	tpitch = pitch
	velocity = Vector3.ZERO
	cam.rotation = Vector3(pitch, yaw, 0.0)


func _process(delta: float) -> void:
	var dt := minf(delta, 0.055)
	time += dt
	RenderingServer.global_shader_parameter_set("forest_time", time)
	if not _scripted():
		_move(dt)
	cam.rotation = Vector3(pitch, yaw, 0.0)

	fps_acc += delta
	fps_n += 1
	if fps_acc > 0.5 and ui:
		var sz := get_viewport().get_visible_rect().size
		ui.update_stats("%d fps  ·  %d×%d" % [fps_n / fps_acc, sz.x, sz.y])
		fps_acc = 0.0
		fps_n = 0
	frames += 1
	if args.has("bench"):
		if frames == 1:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		elif frames == 240:
			bench_t0 = Time.get_ticks_usec()
		elif frames == 840:
			print("bench: %.2f ms/frame (%d fps)" % [(Time.get_ticks_usec() - bench_t0) / 600000.0, 600e6 / (Time.get_ticks_usec() - bench_t0)])
			get_tree().quit()
	if args.has("shot") and frames == int(_arg("settle", 120)):
		await RenderingServer.frame_post_draw
		var path: String = args.shot
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		get_viewport().get_texture().get_image().save_png(path)
		print("saved ", path)
		get_tree().quit()


func _move(dt: float) -> void:
	var smooth := 1.0 - exp(-dt * 18.0)
	yaw += (tyaw - yaw) * smooth
	pitch += (tpitch - pitch) * smooth
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		velocity = velocity.lerp(Vector3.ZERO, 1.0 - exp(-dt * 8.0))
	else:
		var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
		var right := Vector3(cos(yaw), 0.0, -sin(yaw))
		var f := _held("forward") - _held("back")
		var s := _held("right") - _held("left")
		var up := _held("rise") - _held("descend")
		var v := fwd * f + right * s
		v.y = up
		if v.length() > 1.0:
			v = v.normalized()
		v *= 8.0 if ui.pressed("sprint") else 3.2
		velocity = velocity.lerp(v, 1.0 - exp(-dt * 8.0))
	var p := cam.global_position + velocity * dt
	p.x = clampf(p.x, -FM.EXPLORATION, FM.EXPLORATION)
	p.z = clampf(p.z, -FM.EXPLORATION, FM.EXPLORATION)
	p.y = clampf(p.y, FM.height_at(p.x, p.z) + 0.32, 46.0)
	cam.global_position = p


func _held(id: String) -> float:
	return 1.0 if ui.pressed(id) else 0.0


func _unhandled_input(e: InputEvent) -> void:
	if _scripted():
		return
	if e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_LEFT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var d := 1.4 if e.button_index == MOUSE_BUTTON_WHEEL_UP else -1.4
			cam.global_position += -cam.global_basis.z * d
	elif e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		tyaw -= e.relative.x * 0.0025
		tpitch = clampf(tpitch - e.relative.y * 0.0025, -1.49, 1.49)
	elif e is InputEventKey and e.pressed and not e.echo:
		if e.keycode == KEY_ESCAPE:
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			else:
				get_tree().quit()
