extends Node2D

const Player = preload("res://scripts/player.gd")
const Enemy = preload("res://scripts/enemy.gd")
const Tuning = preload("res://scripts/tuning.gd")
const Trials = preload("res://scripts/trials.gd")
const PanelUI = preload("res://scripts/panel.gd")
const ArenaView = preload("res://scripts/arena_view.gd")
const ThrowBall = preload("res://scripts/throw_ball.gd")
const CombatFeedback = preload("res://scripts/combat_feedback.gd")

const FLOOR := 555.0
const PLATFORM := Rect2(375, 428, 253, 13)
const FLOOR_RECT := Rect2(30, FLOOR, 866, 32)
const MODES := ["角色手感", "战斗决策", "武器差异"]
const WEAPONS := ["快武器", "重武器"]
const PROFILES := ["A · 灵敏", "B · 惯性"]
const COUNTERS := [
	"jump", "air_jump", "roll", "buffered", "attack", "hit", "hurt", "dodge", "spacing",
	"enemy_attack", "early", "late", "punish", "interrupt",
]

var motion := [Tuning.MOVEMENT_A.duplicate(), Tuning.MOVEMENT_B.duplicate()]
var arms := [Tuning.FAST.duplicate(), Tuning.HEAVY.duplicate()]
var enemy_data: Dictionary = Tuning.ENEMY.duplicate()
var throw_data: Dictionary = Tuning.THROW_BALL.duplicate()
var options := Tuning.FEEDBACK_SWITCHES.merged({"sound": true, "boxes": true})
var feedback_values := Tuning.FEEDBACK.duplicate()
var feedback := CombatFeedback.new(feedback_values, options)
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
var enemy_evaded := false
var player_struck_ball := false
var enemy_struck_ball := false
var blast_position := Vector2.ZERO
var blast_time := 0.0
var blast_targets_player := false
var started := false
var paused := false
var motion_platform: StaticBody2D
var player: Player
var enemy: Enemy
var ball: ThrowBall
var view: ArenaView
var panel: PanelUI
var sounds := {}

func _ready() -> void:
	bind_keys("move_left", [KEY_A, KEY_LEFT])
	bind_keys("move_right", [KEY_D, KEY_RIGHT])
	bind_keys("jump", [KEY_SPACE, KEY_W])
	bind_keys("roll", [KEY_K, KEY_SHIFT])
	bind_keys("attack", [KEY_J])
	bind_keys("throw_ball", [KEY_L])
	load_setup()
	stage_body(FLOOR_RECT)
	stage_body(Rect2(6, 198, 24, FLOOR - 198))
	stage_body(Rect2(896, 198, 24, FLOOR - 198))
	motion_platform = stage_body(PLATFORM)
	player = Player.new()
	add_child(player)
	player.action_started.connect(on_player_action)
	player.attack_became_active.connect(on_player_attack_active)
	enemy = Enemy.new()
	add_child(enemy)
	enemy.phase_started.connect(on_enemy_phase)
	sounds = {
		"warn": build_sound(330.0, 0.12, 0.38, 0.29),
		"hit": build_sound(210.0, 0.10, -0.5, 0.38),
		"hurt": build_sound(106.0, 0.20, -0.4, 0.35),
		"dodge": build_sound(520.0, 0.10, 0.55, 0.24),
		"blast": build_sound(82.0, 0.24, -0.36, 0.54),
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
	clear_ball()
	blast_time = 0.0
	player_struck_ball = false
	enemy_struck_ball = false
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
	feedback.clear()
	enemy_evaded = false
	outcome = ""
	message = "输入移动、跳跃或翻滚开始" if mode == 0 else "输入移动、跳跃、攻击、翻滚或投掷开始"

func toggle_pause() -> void:
	paused = not paused

func _physics_process(delta: float) -> void:
	if paused or panel.note.has_focus():
		return
	feedback.step(delta)
	blast_time = maxf(0.0, blast_time - delta)
	if not outcome.is_empty():
		return
	player.sample_inputs()
	var wants_throw := mode > 0 and Input.is_action_just_pressed("throw_ball")
	if not started:
		started = (
			Input.is_action_pressed("move_left") or Input.is_action_pressed("move_right")
			or player.jump_buffer >= 0.0 or player.roll_buffer >= 0.0 or player.attack_buffer >= 0.0
			or wants_throw
		)
		if not started:
			player.step(delta)
			return
		message = ""
	elapsed += delta
	if freeze > 0.0:
		if wants_throw:
			throw_ball()
		freeze -= delta
		return

	var before := player.position
	player.step(delta)
	distance += before.distance_to(player.position)
	if mode == 0:
		return
	if wants_throw:
		throw_ball()
	enemy.step(delta, player.position, enemy_ball_direction())
	advance_ball(delta)
	if player.hp > 0 and enemy.hp > 0:
		resolve_hits()
	if player.hp <= 0 or enemy.hp <= 0:
		outcome = "击败敌人" if enemy.hp <= 0 else "玩家倒下"
		message = outcome + " · 可记录试验或按 R 重开"

func throw_ball() -> void:
	if ball != null or player.state == &"hurt":
		return
	ball = ThrowBall.new()
	ball.position = player.position - Vector2(0.0, Player.BODY.y * 0.6)
	add_child(ball)
	ball.launch(player, player.facing, throw_data.fuse)

func clear_ball() -> void:
	if ball != null:
		ball.queue_free()
		ball = null

func enemy_ball_direction() -> float:
	if ball == null or ball.targets_player or enemy.state != &"chase":
		return 0.0
	var direction := signf(ball.position.x - enemy.position.x)
	if is_zero_approx(direction):
		direction = enemy.facing
	var zone := hit_rect(enemy.position, direction, enemy.profile.reach)
	return direction if ball.intersects(zone, ThrowBall.RADIUS) else 0.0

func advance_ball(delta: float) -> void:
	if ball == null:
		return
	var striker_bounds := Rect2()
	if ball.ignored_body == player:
		striker_bounds = hurt_rect(player.position, Player.BODY)
	elif ball.ignored_body == enemy:
		striker_bounds = hurt_rect(enemy.position, Enemy.BODY)
	ball.step(delta, striker_bounds)
	if ball.remaining > 0.0001:
		return

	blast_position = ball.position
	blast_time = 0.28
	blast_targets_player = ball.targets_player
	var target: CharacterBody2D = player if blast_targets_player else enemy
	var bounds := hurt_rect(target.position, Player.BODY if blast_targets_player else Enemy.BODY)
	var damage := 1 if blast_targets_player else 2
	var dealt_damage := false
	if ball.intersects(bounds, ThrowBall.BLAST_RADIUS):
		dealt_damage = apply_damage(target, damage, ball.position.x, bounds, ball.position.clamp(bounds.position, bounds.end), "blast")
	if blast_targets_player:
		if dealt_damage:
			counts.hurt += 1
			message = "爆炸球命中玩家"
		else:
			message = "躲过了爆炸"
	elif dealt_damage:
		message = "爆炸球命中敌人"
	else:
		message = "爆炸范围内没有敌人"
	if not dealt_damage:
		play_sound("blast")
	clear_ball()

func hit_rect(at: Vector2, direction: float, reach: float) -> Rect2:
	var left := at.x if direction > 0.0 else at.x - reach
	return Rect2(left, at.y - 62.0, reach, 58.0)

func hurt_rect(at: Vector2, size: Vector2) -> Rect2:
	return Rect2(at - Vector2(size.x * 0.5, size.y), size)

func resolve_hits() -> void:
	if player.attack_phase() == "active":
		var zone := hit_rect(player.position, player.facing, player.swing.reach)
		if not player_struck_ball and ball != null and ball.intersects(zone, ThrowBall.RADIUS):
			ball.deflect(player, player.facing, false)
			player_struck_ball = true
			message = "击球 · 爆炸将攻击敌人"
		var enemy_bounds := hurt_rect(enemy.position, Enemy.BODY)
		if not player.spent_swing and zone.intersects(enemy_bounds):
			var punishing := enemy.state == &"recovery"
			var interrupted: bool = enemy.state == &"windup" or enemy.state == &"active"
			player.spent_swing = true
			counts.hit += 1
			hit_distance += absf(player.position.x - enemy.position.x)
			if punishing:
				counts.punish += 1
			if interrupted:
				counts.interrupt += 1
			apply_damage(enemy, int(player.swing.damage), player.position.x, enemy_bounds, zone.intersection(enemy_bounds).get_center(), "hit", player.swing.interrupts)
			message = "打断敌人攻击" if interrupted else ("抓住后摇 · 反击命中" if punishing else "命中")
	if enemy.state != &"active":
		return
	var zone := hit_rect(enemy.position, enemy.facing, enemy.swing.reach)
	if not enemy_struck_ball and ball != null and ball.intersects(zone, ThrowBall.RADIUS):
		ball.deflect(enemy, enemy.facing, true)
		enemy_struck_ball = true
		message = "敌人击球 · 爆炸将攻击玩家"
	var player_bounds := hurt_rect(player.position, Player.BODY)
	if enemy.spent_swing or not zone.intersects(player_bounds):
		return
	if player.invulnerable():
		if not enemy_evaded:
			enemy_evaded = true
			counts.dodge += 1
			message = "翻滚避伤 · 观察敌人后摇"
			play_sound("dodge")
	elif apply_damage(player, 1, enemy.position.x, player_bounds, zone.intersection(player_bounds).get_center(), "hurt"):
		enemy.spent_swing = true
		counts.hurt += 1
		message = "受击 · 攻击、翻滚和站位时机都可以复盘"

func apply_damage(target: CharacterBody2D, damage: int, source_x: float, bounds: Rect2, contact: Vector2, sound: String, extended_hitstun := false) -> bool:
	var direction := 1.0 if target.position.x >= source_x else -1.0
	var impulse: float = direction * feedback_values.knockback_speed if options.knockback else 0.0
	var brake: float = feedback_values.knockback_brake if options.knockback else Tuning.FEEDBACK.knockback_brake
	if target == player:
		if not player.receive_hit(impulse, brake):
			return false
	else:
		damage = mini(enemy.hp, damage)
		if damage <= 0:
			return false
		enemy.receive_hit(damage, extended_hitstun, impulse, brake)
	feedback.cancel_slash(target)
	play_sound(sound)
	if options.freeze:
		freeze = maxf(freeze, feedback_values.stop_time)
	feedback.add_hit(target, bounds, contact, direction, damage)
	return true

func on_player_action(action: StringName, buffered: bool) -> void:
	counts[action] += 1
	if buffered:
		counts.buffered += 1
	if action != &"attack":
		return
	player_struck_ball = false
	if enemy.state == &"windup":
		counts.early += 1
	elif enemy.state == &"recovery":
		counts.late += 1

func on_player_attack_active() -> void:
	feedback.add_slash(player, player.facing, player.swing.reach, arm_index() == 1, ArenaView.TEAL)

func on_enemy_phase(phase: StringName) -> void:
	if phase == &"windup":
		enemy_evaded = false
		play_sound("warn")
	elif phase == &"active":
		enemy_struck_ball = false
		counts.enemy_attack += 1
		feedback.add_slash(enemy, enemy.facing, enemy.swing.reach, false, ArenaView.RED)
	elif phase == &"recovery" and not enemy.spent_swing and not enemy_evaded:
		counts.spacing += 1
		message = "拉开或绕出攻击范围 · 敌人进入后摇"

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

func change_parameter(group: String, key: String, value: Variant) -> void:
	match group:
		"motion":
			motion[profile_id][key] = value
		"enemy":
			enemy_data[key] = value
		"weapon":
			arms[arm_index()][key] = value
		"throw":
			throw_data[key] = value
		"feedback":
			feedback_values[key] = value
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
		snappedf(elapsed, 0.01), roundi(distance), counts.jump + counts.air_jump, counts.roll, counts.buffered,
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
	config.set_value("tuning", "throw_ball", throw_data)
	config.set_value("tuning", "feedback", options)
	config.set_value("tuning", "feedback_values", feedback_values)
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
	throw_data.merge(config.get_value("tuning", "throw_ball", {}), true)
	options.merge(config.get_value("tuning", "feedback", {}), true)
	feedback_values.merge(config.get_value("tuning", "feedback_values", {}), true)

func restore_feedback_defaults() -> void:
	options.merge(Tuning.FEEDBACK_SWITCHES, true)
	feedback_values.merge(Tuning.FEEDBACK, true)
	save_setup()
	reset_trial()
	panel.refresh()

func restore_defaults() -> void:
	motion[profile_id] = (Tuning.MOVEMENT_A if profile_id == 0 else Tuning.MOVEMENT_B).duplicate()
	if mode > 0:
		enemy_data = Tuning.ENEMY.duplicate()
		throw_data = Tuning.THROW_BALL.duplicate()
	if mode == 2:
		arms[weapon_id] = (Tuning.FAST if weapon_id == 0 else Tuning.HEAVY).duplicate()
	save_setup()
	reset_trial()
	panel.refresh()
