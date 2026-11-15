extends SceneTree
## Captures de chaque terrain (à lancer AVEC fenêtre, pas en --headless) :
##   godot --path . -s tests/terrain_shots.gd
## Enregistre captures/terrain_<type>.png (vue d'ensemble) et captures/terrain_<type>_zoom.png
## (gros plan sur le relief, un gué, le village ou une brèche, après 35 s de bataille).

const SEED := 12345

var scene: PackedScene
var battle: Node
var index := 0
var frame := 0


func _initialize() -> void:
	scene = load("res://scenes/main.tscn")
	_open()


func _open() -> void:
	battle = scene.instantiate()
	battle.set("seed_override", SEED)
	battle.set("terrain_override", Terrain.KINDS[index])
	root.add_child(battle)
	frame = 0


func _process(_delta: float) -> bool:
	frame += 1
	var kind: String = Terrain.KINDS[index]
	match frame:
		4:
			battle.camera.zoom = Vector2(0.5, 0.5)
			battle.camera.position = battle.WORLD_SIZE * 0.5
			battle.show_help = false
		8:
			_save("terrain_%s.png" % kind)
			battle.start_battle()
			for i in 700:
				battle.simulate(0.05)
			battle.camera.zoom = Vector2(1.6, 1.6)
			battle.camera.position = _focus(battle.terrain)
		12:
			_save("terrain_%s_zoom.png" % kind)
			root.remove_child(battle)
			battle.free()
			index += 1
			if index >= Terrain.KINDS.size():
				quit(0)
				return true
			_open()
	return false


## Point intéressant du terrain pour le gros plan.
func _focus(t: Terrain) -> Vector2:
	match t.kind:
		"hills":
			var best := Vector2.ZERO
			var bh := -1.0
			for y in range(500, 1500, 40):
				for x in range(300, 2900, 40):
					var h := t.height(Vector2(x, y))
					if h > bh:
						bh = h
						best = Vector2(x, y)
			return best
		"river":
			return Vector2(t.fords[0], battle.road_y(t.fords[0]))
		"village":
			return t.village_rect.get_center()
		"siege":
			return Vector2(t.breaches[0], Terrain.WALL_Y)
	# Sinon : là où l'on se bat
	var c := Vector2.ZERO
	var n := 0
	for r in battle.regiments:
		if r.engaged and not r.is_dead():
			c += r.center
			n += 1
	return c / n if n > 0 else battle.WORLD_SIZE * 0.5


func _save(name: String) -> void:
	var img := root.get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://captures/").path_join(name)
	img.save_png(path)
	print("Capture : ", path)
