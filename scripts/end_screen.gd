extends Control
## Écran de fin de campagne, dans le style des menus : victoire (la bataille décisive est gagnée)
## ou game over (la compagnie est anéantie et ruinée), avec le bilan de la campagne.
## Lit CampaignState.current, ou la sauvegarde si aucune campagne n'est en mémoire.

const MENU_SCENE := "res://scenes/menu.tscn"
const CAMPAIGN_SCENE := "res://scenes/campaign.tscn"
const PIX := 4 ## Taille d'un « pixel » du fond

var change_scenes := true ## Faux dans les tests : on note la scène demandée sans en changer
var last_scene := "" ## Dernière scène demandée
var state: CampaignState
var victory := false
var font: Font
var sky_tex: ImageTexture
var clock := 0.0
var panel: PanelContainer
var box: VBoxContainer


func _ready() -> void:
	GameOptions.ensure_loaded()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	font = ThemeDB.fallback_font
	state = CampaignState.current
	if state == null:
		state = CampaignState.load_game()
	victory = state != null and state.ended == "victory"
	GameAudio.music("victory" if victory else "defeat")
	build_background()
	panel = PanelContainer.new()
	panel.theme = UiTheme.make(16)
	add_child(panel)
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	build()
	panel.reset_size()
	place_panel.call_deferred() # Une fois le contenu mesuré


func place_panel() -> void:
	if not is_inside_tree():
		return
	var vs := get_viewport_rect().size
	var w := panel.get_combined_minimum_size()
	panel.position = Vector2(((vs.x - w.x) * 0.5), maxf(vs.y * 0.3, (vs.y - w.y) * 0.5 + 40.0)).round()


func _process(delta: float) -> void:
	clock += delta
	queue_redraw()


## Lignes du bilan : [intitulé, valeur].
func summary_rows() -> Array:
	var s := state
	var vets := 0
	var seasoned := 0
	for r in s.company:
		match CampaignState.rank_of(r):
			2:
				vets += 1
			1:
				seasoned += 1
	var days := s.end_day if s.end_day > 0 else s.day
	return [
		["Durée de la campagne", CampaignState.plural(days, "jour", "jours")],
		["Batailles livrées", "%d (%s, %s)" % [s.victories + s.defeats, CampaignState.plural(s.victories, "victoire", "victoires"), CampaignState.plural(s.defeats, "défaite", "défaites")]],
		["Ennemis tués", str(s.enemies_killed)],
		["Hommes perdus", str(s.men_lost)],
		["Or gagné (primes, butin, escortes)", "%d écus" % s.gold_earned],
		["Or en caisse", "%d écus" % int(s.gold)],
		["Renommée", str(s.fame)],
		["Compagnie à la fin", "%s, %s" % [CampaignState.plural(s.company.size(), "régiment", "régiments"), CampaignState.plural(s.total_men(), "homme", "hommes")]],
		["Régiments vétérans / aguerris", "%d / %d" % [vets, seasoned]],
	]


func build() -> void:
	if state == null or state.ended == "":
		box.add_child(UiTheme.label("Aucune campagne terminée.", 20, UiTheme.GOLD))
		focus_later(add_button("Menu principal", to_menu))
		return
	var title := UiTheme.label("La guerre est gagnée !" if victory else "La compagnie est dissoute", 26, UiTheme.GOLD if victory else UiTheme.WARN)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var note := UiTheme.label(state.end_note, 15)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 520
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(note)
	box.add_child(HSeparator.new())
	box.add_child(UiTheme.label("Bilan", 18, UiTheme.GOLD))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 3)
	box.add_child(grid)
	for row in summary_rows():
		var l := UiTheme.label(str(row[0]), 15, UiTheme.DIM)
		l.custom_minimum_size.x = 300
		grid.add_child(l)
		grid.add_child(UiTheme.label(str(row[1]), 15))
	box.add_child(HSeparator.new())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	var nb := add_button("Nouvelle campagne", new_campaign, row)
	add_button("Menu principal", to_menu, row)
	focus_later(nb)


func add_button(s: String, cb: Callable, parent: Control = null) -> Button:
	var b := Button.new()
	b.text = s
	b.pressed.connect(cb)
	(parent if parent != null else box).add_child(b)
	return b


func focus_later(b: Button) -> void:
	b.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
		to_menu()


func go(path: String) -> void:
	last_scene = path
	if change_scenes:
		get_tree().change_scene_to_file(path)


## La campagne finie reste sauvegardée (le menu propose d'en revoir le bilan).
func to_menu() -> void:
	go(MENU_SCENE)


func new_campaign() -> void:
	var level := CampaignState.current.difficulty if CampaignState.current != null else Difficulty.NORMAL
	CampaignState.current = CampaignState.new_game(0, level) # Même difficulté qu'avant
	CampaignState.current.save()
	go(CAMPAIGN_SCENE)


# ---------------------------------------------------------------- Fond pixel art

## Victoire : aube dorée et bannières levées. Ruine : nuit froide, bannière à terre.
func build_background() -> void:
	var w := 1280 / PIX
	var h := 720 / PIX
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1346
	var top := Color(0.2, 0.22, 0.42) if victory else Color(0.05, 0.06, 0.1)
	var low := Color(1, 0.78, 0.45) if victory else Color(0.22, 0.2, 0.26)
	for y in h:
		var t := floorf(float(y) / (h * 0.7) * 10.0) / 10.0
		img.fill_rect(Rect2i(0, y, w, 1), top.lerp(low, clampf(t, 0.0, 1.0)))
	if not victory:
		for i in 60:
			img.set_pixel(rng.randi_range(0, w - 1), rng.randi_range(0, int(h * 0.4)), Color(0.85, 0.85, 0.95).darkened(rng.randf() * 0.5))
	var hills := FastNoiseLite.new()
	hills.seed = 9
	hills.frequency = 0.015
	var near := Color(0.27, 0.36, 0.2) if victory else Color(0.1, 0.11, 0.12)
	for x in w:
		var gy := int(h * 0.72 + hills.get_noise_1d(x) * 12.0)
		for y in range(gy, h):
			var c := near.darkened(float(y - gy) / float(h - gy) * 0.4)
			if rng.randf() < 0.05:
				c = c.lightened(0.07)
			img.set_pixel(x, y, c)
	sky_tex = ImageTexture.create_from_image(img)


func _draw() -> void:
	var vs := get_viewport_rect().size
	if sky_tex != null:
		draw_texture_rect(sky_tex, Rect2(Vector2.ZERO, vs), false)
	var ground := vs.y * 0.74
	if victory:
		# Bannières bleues de la compagnie qui flottent au vent
		for k in 5:
			var x := vs.x * (0.12 + k * 0.19)
			var base := Vector2(x, ground + (k % 2) * 10.0)
			draw_line(base, base + Vector2(0, -90), Color(0.35, 0.24, 0.12), 4.0)
			var wave := sin(clock * 3.0 + k) * 4.0
			var flag := PackedVector2Array([base + Vector2(2, -90), base + Vector2(46, -84 + wave), base + Vector2(44, -62 + wave), base + Vector2(2, -66)])
			draw_colored_polygon(flag, Color(0.22, 0.38, 0.85))
			draw_rect(Rect2(base + Vector2(18, -82), Vector2(6, 14)), Color(1, 0.95, 0.8))
			draw_rect(Rect2(base + Vector2(13, -77), Vector2(16, 4)), Color(1, 0.95, 0.8))
	else:
		# Une bannière brisée plantée de travers
		var base := Vector2(vs.x * 0.8, ground + 6.0)
		var tip := base + Vector2(40, -70)
		draw_line(base, tip, Color(0.3, 0.22, 0.14), 4.0)
		draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(30, 20), tip + Vector2(16, 40), tip + Vector2(-6, 24)]), Color(0.2, 0.28, 0.5))
	var title := "COMPAGNIE FRANCHE"
	var tw := 1200.0
	var ty := vs.y * 0.17
	for o in [Vector2(4, 4), Vector2(-2, 0), Vector2(2, 0), Vector2(0, -2), Vector2(0, 2)]:
		draw_string(font, Vector2((vs.x - tw) * 0.5, ty) + o, title, HORIZONTAL_ALIGNMENT_CENTER, tw, 52, Color(0.1, 0.06, 0.03))
	draw_string(font, Vector2((vs.x - tw) * 0.5, ty), title, HORIZONTAL_ALIGNMENT_CENTER, tw, 52, UiTheme.GOLD)
	var sub := "Victoire" if victory else "Fin de la campagne"
	draw_string(font, Vector2((vs.x - tw) * 0.5, ty + 36), sub, HORIZONTAL_ALIGNMENT_CENTER, tw, 22, Color(1, 0.93, 0.8))
