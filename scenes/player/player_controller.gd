extends CharacterBody3D

@export var move_speed: float = 5.0
@export var sprint_speed: float = 8.5
@export var acceleration: float = 18.0
@export var deceleration: float = 22.0
@export var turn_speed: float = 12.0
@export var jump_velocity: float = 4.5
@export_range(0.0, 0.3, 0.01) var jump_buffer_time: float = 0.15

@onready var camera_pivot: Node3D = $CameraPivot
@onready var visual_root: Node3D = $VisualRoot
@onready var flight_controller: PlayerFlightController = $FlightController

var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
var _jump_buffer_timer: float = 0.0
var _spawn_transform: Transform3D


func _ready() -> void:
	_spawn_transform = global_transform


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("respawn"):
		global_transform = _spawn_transform
		velocity = Vector3.ZERO
		flight_controller.is_flying = false
		flight_controller.is_diving = false

func _physics_process(delta: float) -> void:
	# Si el controlador aéreo procesa el movimiento, no ejecutamos
	# el movimiento terrestre en este frame.
	if flight_controller.update_flight(
		self,
		camera_pivot,
		visual_root,
		gravity,
		delta
	):
		_jump_buffer_timer = 0.0
		move_and_slide()
		return

	# Endereza el visual gradualmente al salir del vuelo.
	visual_root.rotation.x = lerp_angle(
		visual_root.rotation.x,
		0.0,
		clampf(turn_speed * delta, 0.0, 1.0)
	)

	# Guarda brevemente la pulsación de salto.
	var jump_pressed: bool = Input.is_action_just_pressed("jump")

	if jump_pressed:
		_jump_buffer_timer = jump_buffer_time
	else:
		_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)

	# Salto y gravedad terrestres.
	if is_on_floor():
		if jump_pressed or _jump_buffer_timer > 0.0:
			velocity.y = jump_velocity
			_jump_buffer_timer = 0.0
		else:
			velocity.y = 0.0
	else:
		velocity.y -= gravity * delta

	# Movimiento terrestre relativo a la cámara.
	var input_vector: Vector2 = Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_back"
	)


	var camera_forward: Vector3 = -camera_pivot.global_basis.z
	camera_forward.y = 0.0
	camera_forward = camera_forward.normalized()

	var camera_right: Vector3 = camera_pivot.global_basis.x
	camera_right.y = 0.0
	camera_right = camera_right.normalized()

	var move_direction: Vector3 = (
		camera_right * input_vector.x
		- camera_forward * input_vector.y
	)

	if move_direction.length_squared() > 0.001:
		move_direction = move_direction.normalized()
	else:
		move_direction = Vector3.ZERO

	var is_moving: bool = move_direction.length_squared() > 0.001

	var is_sprinting: bool = is_moving and Input.is_action_pressed("sprint")

	# Sprint: misma dirección, más velocidad.
	var velocidad_objetivo: float = sprint_speed if is_sprinting else move_speed
	var target_horizontal_velocity: Vector3 = move_direction * velocidad_objetivo
	var horizontal_velocity: Vector3 = Vector3(
		velocity.x,
		0.0,
		velocity.z
	)
	var speed_change: float = acceleration if is_moving else deceleration

	horizontal_velocity = horizontal_velocity.move_toward(
		target_horizontal_velocity,
		speed_change * delta
	)

	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z

	if is_moving and not _peleando():
		var target_yaw: float = atan2(
			-move_direction.x,
			-move_direction.z
		)
		visual_root.rotation.y = lerp_angle(
			visual_root.rotation.y,
			target_yaw,
			clampf(turn_speed * delta, 0.0, 1.0)
		)

	move_and_slide()


## Mientras GroundCombat pega o cubre, él es el dueño de la rotación del
## visual (si no, ambos scripts escriben rotation.y y el modelo oscila).
func _peleando() -> bool:
	var combate: Node = get_node_or_null("GroundCombat")
	return combate != null and combate.has_method("esta_peleando") and combate.esta_peleando()
