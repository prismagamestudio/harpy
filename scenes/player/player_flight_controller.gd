extends Node
class_name PlayerFlightController

@export_range(0.1, 1.0, 0.01) var double_tap_window: float = 0.30
@export var flight_speed: float = 9.0
@export var boost_speed: float = 15.0
@export var boost_duration: float = 0.65
@export var flight_acceleration: float = 8.0
@export var dive_speed: float = 14.0
@export var dive_acceleration: float = 16.0
@export var max_climb_pitch_degrees: float = 45.0
@export var max_dive_pitch_degrees: float = 85.0
@export_range(0.0, 1.0, 0.05) var upright_lean_scale: float = 0.3

# Se conserva por compatibilidad con el valor guardado en el Inspector.
# El dive ahora cae verticalmente y ya no usa este ajuste.
@export var dive_downward_bias: float = 1.3

## Segundos manteniendo Ctrl para comprometer el picado.
@export var dive_hold_time: float = 0.3
## Cuánto curvan A/D el picado (0..1).
@export_range(0.0, 1.0, 0.05) var dive_turn_influence: float = 0.6
## Cuánto tira hacia arriba Space durante el picado (0..1).
@export_range(0.0, 1.0, 0.05) var dive_pull_up_influence: float = 0.8

## --- Mando vertical del vuelo (más controlable) ---
## Velocidad de trepada con Space.
@export_range(2.0, 15.0, 0.5) var climb_speed: float = 6.5
## Velocidad de descenso controlado con C (antes de comprometer picado).
@export_range(1.0, 15.0, 0.5) var descend_speed: float = 6.0
## Aceleración del mando vertical (qué tan rápido obedece Space/C).
@export_range(4.0, 40.0, 0.5) var vertical_acceleration: float = 14.0
## Multiplicador de freno al INVERTIR el sentido vertical (caída -> subida).
@export_range(1.0, 6.0, 0.1) var freno_inversion: float = 3.0
## Segundos de "alerón" tras soltar el picado: frena la caída solo.
@export_range(0.0, 1.0, 0.05) var post_dive_brake_time: float = 0.45
## La cámara dirige el vuelo además de los botones: con W/avance apretado,
## mirar arriba trepa y mirar abajo pica suave (sin comprometer el dive).
@export var camara_dirige_vertical: bool = true
## Aceleración del boost: Shift "puncha" en vez de acelerar parejo.
@export_range(4.0, 40.0, 0.5) var boost_acceleration: float = 16.0
## Banking: cuánto inclina el cuerpo en los giros (grados). Si inclinara
## para AFUERA del giro, ponelo negativo.
@export_range(-45.0, 45.0, 1.0) var bank_grados: float = 24.0
## Qué tan rápido entra/sale la inclinación del giro.
@export_range(1.0, 12.0, 0.5) var bank_velocidad: float = 6.0
## Multiplicador de aceleración al cambiar CONTRA la dirección actual
## (media vuelta de frente a atrás = pivote seco, sin derrape largo).
@export_range(1.0, 6.0, 0.1) var accel_cambio_direccion: float = 2.5

## Ya NO se usa en planeo (el mando vertical es velocidad objetivo fija y
## la gravedad deja de acumularse). Se conserva porque el Inspector puede
## tenerlo guardado de versiones anteriores.
@export_range(0.0, 1.0, 0.01) var glide_gravity_scale: float = 0.15
@export_range(0.5, 2.0, 0.05) var dive_gravity_scale: float = 1.2
@export var takeoff_lift: float = 4.5
## Despegue CAMINANDO: fracción del impulso (se eleva de a poco).
@export_range(0.2, 1.0, 0.05) var despegue_caminando_ratio: float = 0.65
## Despegue CORRIENDO: multiplicador del impulso (sale disparado).
@export_range(1.0, 2.0, 0.05) var despegue_corriendo_ratio: float = 1.3
## Velocidad horizontal a partir de la cual el despegue es "corriendo".
@export_range(3.0, 9.0, 0.5) var corriendo_umbral: float = 5.5
## En un giro cerrado (reversa) el cuerpo se endereza, gira y vuelve a
## horizontal. 0 = apunta siempre (antes); 0.6 = pivote legible.
@export_range(0.0, 1.0, 0.05) var endereza_en_giro: float = 0.6
## Volar PRONE (boca abajo, pecho al piso, como Falcon/Vulture). Si tu
## import tuviera la convención de ejes al revés y saliera boca arriba,
## desactivá esta perilla.
@export var volar_boca_abajo: bool = true
## Inclinación del cuerpo al crucero (grados, 0=parado 90=horizontal).
## A velocidad/boost estira hasta horizontal.
@export_range(20.0, 90.0, 5.0) var pitch_crucero_grados: float = 55.0

## --- VUELO 360 HÉROE (Superman-style): apuntás con la cámara y VAS ahí ---
## Aceleración base del vuelo (respuesta directa, sin gestión de energía).
@export_range(4.0, 30.0, 0.5) var control_aceleracion: float = 12.0
## Aceleración durante el boost (el empujón de Shift).
@export_range(4.0, 40.0, 0.5) var boost_aceleracion_heroe: float = 20.0
## Velocidad de referencia para el ratio de cámara/estelas (el tope de
## la picada aproxima el máximo de aire).
@export_range(10.0, 30.0, 0.5) var velocidad_picada_max: float = 20.0
## Al DESCENDER con direccion: grados EXTRA de estiramiento hacia la
## picada segun cuanto miras abajo (cuadratico: bajada leve suma poco).
@export_range(0.0, 45.0, 1.0) var pitch_descenso_extra_grados: float = 20.0
## Velocidad del giro visual hacia la direccion de vuelo.
@export var steering_turn_speed: float = 8.0
## --- Flote ---
@export_range(0.0, 0.5, 0.01) var hover_bob_amplitude: float = 0.12
@export_range(0.1, 4.0, 0.1) var hover_bob_frequency: float = 1.5
@export_range(0.0, 1.0, 0.01) var hover_velocity_threshold: float = 0.35
@export_range(0.1, 5.0, 0.1) var hover_return_speed: float = 1.0

var is_flying: bool = false
var is_diving: bool = false

## Modo de vuelo actual (para animaciones): flote/subida/avance/bajada/dive.
var _modo_vuelo: StringName = &"flote"
## Fracción de flight_speed a partir de la cual se considera "avance".
@export_range(0.2, 1.0, 0.05) var umbral_avance_ratio: float = 0.55

var _boost_timer: float = 0.0

var _visual_root_rest_position: Vector3 = Vector3.ZERO
var _visual_root_rest_position_captured: bool = false
var _hover_time: float = 0.0
var _hover_offset: float = 0.0

var _dive_hold_timer: float = 0.0
var _flare_timer: float = 0.0
var _bank: float = 0.0
var _error_yaw: float = 0.0
## Velocidad de aire del carve y demanda de empuje (0..1) que comparten
## física y animación.
var _velocidad_aire: float = 0.0
var _demanda: float = 0.0

func update_flight(
	character: CharacterBody3D,
	camera_pivot: Node3D,
	visual_root: Node3D,
	gravity: float,
	delta: float
) -> bool:
	if not _visual_root_rest_position_captured:
		_visual_root_rest_position = visual_root.position
		_visual_root_rest_position_captured = true

	# F / Triángulo: activa o desactiva el vuelo.
	if Input.is_action_just_pressed("toggle_flight"):
		if is_flying:
			is_flying = false
			is_diving = false
			_dive_hold_timer = 0.0
			_velocidad_aire = 0.0
			_demanda = 0.0
			_update_hover_bob(visual_root, false, delta)
		else:
			is_flying = true
			is_diving = false
			# Despegue según cómo venga: quieto = un impulso; caminando =
			# se eleva suave; corriendo = sale disparado hacia adelante.
			var h_previo := Vector2(
				character.velocity.x,
				character.velocity.z
			).length()
			var impulso := takeoff_lift
			if h_previo > corriendo_umbral:
				impulso = takeoff_lift * despegue_corriendo_ratio
				var dir_h := Vector3(
					character.velocity.x,
					0.0,
					character.velocity.z
				).normalized()
				var empuje := h_previo * 1.2
				character.velocity.x = dir_h.x * empuje
				character.velocity.z = dir_h.z * empuje
			elif h_previo > 0.5:
				impulso = takeoff_lift * despegue_caminando_ratio
			character.velocity.y = maxf(character.velocity.y, impulso)
			_velocidad_aire = character.velocity.length()

	# Al tocar el suelo, vuelve al modo terrestre.
	if is_flying and character.is_on_floor() and character.velocity.y <= 0.0:
		is_flying = false
		is_diving = false
		_boost_timer = 0.0
		_velocidad_aire = 0.0
		_demanda = 0.0
		_reset_hover_bob(visual_root)
		return false

	if not is_flying:
		_modo_vuelo = &"flote"
		_bank = 0.0
		visual_root.rotation.z = 0.0
		_update_hover_bob(visual_root, false, delta)
		return false

	# Boost: mantener Shift en vuelo (en tierra, Shift es sprint).
	var boosting: bool = (
		Input.is_action_pressed("sprint")
		and not is_diving
	)

	# WASD dirige el vuelo siguiendo la orientación de la cámara.
	var move_input: Vector2 = Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_back"
	)

	var camera_forward: Vector3 = -camera_pivot.global_basis.z
	camera_forward = camera_forward.normalized()

	var camera_right: Vector3 = camera_pivot.global_basis.x
	camera_right.y = 0.0
	camera_right = camera_right.normalized()

	var flight_direction: Vector3 = (
		camera_right * move_input.x
		- camera_forward * move_input.y
	)

	# Espacio asciende y Ctrl desciende.
	var vertical_input: float = 0.0

	if Input.is_action_pressed("jump"):
		vertical_input += 1.0

	if Input.is_action_pressed("fly_down"):
		vertical_input -= 1.0

	flight_direction += Vector3.UP * vertical_input

	var has_flight_direction: bool = (
		flight_direction.length_squared() > 0.001
	)

	if has_flight_direction:
		flight_direction = flight_direction.normalized()

	var target_speed: float = boost_speed if boosting else flight_speed
	var acceleration: float = boost_acceleration if boosting else flight_acceleration
	var estaba_picando := is_diving

	# Dive-bomb estilo Spider-Man: mantener Ctrl compromete el picado,
	# que sigue la mirada de la cámara. Soltar Ctrl lo cancela.
	var ctrl_pressed: bool = Input.is_action_pressed("fly_down")

	if ctrl_pressed:
		if not is_diving:
			_dive_hold_timer += delta
			if _dive_hold_timer >= dive_hold_time:
				is_diving = true
	else:
		_dive_hold_timer = 0.0
		is_diving = false

	# Soltar el picado despliega el "alerón": freno fuerte de la caída.
	if estaba_picando and not is_diving:
		_flare_timer = post_dive_brake_time

	if is_diving:
		# El picado apunta hacia donde mirás; A/D curvan la caída
		# y Space tira del cuerpo hacia arriba (frenar el picado).
		flight_direction = camera_forward
		flight_direction += camera_right * move_input.x * dive_turn_influence
		flight_direction += Vector3.UP * vertical_input * dive_pull_up_influence
		flight_direction = flight_direction.normalized()
		has_flight_direction = true
		target_speed = dive_speed
		acceleration = dive_acceleration

	if is_diving:
		# El picado conserva su física propia (gravedad y techo de caída).
		character.velocity = character.velocity.move_toward(
			flight_direction * target_speed,
			acceleration * delta
		)
		character.velocity.y -= gravity * dive_gravity_scale * delta
		character.velocity.y = maxf(character.velocity.y, -dive_speed)
	else:
		# ===== VUELO 360 HÉROE =====
		# La dirección de vuelo (cámara + Space/C) es la ley: el cuerpo va
		# EXACTAMENTE ahí, a velocidad de crucero o de boost. Respuesta
		# directa, pivote asistido en la reversa, sin gestión de energía.
		var controlando: bool = (
			has_flight_direction or not is_zero_approx(vertical_input)
		)

		if not controlando:
			# FLOTE: freno suave + demanda de aleteo al máximo.
			_demanda = lerpf(_demanda, 1.0, clampf(6.0 * delta, 0.0, 1.0))
			character.velocity = character.velocity.move_toward(
				Vector3.ZERO,
				flight_acceleration * delta
			)
		else:
			# 1) Vector objetivo a fondo (la dirección ya incluye el
			#    vertical de Space/C: avanzar mirando arriba = trepar 360).
			# target_speed ya está calculado arriba (boost o crucero).
			var accel := (
				boost_aceleracion_heroe if boosting else control_aceleracion
			)

			# 2) Pivote asistido: pedir lo CONTRARIO multiplica la accel.
			if has_flight_direction:
				var objetivo_vector := flight_direction * target_speed
				var vel_actual := character.velocity
				var dir_deseada := flight_direction
				if vel_actual.length_squared() > 0.5:
					var en_contra: float = clampf(
						-vel_actual.normalized().dot(dir_deseada),
						0.0,
						1.0
					)
					accel *= lerpf(1.0, accel_cambio_direccion, en_contra)
				character.velocity = vel_actual.move_toward(
					objetivo_vector,
					accel * delta
				)

			# 3) Alerón: soltar el picado frena la caída solo.
			if _flare_timer > 0.0:
				_flare_timer -= delta
				character.velocity.y = move_toward(
					character.velocity.y,
					0.0,
					vertical_acceleration * freno_inversion * delta
				)

			# 4) Demanda de empuje (0..1) para las animaciones: trepar y
			# flote aletean; rápido y descendiendo planean.
			var d := 0.0
			var vel_rapida := (
				boosting or
				character.velocity.length() >= flight_speed * 0.95
			)
			if vertical_input > 0.0 or flight_direction.y > 0.25:
				d = 1.0
			elif flight_direction.y < -0.1:
				d = 0.0
			elif vel_rapida:
				d = 0.0
			else:
				d = clampf(
					1.25 - character.velocity.length()
						/ maxf(flight_speed, 0.1),
					0.15,
					1.0
				)
			_demanda = lerpf(_demanda, d, clampf(6.0 * delta, 0.0, 1.0))

		_velocidad_aire = character.velocity.length()


	# Orienta el visual hacia el movimiento horizontal.
	# La cápsula y el Player no se inclinan.
	var horizontal_velocity: Vector3 = Vector3(
		character.velocity.x,
		0.0,
		character.velocity.z
	)
	var horizontal_speed: float = horizontal_velocity.length()
	var turn_weight: float = clampf(
		steering_turn_speed * delta,
		0.0,
		1.0
	)

	var bank_objetivo := 0.0
	# Zona muerta de yaw: con resagos horizontales diminutos (0.1-0.4 m/s,
	# típicos tras tocar S o un pivote), el atan2 apunta para atrás y el
	# modelo "mira a la cámara". Abajo de 0.5 m/s no se toca la orientación.
	if horizontal_speed > 0.5:
		var target_yaw: float = atan2(
			-horizontal_velocity.x,
			-horizontal_velocity.z
		)
		var yaw_anterior: float = visual_root.rotation.y
		visual_root.rotation.y = lerp_angle(
			yaw_anterior,
			target_yaw,
			turn_weight
		)
		# Banking: inclina según cuánto giro falta dar (señal de curva).
		if not is_diving and bank_grados != 0.0:
			var error_yaw := wrapf(target_yaw - yaw_anterior, -PI, PI)
			_error_yaw = error_yaw
			bank_objetivo = (
				clampf(error_yaw / PI, -1.0, 1.0) * deg_to_rad(bank_grados)
			)
	elif not is_diving:
		_error_yaw = lerpf(_error_yaw, 0.0, clampf(6.0 * delta, 0.0, 1.0))
	_bank = lerpf(
		_bank,
		bank_objetivo,
		clampf(bank_velocidad * delta, 0.0, 1.0)
	)
	visual_root.rotation.z = _bank

	# Durante el dive, -PI pone la cabeza hacia el suelo (rotando adelante).
	var target_pitch: float = -PI

	if not is_diving:
		# Referencia Vulture/Falcon (MCU): el cuerpo vuela CABEZA-PRIMERO a
		# lo largo del arco de la dirección. Crucero = horizontal (90°),
		# trepada = apunta arriba, descenso = apunta abajo, flote y caída
		# libre = erguido. (0° = parado, 90° = superman, 180° = cabeza abajo.)
		var intended_horizontal_speed: float = Vector2(
			flight_direction.x,
			flight_direction.z
		).length()

		var angulo_arco: float = atan2(
			flight_direction.y,
			maxf(intended_horizontal_speed, 0.05)
		)
		# Ángulo del arco en MAGNITUD (0=parado, 90=horizontal, >90=picode).
		var pitch_mag: float = clampf(
			PI * 0.5 - angulo_arco,
			0.0,
			deg_to_rad(165.0)
		)
		# Techo de estiramiento por velocidad: a crucero va medio inclinado
		# (pitch_crucero_grados); a velocidad/boost llega a horizontal.
		var cap_pitch: float = lerpf(
			deg_to_rad(pitch_crucero_grados),
			deg_to_rad(90.0),
			clampf(
				(horizontal_speed - flight_speed)
				/ maxf(boost_speed - flight_speed, 0.1),
				0.0,
				1.0
			)
		)
		if pitch_mag < deg_to_rad(90.0):
			pitch_mag = minf(pitch_mag, cap_pitch)

		# Descender con dirección: estirarse un poco mas hacia la picada
		# segun cuánto mira abajo la direccion (cuadratico: bajada leve
		# suma apenas; mirando fuerte abajo se tira de verdad).
		if pitch_descenso_extra_grados > 0.0 and flight_direction.y < 0.0:
			var bajando: float = clampf(-flight_direction.y / 0.85, 0.0, 1.0)
			pitch_mag += deg_to_rad(pitch_descenso_extra_grados) * bajando * bajando

		# La alineación la da la velocidad horizontal REAL (sobre crucero):
		# en flote o caída lenta queda erguido con el aleteo.
		var alineacion: float = clampf(
			_velocidad_aire / maxf(flight_speed, 0.1),
			0.0,
			1.0
		)

		# Giro cerrado (reversa): el cuerpo se endereza, gira, y vuelve a
		# horizontal. El pivote se lee mejor que un giro acostado.
		var enderezar: float = (
			clampf(absf(_error_yaw) * 1.8, 0.0, 1.0) * endereza_en_giro
		)
		var pitch_final: float = lerpf(
			0.0,
			pitch_mag,
			alineacion * (1.0 - enderezar)
		)
		# Prone = rotación NEGATIVA (cara al piso); positiva = boca arriba.
		target_pitch = -pitch_final if volar_boca_abajo else pitch_final
	else:
		# Picado: el cuerpo se alinea con la dirección del dive.
		# Diagonal = superman; casi vertical = pose clásica cabeza abajo.
		var dive_horizontal: float = Vector2(
			flight_direction.x,
			flight_direction.z
		).length()
		var verticalidad := clampf(-flight_direction.y, 0.0, 1.0)
		# OJO: el pico va hacia -PI (mismo angulo que PI, pero rotando
		# hacia ADELANTE). Con +PI el lerpf cruzaba por 0 y recostaba de
		# espaldas antes de clavarse (bug del "se va de espaldas").
		target_pitch = lerpf(
			atan2(flight_direction.y, maxf(dive_horizontal, 0.05)),
			-PI,
			smoothstep(0.75, 0.98, verticalidad)
		)

	visual_root.rotation.x = lerp_angle(
		visual_root.rotation.x,
		target_pitch,
		turn_weight
	)

	# El vaivén empieza solo cuando no hay controles y el personaje
	# ya casi se detuvo en el aire.
	var has_control_input: bool = (
		move_input.length_squared() > 0.001
		or not is_zero_approx(vertical_input)
	)

	var should_hover: bool = (
		not has_control_input
		and not is_diving
		and not boosting
		and not character.is_on_floor()
		and character.velocity.length() <= hover_velocity_threshold
	)

	_update_hover_bob(visual_root, should_hover, delta)

	_actualizar_modo_vuelo(character, vertical_input, boosting)

	return true


## Publica el modo de vuelo para las animaciones.
func _actualizar_modo_vuelo(
	character: CharacterBody3D,
	vertical_input: float,
	boosting: bool
) -> void:
	if is_diving:
		_modo_vuelo = &"dive"
	elif vertical_input > 0.0:
		_modo_vuelo = &"subida"
	elif vertical_input < 0.0:
		_modo_vuelo = &"bajada"
	else:
		var h_speed := Vector2(character.velocity.x, character.velocity.z).length()
		if h_speed > flight_speed * umbral_avance_ratio or boosting:
			_modo_vuelo = &"avance"
		else:
			_modo_vuelo = &"flote"


## Demanda de empuje (0 = planeo, 1 = aleteo). Heurística del vuelo héroe:
## trepar/flote = aletear, rápido/descender = alas quietas.
func demanda_empuje() -> float:
	return _demanda


## Velocidad de aire normalizada 0..1 (sobre la velocidad de picada).
## La consume la cámara para el zoom de velocidad (que la rapidez SE SIENTA).
func ratio_velocidad() -> float:
	return clampf(_velocidad_aire / maxf(velocidad_picada_max, 0.1), 0.0, 1.0)


## Modo actual: &"flote", &"subida", &"avance", &"bajada" o &"dive".
## Lo consultan las animaciones (overlay y AnimationController).
func modo_vuelo() -> StringName:
	return _modo_vuelo


## El boost es Shift MANTENIDO en vuelo (sin timer desde el rediseño de
## controles). La cámara consulta esto para FOV/shake.
## FIX: antes miraba _boost_timer, que nadie incrementa -> siempre false.
func is_boosting() -> bool:
	return (
		is_flying
		and Input.is_action_pressed("sprint")
		and not is_diving
	)

func _update_hover_bob(
	visual_root: Node3D,
	should_hover: bool,
	delta: float
) -> void:
	if should_hover:
		_hover_time += delta
		_hover_offset = (
			sin(_hover_time * TAU * hover_bob_frequency)
			* hover_bob_amplitude
		)
	else:
		_hover_time = 0.0
		_hover_offset = move_toward(
			_hover_offset,
			0.0,
			hover_return_speed * delta
		)

	visual_root.position.y = (
		_visual_root_rest_position.y + _hover_offset
	)


func _reset_hover_bob(visual_root: Node3D) -> void:
	_hover_time = 0.0
	_hover_offset = 0.0
	visual_root.position.y = _visual_root_rest_position.y
	visual_root.rotation.z = 0.0
	_bank = 0.0
