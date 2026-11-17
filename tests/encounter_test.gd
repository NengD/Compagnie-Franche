extends SceneTree
## Test des rencontres de la carte (encounter.gd, encounter_panel.gd et le bloc de
## campaign_state.gd), avec des groupes construits à la main, sans carte ni fenêtre :
##   godot --headless --path . -s tests/encounter_test.gd
## Code de sortie : 0 si tout va bien, 1 sinon.

var fails: Array[String] = []
var next_id := 10


func check(ok: bool, what: String) -> void:
	if not ok:
		fails.append(what)


func new_state() -> CampaignState:
	CampaignState.event_chance = 0.0
	var s := CampaignState.new_game(42)
	s.gold = 500.0
	return s


func player_party() -> Party:
	var p := Party.new()
	p.id = 1
	p.kind = "player"
	return p


func party(kind: String, troops: Array, faction := -1, gold := 0, goods := 0) -> Party:
	var p := Party.new()
	next_id += 1
	p.id = next_id
	p.kind = kind
	p.faction = faction
	p.gold = gold
	p.goods = goods
	for t in troops:
		p.troops.append({"type": str(t[0]), "men": int(t[1]), "xp": float(t[2]) if t.size() > 2 else 0.0})
	return p


func ids(state: CampaignState, pl: Party, other: Party) -> Array:
	var out: Array[String] = []
	for o in Encounter.options(state, pl, other):
		out.append(str(o["id"]))
	return out


func option(state: CampaignState, pl: Party, other: Party, id: String) -> Dictionary:
	for o in Encounter.options(state, pl, other):
		if o["id"] == id:
			return o
	return {}


func enabled(state: CampaignState, pl: Party, other: Party, id: String) -> bool:
	return bool(option(state, pl, other, id).get("enabled", false))


func _initialize() -> void:
	AudioServer.set_bus_mute(0, true)
	test_estimates()
	test_bandits()
	test_attacked()
	test_villagers()
	test_caravan()
	test_patrol()
	test_deserters()
	test_party_battle()
	test_flee()
	test_save()
	test_greetings()


## Le panneau a besoin d'un arbre en marche : au premier tour de boucle.
func _process(_delta: float) -> bool:
	test_panel()
	if fails.is_empty():
		print("Rencontres : OK")
		quit(0)
	else:
		for f in fails:
			printerr("ÉCHEC : ", f)
		quit(1)
	return true


func test_estimates() -> void:
	var b := party("bandits", [["archer", 42], ["spear", 17]])
	check(Encounter.strength_line(b) == "Ils sont environ 60, surtout des archers.", "estimation : %s" % Encounter.strength_line(b))
	var s := new_state()
	check(Encounter.player_line(s, player_party()).begins_with("Vous êtes "), "ligne du joueur")
	check(Encounter.player_strength(s, player_party()) > 0.0, "force du joueur d'après la compagnie")


func test_bandits() -> void:
	var s := new_state()
	var pl := player_party()
	var big := party("bandits", [["spear", 60], ["archer", 40]], -1, 80)
	check(ids(s, pl, big) == ["attack", "pay", "intimidate", "flee"], "choix des bandits : %s" % str(ids(s, pl, big)))
	check(not enabled(s, pl, big, "intimidate"), "intimider une grosse bande")
	check(option(s, pl, big, "intimidate")["reason"] != "", "raison du refus")
	# Attaquer : contrat de bataille
	var rng_state := s.rng.state
	var r := Encounter.resolve(s, pl, big, "attack")
	check(s.rng.state == rng_state, "le rng de la campagne a servi")
	check(r["battle"] and not r["contract"].is_empty(), "attaque sans bataille")
	var c: Dictionary = r["contract"]
	check(int(c["party_id"]) == big.id, "party_id du contrat")
	check(str(c["terrain"]) in WorldSim.ROAD_TERRAINS, "terrain du contrat %s" % c.get("terrain"))
	var men := 0
	for e in c["enemy"]:
		men += int(e["men"])
		check(int(e["men"]) <= int(UnitTypes.STATS[e["type"]]["count"]), "régiment trop gros")
	check(men == 100, "effectif du contrat %d" % men)
	check(int(c["reward"]) == 0 and int(c["faction"]) == -1 and c["foe"] == "bandits", "contrat sans prime")
	for key in ["town", "title", "text", "difficulty", "expires", "seed", "objective", "enemy_faction"]:
		check(c.has(key), "contrat sans « %s »" % key)
	check(Encounter.resolve(s, pl, big, "attack")["contract"]["seed"] == c["seed"], "graine non déterministe")
	# Le contrat passe par la bataille de campagne (même forme qu'un contrat ordinaire)
	s.pending = c
	check(s.battle_army().size() > 0, "armée de bataille")
	# Payer
	var gold := s.gold
	r = Encounter.resolve(s, pl, big, "pay")
	check(not r["battle"] and r["close"] and s.gold == gold - Encounter.toll(big), "tribut payé")
	# Payer sans or
	s.gold = 5.0
	check(not enabled(s, pl, big, "pay"), "tribut sans or")
	r = Encounter.resolve(s, pl, big, "pay")
	check(not r["close"] and str(r["text"]).begins_with("Impossible"), "choix désactivé appliqué")
	# Intimider une petite bande : elle fuit ou se rend, toujours la même issue
	s.gold = 100.0
	var small := party("bandits", [["spear", 8]], -1, 30)
	check(enabled(s, pl, small, "intimidate"), "intimider une petite bande")
	var a := Encounter.resolve(s, pl, small, "intimidate")
	check(a["remove_other"] or a["other_flees"], "intimidation sans effet")
	if a["remove_other"]:
		check(s.gold == 130.0, "bourse des bandits soumis")


func test_attacked() -> void:
	var s := new_state()
	var pl := player_party()
	var b := party("bandits", [["spear", 40]])
	b.target_id = pl.id
	b.state = "chase"
	check(Encounter.attitude(s, pl, b) == Encounter.ATTACKING, "attitude attaquante")
	check(ids(s, pl, b) == ["attack", "pay", "flee"], "choix sous attaque : %s" % str(ids(s, pl, b)))
	var army := party("army", [["men_at_arms", 200]], 1)
	s.reputation[1] = -60
	army.target_id = pl.id
	army.state = "attack"
	check(ids(s, pl, army) == ["attack", "surrender", "flee"], "armée qui attaque : %s" % str(ids(s, pl, army)))
	var r := Encounter.resolve(s, pl, b, "pay")
	check(b.target_id == -1 and b.state == "idle", "les bandits payés lâchent la poursuite")
	check(not r["battle"], "payer sans bataille")


func test_villagers() -> void:
	var s := new_state()
	var pl := player_party()
	var v := party("villagers", [["spear", 20]], 0, 60, 200)
	check(ids(s, pl, v) == ["buy_food", "sell_loot", "recruit", "extort", "attack", "leave"], "choix des villageois : %s" % str(ids(s, pl, v)))
	# Vivres : la solde du lendemain baisse
	var wage := s.daily_wage()
	var r := Encounter.resolve(s, pl, v, "buy_food")
	check(not r["close"] and s.provisions > 0.0, "vivres achetés")
	check(not enabled(s, pl, v, "buy_food"), "vivres deux fois")
	var gold := s.gold
	s.pass_day()
	check(absf((gold - s.gold) - (wage - Encounter.food_cover(s))) < 1.0 or s.daily_wage() != wage, "solde allégée %f" % (gold - s.gold))
	check(s.provisions == 0.0, "vivres consommés")
	# Butin
	check(not enabled(s, pl, v, "sell_loot"), "vendre sans butin")
	s.loot = 50
	gold = s.gold
	r = Encounter.resolve(s, pl, v, "sell_loot")
	check(s.gold == gold + 30.0 and s.loot == 0, "butin vendu %f %d" % [s.gold - gold, s.loot])
	# Volontaires : piquiers (réputation neutre), archers (amis)
	check(Encounter.volunteer_type(s, v) == "spear", "volontaires piquiers")
	var men := s.total_men()
	var vmen := v.men()
	r = Encounter.resolve(s, pl, v, "recruit")
	check(s.total_men() > men and v.men() < vmen and s.total_men() - men == vmen - v.men(), "volontaires recrutés")
	s.reputation[0] = 40
	check(Encounter.volunteer_type(s, v) == "archer", "volontaires archers")
	# Rançonner : or et réputation
	s.reputation[0] = 0
	gold = s.gold
	var take := Encounter.extort_value(v)
	r = Encounter.resolve(s, pl, v, "extort")
	check(r["other_flees"] and s.gold == gold + take and s.reputation[0] == CampaignState.REP_EXTORT, "rançon %d, réputation %d" % [take, s.reputation[0]])
	# Réputation fermée : plus de commerce
	s.reputation[0] = -50
	check(Encounter.attitude(s, pl, v) == Encounter.HOSTILE and not enabled(s, pl, v, "buy_food") and not enabled(s, pl, v, "recruit"), "village hostile")
	# Attaquer et passer son chemin
	check(Encounter.resolve(s, pl, v, "attack")["battle"], "attaquer le village")
	r = Encounter.resolve(s, pl, v, "leave")
	check(r["close"] and not r["battle"] and not r["remove_other"], "passer son chemin")
	# Village fort : on ne le rançonne pas
	var strong := party("villagers", [["spear", 400]], 0)
	check(not enabled(s, pl, strong, "extort"), "rançonner un gros village")


func test_caravan() -> void:
	var s := new_state()
	var pl := player_party()
	var c := party("caravan", [["spear", 10]], 2, 150, 900)
	c.goal = 3
	check(ids(s, pl, c) == ["buy_food", "sell_loot", "escort", "plunder", "leave"], "choix de la caravane : %s" % str(ids(s, pl, c)))
	var r := Encounter.resolve(s, pl, c, "escort")
	check(r["escort"] and not s.escort_for(c.id).is_empty(), "escorte acceptée")
	check(not enabled(s, pl, c, "escort"), "escorter deux fois")
	var gold := s.gold
	var msg := s.finish_escort(c.id, true)
	check(s.gold == gold + Encounter.escort_reward(c) and s.reputation[2] == CampaignState.REP_ESCORT and msg != "", "escorte payée")
	check(s.finish_escort(c.id, true) == "", "escorte payée deux fois")
	# Caravane sans but : pas d'escorte
	var lost := party("caravan", [["spear", 10]], 2)
	check(not enabled(s, pl, lost, "escort"), "escorte sans but")
	# Piller une caravane presque sans gardes : reddition, butin, grosse perte de réputation
	s.reputation[2] = 0
	gold = s.gold
	r = Encounter.resolve(s, pl, c, "plunder")
	check(not r["battle"] and r["remove_other"] and s.gold == gold + 150.0 and s.loot == 900, "pillage sans combat")
	check(s.reputation[2] == CampaignState.REP_PLUNDER, "réputation après pillage %d" % s.reputation[2])
	# Caravane bien gardée : bataille
	var guarded := party("caravan", [["men_at_arms", 60], ["crossbow", 30]], 2, 100, 500)
	r = Encounter.resolve(s, pl, guarded, "plunder")
	check(r["battle"] and r["contract"]["foe"] == "gardes de la caravane", "pillage avec bataille")


func test_patrol() -> void:
	var s := new_state()
	var pl := player_party()
	var p := party("patrol", [["cavalry", 20], ["spear", 30]], 1)
	check(ids(s, pl, p) == ["talk", "join", "attack", "leave"], "choix de la patrouille : %s" % str(ids(s, pl, p)))
	check(not enabled(s, pl, p, "join") and not enabled(s, pl, p, "attack"), "patrouille neutre")
	var r := Encounter.resolve(s, pl, p, "talk")
	check(not r["close"] and str(r["text"]).begins_with("« La guerre"), "nouvelles : %s" % r["text"])
	s.reputation[1] = 30
	check(Encounter.attitude(s, pl, p) == Encounter.FRIENDLY and enabled(s, pl, p, "join"), "patrouille amie")
	r = Encounter.resolve(s, pl, p, "join")
	check(r["join"] and pl.target_id == p.id and pl.state == "follow", "se joindre")
	# En guerre (le joueur sert une faction ennemie) : on peut attaquer
	pl.target_id = -1
	s.reputation[1] = 0
	var war := ""
	for k in s.world.wars:
		war = str(k)
	if war != "":
		var ab := war.split("-")
		var a := int(ab[0])
		var b := int(ab[1])
		pl.faction = a
		var foe := party("patrol", [["spear", 20]], b)
		check(Encounter.at_war(s, pl, foe) and enabled(s, pl, foe, "attack"), "attaquer en guerre")
		pl.faction = -1
	# Armée hostile et plus forte : se rendre ou fuir
	var army := party("army", [["men_at_arms", 150], ["foot_knight", 100]], 1, 0)
	s.reputation[1] = -60
	check(ids(s, pl, army) == ["talk", "join", "attack", "surrender", "flee"], "armée hostile : %s" % str(ids(s, pl, army)))
	check(not enabled(s, pl, army, "talk") and enabled(s, pl, army, "attack"), "armée hostile : parler, attaquer")
	var gold := s.gold
	r = Encounter.resolve(s, pl, army, "surrender")
	check(r["player_flees"] and s.gold == gold - floorf(gold * Encounter.SURRENDER_GOLD) and army.gold > 0, "reddition")


func test_deserters() -> void:
	var s := new_state()
	var pl := player_party()
	var d := party("deserters", [["archer", 12]], 1)
	check(ids(s, pl, d) == ["recruit", "turn_in", "attack", "leave"], "choix des déserteurs : %s" % str(ids(s, pl, d)))
	var gold := s.gold
	var r := Encounter.resolve(s, pl, d, "turn_in")
	check(r["remove_other"] and s.gold == gold + 12 * Encounter.BOUNTY_PER_MAN and s.reputation[1] == CampaignState.REP_TURN_IN, "déserteurs livrés")
	var d2 := party("deserters", [["archer", 12]], 1)
	var men := s.total_men()
	gold = s.gold
	r = Encounter.resolve(s, pl, d2, "recruit")
	check(s.total_men() == men + 12 and r["remove_other"] and s.gold < gold, "déserteurs recrutés")
	check(s.gold == gold - Encounter.volunteer_cost("archer", 12, Encounter.DESERTER_PRICE), "prix des déserteurs")
	var d3 := party("deserters", [["men_at_arms", 300]], 1)
	check(not enabled(s, pl, d3, "turn_in"), "livrer une grosse troupe")
	check(Encounter.resolve(s, pl, d3, "attack")["battle"], "attaquer les déserteurs")


func test_party_battle() -> void:
	# Victoire sur des bandits : pertes, butin, réputation de la faction locale
	var s := new_state()
	var b := party("bandits", [["spear", 30], ["archer", 20]], -1, 120, 40)
	var local := s.town_owner(s.location)
	var rep := s.reputation[local]
	var gold := s.gold
	var note := s.apply_party_battle(b, {"victory": true, "enemy_survivors": 10})
	check(b.men() == 10, "survivants des bandits %d" % b.men())
	check(s.gold == gold + 120.0 and s.loot == 40 and b.gold == 0 and b.goods == 0, "butin des bandits")
	check(s.reputation[local] == rep + CampaignState.REP_BANDITS, "réputation locale")
	check(note.contains("Réputation"), "note : %s" % note)
	# Défaite contre des villageois d'une faction : elle est fâchée, les villageois gardent l'or pillé
	var v := party("villagers", [["spear", 40]], 2, 10)
	s.reputation[2] = 0
	s.apply_party_battle(v, {"victory": false, "totals": {"enemy_standing": 25, "enemy_fled": 5, "enemy_before": 40}, "pillage": 50})
	check(v.men() == 30 and v.gold == 60 and s.reputation[2] == CampaignState.REP_VILLAGERS, "défaite contre le village : %d hommes, %d écus" % [v.men(), v.gold])
	# Bilan de finish_battle seul (« killed »), armée de faction détruite
	var army := party("army", [["men_at_arms", 30]], 1)
	s.reputation[1] = 0
	s.apply_party_battle(army, {"victory": true, "killed": 30})
	check(army.is_dead() and s.reputation[1] == -WorldSim.REP_ARMY, "armée détruite")
	# Caravane pillée en bataille
	var c := party("caravan", [["spear", 10]], 0, 50, 300)
	s.reputation[0] = 0
	s.apply_party_battle(c, {"victory": true, "enemy_survivors": 0})
	check(s.reputation[0] == CampaignState.REP_PLUNDER and c.is_dead(), "caravane pillée en bataille")
	# Bataille complète : contrat -> finish_battle -> apply_party_battle
	var s2 := new_state()
	var pl := player_party()
	var foe := party("bandits", [["spear", 25]], -1, 70)
	var r := Encounter.resolve(s2, pl, foe, "attack")
	s2.pending = r["contract"]
	var surv: Array = []
	for reg in s2.battle_army():
		surv.append(int(reg["men"]))
	var out := s2.finish_battle(true, surv, [25])
	check(s2.pending.is_empty() and bool(out["victory"]), "bataille de campagne terminée")
	s2.apply_party_battle(foe, out)
	check(foe.is_dead(), "bandits anéantis (%d)" % foe.men())


func test_flee() -> void:
	var s := new_state()
	var pl := player_party()
	var slow := party("caravan", [["spear", 10]])
	var fast := party("bandits", [["cavalry", 200]])
	fast.speed_bonus = 2.0
	check(Encounter.flee_chance(s, pl, slow) > Encounter.flee_chance(s, pl, fast), "vitesse et fuite")
	check(not enabled(s, pl, fast, "flee"), "fuir des cavaliers rapides")
	var mid := party("bandits", [["spear", 60]])
	var a := Encounter.resolve(s, pl, mid, "flee")
	var b := Encounter.resolve(s, pl, mid, "flee")
	check(a["player_flees"] == b["player_flees"] and a["battle"] == b["battle"], "fuite non déterministe")
	check(a["player_flees"] != a["battle"], "fuite : ni fuite ni bataille")
	# Sur plusieurs jours, la fuite réussit parfois et échoue parfois
	var ok := 0
	for i in 40:
		s.day = i + 1
		if Encounter.resolve(s, pl, mid, "flee")["player_flees"]:
			ok += 1
	check(ok > 0 and ok < 40, "fuites réussies %d / 40" % ok)


func test_save() -> void:
	var s := new_state()
	s.loot = 70
	s.provisions = 12.5
	var c := party("caravan", [["spear", 10]], 2, 0, 100)
	c.goal = 2
	s.start_escort(c, 90)
	var foe := party("bandits", [["spear", 20]])
	s.pending = s.party_contract(foe, "forest")
	var t := CampaignState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	check(t != null, "relecture")
	if t != null:
		check(t.loot == 70 and is_equal_approx(t.provisions, 12.5) and t.escorts.size() == 1 and int(t.escorts[0]["reward"]) == 90, "rencontres relues")
		check(int(t.pending.get("party_id", -1)) == foe.id and t.pending.get("terrain") == "forest", "bataille de rencontre relue")
	var old := s.to_dict()
	old.erase("encounters")
	var u := CampaignState.from_dict(old)
	check(u != null and u.loot == 0 and u.escorts.is_empty(), "sauvegarde sans rencontres")


func test_greetings() -> void:
	var s := new_state()
	var pl := player_party()
	for kind in Party.KINDS:
		if kind == "player":
			continue
		for rep in [-60, 0, 40]:
			var p := party(kind, [["spear", 20]], -1 if kind == "bandits" else 1)
			s.reputation[1] = rep
			var g := Encounter.greeting(s, pl, p)
			check(g != "" and not g.contains("{f}"), "accueil %s %d : %s" % [kind, rep, g])
			p.target_id = pl.id
			p.state = "chase"
			check(Encounter.greeting(s, pl, p) != "", "accueil sous attaque %s" % kind)
			check(not Encounter.options(s, pl, p).is_empty(), "aucun choix pour %s" % kind)


func test_panel() -> void:
	AudioServer.set_bus_mute(0, true)
	var s := new_state()
	var pl := player_party()
	var v := party("villagers", [["spear", 20]], 0, 60, 200)
	var holder := Node.new()
	root.add_child(holder)
	var panel := Encounter.open(holder, s, pl, v) as EncounterPanel
	check(panel != null and panel.is_inside_tree(), "panneau ouvert")
	var got: Array = []
	panel.closed.connect(func(r: Dictionary) -> void: got.append(r))
	check(panel.buttons.size() == Encounter.options(s, pl, v).size(), "un bouton par choix")
	check(panel.can_leave(), "Échap permis")
	panel.choose("buy_food")
	check(got.is_empty() and not panel.ended and panel.notes.size() == 1, "commerce : le panneau reste ouvert")
	panel.choose("leave")
	check(got.is_empty() and panel.ended and panel.buttons.size() == 1, "issue affichée")
	panel.choose("continue")
	check(got.size() == 1 and got[0]["option"] == "leave", "fermeture")
	# Bandits sous attaque : pas d'Échap, la bataille ferme tout de suite
	var b := party("bandits", [["spear", 40]])
	b.target_id = pl.id
	b.state = "chase"
	var p2 := Encounter.open(holder, s, pl, b) as EncounterPanel
	check(not p2.can_leave(), "Échap sous attaque")
	var got2: Array = []
	p2.closed.connect(func(r: Dictionary) -> void: got2.append(r))
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.physical_keycode = KEY_1
	p2._unhandled_input(ev)
	check(got2.size() == 1 and got2[0]["battle"], "touche 1 : combattre")
	root.remove_child(holder)
	holder.free()
