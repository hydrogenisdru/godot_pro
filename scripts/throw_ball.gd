extends CharacterBody2D

const RADIUS := 10.0
const BLAST_RADIUS := 86.0
const GRAVITY := 1050.0
const THROW_SPEED := Vector2(365.0, -235.0)
const DEFLECT_SPEED := Vector2(510.0, -158.0)

var remaining := 0.0
var fuse_time := 0.0
var targets_player := false
var ignored_body: PhysicsBody2D

func _ready() -> void:
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	var collision := CollisionShape2D.new()
	collision.shape = circle
	add_child(collision)
	collision_layer = 0
	collision_mask = 1 | 2 | 4

func launch(thrower: PhysicsBody2D, direction: float, delay: float) -> void:
	fuse_time = delay
	remaining = delay
	velocity = Vector2(direction * THROW_SPEED.x, THROW_SPEED.y)
	ignore_striker(thrower)

func deflect(striker: PhysicsBody2D, direction: float, toward_player: bool) -> void:
	targets_player = toward_player
	velocity = Vector2(direction * DEFLECT_SPEED.x, DEFLECT_SPEED.y)
	ignore_striker(striker)

func ignore_striker(striker: PhysicsBody2D) -> void:
	if ignored_body != null:
		remove_collision_exception_with(ignored_body)
	ignored_body = striker
	add_collision_exception_with(striker)

func step(delta: float, striker_bounds: Rect2) -> void:
	var move_time := minf(delta, remaining)
	remaining = maxf(0.0, remaining - delta)
	if ignored_body != null and not intersects(striker_bounds.grow(1.0), RADIUS):
		remove_collision_exception_with(ignored_body)
		ignored_body = null

	velocity.y += GRAVITY * move_time
	for bounce_index in 3:
		var motion := velocity * move_time
		if motion.is_zero_approx():
			break
		var contact := move_and_collide(motion)
		if contact == null:
			break

		var normal := contact.get_normal()
		var speed_into_surface := velocity.dot(normal)
		if speed_into_surface >= 0.0:
			break
		move_time *= contact.get_remainder().length() / motion.length()
		var tangent := velocity.slide(normal)
		var rebound := -speed_into_surface * 0.58
		if normal.y < -0.7 and rebound < 30.0:
			rebound = 0.0
		velocity = tangent * 0.88 + normal * rebound

func intersects(rect: Rect2, radius: float) -> bool:
	var nearest := position.clamp(rect.position, rect.end)
	return position.distance_squared_to(nearest) <= radius * radius
