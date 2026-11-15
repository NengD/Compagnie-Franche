extends SceneTree
## Test headless de la difficulté (facile / normal / difficile) :
##   godot --headless --path . -s tests/difficulty_test.gd
## - définition centralisée cohérente (facile < normal < difficile) ;
## - escarmouche : multiplicateurs appliqués aux ennemis et à l'IA, difficulté lue dans les options ;
## - campagne : prix, solde et primes modulés, difficulté sauvegardée et rechargée,
##   anciennes sauvegardes (versions 1 et 2) relues en « normal », bataille de contrat à la bonne difficulté.
## N'utilise pas les vrais fichiers du joueur. Code de sortie : 0 si tout va bien, 1 sinon.

const OPTIONS_TEST := "user://test_difficulte_options.cfg"
const SAVE_TEST := "user://test_difficulte_campagne.json"

var fails: Array[String] = []
var scene: PackedScene


func check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)
		print("ÉCHEC : ", msg)


func _initialize() -> void:
	AudioServer.set_bus_mute(0, true) # Aucun son pendant les tests
	GameOptions.path = OPTIONS_TEST
	GameOptions.loaded = false
	CampaignState.save_path = SAVE_TEST
	CampaignState.current = null
	CampaignState.event_chance = 0.0
	for p in [OPTIONS_TEST, SAVE_TEST]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	scene = load("res://scenes/main.tscn")


## Les scènes ajoutées ne reçoivent _ready qu'une fois l'arbre lancé : tout se joue à la première image.
func _process(_delta: float) -> bool:
	_test_definition()
	_test_skirmish()
	_test_campaign_economy()
	_test_campaign_save()
	_test_campaign_battle()
	GameOptions.reset_all()
	CampaignState.current = null
	for p in [OPTIONS_TEST, SAVE_TEST]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	if fails.is_empty():
		print("TEST DIFFICULTÉ OK")
	else:
		print("TEST DIFFICULTÉ : %d échec(s)" % fails.size())
	quit(0 if fails.is_empty() else 1)
	return true


func _test_definition() -> void:
	check(Difficulty.sanitize("") == "normal" and Difficulty.sanitize("dragon") == "normal", "valeur inconnue → normal")
	for key in ["enemy_men", "enemy_morale", "enemy_damage", "ai_advance", "recruit", "wage", "reward", "ai_think", "ai_cavalry_wait"]:
		for id in Difficulty.IDS:
			check(Difficulty.level(id).has(key), "clé %s présente en %s" % [key, id])
	# Plus c'est difficile, plus l'ennemi est fort et l'or rare
	for key in ["enemy_men", "enemy_morale", "enemy_damage", "recruit", "wage"]:
		check(Difficulty.value("easy", key) <= Difficulty.value("normal", key) and Difficulty.value("normal", key) <= Difficulty.value("hard", key), "%s croissant avec la difficulté" % key)
	for key in ["reward", "ai_think", "ai_advance", "ai_cavalry_wait"]:
		check(Difficulty.value("easy", key) >= Difficulty.value("normal", key) and Difficulty.value("normal", key) >= Difficulty.value("hard", key), "%s décroissant avec la difficulté" % key)
	for key in ["enemy_men", "enemy_morale", "enemy_damage", "recruit", "wage", "reward"]:
		check(Difficulty.value("normal", key) == 1.0, "normal = référence (%s = 1)" % key)
	check(Difficulty.enemy_men("easy", 1) == 1, "au moins un homme par régiment")
	print("Définition : %s" % ("OK" if fails.is_empty() else "ÉCHEC"))


## Bataille d'escarmouche instanciée (non lancée) ; difficulty "" = celle des options.
func make_battle(level: String, seed_value := 7) -> Node:
	var b := scene.instantiate()
	b.set("seed_override", seed_value)
	b.set("terrain_override", "plain")
	b.set("difficulty", level)
	root.add_child(b)
	return b


func free_battle(b: Node) -> void:
	root.remove_child(b)
	b.free()


func enemy_stats(b: Node) -> Dictionary:
	var men := 0
	var morale := 0.0
	var dmg := 0.0
	var n := 0
	for r in b.regiments:
		if r.team == 1:
			men += r.soldiers.size()
			morale += r.max_morale
			dmg += r.rank_damage()
			n += 1
	return {"men": men, "morale": morale, "dmg": dmg / n, "n": n}


func _test_skirmish() -> void:
	var stats := {}
	for id in Difficulty.IDS:
		var b := make_battle(id)
		stats[id] = enemy_stats(b)
		check(b.difficulty == id, "difficulté imposée (%s)" % id)
		check(is_equal_approx(b.ai.think_every, Difficulty.value(id, "ai_think")) and is_equal_approx(b.ai.advance_time, Difficulty.value(id, "ai_advance"))
			and is_equal_approx(b.ai.cavalry_wait, Difficulty.value(id, "ai_cavalry_wait")), "IA réglée (%s)" % id)
		for r in b.regiments:
			if r.team == 0:
				check(r.morale_mult == 1.0 and r.damage_mult == 1.0, "le joueur n'est pas modifié (%s)" % id)
		free_battle(b)
	var n: Dictionary = stats["normal"]
	for id in ["easy", "hard"]:
		var s: Dictionary = stats[id]
		check(s["n"] == n["n"], "même nombre de régiments ennemis (%s)" % id)
		check(abs(s["men"] - n["men"] * Difficulty.value(id, "enemy_men")) <= n["n"], "effectifs ennemis x%.2f (%s : %d contre %d)" % [Difficulty.value(id, "enemy_men"), id, s["men"], n["men"]])
		check(is_equal_approx(s["morale"], n["morale"] * Difficulty.value(id, "enemy_morale")), "moral ennemi x%.2f (%s)" % [Difficulty.value(id, "enemy_morale"), id])
		check(is_equal_approx(s["dmg"], n["dmg"] * Difficulty.value(id, "enemy_damage")), "dégâts ennemis x%.2f (%s)" % [Difficulty.value(id, "enemy_damage"), id])
	check(stats["easy"]["men"] < n["men"], "moins d'ennemis en facile")
	# Sans difficulté imposée : celle des options
	GameOptions.ensure_loaded()
	GameOptions.difficulty = "easy"
	check(GameOptions.save_options(), "options écrites")
	GameOptions.difficulty = "normal"
	GameOptions.load_options()
	check(GameOptions.difficulty == "easy", "difficulté d'escarmouche relue dans options.cfg")
	var b := make_battle("")
	check(b.difficulty == "easy", "l'escarmouche prend la difficulté des options")
	free_battle(b)
	# Fichier d'options abîmé : retour au normal
	var cfg := ConfigFile.new()
	cfg.set_value("jeu", "difficulte", "cauchemar")
	cfg.save(OPTIONS_TEST)
	GameOptions.load_options()
	check(GameOptions.difficulty == "normal", "difficulté inconnue dans options.cfg → normal")
	print("Escarmouche : %s" % ("OK" if fails.is_empty() else "ÉCHEC"))


func _test_campaign_economy() -> void:
	var c := {}
	for id in Difficulty.IDS:
		c[id] = CampaignState.new_game(31, id)
		check(c[id].difficulty == id, "nouvelle campagne en %s" % id)
	var n: CampaignState = c["normal"]
	var k: Dictionary = n.contracts[0]
	for id in ["easy", "hard"]:
		var s: CampaignState = c[id]
		var mult_r := Difficulty.value(id, "recruit")
		check(abs(s.recruit_cost("cavalry", 10) - n.recruit_cost("cavalry", 10) * mult_r) <= 1.0, "prix des recrues x%.2f (%s)" % [mult_r, id])
		check(is_equal_approx(s.daily_wage(), n.daily_wage() * Difficulty.value(id, "wage")), "solde x%.2f (%s)" % [Difficulty.value(id, "wage"), id])
		var expect := n.contract_reward(k) * Difficulty.value(id, "reward")
		check(abs(s.contract_reward(k) - expect) <= 5.0, "prime x%.2f (%s : %d pour %.0f attendus)" % [Difficulty.value(id, "reward"), id, s.contract_reward(k), expect])
	check(c["easy"].recruit_cost("spear", 20) < n.recruit_cost("spear", 20) and n.recruit_cost("spear", 20) < c["hard"].recruit_cost("spear", 20), "recrues : facile < normal < difficile")
	check(c["easy"].contract_reward(k) > n.contract_reward(k) and n.contract_reward(k) > c["hard"].contract_reward(k), "primes : facile > normal > difficile")
	# Le recrutement débite bien le prix modulé
	var h: CampaignState = c["hard"]
	h.gold = 10000.0
	var before := h.gold
	h.company.resize(1)
	var town_recruits: Array = CampaignState.TOWNS[h.location]["recruits"]
	var t := str(town_recruits[0])
	var cost := h.recruit_cost(t, int(UnitTypes.STATS[t]["count"]))
	var err := h.recruit(t)
	check(err == "", "recrutement refusé : " + err)
	check(is_equal_approx(before - h.gold, cost), "recrutement en difficile : %d écus débités" % cost)
	print("Économie de campagne : %s" % ("OK" if fails.is_empty() else "ÉCHEC"))


func _test_campaign_save() -> void:
	var c := CampaignState.new_game(55, "hard")
	check(c.save(), "sauvegarde écrite")
	var l := CampaignState.load_game()
	check(l != null and l.difficulty == "hard", "difficulté sauvegardée puis rechargée")
	check(int(c.to_dict()["version"]) == CampaignState.SAVE_VERSION and CampaignState.SAVE_VERSION >= 3, "version de sauvegarde incrémentée")
	# Anciennes sauvegardes : pas de champ → normal
	for v in [1, 2]:
		var d := c.to_dict()
		d.erase("difficulty")
		d["version"] = v
		var old := CampaignState.from_dict(d)
		check(old != null and old.difficulty == "normal", "sauvegarde version %d relue en normal" % v)
	var bad := c.to_dict()
	bad["difficulty"] = "cauchemar"
	var r := CampaignState.from_dict(bad)
	check(r != null and r.difficulty == "normal", "difficulté inconnue → normal")
	CampaignState.delete_save()
	print("Sauvegarde : %s" % ("OK" if fails.is_empty() else "ÉCHEC"))


func _test_campaign_battle() -> void:
	# Une bataille de contrat prend la difficulté de la campagne, pas celle des options
	GameOptions.difficulty = "hard"
	var c := CampaignState.new_game(66, "easy")
	c.refresh_contracts(c.location)
	var k: Dictionary = c.contracts_at(c.location)[0]
	check(c.accept(k) == "", "contrat accepté")
	var planned := 0
	for e in c.pending["enemy"]:
		planned += mini(int(e["men"]), int(UnitTypes.STATS[e["type"]]["count"]))
	CampaignState.current = c
	var b := scene.instantiate()
	root.add_child(b)
	check(b.difficulty == "easy", "bataille de contrat en difficulté de campagne")
	var men := 0
	var n := 0
	for r in b.regiments:
		if r.team == 1:
			men += r.soldiers.size()
			n += 1
	# Le siège ajoute des renforts : on ne compare que si le terrain n'en est pas un
	if b.terrain.kind != "siege":
		check(abs(men - planned * Difficulty.value("easy", "enemy_men")) <= n, "effectifs du contrat réduits en facile (%d sur %d prévus)" % [men, planned])
	free_battle(b)
	CampaignState.current = null
	GameOptions.difficulty = "normal"
	print("Bataille de campagne : %s" % ("OK" if fails.is_empty() else "ÉCHEC"))
