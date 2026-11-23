class_name Hud
extends Control
## Interface : forces en présence, cartes des régiments, messages, aide, info-bulle de survol,
## mini-carte (minimap.gd), sous-titres des évènements sonores et pluie.
##
## Tout se place d'après la taille visible de la vue (get_viewport_rect), qui dépend de la fenêtre
## et de la taille de l'interface : à 150 % dans une fenêtre 1280×720, la vue ne fait que 853×480,
## et les cartes, la barre du haut et l'aide se resserrent (card_rects, help_layout).
## Les numéros des cartes suivent battle.player_roster() : fixes pendant toute la bataille.

const BAR_H := 32.0 ## Hauteur de la barre du haut
const CARD_H := 56.0
const CARD_GAP := 5.0
const CARD_MAX_W := 116.0
const CARD_MIN_W := 72.0
const TAB_H := 18.0 ## Onglet qui cache ou montre les cartes
const MSG_SIZE := 15
const OBJ_H := 46.0 ## Hauteur du panneau d'objectif (sous la barre du haut)
const HELP_SIZE := 13
const CAPTION_LIFE := 3.5 ## Durée d'un sous-titre (secondes)
const CAPTION_COOLDOWN := 6.0 ## Délai avant de répéter le même sous-titre
## Sous-titres des évènements sonores (option d'accessibilité).
const CAPTIONS := {
	"charge": "[Cor : la charge sonne]",
	"retreat": "[Cor : la retraite sonne]",
	"victory": "[Fanfare de victoire]",
	"defeat": "[Tambours de la défaite]",
	"ambush": "[Cris de guerre : embuscade !]",
	"cavalry": "[Galop et fracas : charge de cavalerie]",
	"rout": "[Clameur : des hommes fuient]",
}
const PLAYER_COL := Color(0.22, 0.38, 0.85)
const ENEMY_COL := Color(0.78, 0.16, 0.14)

var battle: Battle ## Bataille affichée (battle.gd ou tutorial.gd)
var font: Font
var drops: Array[Vector2] = []
var hovered: Regiment = null ## Régiment sous la souris (info-bulle)
var captions: Array = [] ## Sous-titres affichés : [texte, temps restant]
var caption_clock := {} ## Sorte de sous-titre -> instant (ms) du dernier affichage
var last_state := -1 ## État de la bataille vu à l'image précédente (sous-titres des cors)


func _ready() -> void:
	font = hud_font()


## Police du HUD : la police par défaut, un peu épaissie pour rester lisible sur l'herbe.
static func hud_font() -> Font:
	var f := FontVariation.new()
	f.base_font = ThemeDB.fallback_font
	f.variation_embolden = 0.45
	f.spacing_glyph = 1
	return f


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
	watch_state()
	for c in captions:
		c[1] -= delta
	captions = captions.filter(func(c): return c[1] > 0.0)
	hovered = find_hovered(get_viewport().get_mouse_position(), vs)


# ---------------------------------------------------------------- Sous-titres

## Cors et fanfares suivent l'état de la bataille (comme battle_audio.gd).
func watch_state() -> void:
	var st := int(battle.state)
	if st == last_state:
		return
	var first := last_state < 0
	last_state = st
	if first:
		return
	match st:
		Battle.State.BATTLE:
			caption("charge")
		Battle.State.VICTORY:
			caption("victory")
		Battle.State.DEFEAT:
			caption("retreat" if battle.retreated else "defeat")


## Affiche le sous-titre d'un évènement sonore (si l'option est active), sans le répéter trop souvent.
func caption(kind: String) -> void:
	if not GameOptions.subtitles or not CAPTIONS.has(kind):
		return
	var now := Time.get_ticks_msec()
	if caption_clock.has(kind) and now - int(caption_clock[kind]) < CAPTION_COOLDOWN * 1000.0:
		return
	caption_clock[kind] = now
	captions.append([CAPTIONS[kind], CAPTION_LIFE])
	if captions.size() > 3:
		captions.pop_front()


# ---------------------------------------------------------------- Mise en page

## Cadres des cartes de régiment (une par régiment du roster), centrés en bas de la vue.
## Les cartes rétrécissent quand la vue est étroite (interface agrandie, petite fenêtre).
static func card_rects(vs: Vector2, n: int) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if n <= 0:
		return out
	var cw := clampf((vs.x - 16.0) / n - CARD_GAP, CARD_MIN_W, CARD_MAX_W)
	var total := n * (cw + CARD_GAP) - CARD_GAP
	var x0 := maxf((vs.x - total) * 0.5, 4.0)
	for i in n:
		out.append(Rect2(x0 + i * (cw + CARD_GAP), vs.y - CARD_H - 6.0, cw, CARD_H))
	return out


## Aide F1 : cadre et taille de police, pour tenir entre la barre du haut et les cartes.
## Repliée : un simple onglet « F1 : aide ».
func help_layout(vs: Vector2, lines: Array[String]) -> Dictionary:
	var top := BAR_H + 8.0
	var avail_h := vs.y - top - cards_height() - 20.0
	var size := HELP_SIZE
	var lh := size + 5.0
	if lines.size() * lh + 14.0 > avail_h:
		lh = maxf((avail_h - 14.0) / lines.size(), 12.0)
		size = clampi(int(lh) - 4, 9, HELP_SIZE)
	var w := 0.0
	for l in lines:
		w = maxf(w, font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
	w = minf(w + 22.0, vs.x * 0.55)
	return {"rect": Rect2(vs.x - w - 10.0, top, w, lines.size() * lh + 14.0), "size": size, "lh": lh}


## Raccourcit s au besoin (« … ») pour tenir dans la largeur w.
func fit(s: String, size: int, w: float) -> String:
	if font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= w:
		return s
	while s.length() > 1 and font.get_string_size(s + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > w:
		s = s.substr(0, s.length() - 1)
	return s + "…"


func text_width(s: String, size: int) -> float:
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


func text(pos: Vector2, s: String, fsize: int = 14, col: Color = Color.WHITE, align := HORIZONTAL_ALIGNMENT_LEFT, w: float = -1) -> void:
	draw_string_outline(font, pos, s, align, w, fsize, 3, Color(0, 0, 0, 0.75 * col.a))
	draw_string(font, pos, s, align, w, fsize, col)


# ---------------------------------------------------------------- Survol

## Régiment sous la souris (ami, ou ennemi visible), sauf au-dessus de l'interface.
func find_hovered(mouse: Vector2, vs: Vector2) -> Regiment:
	if battle.menu_open() or (battle.report_panel != null and battle.report_panel.visible):
		return null
	if mouse.y < BAR_H or not Rect2(Vector2.ZERO, vs).has_point(mouse):
		return null
	if cards_tab_rect(vs).has_point(mouse) or Minimap.rect(self, vs).grow(3.0).has_point(mouse):
		return null
	if battle.show_cards:
		for rect in card_rects(vs, battle.player_roster().size()):
			if rect.grow(4.0).has_point(mouse):
				return null
	var wp := battle.get_canvas_transform().affine_inverse() * mouse
	var r := battle.sim.regiment_at(wp, Battle.PLAYER)
	if r == null:
		r = battle.sim.regiment_at(wp, Battle.ENEMY)
	return r


## Morale en mots (info-bulle).
static func morale_word(r: Regiment) -> String:
	if r.routing:
		return "en déroute"
	var k := r.morale / maxf(r.max_morale, 1.0)
	if k >= 0.7:
		return "ferme"
	if k >= 0.4:
		return "ébranlé"
	return "vacillant"


## Lignes de l'info-bulle d'un régiment : type, effectif, moral, endurance, rang.
func tooltip_lines(r: Regiment) -> Array[String]:
	var head := r.display_name()
	if r.allied:
		head += " (allié)"
	elif r.team == Battle.PLAYER:
		var n: int = battle.orders.roster_number(r)
		head = ("%d  " % n if n > 0 else "") + head + " (vous)"
	else:
		head += " (ennemi)"
	var lines: Array[String] = [head]
	lines.append("Effectif : %d / %d" % [r.alive_n, r.soldiers.size()])
	lines.append("Moral : %d %% (%s)" % [roundi(100.0 * clampf(r.morale / maxf(r.max_morale, 1.0), 0.0, 1.0)), morale_word(r)])
	lines.append("Endurance : %d %% (%s)" % [roundi(100.0 * clampf(r.stamina, 0.0, 1.0)), r.stamina_label()])
	lines.append("Rang : %s" % Regiment.RANK_NAMES[r.rank])
	lines.append("Formation : %s" % r.formation_name())
	if r.is_resting(battle.sim.battle_time):
		lines.append("Relevé : il souffle derrière la ligne")
	elif r.contact_time > 10.0:
		lines.append("Usure au contact : fatigue x%.1f" % battle.sim.wear_factor(r))
	return lines


func draw_tooltip(r: Regiment, mouse: Vector2, vs: Vector2) -> void:
	var lines := tooltip_lines(r)
	var w := 0.0
	for l in lines:
		w = maxf(w, text_width(l, 13))
	var size := Vector2(w + 20.0 + (14.0 if GameOptions.team_shapes else 0.0), lines.size() * 17.0 + 10.0)
	var p := mouse + Vector2(18, 18)
	if p.x + size.x > vs.x - 4.0:
		p.x = mouse.x - size.x - 10.0
	if p.y + size.y > vs.y - 4.0:
		p.y = mouse.y - size.y - 10.0
	var box := Rect2(p.max(Vector2(4, BAR_H + 2)), size)
	var col := PLAYER_COL if r.team == Battle.PLAYER else ENEMY_COL
	draw_rect(box, Color(0.06, 0.05, 0.04, 0.9))
	draw_rect(box, col.lightened(0.25), false, 2.0)
	var x := box.position.x + 10.0
	if GameOptions.team_shapes:
		draw_team_shape(self, r.team, box.position + Vector2(14, 13), 5.0)
		x += 14.0
	for i in lines.size():
		var c := Color(1, 0.9, 0.6) if i == 0 else Color(0.92, 0.9, 0.84)
		text(Vector2(x, box.position.y + 19.0 + i * 17.0), lines[i], 13, c)


## Forme de camp (option d'accessibilité) : rond pour le joueur, losange pour l'ennemi.
## Partagée avec le rendu des étendards (battle_renderer.gd).
static func draw_team_shape(ci: CanvasItem, team: int, at: Vector2, r: float, outline := true) -> void:
	var col := PLAYER_COL.lightened(0.3) if team == Battle.PLAYER else ENEMY_COL.lightened(0.3)
	if team == Battle.PLAYER:
		if outline:
			ci.draw_circle(at, r + 1.0, Color(0, 0, 0, 0.85))
		ci.draw_circle(at, r, col)
		ci.draw_circle(at, r * 0.45, Color(1, 1, 1, 0.9))
	else:
		var pts := PackedVector2Array([at + Vector2(0, -r - 1), at + Vector2(r + 1, 0), at + Vector2(0, r + 1), at + Vector2(-r - 1, 0)])
		if outline:
			ci.draw_colored_polygon(pts, Color(0, 0, 0, 0.85))
		var inner := PackedVector2Array([at + Vector2(0, -r), at + Vector2(r, 0), at + Vector2(0, r), at + Vector2(-r, 0)])
		ci.draw_colored_polygon(inner, col)
		ci.draw_line(at + Vector2(-r * 0.45, -r * 0.45), at + Vector2(r * 0.45, r * 0.45), Color(1, 1, 1, 0.9), 1.0)
		ci.draw_line(at + Vector2(r * 0.45, -r * 0.45), at + Vector2(-r * 0.45, r * 0.45), Color(1, 1, 1, 0.9), 1.0)


# ---------------------------------------------------------------- Dessin

func _draw() -> void:
	var vs := get_viewport_rect().size

	if battle.raining:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0.1, 0.12, 0.22, 0.2))
		for d in drops:
			draw_line(d, d + Vector2(-2, 10), Color(0.75, 0.8, 0.95, 0.35), 1.0)
	if battle.sim.fog:
		draw_fog(vs)

	draw_top_bar(vs)
	draw_cards(vs)

	# Le bilan de fin de bataille masque messages, aide et info-bulle (il les résume)
	var report_shown: bool = battle.report_panel != null and battle.report_panel.visible
	if not report_shown:
		draw_objective(vs)
		var mm := Minimap.rect(self, vs)
		if mm.has_area():
			Minimap.draw(self, mm)
		draw_messages()
		draw_help(vs)
		draw_captions(vs)
		if hovered != null and not hovered.is_dead():
			draw_tooltip(hovered, get_viewport().get_mouse_position(), vs)

	# Grand texte central
	var title := ""
	var sub := ""
	match battle.state:
		Battle.State.DEPLOY:
			title = "DÉPLOIEMENT"
			sub = "Placez vos troupes dans la zone bleue, puis appuyez sur Espace"
		Battle.State.VICTORY:
			title = "VICTOIRE"
			sub = end_hint()
		Battle.State.DEFEAT:
			title = "RETRAITE" if battle.retreated else "DÉFAITE"
			sub = end_hint()
	if battle.paused and battle.state == Battle.State.BATTLE:
		title = "PAUSE"
		sub = "Espace pour reprendre"
	if report_shown:
		title = "" # Le panneau du bilan (battle_report.gd) prend le relais
	if title != "":
		var ts := UiTheme.title_size(vs, 42, title.length() + 4)
		text(Vector2(0, vs.y * 0.3), title, ts, Color(1, 0.88, 0.55), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
		var ss := clampi(int(vs.x / maxf(sub.length() * 0.6, 1.0)), 12, 17)
		text(Vector2(0, vs.y * 0.3 + 32), sub, ss, Color(1, 1, 1, 0.9), HORIZONTAL_ALIGNMENT_CENTER, vs.x)


## Barre du haut : nom, difficulté, rapport de forces au centre, météo, terrain et vitesse à droite.
## Les éléments de côté qui ne tiennent pas (vue étroite) sont omis.
func draw_top_bar(vs: Vector2) -> void:
	draw_rect(Rect2(0, 0, vs.x, BAR_H), Color(0.05, 0.04, 0.03, 0.8))
	var p: int = battle.team_strength(0)
	var e: int = battle.team_strength(1)
	var total := float(maxi(p + e, 1))
	var bw := clampf(vs.x * 0.3, 140.0, 400.0)
	var bar := Rect2(vs.x * 0.5 - bw * 0.5, 10, bw, 12)
	draw_rect(bar, Color(0, 0, 0, 0.6))
	var pw := bar.size.x * p / total
	draw_rect(Rect2(bar.position, Vector2(pw, bar.size.y)), PLAYER_COL)
	var er := Rect2(bar.position + Vector2(pw, 0), Vector2(bar.size.x - pw, bar.size.y))
	draw_rect(er, ENEMY_COL)
	if GameOptions.team_shapes:
		# Motif rayé sur la part ennemie : lisible sans distinguer le rouge du bleu
		var x := er.position.x + 3.0
		while x < er.end.x:
			draw_line(Vector2(x, er.end.y), Vector2(minf(x + 6.0, er.end.x), er.position.y), Color(1, 1, 1, 0.45), 2.0)
			x += 7.0
	var ps := str(p)
	var left_x := bar.position.x - 10.0 - text_width(ps, 15)
	var right_x := bar.end.x + 10.0
	if GameOptions.team_shapes:
		draw_team_shape(self, Battle.PLAYER, Vector2(left_x - 10.0, 16), 5.0)
		draw_team_shape(self, Battle.ENEMY, Vector2(right_x + 5.0, 16), 5.0)
		right_x += 14.0
	text(Vector2(left_x, 22), ps, 15, Color(0.6, 0.75, 1))
	text(Vector2(right_x, 22), str(e), 15, Color(1, 0.6, 0.55))
	var right_free := right_x + text_width(str(e), 15) + 16.0
	var left_free := left_x - (24.0 if GameOptions.team_shapes else 10.0)

	# Côté gauche : nom de la compagnie puis difficulté, s'il y a la place
	var x := 12.0
	for item in [["COMPAGNIE FRANCHE", 16, Color(1, 0.86, 0.5)], [Difficulty.display_name(battle.difficulty), 14, Color(0.85, 0.85, 0.85)]]:
		var w := text_width(item[0], item[1])
		if x + w > left_free:
			break
		text(Vector2(x, 22), item[0], item[1], item[2])
		x += w + 18.0

	# Côté droit, depuis le bord : météo, terrain, vitesse
	var items: Array = []
	var weather := BattleWeather.label(battle.sim)
	if battle.campaign == null: # En campagne, la météo du jour ne se change pas (pas de touche)
		weather += "  [%s]" % GameOptions.key_label("rain")
	items.append([weather, Color(0.85, 0.85, 0.85)])
	items.append(["Terrain : " + battle.terrain.display_name(), Color(0.85, 0.85, 0.85)])
	if battle.sim.siege != null and battle.sim.objective.shows_panel(): # Sinon : panneau de siège (draw_siege)
		items.push_front([battle.sim.siege.status_text(battle.sim), Color(1, 0.85, 0.45)])
	if battle.game_speed != 1.0:
		items.append(["Vitesse " + GameOptions.speed_label(battle.game_speed), Color(1, 0.85, 0.45)])
	var rx := vs.x - 12.0
	for it in items:
		var w := text_width(it[0], 14)
		if rx - w < right_free:
			break
		text(Vector2(rx - w, 22), it[0], 14, it[1])
		rx -= w + 18.0


## Hauteur prise en bas de la vue par les cartes (ou leur seul onglet quand elles sont cachées).
func cards_height() -> float:
	return (CARD_H + 6.0 + TAB_H + 10.0) if battle.show_cards else (TAB_H + 6.0)


## Onglet cliquable « Tab : cacher » au-dessus de la première carte, ou « Tab : cartes » en bas
## au centre quand elles sont cachées.
func cards_tab_rect(vs: Vector2) -> Rect2:
	var label := cards_tab_text()
	var w := text_width(label, 11) + 14.0
	if not battle.show_cards:
		return Rect2(roundf((vs.x - w) * 0.5), vs.y - TAB_H - 6.0, w, TAB_H)
	var rects := card_rects(vs, battle.player_roster().size())
	var x := rects[0].position.x if not rects.is_empty() else (vs.x - w) * 0.5
	var y := (rects[0].position.y if not rects.is_empty() else vs.y - CARD_H - 6.0) - TAB_H - 2.0 - 8.0
	return Rect2(x, y, w, TAB_H)


func cards_tab_text() -> String:
	var key := GameOptions.key_label("cards")
	if battle.show_cards:
		return "%s : cacher les cartes" % key
	return "%s : cartes des régiments (%d)" % [key, battle.player_roster().size()]


func draw_cards_tab(vs: Vector2) -> void:
	var r := cards_tab_rect(vs)
	draw_rect(r, Color(0.05, 0.04, 0.03, 0.7))
	draw_rect(r, Color(0.45, 0.4, 0.3), false, 1.0)
	text(r.position + Vector2(7, 13), cards_tab_text(), 11, Color(0.9, 0.88, 0.8))


## Cartes des régiments du joueur, numéros fixes ; mort ou en fuite : carte grisée.
## Compactes : nom, effectif et formation, moral et endurance, état et ordres sur une ligne.
func draw_cards(vs: Vector2) -> void:
	if battle.player_roster().is_empty():
		return
	draw_cards_tab(vs)
	if not battle.show_cards:
		return
	var list: Array[Regiment] = battle.player_roster()
	var rects := card_rects(vs, list.size())
	for i in list.size():
		var r := list[i]
		var rect := rects[i]
		var cw := rect.size.x
		var inner := cw - 10.0
		var out := r.is_dead() or r.routing
		draw_rect(rect, Color(0.08, 0.07, 0.06, 0.82) if not out else Color(0.1, 0.1, 0.1, 0.55))
		var border := Color(1, 0.9, 0.4) if r.selected else Color(0.45, 0.4, 0.3)
		if out:
			border = Color(0.3, 0.3, 0.3)
		draw_rect(rect, border, false, 2.0 if r.selected else 1.0)
		var o := rect.position
		var name_col := Color(1, 1, 1) if not out else Color(0.55, 0.55, 0.55)
		var title := "%d  %s" % [i + 1, r.display_name()]
		var ns := 12 if text_width(title, 12) <= inner else 11
		text(o + Vector2(5, 14), fit(title, ns, inner), ns, name_col)
		if out:
			var why := "anéanti" if r.is_dead() else "en fuite"
			text(o + Vector2(5, 30), fit("%s · %d" % [why, r.alive_n] if not r.is_dead() else why, 11, inner), 11, Color(0.9, 0.5, 0.4, 0.85))
			continue
		var count: int = r.stats["count"]
		var men := "%d / %d" % [r.alive_n, count]
		text(o + Vector2(5, 28), men, 11, Color(0.82, 0.82, 0.76))
		var mx := 5.0 + text_width(men, 11) + 6.0
		var hid_w := text_width("caché", 10) if r.hidden else 0.0
		if r.formation != Regiment.Formation.LINE:
			text(o + Vector2(mx, 28), fit(r.formation_name(), 11, cw - mx - hid_w - 8.0), 11, Color(1, 0.85, 0.45))
		if r.hidden:
			text(o + Vector2(cw - 5.0 - hid_w, 28), "caché", 10, Color(0.4, 1, 0.5))
		# Moral (rouge → vert) puis endurance (jaune)
		var k := clampf(r.morale / r.max_morale, 0.0, 1.0)
		draw_rect(Rect2(o + Vector2(5, 32), Vector2(inner, 3)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(o + Vector2(5, 32), Vector2(inner * k, 3)), Color(1, 0.2, 0.15).lerp(Color(0.3, 1, 0.3), k))
		var st := clampf(r.stamina, 0.0, 1.0)
		draw_rect(Rect2(o + Vector2(5, 36), Vector2(inner, 2)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(o + Vector2(5, 36), Vector2(inner * st, 2)), Color(0.55, 0.45, 0.2).lerp(Color(1, 0.85, 0.3), st))
		# Dernière ligne : ordres permanents s'il y en a, sinon l'état (fatigue, course) ; groupe à droite
		var orders: Array[String] = []
		if r.hold_position:
			orders.append("tient")
		if r.stats["ranged"] and not r.fire_at_will:
			orders.append("tir retenu")
		var line := " · ".join(orders)
		var lcol := Color(0.55, 0.85, 1)
		if line == "":
			line = r.stamina_label()
			lcol = Color(0.78, 0.78, 0.72)
			if st < UnitTypes.STAMINA_TIRED:
				lcol = Color(1, 0.6, 0.3)
			if r.running:
				line += " · course"
				lcol = Color(1, 0.7, 0.25)
		var group := battle.group_label(r)
		var gw := 0.0
		if group != "":
			gw = text_width(group, 10)
			text(o + Vector2(cw - 5.0 - gw, 50), group, 10, Color(0.75, 0.75, 0.7))
		text(o + Vector2(5, 50), fit(line, 10, inner - gw - 4.0), 10, lcol)
		draw_chevrons(self, o + Vector2(cw - 14, -3.0 - 4.0 * r.rank), r.rank) # Badge au-dessus de la carte


## Messages en haut à gauche, chacun sur un fond sombre.
## Rectangle du panneau d'objectif (vide si l'objectif n'en affiche pas : « détruire l'ennemi »).
## Un vrai siège sans autre panneau y montre l'état de la porte (draw_siege).
func objective_rect(vs: Vector2) -> Rect2:
	if not battle.sim.objective.shows_panel() and battle.sim.siege == null:
		return Rect2()
	var w := clampf(vs.x * 0.42, 260.0, 520.0)
	return Rect2(vs.x * 0.5 - w * 0.5, BAR_H + 4.0, w, OBJ_H)


## Panneau d'objectif : nom, état (chronomètre, chariots, fuyards), progression et jauge de danger.
func draw_objective(vs: Vector2) -> void:
	var r := objective_rect(vs)
	if not r.has_area():
		return
	if not battle.sim.objective.shows_panel():
		draw_siege(r)
		return
	var o := battle.sim.objective
	draw_rect(r, Color(0.05, 0.04, 0.03, 0.78))
	draw_rect(r, Color(0.55, 0.47, 0.3), false, 1.0)
	text(r.position + Vector2(8, 16), fit(o.label().to_upper(), 14, r.size.x - 16.0), 14, Color(1, 0.86, 0.5))
	text(r.position + Vector2(8, 32), fit(o.status(battle.sim), 13, r.size.x - 16.0), 13, Color(0.92, 0.9, 0.82))
	var bar := Rect2(r.position.x + 8.0, r.end.y - 10.0, r.size.x - 16.0, 5.0)
	var p := o.progress(battle.sim)
	if p >= 0.0:
		draw_rect(bar, Color(0, 0, 0, 0.6))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * p, bar.size.y)), Color(1, 0.84, 0.4))
	var dg := o.danger(battle.sim)
	if dg > 0.0:
		draw_rect(Rect2(bar.position + Vector2(0, 6), Vector2(bar.size.x * dg, 2.0)), ENEMY_COL.lightened(0.2))


## Panneau de siège : la porte (jauge de solidité, ou enfoncée), le bélier, les échelles dressées,
## l'huile qui reste et la prise de la place.
func draw_siege(r: Rect2) -> void:
	var sg: Siege = battle.sim.siege
	draw_rect(r, Color(0.05, 0.04, 0.03, 0.78))
	draw_rect(r, Color(0.55, 0.47, 0.3), false, 1.0)
	var title := "DÉFENSE DE LA VILLE" if sg.town.defense else "ASSAUT DE LA VILLE"
	text(r.position + Vector2(8, 16), title, 14, Color(1, 0.86, 0.5))
	text(r.position + Vector2(8, 32), fit(sg.status_text(battle.sim), 13, r.size.x - 16.0), 13, Color(0.92, 0.9, 0.82))
	var bar := Rect2(r.position.x + 8.0, r.end.y - 10.0, r.size.x - 16.0, 5.0)
	draw_rect(bar, Color(0, 0, 0, 0.6))
	if sg.town.gate_open:
		draw_rect(bar, Color(0.75, 0.2, 0.15, 0.9)) # Porte enfoncée : jauge rouge pleine
	else:
		var k := clampf(sg.gate_hp / Siege.GATE_HP, 0.0, 1.0)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * k, bar.size.y)), Color(0.6, 0.42, 0.2).lerp(Color(0.85, 0.3, 0.15), 1.0 - k))
	if sg.hold > 0.0:
		var col: Color = PLAYER_COL if sg.attacker == Battle.PLAYER else ENEMY_COL
		draw_rect(Rect2(bar.position + Vector2(0, 6), Vector2(bar.size.x * sg.hold, 2.0)), col.lightened(0.2))


func draw_messages() -> void:
	var vs := get_viewport_rect().size
	var y := BAR_H + 22.0
	var obj := objective_rect(vs)
	if obj.has_area() and obj.position.x < minf(vs.x * 0.6, free_width(vs) - 12.0):
		y += OBJ_H + 8.0 # Sous le panneau d'objectif

	var maxw := minf(vs.x * 0.6, free_width(vs) - 12.0) # Jamais sous l'aide dépliée
	for m in battle.messages:
		var a := clampf(m[1], 0.0, 1.0)
		var s := fit(str(m[0]), MSG_SIZE, maxw - 16.0)
		var w := text_width(s, MSG_SIZE)
		draw_rect(Rect2(8, y - 16, w + 14, 22), Color(0.05, 0.04, 0.03, 0.62 * a))
		text(Vector2(15, y), s, MSG_SIZE, Color(1, 0.95, 0.8, a))
		y += 25.0


## Aide F1 dépliée, ou onglet replié « F1 : aide ».
func draw_help(vs: Vector2) -> void:
	if not battle.show_help:
		var tab := "%s : aide" % GameOptions.key_label("help")
		var w := text_width(tab, 13) + 16.0
		var r := Rect2(vs.x - w - 10.0, BAR_H + 6.0, w, 22)
		draw_rect(r, Color(0.05, 0.04, 0.03, 0.7))
		draw_rect(r, Color(0.45, 0.4, 0.3), false, 1.0)
		text(r.position + Vector2(8, 16), tab, 13, Color(0.9, 0.88, 0.8))
		draw_weather_effects(vs, r.end.y + 18.0)
		return
	var lines := shown_help_lines()
	var lay := help_layout(vs, lines)
	var hr: Rect2 = lay["rect"]
	draw_rect(hr, Color(0.05, 0.04, 0.03, 0.78))
	draw_rect(hr, Color(0.45, 0.4, 0.3), false, 1.0)
	var lh: float = lay["lh"]
	for i in lines.size():
		text(hr.position + Vector2(10, 7 + lh * (i + 1) - 4), fit(lines[i], lay["size"], hr.size.x - 16.0), lay["size"], Color(0.92, 0.9, 0.82))


## Largeur libre à gauche de l'aide dépliée (toute la vue si elle est repliée).
func free_width(vs: Vector2) -> float:
	if not battle.show_help:
		return vs.x
	var hr: Rect2 = help_layout(vs, shown_help_lines())["rect"]
	return hr.position.x


## Lignes de l'aide dépliée : la météo en cours et ses effets, puis l'aide des touches.
func shown_help_lines() -> Array[String]:
	var lines: Array[String] = []
	for e in BattleWeather.effects(battle.sim):
		lines.append("Météo : " + e)
	lines.append_array(help_lines(battle.campaign == null))
	return lines


## Effets de la météo en cours, en petit sous l'onglet d'aide (aide repliée).
func draw_weather_effects(vs: Vector2, y: float) -> void:
	for e in BattleWeather.effects(battle.sim):
		var w := text_width(e, 12)
		draw_rect(Rect2(vs.x - w - 20.0, y - 14.0, w + 12.0, 19.0), Color(0.05, 0.04, 0.03, 0.55))
		text(Vector2(vs.x - w - 14.0, y), e, 12, Color(0.85, 0.9, 1.0))
		y += 21.0


## Brouillard : voile pâle et nappes qui dérivent lentement (purement visuel).
func draw_fog(vs: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.78, 0.8, 0.82, 0.16))
	var t := Time.get_ticks_msec() / 1000.0
	for i in 9:
		var k := float(i)
		var x := fposmod(k * 397.0 + t * (8.0 + k), vs.x + 600.0) - 300.0
		var y := fposmod(k * 233.0, vs.y)
		var rad := 180.0 + 40.0 * sin(k * 1.7)
		draw_circle(Vector2(x, y), rad, Color(0.85, 0.87, 0.9, 0.07))
		draw_circle(Vector2(x + rad * 0.4, y + 20.0), rad * 0.7, Color(0.85, 0.87, 0.9, 0.06))


## Sous-titres au-dessus des cartes, centrés dans la place laissée par l'aide.
func draw_captions(vs: Vector2) -> void:
	var y := vs.y - cards_height() - 22.0
	var fw := free_width(vs)
	var left := 0.0 # Pas sur la mini-carte : centrés dans la place à sa droite
	var mm := Minimap.rect(self, vs)
	if mm.has_area() and mm.end.y > y - 18.0 - 29.0 * (captions.size() - 1):
		left = mm.end.x + 6.0
	for i in range(captions.size() - 1, -1, -1):
		var c: Array = captions[i]
		var a := clampf(float(c[1]), 0.0, 1.0)
		var s := fit(str(c[0]), 16, fw - left - 28.0)
		var w := text_width(s, 16)
		draw_rect(Rect2(left + (fw - left - w) * 0.5 - 10.0, y - 18.0, w + 20.0, 25.0), Color(0, 0, 0, 0.72 * a))
		text(Vector2(left, y), s, 16, Color(1, 1, 0.85, a), HORIZONTAL_ALIGNMENT_CENTER, fw - left)
		y -= 29.0


## Lignes de l'aide (panneau F1 et page Aide du menu pause). Les touches suivent les Options.
## rain_key : faux en campagne, où la météo du jour s'impose (la touche de pluie n'y fait rien).
static func help_lines(rain_key := true) -> Array[String]:
	var lines: Array[String] = [
		"Clic gauche / glisser : sélectionner",
		"Maj + clic : ajouter à la sélection",
		"Clic droit : se déplacer / attaquer",
		"Clic droit glissé : tracer la ligne de front",
		"Double clic droit : courir (fatigue)",
		"Ctrl+A : tout   1-8 : un régiment (numéro fixe)",
		"Ctrl+1-8 : mémoriser un groupe",
		"1-8 : rappeler le groupe (2 fois : y aller)",
		"%s : halte   %s : formation (ligne / colonne / carré)" % [GameOptions.key_label("halt"), GameOptions.key_label("formation")],
		"%s : tenir la position (on / off)" % GameOptions.key_label("hold"),
		"%s : archers, tir à volonté / cesser le tir" % GameOptions.key_label("fire"),
		"%s / flèches / molette (clic) : caméra" % GameOptions.camera_keys_label(),
		"Molette : zoom   Survol : détails d'un régiment",
		("%s : météo (clair, pluie, brouillard, vent)   Espace : lancer / pause" % GameOptions.key_label("rain")) if rain_key else "Météo du jour et du lieu imposée   Espace : lancer / pause",
		"Pluie : arcs courts (arbalètes moins), boue : cavalerie lente",
		"Brouillard : ennemi invisible au loin   Vent : porte les flèches",
		"%s : relever (survoler l'ami qui prend la place) ou se replier" % GameOptions.key_label("relief"),
		"Mêlée longue : on s'use vite ; au repos, on récupère",
		"Déploiement : zone bleue, aucun combat",
		"%s deux fois : sonner la retraite (défaite limitée)" % GameOptions.key_label("retreat"),
		"Clic : capitaine   %s : il rejoint la sélection" % GameOptions.key_label("captain"),
		"%s : couper / remettre le son   %s : vitesse" % [GameOptions.key_label("sound"), GameOptions.key_label("speed")],
		"Alt+Entrée / F11 : plein écran",
		"Échap : menu pause (options, abandon)",
		"%s : cacher / montrer les cartes des régiments" % GameOptions.key_label("cards"),
		"%s : mini-carte (clic dessus : y centrer la vue)" % GameOptions.key_label("minimap"),
		"%s : masquer l'aide" % GameOptions.key_label("help"),
	]
	return lines


## Chevrons de rang (un par rang au-dessus des recrues), pointe en haut, empilés vers le bas.
## Partagé avec le panneau de la carte de campagne.
static func draw_chevrons(ci: CanvasItem, at: Vector2, rank: int, col := Color(1, 0.84, 0.4)) -> void:
	for k in rank:
		var y := at.y + k * 4.0
		var pts := PackedVector2Array([Vector2(at.x, y + 4), Vector2(at.x + 5, y), Vector2(at.x + 10, y + 4)])
		ci.draw_polyline(pts, Color(0, 0, 0, 0.8), 3.0)
		ci.draw_polyline(pts, col, 1.6)


func end_hint() -> String:
	return "Entrée : voir le bilan"
