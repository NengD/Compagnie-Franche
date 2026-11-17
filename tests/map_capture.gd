extends SceneTree
## Captures de la grande carte (à lancer AVEC fenêtre) :
##   godot --path . --resolution 1280x720 -s tests/map_capture.gd [-- --out=<dossier>]
## Écrit dans user://captures (voir capture_dir.gd) : grande_carte_loin (zoom minimal, noms des
## régions), grande_carte_moyen (zoom moyen sur le centre), grande_carte_pres (zoom fort sur une
## forêt et une rivière), grande_carte_monts (les Monts de Fer et leur col), grande_carte_sud
## (le bocage, le gué et l'étang). Campagne de test dans user://, jamais celle du joueur.

const CaptureDir := preload("res://tests/capture_dir.gd")

const SHOTS := [
	{"file": "grande_carte_loin.png", "zoom": 0.3, "at": Vector2(1900, 1560)},
	{"file": "grande_carte_moyen.png", "zoom": 0.75, "at": Vector2(1700, 1500)},
	{"file": "grande_carte_pres.png", "zoom": 1.8, "at": Vector2(2230, 1330)},
	{"file": "grande_carte_monts.png", "zoom": 1.0, "at": Vector2(3080, 560)},
	{"file": "grande_carte_sud.png", "zoom": 1.0, "at": Vector2(1050, 2650)},
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
		map.town_open = false
		map.paused = true
		map.cam.zoom = Vector2(z, z)
		map.center_on(s["at"])
		map.refresh_ui()
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
