class_name Minimap
extends RefCounted
## Mini-carte de la bataille, dessinée par le HUD (hud.gd) dans le coin en bas à gauche :
## le champ (sol et relief en réduction), la zone de déploiement, les régiments amis et les
## ennemis visibles (jamais ceux qui sont cachés en forêt) et le rectangle de la vue.
## Un clic (ou un glisser) dessus centre la caméra : voir battle_orders.gd.
## Touche reconfigurable « minimap » (N par défaut) ; état mémorisé dans GameOptions.show_minimap.

const WORLD_SIZE := BattleSim.WORLD_SIZE
const MAX_W := 200.0
const MIN_W := 112.0
const MARGIN := 8.0


## Cadre de la mini-carte : coin en bas à gauche, au-dessus des cartes des régiments
## si elles s'étendent jusque-là (vide si elle est cachée).
static func rect(hud: Hud, vs: Vector2) -> Rect2:
	var b := hud.battle
	if not b.show_minimap:
		return Rect2()
	var w := clampf(vs.x * 0.16, MIN_W, MAX_W)
	var h := w * WORLD_SIZE.y / WORLD_SIZE.x
	var y := vs.y - h - MARGIN
	if not b.player_roster().is_empty():
		var tab := hud.cards_tab_rect(vs)
		var left := tab.position.x
		if b.show_cards:
			var cards := Hud.card_rects(vs, b.player_roster().size())
			if not cards.is_empty():
				left = minf(left, cards[0].position.x)
		if left < MARGIN + w + MARGIN:
			y = tab.position.y - h - MARGIN # Pas la place à côté : au-dessus des cartes
	return Rect2(MARGIN, maxf(y, Hud.BAR_H + MARGIN), w, h)


static func to_map(p: Vector2, r: Rect2) -> Vector2:
	return r.position + p / WORLD_SIZE * r.size


## Point du monde sous un point de la mini-carte (borné au champ).
static func to_world(p: Vector2, r: Rect2) -> Vector2:
	return ((p - r.position) / r.size * WORLD_SIZE).clamp(Vector2.ZERO, WORLD_SIZE)


## Rectangle du monde vu par la caméra (d'après la transformation du canevas).
static func view_rect(b: Battle) -> Rect2:
	var inv := b.get_canvas_transform().affine_inverse()
	var vs := b.get_viewport_rect().size
	var a := inv * Vector2.ZERO
	var c := inv * vs
	return Rect2(a, c - a)


static func draw(hud: Hud, r: Rect2) -> void:
	var b := hud.battle
	var sim := b.sim
	# Cadre et sol en réduction (mêmes textures que le rendu, simplement réduites)
	hud.draw_rect(r.grow(2.0), Color(0.05, 0.04, 0.03, 0.85))
	var rd := b.renderer
	if rd != null and rd.ground_tex != null:
		hud.draw_texture_rect(rd.ground_tex, r, false, Color(0.8, 0.8, 0.75))
		if rd.terrain_tex != null:
			hud.draw_texture_rect(rd.terrain_tex, r, false, Color(0.8, 0.8, 0.75))
	else:
		hud.draw_rect(r, Color(0.3, 0.42, 0.22))
	var k := r.size.x / WORLD_SIZE.x
	for f in sim.forests:
		hud.draw_circle(to_map(f[0], r), maxf(float(f[1]) * k, 2.0), Color(0.1, 0.24, 0.1, 0.75))
	for o in sim.terrain.obstacles:
		var ob: Rect2 = o
		hud.draw_rect(Rect2(to_map(ob.position, r), (ob.size * k).max(Vector2(1, 1))), Color(0.35, 0.25, 0.16, 0.9))
	# Zone de déploiement : pleine pendant le déploiement, simple trait ensuite
	var top := sim.deploy_top()
	var dz := Rect2(to_map(Vector2(0, top), r), Vector2(r.size.x, r.end.y - to_map(Vector2(0, top), r).y))
	if sim.state == BattleSim.State.DEPLOY:
		hud.draw_rect(dz, Color(0.3, 0.5, 1.0, 0.22))
		hud.draw_rect(dz, Color(0.5, 0.7, 1.0, 0.8), false, 1.0)
	else:
		hud.draw_line(dz.position, dz.position + Vector2(dz.size.x, 0), Color(0.5, 0.7, 1.0, 0.35), 1.0)
	# Régiments : ennemis visibles, puis ceux du joueur par-dessus
	for team in [BattleSim.ENEMY, BattleSim.PLAYER]:
		for reg in sim.regiments:
			if reg.team != team or reg.is_dead() or not shows(reg):
				continue
			var p := to_map(reg.center, r)
			var s := clampf(sqrt(float(reg.alive_n)) * 0.55, 2.0, 4.5)
			var col := Hud.PLAYER_COL.lightened(0.35) if team == BattleSim.PLAYER else Hud.ENEMY_COL.lightened(0.25)
			if reg.routing:
				col.a = 0.45
			if GameOptions.team_shapes:
				Hud.draw_team_shape(hud, team, p, s, true)
			else:
				hud.draw_rect(Rect2(p - Vector2(s, s) - Vector2.ONE, Vector2(s, s) * 2.0 + Vector2(2, 2)), Color(0, 0, 0, 0.8 * col.a))
				hud.draw_rect(Rect2(p - Vector2(s, s), Vector2(s, s) * 2.0), col)
			if reg.selected:
				hud.draw_rect(Rect2(p - Vector2(s, s) - Vector2(2, 2), Vector2(s, s) * 2.0 + Vector2(4, 4)), Color(1, 0.9, 0.4), false, 1.0)
	# Rectangle de la vue
	var v := view_rect(b)
	var vr := Rect2(to_map(v.position, r), v.size * k).intersection(r)
	if vr.has_area():
		hud.draw_rect(vr, Color(1, 1, 1, 0.85), false, 1.0)
	hud.draw_rect(r, Color(0.55, 0.47, 0.3), false, 1.0)
	hud.text(r.position + Vector2(4, 12), GameOptions.key_label("minimap"), 10, Color(0.9, 0.88, 0.8, 0.7))


## Régiment visible sur la mini-carte : tous ceux du joueur, les ennemis non cachés.
static func shows(reg: Regiment) -> bool:
	return reg.team == BattleSim.PLAYER or not reg.hidden
