extends SceneTree
## Test headless du monde de campagne vivant (world_sim.gd, world_army.gd, world_view.gd) :
##   godot --headless --path . -s tests/world_test.gd
## - saisons, météo (automne pluvieux), marches lentes et froid de l'hiver ;
## - 200 jours de simulation sur plusieurs graines, sans erreur et sans état incohérent ;
## - une guerre, un siège et une ville qui change de mains (contrats réattribués) ;
## - contrats d'une ville en guerre (un de plus, mieux payés), influence de la réputation ;
## - rencontre d'une armée hostile : bataille (armée dispersée) ou fuite ;
## - sauvegarde : aller-retour, même suite d'évènements après relecture, ancienne version ;
## - la pluie du jour s'impose à la bataille ; la carte affiche le monde sans erreur.
## N'écrit que dans user://test_monde_*.json. Code de sortie : 0 si tout va bien, 1 sinon.


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
var node: Node
var rain_camp: CampaignState


func check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)
		print("ÉCHEC : ", msg)


func _initialize() -> void:
	AudioServer.set_bus_mute(0, true) # Aucun son pendant les tests
	OS.add_logger(counter)
	CampaignState.slot_prefix = "user://test_monde"
	for i in range(1, CampaignState.SLOT_COUNT + 1):
		CampaignState.delete_slot(i)
	CampaignState.use_slot(1)
	CampaignState.current = null
	CampaignState.event_chance = 0.0
	_test_seasons()
	_test_simulation()
	_test_capture()
	_test_war_contracts()
	_test_reputation()
	_test_encounter()
	_test_save()


## Une campagne riche (pas de désertion) qui ne s'arrête pas.
func rich(seed_value: int) -> CampaignState:
	var c := CampaignState.new_game(seed_value)
	c.gold = 1.0e7
	return c


# ---------------------------------------------------------------- Saisons et météo

func _test_seasons() -> void:
	check(WorldSim.season_of(1) == 0 and WorldSim.season_of(30) == 0 and WorldSim.season_of(31) == 1, "saisons : printemps puis été")
	check(WorldSim.season_of(61) == 2 and WorldSim.season_of(91) == WorldSim.WINTER and WorldSim.season_of(121) == 0, "saisons : automne, hiver, nouvelle année")
	check(WorldSim.season_name(95) == "hiver" and WorldSim.season_day(95) == 5, "saisons : nom et jour")
	# Pluie : bien plus fréquente en automne qu'en été
	var c := rich(11)
	var rain := [0, 0, 0, 0]
	for i in 240:
		c.pass_day()
		if c.world.raining:
			rain[WorldSim.season_of(c.day)] += 1
	check(rain[2] > rain[1] * 2 and rain[2] >= 20, "météo : l'automne n'est pas pluvieux (%s)" % str(rain))
	check("pluie" in c.world.weather_text(c.day) or c.world.weather_text(c.day) in ["temps clair", "froid sec"], "météo : texte")
	# Hiver : marches plus lentes et froid qui tue en route
	var w := rich(12)
	var spring := w.travel_days(1)
	w.day = 91
	check(w.travel_days(1) > spring, "hiver : marche pas plus lente (%d j contre %d)" % [w.travel_days(1), spring])
	var lost0 := w.men_lost
	for i in 6:
		w.day = 91 + i * 4
		w.world.armies.clear()
		w.travel(1 if w.location == 0 else 0)
	check(w.men_lost > lost0, "hiver : le froid n'emporte personne en route")
	print("Saisons et météo : OK")


# ---------------------------------------------------------------- 200 jours

func _test_simulation() -> void:
	var wars := 0
	var captures := 0
	var sieges := 0
	var max_armies := 0
	var err0 := counter.errors.size()
	for seed_value in [1, 2, 3, 4, 5]:
		var c := rich(seed_value)
		for d in 200:
			c.pass_day()
			var w := c.world
			if not w.wars.is_empty():
				wars += 1
			max_armies = maxi(max_armies, w.armies.size())
			for t in CampaignState.TOWNS.size():
				if c.town_besieged(t):
					sieges += 1
					var s := c.town_siege(t)
					check(int(s["faction"]) != int(s["defender"]) and w.at_war(int(s["faction"]), int(s["defender"])), "200 jours : siège sans guerre")
			for a in w.armies:
				if a.men < WorldSim.MIN_ARMY or a.pos.x < 0 or a.pos.y < 0 or a.pos.x > 880 or a.pos.y > 720:
					check(false, "200 jours : armée incohérente (graine %d, jour %d, %s)" % [seed_value, c.day, str(a.to_dict())])
			for k in c.contracts:
				if not k.get("final", false) and int(k["faction"]) != c.town_owner(int(k["town"])):
					check(false, "200 jours : contrat de %s offert par l'ancien maître" % WorldSim.town_name(int(k["town"])))
					break
		captures += c.world.captures
		print("  graine %d : %d villes prises, guerres en cours : %s" % [seed_value, c.world.captures, c.world.wars_text()])
		check(c.day == 201 and not c.is_over(), "200 jours : la campagne s'est arrêtée")
	check(counter.errors.size() == err0, "200 jours : erreurs %s" % str(counter.errors.slice(err0)))
	check(wars > 0, "200 jours : aucune guerre déclarée")
	check(sieges > 0, "200 jours : aucun siège")
	check(captures > 0, "200 jours : aucune ville n'a changé de mains")
	check(max_armies >= 2, "200 jours : armées trop rares")
	print("200 jours : OK (%d jours de guerre, %d jours de siège, %d villes prises)" % [wars, sieges, captures])


# ---------------------------------------------------------------- Une ville change de mains

func _test_capture() -> void:
	var c := rich(21)
	var w := c.world
	w.armies.clear()
	check(c.town_owner(1) == 0 and not c.town_besieged(1), "prise : Saint-Aubin au Comté au départ")
	w.declare_war(c, 1, 0)
	check(w.at_war(0, 1) and c.log_lines[0].contains("déclare la guerre"), "prise : guerre non annoncée")
	var army := w.add_army(1, 2, 1, 600, "march") # La Baronnie marche de Montfaucon sur Saint-Aubin
	var seen_siege := false
	for d in 40:
		c.pass_day()
		if c.town_besieged(1):
			seen_siege = true
			check(int(c.town_siege(1)["faction"]) == 1, "prise : mauvais assiégeant")
		if c.town_owner(1) == 1:
			break
	check(seen_siege, "prise : pas de siège avant la prise")
	check(c.town_owner(1) == 1 and w.captures >= 1, "prise : Saint-Aubin n'est pas tombée (garnison %d, armée %d)" % [w.garrison[1], army.men])
	check(not w.armies.has(army), "prise : l'armée victorieuse n'a pas rejoint la garnison")
	var news := false
	for s in c.log_lines:
		news = news or s.contains("prend Saint-Aubin")
	check(news, "prise : nouvelle absente du journal")
	for k in c.contracts_at(1):
		check(int(k["faction"]) == 1, "prise : contrat encore offert par le Comté")
	check(c.closed_message(1) == "" or c.faction_closed(1), "prise : portes de la ville")
	print("Prise d'une ville : OK")


# ---------------------------------------------------------------- Contrats de guerre

func _test_war_contracts() -> void:
	var c := rich(31)
	var w := c.world
	check(w.extra_contracts(0) == 0, "guerre : contrat en plus en temps de paix")
	var k := c.make_contract(0)
	var r0 := int(k["reward"])
	w.declare_war(c, 0, 1)
	check(w.extra_contracts(0) == 1 and w.extra_contracts(3) == 0, "guerre : pas de contrat en plus (ou pour la Ligue en paix)")
	w.adjust_contract(k)
	check(absi(int(k["reward"]) - int(round(r0 * WorldSim.WAR_REWARD / 10.0)) * 10) <= 10 and int(k["reward"]) > r0, "guerre : prime non majorée (%d -> %d)" % [r0, int(k["reward"])])
	check(str(k["text"]).contains("En guerre"), "guerre : texte du contrat")
	# Une ville en guerre propose au moins deux contrats
	c.contracts = c.contracts.filter(func(x: Dictionary) -> bool: return int(x["town"]) != 1)
	c.refresh_contracts(1)
	check(c.contracts_at(1).size() >= 2, "guerre : une ville en guerre n'embauche pas plus")
	w.make_peace(c, 0, 1)
	check(not w.at_war(0, 1) and c.log_lines[0].contains("trêve"), "guerre : trêve non signée")
	print("Contrats de guerre : OK")


# ---------------------------------------------------------------- Réputation

func _test_reputation() -> void:
	var c := rich(41)
	var w := c.world
	var a := WorldArmy.new()
	a.faction = 1
	a.men = 200
	check(not w.hostile_to_player(c, a), "réputation : armée hostile à une compagnie neutre")
	c.reputation[1] = CampaignState.REP_CLOSED
	check(w.hostile_to_player(c, a), "réputation : une faction fermée n'attaque pas")
	c.reputation[1] = -5
	c.reputation[0] = 25
	check(not w.hostile_to_player(c, a), "réputation : hostile sans guerre")
	w.declare_war(c, 0, 1)
	check(w.hostile_to_player(c, a), "réputation : l'ennemi d'un ami méfiant n'attaque pas")
	c.reputation[0] = 100
	check(w.rep_factor(c, 0) > 1.0 and w.rep_factor(c, 1) < 1.0, "réputation : taille des armées")
	print("Réputation : OK")


# ---------------------------------------------------------------- Rencontre d'une armée

func _test_encounter() -> void:
	var c := rich(51)
	var w := c.world
	w.armies.clear()
	w.declare_war(c, 0, 1)
	c.reputation[0] = 30
	c.reputation[1] = -10
	var a := w.add_army(1, 2, 0, 300, "march")
	a.pos = WorldSim.town_pos(0).lerp(WorldSim.town_pos(1), 0.5)
	w.on_march_day(c, 0, 1, 0.5)
	check(w.has_encounter() and w.encounter_army() == a, "rencontre : l'armée hostile ne barre pas la route")
	check(not c.travel_events.is_empty() and c.travel_events[-1].contains("barre la route"), "rencontre : pas annoncée")
	# Bataille : la compagnie la disperse
	check(w.fight(c) == "" and c.in_battle() and int(c.pending["world_army"]) == a.id, "rencontre : bataille non engagée")
	check(c.pending["enemy"].size() >= 3 and int(c.pending["faction"]) == -1, "rencontre : armée ennemie")
	# La bataille en attente survit à la sauvegarde
	var back := CampaignState.from_dict(JSON.parse_string(JSON.stringify(c.to_dict())))
	check(back != null and int(back.pending.get("world_army", -1)) == a.id, "rencontre : bataille en cours perdue à la sauvegarde")
	var rep1 := c.reputation[1]
	var out := c.finish_battle(true, [], [])
	check(not w.armies.has(a) and c.reputation[1] <= rep1 - WorldSim.REP_ARMY + 1, "rencontre : armée non dispersée ou réputation inchangée")
	check(str(out["text"]).contains("dispersée"), "rencontre : compte rendu")
	# Fuite : un jour de détour et des bagages abandonnés
	var b := w.add_army(1, 2, 0, 300, "march")
	b.pos = WorldSim.town_pos(0)
	w.on_march_day(c, 0, 1, 0.0)
	var day := c.day
	var gold := c.gold
	check(w.has_encounter(), "fuite : pas de rencontre")
	var msg := w.flee(c)
	check(not w.has_encounter() and not c.in_battle() and c.day == day + 1 and c.gold < gold - gold * WorldSim.FLEE_GOLD * 0.9, "fuite : %s" % msg)
	# Une armée amie ne barre pas la route
	var f := w.add_army(0, 0, 1, 300, "patrol")
	w.armies.clear()
	w.armies.append(f)
	w.on_march_day(c, 0, 1, 0.0)
	check(not w.has_encounter(), "rencontre : une armée amie barre la route")
	print("Rencontre : OK")


# ---------------------------------------------------------------- Sauvegarde

func _test_save() -> void:
	var c := rich(61)
	for d in 70:
		c.pass_day()
	var w := c.world
	w.declare_war(c, 1, 2)
	var a := w.add_army(1, 4, 6, 250, "march")
	a.pos = a.pos.lerp(WorldSim.town_pos(6), 0.3)
	w.encounter = {"army": a.id, "town": 6}
	w.raining = true
	check(c.save(), "sauvegarde : écriture")
	var l := CampaignState.load_game()
	check(l != null, "sauvegarde : relecture")
	if l == null:
		return
	var lw := l.world
	check(lw.owner == w.owner and lw.garrison == w.garrison and lw.wars.size() == w.wars.size() and lw.at_war(1, 2), "sauvegarde : villes ou guerres perdues")
	check(lw.armies.size() == w.armies.size() and lw.army_by_id(a.id) != null and lw.army_by_id(a.id).pos.distance_to(a.pos) < 0.01, "sauvegarde : armées perdues")
	check(lw.has_encounter() and lw.raining and lw.news == w.news and lw.next_id == w.next_id, "sauvegarde : rencontre, météo ou nouvelles perdues")
	check(int(l.to_dict()["version"]) == CampaignState.SAVE_VERSION and CampaignState.SAVE_VERSION == 7, "sauvegarde : version 7")
	# Après relecture, le monde suit exactement le même cours
	for d in 40:
		c.pass_day()
		l.pass_day()
	check(_same_world(c.world, l.world), "sauvegarde : le monde ne suit pas le même cours après relecture")
	# Ancienne sauvegarde (version 6, sans monde) : monde neuf, en paix
	var old := c.to_dict()
	old["version"] = 6
	old.erase("world")
	var o := CampaignState.from_dict(JSON.parse_string(JSON.stringify(old)))
	check(o != null and o.world.wars.is_empty() and o.town_owner(1) == 0 and o.world.armies.size() > 0, "sauvegarde : version 6 mal relue")
	# Monde abîmé : refusé
	var bad := c.to_dict()
	bad["world"]["owner"] = [0, 1]
	check(CampaignState.from_dict(JSON.parse_string(JSON.stringify(bad))) == null, "sauvegarde : monde abîmé accepté")
	bad = c.to_dict()
	bad["world"]["armies"] = [{"faction": 9, "men": 100}]
	check(CampaignState.from_dict(JSON.parse_string(JSON.stringify(bad))) == null, "sauvegarde : armée abîmée acceptée")
	CampaignState.delete_slot(1)
	print("Sauvegarde : OK")


# ---------------------------------------------------------------- Scènes : bataille sous la pluie, carte

func _process(_delta: float) -> bool:
	frame += 1
	match frame:
		1:
			# La pluie du jour s'impose à la bataille d'un contrat
			rain_camp = rich(71)
			rain_camp.world.raining = true
			rain_camp.accept(rain_camp.contracts_at(rain_camp.location)[0])
			CampaignState.current = rain_camp
			node = load("res://scenes/main.tscn").instantiate()
			root.add_child(node)
		3:
			check(node.sim.raining, "bataille : la pluie du jour ne s'impose pas")
			_free()
			rain_camp.world.raining = false
			node = load("res://scenes/main.tscn").instantiate()
			root.add_child(node)
		5:
			check(not node.sim.raining, "bataille : pluie sans pluie du jour")
			_free()
			# Carte : armées, siège, hiver, pluie et rencontre affichés sans erreur
			var c := rich(81)
			c.day = 95
			c.world.declare_war(c, 0, 1)
			c.reputation[0] = 30
			c.reputation[1] = -10
			var a := c.world.add_army(1, 2, 1, 300, "march")
			a.pos = WorldSim.town_pos(1)
			a.path.clear()
			a.mode = "siege"
			c.world.raining = true
			c.world.encounter = {"army": a.id, "town": 1}
			c.world.post(c, "nouvelle de test", true)
			c.save()
			CampaignState.current = c
			node = (load("res://scenes/campaign.tscn") as PackedScene).instantiate()
			node.auto_launch = false
			root.add_child(node)
		8:
			var texts := _texts(node.box)
			check(texts.has("Livrer bataille") and texts.has("Fuir"), "carte : choix de la rencontre absent")
			check(_any(texts, "assiégée") and _any(texts, "Hiver") and _any(texts, "nouvelle de test"), "carte : le monde n'est pas affiché")
			check(WorldView.army_at(node.state, WorldView.army_spot(node.state.world.armies[0])) != null, "carte : armée introuvable sous la souris")
			node.click_town(1)
			check(not node.walking, "carte : on marche malgré l'armée qui barre la route")
			WorldView.flee(node)
			check(not node.state.world.has_encounter() and _texts(node.box).has("Camper un jour à Valombre (solde %d écus)" % ceili(node.state.daily_wage())), "carte : fuite ou camp")
			var day: int = node.state.day
			WorldView.camp(node)
			check(node.state.day == day + 1, "carte : camper ne fait pas passer le jour")
		10:
			_free()
			CampaignState.current = null
			CampaignState.delete_slot(1)
			check(counter.errors.is_empty(), "erreurs : %s" % str(counter.errors))
			if fails.is_empty():
				print("Monde vivant : tout est OK")
			else:
				print("Monde vivant : %d échec(s)" % fails.size())
				for f in fails:
					print("  - ", f)
			quit(0 if fails.is_empty() else 1)
	return false


## Mêmes villes, guerres, armées (positions à 0,01 près : le JSON arrondit) et nouvelles.
func _same_world(a: WorldSim, b: WorldSim) -> bool:
	var da := a.to_dict()
	var db := b.to_dict()
	if da["armies"].size() != db["armies"].size():
		return false
	for i in da["armies"].size():
		var x: Dictionary = da["armies"][i]
		var y: Dictionary = db["armies"][i]
		if absf(float(x["x"]) - float(y["x"])) > 0.01 or absf(float(x["y"]) - float(y["y"])) > 0.01:
			return false
		for k in ["x", "y"]:
			x.erase(k)
			y.erase(k)
	return JSON.stringify(da) == JSON.stringify(db)


func _free() -> void:
	root.remove_child(node)
	node.free()
	node = null


func _texts(n: Node) -> Array[String]:
	var out: Array[String] = []
	for ch in n.get_children():
		if ch is Label:
			out.append((ch as Label).text)
		elif ch is Button:
			out.append((ch as Button).text)
		out.append_array(_texts(ch))
	return out


func _any(texts: Array[String], part: String) -> bool:
	for s in texts:
		if s.contains(part):
			return true
	return false
