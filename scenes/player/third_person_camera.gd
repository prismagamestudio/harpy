extends Node3D

@export_range(0.001, 0.02, 0.001) var mouse_sensitivity: float = 0.003
@export_range(1.0, 10.0, 0.1) var camera_distance: float = 4.5
@export var min_pitch_degrees: float = -85.0
@export var max_pitch_degrees: float = 85.0
@export var initial_pitch_degrees: float = -10.0

@export var ground_fov: float = 75.0
@export var flight_fov: float = 84.0
@export var boost_fov: float = 94.0
@export var dive_fov: float = 99.0
@export var camera_smoothing: float = 5.0

@export var max_bank_degrees: float = 14.0
@export var speed_zoom_out: float = 0.5
@export var flight_bob_amount: float = 0.025
@export var camera_shake_amount: float = 0.012
@export var boost_shake_bonus: float = 0.025
@export var dive_shake_bonus: float = 0.035

## Velocidad de giro con el stick derecho (grados por segundo a fondo).
@export_range(30.0, 400.0, 5.0) var pad_look_speed_degrees: float = 180.0

## --- Apuntado (OTS) ---
## Distancia de cámara al apuntar (más cerca = over-the-shoulder).
@export_range(1.0, 4.0, 0.1) var aim_distance: float = 2.4
## FOV extra del apuntado (zoom de mira; negativo acerca más el mundo).
@export_range(-15.0, 0.0, 1.0) var aim_fov_bonus: float = -5.0

@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D
@onready var character: CharacterBody3D = get_parent() as CharacterBody3D
@onready var flight_controller: PlayerFlightController = (
	get_node("../FlightController") as PlayerFlightController
)

var _pitch: float = 0.0
var _elapsed_time: float = 0.0
var _mouse_turn_strength: float = 0.0
var _base_pivot_position: Vector3


func _ready() -> void:
	spring_arm.spring_length = camera_distance
	_base_pivot_position = position

	_pitch = clampf(
		deg_to_rad(initial_pitch_degrees),
		deg_to_rad(min_pitch_degrees),
		deg_to_rad(max_pitch_degrees)
	)
	rotation.x = _pitch

	camera.make_current()
	camera.fov = ground_fov
	# CAPTURA DEL MOUSE DIFERIDA: en _ready la ventana a veces todavía no
	# puede "agarrar" el mouse (X11/Wayland) y Godot lanza "NO GRAB".
	# Al diferirlo un frame, el grab sale siempre limpio.
	_capturar_mouse.call_deferred()


func _capturar_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and event.keycode == KEY_ESCAPE
	):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return

	if (
		event is InputEventMouseButton
		and event.pressed
		and event.button_index == MOUSE_BUTTON_LEFT
	):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotation.y -= event.relative.x * mouse_sensitivity

		_pitch -= event.relative.y * mouse_sensitivity
		_pitch = clampf(
			_pitch,
			deg_to_rad(min_pitch_degrees),
			deg_to_rad(max_pitch_degrees)
		)
		rotation.x = _pitch

		# El giro reciente del mouse inclina la cámara durante el vuelo.
		_mouse_turn_strength = clampf(-event.relative.x / 28.0, -1.0, 1.0)


func _process(delta: float) -> void:
	_elapsed_time += delta
	_mouse_turn_strength = move_toward(
		_mouse_turn_strength,
		0.0,
		2.8 * delta
	)

	var pad_look: Vector2 = Input.get_vector(
		"look_left",
		"look_right",
		"look_up",
		"look_down"
	)
	if pad_look.length_squared() > 0.0025:
		var giro := deg_to_rad(pad_look_speed_degrees) * delta
		rotation.y -= pad_look.x * giro
		_pitch = clampf(
			_pitch - pad_look.y * giro,
			deg_to_rad(min_pitch_degrees),
			deg_to_rad(max_pitch_degrees)
		)
		rotation.x = _pitch

	var apuntando: bool = (
		InputMap.has_action("aim") and Input.is_action_pressed("aim")
	)

	var target_fov: float = ground_fov
	var target_distance: float = camera_distance
	var target_roll: float = 0.0
	var target_position: Vector3 = _base_pivot_position

	if apuntando:
		# Over-the-shoulder: la cámara se acerca y enfoca (los offsets
		# laterales los pone ApuntadoOTS en la Camera3D).
		target_distance = aim_distance
		target_fov += aim_fov_bonus

	if flight_controller != null and flight_controller.is_flying:
		var boosting: bool = flight_controller.is_boosting()
		var diving: bool = flight_controller.is_diving

		if diving:
			target_fov = dive_fov
		elif boosting:
			target_fov = boost_fov
		else:
			target_fov = flight_fov

		# Velocidad de AIRE del carve (0..1 hasta la picada máxima): la
		# misma señal que alimenta la demanda/animaciones. La rapidez que
		# se GANA picando se siente en el FOV, más allá del estado.
		var speed_ratio: float = flight_controller.ratio_velocidad()

		# El picar acelera y el mundo se abre: hasta +7 de FOV extra.
		target_fov += speed_ratio * 7.0
		target_distance += speed_ratio * speed_zoom_out
		target_roll = deg_to_rad(max_bank_degrees * _mouse_turn_strength)

		var shake_strength: float = camera_shake_amount * speed_ratio
		if boosting:
			shake_strength += boost_shake_bonus
		if diving:
			shake_strength += dive_shake_bonus

		var shake_frequency: float = 10.0 + speed_ratio * 8.0

		target_position.x += (
			sin(_elapsed_time * shake_frequency * 1.31)
			* shake_strength
		)
		target_position.y += (
			sin(_elapsed_time * shake_frequency)
			* shake_strength
			* 0.6
		)
		target_position.y += (
			sin(_elapsed_time * 3.5)
			* flight_bob_amount
		)

	var blend: float = 1.0 - exp(-camera_smoothing * delta)

	camera.fov = lerpf(camera.fov, target_fov, blend)
	spring_arm.spring_length = lerpf(
		spring_arm.spring_length,
		target_distance,
		blend
	)
	spring_arm.rotation.z = lerp_angle(
		spring_arm.rotation.z,
		target_roll,
		blend
	)
	position = position.lerp(target_position, blend)
