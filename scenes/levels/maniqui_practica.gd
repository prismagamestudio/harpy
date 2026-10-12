extends RigidBody3D
## HARPY — Maniquí de práctica: recibe golpes, plumas, cajas lanzadas y
## embestidas del dive; muestra daño flotante, temblor, knockback y respawn.
##
## SETUP (clic por clic en el chat): RigidBody3D con este script + un
## CollisionShape3D (cápsula ~1.8) + el GLB del maniquí como hijo (mesh).
## El script se agrega SOLO a los grupos "maniqui" y "agarrables"
## (por lo tanto tus garras ya lo pueden agarrar volando).
##
## Cómo le pegan:
##   - Melee: ground_combat consulta los maniquíes al pico del golpe.
##   - Plumas / cajas / embestidas: el detector de impactos (esfera que el
##     script crea solo) mide la velocidad del intruso y convierte el choque
##     en daño. Nada que configurar.

@export var vida_max: int = 100
## Daño por velocidad de impacto (x m/s).
@export var danio_por_velocidad: float = 3.0
## Velocidad mínima de un choque para contar como impacto (objetos:
## plumas, cajas lanzadas, maniquíes tirados).
@export_range(1.0, 10.0, 0.5) var velocidad_minima: float = 4.0
## Velocidad mínima del JUGADOR para dañar por embestida (dive, boost,
## caída alta). Caminar (5) y sprint (8.5) quedan DEBAJO a propósito.
@export_range(5.0, 20.0, 0.5) var umbral_embestida: float = 9.5
## Segundos entre impactos del mismo cuerpo (anti-multi-hit).
@export_range(0.2, 2.0, 0.1) var cooldown_impacto: float = 0.6
## Frenado del deslizamiento al recibir golpes (0 = patina eterno).
@export_range(0.0, 6.0, 0.25) var deslizamiento: float = 2.5
## Velocidad propia mínima para dañarse al CHOCAR (caída/lanzamiento).
@export_range(3.0, 20.0, 0.5) var umbral_caida: float = 7.5
## Segundos de colapso antes de respawnear.
@export var respawn_segundos: float = 2.5

var _vida: int
var _mesh: Node3D
var _etiqueta: Label3D
var _zona: Area3D
var _muerto := false
var _avisos := {}

func _ready() -> void:
	_vida = vida_max
	add_to_group("maniqui")
	add_to_group("agarrables")
	# Muñeco inflable de boxeo: se empuja pero no se vuelca.
	axis_lock_angular_x = true
	axis_lock_angular_z = true
	mass = 8.0
	linear_damp = deslizamiento  # se frena rapido: muneco inflable, no puck
	var fisica := PhysicsMaterial.new()
	fisica.friction = 1.1
	fisica.bounce = 0.05
	physics_material_override = fisica
	_mesh = _buscar_mesh(self)
	_armar_etiqueta()
	_armar_zona_impactos()
	print("[Maniqui] ", name, " listo (grupo maniqui+agarrables).")

func _buscar_mesh(nodo: Node) -> Node3D:
	for hijo in nodo.get_children():
		if hijo is Node3D and not (hijo is CollisionShape3D) and hijo != _etiqueta:
			return hijo as Node3D
	return null

## Punto único de entrada para TODO daño dirigido (melee, futuros hechizos).
func recibir_golpe(danio: int, direccion: Vector3, fuerza: float = 4.5) -> void:
	if _muerto:
		return
	_vida = maxi(_vida - danio, 0)
	linear_velocity += direccion * fuerza + Vector3.UP * (fuerza * 0.4)
	_temblar()
	_mostrar_danio(danio)
	_actualizar_etiqueta()
	if _vida == 0:
		_colapsar()

## Choques rápidos = daño (plumas, cajas lanzadas, dive del jugador).
func _armar_zona_impactos() -> void:
	_zona = Area3D.new()
	_zona.name = "ZonaImpacto"
	var forma := CollisionShape3D.new()
	var esfera := SphereShape3D.new()
	esfera.radius = 1.3
	forma.shape = esfera
	_zona.add_child(forma)
	add_child(_zona)
	# SIN body_entered: el monitoreo es CONTINUO (el disparo por entrada
	# dañaba al ACERCARSE caminando y solo evaluaba velocidad una vez).

## Monitoreo continuo: cada frame mira qué hay dentro de la zona y decide.
## - Objetos físicos (plumas, cajas, otro maniquí tirado): impacto si van
##   a velocidad_minima o más.
## - Jugador (CharacterBody3D): SOLO embestida a umbral_embestida o más
##   (dive/boost/caída alta); caminar y sprintar NUNCA dañan.
## - Memoria de la velocidad PREVIA del jugador: al aterrizar el motor
##   anula velocity en su frame; con la previa no se pierde la caída.
func _physics_process(delta: float) -> void:
	for clave in _cooldowns.keys():
		_cooldowns[clave] -= delta
	for clave in _cooldowns.keys():
		if _cooldowns[clave] <= 0.0:
			_cooldowns.erase(clave)
	# Congelado = cargado por las garras o colapsado: invulnerable.
	if _muerto or freeze or _zona == null:
		return
	for cuerpo in _zona.get_overlapping_bodies():
		if cuerpo == self or _cooldowns.has(cuerpo.get_instance_id()):
			continue
		var velocidad := Vector3.ZERO
		var umbral := velocidad_minima
		if cuerpo is RigidBody3D:
			velocidad = (cuerpo as RigidBody3D).linear_velocity
		elif cuerpo is CharacterBody3D:
			umbral = umbral_embestida
			var actual := (cuerpo as CharacterBody3D).velocity
			var previa: Vector3 = _vel_jugador_prev.get(
				cuerpo.get_instance_id(), Vector3.ZERO
			)
			velocidad = actual if actual.length() >= previa.length() else previa
			# La memoria guarda SIEMPRE la velocidad actual (si guardara el
			# pico de la caída, caminar cerca después dispararía de nuevo).
			_vel_jugador_prev[cuerpo.get_instance_id()] = actual
		else:
			continue
		var rapidez := velocidad.length()
		if rapidez < umbral:
			continue
		_cooldowns[cuerpo.get_instance_id()] = cooldown_impacto
		var danio := int(clampf(rapidez * danio_por_velocidad, 5.0, 60.0))
		recibir_golpe(danio, velocidad.normalized(), rapidez * 0.35)
		print("[Maniqui] Impacto de %s a %.1f m/s -> %d de daño." % [
			cuerpo.name, rapidez, danio,
		])
	# PROYECTILES (Area3D, p. ej. plumas): no son cuerpos; se miden por el
	# desplazamiento entre frames. Un daño por proyectil (al golpear se
	# borra de la memoria y la siguiente pluma vuelve a contar).
	var vistas := {}
	for area in _zona.get_overlapping_areas():
		var ida := area.get_instance_id()
		vistas[ida] = true
		if _cooldowns.has(ida):
			_pos_areas[ida] = area.global_position
			continue
		var ahora: Vector3 = area.global_position
		if not _pos_areas.has(ida):
			_pos_areas[ida] = ahora
			continue
		var vel_area: Vector3 = (
			(ahora - _pos_areas[ida]) / maxf(delta, 0.001)
		)
		_pos_areas[ida] = ahora
		if vel_area.length() < velocidad_minima:
			continue
		_cooldowns[ida] = cooldown_impacto
		_pos_areas.erase(ida)
		var danio_area := int(clampf(
			vel_area.length() * danio_por_velocidad, 5.0, 60.0
		))
		recibir_golpe(danio_area, vel_area.normalized(), 0.5)
		print("[Maniqui] Impacto de proyectil %s a %.1f m/s -> %d de daño." % [
			area.name, vel_area.length(), danio_area,
		])
	for clave in _pos_areas.keys():
		if not vistas.has(clave):
			_pos_areas.erase(clave)

var _pos_areas := {}
var _mi_vel_previa := Vector3.ZERO

## Auto-impacto: si el PROPIO maniqui choca yendo rapido (caida desde
## altura o lanzamiento con las garras), recibe su propio golpe.
func _integrate_forces(estado: PhysicsDirectBodyState3D) -> void:
	if _muerto or freeze:
		_mi_vel_previa = estado.linear_velocity
		return
	var rap := _mi_vel_previa.length()
	if estado.get_contact_count() > 0 and rap >= umbral_caida:
		var danio := int(clampf(rap * danio_por_velocidad, 5.0, 90.0))
		recibir_golpe(danio, Vector3.UP, 0.0)
		print("[Maniqui] Estampado a %.1f m/s -> %d de daño." % [rap, danio])
	_mi_vel_previa = estado.linear_velocity

var _cooldowns := {}
var _vel_jugador_prev := {}

func _temblar() -> void:
	if _mesh == null:
		return
	var tw := create_tween()
	for i in 4:
		tw.tween_property(_mesh, "position",
			Vector3(randf_range(-0.08, 0.08), 0.0, randf_range(-0.08, 0.08)), 0.04)
	tw.tween_property(_mesh, "position", Vector3.ZERO, 0.05)

func _mostrar_danio(danio: int) -> void:
	var texto := Label3D.new()
	texto.text = str(danio)
	texto.font_size = 64
	texto.pixel_size = 0.006
	texto.modulate = Color(1.0, 0.85, 0.3)
	texto.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	texto.no_depth_test = true
	add_child(texto)
	texto.position = Vector3(0.0, 2.2, 0.0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(texto, "position:y", 3.0, 0.7)
	tw.tween_property(texto, "modulate:a", 0.0, 0.7)
	tw.chain().tween_callback(texto.queue_free)

func _armar_etiqueta() -> void:
	_etiqueta = Label3D.new()
	_etiqueta.font_size = 40
	_etiqueta.pixel_size = 0.005
	_etiqueta.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_etiqueta.no_depth_test = true
	add_child(_etiqueta)
	_etiqueta.position = Vector3(0.0, 2.0, 0.0)
	_actualizar_etiqueta()

func _actualizar_etiqueta() -> void:
	var lleno := float(_vida) / float(vida_max)
	_etiqueta.text = "%d/100" % _vida
	if lleno > 0.5:
		_etiqueta.modulate = Color(0.55, 1.0, 0.6)
	elif lleno > 0.25:
		_etiqueta.modulate = Color(1.0, 0.8, 0.35)
	else:
		_etiqueta.modulate = Color(1.0, 0.45, 0.4)

func _colapsar() -> void:
	_muerto = true
	freeze = true
	_etiqueta.text = ""
	if _mesh != null:
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(_mesh, "rotation:x", deg_to_rad(-85.0), 0.5)
		tw.tween_property(_mesh, "position:y", -0.4, 0.5)
	get_tree().create_timer(respawn_segundos).timeout.connect(_respawn)
	_avisar("muerte", "[Maniqui] " + String(name) + " colapsado. Respawn en " + str(respawn_segundos) + "s.")

func _respawn() -> void:
	_vida = vida_max
	_muerto = false
	freeze = false
	linear_velocity = Vector3.ZERO
	if _mesh != null:
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(_mesh, "rotation:x", 0.0, 0.3)
		tw.tween_property(_mesh, "position:y", 0.0, 0.3)
	_actualizar_etiqueta()

func _avisar(clave: String, mensaje: String) -> void:
	if _avisos.has(clave):
		return
	_avisos[clave] = true
	print(mensaje)
