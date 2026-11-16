extends SceneTree
## Test des effets visuels de bataille (battle_effects.gd), sans fenêtre :
##   godot --headless --path . -s tests/effects_test.gd
## - la même graine donne exactement la même bataille avec les effets complets, réduits ou
##   aucun (les effets ne tirent jamais le rng de la simulation) ;
## - les particules restent sous leur plafond, et des effets apparaissent bien (sang, pluie,
##   éclaboussures, fumée) ;
## - l'option « effets » est sauvegardée et relue (valeur inconnue → complets).
## Code de sortie : 0 si tout va bien, 1 sinon.

const TestPlayer := preload("res://tests/test_player.gd")
const OPTIONS_TEST := "user://test_effets_options.cfg"
const STEP := 0.05
const STEPS := 2400 ## 120 s de bataille simulée (l'IA peut attendre en défense avant le contact)
const SEED := 4242

var scene: PackedScene
var fails: Array[String] = []


func _initialize() -> void:
	AudioServer.set_bus_mute(0, true) # Aucun son pendant les tests
	GameOptions.path = OPTIONS_TEST
	GameOptions.loaded = false
	GameOptions.ensure_loaded()
	scene = load("res://scenes/main.tscn")


func check(ok: bool, what: String) -> void:
	if not ok:
		fails.append(what)


func _process(_delta: float) -> bool:
	var sigs := {}
	for level in GameOptions.EFFECTS:
		for kind in ["river", "village"]:
			sigs["%s/%s" % [level, kind]] = run_battle(level, kind)
	for kind in ["river", "village"]:
		var ref: String = sigs["full/%s" % kind]
		for level in ["reduced", "none"]:
			check(sigs["%s/%s" % [level, kind]] == ref, "%s : la bataille diffère avec les effets « %s »" % [kind, level])
	var same := fails.filter(func(f: String): return "diffère" in f).is_empty()
	print("Déterminisme avec ou sans effets : %s" % ("OK" if same else "ÉCHEC"))
	check_options()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(OPTIONS_TEST))
	GameOptions.path = GameOptions.DEFAULT_PATH
	GameOptions.loaded = false
	if fails.is_empty():
		print("Effets visuels : OK")
		quit(0)
	else:
		for f in fails:
			printerr("ÉCHEC : ", f)
		quit(1)
	return true


## Joue une bataille sous la pluie et renvoie sa signature (survivants et positions).
func run_battle(level: String, kind: String) -> String:
	GameOptions.effects = level
	var b := scene.instantiate()
	b.set("seed_override", SEED)
	b.set("terrain_override", kind)
	b.set("difficulty", "normal")
	root.add_child(b)
	var fx: BattleEffects = b.renderer.effects
	var player := TestPlayer.new("tactical")
	b.raining = true
	b.start_battle()
	var max_parts := 0
	var seen := {}
	for i in STEPS:
		if b.state != b.State.BATTLE:
			break
		player.update(b)
		b.simulate(STEP)
		# Vue : tout le champ de bataille (la caméra ne bouge pas en mode test)
		b.camera.zoom = Vector2(0.4, 0.4)
		b.camera.position = b.WORLD_SIZE * 0.5
		b.renderer.update_effects(STEP)
		max_parts = maxi(max_parts, fx.parts.size())
		for d in fx.parts:
			seen[int(d[6])] = true
	check(max_parts <= fx.cap(), "%s/%s : %d particules (plafond %d)" % [level, kind, max_parts, fx.cap()])
	check(fx.stains.size() <= BattleEffects.MAX_STAINS, "%s/%s : trop de taches de sang" % [level, kind])
	if level == "none":
		check(max_parts == 0 and fx.stains.is_empty(), "%s : des effets avec le niveau « aucun »" % kind)
	else:
		check(seen.has(BattleEffects.BLOOD), "%s/%s : pas de sang" % [level, kind])
		check(seen.has(BattleEffects.RING), "%s/%s : pas d'impact de pluie" % [level, kind])
		check(not fx.puddles.is_empty() and fx.wet > 0.5, "%s/%s : pas de flaques" % [level, kind])
		if kind == "village":
			check(seen.has(BattleEffects.SMOKE), "%s : pas de fumée au village" % level)
	var sig := "%d %.1f" % [b.battle_time / STEP, b.battle_time]
	for s in b.soldiers:
		sig += " %d:%.2f,%.2f" % [int(s.alive), s.pos.x, s.pos.y]
	print("  %s / %s : %d particules au plus, %d taches" % [level, kind, max_parts, fx.stains.size()])
	root.remove_child(b)
	b.free()
	return sig


func check_options() -> void:
	GameOptions.effects = "reduced"
	check(GameOptions.save_options(), "écriture de options.cfg")
	GameOptions.reset_all()
	check(GameOptions.effects == "full", "reset_all remet les effets complets")
	GameOptions.load_options()
	check(GameOptions.effects == "reduced", "effets réduits rechargés")
	var cfg := ConfigFile.new()
	cfg.load(OPTIONS_TEST)
	cfg.set_value("affichage", "effets", "nimporte")
	cfg.save(OPTIONS_TEST)
	GameOptions.load_options()
	check(GameOptions.effects == "full", "valeur d'effets inconnue → complets")
