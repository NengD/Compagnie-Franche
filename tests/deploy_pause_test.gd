extends SceneTree
## Test headless du déploiement et du menu pause :
##   godot --headless --path . -s tests/deploy_pause_test.gd
## - déploiement : aucun coup ni tir avant Espace, même au contact de l'ennemi (témoin : après
##   Espace, les mêmes troupes se battent) ; ordres limités à la zone bleue (clic droit, double clic,
##   ligne tracée, formation de côté) ; ordre d'attaque refusé avec un message ;
## - menu pause (Échap) : la simulation s'arrête puis reprend, Échap revient en arrière / ferme,
##   Reprendre, Options (vitesse), Abandonner en escarmouche = menu principal, tutoriel ;
## - contrat : Abandonner = retraite ordonnée (contrat terminé, sauvegardé), Échap sur l'écran de fin
##   ne rouvre pas le menu, Menu principal = retraite puis menu.
## N'utilise pas les vrais fichiers du joueur (options et campagne de test dans user://).
## Code de sortie : 0 si tout va bien, 1 sinon.

const OPTIONS_TEST := "user://test_pause_options.cfg"
const SAVE_TEST := "user://test_pause_campagne.json"
const STEP := 0.05
const MENU_SCENE := "res://scenes/menu.tscn"


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
var battle: Node2D
var camp: CampaignState


func check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)
		push_warning("ÉCHEC : " + msg)


func _initialize() -> void:
	OS.add_logger(counter)
	GameOptions.path = OPTIONS_TEST
	GameOptions.loaded = false
	CampaignState.save_path = SAVE_TEST
	CampaignState.current = null
	CampaignState.event_chance = 0.0
	CampaignState.delete_file(SAVE_TEST) # Avec sa copie de secours (.bak)
	for p in [OPTIONS_TEST, SAVE_TEST]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _process(_delta: float) -> bool:
	frame += 1
	match frame:
		1:
			battle = _new_battle("res://scenes/main.tscn")
		2:
			_test_rain_key("escarmouche", true)
			_test_deploy_orders()
			print("Déploiement, ordres bornés à la zone bleue : %s" % _status())
			_test_deploy_no_combat()
			print("Déploiement, aucun combat avant Espace : %s" % _status())
			_test_pause_skirmish()
			print("Menu pause en escarmouche : %s" % _status())
			_free_battle()
			battle = _new_battle("res://scenes/tutorial.tscn")
		3:
			_test_rain_key("tutoriel", true)
			_test_pause_tutorial()
			print("Menu pause dans le tutoriel : %s" % _status())
			_free_battle()
			camp = CampaignState.new_game(42)
			CampaignState.current = camp
			_accept_contract()
			battle = _new_battle("res://scenes/main.tscn")
		4:
			_test_rain_key("contrat", false)
			_test_contract_abandon()
			print("Contrat : abandonner = retraite : %s" % _status())
			_free_battle()
			_accept_contract()
			battle = _new_battle("res://scenes/main.tscn")
		5:
			_test_contract_main_menu()
			print("Contrat : menu principal = retraite : %s" % _status())
			_free_battle()
			_finish()
			return true
	return false


func _status() -> String:
	return "OK" if fails.is_empty() and counter.errors.is_empty() else "ÉCHEC"


func _new_battle(path: String) -> Node2D:
	var b := (load(path) as PackedScene).instantiate() as Node2D
	b.set("seed_override", 777)
	b.set("terrain_override", "plain")
	root.add_child(b)
	return b


func _free_battle() -> void:
	if battle != null:
		root.remove_child(battle)
		battle.free()
		battle = null


func _accept_contract() -> void:
	camp.refresh_contracts(camp.location)
	var err := camp.accept(camp.contracts_at(camp.location)[0])
	check(err == "", "contrat refusé : " + err)


# ---------------------------------------------------------------- Outils

func key_event(code: int) -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = code as Key
	k.physical_keycode = code as Key
	k.pressed = true
	return k


func press_key(code: int) -> void:
	battle._unhandled_input(key_event(code))


func press_button(text: String) -> bool:
	var menu: Control = battle.pause_menu
	for c in menu.find_children("*", "Button", true, false):
		var b := c as Button
		if b.text == text and b.is_inside_tree():
			b.pressed.emit()
			return true
	check(false, "bouton « %s » absent (page %s)" % [text, menu.page])
	return false


func select_only(r: Regiment) -> void:
	for x in battle.regiments:
		x.selected = x == r


func first_of(team: int, type: String) -> Regiment:
	for r in battle.regiments:
		if r.team == team and r.type == type and not r.is_dead():
			return r
	return null


func teleport(r: Regiment, p: Vector2, face: Vector2) -> void:
	r.dest = p
	r.facing = face
	r.target = null
	var alive := r.alive_soldiers()
	for i in alive.size():
		alive[i].pos = r.slot_position(i, alive.size())
	r.update_center()


func team_hp(team: int) -> float:
	var hp := 0.0
	for s in battle.soldiers:
		if s.alive and s.regiment.team == team:
			hp += s.hp
	return hp


## Plus petite ordonnée des places de la formation (le haut du régiment).
func top_of_slots(r: Regiment) -> float:
	var n := r.alive_n
	var top := INF
	for i in n:
		top = minf(top, r.slot_position(i, n).y)
	return top


func slots_inside_world(r: Regiment) -> bool:
	var n := r.alive_n
	for i in n:
		var p := r.slot_position(i, n)
		if p.x < 0.0 or p.y < 0.0 or p.x > battle.WORLD_SIZE.x or p.y > battle.WORLD_SIZE.y:
			return false
	return true


# ---------------------------------------------------------------- Déploiement

func _test_deploy_orders() -> void:
	check(battle.state == battle.State.DEPLOY, "la bataille ne commence pas en déploiement")
	var top: float = battle.deploy_top()
	var spear := first_of(0, "spear")
	var cav := first_of(0, "cavalry")
	# Clic droit simple loin au-dessus de la zone bleue
	select_only(spear)
	battle.issue_order(Vector2(1600, 500))
	check(top_of_slots(spear) >= top, "clic droit : formation au-dessus de la zone (%.0f < %.0f)" % [top_of_slots(spear), top])
	check(spear.dest.y < 1600.0, "clic droit : le régiment devrait tout de même avancer jusqu'au bord de la zone")
	# Double clic (course) dans un coin
	select_only(cav)
	battle.issue_order(Vector2(3, 900), true)
	check(top_of_slots(cav) >= top and slots_inside_world(cav), "double clic : formation hors de la zone ou du monde")
	# Deux régiments à la fois : chacun borné
	spear.selected = true
	battle.issue_order(Vector2(2000, 1300))
	for r in [spear, cav]:
		check(top_of_slots(r) >= top, "ordre groupé : %s au-dessus de la zone" % r.display_name())
	# Ligne tracée au-dessus de la zone
	select_only(spear)
	battle.issue_line_order(Vector2(1300, 1000), Vector2(1700, 1000))
	check(top_of_slots(spear) >= top and spear.cols_override > 0, "ligne tracée : formation au-dessus de la zone")
	# Ligne verticale (régiment de côté : sa largeur s'étend en hauteur)
	battle.issue_line_order(Vector2(1500, 1350), Vector2(1500, 1900))
	check(top_of_slots(spear) >= top and slots_inside_world(spear), "ligne verticale : formation hors de la zone")
	# Le régiment rejoint bien sa place sans franchir la limite
	for i in 300:
		battle.simulate(STEP)
	var highest := INF
	for s in spear.soldiers:
		if s.alive:
			highest = minf(highest, s.pos.y)
	check(highest >= top - 6.0, "les soldats franchissent la limite de déploiement (y = %.0f)" % highest)
	# Ordre d'attaque sur un ennemi : refusé, avec un message
	var foe := first_of(1, "spear")
	var dest_before := spear.dest
	battle.messages.clear()
	battle.issue_order(foe.center)
	check(spear.target == null, "déploiement : un ordre d'attaque a été accepté")
	check(spear.dest == dest_before, "déploiement : l'ordre d'attaque refusé a déplacé le régiment")
	var said := false
	for m in battle.messages:
		if "déploiement" in str(m[0]):
			said = true
	check(said, "déploiement : pas de message quand l'attaque est refusée")
	# Les mêmes ordres en bataille ne sont plus bornés
	battle.state = battle.State.BATTLE
	battle.issue_order(Vector2(1600, 800))
	check(spear.dest.y < 900.0, "en bataille, la destination ne devrait plus être bornée")
	battle.state = battle.State.DEPLOY
	for r in battle.regiments:
		r.selected = false


func _test_deploy_no_combat() -> void:
	var foe := first_of(1, "spear")
	var foe_archers := first_of(1, "archer")
	var mine := first_of(0, "men_at_arms")
	var archers := first_of(0, "archer")
	# Au contact : nos hommes d'armes collés aux piquiers ennemis, nos archers à bonne portée
	teleport(mine, foe.center + Vector2(0, 22), Vector2.UP)
	teleport(archers, foe.center + Vector2(220, 160), Vector2.UP)
	foe.target = mine # Même un ordre d'attaque donné à l'ennemi ne doit rien faire
	archers.target = foe
	foe_archers.target = archers
	var hp0: float = team_hp(0)
	var hp1: float = team_hp(1)
	battle.arrows.clear()
	var arrows := 0
	for i in 200:
		battle.simulate(STEP)
		arrows += battle.arrows.size()
	check(team_hp(0) == hp0 and team_hp(1) == hp1, "déploiement : des dégâts ont été faits (%.0f → %.0f, %.0f → %.0f)" % [hp0, team_hp(0), hp1, team_hp(1)])
	check(arrows == 0, "déploiement : %d flèche(s) tirée(s)" % arrows)
	check(mine.target == null and foe.target == null and archers.target == null, "déploiement : des cibles d'attaque subsistent")
	check(battle.state == battle.State.DEPLOY and battle.battle_time == 0.0, "déploiement : la bataille a démarré toute seule")
	# Témoin : une fois la bataille lancée, les mêmes troupes se battent
	press_key(KEY_SPACE)
	check(battle.state == battle.State.BATTLE, "Espace ne lance pas la bataille")
	for i in 80:
		battle.simulate(STEP)
	check(team_hp(1) < hp1, "témoin : aucun dégât après le lancement de la bataille")


# ---------------------------------------------------------------- Menu pause

func _test_pause_skirmish() -> void:
	check(battle.state == battle.State.BATTLE, "pause : la bataille devrait être lancée")
	press_key(KEY_ESCAPE)
	check(battle.menu_open(), "Échap n'ouvre pas le menu pause")
	battle.pause_menu.change_scenes = false
	var t0: float = battle.battle_time
	var s: Soldier = null
	for x in battle.soldiers:
		if x.alive:
			s = x
			break
	var p0 := s.pos
	var cam0: Vector2 = battle.camera.position
	for i in 20:
		battle._process(0.05)
	check(battle.battle_time == t0 and s.pos == p0, "pause : la simulation continue pendant le menu")
	check(battle.camera.position == cam0, "pause : la caméra bouge pendant le menu")
	# Les touches de bataille sont ignorées pendant le menu
	press_key(KEY_SPACE)
	check(not battle.paused, "pause : Espace agit sur la bataille sous le menu")
	# Échap ferme, la simulation reprend
	press_key(KEY_ESCAPE)
	check(not battle.menu_open(), "Échap ne ferme pas le menu pause")
	for i in 5:
		battle._process(0.05)
	check(battle.battle_time > t0, "pause : la simulation ne reprend pas après la fermeture")
	# Page Options : Échap revient à la page principale, puis ferme
	press_key(KEY_ESCAPE)
	press_button("Options")
	check(battle.pause_menu.page == "options", "pause : le bouton Options n'ouvre pas la page")
	var sp := battle.pause_menu.find_child("Vitesse", true, false) as OptionButton
	check(sp != null, "pause : réglage de la vitesse absent")
	if sp != null:
		sp.item_selected.emit(2)
		check(battle.game_speed == GameOptions.SPEEDS[2] and GameOptions.speed == GameOptions.SPEEDS[2], "pause : la vitesse choisie n'est pas appliquée")
		sp.item_selected.emit(0)
	check(battle.pause_menu.find_child("Volume_master", true, false) != null, "pause : volume absent des options")
	press_key(KEY_ESCAPE)
	check(battle.menu_open() and battle.pause_menu.page == "main", "pause : Échap sur une sous-page devrait revenir au menu")
	press_button("Aide")
	check(battle.pause_menu.page == "help", "pause : le bouton Aide n'ouvre pas la page")
	press_button("Retour")
	press_button("Reprendre")
	check(not battle.menu_open(), "pause : Reprendre ne ferme pas le menu")
	# Abandonner en escarmouche : retour au menu principal (après confirmation)
	press_key(KEY_ESCAPE)
	press_button("Abandonner la bataille")
	press_button("Non")
	check(battle.pause_menu.last_scene == "" and battle.menu_open(), "pause : « Non » a quitté la bataille")
	press_button("Abandonner la bataille")
	press_button("Oui, abandonner")
	check(battle.pause_menu.last_scene == MENU_SCENE, "escarmouche : abandonner ne ramène pas au menu principal")
	check(battle.campaign == null and not battle.retreated, "escarmouche : l'abandon ne doit pas sonner de retraite")


func _test_pause_tutorial() -> void:
	check(battle.has_method("current_id"), "le tutoriel n'est pas chargé")
	press_key(KEY_ESCAPE)
	check(battle.menu_open(), "tutoriel : Échap n'ouvre pas le menu pause")
	battle.pause_menu.change_scenes = false
	press_key(KEY_SPACE) # Ignoré (ni message « pas encore », ni lancement)
	check(battle.state == battle.State.DEPLOY, "tutoriel : Espace lance la bataille sous le menu")
	for i in 5:
		battle._process(0.05)
	press_key(KEY_ESCAPE)
	check(not battle.menu_open(), "tutoriel : Échap ne ferme pas le menu")
	battle._process(0.05)
	press_key(KEY_ESCAPE)
	press_button("Menu principal")
	check(battle.pause_menu.last_scene == MENU_SCENE, "tutoriel : Menu principal ne ramène pas au menu")


## La touche de météo (T) : libre en escarmouche et au tutoriel (clair → pluie → brouillard → vent) ;
## en campagne, la météo du jour s'impose, T est sans effet (un court message) et ni la barre ni
## l'aide ne la proposent.
func _test_rain_key(what: String, free: bool) -> void:
	var before := BattleWeather.kind(battle.sim)
	var n_msg: int = battle.messages.size()
	press_key(KEY_T)
	check((BattleWeather.kind(battle.sim) != before) == free,
		"%s : la touche T %s la météo" % [what, "ne change pas" if free else "change"])
	check(battle.messages.size() > n_msg, "%s : T sans message" % what)
	if free:
		for i in BattleWeather.KINDS.size() - 1: # Fait le tour du cycle
			press_key(KEY_T)
		check(BattleWeather.kind(battle.sim) == before, "%s : T ne fait pas le tour des temps" % what)
	var rain_line := GameOptions.key_label("rain") + " : météo"
	var help := " | ".join(Hud.help_lines(battle.campaign == null))
	check(help.contains(rain_line) == free, "%s : l'aide F1 %s la touche de pluie" % [what, "ne montre pas" if free else "montre"])


func _test_contract_abandon() -> void:
	check(battle.campaign == camp, "contrat : la bataille n'est pas en mode campagne")
	var men := camp.total_men()
	press_key(KEY_ESCAPE)
	check(battle.menu_open(), "contrat : Échap n'ouvre pas le menu pause pendant le déploiement")
	battle.pause_menu.change_scenes = false
	press_button("Abandonner la bataille")
	check(battle.pause_menu.page == "confirm_abandon", "contrat : abandonner sans confirmation")
	check(battle.state == battle.State.DEPLOY, "contrat : retraite sonnée avant la confirmation")
	press_button("Oui, sonner la retraite")
	check(battle.state == battle.State.DEFEAT and battle.retreated, "contrat : abandonner ne sonne pas la retraite")
	check(not camp.in_battle(), "contrat : le contrat est toujours en cours après l'abandon")
	check(battle.campaign_report != "", "contrat : pas de compte rendu après l'abandon")
	check(not battle.menu_open(), "contrat : le menu reste ouvert après la retraite")
	check(camp.total_men() == men, "contrat : retraite pendant le déploiement, %d hommes perdus" % (men - camp.total_men()))
	var saved := CampaignState.load_game()
	check(saved != null and not saved.in_battle(), "contrat : résultat de la retraite non sauvegardé")
	# Écran de fin : Échap garde son comportement (rien en contrat, pas de menu pause)
	press_key(KEY_ESCAPE)
	check(not battle.menu_open(), "écran de fin : Échap ne doit pas ouvrir le menu pause")


func _test_contract_main_menu() -> void:
	battle.start_battle()
	for i in 20:
		battle.simulate(STEP)
	press_key(KEY_ESCAPE)
	battle.pause_menu.change_scenes = false
	press_button("Menu principal")
	check(battle.pause_menu.page == "confirm_menu", "contrat : Menu principal sans avertissement")
	check(battle.state == battle.State.BATTLE, "contrat : retraite sonnée avant la confirmation")
	press_button("Oui, retraite et menu")
	check(battle.retreated and battle.state == battle.State.DEFEAT, "contrat : Menu principal ne compte pas comme une retraite")
	check(not camp.in_battle(), "contrat : contrat toujours en cours après Menu principal")
	check(battle.pause_menu.last_scene == MENU_SCENE, "contrat : pas de retour au menu principal")


func _finish() -> void:
	CampaignState.delete_file(SAVE_TEST) # Avec sa copie de secours (.bak)
	for p in [OPTIONS_TEST, SAVE_TEST]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	CampaignState.current = null
	var all := fails.duplicate()
	for e in counter.errors:
		all.append("erreur moteur : " + e)
	if all.is_empty():
		print("Déploiement et menu pause : tout est OK")
		quit(0)
	else:
		for f in all:
			print("ÉCHEC : ", f)
		quit(1)
