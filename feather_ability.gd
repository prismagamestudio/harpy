extends Node
class_name FeatherAbility

const LIB_BRAZOS := "UAL2Brazos"
const CLIP_ATAQUE_IZQ := LIB_BRAZOS + "/Sword_Light_A"
const CLIP_ATAQUE_DER := LIB_BRAZOS + "/Sword_Light_A_M"
const REC_IZQ := LIB_BRAZOS + "/Sword_Light_A_Rec"
const REC_DER := LIB_BRAZOS + "/Sword_Light_A_Rec_M"
const PROYECTIL := preload("res://scenes/projectiles/feather_projectile.tscn")

@export var camera_path: NodePath = ^"../CameraPivot/SpringArm3D/Camera3D"
@export var left_spawn_path: NodePath = ^"../VisualRoot/FeatherSpawnLeft"
@export var right_spawn_path: NodePath = ^"../VisualRoot/FeatherSpawnRight"
@export_range(0.1, 0.5, 0.01) var burst_threshold: float = 0.25
@export_range(0.05, 1.0, 0.01) var shot_interval: float = 0.18
@export var aim_distance: float = 80.0
## Override manual del lado ("izquierda" / "derecha"). Vacio = AUTO: se lee
## el lado del brazo que anima cada clip contando sus pistas de huesos.
@export var forzar_lado: String = ""

@onready var _shooter: CharacterBody3D = get_parent() as CharacterBody3D
@onready var _camera: Camera3D = (
	get_node_or_null(camera_path) as Camera3D
)
@onready var _left_spawn: Node3D = (
	get_node_or_null(left_spawn_path) as Node3D
)
@onready var _right_spawn: Node3D = (
	get_node_or_null(right_spawn_path) as Node3D
)

var _shot_cooldown: float = 0.0
var _next_left_spawn: bool = true
var _apuntando: bool = false
var _hold_time: float = 0.0
var _en_rafaga: bool = false
var _rec_pendiente: bool = false
var _ultimo_clip: String = ""
var _overlay: AnimationPlayer
var _avisos := {}


func _ready() -> void:
	if _shooter == null:
		push_error("FeatherAbility debe ser hijo directo de Player.")
		set_physics_process(false)
		return

	if _camera == null:
		push_error("FeatherAbility: revisá camera_path.")
		set_physics_process(false)
		return

	if _left_spawn == null or _right_spawn == null:
		push_error("FeatherAbility: no se encontraron los puntos de salida.")
		set_physics_process(false)
		return


## El overlay lo crea el loader por código; lo buscamos de forma perezosa
## porque puede no existir todavía cuando arranca esta Ability.
func _overlay_player() -> AnimationPlayer:
	if _overlay == null or not is_instance_valid(_overlay):
		_overlay = get_tree().get_first_node_in_group("ual2_overlay_player") as AnimationPlayer
	return _overlay


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("aim"):
		_apuntando = true
	elif event.is_action_released("aim"):
		_apuntando = false
		_hold_time = 0.0
		_en_rafaga = false
	elif event.is_action_pressed("feather_fire") and _apuntando:
		# Toque: una pluma con el clip de un brazo (alterna A/B).
		_hold_time = 0.0
		_en_rafaga = false
		_disparo_con_clip()


func _physics_process(delta: float) -> void:
	_shot_cooldown = maxf(_shot_cooldown - delta, 0.0)
	_gestionar_rec_pendiente()

	if not (_apuntando and Input.is_action_pressed("feather_fire")):
		_hold_time = 0.0
		_en_rafaga = false
		return

	if not _en_rafaga:
		# Mantenido: al superar el umbral arranca la ráfaga.
		_hold_time += delta
		if _hold_time >= burst_threshold:
			_en_rafaga = true
			_disparo_con_clip()
			_shot_cooldown = shot_interval
	elif _shot_cooldown <= 0.0:
		_disparo_con_clip()
		_shot_cooldown = shot_interval


## Dispara una pluma y reproduce el clip de brazos correspondiente en el overlay.
## La animación base (Idle/Walk/Jump) sigue reproduciéndose en el resto del cuerpo.
func _disparo_con_clip() -> void:
	var clip: String = (
		CLIP_ATAQUE_IZQ if _next_left_spawn else CLIP_ATAQUE_DER
	)
	_fire_feather()
	_ultimo_clip = clip
	_rec_pendiente = false

	var overlay := _overlay_player()
	if overlay.speed_scale == 0.0:
		overlay.speed_scale = 1.0  # si venía congelado por el descenso, reactivarlo
	if overlay != null and overlay.has_animation(clip):
		overlay.play(clip)
	elif not _avisos.has(clip):
		_avisos[clip] = true
		push_warning("FeatherAbility: no encontré " + clip + " en el overlay")

## Al dejar de disparar, cuando el clip de brazos termina encadena el Rec.
func _gestionar_rec_pendiente() -> void:
	if _rec_pendiente or _ultimo_clip.is_empty():
		return
	if _apuntando and Input.is_action_pressed("feather_fire"):
		return  # seguimos disparando, no toca recovery

	var overlay := _overlay_player()
	if overlay == null:
		return
	if overlay.is_playing():
		return  # todavía está reproduciendo el ataque

	# El ataque terminó: encadenar el Rec del último brazo usado.
	var rec: String = REC_IZQ if _ultimo_clip == CLIP_ATAQUE_IZQ else REC_DER
	_rec_pendiente = true
	if overlay.has_animation(rec):
		overlay.play(rec)

var _lado_cache := {}

## ¿El clip anima el brazo DERECHO? Se cuenta huesos Left/Right de brazo en
## SUS PISTAS: nada de suposiciones por nombre. Cacheado e informado una vez.
func _clip_anima_derecho(clip: String) -> bool:
	if _lado_cache.has(clip):
		return _lado_cache[clip]
	var derecho := 0
	var izquierdo := 0
	var overlay := _overlay_player()
	if overlay != null and overlay.has_animation(clip):
		var anim := overlay.get_animation(clip)
		for i in anim.get_track_count():
			if anim.track_get_type(i) != Animation.TYPE_ROTATION_3D:
				continue
			var np := String(anim.track_get_path(i))
			var hueso := np.substr(np.rfind(":") + 1)
			if hueso.contains("Arm") or hueso.contains("Hand"):
				if hueso.contains("Right"):
					derecho += 1
				elif hueso.contains("Left"):
					izquierdo += 1
	var es_derecho: bool = derecho >= izquierdo
	if forzar_lado == "derecha":
		es_derecho = true
	elif forzar_lado == "izquierda":
		es_derecho = false
	_lado_cache[clip] = es_derecho
	print("[Feather] %s anima brazo %s (%d R / %d L) -> proyectil sale del lado %s" % [
		clip.get_slice("/", 1),
		"DERECHO" if es_derecho else "IZQUIERDO",
		derecho,
		izquierdo,
		"derecho" if es_derecho else "izquierdo",
	])
	return es_derecho

func _fire_feather() -> void:
	var viewport_size: Vector2 = _camera.get_viewport().get_visible_rect().size
	var screen_center: Vector2 = viewport_size * 0.5

	var ray_origin: Vector3 = _camera.project_ray_origin(screen_center)
	var ray_direction: Vector3 = _camera.project_ray_normal(screen_center)
	var ray_end: Vector3 = ray_origin + ray_direction * aim_distance

	var query: PhysicsRayQueryParameters3D = (
		PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	)
	query.exclude = [_shooter.get_rid()]

	var hit: Dictionary = (
		_camera.get_world_3d().direct_space_state.intersect_ray(query)
	)

	var aim_point: Vector3 = ray_end
	if not hit.is_empty():
		aim_point = hit["position"]

	# El lado lo dicta el CLIP que se anima (no el turno): brazo animado =
	# spawn de ese lado. El turno solo alterna clip A/B.
	var clip_actual: String = _ultimo_clip if _ultimo_clip != "" else (
		CLIP_ATAQUE_IZQ if _next_left_spawn else CLIP_ATAQUE_DER
	)
	var spawn: Node3D = (
		_right_spawn if _clip_anima_derecho(clip_actual) else _left_spawn
	)
	_next_left_spawn = not _next_left_spawn

	var direction: Vector3 = aim_point - spawn.global_position
	if direction.length_squared() < 0.001:
		direction = ray_direction
	direction = direction.normalized()

	var projectile: FeatherProjectile = PROYECTIL.instantiate() as FeatherProjectile

	if projectile == null:
		push_error("La escena asignada no tiene un FeatherProjectile en la raíz.")
		return

	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		scene_root = get_tree().root

	scene_root.add_child(projectile)
	projectile.launch(
		_shooter,
		spawn.global_position,
		direction
	)
