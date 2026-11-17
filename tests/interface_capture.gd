extends SceneTree
## Captures de l'interface de bataille (à lancer AVEC fenêtre) :
##   godot --path . --resolution 1280x720 -s tests/interface_capture.gd -- --ui=1.5
## Écrit hors du dépôt : user://captures_interface/<taille>_ui<taille>_<écran>.png
## (aide repliée, aide dépliée + formes des camps + sous-titre + info-bulle, cartes cachées, bilan de fin).
## N'utilise pas les fichiers du joueur (options de test dans user://).

const OPTIONS_TEST := "user://capture_interface_options.cfg"
const OUT_DIR := "user://captures_interface"

var b: Battle
var frame := 0
var ui := 1.0
var tag := ""


func _initialize() -> void:
	AudioServer.set_bus_mute(0, true) # Aucun son pendant les captures
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ui="):
			ui = float(a.trim_prefix("--ui="))
	GameOptions.path = OPTIONS_TEST
	GameOptions.loaded = false
	GameOptions.ensure_loaded()
	GameOptions.reset_all()
	GameOptions.set_ui_scale(ui)
	CampaignState.current = null
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	b = load("res://scenes/main.tscn").instantiate()
	b.seed_override = 31
	root.add_child(b)


func _process(_delta: float) -> bool:
	frame += 1
	match frame:
		2:
			var ws := DisplayServer.window_get_size()
			tag = "%dx%d_ui%d" % [ws.x, ws.y, roundi(ui * 100.0)]
			print("Fenêtre %s, vue %s, échelle du monde %s" % [ws, root.get_visible_rect().size, b.camera.screen_scale()])
		20:
			_save("deploiement")
			GameOptions.team_shapes = true
			GameOptions.subtitles = true
			b.show_help = true
			b.start_battle()
			b.camera.position = Vector2(BattleSim.WORLD_SIZE.x * 0.5, 620)
			b.camera.clamp_to_world()
		90:
			# Souris sur un régiment ennemi : info-bulle
			for r in b.regiments:
				if r.team == Battle.ENEMY and not r.hidden and not r.is_dead():
					var p: Vector2 = b.get_canvas_transform() * r.center
					var vs := root.get_visible_rect().size
					if Rect2(Vector2(0, 40), vs - Vector2(0, 140)).has_point(p):
						Input.warp_mouse(p * b.camera.window_scale())
						break
			b.add_message("Embuscade !")
		100:
			_save("bataille")
			b.show_cards = false # Tab : cartes cachées
		106:
			_save("cartes_cachees")
			b.show_cards = true
			for s in b.player_roster()[0].soldiers:
				s.alive = false
			b.sim.state = BattleSim.State.VICTORY
			b.open_report()
			b.show_report()
		125:
			_save("bilan")
			root.remove_child(b)
			b.free()
			GameOptions.reset_all()
			DirAccess.remove_absolute(ProjectSettings.globalize_path(OPTIONS_TEST))
			quit(0)
	return false


func _save(screen: String) -> void:
	var path := ProjectSettings.globalize_path(OUT_DIR).path_join("%s_%s.png" % [tag, screen])
	root.get_texture().get_image().save_png(path)
	print("Capture : ", path)
