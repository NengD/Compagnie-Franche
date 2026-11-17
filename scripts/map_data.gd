class_name MapData
extends RefCounted
## Carte du monde (seule source de vérité de la géographie) : taille, lieux, routes, relief,
## vitesse de marche et terrain de bataille selon l'endroit, chemins (A* sur une grille grossière).
##
## Coordonnées : pixels de la carte du monde (SIZE). La carte d'avant (880 x 720) est agrandie
## SCALE fois ; ses 7 villes gardent leur place relative. Une ville est un lieu (« town ») dont
## l'indice est aussi celui de CampaignState.TOWNS (contrats, recrutement, monde vivant).
##
## Pour étendre la carte : ajouter des lieux dans PLACES (village, château...) avec « link » (nom du
## lieu relié par une route), des étendues d'eau dans LAKES, et retoucher les bruits de relief.
## Tout le reste (dessin, vitesse, chemins, terrain de bataille) en découle.

const SCALE := 3.0 ## Agrandissement par rapport à l'ancienne carte (880 x 720)
const SIZE := Vector2(2640, 2160)
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

## Autres lieux (après les villes dans places()) : villages, châteaux... « link » : lieu relié par
## un chemin (nom). « faction » : seigneur (-1 : aucun).
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
]
## Étendues d'eau (ellipses) : centre, rayons. Un anneau de marais les entoure (MARSH_RING).
const LAKES := [
	{"center": Vector2(1960, 1790), "radius": Vector2(150, 85)},
	{"center": Vector2(360, 420), "radius": Vector2(110, 70)},
]
const MARSH_RING := 1.7 ## Rayon du marais autour d'un lac (x le rayon du lac)
const RIVER_HALF := 20.0 ## Demi-largeur de la rivière
const ROAD_HALF := 9.0 ## Demi-largeur d'une route (une case dont le centre est plus près est une route)
const PLACE_RADIUS := 34.0 ## Rayon d'un lieu (clic, arrivée)

## Sortes de terrain de la grille.
enum Ground { PLAIN, FOREST, HILLS, MARSH, WATER }
const GROUND_NAMES := ["plaine", "forêt", "collines", "marais", "eau"]
## Vitesse de marche selon le terrain (x la vitesse du groupe). L'eau ne se traverse qu'aux ponts.
const GROUND_SPEED := [1.0, 0.6, 0.7, 0.5, 0.0]
const ROAD_SPEED := 1.3 ## Sur une route (ou un pont)
## Terrains de bataille possibles (Terrain.KINDS, hors sièges) selon l'endroit (battle_terrain_at).
const BATTLE_TERRAINS := ["plain", "forest", "hills", "river", "village"]

static var _w := 0
static var _h := 0
static var _ground := PackedByteArray()
static var _road := PackedByteArray()
static var _height := PackedFloat32Array()
static var _places: Array[Dictionary] = []
static var _roads: Array = []
static var _astar: AStarGrid2D = null


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


## Toutes les routes, en paires d'indices de lieux : les grandes routes puis les chemins des lieux.
static func roads() -> Array:
	if _roads.is_empty():
		for r in TOWN_ROADS:
			_roads.append([int(r[0]), int(r[1])])
		for i in PLACES.size():
			var to := place_named(str(PLACES[i].get("link", "")))
			if to >= 0:
				_roads.append([TOWNS.size() + i, to])
	return _roads


## Distance d'un point à la route la plus proche.
static func road_distance(pos: Vector2) -> float:
	var best := INF
	for r in roads():
		var a := place_pos(r[0])
		var b := place_pos(r[1])
		best = minf(best, pos.distance_to(Geometry2D.get_closest_point_to_segment(pos, a, b)))
	return best


# ---------------------------------------------------------------- Relief

## Abscisse de la rivière qui traverse la carte du nord au sud (celle de l'ancienne carte, agrandie).
static func river_x(y: float) -> float:
	var oy := y / SCALE
	return SCALE * (440.0 + sin(oy * 0.011) * 70.0 + sin(oy * 0.031) * 18.0)


static func river_distance(pos: Vector2) -> float:
	return absf(pos.x - river_x(pos.y))


## « Distance » elliptique au lac le plus proche (1 : sur la rive, < 1 : dans l'eau).
static func lake_factor(pos: Vector2) -> float:
	var best := INF
	for l in LAKES:
		var d: Vector2 = (pos - l["center"]) / (l["radius"] as Vector2)
		best = minf(best, d.length())
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
	var relief := FastNoiseLite.new()
	relief.seed = 7
	relief.frequency = 0.02
	var wood := FastNoiseLite.new()
	wood.seed = 11
	wood.frequency = 0.03
	var wet := FastNoiseLite.new()
	wet.seed = 23
	wet.frequency = 0.04
	for y in _h:
		for x in _w:
			var i := y * _w + x
			var p := Vector2(x + 0.5, y + 0.5) * CELL
			var q := p / (SCALE * 4.0) # Mêmes bruits que l'ancienne carte (pixels de 4)
			var hgt := relief.get_noise_2d(q.x, q.y) * 0.5 + 0.5
			_height[i] = hgt
			var near_place := false
			for pl in places():
				if p.distance_to(pl["pos"]) < PLACE_RADIUS + 24.0:
					near_place = true
					break
			var rd := road_distance(p)
			_road[i] = 1 if rd <= ROAD_HALF + CELL * 0.35 else 0
			var g: int = Ground.PLAIN
			var lake := lake_factor(p)
			var river := river_distance(p)
			if lake < 1.0 or river < RIVER_HALF:
				g = Ground.WATER
			elif lake < MARSH_RING or (river < 90.0 and wet.get_noise_2d(q.x, q.y) > 0.35 and p.y > SIZE.y * 0.45):
				g = Ground.MARSH
			elif hgt > 0.68:
				g = Ground.HILLS
			elif wood.get_noise_2d(q.x, q.y) > 0.28 and rd > 40.0:
				g = Ground.FOREST
			if near_place and g != Ground.WATER:
				g = Ground.PLAIN
			_ground[i] = g


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


## Nom du terrain sous un point (« route », « forêt »...), pour l'infobulle.
static func ground_name(pos: Vector2) -> String:
	var g := ground_at(pos)
	if is_road(pos):
		return "pont" if g == Ground.WATER else "route"
	return str(GROUND_NAMES[g])


## Peut-on marcher ici ? (l'eau seulement par un pont)
static func walkable(pos: Vector2) -> bool:
	if pos.x < 0.0 or pos.y < 0.0 or pos.x > SIZE.x or pos.y > SIZE.y:
		return false
	return is_road(pos) or ground_at(pos) != Ground.WATER


## Vitesse de marche à cet endroit (x la vitesse du groupe) : route plus rapide, forêt, collines
## et marais plus lents. Hors de la carte ou dans l'eau : très lent (on ne devrait pas y être).
static func speed_at(pos: Vector2) -> float:
	if is_road(pos):
		return ROAD_SPEED
	var s := float(GROUND_SPEED[ground_at(pos)])
	return s if s > 0.0 else 0.25


## Terrain de bataille selon l'endroit (voir Terrain) : village près d'un lieu habité, rivière au
## bord de l'eau ou dans les marais, forêt, collines, sinon plaine.
static func battle_terrain_at(pos: Vector2) -> String:
	var pl := place_at(pos, 2.2)
	if pl >= 0:
		return "village"
	if river_distance(pos) < RIVER_HALF + 70.0 or lake_factor(pos) < MARSH_RING:
		return "river"
	match ground_at(pos):
		Ground.FOREST:
			return "forest"
		Ground.HILLS:
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
## qui préfère les routes et contourne l'eau. Le but est ramené sur la terre ferme s'il le faut.
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
