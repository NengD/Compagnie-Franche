class_name BattleWeather
extends RefCounted
## Météo de la bataille et ses effets (fonctions statiques sur la simulation, battle_sim.gd).
##  - pluie : les arcs portent moins loin, visent moins juste et frappent moins fort ; les arbalètes
##    (« pierce » > 0) en souffrent moins. La pluie détrempe le sol : la boue (sim.mud, de 0 à 1)
##    monte avec le temps de pluie (pleine d'emblée en campagne, où il pleut depuis le matin) ;
##  - boue : tout le monde marche moins vite, la cavalerie bien plus, et les charges perdent leur élan ;
##  - brouillard : au-delà de FOG_CLEAR, un régiment adverse s'estompe ; au-delà de FOG_SIGHT, il
##    disparaît (r.fogged) : ni affiché, ni ciblé, ni visé par les tireurs, pour l'IA comme pour le joueur ;
##  - vent (sim.wind, vecteur, longueur 0 à 1) : il allonge les tirs qui le suivent, raccourcit ceux
##    qui le remontent et fait dériver les flèches.
## Rien ici ne tire dans sim.rng (graines fixes des tests et du banc).

const KINDS: Array[String] = ["clear", "rain", "fog", "wind"] ## Cycle de la touche météo (escarmouche)

## Pluie : [arcs, arbalètes]
const RAIN_RANGE := [0.7, 0.9] ## Portée
const RAIN_DAMAGE := [0.75, 0.92] ## Dégâts des traits
const RAIN_SPREAD := [1.8, 1.3] ## Dispersion
## Boue
const MUD_TIME := 40.0 ## Secondes de pluie pour une boue pleine
const DRY_TIME := 180.0 ## Secondes de temps sec pour qu'elle sèche
const MUD_SPEED_FOOT := 0.88 ## Vitesse des fantassins dans une boue pleine (x)
const MUD_SPEED_HORSE := 0.7 ## Vitesse des montés dans une boue pleine (x)
const MUD_CHARGE := 0.5 ## Bonus de charge restant dans une boue pleine (x)
const MUD_RUN_DRAIN := 0.5 ## Course : endurance perdue en plus dans une boue pleine (+50 %)
## Brouillard
const FOG_CLEAR := 220.0 ## En deçà, on voit l'adversaire nettement
const FOG_SIGHT := 380.0 ## Au-delà, on ne le voit plus du tout
## Vent
const WIND_RANGE := 0.15 ## Portée gagnée (ou perdue) en tirant vent arrière (ou de face), vent fort
const WIND_DRIFT := 0.06 ## Dérive des flèches : part de la distance, vent fort


## Règle la météo d'après un dictionnaire {"rain", "fog", "wind"} (WorldSim.battle_weather) ;
## wind : composante verticale (> 0 : le vent souffle vers le sud, au visage du joueur).
static func apply(sim: BattleSim, w: Dictionary) -> void:
	sim.raining = bool(w.get("rain", false))
	sim.fog = bool(w.get("fog", false)) and not sim.raining
	sim.wind = Vector2(0.0, clampf(float(w.get("wind", 0.0)), -1.0, 1.0))
	sim.mud = 1.0 if sim.raining else 0.0 # Il pleut depuis le matin : le sol est détrempé


## Temps dominant : « clear », « rain », « fog » ou « wind ».
static func kind(sim: BattleSim) -> String:
	if sim.raining:
		return "rain"
	if sim.fog:
		return "fog"
	if sim.wind.length() > 0.05:
		return "wind"
	return "clear"


## Touche météo de l'escarmouche : temps suivant (clair → pluie → brouillard → vent → clair).
## Renvoie le message à afficher.
static func cycle(sim: BattleSim) -> String:
	var next := KINDS[(KINDS.find(kind(sim)) + 1) % KINDS.size()]
	sim.raining = next == "rain"
	sim.fog = next == "fog"
	sim.wind = Vector2(0, 0.8) if next == "wind" else Vector2.ZERO
	match next:
		"rain":
			return "Il pleut : les arcs portent moins loin, le sol va se changer en boue."
		"fog":
			return "Le brouillard tombe : on ne voit plus l'ennemi au-delà de quelques centaines de pas."
		"wind":
			return "Le vent se lève, de face : vos flèches portent moins loin, celles de l'ennemi plus loin."
	return "Le temps se dégage."


## Avance la météo de dt : la boue monte sous la pluie, sèche sinon ; visibilité dans le brouillard.
static func step(sim: BattleSim, dt: float) -> void:
	if sim.raining:
		sim.mud = minf(sim.mud + dt / MUD_TIME, 1.0)
	else:
		sim.mud = maxf(sim.mud - dt / DRY_TIME, 0.0)
	update_fog(sim)


## Visibilité de chaque régiment pour le camp adverse (r.fog_alpha, r.fogged).
static func update_fog(sim: BattleSim) -> void:
	for r in sim.regiments:
		if not sim.fog or r.is_dead():
			r.fog_alpha = 1.0
			r.fogged = false
			continue
		var d := INF
		for o in sim.regiments:
			if o.team != r.team and not o.is_dead() and not o.routing:
				d = minf(d, r.center.distance_to(o.center))
		r.fog_alpha = fog_alpha(d)
		r.fogged = r.fog_alpha <= 0.0


## Netteté d'un régiment vu à la distance d (1 : net, 0 : invisible).
static func fog_alpha(d: float) -> float:
	return clampf((FOG_SIGHT - d) / (FOG_SIGHT - FOG_CLEAR), 0.0, 1.0)


## 1 pour une arme qui craint peu la pluie (arbalète : « pierce » > 0), 0 pour un arc.
static func wet_resist(r: Regiment) -> int:
	return 1 if float(r.stats.get("pierce", 0.0)) > 0.0 else 0


## Multiplicateur de portée d'un tir de r vers le point to (pluie, vent).
static func range_factor(sim: BattleSim, r: Regiment, to: Vector2) -> float:
	var f := 1.0
	if sim.raining:
		f *= float(RAIN_RANGE[wet_resist(r)])
	if sim.wind != Vector2.ZERO and to != r.center:
		f *= 1.0 + WIND_RANGE * sim.wind.dot((to - r.center).normalized())
	return f


## Multiplicateur des dégâts des traits de r.
static func damage_factor(sim: BattleSim, r: Regiment) -> float:
	return float(RAIN_DAMAGE[wet_resist(r)]) if sim.raining else 1.0


## Multiplicateur de la dispersion des traits de r.
static func spread_factor(sim: BattleSim, r: Regiment) -> float:
	var f := float(RAIN_SPREAD[wet_resist(r)]) if sim.raining else 1.0
	return f * (1.0 + sim.wind.length() * 0.3)


## Dérive d'une flèche tirée à la distance dist.
static func drift(sim: BattleSim, dist: float) -> Vector2:
	return sim.wind * dist * WIND_DRIFT


## Multiplicateur de vitesse dû à la boue.
static func speed_factor(sim: BattleSim, r: Regiment) -> float:
	return lerpf(1.0, MUD_SPEED_HORSE if r.stats["mounted"] else MUD_SPEED_FOOT, sim.mud)


## Multiplicateur du bonus de charge dû à la boue.
static func charge_factor(sim: BattleSim) -> float:
	return lerpf(1.0, MUD_CHARGE, sim.mud)


## Multiplicateur de l'endurance perdue à la course.
static func run_drain_factor(sim: BattleSim) -> float:
	return 1.0 + MUD_RUN_DRAIN * sim.mud


## Nom court pour la barre du haut (« Pluie, boue », « Brouillard », « Vent de face »...).
static func label(sim: BattleSim) -> String:
	var parts: Array[String] = []
	match kind(sim):
		"rain":
			parts.append("Pluie")
		"fog":
			parts.append("Brouillard")
		"clear":
			if sim.mud <= 0.2:
				parts.append("Temps clair")
	if sim.mud > 0.2 and not sim.raining:
		parts.append("Sol boueux")
	elif sim.mud > 0.2:
		parts.append("boue")
	if sim.wind.length() > 0.05:
		parts.append(wind_text(sim))
	return ", ".join(parts)


## « Vent de face » / « vent dans le dos » (du point de vue du joueur, qui tire vers le haut).
static func wind_text(sim: BattleSim) -> String:
	return "vent de face" if sim.wind.y > 0.0 else "vent dans le dos"


## Effets en cours, en clair (HUD, message de début de bataille).
static func effects(sim: BattleSim) -> Array[String]:
	var out: Array[String] = []
	if sim.raining:
		out.append("arcs -%d %% de portée (arbalètes -%d %%)" % [roundi((1.0 - RAIN_RANGE[0]) * 100.0), roundi((1.0 - RAIN_RANGE[1]) * 100.0)])
	if sim.mud > 0.2:
		out.append("boue : cavalerie et charges ralenties")
	if sim.fog:
		out.append("brouillard : ennemi invisible au-delà de %d pas" % roundi(FOG_SIGHT))
	if sim.wind.length() > 0.05:
		out.append("%s : vos flèches portent %s" % [wind_text(sim), "moins loin" if sim.wind.y > 0.0 else "plus loin"])
	return out


## Message de début de bataille (vide par temps clair).
static func briefing(sim: BattleSim) -> String:
	var e := effects(sim)
	if e.is_empty():
		return ""
	return "Météo : %s (%s)." % [label(sim).to_lower(), " ; ".join(e)]
