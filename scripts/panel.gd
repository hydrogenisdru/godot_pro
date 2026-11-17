extends Control

const Tuning = preload("res://scripts/tuning.gd")
const Trials = preload("res://scripts/trials.gd")
const INK := Color("#deeaf1")
const MUTED := Color("#8fa7b6")
const ACCENT := Color("#69e0c3")

var lab
var navigation: Array[Button] = []
var scroll: ScrollContainer
var fields: VBoxContainer
var note: LineEdit
var save_status: Label
var title: Label
var pages: HBoxContainer
var feedback_page := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ui_theme := Theme.new()
	ui_theme.default_font = preload("res://scripts/lab_font.gd").create()
	theme = ui_theme
	var bar := HBoxContainer.new()
	bar.position = Vector2(28, 103)
	bar.add_theme_constant_override("separation", 9)
	add_child(bar)
	for i in 3:
		var button := make_button("%s   %s" % [i + 1, lab.MODES[i]], lab.select_mode.bind(i))
		button.custom_minimum_size = Vector2(171, 36)
		bar.add_child(button)
		navigation.append(button)
	var reset := make_button("R   重开", lab.reset_trial)
	reset.custom_minimum_size = Vector2(95, 36)
	bar.add_child(reset)
	var pause := make_button("P   暂停", lab.toggle_pause)
	pause.custom_minimum_size = Vector2(95, 36)
	bar.add_child(pause)

	var shell := PanelContainer.new()
	shell.position = Vector2(930, 23)
	shell.size = Vector2(324, 752)
	var skin := style("#101e2a", "#2a4050")
	skin.content_margin_left = 15
	skin.content_margin_right = 15
	skin.content_margin_top = 13
	skin.content_margin_bottom = 12
	shell.add_theme_stylebox_override("panel", skin)
	add_child(shell)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 6)
	shell.add_child(stack)
	title = label("实时调参", 23, INK)
	stack.add_child(title)
	pages = HBoxContainer.new()
	for index in 2:
		var button := make_button("战斗参数" if index == 0 else "打击反馈", select_page.bind(index == 1))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pages.add_child(button)
	stack.add_child(pages)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(scroll)
	fields = VBoxContainer.new()
	fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields.add_theme_constant_override("separation", 3)
	scroll.add_child(fields)

	stack.add_child(label("试验记录", 18, ACCENT))
	note = LineEdit.new()
	note.placeholder_text = "备注：流畅度、判断或策略"
	note.add_theme_font_size_override("font_size", 14)
	note.text_submitted.connect(func(_value: String): record())
	note.gui_input.connect(on_note_input)
	stack.add_child(note)
	var actions := HBoxContainer.new()
	stack.add_child(actions)
	for button in [
		make_button("记录到 CSV", record),
		make_button("打开记录目录", func(): OS.shell_open(ProjectSettings.globalize_path("user://"))),
	]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(button)
	save_status = label("记录时间、指标和当前参数", 13, MUTED)
	stack.add_child(save_status)

func refresh() -> void:
	for i in navigation.size():
		var selected: bool = i == lab.mode
		navigation[i].add_theme_stylebox_override("normal", style("#1d534c", "#69e0c3") if selected else style("#172936", "#2d4656"))
	for child in fields.get_children():
		fields.remove_child(child)
		child.queue_free()
	pages.visible = lab.mode > 0
	var show_feedback: bool = pages.visible and feedback_page
	for index in pages.get_child_count():
		var button: Button = pages.get_child(index)
		var active := (index == 1) == show_feedback
		button.add_theme_stylebox_override("normal", style("#1d534c", "#69e0c3") if active else style("#172936", "#2d4656"))
	scroll.scroll_vertical = 0
	if show_feedback:
		for spec in Tuning.FEEDBACK_FIELDS:
			add_toggle(spec[1], lab.options[spec[0]], set_option.bind(spec[0]))
			add_fields("feedback", lab.feedback_values, spec[2])
			fields.add_child(HSeparator.new())
		fields.add_child(make_button("恢复反馈默认值", lab.restore_feedback_defaults))
		return
	var tabs := HBoxContainer.new()
	fields.add_child(tabs)
	var choosing_weapon: bool = lab.mode == 2
	for i in 2:
		var choice: String = lab.WEAPONS[i] if choosing_weapon else lab.PROFILES[i]
		var callback: Callable = lab.select_weapon.bind(i) if choosing_weapon else lab.select_profile.bind(i)
		var button := make_button(choice, callback)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var selected: bool = i == (lab.weapon_id if choosing_weapon else lab.profile_id)
		if selected:
			button.add_theme_stylebox_override("normal", style("#1d534c", "#69e0c3"))
		tabs.add_child(button)
	fields.add_child(label("调参或切换方案会重开试验", 13, MUTED))
	if lab.mode > 0:
		section("副武器 · 爆炸球", "throw", lab.throw_data, Tuning.THROW_FIELDS)
	if lab.mode == 2:
		section("当前武器", "weapon", lab.arms[lab.arm_index()], Tuning.W_FIELDS)
		add_toggle("延长敌人受击硬直", lab.arms[lab.arm_index()].interrupts, set_extended_hitstun)
	if lab.mode > 0:
		section("近战敌人", "enemy", lab.enemy_data, Tuning.E_FIELDS)
	section("角色控制 · " + lab.PROFILES[lab.profile_id], "motion", lab.motion[lab.profile_id], Tuning.M_FIELDS)
	if lab.mode == 2:
		var motion_tabs := HBoxContainer.new()
		fields.add_child(motion_tabs)
		for i in 2:
			motion_tabs.add_child(make_button(lab.PROFILES[i], lab.select_profile.bind(i)))
	fields.add_child(label("反馈与观测", 16, ACCENT))
	for entry in [["sound", "合成短音效"], ["boxes", "显示攻击/受击框"]]:
		var key: String = entry[0]
		add_toggle(entry[1], lab.options[key], set_option.bind(key))
	fields.add_child(make_button("恢复当前实验默认参数", lab.restore_defaults))

func select_page(show_feedback: bool) -> void:
	feedback_page = show_feedback
	refresh()

func section(heading: String, group: String, data: Dictionary, specs: Array) -> void:
	fields.add_child(label(heading, 16, ACCENT))
	add_fields(group, data, specs)

func add_fields(group: String, data: Dictionary, specs: Array) -> void:
	for spec in specs:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 3)
		fields.add_child(row)
		var caption := label(spec[1], 13, INK)
		caption.custom_minimum_size.x = 87
		row.add_child(caption)
		if spec[5] == "color":
			var picker := ColorPickerButton.new()
			picker.color = data[spec[0]]
			picker.edit_alpha = false
			picker.custom_minimum_size = Vector2(58, 22)
			picker.color_changed.connect(set_color.bind(group, spec[0]))
			row.add_child(picker)
			continue
		var slider := HSlider.new()
		slider.min_value = spec[2]
		slider.max_value = spec[3]
		slider.step = spec[4]
		slider.value = data[spec[0]]
		slider.focus_mode = Control.FOCUS_NONE
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.custom_minimum_size.x = 65
		row.add_child(slider)
		var value := label(format_value(data[spec[0]], spec[5]), 12, MUTED)
		value.custom_minimum_size.x = 72
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value)
		slider.value_changed.connect(set_slider.bind(group, spec[0], spec[5], value))

func set_slider(value: float, group: String, key: String, unit: String, display: Label) -> void:
	display.text = format_value(value, unit)
	lab.change_parameter(group, key, value)

func set_color(value: Color, group: String, key: String) -> void:
	lab.change_parameter(group, key, value)

func format_value(value: float, unit: String) -> String:
	if unit == "ms":
		return "%d ms" % roundi(value * 1000.0)
	if unit == "×":
		return "%.2f ×" % value
	if unit == "%":
		return "%d%%" % roundi(value * 100.0)
	if unit == "px" and not is_equal_approx(value, roundf(value)):
		return "%.1f px" % value
	return "%d %s" % [roundi(value), unit]

func set_extended_hitstun(enabled: bool) -> void:
	lab.arms[lab.arm_index()].interrupts = enabled
	lab.save_setup()
	lab.reset_trial()

func set_option(enabled: bool, key: String) -> void:
	lab.options[key] = enabled
	lab.save_setup()
	if key != "boxes" and lab.started:
		lab.reset_trial()
		lab.message = "反馈已变更 · 新试验就绪"

func add_toggle(caption: String, enabled: bool, callback: Callable) -> void:
	var toggle := CheckBox.new()
	toggle.text = caption
	toggle.button_pressed = enabled
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.add_theme_font_size_override("font_size", 14)
	toggle.toggled.connect(callback)
	fields.add_child(toggle)

func on_note_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		note.release_focus()
		note.accept_event()

func record() -> void:
	var result: Error = lab.save_trial(note.text)
	if result == OK:
		save_status.text = "已记录到 trials.csv"
		note.clear()
		note.release_focus()
	elif result == ERR_UNCONFIGURED:
		save_status.text = "先在场地内操作，再记录试验"
	else:
		save_status.text = "保存失败 · " + error_string(result)

func make_button(caption: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_stylebox_override("normal", style("#172936", "#2d4656"))
	button.add_theme_stylebox_override("hover", style("#244353", "#6eabbb"))
	button.add_theme_stylebox_override("pressed", style("#1d534c", "#69e0c3"))
	button.pressed.connect(callback)
	return button

func label(caption: String, size_px: int, color: Color) -> Label:
	var result := Label.new()
	result.text = caption
	result.add_theme_font_size_override("font_size", size_px)
	result.add_theme_color_override("font_color", color)
	return result

func style(fill: String, border: String) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(fill)
	box.border_color = Color(border)
	box.set_border_width_all(1)
	box.set_corner_radius_all(7)
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	return box
