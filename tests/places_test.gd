extends SceneTree
## Test headless des lieux de la carte (map_places.gd) et des portraits (portrait.gd) :
##   godot --headless --path . -s tests/places_test.gd
## - portraits : même graine, même portrait ; variété ; pièces valides ; capitaine et compagnons
##   stables après sauvegarde et relecture ; surnoms (Barbe-Grise, le Borgne, Frère) ; femmes sans barbe ;
## - lieux : taille (cité, ville, village) ; la bannière change avec le propriétaire (ville prise,
##   château devenu le fief de la compagnie : ses armoiries) ; un village suit sa ville ; siège
##   d'une ville et du fief (assiégeant) ;
## - la scène de la carte : lieux dessinés (siège compris), portraits dans l'onglet Compagnie
##   (capitaine, compagnon) et dans la fenêtre de rencontre, sans erreur.
## N'écrit que dans user://test_lieux_*.json. Code de sortie : 0 si tout va bien, 1 sinon.


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
	CampaignState.slot_prefix = "user://test_lieux"
	CampaignState.use_slot(1)
	CampaignState.event_chance = 0.0
	_test_portraits()
	_test_places()
	var c := CampaignState.new_game(777)
	CampaignState.current = c
	map = (load("res://scenes/campaign.tscn") as PackedScene).instantiate()
	map.auto_launch = false
	root.add_child(map)


func _test_portraits() -> void:
	var a := Portrait.make(42, {"role": "sergeant"})
	check(a == Portrait.make(42, {"role": "sergeant"}), "portrait : même graine, même portrait")
	check(a != Portrait.make(43, {"role": "sergeant"}), "portrait : autre graine, autre portrait")
	var faces := {}
	for s in 60:
		var p := Portrait.make(s, {"role": "soldier"})
		check(str(p["shape"]) in Portrait.SHAPES and str(p["hair"]) in Portrait.HAIRS and str(p["beard"]) in Portrait.BEARDS, "portrait : pièces valides")
		check(str(p["headgear"]) in Portrait.ROLE_GEAR["soldier"] and str(p["scar"]) in Portrait.SCARS, "portrait : couvre-chef du rôle")
		check(str(p["skin"]) in Portrait.SKINS and Color.html_is_valid(str(p["hair_color"])), "portrait : couleurs valides")
		faces[str([p["shape"], p["skin"], p["hair"], p["beard"], p["headgear"]])] = true
	check(faces.size() >= 40, "portraits variés (%d sur 60)" % faces.size())
	var w := Portrait.make(5, {"role": "surgeon", "name": "Ysabeau la Savante"})
	check(bool(w["woman"]) and str(w["beard"]) == "none" and str(w["hair"]) in Portrait.WOMAN_HAIRS, "portrait : une femme, sans barbe")
	check(str(Portrait.make(1, {"name": "Odon Barbe-Grise"})["beard"]) == "full", "surnom : Barbe-Grise")
	check(str(Portrait.make(1, {"name": "Aymeric le Borgne"})["scar"]) == "eyepatch", "surnom : le Borgne")
	check(str(Portrait.make(1, {"name": "Frère Clément", "role": "surgeon"})["hair"]) == "tonsure", "surnom : Frère")
	check(Portrait.make(1, {"name": "Arnaud le Roux"})["hair_color"] == Portrait.HAIR_COLORS["roux"], "surnom : le Roux")
	# Capitaine et compagnons : stables après sauvegarde et relecture, tabard aux armoiries
	var c := CampaignState.new_game(31337)
	c.companions.list.append(Companions.make("scout", Companions.offer_name(c, "scout")))
	var cap := Portrait.of_captain(c)
	var comp := Portrait.of_companion(c, c.companions.list[0])
	check(cap.has("tabard") and cap["tabard"][0] == Heraldry.color(c.arms, 0).to_html(false), "capitaine : tabard aux armoiries")
	var l := CampaignState.from_dict(JSON.parse_string(JSON.stringify(c.to_dict())))
	check(l != null and Portrait.of_captain(l) == cap, "capitaine : même portrait après relecture")
	check(l != null and Portrait.of_companion(l, l.companions.list[0]) == comp, "compagnon : même portrait après relecture")
	check(Portrait.of_companion(c, {"kind": "scout", "name": Companions.offer_name(c, "scout")}) == comp, "compagnon : l'offre a le visage de celui qu'on engage")
	check(Portrait.of_captain(CampaignState.new_game(4)) != Portrait.of_captain(CampaignState.new_game(5)), "capitaine : autre campagne, autre visage")
	var q := Party.new()
	q.id = 12
	q.kind = "patrol"
	q.faction = 2
	var pq := Portrait.of_party(q)
	check(pq == Portrait.of_party(q) and str(pq["headgear"]) in Portrait.ROLE_GEAR["soldier"], "groupe rencontré : portrait stable d'un soldat")
	check(str(pq["clothes"]) == (CampaignState.FACTIONS[2]["color"] as Color).darkened(0.25).to_html(false), "patrouille : habit aux couleurs de sa faction")


func _test_places() -> void:
	for f in CampaignState.FACTIONS:
		check(MapPlaces.size_of(int(f["capital"])) == MapPlaces.SIZE_CITY, "capitale : une cité")
	check(MapPlaces.size_of(0) == MapPlaces.SIZE_TOWN, "Valombre : une ville")
	var vil := MapData.place_named("Les Aulnes")
	check(MapPlaces.size_of(vil) == MapPlaces.SIZE_VILLAGE, "Les Aulnes : un village")
	var c := CampaignState.new_game(2024)
	var w := c.world
	w.armies.clear()
	# Ville prise : la bannière change de couleur ; ses villages suivent
	var b0 := MapPlaces.banner(c, 0)
	check(int(b0["owner"]) == 0 and (b0["color"] as Color).is_equal_approx(CampaignState.FACTIONS[0]["color"]), "Valombre : bannière du Comté")
	check(int(MapPlaces.banner(c, vil)["owner"]) == 0, "Les Aulnes : fanion de Valombre")
	w.owner[0] = 1
	var b1 := MapPlaces.banner(c, 0)
	check(int(b1["owner"]) == 1 and (b1["color"] as Color).is_equal_approx(CampaignState.FACTIONS[1]["color"]), "Valombre prise : bannière de la Baronnie")
	check(int(MapPlaces.banner(c, vil)["owner"]) == 1, "Les Aulnes : le village suit sa ville")
	# Château devenu le fief de la compagnie : ses armoiries
	var castle := MapData.place_named("Tour du Guet")
	check(int(MapPlaces.banner(c, castle)["owner"]) == 0 and (MapPlaces.banner(c, castle)["arms"] as Dictionary).is_empty(), "Tour du Guet : bannière unie du Comté")
	c.fiefs.owners[str(castle)] = Fiefs.PLAYER
	var bf := MapPlaces.banner(c, castle)
	check(int(bf["owner"]) == Fiefs.PLAYER and bf["arms"] == c.arms, "fief : bannière aux armoiries de la compagnie")
	c.fiefs.owners[str(castle)] = 2
	check(int(MapPlaces.banner(c, castle)["owner"]) == 2, "château pris par la Ligue : sa bannière")
	# Sièges : ville, puis fief
	check(MapPlaces.besieger(c, 1) == -1, "Saint-Aubin : pas de siège au départ")
	w.declare_war(c, 1, 0)
	var army := w.add_army(1, 2, 1, 600, "siege")
	army.mode = "siege"
	army.target = 1
	check(MapPlaces.besieger(c, 1) == 1, "Saint-Aubin assiégée par la Baronnie")
	c.fiefs.owners[str(castle)] = Fiefs.PLAYER
	c.fiefs.held.append({"place": castle, "garrison": [], "since": 1, "from": 0, "siege": {"faction": 2, "men": 120, "days": 3}})
	check(MapPlaces.besieger(c, castle) == 2, "fief assiégé par la Ligue")


func _process(_delta: float) -> bool:
	frame += 1
	var c: CampaignState = map.state
	var ow := c.overworld
	match frame:
		3: # Lieux sous toutes leurs formes : ville prise et assiégée, fief assiégé
			map.paused = true
			c.world.armies.clear()
			c.world.declare_war(c, 1, 0)
			var army := c.world.add_army(1, 2, 1, 600, "siege")
			army.mode = "siege"
			army.target = 1
			c.world.owner[0] = 2
			var castle := MapData.place_named("Tour du Guet")
			c.fiefs.owners[str(castle)] = Fiefs.PLAYER
			c.fiefs.held.append({"place": castle, "garrison": [], "since": 1, "from": 0, "siege": {"faction": 1, "men": 120, "days": 3}})
			c.companions.list.append(Companions.make("surgeon", Companions.offer_name(c, "surgeon")))
			map.cam.zoom = Vector2(0.6, 0.6)
			map.center_on(MapData.place_pos(1))
			map.queue_redraw()
		6:
			map.view = "company"
			map.refresh_ui()
		8:
			var views := find_views(map.box)
			check(views.size() >= 2, "onglet Compagnie : portraits du capitaine et du compagnon (%d)" % views.size())
			if views.size() >= 1:
				check(views[0].data == Portrait.of_captain(c), "onglet Compagnie : le premier portrait est celui du capitaine")
			map.view = ""
			var q := Party.new()
			q.kind = "bandits"
			q.troops = [{"type": "spear", "men": 20, "xp": 0.0}]
			q.pos = ow.player.pos + Vector2(30, 0)
			ow.add(c, q)
			map.open_contact(q)
			map.refresh_ui()
		10:
			check(find_views(map.box).size() == 1, "fenêtre de rencontre : portrait du chef")
			var panel := EncounterPanel.new()
			panel.setup(c, ow.player, map.contact)
			root.add_child(panel)
			check(panel.find_child("Portrait", true, false) is Portrait.View, "panneau de rencontre : portrait")
			panel.queue_free()
		14:
			for e in counter.errors:
				fails.append("erreur : " + e)
			root.remove_child(map)
			map.free()
			CampaignState.current = null
			CampaignState.delete_slot(1)
			if fails.is_empty():
				print("Lieux et portraits : OK")
			else:
				print("Lieux et portraits : %d échec(s)" % fails.size())
			quit(0 if fails.is_empty() else 1)
	return false


func find_views(n: Node) -> Array[Portrait.View]:
	var out: Array[Portrait.View] = []
	for k in n.get_children():
		if k is Portrait.View:
			out.append(k)
		out.append_array(find_views(k))
	return out
