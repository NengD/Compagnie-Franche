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


## Notification discrète en haut à droite, posée sur la racine (survit aux changements de scène).
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
		panel.theme = UiTheme.make(14)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var box := VBoxContainer.new()
		box.add_child(UiTheme.label("Succès : %s" % a["name"], 15, UiTheme.GOLD))
		box.add_child(UiTheme.label(str(a["desc"]), 12, UiTheme.DIM))
		panel.add_child(box)
		layer.add_child(panel)
		var vs := tree.root.get_visible_rect().size
		panel.position = Vector2(vs.x - 340.0, 16.0 + i * 64.0)
		panel.modulate.a = 0.0
		tree.root.add_child.call_deferred(layer)
		var tw := panel.create_tween()
		tw.tween_property(panel, "modulate:a", 1.0, 0.3).set_delay(0.5 * i)
		tw.tween_interval(4.0)
		tw.tween_property(panel, "modulate:a", 0.0, 0.6)
		tw.tween_callback(layer.queue_free)
