class_name EnemyCommander
extends RefCounted
## Chef de l'armée ennemie : une figurine distincte (cavalier, grand étendard) au milieu d'un
## régiment de garde. Présent dans les contrats de niveau 2 et plus et la bataille décisive
## (ni en escarmouche, ni au tutoriel, ni dans une embuscade de la route).
##
## - Sa garde est plus solide (moral, vie et coups renforcés) ; lui se tient derrière elle et
##   recule quand des ennemis approchent (THREAT_RADIUS).
## - Les soldats du joueur au contact le frappent, les flèches qui tombent près de lui aussi.
## - S'il tombe : toute l'armée ennemie perd DEATH_MORALE de moral, message et cris.
## - Campagne : battle.gd note le résultat dans le contrat (note_result) ; CampaignState.finish_battle
##   appelle campaign_reward, qui paie la tête du chef (prime et renommée) et l'écrit au bilan.
## Non sauvegardé : il n'existe que le temps de la bataille (BattleSim.commander).

const NAMES := ["Gaucher de Brienne", "Foulques le Noir", "Mathieu Tranche-Mont", "Robert de Sarrebourg",
	"Gilles l'Ancien", "Hervé de Kerlouan", "Bérenger le Hardi", "Amaury de Craon", "Seguin Pied-de-Fer",
	"Renaud de Lusignan", "Thierry l'Âpre", "Garin de Montbrun"]
const MAX_HP := 160.0
const SPEED := 70.0
const DANGER_RADIUS := 16.0 ## Les ennemis à cette distance le frappent
const ARROW_RADIUS := 7.0 ## Une flèche qui tombe à cette distance le touche
const THREAT_RADIUS := 110.0 ## Des soldats du joueur à cette distance : il recule
const BACK_OFF := 70.0 ## Distance de recul derrière sa garde quand il est menacé
const DEATH_MORALE := 35.0 ## Moral perdu par chaque régiment ennemi quand il tombe
const GUARD_MORALE := 1.3 ## Garde : moral maximal multiplié
const GUARD_HP := 1.3 ## Garde : vie de chaque soldat multipliée
const GUARD_DAMAGE := 1.15 ## Garde : coups multipliés
const MIN_LEVEL := 2 ## Niveau de contrat à partir duquel l'ennemi a un chef visible
const BOUNTY_SHARE := 0.25 ## Tête du chef : part de la prime du contrat...
const BOUNTY_MIN := 60 ## ... jamais moins que ça
const FAME_WIN := 6 ## Renommée en plus si le chef tombe et que la bataille est gagnée
const FAME_LOSS := 3 ## ... et même si elle est perdue

var name := "Le chef ennemi"
var pos := Vector2.ZERO
var hp := MAX_HP
var guard: Regiment = null
var dead := false
var fled := false ## Sorti du champ (son armée a fui ou s'est retirée)
var flash := 0.0


## Vrai si la bataille de la scène a un chef ennemi.
static func wanted(battle: Battle) -> bool:
	if battle.is_tutorial or battle.campaign == null:
		return false
	var p: Dictionary = battle.campaign.pending
	if p.get("ambush", false):
		return false
	return bool(p.get("final", false)) or int(p.get("difficulty", 1)) >= MIN_LEVEL


## Nom tiré de la graine (sans toucher au rng de la simulation : l'ordre des tirages compte).
static func pick_name(seed_value: int) -> String:
	return str(NAMES[posmod(seed_value, NAMES.size())])


## Place un chef dans la bataille de la scène s'il y a lieu (appelé par battle.gd après le déploiement).
static func enter_battle(battle: Battle) -> void:
	if not wanted(battle):
		return
	var c := EnemyCommander.new()
	c.name = pick_name(battle.sim.rng.seed)
	c.take_field(battle.sim)


## Annonce du chef, au début de la bataille (les messages du déploiement sont déjà nombreux).
static func announce(battle: Battle) -> void:
	var c := battle.sim.commander
	if c == null or c.dead:
		return
	var who := c.name
	if battle.campaign != null:
		who += ", chef des %s" % str(battle.campaign.pending.get("foe", "ennemis"))
	battle.add_message("En face : %s, sous le grand étendard doré. Abattez-le pour ébranler son armée." % who)


## Choisit la garde (infanterie de préférence, la plus solide) et la renforce. Faux sans ennemi.
func take_field(sim: BattleSim) -> bool:
	guard = pick_guard(sim)
	if guard == null:
		return false
	sim.commander = self
	dead = false
	fled = false
	hp = MAX_HP
	guard.max_morale *= GUARD_MORALE
	guard.morale = guard.max_morale
	guard.damage_mult *= GUARD_DAMAGE
	for s in guard.soldiers:
		s.max_hp *= GUARD_HP
		s.hp = s.max_hp
	pos = follow_point()
	return true


## Régiment de garde : infanterie (ni tireur ni monté), la plus robuste ; à défaut, n'importe lequel.
static func pick_guard(sim: BattleSim) -> Regiment:
	var best: Regiment = null
	var best_score := -INF
	for r in sim.regiments:
		if r.team != BattleSim.ENEMY or r.is_dead() or r.routing:
			continue
		var score := float(r.stats["hp"]) * r.alive_n
		if r.stats["ranged"]:
			score *= 0.2
		elif r.stats["mounted"]:
			score *= 0.5
		if score > best_score:
			best_score = score
			best = r
	return best


## Derrière le centre de sa garde (par rapport à son front).
func follow_point() -> Vector2:
	var n := maxi(guard.alive_n, 1)
	var depth := guard.depth_rows(n) * float(guard.stats["spacing"]) * 0.5
	return guard.center - guard.facing * (depth + 40.0) + Vector2(guard.facing.y, -guard.facing.x) * 30.0 # Un peu de côté : son étendard ne cache pas celui du régiment


func step(sim: BattleSim, dt: float) -> void:
	if dead or fled:
		return
	flash = maxf(flash - dt, 0.0)
	if guard == null or guard.is_dead() or guard.routing:
		guard = nearest_friend(sim)
		if guard == null:
			# Plus personne à qui se fier : il quitte le champ par son bord
			pos = pos.move_toward(Vector2(pos.x, -80.0), SPEED * 1.4 * dt)
			if sim.state == BattleSim.State.BATTLE and pos.y < -40.0:
				fled = true
				sim.message("%s s'enfuit du champ de bataille." % name)
			return
	var goal := follow_point()
	if sim.state == BattleSim.State.DEPLOY:
		pos = goal
		return
	if sim.state != BattleSim.State.BATTLE:
		return
	# Menacé : il recule derrière sa garde, à l'opposé des soldats du joueur les plus proches
	var threat := threat_center(sim)
	if threat != Vector2.INF:
		var away := (pos - threat).normalized()
		if away == Vector2.ZERO:
			away = -guard.facing
		goal = goal.lerp(pos + away * BACK_OFF, 0.7)
	goal = goal.clamp(Vector2(30, 30), BattleSim.WORLD_SIZE - Vector2(30, 30))
	pos = pos.move_toward(goal, SPEED * (1.3 if threat != Vector2.INF else 1.0) * dt)
	take_hits(sim, dt)


## Centre des soldats du joueur (ou de ses alliés) à moins de THREAT_RADIUS, Vector2.INF si aucun.
func threat_center(sim: BattleSim) -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	for s in sim.soldiers_near(pos, THREAT_RADIUS):
		var r: Regiment = s.regiment
		if r.team == BattleSim.PLAYER and not r.routing:
			sum += s.pos
			n += 1
	return sum / n if n > 0 else Vector2.INF


## Coups des soldats du joueur au contact, et flèches qui tombent sur lui à ce pas.
func take_hits(sim: BattleSim, dt: float) -> void:
	var hurt := 0.0
	for s in sim.soldiers_near(pos, DANGER_RADIUS):
		var r: Regiment = s.regiment
		if r.team == BattleSim.PLAYER and not r.routing:
			hurt += float(r.stats["damage"]) / float(r.stats["cooldown"]) * 0.5 * r.rank_damage()
	var damage := hurt * dt
	for a in sim.arrows:
		var src: Regiment = a.get("src")
		if src == null or src.team != BattleSim.PLAYER:
			continue
		if float(a["t"]) + dt >= float(a["dur"]) and (a["to"] as Vector2).distance_to(pos) <= ARROW_RADIUS:
			damage += float(a["dmg"]) * 0.6 # Sa cuirasse arrête une partie du trait
	if damage <= 0.0:
		return
	hp -= damage
	flash = 0.12
	if hp <= 0.0:
		die(sim)


func nearest_friend(sim: BattleSim) -> Regiment:
	var best: Regiment = null
	var bd := INF
	for r in sim.regiments:
		if r.team != BattleSim.ENEMY or r.is_dead() or r.routing:
			continue
		var d := r.center.distance_to(pos)
		if d < bd:
			bd = d
			best = r
	return best


## Le chef tombe : toute son armée vacille.
func die(sim: BattleSim) -> void:
	if dead:
		return
	dead = true
	hp = 0.0
	for r in sim.regiments:
		if r.team == BattleSim.ENEMY and not r.is_dead() and not r.routing:
			r.morale -= DEATH_MORALE
	sim.message("%s, le chef ennemi, est tombé ! Son armée vacille." % name)
	sim.cries_played.emit(pos, 6)
	sim.impact.emit(pos, 0.05)
	sim.corpses.append([pos.round(), BattleSim.ENEMY, guard.type if guard != null else "men_at_arms", 1, sim.battle_time, guard, Vector2.DOWN])
	guard = null


## Résultat pour le bilan : {"present", "name", "slain", "fled"}.
func result() -> Dictionary:
	return {"present": true, "name": name, "slain": dead, "fled": fled}


static func result_of(sim: BattleSim) -> Dictionary:
	if sim.commander == null:
		return {"present": false}
	return sim.commander.result()


# ---------------------------------------------------------------- Campagne

## Avant CampaignState.finish_battle : note dans le contrat si le chef est tombé.
static func note_result(pending: Dictionary, sim: BattleSim) -> void:
	var res := result_of(sim)
	if bool(res.get("present", false)):
		pending["commander"] = res


## Dans CampaignState.finish_battle : tête du chef (prime et renommée si victoire, un peu de
## renommée sinon). Remplit out["commander"] = {"name", "slain", "bounty", "fame"} et renvoie
## une phrase pour le compte rendu ("" sans chef).
static func campaign_reward(state: CampaignState, out: Dictionary, victory: bool) -> String:
	var res: Variant = state.pending.get("commander", {})
	if not res is Dictionary or not bool((res as Dictionary).get("present", false)):
		return ""
	var who := str(res.get("name", "le chef ennemi"))
	var info := {"name": who, "slain": bool(res.get("slain", false)), "bounty": 0, "fame": 0}
	out["commander"] = info
	if not info["slain"]:
		return ""
	if victory:
		var bounty := maxi(BOUNTY_MIN, int(round(float(state.contract_reward(state.pending)) * BOUNTY_SHARE)))
		info["bounty"] = bounty
		info["fame"] = FAME_WIN
		state.gold += bounty
		state.gold_earned += bounty
		state.fame += FAME_WIN
		return " %s, leur chef, est tombé : %d écus pour sa tête, renommée +%d." % [who, bounty, FAME_WIN]
	info["fame"] = FAME_LOSS
	state.fame += FAME_LOSS
	return " On chantera tout de même la chute de %s (renommée +%d)." % [who, FAME_LOSS]


# ---------------------------------------------------------------- Dessin

## Cavalier en manteau sombre, grand étendard à queue fourchue aux couleurs de son camp.
func draw(ci: CanvasItem, flag: Color) -> void:
	if fled:
		return
	if dead:
		return
	if guard != null and guard.hidden:
		return # Embusqué avec sa garde
	var p := pos.round()
	var body := Color(1, 1, 1) if flash > 0.0 else Color(0.18, 0.1, 0.1)
	ci.draw_rect(Rect2(p.x - 7, p.y + 3, 14, 2), Color(0, 0, 0, 0.3)) # Ombre
	ci.draw_rect(Rect2(p.x - 6, p.y - 2, 12, 5), Color(0.32, 0.22, 0.14)) # Cheval
	ci.draw_rect(Rect2(p.x + 5, p.y - 5, 3, 4), Color(0.32, 0.22, 0.14)) # Tête du cheval
	ci.draw_rect(Rect2(p.x - 2, p.y - 9, 5, 8), body) # Cavalier
	ci.draw_rect(Rect2(p.x - 2, p.y - 13, 5, 4), Color(0.85, 0.72, 0.3)) # Heaume doré
	ci.draw_rect(Rect2(p.x - 1, p.y - 16, 3, 3), Color(0.95, 0.95, 0.9)) # Cimier
	ci.draw_line(p + Vector2(-5, 2), p + Vector2(-5, -34), Color(0.4, 0.27, 0.14), 1.5) # Hampe
	var top := p + Vector2(-5, -34)
	var pts := PackedVector2Array([top, top + Vector2(-16, 0), top + Vector2(-12, 5), top + Vector2(-16, 10), top + Vector2(0, 10)])
	ci.draw_colored_polygon(pts, flag) # Étendard à queue fourchue
	pts.append(top)
	ci.draw_polyline(pts, Color(0.95, 0.8, 0.3), 1.0)
	ci.draw_rect(Rect2(top.x - 9, top.y + 3, 3, 3), Color(0.95, 0.8, 0.3)) # Pièce d'or
	# Vie
	var k := clampf(hp / MAX_HP, 0.0, 1.0)
	ci.draw_rect(Rect2(p.x - 8, p.y + 6, 16, 2), Color(0, 0, 0, 0.6))
	ci.draw_rect(Rect2(p.x - 8, p.y + 6, 16 * k, 2), Color(1, 0.2, 0.15).lerp(Color(1, 0.84, 0.3), k))
