class_name UiTheme
extends RefCounted
## Thème des menus (bois sombre et bordures dorées, comme le panneau de la carte de campagne).

const GOLD := Color(1, 0.84, 0.4)
const TEXT := Color(0.92, 0.88, 0.78)
const DIM := Color(0.72, 0.69, 0.62)
const WARN := Color(1, 0.62, 0.3)


static func make(font_size := 16) -> Theme:
	var th := Theme.new()
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.11, 0.08, 0.06, 0.94)
	bg.border_color = Color(0.6, 0.47, 0.25)
	bg.set_border_width_all(3)
	bg.set_content_margin_all(18)
	bg.shadow_color = Color(0, 0, 0, 0.5)
	bg.shadow_size = 0
	bg.shadow_offset = Vector2(6, 6)
	th.set_stylebox("panel", "PanelContainer", bg)
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		sb.content_margin_top = 7
		sb.content_margin_bottom = 7
		sb.set_border_width_all(2)
		sb.bg_color = Color(0.3, 0.21, 0.12)
		sb.border_color = Color(0.6, 0.47, 0.25)
		match st:
			"hover":
				sb.bg_color = Color(0.42, 0.3, 0.16)
				sb.border_color = GOLD
			"pressed":
				sb.bg_color = Color(0.22, 0.15, 0.08)
			"disabled":
				sb.bg_color = Color(0.18, 0.15, 0.12)
				sb.border_color = Color(0.3, 0.27, 0.22)
			"focus":
				sb.draw_center = false
				sb.border_color = GOLD
		for cls in ["Button", "OptionButton", "CheckButton"]:
			th.set_stylebox(st, cls, sb)
	for cls in ["Button", "OptionButton", "CheckButton"]:
		th.set_color("font_color", cls, Color(1, 0.93, 0.78))
		th.set_color("font_hover_color", cls, Color(1, 1, 0.85))
		th.set_color("font_pressed_color", cls, GOLD)
		th.set_color("font_disabled_color", cls, Color(0.55, 0.5, 0.42))
		th.set_font_size("font_size", cls, font_size)
	th.set_color("font_color", "Label", TEXT)
	th.set_font_size("font_size", "Label", font_size)
	# Curseurs de volume : rainure sombre, partie remplie dorée
	var groove := StyleBoxFlat.new()
	groove.bg_color = Color(0.06, 0.05, 0.04)
	groove.border_color = Color(0.45, 0.35, 0.2)
	groove.set_border_width_all(1)
	groove.content_margin_top = 4
	groove.content_margin_bottom = 4
	th.set_stylebox("slider", "HSlider", groove)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.75, 0.58, 0.25)
	fill.content_margin_top = 4
	fill.content_margin_bottom = 4
	th.set_stylebox("grabber_area", "HSlider", fill)
	th.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var popup := StyleBoxFlat.new()
	popup.bg_color = Color(0.16, 0.11, 0.07)
	popup.border_color = Color(0.6, 0.47, 0.25)
	popup.set_border_width_all(2)
	th.set_stylebox("panel", "PopupMenu", popup)
	th.set_color("font_color", "PopupMenu", Color(1, 0.93, 0.78))
	th.set_font_size("font_size", "PopupMenu", font_size)
	return th


## Étiquette avec couleur et taille.
static func label(s: String, size := 16, col := TEXT) -> Label:
	var l := Label.new()
	l.text = s
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


## Place un panneau dans la zone visible `vs` (taille réelle de la vue, qui dépend de la fenêtre
## et de la taille de l'interface) : centré horizontalement, en haut à `top` (fraction de la
## hauteur, ou centré si négatif), et réduit s'il ne tient pas (petite fenêtre, interface à 150 %).
static func fit_panel(panel: Control, vs: Vector2, top := -1.0, margin := 12.0) -> void:
	panel.reset_size()
	var w := panel.get_combined_minimum_size()
	panel.size = w
	if w.x <= 0.0 or w.y <= 0.0:
		return
	var avail := vs - Vector2(margin, margin) * 2.0
	var k := clampf(minf(avail.x / w.x, avail.y / w.y), 0.4, 1.0)
	panel.pivot_offset = Vector2.ZERO
	panel.scale = Vector2(k, k)
	var s := w * k
	var y := (vs.y - s.y) * 0.5
	if top >= 0.0:
		y = minf(vs.y * top, vs.y - margin - s.y)
	panel.position = Vector2((vs.x - s.x) * 0.5, maxf(y, margin)).round()


## Taille de police d'un titre dessiné, réduite si la vue est trop étroite pour `chars` caractères.
static func title_size(vs: Vector2, base: int, chars: int) -> int:
	return clampi(int(vs.x / (chars * 0.72)), 18, base)


## Accessibilité : formes des camps et sous-titres (menu principal et menu pause).
static func add_access_options(grid: GridContainer) -> void:
	var rows := [
		["Formes des camps", "FormesCamps", GameOptions.team_shapes, "(rond : vous, losange : l'ennemi)"],
		["Sous-titres", "SousTitres", GameOptions.subtitles, "(cors, charges, embuscades)"],
		["Tutoriel guidé", "TutorielGuide", GameOptions.tutorial, "(proposé à la première campagne)"],
	]
	for row in rows:
		grid.add_child(UiTheme.label(row[0]))
		var c := CheckButton.new()
		c.name = row[1]
		c.button_pressed = row[2]
		var which: String = row[1]
		c.toggled.connect(func(on: bool) -> void:
			if which == "FormesCamps":
				GameOptions.team_shapes = on
			elif which == "TutorielGuide":
				GameOptions.tutorial = on
				if on:
					GameOptions.tutorial_offered = false # Proposé de nouveau à la prochaine campagne
			else:
				GameOptions.subtitles = on
			GameOptions.save_options())
		grid.add_child(c)
		grid.add_child(UiTheme.label(row[3], 13, UiTheme.DIM))
