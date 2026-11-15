extends Node2D
## Carte de campagne : des villes reliées par des routes, la compagnie marche de l'une à l'autre.
## Clic sur une ville voisine : y marcher (chaque jour de marche coûte la solde).
## Panneau de droite : or, troupes, recrutement et contrats de la ville où l'on se trouve.

const MAP_SIZE := Vector2(880, 720)
const PIX := 4 ## Taille d'un « pixel » du fond de carte
const DAY_ANIM := 0.4 ## Durée de l'animation d'un jour de marche, en secondes
const TOWN_RADIUS := 24.0
const GOLD_COL := Color(1, 0.84, 0.4)
const BLUE := Color(0.22, 0.38, 0.85)
const WOOD := Color(0.48, 0.32, 0.17)
const TYPE_ORDER := ["spear", "men_at_arms", "archer", "cavalry"]

var state: CampaignState
var font: Font
var sprites := SpriteBank.new()
var land_tex: ImageTexture
var trees: Array[Vector2] = []
var hover := -1
var walking := false
var walk_to := -1
var walk_t := 0.0
var walk_dur := 1.0
var notice := "" ## Message d'information ou de refus affiché dans le panneau
var box: VBoxContainer
var confirm_new := false ## Premier clic sur « Nouvelle campagne » : demande confirmation
var auto_launch := true ## Lancer la scène de bataille après une embuscade (désactivé par les tests)
var ambushed := false ## Une embuscade attend : la bataille va commencer
var resuming := false ## Une bataille sauvegardée (contrat ou embuscade) reprend dès l'ouverture
var end_requested := false ## Campagne terminée : l'écran de fin a été demandé

const END_SCENE := "res://scenes/end.tscn"


## Petit emplacement qui dessine les chevrons de rang d'un régiment dans le panneau.
class RankIcon extends Control:
	var rank := 0

	func _init() -> void:
		custom_minimum_size = Vector2(14, 14)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		Hud.draw_chevrons(self, Vector2(2, 3), rank)


func _ready() -> void:
	GameOptions.ensure_loaded()
	if CampaignState.current == null:
		# Au lancement du jeu : reprend la campagne sauvegardée s'il y en a une
		CampaignState.migrate_legacy()
		var loaded := CampaignState.load_game()
		if loaded != null:
			CampaignState.current = loaded
			notice = "Campagne reprise au jour %d." % loaded.day
			if CampaignState.loaded_from_backup:
				notice += " Sauvegarde abîmée : copie de secours relue."
		else:
			if CampaignState.has_save():
				notice = "Sauvegarde illisible : nouvelle campagne."
			CampaignState.current = CampaignState.new_game()
	state = CampaignState.current
	if state.in_battle():
		if state.lenient or state.is_over():
			state.pending = {} # Mode indulgent : on revient à l'état d'avant la bataille
		else:
			# Bataille interrompue (jeu fermé, embuscade pendant la marche) : elle reprend
			resuming = true
			ambushed = true
			notice = "La bataille interrompue reprend : %s." % str(state.pending.get("title", ""))
			if auto_launch:
				get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
	state.save()
	font = ThemeDB.fallback_font
	if state.is_over():
		# Retour de la bataille décisive (ou de la dernière défaite) : place au bilan
		show_end()
	build_land()
	build_ui()
	refresh_ui()


func _process(delta: float) -> void:
	if walking:
		walk_t += delta
		if walk_t >= walk_dur:
			walking = false
			notice = state.travel(walk_to)
			if notice == "" and not state.travel_events.is_empty():
				notice = " ".join(state.travel_events)
			state.save()
			refresh_ui()
			if state.is_over():
				show_end()
			elif state.in_battle():
				# Embuscade : la bataille est forcée dès l'arrivée
				ambushed = true
				if auto_launch:
					get_tree().change_scene_to_file("res://scenes/main.tscn")
	queue_redraw()


# ---------------------------------------------------------------- Fond de carte

## Fond pixel art généré une fois (toujours le même : la carte ne change pas d'une partie à l'autre).
func build_land() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1789
	var relief := FastNoiseLite.new()
	relief.seed = 7
	relief.frequency = 0.02
	var wood := FastNoiseLite.new()
	wood.seed = 11
	wood.frequency = 0.03
	var w := int(MAP_SIZE.x) / PIX
	var h := int(MAP_SIZE.y) / PIX
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5) * PIX
			var n := relief.get_noise_2d(x, y) * 0.5 + 0.5
			var c := Color(0.56, 0.63, 0.34).lerp(Color(0.4, 0.5, 0.25), n)
			if n > 0.72:
				c = c.lerp(Color(0.62, 0.56, 0.38), (n - 0.72) * 2.5) # Collines
			if rng.randf() < 0.06:
				c = c.lightened(0.07)
			var forest := wood.get_noise_2d(x, y) > 0.28 and clear_of_towns_and_roads(p, 30.0)
			if forest:
				c = c.darkened(0.22)
				if rng.randf() < 0.2:
					trees.append(p + Vector2(rng.randf_range(-2, 2), rng.randf_range(-2, 2)))
			var dr := absf(p.x - river_x(p.y))
			if dr < 7.0:
				c = Color(0.3, 0.47, 0.66).lightened(0.08 if rng.randf() < 0.1 else 0.0)
			elif dr < 10.0:
				c = Color(0.5, 0.52, 0.34)
			# Bord de carte assombri
			var edge := minf(minf(p.x, MAP_SIZE.x - p.x), minf(p.y, MAP_SIZE.y - p.y))
			if edge < 14.0:
				c = c.darkened(0.35 * (1.0 - edge / 14.0))
			img.set_pixel(x, y, c)
	land_tex = ImageTexture.create_from_image(img)
	trees = trees.filter(func(t): return absf(t.x - river_x(t.y)) > 14.0)
	trees.sort_custom(func(a, b): return a.y < b.y)


## Abscisse de la rivière qui traverse la carte du nord au sud.
func river_x(y: float) -> float:
	return 440.0 + sin(y * 0.011) * 70.0 + sin(y * 0.031) * 18.0


func clear_of_towns_and_roads(p: Vector2, margin: float) -> bool:
	for t in CampaignState.TOWNS:
		if p.distance_to(t["pos"]) < margin + 20.0:
			return false
	for road in CampaignState.ROADS:
		var a: Vector2 = CampaignState.TOWNS[road[0]]["pos"]
		var b: Vector2 = CampaignState.TOWNS[road[1]]["pos"]
		if p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)) < margin * 0.5:
			return false
	return true


func town_pos(i: int) -> Vector2:
	return CampaignState.TOWNS[i]["pos"]


func town_at(p: Vector2) -> int:
	for i in CampaignState.TOWNS.size():
		if p.distance_to(town_pos(i)) < TOWN_RADIUS:
			return i
	return -1


# ---------------------------------------------------------------- Ordres

func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
		back_to_menu()
		return
	var mm := event as InputEventMouseMotion
	if mm != null:
		hover = town_at(mm.position)
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		var t := town_at(mb.position)
		if t >= 0:
			click_town(t)


## Clic sur une ville : marche vers elle si une route y mène directement.
func click_town(t: int) -> void:
	if walking or ambushed or t == state.location:
		return
	if state.is_over():
		notice = "La campagne est terminée."
	elif state.is_destroyed():
		notice = "Sans troupes, la compagnie ne peut plus marcher."
	elif not t in state.neighbours(state.location):
		notice = "Pas de route directe vers %s : passez par une ville voisine." % CampaignState.TOWNS[t]["name"]
	else:
		walking = true
		walk_to = t
		walk_t = 0.0
		walk_dur = state.travel_days(t) * DAY_ANIM
		notice = "En marche vers %s..." % CampaignState.TOWNS[t]["name"]
	refresh_ui()


## Campagne terminée (victoire ou ruine) : écran de fin.
func show_end() -> void:
	if end_requested:
		return
	end_requested = true
	if auto_launch:
		get_tree().change_scene_to_file.call_deferred(END_SCENE)


func do_recruit(type: String) -> void:
	notice = state.recruit(type)
	state.save()
	refresh_ui()


func do_refill(i: int) -> void:
	notice = state.refill(i)
	state.save()
	refresh_ui()


func do_accept(c: Dictionary) -> void:
	notice = state.accept(c)
	if notice == "":
		state.save() # Contrat en cours sauvegardé (sauf mode indulgent) : fermer le jeu ne l'annule pas
		get_tree().change_scene_to_file("res://scenes/main.tscn")
	else:
		refresh_ui()


func do_skirmish() -> void:
	state.pending = {}
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func back_to_menu() -> void:
	if walking:
		# Termine la marche en cours avant de quitter (sauvegarde cohérente)
		walking = false
		state.travel(walk_to)
		state.save()
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


func do_new_campaign() -> void:
	if not confirm_new and not state.is_ruined() and not state.is_over():
		confirm_new = true # Il faut cliquer une seconde fois
		refresh_ui()
		return
	confirm_new = false
	CampaignState.current = CampaignState.new_game(0, state.difficulty, state.lenient) # Mêmes réglages qu’avant
	state = CampaignState.current
	state.save()
	end_requested = false
	notice = "Nouvelle campagne."
	refresh_ui()


func cancel_new_campaign() -> void:
	confirm_new = false
	refresh_ui()


# ---------------------------------------------------------------- Panneau

func build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(MAP_SIZE.x, 0)
	panel.size = Vector2(1280.0 - MAP_SIZE.x, MAP_SIZE.y)
	panel.theme = make_theme()
	layer.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	box = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 5)
	scroll.add_child(box)


func make_theme() -> Theme:
	var th := Theme.new()
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.11, 0.08, 0.06, 0.97)
	bg.border_color = Color(0.45, 0.35, 0.2)
	bg.border_width_left = 2
	bg.set_content_margin_all(12)
	th.set_stylebox("panel", "PanelContainer", bg)
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.set_content_margin_all(5)
		sb.set_border_width_all(1)
		sb.bg_color = Color(0.3, 0.21, 0.12)
		sb.border_color = Color(0.6, 0.47, 0.25)
		match st:
			"hover":
				sb.bg_color = Color(0.42, 0.3, 0.16)
				sb.border_color = GOLD_COL
			"pressed":
				sb.bg_color = Color(0.22, 0.15, 0.08)
			"disabled":
				sb.bg_color = Color(0.18, 0.15, 0.12)
				sb.border_color = Color(0.3, 0.27, 0.22)
			"focus":
				sb.draw_center = false
		th.set_stylebox(st, "Button", sb)
	th.set_color("font_color", "Button", Color(1, 0.93, 0.78))
	th.set_color("font_hover_color", "Button", Color(1, 1, 0.85))
	th.set_color("font_disabled_color", "Button", Color(0.55, 0.5, 0.42))
	th.set_font_size("font_size", "Button", 13)
	th.set_color("font_color", "Label", Color(0.92, 0.88, 0.78))
	th.set_font_size("font_size", "Label", 13)
	return th


func add_label(s: String, size := 13, col := Color(0.92, 0.88, 0.78)) -> Label:
	var l := Label.new()
	l.text = s
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 360
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	box.add_child(l)
	return l


func add_button(s: String, cb: Callable, enabled := true, parent: Control = null) -> Button:
	var b := Button.new()
	b.text = s
	b.disabled = not enabled
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	(parent if parent != null else box).add_child(b)
	return b


func add_section(s: String) -> void:
	box.add_child(HSeparator.new())
	add_label(s, 15, GOLD_COL)


func refresh_ui() -> void:
	if box == null:
		return
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	var town: Dictionary = CampaignState.TOWNS[state.location]
	var recruits: Array = town["recruits"]

	add_label("COMPAGNIE FRANCHE", 19, GOLD_COL)
	add_label("Jour %d   ·   %d écus   ·   solde %d écus / jour" % [state.day, int(state.gold), ceili(state.daily_wage())], 14)
	add_label("Victoires %d   ·   défaites %d   ·   %s   ·   renommée %d" % [state.victories, state.defeats, CampaignState.plural(state.total_men(), "homme", "hommes"), state.fame], 12, Color(0.75, 0.72, 0.65))
	if notice != "":
		add_label(notice, 13, Color(1, 0.62, 0.3))

	add_section("Objectif")
	add_label(state.objective_status(), 12, Color(1, 0.9, 0.7))
	if state.is_over():
		add_button("Voir le bilan de la campagne", show_end_now)

	add_section("À %s" % town["name"])
	var fac := CampaignState.town_faction(state.location)
	add_label("%s — réputation %+d (%s)" % [CampaignState.faction_name(fac), state.reputation[fac], state.reputation_label(fac)], 12, CampaignState.FACTIONS[fac]["color"])
	var closed := state.closed_message(state.location)
	if closed != "":
		add_label(closed + " Ni contrat ni recrutement ici.", 12, Color(1, 0.5, 0.4))
	var names: Array[String] = []
	for t in recruits:
		names.append(CampaignState.type_name(t).to_lower())
	add_label("On y lève : %s.   Prix des recrues : %s" % [", ".join(names), price_text(state.location)], 12, Color(0.75, 0.72, 0.65))

	# Troupes
	add_section("Votre compagnie")
	if state.is_destroyed():
		if state.is_ruined():
			add_label("Plus personne ne marche sous votre bannière, et les caisses sont vides...", 13, Color(1, 0.5, 0.4))
			add_button("Recommencer une campagne", do_new_campaign)
		else:
			add_label("Plus personne ne marche sous votre bannière. Levez un régiment pour reprendre la route.", 13, Color(1, 0.5, 0.4))
	for i in state.company.size():
		var r: Dictionary = state.company[i]
		var type: String = r["type"]
		var full: int = UnitTypes.STATS[type]["count"]
		var row := HBoxContainer.new()
		box.add_child(row)
		var chev := RankIcon.new()
		chev.rank = CampaignState.rank_of(r)
		row.add_child(chev)
		var l := Label.new()
		l.text = "%d. %s   %d / %d   %s" % [i + 1, CampaignState.type_name(type), int(r["men"]), full, CampaignState.rank_name(chev.rank)]
		l.tooltip_text = "Expérience %d (aguerris à %d, vétérans à %d)" % [int(r.get("xp", 0.0)), int(CampaignState.RANK_XP[1]), int(CampaignState.RANK_XP[2])]
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if int(r["men"]) < full:
			l.add_theme_color_override("font_color", Color(1, 0.75, 0.5))
		row.add_child(l)
		var missing := state.refill_missing(i)
		if missing > 0 and type in recruits:
			var cost := state.recruit_cost(type, missing)
			add_button("Compléter : +%d, %d écus" % [missing, cost], do_refill.bind(i), state.gold >= cost and closed == "", row)

	# Recrutement
	add_section("Lever un régiment")
	for t in TYPE_ORDER:
		if not t in recruits:
			continue
		var men: int = UnitTypes.STATS[t]["count"]
		var cost := state.recruit_cost(t, men)
		var ok := state.gold >= cost and state.company.size() < CampaignState.MAX_REGIMENTS and closed == ""
		add_button("%s : %d hommes, %d écus (solde %.0f / jour)" % [CampaignState.type_name(t), men, cost, men * float(CampaignState.WAGE[t])], do_recruit.bind(t), ok)
	if state.company.size() >= CampaignState.MAX_REGIMENTS:
		add_label("La compagnie compte déjà %d régiments." % CampaignState.MAX_REGIMENTS, 12, Color(0.75, 0.72, 0.65))

	# Contrats
	add_section("Contrats")
	var here := state.contracts_at(state.location)
	if here.is_empty():
		add_label("Aucun contrat ici. Les villes marquées d'un drapeau rouge en proposent.", 12, Color(0.75, 0.72, 0.65))
	for c in here:
		if c.get("final", false):
			add_label("★ CONTRAT FINAL ★", 13, GOLD_COL)
		add_label(str(c["title"]), 14, Color(1, 0.9, 0.7))
		add_label(str(c["text"]), 12, Color(0.8, 0.77, 0.7))
		add_label("Ennemi : %s" % CampaignState.army_summary(c["enemy"]), 12)
		add_label("Prime : %d écus   ·   difficulté %s   ·   jusqu'au jour %d" % [state.contract_reward(c), stars(int(c["difficulty"])), int(c["expires"])], 12, GOLD_COL)
		add_button("Accepter et livrer bataille", do_accept.bind(c), not state.is_destroyed() and not state.is_over() and not walking and not ambushed and closed == "")

	# Réputation
	add_section("Réputation")
	for f in CampaignState.FACTIONS.size():
		add_label("%s : %+d (%s)" % [CampaignState.faction_name(f), state.reputation[f], state.reputation_label(f)], 12, CampaignState.FACTIONS[f]["color"])
	add_label("Un contrat gagné plaît à qui paie et fâche sa rivale ; la réputation fait varier la prime. Sous %d, la faction ferme ses portes." % CampaignState.REP_CLOSED, 11, Color(0.6, 0.58, 0.52))

	# Journal
	add_section("Journal")
	for s in state.log_lines:
		add_label(s, 11, Color(0.72, 0.69, 0.62))

	box.add_child(HSeparator.new())
	add_button("Menu principal (Échap)", back_to_menu)
	add_button("Escarmouche libre (hors campagne)", do_skirmish)
	if confirm_new:
		add_label("Effacer la campagne en cours (jour %d) ?" % state.day, 12, Color(1, 0.62, 0.3))
		var row := HBoxContainer.new()
		box.add_child(row)
		add_button("Oui, recommencer", do_new_campaign, true, row)
		add_button("Non", cancel_new_campaign, true, row)
	elif not state.is_ruined():
		add_button("Nouvelle campagne", do_new_campaign)
	add_label("Sauvegarde automatique après chaque marche, recrutement et bataille.", 11, Color(0.6, 0.58, 0.52))
	add_label("Cliquez sur une ville voisine pour y marcher. Chaque jour coûte la solde ; sans or, des hommes désertent. En route : marchands, déserteurs, épidémies, intempéries… et brigands.", 11, Color(0.6, 0.58, 0.52))


func show_end_now() -> void:
	end_requested = false
	show_end()


## Difficulté d'un contrat en étoiles : « ★★★☆☆ ».
static func stars(d: int) -> String:
	var m := CampaignState.MAX_LEVEL
	d = clampi(d, 0, m)
	return "★".repeat(d) + "☆".repeat(m - d)


## « normal », « +15 % », « -10 % » : prix des recrues d'une ville.
func price_text(town: int) -> String:
	var p := int(round((float(CampaignState.TOWNS[town]["price"]) - 1.0) * 100.0))
	return "normal" if p == 0 else "%+d %%" % p


# ---------------------------------------------------------------- Rendu

func _draw() -> void:
	draw_texture_rect(land_tex, Rect2(Vector2.ZERO, MAP_SIZE), false)
	var near := state.neighbours(state.location)

	# Routes (celles qui partent de la ville actuelle sont plus claires)
	for road in CampaignState.ROADS:
		var a := town_pos(road[0])
		var b := town_pos(road[1])
		var from_here: bool = road[0] == state.location or road[1] == state.location
		draw_line(a, b, Color(0.35, 0.25, 0.14), 6.0)
		draw_line(a, b, Color(0.82, 0.7, 0.46) if from_here else Color(0.66, 0.55, 0.36), 3.0)
	# Ponts
	for road in CampaignState.ROADS:
		var a := town_pos(road[0])
		var b := town_pos(road[1])
		for k in 40:
			var p := a.lerp(b, k / 40.0)
			if absf(p.x - river_x(p.y)) < 4.0:
				draw_rect(Rect2(p - Vector2(7, 4), Vector2(14, 8)), Color(0.45, 0.33, 0.2))
				draw_rect(Rect2(p - Vector2(7, 4), Vector2(14, 8)), Color(0.25, 0.17, 0.1), false, 1.0)
				break

	for t in trees:
		draw_tree(t)

	for i in CampaignState.TOWNS.size():
		draw_town(i, i == state.location, i in near)

	# Jours de marche sur les routes partant d'ici
	for t in near:
		var mid := (town_pos(state.location) + town_pos(t)) * 0.5
		var s := "%d j" % state.travel_days(t)
		draw_rect(Rect2(mid - Vector2(13, 9), Vector2(26, 16)), Color(0.12, 0.08, 0.05, 0.8))
		draw_string(font, mid + Vector2(-12, 4), s, HORIZONTAL_ALIGNMENT_CENTER, 24, 11, Color(1, 0.92, 0.75))

	# La compagnie
	var at := town_pos(state.location)
	if walking:
		var k := clampf(walk_t / walk_dur, 0.0, 1.0)
		at = town_pos(state.location).lerp(town_pos(walk_to), k)
	draw_company(at + Vector2(-38, -14))

	# Cartouche
	draw_rect(Rect2(12, 12, 210, 30), Color(0.12, 0.08, 0.05, 0.8))
	draw_rect(Rect2(12, 12, 210, 30), Color(0.6, 0.47, 0.25), false, 1.0)
	draw_string(font, Vector2(22, 33), "Pays de Valfrène", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, GOLD_COL)
	draw_objective(Vector2(12, 48))

	if hover >= 0 and not walking:
		draw_tooltip(hover)


## Encart d'objectif : renommée et barre de progression vers la bataille décisive.
func draw_objective(at: Vector2) -> void:
	var size := Vector2(300, 52)
	draw_rect(Rect2(at, size), Color(0.12, 0.08, 0.05, 0.8))
	draw_rect(Rect2(at, size), Color(0.6, 0.47, 0.25), false, 1.0)
	var final := state.final_contract()
	var head := "Objectif : la bataille décisive"
	if state.ended == "victory":
		head = "Objectif atteint : la guerre est gagnée !"
	elif state.ended == "ruin":
		head = "La compagnie est dissoute"
	draw_string(font, at + Vector2(10, 17), head, HORIZONTAL_ALIGNMENT_LEFT, size.x - 20, 13, GOLD_COL)
	var bar := Rect2(at + Vector2(10, 24), Vector2(size.x - 20, 8))
	draw_rect(bar, Color(0.06, 0.05, 0.04))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * state.objective_progress(), bar.size.y)), Color(0.75, 0.58, 0.25))
	draw_rect(bar, Color(0.45, 0.35, 0.2), false, 1.0)
	var line := "Renommée %d / %d" % [state.fame, CampaignState.FINAL_FAME]
	if not final.is_empty():
		line = "Rendez-vous à %s !" % CampaignState.TOWNS[int(final["town"])]["name"]
	draw_string(font, at + Vector2(10, 46), line, HORIZONTAL_ALIGNMENT_LEFT, size.x - 20, 11, Color(0.92, 0.88, 0.78))


func draw_tree(t: Vector2) -> void:
	if sprites.has_trees():
		var tr := sprites.tree_at(t)
		var src: Rect2 = tr["src"]
		draw_texture_rect_region(tr["tex"], Rect2(t.round() - Vector2(8, 15), src.size), src)
		return
	draw_rect(Rect2(t.x - 1, t.y - 3, 2, 3), WOOD)
	draw_rect(Rect2(t.x - 4, t.y - 10, 8, 7), Color(0.15, 0.32, 0.14))


## Petite ville fortifiée dessinée en pixels (x2).
func draw_town(i: int, here: bool, near: bool) -> void:
	var p := town_pos(i).round()
	if here:
		draw_circle(p, TOWN_RADIUS, Color(1, 0.84, 0.4, 0.25))
		draw_arc(p, TOWN_RADIUS, 0, TAU, 32, GOLD_COL, 2.0)
	elif i == hover and near:
		draw_arc(p, TOWN_RADIUS, 0, TAU, 32, Color(1, 1, 1, 0.8), 2.0)
	draw_set_transform(p, 0.0, Vector2(2, 2))
	var stone := Color(0.7, 0.68, 0.62)
	var dark := Color(0.3, 0.28, 0.26)
	var roof := Color(0.66, 0.24, 0.16)
	draw_rect(Rect2(-9, -2, 18, 7), dark) # Ombre de l'enceinte
	draw_rect(Rect2(-8, -3, 16, 7), stone)
	for k in 4:
		draw_rect(Rect2(-8 + k * 5, -4, 2, 1), stone) # Créneaux
	draw_rect(Rect2(-1, 1, 3, 3), dark) # Porte
	draw_rect(Rect2(-10, -8, 4, 12), stone) # Tours
	draw_rect(Rect2(6, -8, 4, 12), stone)
	draw_rect(Rect2(-11, -10, 6, 2), roof)
	draw_rect(Rect2(5, -10, 6, 2), roof)
	draw_rect(Rect2(-4, -8, 3, 4), Color(0.85, 0.78, 0.6)) # Maisons derrière le mur
	draw_rect(Rect2(-5, -9, 5, 1), roof)
	draw_rect(Rect2(1, -9, 3, 5), Color(0.85, 0.78, 0.6))
	draw_rect(Rect2(0, -10, 5, 1), roof)
	draw_set_transform(Vector2.ZERO)
	# Drapeau rouge s'il y a des contrats
	var n := state.contracts_at(i).size()
	if n > 0:
		var f := p + Vector2(14, -22)
		draw_line(f, f + Vector2(0, 14), WOOD, 2.0)
		var final_here := int(state.final_contract().get("town", -1)) == i
		draw_rect(Rect2(f, Vector2(10, 7)), GOLD_COL if final_here else Color(0.8, 0.15, 0.12))
		draw_string(font, f + Vector2(2, 6), str(n), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.2, 0.1, 0.02) if final_here else Color.WHITE)
	# Liseré aux couleurs de la faction sous le nom (rayé si elle nous ferme ses portes)
	var fcol: Color = CampaignState.FACTIONS[CampaignState.town_faction(i)]["color"]
	var bar := Rect2(p + Vector2(-22, 38), Vector2(44, 4))
	draw_rect(bar.grow(1), Color(0, 0, 0, 0.7))
	draw_rect(bar, fcol)
	if state.faction_closed(CampaignState.town_faction(i)):
		for k in 4:
			draw_rect(Rect2(bar.position + Vector2(4 + k * 11, 0), Vector2(5, 4)), Color(0.55, 0.08, 0.06))
	var name: String = CampaignState.TOWNS[i]["name"]
	var col := GOLD_COL if here else (Color(1, 1, 1) if near else Color(0.85, 0.82, 0.75))
	draw_string(font, p + Vector2(-60, 33), name, HORIZONTAL_ALIGNMENT_CENTER, 120, 13, Color(0, 0, 0, 0.8))
	draw_string(font, p + Vector2(-61, 32), name, HORIZONTAL_ALIGNMENT_CENTER, 120, 13, col)


## Bannière de la compagnie.
func draw_company(base: Vector2) -> void:
	base = base.round()
	draw_set_transform(base, 0.0, Vector2(2, 2))
	draw_rect(Rect2(-3, 8, 8, 2), Color(0, 0, 0, 0.3))
	draw_line(Vector2(0, -2), Vector2(0, 9), WOOD, 1.0)
	draw_rect(Rect2(1, -2, 8, 6), BLUE)
	draw_rect(Rect2(1, -2, 8, 6), Color(0, 0, 0, 0.6), false, 0.5)
	draw_rect(Rect2(4, -1, 2, 4), Color(1, 0.95, 0.8))
	draw_rect(Rect2(3, 0, 4, 1), Color(1, 0.95, 0.8))
	draw_set_transform(Vector2.ZERO)


func draw_tooltip(i: int) -> void:
	var lines: Array[String] = [str(CampaignState.TOWNS[i]["name"])]
	var fi := CampaignState.town_faction(i)
	lines.append("%s (%s)" % [CampaignState.faction_name(fi), state.reputation_label(fi)])
	if i == state.location:
		lines.append("Vous êtes ici")
	elif i in state.neighbours(state.location):
		var d := state.travel_days(i)
		lines.append("%s de marche, solde %d écus" % [CampaignState.plural(d, "jour", "jours"), ceili(state.daily_wage() * d)])
	else:
		lines.append("Pas de route directe")
	var names: Array[String] = []
	for t in CampaignState.TOWNS[i]["recruits"]:
		names.append(CampaignState.type_name(t).to_lower())
	lines.append("Recrues : %s (prix %s)" % [", ".join(names), price_text(i)])
	for c in state.contracts_at(i):
		lines.append("Contrat : %s (%d écus)" % [c["title"], state.contract_reward(c)])
	var w := 0.0
	for s in lines:
		w = maxf(w, font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x)
	var size := Vector2(w + 16, lines.size() * 16 + 10)
	var at := town_pos(i) + Vector2(28, -size.y * 0.5)
	at.x = minf(at.x, MAP_SIZE.x - size.x - 6)
	at.y = clampf(at.y, 6, MAP_SIZE.y - size.y - 6)
	draw_rect(Rect2(at, size), Color(0.1, 0.07, 0.05, 0.92))
	draw_rect(Rect2(at, size), Color(0.6, 0.47, 0.25), false, 1.0)
	for k in lines.size():
		draw_string(font, at + Vector2(8, 18 + k * 16), lines[k], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, GOLD_COL if k == 0 else Color(0.92, 0.88, 0.78))
