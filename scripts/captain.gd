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
## Compétences : nom, description, niveau maximal.
const SKILLS := {
	"aura": {"name": "Aura", "text": "rayon de l'aura +25 %"},
	"rally": {"name": "Ralliement", "text": "les fuyards proches se rallient (même deux fois)"},
	"wages": {"name": "Solde réduite", "text": "solde de la compagnie -5 %"},
}
const SKILL_MAX := 3
const LEVEL_XP := 100.0 ## Expérience pour chaque niveau
const MAX_LEVEL := 1 + SKILL_MAX * 3 ## Assez de niveaux pour tout apprendre
const XP_BATTLE := 30.0
const XP_VICTORY := 30.0
const WOUND_DAYS := 5 ## Jours d'indisponibilité après être tombé
const AURA_RADIUS := 180.0
const AURA_STEP := 0.25 ## Rayon en plus par niveau d'aura
const AURA_REGEN := 1.0 ## Moral rendu par seconde dans l'aura (même en mêlée)
const RALLY_REGEN := 3.0 ## Moral rendu par seconde aux fuyards, par niveau de ralliement
const WAGE_STEP := 0.05
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
var skills := {"aura": 0, "rally": 0, "wages": 0}
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
			c.skills[k] = clampi(int(sk.get(k, 0)), 0, SKILL_MAX)
	c.wounded_until = maxi(0, int(d.get("wounded_until", 0)))
	return c


func available(day: int) -> bool:
	return day >= wounded_until


func aura_radius() -> float:
	return AURA_RADIUS * (1.0 + AURA_STEP * int(skills["aura"]))


## Multiplicateur de la solde de la compagnie.
func wage_factor() -> float:
	return 1.0 - WAGE_STEP * int(skills["wages"])


## Apprend une compétence (un point). Renvoie un message d'erreur ou "".
func learn(skill: String) -> String:
	if not skills.has(skill):
		return "Compétence inconnue."
	if points <= 0:
		return "Aucun point de compétence."
	if int(skills[skill]) >= SKILL_MAX:
		return "%s est déjà au maximum." % SKILLS[skill]["name"]
	points -= 1
	skills[skill] = int(skills[skill]) + 1
	return ""


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
			r.morale -= DEATH_MORALE
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
