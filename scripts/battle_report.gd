class_name BattleReport
extends Control
## Bilan de fin de bataille : panneau dans le style des menus, posé sur le champ de bataille
## (qui continue au ralenti derrière). Construit à partir du bilan de battle.gd (build_end_report).
## Entrée ou le bouton principal : continuer (carte de campagne, rejouer) ; Échap : menu principal.

## Largeur des colonnes du tableau des régiments (en pixels).
const COLS := {"name": 232, "men": 118, "dead": 62, "fled": 72, "healed": 70, "kills": 60, "xp": 196}
const GOOD := Color(0.6, 0.9, 0.5)
const BAD := Color(1, 0.5, 0.4)

var battle: Battle ## Bataille terminée (battle.gd ou tutorial.gd)
var report: Dictionary = {}
var panel: PanelContainer
var buttons: Array[Button] = []
var table_box: VBoxContainer ## Page « Régiments » (tableau)
var stats_box: Control ## Page « Statistiques » (graphiques), null sans relevés
var tab_buttons: Array[Button] = []


## Construit le panneau. rep : bilan de battle.build_end_report().
func setup(rep: Dictionary, b: Battle) -> void:
	report = rep
	battle = b
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP # Les clics ne passent plus au champ de bataille
	theme = UiTheme.make(15)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.35)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	panel = PanelContainer.new()
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	build_header(box)
	build_tabs(box)
	box.add_child(HSeparator.new())
	table_box = VBoxContainer.new()
	table_box.name = "Regiments"
	table_box.add_theme_constant_override("separation", 6)
	box.add_child(table_box)
	build_table(table_box)
	stats_box = build_stats(box)
	box.add_child(HSeparator.new())
	build_totals(box)
	build_buttons(box)


func _ready() -> void:
	get_viewport().size_changed.connect(place_panel)
	place_panel.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and visible:
		place_panel.call_deferred()


## Centré dans la vue, réduit s'il ne tient pas (petite fenêtre, interface à 150 %).
func place_panel() -> void:
	if panel == null or not is_inside_tree():
		return
	UiTheme.fit_panel(panel, get_viewport_rect().size)


func is_campaign() -> bool:
	return not (report.get("campaign", {}) as Dictionary).is_empty()


func build_header(box: VBoxContainer) -> void:
	var title := "VICTOIRE"
	var col := UiTheme.GOLD
	match str(report["outcome"]):
		"defeat":
			title = "DÉFAITE"
			col = BAD
		"retreat":
			title = "RETRAITE"
			col = UiTheme.WARN
	var t := UiTheme.label(title, 34, col)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	var parts: Array[String] = [str(report["title"]), "Terrain : " + str(report["terrain"]), "Durée : " + duration_text(float(report["duration"]))]
	var sub := UiTheme.label(" · ".join(parts), 15, UiTheme.TEXT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	# Objectif du contrat (sauf « détruire l'ennemi », que l'issue dit déjà)
	var obj: Dictionary = report.get("objective", {})
	if not obj.is_empty() and str(obj.get("kind", "destroy")) != "destroy":
		var line := "Objectif : %s" % str(obj["label"])
		if str(obj.get("summary", "")) != "":
			line += " — " + str(obj["summary"])
		var ol := UiTheme.label(line, 15, GOOD if bool(obj.get("success", false)) else BAD)
		ol.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ol.name = "Objectif" # Repérable par les tests
		box.add_child(ol)


static func duration_text(t: float) -> String:
	var s := int(round(t))
	@warning_ignore("integer_division")
	return "%d min %02d s" % [s / 60, s % 60]


## Tableau : une ligne par régiment du joueur. Blessés et expérience seulement en campagne.
func build_table(box: VBoxContainer) -> void:
	var camp := is_campaign()
	var head := {"name": "Régiment", "men": "Effectif", "dead": "Morts", "fled": "Fuyards", "kills": "Tués"}
	if camp:
		head["healed"] = "Blessés"
		head["xp"] = "Expérience"
	box.add_child(make_row(head, UiTheme.DIM, 13, null))
	for row in report["rows"]:
		var cells := {
			"name": "%d  %s" % [int(row["index"]) + 1, row["name"]],
			"men": "%d → %d" % [int(row["before"]), int(row["after"])],
			"dead": str(row["dead"]) if int(row["dead"]) > 0 else "—",
			"fled": str(row["fled"]) if int(row["fled"]) > 0 else "—",
			"kills": str(row["kills"]),
		}
		if int(row["rank"]) > 0:
			cells["name"] += "  (%s)" % Regiment.RANK_NAMES[int(row["rank"])]
		var promo: bool = row["promoted"]
		if camp:
			cells["healed"] = "+%d" % int(row["healed"]) if int(row["healed"]) > 0 else "—"
			cells["xp"] = "+%d xp" % int(round(float(row["xp"])))
			if promo:
				cells["xp"] += "   ▲ %s !" % str(Regiment.RANK_NAMES[int(row["rank_after"])]).to_upper()
		var col := UiTheme.TEXT
		if int(row["after"]) <= 0:
			cells["men"] += "  anéanti"
			col = BAD
		box.add_child(make_row(cells, col, 15, row))


## Une ligne du tableau. row : données du régiment (null pour l'en-tête) ; une promotion
## colore la ligne en doré et encadre la cellule d'expérience.
func make_row(cells: Dictionary, col: Color, size: int, row) -> Control:
	var holder := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	sb.bg_color = Color(0, 0, 0, 0)
	var promo: bool = row != null and bool(row["promoted"])
	if promo:
		sb.bg_color = Color(0.42, 0.31, 0.1, 0.75)
		sb.border_color = UiTheme.GOLD
		sb.set_border_width_all(1)
	elif row != null and int(row["index"]) % 2 == 1:
		sb.bg_color = Color(1, 1, 1, 0.04)
	holder.add_theme_stylebox_override("panel", sb)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 4)
	holder.add_child(line)
	for key in COLS:
		if not is_campaign() and (key == "healed" or key == "xp"):
			continue
		var c := col
		if row != null:
			if key == "dead" and int(row["dead"]) > 0:
				c = BAD if col != BAD else col
			elif key == "healed" and int(row["healed"]) > 0:
				c = GOOD
			elif key == "xp" and promo:
				c = UiTheme.GOLD
			elif key == "kills" and int(row["kills"]) > 0:
				c = Color(1, 0.9, 0.7)
		var l := UiTheme.label(str(cells.get(key, "")), size, c)
		l.custom_minimum_size.x = COLS[key]
		l.clip_text = true
		if key != "name" and key != "xp":
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		line.add_child(l)
	if promo:
		holder.name = "Promotion%d" % int(row["index"]) # Repérable par les tests
	return holder


## Totaux : pertes des deux camps ; en campagne, or, réputation et renommée.
func build_totals(box: VBoxContainer) -> void:
	var t: Dictionary = report["totals"]
	var mine := "Votre compagnie : %d → %d hommes" % [int(t["player_before"]), int(t["player_after"])]
	var det: Array[String] = ["%d morts" % int(t["player_dead"])]
	if int(t["player_fled"]) > 0:
		det.append("%d fuyards revenus" % int(t["player_fled"]))
	if int(t["player_healed"]) > 0:
		det.append("%d blessés relevés" % int(t["player_healed"]))
	box.add_child(UiTheme.label(mine + "  (" + ", ".join(det) + ")", 15, UiTheme.TEXT))
	var foe := "Ennemis : %d hommes, %d tombés" % [int(t["enemy_before"]), int(t["enemy_dead"])]
	if int(t["enemy_fled"]) > 0:
		foe += ", %d en fuite" % int(t["enemy_fled"])
	if int(t["enemy_standing"]) > 0:
		foe += ", %d encore debout" % int(t["enemy_standing"])
	box.add_child(UiTheme.label(foe, 15, UiTheme.TEXT))
	if not is_campaign():
		return
	var c: Dictionary = report["campaign"]
	var money: Array[String] = []
	if bool(c["victory"]):
		if not bool(c["ambush"]):
			money.append("Prime %d écus" % int(c["reward"]))
		money.append("Butin %d écus" % int(c["loot"]))
		if int(c.get("bonus", 0)) > 0:
			money.append("%s %d écus" % [str(c.get("bonus_label", "Prime d'objectif")), int(c["bonus"])])

	elif int(c["pillage"]) > 0:
		money.append(("Bagages abandonnés -%d écus" if bool(c["retreat"]) else "Bagages pillés -%d écus") % int(c["pillage"]))
	if float(c["wage"]) > 0.0:
		money.append("Solde du jour -%d écus" % int(round(float(c["wage"]))))
	if int(c["deserted"]) > 0:
		money.append("%d déserteurs (solde impayée)" % int(c["deserted"]))
	var gold_line := "Or : %d → %d écus" % [int(c["gold_before"]), int(c["gold_after"])]
	if not money.is_empty():
		gold_line += "   (" + ", ".join(money) + ")"
	var up := float(c["gold_after"]) >= float(c["gold_before"])
	box.add_child(UiTheme.label(gold_line, 15, GOOD if up else BAD))
	var rep: Array[String] = []
	var r0: Array = c["reputation_before"]
	var r1: Array = c["reputation_after"]
	for f in r1.size():
		var d := int(r1[f]) - int(r0[f])
		if d != 0:
			rep.append("%s %+d" % [str(CampaignState.FACTIONS[f]["short"]).capitalize(), d])
	var fame_line := "Renommée : %d → %d" % [int(c["fame_before"]), int(c["fame_after"])]
	if not rep.is_empty():
		fame_line = "Réputation : " + ", ".join(rep) + "   ·   " + fame_line
	box.add_child(UiTheme.label(fame_line, 15, UiTheme.TEXT))


# ---------------------------------------------------------------- Statistiques

## Onglets « Régiments » / « Statistiques » (seulement s'il y a des relevés).
func build_tabs(box: VBoxContainer) -> void:
	if not has_stats():
		return
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	for i in 2:
		var b := Button.new()
		b.text = ["Régiments", "Statistiques"][i]
		b.name = ["OngletRegiments", "OngletStatistiques"][i]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(show_page.bind(i))
		row.add_child(b)
		tab_buttons.append(b)
	tab_buttons[0].button_pressed = true


func has_stats() -> bool:
	var st: Dictionary = report.get("stats", {})
	return not (st.get("samples", []) as Array).is_empty()


## Affiche le tableau (0) ou les statistiques (1).
func show_page(i: int) -> void:
	if stats_box == null:
		return
	table_box.visible = i == 0
	stats_box.visible = i == 1
	for k in tab_buttons.size():
		tab_buttons[k].set_pressed_no_signal(k == i)
	place_panel.call_deferred()


## Page des statistiques : carte de chaleur des pertes, effectifs dans le temps, tués par régiment.
func build_stats(box: VBoxContainer) -> Control:
	if not has_stats():
		return null
	var st: Dictionary = report["stats"]
	var row := HBoxContainer.new()
	row.name = "Statistiques"
	row.add_theme_constant_override("separation", 18)
	row.visible = false
	box.add_child(row)
	var deaths: Array = st["deaths"]
	var items := [
		["Où sont tombés les hommes", StatChart.new("heat", st, battle)],
		["Effectifs debout", StatChart.new("strength", st, battle)],
		["Ennemis tués par régiment", StatChart.new("kills", st, battle)],
	]
	for it in items:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		col.add_child(UiTheme.label(it[0], 14, UiTheme.GOLD))
		var chart: StatChart = it[1]
		chart.name = "Graphique_" + chart.kind
		col.add_child(chart)
		var legend := ""
		match chart.kind:
			"heat":
				legend = "Bleu : vos %d morts · rouge : %d ennemis" % [(deaths[0] as Array).size(), (deaths[1] as Array).size()]
			"strength":
				legend = "Bleu : vous · rouge : l'ennemi (fuyards exclus)"
			"kills":
				legend = "Bleu : vos régiments · rouge : l'ennemi"
		col.add_child(UiTheme.label(legend, 12, UiTheme.DIM))
		row.add_child(col)
	return row


## Un graphique du bilan, dessiné à la main.
class StatChart extends Control:
	const BLUE := Color(0.4, 0.6, 1.0)
	const RED := Color(1.0, 0.4, 0.35)
	var kind := ""
	var st: Dictionary
	var battle: Battle
	var font: Font

	func _init(k: String, stats: Dictionary, b: Battle) -> void:
		kind = k
		st = stats
		battle = b
		font = ThemeDB.fallback_font
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		match kind:
			"heat":
				custom_minimum_size = Vector2(272, 170)
			"strength":
				custom_minimum_size = Vector2(290, 170)
			"kills":
				custom_minimum_size = Vector2(250, maxf(170.0, kill_rows().size() * 17.0 + 8.0))

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.03, 0.02, 0.8))
		match kind:
			"heat":
				draw_heat()
			"strength":
				draw_strength()
			"kills":
				draw_kills()
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.45, 0.37, 0.22), false, 1.0)

	func txt(p: Vector2, s: String, sz: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
		draw_string(font, p, s, align, w, sz, col)

	## Carte de chaleur : le champ en réduction, une case teintée par lieu de mort.
	func draw_heat() -> void:
		var r := Rect2(Vector2(4, 4), size - Vector2(8, 8))
		var rd: BattleRenderer = battle.renderer if is_instance_valid(battle) else null
		if rd != null and rd.ground_tex != null:
			draw_texture_rect(rd.ground_tex, r, false, Color(0.45, 0.45, 0.42))
			if rd.terrain_tex != null:
				draw_texture_rect(rd.terrain_tex, r, false, Color(0.45, 0.45, 0.42))
		else:
			draw_rect(r, Color(0.2, 0.26, 0.16))
		var cell := r.size / Vector2(BattleRecorder.HEAT_COLS, BattleRecorder.HEAT_ROWS)
		var deaths: Array = st["deaths"]
		var maxv := 1
		var maps: Array[PackedInt32Array] = []
		for team in 2:
			var h := BattleRecorder.heat_of(deaths[team])
			maps.append(h)
			for v in h:
				maxv = maxi(maxv, v)
		for team in 2:
			var h := maps[team]
			var col := BLUE if team == 0 else RED
			for i in h.size():
				if h[i] <= 0:
					continue
				var x := i % BattleRecorder.HEAT_COLS
				@warning_ignore("integer_division")
				var y := i / BattleRecorder.HEAT_COLS
				var k := sqrt(float(h[i]) / maxv)
				draw_rect(Rect2(r.position + Vector2(x, y) * cell, cell), Color(col.r, col.g, col.b, 0.25 + 0.7 * k))

	## Effectifs debout des deux camps dans le temps.
	func draw_strength() -> void:
		var samples: Array = st["samples"]
		var plot := Rect2(Vector2(34, 8), size - Vector2(42, 28))
		var t_end := maxf(float(samples[-1][0]), 1.0)
		var maxv := 1
		for s in samples:
			maxv = maxi(maxv, maxi(int(s[1]), int(s[2])))
		# Graduations : 0, moitié, maximum
		for k in 3:
			var y := plot.end.y - plot.size.y * k * 0.5
			draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), Color(1, 1, 1, 0.08 if k > 0 else 0.3), 1.0)
			txt(Vector2(2, y + 4), str(roundi(maxv * k * 0.5)), 10, UiTheme.DIM, HORIZONTAL_ALIGNMENT_RIGHT, 28)
		draw_line(plot.position, Vector2(plot.position.x, plot.end.y), Color(1, 1, 1, 0.3), 1.0)
		txt(Vector2(plot.position.x, size.y - 5), "0 s", 10, UiTheme.DIM)
		txt(Vector2(plot.end.x - 90, size.y - 5), BattleReport.duration_text(t_end), 10, UiTheme.DIM, HORIZONTAL_ALIGNMENT_RIGHT, 90)
		for team in 2:
			var pts := PackedVector2Array()
			for s in samples:
				pts.append(plot.position + Vector2(plot.size.x * float(s[0]) / t_end, plot.size.y * (1.0 - float(s[1 + team]) / maxv)))
			if pts.size() == 1:
				pts.append(pts[0] + Vector2(plot.size.x, 0))
			draw_polyline(pts, BLUE if team == 0 else RED, 2.0, true)

	## Lignes du graphique des tués : régiments du joueur (ordre des cartes), puis les ennemis
	## qui ont tué (les plus meurtriers d'abord, au plus 5).
	func kill_rows() -> Array:
		var mine: Array = []
		var foes: Array = []
		for k in st.get("kills", []):
			if int(k["team"]) == 0:
				mine.append(k)
			elif int(k["kills"]) > 0:
				foes.append(k)
		mine.sort_custom(func(a, b): return int(a["index"]) < int(b["index"]))
		foes.sort_custom(func(a, b): return int(a["kills"]) > int(b["kills"]))
		return mine + foes.slice(0, 5)

	func draw_kills() -> void:
		var rows := kill_rows()
		var maxv := 1
		for k in rows:
			maxv = maxi(maxv, int(k["kills"]))
		var label_w := 118.0
		var bar_w := size.x - label_w - 34.0
		for i in rows.size():
			var k: Dictionary = rows[i]
			var y := 6.0 + i * 17.0
			var mine := int(k["team"]) == 0
			var title := str(k["name"])
			if mine and int(k["index"]) >= 0:
				title = "%d %s" % [int(k["index"]) + 1, title]
			txt(Vector2(6, y + 11), title, 11, UiTheme.TEXT if mine else Color(1, 0.75, 0.7), HORIZONTAL_ALIGNMENT_LEFT, label_w - 8)
			var w := bar_w * int(k["kills"]) / maxv
			draw_rect(Rect2(label_w, y + 2, maxf(w, 1.0), 11), BLUE if mine else RED)
			txt(Vector2(label_w + w + 4, y + 11), str(k["kills"]), 11, UiTheme.TEXT)


func build_buttons(box: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	var labels: Array[String] = []
	if is_campaign():
		labels = ["Retour à la carte  (Entrée)"]
	elif bool(report["tutorial"]):
		labels = ["Recommencer le tutoriel  (Entrée)", "Menu principal  (Échap)"]
	else:
		labels = ["Rejouer  (Entrée)", "Menu principal  (Échap)"]
	for i in labels.size():
		var b := Button.new()
		b.text = labels[i]
		# Pas de focus : Espace (pause) ne doit pas « cliquer » le bouton par mégarde
		b.focus_mode = Control.FOCUS_NONE
		if i == 0:
			b.pressed.connect(func(): battle.continue_after_battle())
		else:
			b.pressed.connect(func(): battle.back_to_menu())
		row.add_child(b)
		buttons.append(b)
