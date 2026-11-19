extends SceneTree
## Captures des effets visuels (à lancer AVEC fenêtre, pas en --headless) :
##   godot --path . -s tests/effects_capture.gd [-- --out=<dossier>] [-- --effects=reduced]
## Enregistre dans user://captures (défaut) : effets_village.png (fumée des cheminées, flaques et
## pluie au sol), effets_gue.png (éclaboussures dans un gué), effets_melee.png (sang, étincelles,
## traînées des flèches, étendards), effets_charge.png (éclat d'une charge de cavalerie, nuage de
## poussière) et effets_equipement.png (régiments du joueur équipés en qualités 1, 2 et 3,
## armoiries sur les bannières, corps qui tombent et restent au sol).

const CaptureDir := preload("res://tests/capture_dir.gd")
const TestPlayer := preload("res://tests/test_player.gd")
const SEED := 12345

## Scènes : terrain, pluie, secondes de bataille avant la capture, cible de la caméra, fichier.
const SHOTS: Array[Dictionary] = [
	{"terrain": "village", "rain": true, "time": 20.0, "aim": "houses", "file": "effets_village.png"},
	{"terrain": "river", "rain": false, "time": 0.0, "aim": "ford", "file": "effets_gue.png"},
	{"terrain": "plain", "rain": false, "time": 65.0, "aim": "melee", "file": "effets_melee.png"},
	{"terrain": "plain", "rain": false, "time": 0.0, "aim": "charge", "file": "effets_charge.png"},
	{"terrain": "plain", "rain": false, "time": 0.0, "aim": "gear", "file": "effets_equipement.png"},
]

var scene: PackedScene
var battle: Node
var player := TestPlayer.new("tactical")
var index := 0
var frame := 0


func _initialize() -> void:
	AudioServer.set_bus_mute(0, true) # Aucun son pendant les tests
	GameOptions.ensure_loaded()
	GameOptions.effects = "full"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--effects="):
			GameOptions.effects = a.trim_prefix("--effects=")
	scene = load("res://scenes/main.tscn")
	_open()


func _open() -> void:
	battle = scene.instantiate()
	battle.set("seed_override", SEED)
	battle.set("terrain_override", SHOTS[index]["terrain"])
	root.add_child(battle)
	frame = 0


func _process(_delta: float) -> bool:
	frame += 1
	var shot: Dictionary = SHOTS[index]
	var aim: String = shot["aim"]
	if frame == 3:
		battle.show_help = false
		battle.raining = shot["rain"]
		battle.start_battle()
		battle.camera.zoom = Vector2(2.5, 2.5)
		match aim:
			"charge":
				_stage_charge()
			"ford":
				_stage_ford()
			"gear":
				_stage_gear()
		while battle.battle_time < shot["time"]:
			if aim == "houses" or aim == "melee":
				player.update(battle)
			battle.simulate(0.05)
			battle.renderer.update_effects(0.05) # Les effets suivent (fumée, flaques)
	if frame >= 3:
		if aim == "houses" or aim == "melee":
			player.update(battle)
		battle.camera.zoom = Vector2(4.0, 4.0) if aim == "gear" else Vector2(2.5, 2.5)
		battle.camera.position = _aim(aim)
	var done := frame == 60
	if aim == "charge":
		done = _charge_hit() or frame == 400
	elif aim == "ford":
		done = (frame > 30 and _in_water() >= 6) or frame == 600
	if done:
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


## Une cavalerie du joueur face à des archers ennemis posés 220 px devant elle, qu'elle charge.
func _stage_charge() -> void:
	for r in battle.regiments:
		if r.team == battle.PLAYER and r.type == "cavalry":
			var e: Regiment = battle.add_regiment(battle.ENEMY, "archer", r.center + Vector2(0, -230), Vector2.DOWN)
			r.target = e
			r.running = true
			charge_reg = r
			return


## Équipe les régiments du joueur (qualités 1, 2, 3 tour à tour), les fait marcher, et fait
## tomber quelques soldats (corps en train de tomber et couchés).
func _stage_gear() -> void:
	var tier := 0
	var mid: Vector2 = battle.WORLD_SIZE * 0.5 + Vector2(0, 400)
	for r in battle.regiments:
		if r.team != battle.PLAYER:
			continue
		var at: Vector2 = mid + Vector2(-2000, 0) # Hors du cadre
		if not r.stats["mounted"] and not r.stats["ranged"] and tier < 3:
			at = mid + Vector2((tier - 1) * 120.0, 0) # Trois fantassins côte à côte : qualités 1, 2, 3
			tier += 1
			r.cols_override = 4
		r.gear = [Equipment.item_id("helmet", maxi(tier, 1)), Equipment.item_id("weapon", maxi(tier, 1)), Equipment.item_id("armor", maxi(tier, 1))]
		r.facing = Vector2.DOWN # Face à la caméra
		r.dest = at
		var alive: Array = r.alive_soldiers()
		for i in alive.size():
			alive[i].pos = r.slot_position(i, alive.size())
		r.update_center()
		r.dest = at + Vector2(0, 40) # Ils marchent vers la caméra
	battle.renderer.looks.clear()
	gear_aim = mid + Vector2(0, 40)
	for i in 12:
		battle.simulate(0.05)
	var k := 0
	for r in battle.regiments:
		if r.team == battle.PLAYER and r.center.distance_to(mid) < 300.0:
			for s in r.alive_soldiers().slice(0, 2):
				battle.sim.damage(s, 99999.0, null)
				k += 1
	battle.simulate(0.15)


var gear_aim := Vector2.ZERO


## Les piquiers du joueur marchent vers le premier gué.
func _stage_ford() -> void:
	var fx: float = battle.terrain.fords[0] if not battle.terrain.fords.is_empty() else 1600.0
	ford_point = Vector2(fx, battle.road_y(fx))
	var best: Regiment = null
	for r in battle.regiments:
		if r.team == battle.PLAYER and (best == null or r.center.distance_to(ford_point) < best.center.distance_to(ford_point)):
			best = r
	best.dest = ford_point + Vector2(0, -60)
	best.running = true
	ford_reg = best


func _in_water() -> int:
	var n := 0
	for s in battle.soldiers:
		if s.alive and battle.terrain.is_river(s.pos):
			n += 1
	return n


var charge_reg: Regiment = null
var ford_reg: Regiment = null
var ford_point := Vector2.ZERO
var charge_frames := -1


func _charge_hit() -> bool:
	if charge_frames < 0:
		var fx: BattleEffects = battle.renderer.effects
		for d in fx.parts:
			if int(d[6]) == BattleEffects.FLASH:
				charge_frames = 0
	else:
		charge_frames += 1
	return charge_frames == 3


func _aim(what: String) -> Vector2:
	match what:
		"houses":
			var houses: Array[Rect2] = battle.terrain.houses
			return houses[0].get_center() if not houses.is_empty() else battle.WORLD_SIZE * 0.5
		"ford":
			if ford_reg != null and _in_water() > 0:
				return ford_reg.center
			# Soldats dans l'eau les plus nombreux, sinon le premier gué
			var c := Vector2.ZERO
			var n := 0
			for s in battle.soldiers:
				if s.alive and battle.terrain.is_river(s.pos):
					c += s.pos
					n += 1
			if n > 0:
				return c / n
			var fx: float = battle.terrain.fords[0] if not battle.terrain.fords.is_empty() else 1600.0
			return Vector2(fx, battle.road_y(fx))
		"charge":
			if charge_reg != null:
				return charge_reg.center + Vector2(0, -40)
		"gear":
			return gear_aim
		"melee":
			if not battle.corpses.is_empty():
				return battle.corpses.back()[0] # Là où l'on se bat : sang et corps au sol
	var c := Vector2.ZERO
	var n := 0
	for r in battle.regiments:
		if r.engaged and not r.is_dead():
			c += r.center
			n += 1
	if n > 0:
		return c / n
	if not battle.corpses.is_empty():
		return battle.corpses.back()[0] # Plus de contact : là où le dernier soldat est tombé
	return battle.WORLD_SIZE * 0.5
