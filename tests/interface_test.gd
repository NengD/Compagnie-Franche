extends SceneTree
## Test headless de l'interface de bataille :
##   godot --headless --path . -s tests/interface_test.gd
## - options : aide mémorisée, formes des camps, sous-titres, touches de caméra (physiques,
##   échange, refus des touches prises ou réservées, fichier invalide) ;
## - B4 : numéros des régiments fixes (mort ou en fuite : la place reste), touches 1 à 8 ;
## - aide F1 repliée par défaut et mémorisée ; info-bulle ; sous-titres ;
## - caméra : la taille de l'interface n'agrandit pas le terrain, pixels entiers ;
## - HUD et bilan qui tiennent à 150 % dans une fenêtre 1280×720 (vue 853×480).
## N'utilise pas les vrais fichiers du joueur (options de test dans user://).
## Code de sortie : 0 si tout va bien, 1 sinon.

const OPTIONS_TEST := "user://test_interface_options.cfg"


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
var b: Battle
var report: BattleReport


func check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)
		push_warning("ÉCHEC : " + msg)


func _initialize() -> void:
	AudioServer.set_bus_mute(0, true) # Aucun son pendant les tests
	OS.add_logger(counter)
	GameOptions.path = OPTIONS_TEST
	GameOptions.loaded = false
	CampaignState.current = null
	_remove_options()
	_test_options()
	print("Options : %s" % ("OK" if fails.is_empty() else "ÉCHEC"))


func _process(_delta: float) -> bool:
	frame += 1
	match frame:
		1:
			GameOptions.reset_all()
			GameOptions.subtitles = true
			GameOptions.save_options()
			b = load("res://scenes/main.tscn").instantiate()
			b.seed_override = 77
			root.add_child(b)
		3:
			_test_help_and_tooltip()
			_test_roster()
			_test_camera()
			_test_layout()
			b.start_battle()
		5:
			_test_captions()
			GameOptions.team_shapes = true # Le dessin des formes doit passer sans erreur
		7:
			GameOptions.set_ui_scale(1.5)
			report = BattleReport.new()
			report.setup(b.build_end_report(), b)
			root.add_child(report)
		10:
			_test_report()
			_finish()
			return true
	return false


func _remove_options() -> void:
	if FileAccess.file_exists(OPTIONS_TEST):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(OPTIONS_TEST))


# ---------------------------------------------------------------- Options

func _test_options() -> void:
	GameOptions.ensure_loaded()
	check(not GameOptions.show_help, "aide repliée par défaut")
	check(not GameOptions.team_shapes and not GameOptions.subtitles, "accessibilité désactivée par défaut")
	check(GameOptions.key_for("cam_up") == KEY_W and GameOptions.camera_keys_label() == "WASD", "caméra par défaut : WASD physique (ZQSD en AZERTY)")
	check(GameOptions.conflicts().is_empty(), "aucun conflit par défaut")

	# Touches de caméra : refus des touches réservées ou prises par une action
	var msg := GameOptions.bind_key("cam_up", KEY_H, KEY_H)
	check(GameOptions.key_for("cam_up") == KEY_W and msg.contains("Halte"), "caméra sur H (halte) refusée : " + msg)
	msg = GameOptions.bind_key("cam_up", KEY_1, KEY_1)
	check(GameOptions.key_for("cam_up") == KEY_W and msg.contains("réservée"), "caméra sur 1 refusée")
	msg = GameOptions.bind_key("cam_up", KEY_UP, KEY_UP)
	check(GameOptions.key_for("cam_up") == KEY_W and msg.contains("réservée"), "caméra sur une flèche refusée")
	# Échange entre deux touches de caméra
	msg = GameOptions.bind_key("cam_up", KEY_A, KEY_A)
	check(GameOptions.key_for("cam_up") == KEY_A and GameOptions.key_for("cam_left") == KEY_W, "échange des touches de caméra : " + msg)
	# Une action ne peut pas prendre une touche de caméra (position physique)
	msg = GameOptions.bind_key("rain", KEY_Q, KEY_A)
	check(GameOptions.key_for("rain") == KEY_T and msg.contains("caméra"), "action sur une touche de caméra refusée : " + msg)
	# Caméra déplacée sur I : la touche W redevient libre pour une action
	GameOptions.bind_key("cam_left", KEY_I, KEY_I)
	check(GameOptions.key_for("cam_left") == KEY_I, "caméra à gauche sur I")
	GameOptions.bind_key("rain", KEY_W, KEY_W)
	check(GameOptions.key_for("rain") == KEY_W, "W libéré par la caméra, pris par la pluie")
	check(GameOptions.conflicts().is_empty(), "aucun conflit après les échanges")
	check(GameOptions.key_label("cam_left") == "I", "nom de la touche de caméra")

	GameOptions.show_help = true
	GameOptions.team_shapes = true
	GameOptions.subtitles = true
	check(GameOptions.save_options(), "écriture des options")
	GameOptions.reset_all()
	check(GameOptions.key_for("cam_up") == KEY_W, "reset_all remet la caméra")
	GameOptions.load_options()
	check(GameOptions.show_help and GameOptions.team_shapes and GameOptions.subtitles, "aide et accessibilité rechargées")
	check(GameOptions.key_for("cam_up") == KEY_A and GameOptions.key_for("cam_left") == KEY_I, "touches de caméra rechargées")
	check(GameOptions.key_for("rain") == KEY_W, "pluie rechargée sur W")

	# Fichier modifié à la main : deux fois la même touche de caméra → touches par défaut
	var cfg := ConfigFile.new()
	cfg.load(OPTIONS_TEST)
	cfg.set_value("touches_camera", "cam_down", KEY_A)
	cfg.save(OPTIONS_TEST)
	GameOptions.load_options()
	check(GameOptions.key_for("cam_up") == KEY_W and GameOptions.key_for("rain") == KEY_T, "touches en double : retour au défaut")
	check(GameOptions.conflicts().is_empty(), "aucun conflit après retour au défaut")
	GameOptions.reset_all()
	GameOptions.save_options()


# ---------------------------------------------------------------- Bataille

func _key(code: int) -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = code as Key
	k.physical_keycode = code as Key
	k.pressed = true
	return k


func _test_help_and_tooltip() -> void:
	check(not b.show_help, "aide repliée au début de la bataille")
	b.orders.handle_key(_key(GameOptions.key_for("help")))
	check(b.show_help and GameOptions.show_help, "F1 déplie l'aide et le mémorise")
	GameOptions.load_options()
	check(GameOptions.show_help, "état de l'aide sauvegardé")
	b.orders.handle_key(_key(GameOptions.key_for("help")))
	check(not GameOptions.show_help, "F1 replie l'aide (mémorisé)")
	var joined := "\n".join(Hud.help_lines())
	check(joined.contains("F11") and joined.contains("Alt+Entrée"), "aide : plein écran")
	check(joined.contains("WASD"), "aide : touches de caméra des Options")
	# Info-bulle d'un ennemi et d'un régiment du joueur
	var foe: Regiment = null
	for r in b.regiments:
		if r.team == Battle.ENEMY:
			foe = r
			break
	var tl := "\n".join(b.hud.tooltip_lines(foe))
	for word in ["ennemi", "Effectif", "Moral", "Endurance", "Rang"]:
		check(tl.contains(word), "info-bulle ennemie sans « %s »" % word)
	var mine: Regiment = b.player_roster()[1]
	check(b.hud.tooltip_lines(mine)[0].begins_with("2  "), "info-bulle : numéro du régiment")
	# Survol : la souris au-dessus d'un régiment le désigne
	var screen: Vector2 = b.get_canvas_transform() * mine.alive_soldiers()[0].pos
	var got := b.hud.find_hovered(screen, b.hud.get_viewport_rect().size)
	check(got == mine, "survol d'un régiment du joueur : %s en %s (vue %s)" % [got, screen, b.hud.get_viewport_rect().size])
	screen = b.get_canvas_transform() * foe.center
	var seen := b.hud.find_hovered(screen, b.hud.get_viewport_rect().size)
	check(foe.hidden or seen == foe or not Rect2(Vector2.ZERO, b.hud.get_viewport_rect().size).has_point(screen), "survol d'un ennemi visible")


func _test_roster() -> void:
	var roster: Array[Regiment] = b.player_roster()
	check(roster.size() == b.player_regiments().size() and roster.size() >= 4, "roster complet au départ")
	var second := roster[1]
	var third := roster[2]
	# Le premier régiment est anéanti, le troisième fuit
	for s in roster[0].soldiers:
		s.alive = false
	roster[0].update_center()
	third.routing = true
	check(b.player_regiments().size() == roster.size() - 2, "régiments vivants et non en fuite")
	var after: Array[Regiment] = b.player_roster()
	check(after.size() == roster.size() and after[1] == second and after[2] == third, "B4 : les numéros ne se décalent pas")
	check(b.orders.roster_number(second) == 2, "B4 : le deuxième reste n° 2")
	for r in b.regiments:
		r.selected = false
	b.orders.last_digit = -1
	b.orders.recall_digit(1, false)
	check(second.selected and b.selected_regiments().size() == 1, "touche 2 : le régiment n° 2")
	for r in b.regiments:
		r.selected = false
	b.orders.recall_digit(0, false)
	check(b.selected_regiments().is_empty(), "touche 1 : régiment anéanti, rien de sélectionné")
	b.orders.recall_digit(2, false)
	check(b.selected_regiments().is_empty(), "touche 3 : régiment en fuite, rien de sélectionné")
	b.hud.queue_redraw()
	third.routing = false


func _test_camera() -> void:
	var cam: BattleCamera = b.camera
	var vs := cam.get_viewport_rect().size
	check(_is_clean(cam.screen_scale()), "zoom réel en pixels entiers : %f" % cam.screen_scale())
	var world_w := vs.x / cam.zoom.x # Largeur de terrain visible (unités du monde)
	GameOptions.set_ui_scale(1.5)
	cam.apply_zoom()
	vs = cam.get_viewport_rect().size
	var world_w2 := vs.x / cam.zoom.x
	check(is_equal_approx(world_w, world_w2), "la taille de l'interface n'agrandit pas le terrain (%f / %f)" % [world_w, world_w2])
	check(_is_clean(cam.screen_scale()), "zoom réel en pixels entiers à 150 %%")
	var before := cam.screen_scale()
	cam.zoom_at(1.15)
	check(cam.screen_scale() > before and _is_clean(cam.screen_scale()), "molette : échelle entière suivante")
	cam.zoom_at(1.0 / 1.15)
	cam.zoom_at(1.0 / 1.15)
	check(cam.screen_scale() < before and _is_clean(cam.screen_scale()), "molette arrière : échelle plus lointaine")
	check(cam.view_zoom >= BattleCamera.ZOOM_MIN and cam.view_zoom <= BattleCamera.ZOOM_MAX, "zoom dans ses bornes")
	GameOptions.set_ui_scale(1.0)
	cam.view_zoom = 1.0
	cam.apply_zoom()


## Entier, ou 1/n.
func _is_clean(e: float) -> bool:
	if e >= 1.0:
		return is_equal_approx(e, roundf(e))
	return is_equal_approx(1.0 / e, roundf(1.0 / e))


func _test_layout() -> void:
	var vs := Vector2(1280, 720) / 1.5 # Vue visible à 150 % dans une fenêtre 1280×720
	var cards := Hud.card_rects(vs, 8)
	check(cards.size() == 8, "8 cartes")
	for i in cards.size():
		check(Rect2(Vector2.ZERO, vs).encloses(cards[i]), "carte %d hors de la vue à 150 %%" % (i + 1))
		if i > 0:
			check(not cards[i].intersects(cards[i - 1]), "cartes %d et %d se chevauchent" % [i, i + 1])
	var lay: Dictionary = b.hud.help_layout(vs, Hud.help_lines())
	var hr: Rect2 = lay["rect"]
	check(Rect2(Vector2.ZERO, vs).encloses(hr), "aide hors de la vue à 150 %")
	check(hr.end.y <= cards[0].position.y, "l'aide passe sous les cartes")


func _test_captions() -> void:
	var texts := ""
	for c in b.hud.captions:
		texts += str(c[0])
	check(texts.contains("charge"), "sous-titre du cor de charge au lancement")
	var n: int = b.hud.captions.size()
	b.add_message("Embuscade !")
	check(b.hud.captions.size() == n + 1, "sous-titre de l'embuscade")
	b.add_message("Embuscade !")
	check(b.hud.captions.size() == n + 1, "sous-titre non répété aussitôt")
	GameOptions.subtitles = false
	b.hud.caption("rout")
	check(b.hud.captions.size() == n + 1, "sous-titres désactivés")


func _test_report() -> void:
	var vs := report.get_viewport_rect().size
	var p := report.panel
	var r := Rect2(p.position, p.size * p.scale)
	check(Rect2(Vector2.ZERO, vs).grow(1.0).encloses(r), "bilan hors de la vue à 150 %% : %s dans %s" % [r, vs])
	GameOptions.set_ui_scale(1.0)


func _finish() -> void:
	if b != null:
		root.remove_child(b)
		b.free()
	if report != null:
		report.free()
	GameOptions.reset_all()
	_remove_options()
	for e in counter.errors:
		fails.append("erreur moteur : " + e)
	if fails.is_empty():
		print("INTERFACE TEST OK")
		quit(0)
	else:
		for f in fails:
			print("ÉCHEC : ", f)
		print("INTERFACE TEST ÉCHOUÉ (%d)" % fails.size())
		quit(1)
