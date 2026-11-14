extends Node2D

const Player = preload("res://scripts/player.gd")
const Enemy = preload("res://scripts/enemy.gd")
const Tuning = preload("res://scripts/tuning.gd")
const Trials = preload("res://scripts/trials.gd")
const PanelUI = preload("res://scripts/panel.gd")
const ArenaView = preload("res://scripts/arena_view.gd")

const FLOOR := 555.0
const PLATFORM := Rect2(375, 428, 253, 13)
const FLOOR_RECT := Rect2(30, FLOOR, 866, 32)
const MODES := ["角色手感", "战斗决策", "武器差异"]
const WEAPONS := ["快武器", "重武器"]
const PROFILES := ["A · 灵敏", "B · 惯性"]
const COUNTERS := [
	"jump", "roll", "buffered", "attack", "hit", "hurt", "dodge", "spacing",
	"enemy_attack", "early", "late", "punish", "interrupt",
]

var motion := [Tuning.MOVEMENT_A.duplicate(), Tuning.MOVEMENT_B.duplicate()]
var arms := [Tuning.FAST.duplicate(), Tuning.HEAVY.duplicate()]
var enemy_data: Dictionary = Tuning.ENEMY.duplicate()
var options := {"sound": true, "freeze": true, "shake": true, "boxes": true}
var mode := 0
var profile_id := 0
var weapon_id := 0
var counts := {}
var elapsed := 0.0
var distance := 0.0
var hit_distance := 0.0
var outcome := ""
var message := ""
var freeze := 0.0
var shake := 0.0
var enemy_evaded := false
var started := false
var paused := false
var motion_platform: StaticBody2D
var player: Player
var enemy: Enemy
var view: ArenaView
var panel: PanelUI
var sounds := {}

func _ready() -> void:
	bind_keys("move_left", [KEY_A, KEY_LEFT])
	bind_keys("move_right", [KEY_D, KEY_RIGHT])
	bind_keys("jump", [KEY_SPACE, KEY_W])
	bind_keys("roll", [KEY_K, KEY_SHIFT])
	bind_keys("attack", [KEY_J])
	load_setup()
	stage_body(FLOOR_RECT)
	stage_body(Rect2(6, 198, 24, FLOOR - 198))
	stage_body(Rect2(896, 198, 24, FLOOR - 198))
	motion_platform = stage_body(PLATFORM, true)
	player = Player.new()
	add_child(player)
	player.action_started.connect(on_player_action)
	enemy = Enemy.new()
	add_child(enemy)
	enemy.phase_started.connect(on_enemy_phase)
	sounds = {
		"warn": build_sound(330.0, 0.12, 0.38, 0.29),
		"hit": build_sound(210.0, 0.10, -0.5, 0.38),
		"hurt": build_sound(106.0, 0.20, -0.4, 0.35),
		"dodge": build_sound(520.0, 0.10, 0.55, 0.24),
	}
	view = ArenaView.new()
	view.lab = self
	add_child(view)
	panel = PanelUI.new()
	panel.lab = self
	add_child(panel)
	reset_trial()
	panel.refresh()

func bind_keys(action: StringName, keys: Array) -> void:
	InputMap.add_action(action)
	for key: int in keys:
		var event := InputEventKey.new()
		event.physical_keycode = key
		InputMap.action_add_event(action, event)

func stage_body(rect: Rect2, one_way := false) -> StaticBody2D:
	var body := StaticBody2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.one_way_collision = one_way
	body.position = rect.get_center()
	body.add_child(collision)
	add_child(body)
	return body

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_1, KEY_2, KEY_3:
			select_mode(int(event.physical_keycode) - KEY_1)
		KEY_TAB:
			if mode == 0:
				select_profile(1 - profile_id)
			elif mode == 2:
				select_weapon(1 - weapon_id)
		KEY_R:
			reset_trial()
		KEY_P:
			toggle_pause()

func select_mode(value: int) -> void:
	if mode == value:
		return
	mode = value
	reset_trial()
	panel.refresh()

func select_profile(value: int) -> void:
	if profile_id == value:
		return
	profile_id = value
	reset_trial()
	panel.refresh()

func select_weapon(value: int) -> void:
	if weapon_id == value or mode != 2:
		return
	weapon_id = value
	reset_trial()
	panel.refresh()

func arm_index() -> int:
	return 0 if mode == 1 else weapon_id

func reset_trial() -> void:
	counts.clear()
	for key in COUNTERS:
		counts[key] = 0
	motion_platform.collision_layer = 1 if mode == 0 else 0
	player.movement = motion[profile_id]
	player.weapon = arms[arm_index()]
	player.attack_enabled = mode > 0
	player.reset(Vector2(206, FLOOR))
	enemy.profile = enemy_data
	enemy.reset(Vector2(674, FLOOR))
	started = false
	paused = false
	elapsed = 0.0
	distance = 0.0
	hit_distance = 0.0
	freeze = 0.0
	shake = 0.0
	enemy_evaded = false
	outcome = ""
	message = "输入移动、跳跃或翻滚开始" if mode == 0 else "输入移动、跳跃、攻击或翻滚开始"

func toggle_pause() -> void:
	paused = not paused

func _physics_process(delta: float) -> void:
	if paused or not outcome.is_empty() or panel.note.has_focus():
		return
	player.sample_inputs()
	if not started:
		started = (
			Input.is_action_pressed("move_left") or Input.is_action_pressed("move_right")
			or player.jump_buffer >= 0.0 or player.roll_buffer >= 0.0 or player.attack_buffer >= 0.0
		)
		if not started:
			player.step(delta)
			return
		message = ""
	elapsed += delta
	shake = maxf(0.0, shake - delta)
	if freeze > 0.0:
		freeze -= delta
		return

	var before := player.position
	player.step(delta)
	distance += before.distance_to(player.position)
	if mode == 0:
		return
	enemy.step(delta, player.position)
	resolve_hits()
	if player.hp <= 0 or enemy.hp <= 0:
		outcome = "击败敌人" if enemy.hp <= 0 else "玩家倒下"
		message = outcome + " · 可记录试验或按 R 重开"

func hit_rect(at: Vector2, direction: float, reach: float) -> Rect2:
	var left := at.x if direction > 0.0 else at.x - reach
	return Rect2(left, at.y - 62.0, reach, 58.0)

func hurt_rect(at: Vector2, size: Vector2) -> Rect2:
	return Rect2(at - Vector2(size.x * 0.5, size.y), size)

func resolve_hits() -> void:
	if player.attack_phase() == "active" and not player.spent_swing:
		var zone := hit_rect(player.position, player.facing, player.swing.reach)
		if zone.intersects(hurt_rect(enemy.position, Enemy.BODY)):
			var punishing := enemy.state == &"recovery"
			var interrupted: bool = player.swing.interrupts and enemy.state == &"windup" and enemy.hp > player.swing.damage
			player.spent_swing = true
			counts.hit += 1
			hit_distance += absf(player.position.x - enemy.position.x)
			if punishing:
				counts.punish += 1
			if interrupted:
				counts.interrupt += 1
			enemy.receive_hit(int(player.swing.damage), player.swing.interrupts)
			message = "打断前摇" if interrupted else ("抓住后摇 · 反击命中" if punishing else "命中")
			impact("hit", 0.062 if player.swing.interrupts else 0.036, 0.16)
	if enemy.state != &"active" or enemy.spent_swing:
		return
	var zone := hit_rect(enemy.position, enemy.facing, enemy.swing.reach)
	if not zone.intersects(hurt_rect(player.position, Player.BODY)):
		return
	if player.invulnerable():
		if not enemy_evaded:
			enemy_evaded = true
			counts.dodge += 1
			message = "翻滚避伤 · 观察敌人后摇"
			play_sound("dodge")
	elif player.receive_hit(enemy.position.x):
		enemy.spent_swing = true
		counts.hurt += 1
		message = "受击 · 攻击、翻滚和站位时机都可以复盘"
		impact("hurt", 0.052, 0.23)

func on_player_action(action: StringName, buffered: bool) -> void:
	counts[action] += 1
	if buffered:
		counts.buffered += 1
	if action != &"attack":
		return
	if enemy.state == &"windup":
		counts.early += 1
	elif enemy.state == &"recovery":
		counts.late += 1

func on_enemy_phase(phase: StringName) -> void:
	if phase == &"windup":
		enemy_evaded = false
		play_sound("warn")
	elif phase == &"active":
		counts.enemy_attack += 1
	elif phase == &"recovery" and not enemy.spent_swing and not enemy_evaded:
		counts.spacing += 1
		message = "拉开或绕出攻击范围 · 敌人进入后摇"

func impact(sound: String, pause_time: float, shake_time: float) -> void:
	play_sound(sound)
	if options.freeze:
		freeze = maxf(freeze, pause_time)
	if options.shake:
		shake = shake_time

func play_sound(id: String) -> void:
	if not options.sound:
		return
	var audio := AudioStreamPlayer.new()
	audio.stream = sounds[id]
	audio.volume_db = -13
	add_child(audio)
	audio.finished.connect(audio.queue_free)
	audio.play()

func build_sound(frequency: float, duration: float, sweep: float, texture: float) -> AudioStreamWAV:
	var rate := 22050
	var samples := PackedByteArray()
	samples.resize(int(duration * rate))
	var phase := 0.0
	for i in samples.size():
		var t := i / float(samples.size())
		phase += TAU * frequency * (1.0 + sweep * t) / rate
		var tone := sin(phase) * (1.0 - texture) + sin(phase * 2.31) * texture
		var sample := int(tone * 107.0 * minf(t * 35.0, 1.0) * pow(1.0 - t, 2.1))
		samples[i] = sample & 255
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = rate
	stream.data = samples
	return stream

func change_parameter(group: String, key: String, value: float) -> void:
	match group:
		"motion":
			motion[profile_id][key] = value
		"enemy":
			enemy_data[key] = value
		"weapon":
			arms[arm_index()][key] = value
	save_setup()
	if started:
		reset_trial()
		message = "参数已变更 · 新试验就绪"

func save_trial(note: String) -> Error:
	if not started:
		return ERR_UNCONFIGURED
	return Trials.append_trial([
		Time.get_datetime_string_from_system(), MODES[mode], PROFILES[profile_id],
		WEAPONS[arm_index()] if mode > 0 else "",
		outcome if not outcome.is_empty() else "手动记录",
		snappedf(elapsed, 0.01), roundi(distance), counts.jump, counts.roll, counts.buffered,
		counts.attack, counts.hit, counts.hurt, counts.dodge, counts.spacing, counts.enemy_attack,
		counts.early, counts.late, counts.punish, counts.interrupt,
		roundi(hit_distance / maxi(1, counts.hit)), options.sound, options.freeze, options.shake, note,
		JSON.stringify(motion[profile_id]), JSON.stringify(enemy_data) if mode > 0 else "",
		JSON.stringify(arms[arm_index()]) if mode > 0 else "",
	])

func save_setup() -> bool:
	var config := ConfigFile.new()
	config.set_value("tuning", "motion", motion)
	config.set_value("tuning", "weapons", arms)
	config.set_value("tuning", "enemy", enemy_data)
	config.set_value("tuning", "feedback", options)
	return config.save(Trials.SAVE) == OK

func load_setup() -> void:
	var config := ConfigFile.new()
	if config.load(Trials.SAVE) != OK:
		return
	var saved_motion: Array = config.get_value("tuning", "motion", motion)
	var saved_arms: Array = config.get_value("tuning", "weapons", arms)
	for index in 2:
		if index < saved_motion.size():
			motion[index].merge(saved_motion[index], true)
		if index < saved_arms.size():
			arms[index].merge(saved_arms[index], true)
	enemy_data.merge(config.get_value("tuning", "enemy", {}), true)
	options.merge(config.get_value("tuning", "feedback", {}), true)

func restore_defaults() -> void:
	motion[profile_id] = (Tuning.MOVEMENT_A if profile_id == 0 else Tuning.MOVEMENT_B).duplicate()
	if mode > 0:
		enemy_data = Tuning.ENEMY.duplicate()
	if mode == 2:
		arms[weapon_id] = (Tuning.FAST if weapon_id == 0 else Tuning.HEAVY).duplicate()
	save_setup()
	reset_trial()
	panel.refresh()
