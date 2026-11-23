class_name BattleTraps
extends RefCounted
## Pièges posés pendant le déploiement : pieux, fossé, chausse-trapes.
##
## - Budget : quelques points selon le terrain (du bois pour les pieux, de la terre meuble pour
##   les fossés) et le temps qu'il fait (la pluie gêne les travaux) ; chaque piège a un coût.
## - Pose : seulement en déploiement, dans la zone bleue, pas sur un autre piège, une maison ou l'eau.
##   On peut retirer un piège (clic droit) tant que la bataille n'a pas commencé : il est remboursé.
## - Effets (sur l'ennemi seulement : la compagnie sait où elle les a plantés) :
##     pieux : un cavalier qui les charge est blessé, rejeté et son régiment s'arrête ; au pas,
##             on passe lentement. Chaque rang de pieux finit par céder (STAKE_USES chocs) ;
##     chausse-trapes : tout le monde ralentit, les chevaux s'y blessent, plus de charge ;
##     fossé : on y avance à peine, plus de charge ni de course, le régiment se désorganise
##             (moral qui baisse, coups reçus plus durs).
## Non sauvegardé : les pièges n'existent que le temps de la bataille (BattleSim.traps).
## Saisie : outil courant « tool » (touche P ou boutons du HUD), clic gauche pour poser (battle_orders.gd).

const KINDS: Array[String] = ["stakes", "ditch", "caltrops"]
const INFO := {
	"stakes": {"name": "Pieux", "cost": 2, "half": Vector2(56, 8), "text": "arrêtent les charges"},
	"ditch": {"name": "Fossé", "cost": 3, "half": Vector2(64, 12), "text": "ralentit, désorganise"},
	"caltrops": {"name": "Chausse-trapes", "cost": 1, "half": Vector2(44, 34), "text": "ralentissent"},
}
## Points de pièges selon le terrain (bois et terre à portée de main)
const BUDGET := {"plain": 6, "forest": 8, "hills": 6, "river": 5, "village": 7, "siege": 5}
const BUDGET_DEFAULT := 5
const RAIN_PENALTY := 2 ## La pluie détrempe le sol et ralentit les travaux
const BUDGET_MIN := 2
const STAKE_USES := 10 ## Chocs de cavaliers avant que la rangée de pieux cède
const STAKE_DAMAGE := Vector2(0.6, 1.1) ## Part de sa vie qu'un cavalier perd sur les pieux : au trot, au grand galop
const STAKE_MORALE := 1.5 ## Moral perdu par le régiment à chaque cheval empalé
const CHARGE_MOMENTUM := 0.35 ## Élan à partir duquel un cavalier « charge » les pieux
const STAKES_SLOW := 0.4 ## Vitesse au pas à travers les pieux
const DITCH_SLOW := 0.4
const CALTROPS_SLOW := 0.5
const CALTROPS_DPS := 2.5 ## Blessures des chevaux par seconde dans les chausse-trapes
const DITCH_MORALE := 5.0 ## Moral perdu par seconde par un régiment entier dans le fossé
const DITCH_EXPOSED := 1.3 ## Coups reçus dans le fossé multipliés

var budget := BUDGET_DEFAULT
var spent := 0
var traps: Array[Dictionary] = [] ## {"kind", "pos", "uses", "seen": {id de régiment: true}}
var tool := "" ## Piège en cours de pose ("" : aucun)
var stats := {"impaled": 0, "stopped": 0, "ditched": 0, "caltrops": 0} ## Pour le bilan


## Pièges de la bataille de la scène (pas au tutoriel), après la météo du jour.
static func enter_battle(battle: Battle) -> void:
	if battle.is_tutorial:
		return
	var t := BattleTraps.new()
	t.budget = budget_for(battle.sim.terrain.kind, battle.sim.raining)
	battle.sim.traps = t # Annoncé dans le message de déploiement (battle.gd) et la barre du HUD


static func budget_for(kind: String, raining: bool) -> int:
	var b := int(BUDGET.get(kind, BUDGET_DEFAULT))
	if raining:
		b -= RAIN_PENALTY
	return maxi(b, BUDGET_MIN)


static func cost(kind: String) -> int:
	return int(INFO[kind]["cost"])


static func rect_of(kind: String, p: Vector2) -> Rect2:
	var h: Vector2 = INFO[kind]["half"]
	return Rect2(p - h, h * 2.0)


func left() -> int:
	return budget - spent


## Raison pour laquelle on ne peut pas poser kind en p ("" si on peut).
func refusal(sim: BattleSim, kind: String, p: Vector2) -> String:
	if sim.state != BattleSim.State.DEPLOY:
		return "Les pièges se posent pendant le déploiement."
	if not INFO.has(kind):
		return "Piège inconnu."
	if cost(kind) > left():
		return "Plus assez de temps pour %s (reste %d point%s)." % [str(INFO[kind]["name"]).to_lower(), left(), "s" if left() > 1 else ""]
	var rect := rect_of(kind, p)
	if rect.position.y < sim.deploy_top() or rect.end.y > BattleSim.WORLD_SIZE.y or rect.position.x < 0.0 or rect.end.x > BattleSim.WORLD_SIZE.x:
		return "Les pièges se posent dans la zone bleue."
	for t in traps:
		if rect_of(t["kind"], t["pos"]).grow(6.0).intersects(rect):
			return "Trop près d'un autre piège."
	for q in [p, rect.position, rect.end, Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.position.y)]:
		if sim.terrain.blocked_at(q) or sim.terrain.is_deep_water(q):
			return "Le terrain ne s'y prête pas."
	return ""


## Pose un piège ; renvoie "" ou la raison du refus.
func place(sim: BattleSim, kind: String, p: Vector2) -> String:
	var why := refusal(sim, kind, p)
	if why != "":
		return why
	traps.append({"kind": kind, "pos": p.round(), "uses": STAKE_USES if kind == "stakes" else 0, "seen": {}})
	spent += cost(kind)
	return ""


## Retire le piège sous p (déploiement seulement) et rend ses points. Renvoie son nom ou "".
func remove_at(sim: BattleSim, p: Vector2) -> String:
	if sim.state != BattleSim.State.DEPLOY:
		return ""
	for i in range(traps.size() - 1, -1, -1):
		var t := traps[i]
		if rect_of(t["kind"], t["pos"]).grow(6.0).has_point(p):
			spent -= cost(t["kind"])
			traps.remove_at(i)
			return str(INFO[t["kind"]]["name"])
	return ""


## Outil suivant (touche P) : aucun → pieux → fossé → chausse-trapes → aucun.
func cycle_tool() -> void:
	var i := KINDS.find(tool)
	tool = KINDS[i + 1] if i + 1 < KINDS.size() else ""


# ---------------------------------------------------------------- Effets

func inside(t: Dictionary, p: Vector2) -> bool:
	var h: Vector2 = INFO[t["kind"]]["half"]
	var d: Vector2 = p - t["pos"]
	return absf(d.x) <= h.x and absf(d.y) <= h.y


func active(t: Dictionary) -> bool:
	return t["kind"] != "stakes" or int(t["uses"]) > 0


## Multiplicateur de vitesse d'un soldat (ennemis seulement), appelé par BattleSim.move_towards.
func speed_factor(s: Soldier) -> float:
	if traps.is_empty() or s.regiment.team != BattleSim.ENEMY:
		return 1.0
	var f := 1.0
	for t in traps:
		if not active(t) or not inside(t, s.pos):
			continue
		match t["kind"]:
			"stakes":
				f = minf(f, STAKES_SLOW)
			"ditch":
				f = minf(f, DITCH_SLOW)
			"caltrops":
				f = minf(f, CALTROPS_SLOW)
	return f


## Multiplicateur des coups reçus par un soldat (désorganisé dans un fossé), appelé par BattleSim.strike.
func damage_taken(s: Soldier) -> float:
	if traps.is_empty() or s.regiment.team != BattleSim.ENEMY:
		return 1.0
	for t in traps:
		if t["kind"] == "ditch" and inside(t, s.pos):
			return DITCH_EXPOSED
	return 1.0


## Effets des pièges pendant la bataille (appelé par BattleSim.step, état BATTLE).
func step(sim: BattleSim, dt: float) -> void:
	for t in traps:
		if not active(t):
			continue
		var h: Vector2 = INFO[t["kind"]]["half"]
		for s in sim.soldiers_near(t["pos"], h.length() + 2.0):
			var r: Regiment = s.regiment
			if r.team != BattleSim.ENEMY or r.routing or not inside(t, s.pos):
				continue
			match t["kind"]:
				"stakes":
					if r.stats["mounted"]:
						hit_stakes(sim, t, s)
						if not active(t):
							sim.message("Les pieux ont cédé sous les charges.")
							break
				"caltrops":
					if r.stats["mounted"]:
						s.momentum = minf(s.momentum, 0.2)
						sim.damage(s, CALTROPS_DPS * dt, null)
					r.running = false
					first_time(sim, t, r, "caltrops", "%s s'empêtrent dans les chausse-trapes." % sim.team_label(r))
				"ditch":
					s.momentum = 0.0
					r.running = false
					r.morale -= DITCH_MORALE * dt / float(r.stats["count"])
					first_time(sim, t, r, "ditched", "%s tombent dans le fossé et se désorganisent !" % sim.team_label(r))


## Un cavalier dans les pieux : s'il charge, il s'y empale, est rejeté en avant des pieux et son
## régiment s'arrête net ; au pas, il passe lentement (speed_factor).
func hit_stakes(sim: BattleSim, t: Dictionary, s: Soldier) -> void:
	var r: Regiment = s.regiment
	if s.momentum < CHARGE_MOMENTUM and not r.running:
		return
	var h: Vector2 = INFO["stakes"]["half"]
	var p: Vector2 = t["pos"]
	var hurt := s.max_hp * lerpf(STAKE_DAMAGE.x, STAKE_DAMAGE.y, clampf(s.momentum, 0.0, 1.0))
	s.momentum = 0.0
	# Rejeté du côté d'où il venait
	s.pos.y = p.y - h.y - 5.0 if s.pos.y < p.y else p.y + h.y + 5.0
	t["uses"] = int(t["uses"]) - 1
	stats["impaled"] += 1
	r.morale -= STAKE_MORALE
	sim.damage(s, hurt, null)
	if not t["seen"].has(r.id):
		t["seen"][r.id] = true
		stats["stopped"] += 1
		r.running = false
		r.target = null # La charge est brisée : le régiment s'arrête
		r.dest = r.center
		r.think = 1.0
		sim.message("%s s'empalent sur les pieux : la charge est brisée !" % sim.team_label(r))
		sim.impact.emit(s.pos, 0.06)
		sim.sound_played.emit("clash", s.pos)


func first_time(sim: BattleSim, t: Dictionary, r: Regiment, stat: String, text: String) -> void:
	if t["seen"].has(r.id):
		return
	t["seen"][r.id] = true
	stats[stat] += 1
	sim.message(text)


## Ligne du bilan ("" si aucun piège n'a servi).
func summary() -> String:
	if traps.is_empty():
		return ""
	var parts: Array[String] = []
	if int(stats["impaled"]) > 0:
		parts.append("%d chevaux empalés sur les pieux" % int(stats["impaled"]))
	if int(stats["ditched"]) > 0:
		parts.append("%d régiment%s au fossé" % [int(stats["ditched"]), "s" if int(stats["ditched"]) > 1 else ""])
	if int(stats["caltrops"]) > 0:
		parts.append("%d régiment%s dans les chausse-trapes" % [int(stats["caltrops"]), "s" if int(stats["caltrops"]) > 1 else ""])
	if parts.is_empty():
		return "Pièges : %d posés, l'ennemi les a évités." % traps.size()
	return "Pièges : " + ", ".join(parts) + "."


# ---------------------------------------------------------------- Dessin

const WOOD := Color(0.5, 0.34, 0.18)
const WOOD_TIP := Color(0.78, 0.66, 0.45)
const EARTH := Color(0.3, 0.22, 0.13)


func draw(ci: CanvasItem, deploying: bool) -> void:
	for t in traps:
		draw_trap(ci, t["kind"], t["pos"], active(t), Color(1, 1, 1, 1))
		if deploying:
			ci.draw_rect(rect_of(t["kind"], t["pos"]), Color(1, 0.9, 0.5, 0.35), false, 1.0)


## Aperçu sous la souris pendant la pose : vert si possible, rouge sinon.
func draw_ghost(ci: CanvasItem, sim: BattleSim, p: Vector2) -> void:
	if tool == "" or sim.state != BattleSim.State.DEPLOY:
		return
	var ok := refusal(sim, tool, p) == ""
	var col := Color(0.4, 1, 0.4, 0.8) if ok else Color(1, 0.3, 0.25, 0.8)
	draw_trap(ci, tool, p.round(), true, Color(1, 1, 1, 0.55))
	ci.draw_rect(rect_of(tool, p.round()), col, false, 1.5)


static func draw_trap(ci: CanvasItem, kind: String, p: Vector2, intact: bool, tint: Color) -> void:
	var h: Vector2 = INFO[kind]["half"]
	match kind:
		"stakes":
			# Rangée de pieux plantés en oblique, pointe vers l'ennemi (en haut)
			var x := -h.x + 3.0
			var k := 0
			while x <= h.x - 2.0:
				var base := p + Vector2(x, h.y - 2.0 - (k % 2) * 5.0)
				var tip := base + (Vector2(2, -12) if intact else Vector2(7, -4))
				ci.draw_line(base, tip, WOOD * tint, 2.0)
				if intact:
					ci.draw_line(tip, tip + Vector2(0.6, -2.5), WOOD_TIP * tint, 1.5)
				x += 7.0
				k += 1
		"ditch":
			var r := Rect2(p - h, h * 2.0)
			ci.draw_rect(r, EARTH * tint)
			ci.draw_rect(Rect2(r.position + Vector2(3, 4), r.size - Vector2(6, 8)), EARTH.darkened(0.45) * tint)
			ci.draw_rect(Rect2(r.position.x, r.end.y, r.size.x, 4), Color(0.45, 0.35, 0.2) * tint) # Déblais du côté de la compagnie
		"caltrops":
			# Semis de pointes de fer, toujours au même endroit pour un même piège
			var seed_v := int(p.x) * 73856093 ^ int(p.y) * 19349663
			for i in 26:
				seed_v = (seed_v * 1103515245 + 12345) & 0x7fffffff
				var dx := float(seed_v % 1000) / 1000.0 * 2.0 - 1.0
				seed_v = (seed_v * 1103515245 + 12345) & 0x7fffffff
				var dy := float(seed_v % 1000) / 1000.0 * 2.0 - 1.0
				var q := (p + Vector2(dx * (h.x - 3.0), dy * (h.y - 3.0))).round()
				var c := Color(0.3, 0.3, 0.34) * tint
				ci.draw_line(q + Vector2(-2, -2), q + Vector2(2, 2), c, 1.5)
				ci.draw_line(q + Vector2(-2, 2), q + Vector2(2, -2), c, 1.5)
				ci.draw_rect(Rect2(q - Vector2(0.5, 0.5), Vector2(1, 1)), Color(0.75, 0.75, 0.8) * tint)
