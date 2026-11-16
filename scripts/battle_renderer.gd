class_name BattleRenderer
extends Node2D
## Rendu pixel art de la bataille, dessiné en un seul _draw() : sol, relief et eau, zone de
## déploiement, corps, poussière, ordres des régiments sélectionnés, soldats, arbres, maisons et
## palissades triés par profondeur, flèches, étendards, repères d'ordres et aperçus de la saisie.
## Il ne modifie jamais la simulation : il lit battle.sim et battle.orders.
##
## Points d'extension :
## - nouvelle unité : ses sprites viennent de sprite_bank.gd ; sans sprite, ajouter son dessin de
##   repli dans draw_soldier_code() et son pictogramme dans draw_banner_shape() ;
## - nouvel effet visuel : de préférence dans BattleEffects (battle_effects.gd) ; sinon une liste ici (comme markers), mise à jour dans update_effects(),
##   dessinée dans _draw() ; ou une liste de la simulation (comme dust) si elle suit le temps simulé.

const WORLD_SIZE := BattleSim.WORLD_SIZE
const PLAYER := BattleSim.PLAYER
const ENEMY := BattleSim.ENEMY
const ROAD_HALF := BattleSim.ROAD_HALF
const TEAM_COLORS := [Color(0.22, 0.38, 0.85), Color(0.78, 0.16, 0.14)]
const TEAM_DARK := [Color(0.12, 0.18, 0.42), Color(0.42, 0.08, 0.07)]
const SKIN := Color(0.93, 0.76, 0.6)
const STEEL := Color(0.72, 0.74, 0.78)
const WOOD := Color(0.48, 0.32, 0.17)
const HORSE := Color(0.42, 0.27, 0.15)
const HORSE_DARK := Color(0.28, 0.17, 0.09)
const PX := 2.0 ## Taille d'un « pixel » des dessins en code (repli quand un sprite manque)
const MARKER_LIFE := 0.6 ## Durée d'un repère d'ordre (secondes)

var battle: Battle
var sim: BattleSim
var sprites := SpriteBank.new()
var ground_tex: ImageTexture
var ground_scale := 1.0 ## Taille d'un pixel de ground_tex dans le monde
var terrain_tex: ImageTexture = null ## Couche du relief et de l'eau posée sur le sol
var markers: Array = [] ## Repères d'ordres : [position, couleur, vie restante]
var effects: BattleEffects ## Sang, fumée, éclaboussures, pluie au sol… (battle_effects.gd)


func _init(b: Battle) -> void:
	battle = b
	sim = b.sim
	name = "Renderer"
	effects = BattleEffects.new(sim)


## Repère d'ordre (cercle qui s'élargit et s'efface) en p.
func add_marker(p: Vector2, col: Color) -> void:
	markers.append([p, col, MARKER_LIFE])


## Effets en temps réel (indépendants de la vitesse du jeu).
func update_effects(delta: float) -> void:
	for m in markers:
		m[2] -= delta
	markers = markers.filter(func(m): return m[2] > 0.0)
	effects.update(delta, self)


# ---------------------------------------------------------------- Sol

## Sol en tuiles MiniWorld (16 px). Renvoie false si les tuiles ne sont pas disponibles.
## rng : celui de la simulation (l'ordre des tirages compte pour les graines fixes).
func build_tiled_ground(rng: RandomNumberGenerator) -> bool:
	var grass := tile_images("res://assets/sprites/ground/TexturedGrass.png", [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)])
	var plain := tile_images("res://assets/sprites/ground/Grass.png", [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)])
	if grass.size() < 6 or plain.size() < 3:
		return false
	var sand: Image = plain[2]
	var dark: Array[Image] = []
	for t in grass:
		var d: Image = t.duplicate()
		d.adjust_bcs(0.72, 1.0, 0.95)
		dark.append(d)
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.004
	var tw := int(WORLD_SIZE.x) / 16
	var th := int(WORLD_SIZE.y) / 16
	var img := Image.create_empty(tw * 16, th * 16, false, Image.FORMAT_RGBA8)
	var r16 := Rect2i(0, 0, 16, 16)
	for ty in th:
		for tx in tw:
			var c := Vector2(tx * 16 + 8, ty * 16 + 8)
			var t: Image
			if sim.on_road(c, ROAD_HALF):
				t = sand
			elif sim.is_in_forest(c):
				t = dark[rng.randi() % dark.size()]
			else:
				# Surtout de l'herbe rase, des touffes plus nombreuses par endroits
				var tufts := 0.25 + noise.get_noise_2d(c.x, c.y) * 0.35
				t = grass[rng.randi() % 6] if rng.randf() < tufts else grass[0]
			img.blit_rect(t, r16, Vector2i(tx * 16, ty * 16))
	ground_tex = ImageTexture.create_from_image(img)
	ground_scale = 1.0
	return true


## Découpe des tuiles 16x16 d'une planche (vide si l'image n'est pas lisible).
func tile_images(path: String, cells: Array[Vector2i]) -> Array[Image]:
	var out: Array[Image] = []
	if not ResourceLoader.exists(path):
		return out
	var tex := load(path) as Texture2D
	if tex == null:
		return out
	var full := tex.get_image()
	if full == null or full.is_empty():
		return out # Pas d'accès aux pixels (ex. mode sans affichage) : repli
	if full.is_compressed():
		full.decompress()
	full.convert(Image.FORMAT_RGBA8)
	for c in cells:
		if (c.x + 1) * 16 <= full.get_width() and (c.y + 1) * 16 <= full.get_height():
			out.append(full.get_region(Rect2i(c.x * 16, c.y * 16, 16, 16)))
	return out


## Sol de repli dessiné en code : une petite image agrandie 8x pour l'effet pixel.
func build_procedural_ground(rng: RandomNumberGenerator) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.03
	ground_scale = 8.0
	var w := int(WORLD_SIZE.x / ground_scale)
	var h := int(WORLD_SIZE.y / ground_scale)
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGB8)
	var grass_a := Color(0.38, 0.56, 0.25)
	var grass_b := Color(0.27, 0.44, 0.19)
	for y in h:
		for x in w:
			var n := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var c := grass_a.lerp(grass_b, n)
			if rng.randf() < 0.07:
				c = c.lightened(0.08)
			var wp := Vector2(x + 0.5, y + 0.5) * ground_scale
			if sim.is_in_forest(wp):
				c = c.darkened(0.3)
			if sim.on_road(wp, ROAD_HALF):
				c = Color(0.58, 0.47, 0.31).darkened(rng.randf() * 0.08)
			elif sim.on_road(wp, ROAD_HALF + ground_scale):
				c = Color(0.46, 0.42, 0.27)
			img.set_pixel(x, y, c)
	ground_tex = ImageTexture.create_from_image(img)


# ---------------------------------------------------------------- Dessin

func _draw() -> void:
	draw_texture_rect(ground_tex, Rect2(Vector2.ZERO, WORLD_SIZE), false)
	if terrain_tex != null:
		draw_texture_rect(terrain_tex, Rect2(Vector2.ZERO, WORLD_SIZE), false)
	if sim.terrain.has_river():
		draw_river_glints()

	if sim.state == BattleSim.State.DEPLOY:
		var top := sim.deploy_top()
		draw_rect(Rect2(0, top, WORLD_SIZE.x, WORLD_SIZE.y - top), Color(0.3, 0.5, 1.0, 0.08))
		draw_line(Vector2(0, top), Vector2(WORLD_SIZE.x, top), Color(0.6, 0.75, 1.0, 0.4), 2.0)

	for c in sim.corpses:
		draw_corpse(c)

	draw_dust()
	effects.draw_ground(self)

	# Ordres des régiments sélectionnés
	for r in sim.regiments:
		if not r.selected or r.is_dead():
			continue
		for s in r.soldiers:
			if s.alive:
				draw_rect(Rect2(s.pos.x - 6, s.pos.y - 1, 12, 3), Color(1, 0.95, 0.4, 0.55))
		if r.target != null:
			draw_dashed_line(r.center, r.target.center, Color(1, 0.35, 0.25, 0.6), 2.0, 8.0)
		elif r.center.distance_to(r.dest) > 24.0:
			draw_dashed_line(r.center, r.dest, Color(1, 0.6, 0.15, 0.75) if r.running else Color(1, 1, 1, 0.4), 2.0, 8.0)
			draw_rect(Rect2(r.dest - Vector2(2, 2), Vector2(6, 6)), Color(1, 1, 1, 0.7))

	# Flèche d'orientation de chaque régiment du joueur (plus visible s'il est sélectionné)
	for r in sim.regiments:
		if r.team != PLAYER or r.is_dead() or r.routing:
			continue
		var acol := Color(1, 0.95, 0.4, 0.9) if r.selected else Color(1, 1, 1, 0.45)
		# Vers sa destination s'il marche, sinon sur place
		var at := r.dest if r.center.distance_to(r.dest) > 24.0 and r.target == null else r.center
		draw_facing_arrow(r, at, r.facing, 0, acol, 14.0)

	# Soldats et arbres triés par hauteur pour la profondeur
	var items := []
	for s in sim.soldiers:
		if not s.alive:
			continue
		if s.regiment.team == ENEMY and s.regiment.hidden:
			continue
		items.append([s.pos.y, s])
	for t in sim.trees:
		items.append([t.y, t])
	for h in sim.terrain.houses:
		items.append([h.end.y, h])
	for w in sim.terrain.walls:
		items.append([w.end.y, w])
	items.sort_custom(func(a, b): return a[0] < b[0])
	for it in items:
		if it[1] is Vector2:
			draw_tree(it[1])
		elif it[1] is Rect2:
			if (it[1] as Rect2).size.y <= Terrain.WALL_HALF * 2.0:
				draw_palisade(it[1])
			else:
				draw_house(it[1])
		else:
			draw_soldier(it[1])

	effects.draw_air(self)
	draw_arrows()

	if GameOptions.team_shapes:
		draw_team_marks()

	for r in sim.regiments:
		if r.is_dead() or (r.team == ENEMY and r.hidden):
			continue
		draw_banner(r)

	for m in markers:
		var p: Vector2 = m[0]
		var col: Color = m[1]
		var k: float = m[2] / MARKER_LIFE
		col.a = k
		draw_arc(p, 6.0 + (1.0 - k) * 16.0, 0, TAU, 20, col, 2.0)

	var o := battle.orders
	if o.line_dragging and o.is_line_drag(o.line_start, o.line_now):
		draw_line_preview()

	if o.dragging and o.drag_start.distance_to(o.drag_now) > 2.0:
		var rect := Rect2(o.drag_start, Vector2.ZERO).expand(o.drag_now)
		draw_rect(rect, Color(1, 1, 1, 0.12), true)
		draw_rect(rect, Color(1, 1, 1, 0.7), false, 1.0 / battle.camera.zoom.x)


## Aperçu fantôme pendant le tracé : place de chaque soldat et flèche d'orientation.
func draw_line_preview() -> void:
	var ghost := Color(1, 0.95, 0.4, 0.55)
	var lw := 1.0 / battle.camera.zoom.x
	var o := battle.orders
	draw_line(o.line_start, o.line_now, Color(1, 1, 1, 0.35), lw)
	for e in o.line_layout(sim.selected_regiments(), o.line_start, o.line_now):
		var r: Regiment = e["reg"]
		var face: Vector2 = e["facing"]
		var cols: int = e["cols"]
		var at: Vector2 = o.order_dest(r, e["dest"], face, cols)
		var n := r.alive_n
		for i in n:
			var p := r.formation_slot(i, n, cols, at, face)
			draw_rect(Rect2(p.x - 3, p.y - 3, 6, 6), ghost)
		draw_facing_arrow(r, at, face, cols, Color(1, 1, 1, 0.85), 24.0)


## Petite flèche devant le premier rang, qui montre où le régiment fait face.
## cols <= 0 : utilise la formation actuelle du régiment.
func draw_facing_arrow(r: Regiment, at: Vector2, face: Vector2, cols: int, col: Color, length: float) -> void:
	var n := maxi(r.alive_n, 1)
	var rows := r.depth_rows(n) if cols <= 0 else ceili(float(n) / float(clampi(cols, 1, n)))
	var sp: float = r.stats["spacing"]
	var tail := at + face * (rows * 0.5 * sp + 4.0)
	var tip := tail + face * length
	var head := minf(length * 0.45, 8.0)
	var wing := Vector2(-face.y, face.x) * head * 0.8
	draw_line(tail, tip, col, 2.0)
	draw_line(tip, tip - face * head + wing, col, 2.0)
	draw_line(tip, tip - face * head - wing, col, 2.0)


func px(p: Vector2, fx: int, x: float, y: float, w: float, h: float, c: Color) -> void:
	var xx := x if fx > 0 else -x - w
	draw_rect(Rect2(p.x + xx, p.y + y, w, h), c)


## Direction dans laquelle le soldat regarde : son adversaire, sinon sa marche, sinon le front.
func soldier_look(s: Soldier) -> Vector2:
	if s.foe != null:
		return s.foe.pos - s.pos
	if s.regiment.fire_target != null and s.regiment.stats["ranged"]:
		return s.regiment.fire_target.center - s.pos
	if s.moving:
		return s.move_dir
	if s.regiment.formation == Regiment.Formation.SQUARE:
		var out := s.slot_pos - s.regiment.dest
		if out.length() > 1.0:
			return out # Le carré fait face de tous les côtés
	return s.regiment.facing


func draw_soldier(s: Soldier) -> void:
	var r := s.regiment
	var hidden_alpha := 0.55 if (r.team == PLAYER and r.hidden) else 1.0
	if sprites.has_unit(r.type, r.team):
		var look := soldier_look(s)
		var dir := SpriteBank.dir_of(look)
		var anim := "idle"
		var t := s.anim
		if s.attack_anim > 0.0:
			anim = "attack"
			t = 1.0 - s.attack_anim / s.attack_dur
		elif s.moving:
			anim = "walk"
		var f := sprites.frame(r.type, r.team, dir, anim, t)
		var p := s.pos.round()
		if s.attack_anim > 0.0 and r.type == "spear":
			p += look.normalized().round() * 3.0 # Coup de pique : petite fente vers l'avant
		var src: Rect2 = f["src"]
		var foot: Vector2 = f["foot"]
		draw_rect(Rect2(p.x - 5, p.y - 1, 10, 3), Color(0, 0, 0, 0.22))
		var mod := Color(1, 1, 1, hidden_alpha)
		if s.flash > 0.0:
			mod = Color(2.5, 2.5, 2.5, hidden_alpha) # Éclair blanc quand il est touché
		draw_texture_rect_region(f["tex"], Rect2(p - foot, src.size), src, mod)
		return
	draw_soldier_code(s)


## Corps au sol : le sprite couché et assombri, ou un petit dessin en code.
func draw_corpse(c: Array) -> void:
	var p: Vector2 = c[0]
	var team: int = c[1]
	var type: String = c[2]
	var side: int = c[3]
	if sprites.has_unit(type, team):
		var f := sprites.frame(type, team, SpriteBank.DOWN, "idle", 0.0)
		var src: Rect2 = f["src"]
		var foot: Vector2 = f["foot"]
		draw_set_transform(p, side * PI * 0.5)
		draw_texture_rect_region(f["tex"], Rect2(Vector2(-src.size.x * 0.5, -foot.y * 0.5), src.size), src, Color(0.55, 0.45, 0.42, 0.85))
		draw_set_transform(Vector2.ZERO)
		return
	draw_set_transform(p, 0.0, Vector2(PX, PX))
	if UnitTypes.STATS[type]["mounted"]:
		draw_rect(Rect2(-3, -2, 7, 2), HORSE_DARK)
	draw_rect(Rect2(-2, -1, 4, 1), TEAM_DARK[team])
	draw_rect(Rect2(-1, 0, 2, 1), Color(0.45, 0.07, 0.05, 0.8))
	draw_set_transform(Vector2.ZERO)


## Repli : soldat dessiné en code (si son sprite manque), agrandi PX fois.
func draw_soldier_code(s: Soldier) -> void:
	var r := s.regiment
	draw_set_transform(s.pos.round(), 0.0, Vector2(PX, PX))
	var p := Vector2.ZERO
	var fx := 1 if r.facing.x >= 0.0 else -1
	if s.foe != null:
		fx = 1 if s.foe.pos.x >= s.pos.x else -1
	if s.attack_anim > 0.0:
		p.x += fx
	var col: Color = TEAM_COLORS[r.team]
	var dark: Color = TEAM_DARK[r.team]
	if s.flash > 0.0:
		col = Color.WHITE
	var step := 0.0
	if s.moving and int(s.anim) % 2 == 0:
		step = 1.0
	var alpha := 0.55 if (r.team == PLAYER and r.hidden) else 1.0
	if alpha < 1.0:
		col.a = alpha
		dark.a = alpha

	draw_rect(Rect2(p.x - 2, p.y - 0.5, 5, 1.5), Color(0, 0, 0, 0.28))

	if r.type == "cavalry":
		var horse := HORSE
		horse.a = alpha
		px(p, fx, -3, -5, 7, 3, horse)
		px(p, fx, 3, -7, 2, 3, horse)
		px(p, fx, 4, -6, 1, 1, HORSE_DARK)
		px(p, fx, -4, -5, 1, 3, HORSE_DARK)
		px(p, fx, -3, -2, 1, 2 - step, HORSE_DARK)
		px(p, fx, 2, -2, 1, 1 + step, HORSE_DARK)
		px(p, fx, -1, -2, 1, 1 + step, HORSE_DARK)
		px(p, fx, 0, -2, 1, 2 - step, HORSE_DARK)
		px(p, fx, -1, -6, 1, 2, dark)
		px(p, fx, -1, -9, 3, 3, col)
		px(p, fx, -1, -11, 2, 2, STEEL)
		if s.momentum > 0.5:
			px(p, fx, 2, -8, 6, 1, WOOD)
		else:
			px(p, fx, 2, -13, 1, 7, WOOD)
		draw_set_transform(Vector2.ZERO)
		return

	# Fantassin : jambes, corps, tête
	px(p, fx, -1, -2, 1, 2 - step, dark)
	px(p, fx, 1, -2, 1, 1 + step, dark)
	px(p, fx, -1, -5, 3, 3, col)
	match r.type:
		"men_at_arms":
			px(p, fx, -1, -7, 3, 2, STEEL)
			px(p, fx, 1, -7, 1, 1, SKIN)
			px(p, fx, 2, -5, 2, 3, dark.lightened(0.2))
			px(p, fx, 2, -4, 1, 1, Color(0.9, 0.8, 0.3))
		"spear":
			px(p, fx, -1, -7, 3, 2, SKIN)
			px(p, fx, -1, -7, 3, 1, STEEL)
			if s.foe != null:
				px(p, fx, 1, -5, 7, 1, WOOD)
				px(p, fx, 8, -5, 1, 1, STEEL)
			else:
				px(p, fx, 2, -10, 1, 9, WOOD)
				px(p, fx, 2, -11, 1, 1, STEEL)
		"archer":
			px(p, fx, -1, -7, 3, 2, Color(0.33, 0.42, 0.2))
			px(p, fx, 1, -6, 1, 1, SKIN)
			px(p, fx, 2, -7, 1, 5, WOOD)
			if s.attack_anim > 0.0:
				px(p, fx, 1, -5, 1, 1, Color(0.9, 0.9, 0.8))
	draw_set_transform(Vector2.ZERO)


func draw_tree(t: Vector2) -> void:
	if sprites.has_trees():
		var tr := sprites.tree_at(t)
		var src: Rect2 = tr["src"]
		var tp := t.round()
		draw_rect(Rect2(tp.x - 7, tp.y - 1, 14, 3), Color(0, 0, 0, 0.22))
		draw_texture_rect_region(tr["tex"], Rect2(tp - Vector2(8, 15), src.size), src)
		return
	draw_set_transform(t.round(), 0.0, Vector2(PX, PX))
	var p := Vector2.ZERO
	draw_rect(Rect2(p.x - 4, p.y - 1, 9, 2), Color(0, 0, 0, 0.22))
	draw_rect(Rect2(p.x - 1, p.y - 4, 2, 4), Color(0.35, 0.22, 0.12))
	draw_rect(Rect2(p.x - 4, p.y - 11, 9, 7), Color(0.12, 0.29, 0.12, 0.93))
	draw_rect(Rect2(p.x - 3, p.y - 13, 7, 2), Color(0.15, 0.35, 0.14, 0.93))
	draw_rect(Rect2(p.x - 2, p.y - 11, 3, 2), Color(0.22, 0.45, 0.18, 0.93))
	draw_set_transform(Vector2.ZERO)


## Poussière : petits carrés de « pixels » couleur terre qui grossissent un peu et s'estompent.
func draw_dust() -> void:
	for d in sim.dust:
		var k: float = d[2] / d[3] # 1 = vient d'apparaître
		var sz: float = d[4] * PX * (1.0 if k > 0.5 else 1.5)
		var p := ((d[0] as Vector2) / PX).round() * PX # Calé sur la grille des pixels
		var col := Color(0.66, 0.56, 0.4, 0.55 * k).lerp(Color(0.78, 0.72, 0.6, 0.4 * k), 1.0 - k)
		draw_rect(Rect2(p - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), col)


func draw_arrows() -> void:
	for a in sim.arrows:
		var k: float = a["t"] / a["dur"]
		var k2 := minf(k + 0.05, 1.0)
		var from: Vector2 = a["from"]
		var to: Vector2 = a["to"]
		var h: float = a["h"]
		var p1 := from.lerp(to, k) - Vector2(0, h * 4.0 * k * (1.0 - k))
		var p2 := from.lerp(to, k2) - Vector2(0, h * 4.0 * k2 * (1.0 - k2))
		var dir := (p2 - p1).normalized() * 5.0
		draw_line(p1 - dir, p1 + dir, Color(0.35, 0.25, 0.15), 1.0)
		draw_line(p1 + dir * 0.6, p1 + dir, Color(0.85, 0.87, 0.9), 1.0)


## Étendard au-dessus du régiment (dessiné en code, agrandi PX fois).
## Option « formes des camps » : rond (joueur) ou losange (ennemi) à côté du drapeau.
func draw_banner(r: Regiment) -> void:
	var lift := 34.0 if r.stats["mounted"] else 26.0
	var at := (r.center + Vector2(0, -lift)).round()
	draw_set_transform(at, 0.0, Vector2(PX, PX))
	draw_banner_shape(r, Vector2.ZERO)
	effects.draw_banner_tail(self, r, (TEAM_COLORS[r.team] as Color).darkened(0.5 if r.routing else 0.0))
	draw_set_transform(Vector2.ZERO)
	if GameOptions.team_shapes:
		Hud.draw_team_shape(self, r.team, at + Vector2(-9, -15), 4.5)


## Option « formes des camps » : petite marque sous chaque soldat visible, anneau clair pour le
## joueur, croix pour l'ennemi (distinguables sans voir le bleu et le rouge).
func draw_team_marks() -> void:
	for s in sim.soldiers:
		if not s.alive:
			continue
		var r: Regiment = s.regiment
		if r.team == ENEMY and r.hidden:
			continue
		var p: Vector2 = s.pos.round() + Vector2(0, 3)
		if r.team == PLAYER:
			draw_arc(p, 2.5, 0, TAU, 8, Color(0.85, 0.92, 1, 0.9), 1.0)
		else:
			draw_line(p + Vector2(-2.5, -2.5), p + Vector2(2.5, 2.5), Color(1, 0.85, 0.6, 0.9), 1.0)
			draw_line(p + Vector2(2.5, -2.5), p + Vector2(-2.5, 2.5), Color(1, 0.85, 0.6, 0.9), 1.0)


func draw_banner_shape(r: Regiment, base: Vector2) -> void:
	var col: Color = TEAM_COLORS[r.team]
	if r.routing:
		col = col.darkened(0.5)
	draw_line(base, base + Vector2(0, -10), WOOD, 1.0)
	draw_rect(Rect2(base.x, base.y - 10, 7, 5), col)
	draw_rect(Rect2(base.x, base.y - 10, 7, 5), Color(0, 0, 0, 0.6), false, 0.5)
	# Pictogramme du type
	var ic := Color(1, 1, 0.85)
	match r.type:
		"men_at_arms":
			draw_rect(Rect2(base.x + 3, base.y - 9, 1, 3), ic)
			draw_rect(Rect2(base.x + 2, base.y - 8, 3, 1), ic)
		"spear":
			draw_line(base + Vector2(1.5, -6), base + Vector2(5.5, -9.5), ic, 1.0)
		"archer":
			draw_arc(base + Vector2(3, -7.5), 1.8, -PI / 2, PI / 2, 6, ic, 1.0)
		"cavalry":
			draw_rect(Rect2(base.x + 2, base.y - 8, 3, 2), ic)
	# Barre de moral
	var k := clampf(r.morale / r.max_morale, 0.0, 1.0)
	draw_rect(Rect2(base.x - 4, base.y + 1, 14, 2), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(base.x - 4, base.y + 1, 14 * k, 2), Color(1, 0.2, 0.15).lerp(Color(0.3, 1, 0.3), k))
	if r.selected:
		draw_rect(Rect2(base.x - 1, base.y - 11, 9, 7), Color(1, 0.95, 0.4), false, 0.7)
	if r.team == PLAYER and r.hidden:
		draw_rect(Rect2(base.x + 8, base.y - 9, 2, 2), Color(0.3, 1, 0.4))


## Petits reflets mouvants sur l'eau de la rivière.
func draw_river_glints() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for i in 70:
		var x := fposmod(i * 47.3 + t * 18.0, WORLD_SIZE.x)
		var off := sin(i * 12.9898) * (Terrain.RIVER_HALF - 8.0)
		var p := Vector2(x, sim.road_y(x) + off).round()
		if sim.terrain.is_ford(p):
			continue
		var a := 0.25 + 0.2 * sin(t * 2.0 + i)
		draw_rect(Rect2(p.x, p.y, 6, 2), Color(0.85, 0.93, 1.0, a))


## Maison vue de trois quarts : l'emprise au sol r porte les murs, le toit déborde vers le haut.
func draw_house(r: Rect2) -> void:
	var x := r.position.x
	var w := r.size.x
	var wall_h := roundf(r.size.y * 0.45 / PX) * PX
	var roof_top := r.position.y - 20.0
	var eave := r.end.y - wall_h
	draw_rect(Rect2(x + 4, r.end.y - 2, w, 6), Color(0, 0, 0, 0.25)) # Ombre
	# Murs à colombages
	draw_rect(Rect2(x, eave, w, wall_h), Color(0.86, 0.79, 0.62))
	var beam := Color(0.36, 0.23, 0.13)
	draw_rect(Rect2(x, eave, w, PX), beam)
	draw_rect(Rect2(x, r.end.y - PX, w, PX), beam)
	var bx := x
	while bx <= x + w - PX:
		draw_rect(Rect2(bx, eave, PX, wall_h), beam)
		bx += 14.0
	draw_rect(Rect2(x + w - PX, eave, PX, wall_h), beam)
	# Porte et fenêtre
	var door := Rect2(roundf((x + w * 0.5) / PX) * PX, r.end.y - 12.0, 6, 12 - PX)
	draw_rect(door, Color(0.3, 0.18, 0.1))
	draw_rect(Rect2(x + 4, eave + 4, 6, 4), Color(0.2, 0.25, 0.3))
	# Toit de tuiles
	var roof := Rect2(x - PX * 2, roof_top, w + PX * 4, eave - roof_top)
	var row := 0
	var y := roof.position.y
	while y < roof.end.y:
		var col := Color(0.62, 0.28, 0.18) if row % 2 == 0 else Color(0.53, 0.22, 0.14)
		draw_rect(Rect2(roof.position.x, y, roof.size.x, minf(PX * 2, roof.end.y - y)), col)
		var tx := roof.position.x + (PX * 2 if row % 2 == 0 else 0.0)
		while tx < roof.end.x:
			draw_rect(Rect2(tx, y, PX, PX), Color(0.45, 0.18, 0.11))
			tx += PX * 4
		y += PX * 2
		row += 1
	draw_rect(Rect2(roof.position.x, roof.position.y, roof.size.x, PX), Color(0.4, 0.16, 0.1)) # Faîtage
	draw_rect(Rect2(roof.position.x, roof.end.y - PX, roof.size.x, PX), Color(0.3, 0.12, 0.08)) # Avant-toit
	# Cheminée
	draw_rect(Rect2(x + w - 14, roof_top - 6, 6, 10), Color(0.5, 0.48, 0.45))


## Tronçon de palissade : une rangée de pieux taillés en pointe.
func draw_palisade(r: Rect2) -> void:
	var base := r.end.y
	draw_rect(Rect2(r.position.x, base - 2, r.size.x, 4), Color(0, 0, 0, 0.25))
	var x := r.position.x
	var i := 0
	while x < r.end.x - 1.0:
		var h := 16.0 + float((i * 7) % 3) * PX
		var top := base - h
		draw_rect(Rect2(x, top + PX, 4, h - PX), Color(0.5, 0.34, 0.18))
		draw_rect(Rect2(x + 3, top + PX, 1, h - PX), Color(0.33, 0.21, 0.1))
		draw_rect(Rect2(x + 1, top, 2, PX), Color(0.62, 0.45, 0.26)) # Pointe
		x += 5.0
		i += 1
	# Liens de corde
	draw_rect(Rect2(r.position.x, base - 10, r.size.x, 1), Color(0.7, 0.6, 0.38, 0.9))
