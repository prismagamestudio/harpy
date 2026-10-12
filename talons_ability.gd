extends Node
## HARPY — Garras de los pies: agarre AÉREO estilo ave de rapiña.
##
## DECISIONES DE DISEÑO (aprobadas por el usuario):
##   1. SOLO se agarra VOLANDO (swoop de caza: pasás cerca, apretás G).
##   2. Cargar es cosa de aire: AL ATERRIZAR se suelta solo.
##   3. LANZAR = patada procedural propia (clip "PatadaGarra" generado por
##      el loader sobre los huesos de las piernas; SIN clips humanos).
##   Sin animación de agarre: la presa "vuela" a las garras (snap de ave).
##
## CONTROLES:
##   grab (E / G / D-pad der) en el aire, cerca de un agarrable: AGARRAR
##   grab otra vez            : soltar (queda cayendo suave)
##   feather_fire (LMB) SIN apuntar, cargando: PATADA + lanzamiento
##   aterrizar                : se suelta solo
##
## SETUP EN LA ESCENA:
##   - Nodo hijo del Player "TalonsAbility" con este script.
##   - Bajo VisualRoot: Marker3D "GarraSpawn" = punto donde cuelga la presa
##     (sugerencia (0, -0.3, 0.15): bajo los pies, apenas adelante).
##     Sin marker, la presa cuelga del origen del Player (calibrable igual).
##   - Objetos: RigidBody3D en el grupo "agarrables" (cajas de prueba).
##   - Acción del Input Map: "grab" (G + botón pad 14).
##
## Enemigos agarrables a futuro: sumarlos al grupo "agarrables".

@export var animation_player_path: NodePath = NodePath()
@export var garra_path: NodePath = NodePath()
## Grupo que marca lo agarrable.
@export var grupo_agarrables := "agarrables"
## Radio de swoop: distancia máx. para agarrar volando (m).
@export_range(1.0, 8.0, 0.1) var radio_agarre: float = 3.2
## Velocidad de salida del lanzamiento (m/s).
@export_range(2.0, 25.0, 0.5) var fuerza_lanzamiento: float = 10.0
## Componente vertical del lanzamiento (m/s).
@export_range(0.0, 8.0, 0.25) var altura_lanzamiento: float = 2.5
## Fracción de la patada en la que la presa sale disparada.
@export_range(0.2, 0.8, 0.05) var momento_lanzamiento: float = 0.35

enum Estado { LIBRE, CARGANDO, PATANDO }

var _body: CharacterBody3D
var _anim: AnimationPlayer
var _garra: Node3D
var _controller: Node = null
var _combat: Node = null
var _cargado: RigidBody3D = null
var _estado: int = Estado.LIBRE
var _capa_respaldo: int = 1
var _avisos := {}

func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	_anim = _buscar_animation_player()
	_garra = _resolver_garra()
	_controller = get_parent().get_node_or_null("AnimationController")
	_combat = get_parent().get_node_or_null("GroundCombat")
	if _body == null or _anim == null:
		printerr("[Garras] Falta el Player (CharacterBody3D) o el AnimationPlayer.")
		return
	if _garra == null:
		_avisar("garra", "[Garras] Sin VisualRoot/GarraSpawn: la presa cuelga del origen del Player.")
	# El loader llena la biblioteca en SU _ready: informar al primer frame.
	call_deferred("_informar_estado")

func _informar_estado() -> void:
	var patada := "OK" if not _resolver_clip(&"PatadaGarra").is_empty() else "NO generada (¿loader actualizado?)"
	print("[Garras] Listo (agarre SOLO volando). PatadaGarra: ", patada)

func esta_cargando() -> bool:
	return _estado == Estado.CARGANDO

func _physics_process(_delta: float) -> void:
	if _body == null:
		return
	var hay_grab := InputMap.has_action("grab")
	match _estado:
		Estado.LIBRE:
			if hay_grab and Input.is_action_just_pressed("grab") and _puede_agarrar():
				_intentar_agarrar()
		Estado.CARGANDO:
			if _body.is_on_floor() or not _volando():
				_soltar()  # al aterrizar se suelta solo (decisión de diseño)
			elif hay_grab and Input.is_action_just_pressed("grab"):
				_soltar()
			elif _quiere_lanzar():
				_patear()
		Estado.PATANDO:
			pass  # el timer del puntapié impulsa la presa y vuelve a LIBRE

func _puede_agarrar() -> bool:
	if not _volando():
		return false  # concepto ave: solo se caza en el aire
	if _combat != null and _combat.esta_peleando():
		return false
	return true

func _quiere_lanzar() -> bool:
	if not InputMap.has_action("feather_fire") or not Input.is_action_just_pressed("feather_fire"):
		return false
	if InputMap.has_action("aim") and Input.is_action_pressed("aim"):
		return false  # apuntando = plumas, no lanzamiento
	return true

## Swoop: lo más cercano del grupo agarrables, medido desde el Player.
func _intentar_agarrar() -> void:
	var objetivo := _mas_cercano()
	if objetivo == null:
		_avisar("cerca", "[Garras] Nada agarrable a %.1f m volando (grupo '%s')." % [radio_agarre, grupo_agarrables])
		return
	_capa_respaldo = objetivo.collision_layer
	objetivo.freeze = true
	objetivo.collision_layer = 0  # no choca con el portador mientras cuelga
	var destino: Node3D = _garra if _garra != null else _body
	objetivo.reparent(destino)  # conserva la posición global...
	_cargado = objetivo
	_estado = Estado.CARGANDO
	var tw := create_tween()
	tw.tween_property(objetivo, "position", Vector3.ZERO, 0.12)  # ...y "vuela" a la garra
	print("[Garras] ¡Presa agarrada! ", objetivo.name)

func _soltar() -> void:
	if _cargado == null:
		_estado = Estado.LIBRE
		return
	var objeto := _cargado
	_cargado = null
	_estado = Estado.LIBRE
	objeto.reparent(_escena())
	objeto.freeze = false
	objeto.collision_layer = _capa_respaldo
	objeto.linear_velocity = Vector3.ZERO  # caída suave
	print("[Garras] Soltado: ", objeto.name)

## Lanzamiento: patada procedural y, al pico, la presa sale disparada
## hacia donde mira la cámara.
func _patear() -> void:
	_estado = Estado.PATANDO
	var nombre := _resolver_clip(&"PatadaGarra")
	if not nombre.is_empty() and _controller != null:
		_controller.reproducir_overlay(StringName(nombre))
	var duracion := 0.45
	if not nombre.is_empty() and _anim.has_animation(nombre):
		duracion = _anim.get_animation(nombre).length
	get_tree().create_timer(duracion * momento_lanzamiento).timeout.connect(_impulsar)

func _impulsar() -> void:
	var objeto := _cargado
	_cargado = null
	_estado = Estado.LIBRE
	if objeto == null or not is_instance_valid(objeto):
		return
	objeto.reparent(_escena())
	objeto.freeze = false
	objeto.collision_layer = _capa_respaldo
	var direccion := Vector3.FORWARD
	var camara := get_viewport().get_camera_3d()
	if camara != null:
		direccion = -camara.global_transform.basis.z
		direccion.y = clampf(direccion.y, -0.2, 0.6)
		direccion = direccion.normalized()
	objeto.linear_velocity = direccion * fuerza_lanzamiento + Vector3.UP * altura_lanzamiento
	print("[Garras] ¡Puntapié de garras! ", objeto.name, " sale volando.")

func _mas_cercano() -> RigidBody3D:
	var mejor: RigidBody3D = null
	var mejor_dist := radio_agarre
	for nodo in get_tree().get_nodes_in_group(grupo_agarrables):
		var cuerpo := nodo as RigidBody3D
		if cuerpo == null or not is_instance_valid(cuerpo) or cuerpo.freeze:
			continue
		var d := cuerpo.global_position.distance_to(_body.global_position)
		if d < mejor_dist:
			mejor_dist = d
			mejor = cuerpo
	return mejor

func _volando() -> bool:
	var fc := get_parent().get_node_or_null("FlightController")
	return fc != null and fc.is_flying

func _escena() -> Node:
	var escena := get_tree().current_scene
	return escena if escena != null else get_tree().root

func _resolver_garra() -> Node3D:
	if garra_path != NodePath():
		return get_node_or_null(garra_path) as Node3D
	return get_parent().get_node_or_null(NodePath("VisualRoot/GarraSpawn")) as Node3D

## Busca "PatadaGarra" (o el nombre con prefijo de biblioteca) y devuelve
## el nombre COMPLETO para reproducir (los clips viven en la lib UAL2).
func _resolver_clip(nombre: StringName) -> String:
	var completo := String(nombre)
	if _anim != null and _anim.has_animation(completo):
		return completo
	var sufijo := "/" + completo
	if _anim != null:
		for candidato in _anim.get_animation_list():
			if String(candidato).ends_with(sufijo):
				return String(candidato)
	return ""

func _buscar_animation_player() -> AnimationPlayer:
	if animation_player_path != NodePath():
		return get_node_or_null(animation_player_path) as AnimationPlayer
	return _anim_de(get_parent())

func _anim_de(nodo: Node) -> AnimationPlayer:
	if nodo is AnimationPlayer:
		return nodo as AnimationPlayer
	for hijo in nodo.get_children():
		var encontrado := _anim_de(hijo)
		if encontrado != null:
			return encontrado
	return null

func _avisar(clave: String, mensaje: String) -> void:
	if _avisos.has(clave):
		return
	_avisos[clave] = true
	print(mensaje)
