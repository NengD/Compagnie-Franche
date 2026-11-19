extends SceneTree
## Test headless des fonctions d'interface ajoutées :
##   godot --headless --path . -s tests/interface_plus_test.gd
## - mini-carte : cadre (coin bas gauche, hors des cartes), clic et glisser qui centrent la caméra,
##   touche N (reconfigurable) qui la cache, état mémorisé dans les options, ennemis cachés absents ;
## - statistiques de bataille : relevés des effectifs toutes les 2 s, lieux des morts par camp,
##   tués par régiment, onglet « Statistiques » du bilan ;
## - aperçu des emplacements : en-tête écrit à côté de la sauvegarde, lu sans la campagne,
##   recréé pour une ancienne sauvegarde, effacé avec l'emplacement ; page des emplacements ;
## - page « Succès » du menu (grille, progression, date) et notification.
## N'utilise pas les fichiers du joueur. Code de sortie : 0 si tout va bien, 1 sinon.

const OPTIONS_TEST := "user://test_interface_plus_options.cfg"
const SLOT_TEST := "user://test_interface_plus_campagne"
const STATS_TEST := "user://test_interface_plus_stats.json"


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
var menu: Node


func check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)
		push_warning("ÉCHEC : " + msg)


func _initialize() -> void:
	AudioServer.set_bus_mute(0, true)
	OS.add_logger(counter)
	GameOptions.path = OPTIONS_TEST
	GameOptions.loaded = false
	_remove(OPTIONS_TEST)
	GameOptions.ensure_loaded()
	GameOptions.reset_all()
	CampaignState.current = null
	CampaignState.slot_prefix = SLOT_TEST
	Stats.path = STATS_TEST
	_remove(STATS_TEST)
	Stats.load_stats()
	_test_recorder_unit()
	_test_preview()


func _process(_delta: float) -> bool:
	frame += 1
	match frame:
		1:
			b = load("res://scenes/main.tscn").instantiate()
			b.seed_override = 4242
			b.terrain_override = "forest"
			root.add_child(b)
		3:
			_test_minimap()
			b.start_battle()
		4:
			_test_battle_stats()
			root.remove_child(b)
			b.free()
			menu = load("res://scenes/menu.tscn").instantiate()
			menu.set("change_scenes", false)
			root.add_child(menu)
		6:
			_test_menu_slots()
		8:
			_test_achievements_page()
		10:
			root.remove_child(menu)
			menu.free()
			_finish()
			return true
	return false


# ---------------------------------------------------------------- Mini-carte

func _test_minimap() -> void:
	var vs := b.hud.get_viewport_rect().size
	check(GameOptions.key_for("minimap") == KEY_N, "touche de la mini-carte : N par défaut")
	check("Mini-carte" in GameOptions.action_name("minimap"), "action « minimap » dans les options")
	var r := Minimap.rect(b.hud, vs)
	check(r.has_area() and r.position.x < vs.x * 0.25 and r.end.y <= vs.y, "mini-carte dans le coin bas gauche : %s" % r)
	check(r.position.y > Hud.BAR_H, "mini-carte sous la barre du haut")
	for c in Hud.card_rects(vs, b.player_roster().size()):
		check(not c.intersects(r), "mini-carte hors des cartes des régiments (%s / %s)" % [c, r])
	check(not b.hud.cards_tab_rect(vs).intersects(r), "mini-carte hors de l'onglet des cartes")
	check(not b.hud.help_layout(vs, Hud.help_lines()).get("rect", Rect2()).intersects(r), "mini-carte hors de l'aide F1")
	var obj := b.hud.objective_rect(vs)
	check(not obj.has_area() or not obj.intersects(r), "mini-carte hors du panneau d'objectif")
	# Conversions aller-retour
	var w := Vector2(800, 1200)
	check(Minimap.to_world(Minimap.to_map(w, r), r).distance_to(w) < 1.0, "conversion monde ↔ mini-carte")

	# Clic sur la mini-carte : la caméra se centre sur ce point du champ
	var target := Vector2(BattleSim.WORLD_SIZE.x * 0.75, BattleSim.WORLD_SIZE.y * 0.5)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Minimap.to_map(target, r)
	b.orders.handle_input(click)
	check(b.camera.position.distance_to(target) < 40.0, "clic sur la mini-carte : caméra en %s (voulu %s)" % [b.camera.position, target])
	check(not b.orders.dragging, "clic sur la mini-carte : pas de cadre de sélection")
	# Glisser : la vue suit
	var move := InputEventMouseMotion.new()
	var target2 := Vector2(BattleSim.WORLD_SIZE.x * 0.3, BattleSim.WORLD_SIZE.y * 0.5)
	move.position = Minimap.to_map(target2, r)
	b.orders.handle_input(move)
	check(b.camera.position.distance_to(target2) < 40.0, "glisser sur la mini-carte : la caméra suit")
	click = click.duplicate()
	click.pressed = false
	b.orders.handle_input(click)
	check(not b.orders.minimap_dragging, "relâcher : fin du glisser")
	# Un clic ailleurs ne bouge pas la caméra et commence une sélection
	var cam := b.camera.position
	click = click.duplicate()
	click.pressed = true
	click.position = vs * 0.5
	b.orders.handle_input(click)
	check(b.camera.position == cam and b.orders.dragging, "clic hors de la mini-carte : sélection normale")
	click = click.duplicate()
	click.pressed = false
	b.orders.handle_input(click)
	# Survol : pas d'info-bulle sur la mini-carte
	check(b.hud.find_hovered(r.get_center(), vs) == null, "pas d'info-bulle au-dessus de la mini-carte")

	# Ennemis cachés : absents de la mini-carte
	var foe: Regiment = null
	for reg in b.regiments:
		if reg.team == Battle.ENEMY:
			foe = reg
			break
	foe.hidden = true
	check(not Minimap.shows(foe), "ennemi caché absent de la mini-carte")
	foe.hidden = false
	check(Minimap.shows(foe), "ennemi visible sur la mini-carte")
	b.player_roster()[0].hidden = true
	check(Minimap.shows(b.player_roster()[0]), "régiment caché du joueur toujours sur la mini-carte")
	b.player_roster()[0].hidden = false
	b.hud.queue_redraw() # Le dessin doit passer sans erreur

	# Touche N : cachée, mémorisée ; un clic à sa place ne déplace plus la caméra
	var key := InputEventKey.new()
	key.keycode = KEY_N
	key.physical_keycode = KEY_N
	key.pressed = true
	b.orders.handle_input(key)
	check(not b.show_minimap and not GameOptions.show_minimap, "touche N : mini-carte cachée")
	check(not Minimap.rect(b.hud, vs).has_area(), "mini-carte cachée : plus de cadre")
	GameOptions.loaded = false
	GameOptions.load_options()
	check(not GameOptions.show_minimap, "mini-carte cachée mémorisée dans les options")
	cam = b.camera.position
	check(not b.orders.minimap_click(Minimap.to_map(target, r)), "mini-carte cachée : le clic ne la vise plus")
	b.orders.handle_input(key)
	check(b.show_minimap and GameOptions.show_minimap, "touche N : mini-carte de retour")
	# Touche reconfigurée
	check(GameOptions.bind_key("minimap", KEY_B, KEY_B) == "" or GameOptions.key_for("minimap") == KEY_B, "mini-carte reconfigurable")
	check(GameOptions.key_for("minimap") == KEY_B, "mini-carte sur B")
	check(GameOptions.remap_key(KEY_B) == KEY_N, "B joue le rôle de N")
	GameOptions.reset_keys()
	# Cartes cachées : la mini-carte descend dans le coin
	b.show_cards = false
	var low := Minimap.rect(b.hud, vs)
	check(low.end.y >= r.end.y - 0.5 and not b.hud.cards_tab_rect(vs).intersects(low), "cartes cachées : mini-carte dans le coin, hors de l'onglet")
	b.show_cards = true
	# Interface à 150 % (vue 853×480) : tient toujours sans chevauchement
	var small := Vector2(853, 480)
	var rs := Minimap.rect(b.hud, small)
	check(rs.has_area() and rs.end.y <= small.y and rs.position.y > Hud.BAR_H, "mini-carte en 853×480 : %s" % rs)
	for c in Hud.card_rects(small, b.player_roster().size()):
		check(not c.intersects(rs), "853×480 : mini-carte hors des cartes")
	print("Mini-carte : %s" % ("OK" if fails.is_empty() else "ÉCHEC"))


# ---------------------------------------------------------------- Statistiques

## Enregistreur seul, sur une simulation sans rendu.
func _test_recorder_unit() -> void:
	var sim := BattleSim.new()
	sim.rng.seed = 99
	sim.generate_world("plain")
	sim.spawn_default_armies()
	var rec := BattleRecorder.new()
	rec.step(sim, 0.5)
	check(rec.samples.is_empty(), "pas de relevé pendant le déploiement")
	sim.start()
	var t := 0.0
	while t < 30.0 and sim.state == BattleSim.State.BATTLE:
		sim.step(0.05)
		rec.step(sim, 0.05)
		t += 0.05
	# Un relevé au départ puis un toutes les 2 s
	check(rec.samples.size() >= 14 and rec.samples.size() <= 17, "relevés toutes les 2 s : %d en %.0f s" % [rec.samples.size(), t])
	check(int(rec.samples[0][1]) == sim.initial_strength[0] or int(rec.samples[0][1]) > 0, "premier relevé : effectif de départ")
	# Tuer des soldats de chaque camp à des endroits connus : comptés une seule fois, au bon endroit
	var killed := [0, 0]
	for r in sim.regiments:
		var s: Soldier = null
		for x in r.soldiers:
			if x.alive:
				s = x
				break
		if s == null:
			continue
		s.pos = Vector2(40, 40) if r.team == 0 else Vector2(3160, 1960)
		sim.damage(s, 9999.0, null)
		killed[r.team] += 1
	var before := [(rec.deaths[0] as Array).size(), (rec.deaths[1] as Array).size()]
	rec.sample(sim)
	rec.sample(sim)
	for team in 2:
		check((rec.deaths[team] as Array).size() - int(before[team]) == killed[team], "morts du camp %d comptés une fois (%d)" % [team, killed[team]])
	var h0 := rec.heat(0)
	var h1 := rec.heat(1)
	check(h0.size() == BattleRecorder.HEAT_COLS * BattleRecorder.HEAT_ROWS, "carte de chaleur : %d cases" % h0.size())
	check(h0[0] >= killed[0], "carte de chaleur : morts du joueur dans la case du coin haut gauche")
	check(h1[h1.size() - 1] >= killed[1], "carte de chaleur : morts ennemis dans la case du coin bas droit")
	# Long combat : au plus MAX_SAMPLES relevés (on en garde un sur deux)
	var long := BattleRecorder.new()
	sim.state = BattleSim.State.BATTLE
	for i in BattleRecorder.MAX_SAMPLES + 50:
		long.sample(sim)
	check(long.samples.size() <= BattleRecorder.MAX_SAMPLES and long.interval > BattleRecorder.INTERVAL, "relevés bornés (%d)" % long.samples.size())
	var d := rec.to_dict(sim)
	check((d["kills"] as Array).size() == sim.regiments.size(), "tués : une ligne par régiment")
	rec.finish(sim)
	var n := rec.samples.size()
	rec.step(sim, 10.0)
	check(rec.samples.size() == n, "plus de relevé après la fin")
	sim.clear()
	print("Enregistreur : %s" % ("OK" if fails.is_empty() else "ÉCHEC"))


## Bataille réelle : bilan avec onglet Statistiques.
func _test_battle_stats() -> void:
	for i in 400: # 20 s de bataille
		b.simulate(0.05)
	check(b.recorder.samples.size() >= 9, "bataille : relevés pendant 20 s (%d)" % b.recorder.samples.size())
	var rep := b.build_end_report()
	check(rep.has("stats") and not (rep["stats"]["samples"] as Array).is_empty(), "bilan : statistiques présentes")
	var kills: Array = rep["stats"]["kills"]
	var mine := kills.filter(func(k): return int(k["team"]) == 0)
	check(mine.size() == b.player_roster().size(), "bilan : tués de chaque régiment du joueur")
	check(mine.all(func(k): return int(k["index"]) >= 0), "bilan : numéro de carte de chaque régiment")
	var report := BattleReport.new()
	report.setup(rep, b)
	root.add_child(report)
	check(report.stats_box != null and not report.stats_box.visible and report.table_box.visible, "bilan : tableau d'abord")
	check(report.find_child("OngletStatistiques", true, false) != null, "bilan : onglet Statistiques")
	report.show_page(1)
	check(report.stats_box.visible and not report.table_box.visible, "bilan : onglet Statistiques affiché")
	for kind in ["heat", "strength", "kills"]:
		check(report.find_child("Graphique_" + kind, true, false) != null, "bilan : graphique %s" % kind)
	report.show_page(0)
	check(report.table_box.visible, "bilan : retour au tableau")
	root.remove_child(report)
	report.free()
	print("Statistiques de bataille : %s" % ("OK" if fails.is_empty() else "ÉCHEC"))


# ---------------------------------------------------------------- Aperçu des emplacements

func _test_preview() -> void:
	for i in range(1, CampaignState.SLOT_COUNT + 1):
		CampaignState.delete_slot(i)
	CampaignState.use_slot(2)
	var c := CampaignState.new_game(5, Difficulty.HARD)
	c.day = 17
	c.gold = 777.0
	c.fame = 42
	check(c.save(), "sauvegarde de l'emplacement 2")
	var head := SavePreview.path_for(CampaignState.slot_path(2))
	check(FileAccess.file_exists(head), "en-tête écrit à côté de la sauvegarde (%s)" % head)
	var d := SavePreview.read_header(head)
	check(int(d.get("day", 0)) == 17 and int(d.get("gold", 0)) == 777 and int(d.get("fame", -1)) == 42, "en-tête : jour, or, renommée")
	check(int(d.get("men", 0)) == c.total_men() and str(d.get("difficulty", "")) == Difficulty.HARD, "en-tête : hommes, difficulté")
	check(absf(float(d.get("saved_at", 0.0)) - c.saved_at) < 1.0, "en-tête : date de la sauvegarde")
	check((d.get("owners", []) as Array).size() == CampaignState.TOWNS.size() and (d.get("pos", []) as Array).size() == 2, "en-tête : villes et position (miniature)")
	var size := FileAccess.get_file_as_bytes(head).size()
	check(size < 2048, "en-tête léger (%d octets)" % size)
	# Lecture sans la campagne : l'en-tête suffit (sauvegarde rendue illisible, l'aperçu reste)
	var f := FileAccess.open(head, FileAccess.WRITE)
	d["day"] = 99 # Repère : si l'aperçu vient de l'en-tête, on lit 99
	f.store_string(JSON.stringify(d))
	f.close()
	check(int(SavePreview.read_slot(2).get("day", 0)) == 99, "aperçu lu dans l'en-tête, sans charger la campagne")
	check(SavePreview.lines(SavePreview.read_slot(2))[0].begins_with("Jour 99"), "lignes de l'aperçu")
	check(SavePreview.date_text(c.saved_at).contains("/") and SavePreview.date_text(0.0) == "date inconnue", "date réelle en clair")
	# Ancienne sauvegarde sans en-tête : relue une fois, puis l'en-tête est écrit
	DirAccess.remove_absolute(ProjectSettings.globalize_path(head))
	var again := SavePreview.read_slot(2)
	check(int(again.get("day", 0)) == 17, "sauvegarde sans en-tête : aperçu recalculé")
	check(FileAccess.file_exists(head), "sauvegarde sans en-tête : en-tête écrit pour la fois suivante")
	check(SavePreview.read_slot(1).is_empty(), "emplacement vide : pas d'aperçu")
	check(SavePreview.terrain_texture() != null, "fond de la miniature")
	# Supprimer l'emplacement efface l'en-tête
	CampaignState.use_slot(3)
	c.save()
	CampaignState.delete_slot(3)
	check(not FileAccess.file_exists(SavePreview.path_for(CampaignState.slot_path(3))), "en-tête effacé avec l'emplacement")
	print("Aperçu des emplacements : %s" % ("OK" if fails.is_empty() else "ÉCHEC"))


func _test_menu_slots() -> void:
	check(menu.continue_slot() == 2, "Continuer : emplacement 2 (d'après les en-têtes)")
	menu.open_slots()
	check(menu.find_child("Miniature_2", true, false) != null, "page des emplacements : miniature de l'emplacement 2")
	check(menu.find_child("Miniature_1", true, false) == null, "emplacement vide : pas de miniature")
	var texts: Array[String] = []
	for l in menu.find_children("*", "Label", true, false):
		texts.append((l as Label).text)
	var all := " | ".join(texts)
	check("Jour 17" in all and "Renommée 42" in all and "Difficile" in all and "Sauvegardé le" in all, "page des emplacements : aperçu (%s)" % all)
	menu.back_to_main()


# ---------------------------------------------------------------- Succès

func _test_achievements_page() -> void:
	Stats.reset()
	Stats.loaded = true
	Stats.data["enemies_killed"] = 37
	Stats.unlock("premiere_victoire")
	check(Achievements.progress("tues_100") == [37, 100], "progression : 37 / 100")
	check(Achievements.progress("premiere_victoire").is_empty(), "succès d'un coup : pas de compteur")
	check(Achievements.unlocked_date("premiere_victoire").contains("/") and Achievements.unlocked_date("siege") == "", "date d'obtention")
	for a in Achievements.LIST:
		check(Achievements.ICONS.has(a["id"]), "icône du succès %s" % a["id"])
	menu.open_achievements()
	check(menu.page == "achievements", "page Succès ouverte")
	var grid: Node = menu.find_child("GrilleSucces", true, false)
	check(grid != null and grid.get_child_count() == Achievements.LIST.size(), "grille : une case par succès")
	var texts: Array[String] = []
	for l in menu.find_children("*", "Label", true, false):
		texts.append((l as Label).text)
	var all := " | ".join(texts)
	check("Succès : 1 / %d" % Achievements.LIST.size() in all and "Obtenu le" in all and "37 / 100" in all, "grille : total, date et progression")
	Achievements.notify(["premiere_victoire"] as Array[String])
	menu.back_to_main()
	var labels: Array[String] = []
	for c in menu.find_children("*", "Button", true, false):
		labels.append((c as Button).text)
	check("Succès" in labels and "Statistiques" in labels, "menu principal : boutons Statistiques et Succès")
	print("Page Succès : %s" % ("OK" if fails.is_empty() else "ÉCHEC"))


# ---------------------------------------------------------------- Fin

func _remove(p: String) -> void:
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _finish() -> void:
	for i in range(1, CampaignState.SLOT_COUNT + 1):
		CampaignState.delete_slot(i)
	_remove(OPTIONS_TEST)
	_remove(STATS_TEST)
	for e in counter.errors:
		fails.append("erreur moteur : " + e)
	if fails.is_empty():
		print("interface_plus : tout est OK")
		quit(0)
	else:
		for f in fails:
			print("ÉCHEC : ", f)
		quit(1)
