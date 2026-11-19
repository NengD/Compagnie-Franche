extends SceneTree
## Test headless du rendu de la carte du monde (heraldry.gd, map_sky.gd, map_icons.gd et la partie
## dessin de campaign_map.gd) :
##   godot --headless --path . -s tests/map_visuals_test.gd
## - armoiries : tirage stable d'après la graine, valeurs valides, sauvegarde et relecture,
##   ancienne sauvegarde (version 9) sans armoiries, valeurs abîmées remplacées, blason ;
## - saisons : pas de neige au premier printemps, neige en hiver qui fond au printemps suivant,
##   feuillage roux en automne ; nuit, aube, brouillard du matin ;
## - la scène de la carte : chaque sorte de groupe dessinée, traces de marche, sens de marche,
##   nuit, pluie, neige et brouillard sans erreur, saison passée au shader et à la mini-carte,
##   onglet Compagnie (boutons des armoiries).
## N'écrit que dans user://test_visuels_*.json. Code de sortie : 0 si tout va bien, 1 sinon.


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
var frame := 0
var map: Node


func check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)
		print("ÉCHEC : ", msg)


func _initialize() -> void:
	AudioServer.set_bus_mute(0, true)
	OS.add_logger(counter)
	CampaignState.slot_prefix = "user://test_visuels"
	CampaignState.use_slot(1)
	CampaignState.event_chance = 0.0
	_test_arms()
	_test_sky()
	var c := CampaignState.new_game(777)
	CampaignState.current = c
	map = (load("res://scenes/campaign.tscn") as PackedScene).instantiate()
	map.auto_launch = false
	root.add_child(map)


func _test_arms() -> void:
	var a := Heraldry.random(42)
	check(a == Heraldry.random(42), "armoiries : même graine, mêmes armoiries")
	var seen := {}
	for s in 40:
		var r := Heraldry.random(s)
		check(str(r["field"]) in Heraldry.FIELDS and str(r["charge"]) in Heraldry.CHARGES, "armoiries : partition et meuble valides")
		check((r["colors"] as Array).size() == 3, "armoiries : trois couleurs")
		check(not Color.html(str(r["colors"][0])).is_equal_approx(Color.html(str(r["colors"][1]))), "armoiries : champ et seconde couleur différents")
		seen[str(r["field"]) + str(r["charge"])] = true
	check(seen.size() >= 8, "armoiries variées (%d combinaisons sur 40)" % seen.size())
	# Nouvelle campagne : armoiries tirées, sauvegardées, relues
	var c := CampaignState.new_game(1234)
	check(not c.arms.is_empty() and Heraldry.sanitize(c.arms, 1) == c.arms, "nouvelle campagne : armoiries valides")
	c.arms = {"field": "quarterly", "charge": "star", "colors": ["#b3201b", "#e8c040", "#ecebe4"]}
	var d: Dictionary = JSON.parse_string(JSON.stringify(c.to_dict()))
	var l := CampaignState.from_dict(d)
	check(l != null and l.arms == c.arms, "armoiries sauvegardées et relues")
	# Version 9 : pas d'armoiries -> tirées d'après la graine
	d.erase("arms")
	d["version"] = 9
	var old := CampaignState.from_dict(d)
	check(old != null and old.arms == Heraldry.random(old.rng.seed), "sauvegarde de version 9 : armoiries d'après la graine")
	# Valeurs abîmées
	var bad := Heraldry.sanitize({"field": "licorne", "charge": "star", "colors": ["rouge", 3]}, 5)
	check(str(bad["field"]) in Heraldry.FIELDS and str(bad["charge"]) == "star" and (bad["colors"] as Array).size() == 3, "armoiries abîmées : réparées")
	var bz := Heraldry.blazon({"field": "chevron", "charge": "tower", "colors": ["#b3201b", "#ecebe4", "#e8c040"]})
	check(bz == "De gueules au chevron d'argent, à la tour d'or", "blason : %s" % bz)
	check(Heraldry.blazon({"field": "plain", "charge": "none", "colors": ["#e8c040", "#2448a8", "#2448a8"]}) == "D'or", "blason : écu plein")


func _test_sky() -> void:
	check(float(MapSky.season(1, 8.0)["snow"]) == 0.0, "premier printemps : pas de neige")
	check(float(MapSky.season(100, 12.0)["snow"]) > 0.99, "hiver : neige")
	check(float(MapSky.season(91, 1.0)["snow"]) < 0.2, "hiver : la neige tombe peu à peu")
	var melt := float(MapSky.season(121, 12.0)["snow"])
	check(melt > 0.5 and melt < 1.0, "printemps suivant : la neige fond (%.2f)" % melt)
	check(float(MapSky.season(127, 12.0)["snow"]) == 0.0, "printemps suivant : neige fondue")
	check(float(MapSky.season(75, 12.0)["autumn"]) > 0.99, "automne : feuillage roux")
	check(float(MapSky.season(45, 12.0)["autumn"]) == 0.0 and float(MapSky.season(45, 12.0)["summer"]) > 0.99, "été : prés secs, pas de roux")
	check(MapSky.night(23.0) == 1.0 and MapSky.night(13.0) == 0.0, "nuit noire à 23 h, plein jour à 13 h")
	check(MapSky.daylight(13.0) == Color.WHITE and MapSky.daylight(0.0).v < 0.75, "lumière : jour blanc, nuit sombre")
	check(MapSky.fog(70, 6.5, false) > 0.8 and MapSky.fog(70, 14.0, true) == 0.0, "brouillard : le matin, pas l'après-midi")
	check(MapSky.fog(40, 7.0, false) < MapSky.fog(70, 7.0, false), "brouillard plus épais en automne qu'en été")


func _process(_delta: float) -> bool:
	frame += 1
	var c: CampaignState = map.state
	var ow := c.overworld
	match frame:
		3:
			map.paused = true
			ow.inside = -1
			map.town_open = false
			# Un groupe de chaque sorte près de la compagnie
			for q in ow.parties.duplicate():
				ow.remove(c, q)
			var k := 0
			for kind in ["caravan", "villagers", "bandits", "deserters", "patrol"]:
				var q := Party.new()
				q.kind = kind
				q.faction = 0 if kind in ["patrol", "deserters"] else -1
				q.troops = [{"type": "spear", "men": 20 + k * 7, "xp": 0.0}]
				q.pos = ow.player.pos + Vector2(-100 + k * 50, 60)
				ow.add(c, q)
				k += 1
			map.update_trails()
			var west: Party = ow.parties[0]
			for s in 5:
				west.pos += Vector2(-12, 0)
				map.update_trails()
			check((map.trails[west.id] as Array).size() == 6, "trace de marche : un point par pas (%d)" % (map.trails[west.id] as Array).size())
			check(map.face_of(west) == -1.0, "un groupe qui va vers l'ouest regarde l'ouest")
			west.pos += Vector2(500, 0) # Saut : la trace repart de zéro
			map.update_trails()
			check((map.trails[west.id] as Array).size() == 1, "trace effacée après un saut")
			map.center_on(ow.player.pos)
		6: # Nuit d'hiver sous la neige
			c.day = 100
			ow.hour = 23.0
			c.world.raining = true
			map.update_light()
			var mat: ShaderMaterial = map.ground_mat
			check(float(mat.get_shader_parameter("snow")) > 0.99, "shader du terrain : neige en hiver")
			var mini: ShaderMaterial = map.minimap.ground
			check(float(mini.get_shader_parameter("snow")) > 0.99, "mini-carte : neige en hiver")
		9: # Pluie d'été, puis brouillard d'automne
			c.day = 50
			ow.hour = 15.0
			map.update_light()
			check(float((map.ground_mat as ShaderMaterial).get_shader_parameter("snow")) == 0.0, "shader du terrain : plus de neige en été")
		12:
			c.day = 70
			ow.hour = 6.5
			c.world.raining = false
			map.update_light()
			check(float((map.minimap.ground as ShaderMaterial).get_shader_parameter("autumn")) > 0.99, "mini-carte : couleurs d'automne")
		15: # Onglet Compagnie : les boutons changent les armoiries
			map.toggle_view("company")
			var before: Dictionary = c.arms.duplicate(true)
			var pressed := 0
			for b in _buttons(map.box):
				if b.text in ["Partition", "Meuble", "Champ"]:
					b.pressed.emit()
					pressed += 1
			check(pressed == 3, "onglet Compagnie : boutons des armoiries (%d)" % pressed)
			check(c.arms != before, "les boutons changent les armoiries")
			check(Heraldry.sanitize(c.arms, 1) == c.arms, "armoiries toujours valides après changement")
			var saved := CampaignState.load_game()
			check(saved != null and saved.arms == c.arms, "armoiries sauvegardées après changement")
		20:
			check(counter.errors.is_empty(), "aucune erreur : %s" % str(counter.errors))
			root.remove_child(map)
			map.free()
			CampaignState.current = null
			CampaignState.delete_slot(1)
			if fails.is_empty():
				print("Rendu de la carte : OK")
				quit(0)
			else:
				print("%d échec(s)" % fails.size())
				quit(1)
	return false


func _buttons(n: Node) -> Array[Button]:
	var out: Array[Button] = []
	for ch in n.get_children():
		if ch is Button:
			out.append(ch)
		out.append_array(_buttons(ch))
	return out
