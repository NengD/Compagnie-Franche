extends SceneTree
## Captures du bilan de fin de bataille (à lancer AVEC fenêtre, pas en --headless) :
##   godot --path . -s tests/report_capture.gd [-- --out=<dossier>]
## Joue une bataille de contrat (avec une promotion) puis une escarmouche, et enregistre
## bilan_campagne.png et bilan_escarmouche.png (et leur onglet « Statistiques » : *_stats.png) dans user://captures (défaut) ou dans <dossier>
## (relatif à la racine du projet : --out=captures met à jour celles du dépôt).
## La campagne s'écrit dans user://capture_campagne.json : la vraie sauvegarde n'est pas touchée.

const TestPlayer := preload("res://tests/test_player.gd")
const CaptureDir := preload("res://tests/capture_dir.gd")

var battle: Node
var player
var frame := 0
var phase := "campaign"
var end_frame := -1


func _initialize() -> void:
	AudioServer.set_bus_mute(0, true) # Aucun son pendant la capture
	CampaignState.save_path = "user://capture_campagne.json"
	CampaignState.event_chance = 0.0
	var camp := CampaignState.new_game(42)
	camp.company[0]["xp"] = float(CampaignState.RANK_XP[1]) - 1.0 # Promotion assurée
	camp.company[2]["xp"] = float(CampaignState.RANK_XP[1]) + 10.0 # Déjà aguerris
	camp.refresh_contracts(camp.location)
	camp.accept(camp.contracts_at(camp.location)[0])
	CampaignState.current = camp
	_spawn()


func _spawn() -> void:
	battle = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	if phase == "skirmish":
		battle.set("seed_override", 12345)
	root.add_child(battle)
	frame = 0
	end_frame = -1


func _process(delta: float) -> bool:
	frame += 1
	if frame == 2:
		battle.start_battle()
		player = TestPlayer.new("tactical")
		battle.camera.zoom = Vector2(1.2, 1.2)
	elif frame > 2 and battle.state == 1:
		# Bataille accélérée jusqu'à la fin
		for i in 20:
			player.update(battle)
			battle.simulate(0.05)
			if battle.state != 1:
				break
		battle.camera.position = _fight_center()
	elif battle.state >= 2 and end_frame < 0:
		end_frame = frame
	if end_frame > 0 and frame == end_frame + 140: # Ralenti, puis le bilan apparaît en fondu
		_save("bilan_campagne.png" if phase == "campaign" else "bilan_escarmouche.png")
		battle.report_panel.show_page(1) # Onglet « Statistiques »
	elif end_frame > 0 and frame == end_frame + 146:
		_save("bilan_campagne_stats.png" if phase == "campaign" else "bilan_escarmouche_stats.png")
		root.remove_child(battle)
		battle.free()
		if phase == "campaign":
			CampaignState.current = null
			CampaignState.delete_save()
			phase = "skirmish"
			_spawn()
		else:
			quit(0)
	return false


func _fight_center() -> Vector2:
	var c := Vector2.ZERO
	var n := 0
	for r in battle.regiments:
		if not r.is_dead():
			c += r.center
			n += 1
	return c / n if n > 0 else battle.WORLD_SIZE * 0.5


func _save(file: String) -> void:
	CaptureDir.save(self, file)
