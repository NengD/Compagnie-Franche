extends SceneTree
## Captures du menu, des options et du tutoriel (à lancer AVEC fenêtre) :
##   godot --path . -s tests/menu_capture.gd [-- --out=<dossier>]
## Enregistre menu.png, menu_options.png, menu_emplacements.png (aperçus des sauvegardes),
## menu_succes.png (grille des succès et notification) et tutoriel.png dans user://captures (défaut)
## ou dans <dossier> (relatif à la racine du projet : --out=captures met à jour celles du dépôt).

const CaptureDir := preload("res://tests/capture_dir.gd")
const SLOTS := "user://capture_menu_campagne" ## Emplacements de la capture (jamais ceux du joueur)
const STATS := "user://capture_stats.json"

var node: Node
var frame := 0


func _initialize() -> void:
	AudioServer.set_bus_mute(0, true) # Aucun son pendant les tests
	GameOptions.path = "user://capture_options.cfg" # Ne touche pas aux options du joueur
	GameOptions.loaded = false
	_clean()
	_fake_saves()
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
			node.open_slots()
		70:
			_save("menu_emplacements.png")
			node.open_achievements()
			Achievements.notify(["premiere_victoire"] as Array[String])
		120:
			_save("menu_succes.png")
			node.back_to_main()
		130:
			root.remove_child(node)
			node.free()
			node = load("res://scenes/tutorial.tscn").instantiate()
			root.add_child(node)
		134:
			# Deux premières étapes faites, comme un joueur : sélection puis déplacement
			var r: Regiment = node.player_regiments()[0]
			r.selected = true
			node.check_steps()
			r.dest = r.center + Vector2(-80, -140)
			node.check_steps()
			node.camera.zoom = Vector2(1.4, 1.4)
			node.camera.position = Vector2(1600, 1450)
		160:
			_save("tutoriel.png")
			root.remove_child(node)
			node.free() # Arrête la musique avant de quitter (sinon fuite à la fermeture)
		162:
			_clean()
			quit(0)
	return false


func _save(file: String) -> void:
	CaptureDir.save(self, file)


## Deux campagnes sauvegardées (emplacements 1 et 3) et quelques succès, hors des fichiers du joueur.
func _fake_saves() -> void:
	CampaignState.slot_prefix = SLOTS
	for i in range(1, CampaignState.SLOT_COUNT + 1):
		CampaignState.delete_slot(i)
	CampaignState.use_slot(1)
	var c := CampaignState.new_game(7)
	c.day = 12
	c.gold = 840.0
	c.fame = 35
	c.save()
	CampaignState.use_slot(3)
	c = CampaignState.new_game(9, Difficulty.HARD)
	c.day = 41
	c.gold = 2310.0
	c.fame = 120
	c.overworld.player.pos = CampaignState.TOWNS[4]["pos"] + Vector2(160, 90)
	c.overworld.inside = -1 # En route
	c.save()
	CampaignState.current = null
	Stats.path = STATS
	Stats.reset()
	Stats.loaded = true
	Stats.data["enemies_killed"] = 64
	Stats.data["battles"] = 7
	Stats.data["victories"] = 5
	Stats.data["gold_earned"] = 2130
	var now := int(Time.get_unix_time_from_system())
	for id in ["premiere_victoire", "sans_perte_regiment", "carre", "eclair", "retraite"]:
		Stats.data["achievements"][id] = now - 86400 * 3


func _clean() -> void:
	CampaignState.slot_prefix = SLOTS
	for i in range(1, CampaignState.SLOT_COUNT + 1):
		CampaignState.delete_slot(i)
	if FileAccess.file_exists(GameOptions.path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(GameOptions.path))
	GameOptions.reset_all()
