extends SceneTree
## Test headless de l'audio :
##   godot --headless --path . -s tests/audio_test.gd
## - toutes les musiques et tous les sons d'interface se chargent (GameAudio.load_all) ;
## - aucun nœud audio persistant pendant les tests (le son reste coupé) ;
## - la banque de bataille charge ses familles (dont « swish »), l'ambiance, le cor et la fanfare,
##   sur les bus Musique et Effets ;
## - le suivi de l'état de bataille (pluie, lancement, victoire) fonctionne sans jouer de son ;
## - fondu enchaîné entre deux musiques et branchement automatique des boutons.
## Code de sortie : 0 si tout va bien, 1 sinon.


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


## Fausse bataille : juste les propriétés que BattleAudio lit.
class FakeBattle extends Node2D:
	var state := 0
	var raining := false
	var retreated := false
	var camera: Camera2D = null


var counter := ErrorCounter.new()
var fails: Array[String] = []
var frame := 0
var fake: FakeBattle
var ba: BattleAudio
var ga: GameAudio


func check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)
		print("ÉCHEC : ", msg)


func _initialize() -> void:
	AudioServer.set_bus_mute(0, true) # Aucun son pendant les tests
	OS.add_logger(counter)
	check(GameOptions.is_test_run(), "is_test_run() devrait être vrai sous -s")

	var missing := GameAudio.load_all()
	check(missing.is_empty(), "sons introuvables : %s" % ", ".join(missing))
	for k in GameAudio.MUSIC:
		var s := GameAudio.stream(GameAudio.MUSIC[k][0])
		check(s != null and s.get_length() > 5.0, "musique « %s » vide ou trop courte" % k)
	check(GameAudio.instance() == null, "GameAudio ne doit pas exister pendant les tests")
	GameAudio.music("menu") # Sans effet, sans erreur
	GameAudio.feedback(true)

	fake = FakeBattle.new()
	root.add_child(fake)
	ba = BattleAudio.new()
	ba.battle = fake
	fake.add_child(ba)


func _process(_delta: float) -> bool:
	frame += 1
	match frame:
		1:
			_test_battle_audio()
		2:
			fake.raining = true
			fake.state = 1 # Lancement de la bataille
		3:
			check(ba.raining, "la pluie n'est pas suivie")
			check(ba.last_state == 1, "l'état de bataille n'est pas suivi")
			fake.state = 2 # Victoire
		4:
			check(ba.last_state == 2, "la victoire n'est pas vue")
			fake.queue_free()
			_test_game_audio_node()
		6:
			check(ga.current == "menu" and ga.players[ga.active].stream != null, "musique du menu non lancée")
			var first := ga.active
			ga.play_music("campaign")
			check(ga.active != first and ga.current == "campaign", "pas de fondu vers la musique de carte")
			ga.play_music("campaign") # Même musique : rien ne change
			check(ga.current == "campaign", "relance inutile de la même musique")
			check(not ga.players[0].playing and not ga.players[1].playing, "musique lancée pendant les tests")
			var b := Button.new()
			root.add_child(b)
			check(b.has_meta("ui_audio") and b.pressed.is_connected(ga._on_pressed), "bouton non branché sur les sons d'interface")
			b.queue_free()
			ga.queue_free()
		8:
			_finish()
			return true
	return false


func _test_battle_audio() -> void:
	check(not ba.enabled, "BattleAudio doit rester muet pendant les tests")
	for bank in BattleAudio.BANKS:
		check(not (ba.streams.get(bank, []) as Array).is_empty(), "banque « %s » vide" % bank)
	check((ba.streams["swish"] as Array).size() == 3, "banque « swish » incomplète")
	for k in BattleAudio.AMBIENCE:
		check(ba.ambience.has(k), "ambiance « %s » non chargée" % k)
	check(ba.horn != null and ba.fanfare != null, "cor ou fanfare non chargés")
	check(ba.music != null, "musique de bataille non chargée")
	for p in ba.find_children("*", "AudioStreamPlayer", false, false):
		var player := p as AudioStreamPlayer
		check(player.bus == GameOptions.BUS_SFX or player.bus == GameOptions.BUS_MUSIC, "lecteur hors des bus Musique / Effets")
		check(not player.playing, "un son joue pendant les tests")
	check(AudioServer.get_bus_index(GameOptions.BUS_MUSIC) >= 0 and AudioServer.get_bus_index(GameOptions.BUS_SFX) >= 0, "bus Musique / Effets absents")
	check(AudioServer.is_bus_mute(0), "bus Master non coupé pendant les tests")
	print("Sons de bataille chargés : %d" % ba.loaded_count())
	check(ba.loaded_count() >= 40, "seulement %d sons de bataille" % ba.loaded_count())


## Nœud créé à la main (instance() refuse pendant les tests) pour vérifier fondu et boutons.
func _test_game_audio_node() -> void:
	ga = GameAudio.new()
	ga.play_music("menu") # Demandée avant l'entrée dans l'arbre : jouée au _ready
	root.add_child(ga)
	for p in ga.players:
		check(p.bus == GameOptions.BUS_MUSIC, "musique hors du bus Musique")
	for v in ga.ui_voices:
		check(v.bus == GameOptions.BUS_SFX, "son d'interface hors du bus Effets")


func _finish() -> void:
	for e in counter.errors:
		fails.append("erreur moteur : " + e)
	if fails.is_empty():
		print("TEST AUDIO OK")
		quit(0)
	else:
		print("TEST AUDIO ÉCHOUÉ (%d)" % fails.size())
		quit(1)
