extends Node
## PalmazoViento — el héroe junta las palmas y suelta una RÁFAGA DIRECCIONAL:
## un cono de viento hacia donde mirás (con pitch, como las plumas) que
## empuja maniquíes y objetos (y les pega un poquito). Es el aleteo
## convertido en arma: poca culpa, mucho empuje.
##
## Gesto: clip "PalmazoPush" (secuencia Push_Enter -> Push -> Push_Exit de
## UAL1, recortada a torso+brazos por el loader) reproducido por el
## AnimationController, a la velocidad del efecto.
##
## Setup: nodo Node hijo del Player con este script + acción "palmazo"
## en el Input Map (tecla V).

@export var accion: String = "palmazo"
## Segundos entre ráfagas.
@export_range(0.5, 5.0, 0.1) var cooldown: float = 2.5
## Alcance de la ráfaga (metros, desde el pecho).
@export_range(1.5, 10.0, 0.1) var radio: float = 4.5
## Semiángulo del cono (grados): 35 = cono total de 70.
@export_range(5.0, 89.0, 1.0) var apertura_grados: float = 35.0
## Daño directo a maniquíes (el empuje es lo principal).
@export_range(0.0, 30.0) var dano: float = 8.0
## Fuerza del empuje (semántica de cambio de velocidad en props).
@export_range(1.0, 25.0) var fuerza: float = 11.0
## Cuánto LEVANTA la ráfaga (0 = solo horizontal, 1 = casi vertical).
## Se aplica a props Y a maniquíes (inclina la dirección del golpe).
@export_range(0.0, 1.0, 0.05) var empuje_hacia_arriba: float = 0.6
## Gesto con los clips Push de UAL1 (torso+brazos via overlay).
@export var gesto_push: bool = true
## Velocidad del gesto (acorde a la ráfaga: entra y empuja rápido).
@export_range(0.5, 4.0, 0.1) var velocidad_gesto: float = 2.5
## Clip de repuesto si el loader no armo PalmazoPush ("" = sin gesto).
@export var clip_gesto_fallback: StringName = &"Sword_Light_A"
## Color de la onda expansiva.
@export var color_onda: Color = Color(0.75, 0.9, 1.0, 0.55)

var _cd: float = 0.0

@onready var _player: CharacterBody3D = get_parent() as CharacterBody3D

func _physics_process(delta: float) -> void:
	_cd = maxf(_cd - delta, 0.0)
	if _cd > 0.0 or _player == null:
		return
	if not Input.is_action_just_pressed(accion):
		return
	_cd = cooldown
	_palmazo()

func _palmazo() -> void:
	var dir := _direccion()
	var origen := _player.global_position + Vector3.UP * 1.2
	_gesto()
	_rafaga(dir, origen)
	_onda(dir, origen)

## Dirección de la ráfaga: EXACTAMENTE adonde mira la cámara (con pitch:
## mirás al piso, la ráfaga va al piso; mirás arriba, barre el cielo).
func _direccion() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var d := -cam.global_transform.basis.z
		if d.length_squared() > 0.001:
			return d.normalized()
	if _player != null:
		return -_player.global_transform.basis.z
	return Vector3.FORWARD

## Gesto de brazos: PalmazoPush (armado por el loader) por el mismo
## canal que el melee; repuesto con un clip de golpe si no esta.
func _gesto() -> void:
	if _player == null:
		return
	var ctrl := _player.get_node_or_null("AnimationController")
	if ctrl == null or not ctrl.has_method("reproducir_overlay"):
		return
	var ap := _primer_player(_player)
	if gesto_push and ap != null and ap.has_animation(&"UAL2/PalmazoPush"):
		ctrl.reproducir_overlay(&"UAL2/PalmazoPush", velocidad_gesto)
		print("[Palmazo] Gesto: PalmazoPush")
		return
	if clip_gesto_fallback != &"":
		ctrl.reproducir_overlay(clip_gesto_fallback, velocidad_gesto)
		print("[Palmazo] Gesto: repuesto ", clip_gesto_fallback)

## Primer AnimationPlayer colgando del Player (el principal del maniqui).
func _primer_player(nodo: Node) -> AnimationPlayer:
	if nodo is AnimationPlayer:
		return nodo as AnimationPlayer
	for hijo in nodo.get_children():
		var r := _primer_player(hijo)
		if r != null:
			return r
	return null

## Cono de empuje DIRECCIONAL (3D): todo lo que esté dentro del cono que
## nace en el pecho y apunta a donde mirás sale volando hacia allá.
func _rafaga(dir: Vector3, origen: Vector3) -> void:
	var cos_ap := cos(deg_to_rad(apertura_grados))
	var vistas := {}
	for grupo in ["maniqui", "agarrables"]:
		for nodo in get_tree().get_nodes_in_group(grupo):
			var cuerpo := nodo as Node3D
			if cuerpo == null or vistas.has(cuerpo.get_instance_id()):
				continue
			vistas[cuerpo.get_instance_id()] = true
			var hacia := cuerpo.global_position - origen
			if hacia.length() > radio:
				continue
			if hacia.length_squared() > 0.001 and hacia.normalized().dot(dir) < cos_ap:
				continue
			var dir_empuje := hacia.normalized() if hacia.length_squared() > 0.001 else dir
			_empujar(cuerpo, dir_empuje)
			print("[Palmazo] Ráfaga pega a ", cuerpo.name)

func _empujar(cuerpo: Node3D, dir_empuje: Vector3) -> void:
	var rb := cuerpo as RigidBody3D
	if rb == null:
		return
	if cuerpo.has_method("recibir_golpe"):
		# El maniquí aplica su propio knockback + daño + etiqueta; la
		# dirección inclinada hacia arriba le suma la elevación.
		var inclinada := (dir_empuje + Vector3.UP * empuje_hacia_arriba).normalized()
		cuerpo.recibir_golpe(dano, inclinada, fuerza)
		return
	# Prop genérico: impulso proporcional a la masa (mismo arranque).
	rb.apply_central_impulse((dir_empuje + Vector3.UP * empuje_hacia_arriba) * fuerza * rb.mass)

## Onda expansiva: anillo que nace en el pecho, mirando a donde mirás,
## crece y se desvanece.
func _onda(dir: Vector3, origen: Vector3) -> void:
	var anillo := MeshInstance3D.new()
	var malla := TorusMesh.new()
	malla.inner_radius = radio * 0.55
	malla.outer_radius = radio * 0.62
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color_onda
	malla.material = mat
	anillo.mesh = malla
	get_tree().current_scene.add_child(anillo)
	anillo.global_position = origen + dir * 1.6
	anillo.look_at(anillo.global_position + dir, Vector3.UP)
	anillo.rotate_object_local(Vector3(1.0, 0.0, 0.0), PI / 2.0)
	anillo.scale = Vector3.ONE * 0.12
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(anillo, "scale", Vector3.ONE, 0.26) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.3)
	tw.chain().tween_callback(anillo.queue_free)
