extends SceneTree
## Test headless du chef ennemi et des pièges :
##   godot --headless --path . -s tests/chefs_pieges_test.gd
## - chef (simulation seule) : garde d'infanterie renforcée, il se tient derrière elle, recule quand
##   on le menace, tombe sous les coups et sa mort fait baisser le moral de toute l'armée ennemie ;
## - pièges : pose seulement en déploiement, dans la zone bleue et dans le budget ; retrait remboursé ;
##   budget selon le terrain et la pluie ;
## - un rang de pieux brise une charge de cavalerie (pertes, régiment arrêté), sans pieux elle passe ;
##   fossé et chausse-trapes ralentissent ;
## - campagne : chef présent dès le niveau 2, tête du chef payée (prime et renommée) et écrite au bilan ;
## - scène : chef et pièges en escarmouche, boutons du HUD, touche P, clic de pose, aide.
## Code de sortie : 0 si tout va bien, 1 sinon.

const PREFIX := "user://test_chefs_pieges"


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
	_test_commander_sim()
	_test_trap_rules()
	_test_stakes_stop_charge()
	_test_slowing_traps()
	_test_campaign_reward()


func _process(_delta: float) -> bool:
	frame += 1
	match frame:
		1:
			_start_battle()
		3:
			_test_scene()
		4:
			_end_battle()
			CampaignState.delete_slot(1)
			for e in counter.errors:
				fails.append("erreur moteur : " + e)
			if fails.is_empty():
				print("Chefs et pièges : tous les tests passent.")
			else:
				print("Chefs et pièges : %d échec(s)" % fails.size())
				for f in fails:
					print("  - " + f)
			quit(0 if fails.is_empty() else 1)
			return true
	return false


func _make_sim(enemy: Array) -> BattleSim:
	var sim := BattleSim.new()
	sim.rng.seed = 5
	sim.generate_world("plain")
	sim.spawn_army(BattleSim.PLAYER, [{"type": "spear", "men": 20}, {"type": "archer", "men": 16}])
	sim.spawn_army(BattleSim.ENEMY, enemy)
	return sim


# ---------------------------------------------------------------- Chef ennemi

func _test_commander_sim() -> void:
	var sim := _make_sim([{"type": "archer", "men": 16}, {"type": "men_at_arms", "men": 20}, {"type": "cavalry", "men": 12}])
	var maa: Regiment = sim.regiments[3]
	var morale0 := maa.max_morale
	var hp0: float = maa.soldiers[0].max_hp
	var cmd := EnemyCommander.new()
	check(cmd.take_field(sim) and sim.commander == cmd, "le chef doit prendre le champ")
	check(cmd.guard == maa, "garde : l'infanterie attendue, pas les %s" % (cmd.guard.type if cmd.guard != null else "rien"))
	check(is_equal_approx(maa.max_morale, morale0 * EnemyCommander.GUARD_MORALE) and is_equal_approx(maa.soldiers[0].max_hp, hp0 * EnemyCommander.GUARD_HP), "garde non renforcée")
	sim.step(0.05)
	check(cmd.pos.y < maa.center.y and cmd.pos.distance_to(maa.center) < 120.0, "le chef doit se tenir derrière sa garde (%s / %s)" % [cmd.pos, maa.center])
	# Menacé : il recule
	sim.start()
	sim.ai.team = 9 # Pas d'IA : on teste le chef seul
	var spear: Regiment = sim.regiments[0]
	var start := cmd.pos
	for s in spear.soldiers:
		s.pos = start + Vector2(randf_range(-30, 30), 60.0 + randf_range(0, 20))
	sim.rebuild_grid()
	cmd.step(sim, 0.5)
	check(cmd.pos.y < start.y - 5.0, "menacé, le chef doit reculer (%.1f → %.1f)" % [start.y, cmd.pos.y])
	# Il tombe : tout son camp vacille
	for r in sim.regiments:
		r.morale = r.max_morale
	var enemy_before: Array[float] = []
	for r in sim.regiments:
		if r.team == BattleSim.ENEMY:
			enemy_before.append(r.morale)
	var mine_before := spear.morale
	for i in 400:
		for s in spear.soldiers:
			if s.alive:
				s.pos = cmd.pos + Vector2(randf_range(-6, 6), randf_range(-6, 6))
		sim.rebuild_grid()
		cmd.take_hits(sim, 0.05)
		if cmd.dead:
			break
	check(cmd.dead, "entouré, le chef doit tomber (vie %.1f)" % cmd.hp)
	var k := 0
	for r in sim.regiments:
		if r.team == BattleSim.ENEMY:
			check(r.morale <= enemy_before[k] - EnemyCommander.DEATH_MORALE + 0.01, "mort du chef : le moral des %s doit baisser (%.1f)" % [r.type, r.morale])
			k += 1
	check(is_equal_approx(spear.morale, mine_before), "mort du chef : le moral du joueur ne doit pas bouger")
	check(EnemyCommander.result_of(sim)["slain"], "résultat : chef tombé")
	cmd.step(sim, 0.05) # Mort : plus rien
	sim.clear()


# ---------------------------------------------------------------- Pièges

func _test_trap_rules() -> void:
	check(BattleTraps.budget_for("forest", false) > BattleTraps.budget_for("river", false), "le bois doit donner plus de pieux que la rivière")
	check(BattleTraps.budget_for("plain", true) == BattleTraps.budget_for("plain", false) - BattleTraps.RAIN_PENALTY, "la pluie doit réduire le budget")
	check(BattleTraps.budget_for("siege", true) >= BattleTraps.BUDGET_MIN, "budget minimal")
	var sim := _make_sim([{"type": "spear", "men": 20}])
	var t := BattleTraps.new()
	t.budget = 5
	sim.traps = t
	var y := sim.deploy_top() + 100.0
	check(t.place(sim, "stakes", Vector2(800, sim.deploy_top() - 50.0)) != "", "piège posé hors de la zone bleue")
	check(t.place(sim, "stakes", Vector2(800, y)) == "" and t.left() == 3, "pieux refusés en déploiement")
	check(t.place(sim, "caltrops", Vector2(810, y)) != "", "piège posé sur un autre")
	check(t.place(sim, "catapulte", Vector2(1400, y)) != "", "piège inconnu accepté")
	check(t.place(sim, "ditch", Vector2(1200, y)) == "" and t.left() == 0, "fossé refusé")
	check(t.place(sim, "caltrops", Vector2(1600, y)) != "" and t.traps.size() == 2, "piège posé au-delà du budget")
	check(t.remove_at(sim, Vector2(1200, y)) == "Fossé" and t.left() == 3, "fossé non retiré ou non remboursé")
	t.tool = ""
	t.cycle_tool()
	check(t.tool == "stakes", "touche P : premier outil")
	t.cycle_tool()
	t.cycle_tool()
	t.cycle_tool()
	check(t.tool == "", "touche P : retour à aucun outil")
	sim.start()
	check(t.place(sim, "caltrops", Vector2(1600, y)) != "" and t.traps.size() == 1, "piège posé pendant la bataille")
	check(t.remove_at(sim, Vector2(800, y)) == "" and t.traps.size() == 1, "piège retiré pendant la bataille")
	sim.clear()


## Cavalerie ennemie lancée au galop sur des piquiers : avec ou sans pieux devant eux.
func _charge(with_stakes: bool) -> Dictionary:
	var sim := BattleSim.new()
	sim.rng.seed = 11
	sim.generate_world("plain")
	var foot := sim.add_regiment(BattleSim.PLAYER, "spear", Vector2(1600, 1650), Vector2.UP, 30)
	var horse := sim.add_regiment(BattleSim.ENEMY, "cavalry", Vector2(1600, 1180), Vector2.DOWN, 16)
	sim.traps = BattleTraps.new()
	sim.traps.budget = 10
	var stake_y := 1520.0
	if with_stakes:
		for x in [1500.0, 1620.0, 1740.0]:
			check(sim.traps.place(sim, "stakes", Vector2(x - 60.0, stake_y)) == "", "pieux refusés à x=%d" % x)
	sim.start()
	sim.ai.team = 9 # Pas d'IA : la charge est ordonnée à la main
	horse.target = foot
	horse.running = true
	var crossed := 0
	var engaged := false
	for i in 160: # 8 secondes
		if horse.target == null and not with_stakes:
			horse.target = foot
		sim.step(0.05)
		engaged = engaged or horse.engaged
	for s in horse.soldiers:
		if s.alive and s.pos.y > stake_y + 20.0:
			crossed += 1
	var dead := 0
	for s in horse.soldiers:
		if not s.alive:
			dead += 1
	var out := {"crossed": crossed, "dead": dead, "impaled": int(sim.traps.stats["impaled"]),
		"stopped": int(sim.traps.stats["stopped"]), "engaged": engaged, "target": horse.target}
	sim.clear()
	return out


func _test_stakes_stop_charge() -> void:
	var free := _charge(false)
	var staked := _charge(true)
	check(bool(free["engaged"]) and int(free["crossed"]) >= 4, "sans pieux, la charge doit arriver (%s)" % str(free))
	check(int(staked["impaled"]) > 0 and int(staked["stopped"]) >= 1, "les pieux doivent briser la charge (%s)" % str(staked))
	check(staked["target"] == null, "après les pieux, le régiment doit s'arrêter")
	check(int(staked["dead"]) > 0, "les pieux doivent coûter des cavaliers (%s / %s)" % [staked, free])
	check(int(staked["crossed"]) < int(free["crossed"]), "moins de cavaliers doivent passer les pieux (%d / %d)" % [staked["crossed"], free["crossed"]])


func _test_slowing_traps() -> void:
	var sim := _make_sim([{"type": "spear", "men": 20}, {"type": "cavalry", "men": 10}])
	var t := BattleTraps.new()
	t.budget = 10
	sim.traps = t
	var y := sim.deploy_top() + 120.0
	check(t.place(sim, "ditch", Vector2(700, y)) == "" and t.place(sim, "caltrops", Vector2(1100, y)) == "", "fossé ou chausse-trapes refusés")
	var foe: Soldier = sim.regiments[2].soldiers[0]
	var mine: Soldier = sim.regiments[0].soldiers[0]
	foe.pos = Vector2(700, y)
	check(is_equal_approx(t.speed_factor(foe), BattleTraps.DITCH_SLOW) and t.damage_taken(foe) > 1.0, "fossé : ni ralenti ni désorganisé")
	foe.pos = Vector2(1100, y)
	check(is_equal_approx(t.speed_factor(foe), BattleTraps.CALTROPS_SLOW), "chausse-trapes : pas de ralentissement")
	mine.pos = Vector2(1100, y)
	check(t.speed_factor(mine) == 1.0, "nos pièges ne doivent pas gêner la compagnie")
	foe.pos = Vector2(700, y)
	var r: Regiment = sim.regiments[2]
	sim.start()
	var m0 := r.morale
	foe.momentum = 1.0
	sim.rebuild_grid()
	t.step(sim, 0.5)
	check(foe.momentum == 0.0 and r.morale < m0 and int(t.stats["ditched"]) == 1, "fossé : charge et moral intacts")
	check(t.summary().contains("fossé"), "bilan des pièges : %s" % t.summary())
	sim.clear()


# ---------------------------------------------------------------- Campagne

func _test_campaign_reward() -> void:
	var c := CampaignState.new_game(31)
	var k: Dictionary = c.contracts[0].duplicate(true)
	k["difficulty"] = 2
	k.erase("ambush")
	c.pending = k
	c.gold = 100.0
	var fame0 := c.fame
	c.pending["commander"] = {"present": true, "name": "Foulques le Noir", "slain": true, "fled": false}
	var out := c.finish_battle(true, [99, 99, 99, 99, 99, 99])
	var info: Dictionary = out.get("commander", {})
	check(int(info.get("bounty", 0)) >= EnemyCommander.BOUNTY_MIN, "tête du chef non payée : %s" % str(info))
	check(c.fame >= fame0 + EnemyCommander.FAME_WIN, "tête du chef : renommée")
	check("Foulques le Noir" in str(out["text"]), "compte rendu sans le chef : %s" % out["text"])
	# Chef survivant : rien
	var c2 := CampaignState.new_game(31)
	c2.pending = c2.contracts[0].duplicate(true)
	c2.pending["commander"] = {"present": true, "name": "X", "slain": false}
	var out2 := c2.finish_battle(true, [99, 99, 99, 99, 99, 99])
	check(int((out2.get("commander", {}) as Dictionary).get("bounty", -1)) == 0, "chef survivant payé")
	# Ligne du bilan
	var rep := BattleReport.new()
	rep.report = {"commander": {"present": true, "name": "Foulques le Noir", "slain": true}, "campaign": out}
	var line := rep.commander_line()
	check("Foulques" in line and "écus" in line, "ligne du bilan : %s" % line)
	rep.free()
	# Présence selon le niveau du contrat
	var b := Battle.new()
	b.campaign = c2
	c2.pending = {"difficulty": 1}
	check(not EnemyCommander.wanted(b), "chef dans un contrat de niveau 1")
	c2.pending = {"difficulty": 2}
	check(EnemyCommander.wanted(b), "pas de chef dans un contrat de niveau 2")
	c2.pending = {"difficulty": 1, "final": true}
	check(EnemyCommander.wanted(b), "pas de chef dans la bataille décisive")
	c2.pending = {"difficulty": 3, "ambush": true}
	check(not EnemyCommander.wanted(b), "chef dans une embuscade de la route")
	b.campaign = null
	check(not EnemyCommander.wanted(b), "chef en escarmouche")
	b.is_tutorial = true
	check(not EnemyCommander.wanted(b), "chef au tutoriel")
	b.free()


# ---------------------------------------------------------------- Scène

## Bataille d'un contrat de niveau 2 (chef ennemi et pièges), en rase campagne.
func _start_battle() -> void:
	var c := CampaignState.new_game(41)
	var k: Dictionary = c.contracts[0].duplicate(true)
	k["difficulty"] = 2
	k.erase("ambush")
	k.erase("siege")
	c.pending = k
	CampaignState.current = c
	battle = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	battle.seed_override = 23
	battle.terrain_override = "plain"
	root.add_child(battle)


func _end_battle() -> void:
	root.remove_child(battle)
	battle.free()
	battle = null
	CampaignState.current = null


func _test_scene() -> void:
	var cmd := battle.sim.commander
	check(battle.campaign != null, "la bataille de contrat n'a pas démarré")
	check(cmd != null and cmd.guard != null and cmd.guard.team == BattleSim.ENEMY, "contrat de niveau 2 : pas de chef ennemi")
	var t := battle.sim.traps
	check(t != null and t.budget == BattleTraps.budget_for("plain", battle.sim.raining), "contrat : pas de pièges")
	if t == null:
		return
	var vs := battle.hud.get_viewport_rect().size
	var btns := battle.hud.trap_buttons(vs)
	check(btns.size() == 3, "HUD : %d boutons de pièges" % btns.size())
	# Bouton du HUD : choisit les chausse-trapes
	check(battle.orders.trap_button_click((btns[2]["rect"] as Rect2).get_center()) and t.tool == "caltrops", "bouton des chausse-trapes sans effet")
	# Touche P : outil suivant
	var ev := InputEventKey.new()
	ev.keycode = KEY_P
	ev.pressed = true
	battle.orders.handle_key(ev)
	check(t.tool == "", "touche P après les chausse-trapes : %s" % t.tool)
	battle.orders.handle_key(ev)
	check(t.tool == "stakes", "touche P : pieux attendus")
	var at := Vector2(BattleSim.WORLD_SIZE.x * 0.5 - 300.0, battle.sim.deploy_top() + 60.0)
	battle.orders.place_trap(at)
	check(t.traps.size() == 1, "clic de pose sans piège")
	battle.renderer.queue_redraw()
	battle.hud.queue_redraw()
	var help := "\n".join(Hud.help_lines())
	check("pièges" in help and GameOptions.key_label("traps") in help, "aide sans la touche des pièges")
	battle.start_battle()
	var announced := false
	for m in battle.messages:
		announced = announced or (cmd != null and cmd.name in str(m[0]))
	check(announced, "chef non annoncé au début de la bataille")
	check(battle.hud.trap_buttons(vs).is_empty() and not battle.orders.trap_tool_active(), "boutons de pièges après le déploiement")
	battle.orders.cycle_trap_tool()
	check(t.place(battle.sim, "caltrops", at + Vector2(400, 0)) != "", "piège posé en pleine bataille")
	for i in 20:
		battle.simulate(0.05)
	var rep := battle.build_end_report()
	check(bool(rep["commander"].get("present", false)), "bilan sans chef ennemi")
