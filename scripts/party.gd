class_name Party
extends RefCounted
## Groupe qui se déplace en temps réel sur la carte de campagne : la compagnie du joueur,
## des villageois, des bandits, une caravane, une patrouille, l'armée d'une faction...
##
## Squelette commun aux sessions « carte en temps réel » : ce fichier fixe les champs et les
## fonctions de base. Le déplacement (overworld), les comportements (party_ai) et les rencontres
## (encounter) s'appuient dessus. Aucune donnée de rendu : la carte dessine d'après kind et pos.
##
## Unités de la carte : pixels de la carte du monde. Unité de temps : l'heure de jeu
## (24 heures = 1 jour de campagne : solde, saisons, contrats).

## Sortes de groupes. Un nouveau type ajoute ici son nom, puis son comportement et ses rencontres.
const KINDS := ["player", "villagers", "bandits", "caravan", "patrol", "army", "deserters"]

## Nom affiché par sorte (au pluriel ou collectif).
const KIND_NAMES := {
	"player": "votre compagnie",
	"villagers": "des villageois",
	"bandits": "des bandits",
	"caravan": "une caravane marchande",
	"patrol": "une patrouille",
	"army": "une armée",
	"deserters": "des déserteurs",
}

## Vitesse de base (pixels de carte par heure de jeu) par sorte, avant terrain, route et saison
## (MapData.speed_at : x1,3 sur la route). La compagnie fait environ 400 px par jour sur la route,
## comme les 130 px par jour de l'ancienne carte, trois fois plus petite.
const BASE_SPEED := {
	"player": 12.5,
	"villagers": 8.5,
	"bandits": 13.5,
	"caravan": 7.5,
	"patrol": 12.5,
	"army": 9.6,
	"deserters": 11.5,
}

var id := 0
var kind := "villagers" ## Une valeur de KINDS
var faction := -1 ## Faction (index de CampaignState.FACTIONS), -1 : aucune (bandits, villageois sans seigneur)
var name := "" ## Nom propre facultatif (« les Écorcheurs », « l'ost du baron »)
var pos := Vector2.ZERO ## Position sur la carte
var path: Array[Vector2] = [] ## Points de passage restants (le dernier est le but)
var target_id := -1 ## Groupe poursuivi (-1 : aucun) ; le déplacement suit sa position
var home := -1 ## Lieu d'attache (index de lieu de la carte), -1 : aucun
var goal := -1 ## Lieu visé (index de lieu), -1 : aucun
var state := "idle" ## État libre pour le comportement (« idle », « travel », « chase », « flee », « camp »...)
var troops: Array[Dictionary] = [] ## Régiments : {"type": String (UnitTypes), "men": int, "xp": float}
var gold := 0 ## Or porté (butin possible)
var goods := 0 ## Marchandises (caravanes, villageois) : valeur en écus
var speed_bonus := 1.0 ## Multiplicateur de vitesse propre au groupe (chevaux, fatigue...)
var hidden := false ## Groupe caché (forêt, embuscade) : invisible tant qu'il n'est pas repéré
var busy_hours := 0.0 ## Heures pendant lesquelles le groupe reste sur place (repos, pillage, commerce)
var base := Vector2(-1, -1) ## Point d'attache hors des lieux (repaire de bandits) ; (-1, -1) : aucun
var age := 0.0 ## Heures depuis l'apparition du groupe (déserteurs qui tournent au brigandage...)


## Effectif total.
func men() -> int:
	var n := 0
	for r in troops:
		n += int(r.get("men", 0))
	return n


## Force approximative pour comparer deux groupes (effectifs pondérés par l'expérience).
func strength() -> float:
	var s := 0.0
	for r in troops:
		s += float(r.get("men", 0)) * (1.0 + float(r.get("xp", 0.0)) / 200.0)
	return s


## Le groupe ne compte plus (plus un homme).
func is_dead() -> bool:
	return men() <= 0


## Nom affiché : le nom propre s'il existe, sinon la sorte.
func display_name() -> String:
	if name != "":
		return name
	return str(KIND_NAMES.get(kind, kind))


## Vitesse de base (avant terrain, route et saison, que la carte applique).
func base_speed() -> float:
	return float(BASE_SPEED.get(kind, 5.0)) * speed_bonus


## Envoie le groupe vers une suite de points (le dernier est le but).
func go(points: Array[Vector2]) -> void:
	path = points.duplicate()
	target_id = -1


## Avance de distance pixels le long du chemin. Renvoie vrai si le groupe est arrivé au but.
func advance(distance: float) -> bool:
	var left := distance
	while not path.is_empty() and left > 0.0:
		var d := pos.distance_to(path[0])
		if d <= left:
			pos = path[0]
			left -= d
			path.remove_at(0)
		else:
			pos = pos.move_toward(path[0], left)
			left = 0.0
	return path.is_empty()


# ---------------------------------------------------------------- Sauvegarde

func to_dict() -> Dictionary:
	var pts: Array = []
	for p in path:
		pts.append([p.x, p.y])
	return {
		"id": id, "kind": kind, "faction": faction, "name": name,
		"pos": [pos.x, pos.y], "path": pts, "target_id": target_id,
		"home": home, "goal": goal, "state": state,
		"troops": troops.duplicate(true), "gold": gold, "goods": goods,
		"speed_bonus": speed_bonus, "hidden": hidden, "busy_hours": busy_hours,
		"base": [base.x, base.y], "age": age,
	}


## Relit un groupe sauvegardé ; null si les données sont invalides.
static func from_dict(d: Variant) -> Party:
	if not (d is Dictionary):
		return null
	var p := Party.new()
	p.kind = str(d.get("kind", ""))
	if not p.kind in KINDS:
		return null
	p.id = int(d.get("id", 0))
	p.faction = int(d.get("faction", -1))
	p.name = str(d.get("name", ""))
	var xy: Variant = d.get("pos", [0, 0])
	if xy is Array and (xy as Array).size() == 2:
		p.pos = Vector2(float(xy[0]), float(xy[1]))
	for q in d.get("path", []):
		if q is Array and (q as Array).size() == 2:
			p.path.append(Vector2(float(q[0]), float(q[1])))
	p.target_id = int(d.get("target_id", -1))
	p.home = int(d.get("home", -1))
	p.goal = int(d.get("goal", -1))
	p.state = str(d.get("state", "idle"))
	for r in d.get("troops", []):
		if r is Dictionary and UnitTypes.STATS.has(str(r.get("type", ""))):
			p.troops.append({"type": str(r["type"]), "men": maxi(0, int(r.get("men", 0))), "xp": maxf(0.0, float(r.get("xp", 0.0)))})
	p.gold = maxi(0, int(d.get("gold", 0)))
	p.goods = maxi(0, int(d.get("goods", 0)))
	p.speed_bonus = clampf(float(d.get("speed_bonus", 1.0)), 0.1, 3.0)
	p.hidden = bool(d.get("hidden", false))
	p.busy_hours = maxf(0.0, float(d.get("busy_hours", 0.0)))
	var b: Variant = d.get("base", [-1, -1])
	if b is Array and (b as Array).size() == 2:
		p.base = Vector2(float(b[0]), float(b[1]))
	p.age = maxf(0.0, float(d.get("age", 0.0)))
	return p
