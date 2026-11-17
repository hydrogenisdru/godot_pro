extends CharacterBody2D

const BODY := Vector2(28, 48)
const GRAVITY := 1500.0
const JUMP_RELEASE_SPEED_FACTOR := 0.55
const MAX_HP := 5
const HURT_TIME := 0.24

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
var air_jump_used := false
var jump_can_be_cut := false
var roll_cooldown := 0.0
var attack_enabled := false
var spent_swing := false
var hurt_brake := 660.0

signal action_started(action: StringName, buffered: bool)
signal attack_became_active

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
	air_jump_used = false
	jump_can_be_cut = false
	roll_cooldown = 0.0
	jump_buffer = -1.0
	roll_buffer = -1.0
	attack_buffer = -1.0
	spent_swing = false
	reset_physics_interpolation()

func sample_inputs() -> void:
	if hp <= 0 or state == &"hurt":
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
	var was_attacking := attack_phase() == "active"
	age += delta
	roll_cooldown = maxf(0.0, roll_cooldown - delta)
	coyote = 0.08 if is_on_floor() else maxf(0.0, coyote - delta)
	if is_on_floor():
		velocity.y = 0.0
		air_jump_used = false
	velocity.y += GRAVITY * delta
	var axis := Input.get_axis("move_left", "move_right")

	match state:
		&"roll":
			if age >= movement.roll_time:
				state = &"ready"
				roll_cooldown = 0.13
		&"attack":
			if age >= swing.windup + swing.active + swing.recovery:
				state = &"ready"
		&"hurt":
			if age >= HURT_TIME:
				state = &"ready"

	if state == &"ready":
		if absf(axis) > 0.01:
			facing = signf(axis)
		if queued(roll_buffer) and is_on_floor() and roll_cooldown <= 0.0:
			velocity.x = facing * maxf(facing * velocity.x, movement.roll_speed)
			start_action(&"roll")
			roll_buffer = -1.0
		elif queued(attack_buffer) and attack_enabled:
			swing = weapon.duplicate()
			spent_swing = false
			start_action(&"attack")
			attack_buffer = -1.0
		elif queued(jump_buffer) and (coyote > 0.0 or not air_jump_used):
			perform_jump(coyote <= 0.0)

	if jump_can_be_cut:
		if velocity.y >= 0.0:
			jump_can_be_cut = false
		elif not Input.is_action_pressed("jump"):
			velocity.y *= JUMP_RELEASE_SPEED_FACTOR
			jump_can_be_cut = false

	var grounded := is_on_floor() and velocity.y >= 0.0
	match state:
		&"attack":
			if swing.move_factor == 0.0:
				velocity.x = 0.0
			else:
				apply_horizontal_inertia(axis, movement.speed * swing.move_factor, grounded, delta)
		&"ready":
			apply_horizontal_inertia(axis, movement.speed, grounded, delta)
		&"hurt":
			velocity.x = move_toward(velocity.x, 0.0, hurt_brake * delta)

	move_and_slide()
	if not was_attacking and attack_phase() == "active":
		attack_became_active.emit()
	jump_buffer = next_buffer(jump_buffer, delta)
	roll_buffer = next_buffer(roll_buffer, delta)
	attack_buffer = next_buffer(attack_buffer, delta)

func perform_jump(in_air: bool) -> void:
	var height: float = movement.air_jump_height if in_air else movement.jump_height
	velocity.y = -sqrt(2.0 * GRAVITY * height)
	jump_can_be_cut = true
	air_jump_used = in_air
	coyote = 0.0
	action_started.emit(&"air_jump" if in_air else &"jump", jump_buffer > 0.001)
	jump_buffer = -1.0

func apply_horizontal_inertia(axis: float, speed: float, grounded: bool, delta: float) -> void:
	var control: float = 1.0 if grounded else movement.air_control
	var deceleration: float = movement.brake if grounded else movement.air_drag
	if is_zero_approx(axis):
		velocity.x = move_toward(velocity.x, 0.0, deceleration * delta)
		return

	var target := axis * speed
	if velocity.x * axis < 0.0:
		var turn_brake: float = movement.turn_brake * control
		var time_to_stop := absf(velocity.x) / turn_brake
		velocity.x = move_toward(velocity.x, 0.0, turn_brake * delta)
		delta = maxf(0.0, delta - time_to_stop)

	var rate: float = deceleration if absf(velocity.x) > absf(target) else movement.accel * control
	velocity.x = move_toward(velocity.x, target, rate * delta)

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

func receive_hit(horizontal_impulse: float, brake: float) -> bool:
	if hp <= 0 or state == &"hurt" or invulnerable():
		return false
	hp -= 1
	state = &"hurt" if hp > 0 else &"dead"
	age = 0.0
	swing = {}
	spent_swing = true
	jump_buffer = -1.0
	roll_buffer = -1.0
	attack_buffer = -1.0
	jump_can_be_cut = false
	hurt_brake = brake
	velocity.x += horizontal_impulse
	return true
