extends SceneTree
## Captures du chef ennemi et des pièges (à lancer AVEC fenêtre) :
##   godot --path . -s tests/chefs_pieges_capture.gd [-- --out=<dossier>]
## Enregistre traps_deploy.png (pièges posés, barre du HUD, aperçu) et commander.png (chef et sa garde).

var battle: Battle
var frame := 0
var out_dir := "user://captures_chefs_pieges"


func _initialize() -> void:
	AudioServer.set_bus_mute(0, true)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var c := CampaignState.new_game(41) # Contrat de niveau 2 : chef ennemi
	var k: Dictionary = c.contracts[0].duplicate(true)
	k["difficulty"] = 2
	k.erase("ambush")
	k.erase("siege")
	c.pending = k
	CampaignState.current = c
	battle = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	battle.seed_override = 23
	battle.terrain_override = "plain"
	root.add_child(battle)


func _process(_delta: float) -> bool:
	frame += 1
	match frame:
		5:
			var t := battle.sim.traps
			var y := battle.sim.deploy_top() + 70.0
			var cx := BattleSim.WORLD_SIZE.x * 0.5
			t.place(battle.sim, "stakes", Vector2(cx - 320, y))
			t.place(battle.sim, "ditch", Vector2(cx, y))
			t.place(battle.sim, "caltrops", Vector2(cx + 240, y))
			t.tool = "stakes"
			battle.camera.zoom = Vector2(2, 2)
			battle.camera.position = Vector2(cx - 40, y + 60)
		9:
			_save("traps_deploy.png")
			var cmd := battle.sim.commander
			battle.camera.zoom = Vector2(3, 3)
			battle.camera.position = cmd.pos + Vector2(0, 10)
		13:
			_save("commander.png")
			quit()
			return true
	return false


func _save(file: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(out_dir.path_join(file))
	print("Capture : ", out_dir.path_join(file))
