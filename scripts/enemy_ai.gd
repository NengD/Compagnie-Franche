class_name EnemyAI
extends RefCounted
## IA ennemie simple : l'infanterie avance en ligne, les archers tirent et reculent,
## la cavalerie contourne pour frapper les archers ou prendre de flanc.
## Elle utilise aussi les formations (colonne pour marcher, carré contre la cavalerie) et la course.

var timer := 0.0
var advance := false
const LINE_SLACK := 120.0 ## Avance maximale d'un régiment d'infanterie sur le reste de la ligne
const COLUMN_DIST := 700.0 ## En deçà, l'infanterie en colonne se déploie en ligne
const COLUMN_HYSTERESIS := 150.0 ## Il faut être à COLUMN_DIST + ça pour repasser en colonne (pas d'oscillation)
const SQUARE_DIST := 400.0 ## Une cavalerie qui charge plus près que ça : les piquiers forment le carré
const REDEPLOY_DIST := 1200.0 ## Un régiment déjà déployé ne repasse en colonne qu'au-delà
const CAVALRY_WAIT := 20.0 ## La cavalerie reste en réserve ce délai (en s) avant de contourner
const RUSH_DIST := 220.0 ## Les hommes d'armes courent sur les derniers mètres
const CHARGE_RUN_DIST := 800.0 ## La cavalerie ne galope que sur la fin de la charge

var line_depth := 0.0
var charged := {} ## id de cavalerie → cible déjà chargée au galop (une seule course par cible)
var melee_started := false ## La cavalerie peut quitter la réserve
var deployed := {} ## id de régiment → true une fois passé en ligne près de l'ennemi
var team := 1 ## Camp contrôlé (1 = ennemi ; 0 sert aux tests « IA contre IA »)

## Réglages de difficulté (voir difficulty.gd ; valeurs du mode normal par défaut)
var think_every := 0.8 ## Intervalle entre deux réflexions, en secondes
var advance_time := 12.0 ## Délai avant de marcher sur l'ennemi
var cavalry_wait := CAVALRY_WAIT ## Délai avant que la cavalerie ne quitte la réserve
var use_square := true ## Les piquiers forment le carré contre une charge


## Applique un niveau de difficulté (« easy », « normal », « hard »).
func configure(difficulty: String) -> void:
	think_every = Difficulty.value(difficulty, "ai_think")
	advance_time = Difficulty.value(difficulty, "ai_advance")
	cavalry_wait = Difficulty.value(difficulty, "ai_cavalry_wait")
	use_square = bool(Difficulty.level(difficulty)["ai_square"])


## Une réflexion (au plus toutes les think_every secondes). b : la simulation de la bataille.
func think(b: BattleSim, dt: float) -> void:
	timer -= dt
	if timer > 0.0:
		return
	timer = think_every

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
		if b.battle_time > advance_time:
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
	if b.battle_time > cavalry_wait:
		melee_started = true

	for r in mine:
		match r.type:
			"archer", "crossbow": # Les arbalétriers tirent comme des archers
				think_archer(b, r, mine, theirs)
			"cavalry":
				think_cavalry(r, theirs)
			"horse_archer":
				think_horse_archer(r, mine, theirs)
			_:
				think_infantry(r, theirs)


## Distance parcourue vers le camp adverse (l'ennemi descend, le joueur monte).
func advance_depth(p: Vector2) -> float:
	return p.y if team == 1 else -p.y


func think_archer(b: BattleSim, r: Regiment, mine: Array[Regiment], theirs: Array[Regiment]) -> void:
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
		# Repli vers l'infanterie amie (s'il n'y en a plus, ou si on est acculé au bord, on tient)
		var cover: Regiment = null
		for o in mine:
			if not o.stats["ranged"] and o.type != "cavalry" and (cover == null or r.center.distance_to(o.center) < r.center.distance_to(cover.center)):
				cover = o
		var away := (r.center - threat.center).normalized()
		if cover != null:
			away = (away + (cover.center - r.center).normalized()).normalized()
		var to := (r.center + away * 140.0).clamp(Vector2(40, 40), Vector2(3160, 1960))
		if cover != null and to.distance_to(r.center) > 70.0:
			r.target = null
			r.holding = false
			r.running = r.stamina > 0.3 # Repli au pas de course
			r.dest = to
			r.facing = -away
			return
		r.target = threat # Plus d'abri : tir à bout portant
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
	if not melee_started:
		# En réserve derrière la ligne, sauf si une cavalerie ennemie vient la chercher
		var raider := nearest_of_type(r, theirs, "cavalry")
		if raider != null and r.center.distance_to(raider.center) < 300.0:
			r.target = raider
		return
	if r.target != null and not r.target.is_dead() and not r.target.routing:
		try_charge(r)
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
	r.flank_time += think_every
	if r.center.distance_to(flank_pt) > 90.0 and r.flank_time < 9.0:
		r.dest = flank_pt.clamp(Vector2(40, 40), Vector2(3160, 1960))
		r.facing = (prey.center - flank_pt).normalized()
	else:
		r.flank_time = 0.0
		r.target = prey
		try_charge(r)


## Archers montés : harcèlent l'infanterie (la simulation les fait décrocher seuls devant la mêlée)
## et se replient derrière leur ligne quand une cavalerie ennemie les menace.
func think_horse_archer(r: Regiment, mine: Array[Regiment], theirs: Array[Regiment]) -> void:
	if not advance:
		return
	var raider := nearest_of_type(r, theirs, "cavalry")
	if raider != null and r.center.distance_to(raider.center) < 360.0:
		var home := r.center
		for o in mine:
			if not o.stats["mounted"] and not o.stats["ranged"]:
				home = o.center - Vector2(0, 160.0 if team == 1 else -160.0)
				break
		r.target = null
		r.holding = false
		r.dest = home.clamp(Vector2(40, 40), Vector2(3160, 1960))
		return
	if r.target != null and not r.target.is_dead() and not r.target.routing and not r.target.hidden:
		return
	# Proie : l'infanterie à pied la plus proche (lente, elle ne peut pas les rattraper)
	var prey: Regiment = null
	for o in theirs:
		if o.stats["mounted"]:
			continue
		if prey == null or r.center.distance_to(o.center) < r.center.distance_to(prey.center):
			prey = o
	r.target = prey if prey != null else nearest(r, theirs)


## Charge au galop sur les derniers mètres, une seule fois par cible (pour ne pas épuiser les chevaux).
func try_charge(r: Regiment) -> void:
	if r.engaged or r.running or r.stamina <= 0.5 or charged.get(r.id) == r.target:
		return
	if r.center.distance_to(r.target.center) < CHARGE_RUN_DIST:
		r.running = true
		charged[r.id] = r.target


func think_infantry(r: Regiment, theirs: Array[Regiment]) -> void:
	var near := nearest(r, theirs)
	var d := r.center.distance_to(near.center)
	# Piquiers chargés par de la cavalerie : carré, on l'attend sur place
	if r.type == "spear" and not r.engaged and use_square:
		var charger: Regiment = null
		for o in theirs:
			if o.type != "cavalry":
				continue
			var cd := r.center.distance_to(o.center)
			if o.target == r and cd < SQUARE_DIST:
				charger = o
		if charger != null:
			if r.formation != Regiment.Formation.SQUARE:
				r.formation = Regiment.Formation.SQUARE
				r.target = null
				r.dest = r.center
			return
	# Colonne pour marcher de loin, ligne pour combattre
	# (hystérésis : on ne repasse en colonne que nettement plus loin, pour ne pas osciller)
	if not r.engaged:
		var column_dist := REDEPLOY_DIST if deployed.has(r.id) else COLUMN_DIST + COLUMN_HYSTERESIS
		if r.target != null or d < COLUMN_DIST:
			r.formation = Regiment.Formation.LINE
			deployed[r.id] = true
		elif d > column_dist and r.formation == Regiment.Formation.LINE and not r.holding:
			r.formation = Regiment.Formation.COLUMN
		elif r.formation == Regiment.Formation.SQUARE:
			r.formation = Regiment.Formation.LINE
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
