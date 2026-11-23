class_name BattleRenderer
extends Node2D
## Rendu pixel art de la bataille, dessiné en un seul _draw() : sol, relief et eau, zone de
## déploiement, boue, corps, armes au sol, flèches plantées et étendards tombés (BattleField), poussière, ordres des régiments sélectionnés, soldats, arbres, maisons et
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
## Alliés (camp du joueur, menés par l'IA) : bleu-vert, proche du bleu de la compagnie
const ALLY_COLOR := Color(0.18, 0.62, 0.66)
const ALLY_DARK := Color(0.08, 0.3, 0.32)
const ALLY_MOD := Color(0.5, 1.15, 0.62) ## Teinte appliquée aux planches bleues des alliés
const SKIN := Color(0.93, 0.76, 0.6)
const STEEL := Color(0.72, 0.74, 0.78)
const STEEL_BRIGHT := Color(0.79, 0.805, 0.835) ## Pointes des piques et des lances
const WOOD := Color(0.48, 0.32, 0.17)
const HORSE := Color(0.42, 0.27, 0.15)
const HORSE_DARK := Color(0.28, 0.17, 0.09)
const PX := 2.0 ## Taille d'un « pixel » des dessins en code (repli quand un sprite manque)
const MARKER_LIFE := 0.6 ## Durée d'un repère d'ordre (secondes)
const FALL_TIME := 0.45 ## Durée de la chute d'un soldat tué (secondes de bataille)
const KNEEL_TIME := 1.1 ## Mort à genoux : il s'affaisse, reste un instant, puis bascule
## Manières de tomber (death_kind)
enum { DEATH_SIDE, DEATH_BACK, DEATH_FORWARD, DEATH_KNEEL }
const CORPSE_TINT := Color(0.55, 0.45, 0.42, 0.85) ## Teinte d'un corps au sol
const ARROW_SHAFT := Color(0.32, 0.22, 0.12)
const ARROW_FLETCH := Color(0.96, 0.95, 0.9)

var battle: Battle
var sim: BattleSim
var sprites := SpriteBank.new()
var ground_tex: ImageTexture
var ground_scale := 1.0 ## Taille d'un pixel de ground_tex dans le monde
var terrain_tex: ImageTexture = null ## Couche du relief et de l'eau posée sur le sol
var ground_tint := Color(0, 0, 0, 0) ## Voile de saison sur le sol (Battle.apply_ambiance)
var markers: Array = [] ## Repères d'ordres : [position, couleur, vie restante]
var field: BattleField ## Traces persistantes : débris, flèches plantées, boue, étendards tombés (battle_field.gd)
var effects: BattleEffects ## Sang, fumée, éclaboussures, pluie au sol… (battle_effects.gd)
var arms: Dictionary = Heraldry.DEFAULT ## Armoiries de la compagnie (bannières du joueur)
var enemy_faction := -1 ## Faction ennemie du contrat (couleurs de ses bannières), -1 : aucune
var looks := {} ## Regiment -> {"tex" : planche repeinte, "helmet", "armor", "weapon"} (équipement visible)


func _init(b: Battle) -> void:
	battle = b
	sim = b.sim
	name = "Renderer"
	effects = BattleEffects.new(sim)
	field = BattleField.new(sim)
	if b.campaign != null:
		arms = b.campaign.arms
		if not b.campaign.pending.is_empty():
			enemy_faction = int(b.campaign.pending.get("enemy_faction", -1))


## Repère d'ordre (cercle qui s'élargit et s'efface) en p.
func add_marker(p: Vector2, col: Color) -> void:
	markers.append([p, col, MARKER_LIFE])


## Effets en temps réel (indépendants de la vitesse du jeu).
func update_effects(delta: float) -> void:
	for m in markers:
		m[2] -= delta
	markers = markers.filter(func(m): return m[2] > 0.0)
	effects.update(delta, self)
	field.update(delta)


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
	if ground_tint.a > 0.0:
		draw_rect(Rect2(Vector2.ZERO, WORLD_SIZE), ground_tint) # Sous le relief : l'eau et les murs restent nets
	if terrain_tex != null:
		draw_texture_rect(terrain_tex, Rect2(Vector2.ZERO, WORLD_SIZE), false)
	if sim.terrain.has_river():
		draw_river_glints()
	if sim.siege != null:
		sim.siege.draw_ground(self)

	if sim.state == BattleSim.State.DEPLOY:
		var top := sim.deploy_top()
		draw_rect(Rect2(0, top, WORLD_SIZE.x, WORLD_SIZE.y - top), Color(0.3, 0.5, 1.0, 0.08))
		draw_line(Vector2(0, top), Vector2(WORLD_SIZE.x, top), Color(0.6, 0.75, 1.0, 0.4), 2.0)

	var view := effects.view
	var cull := view.has_area()
	field.draw_mud(self, view)
	for c in sim.corpses:
		if not cull or view.has_point(c[0]):
			draw_corpse(c)
	field.draw_ground(self, view)
	for fb in field.fallen:
		if not cull or view.has_point(fb[0]):
			draw_fallen_banner(fb)

	draw_dust()
	effects.draw_ground(self)
	sim.objective.draw(self, sim) # Zone à tenir ou à prendre, chariots du convoi, ligne de fuite
	if sim.traps != null:
		sim.traps.draw(self, sim.state == BattleSim.State.DEPLOY) # Pieux, fossés, chausse-trapes
		sim.traps.draw_ghost(self, sim, get_global_mouse_position())


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
		draw_order_queue(r)

	# Flèche d'orientation de chaque régiment du joueur (plus visible s'il est sélectionné)
	for r in sim.regiments:
		if r.team != PLAYER or r.allied or r.is_dead() or r.routing:
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
		if s.regiment.team == ENEMY and sim.unseen(s.regiment):
			continue # Caché en forêt, ou perdu dans le brouillard
		items.append([s.pos.y, s])
	for t in sim.trees:
		items.append([t.y, t])
	for h in sim.terrain.houses:
		items.append([h.end.y, h])
	for w in sim.terrain.walls:
		items.append([w.end.y, w])
	if sim.siege != null:
		sim.siege.add_items(items, self) # Rempart, tours, porte, échelles, bélier : [y, Callable]
	items.sort_custom(func(a, b): return a[0] < b[0])
	for it in items:
		if it[1] is Vector2:
			draw_tree(it[1])
		elif it[1] is Callable:
			it[1].call()
		elif it[1] is Rect2:
			if (it[1] as Rect2).size.y <= Terrain.WALL_HALF * 2.0:
				draw_palisade(it[1])
			else:
				draw_house(it[1])
		else:
			draw_soldier(it[1])

	effects.draw_air(self)
	draw_arrows()
	if sim.siege != null:
		sim.siege.draw_air(self)

	if GameOptions.team_shapes:
		draw_team_marks()
	if sim.captain != null:
		sim.captain.draw(self, sim.state == BattleSim.State.DEPLOY)
	if sim.commander != null and sim.commander.guard != null:
		sim.commander.draw(self, flag_color(sim.commander.guard))
	Officers.draw(self, sim) # Officiers à la tête de leurs régiments

	for r in sim.regiments:
		if r.is_dead() or (r.team == ENEMY and sim.unseen(r)) or field.routed.has(r):
			continue # L'étendard d'un régiment en déroute est tombé (draw_fallen_banner)
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
## File d'ordres (Maj) d'un régiment sélectionné : points de passage numérotés reliés en pointillés,
## depuis la fin de l'ordre en cours ; une attaque en file se marque en rouge sur sa cible.
func draw_order_queue(r: Regiment) -> void:
	if r.orders.is_empty():
		return
	var from := r.target.center if r.target != null else r.dest
	var font := ThemeDB.fallback_font
	var n := 1
	for o in r.orders:
		var to: Vector2
		var col := Color(1, 1, 1, 0.55)
		if str(o["kind"]) == "attack":
			var t: Regiment = o.get("target")
			if t == null or t.is_dead():
				continue
			to = t.center
			col = Color(1, 0.35, 0.25, 0.7)
		else:
			to = o["dest"]
			if bool(o.get("run", false)):
				col = Color(1, 0.6, 0.15, 0.75)
		draw_dashed_line(from, to, col, 2.0, 6.0)
		draw_circle(to, 6.0, Color(0.08, 0.06, 0.04, 0.8))
		draw_arc(to, 6.0, 0.0, TAU, 16, col, 1.5)
		draw_string(font, to + Vector2(-3.5, 4.0), str(n), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 0.95, 0.8))
		from = to
		n += 1


func draw_line_preview() -> void:
	var ghost := Color(1, 0.95, 0.4, 0.55)
	var lw := 1.0 / battle.camera.zoom.x
	var o := battle.orders
	draw_line(o.line_start, o.line_now, Color(1, 1, 1, 0.35), lw)
	for e in o.line_layout(sim.selected_regiments(), o.line_start, o.line_now, o.line_queue):
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
	if r.team == ENEMY:
		hidden_alpha = r.fog_alpha # Brouillard : l'ennemi s'estompe avec la distance
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
		if sim.siege != null:
			p.y -= roundf(sim.siege.lift(s.pos)) # Sur le chemin de ronde ou à l'échelle
		p += anim_offset(s, look, anim, t)
		if r.routing and s.moving:
			p.y -= roundf(absf(sin(s.anim * 2.2)) * 1.5) # Course éperdue des fuyards
		elif r.type == "crossbow":
			var rl := reload_progress(s)
			if rl >= 0.0 and rl < 0.85 and sin(rl * TAU * 3.0) > 0.0:
				p.y += 1.0 # Il tend l'arbalète
		var src: Rect2 = f["src"]
		var foot: Vector2 = f["foot"]
		draw_rect(Rect2(p.x - 5, p.y - 1, 10, 3), Color(0, 0, 0, 0.22))
		var tint: Color = f["tint"]
		var mod := Color(tint.r, tint.g, tint.b, hidden_alpha)
		if r.allied:
			mod *= ALLY_MOD
		if s.flash > 0.0:
			mod = Color(2.5, 2.5, 2.5, hidden_alpha) # Éclair blanc quand il est touché
		var lk := look_of(r)
		if r.facing.y < 0.0 and r.type == "crossbow":
			draw_pavise(s, p, hidden_alpha) # Pavois du côté de l'ennemi, loin de la caméra : derrière lui
		draw_texture_rect_region(lk["tex"], Rect2(p - foot, src.size), src, mod)
		if int(lk["weapon"]) >= 2:
			draw_weapon_gleam(s, p - foot, r.type, src, int(lk["weapon"]), anim == "attack", hidden_alpha)
		draw_unit_extras(s, p, p - foot, src, look, anim == "attack", hidden_alpha)
		return
	draw_soldier_code(s)


## Équipement visible d'un régiment (mis en cache) : planche repeinte et qualités des pièces.
func look_of(r: Regiment) -> Dictionary:
	var lk: Variant = looks.get(r)
	if lk == null:
		var h := r.gear_tier("helmet")
		var a := r.gear_tier("armor")
		# Chevaliers à pied : toujours en harnois blanc (plates polies), quel que soit l'équipement
		var th := maxi(h, 2) if r.type == "foot_knight" else h
		var ta := 3 if r.type == "foot_knight" else a
		lk = {"helmet": h, "armor": a, "weapon": r.gear_tier("weapon"),
			"tex": sprites.dressed_tex(r.type, r.team, th, ta) if sprites.has_unit(r.type, r.team) else null}
		looks[r] = lk
	return lk


## Décalage d'animation : léger galop des montés, fente vers l'adversaire pendant un coup de
## mêlée (plus longue pour les montés et les piques), recul de l'épaule au tir.
func anim_offset(s: Soldier, look: Vector2, anim: String, t: float) -> Vector2:
	var r := s.regiment
	if anim == "attack":
		var f := look.normalized()
		var k := sin(clampf(t, 0.0, 1.0) * PI)
		if r.stats["ranged"] and s.foe == null:
			return (-f * k * 1.5).round() # Recul de l'arc ou de l'arbalète
		var reach := 4.0 if (r.stats["mounted"] or r.type == "spear") else 2.5
		return (f * k * reach).round()
	if anim == "walk" and r.stats["mounted"] and (r.running or s.momentum > 0.5):
		return Vector2(0, -roundf(absf(sin(s.anim * 1.6)) * 2.0)) # Galop : le cheval se soulève
	return Vector2.ZERO


## Éclat des meilleures armes au bout de la lame : un reflet de temps en temps (armes de maître),
## un halo doré qui palpite et un reflet fréquent (armes de Milan) ; vif pendant le coup.
func draw_weapon_gleam(s: Soldier, origin: Vector2, type: String, src: Rect2, tier: int, striking: bool, alpha: float) -> void:
	var tip := sprites.blade_tip(type, src)
	var q := (origin + tip) if tip.x >= 0.0 else origin + Vector2(src.size.x * 0.75, src.size.y * 0.3)
	var phase := float(s.get_instance_id() % 113) * 0.71
	var clock := effects.clock
	if tier >= 3:
		var a := (0.25 + 0.15 * sin(clock * 4.0 + phase)) * alpha
		draw_rect(Rect2(q - Vector2(1, 1), Vector2(3, 3)), Color(1.0, 0.85, 0.4, a))
	var shine := sin(clock * (2.2 if tier >= 3 else 1.3) + phase)
	if striking or shine > (0.8 if tier >= 3 else 0.94):
		var c := Color(1, 1, 0.9, alpha) if tier >= 3 else Color(1, 1, 1, 0.85 * alpha)
		draw_rect(Rect2(q.x - 1, q.y, 3, 1), c)
		draw_rect(Rect2(q.x, q.y - 1, 1, 3), c)


## Avancement du rechargement d'un tireur (0 juste après le tir, 1 prêt), -1 s'il ne recharge pas.
func reload_progress(s: Soldier) -> float:
	var r := s.regiment
	if r.fire_target == null or s.attack_anim > 0.0 or s.cooldown <= 0.0 or s.foe != null:
		return -1.0
	var full: float = r.stats["reload"]
	if full <= 0.0 or s.cooldown > full * 1.3:
		return -1.0
	return clampf(1.0 - s.cooldown / full, 0.0, 1.0)


## Pavois planté devant un arbalétrier qui tient sa place.
func draw_pavise(s: Soldier, p: Vector2, alpha: float) -> void:
	var r := s.regiment
	if sim.pavise_factor(r) >= 1.0:
		return
	var c := p + r.facing.normalized() * 6.0 + Vector2(0, -6)
	draw_rect(Rect2(c - Vector2(4, 5), Vector2(8, 10)), Color(WOOD, alpha))
	draw_rect(Rect2(c - Vector2(2, 3), Vector2(4, 5)), Color(TEAM_COLORS[r.team], alpha))


## Silhouettes propres à chaque type, dessinées par-dessus les planches : longues piques (dressées,
## ou baissées face à l'ennemi), arcs longs plus hauts qu'un homme, arbalètes (tendues au pied
## pendant le rechargement), lances à pennon des cavaliers, arc court et carquois des archers
## montés, reflets du harnois des chevaliers à pied, pavois des arbalétriers. Les fuyards ont jeté
## leurs armes (BattleField) : rien n'est dessiné pour eux.
## p : point des pieds ; origin : coin de la case ; src : case de la planche ; look : regard.
func draw_unit_extras(s: Soldier, p: Vector2, origin: Vector2, src: Rect2, look: Vector2, striking: bool, alpha: float) -> void:
	var r := s.regiment
	var type := r.type
	if type == "men_at_arms" or (r.routing and type != "crossbow"):
		return # Rien à ajouter ; les fuyards ont jeté leurs armes
	if type == "crossbow" and r.facing.y >= 0.0:
		draw_pavise(s, p, alpha) # Pavois devant l'arbalétrier (vers la caméra) : par-dessus lui
	if r.routing:
		return
	var wood := Color(WOOD, alpha)
	var steel := Color(STEEL_BRIGHT, alpha)
	var f := look.normalized() if look.length_squared() > 0.01 else Vector2.DOWN
	var tip := Vector2(-1, -1)
	if type == "spear" or type == "archer":
		tip = sprites.blade_tip(type, src)
	var hand := origin + tip if tip.x >= 0.0 else p + Vector2(4, -8)
	match type:
		"spear":
			if s.foe != null or striking:
				# Pique baissée : elle dépasse loin devant le premier rang
				var grip := p + Vector2(0, -7)
				var lunge := f * (3.0 if striking else 0.0)
				draw_line(grip - f * 8.0 + lunge, grip + f * 26.0 + lunge, wood, 1.0)
				draw_line(grip + f * 26.0 + lunge, grip + f * 30.0 + lunge, steel, 1.0)
			else:
				# Pique dressée : la hampe de la planche prolongée bien au-dessus des têtes
				var sway := roundf(sin(effects.clock * 1.3 + float(s.get_instance_id() % 53)) * 0.6)
				var top := Vector2(hand.x + sway, hand.y - 16.0)
				draw_line(hand, top, wood, 1.0)
				draw_line(top, top + Vector2(0, -3), steel, 1.0)
		"archer":
			# Arc long : une douve plus haute que l'archer, à son côté
			var bx := hand.x if tip.x >= 0.0 else p.x + 5.0
			var y0 := p.y - 21.0
			var y1 := p.y + 1.0
			var bulge := 2.0 if f.x >= 0.0 else -2.0
			var mid := Vector2(bx + bulge, (y0 + y1) * 0.5)
			draw_line(Vector2(bx, y0), mid, wood, 1.0)
			draw_line(mid, Vector2(bx, y1), wood, 1.0)
			var string := Color(0.9, 0.9, 0.82, 0.7 * alpha)
			if striking: # Corde tirée jusqu'à l'oreille
				var nock := Vector2(bx - bulge * 2.0, mid.y)
				draw_line(Vector2(bx, y0), nock, string, 1.0)
				draw_line(nock, Vector2(bx, y1), string, 1.0)
			else:
				draw_line(Vector2(bx, y0), Vector2(bx, y1), string, 1.0)
		"crossbow":
			var rl := reload_progress(s)
			if rl >= 0.0 and rl < 0.85:
				# Rechargement : arbalète tête en bas, le pied dans l'étrier, le cranequin qui tourne
				var x := p.x + (5.0 if f.x >= 0.0 else -5.0)
				draw_line(Vector2(x, p.y - 1), Vector2(x, p.y - 10), wood, 2.0)
				draw_line(Vector2(x - 4, p.y - 1), Vector2(x + 4, p.y - 1), steel, 1.0)
				var crank := Vector2(x, p.y - 10) + Vector2.from_angle(rl * TAU * 3.0) * 2.0
				draw_rect(Rect2(crank.round(), Vector2(1, 1)), Color(0.3, 0.3, 0.32, alpha))
			else:
				# Arbalète épaulée : fût vers la cible, arc d'acier en travers
				var grip := p + Vector2(0, -7)
				var front := grip + f * (8.0 if not striking else 6.0)
				var n := Vector2(-f.y, f.x * 0.6)
				draw_line(grip - f * 2.0, front, wood, 2.0)
				draw_line(front - n * 4.0, front + n * 4.0, steel, 1.0)
		"foot_knight":
			# Harnois poli : un reflet qui court sur les plates, le plumet blanc
			var phase := float(s.get_instance_id() % 89) * 0.53
			var shine := sin(effects.clock * 1.8 + phase)
			if shine > 0.55:
				var y := p.y - 6.0 - roundf((shine - 0.55) / 0.45 * 6.0)
				draw_rect(Rect2(p.x - 2, y, 1, 1), Color(1, 1, 1, 0.9 * alpha))
			draw_rect(Rect2(p.x + 1, p.y - 9, 1, 1), Color(1, 1, 1, 0.55 * alpha))
			draw_rect(Rect2(p.x - 1, p.y - 18, 2, 3), Color(0.96, 0.92, 0.78, alpha))
		"cavalry":
			# Lance à pennon : couchée pendant la charge, dressée sinon
			var pennon := Color(team_color(r), alpha)
			if s.momentum > 0.5 or striking or (r.running and s.moving):
				var grip := p + Vector2(0, -14)
				var end := grip + f * 22.0
				draw_line(grip - f * 6.0, end, Color(0.62, 0.5, 0.32, alpha), 1.5)
				draw_line(end, end + f * 3.0, steel, 1.0)
				draw_rect(Rect2((end - f * 5.0).round() + Vector2(0, -1), Vector2(2, 2)), pennon)
			else:
				var x := p.x + (7.0 if f.x >= 0.0 else -7.0)
				draw_line(Vector2(x, p.y - 4), Vector2(x, p.y - 32), Color(0.62, 0.5, 0.32, alpha), 1.5)
				draw_line(Vector2(x, p.y - 32), Vector2(x, p.y - 35), steel, 1.0)
				var wave := roundf(sin(effects.clock * 5.0 + float(s.get_instance_id() % 37)))
				draw_rect(Rect2(x, p.y - 31 + wave, 4, 2), pennon)
		"horse_archer":
			# Arc court recourbé et carquois au dos : pas de lance ni de caparaçon
			var bx := p.x + (6.0 if f.x >= 0.0 else -6.0)
			var dirx := 1.0 if f.x >= 0.0 else -1.0
			draw_line(Vector2(bx - dirx, p.y - 22), Vector2(bx + dirx * 2.0, p.y - 17), wood, 1.0)
			draw_line(Vector2(bx + dirx * 2.0, p.y - 17), Vector2(bx - dirx, p.y - 12), wood, 1.0)
			draw_line(Vector2(bx - dirx, p.y - 22), Vector2(bx - dirx * (3.0 if striking else 1.0), p.y - 17), Color(0.9, 0.9, 0.82, 0.7 * alpha), 1.0)
			draw_line(Vector2(bx - dirx, p.y - 17), Vector2(bx - dirx, p.y - 12), Color(0.9, 0.9, 0.82, 0.7 * alpha), 1.0)
			var qx := p.x - dirx * 5.0
			draw_rect(Rect2(qx - 1, p.y - 19, 3, 6), Color(0.36, 0.22, 0.12, alpha))
			draw_rect(Rect2(qx - 1, p.y - 21, 1, 2), Color(0.92, 0.9, 0.84, alpha))
			draw_rect(Rect2(qx + 1, p.y - 20, 1, 1), Color(0.92, 0.9, 0.84, alpha))


## Manière de tomber d'un corps (stable : tirée de sa position et de l'heure de sa mort, sans
## toucher au hasard de la simulation). Les montés tombent toujours sur le flanc.
func death_kind(c: Array) -> int:
	if c.size() <= 6 or UnitTypes.STATS[c[2]]["mounted"]:
		return DEATH_SIDE
	var p: Vector2 = c[0]
	var h := absi(int(p.x) * 7 + int(p.y) * 13 + int(float(c[4]) * 10.0))
	return h % 4


## Pose d'un corps qui tombe : rotation et échelle verticale autour des pieds, selon la direction
## où finit la tête (lie). k : avancement de la chute (0 debout, 1 couché).
static func fall_pose(lie: Vector2, k: float) -> Array:
	var e := k * k # La chute accélère
	if absf(lie.x) >= absf(lie.y) * 0.8:
		return [signf(lie.x) * PI * 0.5 * e, 1.0]
	if lie.y < 0.0:
		return [0.0, lerpf(1.0, 0.45, e)] # Tête vers le haut de l'écran : vu en raccourci
	return [0.0, lerpf(1.0, -0.55, e)] # Tête vers la caméra : le corps passe devant les pieds


## Corps au sol : le sprite qui tombe (FALL_TIME, KNEEL_TIME) puis reste couché et assombri, avec
## son équipement ; quatre manières : sur le côté, à la renverse (loin du coup), en avant (vers le
## coup), à genoux puis en avant. Repli : un petit dessin en code.
## c : [position, camp, type, côté, heure de la mort, régiment, regard] (les 4 premiers suffisent).
func draw_corpse(c: Array) -> void:
	var p: Vector2 = c[0]
	var team: int = c[1]
	var type: String = c[2]
	var side: int = c[3]
	var kind := death_kind(c)
	var k := 1.0 # Avancement de la chute (1 = couché)
	var kneel := 0.0 # Affaissement à genoux (0 à 1)
	if c.size() > 4 and sim.state == BattleSim.State.BATTLE:
		var age := sim.battle_time - float(c[4])
		if kind == DEATH_KNEEL:
			kneel = clampf(age / (KNEEL_TIME * 0.4), 0.0, 1.0)
			k = clampf((age - KNEEL_TIME * 0.55) / (KNEEL_TIME * 0.45), 0.0, 1.0)
		else:
			k = clampf(age / FALL_TIME, 0.0, 1.0)
	elif kind == DEATH_KNEEL:
		kneel = 1.0
	if sprites.has_unit(type, team):
		var dir := SpriteBank.DOWN
		var look := Vector2.DOWN
		if c.size() > 6:
			look = c[6]
			if look.length_squared() < 0.01:
				look = Vector2.DOWN
			dir = SpriteBank.dir_of(look)
		var f := sprites.frame(type, team, dir, "idle", 0.0)
		var src: Rect2 = f["src"]
		var foot: Vector2 = f["foot"]
		var tex: Texture2D = f["tex"]
		if c.size() > 5 and c[5] is Regiment and (c[5] as Regiment).team == team:
			var lk := look_of(c[5])
			if lk["tex"] != null:
				tex = lk["tex"]
		var tint: Color = f["tint"]
		var lie := Vector2(side, 0)
		match kind:
			DEATH_BACK:
				lie = -look
			DEATH_FORWARD, DEATH_KNEEL:
				lie = look
		var pose := fall_pose(lie, k)
		var sy: float = float(pose[1]) * lerpf(1.0, 0.72, kneel) if k < 1.0 else float(pose[1])
		# Bascule autour des pieds ; le corps s'assombrit au sol
		draw_set_transform(p + Vector2(0, -2.0 * k + kneel * (1.0 - k)), pose[0], Vector2(1.0, sy))
		draw_texture_rect_region(tex, Rect2(Vector2(-src.size.x * 0.5, -foot.y), src.size), src, Color(tint, 1.0).lerp(CORPSE_TINT, maxf(k, kneel * 0.3)))
		draw_set_transform(Vector2.ZERO)
		return
	draw_set_transform(p, side * PI * 0.5 * (1.0 - k), Vector2(PX, PX))
	if UnitTypes.STATS[type]["mounted"]:
		draw_rect(Rect2(-3, -2, 7, 2), HORSE_DARK)
	draw_rect(Rect2(-2, -1, 4, 1), TEAM_DARK[team])
	draw_rect(Rect2(-1, 0, 2, 1), Color(0.45, 0.07, 0.05, 0.8 * k))
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
	var col: Color = team_color(r)
	var dark: Color = ALLY_DARK if r.allied else TEAM_DARK[r.team]
	if s.flash > 0.0:
		col = Color.WHITE
	var step := 0.0
	if s.moving and int(s.anim) % 2 == 0:
		step = 1.0
	var alpha := 0.55 if (r.team == PLAYER and r.hidden) else 1.0
	if r.team == ENEMY:
		alpha = r.fog_alpha
	if alpha < 1.0:
		col.a = alpha
		dark.a = alpha
	var lk := look_of(r)
	var steel := STEEL if int(lk["helmet"]) == 0 else SpriteBank.HELMET_COLORS[int(lk["helmet"])]

	draw_rect(Rect2(p.x - 2, p.y - 0.5, 5, 1.5), Color(0, 0, 0, 0.28))

	if r.stats["mounted"]:
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
		px(p, fx, -1, -11, 2, 2, steel)
		if r.stats["skirmish"]:
			px(p, fx, 2, -11, 1, 5, WOOD) # Arc
		elif s.momentum > 0.5:
			px(p, fx, 2, -8, 6, 1, WOOD)
		else:
			px(p, fx, 2, -13, 1, 7, WOOD)
		draw_set_transform(Vector2.ZERO)
		return

	# Fantassin : jambes, corps, tête
	px(p, fx, -1, -2, 1, 2 - step, dark)
	px(p, fx, 1, -2, 1, 1 + step, dark)
	px(p, fx, -1, -5, 3, 3, col)
	if int(lk["armor"]) > 0: # Armure : épaule et flanc
		px(p, fx, -1, -5, 1, 2, SpriteBank.ARMOR_COLORS[int(lk["armor"])])
	match r.type:
		"men_at_arms":
			px(p, fx, -1, -7, 3, 2, steel)
			px(p, fx, 1, -7, 1, 1, SKIN)
			px(p, fx, 2, -5, 2, 3, dark.lightened(0.2))
			px(p, fx, 2, -4, 1, 1, Color(0.9, 0.8, 0.3))
		"spear":
			px(p, fx, -1, -7, 3, 2, SKIN)
			px(p, fx, -1, -7, 3, 1, steel)
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
		"foot_knight":
			px(p, fx, -1, -7, 3, 2, steel)
			px(p, fx, -1, -5, 3, 1, STEEL)
			px(p, fx, 0, -8, 1, 1, Color(0.96, 0.92, 0.78))
			px(p, fx, 2, -7, 1, 5, STEEL.lightened(0.2))
		"crossbow":
			px(p, fx, -1, -7, 3, 2, steel)
			px(p, fx, 1, -6, 1, 1, SKIN)
			px(p, fx, 1, -5, 4, 1, WOOD)
			px(p, fx, 4, -6, 1, 3, WOOD)
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
	var lvl := effects.level()
	if lvl == 0:
		return
	var i := 0
	for d in sim.dust:
		i += 1
		if lvl == 1 and i % 2 == 0:
			continue # Effets réduits : un grain sur deux
		var k: float = d[2] / d[3] # 1 = vient d'apparaître
		var sz: float = d[4] * PX * (1.0 if k > 0.5 else 1.5)
		var p := ((d[0] as Vector2) / PX).round() * PX # Calé sur la grille des pixels
		var col := Color(0.66, 0.56, 0.4, 0.55 * k).lerp(Color(0.78, 0.72, 0.6, 0.4 * k), 1.0 - k)
		draw_rect(Rect2(p - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), col)


## Flèches et carreaux en vol : ombre au sol (qui montre la trajectoire), hampe épaisse, pointe
## d'acier et empennage clair ; les carreaux d'arbalète sont plus courts et plus trapus.
func draw_arrows() -> void:
	var view := effects.view
	var cull := view.has_area()
	for a in sim.arrows:
		var k: float = a["t"] / a["dur"]
		var k2 := minf(k + 0.05, 1.0)
		var from: Vector2 = a["from"]
		var to: Vector2 = a["to"]
		var h: float = a["h"]
		var p1 := from.lerp(to, k) - Vector2(0, h * 4.0 * k * (1.0 - k))
		if cull and not view.has_point(p1):
			continue
		var p2 := from.lerp(to, k2) - Vector2(0, h * 4.0 * k2 * (1.0 - k2))
		var bolt := float(a.get("pierce", 0.0)) > 0.0
		var dir := (p2 - p1).normalized() * (4.0 if bolt else 6.0)
		# Ombre au sol, sous la flèche (le départ est tiré à hauteur d'épaule)
		var g := (from + Vector2(0, 8)).lerp(to, k)
		draw_line(g - dir * 0.8, g + dir * 0.8, Color(0, 0, 0, 0.22), 2.0)
		draw_line(p1 - dir, p1 + dir, ARROW_SHAFT, 2.0 if bolt else 1.5)
		draw_line(p1 + dir * 0.55, p1 + dir * 1.15, STEEL.lightened(0.2), 2.0)
		draw_line(p1 - dir, p1 - dir * (0.6 if bolt else 0.45), ARROW_FLETCH if not bolt else Color(0.6, 0.5, 0.35), 2.5)


## Étendard au-dessus du régiment (dessiné en code, agrandi PX fois).
## Option « formes des camps » : rond (joueur) ou losange (ennemi) à côté du drapeau.
func draw_banner(r: Regiment) -> void:
	var lift := 34.0 if r.stats["mounted"] else 26.0
	var at := (r.center + Vector2(0, -lift)).round()
	draw_set_transform(at, 0.0, Vector2(PX, PX))
	draw_banner_shape(r, Vector2.ZERO)
	effects.draw_banner_tail(self, r, flag_tail_color(r).darkened(0.5 if r.routing else 0.0))
	draw_set_transform(Vector2.ZERO)
	if GameOptions.team_shapes:
		Hud.draw_team_shape(self, r.team, at + Vector2(-23, -15), 4.5)


## Étendard tombé d'un régiment brisé (BattleField.fallen) : la hampe bascule autour de son pied
## (BattleField.BANNER_FALL) puis reste couchée, le drapeau souillé de boue.
func draw_fallen_banner(fb: Array) -> void:
	var base: Vector2 = fb[0]
	var r: Regiment = fb[1]
	var k := clampf((field.clock - float(fb[2])) / BattleField.BANNER_FALL, 0.0, 1.0)
	var side := float(fb[3])
	draw_rect(Rect2(base.x - 4 + side * 8.0 * k, base.y - 1, 8 + 10.0 * k, 3), Color(0, 0, 0, 0.18 * k))
	draw_set_transform(base, side * PI * 0.5 * 0.9 * k * k, Vector2(PX, PX))
	draw_line(Vector2.ZERO, Vector2(0, -10), WOOD, 1.0)
	var flag := Rect2(0, -10, 7, 5)
	if r.team == PLAYER and not r.allied:
		Heraldry.draw(self, flag, arms)
	else:
		draw_rect(flag, flag_color(r))
	draw_rect(flag, Color(0.25, 0.18, 0.1, 0.45 * k)) # Boue et ombre
	draw_rect(flag, Color(0, 0, 0, 0.6), false, 0.5)
	draw_set_transform(Vector2.ZERO)


## Couleur principale du drapeau : armoiries de la compagnie, couleur de la faction ennemie du
## contrat, sinon le rouge des ennemis sans seigneur (bandits, pillards).
func flag_color(r: Regiment) -> Color:
	if r.allied:
		return ALLY_COLOR
	if r.team == PLAYER:
		return Heraldry.color(arms, 0)
	if enemy_faction >= 0 and enemy_faction < CampaignState.FACTIONS.size():
		return CampaignState.FACTIONS[enemy_faction]["color"]
	return TEAM_COLORS[ENEMY]


## Couleur du bord flottant du drapeau (celle de son côté droit).
func flag_tail_color(r: Regiment) -> Color:
	if r.team == PLAYER and not r.allied and str(arms.get("field", "")) in ["per_pale", "quarterly"]:
		return Heraldry.color(arms, 1)
	return flag_color(r)


## Option « formes des camps » : petite marque sous chaque soldat visible, anneau clair pour le
## joueur, croix pour l'ennemi (distinguables sans voir le bleu et le rouge).
func draw_team_marks() -> void:
	for s in sim.soldiers:
		if not s.alive:
			continue
		var r: Regiment = s.regiment
		if r.team == ENEMY and sim.unseen(r):
			continue
		var p: Vector2 = s.pos.round() + Vector2(0, 3)
		if r.team == PLAYER:
			draw_arc(p, 2.5, 0, TAU, 8, Color(0.85, 0.92, 1, 0.9), 1.0)
		else:
			draw_line(p + Vector2(-2.5, -2.5), p + Vector2(2.5, 2.5), Color(1, 0.85, 0.6, 0.9), 1.0)
			draw_line(p + Vector2(2.5, -2.5), p + Vector2(-2.5, 2.5), Color(1, 0.85, 0.6, 0.9), 1.0)


## Couleur du camp d'un régiment (les alliés ont la leur).
func team_color(r: Regiment) -> Color:
	return ALLY_COLOR if r.allied else TEAM_COLORS[r.team]


## Étendard (repère agrandi PX fois) : à droite de la hampe, le drapeau aux armoiries de la
## compagnie ou aux couleurs de la faction ennemie ; à gauche, une plaque à la couleur du camp
## (bleu ou rouge) avec le pictogramme du type de régiment ; dessous, la barre de moral.
func draw_banner_shape(r: Regiment, base: Vector2) -> void:
	draw_line(base, base + Vector2(0, -10), WOOD, 1.0)
	var flag := Rect2(base.x, base.y - 10, 7, 5)
	if r.team == PLAYER and not r.allied:
		Heraldry.draw(self, flag, arms)
	else:
		var fc := flag_color(r)
		draw_rect(flag, fc)
		if enemy_faction >= 0:
			draw_rect(Rect2(base.x, base.y - 8, 7, 1), fc.darkened(0.45)) # Fasce sombre de la faction
	if r.routing:
		draw_rect(flag, Color(0, 0, 0, 0.5))
	draw_rect(flag, Color(0, 0, 0, 0.6), false, 0.5)
	# Plaque du camp, pictogramme du type
	var col: Color = team_color(r)
	if r.routing:
		col = col.darkened(0.5)
	draw_rect(Rect2(base.x - 8, base.y - 10, 7, 5), col)
	draw_rect(Rect2(base.x - 8, base.y - 10, 7, 5), Color(0, 0, 0, 0.6), false, 0.5)
	base.x -= 8.0 # Le pictogramme est dessiné dans la plaque
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
		"foot_knight":
			draw_rect(Rect2(base.x + 2, base.y - 9, 3, 3), ic)
			draw_rect(Rect2(base.x + 3, base.y - 10, 1, 1), ic)
		"crossbow":
			draw_line(base + Vector2(1.5, -7.5), base + Vector2(5.5, -7.5), ic, 1.0)
			draw_line(base + Vector2(3.5, -9.5), base + Vector2(3.5, -5.5), ic, 1.0)
		"horse_archer":
			draw_rect(Rect2(base.x + 1, base.y - 7, 3, 1), ic)
			draw_arc(base + Vector2(4.5, -7.5), 1.6, -PI / 2, PI / 2, 6, ic, 1.0)
	base.x += 8.0
	# Barre de moral
	var k := clampf(r.morale / r.max_morale, 0.0, 1.0)
	draw_rect(Rect2(base.x - 7, base.y + 1, 14, 2), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(base.x - 7, base.y + 1, 14 * k, 2), Color(1, 0.2, 0.15).lerp(Color(0.3, 1, 0.3), k))
	if r.selected:
		draw_rect(Rect2(base.x - 9, base.y - 11, 17, 7), Color(1, 0.95, 0.4), false, 0.7)
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
