extends SceneTree
## Captures du menu, des options et du tutoriel (à lancer AVEC fenêtre) :
##   godot --path . -s tests/menu_capture.gd
## Enregistre captures/menu.png, captures/menu_options.png et captures/tutoriel.png.

var node: Node
var frame := 0


func _initialize() -> void:
	GameOptions.path = "user://capture_options.cfg" # Ne touche pas aux options du joueur
	GameOptions.loaded = false
	_clean()
	node = load("res://scenes/menu.tscn").instantiate()
	node.set("change_scenes", false)
	root.add_child(node)


func _process(_delta: float) -> bool:
	frame += 1
	match frame:
		40:
			_save("menu.png")
			node.open_options()
		50:
			node.start_rebind("formation")
		60:
			_save("menu_options.png")
			node.waiting_action = "" # Une touche pressée pendant la capture ne doit rien changer
			root.remove_child(node)
			node.free()
			node = load("res://scenes/tutorial.tscn").instantiate()
			root.add_child(node)
		64:
			# Deux premières étapes faites, comme un joueur : sélection puis déplacement
			var r: Regiment = node.player_regiments()[0]
			r.selected = true
			node.check_steps()
			r.dest = r.center + Vector2(-80, -140)
			node.check_steps()
			node.camera.zoom = Vector2(1.4, 1.4)
			node.camera.position = Vector2(1600, 1450)
		90:
			_save("tutoriel.png")
			root.remove_child(node)
			node.free() # Arrête la musique avant de quitter (sinon fuite à la fermeture)
		92:
			_clean()
			quit(0)
	return false


func _save(file: String) -> void:
	var path := ProjectSettings.globalize_path("res://captures/").path_join(file)
	root.get_texture().get_image().save_png(path)
	print("Capture : ", path)


func _clean() -> void:
	if FileAccess.file_exists(GameOptions.path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(GameOptions.path))
	GameOptions.reset_all()
