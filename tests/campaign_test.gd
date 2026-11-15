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
	_test_veterans()
	_test_reputation()
	_test_defeat()
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


## Vétérans : gain d'expérience, rangs, bonus, dilution par les recrues, ennemis classés.
func _test_veterans() -> void:
	var c := CampaignState.new_game(5)
	check(CampaignState.rank_of(c.company[0]) == 0 and float(c.company[0]["xp"]) == 0.0, "vétérans : la compagnie de départ n'est pas faite de recrues")
	c.refresh_contracts(c.location)
	c.accept(c.contracts_at(c.location)[0])
	var army := c.battle_army()
	var surv := []
	var kills := []
	for r in army:
		surv.append(int(r["men"]))
		kills.append(0)
	var full := float(UnitTypes.STATS[army[0]["type"]]["count"])
	kills[0] = int(full) # Le premier régiment tue autant d'ennemis qu'il compte d'hommes
	c.finish_battle(true, surv, kills)
	var want0 := CampaignState.XP_BATTLE + CampaignState.XP_VICTORY + CampaignState.XP_KILLS
	check(is_equal_approx(float(c.company[0]["xp"]), want0), "vétérans : xp du régiment tueur %.1f au lieu de %.1f" % [float(c.company[0]["xp"]), want0])
	check(is_equal_approx(float(c.company[1]["xp"]), CampaignState.XP_BATTLE + CampaignState.XP_VICTORY), "vétérans : xp de victoire")
	check(CampaignState.rank_of(c.company[0]) == 1, "vétérans : pas de promotion à %d xp" % int(c.company[0]["xp"]))
	# Défaite : seulement la participation
	var xp1 := float(c.company[1]["xp"])
	c.refresh_contracts(c.location)
	c.accept(c.contracts_at(c.location)[0])
	c.finish_battle(false, surv, [])
	check(is_equal_approx(float(c.company[1]["xp"]), xp1 + CampaignState.XP_BATTLE), "vétérans : xp de défaite")
	# Dilution : moitié de vétérans, moitié de recrues → moitié de l'expérience
	c.gold = 5000.0
	c.location = 0 # Valombre lève des piquiers et des archers
	var spear := -1
	for i in c.company.size():
		if c.company[i]["type"] == "spear":
			spear = i
	c.company[spear]["xp"] = 300.0
	c.company[spear]["men"] = 10
	var sf := float(UnitTypes.STATS["spear"]["count"])
	check(c.refill(spear) == "", "vétérans : complément refusé")
	check(is_equal_approx(float(c.company[spear]["xp"]), 300.0 * 10.0 / sf), "vétérans : les recrues ne diluent pas l'expérience (%.1f)" % float(c.company[spear]["xp"]))
	check(c.recruit("spear") == "" and float(c.company[-1]["xp"]) == 0.0, "vétérans : un nouveau régiment n'est pas fait de recrues")
	# Bonus de rang sur un régiment de bataille
	var reg := Regiment.new()
	reg.stats = UnitTypes.STATS["spear"]
	reg.set_rank(2)
	check(is_equal_approx(reg.max_morale, float(UnitTypes.STATS["spear"]["morale"]) * (1.0 + 2 * Regiment.RANK_MORALE)) and is_equal_approx(reg.rank_damage(), 1.0 + 2 * Regiment.RANK_DAMAGE), "vétérans : bonus de rang")
	check(CampaignState.rank_of({"type": "spear", "rank": 2}) == 2 and CampaignState.rank_of({"xp": 260.0}) == 2, "vétérans : rang mal lu")
	# Contrats difficiles : ennemis classés
	c.fame = 200
	var ranked := 0
	for i in 20:
		var k := c.make_contract(0)
		for e in k["enemy"]:
			if int(k["difficulty"]) == 3:
				check(int(e["rank"]) >= 1, "vétérans : ost du baron sans expérience")
			if int(e["rank"]) > 0:
				ranked += 1
	check(ranked > 0, "vétérans : aucun ennemi aguerri")
	print("Vétérans : OK")


## Réputation et factions : contrat gagné, rivale, prime modulée, portes fermées, renommée.
func _test_reputation() -> void:
	var c := CampaignState.new_game(9)
	var owned := [0, 0, 0]
	for t in CampaignState.TOWNS.size():
		owned[CampaignState.town_faction(t)] += 1
	check(owned[0] > 0 and owned[1] > 0 and owned[2] > 0 and c.reputation == [0, 0, 0], "réputation : factions mal réparties %s" % str(owned))
	for k in c.contracts:
		check(int(k["faction"]) == CampaignState.town_faction(int(k["town"])) and int(k["difficulty"]) == 1, "réputation : contrat mal attribué ou trop dur sans renommée")
	# Contrat gagné à Valombre (Comté) : le Comté apprécie, sa rivale la Baronnie beaucoup moins
	var f := CampaignState.town_faction(0)
	var rival := int(CampaignState.FACTIONS[f]["rival"])
	var other := 3 - f - rival
	c.accept(c.contracts_at(0)[0])
	var surv := []
	for r in c.battle_army():
		surv.append(int(r["men"]))
	c.finish_battle(true, surv, [])
	# (la bataille prend la journée : la rancune de la rivale peut déjà s'apaiser d'un point)
	check(c.reputation[f] == CampaignState.REP_WIN and c.reputation[rival] - CampaignState.REP_RIVAL in [0, 1] and c.reputation[other] == 0,
		"réputation après victoire : %s" % str(c.reputation))
	check(c.fame > 0, "renommée : pas de gain après une victoire")
	# La réputation module la prime
	var k := {"reward": 400, "faction": f}
	c.reputation[f] = 50
	check(c.contract_reward(k) == 500, "réputation : prime à +50 = %d au lieu de 500" % c.contract_reward(k))
	c.reputation[f] = -20
	check(c.contract_reward(k) == 360, "réputation : prime à -20 = %d au lieu de 360" % c.contract_reward(k))
	# Réputation très basse : contrats et recrutement fermés
	c.gold = 5000.0
	c.location = 0
	c.reputation[f] = CampaignState.REP_CLOSED
	c.refresh_contracts(0)
	check(c.faction_closed(f) and c.accept(c.contracts_at(0)[0]) != "" and not c.in_battle(), "réputation : contrat accepté par une faction hostile")
	check(c.recruit("spear") != "", "réputation : recrutement accepté par une faction hostile")
	c.company[0]["men"] = 3
	check(c.refill(0) != "", "réputation : complément accepté par une faction hostile")
	# Les rancunes s'apaisent avec le temps
	var r0 := c.reputation[f]
	c.pass_day()
	c.pass_day()
	check(c.reputation[f] > r0, "réputation : aucune remontée avec le temps")
	# La difficulté suit la renommée
	c.fame = 0
	var hard := 0
	for i in 20:
		check(int(c.make_contract(1)["difficulty"]) == 1, "renommée nulle : contrat difficile")
	c.fame = CampaignState.FAME_STEP * 2
	for i in 20:
		var d := int(c.make_contract(1)["difficulty"])
		check(d >= 2, "renommée haute : contrat facile")
		if d == 3:
			hard += 1
	check(hard > 0, "renommée haute : jamais de contrat difficile")
	print("Réputation : OK")


## Défaite : pillage et réputation ; retraite : pénalités réduites.
func _test_defeat() -> void:
	for retreat in [false, true]:
		var c := CampaignState.new_game(11)
		c.gold = 1000.0
		c.fame = 40
		var k: Dictionary = c.contracts_at(0)[0]
		var f := int(k["faction"])
		c.accept(k)
		var surv := []
		for r in c.battle_army():
			surv.append(int(r["men"]))
		var wage := c.daily_wage()
		c.finish_battle(false, surv, [], retreat)
		var pill: float = CampaignState.PILLAGE_RETREAT if retreat else CampaignState.PILLAGE
		var want: float = 1000.0 - floor(1000.0 * pill) - wage
		var what := "retraite" if retreat else "défaite"
		check(absf(c.gold - want) < 0.01, "%s : or %.1f au lieu de %.1f" % [what, c.gold, want])
		var loss: int = CampaignState.REP_RETREAT if retreat else CampaignState.REP_LOSS
		check(c.reputation[f] - loss in [0, 1], "%s : réputation %d au lieu de %d" % [what, c.reputation[f], loss])
		check(c.fame == 40 - (CampaignState.FAME_RETREAT if retreat else CampaignState.FAME_LOSS), "%s : renommée %d" % [what, c.fame])
		check(c.defeats == 1 and not c.in_battle() and not k in c.contracts, "%s : contrat non soldé" % what)
	print("Défaite et retraite : OK")


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
	# Rangs appliqués au déploiement
	for r in mine:
		check(r.rank == CampaignState.rank_of(army[r.company_index]), "%s : rang du régiment %d non appliqué" % [phase, r.company_index])
	for r in theirs:
		var e: Dictionary = enemy[theirs.find(r)]
		check(r.rank == int(e.get("rank", 0)), "%s : rang ennemi non appliqué" % phase)
	print("%s : %d hommes contre %d (%s)" % [phase, camp.total_men(), battle.initial_strength[1], camp.pending["title"]])
	battle.start_battle()
	battle.set_meta("player", TestPlayer.new("tactical"))
	battle.set_meta("men_before", camp.total_men())
	battle.set_meta("gold_before", camp.gold)
	battle.set_meta("reward", int(camp.pending["reward"]))
	var xp := []
	for r in army:
		xp.append(float(r.get("xp", 0.0)))
	battle.set_meta("xp_before", xp)
	if phase == "battle1":
		# Une flèche d'archer qui tue compte pour le régiment qui l'a tirée
		var archer = null
		for r in mine:
			if r.type == "archer":
				archer = r
		if archer != null:
			battle.rebuild_grid()
			var foe = theirs[0].soldiers[0]
			battle.arrow_impact({"to": foe.pos, "dmg": 99999.0, "src": archer})
			check(not foe.alive and archer.kills == 1, "battle1 : tué par une flèche non compté (%d)" % archer.kills)


func _run_battle() -> void:
	var player = battle.get_meta("player")
	for i in 40:
		player.update(battle)
		battle.simulate(STEP)
		if phase == "retreat" and battle.state == 1 and _try_retreat():
			break
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
	if phase != "retreat":
		check(camp.total_men() < before, "%s : aucune perte reportée" % phase)
	else:
		check(not victory and battle.retreated, "retraite : la bataille ne finit pas en retraite")
		check(battle.retreat_caught <= int(battle.get_meta("contact")), "retraite : %d rattrapés pour %d au contact" % [battle.retreat_caught, int(battle.get_meta("contact"))])
		var g0: float = battle.get_meta("gold_before")
		check(camp.gold <= g0 - floor(g0 * CampaignState.PILLAGE_RETREAT) + 0.01 and camp.gold > g0 * (1.0 - CampaignState.PILLAGE) - 0.01 - camp.daily_wage() * 2,
			"retraite : or %.1f (avant %.1f)" % [camp.gold, g0])
		check(camp.reputation[int(battle.get_meta("faction"))] < int(battle.get_meta("rep_before")), "retraite : réputation intacte")
	check(battle.campaign_report != "", "%s : pas de compte rendu" % phase)
	var saved := CampaignState.load_game()
	check(saved != null and saved.total_men() == camp.total_men() and saved.victories == camp.victories,
		"%s : résultat de la bataille non sauvegardé" % phase)
	if victory:
		check(camp.gold > float(battle.get_meta("gold_before")), "%s : prime non payée" % phase)
	# Expérience : chaque régiment survivant a gagné au moins la participation
	var kills_total := 0
	for r in battle.regiments:
		if r.team == 0:
			kills_total += r.kills
	check(kills_total > 0 or phase == "retreat", "%s : aucun ennemi tué compté" % phase)
	for r in camp.company:
		check(float(r["xp"]) >= CampaignState.XP_BATTLE, "%s : expérience non gagnée" % phase)
	root.remove_child(battle)
	battle.free()
	battle = null

	if phase == "battle1" and not camp.is_destroyed():
		phase = "battle2"
		_start_contract_battle()
		return
	if phase == "battle2" and not camp.is_destroyed():
		phase = "retreat"
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


## Phase « retreat » : dès que la mêlée est engagée, R deux fois. Renvoie true si la retraite est sonnée.
func _try_retreat() -> bool:
	var contact := 0
	var alive := 0
	for r in battle.regiments:
		if r.team != 0 or r.routing:
			continue
		for s in r.soldiers:
			if s.alive:
				alive += 1
				if s.foe != null and s.foe.alive and s.pos.distance_to(s.foe.pos) < 30.0:
					contact += 1
	if contact < 5 and battle.battle_time < 90.0:
		return false
	var f := int(camp.pending["faction"])
	battle.set_meta("contact", contact)
	battle.set_meta("faction", f)
	battle.set_meta("rep_before", camp.reputation[f])
	battle.set_meta("gold_before", camp.gold)
	battle.request_retreat()
	check(battle.state == 1, "retraite : sonnée sans confirmation")
	battle.request_retreat()
	print("retreat : retraite à %.0f s, %d hommes au contact sur %d, %d rattrapés" % [battle.battle_time, contact, alive, battle.retreat_caught])
	return true


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
