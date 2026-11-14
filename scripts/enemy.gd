extends CharacterBody2D

const BODY := Vector2(34, 52)
const MAX_HP := 6

var profile: Dictionary
var swing: Dictionary
var state := &"chase"
var age := 0.0
var facing := -1.0
var hp := MAX_HP
var spent_swing := false
var flash := 0.0

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
	flash = 0.0
	spent_swing = false
	reset_physics_interpolation()

func step(delta: float, target: Vector2) -> void:
	age += delta
	flash = maxf(0.0, flash - delta)
	velocity.x = 0.0
	if is_on_floor():
		velocity.y = 0.0
	velocity.y += 1500.0 * delta
	match state:
		&"chase":
			var offset := target.x - position.x
			if absf(offset) > 1.0:
				facing = signf(offset)
			if absf(offset) <= profile.reach - 8.0 and absf(target.y - position.y) < 55.0:
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
			if age >= swing.stagger:
				enter(&"chase")
	move_and_slide()

func enter(next: StringName) -> void:
	state = next
	age = 0.0
	phase_started.emit(next)

func receive_hit(damage: int, interrupts: bool) -> void:
	hp = maxi(0, hp - damage)
	flash = 0.18
	if hp == 0:
		enter(&"dead")
	elif interrupts and state == &"windup":
		enter(&"stagger")
