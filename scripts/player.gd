extends CharacterBody2D

const BODY := Vector2(28, 48)
const GRAVITY := 1500.0
const MAX_HP := 5

var movement: Dictionary
var weapon: Dictionary
var swing: Dictionary
var state := &"ready"
var age := 0.0
var facing := 1.0
var hp := MAX_HP
var jump_buffer := -1.0
var roll_buffer := -1.0
var attack_buffer := -1.0
var coyote := 0.0
var roll_cooldown := 0.0
var attack_enabled := false
var spent_swing := false
var flash := 0.0

signal action_started(action: StringName, buffered: bool)

func _ready() -> void:
	var shape := RectangleShape2D.new()
	shape.size = BODY
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.position.y = -BODY.y / 2.0
	add_child(collision)
	collision_mask = 1
	collision_layer = 2

func reset(at: Vector2) -> void:
	position = at
	velocity = Vector2.ZERO
	state = &"ready"
	facing = 1.0
	hp = MAX_HP
	age = 0.0
	coyote = 0.0
	roll_cooldown = 0.0
	jump_buffer = -1.0
	roll_buffer = -1.0
	attack_buffer = -1.0
	flash = 0.0
	spent_swing = false
	reset_physics_interpolation()

func sample_inputs() -> void:
	if hp <= 0:
		return
	if Input.is_action_just_pressed("jump"):
		jump_buffer = 0.0
	if Input.is_action_just_pressed("roll"):
		roll_buffer = 0.0
	if attack_enabled and Input.is_action_just_pressed("attack"):
		attack_buffer = 0.0

func step(delta: float) -> void:
	if hp <= 0:
		return
	age += delta
	flash = maxf(0.0, flash - delta)
	roll_cooldown = maxf(0.0, roll_cooldown - delta)
	coyote = 0.08 if is_on_floor() else maxf(0.0, coyote - delta)
	if is_on_floor():
		velocity.y = 0.0
	velocity.y += GRAVITY * delta
	var axis := Input.get_axis("move_left", "move_right")

	match state:
		&"roll":
			if age >= movement.roll_time:
				state = &"ready"
				roll_cooldown = 0.13
				velocity.x = clampf(velocity.x, -movement.speed, movement.speed)
		&"attack":
			if age >= swing.windup + swing.active + swing.recovery:
				state = &"ready"
		&"hurt":
			if age >= 0.24:
				state = &"ready"

	if state == &"ready":
		if absf(axis) > 0.01:
			facing = signf(axis)
		if queued(roll_buffer) and is_on_floor() and roll_cooldown <= 0.0:
			start_action(&"roll")
			roll_buffer = -1.0
		elif queued(attack_buffer) and attack_enabled:
			swing = weapon.duplicate()
			var attack_speed: float = movement.speed * swing.move_factor
			velocity.x = clampf(velocity.x, -attack_speed, attack_speed)
			spent_swing = false
			start_action(&"attack")
			attack_buffer = -1.0
		elif queued(jump_buffer) and coyote > 0.0:
			velocity.y = -sqrt(2.0 * GRAVITY * float(movement.jump_height))
			action_started.emit(&"jump", jump_buffer > 0.001)
			coyote = 0.0
			jump_buffer = -1.0

	match state:
		&"roll":
			velocity.x = facing * float(movement.roll_speed)
		&"attack":
			if swing.move_factor == 0.0:
				velocity.x = 0.0
			else:
				velocity.x = move_toward(velocity.x, axis * movement.speed * swing.move_factor, movement.accel * delta)
		&"ready":
			var rate: float = movement.accel if absf(axis) > 0.01 else movement.brake
			if not is_on_floor():
				rate *= float(movement.air_control)
			velocity.x = move_toward(velocity.x, axis * movement.speed, rate * delta)
		&"hurt":
			velocity.x = move_toward(velocity.x, 0.0, 660.0 * delta)

	move_and_slide()
	jump_buffer = next_buffer(jump_buffer, delta)
	roll_buffer = next_buffer(roll_buffer, delta)
	attack_buffer = next_buffer(attack_buffer, delta)

func queued(value: float) -> bool:
	return value >= 0.0 and value <= float(movement.buffer) + 0.0001

func next_buffer(value: float, delta: float) -> float:
	if value < 0.0 or not queued(value + delta):
		return -1.0
	return value + delta

func start_action(action: StringName) -> void:
	state = action
	age = 0.0
	var buffered := roll_buffer > 0.001 if action == &"roll" else attack_buffer > 0.001
	action_started.emit(action, buffered)

func invulnerable() -> bool:
	return state == &"roll" and age >= movement.iframe_start and age < movement.iframe_end

func attack_phase() -> String:
	if state != &"attack":
		return ""
	if age < swing.windup:
		return "windup"
	if age < swing.windup + swing.active:
		return "active"
	return "recovery"

func receive_hit(from_x: float) -> bool:
	if hp <= 0 or state == &"hurt" or invulnerable():
		return false
	hp -= 1
	state = &"hurt" if hp > 0 else &"dead"
	age = 0.0
	flash = 0.20
	velocity.x = 240.0 * (1.0 if position.x >= from_x else -1.0)
	return true
