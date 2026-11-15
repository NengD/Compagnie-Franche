extends SceneTree
## Captures multi-résolution (à lancer AVEC fenêtre, une fois par taille de fenêtre) :
##   godot --path . --resolution 1920x1200 -s tests/resolution_capture.gd
##   godot --path . --resolution 1280x720 -s tests/resolution_capture.gd -- --ui=1.5
## Écrit hors du dépôt : user://captures_resolution/<taille>_<ui>_<écran>.png
## (menu, options, carte de campagne, écran de fin, bataille avec le menu pause).
## N'utilise pas les fichiers du joueur (options et campagne de test dans user://).

const OPTIONS_TEST := "user://capture_res_options.cfg"
const SAVE_TEST := "user://capture_res_campagne.json"
const OUT_DIR := "user://captures_resolution"

var node: Node
var frame := 0
var ui := 1.0
var tag := ""


func _initialize() -> void:
	AudioServer.set_bus_mute(0, true) # Aucun son pendant les tests
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ui="):
			ui = float(a.trim_prefix("--ui="))
	GameOptions.path = OPTIONS_TEST
	GameOptions.loaded = false
	CampaignState.save_path = SAVE_TEST
	_clean()
	GameOptions.ensure_loaded()
	GameOptions.set_ui_scale(ui)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	CampaignState.current = CampaignState.new_game(0)
	CampaignState.current.save()
	_show("res://scenes/menu.tscn")


func _process(_delta: float) -> bool:
	frame += 1
	match frame:
		2:
			var ws := DisplayServer.window_get_size()
			tag = "%dx%d_ui%d" % [ws.x, ws.y, roundi(ui * 100.0)]
			print("Fenêtre %s, vue visible %s" % [ws, root.get_visible_rect().size])
		30:
			_save("menu")
			node.open_options()
		45:
			_save("options")
			_show("res://scenes/campaign.tscn")
		75:
			_save("carte")
			var st: CampaignState = CampaignState.current
			st.ended = "victory"
			st.end_note = "La bataille décisive est gagnée : le comté est à vous."
			_show("res://scenes/end.tscn")
		105:
			_save("fin")
			CampaignState.current = CampaignState.new_game(0)
			CampaignState.current.pending = {}
			_show("res://scenes/main.tscn")
		130:
			_save("bataille")
			node.open_pause_menu()
		145:
			_save("pause")
			_free()
		147:
			_clean()
			quit(0)
	return false


func _show(path: String) -> void:
	_free()
	node = load(path).instantiate()
	node.set("change_scenes", false)
	node.set("auto_launch", false)
	root.add_child(node)


func _free() -> void:
	if node != null and is_instance_valid(node):
		root.remove_child(node)
		node.free()
	node = null


func _save(what: String) -> void:
	var img := root.get_texture().get_image()
	var p := "%s/%s_%s.png" % [OUT_DIR, tag, what]
	img.save_png(p)
	print("Capture : ", ProjectSettings.globalize_path(p), " (", img.get_size(), ")")


func _clean() -> void:
	for p in [OPTIONS_TEST, SAVE_TEST, SAVE_TEST + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
