extends Node

enum MotionState {
	GROUNDED,
	JUMP_START,
	AIRBORNE,
	LANDING
}

@export var animation_player_path: NodePath = ^"../VisualRoot/AnimationLibrary_Godot_Standard/AnimationPlayer"
@export var idle_animation: StringName = &"Idle"
@export var walk_animation: StringName = &"Walk"
@export var jump_start_animation: StringName = &"Jump_Start"
@export var jump_animation: StringName = &"Jump"
@export var jump_land_animation: StringName = &"Jump_Land"
@export_range(0.0, 1.0, 0.01) var blend_time: float = 0.2
@export var movement_threshold: float = 0.1
@export_range(0.0, 0.5, 0.01) var landing_interrupt_delay: float = 0.08
@export_range(0.0, 0.5, 0.01) var overlay_blend_time: float = 0.1
@export_range(1.0, 2.5, 0.05) var sprint_anim_speed: float = 1.4
@export var sprint_animation: StringName = &"Sprint"
## Velocidad horizontal (m/s) a partir de la cual se considera sprint.
@export_range(4.0, 12.0, 0.1) var sprint_speed_threshold: float = 6.5

@onready var _character: CharacterBody3D = get_parent() as CharacterBody3D
@onready var _animation_player: AnimationPlayer = (
	get_node_or_null(animation_player_path) as AnimationPlayer
)
@onready var _flight_controller: PlayerFlightController = (
	get_node_or_null("../FlightController") as PlayerFlightController
)

var _state: int = MotionState.GROUNDED
var _current_animation: StringName = &""
var _landing_elapsed: float = 0.0
var _was_diving: bool = false
## Vino de un dive: el aterrizaje es épico (backflip o pose de héroe).
var _aterrizaje_epico: bool = false

var _overlay_activo: bool = false
var _overlay_clip: StringName = &""

var _estado_terrestre: StringName = &"idle"

var _idle_animation_name: StringName = &""
var _walk_animation_name: StringName = &""
var _jump_start_animation_name: StringName = &""
var _jump_animation_name: StringName = &""
var _jump_land_animation_name: StringName = &""
var _sprint_animation_name: StringName = &""

func _ready() -> void:
	if _character == null:
		push_error("AnimationController debe ser hijo directo de Player.")
		return

	if _animation_player == null:
		push_error("No se encontró el AnimationPlayer. Revisá animation_player_path.")
		return

	_idle_animation_name = _find_animation(idle_animation)
	# Walk/Sprint con fallback silencioso: si pedis un clip RM que no cargo,
	# cae al in-place en vez de romper la maquina de estados.
	_walk_animation_name = _find_animation(walk_animation)
	_jump_start_animation_name = _find_animation(jump_start_animation)
	_jump_animation_name = _find_animation(jump_animation)
	_jump_land_animation_name = _find_animation(jump_land_animation)
	_sprint_animation_name = _find_animation(sprint_animation)

	if _sprint_animation_name == &"":
		# Sin clip de sprint, cae al Walk para no romper nada.
		_sprint_animation_name = _walk_animation_name

	if (
		_idle_animation_name == &""
		or _walk_animation_name == &""
		or _jump_start_animation_name == &""
		or _jump_animation_name == &""
		or _jump_land_animation_name == &""
	):
		return

	_animation_player.animation_finished.connect(_on_animation_finished)
	_play_if_changed(_idle_animation_name)


## Reproduce un clip por encima de la máquina de estados (ataques, etc.)
## hasta que termina. Mientras dura, Idle/Walk/Jump no pisan el clip.
func reproducir_overlay(clip: StringName, velocidad: float = 1.0) -> void:
	if _animation_player == null or not _animation_player.has_animation(clip):
		return
	_overlay_activo = true
	_overlay_clip = clip
	_animation_player.play(clip, overlay_blend_time)
	_animation_player.speed_scale = velocidad


func esta_en_overlay() -> bool:
	return _overlay_activo


func _physics_process(delta: float) -> void:
	if _character == null or _animation_player == null:
		return

	# Mientras dura un overlay, la máquina de estados no toca la animación.
	if _overlay_activo:
		return

	# Mientras dura el dive-bomb, reproduce Idle.
	if (
		_flight_controller != null
		and _flight_controller.is_flying
		and _flight_controller.is_diving
	):
		_state = MotionState.AIRBORNE
		_landing_elapsed = 0.0
		_was_diving = true
		_animation_player.speed_scale = 1.0
		var picado := _find_opcional(&"PosePicado")
		_play_if_changed(picado if picado != &"" else _idle_animation_name)
		return

	# Regímenes de vuelo: pose héroe al pedir empuje (superman), Planeo
	# (alas) en crucero lento, PosePicado en dive, CaidaLibre en bajada.
	if _flight_controller != null and _flight_controller.is_flying:
		_state = MotionState.AIRBORNE
		_landing_elapsed = 0.0
		_procesar_regimenes_vuelo(delta)
		return

	# Al soltar Shift, vuelve a Jump si sigue en el aire.
	if _was_diving:
		_was_diving = false
		if not _character.is_on_floor():
			_aterrizaje_epico = true
			_state = MotionState.AIRBORNE
			_play_if_changed(_jump_animation_name)

	match _state:
		MotionState.GROUNDED:
			if not _character.is_on_floor() and _character.velocity.y > 0.0:
				_state = MotionState.JUMP_START
				_play_if_changed(_jump_start_animation_name)
			elif _character.is_on_floor():
				_update_ground_animation()

		MotionState.JUMP_START:
			if _character.is_on_floor():
				_begin_landing()

		MotionState.AIRBORNE:
			if _character.is_on_floor():
				_begin_landing()

		MotionState.LANDING:
			# Un nuevo salto interrumpe inmediatamente la animación de aterrizaje.
			if not _character.is_on_floor() and _character.velocity.y > 0.0:
				_state = MotionState.JUMP_START
				_landing_elapsed = 0.0
				_play_if_changed(_jump_start_animation_name)
				return

			# Si seguimos desplazándonos, no hace falta esperar a que termine Jump_Land.
			_landing_elapsed += delta
			if (
				_character.is_on_floor()
				and _horizontal_speed() > movement_threshold
				and _landing_elapsed >= landing_interrupt_delay
			):
				_state = MotionState.GROUNDED
				_update_ground_animation()
					# Sprint: acelera la caminata; toda otra animación va a velocidad normal.
	var en_sprint: bool = (
		Input.is_action_pressed("sprint")
		and _state == MotionState.GROUNDED
		and _horizontal_speed() > movement_threshold
	)
	_animation_player.speed_scale = sprint_anim_speed if en_sprint else 1.0


## --- Regímenes de vuelo (animaciones) ---
## (El aleteo de brazos quedó fuera: vuelo héroe, puño al frente.)
## Velocidad horizontal (ratio sobre flight_speed) que despliega el planeo.
@export_range(0.5, 1.5, 0.05) var umbral_planeo_ratio: float = 0.9
## Pose congelada de alas (la genera el loader).
@export var clip_planeo: StringName = &"Planeo"

var _cooldown_regimen: float = 0.0
var _regimen_clip: StringName = &""

## FSM de vuelo por DEMANDA DE EMPUJE (el MISMO número que lee la física):
## alta (>0.65) = VueloHeroe (superman: puño al frente, piernas rectas) ·
## media (>0.3) = VueloHeroe también · baja = Planeo (alas quietas) ·
## dive = PosePicado · bajada en el lugar = CaidaLibre (brazos arriba).
## Cooldown anti-parpadeo 0.25 s.
func _procesar_regimenes_vuelo(delta: float) -> void:
	_cooldown_regimen = maxf(_cooldown_regimen - delta, 0.0)
	_animation_player.speed_scale = 1.0
	var demanda: float = _flight_controller.demanda_empuje()
	var clip := _idle_animation_name
	if _flight_controller.is_diving:
		clip = _find_opcional(&"PosePicado")
		if clip == &"":
			clip = _idle_animation_name
	elif _flight_controller.modo_vuelo() == &"bajada" and demanda <= 0.35:
		clip = _find_opcional(&"CaidaLibre")
		if clip == &"":
			clip = _idle_animation_name
	elif demanda > 0.65:
		# Trepada: superman con puño al frente.
		clip = _find_opcional(&"VueloHeroe")
		if clip == &"":
			clip = _jump_animation_name
	else:
		if demanda > 0.3:
			# Crucero con empuje: misma pose héroe.
			clip = _find_opcional(&"VueloHeroe")
			if clip == &"":
				clip = _find_opcional(&"Jump_Planeo")
				if clip == &"":
					clip = _jump_animation_name
		else:
			clip = _find_opcional(clip_planeo)
			if clip == &"":
				clip = _find_opcional(&"Jump_Planeo")
				if clip == &"":
					clip = _jump_animation_name
	var es_cambio: bool = clip != _regimen_clip
	if es_cambio and _cooldown_regimen > 0.0 and not _flight_controller.is_diving:
		return  # anti-parpadeo: el régimen aguantó unos ms más
	if es_cambio:
		_regimen_clip = clip
		_cooldown_regimen = 0.25
	_play_if_changed(clip)

func _begin_landing() -> void:
	_state = MotionState.LANDING
	_landing_elapsed = 0.0
	if _aterrizaje_epico:
		_aterrizaje_epico = false
		# Cayera picando rápido: backflip de recuperación; lento: pose de héroe.
		if _horizontal_speed() > 3.5:
			var vuelta := _find_opcional(&"BackFlip")
			if vuelta != &"":
				_play_if_changed(vuelta)
				_current_animation = vuelta
				return
	_play_if_changed(_jump_land_animation_name)


func _on_animation_finished(animation_name: StringName) -> void:
	# BackFlip del aterrizaje épico: al terminar, queda en Idle.
	if _state == MotionState.LANDING and animation_name.ends_with(&"BackFlip"):
		_current_animation = &""
		_play_if_changed(_idle_animation_name)
		return
	# Al terminar un overlay, devolvemos el control a la máquina de estados.
	if _overlay_activo and animation_name == _overlay_clip:
		_overlay_activo = false
		_overlay_clip = &""
		_current_animation = &""  # fuerza a que la base se reproduzione de nuevo
		return

	if (
		animation_name == _jump_start_animation_name
		and _state == MotionState.JUMP_START
	):
		if _character.is_on_floor():
			_state = MotionState.GROUNDED
			_update_ground_animation()
		else:
			_state = MotionState.AIRBORNE
			_play_if_changed(_jump_animation_name)
		return

	if (
		animation_name == _jump_animation_name
		and _state == MotionState.AIRBORNE
	):
		# Si Jump no está configurada en loop, la repetimos mientras siga en el aire.
		_current_animation = &""
		_play_if_changed(_jump_animation_name)
		return

	if (
		animation_name == _jump_land_animation_name
		and _state == MotionState.LANDING
	):
		_state = MotionState.GROUNDED
		_update_ground_animation()


func _update_ground_animation() -> void:
	var target_animation: StringName = _idle_animation_name
	var moviendo := _horizontal_speed() > movement_threshold
	var es_sprint := _horizontal_speed() > sprint_speed_threshold
	if moviendo:
		target_animation = _sprint_animation_name if es_sprint else _walk_animation_name

	_estado_terrestre = target_animation
	_play_if_changed(target_animation)


func _horizontal_speed() -> float:
	return Vector2(_character.velocity.x, _character.velocity.z).length()


func _play_if_changed(animation_name: StringName) -> void:
	if animation_name == _current_animation:
		return

	_animation_player.play(animation_name, blend_time)
	_current_animation = animation_name


## Como _find_animation pero silencioso: devuelve &"" si no existe
## (para clips opcionales: arranques, Jump_Planeo, etc.).
func _find_opcional(requested_name: StringName) -> StringName:
	if _animation_player.has_animation(requested_name):
		return requested_name
	var suffix: String = "/" + String(requested_name)
	for candidate in _animation_player.get_animation_list():
		if String(candidate).ends_with(suffix):
			return StringName(candidate)
	return &""


func _find_animation(requested_name: StringName) -> StringName:
	if _animation_player.has_animation(requested_name):
		return requested_name

	# También encuentra clips que Godot haya importado con un prefijo de librería.
	var suffix: String = "/" + String(requested_name)

	for candidate in _animation_player.get_animation_list():
		var candidate_text: String = String(candidate)
		if candidate_text.ends_with(suffix):
			return StringName(candidate_text)

	push_error("No se encontró la animación: " + String(requested_name))
	return &""


## Cierra el overlay ANTES de que el clip termine (guardia, cortes de combo).
## La máquina de estados retoma el control en el mismo frame.
## La usa GroundCombat para soltar la guardia y para cortar al despegar.
func terminar_overlay() -> void:
	_overlay_activo = false
	_overlay_clip = &""
	_current_animation = &""
