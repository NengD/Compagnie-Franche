extends SceneTree
## Test de performance : bataille d'escarmouche à deux fois les effectifs habituels (chaque régiment
## est doublé d'un second, placé derrière lui). Mesure :
##   1. le temps d'une étape de simulation (battle.simulate(0.05)) pendant l'approche puis la mêlée ;
##   2. le temps d'une image complète (_process de la bataille, dessin, rendu) au cœur de la mêlée.
##
## Lancer :  godot --headless --path . -s tests/perf_test.gd        (simulation ; rendu factice)
##           godot --path . -s tests/perf_test.gd                   (avec fenêtre : vrai coût du rendu)
## Options (après « -- ») :  --seed=N            graine (défaut 12345)
##                           --factor=K          multiplicateur des effectifs (défaut 2)
##                           --frames=N          images mesurées en mêlée (défaut 300)
##                           --out=<fichier>     résultats JSON (défaut user://perf/perf_results.json)
##                           --max-step-ms=X     échec si l'étape moyenne dépasse X ms (défaut : pas de seuil)
## Code de sortie : 0 si la bataille tourne sans erreur (et sous le seuil éventuel), 1 sinon.

const TestPlayer := preload("res://tests/test_player.gd")
const STEP := 0.05
const APPROACH_STEPS := 700 ## 35 s simulées : les lignes se rencontrent
const MELEE_STEPS := 600 ## 30 s de mêlée simulée après la mesure des images


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
var battle: Node
var player := TestPlayer.new("tactical")
var seed_value := 12345
var factor := 2
var frames_wanted := 300
var out_path := "user://perf/perf_results.json"
var max_step_ms := -1.0
var frame := 0
var phase := "setup" ## setup, frames, done
var frame_usec: Array[int] = []
var last_usec := 0
var approach: Dictionary = {}
var melee: Dictionary = {}
var soldiers_start := 0
var soldiers_melee := 0


func _initialize() -> void:
	AudioServer.set_bus_mute(0, true) # Aucun son pendant les tests
	OS.add_logger(counter)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			seed_value = int(a.trim_prefix("--seed="))
		elif a.begins_with("--factor="):
			factor = maxi(1, int(a.trim_prefix("--factor=")))
		elif a.begins_with("--frames="):
			frames_wanted = maxi(10, int(a.trim_prefix("--frames=")))
		elif a.begins_with("--out="):
			out_path = a.trim_prefix("--out=")
		elif a.begins_with("--max-step-ms="):
			max_step_ms = float(a.trim_prefix("--max-step-ms="))
	Engine.max_fps = 0 # Images aussi vite que possible : on mesure le coût, pas la synchro
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	battle = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	battle.set("seed_override", seed_value)
	battle.set("terrain_override", "plain")
	battle.set("difficulty", "normal")
	root.add_child(battle)


func _process(_delta: float) -> bool:
	frame += 1
	if phase == "setup":
		_multiply_armies()
		soldiers_start = battle.soldiers.size()
		print("Perf : graine %d, effectifs x%d : %d soldats, %d régiments" % [seed_value, factor, soldiers_start, battle.regiments.size()])
		battle.start_battle()
		approach = _measure_steps(APPROACH_STEPS)
		soldiers_melee = _alive()
		battle.camera.zoom = Vector2(1, 1)
		battle.camera.position = _fight_center()
		battle.show_help = false
		phase = "frames"
		last_usec = Time.get_ticks_usec()
		return false
	if phase == "frames":
		# Une image entière s'est écoulée depuis le passage précédent (bataille, dessin, rendu)
		var now := Time.get_ticks_usec()
		frame_usec.append(now - last_usec)
		player.update(battle)
		battle.camera.position = _fight_center()
		if frame_usec.size() >= frames_wanted + 5 or battle.state != battle.State.BATTLE:
			frame_usec = frame_usec.slice(5) # Les premières images chauffent les caches
			melee = _measure_steps(MELEE_STEPS)
			phase = "done"
			_finish()
			return true
		last_usec = Time.get_ticks_usec()
	return false


## Ajoute (factor - 1) copies de chaque régiment, rangées derrière l'original.
func _multiply_armies() -> void:
	var originals: Array = battle.regiments.duplicate()
	for k in range(1, factor):
		for r in originals:
			var back := 150.0 * k * (1.0 if r.team == battle.PLAYER else -1.0)
			var at := Vector2(r.center.x, clampf(r.center.y + back, 60.0, battle.WORLD_SIZE.y - 60.0))
			battle.add_regiment(r.team, r.type, at, r.facing)


## Joue n étapes de simulation (avec le joueur simulé) et renvoie leurs statistiques.
func _measure_steps(n: int) -> Dictionary:
	var times: Array[int] = []
	for i in n:
		if battle.state != battle.State.BATTLE:
			break
		player.update(battle)
		var t0 := Time.get_ticks_usec()
		battle.simulate(STEP)
		times.append(Time.get_ticks_usec() - t0)
	return _stats(times)


func _stats(times: Array[int]) -> Dictionary:
	if times.is_empty():
		return {"n": 0, "avg_ms": 0.0, "p95_ms": 0.0, "max_ms": 0.0}
	var sorted := times.duplicate()
	sorted.sort()
	var sum := 0
	for t in times:
		sum += t
	return {
		"n": times.size(),
		"avg_ms": snappedf(sum / 1000.0 / times.size(), 0.001),
		"p95_ms": snappedf(sorted[int(sorted.size() * 0.95)] / 1000.0, 0.001),
		"max_ms": snappedf(sorted[-1] / 1000.0, 0.001),
	}


func _alive() -> int:
	var n := 0
	for s in battle.soldiers:
		if s.alive:
			n += 1
	return n


func _fight_center() -> Vector2:
	var c := Vector2.ZERO
	var n := 0
	for r in battle.regiments:
		if r.engaged and not r.is_dead():
			c += r.center
			n += 1
	return c / n if n > 0 else battle.WORLD_SIZE * 0.5


func _finish() -> void:
	var frames := _stats(frame_usec)
	var all_steps_avg := 0.0
	if approach["n"] + melee["n"] > 0:
		all_steps_avg = (approach["avg_ms"] * approach["n"] + melee["avg_ms"] * melee["n"]) / (approach["n"] + melee["n"])
	var result := {
		"version": str(ProjectSettings.get_setting("application/config/version", "")),
		"date": Time.get_datetime_string_from_system(),
		"display": DisplayServer.get_name(),
		"renderer": RenderingServer.get_video_adapter_name(),
		"seed": seed_value,
		"factor": factor,
		"soldiers_start": soldiers_start,
		"soldiers_alive_melee": soldiers_melee,
		"step_approach": approach,
		"step_melee": melee,
		"step_avg_ms": snappedf(all_steps_avg, 0.001),
		"frame": frames,
		"fps_avg": snappedf(1000.0 / frames["avg_ms"], 0.1) if frames["avg_ms"] > 0.0 else 0.0,
		"battle_time": snappedf(battle.battle_time, 0.1),
	}
	print("Étape de simulation (0,05 s) : approche %.2f ms (p95 %.2f), mêlée %.2f ms (p95 %.2f, max %.2f)" % [
		approach["avg_ms"], approach["p95_ms"], melee["avg_ms"], melee["p95_ms"], melee["max_ms"]])
	print("Image en mêlée (%s, %d soldats vivants) : %.2f ms en moyenne (p95 %.2f), soit %.0f images/s" % [
		DisplayServer.get_name(), soldiers_melee, frames["avg_ms"], frames["p95_ms"], result["fps_avg"]])

	var fails: Array[String] = []
	if not counter.errors.is_empty():
		fails.append("%d erreur(s) moteur/script, dont : %s" % [counter.errors.size(), counter.errors[0]])
	if approach["n"] < 100:
		fails.append("la bataille s'est arrêtée trop tôt (%d étapes)" % approach["n"])
	if max_step_ms > 0.0 and all_steps_avg > max_step_ms:
		fails.append("étape moyenne %.2f ms > seuil %.2f ms" % [all_steps_avg, max_step_ms])

	var path := out_path if out_path.contains("://") or out_path.is_absolute_path() \
		else ProjectSettings.globalize_path("res://").path_join(out_path)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir() if not path.begins_with("user://") \
		else ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		fails.append("impossible d'écrire %s" % path)
	else:
		f.store_string(JSON.stringify(result, "\t") + "\n")
		f.close()
		print("Résultats : ", ProjectSettings.globalize_path(path))

	root.remove_child(battle)
	battle.free()
	if fails.is_empty():
		print("Perf test : OK")
		quit(0)
	else:
		for m in fails:
			printerr("ÉCHEC : ", m)
		quit(1)
