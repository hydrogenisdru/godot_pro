extends RefCounted

class HitEffect:
	var actor: CharacterBody2D
	var contact: Vector2
	var number_origin: Vector2
	var direction: float
	var damage: int
	var age := 0.0
	var lifetime := 0.0
	var particles := PackedVector2Array()

class SlashEffect:
	var attacker: CharacterBody2D
	var origin: Vector2
	var facing: float
	var reach: float
	var heavy: bool
	var color: Color
	var age := 0.0

var settings: Dictionary
var enabled: Dictionary
var hits: Array[HitEffect] = []
var slashes: Array[SlashEffect] = []
var shake_age := INF
var shake_direction := 1.0

func _init(values: Dictionary, switches: Dictionary) -> void:
	settings = values
	enabled = switches

func clear() -> void:
	hits.clear()
	slashes.clear()
	shake_age = INF

func step(delta: float) -> void:
	shake_age += delta
	for index in range(hits.size() - 1, -1, -1):
		var hit := hits[index]
		hit.age += delta
		if hit.age >= hit.lifetime:
			hits.remove_at(index)
	for index in range(slashes.size() - 1, -1, -1):
		var slash := slashes[index]
		slash.age += delta
		if slash.age >= settings.slash_time:
			slashes.remove_at(index)

func add_hit(actor: CharacterBody2D, bounds: Rect2, contact: Vector2, direction: float, damage: int) -> void:
	if enabled.shake:
		shake_age = 0.0
		shake_direction = direction
	var hit := HitEffect.new()
	hit.actor = actor
	hit.contact = contact
	hit.number_origin = Vector2(bounds.get_center().x, bounds.position.y - 10.0)
	hit.direction = direction
	hit.damage = damage
	for duration in [["flash", "flash_time"], ["spark", "spark_time"], ["particles", "particle_time"], ["damage_number", "number_time"]]:
		if enabled[duration[0]]:
			hit.lifetime = maxf(hit.lifetime, settings[duration[1]])
	if hit.lifetime <= 0.0:
		return
	if enabled.particles:
		var count := int(settings.particle_count)
		var spread := deg_to_rad(settings.particle_spread)
		for index in count:
			var angle := lerpf(-spread * 0.5, spread * 0.5, (float(index) + 0.5) / count) - 0.2
			var speed: float = settings.particle_speed * (0.65 + float((index * 7) % 11) * 0.07)
			hit.particles.append(Vector2(cos(angle) * direction, sin(angle)) * speed)
	hits.append(hit)

func add_slash(attacker: CharacterBody2D, facing: float, reach: float, heavy: bool, color: Color) -> void:
	if not enabled.slash:
		return
	var slash := SlashEffect.new()
	slash.attacker = attacker
	slash.origin = attacker.position - Vector2(0.0, 30.0)
	slash.facing = facing
	slash.reach = reach
	slash.heavy = heavy
	slash.color = color
	slashes.append(slash)

func cancel_slash(attacker: CharacterBody2D) -> void:
	for index in range(slashes.size() - 1, -1, -1):
		if slashes[index].attacker == attacker:
			slashes.remove_at(index)

func flash_amount(actor: CharacterBody2D) -> float:
	if not enabled.flash:
		return 0.0
	for index in range(hits.size() - 1, -1, -1):
		var hit := hits[index]
		if hit.actor == actor:
			return settings.flash_strength * maxf(0.0, 1.0 - hit.age / settings.flash_time)
	return 0.0

func shake_offset() -> Vector2:
	if not enabled.shake or shake_age >= settings.shake_time:
		return Vector2.ZERO
	var phase := TAU * shake_age * float(settings.shake_frequency)
	var envelope := pow(1.0 - shake_age / float(settings.shake_time), 2.0)
	return Vector2(cos(phase) * shake_direction, sin(phase * 0.72) * 0.45) * float(settings.shake_strength) * envelope

func draw_effects(canvas: Node2D, font: Font) -> void:
	for slash in slashes:
		draw_slash(canvas, slash)
	for hit in hits:
		if enabled.particles and hit.age < settings.particle_time:
			draw_particles(canvas, hit)
		if enabled.spark and hit.age < settings.spark_time:
			draw_spark(canvas, hit)
		if enabled.damage_number and hit.age < settings.number_time:
			draw_number(canvas, font, hit)

func draw_particles(canvas: Node2D, hit: HitEffect) -> void:
	var fade := 1.0 - hit.age / float(settings.particle_time)
	for index in hit.particles.size():
		var point := hit.contact + hit.particles[index] * hit.age + Vector2(0, 260.0 * hit.age * hit.age)
		var color := Color("#ffb969") if index % 3 == 0 else Color("#f88b75")
		canvas.draw_circle(point, (1.8 + (index % 3) * 0.65) * (0.55 + fade * 0.45), Color(color, fade * 0.9), true, -1.0, true)

func draw_spark(canvas: Node2D, hit: HitEffect) -> void:
	var fade := 1.0 - hit.age / float(settings.spark_time)
	var strength: float = settings.spark_strength * fade
	var tint: Color = settings.spark_color
	var size: float = settings.spark_size * (0.8 + (1.0 - fade) * 0.5)
	for index in 6:
		var ray := Vector2.from_angle(float(index) * TAU / 6.0 + 0.22)
		var length_px := size * (1.0 if index % 3 == 0 else 0.58)
		canvas.draw_line(hit.contact + ray * 3.0, hit.contact + ray * length_px, Color(tint, tint.a * strength), 2.0, true)
	canvas.draw_circle(hit.contact, 3.0 + size * 0.10, Color(Color.WHITE, strength * tint.a), true, -1.0, true)

func draw_number(canvas: Node2D, font: Font, hit: HitEffect) -> void:
	var progress := hit.age / float(settings.number_time)
	var opacity := 1.0 - smoothstep(0.40, 1.0, progress)
	var size_px := int(settings.number_size)
	var caption := "-%d" % hit.damage
	var width := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	var baseline := hit.number_origin + Vector2(hit.direction * 10.0 * progress - width * 0.5, -settings.number_rise * ease(progress, 0.55))
	var tint := Color("#ffe5b1")
	canvas.draw_string_outline(font, baseline, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, 4, Color(Color("#111923"), opacity))
	canvas.draw_string(font, baseline, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, Color(tint, opacity))

func draw_slash(canvas: Node2D, slash: SlashEffect) -> void:
	var progress := slash.age / float(settings.slash_time)
	var opacity: float = settings.slash_opacity * (1.0 - progress)
	var width: float = settings.slash_width * (1.5 if slash.heavy else 1.0)
	var extent := 0.80 if slash.heavy else 0.62
	var arc := PackedVector2Array()
	for index in 19:
		var ratio := float(index) / 18.0
		var angle := lerpf(-extent + progress * 0.32, extent, ratio)
		var reach_factor := lerpf(0.30, 1.0, sin(PI * ratio))
		var x: float = reach_factor * slash.reach * settings.slash_length * slash.facing
		var y := sin(angle) * (33.0 if slash.heavy else 28.0)
		arc.append(slash.origin + Vector2(x, y))
	canvas.draw_polyline(arc, Color(slash.color, opacity * 0.38), width + 4.0, true)
	canvas.draw_polyline(arc, Color(slash.color.lerp(Color.WHITE, 0.62), opacity), width, true)
