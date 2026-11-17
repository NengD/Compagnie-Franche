extends Node2D
## Carte du monde en temps réel : la compagnie et les autres groupes (villageois, bandits,
## caravanes, armées des factions) se déplacent librement sur une grande carte (MapData).
## Le temps s'écoule en heures de jeu (overworld.gd) ; pause avec Espace, vitesses x1, x2, x4 ;
## il s'arrête quand le panneau d'une ville ou une rencontre est ouvert.
##
## Clic gauche : marcher vers un point ; sur un lieu : y entrer en arrivant (panneau de ville :
## recrutement, contrats) ; sur un groupe : le poursuivre (au contact : la rencontre). Clic droit :
## halte. Caméra : ZQSD (touches physiques) ou flèches, bord de l'écran, clic molette, molette
## pour le zoom. Mini-carte en bas à gauche (clic : y regarder).
## Panneau de droite : compagnie, ville, rencontre, monde, réputation, journal.

const PANEL_SHARE := 0.3125 ## Part de la largeur de la vue prise par le panneau (400 px en 1280)
const PANEL_MIN := 340.0
const PANEL_MAX := 480.0
const MAP_BG := Color(0.09, 0.07, 0.05)
const PIX := 4 ## Taille d'un « pixel » du fond de carte (pixels de carte)
const HOURS_PER_SECOND := 1.5 ## Heures de jeu par seconde à la vitesse x1
const SPEEDS := [1, 2, 4]
const ZOOM_MIN := 0.45
const ZOOM_MAX := 2.5
const PAN_SPEED := 900.0 ## Défilement au clavier, pixels d'écran par seconde
const EDGE := 12.0 ## Largeur du bord d'écran qui fait défiler
const PICK := 16.0 ## Rayon de clic d'un groupe (pixels d'écran)
const GOLD_COL := Color(1, 0.84, 0.4)
const BLUE := Color(0.22, 0.38, 0.85)
const WOOD := Color(0.48, 0.32, 0.17)
const TYPE_ORDER := UnitTypes.ORDER
const KIND_COLORS := {"villagers": Color(0.7, 0.55, 0.3), "bandits": Color(0.55, 0.1, 0.08), "caravan": Color(0.85, 0.7, 0.3),
	"patrol": Color(0.4, 0.5, 0.75), "deserters": Color(0.5, 0.5, 0.5)}
const END_SCENE := "res://scenes/end.tscn"
const BATTLE_SCENE := "res://scenes/main.tscn"

static var land_tex: ImageTexture = null ## Fond de carte, construit une fois (la carte ne change pas)
static var tree_spots: Array[Vector2] = []

var state: CampaignState
var font: Font
var sprites := SpriteBank.new()
var cam: Camera2D
var land: Node2D
var light: CanvasModulate
var notice := "" ## Message d'information ou de refus affiché dans le panneau
var box: VBoxContainer
var panel: PanelContainer
var top_label: Label
var speed_buttons: Array[Button] = []
var minimap: Control
var tip: PanelContainer
var tip_label: Label
var paused := false
var speed_index := 0
var town_open := false ## Panneau du lieu où la compagnie est entrée : le temps est arrêté
var contact: Party = null ## Rencontre en cours (choix à faire) : le temps est arrêté
var hover_place := -1
var hover_party: Party = null
var dragging := false
var confirm_new := false ## Premier clic sur « Nouvelle campagne » : demande confirmation
var auto_launch := true ## Lancer la scène de bataille (désactivé par les tests)
var ambushed := false ## Une bataille va commencer (embuscade, rencontre, contrat repris)
var resuming := false ## Une bataille sauvegardée reprend dès l'ouverture
var end_requested := false ## Campagne terminée : l'écran de fin a été demandé
var walking := false ## La compagnie marche (pour l'affichage et les tests)


## Petit emplacement qui dessine les chevrons de rang d'un régiment dans le panneau.
class RankIcon extends Control:
	var rank := 0

	func _init() -> void:
		custom_minimum_size = Vector2(14, 14)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		Hud.draw_chevrons(self, Vector2(2, 3), rank)


## Fond de carte (texture, routes, arbres) : dessiné une fois, sous la couche vivante.
class LandLayer extends Node2D:
	var map: Node2D

	func _draw() -> void:
		map.draw_land(self)


## Mini-carte : toute la carte, les lieux, les groupes et le cadre de la caméra. Clic : y regarder.
class MiniMap extends Control:
	var map: Node2D

	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		var mm := event as InputEventMouseMotion
		if (mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT) or (mm != null and mm.button_mask & MOUSE_BUTTON_MASK_LEFT):
			var p: Vector2 = (mb.position if mb != null else mm.position) / size * MapData.SIZE
			map.look_at_point(p)
			accept_event()

	func _draw() -> void:
		map.draw_minimap(self)


func _ready() -> void:
	GameOptions.ensure_loaded()
	GameAudio.music("campaign")
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
	state.world.realtime = true
	if state.in_battle():
		if state.lenient or state.is_over():
			state.pending = {} # Mode indulgent : on revient à l'état d'avant la bataille
		else:
			# Bataille interrompue (jeu fermé, embuscade, rencontre) : elle reprend
			resuming = true
			ambushed = true
			notice = "La bataille interrompue reprend : %s." % str(state.pending.get("title", ""))
			if auto_launch:
				get_tree().change_scene_to_file.call_deferred(BATTLE_SCENE)
	state.save()
	font = ThemeDB.fallback_font
	if state.is_over():
		show_end() # Retour de la bataille décisive (ou de la dernière défaite) : place au bilan
	town_open = state.overworld.inside >= 0 and not ambushed
	build_land()
	land = LandLayer.new()
	land.map = self
	land.z_index = -1
	add_child(land)
	light = CanvasModulate.new()
	add_child(light)
	cam = Camera2D.new()
	cam.limit_left = -200
	cam.limit_top = -200
	cam.limit_right = int(MapData.SIZE.x) + 200
	cam.limit_bottom = int(MapData.SIZE.y) + 200
	add_child(cam)
	cam.make_current()
	build_ui()
	layout()
	get_viewport().size_changed.connect(layout)
	center_on(state.overworld.player.pos)
	update_light()
	refresh_ui()


## Largeur du panneau pour une vue donnée.
static func panel_width(vs: Vector2) -> float:
	return clampf(roundf(vs.x * PANEL_SHARE), PANEL_MIN, minf(PANEL_MAX, vs.x * 0.6))


func layout() -> void:
	var vs := get_viewport_rect().size
	if panel != null:
		panel.offset_left = -panel_width(vs)
	queue_redraw()


## Largeur de la carte visible à gauche du panneau (pixels d'écran).
func map_area() -> Vector2:
	var vs := get_viewport_rect().size
	return Vector2(maxf(vs.x - panel_width(vs), 1.0), vs.y)


## Centre la caméra pour que p soit au milieu de la carte visible (à gauche du panneau).
func center_on(p: Vector2) -> void:
	var vs := get_viewport_rect().size
	cam.position = p + Vector2((vs.x - map_area().x) * 0.5, 0.0) / cam.zoom.x
	clamp_camera()


func look_at_point(p: Vector2) -> void:
	center_on(p)


func clamp_camera() -> void:
	cam.position = cam.position.clamp(Vector2(-100, -100), MapData.SIZE + Vector2(100, 100))


## Partie de la carte visible à l'écran (coordonnées de la carte).
func view_rect() -> Rect2:
	var vs := get_viewport_rect().size / cam.zoom
	return Rect2(cam.position - vs * 0.5, vs)


# ---------------------------------------------------------------- Le temps

## Le temps est-il arrêté ? (pause, panneau de ville ou rencontre ouverts, bataille, fin)
func time_stopped() -> bool:
	return paused or town_open or contact != null or ambushed or state.is_over() or state.world.has_encounter()


func game_speed() -> float:
	return HOURS_PER_SECOND * float(SPEEDS[speed_index])


func _process(delta: float) -> void:
	pan_camera(delta)
	update_hover()
	if not time_stopped():
		advance_time(delta * game_speed())
	walking = not state.overworld.player.path.is_empty()
	update_top()
	queue_redraw()
	if minimap != null:
		minimap.queue_redraw()


## Fait passer hours heures de jeu et réagit aux évènements (arrivée, rencontre, embuscade, fin).
func advance_time(hours: float) -> void:
	var ow := state.overworld
	var e := ow.tick(state, hours)
	update_light()
	if e.get("day", false):
		if not state.travel_events.is_empty():
			notice = " ".join(state.travel_events)
		state.save() # Sauvegarde automatique chaque jour
	match str(e.get("event", "")):
		"enter":
			var i := int(e["place"])
			town_open = true
			notice = "La compagnie entre à %s." % MapData.place(i)["name"]
			GameAudio.ui("click")
			state.save()
		"contact":
			open_contact(ow.by_id(state, int(e["id"])))
		"battle":
			start_battle() # Embuscade de la route
		"over":
			state.save()
			show_end()
	if e.has("event") or e.get("day", false):
		refresh_ui()


func toggle_pause() -> void:
	paused = not paused
	refresh_speed_buttons()


func set_speed(i: int) -> void:
	speed_index = clampi(i, 0, SPEEDS.size() - 1)
	paused = false
	refresh_speed_buttons()


## Éclairage léger du jour et de la nuit (CanvasModulate : la carte, pas le panneau).
func update_light() -> void:
	if light == null:
		return
	light.color = daylight(state.overworld.hour)


static func daylight(hour: float) -> Color:
	var night := Color(0.55, 0.6, 0.85)
	var dusk := Color(1.0, 0.82, 0.7)
	if hour < 5.0 or hour >= 21.0:
		return night
	if hour < 7.0:
		return night.lerp(dusk, (hour - 5.0) / 2.0)
	if hour < 8.5:
		return dusk.lerp(Color.WHITE, (hour - 7.0) / 1.5)
	if hour < 18.5:
		return Color.WHITE
	if hour < 20.0:
		return Color.WHITE.lerp(dusk, (hour - 18.5) / 1.5)
	return dusk.lerp(night, hour - 20.0)


## « Jour 12 · 14 h 30 ».
func clock_text() -> String:
	var h := state.overworld.hour
	return "Jour %d · %d h %02d" % [state.day, int(h), int(fposmod(h, 1.0) * 60.0)]


# ---------------------------------------------------------------- Caméra et souris

func pan_camera(delta: float) -> void:
	if cam == null:
		return
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		v.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		v.x += 1
	if Input.is_physical_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		v.y -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		v.y += 1
	if DisplayServer.get_name() != "headless" and get_window().has_focus() and not dragging:
		var m := get_viewport().get_mouse_position()
		var area := map_area()
		if m.x >= 0 and m.y >= 0 and m.x < area.x and m.y < area.y:
			if m.x < EDGE:
				v.x -= 1
			elif m.x > area.x - EDGE:
				v.x += 1
			if m.y < EDGE:
				v.y -= 1
			elif m.y > area.y - EDGE:
				v.y += 1
	if v != Vector2.ZERO:
		cam.position += v.normalized() * PAN_SPEED * delta / cam.zoom.x
		clamp_camera()


func zoom_at(factor: float, screen: Vector2) -> void:
	var before := screen_to_world(screen)
	var z := clampf(cam.zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	cam.zoom = Vector2(z, z)
	cam.position += before - screen_to_world(screen)
	clamp_camera()


func screen_to_world(screen: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen


## Groupe sous un point de la carte (null sinon) : le plus proche dans PICK pixels d'écran.
func party_at(p: Vector2) -> Party:
	var best: Party = null
	var best_d := PICK / cam.zoom.x
	for q in state.overworld.all(state):
		if q == state.overworld.player or q.hidden or q.is_dead():
			continue
		var d := draw_spot(q).distance_to(p)
		if d < best_d:
			best_d = d
			best = q
	return best


## Où l'on dessine un groupe (une armée : à côté de la ville qu'elle assiège ou occupe).
func draw_spot(q: Party) -> Vector2:
	if q is WorldArmy:
		return WorldView.army_spot(q as WorldArmy)
	return q.pos


func update_hover() -> void:
	if cam == null:
		return
	var p := get_global_mouse_position()
	var over_ui := get_viewport().get_mouse_position().x >= map_area().x
	hover_party = null if over_ui else party_at(p)
	hover_place = -1 if over_ui or hover_party != null else MapData.place_at(p)
	if tip == null:
		return
	var lines: Array[String] = []
	if hover_party != null:
		lines = party_lines(hover_party)
	elif hover_place >= 0:
		lines = place_lines(hover_place)
	tip.visible = not lines.is_empty()
	if tip.visible:
		tip_label.text = "\n".join(lines)
		tip.reset_size()
		var m := get_viewport().get_mouse_position() + Vector2(18, 12)
		var vs := get_viewport_rect().size
		tip.position = Vector2(minf(m.x, map_area().x - tip.size.x - 4), minf(m.y, vs.y - tip.size.y - 4))


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo:
		match k.keycode:
			KEY_ESCAPE:
				back_to_menu()
			KEY_SPACE:
				toggle_pause()
			KEY_KP_1:
				set_speed(0)
			KEY_KP_2:
				set_speed(1)
			KEY_KP_3:
				set_speed(2)
			KEY_C:
				center_on(state.overworld.player.pos)
		# Vitesses : touches 1, 2, 3 de la rangée du haut (touches physiques : & é " en AZERTY)
		match k.physical_keycode:
			KEY_1:
				set_speed(0)
			KEY_2:
				set_speed(1)
			KEY_3:
				set_speed(2)
		return
	var mb := event as InputEventMouseButton
	if mb != null:
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					zoom_at(1.15, mb.position)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					zoom_at(1.0 / 1.15, mb.position)
			MOUSE_BUTTON_MIDDLE:
				dragging = mb.pressed
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					click_map(screen_to_world(mb.position))
			MOUSE_BUTTON_RIGHT:
				if mb.pressed and not time_locked():
					state.overworld.halt()
					notice = "Halte."
					refresh_ui()
		return
	var mm := event as InputEventMouseMotion
	if mm != null and dragging:
		cam.position -= mm.relative / cam.zoom.x
		clamp_camera()


## Une décision attend (rencontre, bataille) : la compagnie ne reçoit pas d'ordre de marche.
func time_locked() -> bool:
	return contact != null or ambushed or state.world.has_encounter()


## Clic sur la carte : un groupe (le poursuivre), un lieu (y aller et y entrer) ou un point.
func click_map(p: Vector2) -> void:
	if time_locked():
		notice = "Décidez d'abord de la rencontre." if not ambushed else notice
		GameAudio.ui("refuse")
		refresh_ui()
		return
	var other := party_at(p)
	if other != null:
		order(state.overworld.chase(state, other.id), "Poursuite : %s." % other.display_name())
		return
	var place := MapData.place_at(p)
	if place >= 0:
		click_place(place)
		return
	order(state.overworld.go_to(state, p), "En marche (%s)." % MapData.ground_name(p))


## Clic sur un lieu : y entrer si l'on y est déjà, sinon y marcher.
func click_place(i: int) -> void:
	if time_locked():
		return
	var ow := state.overworld
	if ow.inside == i:
		town_open = true
		notice = ""
		refresh_ui()
		return
	order(ow.go_to_place(state, i), "En marche vers %s..." % MapData.place(i)["name"])
	if ow.inside == i:
		town_open = true
		refresh_ui()


## Compatibilité : clic sur une ville (indice de CampaignState.TOWNS).
func click_town(t: int) -> void:
	click_place(t)


func order(err: String, ok_text: String) -> void:
	notice = err if err != "" else ok_text
	if err == "":
		town_open = false
		paused = false
		refresh_speed_buttons()
	GameAudio.ui("click" if err == "" else "refuse")
	refresh_ui()


## Le joueur ferme le panneau de la ville : la compagnie y reste, le temps reprend.
func close_town() -> void:
	town_open = false
	notice = "Le temps reprend. Cliquez sur la carte pour partir."
	refresh_ui()


# ---------------------------------------------------------------- Rencontres et batailles

func open_contact(other: Party) -> void:
	if other == null:
		return
	contact = other
	notice = ""
	GameAudio.ui("click")
	center_on(state.overworld.player.pos)


## Choix d'une rencontre (Overworld.options / resolve, ou encounter.gd quand il existe).
func choose(option_id: String) -> void:
	if contact == null:
		return
	var other := contact
	contact = null
	var out := state.overworld.resolve(state, other, option_id)
	notice = str(out.get("text", ""))
	if bool(out.get("battle", false)) and state.in_battle():
		start_battle()
	else:
		state.check_ruin()
		state.save()
		if state.is_over():
			show_end()
	refresh_ui()


## Lance la bataille en attente (state.pending) : sauvegarde, puis scène de bataille. Au retour,
## la carte reprend à l'endroit du combat (la position est dans la sauvegarde).
func start_battle() -> void:
	ambushed = true
	state.save()
	if auto_launch:
		get_tree().change_scene_to_file.call_deferred(BATTLE_SCENE)


## Campagne terminée (victoire ou ruine) : écran de fin.
func show_end() -> void:
	if end_requested:
		return
	end_requested = true
	if auto_launch:
		get_tree().change_scene_to_file.call_deferred(END_SCENE)


func show_end_now() -> void:
	end_requested = false
	show_end()


func do_recruit(type: String) -> void:
	notice = state.recruit(type)
	GameAudio.feedback(notice == "")
	state.save()
	refresh_ui()


func do_refill(i: int) -> void:
	notice = state.refill(i)
	GameAudio.feedback(notice == "")
	state.save()
	refresh_ui()


func do_accept(c: Dictionary) -> void:
	notice = state.accept(c)
	if notice == "":
		start_battle() # Contrat en cours sauvegardé (sauf mode indulgent) : fermer le jeu ne l'annule pas
	else:
		refresh_ui()


func do_skirmish() -> void:
	state.pending = {}
	get_tree().change_scene_to_file(BATTLE_SCENE)


func back_to_menu() -> void:
	state.save()
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


func do_new_campaign() -> void:
	if not confirm_new and not state.is_ruined() and not state.is_over():
		confirm_new = true # Il faut cliquer une seconde fois
		refresh_ui()
		return
	confirm_new = false
	CampaignState.current = CampaignState.new_game(0, state.difficulty, state.lenient) # Mêmes réglages qu'avant
	state = CampaignState.current
	state.world.realtime = true
	state.save()
	end_requested = false
	contact = null
	town_open = true
	notice = "Nouvelle campagne."
	center_on(state.overworld.player.pos)
	refresh_ui()


func cancel_new_campaign() -> void:
	confirm_new = false
	refresh_ui()


# ---------------------------------------------------------------- Interface

func build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var th := make_theme()
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -400.0
	panel.offset_right = 0.0
	panel.theme = th
	layer.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	box = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 5)
	scroll.add_child(box)
	# Barre du temps, en haut à gauche : date, heure, météo, pause et vitesses
	var bar := PanelContainer.new()
	bar.theme = th
	bar.position = Vector2(10, 10)
	layer.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	bar.add_child(row)
	top_label = Label.new()
	top_label.add_theme_font_size_override("font_size", 14)
	top_label.add_theme_color_override("font_color", GOLD_COL)
	row.add_child(top_label)
	var pause := Button.new()
	pause.text = "Pause"
	pause.focus_mode = Control.FOCUS_NONE
	pause.toggle_mode = true
	pause.pressed.connect(toggle_pause)
	row.add_child(pause)
	speed_buttons.append(pause)
	for i in SPEEDS.size():
		var b := Button.new()
		b.text = "x%d" % SPEEDS[i]
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.pressed.connect(set_speed.bind(i))
		row.add_child(b)
		speed_buttons.append(b)
	refresh_speed_buttons()
	# Mini-carte en bas à gauche
	minimap = MiniMap.new()
	minimap.map = self
	minimap.custom_minimum_size = Vector2(220, 180)
	minimap.size = Vector2(220, 180)
	minimap.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	minimap.position = Vector2(10, get_viewport_rect().size.y - 190)
	minimap.offset_top = -190
	minimap.offset_bottom = -10
	minimap.offset_left = 10
	minimap.offset_right = 230
	layer.add_child(minimap)
	# Infobulle
	tip = PanelContainer.new()
	tip.theme = th
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip.visible = false
	tip_label = Label.new()
	tip_label.add_theme_font_size_override("font_size", 12)
	tip.add_child(tip_label)
	layer.add_child(tip)


func refresh_speed_buttons() -> void:
	for i in speed_buttons.size():
		speed_buttons[i].button_pressed = paused if i == 0 else (not paused and speed_index == i - 1)


func update_top() -> void:
	if top_label == null:
		return
	var s := "%s  ·  %s" % [clock_text(), state.world.calendar_text(state.day)]
	if time_stopped() and not paused:
		s += "  ·  temps arrêté"
	top_label.text = s


func make_theme() -> Theme:
	var th := Theme.new()
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.11, 0.08, 0.06, 0.95)
	bg.border_color = Color(0.45, 0.35, 0.2)
	bg.set_border_width_all(1)
	bg.border_width_left = 2
	bg.set_content_margin_all(10)
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
				sb.bg_color = Color(0.55, 0.38, 0.15)
				sb.border_color = GOLD_COL
			"disabled":
				sb.bg_color = Color(0.18, 0.15, 0.12)
				sb.border_color = Color(0.3, 0.27, 0.22)
			"focus":
				sb.draw_center = false
		th.set_stylebox(st, "Button", sb)
	th.set_color("font_color", "Button", Color(1, 0.93, 0.78))
	th.set_color("font_hover_color", "Button", Color(1, 1, 0.85))
	th.set_color("font_pressed_color", "Button", Color(1, 1, 0.9))
	th.set_color("font_disabled_color", "Button", Color(0.55, 0.5, 0.42))
	th.set_font_size("font_size", "Button", 13)
	th.set_color("font_color", "Label", Color(0.92, 0.88, 0.78))
	th.set_font_size("font_size", "Label", 13)
	return th


func add_label(s: String, size := 13, col := Color(0.92, 0.88, 0.78)) -> Label:
	var l := Label.new()
	l.text = s
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 0 # Prend la largeur du panneau (qui suit celle de la fenêtre)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	box.add_child(l)
	return l


func add_button(s: String, cb: Callable, enabled := true, parent: Control = null) -> Button:
	var b := Button.new()
	b.text = s
	b.disabled = not enabled
	b.focus_mode = Control.FOCUS_NONE
	if parent == null:
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART # Panneau étroit : le texte passe à la ligne
	b.pressed.connect(cb)
	(parent if parent != null else box).add_child(b)
	return b


func add_section(s: String) -> void:
	box.add_child(HSeparator.new())
	add_label(s, 15, GOLD_COL)


## Lieu (ville) où l'on peut signer et recruter : la ville où la compagnie est entrée, -1 sinon.
func town_here() -> int:
	var i := state.overworld.inside
	return i if i >= 0 and i < CampaignState.TOWNS.size() and town_open else -1


func refresh_ui() -> void:
	if box == null:
		return
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	var here := town_here()
	var closed := state.closed_message(here) if here >= 0 else ""
	add_label("COMPAGNIE FRANCHE", 19, GOLD_COL)
	add_label("Jour %d   ·   %d écus   ·   solde %d écus / jour" % [state.day, int(state.gold), ceili(state.daily_wage())], 14)
	add_label("Victoires %d   ·   défaites %d   ·   %s   ·   renommée %d" % [state.victories, state.defeats, CampaignState.plural(state.total_men(), "homme", "hommes"), state.fame], 12, Color(0.75, 0.72, 0.65))
	add_label("Ennemis tués %d   ·   hommes perdus %d   ·   or gagné %d écus" % [state.enemies_killed, state.men_lost, state.gold_earned], 12, Color(0.75, 0.72, 0.65))
	if notice != "":
		add_label(notice, 13, Color(1, 0.62, 0.3))
	build_contact()
	WorldView.build_encounter(self) # Ancienne rencontre d'une sauvegarde : bataille ou fuite

	add_section("Objectif")
	add_label(state.objective_status(), 12, Color(1, 0.9, 0.7))
	if state.is_over():
		add_button("Voir le bilan de la campagne", show_end_now)

	var ow := state.overworld
	if here >= 0:
		build_town(here, closed)
	elif ow.inside >= 0:
		add_section("À %s" % MapData.place(ow.inside)["name"])
		add_label(place_lines(ow.inside)[1], 12, Color(0.75, 0.72, 0.65))
		if town_open:
			add_label("Un lieu calme : rien à y faire pour l'instant.", 12, Color(0.75, 0.72, 0.65))
			add_button("Repartir (le temps reprend)", close_town)
	else:
		add_section("En campagne")
		add_label(where_text(), 12, Color(0.75, 0.72, 0.65))

	build_company(here, closed)
	if here >= 0:
		CompanyPanel.build(self) # Capitaine, traits et équipement (achats en ville)
		build_recruits(here, closed)
		build_contracts(here, closed)

	WorldView.build_world(self) # Saison, météo, guerres, sièges, nouvelles

	add_section("Réputation")
	for f in CampaignState.FACTIONS.size():
		add_label("%s : %+d (%s)" % [CampaignState.faction_name(f), state.reputation[f], state.reputation_label(f)], 12, CampaignState.FACTIONS[f]["color"])
	add_label("Un contrat gagné plaît à qui paie et fâche sa rivale ; la réputation fait varier la prime. Sous %d, la faction ferme ses portes." % CampaignState.REP_CLOSED, 11, Color(0.6, 0.58, 0.52))

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
	add_label("Sauvegarde automatique chaque jour, à chaque arrivée, recrutement et bataille.", 11, Color(0.6, 0.58, 0.52))
	add_label("Clic gauche : marcher (sur une ville : y entrer ; sur un groupe : le poursuivre). Clic droit : halte. Espace : pause ; 1, 2, 3 : vitesses. ZQSD, flèches, bord de l'écran ou clic molette : déplacer la vue ; molette : zoom ; C : recentrer. La route va plus vite, forêts, collines et marais ralentissent, l'hiver aussi. Chaque jour coûte la solde ; sans or, des hommes désertent. Les bandits et les armées hostiles (cerclés de rouge) vous attaquent s'ils vous rattrapent.", 11, Color(0.6, 0.58, 0.52))


## Où est la compagnie, et ce qu'elle fait.
func where_text() -> String:
	var ow := state.overworld
	var p := ow.player
	var town := MapData.nearest_town(p.pos)
	var s := "Près de %s, en %s." % [CampaignState.TOWNS[town]["name"], MapData.ground_name(p.pos)]
	if p.target_id >= 0:
		var t := ow.by_id(state, p.target_id)
		if t != null:
			s += " Elle poursuit %s." % t.display_name()
	elif ow.enter_goal >= 0:
		var left := MapData.path_length(p.pos, p.path)
		var hours := left / maxf(1.0, Overworld.speed_of(state, p))
		s += " En marche vers %s (environ %d h)." % [MapData.place(ow.enter_goal)["name"], ceili(hours)]
	elif not p.path.is_empty():
		s += " En marche."
	else:
		s += " À l'arrêt."
	if p.busy_hours > 0.0:
		s += " Immobilisée encore %d h." % ceili(p.busy_hours)
	return s


## Rencontre en cours : description et choix.
func build_contact() -> void:
	if contact == null:
		return
	var ow := state.overworld
	add_section("Rencontre : %s" % CampaignState.cap_first(contact.display_name()))
	var lines := party_lines(contact)
	add_label(" · ".join(lines.slice(1, lines.size() - 1)), 12, Color(1, 0.5, 0.4) if ow.hostile(state, contact) else Color(0.92, 0.88, 0.78))
	add_label("Terrain du combat : %s." % str(Terrain.NAMES.get(MapData.battle_terrain_at(ow.player.pos), "plaine")).to_lower(), 12, Color(0.75, 0.72, 0.65))
	for o in ow.options(state, contact):
		var text := str(o.get("text", o.get("label", o.get("id", "?"))))
		add_button(text, choose.bind(str(o.get("id", ""))), bool(o.get("enabled", true)) and (str(o.get("id", "")) != "attack" or not state.is_destroyed()))


func build_town(here: int, closed: String) -> void:
	var town: Dictionary = CampaignState.TOWNS[here]
	add_section("À %s" % town["name"])
	var fac := state.town_owner(here)
	add_label("%s — réputation %+d (%s)" % [CampaignState.faction_name(fac), state.reputation[fac], state.reputation_label(fac)], 12, CampaignState.FACTIONS[fac]["color"])
	if closed != "":
		add_label(closed + " Ni contrat ni recrutement ici.", 12, Color(1, 0.5, 0.4))
	var names: Array[String] = []
	for t in town["recruits"]:
		names.append(CampaignState.type_name(t).to_lower())
	add_label("On y lève : %s.   Prix des recrues : %s" % [", ".join(names), price_text(here)], 12, Color(0.75, 0.72, 0.65))
	add_label("Le temps est arrêté tant que vous êtes dans la ville.", 11, Color(0.6, 0.58, 0.52))
	add_button("Quitter le panneau (le temps reprend, la compagnie reste en ville)", close_town)


func build_company(here: int, closed: String) -> void:
	add_section("Votre compagnie")
	if state.is_destroyed():
		if state.is_ruined():
			add_label("Plus personne ne marche sous votre bannière, et les caisses sont vides...", 13, Color(1, 0.5, 0.4))
			add_button("Recommencer une campagne", do_new_campaign)
		else:
			add_label("Plus personne ne marche sous votre bannière. Levez un régiment en ville pour reprendre la route.", 13, Color(1, 0.5, 0.4))
	var recruits: Array = CampaignState.TOWNS[here]["recruits"] if here >= 0 else []
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


func build_recruits(here: int, closed: String) -> void:
	add_section("Lever un régiment")
	for t in TYPE_ORDER:
		if not t in CampaignState.TOWNS[here]["recruits"]:
			continue
		var men: int = UnitTypes.STATS[t]["count"]
		var cost := state.recruit_cost(t, men)
		var ok := state.gold >= cost and state.company.size() < CampaignState.MAX_REGIMENTS and closed == ""
		add_button("%s : %d hommes, %d écus (solde %.0f / jour)" % [CampaignState.type_name(t), men, cost, men * float(CampaignState.WAGE[t])], do_recruit.bind(t), ok)
	if state.company.size() >= CampaignState.MAX_REGIMENTS:
		add_label("La compagnie compte déjà %d régiments." % CampaignState.MAX_REGIMENTS, 12, Color(0.75, 0.72, 0.65))


func build_contracts(here: int, closed: String) -> void:
	add_section("Contrats")
	var list := state.contracts_at(here)
	if list.is_empty():
		add_label("Aucun contrat ici. Les villes marquées d'un drapeau rouge en proposent.", 12, Color(0.75, 0.72, 0.65))
	for c in list:
		if c.get("final", false):
			add_label("★ CONTRAT FINAL ★", 13, GOLD_COL)
		add_label(str(c["title"]), 14, Color(1, 0.9, 0.7))
		add_label(str(c["text"]), 12, Color(0.8, 0.77, 0.7))
		add_label(CampaignState.objective_line(c), 12, Color(0.95, 0.85, 0.6))
		add_label("Ennemi : %s" % CampaignState.army_summary(c["enemy"]), 12)
		add_label("Prime : %d écus   ·   difficulté %s   ·   jusqu'au jour %d" % [state.contract_reward(c), stars(int(c["difficulty"])), int(c["expires"])], 12, GOLD_COL)
		add_button("Accepter et livrer bataille", do_accept.bind(c), not state.is_destroyed() and not state.is_over() and not ambushed and closed == "" and contact == null and not state.world.has_encounter())


## Difficulté d'un contrat en étoiles : « ★★★☆☆ ».
static func stars(d: int) -> String:
	var m := CampaignState.MAX_LEVEL
	d = clampi(d, 0, m)
	return "★".repeat(d) + "☆".repeat(m - d)


## « normal », « +15 % », « -10 % » : prix des recrues d'une ville.
func price_text(town: int) -> String:
	var p := int(round((float(CampaignState.TOWNS[town]["price"]) - 1.0) * 100.0))
	return "normal" if p == 0 else "%+d %%" % p


## Infobulle d'un lieu.
func place_lines(i: int) -> Array[String]:
	var pl := MapData.place(i)
	var lines: Array[String] = [str(pl["name"])]
	var kind_name := {"town": "ville", "village": "village", "castle": "château"}
	if i < CampaignState.TOWNS.size():
		var fi := state.town_owner(i)
		lines.append("Ville de %s (%s)" % [CampaignState.faction_name(fi), state.reputation_label(fi)])
		var names: Array[String] = []
		for t in CampaignState.TOWNS[i]["recruits"]:
			names.append(CampaignState.type_name(t).to_lower())
		lines.append("Recrues : %s (prix %s)" % [", ".join(names), price_text(i)])
		for c in state.contracts_at(i):
			lines.append("Contrat : %s (%d écus)" % [c["title"], state.contract_reward(c)])
		if state.town_besieged(i):
			lines.append("Assiégée !")
	else:
		var f := int(pl["faction"])
		lines.append("%s%s" % [CampaignState.cap_first(str(kind_name.get(pl["kind"], pl["kind"]))), (" de %s" % CampaignState.FACTIONS[f]["short"]) if f >= 0 else ""])
	var ow := state.overworld
	if ow.inside == i:
		lines.append("Vous êtes ici")
	else:
		var path := MapData.find_path(ow.player.pos, MapData.place_pos(i))
		var hours := MapData.path_length(ow.player.pos, path) / maxf(1.0, Overworld.speed_of(state, ow.player))
		lines.append("Environ %d h de marche" % ceili(hours))
	return lines


## Infobulle d'un groupe.
func party_lines(q: Party) -> Array[String]:
	var lines: Array[String] = [CampaignState.cap_first(q.display_name())]
	if q is WorldArmy:
		var a := q as WorldArmy
		lines.append(CampaignState.plural(a.force, "homme", "hommes") + ", " + a.doing())
	else:
		lines.append(CampaignState.plural(q.men(), "homme", "hommes"))
		if q.faction >= 0:
			lines.append("Bannière de %s" % CampaignState.FACTIONS[q.faction]["short"])
	if state.overworld.hostile(state, q):
		lines.append("Hostile : il attaquera la compagnie qui passe à sa portée")
	lines.append("Clic : le poursuivre et le rencontrer")
	return lines


# ---------------------------------------------------------------- Fond de carte

## Fond pixel art construit une fois par partie d'après MapData (la carte est toujours la même).
func build_land() -> void:
	if land_tex != null:
		return
	var g := MapData.grid_size()
	var w := int(MapData.SIZE.x) / PIX
	var h := int(MapData.SIZE.y) / PIX
	var per := int(MapData.CELL) / PIX
	var cols: Array[Color] = [Color(0.56, 0.63, 0.34), Color(0.3, 0.45, 0.22), Color(0.62, 0.58, 0.4), Color(0.42, 0.5, 0.38), Color(0.3, 0.47, 0.66)]
	var cell_col := PackedColorArray()
	cell_col.resize(g.x * g.y)
	var river_cell := PackedByteArray() # Case d'eau de la rivière (pas d'un lac) : dessinée au pixel près
	river_cell.resize(g.x * g.y)
	for cy in g.y:
		for cx in g.x:
			var c := Vector2i(cx, cy)
			var gr := MapData.ground_cell(c)
			var col: Color = cols[gr]
			var hgt := MapData.height_cell(c)
			if gr != MapData.Ground.WATER:
				col = col.lerp(col.darkened(0.25), clampf(hgt, 0.0, 1.0))
			cell_col[cy * g.x + cx] = col
			if gr == MapData.Ground.WATER and MapData.lake_factor(MapData.cell_center(c)) >= 1.0:
				river_cell[cy * g.x + cx] = 1
				cell_col[cy * g.x + cx] = Color(0.5, 0.52, 0.34) # Berge
			if gr == MapData.Ground.FOREST and (cx * 7 + cy * 13) % 3 == 0:
				tree_spots.append(MapData.cell_center(c) + Vector2(((cx * 31 + cy * 17) % 9) - 4, ((cx * 11 + cy * 29) % 9) - 4))
	var data := PackedByteArray()
	data.resize(w * h * 3)
	var k := 0
	var water: Color = cols[MapData.Ground.WATER]
	for y in h:
		var cy := mini(y / per, g.y - 1)
		var rx := MapData.river_x((y + 0.5) * PIX)
		for x in w:
			var ci := cy * g.x + mini(x / per, g.x - 1)
			var col := cell_col[ci]
			var dr := absf((x + 0.5) * PIX - rx)
			if dr < MapData.RIVER_HALF:
				col = water
			elif river_cell[ci] == 0 and dr < MapData.RIVER_HALF + 6.0 and MapData.ground_cell(Vector2i(mini(x / per, g.x - 1), cy)) != MapData.Ground.WATER:
				col = Color(0.5, 0.52, 0.34)
			var hsh := (x * 73856093) ^ (y * 19349663)
			var bump := 0.06 if hsh % 17 == 0 else (-0.04 if hsh % 23 == 0 else 0.0)
			data[k] = clampi(int((col.r + bump) * 255.0), 0, 255)
			data[k + 1] = clampi(int((col.g + bump) * 255.0), 0, 255)
			data[k + 2] = clampi(int((col.b + bump) * 255.0), 0, 255)
			k += 3
	var img := Image.create_from_data(w, h, false, Image.FORMAT_RGB8, data)
	land_tex = ImageTexture.create_from_image(img)
	tree_spots.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.y < b.y)


## Dessin du fond (LandLayer) : fond, routes, ponts, arbres.
func draw_land(ci: CanvasItem) -> void:
	ci.draw_rect(Rect2(Vector2(-400, -400), MapData.SIZE + Vector2(800, 800)), MAP_BG)
	ci.draw_texture_rect(land_tex, Rect2(Vector2.ZERO, MapData.SIZE), false)
	for road in MapData.roads():
		var a := MapData.place_pos(road[0])
		var b := MapData.place_pos(road[1])
		var big: bool = road[0] < CampaignState.TOWNS.size() and road[1] < CampaignState.TOWNS.size()
		ci.draw_line(a, b, Color(0.35, 0.25, 0.14), 8.0 if big else 5.0)
		ci.draw_line(a, b, Color(0.72, 0.6, 0.4) if big else Color(0.62, 0.52, 0.34), 4.0 if big else 2.5)
		# Pont là où la route franchit la rivière
		var n := int(a.distance_to(b) / 8.0)
		for i in n:
			var p := a.lerp(b, float(i) / n)
			if MapData.river_distance(p) < 4.0:
				var r := Rect2(p - Vector2(12, 7), Vector2(24, 14))
				ci.draw_rect(r, Color(0.45, 0.33, 0.2))
				ci.draw_rect(r, Color(0.25, 0.17, 0.1), false, 2.0)
				break
	for t in tree_spots:
		if sprites.has_trees():
			var tr := sprites.tree_at(t)
			var src: Rect2 = tr["src"]
			ci.draw_texture_rect_region(tr["tex"], Rect2(t.round() - Vector2(8, 15), src.size), src)
		else:
			ci.draw_rect(Rect2(t.x - 1, t.y - 3, 2, 3), WOOD)
			ci.draw_rect(Rect2(t.x - 4, t.y - 10, 8, 7), Color(0.15, 0.32, 0.14))


# ---------------------------------------------------------------- Rendu de la couche vivante

func _draw() -> void:
	var ow := state.overworld
	var view := view_rect().grow(80)
	for i in MapData.place_count():
		if view.has_point(MapData.place_pos(i)):
			draw_place(i)
	WorldView.draw_world(self) # Sièges et armées des factions
	for q in ow.parties:
		if not q.hidden and view.has_point(q.pos):
			draw_group(q)
	if hover_party != null:
		draw_arc(draw_spot(hover_party), 16.0, 0, TAU, 24, Color(1, 1, 1, 0.8), 2.0)
	# Chemin de la compagnie, en pointillés
	var p := ow.player
	var at := p.pos
	for q in p.path:
		var d := at.distance_to(q)
		var n := int(d / 14.0)
		for k in n:
			if k % 2 == 0:
				draw_line(at.lerp(q, float(k) / maxi(n, 1)), at.lerp(q, float(k + 1) / maxi(n, 1)), Color(1, 0.95, 0.75, 0.7), 2.0)
		at = q
	if not p.path.is_empty():
		draw_arc(p.path[-1], 6.0, 0, TAU, 12, GOLD_COL, 2.0)
	draw_company(p.pos + Vector2(-4, -18))
	WorldView.draw_weather(self, view_rect()) # Voile de saison, pluie ou neige


## Un lieu : ville fortifiée, village ou château, avec son nom.
func draw_place(i: int) -> void:
	var pl := MapData.place(i)
	var p := (pl["pos"] as Vector2).round()
	var ow := state.overworld
	var here := ow.inside == i
	var r := MapData.PLACE_RADIUS
	if here:
		draw_circle(p, r, Color(1, 0.84, 0.4, 0.22))
		draw_arc(p, r, 0, TAU, 32, GOLD_COL, 2.0)
	elif i == hover_place:
		draw_arc(p, r, 0, TAU, 32, Color(1, 1, 1, 0.8), 2.0)
	match str(pl["kind"]):
		"town":
			draw_town(i)
		"castle":
			draw_castle(p, int(pl["faction"]))
		_:
			draw_village(p)
	var name := str(pl["name"])
	var size := 14 if pl["kind"] == "town" else 11
	var col := GOLD_COL if here else (Color(1, 1, 1) if pl["kind"] == "town" else Color(0.9, 0.86, 0.78))
	draw_string(font, p + Vector2(-79, 37), name, HORIZONTAL_ALIGNMENT_CENTER, 160, size, Color(0, 0, 0, 0.8))
	draw_string(font, p + Vector2(-80, 36), name, HORIZONTAL_ALIGNMENT_CENTER, 160, size, col)


## Petite ville fortifiée dessinée en pixels (x2), drapeau des contrats, couleurs de la faction.
func draw_town(i: int) -> void:
	var p := MapData.place_pos(i).round()
	draw_set_transform(p, 0.0, Vector2(2, 2))
	var stone := Color(0.7, 0.68, 0.62)
	var dark := Color(0.3, 0.28, 0.26)
	var roof := Color(0.66, 0.24, 0.16)
	draw_rect(Rect2(-9, -2, 18, 7), dark)
	draw_rect(Rect2(-8, -3, 16, 7), stone)
	for k in 4:
		draw_rect(Rect2(-8 + k * 5, -4, 2, 1), stone)
	draw_rect(Rect2(-1, 1, 3, 3), dark)
	draw_rect(Rect2(-10, -8, 4, 12), stone)
	draw_rect(Rect2(6, -8, 4, 12), stone)
	draw_rect(Rect2(-11, -10, 6, 2), roof)
	draw_rect(Rect2(5, -10, 6, 2), roof)
	draw_rect(Rect2(-4, -8, 3, 4), Color(0.85, 0.78, 0.6))
	draw_rect(Rect2(-5, -9, 5, 1), roof)
	draw_rect(Rect2(1, -9, 3, 5), Color(0.85, 0.78, 0.6))
	draw_rect(Rect2(0, -10, 5, 1), roof)
	draw_set_transform(Vector2.ZERO)
	var n := state.contracts_at(i).size()
	if n > 0:
		var f := p + Vector2(14, -22)
		draw_line(f, f + Vector2(0, 14), WOOD, 2.0)
		var final_here := int(state.final_contract().get("town", -1)) == i
		draw_rect(Rect2(f, Vector2(10, 7)), GOLD_COL if final_here else Color(0.8, 0.15, 0.12))
		draw_string(font, f + Vector2(2, 6), str(n), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.2, 0.1, 0.02) if final_here else Color.WHITE)
	var fcol: Color = CampaignState.FACTIONS[state.town_owner(i)]["color"]
	var bar := Rect2(p + Vector2(-22, 40), Vector2(44, 4))
	draw_rect(bar.grow(1), Color(0, 0, 0, 0.7))
	draw_rect(bar, fcol)
	if state.faction_closed(state.town_owner(i)):
		for k in 4:
			draw_rect(Rect2(bar.position + Vector2(4 + k * 11, 0), Vector2(5, 4)), Color(0.55, 0.08, 0.06))


func draw_village(p: Vector2) -> void:
	var wall := Color(0.85, 0.78, 0.6)
	var roof := Color(0.55, 0.35, 0.2)
	for h in [Vector2(-10, 0), Vector2(4, -4), Vector2(-2, 6)]:
		draw_rect(Rect2(p + h + Vector2(0, 1), Vector2(10, 7)), Color(0, 0, 0, 0.3))
		draw_rect(Rect2(p + h, Vector2(9, 6)), wall)
		draw_rect(Rect2(p + h + Vector2(-1, -3), Vector2(11, 3)), roof)
		draw_rect(Rect2(p + h + Vector2(4, 3), Vector2(2, 3)), Color(0.3, 0.2, 0.12))


func draw_castle(p: Vector2, f: int) -> void:
	var stone := Color(0.62, 0.6, 0.56)
	draw_rect(Rect2(p + Vector2(-9, -6), Vector2(20, 16)), Color(0, 0, 0, 0.3))
	draw_rect(Rect2(p + Vector2(-10, -8), Vector2(20, 16)), stone)
	draw_rect(Rect2(p + Vector2(-4, -20), Vector2(8, 14)), stone.lightened(0.1))
	for k in 3:
		draw_rect(Rect2(p + Vector2(-10 + k * 8, -10), Vector2(4, 2)), stone)
	draw_rect(Rect2(p + Vector2(-2, 2), Vector2(4, 6)), Color(0.25, 0.2, 0.18))
	draw_line(p + Vector2(0, -20), p + Vector2(0, -30), WOOD, 1.5)
	var col: Color = CampaignState.FACTIONS[f]["color"] if f >= 0 else Color(0.6, 0.6, 0.6)
	draw_rect(Rect2(p + Vector2(1, -30), Vector2(8, 5)), col)


## Un groupe errant : quelques silhouettes de sa couleur, sa bannière, son effectif.
func draw_group(q: Party) -> void:
	var p := q.pos.round()
	var col: Color = KIND_COLORS.get(q.kind, Color(0.7, 0.7, 0.7))
	var hostile := state.overworld.hostile(state, q)
	draw_circle(p + Vector2(0, 5), 9.0, Color(0, 0, 0, 0.25))
	if hostile:
		draw_arc(p + Vector2(0, 1), 12.0, 0, TAU, 20, Color(0.9, 0.15, 0.1, 0.9), 1.5)
	var n := clampi(ceili(q.men() / 12.0), 1, 4)
	for k in n:
		var s := p + Vector2(-5 + k * 4, 4 - (k % 2) * 2)
		draw_rect(Rect2(s + Vector2(0, -4), Vector2(3, 5)), col)
		draw_rect(Rect2(s + Vector2(0, -6), Vector2(3, 2)), Color(0.85, 0.75, 0.6))
	if q.kind == "caravan":
		draw_rect(Rect2(p + Vector2(4, -2), Vector2(10, 6)), Color(0.55, 0.4, 0.22))
		draw_rect(Rect2(p + Vector2(4, -5), Vector2(10, 3)), Color(0.9, 0.88, 0.8))
		draw_circle(p + Vector2(6, 5), 1.5, Color(0.2, 0.15, 0.1))
		draw_circle(p + Vector2(12, 5), 1.5, Color(0.2, 0.15, 0.1))
	elif q.kind == "bandits":
		draw_line(p + Vector2(-8, -10), p + Vector2(-8, 3), WOOD, 1.5)
		draw_rect(Rect2(p + Vector2(-7, -10), Vector2(7, 5)), Color(0.15, 0.12, 0.1))
	var label := str(q.men())
	draw_string(font, p + Vector2(-12, 18), label, HORIZONTAL_ALIGNMENT_CENTER, 24, 10, Color(0, 0, 0, 0.85))
	draw_string(font, p + Vector2(-13, 17), label, HORIZONTAL_ALIGNMENT_CENTER, 24, 10, Color(1, 0.6, 0.5) if hostile else Color(1, 0.95, 0.85))


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


## Mini-carte (MiniMap._draw).
func draw_minimap(ci: Control) -> void:
	var size := ci.size
	var k := size / MapData.SIZE
	ci.draw_rect(Rect2(Vector2.ZERO, size).grow(2), Color(0.1, 0.07, 0.05))
	ci.draw_texture_rect(land_tex, Rect2(Vector2.ZERO, size), false)
	for road in MapData.roads():
		ci.draw_line(MapData.place_pos(road[0]) * k, MapData.place_pos(road[1]) * k, Color(0.72, 0.6, 0.4), 1.0)
	for i in MapData.place_count():
		var pl := MapData.place(i)
		var col := Color(0.9, 0.86, 0.78)
		if i < CampaignState.TOWNS.size():
			col = CampaignState.FACTIONS[state.town_owner(i)]["color"]
		var r := 3.0 if pl["kind"] == "town" else 1.5
		ci.draw_rect(Rect2(MapData.place_pos(i) * k - Vector2(r, r), Vector2(r, r) * 2), col)
	var ow := state.overworld
	for q in ow.all(state):
		if q == ow.player or q.hidden:
			continue
		var col: Color = Color(0.9, 0.15, 0.1) if ow.hostile(state, q) else (CampaignState.FACTIONS[q.faction]["color"] if q is WorldArmy else Color(1, 1, 1, 0.8))
		ci.draw_circle(q.pos * k, 2.0 if q is WorldArmy else 1.5, col)
	ci.draw_circle(ow.player.pos * k, 3.0, BLUE.lightened(0.3))
	ci.draw_arc(ow.player.pos * k, 4.0, 0, TAU, 12, Color.WHITE, 1.0)
	if cam != null:
		var v := view_rect()
		v.size.x *= map_area().x / get_viewport_rect().size.x # La partie cachée par le panneau
		ci.draw_rect(Rect2(v.position * k, v.size * k), Color(1, 1, 1, 0.8), false, 1.0)
	ci.draw_rect(Rect2(Vector2.ZERO, size), Color(0.6, 0.47, 0.25), false, 1.0)
