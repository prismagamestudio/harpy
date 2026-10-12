extends Node3D
## HARPY — Estelas de viento: cintas translúcidas que salen de las puntas
## de los brazos cuando el aire pasa rápido (ratio_velocidad del vuelo).
## Se adjunta a VisualRoot y solo se busca los FeatherSpawn (puntas) y el
## FlightController. Nada que configurar; perillas de grosor y color abajo.
##
## Cómo funciona: cada mano guarda un historial de posiciones del mundo;
## se dibuja una cinta (quads billboards) que se desvanece con la edad.
## Si no hay velocidad, la cinta se encoge y no se ve.

@export_range(0.02, 0.3, 0.01) var grosor: float = 0.07
## Cuántos metros por segundo hacen visible la estela (0..1 del máx).
@export_range(0.0, 1.0, 0.05) var umbral_ratio: float = 0.35
## Longitud de la estela (en segmentos).
@export_range(8, 40, 2) var segmentos: int = 22
@export var color: Color = Color(0.75, 0.9, 1.0, 0.55)

var _flight: Node = null
var _puntas: Array[Node3D] = []
var _historial: Array = []  # por punta: PackedVector3Array de puntos
var _meshes: Array[MeshInstance3D] = []
var _intensidad := 0.0

func _ready() -> void:
	var player := get_parent()
	_flight = player.get_node_or_null("FlightController")
	for ruta in ["FeatherSpawnLeft", "FeatherSpawnRight"]:
		var punta := get_node_or_null(ruta) as Node3D
		if punta != null:
			_puntas.append(punta)
	if _puntas.is_empty():
		# Fallback: puntas imaginarias a los costados.
		_puntas.append(self)
		_puntas.append(self)
		print("[Estelas] Sin FeatherSpawnLeft/Right bajo VisualRoot: uso el centro.")
	for i in _puntas.size():
		_historial.append(PackedVector3Array())
		var mi := MeshInstance3D.new()
		mi.mesh = ImmediateMesh.new()
		mi.top_level = true  # la cinta vive en espacio del mundo
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_meshes.append(mi)
	print("[Estelas] Listo (", _puntas.size(), " cintas).")

func _process(delta: float) -> void:
	var ratio := 0.0
	if _flight != null and _flight.is_flying:
		ratio = _flight.ratio_velocidad()
	var objetivo := 0.0
	if ratio > umbral_ratio:
		objetivo = clampf((ratio - umbral_ratio) / (1.0 - umbral_ratio), 0.0, 1.0)
	_intensidad = lerpf(_intensidad, objetivo, clampf(6.0 * delta, 0.0, 1.0))
	if _intensidad < 0.02:
		_limpiar()
		return
	var camara := get_viewport().get_camera_3d()
	for i in _puntas.size():
		var puntos: PackedVector3Array = _historial[i]
		puntos.append(_puntas[i].global_position)
		while puntos.size() > segmentos:
			puntos.remove_at(0)
		_historial[i] = puntos
		_dibujar_cinta(i, puntos, camara)

func _limpiar() -> void:
	for mi in _meshes:
		(mi.mesh as ImmediateMesh).clear_surfaces()
	# Al quedarse quieto el historial se acorta para que la cinta muera.
	for i in _historial.size():
		var puntos: PackedVector3Array = _historial[i]
		if puntos.size() > 2:
			puntos.remove_at(0)
		_historial[i] = puntos

func _dibujar_cinta(i: int, puntos: PackedVector3Array, camara: Camera3D) -> void:
	var mesh := _meshes[i].mesh as ImmediateMesh
	mesh.clear_surfaces()
	if puntos.size() < 3 or camara == null:
		return
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := puntos.size()
	for k in n - 1:
		var edad := float(k) / float(n - 1)          # 0 reciente, 1 vieja
		var alpha := (1.0 - edad) * _intensidad * color.a
		if alpha <= 0.01:
			continue
		var a := puntos[k]
		var b := puntos[k + 1]
		# Billboard: el ancho se abre hacia la cámara.
		var seg := b - a
		if seg.length_squared() < 0.000001:
			continue
		var al_camara := (camara.global_position - (a + b) * 0.5).normalized()
		var lateral := seg.cross(al_camara).normalized() * grosor * (1.0 - edad * 0.6)
		var color_a := Color(color.r, color.g, color.b, alpha)
		var color_b := Color(color.r, color.g, color.b, alpha * 0.7)
		mesh.surface_set_color(color_a)
		mesh.surface_add_vertex(a - lateral)
		mesh.surface_add_vertex(a + lateral)
		mesh.surface_set_color(color_b)
		mesh.surface_add_vertex(b - lateral)
		mesh.surface_add_vertex(b + lateral)
		mesh.surface_add_vertex(b - lateral)
	mesh.surface_end()
