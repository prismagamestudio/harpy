class_name GroundCombat
extends Node
## HARPY — Combate terrestre FLUIDO: cadena Jab -> Cross -> Patada -> Uppercut.
## Diseño tipo Arkham:
##  - Cancel al 50% del gesto con blend: los golpes se FUNDEN.
##  - Buffer de clics + cadena infinita.
##  - Avance hacia adelante por golpe + el cuerpo mira hacia la cámara.
##  - Guardia SOLO mientras se mantiene presionado "guard" (hold, no toggle).
##    Golpear despeja la guardia. Soltar vuelve a Idle/Walk solo.
## Requiere acciones: "melee_light" (LMB / Square), "guard" (Q / R1)
## y "aim" (RMB / L2): mientras se apunta, no sale melee.

@export var animation_player_path: NodePath = NodePath()
@export var animation_controller_path: NodePath = NodePath()
@export var feather_ability_path: NodePath = NodePath()

## Golpes en orden (nombres base; se resuelven con o sin prefijo de biblioteca).
@export var cadena: Array[StringName] = [
	&"Punch_Jab", &"Punch_Cross", &"Kick", &"Melee_Uppercut",
]
## Fracción del clip desde la que un clic nuevo encadena (cancela el gesto).
@export_range(0.2, 0.9, 0.05) var cancel_ratio: float = 0.5
## Velocidad de reproducción de los golpes (>1 = más vertiginoso).
@export_range(0.8, 2.0, 0.05) var velocidad_golpes: float = 1.15
## Avance hacia adelante al empezar cada golpe (m/s).
@export var impulso_avance: float = 3.5
## Fracción inicial del clip en la que empuja hacia adelante.
@export_range(0.1, 0.6, 0.05) var avance_ratio: float = 0.3
@export var frenado_velocidad: float = 20.0
@export var giro_al_atacar: float = 14.0
## Pose de escudo al mantener "guard" (GuardiaAlas la genera el loader).
@export var guardia_animacion: StringName = &"GuardiaAlas"

const GUARDIA_FALLBACKS: Array[StringName] = [
	&"GuardiaAlas", &"Idle_Shield", &"Sword_Block",
]

var _anim: AnimationPlayer
var _visual: Node3D
var _body: CharacterBody3D
var _controller: Node = null
var _feathers: Node = null

var _indice := -1
var _clip_actual := ""
var _buffer := false
var _impacto_t: float = -1.0
var _impacto_indice: int = 0
var _guardia := false
var _aviso_guardia := false
var _avisos_clip := {}

func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	_anim = _buscar_animation_player()
	_visual = get_parent().get_node_or_null("VisualRoot") as Node3D
	_controller = _resolver(animation_controller_path, "AnimationController")
	_feathers = _resolver(feather_ability_path, "FeatherAbility")
	if _anim == null or _controller == null:
		printerr("[GroundCombat] Faltan piezas: anim=", _anim, " controller=", _controller)
		return
	var estado := PackedStringArray()
	for c in cadena:
		var resuelto := _resolver_clip(String(c))
		var ok := not resuelto.is_empty()
		estado.append(String(c) + ("=OK" if ok else "=FALTA"))
	print("[GroundCombat] Cadena: ", ", ".join(estado))
	var guardia_resuelta := _resolver_clip(String(guardia_animacion))
	print("[GroundCombat] Guardia: ", guardia_resuelta if not guardia_resuelta.is_empty() else "¡SIN CLIP!")

## Verdadero mientras dura un combo o la guardia. player.gd lo consulta para
## NO pelearse por la rotación del visual.
func esta_peleando() -> bool:
	return _indice != -1 or _guardia

func _physics_process(delta: float) -> void:
	if _anim == null or _controller == null or _body == null:
		return
	# Impacto del golpe pendiente (cuenta regresiva en física).
	if _impacto_t >= 0.0:
		_impacto_t -= delta
		if _impacto_t < 0.0:
			_impacto_melee(_impacto_indice)

	# En el aire o volando: nada de combate terrestre.
	if not _body.is_on_floor():
		if _indice != -1 or _guardia:
			_cortar()
		return

	var apuntando: bool = InputMap.has_action("aim") and Input.is_action_pressed("aim")

	# --- Guardia: SOLO existe mientras el botón está presionado ---
	var quiere_guardia: bool = Input.is_action_pressed("guard") and not apuntando
	if _indice == -1 and quiere_guardia and not _guardia:
		_abrir_guardia()
	elif _guardia and not quiere_guardia:
		_cerrar_guardia()

	# --- Golpes (un golpe despeja la guardia) ---
	# melee_light (Square/LMB) o feather_fire (R2/LMB) sin apuntar: el botón
	# principal es contextual, igual en teclado y pad.
	var golpea: bool = Input.is_action_just_pressed("melee_light") or (
		InputMap.has_action("feather_fire")
		and Input.is_action_just_pressed("feather_fire")
	)
	if not apuntando and not _garras_ocupadas() and golpea:
		if _indice == -1:
			_lanzar(0)
		else:
			_buffer = true

	# --- Flujo ---
	if _guardia:
		_frenar(delta)
		_encarar_camara(delta)
	elif _indice != -1:
		_avanzar_combo(delta)

## Corazón del combo: cancela con buffer, detecta el fin y empuja hacia adelante.
func _avanzar_combo(delta: float) -> void:
	var progreso := 0.0
	if _anim.current_animation == _clip_actual and _anim.is_playing():
		var largo := _anim.current_animation_length
		if largo > 0.0:
			progreso = _anim.current_animation_position / largo

	# Clic bufferado + ventana alcanzada: encadena YA (con blend del overlay).
	if _buffer and progreso >= cancel_ratio:
		_lanzar((_indice + 1) % cadena.size())
		return

	# El clip terminó (o el controller retomó el control): combo cerrado.
	if _anim.current_animation != _clip_actual or not _anim.is_playing():
		_terminar()
		return

	_encarar_camara(delta)

	# Avance: empuja al principio del golpe, frena después (peso coreográfico).
	var objetivo := Vector3.ZERO
	if progreso <= avance_ratio:
		objetivo = _frente_camara() * impulso_avance
	_body.velocity.x = move_toward(_body.velocity.x, objetivo.x, 40.0 * delta)
	_body.velocity.z = move_toward(_body.velocity.z, objetivo.z, 40.0 * delta)

func _lanzar(indice: int) -> void:
	var clip := _resolver_clip(String(cadena[indice]))
	if clip.is_empty():
		printerr("[GroundCombat] No está el clip: ", cadena[indice])
		_terminar()
		return
	_indice = indice
	_buffer = false
	_clip_actual = clip
	if _guardia:  # un golpe despeja la guardia
		_guardia = false
		_set_feathers(true)
	_encarar_camara(1.0)
	# Diagnóstico (una vez por clip): si dice "0 pistas", ese clip cargó vacío.
	if not _avisos_clip.has(clip):
		_avisos_clip[clip] = true
		var recurso := _anim.get_animation(clip)
		print("[GroundCombat] ▶ %s (%.2f s, %d pistas)" % [clip, recurso.length, recurso.get_track_count()])
	_controller.reproducir_overlay(StringName(clip), velocidad_golpes)
	# Al pico del golpe (~mitad) se consulta el impacto — DENTRO del ciclo
	# de física (un timer de escena dispara fuera y la consulta espacial
	# volvía vacía: por eso el puño no conectaba).
	_impacto_t = _anim.get_animation(clip).length / maxf(velocidad_golpes, 0.1) * 0.4
	_impacto_indice = indice

## Detección de impacto del melee: esfera delante del jugador; si hay un
## maniquí de práctica, le pasa daño creciente por eslabón de la cadena.
func _impacto_melee(indice: int) -> void:
	if _indice == -1:
		return  # el golpe se cortó (aire, guardia, etc.)
	var espacio := _body.get_world_3d().direct_space_state
	var forma := SphereShape3D.new()
	forma.radius = 1.4
	var consulta := PhysicsShapeQueryParameters3D.new()
	consulta.shape = forma
	var visual := _body.get_node_or_null("VisualRoot") as Node3D
	var adelante := Vector3.FORWARD
	if visual != null:
		adelante = -visual.global_transform.basis.z
	consulta.transform = Transform3D(
		Basis.IDENTITY,
		_body.global_position + adelante * 1.2 + Vector3.UP * 0.9
	)
	consulta.collide_with_bodies = true
	consulta.collision_mask = 1
	for resultado in espacio.intersect_shape(consulta, 6):
		var cuerpo: Object = resultado["collider"]
		if cuerpo != null and cuerpo.is_in_group("maniqui"):
			var danio := 8 + indice * 4
			cuerpo.recibir_golpe(danio, adelante, 4.5)
			print("[GroundCombat] 💥 ", cadena[indice], " conecta: ", danio, " de daño")
			return

func _terminar() -> void:
	_indice = -1
	_buffer = false
	_clip_actual = ""
	_anim.speed_scale = 1.0
	# El AnimationController retoma Idle/Walk solo al terminar el clip.

func _cortar() -> void:
	# Corte de emergencia (despegue, caída): cierra TODO y devuelve el mando.
	_terminar()
	_guardia = false
	_set_feathers(true)
	_controller.terminar_overlay()

func _abrir_guardia() -> void:
	var clip := _resolver_clip(String(guardia_animacion))
	if clip.is_empty():
		for candidato in GUARDIA_FALLBACKS:
			clip = _resolver_clip(String(candidato))
			if not clip.is_empty():
				break
	if clip.is_empty():
		if not _aviso_guardia:
			_aviso_guardia = true
			printerr("[GroundCombat] No hay animación de guardia (¿el loader cargó GuardiaAlas?)")
		return
	var recurso := _anim.get_animation(clip)
	if recurso != null and recurso.loop_mode == Animation.LOOP_NONE:
		recurso.loop_mode = Animation.LOOP_LINEAR  # se mantiene mientras se mantiene Q
	_guardia = true  # <- EL FIX: sin esto, el flag nunca enciende y el cierre nunca corre
	_encarar_camara(1.0)
	_set_feathers(false)
	_controller.reproducir_overlay(StringName(clip))

func _cerrar_guardia() -> void:
	# FIX del bug del "toggle": el flag se apaga SIEMPRE acá.
	_guardia = false
	_set_feathers(true)
	_anim.speed_scale = 1.0
	if _controller.has_method("terminar_overlay"):
		_controller.terminar_overlay()
	else:
		printerr("[GroundCombat] animation_controller.gd NO tiene terminar_overlay(): actualizalo.")
	# El clip de guardia sigue en loop en el player: hay que cortarlo YA,
	# si no las piernas quedan en pose de defensa (también al volar).
	var idle := _resolver_clip("Idle")
	if not idle.is_empty():
		_anim.play(idle, 0.15)

# --- helpers ---

## Root motion: el clip mueve el hueso Root del esqueleto; medimos ese
## desplazamiento frame a frame y lo convertimos en velocidad del cuerpo,
## así el personaje recorre EXACTAMENTE lo que la animación pisa.
func _set_feathers(activo: bool) -> void:
	if _feathers != null:
		_feathers.process_mode = Node.PROCESS_MODE_INHERIT if activo else Node.PROCESS_MODE_DISABLED

func _frenar(delta: float) -> void:
	_body.velocity.x = move_toward(_body.velocity.x, 0.0, frenado_velocidad * delta)
	_body.velocity.z = move_toward(_body.velocity.z, 0.0, frenado_velocidad * delta)

func _encarar_camara(delta: float) -> void:
	if _visual == null:
		return
	var camara := get_viewport().get_camera_3d()
	if camara == null:
		return
	# MISMA convención que player.gd: mirar hacia v = atan2(-v.x, -v.z).
	var adelante := -camara.global_transform.basis.z
	adelante.y = 0.0
	if adelante.length_squared() < 0.0001:
		return
	var angulo := atan2(-adelante.x, -adelante.z)
	_visual.rotation.y = lerp_angle(_visual.rotation.y, angulo, clampf(giro_al_atacar * delta, 0.0, 1.0))

func _frente_camara() -> Vector3:
	var camara := get_viewport().get_camera_3d()
	if camara == null:
		return Vector3.ZERO
	var frente := -camara.global_transform.basis.z
	frente.y = 0.0
	return frente.normalized() if frente.length_squared() > 0.0001 else Vector3.ZERO

## Encuentra un clip por nombre exacto o por sufijo "/nombre" (cualquier biblioteca).
func _resolver_clip(nombre: String) -> String:
	if _anim.has_animation(nombre):
		return nombre
	var sufijo := "/" + nombre
	for candidato in _anim.get_animation_list():
		if String(candidato).ends_with(sufijo):
			return String(candidato)
	return ""

func _resolver(ruta: NodePath, nombre_fallback: String) -> Node:
	if ruta != NodePath():
		return get_node_or_null(ruta)
	return get_parent().get_node_or_null(NodePath(nombre_fallback))

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


## Con presa en las garras no se pelea a puños: LMB lanza, E suelta.
func _garras_ocupadas() -> bool:
	var talons := get_parent().get_node_or_null("TalonsAbility")
	return talons != null and talons.esta_cargando()
