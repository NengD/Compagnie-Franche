extends SceneTree
## Captures des vrais sièges (à lancer AVEC fenêtre, pas en --headless) :
##   godot --path . -s tests/siege_capture.gd [-- --out=<dossier>]
## Pour l'assaut puis la défense : vue d'ensemble au déploiement (siege_<sorte>.png), puis gros plans
## sur la porte et une échelle après quelques dizaines de secondes de bataille jouée par l'IA des deux
## côtés (siege_<sorte>_porte.png, siege_<sorte>_echelle.png). Dossier par défaut : user://captures.

const CaptureDir := preload("res://tests/capture_dir.gd")
const TestPlayer := preload("res://tests/test_player.gd")
const SEED := 4242
const KINDS := ["town_assault", "town_defense"]
const NAMES := {"town_assault": "assaut", "town_defense": "defense"}

var scene: PackedScene
var battle: Node
var player: RefCounted
var index := 0
var frame := 0


func _initialize() -> void:
	AudioServer.set_bus_mute(0, true) # Aucun son pendant les tests
	scene = load("res://scenes/main.tscn")
	_open()


func _open() -> void:
	battle = scene.instantiate()
	battle.set("seed_override", SEED)
	battle.set("terrain_override", KINDS[index])
	root.add_child(battle)
	player = TestPlayer.new("ai")
	frame = 0


## Joue la bataille jusqu'à ce que cond soit vraie (ou max_t secondes de plus).
func _play_until(cond: Callable, max_t: float) -> void:
	var t0: float = battle.battle_time
	while battle.state == battle.State.BATTLE and battle.battle_time - t0 < max_t and not cond.call():
		player.update(battle)
		battle.simulate(0.05)


func _process(_delta: float) -> bool:
	frame += 1
	var name: String = NAMES[KINDS[index]]
	var sg: Siege = battle.sim.siege
	match frame:
		4:
			battle.camera.zoom = Vector2(0.5, 0.5)
			battle.camera.position = Vector2(1600, sg.town.front_y)
			battle.show_help = false
		8:
			_save("siege_%s.png" % name)
			battle.start_battle()
			_play_until(func(): return sg.raised > 0 and sg.climbers.size() > 2, 160.0)
			var x: float = sg.town.gate_x + 300.0
			for l in sg.ladders:
				if l["state"] in ["up", "down", "raising"]:
					x = float(l["x"])
					break
			battle.camera.zoom = Vector2(2, 2)
			battle.camera.position = Vector2(x, sg.town.front_y - 10.0)
		12:
			_save("siege_%s_echelle.png" % name)
			_play_until(func(): return sg.town.gate_open or sg.gate_hp < 50.0, 90.0)
			battle.camera.zoom = Vector2(2, 2)
			battle.camera.position = Vector2(sg.town.gate_x, sg.town.front_y)
		16:
			_save("siege_%s_porte.png" % name)
			root.remove_child(battle)
			battle.free()
			index += 1
			if index >= KINDS.size():
				quit(0)
				return true
			_open()
	return false


func _save(file: String) -> void:
	CaptureDir.save(self, file)
