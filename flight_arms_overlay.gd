extends Node

## Aleteo de vuelo sincronizado con el bobbing del hover (1 flote cada 1.5 s).
## - Neutro: un aleteo por ciclo de bob, fase calzada al flotado.
## - Ascenso: aleteo más rápido e intenso (como ave que gana altura).
## - Descenso: brazos congelados en pose "alas arriba" (planeo).
## Los clips de disparo (Light A/B y Rec) tienen prioridad sobre todo esto.

enum Modo { NEUTRO, ASCENSO, DESCENSO }

const CLIP_ALETEO := "UAL2Brazos/DoubleJump"

@export var flight_controller_path: NodePath = ^"../FlightController"
@export_range(0.0, 0.5, 0.01) var blend_in: float = 0.15
## Período del flote en segundos. Debe coincidir con el FlightController
## (hover_bob_frequency = 1 / periodo_bob ≈ 0.667).
@export_range(0.3, 3.0, 0.01) var periodo_bob: float = 1.5
## Cuánto se acelera el aleteo al ascender (mayor = más intenso).
@export_range(1.0, 4.0, 0.05) var intensidad_ascenso: float = 2.2
## Velocidad vertical (m/s) a partir de la cual se considera ascenso/descenso.
## El bob aporta picos de ~0.5 m/s, así que no bajar de 0.7.
@export_range(0.7, 5.0, 0.1) var umbral_vertical: float = 1.2
## Momento del clip (0..1) congelado como pose "alas arriba" al descender.
## Ajustalo en vivo hasta dar con el frame donde los brazos están más arriba.
@export_range(0.0, 1.0, 0.01) var pose_descenso: float = 0.5
## Ajuste fino de fase del aleteo respecto del bob (0..1).
@export_range(0.0, 1.0, 0.01) var fase_aleteo: float = 0.0

@onready var _flight: PlayerFlightController = (
	get_node_or_null(flight_controller_path) as PlayerFlightController
)
@onready var _cuerpo: CharacterBody3D = get_parent() as CharacterBody3D

var _overlay: AnimationPlayer
var _aviso_overlay := false
var _tiempo_vuelo := 0.0
var _modo: int = -1
var _parametros_aplicados := ""

func _physics_process(delta: float) -> void:
	_overlay = _overlay_player()
	if _overlay == null:
		return

	var volando: bool = (
		_flight != null
		and _flight.is_flying
		and not _flight.is_diving
	)
			
	if not volando:
		_overlay.speed_scale = 1.0
		if _overlay.is_playing() and _overlay.current_animation == CLIP_ALETEO:
			_overlay.stop()
		_tiempo_vuelo = 0.0
		_modo = -1
		return

	_tiempo_vuelo += delta

	var modo := _modo_actual()
	if modo != _modo:
		_modo = modo
		_parametros_aplicados = ""

	# Los disparos tienen prioridad: no tocamos el overlay mientras duran.
	if _overlay.is_playing() and _overlay.current_animation != CLIP_ALETEO:
		return

	match modo:
		Modo.NEUTRO:
			_manejar_neutro()
		Modo.ASCENSO:
			_manejar_ascenso()
		Modo.DESCENSO:
			_manejar_descenso()


func _modo_actual() -> int:
	var vy: float = _cuerpo.velocity.y if _cuerpo != null else 0.0
	if vy > umbral_vertical:
		return Modo.ASCENSO
	if vy < -umbral_vertical:
		return Modo.DESCENSO
	return Modo.NEUTRO


func _manejar_neutro() -> void:
	var firma := "neutro|%s|%s" % [str(periodo_bob), str(fase_aleteo)]
	if not _overlay.is_playing() or _firma_cambio(firma):
		_iniciar_aleteo(_calcular_velocidad(1.0), true)


func _manejar_ascenso() -> void:
	var firma := "ascenso|%s" % str(intensidad_ascenso)
	if not _overlay.is_playing() or _firma_cambio(firma):
		_iniciar_aleteo(_calcular_velocidad(intensidad_ascenso), false)


func _manejar_descenso() -> void:
	# Congelar el aleteo en la pose "alas arriba": posición fija, velocidad 0.
	_overlay.seek(pose_descenso * _duracion_clip(), true)
	_overlay.speed_scale = 0.0


func _calcular_velocidad(multiplicador: float) -> float:
	return (_duracion_clip() / periodo_bob) * multiplicador


func _iniciar_aleteo(velocidad: float, calzar_fase: bool) -> void:
	if not _overlay.has_animation(CLIP_ALETEO):
		return
	var duracion := _duracion_clip()
	if duracion <= 0.0:
		return
	_overlay.speed_scale = 1.0
	_overlay.play(CLIP_ALETEO, blend_in, velocidad)
	if calzar_fase:
		var fase_bob := fposmod(_tiempo_vuelo / periodo_bob, 1.0)
		var fase := fposmod(fase_bob + fase_aleteo, 1.0)
		_overlay.seek(fase * duracion, true)


func _duracion_clip() -> float:
	if _overlay.has_animation(CLIP_ALETEO):
		return _overlay.get_animation(CLIP_ALETEO).length
	return 1.0


func _firma_cambio(firma: String) -> bool:
	if firma == _parametros_aplicados:
		return false
	_parametros_aplicados = firma
	return true


func _overlay_player() -> AnimationPlayer:
	var overlay := get_tree().get_first_node_in_group("ual2_overlay_player") as AnimationPlayer
	if overlay == null and not _aviso_overlay:
		_aviso_overlay = true
		push_warning("FlightArmsOverlay: no encontré el overlay del UAL2 loader.")
	return overlay
