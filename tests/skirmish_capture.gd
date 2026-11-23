extends SceneTree
## Captures de l'escarmouche personnalisée et des défis (à lancer AVEC fenêtre) :
##   godot --path . -s tests/skirmish_capture.gd [-- --out=<dossier>]
## Enregistre menu_escarmouche.png (préparation), menu_defis.png (nouvelle campagne et ses défis),
## escarmouche_hiver_nuit.png et escarmouche_automne_aube.png (batailles préparées) dans
## user://captures (défaut) ou dans <dossier>.

const CaptureDir := preload("res://tests/capture_dir.gd")

var node: Node
var frame := 0


func _initialize() -> void:
	AudioServer.set_bus_mute(0, true) # Aucun son pendant les tests
	GameOptions.path = "user://capture_escarmouche_options.cfg" # Ne touche pas aux options du joueur
	GameOptions.loaded = false
	CampaignState.slot_prefix = "user://capture_defis_campagne"
	node = load("res://scenes/menu.tscn").instantiate()
	node.set("change_scenes", false)
	root.add_child(node)


func _process(_delta: float) -> bool:
	frame += 1
	match frame:
		10:
			GameOptions.skirmish = {
				"player": {"spear": {"n": 2, "rank": 1, "gear": 1}, "men_at_arms": {"n": 2, "rank": 2, "gear": 3}, "crossbow": {"n": 2, "rank": 0, "gear": 0}},
				"enemy": {"spear": {"n": 3, "rank": 0, "gear": 0}, "archer": {"n": 2, "rank": 0, "gear": 0}, "cavalry": {"n": 2, "rank": 1, "gear": 1}},
				"terrain": "forest", "weather": "clear", "season": "winter", "hour": "night", "difficulty": "hard",
			}
			node.open_skirmish()
		30:
			CaptureDir.save(self, "menu_escarmouche.png")
			node.new_campaign(1)
			node.toggle_challenge(true, Challenges.IRONMAN)
			node.toggle_challenge(true, Challenges.NO_CAVALRY)
		50:
			CaptureDir.save(self, "menu_defis.png")
			_battle(node.skirmish_cfg)
		80:
			CaptureDir.save(self, "escarmouche_hiver_nuit.png")
			var cfg: Dictionary = node.skirmish_cfg.duplicate(true)
			cfg["season"] = "autumn"
			cfg["hour"] = "dawn"
			cfg["terrain"] = "village"
			_battle(cfg)
		110:
			CaptureDir.save(self, "escarmouche_automne_aube.png")
		112:
			_clear()
			node.free()
			for i in range(1, CampaignState.SLOT_COUNT + 1):
				CampaignState.delete_slot(i)
			quit(0)
	return false


var battle: Node = null


func _clear() -> void:
	if battle != null:
		root.remove_child(battle)
		battle.free()
		battle = null


func _battle(cfg: Dictionary) -> void:
	_clear()
	if node.get_parent() != null:
		root.remove_child(node)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	SkirmishSetup.pending = SkirmishSetup.resolve(cfg, rng)
	battle = load("res://scenes/main.tscn").instantiate()
	battle.set("seed_override", 21)
	root.add_child(battle)
