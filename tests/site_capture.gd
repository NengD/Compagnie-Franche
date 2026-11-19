extends SceneTree
## Captures du champ tiré de la carte et des alliés (à lancer AVEC fenêtre, pas en --headless) :
##   godot --path . -s tests/site_capture.gd [-- --out=<dossier>]
## site_pont.png : bataille près d'un pont de la carte (rivière, pont, route qui y mène) ;
## site_allies.png : bataille avec une patrouille alliée (bleu-vert) qui marche sur l'ennemi.

const CaptureDir := preload("res://tests/capture_dir.gd")

var battle: Node
var frame := 0
var phase := "bridge"
var bridge_at := Vector2.ZERO


func _initialize() -> void:
	AudioServer.set_bus_mute(0, true)
	CampaignState.current = null
	_spawn()


## Le premier pont de la carte loin des lieux habités, vu de sa rive.
func bridge_site() -> Dictionary:
	for b in MapData.bridges():
		var mid: Vector2 = (b["a"] + b["b"]) * 0.5
		if MapData.place_at(mid, 4.0) >= 0:
			continue
		var dir: Vector2 = (b["b"] - b["a"]).normalized()
		var pos: Vector2 = b["b"] + dir * 30.0
		return BattleSite.describe(pos, pos + dir * 60.0)
	return {}


func _spawn() -> void:
	battle = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	battle.set("seed_override", 4242)
	var site := bridge_site()
	battle.set("site_override", site)
	for c in site.get("crossings", []):
		if str(c[1]) == "bridge":
			bridge_at = Vector2(float(c[0]), 0.0)
	if phase == "allies":
		battle.set("allies_override", [{"party": -1, "name": "la patrouille de Valombre", "faction": 0,
			"troops": [{"type": "cavalry", "men": 10, "rank": 1}, {"type": "men_at_arms", "men": 16, "rank": 1}, {"type": "spear", "men": 20, "rank": 1}]}])
	root.add_child(battle)
	frame = 0


func _process(_delta: float) -> bool:
	frame += 1
	if phase == "bridge":
		if frame == 2:
			bridge_at.y = battle.sim.road_y(bridge_at.x)
		if frame >= 2:
			battle.camera.position = bridge_at
			battle.camera.zoom = Vector2(0.6, 0.6)
		if frame == 30:
			CaptureDir.save(self, "site_pont.png")
			root.remove_child(battle)
			battle.free()
			phase = "allies"
			_spawn()
	else:
		if frame == 2:
			battle.start_battle()
		elif frame > 2 and frame < 34:
			for i in 10:
				battle.simulate(0.05)
		for r in battle.sim.regiments:
			if r.allied and not r.is_dead():
				battle.camera.position = r.center + Vector2(160, -80) # Le premier allié et ses voisins
				break
		battle.camera.zoom = Vector2(1.0, 1.0)
		if frame == 50:
			CaptureDir.save(self, "site_allies.png")
			quit(0)
	return false
