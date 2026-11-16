extends Control
## Menu principal : campagne (continuer / nouvelle), tutoriel, escarmouche, options, quitter.
## Fond pixel art généré en code (ciel du soir, château, collines) et une colonne de soldats
## qui défile au pied de l'écran (sprites MiniWorld, voir CREDITS.md).

const CAMPAIGN_SCENE := "res://scenes/campaign.tscn"
const BATTLE_SCENE := "res://scenes/main.tscn"
const TUTORIAL_SCENE := "res://scenes/tutorial.tscn"
const END_SCENE := "res://scenes/end.tscn"
const PIX := 4 ## Taille d'un « pixel » du fond
const MARCH := ["spear", "spear", "men_at_arms", "archer", "spear", "cavalry", "men_at_arms", "archer", "cavalry", "spear"]

var change_scenes := true ## Faux dans les tests : on note la scène demandée sans en changer
var last_scene := "" ## Dernière scène demandée
var page := "main" ## "main", "slots", "confirm_delete", "new_campaign" (difficulté) ou "options"
var notice := ""
var target_slot := 1 ## Emplacement visé par « nouvelle campagne » ou « supprimer »
var lenient_choice := false ## Case « Mode indulgent » de la nouvelle campagne
var waiting_action := "" ## Action dont on attend la nouvelle touche ("" = aucune)
var font: Font
var sprites := SpriteBank.new()
var sky_tex: ImageTexture
var clock := 0.0
var panel: PanelContainer
var box: VBoxContainer
var theme_ui: Theme


func _ready() -> void:
	GameOptions.ensure_loaded()
	if CampaignState.migrate_legacy():
		notice = "Ancienne sauvegarde déplacée dans l'emplacement 1."
	GameAudio.music("menu")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	font = ThemeDB.fallback_font
	theme_ui = UiTheme.make(17)
	build_background()
	panel = PanelContainer.new()
	panel.theme = theme_ui
	add_child(panel)
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	add_version_label()
	get_viewport().size_changed.connect(_on_view_resized)
	var keys := get_node_or_null("/root/DisplayKeys")
	if keys != null:
		keys.fullscreen_toggled.connect(_on_fullscreen_toggled)
	refresh()


## Fenêtre redimensionnée (ou taille de l'interface changée) : fond et panneau recalculés.
func _on_view_resized() -> void:
	build_background()
	place_panel()


## Alt+Entrée / F11 : la case « Plein écran » de la page Options suit.
func _on_fullscreen_toggled(_on: bool) -> void:
	if page == "options" and waiting_action == "":
		refresh()


## Numéro de version du jeu (application/config/version dans project.godot).
static func game_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


## Version affichée discrètement dans le coin inférieur droit.
func add_version_label() -> void:
	var l := UiTheme.label("v" + game_version(), 12, UiTheme.DIM)
	l.name = "Version"
	l.modulate.a = 0.7
	l.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	l.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	l.grow_vertical = Control.GROW_DIRECTION_BEGIN
	l.offset_right = -8
	l.offset_bottom = -6
	add_child(l)


func _process(delta: float) -> void:
	clock += delta
	queue_redraw()


# ---------------------------------------------------------------- Pages

func refresh() -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	match page:
		"options":
			build_options()
		"new_campaign":
			build_new_campaign()
		"slots":
			build_slots()
		"confirm_delete":
			build_confirm_delete()
		_:
			build_main()
	# Le panneau se recentre sur son nouveau contenu
	panel.reset_size()
	await get_tree().process_frame
	place_panel()


## Page principale sous le titre, autres pages centrées ; réduites si la vue est trop petite.
func place_panel() -> void:
	if not is_inside_tree() or panel == null:
		return
	UiTheme.fit_panel(panel, get_viewport_rect().size, 0.36 if page == "main" else -1.0)


## Donne le focus clavier au bouton à l'image suivante, s'il est encore affiché.
func focus_later(b: Button) -> void:
	_grab_focus.call_deferred(b.get_instance_id())


func _grab_focus(id: int) -> void:
	var b := instance_from_id(id) as Button
	if b != null and b.is_inside_tree():
		b.grab_focus()


func add_button(s: String, cb: Callable, enabled := true, parent: Control = null) -> Button:
	var b := Button.new()
	b.text = s
	b.disabled = not enabled
	b.pressed.connect(cb)
	(parent if parent != null else box).add_child(b)
	return b


## Emplacement que « Continuer la campagne » reprend : celui joué en dernier (0 si aucun).
func continue_slot() -> int:
	return CampaignState.latest_slot()


func build_main() -> void:
	var last := continue_slot()
	var saved := CampaignState.load_slot(last) if last > 0 else null
	var over := saved != null and saved.is_over()
	var b := add_button("Bilan de la campagne" if over else "Continuer la campagne", continue_campaign, saved != null)
	b.custom_minimum_size.x = 300
	if saved != null:
		b.tooltip_text = "Emplacement %d : %s" % [last, saved.summary()]
		focus_later(b)
	var nb := add_button("Nouvelle campagne", new_campaign)
	if saved == null:
		focus_later(nb)
	add_button("Emplacements de campagne", open_slots)
	add_button("Tutoriel", start_tutorial)
	add_button("Escarmouche", start_skirmish)
	box.add_child(UiTheme.label("Escarmouche en difficulté %s (Options)" % Difficulty.display_name(GameOptions.difficulty).to_lower(), 13, UiTheme.DIM))
	add_button("Options", open_options)
	add_button("Quitter", quit_game)
	add_notice(300)


func add_notice(width: float) -> void:
	if notice != "":
		var l := UiTheme.label(notice, 14, UiTheme.WARN)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = width
		box.add_child(l)


func add_wrapped(s: String, size: int, col: Color, width := 460.0) -> Label:
	var l := UiTheme.label(s, size, col)
	l.custom_minimum_size.x = width
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(l)
	return l


## Emplacements : pour chacun, son résumé (jour, or, hommes, difficulté, état) et ses actions.
func build_slots() -> void:
	box.add_child(UiTheme.label("Emplacements de campagne", 22, UiTheme.GOLD))
	var first: Button = null
	for i in range(1, CampaignState.SLOT_COUNT + 1):
		box.add_child(HSeparator.new())
		var used := CampaignState.slot_used(i)
		var saved := CampaignState.load_slot(i) if used else null
		box.add_child(UiTheme.label("Emplacement %d" % i, 18, UiTheme.TEXT))
		if saved != null:
			add_wrapped(saved.summary(), 15, UiTheme.TEXT)
			add_wrapped(saved.status_text(), 13, UiTheme.WARN if saved.is_over() else UiTheme.DIM)
		elif used:
			add_wrapped("Sauvegarde illisible.", 14, UiTheme.WARN)
		else:
			add_wrapped("Vide.", 14, UiTheme.DIM)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		box.add_child(row)
		if saved != null:
			var c := add_button("Bilan" if saved.is_over() else "Continuer", continue_campaign.bind(i), true, row)
			c.name = "Continuer_%d" % i
			if first == null:
				first = c
		var n := add_button("Nouvelle campagne", new_campaign.bind(i), true, row)
		n.name = "Nouvelle_%d" % i
		if first == null:
			first = n
		if used:
			var d := add_button("Supprimer", ask_delete.bind(i), true, row)
			d.name = "Supprimer_%d" % i
	box.add_child(HSeparator.new())
	add_notice(460)
	var back := add_button("Retour", back_to_main)
	focus_later(first if first != null else back)


## Confirmation avant d'effacer un emplacement.
func build_confirm_delete() -> void:
	box.add_child(UiTheme.label("Supprimer l'emplacement %d ?" % target_slot, 22, UiTheme.GOLD))
	var saved := CampaignState.load_slot(target_slot)
	if saved != null:
		add_wrapped("%s\n%s" % [saved.summary(), saved.status_text()], 15, UiTheme.TEXT)
	add_wrapped("La campagne et sa copie de secours seront effacées. Impossible de revenir en arrière.", 15, UiTheme.WARN)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var yes := add_button("Supprimer", confirm_delete, true, row)
	yes.name = "Confirmer_suppression"
	var no := add_button("Annuler", open_slots, true, row)
	focus_later(no)


## Nouvelle campagne : choix de la difficulté et du mode indulgent (avertissement si
## l'emplacement choisi contient déjà une campagne en cours).
func build_new_campaign() -> void:
	box.add_child(UiTheme.label("Nouvelle campagne (emplacement %d)" % target_slot, 22, UiTheme.GOLD))
	var saved := CampaignState.load_slot(target_slot) if CampaignState.slot_used(target_slot) else null
	var running := saved != null and not saved.is_over()
	if running:
		add_wrapped("Une campagne est en cours sur cet emplacement (%s).\nLa remplacer par une nouvelle ? Sa sauvegarde sera effacée." % saved.summary(), 16, UiTheme.WARN)
	var ind := CheckButton.new()
	ind.name = "Indulgent"
	ind.text = "Mode indulgent"
	ind.button_pressed = lenient_choice
	ind.toggled.connect(func(on: bool) -> void: lenient_choice = on)
	box.add_child(ind)
	add_wrapped("Fermer le jeu pendant une bataille de contrat revient à l'état d'avant la bataille, et une embuscade interrompue est oubliée. Sans ce mode, la bataille reprend au lancement suivant.", 13, UiTheme.DIM)
	box.add_child(UiTheme.label("Choisissez la difficulté :", 16))
	for id in Difficulty.IDS:
		var b := add_button(Difficulty.display_name(id), confirm_new_campaign.bind(id))
		b.name = "Difficulte_" + id
		add_wrapped(Difficulty.hint(id), 13, UiTheme.DIM)
		if id == Difficulty.NORMAL and not running:
			focus_later(b)
	var back := add_button("Retour", back_to_main)
	if running:
		focus_later(back)


# ---------------------------------------------------------------- Options

func build_options() -> void:
	box.add_child(UiTheme.label("Options", 24, UiTheme.GOLD))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	add_volume(grid, "Volume général", "master", GameOptions.master_volume)
	add_volume(grid, "Musique", "music", GameOptions.music_volume)
	add_volume(grid, "Effets", "sfx", GameOptions.sfx_volume)

	grid.add_child(UiTheme.label("Plein écran"))
	var fs := CheckButton.new()
	fs.name = "PleinEcran"
	fs.button_pressed = GameOptions.is_window_fullscreen()
	fs.toggled.connect(set_fullscreen)
	grid.add_child(fs)
	grid.add_child(UiTheme.label("(Alt+Entrée ou F11)", 13, UiTheme.DIM))

	grid.add_child(UiTheme.label("Taille de l'interface"))
	var ui := OptionButton.new()
	ui.name = "TailleInterface"
	for v in GameOptions.UI_SCALES:
		ui.add_item(GameOptions.ui_scale_label(v))
	ui.selected = maxi(GameOptions.UI_SCALES.find(GameOptions.ui_scale), 0)
	ui.item_selected.connect(set_ui_scale)
	grid.add_child(ui)
	grid.add_child(UiTheme.label("(menus, carte et bataille)", 13, UiTheme.DIM))

	grid.add_child(UiTheme.label("Effets visuels"))
	var fx := OptionButton.new()
	fx.name = "Effets"
	for n in GameOptions.EFFECTS_NAMES:
		fx.add_item(n)
	fx.selected = maxi(GameOptions.EFFECTS.find(GameOptions.effects), 0)
	fx.item_selected.connect(set_effects)
	grid.add_child(fx)
	grid.add_child(UiTheme.label("(sang, fumée, éclaboussures, pluie au sol)", 13, UiTheme.DIM))

	grid.add_child(UiTheme.label("Vitesse du jeu"))
	var sp := OptionButton.new()
	for s in GameOptions.SPEEDS:
		sp.add_item(GameOptions.speed_label(s))
	sp.selected = maxi(GameOptions.SPEEDS.find(GameOptions.speed), 0)
	sp.item_selected.connect(set_speed)
	grid.add_child(sp)
	grid.add_child(UiTheme.label("(touche %s en bataille)" % GameOptions.key_label("speed"), 13, UiTheme.DIM))

	grid.add_child(UiTheme.label("Difficulté (escarmouche)"))
	var df := OptionButton.new()
	df.name = "Difficulte"
	for id in Difficulty.IDS:
		df.add_item(Difficulty.display_name(id))
	df.selected = maxi(Difficulty.IDS.find(GameOptions.difficulty), 0)
	df.item_selected.connect(set_difficulty)
	grid.add_child(df)
	grid.add_child(UiTheme.label("(la campagne a la sienne)", 13, UiTheme.DIM))
	UiTheme.add_access_options(grid)

	box.add_child(HSeparator.new())
	box.add_child(UiTheme.label("Touches de bataille", 18, UiTheme.GOLD))
	var keys := GridContainer.new()
	keys.columns = 4
	keys.add_theme_constant_override("h_separation", 12)
	keys.add_theme_constant_override("v_separation", 4)
	box.add_child(keys)
	for a in GameOptions.ACTIONS + GameOptions.CAMERA_ACTIONS:
		var id: String = a["id"]
		var l := UiTheme.label(str(a["name"]), 14)
		l.custom_minimum_size.x = 250
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		keys.add_child(l)
		var txt := "Appuyez…" if waiting_action == id else GameOptions.key_label(id)
		var b := add_button(txt, start_rebind.bind(id), true, keys)
		b.custom_minimum_size.x = 110
		b.name = "Touche_" + id
	var info := "Échap pour annuler." if waiting_action != "" else "Cliquez sur une touche pour la changer. Espace, Entrée, Échap, F11, flèches et chiffres sont réservés. La caméra garde la position des touches (ZQSD en AZERTY)."
	var il := UiTheme.label(info, 13, UiTheme.DIM)
	il.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	il.custom_minimum_size.x = 560
	box.add_child(il)
	if notice != "":
		var nl := UiTheme.label(notice, 14, UiTheme.WARN)
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nl.custom_minimum_size.x = 560
		box.add_child(nl)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	add_button("Touches par défaut", reset_keys, true, row)
	var back := add_button("Retour", back_to_main, true, row)
	if waiting_action == "":
		focus_later(back)


func add_volume(grid: GridContainer, title: String, which: String, value: float) -> void:
	grid.add_child(UiTheme.label(title))
	var s := HSlider.new()
	s.min_value = 0
	s.max_value = 100
	s.step = 5
	s.value = roundf(value * 100.0)
	s.custom_minimum_size = Vector2(260, 24)
	s.focus_mode = Control.FOCUS_ALL
	var pct := UiTheme.label("%d %%" % int(s.value), 15, UiTheme.DIM)
	pct.custom_minimum_size.x = 60
	s.value_changed.connect(func(v: float) -> void:
		set_volume(which, v / 100.0)
		pct.text = "%d %%" % int(v))
	grid.add_child(s)
	grid.add_child(pct)


func set_volume(which: String, v: float) -> void:
	match which:
		"master":
			GameOptions.master_volume = v
		"music":
			GameOptions.music_volume = v
		"sfx":
			GameOptions.sfx_volume = v
	GameOptions.apply_audio()
	GameOptions.save_options()


func set_fullscreen(on: bool) -> void:
	GameOptions.fullscreen = on
	GameOptions.apply_display()
	GameOptions.save_options()


func set_ui_scale(i: int) -> void:
	GameOptions.set_ui_scale(GameOptions.UI_SCALES[i])
	_on_view_resized.call_deferred() # La vue visible a changé de taille


func set_speed(i: int) -> void:
	GameOptions.speed = GameOptions.SPEEDS[i]
	GameOptions.save_options()


func set_effects(i: int) -> void:
	GameOptions.effects = GameOptions.EFFECTS[i]
	GameOptions.save_options()


func set_difficulty(i: int) -> void:
	GameOptions.difficulty = Difficulty.IDS[i]
	GameOptions.save_options()


func start_rebind(id: String) -> void:
	waiting_action = id
	notice = ""
	refresh()


func reset_keys() -> void:
	GameOptions.reset_keys()
	GameOptions.save_options()
	waiting_action = ""
	notice = "Touches remises par défaut."
	refresh()


## Écran « appuyez sur une touche » : la touche suivante est donnée à l'action choisie.
func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo:
		if waiting_action != "":
			get_viewport().set_input_as_handled()
			capture_key(k)
		elif k.keycode == KEY_ESCAPE and page != "main":
			get_viewport().set_input_as_handled()
			if page == "confirm_delete":
				open_slots()
			else:
				back_to_main()
		return
	# Un clic ailleurs pendant l'attente : on laisse le bouton cliqué agir normalement


func capture_key(k: InputEventKey) -> void:
	var id := waiting_action
	waiting_action = ""
	if k.keycode == KEY_ESCAPE:
		notice = "Changement annulé."
	else:
		notice = GameOptions.bind_event(id, k)
		GameOptions.save_options()
	refresh()


# ---------------------------------------------------------------- Actions

func go(path: String) -> void:
	last_scene = path
	if change_scenes:
		get_tree().change_scene_to_file(path)


## Continue une campagne : l'emplacement donné, sinon celui joué en dernier.
## Une bataille sauvegardée en cours reprend aussitôt (la carte relance la bataille).
func continue_campaign(i := 0) -> void:
	if i <= 0:
		i = continue_slot()
	if i <= 0:
		notice = "Aucune campagne sauvegardée."
		refresh()
		return
	var loaded := CampaignState.load_slot(i)
	if loaded == null:
		notice = "Sauvegarde illisible (emplacement %d)." % i
		refresh()
		return
	CampaignState.use_slot(i)
	CampaignState.current = loaded
	go(END_SCENE if loaded.is_over() else CAMPAIGN_SCENE)


## Nouvelle campagne sur un emplacement (par défaut : le premier libre, sinon le dernier joué).
func new_campaign(i := 0) -> void:
	if i <= 0:
		i = CampaignState.free_slot()
	if i <= 0:
		i = maxi(continue_slot(), 1)
	target_slot = i
	lenient_choice = false
	page = "new_campaign"
	notice = ""
	refresh()


func confirm_new_campaign(level := Difficulty.NORMAL) -> void:
	CampaignState.use_slot(target_slot)
	CampaignState.delete_save() # L'ancienne campagne et sa copie de secours disparaissent
	CampaignState.current = CampaignState.new_game(0, level, lenient_choice)
	CampaignState.current.save()
	page = "main"
	go(CAMPAIGN_SCENE)


func open_slots() -> void:
	page = "slots"
	notice = ""
	refresh()


func ask_delete(i: int) -> void:
	target_slot = i
	page = "confirm_delete"
	refresh()


func confirm_delete() -> void:
	CampaignState.delete_slot(target_slot)
	if CampaignState.slot == target_slot:
		CampaignState.current = null
	notice = "Emplacement %d supprimé." % target_slot
	page = "slots"
	refresh()


func start_tutorial() -> void:
	go(TUTORIAL_SCENE)


func start_skirmish() -> void:
	if CampaignState.current != null:
		CampaignState.current.pending = {} # Bataille hors campagne
	go(BATTLE_SCENE)


func open_options() -> void:
	page = "options"
	notice = ""
	waiting_action = ""
	refresh()


func back_to_main() -> void:
	page = "main"
	notice = ""
	waiting_action = ""
	refresh()


func quit_game() -> void:
	last_scene = "quit"
	if change_scenes:
		get_tree().quit()


# ---------------------------------------------------------------- Fond pixel art

## Le fond est généré à la taille de la vue (pixels carrés en 16:9, 16:10 comme en 21:9).
func build_background() -> void:
	var vs := get_viewport_rect().size
	var w := maxi(ceili(vs.x / PIX), 80)
	var h := maxi(ceili(vs.y / PIX), 45)
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1453
	var hills := FastNoiseLite.new()
	hills.seed = 3
	hills.frequency = 0.012
	var top := Color(0.13, 0.12, 0.27)
	var mid := Color(0.62, 0.34, 0.33)
	var low := Color(0.98, 0.7, 0.4)
	for y in h:
		# Ciel en bandes de couleur nettes (dégradé « pixel art »)
		var t := floorf(float(y) / (h * 0.62) * 12.0) / 12.0
		var c := top.lerp(mid, clampf(t * 1.4, 0, 1)) if t < 0.7 else mid.lerp(low, clampf((t - 0.7) / 0.3, 0, 1))
		for x in w:
			img.set_pixel(x, y, c)
	# Étoiles
	for i in 70:
		var p := Vector2i(rng.randi_range(0, w - 1), rng.randi_range(0, int(h * 0.3)))
		img.set_pixel(p.x, p.y, Color(1, 0.95, 0.85).darkened(rng.randf() * 0.4))
	# Soleil couchant
	var sun := Vector2(w * 0.72, h * 0.6)
	for y in h:
		for x in w:
			if Vector2(x, y).distance_to(sun) < 14.0:
				img.set_pixel(x, y, Color(1, 0.86, 0.55))
	# Montagnes lointaines, puis collines proches
	_ridge(img, h * 0.55, 18.0, 0.02, 21, Color(0.36, 0.25, 0.36))
	_ridge(img, h * 0.66, 10.0, 0.035, 5, Color(0.25, 0.2, 0.27))
	# Château sur la colline (silhouette)
	var base_y := int(h * 0.6)
	var cx := int(w * 0.17)
	var dark := Color(0.14, 0.11, 0.17)
	_rect(img, cx - 26, base_y - 14, 52, 22, dark)
	for k in 7:
		_rect(img, cx - 26 + k * 8, base_y - 17, 4, 3, dark) # Créneaux
	_rect(img, cx - 34, base_y - 30, 12, 38, dark)
	_rect(img, cx + 22, base_y - 26, 12, 34, dark)
	_rect(img, cx - 6, base_y - 40, 12, 30, dark)
	for tx in [cx - 34, cx + 22, cx - 6]:
		for k in 3:
			_rect(img, tx + k * 5, (base_y - 33) if tx == cx - 34 else ((base_y - 29) if tx == cx + 22 else base_y - 43), 3, 3, dark)
	_rect(img, cx - 1, base_y - 52, 1, 9, dark) # Hampe
	_rect(img, cx, base_y - 52, 6, 3, Color(0.22, 0.38, 0.85)) # Bannière bleue
	for p in [Vector2i(cx - 30, base_y - 22), Vector2i(cx + 26, base_y - 18), Vector2i(cx - 2, base_y - 32)]:
		_rect(img, p.x, p.y, 2, 3, Color(1, 0.75, 0.35)) # Fenêtres éclairées
	# Collines du premier plan
	for x in w:
		var gy := int(h * 0.74 + hills.get_noise_1d(x) * 10.0)
		for y in range(gy, h):
			var d := float(y - gy) / float(h - gy)
			var c := Color(0.27, 0.36, 0.2).lerp(Color(0.16, 0.22, 0.12), d)
			if rng.randf() < 0.06:
				c = c.lightened(0.08)
			img.set_pixel(x, y, c)
	# Route où défile la colonne
	for x in w:
		for y in range(int(h * 0.87), int(h * 0.92)):
			img.set_pixel(x, y, Color(0.45, 0.36, 0.24).darkened(0.1 if rng.randf() < 0.2 else 0.0))
	sky_tex = ImageTexture.create_from_image(img)


func _ridge(img: Image, base: float, amp: float, freq: float, seed_value: int, col: Color) -> void:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.frequency = freq
	n.fractal_octaves = 3
	for x in img.get_width():
		var top := int(base + n.get_noise_1d(x) * amp * 2.0)
		for y in range(maxi(top, 0), img.get_height()):
			img.set_pixel(x, y, col)


func _rect(img: Image, x: int, y: int, w: int, h: int, col: Color) -> void:
	img.fill_rect(Rect2i(x, y, w, h).intersection(Rect2i(0, 0, img.get_width(), img.get_height())), col)


func _draw() -> void:
	var vs := get_viewport_rect().size
	if sky_tex != null:
		draw_texture_rect(sky_tex, Rect2(Vector2.ZERO, Vector2(sky_tex.get_size()) * PIX), false)
	if page != "main":
		return # Les pages Options et confirmation masquent le titre et la colonne
	# Titre
	var title := "COMPAGNIE FRANCHE"
	var tw := vs.x
	var big := UiTheme.title_size(vs, 64, title.length())
	var ty := minf(vs.y * 0.2, vs.y * 0.36 - 56.0)
	for o in [Vector2(5, 5), Vector2(-2, 0), Vector2(2, 0), Vector2(0, -2), Vector2(0, 2)]:
		draw_string(font, Vector2(0, ty) + o, title, HORIZONTAL_ALIGNMENT_CENTER, tw, big, Color(0.1, 0.06, 0.03))
	draw_string(font, Vector2(0, ty), title, HORIZONTAL_ALIGNMENT_CENTER, tw, big, UiTheme.GOLD)
	var sub := "Batailles de mercenaires au comté de Valfrène"
	var small := UiTheme.title_size(vs, 20, sub.length())
	draw_string(font, Vector2(2, ty + 42), sub, HORIZONTAL_ALIGNMENT_CENTER, tw, small, Color(0, 0, 0, 0.7))
	draw_string(font, Vector2(0, ty + 40), sub, HORIZONTAL_ALIGNMENT_CENTER, tw, small, Color(1, 0.93, 0.8))
	# Colonne en marche sur la route, de gauche à droite (en boucle)
	var road_y := vs.y * 0.9
	var step := 64.0
	var span := MARCH.size() * step + vs.x
	for i in MARCH.size():
		var type: String = MARCH[i]
		var x := fmod(clock * 30.0 + i * step, span) - MARCH.size() * step * 0.5
		var p := Vector2(x, road_y + (i % 2) * 6.0)
		if sprites.has_unit(type, 0):
			var f := sprites.frame(type, 0, SpriteBank.RIGHT, "walk", clock * 8.0 + i)
			var src: Rect2 = f["src"]
			var foot: Vector2 = f["foot"]
			var sc := 3.0
			draw_rect(Rect2(p.x - 15, p.y - 3, 30, 6), Color(0, 0, 0, 0.25))
			draw_texture_rect_region(f["tex"], Rect2(p - foot * sc, src.size * sc), src)
		else:
			draw_rect(Rect2(p.x - 6, p.y - 30, 12, 30), Color(0.22, 0.38, 0.85))
	draw_string(font, Vector2(12, vs.y - 10), "Prototype · assets libres (voir CREDITS.md)", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.5))
