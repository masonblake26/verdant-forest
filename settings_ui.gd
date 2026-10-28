extends CanvasLayer
## The viewer's settings panel, bottom left: Movement (condensed), then Display, World and Interface. Every row shows
## its fixed hotkey on a key chip. Toggles are saved to user://settings.cfg. forest.gd owns what the settings do
## (apply_setting, action).

const SAVE := "user://settings.cfg"

# id, label, section, default key, kind: toggle (hotkey flips it), hold (movement), action (one press), show (a fixed
# control, listed in SHOWN)
const ITEMS := [
	["move", "Move", "Movement", KEY_NONE, "show"],
	["rise", "Rise", "Movement", KEY_SPACE, "hold"],
	["descend", "Descend", "Movement", KEY_E, "hold"],
	["sprint", "Sprint", "Movement", KEY_SHIFT, "hold"],
	["zoom", "Zoom", "Movement", KEY_NONE, "show"],
	["fullscreen", "Fullscreen", "Display", KEY_F11, "toggle"],
	["msaa", "Crisp edges (MSAA)", "Display", KEY_T, "toggle"],
	["stats", "Frame rate", "Display", KEY_F3, "toggle"],
	["border", "Walkable edge", "World", KEY_B, "toggle"],
	["home", "Return to the trail", "World", KEY_R, "action"],
	["panel", "This panel", "Interface", KEY_H, "toggle"],
]
const SHOWN := {"move": "WASD", "zoom": "Mouse Wheel"}
const WASD := {"forward": KEY_W, "back": KEY_S, "left": KEY_A, "right": KEY_D}
const DEFAULTS := {"fullscreen": false, "msaa": false, "stats": true, "border": false, "panel": true}

# Moss, bark and late-afternoon amber.
const C_BG := Color(0.043, 0.075, 0.051, 0.88)
const C_EDGE := Color(0.49, 0.69, 0.36, 0.55)
const C_TITLE := Color(0.92, 0.95, 0.87)
const C_LEAF := Color(0.56, 0.8, 0.42)
const C_SECTION := Color(0.91, 0.78, 0.45)
const C_TEXT := Color(0.86, 0.91, 0.82)
const C_DIM := Color(0.6, 0.7, 0.56)
const C_CHIP := Color(0.1, 0.16, 0.1)
const C_ON := Color(0.44, 0.64, 0.33)
const C_OFF := Color(0.13, 0.19, 0.13)

var forest: Node
var values := {}
var keys := {}
var panel: PanelContainer
var tab: Button
var stats: Label
var switches := {}


## Saved settings, read straight from disk (forest.gd needs fullscreen before the panel exists).
static func load_cfg() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(SAVE)
	return cfg


func _ready() -> void:
	layer = 10
	var cfg := load_cfg()
	keys.merge(WASD)
	for it in ITEMS:
		if it[4] != "show":
			keys[it[0]] = it[3]
		if it[4] == "toggle":
			values[it[0]] = bool(cfg.get_value("settings", it[0], DEFAULTS[it[0]]))
	_build()
	for id in values:
		_apply(id)


func pressed(id: String) -> bool:
	return Input.is_key_pressed(keys[id])


func set_value(id: String, v: bool) -> void:
	values[id] = v
	_apply(id)
	_save()


func update_stats(text: String) -> void:
	stats.text = text


func _apply(id: String) -> void:
	var v: bool = values[id]
	if switches.has(id):
		_paint_switch(switches[id], v)
	match id:
		"panel":
			panel.visible = v
			tab.visible = not v
		"stats":
			stats.visible = v
		_:
			forest.apply_setting(id, v)


func _save() -> void:
	var cfg := ConfigFile.new()
	for id in values:
		cfg.set_value("settings", id, values[id])
	cfg.save(SAVE)


# ---------------------------------------------------------------- hotkeys

func _unhandled_key_input(e: InputEvent) -> void:
	if not e.pressed or e.echo:
		return
	for it in ITEMS:
		if keys.get(it[0], KEY_NONE) == e.keycode:
			if it[4] == "toggle":
				set_value(it[0], not values[it[0]])
				get_viewport().set_input_as_handled()
			elif it[4] == "action":
				forest.action(it[0])
				get_viewport().set_input_as_handled()
			return


# ---------------------------------------------------------------- layout

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(C_BG, C_EDGE, 14, 20, 1))
	root.add_child(panel)
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_left = 24
	panel.offset_top = -24
	panel.offset_bottom = -24
	panel.custom_minimum_size.x = 380

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	col.add_child(head)
	head.add_child(_label("❦", 26, C_LEAF))
	head.add_child(_label("Verdant Forest", 21, C_TITLE))

	var section := ""
	var grid: GridContainer
	for it in ITEMS:
		if it[2] != section:
			section = it[2]
			col.add_child(_spacer(6))
			col.add_child(_section(section))
			grid = GridContainer.new()
			grid.columns = 3
			grid.add_theme_constant_override("h_separation", 10)
			grid.add_theme_constant_override("v_separation", 5)
			col.add_child(grid)
		var name := _label(it[1], 15, C_TEXT)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(name)
		if it[4] == "toggle":
			var sw := Button.new()
			sw.toggle_mode = true
			sw.focus_mode = Control.FOCUS_NONE
			sw.custom_minimum_size = Vector2(58, 26)
			sw.add_theme_font_size_override("font_size", 12)
			var id: String = it[0]
			sw.pressed.connect(func() -> void: set_value(id, not values[id]))
			switches[id] = sw
			grid.add_child(sw)
		else:
			grid.add_child(Control.new())
		var chip := Button.new()
		chip.focus_mode = Control.FOCUS_NONE
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.custom_minimum_size = Vector2(110 if it[4] == "show" else 84, 26)
		chip.add_theme_font_size_override("font_size", 13)
		chip.text = SHOWN[it[0]] if SHOWN.has(it[0]) else OS.get_keycode_string(keys[it[0]])
		chip.add_theme_stylebox_override("normal", _box(C_CHIP, C_EDGE, 7, 6, 1))
		chip.add_theme_color_override("font_color", Color(0.95, 0.9, 0.76))
		grid.add_child(chip)

	col.add_child(_spacer(8))
	col.add_child(_rule())
	stats = _label("", 13, C_DIM)
	col.add_child(stats)

	# Collapsed: a small tab in the same corner brings the panel back.
	tab = Button.new()
	tab.focus_mode = Control.FOCUS_NONE
	tab.add_theme_font_size_override("font_size", 13)
	for s in ["normal", "hover", "pressed"]:
		tab.add_theme_stylebox_override(s, _box(C_BG if s == "normal" else C_OFF, C_EDGE, 10, 8, 1))
	tab.add_theme_color_override("font_color", C_TEXT)
	tab.pressed.connect(func() -> void: set_value("panel", true))
	root.add_child(tab)
	tab.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	tab.grow_vertical = Control.GROW_DIRECTION_BEGIN
	tab.offset_left = 24
	tab.offset_top = -24
	tab.offset_bottom = -24
	_paint_tab()


func _paint_switch(sw: Button, on: bool) -> void:
	sw.set_pressed_no_signal(on)
	sw.text = "ON" if on else "OFF"
	var bg := C_ON if on else C_OFF
	for s in ["normal", "hover", "pressed", "hover_pressed"]:
		sw.add_theme_stylebox_override(s, _box(bg.lightened(0.08) if s.begins_with("hover") else bg, C_EDGE, 13, 4, 1))
	var fc := Color(0.06, 0.11, 0.05) if on else C_DIM
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		sw.add_theme_color_override(c, fc)


func _paint_tab() -> void:
	tab.text = "❦  Settings  ·  %s" % OS.get_keycode_string(keys.panel)


func _box(bg: Color, edge: Color, radius: int, pad: int, border: int) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = edge
	b.set_border_width_all(border)
	b.set_corner_radius_all(radius)
	b.set_content_margin_all(pad)
	b.content_margin_top = pad * 0.5 if pad < 10 else pad
	b.content_margin_bottom = b.content_margin_top
	if radius >= 14:
		b.shadow_color = Color(0, 0, 0, 0.35)
		b.shadow_size = 14
	return b


func _label(t: String, size: int, c: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	return l


func _section(t: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := _label(t.to_upper(), 12, C_SECTION)
	row.add_child(l)
	var line := _rule()
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(line)
	return row


func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(C_EDGE, 0.35)
	r.custom_minimum_size = Vector2(0, 1)
	return r


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	return c
