class_name MapIcons
extends RefCounted
## Petites figurines des groupes sur la carte du monde (campaign_map.gd, world_view.gd) :
## caravane (charrette et bœufs), villageois, patrouille et armée (cavaliers et bannière de la
## faction), bandits et déserteurs (silhouettes), et la compagnie du joueur (ses armoiries).
##
## Toutes les fonctions dessinent en pixels de carte, les pieds du groupe en (0, 0), tournées vers
## la droite : l'appelant pose la transformation (position, miroir quand le groupe va vers
## l'ouest). step (0 ou 1) alterne les jambes d'un groupe qui marche.

const WOOD := Color(0.48, 0.32, 0.17)
const SKIN := Color(0.9, 0.74, 0.58)
const DARK := Color(0.16, 0.12, 0.1)
const STEEL := Color(0.78, 0.8, 0.84)
const SHADOW := Color(0, 0, 0, 0.25)


## Ombre au sol, ovale.
static func shadow(ci: CanvasItem, w: float) -> void:
	var pts := PackedVector2Array()
	for k in 14:
		var a := TAU * k / 14.0
		pts.append(Vector2(cos(a) * w, 1.0 + sin(a) * w * 0.28))
	ci.draw_colored_polygon(pts, SHADOW)


## Un piéton : jambes, tunique, tête (capuche ou chapeau). x : position, kind : « hat », « hood », « helm ».
static func walker(ci: CanvasItem, x: float, tunic: Color, head: String, step: int) -> void:
	var o := Vector2(x, 0)
	var lift := 1.0 if step == 1 else 0.0
	ci.draw_rect(Rect2(o + Vector2(0, -3 + lift), Vector2(1, 3 - lift)), DARK)
	ci.draw_rect(Rect2(o + Vector2(2, -3), Vector2(1, 3)), DARK)
	ci.draw_rect(Rect2(o + Vector2(0, -7), Vector2(3, 4)), tunic)
	ci.draw_rect(Rect2(o + Vector2(0, -9), Vector2(3, 2)), SKIN)
	match head:
		"hat": # Chapeau de paille
			ci.draw_rect(Rect2(o + Vector2(-1, -10), Vector2(5, 1)), Color(0.86, 0.76, 0.42))
		"hood": # Capuche pointue
			ci.draw_rect(Rect2(o + Vector2(0, -10), Vector2(3, 2)), tunic.darkened(0.2))
			ci.draw_rect(Rect2(o + Vector2(0, -9), Vector2(1, 2)), tunic.darkened(0.2))
			ci.draw_rect(Rect2(o + Vector2(1, -11), Vector2(1, 1)), tunic.darkened(0.2))
		"helm":
			ci.draw_rect(Rect2(o + Vector2(0, -10), Vector2(3, 2)), STEEL.darkened(0.15))


## Un cavalier : cheval, cavalier à la tunique de la faction, lance.
static func rider(ci: CanvasItem, x: float, coat: Color, tabard: Color, step: int, lance := true) -> void:
	var o := Vector2(x, 0)
	# Jambes du cheval (alternées au pas)
	var a := 1.0 if step == 1 else 0.0
	ci.draw_rect(Rect2(o + Vector2(-4 + a, -3), Vector2(1, 3)), coat.darkened(0.35))
	ci.draw_rect(Rect2(o + Vector2(-2 - a, -3), Vector2(1, 3)), coat.darkened(0.2))
	ci.draw_rect(Rect2(o + Vector2(2 + a, -3), Vector2(1, 3)), coat.darkened(0.35))
	ci.draw_rect(Rect2(o + Vector2(4 - a, -3), Vector2(1, 3)), coat.darkened(0.2))
	ci.draw_rect(Rect2(o + Vector2(-5, -7), Vector2(11, 4)), coat) # Corps
	ci.draw_rect(Rect2(o + Vector2(-6, -7), Vector2(1, 3)), coat.darkened(0.4)) # Queue
	ci.draw_rect(Rect2(o + Vector2(5, -10), Vector2(2, 4)), coat) # Encolure
	ci.draw_rect(Rect2(o + Vector2(6, -11), Vector2(3, 2)), coat) # Tête
	ci.draw_rect(Rect2(o + Vector2(5, -11), Vector2(1, 1)), coat.darkened(0.4)) # Crinière
	# Cavalier
	ci.draw_rect(Rect2(o + Vector2(-1, -12), Vector2(3, 5)), tabard)
	ci.draw_rect(Rect2(o + Vector2(-1, -14), Vector2(3, 2)), STEEL)
	ci.draw_rect(Rect2(o + Vector2(0, -8), Vector2(1, 2)), DARK) # Jambe
	if lance:
		ci.draw_line(o + Vector2(2, -6), o + Vector2(6, -20), WOOD.lightened(0.15), 1.0)
		ci.draw_rect(Rect2(o + Vector2(6, -21), Vector2(1, 2)), STEEL)


## Bannière : hampe et drapeau (fourché si forked), de la couleur col.
static func banner(ci: CanvasItem, at: Vector2, col: Color, h: float, w: float, forked := false, torn := false) -> void:
	ci.draw_line(at, at + Vector2(0, -h), WOOD, 1.5)
	var top := at + Vector2(1, -h)
	var fh := w * 0.65
	var pts := PackedVector2Array([top, top + Vector2(w, 0)])
	if forked:
		pts.append(top + Vector2(w - 3, fh * 0.5))
	if torn:
		pts.append_array([top + Vector2(w - 1, fh * 0.7), top + Vector2(w * 0.6, fh * 0.55), top + Vector2(w * 0.35, fh)])
	else:
		pts.append(top + Vector2(w, fh))
	pts.append(top + Vector2(0, fh))
	ci.draw_colored_polygon(pts, col)
	pts.append(top)
	ci.draw_polyline(pts, Color(0, 0, 0, 0.55), 1.0)
	ci.draw_circle(at + Vector2(0, -h - 1), 1.0, Color(0.95, 0.85, 0.5))


## Caravane : deux bœufs attelés devant une charrette bâchée.
static func caravan(ci: CanvasItem, n: int, step: int) -> void:
	shadow(ci, 15.0)
	var ox := Color(0.55, 0.38, 0.24)
	for k in 2:
		var o := Vector2(5 + k * 0.5, -k * 2.0)
		var c := ox.darkened(0.15 * k)
		var a := 1.0 if (step + k) % 2 == 1 else 0.0
		ci.draw_rect(Rect2(o + Vector2(0 + a, -2), Vector2(1, 2)), c.darkened(0.3))
		ci.draw_rect(Rect2(o + Vector2(5 - a, -2), Vector2(1, 2)), c.darkened(0.3))
		ci.draw_rect(Rect2(o + Vector2(0, -6), Vector2(7, 4)), c)
		ci.draw_rect(Rect2(o + Vector2(7, -6), Vector2(2, 3)), c.darkened(0.1)) # Tête
		ci.draw_rect(Rect2(o + Vector2(7, -7), Vector2(1, 1)), Color(0.95, 0.92, 0.82)) # Corne
		ci.draw_rect(Rect2(o + Vector2(9, -7), Vector2(1, 1)), Color(0.95, 0.92, 0.82))
	ci.draw_line(Vector2(3, -5), Vector2(6, -6), WOOD.darkened(0.2), 1.0) # Timon
	# Charrette
	ci.draw_rect(Rect2(-12, -7, 15, 5), WOOD)
	ci.draw_rect(Rect2(-12, -7, 15, 1), WOOD.lightened(0.2))
	var cover := Color(0.92, 0.88, 0.76)
	ci.draw_rect(Rect2(-12, -11, 15, 4), cover)
	ci.draw_rect(Rect2(-11, -12, 13, 1), cover)
	for k in 3:
		ci.draw_rect(Rect2(-10 + k * 5, -11, 1, 4), cover.darkened(0.15))
	if n > 1: # Ballots
		ci.draw_rect(Rect2(-15, -5, 3, 3), Color(0.7, 0.55, 0.32))
	for wx in [-9.0, 0.0]:
		ci.draw_circle(Vector2(wx, -1.5), 2.5, DARK)
		ci.draw_circle(Vector2(wx, -1.5), 1.0, WOOD.lightened(0.2))
	walker(ci, 13, Color(0.35, 0.45, 0.55), "hat", step) # Bouvier


## Villageois : paysans en tuniques de laine, chapeaux de paille, fourche et baluchon.
static func villagers(ci: CanvasItem, n: int, step: int) -> void:
	shadow(ci, 4.0 + n * 3.0)
	var tunics := [Color(0.55, 0.42, 0.25), Color(0.42, 0.5, 0.3), Color(0.62, 0.55, 0.42), Color(0.5, 0.35, 0.3)]
	for k in n:
		var x := -2.0 * n + k * 4.5
		walker(ci, x, tunics[k % tunics.size()], "hat" if k % 2 == 0 else "", (step + k) % 2)
		if k == 0: # Fourche sur l'épaule
			ci.draw_line(Vector2(x + 3, -6), Vector2(x + 7, -14), WOOD, 1.0)
			ci.draw_line(Vector2(x + 6, -15), Vector2(x + 8, -14), STEEL, 1.0)
			ci.draw_line(Vector2(x + 6, -15), Vector2(x + 6, -17), STEEL, 1.0)
			ci.draw_line(Vector2(x + 8, -14), Vector2(x + 9, -16), STEEL, 1.0)
		elif k == 1: # Baluchon
			ci.draw_circle(Vector2(x - 1, -7), 2.0, Color(0.8, 0.72, 0.55))


## Patrouille : cavaliers aux couleurs de la faction et sa bannière.
static func patrol(ci: CanvasItem, n: int, col: Color, step: int) -> void:
	shadow(ci, 6.0 + n * 4.0)
	var coats := [Color(0.42, 0.28, 0.18), Color(0.3, 0.22, 0.17), Color(0.6, 0.5, 0.4)]
	for k in n:
		rider(ci, -6.0 * (n - 1) + k * 9.0 + 2.0, coats[k % coats.size()], col, (step + k) % 2, k != 0)
	banner(ci, Vector2(-6.0 * (n - 1) - 1.0, -2), col, 22.0, 9.0)


## Armée : cavaliers et piquiers, grande bannière fourchée de la faction.
static func army(ci: CanvasItem, horse: int, foot: int, col: Color, step: int) -> void:
	shadow(ci, 10.0 + (horse + foot) * 2.5)
	var tab := col.darkened(0.15)
	for k in foot: # Piquiers derrière, au second rang
		var x := -4.0 * foot + k * 4.0 + 4.0
		walker(ci, x, tab, "helm", (step + k) % 2)
		ci.draw_line(Vector2(x + 3, -2), Vector2(x + 3, -16), WOOD.lightened(0.1), 1.0)
		ci.draw_rect(Rect2(Vector2(x + 2.5, -18), Vector2(1, 2)), STEEL)
	for k in horse:
		rider(ci, -5.0 * (horse - 1) + k * 10.0 + 3.0, [Color(0.35, 0.24, 0.16), Color(0.86, 0.84, 0.8), Color(0.2, 0.16, 0.14)][k % 3], tab, (step + k + 1) % 2)
	banner(ci, Vector2(-5.0 * (horse - 1) - 4.0, -1), col, 28.0, 13.0, true)


## Bandits : silhouettes encapuchonnées, lames, chiffon noir.
static func bandits(ci: CanvasItem, n: int, step: int) -> void:
	shadow(ci, 4.0 + n * 3.0)
	var cloaks := [Color(0.22, 0.18, 0.15), Color(0.3, 0.2, 0.16), Color(0.18, 0.2, 0.16)]
	for k in n:
		var x := -2.0 * n + k * 4.5 + 2.0
		walker(ci, x, cloaks[k % cloaks.size()], "hood", (step + k) % 2)
		if k % 2 == 0: # Lame levée
			ci.draw_line(Vector2(x + 3, -6), Vector2(x + 6, -12), STEEL, 1.0)
		else: # Hache
			ci.draw_line(Vector2(x + 3, -5), Vector2(x + 4, -12), WOOD, 1.0)
			ci.draw_rect(Rect2(Vector2(x + 4, -13), Vector2(2, 3)), STEEL.darkened(0.2))
	banner(ci, Vector2(-2.0 * n - 4.0, -1), Color(0.12, 0.1, 0.09), 15.0, 7.0, false, true)


## Déserteurs : soldats débraillés, piques basses, bannière déchirée et délavée.
static func deserters(ci: CanvasItem, n: int, faded: Color, step: int) -> void:
	shadow(ci, 4.0 + n * 3.0)
	for k in n:
		var x := -2.0 * n + k * 4.5 + 2.0
		walker(ci, x, Color(0.45, 0.44, 0.42).lerp(faded, 0.25), "helm" if k % 2 == 0 else "", (step + k) % 2)
		ci.draw_line(Vector2(x + 2, -6), Vector2(x + 11, -2), WOOD.darkened(0.1), 1.0) # Pique basse
	banner(ci, Vector2(-2.0 * n - 4.0, -1), faded.lerp(Color(0.55, 0.52, 0.48), 0.55), 14.0, 8.0, false, true)


## Compagnie du joueur : quelques soldats bleus et la bannière à ses armoiries.
static func company(ci: CanvasItem, n: int, arms: Dictionary, step: int) -> void:
	shadow(ci, 7.0 + n * 3.0)
	for k in n:
		var x := -1.0 + k * 4.5
		walker(ci, x, Color(0.22, 0.32, 0.62), "helm", (step + k) % 2)
		ci.draw_line(Vector2(x + 3, -3), Vector2(x + 3, -15), WOOD.lightened(0.1), 1.0)
		ci.draw_rect(Rect2(Vector2(x + 2.5, -17), Vector2(1, 2)), STEEL)
	# Bannière carrée aux armoiries, à franges d'or
	var at := Vector2(-5, 0)
	ci.draw_line(at, at + Vector2(0, -32), WOOD.darkened(0.1), 2.0)
	ci.draw_line(at + Vector2(-2, -31), at + Vector2(16, -31), WOOD.darkened(0.1), 1.5) # Traverse
	var r := Rect2(at + Vector2(1, -30), Vector2(14, 15))
	ci.draw_rect(r.grow(1), Color(0.1, 0.07, 0.05))
	Heraldry.draw(ci, r, arms)
	for k in 5:
		ci.draw_rect(Rect2(r.position + Vector2(1 + k * 3, r.size.y), Vector2(1, 2)), Color(0.95, 0.8, 0.35))
	ci.draw_circle(at + Vector2(0, -33), 1.5, Color(0.95, 0.85, 0.5))
