@tool
extends EditorScript

func _run():
	var lib: AnimationLibrary = load("res://addons/_ALL_SOURCE_ANIMS_2.glb")
	if lib == null:
		print("ERROR: no se pudo cargar la biblioteca")
		return
	var lista := lib.get_animation_list()
	print("Clips: ", lista.size())
	for nombre in lista:
		if nombre.contains("Sword_Aerial_A") and not nombre.contains("Rec"):
			var a: Animation = lib.get_animation(nombre)
			print(nombre, " -> ", a.get_track_count(), " pistas")
			for i in mini(a.get_track_count(), 6):
				print("   ", a.track_get_path(i))
			break
