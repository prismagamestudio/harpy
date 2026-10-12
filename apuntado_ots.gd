extends Node
## HARPY — Modo apuntado OVER-THE-SHOULDER:
##   - RMB desplaza la cámara al hombro (y sube un pelín).
##   - Aparece la MIRA en el centro de la pantalla: ese punto es adónde
##     van los proyectiles (feather_ability ya dispara al centro).
##   - El CUERPO gira siguiendo la cámara al apuntar: los brazos apuntan
##     a donde apunta la mira, no de costado.
##
## SETUP: nodo hijo del Player "ApuntadoOTS" con este script. Busca solo
## la cámara (CameraPivot/SpringArm3D/Camera3D) y el VisualRoot.
##
## Perillas: hombro, subida, suavizado, giro_cuerpo. Todo en vivo por Remote.

@export var camera_path: NodePath = NodePath("../CameraPivot/SpringArm3D/Camera3D")
@export var visual_path: NodePath = NodePath("../VisualRoot")
## Cuánto se corre la cámara hacia el hombro derecho (metros).
@export_range(0.0, 2.0, 0.05) var hombro: float = 0.9
## Cuánto sube la cámara al apuntar (metros).
@export_range(0.0, 1.0, 0.05) var subida: float = 0.1
@export_range(1.0, 12.0, 0.5) var suavizado: float = 8.0
## Velocidad a la que el cuerpo gira hacia la cámara al apuntar.
@export_range(1.0, 20.0, 0.5) var giro_cuerpo: float = 12.0

var _camera: Camera3D
var _visual: Node3D
var _capa: CanvasLayer
var _mira: Control
var _apuntando := false

func _ready() -> void:
	_camera = get_node_or_null(camera_path) as Camera3D
	_visual = get_node_or_null(visual_path) as Node3D
	if _camera == null:
		printerr("[Apuntado] Sin cámara: revisá camera_path.")
		set_process(false)
		return
	_capa = CanvasLayer.new()
	_capa.name = "MiraCapa"
	_capa.layer = 100  # por encima de todo HUD
	add_child(_capa)
	_mira = Mira.new()
	_capa.add_child(_mira)
	_mira.visible = false
	print("[Apuntado] Listo (OTS + mira).")

func _process(delta: float) -> void:
	_apuntando = (
		InputMap.has_action("aim") and Input.is_action_pressed("aim")
	)
	_mira.visible = _apuntando
	if _apuntando:
		_mira.queue_redraw()  # redibujada cada frame: no depende del tamaño
	var f := clampf(suavizado * delta, 0.0, 1.0)
	_camera.h_offset = lerpf(
		_camera.h_offset,
		hombro if _apuntando else 0.0,
		f
	)
	_camera.v_offset = lerpf(
		_camera.v_offset,
		subida if _apuntando else 0.0,
		f
	)
	if _apuntando and _visual != null:
		var adelante := -_camera.global_transform.basis.z
		var yaw := atan2(-adelante.x, -adelante.z)
		_visual.rotation.y = lerp_angle(
			_visual.rotation.y,
			yaw,
			clampf(giro_cuerpo * delta, 0.0, 1.0)
		)


## La mira: círculo, punto central y 4 marcas. Dibujada por código (sin
## assets), centrada por VIEWPORT (no por tamaño del control: inmune a
## layouts) y re-dibujada cada frame desde afuera.
class Mira:
	extends Control

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var centro := get_viewport_rect().size * 0.5
		var radio := 13.0
		var tinta := Color(1.0, 1.0, 1.0, 0.92)
		var sombra := Color(0.0, 0.0, 0.0, 0.35)
		draw_arc(centro + Vector2(1, 1), radio, 0.0, TAU, 40, sombra, 1.6, true)
		draw_arc(centro, radio, 0.0, TAU, 40, tinta, 1.6, true)
		draw_circle(centro + Vector2(1, 1), 2.0, sombra)
		draw_circle(centro, 2.0, tinta)
		var adentro := radio * 1.35
		var afuera := radio * 1.95
		for direccion in [
			Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN
		]:
			draw_line(
				centro + direccion * adentro,
				centro + direccion * afuera,
				tinta,
				1.6,
				true
			)
