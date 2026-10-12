extends Node

## Carga los clips pedidos de los GLB source (importados como Scene), los
## retargetea y arma dos bibliotecas:
##  - "UAL2": clips completos, en el AnimationPlayer principal.
##  - "UAL2Brazos": parte superior del cuerpo (torso + brazos), en un
##    AnimationPlayer overlay creado por código.
## Además genera copias espejadas (_M) de los clips de CLIPS_ESPEJO y el
## clip "GuardiaAlas": brazos cruzados en X al pecho (placeholder del
## capullo de alas — las alas se envuelven encima de ese cruce).
##
## v5: GuardiaAlas construida por DIRECCIONES (apuntar cada segmento del
## brazo hacia un punto del cuerpo), con perillas de calibración.

## Huesos cuya inclinación se corrige hacia la pose neutra.
const HUESOS_POSTURA := ["Hips", "Spine", "Chest", "UpperChest"]

const LIBRARY_NAME := "UAL2"
const LIB_BRAZOS := "UAL2Brazos"
const TARGET_SKELETON := "Rig/GeneralSkeleton"
const OVERLAY_PLAYER_NAME := "UAL2_OverlayPlayer"

## Archivos fuente, en orden de prioridad. El primer archivo que traiga un
## clip pedido gana (no se cargan duplicados). Cada uno se busca en las DOS
## grafías de carpeta (animations/animaciones) para evitar dramas de rutas.
const FUENTES_CANDIDATAS: Array = [
	["res://animations/UAL2/_ALL_SOURCE_ANIMS_2.glb",
	 "res://animaciones/UAL2/_ALL_SOURCE_ANIMS_2.glb"],
	["res://animations/UAL2/UAL2_Standard.glb",
	 "res://animaciones/UAL2/UAL2_Standard.glb"],
	["res://animations/UAL1/_ALL_SOURCE_ANIMS_1.glb",
	 "res://animaciones/UAL1/_ALL_SOURCE_ANIMS_1.glb"],
]

## Huesos que pisa el overlay: torso + brazos (las piernas quedan para la base).
const PALABRAS_SUPERIORES := [
	"Shoulder", "Arm", "Hand", "Thumb", "Index",
	"Middle", "Ring", "Little", "Spine", "Chest",
]

## Huesos de piernas que se acercan a la pose neutra en el clip colgante.
const HUESOS_PIERNAS_NEUTRAS := [
	"LeftUpperLeg", "RightUpperLeg",
	"LeftLowerLeg", "RightLowerLeg",
	"LeftFoot", "RightFoot",
]

const LIB_PIERNAS := "UAL2Piernas"
const PIERNAS_PLAYER_NAME := "UAL2_PiernasPlayer"
const CLIP_PIERNAS_FUENTE := "Swim_Idle"
const PALABRAS_PIERNAS := ["Leg", "Foot", "Toes"]

## Clips a importar (sin prefijo de origen). Se matchean por sufijo.
const CLIPS := [
	"DoubleJump",
	"Sword_Light_A",
	"Sword_Light_A_Rec",
	"Sword_Light_B",
	"Sword_Light_B_Rec",
	"Melee_Knee",
	"Melee_Knee_Rec",
	"Melee_Uppercut",
	"Idle_Shield",
	"Kick",
	"Swim_Fwd",
	"LiftAir_Idle",
	"BackFlip",
]


## Clips a los que se les genera una copia espejada con sufijo "_M".
const CLIPS_ESPEJO := [
	"Sword_Light_A",
	"Sword_Light_A_Rec",
]
const SUFIJO_ESPEJO := "_M"

## Golpes a los que se les quita la pista de ROTACIÓN del hueso Root:
## traen giros corporales horneados (el uppercut hacía piruetear al modelo).
## Nuestro código controla la orientación; el clip no.
const CLIPS_SIN_GIRO_ROOT := [
	"Punch_Jab", "Punch_Cross", "Kick", "Melee_Knee", "Melee_Uppercut",
]

## Eje que separa izquierda y derecha en el espacio local del hueso padre.
## Si el espejo se ve con dobleces raros (codos "al revés"), probá
## Vector3.UP o Vector3.BACK acá.
const EJE_ESPEJO := Vector3.RIGHT

## 0 = sin corrección, 1 = torso totalmente recto (pose de descanso).
@export_range(0.0, 1.0, 0.05) var enderezado_postura := 0.6

## 0 = piernas como Swim_Idle, 1 = totalmente rectas y juntas (rígido).
@export_range(0.0, 1.0, 0.05) var piernas_juntas := 0.35

## Punto de los pies (flexión plantar) en grados. Positivo apunta los pies
## hacia abajo; si te quedan apuntando al revés, ponelo negativo.
@export_range(-60.0, 60.0, 1.0) var punta_pies_grados := 30.0

## --- Guardia de alas (cruce en X) ---
## Genera "GuardiaAlas": cuerpo del Idle (respira) + brazos cruzados en X
## al pecho (mano izquierda hacia el hombro derecho y viceversa).
##
## AJUSTE EN TIEMPO REAL: corré el juego, mantené Q, y en el editor abrí
## la pestaña "Remote" (arriba del árbol de escena) -> Player -> UALLoader.
## El Inspector muestra estas perillas EN VIVO: al moverlas, la guardia se
## regenera al instante y el maniquí se recruza solo.
@export var guardia_alas_activada := true
## Genera "PatadaGarra": doble patada de garras (lanzamiento del agarre aéreo).
@export var patada_garra_activada := true
## Genera "Planeo": pose congelada de alas para el vuelo a toda velocidad.
@export var planeo_activado := true
## Planeo: cuánto se abren los brazos-alas (afuera / arriba, en metros).
@export var planeo_brazos_afuera: float = 0.45
@export var planeo_brazos_arriba: float = 0.30
## Cuánto ADELANtado queda el cruce (metros). Más = se despega del cuerpo.
@export_range(0.0, 0.6, 0.02) var guardia_cruce_forward := 0.3:
	set(valor):
		guardia_cruce_forward = valor
		_regen_guardia()
## Altura de las manos respecto del hombro OPUESTO (metros).
## 0 = mano al nivel del hombro contrario; negativo = más abajo (pecho).
## OJO: positivo alto termina en la garganta (¡probado!).
@export_range(-0.3, 0.4, 0.02) var guardia_manos_arriba := -0.12:
	set(valor):
		guardia_manos_arriba = valor
		_regen_guardia()
## Extra hacia adelante del CODO: separa el brazo/antebrazo del torso.
## Subilo si el codo se hunde en el pecho.
@export_range(-0.2, 0.4, 0.02) var guardia_codo_forward := 0.08:
	set(valor):
		guardia_codo_forward = valor
		_regen_guardia()
## Extra hacia adelante de las MUÑECAS: distancia de las manos al pecho
## (y al mentón, junto con manos_arriba). Subilo si están pegadas.
@export_range(-0.2, 0.5, 0.02) var guardia_manos_forward := 0.12:
	set(valor):
		guardia_manos_forward = valor
		_regen_guardia()
## Empuja las manos hacia AFUERA del centro del pecho (anti-clipping).
## 0 = en el medio; más = la X se abre un poco a los costados.
@export_range(0.0, 0.3, 0.02) var guardia_separacion_cuerpo := 0.06:
	set(valor):
		guardia_separacion_cuerpo = valor
		_regen_guardia()

@export var test_al_iniciar := false

## Cambio de modelo: player y esqueleto se BUSCAN solos bajo VisualRoot.
## OJO: se toma el PRIMERO del árbol (el maniquí del rig de referencia).
@onready var anim_player: AnimationPlayer = _resolver_player()
@onready var _skeleton: Skeleton3D = _buscar_esqueleto(get_node_or_null("../VisualRoot"))

## Ruta del esqueleto RELATIVA al root del player (para las pistas).
## El _ready la recalcula a partir del esqueleto encontrado.
var _ruta_esqueleto: String = TARGET_SKELETON

func _resolver_player() -> AnimationPlayer:
	var visual := get_node_or_null("../VisualRoot")
	var encontrado := _buscar_player(visual)
	if encontrado != null:
		return encontrado
	# Sin player (p. ej. un FBX sin animaciones): crear uno.
	var nuevo := AnimationPlayer.new()
	nuevo.name = "AnimationPlayerAuto"
	if visual != null:
		visual.add_child(nuevo)
		nuevo.owner = null
		nuevo.root_node = nuevo.get_path_to(visual)
	print("[Loader] AnimationPlayer autogenerado (el modelo no trajo uno).")
	return nuevo

func _buscar_player(nodo: Node) -> AnimationPlayer:
	if nodo == null:
		return null
	if nodo is AnimationPlayer:
		return nodo
	for hijo in nodo.get_children():
		var r := _buscar_player(hijo)
		if r != null:
			return r
	return null

func _buscar_esqueleto(nodo: Node) -> Skeleton3D:
	if nodo == null:
		return null
	if nodo is Skeleton3D:
		return nodo as Skeleton3D
	for hijo in nodo.get_children():
		var r := _buscar_esqueleto(hijo)
		if r != null:
			return r as Skeleton3D
	return null

func _ready() -> void:
	if anim_player != null and _skeleton != null:
		var raiz := anim_player.get_node(anim_player.root_node)
		_ruta_esqueleto = String(raiz.get_path_to(_skeleton))
	_agregar_bibliotecas()
	if test_al_iniciar:
		_prueba_temporal()

func _agregar_bibliotecas() -> void:
	if anim_player == null or anim_player.has_animation_library(LIBRARY_NAME):
		return

	var lib_completa := AnimationLibrary.new()
	var lib_brazos := AnimationLibrary.new()
	var encontrados := {}

	for candidatos in FUENTES_CANDIDATAS:
		var source_scene := _primera_existente(candidatos)
		if source_scene.is_empty():
			push_warning("UAL2 loader: no encontré ninguna de estas rutas: ", ", ".join(PackedStringArray(candidatos)))
			continue
		var packed: PackedScene = load(source_scene)
		if packed == null:
			push_warning("UAL2 loader: no se pudo cargar " + source_scene)
			continue
		var src: Node = packed.instantiate()
		var src_ap := _animation_player_de(src)
		if src_ap == null:
			push_warning("UAL2 loader: no encontré AnimationPlayer en " + source_scene)
			src.queue_free()
			continue

		for clip in src_ap.get_animation_list():
			var nombre := String(clip)
			nombre = nombre.replace("UAL2_Source_", "").replace("UAL1_Source_", "")
			var pedido := _clip_pedido(nombre)
			if pedido.is_empty() or encontrados.has(pedido):
				continue
			encontrados[pedido] = true
			var retargeteado := _retarget_clip(src_ap.get_animation(clip), pedido)
			if pedido == "Idle_Shield":
				retargeteado.loop_mode = Animation.LOOP_LINEAR  # la guardia se mantiene
			lib_completa.add_animation(pedido, retargeteado)
			var brazos := _clip_parte_superior(retargeteado)
			if pedido == "DoubleJump":
				brazos.loop_mode = Animation.LOOP_LINEAR  # aleteo continuo
				brazos = _enderezar_postura(brazos)
			lib_brazos.add_animation(pedido, brazos)
			if CLIPS_ESPEJO.has(pedido):
				var espejado := _clip_espejado(retargeteado)
				lib_completa.add_animation(pedido + SUFIJO_ESPEJO, espejado)
				lib_brazos.add_animation(pedido + SUFIJO_ESPEJO, _clip_parte_superior(espejado))

		src.queue_free()

	for pedido in CLIPS:
		if encontrados.has(pedido):
			continue
		# Algunos clips viven SOLO en el maniquí (UAL1_Standard = GLB base):
		# Swim_Fwd, etc. Se copian de ahí antes de avisar falta.
		var en_base := _buscar_clip_base(pedido)
		if not en_base.is_empty():
			lib_completa.add_animation(pedido, anim_player.get_animation(en_base))
			continue
		push_warning("UAL2 loader: NO encontré el clip " + pedido + " en ninguna fuente")

	if lib_completa.get_animation_list().is_empty():
		push_warning("UAL2 loader: no se copió ningún clip")
		return

	if guardia_alas_activada:
		var guardia := _clip_guardia_alas()
		if guardia != null:
			lib_completa.add_animation("GuardiaAlas", guardia)
			print("UAL2 loader: GuardiaAlas generada (cruce en X; perillas en el Inspector).")

	if patada_garra_activada:
		var patada := _armar_patada_garra()
		if patada != null:
			lib_completa.add_animation("PatadaGarra", patada)
			print("UAL2 loader: PatadaGarra generada (doble patada de garras).")

	anim_player.add_animation_library(LIBRARY_NAME, lib_completa)

	var overlay := _crear_overlay_player()
	overlay.add_animation_library(LIB_BRAZOS, lib_brazos)
	_aleteo_brazos_loop(overlay, lib_brazos)
	print("UAL2 loader: clips completos -> ", lib_completa.get_animation_list())
	print("UAL2 loader: clips de torso+brazos -> ", lib_brazos.get_animation_list())

	_enderezar_jump_base()
	_armar_jump_planeo()
	_armar_planeo()
	_armar_aleteo_alas()
	_armar_pose_picado()
	_armar_vuelo_heroe()
	_armar_palmazo_push()
	_armar_caida_libre()



func _clip_pedido(nombre: String) -> String:
	for pedido in CLIPS:
		if nombre == pedido or nombre.ends_with(pedido):
			return pedido
	return ""

## Primera ruta de la lista que exista en este proyecto.
func _primera_existente(candidatos: Array) -> String:
	for ruta in candidatos:
		if ResourceLoader.exists(ruta):
			return String(ruta)
	return ""

## Busca el AnimationPlayer del source sin importar cómo se llame
## (AnimationPlayer, AnimationPlayer2, etc.).
func _animation_player_de(nodo: Node) -> AnimationPlayer:
	if nodo is AnimationPlayer:
		return nodo as AnimationPlayer
	for hijo in nodo.get_children():
		var encontrado := _animation_player_de(hijo)
		if encontrado != null:
			return encontrado
	return null

func _crear_overlay_player() -> AnimationPlayer:
	var overlay := AnimationPlayer.new()
	overlay.name = OVERLAY_PLAYER_NAME
	overlay.root_node = anim_player.root_node
	anim_player.get_parent().add_child(overlay)
	overlay.add_to_group("ual2_overlay_player")
	return overlay

func _hueso(nombre: String) -> String:
	# La migración al FBX Mixamo quedó ARCHIVADA: pase directo del nombre
	# (los generadores procedurales la usan sin saberlo).
	return nombre

func _retarget_clip(src_anim: Animation, pedido: String = "") -> Animation:
	var nueva: Animation = src_anim.duplicate(true)
	for i in range(nueva.get_track_count() - 1, -1, -1):
		var np: NodePath = nueva.track_get_path(i)
		if np.get_subname_count() == 0:
			nueva.remove_track(i)
			continue
		var hueso := String(np.get_subname(0))
		var mapeado := "Root" if hueso == "Root2" else hueso
		nueva.track_set_path(i, NodePath(_ruta_esqueleto + ":" + mapeado))
	# Giros horneados fuera: en los clips de melee, la rotación del hueso
	# Root giraba al personaje entero (el uppercut terminaba mirando a la
	# cámara). La orientación la maneja nuestro código, no el clip.
	if CLIPS_SIN_GIRO_ROOT.has(pedido):
		for i in range(nueva.get_track_count() - 1, -1, -1):
			var np2: NodePath = nueva.track_get_path(i)
			if nueva.track_get_type(i) == Animation.TYPE_ROTATION_3D \
					and np2.get_subname_count() > 0 \
					and String(np2.get_subname(0)) == "Root":
				nueva.remove_track(i)
	return nueva

func _clip_parte_superior(clip: Animation) -> Animation:
	var nueva: Animation = clip.duplicate(true)
	for i in range(nueva.get_track_count() - 1, -1, -1):
		var np: NodePath = nueva.track_get_path(i)
		if np.get_subname_count() == 0:
			continue
		if not _es_hueso_superior(String(np.get_subname(0))):
			nueva.remove_track(i)
	return nueva

func _es_hueso_superior(hueso: String) -> bool:
	for palabra in PALABRAS_SUPERIORES:
		if hueso.contains(palabra):
			return true
	return false

### Genera la copia espejada: intercambia huesos Left<->Right y refleja
## posición y rotación sobre el plano definido por EJE_ESPEJO.
func _clip_espejado(clip: Animation) -> Animation:
	var nueva := Animation.new()
	nueva.length = clip.length
	nueva.step = clip.step
	nueva.loop_mode = clip.loop_mode

	for i in range(clip.get_track_count()):
		var tipo := clip.track_get_type(i)
		var np: NodePath = clip.track_get_path(i)

		if tipo == Animation.TYPE_POSITION_3D \
				or tipo == Animation.TYPE_ROTATION_3D \
				or tipo == Animation.TYPE_SCALE_3D:
			var idx := nueva.add_track(tipo)
			nueva.track_set_path(idx, _ruta_espejada(np))
			for k in range(clip.track_get_key_count(i)):
				var t := clip.track_get_key_time(i, k)
				match tipo:
					Animation.TYPE_POSITION_3D:
						var p: Vector3 = clip.track_get_key_value(i, k)
						nueva.position_track_insert_key(idx, t, _punto_espejado(p))
					Animation.TYPE_ROTATION_3D:
						var q: Quaternion = clip.track_get_key_value(i, k)
						nueva.rotation_track_insert_key(idx, t, _quaternion_espejado(q))
					Animation.TYPE_SCALE_3D:
						var s: Vector3 = clip.track_get_key_value(i, k)
						nueva.scale_track_insert_key(idx, t, s)
		else:
			# Pistas de nodo/método/etc.: se copian tal cual.
			clip.copy_track(i, nueva)

	return nueva

func _ruta_espejada(np: NodePath) -> NodePath:
	if np.get_subname_count() == 0:
		return np
	var hueso := String(np.get_subname(0))
	return NodePath(String(np.get_concatenated_names()) + ":" + _hueso_espejado(hueso))

func _hueso_espejado(hueso: String) -> String:
	if hueso.begins_with("Left"):
		return "Right" + hueso.trim_prefix("Left")
	if hueso.begins_with("Right"):
		return "Left" + hueso.trim_prefix("Right")
	return hueso

func _punto_espejado(p: Vector3) -> Vector3:
	return p - 2.0 * p.dot(EJE_ESPEJO) * EJE_ESPEJO

func _quaternion_espejado(q: Quaternion) -> Quaternion:
	var v := Vector3(q.x, q.y, q.z)
	var v2 := -v + 2.0 * v.dot(EJE_ESPEJO) * EJE_ESPEJO
	return Quaternion(v2.x, v2.y, v2.z, q.w)

func _prueba_temporal() -> void:
	var overlay := get_tree().get_first_node_in_group("ual2_overlay_player") as AnimationPlayer
	if overlay != null and overlay.has_animation(LIB_BRAZOS + "/Sword_Light_A_M"):
		anim_player.play("Idle")
		overlay.play(LIB_BRAZOS + "/Sword_Light_A_M")

# --- Guardia de alas: cruce en X por direcciones ---

## Cuerpo del Idle (respira) + brazos cruzados en X: cada brazo cruza al
## pecho con la mano hacia el hombro OPUESTO. Se apunta cada segmento del
## brazo (upper/lower) hacia un punto objetivo del cuerpo y el quaternion
## sale de la diferencia entre la dirección actual y la deseada.
func _clip_guardia_alas() -> Animation:
	var base := _buscar_clip_base("Idle")
	if base.is_empty() or _skeleton == null:
		push_warning("UAL2 loader: sin Idle o sin esqueleto, no genero GuardiaAlas")
		return null
	var guardia: Animation = anim_player.get_animation(base).duplicate(true)
	_quitar_pistas_brazo(guardia)
	var ok := _cruzar_brazo(guardia, "Left", "Right")
	ok = _cruzar_brazo(guardia, "Right", "Left") and ok
	if not ok:
		push_warning("UAL2 loader: no encontré los huesos de brazo; no genero GuardiaAlas")
		return null
	guardia.loop_mode = Animation.LOOP_LINEAR
	return guardia

## Cruza UN brazo: el upper apunta al hombro opuesto (un pelín abajo),
## el lower apunta por debajo del hombro opuesto (la mano al deltoide
## contrario, no a la garganta).
func _cruzar_brazo(guardia: Animation, lado: String, opuesto: String) -> bool:
	var upper := _skeleton.find_bone(_hueso(lado + "UpperArm"))
	var lower := _skeleton.find_bone(_hueso(lado + "LowerArm"))
	var sh_op := _skeleton.find_bone(_hueso(opuesto + "Shoulder"))
	if upper < 0 or lower < 0 or sh_op < 0:
		return false
	var p_sh := _pos_global_rest(_skeleton.find_bone(_hueso(lado + "Shoulder")))
	if p_sh == Vector3.ZERO:
		p_sh = _pos_global_rest(upper)
	var p_lo := _pos_global_rest(lower)
	var p_sh_op := _pos_global_rest(sh_op)

	# OJO: el maniquí mira hacia +Z en su espacio interno (el GLB trae la
	# cara para +Z; la instancia lo compensa con 180°). "Adelante" acá es +Z.
	var adelante := Vector3(0.0, 0.0, 1.0)
	var objetivo_upper := p_sh_op \
		+ adelante * (guardia_cruce_forward * 0.5 + guardia_codo_forward) \
		- Vector3(0.0, 0.05, 0.0)
	var objetivo_lower := p_sh_op \
		+ Vector3(0.0, guardia_manos_arriba, 0.0) \
		+ adelante * (guardia_cruce_forward + guardia_manos_forward)
	objetivo_lower += _hacia_afuera(p_sh) * guardia_separacion_cuerpo

	var ok := true
	ok = _poner_direccion(guardia, upper, (objetivo_upper - p_sh).normalized()) and ok
	ok = _poner_direccion(guardia, lower, (objetivo_lower - p_lo).normalized()) and ok
	return ok

## Dirección desde el centro del pecho hacia el hombro propio (plano XZ).
## Se usa para empujar las manos hacia afuera, sea cual sea la convención
## de ejes del import.
func _hacia_afuera(p_sh: Vector3) -> Vector3:
	var izq := _pos_global_rest(_skeleton.find_bone(_hueso("LeftShoulder")))
	var der := _pos_global_rest(_skeleton.find_bone(_hueso("RightShoulder")))
	var centro := (izq + der) * 0.5
	var afuera := p_sh - centro
	afuera.y = 0.0
	return afuera.normalized() if afuera.length_squared() > 0.000001 else Vector3.ZERO

## Regenera el clip GuardiaAlas con los valores actuales de las perillas.
## Se llama sola al cambiarlas (setter): ajuste en vivo durante el juego.
func _regen_guardia() -> void:
	if not is_inside_tree() or anim_player == null:
		return  # al cargar la escena todavía no hay nada que regenerar
	if not anim_player.has_animation_library(LIBRARY_NAME):
		return  # las bibliotecas no están (o aún no) cargadas
	var lib := anim_player.get_animation_library(LIBRARY_NAME)
	var estaba := anim_player.current_animation == LIBRARY_NAME + "/GuardiaAlas"
	if estaba:
		anim_player.stop()  # para poder reemplazar el clip sin errores
	if lib.has_animation("GuardiaAlas"):
		lib.remove_animation("GuardiaAlas")
	var guardia := _clip_guardia_alas()
	if guardia != null:
		lib.add_animation("GuardiaAlas", guardia)
	if estaba:
		anim_player.play(LIBRARY_NAME + "/GuardiaAlas")

func _pos_global_rest(idx: int) -> Vector3:
	if idx < 0:
		return Vector3.ZERO
	return _skeleton.get_bone_global_rest(idx).origin

## Fija la dirección de un hueso (de su origen hacia su primer hijo) hacia
## dir_modelo (espacio del modelo). Escribe UNA clave estática: la pose se
## mantiene constante mientras el resto del cuerpo respira con el Idle.
func _poner_direccion(clip: Animation, idx_hueso: int, dir_modelo: Vector3, t: float = 0.0) -> bool:
	var idx_padre := _skeleton.get_bone_parent(idx_hueso)
	if idx_padre < 0:
		return false
	# Dirección ACTUAL del segmento: hueso -> su primer hijo.
	var hijo := -1
	for i in _skeleton.get_bone_count():
		if _skeleton.get_bone_parent(i) == idx_hueso:
			hijo = i
			break
	var dir_actual := Vector3(0.0, 1.0, 0.0)
	if hijo >= 0:
		dir_actual = (_pos_global_rest(hijo) - _pos_global_rest(idx_hueso)).normalized()
	if dir_actual.length_squared() < 0.5 or dir_modelo.length_squared() < 0.5:
		return false
	var q_delta := Quaternion(dir_actual.normalized(), dir_modelo.normalized())
	var q_padre := _skeleton.get_bone_global_rest(idx_padre).basis.get_rotation_quaternion()
	var q_local := q_padre.inverse() * q_delta * q_padre * _rest_q_local(idx_hueso)
	var ruta := _ruta_esqueleto + ":" + _skeleton.get_bone_name(idx_hueso)
	var idx := clip.find_track(NodePath(ruta), Animation.TYPE_ROTATION_3D)
	if idx < 0:
		idx = clip.add_track(Animation.TYPE_ROTATION_3D)
		clip.track_set_path(idx, NodePath(ruta))
	clip.rotation_track_insert_key(idx, t, q_local)
	return true

func _rest_q_local(idx: int) -> Quaternion:
	return _skeleton.get_bone_rest(idx).basis.get_rotation_quaternion()

func _es_brazo(hueso: String) -> bool:
	return (hueso.begins_with("Left") or hueso.begins_with("Right")) \
		and (hueso.contains("Arm") or hueso.contains("Hand"))

func _quitar_pistas_brazo(clip: Animation) -> void:
	for i in range(clip.get_track_count() - 1, -1, -1):
		var np := clip.track_get_path(i)
		if np.get_subname_count() > 0 and _es_brazo(String(np.get_subname(0))):
			clip.remove_track(i)

# --- piernas / postura / pies ---

## Crea un tercer AnimationPlayer solo para las piernas, con el recorte
## de piernas de Swim_Idle del personaje base (mismo esqueleto, sin retarget).
## NOTA: desactivada por decisión de diseño (las piernas de vuelo las anima
## el clip Jump base enderezado). Se conserva por si se reactiva.
func _armar_piernas_player() -> void:
	var clip_base := _buscar_clip_base(CLIP_PIERNAS_FUENTE)
	if clip_base.is_empty():
		push_warning("UAL2 loader: no encontré " + CLIP_PIERNAS_FUENTE + " en el AnimationPlayer principal")
		return
	var piernas := _clip_solo_piernas(anim_player.get_animation(clip_base))
	piernas.loop_mode = Animation.LOOP_LINEAR
	piernas = _juntar_piernas(piernas)
	piernas = _apuntar_pies(piernas)

	var overlay := AnimationPlayer.new()
	overlay.name = PIERNAS_PLAYER_NAME
	overlay.root_node = anim_player.root_node
	anim_player.get_parent().add_child(overlay)
	overlay.add_to_group("ual2_piernas_player")

	var lib := AnimationLibrary.new()
	lib.add_animation(CLIP_PIERNAS_FUENTE, piernas)
	overlay.add_animation_library(LIB_PIERNAS, lib)
	print("UAL2 loader: piernas -> ", lib.get_animation_list())

func _buscar_clip_base(nombre: String) -> String:
	if anim_player.has_animation(nombre):
		return nombre
	var sufijo := "/" + nombre
	for c in anim_player.get_animation_list():
		if String(c).ends_with(sufijo):
			return String(c)
	return ""

func _clip_solo_piernas(clip: Animation) -> Animation:
	var nueva: Animation = clip.duplicate(true)
	for i in range(nueva.get_track_count() - 1, -1, -1):
		var np: NodePath = nueva.track_get_path(i)
		if np.get_subname_count() == 0:
			nueva.remove_track(i)
			continue
		if not _es_hueso_pierna(String(np.get_subname(0))):
			nueva.remove_track(i)
	return nueva

func _es_hueso_pierna(hueso: String) -> bool:
	for palabra in PALABRAS_PIERNAS:
		if hueso.contains(palabra):
			return true
	return false

## Endereza la base Jump (Hips/Spine/Chest) y la reemplaza en su biblioteca,
## para que el cuerpo de vuelo quede más erguido. Ojo: también afecta los
## saltos comunes (quedan más rectos); si molesta, después lo separamos.
func _enderezar_jump_base() -> void:
	var nombre_base := _buscar_clip_base("Jump")
	if nombre_base.is_empty():
		push_warning("UAL2 loader: no encontré Jump para enderezar")
		return
	for lib_name in anim_player.get_animation_library_list():
		var lib := anim_player.get_animation_library(lib_name)
		if lib.has_animation(nombre_base):
			lib.add_animation(nombre_base, _enderezar_postura(anim_player.get_animation(nombre_base)))
			return

## Jump con piernas recogidas (para el planeo/avance en vuelo).
## Copia el Jump enderezado y acerca las piernas a rest con piernas_juntas.
func _armar_jump_planeo() -> void:
	var nombre_base := _buscar_clip_base("Jump")
	if nombre_base.is_empty():
		return
	var clip := _enderezar_postura(anim_player.get_animation(nombre_base).duplicate(true))
	clip = _juntar_piernas(clip)
	for lib_name in anim_player.get_animation_library_list():
		var lib := anim_player.get_animation_library(lib_name)
		if lib.has_animation(nombre_base):
			if lib.has_animation("Jump_Planeo"):
				lib.remove_animation("Jump_Planeo")
			lib.add_animation("Jump_Planeo", clip)
			print("UAL2 loader: Jump_Planeo generado (piernas recogidas para el avance).")
			return

## Gira las pistas de rotación de los huesos de postura hacia su rest pose.
func _enderezar_postura(clip: Animation) -> Animation:
	if _skeleton == null or enderezado_postura <= 0.0:
		return clip
	var nueva: Animation = clip.duplicate(true)
	var conservar := 1.0 - enderezado_postura

	for i in range(nueva.get_track_count()):
		if nueva.track_get_type(i) != Animation.TYPE_ROTATION_3D:
			continue
		var np: NodePath = nueva.track_get_path(i)
		if np.get_subname_count() == 0:
			continue
		var hueso := String(np.get_subname(0))
		if not HUESOS_POSTURA.has(hueso):
			continue
		var idx_hueso := _skeleton.find_bone(_hueso(hueso))
		if idx_hueso < 0:
			continue
		var rest_q: Quaternion = _skeleton.get_bone_rest(idx_hueso).basis.get_rotation_quaternion()
		for k in range(nueva.track_get_key_count(i)):
			var t := nueva.track_get_key_time(i, k)
			var q: Quaternion = nueva.track_get_key_value(i, k)
			nueva.rotation_track_insert_key(i, t, rest_q.slerp(q, conservar))
	return nueva

func _juntar_piernas(clip: Animation) -> Animation:
	return _aproximar_a_rest(clip, HUESOS_PIERNAS_NEUTRAS, piernas_juntas)

## Mezcla las pistas de rotación de los huesos indicados hacia su rest pose.
func _aproximar_a_rest(clip: Animation, huesos: Array, factor: float) -> Animation:
	if _skeleton == null or factor <= 0.0:
		return clip
	var nueva: Animation = clip.duplicate(true)
	var conservar := 1.0 - factor

	for i in range(nueva.get_track_count()):
		if nueva.track_get_type(i) != Animation.TYPE_ROTATION_3D:
			continue
		var np: NodePath = nueva.track_get_path(i)
		if np.get_subname_count() == 0:
			continue
		var hueso := String(np.get_subname(0))
		if not huesos.has(hueso):
			continue
		var idx_hueso := _skeleton.find_bone(_hueso(hueso))
		if idx_hueso < 0:
			continue
		var rest_q: Quaternion = _skeleton.get_bone_rest(idx_hueso).basis.get_rotation_quaternion()
		for k in range(nueva.track_get_key_count(i)):
			var t := nueva.track_get_key_time(i, k)
			var q: Quaternion = nueva.track_get_key_value(i, k)
			nueva.rotation_track_insert_key(i, t, rest_q.slerp(q, conservar))
	return nueva

## Gira los huesos de los pies alrededor de su eje X local para puntarlos
## (flexión plantar). Estático: la punta se mantiene en todo el clip.
func _apuntar_pies(clip: Animation) -> Animation:
	if _skeleton == null or is_zero_approx(punta_pies_grados):
		return clip
	var nueva: Animation = clip.duplicate(true)
	var extra := Quaternion(Vector3(1.0, 0.0, 0.0), deg_to_rad(punta_pies_grados))

	for i in range(nueva.get_track_count()):
		if nueva.track_get_type(i) != Animation.TYPE_ROTATION_3D:
			continue
		var np: NodePath = nueva.track_get_path(i)
		if np.get_subname_count() == 0:
			continue
		var hueso := String(np.get_subname(0))
		if not hueso.contains("Foot"):
			continue
		for k in range(nueva.track_get_key_count(i)):
			var t := nueva.track_get_key_time(i, k)
			var q: Quaternion = nueva.track_get_key_value(i, k)
			nueva.rotation_track_insert_key(i, t, extra * q)
	return nueva


# --- Patada de garras (lanzamiento del agarre aéreo) ---

## Genera "PatadaGarra": doble patada hacia adelante con ambas piernas
## (golpe de águila). Clip DINÁMICO generado por código: 3 claves por
## segmento de pierna (rest -> extendido -> rest) en 0.45 s. Igual que la
## GuardiaAlas: por DIRECCIONES en espacio modelo (+Z = adelante), sin
## depender de clips externos.
func _armar_patada_garra() -> Animation:
	if _skeleton == null:
		push_warning("UAL2 loader: sin esqueleto, no genero PatadaGarra")
		return null
	# [nombre principal, nombre alternativo, dirección del segmento en el
	#  pico de la patada]. Muslos ~40° hacia adelante; piernas casi
	# extendidas (~70°): las garras sonpean adelante-abajo.
	var segmentos := [
		["LeftUpperLeg", "LeftUpLeg", Vector3(0.0, -0.75, 0.66)],
		["RightUpperLeg", "RightUpLeg", Vector3(0.0, -0.75, 0.66)],
		["LeftLowerLeg", "LeftLeg", Vector3(0.0, -0.35, 0.94)],
		["RightLowerLeg", "RightLeg", Vector3(0.0, -0.35, 0.94)],
	]
	var patada := Animation.new()
	patada.length = 0.45
	var ok := false
	for seg: Array in segmentos:
		var idx := _skeleton.find_bone(_hueso(String(seg[0])))
		if idx < 0:
			idx = _skeleton.find_bone(_hueso(String(seg[1])))
		if idx < 0:
			continue
		var dir_objetivo: Vector3 = seg[2]
		# Dirección ACTUAL del segmento: hueso -> su primer hijo.
		var hijo := -1
		for i in _skeleton.get_bone_count():
			if _skeleton.get_bone_parent(i) == idx:
				hijo = i
				break
		if hijo < 0:
			continue
		var dir_actual := (_pos_global_rest(hijo) - _pos_global_rest(idx)).normalized()
		if dir_actual.length_squared() < 0.5:
			continue
		var q_delta := Quaternion(dir_actual, dir_objetivo.normalized())
		var idx_padre := _skeleton.get_bone_parent(idx)
		var q_kick := q_delta * _rest_q_local(idx)
		if idx_padre >= 0:
			var q_padre := _skeleton.get_bone_global_rest(idx_padre).basis.get_rotation_quaternion()
			q_kick = q_padre.inverse() * q_delta * q_padre * _rest_q_local(idx)
		var ruta := _ruta_esqueleto + ":" + _skeleton.get_bone_name(idx)
		var t := patada.add_track(Animation.TYPE_ROTATION_3D)
		patada.track_set_path(t, NodePath(ruta))
		var rest_q := _rest_q_local(idx)
		patada.rotation_track_insert_key(t, 0.0, rest_q)
		patada.rotation_track_insert_key(t, 0.14, q_kick)
		patada.rotation_track_insert_key(t, 0.34, rest_q)
		ok = true
	if not ok:
		push_warning("UAL2 loader: no encontré huesos de pierna; no genero PatadaGarra")
		return null
	return patada


# --- Planeo congelado (régimen de alta velocidad del vuelo) ---

## Genera "Planeo": pose ESTÁTICA de planeo. Cuerpo = Jump_Planeo (piernas
## recogidas) + brazos extendidos hacia afuera-arriba (alas). Misma técnica
## que la GuardiaAlas: por DIRECCIONES (hombro -> punto). Loop con pose
## única: se sostiene sola mientras dura el crucero rápido.
func _armar_planeo() -> void:
	if not planeo_activado:
		return
	var base := _buscar_clip_base("Jump_Planeo")
	if base.is_empty() or _skeleton == null:
		push_warning("UAL2 loader: sin Jump_Planeo o sin esqueleto; no genero Planeo")
		return
	var planeo: Animation = anim_player.get_animation(base).duplicate(true)
	_quitar_pistas_brazo(planeo)
	var ok := _extender_ala(planeo, "Left")
	ok = _extender_ala(planeo, "Right") and ok
	if not ok:
		push_warning("UAL2 loader: sin huesos de brazo; no genero Planeo")
		return
	planeo.length = 1.2
	planeo.loop_mode = Animation.LOOP_LINEAR
	var nombre_lib := ""
	if base.contains("/"):
		nombre_lib = base.get_slice("/", 0)
	var lib := anim_player.get_animation_library(nombre_lib)
	if lib.has_animation("Planeo"):
		lib.remove_animation("Planeo")
	lib.add_animation("Planeo", planeo)
	print("UAL2 loader: Planeo generado (pose congelada de alas).")

## Extiende UN brazo como ala: upper y lower apuntan hacia afuera-arriba.
func _extender_ala(planeo: Animation, lado: String) -> bool:
	var upper := _skeleton.find_bone(_hueso(lado + "UpperArm"))
	var lower := _skeleton.find_bone(_hueso(lado + "LowerArm"))
	var sh := _skeleton.find_bone(_hueso(lado + "Shoulder"))
	if upper < 0 or lower < 0 or sh < 0:
		return false
	var p_sh := _pos_global_rest(sh)
	if p_sh == Vector3.ZERO:
		p_sh = _pos_global_rest(upper)
	var afuera := _hacia_afuera(p_sh)
	if afuera.length_squared() < 0.000001:
		afuera = Vector3(1.0 if lado == "Left" else -1.0, 0.0, 0.0)
	var punto_upper := p_sh \
		+ afuera * planeo_brazos_afuera \
		+ Vector3(0.0, planeo_brazos_arriba, 0.0)
	var punto_lower := punto_upper \
		+ afuera * (planeo_brazos_afuera * 0.9) \
		+ Vector3(0.0, planeo_brazos_arriba * 0.3, 0.0)
	var ok := true
	ok = _poner_direccion(planeo, upper, (punto_upper - p_sh).normalized()) and ok
	var p_lo := _pos_global_rest(lower)
	ok = _poner_direccion(planeo, lower, (punto_lower - p_lo).normalized()) and ok
	return ok


## Saca las pistas de ROTACIÓN del hueso Root de un clip (giros horneados
## que pelean con el yaw que maneja el código). NO toca la posición.
func _quitar_giro_raiz(anim: Animation) -> void:
	for i in range(anim.get_track_count() - 1, -1, -1):
		var np: NodePath = anim.track_get_path(i)
		if anim.track_get_type(i) == Animation.TYPE_ROTATION_3D \
				and np.get_subname_count() > 0 \
				and String(np.get_subname(0)).to_lower() == "root":
			anim.remove_track(i)


## El aleteo de la SUBIDA usa DoubleJump de BRAZOS en loop (el cuerpo
## mantiene Jump con las piernas aprobadas). Le saca el giro horneado
## del Root a la copia del overlay, que pelearia con el yaw del codigo.
func _aleteo_brazos_loop(_overlay: AnimationPlayer, lib: AnimationLibrary) -> void:
	if lib.has_animation("DoubleJump"):
		var dj: Animation = lib.get_animation("DoubleJump")
		dj.loop_mode = Animation.LOOP_LINEAR
		_quitar_giro_raiz(dj)


## Genera "PosePicado": brazos pegados al costado-atras y piernas juntas
## (aerodinamica del dive-bomb). Cuerpo = Jump con piernas unidas.
func _armar_pose_picado() -> void:
	var base := _buscar_clip_base("Jump")
	if base.is_empty() or _skeleton == null:
		push_warning("UAL2 loader: sin Jump; no genero PosePicado")
		return
	var picado: Animation = anim_player.get_animation(base).duplicate(true)
	picado = _juntar_piernas(picado)
	_quitar_pistas_brazo(picado)
	var ok := _brazo_picado(picado, "Left")
	ok = _brazo_picado(picado, "Right") and ok
	if not ok:
		push_warning("UAL2 loader: sin huesos de brazo; no genero PosePicado")
		return
	picado.length = 1.2
	picado.loop_mode = Animation.LOOP_LINEAR
	var nombre_lib := ""
	if base.contains("/"):
		nombre_lib = base.get_slice("/", 0)
	var lib := anim_player.get_animation_library(nombre_lib)
	if lib.has_animation("PosePicado"):
		lib.remove_animation("PosePicado")
	lib.add_animation("PosePicado", picado)
	print("UAL2 loader: PosePicado generada (brazos al costado, piernas juntas).")

## Brazos del picado: upper y lower barridos hacia el costado-atras del cuerpo.
func _brazo_picado(picado: Animation, lado: String) -> bool:
	var upper := _skeleton.find_bone(_hueso(lado + "UpperArm"))
	var lower := _skeleton.find_bone(_hueso(lado + "LowerArm"))
	var sh := _skeleton.find_bone(_hueso(lado + "Shoulder"))
	if upper < 0 or lower < 0 or sh < 0:
		return false
	var p_sh := _pos_global_rest(sh)
	if p_sh == Vector3.ZERO:
		p_sh = _pos_global_rest(upper)
	var afuera := _hacia_afuera(p_sh)
	if afuera.length_squared() < 0.000001:
		afuera = Vector3(1.0 if lado == "Left" else -1.0, 0.0, 0.0)
	var atras := Vector3(0.0, 0.0, -1.0)  # el maniqui mira +Z
	var punto_upper := p_sh + afuera * 0.30 + Vector3(0.0, -0.10, 0.0) + atras * 0.18
	var p_lo := _pos_global_rest(lower)
	var punto_lower := p_lo + afuera * 0.45 + Vector3(0.0, -0.28, 0.0) + atras * 0.10
	var ok := true
	ok = _poner_direccion(picado, upper, (punto_upper - p_sh).normalized()) and ok
	ok = _poner_direccion(picado, lower, (punto_lower - p_lo).normalized()) and ok
	return ok

## Genera "VueloHeroe": vuelo estilo superman — puño derecho estirado al
## frente, brazo izquierdo pegado al cuerpo, piernas rectas y juntas con
## puntas extendidas. La inclinación horizontal del cuerpo la pone el
## controller al volar (el clip es la pose en espacio del cuerpo).
func _armar_vuelo_heroe() -> void:
	var base := _buscar_clip_base("Jump")
	if base.is_empty() or _skeleton == null:
		push_warning("UAL2 loader: sin Jump; no genero VueloHeroe")
		return
	var heroe: Animation = anim_player.get_animation(base).duplicate(true)
	# Piernas rectas y juntas (rest completo de las piernas neutras).
	heroe = _aproximar_a_rest(heroe, HUESOS_PIERNAS_NEUTRAS, 1.0)
	_quitar_pistas_brazo(heroe)
	var ok := _brazo_heroe(heroe, "Right")
	ok = _brazo_heroe(heroe, "Left") and ok
	if not ok:
		push_warning("UAL2 loader: sin huesos de brazo; no genero VueloHeroe")
		return
	heroe = _apuntar_pies(heroe)
	heroe.length = 1.2
	heroe.loop_mode = Animation.LOOP_LINEAR
	var nombre_lib := ""
	if base.contains("/"):
		nombre_lib = base.get_slice("/", 0)
	var lib := anim_player.get_animation_library(nombre_lib)
	if lib.has_animation("VueloHeroe"):
		lib.remove_animation("VueloHeroe")
	lib.add_animation("VueloHeroe", heroe)
	print("UAL2 loader: VueloHeroe generado (superman: puño al frente, piernas rectas).")

## Brazo del vuelo héroe: Right = estirado al frente (+Z; el maniqui mira
## +Z); Left = pegado al costado, levemente atras.
func _brazo_heroe(clip: Animation, lado: String) -> bool:
	var upper := _skeleton.find_bone(_hueso(lado + "UpperArm"))
	var lower := _skeleton.find_bone(_hueso(lado + "LowerArm"))
	var sh := _skeleton.find_bone(_hueso(lado + "Shoulder"))
	if upper < 0 or lower < 0 or sh < 0:
		return false
	var p_sh := _pos_global_rest(sh)
	if p_sh == Vector3.ZERO:
		p_sh = _pos_global_rest(upper)
	var alante := Vector3(0.0, 0.0, 1.0)  # el maniqui mira +Z
	var abajo := Vector3(0.0, -1.0, 0.0)
	var ok := true
	if lado == "Right":
		ok = _poner_direccion(clip, upper, alante) and ok
		ok = _poner_direccion(clip, lower, alante) and ok
	else:
		var afuera := _hacia_afuera(p_sh)
		if afuera.length_squared() < 0.000001:
			afuera = Vector3(1.0, 0.0, 0.0)
		var costado := (abajo + afuera * 0.15 + Vector3(0.0, 0.0, -0.3)).normalized()
		ok = _poner_direccion(clip, upper, costado) and ok
		ok = _poner_direccion(clip, lower, (abajo + Vector3(0.0, 0.0, -0.2)).normalized()) and ok
	return ok

## Genera "PalmazoPush": secuencia Push_Enter -> Push -> Push_Exit de
## UAL1 (standard del maniqui o source), recortada a torso+brazos (las
## piernas quedan para la base) y encadenada en UN solo clip. El palmazo
## la reproduce a velocidad acorde por el overlay del cuerpo.
func _armar_palmazo_push() -> void:
	if _skeleton == null:
		return
	var partes := {}
	for par in [["Enter", "Push_Enter"], ["Push", "Push"], ["Exit", "Push_Exit"]]:
		var clip := _clip_push_fuente(String(par[1]))
		if clip != null:
			partes[String(par[0])] = clip
	if not partes.has("Push"):
		push_warning("UAL2 loader: sin clips Push en UAL1; no genero PalmazoPush")
		return
	var orden: Array = []
	if partes.has("Enter"):
		orden.append("Enter")
	orden.append("Push")
	if partes.has("Exit"):
		orden.append("Exit")
	var total := Animation.new()
	total.step = 0.033
	var offset := 0.0
	for clave in orden:
		var fuente: Animation = partes[clave]
		var recorte := _clip_parte_superior(_retarget_clip(fuente, ""))
		for i in recorte.get_track_count():
			var tipo := recorte.track_get_type(i)
			var ti := total.find_track(recorte.track_get_path(i), tipo)
			if ti < 0:
				ti = total.add_track(tipo)
				total.track_set_path(ti, recorte.track_get_path(i))
				total.track_set_interpolation_type(ti, recorte.track_get_interpolation_type(i))
			for k in recorte.track_get_key_count(i):
				total.track_insert_key(ti, offset + recorte.track_get_key_time(i, k), recorte.track_get_key_value(i, k))
		offset += recorte.length
	total.length = offset
	var lib := anim_player.get_animation_library(LIBRARY_NAME)
	if lib.has_animation("PalmazoPush"):
		lib.remove_animation("PalmazoPush")
	lib.add_animation("PalmazoPush", total)
	print("UAL2 loader: PalmazoPush generado (solo torso+brazos; partes: ", orden, ").")

## Busca un clip Push: primero en el maniqui (UAL1 Standard ya cargado),
## despues en los GLB de source de UAL1, despues en las fuentes comunes.
func _clip_push_fuente(nombre: String) -> Animation:
	var en_base := _buscar_clip_base(nombre)
	if not en_base.is_empty():
		return anim_player.get_animation(en_base)
	var rutas_ual1 := [
		["res://animations/UAL1/_ALL_SOURCE_ANIMS_1.glb",
		 "res://animaciones/UAL1/_ALL_SOURCE_ANIMS_1.glb"],
		["res://animations/UAL1/UAL1_Standard.glb",
		 "res://animaciones/UAL1/UAL1_Standard.glb"],
	]
	for candidatos in rutas_ual1:
		var ruta_usada := ""
		for r in candidatos:
			if ResourceLoader.exists(r):
				ruta_usada = r
				break
		if ruta_usada == "":
			continue
		var packed: PackedScene = load(ruta_usada)
		if packed == null:
			continue
		var src: Node = packed.instantiate()
		var src_ap := _animation_player_de(src)
		if src_ap != null:
			for clip in src_ap.get_animation_list():
				var limpio := String(clip).replace("UAL2_Source_", "").replace("UAL1_Source_", "")
				if limpio == nombre:
					var anim: Animation = src_ap.get_animation(clip)
					src.queue_free()
					return anim
		src.queue_free()
	for candidatos in FUENTES_CANDIDATAS:
		var source_scene := _primera_existente(candidatos)
		if source_scene.is_empty():
			continue
		var packed2: PackedScene = load(source_scene)
		if packed2 == null:
			continue
		var src2: Node = packed2.instantiate()
		var src_ap2 := _animation_player_de(src2)
		if src_ap2 != null:
			for clip2 in src_ap2.get_animation_list():
				var limpio2 := String(clip2).replace("UAL2_Source_", "").replace("UAL1_Source_", "")
				if limpio2 == nombre:
					var anim2: Animation = src_ap2.get_animation(clip2)
					src2.queue_free()
					return anim2
		src2.queue_free()
	return null

## Genera "CaidaLibre": cuerpo del Idle + brazos rectos hacia ARRIBA
## (dejarse caer sin direccion).
func _armar_caida_libre() -> void:
	var base := _buscar_clip_base("Idle")
	if base.is_empty() or _skeleton == null:
		push_warning("UAL2 loader: sin Idle; no genero CaidaLibre")
		return
	var caida: Animation = anim_player.get_animation(base).duplicate(true)
	_quitar_pistas_brazo(caida)
	var ok := _brazos_arriba(caida, "Left")
	ok = _brazos_arriba(caida, "Right") and ok
	if not ok:
		push_warning("UAL2 loader: sin huesos de brazo; no genero CaidaLibre")
		return
	var nombre_lib := ""
	if base.contains("/"):
		nombre_lib = base.get_slice("/", 0)
	var lib := anim_player.get_animation_library(nombre_lib)
	if lib.has_animation("CaidaLibre"):
		lib.remove_animation("CaidaLibre")
	lib.add_animation("CaidaLibre", caida)
	print("UAL2 loader: CaidaLibre generada (brazos hacia arriba).")

func _brazos_arriba(caida: Animation, lado: String) -> bool:
	var upper := _skeleton.find_bone(_hueso(lado + "UpperArm"))
	var lower := _skeleton.find_bone(_hueso(lado + "LowerArm"))
	var sh := _skeleton.find_bone(_hueso(lado + "Shoulder"))
	if upper < 0 or lower < 0 or sh < 0:
		return false
	var p_sh := _pos_global_rest(sh)
	if p_sh == Vector3.ZERO:
		p_sh = _pos_global_rest(upper)
	var afuera := _hacia_afuera(p_sh)
	var p_lo := _pos_global_rest(lower)
	var punto_upper := p_sh + Vector3(0.0, 0.45, 0.0) + afuera * 0.06
	var punto_lower := p_lo + Vector3(0.0, 0.50, 0.0)
	var ok := true
	ok = _poner_direccion(caida, upper, (punto_upper - p_sh).normalized()) and ok
	ok = _poner_direccion(caida, lower, (punto_lower - p_lo).normalized()) and ok
	return ok


## Genera "AleteoAlas": el planeo que ALETEA. Cuerpo de Jump_Planeo
## (piernas recogidas) + brazos-alas con golpe de ala hacia ABAJO en loop:
## extendidas (t=0) -> barridas al piso (t=0.3, el empuje) -> recuperacion
## (t=0.8). Es el empuje visible de "estoy sosteniendome volando".
func _armar_aleteo_alas() -> void:
	var base := _buscar_clip_base("Jump_Planeo")
	if base.is_empty() or _skeleton == null:
		push_warning("UAL2 loader: sin Jump_Planeo; no genero AleteoAlas")
		return
	var alas: Animation = anim_player.get_animation(base).duplicate(true)
	_quitar_pistas_brazo(alas)
	var ok := _ala_aleteo(alas, "Left")
	ok = _ala_aleteo(alas, "Right") and ok
	if not ok:
		push_warning("UAL2 loader: sin huesos de brazo; no genero AleteoAlas")
		return
	alas.length = 0.8
	alas.loop_mode = Animation.LOOP_LINEAR
	var nombre_lib := ""
	if base.contains("/"):
		nombre_lib = base.get_slice("/", 0)
	var lib := anim_player.get_animation_library(nombre_lib)
	if lib.has_animation("AleteoAlas"):
		lib.remove_animation("AleteoAlas")
	lib.add_animation("AleteoAlas", alas)
	print("UAL2 loader: AleteoAlas generado (golpe de ala hacia abajo).")

## Escribe las 3 claves del ciclo de aleteo para UN ala.
func _ala_aleteo(alas: Animation, lado: String) -> bool:
	var upper := _skeleton.find_bone(_hueso(lado + "UpperArm"))
	var lower := _skeleton.find_bone(_hueso(lado + "LowerArm"))
	var sh := _skeleton.find_bone(_hueso(lado + "Shoulder"))
	if upper < 0 or lower < 0 or sh < 0:
		return false
	var p_sh := _pos_global_rest(sh)
	if p_sh == Vector3.ZERO:
		p_sh = _pos_global_rest(upper)
	var p_lo := _pos_global_rest(lower)
	var afuera := _hacia_afuera(p_sh)
	if afuera.length_squared() < 0.000001:
		afuera = Vector3(1.0 if lado == "Left" else -1.0, 0.0, 0.0)
	var arriba := Vector3(0.0, 0.30, 0.0)
	var abajo := Vector3(0.0, -0.55, 0.0)
	# Puntos objetivo del SEGMENTO superior en cada fase.
	var fase_arriba := p_sh + afuera * 0.45 + arriba
	var fase_abajo := p_sh + afuera * 0.22 + abajo
	var ok := true
	for fase in [[0.0, fase_arriba], [0.3, fase_abajo], [0.8, fase_arriba]]:
		var t: float = fase[0]
		var punto: Vector3 = fase[1]
		# El lower sigue al upper con una leve flexion en el golpe.
		var punto_lower := punto \
			+ afuera * (0.40 if t == 0.0 else 0.30) \
			+ (Vector3(0.0, 0.10, 0.0) if t == 0.0 else Vector3(0.0, -0.05, 0.0))
		ok = _poner_direccion(alas, upper, (punto - p_sh).normalized(), t) and ok
		ok = _poner_direccion(alas, lower, (punto_lower - p_lo).normalized(), t) and ok
	return ok
