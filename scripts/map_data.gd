class_name MapData
extends RefCounted
## Carte du monde (seule source de vérité de la géographie) : taille, lieux, routes, relief,
## rivières, régions, vitesse de marche et terrain de bataille selon l'endroit, chemins (A* sur
## une grille grossière).
##
## Coordonnées : pixels de la carte du monde (SIZE). L'ancienne carte (880 x 720) a d'abord été
## agrandie SCALE fois (2640 x 2160) ; la carte actuelle la prolonge vers l'est et le sud
## (3840 x 3120) sans rien déplacer : les 7 villes, les 14 premiers lieux et les positions des
## sauvegardes restent valables. Une ville est un lieu (« town ») dont l'indice est aussi celui de
## CampaignState.TOWNS (contrats, recrutement, monde vivant).
##
## Sortes de lieux (« kind ») :
##   town     ville (indices 0 à 6, CampaignState.TOWNS) : contrats, recrutement ;
##   village  village (les villageois y naissent) ;
##   castle   château ou tour d'un seigneur ;
##   abbey    abbaye ;
##   mill     moulin ;
##   bridge   pont fortifié sur une rivière ;  ford  gué ;
##   mine     mine (dans les montagnes) ;
##   ruins    ruines ;  lair  repaire de bandits (faction -1, au bout d'un sentier).
## Terrain de bataille près d'un lieu : « village » pour les lieux habités (town, village, castle,
## abbey, mill), « river » pour bridge et ford, sinon le terrain de l'endroit (SETTLED_KINDS).
##
## Pour étendre la carte : ajouter des lieux À LA FIN de PLACES (les indices des lieux sont
## sauvegardés) avec « link » (nom du lieu relié par un chemin), des chemins dans EXTRA_ROADS, des
## étendues d'eau dans LAKES, des rivières dans RIVERS, des chaînes dans MOUNTAINS, des forêts dans
## FORESTS, des régions dans REGIONS. Tout le reste (dessin, vitesse, chemins, terrain de
## bataille) en découle. tests/overworld_test.gd vérifie la cohérence (lieux au sec, routes hors
## des lacs, faction des lieux = faction de leur région).

const SCALE := 3.0 ## Agrandissement de l'ancienne carte (880 x 720) : villes et vitesses en dépendent
const SIZE := Vector2(3840, 3120)
const CELL := 16.0 ## Pas de la grille du terrain et des chemins

## Villes : positions sur la grande carte, faction de départ, prix des recrues (x RECRUIT_COST) et
## types de troupes qu'on peut y lever (CampaignState.TOWNS en est un alias).
const TOWNS := [
	{"name": "Valombre", "pos": Vector2(420, 1680), "faction": 0, "price": 1.0, "recruits": ["spear", "archer"]},
	{"name": "Saint-Aubin", "pos": Vector2(990, 1260), "faction": 0, "price": 0.9, "recruits": ["spear", "men_at_arms", "foot_knight"]},
	{"name": "Montfaucon", "pos": Vector2(690, 600), "faction": 1, "price": 1.15, "recruits": ["archer", "cavalry", "horse_archer"]},
	{"name": "Brévannes", "pos": Vector2(1500, 1800), "faction": 2, "price": 0.85, "recruits": ["spear", "archer", "crossbow"]},
	{"name": "Castelroux", "pos": Vector2(1680, 870), "faction": 1, "price": 1.1, "recruits": ["men_at_arms", "cavalry", "horse_archer"]},
	{"name": "Hautemure", "pos": Vector2(2310, 420), "faction": 1, "price": 1.25, "recruits": ["men_at_arms", "foot_knight", "archer", "cavalry"]},
	{"name": "Pontrieux", "pos": Vector2(2280, 1410), "faction": 2, "price": 0.95, "recruits": ["spear", "men_at_arms", "archer", "crossbow"]},
]
## Grandes routes entre les villes (indices de TOWNS) : celles du monde vivant (armées, marche).
const TOWN_ROADS := [[0, 1], [0, 3], [1, 2], [1, 3], [1, 4], [2, 4], [3, 6], [4, 6], [4, 5], [5, 6]]

## Autres lieux (après les villes dans places()) : « kind » (voir plus haut), « link » : lieu relié
## par un chemin (nom), « faction » : seigneur (-1 : aucun). Ne jamais réordonner : ajouter à la fin.
const PLACES := [
	{"name": "Les Aulnes", "kind": "village", "pos": Vector2(250, 1250), "faction": 0, "link": "Valombre"},
	{"name": "Bois-Margot", "kind": "village", "pos": Vector2(640, 1960), "faction": 0, "link": "Valombre"},
	{"name": "Saulieu", "kind": "village", "pos": Vector2(860, 1660), "faction": 0, "link": "Saint-Aubin"},
	{"name": "Gué-Robert", "kind": "village", "pos": Vector2(1040, 1010), "faction": 0, "link": "Saint-Aubin"},
	{"name": "Ormes", "kind": "village", "pos": Vector2(420, 900), "faction": 1, "link": "Montfaucon"},
	{"name": "Vauclair", "kind": "village", "pos": Vector2(1000, 330), "faction": 1, "link": "Montfaucon"},
	{"name": "Roche-Aigue", "kind": "village", "pos": Vector2(1960, 640), "faction": 1, "link": "Castelroux"},
	{"name": "Haut-Bourg", "kind": "village", "pos": Vector2(1460, 1340), "faction": 2, "link": "Brévannes"},
	{"name": "Fontbrune", "kind": "village", "pos": Vector2(1880, 1480), "faction": 2, "link": "Pontrieux"},
	{"name": "Pré-Vert", "kind": "village", "pos": Vector2(2470, 1020), "faction": 2, "link": "Pontrieux"},
	{"name": "Les Mares", "kind": "village", "pos": Vector2(2120, 2000), "faction": 2, "link": "Brévannes"},
	{"name": "Grisemont", "kind": "castle", "pos": Vector2(1250, 600), "faction": 1, "link": "Castelroux"},
	{"name": "Tour du Guet", "kind": "castle", "pos": Vector2(660, 1420), "faction": 0, "link": "Saint-Aubin"},
	{"name": "Fort-Lisière", "kind": "castle", "pos": Vector2(2060, 1140), "faction": 2, "link": "Pontrieux"},
	# Grande carte : marches du nord-est (Baronnie)
	{"name": "Mine de Fer-Rouge", "kind": "mine", "pos": Vector2(2860, 230), "faction": 1, "link": "Hautemure"},
	{"name": "Château-Corbin", "kind": "castle", "pos": Vector2(3330, 520), "faction": 1, "link": "Hautemure"},
	{"name": "Sombreval", "kind": "village", "pos": Vector2(3560, 230), "faction": 1, "link": "Château-Corbin"},
	{"name": "Les Essarts", "kind": "village", "pos": Vector2(3450, 860), "faction": 1, "link": "Château-Corbin"},
	{"name": "Abbaye de Clairfont", "kind": "abbey", "pos": Vector2(2640, 760), "faction": 1, "link": "Hautemure"},
	{"name": "Abbaye de Saint-Fiacre", "kind": "abbey", "pos": Vector2(1660, 330), "faction": 1, "link": "Hautemure"},
	# Orient (Ligue)
	{"name": "Bellerive", "kind": "village", "pos": Vector2(3080, 1340), "faction": 2, "link": "Pontrieux"},
	{"name": "Moulin de l'Orbe", "kind": "mill", "pos": Vector2(2700, 1660), "faction": 2, "link": "Pontrieux"},
	{"name": "Lunel", "kind": "village", "pos": Vector2(3560, 1700), "faction": 2, "link": "Bellerive"},
	{"name": "Fort-Orient", "kind": "castle", "pos": Vector2(3420, 1130), "faction": 2, "link": "Bellerive"},
	{"name": "Valcreux", "kind": "village", "pos": Vector2(3200, 2060), "faction": 2, "link": "Lunel"},
	# Bocage du sud (Comté)
	{"name": "Sainte-Ondine", "kind": "village", "pos": Vector2(900, 2420), "faction": 0, "link": "Bois-Margot"},
	{"name": "Abbaye de Montsaint", "kind": "abbey", "pos": Vector2(560, 2300), "faction": 0, "link": "Bois-Margot"},
	{"name": "Moulin-Neuf", "kind": "mill", "pos": Vector2(1380, 2250), "faction": 0, "link": "Saulieu"},
	{"name": "Les Ronces", "kind": "village", "pos": Vector2(1000, 2860), "faction": 0, "link": "Sainte-Ondine"},
	{"name": "Mine du Puits-Noir", "kind": "mine", "pos": Vector2(330, 2760), "faction": -1, "link": "Abbaye de Montsaint"},
	# Rives du midi (Ligue)
	{"name": "Port-Sablon", "kind": "village", "pos": Vector2(1820, 2450), "faction": 2, "link": "Brévannes"},
	{"name": "Castel-Brume", "kind": "castle", "pos": Vector2(2330, 2620), "faction": 2, "link": "Les Mares"},
	{"name": "Gué-aux-Saules", "kind": "ford", "pos": Vector2(1250, 2700), "faction": 0, "link": "Les Ronces"},
	{"name": "Pont-de-Vionne", "kind": "bridge", "pos": Vector2(1165, 1140), "faction": 0, "link": "Gué-Robert"},
	# Terres sans seigneur : ruines et repaires
	{"name": "Ruines de Vieille-Tour", "kind": "ruins", "pos": Vector2(2930, 2330), "faction": -1, "link": "Valcreux"},
	{"name": "Repaire des Loups", "kind": "lair", "pos": Vector2(3420, 2830), "faction": -1, "link": "Ruines de Vieille-Tour"},
	{"name": "Repaire de la Combe", "kind": "lair", "pos": Vector2(170, 640), "faction": -1, "link": "Ormes"},
	{"name": "Ruines du Vieux-Moutier", "kind": "ruins", "pos": Vector2(1760, 2960), "faction": -1, "link": "Port-Sablon"},
]
## Chemins de plus entre les lieux (noms) : le réseau secondaire qui relie les villages.
const EXTRA_ROADS := [
	["Les Aulnes", "Tour du Guet"], ["Les Aulnes", "Ormes"], ["Saulieu", "Bois-Margot"], ["Gué-Robert", "Pont-de-Vionne"],
	["Pont-de-Vionne", "Haut-Bourg"], ["Vauclair", "Grisemont"], ["Roche-Aigue", "Hautemure"], ["Fontbrune", "Haut-Bourg"],
	["Fontbrune", "Fort-Lisière"], ["Pré-Vert", "Fort-Lisière"], ["Pré-Vert", "Abbaye de Clairfont"], ["Abbaye de Saint-Fiacre", "Roche-Aigue"],
	["Les Essarts", "Fort-Orient"], ["Bellerive", "Moulin de l'Orbe"], ["Valcreux", "Les Mares"], ["Sainte-Ondine", "Moulin-Neuf"],
	["Moulin-Neuf", "Port-Sablon"], ["Port-Sablon", "Castel-Brume"], ["Gué-aux-Saules", "Port-Sablon"], ["Vauclair", "Abbaye de Saint-Fiacre"],
]
## Lieux habités : une bataille à côté se livre dans le village (battle_terrain_at).
const SETTLED_KINDS := ["town", "village", "castle", "abbey", "mill"]
## Noms des sortes de lieux (infobulle).
const KIND_NAMES := {"town": "ville", "village": "village", "castle": "château", "abbey": "abbaye", "mill": "moulin",
	"bridge": "pont", "ford": "gué", "mine": "mine", "ruins": "ruines", "lair": "repaire de bandits"}

## Régions nommées : faction (-1 : sans seigneur), centre (graine des frontières) et place du nom
## (« label », le centre par défaut).
const REGIONS := [
	{"name": "Val d'Ombre", "faction": 0, "pos": Vector2(330, 1660), "label": Vector2(330, 1530)},
	{"name": "Pays d'Aubin", "faction": 0, "pos": Vector2(930, 1420)},
	{"name": "Bocage du Sud", "faction": 0, "pos": Vector2(880, 2620)},
	{"name": "Montfalcois", "faction": 1, "pos": Vector2(560, 600), "label": Vector2(600, 450)},
	{"name": "Marche de Castelroux", "faction": 1, "pos": Vector2(1640, 980)},
	{"name": "Hautes-Terres", "faction": 1, "pos": Vector2(2250, 330), "label": Vector2(2300, 600)},
	{"name": "Marches de Fer", "faction": 1, "pos": Vector2(3420, 560)},
	{"name": "Brévannais", "faction": 2, "pos": Vector2(1640, 1620)},
	{"name": "Pays de Pontrieux", "faction": 2, "pos": Vector2(2460, 1380), "label": Vector2(2560, 1250)},
	{"name": "Plaines d'Orient", "faction": 2, "pos": Vector2(3330, 1620)},
	{"name": "Rives du Midi", "faction": 2, "pos": Vector2(2050, 2580)},
	{"name": "Terres Gastes", "faction": -1, "pos": Vector2(3250, 2720)},
	{"name": "Monts Noirs", "faction": -1, "pos": Vector2(200, 2700)},
]
const REGION_WARP := 170.0 ## Ondulation des frontières (pixels)

## Étendues d'eau (ellipses un peu irrégulières) : centre, rayons, nom. Un anneau de marais les
## entoure (MARSH_RING).
const LAKES := [
	{"center": Vector2(1960, 1790), "radius": Vector2(150, 85), "name": "Lac des Mares"},
	{"center": Vector2(360, 420), "radius": Vector2(110, 70), "name": "Lac de la Combe"},
	{"center": Vector2(3700, 560), "radius": Vector2(95, 150), "name": "Lac Noir"},
	{"center": Vector2(3560, 2240), "radius": Vector2(170, 95), "name": "Lac de Gaste"},
	{"center": Vector2(760, 2650), "radius": Vector2(115, 75), "name": "Étang des Sorbiers"},
	{"center": Vector2(2580, 2900), "radius": Vector2(140, 85), "name": "Lac de Brume"},
]
const MARSH_RING := 1.7 ## Rayon du marais autour d'un lac (x le rayon du lac)
const LAKE_WOBBLE := 0.13 ## Irrégularité des rives
const RIVER_HALF := 20.0 ## Demi-largeur de la grande rivière (la Vionne)
const RIVER_NAME := "la Vionne"
## Autres rivières : points de passage (lissés), demi-largeur, nom. Elles se jettent dans un lac
## ou dans la Vionne.
const RIVERS := [
	{"name": "l'Orbe", "half": 15.0, "points": [Vector2(3250, 1040), Vector2(3120, 1180), Vector2(2960, 1320), Vector2(2830, 1480),
		Vector2(2640, 1600), Vector2(2420, 1700), Vector2(2240, 1760), Vector2(2100, 1790)]},
	{"name": "la Basse-Orbe", "half": 15.0, "points": [Vector2(1820, 1800), Vector2(1720, 1870), Vector2(1630, 1950), Vector2(1545, 2005)]},
	{"name": "le Ru de la Combe", "half": 10.0, "points": [Vector2(465, 430), Vector2(560, 500), Vector2(640, 700), Vector2(760, 790),
		Vector2(930, 820), Vector2(1120, 860), Vector2(1270, 880), Vector2(1380, 860)]},
	{"name": "la Sorgue", "half": 11.0, "points": [Vector2(3480, 2190), Vector2(3300, 2130), Vector2(3060, 2160), Vector2(2860, 2120),
		Vector2(2620, 2180), Vector2(2400, 2120), Vector2(2200, 2050), Vector2(2090, 1860)]},
]
## Chaînes de montagnes (infranchissables hors des cols, où passent les routes) et de collines
## (« hills » : seulement des collines) : ligne de crête, demi-largeur, nom.
const MOUNTAINS := [
	{"name": "Monts de Fer", "width": 170.0, "points": [Vector2(2980, -60), Vector2(2930, 260), Vector2(3020, 560), Vector2(3130, 820), Vector2(3240, 960)]},
	{"name": "Montagnes Noires", "width": 160.0, "points": [Vector2(-60, 2330), Vector2(230, 2470), Vector2(420, 2650), Vector2(470, 2920), Vector2(420, 3180)]},
	{"name": "Dents de Gaste", "width": 140.0, "points": [Vector2(2780, 3180), Vector2(2900, 2700), Vector2(3150, 2520), Vector2(3500, 2480), Vector2(3900, 2380)]},
	{"name": "Collines de Grisemont", "width": 150.0, "hills": true, "points": [Vector2(1080, 470), Vector2(1300, 560), Vector2(1500, 700)]},
	{"name": "Coteaux d'Orient", "width": 170.0, "hills": true, "points": [Vector2(2700, 1900), Vector2(2950, 1800), Vector2(3150, 1880)]},
]
## Grandes forêts : centre, rayons, nom (d'autres petits bois naissent du bruit).
const FORESTS := [
	{"name": "Forêt d'Ombre", "center": Vector2(230, 1990), "radius": Vector2(230, 200)},
	{"name": "Bois de Vauclair", "center": Vector2(1260, 220), "radius": Vector2(260, 140)},
	{"name": "Forêt de la Lisière", "center": Vector2(2230, 1180), "radius": Vector2(150, 110)},
	{"name": "Grande Sylve", "center": Vector2(3620, 1320), "radius": Vector2(220, 200)},
	{"name": "Bois des Pendus", "center": Vector2(3150, 2290), "radius": Vector2(190, 130)},
	{"name": "Forêt des Sorbiers", "center": Vector2(1230, 2560), "radius": Vector2(220, 200)},
	{"name": "Bois de la Combe", "center": Vector2(190, 760), "radius": Vector2(150, 200)},
	{"name": "Forêt de Haute-Garde", "center": Vector2(2010, 210), "radius": Vector2(200, 140)},
	{"name": "Bois de Gaste", "center": Vector2(3700, 2760), "radius": Vector2(170, 220)},
]
const ROAD_HALF := 9.0 ## Demi-largeur d'une route (une case dont le centre est plus près est une route)
const PLACE_RADIUS := 34.0 ## Rayon d'un lieu (clic, arrivée)
## Sortes de routes (road_class) : grande route entre villes, chemin, sentier (ruines, repaires, mines).
enum RoadClass { MAIN, LANE, TRAIL }
const TRAIL_KINDS := ["ruins", "lair", "mine"]

## Sortes de terrain de la grille (MOUNTAIN : infranchissable, sauf par les cols des routes).
enum Ground { PLAIN, FOREST, HILLS, MARSH, WATER, MOUNTAIN }
const GROUND_NAMES := ["plaine", "forêt", "collines", "marais", "eau", "montagne"]
## Vitesse de marche selon le terrain (x la vitesse du groupe). L'eau ne se traverse qu'aux ponts,
## la montagne qu'aux cols (routes).
const GROUND_SPEED := [1.0, 0.6, 0.7, 0.5, 0.0, 0.0]
const ROAD_SPEED := 1.3 ## Sur une route (ou un pont, ou un col)
## Terrains de bataille possibles (Terrain.KINDS, hors sièges) selon l'endroit (battle_terrain_at).
const BATTLE_TERRAINS := ["plain", "forest", "hills", "river", "village"]

static var _w := 0
static var _h := 0
static var _ground := PackedByteArray()
static var _road := PackedByteArray()
static var _height := PackedFloat32Array() ## Hauteur du relief (0-1, plus haut en montagne), pour l'ombrage
static var _water := PackedFloat32Array() ## Distance signée à l'eau (négative dans l'eau)
static var _river := PackedFloat32Array() ## Distance signée aux rivières de RIVERS (pas la Vionne)
static var _forest := PackedFloat32Array() ## Densité de la forêt (0-1)
static var _mount := PackedFloat32Array() ## Montagne (0-1 ; > MOUNT_CORE : infranchissable)
static var _marsh := PackedFloat32Array() ## Marais (0-1)
static var _region := PackedByteArray() ## Région (indice de REGIONS)
static var _border := PackedFloat32Array() ## Écart à la frontière la plus proche (pixels)
static var _warp := PackedVector2Array() ## Déplacement du point qui ondule les frontières
static var _places: Array[Dictionary] = []
static var _roads: Array = []
static var _road_pts: Array[PackedVector2Array] = []
static var _road_cls: Array[int] = []
static var _river_pts: Array[PackedVector2Array] = []
static var _bridges: Array[Dictionary] = []
static var _astar: AStarGrid2D = null
static var _lake_noise: FastNoiseLite = null

const MOUNT_CORE := 0.55 ## Au-delà : montagne ; au-delà de MOUNT_SKIRT : collines
const MOUNT_SKIRT := 0.2


# ---------------------------------------------------------------- Lieux et routes

## Tous les lieux : les villes d'abord (même indice que TOWNS, kind « town »), puis PLACES.
## Chaque lieu : {id, name, kind, pos, faction}.
static func places() -> Array[Dictionary]:
	if _places.is_empty():
		for i in TOWNS.size():
			var t: Dictionary = TOWNS[i]
			_places.append({"id": i, "name": t["name"], "kind": "town", "pos": t["pos"], "faction": int(t["faction"])})
		for p in PLACES:
			_places.append({"id": _places.size(), "name": p["name"], "kind": p["kind"], "pos": p["pos"], "faction": int(p["faction"])})
	return _places


static func place_count() -> int:
	return places().size()


static func place(i: int) -> Dictionary:
	return places()[i]


static func place_pos(i: int) -> Vector2:
	return places()[i]["pos"]


## Indice d'un lieu d'après son nom (-1 s'il n'existe pas).
static func place_named(n: String) -> int:
	for p in places():
		if str(p["name"]) == n:
			return int(p["id"])
	return -1


## Lieu sous un point (dans PLACE_RADIUS x k), le plus proche ; -1 sinon.
static func place_at(pos: Vector2, k := 1.0) -> int:
	var best := -1
	var best_d := PLACE_RADIUS * k
	for p in places():
		var d := pos.distance_to(p["pos"])
		if d < best_d:
			best_d = d
			best = int(p["id"])
	return best


## Lieu le plus proche d'un point (filtré par sorte si kinds n'est pas vide).
static func nearest_place(pos: Vector2, kinds: Array = []) -> int:
	var best := -1
	for p in places():
		if not kinds.is_empty() and not p["kind"] in kinds:
			continue
		if best < 0 or pos.distance_to(p["pos"]) < pos.distance_to(place_pos(best)):
			best = int(p["id"])
	return best


## Ville la plus proche d'un point.
static func nearest_town(pos: Vector2) -> int:
	return nearest_place(pos, ["town"])


## Toutes les routes, en paires d'indices de lieux : les grandes routes, puis les chemins des lieux
## (« link »), puis EXTRA_ROADS. Même ordre que road_points et road_class.
static func roads() -> Array:
	if _roads.is_empty():
		var seen := {}
		var add := func(a: int, b: int) -> void:
			if a < 0 or b < 0 or a == b or seen.has(Vector2i(mini(a, b), maxi(a, b))):
				return
			seen[Vector2i(mini(a, b), maxi(a, b))] = true
			_roads.append([a, b])
		for r in TOWN_ROADS:
			add.call(int(r[0]), int(r[1]))
		for i in PLACES.size():
			add.call(TOWNS.size() + i, place_named(str(PLACES[i].get("link", ""))))
		for r in EXTRA_ROADS:
			add.call(place_named(str(r[0])), place_named(str(r[1])))
	return _roads


## Sorte d'une route (RoadClass) : grande route entre deux villes, sentier vers des ruines, un
## repaire ou une mine, chemin sinon.
static func road_class(i: int) -> int:
	if _road_cls.is_empty():
		for r in roads():
			var ka := str(place(r[0])["kind"])
			var kb := str(place(r[1])["kind"])
			if ka == "town" and kb == "town":
				_road_cls.append(RoadClass.MAIN)
			elif ka in TRAIL_KINDS or kb in TRAIL_KINDS:
				_road_cls.append(RoadClass.TRAIL)
			else:
				_road_cls.append(RoadClass.LANE)
	return _road_cls[i]


## Tracé d'une route (indice dans roads()) : une ligne doucement infléchie d'un lieu à l'autre,
## toujours la même (les virages viennent des indices des lieux). Points espacés d'environ 20 px.
static func road_points(i: int) -> PackedVector2Array:
	if _road_pts.is_empty():
		for k in roads().size():
			_road_pts.append(_bend_road(k))
	return _road_pts[i]


static func _bend_road(k: int) -> PackedVector2Array:
	var r: Array = roads()[k]
	var a := place_pos(r[0])
	var b := place_pos(r[1])
	var d := b - a
	var len := d.length()
	var nrm := Vector2(-d.y, d.x) / maxf(len, 1.0)
	var h := absi((mini(r[0], r[1]) * 7919 + maxi(r[0], r[1]) * 104729) % 1000)
	var s1 := float(h % 200) / 100.0 - 1.0 # -1..1 : sens et force du grand virage
	var s2 := float((h / 7) % 200) / 100.0 - 1.0 # Petite ondulation
	var amp := [0.035, 0.07, 0.09][road_class(k)] as float
	var cap := [40.0, 70.0, 80.0][road_class(k)] as float
	var a1 := minf(len * amp, cap) * s1
	var a2 := minf(len * amp * 0.35, cap * 0.35) * s2
	var n := maxi(2, int(len / 20.0))
	var out := PackedVector2Array()
	for j in n + 1:
		var t := float(j) / n
		out.append(a + d * t + nrm * (sin(PI * t) * a1 + sin(TAU * t) * a2))
	return out


## Distance d'un point à la route la plus proche.
static func road_distance(pos: Vector2) -> float:
	var best := INF
	for k in roads().size():
		var pts := road_points(k)
		for j in pts.size() - 1:
			best = minf(best, pos.distance_to(Geometry2D.get_closest_point_to_segment(pos, pts[j], pts[j + 1])))
	return best


## Ponts : où une route franchit l'eau (rivière). Chaque pont : {a, b (rives), road (indice)}.
static func bridges() -> Array[Dictionary]:
	if _bridges.is_empty():
		_build()
		for k in roads().size():
			var pts := road_points(k)
			var wet := false
			var start := Vector2.ZERO
			for j in pts.size() - 1:
				var n := maxi(1, int(pts[j].distance_to(pts[j + 1]) / 3.0))
				for s in n:
					var p := pts[j].lerp(pts[j + 1], float(s) / n)
					var w := water_sdf(p) < 0.0
					if w and not wet:
						start = p
					elif wet and not w and not _near_ford((start + p) * 0.5):
						var dir := (p - start).normalized()
						_bridges.append({"a": start - dir * 6.0, "b": p + dir * 6.0, "road": k})
					wet = w
	return _bridges


## Un gué tout près ? (on y passe à pied sec sur des pierres : pas de pont)
static func _near_ford(p: Vector2) -> bool:
	var i := place_at(p, 2.0)
	return i >= 0 and str(place(i)["kind"]) == "ford"


# ---------------------------------------------------------------- Relief

## Abscisse de la Vionne, qui traverse la carte du nord au sud (celle de l'ancienne carte, agrandie).
static func river_x(y: float) -> float:
	var oy := y / SCALE
	return SCALE * (440.0 + sin(oy * 0.011) * 70.0 + sin(oy * 0.031) * 18.0)


## Distance au bord de la rivière la plus proche, compté depuis son milieu (la Vionne : écart
## horizontal ; les autres : distance au lit, + leur demi-largeur ramenée à celle de la Vionne).
static func river_distance(pos: Vector2) -> float:
	var main := absf(pos.x - river_x(pos.y))
	return minf(main, _sample(_river, pos) + RIVER_HALF)


## Tracés lissés des rivières de RIVERS (même ordre).
static func river_points(i: int) -> PackedVector2Array:
	if _river_pts.is_empty():
		for r in RIVERS:
			_river_pts.append(_smooth(r["points"]))
	return _river_pts[i]


## Courbe de Catmull-Rom passant par les points, un point tous les 10 px environ.
static func _smooth(src: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in src.size() - 1:
		var p0: Vector2 = src[maxi(i - 1, 0)]
		var p1: Vector2 = src[i]
		var p2: Vector2 = src[i + 1]
		var p3: Vector2 = src[mini(i + 2, src.size() - 1)]
		var n := maxi(2, int(p1.distance_to(p2) / 10.0))
		for j in n:
			var t := float(j) / n
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * (2.0 * p1 + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t3))
	out.append(src[-1])
	return out


## « Distance » elliptique au lac le plus proche (1 : sur la rive, < 1 : dans l'eau). Les rives
## ondulent un peu (LAKE_WOBBLE).
static func lake_factor(pos: Vector2) -> float:
	if _lake_noise == null:
		_lake_noise = FastNoiseLite.new()
		_lake_noise.seed = 41
		_lake_noise.frequency = 0.012
	var best := INF
	for l in LAKES:
		var d: Vector2 = (pos - l["center"]) / (l["radius"] as Vector2)
		var f := d.length()
		if f < 2.5:
			f *= 1.0 + LAKE_WOBBLE * _lake_noise.get_noise_2d(pos.x, pos.y)
		best = minf(best, f)
	return best


## Distance signée à l'eau la plus proche (négative dans l'eau) : lacs, Vionne, autres rivières.
static func water_sdf(pos: Vector2) -> float:
	_build()
	var main := absf(pos.x - river_x(pos.y)) - RIVER_HALF
	return minf(minf(main, _sample(_river, pos)), _lake_sdf(pos))


static func _lake_sdf(pos: Vector2) -> float:
	var best := INF
	for l in LAKES:
		var r: Vector2 = l["radius"]
		var d: Vector2 = (pos - l["center"]) / r
		var f := d.length()
		if f < 2.5:
			f *= 1.0 + LAKE_WOBBLE * _lake_noise_at(pos)
		best = minf(best, (f - 1.0) * minf(r.x, r.y))
	return best


static func _lake_noise_at(pos: Vector2) -> float:
	if _lake_noise == null:
		lake_factor(pos)
	return _lake_noise.get_noise_2d(pos.x, pos.y)


## Valeur d'un champ de la grille au point (interpolation bilinéaire entre les centres des cases).
static func _sample(field: PackedFloat32Array, pos: Vector2) -> float:
	_build()
	var f := pos / CELL - Vector2(0.5, 0.5)
	var x0 := clampi(floori(f.x), 0, _w - 1)
	var y0 := clampi(floori(f.y), 0, _h - 1)
	var x1 := mini(x0 + 1, _w - 1)
	var y1 := mini(y0 + 1, _h - 1)
	var tx := clampf(f.x - x0, 0.0, 1.0)
	var ty := clampf(f.y - y0, 0.0, 1.0)
	var top := lerpf(field[y0 * _w + x0], field[y0 * _w + x1], tx)
	var bot := lerpf(field[y1 * _w + x0], field[y1 * _w + x1], tx)
	return lerpf(top, bot, ty)


## Distance d'un point à une ligne brisée (et rien si la boîte grossie de margin ne le contient pas).
static func _polyline_distance(p: Vector2, pts: Array) -> float:
	var best := INF
	for j in pts.size() - 1:
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[j], pts[j + 1])))
	return best


## Construit la grille du terrain (une fois par partie : la carte est la même d'une partie à l'autre).
static func _build() -> void:
	if not _ground.is_empty():
		return
	_w = ceili(SIZE.x / CELL)
	_h = ceili(SIZE.y / CELL)
	var n := _w * _h
	_ground.resize(n)
	_road.resize(n)
	_height.resize(n)
	_water.resize(n)
	_river.resize(n)
	_forest.resize(n)
	_mount.resize(n)
	_marsh.resize(n)
	_region.resize(n)
	_border.resize(n)
	_warp.resize(n)
	var relief := FastNoiseLite.new()
	relief.seed = 7
	relief.frequency = 0.02
	var wood := FastNoiseLite.new()
	wood.seed = 11
	wood.frequency = 0.03
	var wet := FastNoiseLite.new()
	wet.seed = 23
	wet.frequency = 0.04
	var rough := FastNoiseLite.new() # Irrégularité des crêtes et des lisières
	rough.seed = 5
	rough.frequency = 0.012
	rough.fractal_octaves = 3
	var warp := FastNoiseLite.new() # Ondulation des frontières
	warp.seed = 31
	warp.frequency = 0.0016
	# Champs « tamponnés » le long des lignes : rivières, routes, lieux
	_river.fill(999.0)
	for i in RIVERS.size():
		var half := float(RIVERS[i]["half"])
		for p in river_points(i):
			_stamp_min(_river, p, 120.0, -half)
	var road_d := PackedFloat32Array()
	road_d.resize(n)
	road_d.fill(999.0)
	for k in roads().size():
		var pts := road_points(k)
		for j in pts.size() - 1:
			var m := maxi(1, int(pts[j].distance_to(pts[j + 1]) / 5.0))
			for s in m:
				_stamp_min(road_d, pts[j].lerp(pts[j + 1], float(s) / m), 56.0, 0.0)
	var place_d := PackedFloat32Array()
	place_d.resize(n)
	place_d.fill(999.0)
	for pl in places():
		_stamp_min(place_d, pl["pos"], PLACE_RADIUS + 80.0, 0.0)
	var boxes: Array[Rect2] = []
	for m in MOUNTAINS:
		var r := Rect2(m["points"][0], Vector2.ZERO)
		for q in m["points"]:
			r = r.expand(q)
		boxes.append(r.grow(float(m["width"]) * 1.3))
	for y in _h:
		var rx := river_x((y + 0.5) * CELL)
		for x in _w:
			var i := y * _w + x
			var p := Vector2(x + 0.5, y + 0.5) * CELL
			var q := p / (SCALE * 4.0) # Mêmes bruits que l'ancienne carte (pixels de 4)
			var hgt := relief.get_noise_2d(q.x, q.y) * 0.5 + 0.5
			var rn := rough.get_noise_2d(p.x, p.y) * 0.5 + 0.5
			# Montagnes et collines des chaînes
			var mount := 0.0
			for k in MOUNTAINS.size():
				if not boxes[k].has_point(p):
					continue
				var mt: Dictionary = MOUNTAINS[k]
				var v := 1.0 - _polyline_distance(p, mt["points"]) / float(mt["width"])
				v = clampf(v * (0.7 + 0.7 * rn), 0.0, 1.0)
				if mt.get("hills", false):
					v = minf(v, 0.5)
				mount = maxf(mount, v)
			# Eau
			var lake := lake_factor(p)
			var sdf := minf(minf(absf(p.x - rx) - RIVER_HALF, _river[i]), _lake_sdf(p))
			_water[i] = sdf
			# Marais : autour des lacs, et par endroits au bord des rivières
			var wn := wet.get_noise_2d(q.x, q.y)
			var marsh := 0.0
			if lake < MARSH_RING:
				marsh = clampf((1.0 - (lake - 1.0) / (MARSH_RING - 1.0)) * (0.75 + wn), 0.0, 1.0)
			if sdf < 80.0 and p.y > SIZE.y * 0.3:
				marsh = maxf(marsh, clampf((wn - 0.25) * 6.0, 0.0, 1.0) * clampf(1.0 - sdf / 80.0, 0.0, 1.0))
			# Forêts : les grandes forêts nommées et les bois du bruit
			var fo := clampf((wood.get_noise_2d(q.x, q.y) - 0.16) * 3.5, 0.0, 1.0)
			for f in FORESTS:
				var e := ((p - (f["center"] as Vector2)) / (f["radius"] as Vector2)).length()
				if e < 1.6:
					fo = maxf(fo, clampf((1.3 - e * (0.75 + 0.5 * rn)) * 1.6, 0.0, 1.0))
			fo *= clampf((road_d[i] - 26.0) / 18.0, 0.0, 1.0) * clampf((place_d[i] - PLACE_RADIUS - 10.0) / 40.0, 0.0, 1.0)
			var near_place := place_d[i] < PLACE_RADIUS + 24.0
			_road[i] = 1 if road_d[i] <= ROAD_HALF + CELL * 0.35 else 0
			var g: int = Ground.PLAIN
			if sdf < 0.0:
				g = Ground.WATER
			elif near_place:
				g = Ground.PLAIN
			elif marsh > 0.5:
				g = Ground.MARSH
			elif mount > MOUNT_CORE:
				g = Ground.MOUNTAIN
			elif hgt > 0.68 or mount > MOUNT_SKIRT:
				g = Ground.HILLS
			elif fo > 0.5 and road_d[i] > 40.0:
				g = Ground.FOREST
			_ground[i] = g
			if g == Ground.WATER or near_place:
				mount = minf(mount, MOUNT_SKIRT)
			_mount[i] = mount
			_marsh[i] = marsh if g != Ground.WATER else 0.0
			_forest[i] = fo if g == Ground.FOREST or g == Ground.PLAIN else 0.0
			_height[i] = clampf(hgt * 0.45 + mount * 0.75 + rn * mount * 0.3, 0.0, 1.0)
			# Région : la graine la plus proche, d'un point un peu déplacé (frontières ondulées)
			_warp[i] = Vector2(warp.get_noise_2d(p.x, p.y), warp.get_noise_2d(p.x + 913.0, p.y - 377.0)) * REGION_WARP
			var wp := p + _warp[i]
			var d1 := INF
			var d2 := INF
			var best := 0
			for k in REGIONS.size():
				var d := wp.distance_to(REGIONS[k]["pos"])
				if d < d1:
					d2 = d1
					d1 = d
					best = k
				elif d < d2:
					d2 = d
			_region[i] = best
			_border[i] = (d2 - d1) * 0.5
	_connect()


## Tamponne un champ : chaque case dont le centre est à moins de r du point prend
## min(valeur, distance + offset).
static func _stamp_min(field: PackedFloat32Array, p: Vector2, r: float, offset: float) -> void:
	var c0 := Vector2i(floori((p.x - r) / CELL), floori((p.y - r) / CELL))
	var c1 := Vector2i(floori((p.x + r) / CELL), floori((p.y + r) / CELL))
	for cy in range(maxi(c0.y, 0), mini(c1.y, _h - 1) + 1):
		for cx in range(maxi(c0.x, 0), mini(c1.x, _w - 1) + 1):
			var d := p.distance_to(Vector2(cx + 0.5, cy + 0.5) * CELL)
			if d <= r:
				var i := cy * _w + cx
				field[i] = minf(field[i], d + offset)


## Toute la terre praticable doit être d'un seul tenant : une poche coupée du reste (entre des
## montagnes, une île) devient infranchissable, pour que tout chemin aboutisse.
static func _connect() -> void:
	var seen := PackedByteArray()
	seen.resize(_w * _h)
	var start := cell_of(TOWNS[0]["pos"])
	var stack: Array[int] = [start.y * _w + start.x]
	seen[stack[0]] = 1
	while not stack.is_empty():
		var i: int = stack.pop_back()
		var x := i % _w
		var y := i / _w
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = x + d.x
			var ny: int = y + d.y
			if nx < 0 or ny < 0 or nx >= _w or ny >= _h:
				continue
			var j := ny * _w + nx
			if seen[j] == 0 and _cell_walkable(j):
				seen[j] = 1
				stack.append(j)
	for i in _w * _h:
		if seen[i] == 0 and _cell_walkable(i):
			_ground[i] = Ground.MOUNTAIN if _water[i] >= 0.0 else Ground.WATER
			_road[i] = 0


static func _cell_walkable(i: int) -> bool:
	return _road[i] == 1 or float(GROUND_SPEED[_ground[i]]) > 0.0


static func grid_size() -> Vector2i:
	_build()
	return Vector2i(_w, _h)


static func cell_of(pos: Vector2) -> Vector2i:
	_build()
	return Vector2i(clampi(int(pos.x / CELL), 0, _w - 1), clampi(int(pos.y / CELL), 0, _h - 1))


static func cell_center(c: Vector2i) -> Vector2:
	return (Vector2(c) + Vector2(0.5, 0.5)) * CELL


static func ground_at(pos: Vector2) -> int:
	var c := cell_of(pos)
	return _ground[c.y * _w + c.x]


static func ground_cell(c: Vector2i) -> int:
	_build()
	return _ground[c.y * _w + c.x]


static func height_cell(c: Vector2i) -> float:
	_build()
	return _height[c.y * _w + c.x]


static func is_road(pos: Vector2) -> bool:
	var c := cell_of(pos)
	return _road[c.y * _w + c.x] == 1


static func is_road_cell(c: Vector2i) -> bool:
	_build()
	return _road[c.y * _w + c.x] == 1


## Où écrire le nom d'une région.
static func region_label_pos(i: int) -> Vector2:
	return REGIONS[i].get("label", REGIONS[i]["pos"])


## Région d'un point (indice de REGIONS).
static func region_at(pos: Vector2) -> int:
	var c := cell_of(pos)
	return _region[c.y * _w + c.x]


## Champs de la grille pour le dessin de la carte (w, h et tableaux d'une valeur par case) :
## height, water (distance signée), forest, mount, marsh, region, border, warp (ondulation des
## frontières), ground.
static func fields() -> Dictionary:
	_build()
	return {"w": _w, "h": _h, "height": _height, "water": _water, "forest": _forest, "mount": _mount,
		"marsh": _marsh, "region": _region, "border": _border, "warp": _warp, "ground": _ground}


## Nom du terrain sous un point (« route », « forêt »...), pour l'infobulle.
static func ground_name(pos: Vector2) -> String:
	var g := ground_at(pos)
	if is_road(pos):
		if g == Ground.WATER:
			return "pont"
		return "col" if g == Ground.MOUNTAIN else "route"
	return str(GROUND_NAMES[g])


## Peut-on marcher ici ? (l'eau seulement par un pont, la montagne par un col)
static func walkable(pos: Vector2) -> bool:
	if pos.x < 0.0 or pos.y < 0.0 or pos.x > SIZE.x or pos.y > SIZE.y:
		return false
	return is_road(pos) or float(GROUND_SPEED[ground_at(pos)]) > 0.0


## Vitesse de marche à cet endroit (x la vitesse du groupe) : route plus rapide, forêt, collines
## et marais plus lents. Hors de la carte, dans l'eau ou la montagne : très lent (on ne devrait pas
## y être).
static func speed_at(pos: Vector2) -> float:
	if is_road(pos):
		return ROAD_SPEED
	var s := float(GROUND_SPEED[ground_at(pos)])
	return s if s > 0.0 else 0.25


## Terrain de bataille selon l'endroit (voir Terrain) : village près d'un lieu habité, rivière au
## bord de l'eau, dans les marais ou à un pont ou un gué, forêt, collines (et montagne), sinon plaine.
static func battle_terrain_at(pos: Vector2) -> String:
	var pl := place_at(pos, 2.2)
	if pl >= 0:
		var kind := str(place(pl)["kind"])
		if kind in SETTLED_KINDS:
			return "village"
		if kind == "bridge" or kind == "ford":
			return "river"
	if river_distance(pos) < RIVER_HALF + 70.0 or lake_factor(pos) < MARSH_RING:
		return "river"
	match ground_at(pos):
		Ground.FOREST:
			return "forest"
		Ground.HILLS, Ground.MOUNTAIN:
			return "hills"
		Ground.MARSH, Ground.WATER:
			return "river"
	return "plain"


# ---------------------------------------------------------------- Chemins

static func _grid() -> AStarGrid2D:
	if _astar != null:
		return _astar
	_build()
	_astar = AStarGrid2D.new()
	_astar.region = Rect2i(0, 0, _w, _h)
	_astar.cell_size = Vector2(CELL, CELL)
	_astar.offset = Vector2(CELL, CELL) * 0.5
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.update()
	for y in _h:
		for x in _w:
			var c := Vector2i(x, y)
			var i := y * _w + x
			var s := ROAD_SPEED if _road[i] == 1 else float(GROUND_SPEED[_ground[i]])
			if s <= 0.0:
				_astar.set_point_solid(c, true)
			else:
				_astar.set_point_weight_scale(c, ROAD_SPEED / s) # Route : 1 ; ailleurs plus cher
	return _astar


## Case praticable la plus proche (recherche en spirale) ; c si elle l'est déjà.
static func nearest_walkable_cell(c: Vector2i) -> Vector2i:
	var g := _grid()
	if not g.is_point_solid(c):
		return c
	for r in range(1, 40):
		var best := Vector2i(-1, -1)
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var k := c + Vector2i(dx, dy)
				if g.is_in_boundsv(k) and not g.is_point_solid(k):
					if best.x < 0 or Vector2(k - c).length() < Vector2(best - c).length():
						best = k
		if best.x >= 0:
			return best
	return c


## Point praticable le plus proche d'un point (lui-même s'il l'est).
static func walkable_point(pos: Vector2) -> Vector2:
	pos = pos.clamp(Vector2.ZERO, SIZE - Vector2.ONE)
	if walkable(pos):
		return pos
	return cell_center(nearest_walkable_cell(cell_of(pos)))


## Chemin de from à to (points de passage, to compris ; vide si from == to) : A* sur la grille,
## qui préfère les routes et contourne l'eau et les montagnes. Le but est ramené sur la terre
## ferme s'il le faut.
static func find_path(from: Vector2, to: Vector2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var goal := walkable_point(to)
	if from.distance_to(goal) < 1.0:
		return out
	var g := _grid()
	var a := nearest_walkable_cell(cell_of(from))
	var b := nearest_walkable_cell(cell_of(goal))
	if a == b:
		out.append(goal)
		return out
	var pts := g.get_point_path(a, b)
	if pts.is_empty():
		out.append(goal)
		return out
	# Lissage : on saute les cases intermédiaires tant que la ligne droite reste aussi rapide
	# (sur la route, elle suit la route au lieu de l'escalier des cases)
	var all: Array[Vector2] = [from]
	for i in range(1, pts.size() - 1):
		all.append(pts[i])
	all.append(goal)
	var kept: Array[Vector2] = []
	var i0 := 0
	while i0 < all.size() - 1:
		var j := i0 + 1
		while j + 1 < all.size() and _straight_ok(all[i0], all[j + 1], all, i0, j + 1):
			j += 1
		kept.append(all[j])
		i0 = j
	return kept


## La ligne droite de a à b est-elle praticable et aussi rapide que les points all[i..j] qu'elle remplace ?
static func _straight_ok(a: Vector2, b: Vector2, all: Array[Vector2], i: int, j: int) -> bool:
	var slow := INF
	for k in range(i, j + 1):
		slow = minf(slow, speed_at(all[k]))
	var n := maxi(1, int(a.distance_to(b) / (CELL * 0.5)))
	for k in range(1, n):
		var p := a.lerp(b, float(k) / n)
		if not walkable(p) or speed_at(p) < slow - 0.001:
			return false
	return true


## Longueur d'un chemin depuis from.
static func path_length(from: Vector2, path: Array[Vector2]) -> float:
	var len := 0.0
	var at := from
	for p in path:
		len += at.distance_to(p)
		at = p
	return len
