extends Node

## La cabeza mira hacia donde apunta la cámara, con límites respecto del
## modelo VISIBLE (VisualRoot, que es el que gira con el steering).
## Al salir la cámara del rango, el control se desvanece en una
## "zona de gracia" y la cabeza vuelve a mirar al frente (pose idle).

@export var skeleton_path: NodePath = ^"../VisualRoot/AnimationLibrary_Godot_Standard/Rig/GeneralSkeleton"
@export var visual_root_path: NodePath = ^"../VisualRoot"
@export var camera_path: NodePath = ^"../CameraPivot/SpringArm3D/Camera3D"
@export var flight_controller_path: NodePath = ^"../FlightController"
@export var hueso_cabeza := "Head"
## Distancia del punto de mirada sobre el rayo de la cámara.
@export var distancia_mirada := 30.0
## Interpolación interna del LookAt al cambiar de objetivo (suavizado).
@export_range(0.0, 0.5, 0.01) var suavizado_giro := 0.2
## Eje del hueso que apunta "hacia adelante" (si mira mal, probá otros).
@export_range(0, 5) var eje_adelante := 4
## Límite de giro lateral (yaw) en grados, respecto del frente del modelo.
@export_range(10.0, 120.0, 1.0) var limite_giro := 70.0
## Límite de inclinación (pitch) en grados: arriba y abajo.
@export_range(10.0, 90.0, 1.0) var limite_inclinacion := 45.0
## Grados extra más allá del límite donde el control se desvanece suave.
@export_range(5.0, 45.0, 1.0) var margen_retorno := 20.0
## En vuelo, si la velocidad horizontal pasa de esto, la cabeza deja de seguir.
@export_range(0.0, 10.0, 0.5) var velocidad_max_hover := 2.0

@onready var _camera: Camera3D = get_node_or_null(camera_path) as Camera3D
@onready var _visual: Node3D = get_node_or_null(visual_root_path) as Node3D
@onready var _flight: PlayerFlightController = (
	get_node_or_null(flight_controller_path) as PlayerFlightController
)

var _skeleton: Skeleton3D
var _modifier: LookAtModifier3D
var _aim_point: Node3D


func _ready() -> void:
	_skeleton = get_node_or_null(skeleton_path) as Skeleton3D
	if _skeleton == null:
		push_error("HeadAim: no encontré el esqueleto. Revisá skeleton_path.")
		set_physics_process(false)
		return
	if _camera == null:
		push_error("HeadAim: revisá camera_path.")
		set_physics_process(false)
		return
	if _visual == null:
		_visual = get_parent() as Node3D

	_aim_point = Node3D.new()
	_aim_point.name = "HeadAimPoint"
	add_child(_aim_point)
	_aim_point.global_position = _camera.global_position + -_camera.global_transform.basis.z * distancia_mirada

	_modifier = LookAtModifier3D.new()
	_modifier.name = "HeadLookAt"
	_modifier.bone_name = hueso_cabeza
	_modifier.forward_axis = eje_adelante as SkeletonModifier3D.BoneAxis
	_modifier.duration = suavizado_giro
	_modifier.use_angle_limitation = true
	_modifier.primary_limit_angle = limite_giro + margen_retorno
	_modifier.secondary_limit_angle = limite_inclinacion + margen_retorno
	_skeleton.add_child(_modifier)
	_modifier.target_node = _modifier.get_path_to(_aim_point)


func _physics_process(_delta: float) -> void:
	var activo := _cabeza_activa()
	_modifier.active = activo
	if not activo:
		return

	var origen := _posicion_cabeza()
	var destino := _camera.global_position + -_camera.global_transform.basis.z * distancia_mirada
	var dir := destino - origen
	if dir.length_squared() < 0.0001:
		return

	var base := _base_visible()
	var local := base.inverse() * dir.normalized()
	var yaw := _yaw_local(local)
	var pitch := asin(clampf(local.y, -1.0, 1.0))

	# Cuánto se pasa el objetivo de los límites (0 = dentro, en radianes).
	var exceso := maxf(
		absf(yaw) - deg_to_rad(limite_giro),
		absf(pitch) - deg_to_rad(limite_inclinacion)
	)
	exceso = maxf(exceso, 0.0)

	# Influencia: 1 dentro del rango, se desvanece a 0 en la zona de gracia.
	var influencia := 1.0 - clampf(exceso / deg_to_rad(margen_retorno), 0.0, 1.0)
	influencia = smoothstep(0.0, 1.0, influencia)

	var dir_segura := _recortar_local(local)
	var dir_final := Vector3.FORWARD.slerp(dir_segura, influencia)
	_aim_point.global_position = origen + (base * dir_final) * distancia_mirada


## Base orientada del modelo visible, sin escala.
func _base_visible() -> Basis:
	if _visual != null:
		return _visual.global_transform.orthonormalized().basis
	return get_parent().global_transform.orthonormalized().basis


## La cabeza sigue la mira en tierra y en hover; no en dive ni en vuelo rápido.
func _cabeza_activa() -> bool:
	if _flight != null and _flight.is_diving:
		return false
	if _flight != null and _flight.is_flying:
		var cuerpo := get_parent() as CharacterBody3D
		if cuerpo == null:
			return false
		var velocidad_horizontal := Vector2(cuerpo.velocity.x, cuerpo.velocity.z).length()
		return velocidad_horizontal <= velocidad_max_hover
	return true


## Devuelve la posición global del hueso de la cabeza.
func _posicion_cabeza() -> Vector3:
	var idx := _skeleton.find_bone(hueso_cabeza)
	if idx >= 0:
		return _skeleton.global_transform * _skeleton.get_bone_global_pose(idx).origin
	return _skeleton.global_position + Vector3.UP


## Yaw de una dirección local respecto del frente (-Z).
func _yaw_local(local: Vector3) -> float:
	var plano := Vector3(local.x, 0.0, local.z)
	if plano.length() < 0.001:
		return 0.0
	return Vector3(0.0, 0.0, -1.0).signed_angle_to(plano.normalized(), Vector3.UP)


## Recorta una dirección local a los límites de yaw/pitch.
func _recortar_local(local: Vector3) -> Vector3:
	var plano := Vector3(local.x, 0.0, local.z)
	if plano.length() < 0.001:
		plano = Vector3(0.0, 0.0, -1.0)
	plano = plano.normalized()
	var yaw := _yaw_local(local)
	var yaw_recortado := clampf(yaw, deg_to_rad(-limite_giro), deg_to_rad(limite_giro))
	plano = plano.rotated(Vector3.UP, yaw_recortado - yaw)

	var pitch := asin(clampf(local.y, -1.0, 1.0))
	var pitch_recortado := clampf(pitch, deg_to_rad(-limite_inclinacion), deg_to_rad(limite_inclinacion))
	return plano * cos(pitch_recortado) + Vector3.UP * sin(pitch_recortado)	
