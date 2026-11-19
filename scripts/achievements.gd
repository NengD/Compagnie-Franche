class_name Achievements
extends RefCounted
## Succès : liste, conditions (earned) et notification discrète en jeu (notify).
## Les compteurs sont dans Stats ; « info » décrit l'évènement qui vient d'avoir lieu
## (fin de bataille : voir Stats.record_battle ; fin de campagne : voir Stats.record_campaign_end).

const LIST: Array[Dictionary] = [
	{"id": "premiere_victoire", "name": "Premier sang", "desc": "Gagner une bataille."},
	{"id": "sans_perte_regiment", "name": "Personne ne reste en arrière", "desc": "Gagner une bataille sans perdre un régiment."},
	{"id": "sans_un_mort", "name": "Victoire parfaite", "desc": "Gagner une bataille sans perdre un homme."},
	{"id": "carre", "name": "Le carré tient", "desc": "Un carré repousse une charge de cavalerie."},
	{"id": "embuscade", "name": "Loups des bois", "desc": "Surprendre l'ennemi depuis une forêt et gagner."},
	{"id": "brigands", "name": "Route sûre", "desc": "Repousser une embuscade sur la route."},
	{"id": "siege", "name": "Assaut", "desc": "Gagner une bataille de siège."},
	{"id": "eclair", "name": "Bataille éclair", "desc": "Gagner une bataille en moins de deux minutes."},
	{"id": "un_contre_deux", "name": "Contre toute attente", "desc": "Gagner face à une armée une fois et demie plus nombreuse."},
	{"id": "retraite", "name": "Repli en bon ordre", "desc": "Sonner la retraite."},
	{"id": "elite", "name": "Régiment d'élite", "desc": "Un régiment devient vétéran."},
	{"id": "doyen", "name": "Vieille garde", "desc": "Un régiment survit à 10 batailles."},
	{"id": "escarmouche_difficile", "name": "Fine lame", "desc": "Gagner une escarmouche en difficile."},
	{"id": "tues_100", "name": "Cent têtes", "desc": "100 ennemis tués (toutes parties)."},
	{"id": "tues_1000", "name": "Fléau du comté", "desc": "1 000 ennemis tués (toutes parties)."},
	{"id": "batailles_10", "name": "Routiers", "desc": "Livrer 10 batailles."},
	{"id": "batailles_50", "name": "Vieux briscards", "desc": "Livrer 50 batailles."},
	{"id": "victoires_25", "name": "Habitués de la victoire", "desc": "Gagner 25 batailles."},
	{"id": "riche", "name": "Coffres pleins", "desc": "Gagner 5 000 écus (toutes campagnes)."},
	{"id": "campagne_gagnee", "name": "La guerre est gagnée", "desc": "Gagner une campagne."},
	{"id": "campagne_difficile", "name": "Légende du comté", "desc": "Gagner une campagne en difficile."},
	{"id": "campagne_rapide", "name": "Guerre éclair", "desc": "Gagner une campagne en moins de 60 jours."},
	{"id": "dissous", "name": "Tout se perd", "desc": "Perdre une campagne."},
]


static func find(id: String) -> Dictionary:
	for a in LIST:
		if a["id"] == id:
			return a
	return {}


## Succès mérité ? (compteurs de Stats et évènement « info »)
static func earned(id: String, info: Dictionary) -> bool:
	var win := str(info.get("outcome", "")) == "victory"
	match id:
		"premiere_victoire": return win
		"sans_perte_regiment": return win and int(info.get("regiments_lost", 1)) == 0
		"sans_un_mort": return win and int(info.get("lost", 1)) == 0
		"carre": return bool(info.get("square_repelled", false))
		"embuscade": return win and bool(info.get("ambush_by_player", false))
		"brigands": return win and bool(info.get("road_ambush", false))
		"siege": return win and str(info.get("terrain", "")) in ["siege", "town_assault", "town_defense"]
		"eclair": return win and float(info.get("duration", 999.0)) < 120.0
		"un_contre_deux": return win and int(info.get("enemy_before", 0)) >= 1.5 * maxi(int(info.get("player_before", 1)), 1)
		"retraite": return str(info.get("outcome", "")) == "retreat"
		"elite": return bool(info.get("new_veteran", false))
		"doyen": return int(Stats.data["oldest"].get("battles", 0)) >= 10
		"escarmouche_difficile": return win and not bool(info.get("campaign", true)) and str(info.get("difficulty", "")) == Difficulty.HARD
		"tues_100": return Stats.count("enemies_killed") >= 100
		"tues_1000": return Stats.count("enemies_killed") >= 1000
		"batailles_10": return Stats.count("battles") >= 10
		"batailles_50": return Stats.count("battles") >= 50
		"victoires_25": return Stats.count("victories") >= 25
		"riche": return Stats.count("gold_earned") >= 5000
		"campagne_gagnee": return Stats.count("campaigns_won") >= 1
		"campagne_difficile": return str(info.get("campaign_end", "")) == "victory" and str(info.get("campaign_difficulty", "")) == Difficulty.HARD
		"campagne_rapide": return str(info.get("campaign_end", "")) == "victory" and int(info.get("campaign_days", 999)) < 60
		"dissous": return Stats.count("campaigns_lost") >= 1
	return false


## Débloque les succès mérités ; renvoie les nouveaux.
static func check(info: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for a in LIST:
		var id: String = a["id"]
		if not Stats.is_unlocked(id) and earned(id, info) and Stats.unlock(id):
			out.append(id)
	return out


## Observe une bataille : faits d'armes signalés par la simulation (BattleSim.feat), puis bilan
## enregistré dans Stats une fois le bilan de fin construit. Créé par battle.gd (watch()).
class Watch extends RefCounted:
	var battle: Battle
	var ambush_by_player := false
	var charges: Array = [] ## [cavalerie ennemie, carré du joueur] : charges reçues par un carré
	var square_repelled := false

	func _init(b: Battle) -> void:
		battle = b
		b.sim.feat.connect(_on_feat)
		b.sim.ended.connect(_on_ended)

	func _on_feat(kind: String, by: Regiment, against: Regiment) -> void:
		if kind == "ambush" and by.team == BattleSim.PLAYER:
			ambush_by_player = true
		elif kind == "charge_on_square" and against.team == BattleSim.PLAYER and not [by, against] in charges:
			charges.append([by, against])

	## Fin de bataille : un carré a repoussé une charge si la cavalerie a fui ou péri et que le carré tient.
	func _on_ended() -> void:
		for p in charges:
			var cav: Regiment = p[0]
			var sq: Regiment = p[1]
			if (cav.is_dead() or cav.routing) and not sq.is_dead() and not sq.routing:
				square_repelled = true
		_record.call_deferred() # Après battle._on_battle_ended (bilan et campagne)

	func _record() -> void:
		if not is_instance_valid(battle) or battle.is_tutorial or battle.end_report.is_empty():
			return
		Stats.record_battle(Achievements.battle_info(battle.end_report, self, battle))
		if battle.campaign != null and battle.campaign.is_over():
			Stats.record_campaign_end(battle.campaign)


## Crée l'observateur d'une bataille (une ligne dans battle.gd._ready).
static func watch(b: Battle) -> Watch:
	return Watch.new(b)


## Résumé d'une fin de bataille pour Stats.record_battle, d'après Battle.build_end_report.
static func battle_info(report: Dictionary, w: Watch, b: Battle) -> Dictionary:
	var t: Dictionary = report.get("totals", {})
	var camp: Dictionary = report.get("campaign", {})
	var killed := 0
	var regiments_lost := 0
	var new_veteran := false
	for row in report.get("rows", []):
		killed += int(row.get("kills", 0))
		if int(row.get("after", 0)) <= 0:
			regiments_lost += 1
		if bool(row.get("promoted", false)) and int(row.get("rank_after", 0)) >= 2:
			new_veteran = true
	return {
		"outcome": str(report.get("outcome", "")),
		"campaign": not camp.is_empty(),
		"difficulty": b.sim.difficulty if b != null else "",
		"terrain": b.sim.terrain.kind if b != null else "",
		"duration": float(report.get("duration", 0.0)),
		"killed": killed,
		"lost": int(t.get("player_dead", 0)),
		"gold": int(camp.get("reward", 0)) + int(camp.get("loot", 0)),
		"regiments_lost": regiments_lost,
		"player_before": int(t.get("player_before", 0)),
		"enemy_before": int(t.get("enemy_before", 0)),
		"new_veteran": new_veteran,
		"road_ambush": bool(camp.get("ambush", false)),
		"ambush_by_player": w != null and w.ambush_by_player,
		"square_repelled": w != null and w.square_repelled,
		"regiments": camp.get("regiments", []),
	}


## Régiment de la compagnie qui a la plus grande valeur de `key` ("battles" ou "kills"), ou {}.
static func company_best(company: Array, key: String) -> Dictionary:
	var best := {}
	for r in company:
		if int(r.get(key, 0)) > int(best.get(key, 0)):
			best = r
	if best.is_empty():
		return {}
	return {"type": best["type"], "battles": int(best.get("battles", 0)), "kills": int(best.get("kills", 0)),
		"rank": CampaignState.rank_of(best)}


## « Piquiers vétérans : 12 batailles, 85 ennemis tués » (ou « — »).
static func regiment_text(r: Dictionary) -> String:
	if r.is_empty() or not UnitTypes.STATS.has(str(r.get("type", ""))):
		return "—"
	return "%s %s : %s, %s" % [CampaignState.type_name(str(r["type"])), CampaignState.rank_name(int(r.get("rank", 0))),
		CampaignState.plural(int(r.get("battles", 0)), "bataille", "batailles"),
		CampaignState.plural(int(r.get("kills", 0)), "ennemi tué", "ennemis tués")]


## Lignes des statistiques globales : [intitulé, valeur].
static func stats_rows() -> Array:
	Stats.ensure_loaded()
	return [
		["Batailles livrées", "%d (%d gagnées, %d perdues)" % [Stats.count("battles"), Stats.count("victories"), Stats.count("defeats")]],
		["Ennemis tués", str(Stats.count("enemies_killed"))],
		["Hommes perdus", str(Stats.count("men_lost"))],
		["Or gagné", "%d écus" % Stats.count("gold_earned")],
		["Campagnes gagnées / perdues", "%d / %d" % [Stats.count("campaigns_won"), Stats.count("campaigns_lost")]],
		["Plus longue campagne", CampaignState.plural(Stats.count("longest_campaign"), "jour", "jours")],
		["Régiment le plus ancien", regiment_text(Stats.data["oldest"])],
		["Régiment le plus décoré", regiment_text(Stats.data["decorated"])],
	]


## Page « Statistiques et succès » du menu principal (le menu ajoute le bouton Retour).
static func build_page(box: VBoxContainer) -> void:
	Stats.ensure_loaded()
	box.add_child(UiTheme.label("Statistiques et succès", 24, UiTheme.GOLD))
	var grid := GridContainer.new()
	grid.name = "Statistiques"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	for row in stats_rows():
		grid.add_child(UiTheme.label(str(row[0]), 14, UiTheme.DIM))
		grid.add_child(UiTheme.label(str(row[1]), 14))
	box.add_child(grid)
	var got := 0
	for a in LIST:
		if Stats.is_unlocked(a["id"]):
			got += 1
	box.add_child(HSeparator.new())
	box.add_child(UiTheme.label("Succès : %d / %d" % [got, LIST.size()], 18, UiTheme.GOLD))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 240)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.name = "Succes"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for a in LIST:
		var on := Stats.is_unlocked(a["id"])
		var l := UiTheme.label("%s — %s%s" % [a["name"], a["desc"], "" if on else " (à obtenir)"], 13, UiTheme.GOLD if on else UiTheme.DIM)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 540
		list.add_child(l)
	scroll.add_child(list)
	box.add_child(scroll)


## Notification discrète en haut à droite, sous la barre du haut et l'onglet d'aide de la bataille :
## médaillon, « Succès obtenu » et nom. Posée sur la racine (survit aux changements de scène :
## bataille → carte de campagne) ; plusieurs succès s'empilent.
static func notify(ids: Array[String]) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	for i in ids.size():
		var a := find(ids[i])
		if a.is_empty():
			continue
		var layer := CanvasLayer.new()
		layer.layer = 50
		layer.name = "Succes_" + ids[i]
		var panel := PanelContainer.new()
		var th := UiTheme.make(14)
		var sb: StyleBoxFlat = th.get_stylebox("panel", "PanelContainer").duplicate()
		sb.set_content_margin_all(8)
		sb.set_border_width_all(2)
		th.set_stylebox("panel", "PanelContainer", sb)
		panel.theme = th
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(row)
		row.add_child(Icon.new(str(ICONS.get(ids[i], "star")), true, 30.0))
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 0)
		box.add_child(UiTheme.label("Succès obtenu", 11, UiTheme.DIM))
		box.add_child(UiTheme.label(str(a["name"]), 15, UiTheme.GOLD))
		row.add_child(box)
		layer.add_child(panel)
		var vs := tree.root.get_visible_rect().size
		var w := 260.0
		panel.custom_minimum_size.x = w
		var y := 68.0 + i * 58.0 # Sous la barre du haut (32 px) et l'onglet « F1 : aide »
		panel.position = Vector2(vs.x - w - 10.0 + 40.0, y)
		panel.modulate.a = 0.0
		tree.root.add_child.call_deferred(layer)
		var tw := panel.create_tween()
		tw.tween_interval(0.5 * i + 0.01)
		tw.tween_property(panel, "modulate:a", 1.0, 0.3)
		tw.parallel().tween_property(panel, "position:x", vs.x - w - 10.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_interval(4.0)
		tw.tween_property(panel, "modulate:a", 0.0, 0.6)
		tw.tween_callback(layer.queue_free)


# ---------------------------------------------------------------- Page « Succès » (grille)

## Icône de chaque succès (dessinée par Icon).
const ICONS := {
	"premiere_victoire": "sword", "sans_perte_regiment": "shield", "sans_un_mort": "star", "carre": "square",
	"embuscade": "tree", "brigands": "shield", "siege": "castle", "eclair": "bolt", "un_contre_deux": "swords",
	"retraite": "flag", "elite": "chevron", "doyen": "chevron", "escarmouche_difficile": "skull",
	"tues_100": "skull", "tues_1000": "skull", "batailles_10": "swords", "batailles_50": "swords",
	"victoires_25": "laurel", "riche": "coin", "campagne_gagnee": "crown", "campagne_difficile": "crown",
	"campagne_rapide": "bolt", "dissous": "flag",
}
## Succès à compteur : [clé de Stats (ou « oldest » : batailles du doyen), objectif].
const GOALS := {
	"tues_100": ["enemies_killed", 100], "tues_1000": ["enemies_killed", 1000],
	"batailles_10": ["battles", 10], "batailles_50": ["battles", 50], "victoires_25": ["victories", 25],
	"riche": ["gold_earned", 5000], "doyen": ["oldest", 10],
	"campagne_gagnee": ["campaigns_won", 1], "dissous": ["campaigns_lost", 1],
}


## Progression d'un succès à compteur : [valeur, objectif] ; [] pour un succès d'un seul coup.
static func progress(id: String) -> Array:
	if not GOALS.has(id):
		return []
	var g: Array = GOALS[id]
	var v := 0
	if g[0] == "oldest":
		v = int((Stats.data["oldest"] as Dictionary).get("battles", 0))
	else:
		v = Stats.count(g[0])
	return [mini(v, int(g[1])), int(g[1])]


## Date d'obtention (« 18/11/2026 »), vide si le succès n'est pas obtenu.
static func unlocked_date(id: String) -> String:
	if not Stats.is_unlocked(id):
		return ""
	var unix := int(Stats.data["achievements"][id])
	if unix <= 0:
		return "date inconnue"
	var t := Time.get_datetime_dict_from_unix_time(unix + int(Time.get_time_zone_from_system()["bias"]) * 60)
	return "%02d/%02d/%d" % [t["day"], t["month"], t["year"]]


## Page « Succès » du menu principal : une grille (icône, nom, description, obtenu le…,
## progression des succès à compteur). Le menu ajoute le bouton Retour.
static func build_grid_page(box: VBoxContainer) -> void:
	Stats.ensure_loaded()
	var got := 0
	for a in LIST:
		if Stats.is_unlocked(a["id"]):
			got += 1
	box.add_child(UiTheme.label("Succès : %d / %d" % [got, LIST.size()], 24, UiTheme.GOLD))
	box.add_child(progress_bar(got, LIST.size(), Vector2(300, 8)))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(880, 400)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var grid := GridContainer.new()
	grid.name = "GrilleSucces"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	for a in LIST:
		grid.add_child(card(a))
	scroll.add_child(grid)
	box.add_child(scroll)


## Jauge de progression aux couleurs des menus (rainure sombre, remplissage doré).
static func progress_bar(value: int, max_value: int, min_size: Vector2) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.max_value = maxi(max_value, 1)
	pb.value = value
	pb.show_percentage = false
	pb.custom_minimum_size = min_size
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.04, 0.03)
	bg.border_color = Color(0.45, 0.35, 0.2)
	bg.set_border_width_all(1)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.85, 0.66, 0.28)
	pb.add_theme_stylebox_override("background", bg)
	pb.add_theme_stylebox_override("fill", fill)
	return pb


## Une case de la grille.
static func card(a: Dictionary) -> Control:
	var id: String = a["id"]
	var on := Stats.is_unlocked(id)
	var holder := PanelContainer.new()
	holder.name = "Succes_" + id
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.2, 0.15, 0.08, 0.9) if on else Color(0.09, 0.08, 0.07, 0.9)
	sb.border_color = UiTheme.GOLD if on else Color(0.3, 0.27, 0.22)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(6)
	holder.add_theme_stylebox_override("panel", sb)
	holder.custom_minimum_size = Vector2(286, 0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	holder.add_child(row)
	var icon := Icon.new(str(ICONS.get(id, "star")), on, 40.0)
	row.add_child(icon)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	col.add_child(UiTheme.label(str(a["name"]), 14, UiTheme.GOLD if on else UiTheme.TEXT))
	var desc := UiTheme.label(str(a["desc"]), 12, UiTheme.TEXT if on else UiTheme.DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size.x = 220
	col.add_child(desc)
	var prog := progress(id)
	if on:
		col.add_child(UiTheme.label("Obtenu le " + unlocked_date(id), 11, Color(0.6, 0.9, 0.5)))
	elif not prog.is_empty() and int(prog[1]) > 1:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		var pb := progress_bar(int(prog[0]), int(prog[1]), Vector2(120, 7))
		pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(pb)
		line.add_child(UiTheme.label("%d / %d" % [int(prog[0]), int(prog[1])], 11, UiTheme.DIM))
		col.add_child(line)
	else:
		col.add_child(UiTheme.label("À obtenir", 11, UiTheme.DIM))
	return holder


## Médaillon d'un succès : doré une fois obtenu, gris sinon, avec un symbole simple.
class Icon extends Control:
	var kind := "star"
	var on := false

	func _init(k: String, unlocked: bool, s := 40.0) -> void:
		kind = k
		on = unlocked
		custom_minimum_size = Vector2(s, s)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 1.0
		var ring := UiTheme.GOLD if on else Color(0.42, 0.4, 0.36)
		var fill := Color(0.35, 0.22, 0.08) if on else Color(0.16, 0.15, 0.14)
		var ink := Color(1, 0.92, 0.65) if on else Color(0.5, 0.48, 0.44)
		draw_circle(c, r, ring)
		draw_circle(c, r - 2.5, fill)
		Achievements.draw_glyph(self, kind, c, r * 0.62, ink)


## Symbole d'un succès, centré en c, de rayon s (partagé par la grille et la notification).
static func draw_glyph(ci: CanvasItem, kind: String, c: Vector2, s: float, ink: Color) -> void:
	var w := maxf(s * 0.16, 1.5)
	match kind:
		"sword":
			ci.draw_line(c + Vector2(-s * 0.7, s * 0.7), c + Vector2(s * 0.7, -s * 0.7), ink, w * 1.3)
			ci.draw_line(c + Vector2(-s * 0.55, s * 0.1), c + Vector2(-s * 0.1, s * 0.55), ink, w)
		"swords":
			ci.draw_line(c + Vector2(-s * 0.7, s * 0.7), c + Vector2(s * 0.7, -s * 0.7), ink, w * 1.2)
			ci.draw_line(c + Vector2(s * 0.7, s * 0.7), c + Vector2(-s * 0.7, -s * 0.7), ink, w * 1.2)
		"shield", "square":
			var pts := PackedVector2Array([c + Vector2(-s * 0.7, -s * 0.75), c + Vector2(s * 0.7, -s * 0.75),
				c + Vector2(s * 0.7, s * 0.05), c + Vector2(0, s * 0.85), c + Vector2(-s * 0.7, s * 0.05)])
			if kind == "square":
				pts = PackedVector2Array([c + Vector2(-s * 0.65, -s * 0.65), c + Vector2(s * 0.65, -s * 0.65),
					c + Vector2(s * 0.65, s * 0.65), c + Vector2(-s * 0.65, s * 0.65)])
			ci.draw_colored_polygon(pts, ink)
		"star":
			var pts := PackedVector2Array()
			for i in 10:
				var rr := s * (0.95 if i % 2 == 0 else 0.42)
				pts.append(c + Vector2.from_angle(-PI * 0.5 + i * PI / 5.0) * rr)
			ci.draw_colored_polygon(pts, ink)
		"tree":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s * 0.9), c + Vector2(s * 0.65, s * 0.4), c + Vector2(-s * 0.65, s * 0.4)]), ink)
			ci.draw_line(c + Vector2(0, s * 0.4), c + Vector2(0, s * 0.9), ink, w * 1.4)
		"castle":
			ci.draw_rect(Rect2(c + Vector2(-s * 0.75, -s * 0.2), Vector2(s * 1.5, s * 0.95)), ink)
			for k in 3:
				ci.draw_rect(Rect2(c + Vector2(-s * 0.75 + k * s * 0.6, -s * 0.55), Vector2(s * 0.3, s * 0.4)), ink)
		"bolt":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(s * 0.2, -s * 0.95), c + Vector2(-s * 0.5, s * 0.1),
				c + Vector2(-s * 0.02, s * 0.1), c + Vector2(-s * 0.2, s * 0.95), c + Vector2(s * 0.5, -s * 0.1), c + Vector2(s * 0.02, -s * 0.1)]), ink)
		"flag":
			ci.draw_line(c + Vector2(-s * 0.55, -s * 0.85), c + Vector2(-s * 0.55, s * 0.9), ink, w * 1.2)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.5, -s * 0.85), c + Vector2(s * 0.75, -s * 0.5), c + Vector2(-s * 0.5, -s * 0.1)]), ink)
		"chevron":
			for k in 2:
				var y := -s * 0.35 + k * s * 0.6
				ci.draw_polyline(PackedVector2Array([c + Vector2(-s * 0.7, y + s * 0.35), c + Vector2(0, y - s * 0.2), c + Vector2(s * 0.7, y + s * 0.35)]), ink, w * 1.3)
		"skull":
			ci.draw_circle(c + Vector2(0, -s * 0.15), s * 0.62, ink)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.35, s * 0.3), Vector2(s * 0.7, s * 0.45)), ink)
			var hole := Color(0.1, 0.07, 0.04)
			ci.draw_circle(c + Vector2(-s * 0.25, -s * 0.15), s * 0.16, hole)
			ci.draw_circle(c + Vector2(s * 0.25, -s * 0.15), s * 0.16, hole)
		"laurel":
			for side in [-1.0, 1.0]:
				for k in 4:
					var a := PI * (0.55 + 0.17 * k)
					var p := c + Vector2(cos(a) * side, sin(a) - 0.2) * s * 0.75
					ci.draw_circle(p, s * 0.17, ink)
		"coin":
			ci.draw_circle(c, s * 0.8, ink)
			ci.draw_arc(c, s * 0.55, 0, TAU, 20, Color(0.35, 0.22, 0.08, 0.8), w)
		"crown":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.8, s * 0.55), c + Vector2(-s * 0.8, -s * 0.5),
				c + Vector2(-s * 0.4, 0), c + Vector2(0, -s * 0.75), c + Vector2(s * 0.4, 0), c + Vector2(s * 0.8, -s * 0.5), c + Vector2(s * 0.8, s * 0.55)]), ink)
		_:
			ci.draw_circle(c, s * 0.5, ink)
