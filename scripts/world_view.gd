class_name WorldView
extends RefCounted
## Affichage du monde vivant (world_sim.gd) sur la carte de campagne : armées, sièges, saison et
## météo, guerres, nouvelles, rencontre d'une armée (bataille ou fuite) et « camper un jour ».
## map : le nœud de campaign_map.gd (state, notice, add_label, add_button, add_section, refresh_ui).
## Les fonctions draw_* sont appelées depuis map._draw (elles dessinent sur la carte).

const DIM := Color(0.75, 0.72, 0.65)
const GOLD := Color(1, 0.84, 0.4)
const WARN := Color(1, 0.5, 0.4)
const WOOD := Color(0.48, 0.32, 0.17)
const ARMY_PICK := 16.0 ## Rayon de survol d'une armée
const MAP_SIZE := MapData.SIZE


# ---------------------------------------------------------------- Panneau

## Rencontre d'une armée hostile : le joueur choisit entre la bataille et la fuite.
static func build_encounter(map: Node) -> void:
	var state: CampaignState = map.state
	var w := state.world
	if not w.has_encounter():
		return
	var a := w.encounter_army()
	map.add_section("Une armée barre la route !")
	if a == null:
		map.add_label("L'armée s'est éloignée.", 12, DIM)
		map.add_button("Reprendre la route", WorldView.clear_encounter.bind(map))
		return
	map.add_label("%s (%s) vous attend sur la route de %s." % [CampaignState.cap_first(a.display_name()), CampaignState.plural(a.force, "homme", "hommes"), WorldSim.town_name(int(w.encounter["town"]))], 13, WARN)
	map.add_label("Combattre : pas de prime, mais le butin ; la disperser fâche %s (%+d) et plaît à ses ennemis (%+d). Fuir : un jour de détour et %d %% de l'or abandonné avec les bagages." % [WorldSim.short(a.faction), -WorldSim.REP_ARMY, WorldSim.REP_ARMY, int(WorldSim.FLEE_GOLD * 100)], 12, DIM)
	map.add_button("Livrer bataille", WorldView.fight.bind(map), not state.is_destroyed())
	map.add_button("Fuir", WorldView.flee.bind(map))


## Section « Le pays » : saison, météo, guerres, sièges et nouvelles du monde.
static func build_world(map: Node) -> void:
	var state: CampaignState = map.state
	var w := state.world
	map.add_section("Le pays")
	map.add_label(w.calendar_text(state.day), 13, Color(1, 0.9, 0.7))
	if not state.challenges.is_empty():
		map.add_label("Défis : %s" % Challenges.names(state.challenges), 12, WARN)
	var notes: Array[String] = []
	if state.world.season(state.day) == WorldSim.WINTER:
		notes.append("Hiver : marches plus lentes (x%.1f), le froid emporte des hommes en route." % WorldSim.MARCH_FACTOR[WorldSim.WINTER])
	if w.raining:
		notes.append("Une bataille livrée aujourd'hui se fera sous la pluie.")
	if not notes.is_empty():
		map.add_label(" ".join(notes), 12, DIM)
	map.add_label("Guerres : %s" % w.wars_text(), 12, WARN if not w.wars.is_empty() else DIM)
	for t in CampaignState.TOWNS.size():
		var s := state.town_siege(t)
		if not s.is_empty():
			map.add_label("%s est assiégée par %s (%s, %s de siège ; garnison %d)." % [WorldSim.town_name(t), WorldSim.short(int(s["faction"])), CampaignState.plural(int(s["men"]), "homme", "hommes"), CampaignState.plural(int(s["days"]), "jour", "jours"), int(s["garrison"])], 12, WARN)
	if not w.news.is_empty():
		map.add_label("Nouvelles du monde", 13, GOLD)
		for i in mini(5, w.news.size()):
			map.add_label(w.news[i], 11, Color(0.72, 0.69, 0.62))


static func fight(map: Node) -> void:
	var state: CampaignState = map.state
	map.notice = state.world.fight(state)
	GameAudio.feedback(map.notice == "")
	if map.notice == "" and state.in_battle():
		map.ambushed = true
		state.save()
		if map.auto_launch:
			map.get_tree().change_scene_to_file("res://scenes/main.tscn")
	map.refresh_ui()


static func flee(map: Node) -> void:
	var state: CampaignState = map.state
	map.notice = state.world.flee(state)
	GameAudio.ui("click")
	state.save()
	map.refresh_ui()
	if state.is_over():
		map.show_end()


static func clear_encounter(map: Node) -> void:
	var state: CampaignState = map.state
	state.world.encounter = {}
	state.save()
	map.refresh_ui()


## Un jour passe d'un coup sans marcher (la solde est due). La carte en temps réel n'en a plus
## besoin (le temps s'écoule tout seul) ; gardé pour les outils et les tests.
static func camp(map: Node) -> void:
	var state: CampaignState = map.state
	state.pass_day()
	state.add_log("Jour %d : la compagnie campe à %s." % [state.day, WorldSim.town_name(state.location)])
	state.check_ruin()
	map.notice = "Un jour au camp. %s." % CampaignState.cap_first(state.world.calendar_text(state.day))
	GameAudio.ui("click")
	state.save()
	map.refresh_ui()
	if state.is_over():
		map.show_end()


# ---------------------------------------------------------------- Carte

## Armée sous la souris (null sinon).
static func army_at(state: CampaignState, p: Vector2) -> WorldArmy:
	for a in state.world.armies:
		if army_spot(a).distance_to(p) < ARMY_PICK:
			return a
	return null


## Où dessiner une armée : sur sa route, ou sous les murs de la ville qu'elle assiège.
static func army_spot(a: WorldArmy) -> Vector2:
	if a.mode == "siege":
		return a.pos + Vector2(-40, -2) # À gauche des murs, au-dessus du nom
	if a.town_here() >= 0:
		return a.pos + Vector2(26, 16)
	return a.pos


## Sièges et armées (après les villes, avant la compagnie).
static func draw_world(map: Node2D) -> void:
	var state: CampaignState = map.state
	var t_ms := Time.get_ticks_msec() / 1000.0
	for t in CampaignState.TOWNS.size():
		if state.town_besieged(t):
			var p := WorldSim.town_pos(t)
			# Anneau rouge pointillé et fumée des incendies
			for k in 12:
				var a0 := TAU * k / 12.0 + t_ms * 0.3
				map.draw_arc(p, 30.0, a0, a0 + 0.3, 4, Color(0.85, 0.15, 0.1), 2.0)
			for k in 3:
				var s := fposmod(t_ms * 6.0 + k * 7.0, 20.0)
				map.draw_rect(Rect2(p + Vector2(-8 + k * 8, -18 - s), Vector2(4, 4)), Color(0.25, 0.22, 0.2, 0.7 * (1.0 - s / 20.0)))
			map.draw_rect(Rect2(p + Vector2(-6, -12), Vector2(3, 3)), Color(1, 0.5, 0.1))
			map.draw_rect(Rect2(p + Vector2(4, -10), Vector2(3, 3)), Color(1, 0.7, 0.2))
	for a in state.world.armies:
		draw_army(map, state, a)


static func draw_army(map: Node2D, state: CampaignState, a: WorldArmy) -> void:
	var p := army_spot(a).round()
	var col: Color = CampaignState.FACTIONS[a.faction]["color"]
	var hostile := state.world.hostile_to_player(state, a)
	if hostile:
		map.draw_arc(p + Vector2(0, -3), 17.0, 0, TAU, 24, Color(0.9, 0.15, 0.1, 0.9), 1.5)
	# Figurines (MapIcons) : cavaliers et piquiers, d'autant plus nombreux que l'armée est grande
	var horse := clampi(ceili(a.force / 120.0), 1, 3)
	var foot := clampi(ceili(a.force / 90.0), 1, 4)
	var face := 1.0
	var step := 0
	if map.has_method("face_of"):
		face = map.face_of(a)
		step = map.step_of(a) if a.mode != "siege" else 0
	map.draw_set_transform(p, 0.0, Vector2(face, 1.0))
	MapIcons.army(map, horse, foot, col, step)
	map.draw_set_transform(Vector2.ZERO)
	var font: Font = map.font
	var label := str(a.force)
	map.draw_string(font, p + Vector2(-13, 15), label, HORIZONTAL_ALIGNMENT_CENTER, 26, 10, Color(0, 0, 0, 0.85))
	map.draw_string(font, p + Vector2(-14, 14), label, HORIZONTAL_ALIGNMENT_CENTER, 26, 10, Color(1, 0.6, 0.5) if hostile else Color(1, 0.95, 0.85))


## Cartouche du calendrier et des guerres, en haut à droite de la carte.
static func draw_calendar(map: Node2D) -> void:
	var state: CampaignState = map.state
	var w := state.world
	var font: Font = map.font
	var lines: Array[String] = []
	for k in w.wars:
		var ab: PackedStringArray = str(k).split("-")
		lines.append("Guerre : %s contre %s" % [WorldSim.short(int(ab[0])), WorldSim.short(int(ab[1]))])
	if lines.is_empty():
		lines.append("En paix")
	var size := Vector2(250, 30 + lines.size() * 15)
	var at := Vector2(MAP_SIZE.x - size.x - 12, 12)
	map.draw_rect(Rect2(at, size), Color(0.12, 0.08, 0.05, 0.8))
	map.draw_rect(Rect2(at, size), Color(0.6, 0.47, 0.25), false, 1.0)
	map.draw_string(font, at + Vector2(10, 18), w.calendar_text(state.day), HORIZONTAL_ALIGNMENT_LEFT, size.x - 20, 13, GOLD)
	for i in lines.size():
		map.draw_string(font, at + Vector2(10, 36 + i * 15), lines[i], HORIZONTAL_ALIGNMENT_LEFT, size.x - 20, 11, Color(1, 0.6, 0.5) if not w.wars.is_empty() else Color(0.92, 0.88, 0.78))


## Infobulle d'une armée survolée.
static func draw_army_tooltip(map: Node2D, a: WorldArmy) -> void:
	var state: CampaignState = map.state
	var font: Font = map.font
	var lines: Array[String] = [CampaignState.cap_first(a.display_name()), CampaignState.plural(a.force, "homme", "hommes") + ", " + a.doing()]
	if state.world.hostile_to_player(state, a):
		lines.append("Hostile : elle attaquera la compagnie qui croise sa route")
	var wd := 0.0
	for s in lines:
		wd = maxf(wd, font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x)
	var size := Vector2(wd + 16, lines.size() * 16 + 10)
	var at := army_spot(a) + Vector2(18, -size.y * 0.5)
	at.x = minf(at.x, MAP_SIZE.x - size.x - 6)
	at.y = clampf(at.y, 6, MAP_SIZE.y - size.y - 6)
	map.draw_rect(Rect2(at, size), Color(0.1, 0.07, 0.05, 0.92))
	map.draw_rect(Rect2(at, size), Color(0.6, 0.47, 0.25), false, 1.0)
	for k in lines.size():
		map.draw_string(font, at + Vector2(8, 18 + k * 16), lines[k], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, GOLD if k == 0 else Color(0.92, 0.88, 0.78))
