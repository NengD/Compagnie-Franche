class_name BattleObjectives
extends RefCounted
## Objectifs de bataille : la condition de victoire ou de défaite d'une bataille.
##
## La simulation (battle_sim.gd) garde un objectif (sim.objective) et l'interroge à chaque pas :
##   setup(sim)        une fois, armées déployées (zone, chariots, garnison, bande en fuite) ;
##   step(sim, dt)     pendant la bataille (chronomètre, contrôle d'une zone, chariots) ;
##   check(sim)        ONGOING, WON ou LOST (avec end_message pour le journal).
## Le reste sert à l'affichage et à l'IA :
##   shows_panel() / label() / status(sim) / progress(sim) / danger(sim)  panneau du HUD ;
##   draw(ci, sim)     dessin au sol (zone, chariots, ligne de fuite), sous les soldats ;
##   briefing()        message affiché au déploiement ;
##   result(sim)       bilan de fin de bataille ({"kind", "label", "summary", "success"...}) ;
##   allowed_terrains() terrains possibles ([] : tous) ; fit_terrain(kind, seed) en découle ;
##   ai_plan()         plan imposé à l'IA ennemie ("" : libre ; voir EnemyAI.PLANS et EnemyAI.FLEE) ;
##   ai_point(sim, r)  point que le régiment ennemi r doit gagner (Vector2.INF : aucun) ;
##   ai_engage         distance en deçà de laquelle il combat plutôt que de gagner ce point ;
##   ai_anchor(sim)    poste à défendre en plan défensif (Vector2.INF : celui de l'IA) ;
##   ai_counterattacks() faux : la défense ne lâche pas son poste pour contre-attaquer.
##
## « Détruire l'ennemi » (Destroy) est l'objectif par défaut. Pour un nouvel objectif (le siège,
## par exemple) : une classe qui étend BattleObjectives.Objective (ici ou dans son propre fichier),
## une entrée dans create() et dans KINDS / NAMES, puis ses contrats (CampaignState.OBJECTIVES).
## Un objectif ne tire jamais dans sim.rng pendant la bataille (graines fixes des tests et du banc).

const ONGOING := 0
const WON := 1
const LOST := 2
const KINDS: Array[String] = ["destroy", "hold", "escort", "capture", "pursue"]
const NAMES := {
	"destroy": "Détruire l'ennemi", "hold": "Tenir la position", "escort": "Escorter le convoi",
	"capture": "Prendre le village", "pursue": "Rattraper la bande",
}
const MIN_MEN := 4 ## Hommes nécessaires dans une zone pour la contester
const PLAYER_ZONE := Color(0.35, 0.55, 1.0)
const ENEMY_ZONE := Color(1.0, 0.3, 0.25)
const NEUTRAL_ZONE := Color(1.0, 0.92, 0.6)


## Objectif de sorte kind (clé de NAMES ; inconnue = détruire), réglé par params.
static func create(kind: String, params: Dictionary = {}) -> Objective:
	var o: Objective
	match kind:
		"hold":
			o = Hold.new()
		"escort":
			o = Escort.new()
		"capture":
			o = Capture.new()
		"pursue":
			o = Pursue.new()
		_:
			o = Destroy.new()
	o.params = params.duplicate(true)
	o.configure()
	return o


## Objectif d'un contrat de campagne (clé « objective » : {"kind", réglages}) ; détruire par défaut.
static func from_contract(contract: Dictionary) -> Objective:
	var spec: Variant = contract.get("objective", {})
	if not spec is Dictionary:
		return create("destroy")
	return create(str(spec.get("kind", "destroy")), spec)


## [le joueur a encore un régiment debout, l'ennemi aussi] (ni mort ni en fuite).
static func standing(sim: BattleSim) -> Array[bool]:
	var out: Array[bool] = [false, false]
	for r in sim.regiments:
		if not r.is_dead() and not r.routing:
			out[0 if r.team == BattleSim.PLAYER else 1] = true
	return out


## Hommes de team debout (pas en fuite) à moins de radius de center.
static func men_in(sim: BattleSim, team: int, center: Vector2, radius: float) -> int:
	var n := 0
	var r2 := radius * radius
	for s in sim.soldiers:
		if s.alive and s.regiment.team == team and not s.regiment.routing and s.pos.distance_squared_to(center) <= r2:
			n += 1
	return n


## « 2:05 » : temps restant en minutes et secondes.
static func clock(t: float) -> String:
	var s := maxi(0, ceili(t))
	@warning_ignore("integer_division")
	return "%d:%02d" % [s / 60, s % 60]


## « 3 minutes », « 1 minute 30 » : durée lisible (textes de contrat et bilan).
static func duration_words(t: float) -> String:
	var s := int(round(t))
	@warning_ignore("integer_division")
	var m := s / 60
	var rest := s % 60
	var out := "%d %s" % [m, "minute" if m == 1 else "minutes"]
	if rest > 0:
		out = "%d min %02d s" % [m, rest]
	return out


## Point du milieu du champ, sur la route s'il y en a une (entre les deux armées).
static func middle(sim: BattleSim) -> Vector2:
	var x := BattleSim.WORLD_SIZE.x * 0.5
	if sim.terrain.has_road():
		return Vector2(x, sim.road_y(x))
	return Vector2(x, BattleSim.WORLD_SIZE.y * 0.5)


## Place le régiment r en at, face à face (soldats compris : sert avant le début de la bataille).
static func place(r: Regiment, at: Vector2, face: Vector2) -> void:
	r.dest = at
	r.facing = face
	var alive := r.alive_soldiers()
	for i in alive.size():
		alive[i].pos = r.slot_position(i, alive.size())
	r.update_center()


## Range une liste de régiments côte à côte autour de at (front face, écart gap).
static func place_row(list: Array[Regiment], at: Vector2, face: Vector2, gap: float) -> void:
	var right := Vector2(-face.y, face.x)
	for k in list.size():
		place(list[k], (at + right * (k - (list.size() - 1) * 0.5) * gap).clamp(Vector2(80, 80), BattleSim.WORLD_SIZE - Vector2(80, 80)), face)


## Zone au sol : disque teinté selon qui la tient, cercle en tirets, arc de progression.
static func draw_zone(ci: CanvasItem, center: Vector2, radius: float, col: Color, fill: float) -> void:
	ci.draw_circle(center, radius, Color(col.r, col.g, col.b, 0.1))
	var n := 36
	for i in n:
		if i % 2 == 1:
			continue
		var a0 := TAU * i / n
		ci.draw_arc(center, radius, a0, a0 + TAU / n, 4, Color(col.r, col.g, col.b, 0.75), 3.0)
	if fill > 0.0:
		ci.draw_arc(center, radius + 7.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(fill, 0.0, 1.0), 48, Color(1, 0.9, 0.45, 0.85), 4.0)
	# Fanion planté au centre
	ci.draw_line(center, center + Vector2(0, -34), Color(0.3, 0.22, 0.12), 2.0)
	ci.draw_colored_polygon(PackedVector2Array([center + Vector2(1, -34), center + Vector2(16, -29), center + Vector2(1, -24)]), col)


# ================================================================ Objectif (classe de base)

## Interface commune (voir l'en-tête du fichier). Par défaut : victoire quand l'ennemi n'a plus de
## régiment debout, défaite dans le cas inverse.
class Objective extends RefCounted:
	var kind := "destroy"
	var params: Dictionary = {}
	var end_message := "" ## Message de fin (journal), fixé par check()
	var ai_engage := 340.0 ## L'IA combat ce qui est plus près que ça plutôt que de gagner ai_point

	## Lit params (appelé par create).
	func configure() -> void:
		pass

	func label() -> String:
		return str(BattleObjectives.NAMES.get(kind, kind))

	## Message de déploiement ("" : aucun).
	func briefing() -> String:
		return ""

	## Terrains possibles pour cet objectif ([] : tous).
	func allowed_terrains() -> Array[String]:
		return []

	## Terrain retenu : wanted s'il convient, sinon un terrain permis tiré d'après seed.
	func fit_terrain(wanted: String, seed_value: int) -> String:
		var ok := allowed_terrains()
		if ok.is_empty() or wanted in ok:
			return wanted
		return ok[absi(seed_value) % ok.size()]

	func setup(_sim: BattleSim) -> void:
		pass

	func step(_sim: BattleSim, _dt: float) -> void:
		pass

	## Fin de bataille : ONGOING, WON ou LOST (end_message expliqué au joueur).
	func check(sim: BattleSim) -> int:
		return broken(sim, "L'ennemi est en déroute. Victoire !")

	## Règle commune : compagnie brisée = défaite ; ennemi brisé = victoire (avec win_text).
	func broken(sim: BattleSim, win_text: String) -> int:
		var st := BattleObjectives.standing(sim)
		if not st[0]:
			end_message = "Votre compagnie est brisée..."
			return BattleObjectives.LOST
		if not st[1]:
			end_message = win_text
			return BattleObjectives.WON
		return BattleObjectives.ONGOING

	## Panneau d'objectif dans le HUD (inutile pour « détruire l'ennemi »).
	func shows_panel() -> bool:
		return false

	## Ligne d'état du panneau (chronomètre, chariots, fuyards).
	func status(_sim: BattleSim) -> String:
		return ""

	## Barre de progression vers la victoire, de 0 à 1 (-1 : pas de barre).
	func progress(_sim: BattleSim) -> float:
		return -1.0

	## Jauge du danger de défaite, de 0 à 1 (-1 : pas de jauge).
	func danger(_sim: BattleSim) -> float:
		return -1.0

	func draw(_ci: CanvasItem, _sim: BattleSim) -> void:
		pass

	func ai_plan() -> String:
		return ""

	func ai_point(_sim: BattleSim, _r: Regiment) -> Vector2:
		return Vector2.INF

	func ai_anchor(_sim: BattleSim) -> Vector2:
		return Vector2.INF

	func ai_counterattacks() -> bool:
		return true

	## Bilan : sorte, nom, phrase de résumé, réussite ; les sous-classes ajoutent leurs chiffres.
	func result(sim: BattleSim) -> Dictionary:
		return {"kind": kind, "label": label(), "summary": summary(sim), "success": sim.state == BattleSim.State.VICTORY}

	func summary(_sim: BattleSim) -> String:
		return ""


# ================================================================ Détruire l'ennemi

class Destroy extends Objective:
	func configure() -> void:
		kind = "destroy"


# ================================================================ Tenir une position

## Une zone marquée au sol, à tenir params["time"] secondes. Si l'ennemi l'occupe seul
## params["loss"] secondes (cumulées, la jauge redescend quand on la reprend), c'est perdu.
class Hold extends Objective:
	const RADIUS := 130.0
	var time := 180.0
	var loss := 30.0
	var center := Vector2.INF
	var elapsed := 0.0
	var enemy_hold := 0.0
	var p_in := 0
	var e_in := 0

	func configure() -> void:
		kind = "hold"
		time = maxf(float(params.get("time", 180.0)), 10.0)
		loss = maxf(float(params.get("loss", 30.0)), 5.0)

	func briefing() -> String:
		return "Objectif : tenir la position marquée pendant %s. Ne la laissez pas à l'ennemi !" % BattleObjectives.duration_words(time)

	func allowed_terrains() -> Array[String]:
		return ["plain", "forest", "hills", "village"]

	## La position : la colline la plus centrale, la place du village, sinon le milieu de la route.
	func setup(sim: BattleSim) -> void:
		var mid := BattleObjectives.middle(sim)
		center = mid
		var t := sim.terrain
		if t.kind == "village" and t.village_rect.has_area():
			var x := t.village_rect.get_center().x
			center = Vector2(x, sim.road_y(x))
		else:
			var best := INF
			for top in t.hill_tops():
				var d := top.distance_to(mid)
				if d < best and top.y > 650.0 and top.y < 1300.0:
					best = d
					center = top

	func step(sim: BattleSim, dt: float) -> void:
		elapsed += dt
		p_in = BattleObjectives.men_in(sim, BattleSim.PLAYER, center, RADIUS)
		e_in = BattleObjectives.men_in(sim, BattleSim.ENEMY, center, RADIUS)
		if e_in >= BattleObjectives.MIN_MEN and p_in == 0:
			if enemy_hold <= 0.0:
				sim.message("L'ennemi occupe la position : reprenez-la !")
			enemy_hold += dt
		elif p_in > 0:
			enemy_hold = maxf(enemy_hold - dt * 0.5, 0.0)

	func check(sim: BattleSim) -> int:
		var st := BattleObjectives.standing(sim)
		if not st[0]:
			end_message = "Votre compagnie est brisée..."
			return BattleObjectives.LOST
		if enemy_hold >= loss:
			end_message = "L'ennemi s'est emparé de la position. Le contrat est perdu..."
			return BattleObjectives.LOST
		if elapsed >= time:
			end_message = "La position a tenu ! Victoire !"
			return BattleObjectives.WON
		if not st[1]:
			end_message = "L'ennemi est en déroute : la position est à vous. Victoire !"
			return BattleObjectives.WON
		return BattleObjectives.ONGOING

	func shows_panel() -> bool:
		return true

	func status(_sim: BattleSim) -> String:
		var s := "Tenir encore %s" % BattleObjectives.clock(time - elapsed)
		if e_in >= BattleObjectives.MIN_MEN and p_in == 0:
			s += "  —  l'ennemi tient la position !"
		elif p_in > 0 and e_in > 0:
			s += "  —  position disputée"
		elif p_in > 0:
			s += "  —  position tenue"
		return s

	func progress(_sim: BattleSim) -> float:
		return clampf(elapsed / time, 0.0, 1.0)

	func danger(_sim: BattleSim) -> float:
		return clampf(enemy_hold / loss, 0.0, 1.0)

	func draw(ci: CanvasItem, _sim: BattleSim) -> void:
		var col := BattleObjectives.NEUTRAL_ZONE
		if p_in > 0 and e_in < BattleObjectives.MIN_MEN:
			col = BattleObjectives.PLAYER_ZONE
		elif e_in >= BattleObjectives.MIN_MEN and p_in == 0:
			col = BattleObjectives.ENEMY_ZONE
		BattleObjectives.draw_zone(ci, center, RADIUS, col, elapsed / time)

	func ai_plan() -> String:
		return EnemyAI.AGGRESSIVE

	## L'infanterie ennemie marche sur la position (la cavalerie garde son rôle).
	func ai_point(_sim: BattleSim, r: Regiment) -> Vector2:
		if r.stats["mounted"] or r.stats["ranged"]:
			return Vector2.INF
		return center

	func result(sim: BattleSim) -> Dictionary:
		var out := super(sim)
		out.merge({"time": time, "elapsed": elapsed, "enemy_hold": enemy_hold})
		return out

	func summary(sim: BattleSim) -> String:
		if sim.state == BattleSim.State.VICTORY:
			return "Position tenue (%s)" % BattleObjectives.duration_words(minf(elapsed, time))
		if enemy_hold >= loss:
			return "Position perdue après %s" % BattleObjectives.duration_words(elapsed)
		return "Position abandonnée après %s" % BattleObjectives.duration_words(elapsed)


# ================================================================ Escorter un convoi

## Des chariots suivent la route d'ouest en est ; params["need"] doivent arriver. L'ennemi qui
## est au contact d'un chariot l'abîme (et arrête tout le convoi) ; à 0, le chariot est perdu.
class Escort extends Objective:
	const START_X := 90.0
	const END_X := 3110.0
	const SPACING := 64.0
	const SPEED := 22.0 ## Pixels par seconde
	const HP := 160.0
	const REACH := 40.0 ## Un ennemi à cette distance d'un chariot l'attaque
	const MAX_ATTACKERS := 10
	var count := 4
	var need := 2
	var wagons: Array[Dictionary] = [] ## {"x", "pos", "hp", "state" ("road", "arrived", "lost")}
	var halted := false
	var road: Callable

	func configure() -> void:
		kind = "escort"
		ai_engage = 150.0
		count = clampi(int(params.get("wagons", 4)), 1, 8)
		need = clampi(int(params.get("need", ceili(count * 0.5))), 1, count)

	func briefing() -> String:
		return "Objectif : escorter le convoi (%d chariots) jusqu'à l'est de la carte ; %d au moins doivent passer." % [count, need]

	func allowed_terrains() -> Array[String]:
		return ["plain", "forest", "hills"]

	func setup(sim: BattleSim) -> void:
		road = sim.road_y
		wagons.clear()
		for i in count:
			var x := START_X + SPACING * (count - 1 - i)
			wagons.append({"x": x, "pos": Vector2(x, sim.road_y(x)), "hp": HP, "state": "road"})

	func step(sim: BattleSim, dt: float) -> void:
		halted = false
		for w in wagons:
			if w["state"] != "road":
				continue
			var dps := 0.0
			var n := 0
			for s in sim.soldiers_near(w["pos"], REACH):
				if s.regiment.team != BattleSim.ENEMY or s.regiment.routing:
					continue
				dps += float(s.regiment.stats["damage"]) / float(s.regiment.stats["cooldown"]) * s.regiment.rank_damage()
				n += 1
				if n >= MAX_ATTACKERS:
					break
			if n > 0:
				halted = true
				w["hp"] = float(w["hp"]) - dps * dt
				if float(w["hp"]) <= 0.0:
					w["hp"] = 0.0
					w["state"] = "lost"
					sim.message("Un chariot du convoi est détruit ! (%d perdus)" % lost())
		if halted:
			return # Le convoi s'arrête tant qu'un chariot est attaqué
		for w in wagons:
			if w["state"] != "road":
				continue
			w["x"] = float(w["x"]) + SPEED * dt
			w["pos"] = Vector2(w["x"], sim.road_y(w["x"]))
			if float(w["x"]) >= END_X:
				w["state"] = "arrived"
				sim.message("Un chariot arrive à bon port (%d sur %d)." % [arrived(), count])

	func arrived() -> int:
		return wagons.filter(func(w): return w["state"] == "arrived").size()

	func lost() -> int:
		return wagons.filter(func(w): return w["state"] == "lost").size()

	func on_road() -> int:
		return wagons.filter(func(w): return w["state"] == "road").size()

	func check(sim: BattleSim) -> int:
		var st := BattleObjectives.standing(sim)
		if not st[0]:
			end_message = "Votre compagnie est brisée : le convoi est livré à l'ennemi..."
			return BattleObjectives.LOST
		if count - lost() < need:
			end_message = "Trop de chariots sont perdus : le convoi a échoué..."
			return BattleObjectives.LOST
		if on_road() == 0:
			end_message = "Le convoi est passé (%d chariots sur %d). Victoire !" % [arrived(), count]
			return BattleObjectives.WON
		if not st[1]:
			end_message = "L'ennemi est en déroute : la route est libre pour le convoi. Victoire !"
			return BattleObjectives.WON
		return BattleObjectives.ONGOING

	func shows_panel() -> bool:
		return true

	func status(_sim: BattleSim) -> String:
		var s := "Arrivés %d · en route %d · perdus %d (il en faut %d)" % [arrived(), on_road(), lost(), need]
		if halted:
			s += "  —  attaqué !"

		return s

	## Chemin parcouru par le convoi (les chariots perdus ne comptent pas).
	func progress(_sim: BattleSim) -> float:
		var sum := 0.0
		for w in wagons:
			match str(w["state"]):
				"arrived":
					sum += 1.0
				"road":
					sum += clampf((float(w["x"]) - START_X) / (END_X - START_X), 0.0, 1.0)
		return sum / maxf(count, 1)

	func danger(_sim: BattleSim) -> float:
		return clampf(float(lost()) / float(count - need + 1), 0.0, 1.0)

	func draw(ci: CanvasItem, sim: BattleSim) -> void:
		# Arrivée : un poteau et un fanion bleu au bout de la route
		var goal := Vector2(END_X, sim.road_y(END_X))
		ci.draw_line(goal + Vector2(0, 26), goal + Vector2(0, -30), Color(0.3, 0.22, 0.12), 3.0)
		ci.draw_colored_polygon(PackedVector2Array([goal + Vector2(2, -30), goal + Vector2(22, -24), goal + Vector2(2, -18)]), BattleObjectives.PLAYER_ZONE)
		for w in wagons:
			if w["state"] == "arrived":
				continue
			var p: Vector2 = w["pos"]
			if w["state"] == "lost":
				ci.draw_rect(Rect2(p + Vector2(-12, -4), Vector2(24, 8)), Color(0.18, 0.13, 0.09))
				ci.draw_rect(Rect2(p + Vector2(-6, -9), Vector2(10, 5)), Color(0.12, 0.1, 0.08))
				continue
			ci.draw_rect(Rect2(p + Vector2(-13, -6), Vector2(26, 10)), Color(0.45, 0.3, 0.16)) # Caisse
			ci.draw_rect(Rect2(p + Vector2(-11, -15), Vector2(22, 9)), Color(0.88, 0.84, 0.72)) # Bâche
			ci.draw_rect(Rect2(p + Vector2(-11, -15), Vector2(22, 9)), Color(0.55, 0.5, 0.4), false, 1.0)
			for wx in [-8.0, 8.0]:
				ci.draw_circle(p + Vector2(wx, 5), 3.5, Color(0.2, 0.14, 0.08))
			ci.draw_rect(Rect2(p + Vector2(13, -3), Vector2(8, 2)), Color(0.35, 0.24, 0.12)) # Timon
			var hp := float(w["hp"]) / HP
			if hp < 1.0:
				ci.draw_rect(Rect2(p + Vector2(-13, -21), Vector2(26, 3)), Color(0, 0, 0, 0.6))
				ci.draw_rect(Rect2(p + Vector2(-13, -21), Vector2(26 * hp, 3)), Color(1, 0.75, 0.3).lerp(Color(1, 0.2, 0.15), 1.0 - hp))

	func ai_plan() -> String:
		return EnemyAI.AGGRESSIVE

	## Infanterie et cavalerie (pas les tireurs) vont au chariot le plus proche.
	func ai_point(_sim: BattleSim, r: Regiment) -> Vector2:
		if r.stats["ranged"]:
			return Vector2.INF
		var best := Vector2.INF
		var bd := INF
		for w in wagons:
			if w["state"] != "road":
				continue
			var d := r.center.distance_to(w["pos"])
			if d < bd:
				bd = d
				best = w["pos"]
		return best

	func result(sim: BattleSim) -> Dictionary:
		var out := super(sim)
		out.merge({"wagons": count, "need": need, "arrived": arrived(), "lost": lost(),
			"saved": count - lost() if sim.state == BattleSim.State.VICTORY else arrived()})
		return out

	func summary(sim: BattleSim) -> String:
		var saved: int = count - lost() if sim.state == BattleSim.State.VICTORY else arrived()
		return "Chariots sauvés : %d sur %d (%d perdus)" % [saved, count, lost()]


# ================================================================ Prendre un village

## La place du village est défendue ; il faut l'occuper seul (params["hold"] secondes cumulées)
## avant params["time"] secondes. L'ennemi qui y revient seul fait redescendre la jauge.
class Capture extends Objective:
	const RADIUS := 120.0
	var time := 360.0
	var hold := 25.0
	var center := Vector2.INF
	var elapsed := 0.0
	var taken := 0.0 ## Prise de la place, de 0 à 1
	var p_in := 0
	var e_in := 0

	func configure() -> void:
		kind = "capture"
		time = maxf(float(params.get("time", 360.0)), 30.0)
		hold = maxf(float(params.get("hold", 25.0)), 3.0)

	func briefing() -> String:
		return "Objectif : chassez la garnison et occupez la place du village avant la nuit (%s)." % BattleObjectives.duration_words(time)

	func allowed_terrains() -> Array[String]:
		return ["village"]

	## La place, sur la route au milieu du village ; la garnison s'y poste dès le déploiement.
	func setup(sim: BattleSim) -> void:
		center = BattleObjectives.middle(sim)
		var t := sim.terrain
		if t.village_rect.has_area():
			var x := t.village_rect.get_center().x
			center = Vector2(x, sim.road_y(x))
		var foot: Array[Regiment] = []
		var archers: Array[Regiment] = []
		var horse: Array[Regiment] = []
		for r in sim.regiments:
			if r.team != BattleSim.ENEMY:
				continue
			if r.stats["mounted"]:
				horse.append(r)
			elif r.stats["ranged"]:
				archers.append(r)
			else:
				foot.append(r)
		BattleObjectives.place_row(foot, center + Vector2(0, 70), Vector2.DOWN, 140.0)
		BattleObjectives.place_row(archers, center + Vector2(0, -50), Vector2.DOWN, 150.0)
		BattleObjectives.place_row(horse, center + Vector2(0, -260), Vector2.DOWN, 420.0)

	func step(sim: BattleSim, dt: float) -> void:
		elapsed += dt
		p_in = BattleObjectives.men_in(sim, BattleSim.PLAYER, center, RADIUS)
		e_in = BattleObjectives.men_in(sim, BattleSim.ENEMY, center, RADIUS)
		if p_in >= BattleObjectives.MIN_MEN and e_in == 0:
			if taken <= 0.0:
				sim.message("Vos hommes entrent sur la place du village !")
			taken = minf(taken + dt / hold, 1.0)
		elif e_in > 0 and p_in == 0:
			taken = maxf(taken - dt / hold * 0.5, 0.0)

	func check(sim: BattleSim) -> int:
		var st := BattleObjectives.standing(sim)
		if not st[0]:
			end_message = "Votre compagnie est brisée..."
			return BattleObjectives.LOST
		if taken >= 1.0:
			end_message = "Le village est à vous ! Victoire !"
			return BattleObjectives.WON
		if not st[1]:
			end_message = "La garnison est en déroute : le village est à vous. Victoire !"
			return BattleObjectives.WON
		if elapsed >= time:
			end_message = "La nuit tombe : le village reste aux mains de l'ennemi..."
			return BattleObjectives.LOST
		return BattleObjectives.ONGOING

	func shows_panel() -> bool:
		return true

	func status(_sim: BattleSim) -> String:
		var s := "Place prise à %d %%  —  nuit dans %s" % [int(taken * 100.0), BattleObjectives.clock(time - elapsed)]
		if p_in > 0 and e_in > 0:
			s += "  —  on se bat sur la place"
		return s

	func progress(_sim: BattleSim) -> float:
		return taken

	func danger(_sim: BattleSim) -> float:
		return clampf(elapsed / time, 0.0, 1.0)

	func draw(ci: CanvasItem, _sim: BattleSim) -> void:
		var col := BattleObjectives.ENEMY_ZONE
		if p_in >= BattleObjectives.MIN_MEN and e_in == 0:
			col = BattleObjectives.PLAYER_ZONE
		elif p_in > 0:
			col = BattleObjectives.NEUTRAL_ZONE
		BattleObjectives.draw_zone(ci, center, RADIUS, col, taken)

	func ai_plan() -> String:
		return EnemyAI.DEFENSIVE

	func ai_anchor(_sim: BattleSim) -> Vector2:
		return center

	func ai_counterattacks() -> bool:
		return false

	func result(sim: BattleSim) -> Dictionary:
		var out := super(sim)
		out.merge({"time": time, "elapsed": elapsed, "taken": taken})
		return out

	func summary(sim: BattleSim) -> String:
		if sim.state == BattleSim.State.VICTORY:
			return "Village pris en %s" % BattleObjectives.duration_words(elapsed)
		return "Place prise à %d %% seulement" % int(taken * 100.0)


# ================================================================ Poursuivre une bande en fuite

## La bande ennemie, chargée de butin (donc lente), fuit vers le nord. Les régiments qui atteignent
## le bord s'échappent ; si params["escape"] de ses hommes s'échappent, c'est perdu.
class Pursue extends Objective:
	const START_Y := 1040.0 ## Hauteur de la bande au début de la bataille
	const EXIT_Y := 70.0 ## Au-delà, un régiment a quitté la carte
	const LOOT_SLOW := 0.55 ## Vitesse des fantassins chargés de butin
	const LOOT_SLOW_MOUNTED := 0.7
	var escape := 0.5
	var initial := 0
	var escaped := 0

	func configure() -> void:
		kind = "pursue"
		escape = clampf(float(params.get("escape", 0.5)), 0.1, 1.0)

	func briefing() -> String:
		return "Objectif : la bande fuit vers le nord avec son butin. Rattrapez-la avant que la moitié de ses hommes ne s'échappe !" \
			if is_equal_approx(escape, 0.5) else "Objectif : rattrapez la bande avant qu'elle ne quitte la carte par le nord !"

	func allowed_terrains() -> Array[String]:
		return ["plain", "forest", "hills"]

	## La bande est déjà en route : plus près du joueur, face au nord, ralentie par son butin.
	func setup(sim: BattleSim) -> void:
		initial = 0
		for r in sim.regiments:
			if r.team != BattleSim.ENEMY:
				continue
			r.speed_mult = LOOT_SLOW_MOUNTED if r.stats["mounted"] else LOOT_SLOW
			BattleObjectives.place(r, Vector2(r.center.x, START_Y + (r.center.y - 400.0) * 0.6), Vector2.UP)
			initial += r.alive_n

	## Un régiment debout qui atteint le bord nord s'échappe (il ne reviendra pas).
	func step(sim: BattleSim, _dt: float) -> void:
		for r in sim.regiments:
			if r.team != BattleSim.ENEMY or r.is_dead() or r.routing or r.center.y > EXIT_Y:
				continue
			escaped += r.alive_n
			r.routing = true
			r.rallied_once = true
			r.morale = 0.0
			r.target = null
			r.fire_target = null
			sim.message("%d pillards s'échappent avec leur butin ! (%d sur %d)" % [r.alive_n, escaped, initial])

	func limit() -> int:
		return maxi(1, ceili(initial * escape))

	func check(sim: BattleSim) -> int:
		var st := BattleObjectives.standing(sim)
		if not st[0]:
			end_message = "Votre compagnie est brisée..."
			return BattleObjectives.LOST
		if escaped >= limit():
			end_message = "La bande s'est échappée avec son butin. Le contrat est perdu..."
			return BattleObjectives.LOST
		if not st[1]:
			end_message = "La bande est rattrapée et dispersée ! Victoire !"
			return BattleObjectives.WON
		return BattleObjectives.ONGOING

	func shows_panel() -> bool:
		return true

	func status(sim: BattleSim) -> String:
		var running := 0
		for r in sim.regiments:
			if r.team == BattleSim.ENEMY and not r.is_dead() and not r.routing:
				running += r.alive_n
		return "%d pillards en fuite, %d échappés (limite %d)" % [running, escaped, limit()]

	## Part de la bande arrêtée (tombée ou dispersée).
	func progress(sim: BattleSim) -> float:
		var running := 0
		for r in sim.regiments:
			if r.team == BattleSim.ENEMY and not r.is_dead() and not r.routing:
				running += r.alive_n
		return clampf(1.0 - float(running + escaped) / maxf(initial, 1), 0.0, 1.0)

	func danger(_sim: BattleSim) -> float:
		return clampf(float(escaped) / float(limit()), 0.0, 1.0)

	func draw(ci: CanvasItem, _sim: BattleSim) -> void:
		# Ligne de fuite au nord : tirets rouges et flèches
		var col := Color(BattleObjectives.ENEMY_ZONE, 0.7)
		var x := 0.0
		while x < BattleSim.WORLD_SIZE.x:
			ci.draw_line(Vector2(x, EXIT_Y), Vector2(x + 24.0, EXIT_Y), col, 3.0)
			x += 40.0
		x = 160.0
		while x < BattleSim.WORLD_SIZE.x:
			var p := Vector2(x, EXIT_Y + 30.0)
			ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-8, 0), p + Vector2(0, -12), p + Vector2(8, 0)]), col)
			x += 320.0

	func ai_plan() -> String:
		return EnemyAI.FLEE

	func result(sim: BattleSim) -> Dictionary:
		var out := super(sim)
		out.merge({"initial": initial, "escaped": escaped, "limit": limit()})
		return out

	func summary(_sim: BattleSim) -> String:
		return "Pillards échappés : %d sur %d (limite %d)" % [escaped, initial, limit()]
