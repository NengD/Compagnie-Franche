class_name EnemyAI
extends RefCounted
## IA ennemie. Au début de la bataille, elle choisit un plan d'après les forces en présence et le terrain :
##  - « agressif » : l'infanterie avance en ligne, les archers tirent (depuis une colline s'il y en a une
##    de leur côté), la cavalerie contourne pour frapper les archers ou prendre de flanc ;
##  - « défensif » : l'armée tient une position (colline, lisière du village, rive de la rivière, palissade
##    ou sa ligne de départ), attend l'assaut, puis contre-attaque quand l'ennemi est engagé ou affaibli ;
##  - « débordement » : l'infanterie fixe l'ennemi pendant que la cavalerie part tôt et large,
##    ou se cache dans un bois pour une embuscade.
## Dans tous les plans : formations (colonne pour marcher, ligne pour combattre, carré contre la cavalerie),
## course, passage par les gués, et retraite en bon ordre quand la bataille est perdue.
##
## Objectif de contrat (battle_objectives.gd) : il peut imposer le plan (agressif pour prendre une position
## ou attaquer un convoi, défensif pour garder un village, « fuite » pour une bande poursuivie), un point
## à gagner (ai_point) et un poste à défendre (ai_anchor). Voir la section « Objectifs ».
##
## Ajouter un type d'unité : une branche dans think_regiment() qui appelle sa propre fonction ; à défaut,
## le type est joué d'après ses capacités (« ranged » → archers, « mounted » → cavalerie, sinon infanterie).

const AGGRESSIVE := "aggressive"
const DEFENSIVE := "defensive"
const FLANK := "flank"
const PLANS: Array[String] = [AGGRESSIVE, DEFENSIVE, FLANK]
const PLAN_NAMES := {AGGRESSIVE: "agressif", DEFENSIVE: "défensif", FLANK: "débordement", "flee": "fuite"}
const FLEE := "flee" ## Plan imposé par l'objectif « poursuivre » : la bande fuit vers son bord du champ
const REAR_GUARD_TIME := 40.0 ## Fuite : l'arrière-garde tient ce délai avant de suivre la bande
const TURN_AT_BAY := 90.0 ## Fuite : un fantassin rattrapé à cette distance fait face et se bat

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

## Défense
const MUCH_WEAKER := 0.65 ## Rapport de forces sous lequel l'IA se met toujours en défense
const DEFEND_PATIENCE := 95.0 ## Sans assaut, l'armée en défense finit par attaquer
const COUNTER_CONTACT := 8.0 ## Secondes de mêlée avant la contre-attaque générale
const COUNTER_GAIN := 1.3 ## Contre-attaque aussi quand le rapport de forces s'est amélioré d'autant
const BLED := 0.8 ## ... ou quand les flèches ont coûté ce qu'il reste de la force de départ, sans mêlée
const LEASH := 380.0 ## Distance maximale de poursuite autour d'un poste défensif
const POST_CHARGE := 260.0 ## Contre-charge locale : un ennemi à cette distance d'un régiment posté
const HILL_REACH := 900.0 ## Une colline plus loin que ça de l'armée n'est pas occupée
## Débordement
const PIN_DIST := 480.0 ## L'infanterie qui fixe l'ennemi s'arrête à cette distance...
const PIN_TIME := 35.0 ## ... jusqu'à la charge de flanc, ou ce délai après le début de l'avance
const AMBUSH_RANGE := 300.0 ## La cavalerie embusquée charge une proie à cette distance
const AMBUSH_MAX_WAIT := 110.0 ## Délai au-delà duquel elle sort quand même du bois
## Retraite
const WITHDRAW_LEFT := 0.4 ## Retraite quand il reste moins de cette part de la force de départ...
const WITHDRAW_RATIO := 0.6 ## ... et que le rapport de forces est tombé sous ce seuil
const EXIT_MARGIN := 110.0 ## Un régiment en retraite quitte le champ à cette distance de son bord

var line_depth := 0.0
var charged := {} ## id de cavalerie → cible déjà chargée au galop (une seule course par cible)
var melee_started := false ## La cavalerie peut quitter la réserve
var deployed := {} ## id de régiment → true une fois passé en ligne près de l'ennemi
var team := 1 ## Camp contrôlé (1 = ennemi ; 0 sert aux tests « IA contre IA »)

## Plan de bataille
var plan := "" ## Choisi à la première réflexion (voir choose_plan)
var plan_override := "" ## Plan imposé (tests)
var counter := false ## Défense : la contre-attaque est lancée
var withdrawing := false ## Retraite en bon ordre en cours
var contact_time := 0.0 ## Secondes de mêlée cumulées
var start_power: Array[float] = [0.0, 0.0] ## Force de départ : la nôtre, celle de l'ennemi
var anchor := Vector2.INF ## Position défendue (Vector2.INF : aucune)
var anchor_kind := "" ## « hill », « village », « bank », « wall » ou « line »
var hill := Vector2.INF ## Colline occupée (sommet), s'il y en a une de notre côté
var posts := {} ## id de régiment → poste à tenir (défense, ou colline des archers)
var post_facing := Vector2.DOWN ## Front des postes (vers l'ennemi)
var post_idle := {} ## id d'archers → secondes passées au poste sans cible
var ambush := {} ## id de cavalerie → centre du bois où elle s'embusque
var left_field := 0 ## Régiments sortis du champ en bon ordre

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
	var theirs: Array[Regiment] = [] ## Ennemis visibles
	var all_theirs: Array[Regiment] = [] ## Y compris ceux qui sont cachés (pour le rapport de forces)
	for r in b.regiments:
		if r.is_dead() or r.routing:
			continue
		if r.team == team:
			mine.append(r)
		else:
			all_theirs.append(r)
			if not r.hidden:
				theirs.append(r)
	if mine.is_empty() or theirs.is_empty():
		return
	if plan == "":
		choose_plan(b, mine, all_theirs)

	if plan == FLEE:
		for r in mine:
			flee(b, r, theirs)
		return

	var p_mine := power(mine)
	var p_theirs := power(all_theirs)
	if not withdrawing and p_mine < start_power[0] * WITHDRAW_LEFT and p_mine < p_theirs * WITHDRAW_RATIO:
		withdrawing = true
		advance = false
		b.message("L'ennemi sonne la retraite et décroche en bon ordre !" if team == 1 else "Votre compagnie sonne la retraite.")
	if withdrawing:
		for r in mine:
			withdraw(b, r, theirs)
		return

	update_posture(b, mine, theirs, p_mine, p_theirs)

	# Front de l'infanterie : chaque régiment règle son pas sur la moyenne pour avancer en ligne
	var sum := 0.0
	var n := 0
	for r in mine:
		if is_foot(r):
			sum += advance_depth(r.center)
			n += 1
	line_depth = sum / n if n > 0 else 0.0

	for r in mine:
		think_regiment(b, r, mine, theirs)


## Aiguillage par type. Un nouveau type ajoute ici sa branche (et sa fonction think_xxx).
func think_regiment(b: BattleSim, r: Regiment, mine: Array[Regiment], theirs: Array[Regiment]) -> void:
	if b.siege != null and think_siege(b, r, theirs):
		return
	match r.type:
		"archer", "crossbow": # Les arbalétriers tirent comme des archers
			think_archer(b, r, mine, theirs)
		"cavalry":
			think_cavalry(b, r, theirs)
		"horse_archer":
			think_horse_archer(r, mine, theirs)
		"spear", "men_at_arms":
			think_infantry(b, r, theirs)
		_:
			# Type sans fonction dédiée : joué d'après ses capacités
			if r.stats["ranged"]:
				think_archer(b, r, mine, theirs)
			elif r.stats["mounted"]:
				think_cavalry(b, r, theirs)
			else:
				think_infantry(b, r, theirs)


## Distance parcourue vers le camp adverse (l'ennemi descend, le joueur monte).
func advance_depth(p: Vector2) -> float:
	return p.y if team == 1 else -p.y


## Infanterie de ligne : ni tireurs ni montés.
static func is_foot(r: Regiment) -> bool:
	return not r.stats["ranged"] and not r.stats["mounted"]


# ---------------------------------------------------------------- Plan de bataille

## Valeur de combat d'une liste de régiments (effectif × solidité × dégâts, cavalerie majorée).
static func power(list: Array[Regiment]) -> float:
	var p := 0.0
	for r in list:
		var st: Dictionary = r.stats
		var dps := float(st["damage"]) / float(st["cooldown"])
		if st["ranged"]:
			dps += float(st["ranged_damage"]) / float(st["reload"])
		var v := sqrt(float(st["hp"]) * dps)
		if st["mounted"]:
			v *= 1.3
		p += v * r.alive_n * r.rank_damage()
	return p


## Nombre d'hommes montés (hors tireurs) dans une liste de régiments.
static func mounted_count(list: Array[Regiment]) -> int:
	var n := 0
	for r in list:
		if r.stats["mounted"] and not r.stats["ranged"]:
			n += r.alive_n
	return n


static func centroid(list: Array[Regiment]) -> Vector2:
	var c := Vector2.ZERO
	for r in list:
		c += r.center
	return c / maxf(list.size(), 1)


## Choisit le plan (une fois par bataille) et prépare les postes, la colline et l'embuscade.
## Le tirage dépend de la graine de la bataille : même graine, même plan.
func choose_plan(b: BattleSim, mine: Array[Regiment], theirs: Array[Regiment]) -> void:
	start_power = [power(mine), power(theirs)]
	var my_c := centroid(mine)
	var their_c := centroid(theirs)
	post_facing = (their_c - my_c).normalized()
	hill = find_hill(b, my_c, their_c)
	var forest := find_ambush_forest(b, my_c, their_c)
	var attacker := b.terrain.kind == "siege" and team == 1 ## L'assaillant d'une palissade ne peut pas attendre

	# Le débordement ne vaut que s'il y a un bois où s'embusquer, ou plus de cavaliers que l'ennemi
	var w := {AGGRESSIVE: 1.0, DEFENSIVE: 1.0, FLANK: 0.3}
	if mounted_count(mine) > mounted_count(theirs):
		w[FLANK] += 1.2
	var ratio: float = start_power[0] / maxf(start_power[1], 1.0)
	if ratio < 0.8:
		w[DEFENSIVE] += 3.0
	elif ratio < 0.95:
		w[DEFENSIVE] += 1.0
	elif ratio > 1.25:
		w[AGGRESSIVE] += 3.0
	elif ratio > 1.05:
		w[AGGRESSIVE] += 1.0
	if hill.is_finite():
		w[DEFENSIVE] += 1.5
	if forest.is_finite():
		w[FLANK] += 1.5
	match b.terrain.kind:
		"village":
			w[DEFENSIVE] += 1.0
		"river":
			w[DEFENSIVE] += 0.5
			w[FLANK] += 0.5
		"siege":
			if attacker:
				w[DEFENSIVE] = 0.0
				w[FLANK] = 0.0 # Pas de contournement : la palissade ne s'ouvre qu'aux brèches
			else:
				w[DEFENSIVE] += 3.0
	if objective_plan(b) != "":
		plan = objective_plan(b) # Imposé par l'objectif du contrat
	elif plan_override in PLANS:
		plan = plan_override
	elif ratio < MUCH_WEAKER and not attacker:
		plan = DEFENSIVE # Bien trop faible pour attaquer : on attend l'ennemi sur la meilleure position
	else:
		var prng := RandomNumberGenerator.new()
		prng.seed = hash([b.rng.seed, "plan"])
		var total := 0.0
		for k in PLANS:
			total += float(w[k])
		var roll := prng.randf() * total
		plan = PLANS[-1]
		for k in PLANS:
			roll -= float(w[k])
			if roll < 0.0:
				plan = k
				break
	if b.siege != null:
		plan = AGGRESSIVE if b.siege.attacker == team else DEFENSIVE # Vrai siège : voir think_siege

	posts.clear()
	if plan == FLEE:
		choose_rear_guard(mine, their_c)
		return
	if plan == DEFENSIVE:
		setup_defense(b, mine, my_c)
	elif hill.is_finite():
		# Les archers tirent depuis la colline (portée accrue), l'infanterie avance devant eux
		var archers: Array[Regiment] = []
		for r in mine:
			if r.stats["ranged"]:
				archers.append(r)
		place_row(archers, hill, 150.0)
	if forest.is_finite() and (plan == FLANK or (plan == DEFENSIVE and forest.distance_to(anchor) < 900.0)):
		for r in mine:
			if r.stats["mounted"] and not r.stats["ranged"]:
				ambush[r.id] = forest
				break # Une seule embuscade par bataille


## Sommet de colline à occuper : de notre côté du champ et pas trop loin (Vector2.INF : aucun).
func find_hill(b: BattleSim, my_c: Vector2, their_c: Vector2) -> Vector2:
	var best := Vector2.INF
	var bs := -INF
	for top in b.terrain.hill_tops():
		var dm := top.distance_to(my_c)
		if dm > HILL_REACH or dm > top.distance_to(their_c) or b.terrain.crosses_river(top, my_c):
			continue
		var s := b.terrain.height(top) * 600.0 - dm
		if s > bs:
			bs = s
			best = top
	return best


## Bois où cacher la cavalerie : sur un flanc de l'ennemi, assez près pour frapper (Vector2.INF : aucun).
func find_ambush_forest(b: BattleSim, my_c: Vector2, their_c: Vector2) -> Vector2:
	var best := Vector2.INF
	var bd := INF
	for f in b.forests:
		var c: Vector2 = f[0]
		var rad: float = f[1]
		var dt := c.distance_to(their_c)
		if rad < 110.0 or dt < 350.0 or dt > 1000.0 or c.distance_to(my_c) > 1400.0:
			continue
		if absf(c.x - their_c.x) < 250.0 or b.terrain.crosses_river(c, my_c):
			continue
		if dt < bd:
			bd = dt
			best = c
	return best


## Postes de défense : la colline, la lisière du village, la rive, la palissade ou la ligne de départ.
func setup_defense(b: BattleSim, mine: Array[Regiment], my_c: Vector2) -> void:
	var t := b.terrain
	var face := post_facing
	var foot: Array[Regiment] = []
	var archers: Array[Regiment] = []
	var horse: Array[Regiment] = []
	for r in mine:
		if r.stats["ranged"]:
			archers.append(r)
		elif r.stats["mounted"]:
			horse.append(r)
		else:
			foot.append(r)
	var foot_at := my_c + face * 120.0
	var archers_at := my_c - face * 10.0
	anchor_kind = "line"
	if t.kind == "siege" or b.siege != null:
		# Derrière la palissade (ou sur le rempart) : chacun garde la place de son déploiement
		anchor_kind = "wall"
		anchor = my_c
		for r in mine:
			posts[r.id] = r.dest
		return
	var held := objective_anchor(b)
	if held.is_finite():
		anchor_kind = "objective" # Garder la place de l'objectif (le village à prendre)
		foot_at = held + face * 70.0
		archers_at = held - face * 50.0
	elif hill.is_finite():
		anchor_kind = "hill"
		foot_at = hill + face * 110.0
		archers_at = hill - face * 15.0
	elif t.kind == "village" and t.village_rect.has_area():
		anchor_kind = "village"
		var rect := t.village_rect
		var edge_y := rect.position.y - 50.0 if face.y > 0.0 else rect.end.y + 50.0
		foot_at = Vector2(rect.get_center().x, edge_y)
		archers_at = foot_at - face * 120.0
	elif t.has_river():
		anchor_kind = "bank"
		foot_at = Vector2(my_c.x, 0.0) # Hauteur fixée régiment par régiment, le long de la rive
		archers_at = foot_at
	anchor = foot_at
	place_row(foot, foot_at, 150.0)
	place_row(archers, archers_at, 170.0)
	if anchor_kind == "bank":
		var side := t.river_side(my_c)
		for r in foot:
			var p: Vector2 = posts[r.id]
			posts[r.id] = Vector2(p.x, b.road_y(p.x) + side * 160.0)
		for r in archers:
			var p: Vector2 = posts[r.id]
			posts[r.id] = Vector2(p.x, b.road_y(p.x) + side * 280.0)
		anchor = Vector2(my_c.x, b.road_y(my_c.x) + side * 160.0)
	# Cavalerie en réserve derrière les ailes
	var right := Vector2(-face.y, face.x)
	var half := maxf(foot.size(), 2) * 75.0 + 120.0
	for k in horse.size():
		var s := -1.0 if k % 2 == 0 else 1.0
		posts[horse[k].id] = clamp_world(anchor - face * 170.0 + right * s * half)


## Range des régiments côte à côte (triés de gauche à droite) autour de at.
func place_row(list: Array[Regiment], at: Vector2, gap: float) -> void:
	var right := Vector2(-post_facing.y, post_facing.x)
	var sorted := list.duplicate()
	sorted.sort_custom(func(a: Regiment, c: Regiment) -> bool: return a.center.dot(right) < c.center.dot(right))
	for k in sorted.size():
		posts[sorted[k].id] = clamp_world(at + right * (k - (sorted.size() - 1) * 0.5) * gap)


static func clamp_world(p: Vector2) -> Vector2:
	return p.clamp(Vector2(60, 60), BattleSim.WORLD_SIZE - Vector2(60, 60))


## Défense : contre-attaque générale quand l'ennemi s'est engagé, s'est affaibli, ou se fait attendre.
## Sinon (autres plans) : marche sur l'ennemi après un délai ou à son approche.
func update_posture(b: BattleSim, mine: Array[Regiment], theirs: Array[Regiment], p_mine: float, p_theirs: float) -> void:
	for r in mine:
		if r.engaged:
			contact_time += think_every
			break
	if plan == DEFENSIVE and not counter:
		var gain := (p_mine / maxf(p_theirs, 1.0)) / maxf(start_power[0] / maxf(start_power[1], 1.0), 0.01)
		var bled := contact_time <= 0.0 and p_mine < start_power[0] * BLED
		var may := objective_counterattacks(b) # Une garnison ne quitte sa place que saignée par les flèches
		if bled or (may and (contact_time > COUNTER_CONTACT or gain > COUNTER_GAIN or b.battle_time > DEFEND_PATIENCE)):
			counter = true
			advance = true
			melee_started = true
		return
	if not advance:
		if b.battle_time > advance_time:
			advance = true
		for r in mine:
			if r.center.distance_to(nearest(r, theirs).center) < 520.0:
				advance = true
	var wait := cavalry_wait * (0.4 if plan == FLANK else 1.0)
	if b.battle_time > wait:
		melee_started = true


## Vrai tant que l'armée tient ses postes de défense.
func holding_posts() -> bool:
	return plan == DEFENSIVE and not counter and not withdrawing


## Prochain point vers goal (par un gué si la rivière les sépare).
func go_to(b: BattleSim, from: Vector2, goal: Vector2) -> Vector2:
	return b.terrain.ford_waypoint(from, goal)


## Vrai si rejoindre o obligerait à patauger loin d'un gué (on préfère alors le détour).
func must_wade(b: BattleSim, r: Regiment, o: Regiment) -> bool:
	return b.terrain.crosses_river(r.center, o.center) and r.center.distance_to(o.center) > 200.0


# ---------------------------------------------------------------- Archers

func think_archer(b: BattleSim, r: Regiment, mine: Array[Regiment], theirs: Array[Regiment]) -> void:
	var range_px: float = r.stats["range"] * b.terrain.range_factor(r.center)
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
			if is_foot(o) and (cover == null or r.center.distance_to(o.center) < r.center.distance_to(cover.center)):
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
	if posts.has(r.id) and keeps_post(r):
		hold_archer_post(r, theirs, range_px)
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


## Les archers quittent leur poste (colline) une fois la défense levée et sans cible depuis un moment.
func keeps_post(r: Regiment) -> bool:
	if holding_posts():
		return true
	if float(post_idle.get(r.id, 0.0)) > 12.0 and (advance or counter):
		posts.erase(r.id)
		return false
	return true


## Tir depuis le poste : seulement sur ce qui est à portée, sans aller au-devant.
func hold_archer_post(r: Regiment, theirs: Array[Regiment], range_px: float) -> void:
	var post: Vector2 = posts[r.id]
	if r.target != null and not r.target.is_dead() and not r.target.hidden \
			and r.center.distance_to(r.target.center) <= range_px * 1.02:
		post_idle[r.id] = 0.0
		return
	var best: Regiment = null
	var bd := range_px
	for o in theirs:
		var d := r.center.distance_to(o.center)
		if not o.engaged and d < bd:
			bd = d
			best = o
	if best != null:
		r.target = best
		post_idle[r.id] = 0.0
		return
	r.target = null
	r.holding = false
	post_idle[r.id] = float(post_idle.get(r.id, 0.0)) + think_every
	if r.center.distance_to(post) > 20.0:
		r.running = false
		r.dest = post
		r.facing = post_facing


# ---------------------------------------------------------------- Cavalerie

func think_cavalry(b: BattleSim, r: Regiment, theirs: Array[Regiment]) -> void:
	if ambush.has(r.id) and lie_in_ambush(b, r, theirs):
		return
	if advance and seek_objective(b, r, theirs):
		return # Raid sur le convoi
	if holding_posts() or not advance:
		# En réserve (derrière la ligne ou à son poste), sauf si une cavalerie ennemie vient la chercher
		var raider := nearest_of_type(r, theirs, "cavalry")
		if raider != null and r.center.distance_to(raider.center) < 300.0:
			r.target = raider
		elif posts.has(r.id) and r.target == null:
			r.dest = go_to(b, r.center, posts[r.id])
			r.facing = post_facing
		return
	if not melee_started:
		var raider := nearest_of_type(r, theirs, "cavalry")
		if raider != null and r.center.distance_to(raider.center) < 300.0:
			r.target = raider
		return
	if r.target != null and not r.target.is_dead() and not r.target.routing:
		if must_wade(b, r, r.target):
			var t := r.target
			r.target = null
			r.dest = go_to(b, r.center, t.center)
			return
		try_charge(r)
		return
	# Proies préférées : archers, puis tout sauf les piquiers
	var prey: Regiment = nearest_of_type(r, theirs, "archer")
	if prey == null:
		for o in theirs:
			if not o.stats["braces"] and (prey == null or r.center.distance_to(o.center) < r.center.distance_to(prey.center)):
				prey = o
	if prey == null:
		prey = nearest(r, theirs)
	# Contournement : viser l'arrière de la cible avant de charger (plus large en débordement)
	var wide := 1.6 if plan == FLANK else 1.0
	var side := Vector2(-prey.facing.y, prey.facing.x)
	if (r.center - prey.center).dot(side) < 0.0:
		side = -side
	var flank_pt: Vector2 = prey.center - prey.facing * 140.0 * wide + side * 120.0 * wide
	r.flank_time += think_every
	if (r.center.distance_to(flank_pt) > 90.0 and r.flank_time < 9.0 * wide) or b.terrain.crosses_river(r.center, prey.center):
		r.dest = go_to(b, r.center, clamp_world(flank_pt))
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


## Embuscade : la cavalerie gagne le bois et y attend qu'une proie passe à portée.
## Renvoie faux une fois l'embuscade déclenchée (ou abandonnée) : la cavalerie reprend son rôle habituel.
func lie_in_ambush(b: BattleSim, r: Regiment, theirs: Array[Regiment]) -> bool:
	var wood: Vector2 = ambush[r.id]
	var prey: Regiment = null
	var pd := AMBUSH_RANGE
	for o in theirs:
		var d := r.center.distance_to(o.center)
		if o.stats["braces"] and o.formation == Regiment.Formation.LINE and not o.engaged:
			d += 120.0 # Des piques en ligne : proie de dernier recours
		if d < pd:
			pd = d
			prey = o
	var late := b.battle_time > AMBUSH_MAX_WAIT or (counter and contact_time > 20.0)
	if prey != null or late or r.engaged:
		ambush.erase(r.id)
		if prey != null:
			r.target = prey
			melee_started = true
			try_charge(r)
			return true
		return false
	if r.center.distance_to(wood) > 30.0:
		r.dest = go_to(b, r.center, wood)
		r.facing = post_facing
	r.target = null
	return true


## Charge au galop sur les derniers mètres, une seule fois par cible (pour ne pas épuiser les chevaux).
func try_charge(r: Regiment) -> void:
	if r.engaged or r.running or r.stamina <= 0.5 or charged.get(r.id) == r.target:
		return
	if r.center.distance_to(r.target.center) < CHARGE_RUN_DIST:
		r.running = true
		charged[r.id] = r.target


# ---------------------------------------------------------------- Infanterie

func think_infantry(b: BattleSim, r: Regiment, theirs: Array[Regiment]) -> void:
	var near := nearest(r, theirs)
	var d := r.center.distance_to(near.center)
	# Piquiers chargés par de la cavalerie : carré, on l'attend sur place
	if r.stats["braces"] and not r.engaged and use_square:
		var charger: Regiment = null
		for o in theirs:
			if not o.stats["mounted"]:
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
	if posts.has(r.id) and holding_posts():
		defend_post(b, r, near, d)
		return
	if r.target != null and not r.target.is_dead() and not r.target.hidden:
		if must_wade(b, r, r.target):
			r.target = null # Trop loin de l'autre côté de l'eau : on passe par le gué
		else:
			if r.type == "men_at_arms" and not r.engaged and r.center.distance_to(r.target.center) < RUSH_DIST and r.stamina > 0.6:
				r.running = true
			return
	if r.stats["braces"]:
		var cav := nearest_of_type(r, theirs, "cavalry")
		if cav != null and r.center.distance_to(cav.center) < 300.0 and not must_wade(b, r, cav):
			r.target = cav
			return
	if advance and seek_objective(b, r, theirs):
		return # Marche sur la position, ou sur le convoi
	if d < 340.0 and not must_wade(b, r, near):
		r.target = near
	elif advance:
		var wp := go_to(b, r.center, near.center)
		if wp != near.center:
			# Traversée par un gué : en colonne, étroite comme le passage
			r.formation = Regiment.Formation.COLUMN
			r.dest = wp
			r.facing = (wp - r.center).normalized()
			return
		var dir := (near.center - r.center).normalized()
		r.facing = dir
		if pins(b) and d < PIN_DIST and not melee_started_flank(b):
			r.dest = r.center # Fixe l'ennemi (charge de flanc, ou flèches sur la palissade) avant l'assaut
		elif advance_depth(r.center) > line_depth + LINE_SLACK:
			r.dest = r.center # Trop en avance : attend que la ligne le rejoigne
		else:
			r.dest = r.center + dir * 160.0


## L'infanterie s'arrête-t-elle à PIN_DIST avant l'assaut ? En débordement (elle attend la charge de flanc)
## et à l'assaut d'une palissade (les archers tirent d'abord sur les défenseurs).
func pins(b: BattleSim) -> bool:
	return plan == FLANK or (b.terrain.kind == "siege" and team == 1)


## L'infanterie repart à l'assaut quand la cavalerie a chargé, au premier contact, ou après PIN_TIME.
func melee_started_flank(b: BattleSim) -> bool:
	if b.battle_time > advance_time + PIN_TIME or contact_time > 0.0:
		return true
	for r in b.regiments:
		if r.team == team and r.stats["mounted"] and r.engaged:
			return true
	return false


## Tient son poste : contre-charge ce qui s'approche, sans poursuivre au-delà de LEASH.
func defend_post(b: BattleSim, r: Regiment, near: Regiment, d: float) -> void:
	var post: Vector2 = posts[r.id]
	if r.target != null and not r.target.is_dead() and not r.target.hidden:
		if not r.engaged and r.target.center.distance_to(post) > LEASH:
			r.target = null
		else:
			if r.type == "men_at_arms" and not r.engaged and r.center.distance_to(r.target.center) < RUSH_DIST and r.stamina > 0.6:
				r.running = true
			return
	if d < POST_CHARGE and near.center.distance_to(post) < LEASH and not must_wade(b, r, near):
		r.target = near
		return
	if r.center.distance_to(post) < 60.0 and r.formation == Regiment.Formation.COLUMN:
		r.formation = Regiment.Formation.LINE # Arrivé au poste : on se déploie face à l'ennemi
		deployed[r.id] = true
	r.dest = go_to(b, r.center, post)
	r.facing = post_facing


# ---------------------------------------------------------------- Siège (siege.gd)

## Vrai siège : la garnison tient ses postes sans sortir ; l'assaillant mène le bélier à la porte et
## les échelles au pied du rempart, attend une ouverture hors de portée des tours, puis marche sur
## la place. Renvoie faux pour laisser le régiment jouer comme d'habitude (tireurs de l'assaillant).
func think_siege(b: BattleSim, r: Regiment, theirs: Array[Regiment]) -> bool:
	if b.siege.attacker == team:
		return siege_attack(b, b.siege, r, theirs)
	return siege_defend(b, b.siege, r, theirs)


func siege_attack(b: BattleSim, sg: Siege, r: Regiment, theirs: Array[Regiment]) -> bool:
	if r.stats["ranged"]:
		return false
	var t := sg.town
	var inward := Vector2(0, -t.out_dir)
	match sg.role(r):
		"ram":
			r.target = null
			r.formation = Regiment.Formation.COLUMN
			r.dest = t.ram_spot() + Vector2(0, t.out_dir * 20.0)
			r.facing = inward
			return true
		"ladder":
			r.target = null
			r.dest = t.ladder_foot(sg.ladder_x(sg.ladder_of(r))) + Vector2(0, t.out_dir * 16.0)
			r.facing = inward
			return true
	var near := nearest(r, theirs)
	var nd := r.center.distance_to(near.center)
	var open: bool = sg.has_opening() and (t.gate_open or not r.stats["mounted"]) # Les chevaux attendent la porte
	if not open:
		r.target = null
		if not t.inside(near.center, SiegeTerrain.WALL_T) and nd < 250.0:
			r.target = near # Sortie de la garnison : on la reçoit
			return true
		var wait := Vector2(clampf(r.center.x, SiegeTerrain.X0 + 100.0, SiegeTerrain.X1 - 100.0), t.front_y + t.out_dir * Siege.STAGING)
		if sg.raised > 0 and not r.stats["mounted"]:
			# L'assaut est lancé : on attend au pied d'une échelle renversée qu'elle se redresse
			for l in sg.ladders:
				if l["state"] in ["down", "raising"]:
					wait = t.ladder_foot(float(l["x"])) + Vector2(0, t.out_dir * 60.0)
					break
		r.dest = wait
		r.facing = inward
		return true
	if r.target != null and not r.target.is_dead() and not r.target.routing and r.center.distance_to(r.target.center) < 400.0:
		return true
	if nd < 200.0 and not b.terrain.wall_blocks(r.center, near.center):
		r.target = near
		return true
	r.target = null
	r.dest = t.plaza # Par la porte ou les échelles (voir SiegeTerrain.route)
	r.facing = (t.plaza - r.center).normalized()
	return true


func siege_defend(b: BattleSim, sg: Siege, r: Regiment, theirs: Array[Regiment]) -> bool:
	var t := sg.town
	if not posts.has(r.id):
		posts[r.id] = r.dest
	var post: Vector2 = posts[r.id]
	var outward := Vector2(0, t.out_dir)
	r.hold_position = true # Ne sort pas des murs pour poursuivre
	if r.stats["ranged"] and not r.stats["mounted"]:
		var range_px: float = r.stats["range"] * b.terrain.range_factor(r.center)
		if r.target != null and not r.target.is_dead() and not r.target.hidden and r.center.distance_to(r.target.center) <= range_px:
			return true
		r.target = null
		var bd := range_px
		for o in theirs:
			var d := r.center.distance_to(o.center)
			if d < bd:
				bd = d
				r.target = o
		if r.target == null and r.center.distance_to(post) > 20.0:
			r.dest = post
			r.facing = outward
		return true
	# Ennemis entrés dans la ville : on les charge
	var threat: Regiment = null
	var td := 700.0
	for o in theirs:
		if not t.inside(o.center, 6.0) or o.center.distance_to(post) > 750.0:
			continue
		var d := r.center.distance_to(o.center)
		if d < td:
			td = d
			threat = o
	if threat != null:
		r.target = threat
		return true
	r.target = null
	if not r.stats["mounted"]:
		# Échelle dressée près du poste : on garde son débouché (et on la repousse)
		var best := -1.0
		var bd := 560.0
		for l in sg.ladders_up():
			var d := post.distance_to(t.ladder_top(float(l["x"])))
			if d < bd:
				bd = d
				best = float(l["x"])
		if best >= 0.0:
			r.dest = t.ladder_top(best) - outward * 6.0
			r.facing = outward
			return true
	if r.center.distance_to(post) > 24.0:
		r.dest = post
		r.facing = outward
	return true


# ---------------------------------------------------------------- Retraite

## Retraite en bon ordre : chacun recule vers son bord du champ, face à l'ennemi ; la cavalerie couvre
## l'infanterie en chargeant ceux qui la talonnent. Arrivé au bord, le régiment quitte le champ.
func withdraw(b: BattleSim, r: Regiment, theirs: Array[Regiment]) -> void:
	var edge_y := 0.0 if team == 1 else BattleSim.WORLD_SIZE.y
	if absf(r.center.y - edge_y) < EXIT_MARGIN:
		r.routing = true # Sortie du champ : ces hommes ne reviendront pas, mais ils sont saufs
		r.rallied_once = true
		r.morale = 0.0
		r.target = null
		r.fire_target = null
		r.running = false
		left_field += 1
		return
	var near := nearest(r, theirs)
	if r.stats["mounted"] and not r.stats["ranged"] and near != null and not near.stats["braces"] \
			and near.center.distance_to(r.center) < 260.0 and r.stamina > 0.3:
		r.target = near # Arrière-garde
		try_charge(r)
		return
	r.target = null
	r.running = false
	if r.formation == Regiment.Formation.SQUARE:
		r.formation = Regiment.Formation.LINE
	var wp := go_to(b, r.center, Vector2(r.center.x, edge_y))
	r.dest = r.center + (wp - r.center).limit_length(220.0)
	r.facing = post_facing


# ---------------------------------------------------------------- Objectifs

## Plan imposé par l'objectif de la bataille ("" : libre).
func objective_plan(b: BattleSim) -> String:
	return b.objective.ai_plan() if b.objective != null else ""


## Poste à défendre imposé par l'objectif (Vector2.INF : aucun).
func objective_anchor(b: BattleSim) -> Vector2:
	return b.objective.ai_anchor(b) if b.objective != null else Vector2.INF


## Faux si l'objectif veut que la défense garde sa place plutôt que de contre-attaquer.
func objective_counterattacks(b: BattleSim) -> bool:
	return b.objective == null or b.objective.ai_counterattacks()


## Gagne le point de l'objectif (position à prendre, chariot à piller) tant qu'aucun ennemi n'est
## plus près que ai_engage. Renvoie vrai si le régiment a reçu cet ordre.
func seek_objective(b: BattleSim, r: Regiment, theirs: Array[Regiment]) -> bool:
	if b.objective == null:
		return false
	var p := b.objective.ai_point(b, r)
	if not p.is_finite():
		return false
	if r.target != null and not r.target.is_dead() and not r.target.routing and not r.target.hidden:
		return false # Déjà au combat
	var near := nearest(r, theirs)
	if near != null and r.center.distance_to(near.center) < b.objective.ai_engage and not must_wade(b, r, near):
		return false # Un ennemi barre la route : on le combat
	var wp := go_to(b, r.center, p)
	r.dest = wp
	if wp.distance_to(r.center) > 1.0:
		r.facing = (wp - r.center).normalized()
	if r.stats["mounted"] and r.center.distance_to(p) < CHARGE_RUN_DIST and r.stamina > 0.5 and not r.engaged:
		r.running = true # La cavalerie fond sur le convoi
	return true


## Fuite (objectif « poursuivre ») : l'arrière-garde tient un moment, les autres marchent vers leur
## bord du champ en colonne ; un fantassin rattrapé fait face et se bat.
func choose_rear_guard(mine: Array[Regiment], their_c: Vector2) -> void:
	var best: Regiment = null
	for r in mine:
		if is_foot(r) and r.stats["braces"] and (best == null or r.center.distance_to(their_c) < best.center.distance_to(their_c)):
			best = r
	if best != null:
		posts[best.id] = best.center


func flee(b: BattleSim, r: Regiment, theirs: Array[Regiment]) -> void:
	var near := nearest(r, theirs)
	var d := r.center.distance_to(near.center) if near != null else INF
	if posts.has(r.id) and b.battle_time < REAR_GUARD_TIME:
		# Arrière-garde : piques plantées face aux poursuivants
		r.formation = Regiment.Formation.LINE
		if d < POST_CHARGE and near != null:
			r.target = near
		else:
			r.target = null
			r.dest = posts[r.id]
			r.facing = (near.center - r.center).normalized() if near != null else -post_facing
		return
	if is_foot(r) and d < TURN_AT_BAY:
		r.formation = Regiment.Formation.LINE
		r.target = near # Rattrapé : on fait face
		return
	if r.engaged and not r.stats["mounted"]:
		return # Au contact : on ne tourne pas le dos
	r.target = null
	r.running = false
	if is_foot(r):
		r.formation = Regiment.Formation.COLUMN
	var edge_y := -200.0 if team == 1 else BattleSim.WORLD_SIZE.y + 200.0
	var wp := go_to(b, r.center, Vector2(r.center.x, edge_y))
	r.dest = r.center + (wp - r.center).limit_length(240.0)
	r.facing = (r.dest - r.center).normalized()


# ---------------------------------------------------------------- Outils


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
