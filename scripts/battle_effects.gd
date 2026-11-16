class_name BattleEffects
extends RefCounted
## Effets visuels de la bataille, purement décoratifs : sang et étincelles des coups, mottes de
## terre des flèches perdues, éclat des charges de cavalerie, traînées des flèches, fumée des
## cheminées du village, éclaboussures dans l'eau, pluie au sol (impacts, flaques) et queues
## d'étendards qui flottent au vent.
##
## - Temps réel : update() reçoit le delta de l'image (comme les repères d'ordres du rendu).
## - Hasard : un générateur à part (fx_rng). Le rng de la simulation n'est jamais tiré, donc les
##   graines fixes (tests, banc d'équilibrage) donnent exactement la même bataille.
## - Niveau : GameOptions.effects (« full », « reduced », « none »), relu à chaque image.
## - Particules : des tableaux dans parts, plafonnées (MAX_PARTS), comme la poussière de BattleSim.
## - Discrétion : la simulation n'émet ni coup ni son pour un ennemi en embuscade, et les
##   éclaboussures ignorent les régiments ennemis cachés : aucun effet ne trahit une embuscade.
##
## Le rendu appelle draw_ground() (sous les soldats), draw_air() (au-dessus) et
## draw_banner_tail() (dans le repère agrandi de chaque étendard).

const PX := 2.0 ## Taille d'un « pixel » des dessins en code
const MAX_PARTS := 500 ## Particules au maximum (niveau complet)
const MAX_PARTS_REDUCED := 180 ## Particules au maximum (niveau réduit)
const MAX_STAINS := 160 ## Taches de sang au sol au maximum
const STAIN_LIFE := 12.0 ## Durée d'une tache de sang (secondes)
const GRAVITY := 260.0
const WIND := Vector2(7.0, 0.0) ## Vent léger vers l'est : fumée, étendards
const PUDDLES := 160 ## Flaques réparties sur le champ de bataille (pluie)
const WET_TIME := 15.0 ## Secondes de pluie pour que les flaques soient pleines
const DRY_TIME := 40.0 ## Secondes de temps clair pour qu'elles disparaissent

## Sortes de particules
enum { BLOOD, SPARK, DIRT, SMOKE, DROP, RING, FLASH }

const BLOOD_COLORS: Array[Color] = [Color(0.55, 0.06, 0.05), Color(0.42, 0.04, 0.04), Color(0.66, 0.1, 0.07)]
const SPARK_COLOR := Color(1.0, 0.93, 0.6)
const DIRT_COLOR := Color(0.5, 0.4, 0.27)
const SMOKE_COLOR := Color(0.6, 0.59, 0.57)
const WATER_COLOR := Color(0.82, 0.9, 1.0)
const PUDDLE_COLOR := Color(0.3, 0.38, 0.48)

var sim: BattleSim
var fx_rng := RandomNumberGenerator.new() ## Hasard des effets, séparé de celui de la simulation
## Particules : [position, vitesse, vie restante, vie totale, taille, couleur, sorte, sol (y)]
var parts: Array = []
var stains: Array = [] ## Taches de sang : [position, vie restante, taille]
var puddles: Array = [] ## Flaques : [centre, demi-largeur]
var wet := 0.0 ## 0 = sol sec, 1 = flaques pleines
var smoke_clock: Array[float] = [] ## Une horloge par maison
var rain_clock := 0.0
var clock := 0.0 ## Temps réel écoulé (étendards)
var splash_phase := 0 ## Moitié des soldats examinée à cette image (éclaboussures)
var view := Rect2() ## Partie du monde visible, mise à jour à chaque image


func _init(s: BattleSim) -> void:
	sim = s
	fx_rng.randomize()
	sim.hit.connect(on_hit)
	sim.sound_played.connect(on_sound)
	sim.impact.connect(on_impact)


## Niveau courant : 2 = complets, 1 = réduits, 0 = aucun.
func level() -> int:
	match GameOptions.effects:
		"none":
			return 0
		"reduced":
			return 1
	return 2


## Nombre de particules autorisé au niveau courant.
func cap() -> int:
	return MAX_PARTS if level() == 2 else MAX_PARTS_REDUCED


## Fréquence relative des effets (1 au niveau complet).
func rate() -> float:
	return 1.0 if level() == 2 else 0.4


func add(p: Vector2, v: Vector2, life: float, size: float, col: Color, kind: int, floor_y := INF) -> void:
	if parts.size() >= cap():
		return
	parts.append([p, v, life, life, size, col, kind, floor_y])


## Tire n événements « en moyenne » (n peut être fractionnaire : 0,4 = une fois sur 2,5).
func roll(n: float) -> int:
	var k := int(n)
	if fx_rng.randf() < n - k:
		k += 1
	return k


# ---------------------------------------------------------------- Événements de la simulation

## Coup reçu en at, porté depuis from (from == at : flèche, direction au hasard).
func on_hit(at: Vector2, from: Vector2) -> void:
	if level() == 0:
		return
	var dir := (at - from).normalized() if at.distance_squared_to(from) > 1.0 else Vector2.from_angle(fx_rng.randf() * TAU)
	for i in roll(2.5 * rate()):
		spill_blood(at, dir)


## Gouttes de sang projetées depuis le torse, qui tachent le sol en retombant.
func spill_blood(at: Vector2, dir: Vector2) -> void:
	var v := dir * fx_rng.randf_range(18.0, 45.0) + Vector2(fx_rng.randf_range(-14, 14), fx_rng.randf_range(-70, -30))
	var col: Color = BLOOD_COLORS[fx_rng.randi() % BLOOD_COLORS.size()]
	add(at + Vector2(fx_rng.randf_range(-2, 2), -7), v, 1.2, PX if fx_rng.randf() < 0.7 else PX * 0.5, col, BLOOD, at.y + fx_rng.randf_range(-3, 3))


func on_sound(sound: String, at: Vector2) -> void:
	if level() == 0:
		return
	match sound:
		"clash": # Lame sur armure : une ou deux étincelles
			for i in roll(1.5 * rate()):
				var v := Vector2(fx_rng.randf_range(-50, 50), fx_rng.randf_range(-80, -30))
				add(at + Vector2(0, -8), v, 0.25, PX * 0.5, SPARK_COLOR, SPARK, at.y)
		"death": # Une flaque de sang sous le corps
			if fx_rng.randf() < rate():
				add_stain(at + Vector2(fx_rng.randf_range(-3, 3), 1), PX * 2.0)
		"swish": # Flèche perdue : motte de terre, ou gerbe d'eau dans la rivière
			if sim.terrain.is_river(at):
				splash(at, 1.0)
			else:
				for i in roll(2.0 * rate()):
					var v := Vector2(fx_rng.randf_range(-20, 20), fx_rng.randf_range(-45, -15))
					add(at, v, 0.5, PX, DIRT_COLOR, DIRT, at.y + 1.0)


## Choc d'une charge de cavalerie : éclat blanc, étincelles en étoile et poussière qui s'écarte.
func on_impact(at: Vector2, amount: float) -> void:
	if level() == 0:
		return
	var torso := at + Vector2(0, -8)
	add(torso, Vector2.ZERO, 0.16, PX * (3.0 + amount * 20.0), Color(1, 1, 0.9), FLASH)
	for i in roll(5.0 * rate()):
		var v := Vector2.from_angle(fx_rng.randf() * TAU) * fx_rng.randf_range(50, 110) + Vector2(0, -30)
		add(torso, v, 0.3, PX * 0.5, SPARK_COLOR, SPARK, at.y)
	for i in roll(4.0 * rate()):
		var v := Vector2(fx_rng.randf_range(-1, 1), fx_rng.randf_range(-0.3, 0.1)).normalized() * fx_rng.randf_range(20, 40)
		add(at, v, 0.7, PX * 1.5, Color(0.7, 0.6, 0.44, 0.6), DIRT)


func add_stain(p: Vector2, size: float) -> void:
	stains.append([p, STAIN_LIFE, size])
	if stains.size() > MAX_STAINS:
		stains.pop_front()


## Gerbe d'eau et rond dans l'eau en p (force 1 = pas d'un fantassin).
func splash(p: Vector2, force: float) -> void:
	for i in roll((1.5 + force) * rate() + 0.5):
		var v := Vector2(fx_rng.randf_range(-22, 22), fx_rng.randf_range(-70, -35) * force)
		add(p + Vector2(fx_rng.randf_range(-3, 3), 0), v, 0.6, PX * 0.5 if fx_rng.randf() < 0.5 else PX, WATER_COLOR, DROP, p.y + 1.0)
	add(p + Vector2(0, 1), Vector2.ZERO, 0.5, 3.0 * force, Color(0.85, 0.93, 1.0, 0.7), RING)


# ---------------------------------------------------------------- Mise à jour

## Avance les effets de delta secondes (temps réel). canvas : le nœud de rendu (pour la vue).
func update(delta: float, canvas: CanvasItem) -> void:
	clock += delta
	view = canvas.get_canvas_transform().affine_inverse() * canvas.get_viewport_rect()
	view = view.grow(40.0)
	update_wetness(delta)
	if level() == 0:
		parts.clear()
		stains.clear()
		return
	update_parts(delta)
	for st in stains:
		st[1] -= delta
	if not stains.is_empty() and stains[0][1] <= 0.0:
		stains = stains.filter(func(st): return st[1] > 0.0)
	emit_smoke(delta)
	emit_splashes(delta)
	emit_rain(delta)


func update_parts(delta: float) -> void:
	var keep := []
	for d in parts:
		d[2] -= delta
		if d[2] <= 0.0:
			continue
		var kind: int = d[6]
		match kind:
			BLOOD, SPARK, DROP:
				d[1].y += GRAVITY * delta
			DIRT:
				d[1].y += GRAVITY * 0.5 * delta
				d[1] *= 1.0 - minf(delta * 2.0, 1.0)
			SMOKE:
				d[1] = d[1].lerp(WIND + Vector2(0, -12), minf(delta * 0.6, 1.0))
		d[0] += d[1] * delta
		var floor_y: float = d[7]
		if d[0].y >= floor_y and d[1].y > 0.0:
			if kind == BLOOD:
				add_stain(Vector2(d[0].x, floor_y), d[4])
			continue
		keep.append(d)
	parts = keep


## Fumée qui monte des cheminées : une horloge par maison, des bouffées grises qui grossissent.
func emit_smoke(delta: float) -> void:
	var houses := sim.terrain.houses
	if smoke_clock.size() != houses.size():
		smoke_clock.resize(houses.size())
		for i in houses.size():
			smoke_clock[i] = fx_rng.randf() # Les cheminées ne fument pas toutes en même temps
	var every := 0.45 / rate()
	for i in houses.size():
		smoke_clock[i] -= delta
		if smoke_clock[i] > 0.0:
			continue
		smoke_clock[i] = every * fx_rng.randf_range(0.7, 1.3)
		var h: Rect2 = houses[i]
		var top := Vector2(h.end.x - 11.0, h.position.y - 27.0) # Haut de la cheminée (voir draw_house)
		var v := Vector2(fx_rng.randf_range(-3, 3), fx_rng.randf_range(-20, -14))
		add(top + Vector2(fx_rng.randf_range(-1, 1), 0), v, fx_rng.randf_range(2.6, 3.6), PX * 1.5, SMOKE_COLOR, SMOKE)


## Éclaboussures sous les pas dans l'eau (gués et rivière). La moitié des soldats par image.
func emit_splashes(delta: float) -> void:
	if not sim.terrain.has_river():
		return
	splash_phase = 1 - splash_phase
	var chance := delta * 2.0 * 2.5 * rate() # 2,5 gerbes par seconde et par soldat qui patauge
	var soldiers := sim.soldiers
	for i in range(splash_phase, soldiers.size(), 2):
		var s: Soldier = soldiers[i]
		if not s.alive or not s.moving:
			continue
		var r := s.regiment
		if r.team == BattleSim.ENEMY and r.hidden:
			continue
		if not view.has_point(s.pos) or not sim.terrain.is_river(s.pos):
			continue
		var mounted: bool = r.stats["mounted"]
		if fx_rng.randf() < chance * (2.0 if mounted else 1.0):
			splash(s.pos, 1.4 if mounted else 1.0)


## Pluie au sol : les flaques se remplissent, les gouttes rebondissent (dans la vue seulement).
func update_wetness(delta: float) -> void:
	if sim.raining:
		wet = minf(wet + delta / WET_TIME, 1.0)
	else:
		wet = maxf(wet - delta / DRY_TIME, 0.0)


func emit_rain(delta: float) -> void:
	if not sim.raining:
		return
	if puddles.is_empty():
		make_puddles()
	# Impacts proportionnels à la surface vue (environ 120 par seconde sur un écran de 1280×720)
	var area := clampf(view.get_area() / (1360.0 * 800.0), 0.2, 3.0)
	rain_clock += delta * 120.0 * rate() * area
	var visible: Array = puddles.filter(func(pd): return view.has_point(pd[0])) if wet > 0.3 else []
	while rain_clock >= 1.0:
		rain_clock -= 1.0
		if parts.size() > cap() * 0.5:
			continue # La pluie laisse toujours de la place aux autres effets
		var p: Vector2
		var big := false
		if not visible.is_empty() and fx_rng.randf() < 0.3:
			var pd: Array = visible[fx_rng.randi() % visible.size()]
			var hw: float = pd[1]
			p = pd[0] + Vector2(fx_rng.randf_range(-hw, hw) * 0.7, fx_rng.randf_range(-hw, hw) * 0.25)
			big = true # Rond dans la flaque
		else:
			p = Vector2(fx_rng.randf_range(view.position.x, view.end.x), fx_rng.randf_range(view.position.y, view.end.y))
		if big or sim.terrain.is_river(p):
			add(p, Vector2.ZERO, 0.45, 2.5, Color(0.8, 0.88, 1.0, 0.55), RING)
		else:
			add(p, Vector2(0, -18), 0.12, PX * 0.5, Color(0.8, 0.86, 1.0, 0.6), DROP, p.y + 0.5)


## Flaques placées au hasard (hors rivière et maisons), une fois pour toute la bataille.
func make_puddles() -> void:
	var tries := 0
	while puddles.size() < PUDDLES and tries < 400:
		tries += 1
		var p := Vector2(fx_rng.randf_range(40, BattleSim.WORLD_SIZE.x - 40), fx_rng.randf_range(40, BattleSim.WORLD_SIZE.y - 40))
		if sim.terrain.is_river(p, 12.0) or sim.is_in_forest(p):
			continue
		var in_house := false
		for h in sim.terrain.houses:
			if h.grow(16.0).has_point(p):
				in_house = true
				break
		if not in_house:
			puddles.append([(p / PX).round() * PX, roundf(fx_rng.randf_range(4, 9)) * PX])


# ---------------------------------------------------------------- Dessin

## Couche du sol (sous les soldats) : flaques, taches de sang, ronds dans l'eau.
func draw_ground(c: CanvasItem) -> void:
	if level() == 0:
		return
	if wet > 0.02:
		for pd in puddles:
			draw_puddle(c, pd[0], pd[1])
	for st in stains:
		var p: Vector2 = st[0]
		if not view.has_point(p):
			continue
		var a := clampf(st[1] / 3.0, 0.0, 1.0) * 0.7
		var sz: float = st[2]
		var q := (p / PX).round() * PX
		c.draw_rect(Rect2(q - Vector2(sz * 0.5, sz * 0.25), Vector2(sz, maxf(sz * 0.5, 1.0))), Color(0.38, 0.04, 0.03, a))
	for d in parts:
		if d[6] == RING:
			draw_part(c, d)


## Couche de l'air (au-dessus des soldats et des maisons) : traînées des flèches et particules.
func draw_air(c: CanvasItem) -> void:
	if level() == 0:
		return
	draw_arrow_trails(c)
	for d in parts:
		if d[6] != RING:
			draw_part(c, d)


func draw_part(c: CanvasItem, d: Array) -> void:
	var p: Vector2 = d[0]
	if not view.has_point(p):
		return
	var k: float = d[2] / d[3] # 1 = vient d'apparaître
	var sz: float = d[4]
	var col: Color = d[5]
	match int(d[6]):
		SMOKE:
			sz = roundf(sz * (1.0 + (1.0 - k) * 2.5) / PX) * PX
			col.a = 0.55 * minf(k * 1.5, 1.0) * minf((1.0 - k) * 8.0 + 0.3, 1.0)
		RING:
			draw_ring(c, p, sz * (1.0 + (1.0 - k) * 1.5), Color(col, col.a * k))
			return
		FLASH:
			var r := sz * k
			var q := p.round()
			c.draw_rect(Rect2(q.x - r, q.y - PX * 0.5, r * 2.0, PX), Color(col, k))
			c.draw_rect(Rect2(q.x - PX * 0.5, q.y - r, PX, r * 2.0), Color(col, k))
			c.draw_rect(Rect2(q - Vector2(r, r) * 0.35, Vector2(r, r) * 0.7), Color(col, 0.8 * k))
			return
		DIRT, SPARK:
			col.a *= minf(k * 2.0, 1.0)
		_:
			col.a *= minf(k * 3.0, 1.0)
	var q := (p / PX).round() * PX # Calé sur la grille des pixels
	c.draw_rect(Rect2(q - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), col)


## Rond aplati (vu de trois quarts) en pixels : quatre traits d'un pixel.
func draw_ring(c: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	var q := p.round()
	var rx := roundf(r)
	var ry := maxf(roundf(r * 0.45), 1.0)
	c.draw_rect(Rect2(q.x - rx * 0.6, q.y - ry, rx * 1.2, 1), col)
	c.draw_rect(Rect2(q.x - rx * 0.6, q.y + ry, rx * 1.2, 1), col)
	c.draw_rect(Rect2(q.x - rx, q.y - ry * 0.5, 1, ry), col)
	c.draw_rect(Rect2(q.x + rx - 1, q.y - ry * 0.5, 1, ry), col)


## Flaque en pixels : deux rectangles superposés et un reflet, plus nets à mesure qu'il pleut.
func draw_puddle(c: CanvasItem, p: Vector2, hw: float) -> void:
	if not view.has_point(p):
		return
	var a := 0.4 * wet
	var hh := maxf(roundf(hw * 0.4 / PX) * PX, PX)
	c.draw_rect(Rect2(p.x - hw, p.y - hh * 0.5, hw * 2.0, hh), Color(PUDDLE_COLOR, a))
	c.draw_rect(Rect2(p.x - hw + PX * 2, p.y - hh * 0.5 - PX, hw * 2.0 - PX * 4, hh + PX * 2), Color(PUDDLE_COLOR, a))
	c.draw_rect(Rect2(p.x - hw * 0.4, p.y - hh * 0.5, PX * 2, 1), Color(0.75, 0.82, 0.95, a * 0.8))


## Traînée pâle derrière chaque flèche en vol (le long de sa courbe).
func draw_arrow_trails(c: CanvasItem) -> void:
	var segs := 3 if level() == 2 else 1
	for a in sim.arrows:
		var dur: float = a["dur"]
		var k: float = a["t"] / dur
		var prev := arrow_point(a, k)
		if not view.has_point(prev):
			continue
		for j in segs:
			var kk := k - (j + 1) * 0.045
			if kk <= 0.0:
				break
			var p := arrow_point(a, kk)
			c.draw_line(prev, p, Color(0.95, 0.95, 0.9, 0.28 * (1.0 - float(j) / segs)), 1.0)
			prev = p


## Position d'une flèche à la fraction k de son vol (même courbe que BattleRenderer.draw_arrows).
static func arrow_point(a: Dictionary, k: float) -> Vector2:
	var from: Vector2 = a["from"]
	var to: Vector2 = a["to"]
	var h: float = a["h"]
	return from.lerp(to, k) - Vector2(0, h * 4.0 * k * (1.0 - k))


## Queue de l'étendard qui flotte au vent, dessinée dans le repère agrandi de draw_banner_shape
## (le drapeau occupe x 0..7, y -10..-5). col : la couleur du drapeau.
func draw_banner_tail(c: CanvasItem, r: Regiment, col: Color) -> void:
	if level() == 0:
		return
	var phase := float(r.get_instance_id() % 97) * 0.37
	var speed := 9.0 if r.routing else 5.0
	for i in 4:
		var h := 4.0 - i
		var wave := roundf(sin(clock * speed - i * 1.1 + phase) * (0.5 + i * 0.25))
		var shade := col.darkened(0.25) if sin(clock * speed - i * 1.1 + phase + 0.8) < 0.0 else col
		c.draw_rect(Rect2(7 + i, -10 + (5.0 - h) * 0.5 + wave, 1, h), shade)
	# Pli qui court sur le drapeau
	var fold := int(fposmod(clock * speed * 0.6 + phase, 7.0))
	c.draw_rect(Rect2(fold, -10, 1, 5), Color(0, 0, 0, 0.12))
