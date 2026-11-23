extends SceneTree
## Test headless de la sauvegarde de campagne :
##   godot --headless --path . -s tests/save_test.gd
## - emplacements (chemins, dernier joué, premier libre, suppression, résumé pour le menu) ;
## - migration de l'ancien fichier unique vers l'emplacement 1 ;
## - copie de secours .bak relue quand le fichier principal est abîmé ou absent ;
## - contrat ou embuscade en cours (B3) sauvegardé, relu et repris par la carte ;
## - mode indulgent : la bataille en cours n'est pas sauvegardée ;
## - anciennes versions lisibles, version inconnue refusée ;
## - menu : page des emplacements, nouvelle campagne indulgente, suppression avec confirmation.
## N'utilise que des fichiers de test dans user://. Code de sortie : 0 si tout va bien, 1 sinon.

const PREFIX := "user://test_sauvegarde"


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


func check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)
		push_warning("ÉCHEC : " + msg)


func _initialize() -> void:
	AudioServer.set_bus_mute(0, true) # Aucun son pendant les tests
	OS.add_logger(counter)
	CampaignState.slot_prefix = PREFIX
	CampaignState.event_chance = 0.0
	_clean()
	_test_slots()
	_test_migration()
	_test_backup()
	_test_pending()
	_test_lenient()
	_test_versions()


func _process(_delta: float) -> bool:
	frame += 1
	match frame:
		1:
			_test_map_resume()
		2:
			_test_menu()
		3:
			_clean()
			for e in counter.errors:
				fails.append("erreur moteur : " + e)
			if fails.is_empty():
				print("Sauvegarde : tous les tests passent.")
			else:
				print("Sauvegarde : %d échec(s)" % fails.size())
				for f in fails:
					print("  - " + f)
			quit(0 if fails.is_empty() else 1)
			return true
	return false


func _clean() -> void:
	for i in range(1, CampaignState.SLOT_COUNT + 1):
		CampaignState.delete_slot(i)
	CampaignState.delete_file(CampaignState.legacy_path())
	CampaignState.current = null
	CampaignState.use_slot(1)


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


# ---------------------------------------------------------------- Emplacements

func _test_slots() -> void:
	check(CampaignState.slot_path(2) == PREFIX + "_2.json", "chemin de l'emplacement 2 : " + CampaignState.slot_path(2))
	check(CampaignState.latest_slot() == 0 and CampaignState.free_slot() == 1, "aucun emplacement au départ")
	CampaignState.use_slot(1)
	var a := CampaignState.new_game(11, Difficulty.EASY)
	check(a.save(), "écriture de l'emplacement 1")
	CampaignState.use_slot(3)
	var b := CampaignState.new_game(12, Difficulty.HARD)
	b.gold = 777.0
	check(b.save() and CampaignState.save_path == PREFIX + "_3.json", "écriture de l'emplacement 3")
	check(CampaignState.slot_used(1) and not CampaignState.slot_used(2) and CampaignState.slot_used(3), "emplacements occupés")
	check(CampaignState.free_slot() == 2, "premier emplacement libre")
	check(CampaignState.latest_slot() == 3, "dernier emplacement joué (3) : %d" % CampaignState.latest_slot())
	var l := CampaignState.load_slot(3)
	check(l != null and int(l.gold) == 777 and l.difficulty == Difficulty.HARD, "relecture de l'emplacement 3")
	check(CampaignState.load_slot(1).difficulty == Difficulty.EASY, "les emplacements sont séparés")
	# Résumé affiché par le menu
	var s := l.summary()
	check("Jour 1" in s and "777 écus" in s and "%d hommes" % l.total_men() in s and Difficulty.display_name(Difficulty.HARD) in s, "résumé : " + s)
	check(l.status_text().begins_with("En cours"), "état en cours : " + l.status_text())
	l.ended = "victory"
	l.end_day = 40
	check(l.status_text().begins_with("Terminée") and "40" in l.status_text(), "état terminé : " + l.status_text())
	# Une sauvegarde plus récente de l'emplacement 1 devient « la dernière jouée »
	CampaignState.use_slot(1)
	a.save()
	check(CampaignState.latest_slot() == 1, "dernier emplacement après une nouvelle écriture")
	CampaignState.delete_slot(3)
	check(not CampaignState.slot_used(3) and not FileAccess.file_exists(PREFIX + "_3.json.bak"), "suppression de l'emplacement 3 (et de son .bak)")
	_clean()
	print("Emplacements : OK")


# ---------------------------------------------------------------- Migration

func _test_migration() -> void:
	# Ancien fichier unique en version 4 (sans emplacement, sans mode indulgent ni bataille en cours)
	var c := CampaignState.new_game(21)
	c.gold = 432.0
	var d := c.to_dict()
	d["version"] = 4
	d.erase("lenient")
	_write(CampaignState.legacy_path(), JSON.stringify(d))
	check(CampaignState.migrate_legacy(), "migration de l'ancien fichier")
	check(not FileAccess.file_exists(CampaignState.legacy_path()) and CampaignState.slot_used(1), "ancien fichier déplacé dans l'emplacement 1")
	var l := CampaignState.load_slot(1)
	check(l != null and int(l.gold) == 432 and not l.lenient and not l.in_battle(), "ancienne sauvegarde relue dans l'emplacement 1")
	# Emplacement 1 déjà pris : l'ancien fichier n'écrase rien
	_write(CampaignState.legacy_path(), JSON.stringify(CampaignState.new_game(22).to_dict()))
	check(not CampaignState.migrate_legacy() and int(CampaignState.load_slot(1).gold) == 432, "migration qui écrase l'emplacement 1")
	check(not CampaignState.migrate_legacy(), "migration sans ancien fichier")
	_clean()
	print("Migration : OK")


# ---------------------------------------------------------------- Copie de secours

func _test_backup() -> void:
	var path := CampaignState.save_path
	var c := CampaignState.new_game(31)
	c.gold = 100.0
	c.save()
	check(not FileAccess.file_exists(path + ".bak"), "pas de .bak à la première écriture")
	c.gold = 200.0
	c.save()
	check(FileAccess.file_exists(path + ".bak") and not FileAccess.file_exists(path + ".tmp"), ".bak écrit, .tmp nettoyé")
	check(int(CampaignState.read_file(path + ".bak").gold) == 100, ".bak : version précédente")
	check(int(CampaignState.load_game().gold) == 200 and not CampaignState.loaded_from_backup, "fichier principal relu en priorité")
	# Fichier principal abîmé : la copie de secours est relue
	_write(path, "{pas du json")
	var l := CampaignState.load_game()
	check(l != null and int(l.gold) == 100 and CampaignState.loaded_from_backup, "relecture depuis le .bak")
	# L'écriture suivante ne fait pas du fichier abîmé la nouvelle copie de secours
	l.gold = 300.0
	l.save()
	check(int(CampaignState.read_file(path + ".bak").gold) == 100 and int(CampaignState.load_game().gold) == 300, "fichier abîmé promu en .bak")
	# Fichier principal absent (écriture interrompue) : le .bak suffit
	DirAccess.remove_absolute(path)
	check(CampaignState.has_save() and int(CampaignState.load_game().gold) == 100, "relecture du .bak sans fichier principal")
	# Les deux abîmés : refusés sans planter
	_write(path, "{")
	_write(path + ".bak", "[]")
	check(CampaignState.load_game() == null, "deux fichiers abîmés acceptés")
	_clean()
	print("Copie de secours : OK")


# ---------------------------------------------------------------- Bataille en cours (B3)

func _test_pending() -> void:
	# Contrat accepté : sauvegardé avec la campagne, repris tel quel
	var c := CampaignState.new_game(41)
	var k: Dictionary = c.contracts_at(c.location)[0]
	check(c.accept(k) == "", "contrat accepté")
	c.save()
	var l := CampaignState.load_game()
	check(l != null and l.in_battle(), "contrat en cours sauvegardé")
	if l == null or not l.in_battle():
		return
	check(l.pending["title"] == k["title"] and l.pending["seed"] == k["seed"] and l.pending["enemy"].size() == k["enemy"].size(), "contrat en cours relu à l'identique")
	check(l.contracts.has(l.pending) and is_same(l.contracts[l.contracts.find(l.pending)], l.pending), "contrat en cours repris dans la liste des contrats")
	var zero := []
	zero.resize(l.battle_army().size())
	zero.fill(10)
	l.finish_battle(true, zero, [])
	var still := l.contracts.any(func(x: Dictionary) -> bool: return x["seed"] == k["seed"] and x["title"] == k["title"])
	check(not l.in_battle() and not still, "contrat retiré après la bataille reprise")
	l.save()
	check(not CampaignState.load_game().in_battle(), "bataille terminée encore en cours dans la sauvegarde")
	# Embuscade : hors de la liste des contrats, sauvegardée en entier
	var a := CampaignState.new_game(42)
	a.pending = a.make_ambush(1)
	a.save()
	var la := CampaignState.load_game()
	check(la != null and la.in_battle() and bool(la.pending.get("ambush", false)), "embuscade sauvegardée")
	if la != null and la.in_battle():
		check(la.pending["seed"] == a.pending["seed"] and la.pending["enemy"] == a.pending["enemy"] and int(la.pending["town"]) == 1, "embuscade relue à l'identique")
		check(not la.contracts.has(la.pending), "embuscade hors des contrats")
		check(JSON.stringify(la.to_dict()) == JSON.stringify(a.to_dict()), "embuscade : données différentes après relecture")
	# Bataille en cours invalide : sauvegarde refusée
	var d := a.to_dict()
	d["pending"]["enemy"] = [{"type": "dragon", "men": 3}]
	check(CampaignState.from_dict(JSON.parse_string(JSON.stringify(d))) == null, "embuscade invalide acceptée")
	d = c.to_dict()
	d["pending_index"] = 99
	check(CampaignState.from_dict(JSON.parse_string(JSON.stringify(d))) == null, "rang de contrat invalide accepté")
	_clean()
	print("Bataille en cours : OK")


# ---------------------------------------------------------------- Mode indulgent

func _test_lenient() -> void:
	var c := CampaignState.new_game(51, Difficulty.NORMAL, true)
	check(c.lenient, "mode indulgent à la création")
	c.accept(c.contracts_at(c.location)[0])
	c.save()
	var l := CampaignState.load_game()
	check(l != null and l.lenient and not l.in_battle(), "mode indulgent : la bataille en cours n'est pas sauvegardée")
	var d := c.to_dict()
	check(not d.has("pending") and not d.has("pending_index"), "mode indulgent : aucune bataille dans la sauvegarde")
	c.pending = c.make_ambush(2)
	check(not c.to_dict().has("pending"), "mode indulgent : embuscade non sauvegardée")
	_clean()
	print("Mode indulgent : OK")


# ---------------------------------------------------------------- Versions

func _test_versions() -> void:
	var c := CampaignState.new_game(61)
	var d := c.to_dict()
	check(int(d["version"]) == CampaignState.SAVE_VERSION and CampaignState.SAVE_VERSION >= 10, "version de sauvegarde 10 au moins")
	for v in range(1, CampaignState.SAVE_VERSION):
		var old := d.duplicate(true)
		old["version"] = v
		old.erase("lenient")
		old.erase("world") # Monde vivant : version 7
		for key in ["supplies", "prisoners", "companions", "realm"]: # Vivres, prisonniers, compagnons ; domaine
			old.erase(key)
		var l := CampaignState.from_dict(JSON.parse_string(JSON.stringify(old)))
		check(l != null and not l.lenient and not l.in_battle() and l.world.wars.is_empty(), "version %d illisible" % v)
	d["version"] = CampaignState.SAVE_VERSION + 1
	check(CampaignState.from_dict(d) == null, "version future acceptée")

	print("Versions : OK")


# ---------------------------------------------------------------- Carte : reprise de la bataille

func _map_with(c: CampaignState) -> Node:
	c.save()
	CampaignState.current = null # Comme au lancement du jeu
	var m: Node = (load("res://scenes/campaign.tscn") as PackedScene).instantiate()
	m.auto_launch = false
	root.add_child(m)
	return m


func _free(n: Node) -> void:
	root.remove_child(n)
	n.free()


func _test_map_resume() -> void:
	# Jeu fermé pendant un contrat : la carte relance la bataille
	var c := CampaignState.new_game(71)
	var k: Dictionary = c.contracts_at(c.location)[0]
	c.accept(k)
	var m := _map_with(c)
	check(m.resuming and m.ambushed and CampaignState.current.in_battle(), "carte : bataille de contrat non reprise")
	check(CampaignState.current.pending["title"] == k["title"], "carte : mauvais contrat repris")
	check(CampaignState.load_game().in_battle(), "carte : la bataille reprise n'est plus sauvegardée")
	_free(m)
	# Embuscade pendant la marche : elle ne disparaît plus
	var a := CampaignState.new_game(72)
	a.pending = a.make_ambush(1)
	m = _map_with(a)
	check(m.resuming and bool(CampaignState.current.pending.get("ambush", false)), "carte : embuscade oubliée")
	_free(m)
	# Mode indulgent : retour à l'état d'avant la bataille
	var i := CampaignState.new_game(73, Difficulty.NORMAL, true)
	i.accept(i.contracts_at(i.location)[0])
	m = _map_with(i)
	check(not m.resuming and not CampaignState.current.in_battle(), "carte : mode indulgent, bataille reprise")
	_free(m)
	# Accepter un contrat sur la carte le sauvegarde aussitôt
	var s := CampaignState.new_game(74)
	m = _map_with(s)
	var st: CampaignState = CampaignState.current
	var err := st.accept(st.contracts_at(st.location)[0])
	st.save()
	check(err == "" and CampaignState.load_game().in_battle(), "carte : contrat accepté non sauvegardé")
	_free(m)
	_clean()
	print("Reprise par la carte : OK")


# ---------------------------------------------------------------- Menu

func _buttons(n: Node) -> Array[String]:
	var out: Array[String] = []
	for b in n.find_children("*", "Button", true, false):
		out.append((b as Button).text)
	return out


func _test_menu() -> void:
	# Ancienne sauvegarde : migrée à l'ouverture du menu
	_write(CampaignState.legacy_path(), JSON.stringify(CampaignState.new_game(81).to_dict()))
	var m: Node = (load("res://scenes/menu.tscn") as PackedScene).instantiate()
	m.change_scenes = false
	root.add_child(m)
	check(CampaignState.slot_used(1) and "emplacement 1" in m.notice, "menu : migration à l'ouverture")
	check("Continuer la campagne" in _buttons(m) and "Emplacements de campagne" in _buttons(m), "menu : boutons de campagne %s" % str(_buttons(m)))
	# Page des emplacements
	m.open_slots()
	var labels := _buttons(m)
	check(m.page == "slots" and labels.count("Nouvelle campagne") == CampaignState.SLOT_COUNT and labels.count("Supprimer") == 1 and "Continuer" in labels, "menu : page des emplacements %s" % str(labels))
	var texts: Array[String] = []
	for lb in m.find_children("*", "Label", true, false):
		texts.append((lb as Label).text)
	var all := " | ".join(texts)
	check("Emplacement 3" in all and "Vide." in all and "Jour 1" in all and "En cours" in all, "menu : résumé des emplacements (%s)" % all)
	# Nouvelle campagne indulgente sur l'emplacement 2
	m.new_campaign(2)
	check(m.page == "new_campaign" and m.target_slot == 2 and "Mode indulgent" in _buttons(m), "menu : nouvelle campagne sur l'emplacement 2")
	m.lenient_choice = true
	GameOptions.tutorial_offered = true # Tutoriel guidé déjà proposé (testé dans menu_test.gd)
	m.confirm_new_campaign(Difficulty.HARD)
	check(m.last_scene == m.CAMPAIGN_SCENE and CampaignState.slot == 2, "menu : campagne lancée sur l'emplacement 2")
	var l := CampaignState.load_slot(2)
	check(l != null and l.lenient and l.difficulty == Difficulty.HARD, "menu : mode indulgent et difficulté sauvegardés")
	check(CampaignState.latest_slot() == 2, "menu : l'emplacement 2 devient le dernier joué")
	# Sans précision, une nouvelle campagne prend le premier emplacement libre
	m.new_campaign()
	check(m.target_slot == 3, "menu : premier emplacement libre (%d)" % m.target_slot)
	# Suppression avec confirmation
	m.open_slots()
	m.ask_delete(1)
	check(m.page == "confirm_delete" and "Supprimer" in _buttons(m) and "Annuler" in _buttons(m) and CampaignState.slot_used(1), "menu : confirmation avant suppression")
	m.open_slots() # Annuler
	check(CampaignState.slot_used(1), "menu : suppression annulée")
	m.ask_delete(1)
	m.confirm_delete()
	check(m.page == "slots" and not CampaignState.slot_used(1), "menu : emplacement 1 supprimé")
	# Continuer : l'emplacement choisi (ou le dernier joué)
	m.last_scene = ""
	m.continue_campaign()
	check(m.last_scene == m.CAMPAIGN_SCENE and CampaignState.slot == 2 and CampaignState.current.lenient, "menu : continuer le dernier emplacement")
	_free(m)
	_clean()
	print("Menu des emplacements : OK")
