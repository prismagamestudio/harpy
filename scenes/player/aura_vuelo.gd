extends Node
## AuraVuelo — aura de héroe al volar: partículas de viento que suben por
## el cuerpo + una luz suave del mismo color. Prende al volar (fade in),
## se apaga al aterrizar (fade out) y se intensifica con la velocidad.
## Autocontenida: colgala del Player y nada más (no depende de estelas).
##
## Setup: nodo Node hijo del Player con este script (nada más).

## Color del aura (partículas y luz).
@export var color_aura: Color = Color(0.55, 0.8, 1.0):
	set(v):
		color_aura = v
		_actualizar_colores()
## Cantidad máxima de partículas.
@export_range(20, 600, 10) var cantidad: int = 220:
	set(v):
		cantidad = v
		if _particulas != null:
			_particulas.amount = v
## Intensidad de la luz del aura (0 = sin luz).
@export_range(0.0, 6.0, 0.1) var luz_intensidad: float = 1.4
## Alcance de la luz (metros).
@export_range(1.0, 12.0, 0.5) var alcance_luz: float = 4.0
## Qué tan fuerte suben las partículas.
@export_range(0.0, 4.0, 0.1) var velocidad_subida: float = 1.6
## Tamaño de las motas de viento.
@export_range(0.02, 0.3, 0.01) var tamano: float = 0.09
## Aura mínima al volar quieto/lando (la velocidad la sube hasta 1).
@export_range(0.0, 1.0, 0.05) var intensidad_base: float = 0.55
## Qué tan rápido prende/apaga (por segundo).
@export_range(1.0, 12.0, 0.5) var suavizado: float = 6.0
## Extra de extensión vertical de la zona de emisión.
@export_range(0.5, 3.0, 0.1) var altura_cuerpo: float = 1.9
## MODO PRUEBA: aura SIEMPRE prendida. Arranca ON para que VERIFIQUES
## el visual y que siga al cuerpo; para el vuelo real dejala en OFF.
@export var modo_prueba: bool = true

var _particulas: GPUParticles3D = null
var _luz: OmniLight3D = null
var _mat_particulas: StandardMaterial3D = null
var _intensidad: float = 0.0
var _flight: Node = null
var _estado_volando: bool = false

func _ready() -> void:
	# Diferido: el re-parent necesita el árbol quieto.
	call_deferred("_inicializar")

func _inicializar() -> void:
	_asegurar_bajo_player()
	_buscar_flight()
	var nombre_flight: String = "NO ENCONTRADO"
	if _flight != null:
		nombre_flight = String(_flight.name)
	print("[Aura] Controlador de vuelo: ", nombre_flight)
	_armar_particulas()
	_armar_luz()
	_actualizar_colores()

## El aura DEBE colgar del Player para seguirlo. Si la colgaron de otro
## lado (raíz de la arena, etc.), se re-parenta sola y avisa.
func _asegurar_bajo_player() -> void:
	var player := _encontrar_player()
	if player == null:
		print("[Aura] Player no encontrado: el aura queda ESTÁTICA.")
		return
	if get_parent() == player:
		return
	var viejo := get_parent()
	get_parent().remove_child(self)
	player.add_child(self)
	# El nodo aura es un Node simple (sin transform): sus hijos
	# (particulas y luz) ya guardan sus propios offsets locales.
	print("[Aura] Re-parentada bajo el Player (antes colgaba de ", viejo.name, ").")

## Busca al Player: ancestros -> grupo "player" -> nodo llamado Player.
func _encontrar_player() -> Node:
	var actual := get_parent()
	while actual != null:
		if actual is CharacterBody3D:
			return actual
		actual = actual.get_parent()
	var por_grupo := get_tree().get_first_node_in_group("player")
	if por_grupo != null:
		return por_grupo
	var escena := get_tree().current_scene
	if escena != null:
		return _buscar_descendiente(escena, "Player")
	return null

func _buscar_descendiente(nodo: Node, nombre: String) -> Node:
	for hijo in nodo.get_children():
		if String(hijo.name) == nombre:
			return hijo
		var r := _buscar_descendiente(hijo, nombre)
		if r != null:
			return r
	return null

## Busca el controlador de vuelo: por nombre y, si no, barre los hijos
## del Player buscando quien entienda "is_flying" (a prueba de nombres).
func _buscar_flight() -> void:
	_flight = get_node_or_null("../FlightController")
	if _flight != null:
		return
	var padre := get_parent()
	if padre == null:
		return
	for hijo in padre.get_children():
		if hijo == self:
			continue
		if hijo.get("is_flying") != null:
			_flight = hijo
			return

func _armar_particulas() -> void:
	_particulas = GPUParticles3D.new()
	_particulas.amount = cantidad
	_particulas.lifetime = 0.9
	_particulas.preprocess = 0.6
	_particulas.emitting = true
	# Coordenadas LOCALES: la nube viaja pegada al cuerpo (aura que abraza,
	# estilo Linterna Verde) en vez de quedarse atras como estela.
	_particulas.local_coords = true
	var mat := ParticleProcessMaterial.new()
	# El shape de emision vive en el MATERIAL de proceso (no en el nodo).
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(0.45, altura_cuerpo * 0.5, 0.35)
	mat.direction = Vector3(0.0, 1.0, 0.0)
	mat.spread = 18.0
	mat.initial_velocity_min = 0.4
	mat.initial_velocity_max = 0.9
	mat.gravity = Vector3(0.0, velocidad_subida, 0.0)
	mat.scale_min = 0.5
	mat.scale_max = 1.0
	_particulas.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(tamano, tamano)
	_mat_particulas = StandardMaterial3D.new()
	_mat_particulas.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_particulas.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_particulas.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat_particulas.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_mat_particulas.vertex_color_use_as_albedo = true
	_mat_particulas.disable_receive_shadows = true
	quad.material = _mat_particulas
	_particulas.draw_pass_1 = quad
	add_child(_particulas)
	_particulas.position = Vector3(0.0, altura_cuerpo * 0.5, 0.0)
	_particulas.amount_ratio = 0.0

func _armar_luz() -> void:
	_luz = OmniLight3D.new()
	_luz.omni_range = alcance_luz
	_luz.light_energy = 0.0
	add_child(_luz)
	_luz.position = Vector3(0.0, altura_cuerpo * 0.6, 0.0)

func _actualizar_colores() -> void:
	if _mat_particulas != null:
		_mat_particulas.albedo_color = color_aura
	if _luz != null:
		_luz.light_color = color_aura

func _process(delta: float) -> void:
	if _particulas == null:
		return
	var volando: bool = modo_prueba
	if not volando and _flight != null:
		volando = bool(_flight.get("is_flying"))
	var ratio: float = 0.0
	if volando and _flight != null and _flight.has_method("ratio_velocidad"):
		ratio = clampf(float(_flight.call("ratio_velocidad")), 0.0, 1.0)
	var objetivo: float = 0.0
	if volando:
		objetivo = clampf(intensidad_base + ratio * (1.0 - intensidad_base), 0.0, 1.0)
	if volando != _estado_volando:
		_estado_volando = volando
		if volando:
			print("[Aura] PRENDIENDO (vuelo), objetivo: ", snappedf(objetivo, 0.01))
		else:
			print("[Aura] APAGANDO (sin vuelo)")
	_intensidad = lerpf(_intensidad, objetivo, clampf(suavizado * delta, 0.0, 1.0))
	_particulas.amount_ratio = _intensidad
	if _luz != null:
		_luz.light_energy = _intensidad * luz_intensidad
