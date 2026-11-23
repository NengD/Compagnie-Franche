class_name BattleField
extends RefCounted
## Traces que la bataille laisse sur le champ, purement décoratives et persistantes : armes et
## boucliers tombés près des morts ou jetés par les fuyards, flèches et carreaux plantés là où ils
## sont tombés, boue piétinée sous les mêlées et sous les charges, étendards des régiments brisés
## couchés au sol. Le rendu (battle_renderer.gd) appelle update() à chaque image puis
## draw_mud() (sous les corps), draw_ground() (sur les corps) ; il dessine lui-même les étendards
## tombés (fallen) pour reprendre leurs armoiries.
##
## - Aucun signal ni tirage ajouté à la simulation : les nouveaux corps sont relevés à la fin de
##   sim.corpses, les déroutes en regardant Regiment.routing, les flèches perdues par le son « swish »
##   (émis pendant que sim.arrows contient encore la flèche). Hasard : field_rng, à part.
## - Plafonds (niveau des effets complet / réduit) : MAX_DEBRIS, MAX_STUCK, MAX_MUD ; au-delà, les
##   plus anciennes traces s'effacent. Effets « aucun » : seuls les étendards tombent.
## - Discrétion : rien n'est laissé par un régiment ennemi en embuscade.

const PX := 2.0
const MAX_DEBRIS := 700 ## Armes, boucliers et casques au sol (niveau complet)
const MAX_DEBRIS_REDUCED := 250
const MAX_STUCK := 800 ## Flèches plantées (niveau complet)
const MAX_STUCK_REDUCED := 300
const MAX_MUD := 500 ## Plaques de boue (niveau complet)
const MAX_MUD_REDUCED := 180
const MUD_CELL := 16.0 ## Côté de la case qui regroupe les piétinements d'une même plaque
const MUD_EVERY := 0.25 ## Secondes entre deux relevés des mêlées
const DROP_TIME := 0.3 ## Durée de la chute d'une arme lâchée (secondes)
const BANNER_FALL := 0.8 ## Durée de la chute d'un étendard (secondes)
const NEW_CORPSES_MAX := 200 ## Corps nouveaux examinés au plus par image

## Sortes de débris
enum { SWORD, PIKE, BOW, CROSSBOW, SHIELD, HELMET, LANCE }

const STEEL := Color(0.7, 0.72, 0.76)
const WOOD := Color(0.45, 0.3, 0.16)
const MUD_COLOR := Color(0.27, 0.2, 0.12)
const SHAFT := Color(0.34, 0.24, 0.13)
const FLETCH := Color(0.92, 0.9, 0.84)

var sim: BattleSim
var field_rng := RandomNumberGenerator.new()
## Débris : [position, sorte, angle, couleur du camp, heure de la chute (clock)]
var debris: Array = []
## Flèches plantées : [position, direction du vol (normée), carreau ?]
var stuck: Array = []
## Boue : [position, force 0..1, demi-taille] ; mud_cells : case -> plaque (même tableau)
var mud: Array = []
var mud_cells := {}
## Étendards tombés : [pied de la hampe, régiment, heure de la chute (clock), côté (-1 ou 1)]
var fallen: Array = []
var routed := {} ## Regiment -> true quand son étendard est déjà tombé (déroute ou anéantissement)
var last_corpse: Array = [] ## Dernier corps traité (référence dans sim.corpses)
var clock := 0.0
var mud_clock := 0.0
var level := 2 ## Niveau des effets (2 complets, 1 réduits, 0 aucun), relu à chaque image


func _init(s: BattleSim) -> void:
	sim = s
	field_rng.randomize()
	sim.sound_played.connect(on_sound)


static func current_level() -> int:
	match GameOptions.effects:
		"none":
			return 0
		"reduced":
			return 1
	return 2


func cap(full: int, reduced: int) -> int:
	return full if level == 2 else reduced


# ---------------------------------------------------------------- Événements

## Flèche perdue : elle se plante dans le sol (pas dans l'eau), penchée dans le sens du vol.
func on_sound(sound: String, at: Vector2) -> void:
	if sound != "swish" or level == 0 or sim.terrain.is_river(at):
		return
	var dir := Vector2.DOWN
	var bolt := false
	for a in sim.arrows: # La flèche est encore dans la liste au moment du son
		if a["to"] == at:
			var from: Vector2 = a["from"]
			if from.distance_squared_to(at) > 1.0:
				dir = (at - from).normalized()
			bolt = float(a.get("pierce", 0.0)) > 0.0
			break
	stuck.append([at.round(), dir, bolt])
	var m := cap(MAX_STUCK, MAX_STUCK_REDUCED)
	if stuck.size() > m:
		stuck = stuck.slice(stuck.size() - m)


## Arme lâchée en p par un soldat du type donné (chute de la main jusqu'au sol).
func drop(p: Vector2, type: String, team_col: Color, chance: float) -> void:
	if level == 0 or field_rng.randf() >= chance:
		return
	var kind := SWORD
	match type:
		"spear":
			kind = PIKE
		"archer", "horse_archer":
			kind = BOW
		"crossbow":
			kind = CROSSBOW
		"cavalry":
			kind = LANCE if field_rng.randf() < 0.6 else SHIELD
		"foot_knight":
			kind = HELMET if field_rng.randf() < 0.3 else SWORD
		_:
			kind = SHIELD if field_rng.randf() < 0.35 else SWORD
	var off := Vector2(field_rng.randf_range(-7, 7), field_rng.randf_range(-3, 4))
	debris.append([(p + off).round(), kind, field_rng.randf_range(-PI, PI), team_col, clock])
	var m := cap(MAX_DEBRIS, MAX_DEBRIS_REDUCED)
	if debris.size() > m:
		debris = debris.slice(debris.size() - m)


## Piétinement en p : renforce la plaque de la case, ou en crée une (les plus vieilles s'effacent).
func trample(p: Vector2, amount: float) -> void:
	if level == 0:
		return
	var cell := Vector2i(floori(p.x / MUD_CELL), floori(p.y / MUD_CELL))
	var m: Variant = mud_cells.get(cell)
	if m != null:
		m[1] = minf(float(m[1]) + amount, 1.0)
		return
	var patch := [((Vector2(cell) + Vector2(0.5, 0.5)) * MUD_CELL + Vector2(field_rng.randf_range(-3, 3), field_rng.randf_range(-3, 3))).round(),
		amount, roundf(field_rng.randf_range(4, 7)) * PX * 0.5, cell]
	mud.append(patch)
	mud_cells[cell] = patch
	var mx := cap(MAX_MUD, MAX_MUD_REDUCED)
	while mud.size() > mx:
		var old: Array = mud.pop_front()
		mud_cells.erase(old[3])


# ---------------------------------------------------------------- Mise à jour

## Avance d'une image (delta en temps réel) : nouveaux morts, déroutes, piétinements.
func update(delta: float) -> void:
	clock += delta
	level = current_level()
	if level == 0:
		debris.clear()
		stuck.clear()
		mud.clear()
		mud_cells.clear()
	scan_corpses()
	scan_routs()
	if level > 0:
		mud_clock -= delta
		if mud_clock <= 0.0:
			mud_clock = MUD_EVERY
			scan_melees()


## Corps apparus depuis la dernière image (à la fin de sim.corpses) : chacun lâche son arme.
func scan_corpses() -> void:
	var cs := sim.corpses
	if cs.is_empty() or is_same(cs.back(), last_corpse):
		return
	var fresh: Array = []
	var i := cs.size() - 1
	while i >= 0 and not is_same(cs[i], last_corpse) and fresh.size() < NEW_CORPSES_MAX:
		fresh.append(cs[i])
		i -= 1
	last_corpse = cs.back()
	for k in range(fresh.size() - 1, -1, -1):
		var c: Array = fresh[k]
		var r: Regiment = c[5] if c.size() > 5 and c[5] is Regiment else null
		if r != null and sim.is_secret(r):
			continue
		var col: Color = BattleRenderer.TEAM_COLORS[int(c[1])]
		drop(c[0], str(c[2]), col, 0.75)
		if level > 0:
			trample(c[0], 0.25)


## Régiment qui fuit ou vient d'être anéanti : son étendard tombe, ses fuyards jettent leurs armes.
## S'il se rallie, il relève un étendard (l'ancien reste au sol).
func scan_routs() -> void:
	for r in sim.regiments:
		if routed.has(r):
			if not r.routing and not r.is_dead():
				routed.erase(r) # Rallié
			continue
		if not (r.routing or r.is_dead()) or sim.is_secret(r):
			continue
		if r.soldiers.is_empty():
			continue
		routed[r] = true
		var at := r.center
		if not r.routing:
			# Anéanti : l'étendard tombe là où est mort le dernier homme
			for i in range(sim.corpses.size() - 1, maxi(sim.corpses.size() - 40, 0) - 1, -1):
				var c: Array = sim.corpses[i]
				if c.size() > 5 and c[5] == r:
					at = c[0]
					break
		fallen.append([at.round() + Vector2(0, 6), r, clock, 1 if field_rng.randf() < 0.5 else -1])
		if r.routing:
			for s in r.soldiers:
				if s.alive:
					drop(s.pos, r.type, BattleRenderer.TEAM_COLORS[r.team], 0.8)


## Mêlées et charges : quelques soldats au contact piétinent le sol à chaque relevé.
func scan_melees() -> void:
	for r in sim.regiments:
		if r.is_dead() or sim.is_secret(r):
			continue
		var charging: bool = r.stats["mounted"] and r.running
		if not r.engaged and not charging:
			continue
		var n := r.soldiers.size()
		if n == 0:
			continue
		for k in 3:
			var s: Soldier = r.soldiers[field_rng.randi() % n]
			if not s.alive or sim.terrain.is_river(s.pos):
				continue
			if s.foe != null:
				trample(s.pos + Vector2(field_rng.randf_range(-4, 4), field_rng.randf_range(-2, 3)), 0.12)
			elif charging and s.moving:
				trample(s.pos, 0.05) # Sabots : une trace légère


# ---------------------------------------------------------------- Dessin

## Boue piétinée (sous les corps) : deux pavés sombres, plus marqués à mesure qu'on s'y bat.
func draw_mud(c: CanvasItem, view: Rect2) -> void:
	if level == 0:
		return
	var cull := view.has_area()
	for m in mud:
		var p: Vector2 = m[0]
		if cull and not view.has_point(p):
			continue
		var k: float = m[1]
		var hw: float = m[2]
		var col := Color(MUD_COLOR, 0.12 + 0.3 * k)
		c.draw_rect(Rect2(p.x - hw, p.y - hw * 0.4, hw * 2.0, hw * 0.8), col)
		c.draw_rect(Rect2(p.x - hw * 0.6, p.y - hw * 0.7, hw * 1.2, hw * 1.4), col)
		if k > 0.5: # Ornières : traces de pas plus sombres
			c.draw_rect(Rect2(p.x - hw * 0.5, p.y, PX, 1), Color(0.16, 0.11, 0.06, 0.45 * k))
			c.draw_rect(Rect2(p.x + hw * 0.3, p.y - hw * 0.3, PX, 1), Color(0.16, 0.11, 0.06, 0.45 * k))


## Débris et flèches plantées (au-dessus des corps, sous les soldats).
func draw_ground(c: CanvasItem, view: Rect2) -> void:
	if level == 0:
		return
	var cull := view.has_area()
	for d in debris:
		var p: Vector2 = d[0]
		if cull and not view.has_point(p):
			continue
		draw_debris(c, d)
	for a in stuck:
		var p: Vector2 = a[0]
		if cull and not view.has_point(p):
			continue
		draw_stuck(c, p, a[1], a[2])


## Une arme au sol (lâchée il y a moins de DROP_TIME : elle tombe en tournant).
func draw_debris(c: CanvasItem, d: Array) -> void:
	var p: Vector2 = d[0]
	var angle: float = d[2]
	var k := clampf((clock - float(d[4])) / DROP_TIME, 0.0, 1.0)
	if k < 1.0:
		p.y -= 8.0 * (1.0 - k * k)
		angle += (1.0 - k) * 2.5
	var team: Color = d[3]
	var dir := Vector2.from_angle(angle)
	var flat := Vector2(dir.x, dir.y * 0.5) # Couché au sol : vu en raccourci
	match int(d[1]):
		SWORD:
			c.draw_line(p - flat * 4.0, p + flat * 4.0, STEEL, 1.0)
			c.draw_rect(Rect2(p - flat * 2.5 - Vector2(1, 1), Vector2(2, 2)), Color(0.4, 0.3, 0.2)) # Garde
		PIKE:
			c.draw_line(p - flat * 13.0, p + flat * 13.0, WOOD, 1.0)
			c.draw_line(p + flat * 13.0, p + flat * 16.0, STEEL, 1.0)
		LANCE:
			c.draw_line(p - flat * 11.0, p + flat * 11.0, Color(0.62, 0.5, 0.32), 1.5)
			c.draw_line(p + flat * 11.0, p + flat * 14.0, STEEL, 1.0)
			c.draw_rect(Rect2(p + flat * 8.0 - Vector2(1, 1), Vector2(3, 2)), team.darkened(0.2)) # Pennon
		BOW:
			var n := Vector2(-flat.y, flat.x) * 2.0
			c.draw_polyline(PackedVector2Array([p - flat * 6.0, p + n, p + flat * 6.0]), WOOD, 1.0)
			c.draw_line(p - flat * 6.0, p + flat * 6.0, Color(0.85, 0.85, 0.78, 0.7), 1.0)
		CROSSBOW:
			c.draw_line(p - flat * 4.0, p + flat * 4.0, WOOD, 2.0)
			var n2 := Vector2(-flat.y, flat.x)
			c.draw_line(p + flat * 4.0 - n2 * 4.0, p + flat * 4.0 + n2 * 4.0, STEEL, 1.0)
		SHIELD:
			var q := p.round()
			c.draw_rect(Rect2(q.x - 3, q.y - 2, 6, 4), team.darkened(0.35))
			c.draw_rect(Rect2(q.x - 3, q.y - 2, 6, 4), Color(0.1, 0.08, 0.06, 0.8), false, 1.0)
			c.draw_rect(Rect2(q.x - 1, q.y - 1, 2, 1), STEEL)
		HELMET:
			var q2 := p.round()
			c.draw_rect(Rect2(q2.x - 2, q2.y - 2, 4, 3), STEEL.lightened(0.15))
			c.draw_rect(Rect2(q2.x - 2, q2.y, 4, 1), Color(0.3, 0.3, 0.32))


## Flèche plantée : la pointe dans le sol, la hampe dressée vers le tireur, l'empennage clair.
static func draw_stuck(c: CanvasItem, p: Vector2, dir: Vector2, bolt: bool) -> void:
	var back := Vector2(-dir.x * 0.6, -3.5) if not bolt else Vector2(-dir.x * 0.5, -2.5)
	var tail := p + back * (1.6 if not bolt else 1.3)
	c.draw_line(p, tail, SHAFT, 1.0)
	c.draw_rect(Rect2(tail.round() - Vector2(0, 1), Vector2(1, 2)), FLETCH if not bolt else Color(0.6, 0.5, 0.35))
