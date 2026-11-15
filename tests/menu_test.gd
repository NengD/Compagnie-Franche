extends SceneTree
## Test headless du menu, des options et du tutoriel :
##   godot --headless --path . -s tests/menu_test.gd
## - options sauvegardées puis rechargées (volumes, plein écran, vitesse, difficulté, touches) ;
## - rebind d'une touche : l'action part avec la nouvelle touche, plus avec l'ancienne ;
##   conflit (échange), touches réservées, retour aux valeurs par défaut ;
## - menu principal qui s'instancie sans erreur, pages Options et nouvelle campagne (difficulté) ;
## - tutoriel parcouru étape par étape en simulant les clics et les touches du joueur.
## N'utilise pas les vrais fichiers du joueur (options et campagne de test dans user://).
## Code de sortie : 0 si tout va bien, 1 sinon.

const OPTIONS_TEST := "user://test_options.cfg"
const SAVE_TEST := "user://test_menu_campagne.json" ## Ancien fichier unique (nettoyé)
const SLOT_TEST := "user://test_menu_campagne" ## Emplacements de test : <base>_1.json...
const STEP := 0.05


class ErrorCounter extends Logger:
	var errors: Array[String] = []
	var mutex := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING:
			return
		mutex.lock()
		errors.append("%s:%d (%s) %s" % [file, line, function, rationale if rationale != "" else code])
		mutex.unlock()


var counter := ErrorCounter.new()
var fails: Array[String] = []
var frame := 0
var node: Node ## Scène testée en cours
var phase := ""


func check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)
		push_warning("ÉCHEC : " + msg)


func _initialize() -> void:
	AudioServer.set_bus_mute(0, true) # Aucun son pendant les tests
	OS.add_logger(counter)
	GameOptions.path = OPTIONS_TEST
	GameOptions.loaded = false
	CampaignState.slot_prefix = SLOT_TEST
	for i in range(1, CampaignState.SLOT_COUNT + 1):
		CampaignState.delete_slot(i)
	CampaignState.use_slot(1)
	CampaignState.current = null
	for p in [OPTIONS_TEST, SAVE_TEST]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	_test_options()
	print("Options sauvegardées / rechargées : %s" % ("OK" if fails.is_empty() else "ÉCHEC"))


func _process(_delta: float) -> bool:
	frame += 1
	match frame:
		1:
			# Bataille d'escarmouche avec une touche reconfigurée
			GameOptions.reset_keys()
			GameOptions.bind_key("halt", KEY_J)
			node = load("res://scenes/main.tscn").instantiate()
			node.set("seed_override", 99)
			root.add_child(node)
		3:
			_test_rebind_in_battle(node)
			_free_node()
			GameOptions.reset_keys()
		4:
			node = load("res://scenes/menu.tscn").instantiate()
			node.set("change_scenes", false)
			root.add_child(node)
		6:
			_test_menu(node)
			_free_node()
		7:
			node = load("res://scenes/tutorial.tscn").instantiate()
			root.add_child(node)
		9:
			_test_tutorial(node)
			_free_node()
		11:
			_finish()
			return true
	return false


func _free_node() -> void:
	if node != null:
		root.remove_child(node)
		node.free()
		node = null


# ---------------------------------------------------------------- Options

func _test_options() -> void:
	GameOptions.ensure_loaded() # Fichier absent : valeurs par défaut
	check(GameOptions.key_for("halt") == KEY_H, "touche par défaut de la halte")
	check(AudioServer.get_bus_index(GameOptions.BUS_MUSIC) >= 0, "bus Musique créé")
	check(AudioServer.get_bus_index(GameOptions.BUS_SFX) >= 0, "bus Effets créé")

	GameOptions.master_volume = 0.7
	GameOptions.music_volume = 0.25
	GameOptions.sfx_volume = 0.0
	GameOptions.fullscreen = true
	GameOptions.speed = 1.5
	GameOptions.difficulty = "hard"
	check(GameOptions.bind_key("halt", KEY_J).contains("J"), "rebind halte sur J")
	check(GameOptions.save_options(), "écriture de options.cfg")

	# On brouille tout puis on recharge depuis le fichier
	GameOptions.reset_all()
	check(GameOptions.key_for("halt") == KEY_H, "reset_all remet H")
	GameOptions.load_options()
	check(is_equal_approx(GameOptions.master_volume, 0.7), "volume général rechargé")
	check(is_equal_approx(GameOptions.music_volume, 0.25), "volume musique rechargé")
	check(is_equal_approx(GameOptions.sfx_volume, 0.0), "volume effets rechargé")
	check(GameOptions.fullscreen, "plein écran rechargé")
	check(is_equal_approx(GameOptions.speed, 1.5), "vitesse rechargée")
	check(GameOptions.difficulty == "hard", "difficulté d'escarmouche rechargée")
	check(GameOptions.key_for("halt") == KEY_J, "touche de halte rechargée (J)")

	# Application aux bus
	GameOptions.apply_audio()
	var mi := AudioServer.get_bus_index(GameOptions.BUS_MUSIC)
	check(is_equal_approx(AudioServer.get_bus_volume_db(mi), linear_to_db(0.25)), "volume du bus Musique appliqué")
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index(GameOptions.BUS_SFX)), "bus Effets coupé à 0 %")

	# Conflit : F appartient à « formation » → échange des touches
	var msg := GameOptions.bind_key("halt", KEY_F)
	check(GameOptions.key_for("halt") == KEY_F and GameOptions.key_for("formation") == KEY_J, "conflit résolu par échange : " + msg)
	check(GameOptions.conflicts().is_empty(), "aucune touche en double")
	# Touches réservées : Espace, et la position physique de la caméra (Z en AZERTY = W physique)
	msg = GameOptions.bind_key("rain", KEY_SPACE, KEY_SPACE)
	check(GameOptions.key_for("rain") == KEY_T and msg.contains("réservée"), "Espace refusée")
	msg = GameOptions.bind_key("rain", KEY_Z, KEY_W)
	check(GameOptions.key_for("rain") == KEY_T and msg.contains("caméra"), "touche de caméra (Z AZERTY) refusée")
	# Une lettre AZERTY hors caméra (A logique = Q physique) est acceptée
	GameOptions.bind_key("rain", KEY_A, KEY_Q)
	check(GameOptions.key_for("rain") == KEY_A, "A (AZERTY) acceptée")
	# Remappage vers les touches par défaut, utilisé par battle.gd
	check(GameOptions.remap_key(KEY_A) == KEY_T, "A déclenche la pluie")
	check(GameOptions.remap_key(KEY_T) == KEY_NONE, "T ne fait plus rien")
	check(GameOptions.remap_key(KEY_K) == KEY_K, "touche non liée inchangée")
	GameOptions.reset_keys()
	check(GameOptions.key_for("rain") == KEY_T and GameOptions.key_for("halt") == KEY_H, "touches par défaut")
	GameOptions.reset_all()
	GameOptions.save_options()
	GameOptions.apply_audio()


func key_event(code: int, physical := KEY_NONE, ctrl := false) -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = code as Key
	k.physical_keycode = (physical if physical != KEY_NONE else code) as Key
	k.ctrl_pressed = ctrl
	k.pressed = true
	return k


func _test_rebind_in_battle(b: Node) -> void:
	var r: Regiment = b.player_regiments()[0]
	for o in b.regiments:
		o.selected = false
	r.selected = true
	r.dest = r.center + Vector2(0, -300)
	b._unhandled_input(key_event(KEY_H))
	check(r.dest.distance_to(r.center) > 200.0, "H ne fait plus halte après rebind")
	b._unhandled_input(key_event(KEY_J))
	check(r.dest.distance_to(r.center) < 1.0, "J (nouvelle touche) fait halte")
	# Vitesse du jeu : V fait passer de x1 à x1,5
	var before: float = b.game_speed
	b._unhandled_input(key_event(KEY_V))
	check(not is_equal_approx(b.game_speed, before), "V change la vitesse")
	GameOptions.speed = 1.0
	GameOptions.save_options()
	print("Rebind en bataille : %s" % ("OK" if fails.is_empty() else "ÉCHEC"))


# ---------------------------------------------------------------- Menu

func _buttons(n: Node) -> Array[String]:
	var out: Array[String] = []
	for c in n.find_children("*", "Button", true, false):
		out.append((c as Button).text)
	return out


func _test_menu(m: Node) -> void:
	var labels := _buttons(m)
	for want in ["Continuer la campagne", "Nouvelle campagne", "Tutoriel", "Escarmouche", "Options", "Quitter"]:
		check(want in labels, "bouton « %s » présent" % want)
	# « Nouvelle campagne » : choix de la difficulté, puis la carte
	m.new_campaign()
	check(m.page == "new_campaign" and m.last_scene == "", "nouvelle campagne → choix de la difficulté")
	var choice := _buttons(m)
	for want in ["Facile", "Normal", "Difficile", "Retour"]:
		check(want in choice, "bouton de difficulté « %s »" % want)
	m.confirm_new_campaign("hard")
	check(m.last_scene == m.CAMPAIGN_SCENE, "nouvelle campagne → carte")
	check(CampaignState.has_save(), "nouvelle campagne sauvegardée")
	check(CampaignState.current.difficulty == "hard" and CampaignState.load_game().difficulty == "hard", "difficulté de la campagne choisie au menu et sauvegardée")
	# Avec sauvegarde : même page, avec l'avertissement
	m.last_scene = ""
	m.new_campaign()
	check(m.page == "new_campaign" and m.last_scene == "", "avertissement si une sauvegarde existe")
	m.back_to_main()
	m.continue_campaign()
	check(m.last_scene == m.CAMPAIGN_SCENE and CampaignState.current != null, "continuer la campagne")
	m.start_tutorial()
	check(m.last_scene == m.TUTORIAL_SCENE, "tutoriel")
	m.start_skirmish()
	check(m.last_scene == m.BATTLE_SCENE and not CampaignState.current.in_battle(), "escarmouche hors campagne")
	# Options : écran « appuyez sur une touche »
	m.open_options()
	check(m.page == "options", "page Options")
	m.start_rebind("rain")
	check(m.waiting_action == "rain", "attente d'une touche")
	m.capture_key(key_event(KEY_K))
	check(GameOptions.key_for("rain") == KEY_K and m.waiting_action == "", "pluie sur K depuis le menu")
	var cfg := ConfigFile.new()
	cfg.load(OPTIONS_TEST)
	check(int(cfg.get_value("touches", "rain", 0)) == KEY_K, "rebind écrit dans options.cfg")
	m.start_rebind("rain")
	m.capture_key(key_event(KEY_ESCAPE))
	check(GameOptions.key_for("rain") == KEY_K, "Échap annule le changement")
	m.reset_keys()
	check(GameOptions.key_for("rain") == KEY_T, "touches par défaut depuis le menu")
	m.set_volume("music", 0.5)
	check(is_equal_approx(GameOptions.music_volume, 0.5), "curseur de musique")
	m.set_difficulty(0)
	cfg.load(OPTIONS_TEST)
	check(GameOptions.difficulty == "easy" and str(cfg.get_value("jeu", "difficulte", "")) == "easy", "difficulté d'escarmouche choisie dans les Options")
	m.back_to_main()
	GameOptions.reset_all()
	GameOptions.save_options()
	CampaignState.current = null
	print("Menu : %s" % ("OK" if fails.is_empty() else "ÉCHEC"))


# ---------------------------------------------------------------- Tutoriel

func screen_of(b: Node2D, world: Vector2) -> Vector2:
	return b.get_canvas_transform() * world


func mouse(b: Node2D, button: MouseButton, world: Vector2, pressed: bool, double := false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	e.double_click = double
	e.position = screen_of(b, world)
	b._unhandled_input(e)


func motion(b: Node2D, world: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = screen_of(b, world)
	b._unhandled_input(e)


func run_for(b: Node, seconds: float) -> void:
	for i in int(seconds / STEP):
		b.simulate(STEP)
	b.check_steps()


func expect_step(b: Node, id: String) -> void:
	check(b.current_id() == id, "tutoriel : étape « %s » attendue, on est à « %s »" % [id, b.current_id()])


func _test_tutorial(b: Node2D) -> void:
	check(b.steps.size() == 8, "8 étapes")
	check(b.player_regiments().size() == 4, "armée réduite du joueur")
	var enemies := 0
	for r in b.regiments:
		if r.team == 1:
			enemies += 1
	check(enemies == 3, "petite armée ennemie")
	expect_step(b, "select")
	# Espace trop tôt : refusé, l'ennemi attend
	b._unhandled_input(key_event(KEY_SPACE))
	check(b.state == 0, "Espace refusée avant l'étape prévue")
	var enemy_pos: Array[Vector2] = []
	for r in b.regiments:
		if r.team == 1:
			enemy_pos.append(r.center)
	run_for(b, 2.0)

	# 1. Sélectionner : clic gauche sur les piquiers
	var spear: Regiment = b.player_regiments()[0]
	mouse(b, MOUSE_BUTTON_LEFT, spear.center, true)
	mouse(b, MOUSE_BUTTON_LEFT, spear.center, false)
	b.check_steps()
	check(spear.selected, "clic gauche sélectionne")
	expect_step(b, "move")

	# 2. Déplacer : clic droit sur le sol
	var goal := spear.center + Vector2(-60, -120)
	mouse(b, MOUSE_BUTTON_RIGHT, goal, true)
	mouse(b, MOUSE_BUTTON_RIGHT, goal, false)
	b.check_steps()
	expect_step(b, "line")
	run_for(b, 3.0)

	# 3. Ligne de front : Ctrl+A puis clic droit glissé
	b._unhandled_input(key_event(KEY_A, KEY_Q, true)) # Ctrl+A en AZERTY (A logique, Q physique)
	check(b.selected_regiments().size() == 4, "Ctrl+A sélectionne tout")
	var a := Vector2(1150, 1500)
	var c := Vector2(2050, 1500)
	mouse(b, MOUSE_BUTTON_RIGHT, a, true)
	motion(b, (a + c) * 0.5)
	motion(b, c)
	mouse(b, MOUSE_BUTTON_RIGHT, c, false)
	b.check_steps()
	expect_step(b, "formation")
	run_for(b, 4.0)

	# 4. Formation : touche F (touches 1 = piquiers d'abord)
	b._unhandled_input(key_event(KEY_1))
	b._unhandled_input(key_event(GameOptions.key_for("formation")))
	b.check_steps()
	check(spear.formation != Regiment.Formation.LINE, "F change la formation")
	expect_step(b, "run")

	# 5. Courir : double clic droit
	var run_to := spear.center + Vector2(0, -80)
	mouse(b, MOUSE_BUTTON_RIGHT, run_to, true, true)
	mouse(b, MOUSE_BUTTON_RIGHT, run_to, false)
	b.check_steps()
	expect_step(b, "start")
	run_for(b, 3.0)
	# L'ennemi n'a pas bougé pendant le déploiement
	var k := 0
	for r in b.regiments:
		if r.team == 1:
			check(r.center.distance_to(enemy_pos[k]) < 12.0, "l'ennemi attend le début de la bataille")
			k += 1

	# 6. Lancer la bataille
	b._unhandled_input(key_event(KEY_SPACE))
	b.check_steps()
	check(b.state == 1, "Espace lance la bataille")
	expect_step(b, "cavalry")

	# 7. La cavalerie (touche 4) sur les archers ennemis
	var archers: Regiment = null
	for r in b.regiments:
		if r.team == 1 and r.type == "archer":
			archers = r
	b._unhandled_input(key_event(KEY_4))
	var cav: Regiment = b.selected_regiments()[0]
	check(cav.type == "cavalry", "touche 4 = cavalerie")
	b.rebuild_grid()
	mouse(b, MOUSE_BUTTON_RIGHT, archers.alive_soldiers()[0].pos, true)
	mouse(b, MOUSE_BUTTON_RIGHT, archers.alive_soldiers()[0].pos, false)
	b.check_steps()
	check(cav.target == archers, "clic droit sur les archers : attaque")
	expect_step(b, "win")

	# 8. Gagner : l'infanterie charge l'ennemi le plus proche
	var t := 0.0
	while b.state == 1 and t < 400.0:
		for r in b.player_regiments():
			if r.target == null and r.type != "archer":
				r.target = b.nearest_enemy_regiment(r, INF, true)
		run_for(b, 2.0)
		t += 2.0
	b.check_steps()
	check(b.state == 2, "tutoriel gagné (état %d après %d s)" % [b.state, int(t)])
	check(b.finished(), "toutes les étapes validées")
	# Bilan simplifié (sans campagne) : recommencer ou menu principal
	var rep: Dictionary = b.end_report
	check(bool(rep.get("tutorial", false)) and (rep.get("campaign", {}) as Dictionary).is_empty() and rep["outcome"] == "victory",
		"tutoriel : bilan absent ou en mode campagne")
	check(b.report_panel != null and b.report_panel.buttons.size() == 2, "tutoriel : panneau du bilan sans ses deux boutons")
	print("Tutoriel : %s (victoire en %d s)" % ["OK" if fails.is_empty() else "ÉCHEC", int(t)])


func _finish() -> void:
	for p in [OPTIONS_TEST, SAVE_TEST]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	for i in range(1, CampaignState.SLOT_COUNT + 1):
		CampaignState.delete_slot(i)
	for e in counter.errors:
		fails.append("erreur moteur : " + e)
	if fails.is_empty():
		print("MENU TEST OK")
		quit(0)
	else:
		for f in fails:
			print("ÉCHEC : ", f)
		print("MENU TEST ÉCHOUÉ (%d)" % fails.size())
		quit(1)
