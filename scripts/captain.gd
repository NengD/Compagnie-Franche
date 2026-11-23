class_name Captain
extends RefCounted
## Capitaine de la compagnie : un personnage nommé, présent sur le champ de bataille.
##
## En campagne (sauvegardé) : nom, niveau, expérience, points de compétence, compétences
## (aura, ralliement, solde) et blessure (indisponible jusqu'au jour « wounded_until »).
## En bataille (non sauvegardé) : position, vie, régiment d'escorte. Il suit son escorte, rend
## du moral aux régiments proches (aura) ; s'il tombe, toute la compagnie perd beaucoup de moral,
## mais la bataille continue. En campagne, il n'est que blessé.
## Le même objet sert en campagne et en bataille (CampaignState.current.captain).

const NAMES := ["Bertrand de Vaux", "Arnaud le Roux", "Guiraud Sans-Peur", "Thibaut de Montjoie",
	"Raoul l'Écorcheur", "Enguerrand de Saulx", "Hugues Brise-Lance", "Jehan de Castelnau",
	"Aymeric le Borgne", "Perrin de Lusse"]
## Arbre de compétences : trois voies (PATHS), quatre compétences chacune. Chaque compétence a
## un nom, une description, un rang maximal (« max »), un coût en points par rang (« cost »), un
## niveau de capitaine requis (« level ») et des prérequis (« req » : compétence -> rang minimal).
## Les effets de bataille (Meneur, Tacticien) ne jouent que si le capitaine est sur le champ ;
## ceux de l'Intendant jouent toujours.
const PATHS := {
	"leader": {"name": "Meneur", "text": "moral et ralliement"},
	"tactician": {"name": "Tacticien", "text": "manœuvres, formations et déploiement"},
	"steward": {"name": "Intendant", "text": "solde, vivres et prix"},
}
const PATH_ORDER := ["leader", "tactician", "steward"]
const SKILLS := {
	# Meneur
	"aura": {"path": "leader", "name": "Aura", "text": "rayon de l'aura de moral +25 % par rang", "max": 3, "cost": 1, "level": 1, "req": {}},
	"rally": {"path": "leader", "name": "Ralliement", "text": "dans l'aura, les fuyards se rallient (même deux fois), plus vite à chaque rang", "max": 3, "cost": 1, "level": 1, "req": {}},
	"banner": {"path": "leader", "name": "Bannière haute", "text": "moral maximal des régiments +10 %", "max": 1, "cost": 2, "level": 4, "req": {"aura": 1, "rally": 1}},
	"iron": {"path": "leader", "name": "Volonté de fer", "text": "la chute du capitaine ou d'un officier ébranle moitié moins", "max": 1, "cost": 2, "level": 6, "req": {"banner": 1}},
	# Tacticien
	"drill": {"path": "tactician", "name": "Manœuvres", "text": "vitesse des régiments +5 % par rang", "max": 2, "cost": 1, "level": 1, "req": {}},
	"formations": {"path": "tactician", "name": "Formations serrées", "text": "en colonne et en carré, les régiments marchent 25 % plus vite", "max": 1, "cost": 1, "level": 2, "req": {"drill": 1}},
	"scouting": {"path": "tactician", "name": "Reconnaissance", "text": "zone de déploiement plus profonde de 150 pas vers l'ennemi", "max": 1, "cost": 2, "level": 4, "req": {"formations": 1}},
	"eye": {"path": "tactician", "name": "Coup d'œil", "text": "dégâts en mêlée +8 %", "max": 1, "cost": 2, "level": 6, "req": {"scouting": 1}},
	# Intendant
	"wages": {"path": "steward", "name": "Solde réduite", "text": "solde de la compagnie -5 % par rang", "max": 3, "cost": 1, "level": 1, "req": {}},
	"thrift": {"path": "steward", "name": "Économe", "text": "la compagnie mange 10 % de vivres en moins par rang", "max": 2, "cost": 1, "level": 2, "req": {"wages": 1}},
	"haggle": {"path": "steward", "name": "Marchandeur", "text": "recrues, équipement et vivres 10 % moins chers", "max": 1, "cost": 2, "level": 4, "req": {"thrift": 1}},
	"plunder": {"path": "steward", "name": "Pillard avisé", "text": "butin des batailles +20 %", "max": 1, "cost": 2, "level": 6, "req": {"haggle": 1}},
}
const SKILL_MAX := 3 ## Rang maximal le plus haut de l'arbre
const LEVEL_XP := 100.0 ## Expérience pour chaque niveau
const MAX_LEVEL := 10 ## Neuf points en tout : pas assez pour tout l'arbre, il faut choisir sa voie
const XP_BATTLE := 30.0
const XP_VICTORY := 30.0
const WOUND_DAYS := 5 ## Jours d'indisponibilité après être tombé
const AURA_RADIUS := 180.0
const AURA_STEP := 0.25 ## Rayon en plus par niveau d'aura
const AURA_REGEN := 1.0 ## Moral rendu par seconde dans l'aura (même en mêlée)
const RALLY_REGEN := 3.0 ## Moral rendu par seconde aux fuyards, par niveau de ralliement
const WAGE_STEP := 0.05
const BANNER_MORALE := 0.1
const IRON_FACTOR := 0.5
const DRILL_SPEED := 0.05
const FORMATION_SPEED := 1.25
const SCOUTING_DEPTH := 150.0
const EYE_DAMAGE := 0.08
const THRIFT_STEP := 0.1
const HAGGLE_PRICE := 0.9
const PLUNDER_LOOT := 1.2
const DEATH_MORALE := 40.0 ## Moral perdu par chaque régiment quand le capitaine tombe
const MAX_HP := 120.0
const SPEED := 80.0
const DANGER_RADIUS := 16.0 ## Les ennemis à cette distance le frappent
const PICK_RADIUS := 12.0

# ---------------------------------------------------------------- Campagne (sauvegardé)
var name := "Le capitaine"
var level := 1
var xp := 0.0
var points := 0
var skills := Captain.empty_skills()
var wounded_until := 0 ## Jour à partir duquel il est de nouveau disponible

# ---------------------------------------------------------------- Bataille
var pos := Vector2.ZERO
var hp := MAX_HP
var escort: Regiment = null
var dead := false
var fell := false ## Tombé pendant la dernière bataille (blessé en campagne)
var selected := false
var flash := 0.0


## Capitaine d'une nouvelle campagne : son nom dépend de la graine, sans toucher au rng de la campagne.
static func recruit(seed_value: int) -> Captain:
	var c := Captain.new()
	c.name = str(NAMES[posmod(seed_value, NAMES.size())])
	return c


func to_dict() -> Dictionary:
	return {"name": name, "level": level, "xp": xp, "points": points, "skills": skills.duplicate(), "wounded_until": wounded_until}


## Relit un capitaine sauvegardé ; d vide (sauvegarde de version 5 et avant) : capitaine neuf.
static func from_dict(d: Variant, seed_value: int) -> Captain:
	var c := recruit(seed_value)
	if not d is Dictionary or (d as Dictionary).is_empty():
		return c
	c.name = str(d.get("name", c.name))
	c.level = clampi(int(d.get("level", 1)), 1, MAX_LEVEL)
	c.xp = clampf(float(d.get("xp", 0.0)), 0.0, LEVEL_XP * MAX_LEVEL)
	c.points = clampi(int(d.get("points", 0)), 0, MAX_LEVEL)
	var sk: Variant = d.get("skills", {})
	if sk is Dictionary:
		for k in c.skills:
			c.skills[k] = clampi(int(sk.get(k, 0)), 0, int(SKILLS[k]["max"])) # Version 13 et avant : trois compétences
	c.wounded_until = maxi(0, int(d.get("wounded_until", 0)))
	return c


func available(day: int) -> bool:
	return day >= wounded_until


func aura_radius() -> float:
	return AURA_RADIUS * (1.0 + AURA_STEP * int(skills["aura"]))


## Multiplicateur de la solde de la compagnie.
func wage_factor() -> float:
	return 1.0 - WAGE_STEP * int(skills["wages"])


static func empty_skills() -> Dictionary:
	var d := {}
	for k in SKILLS:
		d[k] = 0
	return d


func rank(skill: String) -> int:
	return int(skills.get(skill, 0))


## Pourquoi on ne peut pas prendre un rang de plus de cette compétence ("" : possible).
func refusal(skill: String) -> String:
	if not SKILLS.has(skill):
		return "Compétence inconnue."
	var info: Dictionary = SKILLS[skill]
	if rank(skill) >= int(info["max"]):
		return "%s est déjà au maximum." % info["name"]
	if level < int(info["level"]):
		return "%s demande un capitaine de niveau %d." % [info["name"], int(info["level"])]
	for k in info["req"]:
		if rank(k) < int(info["req"][k]):
			return "%s demande d'abord %s." % [info["name"], SKILLS[k]["name"]]
	if points < int(info["cost"]):
		return "Aucun point de compétence." if points <= 0 else "Pas assez de points (%d)." % int(info["cost"])
	return ""


## Apprend un rang d'une compétence (son coût en points). Renvoie un message d'erreur ou "".
func learn(skill: String) -> String:
	var why := refusal(skill)
	if why != "":
		return why
	points -= int(SKILLS[skill]["cost"])
	skills[skill] = rank(skill) + 1
	return ""


## Points dépensés dans une voie.
func spent(path: String) -> int:
	var n := 0
	for k in SKILLS:
		if str(SKILLS[k]["path"]) == path:
			n += rank(k) * int(SKILLS[k]["cost"])
	return n


# ---------------------------------------------------------------- Effets de l'arbre

func morale_factor() -> float:
	return 1.0 + BANNER_MORALE * rank("banner")


## Moral perdu quand le capitaine ou un officier tombe (multiplicateur).
func fall_factor() -> float:
	return IRON_FACTOR if rank("iron") > 0 else 1.0


func speed_factor() -> float:
	return 1.0 + DRILL_SPEED * rank("drill")


func formation_factor() -> float:
	return FORMATION_SPEED if rank("formations") > 0 else 1.0


func deploy_depth() -> float:
	return SCOUTING_DEPTH * rank("scouting")


func melee_factor() -> float:
	return 1.0 + EYE_DAMAGE * rank("eye")


## Multiplicateur des vivres mangés chaque jour.
func food_factor() -> float:
	return 1.0 - THRIFT_STEP * rank("thrift")


## Multiplicateur des prix (recrues, équipement, vivres).
func price_factor() -> float:
	return HAGGLE_PRICE if rank("haggle") > 0 else 1.0


func loot_factor() -> float:
	return PLUNDER_LOOT if rank("plunder") > 0 else 1.0


## Effets de bataille du Meneur et du Tacticien sur les régiments du joueur (capitaine présent).
func apply_tree(sim: BattleSim) -> void:
	sim.deploy_bonus = deploy_depth()
	var mk := morale_factor()
	for r in sim.player_regiments():
		if r.allied:
			continue
		r.stats = r.stats.duplicate()
		r.stats["speed"] = float(r.stats["speed"]) * speed_factor()
		r.stats["damage"] = float(r.stats["damage"]) * melee_factor()
		r.drill_mult = formation_factor()
		r.max_morale *= mk
		r.morale = minf(r.morale * mk, r.max_morale)


## Après une bataille de campagne : expérience, niveaux, blessure. Renvoie une phrase pour le compte rendu.
func after_battle(state: CampaignState, victory: bool) -> String:
	if not available(state.day):
		return ""
	var out := ""
	xp = minf(xp + XP_BATTLE + (XP_VICTORY if victory else 0.0), LEVEL_XP * MAX_LEVEL)
	while level < MAX_LEVEL and xp >= LEVEL_XP * level:
		level += 1
		points += 1
		out += " %s passe au niveau %d (un point de compétence)." % [name, level]
	if fell:
		wounded_until = state.day + 1 + WOUND_DAYS
		out = " %s est tombé, blessé : indisponible jusqu'au jour %d." % [name, wounded_until] + out
	fell = false
	return out


# ---------------------------------------------------------------- Bataille

## Place le capitaine de la campagne (ou celui d'une escarmouche) sur le champ.
## Aucun capitaine dans le tutoriel ; un capitaine blessé reste au camp.
static func enter_battle(battle: Battle) -> void:
	if battle.is_tutorial:
		return
	var cap: Captain
	if battle.campaign != null:
		cap = battle.campaign.captain
		if not cap.available(battle.campaign.day):
			battle.add_message("%s, blessé, garde le lit jusqu'au jour %d." % [cap.name, cap.wounded_until])
			return
	else:
		cap = Captain.new()
	cap.take_field(battle.sim)


func take_field(sim: BattleSim) -> void:
	dead = false
	fell = false
	selected = false
	hp = MAX_HP
	escort = null
	sim.captain = self
	var best: Regiment = null
	for r in sim.player_regiments():
		# De préférence avec l'infanterie (au centre), sinon le premier venu
		if best == null or (not r.stats["ranged"] and not r.stats["mounted"] and (best.stats["ranged"] or best.stats["mounted"])):
			best = r
	escort = best
	if escort != null:
		pos = follow_point()
	apply_tree(sim)


## Quitte le champ de bataille (fin de scène) : plus de référence aux régiments.
func leave_field() -> void:
	escort = null
	selected = false


## Place derrière le centre de l'escorte.
func follow_point() -> Vector2:
	var n := maxi(escort.alive_n, 1)
	var depth := escort.depth_rows(n) * float(escort.stats["spacing"]) * 0.5
	return escort.center - escort.facing * (depth + 14.0)


func step(sim: BattleSim, dt: float) -> void:
	if dead:
		return
	flash = maxf(flash - dt, 0.0)
	if escort == null or escort.is_dead() or escort.routing:
		escort = nearest_friend(sim)
	if escort != null:
		var goal := follow_point()
		if sim.state == BattleSim.State.DEPLOY:
			pos = goal
		else:
			pos = pos.move_toward(goal, SPEED * dt)
	if sim.state != BattleSim.State.BATTLE:
		return
	apply_aura(sim, dt)
	# Les ennemis au contact le frappent
	var hurt := 0.0
	for s in sim.soldiers_near(pos, DANGER_RADIUS):
		var r: Regiment = s.regiment
		if r.team != BattleSim.PLAYER and not r.routing:
			hurt += float(r.stats["damage"]) / float(r.stats["cooldown"]) * 0.5 * r.damage_mult
	if hurt > 0.0:
		hp -= hurt * dt
		flash = 0.12
		if hp <= 0.0:
			die(sim)


func apply_aura(sim: BattleSim, dt: float) -> void:
	var rad := aura_radius()
	var rally := int(skills["rally"])
	for r in sim.regiments:
		if r.team != BattleSim.PLAYER or r.is_dead() or r.center.distance_to(pos) > rad:
			continue
		if r.routing:
			if rally > 0:
				r.rallied_once = false # Le capitaine peut rallier encore et encore
				r.morale += RALLY_REGEN * rally * dt
		else:
			r.morale = minf(r.morale + AURA_REGEN * dt, r.max_morale)


func nearest_friend(sim: BattleSim) -> Regiment:
	var best: Regiment = null
	var bd := INF
	for r in sim.player_regiments():
		var d := r.center.distance_to(pos)
		if d < bd:
			bd = d
			best = r
	return best


## Le capitaine tombe : la compagnie est ébranlée, mais la bataille continue.
func die(sim: BattleSim) -> void:
	dead = true
	fell = true
	selected = false
	escort = null
	for r in sim.regiments:
		if r.team == BattleSim.PLAYER and not r.is_dead() and not r.routing:
			r.morale -= DEATH_MORALE * fall_factor()
	sim.message("%s est tombé ! La compagnie vacille." % name)
	sim.cries_played.emit(pos, 6)


## Clic sur le capitaine : il est sélectionné avec son escorte. Renvoie vrai si on l'a touché.
func pick(p: Vector2) -> bool:
	if dead or escort == null or p.distance_to(pos) > PICK_RADIUS:
		return false
	selected = true
	escort.selected = true
	return true


## Touche C : le capitaine rejoint le premier régiment sélectionné.
static func order_join(battle: Battle) -> void:
	var cap := battle.sim.captain
	if cap == null or cap.dead:
		return
	var sel := battle.sim.selected_regiments()
	if sel.is_empty():
		battle.add_message("Sélectionnez le régiment que le capitaine doit rejoindre.")
		return
	cap.escort = sel[0]
	battle.add_message("%s rejoint les %s." % [cap.name, sel[0].display_name().to_lower()])


## Dessin sur le champ de bataille (appelé par battle_renderer.gd) : aura, cavalier et fanion.
func draw(ci: CanvasItem, deploying: bool) -> void:
	if dead or escort == null:
		return
	if selected or deploying:
		ci.draw_arc(pos, aura_radius(), 0, TAU, 64, Color(1, 0.84, 0.4, 0.35 if selected else 0.15), 1.5)
	var p := pos.round()
	var body := Color(1, 1, 1) if flash > 0.0 else Color(0.22, 0.38, 0.85)
	ci.draw_rect(Rect2(p.x - 5, p.y + 3, 10, 2), Color(0, 0, 0, 0.3)) # Ombre
	ci.draw_rect(Rect2(p.x - 2, p.y - 6, 4, 8), body) # Corps
	ci.draw_rect(Rect2(p.x - 2, p.y - 10, 4, 4), Color(0.72, 0.74, 0.78)) # Casque
	ci.draw_rect(Rect2(p.x - 1, p.y - 13, 2, 3), Color(0.9, 0.15, 0.12)) # Plumet
	ci.draw_line(p + Vector2(4, 2), p + Vector2(4, -22), Color(0.48, 0.32, 0.17), 1.0) # Hampe
	ci.draw_rect(Rect2(p.x + 4, p.y - 22, 9, 6), Color(1, 0.84, 0.4)) # Fanion doré
	ci.draw_rect(Rect2(p.x + 4, p.y - 22, 9, 6), Color(0, 0, 0, 0.6), false, 1.0)
	if selected:
		ci.draw_rect(Rect2(p.x - 4, p.y - 15, 8, 20), Color(1, 0.95, 0.4), false, 1.0)
	# Vie
	var k := clampf(hp / MAX_HP, 0.0, 1.0)
	ci.draw_rect(Rect2(p.x - 6, p.y + 6, 12, 2), Color(0, 0, 0, 0.6))
	ci.draw_rect(Rect2(p.x - 6, p.y + 6, 12 * k, 2), Color(1, 0.2, 0.15).lerp(Color(0.3, 1, 0.3), k))
