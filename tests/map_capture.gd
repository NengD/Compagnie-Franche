extends SceneTree
## Captures de la grande carte (à lancer AVEC fenêtre) :
##   godot --path . --resolution 1280x720 -s tests/map_capture.gd [-- --out=<dossier>]
## Écrit dans user://captures (voir capture_dir.gd) : grande_carte_loin (zoom minimal, noms des
## régions), grande_carte_moyen (zoom moyen sur le centre), grande_carte_pres (zoom fort sur une
## forêt et une rivière), grande_carte_monts (les Monts de Fer et leur col), grande_carte_sud
## (le bocage, le gué et l'étang), grande_carte_hiver (vue éloignée sous la neige, mini-carte
## comprise), grande_carte_automne, grande_carte_nuit (lumières des villes), grande_carte_pluie, fenetre_ville, fenetre_monde et fenetre_compagnie (fenêtres sur la carte ; la dernière
## montre les armoiries de la compagnie). Campagne de test dans user://, jamais celle du joueur.

const CaptureDir := preload("res://tests/capture_dir.gd")

const SHOTS := [
	{"file": "grande_carte_loin.png", "zoom": 0.3, "at": Vector2(1900, 1560)},
	{"file": "grande_carte_moyen.png", "zoom": 0.75, "at": Vector2(1700, 1500)},
	{"file": "grande_carte_pres.png", "zoom": 1.8, "at": Vector2(2230, 1330)},
	{"file": "grande_carte_monts.png", "zoom": 1.0, "at": Vector2(3080, 560)},
	{"file": "grande_carte_sud.png", "zoom": 1.0, "at": Vector2(1050, 2650)},
	{"file": "grande_carte_hiver.png", "zoom": 0.3, "at": Vector2(1900, 1560), "day": 100, "hour": 12.0},
	{"file": "grande_carte_automne.png", "zoom": 0.75, "at": Vector2(1700, 1500), "day": 75, "hour": 15.0},
	{"file": "grande_carte_nuit.png", "zoom": 0.75, "at": Vector2(1700, 1500), "day": 20, "hour": 23.0},
	{"file": "grande_carte_pluie.png", "zoom": 1.0, "at": Vector2(1050, 2650), "day": 50, "hour": 16.0, "rain": true},
	{"file": "fenetre_ville.png", "zoom": 1.0, "at": Vector2(-1, -1), "town": true},
	{"file": "fenetre_monde.png", "zoom": 1.0, "at": Vector2(-1, -1), "view": "world"},
	{"file": "fenetre_compagnie.png", "zoom": 1.0, "at": Vector2(-1, -1), "view": "company", "bottom": true},
]

var map: Node
var frame := 0
var shot := 0


func _initialize() -> void:
	AudioServer.set_bus_mute(0, true)
	CampaignState.slot_prefix = "user://capture_grande_carte"
	CampaignState.use_slot(1)
	CampaignState.event_chance = 0.0
	var c := CampaignState.new_game(4321)
	CampaignState.current = c
	map = (load("res://scenes/campaign.tscn") as PackedScene).instantiate()
	map.auto_launch = false
	root.add_child(map)


func _process(_delta: float) -> bool:
	frame += 1
	if frame % 15 == 5 and shot < SHOTS.size():
		var s: Dictionary = SHOTS[shot]
		var z: float = s["zoom"]
		map.town_open = bool(s.get("town", false))
		map.view = str(s.get("view", ""))
		map.paused = true
		map.state.day = int(s.get("day", 1))
		map.state.overworld.hour = float(s.get("hour", 12.0))
		map.state.world.raining = bool(s.get("rain", false))
		map.update_light()
		map.cam.zoom = Vector2(z, z)
		var at: Vector2 = s["at"]
		map.center_on(map.state.overworld.player.pos if at.x < 0 else at)
		map.refresh_ui()
	elif frame % 15 == 10 and shot < SHOTS.size() and bool(SHOTS[shot].get("bottom", false)):
		map.scroll.scroll_vertical = 100000 # Bas de la fenêtre (armoiries)
	elif frame % 15 == 0 and shot < SHOTS.size():
		CaptureDir.save(self, str(SHOTS[shot]["file"]))
		shot += 1
	elif shot >= SHOTS.size():
		root.remove_child(map)
		map.free()
		CampaignState.current = null
		CampaignState.delete_slot(1)
		quit(0)
	return false
