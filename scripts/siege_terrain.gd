class_name SiegeTerrain
extends RefCounted
## Géométrie d'une ville fortifiée (terrains « town_assault » et « town_defense ») : rempart de
## pierre (front percé d'une porte, deux murs latéraux), tours, chemin de ronde, place de la ville
## et maisons. La ville touche le bord du champ (le reste de la ville est hors champ) : en assaut
## elle est en haut, chez l'ennemi ; en défense elle est en bas, chez le joueur.
##
## Ce script ne connaît que la géométrie et les ouvertures (porte enfoncée, échelles dressées) ;
## siege.gd fait vivre la mécanique et met à jour les ouvertures (set_openings), terrain.gd lui
## délègue route, wall_blocks, wall_shelters, height et speed_factor.
##
## Repère : depth(p) mesure la distance au milieu du rempart, positive vers l'intérieur de la ville.

const X0 := 760.0 ## Mur latéral gauche
const X1 := 2440.0 ## Mur latéral droit
const FRONT_ASSAULT := 760.0 ## Ligne du rempart en assaut (ville en haut)
const FRONT_DEFENSE := 1240.0 ## Ligne du rempart en défense (ville en bas)
const WALL_T := 20.0 ## Épaisseur du rempart au sol
const WALL_H := 24.0 ## Hauteur dessinée du rempart (vue de trois quarts)
const WALK := 44.0 ## Profondeur du chemin de ronde, derrière le parapet
const GATE_HALF := 28.0 ## Demi-largeur de la porte
const TOWER_HALF := 24.0 ## Demi-côté d'une tour
const LADDER_HALF := 10.0 ## Demi-largeur du passage d'une échelle
const PLAZA_DEPTH := 330.0 ## Distance de la place au rempart
const PLAZA_R := 130.0 ## Rayon de la place de la ville
const CLIMB_SPEED := 0.4 ## Vitesse sur une échelle
const HORSE_RADIUS := 7.0 ## Au-delà de ce rayon (les chevaux), on ne monte pas aux échelles

var defense := false ## Vrai : le joueur défend (ville en bas)
var front_y := FRONT_ASSAULT
var out_dir := 1.0 ## Sens de l'extérieur sur l'axe y (+1 : vers le bas, -1 : vers le haut)
var gate_x := 1600.0
var plaza := Vector2.ZERO
var towers: Array[Vector2] = [] ## Centres des tours (sur la ligne du rempart)
var openings: Array[Dictionary] = [] ## {"x", "half", "kind" : « gate » ou « ladder »}
var gate_open := false ## Porte enfoncée
var solid: Array[Rect2] = [] ## Rempart, porte fermée, tours et murs latéraux (obstacles)
var front_rects: Array[Rect2] = [] ## Tronçons du rempart (pour le dessin)
var side_rects: Array[Rect2] = [] ## Murs latéraux
var gate_rect := Rect2()
var world := Vector2(3200, 2000)


## Construit la ville. houses reçoit les maisons (dessinées et contournées comme celles du village).
func build(is_defense: bool, rng: RandomNumberGenerator, size: Vector2, houses: Array[Rect2]) -> void:
	defense = is_defense
	world = size
	front_y = FRONT_DEFENSE if defense else FRONT_ASSAULT
	out_dir = -1.0 if defense else 1.0
	gate_x = roundf(1600.0 + rng.randf_range(-160.0, 160.0))
	plaza = Vector2(1600.0, front_y - out_dir * PLAZA_DEPTH)
	towers.clear()
	var flank := GATE_HALF + TOWER_HALF
	for x in [X0, (X0 + gate_x - flank) * 0.5, gate_x - flank, gate_x + flank, (gate_x + flank + X1) * 0.5, X1]:
		towers.append(Vector2(roundf(x), front_y))
	var y0 := -80.0 if not defense else front_y
	var y1 := front_y if not defense else world.y + 80.0
	side_rects = [Rect2(X0 - WALL_T * 0.5, y0, WALL_T, y1 - y0), Rect2(X1 - WALL_T * 0.5, y0, WALL_T, y1 - y0)]
	gate_rect = Rect2(gate_x - GATE_HALF, front_y - WALL_T * 0.5, GATE_HALF * 2.0, WALL_T)
	make_houses(rng, houses)
	set_openings([])


## Maisons de la ville : loin du rempart, de la place et de la grand-rue (porte → place).
func make_houses(rng: RandomNumberGenerator, houses: Array[Rect2]) -> void:
	var tries := 0
	var made := 0
	while made < 12 and tries < 500:
		tries += 1
		var w := float(rng.randi_range(18, 28) * 2)
		var h := float(rng.randi_range(14, 19) * 2)
		var p := Vector2(rng.randf_range(X0 + 50.0, X1 - 50.0 - w), rng.randf_range(60.0, world.y - 60.0 - h)).round()
		var r := Rect2(p, Vector2(w, h))
		var near := minf(depth(r.position), depth(r.end))
		var far := maxf(depth(r.position), depth(r.end))
		if near < WALL_T * 0.5 + WALK + 80.0 or far > 900.0:
			continue
		if r.grow(PLAZA_R + 40.0).has_point(plaza) or absf(r.get_center().x - gate_x) < w * 0.5 + 80.0:
			continue
		var ok := true
		for o in houses:
			if o.grow(30.0).intersects(r):
				ok = false
				break
		if ok:
			houses.append(r)
			made += 1


## Ouvertures du rempart : la porte (si elle est enfoncée) et les échelles dressées (x de chacune).
func set_openings(ladder_xs: Array) -> void:
	openings.clear()
	if gate_open:
		openings.append({"x": gate_x, "half": GATE_HALF, "kind": "gate"})
	for x in ladder_xs:
		openings.append({"x": float(x), "half": LADDER_HALF, "kind": "ladder"})
	# Tronçons pleins du rempart, entre les ouvertures (la porte fermée est un obstacle à part)
	var cuts: Array = []
	for op in openings:
		cuts.append([float(op["x"]) - float(op["half"]), float(op["x"]) + float(op["half"])])
	if not gate_open:
		cuts.append([gate_rect.position.x, gate_rect.end.x])
	cuts.sort_custom(func(a, b): return a[0] < b[0])
	front_rects.clear()
	var x := X0 - WALL_T * 0.5
	for c in cuts:
		if c[0] > x:
			front_rects.append(Rect2(x, front_y - WALL_T * 0.5, c[0] - x, WALL_T))
		x = maxf(x, c[1])
	if X1 + WALL_T * 0.5 > x:
		front_rects.append(Rect2(x, front_y - WALL_T * 0.5, X1 + WALL_T * 0.5 - x, WALL_T))
	solid.clear()
	solid.append_array(front_rects)
	if not gate_open:
		solid.append(gate_rect)
	for t in towers:
		solid.append(Rect2(t - Vector2(TOWER_HALF, TOWER_HALF), Vector2(TOWER_HALF, TOWER_HALF) * 2.0))
	solid.append_array(side_rects)


# ---------------------------------------------------------------- Requêtes

## Distance au milieu du rempart, positive à l'intérieur de la ville.
func depth(p: Vector2) -> float:
	return (front_y - p.y) * out_dir


## Vrai si p est dans la ville (le rempart compris quand margin >= WALL_T / 2).
func inside(p: Vector2, margin := 0.0) -> bool:
	return p.x > X0 and p.x < X1 and depth(p) > -margin


## Vrai si p est dans le passage de la porte.
func in_gate(p: Vector2) -> bool:
	return absf(p.x - gate_x) < GATE_HALF + 4.0


## Vrai si p est sur le chemin de ronde (derrière le parapet, hors tours et passage de la porte).
func on_walk(p: Vector2) -> bool:
	var d := depth(p)
	return d > WALL_T * 0.5 - 2.0 and d < WALL_T * 0.5 + WALK and p.x > X0 + TOWER_HALF and p.x < X1 - TOWER_HALF and not in_gate(p)


## Ouverture d'échelle où se trouve p (dans l'épaisseur du rempart), {} sinon.
func ladder_at(p: Vector2) -> Dictionary:
	if absf(depth(p)) > WALL_T * 0.5 + 4.0:
		return {}
	for op in openings:
		if op["kind"] == "ladder" and absf(p.x - float(op["x"])) < float(op["half"]) + 2.0:
			return op
	return {}


## Hauteur du sol : 1 sur le chemin de ronde, 0,5 sur une échelle, 0 ailleurs.
func height(p: Vector2) -> float:
	if on_walk(p):
		return 1.0
	if not ladder_at(p).is_empty():
		return 0.5
	return 0.0


## Facteur de vitesse : on monte lentement à l'échelle.
func speed_factor(p: Vector2) -> float:
	return CLIMB_SPEED if not ladder_at(p).is_empty() else 1.0


## Vrai si le segment a→b traverse le rempart ou un mur latéral ailleurs que par une ouverture.
func blocks(a: Vector2, b: Vector2, radius := 0.0) -> bool:
	var da := depth(a)
	var db := depth(b)
	if da * db < 0.0:
		var x := lerpf(a.x, b.x, da / (da - db))
		if x > X0 - WALL_T and x < X1 + WALL_T:
			var open := false
			for op in openings:
				if absf(x - float(op["x"])) < float(op["half"]) - radius:
					open = true
					break
			if not open:
				return true
	for sx in [X0, X1]:
		if (a.x - sx) * (b.x - sx) < 0.0:
			var y := lerpf(a.y, b.y, (sx - a.x) / (b.x - a.x))
			if depth(Vector2(sx, y)) > -WALL_T * 0.5:
				return true
	return false


## Point de passage vers goal : l'ouverture la plus commode si le rempart barre la route
## (les chevaux ne montent pas aux échelles), sinon goal ramené hors des obstacles.
func route(p: Vector2, goal: Vector2, radius: float, terrain: Terrain) -> Vector2:
	if not blocks(p, goal, radius):
		return terrain.push_out(goal, radius)
	var best: Dictionary = {}
	var bd := INF
	for op in openings:
		if op["kind"] == "ladder" and radius > HORSE_RADIUS:
			continue
		var at := Vector2(float(op["x"]), front_y)
		var d := p.distance_to(at) + at.distance_to(goal)
		if d < bd:
			bd = d
			best = op
	if best.is_empty():
		return terrain.push_out(goal, radius) # Aucune ouverture : on attend au pied du mur
	var ox: float = best["x"]
	var room := maxf(float(best["half"]) - radius - 2.0, 0.0)
	var gate := Vector2(clampf(p.x, ox - room, ox + room), front_y)
	var side := -out_dir if inside(p) else out_dir # Côté du rempart où se trouve p (en y)
	if p.distance_to(gate) < WALL_T * 0.5 + 16.0:
		return gate - Vector2(0, side * (WALL_T * 0.5 + 30.0)) # Dans le passage : on le franchit
	return gate + Vector2(0, side * (WALL_T * 0.5 + 14.0)) # On se présente devant le passage


## Vrai si une flèche tirée de from vers p (derrière le rempart) est en partie arrêtée par le parapet.
func shelters(from: Vector2, p: Vector2) -> bool:
	var d := depth(p)
	if d <= 0.0 or d > WALL_T * 0.5 + 80.0 or depth(from) > -WALL_T * 0.5 or p.x < X0 or p.x > X1:
		return false
	for op in openings:
		if absf(p.x - float(op["x"])) < float(op["half"]) + 4.0:
			return false # Au débouché d'une échelle ou dans la porte : pas d'abri
	return true


## Emplacement libre d'une échelle le plus proche de want_x (ni porte, ni tour, ni autre échelle).
func ladder_spot(want_x: float, taken: Array) -> float:
	var step := 8.0
	for k in 260:
		for sgn in [1.0, -1.0]:
			var x := roundf(want_x + sgn * k * step)
			if ladder_ok(x, taken):
				return x
	return gate_x + GATE_HALF + TOWER_HALF * 2.0 + 60.0


func ladder_ok(x: float, taken: Array) -> bool:
	if x < X0 + TOWER_HALF + 30.0 or x > X1 - TOWER_HALF - 30.0:
		return false
	if absf(x - gate_x) < GATE_HALF + TOWER_HALF * 2.0 + 24.0:
		return false
	for t in towers:
		if absf(x - t.x) < TOWER_HALF + 18.0:
			return false
	for o in taken:
		if absf(x - float(o)) < 50.0:
			return false
	return true


## Pied d'une échelle (dehors) et débouché (sur le chemin de ronde) en x.
func ladder_foot(x: float) -> Vector2:
	return Vector2(x, front_y + out_dir * (WALL_T * 0.5 + 18.0))


func ladder_top(x: float) -> Vector2:
	return Vector2(x, front_y - out_dir * (WALL_T * 0.5 + 10.0))


## Là où le bélier frappe la porte (dehors).
func ram_spot() -> Vector2:
	return Vector2(gate_x, front_y + out_dir * (WALL_T * 0.5 + 26.0))


## Postes de la garnison sur le chemin de ronde (n emplacements, hors porte et tours).
func walk_posts(n: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var y := front_y - out_dir * (WALL_T * 0.5 + 22.0)
	for k in n:
		var x := lerpf(X0 + 170.0, X1 - 170.0, (k + 0.5) / float(maxi(n, 1)))
		if absf(x - gate_x) < 150.0:
			x = gate_x + signf(x - gate_x + 0.01) * 150.0
		out.append(Vector2(roundf(x), y))
	return out


## Point de la ville à depth en x (pour placer des régiments derrière le rempart).
func at_depth(x: float, d: float) -> Vector2:
	return Vector2(x, front_y - out_dir * d)
