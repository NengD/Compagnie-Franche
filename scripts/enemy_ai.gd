class_name EnemyAI
extends RefCounted
## IA ennemie simple : l'infanterie avance en ligne, les archers tirent et reculent,
## la cavalerie contourne pour frapper les archers ou prendre de flanc.
## Elle utilise aussi les formations (colonne pour marcher, carré contre la cavalerie) et la course.

var timer := 0.0
var advance := false
const LINE_SLACK := 120.0 ## Avance maximale d'un régiment d'infanterie sur le reste de la ligne
const COLUMN_DIST := 700.0 ## Au-delà, l'infanterie marche en colonne
const SQUARE_DIST := 260.0 ## Une cavalerie qui charge plus près que ça : les piquiers forment le carré
const RUSH_DIST := 220.0 ## Les hommes d'armes courent sur les derniers mètres

var line_depth := 0.0
var team := 1 ## Camp contrôlé (1 = ennemi ; 0 sert aux tests « IA contre IA »)


func think(b, dt: float) -> void:
	timer -= dt
	if timer > 0.0:
		return
	timer = 0.8

	var mine: Array[Regiment] = []
	var theirs: Array[Regiment] = []
	for r in b.regiments:
		if r.is_dead() or r.routing:
			continue
		if r.team == team:
			mine.append(r)
		elif not r.hidden:
			theirs.append(r)
	if mine.is_empty() or theirs.is_empty():
		return

	if not advance:
		if b.battle_time > 12.0:
			advance = true
		for r in mine:
			if r.center.distance_to(nearest(r, theirs).center) < 520.0:
				advance = true

	# Front de l'infanterie : chaque régiment règle son pas sur la moyenne pour avancer en ligne
	var sum := 0.0
	var n := 0
	for r in mine:
		if r.type == "spear" or r.type == "men_at_arms":
			sum += advance_depth(r.center)
			n += 1
	line_depth = sum / n if n > 0 else 0.0

	for r in mine:
		match r.type:
			"archer":
				think_archer(b, r, theirs)
			"cavalry":
				think_cavalry(r, theirs)
			_:
				think_infantry(r, theirs)


## Distance parcourue vers le camp adverse (l'ennemi descend, le joueur monte).
func advance_depth(p: Vector2) -> float:
	return p.y if team == 1 else -p.y


func think_archer(b, r: Regiment, theirs: Array[Regiment]) -> void:
	var range_px: float = r.stats["range"]
	if b.raining:
		range_px *= 0.75
	# Recule si une unité de mêlée s'approche
	var threat: Regiment = null
	var td := 140.0
	for o in theirs:
		if o.stats["ranged"]:
			continue
		var d := r.center.distance_to(o.center)
		if d < td:
			td = d
			threat = o
	if threat != null and not r.engaged:
		var away := (r.center - threat.center).normalized()
		r.target = null
		r.holding = false
		r.running = r.stamina > 0.3 # Repli au pas de course
		r.dest = (r.center + away * 140.0).clamp(Vector2(40, 40), Vector2(3160, 1960))
		r.facing = -away
		return
	if r.target != null and not r.target.is_dead() and not r.target.hidden:
		return
	# Cible : l'unité visible la plus proche qui n'est pas en mêlée
	var best: Regiment = null
	var bd := INF
	for o in theirs:
		if o.engaged:
			continue
		var d := r.center.distance_to(o.center)
		if d < bd:
			bd = d
			best = o
	if best != null and (advance or bd < range_px):
		r.target = best


func think_cavalry(r: Regiment, theirs: Array[Regiment]) -> void:
	if not advance:
		return
	if r.target != null and not r.target.is_dead() and not r.target.routing:
		return
	# Proies préférées : archers, puis tout sauf les piquiers
	var prey: Regiment = nearest_of_type(r, theirs, "archer")
	if prey == null:
		for o in theirs:
			if o.type != "spear" and (prey == null or r.center.distance_to(o.center) < r.center.distance_to(prey.center)):
				prey = o
	if prey == null:
		prey = nearest(r, theirs)
	# Contournement : viser l'arrière de la cible avant de charger
	var side := Vector2(-prey.facing.y, prey.facing.x)
	if (r.center - prey.center).dot(side) < 0.0:
		side = -side
	var flank_pt: Vector2 = prey.center - prey.facing * 140.0 + side * 120.0
	r.flank_time += 0.8
	if r.center.distance_to(flank_pt) > 90.0 and r.flank_time < 9.0:
		r.dest = flank_pt.clamp(Vector2(40, 40), Vector2(3160, 1960))
		r.facing = (prey.center - flank_pt).normalized()
	else:
		r.flank_time = 0.0
		r.target = prey
		r.running = r.stamina > 0.5 # Charge au galop


func think_infantry(r: Regiment, theirs: Array[Regiment]) -> void:
	var near := nearest(r, theirs)
	var d := r.center.distance_to(near.center)
	# Piquiers chargés par de la cavalerie : carré, on l'attend sur place
	if r.type == "spear" and not r.engaged:
		var charger: Regiment = null
		for o in theirs:
			if o.type == "cavalry" and o.target == r and r.center.distance_to(o.center) < SQUARE_DIST:
				charger = o
		if charger != null:
			if r.formation != Regiment.Formation.SQUARE:
				r.formation = Regiment.Formation.SQUARE
				r.target = null
				r.dest = r.center
			return
	# Colonne pour marcher de loin, ligne pour combattre
	if not r.engaged:
		r.formation = Regiment.Formation.COLUMN if d > COLUMN_DIST and r.target == null else Regiment.Formation.LINE
	if r.target != null and not r.target.is_dead() and not r.target.hidden:
		if r.type == "men_at_arms" and not r.engaged and r.center.distance_to(r.target.center) < RUSH_DIST and r.stamina > 0.6:
			r.running = true
		return
	if r.type == "spear":
		var cav := nearest_of_type(r, theirs, "cavalry")
		if cav != null and r.center.distance_to(cav.center) < 300.0:
			r.target = cav
			return
	if d < 340.0:
		r.target = near
	elif advance:
		var dir := (near.center - r.center).normalized()
		r.facing = dir
		if advance_depth(r.center) > line_depth + LINE_SLACK:
			r.dest = r.center # Trop en avance : attend que la ligne le rejoigne
		else:
			r.dest = r.center + dir * 160.0


func nearest(r: Regiment, list: Array[Regiment]) -> Regiment:
	var best: Regiment = null
	var bd := INF
	for o in list:
		var d := r.center.distance_to(o.center)
		if d < bd:
			bd = d
			best = o
	return best


func nearest_of_type(r: Regiment, list: Array[Regiment], type: String) -> Regiment:
	var best: Regiment = null
	var bd := INF
	for o in list:
		if o.type != type:
			continue
		var d := r.center.distance_to(o.center)
		if d < bd:
			bd = d
			best = o
	return best
