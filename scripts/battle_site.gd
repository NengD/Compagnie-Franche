class_name BattleSite
extends RefCounted
## Champ de bataille tiré de l'endroit exact de la carte du monde (MapData) : une fenêtre de la
## carte autour du point de contact, tournée et agrandie (SCALE pixels de bataille par pixel de
## carte), devient le champ de bataille (BattleSim.WORLD_SIZE).
##
## describe(pos, toward, place) renvoie un descripteur (dictionnaire sauvegardable en JSON) porté
## par le contrat (contract["site"]) ; Terrain.setup s'en sert (voir Terrain.apply_site). Sans
## descripteur, le terrain garde l'ancien tirage au sort.
##
## Orientation : s'il y a une rivière, elle traverse le champ d'ouest en est, la compagnie sur sa
## rive (en bas) ; sinon une route proche le traverse de même ; sinon l'ennemi vient du haut
## (direction du groupe rencontré). La fenêtre est un peu décalée pour que la rivière ou la route
## passe entre les deux armées.
##
## Clés du descripteur (coordonnées du champ de bataille) :
##   kind      terrain principal (Terrain.KINDS hors siège) : village, river, forest, hills, plain ;
##   label     où l'on se bat (« au pont de Pont-de-Vionne, sur la Vionne ») ;
##   pos, angle, origin   point de contact, angle de l'axe x du champ sur la carte, centre de la fenêtre ;
##   river     vrai si une rivière traverse le champ (sa ligne est « line ») ;
##   road      vrai si une route le traverse d'ouest en est (sa ligne est « line ») ;
##   line      hauteurs de la rivière ou de la route, un point tous les LINE_STEP px depuis LINE_X0 ;
##   roads     autres routes : listes plates [x0, y0, x1, y1...] (celles qui franchissent la rivière) ;
##   crossings passages de la rivière : [x, « bridge » | « ford » | « shallows »] ;
##   forests   bois de la carte : [x, y, rayon] ;
##   hills     collines là où le relief monte : [x, y, rayon, hauteur] ;
##   ponds     eau d'un lac : [x, y, rayon] ;
##   village   [x, y] du village (la compagnie y était), vide sinon ; place : son indice de lieu.

const SCALE := 6.0 ## Pixels du champ de bataille par pixel de la carte
const WORLD := Vector2(3200, 2000) ## = BattleSim.WORLD_SIZE (pas de dépendance au simulateur ici)
const CENTER := Vector2(1600, 1000)
const LINE_X0 := -200.0
const LINE_STEP := 100.0
const LINE_N := 37 ## De -200 à 3400
const RIVER_REACH := 90.0 ## Rivière à moins de tant (carte) : elle passe sur le champ
const ROAD_REACH := 45.0 ## Route à moins de tant (carte) : elle traverse le champ
const RIVER_BAND := Vector2(700, 1240) ## La rivière passe entre ces hauteurs (au centre)
const ROAD_BAND := Vector2(850, 1150) ## La route aussi
const LINE_CLAMP := Vector2(620, 1360) ## Jamais plus près des zones de déploiement
const FOREST_STEP := 160.0
const FOREST_R := 150.0
const MAX_FORESTS := 18
const HILL_STEP := 200.0
const MAX_HILLS := 4
const POND_STEP := 110.0
const POND_R := 80.0
const SETTLED := ["town", "village", "castle", "abbey", "mill"]


## Descripteur du champ de bataille au point pos de la carte. toward : position de l'ennemi (sa
## direction donne le haut du champ quand rien d'autre ne l'oriente). place : lieu où se trouvait
## la compagnie (-1 : en campagne) ; s'il est habité, on s'y bat.
static func describe(pos: Vector2, toward: Vector2, place := -1) -> Dictionary:
	MapData.fields() # Construit la grille de la carte si besoin
	pos = pos.clamp(Vector2.ZERO, MapData.SIZE)
	var riv := nearest_river(pos)
	var has_river := float(riv["dist"]) < RIVER_REACH
	var road := nearest_road(pos)
	var main_road := -1
	var x_axis := Vector2.RIGHT
	var side := pos - toward # Vers la compagnie (le bas du champ)
	if has_river:
		x_axis = riv["tangent"]
		var bank: Vector2 = pos - riv["point"]
		if bank.length() > MapData.RIVER_HALF + 4.0:
			side = bank
	elif float(road["dist"]) < ROAD_REACH:
		x_axis = road["tangent"]
		main_road = int(road["index"])
	elif side.length() > 1.0:
		x_axis = (-side).normalized().rotated(PI / 2.0) # Le haut du champ regarde l'ennemi
	if side.length() < 1.0:
		side = x_axis.rotated(PI / 2.0)
	var y_axis := x_axis.rotated(PI / 2.0)
	if y_axis.dot(side) < 0.0:
		x_axis = -x_axis
		y_axis = -y_axis
	var origin := pos
	# Décalage : la rivière (ou la route) passe entre les deux armées
	if has_river or main_road >= 0:
		var anchor: Vector2 = riv["point"] if has_river else road["point"]
		var band := RIVER_BAND if has_river else ROAD_BAND
		var ly := CENTER.y + (anchor - pos).dot(y_axis) * SCALE
		var want := clampf(ly, band.x, band.y)
		origin += y_axis * (ly - want) / SCALE
	var f := Frame.new(origin, x_axis, y_axis)
	var site := {
		"pos": [pos.x, pos.y], "angle": x_axis.angle(), "origin": [origin.x, origin.y],
		"river": has_river, "road": false, "line": [], "roads": [], "crossings": [],
		"forests": [], "hills": [], "ponds": [], "village": [], "place": -1,
	}
	if has_river:
		site["line"] = river_line(f)
	elif main_road >= 0:
		var ys := road_line(f, MapData.road_points(main_road))
		if not ys.is_empty():
			site["line"] = ys
			site["road"] = true
	site["roads"] = other_roads(f, main_road)
	if has_river:
		site["crossings"] = crossings(f, site["line"], site["roads"], pos)
	site["forests"] = forests(f)
	site["hills"] = hills(f, MapData.ground_at(pos))
	site["ponds"] = ponds(f)
	var vil := village_place(pos, place)
	if vil >= 0:
		var vp := f.to_battle(MapData.place_pos(vil))
		vp.x = clampf(vp.x, 900.0, 2300.0)
		vp.y = clampf(vp.y, 850.0, 1150.0)
		site["village"] = [vp.x, vp.y]
		site["place"] = vil
	site["kind"] = kind_of(site, pos)
	site["label"] = label_of(site, pos, riv, road)
	return site


## Repère de la fenêtre : centre (origin, sur la carte) et axes du champ sur la carte.
class Frame:
	var origin: Vector2
	var ax: Vector2
	var ay: Vector2

	func _init(o: Vector2, x: Vector2, y: Vector2) -> void:
		origin = o
		ax = x
		ay = y

	func to_map(b: Vector2) -> Vector2:
		var d := (b - BattleSite.CENTER) / BattleSite.SCALE
		return origin + ax * d.x + ay * d.y

	func to_battle(m: Vector2) -> Vector2:
		var d := m - origin
		return BattleSite.CENTER + Vector2(d.dot(ax), d.dot(ay)) * BattleSite.SCALE


static func in_map(m: Vector2) -> bool:
	return m.x >= 0.0 and m.y >= 0.0 and m.x < MapData.SIZE.x and m.y < MapData.SIZE.y


# ---------------------------------------------------------------- Lignes : rivière et route

## Rivière la plus proche de pos : {dist (au milieu du lit), point, tangent, name}.
static func nearest_river(pos: Vector2) -> Dictionary:
	# La Vionne : une courbe x(y)
	var y0 := pos.y
	var best := {"dist": INF, "point": pos, "tangent": Vector2.RIGHT, "name": MapData.RIVER_NAME}
	for k in range(-60, 61, 2):
		var y := y0 + k
		var p := Vector2(MapData.river_x(y), y)
		var d := p.distance_to(pos)
		if d < float(best["dist"]):
			var t := Vector2(MapData.river_x(y + 1.0) - MapData.river_x(y - 1.0), 2.0).normalized()
			best = {"dist": d, "point": p, "tangent": t, "name": MapData.RIVER_NAME}
	for i in MapData.RIVERS.size():
		var pts := MapData.river_points(i)
		for j in pts.size() - 1:
			var q := Geometry2D.get_closest_point_to_segment(pos, pts[j], pts[j + 1])
			var d := q.distance_to(pos)
			if d < float(best["dist"]):
				best = {"dist": d, "point": q, "tangent": (pts[j + 1] - pts[j]).normalized(), "name": str(MapData.RIVERS[i]["name"])}
	return best


## Route la plus proche de pos : {dist, point, tangent, index}.
static func nearest_road(pos: Vector2) -> Dictionary:
	var best := {"dist": INF, "point": pos, "tangent": Vector2.RIGHT, "index": -1}
	for k in MapData.roads().size():
		var pts := MapData.road_points(k)
		for j in pts.size() - 1:
			var q := Geometry2D.get_closest_point_to_segment(pos, pts[j], pts[j + 1])
			var d := q.distance_to(pos)
			if d < float(best["dist"]):
				best = {"dist": d, "point": q, "tangent": (pts[j + 1] - pts[j]).normalized(), "index": k}
	return best


## Ligne de la rivière : dans chaque colonne du champ, la hauteur où l'on est le plus près du lit.
static func river_line(f: Frame) -> Array:
	var ys: Array = []
	for i in LINE_N:
		var x := LINE_X0 + i * LINE_STEP
		var best := INF
		var by := NAN
		for k in range(0, 71):
			var y := 300.0 + k * 20.0
			var m := f.to_map(Vector2(x, y))
			if not in_map(m):
				continue
			var d := MapData.river_distance(m)
			if d < best:
				best = d
				by = y
		ys.append(by if best < MapData.RIVER_HALF * 2.0 + 25.0 else NAN)
	return finish_line(ys)


## Ligne d'une route (tracé de la carte) : sa hauteur dans chaque colonne du champ.
static func road_line(f: Frame, pts: PackedVector2Array) -> Array:
	var bp: Array[Vector2] = []
	for p in pts:
		bp.append(f.to_battle(p))
	var ys: Array = []
	var found := 0
	for i in LINE_N:
		var x := LINE_X0 + i * LINE_STEP
		var by := NAN
		var bd := INF
		for j in bp.size() - 1:
			var a := bp[j]
			var b := bp[j + 1]
			if x < minf(a.x, b.x) or x > maxf(a.x, b.x) or absf(b.x - a.x) < 0.001:
				continue
			var y := lerpf(a.y, b.y, (x - a.x) / (b.x - a.x))
			if absf(y - CENTER.y) < bd:
				bd = absf(y - CENTER.y)
				by = y
		if not is_nan(by):
			found += 1
		ys.append(by)
	if found < 4:
		return []
	return finish_line(ys)


## Complète une ligne (colonnes sans valeur : la voisine la plus proche), la lisse et la garde
## loin des zones de déploiement.
static func finish_line(ys: Array) -> Array:
	var n := ys.size()
	var any := false
	for y in ys:
		if not is_nan(float(y)):
			any = true
	if not any:
		ys.fill(CENTER.y)
		return ys
	var out: Array = ys.duplicate()
	for i in n:
		if is_nan(float(out[i])):
			for d in range(1, n):
				if i - d >= 0 and not is_nan(float(ys[i - d])):
					out[i] = ys[i - d]
					break
				if i + d < n and not is_nan(float(ys[i + d])):
					out[i] = ys[i + d]
					break
	var smooth: Array = []
	for i in n:
		var s := 0.0
		var w := 0.0
		for d in range(-2, 3):
			var j := clampi(i + d, 0, n - 1)
			var k := 3.0 - absf(d)
			s += float(out[j]) * k
			w += k
		smooth.append(snappedf(clampf(s / w, LINE_CLAMP.x, LINE_CLAMP.y), 0.1))
	return smooth


## Hauteur d'une ligne échantillonnée en x.
static func line_y(line: Array, x: float) -> float:
	if line.is_empty():
		return CENTER.y
	var t := clampf((x - LINE_X0) / LINE_STEP, 0.0, line.size() - 1.001)
	var i := int(t)
	return lerpf(float(line[i]), float(line[mini(i + 1, line.size() - 1)]), t - i)


## Routes de la carte qui passent sur le champ (hors celle qui sert de ligne) : listes plates de
## points du champ, coupées aux abords.
static func other_roads(f: Frame, skip: int) -> Array:
	var box := Rect2(Vector2(-300, -300), WORLD + Vector2(600, 600))
	var reach := (WORLD.length() * 0.5 + 300.0) / SCALE
	var out: Array = []
	for k in MapData.roads().size():
		if k == skip:
			continue
		var pts := MapData.road_points(k)
		var cur: Array = []
		for j in pts.size():
			var m := pts[j]
			if m.distance_to(f.origin) > reach + 40.0:
				if cur.size() >= 4:
					out.append(cur)
				cur = []
				continue
			var b := f.to_battle(m)
			if box.has_point(b):
				cur.append_array([snappedf(b.x, 0.1), snappedf(b.y, 0.1)])
			elif cur.size() >= 2:
				cur.append_array([snappedf(b.x, 0.1), snappedf(b.y, 0.1)]) # Sortie du champ
				out.append(cur)
				cur = []
		if cur.size() >= 4:
			out.append(cur)
	return out


## Passages de la rivière : ponts et gués des routes qui la franchissent, gués de la carte ; sans
## aucun, deux hauts-fonds (sinon personne ne passerait).
static func crossings(f: Frame, line: Array, roads: Array, pos: Vector2) -> Array:
	var out: Array = []
	var fords: Array[Vector2] = []
	for p in MapData.places():
		if str(p["kind"]) == "ford":
			fords.append(p["pos"])
	var add := func(x: float, kind: String) -> void:
		if x < 120.0 or x > WORLD.x - 120.0:
			return
		for c in out:
			if absf(float(c[0]) - x) < 160.0:
				return
		out.append([snappedf(x, 0.1), kind])
	for r in roads:
		for j in range(0, r.size() - 2, 2):
			var a := Vector2(r[j], r[j + 1])
			var b := Vector2(r[j + 2], r[j + 3])
			var da := a.y - line_y(line, a.x)
			var db := b.y - line_y(line, b.x)
			if da * db > 0.0 or da == db:
				continue
			var x := lerpf(a.x, b.x, da / (da - db))
			var m := f.to_map(Vector2(x, line_y(line, x)))
			var kind := "bridge"
			for q in fords:
				if q.distance_to(m) < 60.0:
					kind = "ford"
			add.call(x, kind)
	for q in fords:
		var b := f.to_battle(q)
		if absf(b.y - line_y(line, b.x)) < 260.0:
			add.call(b.x, "ford")
	if out.is_empty():
		var h := absi(hash([int(pos.x), int(pos.y)]))
		add.call(WORLD.x * (0.22 + float(h % 9) * 0.01), "shallows")
		add.call(WORLD.x * (0.7 + float(int(h / 9.0) % 9) * 0.01), "shallows")
	out.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	return out


# ---------------------------------------------------------------- Bois, relief, lacs, village

## Bois : la forêt de la carte, en cercles qui se chevauchent (lisière du bon côté).
static func forests(f: Frame) -> Array:
	var out: Array = []
	var y := 520.0
	while y <= 1480.0:
		var x := 100.0
		while x <= WORLD.x - 100.0:
			var m := f.to_map(Vector2(x, y))
			if in_map(m) and MapData.ground_at(m) == MapData.Ground.FOREST:
				var h := absi(hash([int(m.x), int(m.y)]))
				var c := Vector2(x + float(h % 41) - 20.0, y + float(int(h / 41.0) % 41) - 20.0)
				var ok := true
				for o in out:
					if c.distance_to(Vector2(o[0], o[1])) < FOREST_R * 1.1:
						ok = false
						break
				if ok and out.size() < MAX_FORESTS:
					out.append([snappedf(c.x, 0.1), snappedf(c.y, 0.1), FOREST_R + float(h % 30)])
			x += FOREST_STEP
		y += FOREST_STEP
	return out


## Collines : sommets du relief de la carte (cases de collines ou de montagne) sur le champ.
static func hills(f: Frame, ground_here: int) -> Array:
	var cols := int(WORLD.x / HILL_STEP)
	var rows := 8
	var hs: Array[float] = []
	var hilly: Array[bool] = []
	var hmin := INF
	for j in rows:
		for i in cols:
			var b := Vector2(100.0 + i * HILL_STEP, 300.0 + j * HILL_STEP)
			var m := f.to_map(b)
			var h := 0.0
			var g := MapData.Ground.PLAIN
			if in_map(m):
				var c := MapData.cell_of(m)
				h = MapData.height_cell(c)
				g = MapData.ground_cell(c)
			hs.append(h)
			hilly.append(g == MapData.Ground.HILLS or g == MapData.Ground.MOUNTAIN)
			hmin = minf(hmin, h)
	var peaks: Array = []
	for j in rows:
		for i in cols:
			var k := j * cols + i
			if not hilly[k]:
				continue
			var top := true
			for dj in range(-1, 2):
				for di in range(-1, 2):
					var jj := j + dj
					var ii := i + di
					if (di == 0 and dj == 0) or jj < 0 or ii < 0 or jj >= rows or ii >= cols:
						continue
					if hs[jj * cols + ii] > hs[k]:
						top = false
			if top:
				peaks.append([hs[k], Vector2(100.0 + i * HILL_STEP, 300.0 + j * HILL_STEP)])
	if peaks.is_empty() and (ground_here == MapData.Ground.HILLS or ground_here == MapData.Ground.MOUNTAIN):
		var best := 0
		for k in hs.size():
			if hs[k] > hs[best]:
				best = k
		peaks.append([hs[best], Vector2(100.0 + (best % cols) * HILL_STEP, 300.0 + floorf(best / float(cols)) * HILL_STEP)])
	peaks.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	var out: Array = []
	for p in peaks:
		var c: Vector2 = p[1]
		var ok := true
		for o in out:
			if c.distance_to(Vector2(o[0], o[1])) < 450.0:
				ok = false
		if ok and out.size() < MAX_HILLS:
			var amp := clampf(0.6 + (float(p[0]) - hmin) * 2.0, 0.6, 1.0)
			out.append([c.x, c.y, 170.0 + (int(c.x + c.y) % 50), snappedf(amp, 0.01)])
	return out


## Eau d'un lac sur le champ (hors de la rivière, qui a sa ligne), loin des zones de déploiement.
static func ponds(f: Frame) -> Array:
	var out: Array = []
	var y := POND_STEP * 0.5
	while y < WORLD.y:
		var x := POND_STEP * 0.5
		while x < WORLD.x:
			var deploy := (y < 560.0 or y > 1440.0) and absf(x - CENTER.x) < 1300.0
			var m := f.to_map(Vector2(x, y))
			if not deploy and in_map(m) and MapData.lake_factor(m) < 1.0:
				out.append([x, y, POND_R])
			x += POND_STEP
		y += POND_STEP
	return out


## Village où l'on se bat : le lieu où était la compagnie, ou un lieu habité tout proche.
static func village_place(pos: Vector2, place: int) -> int:
	if place >= 0 and place < MapData.place_count() and str(MapData.place(place)["kind"]) in SETTLED:
		return place
	var near := MapData.place_at(pos, 2.2)
	if near >= 0 and str(MapData.place(near)["kind"]) in SETTLED:
		return near
	return -1


static func kind_of(site: Dictionary, pos: Vector2) -> String:
	if not (site["village"] as Array).is_empty():
		return "village"
	if bool(site["river"]):
		return "river"
	match MapData.ground_at(pos):
		MapData.Ground.FOREST:
			return "forest"
		MapData.Ground.HILLS, MapData.Ground.MOUNTAIN:
			return "hills" if not (site["hills"] as Array).is_empty() else "plain"
	if (site["forests"] as Array).size() >= 6:
		return "forest"
	return "plain"


## Où l'on se bat, en toutes lettres.
static func label_of(site: Dictionary, pos: Vector2, riv: Dictionary, road: Dictionary) -> String:
	if int(site["place"]) >= 0:
		return "à %s" % str(MapData.place(int(site["place"]))["name"])
	var near := MapData.nearest_place(pos)
	var where := str(MapData.place(near)["name"]) if near >= 0 else ""
	if bool(site["river"]):
		var river := str(riv["name"])
		for c in site["crossings"]:
			if absf(float(c[0]) - CENTER.x) < 900.0:
				match str(c[1]):
					"bridge":
						return "au pont sur %s, près de %s" % [river, where]
					"ford":
						return "au gué sur %s, près de %s" % [river, where]
		return "au bord de %s, près de %s" % [river, where]
	if bool(site["road"]):
		var r: Array = MapData.roads()[int(road["index"])]
		return "sur la route de %s à %s" % [MapData.place(r[0])["name"], MapData.place(r[1])["name"]]
	for fo in MapData.FORESTS:
		var e := ((pos - (fo["center"] as Vector2)) / (fo["radius"] as Vector2)).length()
		if e < 1.5:
			var n := str(fo["name"])
			return "à la lisière de la %s" % n if n.begins_with("Forêt") else "à la lisière du %s" % n
	match str(site["kind"]):
		"forest":
			return "dans les bois, près de %s" % where
		"hills":
			return "dans les collines, près de %s" % where
	if not (site["ponds"] as Array).is_empty():
		return "au bord d'un lac, près de %s" % where
	return "en rase campagne, près de %s" % where


## Relit un descripteur sauvegardé (JSON) : {} s'il est invalide.
static func sanitize(v: Variant) -> Dictionary:
	if not v is Dictionary:
		return {}
	var d: Dictionary = v
	var kind := str(d.get("kind", ""))
	if not kind in MapData.BATTLE_TERRAINS:
		return {}
	var out := d.duplicate(true)
	for key in ["line", "roads", "crossings", "forests", "hills", "ponds", "village"]:
		if not out.get(key, []) is Array:
			out[key] = []
	out["river"] = bool(out.get("river", false)) and (out["line"] as Array).size() >= 2
	out["road"] = bool(out.get("road", false)) and (out["line"] as Array).size() >= 2
	if kind == "river" and not out["river"]:
		out["kind"] = "plain"
	if kind == "village" and (out["village"] as Array).size() < 2:
		out["village"] = []
	out["label"] = str(out.get("label", ""))
	out["place"] = int(out.get("place", -1))
	return out
