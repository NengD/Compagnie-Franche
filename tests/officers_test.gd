extends SceneTree
## Test headless des officiers, de l'arbre de compétences du capitaine et de la chronique :
##   godot --headless --path . -s tests/officers_test.gd
## - officiers : nommer (bonus selon le métier et le niveau), changer de régiment, relever,
##   renvoi du compagnon ; en bataille (simulation) : bonus appliqué, chute forcée d'un régiment
##   anéanti, moral perdu, bonus retiré ; après la bataille : officier tué (quitte la compagnie,
##   journal, chronique) ou blessé ; scène de bataille de campagne : officier à la tête du régiment ;
## - arbre du capitaine : prérequis, niveau, coût, maximum ; effets réels (solde, vivres, prix,
##   butin, moral, vitesse, formations, mêlée, déploiement, chute qui ébranle moins) ;
## - chronique : non vide, cohérente avec les batailles, officiers tombés, fiefs et l'issue ;
##   onglet Journal et écran de fin ;
## - sauvegarde : aller-retour (officiers, arbre, chronique), version 13 relue.
## Code de sortie : 0 si tout va bien, 1 sinon.

const PREFIX := "user://test_officiers"


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
var battle: Battle = null


func check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)
		push_warning("ÉCHEC : " + msg)


func _initialize() -> void:
	AudioServer.set_bus_mute(0, true)
	OS.add_logger(counter)
	CampaignState.slot_prefix = PREFIX
	CampaignState.use_slot(1)
	CampaignState.event_chance = 0.0
	_test_assign()
	_test_officer_battle()
	_test_after_battle()
	_test_tree()
	_test_tree_battle()
	_test_chronicle()
	_test_save()


func _process(_delta: float) -> bool:
	frame += 1
	match frame:
		1:
			var c := _with_companions(CampaignState.new_game(7))
			Officers.assign(c, "scout", 2)
			c.pending = c.contracts[0]
			CampaignState.current = c
			battle = (load("res://scenes/main.tscn") as PackedScene).instantiate()
			battle.seed_override = 4
			battle.terrain_override = "plain"
			root.add_child(battle)
		3:
			_test_battle_scene()
			root.remove_child(battle)
			battle.free()
			battle = null
			CampaignState.current = null
			_test_map()
			_test_end_screen()
		4:
			for e in counter.errors:
				fails.append("erreur : " + e)
			for i in CampaignState.SLOT_COUNT:
				CampaignState.delete_slot(i + 1)
			if fails.is_empty():
				print("Officiers, capitaine, chronique : OK")
				quit(0)
			else:
				for f in fails:
					print("ÉCHEC : " + f)
				quit(1)
	return false


func _with_companions(c: CampaignState) -> CampaignState:
	for kind in Companions.ORDER:
		c.companions.list.append(Companions.make(kind, str(Companions.KINDS[kind]["names"][0])))
	return c


func _sim_for(c: CampaignState) -> BattleSim:
	var sim := BattleSim.new()
	sim.rng.seed = 3
	sim.generate_world("plain")
	sim.spawn_army(BattleSim.PLAYER, c.battle_army())
	sim.spawn_army(BattleSim.ENEMY, [{"type": "spear", "men": 20, "rank": 0}])
	return sim


# ---------------------------------------------------------------- Nominations

func _test_assign() -> void:
	var c := _with_companions(CampaignState.new_game(11))
	check(Officers.assign(c, "sergeant", 0) == "", "nomination du sergent refusée")
	check(Officers.of(c.company[0]) == "sergeant" and Officers.regiment_of(c, "sergeant") == 0, "sergent mal nommé")
	check("prend la tête" in c.log_lines[0], "nomination absente du journal")
	check(Officers.assign(c, "sergeant", 0) != "", "même nomination acceptée deux fois")
	check(Officers.assign(c, "sergeant", 1) == "" and Officers.of(c.company[0]) == "" and Officers.of(c.company[1]) == "sergeant", "changement de régiment")
	check(Officers.assign(c, "surgeon", 1) == "" and Officers.of(c.company[1]) == "surgeon" and Officers.regiment_of(c, "sergeant") == -1, "remplacement de l'officier d'un régiment")
	check(Officers.assign(c, "scout", 99) != "", "régiment inconnu accepté")
	check(Officers.remove(c, 1) == "" and Officers.of(c.company[1]) == "", "officier non relevé")
	check(Officers.remove(c, 1) != "", "relever un régiment sans officier")
	# Bonus selon le niveau
	var m := c.companions.get_kind("scout")
	check(is_equal_approx(Officers.bonus_value(m), Officers.BASE_BONUS), "bonus de niveau 1")
	m["level"] = 4
	check(is_equal_approx(Officers.bonus_value(m), Officers.BASE_BONUS + 3 * Officers.LEVEL_BONUS), "bonus de niveau 4")
	check("vitesse" in Officers.bonus_text(m), "bonus de l'éclaireur : %s" % Officers.bonus_text(m))
	# Renvoi : il n'est plus officier
	Officers.assign(c, "quartermaster", 3)
	c.overworld.inside = 0
	Companions.dismiss(c, "quartermaster")
	check(Officers.of(c.company[3]) == "", "compagnon renvoyé encore officier")
	# Pas de changement en bataille
	c.pending = c.contracts[0]
	check(Officers.assign(c, "scout", 0) != "", "nomination en pleine bataille")


func _test_officer_battle() -> void:
	var c := _with_companions(CampaignState.new_game(12))
	Officers.assign(c, "sergeant", 2) # Hommes d'armes
	Officers.assign(c, "quartermaster", 3) # Archers
	Officers.assign(c, "scout", 5) # Cavaliers
	Officers.assign(c, "surgeon", 0) # Piquiers
	var sim := _sim_for(c)
	var regs := {}
	for r in sim.player_regiments():
		regs[r.company_index] = r
	var base := {}
	var mm := {}
	for i in regs:
		mm[i] = (regs[i] as Regiment).max_morale
		base[i] = (regs[i] as Regiment).stats.duplicate()
		var kind := Officers.of(c.company[i])
		if kind != "":
			var mm0 := (regs[i] as Regiment).max_morale
			Officers.apply_bonus(regs[i], c.companions.get_kind(kind))
			if kind == "surgeon":
				check(is_equal_approx((regs[i] as Regiment).max_morale, mm0 * (1.0 + Officers.BASE_BONUS)), "chirurgien : moral maximal")
	var k := 1.0 + Officers.BASE_BONUS
	check(is_equal_approx(float(regs[2].stats["damage"]), float(base[2]["damage"]) * k), "sergent : mêlée")
	check(is_equal_approx(float(regs[3].stats["ranged_damage"]), float(base[3]["ranged_damage"]) * k), "quartier-maître : tir")
	check(is_equal_approx(float(regs[5].stats["speed"]), float(base[5]["speed"]) * k), "éclaireur : vitesse")
	check(is_equal_approx(float(regs[1].stats["damage"]), float(base[1]["damage"])), "régiment sans officier modifié")
	# Le régiment du sergent est anéanti : l'officier tombe forcément, bonus retiré
	sim.start()
	var r: Regiment = regs[2]
	var other: Regiment = regs[3]
	other.soldiers[0].alive = false
	other.alive_n -= 1
	for s in r.soldiers:
		s.alive = false
	r.alive_n = 0
	Officers.step(sim)
	check(r.officer_fate in ["dead", "wounded"], "officier d'un régiment anéanti debout")
	check(str(c.companions.get_kind("sergeant").get("fell", "")) == r.officer_fate, "chute non transmise à la campagne")
	check(is_equal_approx(float(r.stats["damage"]), float(base[2]["damage"])), "bonus de l'officier tombé non retiré")
	check(other.officer_fate == "" or other.officer_fate in ["dead", "wounded"], "chute impossible")
	# Chute d'un officier du chirurgien : moral perdu
	var q: Regiment = regs[0]
	q.morale = 80.0
	Officers.fall(sim, q)
	check(is_equal_approx(q.morale, minf(80.0, q.max_morale) - Officers.FALL_MORALE), "chute : moral %.1f" % q.morale)
	check(is_equal_approx(q.max_morale, float(mm[0])), "bonus de moral non retiré")
	# Risque : pas de chute sans pertes
	var s0 := Officers.FALL_RATE
	check(s0 > 0.0 and s0 < 1.0, "risque de chute")


func _test_after_battle() -> void:
	var c := _with_companions(CampaignState.new_game(13))
	Officers.assign(c, "sergeant", 2)
	Officers.assign(c, "scout", 1)
	c.companions.get_kind("sergeant")["fell"] = "dead"
	c.companions.get_kind("scout")["fell"] = "wounded"
	c.pending = c.contracts[0]
	var out := c.finish_battle(true, [99, 99, 99, 99, 99, 99])
	check(c.companions.get_kind("sergeant").is_empty(), "officier tué encore dans la compagnie")
	check(Officers.regiment_of(c, "sergeant") == -1, "officier tué encore nommé")
	var scout := c.companions.get_kind("scout")
	check(not Companions.available(scout, c.day) and Officers.regiment_of(c, "scout") == 1, "officier blessé : absent mais toujours nommé")
	check("mort à la tête" in str(out["text"]) and "blessé" in str(out["text"]), "compte rendu : %s" % out["text"])
	check(not c.chronicle.of_kind("officer_dead").is_empty() and not c.chronicle.of_kind("officer_wounded").is_empty(), "officiers tombés absents de la chronique")
	check(not scout.has("fell"), "marque de chute restée")
	# Régiment anéanti hors de la scène : l'officier tombe aussi
	var c2 := CampaignState.new_game(14) # Sans chirurgien : personne n'est relevé après une défaite
	c2.companions.list.append(Companions.make("sergeant", "Sergent d'essai"))
	Officers.assign(c2, "sergeant", 0)
	c2.pending = c2.contracts[0]
	c2.finish_battle(false, [0, 99, 99, 99, 99, 99])
	check(Officers.regiment_of(c2, "sergeant") == -1, "régiment anéanti encore mené")
	var sg := c2.companions.get_kind("sergeant")
	check(sg.is_empty() or not Companions.available(sg, c2.day), "officier d'un régiment anéanti indemne")


# ---------------------------------------------------------------- Arbre du capitaine

func _test_tree() -> void:
	var c := CampaignState.new_game(21)
	var cap := c.captain
	check(Captain.PATH_ORDER.size() == 3 and Captain.SKILLS.size() == 12, "trois voies de quatre compétences")
	for k in Captain.SKILLS:
		check(cap.skills.has(k) and Captain.PATHS.has(str(Captain.SKILLS[k]["path"])), "compétence %s mal définie" % k)
		for q in Captain.SKILLS[k]["req"]:
			check(Captain.SKILLS.has(q), "prérequis inconnu %s" % q)
	cap.points = 5
	check(cap.learn("thrift") != "", "économe sans solde réduite")
	check(cap.learn("wages") == "" and cap.points == 4, "solde réduite")
	check(cap.learn("thrift") != "", "économe avant le niveau 2")
	cap.level = 2
	var food0 := Supplies.consumption(c)
	check(cap.learn("thrift") == "" and cap.points == 3, "économe refusé")
	check(is_equal_approx(Supplies.consumption(c), food0 * (1.0 - Captain.THRIFT_STEP)), "économe : vivres %.2f" % Supplies.consumption(c))
	check(cap.learn("haggle") != "", "marchandeur avant le niveau 4")
	cap.level = 4
	var price0 := c.recruit_cost("spear", 20)
	var ration0 := Supplies.ration_price(c)
	check(cap.learn("haggle") == "" and cap.points == 1, "marchandeur : coût de deux points")
	check(c.recruit_cost("spear", 20) < price0 and is_equal_approx(Supplies.ration_price(c), ration0 * Captain.HAGGLE_PRICE), "marchandeur : prix")
	check(cap.learn("plunder") != "", "pillard sans niveau ni points")
	cap.level = 6
	check("points" in cap.refusal("plunder"), "manque de points : %s" % cap.refusal("plunder"))
	cap.points = 2
	check(cap.learn("plunder") == "" and cap.points == 0, "pillard avisé")
	check(cap.learn("haggle") != "", "au-delà du maximum")
	check(cap.spent("steward") == 1 + 1 + 2 + 2 and cap.spent("leader") == 0, "points dépensés par voie")
	# Butin +20 %
	var c2 := CampaignState.new_game(22)
	c2.pending = c2.contracts[0]
	var out0 := c2.finish_battle(true, [99, 99, 99, 99, 99, 99], [5, 5, 5, 5, 5, 5])
	var c3 := CampaignState.new_game(22)
	c3.captain.skills["plunder"] = 1
	c3.pending = c3.contracts[0]
	var out1 := c3.finish_battle(true, [99, 99, 99, 99, 99, 99], [5, 5, 5, 5, 5, 5])
	check(int(out1["loot"]) == roundi(int(out0["loot"]) * Captain.PLUNDER_LOOT), "pillard avisé : butin %d au lieu de %d" % [int(out1["loot"]), int(out0["loot"])])
	# Meneur : prérequis multiples
	var cap2 := Captain.new()
	cap2.level = 4
	cap2.points = 9
	check(cap2.learn("banner") != "", "bannière sans aura ni ralliement")
	cap2.learn("aura")
	check(cap2.learn("banner") != "", "bannière sans ralliement")
	cap2.learn("rally")
	check(cap2.learn("banner") == "", "bannière refusée")
	check(is_equal_approx(cap2.morale_factor(), 1.0 + Captain.BANNER_MORALE), "bannière : moral")


func _test_tree_battle() -> void:
	var c := CampaignState.new_game(23)
	var sim0 := _sim_for(c)
	var cap0 := Captain.new()
	cap0.take_field(sim0)
	var sim := _sim_for(c)
	var cap := Captain.new()
	for k in ["banner", "drill", "formations", "scouting", "eye", "iron"]:
		cap.skills[k] = 1
	cap.take_field(sim)
	var a := sim0.player_regiments()[0]
	var b := sim.player_regiments()[0]
	check(is_equal_approx(float(b.stats["speed"]), float(a.stats["speed"]) * (1.0 + Captain.DRILL_SPEED)), "manœuvres : vitesse")
	check(is_equal_approx(float(b.stats["damage"]), float(a.stats["damage"]) * (1.0 + Captain.EYE_DAMAGE)), "coup d'œil : mêlée")
	check(is_equal_approx(b.max_morale, a.max_morale * (1.0 + Captain.BANNER_MORALE)), "bannière : moral maximal en bataille")
	check(is_equal_approx(b.drill_mult, Captain.FORMATION_SPEED) and is_equal_approx(a.drill_mult, 1.0), "formations serrées")
	check(is_equal_approx(sim.deploy_top(), sim0.deploy_top() - Captain.SCOUTING_DEPTH), "reconnaissance : déploiement")
	# Formations serrées : un carré marche plus vite
	sim.start()
	sim0.start()
	for s2 in [sim0, sim]:
		var r: Regiment = (s2 as BattleSim).player_regiments()[0]
		r.formation = Regiment.Formation.COLUMN
	var ra := sim0.player_regiments()[0]
	var rb := sim.player_regiments()[0]
	var pa := ra.center
	var pb := rb.center
	ra.dest = pa + Vector2(0, -600)
	rb.dest = pb + Vector2(0, -600)
	for i in 20:
		sim0.step(0.05)
		sim.step(0.05)
	check(rb.center.distance_to(pb) > ra.center.distance_to(pa) * 1.2, "colonne : %.1f contre %.1f" % [rb.center.distance_to(pb), ra.center.distance_to(pa)])
	# Volonté de fer : la chute du capitaine ébranle moitié moins
	var m0 := rb.morale
	cap.die(sim)
	check(is_equal_approx(rb.morale, m0 - Captain.DEATH_MORALE * Captain.IRON_FACTOR), "volonté de fer : moral %.1f" % rb.morale)


# ---------------------------------------------------------------- Chronique

func _test_chronicle() -> void:
	var c := _with_companions(CampaignState.new_game(31))
	var start := Chronicle.narrate(c)
	check(start.size() >= 3 and c.captain.name in start[0], "chronique de départ : %s" % str(start))
	check("aucune bataille" in " ".join(start), "chronique sans bataille")
	Officers.assign(c, "sergeant", 2)
	c.pending = c.contracts[0]
	c.finish_battle(true, [99, 99, 99, 99, 99, 99], [3, 3, 12, 3, 3, 3])
	c.pending = c.contracts[0]
	var foe := str(c.pending["foe"])
	c.companions.get_kind("sergeant")["fell"] = "dead"
	c.finish_battle(false, [5, 5, 5, 5, 5, 5])
	c.fiefs.grant(c, 0, 1)
	var text := "\n".join(Chronicle.narrate(c))
	check(c.chronicle.of_kind("battle").size() == 2, "batailles notées : %d" % c.chronicle.of_kind("battle").size())
	check("2 batailles" in text and "1 victoire" in text and "1 défaite" in text, "bilan des batailles : %s" % text)
	check("plus belle victoire" in text and "plus sombre" in text and foe in text, "batailles marquantes : %s" % text)
	check(str(Companions.KINDS["sergeant"]["names"][0]) in text and "pleura" in text, "officier tombé absent : %s" % text)
	check("château" in text and "prit" in text, "fief absent : %s" % text)
	check("pas finie" in text, "issue d'une campagne en cours")
	c.ended = "victory"
	c.end_day = c.day
	c.end_note = "La guerre est finie."
	var fin := Chronicle.narrate(c)
	check("légende" in fin[-1] and "La guerre est finie." in fin[-1], "issue de victoire : %s" % fin[-1])
	c.ended = "ruin"
	check("déchirée" in Chronicle.narrate(c)[-1], "issue de ruine")
	c.ended = ""
	# Bornes
	for i in Chronicle.MAX_EVENTS + 5:
		Chronicle.note(c, "battle", {"victory": true, "killed": 1, "lost": 0, "foe": "bandits"})
	check(c.chronicle.events.size() == Chronicle.MAX_EVENTS, "chronique non bornée")


# ---------------------------------------------------------------- Sauvegarde

func _test_save() -> void:
	var c := _with_companions(CampaignState.new_game(41))
	Officers.assign(c, "scout", 4)
	c.captain.skills["drill"] = 2
	c.captain.skills["wages"] = 1
	Chronicle.note(c, "fief", {"place": "le château de Test", "bought": true})
	var d := JSON.parse_string(JSON.stringify(c.to_dict())) as Dictionary
	check(int(d["version"]) == 14 or int(d["version"]) == CampaignState.SAVE_VERSION, "version de sauvegarde")
	var b := CampaignState.from_dict(d)
	check(b != null, "sauvegarde illisible")
	if b == null:
		return
	check(Officers.of(b.company[4]) == "scout" and Officers.regiment_of(b, "scout") == 4, "officier mal relu")
	check(int(b.captain.skills["drill"]) == 2 and int(b.captain.skills["wages"]) == 1 and int(b.captain.skills["eye"]) == 0, "arbre mal relu")
	check(b.chronicle.of_kind("fief").size() == 1 and str(b.chronicle.of_kind("fief")[0]["place"]) == "le château de Test", "chronique mal relue")
	check(" ".join(Chronicle.narrate(b)) == " ".join(Chronicle.narrate(c)), "récit différent après relecture")
	# Valeurs abîmées : bornées, officier sans compagnon relevé
	d["captain"]["skills"]["drill"] = 99
	d["company"][0]["officer"] = "scout" # Doublon
	d["company"][1]["officer"] = "inconnu"
	d["companions"] = (d["companions"] as Array).filter(func(m): return str(m["kind"]) != "surgeon")
	d["company"][2]["officer"] = "surgeon"
	var e := CampaignState.from_dict(d)
	check(e != null and int(e.captain.skills["drill"]) == int(Captain.SKILLS["drill"]["max"]), "rang abîmé mal borné")
	if e != null:
		var n := 0
		for entry in e.company:
			if Officers.of(entry) == "scout":
				n += 1
		check(n == 1 and Officers.of(e.company[1]) == "" and Officers.of(e.company[2]) == "", "officiers abîmés mal relevés")
	# Version 13 : ni officiers, ni chronique, trois compétences
	var old := JSON.parse_string(JSON.stringify(c.to_dict())) as Dictionary
	old["version"] = 13
	old.erase("chronicle")
	old["captain"]["skills"] = {"aura": 2, "rally": 1, "wages": 3}
	for entry in old["company"]:
		(entry as Dictionary).erase("officer")
	var o := CampaignState.from_dict(old)
	check(o != null and int(o.captain.skills["aura"]) == 2 and int(o.captain.skills["wages"]) == 3 and int(o.captain.skills["banner"]) == 0, "version 13 : capitaine")
	check(o != null and o.chronicle.events.is_empty() and not Chronicle.narrate(o).is_empty(), "version 13 : chronique")
	# Fichier
	CampaignState.current = c
	check(c.save(), "écriture de la sauvegarde")
	var f := CampaignState.load_game()
	check(f != null and Officers.of(f.company[4]) == "scout" and not f.chronicle.events.is_empty(), "sauvegarde sur disque")
	CampaignState.current = null


# ---------------------------------------------------------------- Scènes

func _test_battle_scene() -> void:
	var c := battle.campaign
	check(c != null, "bataille sans campagne")
	if c == null:
		return
	var led: Regiment = null
	for r in battle.sim.regiments:
		if r.company_index == 2:
			led = r
	check(led != null and not led.officer.is_empty() and str(led.officer["kind"]) == "scout", "officier absent de son régiment en bataille")
	if led != null:
		var base := float(UnitTypes.STATS[led.type]["speed"])
		check(float(led.stats["speed"]) > base * (1.0 + Officers.BASE_BONUS) - 0.01, "bonus de vitesse absent en bataille")
	var msgs := ""
	for m in battle.messages:
		msgs += str(m[0]) + " "
	check("Officiers" in msgs, "message des officiers absent : %s" % msgs)


func _test_map() -> void:
	var c := _with_companions(CampaignState.new_game(51))
	c.captain.points = 2
	CampaignState.current = c
	var m: Node = (load("res://scenes/campaign.tscn") as PackedScene).instantiate()
	m.auto_launch = false
	root.add_child(m)
	m.toggle_view("company")
	var named: Button = null
	var tree: Button = null
	for b in m.find_children("*", "Button", true, false):
		var t := (b as Button).text
		if t == "→ 2" and named == null:
			named = b
		if t.begins_with("Compétences du capitaine"):
			tree = b
	check(named != null and tree != null, "onglet Compagnie : boutons des officiers ou de l'arbre absents")
	if named != null:
		named.pressed.emit()
		check(Officers.of(c.company[1]) == "sergeant", "bouton de nomination sans effet")
	if tree != null:
		tree.pressed.emit()
		var learn: Button = null
		var labels := ""
		for b in m.find_children("*", "Button", true, false):
			if b.has_meta("skill") and str(b.get_meta("skill")) == "drill" and not b.is_queued_for_deletion():
				learn = b
		for l in m.find_children("*", "Label", true, false):
			if not l.is_queued_for_deletion():
				labels += (l as Label).text + " | "
		check("Meneur" in labels and "Tacticien" in labels and "Intendant" in labels and "requiert" in labels and "Coût" in labels, "fenêtre de l'arbre incomplète : %s" % labels)
		check(learn != null and not learn.disabled, "bouton Manœuvres absent")
		if learn != null:
			learn.pressed.emit()
			check(int(c.captain.skills["drill"]) == 1 and c.captain.points == 1, "bouton de l'arbre sans effet")
	m.toggle_view("journal")
	var all := ""
	for l in m.find_children("*", "Label", true, false):
		if not l.is_queued_for_deletion():
			all += (l as Label).text + " "
	check("Chronique" in all and c.captain.name in all, "chronique absente du journal")
	root.remove_child(m)
	m.free()
	CampaignState.current = null


func _test_end_screen() -> void:
	var c := CampaignState.new_game(61)
	c.pending = c.contracts[0]
	c.finish_battle(true, [99, 99, 99, 99, 99, 99], [4, 4, 4, 4, 4, 4])
	c.ended = "victory"
	c.end_day = c.day
	c.end_note = "Victoire décisive."
	CampaignState.current = c
	var s: Control = (load("res://scenes/end.tscn") as PackedScene).instantiate()
	s.change_scenes = false
	root.add_child(s)
	var ch := s.find_child("Chronicle", true, false)
	check(ch != null, "chronique absente de l'écran de fin")
	var all := ""
	for l in s.find_children("*", "Label", true, false):
		all += (l as Label).text + " "
	check("légende" in all and "plus belle victoire" in all, "récit de fin : %s" % all.substr(0, 300))
	root.remove_child(s)
	s.free()
	CampaignState.current = null
