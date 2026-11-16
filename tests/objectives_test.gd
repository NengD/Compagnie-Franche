extends SceneTree
## Test des objectifs de bataille (battle_objectives.gd), sans fenêtre :
##   godot --headless --path . -s tests/objectives_test.gd
## Pour chaque objectif (détruire, tenir, escorter, prendre, poursuivre) : mise en place (zone, chariots,
## garnison, bande en fuite), comportement de l'IA, une victoire et une défaite, panneau du HUD et bilan.
## Puis deux contrats de campagne : l'objectif et le terrain viennent du contrat, le supplément de
## l'escorte est payé. Le test écrit dans user://test_objectifs_1.json (jamais dans les sauvegardes du joueur).
## Code de sortie : 0 si tout va bien, 1 sinon.

const STEP := 0.05

var scene: PackedScene
var fails: Array[String] = []


func _initialize() -> void:
	AudioServer.set_bus_mute(0, true) # Aucun son pendant les tests
	scene = load("res://scenes/main.tscn")
	CampaignState.slot_prefix = "user://test_objectifs"
	CampaignState.use_slot(1)


func _process(_delta: float) -> bool:
	test_registry()
	test_destroy()
	test_hold()
	test_escort()
	test_capture()
	test_pursue()
	test_campaign_capture()
	test_campaign_escort()
	CampaignState.current = null
	CampaignState.delete_slot(1)
	if fails.is_empty():
		print("OBJECTIVES TEST OK")
		quit(0)
	else:
		for f in fails:
			printerr("ÉCHEC : " + f)
		print("OBJECTIVES TEST ÉCHOUÉ")
		quit(1)
	return true


func check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)
		print("ÉCHEC : ", msg)


# ---------------------------------------------------------------- Outils

func new_battle(seed_value: int, objective: String, params: Dictionary = {}, terrain := "plain") -> Battle:
	var b := scene.instantiate() as Battle
	b.seed_override = seed_value
	b.objective_override = objective
	b.objective_params = params
	b.terrain_override = terrain
	root.add_child(b)
	return b


func end_battle(b: Battle) -> void:
	root.remove_child(b)
	b.free()


## Simule jusqu'à seconds secondes (ou la fin de la bataille).
func run(b: Battle, seconds: float) -> void:
	for i in int(seconds / STEP):
		b.simulate(STEP)
		if b.state == Battle.State.VICTORY or b.state == Battle.State.DEFEAT:
			return


func team(b: Battle, t: int) -> Array[Regiment]:
	var out: Array[Regiment] = []
	for r in b.regiments:
		if r.team == t and not r.is_dead():
			out.append(r)
	return out


func rout_team(b: Battle, t: int) -> void:
	for r in team(b, t):
		b.sim.start_rout(r)


func kill(r: Regiment) -> void:
	for s in r.soldiers:
		s.alive = false
	r.update_center()


## Distance moyenne des régiments de list à p.
func mean_dist(list: Array[Regiment], p: Vector2) -> float:
	var sum := 0.0
	for r in list:
		sum += r.center.distance_to(p)
	return sum / maxf(list.size(), 1)


func foot(list: Array[Regiment]) -> Array[Regiment]:
	return list.filter(func(r: Regiment) -> bool: return EnemyAI.is_foot(r))


## Panneau du HUD et bilan : cohérents avec l'objectif et l'issue.
func check_display(b: Battle, kind: String, won: bool) -> void:
	var o := b.sim.objective
	var vs := Vector2(1280, 720)
	check(b.hud.objective_rect(vs).has_area() == (kind != "destroy"), "%s : panneau d'objectif mal affiché" % kind)
	if kind != "destroy":
		check(o.status(b.sim) != "" and o.progress(b.sim) >= 0.0, "%s : panneau sans état ni progression" % kind)
	var rep: Dictionary = b.end_report.get("objective", {})
	check(str(rep.get("kind", "")) == kind and bool(rep.get("success", not won)) == won, "%s : bilan de l'objectif %s" % [kind, str(rep)])
	check(str(b.end_report.get("outcome", "")) == ("victory" if won else "defeat"), "%s : issue du bilan %s" % [kind, b.end_report.get("outcome", "")])
	if kind != "destroy":
		check(str(rep.get("summary", "")) != "", "%s : bilan sans résumé" % kind)
	if b.report_panel != null and kind != "destroy":
		check(b.report_panel.find_child("Objectif", true, false) != null, "%s : ligne d'objectif absente du bilan" % kind)


# ---------------------------------------------------------------- Registre

func test_registry() -> void:
	for k in BattleObjectives.KINDS:
		var o := BattleObjectives.create(k)
		check(o.kind == k and BattleObjectives.NAMES.has(k), "registre : objectif %s mal créé" % k)
	check(BattleObjectives.create("inconnu").kind == "destroy", "registre : un objectif inconnu doit valoir « détruire »")
	check(BattleObjectives.from_contract({}).kind == "destroy", "registre : contrat sans objectif")
	check(BattleObjectives.from_contract({"objective": {"kind": "hold", "time": 60.0}}).get("time") == 60.0, "registre : réglage du contrat non lu")
	var cap := BattleObjectives.create("capture")
	check(cap.fit_terrain("river", 3) == "village" and cap.fit_terrain("village", 3) == "village", "registre : terrain de la prise du village")
	check(BattleObjectives.create("destroy").fit_terrain("siege", 3) == "siege", "registre : détruire garde tous les terrains")
	check(BattleObjectives.duration_words(180.0) == "3 minutes" and BattleObjectives.clock(65.2) == "1:06", "registre : durées")
	print("Registre : OK")


# ---------------------------------------------------------------- Détruire l'ennemi

func test_destroy() -> void:
	var b := new_battle(401, "destroy")
	check(b.sim.objective.kind == "destroy", "détruire : objectif par défaut")
	b.start_battle()
	run(b, 2.0)
	rout_team(b, Battle.ENEMY)
	run(b, 1.0)
	check(b.state == Battle.State.VICTORY and "Victoire" in b.sim.objective.end_message, "détruire : pas de victoire quand l'ennemi fuit")
	check_display(b, "destroy", true)
	end_battle(b)
	b = new_battle(402, "")
	b.start_battle()
	rout_team(b, Battle.PLAYER)
	run(b, 1.0)
	check(b.state == Battle.State.DEFEAT, "détruire : pas de défaite quand la compagnie fuit")
	check_display(b, "destroy", false)
	end_battle(b)
	print("Détruire : OK")


# ---------------------------------------------------------------- Tenir une position

func test_hold() -> void:
	var b := new_battle(411, "hold", {"time": 120.0})
	var o = b.sim.objective
	check(o.kind == "hold" and o.time == 120.0, "tenir : réglages")
	check(o.center.is_finite() and o.center.y > 600.0 and o.center.y < 1350.0, "tenir : position mal placée %s" % str(o.center))
	# Défaite : la compagnie reste en arrière, l'ennemi prend la position et la garde
	var enemy_foot := foot(team(b, Battle.ENEMY))
	var d0 := mean_dist(enemy_foot, o.center)
	b.start_battle()
	run(b, 30.0)
	var d1 := mean_dist(enemy_foot, o.center)
	check(d1 < d0 - 250.0, "tenir : l'infanterie ennemie ne marche pas sur la position (%.0f → %.0f)" % [d0, d1])
	run(b, 120.0)
	check(b.state == Battle.State.DEFEAT and o.enemy_hold >= o.loss, "tenir : pas de défaite quand l'ennemi tient la position (état %d, %.0f s)" % [b.state, o.enemy_hold])
	check(BattleObjectives.standing(b.sim)[0], "tenir : la défaite doit venir de la position, pas de la compagnie brisée")
	check_display(b, "hold", false)
	end_battle(b)
	# Victoire : la compagnie occupe la position jusqu'au bout du chronomètre
	b = new_battle(412, "hold", {"time": 40.0})
	o = b.sim.objective
	var mine := team(b, Battle.PLAYER)
	BattleObjectives.place_row(mine, o.center, Vector2.UP, 90.0)
	b.start_battle()
	run(b, 45.0)
	check(b.state == Battle.State.VICTORY and "tenu" in o.end_message, "tenir : pas de victoire au bout du chronomètre (%s)" % o.end_message)
	check(o.elapsed >= o.time - 0.1, "tenir : victoire avant la fin du chronomètre")
	check_display(b, "hold", true)
	end_battle(b)
	print("Tenir : OK")


# ---------------------------------------------------------------- Escorter un convoi

func test_escort() -> void:
	var b := new_battle(421, "escort", {"wagons": 4, "need": 2})
	var o = b.sim.objective
	check(o.wagons.size() == 4 and o.need == 2, "escorte : %d chariots" % o.wagons.size())
	for w in o.wagons:
		check(float(w["x"]) < 400.0 and absf(w["pos"].y - b.road_y(w["x"])) < 1.0, "escorte : chariot hors de la route")
	var x0 := float(o.wagons[0]["x"])
	run(b, 2.0)
	check(float(o.wagons[0]["x"]) == x0, "escorte : le convoi part pendant le déploiement")
	b.start_battle()
	run(b, 5.0)
	check(float(o.wagons[0]["x"]) > x0 + 80.0, "escorte : le convoi n'avance pas (%.0f → %.0f)" % [x0, float(o.wagons[0]["x"])])
	# L'ennemi vient au convoi
	var raiders := team(b, Battle.ENEMY).filter(func(r: Regiment) -> bool: return not r.stats["ranged"])
	var d0 := 0.0
	for r in raiders:
		d0 += r.center.distance_to(o.ai_point(b.sim, r))
	run(b, 25.0)
	var d1 := 0.0
	for r in raiders:
		d1 += r.center.distance_to(o.ai_point(b.sim, r))
	check(d1 < d0 * 0.8, "escorte : l'ennemi ne va pas au convoi (%.0f → %.0f)" % [d0, d1])
	# Défaite : l'ennemi au contact des chariots les détruit
	var k := 0
	for r in team(b, Battle.ENEMY):
		var w: Dictionary = o.wagons[k % o.wagons.size()]
		BattleObjectives.place(r, w["pos"], Vector2.DOWN)
		k += 1
	run(b, 60.0)
	check(b.state == Battle.State.DEFEAT and o.lost() >= 3, "escorte : pas de défaite quand les chariots sont détruits (état %d, %d perdus)" % [b.state, o.lost()])
	check(BattleObjectives.standing(b.sim)[0], "escorte : la défaite doit venir du convoi")
	check_display(b, "escort", false)
	end_battle(b)
	# Victoire : tous les chariots arrivent
	b = new_battle(422, "escort")
	o = b.sim.objective
	b.start_battle()
	for w in o.wagons:
		w["x"] = BattleObjectives.Escort.END_X - 5.0
	run(b, 3.0)
	check(b.state == Battle.State.VICTORY and o.arrived() == 4, "escorte : pas de victoire à l'arrivée du convoi (%d arrivés)" % o.arrived())
	check(int(o.result(b.sim)["saved"]) == 4, "escorte : chariots sauvés mal comptés")
	check_display(b, "escort", true)
	end_battle(b)
	print("Escorte : OK")


# ---------------------------------------------------------------- Prendre un village

func test_capture() -> void:
	var b := new_battle(431, "capture", {}, "")
	var o = b.sim.objective
	check(b.terrain.kind == "village", "prendre : terrain %s au lieu du village" % b.terrain.kind)
	check(b.terrain.village_rect.has_point(o.center), "prendre : la place n'est pas dans le village")
	var garrison := foot(team(b, Battle.ENEMY))
	check(mean_dist(garrison, o.center) < 250.0, "prendre : la garnison n'est pas sur la place")
	# La garnison tient la place (pas de contre-attaque générale)
	b.start_battle()
	run(b, 60.0)
	check(b.state == Battle.State.BATTLE and b.ai.plan == EnemyAI.DEFENSIVE and not b.ai.counter, "prendre : la garnison ne tient pas (plan %s)" % b.ai.plan)
	check(mean_dist(garrison, o.center) < 400.0, "prendre : la garnison a quitté la place (%.0f)" % mean_dist(garrison, o.center))
	# Défaite : la nuit tombe
	o.elapsed = o.time - 1.0
	run(b, 3.0)
	check(b.state == Battle.State.DEFEAT and "nuit" in o.end_message, "prendre : pas de défaite à la nuit (%s)" % o.end_message)
	check_display(b, "capture", false)
	end_battle(b)
	# Victoire : la compagnie chasse la garnison et occupe la place
	b = new_battle(432, "capture", {"hold": 6.0}, "")
	o = b.sim.objective
	var theirs := team(b, Battle.ENEMY)
	for i in theirs.size():
		if i == 0:
			BattleObjectives.place(theirs[i], Vector2(150, 150), Vector2.DOWN) # Un régiment reste debout, loin
		else:
			kill(theirs[i])
	BattleObjectives.place_row(foot(team(b, Battle.PLAYER)), o.center, Vector2.UP, 70.0)
	b.start_battle()
	run(b, 20.0)
	check(b.state == Battle.State.VICTORY and o.taken >= 1.0, "prendre : pas de victoire sur la place (état %d, %.0f %%)" % [b.state, o.taken * 100.0])
	check(BattleObjectives.standing(b.sim)[1], "prendre : la victoire doit venir de la place, pas de l'ennemi détruit")
	check_display(b, "capture", true)
	end_battle(b)
	print("Prendre : OK")


# ---------------------------------------------------------------- Poursuivre

func test_pursue() -> void:
	var b := new_battle(441, "pursue")
	var o = b.sim.objective
	var band := team(b, Battle.ENEMY)
	var y0 := 0.0
	for r in band:
		check(r.speed_mult < 1.0 and r.center.y > 850.0, "poursuivre : la bande n'est pas en route ou pas ralentie")
		y0 += r.center.y
	check(o.initial > 0 and o.limit() == ceili(o.initial * 0.5), "poursuivre : limite de fuite %d pour %d" % [o.limit(), o.initial])
	# Défaite : personne ne la poursuit, la bande quitte la carte
	b.start_battle()
	run(b, 20.0)
	var y1 := 0.0
	for r in band:
		y1 += r.center.y
	check(b.ai.plan == EnemyAI.FLEE and y1 < y0 - 200.0 * band.size(), "poursuivre : la bande ne fuit pas vers le nord (plan %s)" % b.ai.plan)
	run(b, 160.0)
	check(b.state == Battle.State.DEFEAT and o.escaped >= o.limit(), "poursuivre : pas de défaite quand la bande s'échappe (état %d, %d échappés)" % [b.state, o.escaped])
	check(BattleObjectives.standing(b.sim)[0], "poursuivre : la défaite doit venir de la fuite")
	check_display(b, "pursue", false)
	end_battle(b)
	# Victoire : la bande est rattrapée et dispersée avant d'atteindre le bord
	b = new_battle(442, "pursue")
	o = b.sim.objective
	b.start_battle()
	run(b, 5.0)
	rout_team(b, Battle.ENEMY)
	run(b, 1.0)
	check(b.state == Battle.State.VICTORY and o.escaped == 0 and "rattrap" in o.end_message, "poursuivre : pas de victoire quand la bande est dispersée")
	check_display(b, "pursue", true)
	end_battle(b)
	print("Poursuivre : OK")


# ---------------------------------------------------------------- Contrats de campagne

## Campagne en bataille sur un contrat de la ville actuelle, avec l'objectif objective.
func campaign_with(objective: Dictionary, seed_value: int) -> CampaignState:
	var c := CampaignState.new_game(seed_value)
	c.contracts.clear()
	var k := c.make_contract(c.location)
	k["objective"] = objective
	c.contracts.append(k)
	check(c.accept(k) == "", "campagne : contrat refusé")
	CampaignState.current = c
	return c


func test_campaign_capture() -> void:
	var c := campaign_with({"kind": "capture", "time": 360.0, "hold": 25.0}, 51)
	var b := scene.instantiate() as Battle
	root.add_child(b)
	check(b.campaign == c and b.sim.objective.kind == "capture" and b.terrain.kind == "village", "campagne : objectif ou terrain du contrat non repris (%s, %s)" % [b.sim.objective.kind, b.terrain.kind])
	b.start_battle()
	rout_team(b, Battle.ENEMY)
	run(b, 1.0)
	var res: Dictionary = b.campaign_result
	check(b.state == Battle.State.VICTORY and str(res.get("objective", {}).get("kind", "")) == "capture", "campagne : bilan sans l'objectif")
	check(str(res.get("text", "")).begins_with("Village pris"), "campagne : compte rendu « %s »" % str(res.get("text", "")))
	end_battle(b)
	CampaignState.current = null
	print("Campagne (prendre) : OK")


func test_campaign_escort() -> void:
	var c := campaign_with({"kind": "escort", "wagons": 4, "need": 2}, 52)
	var b := scene.instantiate() as Battle
	root.add_child(b)
	var o = b.sim.objective
	check(o.kind == "escort", "campagne : l'escorte n'est pas l'objectif de la bataille")
	b.start_battle()
	for w in o.wagons:
		w["x"] = BattleObjectives.Escort.END_X - 5.0
	run(b, 3.0)
	var res: Dictionary = b.campaign_result
	check(b.state == Battle.State.VICTORY, "campagne : l'escorte n'est pas gagnée")
	var expected := int(round(int(res.get("reward", 0)) * float(CampaignState.OBJECTIVES["escort"]["bonus"]) * 4))
	check(int(res.get("bonus", 0)) == expected and expected > 0, "campagne : supplément du convoi %d au lieu de %d" % [int(res.get("bonus", 0)), expected])
	var money := float(res["reward"]) + float(res["loot"]) + float(res["bonus"]) - float(res["pillage"]) - float(res["wage"])
	check(absf(float(res["gold_before"]) + money - c.gold) < 0.01, "campagne : prime, butin, supplément et solde ne font pas l'or final")
	end_battle(b)
	CampaignState.current = null
	print("Campagne (escorte) : OK")
