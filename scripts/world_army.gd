class_name WorldArmy
extends RefCounted
## Armée d'une faction sur la carte de campagne (voir world_sim.gd) : elle marche de ville en
## ville par les routes, assiège les villes ennemies et livre bataille aux armées ennemies.
## Aucune donnée de rendu : la carte la dessine d'après pos, faction et men.

const MODES := ["march", "patrol", "siege", "retreat"]

var id := 0
var faction := 0
var men := 0 ## Effectif (abstrait : une armée de 300 hommes donne une bataille d'environ 8 régiments)
var pos := Vector2.ZERO ## Position sur la carte (mêmes coordonnées que CampaignState.TOWNS)
var path: Array[int] = [] ## Prochaines villes à atteindre, dans l'ordre (la dernière est le but)
var target := -1 ## Ville visée (attaque, patrouille ou repli)
var mode := "march" ## « march » (attaque), « patrol » (en paix), « siege », « retreat » (repli)
var siege_days := 0 ## Jours de siège devant la ville visée


## Avance de speed pixels le long du chemin. Renvoie vrai si l'armée est arrivée au but.
func step(speed: float) -> bool:
	var left := speed
	while not path.is_empty() and left > 0.0:
		var goal: Vector2 = CampaignState.TOWNS[path[0]]["pos"]
		var d := pos.distance_to(goal)
		if d <= left:
			pos = goal
			left -= d
			path.remove_at(0)
		else:
			pos = pos.move_toward(goal, left)
			left = 0.0
	return path.is_empty()


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
	return {"id": id, "faction": faction, "men": men, "x": pos.x, "y": pos.y,
		"path": Array(path), "target": target, "mode": mode, "siege_days": siege_days}


## Relit une armée sauvegardée. Renvoie null si elle est invalide.
static func from_dict(d: Variant) -> WorldArmy:
	if not d is Dictionary:
		return null
	var a := WorldArmy.new()
	a.id = int(d.get("id", 0))
	a.faction = int(d.get("faction", -1))
	a.men = int(d.get("men", 0))
	a.pos = Vector2(float(d.get("x", 0.0)), float(d.get("y", 0.0)))
	a.target = int(d.get("target", -1))
	a.mode = str(d.get("mode", "march"))
	a.siege_days = maxi(0, int(d.get("siege_days", 0)))
	if a.faction < 0 or a.faction >= CampaignState.FACTIONS.size() or a.men <= 0 or not a.mode in MODES:
		return null
	if a.target < -1 or a.target >= CampaignState.TOWNS.size():
		return null
	for t in d.get("path", []):
		var i := int(t)
		if i < 0 or i >= CampaignState.TOWNS.size():
			return null
		a.path.append(i)
	return a
