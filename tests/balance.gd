extends SceneTree
## Banc d'essai d'équilibrage (sans fenêtre) : joue de nombreuses batailles par stratégie.
##   godot --headless --path . -s tests/balance.gd -- --seeds=12 --strategies=idle,naive,tactical
##   --terrain=T : terrain imposé (plain, forest, hills, river, village, siege) ; « all » = chacun tour à tour ;
##                 sans option, tiré au sort comme en escarmouche.
## Affiche le taux de victoire, la durée et les pertes moyennes.

const TestPlayer := preload("res://tests/test_player.gd")
const STEP := 0.05
const MAX_TIME := 600.0

var scene: PackedScene
var n_seeds := 10
var first_seed := 1
var strategies: PackedStringArray = ["idle", "naive", "tactical"]
var trace := false ## --trace : journal des mêlées et des déroutes
var mirror := false ## --mirror : armées identiques (diagnostic)
var terrains: PackedStringArray = [""] ## "" = terrain au hasard
var terrain := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seeds="):
			n_seeds = int(a.trim_prefix("--seeds="))
		elif a.begins_with("--first="):
			first_seed = int(a.trim_prefix("--first="))
		elif a.begins_with("--strategies="):
			strategies = a.trim_prefix("--strategies=").split(",")
		elif a == "--trace":
			trace = true
		elif a == "--mirror":
			mirror = true
		elif a.begins_with("--terrain="):
			var t := a.trim_prefix("--terrain=")
			terrains = PackedStringArray(Terrain.KINDS) if t == "all" else t.split(",")
	scene = load("res://scenes/main.tscn")


func _process(_delta: float) -> bool:
	var t0 := Time.get_ticks_msec()
	for tk in terrains:
		terrain = tk
		if terrains.size() > 1 or tk != "":
			print("--- terrain : %s" % (tk if tk != "" else "au hasard"))
		run_strategies()
	print("(%.1f s de calcul)" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit(0)
	return true


func run_strategies() -> void:
	for strat in strategies:
		var wins := 0
		var times: Array[float] = []
		var surv := [0.0, 0.0]
		var unfinished := 0
		for i in n_seeds:
			var res := play(strat, first_seed + i)
			if res["state"] == "VICTORY":
				wins += 1
			elif res["state"] == "BATTLE":
				unfinished += 1
			times.append(res["time"])
			surv[0] += res["surv"][0]
			surv[1] += res["surv"][1]
		times.sort()
		var mean := 0.0
		for t in times:
			mean += t
		mean /= times.size()
		print("%-9s victoires %2d/%d  non finies %d  durée moy %5.0f s (min %4.0f, médiane %4.0f, max %4.0f)  survivants joueur %4.0f%%  ennemi %4.0f%%" % [
			strat, wins, n_seeds, unfinished, mean, times[0], times[times.size() / 2], times[-1],
			100.0 * surv[0] / n_seeds, 100.0 * surv[1] / n_seeds])


func play(strat: String, seed_value: int) -> Dictionary:
	var b := scene.instantiate()
	b.set("seed_override", seed_value)
	b.set("terrain_override", terrain)
	root.add_child(b)
	var player := TestPlayer.new(strat)
	if mirror:
		# Armées identiques : retire le régiment ennemi en trop (piquiers le plus à droite)
		var extra: Regiment = null
		for r in b.regiments:
			if r.team == 1 and r.type == "spear" and (extra == null or r.center.x > extra.center.x):
				extra = r
		for s in extra.soldiers:
			s.alive = false
		extra.update_center()
		b.initial_strength[1] -= extra.soldiers.size()
	b.start_battle()
	var was_routing := {}
	var was_engaged := {}
	while b.state == b.State.BATTLE and b.battle_time < MAX_TIME:
		player.update(b)
		b.simulate(STEP)
		if trace:
			for r in b.regiments:
				var key: int = r.id
				if r.engaged and not was_engaged.get(key, false):
					print("  %5.1f s  %s %s (%d) entre en mêlée" % [b.battle_time, "J" if r.team == 0 else "E", r.type, r.alive_n])
				was_engaged[key] = r.engaged
				if r.routing != was_routing.get(key, false):
					print("  %5.1f s  %s %s %s — %d/%d vivants" % [b.battle_time, "J" if r.team == 0 else "E", r.type,
						"FUIT" if r.routing else "se rallie", r.alive_n, int(r.stats["count"])])
				was_routing[key] = r.routing
	if trace:
		print("  fin %s à %.1f s" % [b.State.keys()[b.state], b.battle_time])
	var alive := [0, 0]
	for r in b.regiments:
		alive[r.team] += r.alive_n if not r.routing else 0
	var res := {
		"state": b.State.keys()[b.state],
		"time": b.battle_time,
		"surv": [float(alive[0]) / b.initial_strength[0], float(alive[1]) / b.initial_strength[1]],
	}
	root.remove_child(b)
	b.free()
	return res
