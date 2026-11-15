extends SceneTree
## Test headless de la campagne : marche, solde, désertion, recrutement, contrats, puis deux
## batailles de contrat d'affilée (les pertes de la première doivent se retrouver dans la seconde),
## la sauvegarde (aller-retour, fichier abîmé, reprise au lancement), et enfin la scène de carte.
## Le test écrit dans user://test_campagne.json : la vraie sauvegarde n'est jamais touchée.
##
## Lancer :  godot --headless --path . -s tests/campaign_test.gd
## Code de sortie : 0 si tout va bien, 1 sinon.

const TestPlayer := preload("res://tests/test_player.gd")
const STEP := 0.05
const MAX_TIME := 600.0


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
var camp: CampaignState
var battle: Node
var map: Node
var phase := "battle1"
var waiting := true ## Le _ready de la scène ajoutée n'a pas encore été appelé


func _initialize() -> void:
	OS.add_logger(counter)
	CampaignState.save_path = "user://test_campagne.json"
	CampaignState.delete_save()
	_test_rules()
	_test_save()
	# Première bataille de contrat
	camp = CampaignState.new_game(42)
	CampaignState.current = camp
	_start_contract_battle()


func check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)
		print("ÉCHEC : ", msg)


## Règles de la campagne, sans scène.
func _test_rules() -> void:
	var c := CampaignState.new_game(42)
	check(int(c.gold) == CampaignState.START_GOLD, "or de départ")
	check(c.company.size() == 6 and c.total_men() == 98, "compagnie de départ : %d régiments, %d hommes" % [c.company.size(), c.total_men()])
	for t in CampaignState.TOWNS.size():
		check(not c.contracts_at(t).is_empty(), "aucun contrat à %s" % CampaignState.TOWNS[t]["name"])

	# Marche : les jours passent et la solde est payée
	var to: int = c.neighbours(0)[0]
	var days := c.travel_days(to)
	var wage := c.daily_wage()
	var g0 := c.gold
	check(c.travel(to) == "", "marche vers une ville voisine refusée")
	check(c.location == to and c.day == 1 + days, "marche : lieu %d, jour %d" % [c.location, c.day])
	check(absf(c.gold - (g0 - wage * days)) < 0.01, "marche : solde mal payée (%.1f au lieu de %.1f)" % [c.gold, g0 - wage * days])
	print("Campagne : marche de %d jours vers %s, solde %.1f écus / jour" % [days, CampaignState.TOWNS[to]["name"], wage])
	var far := -1
	for t in CampaignState.TOWNS.size():
		if t != c.location and not t in c.neighbours(c.location):
			far = t
	check(c.travel(far) != "", "marche sans route directe acceptée")

	# Recrutement et complément
	c.gold = 2000.0
	var recruits: Array = CampaignState.TOWNS[c.location]["recruits"]
	var type: String = recruits[0]
	var n := c.company.size()
	var cost := CampaignState.recruit_cost(type, int(UnitTypes.STATS[type]["count"]))
	check(c.recruit(type) == "" and c.company.size() == n + 1, "recrutement refusé")
	check(is_equal_approx(c.gold, 2000.0 - cost), "recrutement : prix")
	var idx := -1
	for i in c.company.size():
		if c.company[i]["type"] in recruits:
			idx = i
	c.company[idx]["men"] = 5
	var g1 := c.gold
	check(c.refill(idx) == "" and int(c.company[idx]["men"]) == int(UnitTypes.STATS[c.company[idx]["type"]]["count"]), "complément refusé")
	check(c.gold < g1, "complément gratuit")
	var not_here := ""
	for t in ["spear", "men_at_arms", "archer", "cavalry"]:
		if not t in recruits:
			not_here = t
	check(c.recruit(not_here) != "", "recrutement d'un type absent de la ville accepté")
	c.gold = 0.0
	check(c.recruit(type) != "", "recrutement sans or accepté")

	# Désertion sans solde
	var men0 := c.total_men()
	c.pass_day()
	check(c.total_men() < men0, "pas de désertion sans solde")

	# Contrat et fin de bataille : pertes reportées, prime payée, contrat retiré
	c.gold = 100.0
	c.refresh_contracts(c.location)
	var k: Dictionary = c.contracts_at(c.location)[0]
	check(c.accept(k) == "" and c.in_battle(), "contrat refusé")
	var army := c.battle_army()
	var surv := []
	var expected := 0
	for r in army:
		var m: int = r["men"]
		@warning_ignore("integer_division")
		var s := m / 2
		surv.append(s)
		expected += s + int(floor((m - s) * CampaignState.WOUNDED_RECOVER))
	c.finish_battle(true, surv)
	check(c.total_men() == expected, "victoire : %d hommes au lieu de %d" % [c.total_men(), expected])
	check(absf(c.gold - (100.0 + int(k["reward"]) - c.daily_wage())) < 0.01, "victoire : prime ou solde incorrecte (%.1f)" % c.gold)
	check(not c.in_battle() and not k in c.contracts and c.victories == 1, "victoire : contrat non soldé")
	print("Campagne : règles OK" if fails.is_empty() else "Campagne : règles en échec")


## Sauvegarde : aller-retour exact (y compris le tirage des futurs contrats), refus des fichiers abîmés.
func _test_save() -> void:
	var c := CampaignState.new_game(77)
	c.travel(c.neighbours(0)[0])
	c.gold = 1000.0
	c.recruit(CampaignState.TOWNS[c.location]["recruits"][0])
	c.company[0]["men"] = 7
	check(c.save(), "sauvegarde : écriture impossible")
	check(CampaignState.has_save() and not FileAccess.file_exists(CampaignState.save_path + ".tmp"), "sauvegarde : fichier absent ou temporaire oublié")
	var l := CampaignState.load_game()
	check(l != null, "sauvegarde : relecture impossible")
	if l == null:
		return
	check(JSON.stringify(l.to_dict()) == JSON.stringify(c.to_dict()), "sauvegarde : données différentes après relecture")
	var k1 := c.make_contract(2)
	var k2 := l.make_contract(2)
	check(k1["title"] == k2["title"] and k1["reward"] == k2["reward"] and k1["seed"] == k2["seed"], "sauvegarde : tirage aléatoire non restauré")
	# Une seconde sauvegarde remplace bien la première
	l.gold = 12.0
	check(l.save() and int(CampaignState.load_game().gold) == 12, "sauvegarde : écrasement impossible")
	# Fichiers abîmés : refusés sans planter
	var f := FileAccess.open(CampaignState.save_path, FileAccess.WRITE)
	f.store_string("{pas du json")
	f.close()
	check(CampaignState.load_game() == null, "sauvegarde : fichier abîmé accepté")
	var d := c.to_dict()
	d["version"] = 99
	f = FileAccess.open(CampaignState.save_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	check(CampaignState.load_game() == null, "sauvegarde : version inconnue acceptée")
	d = c.to_dict()
	d["company"] = [{"type": "dragon", "men": 3}]
	f = FileAccess.open(CampaignState.save_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	check(CampaignState.load_game() == null, "sauvegarde : type d'unité inconnu accepté")
	CampaignState.delete_save()
	print("Sauvegarde : OK")


func _start_contract_battle() -> void:
	camp.refresh_contracts(camp.location)
	var k: Dictionary = camp.contracts_at(camp.location)[0]
	var err := camp.accept(k)
	check(err == "", "contrat refusé : " + err)
	battle = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(battle)
	waiting = true


func _process(_delta: float) -> bool:
	if waiting:
		waiting = false
		if phase == "map":
			return _test_map()
		_check_deployment()
		return false
	if phase == "map":
		return false
	_run_battle()
	return false


## La bataille reprend exactement la compagnie et l'armée du contrat.
func _check_deployment() -> void:
	var army := camp.battle_army()
	var mine: Array = battle.regiments.filter(func(r): return r.team == 0)
	var theirs: Array = battle.regiments.filter(func(r): return r.team == 1)
	check(battle.campaign == camp, "la bataille n'est pas en mode campagne")
	check(mine.size() == army.size(), "%s : %d régiments joueur au lieu de %d" % [phase, mine.size(), army.size()])
	for r in mine:
		var want: int = army[r.company_index]["men"]
		check(r.alive_n == want and r.type == army[r.company_index]["type"],
			"%s : régiment %d avec %d hommes au lieu de %d" % [phase, r.company_index, r.alive_n, want])
	var enemy: Array = camp.pending["enemy"]
	check(theirs.size() == enemy.size(), "%s : %d régiments ennemis au lieu de %d" % [phase, theirs.size(), enemy.size()])
	print("%s : %d hommes contre %d (%s)" % [phase, camp.total_men(), battle.initial_strength[1], camp.pending["title"]])
	battle.start_battle()
	battle.set_meta("player", TestPlayer.new("tactical"))
	battle.set_meta("men_before", camp.total_men())
	battle.set_meta("gold_before", camp.gold)
	battle.set_meta("reward", int(camp.pending["reward"]))


func _run_battle() -> void:
	var player = battle.get_meta("player")
	for i in 40:
		player.update(battle)
		battle.simulate(STEP)
		if battle.state >= 2 or battle.battle_time > MAX_TIME:
			break
	if battle.state < 2 and battle.battle_time <= MAX_TIME:
		return
	if battle.state < 2:
		_finish(["%s : bataille non terminée" % phase])
		return
	var victory: bool = battle.state == 2
	var before: int = battle.get_meta("men_before")
	# Survivants comptés dans la bataille (debout ou enfuis), plus les blessés relevés après une victoire
	var expected := 0
	for r in battle.regiments:
		if r.team != 0:
			continue
		var surv := 0
		for s in r.soldiers:
			if s.alive or s.fled:
				surv += 1
		var n: int = r.soldiers.size()
		if victory:
			surv += int(floor((n - surv) * CampaignState.WOUNDED_RECOVER))
		expected += surv
	print("%s : %s en %.0f s — compagnie %d → %d hommes, or %d → %d" % [phase, "VICTOIRE" if victory else "DÉFAITE",
		battle.battle_time, before, camp.total_men(), int(battle.get_meta("gold_before")), int(camp.gold)])
	check(not camp.in_battle(), "%s : contrat toujours en cours après la bataille" % phase)
	check(camp.total_men() == expected, "%s : %d hommes dans la compagnie au lieu de %d" % [phase, camp.total_men(), expected])
	check(camp.total_men() < before, "%s : aucune perte reportée" % phase)
	check(battle.campaign_report != "", "%s : pas de compte rendu" % phase)
	var saved := CampaignState.load_game()
	check(saved != null and saved.total_men() == camp.total_men() and saved.victories == camp.victories,
		"%s : résultat de la bataille non sauvegardé" % phase)
	if victory:
		check(camp.gold > float(battle.get_meta("gold_before")), "%s : prime non payée" % phase)
	root.remove_child(battle)
	battle.free()
	battle = null

	if phase == "battle1" and not camp.is_destroyed():
		phase = "battle2"
		_start_contract_battle()
		return
	# Carte de campagne
	phase = "map"
	if camp.is_destroyed():
		camp.company.append({"type": "spear", "men": 5}) # Pour pouvoir tester la marche
	camp.gold = 500.0
	camp.save()
	# Comme au lancement du jeu : aucune campagne en mémoire, la carte doit reprendre la sauvegarde
	CampaignState.current = null
	map = (load("res://scenes/campaign.tscn") as PackedScene).instantiate()
	root.add_child(map)
	waiting = true


func _test_map() -> bool:
	var resumed: CampaignState = CampaignState.current
	check(resumed != null and resumed != camp and resumed.day == camp.day and resumed.total_men() == camp.total_men()
		and int(resumed.gold) == 500, "carte : la campagne sauvegardée n'est pas reprise")
	camp = resumed
	check(map.box.get_child_count() > 5, "carte : panneau vide")
	var from := camp.location
	var to: int = camp.neighbours(from)[0]
	var day := camp.day
	map.click_town(to)
	check(map.walking, "carte : la marche ne démarre pas")
	for i in 40:
		map._process(0.2)
	check(camp.location == to and camp.day > day, "carte : la compagnie n'est pas arrivée")
	var after := CampaignState.load_game()
	check(after != null and after.location == to, "carte : la marche n'est pas sauvegardée")
	# Nouvelle campagne : il faut confirmer
	map.do_new_campaign()
	check(CampaignState.current == camp and map.confirm_new, "carte : nouvelle campagne sans confirmation")
	map.cancel_new_campaign()
	map.do_recruit(CampaignState.TOWNS[to]["recruits"][0])
	map.queue_redraw()
	print("Carte : marche %s → %s, %d éléments dans le panneau" % [CampaignState.TOWNS[from]["name"], CampaignState.TOWNS[to]["name"], map.box.get_child_count()])
	root.remove_child(map)
	map.free()
	_finish([])
	return true


func _finish(extra: Array) -> void:
	fails.append_array(extra)
	for e in counter.errors:
		fails.append("erreur : " + e)
	CampaignState.current = null
	CampaignState.delete_save()
	if battle != null:
		root.remove_child(battle)
		battle.free()
	if fails.is_empty():
		print("TEST CAMPAGNE OK")
		quit(0)
	else:
		for f in fails:
			print("  - ", f)
		print("TEST CAMPAGNE ÉCHOUÉ")
		quit(1)
