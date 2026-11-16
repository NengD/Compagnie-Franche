extends SceneTree
## Test headless du capitaine, des traits et de l'équipement :
##   godot --headless --path . -s tests/captain_test.gd
## - capitaine : nom, niveaux, compétences, solde réduite, blessure après être tombé ;
## - bataille (simulation seule) : il suit son escorte, son aura rend du moral, le ralliement
##   relance les fuyards, sa mort fait perdre du moral sans perdre la bataille ;
## - bataille (scène) : capitaine présent en escarmouche, absent s'il est blessé, sélection au clic,
##   touche C (rejoindre la sélection) ;
## - traits : gagnés à la promotion et par l'évènement « village », effets (stats, solde, butin) ;
## - équipement : achat en ville, refus, effets sur les stats sans toucher UnitTypes.STATS ;
## - sauvegarde version 6 relue, ancienne version 5 lisible (capitaine neuf) ;
## - panneau de la carte : sections du capitaine et de l'équipement, boutons qui marchent.
## Code de sortie : 0 si tout va bien, 1 sinon.

const PREFIX := "user://test_capitaine"


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
	AudioServer.set_bus_mute(0, true) # Aucun son pendant les tests
	OS.add_logger(counter)
	CampaignState.slot_prefix = PREFIX
	CampaignState.use_slot(1)
	CampaignState.event_chance = 0.0
	_test_captain_campaign()
	_test_traits()
	_test_equipment()
	_test_save()
	_test_sim()


func _process(_delta: float) -> bool:
	frame += 1
	match frame:
		1:
			_start_battle(null)
		3:
			_test_battle_scene()
		4:
			_end_battle()
			var c := CampaignState.new_game(7)
			c.captain.wounded_until = c.day + 3
			c.pending = c.contracts[0]
			_start_battle(c)
		6:
			check(battle.sim.captain == null, "scène : un capitaine blessé ne doit pas combattre")
			var hurt := false
			for m in battle.messages:
				if "garde le lit" in str(m[0]):
					hurt = true
			check(hurt, "scène : pas de message pour le capitaine blessé")
			_end_battle()
			_test_map()
		7:
			CampaignState.current = null
			CampaignState.delete_slot(1)
			for e in counter.errors:
				fails.append("erreur moteur : " + e)
			if fails.is_empty():
				print("Capitaine : tous les tests passent.")
			else:
				print("Capitaine : %d échec(s)" % fails.size())
				for f in fails:
					print("  - " + f)
			quit(0 if fails.is_empty() else 1)
			return true
	return false


# ---------------------------------------------------------------- Campagne

func _test_captain_campaign() -> void:
	var c := CampaignState.new_game(42)
	var cap := c.captain
	check(cap.name in Captain.NAMES and cap.level == 1 and cap.points == 0, "capitaine de départ : %s niveau %d" % [cap.name, cap.level])
	check(CampaignState.new_game(42).captain.name == cap.name, "le nom du capitaine doit dépendre de la graine")
	check(cap.learn("aura") != "", "compétence apprise sans point")
	# Solde réduite
	var w0 := c.daily_wage()
	cap.points = 1
	check(cap.learn("wages") == "" and cap.points == 0, "compétence « solde » refusée")
	check(absf(c.daily_wage() - w0 * (1.0 - Captain.WAGE_STEP)) < 0.001, "solde réduite : %.2f au lieu de %.2f" % [c.daily_wage(), w0 * 0.95])
	cap.points = 5
	cap.skills["aura"] = Captain.SKILL_MAX
	check(cap.learn("aura") != "" and cap.points == 5, "compétence au-delà du maximum")
	check(is_equal_approx(cap.aura_radius(), Captain.AURA_RADIUS * (1.0 + Captain.AURA_STEP * Captain.SKILL_MAX)), "rayon de l'aura")
	cap.skills["aura"] = 0
	cap.points = 0
	# Victoire : expérience et niveau
	c.pending = c.contracts[0]
	c.captain.xp = Captain.LEVEL_XP - 10.0
	var out := c.finish_battle(true, [99, 99, 99, 99, 99, 99])
	check(cap.level == 2 and cap.points == 1 and "niveau 2" in str(out["text"]), "niveau du capitaine après victoire (%d) : %s" % [cap.level, out["text"]])
	check(cap.available(c.day), "capitaine indisponible sans être tombé")
	# Il tombe : blessé, indisponible quelques jours, pas d'expérience tant qu'il est blessé
	c.pending = c.contracts[0]
	cap.fell = true
	var day := c.day
	out = c.finish_battle(false, [5, 5, 5, 5, 5, 5])
	check(not cap.fell and cap.wounded_until == day + 1 + Captain.WOUND_DAYS, "blessure : jusqu'au jour %d" % cap.wounded_until)
	check(not cap.available(c.day) and "blessé" in str(out["text"]), "capitaine blessé : %s" % out["text"])
	var xp := cap.xp
	c.pending = c.contracts[0]
	c.finish_battle(true, [5, 5, 5, 5, 5, 5])
	check(cap.xp == xp, "un capitaine blessé ne doit pas gagner d'expérience")
	c.day = cap.wounded_until
	check(cap.available(c.day), "capitaine guéri au jour %d" % c.day)


func _test_traits() -> void:
	var c := CampaignState.new_game(5)
	# Promotion : le premier trait de la liste du type
	c.pending = c.contracts[0]
	c.company[0]["xp"] = CampaignState.RANK_XP[1] - 1.0
	var out := c.finish_battle(true, [99, 99, 99, 99, 99, 99])
	check(Traits.has(c.company[0], "tenaces") and "tenaces" in str(out["text"]), "promotion sans trait : %s" % str(c.company[0].get("traits", [])))
	check(Traits.on_promotion({"type": "spear", "traits": ["tenaces", "adroits", "frugaux"]}) == "", "trait gagné alors que la liste est épuisée")
	check(Traits.on_promotion({"type": "type_inconnu"}) == "tenaces", "trait d'un type inconnu")
	# Effets sur les stats, sans toucher UnitTypes.STATS
	var r := Regiment.new()
	r.type = "spear"
	r.stats = UnitTypes.STATS["spear"]
	Traits.apply_to(r, {"type": "spear", "traits": ["tenaces", "rapides"]})
	r.set_rank(0)
	check(is_equal_approx(r.max_morale, float(UnitTypes.STATS["spear"]["morale"]) * 1.2), "tenaces : moral %.1f" % r.max_morale)
	check(is_equal_approx(float(r.stats["speed"]), float(UnitTypes.STATS["spear"]["speed"]) * 1.1), "rapides : vitesse")
	check(is_equal_approx(float(UnitTypes.STATS["spear"]["morale"]), 85.0), "UnitTypes.STATS modifié par un trait")
	# Économie : solde et butin
	var entry := {"type": "archer", "men": 10, "traits": ["frugaux", "pillards"]}
	check(is_equal_approx(Traits.wage_factor(entry), 0.8), "frugaux : solde")
	check(Traits.extra_loot([entry, {"type": "spear"}], [7, 9]) == 7, "pillards : butin")
	# Évènement de route « village »
	var v := CampaignState.new_game(9)
	CampaignState.forced_event = "village"
	v.travel(v.neighbours(0)[0])
	CampaignState.forced_event = ""
	check(Traits.has(v.company[0], "pillards"), "évènement village : pas de pillards")


func _test_equipment() -> void:
	var c := CampaignState.new_game(11)
	c.gold = 1000.0
	var price := Equipment.cost(c, 0, "armor")
	check(price == int(ceil(3 * int(UnitTypes.STATS[c.company[0]["type"]]["count"]) * float(CampaignState.TOWNS[c.location]["price"]))), "prix de l'armure : %d" % price)
	check(Equipment.buy(c, 0, "armor") == "" and is_equal_approx(c.gold, 1000.0 - price), "achat d'armure")
	check("armor" in Equipment.of(c.company[0]) and "armure" in Traits.describe(c.company[0]), "armure absente du régiment")
	check(Equipment.buy(c, 0, "armor") != "", "armure achetée deux fois")
	c.gold = 1.0
	check(Equipment.buy(c, 0, "weapons") != "" and is_equal_approx(c.gold, 1.0), "achat sans assez d'or")
	check(Equipment.buy(c, 0, "épée magique") != "", "équipement inconnu accepté")
	# Effets en bataille
	var r := Regiment.new()
	r.type = "archer"
	r.stats = UnitTypes.STATS["archer"]
	Traits.apply_to(r, {"type": "archer", "gear": ["armor", "weapons"]})
	check(is_equal_approx(float(r.stats["arrow_armor"]), 0.7) and is_equal_approx(float(r.stats["ranged_damage"]), 2.6 * 1.15), "effets de l'équipement")
	check(is_equal_approx(float(UnitTypes.STATS["archer"]["arrow_armor"]), 1.0), "UnitTypes.STATS modifié par l'équipement")


func _test_save() -> void:
	var c := CampaignState.new_game(13)
	c.captain.level = 3
	c.captain.xp = 230.0
	c.captain.points = 1
	c.captain.skills["rally"] = 2
	c.captain.wounded_until = 9
	c.company[0]["traits"] = ["tenaces"]
	c.company[1]["gear"] = ["weapons", "armor"]
	var d := JSON.parse_string(JSON.stringify(c.to_dict())) as Dictionary
	check(int(d["version"]) == 6 and CampaignState.SAVE_VERSION == 6, "version de sauvegarde")
	var b := CampaignState.from_dict(d)
	check(b != null, "sauvegarde version 6 illisible")
	if b != null:
		check(b.captain.name == c.captain.name and b.captain.level == 3 and b.captain.points == 1 and int(b.captain.skills["rally"]) == 2 and b.captain.wounded_until == 9,
			"capitaine mal relu : %s" % str(b.captain.to_dict()))
		check(Traits.has(b.company[0], "tenaces") and Equipment.of(b.company[1]) == ["weapons", "armor"], "traits ou équipement mal relus")
	# Valeurs abîmées : bornées ou ignorées
	d["captain"]["skills"]["aura"] = 99
	d["company"][0]["traits"] = ["tenaces", "inconnu", "tenaces"]
	b = CampaignState.from_dict(d)
	check(b != null and int(b.captain.skills["aura"]) == Captain.SKILL_MAX and b.company[0]["traits"] == ["tenaces"], "valeurs abîmées mal bornées")
	# Version 5 : pas de capitaine, ni traits, ni équipement
	d.erase("captain")
	d["version"] = 5
	for r in d["company"]:
		r.erase("traits")
		r.erase("gear")
	b = CampaignState.from_dict(d)
	check(b != null and b.captain.level == 1 and b.captain.name in Captain.NAMES and Traits.describe(b.company[1]) == "", "sauvegarde version 5 mal relue")
	# Fichier réel
	c.save()
	var l := CampaignState.load_game()
	check(l != null and l.captain.level == 3, "sauvegarde sur disque du capitaine")


# ---------------------------------------------------------------- Bataille (simulation seule)

func _make_sim() -> BattleSim:
	var sim := BattleSim.new()
	sim.rng.seed = 3
	sim.generate_world("plain")
	sim.spawn_army(BattleSim.PLAYER, [{"type": "spear", "men": 20}, {"type": "archer", "men": 16}])
	sim.spawn_army(BattleSim.ENEMY, [{"type": "spear", "men": 20, "rank": 0}])
	return sim


func _test_sim() -> void:
	var sim := _make_sim()
	var cap := Captain.new()
	cap.take_field(sim)
	check(sim.captain == cap and cap.escort != null and cap.escort.type == "spear", "le capitaine doit escorter l'infanterie")
	sim.step(0.05)
	check(cap.pos.distance_to(cap.escort.center) < 120.0 and cap.pos.y > cap.escort.center.y, "le capitaine doit se tenir derrière son escorte")
	# Aura : moral rendu en bataille, même pour un régiment au contact
	sim.start()
	var r := cap.escort
	r.morale = 30.0
	r.engaged_flag = true
	cap.apply_aura(sim, 1.0)
	check(is_equal_approx(r.morale, 30.0 + Captain.AURA_REGEN), "aura : moral %.1f" % r.morale)
	var far: Regiment = sim.regiments[1]
	far.center = cap.pos + Vector2(Captain.AURA_RADIUS + 50, 0)
	far.morale = 30.0
	cap.apply_aura(sim, 1.0)
	check(is_equal_approx(far.morale, 30.0), "aura : régiment hors de portée touché")
	# Ralliement : un fuyard déjà rallié une fois peut se rallier à nouveau
	r.routing = true
	r.rallied_once = true
	r.morale = 0.0
	cap.apply_aura(sim, 1.0)
	check(r.rallied_once and is_equal_approx(r.morale, 0.0), "sans ralliement, le fuyard ne doit pas être aidé")
	cap.skills["rally"] = 1
	cap.apply_aura(sim, 1.0)
	check(not r.rallied_once and r.morale > 0.0, "ralliement : fuyard non relancé")
	r.routing = false
	# Escorte en fuite : il rejoint un autre régiment
	r.routing = true
	cap.step(sim, 0.05)
	check(cap.escort == sim.regiments[1], "escorte en fuite : le capitaine doit changer de régiment")
	r.routing = false
	# Mort : grosse perte de moral, mais la bataille continue
	for x in sim.regiments:
		x.morale = x.max_morale
	var before: float = sim.regiments[0].morale
	var enemy: Regiment = sim.regiments[2]
	for i in 400:
		# Toute la troupe ennemie entoure le capitaine
		var foes := enemy.alive_soldiers()
		for j in foes.size():
			foes[j].pos = cap.pos + Vector2.from_angle(TAU * j / foes.size()) * 8.0
		sim.rebuild_grid()
		cap.step(sim, 0.05)
		if cap.dead:
			break
	check(cap.dead and cap.fell, "le capitaine au contact de l'ennemi doit finir par tomber")
	check(is_equal_approx(sim.regiments[0].morale, before - Captain.DEATH_MORALE), "mort du capitaine : moral %.1f" % sim.regiments[0].morale)
	sim.check_end()
	check(sim.state == BattleSim.State.BATTLE, "la mort du capitaine ne doit pas finir la bataille")
	cap.step(sim, 0.05) # Un mort ne fait plus rien
	cap.leave_field()
	sim.clear()


# ---------------------------------------------------------------- Bataille (scène)

func _start_battle(c: CampaignState) -> void:
	CampaignState.current = c
	battle = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	battle.seed_override = 21
	battle.terrain_override = "plain"
	root.add_child(battle)


func _end_battle() -> void:
	root.remove_child(battle)
	battle.free()
	battle = null
	CampaignState.current = null


func _test_battle_scene() -> void:
	var cap := battle.sim.captain
	check(cap != null and cap.escort != null, "escarmouche : pas de capitaine sur le champ")
	if cap == null or cap.escort == null:
		return
	# Clic sur le capitaine : lui et son escorte sont sélectionnés
	battle.orders.finish_selection(cap.pos, cap.pos, false)
	check(cap.selected and cap.escort.selected, "clic sur le capitaine sans effet")
	# Un autre clic ailleurs : désélectionné
	battle.orders.finish_selection(Vector2(5, 5), Vector2(5, 5), false)
	check(not cap.selected, "capitaine toujours sélectionné")
	# Touche C : il rejoint le régiment sélectionné
	var other: Regiment = null
	for r in battle.sim.player_regiments():
		if r != cap.escort:
			other = r
	other.selected = true
	var k := InputEventKey.new()
	k.keycode = KEY_C
	k.pressed = true
	battle.orders.handle_key(k)
	check(cap.escort == other, "touche C : le capitaine n'a pas rejoint la sélection")
	check(Hud.help_lines().any(func(s): return "capitaine" in s), "aide sans le capitaine")


func _test_map() -> void:
	var c := CampaignState.new_game(17)
	c.gold = 2000.0
	c.captain.points = 1
	CampaignState.current = c
	var m: Node = (load("res://scenes/campaign.tscn") as PackedScene).instantiate()
	m.auto_launch = false
	root.add_child(m)
	var texts: Array[String] = []
	for lb in m.find_children("*", "Label", true, false):
		texts.append((lb as Label).text)
	var all := " | ".join(texts)
	check("Capitaine" in all and c.captain.name in all and "Traits et équipement" in all, "panneau : sections absentes")
	var learn: Button = null
	var armor: Button = null
	for b in m.find_children("*", "Button", true, false):
		var t := (b as Button).text
		if t.begins_with("Ralliement") and learn == null:
			learn = b
		if t.begins_with("Armure") and armor == null:
			armor = b
	check(learn != null and armor != null and "écus" in armor.text, "panneau : boutons du capitaine ou de l'équipement absents")
	if learn != null and armor != null:
		armor.pressed.emit()
		check("armor" in Equipment.of(c.company[0]) and c.gold < 2000.0, "bouton d'armure sans effet")
		learn.pressed.emit()
		check(int(c.captain.skills["rally"]) == 1 and c.captain.points == 0, "bouton de compétence sans effet")
	root.remove_child(m)
	m.free()
