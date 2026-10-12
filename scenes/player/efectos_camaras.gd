extends Node
## EfectosCamara — jugo de cámara SIN tocar el script del usuario:
## screen shake por trauma, golpes de FOV en eventos y FOV abierto en
## picada. Se cuelga del Player, encuentra la cámara solo y aplica sus
## efectos ENCIMA de lo que la cámara del jugador escribe cada frame
## (corre al final del frame y se auto-limpia, así que nunca pelea).
##
## Eventos AUTOMÁTICOS (por animación y velocidad, cero ediciones ajenas):
## aterrizajes duros, golpes de combo, PalmazoPush, BackFlip, picada.
## API pública para lo que venga: impacto(trauma, fov_kick).
##
## Setup: nodo Node hijo del Player con este script (nada más).

## Interruptor maestro del shake.
@export var activar_shake: bool = true
## Interruptor maestro de los golpes de FOV.
@export var activar_fov: bool = true
## Intensidad global del shake (1 = normal).
@export_range(0.0, 2.0, 0.05) var intensidad_shake: float = 1.0
## Ángulo máximo de shake (grados) con trauma al máximo.
@export_range(0.5, 10.0, 0.25) var angulos_maximos: float = 3.5
## Componente de rotación de rodillos (cámara inclinada).
@export_range(0.0, 1.0, 0.05) var rodillos: float = 0.35
## Qué tan rápido se disipa el trauma (por segundo).
@export_range(0.5, 5.0, 0.1) var decay_trauma: float = 1.8
## FOV máximo de un golpe puntual (grados).
@export_range(2.0, 25.0, 1.0) var fov_kick_max: float = 14.0
## FOV extra mientras dura la picada (C).
@export_range(0.0, 20.0, 1.0) var fov_picada: float = 8.0
## Velocidad vertical de caída (m/s) que cuenta como aterrizaje duro.
@export_range(2.0, 30.0, 0.5) var umbral_aterrizaje: float = 8.0

## Trauma actual (0..1). El shake usa trauma al cuadrado (feel de GDC).
var _trauma: float = 0.0
## Golpe de FOV puntual pendiente (decae exponencial).
var _fov_kick: float = 0.0
## FOV de picada actual (lerp).
var _fov_dive: float = 0.0
## Offset de rotación aplicado en el frame anterior (para devolverlo).
var _shake_aplicado: Basis = Basis.IDENTITY
## FOV total agregado en el frame anterior (para devolverlo).
var _fov_aplicado: float = 0.0
var _player: CharacterBody3D = null
var _flight: Node = null
var _anim_player: AnimationPlayer = null
var _clip_previo: String = ""
var _vel_previa: Vector3 = Vector3.ZERO
var _estaba_en_piso: bool = false

func _ready() -> void:
	# Corre ULTIMO en _process: su efecto va encima de la escritura
	# de la cámara del usuario en cada frame.
	process_priority = 100
	_player = get_parent() as CharacterBody3D
	call_deferred("_inicializar")

func _inicializar() -> void:
	_buscar_flight()
	_buscar_anim_player()
	print("[CamFX] Listo. Camera: ", _nombre_cam(), " | Flight: ", _nombre_flight(), " | Anim: ", _nombre_anim())

## Trauma + FOV en una llamada. API para cualquier sistema.
func impacto(trauma: float, fov_kick: float = 0.0) -> void:
	_trauma = clampf(_trauma + trauma, 0.0, 1.0)
	if fov_kick > 0.0:
		_fov_kick = clampf(_fov_kick + fov_kick, 0.0, fov_kick_max)

func _process(delta: float) -> void:
	_detectar_eventos()
	_trauma = maxf(_trauma - decay_trauma * delta, 0.0)
	_fov_kick = lerpf(_fov_kick, 0.0, clampf(6.0 * delta, 0.0, 1.0))
	var dive_activa: bool = false
	if _flight != null:
		dive_activa = bool(_flight.get("is_diving"))
	var objetivo_dive: float = 0.0
	if dive_activa and activar_fov:
		objetivo_dive = fov_picada
	_fov_dive = lerpf(_fov_dive, objetivo_dive, clampf(5.0 * delta, 0.0, 1.0))
	_aplicar()

## Detecta aterrizajes duros y arranques de clips con impacto.
func _detectar_eventos() -> void:
	# Aterrizaje duro: venía cayendo rápido y ahora toca piso.
	if _player != null:
		if _player.is_on_floor() and not _estaba_en_piso and _vel_previa.y < -umbral_aterrizaje:
			var fuerza_caida: float = clampf(-_vel_previa.y / 25.0, 0.1, 0.45)
			impacto(fuerza_caida, 3.0)
		_vel_previa = _player.velocity
		_estaba_en_piso = _player.is_on_floor()
	# Arranque de un clip "fuerte" (golpes, palmazo, backflip).
	if _anim_player != null:
		var actual: String = _anim_player.current_animation
		if actual != _clip_previo:
			_clip_previo = actual
			var limpio: String = actual
			if actual.contains("/"):
				limpio = actual.get_slice("/", 1)
			_clip_nuevo(limpio)

## Tabla clip -> (trauma, fov). Agregar acá los que quieras sentir.
func _clip_nuevo(limpio: String) -> void:
	if limpio == "PalmazoPush":
		impacto(0.5, 9.0)
	elif limpio == "Melee_Uppercut":
		impacto(0.3, 5.0)
	elif limpio == "Kick":
		impacto(0.25, 4.0)
	elif limpio == "Melee_Knee":
		impacto(0.2, 3.0)
	elif limpio == "Punch_Jab":
		impacto(0.18, 2.5)
	elif limpio == "Punch_Cross":
		impacto(0.2, 3.0)
	elif limpio == "BackFlip":
		impacto(0.4, 5.0)
	elif limpio == "PatadaGarra":
		impacto(0.3, 5.0)
	elif limpio == "Sword_Light_A" or limpio == "Sword_Light_B":
		impacto(0.15, 2.0)

## Aplica (y devuelve) shake y FOV encima de lo escrito por la cámara.
func _aplicar() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# --- FOV: devolver el prestado y aplicar el nuevo ---
	var fov_total: float = 0.0
	if activar_fov:
		fov_total = _fov_kick + _fov_dive
	cam.fov = cam.fov - _fov_aplicado + fov_total
	_fov_aplicado = fov_total
	# --- Shake: devolver el prestado y aplicar el nuevo ---
	# Todo en Basis: Transform3D no multiplica con Basis en Godot 4.7.
	var base_cam: Basis = cam.global_transform.basis
	base_cam = base_cam * _shake_aplicado.inverse()
	var nuevo := Basis.IDENTITY
	if activar_shake and _trauma > 0.0:
		var t := Time.get_ticks_msec() / 1000.0
		var cota := _trauma * _trauma * intensidad_shake
		var max_rad := deg_to_rad(angulos_maximos)
		var picado := max_rad * cota * sin(t * 11.0 + 1.3)
		var guiñada := max_rad * cota * sin(t * 14.5)
		var rodilla := max_rad * rodillos * cota * sin(t * 8.5 + 0.7)
		nuevo = Basis(Vector3.RIGHT, picado) \
			* Basis(Vector3.UP, guiñada) \
			* Basis(Vector3.BACK, rodilla)
	base_cam = base_cam * nuevo
	_shake_aplicado = nuevo
	cam.global_transform.basis = base_cam

## --- Búsquedas (a prueba de nombres, duck-typed donde hace falta) ---
func _buscar_flight() -> void:
	_flight = get_node_or_null("../FlightController")
	if _flight != null:
		return
	if _player == null:
		return
	for hijo in _player.get_children():
		if hijo.get("is_flying") != null:
			_flight = hijo
			return

func _buscar_anim_player() -> void:
	if _player == null:
		return
	_anim_player = _primer_anim_player(_player)

func _primer_anim_player(nodo: Node) -> AnimationPlayer:
	if nodo is AnimationPlayer:
		return nodo as AnimationPlayer
	for hijo in nodo.get_children():
		var r := _primer_anim_player(hijo)
		if r != null:
			return r
	return null

func _nombre_cam() -> String:
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		return String(cam.name)
	return "NO ENCONTRADA"

func _nombre_flight() -> String:
	if _flight != null:
		return String(_flight.name)
	return "NO ENCONTRADO"

func _nombre_anim() -> String:
	if _anim_player != null:
		return String(_anim_player.name)
	return "NO ENCONTRADO"
