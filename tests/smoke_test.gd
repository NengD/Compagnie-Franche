extends SceneTree
## Test de fumée headless : joue une bataille accélérée et vérifie qu'elle se termine sans erreur.
##
## Lancer :  godot --headless --path . -s tests/smoke_test.gd
## Options (après « -- ») :  --seed=N   graine du terrain et des jets de dés (défaut 12345)
##                           --max=S    durée simulée maximale en secondes (défaut 600)
##                           --terrain=T  terrain imposé : plain, forest, hills, river, village, siege
##                                        (défaut : plain ; « random » = tiré au sort comme en escarmouche)
## Code de sortie : 0 si tout va bien, 1 sinon.

const TestPlayer := preload("res://tests/test_player.gd")
const STEP := 0.05 ## Pas de simulation (identique au maximum utilisé par le jeu)
const STEPS_PER_FRAME := 40 ## 2 s de bataille simulées par image
const MIN_DURATION := 60.0 ## En dessous, la bataille est jugée beaucoup trop rapide


## Compte les erreurs émises par le moteur ou les scripts pendant le test.
class ErrorCounter extends Logger:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var mutex := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		var msg := "%s:%d (%s) %s" % [file, line, function, rationale if rationale != "" else code]
		mutex.lock()
		if error_type == Logger.ERROR_TYPE_WARNING:
			warnings.append(msg)
		else:
			errors.append(msg)
		mutex.unlock()


var counter := ErrorCounter.new()
var battle: Node
var max_time := 600.0
var player := TestPlayer.new("tactical") ## Joueur simulé (voir tests/test_player.gd)
var frames := 0
var finished := false
var terrain_kind := "plain"
var max_dust := 0 ## Plus grand nombre de particules de poussière vu pendant la bataille


func _initialize() -> void:
	OS.add_logger(counter)
	var seed_value := 12345
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			seed_value = int(a.trim_prefix("--seed="))
		elif a.begins_with("--max="):
			max_time = float(a.trim_prefix("--max="))
		elif a.begins_with("--terrain="):
			terrain_kind = a.trim_prefix("--terrain=")
	if terrain_kind != "random" and not terrain_kind in Terrain.KINDS:
		_finish(["terrain inconnu : %s (choix : %s)" % [terrain_kind, ", ".join(Terrain.KINDS)]])
		return

	var scene: PackedScene = load("res://scenes/main.tscn")
	if scene == null:
		_finish(["impossible de charger res://scenes/main.tscn"])
		return
	battle = scene.instantiate()
	battle.set("seed_override", seed_value)
	battle.set("terrain_override", "" if terrain_kind == "random" else terrain_kind)
	root.add_child(battle)
	print("Smoke test : graine %d, terrain %s, durée simulée max %d s" % [seed_value, terrain_kind, int(max_time)])


func _process(_delta: float) -> bool:
	if finished:
		return true
	frames += 1
	if frames == 1:
		# _ready() de la bataille a maintenant été appelé : on teste le déploiement, puis on lance.
		# Les ordres se testent sur terrain neutre ; le terrain est vérifié à part.
		battle.terrain.active = false
		var line_fails := _test_line_orders()
		if not line_fails.is_empty() or not counter.errors.is_empty():
			line_fails.append("échec pendant le test des lignes de front")
			_finish(line_fails)
			return true
		print("Lignes de front : OK")
		var form_fails := _test_formations()
		if not form_fails.is_empty() or not counter.errors.is_empty():
			form_fails.append("échec pendant le test des formations")
			_finish(form_fails)
			return true
		print("Formations : OK")
		var run_fails := _test_running()
		if not run_fails.is_empty() or not counter.errors.is_empty():
			run_fails.append("échec pendant le test de la course")
			_finish(run_fails)
			return true
		print("Course et endurance : OK")
		var order_fails := _test_orders()
		if not order_fails.is_empty() or not counter.errors.is_empty():
			order_fails.append("échec pendant le test des ordres (tenir, tir, groupes)")
			_finish(order_fails)
			return true
		print("Ordres (tenir la position, cesser le tir, groupes) : OK")
		var asset_fails := _check_assets()
		if not asset_fails.is_empty():
			_finish(asset_fails)
			return true
		battle.terrain.active = true
		var terrain_fails := _test_terrain()
		if not terrain_fails.is_empty() or not counter.errors.is_empty():
			terrain_fails.append("échec pendant le test du terrain")
			_finish(terrain_fails)
			return true
		print("Terrain (%s) : OK" % battle.terrain.kind)
		battle.start_battle()
		return false
	for i in STEPS_PER_FRAME:
		if battle.state != battle.State.BATTLE:
			break
		player.update(battle)
		battle.simulate(STEP)
		max_dust = maxi(max_dust, battle.dust.size())
	if battle.state != battle.State.BATTLE or battle.battle_time >= max_time:
		# Deux images de plus pour laisser passer _process et _draw sur l'état final
		if frames > 2:
			_finish(_check())
			return true
	return false


## Vérifie l'ordre « ligne de front » (clic droit glissé), pendant le déploiement.
func _test_line_orders() -> Array[String]:
	var fails: Array[String] = []
	var mine: Array[Regiment] = battle.player_regiments()
	var sel: Array[Regiment] = []
	for r in mine:
		if r.type == "spear" or r.type == "men_at_arms":
			sel.append(r)
	var spear: Regiment = sel[0]

	# Un seul régiment : ligne longue = front large, ligne courte = front étroit
	var long_l: Array[Dictionary] = battle.line_layout([spear] as Array[Regiment], Vector2(1200, 1520), Vector2(1480, 1520))
	var short_l: Array[Dictionary] = battle.line_layout([spear] as Array[Regiment], Vector2(1200, 1520), Vector2(1230, 1520))
	var huge_l: Array[Dictionary] = battle.line_layout([spear] as Array[Regiment], Vector2(200, 1520), Vector2(3000, 1520))
	var c_long: int = long_l[0]["cols"]
	var c_short: int = short_l[0]["cols"]
	var c_huge: int = huge_l[0]["cols"]
	print("Ligne : colonnes courte=%d longue=%d immense=%d (min %d, max %d)" % [
		c_short, c_long, c_huge, spear.min_columns(), spear.max_columns()])
	if not (c_short < c_long):
		fails.append("ligne : une ligne longue devrait donner plus de colonnes qu'une courte")
	if c_short != spear.min_columns() or c_huge != spear.max_columns():
		fails.append("ligne : les bornes min/max de colonnes ne sont pas respectées")

	# Orientation : troupes en bas (y≈1600), ligne tracée au-dessus → elles regardent vers le haut,
	# quel que soit le sens du tracé.
	for pts in [[Vector2(1000, 1400), Vector2(2200, 1400)], [Vector2(2200, 1400), Vector2(1000, 1400)]]:
		var lay: Array[Dictionary] = battle.line_layout(sel, pts[0], pts[1])
		for e in lay:
			var f: Vector2 = e["facing"]
			if f.dot(Vector2.UP) < 0.99:
				fails.append("ligne : orientation %s au lieu de vers le haut" % str(f))
				break
	# Ligne tracée derrière elles (y=1800) → elles se retournent (vers le bas)
	var back: Array[Dictionary] = battle.line_layout(sel, Vector2(1000, 1800), Vector2(2200, 1800))
	if (back[0]["facing"] as Vector2).dot(Vector2.DOWN) < 0.99:
		fails.append("ligne : les troupes devraient se retourner vers la ligne tracée derrière elles")

	# Ordre gauche-droite conservé, même si la ligne est tracée de droite à gauche
	var lay2: Array[Dictionary] = battle.line_layout(sel, Vector2(2200, 1400), Vector2(1000, 1400))
	var by_x: Array[Dictionary] = lay2.duplicate()
	by_x.sort_custom(func(p, q): return (p["dest"] as Vector2).x < (q["dest"] as Vector2).x)
	for i in by_x.size() - 1:
		if (by_x[i]["reg"] as Regiment).center.x > (by_x[i + 1]["reg"] as Regiment).center.x:
			fails.append("ligne : l'ordre gauche-droite des régiments n'est pas conservé")
			break
	# Pas de chevauchement entre régiments voisins
	for i in by_x.size() - 1:
		var a: Dictionary = by_x[i]
		var b: Dictionary = by_x[i + 1]
		var wa: float = int(a["cols"]) * float((a["reg"] as Regiment).stats["spacing"])
		var wb: float = int(b["cols"]) * float((b["reg"] as Regiment).stats["spacing"])
		if (b["dest"] as Vector2).x - (a["dest"] as Vector2).x < (wa + wb) * 0.5:
			fails.append("ligne : deux régiments se chevauchent")
			break

	# Ordre réel + simulation pendant le déploiement : les soldats rejoignent la ligne
	for r in battle.regiments:
		r.selected = sel.has(r)
	battle.issue_line_order(Vector2(2200, 1400), Vector2(1000, 1400))
	for i in 400:
		battle.simulate(STEP)
	for r in sel:
		if r.cols_override <= 0:
			fails.append("ligne : cols_override non appliqué")
			break
		if r.center.distance_to(r.dest) > 12.0:
			fails.append("ligne : %s n'a pas rejoint sa place (%.0f px)" % [r.display_name(), r.center.distance_to(r.dest)])
			break
	# Un simple clic (glissé minuscule) n'est pas un tracé de ligne
	if battle.is_line_drag(Vector2(1200, 1200), Vector2(1202, 1200)):
		fails.append("ligne : un clic sans glisser est pris pour un tracé")
	for r in battle.regiments:
		r.selected = false
	return fails


## Vérifie la touche F : ligne → colonne → carré, la vitesse et l'absence de flanc en carré.
func _test_formations() -> Array[String]:
	var fails: Array[String] = []
	var r: Regiment = null
	for x in battle.player_regiments():
		if x.type == "men_at_arms":
			r = x
			break
	var n := r.alive_n
	for x in battle.regiments:
		x.selected = x == r

	# Cycle de la touche F
	var key := InputEventKey.new()
	key.keycode = KEY_F
	key.pressed = true
	var seen: Array[int] = [r.formation]
	for i in 3:
		battle._unhandled_input(key)
		seen.append(r.formation)
	if seen != [0, 1, 2, 0]:
		fails.append("formations : la touche F donne %s au lieu de ligne, colonne, carré, ligne" % str(seen))

	# Colonne : 3 de front, plus profonde que la ligne
	r.formation = Regiment.Formation.COLUMN
	if r.columns(n) != UnitTypes.COLUMN_WIDTH or r.depth_rows(n) <= 2:
		fails.append("formations : colonne de %d de front sur %d rangs" % [r.columns(n), r.depth_rows(n)])

	# Carré : toutes les places sur le pourtour, toutes différentes, centrées sur la destination
	r.formation = Regiment.Formation.SQUARE
	for count in [n, 7, 10, 20]:
		var side := Regiment.square_side(count)
		var half := (side - 1) * 0.5 * float(r.stats["spacing"])
		var places := {}
		var sum := Vector2.ZERO
		for i in count:
			var p := r.square_slot(i, count, Vector2(1000, 1000), Vector2.UP) - Vector2(1000, 1000)
			sum += p
			var edge_dist := maxf(absf(p.x), absf(p.y))
			if absf(edge_dist - half) > 0.5:
				fails.append("formations : place %d du carré (%d) hors du pourtour" % [i, count])
				break
			places[p.round()] = true
		if places.size() != count:
			fails.append("formations : places en double dans un carré de %d" % count)
		if count % 4 == 0 and (sum / count).length() > 1.0:
			fails.append("formations : carré de %d décentré" % count)

	# Le carré annule flancs et dos ; en ligne ils comptent
	var e: Regiment = battle.regiments.filter(func(x): return x.team == 1)[0]
	var victim := Vector2(1000, 1000)
	e.facing = Vector2.DOWN
	e.formation = Regiment.Formation.LINE
	var rear_line: int = battle.hit_side(victim + Vector2(0, -10), victim, e)
	var flank_line: int = battle.hit_side(victim + Vector2(10, 0), victim, e)
	e.formation = Regiment.Formation.SQUARE
	var rear_sq: int = battle.hit_side(victim + Vector2(0, -10), victim, e)
	var flank_sq: int = battle.hit_side(victim + Vector2(10, 0), victim, e)
	e.formation = Regiment.Formation.LINE
	if rear_line != battle.HIT_REAR or flank_line != battle.HIT_FLANK:
		fails.append("formations : en ligne, le dos et le flanc ne sont pas détectés")
	if rear_sq != battle.HIT_FRONT or flank_sq != battle.HIT_FRONT:
		fails.append("formations : le carré devrait annuler le bonus de flanc et de dos")

	# Le carré est plus lent : on mesure un déplacement de 6 s en ligne puis en carré
	var dist := []
	var home := r.dest
	var lane := _clear_lane(Vector2.UP, 420.0) # Trajet sans forêt (le bois ralentit)
	for f in [Regiment.Formation.LINE, Regiment.Formation.SQUARE]:
		r.formation = f
		_teleport(r, lane, Vector2.UP)
		var start := r.center
		r.dest = start + Vector2(0, -400)
		for i in 120:
			battle.simulate(STEP)
		dist.append(r.center.distance_to(start))
		r.dest = r.center
	print("Formations : distance en 6 s — ligne %.0f px, carré %.0f px" % [dist[0], dist[1]])
	if not (dist[1] < dist[0] * 0.75):
		fails.append("formations : le carré n'est pas plus lent que la ligne")

	# Retour à la place de départ, en ligne
	r.formation = Regiment.Formation.LINE
	r.dest = home
	for i in 300:
		battle.simulate(STEP)
	r.selected = false
	return fails


## Course (double clic droit) : plus rapide, vide l'endurance, s'arrête à l'épuisement ;
## la fatigue réduit vitesse et dégâts.
func _test_running() -> Array[String]:
	var fails: Array[String] = []
	var r: Regiment = null
	for x in battle.player_regiments():
		if x.type == "spear":
			r = x
			break
	for x in battle.regiments:
		x.selected = x == r
	var home := r.dest
	var home_facing := r.facing

	# Double clic droit via les vrais évènements : le 2e appui porte double_click
	var screen := battle.get_viewport().get_visible_rect().size * Vector2(0.5, 0.35)
	for dbl in [false, true]:
		for pressed in [true, false]:
			var mb := InputEventMouseButton.new()
			mb.button_index = MOUSE_BUTTON_RIGHT
			mb.position = screen
			mb.pressed = pressed
			mb.double_click = dbl and pressed
			battle._unhandled_input(mb)
		if r.running != dbl:
			fails.append("course : après le %s clic, running = %s" % ["1er" if not dbl else "2e", str(r.running)])

	# Distance parcourue en 4 s au pas puis en courant, depuis frais, sur un trajet sans forêt
	var lane := _clear_lane(Vector2.RIGHT, 520.0)
	var dist := []
	for run in [false, true]:
		r.stamina = 1.0
		_teleport(r, lane, Vector2.RIGHT)
		var start := r.center
		r.dest = start + Vector2(500, 0)
		r.running = run
		for i in 80:
			battle.simulate(STEP)
		dist.append(r.center.distance_to(start))
	print("Course : distance en 4 s — pas %.0f px, course %.0f px, endurance restante %.2f" % [dist[0], dist[1], r.stamina])
	if not (dist[1] > dist[0] * 1.3):
		fails.append("course : pas plus rapide qu'au pas")
	if not (r.stamina < 0.8):
		fails.append("course : l'endurance ne baisse pas (%.2f)" % r.stamina)

	# Épuisement : la course s'arrête d'elle-même
	r.stamina = 0.05
	r.running = true
	r.dest = r.center + Vector2(0, 600)
	for i in 40:
		battle.simulate(STEP)
	if r.running or r.stamina > 0.05:
		fails.append("course : ne s'arrête pas à l'épuisement (endurance %.2f)" % r.stamina)
	battle.issue_order(r.center + Vector2(0, 200), true)
	if r.running:
		fails.append("course : un régiment épuisé ne devrait pas pouvoir courir")

	# Pénalités de fatigue
	if not is_equal_approx(UnitTypes.fatigue_factor(1.0, UnitTypes.EXHAUSTED_DAMAGE), 1.0) 			or not is_equal_approx(UnitTypes.fatigue_factor(UnitTypes.STAMINA_TIRED, UnitTypes.EXHAUSTED_DAMAGE), 1.0) 			or not is_equal_approx(UnitTypes.fatigue_factor(0.0, UnitTypes.EXHAUSTED_DAMAGE), UnitTypes.EXHAUSTED_DAMAGE):
		fails.append("course : facteur de fatigue incorrect")
	var slow := []
	for st in [1.0, 0.0]:
		r.stamina = st
		r.running = false
		_teleport(r, lane, Vector2.RIGHT)
		var start := r.center
		r.dest = start + Vector2(500, 0)
		for i in 40:
			battle.simulate(STEP)
		slow.append(r.center.distance_to(start))
		r.stamina = st
	if not (slow[1] < slow[0] * 0.8):
		fails.append("course : un régiment épuisé n'est pas plus lent (%.0f contre %.0f px)" % [slow[1], slow[0]])

	# Récupération au repos
	r.stamina = 0.2
	r.dest = r.center
	for i in 100:
		battle.simulate(STEP)
	if not (r.stamina > 0.3):
		fails.append("course : pas de récupération au repos (%.2f)" % r.stamina)

	# Retour à la place de départ, reposé
	r.running = false
	_teleport(r, home, home_facing)
	r.stamina = 1.0
	r.selected = false
	return fails


## Vérifs ciblées du terrain : table des contrats, puis selon le terrain forcé : eau et gués,
## relief, maisons à contourner, palissade qui bloque et brèches qui laissent passer.
func _test_terrain() -> Array[String]:
	var fails: Array[String] = []
	var t: Terrain = battle.terrain
	if terrain_kind != "random" and t.kind != terrain_kind:
		fails.append("terrain : %s demandé, %s obtenu" % [terrain_kind, t.kind])
	# Table des contrats de campagne
	var towns := CampaignState.TOWNS
	var expect := {["Valombre", 1]: "forest", ["Brévannes", 2]: "river", ["Saint-Aubin", 1]: "village",
		["Montfaucon", 2]: "hills", ["Hautemure", 3]: "siege", ["Castelroux", 3]: "siege", ["Castelroux", 1]: "hills"}
	for k in expect:
		var idx := -1
		for i in towns.size():
			if towns[i]["name"] == k[0]:
				idx = i
		if Terrain.for_contract(idx, k[1], towns) != expect[k]:
			fails.append("terrain : %s (difficulté %d) devrait donner %s" % [k[0], k[1], expect[k]])
	match t.kind:
		"river":
			fails.append_array(_test_river(t))
		"hills":
			fails.append_array(_test_hills(t))
		"village":
			fails.append_array(_test_village(t))
		"siege":
			fails.append_array(_test_siege(t))
	return fails


## Soldat isolé (hors de la liste de la bataille) d'un régiment du joueur du type voulu.
func _lone_soldier(type: String, at: Vector2) -> Soldier:
	var s := Soldier.new()
	for r in battle.player_regiments():
		if r.type == type:
			s.regiment = r
			break
	if s.regiment == null:
		s.regiment = battle.player_regiments()[0]
	s.pos = at
	return s


## Fait marcher s vers goal pendant duration secondes ; appelle check(pos) à chaque pas.
func _walk(s: Soldier, goal: Vector2, duration: float, check: Callable = Callable()) -> void:
	var speed: float = s.regiment.stats["speed"]
	var rad: float = s.regiment.stats["radius"]
	for i in int(duration / STEP):
		battle.move_towards(s, goal, speed, STEP)
		s.pos = battle.terrain.push_out(s.pos, rad)
		if check.is_valid():
			check.call(s.pos)


func _test_river(t: Terrain) -> Array[String]:
	var fails: Array[String] = []
	if t.fords.size() < 2 or t.fords.size() > 3:
		fails.append("rivière : %d gués au lieu de 2 ou 3" % t.fords.size())
		return fails
	# Point d'eau profonde loin des gués
	var deep_x := 0.0
	for x in range(200, 3000, 40):
		var ok := true
		for f in t.fords:
			if absf(x - f) < Terrain.FORD_HALF + 120.0:
				ok = false
		if ok:
			deep_x = x
			break
	var dist := {}
	for where in ["terre", "eau", "gué"]:
		var x: float = deep_x if where != "gué" else t.fords[0]
		var y: float = battle.road_y(x) - (Terrain.RIVER_HALF - 4.0 if where != "terre" else 260.0)
		var s := _lone_soldier("spear", Vector2(x, y))
		var start := s.pos
		_walk(s, start + Vector2(0, 400), 1.0)
		dist[where] = s.pos.distance_to(start)
	print("Rivière : 1 s de marche — terre %.0f px, eau %.0f px, gué %.0f px" % [dist["terre"], dist["eau"], dist["gué"]])
	if not (dist["eau"] < dist["terre"] * 0.5):
		fails.append("rivière : le soldat n'est pas ralenti dans l'eau")
	if not (dist["gué"] > dist["terre"] * 0.9):
		fails.append("rivière : le gué devrait se traverser à vitesse normale")
	if t.has_road() or battle.on_road(Vector2(deep_x, battle.road_y(deep_x)), 18.0):
		fails.append("rivière : la route devrait être remplacée par la rivière")
	return fails


func _test_hills(t: Terrain) -> Array[String]:
	var fails: Array[String] = []
	var top := Vector2.ZERO
	var best := 0.0
	for y in range(400, 1600, 20):
		for x in range(100, 3100, 20):
			var h := t.height(Vector2(x, y))
			if h > best:
				best = h
				top = Vector2(x, y)
	var foot := top + Vector2(0, 600)
	print("Collines : sommet %.2f en %s, pied %.2f, portée x%.2f, dégâts d'en haut x%.2f" % [
		best, str(top), t.height(foot), t.range_factor(top), t.height_damage(top, foot)])
	if best < 0.6:
		fails.append("collines : aucun sommet assez haut (%.2f)" % best)
	if t.range_factor(top) < 1.15 or t.range_factor(top) <= t.range_factor(foot):
		fails.append("collines : les archers en hauteur ne tirent pas plus loin")
	if t.height_damage(top, foot) <= 1.1 or t.height_damage(foot, top) != 1.0:
		fails.append("collines : frapper d'en haut devrait faire plus de dégâts (et seulement d'en haut)")
	# Montée plus lente que la descente : on cherche le versant le plus raide autour du sommet
	var up := 1.0
	var down := 1.0
	for d in range(40, 400, 20):
		for k in 8:
			var dir := Vector2.from_angle(k * TAU / 8.0)
			var p := top + dir * d
			var f := t.speed_factor(p, -dir, "spear")
			if f < up:
				up = f
				down = t.speed_factor(p, dir, "spear")
	if not (up < 0.85 and down >= 0.999):
		fails.append("collines : la montée devrait ralentir (montée x%.2f, descente x%.2f)" % [up, down])
	return fails


func _test_village(t: Terrain) -> Array[String]:
	var fails: Array[String] = []
	if t.houses.size() < 4:
		fails.append("village : seulement %d maisons" % t.houses.size())
		return fails
	var h: Rect2 = t.houses[0]
	var s := _lone_soldier("men_at_arms", h.get_center() + Vector2(0, h.size.y * 0.5 + 40.0))
	var goal := h.get_center() - Vector2(0, h.size.y * 0.5 + 40.0)
	var inside := [false]
	_walk(s, goal, 20.0, func(p: Vector2) -> void:
		for o in t.houses:
			if o.has_point(p):
				inside[0] = true)
	print("Village : %d maisons, contournement d'une maison → %.0f px du but" % [t.houses.size(), s.pos.distance_to(goal)])
	if inside[0]:
		fails.append("village : un soldat est entré dans une maison")
	if s.pos.distance_to(goal) > 6.0:
		fails.append("village : le soldat n'a pas contourné la maison (%.0f px du but)" % s.pos.distance_to(goal))
	return fails


func _test_siege(t: Terrain) -> Array[String]:
	var fails: Array[String] = []
	if t.walls.size() != 3 or t.breaches.size() != 2:
		fails.append("palissade : %d tronçons et %d brèches" % [t.walls.size(), t.breaches.size()])
		return fails
	var wy := Terrain.WALL_Y
	var x := (t.breaches[0] + t.breaches[1]) * 0.5 # Au milieu du mur, loin des brèches
	var start := Vector2(x, wy - 60.0)
	var goal := Vector2(x, wy + 60.0)
	if not t.wall_blocks(start, goal) or t.wall_blocks(Vector2(t.breaches[0], wy - 60), Vector2(t.breaches[0], wy + 60)):
		fails.append("palissade : wall_blocks incorrect")
	# Bloqué par le mur : en 3 s il n'a pas traversé
	var s := _lone_soldier("men_at_arms", start)
	var crossings: Array[float] = []
	var last := [s.pos.y - wy]
	var watch := func(p: Vector2) -> void:
		var d := p.y - wy
		if d * last[0] < 0.0 or (d >= 0.0 and last[0] < 0.0):
			crossings.append(p.x)
		last[0] = d
	_walk(s, goal, 3.0, watch)
	if s.pos.y > wy:
		fails.append("palissade : le soldat a traversé le mur directement")
	# Puis il passe par une brèche et arrive au but
	_walk(s, goal, 90.0, watch)
	print("Palissade : brèches en x = %d et %d, traversée en x = %s, %.0f px du but" % [
		int(t.breaches[0]), int(t.breaches[1]), str(crossings), s.pos.distance_to(goal)])
	if s.pos.distance_to(goal) > 6.0:
		fails.append("palissade : le soldat n'a pas atteint le but par une brèche (%.0f px)" % s.pos.distance_to(goal))
	for cx in crossings:
		var in_breach := false
		for b in t.breaches:
			if absf(cx - b) < Terrain.BREACH_HALF:
				in_breach = true
		if not in_breach:
			fails.append("palissade : traversée hors brèche en x = %.0f" % cx)
	if crossings.is_empty():
		fails.append("palissade : aucune traversée détectée")
	# Les défenseurs derrière les pieux sont abrités des flèches venues d'en face
	if not t.wall_shelters(Vector2(x, wy - 300), Vector2(x, wy + 30)) or t.wall_shelters(Vector2(x, wy + 300), Vector2(x, wy + 30)):
		fails.append("palissade : abri contre les flèches incorrect")
	# Un ennemi derrière la palissade n'est pas un adversaire de mêlée accessible
	var foe := _lone_soldier("spear", Vector2(x, wy + 12))
	if not t.wall_blocks(Vector2(x, wy - 12), foe.pos):
		fails.append("palissade : la mêlée à travers le mur devrait être impossible")
	return fails

## Ordres : tenir la position (G), cesser le tir (X), groupes de contrôle (Ctrl + chiffre).
## Les combats se font entre régiments de test ajoutés loin des armées, puis retirés.
## Pendant le test, la bataille est « lancée » mais l'IA ennemie ne commande personne.
func _test_orders() -> Array[String]:
	var fails: Array[String] = []
	battle.state = battle.State.BATTLE
	battle.ai.team = 2
	var spot := _clear_spot()

	# --- Tenir la position : un ennemi à 80 px, hors d'allonge
	var mine: Regiment = battle.add_regiment(0, "men_at_arms", spot, Vector2.UP)
	var foe: Regiment = battle.add_regiment(1, "spear", spot + Vector2(0, -80), Vector2.DOWN)
	foe.hold_position = true # L'ennemi ne bouge pas non plus
	# Témoin : sans l'ordre, le régiment va au-devant de l'ennemi
	for i in 20:
		battle.simulate(STEP)
	if mine.target != foe:
		fails.append("tenir : sans l'ordre, le régiment devrait s'engager contre l'ennemi proche")
	_teleport(mine, spot, Vector2.UP)
	for x in battle.regiments:
		x.selected = x == mine
	_press(KEY_G)
	if not mine.hold_position:
		fails.append("tenir : la touche G n'active pas l'ordre")
	var start := mine.center
	for i in 60:
		battle.simulate(STEP)
	print("Tenir : déplacement %.1f px vers un ennemi à 80 px, cible %s" % [
		mine.center.distance_to(start), "aucune" if mine.target == null else mine.target.display_name()])
	if mine.target != null or mine.center.distance_to(start) > 4.0:
		fails.append("tenir : le régiment a quitté sa place (%.1f px)" % mine.center.distance_to(start))
	# Attaqué, il riposte sans poursuivre
	foe.hold_position = false
	foe.target = mine
	var foe_hp := _total_hp(foe)
	for i in 80:
		battle.simulate(STEP)
	if not (_total_hp(foe) < foe_hp):
		fails.append("tenir : le régiment ne frappe pas l'ennemi venu à sa portée")
	if mine.target != null or mine.dest.distance_to(spot) > 0.5:
		fails.append("tenir : le régiment attaqué s'est lancé à la poursuite")
	_press(KEY_G)
	if mine.hold_position:
		fails.append("tenir : un 2e appui sur G ne lève pas l'ordre")
	_remove_test_regiment(mine)
	_remove_test_regiment(foe)

	# --- Cesser le tir : archers et cible à 200 px (à portée)
	var archers: Regiment = battle.add_regiment(0, "archer", spot, Vector2.UP)
	var target: Regiment = battle.add_regiment(1, "spear", spot + Vector2(0, -200), Vector2.DOWN)
	target.hold_position = true
	for x in battle.regiments:
		x.selected = x == archers
	_press(KEY_X)
	if archers.fire_at_will:
		fails.append("tir : la touche X ne fait pas cesser le tir")
	battle.arrows.clear()
	var fired := 0
	for i in 80:
		battle.simulate(STEP)
		fired += battle.arrows.size()
	if fired > 0:
		fails.append("tir : des flèches partent sans ordre alors que le tir à volonté est coupé")
	# Cible ordonnée (clic droit sur l'ennemi) : ils tirent quand même
	archers.target = target
	var ordered := 0
	for i in 80:
		battle.simulate(STEP)
		ordered += battle.arrows.size()
	print("Tir : flèches sans ordre %d, sur cible ordonnée %d" % [fired, ordered])
	if ordered <= 0:
		fails.append("tir : les archers ne tirent pas sur une cible ordonnée")
	archers.target = null
	_press(KEY_X)
	if not archers.fire_at_will:
		fails.append("tir : un 2e appui sur X ne rétablit pas le tir à volonté")
	battle.arrows.clear()
	_remove_test_regiment(archers)
	_remove_test_regiment(target)

	# --- Groupes de contrôle (touches par position physique, comme en AZERTY)
	var list: Array[Regiment] = battle.player_regiments()
	for x in battle.regiments:
		x.selected = x == list[0] or x == list[2]
	_press_digit(3, true) # Ctrl + 3 : mémorise
	if not (list[0].selected and list[2].selected and not list[1].selected):
		fails.append("groupes : Ctrl + chiffre ne doit pas changer la sélection")
	for x in battle.regiments:
		x.selected = x == list[5]
	_press_digit(3, false) # 3 : rappel du groupe
	var sel: Array[Regiment] = battle.selected_regiments()
	if sel.size() != 2 or not sel.has(list[0]) or not sel.has(list[2]):
		fails.append("groupes : le rappel du groupe 3 sélectionne %d régiment(s)" % sel.size())
	_press_digit(5, false) # 5 : pas de groupe → régiment n° 5
	sel = battle.selected_regiments()
	if sel.size() != 1 or sel[0] != list[4]:
		fails.append("groupes : sans groupe, le chiffre 5 devrait sélectionner le régiment n° 5")
	# Double appui : la caméra se centre sur le groupe
	battle.camera.position = Vector2(400, 400)
	battle.clamp_camera()
	var center := (list[0].center + list[2].center) * 0.5
	var before: float = battle.camera.position.distance_to(center)
	_press_digit(3, false)
	_press_digit(3, false)
	var after: float = battle.camera.position.distance_to(center)
	print("Groupes : caméra à %.0f px du groupe avant le double appui, %.0f px après" % [before, after])
	if not (after < before * 0.5):
		fails.append("groupes : le double appui ne centre pas la caméra sur le groupe")
	battle.groups.clear()
	battle.camera.position = Vector2(battle.WORLD_SIZE.x * 0.5, 1560)
	for x in battle.regiments:
		x.selected = false

	battle.ai.team = 1
	battle.state = battle.State.DEPLOY
	battle.battle_time = 0.0
	return fails


func _press(code: Key) -> void:
	var key := InputEventKey.new()
	key.keycode = code
	key.physical_keycode = code
	key.pressed = true
	battle._unhandled_input(key)


## Chiffre n (1-9) par sa position physique seulement : en AZERTY, la touche « & » donne 1.
func _press_digit(n: int, ctrl: bool) -> void:
	var key := InputEventKey.new()
	key.physical_keycode = (KEY_1 + n - 1) as Key
	key.ctrl_pressed = ctrl
	key.pressed = true
	battle._unhandled_input(key)


func _total_hp(r: Regiment) -> float:
	var hp := 0.0
	for s in r.soldiers:
		if s.alive:
			hp += s.hp
	return hp


## Retire un régiment ajouté pour un test, sans laisser de trace dans la bataille.
func _remove_test_regiment(r: Regiment) -> void:
	for s in r.soldiers:
		s.alive = false
		battle.soldiers.erase(s)
		s.regiment = null
		s.foe = null
	for s in battle.soldiers:
		if s.foe != null and s.foe.regiment == null:
			s.foe = null
	battle.initial_strength[r.team] -= r.soldiers.size()
	r.soldiers.clear()
	r.update_center()
	r.target = null
	r.fire_target = null
	battle.regiments.erase(r)
	for o in battle.regiments:
		if o.target == r:
			o.target = null
		if o.fire_target == r:
			o.fire_target = null
	battle.corpses.clear()
	battle.dust.clear()
	battle.rebuild_grid()
	for i in battle.regiments.size():
		battle.regiments[i].id = i


## Endroit dégagé (sans forêt) et loin des deux armées pour les régiments de test.
func _clear_spot() -> Vector2:
	for y in range(900, 1200, 50):
		for x in range(200, 3000, 100):
			var p := Vector2(x, y)
			var ok := true
			for off in [Vector2.ZERO, Vector2(-80, 0), Vector2(80, 0), Vector2(0, -240), Vector2(0, 60),
					Vector2(-80, -240), Vector2(80, -240)]:
				if battle.is_in_forest(p + off):
					ok = false
					break
			if ok:
				return p
	return Vector2(300, 1000)


## Point de départ d'un trajet sans forêt de la longueur voulue dans la zone de déploiement.
func _clear_lane(dir: Vector2, length: float) -> Vector2:
	for y in range(1500 if dir.y >= 0.0 else 1950, 1950 if dir.y >= 0.0 else 1500, 50 if dir.y >= 0.0 else -50):
		for x in range(200, 2800, 100):
			var start := Vector2(x, y)
			var ok := true
			for k in range(0, int(length) + 1, 16):
				for side in [-70.0, 0.0, 70.0]:
					if battle.is_in_forest(start + dir * k + Vector2(-dir.y, dir.x) * side):
						ok = false
						break
				if not ok:
					break
			if ok:
				return start
	return Vector2(400, 1700)


## Place instantanément un régiment en formation en p.
func _teleport(r: Regiment, p: Vector2, face: Vector2) -> void:
	r.dest = p
	r.facing = face
	r.target = null
	var alive := r.alive_soldiers()
	for i in alive.size():
		alive[i].pos = r.slot_position(i, alive.size())
	r.update_center()


## Vérifie que les sprites et les sons sont bien chargés.
func _check_assets() -> Array[String]:
	var fails: Array[String] = []
	var bank: SpriteBank = battle.sprites
	if not bank.ok:
		fails.append("sprites d'unités manquants")
	if not bank.has_trees():
		fails.append("sprites d'arbres manquants")
	var n: int = battle.audio.loaded_count()
	print("Assets : sprites %s, arbres %d, sons chargés %d" % ["OK" if bank.ok else "KO", bank.trees.size(), n])
	if n < 30:
		fails.append("seulement %d sons chargés" % n)
	# Chaque image demandée doit tomber dans la planche
	for type in SpriteBank.UNITS:
		for team in 2:
			for dir in 4:
				for anim in ["idle", "walk", "attack"]:
					for t in [0.0, 0.5, 0.99, 7.0]:
						var f := bank.frame(type, team, dir, anim, t)
						var tex: Texture2D = f["tex"]
						var src: Rect2 = f["src"]
						if not Rect2(Vector2.ZERO, tex.get_size()).encloses(src):
							fails.append("image hors planche : %s %s dir %d" % [type, anim, dir])
							return fails
	return fails


func _check() -> Array[String]:
	var fails: Array[String] = []
	var lost := [0, 0]
	for r in battle.regiments:
		for s in r.soldiers:
			if not s.alive:
				lost[r.team] += 1
	print("Fin à t = %.1f s — état : %s — pertes joueur : %d / %d, ennemi : %d / %d" % [
		battle.battle_time, battle.State.keys()[battle.state],
		lost[0], battle.initial_strength[0], lost[1], battle.initial_strength[1]])
	if battle.state != battle.State.VICTORY and battle.state != battle.State.DEFEAT:
		fails.append("la bataille n'est pas terminée après %d s simulées" % int(max_time))
	if battle.state != battle.State.BATTLE and battle.battle_time < MIN_DURATION:
		fails.append("bataille trop courte : %.0f s (minimum %d s)" % [battle.battle_time, int(MIN_DURATION)])
	if lost[0] <= 0:
		fails.append("aucun soldat du joueur n'est mort")
	if lost[1] <= 0:
		fails.append("aucun soldat ennemi n'est mort")
	# Ressenti : poussière limitée, pas de secousse sans fenêtre, ralenti de fin
	print("Ressenti : poussière max %d particules (limite %d), secousse %.2f, ralenti %s" % [
		max_dust, battle.MAX_DUST, battle.shake, "oui" if battle.slowmo >= 0.0 else "non"])
	if max_dust <= 0:
		fails.append("ressenti : aucune poussière sous les sabots pendant la bataille")
	if max_dust > battle.MAX_DUST:
		fails.append("ressenti : trop de particules de poussière (%d)" % max_dust)
	if battle.shake != 0.0 or battle.camera.offset != Vector2.ZERO:
		fails.append("ressenti : la caméra tremble alors qu'il n'y a pas de fenêtre")
	if battle.state != battle.State.BATTLE:
		if battle.slowmo < 0.0:
			fails.append("ressenti : pas de ralenti à la fin de la bataille")
		battle.slowmo = 0.0
		var slow: float = battle.time_factor(0.1)
		var back: float = battle.time_factor(10.0)
		if not is_equal_approx(slow, battle.SLOWMO_SCALE) or not is_equal_approx(back, 1.0) or battle.slowmo >= 0.0:
			fails.append("ressenti : ralenti incorrect (%.2f puis %.2f)" % [slow, back])
	if not counter.errors.is_empty():
		fails.append("%d erreur(s) pendant la bataille" % counter.errors.size())
	return fails


func _finish(fails: Array[String]) -> void:
	finished = true
	for w in counter.warnings:
		print("  avertissement : ", w)
	for e in counter.errors:
		print("  erreur : ", e)
	if fails.is_empty():
		print("SMOKE TEST OK")
	else:
		for f in fails:
			print("ÉCHEC : ", f)
		print("SMOKE TEST ÉCHOUÉ")
	OS.remove_logger(counter)
	if battle != null:
		root.remove_child(battle)
		battle.free()
	quit(0 if fails.is_empty() else 1)
