extends SceneTree
## Capture d'écran pour vérifier le rendu (à lancer AVEC fenêtre, pas en --headless) :
##   godot --path . -s tests/screenshot.gd
## Enregistre user://shot_*.png : vue d'ensemble, puis gros plan sur la mêlée.

var battle: Node
var frame := 0


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	battle = scene.instantiate()
	battle.set("seed_override", 12345)
	root.add_child(battle)


func _process(_delta: float) -> bool:
	frame += 1
	match frame:
		5:
			battle.camera.zoom = Vector2(0.5, 0.5)
			battle.camera.position = battle.WORLD_SIZE * 0.5
		10:
			_save("shot_overview.png")
			# Quelques formations pour la capture : piquiers en carré, hommes d'armes en colonne
			for r in battle.player_regiments():
				if r.type == "spear" and r.center.x < 1600:
					r.formation = Regiment.Formation.SQUARE
				elif r.type == "men_at_arms" and r.center.x < 1600:
					r.formation = Regiment.Formation.COLUMN
				elif r.type == "archer":
					r.stamina = 0.25 # Pour voir l'affichage de la fatigue
				elif r.type == "cavalry" and r.center.x < 1600:
					r.running = true
					r.dest = r.center + Vector2(0, -320)
			for i in 300:
				battle.simulate(0.05)
			battle.camera.zoom = Vector2(2, 2)
			battle.camera.position = Vector2(1300, 1620)
		15:
			_save("shot_deploy.png")
			battle.start_battle()
			# Fait avancer la bataille de 22 s jusqu'au contact
			for r in battle.player_regiments():
				var e: Regiment = battle.nearest_enemy_regiment(r, INF, true)
				if e != null:
					r.target = e
			for i in 450:
				battle.simulate(0.05)
			var c := Vector2.ZERO
			var n := 0
			for r in battle.regiments:
				if r.engaged and not r.is_dead():
					c += r.center
					n += 1
			battle.camera.position = c / maxi(n, 1) if n > 0 else battle.WORLD_SIZE * 0.5
			battle.camera.zoom = Vector2(2.5, 2.5)
		20:
			_save("shot_melee.png")
			quit(0)
	return false


func _save(name: String) -> void:
	var img := root.get_texture().get_image()
	var path := OS.get_user_data_dir().path_join(name)
	img.save_png(path)
	print("Capture : ", path)
