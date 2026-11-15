class_name Hud
extends Control
## Interface : forces en présence, cartes des régiments, messages, aide et pluie.

var battle ## Référence vers le script de bataille (battle.gd)
var font: Font
var drops: Array[Vector2] = []


func _ready() -> void:
	font = ThemeDB.fallback_font


func _process(delta: float) -> void:
	var vs := get_viewport_rect().size
	if battle.raining:
		if drops.is_empty():
			for i in 260:
				drops.append(Vector2(randf() * vs.x, randf() * vs.y))
		for i in drops.size():
			drops[i] += Vector2(-90, 560) * delta
			if drops[i].y > vs.y:
				drops[i] = Vector2(randf() * (vs.x + 120.0), -10.0)
	else:
		drops.clear()


func text(pos: Vector2, s: String, fsize: int = 14, col: Color = Color.WHITE, align := HORIZONTAL_ALIGNMENT_LEFT, w: float = -1) -> void:
	draw_string(font, pos + Vector2(1, 1), s, align, w, fsize, Color(0, 0, 0, 0.8 * col.a))
	draw_string(font, pos, s, align, w, fsize, col)


func _draw() -> void:
	var vs := get_viewport_rect().size

	if battle.raining:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0.1, 0.12, 0.22, 0.2))
		for d in drops:
			draw_line(d, d + Vector2(-2, 10), Color(0.75, 0.8, 0.95, 0.35), 1.0)

	# Barre du haut : rapport de forces
	draw_rect(Rect2(0, 0, vs.x, 30), Color(0.05, 0.04, 0.03, 0.75))
	text(Vector2(12, 21), "COMPAGNIE FRANCHE", 15, Color(1, 0.86, 0.5))
	text(Vector2(200, 21), Difficulty.display_name(battle.difficulty), 13, Color(0.85, 0.85, 0.85))
	var p: int = battle.team_strength(0)
	var e: int = battle.team_strength(1)
	var total := float(maxi(p + e, 1))
	var bar := Rect2(vs.x * 0.5 - 200, 9, 400, 12)
	draw_rect(bar, Color(0, 0, 0, 0.6))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * p / total, bar.size.y)), Color(0.22, 0.38, 0.85))
	draw_rect(Rect2(bar.position + Vector2(bar.size.x * p / total, 0), Vector2(bar.size.x * e / total, bar.size.y)), Color(0.78, 0.16, 0.14))
	text(Vector2(bar.position.x - 50, 21), str(p), 14, Color(0.6, 0.75, 1))
	text(Vector2(bar.end.x + 10, 21), str(e), 14, Color(1, 0.6, 0.55))
	var weather := "Pluie" if battle.raining else "Temps clair"
	text(Vector2(vs.x - 160, 21), weather + "  [%s]" % GameOptions.key_label("rain"), 13, Color(0.85, 0.85, 0.85))
	text(Vector2(vs.x - 330, 21), "Terrain : " + battle.terrain.display_name(), 13, Color(0.85, 0.85, 0.85))
	if battle.game_speed != 1.0:
		text(Vector2(vs.x - 440, 21), "Vitesse " + GameOptions.speed_label(battle.game_speed), 13, Color(1, 0.85, 0.45))

	# Cartes des régiments du joueur
	var list: Array = battle.player_regiments()
	var cw := 128.0
	var x0 := vs.x * 0.5 - list.size() * (cw + 6) * 0.5
	for i in list.size():
		var r = list[i]
		var rect := Rect2(x0 + i * (cw + 6), vs.y - 86, cw, 78)
		draw_rect(rect, Color(0.08, 0.07, 0.06, 0.82))
		var border := Color(1, 0.9, 0.4) if r.selected else Color(0.45, 0.4, 0.3)
		draw_rect(rect, border, false, 2.0 if r.selected else 1.0)
		text(rect.position + Vector2(6, 16), "%d  %s" % [i + 1, r.display_name()], 13, Color(1, 1, 1))
		var count: int = r.stats["count"]
		if r.formation == Regiment.Formation.LINE:
			text(rect.position + Vector2(6, 32), "%d / %d hommes" % [r.alive_n, count], 12, Color(0.8, 0.8, 0.75))
		else:
			text(rect.position + Vector2(6, 32), "%d / %d" % [r.alive_n, count], 12, Color(0.8, 0.8, 0.75))
			text(rect.position + Vector2(70, 32), r.formation_name(), 12, Color(1, 0.85, 0.45))
		# Moral (rouge → vert) puis endurance (jaune)
		var k := clampf(r.morale / r.max_morale, 0.0, 1.0)
		draw_rect(Rect2(rect.position + Vector2(6, 37), Vector2(cw - 12, 4)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(rect.position + Vector2(6, 37), Vector2((cw - 12) * k, 4)), Color(1, 0.2, 0.15).lerp(Color(0.3, 1, 0.3), k))
		var st := clampf(r.stamina, 0.0, 1.0)
		draw_rect(Rect2(rect.position + Vector2(6, 43), Vector2(cw - 12, 3)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(rect.position + Vector2(6, 43), Vector2((cw - 12) * st, 3)), Color(0.55, 0.45, 0.2).lerp(Color(1, 0.85, 0.3), st))
		var status: String = r.stamina_label()
		var scol := Color(0.75, 0.75, 0.7)
		if st < UnitTypes.STAMINA_TIRED:
			scol = Color(1, 0.6, 0.3)
		if r.running:
			status += " · course"
			scol = Color(1, 0.7, 0.25)
		text(rect.position + Vector2(6, 58), status, 11, scol)
		if r.hidden:
			text(rect.position + Vector2(cw - 40, 58), "caché", 11, Color(0.4, 1, 0.5))
		# Ordres permanents : tenir la position (G), tir retenu (X)
		var orders: Array[String] = []
		if r.hold_position:
			orders.append("tient [G]")
		if r.stats["ranged"] and not r.fire_at_will:
			orders.append("tir retenu [X]")
		var group := battle.group_label(r) as String
		if group != "":
			text(rect.position + Vector2(0, 72), group, 11, Color(0.75, 0.75, 0.7), HORIZONTAL_ALIGNMENT_RIGHT, cw - 6)
		if not orders.is_empty():
			text(rect.position + Vector2(6, 72), " · ".join(orders), 11, Color(0.55, 0.85, 1))
		draw_chevrons(self, rect.position + Vector2(cw - 16, -4.0 - 4.0 * r.rank), r.rank) # Badge au-dessus de la carte

	# Messages
	var y := 52.0
	for m in battle.messages:
		var a := clampf(m[1], 0.0, 1.0)
		text(Vector2(14, y), m[0], 14, Color(1, 0.95, 0.8, a))
		y += 20.0

	# Aide
	if battle.show_help:
		var lines := [
			"Clic gauche / glisser : sélectionner",
			"Maj + clic : ajouter à la sélection",
			"Clic droit : se déplacer / attaquer",
			"Clic droit glissé : tracer la ligne de front",
			"Double clic droit : courir (fatigue)",
			"Ctrl+A : tout   1-8 : un régiment",
			"Ctrl+1-8 : mémoriser un groupe",
			"1-8 : rappeler le groupe (2 fois : y aller)",
			"%s : halte   %s : formation (ligne / colonne / carré)" % [GameOptions.key_label("halt"), GameOptions.key_label("formation")],
			"%s : tenir la position (on / off)" % GameOptions.key_label("hold"),
			"%s : archers, tir à volonté / cesser le tir" % GameOptions.key_label("fire"),
			"ZQSD / flèches / molette (clic) : caméra",
			"Molette : zoom",
			"%s : pluie   Espace : lancer / pause" % GameOptions.key_label("rain"),
			"%s deux fois : sonner la retraite (défaite limitée)" % GameOptions.key_label("retreat"),
			"%s : couper / remettre le son   %s : vitesse" % [GameOptions.key_label("sound"), GameOptions.key_label("speed")],
			"Échap : menu principal (escarmouche)",
			"%s : masquer l'aide" % GameOptions.key_label("help"),
		]
		var hr := Rect2(vs.x - 300, 42, 288, lines.size() * 18 + 14)
		draw_rect(hr, Color(0.05, 0.04, 0.03, 0.7))
		for i in lines.size():
			text(hr.position + Vector2(10, 22 + i * 18), lines[i], 12, Color(0.9, 0.88, 0.8))

	# Grand texte central
	var title := ""
	var sub := ""
	match battle.state:
		0:
			title = "DÉPLOIEMENT"
			sub = "Placez vos troupes dans la zone bleue, puis appuyez sur Espace"
		2:
			title = "VICTOIRE"
			sub = end_hint()
		3:
			title = "RETRAITE" if battle.retreated else "DÉFAITE"
			sub = end_hint()
	if battle.paused and battle.state == 1:
		title = "PAUSE"
		sub = "Espace pour reprendre"
	if title != "":
		text(Vector2(0, vs.y * 0.3), title, 42, Color(1, 0.88, 0.55), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
		text(Vector2(0, vs.y * 0.3 + 32), sub, 16, Color(1, 1, 1, 0.9), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
		if battle.campaign_report != "" and battle.state >= 2:
			text(Vector2(0, vs.y * 0.3 + 58), battle.campaign_report, 14, Color(1, 0.9, 0.65), HORIZONTAL_ALIGNMENT_CENTER, vs.x)


## Chevrons de rang (un par rang au-dessus des recrues), pointe en haut, empilés vers le bas.
## Partagé avec le panneau de la carte de campagne.
static func draw_chevrons(ci: CanvasItem, at: Vector2, rank: int, col := Color(1, 0.84, 0.4)) -> void:
	for k in rank:
		var y := at.y + k * 4.0
		var pts := PackedVector2Array([Vector2(at.x, y + 4), Vector2(at.x + 5, y), Vector2(at.x + 10, y + 4)])
		ci.draw_polyline(pts, Color(0, 0, 0, 0.8), 3.0)
		ci.draw_polyline(pts, col, 1.6)


func end_hint() -> String:
	if battle.campaign != null:
		return "Entrée : retour à la carte de campagne"
	return "Entrée pour rejouer   Échap : menu principal"
