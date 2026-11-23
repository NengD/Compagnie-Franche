extends SceneTree
## Test headless de l'escarmouche personnalisée et des défis de campagne :
##   godot --headless --path . -s tests/skirmish_test.gd
## - préparation (skirmish_setup.gd) : réglage par défaut, bornes, armées au format de bataille,
##   tirage « au hasard », résolution du terrain, du temps et de la difficulté ;
## - bataille lancée avec ce réglage : bonnes armées (types, nombre, rang, équipement), terrain,
##   pluie, saison, heure (lumière) et difficulté ;
## - réglage mémorisé dans les options (aller-retour), page du menu qui lance la bataille ;
## - défis : « Sans cavalerie » (recrutement, complément, volontaires, prisonniers refusés),
##   « Hiver éternel » (saison bloquée), « Homme de fer » (sauvegarde unique, sans copie de
##   secours ni mode indulgent, effacée à la ruine), « Bourse plate », « Contrats maigres » ;
##   défis sauvegardés et relus, anciennes sauvegardes sans défi, cases du menu.
## N'utilise pas les vrais fichiers du joueur. Code de sortie : 0 si tout va bien, 1 sinon.

const OPTIONS_TEST := "user://test_escarmouche_options.cfg"
const SAVE_TEST := "user://test_defis_campagne.json"
const SLOT_TEST := "user://test_defis_emplacement"

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
	CampaignState.slot_prefix = SLOT_TEST
	CampaignState.save_path = SAVE_TEST
	CampaignState.current = null
	CampaignState.event_chance = 0.0
	cleanup()
	scene = load("res://scenes/main.tscn")


func cleanup() -> void:
	CampaignState.delete_file(SAVE_TEST)
	for i in range(1, CampaignState.SLOT_COUNT + 1):
		CampaignState.delete_slot(i)
	if FileAccess.file_exists(OPTIONS_TEST):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(OPTIONS_TEST))


func _process(_delta: float) -> bool:
	_test_setup()
	_test_battle()
	_test_options_and_menu()
	_test_no_cavalry()
	_test_eternal_winter()
	_test_ironman()
	_test_small_challenges()
	_test_challenge_save()
	SkirmishSetup.pending = {}
	GameOptions.reset_all()
	CampaignState.current = null
	CampaignState.save_path = SAVE_TEST
	cleanup()
	if fails.is_empty():
		print("TEST ESCARMOUCHE ET DÉFIS OK")
	else:
		print("TEST ESCARMOUCHE ET DÉFIS : %d échec(s)" % fails.size())
	quit(0 if fails.is_empty() else 1)
	return true


## Réglage fixe des tests : deux régiments d'arbalétriers vétérans en armes de maître et un de
## chevaliers à pied contre trois de piquiers ; collines, pluie, hiver, nuit, difficile.
func fixed_config() -> Dictionary:
	return {
		"player": {"crossbow": {"n": 2, "rank": 2, "gear": 2}, "foot_knight": {"n": 1, "rank": 1, "gear": 0}},
		"enemy": {"spear": {"n": 3, "rank": 0, "gear": 1}},
		"terrain": "hills", "weather": "rain", "season": "winter", "hour": "night", "difficulty": Difficulty.HARD,
	}


# ---------------------------------------------------------------- Préparation

func _test_setup() -> void:
	var d := SkirmishSetup.default_config()
	check(SkirmishSetup.army_size(d["player"]) == 8 and SkirmishSetup.army_size(d["enemy"]) == 8, "réglage par défaut : 8 régiments de chaque côté (escarmouche classique)")
	check(SkirmishSetup.sanitize(d) == d, "le réglage par défaut est valide")
	# Valeurs hors bornes corrigées
	var bad := {"player": {"spear": {"n": 50, "rank": 9, "gear": -3}, "dragon": {"n": 2}}, "enemy": {},
		"terrain": "lune", "weather": "grêle", "season": "mousson", "hour": 99, "difficulty": "dieu"}
	var s := SkirmishSetup.sanitize(bad)
	check(int(s["player"]["spear"]["n"]) == SkirmishSetup.MAX_PER_TYPE and int(s["player"]["spear"]["rank"]) == 2 and int(s["player"]["spear"]["gear"]) == 0, "nombre, rang et équipement bornés")
	check(not s["player"].has("dragon"), "type inconnu écarté")
	check(SkirmishSetup.army_size(s["enemy"]) > 0, "armée vide remplacée par celle par défaut")
	check(s["terrain"] == SkirmishSetup.RANDOM and s["weather"] == "clear" and s["season"] == "summer" and s["hour"] == "day" and s["difficulty"] == Difficulty.NORMAL, "valeurs inconnues ramenées au défaut")
	var many := {}
	for t in UnitTypes.ORDER:
		many[t] = {"n": 6}
	check(SkirmishSetup.army_size(SkirmishSetup.sanitize_side(many)) == SkirmishSetup.MAX_REGIMENTS, "au plus %d régiments par armée" % SkirmishSetup.MAX_REGIMENTS)
	# Armée au format de bataille
	var list := SkirmishSetup.army_list(fixed_config()["player"])
	check(list.size() == 3, "3 régiments du joueur")
	var xb := 0
	for e in list:
		if e["type"] == "crossbow":
			xb += 1
			check(int(e["rank"]) == 2 and int(e["men"]) == int(UnitTypes.STATS["crossbow"]["count"]), "arbalétriers vétérans au complet")
			check(Equipment.tier(e, "weapon") == 2 and Equipment.tier(e, "armor") == 2 and Equipment.tier(e, "helmet") == 2, "équipement de qualité 2 sur les trois pièces")
		else:
			check(e["type"] == "foot_knight" and Equipment.of(e).is_empty() and int(e["rank"]) == 1, "chevaliers à pied aguerris sans équipement")
	check(xb == 2, "deux régiments d'arbalétriers")
	# Résolution : rien au hasard
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var r := SkirmishSetup.resolve(fixed_config(), rng)
	check(r["terrain"] == "hills" and r["raining"] == true and int(r["season"]) == 3 and is_equal_approx(float(r["hour"]), 23.0) and r["difficulty"] == Difficulty.HARD, "réglage résolu tel quel")
	check(SkirmishSetup.describe(r) == "Hiver, nuit, pluie", "temps décrit (%s)" % SkirmishSetup.describe(r))
	# Au hasard : toujours valide, et « random » résolu en valeurs concrètes
	var kinds := {}
	for k in 40:
		var c := SkirmishSetup.random_config(rng)
		check(SkirmishSetup.sanitize(c) == c, "réglage au hasard valide (%d)" % k)
		check(SkirmishSetup.army_size(c["player"]) >= 1 and SkirmishSetup.army_size(c["enemy"]) >= 1, "deux armées non vides (%d)" % k)
		kinds[c["terrain"]] = true
		var any := d.duplicate(true)
		for key in ["terrain", "weather", "season", "hour"]:
			any[key] = SkirmishSetup.RANDOM
		var rr := SkirmishSetup.resolve(any, rng)
		check(rr["terrain"] in Terrain.KINDS and int(rr["season"]) >= 0 and int(rr["season"]) < 4 and float(rr["hour"]) in SkirmishSetup.HOURS.values(), "« au hasard » résolu (%d)" % k)
	check(kinds.size() >= 3, "le hasard varie les terrains (%d)" % kinds.size())
	print("Préparation : %s" % ("OK" if fails.is_empty() else "ÉCHEC"))


# ---------------------------------------------------------------- Bataille

func _test_battle() -> void:
	var before := fails.size()
	CampaignState.current = null
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	SkirmishSetup.pending = SkirmishSetup.resolve(fixed_config(), rng)
	var b := scene.instantiate()
	b.set("seed_override", 9)
	root.add_child(b)
	check(b.terrain.kind == "hills", "terrain imposé : collines (%s)" % b.terrain.kind)
	check(b.raining, "il pleut")
	check(b.season == 3 and is_equal_approx(b.hour, 23.0), "hiver, nuit")
	check(b.difficulty == Difficulty.HARD, "difficulté de la préparation (%s)" % b.difficulty)
	check(b.daylight != null and b.daylight.color == MapSky.daylight(23.0), "lumière de nuit")
	check(b.renderer.ground_tint.a > 0.3, "neige sur le sol")
	var types := {}
	var enemies := 0
	for r in b.regiments:
		if r.team == 0:
			types[r.type] = int(types.get(r.type, 0)) + 1
			if r.type == "crossbow":
				check(r.rank == 2 and r.gear.size() == 3, "arbalétriers vétérans équipés en bataille")
				check(r.stats["ranged_damage"] > float(UnitTypes.STATS["crossbow"]["ranged_damage"]), "armes de maître : dégâts accrus")
		else:
			enemies += 1
			check(r.type == "spear", "ennemis : piquiers")
	check(types == {"crossbow": 2, "foot_knight": 1}, "armée du joueur conforme (%s)" % str(types))
	check(enemies == 3, "trois régiments ennemis (%d)" % enemies)
	root.remove_child(b)
	b.free()
	# Sans réglage : escarmouche classique, au temps clair de midi
	SkirmishSetup.pending = {}
	var c := scene.instantiate()
	c.set("seed_override", 9)
	c.set("terrain_override", "plain")
	root.add_child(c)
	check(c.regiments.size() == 16 and c.season == -1 and c.daylight == null and c.renderer.ground_tint.a == 0.0, "escarmouche par défaut inchangée")
	root.remove_child(c)
	c.free()
	print("Bataille préparée : %s" % ("OK" if fails.size() == before else "ÉCHEC"))


# ---------------------------------------------------------------- Options et menu

func _test_options_and_menu() -> void:
	var before := fails.size()
	GameOptions.ensure_loaded()
	GameOptions.skirmish = fixed_config()
	check(GameOptions.save_options(), "options écrites")
	GameOptions.skirmish = {}
	GameOptions.load_options()
	check(GameOptions.skirmish == SkirmishSetup.sanitize(fixed_config()), "réglage d'escarmouche relu dans les options")
	# Menu : la page de préparation reprend le réglage mémorisé et lance la bataille
	var menu: Control = load("res://scenes/menu.tscn").instantiate()
	menu.set("change_scenes", false)
	root.add_child(menu)
	menu.open_skirmish()
	check(menu.page == "skirmish" and menu.skirmish_cfg == SkirmishSetup.sanitize(fixed_config()), "page de préparation ouverte sur le dernier réglage")
	check(menu.box.find_child("Lancer", true, false) != null and menu.box.find_child("Hasard", true, false) != null, "boutons Lancer et Au hasard")
	check(menu.box.find_child("player_crossbow_n", true, false) is SpinBox and menu.box.find_child("Champ_terrain", true, false) is OptionButton, "réglages des armées et du champ")
	menu.set_skirmish_unit(4.0, "enemy", "cavalry", "n")
	menu.set_skirmish_field("terrain", "river")
	menu.set_skirmish_field("hour", "dawn")
	GameOptions.load_options()
	check(int(GameOptions.skirmish["enemy"]["cavalry"]["n"]) == 4 and GameOptions.skirmish["terrain"] == "river", "chaque changement est mémorisé")
	menu.set_skirmish_unit(6.0, "enemy", "foot_knight", "n") # 3 + 4 + 6 > 12
	check(SkirmishSetup.army_size(menu.skirmish_cfg["enemy"]) == SkirmishSetup.MAX_REGIMENTS, "le menu borne l'armée à %d régiments" % SkirmishSetup.MAX_REGIMENTS)
	menu.randomize_skirmish()
	check(SkirmishSetup.sanitize(menu.skirmish_cfg) == menu.skirmish_cfg and GameOptions.skirmish == menu.skirmish_cfg, "« Au hasard » : réglage valide et mémorisé")
	menu.set_skirmish_field("terrain", "village")
	menu.start_skirmish()
	check(menu.last_scene == menu.BATTLE_SCENE and SkirmishSetup.pending.get("terrain", "") == "village", "Lancer : bataille sur le terrain choisi")
	root.remove_child(menu)
	menu.free()
	SkirmishSetup.pending = {}
	print("Options et menu : %s" % ("OK" if fails.size() == before else "ÉCHEC"))


# ---------------------------------------------------------------- Défis

## Ville où l'on lève de la cavalerie.
func cavalry_town() -> int:
	for t in CampaignState.TOWNS.size():
		if "cavalry" in CampaignState.TOWNS[t]["recruits"]:
			return t
	return -1


func _test_no_cavalry() -> void:
	var before := fails.size()
	var t := cavalry_town()
	check(t >= 0, "une ville lève de la cavalerie")
	var free := CampaignState.new_game(3)
	free.location = t
	free.gold = 99999.0
	free.company.clear()
	check(free.recruit("cavalry") == "", "sans défi, la cavalerie se lève")
	var c := CampaignState.new_game(3, Difficulty.NORMAL, false, false, [Challenges.NO_CAVALRY])
	c.location = t
	c.gold = 99999.0
	var horse := -1
	for i in c.company.size():
		if c.company[i]["type"] == "cavalry":
			horse = i
	c.company[horse]["men"] = 3
	var n := c.company.size()
	check(c.recruit("cavalry") == Challenges.NO_CAVALRY_REFUSAL, "recrutement de cavalerie refusé")
	check(c.recruit("horse_archer") == Challenges.NO_CAVALRY_REFUSAL, "archers montés refusés aussi")
	check(c.refill(horse) == Challenges.NO_CAVALRY_REFUSAL and int(c.company[horse]["men"]) == 3, "complément de cavalerie refusé")
	check(c.company.size() == n, "aucun régiment monté levé")
	check(c.recruit("archer") == "", "les autres troupes se lèvent")
	check(Encounter.room_for(c, "cavalry") == 0 and Prisoners.room_for(c, "horse_archer") == 0 and Encounter.room_for(c, "spear") > 0, "ni volontaires ni prisonniers montés")
	check(Challenges.forbids_type(c.challenges, "cavalry") and not Challenges.forbids_type(c.challenges, "spear"), "règle lue dans challenges.gd")
	print("Sans cavalerie : %s" % ("OK" if fails.size() == before else "ÉCHEC"))


func _test_eternal_winter() -> void:
	var before := fails.size()
	var c := CampaignState.new_game(4, Difficulty.NORMAL, false, false, [Challenges.ETERNAL_WINTER])
	check(c.world.eternal_winter, "le monde connaît le défi")
	for day in [1, 15, 31, 45, 61, 75, 120]:
		check(c.world.season(day) == WorldSim.WINTER, "hiver au jour %d" % day)
		check(is_equal_approx(c.world.march_speed(day), float(WorldSim.MARCH_FACTOR[WorldSim.WINTER])), "marche d'hiver au jour %d" % day)
	check(c.world.calendar_text(40).begins_with("Hiver éternel"), "calendrier : %s" % c.world.calendar_text(40))
	check(MapSky.season(40, 12.0, true)["snow"] == 1.0, "neige sur la carte")
	var plain := CampaignState.new_game(4)
	check(plain.world.season(40) == 1 and not plain.world.eternal_winter, "sans défi, l'été vient au jour 40")
	# Les jours passent : toujours l'hiver, et le froid emporte des hommes en route
	c.day = 31
	c.world.advance(c)
	check(c.world.season(c.day) == WorldSim.WINTER, "toujours l'hiver après un jour")
	# Relu depuis la sauvegarde
	var back := CampaignState.from_dict(JSON.parse_string(JSON.stringify(c.to_dict())))
	check(back != null and back.world.eternal_winter and back.world.season(50) == WorldSim.WINTER, "hiver éternel relu")
	print("Hiver éternel : %s" % ("OK" if fails.size() == before else "ÉCHEC"))


func _test_ironman() -> void:
	var before := fails.size()
	CampaignState.save_path = SAVE_TEST
	CampaignState.delete_file(SAVE_TEST)
	var c := CampaignState.new_game(6, Difficulty.NORMAL, true, false, [Challenges.IRONMAN])
	check(not c.lenient, "Homme de fer : pas de mode indulgent")
	check(c.save() and c.save() and c.save(), "sauvegardes écrites")
	check(FileAccess.file_exists(SAVE_TEST) and not FileAccess.file_exists(SAVE_TEST + ".bak"), "une seule sauvegarde, sans copie de secours")
	var loaded := CampaignState.load_game()
	check(loaded != null and loaded.has_challenge(Challenges.IRONMAN) and not loaded.lenient, "relue avec le défi")
	# Une sauvegarde modifiée à la main pour remettre le mode indulgent : refusé
	var d := c.to_dict()
	d["lenient"] = true
	check(not CampaignState.from_dict(d).lenient, "mode indulgent refusé à la relecture")
	# Sans défi : la copie de secours existe
	var p := CampaignState.new_game(6)
	CampaignState.save_path = SAVE_TEST.replace(".json", "_b.json")
	p.save()
	p.save()
	check(FileAccess.file_exists(CampaignState.save_path + ".bak"), "sans défi, copie de secours gardée")
	CampaignState.delete_file(CampaignState.save_path)
	CampaignState.save_path = SAVE_TEST
	# Défaite finale : la compagnie est ruinée, la sauvegarde disparaît
	c.company.clear()
	c.gold = 0.0
	c.check_ruin()
	check(c.ended == "ruin", "compagnie ruinée")
	check(c.save(), "sauvegarde de la ruine")
	check(not CampaignState.has_save() and not FileAccess.file_exists(SavePreview.path_for(SAVE_TEST)), "sauvegarde effacée à la défaite finale")
	check(CampaignState.load_game() == null, "plus rien à recharger")
	print("Homme de fer : %s" % ("OK" if fails.size() == before else "ÉCHEC"))


func _test_small_challenges() -> void:
	var before := fails.size()
	var base := CampaignState.new_game(8, Difficulty.NORMAL, false, true)
	var poor := CampaignState.new_game(8, Difficulty.NORMAL, false, true, [Challenges.POOR_START])
	check(poor.gold <= base.gold * Challenges.START_GOLD_FACTOR and poor.gold >= base.gold * Challenges.START_GOLD_FACTOR - 10.0, "Bourse plate : moitié de l'or (%d contre %d)" % [int(poor.gold), int(base.gold)])
	var lean := CampaignState.new_game(8, Difficulty.NORMAL, false, false, [Challenges.LEAN_CONTRACTS])
	var k := {"reward": 1000, "faction": -1}
	check(lean.contract_reward(k) == int(round(base.contract_reward(k) * Challenges.REWARD_FACTOR / 10.0)) * 10, "Contrats maigres : prime réduite (%d contre %d)" % [lean.contract_reward(k), base.contract_reward(k)])
	print("Petits défis : %s" % ("OK" if fails.size() == before else "ÉCHEC"))


func _test_challenge_save() -> void:
	var before := fails.size()
	var all := Challenges.IDS.duplicate()
	var c := CampaignState.new_game(12, Difficulty.HARD, false, false, all)
	check(c.challenges == Challenges.IDS, "tous les défis cochés")
	var d := c.to_dict()
	check(int(d["version"]) == CampaignState.SAVE_VERSION and d["challenges"] == Array(Challenges.IDS), "défis écrits dans la sauvegarde")
	var back := CampaignState.from_dict(JSON.parse_string(JSON.stringify(d)))
	check(back != null and back.challenges == c.challenges, "défis relus (aller-retour)")
	check(back.summary().contains("Homme de fer"), "défis dans le résumé du menu")
	# Ancienne sauvegarde (version 13) : aucun défi
	d.erase("challenges")
	d["version"] = 13
	var old := CampaignState.from_dict(d)
	check(old != null and old.challenges.is_empty() and not old.world.eternal_winter, "ancienne sauvegarde : aucun défi")
	# Identifiants inconnus ou en double écartés
	d["challenges"] = ["dragon", Challenges.NO_CAVALRY, Challenges.NO_CAVALRY]
	check(CampaignState.from_dict(d).challenges == [Challenges.NO_CAVALRY], "défis inconnus écartés")
	# Cases de « Nouvelle campagne » : la campagne créée garde les défis cochés
	CampaignState.current = null
	var menu: Control = load("res://scenes/menu.tscn").instantiate()
	menu.set("change_scenes", false)
	root.add_child(menu)
	menu.new_campaign(1)
	check(menu.box.find_child("Defi_" + Challenges.IRONMAN, true, false) is CheckBox, "case « Homme de fer »")
	menu.lenient_choice = true
	menu.toggle_challenge(true, Challenges.IRONMAN)
	menu.toggle_challenge(true, Challenges.ETERNAL_WINTER)
	check(not menu.lenient_choice, "Homme de fer décoche le mode indulgent")
	menu.confirm_new_campaign(Difficulty.NORMAL)
	var cur := CampaignState.current
	check(cur != null and cur.challenges == [Challenges.IRONMAN, Challenges.ETERNAL_WINTER] and not cur.lenient and cur.world.eternal_winter, "nouvelle campagne avec ses défis")
	var preview := SavePreview.read_slot(1)
	check(not preview.is_empty() and " ".join(SavePreview.lines(preview)).contains("Hiver éternel"), "défis dans l'aperçu de l'emplacement")
	root.remove_child(menu)
	menu.free()
	# Fenêtre de fin : les défis figurent au bilan
	var end: Control = load("res://scenes/end.tscn").instantiate()
	end.set("change_scenes", false)
	cur.ended = "victory"
	root.add_child(end)
	var found := false
	for row in end.summary_rows():
		if row[0] == "Défis" and str(row[1]).contains("Homme de fer"):
			found = true
	check(found, "défis au bilan de fin")
	root.remove_child(end)
	end.free()
	CampaignState.current = null
	print("Sauvegarde des défis : %s" % ("OK" if fails.size() == before else "ÉCHEC"))
