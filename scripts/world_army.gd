class_name WorldArmy
extends Party
## Armée d'une faction sur la carte de campagne (voir world_sim.gd) : un groupe (Party) de sorte
## « army » qui marche de ville en ville par les routes, assiège les villes ennemies et livre
## bataille aux armées ennemies. Aucune donnée de rendu : la carte la dessine d'après pos, faction
## et force.
##
## L'effectif est abstrait (« force » : une armée de 300 hommes donne une bataille d'environ
## 8 régiments) ; men() le renvoie, et troops en donne une image en régiments (sync_troops) pour
## les modules qui lisent n'importe quel groupe (rencontres).

const MODES := ["march", "patrol", "siege", "retreat"]

var force := 0 ## Effectif (sauvegardé sous la clé « men »)
var route: Array[int] = [] ## Prochaines villes à atteindre, dans l'ordre (la dernière est le but)
var target := -1 ## Ville visée (attaque, patrouille ou repli)
var mode := "march" ## « march » (attaque), « patrol » (en paix), « siege », « retreat » (repli)
var siege_days := 0 ## Jours de siège devant la ville visée


func _init() -> void:
	kind = "army"


## Effectif (abstrait) de l'armée.
func men() -> int:
	return force


func strength() -> float:
	return float(force)


## Image de l'armée en régiments (d'après WorldSim.ARMY_TYPES), pour les modules génériques.
func sync_troops() -> void:
	troops.clear()
	var types: Array = WorldSim.ARMY_TYPES[clampi(faction, 0, WorldSim.ARMY_TYPES.size() - 1)]
	var n := clampi(int(round(force / 40.0)), 1, types.size())
	var left := force
	for i in n:
		var m := left if i == n - 1 else force / n
		left -= m
		troops.append({"type": str(types[i]), "men": maxi(0, m), "xp": 50.0})


## Avance de speed pixels le long de la route. Renvoie vrai si l'armée est arrivée au but.
func step(speed: float) -> bool:
	var left := speed
	while not route.is_empty() and left > 0.0:
		var goal: Vector2 = CampaignState.TOWNS[route[0]]["pos"]
		var d := pos.distance_to(goal)
		if d <= left:
			pos = goal
			left -= d
			route.remove_at(0)
		else:
			pos = pos.move_toward(goal, left)
			left = 0.0
	return route.is_empty()


## Ville où se trouve l'armée (-1 si elle est sur une route).
func town_here() -> int:
	for i in CampaignState.TOWNS.size():
		if pos.distance_to(CampaignState.TOWNS[i]["pos"]) < 1.0:
			return i
	return -1


## « l'armée du Comté » (avec l'article de la faction).
func display_name() -> String:
	return "l'armée de %s" % str(CampaignState.FACTIONS[faction]["short"])


## Ce que fait l'armée, pour l'infobulle de la carte.
func doing() -> String:
	var where := str(CampaignState.TOWNS[target]["name"]) if target >= 0 else "?"
	match mode:
		"siege":
			return "assiège %s depuis %s" % [where, CampaignState.plural(siege_days, "jour", "jours")]
		"patrol":
			return "patrouille vers %s" % where
		"retreat":
			return "se replie sur %s" % where
	return "marche sur %s" % where


func to_dict() -> Dictionary:
	return {"id": id, "faction": faction, "men": force, "x": pos.x, "y": pos.y,
		"path": Array(route), "target": target, "mode": mode, "siege_days": siege_days}


## Relit une armée sauvegardée. Renvoie null si elle est invalide. pos_scale : agrandissement des
## positions (MapData.SCALE pour une sauvegarde d'avant la grande carte, version 8 et avant).
static func army_from_dict(d: Variant, pos_scale := 1.0) -> WorldArmy:
	if not d is Dictionary:
		return null
	var a := WorldArmy.new()
	a.id = int(d.get("id", 0))
	a.faction = int(d.get("faction", -1))
	a.force = int(d.get("men", 0))
	a.pos = Vector2(float(d.get("x", 0.0)), float(d.get("y", 0.0))) * pos_scale
	a.target = int(d.get("target", -1))
	a.mode = str(d.get("mode", "march"))
	a.siege_days = maxi(0, int(d.get("siege_days", 0)))
	if a.faction < 0 or a.faction >= CampaignState.FACTIONS.size() or a.force <= 0 or not a.mode in MODES:
		return null
	if a.target < -1 or a.target >= CampaignState.TOWNS.size():
		return null
	for t in d.get("path", []):
		var i := int(t)
		if i < 0 or i >= CampaignState.TOWNS.size():
			return null
		a.route.append(i)
	a.sync_troops()
	return a
