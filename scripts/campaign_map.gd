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

const WINDOW_W := 560.0 ## Largeur des fenêtres (ville, rencontre, compagnie...)
const MARGIN := 40.0 ## La vue peut dépasser le bord de la carte de tant (pixels de carte)
const TOAST_SECONDS := 5.0 ## Durée d'affichage d'un message
const MAP_BG := Color(0.09, 0.07, 0.05)
const HOURS_PER_SECOND := 1.5 ## Heures de jeu par seconde à la vitesse x1
const SPEEDS := [1, 2, 4]
const ZOOM_MIN := 0.3
const ZOOM_MAX := 2.5
const PAN_SPEED := 900.0 ## Défilement au clavier, pixels d'écran par seconde
const EDGE := 12.0 ## Largeur du bord d'écran qui fait défiler
const MINIMAP_W := 250.0 ## Largeur de la mini-carte (pixels d'écran)
const PICK := 16.0 ## Rayon de clic d'un groupe (pixels d'écran)
const GOLD_COL := Color(1, 0.84, 0.4)
const DIM_COL := Color(0.75, 0.72, 0.65)
const HINT_COL := Color(0.6, 0.58, 0.52)
const BLUE := Color(0.22, 0.38, 0.85)
const WOOD := Color(0.48, 0.32, 0.17)
const TYPE_ORDER := UnitTypes.ORDER
const KIND_COLORS := {"villagers": Color(0.7, 0.55, 0.3), "bandits": Color(0.55, 0.1, 0.08), "caravan": Color(0.85, 0.7, 0.3),
	"patrol": Color(0.4, 0.5, 0.75), "deserters": Color(0.5, 0.5, 0.5)}
const END_SCENE := "res://scenes/end.tscn"
const BATTLE_SCENE := "res://scenes/main.tscn"

var state: CampaignState
var font: Font
var sprites := SpriteBank.new()
var cam: Camera2D
var land: Node2D ## Fond uni autour de la carte
var terrain: Node2D ## Terrain peint par le shader (MapRender)
var roads_layer: Node2D ## Routes, ponts et noms des forêts, chaînes, lacs et rivières
var sky_layers: Array[Node2D] = [] ## Brouillard, nuit, lumières, pluie (MapSky), au-dessus des groupes
var ground_mat: ShaderMaterial ## Matériau du terrain (saisons)
var season := {} ## Mélange des saisons (MapSky.season), mis à jour avec l'heure
var trails := {} ## Trace de marche de chaque groupe : id -> Array[Vector2] (non sauvegardé)
var facing := {} ## Sens de chaque groupe : id -> -1 (vers l'ouest) ou 1
var notice := "" ## Message d'information ou de refus (affiché en bas de l'écran, puis effacé)
var box: VBoxContainer ## Contenu de la fenêtre ouverte
var panel: PanelContainer ## Fenêtre au centre : cachée quand il n'y a rien à montrer
var scroll: ScrollContainer
var window_title: Label
var close_button: Button
var bar: PanelContainer ## Barre du haut : date, or, effectif, temps, onglets
var top_label: Label
var view_buttons := {} ## Onglet -> bouton de la barre
var view := "" ## Onglet ouvert par le joueur : "", "company", "world", "journal", "menu"
var toast: PanelContainer
var toast_label: Label
var toast_time := 0.0
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


## Fond uni autour de la carte : dessiné une fois.
class LandLayer extends Node2D:
	func _draw() -> void:
		draw_rect(Rect2(Vector2(-600, -600), MapData.SIZE + Vector2(1200, 1200)), MAP_BG)


## Terrain : un rectangle de la taille de la carte peint par le shader de MapRender (champs
## précalculés une fois). Dessiné une fois ; le GPU s'occupe du reste.
class TerrainLayer extends Node2D:
	func _draw() -> void:
		draw_texture_rect(MapRender.fields_tex, Rect2(Vector2.ZERO, MapData.SIZE), false)


## Routes, ponts, noms des forêts, chaînes, lacs et rivières : dessinés une fois.
class RoadLayer extends Node2D:
	var font: Font

	func _draw() -> void:
		MapRender.draw_relief(self)
		MapRender.draw_roads(self)
		MapRender.draw_feature_names(self, font)


## Mini-carte : toute la carte (le shader du fond, sans détails), les lieux, les groupes et le
## cadre de la caméra. Clic ou glisser : y regarder.
class MiniMap extends Control:
	var map: Node2D
	var overlay: Control
	var ground: ShaderMaterial ## Matériau du fond (mêmes saisons que la carte)

	func setup() -> void:
		var tr := TextureRect.new()
		tr.texture = MapRender.fields_tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		ground = MapRender.material(0.0)
		tr.material = ground
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tr)
		overlay = MiniOverlay.new()
		overlay.map = map
		overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(overlay)

	func redraw() -> void:
		if overlay != null:
			overlay.queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		var mm := event as InputEventMouseMotion
		if (mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT) or (mm != null and mm.button_mask & MOUSE_BUTTON_MASK_LEFT):
			var p: Vector2 = (mb.position if mb != null else mm.position) / size * MapData.SIZE
			map.look_at_point(p)
			accept_event()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size).grow(3), Color(0.1, 0.07, 0.05))


## Ce que la mini-carte montre par-dessus le terrain : routes, lieux, groupes, vue de la caméra.
class MiniOverlay extends Control:
	var map: Node2D

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
			CampaignState.current = CampaignState.new_game(0, Difficulty.NORMAL, false, true)
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
	MapRender.build()
	land = LandLayer.new()
	land.z_index = -4
	add_child(land)
	terrain = TerrainLayer.new()
	terrain.z_index = -3
	ground_mat = MapRender.material(1.0)
	terrain.material = ground_mat
	add_child(terrain)
	roads_layer = RoadLayer.new()
	roads_layer.font = ThemeDB.fallback_font
	roads_layer.z_index = -2
	add_child(roads_layer)
	# Brouillard, nuit (multiplication), lumières (addition), pluie : par-dessus les groupes
	var z := 1
	for layer: Node2D in [MapSky.FogLayer.new(), MapSky.DarkLayer.new(), MapSky.GlowLayer.new(), MapSky.RainLayer.new()]:
		layer.set("map", self)
		layer.z_index = z
		z += 1
		add_child(layer)
		sky_layers.append(layer)
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


func layout() -> void:
	fit_window()
	queue_redraw()


## Taille de la carte visible (tout l'écran : les fenêtres flottent par-dessus).
func map_area() -> Vector2:
	return get_viewport_rect().size


func center_on(p: Vector2) -> void:
	cam.position = p
	clamp_camera()


func look_at_point(p: Vector2) -> void:
	center_on(p)


## La vue reste sur la carte (au plus MARGIN au-delà du bord) ; plus large que la carte : centrée.
func clamp_camera() -> void:
	var half := get_viewport_rect().size * 0.5 / cam.zoom.x
	var lo := half - Vector2(MARGIN, MARGIN)
	var hi := MapData.SIZE - half + Vector2(MARGIN, MARGIN)
	for a in 2:
		cam.position[a] = MapData.SIZE[a] * 0.5 if lo[a] > hi[a] else clampf(cam.position[a], lo[a], hi[a])


## La souris est-elle sur l'interface (barre, fenêtre, mini-carte) plutôt que sur la carte ?
func over_ui(m: Vector2) -> bool:
	for c: Control in [bar, panel, minimap]:
		if c != null and c.visible and c.get_global_rect().has_point(m):
			return true
	return false


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
	fit_window()
	if toast_time > 0.0:
		toast_time -= delta
		toast.modulate.a = clampf(toast_time, 0.0, 1.0)
		toast.visible = toast_time > 0.0
	queue_redraw()
	update_trails()
	for layer in sky_layers:
		layer.queue_redraw()
	if minimap != null:
		(minimap as MiniMap).redraw()


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


## Saison du terrain et de la mini-carte (la nuit, le brouillard et la pluie sont redessinés à
## chaque image par les calques de MapSky).
func update_light() -> void:
	var s := MapSky.season(state.day, state.overworld.hour)
	if s == season:
		return
	season = s
	MapRender.set_season(ground_mat, s)
	if minimap != null:
		MapRender.set_season((minimap as MiniMap).ground, s)


## Couleur de la lumière à cette heure (voir MapSky.daylight).
static func daylight(hour: float) -> Color:
	return MapSky.daylight(hour)


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
		if m.x >= 0 and m.y >= 0 and m.x < area.x and m.y < area.y and not over_ui(m):
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
	var on_ui := over_ui(get_viewport().get_mouse_position())
	hover_party = null if on_ui else party_at(p)
	hover_place = -1 if on_ui or hover_party != null else MapData.place_at(p)
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
		# Rencontre : les touches 1 à 9 de la rangée du haut (ou du pavé) choisissent
		if contact != null:
			var digit := -1
			if k.physical_keycode >= KEY_1 and k.physical_keycode <= KEY_9:
				digit = k.physical_keycode - KEY_1
			elif k.keycode >= KEY_KP_1 and k.keycode <= KEY_KP_9:
				digit = k.keycode - KEY_KP_1
			if digit >= 0:
				var opts := state.overworld.options(state, contact)
				if digit < opts.size() and bool(opts[digit].get("enabled", true)):
					choose(str(opts[digit].get("id", "")))
				return
		if LifePanel.key(self, k): # F : marche forcée ; K : camper
			return
		match k.keycode:
			KEY_ESCAPE:
				escape()
			KEY_E:
				toggle_view("company")
			KEY_M:
				toggle_view("world")
			KEY_J:
				toggle_view("journal")
			KEY_T:
				toggle_view("quests") # Onglet des quêtes (realm_panel.gd)
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


## Échap : ferme l'onglet ouvert, puis la ville ; sinon ouvre le menu.
func escape() -> void:
	if view != "":
		toggle_view(view)
	elif town_open:
		close_town()
	elif contact == null and not state.world.has_encounter():
		toggle_view("menu")


## Ouvre un onglet (ou le ferme s'il est déjà ouvert).
func toggle_view(v: String) -> void:
	view = "" if view == v else v
	GameAudio.ui("click")
	refresh_ui()


## Bouton ✕ de la fenêtre.
func close_window() -> void:
	if view != "":
		toggle_view(view)
	elif town_open:
		close_town()


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
	# Commercer, parler, recruter : la rencontre continue (le temps reste arrêté)
	if not bool(out.get("close", true)) and not bool(out.get("battle", false)) and not bool(out.get("remove_other", false)) and not other.is_dead():
		contact = other
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
	CampaignState.current = CampaignState.new_game(0, state.difficulty, state.lenient, true) # Mêmes réglages qu'avant
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
	# Barre du haut : date et heure, or et effectif, temps, onglets
	bar = PanelContainer.new()
	bar.theme = th
	bar.add_theme_stylebox_override("panel", bar_style())
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	layer.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	bar.add_child(row)
	top_label = Label.new()
	top_label.add_theme_font_size_override("font_size", 14)
	top_label.add_theme_color_override("font_color", GOLD_COL)
	top_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_label.clip_text = true
	row.add_child(top_label)
	var pause := Button.new()
	pause.text = "Pause"
	pause.tooltip_text = "Espace"
	pause.focus_mode = Control.FOCUS_NONE
	pause.toggle_mode = true
	pause.pressed.connect(toggle_pause)
	row.add_child(pause)
	speed_buttons.append(pause)
	for i in SPEEDS.size():
		var b := Button.new()
		b.text = "x%d" % SPEEDS[i]
		b.tooltip_text = "Touche %d" % (i + 1)
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.pressed.connect(set_speed.bind(i))
		row.add_child(b)
		speed_buttons.append(b)
	refresh_speed_buttons()
	LifePanel.build_bar(self, row) # Marche forcée, camp (life_panel.gd)
	row.add_child(VSeparator.new())
	for v in [["company", "Compagnie", "E"], ["world", "Monde", "M"], ["journal", "Journal", "J"], ["quests", "Quêtes", "T"], ["menu", "Menu", "Échap"]]:
		var b := Button.new()
		b.text = v[1]
		b.tooltip_text = "Touche %s" % v[2]
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.pressed.connect(toggle_view.bind(v[0]))
		row.add_child(b)
		view_buttons[v[0]] = b
	# Fenêtre au centre (ville, rencontre, onglets) : n'apparaît que s'il y a quelque chose à montrer
	panel = PanelContainer.new()
	panel.theme = th
	panel.visible = false
	layer.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	window_title = Label.new()
	window_title.add_theme_font_size_override("font_size", 18)
	window_title.add_theme_color_override("font_color", GOLD_COL)
	window_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(window_title)
	close_button = Button.new()
	close_button.text = "✕"
	close_button.tooltip_text = "Fermer (Échap)"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(close_window)
	head.add_child(close_button)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	box = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 5)
	scroll.add_child(box)
	# Mini-carte en bas à gauche
	var mm := MiniMap.new()
	mm.map = self
	var ms := Vector2(MINIMAP_W, roundf(MINIMAP_W * MapData.SIZE.y / MapData.SIZE.x))
	mm.custom_minimum_size = ms
	mm.size = ms
	mm.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	mm.offset_top = -ms.y - 10
	mm.offset_bottom = -10
	mm.offset_left = 10
	mm.offset_right = 10 + ms.x
	layer.add_child(mm)
	mm.setup()
	minimap = mm
	# Message en bas de l'écran (arrivée, refus, évènement de la route), qui s'efface seul
	toast = PanelContainer.new()
	toast.theme = th
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.visible = false
	toast_label = Label.new()
	toast_label.add_theme_font_size_override("font_size", 14)
	toast_label.add_theme_color_override("font_color", Color(1, 0.8, 0.5))
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_child(toast_label)
	layer.add_child(toast)
	# Infobulle
	tip = PanelContainer.new()
	tip.theme = th
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip.visible = false
	tip_label = Label.new()
	tip_label.add_theme_font_size_override("font_size", 12)
	tip.add_child(tip_label)
	layer.add_child(tip)


func bar_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.06, 0.04, 0.85)
	sb.border_color = Color(0.45, 0.35, 0.2)
	sb.border_width_bottom = 1
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	return sb


## Ajuste la fenêtre à son contenu (au plus la hauteur de l'écran) et la centre sous la barre.
func fit_window() -> void:
	if panel == null or not panel.visible:
		return
	var vs := get_viewport_rect().size
	var top := bar.size.y if bar != null else 0.0
	var w := minf(WINDOW_W, vs.x - 32.0)
	var h := maxf(40.0, minf(box.get_combined_minimum_size().y, vs.y - top - 120.0))
	if not is_equal_approx(scroll.custom_minimum_size.x, w) or not is_equal_approx(scroll.custom_minimum_size.y, h):
		scroll.custom_minimum_size = Vector2(w, h)
		panel.reset_size()
	panel.position = Vector2(roundf((vs.x - panel.size.x) * 0.5), roundf(top + maxf(10.0, (vs.y - top - panel.size.y) * 0.4)))


## Affiche un message en bas de l'écran pendant quelques secondes.
func show_toast(s: String) -> void:
	if toast == null or s == "":
		return
	toast_label.text = s
	var vs := get_viewport_rect().size
	toast_label.custom_minimum_size.x = minf(620.0, vs.x - 60.0)
	toast.reset_size()
	toast.position = Vector2(roundf((vs.x - toast.size.x) * 0.5), vs.y - toast.size.y - 24.0)
	toast.modulate.a = 1.0
	toast.visible = true
	toast_time = TOAST_SECONDS


func refresh_speed_buttons() -> void:
	for i in speed_buttons.size():
		speed_buttons[i].button_pressed = paused if i == 0 else (not paused and speed_index == i - 1)


func update_top() -> void:
	if top_label == null:
		return
	var s := "%s   ·   %d écus (solde %d / jour)   ·   %s" % [clock_text(), int(state.gold), ceili(state.daily_wage()), CampaignState.plural(state.total_men(), "homme", "hommes")]
	s += LifePanel.top_text(self) # Vivres et fatigue
	if time_stopped() and not paused:
		s += "   ·   temps arrêté"
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
	if box.get_child_count() > 0:
		box.add_child(HSeparator.new())
	add_label(s, 15, GOLD_COL)


## Lieu (ville) où l'on peut signer et recruter : la ville où la compagnie est entrée, -1 sinon.
func town_here() -> int:
	var i := state.overworld.inside
	return i if i >= 0 and i < CampaignState.TOWNS.size() and town_open else -1


## Fenêtre à montrer : la rencontre passe avant tout, puis l'onglet choisi, puis la ville ("" : aucune).
func current_window() -> String:
	if contact != null or state.world.has_encounter():
		return "contact"
	if view != "":
		return view
	if town_open:
		return "town"
	if state.is_over():
		return "world" # Le bouton du bilan y est
	return ""


func refresh_ui() -> void:
	if box == null:
		return
	update_top()
	if notice != "":
		show_toast(notice)
		notice = ""
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	var w := current_window()
	for v in view_buttons:
		(view_buttons[v] as Button).set_pressed_no_signal(v == view)
	panel.visible = w != ""
	close_button.visible = w != "contact"
	match w:
		"contact":
			window_title.text = "Rencontre"
			build_contact()
			WorldView.build_encounter(self) # Ancienne rencontre d'une sauvegarde : bataille ou fuite
		"town":
			build_place()
		"company":
			window_title.text = "Votre compagnie"
			add_label(where_text(), 12, DIM_COL)
			build_company(-1, "")
			CompanyPanel.build(self)
			Heraldry.build_panel(self) # Armoiries de la bannière
			LifePanel.build(self) # Vivres, prisonniers, compagnons
			RealmPanel.build_company(self) # Allégeance, fiefs, cargaison
		"world":
			window_title.text = "Le monde"
			add_section("Objectif")
			add_label(state.objective_status(), 12, Color(1, 0.9, 0.7))
			add_label("Victoires %d   ·   défaites %d   ·   renommée %d   ·   ennemis tués %d   ·   hommes perdus %d   ·   or gagné %d écus" % [state.victories, state.defeats, state.fame, state.enemies_killed, state.men_lost, state.gold_earned], 12, DIM_COL)
			if state.is_over():
				add_button("Voir le bilan de la campagne", show_end_now)
			WorldView.build_world(self) # Saison, météo, guerres, sièges, nouvelles
			add_section("Réputation")
			for f in CampaignState.FACTIONS.size():
				add_label("%s : %+d (%s)" % [CampaignState.faction_name(f), state.reputation[f], state.reputation_label(f)], 12, CampaignState.FACTIONS[f]["color"])
			add_label("Un contrat gagné plaît à qui paie et fâche sa rivale ; la réputation fait varier la prime. Sous %d, la faction ferme ses portes." % CampaignState.REP_CLOSED, 11, HINT_COL)
		"journal":
			window_title.text = "Journal"
			if state.log_lines.is_empty():
				add_label("Rien à signaler pour l'instant.", 12, DIM_COL)
			for s in state.log_lines:
				add_label(s, 12, Color(0.8, 0.77, 0.7))
		"quests":
			RealmPanel.build_quests(self)
		"menu":
			build_menu()
	scroll.scroll_vertical = 0
	fit_window()


## Ville ou lieu où la compagnie est entrée : contrats, recrues, compagnie, capitaine.
func build_place() -> void:
	var here := town_here()
	var ow := state.overworld
	if here < 0 and RealmPanel.build_place(self, ow.inside): # Château, repaire ou pont d'une quête
		return
	if here < 0:
		window_title.text = str(MapData.place(ow.inside)["name"]) if ow.inside >= 0 else "En campagne"
		if ow.inside >= 0:
			add_label(place_lines(ow.inside)[1], 12, DIM_COL)
		add_label("Un lieu calme : rien à y faire pour l'instant.", 12, DIM_COL)
		add_button("Repartir (le temps reprend)", close_town)
		return
	var closed := state.closed_message(here)
	build_town(here, closed)
	if state.company.is_empty(): # Sans un homme : d'abord lever des régiments
		build_company(here, closed)
		build_recruits(here, closed)
		build_contracts(here, closed)
	else:
		build_contracts(here, closed)
		build_recruits(here, closed)
		build_company(here, closed)
	CompanyPanel.build(self) # Capitaine, traits et équipement (achats en ville)
	LifePanel.build(self) # Vivres, prisonniers, compagnons (achats, rançons, engagements en ville)
	RealmPanel.build_town(self, here) # Marché, quêtes, allégeance


## Onglet Menu : quitter, escarmouche, nouvelle campagne, aide.
func build_menu() -> void:
	window_title.text = "Menu"
	add_button("Reprendre", toggle_view.bind("menu"))
	add_button("Menu principal", back_to_menu)
	add_button("Escarmouche libre (hors campagne)", do_skirmish)
	if confirm_new:
		add_label("Effacer la campagne en cours (jour %d) ?" % state.day, 12, Color(1, 0.62, 0.3))
		var row := HBoxContainer.new()
		box.add_child(row)
		add_button("Oui, recommencer", do_new_campaign, true, row)
		add_button("Non", cancel_new_campaign, true, row)
	elif not state.is_ruined():
		add_button("Nouvelle campagne", do_new_campaign)
	add_section("Commandes")
	add_label("Clic gauche : marcher (sur une ville : y entrer ; sur un groupe : le poursuivre). Clic droit : halte.", 12, DIM_COL)
	add_label("F : marche forcée (x2, épuisante) ; K : camper (repos, soins).", 12, DIM_COL)
	add_label("Espace : pause ; 1, 2, 3 : vitesses. E : compagnie ; M : monde ; J : journal ; T : quêtes ; Échap : fermer ou menu.", 12, DIM_COL)
	add_label("ZQSD, flèches, bord de l'écran ou clic molette : déplacer la vue ; molette : zoom ; C : recentrer.", 12, DIM_COL)
	add_label("La route va plus vite ; forêts, collines, marais et hiver ralentissent. Chaque jour coûte la solde ; sans or, des hommes désertent. Les groupes cerclés de rouge vous attaquent s'ils vous rattrapent.", 11, HINT_COL)
	add_label("Sauvegarde automatique chaque jour, à chaque arrivée, recrutement et bataille.", 11, HINT_COL)


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
	window_title.text = "Rencontre : %s" % CampaignState.cap_first(contact.display_name())
	var lines := party_lines(contact)
	add_label(" · ".join(lines.slice(1, lines.size() - 1)), 12, Color(1, 0.5, 0.4) if ow.hostile(state, contact) else Color(0.92, 0.88, 0.78))
	var enc := Overworld.encounter_script()
	if enc != null:
		add_label(str(enc.call("greeting", state, ow.player, contact)), 12, Color(0.92, 0.88, 0.78))
	LifePanel.build_contact(self, contact) # Rapport de l'éclaireur
	var site := ow.battle_site(contact)
	add_label("Terrain du combat : %s, %s." % [str(Terrain.NAMES.get(str(site["kind"]), "plaine")).to_lower(), str(site["label"])], 12, Color(0.75, 0.72, 0.65))
	var allies := ow.allies_line(state, contact)
	if allies != "":
		add_label("À vos côtés : %s." % allies, 12, Color(0.55, 0.85, 0.8))
	var n := 0
	for o in ow.options(state, contact):
		n += 1
		var text := "%d. %s" % [n, str(o.get("text", o.get("label", o.get("id", "?"))))]
		var hint := str(o.get("hint", ""))
		var on := bool(o.get("enabled", true)) and (str(o.get("id", "")) != "attack" or not state.is_destroyed())
		if not on and str(o.get("reason", "")) != "":
			hint = str(o["reason"])
		if hint != "":
			text += " — " + hint
		add_button(text, choose.bind(str(o.get("id", ""))), on)


func build_town(here: int, closed: String) -> void:
	var town: Dictionary = CampaignState.TOWNS[here]
	window_title.text = str(town["name"])
	var fac := state.town_owner(here)
	add_label("%s — réputation %+d (%s)" % [CampaignState.faction_name(fac), state.reputation[fac], state.reputation_label(fac)], 12, CampaignState.FACTIONS[fac]["color"])
	if closed != "":
		add_label(closed + " Ni contrat ni recrutement ici.", 12, Color(1, 0.5, 0.4))
	var names: Array[String] = []
	for t in town["recruits"]:
		names.append(CampaignState.type_name(t).to_lower())
	add_label("On y lève : %s.   Prix des recrues : %s" % [", ".join(names), price_text(here)], 12, Color(0.75, 0.72, 0.65))
	add_button("Repartir (le temps reprend)", close_town)


func build_company(here: int, closed: String) -> void:
	add_section("Régiments")
	if state.is_destroyed():
		if state.is_ruined():
			add_label("Plus personne ne marche sous votre bannière, et les caisses sont vides...", 13, Color(1, 0.5, 0.4))
			add_button("Recommencer une campagne", do_new_campaign)
		elif state.victories + state.defeats == 0:
			add_label("Votre compagnie n'a encore aucun homme. Levez vos premiers régiments avec vos %d écus (d'autres villes lèvent d'autres troupes), et gardez de quoi payer la solde et les équiper !" % int(state.gold), 13, Color(1, 0.84, 0.4))
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
		lines.append("%s%s" % [CampaignState.cap_first(str(MapData.KIND_NAMES.get(pl["kind"], pl["kind"]))), (" de %s" % CampaignState.FACTIONS[f]["short"]) if f >= 0 else ""])
	lines.append_array(RealmPanel.place_lines(state, i)) # Fief, marché, quêtes
	lines.append("Région : %s" % MapData.REGIONS[MapData.region_at(pl["pos"])]["name"])
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


# ---------------------------------------------------------------- Rendu de la couche vivante

func _draw() -> void:
	var ow := state.overworld
	var view := view_rect().grow(80)
	var z := cam.zoom.x if cam != null else 1.0
	MapRender.draw_region_names(self, font, z, view)
	draw_trails(view)
	for i in MapData.place_count():
		if view.has_point(MapData.place_pos(i)):
			draw_place(i, z)
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
	draw_company(p.pos)
	# Brouillard, nuit, lumières et pluie : calques de MapSky (sky_layers), au-dessus


## Un lieu : son icône selon sa sorte et son nom. En vue éloignée, seuls les noms des villes
## restent (agrandis pour rester lisibles).
func draw_place(i: int, zoom := 1.0) -> void:
	var pl := MapData.place(i)
	var p := (pl["pos"] as Vector2).round()
	var ow := state.overworld
	var here := ow.inside == i
	var r := MapData.PLACE_RADIUS
	var kind := str(pl["kind"])
	if here:
		draw_circle(p, r, Color(1, 0.84, 0.4, 0.22))
		draw_arc(p, r, 0, TAU, 32, GOLD_COL, 2.0)
	elif i == hover_place:
		draw_arc(p, r, 0, TAU, 32, Color(1, 1, 1, 0.8), 2.0)
	var f := int(pl["faction"])
	match kind:
		"town":
			draw_town(i)
		"castle":
			draw_castle(p, f)
		"abbey":
			draw_abbey(p)
		"mill":
			draw_mill(p)
		"bridge":
			draw_bridge_tower(p, f)
		"ford":
			draw_ford(p)
		"mine":
			draw_mine(p)
		"ruins":
			draw_ruins(p)
		"lair":
			draw_lair(p)
		_:
			draw_village(p)
	RealmPanel.draw_place(self, i, p) # Bannière des fiefs, cibles des quêtes
	var town := kind == "town"
	if not town and not here and i != hover_place and zoom < 0.55:
		return
	var name := str(pl["name"])
	var size := 14 if town else 11
	var col := GOLD_COL if here else (Color(1, 1, 1) if town else (Color(1, 0.7, 0.6) if kind == "lair" else Color(0.92, 0.88, 0.8)))
	var k := maxf(1.0, 1.1 / zoom) if town else 1.0
	draw_set_transform(p + Vector2(0, 36), 0.0, Vector2(k, k))
	draw_string_outline(font, Vector2(-80, 0), name, HORIZONTAL_ALIGNMENT_CENTER, 160, size, 3, Color(0, 0, 0, 0.7))
	draw_string(font, Vector2(-80, 0), name, HORIZONTAL_ALIGNMENT_CENTER, 160, size, col)
	draw_set_transform(Vector2.ZERO)

## Petite ville fortifiée dessinée en pixels (x2), drapeau des contrats, couleurs de la faction.
func draw_town(i: int) -> void:
	var p := MapData.place_pos(i).round()
	draw_set_transform(p, 0.0, Vector2(2, 2))
	var stone := Color(0.7, 0.68, 0.62)
	var dark := Color(0.3, 0.28, 0.26)
	var roof := snowy(Color(0.66, 0.24, 0.16))
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
	var roof := snowy(Color(0.55, 0.35, 0.2))
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
	draw_rect(Rect2(p + Vector2(1, -30), Vector2(8, 5)), faction_color(f))


static func faction_color(f: int) -> Color:
	return CampaignState.FACTIONS[f]["color"] if f >= 0 else Color(0.6, 0.6, 0.6)


## Abbaye : église (nef, clocher, croix) et cloître.
func draw_abbey(p: Vector2) -> void:
	var wall := Color(0.86, 0.82, 0.72)
	var slate := Color(0.36, 0.4, 0.5)
	draw_rect(Rect2(p + Vector2(-12, -2), Vector2(26, 13)), Color(0, 0, 0, 0.3))
	draw_rect(Rect2(p + Vector2(-2, 0), Vector2(14, 9)), wall.darkened(0.12)) # Cloître
	draw_rect(Rect2(p + Vector2(0, 2), Vector2(10, 5)), Color(0.45, 0.6, 0.32))
	draw_rect(Rect2(p + Vector2(-13, -4), Vector2(14, 9)), wall) # Nef
	draw_colored_polygon(PackedVector2Array([p + Vector2(-14, -4), p + Vector2(2, -4), p + Vector2(-1, -9), p + Vector2(-11, -9)]), slate)
	draw_rect(Rect2(p + Vector2(-17, -14), Vector2(6, 19)), wall.lightened(0.05)) # Clocher
	draw_colored_polygon(PackedVector2Array([p + Vector2(-18, -14), p + Vector2(-10, -14), p + Vector2(-14, -22)]), slate)
	draw_line(p + Vector2(-14, -22), p + Vector2(-14, -28), Color(0.95, 0.85, 0.5), 1.5)
	draw_line(p + Vector2(-16, -26), p + Vector2(-12, -26), Color(0.95, 0.85, 0.5), 1.5)
	draw_rect(Rect2(p + Vector2(-15, -2), Vector2(2, 3)), Color(0.25, 0.2, 0.16))
	draw_rect(Rect2(p + Vector2(-7, 1), Vector2(3, 4)), Color(0.25, 0.2, 0.16))


## Moulin à vent : tour, toit, quatre ailes.
func draw_mill(p: Vector2) -> void:
	draw_rect(Rect2(p + Vector2(-6, 2), Vector2(14, 8)), Color(0, 0, 0, 0.3))
	draw_colored_polygon(PackedVector2Array([p + Vector2(-6, 8), p + Vector2(6, 8), p + Vector2(4, -8), p + Vector2(-4, -8)]), Color(0.85, 0.8, 0.68))
	draw_colored_polygon(PackedVector2Array([p + Vector2(-6, -8), p + Vector2(6, -8), p + Vector2(0, -15)]), Color(0.55, 0.3, 0.18))
	draw_rect(Rect2(p + Vector2(-1.5, 3), Vector2(3, 5)), Color(0.3, 0.2, 0.12))
	var hub := p + Vector2(0, -7)
	for k in 4:
		var d := Vector2.from_angle(PI * 0.25 + k * PI * 0.5)
		draw_line(hub, hub + d * 13.0, WOOD.darkened(0.2), 1.5)
		var side := d.orthogonal() * 2.5
		draw_colored_polygon(PackedVector2Array([hub + d * 4.0, hub + d * 13.0, hub + d * 13.0 + side, hub + d * 4.0 + side]), Color(0.95, 0.92, 0.84))
	draw_circle(hub, 1.5, Color(0.25, 0.18, 0.1))


## Pont fortifié : une tour de garde à la tête du pont.
func draw_bridge_tower(p: Vector2, f: int) -> void:
	var stone := Color(0.66, 0.63, 0.58)
	draw_rect(Rect2(p + Vector2(-6, -4), Vector2(14, 14)), Color(0, 0, 0, 0.3))
	draw_rect(Rect2(p + Vector2(-7, -12), Vector2(12, 20)), stone)
	for k in 3:
		draw_rect(Rect2(p + Vector2(-7 + k * 4.5, -14), Vector2(3, 2)), stone)
	draw_rect(Rect2(p + Vector2(-3, 1), Vector2(4, 7)), Color(0.25, 0.2, 0.18))
	draw_rect(Rect2(p + Vector2(-2, -8), Vector2(2, 3)), Color(0.2, 0.16, 0.14))
	draw_line(p + Vector2(-1, -14), p + Vector2(-1, -22), WOOD, 1.5)
	draw_rect(Rect2(p + Vector2(0, -22), Vector2(7, 4)), faction_color(f))


## Gué : pierres plates en travers du courant et un poteau.
func draw_ford(p: Vector2) -> void:
	for k in 5:
		var s := p + Vector2(-12 + k * 6, 4 + (k % 2) * 2)
		draw_circle(s + Vector2(1, 1), 2.6, Color(0, 0, 0, 0.3))
		draw_circle(s, 2.6, Color(0.7, 0.68, 0.62))
	draw_line(p + Vector2(10, 2), p + Vector2(10, -12), WOOD, 1.5)
	draw_rect(Rect2(p + Vector2(4, -12), Vector2(10, 4)), Color(0.78, 0.66, 0.44))


## Mine : entrée boisée dans un flanc de roche, tas de minerai.
func draw_mine(p: Vector2) -> void:
	draw_colored_polygon(PackedVector2Array([p + Vector2(-16, 8), p + Vector2(-5, -12), p + Vector2(4, -6), p + Vector2(15, 8)]), Color(0.5, 0.45, 0.4))
	draw_colored_polygon(PackedVector2Array([p + Vector2(-5, -12), p + Vector2(4, -6), p + Vector2(15, 8), p + Vector2(2, 8)]), Color(0.38, 0.34, 0.31))
	draw_rect(Rect2(p + Vector2(-5, -1), Vector2(9, 9)), Color(0.1, 0.08, 0.07))
	draw_line(p + Vector2(-6, 8), p + Vector2(-6, -2), WOOD, 2.0)
	draw_line(p + Vector2(5, 8), p + Vector2(5, -2), WOOD, 2.0)
	draw_line(p + Vector2(-7, -2), p + Vector2(6, -2), WOOD, 2.0)
	for k in 3:
		draw_circle(p + Vector2(10 + k * 2.5, 7 - (k % 2) * 2), 2.0, Color(0.65, 0.3, 0.2))


## Ruines : pans de murs brisés et pierres tombées.
func draw_ruins(p: Vector2) -> void:
	var stone := Color(0.58, 0.56, 0.52)
	draw_rect(Rect2(p + Vector2(-12, 4), Vector2(26, 6)), Color(0, 0, 0, 0.25))
	draw_rect(Rect2(p + Vector2(-12, -8), Vector2(5, 15)), stone)
	draw_rect(Rect2(p + Vector2(-7, -2), Vector2(8, 9)), stone.darkened(0.1))
	draw_rect(Rect2(p + Vector2(5, -12), Vector2(5, 19)), stone)
	draw_rect(Rect2(p + Vector2(10, -4), Vector2(3, 11)), stone.darkened(0.15))
	draw_rect(Rect2(p + Vector2(-12, -10), Vector2(2, 2)), stone)
	draw_rect(Rect2(p + Vector2(7, -14), Vector2(3, 2)), stone)
	for s in [Vector2(-3, 9), Vector2(2, 8), Vector2(14, 9)]:
		draw_rect(Rect2(p + s, Vector2(3, 2)), stone.darkened(0.25))
	draw_rect(Rect2(p + Vector2(-5, 0), Vector2(2, 3)), Color(0.32, 0.5, 0.25)) # Lierre


## Repaire de bandits : tentes sombres, palissade, feu de camp.
func draw_lair(p: Vector2) -> void:
	draw_rect(Rect2(p + Vector2(-13, 4), Vector2(28, 6)), Color(0, 0, 0, 0.25))
	for t in [Vector2(-8, 6), Vector2(6, 4)]:
		draw_colored_polygon(PackedVector2Array([p + t + Vector2(-7, 0), p + t + Vector2(7, 0), p + t + Vector2(0, -11)]), Color(0.36, 0.22, 0.16))
		draw_colored_polygon(PackedVector2Array([p + t + Vector2(0, -11), p + t + Vector2(7, 0), p + t + Vector2(2, 0)]), Color(0.25, 0.15, 0.11))
		draw_line(p + t + Vector2(0, -11), p + t + Vector2(0, -14), WOOD, 1.0)
	for k in 6:
		draw_line(p + Vector2(-16 + k * 6, 10), p + Vector2(-16 + k * 6, 4), WOOD.darkened(0.3), 2.0)
	draw_circle(p + Vector2(0, 8), 2.5, Color(1, 0.55, 0.15))
	draw_circle(p + Vector2(0, 7), 1.2, Color(1, 0.9, 0.5))
	draw_line(p + Vector2(-14, -10), p + Vector2(-14, 2), WOOD, 1.5)
	draw_rect(Rect2(p + Vector2(-13, -10), Vector2(7, 5)), Color(0.15, 0.12, 0.1))

## Toits enneigés en hiver (MapSky.season).
func snowy(roof: Color) -> Color:
	return roof.lerp(Color(0.93, 0.95, 0.99), float(season.get("snow", 0.0)) * 0.85)


## Pas des figurines (0 ou 1) : les jambes alternent quand le groupe marche et que le temps passe.
func step_of(q: Party) -> int:
	if time_stopped() or not moving(q):
		return 0
	return (int(Time.get_ticks_msec() / 160.0) + q.id) % 2


## Le groupe marche-t-il ? (sa trace avance)
func moving(q: Party) -> bool:
	var tr: Array = trails.get(q.id, [])
	return not tr.is_empty() and (tr[-1] as Vector2).distance_to(q.pos) > 0.5 or not q.path.is_empty() and q.busy_hours <= 0.0


## Trace de marche : un point tous les TRAIL_STEP px parcourus (TRAIL_POINTS au plus) ; le sens
## du groupe suit sa marche (figurines tournées vers l'ouest ou l'est).
const TRAIL_STEP := 9.0
const TRAIL_POINTS := 9


func update_trails() -> void:
	var alive := {}
	for q in state.overworld.all(state):
		alive[q.id] = true
		var tr: Array = trails.get(q.id, [])
		if tr.is_empty() or (tr[-1] as Vector2).distance_to(q.pos) > 60.0: # Apparition ou saut
			trails[q.id] = [q.pos]
			continue
		var last: Vector2 = tr[-1]
		var d := q.pos - last
		if d.length() >= TRAIL_STEP:
			tr.append(q.pos)
			if tr.size() > TRAIL_POINTS:
				tr.pop_front()
			if absf(d.x) > 2.0:
				facing[q.id] = -1 if d.x < 0.0 else 1
	if trails.size() > alive.size(): # Groupes disparus
		for id in trails.keys():
			if not alive.has(id):
				trails.erase(id)
				facing.erase(id)


## Traces discrètes : petites empreintes qui s'effacent derrière les groupes en marche.
func draw_trails(view: Rect2) -> void:
	for id in trails:
		var tr: Array = trails[id]
		if tr.size() < 2 or not view.has_point(tr[-1]):
			continue
		var n := tr.size()
		for k in n - 1:
			var a: Vector2 = tr[k]
			var b: Vector2 = tr[k + 1]
			var side := (b - a).normalized().orthogonal() * 1.6
			var alpha := 0.5 * float(k + 1) / n
			var col := Color(0.22, 0.16, 0.1, alpha)
			for f in 2: # Deux empreintes par pas, de part et d'autre
				var p := a.lerp(b, 0.25 + f * 0.5) + (side if f == 0 else -side)
				draw_rect(Rect2(p.round() - Vector2(1, 1), Vector2(2, 2)), col)


## Sens d'un groupe (1 : vers l'est, -1 : vers l'ouest), d'après sa marche.
func face_of(q: Party) -> float:
	if not q.path.is_empty() and absf(q.path[0].x - q.pos.x) > 2.0:
		return -1.0 if q.path[0].x < q.pos.x else 1.0
	return float(facing.get(q.id, 1))


## Un groupe errant : ses figurines selon sa sorte (MapIcons), sa bannière, son effectif.
func draw_group(q: Party) -> void:
	var p := q.pos.round()
	var hostile := state.overworld.hostile(state, q)
	if hostile:
		draw_arc(p + Vector2(0, -2), 14.0, 0, TAU, 24, Color(0.9, 0.15, 0.1, 0.9), 1.5)
	var step := step_of(q)
	var men := q.men()
	draw_set_transform(p, 0.0, Vector2(face_of(q), 1.0))
	match q.kind:
		"caravan":
			MapIcons.caravan(self, clampi(ceili(men / 15.0), 1, 2), step)
		"villagers":
			MapIcons.villagers(self, clampi(ceili(men / 10.0), 2, 4), step)
		"patrol", "army":
			MapIcons.patrol(self, clampi(ceili(men / 25.0), 1, 3), faction_color(q.faction), step)
		"bandits":
			MapIcons.bandits(self, clampi(ceili(men / 10.0), 2, 4), step)
		"deserters":
			MapIcons.deserters(self, clampi(ceili(men / 12.0), 2, 4), faction_color(q.faction), step)
		_:
			MapIcons.villagers(self, 2, step)
	draw_set_transform(Vector2.ZERO)
	var label := str(men)
	draw_string(font, p + Vector2(-12, 14), label, HORIZONTAL_ALIGNMENT_CENTER, 24, 10, Color(0, 0, 0, 0.85))
	draw_string(font, p + Vector2(-13, 13), label, HORIZONTAL_ALIGNMENT_CENTER, 24, 10, Color(1, 0.6, 0.5) if hostile else Color(1, 0.95, 0.85))


## La compagnie : quelques soldats et la bannière à ses armoiries (CampaignState.arms).
func draw_company(base: Vector2) -> void:
	var pl := state.overworld.player
	var men := 0
	for r in state.company:
		men += int(r["men"])
	var n := 0 if men == 0 else clampi(ceili(men / 60.0), 1, 3)
	draw_set_transform(base.round()) # Jamais en miroir : les armoiries gardent leur sens
	MapIcons.company(self, n, state.arms, step_of(pl))
	draw_set_transform(Vector2.ZERO)


## Mini-carte, par-dessus le terrain (MiniOverlay._draw) : routes, lieux, groupes, vue de la caméra.
func draw_minimap(ci: Control) -> void:
	var size := ci.size
	var k := size / MapData.SIZE
	for r in MapData.roads().size():
		if MapData.road_class(r) == MapData.RoadClass.TRAIL:
			continue
		var pts := MapData.road_points(r)
		var main := MapData.road_class(r) == MapData.RoadClass.MAIN
		ci.draw_line(pts[0] * k, pts[-1] * k, Color(0.85, 0.72, 0.48, 0.9 if main else 0.5), 1.0)
	for i in MapData.place_count():
		var pl := MapData.place(i)
		var col := Color(0.92, 0.88, 0.8)
		if i < CampaignState.TOWNS.size():
			col = CampaignState.FACTIONS[state.town_owner(i)]["color"]
		elif pl["kind"] == "lair":
			col = Color(0.75, 0.2, 0.15)
		var r := 3.0 if pl["kind"] == "town" else 1.2
		ci.draw_rect(Rect2(MapData.place_pos(i) * k - Vector2(r, r), Vector2(r, r) * 2).grow(1.0), Color(0, 0, 0, 0.6))
		ci.draw_rect(Rect2(MapData.place_pos(i) * k - Vector2(r, r), Vector2(r, r) * 2), col)
	var ow := state.overworld
	for q in ow.all(state):
		if q == ow.player or q.hidden:
			continue
		var col: Color = Color(0.95, 0.2, 0.12) if ow.hostile(state, q) else (CampaignState.FACTIONS[q.faction]["color"] if q is WorldArmy else Color(1, 1, 1, 0.85))
		ci.draw_circle(q.pos * k, 2.0 if q is WorldArmy else 1.5, col)
	ci.draw_circle(ow.player.pos * k, 3.0, BLUE.lightened(0.3))
	ci.draw_arc(ow.player.pos * k, 4.5, 0, TAU, 12, Color.WHITE, 1.0)
	if cam != null:
		var v := view_rect()
		ci.draw_rect(Rect2(v.position * k, v.size * k).intersection(Rect2(Vector2.ZERO, size)), Color(1, 1, 1, 0.9), false, 1.0)
	ci.draw_rect(Rect2(Vector2.ZERO, size), Color(0.6, 0.47, 0.25), false, 1.5)
