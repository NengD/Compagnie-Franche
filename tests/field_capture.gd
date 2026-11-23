extends SceneTree
## Captures des silhouettes et des traces de bataille (à lancer AVEC fenêtre, pas en --headless) :
##   godot --path . -s tests/field_capture.gd [-- --out=<dossier>]
## Enregistre dans user://captures (défaut) :
## - champ_silhouettes.png : un régiment de chaque type côte à côte (piques dressées, arcs longs,
##   arbalétriers qui rechargent, harnois des chevaliers à pied, cavaliers caparaçonnés et archers
##   montés), face à un ennemi qui les attend ;
## - champ_morts.png : soldats en train de tomber (côté, renverse, avant, à genoux) ;
## - champ_melee.png : le champ après une longue mêlée (corps, armes, flèches plantées, boue) ;
## - champ_deroute.png : un régiment qui fuit, son étendard au sol, les armes jetées.

const CaptureDir := preload("res://tests/capture_dir.gd")
const TestPlayer := preload("res://tests/test_player.gd")
const SEED := 12345
const TYPES: Array[String] = ["spear", "men_at_arms", "foot_knight", "archer", "crossbow", "cavalry", "horse_archer"]

const SHOTS: Array[Dictionary] = [
	{"stage": "lineup", "file": "champ_silhouettes.png", "zoom": 3.0},
	{"stage": "deaths", "file": "champ_morts.png", "zoom": 4.0},
	{"stage": "melee", "file": "champ_melee.png", "zoom": 2.2},
	{"stage": "rout", "file": "champ_deroute.png", "zoom": 2.5},
]

var scene: PackedScene
var battle: Node
var player := TestPlayer.new("tactical")
var index := 0
var frame := 0
var aim := Vector2.ZERO


func _initialize() -> void:
	AudioServer.set_bus_mute(0, true) # Aucun son pendant les captures
	GameOptions.ensure_loaded()
	GameOptions.effects = "full"
	scene = load("res://scenes/main.tscn")
	_open()


func _open() -> void:
	battle = scene.instantiate()
	battle.set("seed_override", SEED)
	battle.set("terrain_override", "plain")
	root.add_child(battle)
	frame = 0


func _process(delta: float) -> bool:
	frame += 1
	var shot: Dictionary = SHOTS[index]
	if frame == 3:
		battle.show_help = false
		battle.start_battle()
		match str(shot["stage"]):
			"lineup":
				_stage_lineup()
			"deaths":
				_stage_deaths()
			"melee":
				_stage_melee()
			"rout":
				_stage_rout()
	if frame >= 3:
		battle.camera.zoom = Vector2(shot["zoom"], shot["zoom"])
		battle.camera.position = aim
	if frame == 40:
		CaptureDir.save(self, shot["file"])
		print("Capture : ", shot["file"])
		root.remove_child(battle)
		battle.free()
		index += 1
		if index >= SHOTS.size():
			quit(0)
			return true
		_open()
	return false


## Point dégagé (ni forêt, ni eau, ni maison) sur une largeur w autour de lui, près du centre.
func _clear_spot(w: float) -> Vector2:
	var mid: Vector2 = battle.WORLD_SIZE * 0.5
	for k in 400:
		var p := mid + Vector2((k % 20 - 10) * 80.0, (floori(k / 20.0) - 10) * 60.0)
		var ok := true
		var x := -w * 0.5 - 40.0
		while x <= w * 0.5 + 40.0 and ok:
			for dy in [-360.0, -60.0, 0.0, 60.0]:
				var q := p + Vector2(x, dy)
				if battle.sim.is_in_forest(q) or battle.terrain.is_river(q, 10.0) or not Rect2(Vector2(60, 400), battle.WORLD_SIZE - Vector2(120, 460)).has_point(q):
					ok = false
			x += 12.0
		if ok:
			return p
	return mid


## Écarte tous les régiments du cadre (hors du champ visible).
func _clear() -> void:
	for r in battle.regiments:
		battle.renderer.field.routed[r] = true # Pas d'étendard tombé pour eux
		for s in r.soldiers:
			s.alive = false
		r.update_center()


func _simulate(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		battle.simulate(0.05)
		battle.renderer.update_effects(0.05)
		t += 0.05


## Un régiment de chaque type, de gauche à droite ; un ennemi au loin, que les tireurs visent.
func _stage_lineup() -> void:
	_clear()
	var mid := _clear_spot(TYPES.size() * 62.0)
	var foe: Regiment = battle.add_regiment(battle.ENEMY, "men_at_arms", mid + Vector2(0, -330), Vector2.DOWN, 12)
	foe.hold_position = true
	var regs: Array[Regiment] = []
	for i in TYPES.size():
		var at := mid + Vector2((i - 3) * 62.0, 0)
		var r: Regiment = battle.add_regiment(battle.PLAYER, TYPES[i], at, Vector2.UP, 6)
		r.cols_override = 3
		r.hold_position = true
		if r.stats["ranged"]:
			r.fire_target = foe
		regs.append(r)
	# Les piquiers de gauche face à un ennemi au contact : piques baissées
	_simulate(1.6)
	aim = mid + Vector2(0, -12)


## Des soldats tués à des instants décalés, frappés de directions variées : chutes figées en cours
## (la bataille est mise en pause) et corps déjà couchés.
func _stage_deaths() -> void:
	_clear()
	var mid := _clear_spot(200.0)
	var r: Regiment = battle.add_regiment(battle.PLAYER, "men_at_arms", mid, Vector2.DOWN, 24)
	r.cols_override = 8
	r.hold_position = true
	var far: Regiment = battle.add_regiment(battle.ENEMY, "archer", mid + Vector2(0, -900), Vector2.DOWN, 6)
	far.hold_position = true # Un ennemi au loin : la bataille n'est pas finie
	_simulate(0.3)
	var alive: Array = r.alive_soldiers()
	var looks: Array[Vector2] = [Vector2.DOWN, Vector2.RIGHT, Vector2.UP, Vector2.LEFT]
	for i in alive.size():
		if i % 3 == 0:
			continue # Quelques survivants autour des morts
		battle.sim.damage(alive[i], 99999.0, null)
		battle.corpses.back()[6] = looks[i % 4]
		_simulate(0.06)
	battle.game_speed = 0.0 # Chutes figées, sans le panneau de pause
	aim = r.center


## Une longue bataille : le champ garde les traces des combats.
func _stage_melee() -> void:
	while battle.battle_time < 80.0 and battle.state == battle.State.BATTLE:
		player.update(battle)
		battle.simulate(0.05)
		battle.renderer.update_effects(0.05)
	aim = _busiest()


## Après la mêlée, un régiment ennemi encore debout prend la fuite.
func _stage_rout() -> void:
	_stage_melee()
	var best: Regiment = null
	for r in battle.regiments:
		if r.team == battle.ENEMY and not r.is_dead() and not r.routing and (best == null or r.alive_n > best.alive_n):
			best = r
	if best == null:
		aim = _busiest()
		return
	var at: Vector2 = best.center
	battle.sim.start_rout(best)
	_simulate(1.2)
	aim = at.lerp(best.center, 0.5)


## Endroit où sont tombés le plus de corps (case de 200 px).
func _busiest() -> Vector2:
	var cells := {}
	var top := Vector2i.ZERO
	var best := 0
	for c in battle.corpses:
		var k := Vector2i((c[0] as Vector2) / 200.0)
		cells[k] = int(cells.get(k, 0)) + 1
		if cells[k] > best:
			best = cells[k]
			top = k
	if best == 0:
		return battle.WORLD_SIZE * 0.5
	var sum := Vector2.ZERO
	var n := 0
	for c in battle.corpses:
		if Vector2i((c[0] as Vector2) / 200.0) == top:
			sum += c[0]
			n += 1
	return sum / n
