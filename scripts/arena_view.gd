extends Node2D

const INK := Color("#e1edf4")
const MUTED := Color("#8fa8b8")
const TEAL := Color("#69e0c3")
const GOLD := Color("#ffcf79")
const RED := Color("#ff816b")
const BLUE := Color("#89c7fd")
const PLAYER_BODY := Vector2(28, 48)
const ENEMY_BODY := Vector2(34, 52)
const PHASE_NAMES := {"windup": "前摇", "active": "有效段", "recovery": "后摇", "chase": "追击", "stagger": "硬直", "dead": "倒下"}
const PLAYER_NAMES := {"ready": "可行动", "roll": "翻滚", "hurt": "受击硬直", "dead": "倒下"}
const OBJECTIVES := [
	"对比 A/B 方案的起步、急停、空中回拉、落地缓冲和翻滚距离。",
	"观察抬手与提示音。试着走出范围、翻滚穿过或等待后摇再出手。",
	"同场地、同敌人。分别用两把武器，比较出手时机、命中距离和受击。",
]

var lab
var font: Font

func _ready() -> void:
	font = preload("res://scripts/lab_font.gd").create()

func _process(_delta: float) -> void:
	queue_redraw()

func txt(at: Vector2, caption: String, size_px := 16, color := INK) -> void:
	draw_string(font, at, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)

func centered(at: Vector2, caption: String, size_px := 14, color := INK) -> void:
	var width := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	txt(at - Vector2(width * 0.5, 0), caption, size_px, color)

func plate(rect: Rect2, fill: String, outline: String, radius: int) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(fill)
	box.border_color = Color(outline)
	box.set_border_width_all(1)
	box.set_corner_radius_all(radius)
	draw_style_box(box, rect)

func _draw() -> void:
	if lab == null or lab.player == null:
		return
	txt(Vector2(28, 53), "死亡细胞 · 战斗实验室", 32)
	txt(Vector2(29, 82), OBJECTIVES[lab.mode], 16, MUTED)
	plate(Rect2(28, 151, 868, 445), "#101c29", "#31495a", 10)
	draw_rect(Rect2(29, 208, 866, 347), Color("#101b28"))
	for x in range(66, 890, 38):
		draw_line(Vector2(x, 210), Vector2(x, 555), Color("#182838"))
	for y in range(207, 555, 29):
		draw_line(Vector2(30, y), Vector2(894, y), Color("#182838"))
	var offset := Vector2.ZERO
	if lab.shake > 0.0:
		offset = Vector2(sin(lab.shake * 194.0), cos(lab.shake * 170.0)) * lab.shake * 20.0
	draw_arena(offset)
	draw_overlay()

func draw_arena(offset: Vector2) -> void:
	var player = lab.player
	var enemy = lab.enemy
	draw_set_transform(offset)
	draw_rect(lab.FLOOR_RECT, Color("#25394b"))
	draw_line(Vector2(31, 555), Vector2(895, 555), Color("#96b0b9"), 2.0)
	for x in range(52, 885, 38):
		var long_tick := (x - 52) % 114 == 0
		draw_line(Vector2(x, 556), Vector2(x, 572 if long_tick else 565), Color("#557285"), 1.0)
	if lab.mode == 0:
		draw_rect(lab.PLATFORM, Color("#405e70"))
		draw_line(lab.PLATFORM.position, lab.PLATFORM.position + Vector2(lab.PLATFORM.size.x, 0), BLUE, 2.0)
		centered(Vector2(501, 459), "单向平台 · 127 px", 12, MUTED)
	if lab.mode > 0:
		draw_enemy_range(enemy)
		draw_player_range(player)
		draw_actor(enemy.position, enemy.facing, ENEMY_BODY, RED, enemy.flash, false, enemy.state == &"dead")
		if enemy.state == &"windup":
			var shoulder: Vector2 = enemy.position + Vector2(enemy.facing * 12, -33)
			var fist := shoulder + Vector2(enemy.facing * 11, -23)
			draw_line(shoulder, fist, GOLD, 5.0)
			draw_circle(fist, 4.0, GOLD)
	draw_actor(player.position, player.facing, PLAYER_BODY, TEAL, player.flash, player.state == &"roll", player.hp <= 0)
	if player.state == &"roll" and player.invulnerable():
		draw_arc(player.position - Vector2(0, 19), 23, 0, TAU, 22, BLUE, 2.0, true)
	if lab.options.boxes:
		draw_rect(lab.hurt_rect(player.position, PLAYER_BODY), Color(TEAL, 0.37), false)
		if lab.mode > 0 and enemy.hp > 0:
			draw_rect(lab.hurt_rect(enemy.position, ENEMY_BODY), Color(RED, 0.40), false)
	draw_set_transform(Vector2.ZERO)

func draw_enemy_range(enemy) -> void:
	if enemy.state == &"windup" or enemy.state == &"active":
		draw_range(lab.hit_rect(enemy.position, enemy.facing, enemy.swing.reach), GOLD if enemy.state == &"windup" else RED, enemy.state == &"active")
	if enemy.hp <= 0:
		return
	var tag: String = PHASE_NAMES.get(str(enemy.state), "")
	var color := GOLD if enemy.state == &"windup" else (TEAL if enemy.state == &"recovery" else INK)
	centered(enemy.position - Vector2(0, 76), ("!  " if enemy.state == &"windup" else "") + tag, 15, color)
	var timer_key: String = str(enemy.state)
	if timer_key in ["windup", "active", "recovery", "stagger"]:
		var progress: float = clampf(enemy.age / enemy.swing[timer_key], 0.0, 1.0)
		draw_rect(Rect2(enemy.position - Vector2(25, 67), Vector2(50, 4)), Color("#364859"))
		draw_rect(Rect2(enemy.position - Vector2(25, 67), Vector2(progress * 50, 4)), color)

func draw_player_range(player) -> void:
	var phase: String = player.attack_phase()
	if phase == "active" or (phase == "windup" and lab.options.boxes):
		draw_range(lab.hit_rect(player.position, player.facing, player.swing.reach), TEAL, phase == "active")

func draw_range(zone: Rect2, color: Color, active: bool) -> void:
	draw_rect(zone, Color(color, 0.24 if active else 0.10))
	if lab.options.boxes:
		draw_rect(zone, Color(color, 0.95 if active else 0.56), false, 1.5)
	elif active:
		draw_line(Vector2(zone.position.x, zone.get_center().y), Vector2(zone.end.x, zone.get_center().y - 10), Color(color, 0.74), 4.0, true)

func draw_actor(at: Vector2, direction: float, body: Vector2, color: Color, flash: float, rolling: bool, dead: bool) -> void:
	if dead:
		draw_rect(Rect2(at - Vector2(21, 14), Vector2(42, 12)), Color(color, 0.38))
		return
	draw_line(at + Vector2(-22, 0), at + Vector2(22, 0), Color("#09111c"), 5.0)
	if flash > 0.0:
		color = Color.WHITE.lerp(color, 1.0 - clampf(flash * 5.0, 0.0, 1.0))
	if rolling:
		draw_circle(at - Vector2(0, 16), 16, color)
		draw_arc(at - Vector2(0, 16), 10, -0.35, 4.5, 16, Color("#1d4350"), 3.0, true)
		return
	var top := at - Vector2(0, body.y)
	draw_rect(Rect2(top - Vector2(9, 0), Vector2(18, 15)), color)
	draw_colored_polygon(PackedVector2Array([
		top + Vector2(-body.x / 2, 16), top + Vector2(body.x / 2, 16),
		at + Vector2(body.x * 0.37, -8), at - Vector2(body.x * 0.37, 8),
	]), Color(color, 0.86))
	draw_line(at - Vector2(7, 11), at - Vector2(9, 1), color, 5.0)
	draw_line(at + Vector2(7, -11), at + Vector2(9, -1), color, 5.0)
	draw_line(top + Vector2(direction * 2, 6), top + Vector2(direction * 9, 6), Color("#0e1b29"), 3.0)
	draw_line(top + Vector2(direction * 14, 23), top + Vector2(direction * 23, 27), color, 3.0)

func draw_overlay() -> void:
	var player = lab.player
	var enemy = lab.enemy
	var mode: int = lab.mode
	var player_state: String = PHASE_NAMES.get(player.attack_phase(), PLAYER_NAMES.get(str(player.state), ""))
	txt(Vector2(45, 180), "玩家 · " + player_state, 15, TEAL)
	var status := "%s   ·   %.1f s   ·   %d px/s" % [lab.PROFILES[lab.profile_id], lab.elapsed, roundi(absf(player.velocity.x))]
	if mode > 0:
		status = "%s   ·   %.1f s" % [lab.WEAPONS[lab.arm_index()], lab.elapsed]
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
	var controls := "A / D 或 ← / →  移动       Space  跳跃       K / Shift  翻滚"
	if mode > 0:
		controls += "       J  攻击"
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
		cards = [["移动路径", "%d px" % roundi(lab.distance)], ["跳跃", counts.jump], ["翻滚", counts.roll], ["缓冲触发", counts.buffered]]
		sentence = "试法    从平台落下前按跳，再对比 A/B 能否在落地后接出下一跳。"
	else:
		cards = [["攻击 / 命中", "%d / %d" % [counts.attack, counts.hit]], ["避伤 / 受击", "%d / %d" % [counts.dodge, counts.hurt]], ["反击 / 打断", "%d / %d" % [counts.punish, counts.interrupt]], ["命中距离", "—" if counts.hit == 0 else "%d px" % roundi(lab.hit_distance / maxi(1, counts.hit))]]
		sentence = "敌人出招 %d    脱离攻击范围 %d    前摇出手 %d    后摇出手 %d" % [counts.enemy_attack, counts.spacing, counts.early, counts.late]
	for i in cards.size():
		var x := 47.0 + i * 215.0
		txt(Vector2(x, 642), cards[i][0], 14, MUTED)
		txt(Vector2(x, 675), str(cards[i][1]), 24, TEAL)
	txt(Vector2(47, 707), sentence, 13, MUTED)
