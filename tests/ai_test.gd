extends SceneTree
## Test de l'IA ennemie (sans fenêtre) : vérifie qu'elle utilise bien les formations et la course.
##   godot --headless --path . -s tests/ai_test.gd -- --seeds=3 --first=101
##  1. Batailles complètes contre le joueur simulé « tactical » : temps passé en colonne / ligne / carré,
##     nombre de changements de formation (pas d'oscillation), carré jamais gardé sans cavalerie proche,
##     endurance (la course ne doit pas épuiser l'IA dès le début).
##  2. Scénario de charge : la cavalerie du joueur charge des piquiers ennemis → ils forment le carré,
##     puis reprennent la ligne une fois la menace passée.
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
	if fails.is_empty():
		print("AI TEST OK")
		quit(0)
	else:
		for f in fails:
			printerr("ÉCHEC : " + f)
		print("AI TEST ÉCHOUÉ")
		quit(1)
	return true


func new_battle(seed_value: int) -> Node:
	var b := scene.instantiate()
	b.set("seed_override", seed_value)
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
