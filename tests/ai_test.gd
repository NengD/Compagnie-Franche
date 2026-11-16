extends SceneTree
## Test de l'IA ennemie (sans fenêtre) : vérifie qu'elle utilise bien les formations et la course.
##   godot --headless --path . -s tests/ai_test.gd -- --seeds=3 --first=101
##  1. Batailles complètes contre le joueur simulé « tactical » : temps passé en colonne / ligne / carré,
##     nombre de changements de formation (pas d'oscillation), carré jamais gardé sans cavalerie proche,
##     endurance (la course ne doit pas épuiser l'IA dès le début).
##  2. Scénario de charge : la cavalerie du joueur charge des piquiers ennemis → ils forment le carré,
##     puis reprennent la ligne une fois la menace passée.
##  3. Terrain : l'IA prend une colline (archers au sommet, infanterie sur le versant), passe la rivière
##     par les gués, se met en défense quand elle est bien plus faible puis contre-attaque, se retire
##     en bon ordre quand la bataille est perdue, et embusque sa cavalerie dans un bois.
## Code de sortie : 0 si tout va bien, 1 sinon.

const TestPlayer := preload("res://tests/test_player.gd")
const STEP := 0.05
const MAX_TIME := 600.0
const MAX_SWITCHES := 8 ## Changements de formation tolérés par régiment et par bataille
const STRAY_SQUARE := 6.0 ## Secondes max en carré sans cavalerie ennemie à moins de 400 px

var scene: PackedScene
var n_seeds := 3
var first_seed := 101
var fails: Array[String] = []


func _initialize() -> void:
	AudioServer.set_bus_mute(0, true) # Aucun son pendant les tests
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seeds="):
			n_seeds = int(a.trim_prefix("--seeds="))
		elif a.begins_with("--first="):
			first_seed = int(a.trim_prefix("--first="))
	scene = load("res://scenes/main.tscn")


func _process(_delta: float) -> bool:
	var total := [0.0, 0.0, 0.0]
	var runs := 0
	for i in n_seeds:
		var res := full_battle(first_seed + i)
		for f in 3:
			total[f] += res["time"][f]
		runs += res["runs"]
	print("Total infanterie IA : ligne %.0f s, colonne %.0f s, carré %.0f s ; ordres de course %d" % [total[0], total[1], total[2], runs])
	if total[1] <= 0.0:
		fails.append("l'infanterie de l'IA ne marche jamais en colonne")
	if total[0] <= 0.0:
		fails.append("l'infanterie de l'IA ne se déploie jamais en ligne")
	if runs == 0:
		fails.append("l'IA ne court jamais")
	charge_scenario(first_seed)
	hill_scenario()
	ford_scenario()
	defense_scenario()
	withdraw_scenario()
	ambush_scenario()
	if fails.is_empty():
		print("AI TEST OK")
		quit(0)
	else:
		for f in fails:
			printerr("ÉCHEC : " + f)
		print("AI TEST ÉCHOUÉ")
		quit(1)
	return true


func new_battle(seed_value: int, terrain := "") -> Node:
	var b := scene.instantiate()
	b.set("seed_override", seed_value)
	if terrain != "":
		b.set("terrain_override", terrain)
	root.add_child(b)
	return b


func end_battle(b: Node) -> void:
	root.remove_child(b)
	b.free()


func enemy_cavalry_near(b: Node, r: Regiment, dist: float) -> bool:
	for o in b.regiments:
		if o.team != r.team and o.type == "cavalry" and not o.is_dead() and not o.routing \
				and o.center.distance_to(r.center) < dist:
			return true
	return false


## Bataille complète : compteurs de formations de l'infanterie de l'IA (camp 1).
func full_battle(seed_value: int) -> Dictionary:
	var b := new_battle(seed_value)
	var player := TestPlayer.new("tactical")
	b.start_battle()
	var time := [0.0, 0.0, 0.0]
	var last := {}
	var switches := {}
	var stray := {}
	var was_running := {}
	var runs := 0
	var min_stamina_early := 1.0 ## Endurance minimale de l'IA avant le premier contact
	var contact := false
	while b.state == b.State.BATTLE and b.battle_time < MAX_TIME:
		player.update(b)
		b.simulate(STEP)
		for r: Regiment in b.regiments:
			if r.team != 1 or r.is_dead() or r.routing:
				continue
			if r.engaged:
				contact = true
			if not contact:
				min_stamina_early = minf(min_stamina_early, r.stamina)
			if r.running and not was_running.get(r.id, false):
				runs += 1
			was_running[r.id] = r.running
			if r.type != "spear" and r.type != "men_at_arms":
				continue
			time[r.formation] += STEP
			if last.has(r.id) and last[r.id] != r.formation:
				switches[r.id] = switches.get(r.id, 0) + 1
			last[r.id] = r.formation
			if r.formation == Regiment.Formation.SQUARE and not enemy_cavalry_near(b, r, 400.0):
				stray[r.id] = stray.get(r.id, 0.0) + STEP
				if stray[r.id] > STRAY_SQUARE:
					fails.append("graine %d : %s reste en carré sans cavalerie proche (t = %.0f s)" % [seed_value, r.display_name(), b.battle_time])
					stray[r.id] = -INF # Un seul message par régiment
			elif stray.get(r.id, 0.0) > 0.0:
				stray[r.id] = 0.0
	var worst := 0
	for k in switches:
		worst = maxi(worst, switches[k])
	print("Graine %d : %s à %.0f s — ligne %.0f s, colonne %.0f s, carré %.0f s, max %d changements, %d courses, endurance min avant contact %.2f" % [
		seed_value, b.State.keys()[b.state], b.battle_time, time[0], time[1], time[2], worst, runs, min_stamina_early])
	if worst > MAX_SWITCHES:
		fails.append("graine %d : un régiment change %d fois de formation (oscillation ?)" % [seed_value, worst])
	if min_stamina_early < 0.4:
		fails.append("graine %d : l'IA s'épuise avant le contact (endurance %.2f)" % [seed_value, min_stamina_early])
	end_battle(b)
	return {"time": time, "runs": runs}


## La cavalerie du joueur charge des piquiers ennemis : carré, puis retour en ligne.
func charge_scenario(seed_value: int) -> void:
	var b := new_battle(seed_value)
	var cav: Regiment = null
	var spear: Regiment = null
	for r: Regiment in b.regiments:
		if r.team == 0 and r.type == "cavalry" and cav == null:
			cav = r
	for r: Regiment in b.regiments:
		if r.team == 1 and r.type == "spear" and (spear == null or r.center.distance_to(cav.center) < spear.center.distance_to(cav.center)):
			spear = r
	if cav == null or spear == null:
		fails.append("charge : pas de cavalerie joueur ou de piquiers ennemis")
		end_battle(b)
		return
	b.start_battle()
	var squared_at := -1.0
	var contact_at := -1.0
	var unsquared_at := -1.0
	while b.state == b.State.BATTLE and b.battle_time < 120.0:
		# Ordre du joueur : charger ces piquiers, au galop une fois proche
		if not cav.is_dead() and not cav.routing:
			cav.target = spear
			cav.running = cav.center.distance_to(spear.center) < 300.0 and cav.stamina > 0.3
		b.simulate(STEP)
		if spear.is_dead() or spear.routing:
			break
		if squared_at < 0.0 and spear.formation == Regiment.Formation.SQUARE:
			squared_at = b.battle_time
		if contact_at < 0.0 and spear.engaged:
			contact_at = b.battle_time
		if squared_at >= 0.0 and unsquared_at < 0.0 and spear.formation != Regiment.Formation.SQUARE:
			unsquared_at = b.battle_time
		if (cav.is_dead() or cav.routing) and unsquared_at >= 0.0:
			break
	print("Charge : carré à %.1f s, contact à %.1f s, carré défait à %.1f s, cavalerie %s" % [
		squared_at, contact_at, unsquared_at, "détruite/en fuite" if cav.is_dead() or cav.routing else "encore là"])
	if squared_at < 0.0:
		fails.append("charge : les piquiers ne forment jamais le carré")
	elif contact_at >= 0.0 and squared_at > contact_at:
		fails.append("charge : le carré est formé après le contact")
	if squared_at >= 0.0 and unsquared_at < 0.0:
		fails.append("charge : le carré n'est jamais défait")
	end_battle(b)


# ---------------------------------------------------------------- Terrain et plans

func ai_of(b: Node) -> EnemyAI:
	return b.sim.ai


func ai_regiments(b: Node) -> Array[Regiment]:
	var out: Array[Regiment] = []
	for r: Regiment in b.regiments:
		if r.team == 1 and not r.is_dead() and not r.routing:
			out.append(r)
	return out


## Joue la bataille jusqu'à until secondes (ou sa fin) ; each est appelé après chaque pas.
func run_until(b: Node, player: RefCounted, until: float, each: Callable = Callable()) -> void:
	while b.state == b.State.BATTLE and b.battle_time < until:
		if player != null:
			player.update(b)
		b.simulate(STEP)
		if each.is_valid():
			each.call()


## Colline : en défense sur le terrain de collines, les archers gagnent le sommet, l'infanterie le versant.
func hill_scenario() -> void:
	for k in 10:
		var seed_value := first_seed + k
		var b := new_battle(seed_value, "hills")
		ai_of(b).plan_override = EnemyAI.DEFENSIVE
		b.start_battle()
		var t: Terrain = b.sim.terrain
		var before := 0.0
		for r in ai_regiments(b):
			before += t.height(r.center)
		run_until(b, TestPlayer.new("tactical"), 50.0)
		if not ai_of(b).hill.is_finite():
			end_battle(b)
			continue
		var h := {"archer": [0.0, 0], "foot": [0.0, 0]}
		var after := 0.0
		for r in ai_regiments(b):
			after += t.height(r.center)
			var key := "archer" if r.stats["ranged"] else ("foot" if EnemyAI.is_foot(r) else "")
			if key != "":
				h[key][0] += t.height(r.center)
				h[key][1] += 1
		var ha: float = h["archer"][0] / maxf(h["archer"][1], 1)
		var hf: float = h["foot"][0] / maxf(h["foot"][1], 1)
		print("Colline (graine %d) : poste %s, hauteur moyenne archers %.2f, infanterie %.2f (somme avant %.2f, après %.2f)" % [
			seed_value, ai_of(b).anchor_kind, ha, hf, before, after])
		if ai_of(b).anchor_kind != "hill":
			fails.append("colline : la défense ne s'appuie pas sur la colline trouvée")
		if ha < 0.5:
			fails.append("colline : les archers ne sont pas au sommet (hauteur %.2f)" % ha)
		if hf < 0.25:
			fails.append("colline : l'infanterie n'est pas sur le versant (hauteur %.2f)" % hf)
		end_battle(b)
		return
	fails.append("colline : aucune colline occupable sur 10 graines")


## Gués : en attaque sur la carte de rivière, l'infanterie et la cavalerie traversent par les gués.
func ford_scenario() -> void:
	var b := new_battle(first_seed, "river")
	ai_of(b).plan_override = EnemyAI.AGGRESSIVE
	b.start_battle()
	var t: Terrain = b.sim.terrain
	var start_side := {}
	for r in ai_regiments(b):
		start_side[r.id] = t.river_side(r.center)
	var bed := [0, 0] # Pas passés dans le lit par les régiments de mêlée : total, sur un gué
	var crossed := {}
	var check := func() -> void:
		for r in ai_regiments(b):
			if r.stats["ranged"]:
				continue
			var side := t.river_side(r.center)
			if side == 0.0:
				bed[0] += 1
				if t.is_ford(r.center):
					bed[1] += 1
			elif side != start_side[r.id]:
				crossed[r.id] = true
	run_until(b, TestPlayer.new("idle"), 160.0, check)
	var share := float(bed[1]) / maxf(bed[0], 1)
	print("Gués : %d régiments de mêlée ont traversé, %.0f %% du temps dans le lit passé sur un gué" % [crossed.size(), share * 100.0])
	if crossed.size() < 3:
		fails.append("gués : seulement %d régiments ont traversé la rivière" % crossed.size())
	if share < 0.8:
		fails.append("gués : l'IA traverse surtout à la nage (%.0f %% sur les gués)" % (share * 100.0))
	end_battle(b)


## Retire la part frac des soldats de chaque régiment du camp team.
func thin_out(b: Node, team: int, frac: float) -> void:
	for r: Regiment in b.regiments:
		if r.team != team:
			continue
		var alive := r.alive_soldiers()
		for i in int(alive.size() * frac):
			alive[i].alive = false
		r.update_center()


## Défense : une IA bien plus faible tient sa position, puis contre-attaque une fois l'assaut lancé.
func defense_scenario() -> void:
	var b := new_battle(first_seed, "plain")
	thin_out(b, 1, 0.5)
	b.start_battle()
	var ai := ai_of(b)
	var depth0 := 0.0
	for r in ai_regiments(b):
		if not r.stats["mounted"]: # La cavalerie de réserve peut chasser un raid
			depth0 = maxf(depth0, r.center.y)
	var player := TestPlayer.new("tactical")
	run_until(b, player, 45.0)
	var depth := 0.0
	var off_post := 0.0
	var n := 0
	for r in ai_regiments(b):
		if r.stats["mounted"]:
			continue
		depth = maxf(depth, r.center.y)
		if ai.posts.has(r.id):
			off_post += r.center.distance_to(ai.posts[r.id])
			n += 1
	off_post /= maxf(n, 1)
	var countered_early := ai.counter
	run_until(b, player, 200.0)
	print("Défense : plan %s, poste « %s », avance max %.0f px en 45 s, écart moyen au poste %.0f px, contre-attaque %s" % [
		ai.plan, ai.anchor_kind, depth - depth0, off_post, "oui" if ai.counter else "non"])
	if ai.plan != EnemyAI.DEFENSIVE:
		fails.append("défense : une IA deux fois plus faible choisit le plan %s" % ai.plan)
	if countered_early or depth - depth0 > 400.0:
		fails.append("défense : l'IA n'attend pas l'assaut (avance de %.0f px en 45 s)" % (depth - depth0))
	if off_post > 120.0:
		fails.append("défense : l'IA ne tient pas ses postes (écart moyen %.0f px)" % off_post)
	if not ai.counter and b.state == b.State.BATTLE:
		fails.append("défense : l'IA ne contre-attaque jamais")
	end_battle(b)


## Retraite : une IA décimée en pleine bataille décroche en bon ordre au lieu de se faire détruire.
func withdraw_scenario() -> void:
	var b := new_battle(first_seed, "plain")
	ai_of(b).plan_override = EnemyAI.AGGRESSIVE
	b.start_battle()
	var player := TestPlayer.new("tactical")
	run_until(b, player, 30.0)
	thin_out(b, 1, 0.72)
	run_until(b, player, 400.0)
	var ai := ai_of(b)
	var fled := 0
	for r: Regiment in b.regiments:
		if r.team == 1:
			for s in r.soldiers:
				if s.fled:
					fled += 1
	print("Retraite : %s, %d régiments sortis en bon ordre, %d hommes sauvés, fin %s à %.0f s" % [
		"sonnée" if ai.withdrawing else "jamais sonnée", ai.left_field, fled, b.State.keys()[b.state], b.battle_time])
	if not ai.withdrawing:
		fails.append("retraite : l'IA décimée ne se retire pas")
	elif ai.left_field < 2 or fled == 0:
		fails.append("retraite : presque personne ne quitte le champ en bon ordre (%d régiments)" % ai.left_field)
	end_battle(b)


## Embuscade : en débordement sur le terrain boisé, la cavalerie se cache dans un bois et en sort pour charger.
func ambush_scenario() -> void:
	for k in 10:
		var seed_value := first_seed + k
		var b := new_battle(seed_value, "forest")
		ai_of(b).plan_override = EnemyAI.FLANK
		b.start_battle()
		var ai := ai_of(b)
		var state := {"cav": null, "hidden": 0.0, "sprung": -1.0}
		var watch := func() -> void:
			if state["cav"] == null:
				for id in ai.ambush:
					state["cav"] = b.regiments[id]
			var cav: Regiment = state["cav"]
			if cav != null and not cav.is_dead():
				if cav.hidden:
					state["hidden"] += STEP
				if state["sprung"] < 0.0 and state["hidden"] > 0.0 and cav.target != null:
					state["sprung"] = b.battle_time
		run_until(b, TestPlayer.new("tactical"), 150.0, watch)
		if state["cav"] == null:
			end_battle(b)
			continue
		print("Embuscade (graine %d) : cavalerie cachée %.0f s, sortie à %.0f s" % [seed_value, state["hidden"], state["sprung"]])
		if state["hidden"] < 5.0:
			fails.append("embuscade : la cavalerie ne se cache pas dans le bois")
		if state["sprung"] < 0.0:
			fails.append("embuscade : la cavalerie ne sort jamais du bois")
		end_battle(b)
		return
	fails.append("embuscade : aucun bois propice sur 10 graines")
