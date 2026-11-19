class_name Terrain
extends RefCounted
## Relief et obstacles du champ de bataille : collines, rivière et gués, village, palissade de siège.
## battle.gd garde les forêts et la route ; ce script décrit le reste et ses effets
## (vitesse, portée, dégâts, passages obligés) ainsi que leur rendu.

const KINDS := ["plain", "forest", "hills", "river", "village", "siege"]
const NAMES := {
	"plain": "rase campagne", "forest": "bois", "hills": "collines",
	"river": "rivière", "village": "village", "siege": "palissade",
	"town_assault": "assaut d'une ville", "town_defense": "défense d'une ville",
}
const HINTS := {
	"plain": "Terrain découvert, quelques bosquets.",
	"forest": "Bois épais : embuscades possibles.",
	"hills": "Collines : les archers en hauteur tirent plus loin, frapper d'en haut fait plus mal, monter ralentit.",
	"river": "Rivière : on la traverse lentement, sauf aux gués (passages clairs).",
	"village": "Village : les maisons bloquent le passage.",
	"siege": "Défendez la palissade : l'ennemi doit passer par les brèches, vos troupes derrière les pieux sont abritées des flèches.",
	"town_assault": "Ville fortifiée : le bélier enfonce la porte, les échelles se dressent au pied du rempart. Prenez la place.",
	"town_defense": "Ville fortifiée : vos tireurs sur le chemin de ronde tirent plus loin et sont abrités. Repoussez les échelles.",
}
## Vrais sièges (siege_terrain.gd, siege.gd) : hors de KINDS, ils ne sont jamais tirés au sort.
const TOWN_KINDS := ["town_assault", "town_defense"]

## Terrain d'après la ville d'un contrat de campagne (nom de CampaignState.TOWNS).
const TOWN_TERRAINS := {
	"Valombre": "forest",
	"Saint-Aubin": "village",
	"Montfaucon": "hills",
	"Brévannes": "river",
	"Castelroux": "hills",
	"Hautemure": "plain",
	"Pontrieux": "river",
}
## Villes fortifiées : leurs contrats de difficulté 3 sont des défenses de palissade.
const SIEGE_TOWNS := ["Hautemure", "Castelroux"]

const OVERLAY_SCALE := 4.0 ## Taille d'un pixel de la couche de terrain dans le monde
const HEIGHT_CELL := 16.0 ## Pas de la grille des hauteurs
const RIVER_HALF := 34.0 ## Demi-largeur de la rivière
const FORD_HALF := 46.0 ## Demi-largeur d'un gué (le long de la rivière)
const WATER_SPEED := 0.35 ## Vitesse dans l'eau profonde
const UPHILL_SLOW := 6.0 ## Ralentissement par unité de hauteur gagnée sur 20 px
const UPHILL_MAX := 0.45 ## Ralentissement maximal en montée
const HILL_RANGE := 0.35 ## Portée des archers : +35 % au sommet
const HILL_DAMAGE := 0.5 ## Dégâts : +50 % par unité de hauteur d'avance sur la cible
const WALL_Y := 1330.0 ## Ligne de la palissade (devant la zone de déploiement du joueur)
const WALL_HALF := 6.0 ## Demi-épaisseur de la palissade
const BREACH_HALF := 56.0 ## Demi-largeur d'une brèche
const WALL_COVER := 0.5 ## Part des flèches arrêtées par les pieux
const SIEGE_REINFORCEMENTS := ["archer"] ## Régiments ajoutés à l'assaillant
const WALL_COVER_DIST := 80.0 ## Distance derrière la palissade où l'on est abrité
const BRIDGE_HALF := 30.0 ## Demi-largeur d'un pont (le long de la rivière)
const POND_CELL := 20.0 ## Pas de la grille de l'eau des lacs
const EXTRA_ROAD_HALF := 16.0 ## Demi-largeur des routes de la carte qui croisent le champ

var kind := "plain"
var active := true ## Faux : terrain neutre (sert aux tests des ordres)
var world := Vector2(3200, 2000)
var road_y: Callable ## Hauteur de la route / de la rivière en x (fournie par battle.gd)

var hills: Array = [] ## [centre, rayon (sigma), hauteur]
var heights := PackedFloat32Array()
var hw := 0
var hh := 0
var fords: Array[float] = [] ## Abscisses des gués
var houses: Array[Rect2] = [] ## Emprise au sol des maisons
var village_rect := Rect2()
var breaches: Array[float] = [] ## Abscisses des brèches de la palissade
var walls: Array[Rect2] = [] ## Tronçons de palissade
var obstacles: Array[Rect2] = [] ## Maisons + palissade (+ rempart et tours d'une ville fortifiée)
var town: SiegeTerrain = null ## Ville fortifiée (terrains TOWN_KINDS), null sinon
## Champ tiré de la carte (battle_site.gd) : vide = ancien tirage au sort
var site: Dictionary = {}
var river_on := false ## Une rivière traverse le champ (sa ligne : road_y)
var road_main := true ## Une route le traverse d'ouest en est (sa ligne : road_y)
var line: Array = [] ## Hauteurs de la rivière ou de la route du site (voir BattleSite.line_y)
var extra_roads: Array[PackedVector2Array] = [] ## Autres routes du site (elles franchissent la rivière)
var extra_boxes: Array[Rect2] = []
var bridges: Array[float] = [] ## Abscisses des ponts (ils comptent aussi parmi les gués)
var ponds := PackedByteArray() ## Eau des lacs : 2 dans l'eau, 1 sur la rive, 0 ailleurs
var pw := 0
var ph := 0


## Terrain d'un contrat de campagne (ville et difficulté).
static func for_contract(town: int, difficulty: int, towns: Array) -> String:
	if town < 0 or town >= towns.size():
		return "plain"
	var name := str(towns[town]["name"])
	if difficulty >= 3 and name in SIEGE_TOWNS:
		return "siege"
	return str(TOWN_TERRAINS.get(name, "plain"))


func display_name() -> String:
	return str(NAMES.get(kind, kind))


## Où se livre la bataille sur la carte (« au pont sur la Vionne, près de... »), "" hors site.
func place_text() -> String:
	return str(site.get("label", ""))


func hint() -> String:
	return str(HINTS.get(kind, ""))


## Nombre de forêts à générer pour ce terrain.
func forest_count() -> int:
	match kind:
		"forest":
			return 11
		"hills", "village", "siege", "town_assault", "town_defense":
			return 3
	return 6


func has_road() -> bool:
	return road_main and not river_on


func has_river() -> bool:
	return river_on


## s : descripteur du champ tiré de la carte (BattleSite.describe) ; vide = tirage au sort.
func setup(k: String, rng: RandomNumberGenerator, size: Vector2, road: Callable, s: Dictionary = {}) -> void:
	kind = k if k in KINDS or k in TOWN_KINDS else "plain"
	world = size
	road_y = road
	river_on = kind == "river"
	road_main = true
	site = BattleSite.sanitize(s) if kind in MapData.BATTLE_TERRAINS else {}
	if not site.is_empty():
		kind = str(site["kind"])
		apply_site(rng)
		refresh_obstacles()
		return
	match kind:
		"hills":
			make_hills(rng)
		"river":
			var xs := [rng.randf_range(0.18, 0.3), rng.randf_range(0.45, 0.55), rng.randf_range(0.7, 0.82)]
			var n := 3 if rng.randf() < 0.5 else 2
			if n == 2:
				xs = [xs[0], xs[2]]
			for x in xs:
				fords.append(float(x) * world.x)
		"village":
			make_village(rng)
		"siege":
			make_wall(rng)
		"town_assault", "town_defense":
			town = SiegeTerrain.new()
			town.build(kind == "town_defense", rng, world, houses)
	refresh_obstacles()


## Obstacles : maisons, palissade, rempart et tours (le rempart change quand une échelle se dresse).
func refresh_obstacles() -> void:
	obstacles.clear()
	obstacles.append_array(houses)
	obstacles.append_array(walls)
	if town != null:
		obstacles.append_array(town.solid)


## Champ tiré de la carte : rivière ou route, passages, autres routes, relief, lacs, village.
## (Les bois du site sont plantés par BattleSim.generate_world.)
func apply_site(rng: RandomNumberGenerator) -> void:
	line = site["line"]
	river_on = bool(site["river"])
	road_main = bool(site["road"]) and not river_on
	for r in site["roads"]:
		if not r is Array:
			continue
		var pts := PackedVector2Array()
		for j in range(0, (r as Array).size() - 1, 2):
			pts.append(Vector2(float(r[j]), float(r[j + 1])))
		if pts.size() < 2:
			continue
		var box := Rect2(pts[0], Vector2.ZERO)
		for p in pts:
			box = box.expand(p)
		extra_roads.append(pts)
		extra_boxes.append(box.grow(EXTRA_ROAD_HALF + 24.0))
	if river_on:
		for c in site["crossings"]:
			if not c is Array or (c as Array).size() < 2:
				continue
			fords.append(float(c[0]))
			if str(c[1]) == "bridge":
				bridges.append(float(c[0]))
	for h in site["hills"]:
		if h is Array and (h as Array).size() >= 4:
			hills.append([Vector2(float(h[0]), float(h[1])), float(h[2]), float(h[3])])
	if not hills.is_empty():
		build_heights()
	elif kind == "hills":
		make_hills(rng)
	if not (site["ponds"] as Array).is_empty():
		build_ponds(site["ponds"])
	if kind == "village":
		var v: Array = site["village"]
		make_village(rng, float(v[0]) if v.size() >= 2 else NAN)


## Vrai si p est sur une des routes du site qui croisent le champ.
func on_extra_road(p: Vector2, half: float) -> bool:
	for i in extra_roads.size():
		if not extra_boxes[i].has_point(p):
			continue
		var pts := extra_roads[i]
		for j in pts.size() - 1:
			if p.distance_squared_to(Geometry2D.get_closest_point_to_segment(p, pts[j], pts[j + 1])) < half * half:
				return true
	return false


func build_ponds(list: Array) -> void:
	pw = int(world.x / POND_CELL) + 1
	ph = int(world.y / POND_CELL) + 1
	ponds.resize(pw * ph)
	ponds.fill(0)
	for c in list:
		if not c is Array or (c as Array).size() < 3:
			continue
		var at := Vector2(float(c[0]), float(c[1]))
		var r := float(c[2])
		var n := int((r + 16.0) / POND_CELL) + 1
		var gc := Vector2i(at / POND_CELL)
		for y in range(gc.y - n, gc.y + n + 1):
			for x in range(gc.x - n, gc.x + n + 1):
				if x < 0 or y < 0 or x >= pw or y >= ph:
					continue
				var d := ((Vector2(x, y) + Vector2(0.5, 0.5)) * POND_CELL - at).length()
				var v := 2 if d < r else (1 if d < r + 16.0 else 0)
				ponds[y * pw + x] = maxi(ponds[y * pw + x], v)


## Dans l'eau d'un lac (margin > 0 : sur sa rive aussi).
func in_pond(p: Vector2, margin := 0.0) -> bool:
	if ponds.is_empty():
		return false
	var x := int(p.x / POND_CELL)
	var y := int(p.y / POND_CELL)
	if x < 0 or y < 0 or x >= pw or y >= ph:
		return false
	return ponds[y * pw + x] >= (1 if margin > 0.0 else 2)


func make_hills(rng: RandomNumberGenerator) -> void:
	var n := rng.randi_range(3, 4)
	for i in n:
		# Collines entre les deux armées, plutôt sur les côtés pour laisser des choix
		var c := Vector2(rng.randf_range(350, world.x - 350), rng.randf_range(520, 1350))
		hills.append([c, rng.randf_range(150, 230), rng.randf_range(0.7, 1.0)])
	build_heights()


## Grille des hauteurs d'après les collines (centre, rayon, hauteur).
func build_heights() -> void:
	hw = int(world.x / HEIGHT_CELL) + 2
	hh = int(world.y / HEIGHT_CELL) + 2
	heights.resize(hw * hh)
	for y in hh:
		for x in hw:
			var p := Vector2(x, y) * HEIGHT_CELL
			var h := 0.0
			for hl in hills:
				var s: float = hl[1]
				h += float(hl[2]) * exp(-p.distance_squared_to(hl[0]) / (2.0 * s * s))
			heights[y * hw + x] = 1.0 - exp(-2.0 * h) # Sommets arrondis, sans plateau


func make_village(rng: RandomNumberGenerator, at_x := NAN) -> void:
	var cx := rng.randf_range(world.x * 0.35, world.x * 0.65)
	if not is_nan(at_x):
		cx = at_x # Le village de la carte
	var cy: float = road_y.call(cx)
	if not site.is_empty() and not road_main and not river_on:
		var v: Array = site["village"]
		cy = float(v[1]) if v.size() >= 2 else world.y * 0.5
	village_rect = Rect2(cx - 330, cy - 230, 660, 460)
	var tries := 0
	while houses.size() < 11 and tries < 400:
		tries += 1
		var w := float(rng.randi_range(18, 28) * 2)
		var h := float(rng.randi_range(14, 19) * 2)
		var p := Vector2(rng.randf_range(village_rect.position.x, village_rect.end.x - w),
			rng.randf_range(village_rect.position.y, village_rect.end.y - h)).round()
		var r := Rect2(p, Vector2(w, h))
		# Pas sur la route (les maisons la bordent)
		var ry: float = road_y.call(r.get_center().x)
		if (road_main or river_on) and r.end.y + 26.0 > ry - 18.0 and r.position.y - 26.0 < ry + 18.0:
			continue
		if on_extra_road(r.get_center(), maxf(w, h) * 0.5 + 26.0) or in_pond(r.get_center(), 1.0):
			continue
		var ok := true
		for o in houses:
			if o.grow(30.0).intersects(r):
				ok = false
				break
		if ok:
			houses.append(r)


func make_wall(rng: RandomNumberGenerator) -> void:
	breaches = [rng.randf_range(0.26, 0.34) * world.x, rng.randf_range(0.66, 0.74) * world.x]
	var x := -40.0
	for b in breaches:
		walls.append(Rect2(x, WALL_Y - WALL_HALF, b - BREACH_HALF - x, WALL_HALF * 2.0))
		x = b + BREACH_HALF
	walls.append(Rect2(x, WALL_Y - WALL_HALF, world.x + 40.0 - x, WALL_HALF * 2.0))


## Une forêt de centre c et rayon r peut-elle être placée ici ?
func forest_ok(c: Vector2, r: float) -> bool:
	if kind == "village" and village_rect.grow(r + 40.0).has_point(c):
		return false
	if kind == "siege" and absf(c.y - WALL_Y) < r + 50.0:
		return false
	if in_pond(c):
		return false
	if town != null and town.depth(c) > -r - 60.0 and c.x > SiegeTerrain.X0 - r - 60.0 and c.x < SiegeTerrain.X1 + r + 60.0:
		return false
	return true


## Un arbre isolé ou de forêt peut-il pousser en p ?
func tree_ok(p: Vector2) -> bool:
	if is_river(p, 10.0):
		return false
	if town != null and town.depth(p) > -40.0 and p.x > SiegeTerrain.X0 - 40.0 and p.x < SiegeTerrain.X1 + 40.0:
		return false
	for o in obstacles:
		if o.grow(10.0).has_point(p):
			return false
	return true


# ---------------------------------------------------------------- Relief

## Hauteur du sol en p, de 0 (plaine) à 1 (sommet).
func height(p: Vector2) -> float:
	if town != null:
		return town.height(p) if active else 0.0 # Chemin de ronde
	if not active or heights.is_empty():
		return 0.0
	var gx := clampf(p.x / HEIGHT_CELL, 0.0, hw - 1.001)
	var gy := clampf(p.y / HEIGHT_CELL, 0.0, hh - 1.001)
	var x0 := int(gx)
	var y0 := int(gy)
	var fx := gx - x0
	var fy := gy - y0
	var i := y0 * hw + x0
	var top := lerpf(heights[i], heights[i + 1], fx)
	var bot := lerpf(heights[i + hw], heights[i + hw + 1], fx)
	return lerpf(top, bot, fy)


## Facteur de portée des archers postés en p.
func range_factor(p: Vector2) -> float:
	return 1.0 + HILL_RANGE * height(p)


## Facteur de dégâts d'un coup porté de a vers b (avantage de la hauteur).
func height_damage(a: Vector2, b: Vector2) -> float:
	return 1.0 + HILL_DAMAGE * maxf(height(a) - height(b), 0.0)


# ---------------------------------------------------------------- Rivière

## Vrai si p est dans le lit de la rivière (marge en plus de la largeur).
## (Ou dans l'eau d'un lac du site.)
func is_river(p: Vector2, margin := 0.0) -> bool:
	if river_on and road_y.is_valid() and absf(p.y - float(road_y.call(p.x))) < RIVER_HALF + margin:
		return true
	return in_pond(p, margin)


func is_ford(p: Vector2) -> bool:
	for f in fords:
		if absf(p.x - f) < (BRIDGE_HALF if bridges.has(f) else FORD_HALF):
			return true
	return false


func is_bridge(p: Vector2) -> bool:
	for f in bridges:
		if absf(p.x - f) < BRIDGE_HALF:
			return true
	return false


## Eau profonde (hors gué ou pont, ou lac) : on y avance lentement.
func is_deep_water(p: Vector2) -> bool:
	if not active:
		return false
	if in_pond(p):
		return true
	return river_on and is_river(p) and not is_ford(p)


# ---------------------------------------------------------------- Requêtes pour l'IA

const FORD_EXIT := 90.0 ## Distance à la rivière des points d'entrée et de sortie d'un gué
const FORD_DETOUR := 520.0 ## Détour maximal (en px) accepté pour passer par un gué plutôt qu'à la nage


## Point le plus haut à moins de radius de p (balayage de la grille des hauteurs).
func highest_near(p: Vector2, radius: float) -> Vector2:
	if heights.is_empty():
		return p
	var best := p
	var bh := height(p)
	var stride := HEIGHT_CELL * 2.0
	var n := int(radius / stride)
	for j in range(-n, n + 1):
		for i in range(-n, n + 1):
			var q := p + Vector2(i, j) * stride
			if q.distance_to(p) > radius or q.x < 0.0 or q.y < 0.0 or q.x > world.x or q.y > world.y:
				continue
			var h := height(q)
			if h > bh:
				bh = h
				best = q
	return best


## Sommets des collines (un par colline, au point réellement le plus haut).
func hill_tops() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for hl in hills:
		out.append(highest_near(hl[0], 120.0))
	return out


## Rive où se trouve p : -1 au nord de la rivière, 1 au sud, 0 dans le lit (ou pas de rivière).
func river_side(p: Vector2) -> float:
	if not has_river() or not road_y.is_valid():
		return 0.0
	var dy := p.y - float(road_y.call(p.x))
	if absf(dy) < RIVER_HALF:
		return 0.0
	return signf(dy)


## Vrai si aller de a à b oblige à traverser la rivière.
func crosses_river(a: Vector2, b: Vector2) -> bool:
	var sa := river_side(a)
	var sb := river_side(b)
	return sa != 0.0 and sb != 0.0 and sa != sb


## Prochain point de passage de from vers goal : si la rivière les sépare, le gué le plus avantageux
## (d'abord l'entrée sur sa rive, alignée sur le gué, puis la sortie sur l'autre rive) ;
## sinon, ou si le détour dépasse max_detour par rapport à la traversée à la nage, goal lui-même.
func ford_waypoint(from: Vector2, goal: Vector2, max_detour := FORD_DETOUR) -> Vector2:
	if not active or fords.is_empty() or not has_river():
		return goal
	var sf := river_side(from)
	var sg := river_side(goal)
	if sg == 0.0:
		return goal
	if sf == 0.0:
		# Dans le lit : sur un gué on achève la traversée tout droit, sinon on sort au plus court
		return Vector2(from.x, float(road_y.call(from.x)) + sg * FORD_EXIT) if is_ford(from) else goal
	if sf == sg:
		return goal
	var best := INF
	var fx := 0.0
	for f in fords:
		var fp := Vector2(f, float(road_y.call(f)))
		var c := from.distance_to(fp) + fp.distance_to(goal)
		if c < best:
			best = c
			fx = f
	var wade := from.distance_to(goal) + 2.0 * RIVER_HALF * (1.0 / WATER_SPEED - 1.0)
	if best - wade > max_detour:
		return goal
	var ry: float = road_y.call(fx)
	if absf(from.x - fx) < FORD_HALF * 0.6 and absf(from.y - ry) < FORD_EXIT + 60.0:
		return Vector2(fx, ry - sf * FORD_EXIT) # Aligné sur le gué : on traverse
	return Vector2(fx, ry + sf * FORD_EXIT) # On rejoint l'entrée du gué sur sa rive


# ---------------------------------------------------------------- Déplacement

## Facteur de vitesse d'un soldat en p qui avance dans la direction dir.
func speed_factor(p: Vector2, dir: Vector2, type: String) -> float:
	if not active:
		return 1.0
	var f := 1.0
	if town != null:
		f *= town.speed_factor(p) # Échelles
	if is_deep_water(p):
		f *= WATER_SPEED * (1.2 if type == "cavalry" else 1.0)
	if not heights.is_empty():
		var rise := height(p + dir * 20.0) - height(p)
		f *= 1.0 - clampf(rise * UPHILL_SLOW, 0.0, UPHILL_MAX)
	return f


## Point de passage vers goal : une brèche si la palissade barre la route, sinon goal lui-même
## (ramené hors des obstacles s'il tombe dedans).
func route(p: Vector2, goal: Vector2, radius: float) -> Vector2:
	if not active:
		return goal
	if town != null:
		return town.route(p, goal, radius, self) # Porte enfoncée ou échelle
	if not walls.is_empty() and wall_blocks(p, goal, radius):
		var best := 0.0
		var bd := INF
		for b in breaches:
			var bp := Vector2(b, WALL_Y)
			var d := p.distance_to(bp) + bp.distance_to(goal)
			if d < bd:
				bd = d
				best = b
		var side := signf(p.y - WALL_Y)
		if side == 0.0:
			side = 1.0
		var gate := Vector2(clampf(p.x, best - BREACH_HALF + radius + 6.0, best + BREACH_HALF - radius - 6.0), WALL_Y)
		if p.distance_to(gate) < 30.0:
			return gate - Vector2(0, side * 40.0) # Dans la brèche : on la franchit
		return gate + Vector2(0, side * 22.0) # On se présente devant la brèche
	return push_out(goal, radius)


## Vrai si le segment a→b traverse la palissade ailleurs que dans une brèche.
func wall_blocks(a: Vector2, b: Vector2, radius := 0.0) -> bool:
	if town != null:
		return active and town.blocks(a, b, radius)
	if walls.is_empty() or not active:
		return false
	var da := a.y - WALL_Y
	var db := b.y - WALL_Y
	if da * db >= 0.0:
		return false
	var x := lerpf(a.x, b.x, da / (da - db))
	for br in breaches:
		if absf(x - br) < BREACH_HALF - radius:
			return false
	return true


## Direction de marche corrigée : longe un obstacle au lieu d'y entrer.
func steer(p: Vector2, dir: Vector2, radius: float, goal: Vector2) -> Vector2:
	if not active or obstacles.is_empty():
		return dir
	var ahead := p + dir * (radius + 3.0)
	for o in obstacles:
		var g := o.grow(radius)
		if not g.has_point(ahead):
			continue
		# Face de l'obstacle la plus proche de p : on glisse le long de cette face
		var n := face_normal(g, p)
		var t := Vector2(-n.y, n.x)
		var to_goal := goal - p
		var tg := t.dot(to_goal)
		if absf(tg) < 0.3 * to_goal.length():
			# But droit derrière l'obstacle : on contourne par le coin le plus proche
			tg = t.dot(p - g.get_center())
			if absf(tg) < 0.5:
				tg = 1.0
		return t if tg > 0.0 else -t
	return dir


## Normale de la face de r la plus proche de p (vers l'extérieur).
static func face_normal(r: Rect2, p: Vector2) -> Vector2:
	var dl := absf(p.x - r.position.x)
	var dr := absf(r.end.x - p.x)
	var dt := absf(p.y - r.position.y)
	var db := absf(r.end.y - p.y)
	var m := minf(minf(dl, dr), minf(dt, db))
	if m == dt:
		return Vector2.UP
	if m == db:
		return Vector2.DOWN
	if m == dl:
		return Vector2.LEFT
	return Vector2.RIGHT


## Ramène p hors des obstacles (soldat de rayon radius).
func push_out(p: Vector2, radius: float) -> Vector2:
	if not active:
		return p
	for o in obstacles:
		var g := o.grow(radius)
		if not g.has_point(p):
			continue
		var n := face_normal(g, p)
		if n == Vector2.UP:
			p.y = g.position.y - 0.01
		elif n == Vector2.DOWN:
			p.y = g.end.y + 0.01
		elif n == Vector2.LEFT:
			p.x = g.position.x - 0.01
		else:
			p.x = g.end.x + 0.01
	return p


func blocked_at(p: Vector2, radius := 0.0) -> bool:
	for o in obstacles:
		if o.grow(radius).has_point(p):
			return true
	return false


## Vrai si une flèche tirée de from vers un soldat en p est en partie arrêtée par la palissade.
func wall_shelters(from: Vector2, p: Vector2) -> bool:
	if town != null:
		return active and town.shelters(from, p)
	if walls.is_empty() or not active:
		return false
	if absf(p.y - WALL_Y) > WALL_COVER_DIST or (from.y - WALL_Y) * (p.y - WALL_Y) >= 0.0:
		return false
	for br in breaches:
		if absf(p.x - br) < BREACH_HALF:
			return false # Dans la brèche, pas d'abri
	return true


# ---------------------------------------------------------------- Rendu

## Couche transparente posée sur le sol : relief (éclairci + courbes de niveau), rivière et gués.
## Renvoie null si le terrain n'en a pas besoin.
func build_overlay(rng: RandomNumberGenerator) -> ImageTexture:
	if heights.is_empty() and not river_on and ponds.is_empty():
		return null
	var w := int(world.x / OVERLAY_SCALE)
	var h := int(world.y / OVERLAY_SCALE)
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var was := active
	active = true
	if not heights.is_empty():
		var prev := PackedInt32Array()
		prev.resize(w)
		for y in h:
			var left := -1
			for x in w:
				var p := (Vector2(x, y) + Vector2(0.5, 0.5)) * OVERLAY_SCALE
				var hv := height(p)
				var lv := int(hv * 6.0)
				var c := Color(0, 0, 0, 0)
				if hv > 0.04:
					# Éclairé par le haut à gauche : versants nord-ouest plus clairs
					var slope := height(p + Vector2(-10, -10)) - hv
					c = Color(1.0, 0.96, 0.75, clampf(0.05 + hv * 0.16 + slope * 1.5, 0.0, 0.3))
				if (y > 0 and lv != prev[x]) or (x > 0 and lv != left):
					c = Color(0.28, 0.22, 0.1, 0.42) # Courbe de niveau
				img.set_pixel(x, y, c)
				prev[x] = lv
				left = lv
	if not ponds.is_empty():
		for y in h:
			for x in w:
				var p := (Vector2(x, y) + Vector2(0.5, 0.5)) * OVERLAY_SCALE
				if in_pond(p):
					var c := Color(0.22, 0.4, 0.62)
					if (x * 7 + y * 13) % 23 == 0:
						c = c.lightened(0.2) # Reflets
					img.set_pixel(x, y, c)
				elif in_pond(p, 1.0):
					img.set_pixel(x, y, Color(0.42, 0.36, 0.22, 0.8)) # Rive
	if river_on:
		var noise := FastNoiseLite.new()
		noise.seed = rng.randi()
		noise.frequency = 0.02
		for x in w:
			var wx := (x + 0.5) * OVERLAY_SCALE
			var ry: float = road_y.call(wx)
			var ford := is_ford(Vector2(wx, ry))
			var bridge := INF ## Écart au milieu du pont le plus proche (INF : pas de pont ici)
			for b in bridges:
				if absf(wx - b) < BRIDGE_HALF:
					bridge = wx - b
			var y0 := maxi(int((ry - RIVER_HALF - 10.0) / OVERLAY_SCALE), 0)
			var y1 := mini(int((ry + RIVER_HALF + 10.0) / OVERLAY_SCALE), h - 1)
			for y in range(y0, y1 + 1):
				var wy := (y + 0.5) * OVERLAY_SCALE
				var d := absf(wy - ry)
				var c: Color
				if bridge < INF:
					# Pont de planches, garde-corps sombres sur les bords
					c = Color(0.52, 0.37, 0.2) if int(wy / 8.0) % 2 == 0 else Color(0.45, 0.31, 0.16)
					if absf(bridge) > BRIDGE_HALF - 6.0:
						c = Color(0.3, 0.2, 0.1)
				elif d >= RIVER_HALF:
					c = Color(0.42, 0.34, 0.2, 0.85) # Berge boueuse
				elif ford:
					c = Color(0.44, 0.6, 0.68)
					if rng.randf() < 0.18:
						c = Color(0.62, 0.6, 0.52) # Galets du gué
				else:
					var deep := 1.0 - d / RIVER_HALF
					c = Color(0.3, 0.5, 0.72).lerp(Color(0.15, 0.3, 0.55), deep)
					if noise.get_noise_2d(wx * 0.6, wy * 2.0) > 0.45:
						c = c.lightened(0.25) # Reflets
				img.set_pixel(x, y, c)
	active = was
	return ImageTexture.create_from_image(img)
