extends SceneTree
## Test headless du confort de jeu :
##   godot --headless --path . -s tests/confort_test.gd
## - file d'ordres (Maj) : les ordres s'enchaînent, un ordre sans Maj remplace la file, une
##   attaque en file part quand la marche est finie, la ligne de front se met en file ;
## - tutoriel guidé de campagne : les étapes avancent quand le joueur fait l'action (recruter,
##   s'équiper, vivres, contrat, marcher, entrer en ville), passer une étape, option désactivée ;
## - infobulles : pièce d'équipement comparée à celle portée (bonne différence en %), chances d'un
##   contrat (plus fort = meilleures chances), compétences et terrain ;
## - manette sur la carte : B ferme, LB / RB changent d'onglet, gâchettes et vitesses, A marche,
##   focus donné au premier bouton de la fenêtre.
## N'utilise pas les fichiers du joueur. Code de sortie : 0 si tout va bien, 1 sinon.

const OPTIONS_TEST := "user://test_confort_options.cfg"
const SLOT_TEST := "user://test_confort_campagne"
const STEP := 0.05


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
var node: Node


func check(ok: bool, msg: String) -> void:
	if not ok:
		fails.append(msg)
		push_warning("ÉCHEC : " + msg)


func _initialize() -> void:
	AudioServer.set_bus_mute(0, true)
	OS.add_logger(counter)
	GameOptions.path = OPTIONS_TEST
	GameOptions.loaded = false
	_remove(OPTIONS_TEST)
	GameOptions.ensure_loaded()
	GameOptions.reset_all()
	CampaignState.slot_prefix = SLOT_TEST
	CampaignState.use_slot(1)
	CampaignState.event_chance = 0.0
	CampaignState.current = null
	_test_gear_tooltip()
	_test_contract_odds()
	_test_other_tooltips()


func _process(_delta: float) -> bool:
	frame += 1
	match frame:
		1:
			node = load("res://scenes/main.tscn").instantiate()
			node.set("seed_override", 7)
			root.add_child(node)
		3:
			_test_queue(node as Battle)
			_free()
		4:
			var c := CampaignState.new_game(5, Difficulty.NORMAL, false, true)
			c.tutorial_step = 0
			c.gold = 3000.0
			c.save()
			CampaignState.current = c
			node = (load("res://scenes/campaign.tscn") as PackedScene).instantiate()
			node.auto_launch = false
			root.add_child(node)
		6:
			_test_guide(node)
			_test_pad(node)
			_free()
		7:
			_finish()
			return true
	return false


func _free() -> void:
	if node != null:
		root.remove_child(node)
		node.free()
		node = null


func _remove(p: String) -> void:
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


# ---------------------------------------------------------------- Infobulles

func _test_gear_tooltip() -> void:
	var entry := {"type": "spear", "men": 20, "xp": 0.0, "gear": ["helmet_1"]}
	var d := Tooltips.gear_delta(entry, "helmet_2")
	# 1,15 / 1,08 = +6,48 % de vie ; 1,10 / 1,05 = +4,76 % de moral
	check(d.size() == 2 and absf(float(d.get("hp", 0.0)) - 6.481) < 0.01 and absf(float(d.get("morale", 0.0)) - 4.762) < 0.01,
		"infobulle d'équipement : mauvaise différence %s" % str(d))
	var t := Tooltips.gear_text(entry, "helmet_2")
	check("+6,5 %" in t and "+4,8 %" in t and "chapels de fer" in t, "infobulle d'équipement : texte %s" % t)
	# Sans pièce portée : le gain est celui de la pièce elle-même
	var w := Tooltips.gear_delta(entry, "weapon_1")
	check(absf(float(w.get("damage", 0.0)) - 10.0) < 0.01 and "rien" in Tooltips.gear_text(entry, "weapon_1"), "infobulle : arme sans pièce portée %s" % str(w))
	# Brigandines à la place de gambisons : flèches -17,6 % (un gain), vitesse -3 % (une perte)
	var a := Tooltips.gear_delta({"type": "spear", "gear": ["armor_1"]}, "armor_2")
	check(absf(float(a["arrow_armor"]) + 17.647) < 0.01 and absf(float(a["speed"]) + 3.0) < 0.01, "infobulle : armure %s" % str(a))
	var at := Tooltips.gear_text({"type": "spear", "gear": ["armor_1"]}, "armor_2")
	check("-17,6 %" in at and "vitesse -3 % (perte)" in at, "infobulle : gains et pertes de l'armure %s" % at)
	print("Infobulle d'équipement : %s" % ("OK" if fails.is_empty() else "ÉCHEC"))


func _test_contract_odds() -> void:
	var c := CampaignState.new_game(3)
	var weak := {"enemy": [{"type": "spear", "men": 10, "xp": 0.0}]}
	var strong := {"enemy": [{"type": "men_at_arms", "men": 16, "xp": 400.0}, {"type": "men_at_arms", "men": 16, "xp": 400.0},
		{"type": "cavalry", "men": 10, "xp": 400.0}, {"type": "spear", "men": 20, "xp": 400.0}, {"type": "spear", "men": 20, "xp": 400.0},
		{"type": "archer", "men": 16, "xp": 400.0}, {"type": "archer", "men": 16, "xp": 400.0}, {"type": "cavalry", "men": 10, "xp": 400.0}]}
	var ow := Tooltips.contract_odds(c, weak)
	var os := Tooltips.contract_odds(c, strong)
	check(float(ow["chance"]) > 0.85 and float(os["chance"]) < float(ow["chance"]) and float(os["ratio"]) < 1.0,
		"chances d'un contrat : %s contre %s" % [str(ow), str(os)])
	check("très favorable" in Tooltips.contract_line(c, weak) and "%" in Tooltips.contract_text(c, strong), "ligne des chances %s" % Tooltips.contract_line(c, weak))
	var empty := CampaignState.new_game(3, Difficulty.NORMAL, false, true)
	check("aucune" in Tooltips.contract_line(empty, weak), "chances sans un homme")


func _test_other_tooltips() -> void:
	var cap := Captain.new()
	var s := Tooltips.skill_text(cap, "aura")
	check("180 px" in s and "225 px" in s, "infobulle de l'aura %s" % s)
	cap.skills["wages"] = 3
	check("-15 %" in Tooltips.skill_text(cap, "wages") and "maximal" in Tooltips.skill_text(cap, "wages"), "infobulle de la solde %s" % Tooltips.skill_text(cap, "wages"))
	check("Tenaces : moral +20 %" in Tooltips.traits_text({"traits": ["tenaces"]}), "infobulle des traits")
	var f := Tooltips.terrain_text("forest")
	check("Bois" in f and "caché" in f, "infobulle du terrain %s" % f)
	print("Autres infobulles : %s" % ("OK" if fails.is_empty() else "ÉCHEC"))


# ---------------------------------------------------------------- File d'ordres

func _run(b: Battle, seconds: float) -> void:
	for i in int(seconds / STEP):
		b.simulate(STEP)


func _mouse(b: Battle, button: MouseButton, world: Vector2, pressed: bool, shift := false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	e.shift_pressed = shift
	e.position = b.get_canvas_transform() * world
	b._unhandled_input(e)


func _test_queue(b: Battle) -> void:
	var r: Regiment = b.player_regiments()[0]
	for o in b.regiments:
		o.selected = false
	r.selected = true
	var start := r.center
	var p1 := start + Vector2(-150, 0)
	var p2 := start + Vector2(-150, 60)
	var p3 := start + Vector2(0, 60)
	# Un ordre, puis deux avec Maj : ils s'ajoutent à la file
	b.orders.issue_order(p1)
	check(r.orders.is_empty() and r.dest.distance_to(p1) < 30.0, "file : premier ordre")
	_mouse(b, MOUSE_BUTTON_RIGHT, p2, true, true)
	_mouse(b, MOUSE_BUTTON_RIGHT, p2, false, true)
	b.orders.issue_order(p3, false, true)
	check(r.orders.size() == 2 and r.dest.distance_to(p1) < 30.0, "file : Maj + clic droit ajoute à la file (%d ordres)" % r.orders.size())
	check((r.orders[0]["dest"] as Vector2).distance_to(p2) < 30.0, "file : point de passage 1")
	# La file s'enchaîne : arrivé en p1, le régiment part vers p2, puis p3
	var t := 0.0
	while r.dest.distance_to(p1) < 30.0 and t < 30.0:
		_run(b, 0.5)
		t += 0.5
	check(r.dest.distance_to(p2) < 30.0 and r.orders.size() == 1, "file : l'ordre suivant ne part pas (%.0f s)" % t)
	while not r.orders.is_empty() and t < 60.0:
		_run(b, 0.5)
		t += 0.5
	check(r.orders.is_empty() and r.dest.distance_to(p3) < 30.0, "file : le dernier ordre ne part pas")
	# Un ordre sans Maj remplace la file
	b.orders.issue_order(p1, false, true)
	b.orders.issue_order(p2, false, true)
	check(r.orders.size() >= 1, "file : ordres ajoutés pendant la marche")
	_mouse(b, MOUSE_BUTTON_RIGHT, start, true)
	_mouse(b, MOUSE_BUTTON_RIGHT, start, false)
	check(r.orders.is_empty() and r.dest.distance_to(start) < 30.0, "file : un ordre sans Maj ne remplace pas la file")
	# Ligne de front en file, halte qui vide la file
	b.orders.issue_order(p1)
	b.orders.issue_line_order(p2 + Vector2(-80, 0), p2 + Vector2(80, 0), false, true)
	check(r.orders.size() == 1 and int(r.orders[0]["cols"]) > 0, "file : ligne de front ajoutée à la file")
	b.orders.halt()
	check(r.orders.is_empty(), "file : la halte vide la file")
	# Attaque en file : pendant la bataille, après la marche
	b.start_battle()
	var foe: Regiment = null
	for o in b.regiments:
		if o.team == BattleSim.ENEMY:
			foe = o
			break
	b.orders.issue_order(r.center + Vector2(0, -60))
	b.rebuild_grid()
	b.orders.issue_order(foe.alive_soldiers()[0].pos, false, true)
	check(r.orders.size() == 1 and r.orders[0]["kind"] == "attack" and r.target == null, "file : attaque ajoutée après la marche")
	t = 0.0
	while r.target == null and t < 20.0:
		_run(b, 0.5)
		t += 0.5
	check(r.target == foe and r.orders.is_empty(), "file : l'attaque en file ne part pas")
	print("File d'ordres : %s" % ("OK" if fails.is_empty() else "ÉCHEC"))


# ---------------------------------------------------------------- Tutoriel guidé de campagne

func _test_guide(map: Node) -> void:
	var g: CampaignGuide = map.guide
	check(g != null and g.panel != null and g.current_id() == "recruit", "tutoriel : guide absent ou mauvaise étape")
	if g == null:
		return
	map._process(0.016)
	check(g.panel.visible and "Lever un régiment" in g.title.text, "tutoriel : panneau invisible")
	var st: CampaignState = map.state
	var here: int = map.town_here()
	check(here >= 0, "tutoriel : la compagnie n'est pas en ville au départ")
	# Recruter
	var type := str(CampaignState.TOWNS[here]["recruits"][0])
	map.do_recruit(type)
	map._process(0.016)
	check(g.current_id() == "equip", "tutoriel : recruter ne fait pas avancer (%s)" % g.current_id())
	# S'équiper
	var err := Equipment.buy(st, 0, Equipment.next_item(st.company[0], "helmet"))
	map._process(0.016)
	check(err == "" and g.current_id() == "food", "tutoriel : s'équiper ne fait pas avancer (%s, %s)" % [err, g.current_id()])
	# Vivres (les chariots de départ sont vidés pour qu'il y ait quelque chose à acheter)
	st.supplies.food = 10.0
	g.begin_step()
	LifePanel.buy(map, 5.0)
	map._process(0.016)
	check(g.current_id() == "contract", "tutoriel : les vivres ne font pas avancer (%s)" % g.current_id())
	check(CampaignState.load_game().tutorial_step == 3, "tutoriel : étape non sauvegardée")
	# Une action qui n'est pas celle demandée ne fait rien
	map.do_recruit(type)
	map._process(0.016)
	check(g.current_id() == "contract", "tutoriel : avance sans contrat")
	# Contrat : on passe l'étape par le bouton (le contrat lancerait la bataille)
	g.advance(true)
	check(g.current_id() == "march", "tutoriel : passer l'étape")
	# Marcher, puis entrer dans une autre ville
	map.click_map(MapData.walkable_point(MapData.place_pos(here) + Vector2(300, 0)))
	map._process(0.016)
	check(g.current_id() == "arrive", "tutoriel : marcher ne fait pas avancer (%s)" % g.current_id())
	var other := -1
	for t in CampaignState.TOWNS.size():
		if t != here and (other < 0 or MapData.place_pos(t).distance_to(MapData.place_pos(here)) < MapData.place_pos(other).distance_to(MapData.place_pos(here))):
			other = t
	map.click_place(other)
	var h := 0.0
	while st.overworld.inside != other and h < 400.0:
		map.advance_time(1.0)
		h += 1.0
		if map.contact != null or st.world.has_encounter():
			break
	if st.overworld.inside == other:
		map._process(0.016)
		check(g.finished() and st.tutorial_step == -1 and not g.panel.visible, "tutoriel : entrer en ville ne le termine pas (%s)" % g.current_id())
	else:
		g.advance(true) # Rencontre en chemin : on passe la dernière étape
		check(g.finished(), "tutoriel : dernière étape")
	# Option désactivée : aucun guide
	GameOptions.tutorial = false
	st.tutorial_step = 0
	check(CampaignGuide.attach(map) == null, "tutoriel : l'option désactivée n'arrête pas le guide")
	GameOptions.tutorial = true
	st.tutorial_step = -1
	print("Tutoriel guidé de campagne : %s" % ("OK" if fails.is_empty() else "ÉCHEC"))


# ---------------------------------------------------------------- Manette

func _pad_button(map: Node, b: JoyButton) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	e.pressed = true
	map._input(e)
	var up := InputEventJoypadButton.new()
	up.button_index = b
	up.pressed = false
	map._input(up)


func _pad_axis(map: Node, axis: JoyAxis, v: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = v
	map._input(e)


func _test_pad(map: Node) -> void:
	var pad: MapPad = map.pad
	map.contact = null
	map.view = ""
	map.town_open = false
	map.refresh_ui()
	_pad_button(map, JOY_BUTTON_RIGHT_SHOULDER)
	check(pad.active and map.view == "company", "manette : RB n'ouvre pas l'onglet Compagnie (%s)" % map.view)
	_pad_button(map, JOY_BUTTON_RIGHT_SHOULDER)
	check(map.view == "world", "manette : RB ne passe pas à l'onglet suivant")
	_pad_button(map, JOY_BUTTON_LEFT_SHOULDER)
	_pad_button(map, JOY_BUTTON_LEFT_SHOULDER)
	check(map.view == "quests", "manette : LB ne revient pas en arrière (%s)" % map.view)
	var buttons := MapPad.buttons_in(map.panel)
	check(buttons.any(func(x: Button) -> bool: return x.focus_mode == Control.FOCUS_ALL), "manette : pas de navigation au focus dans la fenêtre")
	_pad_button(map, JOY_BUTTON_B)
	check(map.view == "" and not map.panel.visible, "manette : B ne ferme pas la fenêtre")
	# Gâchettes : vitesses et pause
	map.set_speed(0)
	_pad_axis(map, JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_pad_axis(map, JOY_AXIS_TRIGGER_RIGHT, 0.0)
	check(map.speed_index == 1, "manette : gâchette droite sans effet")
	_pad_axis(map, JOY_AXIS_TRIGGER_LEFT, 1.0)
	_pad_axis(map, JOY_AXIS_TRIGGER_LEFT, 0.0)
	_pad_axis(map, JOY_AXIS_TRIGGER_LEFT, 1.0)
	_pad_axis(map, JOY_AXIS_TRIGGER_LEFT, 0.0)
	check(map.speed_index == 0 and map.paused, "manette : gâchette gauche sans pause")
	_pad_button(map, JOY_BUTTON_X)
	check(not map.paused, "manette : X ne reprend pas")
	# Stick : le curseur bouge ; A : la compagnie marche vers lui
	var st: CampaignState = map.state
	st.overworld.halt()
	map.center_on(st.overworld.player.pos)
	pad.cursor = map.get_viewport_rect().size * 0.5
	var c0 := pad.cursor
	_pad_axis(map, JOY_AXIS_LEFT_X, 1.0)
	pad.step(0.1)
	_pad_axis(map, JOY_AXIS_LEFT_X, 0.0)
	check(pad.cursor.x > c0.x + 30.0, "manette : le stick ne bouge pas le curseur")
	_pad_button(map, JOY_BUTTON_A)
	check(not st.overworld.player.path.is_empty() or map.notice != "" , "manette : A ne fait pas marcher")
	# La souris reprend la main
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_WHEEL_UP
	mb.pressed = true
	map._input(mb)
	check(not pad.active, "manette : la souris ne reprend pas la main")
	print("Manette sur la carte : %s" % ("OK" if fails.is_empty() else "ÉCHEC"))


func _finish() -> void:
	for i in range(1, CampaignState.SLOT_COUNT + 1):
		CampaignState.delete_slot(i)
	_remove(OPTIONS_TEST)
	for e in counter.errors:
		fails.append("erreur moteur : " + e)
	if fails.is_empty():
		print("confort : tout est OK")
		quit(0)
	else:
		for f in fails:
			print("ÉCHEC : ", f)
		quit(1)
