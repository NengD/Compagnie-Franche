class_name PauseMenu
extends Control
## Menu pause de la bataille (Échap) : reprendre, aide, options, abandonner, menu principal.
## La bataille ne simule plus rien tant qu'il est ouvert (battle.gd teste menu_open()).
## En contrat, abandonner ou quitter vers le menu principal sonne la retraite (avec confirmation).

const MENU_SCENE := "res://scenes/menu.tscn"

var battle: Battle ## Bataille en cours (battle.gd ou tutorial.gd)
var page := "main" ## "main", "help", "options", "confirm_abandon" ou "confirm_menu"
var change_scenes := true ## Faux dans les tests : on note la scène demandée sans en changer
var last_scene := "" ## Dernière scène demandée
var box: VBoxContainer
var panel: PanelContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP # Les clics ne passent pas à la bataille
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	panel = PanelContainer.new()
	panel.theme = UiTheme.make(17)
	add_child(panel)
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	get_viewport().size_changed.connect(place_panel)
	var keys := get_node_or_null("/root/DisplayKeys")
	if keys != null:
		keys.fullscreen_toggled.connect(func(_on: bool) -> void:
			if visible and page == "options":
				refresh())
	refresh()


## Centré dans la vue, réduit s'il ne tient pas (petite fenêtre, grande taille d'interface).
func place_panel() -> void:
	if panel == null or not is_inside_tree():
		return
	UiTheme.fit_panel(panel, get_viewport_rect().size)


## Le menu est-il affiché ?
func is_open() -> bool:
	return visible


func open() -> void:
	page = "main"
	visible = true
	refresh()


func close() -> void:
	visible = false
	page = "main"


## Échap : revient à la page principale, ou ferme le menu.
func on_escape() -> void:
	if page == "main":
		close()
	else:
		show_page("main")


func show_page(p: String) -> void:
	page = p
	refresh()


func in_contract() -> bool:
	return battle.campaign != null


# ---------------------------------------------------------------- Pages

func refresh() -> void:
	if box == null:
		return
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	match page:
		"help":
			build_help()
		"options":
			build_options()
		"confirm_abandon":
			build_confirm_abandon()
		"confirm_menu":
			build_confirm_menu()
		_:
			build_main()
	place_panel()
	place_panel.call_deferred() # Une fois les anciens boutons libérés et le contenu mesuré


func add_button(s: String, cb: Callable, parent: Control = null) -> Button:
	var b := Button.new()
	b.text = s
	b.pressed.connect(cb)
	(parent if parent != null else box).add_child(b)
	return b


func focus_later(b: Button) -> void:
	_grab_focus.call_deferred(b.get_instance_id())


func _grab_focus(id: int) -> void:
	var b := instance_from_id(id) as Button
	if b != null and b.is_inside_tree() and b.is_visible_in_tree():
		b.grab_focus()


func add_text(s: String, size := 15, col := UiTheme.TEXT, width := 420.0) -> Label:
	var l := UiTheme.label(s, size, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = width
	box.add_child(l)
	return l


func build_main() -> void:
	box.add_child(UiTheme.label("Pause", 26, UiTheme.GOLD))
	var what := "Escarmouche"
	if in_contract():
		what = "Contrat : %s" % battle.campaign.pending.get("title", "")
	elif battle.has_method("current_id"):
		what = "Tutoriel"
	var l := UiTheme.label(what, 14, UiTheme.DIM)
	box.add_child(l)
	var resume := add_button("Reprendre", resume_battle)
	resume.custom_minimum_size.x = 320
	focus_later(resume)
	add_button("Aide", show_page.bind("help"))
	add_button("Options", show_page.bind("options"))
	add_button("Abandonner la bataille", ask_abandon)
	add_button("Menu principal", ask_main_menu)
	if in_contract():
		add_text("En contrat, abandonner ou quitter compte comme une retraite.", 13, UiTheme.DIM, 320)


func build_help() -> void:
	box.add_child(UiTheme.label("Aide", 24, UiTheme.GOLD))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 2)
	box.add_child(grid)
	var lines: Array[String] = Hud.help_lines()
	@warning_ignore("integer_division")
	var half := (lines.size() + 1) / 2
	# Deux colonnes : la première moitié à gauche, la seconde à droite
	for i in half:
		grid.add_child(UiTheme.label(lines[i], 14))
		grid.add_child(UiTheme.label(lines[i + half] if i + half < lines.size() else "", 14))
	add_text("Pendant le déploiement, vos troupes se placent dans la zone bleue : aucun combat avant Espace.", 14, UiTheme.DIM, 760)
	focus_later(add_button("Retour", show_page.bind("main")))


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
	grid.add_child(UiTheme.label("Vitesse du jeu"))
	var sp := OptionButton.new()
	sp.name = "Vitesse"
	for s in GameOptions.SPEEDS:
		sp.add_item(GameOptions.speed_label(s))
	sp.selected = maxi(GameOptions.SPEEDS.find(battle.game_speed), 0)
	sp.item_selected.connect(set_speed)
	grid.add_child(sp)
	grid.add_child(UiTheme.label("(touche %s)" % GameOptions.key_label("speed"), 13, UiTheme.DIM))
	grid.add_child(UiTheme.label("Plein écran"))
	var fs := CheckButton.new()
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
	grid.add_child(Control.new())
	UiTheme.add_access_options(grid)
	add_text("Les touches se reconfigurent depuis le menu principal (Options).", 13, UiTheme.DIM)
	focus_later(add_button("Retour", show_page.bind("main")))


func add_volume(grid: GridContainer, title: String, which: String, value: float) -> void:
	grid.add_child(UiTheme.label(title))
	var s := HSlider.new()
	s.name = "Volume_" + which
	s.min_value = 0
	s.max_value = 100
	s.step = 5
	s.value = roundf(value * 100.0)
	s.custom_minimum_size = Vector2(240, 24)
	s.focus_mode = Control.FOCUS_ALL
	var pct := UiTheme.label("%d %%" % int(s.value), 15, UiTheme.DIM)
	pct.custom_minimum_size.x = 60
	s.value_changed.connect(func(v: float) -> void:
		set_volume(which, v / 100.0)
		pct.text = "%d %%" % int(v))
	grid.add_child(s)
	grid.add_child(pct)


func build_confirm_abandon() -> void:
	box.add_child(UiTheme.label("Abandonner la bataille", 22, UiTheme.GOLD))
	if in_contract():
		add_text("Sonner la retraite ? La bataille est perdue, mais seuls les hommes au contact de l'ennemi risquent d'être rattrapés.")
		confirm_row("Oui, sonner la retraite", confirm_abandon)
	else:
		add_text("Quitter cette bataille et revenir au menu principal ?")
		confirm_row("Oui, abandonner", confirm_abandon)


func build_confirm_menu() -> void:
	box.add_child(UiTheme.label("Menu principal", 22, UiTheme.GOLD))
	add_text("Quitter vers le menu principal compte comme une retraite : la bataille est perdue et le contrat échoue (pertes limitées aux hommes au contact).", 15, UiTheme.WARN)
	confirm_row("Oui, retraite et menu", confirm_main_menu)


func confirm_row(yes_text: String, yes: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	add_button(yes_text, yes, row)
	focus_later(add_button("Non", show_page.bind("main"), row))


# ---------------------------------------------------------------- Actions

func resume_battle() -> void:
	close()


func ask_abandon() -> void:
	show_page("confirm_abandon")


func ask_main_menu() -> void:
	if in_contract():
		show_page("confirm_menu")
	else:
		go(MENU_SCENE)


## Contrat : retraite ordonnée (l'écran de fin s'affiche, Entrée ramène à la carte).
## Escarmouche et tutoriel : retour au menu principal.
func confirm_abandon() -> void:
	if in_contract():
		battle.order_retreat()
		close()
	else:
		go(MENU_SCENE)


func confirm_main_menu() -> void:
	battle.order_retreat() # Résultat reporté et sauvegardé sur la campagne
	go(MENU_SCENE)


func go(path: String) -> void:
	last_scene = path
	close()
	if change_scenes:
		get_tree().change_scene_to_file(path)


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


func set_speed(i: int) -> void:
	GameOptions.speed = GameOptions.SPEEDS[i]
	battle.game_speed = GameOptions.speed
	GameOptions.save_options()


func set_fullscreen(on: bool) -> void:
	GameOptions.fullscreen = on
	GameOptions.apply_display()
	GameOptions.save_options()


func set_ui_scale(i: int) -> void:
	GameOptions.set_ui_scale(GameOptions.UI_SCALES[i])
	place_panel.call_deferred()
