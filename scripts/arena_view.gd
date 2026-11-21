extends Node2D

const ThrowBall = preload("res://scripts/throw_ball.gd")
const HERO_IDLE := preload("res://assets/characters/red_ninja/red_ninja_video_idle.tres")
const HERO_RUN := preload("res://assets/characters/red_ninja/red_ninja_video_run.tres")
const ENEMY_IDLE := preload("res://assets/characters/enemy_idle.png")
const IDLE_ORIGIN := Vector2(23, 56)
const IDLE_BOUNDS := Rect2(-IDLE_ORIGIN, Vector2(64, 64))
const HERO_SPRITE_SCALE := 48.0 / 93.0
const HERO_IDLE_BOUNDS := Rect2(Vector2(-88, -96) * HERO_SPRITE_SCALE, Vector2(118, 98) * HERO_SPRITE_SCALE)
const HERO_RUN_BOUNDS := Rect2(Vector2(-89, -95) * HERO_SPRITE_SCALE, Vector2(128, 97) * HERO_SPRITE_SCALE)
const HERO_RUN_LOOP_DISTANCE := 157.65
const ARENA_ZOOM := 1.0
const ARENA_FRAME := Rect2(28, 151, 868, 445)
const ARENA_WINDOW := Rect2(29, 208, 866, 387)
const GROUND_LINE := 555.0
const INK := Color("#e1edf4")
const MUTED := Color("#8fa8b8")
const TEAL := Color("#69e0c3")
const GOLD := Color("#ffcf79")
const RED := Color("#ff816b")
const BLUE := Color("#89c7fd")
const PLAYER_BODY := Vector2(28, 48)
const ENEMY_BODY := Vector2(34, 52)
const PHASE_NAMES := {"windup": "前摇", "active": "有效段", "recovery": "后摇", "chase": "追击", "stagger": "受击硬直", "dead": "倒下"}
const PLAYER_NAMES := {"ready": "可行动", "roll": "翻滚", "hurt": "受击硬直", "dead": "倒下"}
const OBJECTIVES := [
	"对比 A/B 方案的起步、松键滑行、反向制动、空中惯性和翻滚余速。",
	"观察抬手与提示音。试着走出范围、翻滚穿过或等待后摇再出手。",
	"同场地、同敌人。分别用两把武器，比较出手时机、命中距离和受击。",
]

var lab
var font: Font
var hero_idle_flash: Array[Texture2D]
var hero_run_flash: Array[Texture2D]
var enemy_flash: Texture2D
var world := Node2D.new()
var idle_time := 0.0
var idle_frame := 0
var run_phase := 0.0
var run_frame := -1

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	font = preload("res://scripts/lab_font.gd").create()
	hero_idle_flash = make_flash_frames(HERO_IDLE, &"idle")
	hero_run_flash = make_flash_frames(HERO_RUN, &"run")
	enemy_flash = make_flash_texture(ENEMY_IDLE)
	var frame := Panel.new()
	frame.position = ARENA_FRAME.position
	frame.size = ARENA_FRAME.size
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.show_behind_parent = true
	frame.add_theme_stylebox_override("panel", panel_style("#101c29", "#31495a", 10))
	add_child(frame)

	var arena_window := ColorRect.new()
	arena_window.position = ARENA_WINDOW.position - ARENA_FRAME.position
	arena_window.size = ARENA_WINDOW.size
	arena_window.color = Color("#101b28")
	arena_window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arena_window.clip_contents = true
	frame.add_child(arena_window)
	world.scale = Vector2.ONE * ARENA_ZOOM
	world.draw.connect(draw_arena)
	arena_window.add_child(world)

func make_flash_texture(texture: Texture2D) -> Texture2D:
	var pixels := texture.get_image()
	for y in pixels.get_height():
		for x in pixels.get_width():
			pixels.set_pixel(x, y, Color(Color.WHITE, pixels.get_pixel(x, y).a))
	return ImageTexture.create_from_image(pixels)

func make_flash_frames(clip: SpriteFrames, animation: StringName) -> Array[Texture2D]:
	var first_frame: AtlasTexture = clip.get_frame_texture(animation, 0)
	var flash_atlas := make_flash_texture(first_frame.atlas)
	var textures: Array[Texture2D] = []
	for frame_index in clip.get_frame_count(animation):
		var frame: AtlasTexture = clip.get_frame_texture(animation, frame_index)
		var flash := frame.duplicate() as AtlasTexture
		flash.atlas = flash_atlas
		textures.append(flash)
	return textures

func _process(delta: float) -> void:
	if lab == null or lab.player == null:
		return
	update_hero_animation(delta)
	var at: Vector2 = lab.player.position
	var half_width := ARENA_WINDOW.size.x / (2.0 * ARENA_ZOOM)
	var focus_x := at.x
	if lab.mode > 0:
		var opponent_offset: float = lab.enemy.position.x - at.x
		focus_x += clampf(opponent_offset * 0.5, -half_width * 0.5, half_width * 0.5)
	var center_x := clampf(focus_x, lab.FLOOR_RECT.position.x + half_width, lab.FLOOR_RECT.end.x - half_width)
	var ground_top: float = lab.FLOOR - (GROUND_LINE - ARENA_WINDOW.position.y) / ARENA_ZOOM
	var top := minf(ground_top, at.y - 88.0)
	world.position = (Vector2(ARENA_WINDOW.size.x * 0.5, 0) - Vector2(center_x, top) * ARENA_ZOOM).round()
	world.queue_redraw()
	queue_redraw()

func update_hero_animation(delta: float) -> void:
	var player = lab.player
	if lab.paused or lab.panel.note.has_focus() or lab.freeze > 0.0:
		return
	var grounded_ready: bool = player.state == &"ready" and player.is_on_floor()
	var speed: float = player.velocity.x
	if grounded_ready and speed * player.facing > 1.0:
		var run_count := HERO_RUN.get_frame_count(&"run")
		if run_frame >= 0:
			run_phase = fposmod(run_phase + absf(speed) * delta / HERO_RUN_LOOP_DISTANCE, 1.0)
		run_frame = mini(floori(run_phase * run_count), run_count - 1)
	else:
		run_phase = 0.0
		run_frame = -1
	if not grounded_ready or absf(speed) > 1.0:
		idle_time = 0.0
		idle_frame = 0
		return
	var count := HERO_IDLE.get_frame_count(&"idle")
	var frame_seconds := HERO_IDLE.get_frame_duration(&"idle", 0) / HERO_IDLE.get_animation_speed(&"idle")
	idle_time = fposmod(idle_time + delta, count * frame_seconds)
	idle_frame = mini(floori(idle_time / frame_seconds), count - 1)

func txt(at: Vector2, caption: String, size_px := 16, color := INK) -> void:
	draw_string(font, at, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)

func centered(at: Vector2, caption: String, size_px := 14, color := INK, canvas: CanvasItem = null) -> void:
	var width := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	var target := self if canvas == null else canvas
	target.draw_string(font, at - Vector2(width * 0.5, 0), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)

func plate(rect: Rect2, fill: String, outline: String, radius: int) -> void:
	draw_style_box(panel_style(fill, outline, radius), rect)

func panel_style(fill: String, outline: String, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(fill)
	box.border_color = Color(outline)
	box.set_border_width_all(1)
	box.set_corner_radius_all(radius)
	return box

func _draw() -> void:
	if lab == null or lab.player == null:
		return
	txt(Vector2(28, 53), "死亡细胞 · 战斗实验室", 32)
	txt(Vector2(29, 82), OBJECTIVES[lab.mode], 16, MUTED)
	draw_overlay()

func draw_arena() -> void:
	var offset := Vector2(lab.feedback.shake_offset())
	world.draw_set_transform(offset)
	for x in range(66, 890, 38):
		world.draw_line(Vector2(x, 198), Vector2(x, lab.FLOOR), Color("#182838"))
	for y in range(207, 555, 29):
		world.draw_line(Vector2(30, y), Vector2(896, y), Color("#182838"))
	var player = lab.player
	var enemy = lab.enemy
	world.draw_rect(lab.FLOOR_RECT, Color("#25394b"))
	world.draw_line(Vector2(31, 555), Vector2(895, 555), Color("#96b0b9"), 2.0)
	for x in range(52, 885, 38):
		var long_tick := (x - 52) % 114 == 0
		world.draw_line(Vector2(x, 556), Vector2(x, 572 if long_tick else 565), Color("#557285"), 1.0)
	if lab.mode == 0:
		world.draw_rect(lab.PLATFORM, Color("#405e70"))
		world.draw_line(lab.PLATFORM.position, lab.PLATFORM.position + Vector2(lab.PLATFORM.size.x, 0), BLUE, 2.0)
		centered(Vector2(501, 459), "实体平台 · 127 px", 12, MUTED, world)
	if lab.mode > 0:
		draw_enemy_range(enemy)
		draw_player_range(player)
		draw_blast()
		draw_actor(enemy.position, -enemy.facing, ENEMY_IDLE, enemy_flash, RED, lab.feedback.flash_amount(enemy), false, enemy.state == &"dead", offset)
		if enemy.state == &"windup":
			var shoulder: Vector2 = enemy.position + Vector2(enemy.facing * 12, -33)
			var fist := shoulder + Vector2(enemy.facing * 11, -23)
			world.draw_line(shoulder, fist, GOLD, 5.0)
			world.draw_circle(fist, 4.0, GOLD)
	var hero_sprite := HERO_IDLE.get_frame_texture(&"idle", idle_frame)
	var hero_flash := hero_idle_flash[idle_frame]
	var hero_bounds := HERO_IDLE_BOUNDS
	if run_frame >= 0:
		hero_sprite = HERO_RUN.get_frame_texture(&"run", run_frame)
		hero_flash = hero_run_flash[run_frame]
		hero_bounds = HERO_RUN_BOUNDS
	draw_actor(player.position, player.facing, hero_sprite, hero_flash, TEAL, lab.feedback.flash_amount(player), player.state == &"roll", player.hp <= 0, offset, hero_bounds)
	if lab.ball != null:
		draw_ball(lab.ball)
	if player.state == &"roll" and player.invulnerable():
		world.draw_arc(player.position - Vector2(0, 19), 23, 0, TAU, 22, BLUE, 2.0, true)
	if lab.options.boxes:
		world.draw_rect(lab.hurt_rect(player.position, PLAYER_BODY), Color(TEAL, 0.37), false)
		if lab.mode > 0 and enemy.hp > 0:
			world.draw_rect(lab.hurt_rect(enemy.position, ENEMY_BODY), Color(RED, 0.40), false)
	lab.feedback.draw_effects(world, font)
	world.draw_set_transform(Vector2.ZERO)

func draw_ball(ball: ThrowBall) -> void:
	var color := RED if ball.targets_player else TEAL
	world.draw_circle(ball.position, ThrowBall.RADIUS + 3.0, Color("#0e1925"))
	world.draw_circle(ball.position, ThrowBall.RADIUS, Color(color, 0.45))
	world.draw_circle(ball.position, 4.0, GOLD)
	var fraction := clampf(ball.remaining / ball.fuse_time, 0.0, 1.0)
	world.draw_arc(ball.position, ThrowBall.RADIUS + 3.0, -PI / 2, -PI / 2 + TAU * fraction, 28, color, 2.2, true)

func draw_blast() -> void:
	if lab.blast_time <= 0.0:
		return
	var center: Vector2 = lab.blast_position
	var opacity: float = clampf(lab.blast_time / 0.28, 0.0, 1.0)
	var color := RED if lab.blast_targets_player else TEAL
	world.draw_circle(center, ThrowBall.BLAST_RADIUS, Color(color, opacity * 0.22))
	world.draw_arc(center, ThrowBall.BLAST_RADIUS, 0.0, TAU, 44, Color(color, opacity), 2.0, true)

func draw_enemy_range(enemy) -> void:
	if enemy.state == &"windup" or (enemy.state == &"active" and lab.options.boxes):
		draw_range(lab.hit_rect(enemy.position, enemy.facing, enemy.swing.reach), GOLD if enemy.state == &"windup" else RED, enemy.state == &"active")
	if enemy.hp <= 0:
		return
	var tag: String = PHASE_NAMES.get(str(enemy.state), "")
	var color := GOLD if enemy.state == &"windup" else (TEAL if enemy.state == &"recovery" else INK)
	centered(enemy.position - Vector2(0, 76), ("!  " if enemy.state == &"windup" else "") + tag, 15, color, world)
	var timer_key: String = str(enemy.state)
	if timer_key in ["windup", "active", "recovery", "stagger"]:
		var duration: float = enemy.hurt_time if timer_key == "stagger" else enemy.swing[timer_key]
		var progress := clampf(enemy.age / duration, 0.0, 1.0)
		world.draw_rect(Rect2(enemy.position - Vector2(25, 67), Vector2(50, 4)), Color("#364859"))
		world.draw_rect(Rect2(enemy.position - Vector2(25, 67), Vector2(progress * 50, 4)), color)

func draw_player_range(player) -> void:
	var phase: String = player.attack_phase()
	if lab.options.boxes and (phase == "active" or phase == "windup"):
		draw_range(lab.hit_rect(player.position, player.facing, player.swing.reach), TEAL, phase == "active")

func draw_range(zone: Rect2, color: Color, active: bool) -> void:
	world.draw_rect(zone, Color(color, 0.24 if active else 0.10))
	if lab.options.boxes:
		world.draw_rect(zone, Color(color, 0.95 if active else 0.56), false, 1.5)

func draw_actor(at: Vector2, horizontal_scale: float, sprite: Texture2D, flash_texture: Texture2D, color: Color, flash: float, rolling: bool, dead: bool, offset: Vector2, bounds := IDLE_BOUNDS) -> void:
	color = color.lerp(Color.WHITE, flash)
	if dead:
		world.draw_rect(Rect2(at - Vector2(21, 14), Vector2(42, 12)), Color(color, 0.38))
		return
	world.draw_line(at + Vector2(-22, 0), at + Vector2(22, 0), Color("#09111c"), 5.0)
	if rolling:
		world.draw_circle(at - Vector2(0, 16), 16, color)
		world.draw_arc(at - Vector2(0, 16), 10, -0.35, 4.5, 16, Color("#1d4350"), 3.0, true)
		return
	world.draw_set_transform((at + offset).round(), 0.0, Vector2(horizontal_scale, 1.0))
	world.draw_texture_rect(sprite, bounds, false)
	if flash > 0.0:
		world.draw_texture_rect(flash_texture, bounds, false, Color(Color.WHITE, flash))
	world.draw_set_transform(offset)

func draw_overlay() -> void:
	var player = lab.player
	var enemy = lab.enemy
	var mode: int = lab.mode
	var player_state: String = PHASE_NAMES.get(player.attack_phase(), PLAYER_NAMES.get(str(player.state), ""))
	txt(Vector2(45, 180), "玩家 · " + player_state, 15, TEAL)
	var status := "%s   ·   %.1f s   ·   横向速度 %+d px/s" % [lab.PROFILES[lab.profile_id], lab.elapsed, roundi(player.velocity.x)]
	if mode > 0:
		status = "%s   ·   %.1f s" % [lab.WEAPONS[lab.arm_index()], lab.elapsed]
		if lab.ball != null:
			status += "    ·    爆炸 %.1f s · %s" % [lab.ball.remaining, "目标：玩家" if lab.ball.targets_player else "目标：敌人"]
		hp_meter(Vector2(47, 191), player.hp, player.MAX_HP, TEAL)
		txt(Vector2(690, 180), "近战敌人", 15, RED)
		hp_meter(Vector2(692, 191), enemy.hp, enemy.MAX_HP, RED)
	centered(Vector2(467, 180), status, 14, MUTED)
	if lab.paused or lab.panel.note.has_focus():
		plate(Rect2(369, 318, 192, 47), "#121e2b", "#567389", 8)
		centered(Vector2(465, 348), "已暂停" if lab.paused else "正在填写备注", 19)
	var message: String = lab.message
	if not message.is_empty():
		centered(Vector2(462, 581), message, 14, GOLD)
	draw_metrics(mode)
	var controls := "A / D 或 ← / →  移动       Space / W  短按低跳，长按高跳       K / Shift  翻滚"
	if mode > 0:
		controls += "       J  攻击       L  投球"
	txt(Vector2(30, 749), controls, 15)
	var shortcut := "1–3 切换实验    R 重开    P 暂停"
	if mode == 0 or mode == 2:
		shortcut += "    Tab " + ("切换手感方案" if mode == 0 else "切换武器")
	txt(Vector2(30, 774), shortcut, 14, MUTED)

func hp_meter(at: Vector2, hp: int, limit: int, color: Color) -> void:
	for i in limit:
		draw_rect(Rect2(at + Vector2(i * 22, 0), Vector2(18, 5)), color if i < hp else Color("#344350"))

func draw_metrics(mode: int) -> void:
	plate(Rect2(28, 614, 868, 109), "#132332", "#31495a", 9)
	var counts: Dictionary = lab.counts
	var cards: Array
	var sentence: String
	if mode == 0:
		cards = [["移动路径", "%d px" % roundi(lab.distance)], ["一段跳 / 二段跳", "%d / %d" % [counts.jump, counts.air_jump]], ["翻滚", counts.roll], ["缓冲触发", counts.buffered]]
		sentence = "试法    比较短按和长按的跳高。空中松开再按，可以二段跳。"
	else:
		cards = [["攻击 / 命中", "%d / %d" % [counts.attack, counts.hit]], ["避伤 / 受击", "%d / %d" % [counts.dodge, counts.hurt]], ["反击 / 打断", "%d / %d" % [counts.punish, counts.interrupt]], ["命中距离", "—" if counts.hit == 0 else "%d px" % roundi(lab.hit_distance / maxi(1, counts.hit))]]
		sentence = "敌人出招 %d    脱离攻击范围 %d    前摇出手 %d    后摇出手 %d" % [counts.enemy_attack, counts.spacing, counts.early, counts.late]
	for i in cards.size():
		var x := 47.0 + i * 215.0
		txt(Vector2(x, 642), cards[i][0], 14, MUTED)
		txt(Vector2(x, 675), str(cards[i][1]), 24, TEAL)
	txt(Vector2(47, 707), sentence, 13, MUTED)
