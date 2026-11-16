extends RefCounted
## Joueurs simulés pour les tests (ils n'utilisent que les ordres disponibles au joueur).
##  - "idle"     : ne donne aucun ordre (les régiments se défendent seuls)
##  - "naive"    : chaque régiment charge l'ennemi visible le plus proche
##  - "tactical" : joueur correct — tient la ligne, tire, contre la cavalerie avec les piques,
##                 lance sa cavalerie sur les archers une fois la mêlée engagée

const ORDER_EVERY := 2.0

var strategy := "tactical"
var next_order := 0.0
var ai_clock := 0.0
var ai: EnemyAI ## Pour la stratégie "ai" : l'IA ennemie joue le camp du joueur
## Vrai : le joueur tactique suit aussi l'objectif de la bataille (tenir, prendre, escorter,
## poursuivre) ; faux (défaut) : il ne vise que l'armée ennemie (banc d'escarmouche, tests).
var objectives := false


func _init(s: String = "tactical") -> void:
	strategy = s


## À appeler à chaque pas de simulation.
func update(b) -> void:
	if strategy == "ai":
		if ai == null:
			ai = EnemyAI.new()
			ai.team = 0
		ai.think(b.sim, b.battle_time - ai_clock)
		ai_clock = b.battle_time
		return
	if b.battle_time < next_order:
		return
	next_order = b.battle_time + ORDER_EVERY
	match strategy:
		"naive":
			naive(b)
		"tactical":
			tactical(b)
			if objectives:
				follow_objective(b)


func visible_enemies(b) -> Array[Regiment]:
	var out: Array[Regiment] = []
	for r in b.regiments:
		if r.team != 0 and not r.is_dead() and not r.routing and not r.hidden:
			out.append(r)
	return out


func nearest(r: Regiment, list: Array[Regiment], filter: Callable = Callable()) -> Regiment:
	var best: Regiment = null
	var bd := INF
	for o in list:
		if filter.is_valid() and not filter.call(o):
			continue
		var d := r.center.distance_to(o.center)
		if d < bd:
			bd = d
			best = o
	return best


func order_attack(r: Regiment, e: Regiment) -> void:
	if r.target != e:
		r.target = e
		r.holding = false
		r.think = 0.0


func naive(b) -> void:
	for r in b.player_regiments():
		if r.target != null:
			continue
		var e: Regiment = b.nearest_enemy_regiment(r, INF, true)
		if e != null and not e.routing:
			order_attack(r, e)


func tactical(b) -> void:
	var enemies := visible_enemies(b)
	if enemies.is_empty():
		return
	var mine: Array[Regiment] = b.player_regiments()
	var melee_started := false
	for r in mine:
		if r.engaged and r.type != "archer":
			melee_started = true
	var archers: Array[Regiment] = []
	for r in mine:
		if r.type == "archer":
			archers.append(r)

	for r in mine:
		var alive_target: bool = r.target != null and not r.target.is_dead() and not r.target.routing
		match r.type:
			"archer", "crossbow":
				# Recule si de la mêlée arrive ; sinon tire sur ce qui n'est pas au contact
				var threat := nearest(r, enemies, func(o): return not o.stats["ranged"])
				if threat != null and r.center.distance_to(threat.center) < 130.0 and not r.engaged:
					r.target = null
					r.holding = false
					r.dest = (r.center + Vector2(0, 160)).clamp(Vector2(40, 40), Vector2(3160, 1960))
					continue
				var e := nearest(r, enemies, func(o): return not o.engaged)
				if e != null and r.center.distance_to(e.center) < float(r.stats["range"]) * 1.2:
					order_attack(r, e)
			"spear", "men_at_arms", "foot_knight":
				if r.type == "spear":
					var cav := nearest(r, enemies, func(o): return o.type == "cavalry")
					if cav != null and r.center.distance_to(cav.center) < 320.0:
						order_attack(r, cav)
						continue
				if alive_target:
					continue
				# Attend l'ennemi en ligne, puis frappe ce qui arrive (ou avance après 70 s)
				var e := nearest(r, enemies, func(o): return o.type != "cavalry" or r.type == "spear")
				if e == null:
					e = nearest(r, enemies)
				if r.center.distance_to(e.center) < 300.0 or b.battle_time > 70.0:
					order_attack(r, e)
			"horse_archer":
				# Harcèle l'infanterie (le décrochage devant la mêlée est automatique)
				if not alive_target:
					var foot := nearest(r, enemies, func(o): return not o.stats["mounted"])
					if foot != null:
						order_attack(r, foot)
			"cavalry":
				# Protège les archers contre la cavalerie ennemie
				var raider: Regiment = null
				for a in archers:
					var c := nearest(a, enemies, func(o): return o.type == "cavalry")
					if c != null and a.center.distance_to(c.center) < 350.0:
						raider = c
				if raider != null:
					order_attack(r, raider)
					continue
				if alive_target and r.target.type != "spear":
					continue
				if melee_started or b.battle_time > 60.0:
					var prey := nearest(r, enemies, func(o): return o.type == "archer")
					if prey == null:
						prey = nearest(r, enemies, func(o): return o.type != "spear" and o.engaged)
					if prey != null:
						order_attack(r, prey)


## Objectif de contrat : l'infanterie tient ou prend la position, escorte le convoi, et tout le
## monde court après une bande qui fuit (appelé après tactical, dont il corrige les ordres).
func follow_objective(b) -> void:
	var o = b.sim.objective
	var enemies := visible_enemies(b)
	if o == null or enemies.is_empty():
		return
	var foot: Array[Regiment] = []
	for r in b.player_regiments():
		if r.type in ["spear", "men_at_arms", "foot_knight"]:
			foot.append(r)
	match str(o.kind):
		"hold", "capture":
			# Chasser l'ennemi de la position, sinon s'y placer en ligne
			var c: Vector2 = o.center
			var reach := 220.0 if o.kind == "hold" else 300.0
			for i in foot.size():
				var r := foot[i]
				var e := nearest_to(c, enemies, reach)
				if e != null:
					order_attack(r, e)
				elif r.center.distance_to(c) > 90.0 and not r.engaged:
					r.target = null
					r.holding = false
					r.dest = c + Vector2((i - (foot.size() - 1) * 0.5) * 70.0, 30.0)
		"escort":
			# Frapper ce qui menace un chariot, sinon accompagner le chariot de tête
			var lead := Vector2.INF
			var threat: Regiment = null
			var td := 380.0
			for w in o.wagons:
				if str(w["state"]) != "road":
					continue
				var p: Vector2 = w["pos"]
				if lead == Vector2.INF or p.x > lead.x:
					lead = p
				for e in enemies:
					var d := e.center.distance_to(p)
					if d < td:
						td = d
						threat = e
			for i in foot.size():
				var r := foot[i]
				if threat != null:
					order_attack(r, threat)
				elif lead != Vector2.INF and not r.engaged:
					r.target = null
					r.holding = false
					r.dest = lead + Vector2(80.0 + 40.0 * i, -60.0 + 40.0 * (i % 4))
		"pursue":
			# La bande s'enfuit : tout le monde la rattrape
			for r in b.player_regiments():
				if r.type in ["archer", "crossbow"]:
					continue
				if r.target == null or r.target.is_dead() or r.target.routing:
					var e := nearest(r, enemies)
					if e != null:
						order_attack(r, e)


## Ennemi le plus proche d'un point, à moins de max_dist (null sinon).
func nearest_to(p: Vector2, list: Array[Regiment], max_dist: float) -> Regiment:
	var best: Regiment = null
	var bd := max_dist
	for o in list:
		var d := o.center.distance_to(p)
		if d < bd:
			bd = d
			best = o
	return best
