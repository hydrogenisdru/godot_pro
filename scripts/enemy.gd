extends CharacterBody2D

const BODY := Vector2(34, 52)
const MAX_HP := 6
const HURT_TIME := 0.16

var profile: Dictionary
var swing: Dictionary
var state := &"chase"
var age := 0.0
var facing := -1.0
var hp := MAX_HP
var spent_swing := false
var hurt_time := HURT_TIME
var knockback_velocity := 0.0
var knockback_brake := 660.0

signal phase_started(phase: StringName)

func _ready() -> void:
	var shape := RectangleShape2D.new()
	shape.size = BODY
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.position.y = -BODY.y / 2.0
	add_child(collision)
	collision_layer = 4
	collision_mask = 1

func reset(at: Vector2) -> void:
	position = at
	velocity = Vector2.ZERO
	state = &"chase"
	facing = -1.0
	hp = MAX_HP
	age = 0.0
	knockback_velocity = 0.0
	spent_swing = false
	reset_physics_interpolation()

func step(delta: float, target: Vector2, ball_direction := 0.0) -> void:
	age += delta
	velocity.x = 0.0
	if is_on_floor():
		velocity.y = 0.0
	velocity.y += 1500.0 * delta
	match state:
		&"chase":
			var offset := target.x - position.x
			if absf(offset) > 1.0:
				facing = signf(offset)
			if ball_direction != 0.0 or (absf(offset) <= profile.reach - 8.0 and absf(target.y - position.y) < 55.0):
				if ball_direction != 0.0:
					facing = ball_direction
				swing = profile.duplicate()
				spent_swing = false
				enter(&"windup")
			else:
				velocity.x = facing * float(profile.speed)
		&"windup":
			if age >= swing.windup:
				enter(&"active")
		&"active":
			if age >= swing.active:
				enter(&"recovery")
		&"recovery":
			if age >= swing.recovery:
				enter(&"chase")
		&"stagger":
			if age >= hurt_time:
				enter(&"chase")
	var knocked_back := not is_zero_approx(knockback_velocity)
	if knocked_back:
		velocity.x = knockback_velocity
	move_and_slide()
	if knocked_back:
		knockback_velocity = move_toward(velocity.x, 0.0, knockback_brake * delta)

func enter(next: StringName) -> void:
	state = next
	age = 0.0
	phase_started.emit(next)

func receive_hit(damage: int, extended_hitstun: bool, horizontal_impulse: float, brake: float) -> void:
	hp = maxi(0, hp - damage)
	swing = {}
	spent_swing = true
	knockback_velocity += horizontal_impulse
	knockback_brake = brake
	if hp == 0:
		enter(&"dead")
	else:
		var duration: float = profile.stagger if extended_hitstun else HURT_TIME
		var remaining := maxf(0.0, hurt_time - age) if state == &"stagger" else 0.0
		hurt_time = maxf(duration, remaining)
		enter(&"stagger")
