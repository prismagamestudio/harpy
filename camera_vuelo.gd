extends Camera3D
## HARPY — Zoom de velocidad: el FOV se abre con la velocidad de aire real
## del vuelo (el truco de todos los juegos de vuelo: que los m/s SE SIENTAN).
## Se engancha a la Camera3D del jugador y sola se busca al FlightController.
##
## Perillas en el Inspector:
##   fov_base   : FOV en reposo (el que ya tenías: 75)
##   fov_maximo : FOV a full picada (17+ m/s)
##   suavizado  : qué tan rápido entra/sale el zoom

@export var fov_base: float = 75.0
@export_range(80.0, 110.0, 1.0) var fov_maximo: float = 97.0
@export_range(1.0, 10.0, 0.5) var suavizado: float = 4.0

var _flight: Node = null

func _ready() -> void:
	_flight = _buscar_flight(get_parent())

func _buscar_flight(nodo: Node) -> Node:
	if nodo != null and nodo.get("is_flying") != null:
		return nodo
	var padre := nodo.get_parent() if nodo != null else null
	return _buscar_flight(padre) if padre != null else null

func _process(delta: float) -> void:
	if _flight == null or not _flight.is_flying:
		fov = lerpf(fov, fov_base, clampf(suavizado * delta, 0.0, 1.0))
		return
	var ratio: float = clampf(_flight.ratio_velocidad(), 0.0, 1.0)
	var objetivo := lerpf(fov_base, fov_maximo, clampf((ratio - 0.45) / 0.55, 0.0, 1.0))
	fov = lerpf(fov, objetivo, clampf(suavizado * delta, 0.0, 1.0))
