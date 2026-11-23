extends SceneTree
## Test des traces de bataille et des morts (battle_field.gd, battle_renderer.gd), sans fenêtre :
##   godot --headless --path . -s tests/field_test.gd
## - une vraie bataille laisse des débris, des flèches plantées et de la boue, sous leurs plafonds ;
## - les plafonds tiennent sous un déluge artificiel (débris, flèches, boue), au niveau complet
##   comme réduit ; le niveau « aucun » ne garde que les étendards tombés ;
## - un régiment qui fuit perd son étendard (au sol, plus au-dessus de lui) et ses fuyards jettent
##   leurs armes ; un régiment rallié relève le sien ;
## - les quatre manières de tomber existent ; poses de chute cohérentes ;
## - aucune erreur de script pendant des images dessinées (corps, débris, étendards tombés).
## Code de sortie : 0 si tout va bien, 1 sinon.

const TestPlayer := preload("res://tests/test_player.gd")
const STEP := 0.05
const SEED := 4242


## Compte les erreurs émises par le moteur ou les scripts pendant le test.
class ErrorCounter extends Logger:
	var errors: Array[String] = []
	var mutex := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING:
			return
		mutex.lock()
		errors.append("%s:%d (%s) %s" % [file, line, function, rationale if rationale != "" else code])
		mutex.unlock()


var counter := ErrorCounter.new()
var fails: Array[String] = []
var battle: Node
var frame := 0
var draw_frames := 0


func _initialize() -> void:
	AudioServer.set_bus_mute(0, true) # Aucun son pendant les tests
	OS.add_logger(counter)
	GameOptions.ensure_loaded()
	GameOptions.effects = "full"


func check(ok: bool, what: String) -> void:
	if not ok:
		fails.append(what)


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 1:
		check_poses()
		play_battle()
		return false
	if frame < 8:
		return false # Quelques images dessinées avec débris, corps et étendards tombés
	check(counter.errors.is_empty(), "erreurs pendant le rendu : %s" % [counter.errors.slice(0, 5)])
	root.remove_child(battle)
	battle.free()
	check_caps()
	if fails.is_empty():
		print("Traces de bataille : OK")
		quit(0)
	else:
		for f in fails:
			printerr("ÉCHEC : ", f)
		quit(1)
	return true


## Une bataille de deux minutes : des traces apparaissent, plafonnées ; puis une déroute forcée.
func play_battle() -> void:
	battle = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	battle.set("seed_override", SEED)
	battle.set("terrain_override", "plain")
	battle.set("difficulty", "normal")
	root.add_child(battle)
	var renderer: BattleRenderer = battle.renderer
	var field := renderer.field
	var player := TestPlayer.new("tactical")
	battle.start_battle()
	var kinds := {}
	for i in 2400:
		if battle.state != battle.State.BATTLE:
			break
		player.update(battle)
		battle.simulate(STEP)
		battle.camera.zoom = Vector2(0.4, 0.4)
		battle.camera.position = battle.WORLD_SIZE * 0.5
		renderer.update_effects(STEP)
		check(field.debris.size() <= BattleField.MAX_DEBRIS, "trop de débris : %d" % field.debris.size())
		check(field.stuck.size() <= BattleField.MAX_STUCK, "trop de flèches plantées : %d" % field.stuck.size())
		check(field.mud.size() <= BattleField.MAX_MUD, "trop de boue : %d" % field.mud.size())
	var sim: BattleSim = battle.sim
	for c in sim.corpses:
		kinds[renderer.death_kind(c)] = true
	print("  %d corps, %d débris, %d flèches plantées, %d plaques de boue, %d étendards tombés" % [
		sim.corpses.size(), field.debris.size(), field.stuck.size(), field.mud.size(), field.fallen.size()])
	check(not sim.corpses.is_empty(), "aucun mort dans la bataille")
	check(not field.debris.is_empty(), "aucune arme au sol après la bataille")
	check(not field.stuck.is_empty(), "aucune flèche plantée après la bataille")
	check(not field.mud.is_empty(), "aucune boue sous les mêlées")
	check(field.mud.size() == field.mud_cells.size(), "boue : index des cases désaccordé")
	for k in [BattleRenderer.DEATH_SIDE, BattleRenderer.DEATH_BACK, BattleRenderer.DEATH_FORWARD, BattleRenderer.DEATH_KNEEL]:
		check(kinds.has(k), "manière de tomber jamais vue : %d" % k)
	# Déroute forcée d'un régiment encore debout
	var r: Regiment = null
	for o in sim.regiments:
		if not o.is_dead() and not o.routing and not sim.is_secret(o) and o.alive_n >= 4:
			r = o
			break
	check(r != null, "plus aucun régiment debout pour la déroute")
	if r == null:
		return
	var fallen_before := field.fallen.size()
	var debris_before := field.debris.size()
	field.debris.clear() # Place pour les armes jetées (le plafond est peut-être atteint)
	sim.start_rout(r)
	renderer.update_effects(STEP)
	check(field.routed.has(r), "le régiment en déroute garde son étendard")
	check(field.fallen.size() == fallen_before + 1 and field.fallen.back()[1] == r, "pas d'étendard tombé pour le régiment en déroute")
	check(field.debris.size() >= 1, "les fuyards ne jettent pas leurs armes (%d débris avant)" % debris_before)
	# Ralliement : il relève un étendard, l'ancien reste au sol
	r.routing = false
	renderer.update_effects(STEP)
	check(not field.routed.has(r), "le régiment rallié n'a pas d'étendard")
	check(field.fallen.size() == fallen_before + 1, "l'étendard tombé a disparu au ralliement")
	sim.start_rout(r)
	renderer.update_effects(STEP)
	# Vue sur la déroute pour les images dessinées suivantes
	battle.camera.zoom = Vector2(2.0, 2.0)
	battle.camera.position = r.center
	renderer.queue_redraw()


## Plafonds sous un déluge artificiel, par niveau d'effets.
func check_caps() -> void:
	var b: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	b.set("seed_override", SEED)
	b.set("terrain_override", "plain")
	root.add_child(b)
	var field: BattleField = b.renderer.field
	for level: String in ["full", "reduced", "none"]:
		GameOptions.effects = level
		field.update(0.01)
		for i in 3000:
			field.drop(Vector2(10 + i % 300, 10 + floori(i / 300.0) * 7), "spear", Color.RED, 1.0)
			field.trample(Vector2(20 + (i % 100) * 16, 20 + floori(i / 100.0) * 16), 0.3)
			b.sim.sound_played.emit("swish", Vector2(30 + i % 500, 40 + floori(i / 500.0) * 9))
		var full: bool = level == "full"
		var md := BattleField.MAX_DEBRIS if full else BattleField.MAX_DEBRIS_REDUCED
		var ms := BattleField.MAX_STUCK if full else BattleField.MAX_STUCK_REDUCED
		var mm := BattleField.MAX_MUD if full else BattleField.MAX_MUD_REDUCED
		if level == "none":
			check(field.debris.is_empty() and field.stuck.is_empty(), "niveau « aucun » : des traces restent")
		else:
			check(field.debris.size() == md, "%s : %d débris (plafond %d)" % [level, field.debris.size(), md])
			check(field.stuck.size() == ms, "%s : %d flèches plantées (plafond %d)" % [level, field.stuck.size(), ms])
			check(field.mud.size() == mm and field.mud_cells.size() == mm, "%s : %d plaques de boue (plafond %d)" % [level, field.mud.size(), mm])
		field.debris.clear()
		field.stuck.clear()
		field.mud.clear()
		field.mud_cells.clear()
	GameOptions.effects = "full"
	root.remove_child(b)
	b.free()


## Poses de chute : debout au départ, couchées (rotation d'un quart de tour ou raccourci) à la fin.
func check_poses() -> void:
	for lie in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		var p0: Array = BattleRenderer.fall_pose(lie, 0.0)
		check(is_zero_approx(float(p0[0])) and is_equal_approx(float(p0[1]), 1.0), "pose de départ pas debout : %s" % [lie])
		var p1: Array = BattleRenderer.fall_pose(lie, 1.0)
		check(absf(float(p1[0])) > 1.4 or absf(float(p1[1])) < 0.6, "corps pas couché à la fin de sa chute : %s" % [lie])
