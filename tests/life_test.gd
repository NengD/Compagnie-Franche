extends SceneTree
## Test headless des prisonniers, des vivres et de la fatigue, et des compagnons :
##   godot --headless --path . -s tests/life_test.gd
## - prisonniers : capture après une victoire (pas après une défaite), limite des gardes,
##   rançon en ville (pas en campagne), enrôlement (régiment complété ou nouveau, moral bas),
##   libération (réputation), évasions, demi-ration ;
## - vivres : consommation, achat en ville, capacité, faim (moral) puis désertions ;
## - fatigue : marche, marche forcée (allure x2, épuisement), camp et ville (repos), endurance
##   de départ ; blessés graves dans les chariots qui guérissent au repos ;
## - compagnons : offres des villes, engagement, solde, compétences, effets (chirurgien,
##   sergent, éclaireur qui repère les bandits cachés et renseigne, quartier-maître), blessure ;
## - sauvegarde : aller-retour, version 9 relue (dix jours de vivres) ;
## - bataille (scène) : fatigue, faim, rancœur et sergent appliqués aux régiments ;
## - carte : sections de la ville et de l'onglet Compagnie, boutons de la barre.
## Code de sortie : 0 si tout va bien, 1 sinon.

const PREFIX := "user://test_vie"


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
	_test_prisoners()
	_test_supplies()
	_test_fatigue()
	_test_wounded()
	_test_companions()
	_test_scout()
	_test_save()


func _process(_delta: float) -> bool:
	frame += 1
	match frame:
		1:
			var c := CampaignState.new_game(5)
			c.supplies.fatigue = Supplies.FATIGUE_MAX
			c.supplies.hungry_days = 1
			c.company[0]["sullen"] = 1.0
			c.pending = c.contracts[0]
			CampaignState.current = c
			battle = (load("res://scenes/main.tscn") as PackedScene).instantiate()
			battle.seed_override = 21
			battle.terrain_override = "plain"
			root.add_child(battle)
		3:
			_test_battle_scene()
			root.remove_child(battle)
			battle.free()
			battle = null
			CampaignState.current = null
			_test_map()
		4:
			for e in counter.errors:
				fails.append("erreur : " + e)
			for i in CampaignState.SLOT_COUNT:
				CampaignState.delete_slot(i + 1)
			if fails.is_empty():
				print("Vie de la compagnie : OK")
				quit(0)
			else:
				for f in fails:
					print("ÉCHEC : " + f)
				quit(1)
	return false


func new_state(seed_value := 3) -> CampaignState:
	var c := CampaignState.new_game(seed_value)
	c.overworld.enter(c, 0) # Dans les murs de Valombre
	return c


## Bataille contre le premier contrat : survivants (part des hommes), tués (par régiment).
func fight(c: CampaignState, victory: bool, keep := 0.7, kills := 5) -> Dictionary:
	c.pending = c.contracts[0]
	var surv := []
	var k := []
	for r in c.battle_army():
		surv.append(int(int(r["men"]) * keep))
		k.append(kills)
	return c.finish_battle(victory, surv, k)


# ---------------------------------------------------------------- Prisonniers

func _test_prisoners() -> void:
	var c := new_state()
	var out := fight(c, false)
	check(c.prisoners.total() == 0 and int(out["prisoners"]) == 0, "prisonniers après une défaite")
	out = fight(c, true)
	var n := c.prisoners.total()
	check(n > 0 and int(out["prisoners"]) == n and "prisonnier" in str(out["text"]), "aucun prisonnier après une victoire (%d)" % n)
	check(n <= int(c.total_men() * Prisoners.GUARD_RATIO), "trop de prisonniers pour les gardes")
	check("prisonniers" in LifePanel.report_line(out) or "prisonnier" in LifePanel.report_line(out), "bilan sans prisonniers : %s" % LifePanel.report_line(out))
	# Limite des gardes : une compagnie réduite à presque rien n'en prend pas
	var tiny := new_state()
	for r in tiny.company:
		r["men"] = 1
	tiny.prisoners.add("spear", 50, 0, 1)
	var o := fight(tiny, true, 1.0, 10)
	check(int(o["prisoners"]) == 0 and tiny.prisoners.total() <= 50, "prisonniers sans gardes")
	# Demi-ration
	var before := Supplies.consumption(c)
	c.prisoners.add("archer", 10, 0, 1)
	check(is_equal_approx(Supplies.consumption(c) - before, 10 * Supplies.PRISONER_RATION), "les prisonniers ne mangent pas")
	# Rançon : en ville seulement, selon le type et le rang, plus cher dans une ville de leur faction
	var p := new_state()
	p.prisoners.add("spear", 10, 0, 1)
	p.prisoners.add("spear", 10, 2, 1)
	p.prisoners.add("cavalry", 4, 0, -1)
	check(Prisoners.ransom_value(p, p.prisoners.list[1], 0) > Prisoners.ransom_value(p, p.prisoners.list[0], 0), "rançon : le rang ne compte pas")
	check(Prisoners.ransom_value(p, p.prisoners.list[0], 2) > Prisoners.ransom_value(p, p.prisoners.list[0], 0), "rançon : pas de prime dans une ville de leur faction")
	p.overworld.inside = -1
	check(Prisoners.ransom(p, 0) != "", "rançon hors de la ville")
	p.overworld.enter(p, 0)
	var gold := p.gold
	var value := Prisoners.ransom_value(p, p.prisoners.list[0], 0)
	check(Prisoners.ransom(p, 0) == "" and is_equal_approx(p.gold - gold, value) and p.prisoners.list.size() == 2, "rançon refusée ou mal payée")
	# Relâcher : réputation auprès de leur faction
	var rep := p.reputation[1]
	check(Prisoners.release(p, 0) == "" and p.reputation[1] == rep + Prisoners.release_reputation({"men": 10}), "libération sans réputation")
	# Enrôler : la moitié accepte et complète un régiment entamé, avec de la rancœur
	var e := new_state()
	e.company[0]["men"] = 6 # Piquiers entamés
	e.prisoners.add("spear", 10, 1, 1)
	var regs := e.company.size()
	check(Prisoners.enlist(e, 0) == "", "enrôlement refusé")
	check(int(e.company[0]["men"]) == 11 and e.company.size() == regs and e.prisoners.total() == 5, "enrôlement : %d hommes, %d prisonniers" % [int(e.company[0]["men"]), e.prisoners.total()])
	check(float(e.company[0].get("sullen", 0.0)) > 0.4 and Prisoners.morale_factor(e.company[0]) < 0.85, "enrôlés sans rancœur")
	# Un type absent de la compagnie forme un nouveau régiment
	e.prisoners.add("crossbow", 12, 0, 1)
	check(Prisoners.enlist(e, e.prisoners.list.size() - 1) == "" and e.company[-1]["type"] == "crossbow" and int(e.company[-1]["men"]) == 6 and float(e.company[-1]["sullen"]) == 1.0, "nouveau régiment d'anciens prisonniers")
	# La rancœur s'efface avec les jours
	e.supplies.food = 1.0e6
	e.gold = 1.0e6
	for i in 30:
		e.pass_day()
	check(not e.company[0].has("sullen"), "rancœur éternelle")
	# Évasions : chaque jour, quelques-uns ; plus quand on a faim
	var esc := new_state()
	esc.supplies.food = 1.0e6
	esc.gold = 1.0e6
	esc.prisoners.add("spear", 40, 0, 1)
	for i in 10:
		esc.pass_day()
	var left := esc.prisoners.total()
	check(left < 40 and left > 15, "évasions : %d prisonniers restent" % left)
	print("Prisonniers : OK")


# ---------------------------------------------------------------- Vivres

func _test_supplies() -> void:
	var c := new_state()
	var days := Supplies.days_left(c)
	check(days >= 9.5 and days <= 10.5, "vivres de départ : %.1f jours" % days)
	var need := Supplies.consumption(c)
	check(is_equal_approx(need, c.total_men()), "consommation %f pour %d hommes" % [need, c.total_men()])
	var food := c.supplies.food
	c.pass_day()
	check(is_equal_approx(food - c.supplies.food, need), "vivres non consommés")
	# Achat en ville : prix de la ville, capacité des chariots
	var gold := c.gold
	var cost := Supplies.buy_cost(c, 5)
	check(Supplies.buy(c, 5) == "" and is_equal_approx(gold - c.gold, cost) and cost > 0, "achat de vivres")
	check(Supplies.buy(c, 0) == "" and Supplies.is_full(c) and Supplies.buy(c, 5) != "", "chariots pleins")
	check(Supplies.days_left(c) <= Supplies.FOOD_MAX_DAYS + 0.01, "chariots trop pleins")
	c.gold = 0.0
	c.supplies.food = 0.0
	check(Supplies.buy(c, 5) != "", "vivres sans or")
	# Faim : le premier jour, le moral ; à partir du troisième, des désertions
	var h := new_state()
	h.gold = 1.0e6 # La solde est payée : seules la faim et ses désertions comptent
	h.supplies.food = 0.0
	var men := h.total_men()
	h.pass_day()
	check(Supplies.hungry(h) and h.total_men() == men, "faim : désertions trop tôt")
	h.pass_day()
	h.pass_day()
	check(h.total_men() < men and "faim" in " ".join(h.log_lines), "famine sans désertions")
	h.supplies.food = 500.0
	h.pass_day()
	check(not Supplies.hungry(h), "toujours affamés avec des vivres")
	print("Vivres : OK")


func _test_fatigue() -> void:
	var c := new_state()
	var ow := c.overworld
	ow.go_to_place(c, 1) # Vers Saint-Aubin
	var normal := Supplies.pace(c)
	check(Supplies.toggle_forced(c) != "" and c.supplies.forced and is_equal_approx(Supplies.pace(c), normal * Supplies.FORCED_PACE), "marche forcée : allure")
	var start := ow.player.pos
	ow.tick(c, 4.0)
	var forced_dist := ow.player.pos.distance_to(start)
	check(c.supplies.fatigue > 8.0, "marche forcée sans fatigue (%.1f)" % c.supplies.fatigue)
	# L'épuisement met fin à la marche forcée
	c.supplies.fatigue = Supplies.FATIGUE_MAX - 0.5
	ow.tick(c, 1.0)
	check(not c.supplies.forced and c.supplies.fatigue >= Supplies.FATIGUE_MAX - 0.01, "épuisée, la compagnie force encore l'allure")
	check(Supplies.toggle_forced(c) != "" and not c.supplies.forced, "marche forcée permise à l'épuisement")
	# Le pas normal fatigue peu, et va moins loin
	c.supplies.fatigue = 0.0
	var p2 := ow.player.pos
	ow.tick(c, 4.0)
	check(c.supplies.fatigue < 3.0 and c.supplies.fatigue > 0.0 and ow.player.pos.distance_to(p2) < forced_dist * 0.8, "pas normal : fatigue %.1f" % c.supplies.fatigue)
	# Camper : la compagnie s'arrête et se repose ; repartir lève le camp
	c.supplies.fatigue = 50.0
	check(Supplies.toggle_camp(c, ow) != "" and c.supplies.camping and ow.player.path.is_empty(), "camp")
	ow.tick(c, 5.0)
	check(c.supplies.fatigue <= 50.0 - Supplies.REST_CAMP * 5.0 + 0.5 and c.supplies.rest_hours > 0.0, "camp sans repos (%.1f)" % c.supplies.fatigue)
	ow.go_to_place(c, 1)
	ow.tick(c, 1.0)
	check(not c.supplies.camping, "le camp n'est pas levé en repartant")
	# En ville : repos plus rapide
	c.overworld.enter(c, 0)
	c.supplies.fatigue = 50.0
	ow.tick(c, 5.0)
	check(c.supplies.fatigue <= 50.0 - Supplies.REST_TOWN * 5.0 + 0.5, "pas de repos en ville")
	check(Supplies.toggle_camp(c, ow) != "" and not c.supplies.camping, "camper dans les murs")
	# Endurance de départ
	c.supplies.fatigue = 0.0
	check(is_equal_approx(Supplies.start_stamina(c), 1.0), "endurance d'une compagnie fraîche")
	c.supplies.fatigue = Supplies.FATIGUE_MAX
	check(is_equal_approx(Supplies.start_stamina(c), 1.0 - Supplies.STAMINA_LOSS), "endurance d'une compagnie épuisée")
	print("Fatigue : OK")


func _test_wounded() -> void:
	var c := new_state()
	c.supplies.food = 1.0e6
	var out := fight(c, true, 0.5)
	var w := c.supplies.wounded_total()
	check(w > 0 and int(out["wounded"]) == w and "chariots" in str(out["text"]), "aucun blessé grave après la bataille")
	check(Supplies.consumption(c) >= c.total_men() + w, "les blessés ne mangent pas")
	# Sans repos, ils ne guérissent pas ; un jour en ville en ramène
	c.pass_day()
	check(c.supplies.wounded_total() == w, "guérison sans repos")
	var men := c.total_men()
	c.supplies.rest_hours = 24.0
	c.pass_day()
	check(c.supplies.wounded_total() < w and c.total_men() == men + (w - c.supplies.wounded_total()), "les blessés ne guérissent pas au repos")
	print("Blessés : OK")


# ---------------------------------------------------------------- Compagnons

func _test_companions() -> void:
	var c := new_state()
	c.gold = 5000.0
	check(Companions.offers(c, 0) == ["quartermaster", "scout"] and Companions.offers(c, 4) == ["sergeant"], "offres des villes")
	check(Companions.hire(c, "surgeon") != "", "chirurgien engagé à Valombre")
	var wage := c.daily_wage()
	var food_price := Supplies.ration_price(c)
	check(Companions.hire(c, "quartermaster") == "" and not c.companions.get_kind("quartermaster").is_empty(), "quartier-maître non engagé")
	check(Companions.hire(c, "quartermaster") != "" and not "quartermaster" in Companions.offers(c, 0), "deux quartiers-maîtres")
	check(Supplies.ration_price(c) < food_price, "quartier-maître : vivres au même prix")
	check(c.daily_wage() < wage + Companions.wage_of(c, c.companions.get_kind("quartermaster")), "quartier-maître : solde au même prix")
	check(Companions.ransom_factor(c) > 1.0, "quartier-maître : rançons au même prix")
	# Compétences : points gagnés aux batailles
	var qm := c.companions.get_kind("quartermaster")
	check(Companions.learn(c, "quartermaster", "rations") != "", "compétence sans point")
	for i in 4:
		fight(c, true, 0.9)
	check(int(qm["level"]) >= 2 and int(qm["points"]) >= 1, "pas de niveau : %d" % int(qm["level"]))
	var price := Supplies.ration_price(c)
	check(Companions.learn(c, "quartermaster", "rations") == "" and Supplies.ration_price(c) < price, "compétence Rations sans effet")
	# Sergent : moral maximal, désertions ; chirurgien : plus de tombés relevés
	c.overworld.enter(c, 1) # Saint-Aubin
	c.gold = 5000.0
	check(Companions.morale_factor(c) == 1.0 and Companions.recover_rate(c, true) == CampaignState.WOUNDED_RECOVER, "effets sans compagnon")
	check(Companions.hire(c, "sergeant") == "" and Companions.hire(c, "surgeon") == "", "sergent ou chirurgien non engagés")
	check(Companions.morale_factor(c) > 1.0 and Companions.desert_factor(c) < 1.0 and Companions.enlist_share(c) > Prisoners.ENLIST_SHARE, "sergent sans effet")
	check(Companions.recover_rate(c, true) > CampaignState.WOUNDED_RECOVER and Companions.recover_rate(c, false) > 0.0 and Companions.wagon_bonus(c) > 0.0, "chirurgien sans effet")
	var d := new_state(9)
	var o1 := fight(d, false, 0.2)
	c.supplies.food = 1.0e6
	var o2 := fight(c, false, 0.2)
	check(int(o2["healed"]) > 0 and int(o1["healed"]) == 0, "chirurgien : aucun blessé relevé dans une défaite")
	# Blessé : plus d'effet jusqu'à sa guérison, mais toujours payé
	var s := c.companions.get_kind("sergeant")
	s["wounded_until"] = c.day + 3
	check(Companions.morale_factor(c) == 1.0 and Companions.daily_wage(c) >= Companions.wage_of(c, s), "sergent blessé")
	check(Companions.dismiss(c, "sergeant") == "" and c.companions.get_kind("sergeant").is_empty(), "renvoi")
	print("Compagnons : OK")


func _test_scout() -> void:
	var c := new_state()
	var ow := c.overworld
	ow.spawning = false
	ow.parties.clear()
	ow.enter(c, 0)
	var b := Party.new()
	b.kind = "bandits"
	b.troops = [{"type": "spear", "men": 23, "xp": 120.0}, {"type": "archer", "men": 12, "xp": 0.0}]
	b.pos = ow.player.pos + Vector2(Overworld.SIGHT * 0.8, 0)
	b.hidden = true
	ow.add(c, b)
	Companions.spot(c, ow)
	check(b.hidden and Companions.sight(c) == 0.0 and Companions.scout_report(c, b.troops) == "", "repérés sans éclaireur")
	c.gold = 5000.0
	check(Companions.hire(c, "scout") == "", "éclaireur non engagé")
	Companions.spot(c, ow)
	check(not b.hidden, "l'éclaireur ne repère pas les bandits cachés")
	var far := Party.new()
	far.kind = "bandits"
	far.troops = [{"type": "spear", "men": 10, "xp": 0.0}]
	far.pos = ow.player.pos + Vector2(Overworld.SIGHT * 2.0, 0)
	far.hidden = true
	ow.add(c, far)
	Companions.spot(c, ow)
	check(far.hidden, "repérés trop loin")
	var rep := Companions.scout_report(c, b.troops)
	check("environ" in rep and "piquiers" in rep, "rapport de l'éclaireur : %s" % rep)
	c.companions.get_kind("scout")["skills"]["spies"] = 1
	rep = Companions.scout_report(c, b.troops)
	check("23 piquiers" in rep and "12 archers" in rep and "aguerris" in rep, "rapport des espions : %s" % rep)
	var pace := Supplies.pace(c)
	c.companions.get_kind("scout")["skills"]["tracks"] = 2
	check(Supplies.pace(c) > pace, "Pistes sans effet")
	print("Éclaireur : OK")


# ---------------------------------------------------------------- Sauvegarde

func _test_save() -> void:
	var c := new_state()
	c.gold = 5000.0
	Companions.hire(c, "scout")
	c.companions.get_kind("scout")["skills"]["eyes"] = 2
	c.companions.get_kind("scout")["wounded_until"] = 7
	c.prisoners.add("archer", 9, 1, 2)
	c.supplies.food = 321.5
	c.supplies.fatigue = 42.0
	c.supplies.forced = true
	c.supplies.hungry_days = 2
	c.supplies.wounded = {"spear": 4}
	c.company[0]["sullen"] = 0.6
	check(c.save(), "écriture de la sauvegarde")
	var b := CampaignState.load_slot(1)
	check(b != null, "sauvegarde illisible")
	if b == null:
		return
	var sc := b.companions.get_kind("scout")
	check(not sc.is_empty() and int(sc["skills"]["eyes"]) == 2 and int(sc["wounded_until"]) == 7, "compagnon perdu à la sauvegarde")
	check(b.prisoners.total() == 9 and int(b.prisoners.list[0]["rank"]) == 1 and int(b.prisoners.list[0]["faction"]) == 2, "prisonniers perdus à la sauvegarde")
	check(is_equal_approx(b.supplies.food, 321.5) and is_equal_approx(b.supplies.fatigue, 42.0) and b.supplies.forced and b.supplies.hungry_days == 2 and int(b.supplies.wounded.get("spear", 0)) == 4, "vivres perdus à la sauvegarde")
	check(is_equal_approx(float(b.company[0].get("sullen", 0.0)), 0.6), "rancœur perdue à la sauvegarde")
	# Version 9 : ni vivres, ni prisonniers, ni compagnons ; dix jours de vivres
	var d := c.to_dict()
	d["version"] = 9
	for key in ["supplies", "prisoners", "companions"]:
		d.erase(key)
	var old := CampaignState.from_dict(JSON.parse_string(JSON.stringify(d)))
	check(old != null and old.prisoners.total() == 0 and old.companions.list.is_empty() and absf(Supplies.days_left(old) - Supplies.FOOD_START_DAYS) < 0.01, "version 9 mal relue")
	# Données abîmées : ignorées sans erreur
	d = c.to_dict()
	d["prisoners"] = [{"type": "dragon", "men": 3}, "x"]
	d["companions"] = [{"kind": "mage"}, {"kind": "scout"}, {"kind": "scout"}]
	d["supplies"] = {"food": -5, "fatigue": 900, "wounded": {"dragon": 3}}
	var bad := CampaignState.from_dict(JSON.parse_string(JSON.stringify(d)))
	check(bad != null and bad.prisoners.total() == 0 and bad.companions.list.size() == 1 and bad.supplies.food == 0.0 and bad.supplies.fatigue == Supplies.FATIGUE_MAX and bad.supplies.wounded.is_empty(), "données abîmées mal relues")
	print("Sauvegarde : OK")


# ---------------------------------------------------------------- Scènes

func _test_battle_scene() -> void:
	var c := battle.campaign
	check(c != null, "bataille sans campagne")
	if c == null:
		return
	var mine := battle.sim.player_regiments()
	check(not mine.is_empty(), "aucun régiment")
	var tired := true
	var sullen_ok := false
	for r in mine:
		if r.stamina > Supplies.start_stamina(c) + 0.01:
			tired = false
		if r.company_index == 0:
			sullen_ok = r.morale <= r.max_morale * Supplies.HUNGER_MORALE * 0.5 + 0.5
	check(tired, "fatigue sans effet sur l'endurance")
	check(sullen_ok, "rancœur et faim sans effet sur le moral")
	check(battle.messages.any(func(m: Array) -> bool: return "endurance" in str(m[0])), "pas de message de fatigue : %s" % str(battle.messages))


func _test_map() -> void:
	var c := CampaignState.new_game(17)
	c.gold = 5000.0
	c.prisoners.add("spear", 8, 0, 1)
	CampaignState.current = c
	var m: Node = (load("res://scenes/campaign.tscn") as PackedScene).instantiate()
	m.auto_launch = false
	root.add_child(m)
	var all := labels(m)
	check("Vivres et repos" in all and "Prisonniers (8)" in all and "Compagnons" in all, "ville : sections absentes")
	check("vivres" in m.top_label.text and "fatigue" in m.top_label.text, "barre sans vivres ni fatigue : %s" % m.top_label.text)
	var food := find_button(m, "+5 jours")
	var hire := find_button(m, "Engager")
	var ransom := find_button(m, "Rançon")
	check(food != null and hire != null and ransom != null, "ville : boutons absents")
	if food != null and hire != null and ransom != null:
		var f0 := c.supplies.food
		food.pressed.emit()
		check(c.supplies.food > f0, "bouton des vivres sans effet")
		find_button(m, "Engager").pressed.emit()
		check(c.companions.list.size() == 1, "bouton d'engagement sans effet")
		find_button(m, "Rançon").pressed.emit()
		check(c.prisoners.total() == 0, "bouton de rançon sans effet")
	# Hors de la ville : onglet Compagnie, boutons de la barre
	m.close_town()
	m.toggle_view("company")
	all = labels(m)
	check("Vivres et repos" in all and "Compagnons" in all, "onglet Compagnie : sections absentes")
	var forced := find_button(m, "Marche forcée")
	var camp := find_button(m, "Camper")
	check(forced != null and camp != null, "barre sans marche forcée ni camp")
	if forced != null and camp != null:
		forced.pressed.emit()
		check(c.supplies.forced, "bouton de marche forcée sans effet")
		c.overworld.inside = -1
		camp.pressed.emit()
		check(c.supplies.camping, "bouton du camp sans effet")
		m.update_top()
		check(camp.button_pressed and "(camp)" in m.top_label.text, "barre : camp non affiché")
	var k := InputEventKey.new()
	k.physical_keycode = KEY_F
	k.pressed = true
	m._unhandled_input(k)
	check(not c.supplies.forced, "touche F sans effet")
	root.remove_child(m)
	m.free()
	CampaignState.current = null


func labels(m: Node) -> String:
	var texts: Array[String] = []
	for lb in m.find_children("*", "Label", true, false):
		texts.append((lb as Label).text)
	return " | ".join(texts)


func find_button(m: Node, prefix: String) -> Button:
	for b in m.find_children("*", "Button", true, false):
		if (b as Button).text.begins_with(prefix) and not (b as Button).is_queued_for_deletion():
			return b
	return null
